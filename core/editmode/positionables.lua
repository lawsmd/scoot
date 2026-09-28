--------------------------------------------------------------------------------
-- positionables.lua
-- Scoot-owned frames in Edit Mode (refactor #30)
-- One registration for a frame LibEditMode can drag: AddFrame, the drop
-- callback that persists the resolved anchor per layout, the restore on every
-- layout switch, the branding, and one enter/exit dispatch. Each component
-- keeps its own storage behind a store adapter, so the seven stores keep the
-- shapes they have; only the code around them is shared.
--
-- RegisterPositionable(frame, {
--     key            = value | function(frame) -> key | nil   nil: skip save and restore
--     default        = { point, x, y }       a table; LibEditMode keeps it for Reset Position
--     store          = { get = function(key, layoutName) -> pos | nil,
--                        set = function(key, layoutName, point, x, y) }
--     apply          = function(frame, point, x, y, reason) -> handled
--                      optional; reason is "drop" or "restore"; the default is
--                      ClearAllPoints + SetPoint(point, x, y); returning true on
--                      "drop" skips the persist (a snapped Cast Bar Z bar)
--     restoreDefault = boolean               apply `default` when nothing is stored
--     positionEditable = function(frame) -> boolean
--                      optional; the dialog's X/Y position row renders only
--                      while this returns true (a snapped Cast Bar Z bar)
--     brand          = table                 Brand:Register(frame, brand) options
-- })
-- Returns the LibEditMode selection frame, nil without the library. A repeat
-- call for the same frame is a no-op that returns the existing selection.
--
-- Design notes (emcustomframes.md):
--   * The stored anchor is the one GetPoint(1) reports after the drop, never the
--     requested one: LibEditMode's normalizePosition picks the point per screen
--     quadrant, so storing the requested point drifts the frame on reload.
--   * LibEditMode applies nothing at AddFrame. A "layout" registration fires at
--     once when a layout is active, so the first registration restores every
--     entry through that, and later ones restore themselves.
--   * Every restore and every enter/exit handler runs under securecallfunction,
--     as the library runs its own callbacks: one throwing component never
--     stops the others.
--   * brand.mirror is composed here: every registration's dialog list starts
--     with the shared X/Y position row, then the component's own entries.
--------------------------------------------------------------------------------

local addonName, addon = ...

addon.EditMode = addon.EditMode or {}
local EM = addon.EditMode
local SS = addon.SecretSafe

-- Same resolution as Brand.GetLib (ui/v2/editmode/Registry.lua), so the hooks
-- and the registrations land on one library object.
local function GetLib()
    return addon._LEM or (LibStub and LibStub("LibEditMode", true))
end

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

-- Weak keys so a released frame never pins its entry; `order` keeps restores
-- and the debug dump deterministic (the Registry.lua pattern).
local registry = setmetatable({}, { __mode = "k" })
local order = {}

local listeners = {}          -- array of { owner, enter, exit }, first-registration order
local listenerByOwner = {}
local hooked = {}             -- event name -> true once registered with the library

-- The Dynamic Layouts view of Edit Mode (core/dynamiclayouts/view.lua). While
-- it holds, a drop on a frame with an adapter writes the frame's dynamic
-- record in place of its position, the X/Y row reads the live center, and
-- the dialog lists the dynamic rows in place of the component's own. Inert
-- on a host without the engine.
local dynamicView = false

local function dynamicIdFor(frame)
    local DL = addon.DynamicLayouts
    if not (dynamicView and DL and DL.IdForFrame) then return nil end
    return DL.IdForFrame(frame)
end

--------------------------------------------------------------------------------
-- Positions
--------------------------------------------------------------------------------

local function resolveKey(entry, frame)
    local key = entry.key
    if type(key) == "function" then
        return key(frame)
    end
    return key
end

local function defaultApply(frame, point, x, y)
    frame:ClearAllPoints()
    frame:SetPoint(point, x, y)
end

local function applyPosition(entry, frame, point, x, y, reason)
    local apply = entry.apply or defaultApply
    return apply(frame, point, x, y, reason)
end

local function restore(entry, frame, layoutName)
    if not layoutName then return end
    local key = resolveKey(entry, frame)
    if key == nil then return end
    local pos = entry.store.get(key, layoutName)
    if pos and pos.point then
        applyPosition(entry, frame, pos.point, pos.x or 0, pos.y or 0, "restore")
    elseif entry.restoreDefault then
        local d = entry.default
        applyPosition(entry, frame, d.point, d.x, d.y, "restore")
    end
end

-- Called by the library on drag-stop, nudge, and Reset Position, always with a
-- point (both TriggerCallback paths compute one). Apply first, then persist
-- what the frame resolved to.
local function onDrop(frame, layoutName, point, x, y)
    local entry = registry[frame]
    if not entry then return end
    if not (point and x and y) then return end
    if applyPosition(entry, frame, point, x, y, "drop") then return end

    -- The dynamic view: the resolved anchor is the frame's dynamic position,
    -- in its own scale at the dynamic scale, which is the record's
    -- convention. The snap that follows puts the engine's hold on it.
    local dynamicId = dynamicIdFor(frame)
    if dynamicId then
        local store = addon.DynamicLayoutsStore
        local ok, dPoint, _, _, dx, dy = pcall(frame.GetPoint, frame, 1)
        dPoint = ok and SS.plainString(dPoint) or nil
        dx, dy = SS.safeNumber(dx), SS.safeNumber(dy)
        if store and dPoint and dx and dy then
            store.SetRecord(dynamicId, { point = dPoint, x = dx, y = dy })
            addon.DynamicLayouts.Refresh(dynamicId, "snap")
        end
        return
    end

    local key = resolveKey(entry, frame)
    if not layoutName or key == nil then return end
    local savedPoint, _, _, savedX, savedY = frame:GetPoint(1)
    if savedPoint then
        entry.store.set(key, layoutName, savedPoint, savedX, savedY)
    else
        entry.store.set(key, layoutName, point, x, y)
    end
end

local function onLayout(layoutName)
    for _, frame in ipairs(order) do
        local entry = registry[frame]
        if entry then
            securecallfunction(restore, entry, frame, layoutName)
        end
    end
end

--------------------------------------------------------------------------------
-- Position row
--------------------------------------------------------------------------------
-- The X/Y boxes on the branded dialog: the frame's center relative to the
-- screen center, in UI units, so (0, 0) is dead center. The resting readout
-- derives from the STORED record, so it echoes what was typed and what the
-- next login restores; live geometry is read only mid-drag. A typed pair becomes a NudgeFrame delta against the
-- live center, computed at commit: an absolute set, with no cached value to
-- drift.

-- Anchor points as rect fractions: LEFT 0 / CENTER 0.5 / RIGHT 1 across,
-- BOTTOM 0 / CENTER 0.5 / TOP 1 up. With them the conversion
--     centerX = x*s + (fx - 0.5) * (W - w*s)
-- is exact for every point, so the readout never depends on which anchor
-- normalizePosition picked on the last drop.
local ANCHOR_FRACTIONS = {
    TOPLEFT    = { 0, 1 },     TOP    = { 0.5, 1 },     TOPRIGHT    = { 1, 1 },
    LEFT       = { 0, 0.5 },   CENTER = { 0.5, 0.5 },   RIGHT       = { 1, 0.5 },
    BOTTOMLEFT = { 0, 0 },     BOTTOM = { 0.5, 0 },     BOTTOMRIGHT = { 1, 0 },
}

-- Geometry reads screened like describeLive below: a secret or a missing rect
-- comes back nil, never as an error.
local function frameScale(frame)
    local ok, s = pcall(frame.GetScale, frame)
    s = ok and SS.safeNumber(s) or nil
    return (s and s > 0) and s or nil
end

local function frameSize(frame)
    local ok, w, h = pcall(frame.GetSize, frame)
    if not ok then return nil end
    w, h = SS.safeNumber(w), SS.safeNumber(h)
    if not (w and h) then return nil end
    return w, h
end

--- Live center relative to the screen center, in UI units.
local function liveCenter(frame)
    local s = frameScale(frame)
    if not s then return nil end
    local ok, cx, cy = pcall(frame.GetCenter, frame)
    if not ok then return nil end
    cx, cy = SS.safeNumber(cx), SS.safeNumber(cy)
    if not (cx and cy) then return nil end
    local ux, uy = UIParent:GetCenter()
    return cx * s - ux, cy * s - uy
end

--- Stored record -> center pair. Offsets are in the frame's own scale (what
--- GetPoint reports and SetPoint takes); sizes convert through it. Today's
--- positionables all run at scale 1; s keeps the math right if one ever
--- does not. `scale` overrides the frame's own, for a caller computing the
--- center the frame will have at another scale (the Dynamic Layouts tween).
local function centerFromRecord(frame, point, x, y, scale)
    local f = ANCHOR_FRACTIONS[point]
    if not f then return nil end
    local w, h = frameSize(frame)
    local s = (scale and scale > 0) and scale or frameScale(frame)
    if not (w and s) then return nil end
    local W, H = UIParent:GetSize()
    return x * s + (f[1] - 0.5) * (W - w * s),
           y * s + (f[2] - 0.5) * (H - h * s)
