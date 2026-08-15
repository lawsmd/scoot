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
    store.learnedDurations = store.learnedDurations or {}
    return store
end

--- Learned original durations for the cadence lock, per spell ID (seconds).
-- Content path: written by cadence.lua when an aura's duration is readable.
function SAU.GetLearnedDuration(spellId)
    local store = SAU.GetStore()
    local map = store and rawget(store, "learnedDurations")
    local seconds = map and spellId and map[spellId] or nil
    if type(seconds) == "number" and seconds > 0 then
        return seconds
    end
    return nil
end

function SAU.SetLearnedDuration(spellId, seconds)
    if type(spellId) ~= "number" or type(seconds) ~= "number" or seconds <= 0 then return end
    local store = SAU.EnsureStore()
    if not store then return end
    local rounded = math.floor(seconds * 100 + 0.5) / 100
    if store.learnedDurations[spellId] == rounded then return end
    store.learnedDurations[spellId] = rounded
    if SAU.Cadence then
        SAU.Cadence.OnLearned(spellId)
    end
end

function SAU.GetTracker(trackerId)
    local store = SAU.GetStore()
    return store and store.trackers and store.trackers[trackerId] or nil
end

--- Returns a sorted array of { id, tracker } for stable iteration.
function SAU.SortedTrackers()
    local out = {}
    local store = SAU.GetStore()
    if store and store.trackers then
        for id, tracker in pairs(store.trackers) do
            table.insert(out, { id = id, tracker = tracker })
        end
        table.sort(out, function(a, b)
            local ao = a.tracker.order or a.id
            local bo = b.tracker.order or b.id
            if ao ~= bo then return ao < bo end
            return a.id < b.id
        end)
    end
    return out
end

function SAU.GetGroup(gid)
    local store = SAU.GetStore()
    return store and store.groups and store.groups[gid] or nil
end

--- Returns a sorted array of { id, group } for stable iteration.
function SAU.SortedGroups()
    local out = {}
    local store = SAU.GetStore()
    if store and store.groups then
        for gid, group in pairs(store.groups) do
            table.insert(out, { id = gid, group = group })
        end
        table.sort(out, function(a, b) return a.id < b.id end)
    end
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
-- Content validation
--------------------------------------------------------------------------------

SAU.VALID_KINDS = { buff = true, debuff = true }
SAU.VALID_SHAPES = { icon = true, bar = true, shape = true }

-- The friendly-debuff wall: debuff information on friendly units is not
-- acquirable, so Debuff offers hostile-capable units only.
SAU.VALID_UNITS = {
    buff   = { player = true, target = true, focus = true },
    debuff = { target = true, focus = true },
}

function SAU.ValidateContent(spellId, kind, unit, shape)
    if type(spellId) ~= "number" or spellId <= 0 then return nil, "invalid spell ID" end
    if not SAU.VALID_KINDS[kind] then return nil, "kind must be buff or debuff" end
    local units = SAU.VALID_UNITS[kind]
    if not units[unit] then return nil, kind .. " cannot target unit '" .. tostring(unit) .. "'" end
    if not SAU.VALID_SHAPES[shape] then return nil, "shape must be icon, bar, or shape" end
    return true
end

-- Own-cast filtering: a debuff tracker watches the player's own aura on the
-- enemy; buffs accept any source (external buffs on the player are the point).
function SAU.FilterForKind(kind)
    return (kind == "debuff") and "HARMFUL|PLAYER" or "HELPFUL"
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
        -- Cadence lock (cadence.lua): drain speed pinned to the aura's original
        -- duration; barLockDuration 0 = use the learned per-spell value.
        barLockCadence          = { type = "addon", default = false },
        barLockDuration         = { type = "addon", default = 0 },
        shapeStyle      = { type = "addon", default = "border:SquareMask" },
        shapeColorMode  = { type = "addon", default = "class" },
        shapeTint       = { type = "addon", default = { 1, 1, 1, 1 } },
        shapeShowDrain  = { type = "addon", default = true },
        opacityInCombat         = { type = "addon", default = 100 },
        opacityWithTarget       = { type = "addon", default = 100 },
        opacityOutOfCombat      = { type = "addon", default = 100 },
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

function SAU.ApplyBarStartingValues(trackerId)
    local db = addon:EnsureComponentDB(SAU.GetComponentId(trackerId))
    if not db then return end
    for key, value in pairs(SAU.BarShapeStartingValues) do
        if rawget(db, key) == nil then
            db[key] = (type(value) == "table") and CopyTable(value) or value
        end
    end
end

function SAU.RemoveBarStartingValues(trackerId)
    local db = addon:EnsureComponentDB(SAU.GetComponentId(trackerId))
    if not db then return end
    for key, value in pairs(SAU.BarShapeStartingValues) do
        if StampEqual(rawget(db, key), value) then
            db[key] = nil
        end
    end
end

--------------------------------------------------------------------------------
-- Component registration
--------------------------------------------------------------------------------

local function PlainSpellName(spellId)
    local ok, name = pcall(C_Spell.GetSpellName, spellId)
    if ok and type(name) == "string" and not issecretvalue(name) and name ~= "" then
        return name
    end
    return "Aura " .. tostring(spellId)
end

