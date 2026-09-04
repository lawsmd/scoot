-- visibility.lua - Per-unit opacity for combat, target, and out-of-combat states
local addonName, addon = ...
-- State opacity (core/opacity.lua): the combat slider floors at 50 and the
-- other two at 1; an unset value reads as the combat value.
local UF_OPACITY_OPTS = { combatMin = 50, min = 1, fallback = "combat" }

-- Hide-enforcement hooks (core/enforce.lua). Every hide in this file reads its
-- flag live from the profile, so each key carries a reader instead of a stored
-- flag; the direct apply and the saved-alpha restore stay with each apply
-- function. Show re-asserts at once, SetAlpha after a stack break.
local Enforce = addon.Enforce
local HIDE_METHODS = { "Show", "SetAlpha" }
local HIDE_TIMING = { Show = "sync", SetAlpha = "defer" }

-- Reads unitFrames[unitKey][sub][flag] (sub nil: unitFrames[unitKey][flag])
-- without touching AceDB defaults; nil while the profile is not there yet.
local function hideOpts(unitKey, sub, flag)
    local function reader()
        local db = addon and addon.db and addon.db.profile
        if not db then return nil end
        local unitFrames = rawget(db, "unitFrames")
        local cfg = unitFrames and rawget(unitFrames, unitKey) or nil
        if sub then cfg = cfg and rawget(cfg, sub) or nil end
        return cfg ~= nil and cfg[flag] == true
    end
    return { methods = HIDE_METHODS, timing = HIDE_TIMING, when = reader }
end

local function installHide(region, key, opts)
    if region then
        Enforce.Install(region, key, opts)
    end
end

-- Unit Frames: Overall visibility (opacity) per unit
do
    local getUnitFrameFor = addon.GetUnitFrame

    local function applyVisibilityForUnit(unit)
        if not addon:IsModuleEnabled("unitFrames", unit) then return end
        local frame = getUnitFrameFor(unit)
        if not frame or not frame.SetAlpha then return end

        local db = addon and addon.db and addon.db.profile
        if not db then return end

        -- Zero‑Touch: if this unit has no config table, do not touch the Blizzard frame.
        local unitFrames = rawget(db, "unitFrames")
        local cfg = unitFrames and rawget(unitFrames, unit) or nil
        if not cfg then
            return
        end

        -- Zero‑Touch: only apply opacity if the user explicitly configured any opacity key.
        local hasAnyOpacitySetting = (cfg.opacityInCombat ~= nil) or (cfg.opacityOutOfCombat ~= nil) or (cfg.opacityWithTarget ~= nil)
        if not hasAnyOpacitySetting then
            return
        end

        local alpha = addon.Opacity.Resolve(cfg, addon.Opacity.Keys.InCombat, UF_OPACITY_OPTS)
        pcall(frame.SetAlpha, frame, alpha)
    end

    function addon.ApplyUnitFrameVisibilityFor(unit)
        applyVisibilityForUnit(unit)
    end

    function addon.ApplyAllUnitFrameVisibility()
        applyVisibilityForUnit("Player")
        applyVisibilityForUnit("Target")
        applyVisibilityForUnit("Focus")
        applyVisibilityForUnit("Pet")
    end
end

-- (Reverted) No additional hooks for reapplying experimental sizing; rely on normal refresh

