-- scootauras/importexport.lua - Aura and group strings: export, validate, import
--
-- One tracker, or one group with its members, travels as a "!SA1!" string
-- through the profile codec (core/importexport.lua): a whitelisted record set
-- serialized, compressed, and encoded for print. Import validates every
-- record into fresh tables before it writes anything, then follows the
-- Duplicate write order: content, styling before the component links, the
-- position under the active layout, then activation. The spec rules are
-- Duplicate's too: a standalone kind with no spell and a group take this
-- character's class specs when their lists carry none of them; a spell kind
-- and every group member keep the exported list.
local addonName, addon = ...

local SAU = addon.ScootAuras
local CopyTable = _G.CopyTable

SAU.EXPORT_VERSION = 1

local NAME_MAX = 64

-- The content fields that cross in both directions. order, groupId, and the
-- migration markers stay home: the importer assigns them.
local TRACKER_FIELDS = {
    "kind", "spellId", "unit", "shape", "name", "enabled",
    "onlyInCombat", "onlyInInstances", "missingVisual", "specs", "homeSpec",
}

-- Read at call time: core/importexport.lua loads after this file.
local function Codec() return addon.ImportExport end

local function PlayerClass()
    return addon.GetClassTokenForUnit and addon.GetClassTokenForUnit("player") or nil
end

local function ActiveLayoutName()
    local Engine = SAU.Engine
    return Engine and Engine.GetActiveLayoutName and Engine.GetActiveLayoutName() or nil
end

local function ClassName(token)
    local names = _G.LOCALIZED_CLASS_NAMES_MALE
    return names and names[token] or token
end

--------------------------------------------------------------------------------
-- Export
--------------------------------------------------------------------------------

local function StoredPosition(key)
    local Engine = SAU.Engine
    local layout = ActiveLayoutName()
    if not (Engine and Engine._GetStoredPosition and layout) then return nil end
    local pos = Engine._GetStoredPosition(key, layout)
    if type(pos) ~= "table" then return nil end
    return { point = pos.point, x = pos.x, y = pos.y }
end

-- The record a tracker exports: the whitelisted content, its written styling
-- keys (CopyTable walks pairs, so the defaults metatable never comes along),
-- and, for a standalone tracker, its position under the active layout.
local function BuildTrackerRecord(trackerId, tracker, withPosition)
    local rec = {}
    for _, field in ipairs(TRACKER_FIELDS) do
        local v = tracker[field]
        rec[field] = (type(v) == "table") and CopyTable(v) or v
    end
    local styling = SAU.GetStylingContainer(false)
    local own = styling and styling[SAU.GetComponentId(trackerId)]
    rec.styling = (type(own) == "table") and CopyTable(own) or {}
    if withPosition then
        rec.position = StoredPosition("t" .. trackerId)
    end
    return rec
end

local function Encode(envelope)
    local codec = Codec()
    if not (codec and codec.EncodeEnvelope) then return nil, "Import/export is not available." end
    envelope.version = SAU.EXPORT_VERSION
    return codec:EncodeEnvelope(envelope, codec.PREFIX_AURA)
end

--- One tracker as an import string. Returns string or nil, err.
function SAU.ExportTracker(trackerId)
    local tracker = SAU.GetTracker(trackerId)
    if not tracker then return nil, "no such tracker" end
    return Encode({ kind = "tracker", tracker = BuildTrackerRecord(trackerId, tracker, true) })
end

--- One group with its members as an import string. Members are the
-- memberOrder entries that exist and agree they belong, the ValidateGroupData
-- rule. They carry no position: the group frame anchors them.
function SAU.ExportGroup(gid)
    local group = SAU.GetGroup(gid)
    if not group then return nil, "no such group" end
    local members = {}
    for _, memberId in ipairs(group.memberOrder or {}) do
        local tracker = SAU.GetTracker(memberId)
        if tracker and tracker.groupId == gid then
            table.insert(members, BuildTrackerRecord(memberId, tracker, false))
        end
    end
    return Encode({
        kind = "group",
        group = {
            name = group.name,
            enabled = group.enabled ~= false,
            settings = CopyTable(group.settings or SAU.GROUP_SETTING_DEFAULTS),
            specs = group.specs and CopyTable(group.specs) or nil,
            position = StoredPosition("g" .. gid),
            members = members,
        },
    })
