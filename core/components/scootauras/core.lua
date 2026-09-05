-- scootauras/core.lua - User-built aura trackers: store, settings, CRUD, reconcile
--
-- Auras are account-wide. One store, db.global.scootAuras, holds content
-- (spell, kind, unit, shape, name, enabled, grouping, specs), styling keyed by
-- component id, and positions keyed t<id>/g<gid> then by Edit Mode layout. Every
-- character sees every aura; the spec list on each record decides where it
-- loads. Content writes go through the API here so engine consequences route
-- through the structural gate; styling writes go through the normal component
-- setAndApply path, which reaches the global table through the component's
-- GetContainer hook.
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
    local global = addon.db and addon.db.global
    return global and rawget(global, "scootAuras") or nil
end

function SAU.EnsureStore()
    local global = addon.db and addon.db.global
    if not global then return nil end
    local store = rawget(global, "scootAuras")
    if type(store) ~= "table" then
        store = { nextId = 1, trackers = {}, groups = {}, styling = {}, positions = {} }
        global.scootAuras = store
    end
    store.trackers = store.trackers or {}
    store.groups = store.groups or {}
    store.styling = store.styling or {}
    store.positions = store.positions or {}
    store.nextId = store.nextId or 1
    -- Left behind by the first cadence-lock build; nothing reads it.
    store.learnedDurations = nil
    return store
end

--- The table holding every tracker component's settings, handed to the base
-- component layer through each component's GetContainer hook.
function SAU.GetStylingContainer(create)
    local store = create and SAU.EnsureStore() or SAU.GetStore()
    if not store then return nil end
    if create then store.styling = store.styling or {} end
    return rawget(store, "styling")
end

--- The position store, keyed "t<id>"/"g<gid>" then by Edit Mode layout name.
function SAU.GetPositionStore(create)
    local store = create and SAU.EnsureStore() or SAU.GetStore()
    if not store then return nil end
    if create then store.positions = store.positions or {} end
    return rawget(store, "positions")
end

--------------------------------------------------------------------------------
-- Record access
--
-- Auras are account-wide: every character sees every tracker and group, and the
-- spec list on each record decides where it loads. There is no per-character
-- filtering at this layer, so these getters are plain store reads.
--------------------------------------------------------------------------------

function SAU.GetTracker(trackerId)
    local store = SAU.GetStore()
    return store and store.trackers and store.trackers[trackerId] or nil
end

function SAU.GetGroup(gid)
    local store = SAU.GetStore()
    return store and store.groups and store.groups[gid] or nil
end

--- Every tracker as { [id] = tracker }. Fresh table; never materializes the store.
function SAU.AllTrackers()
    local out = {}
    local store = SAU.GetStore()
    if store and store.trackers then
        for id, tracker in pairs(store.trackers) do
            if type(tracker) == "table" then
                out[id] = tracker
            end
        end
    end
    return out
end

function SAU.AllGroups()
    local out = {}
    local store = SAU.GetStore()
    if store and store.groups then
        for gid, group in pairs(store.groups) do
            if type(group) == "table" then
                out[gid] = group
            end
        end
    end
    return out
end

-- Ids are shared between trackers and groups and unique account-wide, which is
-- what keeps the styling key "scootAura_<id>" and the position keys "t<id>" and
-- "g<gid>" unambiguous. Bumping past any id already in use guards a hand-merged
-- store whose nextId lags behind its records.
local function AllocateId(store)
    local id = tonumber(store.nextId) or 1
    while (store.trackers and store.trackers[id]) or (store.groups and store.groups[id]) do
        id = id + 1
    end
    store.nextId = id + 1
    return id
end
SAU._AllocateId = AllocateId

--- Returns a sorted array of { id, tracker } for stable iteration.
function SAU.SortedTrackers()
    local out = {}
    for id, tracker in pairs(SAU.AllTrackers()) do
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

--- Returns a sorted array of { id, group } for stable iteration.
function SAU.SortedGroups()
    local out = {}
    for gid, group in pairs(SAU.AllGroups()) do
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

-- Every tracker and group carries `specs`, an array of numeric spec IDs it
-- loads in, stamped at create with every spec of the creating character's
-- class. The gate fails closed: an empty list loads nowhere, which the Aura
-- List shows as Not Loaded and the spec fly-out fixes.

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

