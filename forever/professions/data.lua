--------------------------------------------------------------------------------
-- forever/professions/data.lua
-- What the player's professions are and when one gains a point
-- (professions.lua holds the settings).
--
-- The read is the one Blizzard's own professions book makes: GetProfessions
-- returns one spellbook index per slot, with nil for an empty slot, and
-- GetProfessionInfo gives a slot's name, icon, level, the cap of its trained
-- rank and its skill line. The first two slots are the primary professions;
-- the rest are the secondary ones.
--
-- The bar's band runs from 0 to the cap, the top of the highest rank the
-- player has trained: 142 with Expert trained is 142 of 225. A rank can be
-- trained well before the level reaches the top of the one below, so the bar
-- is full only when the next point waits on a trainer. A cap that does not
-- read falls back to the 75-point span the level stands in.
--
-- Lockpicking is a skill line and no profession, so GetProfessions leaves it
-- out. C_SkillInfo.GetSkillLineInfoByID, the call the character pane makes
-- for a skill, gives its name, level and cap, and a character with a level
-- in it gets an entry after the professions, as a secondary one. The entry
-- carries skill = true: it has no profession window to open.
--
-- No event carries a gained point. SKILL_LINES_CHANGED says only that some
-- skill moved, and it also fires for weapon skills, so every one is gathered
-- into one read on the next frame and compared with the levels held from the
-- read before. A skill line seen for the first time, or one whose held level
-- is 0, is taken as learned and reports no gain.
--
-- While both features are off the event reads nothing. The levels held are
-- then out of date, so the first read after a switch comes on reports no
-- gain either; each switch calls Data.Refresh as it turns on.
--------------------------------------------------------------------------------

local addonName, addon = ...

local Professions = addon.Professions

local Data = {}
Professions.Data = Data

local OWNER = "CamelotProfessions"

-- A rank's width in skill points, for a cap that does not read.
local BAND = 75
-- GetProfessions' slots past these are the secondary professions.
local PRIMARY_SLOTS = 2
-- The Lockpicking skill line, and Pick Lock, whose icon it wears.
local LOCKPICKING = 633
local PICK_LOCK = 1804
local LOCKPICKING_ICON = "Interface\\Icons\\Spell_Nature_MoonKey"

local function isSecret(v)
    return issecretvalue and issecretvalue(v) or false
end

--- The band a level stands in, lower then upper.
function Data.Band(rank, cap)
    if cap > 0 then return 0, cap end
    local lower = math.floor(rank / BAND) * BAND
    return lower, lower + BAND
end

-- One slot. Returns the entry, or nil and whether the slot would not read.
local function readSlot(index, slot)
    local ok, name, icon, rank, cap, _, _, skillLine = pcall(GetProfessionInfo, index)
    if not ok then return nil, true end
    if isSecret(name) or isSecret(icon) or isSecret(rank) or isSecret(cap) or isSecret(skillLine) then
        return nil, true
    end
    if type(name) ~= "string" or type(rank) ~= "number" or type(skillLine) ~= "number" then
        return nil, false
    end
    cap = type(cap) == "number" and cap or 0
    local lower, upper = Data.Band(rank, cap)
    return {
        skillLine = skillLine, name = name, icon = icon,
        rank = rank, cap = cap, lower = lower, upper = upper,
        secondary = slot > PRIMARY_SLOTS,
    }, false
end

-- The slots have holes, so the count comes from select.
local function readSlots(list, ...)
    local complete = true
    for slot = 1, select("#", ...) do
        local index = select(slot, ...)
        if isSecret(index) then
            complete = false
        elseif index ~= nil then
            local entry, unread = readSlot(index, slot)
            if entry then
                list[#list + 1] = entry
            elseif unread then
                complete = false
            end
        end
    end
    return complete
end

-- Lockpicking's entry, when the character has a level in it. Returns false
-- when a value would not read.
local function readLockpicking(list)
    local get = C_SkillInfo and C_SkillInfo.GetSkillLineInfoByID
    if not get then return true end
    local ok, info = pcall(get, LOCKPICKING)
    if not ok or info == nil then return true end
    if isSecret(info) or type(info) ~= "table" then return false end
    local name, rank, cap = info.name, info.rank, info.maxRank
    if isSecret(name) or isSecret(rank) or isSecret(cap) then return false end
    if type(name) ~= "string" or type(rank) ~= "number" or rank <= 0 then return true end
    cap = type(cap) == "number" and cap or 0
    local icon
    if C_Spell and C_Spell.GetSpellTexture then
        local iconOk, texture = pcall(C_Spell.GetSpellTexture, PICK_LOCK)
        if iconOk and texture and not isSecret(texture) then icon = texture end
    end
    local lower, upper = Data.Band(rank, cap)
    list[#list + 1] = {
        skillLine = LOCKPICKING, name = name, icon = icon or LOCKPICKING_ICON,
        rank = rank, cap = cap, lower = lower, upper = upper,
        secondary = true, skill = true,
    }
    return true
end

--- Every known profession, in slot order, then Lockpicking, and whether the
--- whole read held.
--- A read that did not hold is partial and must not be compared against.
function Data.Read()
    local list = {}
    if not (GetProfessions and GetProfessionInfo) then return list, false end
    local ok, complete = pcall(function() return readSlots(list, GetProfessions()) end)
    if not (ok and complete) then return list, false end
    return list, readLockpicking(list)
end

--------------------------------------------------------------------------------
-- Changes
--------------------------------------------------------------------------------

local current = {}
local ranks = {}
local changedFns, skillUpFns = {}, {}

--- The last whole read.
function Data.Current()
    return current
end

--- fn(list) after every read that held: the tracker's signal, which also
--- covers a profession learned or dropped and a newly trained rank.
function Data.OnChanged(fn)
    changedFns[#changedFns + 1] = fn
end

--- fn(entry, oldRank) for each profession whose level rose.
function Data.OnSkillUp(fn)
    skillUpFns[#skillUpFns + 1] = fn
end

-- Returns whether the read held.
local function refresh(report)
    local list, complete = Data.Read()
    if not complete then return false end

    local gains
    local seen = {}
    for _, entry in ipairs(list) do
        seen[entry.skillLine] = true
        local old = ranks[entry.skillLine]
        if report and old and old > 0 and entry.rank > old then
            gains = gains or {}
            gains[#gains + 1] = { entry, old }
        end
        ranks[entry.skillLine] = entry.rank
    end
    for skillLine in pairs(ranks) do
        if not seen[skillLine] then ranks[skillLine] = nil end
    end
    current = list

    for _, fn in ipairs(changedFns) do securecallfunction(fn, list) end
    if gains then
        for _, gain in ipairs(gains) do
            for _, fn in ipairs(skillUpFns) do securecallfunction(fn, gain[1], gain[2]) end
        end
    end
    return true
end

local seeded = false
local pending = false
-- An event went unread, so the levels held may be behind the character's.
local stale = false

--- Read again now, with no gain reported: for a caller that needs the list
--- before the first event, and for a switch turning on.
function Data.Refresh()
    if refresh(false) then stale = false end
end

addon.Events.On(OWNER, "SKILL_LINES_CHANGED", function()
    if not (Professions.TrackerOn() or Professions.SkillUpsOn()) then
        stale = true
        return
    end
    if pending then return end
    pending = true
    C_Timer.After(0, function()
        pending = false
        if refresh(seeded and not stale) then stale = false end
    end)
end)

addon.Events.OnWorldEntered(function()
    refresh(false)
    seeded = true
end)
