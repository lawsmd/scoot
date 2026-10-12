--------------------------------------------------------------------------------
-- forever/actionbars/microbags.lua
-- The micro menu and the bag bar: their settings, the frames that hold the
-- twins (micro.lua, bagbar.lua), the two styles' layouts, the Edit Mode
-- anchors and the Dynamic Layouts adapters. Neither is a cluster member:
-- each stands on an anchor of its own, as Blizzard's two systems do.
--
-- Two styles:
--   * forever: the replica. The micro menu and the bag bar are two anchors,
--     each in the action bar frame art Forever draws around them, laid out
--     by Blizzard's rules and their Edit Mode settings (Orientation, Order or
--     Direction, Size, Bag Slot Padding).
--   * combined: one anchor, no frame art. The micro buttons, then every bag
--     slot drawn as a micro button's rectangle, in one row or column, the
--     micro menu's Orientation, Order and Size deciding the whole.
--
-- The twins are secure buttons, so every holder is implicitly protected:
-- the layout, a style switch and a position wait for regen in a fight.
--------------------------------------------------------------------------------

local _, addon = ...

local ActionBars = addon.ActionBars
local DB = addon.DB

local MicroBags = {}
ActionBars.MicroBags = MicroBags

local PATH = "actionBars.microBags."

-- The Edit Mode and Dynamic Layouts keys, one per anchor.
MicroBags.KEYS = { micro = "microMenu", bags = "bagBar", combined = "microBags" }
-- The Clusters page's section, which Configure opens.
MicroBags.SECTION_KEY = "microBags"

MicroBags.STYLE_VALUES = { forever = "Forever", combined = "Camelot (Combined)" }
MicroBags.STYLE_ORDER = { "forever", "combined" }
MicroBags.ORIENTATION_VALUES = { horizontal = "Horizontal", vertical = "Vertical" }
MicroBags.ORIENTATION_ORDER = { "horizontal", "vertical" }
MicroBags.ORDER_VALUES = { default = "Default", reverse = "Reverse" }
MicroBags.ORDER_ORDER = { "default", "reverse" }
-- Blizzard's own ranges for the two systems' sliders.
MicroBags.RANGES = {
    microSize = { min = 70, max = 200, step = 5 },
    bagsSize = { min = 75, max = 200, step = 5 },
    padding = { min = 2, max = 10, step = 1 },
}

local SLOT_KEYS = { "backpack", "bag1", "bag2", "bag3", "bag4", "reagent", "keyring" }

local defaults = {
    [PATH .. "style"] = "forever",
    [PATH .. "micro.orientation"] = "horizontal",
    [PATH .. "micro.order"] = "default",
    [PATH .. "micro.size"] = 100,
    [PATH .. "bags.orientation"] = "horizontal",
    [PATH .. "bags.direction"] = "left",
    [PATH .. "bags.size"] = 100,
    [PATH .. "bags.padding"] = 2,
    [PATH .. "slots.backpack.freeSlots"] = true,
}
for _, key in ipairs(SLOT_KEYS) do
    defaults[PATH .. "slots." .. key .. ".shown"] = true
end
DB.RegisterDefaults(defaults)

-- The gap between the micro buttons and the bags in the combined style, in
-- the micro menu's units, and Forever's frame art around each bar
-- (its Camelot MainMenuBarMicroMenu.xml and MainMenuBarBagButtons.xml).
local COMBINED_GAP = 6
local FRAME_ATLAS = "UI-HUD-ActionBar-Frame"
local MICRO_BACKGROUND_ATLAS = "UI-HUD-ActionBar-IconFrame-Background"
-- The default anchors: the bottom right corner, the micro menu to the bag
-- bar's left, as retail stands them; Camelot's main cluster holds the
-- bottom center where Forever's own preset puts the micro menu.
local EDGE = 10

--------------------------------------------------------------------------------
-- Settings
--------------------------------------------------------------------------------

function MicroBags.Get(field)
    return DB.Get(PATH .. field)
end

--- Write a setting and lay the bars out again.
function MicroBags.Set(field, value)
    DB.Set(PATH .. field, value)
    if field == "bags.orientation" then
        -- Blizzard resets the direction with the orientation.
        DB.Set(PATH .. "bags.direction", value == "vertical" and "up" or "left")
    end
    MicroBags.Apply()