SAU._PlainSpellName = PlainSpellName

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
    local store = SAU.GetStore()
    if not store or not store.trackers then return end
    for trackerId in pairs(store.trackers) do
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
    local unit = spec and spec.unit or ((kind == "debuff") and "target" or "player")
    local shape = spec and spec.shape or "icon"
    local ok, err = SAU.ValidateContent(spellId, kind, unit, shape)
    if not ok then return nil, err end

    local store = SAU.EnsureStore()
    if not store then return nil, "profile not ready" end

    local trackerId = store.nextId
    store.nextId = trackerId + 1
    store.trackers[trackerId] = {
        spellId = spellId,
        kind = kind,
        unit = unit,
        shape = shape,
        name = spec.name or PlainSpellName(spellId),
        enabled = true,
        order = trackerId,
    }

    SAU.RegisterTrackerComponent(trackerId)
    addon:EnsureComponentDB(SAU.GetComponentId(trackerId))
    if shape == "bar" then
        SAU.ApplyBarStartingValues(trackerId)
    end
    SAU.Engine.ClaimForTracker(trackerId)
    return trackerId
end

--- Deletes a tracker: parks its container, hides its frames, and clears every
-- persisted trace. The pruner never reclaims unregistered components' data, so
-- the cleanup here is explicit.
function SAU.DeleteTracker(trackerId)
    local store = SAU.GetStore()
    local tracker = store and store.trackers and store.trackers[trackerId]
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

--- Applies content edits (spellId/kind/unit/shape) to a live tracker and
-- routes the engine consequence: shape edits rebind, spell/unit/kind edits
-- park the mismatched container immediately and rebuild through the gate.
function SAU.SetTrackerContent(trackerId, changes)
    local tracker = SAU.GetTracker(trackerId)
    if not tracker then return nil, "no such tracker" end
    local spellId = tonumber(changes.spellId) or tracker.spellId
    local kind = changes.kind or tracker.kind
    local unit = changes.unit or tracker.unit
    local shape = changes.shape or tracker.shape
    -- A kind flip can strand the current unit (debuff+player); fall to the
    -- kind's default rather than rejecting the edit.
    if not SAU.VALID_UNITS[kind] or not SAU.VALID_UNITS[kind][unit] then
        unit = (kind == "debuff") and "target" or "player"
    end
    local ok, err = SAU.ValidateContent(spellId, kind, unit, shape)
    if not ok then return nil, err end

    local oldSpellId = tracker.spellId
    local oldShape = tracker.shape
    tracker.spellId = spellId
    tracker.kind = kind
    tracker.unit = unit
    tracker.shape = shape
    if type(changes.name) == "string" and changes.name ~= "" then
        tracker.name = changes.name
    elseif spellId ~= oldSpellId and tracker.name == PlainSpellName(oldSpellId) then
        -- The name was the auto name; follow the new spell. Custom names stay.
        tracker.name = PlainSpellName(spellId)
    end

    if shape == "bar" and oldShape ~= "bar" then
        SAU.ApplyBarStartingValues(trackerId)
    elseif oldShape == "bar" and shape ~= "bar" then
        SAU.RemoveBarStartingValues(trackerId)
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

    local newId = store.nextId
    store.nextId = newId + 1
    store.trackers[newId] = {
        spellId = source.spellId,
        kind = source.kind,
        unit = source.unit,
        shape = source.shape,
        name = (source.name or PlainSpellName(source.spellId)) .. " copy",
        enabled = source.enabled ~= false,
        order = newId,
    }

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
    SAU.Engine.ClaimForTracker(newId)
    return newId
end

function SAU.SetTrackerEnabled(trackerId, enabled)
    local tracker = SAU.GetTracker(trackerId)
    if not tracker then return nil, "no such tracker" end
    tracker.enabled = not not enabled
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

    local gid = store.nextId
    store.nextId = gid + 1
    store.groups[gid] = {
        name = (type(name) == "string" and name ~= "") and name or ("Aura Group " .. gid),
        settings = CopyTable(SAU.GROUP_SETTING_DEFAULTS),
        memberOrder = {},
    }
    SAU.Groups.ClaimForGroup(gid)
    SAU.Groups.LayoutGroup(gid)
    return gid
end

--- Deletes a group. Its members are kept: each returns to standalone form at
-- the screen spot where it currently renders.
function SAU.DeleteGroup(gid)
    local store = SAU.GetStore()
    local group = store and store.groups and store.groups[gid]
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
    if gid ~= nil and not (store and store.groups and store.groups[gid]) then
        return nil, "no such group"
    end

    local oldGid = tracker.groupId
    if oldGid then
        local oldGroup = store.groups and store.groups[oldGid]
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
        local group = store.groups[gid]
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

    local newGid = store.nextId
    store.nextId = newGid + 1
    local newGroup = {
        name = (source.name or ("Aura Group " .. gid)) .. " copy",
        settings = CopyTable(source.settings or SAU.GROUP_SETTING_DEFAULTS),
        memberOrder = {},
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

    for _, tracker in pairs(trackers) do
        if tracker.groupId ~= nil and not groups[tracker.groupId] then
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

    SAU.ValidateGroupData()
    local store = SAU.GetStore()
    local trackers = (SAU.IsModuleActive() and store and store.trackers) or {}

    -- Park pool occupants absent from (or stale in) the new profile.
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
    local store = SAU.GetStore()
    if not store or not store.trackers then return end
    for trackerId, tracker in pairs(store.trackers) do
        if SAU._ApplyStyling then SAU._ApplyStyling(trackerId, tracker) end
    end
end
