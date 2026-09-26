--------------------------------------------------------------------------------
-- forever/objectivetracker/current.lua
-- The Current Objectives pane's state, and the routing of quests between the
-- main tracker and the pane.
--
-- A watched quest is current while the player stands inside its map area,
-- the blue region the world map and minimap draw for it, and for a hold
-- after the player makes progress on it. The client says both:
-- PLAYER_INSIDE_QUEST_BLOB_STATE_CHANGED (questID, isInside) on every
-- crossing, with C_Minimap.IsInsideQuestBlob to seed the picture; and
-- QUEST_WATCH_UPDATE (questID) on every progress, naming the quest only, so
-- the objective that moved is found by diffing C_QuestLog.GetQuestObjectives
-- against the last read. Both read plain on 12.x: Blizzard's own Lua
-- measures and concatenates the objective text.
--
-- The routing is one method. QuestObjectiveTrackerMixin:ShouldDisplayQuest
-- is the sole predicate between the watch list and a quest module's blocks,
-- and assigning it on an instance shadows the mixin's copy, so the Quest and
-- Campaign twins refuse a current quest and the Current twin takes only
-- those. Every change marks the three modules dirty; the pane's container
-- hides itself when its one module has no content, outside Edit Mode.
--------------------------------------------------------------------------------

local addonName, addon = ...

local OT = addon.ObjectiveTracker
local Style = OT.Style

local Current = {}
OT.Current = Current

local OWNER = "camelotObjectiveTrackerCurrent"
local LOG_MAX = 12

-- A change seen by a QUEST_LOG_UPDATE this close before the QUEST_WATCH_UPDATE
-- is the same progress, whichever of the two the client delivered first.
local CHANGE_WINDOW = 1

local QUEST_MODULES = {
    "CamelotQuestObjectiveTracker",
    "CamelotCampaignQuestObjectiveTracker",
    "CamelotCurrentQuestObjectiveTracker",
}
local CURRENT_MODULE = "CamelotCurrentQuestObjectiveTracker"

local entries = {}     -- questID -> { inside, progressAt, token, objective, before, after, pinned }
local snapshots = {}   -- questID -> { [objectiveIndex] = { fulfilled, required, finished, text } }
local changes = {}     -- questID -> { index, before, after, fulfilled, required, rose, t }: the last objective change read
local pendingRead = {} -- questID -> true: progress reported, no change read yet
local log = {}

--------------------------------------------------------------------------------
-- Reads
--------------------------------------------------------------------------------

local function setting(key)
    return Style.Get("current", key)
end

function Current.Enabled()
    return setting("enabled") == true
end

local function now()
    return GetTime()
end

local function isPlain(v)
    return not (issecretvalue and issecretvalue(v))
end

local function questName(questID)
    local ok, title = pcall(C_QuestLog.GetTitleForQuestID, questID)
    if ok and type(title) == "string" and isPlain(title) then return title end
    return "?"
end