--- Spec IDs for a class token ("PRIEST"), in Blizzard's own order. Sits on the
-- Rules spec buckets so the addon keeps one enumeration of every class's specs.
function SAU.SpecIDsForClassToken(token)
    local out = {}
    if type(token) ~= "string" then return out end
    local Rules = addon.Rules
    if not (Rules and Rules.GetSpecBuckets) then return out end
    local ok, buckets = pcall(Rules.GetSpecBuckets, Rules)
    if not ok or type(buckets) ~= "table" then return out end
    for _, classEntry in ipairs(buckets) do
        if classEntry.file == token then
            for _, spec in ipairs(classEntry.specs or {}) do
                if type(spec.specID) == "number" then
                    table.insert(out, spec.specID)
                end
            end
            break
        end
    end
    return out
end

--- Every spec of the player's own class, stamped onto records at create.
function SAU.DefaultSpecsForPlayer()
    local token = addon.GetClassTokenForUnit and addon.GetClassTokenForUnit("player") or nil
    local ids = SAU.SpecIDsForClassToken(token)
    if #ids > 0 then return ids end
    -- Class data missing this early is not a reason to write an empty list: an
    -- aura stamped with nothing would load nowhere and read as broken.
    local out = {}
    local Profiles = addon.Profiles
    if Profiles and Profiles.GetSpecOptions then
        local ok, options = pcall(Profiles.GetSpecOptions, Profiles)
        if ok and type(options) == "table" then
            for _, opt in ipairs(options) do
                if type(opt.specID) == "number" then table.insert(out, opt.specID) end
            end
        end
    end
    return out
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
-- closed: an empty list loads nowhere, and an unresolved spec during early login
-- blocks everything until the PLAYER_ENTERING_WORLD and spec-change passes
-- re-run activation.
function SAU.SpecAllows(record)
    local specs = record and record.specs
    if type(specs) ~= "table" or #specs == 0 then return false end
    local current = SAU.CurrentSpecID()
    if not current then return false end
    for _, id in ipairs(specs) do
        if id == current then return true end
    end
    return false
end

--- Whether a group loads in the current spec. The list, the group layout, and
-- the Edit Mode mirror all ask this one function.
function SAU.IsGroupActive(gid, group)
    group = group or SAU.GetGroup(gid)
    if not group then return false end
    return SAU.SpecAllows(group)
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
        local group = SAU.GetGroup(tracker.groupId)
        if group and not SAU.SpecAllows(group) then return false end
    end
    return true
end

--- Whether this tracker is set to show only while the player is in combat.
-- Only a tracker saved before the option existed carries no value: a
-- missing-buff reminder has always been gated by default, and a buff or debuff
-- tracker has always shown whenever its aura was up, which an upgrade must not
-- change under its owner.
function SAU.OnlyInCombat(tracker)
    if not tracker then return false end
    if tracker.onlyInCombat ~= nil then return tracker.onlyInCombat ~= false end
    return tracker.kind == "missingbuff"
end

--- The combat gate: whether an "Only in Combat" tracker may show right now.
-- Edit Mode forces it open, because the preview and the draggable frame live
-- under the frame the gate hides.
--
-- Never fold this into IsTrackerActive. That one drives claim and release, and
-- a release is a teardown whose rebuild waits behind CanDoStructuralWork until
-- the fight ends. This decides visibility only.
function SAU.CombatGateOpen(tracker)
    if not SAU.OnlyInCombat(tracker) then return true end
    if InCombatLockdown() then return true end
    return (SAU._isEditModeActive and SAU._isEditModeActive()) or false
end

-- Numbers only, deduped, sorted. Returns nil for an empty list so "loads
-- nowhere" has one representation rather than two.
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