end

--------------------------------------------------------------------------------
-- Validation (no writes)
--------------------------------------------------------------------------------

local function Fail(label, msg)
    if label then return nil, label .. ": " .. msg end
    return nil, msg
end

-- Keys the registered settings know, once per import: a key from a newer or
-- an older Scoot has no reader here and must not land in the store.
local function KnownStylingKeys()
    local known = {}
    for key in pairs(SAU.DefaultSettings()) do known[key] = true end
    return known
end

local SCALAR = { number = true, string = true, boolean = true }

local function FilterStyling(tbl, known)
    local out = {}
    if type(tbl) ~= "table" then return out end
    for key, value in pairs(tbl) do
        if type(key) == "string" and known[key] then
            if SCALAR[type(value)] then
                out[key] = value
            elseif type(value) == "table" then
                out[key] = CopyTable(value)
            end
        end
    end
    return out
end

local function CleanPosition(pos)
    if type(pos) ~= "table" then return nil end
    if type(pos.point) ~= "string" or type(pos.x) ~= "number" or type(pos.y) ~= "number" then
        return nil
    end
    return { point = pos.point, x = pos.x, y = pos.y }
end

-- Stamps this character's class specs on a list that carries none of them,
-- the Duplicate rule. Empty class data leaves the list alone rather than
-- writing one that loads nowhere. Returns the list and whether it changed.
local function RescueSpecs(specs)
    local playerClass = PlayerClass()
    if not playerClass or SAU.SpecsListClass(specs, playerClass) then return specs, false end
    local mine = SAU.DefaultSpecsForPlayer()
    if #mine == 0 then return specs, false end
    return SAU._NormalizeSpecs(mine), true
end

-- A fresh clean tracker record, or nil, err. `exact` keeps the exported spec
-- list on any character (a group member); otherwise a kind with no spell
-- follows the character, as DuplicateTracker does.
local function ValidateTrackerRecord(rec, label, exact, known)
    if type(rec) ~= "table" then return Fail(label, "the aura record is missing") end
    local kind = rec.kind
    if not SAU.VALID_KINDS[kind] then
        return Fail(label, "unknown tracker kind '" .. tostring(kind) .. "'")
    end
    local spellId = SAU.KindNeedsSpell(kind) and tonumber(rec.spellId) or nil
    local unit = rec.unit
    if type(unit) ~= "string" or not SAU.VALID_UNITS[kind][unit] then
        unit = SAU.DefaultUnitForKind(kind)
    end
    local shape = rec.shape
    local shapes = SAU.VALID_SHAPES_BY_KIND[kind]
    if type(shape) ~= "string" or not shapes or not shapes[shape] then
        shape = SAU.DefaultShapeForKind(kind)
    end
    local ok, err = SAU.ValidateContent(spellId, kind, unit, shape)
    if not ok then return Fail(label, err) end

    local clean = { kind = kind, spellId = spellId, unit = unit, shape = shape }

    local name = rec.name
    if type(name) == "string" and name ~= "" then
        clean.name = name:sub(1, NAME_MAX)
    elseif SAU.KindNeedsSpell(kind) then
        clean.name = SAU.AutoName(kind, spellId)
    end

    clean.enabled = rec.enabled ~= false
    if rec.onlyInCombat ~= nil then
        clean.onlyInCombat = rec.onlyInCombat ~= false
    else
        -- A record from before its kind carried the field keeps the reading
        -- it ran on, the SetTrackerContent rule.
        clean.onlyInCombat = SAU.OnlyInCombat(clean)
    end
    if kind == "missingbuff" then
        clean.onlyInInstances = rec.onlyInInstances == true
    end
    local missingValid = SAU.KindSupportsMissingVisual(kind) and SAU.VALID_MISSING_VISUALS_BY_SHAPE[shape]
    if missingValid and type(rec.missingVisual) == "string" and missingValid[rec.missingVisual] then
        clean.missingVisual = rec.missingVisual
    end

    clean.specs = SAU._NormalizeSpecs(rec.specs)
    clean.homeSpec = tonumber(rec.homeSpec) or nil
    if not exact and not SAU.KindNeedsSpell(kind) then
        local specs, rescued = RescueSpecs(clean.specs)
        if rescued then
            clean.specs = specs
            clean.homeSpec = SAU.CurrentSpecID()
        end
    end

    clean.styling = FilterStyling(rec.styling, known)
    clean.position = CleanPosition(rec.position)
    return clean
