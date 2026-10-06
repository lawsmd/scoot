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
    applicants = {},     -- the sorted applicants of the player's listing, { id, numMembers }
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

-- id, appStatus, pendingStatus, appDuration, the role applied as; a stale
-- id reads as no application
function GF.Application(id)
    if not id then return nil, "none", nil, nil, nil end
    local ok, appID, status, pending, duration, role = pcall(C_LFGList.GetApplicationInfo, id)
    if not ok then return nil, "none", nil, nil, nil end
    return appID, plain(status) or "none", plain(pending), plainNumber(duration), plain(role)
end

function GF.MemberCounts(id)
    if not id then return nil end
    local ok, counts = pcall(C_LFGList.GetSearchResultMemberCounts, id)
    if ok and type(counts) == "table" then return counts end
    return nil
end

-- The members one by one, as Blizzard's row tooltip reads them: the list,
-- and whether every member answered with a role, which is Blizzard's own
-- test before it lists them. Under chat lockdown the call answers secrets
-- and every member reads as absent.
function GF.Members(id, numMembers)
    local list = {}
    if not id then return list, false end
    for i = 1, numMembers or 0 do
        local ok, m = pcall(C_LFGList.GetSearchResultPlayerInfo, id, i)
        if ok and type(m) == "table" then
            local role = plain(m.assignedRole)
            if type(role) == "string" then
                list[#list + 1] = {
                    role = role,
                    class = plain(m.classFilename),
                    className = plain(m.className),
                    spec = plain(m.specName),
                    name = plain(m.name),
                    leader = plainBool(m.isLeader) == true,
                    leaver = plainBool(m.isLeaver) == true,
                }
            end
        end
    end
    return list, #list == (numMembers or 0) and #list > 0
end

-- The leader's rating as text: the dungeon score for a Mythic+ activity,
-- the rated PvP rating for a rated one, else nothing. Members other than
-- the leader carry no score on a search result.
function GF.LeaderRating(info, activity)
    if not info or not activity then return nil end
    if plainBool(activity.isMythicPlusActivity) == true then
        local score = plainNumber(info.leaderOverallDungeonScore)
        if score and score > 0 then return tostring(score) end
        return nil
    end
    if plainBool(activity.isRatedPvpActivity) == true then
        local ratings = plain(info.leaderPvpRatingInfo)
        local first = type(ratings) == "table" and plain(ratings[1])
        local rating = type(first) == "table" and plainNumber(first.rating)
        if rating and rating > 0 then return tostring(rating) end
    end
    return nil
end

function GF.ActivityID(info)
    local ids = info and plain(info.activityIDs)
    if type(ids) ~= "table" then return nil end
    return plainNumber(ids[1])
end

-- Whether the result lists the activity. A list that does not read plain
-- (the chat lockdown) answers true, so a cut by activity leaves such rows
-- on the pane instead of dropping every one
function GF.ResultHasActivity(info, activityID)
    local ids = info and plain(info.activityIDs)
    if type(ids) ~= "table" or not activityID then return true end
    for _, id in ipairs(ids) do
        local n = plainNumber(id)
        if n == nil then return true end
        if n == activityID then return true end
    end
    return false
end

function GF.ActivityInfo(activityID)
    if not activityID then return nil end
    local ok, t = pcall(C_LFGList.GetActivityInfoTable, activityID)
    if ok and type(t) == "table" then return t end
    return nil
end

-- The activity's full name, "Den of Nalorakk (Mythic Keystone)", with a
-- Mythic+ activity's difficulty, the part in the parentheses, shortened to
-- M+. A Dungeons activity is the difficulty and its group is the dungeon,
-- so the cut takes the activity's own short name when it closes the
-- parentheses, else whatever the parentheses hold, and a name with
-- neither is returned whole.
function GF.ActivityName(info)
    local activityID = GF.ActivityID(info)
    if not activityID then return nil end
    local ok, name = pcall(C_LFGList.GetActivityFullName, activityID, nil, plainBool(info.isWarMode))
    if not ok or type(name) ~= "string" then return nil end
    if plain(name) == nil then return name end
    local activity = GF.ActivityInfo(activityID)
    if not activity or plainBool(activity.isMythicPlusActivity) ~= true then return name end
    local short = plain(activity.shortName)
    if type(short) == "string" and short ~= "" then
        local from, to = string.find(name, short, 1, true)
        if from and string.sub(name, to + 1) == ")" then
            return string.sub(name, 1, from - 1) .. "M+)"
        end
    end
    local open = string.find(name, "%s*%([^()]*%)%s*$")
    if not open then return name end
    return string.sub(name, 1, open - 1) .. " (M+)"
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

