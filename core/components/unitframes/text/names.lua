--------------------------------------------------------------------------------
-- text/names.lua
-- Name and level text styling, class-colored names, visibility control, and
-- positioning for all unit frames.
--------------------------------------------------------------------------------

local addonName, addon = ...

-- Scratch opts for ResolveColorRGBA (ToT/FoT name text; no barKind)
local nameTextColorOpts = {}

-- Font-half opts for the name/level texts
local nameTextFontOpts = { size = 14 }

-- ToT/FoT name texts: size 10; alignment counts toward the Zero-Touch gate
local totFotNameFontOpts = { size = 10 }
local totFotNameCustomizationOpts = { alignment = true }

-- Reference to FrameState module for safe property storage (avoids writing to Blizzard frames)
local FS = addon.FrameState

local function getState(frame)
    return FS.Get(frame)
end

-- Secret-value safe helpers (shared module)
local SS = addon.SecretSafe

local Enforce = addon.Enforce
local safeOffset = SS.safeOffset
local safePointToken = SS.safePointToken
local safeGetWidth = SS.safeGetWidth

--Direct upvalue to the event-driven guard (editmode/core.lua loads first in TOC)
local isEditModeActive = addon.EditMode.IsEditModeActiveOrOpening

--- Unit Frames: Apply Name & Level Text styling (visibility, font, size, style, color, offset)
do
	local getUnitFrameFor = addon.GetUnitFrame

	local findFontStringByNameHint = addon.UnitFrameText._FindFontStringByNameHint
	local forceTextRedraw = addon.UnitFrameText._ForceTextRedraw

	-- The backdrop pair lives in text/namebackdrop.lua (loads first in the TOC).
	local applyNameBackdrop = addon.UnitFrameText._ApplyNameBackdrop
	local applyNameBackdropBorder = addon.UnitFrameText._ApplyNameBackdropBorder

	-- Zero‑Touch apply gate: at least one Name/Level/Backdrop setting must be
	-- explicitly set. Shared with text/bossnames.lua through the UFT seam.
	-- Distinct from the hook-install predicate in the applyAll wrapper below,
	-- which also counts useCustomBorders.
	local function hasNameLevelConfig(cfg)
		local function hasAnyOffset(tbl)
			local off = tbl and tbl.offset
			return off and (off.x ~= nil or off.y ~= nil) or false
		end
		local textNameCfg = rawget(cfg, "textName")
		local textLevelCfg = rawget(cfg, "textLevel")
		local hasNameTextSettings = textNameCfg and (
			textNameCfg.fontFace ~= nil
			or textNameCfg.size ~= nil
			or textNameCfg.style ~= nil
			or textNameCfg.colorMode ~= nil
			or textNameCfg.color ~= nil
			or textNameCfg.alignment ~= nil
			or textNameCfg.containerWidthPct ~= nil
			or hasAnyOffset(textNameCfg)
		) or false
		local hasLevelTextSettings = textLevelCfg and (
			textLevelCfg.fontFace ~= nil
			or textLevelCfg.size ~= nil
			or textLevelCfg.style ~= nil
			or textLevelCfg.colorMode ~= nil
			or textLevelCfg.color ~= nil
			or hasAnyOffset(textLevelCfg)
		) or false
		local hasVisibilitySettings = (cfg.nameTextHidden ~= nil) or (cfg.levelTextHidden ~= nil)
		local hasBackdropSettings = (
			cfg.nameBackdropEnabled ~= nil
			or cfg.nameBackdropTexture ~= nil
			or cfg.nameBackdropColorMode ~= nil
			or cfg.nameBackdropTint ~= nil
			or cfg.nameBackdropOpacity ~= nil
			or cfg.nameBackdropWidthPct ~= nil
			or cfg.nameBackdropBorderEnabled ~= nil
			or cfg.nameBackdropBorderStyle ~= nil
			or cfg.nameBackdropBorderThickness ~= nil
			or cfg.nameBackdropBorderInset ~= nil
			or cfg.nameBackdropBorderInsetH ~= nil
			or cfg.nameBackdropBorderInsetV ~= nil
			or cfg.nameBackdropBorderTintEnable ~= nil
			or cfg.nameBackdropBorderTintColor ~= nil
			or cfg.nameBackdropBorderHiddenEdges ~= nil
		)
		return (hasVisibilitySettings or hasNameTextSettings or hasLevelTextSettings or hasBackdropSettings)
	end
	addon.UnitFrameText._HasNameLevelConfig = hasNameLevelConfig

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

		-- Zero‑Touch: only touch Name/Level/Backdrop when at least one relevant setting is explicitly set.
		if not hasNameLevelConfig(cfg) then
			return
		end

		-- Boss frames are a multi-frame system (Boss1..Boss5); their applier lives
		-- in text/bossnames.lua and is read off the addon table at call time (that
		-- file loads after this one in the TOC).
		if unit == "Boss" then
			local applyBoss = addon.ApplyBossNameLevelText
			if applyBoss then applyBoss() end
			return
		end

		local frame = getUnitFrameFor(unit)
		if not frame then return end

		-- Resolve Name and Level FontStrings through the shared resolvers; the
		-- hint-scan fallback below still covers a miss.
		local nameFS = addon.Frames.resolveNameFS(unit)
		local levelFS = addon.Frames.resolveLevelFS(unit)

		-- Fallback: search by name hints
		if not nameFS then nameFS = findFontStringByNameHint(frame, "Name") end
		if not levelFS then levelFS = findFontStringByNameHint(frame, "LevelText") end

		-- Apply visibility only when explicitly configured.
		-- Name/Level text are NOT StatusBar children, so SetShown is safe here.
		if nameFS and nameFS.SetShown and cfg.nameTextHidden ~= nil then
			pcall(nameFS.SetShown, nameFS, not cfg.nameTextHidden)
		end
		if levelFS and levelFS.SetShown and cfg.levelTextHidden ~= nil then
			pcall(levelFS.SetShown, levelFS, not cfg.levelTextHidden)
		end

		-- Apply styling
		addon._ufNameLevelTextBaselines = addon._ufNameLevelTextBaselines or {}
		-- Kept off addon.UnitFrameText: closes over the per-call frame and is read as an upvalue by applyTextStyle.
		local function ensureBaseline(fs, key)
			addon._ufNameLevelTextBaselines[key] = addon._ufNameLevelTextBaselines[key] or {}
			local b = addon._ufNameLevelTextBaselines[key]
			if b.point == nil then
				if fs and fs.GetPoint then
					local p, relTo, rp, x, y = fs:GetPoint(1)
					b.point = p or "CENTER"
					b.relTo = relTo or (fs.GetParent and fs:GetParent()) or frame
					b.relPoint = rp or b.point
					b.x = safeOffset(x)
					b.y = safeOffset(y)
				else
					b.point, b.relTo, b.relPoint, b.x, b.y = "CENTER", (fs and fs.GetParent and fs:GetParent()) or frame, "CENTER", 0, 0
				end
			end
			return b
		end

		-- Optional: widen the name container for Target/Focus to reduce truncation.
		-- Adjusts the Name FontString's width and anchor so the right edge
		-- stays aligned relative to the ReputationColor strip while growing left.
		-- NOTE: This function MUST incorporate the configured offset values because it
		-- runs AFTER applyTextStyle() and overwrites the position set there.
		addon._ufNameContainerBaselines = addon._ufNameContainerBaselines or {}
		local function applyNameContainerWidth(unitKey, nameFSLocal)
			if not nameFSLocal then return end
			-- Only Target/Focus currently support this control; Player/Pet keep stock behavior.
			if unitKey ~= "Target" and unitKey ~= "Focus" then return end

			local unitCfg = unitFrames and rawget(unitFrames, unitKey) or nil
			local styleCfg = unitCfg and rawget(unitCfg, "textName") or nil
			if not styleCfg then
				return
			end
			-- Zero‑Touch: only touch width/anchors if the user explicitly configured this slider.
			if styleCfg.containerWidthPct == nil then
				return
			end
			local pct = tonumber(styleCfg.containerWidthPct) or 100

			-- Clamp slider semantics to [80,150] (matches UI slider).
			if pct < 80 then pct = 80 elseif pct > 150 then pct = 150 end

			-- Read configured offset values (same as applyTextStyle uses)
			local configOffsetX = (styleCfg.offset and tonumber(styleCfg.offset.x)) or 0
			local configOffsetY = (styleCfg.offset and tonumber(styleCfg.offset.y)) or 0

			local key = unitKey .. ":nameContainer"
			local baseline = addon._ufNameContainerBaselines[key]
			if not baseline then
				baseline = {}
				baseline.width = safeGetWidth(nameFSLocal) or 90
				if nameFSLocal.GetPoint then
					local p, relTo, rp, x, y = nameFSLocal:GetPoint(1)
					baseline.point = p or "TOPLEFT"
					baseline.relTo = relTo or (nameFSLocal.GetParent and nameFSLocal:GetParent()) or frame
					baseline.relPoint = rp or baseline.point
					baseline.x = safeOffset(x)
					baseline.y = safeOffset(y)
				else
					baseline.point, baseline.relTo, baseline.relPoint, baseline.x, baseline.y =
						"TOPLEFT", (nameFSLocal.GetParent and nameFSLocal:GetParent()) or frame, "TOPLEFT", 0, 0
				end
				addon._ufNameContainerBaselines[key] = baseline
			end

			-- Read configured alignment (Target/Focus only)
			local alignment = styleCfg.alignment or "LEFT"

			-- When at 100%, restore original width/anchor (with offset) and bail.
			if pct == 100 then
				if nameFSLocal.ClearAllPoints and nameFSLocal.SetPoint and baseline.width then
					nameFSLocal:SetWidth(baseline.width)
					-- Apply text alignment within the container
					if nameFSLocal.SetJustifyH then
						pcall(nameFSLocal.SetJustifyH, nameFSLocal, alignment)
					end
					nameFSLocal:ClearAllPoints()
					nameFSLocal:SetPoint(
						baseline.point or "TOPLEFT",
						baseline.relTo or (nameFSLocal.GetParent and nameFSLocal:GetParent()) or frame,
						baseline.relPoint or baseline.point or "TOPLEFT",
						(baseline.x or 0) + configOffsetX,
						(baseline.y or 0) + configOffsetY
					)
					-- Force redraw to apply alignment visually
					forceTextRedraw(nameFSLocal)
				end
				return
			end

			local baseWidth = baseline.width or safeGetWidth(nameFSLocal) or 90
			local newWidth = math.floor((baseWidth * pct / 100) + 0.5)

			-- Default behavior: scale the width and preserve left anchor.
			local point, relTo, relPoint, xOff, yOff =
				baseline.point, baseline.relTo, baseline.relPoint, baseline.x, baseline.y

			-- If the canonical ReputationColor strip is found, keep right margin stable
			-- by nudging the TOPLEFT X offset leftwards as width grows.
			local main = addon.Frames.resolveUFContentMain(unitKey)
			local rep = main and main.ReputationColor or nil
			if rep and relTo == rep and (point == "TOPLEFT" or point == "LEFT") then
				-- Right edge offset remains unchanged; only the left edge moves.
				local delta = newWidth - baseWidth
				xOff = (xOff or 0) - delta
			end

			if nameFSLocal.SetWidth then
				nameFSLocal:SetWidth(newWidth)
			end
			-- Apply text alignment within the container
			if nameFSLocal.SetJustifyH then
				pcall(nameFSLocal.SetJustifyH, nameFSLocal, alignment)
			end
			if nameFSLocal.ClearAllPoints and nameFSLocal.SetPoint then
				nameFSLocal:ClearAllPoints()
				nameFSLocal:SetPoint(
					point or "TOPLEFT",
					relTo or (nameFSLocal.GetParent and nameFSLocal:GetParent()) or frame,
					relPoint or point or "TOPLEFT",
					(xOff or 0) + configOffsetX,
					(yOff or 0) + configOffsetY
				)
			end
			-- Force redraw to apply alignment visually
			forceTextRedraw(nameFSLocal)
		end

	-- Kept off addon.ResolveColorRGBA: custom and default both fall back to the stored color, else Name/Level Text yellow.
	local function applyTextStyle(fs, styleCfg, baselineKey)
		if not fs or not styleCfg then return end
		if not addon.HasTextCustomization(styleCfg) then
			return
		end
		addon.ApplyTextFont(fs, styleCfg, nameTextFontOpts)
		-- Determine color based on colorMode
		local c = nil
		local colorMode = styleCfg.colorMode or "default"
		if colorMode == "class" then
			-- Class Color: use player's class color
			if addon.GetClassColorRGB then
				local unitForClass = unit == "Player" and "player" or (unit == "Target" and "target" or (unit == "Focus" and "focus" or "pet"))
				local cr, cg, cb = addon.GetClassColorRGB(unitForClass)
				c = { cr or 1, cg or 1, cb or 1, 1 }
			else
				c = {1.0, 0.82, 0.0, 1} -- fallback to default yellow
			end
		elseif colorMode == "custom" then
			-- Custom: use stored color
			c = styleCfg.color or {1.0, 0.82, 0.0, 1}
		else
			-- Default: use Blizzard's default yellow color (1.0, 0.82, 0.0) instead of white
			c = styleCfg.color or {1.0, 0.82, 0.0, 1}
		end
		if fs.SetTextColor then pcall(fs.SetTextColor, fs, c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1) end

		-- Only reposition if offset is explicitly configured.
		-- Prevents Apply All Fonts (which only sets fontFace) from inadvertently changing
		-- text positioning.
		local hasOffsetCustomization = styleCfg.offset and (styleCfg.offset.x ~= nil or styleCfg.offset.y ~= nil)
		if hasOffsetCustomization then
			local ox = tonumber(styleCfg.offset.x) or 0
			local oy = tonumber(styleCfg.offset.y) or 0
			if fs.ClearAllPoints and fs.SetPoint then
				local b = ensureBaseline(fs, baselineKey)
				fs:ClearAllPoints()
				local point = safePointToken(b.point, "CENTER")
				local relTo = b.relTo or (fs.GetParent and fs:GetParent()) or frame
				local relPoint = safePointToken(b.relPoint, point)
				local x = safeOffset(b.x) + ox
				local y = safeOffset(b.y) + oy
				local ok = pcall(fs.SetPoint, fs, point, relTo, relPoint, x, y)
				if not ok then
					local parent = (fs.GetParent and fs:GetParent()) or frame
					pcall(fs.SetPoint, fs, point, parent, relPoint, 0, 0)
				end
			end
		end
	end

	if nameFS then
		applyTextStyle(nameFS, cfg.textName or {}, unit .. ":name")
		-- Apply optional name container width adjustment (Target/Focus only).
		applyNameContainerWidth(unit, nameFS)

		-- For Target/Focus name text with class color, Blizzard resets the color on target change.
		-- Install hooks to immediately re-apply the class color, preventing visible flash.
		if (unit == "Target" or unit == "Focus") and cfg.textName and cfg.textName.colorMode == "class" then
			local nameState = getState(nameFS)
			local unitFrame = unit == "Target" and _G.TargetFrame or _G.FocusFrame

			-- Hook SetTextColor on the FontString to catch color changes during target switches
			if nameState and not nameState.textColorHooked then
				nameState.textColorHooked = true

				hooksecurefunc(nameFS, "SetTextColor", function(self, r, g, b, a)
					-- Guard against recursion since SetTextColor is called inside the hook
					local st = getState(self)
					if st and st.applyingTextColor then return end

					-- Check if class color is configured for this unit
					local db = addon and addon.db and addon.db.profile
					local unitKey = unit -- captured from outer scope
					local unitCfg = db and db.unitFrames and db.unitFrames[unitKey]
					local textNameCfg = unitCfg and unitCfg.textName

					if textNameCfg and textNameCfg.colorMode == "class" and addon.GetClassColorRGB then
						local unitToken = unitKey == "Target" and "target" or "focus"
						local cr, cg, cb = addon.GetClassColorRGB(unitToken)
						if cr and cg and cb then
							-- Re-apply the class color (overrides what Blizzard just set)
							if st then st.applyingTextColor = true end
							pcall(self.SetTextColor, self, cr, cg, cb, 1)
							if st then st.applyingTextColor = nil end
						end
					end
					-- If class color not configured, Blizzard's color remains (hook does nothing)
				end)
			end

			-- Hook the unit frame's OnShow to catch the "frame freshly drawn" case.
			-- When going from no target to having a target, the frame shows and unit data
			-- may not be available during the initial SetTextColor call.
			-- Strategy: Hide the name text immediately on show, apply the color, then reveal it.
			-- Prevents any flash of the wrong color.
			local frameState = getState(unitFrame)
			if unitFrame and frameState and not frameState.onShowClassColorHooked then
				frameState.onShowClassColorHooked = true

				unitFrame:HookScript("OnShow", function(self)
					local db = addon and addon.db and addon.db.profile
					local unitKey = unit
					local unitCfg = db and db.unitFrames and db.unitFrames[unitKey]
					local textNameCfg = unitCfg and unitCfg.textName

					if textNameCfg and textNameCfg.colorMode == "class" and nameFS then
						-- Hide the name text immediately to prevent flash
						pcall(nameFS.SetAlpha, nameFS, 0)

						-- Defer to next frame to ensure unit data is available, then apply color and reveal
						C_Timer.After(0, function()
							if addon.GetClassColorRGB then
								local unitToken = unitKey == "Target" and "target" or "focus"
								local cr, cg, cb = addon.GetClassColorRGB(unitToken)
								if cr and cg and cb and nameFS.SetTextColor then
									local st = getState(nameFS)
									if st then st.applyingTextColor = true end
									pcall(nameFS.SetTextColor, nameFS, cr, cg, cb, 1)
									if st then st.applyingTextColor = nil end
								end
							end
							-- Reveal the name text with correct color
							pcall(nameFS.SetAlpha, nameFS, 1)
						end)
					end
				end)
			end
		end
	end
	if levelFS then 
		applyTextStyle(levelFS, cfg.textLevel or {}, unit .. ":level")
		
		-- For Player level text, Blizzard uses SetVertexColor (not SetTextColor!) which requires special handling
		-- Blizzard constantly resets the level color, so hooksecurefunc re-applies the custom color
		-- CRITICAL: hooksecurefunc avoids taint. Method overrides cause taint that spreads
		-- through the execution context, blocking protected functions like SetTargetClampingInsets().
		if unit == "Player" and levelFS then
			-- Install hook once (hooksecurefunc runs AFTER Blizzard's SetVertexColor)
			local levelState = getState(levelFS)
			if levelState and not levelState.vertexColorHooked then
				levelState.vertexColorHooked = true
				
				hooksecurefunc(levelFS, "SetVertexColor", function(self, r, g, b, a)
					-- Guard against recursion since SetVertexColor is called inside the hook
					local st = getState(self)
					if st and st.applyingVertexColor then return end
					
					-- Check if a custom color is configured
					local db = addon and addon.db and addon.db.profile
					if db and db.unitFrames and db.unitFrames.Player and db.unitFrames.Player.textLevel and db.unitFrames.Player.textLevel.color then
						local c = db.unitFrames.Player.textLevel.color
						-- Re-apply the custom color (overrides what Blizzard just set)
						if st then st.applyingVertexColor = true end
						pcall(self.SetVertexColor, self, c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
						if st then st.applyingVertexColor = nil end
					end
					-- If no custom color configured, Blizzard's color remains (hook does nothing)
				end)
			end
			
			-- Apply the custom color immediately if configured
			if cfg.textLevel and cfg.textLevel.color then
				local c = cfg.textLevel.color
				local st = getState(levelFS)
				if st then st.applyingVertexColor = true end
				pcall(levelFS.SetVertexColor, levelFS, c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
				if st then st.applyingVertexColor = nil end
			end
		end
	end
		-- Name Backdrop and Border: texture strip anchored to the top edge of the
		-- Health Bar at the lowest z-order, and a border drawn around the same region.
		do
			local main = addon.Frames.resolveUFContentMain(unit)
			local hb = addon.Frames.resolveHealthBar(nil, unit)
			-- Anchor to the RIGHT edge for Target/Focus so the strip grows left
			-- from the portrait side.
			local growLeft = (unit == "Target" or unit == "Focus")
			-- false: the health-bar width was unreadable; abort the rest of the
			-- pass (the pre-split blocks returned out of the whole function here).
			if applyNameBackdrop(main, hb, cfg, unit, growLeft) == false then return end
			if applyNameBackdropBorder(main, hb, cfg, unit, growLeft) == false then return end
		end
	end

	function addon.ApplyUnitFrameNameLevelTextFor(unit)
		applyForUnit(unit)
	end

	function addon.ApplyAllUnitFrameNameLevelText()
		applyForUnit("Player")
		applyForUnit("Target")
		applyForUnit("Focus")
		applyForUnit("Pet")
		applyForUnit("Boss")
	end

	-- Hook TargetFrame_Update, FocusFrame_Update, and Player frame update functions
	-- to reapply name/level text styling (including visibility and alignment) after
	-- Blizzard's updates reset properties.
	--
	-- IMPORTANT (pop-in): Reapply immediately (same frame) to avoid visible
	-- "flash" when acquiring a target. hooksecurefunc already runs AFTER Blizzard's
	-- update completes, so an additional one-frame defer is not required for correctness.
	-- A second reapply is optionally scheduled on the next tick as a safety net.
	local _nameLevelTextHooksInstalled = false
	local function installNameLevelTextHooks()
		if _nameLevelTextHooksInstalled then return end
		_nameLevelTextHooksInstalled = true

		local function reapply(unit)
			if not addon.ApplyUnitFrameNameLevelTextFor then return end
			-- Immediate enforcement (prevents pop-in)
			addon.ApplyUnitFrameNameLevelTextFor(unit)
			-- One-tick backup in case a later same-frame Blizzard update path overrides it
			if _G.C_Timer and _G.C_Timer.After then
				_G.C_Timer.After(0, function()
					if addon.ApplyUnitFrameNameLevelTextFor then
						addon.ApplyUnitFrameNameLevelTextFor(unit)
					end
				end)
			end
		end

		-- Player frame hooks: PlayerFrame_Update and PlayerFrame_UpdateRolesAssigned
		-- can reset level text visibility. Hook both to ensure custom settings persist.
		if _G.hooksecurefunc then
			-- PlayerFrame_Update calls PlayerFrame_UpdateLevel which sets the level text
			if type(_G.PlayerFrame_Update) == "function" then
				_G.hooksecurefunc("PlayerFrame_Update", function()
					reapply("Player")
				end)
			end
			
			-- PlayerFrame_UpdateRolesAssigned directly sets PlayerLevelText:SetShown()
			if type(_G.PlayerFrame_UpdateRolesAssigned) == "function" then
				_G.hooksecurefunc("PlayerFrame_UpdateRolesAssigned", function()
					reapply("Player")
				end)
			end
			
			-- PlayerFrame_ToPlayerArt is called when switching from vehicle to player
			if type(_G.PlayerFrame_ToPlayerArt) == "function" then
				_G.hooksecurefunc("PlayerFrame_ToPlayerArt", function()
					reapply("Player")
				end)
			end
		end

		if _G.hooksecurefunc and type(_G.TargetFrame_Update) == "function" then
			_G.hooksecurefunc("TargetFrame_Update", function()
				if isEditModeActive() then return end
				reapply("Target")
			end)
		end

		if _G.hooksecurefunc and type(_G.FocusFrame_Update) == "function" then
			_G.hooksecurefunc("FocusFrame_Update", function()
				if isEditModeActive() then return end
				reapply("Focus")
			end)
		end
	end

	-- Install hooks on first style application
	local _origApplyAll = addon.ApplyAllUnitFrameNameLevelText
	addon.ApplyAllUnitFrameNameLevelText = function()
		-- Zero-Touch: only install persistence hooks when Name/Level/Backdrop is configured.
		local db = addon and addon.db and addon.db.profile
		local unitFrames = db and rawget(db, "unitFrames") or nil
		local function hasAnyOffset(tbl)
			local off = tbl and tbl.offset
			return off and (off.x ~= nil or off.y ~= nil) or false
		end
		local function unitHasNameLevelConfig(unit)
			local cfg = unitFrames and rawget(unitFrames, unit) or nil
			if not cfg then return false end
			if cfg.nameTextHidden ~= nil or cfg.levelTextHidden ~= nil then return true end
			if cfg.nameBackdropEnabled ~= nil
				or cfg.nameBackdropTexture ~= nil
				or cfg.nameBackdropColorMode ~= nil
				or cfg.nameBackdropTint ~= nil
				or cfg.nameBackdropOpacity ~= nil
				or cfg.nameBackdropWidthPct ~= nil
				or cfg.nameBackdropBorderEnabled ~= nil
				or cfg.nameBackdropBorderStyle ~= nil
				or cfg.nameBackdropBorderThickness ~= nil
				or cfg.nameBackdropBorderInset ~= nil
				or cfg.nameBackdropBorderInsetH ~= nil
				or cfg.nameBackdropBorderInsetV ~= nil
				or cfg.nameBackdropBorderTintEnable ~= nil
				or cfg.nameBackdropBorderTintColor ~= nil
				or cfg.nameBackdropBorderHiddenEdges ~= nil
				or cfg.useCustomBorders ~= nil
			then
				return true
			end
			local tn = rawget(cfg, "textName")
			if tn and (tn.fontFace ~= nil or tn.size ~= nil or tn.style ~= nil or tn.colorMode ~= nil or tn.color ~= nil or tn.alignment ~= nil or tn.containerWidthPct ~= nil or hasAnyOffset(tn)) then
				return true
			end
			local tl = rawget(cfg, "textLevel")
			if tl and (tl.fontFace ~= nil or tl.size ~= nil or tl.style ~= nil or tl.colorMode ~= nil or tl.color ~= nil or hasAnyOffset(tl)) then
				return true
			end
			return false
		end
		if unitHasNameLevelConfig("Player") or unitHasNameLevelConfig("Target") or unitHasNameLevelConfig("Focus") or unitHasNameLevelConfig("Pet") or unitHasNameLevelConfig("Boss") then
			installNameLevelTextHooks()
		end
		_origApplyAll()
	end
end

--- Unit Frames: ToT and FoT Name Text styling
do
	-- The two small-frame names differ only by these tokens (the descriptor idiom
	-- from bars/smallframes.lua). hookFlag is asymmetric: the ToT flag predates
	-- the unit-prefixed convention, and the flags are per-frame, so the names
	-- never collide. Carry both verbatim.
	local SMALL_NAME_CONFIG = {
		{
			unitKey = "TargetOfTarget",
			globalName = "TargetFrameToT",
			baselineStore = "_ufToTNameTextBaseline",
			hiddenKey = "totName",
			hookFlag = "nameTextHooked",
			unitForClass = "targettarget",
		},
		{
			unitKey = "FocusTarget",
			globalName = "FocusFrameToT",
			baselineStore = "_ufFoTNameTextBaseline",
			hiddenKey = "fotName",
			hookFlag = "fotNameTextHooked",
			unitForClass = "focustarget",
		},
	}

	-- Hide-enforcement hooks (core/enforce.lua): the flags stay in FrameState and
	-- the keys read them live; SetText and Show re-assert at once.
	for _, desc in ipairs(SMALL_NAME_CONFIG) do
		addon[desc.baselineStore] = addon[desc.baselineStore] or {}
		local hiddenKey = desc.hiddenKey
		desc.enforceOpts = { methods = { "SetText", "Show" }, when = function(fs) return FS.IsHidden(fs, hiddenKey) end }
	end
	table.freeze(SMALL_NAME_CONFIG)

	-- Capture baseline position once per store. The store is re-read through addon
	-- on every call: the style revert in base/core.lua replaces these tables.
	-- Kept off addon.UnitFrameText: capture into a flat single baseline, not the keyed store.
	local function ensureBaseline(nameFS, storeName)
		local store = addon[storeName]
		if not store.point then
			if nameFS and nameFS.GetPoint then
				local p, relTo, rp, x, y = nameFS:GetPoint(1)
				store.point = p or "TOPLEFT"
				store.relTo = relTo or (nameFS.GetParent and nameFS:GetParent())
				store.relPoint = rp or store.point
				store.x = safeOffset(x)
				store.y = safeOffset(y)
			else
				store.point = "TOPLEFT"
				store.relTo = nameFS and nameFS.GetParent and nameFS:GetParent()
				store.relPoint = "TOPLEFT"
				store.x = 0
				store.y = 0
			end
		end
		return store
	end

	-- Apply small-frame Name Text styling for one descriptor
	local function applySmallNameText(desc)
		local db = addon and addon.db and addon.db.profile
		if not db then return end
		-- Zero‑Touch: do not create config tables. If the unit has no config, do nothing.
		local unitFrames = rawget(db, "unitFrames")
		local cfg = unitFrames and rawget(unitFrames, desc.unitKey) or nil
		if not cfg then return end
		local styleCfg = rawget(cfg, "textName")

		local nameFS = addon.Frames.resolveNameFS(desc.unitKey)
		if not nameFS then return end

		-- Zero‑Touch: if neither visibility nor style is configured, do nothing.
		local hasVisibilitySetting = (cfg.nameTextHidden ~= nil)
		local hasStyleSetting = addon.HasTextCustomization(styleCfg, totFotNameCustomizationOpts)
		if not hasVisibilitySetting and not hasStyleSetting then
			return
		end

		-- Apply visibility: tri‑state (nil=no touch) via SetAlpha (combat-safe)
		-- NOTE: Uses FrameState to avoid writing properties directly to Blizzard frames (causes taint).
		local fstate = FS
		if cfg.nameTextHidden ~= nil and fstate then
			local hidden = (cfg.nameTextHidden == true)
			if hidden then
				if nameFS.SetAlpha then pcall(nameFS.SetAlpha, nameFS, 0) end
				fstate.SetHidden(nameFS, desc.hiddenKey, true)
				Enforce.Install(nameFS, desc.hiddenKey, desc.enforceOpts)
			else
				fstate.SetHidden(nameFS, desc.hiddenKey, false)
				if nameFS.SetAlpha then pcall(nameFS.SetAlpha, nameFS, 1) end
			end
		end

		-- Skip styling if hidden
		if cfg.nameTextHidden == true then return end
		-- Zero‑Touch: only apply font/position/style if explicitly customized.
		if not hasStyleSetting then
			return
		end

		-- Apply font styling
		addon.ApplyTextFont(nameFS, styleCfg, totFotNameFontOpts)

		-- Apply color based on colorMode (no barKind: the small-frame name default is white)
		local colorMode = (styleCfg and styleCfg.colorMode) or "default"
		nameTextColorOpts.unitForClass = desc.unitForClass
		local r, g, b, a = addon.ResolveColorRGBA(colorMode, styleCfg and styleCfg.color, nameTextColorOpts)
		if nameFS.SetTextColor then pcall(nameFS.SetTextColor, nameFS, r, g, b, a) end

		-- Apply alignment
		local alignment = (styleCfg and styleCfg.alignment) or "LEFT"
		if nameFS.SetJustifyH then pcall(nameFS.SetJustifyH, nameFS, alignment) end

		-- Apply offset relative to baseline
		local ox = tonumber(styleCfg and styleCfg.offset and styleCfg.offset.x) or 0
		local oy = tonumber(styleCfg and styleCfg.offset and styleCfg.offset.y) or 0
		if nameFS.ClearAllPoints and nameFS.SetPoint then
			local b = ensureBaseline(nameFS, desc.baselineStore)
			nameFS:ClearAllPoints()
			local point = safePointToken(b.point, "TOPLEFT")
			local relTo = b.relTo or (nameFS.GetParent and nameFS:GetParent())
			local relPoint = safePointToken(b.relPoint, point)
			local x = safeOffset(b.x) + ox
			local y = safeOffset(b.y) + oy
			local ok = pcall(nameFS.SetPoint, nameFS, point, relTo, relPoint, x, y)
			if not ok then
				local parent = (nameFS.GetParent and nameFS:GetParent())
				pcall(nameFS.SetPoint, nameFS, point, parent, relPoint, 0, 0)
			end
		end
	end

	-- Expose for UI and Copy From
	local function applyToTNameText() applySmallNameText(SMALL_NAME_CONFIG[1]) end
	local function applyFoTNameText() applySmallNameText(SMALL_NAME_CONFIG[2]) end
	addon.ApplyToTNameText = applyToTNameText
	addon.ApplyFoTNameText = applyFoTNameText

	-- Hook the small frame's OnShow to reapply styling: both frames are re-shown
	-- when their unit changes.
	-- NOTE: Uses FrameState to avoid writing properties directly to Blizzard frames (causes taint).
	local function installSmallNameHooks(desc, apply)
		local fstate = FS
		if not fstate then return end
		local frame = _G[desc.globalName]
		if frame and not fstate.IsHooked(frame, desc.hookFlag) then
			fstate.MarkHooked(frame, desc.hookFlag)
			if frame.HookScript then
				frame:HookScript("OnShow", function()
					if _G.C_Timer and _G.C_Timer.After then
						_G.C_Timer.After(0, apply)
					end
				end)
			end
		end
	end

	-- Install hooks after PLAYER_ENTERING_WORLD; one registration serves both
	-- frames, ToT then FoT, the order the two per-block registrations fired in.
	addon.Events.On("UnitFrames:Names", "PLAYER_ENTERING_WORLD", function()
		if _G.C_Timer and _G.C_Timer.After then
			_G.C_Timer.After(0.5, function()
				installSmallNameHooks(SMALL_NAME_CONFIG[1], applyToTNameText)
				applyToTNameText()
				installSmallNameHooks(SMALL_NAME_CONFIG[2], applyFoTNameText)
				applyFoTNameText()
			end)
		end
	end)
end