end

local function ValidateGroupRecord(rec, known)
    if type(rec) ~= "table" then return nil, "the group record is missing" end
    local name = (type(rec.name) == "string" and rec.name ~= "") and rec.name:sub(1, NAME_MAX) or "Aura Group"
    local clean = { name = name, enabled = rec.enabled ~= false, members = {} }

    -- The SetGroupSettings clamps, on the defaults.
    local settings = CopyTable(SAU.GROUP_SETTING_DEFAULTS)
    local src = type(rec.settings) == "table" and rec.settings or {}
    local spacing = tonumber(src.spacing)
    if spacing then settings.spacing = math.max(0, math.min(spacing, 100)) end
    local scale = tonumber(src.scale)
    if scale then settings.scale = math.max(25, math.min(scale, 200)) end
    if type(src.grow) == "string" and SAU.Groups and SAU.Groups.VALID_GROW[src.grow] then
        settings.grow = src.grow
    end
    if src.growTouched == true then settings.growTouched = true end
    clean.settings = settings

    clean.specs = RescueSpecs(SAU._NormalizeSpecs(rec.specs))
    clean.position = CleanPosition(rec.position)

    local members = type(rec.members) == "table" and rec.members or {}
    for index, member in ipairs(members) do
        local memberLabel = "Aura " .. index
        if type(member) == "table" and type(member.name) == "string" and member.name ~= "" then
            memberLabel = "Aura '" .. member.name .. "'"
        end
        local cleanMember, err = ValidateTrackerRecord(member, memberLabel, true, known)
        if not cleanMember then return nil, err end
        table.insert(clean.members, cleanMember)
    end
    return clean
end