end

function MicroBags.Style()
    return MicroBags.Get("style") == "combined" and "combined" or "forever"
end

function MicroBags.SlotShown(key)
    return MicroBags.Get("slots." .. key .. ".shown") ~= false
end

--- The direction choices the bag bar's orientation allows.
function MicroBags.DirectionChoices(vertical)
    if vertical then
        return { up = "Up", down = "Down" }, { "up", "down" }
    end
    return { left = "Left", right = "Right" }, { "left", "right" }
end

--------------------------------------------------------------------------------
-- Frames
--------------------------------------------------------------------------------

local holders = {}  -- micro, bags, combined
local strips = {}   -- micro, bags
local built = false
local dividers = {}
MicroBags.Holders = holders

local function Holder(name, label)
    local f = CreateFrame("Frame", name, UIParent)
    f:SetSize(1, 1)
    f:SetFrameStrata("MEDIUM")
    f:SetFrameLevel(50)
    f.editModeName = label
    return f
end

-- Forever's art around a bar: the action bar frame, and under the micro
-- menu the icon frame background.
local function AddFrameArt(holder, inset, background)
    local border = holder:CreateTexture(nil, "BACKGROUND", nil, -3)
    border:SetAtlas(FRAME_ATLAS)
    border:SetPoint("TOPLEFT", -inset.left, inset.top)
    border:SetPoint("BOTTOMRIGHT", inset.right, -inset.bottom)
    holder.BorderArt = border
    if background then
        local bg = holder:CreateTexture(nil, "BACKGROUND", nil, -4)
        bg:SetAtlas(MICRO_BACKGROUND_ATLAS)
        bg:SetPoint("TOPLEFT", border, "TOPLEFT", -13, 0)
        bg:SetPoint("BOTTOMRIGHT", border, "BOTTOMRIGHT", 14, 4)
        holder.BackgroundArt = bg
    end
end

local function Divider(index, vertical)
    local key = (vertical and "v" or "h") .. index
    local d = dividers[key]
    if not d then
        d = CreateFrame("Frame", nil, strips.bags, vertical and "VerticalDividerTemplate" or "HorizontalDividerTemplate")
        dividers[key] = d
    end
    return d
end

--------------------------------------------------------------------------------
-- Layout
--------------------------------------------------------------------------------

-- GridLayoutFrame's single line: each button after the last, Blizzard's
-- negative padding overlapping the art's clear edges.
local function LayoutMicro(vertical, reverse)
    local Micro = MicroBags.Micro
    local strip = strips.micro
    local visible = Micro.Visible()
    local shownSet = {}
    for _, btn in ipairs(visible) do shownSet[btn] = true end
    for _, btn in ipairs(Micro.Buttons) do btn:SetShown(shownSet[btn] == true) end

    local w, h, pad = Micro.WIDTH, Micro.HEIGHT, Micro.PADDING
    local n = #visible
    local width = vertical and w or math.max(1, n * w + (n - 1) * pad)
    local height = vertical and math.max(1, n * h + (n - 1) * pad) or h
    strip:SetSize(width, height)
    for i, btn in ipairs(visible) do
        local step = reverse and (n - i) or (i - 1)
        btn:ClearAllPoints()
        if vertical then
            btn:SetPoint("TOPLEFT", strip, "TOPLEFT", 0, -step * (h + pad))
        else
            btn:SetPoint("TOPLEFT", strip, "TOPLEFT", step * (w + pad), 0)
        end
    end
end

