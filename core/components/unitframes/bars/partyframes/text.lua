--------------------------------------------------------------------------------
-- bars/partyframes/text.lua
-- Party frame text styling: legacy text, name overlays, party title styling,
-- and text hook installation.
--
-- Loaded after partyframes/core.lua. Imports shared state from
-- addon.BarsPartyFrames.
--------------------------------------------------------------------------------

local addonName, addon = ...

-- Scratch opts for ResolveColorRGBA (name overlay text; no barKind)
local gfTextColorOpts = {}

-- Font-half opts for the party title text
local gfTitleFontOpts = { size = 12 }

-- Get modules
local Utils = addon.BarsUtils
local Combat = addon.BarsCombat
local SS = addon.SecretSafe

-- Get module namespace (created in core.lua)
local PartyFrames = addon.BarsPartyFrames

-- Import shared state from core.lua
local PartyFrameState = addon.BarsPartyFrames._PartyFrameState
local getState = addon.BarsPartyFrames._getState
local ensureState = addon.BarsPartyFrames._ensureState
local isEditModeActive = addon.BarsPartyFrames._isEditModeActive

--------------------------------------------------------------------------------
-- Overlay family binding
--------------------------------------------------------------------------------
-- The shared factory (bars/textoverlay.lua) owns the ensure/style/disable
-- machinery for the name and status overlays; this file keeps the public
-- entry points, DB gating, and hook installation. Screening and combat-bail
-- behavior are declared per hook at the install sites below.
local Party = addon.BarsTextOverlay.NewFamily({
    getState = getState,
    ensureState = ensureState,
    isEditModeActive = isEditModeActive,
    isTarget = Utils.isPartyFrame,
    screenFrame = SS.plainFrame,
    queueReapply = function() Combat.queuePartyFrameReapply() end,
    statusDefaultAnchor = "CENTER",
    colorScratch = gfTextColorOpts,
})

local stylePartyNameOverlay = Party.styleNameOverlay
local ensurePartyNameOverlay = Party.ensureNameOverlay
local disablePartyNameOverlay = Party.disableNameOverlay
local stylePartyStatusTextOverlay = Party.styleStatusOverlay
local ensurePartyStatusTextOverlay = Party.ensureStatusOverlay
local disablePartyStatusTextOverlay = Party.disableStatusOverlay

--------------------------------------------------------------------------------
-- Text Styling (Player Name)
--------------------------------------------------------------------------------
-- Applies font settings to party frame name text elements.
-- Target: CompactPartyFrameMember[1-5].name (FontString with parentKey="name")
--------------------------------------------------------------------------------

