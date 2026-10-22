--------------------------------------------------------------------------------
-- forever/actionbars/visibility.lua
-- The Visibility tab's settings on one action bar: when the bar shows, its
-- opacity in combat and with a target, and the mouseover reveal. The micro
-- menu, the bag bar and the two combined take the same settings, under their
-- Edit Mode keys as tokens (microbags.lua).
--
-- Everything here writes the bar frame, CamelotActionBar<n>, or a micro or
-- bag holder's Face. The Dynamic Layouts adapter writes the cluster container
-- the bar sits in, or the holder, so the two never share a frame: the
-- adapter's alpha multiplies over this file's, and a bar hidden here stays
-- hidden whatever the dynamic layout does. Out of
-- combat with no target the bar is at full opacity; that state belongs to the
-- dynamic layout, so there is no Out of Combat value.
--
-- The shown state is a visibility state driver, the secure manager's channel
-- that stays legal in combat. A driver registers out of combat only, since
-- registering resolves it at once. While Edit Mode is open every bar shows
-- at full opacity, Blizzard's rule for its own bars. A hidden bar keeps its
-- slot in its cluster: the combat modes flip in a fight, where nothing moves.
--
-- This file is the one owner of a bar's visibility driver. The vehicle,
-- override and pet battle clauses join VEHICLE_CLAUSES once each has been
-- seen to flip on the beta.
--
-- Nothing is stored for a new profile: a nil value is the stock behaviour.
--------------------------------------------------------------------------------

local _, addon = ...

local DB = addon.DB
local ActionBars = addon.ActionBars
local OWNER = ActionBars.OWNER

local Visibility = {}
ActionBars.Visibility = Visibility

-- The two states the bar's own opacity answers to; out of combat with no
-- target reads 100.
local KEYS = {
    combat = addon.Opacity.Keys.Bar.combat,
    target = addon.Opacity.Keys.Bar.target,
}
Visibility.OPACITY_KEYS = KEYS

Visibility.MODE_ORDER = { "always", "combat", "not_in_combat", "hidden" }
Visibility.MODE_LABELS = {
    always = "Always",
    combat = "In Combat",
    not_in_combat = "Not In Combat",
    hidden = "Hidden",
}

local VEHICLE_CLAUSES = ""

local DRIVERS = {
    combat = "[combat] show; hide",
    not_in_combat = "[combat] hide; show",
    hidden = "hide",
}

local editMode = false
local drivers = {} -- bar -> the driver string registered on it

--- The dotted path of a visibility setting: Visibility.Path("bar2", "visible").
function Visibility.Path(token, field)
    return "actionBars.visibility." .. token .. "." .. field
end

local function get(token, field)
    return DB.Get(Visibility.Path(token, field))
end

local function isBar(token)
    return ActionBars.Frames ~= nil and ActionBars.Frames[token] ~= nil
end

local function isStance(token)
    local Stance = ActionBars.Stance
    return Stance ~= nil and token == Stance.KEY
end

local function barOf(token)
    if isBar(token) then return ActionBars.Frames[token] end
    if isStance(token) then return ActionBars.Stance.Face(token) end
    local MicroBags = ActionBars.MicroBags
    return MicroBags and MicroBags.Face(token) or nil
end

-- Only a bar a cluster holds takes a driver; a parked one draws nowhere. A
-- micro or bag holder takes one while its style is in use, the stance bar
-- while it has forms to show.
local function placed(token)
    if isStance(token) then return ActionBars.Stance.IsActive(token) end
    if not isBar(token) then
        local MicroBags = ActionBars.MicroBags
        return MicroBags ~= nil and MicroBags.IsActive(token)
    end
    local Clusters = ActionBars.Clusters
    return Clusters and Clusters.Owner and Clusters.Owner(token) ~= nil
end

