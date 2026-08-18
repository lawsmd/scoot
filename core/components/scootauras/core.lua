-- scootauras/core.lua - User-built aura trackers: store, settings, CRUD, reconcile
--
-- Content (spell, kind, unit, shape, name, enabled, grouping) lives in
-- profile.scootAuras; styling lives in profile.components["scootAura_<id>"];
-- positions in profile.scootAuraPositions. Content writes go through the API
-- here so engine consequences route through the structural gate; styling
-- writes go through the normal component setAndApply path.
local addonName, addon = ...

addon.ScootAuras = addon.ScootAuras or {}
local SAU = addon.ScootAuras

local Component = addon.ComponentPrototype
local CopyTable = _G.CopyTable

SAU.COMPONENT_PREFIX = "scootAura_"
SAU.MODULE_CATEGORY = "scootAuras"
SAU.NAV_KEY = "scootAurasList"

-- [trackerId] = { container = visualFrame, shell = shellFrame, elements, textFrame }
-- Same table shape the styling/layout layer expects; container is the visual
-- frame all elements and the AuraContainer live under.
SAU._activeStates = {}

--------------------------------------------------------------------------------
-- Store access
--------------------------------------------------------------------------------

-- Read-only: never materializes tables (zero-touch).
function SAU.GetStore()
    local profile = addon.db and addon.db.profile
    return profile and rawget(profile, "scootAuras") or nil
end

function SAU.EnsureStore()
    local profile = addon.db and addon.db.profile
    if not profile then return nil end
    local store = rawget(profile, "scootAuras")
    if type(store) ~= "table" then
        store = { nextId = 1, trackers = {}, groups = {} }
        profile.scootAuras = store
    end
    store.trackers = store.trackers or {}
    store.groups = store.groups or {}
    store.nextId = store.nextId or 1
    -- Left behind by the first cadence-lock build; nothing reads it.
    store.learnedDurations = nil
    return store
end

--------------------------------------------------------------------------------
-- Ownership
--
-- A profile is an Edit Mode layout, and several characters can share one, so
-- trackers and groups are character-specific inside the profile: each record
-- carries `owner` (the AceDB char key, "Name - Realm"). The getters below are
-- the single choke point: anything resolved through GetTracker/GetGroup or the
-- Owned*/Sorted* views belongs to this character. Other characters' records
-- stay in the store untouched (their styling tables in profile.components are
-- unregistered here and the pruner leaves non-empty ones alone).
--------------------------------------------------------------------------------

function SAU.GetOwnerKey()
    local db = addon.db
    return db and db.keys and db.keys.char or nil
end

function SAU.GetOwnerClassToken()
    if addon.GetClassTokenForUnit then
        local token = addon.GetClassTokenForUnit("player")
        if type(token) == "string" then return token end
    end
    return nil
end

function SAU.IsOwnedByMe(record)
    if type(record) ~= "table" or record.owner == nil then return false end
    return record.owner == SAU.GetOwnerKey()
end

--- Records this character's class beside its trackers so other characters can
-- class-color its name in the copy list. Write paths only.
function SAU.StampOwner(store)
    local me = SAU.GetOwnerKey()
    if not store or not me then return end
    local token = SAU.GetOwnerClassToken()
    store.owners = store.owners or {}
    local rec = store.owners[me]
    if type(rec) ~= "table" then
        store.owners[me] = { class = token }
    elseif token and rec.class ~= token then
        rec.class = token
    end
end

-- Unfiltered access, for hygiene passes, debug output, and the copy scan.
function SAU.GetTrackerRaw(trackerId)
    local store = SAU.GetStore()
    return store and store.trackers and store.trackers[trackerId] or nil
end

function SAU.GetGroupRaw(gid)
    local store = SAU.GetStore()
    return store and store.groups and store.groups[gid] or nil
end

--- This character's trackers as { [id] = tracker }. Fresh table; never
-- materializes the store.
function SAU.OwnedTrackers()
    local out = {}
    local store = SAU.GetStore()
    local me = SAU.GetOwnerKey()
    if store and store.trackers and me then
        for id, tracker in pairs(store.trackers) do
            if type(tracker) == "table" and tracker.owner == me then
                out[id] = tracker
            end
        end
    end
    return out
end

function SAU.OwnedGroups()
    local out = {}
    local store = SAU.GetStore()
    local me = SAU.GetOwnerKey()
    if store and store.groups and me then
        for gid, group in pairs(store.groups) do
            if type(group) == "table" and group.owner == me then
                out[gid] = group
            end
        end
    end
    return out
end

--- Migration: records without an owner (created before ownership existed)
-- belong to the first character that loads the profile. Writes nothing when
-- nothing is unowned, so it is safe on every init and reconcile pass.
function SAU.AdoptUnowned(reason)
    local store = SAU.GetStore()
    local me = SAU.GetOwnerKey()
    if not store or not me then return 0 end
    local adopted = 0
    for _, tracker in pairs(store.trackers or {}) do
        if type(tracker) == "table" and tracker.owner == nil then
            tracker.owner = me
            adopted = adopted + 1
        end
    end
    for _, group in pairs(store.groups or {}) do
        if type(group) == "table" and group.owner == nil then
            group.owner = me
            adopted = adopted + 1
        end
    end
    if adopted > 0 then
        SAU.StampOwner(store)
        if SAU.Engine and SAU.Engine.Record then
            SAU.Engine.Record("adopt", tostring(reason) .. "=" .. adopted)
        end
    end
    return adopted
end

-- Ids are shared between trackers and groups and unique across owners within
-- a profile. Bumping past any id already in use guards a hand-merged store
-- whose nextId lags behind its records.
local function AllocateId(store)
    local id = tonumber(store.nextId) or 1
    while (store.trackers and store.trackers[id]) or (store.groups and store.groups[id]) do
        id = id + 1
    end
    store.nextId = id + 1
    return id
end
SAU._AllocateId = AllocateId

--- Owner-filtered: nil for another character's tracker.
function SAU.GetTracker(trackerId)
    local tracker = SAU.GetTrackerRaw(trackerId)
    if tracker and SAU.IsOwnedByMe(tracker) then return tracker end
    return nil
end