local function push(fmt, ...)
    log[#log + 1] = string.format("%.1f " .. fmt, now(), ...)
    if #log > LOG_MAX then table.remove(log, 1) end
end

local function entryFor(questID)
    local e = entries[questID]
    if not e then
        e = {}
        entries[questID] = e
    end
    return e
end

local function modulesDirty()
    for _, name in ipairs(QUEST_MODULES) do
        local module = _G[name]
        if module then module:MarkDirty() end
    end
end

local function eachWatch(fn)
    local ok, n = pcall(C_QuestLog.GetNumQuestWatches)
    if not ok or type(n) ~= "number" then return 0 end
    for i = 1, n do
        local okID, questID = pcall(C_QuestLog.GetQuestIDForQuestWatchIndex, i)
        if okID and type(questID) == "number" then fn(questID) end
    end
    return n
end

-- The objectives read fresh, the fields a diff and the progress flash need.
local function readObjectives(questID)
    local ok, list = pcall(C_QuestLog.GetQuestObjectives, questID)
    if not ok or type(list) ~= "table" then return nil end
    local snap = {}
    for index, o in ipairs(list) do
        if type(o) == "table" then
            snap[index] = { fulfilled = o.numFulfilled, required = o.numRequired, finished = o.finished, text = o.text }
        end
    end
    return snap
end

-- Reads the quest's objectives and records the first objective whose count
-- or finished flag differs from the last read. Returns the change, or nil.
local function updateSnapshot(questID)
    local before, after = snapshots[questID], readObjectives(questID)
    if not after then return nil end
    snapshots[questID] = after
    if not before then return nil end
    for index, o in ipairs(after) do
        local b = before[index]
        if b and isPlain(o.fulfilled) and isPlain(b.fulfilled) and isPlain(o.finished) and isPlain(b.finished)
            and (o.fulfilled ~= b.fulfilled or o.finished ~= b.finished) then
            local change = {
                index = index, before = b.text, after = o.text, t = now(),
                fulfilled = o.fulfilled, required = o.required,
                rose = type(o.fulfilled) == "number" and type(b.fulfilled) == "number" and o.fulfilled > b.fulfilled,
            }
            changes[questID] = change
            return change
        end
    end
    return nil
end

local function insideBlob(questID)
    local ok, inside = pcall(C_Minimap.IsInsideQuestBlob, questID)
    return ok and inside == true
end

--------------------------------------------------------------------------------
-- The current set
--------------------------------------------------------------------------------

--- Whether a quest draws in the pane now. Read by the three routing
--- predicates on every layout.
function Current.IsCurrent(questID)
    if not Current.Enabled() then return false end
    local e = entries[questID]
    if not e then return false end
    if e.pinned then return true end
    if e.inside and setting("onEnterArea") then return true end
    if e.progressAt and setting("onProgress") and now() - e.progressAt < Style.HoldSeconds() then
        return true
    end
    return false
end

-- Why a quest is in the pane, for the dump.
local function reasons(questID, e)
    local parts = {}
    if e.pinned then parts[#parts + 1] = "pinned" end
    if e.inside then parts[#parts + 1] = "inside" end
    if e.progressAt then
        parts[#parts + 1] = string.format("progress %.0fs ago", now() - e.progressAt)
    end
    if #parts == 0 then return "idle" end
    return table.concat(parts, ", ") .. (Current.IsCurrent(questID) and "" or " (not current)")
end

-- Stamps progress and arms the hold's end. A later stamp retires the earlier
-- timer through the token.
local function stampProgress(questID, e)
    e.progressAt = now()
    local token = (e.token or 0) + 1
    e.token = token
    C_Timer.After(Style.HoldSeconds(), function()
        local cur = entries[questID]
        if cur and cur.token == token then
            push("hold over: %d %s", questID, questName(questID))
            modulesDirty()
        end
    end)
end

local function recordChange(questID, e, change)
    e.objective, e.before, e.after = change.index, change.before, change.after
    pendingRead[questID] = nil
    if change.rose and isPlain(change.required) and OT.Flash then
        OT.Flash.Request(questID, change.index, change.fulfilled, change.required)
    end
end

--- Marks the three quest modules dirty: a setting changed.
function Current.Refresh()
    modulesDirty()
end

--- The testing override: toggles a watched quest in and out of the pane
--- whatever the triggers say. Returns the new state.
function Current.Pin(questID)
    local e = entryFor(questID)
    e.pinned = not e.pinned
    push("%s: %d %s", e.pinned and "pinned" or "unpinned", questID, questName(questID))
    modulesDirty()
    return e.pinned
end

function Current.Clear()
    wipe(entries)
    wipe(pendingRead)
    push("cleared")
    modulesDirty()
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

-- The initial picture: every watched quest's objectives, and whether the
-- player stands in its area now. Entries for quests no longer watched go.
local function seed(reason)
    local watched, inside = {}, 0
    local n = eachWatch(function(questID)
        watched[questID] = true
        if not snapshots[questID] then snapshots[questID] = readObjectives(questID) end
        if insideBlob(questID) then
            entryFor(questID).inside = true
            inside = inside + 1
        elseif entries[questID] then
            entries[questID].inside = false
        end
    end)
    for questID in pairs(entries) do
        if not watched[questID] then
            entries[questID] = nil
            snapshots[questID] = nil
        end
    end
    push("seed (%s): %d watched, %d inside an area", reason, n, inside)
    modulesDirty()
end

local function onBlob(_, questID, isInside)
    if type(questID) ~= "number" then return end
    local e = entryFor(questID)
    e.inside = isInside == true
    push("area %s: %d %s", e.inside and "entered" or "left", questID, questName(questID))
    modulesDirty()
end

local function onWatchUpdate(_, questID)
    if type(questID) ~= "number" then return end
    local e = entryFor(questID)
    stampProgress(questID, e)
    local change = updateSnapshot(questID)
    local recent = changes[questID]
    if not change and recent and now() - recent.t <= CHANGE_WINDOW then change = recent end
    if change then
        recordChange(questID, e, change)
        push("progress: %d %s, objective %d: %s -> %s", questID, questName(questID),
            change.index, tostring(change.before), tostring(change.after))
    else
        pendingRead[questID] = true
        push("progress: %d %s, objective not read yet", questID, questName(questID))
    end
    modulesDirty()
end

-- Coalesced per frame. Re-reads every watched quest so the next diff has a
-- base, and settles a progress whose objective the watch update could not
-- read yet.
local function onLogUpdate()
    eachWatch(function(questID)
        local change = updateSnapshot(questID)
        if change and pendingRead[questID] and entries[questID] then
            recordChange(questID, entries[questID], change)
            push("progress read late: %d %s, objective %d: %s -> %s", questID, questName(questID),
                change.index, tostring(change.before), tostring(change.after))
        end
    end)
end

local function onWatchListChanged(_, questID, added)
    if type(questID) ~= "number" then return end
    if added then
        snapshots[questID] = readObjectives(questID)
        if insideBlob(questID) then entryFor(questID).inside = true end
    else
        entries[questID] = nil
        snapshots[questID] = nil
        changes[questID] = nil
        pendingRead[questID] = nil
    end
    modulesDirty()
end

local function onQuestGone(_, questID)
    if type(questID) ~= "number" then return end
    entries[questID] = nil
    snapshots[questID] = nil
    changes[questID] = nil
    pendingRead[questID] = nil
end

--------------------------------------------------------------------------------
-- Install
--------------------------------------------------------------------------------

local installed = false

--- Once, from the tracker's setup, after the modules are in their containers
--- and the style is on. Puts the three predicates on the module instances,
--- titles the pane's module, subscribes, and seeds.
function Current.Install()
    if installed then return end
    local questTwin = CamelotQuestObjectiveTracker
    local campaignTwin = CamelotCampaignQuestObjectiveTracker
    local currentTwin = _G[CURRENT_MODULE]
    if not (questTwin and campaignTwin and currentTwin) then return end
    if not (QuestObjectiveTrackerMixin and CampaignQuestObjectiveTrackerMixin) then return end
    installed = true

    -- Each twin's own copy, chained to the mixin's: the mixin's predicate
    -- keeps deciding tasks, bounties and the campaign split.
    local function excluding(base)
        return function(self, quest)
            if Current.IsCurrent(quest:GetID()) then return false end
            return base(self, quest)
        end
    end
    questTwin.ShouldDisplayQuest = excluding(QuestObjectiveTrackerMixin.ShouldDisplayQuest)
    campaignTwin.ShouldDisplayQuest = excluding(CampaignQuestObjectiveTrackerMixin.ShouldDisplayQuest)
    currentTwin.ShouldDisplayQuest = function(_, quest)
        if quest.isTask or quest:IsDisabledForSession() then return false end
        return Current.IsCurrent(quest:GetID())
    end

    -- The pane has no container header; this module's header is its title.
    currentTwin:SetHeader("Current Objectives")

    addon.Events.On(OWNER, "PLAYER_INSIDE_QUEST_BLOB_STATE_CHANGED", onBlob)
    addon.Events.On(OWNER, "QUEST_WATCH_UPDATE", onWatchUpdate)
    addon.Events.On(OWNER, "QUEST_LOG_UPDATE", onLogUpdate)
    addon.Events.On(OWNER, "QUEST_WATCH_LIST_CHANGED", onWatchListChanged)
    addon.Events.On(OWNER, "QUEST_REMOVED", onQuestGone)
    addon.Events.On(OWNER, "QUEST_TURNED_IN", onQuestGone)
    addon.Events.On(OWNER, "PLAYER_ENTERING_WORLD", function() seed("world") end)

    seed("install")
end

--------------------------------------------------------------------------------
-- /camelot tracker
--------------------------------------------------------------------------------

function Current.Dump(push)
    push("current: installed %s, enabled %s, on entering area %s, on progress %s, hold %ss",
        tostring(installed), tostring(Current.Enabled()), tostring(setting("onEnterArea")),
        tostring(setting("onProgress")), tostring(Style.HoldSeconds()))
    local n = 0
    for questID, e in pairs(entries) do
        n = n + 1
        push("  %-6d %-40s %s%s", questID, questName(questID), reasons(questID, e),
            e.objective and string.format("; last objective %d: %s", e.objective, tostring(e.after)) or "")
    end
    if n == 0 then push("  no entries") end
    push("pane log (%d):", #log)
    for _, line in ipairs(log) do push("  %s", line) end
    if OT.Flash then OT.Flash.Dump(push) end
    push("")
end
