--------------------------------------------------------------------------------
-- core/components/groupfinder/core.lua
-- The Group Finder component: the data layer of the Scoot-drawn Premade
-- Groups window.
--
-- Blizzard's LFGListFrame stays alive and invisible inside PVEFrame and keeps
-- every piece of state: the active panel, the selected category and filters,
-- the search parameters, and the text boxes the C side reads. Scoot's window
-- (ui/v2/groupfinder/) draws a view of that state. The window's buttons run
-- Blizzard's own handlers, so each click makes one protected call with a
-- hardware event behind it, and Blizzard assembles the Search arguments from
-- its own state. This file owns the reads: the results copy and its sort,
-- the declines, the application status words, the throttle, and the guards
-- that keep a secret value out of a comparison.
--
-- The component registers only while the Group Finder module is on, which is
-- the zero-touch gate for the whole feature: no hook and no event until the
-- player turns it on.
--------------------------------------------------------------------------------

local addonName, addon = ...

local GF = {}
addon.GroupFinder = GF

-- Seconds between two searches; the server answers a faster second search
-- with a throttled failure
local SEARCH_COOLDOWN = 3

-- Blizzard's cap on concurrent applications, a local in its own file
local MAX_APPLICATIONS = 5

-- Two more numbers Blizzard keeps local to its own file: the Dungeons
-- category, which takes the advanced filter and the recommended-only
-- search, and the most auto-complete rows shown
GF.DUNGEONS_CATEGORY = 2
GF.MAX_AUTOCOMPLETE = 6

GF.state = {
    results = {},        -- the sorted search result ids, Scoot's own copy
    totalResults = 0,
    declines = {},       -- partyGUID -> the declined status, as LFGListFrame keeps it
    searching = false,
    searchFailed = false,
    failReason = nil,
    lastSearchAt = 0,
    selectedResult = nil,
    lockdown = false,
}

--------------------------------------------------------------------------------
-- Listeners: the window files register for a topic and the handlers below
-- raise it. The window may not exist, so every call is a bare test.
--------------------------------------------------------------------------------

local listeners = {}

function GF.Listen(topic, fn)
    listeners[topic] = listeners[topic] or {}
    table.insert(listeners[topic], fn)
end

function GF.Notify(topic, ...)
    local list = listeners[topic]
    if not list then return end
    for _, fn in ipairs(list) do
        fn(...)
    end
end

--------------------------------------------------------------------------------
-- Guards. type() and issecretvalue() are the only operations legal on a
-- secret; a field that fails them reads as absent and the row draws without it.
--------------------------------------------------------------------------------

local function plain(v)
    if type(v) == "nil" then return nil end
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end
GF.plain = plain

local function plainNumber(v)
    local n = plain(v)
    if type(n) == "number" then return n end
    return nil
end
GF.plainNumber = plainNumber

local function plainBool(v)
    local b = plain(v)
    if type(b) == "boolean" then return b end
    return nil
end
GF.plainBool = plainBool

-- A client string by its global name, read at the moment of use
function GF.Str(key, fallback)
    local s = _G[key]
    if type(s) == "string" then return s end
    return fallback or key
end
local Str = GF.Str

--------------------------------------------------------------------------------
-- Reads
--------------------------------------------------------------------------------

function GF.ResultInfo(id)
    if not id then return nil end
    if C_LFGList.HasSearchResultInfo and not C_LFGList.HasSearchResultInfo(id) then return nil end
    local ok, info = pcall(C_LFGList.GetSearchResultInfo, id)
    if ok and type(info) == "table" then return info end
    return nil
end

-- id, appStatus, pendingStatus, appDuration; a stale id reads as no application
function GF.Application(id)
    if not id then return nil, "none", nil, nil end
    local ok, appID, status, pending, duration = pcall(C_LFGList.GetApplicationInfo, id)
    if not ok then return nil, "none", nil, nil end
    return appID, plain(status) or "none", plain(pending), plainNumber(duration)
