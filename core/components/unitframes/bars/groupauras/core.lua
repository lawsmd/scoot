--------------------------------------------------------------------------------
-- groupauras/core.lua
-- Aura Tracking on group frames (party + raid)
--
-- Renders custom Scoot-styled icons for tracked auras. Spell registry,
-- event handling, active-set management, rainbow color engine, graceful
-- degradation. Hiding Blizzard's own buff icons is handled by the
-- raidFramesDisplayBuffs CVar (see ApplyGroupBuffIconsHiddenForActiveProfile
-- in core/profiles/core.lua), not by anything in this component.
--------------------------------------------------------------------------------

local addonName, addon = ...

addon.AuraTracking = addon.AuraTracking or {}
local HA = addon.AuraTracking

local IsAuraFilteredOutByInstanceID = C_UnitAuras and C_UnitAuras.IsAuraFilteredOutByInstanceID

--------------------------------------------------------------------------------
-- Spell Registry
--------------------------------------------------------------------------------
-- Each class maps to an array of { id = spellId, name = "Spell Name" }.
-- Organized by class token for the settings UI class selector.
--------------------------------------------------------------------------------

HA.SPELL_REGISTRY = {
    EVOKER = {
        -- Preservation
        { id = 355941, name = "Dream Breath",        textureId = 5765862 },
        { id = 363502, name = "Dream Flight",        textureId = 5765860 },
        { id = 364343, name = "Echo",                 textureId = 5765863 },
        { id = 366155, name = "Reversion",            textureId = 5765865 },
        { id = 367364, name = "Echo (Reversion)",     textureId = 5765863 },
        { id = 373267, name = "Lifebind",             textureId = 5765864 },
        { id = 376788, name = "Echo (Dream Breath)",  textureId = 5765863 },
        -- Augmentation
        { id = 360827, name = "Blistering Scales",    textureId = 5199623, stackable = true },
        { id = 395152, name = "Ebon Might",           textureId = 5199630 },
        { id = 410089, name = "Prescience",           textureId = 5199640 },
        { id = 410263, name = "Inferno's Blessing",   textureId = 5199634 },
        { id = 410686, name = "Symbiotic Bloom",      textureId = 5199645 },
        { id = 413984, name = "Shifting Sands",       textureId = 5199644 },
    },
    DRUID = {
        { id = 774,    name = "Rejuvenation",   textureId = 136081 },
        { id = 8936,   name = "Regrowth",        textureId = 136085 },
        { id = 33763,  name = "Lifebloom",        textureId = 134206, stackable = true },
        { id = 48438,  name = "Wild Growth",      textureId = 236153 },
        { id = 155777, name = "Germination",      textureId = 136081 },
    },
    PRIEST = {
        -- Discipline
        { id = 17,      name = "Power Word: Shield",    textureId = 135940 },
        { id = 194384,  name = "Atonement",              textureId = 458722 },
        { id = 1253593, name = "Void Shield",            textureId = 135940 },
        -- Holy
        { id = 139,     name = "Renew",                  textureId = 135953 },
        { id = 41635,   name = "Prayer of Mending",      textureId = 135944, stackable = true },
        { id = 77489,   name = "Echo of Light",           textureId = 237541 },
    },
    MONK = {
        { id = 115175, name = "Soothing Mist",    textureId = 606550 },
        { id = 119611, name = "Renewing Mist",    textureId = 627487 },
        { id = 124682, name = "Enveloping Mist",  textureId = 775461 },
        { id = 450769, name = "Aspect of Harmony", textureId = 5765856, stackable = true },
    },
    SHAMAN = {
        { id = 974,    name = "Earth Shield",          textureId = 136089, stackable = true },
        { id = 383648, name = "Earth Shield (Talent)",  textureId = 136089, stackable = true },
        { id = 61295,  name = "Riptide",               textureId = 252995 },
    },
    PALADIN = {
        { id = 53563,   name = "Beacon of Light",      textureId = 236247 },
        { id = 156322,  name = "Eternal Flame",        textureId = 135972 },
        { id = 156910,  name = "Beacon of Faith",       textureId = 236247 },
        { id = 1244893, name = "Beacon of the Savior",  textureId = 236247 },
    },
}

