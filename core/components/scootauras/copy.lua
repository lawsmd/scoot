-- scootauras/copy.lua - Copy from Global: reuse another character's tracker
--
-- Trackers are character-specific inside a profile (core.lua "Ownership"), and
-- one account's characters spread across every profile in ScootDB. The scan
-- here reads all of them (raw, never materializing anything) and buckets by
-- owner; the copy mirrors DuplicateTracker with the destination character as
-- owner and the source's screen position carried into the active layout.
local addonName, addon = ...

local SAU = addon.ScootAuras
local CopyTable = _G.CopyTable

local UNASSIGNED_KEY = "__unassigned"

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function DeepEqual(a, b)
    if a == b then return true end
    local ta, tb = type(a), type(b)
    -- nil and an empty table both mean "no styling"
    if ta ~= "table" and tb ~= "table" then return false end
    if ta ~= "table" then a = {} end
    if tb ~= "table" then b = {} end
    for k, v in pairs(a) do
        if not DeepEqual(v, b[k]) then return false end
    end
    for k in pairs(b) do
        if a[k] == nil then return false end
    end
    return true
end

-- "Name - Realm" -> "Name", "Realm"; a key without the separator is its own name.
local function SplitOwnerKey(key)
    if type(key) ~= "string" then return tostring(key), nil end
    local name, realm = key:match("^(.-) %- (.+)$")
    if name and name ~= "" then return name, realm end
    return key, nil
end

local function SourceSort(a, b)
    local ao = a.tracker.order or a.trackerId
    local bo = b.tracker.order or b.trackerId
    if ao ~= bo then return ao < bo end
    if a.trackerId ~= b.trackerId then return a.trackerId < b.trackerId end
    return tostring(a.profileName) < tostring(b.profileName)
end

--------------------------------------------------------------------------------
-- Scan
--------------------------------------------------------------------------------

--- Every tracker on the account this character can copy, bucketed by owner.
-- Returns an array of { ownerKey, displayName, classToken, unassigned, sources }
-- sorted by display name ("Unassigned" last). A source is
-- { profileName, trackerId, tracker, styling, classToken, ownerKey } where
-- `tracker` and `styling` are live references into the source profile: read
-- only. Own trackers in the ACTIVE profile are excluded (they are the page's
-- own list); own trackers in other profiles list under this character's name.
-- Unowned trackers (not yet adopted, in a profile nobody has loaded since
-- ownership arrived) list under "Unassigned".
function SAU.CollectCopySources()
    local db = addon.db
    local profiles = db and db.profiles
    if type(profiles) ~= "table" then return {} end
    local me = SAU.GetOwnerKey()
    local activeName = db.GetCurrentProfile and db:GetCurrentProfile() or nil

    -- Pass 1: class tokens from every store's owners map.
    local classByOwner = {}
    for _, profile in pairs(profiles) do
        local store = type(profile) == "table" and rawget(profile, "scootAuras") or nil
        local owners = store and rawget(store, "owners") or nil
        if type(owners) == "table" then
            for key, rec in pairs(owners) do
                if type(rec) == "table" and type(rec.class) == "string" and classByOwner[key] == nil then
                    classByOwner[key] = rec.class
                end
            end
        end
    end

    -- Pass 2: bucket trackers.
    local buckets = {}
    local function BucketFor(key)
        local b = buckets[key]
        if not b then
            b = { ownerKey = (key ~= UNASSIGNED_KEY) and key or nil,
                  unassigned = (key == UNASSIGNED_KEY),
                  classToken = classByOwner[key],
                  sources = {} }
            buckets[key] = b
        end
        return b
    end

    for profileName, profile in pairs(profiles) do
        local store = type(profile) == "table" and rawget(profile, "scootAuras") or nil
        local trackers = store and rawget(store, "trackers") or nil
        if type(trackers) == "table" then
            local components = rawget(profile, "components")
            for trackerId, tracker in pairs(trackers) do
                if type(tracker) == "table" and type(tracker.spellId) == "number" then
                    local owner = tracker.owner
                    local skip = (owner ~= nil and owner == me and profileName == activeName)
                    if not skip then
                        local key = owner or UNASSIGNED_KEY
                        local styling = type(components) == "table"
                            and rawget(components, SAU.GetComponentId(trackerId)) or nil
                        if type(styling) ~= "table" then styling = nil end
                        table.insert(BucketFor(key).sources, {
                            profileName = profileName,
                            trackerId = trackerId,
                            tracker = tracker,
                            styling = styling,
                            classToken = classByOwner[key],
                            ownerKey = (key ~= UNASSIGNED_KEY) and key or nil,
                        })
                    end
                end
            end
        end
    end

    -- Dedupe within a bucket: a copied profile carries exact duplicates.
    for _, bucket in pairs(buckets) do
        table.sort(bucket.sources, SourceSort)
        local kept = {}
        for _, src in ipairs(bucket.sources) do
            local dup = false
            for _, other in ipairs(kept) do
                local t, o = src.tracker, other.tracker
                if t.spellId == o.spellId and t.kind == o.kind and t.unit == o.unit
                    and t.shape == o.shape and t.name == o.name
                    and DeepEqual(src.styling, other.styling) then
                    dup = true
                    break
                end
            end
            if not dup then table.insert(kept, src) end
        end
        bucket.sources = kept
    end

    -- Display names: realm only when two owners share a name.
    local nameCount = {}
    for key, bucket in pairs(buckets) do
        if not bucket.unassigned then
            local name = SplitOwnerKey(key)
            nameCount[name] = (nameCount[name] or 0) + 1
        end
    end
    local out = {}
    for key, bucket in pairs(buckets) do
        if bucket.unassigned then
            bucket.displayName = "Unassigned"
        else
            local name, realm = SplitOwnerKey(key)
            if realm and (nameCount[name] or 0) > 1 then
                bucket.displayName = name .. " - " .. realm
            else
                bucket.displayName = name
            end
        end
        if #bucket.sources > 0 then table.insert(out, bucket) end
    end
    table.sort(out, function(a, b)
        if a.unassigned ~= b.unassigned then return b.unassigned end
        local an, bn = a.displayName:lower(), b.displayName:lower()
        if an ~= bn then return an < bn end
        return tostring(a.ownerKey) < tostring(b.ownerKey)
    end)
    return out