-- BagsBarMixin:Layout: the backpack at the bar's anchor end, each shown slot
-- after the one before it toward the direction, and in Forever's look a
-- divider between neighbours.
local function LayoutBags(vertical, direction, padding, look)
    local Bags = MicroBags.Bags
    local strip = strips.bags
    Bags.ApplyLook(look, vertical)
    local visible = Bags.Visible()
    local shownSet = {}
    for _, btn in ipairs(visible) do shownSet[btn] = true end
    for _, btn in ipairs(Bags.Buttons) do btn:SetShown(shownSet[btn] == true) end

    local point, relativePoint, dx, dy
    if not vertical then
        if direction == "right" then
            point, relativePoint, dx, dy = "LEFT", "RIGHT", padding, 0
        else
            point, relativePoint, dx, dy = "RIGHT", "LEFT", -padding, 0
        end
    else
        if direction == "down" then
            point, relativePoint, dx, dy = "TOP", "BOTTOM", 0, -padding
        else
            point, relativePoint, dx, dy = "BOTTOM", "TOP", 0, padding
        end
    end

    local long, short = 0, 0
    for i, btn in ipairs(visible) do
        local along = vertical and btn:GetHeight() or btn:GetWidth()
        local across = vertical and btn:GetWidth() or btn:GetHeight()
        long = long + along + (i > 1 and padding or 0)
        short = math.max(short, across)
        btn:ClearAllPoints()
        if i == 1 then
            btn:SetPoint(point, strip, point)
        else
            btn:SetPoint(point, visible[i - 1], relativePoint, dx, dy)
        end
    end
    if vertical then
        strip:SetSize(math.max(1, short), math.max(1, long))
    else
        strip:SetSize(math.max(1, long), math.max(1, short))
    end

    for _, d in pairs(dividers) do d:Hide() end
    if look == "forever" then
        for i = 2, #visible do
            local btn = visible[i]
            local d = Divider(i, vertical)
            d:ClearAllPoints()
            if not vertical then
                d:SetPoint("TOP", btn, "TOP")
                d:SetPoint("BOTTOM", btn, "BOTTOM")
                if direction == "right" then
                    d:SetPoint("RIGHT", btn, "LEFT", 5, 0)
                else
                    d:SetPoint("LEFT", btn, "RIGHT", -5, 0)
                end
            else
                d:SetPoint("LEFT", btn, "LEFT")
                d:SetPoint("RIGHT", btn, "RIGHT")
                if direction == "down" then
                    d:SetPoint("BOTTOM", btn, "TOP", 0, -5)
                else
                    d:SetPoint("TOP", btn, "BOTTOM", 0, 5)
                end
            end
            d:Show()
        end
    end
end

-- A holder sized around its strip at the strip's scale; the strip's scale is
-- the Size setting, so the holder's own stays 1 and a stored position never
-- moves with a size change.
local function Fit(holder, strip, scale)
    strip:SetScale(scale)
    holder:SetSize(math.max(1, strip:GetWidth() * scale), math.max(1, strip:GetHeight() * scale))
end

local defaultRecords = {
    micro = { point = "BOTTOMRIGHT", x = 0, y = EDGE },
    bags = { point = "BOTTOMRIGHT", x = -EDGE, y = EDGE },
    combined = { point = "BOTTOMRIGHT", x = -EDGE, y = EDGE },
}
MicroBags.DEFAULTS = defaultRecords

local function Layout()
    local style = MicroBags.Style()
    local microVertical = MicroBags.Get("micro.orientation") == "vertical"
    local reverse = MicroBags.Get("micro.order") == "reverse"
    local microScale = (tonumber(MicroBags.Get("micro.size")) or 100) / 100

    if style == "combined" then
        LayoutMicro(microVertical, reverse)
        -- The bags run on from the micro buttons the same way, the backpack
        -- at the far end, so the row reads as Blizzard's micro menu and bag
        -- bar side by side.
        LayoutBags(microVertical, microVertical and "up" or "left", MicroBags.Micro.PADDING, "combined")
        local micro, bags, holder = strips.micro, strips.bags, holders.combined
        micro:SetParent(holder)
        bags:SetParent(holder)
        micro:SetScale(microScale)
        bags:SetScale(microScale)
        micro:ClearAllPoints()
        bags:ClearAllPoints()
        micro:SetPoint("TOPLEFT", holder, "TOPLEFT")
        if microVertical then
            bags:SetPoint("TOPLEFT", micro, "BOTTOMLEFT", 0, -COMBINED_GAP)
            holder:SetSize(math.max(micro:GetWidth(), bags:GetWidth()) * microScale,
                (micro:GetHeight() + COMBINED_GAP + bags:GetHeight()) * microScale)
        else
            bags:SetPoint("TOPLEFT", micro, "TOPRIGHT", COMBINED_GAP, 0)
            holder:SetSize((micro:GetWidth() + COMBINED_GAP + bags:GetWidth()) * microScale,
                math.max(micro:GetHeight(), bags:GetHeight()) * microScale)
        end
        holders.combined:Show()
        holders.micro:Hide()
        holders.bags:Hide()
    else
        LayoutMicro(microVertical, reverse)
        local bagsVertical = MicroBags.Get("bags.orientation") == "vertical"
        local direction = MicroBags.Get("bags.direction") or (bagsVertical and "up" or "left")
        local padding = tonumber(MicroBags.Get("bags.padding")) or 2
        LayoutBags(bagsVertical, direction, padding, "forever")
        strips.micro:SetParent(holders.micro)
        strips.bags:SetParent(holders.bags)
        for _, key in ipairs({ "micro", "bags" }) do
            strips[key]:ClearAllPoints()
            strips[key]:SetPoint("TOPLEFT", holders[key], "TOPLEFT")
        end
        Fit(holders.micro, strips.micro, microScale)
        Fit(holders.bags, strips.bags, (tonumber(MicroBags.Get("bags.size")) or 100) / 100)
        holders.micro:Show()
        holders.bags:Show()
        holders.combined:Hide()
    end

    -- The micro menu's default stands to the bag bar's left.
    defaultRecords.micro.x = -(EDGE + holders.bags:GetWidth() + EDGE)

    local EM = addon.EditMode
    if EM and EM.RestorePositionable then
        for _, key in ipairs({ "micro", "bags", "combined" }) do
            if holders[key]:IsShown() then EM.RestorePositionable(holders[key]) end
        end
    end