-- Target/Focus Misc.: Threat Meter visibility
-- Frame paths:
--   Target: TargetFrame.TargetFrameContent.TargetFrameContentContextual.NumericalThreat
--   Focus:  FocusFrame.TargetFrameContent.TargetFrameContentContextual.NumericalThreat
do
    local threatOpts = {}
    local _originalThreatMeterAlpha = { Target = nil, Focus = nil }

    local function getThreatMeterFrame(unit)
        local parentFrame = (unit == "Target") and _G.TargetFrame or (unit == "Focus") and _G.FocusFrame or nil
        if not parentFrame then return nil end
        local content = parentFrame.TargetFrameContent
        if not content then return nil end
        local contextual = content.TargetFrameContentContextual
        if not contextual then return nil end
        return contextual.NumericalThreat
    end

    local function applyThreatMeterVisibility(unit)
        if not addon:IsModuleEnabled("unitFrames", unit) then return end
        local threatFrame = getThreatMeterFrame(unit)
        if not threatFrame then return end

        local db = addon and addon.db and addon.db.profile
        if not db then return end

        -- Zero‑Touch: only operate if the user has a misc config table for this unit.
        local unitFrames = rawget(db, "unitFrames")
        local unitCfg = unitFrames and rawget(unitFrames, unit) or nil
        local miscCfg = unitCfg and rawget(unitCfg, "misc") or nil
        if not miscCfg then
            return
        end

        -- Zero‑Touch: nil means "don't touch"; only apply if explicitly set.
        if miscCfg.hideThreatMeter == nil then
            return
        end
        local hideThreatMeter = (miscCfg.hideThreatMeter == true)

        -- Capture original alpha on first run
        if _originalThreatMeterAlpha[unit] == nil then
            _originalThreatMeterAlpha[unit] = threatFrame:GetAlpha() or 1
        end

        if hideThreatMeter then
            -- Hide via SetAlpha(0) - safe for protected frames
            if threatFrame.SetAlpha then
                pcall(threatFrame.SetAlpha, threatFrame, 0)
            end
        else
            -- Restore original alpha
            if threatFrame.SetAlpha then
                pcall(threatFrame.SetAlpha, threatFrame, _originalThreatMeterAlpha[unit])
            end
        end
    end

    -- Install hooks to maintain visibility state when Blizzard updates the threat meter
    local function installThreatMeterHooks(unit)
        threatOpts[unit] = threatOpts[unit] or hideOpts(unit, "misc", "hideThreatMeter")
        installHide(getThreatMeterFrame(unit), "threatMeter", threatOpts[unit])
    end

    function addon.ApplyTargetThreatMeterVisibility()
        installThreatMeterHooks("Target")
        applyThreatMeterVisibility("Target")
    end

    function addon.ApplyFocusThreatMeterVisibility()
        installThreatMeterHooks("Focus")
        applyThreatMeterVisibility("Focus")
    end

    function addon.ApplyAllThreatMeterVisibility()
        addon.ApplyTargetThreatMeterVisibility()
        addon.ApplyFocusThreatMeterVisibility()
        if addon.ApplyBossThreatCounterVisibility then
            addon.ApplyBossThreatCounterVisibility()
        end
    end
end

-- Boss Misc.: Threat Counter visibility (all 5 boss frames)
-- Frame paths:
--   Boss1TargetFrame.TargetFrameContent.TargetFrameContentContextual.NumericalThreat
--   ...
--   Boss5TargetFrame.TargetFrameContent.TargetFrameContentContextual.NumericalThreat
do
    local BOSS_THREAT_OPTS = hideOpts("Boss", "misc", "hideBossThreatCounter")
    local _originalBossThreatAlpha = {}

    local function getBossThreatCounterFrame(index)
        local parentFrame = addon.GetBossFrame(index)
        if not parentFrame then return nil end
        local content = parentFrame.TargetFrameContent
        if not content then return nil end
        local contextual = content.TargetFrameContentContextual
        if not contextual then return nil end
        return contextual.NumericalThreat
    end

    local function applyBossThreatCounterVisibilityFor(index)
        if not addon:IsModuleEnabled("unitFrames", "Boss") then return end
        local threatFrame = getBossThreatCounterFrame(index)
        if not threatFrame then return end

        local db = addon and addon.db and addon.db.profile
        if not db then return end

        -- Zero‑Touch: only operate if the user has a misc config table for Boss.
        local unitFrames = rawget(db, "unitFrames")
        local bossCfg = unitFrames and rawget(unitFrames, "Boss") or nil
        local miscCfg = bossCfg and rawget(bossCfg, "misc") or nil
        if not miscCfg then
            return
        end

        -- Zero‑Touch: nil means "don't touch"; only apply if explicitly set.
        if miscCfg.hideBossThreatCounter == nil then
            return
        end
        local hideThreat = (miscCfg.hideBossThreatCounter == true)

        -- Capture original alpha on first run (per boss frame)
        if _originalBossThreatAlpha[index] == nil then
            _originalBossThreatAlpha[index] = threatFrame:GetAlpha() or 1
        end

        if hideThreat then
            if threatFrame.SetAlpha then
                pcall(threatFrame.SetAlpha, threatFrame, 0)
            end
        else
            if threatFrame.SetAlpha then
                pcall(threatFrame.SetAlpha, threatFrame, _originalBossThreatAlpha[index])
            end
        end
    end

    local function installBossThreatCounterHooksFor(index)
        installHide(getBossThreatCounterFrame(index), "bossThreatCounter", BOSS_THREAT_OPTS)
    end

    function addon.ApplyBossThreatCounterVisibility()
        for i = 1, 5 do
            installBossThreatCounterHooksFor(i)
            applyBossThreatCounterVisibilityFor(i)
        end
    end