function addon.ApplyPartyFrameTextStyle()
    local db = addon and addon.db and addon.db.profile
    if not db then return end

    local groupFrames = rawget(db, "groupFrames")
    local partyCfg = groupFrames and rawget(groupFrames, "party") or nil
    local cfg = partyCfg and rawget(partyCfg, "textPlayerName") or nil
    if not cfg then
        return
    end

    if not Utils.hasCustomTextSettings(cfg) then
        return
    end

    -- Name styling delegates to overlay FontStrings (avoids touching Blizzard's frame.name).
    if addon.ApplyPartyFrameNameOverlays then
        addon.ApplyPartyFrameNameOverlays()
    end
end

local function installPartyFrameTextHooks()
    if addon._PartyFrameTextHooksInstalled then return end
    addon._PartyFrameTextHooksInstalled = true

    -- Name hooks are installed by the overlay system (installPartyNameOverlayHooks).
end

--------------------------------------------------------------------------------
-- Text Overlay (Name Text - Combat-Safe Persistence)
--------------------------------------------------------------------------------
-- Creates addon-owned FontString overlays on party frames that visually replace
-- Blizzard's name text. These overlays can be styled during initial setup and
-- their text content can be updated during combat without taint because only
-- addon-owned FontStrings are manipulated.
--
-- Pattern: Mirror text via SetText hook, style on setup, hide Blizzard's element.
--------------------------------------------------------------------------------

-- Apply overlays to all party frames
function addon.ApplyPartyFrameNameOverlays()
    local db = addon and addon.db and addon.db.profile
    if not db then return end

    local groupFrames = rawget(db, "groupFrames")
    local partyCfg = groupFrames and rawget(groupFrames, "party") or nil

    -- Zero-Touch: if no party config exists, don't touch party frames at all
    if not partyCfg then return end

    local cfg = rawget(partyCfg, "textPlayerName") or nil
    local hasCustom = Utils.hasCustomTextSettings(cfg)

    -- If no custom settings, skip - let RestorePartyFrameNameOverlays handle cleanup
    if not hasCustom then return end

    for i = 1, 5 do
        local frame = _G["CompactPartyFrameMember" .. i]
        if frame then
            -- Only create overlays out of combat (initial setup)
            local state = getState(frame)
            if not (InCombatLockdown and InCombatLockdown()) then
                ensurePartyNameOverlay(frame, cfg)
            elseif state and state.nameOverlayText then
                -- Already have overlay, just update styling (safe during combat for addon-owned FontString)
                stylePartyNameOverlay(frame, cfg)
            end
        end
    end
end

-- Restore all party frames to stock appearance
function addon.RestorePartyFrameNameOverlays()
    for i = 1, 5 do
        local frame = _G["CompactPartyFrameMember" .. i]
        if frame then
            disablePartyNameOverlay(frame)
        end
    end
end

-- Install hooks that trigger overlay setup/updates via CompactUnitFrame events
local function installPartyNameOverlayHooks()
    if addon._PartyNameOverlayHooksInstalled then return end
    addon._PartyNameOverlayHooksInstalled = true

    local function getCfg()
        local db = addon and addon.db and addon.db.profile
        local partyCfg = db and db.groupFrames and db.groupFrames.party or nil
        return partyCfg and partyCfg.textPlayerName or nil
    end

    -- ifNoOverlay: an existing overlay restyles mid-combat (the Apply-loop
    -- philosophy); overlay creation waits for the queued post-combat reapply
    if _G.hooksecurefunc and _G.CompactUnitFrame_UpdateAll then
        _G.hooksecurefunc("CompactUnitFrame_UpdateAll",
            Party.makeCUFHandler("name", getCfg, { screen = true, combatBail = "ifNoOverlay" }))
    end
    if _G.hooksecurefunc and _G.CompactUnitFrame_SetUnit then
        _G.hooksecurefunc("CompactUnitFrame_SetUnit",
            Party.makeCUFHandler("name", getCfg, { requireUnit = true, screen = true, combatBail = "ifNoOverlay" }))
    end
    if _G.hooksecurefunc and _G.CompactUnitFrame_UpdateName then
        _G.hooksecurefunc("CompactUnitFrame_UpdateName",
            Party.makeCUFHandler("name", getCfg, { screen = true, combatBail = "ifNoOverlay" }))
    end

    -- Event-driven re-application for party composition changes.
    -- When entering a Follower Dungeon (or any party change), unit class data
    -- may not be ready when CompactUnitFrame hooks first fire.
    -- GROUP_ROSTER_UPDATE provides a reliable secondary trigger.
    if not addon._PartyNameRosterEventInstalled then
        addon._PartyNameRosterEventInstalled = true
        addon.Events.On("UnitFrames:PartyText", "GROUP_ROSTER_UPDATE", function()
            if isEditModeActive() then return end

            local db = addon and addon.db and addon.db.profile
            local partyCfg = db and db.groupFrames and db.groupFrames.party or nil
            local cfg = partyCfg and partyCfg.textPlayerName or nil
            if not cfg or (cfg.colorMode or "default") ~= "class" then return end
            if not Utils.hasCustomTextSettings(cfg) then return end

            if _G.C_Timer and _G.C_Timer.After then
                _G.C_Timer.After(0.5, function()
                    if isEditModeActive() then return end
                    if InCombatLockdown and InCombatLockdown() then
                        Combat.queuePartyFrameReapply()
                        return
                    end
                    -- Clear fingerprints to force full re-style after roster change
                    for i = 1, 5 do
                        local f = _G["CompactPartyFrameMember" .. i]
                        if f then
                            local s = getState(f)
                            if s then s.lastNameFingerprint = nil end
                        end
                    end
                    if addon.ApplyPartyFrameNameOverlays then
                        addon.ApplyPartyFrameNameOverlays()
                    end
                end)
            end
        end)
    end
end

--------------------------------------------------------------------------------
-- Text Styling (Party Title)
--------------------------------------------------------------------------------
-- Applies the same 7 settings as Party Frames > Text > Player Name to the party frame title text.
-- Target: CompactPartyFrame.title (Button from CompactRaidGroupTemplate: "$parentTitle", parentKey="title").
--------------------------------------------------------------------------------

local function applyTextToFontString_PartyTitle(fs, ownerFrame, cfg)
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
    if fsState and not fsState.originalPointPartyTitle then
        local point, relativeTo, relativePoint, x, y = fs:GetPoint(1)
        if point then
            fsState.originalPointPartyTitle = { point, relativeTo, relativePoint, x or 0, y or 0 }
        end
    end

    local isDefaultAnchor = (anchor == "TOPLEFT")
    local isZeroOffset = (offsetX == 0 and offsetY == 0)

    if isDefaultAnchor and isZeroOffset and fsState and fsState.originalPointPartyTitle then
        local orig = fsState.originalPointPartyTitle
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

local function applyPartyTitle(titleButton, cfg)
    if not titleButton or not cfg then return end
    if not titleButton.GetFontString then return end
    local fs = titleButton:GetFontString()
    if not fs then return end
    if cfg.hide == true then
        -- Hide always wins; styling is irrelevant while hidden.
        -- The hide logic is handled by hideBlizzardPartyTitleText below.
        return
    end
    applyTextToFontString_PartyTitle(fs, titleButton, cfg)
end

-- Hide Blizzard's party title FontString and install alpha-enforcement hook
local function hideBlizzardPartyTitleText(titleButton)
    if not titleButton or not titleButton.GetFontString then return end
    local fs = titleButton:GetFontString()
    if not fs then return end
    addon.BarsTextOverlay.enforceHidden(fs, getState, ensureState)
end

-- Show Blizzard's party title FontString (for restore/cleanup)
local function showBlizzardPartyTitleText(titleButton)
    if not titleButton or not titleButton.GetFontString then return end
    local fs = titleButton:GetFontString()
    if not fs then return end
    addon.BarsTextOverlay.releaseHidden(fs, getState)
end

function addon.ApplyPartyFrameTitleStyle()
    local db = addon and addon.db and addon.db.profile
    if not db then return end

    local groupFrames = rawget(db, "groupFrames")
    local partyCfg = groupFrames and rawget(groupFrames, "party") or nil
    local cfg = partyCfg and rawget(partyCfg, "textPartyTitle") or nil
    if not cfg then
        return
    end

    -- If the user has asked to hide it, do that even if other style settings are default.
    if cfg.hide ~= true and not Utils.hasCustomTextSettings(cfg) then
        return
    end

    if InCombatLockdown and InCombatLockdown() then
        Combat.queuePartyFrameReapply()
        return
    end

    local partyFrame = _G.CompactPartyFrame
    local titleButton = partyFrame and partyFrame.title or _G.CompactPartyFrameTitle
    if titleButton then
        if cfg.hide == true then
            hideBlizzardPartyTitleText(titleButton)
        else
            showBlizzardPartyTitleText(titleButton)
            applyPartyTitle(titleButton, cfg)
        end
    end
end

local function installPartyTitleHooks()
    if addon._PartyFrameTitleHooksInstalled then return end
    addon._PartyFrameTitleHooksInstalled = true

    local function tryApply(groupFrame)
        if not groupFrame or not Utils.isCompactPartyFrame(groupFrame) then
            return
        end
        local db = addon and addon.db and addon.db.profile
        local cfg = db and db.groupFrames and db.groupFrames.party and db.groupFrames.party.textPartyTitle or nil
        if not cfg then
            return
        end
        if cfg.hide ~= true and not Utils.hasCustomTextSettings(cfg) then
            return
        end

        local titleButton = groupFrame.title or _G[groupFrame:GetName() .. "Title"]
        if not titleButton then return end

        local titleRef = titleButton
        local cfgRef = cfg
        if _G.C_Timer and _G.C_Timer.After then
            _G.C_Timer.After(0, function()
                if InCombatLockdown and InCombatLockdown() then
                    Combat.queuePartyFrameReapply()
                    return
                end
                if cfgRef.hide == true then
                    hideBlizzardPartyTitleText(titleRef)
                else
                    showBlizzardPartyTitleText(titleRef)
                    applyPartyTitle(titleRef, cfgRef)
                end
            end)
        else
            if InCombatLockdown and InCombatLockdown() then
                Combat.queuePartyFrameReapply()
                return
            end
            if cfgRef.hide == true then
                hideBlizzardPartyTitleText(titleRef)
            else
                showBlizzardPartyTitleText(titleRef)
                applyPartyTitle(titleRef, cfgRef)
            end
        end
    end

    if _G.hooksecurefunc then
        if _G.CompactRaidGroup_UpdateLayout then
            _G.hooksecurefunc("CompactRaidGroup_UpdateLayout", tryApply)
        end
        if _G.CompactRaidGroup_UpdateUnits then
            _G.hooksecurefunc("CompactRaidGroup_UpdateUnits", tryApply)
        end
        if _G.CompactRaidGroup_UpdateBorder then
            _G.hooksecurefunc("CompactRaidGroup_UpdateBorder", tryApply)
        end
    end
end

--------------------------------------------------------------------------------
-- Text Overlay (Status Text - Combat-Safe Persistence)
--------------------------------------------------------------------------------
-- Creates addon-owned FontString overlays on party frames that visually replace
-- Blizzard's statusText. These overlays persist during combat because only
-- addon-owned FontStrings are manipulated. Blizzard can reset its own
-- statusText all it wants; the Scoot overlay stays styled.
--
-- Pattern: Mirror text via SetText/SetFormattedText hooks, style on setup,
-- hide Blizzard's element via SetAlpha(0).
--------------------------------------------------------------------------------

function addon.ApplyPartyFrameStatusTextStyle()
    local db = addon and addon.db and addon.db.profile
    if not db then return end

    local groupFrames = rawget(db, "groupFrames")
    local partyCfg = groupFrames and rawget(groupFrames, "party") or nil
    local cfg = partyCfg and rawget(partyCfg, "textStatusText") or nil
    if not cfg then
        return
    end

    if not Utils.hasCustomTextSettings(cfg) then
        return
    end

    for i = 1, 5 do
        local frame = _G["CompactPartyFrameMember" .. i]
        if frame and frame.statusText then
            if not (InCombatLockdown and InCombatLockdown()) then
                ensurePartyStatusTextOverlay(frame, cfg)
            else
                -- During combat: only re-style existing overlays (no frame creation)
                local state = getState(frame)
                if state and state.statusTextOverlay then
                    stylePartyStatusTextOverlay(frame, cfg)
                end
            end
        end
    end
end

function addon.RestorePartyFrameStatusTextOverlays()
    for i = 1, 5 do
        local frame = _G["CompactPartyFrameMember" .. i]
        if frame then
            disablePartyStatusTextOverlay(frame)
        end
    end
end

local function installPartyStatusTextHooks()
    if addon._PartyStatusTextHooksInstalled then return end
    addon._PartyStatusTextHooksInstalled = true

    local function getCfg()
        local db = addon and addon.db and addon.db.profile
        local gf = db and rawget(db, "groupFrames") or nil
        local partyCfg = gf and rawget(gf, "party") or nil
        return partyCfg and rawget(partyCfg, "textStatusText") or nil
    end

    if _G.hooksecurefunc and _G.CompactUnitFrame_UpdateAll then
        _G.hooksecurefunc("CompactUnitFrame_UpdateAll",
            Party.makeCUFHandler("status", getCfg, { screen = true }))
    end
    if _G.hooksecurefunc and _G.CompactUnitFrame_SetUnit then
        _G.hooksecurefunc("CompactUnitFrame_SetUnit",
            Party.makeCUFHandler("status", getCfg, { requireUnit = true, screen = true }))
    end
end

--------------------------------------------------------------------------------
-- Text Hook Installation
--------------------------------------------------------------------------------

function PartyFrames.installTextHooks()
    installPartyFrameTextHooks()
    installPartyNameOverlayHooks()
    installPartyStatusTextHooks()
    installPartyTitleHooks()
end

-- Install text hooks on load
PartyFrames.installTextHooks()