end

function GF.MemberCounts(id)
    if not id then return nil end
    local ok, counts = pcall(C_LFGList.GetSearchResultMemberCounts, id)
    if ok and type(counts) == "table" then return counts end
    return nil
end

function GF.ActivityID(info)
    local ids = info and plain(info.activityIDs)
    if type(ids) ~= "table" then return nil end
    return plainNumber(ids[1])
end

function GF.ActivityInfo(activityID)
    if not activityID then return nil end
    local ok, t = pcall(C_LFGList.GetActivityInfoTable, activityID)
    if ok and type(t) == "table" then return t end
    return nil
end

function GF.ActivityName(info)
    local activityID = GF.ActivityID(info)
    if not activityID then return nil end
    local ok, name = pcall(C_LFGList.GetActivityFullName, activityID, nil, plainBool(info.isWarMode))
    if ok and type(name) == "string" then return name end
    return nil
end

-- The row's playstyle line, from the enum's own strings; the protected
-- GetPlaystyleString is never called
function GF.GeneralPlaystyleString(value)
    local P = Enum and Enum.LFGEntryGeneralPlaystyle
    if not P or value == nil then return "" end
    if value == P.Learning then return Str("GROUP_FINDER_GENERAL_PLAYSTYLE1", "") end
    if value == P.FunRelaxed then return Str("GROUP_FINDER_GENERAL_PLAYSTYLE2", "") end
    if value == P.FunSerious then return Str("GROUP_FINDER_GENERAL_PLAYSTYLE3", "") end
    if value == P.Expert then return Str("GROUP_FINDER_GENERAL_PLAYSTYLE4", "") end
    return ""
end

function GF.IsDeclined(status)
    return status == "declined" or status == "declined_delisted" or status == "declined_full"
end

function GF.IsStatusInactive(status)
    return status == "cancelled" or status == "failed" or status == "timedout"
        or status == "invitedeclined" or GF.IsDeclined(status)
end

-- What a row says for an application: the word, whether it is lit, and
-- whether the countdown and the cancel show, decided in the order Blizzard's
-- row decides them. nil when the result carries no application.
function GF.StatusLine(appStatus, pendingStatus)
    if appStatus == "none" and pendingStatus == nil then return nil end
    if pendingStatus == "applied" and C_LFGList.GetRoleCheckInfo and C_LFGList.GetRoleCheckInfo() then
        return Str("LFG_LIST_ROLE_CHECK", "Role check"), false, false
    end
    if pendingStatus == "cancelled" or appStatus == "cancelled" or appStatus == "failed" then
        return Str("LFG_LIST_APP_CANCELLED", "Cancelled"), false, false
    end
    if GF.IsDeclined(appStatus) then
        local key = appStatus == "declined_full" and "LFG_LIST_APP_FULL" or "LFG_LIST_APP_DECLINED"
        return Str(key, "Declined"), false, false
    end
    if appStatus == "timedout" then
        return Str("LFG_LIST_APP_TIMED_OUT", "Timed out"), false, false
    end
    if appStatus == "invited" then
        return Str("LFG_LIST_APP_INVITED", "Invited"), true, false
    end
    if appStatus == "inviteaccepted" then
        return Str("LFG_LIST_APP_INVITE_ACCEPTED", "Accepted"), true, false
    end
    if appStatus == "invitedeclined" then
        return Str("LFG_LIST_APP_INVITE_DECLINED", "Invite declined"), false, false
    end
    return Str("LFG_LIST_PENDING", "Pending"), true, true
end

-- The four conditions of Blizzard's own CanSelectResult
function GF.CanSelect(id)
    local _, status, pending = GF.Application(id)
    if status ~= "none" or pending ~= nil then return false end
    local info = GF.ResultInfo(id)
    if not info then return false end
    if plainBool(info.isDelisted) then return false end
    local guid = plain(info.partyGUID)
    if guid and GF.state.declines[guid] then return false end
    return true
