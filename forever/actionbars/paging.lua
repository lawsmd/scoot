--------------------------------------------------------------------------------
-- forever/actionbars/paging.lua
-- How Action Bar 1 pages. Blizzard's main bar pages because the action bar
-- controller writes its actionpage attribute from untainted Lua; a Camelot
-- bar cannot be written that way, and no addon-handed restricted snippet
-- compiles on this client. What does run is Blizzard's own state driver
-- manager: RegisterAttributeDriver has it evaluate a macro condition string
-- and set exactly one attribute on the frame from its own OnUpdate. The
-- driver sits on each of the twelve buttons, so CalculateAction finds
-- actionpage on the button itself and never walks to a parent.
--
-- The clauses mirror the controller's order (Blizzard_ActionBarController/
-- ActionBarController.lua): vehicle, override, temporary shapeshift, the
-- manual pages, then the class forms, bonusbar 5 last so it cannot pin the
-- bar. The parser on this client answers true to a conditional it does not
-- know, and one unknown clause would page the bar for good, so each clause
-- carries the plain read that says whether its conditional should be true
-- at build; a clause that reads true against that oracle is dropped and
-- listed in the debug window.
--
-- The edge log the window prints compares the driver's page with the
-- controller's on every paging edge, with the parse of every conditional
-- the design leans on, twice per edge: at the event and half a second later,
-- after the manager's next pass.
--------------------------------------------------------------------------------

local _, addon = ...

local ActionBars = addon.ActionBars
local Paging = {}
ActionBars.Paging = Paging

local OWNER = ActionBars.OWNER

local function reads(cond)
    return SecureCmdOptionParse("[" .. cond .. "] 1; 0") == "1"
end

--------------------------------------------------------------------------------
-- The clauses
--------------------------------------------------------------------------------

local CLAUSES = {}