end

--------------------------------------------------------------------------------
-- Copy
--------------------------------------------------------------------------------

--- Creates this character's copy of a source tracker (see CollectCopySources)
-- in the active profile: content and styling copied, name suffixed, the
-- source's screen position carried into the active layout. Returns the new
-- tracker id, or nil, err.
function SAU.CopyTrackerFromSource(src)
    if not SAU.IsModuleActive() then
        return nil, "ScootAuras module is disabled (enable it on the Features page, then reload)"
    end
    local source = src and src.tracker
    if type(source) ~= "table" then return nil, "no such tracker" end

    local spellId = tonumber(source.spellId)
    local kind = source.kind or "buff"
    local unit = source.unit
    local shape = source.shape or "icon"
    -- Foreign data may be stale; fall the unit back to the kind's default
    -- rather than refusing the copy (SetTrackerContent does the same).
    if not SAU.VALID_UNITS[kind] or not SAU.VALID_UNITS[kind][unit] then
        unit = (kind == "debuff") and "target" or "player"
    end
    local ok, err = SAU.ValidateContent(spellId, kind, unit, shape)
    if not ok then return nil, err end

    local store = SAU.EnsureStore()
    if not store then return nil, "profile not ready" end
    local Engine = SAU.Engine

    local newId = SAU._AllocateId(store)
    store.trackers[newId] = {
        spellId = spellId,
        kind = kind,
        unit = unit,
        shape = shape,
        name = (source.name or SAU._PlainSpellName(spellId)) .. " copy",
        enabled = true,
        order = newId,
        owner = SAU.GetOwnerKey(),
    }
    SAU.StampOwner(store)

    local profile = addon.db and addon.db.profile
    if profile then
        -- Styling copy must land in profile.components BEFORE EnsureComponentDB
        -- links the new component, or the copy arrives as defaults.
        if src.styling and next(src.styling) then
            local components = rawget(profile, "components")
            if type(components) ~= "table" then
                components = {}
                profile.components = components
            end
            components[SAU.GetComponentId(newId)] = CopyTable(src.styling)
        end

        -- Same screen spot: the source's position in its own layout (a profile
        -- IS a layout) goes under the active layout for the new id. Written
        -- before the claim so ApplySavedPosition finds it.
        local srcProfile = addon.db.profiles and addon.db.profiles[src.profileName]
        local srcPositions = type(srcProfile) == "table" and rawget(srcProfile, "scootAuraPositions") or nil
        local perKey = type(srcPositions) == "table" and srcPositions["t" .. tostring(src.trackerId)] or nil
        local layoutName = Engine and Engine.GetActiveLayoutName and Engine.GetActiveLayoutName() or nil
        if type(perKey) == "table" and layoutName and Engine and Engine.SavePosition then
            local pos = perKey[src.profileName] or perKey[layoutName]
            if type(pos) ~= "table" then
                local _, first = next(perKey)
                pos = first
            end
            if type(pos) == "table" and pos.point then
                Engine.SavePosition("t" .. newId, layoutName, pos.point, pos.x or 0, pos.y or 0)
            end
        end
    end

    SAU.RegisterTrackerComponent(newId)
    addon:EnsureComponentDB(SAU.GetComponentId(newId))
    if shape == "bar" then
        SAU.ApplyBarStartingValues(newId)
    end
    if Engine and Engine.ClaimForTracker then
        Engine.ClaimForTracker(newId)
    end
    return newId
end
