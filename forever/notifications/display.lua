--------------------------------------------------------------------------------
-- forever/notifications/display.lua
-- The notification anchor and its toasts (notifications.lua holds the
-- settings, the source registry and the painter contract).
--
-- A toast fades in while it rises to the anchor from behind the travel
-- direction, tells its painter it has arrived, waits out whatever the
-- painter animates, holds for the Hold Time, then fades. Live toasts are
-- kept newest first: the newest stands on the anchor and each older one
-- eases one place further along the direction. A push that names a live
-- toast's key updates that toast in place of stacking another.
--
-- The anchor is a fixed-size frame, so its stored Edit Mode point keeps its
-- center whatever the text size is. It shows only while a toast is live or
-- in Edit Mode, and one OnUpdate on it drives everything.
--
-- Every frame here is plain, so a toast shows in combat as out of it.
--------------------------------------------------------------------------------

local addonName, addon = ...

local Notifications = addon.Notifications
local DB = addon.DB

local OWNER = "CamelotNotifications"
local LAYOUT_KEY = "notifications"

-- Above screen center, clear of the overhead bars and their rising icons.
local DEFAULT_POSITION = { point = "CENTER", x = 0, y = 150 }
local ANCHOR_WIDTH, ANCHOR_HEIGHT = 220, 44
local HUD_LEVEL = 80

-- Seconds: the rise and fade in, the fade out, and how fast a fading toast
-- comes back when its key is pushed again.
local ENTER, EXIT, RECOVER = 0.8, 1.0, 0.2
-- The rise, in text heights.
local TRAVEL = 2
-- Between stacked toasts, and how fast a toast eases to its place.
local GAP, SLOT_RATE = 6, 10
local MAX_LIVE = 4

local VECTORS = {
    up = { 0, 1 }, down = { 0, -1 }, left = { -1, 0 }, right = { 1, 0 },
}

local anchor
local pools = {}
local live = {}
local preview = false
local vector = VECTORS.up

local function easeOut(p)
    local q = 1 - p
    return 1 - q * q * q
end

local function snap(value)
    if PixelUtil and PixelUtil.GetNearestPixelSize and anchor then
        return PixelUtil.GetNearestPixelSize(value, anchor:GetEffectiveScale())
    end
    return math.floor(value + 0.5)
end

--------------------------------------------------------------------------------
-- Toasts
--------------------------------------------------------------------------------

local function poolFor(source)
    local pool = pools[source.id]
    if pool then return pool end
    pool = addon.Pool.New(function()
        local frame = CreateFrame("Frame", nil, anchor)
        frame:SetSize(1, 1)
        frame:Hide()
        source.painter.build(frame)
        return frame
    end, function(frame)
        frame:Hide()
        frame:ClearAllPoints()
        frame:SetAlpha(1)
    end)
    pools[source.id] = pool
    return pool
end

-- Where each live toast belongs along the direction: the newest at 0, each
-- older one past the toast before it.
local function retarget()
    local horizontal = vector[1] ~= 0
    local offset, before = 0, nil
    for _, record in ipairs(live) do
        local size = horizontal and record.w or record.h
        if before then offset = offset + before / 2 + GAP + size / 2 end
        record.slotTarget = offset
        before = size
    end
end

local function position(record, rise)
    local along = record.slot + rise
    local x, y = vector[1] * along, vector[2] * along
    if rise == 0 and record.slot == record.slotTarget then
        x, y = snap(x), snap(y)
    end
    if x ~= record.x or y ~= record.y then
        record.x, record.y = x, y
        record.frame:ClearAllPoints()
        record.frame:SetPoint("CENTER", anchor, "CENTER", x, y)
    end
end

local function release(index)
    local record = table.remove(live, index)
    pools[record.source.id]:Release(record.frame)
end

local function releaseAll()
    for i = #live, 1, -1 do release(i) end
end

-- A frame from the source's pool, filled and sized. Shown before the painter
-- runs, since a string takes its font once it is shown with text.
local function fill(source, data)
    local frame = poolFor(source):Acquire()
    if not frame then return nil end
    frame:Show()
    local metrics = Notifications.Metrics()
    local w, h = source.painter.show(frame, data, metrics)
    w, h = math.max(1, tonumber(w) or 1), math.max(1, tonumber(h) or 1)
    frame:SetSize(w, h)
    return frame, w, h, metrics
end

local function update(record, data)
    local painter = record.source.painter
    local there = record.phase ~= "enter"
    local seconds = painter.update and painter.update(record.frame, data, there) or 0
    if there then
        record.phase = "settle"
        record.wait = tonumber(seconds) or 0
    end
    return true