end

-- Boss Misc.: High Level (Skull) Icon visibility (all 5 boss frames)
-- Frame paths:
--   Boss1TargetFrame.TargetFrameContent.TargetFrameContentContextual.HighLevelTexture
--   ...
--   Boss5TargetFrame.TargetFrameContent.TargetFrameContentContextual.HighLevelTexture
do
    local BOSS_HIGH_LEVEL_OPTS = hideOpts("Boss", "misc", "hideHighLevelIcon")
    local _originalBossHighLevelAlpha = {}

    local function getBossHighLevelIconFrame(index)
        local parentFrame = addon.GetBossFrame(index)
        if not parentFrame then return nil end
        local content = parentFrame.TargetFrameContent
        if not content then return nil end
        local contextual = content.TargetFrameContentContextual
        if not contextual then return nil end
        return contextual.HighLevelTexture
    end

    local function applyBossHighLevelIconVisibilityFor(index)
        if not addon:IsModuleEnabled("unitFrames", "Boss") then return end
        local iconFrame = getBossHighLevelIconFrame(index)
        if not iconFrame then return end

        local db = addon and addon.db and addon.db.profile
        if not db then return end

        local unitFrames = rawget(db, "unitFrames")
        local bossCfg = unitFrames and rawget(unitFrames, "Boss") or nil
        local miscCfg = bossCfg and rawget(bossCfg, "misc") or nil
        if not miscCfg then return end
        if miscCfg.hideHighLevelIcon == nil then return end
        local hideIcon = (miscCfg.hideHighLevelIcon == true)

        if _originalBossHighLevelAlpha[index] == nil then
            _originalBossHighLevelAlpha[index] = iconFrame:GetAlpha() or 1
        end

        if hideIcon then
            if iconFrame.SetAlpha then
                pcall(iconFrame.SetAlpha, iconFrame, 0)
            end
        else
            if iconFrame.SetAlpha then
                pcall(iconFrame.SetAlpha, iconFrame, _originalBossHighLevelAlpha[index])
            end
        end
    end

    local function installBossHighLevelIconHooksFor(index)
        installHide(getBossHighLevelIconFrame(index), "bossHighLevelIcon", BOSS_HIGH_LEVEL_OPTS)
    end

    function addon.ApplyBossHighLevelIconVisibility()
        for i = 1, 5 do
            installBossHighLevelIconHooksFor(i)
            applyBossHighLevelIconVisibilityFor(i)
        end
    end
end

-- Target Misc.: Boss Icon visibility
-- Frame path:
--   Target: TargetFrame.TargetFrameContent.TargetFrameContentContextual.BossIcon
do
    local BOSS_ICON_OPTS = hideOpts("Target", "misc", "hideBossIcon")
    local _originalBossIconAlpha = nil

    local function getBossIconFrame()
        local tf = _G.TargetFrame
        if not tf then return nil end
        local content = tf.TargetFrameContent
        if not content then return nil end
        local contextual = content.TargetFrameContentContextual
        if not contextual then return nil end
        return contextual.BossIcon
    end

    local function applyBossIconVisibility()
        if not addon:IsModuleEnabled("unitFrames", "Target") then return end
        local bossIconFrame = getBossIconFrame()
        if not bossIconFrame then return end

        local db = addon and addon.db and addon.db.profile
        if not db then return end

        local unitFrames = rawget(db, "unitFrames")
        local targetCfg = unitFrames and rawget(unitFrames, "Target") or nil
        local miscCfg = targetCfg and rawget(targetCfg, "misc") or nil
        if not miscCfg then
            return
        end
        if miscCfg.hideBossIcon == nil then
            return
        end
        local hideBossIcon = (miscCfg.hideBossIcon == true)

        -- Capture original alpha on first run
        if _originalBossIconAlpha == nil then
            _originalBossIconAlpha = bossIconFrame:GetAlpha() or 1
        end

        if hideBossIcon then
            -- Hide via SetAlpha(0) - safe for protected frames
            if bossIconFrame.SetAlpha then
                pcall(bossIconFrame.SetAlpha, bossIconFrame, 0)
            end
        else
            -- Restore original alpha
            if bossIconFrame.SetAlpha then
                pcall(bossIconFrame.SetAlpha, bossIconFrame, _originalBossIconAlpha)
            end
        end
    end

    local function installBossIconHooks()
        installHide(getBossIconFrame(), "targetBossIcon", BOSS_ICON_OPTS)
    end

    function addon.ApplyTargetBossIconVisibility()
        installBossIconHooks()
        applyBossIconVisibility()
    end