local function clause(cond, page, expect)
    CLAUSES[#CLAUSES + 1] = { cond = cond, page = page, expect = expect }
end

clause("vehicleui",
    function() return C_ActionBar.GetVehicleBarIndex() end,
    function() return C_ActionBar.HasVehicleActionBar() end)
clause("overridebar",
    function() return C_ActionBar.GetOverrideBarIndex() end,
    function() return C_ActionBar.HasOverrideActionBar() end)
clause("shapeshift",
    function() return C_ActionBar.GetTempShapeshiftBarIndex() end,
    function() return C_ActionBar.HasTempShapeshiftActionBar() end)
for n = 2, 6 do
    clause("bar:" .. n,
        function() return n end,
        function() return C_ActionBar.GetActionBarPage() == n end)
end
for n = 1, 5 do
    clause("bonusbar:" .. n,
        function() return NUM_ACTIONBAR_PAGES + n end,
        function() return C_ActionBar.HasBonusActionBar() and C_ActionBar.GetBonusBarOffset() == n end)
end

--- The condition string from the clauses whose parse agrees with its oracle,
--- and the conditionals dropped for disagreeing.
function Paging.Build()
    local parts, dropped = {}, {}
    for _, c in ipairs(CLAUSES) do
        local parsed = reads(c.cond)
        local expected = c.expect() and true or false
        if parsed and not expected then
            dropped[#dropped + 1] = c.cond
        else
            parts[#parts + 1] = string.format("[%s] %d", c.cond, c.page())
        end
    end
    parts[#parts + 1] = "1"
    return table.concat(parts, "; "), dropped
end

--------------------------------------------------------------------------------
-- The edge log
--------------------------------------------------------------------------------

-- Every conditional the design leans on, with a plain oracle where one
-- exists, so a row reads "cond=parsed/expected". A conditional that parses
-- 1 against an oracle of 0 outside the state it names is one the parser
-- does not know. "bogus" is the control: it should read 1 on this client.
local OBSERVED = {
    { "vehicleui",   function() return C_ActionBar.HasVehicleActionBar() end },
    { "overridebar", function() return C_ActionBar.HasOverrideActionBar() end },
    { "shapeshift",  function() return C_ActionBar.HasTempShapeshiftActionBar() end },
    { "possessbar",  function() return C_ActionBar.IsPossessBarVisible() end },
    { "petbattle",   function() return C_PetBattles.IsInBattle() end },
    { "stealth",     function() return IsStealthed() end },
    { "pet",         function() return UnitExists("pet") end },
    { "bar:2",       function() return C_ActionBar.GetActionBarPage() == 2 end },
    { "bar:3",       function() return C_ActionBar.GetActionBarPage() == 3 end },
    { "bar:4",       function() return C_ActionBar.GetActionBarPage() == 4 end },
    { "bar:5",       function() return C_ActionBar.GetActionBarPage() == 5 end },
    { "bar:6",       function() return C_ActionBar.GetActionBarPage() == 6 end },
    { "bonusbar:1",  function() return C_ActionBar.HasBonusActionBar() and C_ActionBar.GetBonusBarOffset() == 1 end },
    { "bonusbar:2",  function() return C_ActionBar.HasBonusActionBar() and C_ActionBar.GetBonusBarOffset() == 2 end },
    { "bonusbar:3",  function() return C_ActionBar.HasBonusActionBar() and C_ActionBar.GetBonusBarOffset() == 3 end },
    { "bonusbar:4",  function() return C_ActionBar.HasBonusActionBar() and C_ActionBar.GetBonusBarOffset() == 4 end },
    { "bonusbar:5",  function() return C_ActionBar.HasBonusActionBar() and C_ActionBar.GetBonusBarOffset() == 5 end },
    { "bogus",       function() return false end },
}

-- The events after which the controller re-pages the main bar, plus the
-- regen pair, since the driver's value in a fight is the whole question.
local EDGES = {
    "ACTIONBAR_PAGE_CHANGED", "UPDATE_BONUS_ACTIONBAR", "UPDATE_VEHICLE_ACTIONBAR",
    "UPDATE_OVERRIDE_ACTIONBAR", "UPDATE_POSSESS_BAR", "UPDATE_SHAPESHIFT_FORM",
    "UPDATE_STEALTH", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
}

local RING_MAX = 40
local rows = {}

local function bit(v)
    return v and "1" or "0"
end

--- One row of the log: the two pages side by side, the client's current
--- page, and every observed conditional.
function Paging.Snapshot(label)
    local blizzard = MainActionBar and MainActionBar:GetAttribute("actionpage")
    local bar = ActionBars.Frames and ActionBars.Frames.bar1
    local mine = bar and bar.actionButtons[1]:GetAttribute("actionpage")
    local seen = {}
    for _, entry in ipairs(OBSERVED) do
        local ok, expected = pcall(entry[2])
        seen[#seen + 1] = string.format("%s=%s/%s", entry[1], bit(reads(entry[1])),
            ok and bit(expected) or "?")
    end
    return string.format("%s %-28s blizzard %s  camelot %s  page %s%s\n      %s",
        date("%H:%M:%S"), label, tostring(blizzard), tostring(mine),
        tostring(C_ActionBar.GetActionBarPage()), InCombatLockdown() and "  (lockdown)" or "",
        table.concat(seen, " "))
end

local function record(label)
    if #rows >= RING_MAX then table.remove(rows, 1) end
    rows[#rows + 1] = Paging.Snapshot(label)
end

local function onEdge(event)
    record(event)
    C_Timer.After(0.5, function() record(event .. " +0.5s") end)
end

function Paging.Rows()
    return rows
end

--------------------------------------------------------------------------------
-- Register
--------------------------------------------------------------------------------

local registered = false

--- The driver on every button of Action Bar 1, once, out of combat: the
--- manager resolves it at once inside this call, and the button's
--- OnAttributeChanged runs UpdateAction, so registering in a fight would
--- run that first write blocked.
function Paging.Register()
    if registered then return end
    local bar = ActionBars.Frames and ActionBars.Frames.bar1
    if not bar or InCombatLockdown() then return end

    local conditions, dropped = Paging.Build()
    Paging.conditions = conditions
    Paging.dropped = dropped
    for _, button in ipairs(bar.actionButtons) do
        RegisterAttributeDriver(button, "actionpage", conditions)
    end
    registered = true

    for _, event in ipairs(EDGES) do
        addon.Events.On(OWNER, event, onEdge)
    end
    record("registered")
end

function Paging.IsRegistered()
    return registered
end
