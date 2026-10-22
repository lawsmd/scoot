--------------------------------------------------------------------------------
-- forever/actionbars/stance.lua
-- The stance bar: its settings, the holder and its secure spell buttons, the
-- state drawn from the shapeshift reads, the grid layout, the Edit Mode
-- anchor and the Dynamic Layouts adapter. Not a cluster member: it stands
-- on an anchor of its own, as the micro menu and the bag bar do
-- (microbags.lua).
--
-- The buttons are SmallActionButtonTemplate plus SecureActionButtonTemplate,
-- never Blizzard's StanceButtonTemplate: its OnClick calls the protected
-- CastShapeshiftForm, and its Quick Keybind OnShow and OnHide write
-- EventRegistry. Each button casts its form's spell by id. The template's
-- HotKey stays hidden: Blizzard's stance buttons never draw their keybind.
--
-- The holder carries a Face. The Visibility settings (visibility.lua) write
-- the Face and the Dynamic Layouts adapter writes the holder, so the two
-- never share a frame. The buttons are secure, so the holder is implicitly
-- protected: the layout and a position wait for regen in a fight. The state
-- (icon, checked, swipe) is unprotected and redraws at once.
--------------------------------------------------------------------------------

local _, addon = ...

local ActionBars = addon.ActionBars
local DB = addon.DB

local Stance = {}
ActionBars.Stance = Stance

local PATH = "actionBars.stance."
local OWNER = ActionBars.OWNER .. ".stance"
local LAYOUT_KEY = "camelotActionBars.stance.layout"

-- The Edit Mode, Dynamic Layouts and Visibility key.
Stance.KEY = "stanceBar"
Stance.NAV_KEY = "actionBarStance"
Stance.LABEL = "Stance Bar"

Stance.ORIENTATION_VALUES = { horizontal = "Horizontal", vertical = "Vertical" }
Stance.ORIENTATION_ORDER = { "horizontal", "vertical" }
-- The directions the forms flow in, from the opposite corner of the grid:
-- along a row first on a horizontal bar, down or up a column first on a
-- vertical one. Blizzard's horizontal bar flows right and up.
Stance.FLOW_X_VALUES = { right = "Left to Right", left = "Right to Left" }
Stance.FLOW_X_ORDER = { "right", "left" }
Stance.FLOW_Y_VALUES = { up = "Bottom to Top", down = "Top to Bottom" }
Stance.FLOW_Y_ORDER = { "up", "down" }
-- Blizzard's own ranges for the stance bar's Edit Mode settings.
Stance.RANGES = {
    lines = { min = 1, max = 4, step = 1 },
    iconSize = { min = 50, max = 200, step = 10 },
    iconPadding = { min = 2, max = 10, step = 1 },
}

local NUM_BUTTONS = 10
local BUTTON_SIZE = 30

DB.RegisterDefaults({
    [PATH .. "orientation"] = "horizontal",
    [PATH .. "lines"] = 1,
    [PATH .. "iconSize"] = 100,
    [PATH .. "iconPadding"] = 2,
    [PATH .. "flowX"] = "right",
    [PATH .. "flowY"] = "up",
})

