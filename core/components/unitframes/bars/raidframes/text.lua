--------------------------------------------------------------------------------
-- bars/raidframes/text.lua
-- Raid frame text styling: legacy text, name overlays, status text overlays,
-- group title styling, and text hook installation.
--
-- Loaded after raidframes/core.lua. Imports shared state from
-- addon.BarsRaidFrames.
--------------------------------------------------------------------------------

local addonName, addon = ...

-- Scratch opts for ResolveColorRGBA (name overlay text; no barKind)
local gfTextColorOpts = {}

-- Font-half opts for the group title text
local gfTitleFontOpts = { size = 12 }

-- Get modules
local Utils = addon.BarsUtils
local Combat = addon.BarsCombat

-- Get module namespace (created in core.lua)
local RaidFrames = addon.BarsRaidFrames

-- Import shared state from core.lua
local RaidFrameState = addon.BarsRaidFrames._RaidFrameState
local getState = addon.BarsRaidFrames._getState
local ensureState = addon.BarsRaidFrames._ensureState
local isEditModeActive = addon.BarsRaidFrames._isEditModeActive

--------------------------------------------------------------------------------
-- Overlay family binding
--------------------------------------------------------------------------------
-- The shared factory (bars/textoverlay.lua) owns the ensure/style/disable
-- machinery for the name and status overlays; this file keeps the public
-- entry points, DB gating, and hook installation. The raid hook paths run
-- unscreened (no screenFrame use) to preserve the shipped behavior; the
-- screening flip is the gated hardening session.
local Raid = addon.BarsTextOverlay.NewFamily({
    getState = getState,
    ensureState = ensureState,
    isEditModeActive = isEditModeActive,
    isTarget = Utils.isRaidFrame,
    screenFrame = addon.SecretSafe.plainFrame,
    queueReapply = function() Combat.queueRaidFrameReapply() end,
    statusDefaultAnchor = "TOPLEFT",
    colorScratch = gfTextColorOpts,
})

local styleRaidNameOverlay = Raid.styleNameOverlay
local ensureRaidNameOverlay = Raid.ensureNameOverlay
local disableRaidNameOverlay = Raid.disableNameOverlay
local styleRaidStatusTextOverlay = Raid.styleStatusOverlay
local ensureRaidStatusTextOverlay = Raid.ensureStatusOverlay
local disableRaidStatusTextOverlay = Raid.disableStatusOverlay

--------------------------------------------------------------------------------
-- Text Styling (Player Name)
--------------------------------------------------------------------------------
-- Applies font settings to raid frame name text elements.
-- Target: CompactRaidGroup*Member*Name (the name FontString on each raid unit frame)
--------------------------------------------------------------------------------

-- Main entry point: Apply raid frame text styling from DB settings
function addon.ApplyRaidFrameTextStyle()
    local db = addon and addon.db and addon.db.profile
    if not db then return end

    -- Zero-Touch: only apply if user has configured raid text styling.
    local groupFrames = rawget(db, "groupFrames")
    local raidCfg = groupFrames and rawget(groupFrames, "raid") or nil
    local cfg = raidCfg and rawget(raidCfg, "textPlayerName") or nil
    if not cfg then
        return
    end

    -- Zero-Touch: if the user changed nothing from the defaults, do nothing.
    if not Utils.hasCustomTextSettings(cfg) then
        return
    end

    -- Name styling delegates to overlay FontStrings. Moving Blizzard's `frame.name`
    -- is avoided because the overlay clipping container copies its anchor geometry to preserve
    -- truncation. Touching `frame.name` here reintroduces leaking/incorrect clipping.
    if addon.ApplyRaidFrameNameOverlays then
        addon.ApplyRaidFrameNameOverlays()
    end
end

-- Install hooks to reapply text styling when raid frames update
local function installRaidFrameTextHooks()
    if addon._RaidFrameTextHooksInstalled then return end
    addon._RaidFrameTextHooksInstalled = true

    -- Name hooks are installed by the overlay system (installRaidNameOverlayHooks).
