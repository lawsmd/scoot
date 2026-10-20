--------------------------------------------------------------------------------
-- core/auraids.lua
-- Which spell ids are one aura: the Cooldown Manager alias expansion every
-- AuraContainer consumer feeds into candidateFilters.includeSpellIDs. The
-- aura tracker and the group-frame aura tracker both read it, and either
-- module may be off, so the catalog invalidator lives here.
--
-- Split out of core/components/base/utilities.lua so the aura tracker could
-- go shared without the Blizzard-HUD restyle helpers around it. Registers
-- its catalog events at file scope, so it loads after core/events.lua.
--------------------------------------------------------------------------------
local addonName, addon = ...

--------------------------------------------------------------------------------
-- Aura identity expansion (shared by every AuraContainer consumer)
--------------------------------------------------------------------------------
-- candidateFilters.includeSpellIDs matches on the exact spell ID the engine
-- sees, and that is not always the ID a user picked: talent overrides, rank
-- variants and tooltip proxies all carry their own IDs. Cooldown Manager
-- config data stays fully readable in 12.1 even when aura data does not, so it
-- is the ground truth for which IDs are aliases of each other.
--
-- No early return anywhere in the walk. Blizzard keys several CDM entries on
-- one hidden base spell and only some of them carry the real aura as a linked
-- spell: Flame Shock's CDM base is 470411 (the debuff, 188389, is never a base
-- anywhere), and on Elemental the Essential entry lists no linked spells at all
-- while the Tracked Bar entry links 188389. Stopping at the first match built
-- {470411, 470057} and the tracker never fired. Union every matching entry.

addon.AuraIds = addon.AuraIds or {}
local AuraIds = addon.AuraIds

-- Enumerated rather than listed: 12.1 added categories 4-8 (GroupBuff,
-- SpecAgnostic*, EquipSlot*) and a hardcoded list would silently miss them.
local CDM_CATEGORIES = (function()
    local cat = Enum and Enum.CooldownViewerCategory
    if cat then
        local out = {}
        for _, v in pairs(cat) do
            if type(v) == "number" then table.insert(out, v) end
        end
        table.sort(out)
        if #out > 0 then return out end
    end
    return { 0, 1, 2, 3 }
end)()

-- Secret-safe numeric read: anything secret, non-numeric or non-positive
-- becomes nil.
local function PlainId(v)
    if type(v) == "number" and not issecretvalue(v) and v > 0 then return v end
    return nil
end
AuraIds.PlainId = PlainId

--- Unions every CDM alias of `lookupSpellId` into the `include` set.
--- @param include table set of [spellId] = true, mutated in place
--- @param lookupSpellId number the picked spell ID
function AuraIds.ExpandFromCDM(include, lookupSpellId)
    if not include or not lookupSpellId or not C_CooldownViewer then return end
    if not C_CooldownViewer.GetCooldownViewerCategorySet
        or not C_CooldownViewer.GetCooldownViewerCooldownInfo then
        return
    end
    for _, category in ipairs(CDM_CATEGORIES) do
        local ok, cooldownIDs = pcall(C_CooldownViewer.GetCooldownViewerCategorySet, category, true)
        if ok and type(cooldownIDs) == "table" and not issecretvalue(cooldownIDs) then
            for _, cooldownID in ipairs(cooldownIDs) do
                if not issecretvalue(cooldownID) then
                    local iok, info = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, cooldownID)
                    if iok and type(info) == "table" and not issecretvalue(info) then
                        local sid = PlainId(info.spellID)
                        local oid = PlainId(info.overrideSpellID)
                        local tid = PlainId(info.overrideTooltipSpellID)
                        if sid == lookupSpellId or oid == lookupSpellId or tid == lookupSpellId then
                            if sid then include[sid] = true end
                            if oid then include[oid] = true end
                            if tid then include[tid] = true end
                            local linked = info.linkedSpellIDs
                            if type(linked) == "table" and not issecretvalue(linked) then
                                for _, lid in ipairs(linked) do
                                    lid = PlainId(lid)
                                    if lid then include[lid] = true end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