-- Trims, routes a profile string to its own importer, decodes, and validates
-- into fresh tables. Nothing here writes. Returns { kind, tracker | group,
-- exportedAt, addonVersion } or nil, err.
local function DecodeAuraString(str)
    local codec = Codec()
    if not (codec and codec.DecodeEnvelope) then return nil, "Import/export is not available." end
    if type(str) ~= "string" then return nil, "No import string provided." end
    str = str:match("^%s*(.-)%s*$") or ""
    if str == "" then return nil, "No import string provided." end
    local profilePrefix = codec.PREFIX_PROFILE
    if profilePrefix and str:sub(1, #profilePrefix) == profilePrefix then
        return nil, "That is a Scoot profile string. Import it under Profiles > Import/Export."
    end
    local ok, envelope = codec:DecodeEnvelope(str, codec.PREFIX_AURA, "aura")
    if not ok then return nil, envelope end
    if envelope.version == nil then
        return nil, "Import data is missing version information."
    end
    if type(envelope.version) ~= "number" or envelope.version > SAU.EXPORT_VERSION then
        return nil, "This aura string was made by a newer version of Scoot. Please update your addon."
    end
    local known = KnownStylingKeys()
    local payload = {
        kind = envelope.kind,
        exportedAt = envelope.exportedAt,
        addonVersion = envelope.addonVersion,
    }
    if envelope.kind == "tracker" then
        local clean, err = ValidateTrackerRecord(envelope.tracker, nil, false, known)
        if not clean then return nil, err end
        payload.tracker = clean
    elseif envelope.kind == "group" then
        local clean, err = ValidateGroupRecord(envelope.group, known)
        if not clean then return nil, err end
        payload.group = clean
    else
        return nil, "Unrecognized aura string."
    end
    return payload
end

--- What a string holds, for a preview line before anything is created. A
-- string this accepts fails ImportString only on the module gate or a store
-- that is not ready. Returns { kind, name, memberCount, class, className,
-- loadsHere, exportedAt, addonVersion } or nil, err.
function SAU.DescribeImportString(str)
    local payload, err = DecodeAuraString(str)
    if not payload then return nil, err end
    local record = payload.tracker or payload.group
    local info = {
        kind = payload.kind,
        exportedAt = payload.exportedAt,
        addonVersion = payload.addonVersion,
        memberCount = payload.group and #payload.group.members or nil,
    }
    if payload.tracker then
        info.name = record.name or SAU.AutoName(record.kind, record.spellId, record.specs, record.homeSpec)
    else
        info.name = record.name
    end
    local specs = record.specs
    info.class = specs and specs[1] and SAU.ClassTokenForSpec(specs[1]) or nil
    info.className = info.class and ClassName(info.class) or nil
    local playerClass = PlayerClass()
    info.loadsHere = (playerClass ~= nil) and SAU.SpecsListClass(specs, playerClass) or false
    return info
end

--------------------------------------------------------------------------------
-- Import
--------------------------------------------------------------------------------

-- The DuplicateTracker write order: content, then styling before the
-- component links (or the copy arrives as defaults), then the position, then
-- register, link, and stamp. No claim here: activation runs once at the end,
-- so a record gated out on this character holds no shell.
local function WriteTrackerRecord(store, clean, groupId)
    local newId = SAU._AllocateId(store)
    store.trackers[newId] = {
        spellId = clean.spellId,
        kind = clean.kind,
        unit = clean.unit,
        shape = clean.shape,
        name = clean.name,
        enabled = clean.enabled,
        order = newId,
        onlyInCombat = clean.onlyInCombat,
        onlyInInstances = clean.onlyInInstances,
        missingVisual = clean.missingVisual,
        specs = clean.specs,
        homeSpec = clean.homeSpec,
        groupId = groupId,
    }
    if next(clean.styling) then
        SAU.GetStylingContainer(true)[SAU.GetComponentId(newId)] = clean.styling
    end
    if clean.position and not groupId then
        local p = clean.position
        SAU.Engine.SavePosition("t" .. newId, ActiveLayoutName(), p.point, p.x, p.y)
    end
    SAU.RegisterTrackerComponent(newId)
    addon:EnsureComponentDB(SAU.GetComponentId(newId))
    SAU.ApplyStartingValuesFor(newId, clean.kind, clean.shape)
    return newId
end

local function WriteGroupRecord(store, clean)
    local newGid = SAU._AllocateId(store)
    local group = {
        name = clean.name,
        enabled = clean.enabled,
        settings = clean.settings,
        memberOrder = {},
        specs = clean.specs,
    }
    store.groups[newGid] = group
    local memberIds = {}
    for _, member in ipairs(clean.members) do
        local id = WriteTrackerRecord(store, member, newGid)
        table.insert(group.memberOrder, id)
        table.insert(memberIds, id)
    end
    if clean.position then
        local p = clean.position
        SAU.Engine.SavePosition("g" .. newGid, ActiveLayoutName(), p.point, p.x, p.y)
    end
    return newGid, memberIds
end

--- Creates the records an aura string holds. Returns { kind, id, memberIds }
-- or nil, err. A bad string writes nothing: every record is validated before
-- the first write. No combat guard: the writes are table writes and Scoot-
-- frame anchors, and structural work queues behind the engine gate.
function SAU.ImportString(str)
    if not SAU.IsModuleActive() then
        return nil, "ScootAuras module is disabled (enable it on the Features page, then reload)"
    end
    local payload, err = DecodeAuraString(str)
    if not payload then return nil, err end
    local store = SAU.EnsureStore()
    if not store then return nil, "profile not ready" end

    local Engine = SAU.Engine
    if payload.tracker then
        local newId = WriteTrackerRecord(store, payload.tracker, nil)
        -- Activation rather than a bare claim: a record gated out on this
        -- character stays released, where a Duplicate would hold a shell.
        SAU.ReconcileActivation("import:t" .. tostring(newId))
        if Engine and Engine.Record then Engine.Record("import", "t" .. newId) end
        return { kind = "tracker", id = newId, memberIds = {} }
    end

    local newGid, memberIds = WriteGroupRecord(store, payload.group)
    SAU.ValidateGroupData()
    SAU.Groups.ApplyMembership()
    SAU.Groups.RequestReflow()
    if Engine and Engine.Record then Engine.Record("import", "g" .. newGid) end
    return { kind = "group", id = newGid, memberIds = memberIds }
end