--- Every token the tab can apply to: the pool's bars, the micro and bag
--- holders, then the stance bar.
function Visibility.Tokens()
    local tokens = {}
    for _, token in ipairs(ActionBars.POOL_ORDER or {}) do tokens[#tokens + 1] = token end
    local MicroBags = ActionBars.MicroBags
    for _, key in ipairs(MicroBags and MicroBags.ORDER or {}) do tokens[#tokens + 1] = MicroBags.KEYS[key] end
    if ActionBars.Stance then tokens[#tokens + 1] = ActionBars.Stance.KEY end
    return tokens
end

function Visibility.Mode(token)
    local v = get(token, "visible")
    if DRIVERS[v] then return v end
    return "always"
end

--- The driver string for a bar, or nil when it always shows.
function Visibility.Driver(token)
    local rule = DRIVERS[Visibility.Mode(token)]
    if not rule then
        return VEHICLE_CLAUSES ~= "" and (VEHICLE_CLAUSES .. " show") or nil
    end
    return VEHICLE_CLAUSES .. rule
end

--- Whether the driver may be hiding the bar now; the layout measures such a
--- bar shown.
function Visibility.IsHiding(token)
    local bar = barOf(token)
    return bar ~= nil and drivers[bar] ~= nil and not bar:IsShown()
end

local function unregister(bar)
    if drivers[bar] then
        UnregisterStateDriver(bar, "visibility")
        drivers[bar] = nil
    end
end

local function applyShown(token)
    local bar = barOf(token)
    if not bar then return end
    local driver = (not editMode) and placed(token) and Visibility.Driver(token) or nil
    if driver == drivers[bar] then return end
    unregister(bar)
    if driver then
        RegisterStateDriver(bar, "visibility", driver)
        drivers[bar] = driver
    else
        bar:Show()
    end
end

function Visibility.ApplyShown(token)
    addon.Events.RunOutOfCombat(function() applyShown(token) end, OWNER .. ".visible." .. token)
end

function Visibility.Alpha(token)
    if editMode or not placed(token) or addon.HoverFade.IsOver(barOf(token)) then return 1 end
    local values = {
        [KEYS.combat] = get(token, KEYS.combat),
        [KEYS.target] = get(token, KEYS.target),
    }
    return (addon.Opacity.Resolve(values, KEYS))
end

function Visibility.ApplyAlpha(token)
    local bar = barOf(token)
    if bar then bar:SetAlpha(Visibility.Alpha(token)) end
end

function Visibility.ApplyHover(token)
    local bar = barOf(token)
    if not bar then return end
    if get(token, "mouseoverMode") and placed(token) then
        addon.HoverFade.Watch(bar, {
            frame = bar,
            onChange = function() Visibility.ApplyAlpha(token) end,
        })
    else
        addon.HoverFade.Unwatch(bar)
    end
end

--- Every part, for one bar: after a setting changes and after a layout.
function Visibility.Apply(token)
    if not barOf(token) then return end
    Visibility.ApplyHover(token)
    Visibility.ApplyAlpha(token)
    Visibility.ApplyShown(token)
end

function Visibility.ApplyAll()
    for _, token in ipairs(Visibility.Tokens()) do
        Visibility.Apply(token)
    end
end

--- The bar left every cluster: it shows plainly under the parking frame.
function Visibility.Release(frame)
    if not frame then return end
    addon.HoverFade.Unwatch(frame)
    addon.Events.RunOutOfCombat(function()
        unregister(frame)
        frame:Show()
        frame:SetAlpha(1)
    end, OWNER .. ".release." .. (frame:GetName() or tostring(frame)))
end

function Visibility.OnEditMode(on)
    editMode = on and true or false
    Visibility.ApplyAll()
end

--- A line for /camelot actionbars.
function Visibility.Describe(token)
    local bar = barOf(token)
    if not bar then return "no frame" end
    local hover = "off"
    if get(token, "mouseoverMode") then
        hover = addon.HoverFade.IsOver(bar) and "over" or "out"
    end
    return string.format("visible %s, driver %s, shown %s, alpha %.2f, hover %s",
        Visibility.Mode(token), drivers[bar] or "none", tostring(bar:IsShown()), bar:GetAlpha(), hover)
end

--------------------------------------------------------------------------------
-- The opacity edges: the pull one frame late so the state reads settle, the
-- regen a tenth of a second late, the target change and the world entry at
-- once. SetAlpha is unprotected, so the combat edge runs in combat.
--------------------------------------------------------------------------------

local function refreshAlpha()
    if not (ActionBars.IsBuilt and ActionBars.IsBuilt()) then return end
    for _, token in ipairs(Visibility.Tokens()) do
        Visibility.ApplyAlpha(token)
    end
end

addon.Events.On(OWNER, "PLAYER_REGEN_DISABLED", function() C_Timer.After(0, refreshAlpha) end)
addon.Events.On(OWNER, "PLAYER_REGEN_ENABLED", function() C_Timer.After(0.1, refreshAlpha) end)
addon.Events.On(OWNER, "PLAYER_TARGET_CHANGED", refreshAlpha)
addon.Events.On(OWNER, "PLAYER_ENTERING_WORLD", refreshAlpha)
