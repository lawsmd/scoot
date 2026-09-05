--------------------------------------------------------------------------------
-- groupauras/core.lua
-- Aura Tracking on group frames (party + raid)
--
-- Spell registry, priority ordering, the enabled-spell list, frame discovery,
-- events and the rainbow color engine. Containers and slots live in
-- engine.lua; button regions, styling and geometry live in icons.lua.
--
-- The registry is a list of curated suggestions, not a capability boundary.
-- Under the 12.1 AuraContainer the engine matches spell IDs on its own side,
-- so any helpful aura on a group member is trackable; the table exists to give
-- the settings UI something to show. That is a change from the pre-12.1 design,
-- where the list named the few spells Blizzard had un-secreted.
--
-- Hiding Blizzard's own buff icons is handled by the raidFramesDisplayBuffs
-- CVar (see the groupBuffIconsHidden applier in core/profiles/cvars.lua),
-- not by anything in this component.
--------------------------------------------------------------------------------

local addonName, addon = ...

addon.AuraTracking = addon.AuraTracking or {}
local HA = addon.AuraTracking


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
-- spellId → owning class token. Needed because positions are fixed: a spell the
-- player cannot cast would otherwise hold an empty slot forever (see
-- RebuildEnabledSpells).
HA.SPELL_CLASS_BY_ID = {}
for classToken, spells in pairs(HA.SPELL_REGISTRY) do
    for _, entry in ipairs(spells) do
        HA.SPELL_REGISTRY_BY_ID[entry.id] = entry
        HA.SPELL_CLASS_BY_ID[entry.id] = classToken
        if entry.linkedIds then
            for _, linkedId in ipairs(entry.linkedIds) do
                HA.SPELL_REGISTRY_BY_ID[linkedId] = entry
                HA.SPELL_CLASS_BY_ID[linkedId] = classToken
            end
        end
    end
end
table.freeze(HA.SPELL_REGISTRY_BY_ID)
table.freeze(HA.SPELL_CLASS_BY_ID)

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
-- Enabled Spell List
--------------------------------------------------------------------------------
-- The set of spells that get a container slot. Rebuilt on every config change
-- and read by the engine and the layout pass, so it is cached rather than
-- walked twice per frame.
--
-- Linked registry variants (the per-class Blessing of the Bronze IDs and the
-- like) do NOT get their own slot: they fold into their parent's
-- includeSpellIDs set, where the engine matches them.
--------------------------------------------------------------------------------

local enabledSpells = {}
local enabledDirty = true

--- True when an enabled spell can ever produce an icon for this character.
---
--- Positions are fixed since the 12.1 port, so every entry in this list holds a
--- slot whether or not the aura is ever present. That makes an unreachable spell
--- a visible defect rather than a harmless no-op: the settings page shows one
--- class tab at a time, so a spell enabled while browsing another class stays
--- invisible in the UI and silently pushes this character's own icons along the
--- row. Own-casts-only cannot match a spell this class does not have, so drop it.
--- "Track all sources" keeps it: watching the raid druid's Rejuvenation as a
--- priest is a real thing to want.
local function ReachableByPlayer(spellId, config)
    if config.trackAllSources then return true end
    local owner = HA.SPELL_CLASS_BY_ID[spellId]
    if not owner then return true end
    local _, playerClass = UnitClass("player")
    if not playerClass then return true end
    return owner == playerClass
end
HA.ReachableByPlayer = ReachableByPlayer

function HA.RebuildEnabledSpells()
    wipe(enabledSpells)
    local db = addon.db and addon.db.profile
    local ha = db and db.groupFrames and db.groupFrames.auraTracking
    local spells = ha and ha.spells
    if spells then
        for spellId, config in pairs(spells) do
            -- Ignore stale DB entries for spells no longer in the registry
            if config.enabled and HA.SPELL_REGISTRY_BY_ID[spellId]
                and ReachableByPlayer(spellId, config) then
                table.insert(enabledSpells, { spellId = spellId, config = config })
            end
        end
        -- Deterministic order so slot creation and layout agree run to run
        table.sort(enabledSpells, function(a, b) return a.spellId < b.spellId end)
    end
    enabledDirty = false
    return enabledSpells
end

function HA.EnabledSpellList()
    if enabledDirty then HA.RebuildEnabledSpells() end
    return enabledSpells
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
-- Shared OnUpdate frame, self-disabling when no rainbow icon is registered.
-- Hue comes from GetTime() so static icons and animated controllers share one
-- phase without sharing state.
--
-- Registered textures are colored unconditionally. They hang under engine aura
-- buttons whose shown state is a SECRET, so IsVisible() on one returns a secret
-- boolean and testing it throws. Painting a hidden texture costs nothing.
--------------------------------------------------------------------------------

HA._rainbowIcons = {}
local rainbowIcons = HA._rainbowIcons
local RAINBOW_CYCLE_PERIOD = 3.0