-- Alphabetical class order for selector
HA.CLASS_ORDER = { "DRUID", "EVOKER", "MONK", "PALADIN", "PRIEST", "SHAMAN" }

-- Display names for the class selector
HA.CLASS_LABELS = {
    DRUID   = "Druid",
    EVOKER  = "Evoker",
    MONK    = "Monk",
    PALADIN = "Paladin",
    PRIEST  = "Priest",
    SHAMAN  = "Shaman",
}

-- Reverse lookup: spellId → classToken (includes linkedIds)
HA.SPELL_TO_CLASS = {}
for classToken, spells in pairs(HA.SPELL_REGISTRY) do
    for _, entry in ipairs(spells) do
        HA.SPELL_TO_CLASS[entry.id] = classToken
        if entry.linkedIds then
            for _, linkedId in ipairs(entry.linkedIds) do
                HA.SPELL_TO_CLASS[linkedId] = classToken
            end
        end
    end
end
table.freeze(HA.SPELL_TO_CLASS)

-- Reverse lookup: spellId → true when the aura is known to stack (i.e. its
-- applications count can exceed 1). Drives conditional visibility of the
-- "Stacks Text" settings tab per-spell. `applications` is a runtime-only
-- observation with no static API to query, so this table is maintained as a
-- manually-curated flag on HA.SPELL_REGISTRY entries.
HA.STACKABLE_SPELLS = {}
for _, spells in pairs(HA.SPELL_REGISTRY) do
    for _, entry in ipairs(spells) do
        if entry.stackable then
            HA.STACKABLE_SPELLS[entry.id] = true
            if entry.linkedIds then
                for _, linkedId in ipairs(entry.linkedIds) do
                    HA.STACKABLE_SPELLS[linkedId] = true
                end
            end
        end
    end
end
table.freeze(HA.STACKABLE_SPELLS)

-- spellId → display name (includes linkedIds → parent name)
HA.SPELL_NAMES = {}
for _, spells in pairs(HA.SPELL_REGISTRY) do
    for _, entry in ipairs(spells) do
        HA.SPELL_NAMES[entry.id] = entry.name
        if entry.linkedIds then
            for _, linkedId in ipairs(entry.linkedIds) do
                HA.SPELL_NAMES[linkedId] = entry.name
            end
        end
    end
end
table.freeze(HA.SPELL_NAMES)

-- linkedId → primary entry id (so linked variants share config with their parent)
HA.LINKED_TO_PRIMARY = {}
for _, spells in pairs(HA.SPELL_REGISTRY) do
    for _, entry in ipairs(spells) do
        if entry.linkedIds then
            for _, linkedId in ipairs(entry.linkedIds) do
                HA.LINKED_TO_PRIMARY[linkedId] = entry.id
            end
        end
    end
end
table.freeze(HA.LINKED_TO_PRIMARY)

-- spellId → registry entry (for textureId lookup; includes linkedIds → parent entry)
HA.SPELL_REGISTRY_BY_ID = {}
for _, spells in pairs(HA.SPELL_REGISTRY) do
    for _, entry in ipairs(spells) do
        HA.SPELL_REGISTRY_BY_ID[entry.id] = entry
        if entry.linkedIds then
            for _, linkedId in ipairs(entry.linkedIds) do
                HA.SPELL_REGISTRY_BY_ID[linkedId] = entry
            end
        end
    end
end
table.freeze(HA.SPELL_REGISTRY_BY_ID)

--------------------------------------------------------------------------------
-- Per-Spell Default Settings
--------------------------------------------------------------------------------

HA.SPELL_DEFAULTS = {
    enabled = false,
    trackAllSources = false,
    iconStyle = "spell",
    iconColor = "original",
    iconCustomColor = { 1, 1, 1, 1 },
    iconScale = 100,
    showDuration = true,
    anchor = "BOTTOMRIGHT",     -- first-time default; auto-slot assigns rank at enable
    offsetX = 0,                -- per-icon fine-tune, added on top of auto-placement
    offsetY = 0,
    -- rank intentionally nil: only meaningful for enabled auras, written by AutoSlotAtEnd
    -- stacksText intentionally nil in defaults: use HA.STACKS_TEXT_DEFAULTS via
    --   rawget + fallback (shared subtable would get mutated across spells otherwise)
}

