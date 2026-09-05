-- bars.lua: Unit Frame bar styling orchestrator. Delegates to bars/ submodules.

local addonName, addon = ...

local Util = addon.ComponentsUtil

-- Reference extracted modules (loaded via TOC before this file)
local Combat = addon.BarsCombat
local Frames = addon.Frames
local Textures = addon.BarsTextures
local BarsOverlays = addon.BarsOverlays
local BarsSmallFrames = addon.BarsSmallFrames
local BarsSnapshot = addon.BarsSnapshot
local BarsBossFrames = addon.BarsBossFrames
local BarsAltPower = addon.BarsAltPower
local BarsPowerGeometry = addon.BarsPowerGeometry
local BarsFrameArt = addon.BarsFrameArt

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

local queuePowerBarReapply = Combat.queuePowerBarReapply
local queueUnitFrameTextureReapply = Combat.queueUnitFrameTextureReapply

-- Unit Frames: Apply custom bar textures (Health/Power) with optional tint per unit
do
    -- Use resolver functions from the shared module
    local getUnitFrameFor = addon.GetUnitFrame
    local resolveHealthBar = Frames.resolveHealthBar
    local resolveHealthContainer = Frames.resolveHealthContainer
    local resolvePowerBar = Frames.resolvePowerBar
    local resolveHealthMask = Frames.resolveHealthMask
    local resolvePowerMask = Frames.resolvePowerMask
    
    -- Use texture functions from extracted module
    local applyToBar = Textures.applyToBar
    local applyBackgroundToBar = Textures.applyBackgroundToBar
    local hasBackgroundCustomization = Textures.hasBackgroundCustomization
    local ensureMaskOnBarTexture = Textures.ensureMaskOnBarTexture

    -- Overlay functions from extracted bars/overlays.lua module
    local ensureTextAndBorderOrdering = BarsOverlays._ensureTextAndBorderOrdering
    local ensureRectHealthOverlay = BarsOverlays._ensureRectHealthOverlay
    local ensureRectPowerOverlay = BarsOverlays._ensureRectPowerOverlay
    local updateRectPowerOverlay = BarsOverlays._updateRectPowerOverlay

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

        -- Boss: five frames on one config. bars/bossframes.lua runs the whole Boss path
        -- (frame art enforcers, ReputationColor, health and power bars); nothing below applies.
        if unit == "Boss" then
            BarsBossFrames.applyForBoss(cfg)
            return
        end

        -- Target/Focus ReputationColor, enforced before the bar passes: bars/frameart.lua
        BarsFrameArt.applyEarly(unit)

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

        local hb = resolveHealthBar(frame, unit)
        if hb then
            local colorModeHB = cfg.healthBarColorMode or "default"
            local texKeyHB = cfg.healthBarTexture or "default"
            local unitId = (unit == "Player" and "player") or (unit == "Target" and "target") or (unit == "Focus" and "focus") or "player"
			-- Avoid applying styling to Target/Focus before they exist; Blizzard will reset sizes on first Update
			if (unit == "Target" or unit == "Focus") and _G.UnitExists and not _G.UnitExists(unitId) then
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
                if hasBackgroundCustomization(cfg, "healthBar") then
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
            if not healthBarHideTextureOnly then
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
            end

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
                        -- Kept off addon.ResolveColorRGBA: hook-install gate; the compare decides whether to hook, not what to paint.
                        local hasCustomColor = (colorMode == "custom" and type(tint) == "table") or (colorMode == "class") or (colorMode == "value") or (colorMode == "valueDark")
                        if not hasCustomTexture and not hasCustomColor then
                            return
                        end
                        applyToBar(self, texKey, colorMode, tint, "player", "health", unitIdP)
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
            local unitId = (unit == "Player" and "player") or (unit == "Target" and "target") or (unit == "Focus" and "focus") or "player"

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
                if hasBackgroundCustomization(cfg, "powerBar") then
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
                            -- Kept off addon.ResolveColorRGBA: hook-install gate; the compare decides whether to hook, not what to paint.
                            if colorMode == "texture" then
                                return
                            end

                            -- Only do work when the user has customized either texture or color;
                            -- default settings can safely follow Blizzard's behavior.
                            local hasCustomTexture = (type(texKey) == "string" and texKey ~= "" and texKey ~= "default")
                            -- Kept off addon.ResolveColorRGBA: hook-install gate; the compare decides whether to hook, not what to paint.
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
                    end)
                end
            end

            -- Alternate Power Bar styling (Player-only, class/spec gated): bars/altpower.lua
            if unit == "Player" then
                BarsAltPower.applyForPlayer(cfg, inCombat)
            end

            -- Power bar width, height, and offsets (Player scales; Target/Focus restore): bars/powergeometry.lua
            BarsPowerGeometry.apply(unit, pb, cfg, inCombat)

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
                -- Skip border application when bar texture is hidden (number-only display).
                -- Skip border application when power bar is fully hidden.
                if cfg.useCustomBorders and not powerBarHideTextureOnly and not powerBarHidden then
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

        -- Stock frame art, prestige art, ReputationColor, and Flash hides behind Use Custom Borders: bars/frameart.lua
        BarsFrameArt.apply(unit, cfg)
    end

    function addon.ApplyUnitFrameBarTexturesFor(unit)
        applyForUnit(unit)
    end

    function addon.ApplyAllUnitFrameBarTextures()
        -- Skip full restyle when bar settings are unchanged.
        if BarsSnapshot.Unchanged() then return end

        -- Styling passes must be resilient to Blizzard "secret value" errors that can
        -- surface from innocuous getters on managed UnitFrames (e.g., PetFrame heal prediction).
        -- Never allow those to hard-fail profile switching/preset apply.
        local units = addon.Frames.UNITS
        for i = 1, #units do
            pcall(applyForUnit, units[i])
        end
    end
end
