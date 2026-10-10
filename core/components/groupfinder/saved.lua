--------------------------------------------------------------------------------
-- core/components/groupfinder/saved.lua
-- Saved searches: the character's list of up to five searches, each the
-- category and its filter bits, the activity the typed text began with, the
-- text after it, and a copy of the Dungeons filter and the language filter
-- at the moment of the save. The window's tray (ui/v2/groupfinder/saved.lua)
-- draws the list and runs a saved search; this file owns the store, the
-- capture off Blizzard's search panel, the key that tells two searches
-- apart, the title and the filter columns a row shows and the sections its
-- tooltip lists, and the fill of the hosted box's text.
--
-- The box refuses SetText from addon code and no API takes search text, so
-- a saved search's free text (a key range) goes into the box by the
-- player's paste, after the C side's own fill, SetSearchToActivity, has put
-- an activity's name in.
--
-- The list is per character (addon.db.char): a search follows the player's
-- goal on that character, not the profile. It is created on the first save
-- and read with a nil test, so a character that never saved stores nothing.
--------------------------------------------------------------------------------

local addonName, addon = ...

local GF = addon.GroupFinder
local Str = GF.Str
local plain = GF.plain
local plainNumber = GF.plainNumber

local Saved = {}
GF.Saved = Saved

Saved.MAX = 5

-- "ran" when the search after the player's paste went through from Scoot,
-- "blocked" or "timeout" when it did not; nil until a paste ran
Saved.autoSearch = nil

-- The booleans of AdvancedFilterOptions in a fixed order, so a copy carries
-- each and a key reads the same whatever order the client's table iterates
local BOOLEANS = {
    "needsTank", "needsHealer", "needsDamage", "needsMyClass", "hasTank", "hasHealer",
    "difficultyNormal", "difficultyHeroic", "difficultyMythic", "difficultyMythicPlus",
    "generalPlaystyle1", "generalPlaystyle2", "generalPlaystyle3", "generalPlaystyle4",
}

-- The labels the drawer shows for the same rows (ui/v2/groupfinder/search.lua)
local ROLE_LABELS = {
    { key = "needsTank", label = "LFG_LIST_NEEDS_TANK" },
    { key = "needsHealer", label = "LFG_LIST_NEEDS_HEALER" },
    { key = "needsDamage", label = "LFG_LIST_NEEDS_DAMAGE" },
    { key = "needsMyClass", label = "LFG_LIST_CLASS_AVAILABLE", class = true },
    { key = "hasTank", label = "LFG_LIST_HAS_TANK" },
    { key = "hasHealer", label = "LFG_LIST_HAS_HEALER" },
}
local function Trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- A plain string off the box or the API, else nil
local function PlainString(v)
    if type(v) ~= "string" then return nil end
    if plain(v) == nil then return nil end
    return v
end

--------------------------------------------------------------------------------
-- The dungeons the Dungeons filter lists, as Blizzard's menu lists them:
-- this season's, the expansion's others, and the Timerunning set when the
-- character is one; three lists of group ids, and all of them in one. The
-- drawer draws its sections from the three and the replay keeps a saved
-- list to the fourth.
--------------------------------------------------------------------------------