--- Returns a sorted array of { id, tracker } for stable iteration.
function SAU.SortedTrackers()
    local out = {}
    for id, tracker in pairs(SAU.OwnedTrackers()) do
        table.insert(out, { id = id, tracker = tracker })
    end
    table.sort(out, function(a, b)
        local ao = a.tracker.order or a.id
        local bo = b.tracker.order or b.id
        if ao ~= bo then return ao < bo end
        return a.id < b.id
    end)
    return out
end

--- Owner-filtered: nil for another character's group.
function SAU.GetGroup(gid)
    local group = SAU.GetGroupRaw(gid)
    if group and SAU.IsOwnedByMe(group) then return group end
    return nil
end

--- Returns a sorted array of { id, group } for stable iteration.
function SAU.SortedGroups()
    local out = {}
    for gid, group in pairs(SAU.OwnedGroups()) do
        table.insert(out, { id = gid, group = group })
    end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end

function SAU.GetComponentId(trackerId)
    return SAU.COMPONENT_PREFIX .. trackerId
end

function SAU.GetDB(trackerId)
    local comp = addon.Components and addon.Components[SAU.GetComponentId(trackerId)]
    return comp and comp.db
end

function SAU.IsModuleActive()
    return addon:IsModuleEnabled(SAU.MODULE_CATEGORY)
end

--------------------------------------------------------------------------------
-- Spec gate
--------------------------------------------------------------------------------

-- A tracker or group may carry `specs`, an array of numeric spec IDs it loads
-- in. Absent or empty means every spec, so old saved variables read as
-- unrestricted and nothing is stamped at create.

local classSpecIDs          -- set: this character's class's spec IDs
local specNameCache = {}

--- This character's current spec ID, nil before the talent data loads.
-- Delegates rather than adding a third GetSpecialization idiom to the addon.
function SAU.CurrentSpecID()
    local get = addon.Profiles and addon.Profiles._getCurrentSpecID
    if type(get) ~= "function" then return nil end
    local ok, specID = pcall(get)
    if ok and type(specID) == "number" and specID > 0 then return specID end
    return nil
end

--- Set of the spec IDs this character's class has, from the current-class-only
-- list Spec Profiles already builds.
function SAU.ClassSpecIDSet()
    if classSpecIDs then return classSpecIDs end
    local set = {}
    local Profiles = addon.Profiles
    if Profiles and Profiles.GetSpecOptions then
        local ok, options = pcall(Profiles.GetSpecOptions, Profiles)
        if ok and type(options) == "table" then
            for _, opt in ipairs(options) do
                if type(opt.specID) == "number" then set[opt.specID] = true end
            end
        end
    end
    -- Cache only once the class data is really there: an empty set captured
    -- before login would stick and open every gate for the session.
    if next(set) then classSpecIDs = set end
    return set
end

--- Spec name for any class's spec ID. The list rows describe other characters'
-- trackers too, so this cannot go through the current-class list.
function SAU.SpecName(specID)
    if type(specID) ~= "number" then return "?" end
    if specNameCache[specID] then return specNameCache[specID] end
    local getter = _G.GetSpecializationInfoByID
    if type(getter) == "function" then
        local ok, _, name = pcall(getter, specID)
        if ok and type(name) == "string" and name ~= "" then
            specNameCache[specID] = name
            return name
        end
    end
    return "Spec " .. tostring(specID)
end

--- Spec names for a stored list, joined for prose: "Shadow",
-- "Discipline & Holy", "Discipline, Holy & Shadow". nil when unrestricted, so
-- callers can append their own " only" and skip the clause entirely.
function SAU.DescribeSpecs(specs)
    if type(specs) ~= "table" or #specs == 0 then return nil end
    local names = {}
    for _, id in ipairs(specs) do
        table.insert(names, SAU.SpecName(id))
    end
    if #names == 1 then return names[1] end
    local last = table.remove(names)
    return table.concat(names, ", ") .. " & " .. last
end

