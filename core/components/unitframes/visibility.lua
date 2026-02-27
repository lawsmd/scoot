local addonName, addon = ...
local Util = addon.ComponentsUtil
local ClampOpacity = Util.ClampOpacity
local PlayerInCombat = Util.PlayerInCombat

-- Reference to FrameState module for safe property storage (avoids writing to Blizzard frames)
local FS = nil
local function ensureFS()
    if not FS then FS = addon.FrameState end
    return FS
end

local function getState(frame)
    local fs = ensureFS()
    return fs and fs.Get(frame) or nil
end

local function getProp(frame, key)
    local st = getState(frame)
    return st and st[key] or nil
end

local function setProp(frame, key, value)
    local st = getState(frame)
    if st then
        st[key] = value
    end
end

-- Unit Frames: Overall visibility (opacity) per unit
do
    local function getUnitFrameFor(unit)
        local mgr = _G.EditModeManagerFrame
        local EM = _G.Enum and _G.Enum.EditModeUnitFrameSystemIndices
        local EMSys = _G.Enum and _G.Enum.EditModeSystem
        if not (mgr and EMSys and mgr.GetRegisteredSystemFrame) then
            -- Fallback for environments where Edit Mode indices aren't available
            if unit == "Pet" then return _G.PetFrame end
            return nil
        end
        local idx = nil
        if EM then
            idx = (unit == "Player" and EM.Player)
                or (unit == "Target" and EM.Target)
                or (unit == "Focus" and EM.Focus)
                or (unit == "Pet" and EM.Pet)
        end
        if idx then
            return mgr:GetRegisteredSystemFrame(EMSys.UnitFrame, idx)
        end
        -- If no index was resolved (older builds lacking EM.Pet), try known globals
        if unit == "Pet" then return _G.PetFrame end
    end

    local function applyVisibilityForUnit(unit)
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

        -- Base opacity (combat) uses the same 50–100 semantics as Cooldown Manager groups
        local baseRaw = cfg.opacityInCombat
        if baseRaw == nil then baseRaw = 100 end
        local baseOpacity = ClampOpacity(baseRaw, 50)

        -- Out-of-combat opacity; falls back to base when unset
        local oocRaw = cfg.opacityOutOfCombat
        local oocOpacity = ClampOpacity(oocRaw == nil and baseOpacity or oocRaw, 1)

        -- With-target opacity; falls back to base when unset
        local tgtRaw = cfg.opacityWithTarget
        local tgtOpacity = ClampOpacity(tgtRaw == nil and baseOpacity or tgtRaw, 1)

        local hasTarget = (UnitExists and UnitExists("target")) and true or false
        local applied = hasTarget and tgtOpacity or (PlayerInCombat() and baseOpacity or oocOpacity)

        pcall(frame.SetAlpha, frame, applied / 100)
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
    local _threatMeterHooked = { Target = false, Focus = false }
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
        if _threatMeterHooked[unit] then return end
        _threatMeterHooked[unit] = true

        local threatFrame = getThreatMeterFrame(unit)
        if not threatFrame then return end

        -- Hook Show() to re-apply visibility when Blizzard shows the frame
        if threatFrame.Show then
            hooksecurefunc(threatFrame, "Show", function(self)
                local db = addon and addon.db and addon.db.profile
                if not db then return end

                local unitFrames = rawget(db, "unitFrames")
                local unitCfg = unitFrames and rawget(unitFrames, unit) or nil
                local miscCfg = unitCfg and rawget(unitCfg, "misc") or nil
                if miscCfg and miscCfg.hideThreatMeter == true then
                    if self.SetAlpha then
                        pcall(self.SetAlpha, self, 0)
                    end
                end
            end)
        end

        -- Hook SetAlpha() to re-enforce alpha=0 when Blizzard tries to change it
        if threatFrame.SetAlpha then
            hooksecurefunc(threatFrame, "SetAlpha", function(self, alpha)
                local db = addon and addon.db and addon.db.profile
                if not db then return end

                local unitFrames = rawget(db, "unitFrames")
                local unitCfg = unitFrames and rawget(unitFrames, unit) or nil
                local miscCfg = unitCfg and rawget(unitCfg, "misc") or nil
                if miscCfg and miscCfg.hideThreatMeter == true and alpha and alpha > 0 then
                    -- Defer to avoid recursion
                    if not getProp(self, "threatAlphaDeferred") then
                        setProp(self, "threatAlphaDeferred", true)
                        C_Timer.After(0, function()
                            setProp(self, "threatAlphaDeferred", nil)
                            if miscCfg and miscCfg.hideThreatMeter == true and self.SetAlpha then
                                pcall(self.SetAlpha, self, 0)
                            end
                        end)
                    end
                end
            end)
        end
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
    local _bossThreatHooked = {}
    local _originalBossThreatAlpha = {}

    local function getBossThreatCounterFrame(index)
        local parentFrame = _G["Boss" .. tostring(index) .. "TargetFrame"]
        if not parentFrame then return nil end
        local content = parentFrame.TargetFrameContent
        if not content then return nil end
        local contextual = content.TargetFrameContentContextual
        if not contextual then return nil end
        return contextual.NumericalThreat
    end

    local function applyBossThreatCounterVisibilityFor(index)
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
        if _bossThreatHooked[index] then return end
        _bossThreatHooked[index] = true

        local threatFrame = getBossThreatCounterFrame(index)
        if not threatFrame then return end

        if threatFrame.Show then
            hooksecurefunc(threatFrame, "Show", function(self)
                local db = addon and addon.db and addon.db.profile
                if not db then return end

                local unitFrames = rawget(db, "unitFrames")
                local bossCfg = unitFrames and rawget(unitFrames, "Boss") or nil
                local miscCfg = bossCfg and rawget(bossCfg, "misc") or nil
                if miscCfg and miscCfg.hideBossThreatCounter == true then
                    if self.SetAlpha then
                        pcall(self.SetAlpha, self, 0)
                    end
                end
            end)
        end

        if threatFrame.SetAlpha then
            hooksecurefunc(threatFrame, "SetAlpha", function(self, alpha)
                local db = addon and addon.db and addon.db.profile
                if not db then return end

                local unitFrames = rawget(db, "unitFrames")
                local bossCfg = unitFrames and rawget(unitFrames, "Boss") or nil
                local miscCfg = bossCfg and rawget(bossCfg, "misc") or nil
                if miscCfg and miscCfg.hideBossThreatCounter == true and alpha and alpha > 0 then
                    if not getProp(self, "bossThreatAlphaDeferred") then
                        setProp(self, "bossThreatAlphaDeferred", true)
                        C_Timer.After(0, function()
                            setProp(self, "bossThreatAlphaDeferred", nil)
                            if miscCfg and miscCfg.hideBossThreatCounter == true and self.SetAlpha then
                                pcall(self.SetAlpha, self, 0)
                            end
                        end)
                    end
                end
            end)
        end
    end

    function addon.ApplyBossThreatCounterVisibility()
        for i = 1, 5 do
            installBossThreatCounterHooksFor(i)
            applyBossThreatCounterVisibilityFor(i)
        end
    end