-- Defaults for the per-spell `stacksText` sub-table. Only used when the spell is
-- stackable (`HA.STACKABLE_SPELLS[spellId]`). Readers must use
-- `rawget(cfg, "stacksText")` + this fallback pattern rather than relying on
-- metatable __index, because the nested `customColor` subtable would otherwise
-- be shared by reference across every spell.
HA.STACKS_TEXT_DEFAULTS = {
    fontFace    = "FRIZQT__",
    size        = 12,
    style       = "OUTLINE",
    colorMode   = "default",        -- "default" (white) | "custom"
    customColor = { 1, 1, 1, 1 },   -- only used when colorMode == "custom"
    anchor      = "BOTTOMRIGHT",    -- 9-way inside-icon anchor
    offsetX     = 0,                -- px offset from the anchor
    offsetY     = 0,
}

-- Global defaults (flat keys on auraTracking DB table). Applied on first read via
-- the DB getters in icons.lua so they don't require eager writes.
HA.GLOBAL_DEFAULTS = {
    positionGroupSpacingDefault = 2,    -- px gap fallback when an anchor key is missing
}
table.freeze(HA.GLOBAL_DEFAULTS)

HA.MAX_RANK = 6  -- cap aligned with Blizzard's max-buffs per CompactUnitFrame

--------------------------------------------------------------------------------
-- Rank Ordering Helpers (ordered-list model)
--------------------------------------------------------------------------------
-- Ranks within an anchor are always contiguous 1..N — no gaps. Operations
-- preserve that invariant. Disabled auras may have stale rank values in DB;
-- they're ignored because re-enable re-computes via AutoSlotAtEnd.
--------------------------------------------------------------------------------

local function GetSpellsTable()
    local db = addon.db and addon.db.profile
    local at = db and db.groupFrames and db.groupFrames.auraTracking
    return at and at.spells or nil
end

-- Resolve the class (token) that owns a given spellId. Linked spell IDs
-- inherit their parent's class via HA.SPELL_TO_CLASS.
local function ClassOf(spellId)
    return HA.SPELL_TO_CLASS and HA.SPELL_TO_CLASS[spellId] or nil
end

-- Returns array of { spellId, config } for enabled auras in `anchor`, sorted by
-- their current rank (ties broken by spellId). Excludes `excludeSpellId`.
-- When `classFilter` is a class token, only auras registered to that class are
-- returned. Priorities are scoped to (anchor, class) so e.g. a Druid's
-- BOTTOMRIGHT list is independent of a Shaman's BOTTOMRIGHT list, even though
-- both live in the same DB table and share the same anchor value.
function HA.EnabledInAnchor(anchor, excludeSpellId, classFilter)
    local out = {}
    local spells = GetSpellsTable()
    if not spells then return out end
    for spellId, cfg in pairs(spells) do
        if spellId ~= excludeSpellId
           and type(cfg) == "table"
           and cfg.enabled
           and (cfg.anchor or HA.SPELL_DEFAULTS.anchor) == anchor then
            if (not classFilter) or ClassOf(spellId) == classFilter then
                table.insert(out, { spellId = spellId, config = cfg })
            end
        end
    end
    table.sort(out, function(a, b)
        local ra = tonumber(a.config.rank) or 0
        local rb = tonumber(b.config.rank) or 0
        if ra ~= rb then return ra < rb end
        return a.spellId < b.spellId
    end)
    return out
end

function HA.CountEnabledInAnchor(anchor, excludeSpellId, classFilter)
    return #HA.EnabledInAnchor(anchor, excludeSpellId, classFilter)
end