end

--- What the boxes display. Stored first; live while dragging, and for a frame
--- with nothing stored yet (a Note before its first drag, a ScootAuras shell
--- whose key resolves nil).
local function positionCurrent(entry, frame)
    if dynamicView then return liveCenter(frame) end
    if not entry.dragging then
        local lib = GetLib()
        local layoutName = lib and lib:GetActiveLayoutName()
        local key = resolveKey(entry, frame)
        if key ~= nil and layoutName then
            local pos = entry.store.get(key, layoutName)
            if pos and pos.point then
                local cx, cy = centerFromRecord(frame, pos.point, pos.x or 0, pos.y or 0)
                if cx then return cx, cy end
            end
        end
    end
    return liveCenter(frame)
end

--- Commit a typed pair. Clamped to the screen rect so a mistyped -9999 cannot
--- lose the frame; the clamp is skipped on an axis where the frame outsizes
--- the screen. The delta is against the LIVE center because NudgeFrame
--- re-normalizes from live geometry before adding it: delta in, absolute
--- position out. Combat: the library refuses the move silently, so refuse
--- here too (the row also disables its boxes).
local function commitPosition(entry, frame, pos)
    if type(pos) ~= "table" or InCombatLockdown() then return end
    local lib = GetLib()
    if not lib then return end
    local tx, ty = tonumber(pos.x), tonumber(pos.y)
    if not (tx and ty) then return end

    local w, h = frameSize(frame)
    local s = frameScale(frame)
    if not (w and s) then return end
    local W, H = UIParent:GetSize()
    -- Bounds round inward so a clamped whole-unit entry stays whole.
    local rx, ry = math.floor((W - w * s) / 2), math.floor((H - h * s) / 2)
    if rx > 0 then tx = math.max(-rx, math.min(rx, tx)) end
    if ry > 0 then ty = math.max(-ry, math.min(ry, ty)) end

    local cx, cy = liveCenter(frame)
    if not cx then return end
    -- NudgeFrame is a local addition to the vendored library; a foreign copy
    -- that won the LibStub race may lack it.
    if not lib.NudgeFrame then return end
    lib:NudgeFrame(frame, (tx - cx) / s, (ty - cy) / s)
