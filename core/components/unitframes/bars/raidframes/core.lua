--------------------------------------------------------------------------------
-- bars/raidframes/core.lua
-- Raid frame health bar styling: the raid descriptor for
-- addon.BarsGroupCore.NewFamily (bars/groupcore.lua), which builds the
-- overlay, border, hook, and integrity machinery shared with the party family.
--
-- Applies styling to CompactRaidGroup*Member* and CompactRaidFrame* frames.
-- Uses combat-safe overlay patterns for persistence during combat.
--------------------------------------------------------------------------------

local addonName, addon = ...

-- Get modules
local Utils = addon.BarsUtils
local Combat = addon.BarsCombat

-- Create module namespace
addon.BarsRaidFrames = addon.BarsRaidFrames or {}
local RaidFrames = addon.BarsRaidFrames

--------------------------------------------------------------------------------
-- TAINT PREVENTION: Lookup table for raid frame state
--------------------------------------------------------------------------------
-- Writing properties directly to CompactRaidFrame/CompactRaidGroup
-- frames (or their children) can mark them as "addon-touched". This causes
-- Blizzard field reads (e.g., frame.unit/outOfRange) to return secret values.
-- Store all Scoot state in a separate lookup table keyed by frame.
--------------------------------------------------------------------------------
local RaidFrameState = setmetatable({}, { __mode = "k" }) -- Weak keys for GC

local function getState(frame)
    if not frame then return nil end
    return RaidFrameState[frame]
end

local function ensureState(frame)
    if not frame then return nil end
    if not RaidFrameState[frame] then
        RaidFrameState[frame] = {}
    end
    return RaidFrameState[frame]
end

-- Shared state (exported for text.lua and extras.lua)
addon.BarsRaidFrames._RaidFrameState = RaidFrameState
addon.BarsRaidFrames._getState = getState
addon.BarsRaidFrames._ensureState = ensureState
addon.BarsRaidFrames._isEditModeActive = addon.EditMode.IsEditModeActiveOrOpening

--------------------------------------------------------------------------------
-- Raid Frame Detection
--------------------------------------------------------------------------------

function RaidFrames.isRaidFrame(frame)
    return Utils.isRaidFrame(frame)
end

function RaidFrames.isRaidHealthBar(frame)
    if not frame or not frame.healthBar then return false end
    return Utils.isRaidFrame(frame)
end

--------------------------------------------------------------------------------
-- Frame Iteration
--------------------------------------------------------------------------------
-- Raid bars exist under two naming schemes at once: the group layout
-- (CompactRaidGroup1Member1 and so on) and the combined layout
-- (CompactRaidFrame1..40). Collection dedupes across the two via a
-- raidBarCounted flag in the state table, cleared after each style pass.

local raidHealthBars = {}

function RaidFrames.collectHealthBars()
    raidHealthBars = {}
    -- Pattern 1: Group-based naming (CompactRaidGroup1Member1HealthBar, etc.)
    for group = 1, 8 do
        for member = 1, 5 do
            local frameName = "CompactRaidGroup" .. group .. "Member" .. member .. "HealthBar"
            local bar = _G[frameName]
            if bar then
                table.insert(raidHealthBars, bar)
            end
        end
    end
    -- Pattern 2: Combined naming (CompactRaidFrame1HealthBar, etc.)
    for i = 1, 40 do
        local frameName = "CompactRaidFrame" .. i .. "HealthBar"
        local bar = _G[frameName]
        if bar then
            local state = ensureState(bar)
            if state and not state.raidBarCounted then
                state.raidBarCounted = true
                table.insert(raidHealthBars, bar)
            end
        end
    end
    return raidHealthBars
end

-- Clear the collection dedupe flags after a style pass
local function afterStylePass(bars)
    for _, bar in ipairs(bars) do
        local state = getState(bar)
        if state then state.raidBarCounted = nil end
    end
end

local function forEachUnitFrame(fn)
    -- Combined layout: CompactRaidFrame1..40
    for i = 1, 40 do
        local frame = _G["CompactRaidFrame" .. i]
        if frame then fn(frame) end
    end
    -- Group layout: CompactRaidGroup1..8 Member1..5
    for g = 1, 8 do
        for m = 1, 5 do
            local frame = _G["CompactRaidGroup" .. g .. "Member" .. m]
            if frame then fn(frame) end
        end
    end
end

local function forEachHealthBar(fn)
    -- Combined layout
    for i = 1, 40 do
        local bar = _G["CompactRaidFrame" .. i .. "HealthBar"]
        if bar then fn(bar) end
    end
    -- Group layout
    for group = 1, 8 do
        for member = 1, 5 do
            local bar = _G["CompactRaidGroup" .. group .. "Member" .. member .. "HealthBar"]
            if bar then fn(bar) end
        end
    end
end

--------------------------------------------------------------------------------
-- Family Construction
--------------------------------------------------------------------------------

local family = addon.BarsGroupCore.NewFamily({
    module = RaidFrames,
    getState = getState,
    ensureState = ensureState,
    isTarget = Utils.isRaidFrame,
    dbKey = "raid",
    bgTag = "Raid",
    queueReapply = Combat.queueRaidFrameReapply,
    collectHealthBars = RaidFrames.collectHealthBars,
    forEachUnitFrame = forEachUnitFrame,
    forEachHealthBar = forEachHealthBar,
    afterStylePass = afterStylePass,
    inGroupGate = IsInRaid,
    hooksInstalledFlag = "_RaidFrameHooksInstalled",
    integrityFlag = "_RaidFrameIntegrityCheckInstalled",
    eventOwner = "UnitFrames:RaidFrames",

    -- Transitional fork flags, raid's current semantics (see bars/groupcore.lua)
    valueFallback = "delegateFirst",
    useStylingApplied = false,
    retryOnHidden = false,
    hookOnSizeChanged = false,
    clearFingerprintOnSetUnit = true,
    unconditionalReanchor = true,
    forceRecreateInIntegrity = true,
    reapplyRoleIconOnUpdateAll = false,

    -- Kept forks: raid frames recycle through Blizzard's reservation pool, so
    -- roster events need the debounced full reapply; the textured border keeps
    -- the BackdropTemplate anchor with its issecretvalue guards.
    rosterRefresh = true,
    texturedBorder = "backdrop",
})

-- Module methods (extras.lua and the shared machinery read these at call time)
RaidFrames.applyToHealthBar = family.applyToHealthBar
RaidFrames.ensureHealthOverlay = family.ensureHealthOverlay
RaidFrames.disableHealthOverlay = family.disableHealthOverlay
RaidFrames.installHooks = family.installHooks

-- Refresh chain appliers (called by name from core/refresh.lua and editmode)
addon.ApplyRaidFrameHealthBarBorders = family.applyHealthBarBorders
addon.ApplyRaidFrameHealthBarStyle = family.applyHealthBarStyle
addon.ApplyRaidFrameHealthOverlays = family.applyHealthOverlays
addon.RestoreRaidFrameHealthOverlays = family.restoreHealthOverlays

-- Install hooks on load
RaidFrames.installHooks()