end

--------------------------------------------------------------------------------
-- Text Overlay (Name Text - Combat-Safe Persistence)
--------------------------------------------------------------------------------
-- Creates addon-owned FontString overlays on raid frames that visually replace
-- Blizzard's name text. These overlays can be styled during initial setup and
-- their text content can be updated during combat without taint because only
-- addon-owned FontStrings are manipulated.
--
-- Pattern: Mirror text via SetText hook, style on setup, hide Blizzard's element.
--------------------------------------------------------------------------------

function addon.ApplyRaidFrameNameOverlays()
    local db = addon and addon.db and addon.db.profile
    if not db then return end

    local groupFrames = rawget(db, "groupFrames")
    local raidCfg = groupFrames and rawget(groupFrames, "raid") or nil

    -- Zero-Touch: if no raid config exists, don't touch raid frames at all
    if not raidCfg then return end

    local cfg = rawget(raidCfg, "textPlayerName") or nil
    local hasCustom = Utils.hasCustomTextSettings(cfg)

    -- If no custom settings, skip - let RestoreRaidFrameNameOverlays handle cleanup
    if not hasCustom then return end

    -- Combined layout: CompactRaidFrame1..40
    for i = 1, 40 do
        local frame = _G["CompactRaidFrame" .. i]
        if frame and frame.name then
            if not (InCombatLockdown and InCombatLockdown()) then
                ensureRaidNameOverlay(frame, cfg)
            else
                local state = getState(frame)
                if state and state.nameOverlayText then
                    styleRaidNameOverlay(frame, cfg)
                end
            end
        end
    end

    -- Group layout: CompactRaidGroup1Member1..CompactRaidGroup8Member5
    for group = 1, 8 do
        for member = 1, 5 do
            local frame = _G["CompactRaidGroup" .. group .. "Member" .. member]
            if frame and frame.name then
                if not (InCombatLockdown and InCombatLockdown()) then
                    ensureRaidNameOverlay(frame, cfg)
                else
                    local state = getState(frame)
                    if state and state.nameOverlayText then
                        styleRaidNameOverlay(frame, cfg)
                    end
                end
            end
        end
    end
end

function addon.RestoreRaidFrameNameOverlays()
    for i = 1, 40 do
        local frame = _G["CompactRaidFrame" .. i]
        if frame then
            disableRaidNameOverlay(frame)
        end
    end
    for group = 1, 8 do
        for member = 1, 5 do
            local frame = _G["CompactRaidGroup" .. group .. "Member" .. member]
            if frame then
                disableRaidNameOverlay(frame)
            end
        end
    end
end