-- The tails a status string may end in, cut in turn until none is left:
-- whitespace, the no-break space, the ASCII hyphen, the Unicode hyphens
-- and dashes (U+2010 to U+2015) and the minus sign. The client's string
-- ends in a dash for the countdown Blizzard's row puts after it
local STATUS_TAILS = { "%s+$", "\194\160$", "%-$", "\226\128[\144-\149]$", "\226\136\146$" }

-- A status word without the dash. The color escapes go first: the enUS
-- string colors its dash ("Pending |cff40bf40-|r"), so a cut of the bare
-- hyphen left it standing on the twelfth look, and the word takes the
-- row's own color in any case
local function Word(key, fallback)
    local s = Str(key, fallback)
    s = s:gsub("|c%x%x%x%x%x%x%x%x", "")
    s = s:gsub("|r", "")
    local cut = true
    while cut do
        cut = false
        for _, tail in ipairs(STATUS_TAILS) do
            local trimmed, n = s:gsub(tail, "")
            if n > 0 then s, cut = trimmed, true end
        end
    end
    return s
end

-- What a row says for an application: the word, whether it is lit, and
-- whether the countdown and the cancel show, decided in the order Blizzard's
-- row decides them. nil when the result carries no application.
function GF.StatusLine(appStatus, pendingStatus)
    if appStatus == "none" and pendingStatus == nil then return nil end
    if pendingStatus == "applied" and C_LFGList.GetRoleCheckInfo and C_LFGList.GetRoleCheckInfo() then
        return Word("LFG_LIST_ROLE_CHECK", "Role check"), false, false
    end
    if pendingStatus == "cancelled" or appStatus == "cancelled" or appStatus == "failed" then
        return Word("LFG_LIST_APP_CANCELLED", "Cancelled"), false, false
    end
    if GF.IsDeclined(appStatus) then
        local key = appStatus == "declined_full" and "LFG_LIST_APP_FULL" or "LFG_LIST_APP_DECLINED"
        return Word(key, "Declined"), false, false
    end
    if appStatus == "timedout" then
        return Word("LFG_LIST_APP_TIMED_OUT", "Timed out"), false, false
    end
    if appStatus == "invited" then
        return Word("LFG_LIST_APP_INVITED", "Invited"), true, false
    end
    if appStatus == "inviteaccepted" then
        return Word("LFG_LIST_APP_INVITE_ACCEPTED", "Accepted"), true, false
    end
    if appStatus == "invitedeclined" then
        return Word("LFG_LIST_APP_INVITE_DECLINED", "Invite declined"), false, false
    end
    return Word("LFG_LIST_PENDING", "Pending"), true, true
end

-- Whether a result still satisfies the advanced filter, the test
-- Blizzard's row runs on each update: a group that filled the role the
-- filter wants open, or whose leader's rating fell under the floor, no
-- longer does. The Dungeons category alone carries the filter, which the
-- caller tests. A count that does not read plain is taken as zero
function GF.MatchesFilter(info, counts)
    local enabled = C_LFGList.GetAdvancedFilter and C_LFGList.GetAdvancedFilter()
    if type(enabled) ~= "table" or type(info) ~= "table" or type(counts) ~= "table" then return true end
    local function Count(key) return plainNumber(counts[key]) or 0 end
    local _, class = UnitClass("player")
    if enabled.needsTank and Count("TANK") ~= 0 then return false end
    if enabled.needsHealer and Count("HEALER") ~= 0 then return false end
    if enabled.needsDamage and Count("DAMAGER") >= 3 then return false end
    if enabled.needsMyClass and class and Count(class) > 0 then return false end
    if enabled.hasTank and Count("TANK") == 0 then return false end
    if enabled.hasHealer and Count("HEALER") == 0 then return false end
    if (plainNumber(enabled.minimumRating) or 0) > (plainNumber(info.leaderOverallDungeonScore) or 0) then
        return false
    end
    local activity = GF.ActivityInfo(GF.ActivityID(info))
    local wanted = enabled.activities
    if type(wanted) == "table" and #wanted > 0 then
        local group = activity and plainNumber(activity.groupFinderActivityGroupID)
        local found = false
        for _, id in ipairs(wanted) do
            if id == group then
                found = true
                break
            end
        end
        if not found then return false end
    end
    if activity and (enabled.difficultyNormal or enabled.difficultyHeroic
        or enabled.difficultyMythic or enabled.difficultyMythicPlus) then
        if (activity.isNormalActivity and not enabled.difficultyNormal)
            or (activity.isHeroicActivity and not enabled.difficultyHeroic)
            or (activity.isMythicActivity and not enabled.difficultyMythic)
            or (activity.isMythicPlusActivity and not enabled.difficultyMythicPlus) then
            return false
        end
    end
    local P = Enum.LFGEntryGeneralPlaystyle
    if P and (enabled.generalPlaystyle1 or enabled.generalPlaystyle2
        or enabled.generalPlaystyle3 or enabled.generalPlaystyle4) then
        local style = plainNumber(info.generalPlaystyle)
        if (style == P.Learning and not enabled.generalPlaystyle1)
            or (style == P.FunRelaxed and not enabled.generalPlaystyle2)
            or (style == P.FunSerious and not enabled.generalPlaystyle3)
            or (style == P.Expert and not enabled.generalPlaystyle4) then
            return false
        end
    end
    return true
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

