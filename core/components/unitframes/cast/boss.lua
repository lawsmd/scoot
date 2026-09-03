--------------------------------------------------------------------------------
-- cast/boss.lua
-- Boss cast bar styling: texture overrides, icon border management, text-fill
-- gradient application, and combat-safe hooks.
--------------------------------------------------------------------------------

local addonName, addon = ...
local CB = addon.CastBars
local getProp = CB._getProp
local setProp = CB._setProp
local getState = CB._getState
local getIconBorderContainer = CB._getIconBorderContainer
local installGradientHook = CB._installGradientHook
local applySpellNameColor = CB._applySpellNameColor

--------------------------------------------------------------------------------
-- Boss Cast Bars (Boss1TargetFrameSpellBar through Boss5TargetFrameSpellBar)
-- All 5 Boss frames share a single config table: db.unitFrames.Boss.castBar
--------------------------------------------------------------------------------
do
	-- Resolve Boss cast bar frame by index (1-5)
	local function resolveBossCastBarFrame(index)
		return _G["Boss" .. index .. "TargetFrameSpellBar"]
	end

	-- Store original widths/icon data per Boss frame for percent scaling
	local bossOriginalWidths = {}
	local bossOriginalIconAnchors = {}
	local bossOriginalIconSizes = {}
	local bossOriginalSparkVertexColor = {}
	local bossOriginalSparkAlpha = {}

	-- Store original cast bar anchors for custom anchor mode positioning
	local bossOriginalCastBarAnchors = {}

	-- Track active anchor modes for SetPoint hook re-application
	local bossActiveAnchorModes = {}
	local bossPendingReapply = {}

	-- CastBarOnSide is pushed to Edit Mode only when the user changes the anchor mode
	-- through the Scoot UI (consume-once marker, set by the Boss renderer). A passive
	-- value comparison at styling time cannot tell a user change from a stale local
	-- profile copy at a cross-machine login, and Edit Mode owns the layout, so styling
	-- passes never write on their own.
	local bossCastOnSideDirty = false
	function addon.MarkBossCastBarOnSideDirty()
		bossCastOnSideDirty = true
	end

	-- Track Boss indices that were reanchored during combat and need a full re-apply after combat ends
	local pendingBossPostCombatRefresh = {}

	-- Lightweight reanchor: only corrects position (ClearAllPoints + SetPoint) without
	-- going through the full apply pipeline or its combat guard.  Boss cast bars are visual
	-- StatusBars — repositioning them is safe during combat (no taint).
	local function reanchorBossCastBar(frame, index)
		local db = addon and addon.db and addon.db.profile
		if not db then return end
		local cfg = db.unitFrames and db.unitFrames.Boss and db.unitFrames.Boss.castBar
		if not cfg then return end

		local anchorMode = cfg.anchorMode or "default"
		if anchorMode == "default" or anchorMode == "leftOfFrame" then return end

		local offsetX = tonumber(cfg.offsetX) or 0
		local offsetY = tonumber(cfg.offsetY) or 0

		if anchorMode == "centeredUnderPower" then
			local bossFrame = addon.GetBossFrame(index)
			local manaBar
			if addon.BarsResolvers and addon.BarsResolvers.resolveBossManaBar then
				manaBar = addon.BarsResolvers.resolveBossManaBar(bossFrame)
			end

			if manaBar then
				setProp(frame, "ignoreSetPoint", true)
				frame:ClearAllPoints()
				frame:SetPoint("TOP", manaBar, "BOTTOM", offsetX, -2 + offsetY)
				setProp(frame, "ignoreSetPoint", nil)
			end
		elseif anchorMode == "underBossName" then
			local bossFrame = addon.GetBossFrame(index)
			local nameFS
			if addon.ResolveBossNameFS then
				nameFS = addon.ResolveBossNameFS(bossFrame)
			end

			if nameFS then
				setProp(frame, "ignoreSetPoint", true)
				frame:ClearAllPoints()
				frame:SetPoint("TOPLEFT", nameFS, "BOTTOMLEFT", 27 + offsetX, -13 + offsetY)
				setProp(frame, "ignoreSetPoint", nil)
			end
		end

		-- Mark for full re-apply when combat ends
		pendingBossPostCombatRefresh[index] = true
	end

	-- Flush deferred full re-applies after combat ends
	function addon.FlushPendingBossCastBarRefresh()
		local any = false
		for _ in pairs(pendingBossPostCombatRefresh) do
			any = true
			break
		end
		if any then
			pendingBossPostCombatRefresh = {}
			if addon.ApplyBossCastBarFor then
				addon.ApplyBossCastBarFor()
			end
		end
	end

	-- Baseline anchors for Boss Spell Name text
	addon._ufBossCastSpellNameBaselines = addon._ufBossCastSpellNameBaselines or {}

	-- Apply styling to a single Boss cast bar frame
	local function applyBossCastBarToFrame(frame, index, cfg)
		if not frame then return end

		-- Install lightweight hooks once to keep cast bar styling persistent
		if not getProp(frame, "bossCastHooksInstalled") and _G.hooksecurefunc then
			setProp(frame, "bossCastHooksInstalled", true)
			local hookIndex = index
			_G.hooksecurefunc(frame, "SetStatusBarTexture", function(self, texArg, ...)
				if getProp(self, "ufInternalTextureWrite") then return end
				-- Track interruptibility from Blizzard's atlas change
				if type(texArg) == "string" and not issecretvalue(texArg) then
					setProp(self, "castNotInterruptible", texArg == "ui-castingbar-uninterruptable")
				end
				if addon and addon.ApplyBossCastBarFor then
					setProp(self, "castVisualOnly", true)
					addon.ApplyBossCastBarFor()
					setProp(self, "castVisualOnly", nil)
				end
			end)
			_G.hooksecurefunc(frame, "SetStatusBarColor", function(self, ...)
				if addon and addon.ApplyBossCastBarFor then
					setProp(self, "castVisualOnly", true)
					addon.ApplyBossCastBarFor()
					setProp(self, "castVisualOnly", nil)
				end
			end)
			-- Hook SetPoint to re-apply custom anchoring when Blizzard overrides it
			_G.hooksecurefunc(frame, "SetPoint", function(self, ...)
				-- Ignore Scoot's SetPoint calls (flagged to prevent infinite loops)
				if getProp(self, "ignoreSetPoint") then return end
				-- Only re-apply if a custom anchor mode is active for this Boss cast bar
				local mode = bossActiveAnchorModes[hookIndex]
				if mode and mode ~= "default" and mode ~= "leftOfFrame" then
					if InCombatLockdown and InCombatLockdown() then
						-- Lightweight reanchor during combat (position only)
						reanchorBossCastBar(self, hookIndex)
					else
						if not bossPendingReapply[hookIndex] then
							bossPendingReapply[hookIndex] = true
							C_Timer.After(0, function()
								bossPendingReapply[hookIndex] = nil
								if addon and addon.ApplyBossCastBarFor then
									addon.ApplyBossCastBarFor()
								end
							end)
						end
					end
				end
			end)
			-- Hook AdjustPosition to catch Blizzard layout resets (aura updates, powerBarAlt, OnShow)
			if frame.AdjustPosition then
				_G.hooksecurefunc(frame, "AdjustPosition", function(self)
					local mode = bossActiveAnchorModes[hookIndex]
					if mode and mode ~= "default" and mode ~= "leftOfFrame" then
						if InCombatLockdown and InCombatLockdown() then
							reanchorBossCastBar(self, hookIndex)
						else
							if addon and addon.ApplyBossCastBarFor then
								addon.ApplyBossCastBarFor()
							end
						end
					end
				end)
			end
		end

		-- Capture original width once
		if not bossOriginalWidths[frame] and frame.GetWidth then
			local ok, w = pcall(frame.GetWidth, frame)
			if ok and w then
				bossOriginalWidths[frame] = w
			end
		end

		local origWidth = bossOriginalWidths[frame]

		-- Capture original icon anchor/size once
		local iconFrame = frame.Icon
		if iconFrame then
			if not bossOriginalIconAnchors[iconFrame] and iconFrame.GetPoint then
				local p, relTo, rp, x, y = iconFrame:GetPoint(1)
				if p then
					bossOriginalIconAnchors[iconFrame] = {
						point = p,
						relativeTo = relTo,
						relativePoint = rp,
						xOfs = x or 0,
						yOfs = y or 0,
					}
				end
			end
			if not bossOriginalIconSizes[iconFrame] and iconFrame.GetWidth and iconFrame.GetHeight then
				local okW, w = pcall(iconFrame.GetWidth, iconFrame)
				local okH, h = pcall(iconFrame.GetHeight, iconFrame)
				if okW and okH and w and h then
					bossOriginalIconSizes[iconFrame] = { width = w, height = h }
				end
			end
		end

		-- Capture original cast bar anchor once (for default positioning restoration)
		if not bossOriginalCastBarAnchors[frame] and frame.GetPoint then
			local p, relTo, rp, x, y = frame:GetPoint(1)
			if p then
				bossOriginalCastBarAnchors[frame] = {
					point = p,
					relativeTo = relTo,
					relativePoint = rp,
					xOfs = x or 0,
					yOfs = y or 0,
				}
			end
		end

		-- Read anchor mode from config
		local anchorMode = cfg.anchorMode or "default"

		-- Programmatically sync Edit Mode "CastBarOnSide" setting to match anchor mode
		do
			local desiredOnSide = (anchorMode == "leftOfFrame") and 1 or 0
			local settingId = _G.Enum and _G.Enum.EditModeUnitFrameSetting and _G.Enum.EditModeUnitFrameSetting.CastBarOnSide
			if settingId then
				local bossSystemFrame = addon.GetEditModeUnitFrame("Boss")
				if bossSystemFrame and addon.EditMode then
					local currentVal = 0
					if addon.EditMode.GetSetting then
						local ok, v = pcall(addon.EditMode.GetSetting, bossSystemFrame, settingId)
						if ok and v then currentVal = v end
					end
					if bossCastOnSideDirty then
						bossCastOnSideDirty = false
						if currentVal ~= desiredOnSide and addon.EditMode.WriteSetting then
							addon.EditMode.WriteSetting(bossSystemFrame, settingId, desiredOnSide)
						end
					end
				end
			end
		end

		-- Read settings from config
		local castBarScale = tonumber(cfg.castBarScale) or 100
		if castBarScale < 50 then castBarScale = 50 elseif castBarScale > 150 then castBarScale = 150 end

		local iconWidth = tonumber(cfg.iconWidth)
		local iconHeight = tonumber(cfg.iconHeight)
		local iconBarPadding = tonumber(cfg.iconBarPadding) or 0
		local iconDisabled = cfg.iconDisabled == true

		local function apply()
			local inCombat = InCombatLockdown and InCombatLockdown()
			local visualOnly = inCombat and getProp(frame, "castVisualOnly")

			-- Layout (size/scale/icon) is skipped for in-combat visual-only refreshes
			if not visualOnly then
				-- Apply cast bar scale
				if frame.SetScale then
					local scale = castBarScale / 100.0
					pcall(frame.SetScale, frame, scale)
				end

				-- Apply custom anchor positioning (only when anchorMode is not "default")
				-- Track the active anchor mode so the SetPoint hook knows when to re-apply
				bossActiveAnchorModes[index] = anchorMode

				if anchorMode ~= "default" and anchorMode ~= "leftOfFrame" then
					local anchorApplied = false
					local offsetX = tonumber(cfg.offsetX) or 0
					local offsetY = tonumber(cfg.offsetY) or 0

					if anchorMode == "centeredUnderPower" then
						local bossFrame = addon.GetBossFrame(index)
						local manaBar
						if addon.BarsResolvers and addon.BarsResolvers.resolveBossManaBar then
							manaBar = addon.BarsResolvers.resolveBossManaBar(bossFrame)
						end

						if manaBar then
							setProp(frame, "ignoreSetPoint", true)
							frame:ClearAllPoints()
							frame:SetPoint("TOP", manaBar, "BOTTOM", offsetX, -2 + offsetY)
							setProp(frame, "ignoreSetPoint", nil)
							anchorApplied = true
						end
					elseif anchorMode == "underBossName" then
						local bossFrame = addon.GetBossFrame(index)
						local nameFS
						if addon.ResolveBossNameFS then
							nameFS = addon.ResolveBossNameFS(bossFrame)
						end

						if nameFS then
							setProp(frame, "ignoreSetPoint", true)
							frame:ClearAllPoints()
							frame:SetPoint("TOPLEFT", nameFS, "BOTTOMLEFT", 27 + offsetX, -13 + offsetY)
							setProp(frame, "ignoreSetPoint", nil)
							anchorApplied = true
						end
					end

					-- If custom anchor failed, fall back to default positioning
					if not anchorApplied then
						local orig = bossOriginalCastBarAnchors[frame]
						if orig then
							setProp(frame, "ignoreSetPoint", true)
							frame:ClearAllPoints()
							frame:SetPoint(
								orig.point,
								orig.relativeTo,
								orig.relativePoint,
								orig.xOfs or 0,
								orig.yOfs or 0
							)
							setProp(frame, "ignoreSetPoint", nil)
						end
					end
				else
					-- Restore default positioning (original anchor)
					-- Only restore if it previously had a custom anchor mode active
					-- Prevents fighting with Blizzard's layout when user has "default" selected
					if getProp(frame, "hadCustomAnchor") then
						local orig = bossOriginalCastBarAnchors[frame]
						if orig then
							setProp(frame, "ignoreSetPoint", true)
							frame:ClearAllPoints()
							frame:SetPoint(
								orig.point,
								orig.relativeTo,
								orig.relativePoint,
								orig.xOfs or 0,
								orig.yOfs or 0
							)
							setProp(frame, "ignoreSetPoint", nil)
						end
						setProp(frame, "hadCustomAnchor", nil)
					end
				end

				-- Track that a custom anchor has been applied (for restoration when switching back to default)
				if anchorMode ~= "default" and anchorMode ~= "leftOfFrame" then
					setProp(frame, "hadCustomAnchor", true)
				end

				-- Apply icon visibility, size, and padding
				local icon = frame.Icon
				if icon then
					if iconDisabled then
						if icon.SetAlpha then pcall(icon.SetAlpha, icon, 0) end
						local container = getIconBorderContainer(icon)
						if container and addon.Borders and addon.Borders.HideAll then
							addon.Borders.HideAll(container)
						end
					else
						if icon.SetAlpha then pcall(icon.SetAlpha, icon, 1) end

						local baseSize = bossOriginalIconSizes[icon]
						if iconWidth or iconHeight then
							local w = tonumber(iconWidth) or (baseSize and baseSize.width) or (icon.GetWidth and icon:GetWidth()) or 16
							local h = tonumber(iconHeight) or (baseSize and baseSize.height) or (icon.GetHeight and icon:GetHeight()) or 16
							w = math.max(8, math.min(64, w))
							h = math.max(8, math.min(64, h))
							pcall(icon.SetSize, icon, w, h)
							if icon.Icon and icon.Icon.SetAllPoints then
								icon.Icon:SetAllPoints(icon)
							end
							if icon.IconMask and icon.IconMask.SetAllPoints then
								icon.IconMask:SetAllPoints(icon)
							end
						end

						-- Icon/Bar padding
						local baseAnchor = bossOriginalIconAnchors[icon]
						if baseAnchor and icon.ClearAllPoints and icon.SetPoint then
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
			end

			-- Text-Fill Cast Bar mode (Boss)
			local castBarMode = cfg.castBarMode or "default"

			if castBarMode == "textFill" then
				local ok, err = pcall(CB._applyTextFillMode, frame, cfg, "Boss")
			else
				CB._hideTextFillElements(frame)
			end

			-- Apply foreground and background styling
			if castBarMode ~= "textFill" and (not inCombat or visualOnly) and (addon._ApplyToStatusBar or addon._ApplyBackgroundToStatusBar) then
				-- Foreground: texture + color
				if addon._ApplyToStatusBar and frame.GetStatusBarTexture then
					local texKey = cfg.castBarTexture or "default"
					local colorMode = cfg.castBarColorMode or "default"
					local tint = cfg.castBarTint
					-- For Boss cast bars, use the boss unit for class color
					local unitId = "boss" .. index
					addon._ApplyToStatusBar(frame, texKey, colorMode, tint, "player", "cast", unitId, visualOnly)
				end

				-- Background: texture + color + opacity
				if addon._ApplyBackgroundToStatusBar then
					local bgTexKey = cfg.castBarBackgroundTexture or "default"
					local bgColorMode = cfg.castBarBackgroundColorMode or "default"
					local bgOpacity = cfg.castBarBackgroundOpacity or 50
					addon._ApplyBackgroundToStatusBar(frame, bgTexKey, bgColorMode, cfg.castBarBackgroundTint, bgOpacity, "Boss", "cast")
				end
			end

			-- Spark visibility and color
			do
				local spark = frame.Spark
				if spark then
					if not bossOriginalSparkVertexColor[spark] and spark.GetVertexColor then
						local ok, r, g, b, a = pcall(spark.GetVertexColor, spark)
						if not ok or not r or not g or not b then
							r, g, b, a = 1, 1, 1, 1
						end
						bossOriginalSparkVertexColor[spark] = { r or 1, g or 1, b or 1, a or 1 }
					end
					if not bossOriginalSparkAlpha[spark] and spark.GetAlpha then
						local ok, alpha = pcall(spark.GetAlpha, spark)
						bossOriginalSparkAlpha[spark] = (ok and alpha) or 1
					end

					local sparkHidden = cfg.castBarSparkHidden == true
					local colorMode = cfg.castBarSparkColorMode or "default"
					local tintTbl = type(cfg.castBarSparkTint) == "table" and cfg.castBarSparkTint or {1,1,1,1}

					local base = bossOriginalSparkVertexColor[spark] or {1,1,1,1}
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

					if sparkHidden then
						if spark.SetAlpha then
							pcall(spark.SetAlpha, spark, 0)
						end
					else
						if spark.SetAlpha then
							local baseAlpha = bossOriginalSparkAlpha[spark] or a or 1
							pcall(spark.SetAlpha, spark, baseAlpha)
						end
					end
				end
			end

			-- Custom Cast Bar border
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

				local userInsetH = tonumber(cfg.castBarBorderInsetH) or tonumber(cfg.castBarBorderInset) or 0
				local userInsetV = tonumber(cfg.castBarBorderInsetV) or tonumber(cfg.castBarBorderInset) or 0
				if userInsetH < -4 then userInsetH = -4 elseif userInsetH > 4 then userInsetH = 4 end
				if userInsetV < -4 then userInsetV = -4 elseif userInsetV > 4 then userInsetV = 4 end
				local derivedInset = math.floor((thickness - 1) * 0.5)
				local baseInset = (styleKey == "square") and -2 or 0
				local combinedInsetH = baseInset + userInsetH + derivedInset
				local combinedInsetV = baseInset + userInsetV + derivedInset

				if not enabled or styleKey == "none" then
					if addon.BarBorders and addon.BarBorders.ClearBarFrame then addon.BarBorders.ClearBarFrame(frame) end
					if addon.Borders and addon.Borders.HideAll then addon.Borders.HideAll(frame) end
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
					if addon.BarBorders.ClearBarFrame then addon.BarBorders.ClearBarFrame(frame) end
					setProp(frame, "borderContainerParentRef", nil)

				-- Unit-specific per-side pad adjustments for Cast Bar:
				-- Boss: Similar to Target - StatusBar bounds extend beyond visible bar texture.
				-- Apply padding adjustments to pull border edges in to match the visible bar.
				if enabled then
					setProp(frame, "borderPadAdjust", {
						left = -2,
						right = -2,
						top = -1,
						bottom = -1,
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
					if addon.BarBorders and addon.BarBorders.ClearBarFrame then addon.BarBorders.ClearBarFrame(frame) end
					if addon.Borders and addon.Borders.ApplySquare then
						local sqColor = tintEnabled and tintColor or {0, 0, 0, 1}
						local baseY = (thickness <= 1) and 0 or 1
						local baseX = 1
						local expandY = baseY - combinedInsetV
						local expandX = baseX - combinedInsetH
						if expandX < -6 then expandX = -6 elseif expandX > 6 then expandX = 6 end
						if expandY < -6 then expandY = -6 elseif expandY > 6 then expandY = 6 end

					-- Per-unit fine-tuning for Boss cast bar pixel fallback:
					-- Boss: Similar to Target - StatusBar bounds extend beyond visible bar texture.
					-- Pull edges in to match the visible bar.
					local exLeft, exRight, exTop, exBottom = expandX, expandX, expandY, expandY
					local name = frame.GetName and frame:GetName()
					if name and name:match("^Boss%d+TargetFrameSpellBar$") then
						exLeft   = math.max(0, exLeft - 2)
						exRight  = math.max(0, exRight - 2)
						exTop    = math.max(0, exTop - 1)
						exBottom = math.max(0, exBottom - 1)
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

				-- Hide Blizzard's stock border when custom borders are enabled
				local border = frame.Border
				if border then
					if border.SetShown then
						pcall(border.SetShown, border, not enabled)
					elseif border.SetAlpha then
						pcall(border.SetAlpha, border, enabled and 0 or 1)
					end
				end
			end
			end -- castBarMode ~= "textFill" (Boss)

			-- Cast Bar Icon border
			do
				local icon = frame.Icon
				if icon then
					local iconBorderEnabled = not not cfg.iconBorderEnable
					local iconStyle = cfg.iconBorderStyle or "square"
					if iconStyle == "none" then
						iconStyle = "square"
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

					if iconBorderEnabled and not iconDisabled then
						if ((addon.Borders.GetAtlasBorder and addon.Borders.GetAtlasBorder(icon)) or (addon.Borders.GetTextureBorder and addon.Borders.GetTextureBorder(icon)) or (addon.Borders.GetSquareContainer and addon.Borders.GetSquareContainer(icon)) or (addon.Borders.GetSquareEdges and addon.Borders.GetSquareEdges(icon)))
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
					local container = getIconBorderContainer(icon)
					if container and addon.Borders and addon.Borders.HideAll then
						addon.Borders.HideAll(container)
					elseif addon.Borders and addon.Borders.HideAll then
							addon.Borders.HideAll(icon)
						end
					end
				end
			end

			-- Ensure boss cast bar text renders above custom borders.
			-- Same pattern as Player/Target/Focus (see above).
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
					local barLevel = (frame.GetFrameLevel and frame:GetFrameLevel()) or 0
					overlay:SetFrameLevel(barLevel + 3)
					overlay:Show()

					if frame.Text and frame.Text.SetParent then
						pcall(frame.Text.SetParent, frame.Text, overlay)
					end
				else
					local overlay = getProp(frame, "ScootCastTextOverlay")
					if overlay then
						if frame.Text and frame.Text.SetParent then
							pcall(frame.Text.SetParent, frame.Text, frame)
						end
						overlay:Hide()
					end
				end
			end

			-- Spell Name Text styling
			do
				local spellFS = frame.Text
				if spellFS then
					local function ensureSpellBaseline(fs, key)
						addon._ufBossCastSpellNameBaselines[key] = addon._ufBossCastSpellNameBaselines[key] or {}
						local b = addon._ufBossCastSpellNameBaselines[key]
						if b.point == nil then
							local parent = (fs and fs.GetParent and fs:GetParent()) or frame
							b.point, b.relTo, b.relPoint, b.x, b.y = "CENTER", parent, "CENTER", 0, 0
						end
						return b
					end

					-- Hide spell name border if configured
					local hideBorder = not not cfg.hideSpellNameBorder
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

					local styleCfg = cfg.spellNameText or {}
					-- Font / size / outline
					local face = addon.ResolveFontFace(styleCfg.fontFace)
					local size = tonumber(styleCfg.size) or 10
					local outline = tostring(styleCfg.style or "OUTLINE")
					if addon.ApplyFontStyle then
						addon.ApplyFontStyle(spellFS, face, size, outline)
					elseif spellFS.SetFont then
						pcall(spellFS.SetFont, spellFS, face, size, outline)
					end

					-- Install gradient SetText hook (once per FontString)
					installGradientHook(spellFS, function()
						local d = addon and addon.db and addon.db.profile
						if not d then return nil end
						local uf = d.unitFrames and d.unitFrames.Boss
						local cb = uf and uf.castBar
						return cb and cb.spellNameText
					end, frame)

					-- Color (mode-aware: default/class/custom/classGradient/customGradient)
					applySpellNameColor(spellFS, styleCfg, frame)

					-- Offsets relative to baseline
					local ox = (styleCfg.offset and tonumber(styleCfg.offset.x)) or 0
					local oy = (styleCfg.offset and tonumber(styleCfg.offset.y)) or 0
					if spellFS.ClearAllPoints and spellFS.SetPoint then
						local b = ensureSpellBaseline(spellFS, "Boss" .. index .. ":spellName")
						spellFS:ClearAllPoints()
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

			-- Sync filled text in textFill mode (after Boss spell name styling)
			if castBarMode == "textFill" then
				pcall(CB._syncTextFillText, frame, cfg)
			end

			-- BorderShield visibility (Boss cast bars)
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
		end

		local inCombat = InCombatLockdown and InCombatLockdown()
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

	-- Apply styling to all Boss cast bars (Boss1-5)
	local function applyAllBossCastBars()
		if not addon:IsModuleEnabled("unitFrames", "Boss") then return end
		if not addon:IsCastBarXEnabled() then return end
		local db = addon and addon.db and addon.db.profile
		if not db then return end

		-- Boss cast bars share config under db.unitFrames.Boss.castBar
		local unitFrames = rawget(db, "unitFrames")
		local bossCfg = unitFrames and rawget(unitFrames, "Boss") or nil
		if not bossCfg then return end
		local cfg = rawget(bossCfg, "castBar")
		if not cfg then return end

		-- Check if there's any cast bar config; if not, skip (Zero-Touch policy)
		local hasConfig = false
		for k, v in pairs(cfg) do
			if v ~= nil then
				hasConfig = true
				break
			end
		end
		if not hasConfig then return end

		-- Apply to all 5 Boss cast bar frames
		for i = 1, addon.NUM_BOSS_FRAMES do
			local frame = resolveBossCastBarFrame(i)
			if frame then
				applyBossCastBarToFrame(frame, i, cfg)
			end
		end
	end

	function addon.ApplyBossCastBarFor()
		applyAllBossCastBars()
	end

	-- Update ApplyAllUnitFrameCastBars to include Boss
	local originalApplyAll = addon.ApplyAllUnitFrameCastBars
	function addon.ApplyAllUnitFrameCastBars()
		if originalApplyAll then
			originalApplyAll()
		end
		applyAllBossCastBars()
	end
end
