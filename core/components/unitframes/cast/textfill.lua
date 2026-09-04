--------------------------------------------------------------------------------
-- cast/textfill.lua
-- Text-fill cast bar effect: character-level gradient fill that tracks cast
-- progress, with spark overlay and Blizzard animation interception.
--------------------------------------------------------------------------------

local addonName, addon = ...
local CB = addon.CastBars
local getProp = CB._getProp
local setProp = CB._setProp
local getState = CB._getState

-- Show() guards (core/enforce.lua): while text-fill is active on a bar, a
-- decorative texture Blizzard re-shows is hidden again at once. One option
-- table per bar, since the key reads that bar's state.
local Enforce = addon.Enforce
local function hideTexture(tex)
	local hide = tex.HideBase or tex.Hide
	if hide then hide(tex) end
end
local guardOptsByFrame = setmetatable({}, { __mode = "k" })
local function textFillGuardOpts(frame)
	local opts = guardOptsByFrame[frame]
	if not opts then
		opts = {
			methods = { "Show" },
			apply = hideTexture,
			when = function() return getProp(frame, "textFillActive") and true or false end,
		}
		guardOptsByFrame[frame] = opts
	end
	return opts
end

-- =========================================================================
-- Text-Fill Cast Bar mode helpers
-- =========================================================================

-- Empowered cast tier colors (shared with styling.lua via CB namespace).
-- Brightened to compensate for vertex color multiplication on custom textures.
CB._TIER_COLORS_NORMAL = {
	{ 0.45, 0.95, 0.55 },  -- Tier 1: bright green
	{ 1.00, 0.90, 0.30 },  -- Tier 2: bright yellow
	{ 1.00, 0.55, 0.25 },  -- Tier 3: bright orange
	{ 1.00, 0.30, 0.20 },  -- Tier 4: bright red
}
CB._TIER_COLORS_DISABLED = {
	{ 0.18, 0.40, 0.22 },  -- ~40% of normal
	{ 0.40, 0.36, 0.12 },
	{ 0.40, 0.22, 0.10 },
	{ 0.40, 0.12, 0.08 },
}
local TIER_COLORS_NORMAL = CB._TIER_COLORS_NORMAL
local TIER_COLORS_DISABLED = CB._TIER_COLORS_DISABLED
local MAX_EMPOWERED_TIERS = 5

-- Shrink-to-fit tuning (core/fonts.lua loads before this file in the TOC, safe to cache)
local measureTextWidth = addon.MeasureTextWidth
local FIT_MIN_POINT_SIZE = 7     -- never render the spell name smaller than this
local FIT_MIN_SCALE = 0.55       -- absolute floor regardless of configured size
local FIT_H_OVERFLOW = 200       -- clipFrame left-edge overflow, px
local FILLED_TRACK_KEYS = { "filledLine", "filledLeftCap", "filledRightCap" }

