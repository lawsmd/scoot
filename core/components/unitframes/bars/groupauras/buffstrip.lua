--------------------------------------------------------------------------------
-- groupauras/buffstrip.lua
-- Replacement-overlay rendering for Blizzard buff icons on party/raid frames.
--
-- Background (see ADDONCONTEXT/docs/groupframes/gfauratracking.md):
-- 12.0.5 moved CompactUnitFrame buff rendering into C++ via Blizzard_PrivateAurasUI.
-- The pool frames are forbidden (IsForbidden() == true); the container frame is
-- an EditModeSystemTemplate (Rules 10-11 in debugging/taint.md). Addons can
-- neither modify the buff icons nor the container frame without tainting.
--
-- This module provides the *replacement* workaround: opaque overlay frames drawn
-- on top of whichever Blizzard buff slots are currently rendering, giving them a
-- uniform neutral look so the user's Scoot custom icons dominate visually.
--
-- Taint-safe rules followed:
--   * Overlays are always parented to UIParent (never to CompactUnitFrame).
--   * We only ANCHOR via SetPoint(relativeTo=compactUnitFrame); anchoring is safe,
--     property writes are not.
--   * Reads from the CompactUnitFrame table are pcall-guarded; secret values are
--     swallowed and we fall back to sane defaults.
--   * No write to any Blizzard frame's property table.
--------------------------------------------------------------------------------

local addonName, addon = ...

local HA = addon.AuraTracking
if not HA then return end

--------------------------------------------------------------------------------
-- Constants (mirrored from 12.0.5 Blizzard_PrivateAurasUI.lua / CompactUnitFrame.lua)
--------------------------------------------------------------------------------

local NATIVE_UNIT_FRAME_AURA_SIZE = 11
local CUF_AURA_BOTTOM_OFFSET = 2
local MAX_BUFFS = 6
local OVERLAY_POOL_PREALLOC = 60  -- ~10 frames * 6 slots

-- Grid parameters per auraOrganizationType. Values mirror the Buffs entry of
-- PrivateAuraUnitFrameLayoutTemplates in Blizzard_PrivateAurasUI.lua (12.0.5).
-- columns: horizontal slots per row; anchor: corner of CompactUnitFrame the
-- row originates from; flowX/flowY: per-slot offset direction (in pixels of
-- auraSize) from that anchor.
local AURA_ORG_LAYOUT = {
    -- [Enum.RaidAuraOrganizationType.Legacy] = 0
    [0] = {
        columns = 3,
        anchor = "BOTTOMRIGHT",
        flowX = -1,  -- slots go left from BOTTOMRIGHT
        flowY =  1,  -- rows go up from bottom
        offsetX = -3,
        offsetY = CUF_AURA_BOTTOM_OFFSET,
    },
    -- [Enum.RaidAuraOrganizationType.BuffsTopDebuffsBottom] = 1
    [1] = {
        columns = 6,
        anchor = "TOPRIGHT",
        flowX = -1,
        flowY = -1,  -- downward from top
        offsetX = -3,
        offsetY = -3,
    },
    -- [Enum.RaidAuraOrganizationType.BuffsRightDebuffsLeft] = 2
    [2] = {
        columns = 3,
        anchor = "BOTTOMRIGHT",
        flowX = -1,
        flowY =  1,
        offsetX = -3,
        offsetY = CUF_AURA_BOTTOM_OFFSET,
    },
}

--------------------------------------------------------------------------------
-- Overlay Pool (UIParent-parented, never touches Blizzard frames beyond anchoring)
--------------------------------------------------------------------------------

local overlayPool = {}
local activeOverlays = setmetatable({}, { __mode = "k" })  -- [compactUnitFrame] = {overlay1, ...}

local function CreateOverlayFrame()
    local f = CreateFrame("Frame", nil, UIParent)
    -- MEDIUM (core/strata.lua), not HIGH: Blizzard's raid frames and their auras
    -- are LOW, so MEDIUM still wins there while letting Blizzard panels cover us.
    -- Level 19 unchanged: below Scoot's custom icons (level 20), above Blizzard's buffs.
    addon.Strata.ApplyHUD(f, 19)
    f:SetSize(11, 11)

    local bg = f:CreateTexture(nil, "ARTWORK")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 1)
    f.Bg = bg

    local num = f:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    num:SetPoint("CENTER", f, "CENTER", 0, 0)
    num:SetTextColor(0.9, 0.9, 0.9, 1)
    num:Hide()
    f.Num = num

    f:Hide()
    return f
end

local function PreallocateOverlayPool()
    for i = 1, OVERLAY_POOL_PREALLOC do
        table.insert(overlayPool, CreateOverlayFrame())
    end