end

--- Show a toast for a registered source, or hand the data to the live toast
--- that carries the same key. Notifications.Push is the public entry.
function Notifications.Show(source, data)
    if not anchor or preview then return false end
    if not source.painter then return false end

    if data.key ~= nil then
        for _, record in ipairs(live) do
            if record.source == source and record.key == data.key then
                return update(record, data)
            end
        end
    end

    vector = VECTORS[Notifications.Direction()]
    anchor:Show()
    local frame, w, h, metrics = fill(source, data)
    if not frame then
        if #live == 0 then anchor:Hide() end
        return false
    end
    frame:SetAlpha(0)

    local record = {
        frame = frame, source = source, key = data.key,
        phase = "enter", t = 0, alpha = 0,
        w = w, h = h, slot = 0, slotTarget = 0,
        travel = TRAVEL * metrics.size,
    }
    table.insert(live, 1, record)
    for i = MAX_LIVE + 1, #live do
        live[i].phase = "exit"
    end
    retarget()
    position(record, -record.travel)
    return true
end

--------------------------------------------------------------------------------
-- The driver
--------------------------------------------------------------------------------

local function onUpdate(_, elapsed)
    local faded = false
    for i = #live, 1, -1 do
        local record = live[i]
        local painter = record.source.painter
        local alpha, rise = record.alpha, 0

        if record.phase == "enter" then
            record.t = record.t + elapsed
            local p = math.min(1, record.t / ENTER)
            alpha = p
            rise = -(1 - easeOut(p)) * record.travel
            if p >= 1 then
                record.phase = "settle"
                record.wait = tonumber(painter.arrive and painter.arrive(record.frame)) or 0
            end
        elseif record.phase == "settle" then
            alpha = math.min(1, alpha + elapsed / RECOVER)
            record.wait = record.wait - elapsed
            if record.wait <= 0 then
                record.phase, record.t = "hold", 0
                record.holdFor = Notifications.Hold()
            end
        elseif record.phase == "hold" then
            alpha = math.min(1, alpha + elapsed / RECOVER)
            record.t = record.t + elapsed
            if record.t >= record.holdFor then record.phase = "exit" end
        elseif record.phase == "exit" then
            alpha = alpha - elapsed / EXIT
        end

        if record.phase == "exit" and alpha <= 0 then
            release(i)
            retarget()
        else
            if record.slot ~= record.slotTarget then
                local step = (record.slotTarget - record.slot) * math.min(1, elapsed * SLOT_RATE)
                record.slot = record.slot + step
                if math.abs(record.slotTarget - record.slot) < 0.25 then
                    record.slot = record.slotTarget
                end
            end
            position(record, rise)
            if alpha ~= record.alpha then
                record.alpha = alpha
                record.frame:SetAlpha(alpha)
                faded = true
            end
            if painter.tick then painter.tick(record.frame, elapsed) end
        end
    end

    -- A Deep Shadow copy is told when its string's frame fades.
    if faded and addon.FontPair and addon.FontPair.RefreshInheritedAlpha then
        addon.FontPair.RefreshInheritedAlpha()
    end
    if #live == 0 and not preview then anchor:Hide() end
end

--------------------------------------------------------------------------------
-- Preview, test, apply
--------------------------------------------------------------------------------
-- In Edit Mode the anchor holds one sample from the first enabled source, so
-- there is something to drag and the size shows. With every source off the
-- anchor stays hidden, and its Edit Mode box, a child of it, with it.

local function firstSampler()
    for _, source in ipairs(Notifications.Sources()) do
        if Notifications.IsEnabled(source) and source.painter and source.painter.sample then
            return source
        end
    end
    return nil
end

local function showPreview()
    preview = true
    releaseAll()
    local source = firstSampler()
    if not source then
        anchor:Hide()
        return
    end
    anchor:Show()
    local frame, w, h = fill(source, source.painter.sample())
    if not frame then return end
    frame:SetAlpha(1)
    local record = {
        frame = frame, source = source, phase = "preview", alpha = 1,
        w = w, h = h, slot = 0, slotTarget = 0,
    }
    live[1] = record
    position(record, 0)
    -- The sample ends on its new value.
    if source.painter.arrive then source.painter.arrive(frame) end
end

local function endPreview()
    preview = false
    releaseAll()
    anchor:Hide()
end