-- Re-index every enabled aura in (anchor, class) so ranks are exactly 1..N
-- contiguous. Called after disable / anchor-change (old-side) to close gaps.
-- When `classFilter` is nil, re-indexes EVERY class's list in the anchor
-- independently (each class keeps its own 1..N sequence).
function HA.ReindexAnchor(anchor, classFilter)
    if classFilter then
        local list = HA.EnabledInAnchor(anchor, nil, classFilter)
        for i, entry in ipairs(list) do
            entry.config.rank = i
        end
        return
    end
    -- No class filter: re-index each class bucket separately so cross-class
    -- priorities don't clobber each other.
    local byClass = {}
    local all = HA.EnabledInAnchor(anchor, nil, nil)
    for _, entry in ipairs(all) do
        local cls = ClassOf(entry.spellId) or "__unknown__"
        byClass[cls] = byClass[cls] or {}
        table.insert(byClass[cls], entry)
    end
    for _, list in pairs(byClass) do
        for i, entry in ipairs(list) do
            entry.config.rank = i
        end
    end
end

-- Assign `spellId` to the end of its class's list in `anchor`. Writes
-- cfg.anchor and cfg.rank. Existing anchor/rank are NOT cleaned up here —
-- callers handle that (disable path / anchor-change path both call
-- ReindexAnchor on the old anchor + class).
function HA.AutoSlotAtEnd(spellId, anchor)
    local spells = GetSpellsTable()
    if not spells or not spells[spellId] then return end
    local cfg = spells[spellId]
    local cls = ClassOf(spellId)
    local others = HA.CountEnabledInAnchor(anchor, spellId, cls)
    local newRank = others + 1
    if newRank > HA.MAX_RANK then newRank = HA.MAX_RANK end  -- overflow: stack on rank MAX
    cfg.anchor = anchor
    cfg.rank = newRank
end

-- Reorder aura `spellId` to position `newRank` within its class's list in
-- `anchor`. Pushes other same-class auras as needed to keep ranks contiguous.
-- Cross-class auras in the same anchor are untouched (their own 1..N list is
-- independent).
function HA.ReorderRank(anchor, spellId, newRank)
    local spells = GetSpellsTable()
    if not spells or not spells[spellId] then return end
    local cfg = spells[spellId]
    if not cfg.enabled then return end
    if (cfg.anchor or HA.SPELL_DEFAULTS.anchor) ~= anchor then return end

    local cls = ClassOf(spellId)
    local list = HA.EnabledInAnchor(anchor, nil, cls)  -- INCLUDES spellId
    local N = #list
    if N == 0 then return end

    -- Find current position
    local curIdx
    for i, entry in ipairs(list) do
        if entry.spellId == spellId then curIdx = i; break end
    end
    if not curIdx then return end

    -- Clamp target rank
    if newRank < 1 then newRank = 1 end
    if newRank > N then newRank = N end
    if newRank == curIdx then return end

    -- Extract and reinsert
    local moved = table.remove(list, curIdx)
    table.insert(list, newRank, moved)

    -- Re-index the (anchor, class) list
    for i, entry in ipairs(list) do
        entry.config.rank = i
    end
end

--------------------------------------------------------------------------------
-- Active Tracked Set
--------------------------------------------------------------------------------
-- Rebuilt when user changes config. Only enabled spells are in this set.
--------------------------------------------------------------------------------

HA.ACTIVE_TRACKED_IDS = {}

function HA.RebuildActiveTrackedSet()
    wipe(HA.ACTIVE_TRACKED_IDS)
    local db = addon.db and addon.db.profile
    local gf = db and db.groupFrames
    local ha = gf and gf.auraTracking
    local spells = ha and ha.spells
    if not spells then return end
    for spellId, config in pairs(spells) do
        -- Only track spells that exist in the registry (ignore stale DB entries)
        if config.enabled and HA.SPELL_REGISTRY_BY_ID[spellId] then
            local trackMode = config.trackAllSources and "all" or "player"
            HA.ACTIVE_TRACKED_IDS[spellId] = trackMode
            -- Also add all linked variants (e.g., Blessing of the Bronze per-class IDs)
            for _, classSpells in pairs(HA.SPELL_REGISTRY) do
                for _, entry in ipairs(classSpells) do
                    if entry.id == spellId and entry.linkedIds then
                        for _, linkedId in ipairs(entry.linkedIds) do
                            HA.ACTIVE_TRACKED_IDS[linkedId] = trackMode
                        end
                    end
                end
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Weak-keyed State Table (taint prevention)
--------------------------------------------------------------------------------
-- Stores all Scoot state per CompactUnitFrame externally.
-- Never write properties directly to Blizzard frames.
--------------------------------------------------------------------------------