end

local function AcquireOverlay()
    local f = table.remove(overlayPool)
    if not f then
        if InCombatLockdown() then return nil end
        f = CreateOverlayFrame()
    end
    return f
end

local function ReleaseOverlay(f)
    if not f then return end
    f:Hide()
    f:ClearAllPoints()
    if f.Num then f.Num:Hide() end
    table.insert(overlayPool, f)
end

--------------------------------------------------------------------------------
-- Config reads
--------------------------------------------------------------------------------

local function GetReplacementStyle()
    local db = addon.db and addon.db.profile
    local at = db and db.groupFrames and db.groupFrames.auraTracking
    return (at and at.replacementStyle) or "none"
end

local function ReadGroupType(frame)
    if not frame then return nil end
    local ok, v = pcall(function() return frame.groupType end)
    if ok and type(v) == "number" then return v end
    return nil
end

local function ReadPowerBarUsedHeight(frame)
    if not frame then return 0 end
    local ok, v = pcall(function() return frame.powerBarUsedHeight end)
    if ok and type(v) == "number" then return v end
    return 0
end

local function ReadAuraOrganizationType(frame)
    local groupType = ReadGroupType(frame)
    if not groupType or not EditModeManagerFrame then return 0 end
    local ok, v = pcall(EditModeManagerFrame.GetRaidFrameAuraOrganizationType, EditModeManagerFrame, groupType)
    if ok and type(v) == "number" then return v end
    return 0
end

local function ReadAuraSize(frame)
    local groupType = ReadGroupType(frame)
    local EM = _G.Enum and _G.Enum.EditModeUnitFrameSetting
    if not groupType or not EditModeManagerFrame or not EM or not EM.IconSize then
        return NATIVE_UNIT_FRAME_AURA_SIZE
    end
    local ok, iconScale = pcall(EditModeManagerFrame.GetRaidFrameIconScale, EditModeManagerFrame, groupType, 1, EM.IconSize)
    if ok and type(iconScale) == "number" and iconScale > 0 then
        return NATIVE_UNIT_FRAME_AURA_SIZE * iconScale
    end
    return NATIVE_UNIT_FRAME_AURA_SIZE
end

--------------------------------------------------------------------------------
-- Buff count scanning — Scoot-owned reimplementation of AuraUtil.ShouldDisplayBuff.
--
-- `AuraUtil.ForEachAura(unit, "HELPFUL")` over-counts: it returns every helpful
-- aura on the unit (raid buffs, personal buffs, passive auras, weapon enchants,
-- etc.), but CompactUnitFrame only renders auras passing a visibility filter.
--
-- We can NOT call AuraUtil.ProcessAura / AuraUtil.ShouldDisplayBuff to replicate
-- that filter: ShouldDisplayBuff indexes the closure-local `cachedVisualizationInfo`
-- table (AuraUtil.lua:272), which is wiped on every PLAYER_REGEN_DISABLED by an
-- EventRegistry callback. The fresh-allocated table is born forbidden to Scoot
-- because combat-entry event dispatch has already propagated our taint, so every
-- in-combat call into ShouldDisplayBuff raises
-- "attempted to index a table that cannot be accessed while tainted". pcall
-- catches the error but does not suppress Blizzard's error taplog.
--
-- Instead, we inline the ShouldDisplayBuff logic using our own caches of
-- C_Spell.GetVisibilityInfo and C_Spell.IsSelfBuff (static spell-metadata C APIs,
-- not combat-state). Our cache tables are addon-owned; if they get Scoot-tainted
-- that is fine because only Scoot reads them.
--------------------------------------------------------------------------------

local visibilityCache = {}
local selfBuffCache = {}

local function ScootGetVisibilityInfo(spellId)
    local cached = visibilityCache[spellId]
    if cached then return cached[1], cached[2], cached[3] end
    local SAV = _G.Enum and _G.Enum.SpellAuraVisibilityType
    if not SAV or not C_Spell or not C_Spell.GetVisibilityInfo then
        return nil, nil, nil
    end
    local visType = UnitAffectingCombat("player") and SAV.RaidInCombat or SAV.RaidOutOfCombat
    local ok, a, b, c = pcall(C_Spell.GetVisibilityInfo, spellId, visType)
    if not ok then return nil, nil, nil end
    visibilityCache[spellId] = { a, b, c }
    return a, b, c
end

local function ScootIsSelfBuff(spellId)
    local cached = selfBuffCache[spellId]
    if cached ~= nil then return cached end
    if not C_Spell or not C_Spell.IsSelfBuff then return false end
    local ok, v = pcall(C_Spell.IsSelfBuff, spellId)
    if not ok then return false end
    selfBuffCache[spellId] = v and true or false
    return selfBuffCache[spellId]
