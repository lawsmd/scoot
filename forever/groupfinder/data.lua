--------------------------------------------------------------------------------
-- forever/groupfinder/data.lua
-- The group finder's data layer: what the client says about categories,
-- activities, the player's listing, roles and instance locks, and the calls
-- that list, change and remove a group.
--
-- Blizzard's own finder keeps the same reads in util functions that are
-- globals once its addon loads. They are ported here and not called: several
-- read Blizzard's frames, and a call from this file would run that read on
-- the addon's path. Every call that carries a restriction (Search,
-- CreateListing, UpdateListing, RemoveListing) is made by a click and nowhere
-- else.
--
-- Panels subscribe to topics with Data.Listen; an event handler here does its
-- read and notifies.
--------------------------------------------------------------------------------

local addonName, addon = ...

local LFG = addon.ForeverGroupFinder

local Data = {}
LFG.Data = Data

local OWNER = LFG.OWNER
local LEVEL_FILTER_CVAR = "disableSuggestedLevelActivityFilter"

--------------------------------------------------------------------------------
-- Topics
--------------------------------------------------------------------------------

local listeners = {}

function Data.Listen(topic, fn)
    local list = listeners[topic]
    if not list then
        list = {}
        listeners[topic] = list
    end
    list[#list + 1] = fn
end

function Data.Notify(topic, ...)
    local list = listeners[topic]
    if not list then return end
    for i = 1, #list do
        list[i](...)
    end
end

--------------------------------------------------------------------------------
-- Plain reads
--------------------------------------------------------------------------------

-- The listing and result getters return a secret table under the chat
-- messaging lockdown; a secret is dropped here so no caller indexes one
local function plain(v)
    if v == nil then return nil end
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end
Data.plain = plain

function Data.Lockdown()
    local restricted = C_RestrictedActions and C_RestrictedActions.IsAddOnRestrictionActive
    local kind = Enum.AddOnRestrictionType and Enum.AddOnRestrictionType.Chat
    if not (restricted and kind) then return false end
    local ok, active = pcall(restricted, kind)
    return ok and plain(active) == true
end

--------------------------------------------------------------------------------
-- The group and who may edit its listing
--------------------------------------------------------------------------------

function Data.InHomeGroup()
    return IsInGroup(LE_PARTY_CATEGORY_HOME) and true or false
end

function Data.CanEdit()
    return not IsInGroup(LE_PARTY_CATEGORY_HOME) or UnitIsGroupLeader("player", LE_PARTY_CATEGORY_HOME)
end

function Data.CanPollRoles()
    return IsInGroup() and (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")) and true or false
end

--------------------------------------------------------------------------------
-- The listing
--------------------------------------------------------------------------------

function Data.HasEntry()
    return C_LFGList.HasActiveEntryInfo() and true or false
end

-- The live listing, or nil with none up or while it reads secret
function Data.Entry()
    if not C_LFGList.HasActiveEntryInfo() then return nil end
    local info = plain(C_LFGList.GetActiveEntryInfo())
    if type(info) ~= "table" then return nil end
    if type(plain(info.activityIDs)) ~= "table" then return nil end
    return info
end

--------------------------------------------------------------------------------
-- Activities
--------------------------------------------------------------------------------

function Data.ActivityInfo(activityID)
    return C_LFGList.GetActivityInfoTable(activityID)
end

-- The short name where the activity has one, as Blizzard's rows read
function Data.ActivityName(info)
    if not info then return "" end
    if info.shortName and info.shortName ~= "" then return info.shortName end
    return info.fullName or ""
end

local groupOfActivity = {}

function Data.ActivityGroup(activityID)
    local group = groupOfActivity[activityID]
    if group == nil then
        local info = C_LFGList.GetActivityInfoTable(activityID)
        if info then
            group = info.groupFinderActivityGroupID
            groupOfActivity[activityID] = group
        end
    end
    return group
end

function Data.LevelFilterOff()
    return GetCVarBool(LEVEL_FILTER_CVAR) and true or false
end

function Data.SetLevelFilterOff(off)
    -- Kept off core/profiles/cvars.lua: a passthrough to Blizzard's own checkbox, stored nowhere in the profile.
    SetCVar(LEVEL_FILTER_CVAR, off and "1" or "0")
end

-- The New Player Friendly check's state with no listing up, which Blizzard
-- keeps in a CVar of its own
function Data.NewPlayerFriendlyDefault()
    return GetCVarBool("lfgNewPlayerFriendly") and true or false
end

function Data.SetNewPlayerFriendlyDefault(on)
    -- Kept off core/profiles/cvars.lua: a passthrough to Blizzard's own checkbox, stored nowhere in the profile.
    pcall(SetCVar, "lfgNewPlayerFriendly", on and "1" or "0")
end

-- The voice mode a new listing starts on: the provider of the voice channel
-- the player is in, or none
function Data.DefaultVoiceMode()
    local modes = Enum.LFGEntryVoiceMode
    if not modes then return nil end
    local voice = C_VoiceChat
    if not (voice and voice.GetActiveChannelID and voice.GetActiveChannelID()) then return modes.None end
    local provider = voice.GetActiveVoiceProviderID and voice.GetActiveVoiceProviderID()
    local discord = Enum.VoiceProviderID and Enum.VoiceProviderID.Discord
    if discord and provider == discord then return modes.Discord end
    return modes.Legacy
end

-- A solo player or a leader who lists on Discord or the client's own voice
-- has the client's provider switched to match, as Blizzard's Post does
function Data.MatchVoiceProvider(voiceMode)
    local modes, providers = Enum.LFGEntryVoiceMode, Enum.VoiceProviderID
    if not (modes and providers) then return end
    if IsInGroup() and not UnitIsGroupLeader("player") then return end
    local provider
    if voiceMode == modes.Discord then
        provider = providers.Discord
    elseif voiceMode == modes.Legacy then
        provider = providers.Legacy
    end
    if provider and tonumber(GetCVar("voiceProvider")) ~= provider then
        -- Kept off core/profiles/cvars.lua: Blizzard's own write on a post, stored nowhere in the profile.
        pcall(SetCVar, "voiceProvider", provider)
    end
end

-- A category's activities, less those outside the player's suggested level
-- range unless the filter is off. An activity of the player's own listing is
-- kept whatever its range. groupID nil is every activity of the category, 0
-- those in no group.
function Data.FilteredActivities(categoryID, groupID)
    local activities = C_LFGList.GetAvailableActivities(categoryID, groupID) or {}
    if Data.LevelFilterOff() then return activities end
    local entry = Data.Entry()
    local own = {}
    if entry then
        for _, id in ipairs(entry.activityIDs) do own[id] = true end
    end
    local level = UnitLevel("player")
    for i = #activities, 1, -1 do
        local id = activities[i]
        if not own[id] then
            local info = C_LFGList.GetActivityInfoTable(id)
            if info then
                local low, high = info.minLevelSuggestion or 0, info.maxLevelSuggestion or 0
                if (low > 0 and low > level) or (high > 0 and high < level) then
                    table.remove(activities, i)
                end
            end
        end
    end
    return activities
end

-- The categories with at least one activity left after the filter, in the
-- client's order: { id, name, autoChoose, icon }
function Data.Categories()
    local out = {}
    for _, categoryID in ipairs(C_LFGList.GetAvailableCategories() or {}) do
        if #Data.FilteredActivities(categoryID) > 0 then
            local info = C_LFGList.GetLfgCategoryInfo(categoryID)
            if info then
                out[#out + 1] = {
                    id = categoryID,
                    name = info.name,
                    autoChoose = info.autoChooseActivity and true or false,
                    icon = LFG.CATEGORY_ICONS[categoryID] or LFG.CATEGORY_ICON_DEFAULT,
                }
            end
        end
    end
    return out
end

function Data.CategoryInfo(categoryID)
    return categoryID and C_LFGList.GetLfgCategoryInfo(categoryID) or nil
end

local function activityRow(activityID)
    local info = C_LFGList.GetActivityInfoTable(activityID)
    if not info then return nil end
    return {
        activityID = activityID,
        name = Data.ActivityName(info),
        minLevel = info.minLevelSuggestion or 0,
        maxLevel = info.maxLevelSuggestion or 0,
        orderIndex = info.orderIndex or 0,
    }
end

-- A category's activities for the Listing tab's tree: those in no group,
-- then each group with its own, as plain rows. multi says whether a group
-- carries an expand button; a group's suggested says whether any of its
-- activities fits the player's level, which decides whether it starts open.
function Data.ActivityTree(categoryID)
    local tree = { loose = {}, groups = {}, multi = false }
    if not categoryID then return tree end
    for _, id in ipairs(Data.FilteredActivities(categoryID, 0)) do
        tree.loose[#tree.loose + 1] = activityRow(id)
    end
    local level = UnitLevel("player")
    local groups = C_LFGList.GetAvailableActivityGroups(categoryID) or {}
    tree.multi = #groups > 1
    for _, groupID in ipairs(groups) do
        local ids = Data.FilteredActivities(categoryID, groupID)
        if #ids > 0 then
            local name, orderIndex = C_LFGList.GetActivityGroupInfo(groupID)
            local group = { groupID = groupID, name = name or "", orderIndex = orderIndex or 0,
                activities = {}, suggested = false }
            for _, id in ipairs(ids) do
                local row = activityRow(id)
                if row then
                    group.activities[#group.activities + 1] = row
                    if level and row.minLevel <= level and level <= row.maxLevel then
                        group.suggested = true
                    end
                end
            end
            tree.groups[#tree.groups + 1] = group
        end
    end
    return tree
end

-- The order of activities inside one parent, as Blizzard's tree sorts them
function Data.ActivityBefore(a, b)
    if a.orderIndex ~= b.orderIndex then return a.orderIndex > b.orderIndex end
    if a.maxLevel ~= b.maxLevel then
        if a.maxLevel == 0 or b.maxLevel == 0 then return a.maxLevel == 0 end
        return a.maxLevel > b.maxLevel
    end
    if a.minLevel ~= b.minLevel then return a.minLevel > b.minLevel end
    return strcmputf8i(a.name, b.name) < 0
end

-- Activity ids by their group, each list in the order of Blizzard's locked
-- view: order index, then name, then id. Group 0 holds those in no group.
function Data.ActivitiesByGroup(activityIDs)
    local byGroup = {}
    for _, id in ipairs(activityIDs) do
        local info = C_LFGList.GetActivityInfoTable(id)
        if info then
            local group = info.groupFinderActivityGroupID or 0
            byGroup[group] = byGroup[group] or {}
            table.insert(byGroup[group], id)
        end
    end
    for _, ids in pairs(byGroup) do
        table.sort(ids, function(a, b)
            local ia, ib = C_LFGList.GetActivityInfoTable(a), C_LFGList.GetActivityInfoTable(b)
            if ia.orderIndex ~= ib.orderIndex then return ia.orderIndex < ib.orderIndex end
            local na, nb = Data.ActivityName(ia), Data.ActivityName(ib)
            if na ~= nb then return strcmputf8i(na, nb) < 0 end
            return a < b
        end)
    end
    local groupIDs = {}
    for group in pairs(byGroup) do groupIDs[#groupIDs + 1] = group end
    table.sort(groupIDs, function(a, b)
        local na, oa = C_LFGList.GetActivityGroupInfo(a)
        local nb, ob = C_LFGList.GetActivityGroupInfo(b)
        if oa and ob and oa ~= ob then return oa < ob end
        if na and nb and na ~= nb then return strcmputf8i(na, nb) < 0 end
        return a < b
    end)
    return byGroup, groupIDs
end

function Data.MaxActivities()
    local consts = Constants and Constants.LFGConstsExposed
    return (consts and consts.GROUP_FINDER_MAX_ACTIVITY_CAPACITY) or LFG.MAX_ACTIVITIES_FALLBACK
end

--------------------------------------------------------------------------------
-- Roles
--------------------------------------------------------------------------------

-- The roles the player lists with while solo: { tank, healer, dps }
function Data.Roles()
    local roles = C_LFGListRoles and C_LFGListRoles.GetRoles and C_LFGListRoles.GetRoles()
    return type(roles) == "table" and roles or {}
end

-- False when the client refuses the set
function Data.SetRoles(roles)
    if not (C_LFGListRoles and C_LFGListRoles.SetRoles) then return false end
    return C_LFGListRoles.SetRoles({
        tank = roles.tank and true or false,
        healer = roles.healer and true or false,
        dps = roles.dps and true or false,
    }) and true or false
end

-- Which of the three the player's class may fill, keyed by role token
function Data.ClassRoles()
    local tank, healer, dps = UnitGetAvailableRoles("player")
    return { TANK = tank and true or false, HEALER = healer and true or false, DAMAGER = dps and true or false }
end

--------------------------------------------------------------------------------
-- Instance locks
--------------------------------------------------------------------------------

local locks = {}

local function fetchLocks()
    locks = {}
    for i = 1, GetNumSavedInstances() or 0 do
        local _, _, _, difficultyID, _, _, _, _, _, _, total, completed, _, mapID = GetSavedInstanceInfo(i)
        locks[#locks + 1] = {
            mapID = mapID,
            difficultyID = difficultyID,
            redirectedDifficultyID = C_RaidLocks and C_RaidLocks.GetRedirectedDifficultyID
                and C_RaidLocks.GetRedirectedDifficultyID(mapID, difficultyID) or nil,
            completed = completed or 0,
            total = total or 0,
        }
    end
end

function Data.RequestLocks()
    RequestRaidInfo()
end

-- The bosses down and the total for an activity the player is saved to, or
-- nil with no lock in progress
function Data.LockFor(activityID)
    local info = C_LFGList.GetActivityInfoTable(activityID)
    if not (info and info.mapID and info.difficultyID) then return nil end
    for _, lock in ipairs(locks) do
        if lock.mapID == info.mapID and lock.completed > 0 and lock.total > 0 then
            local same = info.difficultyID == lock.difficultyID
            local shared = lock.redirectedDifficultyID == info.redirectedDifficultyID
            if same or shared then return lock.completed, lock.total end
        end
    end
    return nil
end

--------------------------------------------------------------------------------
-- Listing, changing and removing: each from a click
--------------------------------------------------------------------------------

-- Set before each call and cleared by the listing's own event, so the
-- window tells a change the player made from one the group's leader made
-- on another client
Data.pending = false

function Data.CreateListing(activityIDs, newPlayerFriendly, generalPlaystyle, voiceMode)
    Data.pending = true
    return C_LFGList.CreateListing({
        activityIDs = activityIDs,
        newPlayerFriendly = newPlayerFriendly and true or false,
        generalPlaystyle = generalPlaystyle,
        voiceMode = voiceMode,
    })
end

-- Blizzard's own update leaves the playstyle out, and a playstyle changed on
-- a live listing is lost there; it is sent here
function Data.UpdateListing(activityIDs, newPlayerFriendly, generalPlaystyle, voiceMode)
    Data.pending = true
    return C_LFGList.UpdateListing({
        activityIDs = activityIDs,
        newPlayerFriendly = newPlayerFriendly and true or false,
        generalPlaystyle = generalPlaystyle,
        voiceMode = voiceMode,
    })
end

function Data.RemoveListing()
    Data.pending = true
    C_LFGList.RemoveListing()
end

--------------------------------------------------------------------------------
-- Searching: from a click
--------------------------------------------------------------------------------

Data.searching = false
Data.searchFailed = false

local SEARCH_TIMEOUT = 15
local searchToken = 0

-- A category's listings, narrowed to the given activities or to all the
-- category's with none given. False while a search is out or with no
-- category. The client answers with an event; a search it never answers is
-- given up after SEARCH_TIMEOUT so the Refresh button comes back.
function Data.Search(categoryID, activityIDs)
    if Data.searching then return false end
    if not categoryID or categoryID <= 0 then return false end
    if not activityIDs or #activityIDs == 0 then
        activityIDs = Data.FilteredActivities(categoryID)
    end
    C_LFGList.Search(categoryID, 0, 0, nil, false, nil, activityIDs)
    Data.searching = true
    Data.searchFailed = false
    searchToken = searchToken + 1
    local token = searchToken
    C_Timer.After(SEARCH_TIMEOUT, function()
        if Data.searching and token == searchToken then
            Data.searching = false
            Data.searchFailed = true
            Data.Notify("results")
        end
    end)
    Data.Notify("search")
    return true
end

local EXPECT_TIMEOUT = 5

-- A search Blizzard's hidden frame makes from its own event handler: a new
-- listing's, and the one LFG_LIST_SHOW_SEARCH asks for. No call is made
-- here; the flag shows the spinner until the answer comes, and is dropped
-- after EXPECT_TIMEOUT where Blizzard's frame made no search.
function Data.ExpectSearch()
    if Data.searching or not LFGBrowseFrame then return false end
    Data.searching = true
    Data.searchFailed = false
    searchToken = searchToken + 1
    local token = searchToken
    C_Timer.After(EXPECT_TIMEOUT, function()
        if Data.searching and token == searchToken then
            Data.searching = false
            Data.Notify("results")
        end
    end)
    Data.Notify("search")
    return true
end

-- One result, or nil where the client has none or it reads secret
function Data.Result(resultID)
    if not resultID then return nil end
    local info = plain(C_LFGList.GetSearchResultInfo(resultID))
    if type(info) ~= "table" or type(plain(info.activityIDs)) ~= "table" then return nil end
    return info
end

function Data.ResultLeader(resultID)
    local info = plain(C_LFGList.GetSearchResultLeaderInfo(resultID))
    return type(info) == "table" and info or nil
end

function Data.ResultMember(resultID, index)
    local info = plain(C_LFGList.GetSearchResultPlayerInfo(resultID, index))
    return type(info) == "table" and info or nil
end

function Data.ResultCounts(resultID)
    local counts = plain(C_LFGList.GetSearchResultMemberCounts(resultID))
    return type(counts) == "table" and counts or nil
end

local function contains(list, value)
    for i = 1, #list do
        if list[i] == value then return true end
    end
    return false
end

-- The player's listed activities that a result shares
function Data.MatchingActivities(info, entry)
    local matching = {}
    if entry then
        for _, id in ipairs(entry.activityIDs) do
            if contains(info.activityIDs, id) then matching[#matching + 1] = id end
        end
    end
    return matching
end

local DUNGEON_ROLES_EXPECTED = { TANK = 1, HEALER = 1, DAMAGER = 3 }

-- Blizzard's order (LFGBrowseUtil_SortSearchResults): the player's own
-- listing, then results sharing an activity with it, then groups before solo
-- players (solo players first for a player in a group), then by role, size
-- and age.
local function sortResults(results)
    local entry = Data.Entry()
    local dungeonRoles = false
    if entry then
        for _, id in ipairs(entry.activityIDs) do
            local activity = C_LFGList.GetActivityInfoTable(id)
            if activity and activity.useDungeonRoleExpectations then
                dungeonRoles = true
                break
            end
        end
    end
    local groupCounts = GetGroupMemberCounts and GetGroupMemberCounts() or nil
    local grouped = IsInGroup()
    local playerRoles = Data.Roles()

    local roleOrder = { "TANK", "HEALER", "DAMAGER" }
    if dungeonRoles and groupCounts then
        for _, role in ipairs({ "TANK", "HEALER", "DAMAGER" }) do
            if (groupCounts[role] or 0) >= DUNGEON_ROLES_EXPECTED[role] then
                for i = #roleOrder, 1, -1 do
                    if roleOrder[i] == role then table.remove(roleOrder, i) end
                end
                roleOrder[#roleOrder + 1] = role
            end
        end
    end

    -- Each result read once, so the comparator sees one answer per result
    local rows = {}
    for _, id in ipairs(results) do
        local info = Data.Result(id)
        if info then
            local counts = Data.ResultCounts(id) or {}
            local row = {
                hasSelf = info.hasSelf and true or false,
                matching = #Data.MatchingActivities(info, entry) > 0,
                solo = info.numMembers == 1,
                members = info.numMembers or 0,
                age = info.age or 0,
                counts = counts,
            }
            row.canTank = (counts.TANK_REMAINING or 0) > 0 and playerRoles.tank and true or false
            row.canHeal = (counts.HEALER_REMAINING or 0) > 0 and playerRoles.healer and true or false
            row.hasSlot = row.canTank or row.canHeal
                or ((counts.DAMAGER_REMAINING or 0) > 0 and playerRoles.dps and true or false)
            rows[id] = row
        end
    end

    table.sort(results, function(a, b)
        local l, r = rows[a], rows[b]
        if not (l and r) then
            if l or r then return l ~= nil end
            return a < b
        end
        if l.hasSelf ~= r.hasSelf then return l.hasSelf end
        if entry and l.matching ~= r.matching then return l.matching end
        if l.solo ~= r.solo then
            if grouped then return l.solo end
            return r.solo
        end
        if l.solo then
            for _, role in ipairs(roleOrder) do
                local lc = l.counts["LEADER_ROLE_" .. role] and true or false
                local rc = r.counts["LEADER_ROLE_" .. role] and true or false
                if lc ~= rc then return lc end
                if lc then break end
            end
        else
            if l.hasSlot ~= r.hasSlot then return l.hasSlot end
            if l.members ~= r.members then return l.members > r.members end
            if l.canTank ~= r.canTank then return l.canTank end
            if l.canHeal ~= r.canHeal then return l.canHeal end
        end
        if l.age ~= r.age then return l.age > r.age end
        return a < b
    end)
end

-- The count the client reports and the result ids in Blizzard's order; none
-- while the list reads secret
function Data.Results()
    local total, results = C_LFGList.GetFilteredSearchResults()
    total, results = plain(total), plain(results)
    if type(total) ~= "number" or type(results) ~= "table" then return 0, {} end
    sortResults(results)
    return total, results
end

-- How a result's members are drawn: the most telling display type among its
-- activities, and the largest group any of them takes
local DISPLAY_PRIORITY
function Data.BestDisplayType(activityIDs)
    local types = Enum.LFGListDisplayType
    if not types then return nil, 0 end
    DISPLAY_PRIORITY = DISPLAY_PRIORITY or {
        [types.Comment] = 6, [types.RoleCount] = 5, [types.PlayerCount] = 4,
        [types.RoleEnumerate] = 3, [types.ClassEnumerate] = 2, [types.HideAll] = 1,
    }
    local best, bestPriority, maxPlayers = nil, 0, 0
    for _, id in ipairs(activityIDs) do
        local info = C_LFGList.GetActivityInfoTable(id)
        if info then
            local priority = DISPLAY_PRIORITY[info.displayType]
            if priority and priority > bestPriority then
                best, bestPriority = info.displayType, priority
            end
            if (info.maxNumPlayers or 0) > maxPlayers then maxPlayers = info.maxNumPlayers end
        end
    end
    return best, maxPlayers
end

-- A solo listing may be invited by a player who is alone or may invite for
-- their group
function Data.CanInviteResult(resultID)
    local info = Data.Result(resultID)
    if not info or info.numMembers ~= 1 then return false end
    return not IsInGroup() or UnitIsGroupLeader("player") or UnitIsGroupAssistant("player") or false
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

local Events = addon.Events

Events.On(OWNER, "LFG_LIST_SEARCH_RESULTS_RECEIVED", function()
    Data.searching = false
    Data.searchFailed = false
    Data.Notify("results")
end)

Events.On(OWNER, "LFG_LIST_SEARCH_FAILED", function()
    Data.searching = false
    Data.searchFailed = true
    Data.Notify("results")
end)

Events.On(OWNER, "LFG_LIST_SEARCH_RESULT_UPDATED", function(_, resultID)
    Data.Notify("resultUpdated", resultID)
end)

-- Another part of the client asks for the Browse tab on a set of activities
Events.On(OWNER, "LFG_LIST_SHOW_SEARCH", function(_, activityIDs)
    local ids
    if type(activityIDs) == "table" then
        ids = {}
        for i = 1, #activityIDs do ids[i] = activityIDs[i] end
    end
    Data.Notify("showSearch", ids)
end)

-- Blizzard's finder does the next three itself once it is loaded: it asks
-- for the activities a new level opens, and tells the leader a listing
-- lapsed. They are done here only while it is not.
Events.On(OWNER, "PLAYER_LEVEL_UP", function()
    if not LFGParentFrame then C_LFGList.RequestAvailableActivities() end
end)

local function expired(which)
    if LFGListingFrame then return end
    if UnitIsGroupLeader("player", LE_PARTY_CATEGORY_HOME) then StaticPopup_Show(which) end
end

Events.On(OWNER, "LFG_LIST_ENTRY_EXPIRED_TOO_MANY_PLAYERS", function()
    expired("LFG_LIST_ENTRY_EXPIRED_TOO_MANY_PLAYERS")
end)

Events.On(OWNER, "LFG_LIST_ENTRY_EXPIRED_TIMEOUT", function()
    expired("LFG_LIST_ENTRY_EXPIRED_TIMEOUT")
end)

Events.On(OWNER, "REPORT_PLAYER_RESULT", function(_, success, reportType)
    local posting = Enum.ReportType and Enum.ReportType.GroupFinderPosting
    if success and posting and reportType == posting then Data.Notify("results") end
end)

Events.On(OWNER, "LFG_LIST_ACTIVE_ENTRY_UPDATE", function(_, createdNew)
    local wasPending = Data.pending
    Data.pending = false
    Data.Notify("entry", createdNew and true or false, wasPending)
end)

Events.On(OWNER, "LFG_LIST_AVAILABILITY_UPDATE", function()
    groupOfActivity = {}
    Data.Notify("availability")
end)

Events.On(OWNER, "LFG_LIST_ROLE_UPDATE", function()
    Data.Notify("roles")
end)

Events.On(OWNER, "GROUP_ROSTER_UPDATE", function()
    Data.Notify("group")
end)

Events.On(OWNER, "PARTY_LEADER_CHANGED", function()
    Data.Notify("group")
end)

Events.On(OWNER, "GROUP_LEFT", function(_, partyCategory)
    Data.Notify("groupLeft", partyCategory == LE_PARTY_CATEGORY_HOME)
end)

Events.On(OWNER, "PLAYER_ROLES_ASSIGNED", function()
    Data.Notify("groupRoles")
end)

Events.On(OWNER, "UPDATE_INSTANCE_INFO", function()
    fetchLocks()
    Data.Notify("locks")
end)

Events.On(OWNER, "CVAR_UPDATE", function(_, name)
    if name == LEVEL_FILTER_CVAR then Data.Notify("filter") end
end)

Events.On(OWNER, "ADDON_RESTRICTION_STATE_CHANGED", function()
    Data.Notify("lockdown")
end)