--- Finishes migration V8. Records moved out of the per-profile stores carry
-- `_pendingSpecClass` instead of a spec list, because turning a class token into
-- spec IDs needs class data the migration cannot count on at ADDON_LOADED.
-- `true` means the record had no known owner, so it goes to whoever loads first,
-- the rule the old adoption pass used. Writes nothing when nothing is pending.
function SAU.ResolvePendingSpecStamps()
    local store = SAU.GetStore()
    if not store then return 0 end
    local resolved = 0
    local mine
    for _, record in pairs(store.trackers or {}) do
        if type(record) == "table" and record._pendingSpecClass ~= nil then
            local ids
            if record._pendingSpecClass == true then
                mine = mine or SAU.DefaultSpecsForPlayer()
                ids = mine
            else
                ids = SAU.SpecIDsForClassToken(record._pendingSpecClass)
            end
            if #ids > 0 then
                record.specs = NormalizeSpecs(ids)
                record._pendingSpecClass = nil
                resolved = resolved + 1
            end
        end
    end
    for _, record in pairs(store.groups or {}) do
        if type(record) == "table" and record._pendingSpecClass ~= nil then
            local ids
            if record._pendingSpecClass == true then
                mine = mine or SAU.DefaultSpecsForPlayer()
                ids = mine
            else
                ids = SAU.SpecIDsForClassToken(record._pendingSpecClass)
            end
            if #ids > 0 then
                record.specs = NormalizeSpecs(ids)
                record._pendingSpecClass = nil
                resolved = resolved + 1
            end
        end
    end
    if resolved > 0 and SAU.Engine and SAU.Engine.Record then
        SAU.Engine.Record("specstamp", tostring(resolved))
    end
    return resolved
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
-- trackers offer the player and "group", which is the whole party or raid
-- rather than one token (missing.lua resolves it).
SAU.VALID_UNITS = {
    buff        = { player = true, target = true, focus = true },
    debuff      = { target = true, focus = true },
    missingbuff = { player = true, group = true },
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

-- The "When it's missing, show..." options a shape offers. The field is
-- content (tracker.missingVisual); nil means Nothing, so trackers saved before
-- the field existed need no migration. The visuals are reveal-shaped: Scoot
-- art beneath the engine button (underlay.lua), never a presence read. Icon
-- and shape share tokens, so a flip between them carries the choice; a bar
-- token strands on any other shape and coerces to nil like a stranded unit.
SAU.VALID_MISSING_VISUALS_BY_SHAPE = {
    icon  = { desat = true, blink = true, blinkdesat = true },
    bar   = { emptybar = true, blinkemptybar = true, blinkicon = true, blinkdesaticon = true },
    shape = { desat = true, blink = true, blinkdesat = true },
}

-- Token traits, so no caller string-matches tokens. art "self" reuses the
-- shape's own art; "emptybar" shows the bar frame with no fill; "baricon"
-- centers an icon on the bar rect. `opacity` marks the tokens that carry the
-- Opacity sub-option: the editor puts a gear in the selector field for exactly
-- those, and underlay.lua reads missingVisualOpacity for exactly those.
local MISSING_VISUAL_TRAITS = {
    desat          = { desat = true,  blink = false, art = "self", opacity = true },
    blink          = { desat = false, blink = true,  art = "self" },
    blinkdesat     = { desat = true,  blink = true,  art = "self" },
    emptybar       = { desat = false, blink = false, art = "emptybar" },
    blinkemptybar  = { desat = false, blink = true,  art = "emptybar" },
    blinkicon      = { desat = false, blink = true,  art = "baricon" },
    blinkdesaticon = { desat = true,  blink = true,  art = "baricon" },
}

--- The one scope switch for missing-state visuals. Debuff only by decision
-- (2026-08-29): the Missing Buff kind owns the buff case.
function SAU.KindSupportsMissingVisual(kind)
    return kind == "debuff"
end

--- Resolves a tracker's missing-state visual to a token, or "none". nil, a
-- token the shape does not offer, and an unsupported kind all read as none.
function SAU.MissingVisualFor(tracker)
    if not tracker then return "none" end
    local token = tracker.missingVisual
    if not token then return "none" end
    if not SAU.KindSupportsMissingVisual(tracker.kind) then return "none" end
    local valid = SAU.VALID_MISSING_VISUALS_BY_SHAPE[tracker.shape]
    if not valid or not valid[token] then return "none" end
    return token
end

--- Trait record for a token, or nil for "none" and anything unknown.
function SAU.MissingVisualTraits(token)
    return token and MISSING_VISUAL_TRAITS[token] or nil
end

-- Own-cast filtering: a debuff tracker watches the player's own aura on the
-- enemy; buffs accept any source (external buffs on the player are the point).
-- A missing-buff tracker matches the same HELPFUL slot; only its rendering
-- differs (the engine's presence hides the visual instead of showing it).
function SAU.FilterForKind(kind)
    if kind == "debuff" then return "HARMFUL|PLAYER" end
    return "HELPFUL"
end

--- The unit an AuraContainer binds to for a tracker. "group" is not a unit
-- token: a group missing-buff tracker keeps the player container as its own
-- presence gate and reads the rest of the group in plain Lua (missing.lua), so
-- flipping Myself and My Group needs no rebuild.
function SAU.EngineUnitFor(tracker)
    local unit = tracker and tracker.unit
    if unit == "group" then return "player" end
    return unit
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
        -- Missing-state visual on a debuff tracker (underlay.lua). Read only
        -- for tokens whose traits carry `opacity`. The underlay root is a
        -- child of the visual, so this multiplies with the tracker's own
        -- opacity rather than replacing it.
        missingVisualOpacity    = { type = "addon", default = 100 },
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
-- Called when the catalog itself moves: data loads, hotfixes, spec changes,
-- and talent edits. A runtime substitution goes through NoteSpellOverride.
function SAU.InvalidateSpellDescriptions()
    cdmDisplayByBase = nil
end

--- Records one runtime substitution against the cached map.
-- The catalog does not move when a spell is substituted, but the entry's own
-- overrideSpellID does: Blizzard patches it in place the moment this event
-- lands (CooldownViewerItemDataMixin:SetOverrideSpell), and the map above is
-- built from that field, so leaving the map alone freezes the substitution out
-- of every answer this file gives. Patch the one base instead of dropping the
-- whole map, which would walk every category again on the next description.
-- The removal branch also repairs a map built while a substitution was already
-- live, which is what a reload in Voidform produces.
function SAU.NoteSpellOverride(baseSpellID, overrideSpellID)
    local base = PlainNumber(baseSpellID)
    if not base or not cdmDisplayByBase then return end
    local shown = PlainNumber(overrideSpellID)
    if shown and shown ~= base then
        cdmDisplayByBase[base] = shown
    elseif cdmDisplayByBase[base] and cdmDisplayByBase[base] ~= base then
        cdmDisplayByBase[base] = base
    end
end

-- The ID the game resolves a stored ID to right now: CDM override chain, else
-- the player's own override, else the ID itself. What DisplaySpellFor used to
-- return outright, before the substitution test below.
local function DisplayCandidate(spellId)
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

--- The override the engine's own candidate filter cannot match, or nil.
-- A talent override is unioned into the include set by ExpandFromCDM, so it
-- never escapes and the container matches its aura as usual. A form swap is
-- reachable from no CDM entry, so the container stays blind to it and its
-- geometry stops answering the question the caller thinks it answers.
function SAU.EscapingOverrideFor(spellId)
    if type(spellId) ~= "number" then return nil end
    local candidate = DisplayCandidate(spellId)
    if candidate == spellId then return nil end
    if addon.AuraIds and addon.AuraIds.IncludesId(spellId, candidate) then
        return nil
    end
    return candidate
end

--- The spell ID a stored ID is shown as. Never an ID the engine's filter
-- cannot match: a spell the game has substituted (Shadowform while Voidform is
-- up) is a replacement for what the user picked, not a description of it, and
-- describing by it renames trackers, repaints icons, and can be stamped into a
-- saved auto name.
function SAU.DisplaySpellFor(spellId)
    if type(spellId) ~= "number" then return spellId end
    local candidate = DisplayCandidate(spellId)
    if candidate == spellId then return spellId end
    if addon.AuraIds and addon.AuraIds.IncludesId(spellId, candidate) then
        return candidate
    end
    return spellId
end

--- The ID the game resolves this one to, matchable by the engine's filter or
-- not. Only the debug readout wants this: every display path goes through
-- DisplaySpellFor, which hides a substitution the filter cannot match.
function SAU.ResolvedSpellFor(spellId)
    if type(spellId) ~= "number" then return spellId end
    return DisplayCandidate(spellId)
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
        -- Auras are account-wide, so their styling lives beside their content in
        -- db.global.scootAuras rather than in profile.components.
        GetContainer = SAU.GetStylingContainer,
        ApplyStyling = function()
            local tracker = SAU.GetTracker(trackerId)
            if tracker and SAU._ApplyStyling then
                SAU._ApplyStyling(trackerId, tracker)
            end
        end,
        RefreshOpacity = function()
            local tracker = SAU.GetTracker(trackerId)
            if tracker and SAU._RefreshOpacity then
                SAU._RefreshOpacity(trackerId, tracker)
            end
        end,
    })
    addon:RegisterComponent(comp)
    return addon.Components and addon.Components[componentId] or nil