local AuraTrackingState = setmetatable({}, { __mode = "k" })

local function getState(frame)
    if not frame then return nil end
    return AuraTrackingState[frame]
end

local function ensureState(frame)
    if not frame then return nil end
    if not AuraTrackingState[frame] then
        AuraTrackingState[frame] = {
            unit = nil,
            iconFrames = {},
        }
    end
    return AuraTrackingState[frame]
end

-- Export for icons.lua
HA._getState = getState
HA._ensureState = ensureState

--------------------------------------------------------------------------------
-- Group Unit Token Set
--------------------------------------------------------------------------------

local GROUP_UNITS = {}

local function RebuildGroupUnits()
    wipe(GROUP_UNITS)
    GROUP_UNITS["player"] = true
    if IsInRaid() then
        for i = 1, 40 do
            GROUP_UNITS["raid" .. i] = true
        end
    else
        for i = 1, 4 do
            GROUP_UNITS["party" .. i] = true
        end
    end
end

--------------------------------------------------------------------------------
-- HSV to RGB Conversion (for rainbow engine)
--------------------------------------------------------------------------------

function HA.HSVtoRGB(h, s, v)
    if s == 0 then return v, v, v end
    local i = math.floor(h * 6)
    local f = h * 6 - i
    local p = v * (1 - s)
    local q = v * (1 - s * f)
    local t = v * (1 - s * (1 - f))
    i = i % 6
    if i == 0 then return v, t, p
    elseif i == 1 then return q, v, p
    elseif i == 2 then return p, v, t
    elseif i == 3 then return p, q, v
    elseif i == 4 then return t, p, v
    else return v, p, q
    end
end

--------------------------------------------------------------------------------
-- Rainbow Color Engine
--------------------------------------------------------------------------------
-- Shared OnUpdate frame, self-disabling when no rainbow icons are active.
-- All icons in rainbow mode share the same hue phase for visual coherence.
--------------------------------------------------------------------------------

HA._rainbowIcons = {}
local rainbowIcons = HA._rainbowIcons
local RAINBOW_CYCLE_PERIOD = 3.0
local rainbowHue = 0

local rainbowFrame = CreateFrame("Frame")
rainbowFrame:SetScript("OnUpdate", function(self, elapsed)
    if not next(rainbowIcons) then
        self:Hide()
        return
    end
    rainbowHue = (rainbowHue + elapsed / RAINBOW_CYCLE_PERIOD) % 1
    local r, g, b = HA.HSVtoRGB(rainbowHue, 0.75, 1)
    for tex in pairs(rainbowIcons) do
        if tex:IsVisible() then
            tex:SetVertexColor(r, g, b, 1)
        end
    end
end)
rainbowFrame:Hide()

function HA.RegisterRainbowIcon(texture)
    rainbowIcons[texture] = true
    rainbowFrame:Show()
end

function HA.UnregisterRainbowIcon(texture)
    rainbowIcons[texture] = nil
end

--------------------------------------------------------------------------------
-- Graceful Degradation
--------------------------------------------------------------------------------

HA._featureAvailable = nil

function HA.IsFeatureAvailable()
    if HA._featureAvailable ~= nil then
        return HA._featureAvailable
    end
    -- Test a canary spell to see if aura data is readable
    local ok, info = pcall(function()
        return C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(774) -- Rejuvenation
    end)
    if not ok or not info then
        HA._featureAvailable = false
        return false
    end
    -- Check if spellID is a secret value
    if issecretvalue and pcall(issecretvalue, info.spellID) then
        local isSecret = issecretvalue(info.spellID)
        if isSecret then
            HA._featureAvailable = false
            return false
        end
    end
    HA._featureAvailable = true
    return true
end

--------------------------------------------------------------------------------
-- Frame-to-Unit Mapping
--------------------------------------------------------------------------------
-- Hooks CompactUnitFrame_SetUnit to cache which unit token each frame has.
-- This avoids reading frame.unit directly (which could be tainted).
--------------------------------------------------------------------------------

