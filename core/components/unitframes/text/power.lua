--------------------------------------------------------------------------------
-- text/power.lua
-- Power (mana/energy/rage/etc.) text font styling, visibility enforcement, and
-- positioning for all unit frames.
--------------------------------------------------------------------------------

local addonName, addon = ...

-- Power text opts for ResolveColorRGBA: classPower (with the mana lighten)
-- and dkSpec resolve here; default stays white (no barKind, no fallback)
local ufPowerTextColorOpts = { classPowerMode = true, dkSpecMode = true, lightenMana = true }

-- Font half and Zero-Touch gate opts for the power texts (colorModeDK: the DK
-- companion slot triggers styling even when the base mode is "default")
local ufTextFontOpts = { size = 14 }
local ufTextCustomizationOpts = { alignment = true, alignmentMode = true, colorModeDK = true }

-- Reference to FrameState module for safe property storage (avoids writing to Blizzard frames)
local FS = addon.FrameState

-- Secret-value safe helpers (shared module)
local SS = addon.SecretSafe
local safeOffset = SS.safeOffset
local safePointToken = SS.safePointToken
local safeGetWidth = SS.safeGetWidth

-- Cross-file import: NAME_ANCHOR_MAP (defined in text/core.lua, loaded first in TOC)
local NAME_ANCHOR_MAP = addon.UnitFrameText._NAME_ANCHOR_MAP

	-- Unit Frames: Toggle Power % (LeftText when present) and Value (RightText) visibility per unit