end

-- The reason Sign Up is off, in the order Blizzard's button tests them, or
-- nil when it is on
-- skipSelection true leaves out the last check, for the button's tooltip:
-- an empty selection is plain to see and says nothing worth a line
function GF.SignUpBlock(skipSelection)
    local home = LE_PARTY_CATEGORY_HOME
    local message = LFGListUtil_GetActiveQueueMessage and LFGListUtil_GetActiveQueueMessage(true)
    if message then return message end
    if LFGListUtil_IsAppEmpowered and not LFGListUtil_IsAppEmpowered() then
        return Str("LFG_LIST_APP_UNEMPOWERED", "Only the leader can sign up")
    end
    if IsInGroup(home) and C_LFGList.IsCurrentlyApplying and C_LFGList.IsCurrentlyApplying() then
        return Str("LFG_LIST_APP_CURRENTLY_APPLYING", "Applying")
    end
    local _, numActive = C_LFGList.GetNumApplications()
    if plainNumber(numActive) and numActive >= MAX_APPLICATIONS then
        return string.format(Str("LFG_LIST_HIT_MAX_APPLICATIONS", "At most %d applications"), MAX_APPLICATIONS)
    end
    if GetNumGroupMembers(home) > (MAX_PARTY_MEMBERS or 4) + 1 then
        return Str("LFG_LIST_MAX_MEMBERS", "Too many members")
    end
    local tank, healer, dps = C_LFGList.GetAvailableRoles()
    if not (tank or healer or dps) then
        return Str("LFG_LIST_MUST_CHOOSE_SPEC", "Choose a specialization")
    end
    if GroupHasOfflineMember and GroupHasOfflineMember(home) then
        return Str("LFG_LIST_OFFLINE_MEMBER", "A member is offline")
    end
    if not skipSelection and not GF.state.selectedResult then
        return Str("LFG_LIST_SELECT_A_SEARCH_RESULT", "Select a group")
    end
    return nil
end

-- The leaver badge beside Sign Up: the player is flagged and the result is a
-- Mythic+ activity
function GF.IsLeaverFlagged(id)
    if not (C_InstanceLeaver and C_InstanceLeaver.IsPlayerLeaver and C_InstanceLeaver.IsPlayerLeaver()) then
        return false
    end
    local info = GF.ResultInfo(id)
    local ids = info and plain(info.activityIDs)
    if type(ids) ~= "table" then return false end
    for _, activityID in ipairs(ids) do
        local activity = GF.ActivityInfo(plainNumber(activityID))
        if activity and activity.isMythicPlusActivity then return true end
    end
    return false
end

--------------------------------------------------------------------------------
-- The results copy and its order: Blizzard's comparator over Scoot's records,
-- each read once per rebuild so no secret reaches a comparison
--------------------------------------------------------------------------------

local ROLE_REMAINING_KEY
local function RoleRemainingKey()
    if not (GetSpecializationRoleEnum and C_SpecializationInfo and C_SpecializationInfo.GetSpecialization) then
        return nil
    end
    if not ROLE_REMAINING_KEY then
        local roles = Enum and Enum.LFGRole
        if not roles then return nil end
        ROLE_REMAINING_KEY = {
            [roles.Tank] = "TANK_REMAINING",
            [roles.Healer] = "HEALER_REMAINING",
            [roles.Damage] = "DAMAGER_REMAINING",
        }
    end
    local ok, role = pcall(GetSpecializationRoleEnum, C_SpecializationInfo.GetSpecialization())
    if not ok or role == nil then return nil end
    return ROLE_REMAINING_KEY[role]
end

local function HasSlotForPlayer(id, key)
    if not key then return false end
    local counts = GF.MemberCounts(id)
    local n = counts and plainNumber(counts[key]) or 0
    return n > 0
end