--- Whether `record` (a tracker or a group) may load in the current spec. Fails
-- open three ways: no restriction; a restriction naming no spec this class has
-- (AdoptUnowned can hand a profile's records to another class); and an unknown
-- current spec during early login.
function SAU.SpecAllows(record)
    local specs = record and record.specs
    if type(specs) ~= "table" or #specs == 0 then return true end
    local mine = SAU.ClassSpecIDSet()
    local relevant = false
    for _, id in ipairs(specs) do
        if mine[id] then relevant = true break end
    end
    if not relevant then return true end
    local current = SAU.CurrentSpecID()
    if not current then return true end
    for _, id in ipairs(specs) do
        if id == current then return true end
    end
    return false
end

--- The single "should this tracker render" test: the manual toggle, the
-- tracker's own spec gate, and its group's. Every engine and layout site reads
-- this; tracker.enabled alone stays the Aura List's ON/OFF pill.
function SAU.IsTrackerActive(trackerId, tracker)
    tracker = tracker or SAU.GetTracker(trackerId)
    if not tracker then return false end
    if tracker.enabled == false then return false end
    if not SAU.SpecAllows(tracker) then return false end
    if tracker.groupId then
        local group = SAU.GetGroupRaw(tracker.groupId)
        if group and not SAU.SpecAllows(group) then return false end
    end
    return true
end

-- Numbers only, deduped, sorted. Returns nil for an empty list so
-- "unrestricted" has one representation rather than two.
local function NormalizeSpecs(ids)
    if type(ids) ~= "table" then return nil end
    local seen, out = {}, {}
    for _, id in ipairs(ids) do
        local n = tonumber(id)
        if n and not seen[n] then
            seen[n] = true
            table.insert(out, n)
        end
    end
    if #out == 0 then return nil end
    table.sort(out)
    return out
end

local function ToggledSpecs(specs, specID)
    local out, found = {}, false
    for _, id in ipairs(specs or {}) do
        if id == specID then found = true else table.insert(out, id) end
    end
    if not found then table.insert(out, specID) end
    return out
end

--------------------------------------------------------------------------------
-- Content validation
--------------------------------------------------------------------------------

-- missingbuff: the visual shows while the player LACKS the buff (missing.lua).
SAU.VALID_KINDS = { buff = true, debuff = true, missingbuff = true }

-- Shapes per kind. Buff/debuff trackers display the aura; a missing-buff
-- tracker is a reminder, so it offers icon, text, or both and no bar/shape.
SAU.VALID_SHAPES_BY_KIND = {
    buff        = { icon = true, bar = true, shape = true },
    debuff      = { icon = true, bar = true, shape = true },
    missingbuff = { icon = true, text = true, icontext = true },
}
-- Union, for callers that only need "is this a shape at all".
SAU.VALID_SHAPES = { icon = true, bar = true, shape = true, text = true, icontext = true }

-- The friendly-debuff wall: debuff information on friendly units is not
-- acquirable, so Debuff offers hostile-capable units only. Missing-buff
-- trackers watch the player alone for now ("My Group" is a later unit).
SAU.VALID_UNITS = {
    buff        = { player = true, target = true, focus = true },
    debuff      = { target = true, focus = true },
    missingbuff = { player = true },
}

--- The unit a kind falls back to when the chosen one is invalid for it.
function SAU.DefaultUnitForKind(kind)
    return (kind == "debuff") and "target" or "player"
end

--- The shape a kind falls back to when the chosen one is invalid for it:
-- "icon" wherever a kind offers it, else the kind's first shape.
function SAU.DefaultShapeForKind(kind)
    local shapes = SAU.VALID_SHAPES_BY_KIND[kind]
    if shapes and not shapes.icon then
        return (next(shapes))
    end
    return "icon"
end

function SAU.ValidateContent(spellId, kind, unit, shape)
    if type(spellId) ~= "number" or spellId <= 0 then return nil, "invalid spell ID" end
    if not SAU.VALID_KINDS[kind] then return nil, "kind must be buff, debuff, or missingbuff" end
    local units = SAU.VALID_UNITS[kind]
    if not units[unit] then return nil, kind .. " cannot target unit '" .. tostring(unit) .. "'" end
    local shapes = SAU.VALID_SHAPES_BY_KIND[kind]
    if not shapes or not shapes[shape] then
        return nil, kind .. " cannot use shape '" .. tostring(shape) .. "'"
    end
    return true
end

-- Own-cast filtering: a debuff tracker watches the player's own aura on the
-- enemy; buffs accept any source (external buffs on the player are the point).
-- A missing-buff tracker matches the same HELPFUL slot; only its rendering
-- differs (the engine's presence hides the visual instead of showing it).
function SAU.FilterForKind(kind)
    if kind == "debuff" then return "HARMFUL|PLAYER" end
    return "HELPFUL"
end

--------------------------------------------------------------------------------
-- Settings factory
--------------------------------------------------------------------------------

--- Fresh settings table for one tracker component. Shape/kind/unit/enabled are
-- content, not settings; everything here is styling.
function SAU.DefaultSettings()
    return {
        scale           = { type = "addon", default = 100 },
        iconMode        = { type = "addon", default = "default" },
        iconSize        = { type = "addon", default = 32 },
        iconShape       = { type = "addon", default = 0 },
        textFont        = { type = "addon", default = "ROBOTO_SEMICOND_BLACK" },
        textStyle       = { type = "addon", default = "OUTLINE" },
        textSize        = { type = "addon", default = 24 },
        textColor       = { type = "addon", default = { 1, 1, 1, 1 } },
        textPosition    = { type = "addon", default = "inside" },
        textOuterAnchor = { type = "addon", default = "RIGHT" },
        textInnerAnchor = { type = "addon", default = "CENTER" },
        hideText        = { type = "addon", default = false },
        textOffsetX     = { type = "addon", default = 0 },
        textOffsetY     = { type = "addon", default = 0 },
        hideStackText   = { type = "addon", default = false },
        stackTextFont        = { type = "addon", default = "ROBOTO_SEMICOND_BLACK" },
        stackTextStyle       = { type = "addon", default = "OUTLINE" },
        stackTextSize        = { type = "addon", default = 14 },
        stackTextColor       = { type = "addon", default = { 1, 1, 1, 1 } },
        stackTextPosition    = { type = "addon", default = "inside" },
        stackTextInnerAnchor = { type = "addon", default = "BOTTOMRIGHT" },
        stackTextOuterAnchor = { type = "addon", default = "TOPRIGHT" },
        stackTextOffsetX     = { type = "addon", default = 0 },
        stackTextOffsetY     = { type = "addon", default = 0 },
        hideNameText        = { type = "addon", default = false },
        nameTextFont        = { type = "addon", default = "ROBOTO_SEMICOND_BLACK" },
        nameTextStyle       = { type = "addon", default = "OUTLINE" },
        nameTextSize        = { type = "addon", default = 10 },
        nameTextColor       = { type = "addon", default = { 1, 1, 1, 1 } },
        nameTextPosition    = { type = "addon", default = "inside" },
        nameTextInnerAnchor = { type = "addon", default = "LEFT" },
        nameTextOuterAnchor = { type = "addon", default = "ABOVE" },
        nameTextOffsetX     = { type = "addon", default = 0 },
        nameTextOffsetY     = { type = "addon", default = 0 },
        borderStyle     = { type = "addon", default = "none" },
        borderThickness = { type = "addon", default = 1 },
        borderInsetH    = { type = "addon", default = 0 },
        borderInsetV    = { type = "addon", default = 0 },
        borderTintEnable = { type = "addon", default = false },
        borderTintColor  = { type = "addon", default = { 1, 1, 1, 1 } },
        barWidth                = { type = "addon", default = 250 },
        barHeight               = { type = "addon", default = 32 },
        barShowIcon             = { type = "addon", default = true },
        barFillMode             = { type = "addon", default = "deplete" },
        barForegroundTexture    = { type = "addon", default = "bevelled" },
        barForegroundColorMode  = { type = "addon", default = "class" },
        barForegroundTint       = { type = "addon", default = { 1, 1, 1, 1 } },
        barBackgroundTexture    = { type = "addon", default = "bevelled" },
        barBackgroundColorMode  = { type = "addon", default = "custom" },
        barBackgroundTint       = { type = "addon", default = { 0, 0, 0, 1 } },
        barBackgroundOpacity    = { type = "addon", default = 50 },
        barBorderStyle          = { type = "addon", default = "none" },
        barBorderThickness      = { type = "addon", default = 1 },
        barBorderInsetH         = { type = "addon", default = 0 },
        barBorderInsetV         = { type = "addon", default = 0 },
        barBorderTintEnable     = { type = "addon", default = false },
        barBorderTintColor      = { type = "addon", default = { 1, 1, 1, 1 } },
        barBorderHiddenEdges    = { type = "addon", default = false },
        -- The bar is the anchor; the icon is an optional addition beside it.
        barIconSide             = { type = "addon", default = "LEFT" },
        barIconGap              = { type = "addon", default = 2 },
        -- Cadence lock (cadence.lua): drain speed pinned to the duration the
        -- aura was assigned with; extensions add fill instead of refilling.
        barLockCadence          = { type = "addon", default = false },
        shapeStyle      = { type = "addon", default = "border:SquareMask" },
        shapeColorMode  = { type = "addon", default = "class" },
        shapeTint       = { type = "addon", default = { 1, 1, 1, 1 } },
        shapeShowDrain  = { type = "addon", default = true },
        opacityInCombat         = { type = "addon", default = 100 },
        opacityWithTarget       = { type = "addon", default = 100 },
        opacityOutOfCombat      = { type = "addon", default = 100 },
        -- Missing-buff kind (missing.lua): text suffix and blink.
        missingSuffix           = { type = "addon", default = false },
        blinkWhenShown          = { type = "addon", default = false },
    }
end

--------------------------------------------------------------------------------
-- Bar-shape starting values
--------------------------------------------------------------------------------

-- Keys whose starting point differs by shape. The statics in DefaultSettings
-- stay icon-appropriate; these are stamped into the component db when a
-- tracker becomes a bar (unwritten keys only, so user choices always win) and
-- removed again when it stops being one (still-pristine keys only).
SAU.BarShapeStartingValues = {
    textInnerAnchor   = "RIGHT",
    stackTextPosition = "outside",
    stackTextSize     = 18,
    stackTextColor    = { 1, 0, 0, 1 },
}

local function StampEqual(a, b)
    if type(a) == "table" and type(b) == "table" then
        for i = 1, 4 do
            if (a[i] or 1) ~= (b[i] or 1) then return false end
        end
        return true
    end
    return a == b
end

-- Missing-buff kind: the name text is the whole reminder (or sits beside the
-- icon), so it starts larger and to the icon's right instead of the bar's
-- small "above" label. Same stamp/unstamp rules as the bar values.
SAU.MissingKindStartingValues = {
    nameTextOuterAnchor = "RIGHT",
    nameTextSize        = 14,
}

local function ApplyStartingValues(trackerId, values)
    local db = addon:EnsureComponentDB(SAU.GetComponentId(trackerId))
    if not db then return end
    for key, value in pairs(values) do
        if rawget(db, key) == nil then
            db[key] = (type(value) == "table") and CopyTable(value) or value
        end
    end
end

local function RemoveStartingValues(trackerId, values)
    local db = addon:EnsureComponentDB(SAU.GetComponentId(trackerId))
    if not db then return end
    for key, value in pairs(values) do
        if StampEqual(rawget(db, key), value) then
            db[key] = nil
        end
    end
end

function SAU.ApplyBarStartingValues(trackerId)
    ApplyStartingValues(trackerId, SAU.BarShapeStartingValues)
end

function SAU.RemoveBarStartingValues(trackerId)
    RemoveStartingValues(trackerId, SAU.BarShapeStartingValues)
end

function SAU.ApplyMissingStartingValues(trackerId)
    ApplyStartingValues(trackerId, SAU.MissingKindStartingValues)
end

function SAU.RemoveMissingStartingValues(trackerId)
    RemoveStartingValues(trackerId, SAU.MissingKindStartingValues)
end

--------------------------------------------------------------------------------
-- Component registration
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- Spell descriptions (name and icon as the player knows the spell)
--------------------------------------------------------------------------------

-- Cooldown Manager entries key on a base spell that a talent may override:
-- Flame Shock's entries carry base 470411, shown as Voltaic Blaze (470057)
-- while that talent is taken. Blizzard's own CDM settings tooltip the entry by
-- the override, so a stored spell ID is described the same way here: the
-- CDM's `overrideSpellID` for a base spell, else the player's own override,
-- else the spell itself. Name and icon always come from the same resolved
-- ID, so they agree (the first cut named cells by the base and iconed them by
-- the override-resolved texture, and "Flame Shock" wore the Voltaic Blaze
-- icon). `overrideTooltipSpellID` is deliberately not in this map: it is a
-- per-entry identity (several tracked entries share one base and differ only
-- there), and the picker stores it as the cell's spell ID instead.

local cdmDisplayByBase   -- [baseSpellId] = displaySpellId; nil until built

local function PlainNumber(v)
    if type(v) == "number" and not issecretvalue(v) and v > 0 then return v end
    return nil
end

local function BuildCDMDisplayMap()
    local map = {}
    local enum = Enum and Enum.CooldownViewerCategory
    if not enum or not C_CooldownViewer
        or not C_CooldownViewer.GetCooldownViewerCategorySet
        or not C_CooldownViewer.GetCooldownViewerCooldownInfo then
        return map, 0
    end
    local count = 0
    for _, category in pairs(enum) do
        if type(category) == "number" then
            local ok, ids = pcall(C_CooldownViewer.GetCooldownViewerCategorySet, category, true)
            if ok and type(ids) == "table" and not issecretvalue(ids) then
                for _, cooldownID in ipairs(ids) do
                    if not issecretvalue(cooldownID) then
                        local iok, info = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, cooldownID)
                        if iok and type(info) == "table" and not issecretvalue(info) then
                            local base = PlainNumber(info.spellID)
                            if base then
                                count = count + 1
                                local shown = PlainNumber(info.overrideSpellID)
                                -- Several entries share one base (cooldown and
                                -- tracked-aura rows); the talent override is a
                                -- property of the base, so any entry that
                                -- reports it wins over the bare base.
                                if shown and shown ~= base then
                                    map[base] = shown
                                elseif map[base] == nil then
                                    map[base] = base
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return map, count
end

--- Drops the cached CDM base-to-display map; rebuilt on the next description.
-- Called on CDM data/override events, spec changes, and talent edits.
function SAU.InvalidateSpellDescriptions()
    cdmDisplayByBase = nil
    classSpecIDs = nil
end

--- The spell ID a stored ID is shown as: CDM override chain, else the
-- player's own override, else the ID itself.
function SAU.DisplaySpellFor(spellId)
    if type(spellId) ~= "number" then return spellId end
    if not cdmDisplayByBase then
        local map, count = BuildCDMDisplayMap()
        -- An empty catalog means the CDM data has not loaded yet; keep
        -- looking until it has.
        if count > 0 then cdmDisplayByBase = map end
        local mapped = map[spellId]
        if mapped then return mapped end
    else
        local mapped = cdmDisplayByBase[spellId]
        if mapped then return mapped end
    end
    local ok, override = pcall(C_Spell.GetOverrideSpell, spellId)
    override = ok and PlainNumber(override) or nil
    if override then return override end
    return spellId
end

--- Name, icon (fileID), and the ID they came from, for a stored spell ID.
-- Name falls back to "Aura <id>", icon to the question mark.
function SAU.DescribeSpell(spellId)
    local shown = SAU.DisplaySpellFor(spellId)
    local name, icon
    local nok, sname = pcall(C_Spell.GetSpellName, shown)
    if nok and type(sname) == "string" and not issecretvalue(sname) and sname ~= "" then
        name = sname
    elseif shown ~= spellId then
        nok, sname = pcall(C_Spell.GetSpellName, spellId)
        if nok and type(sname) == "string" and not issecretvalue(sname) and sname ~= "" then
            name = sname
        end
    end
    -- originalIconID is the described spell's own art; iconID would resolve
    -- overrides a second time through a different ID.
    local tok, iconID, originalIconID = pcall(C_Spell.GetSpellTexture, shown)
    if tok then icon = PlainNumber(originalIconID) or PlainNumber(iconID) end
    if not icon and shown ~= spellId then
        tok, iconID, originalIconID = pcall(C_Spell.GetSpellTexture, spellId)
        if tok then icon = PlainNumber(originalIconID) or PlainNumber(iconID) end
    end
    return name or ("Aura " .. tostring(spellId)), icon or 134400, shown
end

local function PlainSpellName(spellId)
    return (SAU.DescribeSpell(spellId))
end

SAU._PlainSpellName = PlainSpellName

--- Icon fileID for a stored spell ID (see DescribeSpell).
function SAU._SpellIcon(spellId)
    local _, icon = SAU.DescribeSpell(spellId)
    return icon
end

--- Registers the settings component for one tracker. Idempotent; respects the
-- module gate (RegisterComponent no-ops while the category is disabled).
function SAU.RegisterTrackerComponent(trackerId)
    local componentId = SAU.GetComponentId(trackerId)
    if addon.Components and addon.Components[componentId] then
        return addon.Components[componentId]
    end
    local comp = Component:New({
        id = componentId,
        name = "ScootAura: " .. trackerId,
        settings = SAU.DefaultSettings(),
        ApplyStyling = function()
            -- Resolve through the live store: profile switches replace the
            -- tracker table under the same id.
            local tracker = SAU.GetTracker(trackerId)
            if tracker and SAU._ApplyStyling then
                SAU._ApplyStyling(trackerId, tracker)
            end
        end,
    })
    addon:RegisterComponent(comp)
    return addon.Components and addon.Components[componentId] or nil
end

-- Registered at init so LinkComponentsToDB picks up persisted styling tables.
addon:RegisterComponentInitializer(function(self)
    SAU.AdoptUnowned("init")
    for trackerId in pairs(SAU.OwnedTrackers()) do
        SAU.RegisterTrackerComponent(trackerId)
    end
end, SAU.MODULE_CATEGORY)

--------------------------------------------------------------------------------
-- CRUD (content writes)
--------------------------------------------------------------------------------

--- Creates a tracker and brings it live (or queues its wiring when combat or
-- instance restrictions block structural work). Returns trackerId or nil, err.
function SAU.CreateTracker(spec)
    if not SAU.IsModuleActive() then
        return nil, "ScootAuras module is disabled (enable it on the Features page, then reload)"
    end
    local spellId = tonumber(spec and spec.spellId)
    local kind = spec and spec.kind or "buff"
    local unit = spec and spec.unit or SAU.DefaultUnitForKind(kind)
    local shape = spec and spec.shape or SAU.DefaultShapeForKind(kind)
    local ok, err = SAU.ValidateContent(spellId, kind, unit, shape)
    if not ok then return nil, err end

    local store = SAU.EnsureStore()
    if not store then return nil, "profile not ready" end

    local trackerId = AllocateId(store)
    store.trackers[trackerId] = {
        spellId = spellId,
        kind = kind,
        unit = unit,
        shape = shape,
        name = spec.name or PlainSpellName(spellId),
        enabled = true,
        order = trackerId,
        owner = SAU.GetOwnerKey(),
    }
    if kind == "missingbuff" then
        -- Content, not styling: it decides when the reminder may show at all.
        store.trackers[trackerId].onlyInCombat = (spec.onlyInCombat ~= false)
    end
    SAU.StampOwner(store)

    SAU.RegisterTrackerComponent(trackerId)
    addon:EnsureComponentDB(SAU.GetComponentId(trackerId))
    if shape == "bar" then
        SAU.ApplyBarStartingValues(trackerId)
    end
    if kind == "missingbuff" then
        SAU.ApplyMissingStartingValues(trackerId)
    end
    SAU.Engine.ClaimForTracker(trackerId)
    return trackerId
end

--- Deletes a tracker: parks its container, hides its frames, and clears every
-- persisted trace. The pruner never reclaims unregistered components' data, so
-- the cleanup here is explicit.
function SAU.DeleteTracker(trackerId)
    local store = SAU.GetStore()
    local tracker = SAU.GetTracker(trackerId)
    if not tracker then return nil, "no such tracker" end

    if tracker.groupId then
        local group = SAU.GetGroup(tracker.groupId)
        if group and group.memberOrder then
            for i, id in ipairs(group.memberOrder) do
                if id == trackerId then
                    table.remove(group.memberOrder, i)
                    break
                end
            end
        end
    end

    SAU.Engine.ReleaseForTracker(trackerId)

    local componentId = SAU.GetComponentId(trackerId)
    if addon.Components then addon.Components[componentId] = nil end

    local profile = addon.db and addon.db.profile
    if profile then
        local components = rawget(profile, "components")
        if components then components[componentId] = nil end
        local positions = rawget(profile, "scootAuraPositions")
        if positions then positions["t" .. trackerId] = nil end
    end
    store.trackers[trackerId] = nil
    if SAU.Groups then SAU.Groups.RequestReflow() end
    return true
end

--- Applies content edits (spellId/kind/unit/shape/onlyInCombat) to a live
-- tracker and routes the engine consequence: shape and onlyInCombat edits
-- restyle in place, spell/unit/kind edits park the mismatched container
-- immediately and rebuild through the gate.
function SAU.SetTrackerContent(trackerId, changes)
    local tracker = SAU.GetTracker(trackerId)
    if not tracker then return nil, "no such tracker" end
    local spellId = tonumber(changes.spellId) or tracker.spellId
    local kind = changes.kind or tracker.kind
    local unit = changes.unit or tracker.unit
    local shape = changes.shape or tracker.shape
    -- A kind flip can strand the current unit (debuff+player) or shape
    -- (missingbuff+bar); fall to the kind's default rather than rejecting.
    if not SAU.VALID_UNITS[kind] or not SAU.VALID_UNITS[kind][unit] then
        unit = SAU.DefaultUnitForKind(kind)
    end
    local shapes = SAU.VALID_SHAPES_BY_KIND[kind]
    if not shapes or not shapes[shape] then
        shape = SAU.DefaultShapeForKind(kind)
    end
    local ok, err = SAU.ValidateContent(spellId, kind, unit, shape)
    if not ok then return nil, err end

    local oldSpellId = tracker.spellId
    local oldShape = tracker.shape
    local oldKind = tracker.kind
    tracker.spellId = spellId
    tracker.kind = kind
    tracker.unit = unit
    tracker.shape = shape
    if kind == "missingbuff" then
        if changes.onlyInCombat ~= nil then
            tracker.onlyInCombat = (changes.onlyInCombat ~= false)
        elseif tracker.onlyInCombat == nil then
            tracker.onlyInCombat = true
        end
    else
        tracker.onlyInCombat = nil
    end
    if type(changes.name) == "string" and changes.name ~= "" then
        tracker.name = changes.name
    elseif spellId ~= oldSpellId then
        -- The name was the auto name (or a Duplicate / Copy from Global of
        -- one, where the point is to swap the spell next); follow the new
        -- spell. Custom names stay.
        local oldAuto = PlainSpellName(oldSpellId)
        if tracker.name == oldAuto or tracker.name == oldAuto .. " copy" then
            tracker.name = PlainSpellName(spellId)
        end
    end

    if shape == "bar" and oldShape ~= "bar" then
        SAU.ApplyBarStartingValues(trackerId)
    elseif oldShape == "bar" and shape ~= "bar" then
        SAU.RemoveBarStartingValues(trackerId)
    end
    if kind == "missingbuff" and oldKind ~= "missingbuff" then
        SAU.ApplyMissingStartingValues(trackerId)
    elseif oldKind == "missingbuff" and kind ~= "missingbuff" then
        SAU.RemoveMissingStartingValues(trackerId)
    end

    SAU.Engine.ClaimForTracker(trackerId)
    SAU.Engine.UpdateEditModeName(trackerId)
    return true
end

--- Duplicates a tracker: new id, deep-copied styling and positions (offset so
-- the copy is visibly separate), name suffixed.
function SAU.DuplicateTracker(trackerId)
    local source = SAU.GetTracker(trackerId)
    if not source then return nil, "no such tracker" end
    local store = SAU.EnsureStore()
    if not store then return nil, "profile not ready" end

    local newId = AllocateId(store)
    store.trackers[newId] = {
        spellId = source.spellId,
        kind = source.kind,
        unit = source.unit,
        shape = source.shape,
        name = (source.name or PlainSpellName(source.spellId)) .. " copy",
        enabled = source.enabled ~= false,
        order = newId,
        owner = SAU.GetOwnerKey(),
        onlyInCombat = source.onlyInCombat,
        specs = source.specs and CopyTable(source.specs) or nil,
    }
    SAU.StampOwner(store)

    local profile = addon.db and addon.db.profile
    if profile then
        -- Styling copy must land in profile.components BEFORE EnsureComponentDB
        -- links the new component, or the copy arrives as defaults.
        local components = rawget(profile, "components")
        local sourceStyling = components and components[SAU.GetComponentId(trackerId)]
        if sourceStyling and next(sourceStyling) then
            components[SAU.GetComponentId(newId)] = CopyTable(sourceStyling)
        end
        local positions = rawget(profile, "scootAuraPositions")
        local sourcePos = positions and positions["t" .. trackerId]
        if sourcePos then
            local copy = {}
            for layoutName, pos in pairs(sourcePos) do
                copy[layoutName] = { point = pos.point, x = (pos.x or 0) + 20, y = (pos.y or 0) - 20 }
            end
            positions["t" .. newId] = copy
        end
    end

    SAU.RegisterTrackerComponent(newId)
    addon:EnsureComponentDB(SAU.GetComponentId(newId))
    if source.shape == "bar" then
        SAU.ApplyBarStartingValues(newId)
    end
    if source.kind == "missingbuff" then
        SAU.ApplyMissingStartingValues(newId)
    end
    SAU.Engine.ClaimForTracker(newId)
    return newId
end

--- Duplicates a tracker that belongs to a group, placing the copy in the same
-- group directly after it. A tracker outside a group gets a plain duplicate.
function SAU.DuplicateTrackerInGroup(trackerId)
    local source = SAU.GetTracker(trackerId)
    if not source then return nil, "no such tracker" end
    local gid = source.groupId
    local newId, err = SAU.DuplicateTracker(trackerId)
    if not newId then return nil, err end

    local group = gid and SAU.GetGroup(gid)
    local order = group and group.memberOrder
    if not order then return newId end
    local at = #order + 1
    for i, id in ipairs(order) do
        if id == trackerId then at = i + 1; break end
    end
    SAU.SetTrackerGroup(newId, gid, at)
    return newId
end

function SAU.SetTrackerEnabled(trackerId, enabled)
    local tracker = SAU.GetTracker(trackerId)
    if not tracker then return nil, "no such tracker" end
    tracker.enabled = not not enabled
    if SAU._ApplyStyling then SAU._ApplyStyling(trackerId, tracker) end
    return true
end

--- Restricts a tracker to a set of spec IDs. An empty or nil list clears the
-- restriction. Re-styling is the whole consequence: the disabled branch of
-- _ApplyStyling parks the container and hides the visual, all combat-legal.
function SAU.SetTrackerSpecs(trackerId, ids)
    local tracker = SAU.GetTracker(trackerId)
    if not tracker then return nil, "no such tracker" end
    tracker.specs = NormalizeSpecs(ids)
    if SAU._ApplyStyling then SAU._ApplyStyling(trackerId, tracker) end
    if SAU.Groups then SAU.Groups.RequestReflow() end
    return true
end

function SAU.ToggleTrackerSpec(trackerId, specID)
    local tracker = SAU.GetTracker(trackerId)
    if not tracker then return nil, "no such tracker" end
    return SAU.SetTrackerSpecs(trackerId, ToggledSpecs(tracker.specs, specID))
end

--- Writes styling keys on the tracker's component db and restyles. The
-- editor's setAndApply ends in the same two steps (component db write, then
-- the component's ApplyStyling), so a second surface writing through here
-- (the Edit Mode mirror) cannot drift from the Sizing tab.
function SAU.SetTrackerStyling(trackerId, changes)
    local tracker = SAU.GetTracker(trackerId)
    if not tracker then return nil, "no such tracker" end
    local comp = SAU.RegisterTrackerComponent(trackerId)
    if not comp then return nil, "no component" end
    if addon.EnsureComponentDB then addon:EnsureComponentDB(comp) end
    if not comp.db then return nil, "no component db" end
    for key, value in pairs(changes or {}) do
        comp.db[key] = value
    end
    if SAU._ApplyStyling then SAU._ApplyStyling(trackerId, tracker) end
    return true
end

function SAU.RenameTracker(trackerId, name)
    local tracker = SAU.GetTracker(trackerId)
    if not tracker or type(name) ~= "string" or name == "" then return nil, "bad rename" end
    tracker.name = name
    SAU.Engine.UpdateEditModeName(trackerId)
    return true
end

--- Display name shared by the editor title, its carousel, and the list rows.
function SAU.DisplayName(tracker)
    if not tracker then return "" end
    return tracker.name or ("Aura " .. tostring(tracker.spellId))
end

--------------------------------------------------------------------------------
-- Group CRUD (content writes)
--------------------------------------------------------------------------------

SAU.GROUP_SETTING_DEFAULTS = { spacing = 4, grow = "RIGHT", scale = 100 }

function SAU.CreateGroup(name)
    if not SAU.IsModuleActive() then
        return nil, "ScootAuras module is disabled (enable it on the Features page, then reload)"
    end
    local store = SAU.EnsureStore()
    if not store then return nil, "profile not ready" end

    local gid = AllocateId(store)
    store.groups[gid] = {
        name = (type(name) == "string" and name ~= "") and name or ("Aura Group " .. gid),
        settings = CopyTable(SAU.GROUP_SETTING_DEFAULTS),
        memberOrder = {},
        owner = SAU.GetOwnerKey(),
    }
    SAU.StampOwner(store)
    SAU.Groups.ClaimForGroup(gid)
    SAU.Groups.LayoutGroup(gid)
    return gid
end

--- Deletes a group. Its members are kept: each returns to standalone form at
-- the screen spot where it currently renders.
function SAU.DeleteGroup(gid)
    local store = SAU.GetStore()
    local group = SAU.GetGroup(gid)
    if not group then return nil, "no such group" end

    for _, trackerId in ipairs(group.memberOrder or {}) do
        local tracker = SAU.GetTracker(trackerId)
        if tracker and tracker.groupId == gid then
            SAU.Groups.SnapShellToVisual(trackerId)
            tracker.groupId = nil
        end
    end
    store.groups[gid] = nil
    SAU.Groups.ReleaseForGroup(gid)

    local profile = addon.db and addon.db.profile
    if profile then
        local positions = rawget(profile, "scootAuraPositions")
        if positions then positions["g" .. gid] = nil end
    end
    SAU.Groups.ApplyMembership()
    return true
end

function SAU.RenameGroup(gid, name)
    local group = SAU.GetGroup(gid)
    if not group or type(name) ~= "string" or name == "" then return nil, "bad rename" end
    group.name = name
    SAU.Groups.UpdateEditModeName(gid)
    return true
end

--- Applies layout settings (spacing, grow direction, scale) to a group.
function SAU.SetGroupSettings(gid, changes)
    local group = SAU.GetGroup(gid)
    if not group then return nil, "no such group" end
    group.settings = group.settings or CopyTable(SAU.GROUP_SETTING_DEFAULTS)
    if changes.spacing ~= nil then
        local s = tonumber(changes.spacing)
        if s then group.settings.spacing = math.max(0, math.min(s, 100)) end
    end
    if changes.scale ~= nil then
        local s = tonumber(changes.scale)
        if s then group.settings.scale = math.max(25, math.min(s, 200)) end
    end
    if changes.grow ~= nil and SAU.Groups.VALID_GROW[changes.grow] then
        group.settings.grow = changes.grow
        -- A user-chosen direction is final: the first-member default below
        -- never overrides it.
        group.settings.growTouched = true
    end
    SAU.Groups.LayoutGroup(gid)
    return true
end

--- Restricts a group to a set of spec IDs. Members gate on their own list and
-- their group's, so a blocked group lays out zero members and hides its frame
-- outside Edit Mode (groups.lua).
function SAU.SetGroupSpecs(gid, ids)
    local group = SAU.GetGroup(gid)
    if not group then return nil, "no such group" end
    group.specs = NormalizeSpecs(ids)
    SAU.RebuildAll()
    if SAU.Groups then SAU.Groups.RequestReflow() end
    return true
end

function SAU.ToggleGroupSpec(gid, specID)
    local group = SAU.GetGroup(gid)
    if not group then return nil, "no such group" end
    return SAU.SetGroupSpecs(gid, ToggledSpecs(group.specs, specID))
end

-- Starting grow direction from the group's first member: bars are horizontal,
-- so stacking them DOWN keeps them apart; everything else reads best in a row
-- growing RIGHT. (Vertical bars, when they exist, belong on the RIGHT branch.)
local function ApplyDefaultGrow(group, tracker)
    if group.settings and group.settings.growTouched then return end
    group.settings = group.settings or CopyTable(SAU.GROUP_SETTING_DEFAULTS)
    group.settings.grow = (tracker.shape == "bar") and "DOWN" or "RIGHT"
end

--- Moves a tracker into a group (at index, default the end), between groups,
-- within a group (reorder; index counts positions AFTER the removal), or out
-- of every group (gid = nil, the shell snaps to where the visual renders).
-- The single entry point drag-and-drop uses.
function SAU.SetTrackerGroup(trackerId, gid, index)
    local tracker = SAU.GetTracker(trackerId)
    if not tracker then return nil, "no such tracker" end
    local store = SAU.GetStore()
    local group = (gid ~= nil) and SAU.GetGroup(gid) or nil
    if gid ~= nil and not group then
        return nil, "no such group"
    end
    if group and group.owner ~= tracker.owner then
        return nil, "tracker and group belong to different characters"
    end

    local oldGid = tracker.groupId
    if oldGid then
        local oldGroup = store and store.groups and store.groups[oldGid]
        if oldGroup and oldGroup.memberOrder then
            for i, id in ipairs(oldGroup.memberOrder) do
                if id == trackerId then
                    table.remove(oldGroup.memberOrder, i)
                    break
                end
            end
        end
    end

    if gid then
        group.memberOrder = group.memberOrder or {}
        local wasEmpty = #group.memberOrder == 0
        local at = tonumber(index) or (#group.memberOrder + 1)
        at = math.max(1, math.min(at, #group.memberOrder + 1))
        table.insert(group.memberOrder, at, trackerId)
        tracker.groupId = gid
        if wasEmpty then
            ApplyDefaultGrow(group, tracker)
        end
    else
        if oldGid then
            SAU.Groups.SnapShellToVisual(trackerId)
        end
        tracker.groupId = nil
    end

    SAU.Groups.ApplyMembership()
    return true
end

--- Duplicates a group and a copy of every member. The copies join the new
-- group in the same order; the new group lands offset from the source.
function SAU.DuplicateGroup(gid)
    local source = SAU.GetGroup(gid)
    if not source then return nil, "no such group" end
    local store = SAU.EnsureStore()
    if not store then return nil, "profile not ready" end

    local newGid = AllocateId(store)
    local newGroup = {
        name = (source.name or ("Aura Group " .. gid)) .. " copy",
        settings = CopyTable(source.settings or SAU.GROUP_SETTING_DEFAULTS),
        memberOrder = {},
        owner = SAU.GetOwnerKey(),
        specs = source.specs and CopyTable(source.specs) or nil,
    }
    store.groups[newGid] = newGroup
    SAU.StampOwner(store)

    for _, memberId in ipairs(source.memberOrder or {}) do
        if SAU.GetTracker(memberId) then
            local newId = SAU.DuplicateTracker(memberId)
            if newId then
                local copy = SAU.GetTracker(newId)
                copy.groupId = newGid
                table.insert(newGroup.memberOrder, newId)
            end
        end
    end

    local profile = addon.db and addon.db.profile
    if profile then
        local positions = rawget(profile, "scootAuraPositions")
        local sourcePos = positions and positions["g" .. gid]
        if sourcePos then
            local copy = {}
            for layoutName, pos in pairs(sourcePos) do
                copy[layoutName] = { point = pos.point, x = (pos.x or 0) + 20, y = (pos.y or 0) - 20 }
            end
            positions["g" .. newGid] = copy
        end
    end

    SAU.Groups.ClaimForGroup(newGid)
    SAU.Groups.ApplyMembership()
    return newGid
end

--- Repairs tracker/group cross-references. Normal writes keep both sides in
-- step; this guards against manual saved-variable edits and bugs, because a
-- dangling groupId hides the tracker from both panes of the Aura List.
function SAU.ValidateGroupData()
    local store = SAU.GetStore()
    if not store then return end
    local trackers = store.trackers or {}
    local groups = store.groups or {}

    -- Whole-store pass (every owner): a dangling groupId, or membership across
    -- two characters, hides the tracker from both panes of its owner's list.
    for _, tracker in pairs(trackers) do
        local group = tracker.groupId ~= nil and groups[tracker.groupId] or nil
        if tracker.groupId ~= nil and (not group or group.owner ~= tracker.owner) then
            tracker.groupId = nil
        end
    end

    for gid, group in pairs(groups) do
        local order = group.memberOrder or {}
        local seen, cleaned = {}, {}
        for _, trackerId in ipairs(order) do
            local tracker = trackers[trackerId]
            if tracker and tracker.groupId == gid and not seen[trackerId] then
                seen[trackerId] = true
                table.insert(cleaned, trackerId)
            end
        end
        group.memberOrder = cleaned
        for trackerId, tracker in pairs(trackers) do
            if tracker.groupId == gid and not seen[trackerId] then
                table.insert(group.memberOrder, trackerId)
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Profile / Edit Mode layout reconcile
--------------------------------------------------------------------------------

-- Switching Edit Mode layout is a profile switch is a mass tracker
-- create/delete with no reload. Idempotent over current pool occupancy;
-- positions re-applied last because the LibEditMode layout callback and the
-- AceDB profile callback race on the same user action.
function SAU.ReconcileForActiveProfile(reason)
    local Engine = SAU.Engine
    if not Engine or not Engine.IsInitialized() then return end

    -- Adopt before validating so the owner-consistency repair never splits a
    -- pre-ownership group from its members.
    if SAU.IsModuleActive() then SAU.AdoptUnowned("reconcile:" .. tostring(reason)) end
    SAU.ValidateGroupData()
    local trackers = SAU.IsModuleActive() and SAU.OwnedTrackers() or {}

    -- Park pool occupants absent from (or stale in) the new profile, and any
    -- that belong to another character.
    Engine.ReleaseAllExcept(trackers)

    -- Claim/create the new profile's trackers. Claim verifies wired content
    -- against the tracker (same id can mean a different spell per profile).
    for trackerId in pairs(trackers) do
        SAU.RegisterTrackerComponent(trackerId)
        addon:EnsureComponentDB(SAU.GetComponentId(trackerId))
        Engine.ClaimForTracker(trackerId)
    end

    -- Groups after trackers: membership reparents claimed visuals.
    if SAU.Groups then SAU.Groups.ApplyAll() end

    Engine.ApplyPositionsForActiveLayout()
    SAU.RebuildAll()
    if Engine.Record then Engine.Record("reconcile", tostring(reason)) end
end

function SAU.RebuildAll()
    if not SAU._ApplyStyling then return end
    for trackerId, tracker in pairs(SAU.OwnedTrackers()) do
        SAU._ApplyStyling(trackerId, tracker)
    end
end