end

-- Registered at init so LinkComponentsToDB picks up persisted styling tables.
addon:RegisterComponentInitializer(function(self)
    for trackerId in pairs(SAU.AllTrackers()) do
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
        -- Every spec of this character's class. The aura is listed on every
        -- character on the account and loads only where its specs say.
        specs = SAU.DefaultSpecsForPlayer(),
        spellId = spellId,
        kind = kind,
        unit = unit,
        shape = shape,
        name = spec.name or PlainSpellName(spellId),
        enabled = true,
        order = trackerId,
    }
    -- Content, not styling: they decide when the tracker may show at all. Every
    -- kind carries the combat gate, and a new tracker starts gated unless the
    -- editor says otherwise (a My Group reminder passes false, since raid buffs
    -- go up between pulls). The instance gate is a missing-buff field.
    store.trackers[trackerId].onlyInCombat = (spec.onlyInCombat ~= false)
    if kind == "missingbuff" then
        store.trackers[trackerId].onlyInInstances = (spec.onlyInInstances == true)
    end
    local missingValid = SAU.KindSupportsMissingVisual(kind)
        and SAU.VALID_MISSING_VISUALS_BY_SHAPE[shape]
    if missingValid and missingValid[spec.missingVisual] then
        store.trackers[trackerId].missingVisual = spec.missingVisual
    end

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

    local styling = SAU.GetStylingContainer(false)
    if styling then styling[componentId] = nil end
    local positions = SAU.GetPositionStore(false)
    if positions then positions["t" .. trackerId] = nil end
    store.trackers[trackerId] = nil
    if SAU.Groups then SAU.Groups.RequestReflow() end
    return true