end

local function ScootShouldDisplayBuff(sourceUnit, spellId, canApplyAura)
    local hasCustom, alwaysShowMine, showForMySpec = ScootGetVisibilityInfo(spellId)
    if hasCustom then
        return showForMySpec
            or (alwaysShowMine and (sourceUnit == "player" or sourceUnit == "pet" or sourceUnit == "vehicle"))
    elseif (sourceUnit == "player" or sourceUnit == "pet" or sourceUnit == "vehicle") and canApplyAura then
        return not ScootIsSelfBuff(spellId)
    else
        return false
    end
end

local function CountHelpfulAuras(unit)
    if not unit or not UnitExists(unit) then return 0 end
    if not AuraUtil or not AuraUtil.ForEachAura then return 0 end

    local count = 0
    local function handle(aura)
        if not aura then return false end
        if aura.isNameplateOnly then return false end
        if aura.isBossAura and not aura.isRaid then return false end
        if not aura.isHelpful then return false end

        local spellId      = aura.spellId
        local sourceUnit   = aura.sourceUnit
        local canApplyAura = aura.canApplyAura
        if type(spellId) ~= "number" then return false end

        if ScootShouldDisplayBuff(sourceUnit, spellId, canApplyAura) then
            count = count + 1
        end
        return count >= MAX_BUFFS
    end

    pcall(AuraUtil.ForEachAura, unit, "HELPFUL", nil, handle, true)
    return math.min(count, MAX_BUFFS)
end