--- Play a sample from one source, or from every enabled source with no id.
function Notifications.ShowTest(id)
    if not anchor or preview then return false end
    local shown = false
    for _, source in ipairs(Notifications.Sources()) do
        if (id == nil or source.id == id) and Notifications.IsEnabled(source)
            and source.painter and source.painter.sample then
            if Notifications.Show(source, source.painter.sample()) then shown = true end
        end
    end
    return shown
end

--- After a settings write: the direction, and the preview's look. A live
--- toast keeps the look it was drawn with.
function Notifications.Apply()
    if not anchor then return end
    vector = VECTORS[Notifications.Direction()]
    if preview then
        showPreview()
    else
        retarget()
    end
end

--------------------------------------------------------------------------------
-- Edit Mode
--------------------------------------------------------------------------------

local store = {
    get = function(key, layoutName)
        local entry = DB.GetLayout(key)
        local positions = entry and entry.positions
        return positions and positions[layoutName] or nil
    end,
    set = function(key, layoutName, point, x, y)
        local entry = DB.GetLayout(key) or {}
        entry.positions = entry.positions or {}
        entry.positions[layoutName] = { point = point, x = x, y = y }
        DB.SetLayout(key, entry)
    end,
}

local function build()
    if anchor then return end
    anchor = CreateFrame("Frame", "CamelotNotifications", UIParent)
    anchor:SetSize(ANCHOR_WIDTH, ANCHOR_HEIGHT)
    anchor:SetPoint(DEFAULT_POSITION.point, DEFAULT_POSITION.x, DEFAULT_POSITION.y)
    addon.Strata.ApplyHUD(anchor, HUD_LEVEL)
    anchor:Hide()
    anchor:SetScript("OnUpdate", onUpdate)
    vector = VECTORS[Notifications.Direction()]
end

local registered = false
local function registerEditMode()
    if registered or not (addon.EditMode and addon.EditMode.RegisterPositionable) then return end
    registered = true
    anchor.editModeName = "Notifications"
    addon.EditMode.RegisterPositionable(anchor, {
        key = LAYOUT_KEY,
        default = DEFAULT_POSITION,
        restoreDefault = true,
        store = store,
        brand = { navKey = Notifications.NAV_KEY, componentId = Notifications.NAV_KEY },
    })
    addon.EditMode.OnEditMode(OWNER, { enter = showPreview, exit = endPreview })
    if addon.EditMode.IsEditing() then showPreview() end
end

--------------------------------------------------------------------------------
-- Dump
--------------------------------------------------------------------------------

function Notifications.Dump()
    local lines, push = addon.DebugLines()
    local metrics = Notifications.Metrics()
    push("Notifications: anchor %s, preview %s, live %d",
        anchor and (anchor:IsShown() and "shown" or "hidden") or "not built", tostring(preview), #live)
    push("  look: size %s, icon %s, style %s, face %s",
        tostring(metrics.size), tostring(metrics.iconSize), tostring(metrics.style), tostring(metrics.face))
    push("  direction %s, hold %s s", Notifications.Direction(), tostring(Notifications.Hold()))
    push("")
    push("Sources:")
    for _, source in ipairs(Notifications.Sources()) do
        push("  %s: %s (%s), %s, painter %s", source.id, source.label, source.where,
            Notifications.IsEnabled(source) and "on" or "off", source.painter and "set" or "none")
    end
    if #live > 0 then
        push("")
        push("Live, newest first:")
        for i, record in ipairs(live) do
            push("  %d  %s  key %s  %s  alpha %.2f  place %.1f of %.1f", i, record.source.id,
                tostring(record.key), record.phase, record.alpha, record.slot, record.slotTarget)
        end
    end
    addon.DebugShowWindow("Notifications", lines)
end

--------------------------------------------------------------------------------
-- Wiring
--------------------------------------------------------------------------------

addon.Events.OnWorldEntered(function()
    build()
    registerEditMode()
end)

-- After a profile switch the toasts of the old profile go, and the preview
-- reads the new one. A resync pass keeps the profile it had. The position is
-- per profile too: a login can restore it from the profile the database
-- opened on, before the switch to the layout's own, and no layout change
-- follows to restore it again.
addon.Profiles.RegisterApplyStep("camelotNotifications", function(_, ctx)
    if ctx.initial or ctx.resync or not anchor then return end
    if not preview then releaseAll() end
    Notifications.Apply()
    addon.EditMode.RestorePositionable(anchor)
end, 40)

addon:RegisterSlashCommand({
    name = "notifications",
    help = "show the notification sources, the shared look and the live toasts; 'test' plays a sample from each enabled source",
    handler = function(sub)
        if sub == "test" then
            Notifications.ShowTest()
            return
        end
        Notifications.Dump()
    end,
})