-- Stock template widths, used only when frame:GetWidth() is unreadable (secret on
-- tainted target/boss cast bars — see pitfall #13).
--   Player 208 : PlayerCastingBarFrame,   CastingBarFrame.xml
--   Target 150 : TargetSpellBarTemplate,  TargetFrame.xml
--   Focus  150 : same template
--   Boss   120 : BossSpellBarTemplate,    TargetFrame.xml
-- Target/Focus/Boss stay correct because Scoot scales them with frame:SetScale
-- (castBarScale), which GetWidth is independent of. Player is the exception: its
-- width is a real SetWidth of origWidth * widthPct/100 (styling.lua), so the
-- constant is scaled to match.
local FIT_BAR_WIDTH_BY_UNIT = { Player = 208, Target = 150, Focus = 150, Boss = 120 }

-- Resolve the fill color from cast bar color settings (mirrors bars/textures.lua logic)
-- frame: the cast bar frame (used to read interruptibility state for default color mode)
local function resolveBarFillColor(cfg, unit, frame)
	local colorMode = cfg.castBarColorMode or "default"
	local tint = cfg.castBarTint
	if (colorMode == "custom" and type(tint) == "table") or colorMode == "class" then
		local r, g, b, a = addon.ResolveColorRGBA(colorMode, tint)
		return r, g, b, a
	end
	-- "default": white for non-kickable casts, yellow/gold for kickable
	-- (castNotInterruptible is set by the SetStatusBarTexture hook when Blizzard
	-- switches to the "ui-castingbar-uninterruptable" atlas)
	if frame and getProp(frame, "castNotInterruptible") then
		return 1, 1, 1, 1
	end
	local r, g, b = addon.GetCastDefaultColorRGB()
	return r, g, b, 1
end

-- Resolve the cast bar's width in pixels.
-- Ladder: live GetWidth cached at apply time -> stock template constant -> nil.
-- Returns nil when the width is unknowable, in which case callers must not shrink.
local function resolveBarWidth(frame)
	local bw = getProp(frame, "textFillBarWidth")
	if bw and bw > 0 then return bw end

	local unit = getProp(frame, "textFillUnit")
	bw = unit and FIT_BAR_WIDTH_BY_UNIT[unit] or nil
	if bw and unit == "Player" then
		-- Player is the one unit whose width Scoot changes with a real SetWidth
		local d = addon and addon.db and addon.db.profile
		local uf = d and d.unitFrames and d.unitFrames.Player
		local pct = tonumber(uf and uf.castBar and uf.castBar.widthPct) or 100
		if pct < 50 then pct = 50 elseif pct > 150 then pct = 150 end
		bw = bw * (pct / 100)
	end
	if not bw or bw <= 0 then return nil end
	return bw
end

-- Shrink the spell name so it always fits inside the bar, by applying an IDENTICAL
-- text scale to filledText and frame.Text.
--
-- Why scale and not SetWidth: pitfalls #25/#28 were caused by WoW's TRUNCATION
-- engine, which re-shapes per-character |cff strings differently depending on their
-- hex values. SetTextScale never invokes it, so it cannot reintroduce that drift,
-- and it does not fight the SetWidth-to-0 guard hooks. Byte-identical strings +
-- identical scale + identical font => identical glyph positions by construction.
--
-- SetSmoothScaling(true) is REQUIRED, not cosmetic: without it WoW snaps the scaled
-- line height to a whole number and re-rasterises, which IS a shaper input and would
-- put the drift straight back.
--
-- Measurement happens on an off-frame UIParent-anchored ruler (addon.MeasureTextWidth),
-- never on filledText: the geometry getters are SecretWhenAnchoringSecret, and
-- filledText anchors through the Blizzard cast bar — the same chain that made
-- GetHeight() secret in pitfall #13. Measuring there would silently no-op on exactly
-- the tainted target/boss bars where this matters most.
--
-- Always recomputes from scratch and never reads the current scale as state, so it
-- is idempotent and self-correcting across mid-cast text changes (channel -> new
-- cast, "Interrupted", the empowered plain-text swap).
--
-- Returns the applied scale (1 when the fit could not run).
local function fitTextFillScale(frame, styleCfg, text)
	local elements = getProp(frame, "textFillElements")
	if not elements or not elements.filledText then return 1 end
	styleCfg = styleCfg or {}

	local baseSize = tonumber(styleCfg.size) or 10
	local s = 1

	-- Keep the name clear of the end caps (capW mirrors applyTextFillMode)
	local barW = resolveBarWidth(frame)
	local capSize = tonumber(elements.capSize) or 6
	local avail = barW and (barW - (2 * math.max(2, capSize * 0.3) + 4)) or nil
	if avail and avail <= 0 then avail = nil end

	if avail and measureTextWidth then
		local face = addon.ResolveFontFace(styleCfg.fontFace)
		local outline = tostring(styleCfg.style or "OUTLINE")
		-- Measure the EXACT bytes that were set, gradient codes included: |cff hex
		-- values participate in kerning resolution (pitfall #28), so the gradient
		-- string's natural width genuinely differs from the plain string's.
		local natural = measureTextWidth(text, face, baseSize, outline)
		if natural and natural > avail then
			s = avail / natural
			-- Floor expressed in point size, not raw scale: 0.5 of a 10pt name is
			-- unreadable. Clamp rather than give up — a partial shrink plus the
			-- clipFrame horizontal overflow strictly beats no shrink at all.
			local minScale = math.min(1, math.max(FIT_MIN_SCALE, FIT_MIN_POINT_SIZE / baseSize))
			if s < minScale then s = minScale end
		end
	end

	local ft = elements.filledText
	if ft.SetSmoothScaling then pcall(ft.SetSmoothScaling, ft, true) end
	if ft.SetTextScale then pcall(ft.SetTextScale, ft, s) end

	local spellFS = frame.Text
	if spellFS then
		if spellFS.SetSmoothScaling then
			if getProp(frame, "textFillSmoothWas") == nil then
				local was = addon.FitSafeBool and addon.FitSafeBool(spellFS, "GetSmoothScaling")
				setProp(frame, "textFillSmoothWas", was == true)
			end
			pcall(spellFS.SetSmoothScaling, spellFS, true)
		end
		if spellFS.SetTextScale then pcall(spellFS.SetTextScale, spellFS, s) end
	end

	setProp(frame, "textFillTextScale", s)
	return s
end

-- Lazily create all text-fill visual elements for a cast bar frame
local function ensureTextFillElements(frame)
	local existing = getProp(frame, "textFillElements")
	if existing then return existing end

	-- Clip frame: children are clipped to its bounds for the progressive fill effect
	local clipFrame = CreateFrame("Frame", nil, frame)
	clipFrame:SetClipsChildren(true)
	-- Frame level auto-inherited from parent (frame) at C++ level,
	-- bypasses Lua secret value restrictions on tainted boss frames

	-- The twelve line and cap textures (core/casttrack.lua): the unfilled set and
	-- the filled line on the PARENT frame, so the line renders below frame.Text
	-- (OVERLAY) within the same frame's layer stack, and the filled caps in
	-- clipFrame for the progressive reveal.
	local elements = addon.CastTrack.Create(frame, clipFrame, { clipFrame = clipFrame })

	local filledText = clipFrame:CreateFontString(nil, "OVERLAY")
	-- Default font so filledText can render even if GetFont returns secrets
	filledText:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
	elements.filledText = filledText

	-- Spark overlay frame (above clipFrame so spark renders in front of text)
	local sparkFrame = CreateFrame("Frame", nil, frame)
	sparkFrame:SetFrameLevel(clipFrame:GetFrameLevel() + 1)
	sparkFrame:SetAllPoints(frame)
	local sparkTex = sparkFrame:CreateTexture(nil, "OVERLAY", nil, 3)
	sparkTex:Hide()
	sparkFrame:Hide()
	elements.sparkFrame = sparkFrame
	elements.sparkTex = sparkTex

	-- Hide initially
	elements.unfilledLineOL:Hide()
	elements.unfilledLeftCapOL:Hide()
	elements.unfilledRightCapOL:Hide()
	elements.unfilledLine:Hide()
	elements.unfilledLeftCap:Hide()
	elements.unfilledRightCap:Hide()
	elements.filledLine:Hide()
	elements.filledLineOL:Hide()
	clipFrame:Hide()

	setProp(frame, "textFillElements", elements)
	return elements
end

-- Lazily create empowered text-fill elements (tier-colored line segments + pip dividers).
-- Reuses the existing clipFrame from the base text-fill elements. Created once per frame,
-- reused across empowered casts. Elements are hidden initially.
local function ensureEmpoweredTextFillElements(frame, elements)
	if elements.empowered then return elements.empowered end

	local clipFrame = elements.clipFrame
	local emp = {
		filledSegs = {},
		unfilledSegs = {},
		pipDividers = {},
		numActive = 0,
		active = false,
	}

	for i = 1, MAX_EMPOWERED_TIERS do
		-- Unfilled segments: on bar frame, same sublayer as unfilledLine (BACKGROUND:1)
		emp.unfilledSegs[i] = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
		emp.unfilledSegs[i]:Hide()

		-- Filled segments: in clipFrame, same sublayer as filledLine (BACKGROUND:2)
		emp.filledSegs[i] = clipFrame:CreateTexture(nil, "BACKGROUND", nil, 2)
		emp.filledSegs[i]:Hide()
	end

	-- Pip dividers: on bar frame, above caps (ARTWORK:3) so they're visible on both portions
	for i = 1, MAX_EMPOWERED_TIERS - 1 do
		local pip = frame:CreateTexture(nil, "ARTWORK", nil, 3)
		pip:SetColorTexture(0, 0, 0, 1)
		pip:Hide()
		emp.pipDividers[i] = pip
	end

	elements.empowered = emp
	return emp
end

-- Show() guards on decorative textures that Blizzard actively re-shows during
-- casts (ShowSpark, FinishSpell, StandardFinish OnPlay, etc.). Instead of
-- fighting the animation state machine with Stop(), let animations play
-- through (so OnFinished callbacks fire) but keep their target textures hidden.
-- Each texture is hooked once; one absent at the first call is picked up later.
local GUARD_TEXTURE_KEYS = {
	"Spark",          -- ShowSpark() → self.Spark:Show()
	"StandardGlow",   -- ShowSpark() → sparkFx:SetShown(true)
	"CraftGlow",      -- ShowSpark() → sparkFx:SetShown(true)
	"ChannelShadow",  -- ShowSpark() → sparkFx:SetShown(true)
	"Flash",          -- FinishSpell() → self.Flash:Show()
	"EnergyGlow",     -- StandardFinish:OnPlay → SetTargetsShown(true)
	"Flakes01",       -- StandardFinish:OnPlay → SetTargetsShown(true)
	"Flakes02",       -- StandardFinish:OnPlay → SetTargetsShown(true)
	"Flakes03",       -- StandardFinish:OnPlay → SetTargetsShown(true)
	-- InterruptGlow intentionally excluded — controlled by hideInterruptGlow toggle independently
}
local function installTextFillShowGuards(frame)
	local guardOpts = textFillGuardOpts(frame)
	for _, key in ipairs(GUARD_TEXTURE_KEYS) do
		Enforce.Install(frame[key], "textFillGuard", guardOpts)
	end
end

-- Activate empowered text-fill: replace single-color line with tier-colored segments
-- anchored between Blizzard's StagePip frames. Deferred because AddStages creates
-- StagePips after the cast starts. Uses anchor-based positioning (secret-safe).
local function activateEmpoweredTextFill(frame, elements, cfg, unit)
	local emp = ensureEmpoweredTextFillElements(frame, elements)

	-- Hide single-color line elements (keep outlines visible — they frame the full bar)
	elements.unfilledLine:Hide()
	elements.filledLine:Hide()

	-- Mark empowered mode on frame for the stage updater in styling.lua
	setProp(frame, "textFillEmpowered", true)

	-- Read text-fill settings
	local lineHeight = math.max(1, math.min(10, tonumber(cfg.textFillLineHeight) or 2))
	local capSize = math.max(2, math.min(20, tonumber(cfg.textFillEndCapSize) or 6))

	-- Resolve foreground texture
	local texKey = cfg.castBarTexture or "default"
	local texturePath = addon.Media and addon.Media.ResolveBarTexturePath
		and addon.Media.ResolveBarTexturePath(texKey)

	-- Defer to ensure Blizzard's AddStages has created StagePips
	C_Timer.After(0, function()
		-- Guard: empowered text-fill may have been deactivated before this fires
		if not getProp(frame, "textFillActive") then return end
		if not getProp(frame, "textFillEmpowered") then return end

		-- Read StagePips with secret guard
		local pips = frame.StagePips
		if not pips or (issecretvalue and issecretvalue(pips)) then
			-- Fallback: re-show single-color lines
			elements.unfilledLine:Show()
			elements.filledLine:Show()
			setProp(frame, "textFillEmpowered", nil)
			return
		end
		local numPips = #pips
		if numPips == 0 then
			elements.unfilledLine:Show()
			elements.filledLine:Show()
			setProp(frame, "textFillEmpowered", nil)
			return
		end

		local numSegments = numPips + 1  -- one more segment than pips
		if numSegments > MAX_EMPOWERED_TIERS then numSegments = MAX_EMPOWERED_TIERS end
		emp.numActive = numSegments

		-- Configure and show segments
		for i = 1, numSegments do
			local nColor = TIER_COLORS_NORMAL[i] or TIER_COLORS_NORMAL[#TIER_COLORS_NORMAL]
			local dColor = TIER_COLORS_DISABLED[i] or TIER_COLORS_DISABLED[#TIER_COLORS_DISABLED]

			-- Unfilled segment (on bar frame)
			local uSeg = emp.unfilledSegs[i]
			uSeg:ClearAllPoints()
			uSeg:SetHeight(lineHeight)
			if i == 1 then
				uSeg:SetPoint("LEFT", frame, "LEFT", 0, 0)
			else
				uSeg:SetPoint("LEFT", pips[i - 1], "CENTER", 0, 0)
			end
			if i <= numPips then
				uSeg:SetPoint("RIGHT", pips[i], "CENTER", 0, 0)
			else
				uSeg:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
			end
			uSeg:SetColorTexture(dColor[1], dColor[2], dColor[3], 1)
			uSeg:Show()

			-- Filled segment (in clipFrame, anchored to bar frame — clipped by clip bounds)
			local fSeg = emp.filledSegs[i]
			fSeg:ClearAllPoints()
			fSeg:SetHeight(lineHeight)
			if i == 1 then
				fSeg:SetPoint("LEFT", frame, "LEFT", 0, 0)
			else
				fSeg:SetPoint("LEFT", pips[i - 1], "CENTER", 0, 0)
			end
			if i <= numPips then
				fSeg:SetPoint("RIGHT", pips[i], "CENTER", 0, 0)
			else
				fSeg:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
			end
			if texturePath then
				fSeg:SetTexture(texturePath)
				fSeg:SetVertexColor(nColor[1], nColor[2], nColor[3], 1)
			else
				fSeg:SetColorTexture(nColor[1], nColor[2], nColor[3], 1)
			end
			fSeg:Show()
		end

		-- Hide unused segments
		for i = numSegments + 1, MAX_EMPOWERED_TIERS do
			emp.unfilledSegs[i]:Hide()
			emp.filledSegs[i]:Hide()
		end

		-- Configure and show pip dividers at stage boundaries
		for i = 1, math.min(numPips, MAX_EMPOWERED_TIERS - 1) do
			local div = emp.pipDividers[i]
			div:ClearAllPoints()
			div:SetSize(1, capSize)
			div:SetPoint("CENTER", pips[i], "CENTER", 0, 0)
			div:Show()
		end
		for i = numPips + 1, MAX_EMPOWERED_TIERS - 1 do
			emp.pipDividers[i]:Hide()
		end

		-- Color end caps to match tier colors
		local firstD = TIER_COLORS_DISABLED[1]
		local firstN = TIER_COLORS_NORMAL[1]
		local lastD = TIER_COLORS_DISABLED[numSegments] or TIER_COLORS_DISABLED[#TIER_COLORS_DISABLED]
		local lastN = TIER_COLORS_NORMAL[numSegments] or TIER_COLORS_NORMAL[#TIER_COLORS_NORMAL]

		-- Unfilled caps: disabled tier colors
		elements.unfilledLeftCap:SetColorTexture(firstD[1], firstD[2], firstD[3], 1)
		elements.unfilledRightCap:SetColorTexture(lastD[1], lastD[2], lastD[3], 1)

		-- Filled caps: bright tier colors (with texture support)
		if texturePath then
			elements.filledLeftCap:SetTexture(texturePath)
			elements.filledLeftCap:SetVertexColor(firstN[1], firstN[2], firstN[3], 1)
			elements.filledRightCap:SetTexture(texturePath)
			elements.filledRightCap:SetVertexColor(lastN[1], lastN[2], lastN[3], 1)
		else
			elements.filledLeftCap:SetColorTexture(firstN[1], firstN[2], firstN[3], 1)
			elements.filledRightCap:SetColorTexture(lastN[1], lastN[2], lastN[3], 1)
		end

		-- Set filled text color to tier 1 (green) — stage updater will advance this
		elements.filledText:SetTextColor(firstN[1], firstN[2], firstN[3], 1)

		-- Hide Blizzard StageTier visuals (keep frames for potential reference)
		local tiers = frame.StageTiers
		if tiers and not (issecretvalue and issecretvalue(tiers)) then
			for _, tier in ipairs(tiers) do
				if tier and not (tier.IsForbidden and tier:IsForbidden()) then
					if tier.Normal then pcall(tier.Normal.SetAlpha, tier.Normal, 0) end
					if tier.Disabled then pcall(tier.Disabled.SetAlpha, tier.Disabled, 0) end
					if tier.Glow then pcall(tier.Glow.SetAlpha, tier.Glow, 0) end
				end
			end

			-- One-time Play() hooks on StageTier animation groups.
			-- FinishAnim plays on cast completion (PlayFinishAnim), forces Glow alpha
			-- to 1 via C++ animation, bypassing the SetAlpha(0) guard. No OnFinished — safe to Stop().
			-- FlashAnim has setToFinalAlpha="true", no OnFinished — safe to Stop().
			if not getProp(frame, "textFillStageTierAnimsHooked") then
				setProp(frame, "textFillStageTierAnimsHooked", true)
				for _, tier in ipairs(tiers) do
					if tier and not (tier.IsForbidden and tier:IsForbidden()) then
						local animGroups = { tier.FinishAnim, tier.FlashAnim }
						for _, ag in ipairs(animGroups) do
							if ag and ag.Play and ag.Stop then
								local agRef, stopFn = ag, ag.Stop
								hooksecurefunc(ag, "Play", function()
									if getProp(frame, "textFillActive") then
										pcall(stopFn, agRef)
									end
								end)
							end
						end
					end
				end
			end

			-- Show() guards on StageTier textures (Normal, Disabled, Glow), once per
			-- texture. UpdateStage() calls Normal:SetShown(true) on completed tiers;
			-- the guard re-hides them at once while text-fill mode is active.
			local guardOpts = textFillGuardOpts(frame)
			for _, tier in ipairs(tiers) do
				if tier and not (tier.IsForbidden and tier:IsForbidden()) then
					Enforce.Install(tier.Normal, "textFillGuard", guardOpts)
					Enforce.Install(tier.Disabled, "textFillGuard", guardOpts)
					Enforce.Install(tier.Glow, "textFillGuard", guardOpts)
				end
			end
		end

		-- Hide Blizzard StagePip visuals (keep frames positioned for anchoring)
		for _, pip in ipairs(pips) do
			if pip and not (pip.IsForbidden and pip:IsForbidden()) then
				if pip.BasePip then pcall(pip.BasePip.SetAlpha, pip.BasePip, 0) end
				if pip.PipFlare then pcall(pip.PipFlare.SetAlpha, pip.PipFlare, 0) end
			end
		end

		emp.active = true
	end)
end

-- Deactivate empowered text-fill: hide tier segments, optionally restore Blizzard alphas.
-- restoreBlizzardAlphas: when true (full teardown via hideTextFillElements), restores
-- StageTier/StagePip alphas to 1 for non-text-fill use. When false/nil (empowered cast
-- ending via EMPOWER_STOP), alphas stay at 0 to prevent a visual flash during the cast
-- bar's fade-out animation. Blizzard's AddStages resets everything for the next cast.
local function deactivateEmpoweredTextFill(frame, elements, restoreBlizzardAlphas)
	local emp = elements and elements.empowered
	if not emp then return end

	-- Hide all empowered segments and pip dividers
	for i = 1, MAX_EMPOWERED_TIERS do
		if emp.unfilledSegs[i] then emp.unfilledSegs[i]:Hide() end
		if emp.filledSegs[i] then emp.filledSegs[i]:Hide() end
	end
	for i = 1, MAX_EMPOWERED_TIERS - 1 do
		if emp.pipDividers[i] then emp.pipDividers[i]:Hide() end
	end

	emp.numActive = 0
	emp.active = false

	-- Clear empowered flag
	setProp(frame, "textFillEmpowered", nil)

	if restoreBlizzardAlphas then
		-- Restore Blizzard StageTier alphas (full teardown only)
		local tiers = frame.StageTiers
		if tiers and not (issecretvalue and issecretvalue(tiers)) then
			for _, tier in ipairs(tiers) do
				if tier and not (tier.IsForbidden and tier:IsForbidden()) then
					if tier.Normal then pcall(tier.Normal.SetAlpha, tier.Normal, 1) end
					if tier.Disabled then pcall(tier.Disabled.SetAlpha, tier.Disabled, 1) end
					if tier.Glow then pcall(tier.Glow.SetAlpha, tier.Glow, 1) end
				end
			end
		end

		-- Restore Blizzard StagePip alphas
		local pips = frame.StagePips
		if pips and not (issecretvalue and issecretvalue(pips)) then
			for _, pip in ipairs(pips) do
				if pip and not (pip.IsForbidden and pip:IsForbidden()) then
					if pip.BasePip then pcall(pip.BasePip.SetAlpha, pip.BasePip, 1) end
					if pip.PipFlare then pcall(pip.PipFlare.SetAlpha, pip.PipFlare, 1) end
				end
			end
		end
	end
end

-- Apply text-fill mode visuals to a cast bar frame.
-- empowered: boolean — when true, replaces single-color line with tier-colored segments.
local function applyTextFillMode(frame, cfg, unit, empowered)
	local elements = ensureTextFillElements(frame)

	-- Resolve fill color from cast bar color settings
	local r, g, b, a = resolveBarFillColor(cfg, unit, frame)

	-- Resolve foreground texture (user's selected bar texture)
	local texKey = cfg.castBarTexture or "default"
	local texturePath = addon.Media and addon.Media.ResolveBarTexturePath
		and addon.Media.ResolveBarTexturePath(texKey)

	-- Read text-fill settings
	local lineHeight = math.max(1, math.min(10, tonumber(cfg.textFillLineHeight) or 2))
	local capSize = math.max(2, math.min(20, tonumber(cfg.textFillEndCapSize) or 6))

	-- Hide StatusBar fill texture (bar continues functioning for spark positioning)
	local fillTex = frame:GetStatusBarTexture()
	if fillTex and fillTex.SetAlpha then
		pcall(fillTex.SetAlpha, fillTex, 0)
	end

	-- Hide custom background (ScootBG)
	local scootBG = getProp(frame, "ScootBG")
	if scootBG and scootBG.SetAlpha then
		pcall(scootBG.SetAlpha, scootBG, 0)
	end
	-- Hide Blizzard stock background
	if frame.Background and frame.Background.SetAlpha then
		pcall(frame.Background.SetAlpha, frame.Background, 0)
	end

	-- InterruptGlow is NOT hidden in text-fill mode — controlled by hideInterruptGlow toggle independently

	-- Hide Blizzard bar border in text-fill mode
	local border = frame.Border
	if border and border.SetAlpha then
		pcall(border.SetAlpha, border, 0)
	end

	-- Hide all decorative chrome textures (animations play invisibly, callbacks still fire)
	local chromeTextures = {
		frame.Spark, frame.Flash,
		frame.StandardGlow, frame.CraftGlow, frame.ChannelShadow,
		frame.EnergyGlow, frame.Flakes01, frame.Flakes02, frame.Flakes03,
		frame.BaseGlow, frame.WispGlow, frame.Sparkles01, frame.Sparkles02,
		frame.Shine, frame.ChargeFlash, frame.ChargeGlow,
	}
	for _, tex in ipairs(chromeTextures) do
		if tex and tex.Hide then pcall(tex.Hide, tex) end
	end

	-- Flag for Show() guards and shake hook to check
	setProp(frame, "textFillActive", true)

	-- Cache the state the shrink-to-fit needs. The SetText hooks that drive the fit
	-- fire without a cfg in scope, so it has to come from here.
	setProp(frame, "textFillUnit", unit)
	setProp(frame, "textFillSpellNameCfg", cfg.spellNameText or {})
	-- Bar width is read HERE rather than in the fit itself: a dimension read on a
	-- dirty layout forces a flush that fires OnSizeChanged, where pcall cannot reach
	-- the error (see the FitTextToBox header in core/fonts.lua). Secret on tainted
	-- target/boss frames — resolveBarWidth falls back to template constants there.
	do
		local ok_bw, raw_bw = pcall(frame.GetWidth, frame)
		if ok_bw and type(raw_bw) == "number"
			and not (issecretvalue and issecretvalue(raw_bw)) and raw_bw > 0 then
			setProp(frame, "textFillBarWidth", raw_bw)
		end
	end

	-- Install one-time Show() hooks so Blizzard can't re-show hidden chrome textures
	installTextFillShowGuards(frame)

	-- One-time hook on InterruptShakeAnim only (frame shake has no critical callbacks
	-- and would visually shake text-fill elements; other animations play through
	-- harmlessly since their target textures are hidden via Show() guards)
	if not getProp(frame, "textFillShakeHooked") then
		setProp(frame, "textFillShakeHooked", true)
		local ag = frame.InterruptShakeAnim
		if ag and ag.Play and ag.Stop then
			local stopFn = ag.Stop
			local agRef = ag
			hooksecurefunc(ag, "Play", function()
				if getProp(frame, "textFillActive") then
					pcall(stopFn, agRef)
				end
			end)
		end
	end

	-- One-time hooks on animation groups whose setToFinalAlpha="true" overrides
	-- the SetAlpha(0) guard at the C++ level during playback.  Stop them immediately.
	-- FlashAnim: no OnFinished callbacks in XML — safe.
	-- StandardFinish: OnFinished calls SetTargetsShown(false), which hides targets — desired.
	-- InterruptGlowAnim: excluded — handled by hideInterruptGlow Play() hook instead.
	if not getProp(frame, "textFillAnimsHooked") then
		setProp(frame, "textFillAnimsHooked", true)
		local animGroups = { frame.FlashAnim, frame.StandardFinish }
		for _, ag in ipairs(animGroups) do
			if ag and ag.Play and ag.Stop then
				local agRef, stopFn = ag, ag.Stop
				hooksecurefunc(ag, "Play", function()
					if getProp(frame, "textFillActive") then
						pcall(stopFn, agRef)
					end
				end)
			end
		end
	end

	-- Hide the custom spark overlay when Blizzard calls HideSpark (cast complete / interrupt)
	-- Also lock clipFrame to full width so filledText stays visible above unfilled elements
	-- during the FadeOutAnim (prevents collapse when fill texture atlas changes in FinishSpell)
	if not getProp(frame, "textFillHideSparkHooked") then
		setProp(frame, "textFillHideSparkHooked", true)
		hooksecurefunc(frame, "HideSpark", function(self)
			if getProp(self, "textFillActive") then
				local els = getProp(self, "textFillElements")
				if els then
					if els.sparkTex then els.sparkTex:Hide() end
					if els.sparkFrame then els.sparkFrame:Hide() end
					-- Lock clipFrame to full width for clean fade-out.
					-- TOPLEFT keeps the same -FIT_H_OVERFLOW as the live anchor, or any
					-- left-spill text would snap bright -> dim at cast end. BOTTOMRIGHT
					-- stays at the bar's RIGHT so text the sweep never reached stays dim.
					if els.clipFrame and els.clipFrame:IsShown() then
						els.clipFrame:ClearAllPoints()
						local textOverflow = 20
						els.clipFrame:SetPoint("TOPLEFT", self, "TOPLEFT", -FIT_H_OVERFLOW, textOverflow)
						els.clipFrame:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", 0, -textOverflow)
					end
					-- Lock filledLine to full bar width (no longer clipped by clipFrame)
					if els.filledLine then
						els.filledLine:ClearAllPoints()
						els.filledLine:SetPoint("LEFT", self, "LEFT", 0, 0)
						els.filledLine:SetPoint("RIGHT", self, "RIGHT", 0, 0)
						els.filledLine:SetHeight(els.lineHeight or 2)
					end
				end
				-- Re-hide fill texture: FinishSpell calls SetStatusBarTexture(full)
				-- before HideSpark, replacing it with a new texture at alpha 1.
				-- The SetStatusBarTexture hook early-returns during empowered casts,
				-- so the new fill texture is never re-hidden by the normal pipeline.
				local ft = self:GetStatusBarTexture()
				if ft and ft.SetAlpha then
					pcall(ft.SetAlpha, ft, 0)
				end
			end
		end)
	end

	-- Re-show the custom spark when Blizzard starts a new cast (ShowSpark)
	if not getProp(frame, "textFillShowSparkHooked") then
		setProp(frame, "textFillShowSparkHooked", true)
		hooksecurefunc(frame, "ShowSpark", function(self)
			if getProp(self, "textFillActive") then
				local els = getProp(self, "textFillElements")
				if els then
					if els.sparkTex then pcall(els.sparkTex.Show, els.sparkTex) end
					if els.sparkFrame then pcall(els.sparkFrame.Show, els.sparkFrame) end
				end
			end
		end)
	end

	-- End cap dimensions (tick style: narrow width, full height)
	local capW = math.max(2, capSize * 0.3)
	local capH = capSize
	elements.capSize = capSize  -- shrink-to-fit reads this for cap padding

	-- Gray color for unfilled elements (solid, no opacity reduction)
	local grayR, grayG, grayB = 0.5, 0.5, 0.5

	-- Clip frame: LEFT-anchored, RIGHT edge tracks fill texture (secret-safe in 12.0)
	local clipFrame = elements.clipFrame

	-- clipFrame auto-inherits level from parent (frame) — no explicit set needed.
	-- Only refresh sparkFrame relative to clipFrame (safe to read, it's a Scoot-owned frame).
	if elements.sparkFrame then
		elements.sparkFrame:SetFrameLevel(clipFrame:GetFrameLevel() + 1)
	end
	clipFrame:ClearAllPoints()
	-- Anchor vertically to bar frame with overflow for text taller than bar.
	-- Uses anchor-based height (secret-safe) instead of SetHeight(GetHeight()).
	-- Horizontal overflow on the LEFT lets a name wider than the bar reveal whole
	-- glyphs instead of being sliced mid-glyph at the bar edge. It does not change
	-- the sweep rate (the right edge tracks fillTex, which spans exactly the bar):
	-- left spill is lit from t=0, right spill never lights. Shrink-to-fit is the
	-- real fix; this is the floor for names that hit the scale clamp.
	-- Safe because every OTHER clipFrame child is anchored to the bar or to
	-- StagePips, never to clipFrame — so widening it reveals only filledText.
	local textOverflow = 20
	clipFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", -FIT_H_OVERFLOW, textOverflow)
	if fillTex then
		clipFrame:SetPoint("BOTTOMRIGHT", fillTex, "BOTTOMRIGHT", 0, -textOverflow)
	else
		-- No fill texture to track: park the right edge at the bar's left, i.e. zero
		-- progress. The left anchor must match the TOPLEFT above or the two would
		-- disagree on where the frame starts.
		clipFrame:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", -FIT_H_OVERFLOW, -textOverflow)
		clipFrame:SetWidth(FIT_H_OVERFLOW + 0.1)
	end
	clipFrame:Show()

	-- The twelve line and cap textures (core/casttrack.lua). X boxes its unfilled
	-- cap outlines all the way round; the filled line and caps take their texture
	-- and tint here, since the track leaves color to its caller.
	addon.CastTrack.Layout(elements, frame, fillTex, {
		lineHeight = lineHeight, capW = capW, capH = capH,
		gray = { grayR, grayG, grayB }, unfilledCapOutline = "box",
	})
	for _, key in ipairs(FILLED_TRACK_KEYS) do
		local el = elements[key]
		if texturePath then
			el:SetTexture(texturePath)
			el:SetVertexColor(r, g, b, a)
		else
			el:SetColorTexture(r, g, b, a)
		end
	end

	-- Filled text color: use spell name font color (not bar fill color).
	-- Bar fill color (r, g, b, a) continues to drive line and cap textures only.
	-- During empowered casts, skip — activateEmpoweredTextFill sets tier colors instead.
	if not empowered then
		local sc = (cfg.spellNameText or {}).color or {1, 1, 1, 1}
		elements.filledText:SetTextColor(sc[1] or 1, sc[2] or 1, sc[3] or 1, sc[4] or 1)
	end
	elements.filledText:Show()

	-- Custom spark overlay for text-fill mode
	do
		local spark = frame.Spark
		local sparkTex = elements.sparkTex
		local sparkFrame = elements.sparkFrame
		if spark and sparkTex and sparkFrame then
			-- Always use the standard yellow pip atlas (avoids stale red atlas after interrupts)
			sparkTex:SetAtlas("ui-castingbar-pip")

			-- Read spark settings (same keys the normal spark block uses)
			local sparkHidden = cfg.castBarSparkHidden == true
			-- isEmpoweredCast not available here; styling.lua handles empowered override before calling
			-- text-fill, so the passed-in cfg state is trusted

			if sparkHidden then
				sparkTex:Hide()
				sparkFrame:Hide()
			else
				-- Spark color
				local sr, sg, sb, sa = addon.ResolveColorRGBA(cfg.castBarSparkColorMode, cfg.castBarSparkTint)
				sparkTex:SetVertexColor(sr, sg, sb, sa)

				-- Initial position anchored to fill texture edge (secret-safe)
				local ok_sw, raw_sw = pcall(spark.GetWidth, spark)
				local sparkW = (ok_sw and type(raw_sw) == "number") and raw_sw or 8
				sparkTex:SetSize(sparkW, lineHeight)
				sparkTex:ClearAllPoints()
				if fillTex then
					sparkTex:SetPoint("CENTER", fillTex, "RIGHT", 0, 0)
				else
					sparkTex:SetPoint("CENTER", frame, "LEFT", 0, 0)
				end
				sparkTex:Show()
				sparkFrame:Show()
			end

			-- Store dimensions for SetValue hook
			elements.lineHeight = lineHeight
			local ok_sw2, raw_sw2 = pcall(spark.GetWidth, spark)
		elements.sparkWidth = (ok_sw2 and type(raw_sw2) == "number") and raw_sw2 or 8
		end
	end

	-- Install SetValue hook once for dynamic spark height
	-- (clip frame width auto-tracks via anchor to fill texture — no arithmetic needed)
	if not getProp(frame, "textFillSetValueHooked") then
		setProp(frame, "textFillSetValueHooked", true)
		hooksecurefunc(frame, "SetValue", function(self, value)
			pcall(function()
				local els = getProp(self, "textFillElements")
				if not els or not els.clipFrame:IsShown() then return end
				-- Dynamic spark height only (clip frame + spark position auto-track via anchors)
				local sparkTex = els.sparkTex
				if sparkTex and els.sparkFrame and els.sparkFrame:IsShown() then
					local ft = self:GetStatusBarTexture()
					local ok_fw, raw_fw = pcall(ft.GetWidth, ft)
					local sparkX = (ok_fw and type(raw_fw) == "number"
						and not (issecretvalue and issecretvalue(raw_fw))) and raw_fw or nil
					local h = els.lineHeight or 2
					local tl = els.textLeftEdge
					local tr = els.textRightEdge
					if sparkX and tl and tr then
						if sparkX >= tl and sparkX <= tr then
							h = els.effectiveTextHeight or h
						end
					elseif els.effectiveTextHeight then
						h = els.effectiveTextHeight
					end
					sparkTex:SetHeight(h)
				end
			end)
		end)
	end

	-- Install SetWidth guard once: re-clamp any non-zero SetWidth to 0 while text-fill
	-- is active. Defensive belt-and-suspenders for pitfall #28 — ensures truncation
	-- never kicks in even if an unknown code path reapplies a width constraint.
	local spellFS = frame.Text
	if spellFS and not getProp(frame, "textFillSetWidthHooked") then
		setProp(frame, "textFillSetWidthHooked", true)
		local widthApplying = false
		hooksecurefunc(spellFS, "SetWidth", function(self, w)
			if widthApplying then return end
			if not getProp(frame, "textFillActive") then return end
			if type(w) == "number" and w > 0 then
				widthApplying = true
				pcall(self.SetWidth, self, 0)
				widthApplying = false
			end
		end)
	end
	if elements and elements.filledText and not getProp(frame, "textFillFilledSetWidthHooked") then
		setProp(frame, "textFillFilledSetWidthHooked", true)
		local widthApplying = false
		hooksecurefunc(elements.filledText, "SetWidth", function(self, w)
			if widthApplying then return end
			if not getProp(frame, "textFillActive") then return end
			if type(w) == "number" and w > 0 then
				widthApplying = true
				pcall(self.SetWidth, self, 0)
				widthApplying = false
			end
		end)
	end

	-- Install SetText hook once for text content sync
	if spellFS and not getProp(frame, "textFillSetTextHooked") then
		setProp(frame, "textFillSetTextHooked", true)
		hooksecurefunc(spellFS, "SetText", function(self, text)
			if CB._rampApplying then return end  -- Skip during gradient re-application
			pcall(function()
				-- Always store captured text for syncTextFillText fallback
				-- (GetText may return secrets on tainted target/boss frames)
				if type(text) == "string" and not (issecretvalue and issecretvalue(text)) then
					setProp(frame, "textFillCapturedText", text)
				elseif issecretvalue and issecretvalue(text) then
					-- Clear stale cache so syncTextFillText falls through to secret passthrough
					setProp(frame, "textFillCapturedText", nil)
				end
				local els = getProp(frame, "textFillElements")
				if els and els.filledText and els.clipFrame:IsShown() then
					-- When gradient mode is active, the gradient SetText hook fires
					-- immediately after and applies matching escape codes to filledText.
					-- Setting raw text here creates a brief mismatch that can cause
					-- kerning differences around thin characters like apostrophes.
					--
					-- The re-fit below is what makes shrink-to-fit correct at all:
					-- syncTextFillText always runs BEFORE Blizzard's SetText (its
					-- SetStatusBarTexture fires first — pitfall #27), so without this
					-- the scale would be computed for the PREVIOUS spell name. No
					-- reentrancy risk: the fit calls SetTextScale, never SetText.
					if not getProp(frame, "textFillGradientActive") then
						els.filledText:SetText(text)
						fitTextFillScale(frame, getProp(frame, "textFillSpellNameCfg"), text)
					elseif issecretvalue and issecretvalue(text) then
						-- Gradient mode + secret: can't apply gradient to secrets, but
						-- correct plain text is better than stale gradient text
						els.filledText:SetText(text)
						fitTextFillScale(frame, getProp(frame, "textFillSpellNameCfg"), text)
					end
				end
			end)
		end)
	end

	-- Empowered cast: replace single-color line with tier-colored segments
	if empowered then
		activateEmpoweredTextFill(frame, elements, cfg, unit)
	elseif elements.empowered and elements.empowered.active then
		-- Was empowered, now not — deactivate empowered elements
		deactivateEmpoweredTextFill(frame, elements)
		-- Re-show single-color lines (hidden by activateEmpoweredTextFill)
		elements.unfilledLine:Show()
		elements.filledLine:Show()
	end
end

-- Hide text-fill elements (when switching back to default mode)
local function hideTextFillElements(frame)
	local elements = getProp(frame, "textFillElements")
	if not elements then return end

	-- Deactivate empowered text-fill if active (full teardown: restore Blizzard alphas)
	if elements.empowered and elements.empowered.active then
		deactivateEmpoweredTextFill(frame, elements, true)
	end

	elements.unfilledLineOL:Hide()
	elements.unfilledLeftCapOL:Hide()
	elements.unfilledRightCapOL:Hide()
	elements.unfilledLine:Hide()
	elements.unfilledLeftCap:Hide()
	elements.unfilledRightCap:Hide()
	-- filledLine/filledLineOL are on the parent frame (not clipFrame), hide explicitly
	elements.filledLine:Hide()
	elements.filledLineOL:Hide()
	elements.clipFrame:Hide()
	if elements.sparkFrame then elements.sparkFrame:Hide() end
	if elements.sparkTex then elements.sparkTex:Hide() end
	-- Clear stored dimensions
	elements.lineHeight = nil
	elements.capSize = nil
	elements.effectiveTextHeight = nil
	elements.textLeftEdge = nil
	elements.textRightEdge = nil
	-- Restore fill texture alpha
	local fillTex = frame:GetStatusBarTexture()
	if fillTex and fillTex.SetAlpha then
		pcall(fillTex.SetAlpha, fillTex, 1)
	end
	-- Restore backgrounds (normal pipeline will re-apply correct opacity)
	if frame.Background and frame.Background.SetAlpha then
		pcall(frame.Background.SetAlpha, frame.Background, 1)
	end
	-- Restore InterruptGlow (default alpha is 0, animations will show it when needed)
	local interruptGlow = frame.InterruptGlow
	if interruptGlow and interruptGlow.SetAlpha then
		pcall(interruptGlow.SetAlpha, interruptGlow, 0)  -- restore to default (hidden until animated)
	end
	-- Restore Blizzard bar border
	local border = frame.Border
	if border and border.SetAlpha then
		pcall(border.SetAlpha, border, 1)
	end
	-- Restore original text visibility (spell name styling block will re-apply on next cycle)
	if frame.Text and frame.Text.SetAlpha then
		pcall(frame.Text.SetAlpha, frame.Text, 1)
	end
	-- Undo shrink-to-fit. Without this the Blizzard FontString stays shrunk after
	-- switching back to castBarMode = "default". This function is the complete exit
	-- surface — it is called only from styling.lua and boss.lua, both the else-branch
	-- of the castBarMode check.
	if frame.Text then
		if frame.Text.SetTextScale then pcall(frame.Text.SetTextScale, frame.Text, 1) end
		if frame.Text.SetSmoothScaling then
			pcall(frame.Text.SetSmoothScaling, frame.Text, getProp(frame, "textFillSmoothWas") == true)
		end
	end
	if elements.filledText and elements.filledText.SetTextScale then
		pcall(elements.filledText.SetTextScale, elements.filledText, 1)
	end
	setProp(frame, "textFillTextScale", nil)
	setProp(frame, "textFillSmoothWas", nil)
	setProp(frame, "textFillBarWidth", nil)
	-- Clear text-fill flag so Show() guards and shake hook become inactive
	setProp(frame, "textFillActive", nil)

	-- Re-show Spark if mid-cast (ShowSpark won't be called again for current cast)
	if (frame.casting or frame.channeling) and frame.Spark then
		pcall(frame.Spark.Show, frame.Spark)
	end
end

-- Sync filled text to match original spell name (called after spell name styling in apply())
local function syncTextFillText(frame, cfg)
	local elements = getProp(frame, "textFillElements")
	if not elements or not elements.filledText then return end
	local spellFS = frame.Text
	if not spellFS then return end

	-- Font: resolve from config directly (same three values styling.lua applies to
	-- frame.Text). Copying via GetFont() means that on tainted frames — where it
	-- returns secrets — filledText silently keeps its creation-time FRIZQT__ 12,
	-- and the shrink-to-fit below, which measures with the CONFIGURED font, would
	-- compute a scale for a font that is not the one being rendered.
	local styleCfg = cfg.spellNameText or {}
	local face = addon.ResolveFontFace(styleCfg.fontFace)
	local size = tonumber(styleCfg.size) or 10
	local flags = tostring(styleCfg.style or "OUTLINE")
	if addon.ApplyFontStyle then
		addon.ApplyFontStyle(elements.filledText, face, size, flags)
	else
		pcall(elements.filledText.SetFont, elements.filledText, face, size, flags)
	end
	-- Copy shadow properties so filled text has identical visual bounds
	do
		local ok_sc, sr, sg, sb, sa = pcall(spellFS.GetShadowColor, spellFS)
		if ok_sc and type(sr) == "number" and not (issecretvalue and issecretvalue(sr)) then
			pcall(elements.filledText.SetShadowColor, elements.filledText, sr, sg, sb, sa or 1)
		end
		local ok_so, sx, sy = pcall(spellFS.GetShadowOffset, spellFS)
		if ok_so and type(sx) == "number" and not (issecretvalue and issecretvalue(sx)) then
			pcall(elements.filledText.SetShadowOffset, elements.filledText, sx, sy)
		end
	end
	-- Copy text content — use cached raw text to avoid copying gradient |cff codes
	local rawText = getProp(spellFS, "_rampRawText")
	local secretText = nil  -- GetText result that may be secret (for direct passthrough)
	if not rawText then
		local ok_rt, rt = pcall(spellFS.GetText, spellFS)
		if ok_rt and type(rt) == "string" then
			if not (issecretvalue and issecretvalue(rt)) then
				rawText = rt
			else
				secretText = rt  -- retain for last-resort passthrough
			end
		end
	end
	-- Fallback to hook-captured text when GetText returns secrets (tainted target/boss frames)
	if not rawText or rawText == "" then
		local cached = getProp(frame, "textFillCapturedText")
		if cached and not (issecretvalue and issecretvalue(cached)) then
			rawText = cached
		else
			rawText = ""
		end
	end
	-- During empowered text-fill, skip gradient coloring — stage updater manages filled text color.
	-- Use plain text so SetTextColor from the stage updater is the sole color source.
	local isEmpoweredTF = elements.empowered and elements.empowered.active
	local styleCfg_tf = styleCfg
	local colorMode_tf = styleCfg_tf.colorMode or "default"
	-- Store gradient-active flag for the SetText hook to skip raw text copies
	local isGradientActive = not isEmpoweredTF and (colorMode_tf == "classGradient" or colorMode_tf == "specGradient" or colorMode_tf == "customGradient")
	setProp(frame, "textFillGradientActive", isGradientActive or nil)
	-- Secret passthrough: when no non-secret text is available but GetText returned a
	-- secret, pass it directly to filledText (SetText is AllowedWhenTainted).  Gradient
	-- processing is skipped (can't do string operations on secrets) and the gradient-
	-- active flag is cleared so the SetText hook can update filledText on subsequent calls.
	local appliedText = nil  -- the exact bytes set on filledText, for the shrink-to-fit
	if (rawText == "") and secretText then
		elements.filledText:SetText(secretText)
		appliedText = secretText
		setProp(frame, "textFillGradientActive", nil)
	elseif isGradientActive and addon.BuildColorRampString then
		local r1, g1, b1, r2, g2, b2 = CB._resolveGradientColors(colorMode_tf, styleCfg_tf)
		local gradientStr = addon.BuildColorRampString(rawText, r1, g1, b1, r2, g2, b2)
		elements.filledText:SetText(gradientStr)
		appliedText = gradientStr
		-- Identical |cff codes on frame.Text eliminate per-character shaper-run
		-- kerning drift that caused ~1-2px apostrophe ghost (see pitfall #28).
		CB._rampApplying = true
		pcall(spellFS.SetText, spellFS, gradientStr)
		CB._rampApplying = false
	else
		elements.filledText:SetText(rawText)
		appliedText = rawText
		-- Ensure frame.Text has raw text (no inline |cff codes) so unfilled color works
		if rawText and getProp(spellFS, "_rampRawText") then
			local ok_gt, currentText = pcall(spellFS.GetText, spellFS)
			if ok_gt and type(currentText) == "string" and not issecretvalue(currentText) and currentText:find("|cff") then
				CB._rampApplying = true
				pcall(spellFS.SetText, spellFS, rawText)
				CB._rampApplying = false
			end
		end
	end
	-- Match alignment
	if elements.filledText.SetJustifyH then elements.filledText:SetJustifyH("CENTER") end
	-- Position to match original text (read from config, not from current anchor)
	elements.filledText:ClearAllPoints()
	local ox = (styleCfg.offset and tonumber(styleCfg.offset.x)) or 0
	local oy = (styleCfg.offset and tonumber(styleCfg.offset.y)) or 0
	elements.filledText:SetPoint("CENTER", frame, "CENTER", ox, oy)
	-- No SetWidth constraint on either text — both render at natural width.
	-- WoW's truncation engine can produce different centering for per-character
	-- |cff codes with different color values, causing ~1-2px offset on long names.
	-- Long names are handled by scaling instead (see fitTextFillScale).
	-- Clear any previously set width constraint (from prior apply cycles).
	-- Must precede every measurement below.
	if elements.filledText.SetWidth then pcall(elements.filledText.SetWidth, elements.filledText, 0) end
	if spellFS.SetWidth then pcall(spellFS.SetWidth, spellFS, 0) end
	-- Shrink long names to fit the bar. Runs here — after the text and font are set,
	-- before the measurements below — because GetStringHeight/GetStringWidth return
	-- SCALED values, so fitting first makes them correct with no adjustment.
	local tfScale = fitTextFillScale(frame, styleCfg, appliedText) or 1
	-- Expand clip frame height to contain text taller than the bar
	local clipFrame = elements.clipFrame
	if clipFrame then
		local ok_th, raw_th = pcall(elements.filledText.GetStringHeight, elements.filledText)
		local textH = (ok_th and type(raw_th) == "number"
			and not (issecretvalue and issecretvalue(raw_th))) and raw_th or nil
		if (not textH or textH <= 0) and size then
			-- Fallback is in unscaled points, so it needs the scale applied by hand
			textH = size * 1.15 * tfScale
		end
		elements.effectiveTextHeight = textH
	end
	-- Store text horizontal bounds for spark height calculation.
	-- Same width ladder as the fit, so these stay meaningful on tainted frames
	-- where GetWidth is secret (previously they collapsed to a 0-width bar).
	local bw = resolveBarWidth(frame) or 0
	local ok_sw, raw_sw = pcall(elements.filledText.GetStringWidth, elements.filledText)
	-- issecretvalue guard is load-bearing (pitfall #12): type() passes secret numbers,
	-- and a secret reaching the comparison below throws, aborting this function inside
	-- the caller's pcall — silently skipping the visibility and unfilled-dim blocks.
	local sw = (ok_sw and type(raw_sw) == "number"
		and not (issecretvalue and issecretvalue(raw_sw))) and raw_sw or 0
	if sw > 0 then
		-- Cap to bar width since clip frame clips at bar edge anyway
		if bw > 0 and sw > bw then sw = bw end
		local cx = (bw > 0 and bw or 0) / 2 + ox
		elements.textLeftEdge = cx - sw / 2
		elements.textRightEdge = cx + sw / 2
	end
	-- Visibility follows spell name hidden state
	if cfg.castBarSpellNameHidden then
		elements.filledText:Hide()
	else
		elements.filledText:Show()
	end
	-- frame.Text stays visible as the unfilled text — spell name styling block manages its alpha
	if spellFS then
		if isGradientActive then
			-- Gradient mode: frame.Text carries identical |cff codes as filledText
			-- (pitfall #28). SetTextColor is overridden by embedded |cff, so dim via
			-- SetAlpha for the backdrop effect.
			pcall(spellFS.SetAlpha, spellFS, 0.4)
		else
			local uc = cfg.textFillUnfilledTextColor or {0.5, 0.5, 0.5, 1}
			pcall(spellFS.SetAlpha, spellFS, 1)
			if spellFS.SetTextColor then
				pcall(spellFS.SetTextColor, spellFS, uc[1] or 0.5, uc[2] or 0.5, uc[3] or 0.5, uc[4] or 1)
			end
		end
	end
end

-- Export text-fill helpers to namespace for styling.lua and boss.lua.
-- cast/core.lua loads BEFORE this file in the TOC, so it must index
-- CB._fitTextFillScale at call time rather than caching it in a local.
CB._applyTextFillMode = applyTextFillMode
CB._hideTextFillElements = hideTextFillElements
CB._syncTextFillText = syncTextFillText
CB._deactivateEmpoweredTextFill = deactivateEmpoweredTextFill
CB._fitTextFillScale = fitTextFillScale