-- Cache invalidation on spec change. Visibility info is spec-specific (matches
-- AuraUtil's own PLAYER_SPECIALIZATION_CHANGED reset at AuraUtil.lua:266-269).
local cacheResetFrame = CreateFrame("Frame")
cacheResetFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
cacheResetFrame:SetScript("OnEvent", function()
    visibilityCache = {}
    selfBuffCache = {}
end)

--------------------------------------------------------------------------------
-- Per-slot positioning
--------------------------------------------------------------------------------

local function PositionOverlay(overlay, frame, slotIndex, layout, auraSize, powerBarUsedHeight)
    local col = (slotIndex - 1) % layout.columns
    local row = math.floor((slotIndex - 1) / layout.columns)
    local extraY = (layout.anchor == "BOTTOMRIGHT" or layout.anchor == "BOTTOMLEFT") and powerBarUsedHeight or 0
    local x = layout.offsetX + (layout.flowX * col * auraSize)
    local y = layout.offsetY + extraY + (layout.flowY * row * auraSize)
    overlay:ClearAllPoints()
    overlay:SetPoint(layout.anchor, frame, layout.anchor, x, y)
    overlay:SetSize(auraSize, auraSize)
end

local function StyleOverlay(overlay, style, slotIndex)
    if style == "numbered" then
        overlay.Bg:SetColorTexture(0, 0, 0, 0.88)
        overlay.Num:SetText(tostring(slotIndex))
        overlay.Num:Show()
    else  -- "solidBlack" or any unknown → opaque black
        overlay.Bg:SetColorTexture(0, 0, 0, 1)
        overlay.Num:Hide()
    end
end

--------------------------------------------------------------------------------
-- Per-frame refresh
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

function HA.RefreshOverlaysForFrame(frame, unit)
    if not frame then return end
    -- Edit Mode gate: don't render replacement overlays while the user is in
    -- (or transitioning into/out of) Blizzard's Edit Mode. Mirrors the same
    -- guard applied to the custom-icon pipeline in core.lua's UpdateAurasForFrame.
    if IsEditModeOpen() then return end
    local style = GetReplacementStyle()
    local actives = activeOverlays[frame]

    -- Style "none" → release all overlays on this frame
    if style == "none" then
        if actives then
            for i = #actives, 1, -1 do
                ReleaseOverlay(actives[i])
                actives[i] = nil
            end
            activeOverlays[frame] = nil
        end
        return
    end

    -- Frame must be visible
    local okVis, visible = pcall(frame.IsVisible, frame)
    if not okVis or not visible then
        if actives then
            for i = #actives, 1, -1 do
                ReleaseOverlay(actives[i])
                actives[i] = nil
            end
            activeOverlays[frame] = nil
        end
        return
    end

    local desired = CountHelpfulAuras(unit)
    if desired <= 0 then
        if actives then
            for i = #actives, 1, -1 do
                ReleaseOverlay(actives[i])
                actives[i] = nil
            end
            activeOverlays[frame] = nil
        end
        return
    end

    -- PvP arena frames set max-buffs to 0; respect that by reading maxBuffs
    local okMax, maxBuffs = pcall(function() return frame.maxBuffs end)
    if okMax and type(maxBuffs) == "number" then
        if maxBuffs <= 0 then
            if actives then
                for i = #actives, 1, -1 do
                    ReleaseOverlay(actives[i])
                    actives[i] = nil
                end
                activeOverlays[frame] = nil
            end
            return
        end
        desired = math.min(desired, maxBuffs)
    end

    local auraOrgType = ReadAuraOrganizationType(frame)
    local layout = AURA_ORG_LAYOUT[auraOrgType] or AURA_ORG_LAYOUT[0]
    local auraSize = ReadAuraSize(frame)
    local powerBarUsedHeight = ReadPowerBarUsedHeight(frame)

    actives = actives or {}
    activeOverlays[frame] = actives

    -- Grow pool on this frame if needed
    while #actives < desired do
        local ov = AcquireOverlay()
        if not ov then break end
        table.insert(actives, ov)
    end

    -- Shrink if we have too many active
    while #actives > desired do
        local ov = table.remove(actives)
        ReleaseOverlay(ov)
    end

    -- Style + position each active overlay
    for i = 1, #actives do
        local ov = actives[i]
        StyleOverlay(ov, style, i)
        PositionOverlay(ov, frame, i, layout, auraSize, powerBarUsedHeight)
        ov:Show()
    end
end

--------------------------------------------------------------------------------
-- Public API (called from core.lua config-change + per-unit refresh paths)
--------------------------------------------------------------------------------

-- Wipe overlays for a frame (e.g., when its unit goes away). Taint-safe.
function HA.ReleaseOverlaysForFrame(frame)
    if not frame then return end
    local actives = activeOverlays[frame]
    if not actives then return end
    for i = #actives, 1, -1 do
        ReleaseOverlay(actives[i])
        actives[i] = nil
    end
    activeOverlays[frame] = nil
end

-- Wipe overlays across every tracked frame. Used on Edit Mode entry so any
-- previously-rendered replacement overlays disappear cleanly during layout edit.
function HA.ReleaseAllOverlays()
    for frame in pairs(activeOverlays) do
        HA.ReleaseOverlaysForFrame(frame)
    end
end

-- Style-changed refresh: iterate known tracked frames, re-render each. Called by
-- AuraTrackingRenderer set() hooks when the user changes replacementStyle or
-- positionGroupSpacing. Safe OOC (pool expansion) and in combat (uses pre-alloc
-- only; skips grow when lockdown).
function HA.RefreshBuffStripScaling()
    local state = HA._AuraTrackingState
    if not state then return end
    for frame, frameState in pairs(state) do
        if frameState and frameState.unit then
            HA.RefreshOverlaysForFrame(frame, frameState.unit)
        end
    end
end

--------------------------------------------------------------------------------
-- Initialization
--------------------------------------------------------------------------------

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
initFrame:SetScript("OnEvent", function(self)
    PreallocateOverlayPool()
    self:UnregisterAllEvents()
end)

-- Edit Mode lifecycle hooks: clear overlays on entry, restore them on exit.
-- Hook the EditModeManagerFrame's OnShow/OnHide directly — this is the same
-- pattern nudgearrows.lua uses and fires reliably regardless of whether
-- the EventRegistry "EditMode.Enter"/"EditMode.Exit" callbacks dispatch.
local function InstallEditModeLifecycleHooks()
    local mgr = _G.EditModeManagerFrame
    if not mgr or HA._editModeHooksInstalled then return end
    HA._editModeHooksInstalled = true

    mgr:HookScript("OnShow", function()
        HA.ReleaseAllOverlays()
    end)

    mgr:HookScript("OnHide", function()
        -- MarkExitingEditMode keeps the transition flag true for ~1s. Release
        -- any orphaned overlays now (covers preview frames anchored to hidden
        -- frames), then defer the repaint past the transition window so the
        -- function-level guard doesn't block it.
        HA.ReleaseAllOverlays()
        C_Timer.After(1.05, function()
            if InCombatLockdown() then return end
            if HA.RefreshAllAuraDisplays then HA.RefreshAllAuraDisplays() end
        end)
    end)
end

if _G.EditModeManagerFrame then
    InstallEditModeLifecycleHooks()
else
    local hookFrame = CreateFrame("Frame")
    hookFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    hookFrame:SetScript("OnEvent", function(self)
        if _G.EditModeManagerFrame then
            InstallEditModeLifecycleHooks()
            self:UnregisterAllEvents()
        end
    end)
end