local function installRaidNameOverlayHooks()
    if addon._RaidNameOverlayHooksInstalled then return end
    addon._RaidNameOverlayHooksInstalled = true

    local function getCfg()
        local db = addon and addon.db and addon.db.profile
        local gf = db and rawget(db, "groupFrames") or nil
        local raidCfg = gf and rawget(gf, "raid") or nil
        return raidCfg and rawget(raidCfg, "textPlayerName") or nil
    end

    if _G.hooksecurefunc and _G.CompactUnitFrame_UpdateAll then
        _G.hooksecurefunc("CompactUnitFrame_UpdateAll",
            Raid.makeCUFHandler("name", getCfg))
    end
    if _G.hooksecurefunc and _G.CompactUnitFrame_SetUnit then
        _G.hooksecurefunc("CompactUnitFrame_SetUnit",
            Raid.makeCUFHandler("name", getCfg, { requireUnit = true }))
    end
    if _G.hooksecurefunc and _G.CompactUnitFrame_UpdateName then
        _G.hooksecurefunc("CompactUnitFrame_UpdateName",
            Raid.makeCUFHandler("name", getCfg))
    end

    -- Event-driven re-application for raid composition changes.
    if not addon._RaidNameRosterEventInstalled then
        addon._RaidNameRosterEventInstalled = true
        addon.Events.On("UnitFrames:RaidText", "GROUP_ROSTER_UPDATE", function()
            if isEditModeActive() then return end

            local cfg = getCfg()
            if not cfg or (cfg.colorMode or "default") ~= "class" then return end
            if not Utils.hasCustomTextSettings(cfg) then return end

            if _G.C_Timer and _G.C_Timer.After then
                _G.C_Timer.After(0.5, function()
                    if isEditModeActive() then return end
                    if InCombatLockdown and InCombatLockdown() then
                        Combat.queueRaidFrameReapply()
                        return
                    end
                    -- Clear fingerprints to force full re-style after roster change
                    for i = 1, 40 do
                        local f = _G["CompactRaidFrame" .. i]
                        if f then
                            local s = getState(f)
                            if s then s.lastNameFingerprint = nil end
                        end
                    end
                    for group = 1, 8 do
                        for member = 1, 5 do
                            local f = _G["CompactRaidGroup" .. group .. "Member" .. member]
                            if f then
                                local s = getState(f)
                                if s then s.lastNameFingerprint = nil end
                            end
                        end
                    end
                    if addon.ApplyRaidFrameNameOverlays then
                        addon.ApplyRaidFrameNameOverlays()
                    end
                end)
            end
        end)
    end
end

--------------------------------------------------------------------------------
-- Text Overlay (Status Text - Combat-Safe Persistence)
--------------------------------------------------------------------------------
-- Creates addon-owned FontString overlays on raid frames that visually replace
-- Blizzard's statusText. These overlays persist during combat because only
-- addon-owned FontStrings are manipulated. Blizzard can reset its own
-- statusText all it wants -- the Scoot overlay stays styled.
--
-- Pattern: Mirror text via SetText/SetFormattedText hooks, style on setup,
-- hide Blizzard's element via SetAlpha(0).
--------------------------------------------------------------------------------

function addon.ApplyRaidFrameStatusTextStyle()
    local db = addon and addon.db and addon.db.profile
    if not db then return end

    -- Zero-Touch: only apply if user has configured raid status text styling.
    local groupFrames = rawget(db, "groupFrames")
    local raidCfg = groupFrames and rawget(groupFrames, "raid") or nil
    local cfg = raidCfg and rawget(raidCfg, "textStatusText") or nil
    if not cfg then
        return
    end

    -- Zero-Touch: if the user changed nothing from the defaults, do nothing.
    if not Utils.hasCustomTextSettings(cfg) then
        return
    end

    -- Combined layout: CompactRaidFrame1..40
    for i = 1, 40 do
        local frame = _G["CompactRaidFrame" .. i]
        if frame and frame.statusText then
            if not (InCombatLockdown and InCombatLockdown()) then
                ensureRaidStatusTextOverlay(frame, cfg)
            else
                -- During combat: only re-style existing overlays (no frame creation)
                local state = getState(frame)
                if state and state.statusTextOverlay then
                    styleRaidStatusTextOverlay(frame, cfg)
                end
            end
        end
    end

    -- Group layout: CompactRaidGroup1..8Member1..5
    for group = 1, 8 do
        for member = 1, 5 do
            local frame = _G["CompactRaidGroup" .. group .. "Member" .. member]
            if frame and frame.statusText then
                if not (InCombatLockdown and InCombatLockdown()) then
                    ensureRaidStatusTextOverlay(frame, cfg)
                else
                    local state = getState(frame)
                    if state and state.statusTextOverlay then
                        styleRaidStatusTextOverlay(frame, cfg)
                    end
                end
            end
        end
    end
end