local function IsEditModeOpen()
    -- Primary: Scoot's EventRegistry-driven flag.
    if addon.EditMode and addon.EditMode.IsEditModeActiveOrOpening
       and addon.EditMode.IsEditModeActiveOrOpening() then
        return true
    end
    -- Fallback: ask Blizzard directly. Covers cases where EventRegistry
    -- callbacks lag or don't fire (observed under 12.0.5).
    local mgr = _G.EditModeManagerFrame
    if mgr then
        local ok, shown = pcall(mgr.IsShown, mgr)
        if ok and shown == true then return true end
    end
    return false
end

local frameToUnitHookInstalled = false

local function InstallFrameToUnitHook()
    if frameToUnitHookInstalled then return end
    if not CompactUnitFrame_SetUnit then return end

    hooksecurefunc("CompactUnitFrame_SetUnit", function(frame, unit)
        if not frame then return end
        -- Skip during Edit Mode to avoid taint propagation
        if IsEditModeOpen() then return end
        local state = ensureState(frame)
        state.unit = unit
        -- Cache frame height while we have a safe reference (OOC context)
        if not InCombatLockdown() then
            local ok, h = pcall(frame.GetHeight, frame)
            if ok and type(h) == "number" and h > 0 then
                state.cachedHeight = h
            end
        end
        if unit and GROUP_UNITS[unit] then
            local visOk, vis = pcall(frame.IsVisible, frame)
            if visOk and vis then
                HA.UpdateAurasForFrame(frame, unit)
            else
                HA.HideAllAurasForFrame(frame)
            end
        else
            HA.HideAllAurasForFrame(frame)
        end
    end)

    frameToUnitHookInstalled = true
end

--------------------------------------------------------------------------------
-- Aura Scanning
--------------------------------------------------------------------------------