-- The walk above is not cheap: no early return, every category, one
-- GetCooldownViewerCooldownInfo per entry in each. It used to run once per
-- container build. It now also answers "could the engine's filter match this
-- id" for every spell description, so the expansion is memoised per spell and
-- the whole memo is dropped whenever the catalog itself can move. The
-- invalidator lives here rather than in a component because both ScootAuras
-- and the group-frame aura tracker read it and either module may be off.
local expansionCache = {}
local expansionVersion = 1

--- Bumps the epoch and drops every memoised expansion.
function AuraIds.InvalidateIncludeSets()
    expansionCache = {}
    expansionVersion = expansionVersion + 1
end

--- The current epoch, for callers memoising anything derived from an expansion
-- (scootauras/missing.lua IdSet holds ids, range and provider verdicts).
function AuraIds.GetVersion()
    return expansionVersion
end

--- The memoised CDM alias set for one spell, as [spellId] = true. Read-only;
-- a caller that needs a table of its own goes through BuildIncludeSet.
function AuraIds.GetExpansion(spellId)
    if type(spellId) ~= "number" then return nil end
    local set = expansionCache[spellId]
    if set then return set end
    set = { [spellId] = true }
    pcall(AuraIds.ExpandFromCDM, set, spellId)
    expansionCache[spellId] = set
    return set
end

--- True when `id` is one of the ids a filter built for `spellId` would match.
-- Allocates nothing, so it is safe on a per-description path.
function AuraIds.IncludesId(spellId, id)
    if type(id) ~= "number" then return false end
    if spellId == id then return true end
    local set = AuraIds.GetExpansion(spellId)
    return (set and set[id]) and true or false
end

--- Builds a fresh includeSpellIDs set for one tracked spell.
--- @param spellId number
--- @param extraIds table|nil array of additional IDs (linked registry variants)
--- @return table set of [spellId] = true
function AuraIds.BuildIncludeSet(spellId, extraIds)
    -- A fresh table every call: the result goes straight to the engine as
    -- candidateFilters.includeSpellIDs, and two live containers must never
    -- share one. extraIds stays out of the memo for the same reason, since
    -- only the group-frame tracker passes any.
    local include = {}
    local set = AuraIds.GetExpansion(spellId)
    if set then
        for id in pairs(set) do include[id] = true end
    elseif spellId then
        include[spellId] = true
    end
    if type(extraIds) == "table" then
        for _, id in ipairs(extraIds) do
            if type(id) == "number" then include[id] = true end
        end
    end
    return include
end

-- The catalog moves on these and nothing else.
-- COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED is deliberately absent: it reports one
-- spell being substituted, not the catalog changing, and invalidating there
-- would drop the whole memo every time a player shifts form.
local function onCatalogEvent(event, arg1)
    -- PLAYER_SPECIALIZATION_CHANGED fires for party and raid members too.
    if event == "PLAYER_SPECIALIZATION_CHANGED" and arg1 and arg1 ~= "player" then
        return
    end
    AuraIds.InvalidateIncludeSets()
end
-- Events.On tolerates names this client build rejects (returns a dead handle),
-- covering the COOLDOWN_VIEWER_* PTR drift the old pcall loop guarded against.
for _, event in ipairs({
    "COOLDOWN_VIEWER_DATA_LOADED",
    "COOLDOWN_VIEWER_TABLE_HOTFIXED",
    "TRAIT_CONFIG_UPDATED",
    "PLAYER_SPECIALIZATION_CHANGED",
    "PLAYER_ENTERING_WORLD",
}) do
    addon.Events.On("AuraIds", event, onCatalogEvent)
end

-- Defers FullPowerFrame reapplies to avoid taint during combat. The frame is