end

local function positionEditable(entry, frame)
    if type(entry.positionEditable) ~= "function" then return true end
    local ok, allowed = pcall(entry.positionEditable, frame)
    return (ok and allowed) and true or false
end

--- The dialog's rows while the dynamic view holds: the position row over the
--- live center, then Opacity and Scale over the frame's dynamic record, each
--- only for a channel the adapter carries. A slider write snaps, so the
--- frame follows the thumb. A scale write re-expresses a stored position at
--- the new scale, since offsets are in the frame's own scale and the anchor
--- point would otherwise drift.
local function dynamicRows(entry, frame)
    local DL = addon.DynamicLayouts
    local store = addon.DynamicLayoutsStore
    local id = dynamicIdFor(frame)
    local st = id and DL.Get(id)
    if not (st and store and not st.inert) then return {} end
    local channels = st.channelSet or {}

    local function rec()
        return store.GetRecord(id) or {}
    end
    local function write(fields)
        store.SetRecord(id, fields)
        DL.Refresh(id, "snap")
    end
    local function percent(v)
        return math.floor(v * 100 + 0.5)
    end

    local specs = {}
    if channels.position and positionEditable(entry, frame) then
        specs[#specs + 1] = {
            kind  = "position",
            label = "Position",
            get   = function() return liveCenter(frame) end,
            set   = function(p) commitPosition(entry, frame, p) end,
        }
    end
    if channels.opacity then
        specs[#specs + 1] = {
            kind = "slider", label = "Opacity", min = 0, max = 100, step = 1, precision = 0,
            get = function()
                local v = rec().opacity
                return percent(type(v) == "number" and v or 1)
            end,
            set = function(v) write({ opacity = v / 100 }) end,
        }
    end
    if channels.scale then
        specs[#specs + 1] = {
            kind = "slider", label = "Scale", min = 25, max = 200, step = 1, precision = 0,
            get = function()
                local v = rec().scale
                if type(v) ~= "number" then v = DL.BaseValue(id, "scale") or 1 end
                return percent(v)
            end,
            set = function(v)
                local r = rec()
                local new = v / 100
                local old = type(r.scale) == "number" and r.scale or DL.BaseValue(id, "scale") or 1
                local fields = { scale = new }
                if r.point and type(r.x) == "number" and type(r.y) == "number" and old > 0 and new > 0 then
                    fields.x, fields.y = r.x * old / new, r.y * old / new
                end
                write(fields)
            end,
        }
    end
    return specs