end

--- Lay everything out again, after a setting or a change in which Blizzard
--- buttons show. Waits for regen in a fight.
function MicroBags.Apply()
    if not built then return end
    addon.Events.RunOutOfCombat(Layout, "camelotActionBars.microBags.layout")
    if MicroBags.Bags then MicroBags.Bags.ApplyCount() end
    if ActionBars.Page and ActionBars.Page.Refresh then ActionBars.Page.Refresh() end
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
MicroBags.Store = store

local keyByHolder = setmetatable({}, { __mode = "k" })

local function ApplyPosition(frame, point, x, y, reason)
    if InCombatLockdown() then
        addon.Events.RunOutOfCombat(function()
            addon.EditMode.RestorePositionable(frame)
        end, "camelotActionBars.microBags.position." .. tostring(keyByHolder[frame]))
        return true
    end
    frame:ClearAllPoints()
    frame:SetPoint(point, UIParent, point, x, y)
    if reason == "restore" and MicroBags.Dynamic then
        MicroBags.Dynamic.Reassert(keyByHolder[frame])
    end
    return false
end

local function selector(label, values, order, field, rebuild)
    return { kind = "selector", label = label, values = values, order = order,
             get = function() return MicroBags.Get(field) end,
             set = function(v) MicroBags.Set(field, v) end, rebuild = rebuild }
end

local function slider(label, range, field)
    return { kind = "slider", label = label, min = range.min, max = range.max, step = range.step,
             precision = 0, get = function() return tonumber(MicroBags.Get(field)) end,
             set = function(v) MicroBags.Set(field, v) end }
end

local function MicroRows()
    return {
        selector("Orientation", MicroBags.ORIENTATION_VALUES, MicroBags.ORIENTATION_ORDER, "micro.orientation"),
        selector("Order", MicroBags.ORDER_VALUES, MicroBags.ORDER_ORDER, "micro.order"),
        slider("Size", MicroBags.RANGES.microSize, "micro.size"),
    }
end

local function BagRows()
    local vertical = MicroBags.Get("bags.orientation") == "vertical"
    local values, order = MicroBags.DirectionChoices(vertical)
    return {
        selector("Orientation", MicroBags.ORIENTATION_VALUES, MicroBags.ORIENTATION_ORDER, "bags.orientation", true),
        selector("Direction", values, order, "bags.direction"),
        slider("Size", MicroBags.RANGES.bagsSize, "bags.size"),
        slider("Bag Slot Padding", MicroBags.RANGES.padding, "bags.padding"),
    }
end

local MIRRORS = { micro = MicroRows, bags = BagRows, combined = MicroRows }
local LABELS = { micro = "Micro Menu", bags = "Bag Bar", combined = "Micro & Bag Bar" }
MicroBags.LABELS = LABELS