-- The reason an application is off, in the order Blizzard's Sign Up tests
-- them, or nil when it is on; the chain ends at the offline member, since
-- the window's buttons each name their result, and the roles are the
-- column's own test
function GF.SignUpBlock()
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
    return nil
end

-- The reasons Start a Group is off, in the order Blizzard's category panel
-- and its search panel test them, past the category itself, which the
-- caller sees: a member who does not lead, a queue the player is in, a
-- silenced or squelched account, and a listing already up
function GF.StartGroupBlock()
    local home = LE_PARTY_CATEGORY_HOME
    if IsInGroup(home) and not UnitIsGroupLeader("player", home) then
        return Str("LFG_LIST_NOT_LEADER", "Only the leader can start a group")
    end
    local message = LFGListUtil_GetActiveQueueMessage and LFGListUtil_GetActiveQueueMessage(false)
    if message then return message end
    if C_SocialRestrictions then
        if C_SocialRestrictions.IsSilenced and C_SocialRestrictions.IsSilenced() then
            return Str("ERR_ACCOUNT_SILENCED", "This account is silenced")
        elseif C_SocialRestrictions.IsSquelched and C_SocialRestrictions.IsSquelched() then
            return Str("ERR_USER_SQUELCHED", "This account is squelched")
        end
    end
    if GF.HasEntry() and UnitIsGroupLeader("player", home) then
        return Str("CANNOT_DO_THIS_WHILE_LFGLIST_LISTED", "Not while a group is listed")
    end
    return nil
end

function GF.HasEntry()
    return (C_LFGList.HasActiveEntryInfo and C_LFGList.HasActiveEntryInfo()) == true
end

-- The player's own listing, or nil; under chat lockdown its text fields
-- are secret and pass through the plain guards at the reads
function GF.ActiveEntry()
    local ok, entry = pcall(C_LFGList.GetActiveEntryInfo)
    if ok and type(entry) == "table" then return entry end
    return nil
end

-- Whether the player may act on the listing: the leader, or an assistant
function GF.CanManageEntry()
    return (LFGListUtil_IsEntryEmpowered and LFGListUtil_IsEntryEmpowered()) and true or false
end

-- The keystone the player holds as an activity and its group, the regular
-- one first and the timewalking one after, as Blizzard's form picks them
function GF.OwnedKeystoneActivity()
    local read = C_LFGList.GetOwnedKeystoneActivityAndGroupAndLevel
    if not read then return nil end
    for _, timewalking in ipairs({ false, true }) do
        local ok, activityID, groupID = pcall(read, timewalking)
        activityID = ok and plainNumber(activityID) or nil
        if activityID then return activityID, plainNumber(groupID) end
    end
    return nil
end

--------------------------------------------------------------------------------
-- The applicants of the player's listing: the client's list copied and
-- sorted as Blizzard sorts it, each record read once so no secret reaches
-- the comparison
--------------------------------------------------------------------------------

function GF.ApplicantInfo(id)
    if not id then return nil end
    local ok, info = pcall(C_LFGList.GetApplicantInfo, id)
    if ok and type(info) == "table" then return info end
    return nil
end

-- A member of an applicant as a named table through the plain guards. The
-- name is kept raw as well, for Ambiguate and SetText alone, since under
-- chat lockdown it is secret and those two take one.
function GF.ApplicantMember(id, i)
    if not id then return nil end
    local ok, name, class, className, level, itemLevel, honorLevel, tank, healer, damage, assignedRole,
        relationship, dungeonScore, pvpItemLevel, factionGroup, _, specID, isLeaver =
        pcall(C_LFGList.GetApplicantMemberInfo, id, i)
    if not ok then return nil end
    return {
        name = plain(name), rawName = name,
        class = plain(class), className = plain(className),
        level = plainNumber(level), itemLevel = plainNumber(itemLevel), pvpItemLevel = plainNumber(pvpItemLevel),
        honorLevel = plainNumber(honorLevel),
        tank = plainBool(tank) == true, healer = plainBool(healer) == true, damage = plainBool(damage) == true,
        assignedRole = plain(assignedRole), relationship = plain(relationship),
        dungeonScore = plainNumber(dungeonScore), factionGroup = plain(factionGroup),
        specID = plainNumber(specID), leaver = plainBool(isLeaver) == true,
    }
end