do
    -- Cache for resolved power text fontstrings per unit so combat-time hooks stay cheap.
    addon._ufPowerTextFonts = addon._ufPowerTextFonts or {}

	local getUnitFrameFor = addon.GetUnitFrame

	--weak-key cache for power text FontString lookups
	local _ptFSCache = setmetatable({}, { __mode = "k" })

	local function findFontStringByNameHint(root, hint)
		if not root then return nil end
		--check cache
		local rootCache = _ptFSCache[root]
		if rootCache then
			local cached = rootCache[hint]
			if cached then return cached end
		end
		local target
		local function scan(obj)
			if not obj or target then return end
			if obj.GetObjectType and obj:GetObjectType() == "FontString" then
				local nm = obj.GetName and obj:GetName() or (obj.GetDebugName and obj:GetDebugName()) or ""
				if type(nm) == "string" and string.find(string.lower(nm), string.lower(hint), 1, true) then
					target = obj; return
				end
			end
			if obj.GetRegions then
				local n = (obj.GetNumRegions and obj:GetNumRegions(obj)) or 0
				for i = 1, n do
					local r = select(i, obj:GetRegions())
					if r and r.GetObjectType and r:GetObjectType() == "FontString" then
						local nm = r.GetName and r:GetName() or (r.GetDebugName and r:GetDebugName()) or ""
						if type(nm) == "string" and string.find(string.lower(nm), string.lower(hint), 1, true) then
							target = r; return
						end
					end
				end
			end
			if obj.GetChildren then
				local m = (obj.GetNumChildren and obj:GetNumChildren()) or 0
				for i = 1, m do
					local c = select(i, obj:GetChildren())
					scan(c)
					if target then return end
				end
			end
		end
		scan(root)
		--cache non-nil results
		if target then
			if not _ptFSCache[root] then
				_ptFSCache[root] = {}
			end
			_ptFSCache[root][hint] = target
		end
		return target
	end

	-- Resolve the content main frame for anchoring name backdrop
	local function resolveUFContentMain_NLT(unit)
		if unit == "Player" then
			local root = _G.PlayerFrame
			return root and root.PlayerFrameContent and root.PlayerFrameContent.PlayerFrameContentMain or nil
		elseif unit == "Target" then
			local root = _G.TargetFrame
			return root and root.TargetFrameContent and root.TargetFrameContent.TargetFrameContentMain or nil
		elseif unit == "Focus" then
			local root = _G.FocusFrame
			return root and root.TargetFrameContent and root.TargetFrameContent.TargetFrameContentMain or nil
		elseif unit == "Pet" then
			return _G.PetFrame
		end
	end

	-- Resolve the Health Bar status bar for anchoring name backdrop
	local function resolveHealthBar_NLT(unit)
		if unit == "Pet" then return _G.PetFrameHealthBar end
		if unit == "Player" then
			local root = _G.PlayerFrame
			return root
				and root.PlayerFrameContent
				and root.PlayerFrameContent.PlayerFrameContentMain
				and root.PlayerFrameContent.PlayerFrameContentMain.HealthBarsContainer
				and root.PlayerFrameContent.PlayerFrameContentMain.HealthBarsContainer.HealthBar
				or nil
		elseif unit == "Target" then
			local root = _G.TargetFrame
			return root
				and root.TargetFrameContent
				and root.TargetFrameContent.TargetFrameContentMain
				and root.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer
				and root.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer.HealthBar
				or nil
		elseif unit == "Focus" then
			local root = _G.FocusFrame
			return root
				and root.TargetFrameContent
				and root.TargetFrameContent.TargetFrameContentMain
				and root.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer
				and root.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer.HealthBar
				or nil
		end
	end

	-- Resolve power bar for this unit
	local function resolvePowerBarForVisibility(frame, unit)
		if unit == "Pet" then return _G.PetFrameManaBar end
		if frame and frame.ManaBar then return frame.ManaBar end
		-- Try direct paths
		if unit == "Player" then
			local root = _G.PlayerFrame
			if root and root.PlayerFrameContent and root.PlayerFrameContent.PlayerFrameContentMain
				and root.PlayerFrameContent.PlayerFrameContentMain.ManaBarArea
				and root.PlayerFrameContent.PlayerFrameContentMain.ManaBarArea.ManaBar then
				return root.PlayerFrameContent.PlayerFrameContentMain.ManaBarArea.ManaBar
			end
		elseif unit == "Target" then
			local root = _G.TargetFrame
			if root and root.TargetFrameContent and root.TargetFrameContent.TargetFrameContentMain
				and root.TargetFrameContent.TargetFrameContentMain.ManaBar then
				return root.TargetFrameContent.TargetFrameContentMain.ManaBar
			end
		elseif unit == "Focus" then
			local root = _G.FocusFrame
			if root and root.TargetFrameContent and root.TargetFrameContent.TargetFrameContentMain
				and root.TargetFrameContent.TargetFrameContentMain.ManaBar then
				return root.TargetFrameContent.TargetFrameContentMain.ManaBar
			end
		end
	end

	-- Hook UpdateTextString to reapply visibility after Blizzard's updates.
	-- Use hooksecurefunc to avoid replacing the method and taint secure StatusBars.
	local function hookPowerBarUpdateTextString(bar, unit)
		local fstate = FS
		if not bar or not fstate then return end
		if fstate.IsHooked(bar, "powerBarUpdateTextString") then return end
		fstate.MarkHooked(bar, "powerBarUpdateTextString")
		if _G.hooksecurefunc then
			_G.hooksecurefunc(bar, "UpdateTextString", function(self, ...)
				if addon and addon.ApplyUnitFramePowerTextVisibilityFor then
					addon.ApplyUnitFramePowerTextVisibilityFor(unit)
				end
			end)
		end
	end

	-- Styling helpers (defined at do-block scope for use by both applyForUnit and ApplyBossPowerTextStyling)
	addon._ufPowerTextBaselines = addon._ufPowerTextBaselines or {}
	local function ensureBaseline(fs, key, fallbackFrame)
		addon._ufPowerTextBaselines[key] = addon._ufPowerTextBaselines[key] or {}
		local b = addon._ufPowerTextBaselines[key]
		if b.point == nil then
			if fs and fs.GetPoint then
				local p, relTo, rp, x, y = fs:GetPoint(1)
				b.point = p or "CENTER"
				b.relTo = relTo or (fs.GetParent and fs:GetParent()) or fallbackFrame
				b.relPoint = rp or b.point
				b.x = safeOffset(x)
				b.y = safeOffset(y)
			else
				b.point, b.relTo, b.relPoint, b.x, b.y = "CENTER", (fs and fs.GetParent and fs:GetParent()) or fallbackFrame, "CENTER", 0, 0
			end
		end
		return b
	end

	-- Helper to force FontString redraw after alignment change (secret-value safe)
	local function forceTextRedraw(fs)
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

	local function applyTextStyle(fs, styleCfg, baselineKey, fallbackFrame)
		if not fs or not styleCfg then return end
		if not addon.HasTextCustomization(styleCfg, ufTextCustomizationOpts) then
			return
		end
		addon.ApplyTextFont(fs, styleCfg, ufTextFontOpts)
		-- Determine effective color based on colorMode (for Power Bar text)
		local colorMode = addon.ReadColorMode(
			function() return styleCfg.colorMode end,
			function() return styleCfg.colorModeDK end
		)
		local cr, cg, cb, ca = addon.ResolveColorRGBA(colorMode, styleCfg.color, ufPowerTextColorOpts)
		if fs.SetTextColor then pcall(fs.SetTextColor, fs, cr, cg, cb, ca) end

		-- Only modify layout if alignment or offset is explicitly configured (avoids
		-- Apply All Fonts inadvertently changing text positioning).
		local hasLayoutCustomization = styleCfg.alignment ~= nil
			or styleCfg.alignmentMode ~= nil
			or (styleCfg.offset and (styleCfg.offset.x ~= nil or styleCfg.offset.y ~= nil))

		-- Ensure name-anchor reparenting is undone if layout customizations are removed
		if not hasLayoutCustomization then
			local fst = FS
			if fst then
				local origParent = fst.GetProp(fs, "nameAnchorOrigParent")
				if origParent and fs.SetParent then
					pcall(fs.SetParent, fs, origParent)
					local origLayer = fst.GetProp(fs, "nameAnchorOrigLayer") or "OVERLAY"
					local origSub = fst.GetProp(fs, "nameAnchorOrigSublayer") or 1
					pcall(fs.SetDrawLayer, fs, origLayer, origSub)
					fst.SetProp(fs, "nameAnchorOrigParent", nil)
					fst.SetProp(fs, "nameAnchorOrigLayer", nil)
					fst.SetProp(fs, "nameAnchorOrigSublayer", nil)
				end
			end
		end

		if hasLayoutCustomization then
			-- Determine default alignment based on whether this is left (%) or right (value) or center text
			-- Check for both :right and -right patterns to handle all unit types
			local defaultAlign = "LEFT"
			if baselineKey and (baselineKey:find(":right", 1, true) or baselineKey:find("-right", 1, true)) then
				defaultAlign = "RIGHT"
			elseif baselineKey and (baselineKey:find(":center", 1, true) or baselineKey:find("-center", 1, true)) then
				defaultAlign = "CENTER"
			end
			local alignment = styleCfg.alignment or defaultAlign

			local parentBar = fs.GetParent and fs:GetParent()

			-- Get baseline Y position and user offsets
			local b = ensureBaseline(fs, baselineKey, fallbackFrame or parentBar)
			local ox = (styleCfg.offset and tonumber(styleCfg.offset.x)) or 0
			local oy = (styleCfg.offset and tonumber(styleCfg.offset.y)) or 0
			local yOffset = safeOffset(b.y) + oy

			-- Name-anchor mode: position text relative to boss name FontString
			local useNameAnchor = false
			if styleCfg.alignmentMode == "name" and baselineKey and baselineKey:find("^Boss") then
				local bossIdx = baselineKey:match("^Boss(%d+)")
				if bossIdx then
					local bossFrame = addon.GetBossFrame(bossIdx)
					local nameFS = bossFrame and addon.ResolveBossNameFS(bossFrame) or nil
					if nameFS then
						local anchorKey = styleCfg.nameAnchor or "RIGHT_OF_NAME"
						local anchorInfo = NAME_ANCHOR_MAP[anchorKey]
						if anchorInfo then
							useNameAnchor = true
							-- Reparent to contentMain so SetPoint can target nameFS (same hierarchy)
							local contentMain = bossFrame.TargetFrameContent
								and bossFrame.TargetFrameContent.TargetFrameContentMain
							if contentMain and fs.SetParent then
								local fst = FS
								if fst and not fst.GetProp(fs, "nameAnchorOrigParent") then
									fst.SetProp(fs, "nameAnchorOrigParent", fs:GetParent())
									fst.SetProp(fs, "nameAnchorOrigLayer", select(1, fs:GetDrawLayer()))
									fst.SetProp(fs, "nameAnchorOrigSublayer", select(2, fs:GetDrawLayer()))
								end
								pcall(fs.SetParent, fs, contentMain)
								pcall(fs.SetDrawLayer, fs, "OVERLAY", 7)
							end
							local textPt, namePt, justH, gapX, gapY = anchorInfo[1], anchorInfo[2], anchorInfo[3], anchorInfo[4], anchorInfo[5]
							if fs.ClearAllPoints and fs.SetPoint then
								fs:ClearAllPoints()
								pcall(fs.SetPoint, fs, textPt, nameFS, namePt, gapX + ox, gapY + oy)
							end
							if fs.SetJustifyH then
								pcall(fs.SetJustifyH, fs, justH)
							end
							-- Undo two-point width constraint — let text auto-size
							if fs.SetWidth then
								pcall(fs.SetWidth, fs, 0)
							end
							forceTextRedraw(fs)
						end
					end
				end
			end

			if not useNameAnchor then
				-- Restore original parent if previously reparented for name-anchor mode
				local fst = FS
				if fst then
					local origParent = fst.GetProp(fs, "nameAnchorOrigParent")
					if origParent and fs.SetParent then
						pcall(fs.SetParent, fs, origParent)
						local origLayer = fst.GetProp(fs, "nameAnchorOrigLayer") or "OVERLAY"
						local origSub = fst.GetProp(fs, "nameAnchorOrigSublayer") or 1
						pcall(fs.SetDrawLayer, fs, origLayer, origSub)
						fst.SetProp(fs, "nameAnchorOrigParent", nil)
						fst.SetProp(fs, "nameAnchorOrigLayer", nil)
						fst.SetProp(fs, "nameAnchorOrigSublayer", nil)
					end
				end

				-- Bar-relative mode: two-point anchoring to span the parent bar width.
				-- Makes JustifyH work correctly without needing GetWidth() (which can
				-- trigger secret value errors on unit frame StatusBars).
				if fs.ClearAllPoints and fs.SetPoint and parentBar then
					fs:ClearAllPoints()
					local leftPad = 2 + ox
					local rightPad = -2 + ox
					pcall(fs.SetPoint, fs, "LEFT", parentBar, "LEFT", leftPad, yOffset)
					pcall(fs.SetPoint, fs, "RIGHT", parentBar, "RIGHT", rightPad, yOffset)
				end

				if fs.SetJustifyH then
					pcall(fs.SetJustifyH, fs, alignment)
				end

				forceTextRedraw(fs)
			end
		end
	end

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
		local frame = getUnitFrameFor(unit)
		if not frame then return end

		-- Resolve power bar and hook its UpdateTextString if not already hooked
		local pb = resolvePowerBarForVisibility(frame, unit)
		if pb then
			hookPowerBarUpdateTextString(pb, unit)
		end

		--reuse cached FontStrings if available (frame tree is stable)
		local leftFS, rightFS, textStringFS
		local existingCache = addon._ufPowerTextFonts[unit]
		if existingCache and existingCache.leftFS and existingCache.rightFS then
			leftFS = existingCache.leftFS
			rightFS = existingCache.rightFS
			textStringFS = existingCache.textStringFS
		else
			if unit == "Pet" then
				-- Pet uses standalone globals more often
				leftFS = _G.PetFrameManaBarTextLeft
				rightFS = _G.PetFrameManaBarTextRight
			end

			-- Full resolution path (may scan children/regions). This should only run during
			-- explicit styling passes (ApplyStyles), not on every power text update.
			leftFS = leftFS
				or (frame.ManaBar and frame.ManaBar.LeftText)
				or findFontStringByNameHint(frame, "ManaBar.LeftText")
				or findFontStringByNameHint(frame, ".LeftText")
				or findFontStringByNameHint(frame, "ManaBarTextLeft")
			rightFS = rightFS
				or (frame.ManaBar and frame.ManaBar.RightText)
				or findFontStringByNameHint(frame, "ManaBar.RightText")
				or findFontStringByNameHint(frame, ".RightText")
				or findFontStringByNameHint(frame, "ManaBarTextRight")

			-- Also resolve the center TextString (used in NUMERIC display mode and Character Pane)
			-- Ensures styling persists when Blizzard switches between BOTH and NUMERIC modes
			-- Character Pane shows ManaBarText instead of LeftText/RightText
			if unit == "Pet" then
				textStringFS = _G.PetFrameManaBarText
			elseif unit == "Player" then
				local root = _G.PlayerFrame
				textStringFS = root and root.PlayerFrameContent
					and root.PlayerFrameContent.PlayerFrameContentMain
					and root.PlayerFrameContent.PlayerFrameContentMain.ManaBarArea
					and root.PlayerFrameContent.PlayerFrameContentMain.ManaBarArea.ManaBar
					and root.PlayerFrameContent.PlayerFrameContentMain.ManaBarArea.ManaBar.ManaBarText
			elseif unit == "Target" then
				local root = _G.TargetFrame
				textStringFS = root and root.TargetFrameContent
					and root.TargetFrameContent.TargetFrameContentMain
					and root.TargetFrameContent.TargetFrameContentMain.ManaBar
					and root.TargetFrameContent.TargetFrameContentMain.ManaBar.ManaBarText
			elseif unit == "Focus" then
				local root = _G.FocusFrame
				textStringFS = root and root.TargetFrameContent
					and root.TargetFrameContent.TargetFrameContentMain
					and root.TargetFrameContent.TargetFrameContentMain.ManaBar
					and root.TargetFrameContent.TargetFrameContentMain.ManaBar.ManaBarText
			end

			-- Cache resolved fontstrings so combat-time hooks can avoid expensive scans.
			addon._ufPowerTextFonts[unit] = {
				leftFS = leftFS,
				rightFS = rightFS,
				textStringFS = textStringFS,
			}
		end

        -- Apply visibility using SetAlpha (combat-safe) instead of SetShown (taint-prone).
        -- Tri‑state: nil = don't touch; true = hide; false = show.
        local function applyPowerTextVisibility(fs, hiddenSetting, unitForHook)
            if not fs then return end
            local fstate = FS
            if not fstate then return end
            --Invalidate hot-path cache so settings changes propagate
            if fstate then fstate.ClearProp(fs, "powerTextAppliedHidden") end
            if hiddenSetting == nil then
                return
            end
            local hidden = (hiddenSetting == true)
            if hidden then
                if fs.SetAlpha then pcall(fs.SetAlpha, fs, 0) end
                -- Install hooks once to re-enforce alpha when Blizzard calls Show(), SetAlpha(), or SetText()
                if not fstate.IsHooked(fs, "powerTextVisibility") then
                    fstate.MarkHooked(fs, "powerTextVisibility")
                    if _G.hooksecurefunc then
                        -- Hook Show() to re-enforce alpha=0
                        _G.hooksecurefunc(fs, "Show", function(self)
                            local st = FS
                            if st and st.IsHidden(self, "powerText") and self.SetAlpha then
                                pcall(self.SetAlpha, self, 0)
                            end
                        end)
                        -- Hook SetAlpha() to re-enforce alpha=0 when Blizzard tries to make it visible
                        _G.hooksecurefunc(fs, "SetAlpha", function(self, alpha)
                            local st = FS
                            if st and st.IsHidden(self, "powerText") and alpha and alpha > 0 then
                                -- Use C_Timer to avoid infinite recursion (hook calls SetAlpha which triggers hook)
                                if not st.GetProp(self, "powerTextAlphaDeferred") then
                                    st.SetProp(self, "powerTextAlphaDeferred", true)
                                    C_Timer.After(0, function()
                                        local st2 = FS
                                        if st2 then st2.SetProp(self, "powerTextAlphaDeferred", nil) end
                                        if st2 and st2.IsHidden(self, "powerText") and self.SetAlpha then
                                            pcall(self.SetAlpha, self, 0)
                                        end
                                    end)
                                end
                            end
                        end)
                        -- Hook SetText() to re-enforce alpha=0 when Blizzard updates text content
                        _G.hooksecurefunc(fs, "SetText", function(self)
                            local st = FS
                            if st and st.IsHidden(self, "powerText") and self.SetAlpha then
                                pcall(self.SetAlpha, self, 0)
                            end
                        end)
                    end
                end
                fstate.SetHidden(fs, "powerText", true)
            else
                fstate.SetHidden(fs, "powerText", false)
                if fs.SetAlpha then pcall(fs.SetAlpha, fs, 1) end
            end
        end

		-- Visibility: tolerate missing LeftText on some classes/specs (no-op)
		-- When the entire Power Bar is hidden, force all power texts hidden regardless of individual toggles.
		local powerBarHiddenSetting = cfg.powerBarHidden -- tri-state
		local leftHiddenSetting
		local rightHiddenSetting
		if powerBarHiddenSetting == true then
			leftHiddenSetting = true
			rightHiddenSetting = true
		else
			leftHiddenSetting = cfg.powerPercentHidden
			rightHiddenSetting = cfg.powerValueHidden
		end
		applyPowerTextVisibility(leftFS, leftHiddenSetting, unit)
		applyPowerTextVisibility(rightFS, rightHiddenSetting, unit)

        -- Install SetText hook for center TextString to enforce hidden state only
        local fstate = FS
        if textStringFS and fstate and not fstate.IsHooked(textStringFS, "powerTextCenterSetText") then
            fstate.MarkHooked(textStringFS, "powerTextCenterSetText")
            if _G.hooksecurefunc then
                _G.hooksecurefunc(textStringFS, "SetText", function(self)
                    local st = FS
                    if st and st.IsHidden(self, "powerTextCenter") and self.SetAlpha then
                        pcall(self.SetAlpha, self, 0)
                    end
                end)
            end
        end

		-- Migrate dkSpec from base slot to DK companion slot (idempotent)
		local tpv = cfg.textPowerValue
		if tpv then
			addon.MigrateDKColorMode(
				function() return tpv.colorMode end,
				function(v) tpv.colorMode = v end,
				function() return tpv.colorModeDK end,
				function(v) tpv.colorModeDK = v end
			)
		end
		local tpp = cfg.textPowerPercent
		if tpp then
			addon.MigrateDKColorMode(
				function() return tpp.colorMode end,
				function(v) tpp.colorMode = v end,
				function() return tpp.colorModeDK end,
				function(v) tpp.colorModeDK = v end
			)
		end

		if leftFS then applyTextStyle(leftFS, cfg.textPowerPercent or {}, unit .. ":power-left", frame) end
		if rightFS then applyTextStyle(rightFS, cfg.textPowerValue or {}, unit .. ":power-right", frame) end
        -- Style center TextString using Value settings (used in NUMERIC display mode and Character Pane)
        -- Always apply styling if text customizations exist; handle visibility separately
        if textStringFS then
            -- Handle visibility only when explicitly configured
            local centerHiddenSetting = nil
            if powerBarHiddenSetting == true then
                centerHiddenSetting = true
            elseif cfg.powerValueHidden ~= nil then
                centerHiddenSetting = cfg.powerValueHidden
            end

            if centerHiddenSetting ~= nil then
                local valueHidden = (centerHiddenSetting == true)
                if valueHidden then
                    if textStringFS.SetAlpha then pcall(textStringFS.SetAlpha, textStringFS, 0) end
                    if fstate then fstate.SetHidden(textStringFS, "powerTextCenter", true) end
                else
                    if fstate and fstate.IsHidden(textStringFS, "powerTextCenter") then
                        if textStringFS.SetAlpha then pcall(textStringFS.SetAlpha, textStringFS, 1) end
                        fstate.SetHidden(textStringFS, "powerTextCenter", false)
                    end
                end
            end
            -- Always apply styling (applyTextStyle returns early if no customizations)
            if not (fstate and fstate.IsHidden(textStringFS, "powerTextCenter")) then
                applyTextStyle(textStringFS, cfg.textPowerValue or {}, unit .. ":power-center", frame)
            end
        end
	end

    -- Boss frames: Apply Power % (LeftText) and Value (RightText) styling.
    -- Boss frames are not returned by EditModeManagerFrame's UnitFrame system indices like Player/Target/Focus/Pet,
    -- so Boss1..Boss5 are resolved deterministically using their global names.
    function addon.ApplyBossPowerTextStyling()
        local db = addon and addon.db and addon.db.profile
        if not db then return end

        local unitFrames = rawget(db, "unitFrames")
        local cfg = unitFrames and rawget(unitFrames, "Boss") or nil
        if not cfg then
            return
        end

        for i = 1, addon.NUM_BOSS_FRAMES do
            local bossFrame = addon.GetBossFrame(i)
            local manaBar = bossFrame
                and bossFrame.TargetFrameContent
                and bossFrame.TargetFrameContent.TargetFrameContentMain
                and bossFrame.TargetFrameContent.TargetFrameContentMain.ManaBar

            if manaBar then
                -- Ensure combat-time visibility enforcement exists for Boss power texts
                hookPowerBarUpdateTextString(manaBar, "Boss")

                local leftFS = manaBar.LeftText
                local rightFS = manaBar.RightText

                if leftFS then
                    applyTextStyle(leftFS, cfg.textPowerPercent or {}, "Boss" .. tostring(i) .. ":power-left", manaBar)
                end
                if rightFS then
                    applyTextStyle(rightFS, cfg.textPowerValue or {}, "Boss" .. tostring(i) .. ":power-right", manaBar)
                end
            end
        end

        -- Apply visibility once as part of the styling pass.
        if addon.ApplyUnitFramePowerTextVisibilityFor then
            addon.ApplyUnitFramePowerTextVisibilityFor("Boss")
        end
    end

    -- Lightweight visibility-only function used by UpdateTextString hooks.
    -- Uses SetAlpha instead of SetShown to avoid taint during combat.
	function addon.ApplyUnitFramePowerTextVisibilityFor(unit)
        if not addon:IsModuleEnabled("unitFrames", unit) then return end
        local db = addon and addon.db and addon.db.profile
        if not db then return end
        local unitFrames = rawget(db, "unitFrames")
        local cfg = unitFrames and rawget(unitFrames, unit) or nil
        if not cfg then
            return
        end
        --Zero-touch fast path — skip entirely when no visibility settings are configured
        if rawget(cfg, "powerBarHidden") == nil and rawget(cfg, "powerPercentHidden") == nil and rawget(cfg, "powerValueHidden") == nil then return end

        -- Apply visibility using SetAlpha (combat-safe) instead of SetShown (taint-prone).
        -- Tri‑state: nil = don't touch; true = hide; false = show.
        local function applyVisibility(fs, hiddenSetting)
            if not fs then return end
            local fstate = FS
            if not fstate then return end
            if hiddenSetting == nil then
                return
            end
            --Skip if this visibility state is already applied
            local currentApplied = fstate.GetProp(fs, "powerTextAppliedHidden")
            if currentApplied == hiddenSetting then return end
            local hidden = (hiddenSetting == true)
            if hidden then
                if fs.SetAlpha then pcall(fs.SetAlpha, fs, 0) end
                -- Install hooks once to re-enforce alpha when Blizzard calls Show(), SetAlpha(), or SetText()
                if not fstate.IsHooked(fs, "powerTextVisibility") then
                    fstate.MarkHooked(fs, "powerTextVisibility")
                    if _G.hooksecurefunc then
                        -- Hook Show() to re-enforce alpha=0
                        _G.hooksecurefunc(fs, "Show", function(self)
                            local st = FS
                            if st and st.IsHidden(self, "powerText") and self.SetAlpha then
                                pcall(self.SetAlpha, self, 0)
                            end
                        end)
                        -- Hook SetAlpha() to re-enforce alpha=0 when Blizzard tries to make it visible
                        _G.hooksecurefunc(fs, "SetAlpha", function(self, alpha)
                            local st = FS
                            if st and st.IsHidden(self, "powerText") and alpha and alpha > 0 then
                                -- Use C_Timer to avoid infinite recursion (hook calls SetAlpha which triggers hook)
                                if not st.GetProp(self, "powerTextAlphaDeferred") then
                                    st.SetProp(self, "powerTextAlphaDeferred", true)
                                    C_Timer.After(0, function()
                                        local st2 = FS
                                        if st2 then st2.SetProp(self, "powerTextAlphaDeferred", nil) end
                                        if st2 and st2.IsHidden(self, "powerText") and self.SetAlpha then
                                            pcall(self.SetAlpha, self, 0)
                                        end
                                    end)
                                end
                            end
                        end)
                        -- Hook SetText() to re-enforce alpha=0 when Blizzard updates text content
                        _G.hooksecurefunc(fs, "SetText", function(self)
                            local st = FS
                            if st and st.IsHidden(self, "powerText") and self.SetAlpha then
                                pcall(self.SetAlpha, self, 0)
                            end
                        end)
                    end
                end
                fstate.SetHidden(fs, "powerText", true)
                fstate.SetProp(fs, "powerTextAppliedHidden", true)
            else
                fstate.SetHidden(fs, "powerText", false)
                if fs.SetAlpha then pcall(fs.SetAlpha, fs, 1) end
                fstate.SetProp(fs, "powerTextAppliedHidden", false)
            end
        end

        -- Boss frames: apply to Boss1..Boss5 deterministically (no cache dependency).
        if unit == "Boss" then
            local powerBarHiddenSetting = cfg.powerBarHidden -- tri-state
            local leftHiddenSetting
            local rightHiddenSetting
            if powerBarHiddenSetting == true then
                leftHiddenSetting = true
                rightHiddenSetting = true
            else
                leftHiddenSetting = cfg.powerPercentHidden
                rightHiddenSetting = cfg.powerValueHidden
            end
            for i = 1, addon.NUM_BOSS_FRAMES do
                local bossFrame = addon.GetBossFrame(i)
                local mana = bossFrame
                    and bossFrame.TargetFrameContent
                    and bossFrame.TargetFrameContent.TargetFrameContentMain
                    and bossFrame.TargetFrameContent.TargetFrameContentMain.ManaBar
                local leftFS = mana and mana.LeftText or nil
                local rightFS = mana and mana.RightText or nil
                applyVisibility(leftFS, leftHiddenSetting)
                applyVisibility(rightFS, rightHiddenSetting)
            end
            return
        end

        local cache = addon._ufPowerTextFonts and addon._ufPowerTextFonts[unit]
        if not cache then
            -- If fonts haven't been resolved yet this session, skip work here.
            -- They will be resolved during the next ApplyStyles() pass.
            return
        end

        local leftFS = cache.leftFS
        local rightFS = cache.rightFS

        -- Visibility: tolerate missing LeftText on some classes/specs (no-op)
        -- When the entire Power Bar is hidden, force all power texts hidden regardless of individual toggles.
		local powerBarHiddenSetting = cfg.powerBarHidden -- tri-state
		local leftHiddenSetting
		local rightHiddenSetting
		if powerBarHiddenSetting == true then
			leftHiddenSetting = true
			rightHiddenSetting = true
		else
			leftHiddenSetting = cfg.powerPercentHidden
			rightHiddenSetting = cfg.powerValueHidden
		end
        applyVisibility(leftFS, leftHiddenSetting)
        applyVisibility(rightFS, rightHiddenSetting)
	end

	function addon.ApplyAllUnitFramePowerTextVisibility()
		applyForUnit("Player")
		applyForUnit("Target")
		applyForUnit("Focus")
		applyForUnit("Pet")
        if addon.ApplyBossPowerTextStyling then
            addon.ApplyBossPowerTextStyling()
        end
	end

	-- Optional helper mirroring health text settings copy (no-op if missing)
	function addon.CopyUnitFramePowerTextSettings(sourceUnit, destUnit)
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
			"powerPercentHidden",
			"powerValueHidden",
			"textPowerPercent",
			"textPowerValue",
		}
		for _, k in ipairs(keys) do
			if src[k] ~= nil then dst[k] = deepcopy(src[k]) else dst[k] = nil end
		end
		if addon.ApplyUnitFramePowerTextVisibilityFor then addon.ApplyUnitFramePowerTextVisibilityFor(destUnit) end
		return true
	end
end
