--------------------------------------------------------------------------------
-- cast/styling.lua
-- Cast bar visual styling for Player, Target, and Focus frames: textures,
-- borders, spark customization, icon management, and anchor/position overrides.
--------------------------------------------------------------------------------

local addonName, addon = ...
local CB = addon.CastBars
local getProp = CB._getProp
local setProp = CB._setProp
local getState = CB._getState
local getIconBorderContainer = CB._getIconBorderContainer
local getNested = CB._getNested
local installGradientHook = CB._installGradientHook
local applySpellNameColor = CB._applySpellNameColor
local applyTextFillMode = CB._applyTextFillMode
local hideTextFillElements = CB._hideTextFillElements
local syncTextFillText = CB._syncTextFillText
local resolveGradientColors = CB._resolveGradientColors

-- Unit Frames: Cast Bar positioning (Player/Target/Focus)
do
	local function resolveCastBarFrame(unit)
		if unit == "Player" then
			return _G.PlayerCastingBarFrame
		end
		if unit == "Target" then
			return _G.TargetFrameSpellBar
		elseif unit == "Focus" then
			return _G.FocusFrameSpellBar
		end
	end

	-- Resolve Health Bar for Target/Focus (via deterministic paths)
	local function resolveHealthBar(unit)
		if unit == "Target" then
			local root = _G.TargetFrame
			return getNested(root, "TargetFrameContent", "TargetFrameContentMain", "HealthBarsContainer", "HealthBar")
		elseif unit == "Focus" then
			local root = _G.FocusFrame
			return getNested(root, "TargetFrameContent", "TargetFrameContentMain", "HealthBarsContainer", "HealthBar")
		end
	end

	-- Resolve Power Bar (ManaBar) for Target/Focus (via deterministic paths)
	local function resolvePowerBar(unit)
		if unit == "Target" then
			local root = _G.TargetFrame
			return getNested(root, "TargetFrameContent", "TargetFrameContentMain", "ManaBar")
		elseif unit == "Focus" then
			local root = _G.FocusFrame
			return getNested(root, "TargetFrameContent", "TargetFrameContentMain", "ManaBar")
		end
	end

	-- Resolve Name FontString for Target/Focus (anchor target for "Above Name")
	local function resolveNameFS(unit)
		if unit == "Target" then
			return getNested(_G.TargetFrame, "TargetFrameContent", "TargetFrameContentMain", "Name")
		elseif unit == "Focus" then
			return getNested(_G.FocusFrame, "TargetFrameContent", "TargetFrameContentMain", "Name")
		end
	end

	-- Track which cast bars have custom anchor mode active, so the SetPoint hook knows when to re-apply
	local activeAnchorModes = {}
	-- Track scheduled re-apply timers to avoid duplicate scheduling
	local pendingReapply = {}

	-- Store original positions per frame so offsets are always relative to stock layout
	local originalPositions = {}
	-- Store original widths per frame for width-percent scaling
	local originalWidths = {}
	-- Store original icon anchors/sizes so padding and per-axis sizing are relative to stock layout
	local originalIconAnchors = {}
	local originalIconSizes = {}
	-- Store original spark vertex colors/alpha so "Default" can restore stock spark appearance
	local originalSparkVertexColor = {}
	local originalSparkAlpha = {}

	-- Track units that were reanchored during combat and need a full re-apply after combat ends
	local pendingPostCombatRefresh = {}

	-- Empowered cast state per unit token ("player"/"target"/"focus")
	-- Set via events only — never reads Blizzard frame properties (no taint risk)
	local empoweredCastActive = {}

	local function isEmpoweredCast(unit)
		local token = (unit == "Player" and "player")
				  or (unit == "Target" and "target")
				  or (unit == "Focus" and "focus")
		return token and empoweredCastActive[token] or false
	end

	-- Lightweight reanchor: only corrects position (ClearAllPoints + SetPoint) without
	-- going through the full apply pipeline or its combat guard.  Target/Focus cast bars
	-- are visual StatusBars — repositioning them is safe during combat (no taint).
	local function reanchorCastBar(frame, unit)
		if unit ~= "Target" and unit ~= "Focus" then return end

		local db = addon and addon.db and addon.db.profile
		if not db then return end
		local cfg = db.unitFrames and db.unitFrames[unit] and db.unitFrames[unit].castBar
		if not cfg then return end

		local anchorMode = cfg.anchorMode or "default"
		-- Backward-compat: migrate old healthTop → nameTop
		if anchorMode == "healthTop" then
			anchorMode = "nameTop"
			cfg.anchorMode = "nameTop"
		end
		if anchorMode == "default" then return end

		local anchorBar, anchorEdge
		if anchorMode == "nameTop" then
			anchorBar = resolveNameFS(unit)
			anchorEdge = "top"
		elseif anchorMode == "healthBottom" then
			anchorBar = resolveHealthBar(unit)
			anchorEdge = "bottom"
		elseif anchorMode == "powerTop" then
			anchorBar = resolvePowerBar(unit)
			anchorEdge = "top"
		elseif anchorMode == "powerBottom" then
			anchorBar = resolvePowerBar(unit)
			anchorEdge = "bottom"
		end

		if not anchorBar then return end

		local offsetX = tonumber(cfg.offsetX) or 0
		local offsetY = tonumber(cfg.offsetY) or 0
		local castBarPoint = (anchorEdge == "top") and "BOTTOM" or "TOP"
		local anchorPoint = (anchorEdge == "top") and "TOP" or "BOTTOM"

		setProp(frame, "ignoreSetPoint", true)
		frame:ClearAllPoints()
		frame:SetPoint(castBarPoint, anchorBar, anchorPoint, offsetX, offsetY)
		setProp(frame, "ignoreSetPoint", nil)

		-- Mark for full re-apply when combat ends
		pendingPostCombatRefresh[unit] = true
	end

	-- Flush deferred full re-applies after combat ends
	function addon.FlushPendingCastBarRefresh()
		for unit in pairs(pendingPostCombatRefresh) do
			if addon.ApplyUnitFrameCastBarFor then
				addon.ApplyUnitFrameCastBarFor(unit)
			end
		end
		pendingPostCombatRefresh = {}
	end

	local function applyCastBarForUnit(unit)
		if unit ~= "Player" and unit ~= "Target" and unit ~= "Focus" then return end
		if not addon:IsModuleEnabled("unitFrames", unit) then return end
		if not addon:IsCastBarXEnabled() then return end

		local db = addon and addon.db and addon.db.profile
		if not db then return end

		local unitFrames = rawget(db, "unitFrames")
		local unitCfg = unitFrames and rawget(unitFrames, unit) or nil
		if not unitCfg then return end
		local cfg = rawget(unitCfg, "castBar")
		if not cfg then return end
		-- Zero-Touch: skip empty tables (browsed settings but nothing configured)
		local hasConfig = false
		for k, v in pairs(cfg) do
			if v ~= nil then hasConfig = true; break end
		end
		if not hasConfig then return end

		local frame = resolveCastBarFrame(unit)
		if not frame then return end

		local isPlayer = (unit == "Player")

		-- For the Player cast bar, read the current Edit Mode "Lock to Player Frame" setting so
		-- only overrides position when the bar is locked underneath the Player frame. When the
		-- bar is unlocked and freely positioned in Edit Mode, Scoot should not fight that.
		local isLockedToPlayerFrame = false
		if isPlayer and addon and addon.EditMode and addon.EditMode.GetSetting then
			local mgr = _G.EditModeManagerFrame
			local EMSys = _G.Enum and _G.Enum.EditModeSystem
			local sid = _G.Enum and _G.Enum.EditModeCastBarSetting and _G.Enum.EditModeCastBarSetting.LockToPlayerFrame
			if mgr and EMSys and mgr.GetRegisteredSystemFrame and sid then
				local emFrame = mgr:GetRegisteredSystemFrame(EMSys.CastBar, nil)
				if emFrame then
					local v = addon.EditMode.GetSetting(emFrame, sid)
					isLockedToPlayerFrame = (tonumber(v) or 0) ~= 0
				end
			end
		end

		-- Install lightweight hooks once to keep cast bar styling persistent when
		-- Blizzard updates the bar's texture/color (cast start/stop, etc.).
		if not getProp(frame, "castHooksInstalled") and _G.hooksecurefunc then
			setProp(frame, "castHooksInstalled", true)
			local hookUnit = unit
			_G.hooksecurefunc(frame, "SetStatusBarTexture", function(self, texArg, ...)
				-- Ignore Scoot's own internal texture writes
				if getProp(self, "ufInternalTextureWrite") then return end
				-- Track interruptibility from Blizzard's atlas change (text-fill uses this
				-- to show white for non-kickable casts vs yellow/gold for kickable)
				if type(texArg) == "string" and not issecretvalue(texArg) then
					setProp(self, "castNotInterruptible", texArg == "ui-castingbar-uninterruptable")
				end
				-- Don't re-apply foreground during empowered casts (tiers provide visuals)
				local token = (hookUnit == "Player" and "player") or (hookUnit == "Target" and "target") or (hookUnit == "Focus" and "focus")
				if token and empoweredCastActive[token] then return end
				if addon and addon.ApplyUnitFrameCastBarFor then
					-- Mark this as a visual-only refresh to safely reapply
					-- textures/colors in combat without re-anchoring secure frames.
					setProp(self, "castVisualOnly", true)
					addon.ApplyUnitFrameCastBarFor(hookUnit)
					setProp(self, "castVisualOnly", nil)
				end
			end)
			_G.hooksecurefunc(frame, "SetStatusBarColor", function(self, ...)
				-- Don't re-apply color during empowered casts (stage tiers provide visuals)
				local token = (hookUnit == "Player" and "player") or (hookUnit == "Target" and "target") or (hookUnit == "Focus" and "focus")
				if token and empoweredCastActive[token] then return end
				if addon and addon.ApplyUnitFrameCastBarFor then
					setProp(self, "castVisualOnly", true)
					addon.ApplyUnitFrameCastBarFor(hookUnit)
					setProp(self, "castVisualOnly", nil)
				end
			end)
			-- Hook SetPoint to detect when Blizzard re-anchors the cast bar and re-apply
			-- custom anchoring if there is a non-default anchor mode active.
			_G.hooksecurefunc(frame, "SetPoint", function(self, ...)
				-- Ignore Scoot's SetPoint calls (flagged to prevent infinite loops)
				if getProp(self, "ignoreSetPoint") then return end
				-- Only re-apply if a custom anchor exists mode active for this unit
				local mode = activeAnchorModes[hookUnit]
				if mode and mode ~= "default" then
					if InCombatLockdown and InCombatLockdown() then
						-- Lightweight reanchor during combat (position only, no full pipeline)
						reanchorCastBar(self, hookUnit)
					else
						-- Out of combat: schedule full re-apply on next frame
						if not pendingReapply[hookUnit] then
							pendingReapply[hookUnit] = true
							C_Timer.After(0, function()
								pendingReapply[hookUnit] = nil
								if addon and addon.ApplyUnitFrameCastBarFor then
									addon.ApplyUnitFrameCastBarFor(hookUnit)
								end
							end)
						end
					end
				end
			end)

			-- Hook AdjustPosition (Target/Focus only) to immediately reapply custom anchoring
			-- after Blizzard repositions the cast bar (aura updates, ToT changes, etc.).
			-- Causes the flicker - called from UpdateAuras()
			-- on every UNIT_AURA event, which happens frequently during combat.
			if (hookUnit == "Target" or hookUnit == "Focus") and frame.AdjustPosition then
				_G.hooksecurefunc(frame, "AdjustPosition", function(self)
					local mode = activeAnchorModes[hookUnit]
					if mode and mode ~= "default" then
						if InCombatLockdown and InCombatLockdown() then
							-- Lightweight reanchor during combat (position only)
							reanchorCastBar(self, hookUnit)
						else
							if addon and addon.ApplyUnitFrameCastBarFor then
								addon.ApplyUnitFrameCastBarFor(hookUnit)
							end
						end
					end
				end)
			end
		end

		-- Capture baseline anchor:
		-- - Player: capture a baseline that represents the Edit Mode "under Player" layout,
		--   but avoid rebasing while Scoot offsets are non-zero to avoid compounding
		--   offsets on every apply. This keeps slider behaviour linear.
		-- - Target/Focus: capture once so offsets remain relative to stock layout.
		if frame.GetPoint then
			local point, relativeTo, relativePoint, xOfs, yOfs = frame:GetPoint(1)
			if point then
				if isPlayer then
					local hasOffsets =
						(tonumber(cfg.offsetX) or 0) ~= 0 or
						(tonumber(cfg.offsetY) or 0) ~= 0
					-- When offsets are zero and the bar is locked to the Player frame,
					-- treats the current layout as the new baseline. Otherwise, keeps the
					-- previous baseline so offset sliders remain stable.
					if (not hasOffsets and isLockedToPlayerFrame) or not originalPositions[frame] then
						originalPositions[frame] = {
							point = point,
							relativeTo = relativeTo,
							relativePoint = relativePoint,
							xOfs = xOfs or 0,
							yOfs = yOfs or 0,
						}
					end
				elseif not originalPositions[frame] then
					originalPositions[frame] = {
						point = point,
						relativeTo = relativeTo,
						relativePoint = relativePoint,
						xOfs = xOfs or 0,
						yOfs = yOfs or 0,
					}
				end
			end
		end

		local orig = originalPositions[frame]
		if not orig then return end

		-- Capture original width once
		if not originalWidths[frame] and frame.GetWidth then
			local ok, w = pcall(frame.GetWidth, frame)
			if ok and w then
				originalWidths[frame] = w
			end
		end

		local origWidth = originalWidths[frame]

		-- Capture original icon anchor/size once (per physical Icon texture)
		local iconFrame = frame.Icon
		if iconFrame then
			if not originalIconAnchors[iconFrame] and iconFrame.GetPoint then
				local p, relTo, rp, x, y = iconFrame:GetPoint(1)
				if p then
					originalIconAnchors[iconFrame] = {
						point = p,
						relativeTo = relTo,
						relativePoint = rp,
						xOfs = x or 0,
						yOfs = y or 0,
					}
				end
			end
			if not originalIconSizes[iconFrame] and iconFrame.GetWidth and iconFrame.GetHeight then
				local okW, w = pcall(iconFrame.GetWidth, iconFrame)
				local okH, h = pcall(iconFrame.GetHeight, iconFrame)
				if okW and okH and w and h then
					originalIconSizes[iconFrame] = { width = w, height = h }
				end
			end
		end

		-- Offsets:
		-- - Target/Focus always use addon-managed X/Y offsets (relative to stock layout or custom anchor).
		-- - Player uses offsets only when locked to the Player frame; when unlocked, Edit Mode
		--   owns the free position and Scoot must not re-anchor.
		local offsetX, offsetY = 0, 0
		if unit == "Target" or unit == "Focus" then
			offsetX = tonumber(cfg.offsetX) or 0
			offsetY = tonumber(cfg.offsetY) or 0
		elseif isPlayer and isLockedToPlayerFrame then
			offsetX = tonumber(cfg.offsetX) or 0
			offsetY = tonumber(cfg.offsetY) or 0
		end

		-- Anchor Mode (Target/Focus only): determines anchor point for cast bar positioning
		-- "default" = stock Blizzard position, "nameTop/healthBottom/powerTop/powerBottom" = custom anchors
		local anchorMode = (unit == "Target" or unit == "Focus") and (cfg.anchorMode or "default") or "default"
		-- Backward-compat: migrate old healthTop → nameTop
		if anchorMode == "healthTop" then
			anchorMode = "nameTop"
			if cfg then cfg.anchorMode = "nameTop" end
		end

		-- Width percent (50–150%; 100 = stock width)
		local widthPct = tonumber(cfg.widthPct) or 100
		if widthPct < 50 then widthPct = 50 elseif widthPct > 150 then widthPct = 150 end

		-- Cast Bar Scale (addon-only, Target/Focus only; 50–150%; 100 = stock scale)
		local castBarScale = tonumber(cfg.castBarScale) or 100
		if castBarScale < 50 then castBarScale = 50 elseif castBarScale > 150 then castBarScale = 150 end

		-- Icon sizing, padding, and visibility relative to bar
		local iconWidth = tonumber(cfg.iconWidth)
		local iconHeight = tonumber(cfg.iconHeight)
		local iconBarPadding = tonumber(cfg.iconBarPadding) or 0
		local iconDisabled = cfg.iconDisabled == true

		local function apply()
			-- When this is invoked from a SetStatusBarTexture/SetStatusBarColor hook
			-- during combat, treat this as a "visual-only" refresh: apply textures/colors
			-- but avoid re-anchoring secure frames or changing layout, which can taint.
			local inCombat = InCombatLockdown and InCombatLockdown()
			local visualOnly = inCombat and getProp(frame, "castVisualOnly")

			-- Layout (position/size/icon) is skipped for in-combat visual-only refreshes.
			if not visualOnly then
				if frame.ClearAllPoints and frame.SetPoint then
					-- Apply width scaling relative to original width (Player only)
					if isPlayer and origWidth and frame.SetWidth then
						local scale = widthPct / 100.0
						pcall(frame.SetWidth, frame, origWidth * scale)
					end

					-- Anchor behaviour:
					-- - Player: only override anchors when locked to the Player frame so Edit Mode retains
					--   full control when the bar is unlocked and freely positioned.
					-- - Target/Focus: anchor based on anchorMode setting (default = stock baseline, or custom anchor to Health/Power bar).
					if isPlayer then
						if isLockedToPlayerFrame then
							setProp(frame, "ignoreSetPoint", true)
							frame:ClearAllPoints()
							frame:SetPoint(
								orig.point,
								orig.relativeTo,
								orig.relativePoint,
								(orig.xOfs or 0) + offsetX,
								(orig.yOfs or 0) + offsetY
							)
							setProp(frame, "ignoreSetPoint", nil)
						end
					else
						-- Target/Focus: check anchorMode for custom anchoring
						-- Track the active anchor mode so the SetPoint hook knows when to re-apply
						activeAnchorModes[unit] = anchorMode

						local anchorApplied = false
						if anchorMode ~= "default" then
							-- Resolve the target bar based on anchor mode
							local anchorBar
							local anchorEdge -- "top" or "bottom"
							if anchorMode == "nameTop" then
								anchorBar = resolveNameFS(unit)
								anchorEdge = "top"
							elseif anchorMode == "healthBottom" then
								anchorBar = resolveHealthBar(unit)
								anchorEdge = "bottom"
							elseif anchorMode == "powerTop" then
								anchorBar = resolvePowerBar(unit)
								anchorEdge = "top"
							elseif anchorMode == "powerBottom" then
								anchorBar = resolvePowerBar(unit)
								anchorEdge = "bottom"
							end

							if anchorBar then
								-- Use direct relative anchoring to the Health/Power bar
								-- Automatically handles scale and position changes
								-- - For "top" edges: cast bar sits ABOVE the anchor bar (cast bar's BOTTOM to bar's TOP)
								-- - For "bottom" edges: cast bar sits BELOW the anchor bar (cast bar's TOP to bar's BOTTOM)
								local castBarPoint = (anchorEdge == "top") and "BOTTOM" or "TOP"
								local anchorPoint = (anchorEdge == "top") and "TOP" or "BOTTOM"

								-- Flag to prevent the SetPoint hook from triggering a re-apply loop
								setProp(frame, "ignoreSetPoint", true)
								frame:ClearAllPoints()
								frame:SetPoint(
									castBarPoint,
									anchorBar,
									anchorPoint,
									offsetX,
									offsetY
								)
								setProp(frame, "ignoreSetPoint", nil)
								anchorApplied = true
							end
						end

						-- Fallback to default (stock baseline) positioning if custom anchor not applied
						if not anchorApplied then
							setProp(frame, "ignoreSetPoint", true)
							frame:ClearAllPoints()
							frame:SetPoint(
								orig.point,
								orig.relativeTo,
								orig.relativePoint,
								(orig.xOfs or 0) + offsetX,
								(orig.yOfs or 0) + offsetY
							)
							setProp(frame, "ignoreSetPoint", nil)
						end
					end

					-- Apply icon visibility, size, and padding before bar styling
					local icon = frame.Icon
					if icon then
						-- Visibility: when disabled, hide the icon via alpha and clear any
						-- container-based borders so only the bar remains.
						if iconDisabled then
							if icon.SetAlpha then pcall(icon.SetAlpha, icon, 0) end
							local container = getIconBorderContainer(icon)
							if container and addon.Borders and addon.Borders.HideAll then
								addon.Borders.HideAll(container)
							end
						else
							if icon.SetAlpha then pcall(icon.SetAlpha, icon, 1) end

							local baseSize = originalIconSizes[icon]
							if iconWidth or iconHeight then
								local w = tonumber(iconWidth) or (baseSize and baseSize.width) or (icon.GetWidth and icon:GetWidth()) or 16
								local h = tonumber(iconHeight) or (baseSize and baseSize.height) or (icon.GetHeight and icon:GetHeight()) or 16
								-- Clamp to a reasonable range for cast bar icons
								w = math.max(8, math.min(64, w))
								h = math.max(8, math.min(64, h))
								pcall(icon.SetSize, icon, w, h)
								-- Ensure contained texture follows the resized frame
								if icon.Icon and icon.Icon.SetAllPoints then
									icon.Icon:SetAllPoints(icon)
								end
								if icon.IconMask and icon.IconMask.SetAllPoints then
									icon.IconMask:SetAllPoints(icon)
								end
							end

							-- Icon/Bar padding: adjust icon X offset relative to its original anchor
							local baseAnchor = originalIconAnchors[icon]
							if baseAnchor and icon.ClearAllPoints and icon.SetPoint then
								-- Positive padding increases the gap between icon (left) and bar by moving icon further left.
								local pad = tonumber(iconBarPadding) or 0
								local baseX = baseAnchor.xOfs or 0
								local baseY = baseAnchor.yOfs or 0
								local newX = baseX - pad
								icon:ClearAllPoints()
								icon:SetPoint(
									baseAnchor.point or "LEFT",
									baseAnchor.relativeTo or frame,
									baseAnchor.relativePoint or baseAnchor.point or "LEFT",
									newX,
									baseY
								)
							end
						end
					end

					-- Cast Bar Scale (addon-only, Target/Focus only)
					if (unit == "Target" or unit == "Focus") and frame.SetScale then
						local scale = castBarScale / 100.0
						pcall(frame.SetScale, frame, scale)
					end
				end

				-- Player Cast Bar: TextBorder visibility (only visible when unlocked)
				-- The TextBorder frame only exists on PlayerCastingBarFrame when it's not locked to the Player Frame.
				if isPlayer and not isLockedToPlayerFrame then
					local textBorder = frame.TextBorder
					if textBorder then
						local hideTextBorder = cfg.hideTextBorder == true
						if hideTextBorder then
							if textBorder.SetShown then
								pcall(textBorder.SetShown, textBorder, false)
							elseif textBorder.Hide then
								pcall(textBorder.Hide, textBorder)
							end
						else
							if textBorder.SetShown then
								pcall(textBorder.SetShown, textBorder, true)
							elseif textBorder.Show then
								pcall(textBorder.Show, textBorder)
							end
						end
					end
				end

				-- One-time Play() hooks for default-mode cast flash / completion flare toggles.
				-- Reads live DB config per Play() so toggling takes effect immediately.
				-- textFillActive check prevents double-stopping with the text-fill hooks.
				if isPlayer and not getProp(frame, "castFlashAnimHooked") then
					setProp(frame, "castFlashAnimHooked", true)
					local hookUnit = unit
					local function getCastCfg()
						local db = addon and addon.db and addon.db.profile
						return db and db.unitFrames and db.unitFrames[hookUnit] and db.unitFrames[hookUnit].castBar
					end
					-- FlashAnim → hideCastFlash
					local flashAnim = frame.FlashAnim
					if flashAnim and flashAnim.Play and flashAnim.Stop then
						local agRef, stopFn = flashAnim, flashAnim.Stop
						hooksecurefunc(flashAnim, "Play", function()
							if not getProp(frame, "textFillActive") then
								local c = getCastCfg()
								if c and c.hideCastFlash then pcall(stopFn, agRef) end
							end
						end)
					end
					-- InterruptGlowAnim → hideInterruptGlow (works in both default and text-fill modes)
					local intGlowAnim = frame.InterruptGlowAnim
					if intGlowAnim and intGlowAnim.Play and intGlowAnim.Stop then
						local agRef, stopFn = intGlowAnim, intGlowAnim.Stop
						hooksecurefunc(intGlowAnim, "Play", function()
							local c = getCastCfg()
							if c and c.hideInterruptGlow then pcall(stopFn, agRef) end
						end)
					end
					-- StandardFinish → hideCompletionFlare
					local sf = frame.StandardFinish
					if sf and sf.Play and sf.Stop then
						local agRef, stopFn = sf, sf.Stop
						hooksecurefunc(sf, "Play", function()
							if not getProp(frame, "textFillActive") then
								local c = getCastCfg()
								if c and c.hideCompletionFlare then pcall(stopFn, agRef) end
							end
						end)
					end
				end
			end

			-- Player Cast Bar: cosmetic alpha re-assertion on decorative textures.
			-- Lives outside the `if not visualOnly` guard so combat-time visual-only
			-- refreshes (from SetStatusBarTexture/Color hooks) re-apply SetAlpha(0).
			-- Without this, anything that resets a glow texture's alpha mid-combat
			-- (Blizzard re-init, profile/Edit Mode side-effect) leaves it visible
			-- until PLAYER_REGEN_ENABLED, since the layout-guarded path defers.
			if isPlayer then
				local channelShadow = frame.ChannelShadow
				if channelShadow then
					local hideChannelingShadow = cfg.hideChannelingShadow == true
					if channelShadow.SetAlpha then
						pcall(channelShadow.SetAlpha, channelShadow, hideChannelingShadow and 0 or 1)
					end
				end

				local chargeFlash = frame.ChargeFlash
				if chargeFlash and cfg.hideChargeFlash then
					if chargeFlash.SetAlpha then
						pcall(chargeFlash.SetAlpha, chargeFlash, 0)
					end
				end
				local shine = frame.Shine
				if shine and cfg.hideCastShine then
					if shine.SetAlpha then
						pcall(shine.SetAlpha, shine, 0)
					end
				end
				local wispGlow = frame.WispGlow
				if wispGlow and cfg.hideWispGlow then
					if wispGlow.SetAlpha then
						pcall(wispGlow.SetAlpha, wispGlow, 0)
					end
				end
				local standardGlow = frame.StandardGlow
				if standardGlow then
					local hide = not not cfg.hideStandardGlow
					if standardGlow.SetAlpha then
						pcall(standardGlow.SetAlpha, standardGlow, hide and 0 or 1)
					end
				end
				local craftGlow = frame.CraftGlow
				if craftGlow then
					local hide = not not cfg.hideStandardGlow
					if craftGlow.SetAlpha then
						pcall(craftGlow.SetAlpha, craftGlow, hide and 0 or 1)
					end
				end
				local sparkles01 = frame.Sparkles01
				if sparkles01 and cfg.hideChannelSparkles then
					if sparkles01.SetAlpha then
						pcall(sparkles01.SetAlpha, sparkles01, 0)
					end
				end
				local sparkles02 = frame.Sparkles02
				if sparkles02 and cfg.hideChannelSparkles then
					if sparkles02.SetAlpha then
						pcall(sparkles02.SetAlpha, sparkles02, 0)
					end
				end
				local baseGlow = frame.BaseGlow
				if baseGlow and cfg.hideBaseGlow then
					if baseGlow.SetAlpha then
						pcall(baseGlow.SetAlpha, baseGlow, 0)
					end
				end

				if cfg.hideCastFlash then
					local flash = frame.Flash
					if flash and flash.SetAlpha then pcall(flash.SetAlpha, flash, 0) end
				end
				if cfg.hideInterruptGlow then
					local intGlow = frame.InterruptGlow
					if intGlow and intGlow.SetAlpha then pcall(intGlow.SetAlpha, intGlow, 0) end
				end

				if cfg.hideCompletionFlare then
					for _, tex in ipairs({ frame.EnergyGlow, frame.Flakes01, frame.Flakes02, frame.Flakes03 }) do
						if tex and tex.SetAlpha then pcall(tex.SetAlpha, tex, 0) end
					end
				end
			end

			-- Text-Fill Cast Bar mode
			local castBarMode = cfg.castBarMode or "default"

			if castBarMode == "textFill" then
				pcall(applyTextFillMode, frame, cfg, unit, isEmpoweredCast(unit))
			else
				hideTextFillElements(frame)
			end

			-- Apply foreground and background styling via shared bar helpers
			-- When visualOnly is true (combat + hook path from SetStatusBarTexture/SetStatusBarColor),
			-- texture/color is allowed so custom styling persists through Blizzard's updates.
			-- Layout changes are already skipped above when visualOnly is true.
			if castBarMode ~= "textFill" and (not inCombat or visualOnly) and (addon._ApplyToStatusBar or addon._ApplyBackgroundToStatusBar) then
				local db = addon and addon.db and addon.db.profile
				local _uf = db and rawget(db, "unitFrames") or nil
				local _uc = _uf and rawget(_uf, unit) or nil
				local cfgStyle = _uc and rawget(_uc, "castBar") or nil

				-- Foreground: texture + color
				-- Skip during empowered casts: Blizzard uses transparent fill with
				-- stage tiers at BACKGROUND sublevel 4-5. Custom texture hides them.
				if cfgStyle and not isEmpoweredCast(unit) and addon._ApplyToStatusBar and frame.GetStatusBarTexture then
					local texKey = cfgStyle.castBarTexture or "default"
					local colorMode = cfgStyle.castBarColorMode or "default"
					local tint = cfgStyle.castBarTint
					-- For class color, follow Health/Power bars and always use player's class
					local unitId = (unit == "Player" and "player") or (unit == "Target" and "target") or (unit == "Focus" and "focus") or (unit == "Pet" and "pet") or "player"
					-- Pass combatSafe=true only for visual-only refreshes triggered by cast bar hooks.
					-- Allows texture/color re-application in combat while layout operations remain skipped.
					addon._ApplyToStatusBar(frame, texKey, colorMode, tint, "player", "cast", unitId, visualOnly)
				end

				-- Background: texture + color + opacity
				-- Skip during empowered casts: the BG swap helpers handle hiding ScootBG
				-- and restoring stock Background so stage tiers render correctly.
				if cfgStyle and not isEmpoweredCast(unit) and addon._ApplyBackgroundToStatusBar then
					local bgTexKey = cfgStyle.castBarBackgroundTexture or "default"
					local bgColorMode = cfgStyle.castBarBackgroundColorMode or "default"
					local bgOpacity = cfgStyle.castBarBackgroundOpacity or 50
					addon._ApplyBackgroundToStatusBar(frame, bgTexKey, bgColorMode, cfgStyle.castBarBackgroundTint, bgOpacity, unit, "cast")
				end
			end

			-- Spark visibility and color (per unit)
			do
				local spark = frame.Spark
				if spark then
					-- Capture the stock spark vertex color/alpha once so "Default" can restore it later.
					if not originalSparkVertexColor[spark] and spark.GetVertexColor then
						local ok, r, g, b, a = pcall(spark.GetVertexColor, spark)
						if not ok or not r or not g or not b then
							r, g, b, a = 1, 1, 1, 1
						end
						originalSparkVertexColor[spark] = { r or 1, g or 1, b or 1, a or 1 }
					end
					if not originalSparkAlpha[spark] and spark.GetAlpha then
						local ok, alpha = pcall(spark.GetAlpha, spark)
						originalSparkAlpha[spark] = (ok and alpha) or 1
					end

					local sparkHidden = cfg.castBarSparkHidden == true
					-- Empowered charge cursor is essential UX feedback — force-show during empowered casts
					if isEmpoweredCast(unit) then sparkHidden = false end
					local colorMode = cfg.castBarSparkColorMode or "default"
					local tintTbl = type(cfg.castBarSparkTint) == "table" and cfg.castBarSparkTint or {1,1,1,1}

					-- Determine effective color from mode:
					-- - "default": use the stock vertex color captured above.
					-- - "custom": apply the user tint (RGBA) on top of the spark.
					local base = originalSparkVertexColor[spark] or {1,1,1,1}
					local r, g, b, a = base[1] or 1, base[2] or 1, base[3] or 1, base[4] or 1
					if colorMode == "custom" then
						r = tintTbl[1] or r
						g = tintTbl[2] or g
						b = tintTbl[3] or b
						a = tintTbl[4] or a
					end

					if spark.SetVertexColor then
						pcall(spark.SetVertexColor, spark, r, g, b, a)
					end

					-- Visibility: hide the spark via alpha to avoid fighting internal Show/Hide logic.
					if sparkHidden then
						if spark.SetAlpha then
							pcall(spark.SetAlpha, spark, 0)
						end
					else
						if spark.SetAlpha then
							local baseAlpha = originalSparkAlpha[spark] or a or 1
							pcall(spark.SetAlpha, spark, baseAlpha)
						end
					end
				end
			end

			-- Custom Cast Bar border (per unit, uses bar border system)
			if castBarMode == "textFill" then
				if addon.BarBorders and addon.BarBorders.ClearBarFrame then addon.BarBorders.ClearBarFrame(frame) end
				if addon.Borders and addon.Borders.HideAll then addon.Borders.HideAll(frame) end
				if frame.Border and frame.Border.SetShown then pcall(frame.Border.SetShown, frame.Border, false) end
			else
			do
				local enabled = not not cfg.castBarBorderEnable
				local styleKey = cfg.castBarBorderStyle or "square"
				local hiddenEdges = cfg.castBarBorderHiddenEdges
				local tintEnabled = not not cfg.castBarBorderTintEnable
				local tintTbl = type(cfg.castBarBorderTintColor) == "table" and cfg.castBarBorderTintColor or {1,1,1,1}
				local tintColor = {
					tintTbl[1] or 1,
					tintTbl[2] or 1,
					tintTbl[3] or 1,
					tintTbl[4] or 1,
				}
				local thickness = tonumber(cfg.castBarBorderThickness) or 1
				if thickness < 1 then thickness = 1 elseif thickness > 16 then thickness = 16 end

				-- User-controlled inset plus a small thickness-derived term; biases the Default (square)
				-- style outward slightly, with per-unit tuning.
				local userInsetH = tonumber(cfg.castBarBorderInsetH) or tonumber(cfg.castBarBorderInset) or 0
				local userInsetV = tonumber(cfg.castBarBorderInsetV) or tonumber(cfg.castBarBorderInset) or 0
				if userInsetH < -4 then userInsetH = -4 elseif userInsetH > 4 then userInsetH = 4 end
				if userInsetV < -4 then userInsetV = -4 elseif userInsetV > 4 then userInsetV = 4 end
				local derivedInset = math.floor((thickness - 1) * 0.5)
				local baseInset = 0
				if styleKey == "square" then
					if unit == "Player" then
						baseInset = -1
					elseif unit == "Target" then
						baseInset = -2
					elseif unit == "Focus" then
						baseInset = 0
					else
						baseInset = -2
					end
				end
				local combinedInsetH = baseInset + userInsetH + derivedInset
				local combinedInsetV = baseInset + userInsetV + derivedInset

				-- Clear any prior border when disabled
				if not enabled or styleKey == "none" then
					if addon.BarBorders and addon.BarBorders.ClearBarFrame then addon.BarBorders.ClearBarFrame(frame) end
					if addon.Borders and addon.Borders.HideAll then addon.Borders.HideAll(frame) end
				else
					-- Determine effective color from mode + style
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
						if addon.BarBorders.ClearBarFrame then addon.BarBorders.ClearBarFrame(frame) end

						-- Ensure cast bar borders are parented directly to the StatusBar so they
						-- inherit its visibility (hidden when no cast is active).
						setProp(frame, "borderContainerParentRef", nil)

						-- Unit-specific per-side pad adjustments for Cast Bar:
						-- Player: symmetric (no extra nudges; baseInset handles feel).
						-- Target: top pulled down slightly, left/right pulled in slightly more, bottom unchanged.
						if enabled and unit == "Target" then
							setProp(frame, "borderPadAdjust", {
								left = -2,
								right = -2,
								top = -1,
								bottom = 0,
							})
						else
							setProp(frame, "borderPadAdjust", nil)
						end

						handled = addon.BarBorders.ApplyToBarFrame(frame, styleKey, {
							color = color,
							thickness = thickness,
							levelOffset = 1,
							insetH = combinedInsetH,
							insetV = combinedInsetV,
							hiddenEdges = hiddenEdges,
						})
					end

					if not handled then
						-- Fallback: pixel (square) border using generic square helper
						if addon.BarBorders and addon.BarBorders.ClearBarFrame then addon.BarBorders.ClearBarFrame(frame) end
						if addon.Borders and addon.Borders.ApplySquare then
							local sqColor = tintEnabled and tintColor or {0, 0, 0, 1}
							local baseY = (thickness <= 1) and 0 or 1
							local baseX = 1
							local expandY = baseY - combinedInsetV
							local expandX = baseX - combinedInsetH
							if expandX < -6 then expandX = -6 elseif expandX > 6 then expandX = 6 end
							if expandY < -6 then expandY = -6 elseif expandY > 6 then expandY = 6 end

							-- Per-unit fine-tuning for the pixel fallback:
							-- Player: top/bottom/left are good; pull the right edge in slightly.
							-- Target: top pulled down slightly; left/right pulled in more; bottom remains aligned.
							local exLeft, exRight, exTop, exBottom = expandX, expandX, expandY, expandY
							local name = frame.GetName and frame:GetName()
							if name == "PlayerCastingBarFrame" then
								-- Reduce right-side expansion by 1px (clamped to >= 0)
								exRight = math.max(0, exRight - 1)
							elseif name == "TargetFrameSpellBar" then
								exLeft  = math.max(0, exLeft - 2)
								exRight = math.max(0, exRight - 2)
								exTop   = math.max(0, exTop - 1)
							end

							addon.Borders.ApplySquare(frame, {
								size = thickness,
								color = sqColor,
								layer = "OVERLAY",
								layerSublevel = 3,
								expandLeft = exLeft,
								expandRight = exRight,
								expandTop = exTop,
								expandBottom = exBottom,
								hiddenEdges = hiddenEdges,
							})
						end
					end
				end

				-- Hide Blizzard's stock cast bar border when custom borders are enabled (all units that expose .Border)
				local border = frame.Border
				if border then
					if border.SetShown then
						pcall(border.SetShown, border, not enabled)
					elseif border.SetAlpha then
						pcall(border.SetAlpha, border, enabled and 0 or 1)
					end
				end
			end
			end -- castBarMode ~= "textFill"

			-- Cast Bar Icon border (per unit; reuses icon border system from Cooldown Manager)
			do
				local icon = frame.Icon
				if icon then
					local iconBorderEnabled = not not cfg.iconBorderEnable
					local iconStyle = cfg.iconBorderStyle or "square"
					if iconStyle == "none" then
						iconStyle = "square"
						cfg.iconBorderStyle = iconStyle
					end
					local iconThicknessVal = tonumber(cfg.iconBorderThickness) or 1
					if iconThicknessVal < 1 then iconThicknessVal = 1 elseif iconThicknessVal > 16 then iconThicknessVal = 16 end
					local iconTintEnabled = not not cfg.iconBorderTintEnable
					local tintTbl = type(cfg.iconBorderTintColor) == "table" and cfg.iconBorderTintColor or {1,1,1,1}
					local iconTintColor = {
						tintTbl[1] or 1,
						tintTbl[2] or 1,
						tintTbl[3] or 1,
						tintTbl[4] or 1,
					}

					-- Never draw a border when the icon itself is disabled.
					if iconBorderEnabled and not iconDisabled then
						-- Defensive cleanup: if any legacy Scoot borders were drawn directly on the
						-- icon texture (pre-wrapper versions), hide them once so only the current
						-- wrapper/container-based border remains visible.
						if ((addon.Borders.GetAtlasBorder and addon.Borders.GetAtlasBorder(icon)) or (addon.Borders.GetTextureBorder and addon.Borders.GetTextureBorder(icon)) or icon.ScootSquareBorderContainer or icon.ScootSquareBorderEdges)
							and addon.Borders and addon.Borders.HideAll then
							addon.Borders.HideAll(icon)
						end

						addon.ApplyIconBorderStyle(icon, iconStyle, {
							thickness = iconThicknessVal,
							color = iconTintEnabled and iconTintColor or nil,
							tintEnabled = iconTintEnabled,
							db = cfg,
							thicknessKey = "iconBorderThickness",
							tintColorKey = "iconBorderTintColor",
							defaultThickness = 1,
						})
					else
						-- Clear any existing icon border container when custom border is disabled
						-- or when the icon itself is disabled/hidden.
					local container = getIconBorderContainer(icon)
					if container and addon.Borders and addon.Borders.HideAll then
						addon.Borders.HideAll(container)
					elseif addon.Borders and addon.Borders.HideAll then
							addon.Borders.HideAll(icon)
						end
					end
				end
			end

			-- Ensure cast bar text (spell name / cast time) renders above custom borders.
			-- BarBorders creates a holder frame at barLevel + levelOffset, which causes
			-- child FontStrings to render behind the border. Text is re-parented to a thin
			-- overlay frame at a level above the border holder.
			do
				local borderEnabled = not not cfg.castBarBorderEnable
				local borderStyle = cfg.castBarBorderStyle or "square"
				local needsOverlay = castBarMode ~= "textFill" and borderEnabled and borderStyle ~= "none"

				if needsOverlay then
					local overlay = getProp(frame, "ScootCastTextOverlay")
					if not overlay then
						overlay = CreateFrame("Frame", nil, frame)
						overlay:SetAllPoints(frame)
						setProp(frame, "ScootCastTextOverlay", overlay)
					end
					-- Determine level above the border holder.  BarBorders uses
					-- barLevel + levelOffset (1 for cast bars); ApplySquare uses the
					-- bar's own level.  barLevel + 3 safely clears both paths.
					local barLevel = (frame.GetFrameLevel and frame:GetFrameLevel()) or 0
					overlay:SetFrameLevel(barLevel + 3)
					overlay:Show()

					if frame.Text and frame.Text.SetParent then
						pcall(frame.Text.SetParent, frame.Text, overlay)
					end
					if unit == "Player" and frame.CastTimeText and frame.CastTimeText.SetParent then
						pcall(frame.CastTimeText.SetParent, frame.CastTimeText, overlay)
					end
				else
					-- Borders disabled: restore text to bar frame
					local overlay = getProp(frame, "ScootCastTextOverlay")
					if overlay then
						if frame.Text and frame.Text.SetParent then
							pcall(frame.Text.SetParent, frame.Text, frame)
						end
						if unit == "Player" and frame.CastTimeText and frame.CastTimeText.SetParent then
							pcall(frame.CastTimeText.SetParent, frame.CastTimeText, frame)
						end
						overlay:Hide()
					end
				end
			end

			-- Spell Name Text styling (Player/Target/Focus)
			-- Targets: PlayerCastingBarFrame.Text, TargetFrameSpellBar.Text, FocusFrameSpellBar.Text
			-- Borders: PlayerCastingBarFrame.TextBorder, TargetFrameSpellBar.TextBorder, FocusFrameSpellBar.TextBorder
			do
				-- CastingBarFrameBaseTemplate exposes the spell-name FontString as .Text
				local spellFS = frame.Text
				if spellFS then
					-- Capture a stable baseline anchor once per session so offsets are relative.
					-- For the cast bar, always treats the spell name as centered within the bar,
					-- regardless of whether the bar is locked to the Player frame or free-floating.
					local function ensureSpellBaseline(fs, key)
						addon._ufCastSpellNameBaselines[key] = addon._ufCastSpellNameBaselines[key] or {}
						local b = addon._ufCastSpellNameBaselines[key]
						if b.point == nil then
							-- Force a centered baseline: center of the cast bar frame.
							local parent = (fs and fs.GetParent and fs:GetParent()) or frame
							b.point, b.relTo, b.relPoint, b.x, b.y = "CENTER", parent, "CENTER", 0, 0
						end
						return b
					end

					-- All units use the same "Hide Spell Name" toggle key
					local disabled = not not cfg.castBarSpellNameHidden

					-- Visibility: use alpha instead of Show/Hide to avoid fighting Blizzard logic
					if spellFS.SetAlpha then
						pcall(spellFS.SetAlpha, spellFS, disabled and 0 or 1)
					end

					-- Border/Backdrop behind the spell text
					-- Player: cfg.hideSpellNameBackdrop (TextBorder only visible when unlocked)
					-- Target/Focus: cfg.hideSpellNameBorder (TextBorder is always present)
					local hideBorder = false
					if unit == "Player" then
						hideBorder = not not cfg.hideSpellNameBackdrop
					else
						-- Target/Focus use hideSpellNameBorder
						hideBorder = not not cfg.hideSpellNameBorder
					end
					local border = frame.TextBorder
					if border and border.SetAlpha then
						pcall(border.SetAlpha, border, hideBorder and 0 or 1)
					elseif border and border.Hide and border.Show then
						if hideBorder then
							pcall(border.Hide, border)
						else
							pcall(border.Show, border)
						end
					end

					if not disabled then
						local styleCfg = cfg.spellNameText or {}
						-- Font / size / outline
						local face = addon.ResolveFontFace and addon.ResolveFontFace(styleCfg.fontFace or "FRIZQT__")
							or (select(1, _G.GameFontNormal:GetFont()))
						local size = tonumber(styleCfg.size) or 10
						local outline = tostring(styleCfg.style or "OUTLINE")
						if addon.ApplyFontStyle then
							addon.ApplyFontStyle(spellFS, face, size, outline)
						elseif spellFS.SetFont then
							pcall(spellFS.SetFont, spellFS, face, size, outline)
						end

						-- Install gradient SetText hook (once per FontString)
						local hookUnit = unit
						installGradientHook(spellFS, function()
							local d = addon and addon.db and addon.db.profile
							if not d then return nil end
							local uf = d.unitFrames and d.unitFrames[hookUnit]
							local cb = uf and uf.castBar
							return cb and cb.spellNameText
						end, frame)

						-- Color (mode-aware: default/class/custom/classGradient/customGradient)
						applySpellNameColor(spellFS, styleCfg, frame)

						-- Offsets relative to baseline (centered)
						local ox = (styleCfg.offset and tonumber(styleCfg.offset.x)) or 0
						local oy = (styleCfg.offset and tonumber(styleCfg.offset.y)) or 0
						if spellFS.ClearAllPoints and spellFS.SetPoint then
							local b = ensureSpellBaseline(spellFS, unit .. ":spellName")
							spellFS:ClearAllPoints()
							-- Ensure horizontal alignment is centered so long and short strings both
							-- grow outwards from the middle of the bar.
							if spellFS.SetJustifyH then
								pcall(spellFS.SetJustifyH, spellFS, "CENTER")
							end
							spellFS:SetPoint(
								b.point or "CENTER",
								b.relTo or (spellFS.GetParent and spellFS:GetParent()) or frame,
								b.relPoint or b.point or "CENTER",
								(b.x or 0) + ox,
								(b.y or 0) + oy
							)
						end
					end
				end
			end

			-- Sync filled text in textFill mode (after spell name styling)
			if castBarMode == "textFill" then
				pcall(syncTextFillText, frame, cfg)
			end

			-- Cast Time Text styling (Player only; Target/Focus Cast Bars do not have cast time display)
			if unit == "Player" then
				do
					local castTimeFS = frame.CastTimeText
					if castTimeFS then
						-- Capture a stable baseline anchor once per session so offsets are relative
						local function ensureCastTimeBaseline(fs, key)
							addon._ufCastTimeTextBaselines[key] = addon._ufCastTimeTextBaselines[key] or {}
							local b = addon._ufCastTimeTextBaselines[key]
							if b.point == nil then
								if fs and fs.GetPoint then
									local p, relTo, rp, x, y = fs:GetPoint(1)
									b.point = p or "CENTER"
									b.relTo = relTo or (fs.GetParent and fs:GetParent()) or frame
									b.relPoint = rp or b.point
									b.x = tonumber(x) or 0
									b.y = tonumber(y) or 0
								else
									b.point, b.relTo, b.relPoint, b.x, b.y =
										"CENTER", (fs and fs.GetParent and fs:GetParent()) or frame, "CENTER", 0, 0
								end
							end
							return b
						end

						local styleCfg = cfg.castTimeText or {}
						-- Font / size / outline
						local face = addon.ResolveFontFace and addon.ResolveFontFace(styleCfg.fontFace or "FRIZQT__")
							or (select(1, _G.GameFontNormal:GetFont()))
						local size = tonumber(styleCfg.size) or 10
						local outline = tostring(styleCfg.style or "OUTLINE")
						if addon.ApplyFontStyle then
							addon.ApplyFontStyle(castTimeFS, face, size, outline)
						elseif castTimeFS.SetFont then
							pcall(castTimeFS.SetFont, castTimeFS, face, size, outline)
						end

						-- Color (simple RGBA, no mode for now)
						local c = styleCfg.color or {1, 1, 1, 1}
						if castTimeFS.SetTextColor then
							pcall(castTimeFS.SetTextColor, castTimeFS, c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
						end

						-- Offsets relative to baseline
						local ox = (styleCfg.offset and tonumber(styleCfg.offset.x)) or 0
						local oy = (styleCfg.offset and tonumber(styleCfg.offset.y)) or 0
						if castTimeFS.ClearAllPoints and castTimeFS.SetPoint then
							local b = ensureCastTimeBaseline(castTimeFS, "Player:castTime")
							castTimeFS:ClearAllPoints()
							castTimeFS:SetPoint(
								b.point or "CENTER",
								b.relTo or (castTimeFS.GetParent and castTimeFS:GetParent()) or frame,
								b.relPoint or b.point or "CENTER",
								(b.x or 0) + ox,
								(b.y or 0) + oy
							)
						end
					end
				end
			end
		end

		-- BorderShield visibility
		do
			local borderShield = frame.BorderShield
			if borderShield then
				local hideBorderShield = not not cfg.castBarBorderShieldHidden
				if hideBorderShield then
					if borderShield.SetAlpha then
						pcall(borderShield.SetAlpha, borderShield, 0)
					elseif borderShield.Hide then
						pcall(borderShield.Hide, borderShield)
					end
				else
					if borderShield.SetAlpha then
						pcall(borderShield.SetAlpha, borderShield, 1)
					elseif borderShield.Show then
						pcall(borderShield.Show, borderShield)
					end
				end
			end
		end

		local inCombat = InCombatLockdown and InCombatLockdown()
		-- For normal styling passes triggered by profile changes or /reload, avoids
		-- touching secure cast bar anchors during combat and defer until combat ends.
		-- For visual-only refreshes triggered from SetStatusBarTexture/Color hooks,
		-- allows apply() to run in combat so custom textures/colors remain active.
		if inCombat and not getProp(frame, "castVisualOnly") then
			if _G.C_Timer and _G.C_Timer.After then
				_G.C_Timer.After(0.1, function()
					if not (InCombatLockdown and InCombatLockdown()) then
						apply()
					end
				end)
			end
		else
			apply()
		end
	end

	function addon.ApplyUnitFrameCastBarFor(unit)
		applyCastBarForUnit(unit)
	end

	function addon.ApplyAllUnitFrameCastBars()
		applyCastBarForUnit("Player")
		applyCastBarForUnit("Target")
		applyCastBarForUnit("Focus")
	end

	-- Empowered cast event tracking + stage tier texture replacement
	do
		local ef = CreateFrame("Frame")
		ef:RegisterEvent("UNIT_SPELLCAST_EMPOWER_START")
		ef:RegisterEvent("UNIT_SPELLCAST_EMPOWER_STOP")
		ef:RegisterEvent("UNIT_SPELLCAST_STOP")
		ef:RegisterEvent("UNIT_SPELLCAST_FAILED")
		ef:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
		ef:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START")

		local tokenToUnit = { player = "Player", target = "Target", focus = "Focus" }

		-- Background swap helpers: hide ScootBG and restore stock Background during
		-- empowered casts so stage tier textures (sublevel 4-5) render correctly.
		local function hideScootBGForEmpowered(unitToken)
			local titleUnit = tokenToUnit[unitToken]
			if not titleUnit then return end
			local frame = resolveCastBarFrame(titleUnit)
			if not frame then return end
			local scootBG = getProp(frame, "ScootBG")
			if scootBG and scootBG.SetAlpha then
				pcall(scootBG.SetAlpha, scootBG, 0)
			end
			if frame.Background and frame.Background.SetAlpha then
				pcall(frame.Background.SetAlpha, frame.Background, 1)
			end
			setProp(frame, "empoweredBGSwapped", true)
		end

		local function restoreScootBGAfterEmpowered(unitToken)
			local titleUnit = tokenToUnit[unitToken]
			if not titleUnit then return end
			local frame = resolveCastBarFrame(titleUnit)
			if not frame then return end
			if not getProp(frame, "empoweredBGSwapped") then return end
			setProp(frame, "empoweredBGSwapped", nil)
			C_Timer.After(0, function()
				-- Don't restore normal styling if a new empowered cast has started
				if empoweredCastActive[unitToken] then return end
				if addon and addon.ApplyUnitFrameCastBarFor then
					addon.ApplyUnitFrameCastBarFor(titleUnit)
				end
			end)
		end

		-- Weak-key table for Scoot-owned tier overlay textures (avoids writing to Blizzard frame tables)
		local tierOverlays = setmetatable({}, { __mode = "k" })
		local empoweredStageUpdater

		-- Tier colors: shared from textfill.lua via CB namespace
		local TIER_COLORS_NORMAL = CB._TIER_COLORS_NORMAL
		local TIER_COLORS_DISABLED = CB._TIER_COLORS_DISABLED

		-- Lazily create the shared empowered stage updater (handles both default and text-fill modes).
		-- OnUpdate reads CurrSpellStage and transitions colors on tier overlays or text-fill segments.
		local function ensureEmpoweredStageUpdater()
			if empoweredStageUpdater then return end
			empoweredStageUpdater = CreateFrame("Frame")
			empoweredStageUpdater:SetScript("OnUpdate", function(self)
				local f = self._castFrame
				if not f then
					self:Hide()
					return
				end
				local stage = f.CurrSpellStage
				if not stage or stage == self._lastStage or type(stage) ~= "number" then return end
				if issecretvalue and issecretvalue(stage) then return end
				self._lastStage = stage

				-- Text-fill empowered mode: update segment + cap + text colors
				if getProp(f, "textFillEmpowered") then
					local els = getProp(f, "textFillElements")
					local emp = els and els.empowered
					if emp and emp.active then
						local CN = CB._TIER_COLORS_NORMAL
						local CD = CB._TIER_COLORS_DISABLED
						-- Unfilled segments: completed stages go bright
						for i = 1, emp.numActive do
							local completed = (i <= stage)
							local c = completed and CN[i] or CD[i]
							c = c or CD[#CD]
							if emp.unfilledSegs[i] then
								emp.unfilledSegs[i]:SetColorTexture(c[1], c[2], c[3], 1)
							end
						end
						-- Unfilled left cap: always bright (stage 1 reached first)
						local firstN = CN[1]
						if els.unfilledLeftCap and firstN then
							els.unfilledLeftCap:SetColorTexture(firstN[1], firstN[2], firstN[3], 1)
						end
						-- Unfilled right cap: bright when last stage reached
						local lastIdx = emp.numActive
						local lastCompleted = (lastIdx <= stage)
						local lastC = lastCompleted and CN[lastIdx] or CD[lastIdx]
						lastC = lastC or CD[#CD]
						if els.unfilledRightCap then
							els.unfilledRightCap:SetColorTexture(lastC[1], lastC[2], lastC[3], 1)
						end
						-- Filled text: current stage color
						local stageColor = CN[stage] or CN[#CN]
						if els.filledText and stageColor then
							els.filledText:SetTextColor(stageColor[1], stageColor[2], stageColor[3], 1)
						end
					end
					return
				end

				-- Default mode: update tier overlay vertex colors
				if not f.StageTiers then
					self:Hide()
					return
				end
				for _, tier in ipairs(f.StageTiers) do
					local ov = tierOverlays[tier]
					if ov and ov._tierIndex then
						local active = (ov._tierIndex <= stage)
						local c = active and ov._nColor or ov._dColor
						if c then
							ov:SetVertexColor(c[1], c[2], c[3], 1)
						end
					end
				end
			end)
		end

		-- Replace stage tier atlas textures with Scoot-owned overlay textures + vertex colors
		-- that preserve the stage color progression (green→yellow→orange→red).
		-- SetTexture cannot visually override SetAtlas on Blizzard-owned textures, so Scoot creates
		-- its own textures at a higher sublevel and hides the originals behind them.
		local function applyScootTextureToTiers(unitToken)
			local titleUnit = tokenToUnit[unitToken]
			if not titleUnit then return end
			local frame = resolveCastBarFrame(titleUnit)
			if not frame then return end

			-- Read user's configured texture key
			local db = addon and addon.db and addon.db.profile
			if not db then return end
			local cfg = db.unitFrames and db.unitFrames[titleUnit] and db.unitFrames[titleUnit].castBar
			if not cfg then return end
			local texKey = cfg.castBarTexture or "default"
			if texKey == "default" then return end

			-- Resolve to a file path
			local texturePath = addon.Media and addon.Media.ResolveBarTexturePath and addon.Media.ResolveBarTexturePath(texKey)
			if not texturePath then return end

			-- Defer so Blizzard's AddStages has completed and StageTiers is populated
			C_Timer.After(0, function()
				-- Guard: empowered cast may have ended before this deferred callback fires
				if not empoweredCastActive[unitToken] then return end
				if not frame.StageTiers then return end
				-- Guard against secret values on the StageTiers table
				if issecretvalue and issecretvalue(frame.StageTiers) then return end

				for i, tier in ipairs(frame.StageTiers) do
					if tier and not (tier.IsForbidden and tier:IsForbidden()) then
						local nColor = TIER_COLORS_NORMAL[i] or TIER_COLORS_NORMAL[#TIER_COLORS_NORMAL]
						local dColor = TIER_COLORS_DISABLED[i] or TIER_COLORS_DISABLED[#TIER_COLORS_DISABLED]

						-- Get or create Scoot-owned overlay on this tier frame.
						-- Sublevel 7: renders above Normal/Disabled (4) and Glow (5).
						local overlay = tierOverlays[tier]
						if not overlay then
							overlay = tier:CreateTexture(nil, "BACKGROUND", nil, 7)
							overlay:SetAllPoints()
							tierOverlays[tier] = overlay
						end

						-- Apply custom texture + disabled color (all tiers start disabled)
						overlay:SetTexture(texturePath)
						overlay:SetTexCoord(0, 1, 0, 1)
						overlay:SetVertexColor(dColor[1], dColor[2], dColor[3], 1)
						overlay:Show()

						-- Store colors for stage progression (safe: overlay is Scoot-created)
						overlay._nColor = nColor
						overlay._dColor = dColor
						overlay._tierIndex = i

						-- Hide original Blizzard atlas textures behind the Scoot overlay
						pcall(tier.Normal.SetAlpha, tier.Normal, 0)
						pcall(tier.Disabled.SetAlpha, tier.Disabled, 0)
					end
				end

				-- Start stage progression tracker
				ensureEmpoweredStageUpdater()
				empoweredStageUpdater._castFrame = frame
				empoweredStageUpdater._lastStage = nil
				empoweredStageUpdater:Show()

				-- Force the StatusBar fill texture to be invisible during empowered casts.
				-- Blizzard calls SetColorFill(0,0,0,0) but the texture from a prior normal cast
				-- (set by Scoot's _ApplyToStatusBar) may still render at BORDER layer, above the tiers.
				-- The fill auto-restores when the next normal cast starts (Blizzard's SetStatusBarTexture
				-- triggers Scoot's hook which re-applies the full foreground).
				local fill = frame:GetStatusBarTexture()
				if fill and not (issecretvalue and issecretvalue(fill)) then
					if fill.SetAlpha then pcall(fill.SetAlpha, fill, 0) end
				end
			end)
		end

		-- Hide overlay textures and restore original Blizzard tier textures
		local function cleanupTierOverlays(unitToken)
			if empoweredStageUpdater then
				empoweredStageUpdater:Hide()
			end
			local titleUnit = tokenToUnit[unitToken]
			if not titleUnit then return end
			local f = resolveCastBarFrame(titleUnit)
			if f and f.StageTiers then
				for _, tier in ipairs(f.StageTiers) do
					local ov = tierOverlays[tier]
					if ov then ov:Hide() end
					-- Restore original alpha so Blizzard manages visibility normally
					pcall(tier.Normal.SetAlpha, tier.Normal, 1)
					pcall(tier.Disabled.SetAlpha, tier.Disabled, 1)
				end
				-- Restore fill texture alpha (set to 0 by applyScootTextureToTiers)
				local fill = f:GetStatusBarTexture()
				if fill and not (issecretvalue and issecretvalue(fill)) then
					if fill.SetAlpha then pcall(fill.SetAlpha, fill, 1) end
				end
			end
		end

		-- Check if a unit is configured for text-fill mode
		local function isTextFillMode(unitToken)
			local titleUnit = tokenToUnit[unitToken]
			if not titleUnit then return false end
			local db = addon and addon.db and addon.db.profile
			if not db then return false end
			local uf = db.unitFrames and db.unitFrames[titleUnit]
			local cfg = uf and uf.castBar
			return cfg and cfg.castBarMode == "textFill"
		end

		ef:SetScript("OnEvent", function(self, event, unit, ...)
			if event == "UNIT_SPELLCAST_EMPOWER_START" then
				empoweredCastActive[unit] = true
				local textFill = isTextFillMode(unit)
				if not textFill then
					-- Default mode: swap BG and apply Scoot textures to tiers
					hideScootBGForEmpowered(unit)
					applyScootTextureToTiers(unit)
				end
				-- Text-fill mode: applyTextFillMode handles everything via the next apply cycle.
				-- Trigger a refresh so the empowered flag is picked up immediately.
				-- Must set castVisualOnly so the combat guard allows immediate execution
				-- (same pattern as SetStatusBarTexture/SetStatusBarColor hooks).
				if textFill then
					local titleUnit = tokenToUnit[unit]
					if titleUnit and addon.ApplyUnitFrameCastBarFor then
						local f = resolveCastBarFrame(titleUnit)
						if f then
							setProp(f, "castVisualOnly", true)
							addon.ApplyUnitFrameCastBarFor(titleUnit)
							setProp(f, "castVisualOnly", nil)
						end
					end
					-- Start the stage updater (deferred: AddStages + text-fill setup must complete)
					C_Timer.After(0, function()
						if not empoweredCastActive[unit] then return end
						local f = titleUnit and resolveCastBarFrame(titleUnit)
						if not f then return end
						-- Reuse existing updater or create via ensureEmpoweredStageUpdater.
						-- OnUpdate already handles both text-fill and default mode paths.
						ensureEmpoweredStageUpdater()
						empoweredStageUpdater._castFrame = f
						empoweredStageUpdater._lastStage = nil
						empoweredStageUpdater:Show()
					end)
				end
			elseif event == "UNIT_SPELLCAST_EMPOWER_STOP" then
				empoweredCastActive[unit] = nil
				local textFill = isTextFillMode(unit)
				if not textFill then
					cleanupTierOverlays(unit)
					restoreScootBGAfterEmpowered(unit)
				else
					-- Text-fill empowered cleanup: stop stage updater + deactivate tier segments
					if empoweredStageUpdater then empoweredStageUpdater:Hide() end
					local titleUnit = tokenToUnit[unit]
					if titleUnit then
						local f = resolveCastBarFrame(titleUnit)
						if f then
							local els = getProp(f, "textFillElements")
							if els then
								CB._deactivateEmpoweredTextFill(f, els)
							end
						end
					end
				end
			else
				-- Clear on any other cast event (failed, interrupted, new channel, etc.)
				if empoweredCastActive[unit] then
					empoweredCastActive[unit] = nil
					local textFill = isTextFillMode(unit)
					if not textFill then
						cleanupTierOverlays(unit)
						restoreScootBGAfterEmpowered(unit)
					else
						if empoweredStageUpdater then empoweredStageUpdater:Hide() end
						local titleUnit = tokenToUnit[unit]
						if titleUnit then
							local f = resolveCastBarFrame(titleUnit)
							if f then
								local els = getProp(f, "textFillElements")
								if els then
									CB._deactivateEmpoweredTextFill(f, els)
								end
							end
						end
					end
				end
			end
		end)
	end

	-- Zero‑Touch hook installation: install cast bar persistence hooks ONLY when the profile
	-- has explicit cast bar config. This is used to ensure hooks exist even if ApplyStyles()
	-- is deferred due to combat at login/reload.
	local function hasCastBarConfig(unit)
		local profile = addon and addon.db and addon.db.profile
		if not profile then return false end
		local unitFrames = rawget(profile, "unitFrames")
		local unitCfg = unitFrames and rawget(unitFrames, unit)
		return unitCfg and rawget(unitCfg, "castBar") ~= nil
	end

	local function ensureHooksForUnit(unit)
		if unit ~= "Player" and unit ~= "Target" and unit ~= "Focus" then return end
		if not hasCastBarConfig(unit) then return end
		local frame = resolveCastBarFrame(unit)
		if not frame then return end

		-- Reuse the same hook installation block used by applyCastBarForUnit().
		-- It is guarded by frame castHooksInstalled state so it is safe to call repeatedly.
		if not getProp(frame, "castHooksInstalled") and _G.hooksecurefunc then
			setProp(frame, "castHooksInstalled", true)
			local hookUnit = unit
			_G.hooksecurefunc(frame, "SetStatusBarTexture", function(self, texArg, ...)
				-- Ignore Scoot's own internal texture writes
				if getProp(self, "ufInternalTextureWrite") then return end
				-- Track interruptibility from Blizzard's atlas change
				if type(texArg) == "string" and not issecretvalue(texArg) then
					setProp(self, "castNotInterruptible", texArg == "ui-castingbar-uninterruptable")
				end
				-- Don't re-apply foreground during empowered casts (tiers provide visuals)
				local token = (hookUnit == "Player" and "player") or (hookUnit == "Target" and "target") or (hookUnit == "Focus" and "focus")
				if token and empoweredCastActive[token] then return end
				if addon and addon.ApplyUnitFrameCastBarFor then
					setProp(self, "castVisualOnly", true)
					addon.ApplyUnitFrameCastBarFor(hookUnit)
					setProp(self, "castVisualOnly", nil)
				end
			end)
			_G.hooksecurefunc(frame, "SetStatusBarColor", function(self, ...)
				-- Don't re-apply color during empowered casts (stage tiers provide visuals)
				local token = (hookUnit == "Player" and "player") or (hookUnit == "Target" and "target") or (hookUnit == "Focus" and "focus")
				if token and empoweredCastActive[token] then return end
				if addon and addon.ApplyUnitFrameCastBarFor then
					setProp(self, "castVisualOnly", true)
					addon.ApplyUnitFrameCastBarFor(hookUnit)
					setProp(self, "castVisualOnly", nil)
				end
			end)
			_G.hooksecurefunc(frame, "SetPoint", function(self, ...)
				if getProp(self, "ignoreSetPoint") then return end
				local mode = activeAnchorModes[hookUnit]
				if mode and mode ~= "default" then
					if InCombatLockdown and InCombatLockdown() then
						reanchorCastBar(self, hookUnit)
					else
						if not pendingReapply[hookUnit] then
							pendingReapply[hookUnit] = true
							C_Timer.After(0, function()
								pendingReapply[hookUnit] = nil
								if addon and addon.ApplyUnitFrameCastBarFor then
									addon.ApplyUnitFrameCastBarFor(hookUnit)
								end
							end)
						end
					end
				end
			end)
			if (hookUnit == "Target" or hookUnit == "Focus") and frame.AdjustPosition then
				_G.hooksecurefunc(frame, "AdjustPosition", function(self)
					local mode = activeAnchorModes[hookUnit]
					if mode and mode ~= "default" then
						if InCombatLockdown and InCombatLockdown() then
							reanchorCastBar(self, hookUnit)
						else
							if addon and addon.ApplyUnitFrameCastBarFor then
								addon.ApplyUnitFrameCastBarFor(hookUnit)
							end
						end
					end
				end)
			end
		end
	end

	function addon.EnsureAllUnitFrameCastBarHooks()
		ensureHooksForUnit("Player")
		ensureHooksForUnit("Target")
		ensureHooksForUnit("Focus")
	end
end
