-- bars.lua: Unit Frame bar styling orchestrator. Delegates to bars/ submodules.

local addonName, addon = ...
local Util = addon.ComponentsUtil
local CleanupIconBorderAttachments = Util.CleanupIconBorderAttachments
local ClampOpacity = Util.ClampOpacity
local PlayerInCombat = Util.PlayerInCombat
local HideDefaultBarTextures = Util.HideDefaultBarTextures
local ToggleDefaultIconOverlay = Util.ToggleDefaultIconOverlay

-- Secret-value safe helpers (shared module)
local safeOffset = addon.SecretSafe.safeOffset

-- Reference extracted modules (loaded via TOC before this file)
local Utils = addon.BarsUtils
local Combat = addon.BarsCombat
local Resolvers = addon.BarsResolvers
local Textures = addon.BarsTextures
local Alpha = addon.BarsAlpha
local Preemptive = addon.BarsPreemptive
local RaidFrames = addon.BarsRaidFrames
local PartyFrames = addon.BarsPartyFrames
local BarsOverlays = addon.BarsOverlays
local BarsSmallFrames = addon.BarsSmallFrames

-- Direct upvalue to the event-driven guard (editmode/core.lua loads first in TOC)
local isEditModeActive = addon.EditMode.IsEditModeActiveOrOpening

-- Reference to FrameState module for safe property storage (avoids writing to Blizzard frames)
local FS = addon.FrameState

local function getState(frame)
    return FS.Get(frame)
end

local function getProp(frame, key)
    local st = FS.Get(frame)
    return st and st[key] or nil
end

local function setProp(frame, key, value)
    local st = FS.Get(frame)
    if st then
        st[key] = value
    end
end

--------------------------------------------------------------------------------
-- Local aliases to extracted module functions
-- These provide backward compatibility with code in this file
--------------------------------------------------------------------------------

local getUiScale = Utils.getUiScale
local pixelsToUiUnits = Utils.pixelsToUiUnits
local uiUnitsToPixels = Utils.uiUnitsToPixels
local clampScreenCoordinate = Utils.clampScreenCoordinate
local getFrameScreenOffsets = Utils.getFrameScreenOffsets

local queuePowerBarReapply = Combat.queuePowerBarReapply
local queueUnitFrameTextureReapply = Combat.queueUnitFrameTextureReapply
local queueRaidFrameReapply = Combat.queueRaidFrameReapply
local queuePartyFrameReapply = Combat.queuePartyFrameReapply

-- Unit Frames: Copy Health/Power Bar Style settings (texture, color mode, tint)
do
    function addon.CopyUnitFrameBarStyleSettings(sourceUnit, destUnit)
        local db = addon and addon.db and addon.db.profile
        if not db then return false end
        db.unitFrames = db.unitFrames or {}
        local src = db.unitFrames[sourceUnit]
        if not src then return false end
        db.unitFrames[destUnit] = db.unitFrames[destUnit] or {}
        local dst = db.unitFrames[destUnit]

        local function deepcopy(v)
            if type(v) ~= "table" then return v end
            local out = {}
            for k, vv in pairs(v) do out[k] = deepcopy(vv) end
            return out
        end

        local keys = {
            "healthBarTexture",
            "healthBarColorMode",
            "healthBarTint",
            "healthBarBackgroundTexture",
            "healthBarBackgroundColorMode",
            "healthBarBackgroundTint",
            "healthBarBackgroundOpacity",
            "powerBarTexture",
            "powerBarColorMode",
            "powerBarTint",
            "powerBarBackgroundTexture",
            "powerBarBackgroundColorMode",
            "powerBarBackgroundTint",
            "powerBarBackgroundOpacity",
            "powerBarHideFullSpikes",
            "powerBarHideFeedback",
            "powerBarHideSpark",
            "powerBarHideManaCostPrediction",
            "powerBarHidden",
        }
        for _, k in ipairs(keys) do
            if src[k] ~= nil then dst[k] = deepcopy(src[k]) else dst[k] = nil end
        end

        if addon.ApplyUnitFrameBarTexturesFor then addon.ApplyUnitFrameBarTexturesFor(destUnit) end
        return true
    end
end