end

--- The provider Brand:Register gets: the shared position row first, then the
--- component's own mirror entries. The component provider runs under pcall so
--- one bad list cannot take the row down with it.
local function composeMirror(entry, componentMirror)
    return function(frame)
        if dynamicView then return dynamicRows(entry, frame) end
        local specs
        if type(componentMirror) == "function" then
            local ok, list = pcall(componentMirror, frame)
            if ok and type(list) == "table" then specs = list end
        end
        specs = specs or {}

        if positionEditable(entry, frame) then
            table.insert(specs, 1, {
                kind  = "position",
                label = "Position",
                get   = function() return positionCurrent(entry, frame) end,
                set   = function(p) commitPosition(entry, frame, p) end,
            })
        end
        return specs
    end
end

--------------------------------------------------------------------------------
-- Enter and exit
--------------------------------------------------------------------------------

local function dispatch(which)
    for _, listener in ipairs(listeners) do
        local fn = listener[which]
        if fn then
            securecallfunction(fn)
        end
    end
end

local function ensureHook(lib, event)
    if hooked[event] then return end
    hooked[event] = true
    if event == "layout" then
        lib:RegisterCallback("layout", onLayout)
    else
        lib:RegisterCallback(event, function() dispatch(event) end)
    end
end

--------------------------------------------------------------------------------
-- API
--------------------------------------------------------------------------------