end

-- Target Misc.: Boss Icon visibility
-- Frame path:
--   Target: TargetFrame.TargetFrameContent.TargetFrameContentContextual.BossIcon
do
    local _bossIconHooked = false
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
        if _bossIconHooked then return end
        _bossIconHooked = true

        local bossIconFrame = getBossIconFrame()
        if not bossIconFrame then return end

        if bossIconFrame.Show then
            hooksecurefunc(bossIconFrame, "Show", function(self)
                local db = addon and addon.db and addon.db.profile
                if not db then return end
                local unitFrames = rawget(db, "unitFrames")
                local targetCfg = unitFrames and rawget(unitFrames, "Target") or nil
                local miscCfg = targetCfg and rawget(targetCfg, "misc") or nil
                if miscCfg and miscCfg.hideBossIcon == true then
                    if self.SetAlpha then
                        pcall(self.SetAlpha, self, 0)
                    end
                end
            end)
        end

        if bossIconFrame.SetAlpha then
            hooksecurefunc(bossIconFrame, "SetAlpha", function(self, alpha)
                local db = addon and addon.db and addon.db.profile
                if not db then return end
                local unitFrames = rawget(db, "unitFrames")
                local targetCfg = unitFrames and rawget(unitFrames, "Target") or nil
                local miscCfg = targetCfg and rawget(targetCfg, "misc") or nil
                if miscCfg and miscCfg.hideBossIcon == true and alpha and alpha > 0 then
                    if not getProp(self, "bossIconAlphaDeferred") then
                        setProp(self, "bossIconAlphaDeferred", true)
                        C_Timer.After(0, function()
                            setProp(self, "bossIconAlphaDeferred", nil)
                            if miscCfg and miscCfg.hideBossIcon == true and self.SetAlpha then
                                pcall(self.SetAlpha, self, 0)
                            end
                        end)
                    end
                end
            end)
        end
    end

    function addon.ApplyTargetBossIconVisibility()
        installBossIconHooks()
        applyBossIconVisibility()
    end