local function Record(id, roleKey, warModeDesired)
    local info = GF.ResultInfo(id) or {}
    local _, status = GF.Application(id)
    local guid = plain(info.partyGUID)
    local declined = GF.IsDeclined(status) or (guid ~= nil and GF.state.declines[guid] ~= nil)
    return {
        id = id,
        declined = declined and true or false,
        slot = HasSlotForPlayer(id, roleKey),
        bnet = plainNumber(info.numBNetFriends) or 0,
        char = plainNumber(info.numCharFriends) or 0,
        guild = plainNumber(info.numGuildMates) or 0,
        warMode = plainBool(info.isWarMode),
        warMatch = plainBool(info.isWarMode) == warModeDesired,
    }
end

local function Compare(a, b)
    if a.declined ~= b.declined then return b.declined end
    if a.slot ~= b.slot then return a.slot end
    if a.bnet ~= b.bnet then return a.bnet > b.bnet end
    if a.char ~= b.char then return a.char > b.char end
    if a.guild ~= b.guild then return a.guild > b.guild end
    if a.warMode ~= b.warMode then return a.warMatch end
    return a.id < b.id
end

function GF.RebuildResults()
    local total, ids = C_LFGList.GetFilteredSearchResults()
    if type(ids) ~= "table" then ids = {} end
    local roleKey = RoleRemainingKey()
    local warModeDesired = C_PvP and C_PvP.IsWarModeDesired and C_PvP.IsWarModeDesired() or false

    local records, seen = {}, {}
    for _, id in ipairs(ids) do
        local plainID = plainNumber(id)
        if plainID and not seen[plainID] then
            seen[plainID] = true
            records[#records + 1] = Record(plainID, roleKey, warModeDesired)
        end
    end
    table.sort(records, Compare)

    local results = {}
    for i, record in ipairs(records) do results[i] = record.id end

    -- The player's applications the search did not return, after the sort,
    -- as Blizzard's panel appends them
    local apps = C_LFGList.GetApplications and C_LFGList.GetApplications()
    if type(apps) == "table" then
        for _, id in ipairs(apps) do
            local plainID = plainNumber(id)
            if plainID and not seen[plainID] then
                seen[plainID] = true
                results[#results + 1] = plainID
            end
        end
    end

    GF.state.results = results
    GF.state.totalResults = plainNumber(total) or #results
    return results
end

--------------------------------------------------------------------------------
-- The throttle and the lockdown
--------------------------------------------------------------------------------

function GF.SearchAllowed()
    return (GetTime() - GF.state.lastSearchAt) >= SEARCH_COOLDOWN
end

function GF.SearchCooldownLeft()
    return math.max(0, SEARCH_COOLDOWN - (GetTime() - GF.state.lastSearchAt))
end

-- The host's hook on Blizzard's DoSearch calls this, so a search from any
-- button, from Enter in the box or from the clear button is noted once
function GF.NoteSearch()
    local state = GF.state
    state.lastSearchAt = GetTime()
    state.searching = true
    state.searchFailed = false
    state.failReason = nil
    state.selectedResult = nil
    GF.Notify("searching")
end

local function RestrictionType()
    return Enum and Enum.AddOnRestrictionType and Enum.AddOnRestrictionType.Chat
end

local function ReadLockdown()
    local kind = RestrictionType()
    if kind == nil or not (C_RestrictedActions and C_RestrictedActions.IsAddOnRestrictionActive) then
        return false
    end
    local ok, active = pcall(C_RestrictedActions.IsAddOnRestrictionActive, kind)
    return ok and active == true
end

function GF.IsLockedDown()
    return GF.state.lockdown
end

--------------------------------------------------------------------------------
-- Registration
--------------------------------------------------------------------------------

local QUEUE_MESSAGE_EVENTS = {
    "UPDATE_BATTLEFIELD_STATUS", "LFG_UPDATE", "LFG_PROPOSAL_UPDATE", "LFG_PROPOSAL_FAILED",
    "LFG_PROPOSAL_SUCCEEDED", "LFG_PROPOSAL_SHOW", "LFG_QUEUE_STATUS_UPDATE",
}

local BUTTON_EVENTS = {
    "GROUP_ROSTER_UPDATE", "PARTY_LEADER_CHANGED", "PLAYER_SPECIALIZATION_CHANGED", "UNIT_CONNECTION",
}

-- The topic carries whether a search was waiting on these results, which
-- is what the panel's redraw plays on; an update outside a search is quiet
local function OnResultsReceived()
    local state = GF.state
    local wasSearching = state.searching
    state.searching = false
    state.searchFailed = false
    state.failReason = nil
    GF.RebuildResults()
    GF.Notify("results", wasSearching)
end

local function OnSearchFailed(_, reason)
    local state = GF.state
    state.searching = false
    state.searchFailed = true
    state.failReason = plain(reason)
    if state.failReason == "throttled" then
        state.lastSearchAt = GetTime()
    end
    GF.Notify("failed")
end

-- A decline is remembered by party, as LFGListFrame remembers it, so the
-- group stays at the bottom of the next search; a declined row is redrawn
-- in place, any other status re-reads and re-sorts, as Blizzard's does
local function OnApplicationStatus(_, id, newStatus)
    id = plainNumber(id)
    newStatus = plain(newStatus)
    if GF.IsDeclined(newStatus) then
        local info = GF.ResultInfo(id)
        local guid = info and plain(info.partyGUID)
        if guid then GF.state.declines[guid] = newStatus end
        GF.Notify("status", id, newStatus)
        return
    end
    GF.RebuildResults()
    GF.Notify("results")
    GF.Notify("status", id, newStatus)
end

local function OnRestriction(_, kind, newState)
    if kind ~= RestrictionType() then return end
    local inactive = Enum and Enum.AddOnRestrictionState and Enum.AddOnRestrictionState.Inactive
    GF.state.lockdown = newState ~= inactive
    GF.Notify("lockdown")
end

addon:RegisterComponentInitializer(function(self)
    local Component = addon.ComponentPrototype
    local component = Component:New({
        id = "groupfinder",
        name = "Group Finder",
        settings = {},
    })
    self:RegisterComponent(component)
    GF.component = component
    GF.state.lockdown = ReadLockdown()

    component:On("LFG_LIST_AVAILABILITY_UPDATE", function() GF.Notify("categories") end)
    component:On("LFG_LIST_SEARCH_RESULTS_RECEIVED", OnResultsReceived)
    component:On("LFG_LIST_UPDATE_SEARCH_RESULTS", OnResultsReceived)
    component:On("LFG_LIST_SEARCH_RESULT_UPDATED", function(_, id) GF.Notify("result", plainNumber(id)) end)
    component:On("LFG_LIST_SEARCH_FAILED", OnSearchFailed)
    component:On("LFG_LIST_APPLICATION_STATUS_UPDATED", OnApplicationStatus)
    component:On("LFG_LIST_ACTIVE_ENTRY_UPDATE", function() GF.Notify("entry") end)
    component:On("LFG_ROLE_CHECK_UPDATE", function()
        GF.RebuildResults()
        GF.Notify("results")
    end)
    component:On("LFG_ROLE_UPDATE", function() GF.Notify("roles") end)
    for _, event in ipairs(BUTTON_EVENTS) do
        component:On(event, function() GF.Notify("buttons") end)
    end
    for _, event in ipairs(QUEUE_MESSAGE_EVENTS) do
        component:On(event, function() GF.Notify("buttons") end)
    end
    component:On("ADDON_RESTRICTION_STATE_CHANGED", OnRestriction)

    -- The hooks on Blizzard's frames, once those frames exist
    addon.Events.OnAddonLoaded("Blizzard_GroupFinder", function()
        if GF.Host and GF.Host.InstallHooks then GF.Host.InstallHooks() end
    end)
end, "groupfinder")