end

--- Applies content edits (spellId/kind/unit/shape/onlyInCombat/onlyInInstances/
-- missingVisual) to a live tracker and routes the engine consequence: shape and gate edits
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
    if changes.onlyInCombat ~= nil then
        tracker.onlyInCombat = (changes.onlyInCombat ~= false)
    elseif tracker.onlyInCombat == nil then
        -- A tracker saved before its kind carried this field. Freeze the
        -- reading it has been running on rather than seeding a default, so
        -- editing a legacy buff or debuff tracker's spell does not silently
        -- start hiding it. The kind read here is already the new one, which is
        -- what a flip to missingbuff wants.
        tracker.onlyInCombat = SAU.OnlyInCombat(tracker)
    end
    if kind == "missingbuff" then
        -- Backfills to false, not true: this gate defaults off, so a tracker
        -- that predates it keeps showing outside instances as it always has.
        if changes.onlyInInstances ~= nil then
            tracker.onlyInInstances = (changes.onlyInInstances == true)
        elseif tracker.onlyInInstances == nil then
            tracker.onlyInInstances = false
        end
    else
        tracker.onlyInInstances = nil
    end
    if changes.missingVisual ~= nil then
        -- Explicit write: "none" clears, and the `changes.X or tracker.X`
        -- idiom cannot clear a field.
        tracker.missingVisual = (changes.missingVisual ~= "none") and changes.missingVisual or nil
    end
    -- One coercion covers every flip: a kind that does not carry the field and
    -- a token the new shape does not offer both clear it.
    if tracker.missingVisual ~= nil then
        local missingValid = SAU.KindSupportsMissingVisual(kind)
            and SAU.VALID_MISSING_VISUALS_BY_SHAPE[shape]
        if not missingValid or not missingValid[tracker.missingVisual] then
            tracker.missingVisual = nil
        end
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
        onlyInCombat = source.onlyInCombat,
        onlyInInstances = source.onlyInInstances,
        missingVisual = source.missingVisual,
        specs = source.specs and CopyTable(source.specs) or nil,
    }

    -- Styling copy must land in the container BEFORE EnsureComponentDB links
    -- the new component, or the copy arrives as defaults.
    local styling = SAU.GetStylingContainer(true)
    local sourceStyling = styling and styling[SAU.GetComponentId(trackerId)]
    if styling and sourceStyling and next(sourceStyling) then
        styling[SAU.GetComponentId(newId)] = CopyTable(sourceStyling)
    end
    local positions = SAU.GetPositionStore(true)
    local sourcePos = positions and positions["t" .. trackerId]
    if positions and sourcePos then
        local copy = {}
        for layoutName, pos in pairs(sourcePos) do
            copy[layoutName] = { point = pos.point, x = (pos.x or 0) + 20, y = (pos.y or 0) - 20 }
        end
        positions["t" .. newId] = copy
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
    SAU.ReconcileActivation("enable:" .. tostring(trackerId))
    return true
end