end

-- Player Misc.: Role Icon visibility
-- Frame path: PlayerFrame.PlayerFrameContent.PlayerFrameContentContextual.RoleIcon
do
    local ROLE_ICON_OPTS = hideOpts("Player", "misc", "hideRoleIcon")
    local _originalRoleIconAlpha = nil

    local function getRoleIconFrame()
        local pf = _G.PlayerFrame
        if not pf then return nil end
        local content = pf.PlayerFrameContent
        if not content then return nil end
        local contextual = content.PlayerFrameContentContextual
        if not contextual then return nil end
        return contextual.RoleIcon
    end

    local function applyRoleIconVisibility()
        if not addon:IsModuleEnabled("unitFrames", "Player") then return end
        local roleIconFrame = getRoleIconFrame()
        if not roleIconFrame then return end

        local db = addon and addon.db and addon.db.profile
        if not db then return end

        local unitFrames = rawget(db, "unitFrames")
        local playerCfg = unitFrames and rawget(unitFrames, "Player") or nil
        local miscCfg = playerCfg and rawget(playerCfg, "misc") or nil
        if not miscCfg then
            return
        end
        if miscCfg.hideRoleIcon == nil then
            return
        end
        local hideRoleIcon = (miscCfg.hideRoleIcon == true)

        -- Capture original alpha on first run
        if _originalRoleIconAlpha == nil then
            _originalRoleIconAlpha = roleIconFrame:GetAlpha() or 1
        end

        if hideRoleIcon then
            -- Hide via SetAlpha(0) - safe for protected frames
            if roleIconFrame.SetAlpha then
                pcall(roleIconFrame.SetAlpha, roleIconFrame, 0)
            end
        else
            -- Restore original alpha
            if roleIconFrame.SetAlpha then
                pcall(roleIconFrame.SetAlpha, roleIconFrame, _originalRoleIconAlpha)
            end
        end
    end

    -- Install hooks to maintain visibility state when Blizzard updates the role icon
    local function installRoleIconHooks()
        installHide(getRoleIconFrame(), "playerRoleIcon", ROLE_ICON_OPTS)
    end

    function addon.ApplyPlayerRoleIconVisibility()
        installRoleIconHooks()
        applyRoleIconVisibility()
    end
end