local rainbowFrame = CreateFrame("Frame")
rainbowFrame:SetScript("OnUpdate", function(self)
    if not next(rainbowIcons) then
        self:Hide()
        return
    end
    local r, g, b = HA.HSVtoRGB((GetTime() / RAINBOW_CYCLE_PERIOD) % 1, 0.75, 1)
    for tex in pairs(rainbowIcons) do
        pcall(tex.SetVertexColor, tex, r, g, b, 1)
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
-- Edit Mode guard
--------------------------------------------------------------------------------

-- Kept as a deliberate widening of the canonical check (refactor #31,
-- 2026-09-02): the IsShown fallback below works around EventRegistry
-- callbacks that lag or fail to fire. Do not collapse this to the canonical
-- alone while that behavior exists.
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

--------------------------------------------------------------------------------
-- Frame discovery
--------------------------------------------------------------------------------
-- Frames are found by their documented global names, never guessed. A frame
-- with no unit, or one that is not visible, is parked rather than skipped: its
-- container would otherwise keep drawing the last subject's auras.

local function SyncFrame(frame)
    if not frame then return end
    local unitOk, unit = pcall(function() return frame.unit end)
    if not unitOk or issecretvalue(unit) or type(unit) ~= "string" then unit = nil end

    local visOk, vis = pcall(frame.IsVisible, frame)
    if unit and GROUP_UNITS[unit] and visOk and vis then
        HA.Engine.SyncFrame(frame, unit)
    else
        HA.Engine.HideFrame(frame)
    end
end

local function DiscoverGroupFrames()
    for i = 1, 5 do
        SyncFrame(_G["CompactPartyFrameMember" .. i])
    end
    for i = 1, 40 do
        SyncFrame(_G["CompactRaidFrame" .. i])
    end
end
HA._DiscoverGroupFrames = DiscoverGroupFrames

--- Discovery IS the refresh: SyncFrame runs on every named group frame, and a
--- frame that lost its unit or its visibility gets parked by the same pass.
--- Frames Blizzard creates outside the name list arrive through the
--- CompactUnitFrame_SetUnit hook instead.
function HA.RefreshAllAuraDisplays()
    if IsEditModeOpen() then return end
    DiscoverGroupFrames()
end

--------------------------------------------------------------------------------
-- Frame-to-Unit Mapping
--------------------------------------------------------------------------------
-- CompactUnitFrame_SetUnit hands the unit token as an argument, so nothing has
-- to read it off the frame. Re-pointing a container's subject is Tier 1, which
-- is why a roster change mid-fight still lands.
--------------------------------------------------------------------------------

local frameToUnitHookInstalled = false

local function InstallFrameToUnitHook()
    if frameToUnitHookInstalled then return end
    if not CompactUnitFrame_SetUnit then return end

    hooksecurefunc("CompactUnitFrame_SetUnit", function(frame, unit)
        if not frame then return end
        -- Skip during Edit Mode to avoid taint propagation
        if IsEditModeOpen() then return end

        if unit and GROUP_UNITS[unit] then
            local visOk, vis = pcall(frame.IsVisible, frame)
            if visOk and vis then
                HA.Engine.SetSubject(frame, unit)
                return
            end
        end
        HA.Engine.HideFrame(frame)
    end)

    frameToUnitHookInstalled = true
end

--------------------------------------------------------------------------------
-- Config Change Refresh
--------------------------------------------------------------------------------
-- Enable, disable, restyle and re-anchor all land here. Slot creation is the
-- only part that needs an open structural window; retiring a slot, re-pointing
-- its filters and moving its proxy are all legal in combat, so a change made
-- mid-fight is not simply dropped.
--------------------------------------------------------------------------------

function HA.OnConfigChanged()
    enabledDirty = true
    HA.RebuildEnabledSpells()
    -- Discovery, not a walk of known frames: the first aura a user ever enables
    -- has no containers yet, and Zero-Touch means nothing was built to walk.
    HA.RefreshAllAuraDisplays()
end

--------------------------------------------------------------------------------
-- Event Frame
--------------------------------------------------------------------------------
-- UNIT_AURA is deliberately absent. The container tracks its own unit inside
-- the engine, and an addon-side aura scan is exactly the thing 12.1 removed.

local function onEvent(event)
    if event == "PLAYER_ENTERING_WORLD" then
        RebuildGroupUnits()
        InstallFrameToUnitHook()
        HA.RebuildEnabledSpells()

        -- Compact frames need a moment to exist and take their units
        C_Timer.After(1.0, HA.RefreshAllAuraDisplays)

    elseif event == "GROUP_ROSTER_UPDATE" then
        RebuildGroupUnits()
        C_Timer.After(0.1, HA.RefreshAllAuraDisplays)

    elseif event == "PLAYER_REGEN_ENABLED" then
        -- Frames hidden or re-pointed during the fight, and any slot the engine
        -- refused to build while auras were secret. The engine's own drain
        -- watcher covers the queue; this covers discovery.
        HA.RefreshAllAuraDisplays()
    end
end

addon.Events.On("UnitFrames:GroupAuras", "PLAYER_ENTERING_WORLD", onEvent)
addon.Events.On("UnitFrames:GroupAuras", "GROUP_ROSTER_UPDATE", onEvent)
addon.Events.On("UnitFrames:GroupAuras", "PLAYER_REGEN_ENABLED", onEvent)

--------------------------------------------------------------------------------
-- Edit Mode Exit Repaint
--------------------------------------------------------------------------------
-- Nothing repaints on Edit Mode exit unless this hook does: the guards above
-- refuse to run while Edit Mode is open or transitioning. Hook
-- EditModeManagerFrame's OnHide directly; it fires reliably even when the
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
            HA.RefreshAllAuraDisplays()
        end)
    end)
end

if _G.EditModeManagerFrame then
    InstallEditModeExitHook()
else
    -- Retry each world entry until the manager frame exists, then release.
    -- Off() from inside the handler's own dispatch is safe: the bus tombstones
    -- the entry and compacts after the dispatch unwinds.
    local handle
    handle = addon.Events.On("UnitFrames:GroupAuras", "PLAYER_ENTERING_WORLD", function()
        if _G.EditModeManagerFrame then
            InstallEditModeExitHook()
            handle:Off()
        end
    end)
end