end

-- Player Misc.: Role Icon visibility
-- Frame path: PlayerFrame.PlayerFrameContent.PlayerFrameContentContextual.RoleIcon
do
    local _roleIconHooked = false
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
        if _roleIconHooked then return end
        _roleIconHooked = true

        local roleIconFrame = getRoleIconFrame()
        if not roleIconFrame then return end

        -- Hook Show() to re-apply visibility when Blizzard shows the frame
        if roleIconFrame.Show then
            hooksecurefunc(roleIconFrame, "Show", function(self)
                local db = addon and addon.db and addon.db.profile
                if not db then return end
                local unitFrames = rawget(db, "unitFrames")
                local playerCfg = unitFrames and rawget(unitFrames, "Player") or nil
                local miscCfg = playerCfg and rawget(playerCfg, "misc") or nil
                if miscCfg and miscCfg.hideRoleIcon == true then
                    if self.SetAlpha then
                        pcall(self.SetAlpha, self, 0)
                    end
                end
            end)
        end

        -- Hook SetAlpha() to re-enforce alpha=0 when Blizzard tries to change it
        if roleIconFrame.SetAlpha then
            hooksecurefunc(roleIconFrame, "SetAlpha", function(self, alpha)
                local db = addon and addon.db and addon.db.profile
                if not db then return end
                local unitFrames = rawget(db, "unitFrames")
                local playerCfg = unitFrames and rawget(unitFrames, "Player") or nil
                local miscCfg = playerCfg and rawget(playerCfg, "misc") or nil
                if miscCfg and miscCfg.hideRoleIcon == true and alpha and alpha > 0 then
                    -- Defer to avoid recursion
                    if not getProp(self, "roleIconAlphaDeferred") then
                        setProp(self, "roleIconAlphaDeferred", true)
                        C_Timer.After(0, function()
                            setProp(self, "roleIconAlphaDeferred", nil)
                            if miscCfg and miscCfg.hideRoleIcon == true and self.SetAlpha then
                                pcall(self.SetAlpha, self, 0)
                            end
                        end)
                    end
                end
            end)
        end
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
    local _groupNumberHooked = false
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
        if _groupNumberHooked then return end
        _groupNumberHooked = true

        local groupIndicatorFrame = getGroupIndicatorFrame()
        local groupIndicatorText = getGroupIndicatorTextFrame()

        -- Hook GroupIndicator container
        if groupIndicatorFrame then
            if groupIndicatorFrame.Show then
                hooksecurefunc(groupIndicatorFrame, "Show", function(self)
                    local db = addon and addon.db and addon.db.profile
                    if not db then return end
                    local unitFrames = rawget(db, "unitFrames")
                    local playerCfg = unitFrames and rawget(unitFrames, "Player") or nil
                    local miscCfg = playerCfg and rawget(playerCfg, "misc") or nil
                    if miscCfg and miscCfg.hideGroupNumber == true then
                        if self.SetAlpha then
                            pcall(self.SetAlpha, self, 0)
                        end
                    end
                end)
            end

            if groupIndicatorFrame.SetAlpha then
                hooksecurefunc(groupIndicatorFrame, "SetAlpha", function(self, alpha)
                    local db = addon and addon.db and addon.db.profile
                    if not db then return end
                    local unitFrames = rawget(db, "unitFrames")
                    local playerCfg = unitFrames and rawget(unitFrames, "Player") or nil
                    local miscCfg = playerCfg and rawget(playerCfg, "misc") or nil
                    if miscCfg and miscCfg.hideGroupNumber == true and alpha and alpha > 0 then
                        if not getProp(self, "groupIndicatorAlphaDeferred") then
                            setProp(self, "groupIndicatorAlphaDeferred", true)
                            C_Timer.After(0, function()
                                setProp(self, "groupIndicatorAlphaDeferred", nil)
                                if miscCfg and miscCfg.hideGroupNumber == true and self.SetAlpha then
                                    pcall(self.SetAlpha, self, 0)
                                end
                            end)
                        end
                    end
                end)
            end
        end

        -- Hook GroupIndicator text
        if groupIndicatorText then
            if groupIndicatorText.Show then
                hooksecurefunc(groupIndicatorText, "Show", function(self)
                    local db = addon and addon.db and addon.db.profile
                    if not db then return end
                    local unitFrames = rawget(db, "unitFrames")
                    local playerCfg = unitFrames and rawget(unitFrames, "Player") or nil
                    local miscCfg = playerCfg and rawget(playerCfg, "misc") or nil
                    if miscCfg and miscCfg.hideGroupNumber == true then
                        if self.SetAlpha then
                            pcall(self.SetAlpha, self, 0)
                        end
                    end
                end)
            end

            if groupIndicatorText.SetAlpha then
                hooksecurefunc(groupIndicatorText, "SetAlpha", function(self, alpha)
                    local db = addon and addon.db and addon.db.profile
                    if not db then return end
                    local unitFrames = rawget(db, "unitFrames")
                    local playerCfg = unitFrames and rawget(unitFrames, "Player") or nil
                    local miscCfg = playerCfg and rawget(playerCfg, "misc") or nil
                    if miscCfg and miscCfg.hideGroupNumber == true and alpha and alpha > 0 then
                        if not getProp(self, "groupIndicatorTextAlphaDeferred") then
                            setProp(self, "groupIndicatorTextAlphaDeferred", true)
                            C_Timer.After(0, function()
                                setProp(self, "groupIndicatorTextAlphaDeferred", nil)
                                if miscCfg and miscCfg.hideGroupNumber == true and self.SetAlpha then
                                    pcall(self.SetAlpha, self, 0)
                                end
                            end)
                        end
                    end
                end)
            end
        end
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
    local _pvpIconsHooked = false
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
        if _pvpIconsHooked then return end
        _pvpIconsHooked = true

        local prestigeBadge = getPrestigeBadge()
        local prestigePortrait = getPrestigePortrait()

        -- Hook PrestigeBadge
        if prestigeBadge then
            if prestigeBadge.Show then
                hooksecurefunc(prestigeBadge, "Show", function(self)
                    local db = addon and addon.db and addon.db.profile
                    if not db then return end
                    local unitFrames = rawget(db, "unitFrames")
                    local playerCfg = unitFrames and rawget(unitFrames, "Player") or nil
                    local miscCfg = playerCfg and rawget(playerCfg, "misc") or nil
                    if miscCfg and miscCfg.hidePvPIcons == true then
                        if self.SetAlpha then
                            pcall(self.SetAlpha, self, 0)
                        end
                    end
                end)
            end

            if prestigeBadge.SetAlpha then
                hooksecurefunc(prestigeBadge, "SetAlpha", function(self, alpha)
                    local db = addon and addon.db and addon.db.profile
                    if not db then return end
                    local unitFrames = rawget(db, "unitFrames")
                    local playerCfg = unitFrames and rawget(unitFrames, "Player") or nil
                    local miscCfg = playerCfg and rawget(playerCfg, "misc") or nil
                    if miscCfg and miscCfg.hidePvPIcons == true and alpha and alpha > 0 then
                        if not getProp(self, "prestigeBadgeAlphaDeferred") then
                            setProp(self, "prestigeBadgeAlphaDeferred", true)
                            C_Timer.After(0, function()
                                setProp(self, "prestigeBadgeAlphaDeferred", nil)
                                if miscCfg and miscCfg.hidePvPIcons == true and self.SetAlpha then
                                    pcall(self.SetAlpha, self, 0)
                                end
                            end)
                        end
                    end
                end)
            end
        end

        -- Hook PrestigePortrait
        if prestigePortrait then
            if prestigePortrait.Show then
                hooksecurefunc(prestigePortrait, "Show", function(self)
                    local db = addon and addon.db and addon.db.profile
                    if not db then return end
                    local unitFrames = rawget(db, "unitFrames")
                    local playerCfg = unitFrames and rawget(unitFrames, "Player") or nil
                    local miscCfg = playerCfg and rawget(playerCfg, "misc") or nil
                    if miscCfg and miscCfg.hidePvPIcons == true then
                        if self.SetAlpha then
                            pcall(self.SetAlpha, self, 0)
                        end
                    end
                end)
            end

            if prestigePortrait.SetAlpha then
                hooksecurefunc(prestigePortrait, "SetAlpha", function(self, alpha)
                    local db = addon and addon.db and addon.db.profile
                    if not db then return end
                    local unitFrames = rawget(db, "unitFrames")
                    local playerCfg = unitFrames and rawget(unitFrames, "Player") or nil
                    local miscCfg = playerCfg and rawget(playerCfg, "misc") or nil
                    if miscCfg and miscCfg.hidePvPIcons == true and alpha and alpha > 0 then
                        if not getProp(self, "prestigePortraitAlphaDeferred") then
                            setProp(self, "prestigePortraitAlphaDeferred", true)
                            C_Timer.After(0, function()
                                setProp(self, "prestigePortraitAlphaDeferred", nil)
                                if miscCfg and miscCfg.hidePvPIcons == true and self.SetAlpha then
                                    pcall(self.SetAlpha, self, 0)
                                end
                            end)
                        end
                    end
                end)
            end
        end
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
    local _petFrameHooked = false
    local _originalPetFrameAlpha = nil

    local function getPetFrame()
        local mgr = _G.EditModeManagerFrame
        local EM = _G.Enum and _G.Enum.EditModeUnitFrameSystemIndices
        local EMSys = _G.Enum and _G.Enum.EditModeSystem
        if mgr and EMSys and mgr.GetRegisteredSystemFrame and EM and EM.Pet then
            return mgr:GetRegisteredSystemFrame(EMSys.UnitFrame, EM.Pet)
        end
        return _G.PetFrame
    end

    local function applyPetFrameHiddenState()
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
        if _petFrameHooked then return end
        _petFrameHooked = true

        local petFrame = getPetFrame()
        if not petFrame then return end

        -- Hook Show() to re-apply hidden state when Blizzard shows the frame
        if petFrame.Show then
            hooksecurefunc(petFrame, "Show", function(self)
                local db = addon and addon.db and addon.db.profile
                if not db then return end
                local unitFrames = rawget(db, "unitFrames")
                local petCfg = unitFrames and rawget(unitFrames, "Pet") or nil
                if petCfg and petCfg.hideEntireFrame == true then
                    if self.SetAlpha then
                        pcall(self.SetAlpha, self, 0)
                    end
                end
            end)
        end

        -- Hook SetAlpha() to re-enforce alpha=0 when Blizzard tries to change it
        if petFrame.SetAlpha then
            hooksecurefunc(petFrame, "SetAlpha", function(self, alpha)
                local db = addon and addon.db and addon.db.profile
                if not db then return end
                local unitFrames = rawget(db, "unitFrames")
                local petCfg = unitFrames and rawget(unitFrames, "Pet") or nil
                if petCfg and petCfg.hideEntireFrame == true and alpha and alpha > 0 then
                    -- Defer to avoid recursion
                    if not getProp(self, "petFrameAlphaDeferred") then
                        setProp(self, "petFrameAlphaDeferred", true)
                        C_Timer.After(0, function()
                            setProp(self, "petFrameAlphaDeferred", nil)
                            if petCfg and petCfg.hideEntireFrame == true and self.SetAlpha then
                                pcall(self.SetAlpha, self, 0)
                            end
                        end)
                    end
                end
            end)
        end
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