function GF.DungeonGroups()
    local F = Enum and Enum.LFGListFilter
    local season, expansion, timerunning = {}, {}, {}
    if not (F and C_LFGList.GetAvailableActivityGroups) then
        return season, expansion, timerunning, {}
    end
    local function fill(into, filters)
        local groups = C_LFGList.GetAvailableActivityGroups(GF.DUNGEONS_CATEGORY, filters)
        for _, id in ipairs(type(groups) == "table" and groups or {}) do into[#into + 1] = id end
    end
    local pve = F.PvE or 0
    fill(season, bit.bor(F.CurrentSeason or 0, pve))
    fill(expansion, bit.bor(F.CurrentExpansion or 0, F.NotCurrentSeason or 0, pve))
    if F.Timerunning and PlayerIsTimerunning and PlayerIsTimerunning() then
        fill(timerunning, bit.bor(F.Timerunning, pve))
    end
    local all = {}
    for _, part in ipairs({ season, expansion, timerunning }) do
        for _, id in ipairs(part) do all[#all + 1] = id end
    end
    return season, expansion, timerunning, all
end

local function AsSet(ids)
    local set = {}
    for _, id in ipairs(ids) do set[id] = true end
    return set
end

-- The live group ids as a set
function Saved.LiveGroupSet()
    local _, _, _, all = GF.DungeonGroups()
    return AsSet(all)
end

-- The live group ids and this season's, as two sets, for a caller drawing
-- several rows
function Saved.GroupSets()
    local season, _, _, all = GF.DungeonGroups()
    return { live = AsSet(all), season = AsSet(season) }
end

-- A saved activities list without the group ids the client no longer
-- lists, so a past season's id never reaches the server; the set is the
-- caller's when it has one for the pass
function Saved.LiveActivities(ids, liveSet)
    liveSet = liveSet or Saved.LiveGroupSet()
    local kept = {}
    for _, id in ipairs(ids or {}) do
        if liveSet[id] then kept[#kept + 1] = id end
    end
    return kept
end

--------------------------------------------------------------------------------
-- The store
--------------------------------------------------------------------------------

local function Store(create)
    local db = addon.db
    if not (db and db.char) then return nil end
    if not db.char.groupFinderSavedSearches and create then
        db.char.groupFinderSavedSearches = {}
    end
    return db.char.groupFinderSavedSearches
end

function Saved.List()
    return Store(false) or {}
end

function Saved.Count()
    return #Saved.List()
end

function Saved.Add(entry)
    local list = Store(true)
    if not list or not entry or #list >= Saved.MAX then return false end
    list[#list + 1] = entry
    GF.Notify("saved")
    return true
end

function Saved.Remove(index)
    local list = Store(false)
    if not (list and list[index]) then return false end
    table.remove(list, index)
    GF.Notify("saved")
    return true
end

--------------------------------------------------------------------------------
-- Copies: every field of the client's filter, in the shape SaveAdvancedFilter
-- takes, from the client's table or a saved one
--------------------------------------------------------------------------------

function Saved.CopyAdvanced(enabled)
    enabled = type(enabled) == "table" and enabled or {}
    local copy = {}
    for _, k in ipairs(BOOLEANS) do copy[k] = enabled[k] == true end
    copy.minimumRating = plainNumber(enabled.minimumRating) or 0
    copy.activities = {}
    for _, id in ipairs(type(enabled.activities) == "table" and enabled.activities or {}) do
        local n = plainNumber(id)
        if n then copy.activities[#copy.activities + 1] = n end
    end
    return copy
end

-- The languages on, and nothing else; nil when the client has no table
function Saved.CopyLanguages(enabled)
    if type(enabled) ~= "table" then return nil end
    local copy = {}
    for lang, on in pairs(enabled) do
        if on == true and type(lang) == "string" then copy[lang] = true end
    end
    return copy
end

--------------------------------------------------------------------------------
-- The capture: what Blizzard's search panel holds now
--------------------------------------------------------------------------------

-- The activity the typed text begins with, by the longest full name that
-- is a prefix of it, and the text after that name. The activities are the
-- category's own, read without the text as a filter, since a range after
-- the name would match none.
local function SplitActivity(categoryID, filters, text)
    if text == "" then return nil, "" end
    local ok, ids = pcall(C_LFGList.GetAvailableActivities, categoryID, nil,
        GF.ResolveCategoryFilters(categoryID, filters))
    if not (ok and type(ids) == "table") then return nil, text end
    local best, bestLength = nil, 0
    for _, id in ipairs(ids) do
        local okName, name = pcall(C_LFGList.GetActivityFullName, id)
        name = okName and PlainString(name) or nil
        if name and name ~= "" and #name > bestLength and string.sub(text, 1, #name) == name then
            best, bestLength = plainNumber(id), #name
        end
    end
    if not best then return nil, text end
    return best, Trim(string.sub(text, bestLength + 1))
end

-- nil while no search panel or no category is set
function Saved.Capture()
    local sp = LFGListFrame and LFGListFrame.SearchPanel
    if not sp then return nil end
    local categoryID = plainNumber(sp.categoryID)
    if not categoryID then return nil end
    local filters = plainNumber(sp.filters) or 0
    local text = ""
    if sp.SearchBox then
        local ok, typed = pcall(sp.SearchBox.GetText, sp.SearchBox)
        typed = ok and PlainString(typed) or nil
        if typed then text = Trim(typed) end
    end
    local activityID, rest = SplitActivity(categoryID, filters, text)
    local advanced = C_LFGList.GetAdvancedFilter and C_LFGList.GetAdvancedFilter()
    local languages = C_LFGList.GetLanguageSearchFilter and C_LFGList.GetLanguageSearchFilter()
    return {
        categoryID = categoryID,
        filters = filters,
        activityID = activityID,
        text = rest or "",
        advanced = Saved.CopyAdvanced(advanced),
        languages = Saved.CopyLanguages(languages),
        savedAt = time(),
    }
end

-- One string per distinct search, for the duplicate test and the tray's
-- current row: the lists sorted, since the client's table order is its own
function Saved.Key(entry)
    if type(entry) ~= "table" then return nil end
    local parts = {
        tostring(entry.categoryID), tostring(entry.filters or 0),
        tostring(entry.activityID or 0), entry.text or "",
    }
    local a = type(entry.advanced) == "table" and entry.advanced or {}
    for _, k in ipairs(BOOLEANS) do parts[#parts + 1] = a[k] and "1" or "0" end
    parts[#parts + 1] = tostring(a.minimumRating or 0)
    local activities = {}
    for _, id in ipairs(type(a.activities) == "table" and a.activities or {}) do
        activities[#activities + 1] = id
    end
    table.sort(activities)
    parts[#parts + 1] = table.concat(activities, ",")
    local languages = {}
    for lang, on in pairs(type(entry.languages) == "table" and entry.languages or {}) do
        if on then languages[#languages + 1] = lang end
    end
    table.sort(languages)
    parts[#parts + 1] = table.concat(languages, ",")
    return table.concat(parts, "|")
end

--------------------------------------------------------------------------------
-- What a row says: the title (the activity group's name, then the text, or
-- the text alone), the line under it (the activity's difficulty and the
-- category), the filter in columns, and the tooltip's sections. The
-- advanced filter's difficulty and playstyle are replayed but not shown. An
-- empty set adds nothing; an empty dungeon list is every dungeon.
--------------------------------------------------------------------------------

local function Checked(enabled, rows)
    local names = {}
    for _, row in ipairs(rows) do
        if enabled[row.key] then
            local label = Str(row.label, row.key)
            if row.class and PlayerUtil and PlayerUtil.GetClassName then
                label = string.format(label, PlayerUtil.GetClassName())
            end
            names[#names + 1] = label
        end
    end
    return names
end

local function GroupNames(ids)
    local names = {}
    for _, id in ipairs(ids) do
        local ok, name = pcall(C_LFGList.GetActivityGroupInfo, id)
        name = ok and PlainString(name) or nil
        if name and name ~= "" then names[#names + 1] = name end
    end
    return names
end

-- sets: Saved.GroupSets(), computed once by a caller drawing several rows;
-- read here when absent
function Saved.Describe(entry, sets)
    local d = { columns = {}, sections = {}, stale = false }
    local function Add(label, lines)
        if #lines == 0 then return end
        d.columns[#d.columns + 1] = lines
        d.sections[#d.sections + 1] = { label = label, lines = lines }
    end

    local info = C_LFGList.GetLfgCategoryInfo(entry.categoryID)
    local category = type(info) == "table" and PlainString(info.name) or ""
    if category ~= "" and LFGListUtil_GetDecoratedCategoryName then
        category = LFGListUtil_GetDecoratedCategoryName(category, entry.filters or 0, false)
    end
    d.category = category

    -- An activity's title is its group's name, with the difficulty
    -- (Blizzard's activity dropdown's shortName) on the line under it
    local group, difficulty
    if entry.activityID then
        local ok, name = pcall(C_LFGList.GetActivityFullName, entry.activityID)
        d.activity = ok and PlainString(name) or nil
        local okInfo, activity = pcall(C_LFGList.GetActivityInfoTable, entry.activityID)
        if okInfo and type(activity) == "table" then
            local groupID = plainNumber(activity.groupFinderActivityGroupID)
            if groupID and groupID > 0 then
                local okGroup, groupName = pcall(C_LFGList.GetActivityGroupInfo, groupID)
                group = okGroup and PlainString(groupName) or nil
            end
            difficulty = PlainString(activity.shortName)
        end
        if group == "" or difficulty == "" or difficulty == group then
            group, difficulty = nil, nil
        end
    end
    local text = entry.text or ""
    d.text = text
    if d.activity then
        local name = group or d.activity
        d.title = text ~= "" and (name .. " " .. text) or name
        d.sub = difficulty
        if category ~= "" then
            d.sub = difficulty and (difficulty .. ", " .. category) or category
        end
    elseif text ~= "" then
        d.title = text
        if category ~= "" then d.sub = category end
    else
        d.title = category
    end

    local a = type(entry.advanced) == "table" and entry.advanced or {}
    if entry.categoryID == GF.DUNGEONS_CATEGORY then
        Add(Str("LFG_LIST_REQUIRE", "Roles"), Checked(a, ROLE_LABELS))

        local ids = type(a.activities) == "table" and a.activities or {}
        if #ids > 0 then
            sets = sets or Saved.GroupSets()
            local current = {}
            for _, id in ipairs(ids) do
                if not sets.live[id] then d.stale = true end
                if sets.season[id] then current[#current + 1] = id end
            end
            Add(Str("DUNGEONS", "Dungeons"), GroupNames(current))
        end

        local rating = plainNumber(a.minimumRating) or 0
        if rating > 0 then
            Add(Str("LFG_LIST_MINIMUM_RATING", "Minimum rating"), { tostring(rating) .. "+" })
        end
    end

    local languages = {}
    for lang in pairs(type(entry.languages) == "table" and entry.languages or {}) do
        languages[#languages + 1] = Str("LFG_LIST_LANGUAGE_" .. string.upper(lang), lang)
    end
    table.sort(languages)
    Add(Str("LANGUAGE", "Language"), languages)
    return d
end

--------------------------------------------------------------------------------
-- The fill: the activity's name through the C side's own call. The box takes
-- no text from addon code, so the rest is the player's paste (the tray's
-- copy box). Returns the box's text after the fill, the whole text the
-- search wants, and the part the player pastes after the name.
--------------------------------------------------------------------------------

local function BoxText(box)
    local ok, text = pcall(box.GetText, box)
    return ok and PlainString(text) or nil
end
Saved.BoxText = BoxText

function Saved.Fill(box, activityID, text)
    if not box then return "", "", "" end
    pcall(box.ClearFocus, box)
    local prefix = ""
    if activityID and C_LFGList.SetSearchToActivity then
        pcall(C_LFGList.SetSearchToActivity, activityID)
        prefix = BoxText(box) or ""
    end
    text = text or ""
    if text == "" then return prefix, prefix, "" end
    local paste = (prefix ~= "" and " " or "") .. text
    return prefix, prefix .. paste, paste
end
