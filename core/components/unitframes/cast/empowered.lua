--------------------------------------------------------------------------------
-- cast/empowered.lua
-- Empowered cast handling for the unit frame cast bars: per-stage tier
-- overlays, the stage-progress OnUpdate driver, the Scoot background swap,
-- and the UNIT_SPELLCAST_* event wiring. Shares the per-token active-cast
-- table with cast/styling.lua through CB._empoweredCastActive.
--------------------------------------------------------------------------------

local addonName, addon = ...
local CB = addon.CastBars
local getProp = CB._getProp
local setProp = CB._setProp
local resolveCastBarFrame = addon.Frames.resolveCastBarFrame
local empoweredCastActive = CB._empoweredCastActive

-- Empowered cast event tracking + stage tier texture replacement
do
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

	local function onCastEvent(event, unit)
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
	end
	addon.Events.On("UnitFrames:CastStyling", "UNIT_SPELLCAST_EMPOWER_START", onCastEvent)
	addon.Events.On("UnitFrames:CastStyling", "UNIT_SPELLCAST_EMPOWER_STOP", onCastEvent)
	addon.Events.On("UnitFrames:CastStyling", "UNIT_SPELLCAST_STOP", onCastEvent)
	addon.Events.On("UnitFrames:CastStyling", "UNIT_SPELLCAST_FAILED", onCastEvent)
	addon.Events.On("UnitFrames:CastStyling", "UNIT_SPELLCAST_INTERRUPTED", onCastEvent)
	addon.Events.On("UnitFrames:CastStyling", "UNIT_SPELLCAST_CHANNEL_START", onCastEvent)
end