function EM.RegisterPositionable(frame, opts)
    if not frame or type(opts) ~= "table" then return nil end
    local existing = registry[frame]
    if existing then return existing.selection end
    local lib = GetLib()
    if not lib then return nil end

    local entry = {
        key = opts.key,
        default = opts.default,
        store = opts.store,
        apply = opts.apply,
        restoreDefault = opts.restoreDefault and true or false,
        positionEditable = opts.positionEditable,
        brand = opts.brand,
    }
    -- Before AddFrame: the first AddFrame of a session creates the dialog and
    -- runs onEditModeChanged, which fires every layout callback from inside it.
    registry[frame] = entry
    order[#order + 1] = frame

    lib:AddFrame(frame, onDrop, entry.default, nil)
    entry.selection = lib.frameSelections and lib.frameSelections[frame] or nil

    -- The library's drag scripts live on the selection overlay; hooking the
    -- instance marks the window where the position row reads live geometry.
    if entry.selection and entry.selection.HookScript then
        entry.selection:HookScript("OnDragStart", function() entry.dragging = true end)
        entry.selection:HookScript("OnDragStop", function() entry.dragging = nil end)
    end

    -- Registry.lua loads after every consumer; look it up here, never at load.
    local Brand = EM.Brand
    if Brand and entry.brand then
        entry.brand.mirror = composeMirror(entry, entry.brand.mirror)
        Brand:Register(frame, entry.brand)
    end

    if not hooked.layout then
        -- Fires at once when a layout is active, restoring every entry.
        ensureHook(lib, "layout")
    else
        local layoutName = lib:GetActiveLayoutName()
        if layoutName then
            securecallfunction(restore, entry, frame, layoutName)
        end
    end

    -- A frame registered while Edit Mode is open missed the enter pass and
    -- would be undraggable until Edit Mode bounces.
    if lib:IsInEditMode() and entry.selection then
        pcall(entry.selection.ShowHighlighted, entry.selection)
    end

    return entry.selection
end

--- Re-applies the stored position (or the default, when the frame opted in).
--- layoutName defaults to the active layout; nil layout or unknown frame: no-op.
function EM.RestorePositionable(frame, layoutName)
    local entry = frame and registry[frame]
    if not entry then return end
    if layoutName == nil then
        local lib = GetLib()
        layoutName = lib and lib:GetActiveLayoutName()
    end
    restore(entry, frame, layoutName)
end

--- Enter and exit handlers for one component. Re-registering an owner replaces
--- its handlers in place, so a second init pass never doubles them.
function EM.OnEditMode(owner, handlers)
    if not owner or type(handlers) ~= "table" then return end
    local lib = GetLib()
    if not lib then return end
    local listener = listenerByOwner[owner]
    if not listener then
        listener = { owner = owner }
        listenerByOwner[owner] = listener
        listeners[#listeners + 1] = listener
    end
    listener.enter = handlers.enter
    listener.exit = handlers.exit
    ensureHook(lib, "enter")
    ensureHook(lib, "exit")
end

--- LibEditMode's own flag: set before its enter callbacks run and cleared
--- before its exit callbacks run. Not IsEditModeActiveOrOpening, which adds
--- the one-second transition windows the enter/exit bodies must not see.
function EM.IsEditing()
    local lib = GetLib()
    return (lib and lib:IsInEditMode()) or false
end

function EM.GetActiveLayoutName()
    local lib = GetLib()
    return lib and lib:GetActiveLayoutName() or nil
end

--- The center-pair conversion above, for a caller tweening a frame between
--- two stored records: (point, x, y) at `scale` -> center offset from the
--- screen center in UI units, or nil when the frame's rect cannot be read.
EM.CenterFromRecord = centerFromRecord

--------------------------------------------------------------------------------
-- The dynamic view
--------------------------------------------------------------------------------

--- Set by the view's state (core/dynamiclayouts/view.lua) on entry and exit.
function EM.SetDynamicView(on)
    dynamicView = on and true or false
end

function EM.IsDynamicView()
    return dynamicView
end

--- Every registered frame with its selection box, in registration order:
--- fn(frame, selection).
function EM.ForEachPositionable(fn)
    for _, frame in ipairs(order) do
        local entry = registry[frame]
        if entry then fn(frame, entry.selection) end
    end
end

--- The dialog's "Match Regular Layout" in the dynamic view: the frame's
--- record keeps its participation and loses every value, and the frame
--- tweens home.
function EM.MatchBase(frame)
    local id = dynamicIdFor(frame)
    local store = addon.DynamicLayoutsStore
    if not (id and store) then return end
    store.SetRecord(id, { opacity = false, scale = false, point = false, x = false, y = false, offscreen = false })
    addon.DynamicLayouts.Refresh(id, "tween")
end

--------------------------------------------------------------------------------
-- Introspection: /scoot debug positionables, or /run ScootAddon.EditMode.DumpPositionables()
--------------------------------------------------------------------------------

local function describePos(pos)
    if type(pos) ~= "table" then return "-" end
    return ("%s %s,%s"):format(tostring(pos.point), tostring(pos.x), tostring(pos.y))
end

-- The live anchor of a snapped Cast Bar Z bar answers secret; read it screened.
local function describeLive(frame)
    local ok, point, _, _, x, y = pcall(frame.GetPoint, frame, 1)
    if not ok then return "?" end
    point = SS.plainString(point)
    if not point then return "secret" end
    return ("%s %s,%s"):format(point, tostring(SS.safeNumber(x)), tostring(SS.safeNumber(y)))
end

function EM.DumpPositionables()
    local rows = {}
    local layoutName = EM.GetActiveLayoutName()
    rows[#rows + 1] = "layout: " .. tostring(layoutName)
    local count = 0
    for _, frame in ipairs(order) do
        local entry = registry[frame]
        if entry then
            count = count + 1
            local name = "?"
            if frame.GetDebugName then
                local ok, n = pcall(frame.GetDebugName, frame)
                if ok then name = SS.plainString(n) or "?" end
            end
            local key = resolveKey(entry, frame)
            local stored = nil
            if key ~= nil and layoutName then
                stored = entry.store.get(key, layoutName)
            end
            rows[#rows + 1] = ("%s [%s] key=%s stored=%s default=%s%s live=%s"):format(
                name,
                tostring(entry.brand and entry.brand.navKey),
                tostring(key),
                describePos(stored),
                describePos(entry.default),
                entry.restoreDefault and " (restoreDefault)" or "",
                describeLive(frame))
        end
    end
    rows[#rows + 1] = ("positionables: %d, listeners: %d"):format(count, #listeners)
    if addon.DebugShowWindow then
        addon.DebugShowWindow(("Positionables (%d)"):format(count), rows)
    end
    return rows
end

addon:RegisterDebugCommand({
    name = "positionables",
    help = (addon.Brand or "Scoot") .. " frames in Edit Mode: key, stored and default position per layout, live anchor",
    handler = function() EM.DumpPositionables() end,
})