local function Register()
    if not (addon.EditMode and addon.EditMode.RegisterPositionable) then return end
    local NAV_KEY = ActionBars.EditMode.NAV_KEY
    for _, key in ipairs({ "micro", "bags", "combined" }) do
        local holder = holders[key]
        keyByHolder[holder] = key
        addon.EditMode.RegisterPositionable(holder, {
            key = MicroBags.KEYS[key],
            default = defaultRecords[key],
            restoreDefault = true,
            store = store,
            apply = ApplyPosition,
            brand = {
                navKey = NAV_KEY, componentId = NAV_KEY, sectionKey = MicroBags.SECTION_KEY,
                mirror = MIRRORS[key],
            },
        })
        if MicroBags.Dynamic then MicroBags.Dynamic.Register(key, holder) end
    end
end

--------------------------------------------------------------------------------
-- Dynamic Layouts
--------------------------------------------------------------------------------
-- One adapter per anchor, the protected tier, as a cluster's: the twins are
-- secure, so position and scale wait out a fight and opacity does not.

local Dynamic = {}
MicroBags.Dynamic = Dynamic
local dynamicRegistered = {}

function Dynamic.Register(key, holder)
    local DL = addon.DynamicLayouts
    if not (DL and DL.Register) then return end
    local id = MicroBags.KEYS[key]
    dynamicRegistered[key] = true
    DL.Register({
        id = id,
        label = LABELS[key],
        frame = holder,
        tier = "protected",
        channels = { "opacity", "scale", "position" },
        base = {
            opacity = function() return 1 end,
            scale = function() return 1 end,
            position = function()
                local layoutName = addon.EditMode.GetActiveLayoutName and addon.EditMode.GetActiveLayoutName()
                local stored = layoutName and store.get(id, layoutName)
                if stored and stored.point then return stored.point, stored.x or 0, stored.y or 0 end
                local d = defaultRecords[key]
                return d.point, d.x, d.y
            end,
        },
    })
end

function Dynamic.Reassert(key)
    local DL = addon.DynamicLayouts
    if key and dynamicRegistered[key] and DL and DL.Reassert then DL.Reassert(MicroBags.KEYS[key]) end
end

--------------------------------------------------------------------------------
-- Build
--------------------------------------------------------------------------------

--- Build the holders and the twins, once, out of combat, from ActionBars'
--- own build.
function MicroBags.Build()
    if built then return end
    holders.micro = Holder("CamelotMicroMenu", LABELS.micro)
    holders.bags = Holder("CamelotBagBar", LABELS.bags)
    holders.combined = Holder("CamelotMicroBags", LABELS.combined)
    AddFrameArt(holders.micro, { left = 8, right = 8, top = 8, bottom = 8 }, true)
    AddFrameArt(holders.bags, { left = 6, right = 5, top = 6, bottom = 5 }, false)

    strips.micro = CreateFrame("Frame", nil, holders.micro)
    strips.bags = CreateFrame("Frame", nil, holders.bags)
    strips.micro:SetSize(1, 1)
    strips.bags:SetSize(1, 1)

    MicroBags.Micro.Build(strips.micro)
    MicroBags.Bags.Build(strips.bags)
    built = true
    Layout()
    Register()
    -- The layout's restore found nothing registered yet; now each holder
    -- lands on its stored or default spot.
    for _, key in ipairs({ "micro", "bags", "combined" }) do
        addon.EditMode.RestorePositionable(holders[key])
    end

    -- Which Blizzard buttons show changes with the game rules and the
    -- keyring's arrival; a pass at each world entry catches both.
    addon.Events.On(ActionBars.OWNER .. ".microBags", "PLAYER_ENTERING_WORLD", MicroBags.Apply)
end

function MicroBags.IsBuilt()
    return built
end

--- The rows /camelot actionbars prints.
function MicroBags.Report(push)
    push("micro menu and bag bar: built %s, style %s", tostring(built), MicroBags.Style())
    if not built then return end
    for _, key in ipairs({ "micro", "bags", "combined" }) do
        local h = holders[key]
        local point, _, _, x, y = h:GetPoint(1)
        push("  %-8s %-18s shown %-5s %.0fx%.0f at %s %.1f %.1f protected %s", key, h:GetName(),
            tostring(h:IsShown()), h:GetWidth(), h:GetHeight(), tostring(point), x or 0, y or 0,
            tostring((h:IsProtected())))
    end
    push("  micro twins:")
    MicroBags.Micro.Report(push)
    push("  bag twins:")
    MicroBags.Bags.Report(push)
end