function addon.RestoreRaidFrameStatusTextOverlays()
    for i = 1, 40 do
        local frame = _G["CompactRaidFrame" .. i]
        if frame then
            disableRaidStatusTextOverlay(frame)
        end
    end
    for group = 1, 8 do
        for member = 1, 5 do
            local frame = _G["CompactRaidGroup" .. group .. "Member" .. member]
            if frame then
                disableRaidStatusTextOverlay(frame)
            end
        end
    end
end

local function installRaidFrameStatusTextHooks()
    if addon._RaidFrameStatusTextHooksInstalled then return end
    addon._RaidFrameStatusTextHooksInstalled = true

    local function getCfg()
        local db = addon and addon.db and addon.db.profile
        local gf = db and rawget(db, "groupFrames") or nil
        local raidCfg = gf and rawget(gf, "raid") or nil
        return raidCfg and rawget(raidCfg, "textStatusText") or nil
    end

    if _G.hooksecurefunc and _G.CompactUnitFrame_UpdateAll then
        _G.hooksecurefunc("CompactUnitFrame_UpdateAll",
            Raid.makeCUFHandler("status", getCfg))
    end
    if _G.hooksecurefunc and _G.CompactUnitFrame_SetUnit then
        _G.hooksecurefunc("CompactUnitFrame_SetUnit",
            Raid.makeCUFHandler("status", getCfg, { requireUnit = true }))
    end
end

--------------------------------------------------------------------------------
-- Text Styling (Group Numbers / Group Titles)
--------------------------------------------------------------------------------
-- Applies the same 7 settings as Player Name to raid group title text.
-- Target: CompactRaidGroup1..8Title (Button, parentKey "title").
--------------------------------------------------------------------------------

-- Get the current raid group orientation from Edit Mode settings
-- Returns "horizontal" or "vertical"
local function getGroupOrientation()
    local EMSetting = _G.Enum and _G.Enum.EditModeUnitFrameSetting
    local RGD = _G.Enum and _G.Enum.RaidGroupDisplayType
    if not (EMSetting and RGD) then
        return "vertical" -- Default fallback
    end
    local raidFrame = addon.GetEditModeUnitFrame("Raid")
    if not raidFrame then return "vertical" end
    if not (addon and addon.EditMode and addon.EditMode.GetSetting) then
        return "vertical"
    end
    local displayType = addon.EditMode.GetSetting(raidFrame, EMSetting.RaidGroupDisplayType)
    if displayType == RGD.SeparateGroupsHorizontal or displayType == RGD.CombineGroupsHorizontal then
        return "horizontal"
    end
    return "vertical"
end

-- Apply number-only text and auto-centering to a group title
-- groupIndex: the group number (1-8)
local function applyNumberOnlyToGroupTitle(titleButton, groupIndex, cfg)
    if not titleButton or not titleButton.GetFontString then return end
    local fs = titleButton:GetFontString()
    if not fs then return end

    -- Set text to just the number
    if fs.SetText then
        pcall(fs.SetText, fs, tostring(groupIndex or ""))
    end

    -- Determine orientation and set auto-centering
    local orientation = getGroupOrientation()

    -- Apply centering based on orientation
    if orientation == "vertical" then
        -- Vertical layout: groups stacked vertically, title centered above each column
        if fs.SetJustifyH then
            pcall(fs.SetJustifyH, fs, "CENTER")
        end
        -- Position at TOP, centered horizontally
        local offsetX = cfg and cfg.offset and tonumber(cfg.offset.x) or 0
        local offsetY = cfg and cfg.offset and tonumber(cfg.offset.y) or 0
        fs:ClearAllPoints()
        fs:SetPoint("TOP", titleButton, "TOP", offsetX, offsetY)
    else
        -- Horizontal layout: groups laid out horizontally, title beside each row
        if fs.SetJustifyH then
            pcall(fs.SetJustifyH, fs, "LEFT")
        end
        -- Position at LEFT
        local offsetX = cfg and cfg.offset and tonumber(cfg.offset.x) or 0
        local offsetY = cfg and cfg.offset and tonumber(cfg.offset.y) or 0
        fs:ClearAllPoints()
        fs:SetPoint("LEFT", titleButton, "LEFT", offsetX, offsetY)
    end