-- Unit Frames: Apply custom bar textures (Health/Power) with optional tint per unit
do
    -- Use resolver functions from extracted module
    local getUnitFrameFor = Resolvers.getUnitFrameFor
    local resolveHealthBar = Resolvers.resolveHealthBar
    local resolveHealthContainer = Resolvers.resolveHealthContainer
    local resolvePowerBar = Resolvers.resolvePowerBar
    local resolveAlternatePowerBar = Resolvers.resolveAlternatePowerBar
    local resolveHealthMask = Resolvers.resolveHealthMask
    local resolvePowerMask = Resolvers.resolvePowerMask
    local resolveUFContentMain = Resolvers.resolveUFContentMain
    local resolveUnitFrameFrameTexture = Resolvers.resolveUnitFrameFrameTexture
    local resolveBossHealthMask = Resolvers.resolveBossHealthMask
    local resolveBossPowerMask = Resolvers.resolveBossPowerMask
    local resolveBossHealthBarsContainer = Resolvers.resolveBossHealthBarsContainer
    local resolveBossManaBar = Resolvers.resolveBossManaBar
    
    -- Use texture functions from extracted module
    local applyToBar = Textures.applyToBar
    local applyBackgroundToBar = Textures.applyBackgroundToBar
    local ensureMaskOnBarTexture = Textures.ensureMaskOnBarTexture
    
    -- Use alpha functions from extracted module
    local applyAlpha = Alpha.applyAlpha
    local hookAlphaEnforcer = Alpha.hookAlphaEnforcer

    -- Overlay functions from extracted bars/overlays.lua module
    local ensureTextAndBorderOrdering = BarsOverlays._ensureTextAndBorderOrdering
    local ensureBossRectOverlay = BarsOverlays._ensureBossRectOverlay
    local ensureRectHealthOverlay = BarsOverlays._ensureRectHealthOverlay
    local ensureRectPowerOverlay = BarsOverlays._ensureRectPowerOverlay
    local updateRectPowerOverlay = BarsOverlays._updateRectPowerOverlay

    -- Expose helpers for other modules (Cast Bar styling, etc.)
    addon._ApplyToStatusBar = applyToBar
    addon._ApplyBackgroundToStatusBar = applyBackgroundToBar

    local function applyForUnit(unit)
        if not addon:IsModuleEnabled("unitFrames", unit) then return end
        local db = addon and addon.db and addon.db.profile
        if not db then return end
        -- Zero‑Touch: do not create config tables. If this unit has no config, do nothing.
        local unitFrames = rawget(db, "unitFrames")
        local cfg = unitFrames and rawget(unitFrames, unit) or nil
        if not cfg then
            return
        end

        -- Zero‑Touch: only apply when at least one bar-related setting is explicitly configured.
        local function hasAnyKey(tbl, keys)
            if not tbl then return false end
            for i = 1, #keys do
                if tbl[keys[i]] ~= nil then return true end
            end
            return false
        end
        local hasAnyBarSetting =
            hasAnyKey(cfg, {
                "useCustomBorders",
                "healthBarTexture", "healthBarColorMode", "healthBarTint",
                "healthBarBackgroundTexture", "healthBarBackgroundColorMode", "healthBarBackgroundTint", "healthBarBackgroundOpacity",
                "powerBarTexture", "powerBarColorMode", "powerBarTint",
                "powerBarBackgroundTexture", "powerBarBackgroundColorMode", "powerBarBackgroundTint", "powerBarBackgroundOpacity",
                "powerBarHidden",
                "borderStyle", "borderThickness", "borderInset", "borderInsetH", "borderInsetV", "borderTintEnable", "borderTintColor",
                "healthBarHideTextureOnly",
            })
        local altCfg = rawget(cfg, "altPowerBar")
        if not hasAnyBarSetting and not hasAnyKey(altCfg, { "enabled", "width", "height", "x", "y", "fontFace", "size", "style", "color", "alignment" }) then
            return
        end
        local frame = getUnitFrameFor(unit)
        if not frame then return end

        -- Pet, TargetOfTarget, FocusTarget: delegated to bars/smallframes.lua
        if unit == "Pet" or unit == "TargetOfTarget" or unit == "FocusTarget" then
            BarsSmallFrames.applyForSmallUnit(unit, frame, cfg)
            return
        end

        -- Boss unit frames commonly appear/update during combat (e.g., INSTANCE_ENCOUNTER_ENGAGE_UNIT / UPDATE_BOSS_FRAMES).
        -- IMPORTANT (taint): Even "cosmetic-only" writes to Boss unit frame regions (including SetAlpha on textures)
        -- can taint the Boss system and later block protected layout calls like BossTargetFrameContainer:SetSize().
        -- Do not mutate protected unit frame regions during combat. If Boss needs a re-assertion,
        -- queue a post-combat reapply instead.
        if unit == "Boss" then
            if InCombatLockdown and InCombatLockdown() then
                queueUnitFrameTextureReapply("Boss")
            else
                for i = 1, addon.NUM_BOSS_FRAMES do
                    local bossFrame = addon.GetBossFrame(i)
                    if bossFrame then
                        -- FrameTexture (hide for useCustomBorders OR healthBarHideBorder)
                        local bossFT = bossFrame.TargetFrameContainer and bossFrame.TargetFrameContainer.FrameTexture
                        if bossFT then
                            local function computeBossFTAlpha()
                                local db2 = addon and addon.db and addon.db.profile
                                local unitFrames2 = db2 and rawget(db2, "unitFrames") or nil
                                local cfgBoss = unitFrames2 and rawget(unitFrames2, "Boss") or nil
                                if not cfgBoss then return nil end -- config unreadable: skip (fail closed)
                                return (cfgBoss.useCustomBorders or cfgBoss.healthBarHideBorder) and 0 or 1
                            end
                            applyAlpha(bossFT, computeBossFTAlpha())
                            hookAlphaEnforcer(bossFT, computeBossFTAlpha)
                        end

                        -- Flash (aggro/threat glow) (hide for useCustomBorders)
                        local bossFlash = bossFrame.TargetFrameContainer and bossFrame.TargetFrameContainer.Flash
                        if bossFlash then
                            local function computeBossFlashAlpha()
                                local db2 = addon and addon.db and addon.db.profile
                                local unitFrames2 = db2 and rawget(db2, "unitFrames") or nil
                                local cfgBoss = unitFrames2 and rawget(unitFrames2, "Boss") or nil
                                if not cfgBoss then return nil end -- config unreadable: skip (fail closed)
                                return cfgBoss.useCustomBorders and 0 or 1
                            end
                            applyAlpha(bossFlash, computeBossFlashAlpha())
                            hookAlphaEnforcer(bossFlash, computeBossFlashAlpha)
                        end

                        -- ReputationColor strip (hide for useCustomBorders)
                        local bossReputationColor = bossFrame.TargetFrameContent
                            and bossFrame.TargetFrameContent.TargetFrameContentMain
                            and bossFrame.TargetFrameContent.TargetFrameContentMain.ReputationColor
                        if bossReputationColor then
                            local function computeBossRepAlpha()
                                local db2 = addon and addon.db and addon.db.profile
                                local unitFrames2 = db2 and rawget(db2, "unitFrames") or nil
                                local cfgBoss = unitFrames2 and rawget(unitFrames2, "Boss") or nil
                                if not cfgBoss then return nil end -- config unreadable: skip (fail closed)
                                return cfgBoss.useCustomBorders and 0 or 1
                            end
                            applyAlpha(bossReputationColor, computeBossRepAlpha())
                            hookAlphaEnforcer(bossReputationColor, computeBossRepAlpha)
                        end
                    end
                end
            end
        end

        -- Target/Focus frames can be updated/rebuilt by Blizzard during combat (rapid target swaps, faction updates, etc.).
        -- Protected StatusBars/layout must NEVER be touched during combat, but visual-only overlays CAN safely be enforced
        -- (like ReputationColor) via SetAlpha + alpha enforcers. Do this BEFORE the combat early-return so the element
        -- stays hidden even if Blizzard recreates the region during combat.
        --
        -- IMPORTANT: Blizzard may recreate the ReputationColor texture during rapid target changes.
        -- Always apply alpha + install enforcer + schedule a follow-up re-hide to catch late updates.
        if unit == "Target" or unit == "Focus" then
            local function computeUseCustomBordersAlpha()
                local db2 = addon and addon.db and addon.db.profile
                local unitFrames2 = db2 and rawget(db2, "unitFrames") or nil
                local cfg2 = unitFrames2 and rawget(unitFrames2, unit) or nil
                if not cfg2 then return nil end -- config unreadable: skip (fail closed)
                return cfg2.useCustomBorders and 0 or 1
            end

            local reputationColor
            if unit == "Target" and _G.TargetFrame then
                reputationColor = _G.TargetFrame.TargetFrameContent
                    and _G.TargetFrame.TargetFrameContent.TargetFrameContentMain
                    and _G.TargetFrame.TargetFrameContent.TargetFrameContentMain.ReputationColor
            elseif unit == "Focus" and _G.FocusFrame then
                reputationColor = _G.FocusFrame.TargetFrameContent
                    and _G.FocusFrame.TargetFrameContent.TargetFrameContentMain
                    and _G.FocusFrame.TargetFrameContent.TargetFrameContentMain.ReputationColor
            end

            if reputationColor then
                -- Always apply current alpha, regardless of hook state
                local desiredAlpha = computeUseCustomBordersAlpha()
                applyAlpha(reputationColor, desiredAlpha)
                hookAlphaEnforcer(reputationColor, computeUseCustomBordersAlpha)
                
                -- Belt-and-suspenders: schedule a follow-up re-hide after Blizzard's updates complete
                -- Catches cases where Blizzard resets alpha after the initial hide
                if _G.C_Timer and _G.C_Timer.After then
                    _G.C_Timer.After(0, function()
                        -- Re-resolve in case the texture object changed
                        local repColor2
                        if unit == "Target" and _G.TargetFrame then
                            repColor2 = _G.TargetFrame.TargetFrameContent
                                and _G.TargetFrame.TargetFrameContent.TargetFrameContentMain
                                and _G.TargetFrame.TargetFrameContent.TargetFrameContentMain.ReputationColor
                        elseif unit == "Focus" and _G.FocusFrame then
                            repColor2 = _G.FocusFrame.TargetFrameContent
                                and _G.FocusFrame.TargetFrameContent.TargetFrameContentMain
                                and _G.FocusFrame.TargetFrameContent.TargetFrameContentMain.ReputationColor
                        end
                        if repColor2 and repColor2.SetAlpha then
                            local alpha2 = computeUseCustomBordersAlpha()
                            -- nil = config unreadable at this tick: skip the write
                            -- (never restore visible from a transient window)
                            if alpha2 ~= nil then
                                pcall(repColor2.SetAlpha, repColor2, alpha2)
                            end
                            -- Install enforcer on the (possibly new) object
                            hookAlphaEnforcer(repColor2, computeUseCustomBordersAlpha)
                        end
                    end)
                end
            end
        end

        -- Boss frames can also be updated by Blizzard during combat (boss target changes, etc.).
        -- Apply the same early ReputationColor handling pattern as Target/Focus: run BEFORE the combat
        -- early-return so the element stays hidden, with C_Timer follow-up to catch late Blizzard updates.
        if unit == "Boss" then
            local function computeBossUseCustomBordersAlpha()
                local db2 = addon and addon.db and addon.db.profile
                local unitFrames2 = db2 and rawget(db2, "unitFrames") or nil
                local cfgBoss = unitFrames2 and rawget(unitFrames2, "Boss") or nil
                if not cfgBoss then return nil end -- config unreadable: skip (fail closed)
                return cfgBoss.useCustomBorders and 0 or 1
            end

            for i = 1, addon.NUM_BOSS_FRAMES do
                local bossFrame = addon.GetBossFrame(i)
                if bossFrame then
                    local bossRepColor = bossFrame.TargetFrameContent
                        and bossFrame.TargetFrameContent.TargetFrameContentMain
                        and bossFrame.TargetFrameContent.TargetFrameContentMain.ReputationColor

                    if bossRepColor then
                        -- Always apply current alpha, regardless of hook state
                        local desiredAlpha = computeBossUseCustomBordersAlpha()
                        applyAlpha(bossRepColor, desiredAlpha)
                        hookAlphaEnforcer(bossRepColor, computeBossUseCustomBordersAlpha)

                        -- Belt-and-suspenders: schedule a follow-up re-hide after Blizzard's updates complete
                        -- Catches cases where Blizzard resets alpha after the initial hide
                        if _G.C_Timer and _G.C_Timer.After then
                            local bossIndex = i  -- Capture loop variable for closure
                            _G.C_Timer.After(0, function()
                                -- Re-resolve in case the texture object changed
                                local bossFrame2 = addon.GetBossFrame(bossIndex)
                                local repColor2 = bossFrame2 and bossFrame2.TargetFrameContent
                                    and bossFrame2.TargetFrameContent.TargetFrameContentMain
                                    and bossFrame2.TargetFrameContent.TargetFrameContentMain.ReputationColor
                                if repColor2 and repColor2.SetAlpha then
                                    local alpha2 = computeBossUseCustomBordersAlpha()
                                    -- nil = config unreadable at this tick: skip the write
                                    if alpha2 ~= nil then
                                        pcall(repColor2.SetAlpha, repColor2, alpha2)
                                    end
                                    -- Install enforcer on the (possibly new) object
                                    hookAlphaEnforcer(repColor2, computeBossUseCustomBordersAlpha)
                                end
                            end)
                        end
                    end
                end
            end
        end

        -- Combat safety: Player frame has reparenting operations (AnimatedLossBar, HealPrediction)
        -- that interact with protected frame state — defer to post-combat.
        -- Target/Focus use cosmetic-only operations (SetStatusBarTexture, SetVertexColor,
        -- SetReverseFill, overlay/border creation) which are combat-safe.
        -- Layout operations (width/height scaling) have their own `inCombat` guards downstream.
        if unit == "Player" and InCombatLockdown and InCombatLockdown() then
            queueUnitFrameTextureReapply(unit)
            return
        end

        local combatSafe = (unit ~= "Player")

        -- Target-of-Target can get refreshed frequently by Blizzard (even out of combat),
        -- which can reset its bar textures. Install a lightweight, throttled hook on the
        -- ToT frame's Update() to re-assert styling shortly after Blizzard updates it.
        if unit == "TargetOfTarget" and _G.hooksecurefunc then
            local tot = _G.TargetFrameToT
            local totState = getState(tot)
            if tot and totState and not totState.toTUpdateHooked and type(tot.Update) == "function" then
                totState.toTUpdateHooked = true
                _G.hooksecurefunc(tot, "Update", function()
                    if isEditModeActive() then return end
                    local db2 = addon and addon.db and addon.db.profile
                    if not db2 then return end
                    local unitFrames2 = rawget(db2, "unitFrames")
                    local cfgT = unitFrames2 and rawget(unitFrames2, "TargetOfTarget") or nil
                    if not cfgT then
                        return
                    end

                    local texKey = cfgT.healthBarTexture or "default"
                    local colorMode = cfgT.healthBarColorMode or "default"
                    local tint = cfgT.healthBarTint

                    local hasCustomTexture = (type(texKey) == "string" and texKey ~= "" and texKey ~= "default")
                    local hasCustomColor = (colorMode == "custom" and type(tint) == "table") or (colorMode == "class") or (colorMode == "texture")
                    if not hasCustomTexture and not hasCustomColor then
                        return
                    end

                    if InCombatLockdown and InCombatLockdown() then
                        queueUnitFrameTextureReapply("TargetOfTarget")
                        return
                    end

                    local state = getState(tot)
                    if state and state.toTReapplyPending then
                        return
                    end
                    if state then state.toTReapplyPending = true end

                    if _G.C_Timer and _G.C_Timer.After and addon.ApplyUnitFrameBarTexturesFor then
                        _G.C_Timer.After(0, function()
                            local st2 = getState(tot)
                            if st2 then st2.toTReapplyPending = nil end
                            addon.ApplyUnitFrameBarTexturesFor("TargetOfTarget")
                        end)
                    elseif addon.ApplyUnitFrameBarTexturesFor then
                        if state then state.toTReapplyPending = nil end
                        addon.ApplyUnitFrameBarTexturesFor("TargetOfTarget")
                    end
                end)
            end
        end

        -- FocusTarget can get refreshed frequently by Blizzard (even out of combat),
        -- which can reset its bar textures. Install a lightweight, throttled hook on the
        -- FoT frame's Update() to re-assert styling shortly after Blizzard updates it.
        if unit == "FocusTarget" and _G.hooksecurefunc then
            local fot = _G.FocusFrameToT
            local fotState = getState(fot)
            if fot and fotState and not fotState.foTUpdateHooked and type(fot.Update) == "function" then
                fotState.foTUpdateHooked = true
                _G.hooksecurefunc(fot, "Update", function()
                    if isEditModeActive() then return end
                    local db2 = addon and addon.db and addon.db.profile
                    if not db2 then return end
                    local unitFrames2 = rawget(db2, "unitFrames")
                    local cfgF = unitFrames2 and rawget(unitFrames2, "FocusTarget") or nil
                    if not cfgF then
                        return
                    end

                    local texKey = cfgF.healthBarTexture or "default"
                    local colorMode = cfgF.healthBarColorMode or "default"
                    local tint = cfgF.healthBarTint

                    local hasCustomTexture = (type(texKey) == "string" and texKey ~= "" and texKey ~= "default")
                    local hasCustomColor = (colorMode == "custom" and type(tint) == "table") or (colorMode == "class") or (colorMode == "texture")
                    if not hasCustomTexture and not hasCustomColor then
                        return
                    end

                    if InCombatLockdown and InCombatLockdown() then
                        queueUnitFrameTextureReapply("FocusTarget")
                        return
                    end

                    local state = getState(fot)
                    if state and state.foTReapplyPending then
                        return
                    end
                    if state then state.foTReapplyPending = true end

                    if _G.C_Timer and _G.C_Timer.After and addon.ApplyUnitFrameBarTexturesFor then
                        _G.C_Timer.After(0, function()
                            local st2 = getState(fot)
                            if st2 then st2.foTReapplyPending = nil end
                            addon.ApplyUnitFrameBarTexturesFor("FocusTarget")
                        end)
                    elseif addon.ApplyUnitFrameBarTexturesFor then
                        if state then state.foTReapplyPending = nil end
                        addon.ApplyUnitFrameBarTexturesFor("FocusTarget")
                    end
                end)
            end
        end

        -- Boss frames: apply to Boss1..Boss5 frames (shared config: db.unitFrames.Boss), then return.
        -- Boss frames are individual TargetFrame variants and are NOT the same as the EditMode system frame.
        if unit == "Boss" then
            local function resolveBossHealthMask(bossFrame)
                -- Get mask from the health bar's parent container (HealthBarsContainer)
                local hb = bossFrame and bossFrame.healthbar
                if hb then
                    local parent = hb:GetParent()
                    if parent and parent.HealthBarMask then return parent.HealthBarMask end
                end
            end
            local function resolveBossPowerMask(bossFrame)
                -- Get mask from the mana bar directly
                local mb = bossFrame and bossFrame.manabar
                if mb and mb.ManaBarMask then return mb.ManaBarMask end
            end

            for i = 1, addon.NUM_BOSS_FRAMES do
                local bossFrame = addon.GetBossFrame(i)
                local unitId = "boss" .. i
                -- Apply styling whenever the frame exists. Let resolveHealthBar/resolvePowerBar
                -- handle finding the bars within the frame structure.
                if bossFrame then
                    local hb = resolveHealthBar(bossFrame, unit)
                        if hb then
                            local healthBarHideTextureOnly = (cfg.healthBarHideTextureOnly == true)
                            if healthBarHideTextureOnly then
                                if Util and Util.SetHealthBarTextureOnlyHidden then
                                    Util.SetHealthBarTextureOnlyHidden(hb, true)
                                end
                            else
                                if Util and Util.SetHealthBarTextureOnlyHidden then
                                    Util.SetHealthBarTextureOnlyHidden(hb, false)
                                end
                            end

                            -- Skip texture/color application when bar is hidden — no point
                            -- applying textures (which creates new texture objects and stale
                            -- hooks) or colors to an invisible bar.
                            if not healthBarHideTextureOnly then
                                local colorModeHB = cfg.healthBarColorMode or "default"
                                local texKeyHB = cfg.healthBarTexture or "default"
                                applyToBar(hb, texKeyHB, colorModeHB, cfg.healthBarTint, unitId, "health", unitId)

                                -- Background overlay (only when explicitly customized)
                                do
                                    local function hasBackgroundCustomization()
                                        local texKey = cfg.healthBarBackgroundTexture
                                        if type(texKey) == "string" and texKey ~= "" and texKey ~= "default" then
                                            return true
                                        end
                                        local mode = cfg.healthBarBackgroundColorMode
                                        if type(mode) == "string" and mode ~= "" and mode ~= "default" then
                                            return true
                                        end
                                        local op = cfg.healthBarBackgroundOpacity
                                        local opNum = tonumber(op)
                                        if op ~= nil and opNum ~= nil and opNum ~= 50 then
                                            return true
                                        end
                                        if mode == "custom" and type(cfg.healthBarBackgroundTint) == "table" then
                                            return true
                                        end
                                        return false
                                    end
                                    if hasBackgroundCustomization() then
                                        local bgTexKeyHB = cfg.healthBarBackgroundTexture or "default"
                                        local bgColorModeHB = cfg.healthBarBackgroundColorMode or "default"
                                        local bgOpacityHB = cfg.healthBarBackgroundOpacity or 50
                                        applyBackgroundToBar(hb, bgTexKeyHB, bgColorModeHB, cfg.healthBarBackgroundTint, bgOpacityHB, unit, "health")
                                    end
                                end

                                ensureMaskOnBarTexture(hb, resolveBossHealthMask(bossFrame))
                            end

                            -- Clip HealthBarsContainer children to prevent dark background
                            -- below health bar when boss has no power bar
                            local hbClipContainer = resolveBossHealthBarsContainer(bossFrame)
                            if hbClipContainer and hbClipContainer.SetClipsChildren then
                                hbClipContainer:SetClipsChildren(true)
                            end

                            -- Rectangular overlay to fill top-left chip when using custom borders
                            ensureBossRectOverlay(bossFrame, hb, cfg, "health", unitId)

                            -- Health Bar custom border (same settings as other unit frames)
                            -- BOSS FRAME FIX: The HealthBar StatusBar has oversized dimensions spanning both
                            -- health and power bars. The HealthBarsContainer (parent of HealthBar) has the
                            -- correct bounds because ManaBar is a sibling of HealthBarsContainer, not a child.
                            -- The border anchors to HealthBarsContainer instead of the StatusBar.
                            if healthBarHideTextureOnly then
                                -- Clear borders when texture-only hiding is active
                                local anchorFrame = getProp(hb, "bossHealthBorderAnchor")
                                if anchorFrame then
                                    if addon.BarBorders and addon.BarBorders.ClearBarFrame then addon.BarBorders.ClearBarFrame(anchorFrame) end
                                    if addon.Borders and addon.Borders.HideAll then addon.Borders.HideAll(anchorFrame) end
                                end
                            else
                            do
                                local styleKey = cfg.healthBarBorderStyle
                                local hiddenEdges = cfg.healthBarBorderHiddenEdges
                                local tintEnabled = not not cfg.healthBarBorderTintEnable
                                local tintColor = type(cfg.healthBarBorderTintColor) == "table" and {
                                    cfg.healthBarBorderTintColor[1] or 1,
                                    cfg.healthBarBorderTintColor[2] or 1,
                                    cfg.healthBarBorderTintColor[3] or 1,
                                    cfg.healthBarBorderTintColor[4] or 1,
                                } or {1, 1, 1, 1}
                                local thickness = tonumber(cfg.healthBarBorderThickness) or 1
                                if thickness < 1 then thickness = 1 elseif thickness > 16 then thickness = 16 end
                                local insetH = tonumber(cfg.healthBarBorderInsetH) or tonumber(cfg.healthBarBorderInset) or 0
                                local insetV = tonumber(cfg.healthBarBorderInsetV) or tonumber(cfg.healthBarBorderInset) or 0

                                -- Resolve HealthBarsContainer which has correct bounds (just health bar area)
                                local hbContainer = resolveBossHealthBarsContainer(bossFrame)

                                -- Create or retrieve the anchor frame for border application
                                -- This frame matches the HealthBarsContainer bounds, not the oversized StatusBar
                                local anchorFrame = getProp(hb, "bossHealthBorderAnchor")
                                if not anchorFrame then
                                    anchorFrame = CreateFrame("Frame", nil, hb)
                                    anchorFrame:SetFrameLevel((hb:GetFrameLevel() or 0) + 1)
                                    setProp(hb, "bossHealthBorderAnchor", anchorFrame)
                                end

                                -- Anchor to HealthBarsContainer bounds if available, else clipping container or StatusBar
                                anchorFrame:ClearAllPoints()
                                if hbContainer then
                                    anchorFrame:SetPoint("TOPLEFT", hbContainer, "TOPLEFT", 0, 0)
                                    anchorFrame:SetPoint("BOTTOMRIGHT", hbContainer, "BOTTOMRIGHT", 0, 0)
                                else
                                    anchorFrame:SetAllPoints(hb)
                                end
                                anchorFrame:Show()

                                -- BOSS FRAME CLEANUP: Clear any stale borders on parent containers and the StatusBar.
                                -- Previously borders may have been applied to wrong frames (e.g., HealthBarsContainer,
                                -- TargetFrameContentMain, bossFrame.healthbar with wrong dimensions). Clear them all.
                                do
                                    local clearTargets = {
                                        bossFrame.healthbar,
                                        hb,
                                        hb and hb:GetParent(), -- HealthBarsContainer
                                        bossFrame.TargetFrameContent and bossFrame.TargetFrameContent.TargetFrameContentMain,
                                        bossFrame.TargetFrameContent,
                                    }
                                    for _, target in ipairs(clearTargets) do
                                        -- Don't clear the anchor frame itself (borders are applied here)
                                        if target and target ~= anchorFrame then
                                            if addon.BarBorders and addon.BarBorders.ClearBarFrame then
                                                addon.BarBorders.ClearBarFrame(target)
                                            end
                                            if addon.Borders and addon.Borders.HideAll then
                                                addon.Borders.HideAll(target)
                                            end
                                        end
                                    end
                                end

                                -- Apply border to anchor frame (not hb!) so it matches HealthBarTexture bounds
                                if cfg.useCustomBorders then
                                    if styleKey == "none" or styleKey == nil then
                                        if addon.BarBorders and addon.BarBorders.ClearBarFrame then addon.BarBorders.ClearBarFrame(anchorFrame) end
                                        if addon.Borders and addon.Borders.HideAll then addon.Borders.HideAll(anchorFrame) end
                                    else
                                        local styleDef = addon.BarBorders and addon.BarBorders.GetStyle and addon.BarBorders.GetStyle(styleKey)
                                        local color
                                        if tintEnabled then
                                            color = tintColor
                                        else
                                            if styleDef then
                                                color = {1, 1, 1, 1}
                                            else
                                                color = {0, 0, 0, 1}
                                            end
                                        end
                                        local handled = false
                                        -- Clear old borders from anchor frame before applying new
                                        if addon.BarBorders and addon.BarBorders.ClearBarFrame then
                                            addon.BarBorders.ClearBarFrame(anchorFrame)
                                        end
                                        if addon.Borders and addon.Borders.HideAll then
                                            addon.Borders.HideAll(anchorFrame)
                                        end
                                        -- Try ApplySquare for Boss health bar borders (simpler, more reliable)
                                        -- BarBorders.ApplyToBarFrame requires a StatusBar, but anchorFrame is a Frame
                                        if addon.Borders and addon.Borders.ApplySquare then
                                            local sqColor = tintEnabled and tintColor or {0, 0, 0, 1}
                                            local baseY = 1
                                            local baseX = 1
                                            local expandY = baseY - insetV
                                            local expandX = baseX - insetH
                                            if expandX < -6 then expandX = -6 elseif expandX > 6 then expandX = 6 end
                                            if expandY < -6 then expandY = -6 elseif expandY > 6 then expandY = 6 end
                                            addon.Borders.ApplySquare(anchorFrame, {
                                                size = thickness,
                                                color = sqColor,
                                                layer = "OVERLAY",
                                                layerSublevel = 3,
                                                expandX = expandX,
                                                expandY = expandY,
                                                skipDimensionCheck = true, -- Anchor frame may be small
                                                hiddenEdges = hiddenEdges,
                                            })
                                            handled = true
                                        end
                                        if handled then
                                            ensureTextAndBorderOrdering(unit)
                                        end
                                    end
                                else
                                    if addon.BarBorders and addon.BarBorders.ClearBarFrame then addon.BarBorders.ClearBarFrame(anchorFrame) end
                                    if addon.Borders and addon.Borders.HideAll then addon.Borders.HideAll(anchorFrame) end
                                end
                            end
                            end -- if not healthBarHideTextureOnly

                            -- Boss frames can get refreshed by Blizzard (HealthUpdate, Update) which resets textures.
                            -- Install hooks to re-assert styling after Blizzard updates.
                            local bossState = getState(bossFrame)
                            if _G.hooksecurefunc and bossState then
                                local function installBossHealthHook(hookTarget, hookName, flagName)
                                    if bossState[flagName] then return true end
                                    if hookTarget and type(hookTarget[hookName]) == "function" then
                                        bossState[flagName] = true
                                        _G.hooksecurefunc(hookTarget, hookName, function()
                                            if isEditModeActive() then return end
                                            local db2 = addon and addon.db and addon.db.profile
                                            if not db2 then return end
                                            local unitFrames2 = rawget(db2, "unitFrames")
                                            local cfgBoss = unitFrames2 and rawget(unitFrames2, "Boss") or nil
                                            if not cfgBoss then return end

                                            -- Re-hide fill texture after Blizzard may have recreated it
                                            if cfgBoss.healthBarHideTextureOnly == true then
                                                local hbReapply = bossFrame.healthbar
                                                if hbReapply and Util and Util.SetHealthBarTextureOnlyHidden then
                                                    Util.SetHealthBarTextureOnlyHidden(hbReapply, true)
                                                end
                                                return
                                            end

                                            local texKey = cfgBoss.healthBarTexture or "default"
                                            local colorMode = cfgBoss.healthBarColorMode or "default"
                                            local tint = cfgBoss.healthBarTint

                                            local hasCustomTexture = (type(texKey) == "string" and texKey ~= "" and texKey ~= "default")
                                            local hasCustomColor = (colorMode == "custom" and type(tint) == "table") or (colorMode == "class") or (colorMode == "texture")
                                            if not hasCustomTexture and not hasCustomColor then return end

                                            -- Throttle: skip if a reapply is already pending for this frame
                                            local st = getState(bossFrame)
                                            if st and st.bossReapplyPending then return end
                                            if st then st.bossReapplyPending = true end

                                            -- Defer to next frame to let Blizzard finish its updates
                                            if _G.C_Timer and _G.C_Timer.After then
                                                _G.C_Timer.After(0, function()
                                                    local st2 = getState(bossFrame)
                                                    if st2 then st2.bossReapplyPending = nil end
                                                    -- Use direct property (most reliable)
                                                    local hbReapply = bossFrame.healthbar
                                                    if hbReapply then
                                                        local resolvedPath = addon.Media and addon.Media.ResolveBarTexturePath and addon.Media.ResolveBarTexturePath(texKey)
                                                        if resolvedPath and hbReapply.SetStatusBarTexture then
                                                            pcall(hbReapply.SetStatusBarTexture, hbReapply, resolvedPath)
                                                        end
                                                        -- Reapply color
                                                        local tex = hbReapply:GetStatusBarTexture()
                                                        if tex and tex.SetVertexColor then
                                                            local r, g, b, a = 1, 1, 1, 1
                                                            if colorMode == "custom" and type(tint) == "table" then
                                                                r, g, b, a = tint[1] or 1, tint[2] or 1, tint[3] or 1, tint[4] or 1
                                                            elseif colorMode == "class" and addon.GetClassColorRGB then
                                                                local cr, cg, cb = addon.GetClassColorRGB(unitId)
                                                                if cr == nil and addon.GetDefaultHealthColorRGB then
                                                                    cr, cg, cb = addon.GetDefaultHealthColorRGB()
                                                                end
                                                                r, g, b = cr or 0, cg or 1, cb or 0
                                                            elseif colorMode == "texture" then
                                                                r, g, b, a = 1, 1, 1, 1
                                                            elseif colorMode == "default" and addon.GetDefaultHealthColorRGB then
                                                                local hr, hg, hb = addon.GetDefaultHealthColorRGB()
                                                                r, g, b = hr or 0, hg or 1, hb or 0
                                                            end
                                                            pcall(tex.SetVertexColor, tex, r, g, b, a)
                                                        end
                                                    end
                                                end)
                                            end
                                        end)
                                        return true
                                    end
                                    return false
                                end
                                -- Hook HealthUpdate (targeted, fires for low-health player units)
                                installBossHealthHook(bossFrame, "HealthUpdate", "bossHealthUpdateHooked")
                                -- ALSO hook Update — HealthUpdate only fires for player-controlled
                                -- units at <20% health (OnUpdate handler), which bosses never are.
                                -- Update fires on INSTANCE_ENCOUNTER_ENGAGE_UNIT,
                                -- UNIT_TARGETABLE_CHANGED, etc. where Blizzard calls
                                -- UnitFrameHealthBar_Update → SetStatusBarColor(0, 1, 0).
                                installBossHealthHook(bossFrame, "Update", "bossUpdateHooked")
                            end
                        end

                        local pb = resolvePowerBar(bossFrame, unit)
                        if pb then
                            local powerBarHidden = (cfg.powerBarHidden == true)
                            local powerBarHideTextureOnly = (cfg.powerBarHideTextureOnly == true)

                            if pb.GetAlpha and getProp(pb, "origPBAlpha") == nil then
                                local ok, a = pcall(pb.GetAlpha, pb)
                                setProp(pb, "origPBAlpha", ok and (a or 1) or 1)
                            end

                            -- Detect boss with no usable power resource
                            local bossHasNoPower = false
                            if pb.GetMinMaxValues then
                                local okMM, pMin, pMax = pcall(pb.GetMinMaxValues, pb)
                                if okMM and type(pMax) == "number" and not issecretvalue(pMax) and pMax <= 0 then
                                    bossHasNoPower = true
                                end
                            end

                            if bossHasNoPower then
                                -- Hide entire ManaBar to prevent rogue texture artifacts
                                -- (Spark, invalid atlas, etc.). Text repositioned via "Around Name"
                                -- is reparented to TargetFrameContentMain and is NOT affected.
                                if pb.SetAlpha then pcall(pb.SetAlpha, pb, 0) end
                                if addon.BarBorders and addon.BarBorders.ClearBarFrame then addon.BarBorders.ClearBarFrame(pb) end
                                if addon.Borders and addon.Borders.HideAll then addon.Borders.HideAll(pb) end
                                local bpAnchor = getProp(pb, "bossPowerBorderAnchor")
                                if bpAnchor then
                                    if addon.BarBorders and addon.BarBorders.ClearBarFrame then addon.BarBorders.ClearBarFrame(bpAnchor) end
                                    if addon.Borders and addon.Borders.HideAll then addon.Borders.HideAll(bpAnchor) end
                                end
                            end

                            if not bossHasNoPower then
                            if powerBarHidden then
                                if pb.SetAlpha then pcall(pb.SetAlpha, pb, 0) end
                                do local bg = getProp(pb, "ScootBG"); if bg and bg.SetAlpha then pcall(bg.SetAlpha, bg, 0) end end
                                if addon.BarBorders and addon.BarBorders.ClearBarFrame then addon.BarBorders.ClearBarFrame(pb) end
                                if addon.Borders and addon.Borders.HideAll then addon.Borders.HideAll(pb) end
                                if Util and Util.SetPowerBarTextureOnlyHidden then Util.SetPowerBarTextureOnlyHidden(pb, false) end
                            elseif powerBarHideTextureOnly then
                                local origAlpha = getProp(pb, "origPBAlpha")
                                if origAlpha and pb.SetAlpha then pcall(pb.SetAlpha, pb, origAlpha) end
                                if Util and Util.SetPowerBarTextureOnlyHidden then Util.SetPowerBarTextureOnlyHidden(pb, true) end
                                if addon.BarBorders and addon.BarBorders.ClearBarFrame then addon.BarBorders.ClearBarFrame(pb) end
                                if addon.Borders and addon.Borders.HideAll then addon.Borders.HideAll(pb) end
                            else
                                local origAlpha = getProp(pb, "origPBAlpha")
                                if origAlpha and pb.SetAlpha then pcall(pb.SetAlpha, pb, origAlpha) end
                                if Util and Util.SetPowerBarTextureOnlyHidden then Util.SetPowerBarTextureOnlyHidden(pb, false) end
                            end

                            local colorModePB = cfg.powerBarColorMode or "default"
                            local texKeyPB = cfg.powerBarTexture or "default"
                            applyToBar(pb, texKeyPB, colorModePB, cfg.powerBarTint, "player", "power", unitId)

                            do
                                local function hasBackgroundCustomization()
                                    local texKey = cfg.powerBarBackgroundTexture
                                    if type(texKey) == "string" and texKey ~= "" and texKey ~= "default" then
                                        return true
                                    end
                                    local mode = cfg.powerBarBackgroundColorMode
                                    if type(mode) == "string" and mode ~= "" and mode ~= "default" then
                                        return true
                                    end
                                    local op = cfg.powerBarBackgroundOpacity
                                    local opNum = tonumber(op)
                                    if op ~= nil and opNum ~= nil and opNum ~= 50 then
                                        return true
                                    end
                                    if mode == "custom" and type(cfg.powerBarBackgroundTint) == "table" then
                                        return true
                                    end
                                    return false
                                end
                                if hasBackgroundCustomization() then
                                    local bgTexKeyPB = cfg.powerBarBackgroundTexture or "default"
                                    local bgColorModePB = cfg.powerBarBackgroundColorMode or "default"
                                    local bgOpacityPB = cfg.powerBarBackgroundOpacity or 50
                                    applyBackgroundToBar(pb, bgTexKeyPB, bgColorModePB, cfg.powerBarBackgroundTint, bgOpacityPB, unit, "power")
                                end
                            end

                            if powerBarHideTextureOnly and not powerBarHidden then
                                if Util and Util.SetPowerBarTextureOnlyHidden then Util.SetPowerBarTextureOnlyHidden(pb, true) end
                            end

                            ensureMaskOnBarTexture(pb, resolveBossPowerMask(bossFrame))

                            -- Rectangular overlay to fill bottom-right chip when using custom borders
                            ensureBossRectOverlay(bossFrame, pb, cfg, "power", unitId)

                            -- Power Bar custom border (mirrors Health Bar border settings; supports power-specific overrides)
                            -- BOSS FRAME FIX: Use the same anchor frame pattern as Health Bar for consistency.
                            -- Unlike HealthBar, ManaBar is NOT inside a container - it's directly under TargetFrameContentMain.
                            -- The ManaBar StatusBar should have correct bounds (it's a sibling of HealthBarsContainer).
                            do
                                local styleKey = cfg.powerBarBorderStyle or cfg.healthBarBorderStyle
                                local hiddenEdges = cfg.powerBarBorderHiddenEdges
                                local tintEnabled
                                if cfg.powerBarBorderTintEnable ~= nil then
                                    tintEnabled = not not cfg.powerBarBorderTintEnable
                                else
                                    tintEnabled = not not cfg.healthBarBorderTintEnable
                                end
                                local baseTint = type(cfg.powerBarBorderTintColor) == "table" and cfg.powerBarBorderTintColor or cfg.healthBarBorderTintColor
                                local tintColor = type(baseTint) == "table" and {
                                    baseTint[1] or 1,
                                    baseTint[2] or 1,
                                    baseTint[3] or 1,
                                    baseTint[4] or 1,
                                } or {1, 1, 1, 1}
                                local thickness = tonumber(cfg.powerBarBorderThickness) or tonumber(cfg.healthBarBorderThickness) or 1
                                if thickness < 1 then thickness = 1 elseif thickness > 16 then thickness = 16 end
                                local insetH = (cfg.powerBarBorderInsetH ~= nil) and tonumber(cfg.powerBarBorderInsetH) or (cfg.powerBarBorderInset ~= nil) and tonumber(cfg.powerBarBorderInset) or tonumber(cfg.healthBarBorderInsetH) or tonumber(cfg.healthBarBorderInset) or 0
                                local insetV = (cfg.powerBarBorderInsetV ~= nil) and tonumber(cfg.powerBarBorderInsetV) or (cfg.powerBarBorderInset ~= nil) and tonumber(cfg.powerBarBorderInset) or tonumber(cfg.healthBarBorderInsetV) or tonumber(cfg.healthBarBorderInset) or 0

                                -- Resolve ManaBar for correct bounds
                                local mbResolved = resolveBossManaBar(bossFrame)

                                -- Create or retrieve the anchor frame for border application
                                -- For consistency with Health Bar, use the same pattern even though ManaBar
                                -- may already have correct bounds (it's not inside an oversized container)
                                local anchorFrame = getProp(pb, "bossPowerBorderAnchor")
                                if not anchorFrame then
                                    anchorFrame = CreateFrame("Frame", nil, pb)
                                    anchorFrame:SetFrameLevel((pb:GetFrameLevel() or 0) + 1)
                                    setProp(pb, "bossPowerBorderAnchor", anchorFrame)
                                end

                                -- Anchor to resolved ManaBar bounds if available, else fall back to pb
                                anchorFrame:ClearAllPoints()
                                if mbResolved then
                                    anchorFrame:SetPoint("TOPLEFT", mbResolved, "TOPLEFT", 0, 0)
                                    anchorFrame:SetPoint("BOTTOMRIGHT", mbResolved, "BOTTOMRIGHT", 0, 0)
                                else
                                    anchorFrame:SetAllPoints(pb)
                                end
                                anchorFrame:Show()

                                -- BOSS FRAME CLEANUP: Clear any stale borders on the StatusBar
                                do
                                    local clearTargets = {
                                        bossFrame.manabar,
                                        pb,
                                        pb and pb:GetParent(),
                                    }
                                    for _, target in ipairs(clearTargets) do
                                        -- Don't clear the anchor frame itself (borders are applied here)
                                        if target and target ~= anchorFrame then
                                            if addon.BarBorders and addon.BarBorders.ClearBarFrame then
                                                addon.BarBorders.ClearBarFrame(target)
                                            end
                                            if addon.Borders and addon.Borders.HideAll then
                                                addon.Borders.HideAll(target)
                                            end
                                        end
                                    end
                                end

                                -- Apply border to anchor frame
                                -- Skip border application when power bar is fully hidden.
                                if cfg.useCustomBorders and not powerBarHidden and not powerBarHideTextureOnly then
                                    if styleKey == "none" or styleKey == nil then
                                        if addon.BarBorders and addon.BarBorders.ClearBarFrame then addon.BarBorders.ClearBarFrame(anchorFrame) end
                                        if addon.Borders and addon.Borders.HideAll then addon.Borders.HideAll(anchorFrame) end
                                    else
                                        local styleDef = addon.BarBorders and addon.BarBorders.GetStyle and addon.BarBorders.GetStyle(styleKey)
                                        local color
                                        if tintEnabled then
                                            color = tintColor
                                        else
                                            if styleDef then
                                                color = {1, 1, 1, 1}
                                            else
                                                color = {0, 0, 0, 1}
                                            end
                                        end
                                        -- Clear old borders from anchor frame before applying new
                                        if addon.BarBorders and addon.BarBorders.ClearBarFrame then
                                            addon.BarBorders.ClearBarFrame(anchorFrame)
                                        end
                                        if addon.Borders and addon.Borders.HideAll then
                                            addon.Borders.HideAll(anchorFrame)
                                        end
                                        -- Use ApplySquare for Boss power bar borders (same pattern as health bar)
                                        if addon.Borders and addon.Borders.ApplySquare then
                                            local sqColor = tintEnabled and tintColor or {0, 0, 0, 1}
                                            local baseY = 1
                                            local baseX = 1
                                            local expandY = baseY - insetV
                                            local expandX = baseX - insetH
                                            if expandX < -6 then expandX = -6 elseif expandX > 6 then expandX = 6 end
                                            if expandY < -6 then expandY = -6 elseif expandY > 6 then expandY = 6 end
                                            addon.Borders.ApplySquare(anchorFrame, {
                                                size = thickness,
                                                color = sqColor,
                                                layer = "OVERLAY",
                                                layerSublevel = 3,
                                                expandX = expandX,
                                                expandY = expandY,
                                                skipDimensionCheck = true, -- Anchor frame may be small
                                                hiddenEdges = hiddenEdges,
                                            })
                                        end
                                        ensureTextAndBorderOrdering(unit)
                                    end
                                else
                                    if addon.BarBorders and addon.BarBorders.ClearBarFrame then addon.BarBorders.ClearBarFrame(anchorFrame) end
                                    if addon.Borders and addon.Borders.HideAll then addon.Borders.HideAll(anchorFrame) end
                                end
                            end

                            -- Boss power bars can get refreshed by Blizzard which resets textures.
                            -- Install a hook to re-assert styling after Blizzard updates.
                            local bossState = getState(bossFrame)
                            if _G.hooksecurefunc and bossState and not bossState.bossPowerUpdateHooked then
                                bossState.bossPowerUpdateHooked = true
                                -- Hook the power bar's SetValue which is called on every power change
                                if pb.SetValue and type(pb.SetValue) == "function" then
                                    _G.hooksecurefunc(pb, "SetValue", function()
                                        if isEditModeActive() then return end
                                        local db2 = addon and addon.db and addon.db.profile
                                        if not db2 then return end
                                        local unitFrames2 = rawget(db2, "unitFrames")
                                        local cfgBoss = unitFrames2 and rawget(unitFrames2, "Boss") or nil
                                        if not cfgBoss then return end

                                        -- Re-hide fill texture after Blizzard may have reset it
                                        if cfgBoss.powerBarHideTextureOnly == true and not (cfgBoss.powerBarHidden == true) then
                                            local pbReapply = bossFrame.manabar
                                            if pbReapply and Util and Util.SetPowerBarTextureOnlyHidden then
                                                Util.SetPowerBarTextureOnlyHidden(pbReapply, true)
                                            end
                                            return
                                        end

                                        local texKey = cfgBoss.powerBarTexture or "default"
                                        local colorMode = cfgBoss.powerBarColorMode or "default"
                                        local tint = cfgBoss.powerBarTint

                                        local hasCustomTexture = (type(texKey) == "string" and texKey ~= "" and texKey ~= "default")
                                        local hasCustomColor = (colorMode == "custom" and type(tint) == "table") or (colorMode == "class") or (colorMode == "texture")
                                        if not hasCustomTexture and not hasCustomColor then return end

                                        -- Throttle: skip if a reapply is already pending
                                        local st = getState(bossFrame)
                                        if st and st.bossPowerReapplyPending then return end
                                        if st then st.bossPowerReapplyPending = true end

                                        if _G.C_Timer and _G.C_Timer.After then
                                            _G.C_Timer.After(0, function()
                                                local st2 = getState(bossFrame)
                                                if st2 then st2.bossPowerReapplyPending = nil end
                                                local pbReapply = bossFrame.manabar
                                                if pbReapply then
                                                    local resolvedPath = addon.Media and addon.Media.ResolveBarTexturePath and addon.Media.ResolveBarTexturePath(texKey)
                                                    if resolvedPath and pbReapply.SetStatusBarTexture then
                                                        pcall(pbReapply.SetStatusBarTexture, pbReapply, resolvedPath)
                                                    end
                                                    local tex = pbReapply:GetStatusBarTexture()
                                                    if tex and tex.SetVertexColor then
                                                        local r, g, b, a = 1, 1, 1, 1
                                                        if colorMode == "custom" and type(tint) == "table" then
                                                            r, g, b, a = tint[1] or 1, tint[2] or 1, tint[3] or 1, tint[4] or 1
                                                        elseif colorMode == "class" and addon.GetClassColorRGB then
                                                            local cr, cg, cb = addon.GetClassColorRGB(unitId)
                                                            r, g, b = cr or 1, cg or 1, cb or 1
                                                        elseif colorMode == "texture" then
                                                            r, g, b, a = 1, 1, 1, 1
                                                        end
                                                        pcall(tex.SetVertexColor, tex, r, g, b, a)
                                                    end
                                                end
                                            end)
                                        end
                                    end)
                                end
                            end
                            end -- if not bossHasNoPower
                        end
                end
            end

            -- Boss frame art: Handle all 5 Boss frames (Boss1TargetFrame through Boss5TargetFrame)
            for i = 1, addon.NUM_BOSS_FRAMES do
                local bossFrame = addon.GetBossFrame(i)
                if bossFrame and bossFrame.TargetFrameContainer then
                    local bossFT = bossFrame.TargetFrameContainer.FrameTexture
                    if bossFT then
                        local function computeBossAlpha()
                            local db2 = addon and addon.db and addon.db.profile
                            local unitFrames2 = db2 and rawget(db2, "unitFrames") or nil
                            local cfgBoss = unitFrames2 and rawget(unitFrames2, "Boss") or nil
                            if not cfgBoss then return nil end -- config unreadable: skip (fail closed)
                            return (cfgBoss.useCustomBorders or cfgBoss.healthBarHideBorder) and 0 or 1
                        end
                        applyAlpha(bossFT, computeBossAlpha())
                        hookAlphaEnforcer(bossFT, computeBossAlpha)
                    end
                    -- Also hide the Flash (aggro/threat glow) if present on Boss frames
                    local bossFlash = bossFrame.TargetFrameContainer.Flash
                    if bossFlash then
                        local function computeBossFlashAlpha()
                            local db2 = addon and addon.db and addon.db.profile
                            local unitFrames2 = db2 and rawget(db2, "unitFrames") or nil
                            local cfgBoss = unitFrames2 and rawget(unitFrames2, "Boss") or nil
                            if not cfgBoss then return nil end -- config unreadable: skip (fail closed)
                            return cfgBoss.useCustomBorders and 0 or 1
                        end
                        applyAlpha(bossFlash, computeBossFlashAlpha())
                        hookAlphaEnforcer(bossFlash, computeBossFlashAlpha)
                    end
                end
            end

            return
        end

        local hb = resolveHealthBar(frame, unit)
        if hb then
            local colorModeHB = cfg.healthBarColorMode or "default"
            local texKeyHB = cfg.healthBarTexture or "default"
            local unitId = (unit == "Player" and "player") or (unit == "Target" and "target") or (unit == "Focus" and "focus") or (unit == "Pet" and "pet") or (unit == "TargetOfTarget" and "targettarget") or (unit == "FocusTarget" and "focustarget") or "player"
			-- Avoid applying styling to Target/Focus/ToT/FoT before they exist; Blizzard will reset sizes on first Update
			if (unit == "Target" or unit == "Focus" or unit == "TargetOfTarget" or unit == "FocusTarget") and _G.UnitExists and not _G.UnitExists(unitId) then
				return
			end
			local healthBarHideTextureOnly = (cfg.healthBarHideTextureOnly == true)
			if healthBarHideTextureOnly then
				if Util and Util.SetHealthBarTextureOnlyHidden then
					Util.SetHealthBarTextureOnlyHidden(hb, true)
				end
				-- Clear any custom borders so only text remains
				if addon.BarBorders and addon.BarBorders.ClearBarFrame then
					addon.BarBorders.ClearBarFrame(hb)
				end
				if addon.Borders and addon.Borders.HideAll then
					addon.Borders.HideAll(hb)
				end
			else
				if Util and Util.SetHealthBarTextureOnlyHidden then
					Util.SetHealthBarTextureOnlyHidden(hb, false)
				end
			end
            applyToBar(hb, texKeyHB, colorModeHB, cfg.healthBarTint, unitId, "health", unitId, combatSafe)

            -- Apply background texture and color for Health Bar
            do
                -- IMPORTANT: Default/clean profiles should not change the look of Blizzard's bars.
                -- Only apply the background overlay if the user customized background settings.
                local function hasBackgroundCustomization()
                    local texKey = cfg.healthBarBackgroundTexture
                    if type(texKey) == "string" and texKey ~= "" and texKey ~= "default" then
                        return true
                    end
                    local mode = cfg.healthBarBackgroundColorMode
                    if type(mode) == "string" and mode ~= "" and mode ~= "default" then
                        return true
                    end
                    local op = cfg.healthBarBackgroundOpacity
                    local opNum = tonumber(op)
                    if op ~= nil and opNum ~= nil and opNum ~= 50 then
                        return true
                    end
                    if mode == "custom" and type(cfg.healthBarBackgroundTint) == "table" then
                        return true
                    end
                    return false
                end
                if hasBackgroundCustomization() then
                    local bgTexKeyHB = cfg.healthBarBackgroundTexture or "default"
                    local bgColorModeHB = cfg.healthBarBackgroundColorMode or "default"
                    local bgOpacityHB = cfg.healthBarBackgroundOpacity or 50
                    applyBackgroundToBar(hb, bgTexKeyHB, bgColorModeHB, cfg.healthBarBackgroundTint, bgOpacityHB, unit, "health", combatSafe)
                end
            end

            -- Re-apply texture-only hide after styling (ensures newly created ScootBG is also hidden)
            if healthBarHideTextureOnly then
                if Util and Util.SetHealthBarTextureOnlyHidden then
                    Util.SetHealthBarTextureOnlyHidden(hb, true)
                end
            end

			-- When Target/Focus portraits are hidden, draw a rectangular overlay that fills the
			-- right-side "chip" area using the same texture/tint as the health bar.
			ensureRectHealthOverlay(unit, hb, cfg)
            -- If restoring default texture and no captured original exists, restore to the known stock atlas for this unit
            local isDefaultHB = (texKeyHB == "default" or not addon.Media.ResolveBarTexturePath(texKeyHB))
            if isDefaultHB and not getProp(hb, "ufOrigAtlas") and not getProp(hb, "ufOrigPath") then
				local stockAtlas
				if unit == "Player" then
					stockAtlas = "UI-HUD-UnitFrame-Player-PortraitOn-Bar-Health"
				elseif unit == "Target" then
					stockAtlas = "UI-HUD-UnitFrame-Target-PortraitOn-Bar-Health"
				elseif unit == "Focus" then
					stockAtlas = "UI-HUD-UnitFrame-Target-PortraitOn-Bar-Health" -- Focus reuses Target visuals
				elseif unit == "Pet" then
					stockAtlas = "UI-HUD-UnitFrame-Party-PortraitOn-Bar-Health" -- Pet frame shares party atlas
				elseif unit == "TargetOfTarget" then
					stockAtlas = "UI-HUD-UnitFrame-Party-PortraitOn-Bar-Health" -- ToT shares party atlas
				elseif unit == "FocusTarget" then
					stockAtlas = "UI-HUD-UnitFrame-Party-PortraitOn-Bar-Health" -- FoT shares party atlas
				end
                if stockAtlas then
                    local hbTex = hb.GetStatusBarTexture and hb:GetStatusBarTexture()
                    if hbTex and hbTex.SetAtlas then pcall(hbTex.SetAtlas, hbTex, stockAtlas, true) end
					-- Best-effort: ensure the mask uses the matching atlas
					local mask = resolveHealthMask(unit)
					if mask and mask.SetAtlas then
						local maskAtlas
						if unit == "Player" then
							maskAtlas = "UI-HUD-UnitFrame-Player-PortraitOn-Bar-Health-Mask"
						elseif unit == "Target" or unit == "Focus" then
							maskAtlas = "UI-HUD-UnitFrame-Target-PortraitOn-Bar-Health-Mask"
						elseif unit == "Pet" then
							maskAtlas = "UI-HUD-UnitFrame-Party-PortraitOn-Bar-Health-Mask"
						elseif unit == "TargetOfTarget" then
							maskAtlas = "UI-HUD-UnitFrame-Party-PortraitOn-Bar-Health-Mask" -- ToT shares party mask
						elseif unit == "FocusTarget" then
							maskAtlas = "UI-HUD-UnitFrame-Party-PortraitOn-Bar-Health-Mask" -- FoT shares party mask
						end
						if maskAtlas then pcall(mask.SetAtlas, mask, maskAtlas) end
					end
                    -- Re-apply value-based color after SetAtlas (which resets vertex color to white)
                    if (colorModeHB == "value" or colorModeHB == "valueDark") and addon.BarsTextures and addon.BarsTextures.applyValueBasedColor then
                        addon.BarsTextures.applyValueBasedColor(hb, unitId, nil, colorModeHB == "valueDark")
                    end
				end
			end
			ensureMaskOnBarTexture(hb, resolveHealthMask(unit))
            
            -- Hide/Show Over Absorb Glow (Player/Target/Focus)
            if (unit == "Player" or unit == "Target" or unit == "Focus") and hb and Util and Util.SetOverAbsorbGlowHidden then
                Util.SetOverAbsorbGlowHidden(hb, cfg.healthBarHideOverAbsorbGlow == true)
            end

            -- Hide/Show Heal Prediction (Player/Target/Focus)
            if (unit == "Player" or unit == "Target" or unit == "Focus") and hb and Util and Util.SetHealPredictionHidden then
                Util.SetHealPredictionHidden(hb, cfg.healthBarHideHealPrediction == true)
            end

            -- Hide/Show Health Loss Animation (Player only)
            -- Frame: PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.HealthBarsContainer.PlayerFrameHealthBarAnimatedLoss
            if unit == "Player" and hb and Util and Util.SetHealthLossAnimationHidden then
                Util.SetHealthLossAnimationHidden(hb, cfg.healthBarHideHealthLossAnimation == true)
            end

            -- Health Bar custom border (Health Bar only)
            -- PetFrame is a managed/protected frame. Even innocuous getters (GetWidth, GetFrameLevel)
            -- on PetFrame's health bar can trigger Blizzard internal updates that error on "secret values".
            -- Skip ALL border operations for Pet to guarantee preset/profile application doesn't provoke that path.
            if unit ~= "Pet" and unit ~= "TargetOfTarget" and unit ~= "FocusTarget" and not healthBarHideTextureOnly then
            do
				local styleKey = cfg.healthBarBorderStyle
				local hiddenEdges = cfg.healthBarBorderHiddenEdges
				local tintEnabled = not not cfg.healthBarBorderTintEnable
				local tintColor = type(cfg.healthBarBorderTintColor) == "table" and {
					cfg.healthBarBorderTintColor[1] or 1,
					cfg.healthBarBorderTintColor[2] or 1,
					cfg.healthBarBorderTintColor[3] or 1,
					cfg.healthBarBorderTintColor[4] or 1,
				} or {1, 1, 1, 1}
                local thickness = tonumber(cfg.healthBarBorderThickness) or 1
				if thickness < 1 then thickness = 1 elseif thickness > 16 then thickness = 16 end
                local insetH = tonumber(cfg.healthBarBorderInsetH) or tonumber(cfg.healthBarBorderInset) or 0
                local insetV = tonumber(cfg.healthBarBorderInsetV) or tonumber(cfg.healthBarBorderInset) or 0
				-- Only draw custom border when Use Custom Borders is enabled
				if hb then
					if cfg.useCustomBorders then
						-- Handle style = "none" to explicitly clear any custom border
						if styleKey == "none" or styleKey == nil then
							if addon.BarBorders and addon.BarBorders.ClearBarFrame then addon.BarBorders.ClearBarFrame(hb) end
							if addon.Borders and addon.Borders.HideAll then addon.Borders.HideAll(hb) end
						else
							-- Match Tracked Bars: when tint is disabled use white for textured styles,
							-- and black only for the pixel fallback case.
							local styleDef = addon.BarBorders and addon.BarBorders.GetStyle and addon.BarBorders.GetStyle(styleKey)
							local color
							if tintEnabled then
								color = tintColor
							else
								if styleDef then
									color = {1, 1, 1, 1}
								else
									color = {0, 0, 0, 1}
								end
							end
                            -- Determine border anchor target: use clipping container if height reduction active,
                            -- otherwise a union frame spanning HealthBar + HealthBarsContainer so the border
                            -- matches the overlay on "minus" mobs (shrunken container) AND still wraps
                            -- TempMaxHealthLoss when active.
                            local hbContainer = resolveHealthContainer(frame, unit)
                            local borderAnchorTarget
                            if addon.BarsOverlays and addon.BarsOverlays._ensureBorderUnionAnchor then
                                borderAnchorTarget = addon.BarsOverlays._ensureBorderUnionAnchor(hb, hbContainer, unit) or hbContainer
                            else
                                borderAnchorTarget = hbContainer
                            end
                            local handled = false
                            if addon.BarBorders and addon.BarBorders.ApplyToBarFrame then
								-- Clear any prior holder/state to avoid stale tinting when toggling
								if addon.BarBorders.ClearBarFrame then addon.BarBorders.ClearBarFrame(hb) end
								-- Clear any stale Square borders from previous styling pass (may be on hb or clip container)
								if addon.Borders and addon.Borders.HideAll then
									addon.Borders.HideAll(hb)
									if borderAnchorTarget and borderAnchorTarget ~= hb then addon.Borders.HideAll(borderAnchorTarget) end
								end
                                handled = addon.BarBorders.ApplyToBarFrame(hb, styleKey, {
                                    color = color,
                                    thickness = thickness,
                                    levelOffset = 1, -- just above bar fill; text will be raised above holder
                                    containerParent = (hb and hb:GetParent()) or nil,
                                    insetH = insetH,
                                    insetV = insetV,
                                    anchorTarget = borderAnchorTarget, -- anchor to clipping container if active
                                    hiddenEdges = hiddenEdges,
                                })
							end
                            if not handled then
                                -- Fallback: pixel (square) border drawn with the lightweight helper
								if addon.BarBorders and addon.BarBorders.ClearBarFrame then addon.BarBorders.ClearBarFrame(hb) end
                                if addon.Borders and addon.Borders.ApplySquare then
									local sqColor = tintEnabled and tintColor or {0, 0, 0, 1}
                                    -- Always extend border by 1 pixel to cover any texture bleeding above the frame
                                    local baseY = 1
                                    local baseX = 1
                                    local expandY = baseY - insetV
                                    local expandX = baseX - insetH
                                    if expandX < -6 then expandX = -6 elseif expandX > 6 then expandX = 6 end
                                    if expandY < -6 then expandY = -6 elseif expandY > 6 then expandY = 6 end
                                    -- Pet is already excluded by the outer guard
                                    -- Apply to clipping container if height reduction active, else to health bar
                                    local squareBorderTarget = borderAnchorTarget or hb
                                    addon.Borders.ApplySquare(squareBorderTarget, {
                                        size = thickness,
                                        color = sqColor,
                                        layer = "OVERLAY",
                                        layerSublevel = 3,
                                        expandX = expandX,
                                        expandY = expandY,
                                        hiddenEdges = hiddenEdges,
                                    })
                                end
							end
                            -- Deterministically place border below text and ensure text wins
                            ensureTextAndBorderOrdering(unit)
                            -- Light hook: keep ordering stable on bar resize
                            if hb and not getProp(hb, "ufZOrderHooked") and hb.HookScript then
                                hb:HookScript("OnSizeChanged", function()
                                    if isEditModeActive() then return end
                                    if InCombatLockdown and InCombatLockdown() then
                                        return
                                    end
                                    ensureTextAndBorderOrdering(unit)
                                end)
                                setProp(hb, "ufZOrderHooked", true)
                            end
						end
					else
						-- Custom borders disabled -> ensure cleared
						if addon.BarBorders and addon.BarBorders.ClearBarFrame then addon.BarBorders.ClearBarFrame(hb) end
						if addon.Borders and addon.Borders.HideAll then addon.Borders.HideAll(hb) end
					end
				end
            end
            end -- Pet guard

            -- Lightweight persistence hooks for Player Health Bar:
            -- Texture: keep custom texture applied if Blizzard swaps StatusBarTexture.
            -- Color: keep Foreground Color applied if Blizzard calls SetStatusBarColor.
            if unit == "Player" and _G.hooksecurefunc then
                -- Texture hook: reapply custom texture when Blizzard resets it
                if not getProp(hb, "healthTextureHooked") then
                    setProp(hb, "healthTextureHooked", true)
                    _G.hooksecurefunc(hb, "SetStatusBarTexture", function(self, ...)
                        if isEditModeActive() then return end
                        -- Ignore Scoot's own writes to avoid recursion.
                        if getProp(self, "ufInternalTextureWrite") then
                            return
                        end
                        -- Skip during combat to avoid taint on protected StatusBar.
                        if InCombatLockdown and InCombatLockdown() then return end
                        local db = addon and addon.db and addon.db.profile
                        if not db then return end
                        local unitFrames = rawget(db, "unitFrames")
                        local cfgP = unitFrames and rawget(unitFrames, "Player") or nil
                        if not cfgP then return end
                        local texKey = cfgP.healthBarTexture or "default"
                        local colorMode = cfgP.healthBarColorMode or "default"
                        local tint = cfgP.healthBarTint
                        -- Re-apply if custom texture OR "value"/"valueDark" color mode (Blizzard's new texture needs coloring)
                        local hasCustomTexture = (type(texKey) == "string" and texKey ~= "" and texKey ~= "default")
                        local needsValueColor = (colorMode == "value" or colorMode == "valueDark")
                        if not hasCustomTexture and not needsValueColor then
                            return
                        end
                        -- For value mode with default texture, just re-apply color to the new texture
                        -- Use small delay to ensure color is applied AFTER Blizzard's code completes
                        if needsValueColor and not hasCustomTexture then
                            local useDark = (colorMode == "valueDark")
                            C_Timer.After(0, function()
                                if addon.BarsTextures and addon.BarsTextures.applyValueBasedColor then
                                    addon.BarsTextures.applyValueBasedColor(self, "player", nil, useDark)
                                end
                            end)
                        else
                            applyToBar(self, texKey, colorMode, tint, "player", "health", "player")
                        end
                    end)
                end
                -- Color hook: reapply custom color when Blizzard resets it
                if not getProp(hb, "healthColorHooked") then
                    setProp(hb, "healthColorHooked", true)
                    _G.hooksecurefunc(hb, "SetStatusBarColor", function(self, ...)
                        if isEditModeActive() then return end
                        -- Skip if Scoot is calling SetStatusBarColor (from applyValueBasedColor)
                        if getProp(self, "applyingValueBasedColor") then return end
                        -- CRITICAL: Do NOT call applyToBar during combat - it calls SetStatusBarTexture/SetVertexColor
                        -- on the protected StatusBar, which taints it and causes "blocked from an action" errors.
                        if InCombatLockdown and InCombatLockdown() then return end
                        local db = addon and addon.db and addon.db.profile
                        if not db then return end
                        local unitFrames = rawget(db, "unitFrames")
                        local cfgP = unitFrames and rawget(unitFrames, "Player") or nil
                        if not cfgP then return end
                        local texKey = cfgP.healthBarTexture or "default"
                        local colorMode = cfgP.healthBarColorMode or "default"
                        local tint = cfgP.healthBarTint
                        local unitIdP = "player"
                        -- Only do work when the user has customized either texture or color;
                        -- default settings can safely follow Blizzard's behavior.
                        local hasCustomTexture = (type(texKey) == "string" and texKey ~= "" and texKey ~= "default")
                        local hasCustomColor = (colorMode == "custom" and type(tint) == "table") or (colorMode == "class") or (colorMode == "value") or (colorMode == "valueDark")
                        if not hasCustomTexture and not hasCustomColor then
                            return
                        end
                        applyToBar(self, texKey, colorMode, tint, "player", "health", unitIdP)
                    end)
                end
            end

            -- Lightweight persistence hooks for Target-of-Target Health Bar:
            -- Blizzard can reset the ToT StatusBar's fill texture during rapid updates (often in combat).
            -- Re-asserts the configured texture/color by writing to the underlying Texture region
            -- (avoids calling SetStatusBarTexture again inside a secure callstack).
            if unit == "TargetOfTarget" and _G.hooksecurefunc then
                if not getProp(hb, "toTHealthTextureHooked") then
                    setProp(hb, "toTHealthTextureHooked", true)
                    _G.hooksecurefunc(hb, "SetStatusBarTexture", function(self, ...)
                        if isEditModeActive() then return end
                        -- Ignore Scoot's own writes to avoid feedback loops.
                        if getProp(self, "ufInternalTextureWrite") then
                            return
                        end

                        local db = addon and addon.db and addon.db.profile
                        if not db then return end
                        local unitFrames = rawget(db, "unitFrames")
                        local cfgT = unitFrames and rawget(unitFrames, "TargetOfTarget") or nil
                        if not cfgT then return end

                        local texKey = cfgT.healthBarTexture or "default"
                        local colorMode = cfgT.healthBarColorMode or "default"
                        local tint = cfgT.healthBarTint

                        local hasCustomTexture = (type(texKey) == "string" and texKey ~= "" and texKey ~= "default")
                        local hasCustomColor = (colorMode == "custom" and type(tint) == "table") or (colorMode == "class") or (colorMode == "texture")
                        if not hasCustomTexture and not hasCustomColor then
                            return
                        end

                        -- Avoid any writes during combat; defer until after combat.
                        if InCombatLockdown and InCombatLockdown() then
                            queueUnitFrameTextureReapply("TargetOfTarget")
                            return
                        end

                        -- Throttle: coalesce rapid refreshes into a single 0s re-apply.
                        if getProp(self, "toTReapplyPending") then
                            return
                        end
                        setProp(self, "toTReapplyPending", true)
                        if _G.C_Timer and _G.C_Timer.After and addon.ApplyUnitFrameBarTexturesFor then
                            _G.C_Timer.After(0, function()
                                setProp(self, "toTReapplyPending", nil)
                                addon.ApplyUnitFrameBarTexturesFor("TargetOfTarget")
                            end)
                        elseif addon.ApplyUnitFrameBarTexturesFor then
                            setProp(self, "toTReapplyPending", nil)
                            addon.ApplyUnitFrameBarTexturesFor("TargetOfTarget")
                        end
                    end)
                end

                if not getProp(hb, "toTHealthColorHooked") then
                    setProp(hb, "toTHealthColorHooked", true)
                    _G.hooksecurefunc(hb, "SetStatusBarColor", function(self, ...)
                        if isEditModeActive() then return end
                        local db = addon and addon.db and addon.db.profile
                        if not db then return end
                        local unitFrames = rawget(db, "unitFrames")
                        local cfgT = unitFrames and rawget(unitFrames, "TargetOfTarget") or nil
                        if not cfgT then return end

                        local texKey = cfgT.healthBarTexture or "default"
                        local colorMode = cfgT.healthBarColorMode or "default"
                        local tint = cfgT.healthBarTint

                        local hasCustomTexture = (type(texKey) == "string" and texKey ~= "" and texKey ~= "default")
                        local hasCustomColor = (colorMode == "custom" and type(tint) == "table") or (colorMode == "class") or (colorMode == "texture")
                        if not hasCustomTexture and not hasCustomColor then
                            return
                        end

                        if InCombatLockdown and InCombatLockdown() then
                            queueUnitFrameTextureReapply("TargetOfTarget")
                            return
                        end

                        if getProp(self, "toTReapplyPending") then
                            return
                        end
                        setProp(self, "toTReapplyPending", true)
                        if _G.C_Timer and _G.C_Timer.After and addon.ApplyUnitFrameBarTexturesFor then
                            _G.C_Timer.After(0, function()
                                setProp(self, "toTReapplyPending", nil)
                                addon.ApplyUnitFrameBarTexturesFor("TargetOfTarget")
                            end)
                        elseif addon.ApplyUnitFrameBarTexturesFor then
                            setProp(self, "toTReapplyPending", nil)
                            addon.ApplyUnitFrameBarTexturesFor("TargetOfTarget")
                        end
                    end)
                end
            end

            -- Lightweight persistence hooks for Focus-Target Health Bar:
            -- Blizzard can reset the FoT StatusBar's fill texture during rapid updates (often in combat).
            -- Re-asserts the configured texture/color by writing to the underlying Texture region
            -- (avoids calling SetStatusBarTexture again inside a secure callstack).
            if unit == "FocusTarget" and _G.hooksecurefunc then
                if not getProp(hb, "foTHealthTextureHooked") then
                    setProp(hb, "foTHealthTextureHooked", true)
                    _G.hooksecurefunc(hb, "SetStatusBarTexture", function(self, ...)
                        if isEditModeActive() then return end
                        -- Ignore Scoot's own writes to avoid feedback loops.
                        if getProp(self, "ufInternalTextureWrite") then
                            return
                        end

                        local db = addon and addon.db and addon.db.profile
                        if not db then return end
                        local unitFrames = rawget(db, "unitFrames")
                        local cfgF = unitFrames and rawget(unitFrames, "FocusTarget") or nil
                        if not cfgF then return end

                        local texKey = cfgF.healthBarTexture or "default"
                        local colorMode = cfgF.healthBarColorMode or "default"
                        local tint = cfgF.healthBarTint

                        local hasCustomTexture = (type(texKey) == "string" and texKey ~= "" and texKey ~= "default")
                        local hasCustomColor = (colorMode == "custom" and type(tint) == "table") or (colorMode == "class") or (colorMode == "texture")
                        if not hasCustomTexture and not hasCustomColor then
                            return
                        end

                        -- Avoid any writes during combat; defer until after combat.
                        if InCombatLockdown and InCombatLockdown() then
                            queueUnitFrameTextureReapply("FocusTarget")
                            return
                        end

                        -- Throttle: coalesce rapid refreshes into a single 0s re-apply.
                        if getProp(self, "foTReapplyPending") then
                            return
                        end
                        setProp(self, "foTReapplyPending", true)
                        if _G.C_Timer and _G.C_Timer.After and addon.ApplyUnitFrameBarTexturesFor then
                            _G.C_Timer.After(0, function()
                                setProp(self, "foTReapplyPending", nil)
                                addon.ApplyUnitFrameBarTexturesFor("FocusTarget")
                            end)
                        elseif addon.ApplyUnitFrameBarTexturesFor then
                            setProp(self, "foTReapplyPending", nil)
                            addon.ApplyUnitFrameBarTexturesFor("FocusTarget")
                        end
                    end)
                end

                if not getProp(hb, "foTHealthColorHooked") then
                    setProp(hb, "foTHealthColorHooked", true)
                    _G.hooksecurefunc(hb, "SetStatusBarColor", function(self, ...)
                        if isEditModeActive() then return end
                        local db = addon and addon.db and addon.db.profile
                        if not db then return end
                        local unitFrames = rawget(db, "unitFrames")
                        local cfgF = unitFrames and rawget(unitFrames, "FocusTarget") or nil
                        if not cfgF then return end

                        local texKey = cfgF.healthBarTexture or "default"
                        local colorMode = cfgF.healthBarColorMode or "default"
                        local tint = cfgF.healthBarTint

                        local hasCustomTexture = (type(texKey) == "string" and texKey ~= "" and texKey ~= "default")
                        local hasCustomColor = (colorMode == "custom" and type(tint) == "table") or (colorMode == "class") or (colorMode == "texture")
                        if not hasCustomTexture and not hasCustomColor then
                            return
                        end

                        if InCombatLockdown and InCombatLockdown() then
                            queueUnitFrameTextureReapply("FocusTarget")
                            return
                        end

                        if getProp(self, "foTReapplyPending") then
                            return
                        end
                        setProp(self, "foTReapplyPending", true)
                        if _G.C_Timer and _G.C_Timer.After and addon.ApplyUnitFrameBarTexturesFor then
                            _G.C_Timer.After(0, function()
                                setProp(self, "foTReapplyPending", nil)
                                addon.ApplyUnitFrameBarTexturesFor("FocusTarget")
                            end)
                        elseif addon.ApplyUnitFrameBarTexturesFor then
                            setProp(self, "foTReapplyPending", nil)
                            addon.ApplyUnitFrameBarTexturesFor("FocusTarget")
                        end
                    end)
                end
            end
		end

        local pb = resolvePowerBar(frame, unit)
        if pb then
            -- Cache combat state once for this styling pass. Avoid all geometry
            -- changes (width/height/anchors/offsets) while in combat to prevent
            -- taint on protected unit frames (TargetFrameToT:Show() taint path).
            local inCombat = InCombatLockdown and InCombatLockdown()
			local powerBarHidden = (cfg.powerBarHidden == true)
			local powerBarHideTextureOnly = (cfg.powerBarHideTextureOnly == true)

			-- Capture original alpha once for restoration when the bar is un-hidden.
			if pb.GetAlpha and getProp(pb, "origPBAlpha") == nil then
				local ok, a = pcall(pb.GetAlpha, pb)
				setProp(pb, "origPBAlpha", ok and (a or 1) or 1)
			end

			-- When the user chooses to hide the Power Bar:
			-- - Fade the StatusBar frame to alpha 0 so the fill/background vanish.
			-- - Hide any Scoot-drawn borders/backgrounds associated with this bar.
			if powerBarHidden then
				if pb.SetAlpha then
					pcall(pb.SetAlpha, pb, 0)
				end
				do local bg = getProp(pb, "ScootBG"); if bg and bg.SetAlpha then pcall(bg.SetAlpha, bg, 0) end end
				if addon.BarBorders and addon.BarBorders.ClearBarFrame then
					addon.BarBorders.ClearBarFrame(pb)
				end
				if addon.Borders and addon.Borders.HideAll then
					addon.Borders.HideAll(pb)
				end
				-- Ensure texture-only mode is disabled when full bar is hidden
				if Util and Util.SetPowerBarTextureOnlyHidden then
					Util.SetPowerBarTextureOnlyHidden(pb, false)
				end
				-- Also hide the power overlay if present
				local pbSt = getState(pb)
				if pbSt and pbSt.powerFill then pbSt.powerFill:Hide() end
			elseif powerBarHideTextureOnly then
				-- Number-only display: Hide the bar texture/fill while keeping text visible.
				-- Use the utility function which installs persistent hooks to survive combat.
				-- Restore bar frame alpha first (in case user toggled from full-hide to texture-only).
				local origAlpha = getProp(pb, "origPBAlpha")
				if origAlpha and pb.SetAlpha then
					pcall(pb.SetAlpha, pb, origAlpha)
				end

				-- Use persistent utility to hide textures (installs hooks that survive combat)
				if Util and Util.SetPowerBarTextureOnlyHidden then
					Util.SetPowerBarTextureOnlyHidden(pb, true)
				end

				-- Clear any custom borders so only text remains
				if addon.BarBorders and addon.BarBorders.ClearBarFrame then
					addon.BarBorders.ClearBarFrame(pb)
				end
				if addon.Borders and addon.Borders.HideAll then
					addon.Borders.HideAll(pb)
				end
				-- Also hide the power overlay if present
				local pbSt = getState(pb)
				if pbSt and pbSt.powerFill then pbSt.powerFill:Hide() end
			else
				-- Restore alpha when coming back from a hidden state so the bar is visible again.
				local origAlpha = getProp(pb, "origPBAlpha")
				if origAlpha and pb.SetAlpha then
					pcall(pb.SetAlpha, pb, origAlpha)
				end
				-- Disable texture-only hiding (restores texture visibility)
				if Util and Util.SetPowerBarTextureOnlyHidden then
					Util.SetPowerBarTextureOnlyHidden(pb, false)
				end
			end
            local colorModePB = cfg.powerBarColorMode or "default"
            local texKeyPB = cfg.powerBarTexture or "default"
            local unitId = (unit == "Player" and "player") or (unit == "Target" and "target") or (unit == "Focus" and "focus") or (unit == "Pet" and "pet") or (unit == "TargetOfTarget" and "targettarget") or (unit == "FocusTarget" and "focustarget") or "player"

            -- Use the combat-safe power overlay when non-default settings are configured.
            -- The overlay is addon-owned and immune to Blizzard's combat texture resets.
            ensureRectPowerOverlay(unit, pb, cfg)

            local pbSt = getState(pb)
            if not (pbSt and pbSt.powerOverlayActive) then
                -- Overlay not active (default+default): use legacy passthrough
                applyToBar(pb, texKeyPB, colorModePB, cfg.powerBarTint, unitId, "power", unitId, combatSafe)
            end

            -- Apply background texture and color for Power Bar
            do
                -- IMPORTANT: Default/clean profiles should not change the look of Blizzard's bars.
                -- Only apply the background overlay if the user customized background settings.
                local function hasBackgroundCustomization()
                    local texKey = cfg.powerBarBackgroundTexture
                    if type(texKey) == "string" and texKey ~= "" and texKey ~= "default" then
                        return true
                    end
                    local mode = cfg.powerBarBackgroundColorMode
                    if type(mode) == "string" and mode ~= "" and mode ~= "default" then
                        return true
                    end
                    local op = cfg.powerBarBackgroundOpacity
                    local opNum = tonumber(op)
                    if op ~= nil and opNum ~= nil and opNum ~= 50 then
                        return true
                    end
                    if mode == "custom" and type(cfg.powerBarBackgroundTint) == "table" then
                        return true
                    end
                    return false
                end
                if hasBackgroundCustomization() then
                    local bgTexKeyPB = cfg.powerBarBackgroundTexture or "default"
                    local bgColorModePB = cfg.powerBarBackgroundColorMode or "default"
                    local bgOpacityPB = cfg.powerBarBackgroundOpacity or 50
                    applyBackgroundToBar(pb, bgTexKeyPB, bgColorModePB, cfg.powerBarBackgroundTint, bgOpacityPB, unit, "power", combatSafe)
                end
            end
            
            -- Re-apply texture-only hide after styling (ensures newly created ScootBG is also hidden)
            if powerBarHideTextureOnly and not powerBarHidden then
                if Util and Util.SetPowerBarTextureOnlyHidden then
                    Util.SetPowerBarTextureOnlyHidden(pb, true)
                end
            end
            
            ensureMaskOnBarTexture(pb, resolvePowerMask(unit))

            -- When texture-only hide is enabled, also hide animations/feedback/spark (they'd look weird floating)
            local hideAllVisuals = powerBarHidden or powerBarHideTextureOnly
            
            if unit == "Player" and Util and Util.SetFullPowerSpikeHidden then
                Util.SetFullPowerSpikeHidden(pb, cfg.powerBarHideFullSpikes == true or hideAllVisuals)
            end

            -- Hide power feedback animation (Builder/Spender flash when power is spent/gained)
            if unit == "Player" and Util and Util.SetPowerFeedbackHidden then
                Util.SetPowerFeedbackHidden(pb, cfg.powerBarHideFeedback == true or hideAllVisuals)
            end

            -- Hide power bar spark (e.g., Elemental Shaman Maelstrom indicator)
            if unit == "Player" and Util and Util.SetPowerBarSparkHidden then
                Util.SetPowerBarSparkHidden(pb, cfg.powerBarHideSpark == true or hideAllVisuals)
            end

            -- Hide mana cost prediction overlay (shows predicted power cost of current spell)
            if unit == "Player" and Util and Util.SetManaCostPredictionHidden then
                Util.SetManaCostPredictionHidden(pb, cfg.powerBarHideManaCostPrediction == true or hideAllVisuals)
            end

            -- Lightweight persistence hooks for Player Power Bar:
            --  - Texture: keep custom texture applied if Blizzard swaps StatusBarTexture.
            --  - Color:   keep Foreground Color (default/class/custom) applied if Blizzard calls SetStatusBarColor.
            -- IMPORTANT: Do NOT re-apply during combat. Even "cosmetic-only" calls like
            -- SetStatusBarTexture/SetVertexColor on protected unitframe StatusBars can taint the
            -- execution context and later surface as blocked calls in unrelated Blizzard code paths
            -- (e.g., AlternatePowerBar:Hide()).
            --
            -- Also IMPORTANT: Defer work with C_Timer.After(0) to break Blizzard's execution chain
            -- to break Blizzard's execution chain and avoid taint propagation.
            if unit == "Player" and _G.hooksecurefunc then
                if not getProp(pb, "powerTextureHooked") then
                    setProp(pb, "powerTextureHooked", true)
                    _G.hooksecurefunc(pb, "SetStatusBarTexture", function(self, ...)
                        if isEditModeActive() then return end
                        -- Ignore Scoot's own writes to avoid recursion.
                        if getProp(self, "ufInternalTextureWrite") then
                            return
                        end
                        -- When overlay is active, it handles everything (combat-safe).
                        -- Just re-anchor and re-hide the new fill texture.
                        local st = getState(self)
                        if st and st.powerOverlayActive then
                            updateRectPowerOverlay("Player", self)
                            local newTex = self:GetStatusBarTexture()
                            if newTex then pcall(newTex.SetAlpha, newTex, 0) end
                            return
                        end
                        if InCombatLockdown and InCombatLockdown() then
                            queuePowerBarReapply("Player")
                            return
                        end

                        -- Throttle: coalesce rapid texture resets into a single 0s re-apply.
                        if getProp(self, "powerReapplyPending") then
                            return
                        end
                        setProp(self, "powerReapplyPending", true)

                        local bar = self
                        if _G.C_Timer and _G.C_Timer.After then
                            _G.C_Timer.After(0, function()
                                if not bar then return end
                                setProp(bar, "powerReapplyPending", nil)
                                if InCombatLockdown and InCombatLockdown() then
                                    queuePowerBarReapply("Player")
                                    return
                                end
                                local db = addon and addon.db and addon.db.profile
                                if not db then return end
                                local unitFrames = rawget(db, "unitFrames")
                                local cfgP = unitFrames and rawget(unitFrames, "Player") or nil
                                if not cfgP then return end
                                local texKey = cfgP.powerBarTexture or "default"
                                local colorMode = cfgP.powerBarColorMode or "default"
                                local tint = cfgP.powerBarTint
                                -- Only re-apply if the user has configured a non-default texture.
                                if not (type(texKey) == "string" and texKey ~= "" and texKey ~= "default") then
                                    return
                                end
                                applyToBar(bar, texKey, colorMode, tint, "player", "power", "player")
                                -- Re-assert texture-only hide after any texture swap. The hide feature
                                -- attaches to the current fill/background textures, so a SetStatusBarTexture
                                -- can create a fresh texture that needs to be re-hidden.
                                if Util and Util.SetPowerBarTextureOnlyHidden and cfgP.powerBarHideTextureOnly == true and not (cfgP.powerBarHidden == true) then
                                    Util.SetPowerBarTextureOnlyHidden(bar, true)
                                end
                            end)
                        else
                            setProp(self, "powerReapplyPending", nil)
                        end
                    end)
                end
                if not getProp(pb, "powerColorHooked") then
                    setProp(pb, "powerColorHooked", true)
                    _G.hooksecurefunc(pb, "SetStatusBarColor", function(self, ...)
                        if isEditModeActive() then return end
                        -- When overlay is active, it handles color sync directly
                        -- (the sync hook in ensureRectPowerOverlay updates vertex color).
                        local st = getState(self)
                        if st and st.powerOverlayActive then
                            return
                        end
                        if InCombatLockdown and InCombatLockdown() then
                            queuePowerBarReapply("Player")
                            return
                        end

                        if getProp(self, "powerReapplyPending") then
                            return
                        end
                        setProp(self, "powerReapplyPending", true)

                        local bar = self
                        if _G.C_Timer and _G.C_Timer.After then
                            _G.C_Timer.After(0, function()
                                if not bar then return end
                                setProp(bar, "powerReapplyPending", nil)
                                if InCombatLockdown and InCombatLockdown() then
                                    queuePowerBarReapply("Player")
                                    return
                                end
                                local db = addon and addon.db and addon.db.profile
                                if not db then return end
                                local unitFrames = rawget(db, "unitFrames")
                                local cfgP = unitFrames and rawget(unitFrames, "Player") or nil
                                if not cfgP then return end
                                local texKey = cfgP.powerBarTexture or "default"
                                local colorMode = cfgP.powerBarColorMode or "default"
                                local tint = cfgP.powerBarTint

                                -- If color mode is "texture", the user wants the texture's original colors;
                                -- in that case Blizzard's SetStatusBarColor stands.
                                if colorMode == "texture" then
                                    return
                                end

                                -- Only do work when the user has customized either texture or color;
                                -- default settings can safely follow Blizzard's behavior.
                                local hasCustomTexture = (type(texKey) == "string" and texKey ~= "" and texKey ~= "default")
                                local hasCustomColor = (colorMode == "custom" and type(tint) == "table") or (colorMode == "class")
                                if not hasCustomTexture and not hasCustomColor then
                                    return
                                end

                                applyToBar(bar, texKey, colorMode, tint, "player", "power", "player")
                                -- Re-assert texture-only hide after any styling pass that may refresh textures.
                                if Util and Util.SetPowerBarTextureOnlyHidden and cfgP.powerBarHideTextureOnly == true and not (cfgP.powerBarHidden == true) then
                                    Util.SetPowerBarTextureOnlyHidden(bar, true)
                                end
                            end)
                        else
                            setProp(self, "powerReapplyPending", nil)
                        end
                    end)
                end
            end

            -- Alternate Power Bar styling (Player-only, class/spec gated)
            if unit == "Player" and addon.UnitFrames_PlayerHasAlternatePowerBar and addon.UnitFrames_PlayerHasAlternatePowerBar() then
                local apb = resolveAlternatePowerBar()
                if apb then
                    -- Zero‑Touch: only style Alternate Power Bar when explicitly configured.
                    local acfg = rawget(cfg, "altPowerBar")
                    if acfg then

                    -- Optional hide toggle
                    local altHidden = (acfg.hidden == true)
                    if apb.GetAlpha and getProp(apb, "origAltAlpha") == nil then
                        local ok, a = pcall(apb.GetAlpha, apb)
                        setProp(apb, "origAltAlpha", ok and (a or 1) or 1)
                    end
                    if altHidden then
                        if apb.SetAlpha then pcall(apb.SetAlpha, apb, 0) end
                    else
                        local origAlpha = getProp(apb, "origAltAlpha")
                        if origAlpha and apb.SetAlpha then
                            pcall(apb.SetAlpha, apb, origAlpha)
                        end
                    end

                    -- Foreground texture / color
                    local altTexKey = acfg.texture or "default"
                    local altColorMode = acfg.colorMode or "default"
                    local altTint = acfg.tint
                    applyToBar(apb, altTexKey, altColorMode, altTint, "player", "altpower", "player")

                    -- Background texture / color / opacity
                    local altBgTexKey = acfg.backgroundTexture or "default"
                    local altBgColorMode = acfg.backgroundColorMode or "default"
                    local altBgOpacity = acfg.backgroundOpacity or 50
                    applyBackgroundToBar(apb, altBgTexKey, altBgColorMode, acfg.backgroundTint, altBgOpacity, unit, "altpower")

                    -- Hide texture only (bar visible=false but text visible=true)
                    local altHideTextureOnly = (acfg.hideTextureOnly == true)
                    if Util and Util.SetPowerBarTextureOnlyHidden then
                        Util.SetPowerBarTextureOnlyHidden(apb, altHideTextureOnly and not altHidden)
                    end

                    -- Clear custom borders when texture-only hide is enabled (so only text remains)
                    if altHideTextureOnly and not altHidden then
                        if addon.BarBorders and addon.BarBorders.ClearBarFrame then
                            addon.BarBorders.ClearBarFrame(apb)
                        end
                        if addon.Borders and addon.Borders.HideAll then
                            addon.Borders.HideAll(apb)
                        end
                    end

                    -- Determine if all visuals should be hidden (when bar is fully hidden or texture-only hidden)
                    local hideAllVisuals = altHidden or altHideTextureOnly

                    -- Full power spike animations
                    if Util and Util.SetFullPowerSpikeHidden then
                        Util.SetFullPowerSpikeHidden(apb, acfg.hideFullSpikes == true or hideAllVisuals)
                    end

                    -- Power feedback flash
                    if Util and Util.SetPowerFeedbackHidden then
                        Util.SetPowerFeedbackHidden(apb, acfg.hideFeedback == true or hideAllVisuals)
                    end

                    -- Spark/glow indicator
                    if Util and Util.SetPowerBarSparkHidden then
                        Util.SetPowerBarSparkHidden(apb, acfg.hideSpark == true or hideAllVisuals)
                    end

                    -- Mana cost prediction overlay
                    if Util and Util.SetManaCostPredictionHidden then
                        Util.SetManaCostPredictionHidden(apb, acfg.hideManaCostPrediction == true or hideAllVisuals)
                    end

                    -- Custom border (shares global Use Custom Borders; Alt Power has its own style/tint/thickness/inset)
                    do
                        -- Global unit-frame switch; borders only draw when this is enabled.
                        -- Skip borders when bar is hidden or texture-only mode (only text should remain).
                        local useCustomBorders = not not cfg.useCustomBorders
                        if useCustomBorders and not altHidden and not altHideTextureOnly then
                            -- Style resolution: prefer Alternate Power–specific, then Power, then Health.
                            local styleKey = acfg.borderStyle
                                or cfg.powerBarBorderStyle
                                or cfg.healthBarBorderStyle
                            local hiddenEdges = acfg.borderHiddenEdges
                                or cfg.powerBarBorderHiddenEdges
                                or cfg.healthBarBorderHiddenEdges

                            -- Tint enable: prefer Alternate Power–specific, then Power, then Health.
                            local tintEnabled
                            if acfg.borderTintEnable ~= nil then
                                tintEnabled = not not acfg.borderTintEnable
                            elseif cfg.powerBarBorderTintEnable ~= nil then
                                tintEnabled = not not cfg.powerBarBorderTintEnable
                            else
                                tintEnabled = not not cfg.healthBarBorderTintEnable
                            end

                            -- Tint color: prefer Alternate Power–specific, then Power, then Health.
                            local baseTint = type(acfg.borderTintColor) == "table" and acfg.borderTintColor
                                or cfg.powerBarBorderTintColor
                                or cfg.healthBarBorderTintColor
                            local tintColor = type(baseTint) == "table" and {
                                baseTint[1] or 1,
                                baseTint[2] or 1,
                                baseTint[3] or 1,
                                baseTint[4] or 1,
                            } or { 1, 1, 1, 1 }

                            -- Thickness / inset: prefer Alternate Power–specific, then Power, then Health.
                            local thickness = tonumber(acfg.borderThickness)
                                or tonumber(cfg.powerBarBorderThickness)
                                or tonumber(cfg.healthBarBorderThickness)
                                or 1
                            if thickness < 1 then thickness = 1 elseif thickness > 16 then thickness = 16 end

                            local insetH, insetV
                            if acfg.borderInsetH ~= nil or acfg.borderInsetV ~= nil then
                                insetH = tonumber(acfg.borderInsetH) or tonumber(acfg.borderInset) or 0
                                insetV = tonumber(acfg.borderInsetV) or tonumber(acfg.borderInset) or 0
                            elseif cfg.powerBarBorderInsetH ~= nil or cfg.powerBarBorderInsetV ~= nil or cfg.powerBarBorderInset ~= nil then
                                insetH = tonumber(cfg.powerBarBorderInsetH) or tonumber(cfg.powerBarBorderInset) or 0
                                insetV = tonumber(cfg.powerBarBorderInsetV) or tonumber(cfg.powerBarBorderInset) or 0
                            else
                                insetH = tonumber(cfg.healthBarBorderInsetH) or tonumber(cfg.healthBarBorderInset) or 0
                                insetV = tonumber(cfg.healthBarBorderInsetV) or tonumber(cfg.healthBarBorderInset) or 0
                            end

                            if styleKey == "none" or styleKey == nil then
                                if addon.BarBorders and addon.BarBorders.ClearBarFrame then addon.BarBorders.ClearBarFrame(apb) end
                                if addon.Borders and addon.Borders.HideAll then addon.Borders.HideAll(apb) end
                            else
                                local styleDef = addon.BarBorders and addon.BarBorders.GetStyle and addon.BarBorders.GetStyle(styleKey)
                                local color
                                if tintEnabled then
                                    color = tintColor
                                else
                                    if styleDef then
                                        color = { 1, 1, 1, 1 }
                                    else
                                        color = { 0, 0, 0, 1 }
                                    end
                                end

                                local handled = false
                                if addon.BarBorders and addon.BarBorders.ApplyToBarFrame then
                                    if addon.BarBorders.ClearBarFrame then addon.BarBorders.ClearBarFrame(apb) end
                                    handled = addon.BarBorders.ApplyToBarFrame(apb, styleKey, {
                                        color = color,
                                        thickness = thickness,
                                        levelOffset = 1,
                                        containerParent = (apb and apb:GetParent()) or nil,
                                        insetH = insetH,
                                        insetV = insetV,
                                        hiddenEdges = hiddenEdges,
                                    })
                                end

                                if not handled then
                                    if addon.BarBorders and addon.BarBorders.ClearBarFrame then addon.BarBorders.ClearBarFrame(apb) end
                                    if addon.Borders and addon.Borders.ApplySquare then
                                        local sqColor = tintEnabled and tintColor or { 0, 0, 0, 1 }
                                        local baseY = (thickness <= 1) and 0 or 1
                                        local baseX = 1
                                        local expandY = baseY - insetV
                                        local expandX = baseX - insetH
                                        if expandX < -6 then expandX = -6 elseif expandX > 6 then expandX = 6 end
                                        if expandY < -6 then expandY = -6 elseif expandY > 6 then expandY = 6 end
                                        addon.Borders.ApplySquare(apb, {
                                            size = thickness,
                                            color = sqColor,
                                            layer = "OVERLAY",
                                            layerSublevel = 3,
                                            expandX = expandX,
                                            expandY = expandY,
                                            hiddenEdges = hiddenEdges,
                                        })
                                    end
                                end
                            end
                        else
                            -- Global custom borders disabled: clear any previous Alternate Power border.
                            if addon.BarBorders and addon.BarBorders.ClearBarFrame then addon.BarBorders.ClearBarFrame(apb) end
                            if addon.Borders and addon.Borders.HideAll then addon.Borders.HideAll(apb) end
                        end
                    end

                    -- % Text and Value Text (AlternatePowerBar.LeftText / RightText)
                    do
                        local leftFS = apb.LeftText
                        local rightFS = apb.RightText
                        -- Also resolve the center TextString (used in NUMERIC display mode)
                        -- Ensures styling persists when Blizzard switches between BOTH and NUMERIC modes
                        local textStringFS = apb.TextString or apb.text

                        -- Helper: Apply visibility using SetAlpha (combat-safe) instead of SetShown (taint-prone).
                        -- Hooks Show(), SetAlpha(), and SetText() to re-enforce BOTH alpha=0 AND font styling when Blizzard updates.
                        local function applyAltPowerTextVisibility(fs, hidden)
                            if not fs then return end
                            local st = getState(fs)
                            if not st then return end
                            if hidden then
                                if fs.SetAlpha then pcall(fs.SetAlpha, fs, 0) end
                                -- Install hooks once to re-enforce alpha when Blizzard calls Show(), SetAlpha(), or SetText()
                                if not st.altPowerTextVisibilityHooked then
                                    st.altPowerTextVisibilityHooked = true
                                    if _G.hooksecurefunc then
                                        -- Hook Show() to re-enforce alpha=0
                                        _G.hooksecurefunc(fs, "Show", function(self)
                                            if isEditModeActive() then return end
                                            local s = getState(self)
                                            if s and s.altPowerTextHidden and self.SetAlpha then
                                                pcall(self.SetAlpha, self, 0)
                                            end
                                        end)
                                        -- Hook SetAlpha() to re-enforce alpha=0 when Blizzard tries to make it visible
                                        _G.hooksecurefunc(fs, "SetAlpha", function(self, alpha)
                                            if isEditModeActive() then return end
                                            local s = getState(self)
                                            if s and s.altPowerTextHidden and alpha and alpha > 0 then
                                                -- Use C_Timer to avoid infinite recursion (hook calls SetAlpha which triggers hook)
                                                if not s.altPowerTextAlphaDeferred then
                                                    s.altPowerTextAlphaDeferred = true
                                                    C_Timer.After(0, function()
                                                        local s2 = getState(self)
                                                        if s2 then s2.altPowerTextAlphaDeferred = nil end
                                                        if s2 and s2.altPowerTextHidden and self.SetAlpha then
                                                            pcall(self.SetAlpha, self, 0)
                                                        end
                                                    end)
                                                end
                                            end
                                        end)
                                        -- Hook SetText() to re-enforce alpha=0 when Blizzard updates text content
                                        _G.hooksecurefunc(fs, "SetText", function(self)
                                            if isEditModeActive() then return end
                                            local s = getState(self)
                                            if s and s.altPowerTextHidden and self.SetAlpha then
                                                pcall(self.SetAlpha, self, 0)
                                            end
                                        end)
                                    end
                                end
                                st.altPowerTextHidden = true
                            else
                                st.altPowerTextHidden = false
                                if fs.SetAlpha then pcall(fs.SetAlpha, fs, 1) end
                            end
                        end

                        -- NOTE: SetFont/SetFontObject hooks removed for performance reasons.
                        -- Font persistence is handled by the Character Frame hook in text.lua.

                        -- Visibility: respect both the bar-wide hidden flag and the per-text toggles.
                        local percentHidden = (acfg.percentHidden == true)
                        local valueHidden = (acfg.valueHidden == true)

                        applyAltPowerTextVisibility(leftFS, altHidden or percentHidden)
                        applyAltPowerTextVisibility(rightFS, altHidden or valueHidden)

                        -- Install SetText hook for center TextString to enforce hidden state only
                        local tsState = getState(textStringFS)
                        if textStringFS and tsState and not tsState.altPowerTextCenterSetTextHooked then
                            tsState.altPowerTextCenterSetTextHooked = true
                            if _G.hooksecurefunc then
                                _G.hooksecurefunc(textStringFS, "SetText", function(self)
                                    if isEditModeActive() then return end
                                    -- Enforce hidden state immediately if configured
                                    local s = getState(self)
                                    if s and s.altPowerTextCenterHidden and self.SetAlpha then
                                        pcall(self.SetAlpha, self, 0)
                                    end
                                end)
                            end
                        end

                        -- Styling (font/size/style/color/offset) using stable baseline anchors
                        addon._ufAltPowerTextBaselines = addon._ufAltPowerTextBaselines or {}
                        local function ensureBaseline(fs, key)
                            addon._ufAltPowerTextBaselines[key] = addon._ufAltPowerTextBaselines[key] or {}
                            local b = addon._ufAltPowerTextBaselines[key]
                            if b.point == nil then
                                if fs and fs.GetPoint then
                                    local p, relTo, rp, x, y = fs:GetPoint(1)
                                    -- Store raw values; sanitization happens at use time
                                    b.point = p
                                    b.relTo = relTo or (fs.GetParent and fs:GetParent()) or apb
                                    b.relPoint = rp
                                    b.x = x
                                    b.y = y
                                else
                                    b.point, b.relTo, b.relPoint, b.x, b.y =
                                        "CENTER", (fs and fs.GetParent and fs:GetParent()) or apb, "CENTER", 0, 0
                                end
                            end
                            return b
                        end

                        local function applyAltTextStyle(fs, styleCfg, baselineKey)
                            if not fs or not styleCfg then return end
                            -- Default/clean profiles should not modify Blizzard text.
                            -- Only apply styling if the user has configured any text settings.
                            local function hasTextCustomization(cfgT)
                                if not cfgT then return false end
                                -- Font face may be present as a structural default; treat the stock face as non-customization
                                -- unless other settings are set.
                                if cfgT.fontFace ~= nil and cfgT.fontFace ~= "" and cfgT.fontFace ~= "FRIZQT__" then
                                    return true
                                end
                                if cfgT.size ~= nil or cfgT.style ~= nil or cfgT.color ~= nil or cfgT.alignment ~= nil then
                                    return true
                                end
                                -- colorMode is used for APB text to support "classPower" color
                                if cfgT.colorMode ~= nil and cfgT.colorMode ~= "default" then
                                    return true
                                end
                                if cfgT.offset and (cfgT.offset.x ~= nil or cfgT.offset.y ~= nil) then
                                    local ox = tonumber(cfgT.offset.x) or 0
                                    local oy = tonumber(cfgT.offset.y) or 0
                                    if ox ~= 0 or oy ~= 0 then
                                        return true
                                    end
                                end
                                return false
                            end
                            if not hasTextCustomization(styleCfg) then
                                return
                            end
                            local face = addon.ResolveFontFace
                                and addon.ResolveFontFace(styleCfg.fontFace or "FRIZQT__")
                                or (select(1, _G.GameFontNormal:GetFont()))
                            local size = tonumber(styleCfg.size) or 14
                            local outline = tostring(styleCfg.style or "OUTLINE")
                            -- Set flag to prevent the SetFont hook from triggering a reapply loop
                            local fsState = getState(fs)
                            if fsState then fsState.applyingFont = true end
                            if addon.ApplyFontStyle then addon.ApplyFontStyle(fs, face, size, outline) elseif fs.SetFont then pcall(fs.SetFont, fs, face, size, outline) end
                            if fsState then fsState.applyingFont = nil end
                            -- Determine effective color based on colorMode
                            local c = styleCfg.color or {1, 1, 1, 1}
                            local colorMode = styleCfg.colorMode or "default"
                            if colorMode == "classPower" then
                                -- Use the class's power bar color (Energy = yellow, Rage = red, Mana = blue, etc.)
                                if addon.GetPowerColorRGB then
                                    local pr, pg, pb = addon.GetPowerColorRGB("player")
                                    -- Lighten mana blue for text readability (mana = powerType 0)
                                    local powerType = UnitPowerType("player")
                                    if powerType == 0 then -- MANA
                                        local lightenFactor = 0.25
                                        pr = (pr or 0) + (1 - (pr or 0)) * lightenFactor
                                        pg = (pg or 0) + (1 - (pg or 0)) * lightenFactor
                                        pb = (pb or 0) + (1 - (pb or 0)) * lightenFactor
                                    end
                                    c = {pr or 1, pg or 1, pb or 1, 1}
                                end
                            elseif colorMode == "class" then
                                local cr, cg, cb = addon.GetClassColorRGB("player")
                                c = {cr or 1, cg or 1, cb or 1, 1}
                            elseif colorMode == "default" then
                                -- Default white for Blizzard's standard bar text color
                                c = {1, 1, 1, 1}
                            end
                            -- colorMode == "custom" uses styleCfg.color as-is
                            if fs.SetTextColor then
                                pcall(fs.SetTextColor, fs, c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
                            end

                            -- Apply text alignment using two-point anchoring (matches text.lua pattern).
                            -- Makes SetJustifyH work correctly without needing GetWidth() (which can
                            -- trigger secret value errors on unit frame StatusBars).
                            -- Check for both :right and -right patterns to handle all key formats
                            local defaultAlign = "LEFT"
                            if baselineKey and (baselineKey:find(":right", 1, true) or baselineKey:find("-right", 1, true)) then
                                defaultAlign = "RIGHT"
                            elseif baselineKey and (baselineKey:find(":center", 1, true) or baselineKey:find("-center", 1, true)) then
                                defaultAlign = "CENTER"
                            end
                            local alignment = styleCfg.alignment or defaultAlign
                            local parentBar = fs:GetParent()

                            local ox = (styleCfg.offset and tonumber(styleCfg.offset.x)) or 0
                            local oy = (styleCfg.offset and tonumber(styleCfg.offset.y)) or 0

                            -- Get baseline Y position for vertical offset
                            local b = ensureBaseline(fs, baselineKey)
                            local yOffset = safeOffset(b.y) + oy

                            -- Use two-point anchoring to span the parent bar width.
                            if fs.ClearAllPoints and fs.SetPoint and parentBar then
                                fs:ClearAllPoints()
                                -- Anchor both left and right edges to span the bar
                                local leftPad = 2 + ox
                                local rightPad = -2 + ox
                                pcall(fs.SetPoint, fs, "LEFT", parentBar, "LEFT", leftPad, yOffset)
                                pcall(fs.SetPoint, fs, "RIGHT", parentBar, "RIGHT", rightPad, yOffset)
                            end

                            if fs.SetJustifyH then
                                pcall(fs.SetJustifyH, fs, alignment)
                            end

                            -- Force text redraw to apply alignment visually (secret-value safe)
                            if fs and fs.GetText and fs.SetText then
                                local ok, txt = pcall(fs.GetText, fs)
                                if ok and txt and type(txt) == "string" then
                                    fs:SetText("")
                                    fs:SetText(txt)
                                else
                                    -- Fallback: toggle alpha to force redraw without needing text value
                                    local okAlpha, alpha = pcall(function() return fs.GetAlpha and fs:GetAlpha() end)
                                    if okAlpha and alpha then
                                        pcall(fs.SetAlpha, fs, 0)
                                        pcall(fs.SetAlpha, fs, alpha)
                                    end
                                end
                            end
                        end

                        if leftFS then
                            applyAltTextStyle(leftFS, acfg.textPercent or {}, "Player:altpower-left")
                        end
                        if rightFS then
                            applyAltTextStyle(rightFS, acfg.textValue or {}, "Player:altpower-right")
                        end
                        -- Style center TextString using Value settings (used in NUMERIC display mode)
                        -- If Value text is hidden (or entire bar is hidden), also hide center text
                        if textStringFS then
                            local centerHidden = altHidden or valueHidden
                            local tsState = getState(textStringFS)
                            if centerHidden then
                                if textStringFS.SetAlpha then pcall(textStringFS.SetAlpha, textStringFS, 0) end
                                if tsState then tsState.altPowerTextCenterHidden = true end
                            else
                                if tsState and tsState.altPowerTextCenterHidden then
                                    if textStringFS.SetAlpha then pcall(textStringFS.SetAlpha, textStringFS, 1) end
                                    tsState.altPowerTextCenterHidden = nil
                                end
                                applyAltTextStyle(textStringFS, acfg.textValue or {}, "Player:altpower-center")
                            end
                        end
                    end

                    -- Width / height scaling (simple frame SetWidth/SetHeight based on %),
                    -- plus additive X/Y offsets applied from the captured baseline points.
                    if not inCombat then
                        local apbState = getState(apb)
                        if not apbState then return end
                        -- Capture originals once
                        if not apbState.ufOrigWidth then
                            if apb.GetWidth then
                                local ok, w = pcall(apb.GetWidth, apb)
                                if ok and w and not issecretvalue(w) then apbState.ufOrigWidth = w end
                            end
                        end
                        if not apbState.ufOrigHeight then
                            if apb.GetHeight then
                                local ok, h = pcall(apb.GetHeight, apb)
                                if ok and h and not issecretvalue(h) then apbState.ufOrigHeight = h end
                            end
                        end
                        if not apbState.ufOrigPoints then
                            local pts = {}
                            local n = (apb.GetNumPoints and apb:GetNumPoints()) or 0
                            for i = 1, n do
                                local p, rel, rp, x, y = apb:GetPoint(i)
                                table.insert(pts, { p, rel, rp, x or 0, y or 0 })
                            end
                            apbState.ufOrigPoints = pts
                        end

                        local wPct = tonumber(acfg.widthPct) or 100
                        local hPct = tonumber(acfg.heightPct) or 100
                        local scaleX = math.max(0.5, math.min(1.5, wPct / 100))
                        local scaleY = math.max(0.5, math.min(2.0, hPct / 100))

                        -- Restore baseline first
                        if apbState.ufOrigWidth and apb.SetWidth then
                            pcall(apb.SetWidth, apb, apbState.ufOrigWidth)
                        end
                        if apbState.ufOrigHeight and apb.SetHeight then
                            pcall(apb.SetHeight, apb, apbState.ufOrigHeight)
                        end
                        if apbState.ufOrigPoints and apb.ClearAllPoints and apb.SetPoint then
                            pcall(apb.ClearAllPoints, apb)
                            for _, pt in ipairs(apbState.ufOrigPoints) do
                                pcall(apb.SetPoint, apb, pt[1] or "CENTER", pt[2], pt[3] or pt[1] or "CENTER", pt[4] or 0, pt[5] or 0)
                            end
                        end

                        -- Apply width/height scaling (from center)
                        if apbState.ufOrigWidth and apb.SetWidth then
                            pcall(apb.SetWidth, apb, apbState.ufOrigWidth * scaleX)
                        end
                        if apbState.ufOrigHeight and apb.SetHeight then
                            pcall(apb.SetHeight, apb, apbState.ufOrigHeight * scaleY)
                        end

                        -- Apply positioning offsets relative to the original anchor points.
                        local offsetX = tonumber(acfg.offsetX) or 0
                        local offsetY = tonumber(acfg.offsetY) or 0
                        if apbState.ufOrigPoints and apb.ClearAllPoints and apb.SetPoint then
                            pcall(apb.ClearAllPoints, apb)
                            for _, pt in ipairs(apbState.ufOrigPoints) do
                                local baseX = pt[4] or 0
                                local baseY = pt[5] or 0
                                local newX = baseX + offsetX
                                local newY = baseY + offsetY
                                pcall(apb.SetPoint, apb, pt[1] or "CENTER", pt[2], pt[3] or pt[1] or "CENTER", newX, newY)
                            end
                        end
                    end
                    end -- acfg
                end
            end

            -- Power Bar Width scaling (texture/mask only)
            -- Player only - Pet excluded (secret values), Target/Focus not supported.
            do
                local canScale = (unit == "Player")

                local pbState = getState(pb)
                if not pbState then return end
                if canScale and not inCombat then
                    local pct = tonumber(cfg.powerBarWidthPct) or 100
                    local tex = pb.GetStatusBarTexture and pb:GetStatusBarTexture()
                    local mask = resolvePowerMask(unit)
					local isMirroredUnit = (unit == "Target" or unit == "Focus")
					local scaleX = math.min(1.5, math.max(0.5, (pct or 100) / 100))

                    -- Capture original PB width once
                    if pb and not pbState.ufOrigWidth then
                        if pb.GetWidth then
                            local ok, w = pcall(pb.GetWidth, pb)
                            if ok and w and not issecretvalue(w) then pbState.ufOrigWidth = w end
                        end
                    end

                    -- Capture original PB anchors
                    if pb and not pbState.ufOrigPoints then
                        local pts = {}
                        local n = (pb.GetNumPoints and pb:GetNumPoints()) or 0
                        for i = 1, n do
                            local p, rel, rp, x, y = pb:GetPoint(i)
                            table.insert(pts, { p, rel, rp, x or 0, y or 0 })
                        end
                        pbState.ufOrigPoints = pts
                    end

                    -- Helper: reanchor PB to grow left
                    local function reapplyPBPointsWithLeftOffset(dx)
                        if not pb or not pb.ClearAllPoints or not pb.SetPoint or not (pbState and pbState.ufOrigPoints) then return end
                        pcall(pb.ClearAllPoints, pb)
                        for _, pt in ipairs(pbState.ufOrigPoints) do
                            pcall(pb.SetPoint, pb, pt[1] or "LEFT", pt[2], pt[3] or pt[1] or "LEFT", (pt[4] or 0) - dx, pt[5] or 0)
                        end
                    end

                    -- Helper: reanchor PB to grow right
                    local function reapplyPBPointsWithRightOffset(dx)
                        if not pb or not pb.ClearAllPoints or not pb.SetPoint or not (pbState and pbState.ufOrigPoints) then return end
                        pcall(pb.ClearAllPoints, pb)
                        for _, pt in ipairs(pbState.ufOrigPoints) do
                            pcall(pb.SetPoint, pb, pt[1] or "LEFT", pt[2], pt[3] or pt[1] or "LEFT", (pt[4] or 0) + dx, pt[5] or 0)
                        end
                    end

					-- CRITICAL: Always restore to original state FIRST before applying new width
					-- Always start from the captured baseline to avoid cumulative offsets.
					if pb and pbState.ufOrigWidth and pb.SetWidth then
						pcall(pb.SetWidth, pb, pbState.ufOrigWidth)
					end
					if pb and pbState.ufOrigPoints and pb.ClearAllPoints and pb.SetPoint then
						pcall(pb.ClearAllPoints, pb)
						for _, pt in ipairs(pbState.ufOrigPoints) do
							pcall(pb.SetPoint, pb, pt[1] or "LEFT", pt[2], pt[3] or pt[1] or "LEFT", pt[4] or 0, pt[5] or 0)
						end
					end

                    if pct > 100 then
                        -- Widen the status bar frame
                        if pb and pb.SetWidth and pbState.ufOrigWidth then
                            pcall(pb.SetWidth, pb, pbState.ufOrigWidth * scaleX)
                        end

                        -- Reposition the frame to control growth direction
                        if pb and pbState.ufOrigWidth then
                            local dx = (pbState.ufOrigWidth * (scaleX - 1))
                            if dx and dx ~= 0 then
                                if unit == "Target" or unit == "Focus" then
                                    reapplyPBPointsWithLeftOffset(dx)
                                else
                                    reapplyPBPointsWithRightOffset(dx)
                                end
                            end
                        end

                        -- DO NOT touch the StatusBar texture - it's managed automatically by the StatusBar widget
                        -- REMOVE the mask entirely when widening - it causes rendering artifacts
                        if tex and mask and tex.RemoveMaskTexture then
                            pcall(tex.RemoveMaskTexture, tex, mask)
                        end
                        -- NOTE: Do NOT call SetValue to "refresh" the texture - it taints the protected StatusBar
                        -- and causes "blocked from an action" errors when Blizzard later calls Show().
                        -- The StatusBar refreshes automatically when its dimensions change.
                    elseif pct < 100 then
						-- Narrow the status bar frame
						if pb and pb.SetWidth and pbState.ufOrigWidth then
							pcall(pb.SetWidth, pb, pbState.ufOrigWidth * scaleX)
						end
						-- Reposition so mirrored bars keep the portrait edge anchored
						if pb and pbState.ufOrigWidth then
							local shrinkDx = pbState.ufOrigWidth * (1 - scaleX)
							if shrinkDx and shrinkDx ~= 0 and isMirroredUnit then
								reapplyPBPointsWithLeftOffset(-shrinkDx)
							end
						end
						-- Ensure mask remains applied when narrowing
						if pb and mask then
							ensureMaskOnBarTexture(pb, mask)
						end
                    else
                        -- Restore power bar frame
                        if pb and pbState.ufOrigWidth and pb.SetWidth then
                            pcall(pb.SetWidth, pb, pbState.ufOrigWidth)
                        end
                        if pb and pbState.ufOrigPoints and pb.ClearAllPoints and pb.SetPoint then
                            pcall(pb.ClearAllPoints, pb)
                            for _, pt in ipairs(pbState.ufOrigPoints) do
                                pcall(pb.SetPoint, pb, pt[1] or "LEFT", pt[2], pt[3] or pt[1] or "LEFT", pt[4] or 0, pt[5] or 0)
                            end
                        end
                        -- Re-apply mask to texture at original dimensions
                        if pb and mask then
                            ensureMaskOnBarTexture(pb, mask)
                        end
                    end
				elseif not inCombat then
					-- Not scalable (Target/Focus with default fill): ensure restoration of any prior width/anchors/mask
					local tex = pb.GetStatusBarTexture and pb:GetStatusBarTexture()
					local mask = resolvePowerMask(unit)
					-- Restore power bar frame
					if pb and pbState.ufOrigWidth and pb.SetWidth then
						pcall(pb.SetWidth, pb, pbState.ufOrigWidth)
					end
					if pb and pbState.ufOrigPoints and pb.ClearAllPoints and pb.SetPoint then
						pcall(pb.ClearAllPoints, pb)
						for _, pt in ipairs(pbState.ufOrigPoints) do
							pcall(pb.SetPoint, pb, pt[1] or "LEFT", pt[2], pt[3] or pt[1] or "LEFT", pt[4] or 0, pt[5] or 0)
						end
					end
					-- Re-apply mask to texture at original dimensions
					if pb and mask then
						ensureMaskOnBarTexture(pb, mask)
					end
							end
						end
			
			-- Power Bar Height scaling (texture/mask only)
			-- Player only - Pet excluded (secret values), Target/Focus not supported.
			do
                -- Skip all Power Bar height scaling while in combat; defer to the next
                -- out-of-combat styling pass instead to avoid taint.
                if not inCombat then
				    local canScale = (unit == "Player")
				
				    local pbState = getState(pb)
				    if not pbState then return end
				    if canScale then
					    local pct = tonumber(cfg.powerBarHeightPct) or 100
					    local widthPct = tonumber(cfg.powerBarWidthPct) or 100
					    local tex = pb.GetStatusBarTexture and pb:GetStatusBarTexture()
					    local mask = resolvePowerMask(unit)
					    local texState = getState(tex)
					    local maskState = getState(mask)
					
					    -- Capture originals once (height and anchor points)
					    if tex and texState and not texState.origCapturedHeight then
						    if tex.GetHeight then
							    local ok, h = pcall(tex.GetHeight, tex)
							    if ok and h and not issecretvalue(h) then texState.origHeight = h end
						    end
						    -- Texture anchor points already captured by width scaling
						    texState.origCapturedHeight = true
					    end
					    if mask and maskState and not maskState.origCapturedHeight then
						    if mask.GetHeight then
							    local ok, h = pcall(mask.GetHeight, mask)
							    if ok and h and not issecretvalue(h) then maskState.origHeight = h end
						    end
						    -- Mask anchor points already captured by width scaling
						    maskState.origCapturedHeight = true
					    end
					
					    -- Anchor points should already be captured by width scaling
					    -- If not, capture them now
					    if pb and not pbState.ufOrigPoints then
						    local pts = {}
						    local n = (pb.GetNumPoints and pb:GetNumPoints()) or 0
						    for i = 1, n do
							    local p, rel, rp, x, y = pb:GetPoint(i)
							    table.insert(pts, { p, rel, rp, x or 0, y or 0 })
						    end
						    pbState.ufOrigPoints = pts
					    end
					
					    -- Helper: reanchor PB to grow downward (keep top fixed)
					    local function reapplyPBPointsWithBottomOffset(dy)
						    -- Positive dy moves BOTTOM/CENTER anchors downward (keep top edge fixed)
						    local pts = pbState and pbState.ufOrigPoints
						    if not (pb and pts and pb.ClearAllPoints and pb.SetPoint) then return end
						    pcall(pb.ClearAllPoints, pb)
						    for _, pt in ipairs(pts) do
							    local p, rel, rp, x, y = pt[1], pt[2], pt[3], pt[4], pt[5]
							    local yy = y or 0
							    local anchor = tostring(p or "")
							    local relp = tostring(rp or "")
							    if string.find(anchor, "BOTTOM", 1, true) or string.find(relp, "BOTTOM", 1, true) then
								    yy = (y or 0) - (dy or 0)
							    elseif string.find(anchor, "CENTER", 1, true) or string.find(relp, "CENTER", 1, true) then
								    yy = (y or 0) - ((dy or 0) * 0.5)
							    end
							    pcall(pb.SetPoint, pb, p or "TOP", rel, rp or p or "TOP", x or 0, yy or 0)
						    end
					    end
					
					    local scaleY = math.max(0.5, math.min(2.0, pct / 100))
					
					    -- Capture original PowerBar height once
					    if pb and not pbState.ufOrigHeight then
						    if pb.GetHeight then
							    local ok, h = pcall(pb.GetHeight, pb)
							    if ok and h and not issecretvalue(h) then pbState.ufOrigHeight = h end
						    end
					    end
					
					    -- CRITICAL: Always restore to original state FIRST
					    if pb and pbState.ufOrigHeight and pb.SetHeight then
						    pcall(pb.SetHeight, pb, pbState.ufOrigHeight)
					    end
					    if pb and pbState.ufOrigPoints and pb.ClearAllPoints and pb.SetPoint then
						    pcall(pb.ClearAllPoints, pb)
						    for _, pt in ipairs(pbState.ufOrigPoints) do
							    pcall(pb.SetPoint, pb, pt[1] or "TOP", pt[2], pt[3] or pt[1] or "TOP", pt[4] or 0, pt[5] or 0)
						    end
					    end
					
					    if pct ~= 100 then
						    -- Scale the status bar frame height
						    if pb and pb.SetHeight and pbState.ufOrigHeight then
							    pcall(pb.SetHeight, pb, pbState.ufOrigHeight * scaleY)
						    end
						
						    -- Reposition the frame to grow downward (keep top fixed)
						    if pb and pbState.ufOrigHeight then
							    local dy = (pbState.ufOrigHeight * (scaleY - 1))
							    if dy and dy ~= 0 then
								    reapplyPBPointsWithBottomOffset(dy)
							    end
						    end
						
						    -- DO NOT touch the StatusBar texture - it's managed automatically by the StatusBar widget
						    -- REMOVE the mask entirely when scaling - it causes rendering artifacts
						    if tex and mask and tex.RemoveMaskTexture then
							    pcall(tex.RemoveMaskTexture, tex, mask)
						    end

							if Util and Util.ApplyFullPowerSpikeScale then
								Util.ApplyFullPowerSpikeScale(pb, scaleY)
							end
						    -- NOTE: Do NOT call SetValue to "refresh" the texture - it taints the protected StatusBar
						    -- and causes "blocked from an action" errors when Blizzard later calls Show().
						    -- The StatusBar refreshes automatically when its dimensions change.
					    else
						    -- Restore (already done above in the restore-first step)
						    -- Re-apply mask ONLY if both Width and Height are at 100%
						    -- (Width scaling removes the mask, so don't re-apply it if Width is still scaled)
						    if pb and mask and widthPct == 100 then
							    ensureMaskOnBarTexture(pb, mask)
						    end

							if Util and Util.ApplyFullPowerSpikeScale then
								Util.ApplyFullPowerSpikeScale(pb, 1)
							end
					    end
				    else
					    -- Not scalable (Target/Focus with default fill): ensure restoration of any prior height/anchors
					    -- Restore power bar frame
					    if pb and pbState.ufOrigHeight and pb.SetHeight then
						    pcall(pb.SetHeight, pb, pbState.ufOrigHeight)
					    end
					    if pb and pbState.ufOrigPoints and pb.ClearAllPoints and pb.SetPoint then
						    pcall(pb.ClearAllPoints, pb)
						    for _, pt in ipairs(pbState.ufOrigPoints) do
							    pcall(pb.SetPoint, pb, pt[1] or "TOP", pt[2], pt[3] or pt[1] or "TOP", pt[4] or 0, pt[5] or 0)
						    end
					    end
						if Util and Util.ApplyFullPowerSpikeScale then
							Util.ApplyFullPowerSpikeScale(pb, 1)
						end
				    end
                end
			end
						
            -- Power Bar positioning offsets / custom positioning (Player only)
            do
                if not inCombat then
                    local offsetX = tonumber(cfg.powerBarOffsetX) or 0
                    local offsetY = tonumber(cfg.powerBarOffsetY) or 0

                    local pbState = getState(pb)
                    if pbState and not pbState.powerBarOrigPoints then
                        pbState.powerBarOrigPoints = {}
                        for i = 1, pb:GetNumPoints() do
                            local point, relativeTo, relativePoint, xOfs, yOfs = pb:GetPoint(i)
                            table.insert(pbState.powerBarOrigPoints, { point, relativeTo, relativePoint, xOfs, yOfs })
                        end
                    end

                    if offsetX ~= 0 or offsetY ~= 0 then
                        if pb.ClearAllPoints and pb.SetPoint then
                            pcall(pb.ClearAllPoints, pb)
                            local origPoints = pbState and pbState.powerBarOrigPoints or nil
                            if origPoints then
                                for _, pt in ipairs(origPoints) do
                                local newX = (pt[4] or 0) + offsetX
                                local newY = (pt[5] or 0) + offsetY
                                pcall(pb.SetPoint, pb, pt[1] or "LEFT", pt[2], pt[3] or pt[1] or "LEFT", newX, newY)
                                end
                            end
                        end
                    else
                        if pb.ClearAllPoints and pb.SetPoint then
                            pcall(pb.ClearAllPoints, pb)
                            local origPoints = pbState and pbState.powerBarOrigPoints or nil
                            if origPoints then
                                for _, pt in ipairs(origPoints) do
                                    pcall(pb.SetPoint, pb, pt[1] or "LEFT", pt[2], pt[3] or pt[1] or "LEFT", pt[4] or 0, pt[5] or 0)
                                end
                            end
                        end
                    end
                end
            end

            -- Power Bar custom border (mirrors Health Bar border settings; supports power-specific overrides)
            do
                local styleKey = cfg.powerBarBorderStyle or cfg.healthBarBorderStyle
                local hiddenEdges = cfg.powerBarBorderHiddenEdges
                local tintEnabled
                if cfg.powerBarBorderTintEnable ~= nil then
                    tintEnabled = not not cfg.powerBarBorderTintEnable
                else
                    tintEnabled = not not cfg.healthBarBorderTintEnable
                end
                local baseTint = type(cfg.powerBarBorderTintColor) == "table" and cfg.powerBarBorderTintColor or cfg.healthBarBorderTintColor
                local tintColor = type(baseTint) == "table" and {
                    baseTint[1] or 1,
                    baseTint[2] or 1,
                    baseTint[3] or 1,
                    baseTint[4] or 1,
                } or {1, 1, 1, 1}
                local thickness = tonumber(cfg.powerBarBorderThickness) or tonumber(cfg.healthBarBorderThickness) or 1
                if thickness < 1 then thickness = 1 elseif thickness > 16 then thickness = 16 end
                local insetH = (cfg.powerBarBorderInsetH ~= nil) and tonumber(cfg.powerBarBorderInsetH) or (cfg.powerBarBorderInset ~= nil) and tonumber(cfg.powerBarBorderInset) or tonumber(cfg.healthBarBorderInsetH) or tonumber(cfg.healthBarBorderInset) or 0
                local insetV = (cfg.powerBarBorderInsetV ~= nil) and tonumber(cfg.powerBarBorderInsetV) or (cfg.powerBarBorderInset ~= nil) and tonumber(cfg.powerBarBorderInset) or tonumber(cfg.healthBarBorderInsetV) or tonumber(cfg.healthBarBorderInset) or 0
                -- PetFrame is managed/protected: do not create or level custom border frames.
                -- Skip border application when bar texture is hidden (number-only display).
                -- Skip border application when power bar is fully hidden.
                if unit ~= "Pet" and cfg.useCustomBorders and not powerBarHideTextureOnly and not powerBarHidden then
                    if styleKey == "none" or styleKey == nil then
                        if addon.BarBorders and addon.BarBorders.ClearBarFrame then addon.BarBorders.ClearBarFrame(pb) end
                        if addon.Borders and addon.Borders.HideAll then addon.Borders.HideAll(pb) end
                    else
                        local styleDef = addon.BarBorders and addon.BarBorders.GetStyle and addon.BarBorders.GetStyle(styleKey)
                        local color
                        if tintEnabled then
                            color = tintColor
                        else
                            if styleDef then
                                color = {1, 1, 1, 1}
                            else
                                color = {0, 0, 0, 1}
                            end
                        end
                        local handled = false
                        if addon.BarBorders and addon.BarBorders.ApplyToBarFrame then
                            if addon.BarBorders.ClearBarFrame then addon.BarBorders.ClearBarFrame(pb) end
                            handled = addon.BarBorders.ApplyToBarFrame(pb, styleKey, {
                                color = color,
                                thickness = thickness,
                                levelOffset = 1,
                                containerParent = (pb and pb:GetParent()) or nil,
                                insetH = insetH,
                                insetV = insetV,
                                hiddenEdges = hiddenEdges,
                            })
                        end
                        if not handled then
                            if addon.BarBorders and addon.BarBorders.ClearBarFrame then addon.BarBorders.ClearBarFrame(pb) end
                            if addon.Borders and addon.Borders.ApplySquare then
                                local sqColor = tintEnabled and tintColor or {0, 0, 0, 1}
                                local baseY = (thickness <= 1) and 0 or 1
                                local baseX = 1
                                local expandY = baseY - insetV
                                local expandX = baseX - insetH
                                if expandX < -6 then expandX = -6 elseif expandX > 6 then expandX = 6 end
                                if expandY < -6 then expandY = -6 elseif expandY > 6 then expandY = 6 end
                                -- Pet is already excluded by the outer guard
                                addon.Borders.ApplySquare(pb, {
                                    size = thickness,
                                    color = sqColor,
                                    layer = "OVERLAY",
                                    layerSublevel = 3,
                                    expandX = expandX,
                                    expandY = expandY,
                                    hiddenEdges = hiddenEdges,
                                })
                            end
                        end
                        -- Keep ordering stable for power bar borders as well
                        ensureTextAndBorderOrdering(unit)
                        if pb and not getProp(pb, "ufZOrderHooked") and pb.HookScript then
                            pb:HookScript("OnSizeChanged", function()
                                if InCombatLockdown and InCombatLockdown() then
                                    return
                                end
                                ensureTextAndBorderOrdering(unit)
                            end)
                            setProp(pb, "ufZOrderHooked", true)
                        end
                    end
                else
                    if addon.BarBorders and addon.BarBorders.ClearBarFrame then addon.BarBorders.ClearBarFrame(pb) end
                    if addon.Borders and addon.Borders.HideAll then addon.Borders.HideAll(pb) end
                end

            end
        end

        -- Stock frame art (includes the health bar border)
        do
            local ft = resolveUnitFrameFrameTexture(unit)
            if ft then
                local function compute()
                    local db2 = addon and addon.db and addon.db.profile
                    local unitFrames2 = db2 and rawget(db2, "unitFrames") or nil
                    local cfg2 = unitFrames2 and rawget(unitFrames2, unit) or nil
                    if not cfg2 then return nil end -- config unreadable: skip (fail closed)
                    return (cfg2.useCustomBorders or cfg2.healthBarHideBorder) and 0 or 1
                end
                applyAlpha(ft, compute())
                hookAlphaEnforcer(ft, compute)
            end
        end

        -- Target-specific prestige elements (PvP badge/portrait)
        if unit == "Target" then
            local contextual = _G.TargetFrame
                and _G.TargetFrame.TargetFrameContent
                and _G.TargetFrame.TargetFrameContent.TargetFrameContentContextual
            if contextual then
                local prestigePortrait = contextual.PrestigePortrait
                if prestigePortrait then
                    local function computePrestigeAlpha()
                        local db2 = addon and addon.db and addon.db.profile
                        local unitFrames2 = db2 and rawget(db2, "unitFrames") or nil
                        local cfg2 = unitFrames2 and rawget(unitFrames2, "Target") or nil
                        if not cfg2 then return nil end -- config unreadable: skip (fail closed)
                        return cfg2.useCustomBorders and 0 or 1
                    end
                    applyAlpha(prestigePortrait, computePrestigeAlpha())
                    hookAlphaEnforcer(prestigePortrait, computePrestigeAlpha)
                end
                local prestigeBadge = contextual.PrestigeBadge
                if prestigeBadge then
                    local function computePrestigeAlpha()
                        local db2 = addon and addon.db and addon.db.profile
                        local unitFrames2 = db2 and rawget(db2, "unitFrames") or nil
                        local cfg2 = unitFrames2 and rawget(unitFrames2, "Target") or nil
                        if not cfg2 then return nil end -- config unreadable: skip (fail closed)
                        return cfg2.useCustomBorders and 0 or 1
                    end
                    applyAlpha(prestigeBadge, computePrestigeAlpha())
                    hookAlphaEnforcer(prestigeBadge, computePrestigeAlpha)
                end
                local pvpIcon = contextual.PvpIcon
                if pvpIcon then
                    local function computePvpIconAlpha()
                        local db2 = addon and addon.db and addon.db.profile
                        local unitFrames2 = db2 and rawget(db2, "unitFrames") or nil
                        local cfg2 = unitFrames2 and rawget(unitFrames2, "Target") or nil
                        if not cfg2 then return nil end -- config unreadable: skip (fail closed)
                        return cfg2.useCustomBorders and 0 or 1
                    end
                    applyAlpha(pvpIcon, computePvpIconAlpha())
                    hookAlphaEnforcer(pvpIcon, computePvpIconAlpha)
                end
            end
        end

        -- Boss-specific frame art: Handle all 5 Boss frames (Boss1TargetFrame through Boss5TargetFrame)
        -- Unlike other unit frames where there's a single frame per unit, Boss frames have 5 individual frames
        -- that all share the same config (db.unitFrames.Boss). Apply hiding to each one.
        if unit == "Boss" then
            for i = 1, addon.NUM_BOSS_FRAMES do
                local bossFrame = addon.GetBossFrame(i)
                if bossFrame and bossFrame.TargetFrameContainer then
                    local bossFT = bossFrame.TargetFrameContainer.FrameTexture
                    if bossFT then
                        local function computeBossAlpha()
                            local db2 = addon and addon.db and addon.db.profile
                            local unitFrames2 = db2 and rawget(db2, "unitFrames") or nil
                            local cfgBoss = unitFrames2 and rawget(unitFrames2, "Boss") or nil
                            if not cfgBoss then return nil end -- config unreadable: skip (fail closed)
                            return (cfgBoss.useCustomBorders or cfgBoss.healthBarHideBorder) and 0 or 1
                        end
                        applyAlpha(bossFT, computeBossAlpha())
                        hookAlphaEnforcer(bossFT, computeBossAlpha)
                    end
                    -- Also hide the Flash (aggro/threat glow) if present on Boss frames
                    local bossFlash = bossFrame.TargetFrameContainer.Flash
                    if bossFlash then
                        local function computeBossFlashAlpha()
                            local db2 = addon and addon.db and addon.db.profile
                            local unitFrames2 = db2 and rawget(db2, "unitFrames") or nil
                            local cfgBoss = unitFrames2 and rawget(unitFrames2, "Boss") or nil
                            if not cfgBoss then return nil end -- config unreadable: skip (fail closed)
                            return cfgBoss.useCustomBorders and 0 or 1
                        end
                        applyAlpha(bossFlash, computeBossFlashAlpha())
                        hookAlphaEnforcer(bossFlash, computeBossFlashAlpha)
                    end

                    -- Hide ReputationColor strip (Boss1TargetFrame.TargetFrameContent.TargetFrameContentMain.ReputationColor)
                    -- when "Hide Blizzard Frame Art & Animations" (useCustomBorders) is enabled.
                    local bossReputationColor = bossFrame.TargetFrameContent
                        and bossFrame.TargetFrameContent.TargetFrameContentMain
                        and bossFrame.TargetFrameContent.TargetFrameContentMain.ReputationColor
                    if bossReputationColor then
                        local function computeBossReputationAlpha()
                            local db2 = addon and addon.db and addon.db.profile
                            local unitFrames2 = db2 and rawget(db2, "unitFrames") or nil
                            local cfgBoss = unitFrames2 and rawget(unitFrames2, "Boss") or nil
                            if not cfgBoss then return nil end -- config unreadable: skip (fail closed)
                            return cfgBoss.useCustomBorders and 0 or 1
                        end
                        applyAlpha(bossReputationColor, computeBossReputationAlpha())
                        hookAlphaEnforcer(bossReputationColor, computeBossReputationAlpha)
                    end
                end
            end
        end

        -- Player-specific frame art
        if unit == "Player" and _G.PlayerFrame and _G.PlayerFrame.PlayerFrameContainer then
            local container = _G.PlayerFrame.PlayerFrameContainer
            local altTex = container.AlternatePowerFrameTexture
            local vehicleTex = container.VehicleFrameTexture

            local function compute()
                local db2 = addon and addon.db and addon.db.profile
                local unitFrames2 = db2 and rawget(db2, "unitFrames") or nil
                local cfg2 = unitFrames2 and rawget(unitFrames2, "Player") or nil
                if not cfg2 then return nil end -- config unreadable: skip (fail closed)
                return cfg2.useCustomBorders and 0 or 1
            end

            if altTex then
                applyAlpha(altTex, compute())
                hookAlphaEnforcer(altTex, compute)
            end
            if vehicleTex then
                applyAlpha(vehicleTex, compute())
                hookAlphaEnforcer(vehicleTex, compute)
            end
        end
        
        -- Hide static visual elements when Use Custom Borders is enabled.
        -- Rationale: These elements (ReputationColor for Target/Focus, FrameFlash for Player, Flash for Target) have
        -- fixed positions that cannot be adjusted. Since Scoot allows users to reposition and
        -- resize health/power bars independently, these static overlays would remain in their original
        -- positions while the bars they're meant to surround/backdrop move elsewhere, causing
        -- visual confusion. Disabled when custom borders are active.
        
        -- Hide ReputationColor frame for Target/Focus when Use Custom Borders is enabled
        if (unit == "Target" or unit == "Focus") and cfg.useCustomBorders then
            local frame = getUnitFrameFor(unit)
            if frame then
                local reputationColor
                if unit == "Target" and _G.TargetFrame then
                    reputationColor = _G.TargetFrame.TargetFrameContent 
                        and _G.TargetFrame.TargetFrameContent.TargetFrameContentMain
                        and _G.TargetFrame.TargetFrameContent.TargetFrameContentMain.ReputationColor
                elseif unit == "Focus" and _G.FocusFrame then
                    reputationColor = _G.FocusFrame.TargetFrameContent
                        and _G.FocusFrame.TargetFrameContent.TargetFrameContentMain
                        and _G.FocusFrame.TargetFrameContent.TargetFrameContentMain.ReputationColor
                end
                if reputationColor then
                    local function computeAlpha()
                        local db2 = addon and addon.db and addon.db.profile
                        local unitFrames2 = db2 and rawget(db2, "unitFrames") or nil
                        local cfg2 = unitFrames2 and rawget(unitFrames2, unit) or nil
                        if not cfg2 then return nil end -- config unreadable: skip (fail closed)
                        return cfg2.useCustomBorders and 0 or 1
                    end
                    applyAlpha(reputationColor, 0)
                    hookAlphaEnforcer(reputationColor, computeAlpha)
                end
            end
        elseif (unit == "Target" or unit == "Focus") then
            -- Restore ReputationColor when Use Custom Borders is disabled
            local frame = getUnitFrameFor(unit)
            if frame then
                local reputationColor
                if unit == "Target" and _G.TargetFrame then
                    reputationColor = _G.TargetFrame.TargetFrameContent 
                        and _G.TargetFrame.TargetFrameContent.TargetFrameContentMain
                        and _G.TargetFrame.TargetFrameContent.TargetFrameContentMain.ReputationColor
                elseif unit == "Focus" and _G.FocusFrame then
                    reputationColor = _G.FocusFrame.TargetFrameContent
                        and _G.FocusFrame.TargetFrameContent.TargetFrameContentMain
                        and _G.FocusFrame.TargetFrameContent.TargetFrameContentMain.ReputationColor
                end
                if reputationColor then
                    local function computeAlpha()
                        local db2 = addon and addon.db and addon.db.profile
                        local unitFrames2 = db2 and rawget(db2, "unitFrames") or nil
                        local cfg2 = unitFrames2 and rawget(unitFrames2, unit) or nil
                        if not cfg2 then return nil end -- config unreadable: skip (fail closed)
                        return cfg2.useCustomBorders and 0 or 1
                    end
                    applyAlpha(reputationColor, 1)
                    hookAlphaEnforcer(reputationColor, computeAlpha)
                end
            end

    function addon.UnitFrames_GetPowerBarScreenPosition()
        local frame = getUnitFrameFor("Player")
        if not frame then
            return 0, 0
        end
        local pb = resolvePowerBar(frame, "Player")
        if not pb then
            return 0, 0
        end
        local x, y = getFrameScreenOffsets(pb)
        return clampScreenCoordinate(x), clampScreenCoordinate(y)
    end
        end
        
        -- Hide FrameFlash (aggro/threat glow) for Player when Use Custom Borders is enabled
        if unit == "Player" then
            if _G.PlayerFrame and _G.PlayerFrame.PlayerFrameContainer then
                local frameFlash = _G.PlayerFrame.PlayerFrameContainer.FrameFlash
                if frameFlash then
                    local function computeAlpha()
                        local db2 = addon and addon.db and addon.db.profile
                        local unitFrames2 = db2 and rawget(db2, "unitFrames") or nil
                        local cfgP = unitFrames2 and rawget(unitFrames2, "Player") or nil
                        if not cfgP then return nil end -- config unreadable: skip (fail closed)
                        return cfgP.useCustomBorders and 0 or 1
                    end
                    applyAlpha(frameFlash, computeAlpha())
                    hookAlphaEnforcer(frameFlash, computeAlpha)
                end
            end
        end
        
        -- Hide Flash (aggro/threat glow) for Target when Use Custom Borders is enabled
        if unit == "Target" then
            if _G.TargetFrame and _G.TargetFrame.TargetFrameContainer then
                local targetFlash = _G.TargetFrame.TargetFrameContainer.Flash
                if targetFlash then
                    local function computeAlpha()
                        local db2 = addon and addon.db and addon.db.profile
                        local unitFrames2 = db2 and rawget(db2, "unitFrames") or nil
                        local cfgT = unitFrames2 and rawget(unitFrames2, "Target") or nil
                        if not cfgT then return nil end -- config unreadable: skip (fail closed)
                        return cfgT.useCustomBorders and 0 or 1
                    end
                    applyAlpha(targetFlash, computeAlpha())
                    hookAlphaEnforcer(targetFlash, computeAlpha)
                end
            end
        end
        
        -- Hide Flash (aggro/threat glow) for Focus when Use Custom Borders is enabled
        if unit == "Focus" then
            if _G.FocusFrame and _G.FocusFrame.TargetFrameContainer then
                local focusFlash = _G.FocusFrame.TargetFrameContainer.Flash
                if focusFlash then
                    local function computeAlpha()
                        local db2 = addon and addon.db and addon.db.profile
                        local unitFrames2 = db2 and rawget(db2, "unitFrames") or nil
                        local cfgF = unitFrames2 and rawget(unitFrames2, "Focus") or nil
                        if not cfgF then return nil end -- config unreadable: skip (fail closed)
                        return cfgF.useCustomBorders and 0 or 1
                    end
                    applyAlpha(focusFlash, computeAlpha())
                    hookAlphaEnforcer(focusFlash, computeAlpha)
                end
            end
        end
    end

    function addon.ApplyUnitFrameBarTexturesFor(unit)
        applyForUnit(unit)
    end

    ---------------------------------------------------------------------------
    -- Snapshot-based skip guard for ApplyAllUnitFrameBarTextures.
    -- When bar-related DB values haven't changed since the last full restyle,
    -- skip the entire 7-unit dispatch. Targeted per-unit calls via
    -- ApplyUnitFrameBarTexturesFor() and deferred combat reapply bypass this.
    --
    -- MAINTENANCE: New bar DB keys MUST be added to BAR_CFG_KEYS / ALT_CFG_KEYS
    -- or their changes will be silently ignored until profile switch / /reload.
    ---------------------------------------------------------------------------
    local lastBarSnapshot

    -- All cfg keys read by applyForUnit for visual output.
    local BAR_CFG_KEYS = {
        -- health bar
        "useCustomBorders",
        "healthBarTexture", "healthBarColorMode", "healthBarTint",
        "healthBarBackgroundTexture", "healthBarBackgroundColorMode", "healthBarBackgroundTint", "healthBarBackgroundOpacity",
        "healthBarHideBorder", "healthBarHideTextureOnly",
        "healthBarHideOverAbsorbGlow", "healthBarHideHealPrediction", "healthBarHideHealthLossAnimation",
        "healthBarBorderStyle", "healthBarBorderTintEnable", "healthBarBorderTintColor",
        "healthBarBorderThickness", "healthBarBorderInset", "healthBarBorderInsetH", "healthBarBorderInsetV",
        -- power bar
        "powerBarTexture", "powerBarColorMode", "powerBarTint",
        "powerBarBackgroundTexture", "powerBarBackgroundColorMode", "powerBarBackgroundTint", "powerBarBackgroundOpacity",
        "powerBarHidden", "powerBarHideTextureOnly",
        "powerBarHideFullSpikes", "powerBarHideFeedback", "powerBarHideSpark", "powerBarHideManaCostPrediction",
        "powerBarBorderStyle", "powerBarBorderTintEnable", "powerBarBorderTintColor",
        "powerBarBorderThickness", "powerBarBorderInset", "powerBarBorderInsetH", "powerBarBorderInsetV",
        "powerBarWidthPct", "powerBarHeightPct", "powerBarOffsetX", "powerBarOffsetY",
        -- generic border (legacy)
        "borderStyle", "borderThickness", "borderInset", "borderInsetH", "borderInsetV", "borderTintEnable", "borderTintColor",
    }

    -- altPowerBar sub-table keys read by applyForUnit.
    local ALT_CFG_KEYS = {
        "enabled", "hidden", "hideTextureOnly",
        "texture", "colorMode", "tint",
        "backgroundTexture", "backgroundColorMode", "backgroundTint", "backgroundOpacity",
        "hideFullSpikes", "hideFeedback", "hideSpark", "hideManaCostPrediction",
        "borderStyle", "borderTintEnable", "borderTintColor", "borderThickness",
        "borderInset", "borderInsetH", "borderInsetV",
        "percentHidden", "valueHidden",
        "textPercent", "textValue",
        "widthPct", "heightPct", "offsetX", "offsetY",
        "width", "height", "x", "y", "fontFace", "size", "style", "color", "alignment",
    }

    -- Frames.UNITS is frozen in this order; snapshot strings serialize by it.
    local SNAPSHOT_UNITS = addon.Frames.UNITS
    local SEP = "\1"
    local NIL_SENTINEL = "\0"

    local function appendValue(parts, v)
        local t = type(v)
        if t == "table" then
            -- Serialize table contents (color tables {r,g,b,a}, text config sub-tables)
            parts[#parts + 1] = "{"
            for k2, v2 in pairs(v) do
                parts[#parts + 1] = tostring(k2)
                parts[#parts + 1] = "="
                local t2 = type(v2)
                if t2 == "table" then
                    -- One more level for nested sub-tables (e.g. textPercent.color)
                    for k3, v3 in pairs(v2) do
                        parts[#parts + 1] = tostring(k3)
                        parts[#parts + 1] = ":"
                        parts[#parts + 1] = tostring(v3)
                    end
                else
                    parts[#parts + 1] = tostring(v2)
                end
            end
            parts[#parts + 1] = "}"
        elseif v == nil then
            parts[#parts + 1] = NIL_SENTINEL
        else
            parts[#parts + 1] = tostring(v)
        end
    end

    local function buildBarSettingsSnapshot()
        local db = addon and addon.db and addon.db.profile
        local unitFrames = db and rawget(db, "unitFrames") or nil
        local parts = {}
        for u = 1, #SNAPSHOT_UNITS do
            local unit = SNAPSHOT_UNITS[u]
            local cfg = unitFrames and rawget(unitFrames, unit) or nil
            parts[#parts + 1] = unit
            if not cfg then
                parts[#parts + 1] = NIL_SENTINEL
            else
                for i = 1, #BAR_CFG_KEYS do
                    appendValue(parts, cfg[BAR_CFG_KEYS[i]])
                end
                local altCfg = rawget(cfg, "altPowerBar")
                if altCfg then
                    for i = 1, #ALT_CFG_KEYS do
                        appendValue(parts, altCfg[ALT_CFG_KEYS[i]])
                    end
                else
                    parts[#parts + 1] = NIL_SENTINEL
                end
            end
        end
        return table.concat(parts, SEP)
    end

    function addon.ApplyAllUnitFrameBarTextures()
        -- Skip full restyle when bar settings are unchanged.
        local snapshot = buildBarSettingsSnapshot()
        if snapshot == lastBarSnapshot then return end
        lastBarSnapshot = snapshot

        -- Styling passes must be resilient to Blizzard "secret value" errors that can
        -- surface from innocuous getters on managed UnitFrames (e.g., PetFrame heal prediction).
        -- Never allow those to hard-fail profile switching/preset apply.
        local function safeApply(unit)
            pcall(applyForUnit, unit)
        end
        safeApply("Player")
        safeApply("Target")
        safeApply("Focus")
        safeApply("Boss")
        safeApply("Pet")
        safeApply("TargetOfTarget")
        safeApply("FocusTarget")
    end

    -- Pre-emptive hiding and alpha hooks are now provided by the Preemptive module
    addon.PreemptiveHideTargetElements = Preemptive.hideTargetElements
    addon.PreemptiveHideFocusElements = Preemptive.hideFocusElements
    addon.PreemptiveHideBossElements = Preemptive.hideBossElements
    addon.InstallEarlyUnitFrameAlphaHooks = Preemptive.installEarlyAlphaHooks
    addon.InstallBossFrameHooks = Preemptive.installBossFrameHooks
end

-- Restore all party frames to stock Blizzard appearance (profile switch / category reset).

function addon.RestoreAllPartyFrameOverlays()
    -- Restore health bar overlays
    if addon.RestorePartyFrameHealthOverlays then
        addon.RestorePartyFrameHealthOverlays()
    end
    -- Restore name text overlays
    if addon.RestorePartyFrameNameOverlays then
        addon.RestorePartyFrameNameOverlays()
    end
end

-- Restore all raid frames to stock Blizzard appearance (profile switch / category reset).

function addon.RestoreAllRaidFrameOverlays()
    -- Restore health bar overlays
    if addon.RestoreRaidFrameHealthOverlays then
        addon.RestoreRaidFrameHealthOverlays()
    end
    -- Restore name text overlays
    if addon.RestoreRaidFrameNameOverlays then
        addon.RestoreRaidFrameNameOverlays()
    end
    -- Restore status text overlays
    if addon.RestoreRaidFrameStatusTextOverlays then
        addon.RestoreRaidFrameStatusTextOverlays()
    end
end