local function ScanAurasForUnit(unit)
    local found = {}
    if not unit or not AuraUtil or not AuraUtil.ForEachAura then return found, false end

    local ok = pcall(function()
        AuraUtil.ForEachAura(unit, "HELPFUL", nil, function(aura)
            -- Secret checks first: truthiness on a secret entry/field throws
            -- (contained by the outer pcall, but it would abort the whole scan)
            if issecretvalue(aura) or type(aura) ~= "table" then return end
            local spellId = aura.spellId
            -- Skip secret spellIds individually (don't abort the whole scan)
            if issecretvalue(spellId) or not spellId then return end
            local trackMode = HA.ACTIVE_TRACKED_IDS[spellId]
            if trackMode then
                -- Source filtering: only show auras cast by the local player unless
                -- the spell is configured for "all sources" mode.
                if trackMode == "player" then
                    local src = aura.sourceUnit
                    local isMine = nil
                    if src and not (issecretvalue and issecretvalue(src)) then
                        isMine = (src == "player" or src == "pet")
                    end
                    if isMine == nil and IsAuraFilteredOutByInstanceID then
                        local iid = aura.auraInstanceID
                        if iid and not (issecretvalue and issecretvalue(iid)) then
                            local ok2, filtered = pcall(IsAuraFilteredOutByInstanceID, unit, iid, "HELPFUL|PLAYER")
                            if ok2 then isMine = not filtered end
                        end
                    end
                    if isMine == false then return end
                end

                -- Sanitize every stored field: consumers (icons.lua) boolean-test
                -- these outside any pcall, so the produced table must be plain-only
                local icon = aura.icon
                if issecretvalue(icon) then icon = nil end
                local duration = aura.duration
                if issecretvalue(duration) then duration = nil end
                local expirationTime = aura.expirationTime
                if issecretvalue(expirationTime) then expirationTime = nil end
                local applications = aura.applications
                if issecretvalue(applications) then applications = nil end
                local auraInstanceID = aura.auraInstanceID
                if issecretvalue(auraInstanceID) then auraInstanceID = nil end

                found[spellId] = {
                    spellId = spellId,
                    icon = icon,
                    duration = duration or 0,
                    expirationTime = expirationTime or 0,
                    applications = applications or 0,
                    auraInstanceID = auraInstanceID,
                }
            end
        end, true) -- usePackedAura = true
    end)

    return found, ok
end

function HA.UpdateAurasForFrame(frame, unit)
    if not frame or not unit then return end
    -- Don't show icons on hidden frames — they're UIParent-parented and would float visibly
    local okVis, visible = pcall(frame.IsVisible, frame)
    if not okVis or not visible then
        HA.HideAllAurasForFrame(frame)
        return
    end
    if not next(HA.ACTIVE_TRACKED_IDS) then
        HA.HideAllAurasForFrame(frame)
        return
    end

    -- Skip during Edit Mode
    if IsEditModeOpen() then return end

    local state = ensureState(frame)
    local currentAuras, scanOk = ScanAurasForUnit(unit)

    -- 12.1: when aura data is secret in combat the scan aborts and reports
    -- nothing. Releasing icons on that empty result would strip every tracked
    -- icon at the pull. Freeze the current icon set instead; swipes keep
    -- draining from their DurationObjects, and the regen refresh re-syncs.
    if scanOk then
        -- Hide icons for auras no longer present
        for spellId, iconFrame in pairs(state.iconFrames) do
            if not currentAuras[spellId] then
                if HA.ReleaseIcon then
                    HA.ReleaseIcon(iconFrame)
                end
                state.iconFrames[spellId] = nil
            end
        end

        -- Show/update icons for present auras
        for spellId, auraData in pairs(currentAuras) do
            local iconFrame = state.iconFrames[spellId]
            if not iconFrame and HA.AcquireIcon then
                iconFrame = HA.AcquireIcon(frame)
                state.iconFrames[spellId] = iconFrame
            end
            if iconFrame and HA.StyleIcon then
                HA.StyleIcon(iconFrame, spellId, auraData, frame, unit)
            end
        end

        -- Single-pass layout for the whole frame: groups icons by anchor, sorts by
        -- rank, offsets cumulatively. Individual StyleIcon calls above also trigger
        -- reflow via HA.PositionIcon, but running once more here catches any ordering
        -- where a later-added icon needs to push earlier siblings.
        if HA.ReflowIconsForFrame then
            HA.ReflowIconsForFrame(frame)
        end
    end
end

function HA.HideAllAurasForFrame(frame)
    if not frame then return end
    local state = getState(frame)
    if not state then return end
    for spellId, iconFrame in pairs(state.iconFrames) do
        if HA.ReleaseIcon then
            HA.ReleaseIcon(iconFrame)
        end
    end
    wipe(state.iconFrames)
end

local function DiscoverGroupFrames()
    -- Party frames: CompactPartyFrameMember1..5
    for i = 1, 5 do
        local frame = _G["CompactPartyFrameMember" .. i]
        if frame then
            local ok, unit = pcall(function() return frame.unit end)
            if ok and unit and GROUP_UNITS[unit] then
                -- Skip hidden frames: icons are UIParent-parented, so they'd float visibly
                local visOk, vis = pcall(frame.IsVisible, frame)
                if visOk and vis then
                    local state = ensureState(frame)
                    state.unit = unit
                    if not InCombatLockdown() then
                        local hOk, h = pcall(frame.GetHeight, frame)
                        if hOk and type(h) == "number" and h > 0 then
                            state.cachedHeight = h
                        end
                    end
                end
            end
        end
    end
    -- Raid frames: CompactRaidFrame1..40
    for i = 1, 40 do
        local frame = _G["CompactRaidFrame" .. i]
        if frame then
            local ok, unit = pcall(function() return frame.unit end)
            if ok and unit and GROUP_UNITS[unit] then
                -- Skip hidden frames: icons are UIParent-parented, so they'd float visibly
                local visOk, vis = pcall(frame.IsVisible, frame)
                if visOk and vis then
                    local state = ensureState(frame)
                    state.unit = unit
                    if not InCombatLockdown() then
                        local hOk, h = pcall(frame.GetHeight, frame)
                        if hOk and type(h) == "number" and h > 0 then
                            state.cachedHeight = h
                        end
                    end
                end
            end
        end
    end
end

function HA.RefreshAllAuraDisplays()
    DiscoverGroupFrames()
    for frame, state in pairs(AuraTrackingState) do
        if state.unit and GROUP_UNITS[state.unit] then
            HA.UpdateAurasForFrame(frame, state.unit)
        else
            HA.HideAllAurasForFrame(frame)
        end
    end
end

--------------------------------------------------------------------------------
-- Config Change Refresh
--------------------------------------------------------------------------------
-- When user enables/disables a spell, rebuild tracked set and refresh all
-- custom icons.
--------------------------------------------------------------------------------

function HA.OnConfigChanged()
    HA.RebuildActiveTrackedSet()

    if InCombatLockdown() then
        -- Deferred: the PLAYER_REGEN_ENABLED handler refreshes unconditionally
        return
    end

    HA.RefreshAllAuraDisplays()
end

--------------------------------------------------------------------------------
-- Event Frame
--------------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        if not HA.IsFeatureAvailable() then
            -- One-time warning
            if not HA._secretWarningShown then
                HA._secretWarningShown = true
                -- Only warn if user has any spells configured
                local db = addon.db and addon.db.profile
                local ha = db and db.groupFrames and db.groupFrames.auraTracking
                if ha and ha.spells and next(ha.spells) then
                    print("|cff00ff66Scoot:|r Aura Tracking feature unavailable — aura data is protected.")
                end
            end
            return
        end

        RebuildGroupUnits()
        InstallFrameToUnitHook()
        HA.RebuildActiveTrackedSet()

        -- Delayed initial scan (frames need time to initialize)
        C_Timer.After(1.0, function()
            HA.RefreshAllAuraDisplays()
        end)

    elseif event == "UNIT_AURA" then
        local unit = ...
        if not GROUP_UNITS[unit] then return end
        -- Nothing to do when no tracked spells are enabled
        if not next(HA.ACTIVE_TRACKED_IDS) then return end

        -- Find the frame for this unit and refresh its custom icons.
        local found = false
        for frame, state in pairs(AuraTrackingState) do
            if state.unit == unit then
                HA.UpdateAurasForFrame(frame, unit)
                found = true
            end
        end
        if not found then
            DiscoverGroupFrames()
            for frame, state in pairs(AuraTrackingState) do
                if state.unit == unit then
                    HA.UpdateAurasForFrame(frame, unit)
                end
            end
        end

    elseif event == "GROUP_ROSTER_UPDATE" then
        RebuildGroupUnits()
        C_Timer.After(0.1, function()
            HA.RefreshAllAuraDisplays()
        end)

    elseif event == "PLAYER_REGEN_ENABLED" then
        -- Unconditional: icons frozen during combat secrecy must re-sync even
        -- when no post-combat UNIT_AURA arrives to trigger it, and this also
        -- covers config changes deferred by OnConfigChanged during combat
        HA.RefreshAllAuraDisplays()
    end
end)

eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("UNIT_AURA")
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")

--------------------------------------------------------------------------------
-- Edit Mode Exit Repaint
--------------------------------------------------------------------------------
-- UpdateAurasForFrame refuses to run while Edit Mode is open or transitioning,
-- so nothing repaints the custom icons on Edit Mode exit unless we do it here.
-- Hook EditModeManagerFrame's OnHide directly; it fires reliably even when the
-- EventRegistry exit callback does not (observed under 12.0.5).
--------------------------------------------------------------------------------

local function InstallEditModeExitHook()
    local mgr = _G.EditModeManagerFrame
    if not mgr or HA._editModeExitHookInstalled then return end
    HA._editModeExitHookInstalled = true
    mgr:HookScript("OnHide", function()
        -- MarkExitingEditMode keeps the transition flag true for ~1s; defer the
        -- repaint past that window so IsEditModeOpen() does not block it.
        C_Timer.After(1.05, function()
            if InCombatLockdown() then return end
            if HA.RefreshAllAuraDisplays then HA.RefreshAllAuraDisplays() end
        end)
    end)
end

if _G.EditModeManagerFrame then
    InstallEditModeExitHook()
else
    local hookWaitFrame = CreateFrame("Frame")
    hookWaitFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    hookWaitFrame:SetScript("OnEvent", function(self)
        if _G.EditModeManagerFrame then
            InstallEditModeExitHook()
            self:UnregisterAllEvents()
        end
    end)
end