-- Player Misc.: Group Number visibility
-- Frame paths:
--   PlayerFrame.PlayerFrameContent.PlayerFrameContentContextual.GroupIndicator (container with texture child)
--   PlayerFrameGroupIndicatorText (global FontString)
do
    local GROUP_NUMBER_OPTS = hideOpts("Player", "misc", "hideGroupNumber")
    local _originalGroupIndicatorAlpha = nil
    local _originalGroupIndicatorTextAlpha = nil

    local function getGroupIndicatorFrame()
        local pf = _G.PlayerFrame
        if not pf then return nil end
        local content = pf.PlayerFrameContent
        if not content then return nil end
        local contextual = content.PlayerFrameContentContextual
        if not contextual then return nil end
        return contextual.GroupIndicator
    end

    local function getGroupIndicatorTextFrame()
        return _G.PlayerFrameGroupIndicatorText
    end

    local function applyGroupNumberVisibility()
        if not addon:IsModuleEnabled("unitFrames", "Player") then return end
        local groupIndicatorFrame = getGroupIndicatorFrame()
        local groupIndicatorText = getGroupIndicatorTextFrame()

        local db = addon and addon.db and addon.db.profile
        if not db then return end

        local unitFrames = rawget(db, "unitFrames")
        local playerCfg = unitFrames and rawget(unitFrames, "Player") or nil
        local miscCfg = playerCfg and rawget(playerCfg, "misc") or nil
        if not miscCfg then
            return
        end
        if miscCfg.hideGroupNumber == nil then
            return
        end
        local hideGroupNumber = (miscCfg.hideGroupNumber == true)

        -- Apply to GroupIndicator container frame
        if groupIndicatorFrame then
            -- Capture original alpha on first run
            if _originalGroupIndicatorAlpha == nil then
                _originalGroupIndicatorAlpha = groupIndicatorFrame:GetAlpha() or 1
            end

            if hideGroupNumber then
                if groupIndicatorFrame.SetAlpha then
                    pcall(groupIndicatorFrame.SetAlpha, groupIndicatorFrame, 0)
                end
            else
                if groupIndicatorFrame.SetAlpha then
                    pcall(groupIndicatorFrame.SetAlpha, groupIndicatorFrame, _originalGroupIndicatorAlpha)
                end
            end
        end

        -- Apply to GroupIndicator text (global FontString)
        if groupIndicatorText then
            -- Capture original alpha on first run
            if _originalGroupIndicatorTextAlpha == nil then
                _originalGroupIndicatorTextAlpha = groupIndicatorText:GetAlpha() or 1
            end

            if hideGroupNumber then
                if groupIndicatorText.SetAlpha then
                    pcall(groupIndicatorText.SetAlpha, groupIndicatorText, 0)
                end
            else
                if groupIndicatorText.SetAlpha then
                    pcall(groupIndicatorText.SetAlpha, groupIndicatorText, _originalGroupIndicatorTextAlpha)
                end
            end
        end
    end

    -- Install hooks to maintain visibility state when Blizzard updates the group indicator
    local function installGroupNumberHooks()
        installHide(getGroupIndicatorFrame(), "playerGroupNumber", GROUP_NUMBER_OPTS)
        installHide(getGroupIndicatorTextFrame(), "playerGroupNumber", GROUP_NUMBER_OPTS)
    end

    function addon.ApplyPlayerGroupNumberVisibility()
        installGroupNumberHooks()
        applyGroupNumberVisibility()
    end
end

-- Player Misc.: Hide PvP Icons (PrestigeBadge + PrestigePortrait)
-- Frame paths:
--   PlayerFrame.PlayerFrameContent.PlayerFrameContentContextual.PrestigeBadge
--   PlayerFrame.PlayerFrameContent.PlayerFrameContentContextual.PrestigePortrait
do
    local PVP_ICON_OPTS = hideOpts("Player", "misc", "hidePvPIcons")
    local _originalPrestigeBadgeAlpha = nil
    local _originalPrestigePortraitAlpha = nil

    local function getPrestigeBadge()
        local pf = _G.PlayerFrame
        if not pf then return nil end
        local content = pf.PlayerFrameContent
        if not content then return nil end
        local contextual = content.PlayerFrameContentContextual
        if not contextual then return nil end
        return contextual.PrestigeBadge
    end

    local function getPrestigePortrait()
        local pf = _G.PlayerFrame
        if not pf then return nil end
        local content = pf.PlayerFrameContent
        if not content then return nil end
        local contextual = content.PlayerFrameContentContextual
        if not contextual then return nil end
        return contextual.PrestigePortrait
    end

    local function applyPvPIconVisibility()
        if not addon:IsModuleEnabled("unitFrames", "Player") then return end
        local prestigeBadge = getPrestigeBadge()
        local prestigePortrait = getPrestigePortrait()

        local db = addon and addon.db and addon.db.profile
        if not db then return end

        local unitFrames = rawget(db, "unitFrames")
        local playerCfg = unitFrames and rawget(unitFrames, "Player") or nil
        local miscCfg = playerCfg and rawget(playerCfg, "misc") or nil
        if not miscCfg then
            return
        end
        if miscCfg.hidePvPIcons == nil then
            return
        end
        local hidePvPIcons = (miscCfg.hidePvPIcons == true)

        -- Apply to PrestigeBadge
        if prestigeBadge then
            if _originalPrestigeBadgeAlpha == nil then
                _originalPrestigeBadgeAlpha = prestigeBadge:GetAlpha() or 1
            end

            if hidePvPIcons then
                if prestigeBadge.SetAlpha then
                    pcall(prestigeBadge.SetAlpha, prestigeBadge, 0)
                end
            else
                if prestigeBadge.SetAlpha then
                    pcall(prestigeBadge.SetAlpha, prestigeBadge, _originalPrestigeBadgeAlpha)
                end
            end
        end

        -- Apply to PrestigePortrait
        if prestigePortrait then
            if _originalPrestigePortraitAlpha == nil then
                _originalPrestigePortraitAlpha = prestigePortrait:GetAlpha() or 1
            end

            if hidePvPIcons then
                if prestigePortrait.SetAlpha then
                    pcall(prestigePortrait.SetAlpha, prestigePortrait, 0)
                end
            else
                if prestigePortrait.SetAlpha then
                    pcall(prestigePortrait.SetAlpha, prestigePortrait, _originalPrestigePortraitAlpha)
                end
            end
        end
    end

    local function installPvPIconHooks()
        installHide(getPrestigeBadge(), "playerPvPIcons", PVP_ICON_OPTS)
        installHide(getPrestigePortrait(), "playerPvPIcons", PVP_ICON_OPTS)
    end

    function addon.ApplyPlayerPvPIconVisibility()
        installPvPIconHooks()
        applyPvPIconVisibility()
    end