-- New applicants last, then the client's display order, as Blizzard's
-- viewer sorts; a field that reads as absent falls back to the id
function GF.RebuildApplicants()
    local ok, ids = pcall(C_LFGList.GetApplicants)
    if not (ok and type(ids) == "table") then ids = {} end
    local records = {}
    for _, id in ipairs(ids) do
        local plainID = plainNumber(id)
        if plainID then
            local info = GF.ApplicantInfo(plainID)
            records[#records + 1] = {
                id = plainID,
                isNew = (info and plainBool(info.isNew)) == true,
                order = info and plainNumber(info.displayOrderID) or 0,
                numMembers = info and plainNumber(info.numMembers) or 1,
            }
        end
    end
    table.sort(records, function(a, b)
        if a.isNew ~= b.isNew then return b.isNew end
        if a.order ~= b.order then return a.order < b.order end
        return a.id < b.id
    end)
    GF.state.applicants = records
    return records
end

-- Dungeons search and list the current expansion's activities only, as
-- Blizzard's own filter resolution does
function GF.ResolveCategoryFilters(categoryID, filters)
    local F = Enum.LFGListFilter
    if categoryID == GF.DUNGEONS_CATEGORY and F then
        return bit.band(bit.bnot(F.NotRecommended), bit.bor(filters or 0, F.Recommended))
    end
    return filters or 0
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
    "PLAYER_ROLES_ASSIGNED",
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

-- A setting of the page, with its default while nothing is stored
function GF.Setting(key)
    return addon.GetComponentSetting("groupfinder", key)
end

-- The two ways in beside /scoot lfg, each behind a switch on the page: the
-- /lfg word and a row in the widget's click menu. Both are put in place
-- from the initializer, so they exist only while the module is on. The
-- word's handler reads its switch on each call and the menu reads the
-- action's on each open, so a change takes without a reload.
local function InstallOpenPaths()
    if addon.Commands and addon.Commands.InstallWord then
        addon.Commands.InstallWord("lfg", "/lfg", function()
            if not GF.Setting("slashCommand") then
                addon:Print("Enable /lfg in " .. addon.Brand .. " \226\134\146 Interface \226\134\146 Group Finder.")
                return
            end
            if GF.UI then GF.UI:Toggle() end
        end)
    end
    if addon.Widget and addon.Widget.RegisterAction then
        addon.Widget:RegisterAction({
            id = "groupFinder",
            label = "Group Finder",
            order = 20,
            isEnabled = function() return GF.Setting("widgetLaunch") and true or false end,
            Run = function()
                if GF.UI then GF.UI:Toggle() end
            end,
        })
    end
end

addon:RegisterComponentInitializer(function(self)
    local Component = addon.ComponentPrototype
    local component = Component:New({
        id = "groupfinder",
        name = "Group Finder",
        settings = {
            slashCommand = { type = "addon", default = true },
            widgetLaunch = { type = "addon", default = true },
        },
    })
    self:RegisterComponent(component)
    GF.component = component
    GF.state.lockdown = ReadLockdown()
    InstallOpenPaths()

    component:On("LFG_LIST_AVAILABILITY_UPDATE", function() GF.Notify("categories") end)
    component:On("LFG_LIST_SEARCH_RESULTS_RECEIVED", OnResultsReceived)
    component:On("LFG_LIST_UPDATE_SEARCH_RESULTS", OnResultsReceived)
    component:On("LFG_LIST_SEARCH_RESULT_UPDATED", function(_, id) GF.Notify("result", plainNumber(id)) end)
    component:On("LFG_LIST_SEARCH_FAILED", OnSearchFailed)
    component:On("LFG_LIST_APPLICATION_STATUS_UPDATED", OnApplicationStatus)
    component:On("LFG_LIST_ACTIVE_ENTRY_UPDATE", function() GF.Notify("entry") end)
    component:On("LFG_LIST_ENTRY_CREATION_FAILED", function() GF.Notify("creationFailed") end)
    component:On("LFG_LIST_APPLICANT_LIST_UPDATED", function()
        GF.RebuildApplicants()
        GF.Notify("applicants")
    end)
    component:On("LFG_LIST_APPLICANT_UPDATED", function(_, id) GF.Notify("applicant", plainNumber(id)) end)
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
    for _, event in ipairs({ "UI_SCALE_CHANGED", "DISPLAY_SIZE_CHANGED" }) do
        component:On(event, function()
            if GF.Host and GF.Host.SyncScale then GF.Host.SyncScale() end
        end)
    end

    -- The hooks on Blizzard's frames, once those frames exist
    addon.Events.OnAddonLoaded("Blizzard_GroupFinder", function()
        if GF.Host and GF.Host.InstallHooks then GF.Host.InstallHooks() end
    end)
end, "groupfinder")
