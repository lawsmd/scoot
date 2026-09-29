--------------------------------------------------------------------------------
-- forever/objectivetracker/fade.lua
-- The fade between the panes. A quest that becomes current, or stops being
-- current, is drawn by another module: its block leaves one pool and a fresh
-- block comes from the other, and without this file the swap is a cut. Here
-- the two blocks cross-fade over the Fade setting's length: both modules draw
-- the quest for that long, the leaving block's alpha falling from where it
-- stands to 0 and the arriving block's rising to 1, and the leaving side is
-- released at 0. A reversal mid-fade, the player stepping back over the
-- area's edge, turns both alphas around from where they are.
--
-- The routing predicates in current.lua ask Route on every layout, so every
-- trigger the pane has (the area, progress, the hold's end, a pin, a setting)
-- comes through here and nothing in this file subscribes to an event. A
-- block's alpha is the channel Blizzard's own block animations use
-- (ObjectiveTrackerAnimBlockMixin), a freed block's alpha goes back to 1 in
-- its Free, and a block mid-animation is left to the animation. While a
-- module holds no settled quest its header follows the fading block, the
-- pane's background with it, so a first quest brings the pane in and a last
-- one takes it out, and the tracker's Quests header goes with the last quest
-- that leaves it. Nothing fades at login, when a quest is first tracked, or
-- in Edit Mode.
--------------------------------------------------------------------------------

local addonName, addon = ...

local OT = addon.ObjectiveTracker
local Style = OT.Style

local Fade = {}
OT.Fade = Fade

local CONTAINER = "CamelotCurrentObjectiveTracker"
local TRACKER_CONTAINER = "CamelotObjectiveTracker"
local PANE_MODULE = "CamelotCurrentQuestObjectiveTracker"
local PANE_MODULES = { PANE_MODULE }
local TRACKER_MODULES = { "CamelotQuestObjectiveTracker", "CamelotCampaignQuestObjectiveTracker" }
local MODULES = { PANE_MODULE, TRACKER_MODULES[1], TRACKER_MODULES[2] }

local PANE, TRACKER = "pane", "tracker"
local SIDES = { PANE, TRACKER }
local LOG_MAX = 8

-- questID -> { pane = alpha or nil, tracker = alpha or nil, to = "pane" | "tracker" }.
-- `to` is the side the quest belongs on now; its alpha rises to 1. The other
-- side's alpha falls, and at 0 the layout drops its block and the side goes.
local sides = {}
local dimmed = {}            -- block -> true: every block this file wrote, restored each pass
local held = {}              -- module name -> true: its header stands below its base
local backgroundHeld = false -- the pane's background stands below its base
local refreshQueued = false
local log = {}

local function note(fmt, ...)
    log[#log + 1] = string.format("%.1f " .. fmt, GetTime(), ...)
    if #log > LOG_MAX then table.remove(log, 1) end
end

local function editing()
    local EM = addon.EditMode
    return EM and EM.IsEditModeActiveOrOpening and EM.IsEditModeActiveOrOpening() or false
end

-- A side draws its block while its alpha is set, except a leaving side that
-- has reached 0: that block is dropped by the next layout.
local function displayed(s, side)
    local a = s[side]
    return a ~= nil and (side == s.to or a > 0)
end

-- A transition can start inside a layout that covers one container only;
-- the arriving block is created by the other's. One more layout, next frame.
local function queueRefresh()
    if refreshQueued then return end
    refreshQueued = true
    C_Timer.After(0, function()
        refreshQueued = false
        if OT.Current then OT.Current.Refresh() end
    end)
end

local driver = CreateFrame("Frame")
driver:Hide()

--------------------------------------------------------------------------------
-- Routing
--------------------------------------------------------------------------------

--- From the three routing predicates, on every layout. `current` is
--- Current.IsCurrent(questID), the side the quest belongs on. Returns
--- inPane, inTracker: which modules draw the quest now.
function Fade.Route(questID, current)
    local want = current and PANE or TRACKER
    local other = current and TRACKER or PANE
    local s = sides[questID]
    if not s then
        -- First sight: settled where it belongs.
        s = { to = want }
        s[want] = 1
        sides[questID] = s
        return displayed(s, PANE), displayed(s, TRACKER)
    end
    if s.to ~= want then
        s.to = want
        if s[want] == nil then s[want] = 0 end
        note("%d to %s from pane %s, tracker %s", questID, want, tostring(s.pane), tostring(s.tracker))
        queueRefresh()
    end
    if Style.FadeSeconds() <= 0 or editing() then
        s[want] = 1
        s[other] = nil
    elseif s[want] < 1 or s[other] ~= nil then
        driver:Show()
    end
    return displayed(s, PANE), displayed(s, TRACKER)
end

--- The quest left the watch list or the log: whatever it was doing stops,
--- and a block it still has goes back to full alpha on the next pass.
function Fade.Drop(questID)
    sides[questID] = nil
end

--------------------------------------------------------------------------------
-- The pass
--------------------------------------------------------------------------------

local function animating(block)
    return type(block.HasActiveAnim) == "function" and block:HasActiveAnim() or false
end

local function blockOf(moduleName, questID)
    local module = _G[moduleName]
    if not (module and module.usedBlocks) then return nil end
    return module:GetExistingBlock(questID)
end

-- Finds the module drawing a side's block and, below 1, writes the alpha to
-- the block. Returns the module's name, or nil when no block exists: the
-- layout has not created it yet, has dropped it, or skipped it for height.
local function write(side, questID, alpha)
    for _, name in ipairs(side == PANE and PANE_MODULES or TRACKER_MODULES) do
        local block = blockOf(name, questID)
        if block then
            if alpha < 1 and not animating(block) then
                block:SetAlpha(alpha)
                dimmed[block] = true
            end
            return name
        end
    end
    return nil
end

-- A module's header, and for the pane its background too, while the module
-- holds no settled quest: the highest alpha among the quests it draws, over
-- the bases the instance-combat fade and Background Opacity give them. So
-- the pane comes in with its first quest and goes with its last, and the
-- tracker's Quests header goes with the last quest that leaves it.
local function hold(maxByModule)
    local release = false
    for _, name in ipairs(MODULES) do
        local module, factor = _G[name], maxByModule[name]
        if module and module.Header and factor and factor < 1 then
            module.Header:SetAlpha(Style.CombatAlpha() * factor)
            held[name] = true
        elseif held[name] then
            held[name] = nil
            release = true
        end
    end
    if release then Style.ApplyCombatOpacity() end

    local container, factor = _G[CONTAINER], maxByModule[PANE_MODULE]
    if container and container.NineSlice and factor and factor < 1 then
        container.NineSlice:SetAlpha(Style.BackgroundAlpha(Style.CURRENT) * factor)
        backgroundHeld = true
    elseif backgroundHeld then
        backgroundHeld = false
        Style.ApplyBackgroundAlpha()
    end
end

local maxByModule = {}

--- After every layout of either container, and every frame while a fade
--- runs. Restores the last pass, writes every fading side to its block, lets
--- go of a leaving side whose block the layout has dropped, and holds the
--- headers and the pane's background with their quests.
function Fade.Apply()
    for block in pairs(dimmed) do
        if not animating(block) then block:SetAlpha(1) end
    end
    wipe(dimmed)
    wipe(maxByModule)
    for questID, s in pairs(sides) do
        for _, side in ipairs(SIDES) do
            local a = s[side]
            if a then
                local name = write(side, questID, a)
                if name then
                    maxByModule[name] = math.max(maxByModule[name] or 0, a)
                elseif a <= 0 and side ~= s.to then
                    s[side] = nil
                end
            end
        end
    end
    hold(maxByModule)
end

--------------------------------------------------------------------------------
-- The driver
--------------------------------------------------------------------------------

driver:SetScript("OnUpdate", function(self, elapsed)
    local seconds = Style.FadeSeconds()
    local rate = seconds > 0 and elapsed / seconds or 1
    local busy, released = false, false
    for _, s in pairs(sides) do
        local to = s.to
        local from = to == PANE and TRACKER or PANE
        local rising = s[to] or 1
        if rising < 1 then
            s[to] = math.min(1, rising + rate)
            if s[to] < 1 then busy = true end
        end
        local falling = s[from]
        if falling then
            if falling > 0 then
                falling = math.max(0, falling - rate)
                s[from] = falling
                if falling <= 0 then released = true end
            end
            -- At 0 the side waits for the layout that drops its block.
            busy = true
        end
    end
    Fade.Apply()
    if released and OT.Current then OT.Current.Refresh() end
    if not busy then self:Hide() end
end)

--------------------------------------------------------------------------------
-- Install
--------------------------------------------------------------------------------

local installed = false

--- Once, from Current.Install. A layout creates the arriving block and frees
--- the leaving one, so every layout of either container is followed by a pass.
function Fade.Install()
    if installed then return end
    local pane, tracker = _G[CONTAINER], _G[TRACKER_CONTAINER]
    if not (pane and tracker and _G[PANE_MODULE]) then return end
    installed = true
    hooksecurefunc(pane, "Update", Fade.Apply)
    hooksecurefunc(tracker, "Update", Fade.Apply)
end

--------------------------------------------------------------------------------
-- /camelot tracker
--------------------------------------------------------------------------------

local function alphaText(a)
    if a == nil then return "-" end
    return string.format("%.2f", a)
end

function Fade.Dump(push)
    local heldNames = {}
    for name in pairs(held) do heldNames[#heldNames + 1] = name end
    push("fade: %.1fs%s, headers held: %s, pane background held %s", Style.FadeSeconds(),
        editing() and ", instant in Edit Mode" or "",
        #heldNames > 0 and table.concat(heldNames, ", ") or "none", tostring(backgroundHeld))
    local n = 0
    for questID, s in pairs(sides) do
        if (s.pane and s.pane < 1) or (s.tracker and s.tracker < 1) then
            n = n + 1
            push("  %-6d to %s: pane %s, tracker %s", questID, s.to, alphaText(s.pane), alphaText(s.tracker))
        end
    end
    if n == 0 then push("  none in flight") end
    for _, line in ipairs(log) do push("  %s", line) end
end
