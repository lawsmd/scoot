--------------------------------------------------------------------------------
-- bars/partyframes/core.lua
-- Party frame health bar styling: the party descriptor for
-- addon.BarsGroupCore.NewFamily (bars/groupcore.lua), which builds the
-- overlay, border, hook, and integrity machinery shared with the raid family.
--
-- Applies styling to CompactPartyFrameMember[1-5] frames.
-- Uses combat-safe overlay patterns for persistence during combat.
--------------------------------------------------------------------------------

local addonName, addon = ...

-- Get modules
local Utils = addon.BarsUtils
local Combat = addon.BarsCombat

-- Create module namespace
addon.BarsPartyFrames = addon.BarsPartyFrames or {}
local PartyFrames = addon.BarsPartyFrames

--------------------------------------------------------------------------------
-- TAINT PREVENTION: Lookup table for party frame state
--------------------------------------------------------------------------------
-- Writing properties directly to CompactPartyFrameMember frames
-- (e.g., frame._ScootActive = true) can mark the entire frame as "addon-touched".
-- Causes ALL field accesses to return secret values in protected contexts
-- (like Edit Mode), breaking Blizzard's own code (frame.outOfRange becomes secret).
--
-- Solution: Store all Scoot state in a separate lookup table keyed by frame.
-- Avoids modifying Blizzard's frames while preserving overlay functionality.
--------------------------------------------------------------------------------
local PartyFrameState = setmetatable({}, { __mode = "k" }) -- Weak keys for GC

local function getState(frame)
    if not frame then return nil end
    return PartyFrameState[frame]
end

local function ensureState(frame)
    if not frame then return nil end
    if not PartyFrameState[frame] then
        PartyFrameState[frame] = {}
    end
    return PartyFrameState[frame]
end

-- Shared state (exported for text.lua and extras.lua)
addon.BarsPartyFrames._PartyFrameState = PartyFrameState
addon.BarsPartyFrames._getState = getState
addon.BarsPartyFrames._ensureState = ensureState
addon.BarsPartyFrames._isEditModeActive = addon.EditMode.IsEditModeActiveOrOpening

--------------------------------------------------------------------------------
-- Party Frame Detection
--------------------------------------------------------------------------------

function PartyFrames.isPartyFrame(frame)
    return Utils.isPartyFrame(frame)
end

function PartyFrames.isPartyHealthBar(frame)
    if not frame or not frame.healthBar then return false end
    return Utils.isPartyFrame(frame)
end

--------------------------------------------------------------------------------
-- Frame Iteration
--------------------------------------------------------------------------------
-- Party member frames are a static array of five; no dedupe is needed.

local partyHealthBars = {}

function PartyFrames.collectHealthBars()
    partyHealthBars = {}
    for i = 1, 5 do
        local bar = _G["CompactPartyFrameMember" .. i .. "HealthBar"]
        if bar then
            table.insert(partyHealthBars, bar)
        end
    end
    return partyHealthBars
end

local function forEachUnitFrame(fn)
    for i = 1, 5 do
        local frame = _G["CompactPartyFrameMember" .. i]
        if frame then fn(frame) end
    end
end

local function forEachHealthBar(fn)
    for i = 1, 5 do
        local bar = _G["CompactPartyFrameMember" .. i .. "HealthBar"]
        if bar then fn(bar) end
    end
end

--------------------------------------------------------------------------------
-- Family Construction
--------------------------------------------------------------------------------

local family = addon.BarsGroupCore.NewFamily({
    module = PartyFrames,
    getState = getState,
    ensureState = ensureState,
    isTarget = Utils.isPartyFrame,
    dbKey = "party",
    bgTag = "Party",
    queueReapply = Combat.queuePartyFrameReapply,
    collectHealthBars = PartyFrames.collectHealthBars,
    forEachUnitFrame = forEachUnitFrame,
    forEachHealthBar = forEachHealthBar,
    inGroupGate = IsInGroup,
    hooksInstalledFlag = "_PartyFrameHooksInstalled",
    integrityFlag = "_PartyFrameIntegrityCheckInstalled",
    eventOwner = "UnitFrames:PartyFrames",

    -- Transitional fork flags, party's current semantics (see bars/groupcore.lua)
    valueFallback = "prePaint",
    useStylingApplied = true,
    retryOnHidden = true,
    hookOnSizeChanged = true,
    clearFingerprintOnSetUnit = false,
    unconditionalReanchor = false,
    forceRecreateInIntegrity = false,
    reapplyRoleIconOnUpdateAll = true,

    -- Kept forks: party member frames are static, so roster events need no
    -- full reapply; the textured border draws edge textures directly on the
    -- CompactUnitFrame so the selection highlight keeps its draw order.
    rosterRefresh = false,
    texturedBorder = "edges",
})

-- Module methods (extras.lua and the shared machinery read these at call time)
PartyFrames.applyToHealthBar = family.applyToHealthBar
PartyFrames.ensureHealthOverlay = family.ensureHealthOverlay
PartyFrames.disableHealthOverlay = family.disableHealthOverlay
PartyFrames.installHooks = family.installHooks

-- Refresh chain appliers (called by name from core/refresh.lua and editmode)
addon.ApplyPartyFrameHealthBarBorders = family.applyHealthBarBorders
addon.ApplyPartyFrameHealthBarStyle = family.applyHealthBarStyle
addon.ApplyPartyFrameHealthOverlays = family.applyHealthOverlays
addon.RestorePartyFrameHealthOverlays = family.restoreHealthOverlays

-- Install hooks on load
PartyFrames.installHooks()