end

-- Apply all Player Misc. visibility settings
function addon.ApplyAllPlayerMiscVisibility()
    if addon.ApplyPlayerRoleIconVisibility then
        addon.ApplyPlayerRoleIconVisibility()
    end
    if addon.ApplyPlayerGroupNumberVisibility then
        addon.ApplyPlayerGroupNumberVisibility()
    end
    if addon.ApplyPlayerPvPIconVisibility then
        addon.ApplyPlayerPvPIconVisibility()
    end
end

-- Pet Misc.: Hide Entire Pet Frame
-- Useful for ConsolePort users who use the Pet Ring instead of the Pet frame
-- Frame path: PetFrame (global)
do
    local PET_FRAME_OPTS = hideOpts("Pet", nil, "hideEntireFrame")
    local _originalPetFrameAlpha = nil

    local function getPetFrame()
        return addon.GetUnitFrame("Pet")
    end

    local function applyPetFrameHiddenState()
        if not addon:IsModuleEnabled("unitFrames", "Pet") then return end
        local petFrame = getPetFrame()
        if not petFrame then return end

        local db = addon and addon.db and addon.db.profile
        if not db then return end

        -- Zero‑Touch: only operate if the user has a config table for Pet.
        local unitFrames = rawget(db, "unitFrames")
        local petCfg = unitFrames and rawget(unitFrames, "Pet") or nil
        if not petCfg then
            return
        end

        -- Zero‑Touch: nil means "don't touch"; only apply if explicitly set.
        if petCfg.hideEntireFrame == nil then
            return
        end
        local hideEntireFrame = (petCfg.hideEntireFrame == true)

        -- Capture original alpha on first run
        if _originalPetFrameAlpha == nil then
            _originalPetFrameAlpha = petFrame:GetAlpha() or 1
        end

        if hideEntireFrame then
            -- Hide via SetAlpha(0) - safe for protected frames
            if petFrame.SetAlpha then
                pcall(petFrame.SetAlpha, petFrame, 0)
            end
        else
            -- Restore original alpha (other visibility settings will re-apply their values)
            if petFrame.SetAlpha then
                pcall(petFrame.SetAlpha, petFrame, _originalPetFrameAlpha)
            end
            -- Re-apply opacity settings if they exist
            addon.ApplyUnitFrameVisibilityFor("Pet")
        end
    end

    -- Install hooks to maintain hidden state when Blizzard updates the Pet frame
    local function installPetFrameHooks()
        installHide(getPetFrame(), "petEntireFrame", PET_FRAME_OPTS)
    end

    function addon.ApplyPetFrameVisibility()
        installPetFrameHooks()
        applyPetFrameHiddenState()
    end
end

function addon:SyncAllEditModeSettings()
    local anyChanged = false
    for id, component in pairs(self.Components) do
        if component.SyncEditModeSettings then
            if component:SyncEditModeSettings() then
                anyChanged = true
            end
        end
        if addon.EditMode.SyncComponentPositionFromEditMode then
            if addon.EditMode.SyncComponentPositionFromEditMode(component) then
                anyChanged = true
            end
        end
    end

    return anyChanged
end