--- Sets the specs a tracker loads in. An empty or nil list means it loads
-- nowhere. Activation is the whole consequence: claiming and releasing are both
-- combat-legal, and a released tracker leaves Edit Mode with its frame.
function SAU.SetTrackerSpecs(trackerId, ids)
    local tracker = SAU.GetTracker(trackerId)
    if not tracker then return nil, "no such tracker" end
    tracker.specs = NormalizeSpecs(ids)
    SAU.ReconcileActivation("specs:t" .. tostring(trackerId))
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
        specs = SAU.DefaultSpecsForPlayer(),
    }
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

    local positions = SAU.GetPositionStore(false)
    if positions then positions["g" .. gid] = nil end
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
    SAU.ReconcileActivation("specs:g" .. tostring(gid))
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
        specs = source.specs and CopyTable(source.specs) or nil,
    }
    store.groups[newGid] = newGroup

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

    local positions = SAU.GetPositionStore(true)
    local sourcePos = positions and positions["g" .. gid]
    if positions and sourcePos then
        local copy = {}
        for layoutName, pos in pairs(sourcePos) do
            copy[layoutName] = { point = pos.point, x = (pos.x or 0) + 20, y = (pos.y or 0) - 20 }
        end
        positions["g" .. newGid] = copy
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

    -- A dangling groupId hides the tracker from both panes of the Aura List:
    -- it is filtered out of the individual column and its group is gone.
    for _, tracker in pairs(trackers) do
        local group = tracker.groupId ~= nil and groups[tracker.groupId] or nil
        if tracker.groupId ~= nil and not group then
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

-- Switching Edit Mode layout switches profile, which no longer decides which
-- auras exist: the store is account-wide. What it can change is the module
-- toggle and the active layout name, so this re-runs activation and re-applies
-- positions last, because the LibEditMode layout callback and the AceDB profile
-- callback race on the same user action.
function SAU.ReconcileForActiveProfile(reason)
    local Engine = SAU.Engine
    if not Engine or not Engine.IsInitialized() then return end

    SAU.ValidateGroupData()
    -- Cheap when nothing is pending, and the PEW pass is skipped entirely while
    -- the module is off, so this is the second chance after it is turned on.
    SAU.ResolvePendingSpecStamps()
    SAU.ReconcileActivation("reconcile:" .. tostring(reason))
    Engine.ApplyPositionsForActiveLayout()
    if Engine.Record then Engine.Record("reconcile", tostring(reason)) end
end

--- Claims every tracker that should be live and releases every one that should
-- not. With account-wide auras most records are gated out on any given
-- character, and a released tracker holds no pool entry and no container.
--
-- This is also what makes the ON/OFF pill work from a cold start: _ApplyStyling
-- early-returns without an active state, so a tracker that was never claimed
-- could not be switched on by a restyle alone.
function SAU.ReconcileActivation(reason)
    local Engine = SAU.Engine
    if not Engine or not Engine.IsInitialized() then return end

    local active = {}
    if SAU.IsModuleActive() then
        for trackerId, tracker in pairs(SAU.AllTrackers()) do
            -- Every tracker gets a component, loaded or not: the editor opens on
            -- unloaded auras too, and without a registered component its reads
            -- resolve to nil and its writes go nowhere. Linking (rather than
            -- EnsureComponentDB) leaves an unconfigured aura on the defaults
            -- proxy instead of materializing an empty styling table for it.
            SAU.RegisterTrackerComponent(trackerId)
            local comp = addon.Components and addon.Components[SAU.GetComponentId(trackerId)]
            if comp and not comp.db then addon:LinkComponent(comp) end
            if SAU.IsTrackerActive(trackerId, tracker) then
                active[trackerId] = tracker
            end
        end
    end

    Engine.ReleaseAllExcept(active)

    for trackerId in pairs(active) do
        Engine.ClaimForTracker(trackerId)
    end

    -- Groups after trackers: membership reparents claimed visuals.
    if SAU.Groups then SAU.Groups.ApplyAll() end

    if SAU._ApplyStyling then
        for trackerId, tracker in pairs(active) do
            SAU._ApplyStyling(trackerId, tracker)
        end
    end

    if Engine.Record then Engine.Record("activation", tostring(reason)) end
end

--- Re-runs the whole gate. Kept under its old name because the engine, the
-- editor, and the spec handler all call it.
function SAU.RebuildAll(reason)
    SAU.ReconcileActivation(reason or "rebuild")
end