end

local function applyTextToFontString_GroupTitle(fs, ownerFrame, cfg)
    if not fs or not ownerFrame or not cfg then return end

    local color = cfg.color or { 1, 1, 1, 1 }
    local anchor = cfg.anchor or "TOPLEFT"
    local offsetX = cfg.offset and tonumber(cfg.offset.x) or 0
    local offsetY = cfg.offset and tonumber(cfg.offset.y) or 0

    addon.ApplyTextFont(fs, cfg, gfTitleFontOpts)

    if fs.SetTextColor then
        pcall(fs.SetTextColor, fs, color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1)
    end
    if fs.SetJustifyH then
        pcall(fs.SetJustifyH, fs, Utils.getJustifyHFromAnchor(anchor))
    end

    local fsState = ensureState(fs)
    if fsState and not fsState.originalPointGroupTitle then
        local point, relativeTo, relativePoint, x, y = fs:GetPoint(1)
        if point then
            fsState.originalPointGroupTitle = { point, relativeTo, relativePoint, x or 0, y or 0 }
        end
    end

    local isDefaultAnchor = (anchor == "TOPLEFT")
    local isZeroOffset = (offsetX == 0 and offsetY == 0)

    if isDefaultAnchor and isZeroOffset and fsState and fsState.originalPointGroupTitle then
        local orig = fsState.originalPointGroupTitle
        fs:ClearAllPoints()
        fs:SetPoint(orig[1], orig[2], orig[3], orig[4], orig[5])
        if fs.SetJustifyH then
            pcall(fs.SetJustifyH, fs, "LEFT")
        end
    else
        fs:ClearAllPoints()
        fs:SetPoint(anchor, ownerFrame, anchor, offsetX, offsetY)
    end
end

local function applyGroupTitleToButton(titleButton, cfg, groupIndex)
    if not titleButton or not cfg then return end
    if not titleButton.GetFontString then return end
    local fs = titleButton:GetFontString()
    if not fs then return end

    -- Check if numbers-only mode is enabled
    local db = addon and addon.db and addon.db.profile
    local raidCfg = db and db.groupFrames and db.groupFrames.raid
    local numbersOnly = raidCfg and raidCfg.groupTitleNumbersOnly == true

    if numbersOnly and groupIndex then
        -- Apply font styling first (font face, size, style, color)
        applyTextToFontString_GroupTitle(fs, titleButton, cfg)
        -- Then apply number-only text and auto-centering (overrides anchor/position)
        applyNumberOnlyToGroupTitle(titleButton, groupIndex, cfg)
    else
        -- Standard styling with full "Group N" text
        applyTextToFontString_GroupTitle(fs, titleButton, cfg)
    end
end

function addon.ApplyRaidFrameGroupTitlesStyle()
    local db = addon and addon.db and addon.db.profile
    if not db then return end

    -- Zero-Touch: only apply if user has configured raid group title styling
    -- OR if numbers-only mode is enabled.
    local groupFrames = rawget(db, "groupFrames")
    local raidCfg = groupFrames and rawget(groupFrames, "raid") or nil
    local cfg = raidCfg and rawget(raidCfg, "textGroupNumbers") or nil
    local numbersOnly = raidCfg and raidCfg.groupTitleNumbersOnly == true

    -- If no text config and numbers-only is not enabled, skip (Zero-Touch)
    if not cfg and not numbersOnly then
        return
    end

    -- If text config exists, check if it has custom settings
    -- Numbers-only mode alone is enough to proceed
    if cfg and not Utils.hasCustomTextSettings(cfg) and not numbersOnly then
        return
    end

    if InCombatLockdown and InCombatLockdown() then
        Combat.queueRaidFrameReapply()
        return
    end

    -- Ensure cfg exists for applyGroupTitleToButton (use empty table as fallback)
    local effectiveCfg = cfg or {}

    for group = 1, 8 do
        local groupFrame = _G["CompactRaidGroup" .. group]
        local titleButton = (groupFrame and groupFrame.title) or _G["CompactRaidGroup" .. group .. "Title"]
        if titleButton then
            applyGroupTitleToButton(titleButton, effectiveCfg, group)
        end
    end
