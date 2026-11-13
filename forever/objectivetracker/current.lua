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
-- hides itself when its one module has no content, outside Edit Mode. The
-- settled answer goes through fade.lua, which keeps both sides drawing a
-- quest for the fade's length as it moves.
--
-- The Camelot style (cards.lua) reads the same set through List and redraws
-- on OnChanged; with it on, the Current twin draws nothing and the pane
-- stays empty, while the Quest and Campaign twins still refuse a current
-- quest.
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
local dungeon = nil    -- { name, quests = { [questID] = "header" } } while inside a dungeon or raid
local declined = {}    -- questID -> true: a watch this feature added that the player took off, this visit
local unwatched = {}   -- questID -> "limit" | "refused": a dungeon quest the feature could not track, this visit
local kept = {}        -- questID -> true: a swapped-out watch the player tracked again by hand, this visit
local logCount = -1    -- the quest log's entry count at the last dungeon read
local installed = false
local log = {}
local subscribers = {}

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

-- Every change to the set: the three modules re-route, and the cards redraw.
local function modulesDirty()
    for _, name in ipairs(QUEST_MODULES) do
        local module = _G[name]
        if module then module:MarkDirty() end
    end
    for _, fn in ipairs(subscribers) do fn() end
end

--- fn() after every change to the current set, a setting's included.
function Current.OnChanged(fn)
    subscribers[#subscribers + 1] = fn
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

local function isWatched(questID)
    local ok, watchType = pcall(C_QuestLog.GetQuestWatchType, questID)
    return ok and watchType ~= nil
end

--------------------------------------------------------------------------------
-- The dungeon
--------------------------------------------------------------------------------

-- Inside a dungeon or raid, every quest for it is current. No API names a
-- quest's dungeon; the quest log files a dungeon quest under a header with
-- the dungeon's name, and that header is the one read. isOnMap is not used:
-- on Forever it read true inside the Drowned City for quests in other zones
-- (beta, 12 November 2026).

-- A name compared without case or a leading "The ".
local function nameKey(name)
    return (name:lower():gsub("^the%s+", ""))
end

-- The name keys a header may carry for the instance the player is in, or nil
-- outside a dungeon or raid.
local function instanceNames()
    if not Style.InDungeonOrRaid() then return nil end
    local names, first = {}, nil
    local ok, name = pcall(GetInstanceInfo)
    if ok and type(name) == "string" and isPlain(name) and name ~= "" then
        names[nameKey(name)], first = true, name
    end
    local okZone, zone = pcall(GetRealZoneText)
    if okZone and type(zone) == "string" and isPlain(zone) and zone ~= "" then
        names[nameKey(zone)], first = true, first or zone
    end
    if not first then return nil end
    return names, first
end

-- The quests in the log for the instance named, and the log's entry count.
local function readDungeonQuests(names)
    local quests = {}
    local okN, n = pcall(C_QuestLog.GetNumQuestLogEntries)
    if not okN or type(n) ~= "number" then return quests, -1 end
    local header
    for i = 1, n do
        local ok, info = pcall(C_QuestLog.GetInfo, i)
        if ok and type(info) == "table" then
            if info.isHeader then
                local title = info.title
                header = (type(title) == "string" and isPlain(title)) and nameKey(title) or nil
            elseif type(info.questID) == "number" and not info.isHidden and not info.isTask
                and header and names[header] then
                quests[info.questID] = "header"
            end
        end
    end
    return quests, n
end

local function sameQuests(a, b)
    for questID, how in pairs(a) do
        if b[questID] ~= how then return false end
    end
    for questID in pairs(b) do
        if a[questID] == nil then return false end
    end
    return true
end

-- A set of quest ids per character in the account store, so a reload or a
-- logout inside the dungeon still knows what to undo. create false returns
-- nil when the character has none.
local function charSet(key, create)
    local db = addon.db and addon.db.global
    if not db then return nil end
    local ok, guid = pcall(UnitGUID, "player")
    if not ok or type(guid) ~= "string" or not isPlain(guid) then return nil end
    local all = db[key]
    if not all then
        if not create then return nil end
        all = {}
        db[key] = all
    end
    local list = all[guid]
    if not list and create then
        list = {}
        all[guid] = list
    end
    return list, all, guid
end

-- The watches this feature added.
local function addedWatches(create)
    return charSet("currentDungeonWatches", create)
end

-- The player's watches this feature took off to make room under the limit.
local function swappedWatches(create)
    return charSet("currentDungeonSwapped", create)
end

-- Tracks again every quest swapped out, once the player leaves or the
-- trigger goes off.
local function restoreSwapped()
    local list, all, guid = swappedWatches(false)
    if not list then return end
    for questID in pairs(list) do
        list[questID] = nil
        local okIndex, index = pcall(C_QuestLog.GetLogIndexForQuestID, questID)
        if okIndex and index and not isWatched(questID) then
            pcall(C_QuestLog.AddQuestWatch, questID)
            push("watch %s: %d %s", isWatched(questID) and "restored" or "not restored",
                questID, questName(questID))
        end
    end
    all[guid] = nil
end

-- The watch to swap out for a dungeon quest: the last on the watch list that
-- is not a dungeon quest, not supertracked, and not one the player tracked
-- again by hand this visit.
local function swapCandidate()
    local super
    if C_SuperTrack then
        local ok, id = pcall(C_SuperTrack.GetSuperTrackedQuestID)
        if ok and type(id) == "number" then super = id end
    end
    local okN, n = pcall(C_QuestLog.GetNumQuestWatches)
    if not okN or type(n) ~= "number" then return nil end
    for i = n, 1, -1 do
        local ok, questID = pcall(C_QuestLog.GetQuestIDForQuestWatchIndex, i)
        if ok and type(questID) == "number" and not dungeon.quests[questID]
            and questID ~= super and not kept[questID] then
            return questID
        end
    end
    return nil
end

-- Takes off every added watch outside the set given (nil: every one).
local function releaseWatches(keep)
    local list, all, guid = addedWatches(false)
    if not list then return end
    for questID in pairs(list) do
        if not (keep and keep[questID]) then
            -- Off the list before the call, so the watch-list event that
            -- follows does not read as the player's untrack.
            list[questID] = nil
            if isWatched(questID) then
                pcall(C_QuestLog.RemoveQuestWatch, questID)
                push("watch removed: %d %s", questID, questName(questID))
            end
        end
    end
    if next(list) == nil then all[guid] = nil end
end

-- Watches the dungeon's untracked quests while the trigger is on, swapping
-- out the player's last watches when the limit is reached, and undoes both
-- once the player leaves or the trigger goes off.
local function syncWatches()
    if not (dungeon and Current.Enabled() and setting("onDungeon")) then
        releaseWatches(nil)
        restoreSwapped()
        return
    end
    releaseWatches(dungeon.quests)
    local list = addedWatches(true)
    if not list then return end
    local okCount, count = pcall(C_QuestLog.GetNumQuestWatches)
    count = (okCount and type(count) == "number") and count or 0
    local consts = Constants and Constants.QuestWatchConsts
    local cap = consts and consts.MAX_QUEST_WATCHES or 25
    for questID in pairs(dungeon.quests) do
        if not list[questID] and not declined[questID] and not isWatched(questID) then
            -- Room under the limit, unless the client already refused this
            -- quest: a refused track would swap out a watch on every retry.
            if count >= cap and unwatched[questID] ~= "refused" then
                local out = swapCandidate()
                if out then
                    -- On the list before the call, so the watch-list event
                    -- that follows does not read as the player's untrack.
                    local swapped = swappedWatches(true)
                    if swapped then swapped[out] = true end
                    pcall(C_QuestLog.RemoveQuestWatch, out)
                    if isWatched(out) then
                        if swapped then swapped[out] = nil end
                    else
                        count = count - 1
                        push("watch swapped out: %d %s, for %d", out, questName(out), questID)
                    end
                end
            end
            if count >= cap then
                if not unwatched[questID] then
                    unwatched[questID] = "limit"
                    push("watch limit (%d of %d): %d %s not tracked", count, cap, questID, questName(questID))
                end
            else
                local ok, err = pcall(C_QuestLog.AddQuestWatch, questID)
                if isWatched(questID) then
                    unwatched[questID] = nil
                    list[questID] = true
                    count = count + 1
                    push("watch added: %d %s", questID, questName(questID))
                elseif not unwatched[questID] then
                    -- Retried on every log update; logged once a visit.
                    unwatched[questID] = "refused"
                    push("watch refused: %d %s%s", questID, questName(questID),
                        ok and "" or (": " .. tostring(err)))
                end
            end
        end
    end
end

-- Recomputes the dungeon's quests; on a change, re-routes and syncs watches.
local function readDungeon(reason)
    local names, name = instanceNames()
    local quests, n = {}, -1
    if names then quests, n = readDungeonQuests(names) end
    logCount = n
    local was = dungeon
    if names then
        dungeon = { name = name, quests = quests }
    else
        dungeon = nil
        wipe(declined)
        wipe(unwatched)
        wipe(kept)
    end
    if was and dungeon and was.name == dungeon.name and sameQuests(was.quests, quests) then return end
    if not was and not dungeon then return end
    if dungeon then
        local count = 0
        for _ in pairs(quests) do count = count + 1 end
        push("dungeon (%s): %s, %d quests", reason, name, count)
    else
        push("dungeon (%s): left", reason)
    end
    syncWatches()
    modulesDirty()
end

--------------------------------------------------------------------------------
-- The current set
--------------------------------------------------------------------------------

--- Whether a quest draws in the pane now. Read by the three routing
--- predicates on every layout.
function Current.IsCurrent(questID)
    if not Current.Enabled() then return false end
    if dungeon and dungeon.quests[questID] and setting("onDungeon") then return true end
    local e = entries[questID]
    if not e then return false end
    if e.pinned then return true end
    if e.inside and setting("onEnterArea") then return true end
    if e.progressAt and setting("onProgress") and now() - e.progressAt < Style.HoldSeconds() then
        return true
    end
    return false
end

--- The current quests in watch-list order.
function Current.List()
    local list = {}
    eachWatch(function(questID)
        if Current.IsCurrent(questID) then list[#list + 1] = questID end
    end)
    return list
end

-- Where a quest draws now, for the three predicates: the settled answer
-- through the fade between the panes. Returns inPane, inTracker.
local function route(questID)
    local current = Current.IsCurrent(questID)
    if OT.Fade then return OT.Fade.Route(questID, current) end
    return current, not current
end

local function dropFade(questID)
    if OT.Fade then OT.Fade.Drop(questID) end
end

-- Why a quest is in the pane, for the dump.
local function reasons(questID, e)
    local parts = {}
    local how = dungeon and dungeon.quests[questID]
    if how then parts[#parts + 1] = "dungeon (" .. how .. ")" end
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

--- Marks the three quest modules dirty: a setting changed. Also brings the
--- dungeon's added watches in line with the settings.
function Current.Refresh()
    if installed then syncWatches() end
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
            dropFade(questID)
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
    -- The whole log is walked only when an entry came or went, or the player
    -- crossed an instance's door without a zone event.
    if (dungeon ~= nil) ~= Style.InDungeonOrRaid() then
        readDungeon("log")
    elseif dungeon then
        local ok, n = pcall(C_QuestLog.GetNumQuestLogEntries)
        if ok and type(n) == "number" and n ~= logCount then
            readDungeon("log")
        else
            -- A track the client refused, or one the limit held back, is
            -- tried again; a watch freed by the player makes room.
            syncWatches()
        end
    end
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
        -- A swapped-out watch the player tracked again: theirs, and not
        -- swapped out again this visit.
        local swapped, all, guid = swappedWatches(false)
        if swapped and swapped[questID] then
            swapped[questID] = nil
            if next(swapped) == nil then all[guid] = nil end
            kept[questID] = true
            push("watch kept: %d %s", questID, questName(questID))
        end
    else
        -- An added watch the player took off: theirs to keep off this visit.
        local list, all, guid = addedWatches(false)
        if list and list[questID] then
            list[questID] = nil
            if next(list) == nil then all[guid] = nil end
            declined[questID] = true
            push("watch declined: %d %s", questID, questName(questID))
        end
        entries[questID] = nil
        snapshots[questID] = nil
        changes[questID] = nil
        pendingRead[questID] = nil
        dropFade(questID)
    end
    modulesDirty()
end

local function onQuestGone(_, questID)
    if type(questID) ~= "number" then return end
    entries[questID] = nil
    snapshots[questID] = nil
    changes[questID] = nil
    pendingRead[questID] = nil
    dropFade(questID)
    modulesDirty()
end

--------------------------------------------------------------------------------
-- Install
--------------------------------------------------------------------------------

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
            local _, inTracker = route(quest:GetID())
            if not inTracker then return false end
            return base(self, quest)
        end
    end
    questTwin.ShouldDisplayQuest = excluding(QuestObjectiveTrackerMixin.ShouldDisplayQuest)
    campaignTwin.ShouldDisplayQuest = excluding(CampaignQuestObjectiveTrackerMixin.ShouldDisplayQuest)
    currentTwin.ShouldDisplayQuest = function(_, quest)
        if quest.isTask or quest:IsDisabledForSession() then return false end
        local inPane = route(quest:GetID())
        -- The cards draw the pane's quests in the Camelot style.
        return inPane and Style.CurrentStyle() ~= "camelot"
    end

    -- The pane has no container header; this module's header is its title.
    currentTwin:SetHeader("Current Objectives")

    addon.Events.On(OWNER, "PLAYER_INSIDE_QUEST_BLOB_STATE_CHANGED", onBlob)
    addon.Events.On(OWNER, "QUEST_WATCH_UPDATE", onWatchUpdate)
    addon.Events.On(OWNER, "QUEST_LOG_UPDATE", onLogUpdate)
    addon.Events.On(OWNER, "QUEST_WATCH_LIST_CHANGED", onWatchListChanged)
    addon.Events.On(OWNER, "QUEST_REMOVED", onQuestGone)
    addon.Events.On(OWNER, "QUEST_TURNED_IN", onQuestGone)
    addon.Events.On(OWNER, "PLAYER_ENTERING_WORLD", function()
        seed("world")
        readDungeon("world")
    end)
    addon.Events.On(OWNER, "ZONE_CHANGED_NEW_AREA", function() readDungeon("zone") end)

    seed("install")
    readDungeon("install")
    -- Outside every dungeon at install, readDungeon saw no change; a list
    -- left by a logout inside one is taken off here.
    if not dungeon then syncWatches() end

    if OT.Fade then OT.Fade.Install() end
    if OT.Overflow then OT.Overflow.Install() end
    if OT.Cards then OT.Cards.Install() end
end

--------------------------------------------------------------------------------
-- /camelot tracker
--------------------------------------------------------------------------------

function Current.Dump(push)
    push("current: installed %s, enabled %s, on entering area %s, on progress %s, hold %ss",
        tostring(installed), tostring(Current.Enabled()), tostring(setting("onEnterArea")),
        tostring(setting("onProgress")), tostring(Style.HoldSeconds()))
    local added = 0
    for _ in pairs(addedWatches(false) or {}) do added = added + 1 end
    local swappedOut = 0
    for _ in pairs(swappedWatches(false) or {}) do swappedOut = swappedOut + 1 end
    if dungeon then
        local count = 0
        for _ in pairs(dungeon.quests) do count = count + 1 end
        push("dungeon: %s, %d quests, in its dungeon %s, %d watches added, %d swapped out, log entries %d",
            dungeon.name, count, tostring(setting("onDungeon")), added, swappedOut, logCount)
        for questID, how in pairs(dungeon.quests) do
            push("  %-6d %-40s %s%s", questID, questName(questID), how, isWatched(questID) and "" or string.format(" (not watched: %s)",
                declined[questID] and "untracked by hand" or unwatched[questID] or "not tried"))
        end
    else
        push("dungeon: outside, %d watches added, %d swapped out", added, swappedOut)
    end
    local n = 0
    for questID, e in pairs(entries) do
        n = n + 1
        push("  %-6d %-40s %s%s", questID, questName(questID), reasons(questID, e),
            e.objective and string.format("; last objective %d: %s", e.objective, tostring(e.after)) or "")
    end
    if n == 0 then push("  no entries") end
    push("pane log (%d):", #log)
    for _, line in ipairs(log) do push("  %s", line) end
    if OT.Fade then OT.Fade.Dump(push) end
    if OT.Flash then OT.Flash.Dump(push) end
    if OT.Overflow then OT.Overflow.Dump(push) end
    if OT.Cards then OT.Cards.Dump(push) end
    push("")
end