-- Forever's indent for the stance and pet bars and its spacer between the
-- bottom bars (the client's Camelot preset constants), from cluster 1.
local INDENT_X = 30
local SPACER_Y = 4

--------------------------------------------------------------------------------
-- Settings
--------------------------------------------------------------------------------

function Stance.Get(field)
    return DB.Get(PATH .. field)
end

--- Write a setting and lay the bar out again.
function Stance.Set(field, value)
    DB.Set(PATH .. field, value)
    Stance.Apply()
end

local function number(field, fallback)
    return tonumber(Stance.Get(field)) or fallback
end

--------------------------------------------------------------------------------
-- Frames
--------------------------------------------------------------------------------

local holder, strip
local buttons = {}
local built = false
local editMode = false
Stance.Buttons = buttons

--- The frame the Visibility settings write for the token, or nil.
function Stance.Face(token)
    if token ~= Stance.KEY or not holder then return nil end
    return holder.Face
end

--- Whether the bar draws: built, and its holder shown.
function Stance.IsActive(token)
    return token == Stance.KEY and built and holder:IsShown()
end

-- The button mixin: the keys StanceButtonMixin holds that the pingable
-- mixin and the tooltip read.
local ButtonMixin = {}

function ButtonMixin:HasAction()
    return GetShapeshiftFormInfo(self.index) ~= nil
end

function ButtonMixin:GetActionButtonInfo()
    local texture, isActive, isCastable, spellID = GetShapeshiftFormInfo(self.index)
    return { id = spellID, texture = texture, isActive = isActive, isCastable = isCastable }
end

local function OnEnter(self)
    BaseActionButtonMixin.BaseActionButtonMixin_OnEnter(self)
    if GetCVarBool("UberTooltips") then
        GameTooltip_SetDefaultAnchor(GameTooltip, self)
    else
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    end
    GameTooltip:SetShapeshift(self:GetID())
    self.UpdateTooltip = OnEnter
end

local function OnLeave(self)
    BaseActionButtonMixin.BaseActionButtonMixin_OnLeave(self)
    GameTooltip_Hide()
end

local function CreateButton(i)
    local b = CreateFrame("CheckButton", "CamelotStanceButton" .. i, strip,
        "SmallActionButtonTemplate, SecureActionButtonTemplate", i)
    Mixin(b, ButtonMixin)
    b.index = i
    b.cooldown:SetSwipeColor(0, 0, 0)
    b.HotKey:SetText("")
    b.HotKey:Hide()
    b:RegisterForClicks("AnyUp")
    b:SetAttribute("type", "spell")
    -- As the action buttons: a mouse click fires on the release, so a press
    -- casts nothing.
    b:SetAttribute("useOnKeyDown", false)
    b:SetScript("OnEnter", OnEnter)
    b:SetScript("OnLeave", OnLeave)
    return b
end

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

-- A flag that reads secret is not a plain answer; the caller leaves the
-- button as it was.
local function plain(v)
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end

-- The swipe from a duration object, as the action buttons draw theirs; the
-- NeverSecret isActive flag decides whether it shows.
local function UpdateCooldown(b, spellID)
    local cooldown = b.cooldown
    local info = spellID and C_Spell.GetSpellCooldown and C_Spell.GetSpellCooldown(spellID)
    if info and plain(info.isActive) == true and C_Spell.GetSpellCooldownDuration then
        cooldown:SetCooldownFromDurationObject(C_Spell.GetSpellCooldownDuration(spellID))
    else
        cooldown:Clear()
    end
end

local function UpdateButton(b)
    local texture, isActive, isCastable, spellID = GetShapeshiftFormInfo(b.index)
    b.icon:SetTexture(texture)
    if not texture then
        b:SetChecked(false)
        b.cooldown:Clear()
        return
    end
    local active = plain(isActive)
    if active ~= nil then b:SetChecked(active and true or false) end
    local castable = plain(isCastable)
    if castable ~= nil then
        local c = castable and 1 or 0.4
        b.icon:SetVertexColor(c, c, c)
    end
    UpdateCooldown(b, spellID)
end

--- Redraw every button's icon, checked state, tint and swipe.
function Stance.UpdateState()
    if not built then return end
    for _, b in ipairs(buttons) do UpdateButton(b) end
end

--------------------------------------------------------------------------------
-- Layout
--------------------------------------------------------------------------------

local defaultRecord = { point = "BOTTOM", x = 0, y = 140 }
Stance.DEFAULT = defaultRecord

-- Over cluster 1 by Forever's spacer, indented from its left edge, in the
-- container's base scale; the record stays the same table, since the Edit
-- Mode library and the adapter hold it.
local function UpdateDefault()
    local Clusters = ActionBars.Clusters
    local container = Clusters and Clusters.Container and Clusters.Container(Clusters.PRIMARY)
    if not (container and container:IsShown()) then return end
    local left, top, scale = container:GetLeft(), container:GetTop(), container:GetScale()
    if not (left and top and scale and scale > 0) then return end
    defaultRecord.point = "BOTTOMLEFT"
    defaultRecord.x = left * scale + INDENT_X
    defaultRecord.y = top * scale + SPACER_Y
end

-- The grid always has room for every slot, in Edit Mode and out of it, so
-- the forms sit in the same place whether the empty slots show or not.
-- A horizontal bar fills a row, then starts the next; a vertical bar fills a
-- column, then starts the next. flowX and flowY pick the corner the first
-- form takes and the directions the rest follow; the empty slots Edit Mode
-- shows continue the flow after the forms.
local function LayoutGrid(shownCount, vertical, lines, padding, flowLeft, flowDown)
    local perLine = math.max(1, math.ceil(NUM_BUTTONS / lines))
    local usedLines = math.max(1, math.ceil(NUM_BUTTONS / perLine))
    local cols = vertical and usedLines or perLine
    local rows = vertical and perLine or usedLines
    local step = BUTTON_SIZE + padding
    for i, b in ipairs(buttons) do
        local shown = i <= shownCount
        b:SetShown(shown)
        if shown then
            local along = (i - 1) % perLine
            local across = math.floor((i - 1) / perLine)
            local col = vertical and across or along
            local row = vertical and along or across -- counted from the bottom
            if flowLeft then col = cols - 1 - col end
            if flowDown then row = rows - 1 - row end
            b:ClearAllPoints()
            b:SetPoint("BOTTOMLEFT", strip, "BOTTOMLEFT", col * step, row * step)
        end
    end
    local long = perLine * step - padding
    local short = usedLines * step - padding
    if vertical then
        strip:SetSize(math.max(1, short), math.max(1, long))
    else
        strip:SetSize(math.max(1, long), math.max(1, short))
    end
end

local function Layout()
    local forms = math.min(GetNumShapeshiftForms() or 0, NUM_BUTTONS)
    local count = editMode and NUM_BUTTONS or forms
    for _, b in ipairs(buttons) do
        local _, _, _, spellID = GetShapeshiftFormInfo(b.index)
        b:SetAttribute("spell", b.index <= forms and spellID or nil)
        if b.UpdatePingAttributes then b:UpdatePingAttributes() end
    end

    local vertical = Stance.Get("orientation") == "vertical"
    local lines = math.floor(number("lines", 1))
    local padding = number("iconPadding", 2)
    LayoutGrid(count, vertical, lines, padding, Stance.Get("flowX") == "left", Stance.Get("flowY") == "down")

    local scale = number("iconSize", 100) / 100
    strip:SetScale(scale)
    holder:SetSize(math.max(1, strip:GetWidth() * scale), math.max(1, strip:GetHeight() * scale))
    holder:SetShown(count > 0)

    UpdateDefault()
    if holder:IsShown() and addon.EditMode and addon.EditMode.RestorePositionable then
        addon.EditMode.RestorePositionable(holder)
    end
    ActionBars.Visibility.Apply(Stance.KEY)
    Stance.UpdateState()
end

--- Lay the bar out again, after a setting, a form change, a cluster rebuild
--- or a profile switch. Waits for regen in a fight.
function Stance.Apply()
    if not built then return end
    addon.Events.RunOutOfCombat(Layout, LAYOUT_KEY)
    if Stance.Page and Stance.Page.Refresh then Stance.Page.Refresh() end
end

--- Every slot shows while Edit Mode is open, so the box has a size on a
--- class with no forms.
function Stance.OnEditMode(on)
    editMode = on and true or false
    Stance.Apply()
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
Stance.Store = store

local Dynamic = {}
Stance.Dynamic = Dynamic

local function ApplyPosition(frame, point, x, y, reason)
    if InCombatLockdown() then
        addon.Events.RunOutOfCombat(function()
            addon.EditMode.RestorePositionable(frame)
        end, "camelotActionBars.stance.position")
        return true
    end
    frame:ClearAllPoints()
    frame:SetPoint(point, UIParent, point, x, y)
    if reason == "restore" then Dynamic.Reassert() end
    return false
end

local function Rows()
    local function selector(label, values, order, field)
        return { kind = "selector", label = label, values = values, order = order,
                 get = function() return Stance.Get(field) end,
                 set = function(v) Stance.Set(field, v) end }
    end
    local function slider(label, range, field)
        return { kind = "slider", label = label, min = range.min, max = range.max, step = range.step,
                 precision = 0, get = function() return tonumber(Stance.Get(field)) end,
                 set = function(v) Stance.Set(field, v) end }
    end
    return {
        selector("Orientation", Stance.ORIENTATION_VALUES, Stance.ORIENTATION_ORDER, "orientation"),
        slider("Rows", Stance.RANGES.lines, "lines"),
        slider("Icon Size", Stance.RANGES.iconSize, "iconSize"),
        slider("Icon Padding", Stance.RANGES.iconPadding, "iconPadding"),
        selector("Horizontal Flow", Stance.FLOW_X_VALUES, Stance.FLOW_X_ORDER, "flowX"),
        selector("Vertical Flow", Stance.FLOW_Y_VALUES, Stance.FLOW_Y_ORDER, "flowY"),
    }
end

local function Register()
    if not (addon.EditMode and addon.EditMode.RegisterPositionable) then return end
    addon.EditMode.RegisterPositionable(holder, {
        key = Stance.KEY,
        default = defaultRecord,
        restoreDefault = true,
        store = store,
        apply = ApplyPosition,
        -- Wider than the default 340: the label band holds "Horizontal Flow".
        brand = { navKey = Stance.NAV_KEY, componentId = Stance.NAV_KEY, mirror = Rows, dialogWidth = 420 },
    })
    Dynamic.Register()
end

--------------------------------------------------------------------------------
-- Dynamic Layouts
--------------------------------------------------------------------------------
-- The protected tier, as the micro menu's: the buttons are secure, so
-- position and scale wait out a fight and opacity does not.

local dynamicRegistered = false

function Dynamic.Register()
    local DL = addon.DynamicLayouts
    if not (DL and DL.Register) then return end
    dynamicRegistered = true
    DL.Register({
        id = Stance.KEY,
        label = Stance.LABEL,
        group = "stanceBar",
        frame = holder,
        tier = "protected",
        channels = { "opacity", "scale", "position" },
        base = {
            opacity = function() return 1 end,
            scale = function() return 1 end,
            position = function()
                local layoutName = addon.EditMode.GetActiveLayoutName and addon.EditMode.GetActiveLayoutName()
                local stored = layoutName and store.get(Stance.KEY, layoutName)
                if stored and stored.point then return stored.point, stored.x or 0, stored.y or 0 end
                return defaultRecord.point, defaultRecord.x, defaultRecord.y
            end,
        },
    })
end

function Dynamic.Reassert()
    local DL = addon.DynamicLayouts
    if dynamicRegistered and DL and DL.Reassert then DL.Reassert(Stance.KEY) end
end

--------------------------------------------------------------------------------
-- Build
--------------------------------------------------------------------------------

local STATE_EVENTS = {
    "UPDATE_SHAPESHIFT_FORM", "UPDATE_SHAPESHIFT_USABLE", "UPDATE_SHAPESHIFT_COOLDOWN",
    "SPELL_UPDATE_COOLDOWN",
}

--- Build the holder and the buttons, once, out of combat, from ActionBars'
--- own build, after the clusters so the default reads cluster 1.
function Stance.Build()
    if built then return end
    holder = CreateFrame("Frame", "CamelotStanceBar", UIParent)
    holder:SetSize(1, 1)
    holder:SetFrameStrata("MEDIUM")
    holder:SetFrameLevel(60)
    holder.editModeName = Stance.LABEL
    holder.Face = CreateFrame("Frame", nil, holder)
    holder.Face:SetAllPoints(holder)
    strip = CreateFrame("Frame", nil, holder.Face)
    strip:SetPoint("TOPLEFT", holder, "TOPLEFT")
    strip:SetSize(1, 1)
    for i = 1, NUM_BUTTONS do buttons[i] = CreateButton(i) end
    built = true

    Layout()
    Register()
    -- The layout's restore found nothing registered yet.
    if holder:IsShown() then addon.EditMode.RestorePositionable(holder) end

    for _, event in ipairs(STATE_EVENTS) do
        addon.Events.On(OWNER, event, Stance.UpdateState)
    end
    -- The count of forms and their spell ids change here, and at world entry.
    addon.Events.On(OWNER, "UPDATE_SHAPESHIFT_FORMS", Stance.Apply)
    addon.Events.On(OWNER, "PLAYER_ENTERING_WORLD", Stance.Apply)
end

function Stance.IsBuilt()
    return built
end

-- After a profile switch the settings and the position come from the new
-- profile. Runs after the micro menu's step at 31.
addon.Profiles.RegisterApplyStep("camelotStance", function(_, ctx)
    if ctx.initial or ctx.resync or not built then return end
    Stance.Apply()
end, 32)

--- The rows /camelot actionbars prints.
function Stance.Report(push)
    push("stance bar: built %s, forms %d", tostring(built), GetNumShapeshiftForms() or 0)
    if not built then return end
    local point, _, _, x, y = holder:GetPoint(1)
    push("  %-18s shown %-5s %.0fx%.0f at %s %.1f %.1f protected %s, default %s %.1f %.1f",
        holder:GetName(), tostring(holder:IsShown()), holder:GetWidth(), holder:GetHeight(),
        tostring(point), x or 0, y or 0, tostring((holder:IsProtected())),
        defaultRecord.point, defaultRecord.x, defaultRecord.y)
    push("  %s", ActionBars.Visibility.Describe(Stance.KEY))
    for _, b in ipairs(buttons) do
        if b:IsShown() then
            push("  %-22s spell %-8s checked %s", b:GetName(), tostring(b:GetAttribute("spell")),
                tostring(b:GetChecked()))
        end
    end
end