end

local function installRaidFrameGroupTitleHooks()
    if addon._RaidFrameGroupTitleHooksInstalled then return end
    addon._RaidFrameGroupTitleHooksInstalled = true

    local function tryApplyTitle(groupFrame, groupIndex)
        -- CRITICAL: Skip ALL processing when Edit Mode is active to avoid taint
        if isEditModeActive() then return end
        if not groupFrame or not Utils.isCompactRaidGroupFrame(groupFrame) then
            return
        end
        local titleButton = groupFrame.title or _G[groupFrame:GetName() .. "Title"]
        if not titleButton then return end

        local db = addon and addon.db and addon.db.profile
        local raidCfg = db and db.groupFrames and db.groupFrames.raid or nil
        local cfg = raidCfg and raidCfg.textGroupNumbers or nil
        local numbersOnly = raidCfg and raidCfg.groupTitleNumbersOnly == true

        -- Zero-Touch: skip if no text config and numbers-only is not enabled
        if not cfg and not numbersOnly then
            return
        end
        if cfg and not Utils.hasCustomTextSettings(cfg) and not numbersOnly then
            return
        end

        -- Extract group index from frame name if not provided
        local effectiveGroupIndex = groupIndex
        if not effectiveGroupIndex then
            local frameName = groupFrame:GetName()
            if frameName then
                effectiveGroupIndex = tonumber(frameName:match("CompactRaidGroup(%d+)"))
            end
        end

        local titleRef = titleButton
        local cfgRef = cfg or {}
        local groupIndexRef = effectiveGroupIndex
        if _G.C_Timer and _G.C_Timer.After then
            _G.C_Timer.After(0, function()
                if InCombatLockdown and InCombatLockdown() then
                    Combat.queueRaidFrameReapply()
                    return
                end
                applyGroupTitleToButton(titleRef, cfgRef, groupIndexRef)
            end)
        else
            if InCombatLockdown and InCombatLockdown() then
                Combat.queueRaidFrameReapply()
                return
            end
            applyGroupTitleToButton(titleRef, cfgRef, groupIndexRef)
        end
    end

    if _G.hooksecurefunc then
        if _G.CompactRaidGroup_UpdateLayout then
            _G.hooksecurefunc("CompactRaidGroup_UpdateLayout", function(groupFrame)
                -- Extract group index from frame
                local groupIndex = groupFrame and groupFrame.GetID and groupFrame:GetID()
                tryApplyTitle(groupFrame, groupIndex)
            end)
        end
        if _G.CompactRaidGroup_InitializeForGroup then
            _G.hooksecurefunc("CompactRaidGroup_InitializeForGroup", function(groupFrame, groupIndex)
                tryApplyTitle(groupFrame, groupIndex)
            end)
        end
        if _G.CompactRaidGroup_UpdateUnits then
            _G.hooksecurefunc("CompactRaidGroup_UpdateUnits", function(groupFrame)
                -- Extract group index from frame
                local groupIndex = groupFrame and groupFrame.GetID and groupFrame:GetID()
                tryApplyTitle(groupFrame, groupIndex)
            end)
        end
    end
end

--------------------------------------------------------------------------------
-- Text Hook Installation
--------------------------------------------------------------------------------

function RaidFrames.installTextHooks()
    installRaidFrameTextHooks()
    installRaidNameOverlayHooks()
    installRaidFrameStatusTextHooks()
    installRaidFrameGroupTitleHooks()
end

-- Install text hooks on load
RaidFrames.installTextHooks()
