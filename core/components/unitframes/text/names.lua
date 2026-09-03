--------------------------------------------------------------------------------
-- text/names.lua
-- Name and level text styling, class-colored names, visibility control, and
-- positioning for all unit frames.
--------------------------------------------------------------------------------

local addonName, addon = ...

-- Scratch opts for ResolveColorRGBA (ToT/FoT name text; no barKind)
local nameTextColorOpts = {}

-- Reference to FrameState module for safe property storage (avoids writing to Blizzard frames)
local FS = addon.FrameState

local function getState(frame)
    return FS.Get(frame)
end

-- Secret-value safe helpers (shared module)
local SS = addon.SecretSafe
local safeOffset = SS.safeOffset
local safePointToken = SS.safePointToken
local safeGetWidth = SS.safeGetWidth

--Direct upvalue to the event-driven guard (editmode/core.lua loads first in TOC)
local isEditModeActive = addon.EditMode.IsEditModeActiveOrOpening

--- Unit Frames: Apply Name & Level Text styling (visibility, font, size, style, color, offset)
do
	local getUnitFrameFor = addon.GetUnitFrame

	-- Local resolvers for this block (backdrop anchoring helpers)
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

	--weak-key cache for name/level text FontString lookups
	local _nlFSCache = setmetatable({}, { __mode = "k" })

	local function findFontStringByNameHint(root, hint)
		if not (root and hint) then return nil end
		--check cache
		local rootCache = _nlFSCache[root]
		if rootCache then
			local cached = rootCache[hint]
			if cached then return cached end
		end
		local target = nil
		local function scan(obj)
			if not obj then return end
			if target then return end
			if obj.IsObjectType and obj:IsObjectType("FontString") then
				local nm = obj.GetName and obj:GetName() or ""
				if type(nm) == "string" and string.find(nm, hint, 1, true) then
					target = obj
					return
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
			if not _nlFSCache[root] then
				_nlFSCache[root] = {}
			end
			_nlFSCache[root][hint] = target
		end
		return target
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

		-- Zero‑Touch: only touch Name/Level/Backdrop when at least one relevant setting is explicitly set.
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
		if not (hasVisibilitySettings or hasNameTextSettings or hasLevelTextSettings or hasBackdropSettings) then
			return
		end

		-- Boss frames are a multi-frame system (Boss1..Boss5). They do not map cleanly
		-- to a single "unit frame" for baseline/child resolution. Handle as a special case.
		if unit == "Boss" then
			-- Ensure a first application pass when the boss system becomes visible.
			-- Boss frames often become relevant only after the container shows (e.g., in instances),
			-- so the container is hooked once to trigger a reapply and install per-frame hooks.
			if _G and _G.hooksecurefunc then
				local container = _G.BossTargetFrameContainer
				local cState = getState(container)
				if container and cState and not cState.bossNameTextContainerHooked then
					cState.bossNameTextContainerHooked = true
					if type(container.OnShow) == "function" then
						_G.hooksecurefunc(container, "OnShow", function()
							-- IMPORTANT (taint): This hook executes inside Blizzard's boss-frame show/layout flow.
							-- Do not run styling synchronously here; defer to break the execution context chain.
							local function doApply()
								if InCombatLockdown and InCombatLockdown() then
									-- Boss frames show/hide during encounters; defer the heavy work until out of combat.
									addon._pendingApplyStyles = true
									return
								end
								if addon and addon.ApplyUnitFrameNameLevelTextFor then
									addon.ApplyUnitFrameNameLevelTextFor("Boss")
								end
							end
							if _G.C_Timer and _G.C_Timer.After then
								_G.C_Timer.After(0, doApply)
							else
								doApply()
							end
						end)
					end
				end
			end

			-- Apply to all five boss frames when any Boss name/backdrop setting is configured.
			-- Zero‑Touch remains intact because this block is only reached when cfg exists AND
			-- at least one relevant setting was explicitly set above.
			local resolveBossFrame = addon.GetBossFrame

			local resolveBossNameFS = addon.ResolveBossNameFS

			local function resolveBossLevelFS(bossFrame)
				return (bossFrame
					and bossFrame.TargetFrameContent
					and bossFrame.TargetFrameContent.TargetFrameContentMain
					and bossFrame.TargetFrameContent.TargetFrameContentMain.LevelText)
					or nil
			end

			local function resolveBossContentMain(bossFrame)
				return bossFrame
					and bossFrame.TargetFrameContent
					and bossFrame.TargetFrameContent.TargetFrameContentMain
					or nil
			end

			local function resolveBossHealthBar(bossFrame)
				-- Blizzard exposes bossFrame.healthbar (preferred).
				return bossFrame and bossFrame.healthbar
					or (bossFrame and bossFrame.TargetFrameContent
						and bossFrame.TargetFrameContent.TargetFrameContentMain
						and bossFrame.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer
						and bossFrame.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer.HealthBar)
					or nil
			end

			-- Baselines for Boss name text are stored per-boss-index. Guard on every call:
			-- the style revert in base/core.lua nils this table out.
			local function ensureBossBaseline(fs, key, fallbackFrame)
				addon._ufNameLevelTextBaselines = addon._ufNameLevelTextBaselines or {}
				addon._ufNameLevelTextBaselines[key] = addon._ufNameLevelTextBaselines[key] or {}
				local b = addon._ufNameLevelTextBaselines[key]
				if b.point == nil then
					if fs and fs.GetPoint then
						local p, relTo, rp, x, y = fs:GetPoint(1)
						b.point = p or "CENTER"
						b.relTo = relTo or (fs.GetParent and fs:GetParent()) or fallbackFrame
						b.relPoint = rp or b.point
						b.x = safeOffset(x)
						b.y = safeOffset(y)
					else
						b.point, b.relTo, b.relPoint, b.x, b.y = "CENTER", (fallbackFrame or (fs and fs.GetParent and fs:GetParent())), "CENTER", 0, 0
					end
				end
				return b
			end

			local function applyBossTextStyle(fs, styleCfg, baselineKey, fallbackFrame)
				if not fs or not styleCfg then return end

				local function hasTextCustomization(cfgT)
					if not cfgT then return false end
					if cfgT.fontFace ~= nil and cfgT.fontFace ~= "" and cfgT.fontFace ~= "FRIZQT__" then return true end
					if cfgT.size ~= nil or cfgT.style ~= nil then return true end
					if cfgT.colorMode ~= nil and cfgT.colorMode ~= "" and cfgT.colorMode ~= "default" then return true end
					if cfgT.color ~= nil then return true end
					if cfgT.offset and (cfgT.offset.x ~= nil or cfgT.offset.y ~= nil) then
						local ox = tonumber(cfgT.offset.x) or 0
						local oy = tonumber(cfgT.offset.y) or 0
						if ox ~= 0 or oy ~= 0 then return true end
					end
					return false
				end
				if not hasTextCustomization(styleCfg) then return end

				local face = addon.ResolveFontFace(styleCfg.fontFace)
				local size = tonumber(styleCfg.size) or 14
				local outline = tostring(styleCfg.style or "OUTLINE")
				local fst = FS
				if fst then fst.SetProp(fs, "applyingFont", true) end
				if addon.ApplyFontStyle then addon.ApplyFontStyle(fs, face, size, outline) elseif fs.SetFont then pcall(fs.SetFont, fs, face, size, outline) end
				if fst then fst.SetProp(fs, "applyingFont", nil) end

				-- Boss frames: no class color option, and every mode renders the
				-- stored color, else the Name/Level Text default yellow
				local c = styleCfg.color or { 1.0, 0.82, 0.0, 1 }
				if fs.SetTextColor then pcall(fs.SetTextColor, fs, c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1) end

				local ox = (styleCfg.offset and tonumber(styleCfg.offset.x)) or 0
				local oy = (styleCfg.offset and tonumber(styleCfg.offset.y)) or 0
				if fs.ClearAllPoints and fs.SetPoint then
					local b = ensureBossBaseline(fs, baselineKey, fallbackFrame)
					fs:ClearAllPoints()
					local point = safePointToken(b.point, "CENTER")
					local relTo = b.relTo or (fs.GetParent and fs:GetParent()) or fallbackFrame
					local relPoint = safePointToken(b.relPoint, point)
					local x = safeOffset(b.x) + ox
					local y = safeOffset(b.y) + oy
					local ok = pcall(fs.SetPoint, fs, point, relTo, relPoint, x, y)
					if not ok then
						local parent = (fs.GetParent and fs:GetParent()) or fallbackFrame
						pcall(fs.SetPoint, fs, point, parent, relPoint, 0, 0)
					end
				end
			end

			local function applyBossNameContainerWidth(nameFS, styleCfg, bossIndex)
				if not nameFS or not styleCfg then return end
				if styleCfg.containerWidthPct == nil then return end

				local pct = tonumber(styleCfg.containerWidthPct) or 100
				if pct < 80 then pct = 80 elseif pct > 500 then pct = 500 end

				local key = "Boss" .. tostring(bossIndex) .. ":nameContainer"
				local baseline = addon._ufNameContainerBaselines[key]
				if not baseline then
					baseline = { width = safeGetWidth(nameFS) or 90 }
					addon._ufNameContainerBaselines[key] = baseline
				end

				local baseWidth = baseline.width or 90
				local newWidth = math.floor((baseWidth * pct / 100) + 0.5)

				if nameFS.SetWidth then
					nameFS:SetWidth(pct == 100 and baseWidth or newWidth)
				end

				local alignment = styleCfg.alignment or "LEFT"
				if nameFS.SetJustifyH then pcall(nameFS.SetJustifyH, nameFS, alignment) end

				if nameFS.GetText and nameFS.SetText then
					local txt = nameFS:GetText()
					if txt then nameFS:SetText(""); nameFS:SetText(txt) end
				end
			end

			local function applyBossBackdrop(main, hb, index)
				-- Reuse the same DB keys as other unit frames (nameBackdrop*).
				local holderKey = "ScootNameBackdrop_Boss" .. tostring(index)
				local mainState = getState(main)
				local existingTex = mainState and mainState[holderKey] or nil

				local configured = (
					cfg.nameBackdropEnabled ~= nil
					or cfg.nameBackdropTexture ~= nil
					or cfg.nameBackdropColorMode ~= nil
					or cfg.nameBackdropTint ~= nil
					or cfg.nameBackdropOpacity ~= nil
					or cfg.nameBackdropWidthPct ~= nil
				)
				if not configured then
					if existingTex then existingTex:Hide() end
					return
				end

				local texKey = cfg.nameBackdropTexture or ""
				local enabledBackdrop = not not cfg.nameBackdropEnabled
				local colorMode = cfg.nameBackdropColorMode or "default" -- default | texture | custom
				local tint = cfg.nameBackdropTint or { 1, 1, 1, 1 }
				local opacity = tonumber(cfg.nameBackdropOpacity) or 50
				if opacity < 0 then opacity = 0 elseif opacity > 100 then opacity = 100 end
				local opacityAlpha = opacity / 100
				local resolvedPath = addon.Media and addon.Media.ResolveBarTexturePath and addon.Media.ResolveBarTexturePath(texKey)

				local tex = existingTex
				if main and not tex then
					tex = main:CreateTexture(nil, "BACKGROUND", nil, -8)
					if mainState then mainState[holderKey] = tex end
				end
				if not tex then return end

				if hb and resolvedPath and enabledBackdrop then
					addon._ufNameBackdropBaseWidth = addon._ufNameBackdropBaseWidth or {}
					local baseKey = "Boss" .. tostring(index)
					local base = tonumber(addon._ufNameBackdropBaseWidth[baseKey])
					if not base or base <= 0 then
						base = safeGetWidth(hb)
						if base and base > 0 then
							addon._ufNameBackdropBaseWidth[baseKey] = base
						end
					end
					-- If the width can't be safely read (secret-value environment), skip cosmetics.
					if not base or base <= 0 then
						tex:Hide()
						return
					end
					local wPct = tonumber(cfg.nameBackdropWidthPct) or 100
					if wPct < 25 then wPct = 25 elseif wPct > 300 then wPct = 300 end
					local desiredWidth = math.max(1, math.floor((base * wPct / 100) + 0.5))

					tex:ClearAllPoints()
					-- Boss frames align right; grow left from the portrait side (match Target/Focus behavior).
					tex:SetPoint("BOTTOMRIGHT", hb, "TOPRIGHT", 0, 0)
					tex:SetSize(desiredWidth, 16)
					tex:SetTexture(resolvedPath)
					if tex.SetDrawLayer then tex:SetDrawLayer("BACKGROUND", -8) end
					if tex.SetHorizTile then tex:SetHorizTile(false) end
					if tex.SetVertTile then tex:SetVertTile(false) end
					if tex.SetTexCoord then tex:SetTexCoord(0, 1, 0, 1) end

					local r, g, b = 1, 1, 1
					if colorMode == "texture" then
						r, g, b = 1, 1, 1
					elseif colorMode == "default" then
						r, g, b = 0, 0, 0
					elseif colorMode == "custom" and type(tint) == "table" then
						r, g, b = tint[1] or 1, tint[2] or 1, tint[3] or 1
					end
					if tex.SetVertexColor then tex:SetVertexColor(r, g, b, 1) end
					if tex.SetAlpha then tex:SetAlpha(opacityAlpha) end
					tex:Show()
				else
					tex:Hide()
				end
			end

			local function applyBossBackdropBorder(main, hb, index)
				local borderKey = "ScootNameBackdropBorder_Boss" .. tostring(index)
				local mainState = getState(main)
				local existingBorderFrame = mainState and mainState[borderKey] or nil

				local configured = (
					cfg.nameBackdropBorderEnabled ~= nil
					or cfg.nameBackdropBorderStyle ~= nil
					or cfg.nameBackdropBorderThickness ~= nil
					or cfg.nameBackdropBorderInset ~= nil
					or cfg.nameBackdropBorderInsetH ~= nil
					or cfg.nameBackdropBorderInsetV ~= nil
					or cfg.nameBackdropBorderTintEnable ~= nil
					or cfg.nameBackdropBorderTintColor ~= nil
					or cfg.nameBackdropBorderHiddenEdges ~= nil
					or cfg.useCustomBorders ~= nil
					or cfg.nameBackdropEnabled ~= nil
					or cfg.nameBackdropTexture ~= nil
					or cfg.nameBackdropWidthPct ~= nil
				)
				if not configured then
					if existingBorderFrame then
						if addon.Borders and addon.Borders.HideAll then addon.Borders.HideAll(existingBorderFrame) end
						if existingBorderFrame.SetBackdrop then pcall(existingBorderFrame.SetBackdrop, existingBorderFrame, nil) end
						existingBorderFrame:Hide()
					end
					return
				end

				local styleKey = cfg.nameBackdropBorderStyle or "square"
				local hiddenEdges = cfg.nameBackdropBorderHiddenEdges
				local localEnabled = not not cfg.nameBackdropBorderEnabled
				local globalEnabled = not not cfg.useCustomBorders
				local useBorders = localEnabled and globalEnabled
				local thickness = tonumber(cfg.nameBackdropBorderThickness) or 1
				if thickness < 1 then thickness = 1 elseif thickness > 16 then thickness = 16 end
				local insetH = tonumber(cfg.nameBackdropBorderInsetH) or tonumber(cfg.nameBackdropBorderInset) or 0
				local insetV = tonumber(cfg.nameBackdropBorderInsetV) or tonumber(cfg.nameBackdropBorderInset) or 0
				if insetH < -8 then insetH = -8 elseif insetH > 8 then insetH = 8 end
				if insetV < -8 then insetV = -8 elseif insetV > 8 then insetV = 8 end
				local tintEnabled = not not cfg.nameBackdropBorderTintEnable
				local tintColor = cfg.nameBackdropBorderTintColor or { 1, 1, 1, 1 }

				local borderFrame = existingBorderFrame
				if main and not borderFrame then
					local template = BackdropTemplateMixin and "BackdropTemplate" or nil
					borderFrame = CreateFrame("Frame", nil, main, template)
					if mainState then mainState[borderKey] = borderFrame end
				end
				if not borderFrame then return end

				if hb and useBorders then
					addon._ufNameBackdropBaseWidth = addon._ufNameBackdropBaseWidth or {}
					local baseKey = "Boss" .. tostring(index)
					local base = tonumber(addon._ufNameBackdropBaseWidth[baseKey])
					if not base or base <= 0 then
						base = safeGetWidth(hb)
						if base and base > 0 then
							addon._ufNameBackdropBaseWidth[baseKey] = base
						end
					end
					-- If the width can't be safely read (secret-value environment), skip cosmetics.
					if not base or base <= 0 then
						borderFrame:Hide()
						return
					end
					local wPct = tonumber(cfg.nameBackdropWidthPct) or 100
					if wPct < 25 then wPct = 25 elseif wPct > 300 then wPct = 300 end
					local desiredWidth = math.max(1, math.floor((base * wPct / 100) + 0.5))

					borderFrame:ClearAllPoints()
					borderFrame:SetPoint("BOTTOMRIGHT", hb, "TOPRIGHT", 0, 0)
					borderFrame:SetSize(desiredWidth, 16)

					local styleDef = addon.BarBorders and addon.BarBorders.GetStyle and addon.BarBorders.GetStyle(styleKey) or nil
					local styleTexture = styleDef and styleDef.texture or nil
					local thicknessScale = (styleDef and styleDef.thicknessScale) or 1.0
					local DEFAULT_REF = 18
					local DEFAULT_MULT = 1.35
					local h = (borderFrame.GetHeight and borderFrame:GetHeight()) or 16
					if h < 1 then h = DEFAULT_REF end
					local edgeSize = math.floor((thickness * DEFAULT_MULT * thicknessScale * (h / DEFAULT_REF)) + 0.5)
					if edgeSize < 1 then edgeSize = 1 elseif edgeSize > 48 then edgeSize = 48 end

					if styleKey == "square" or not styleTexture then
						if borderFrame.SetBackdrop then pcall(borderFrame.SetBackdrop, borderFrame, nil) end
						if addon.Borders and addon.Borders.HideAll then addon.Borders.HideAll(borderFrame) end
						if addon.Borders and addon.Borders.ApplySquare then
							addon.Borders.ApplySquare(borderFrame, {
								size = edgeSize,
								color = tintEnabled and (tintColor or { 1, 1, 1, 1 }) or { 1, 1, 1, 1 },
								layer = "OVERLAY",
								layerSublevel = 7,
								expandX = -(insetH),
								expandY = -(insetV),
								hiddenEdges = hiddenEdges,
							})
						end
						borderFrame:Show()
					else
						if addon.Borders and addon.Borders.HideAll then addon.Borders.HideAll(borderFrame) end
						local ok = false
						if borderFrame.SetBackdrop then
							local insetPxH = math.max(0, math.floor(edgeSize * 0.65 + 0.5) + insetH)
							local insetPxV = math.max(0, math.floor(edgeSize * 0.65 + 0.5) + insetV)
							local bd = {
								bgFile = nil,
								edgeFile = styleTexture,
								tile = false,
								edgeSize = edgeSize,
								insets = { left = insetPxH, right = insetPxH, top = insetPxV, bottom = insetPxV },
							}
							ok = pcall(borderFrame.SetBackdrop, borderFrame, bd)
						end
						if ok and borderFrame.SetBackdropBorderColor then
							local c = tintEnabled and tintColor or { 1, 1, 1, 1 }
							borderFrame:SetBackdropBorderColor(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
						end
						if not ok then
							borderFrame:Hide()
						else
							borderFrame:Show()
							if hiddenEdges and (hiddenEdges.top or hiddenEdges.bottom or hiddenEdges.left or hiddenEdges.right) then
								if hiddenEdges.top and borderFrame.TopEdge then borderFrame.TopEdge:Hide() end
								if hiddenEdges.bottom and borderFrame.BottomEdge then borderFrame.BottomEdge:Hide() end
								if hiddenEdges.left and borderFrame.LeftEdge then borderFrame.LeftEdge:Hide() end
								if hiddenEdges.right and borderFrame.RightEdge then borderFrame.RightEdge:Hide() end
								if borderFrame.TopLeftCorner and (hiddenEdges.top or hiddenEdges.left) then borderFrame.TopLeftCorner:Hide() end
								if borderFrame.TopRightCorner and (hiddenEdges.top or hiddenEdges.right) then borderFrame.TopRightCorner:Hide() end
								if borderFrame.BottomLeftCorner and (hiddenEdges.bottom or hiddenEdges.left) then borderFrame.BottomLeftCorner:Hide() end
								if borderFrame.BottomRightCorner and (hiddenEdges.bottom or hiddenEdges.right) then borderFrame.BottomRightCorner:Hide() end
							end
						end
					end
				else
					if addon.Borders and addon.Borders.HideAll then addon.Borders.HideAll(borderFrame) end
					if borderFrame.SetBackdrop then pcall(borderFrame.SetBackdrop, borderFrame, nil) end
					borderFrame:Hide()
				end
			end

			local function applyBossIndex(i)
				local bossFrame = resolveBossFrame(i)
				if not bossFrame then return end

				local nameFS = resolveBossNameFS(bossFrame)
				local main = resolveBossContentMain(bossFrame)
				local hb = resolveBossHealthBar(bossFrame)

				-- Visibility: name text is not a StatusBar child, so SetShown is safe.
				if nameFS and nameFS.SetShown and cfg.nameTextHidden ~= nil then
					pcall(nameFS.SetShown, nameFS, not cfg.nameTextHidden)
				end

				if nameFS then
					applyBossTextStyle(nameFS, cfg.textName or {}, "Boss" .. tostring(i) .. ":name", bossFrame)
					applyBossNameContainerWidth(nameFS, cfg.textName or {}, i)
				end

				-- Level text
				local levelFS = resolveBossLevelFS(bossFrame)
				if levelFS and levelFS.SetShown and cfg.levelTextHidden ~= nil then
					pcall(levelFS.SetShown, levelFS, not cfg.levelTextHidden)
				end
				if levelFS then
					applyBossTextStyle(levelFS, cfg.textLevel or {}, "Boss" .. tostring(i) .. ":level", bossFrame)
				end

				-- Backdrop + Border: attach to the same content main frame as Target/Focus.
				if main then
					applyBossBackdrop(main, hb, i)
					applyBossBackdropBorder(main, hb, i)
				end

				-- Persistence hooks (Boss frames can refresh/overwrite text props).
				local bossState = getState(bossFrame)
				if _G.hooksecurefunc and bossState and not bossState.bossNameTextHooked then
					bossState.bossNameTextHooked = true
					local function safeReapply()
						-- Throttle per-frame to avoid rapid spam from Update/OnShow.
						if bossState.bossNameTextReapplyPending then return end
						bossState.bossNameTextReapplyPending = true
						if _G.C_Timer and _G.C_Timer.After then
							_G.C_Timer.After(0, function()
								bossState.bossNameTextReapplyPending = nil
								applyBossIndex(i)
							end)
						else
							bossState.bossNameTextReapplyPending = nil
							applyBossIndex(i)
						end
					end
					if type(bossFrame.Update) == "function" then
						_G.hooksecurefunc(bossFrame, "Update", safeReapply)
					end
					if type(bossFrame.OnShow) == "function" then
						_G.hooksecurefunc(bossFrame, "OnShow", safeReapply)
					end
				end
			end

			for i = 1, addon.NUM_BOSS_FRAMES do
				applyBossIndex(i)
			end
			return
		end

		local frame = getUnitFrameFor(unit)
		if not frame then return end

		-- Resolve Name and Level FontStrings
		local nameFS, levelFS
		
	-- Try direct child access first (most common)
	if unit == "Player" then
		nameFS = _G.PlayerName
		levelFS = _G.PlayerLevelText
	elseif unit == "Target" then
		-- Target uses nested content structure
		local targetFrame = _G.TargetFrame
		if targetFrame and targetFrame.TargetFrameContent and targetFrame.TargetFrameContent.TargetFrameContentMain then
			nameFS = targetFrame.TargetFrameContent.TargetFrameContentMain.Name
			levelFS = targetFrame.TargetFrameContent.TargetFrameContentMain.LevelText
		end
	elseif unit == "Focus" then
		-- Focus reuses Target's content structure naming (TargetFrameContent, not FocusFrameContent!)
		local focusFrame = _G.FocusFrame
		if focusFrame and focusFrame.TargetFrameContent and focusFrame.TargetFrameContent.TargetFrameContentMain then
			nameFS = focusFrame.TargetFrameContent.TargetFrameContentMain.Name
			levelFS = focusFrame.TargetFrameContent.TargetFrameContentMain.LevelText
		end
	elseif unit == "Pet" then
		-- Pet uses global FontString names (PetName is a direct global, not nested)
		nameFS = _G.PetName
		-- Pet frame doesn't have a LevelText FontString (no level display)
		levelFS = nil
	end

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

			-- Helper to force FontString redraw after alignment change
			local function forceTextRedraw(fs)
				if fs and fs.GetText and fs.SetText then
					local txt = fs:GetText()
					if txt then
						fs:SetText("")
						fs:SetText(txt)
					end
				end
			end

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
			local main = resolveUFContentMain_NLT(unitKey)
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

	local function applyTextStyle(fs, styleCfg, baselineKey)
		if not fs or not styleCfg then return end
		-- Default/clean profiles should not modify Blizzard text.
		-- Only treat settings as "customized" if they differ from structural defaults.
		local function hasTextCustomization(cfgT)
			if not cfgT then return false end
			if cfgT.fontFace ~= nil and cfgT.fontFace ~= "" and cfgT.fontFace ~= "FRIZQT__" then
				return true
			end
			if cfgT.size ~= nil or cfgT.style ~= nil then
				return true
			end
			-- Name/Level uses colorMode; only treat as customized if not default.
			if cfgT.colorMode ~= nil and cfgT.colorMode ~= "" and cfgT.colorMode ~= "default" then
				return true
			end
			if cfgT.color ~= nil then
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
		local face = addon.ResolveFontFace(styleCfg.fontFace)
		local size = tonumber(styleCfg.size) or 14
		local outline = tostring(styleCfg.style or "OUTLINE")
		-- Set flag to prevent the SetFont hook from triggering a reapply loop
		local fst = FS
		if fst then fst.SetProp(fs, "applyingFont", true) end
		if addon.ApplyFontStyle then addon.ApplyFontStyle(fs, face, size, outline) elseif fs.SetFont then pcall(fs.SetFont, fs, face, size, outline) end
		if fst then fst.SetProp(fs, "applyingFont", nil) end
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
		-- Name Backdrop: texture strip anchored to top edge of the Health Bar at the lowest z-order
		do
			local main = resolveUFContentMain_NLT(unit)
			local hb = resolveHealthBar_NLT(unit)
			local holderKey = "ScootNameBackdrop_" .. tostring(unit)
			local mainState = getState(main)
			local existingTex = mainState and mainState[holderKey] or nil

			-- Zero‑Touch: only create/manage the backdrop texture when this feature has been configured.
			local configured = (
				cfg.nameBackdropEnabled ~= nil
				or cfg.nameBackdropTexture ~= nil
				or cfg.nameBackdropColorMode ~= nil
				or cfg.nameBackdropTint ~= nil
				or cfg.nameBackdropOpacity ~= nil
				or cfg.nameBackdropWidthPct ~= nil
			)
			if not configured then
				-- If the texture exists from earlier in this session/profile, hide it.
				if existingTex then existingTex:Hide() end
			else
			local texKey = cfg.nameBackdropTexture or ""
			-- Default to disabled backdrop unless explicitly enabled in the profile.
			local enabledBackdrop = not not cfg.nameBackdropEnabled
			local colorMode = cfg.nameBackdropColorMode or "default" -- default | texture | custom
			local tint = cfg.nameBackdropTint or {1,1,1,1}
			local opacity = tonumber(cfg.nameBackdropOpacity) or 50
			if opacity < 0 then opacity = 0 elseif opacity > 100 then opacity = 100 end
			local opacityAlpha = opacity / 100
			local resolvedPath = addon.Media and addon.Media.ResolveBarTexturePath and addon.Media.ResolveBarTexturePath(texKey)
			local tex = existingTex
			if main and not tex then
				tex = main:CreateTexture(nil, "BACKGROUND", nil, -8)
				if mainState then mainState[holderKey] = tex end
			end
			if tex then
				if hb and resolvedPath and enabledBackdrop then
					-- Compute a baseline width per-session (do NOT persist baselines into SavedVariables).
					addon._ufNameBackdropBaseWidth = addon._ufNameBackdropBaseWidth or {}
					local base = tonumber(addon._ufNameBackdropBaseWidth[unit])
					if not base or base <= 0 then
						base = safeGetWidth(hb)
						if base and base > 0 then
							addon._ufNameBackdropBaseWidth[unit] = base
						end
					end
					-- If the width can't be safely read (secret-value environment), skip cosmetics.
					if not base or base <= 0 then
						tex:Hide()
						return
					end
					local wPct = tonumber(cfg.nameBackdropWidthPct) or 100
					if wPct < 25 then wPct = 25 elseif wPct > 300 then wPct = 300 end
					local desiredWidth = math.max(1, math.floor((base * wPct / 100) + 0.5))
					tex:ClearAllPoints()
					-- Anchor to RIGHT edge for Target/Focus so the strip grows left from the portrait side
					if unit == "Target" or unit == "Focus" then
						tex:SetPoint("BOTTOMRIGHT", hb, "TOPRIGHT", 0, 0)
					else
						tex:SetPoint("BOTTOMLEFT", hb, "TOPLEFT", 0, 0)
					end
					tex:SetSize(desiredWidth, 16)
					tex:SetTexture(resolvedPath)
					if tex.SetDrawLayer then tex:SetDrawLayer("BACKGROUND", -8) end
					if tex.SetHorizTile then tex:SetHorizTile(false) end
					if tex.SetVertTile then tex:SetVertTile(false) end
					if tex.SetTexCoord then tex:SetTexCoord(0,1,0,1) end
					-- Color behavior mirrors bar backgrounds:
					--  - texture  => preserve original colors (white vertex)
					--  - default  => use default background color (black)
					--  - custom   => use tint (including alpha)
					do
						local r, g, b = 1, 1, 1
						if colorMode == "texture" then
							r, g, b = 1, 1, 1
						elseif colorMode == "default" then
							-- Unit frame default background is black
							r, g, b = 0, 0, 0
						elseif colorMode == "custom" and type(tint) == "table" then
							r, g, b = tint[1] or 1, tint[2] or 1, tint[3] or 1
						end
						if tex.SetVertexColor then tex:SetVertexColor(r, g, b, 1) end
						if tex.SetAlpha then tex:SetAlpha(opacityAlpha) end
					end
					tex:Show()
				else
					tex:Hide()
				end
			end
			end -- configured
		end
		-- Name Backdrop Border: draw a border around the same region
		do
			local main = resolveUFContentMain_NLT(unit)
			local hb = resolveHealthBar_NLT(unit)
			local borderKey = "ScootNameBackdropBorder_" .. tostring(unit)
			local mainState = getState(main)
			local existingBorderFrame = mainState and mainState[borderKey] or nil

			-- Zero‑Touch: only create/manage the border when this feature has been configured.
			local configured = (
				cfg.nameBackdropBorderEnabled ~= nil
				or cfg.nameBackdropBorderStyle ~= nil
				or cfg.nameBackdropBorderThickness ~= nil
				or cfg.nameBackdropBorderInset ~= nil
				or cfg.nameBackdropBorderInsetH ~= nil
				or cfg.nameBackdropBorderInsetV ~= nil
				or cfg.nameBackdropBorderTintEnable ~= nil
				or cfg.nameBackdropBorderTintColor ~= nil
				or cfg.nameBackdropBorderHiddenEdges ~= nil
				or cfg.useCustomBorders ~= nil
				or cfg.nameBackdropEnabled ~= nil
				or cfg.nameBackdropTexture ~= nil
				or cfg.nameBackdropWidthPct ~= nil
			)
			if not configured then
				-- If the border frame exists from earlier in this session/profile, hide and clear it.
				if existingBorderFrame then
					if addon.Borders and addon.Borders.HideAll then addon.Borders.HideAll(existingBorderFrame) end
					if existingBorderFrame.SetBackdrop then pcall(existingBorderFrame.SetBackdrop, existingBorderFrame, nil) end
					existingBorderFrame:Hide()
				end
			else
			local styleKey = cfg.nameBackdropBorderStyle or "square"
			local hiddenEdges = cfg.nameBackdropBorderHiddenEdges
			-- Align border gating with UI defaults: disabled until explicitly enabled.
			local localEnabled = not not cfg.nameBackdropBorderEnabled
			local globalEnabled = not not cfg.useCustomBorders
			local useBorders = localEnabled and globalEnabled
			local thickness = tonumber(cfg.nameBackdropBorderThickness) or 1
			if thickness < 1 then thickness = 1 elseif thickness > 16 then thickness = 16 end
			local insetH = tonumber(cfg.nameBackdropBorderInsetH) or tonumber(cfg.nameBackdropBorderInset) or 0
			local insetV = tonumber(cfg.nameBackdropBorderInsetV) or tonumber(cfg.nameBackdropBorderInset) or 0
			if insetH < -8 then insetH = -8 elseif insetH > 8 then insetH = 8 end
			if insetV < -8 then insetV = -8 elseif insetV > 8 then insetV = 8 end
			local tintEnabled = not not cfg.nameBackdropBorderTintEnable
			local tintColor = cfg.nameBackdropBorderTintColor or {1,1,1,1}

			local borderFrame = existingBorderFrame
			if main and not borderFrame then
				local template = BackdropTemplateMixin and "BackdropTemplate" or nil
				borderFrame = CreateFrame("Frame", nil, main, template)
				if mainState then mainState[borderKey] = borderFrame end
			end
			if borderFrame and hb and useBorders then
				-- Match border width to the same baseline-derived width as backdrop
				addon._ufNameBackdropBaseWidth = addon._ufNameBackdropBaseWidth or {}
				local base = tonumber(addon._ufNameBackdropBaseWidth[unit])
				if not base or base <= 0 then
					base = safeGetWidth(hb)
					if base and base > 0 then
						addon._ufNameBackdropBaseWidth[unit] = base
					end
				end
				-- If the width can't be safely read (secret-value environment), skip cosmetics.
				if not base or base <= 0 then
					borderFrame:Hide()
					return
				end
				local wPct = tonumber(cfg.nameBackdropWidthPct) or 100
				if wPct < 25 then wPct = 25 elseif wPct > 300 then wPct = 300 end
				local desiredWidth = math.max(1, math.floor((base * wPct / 100) + 0.5))
				borderFrame:ClearAllPoints()
				-- Anchor to RIGHT edge for Target/Focus so the border grows left from the portrait side
				if unit == "Target" or unit == "Focus" then
					borderFrame:SetPoint("BOTTOMRIGHT", hb, "TOPRIGHT", 0, 0)
				else
					borderFrame:SetPoint("BOTTOMLEFT", hb, "TOPLEFT", 0, 0)
				end
				borderFrame:SetSize(desiredWidth, 16)
				local styleDef = addon.BarBorders and addon.BarBorders.GetStyle and addon.BarBorders.GetStyle(styleKey) or nil
				local styleTexture = styleDef and styleDef.texture or nil
				local thicknessScale = (styleDef and styleDef.thicknessScale) or 1.0
				local DEFAULT_REF = 18
				local DEFAULT_MULT = 1.35
				local h = (borderFrame.GetHeight and borderFrame:GetHeight()) or 16
				if h < 1 then h = DEFAULT_REF end
				local edgeSize = math.floor((thickness * DEFAULT_MULT * thicknessScale * (h / DEFAULT_REF)) + 0.5)
				if edgeSize < 1 then edgeSize = 1 elseif edgeSize > 48 then edgeSize = 48 end

				if styleKey == "square" or not styleTexture then
					-- Clear any previous backdrop-based border before applying square edges
					if borderFrame.SetBackdrop then pcall(borderFrame.SetBackdrop, borderFrame, nil) end
					if addon.Borders and addon.Borders.HideAll then addon.Borders.HideAll(borderFrame) end
					if addon.Borders and addon.Borders.ApplySquare then
						addon.Borders.ApplySquare(borderFrame, {
							size = edgeSize,
							color = tintEnabled and (tintColor or {1,1,1,1}) or {1,1,1,1},
							layer = "OVERLAY",
							layerSublevel = 7,
							expandX = -(insetH),
							expandY = -(insetV),
							hiddenEdges = hiddenEdges,
						})
					end
					borderFrame:Show()
				else
					-- Clear any previous square edges before applying a backdrop-based border
					if addon.Borders and addon.Borders.HideAll then addon.Borders.HideAll(borderFrame) end
					local ok = false
					if borderFrame.SetBackdrop then
						local insetPxH = math.max(0, math.floor(edgeSize * 0.65 + 0.5) + insetH)
						local insetPxV = math.max(0, math.floor(edgeSize * 0.65 + 0.5) + insetV)
						local bd = {
							bgFile = nil,
							edgeFile = styleTexture,
							tile = false,
							edgeSize = edgeSize,
							insets = { left = insetPxH, right = insetPxH, top = insetPxV, bottom = insetPxV },
						}
						ok = pcall(borderFrame.SetBackdrop, borderFrame, bd)
					end
					if ok and borderFrame.SetBackdropBorderColor then
						local c = tintEnabled and tintColor or {1,1,1,1}
						borderFrame:SetBackdropBorderColor(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
					end
					if not ok then
						borderFrame:Hide()
					else
						borderFrame:Show()
						if hiddenEdges and (hiddenEdges.top or hiddenEdges.bottom or hiddenEdges.left or hiddenEdges.right) then
							if hiddenEdges.top and borderFrame.TopEdge then borderFrame.TopEdge:Hide() end
							if hiddenEdges.bottom and borderFrame.BottomEdge then borderFrame.BottomEdge:Hide() end
							if hiddenEdges.left and borderFrame.LeftEdge then borderFrame.LeftEdge:Hide() end
							if hiddenEdges.right and borderFrame.RightEdge then borderFrame.RightEdge:Hide() end
							if borderFrame.TopLeftCorner and (hiddenEdges.top or hiddenEdges.left) then borderFrame.TopLeftCorner:Hide() end
							if borderFrame.TopRightCorner and (hiddenEdges.top or hiddenEdges.right) then borderFrame.TopRightCorner:Hide() end
							if borderFrame.BottomLeftCorner and (hiddenEdges.bottom or hiddenEdges.left) then borderFrame.BottomLeftCorner:Hide() end
							if borderFrame.BottomRightCorner and (hiddenEdges.bottom or hiddenEdges.right) then borderFrame.BottomRightCorner:Hide() end
						end
					end
				end
			elseif borderFrame then
				-- Fully clear both border types on disable
				if addon.Borders and addon.Borders.HideAll then addon.Borders.HideAll(borderFrame) end
				if borderFrame.SetBackdrop then pcall(borderFrame.SetBackdrop, borderFrame, nil) end
				borderFrame:Hide()
			end
			end -- configured
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

do
	-- Resolve ToT Name FontString
	local function resolveToTNameFS()
		local tot = _G.TargetFrameToT
		return tot and tot.Name or nil
	end

	-- Baseline storage for ToT Name text
	addon._ufToTNameTextBaseline = addon._ufToTNameTextBaseline or {}

	-- Apply ToT Name Text styling
	local function applyToTNameText()
		local db = addon and addon.db and addon.db.profile
		if not db then return end
		-- Zero‑Touch: do not create config tables. If ToT has no config, do nothing.
		local unitFrames = rawget(db, "unitFrames")
		local cfg = unitFrames and rawget(unitFrames, "TargetOfTarget") or nil
		if not cfg then return end
		local styleCfg = rawget(cfg, "textName")

		local nameFS = resolveToTNameFS()
		if not nameFS then return end

		-- Zero‑Touch: if neither visibility nor style is configured, do nothing.
		local function hasAnyOffset(tbl)
			local off = tbl and tbl.offset
			return off and (off.x ~= nil or off.y ~= nil) or false
		end
		local function hasTextCustomization(tbl)
			if not tbl then return false end
			if tbl.fontFace ~= nil and tbl.fontFace ~= "" and tbl.fontFace ~= "FRIZQT__" then return true end
			if tbl.size ~= nil or tbl.style ~= nil or tbl.colorMode ~= nil or tbl.color ~= nil or tbl.alignment ~= nil then return true end
			if hasAnyOffset(tbl) then return true end
			return false
		end
		local hasVisibilitySetting = (cfg.nameTextHidden ~= nil)
		local hasStyleSetting = hasTextCustomization(styleCfg)
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
				fstate.SetHidden(nameFS, "totName", true)
				-- Install hook to re-enforce hidden state
				if not fstate.IsHooked(nameFS, "totNameVisibility") then
					fstate.MarkHooked(nameFS, "totNameVisibility")
					if _G.hooksecurefunc then
						_G.hooksecurefunc(nameFS, "SetText", function(self)
							local st = FS
							if st and st.IsHidden(self, "totName") and self.SetAlpha then
								pcall(self.SetAlpha, self, 0)
							end
						end)
						_G.hooksecurefunc(nameFS, "Show", function(self)
							local st = FS
							if st and st.IsHidden(self, "totName") and self.SetAlpha then
								pcall(self.SetAlpha, self, 0)
							end
						end)
					end
				end
			else
				fstate.SetHidden(nameFS, "totName", false)
				if nameFS.SetAlpha then pcall(nameFS.SetAlpha, nameFS, 1) end
			end
		end

		-- Skip styling if hidden
		if cfg.nameTextHidden == true then return end
		-- Zero‑Touch: only apply font/position/style if explicitly customized.
		if not hasStyleSetting then
			return
		end

		-- Capture baseline position once
		local function ensureBaseline()
			if not addon._ufToTNameTextBaseline.point then
				if nameFS and nameFS.GetPoint then
					local p, relTo, rp, x, y = nameFS:GetPoint(1)
					addon._ufToTNameTextBaseline.point = p or "TOPLEFT"
					addon._ufToTNameTextBaseline.relTo = relTo or (nameFS.GetParent and nameFS:GetParent())
					addon._ufToTNameTextBaseline.relPoint = rp or addon._ufToTNameTextBaseline.point
					addon._ufToTNameTextBaseline.x = safeOffset(x)
					addon._ufToTNameTextBaseline.y = safeOffset(y)
				else
					addon._ufToTNameTextBaseline.point = "TOPLEFT"
					addon._ufToTNameTextBaseline.relTo = nameFS and nameFS.GetParent and nameFS:GetParent()
					addon._ufToTNameTextBaseline.relPoint = "TOPLEFT"
					addon._ufToTNameTextBaseline.x = 0
					addon._ufToTNameTextBaseline.y = 0
				end
			end
			return addon._ufToTNameTextBaseline
		end

		-- Apply font styling
		local face = addon.ResolveFontFace(styleCfg and styleCfg.fontFace)
		local size = tonumber(styleCfg and styleCfg.size) or 10
		local outline = tostring((styleCfg and styleCfg.style) or "OUTLINE")
		if addon.ApplyFontStyle then
			addon.ApplyFontStyle(nameFS, face, size, outline)
		elseif nameFS.SetFont then
			pcall(nameFS.SetFont, nameFS, face, size, outline)
		end

		-- Apply color based on colorMode (no barKind: ToT name default is white)
		local colorMode = (styleCfg and styleCfg.colorMode) or "default"
		nameTextColorOpts.unitForClass = "targettarget"
		local r, g, b, a = addon.ResolveColorRGBA(colorMode, styleCfg and styleCfg.color, nameTextColorOpts)
		if nameFS.SetTextColor then pcall(nameFS.SetTextColor, nameFS, r, g, b, a) end

		-- Apply alignment
		local alignment = (styleCfg and styleCfg.alignment) or "LEFT"
		if nameFS.SetJustifyH then pcall(nameFS.SetJustifyH, nameFS, alignment) end

		-- Apply offset relative to baseline
		local ox = tonumber(styleCfg and styleCfg.offset and styleCfg.offset.x) or 0
		local oy = tonumber(styleCfg and styleCfg.offset and styleCfg.offset.y) or 0
		if nameFS.ClearAllPoints and nameFS.SetPoint then
			local b = ensureBaseline()
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
	addon.ApplyToTNameText = applyToTNameText

	-- Hook TargetofTarget frame updates to reapply styling
	-- ToT frame is re-shown when target changes, so hook the ToT OnShow
	-- NOTE: Uses FrameState to avoid writing properties directly to Blizzard frames (causes taint).
	local function installToTHooks()
		local fstate = FS
		if not fstate then return end
		local tot = _G.TargetFrameToT
		if tot and not fstate.IsHooked(tot, "nameTextHooked") then
			fstate.MarkHooked(tot, "nameTextHooked")
			if tot.HookScript then
				tot:HookScript("OnShow", function()
					if _G.C_Timer and _G.C_Timer.After then
						_G.C_Timer.After(0, applyToTNameText)
					end
				end)
			end
		end
	end

	-- Install hooks after PLAYER_ENTERING_WORLD
	addon.Events.On("UnitFrames:Names", "PLAYER_ENTERING_WORLD", function()
		if _G.C_Timer and _G.C_Timer.After then
			_G.C_Timer.After(0.5, function()
				installToTHooks()
				-- Apply initial styling
				applyToTNameText()
			end)
		end
	end)
end

do
	local function resolveFoTNameFS()
		local fot = _G.FocusFrameToT
		return fot and fot.Name or nil
	end

	addon._ufFoTNameTextBaseline = addon._ufFoTNameTextBaseline or {}

	local function applyFoTNameText()
		local db = addon and addon.db and addon.db.profile
		if not db then return end
		local unitFrames = rawget(db, "unitFrames")
		local cfg = unitFrames and rawget(unitFrames, "FocusTarget") or nil
		if not cfg then return end
		local styleCfg = rawget(cfg, "textName")

		local nameFS = resolveFoTNameFS()
		if not nameFS then return end

		-- Zero‑Touch: if neither visibility nor style is configured, do nothing.
		local function hasAnyOffset(tbl)
			local off = tbl and tbl.offset
			return off and (off.x ~= nil or off.y ~= nil) or false
		end
		local function hasTextCustomization(tbl)
			if not tbl then return false end
			if tbl.fontFace ~= nil and tbl.fontFace ~= "" and tbl.fontFace ~= "FRIZQT__" then return true end
			if tbl.size ~= nil or tbl.style ~= nil or tbl.colorMode ~= nil or tbl.color ~= nil or tbl.alignment ~= nil then return true end
			if hasAnyOffset(tbl) then return true end
			return false
		end
		local hasVisibilitySetting = (cfg.nameTextHidden ~= nil)
		local hasStyleSetting = hasTextCustomization(styleCfg)
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
				fstate.SetHidden(nameFS, "fotName", true)
				-- Install hook to re-enforce hidden state
				if not fstate.IsHooked(nameFS, "fotNameVisibility") then
					fstate.MarkHooked(nameFS, "fotNameVisibility")
					if _G.hooksecurefunc then
						_G.hooksecurefunc(nameFS, "SetText", function(self)
							local st = FS
							if st and st.IsHidden(self, "fotName") and self.SetAlpha then
								pcall(self.SetAlpha, self, 0)
							end
						end)
						_G.hooksecurefunc(nameFS, "Show", function(self)
							local st = FS
							if st and st.IsHidden(self, "fotName") and self.SetAlpha then
								pcall(self.SetAlpha, self, 0)
							end
						end)
					end
				end
			else
				fstate.SetHidden(nameFS, "fotName", false)
				if nameFS.SetAlpha then pcall(nameFS.SetAlpha, nameFS, 1) end
			end
		end

		-- Skip styling if hidden
		if cfg.nameTextHidden == true then return end
		-- Zero‑Touch: only apply font/position/style if explicitly customized.
		if not hasStyleSetting then
			return
		end

		-- Capture baseline position once
		local function ensureBaseline()
			if not addon._ufFoTNameTextBaseline.point then
				if nameFS and nameFS.GetPoint then
					local p, relTo, rp, x, y = nameFS:GetPoint(1)
					addon._ufFoTNameTextBaseline.point = p or "TOPLEFT"
					addon._ufFoTNameTextBaseline.relTo = relTo or (nameFS.GetParent and nameFS:GetParent())
					addon._ufFoTNameTextBaseline.relPoint = rp or addon._ufFoTNameTextBaseline.point
					addon._ufFoTNameTextBaseline.x = safeOffset(x)
					addon._ufFoTNameTextBaseline.y = safeOffset(y)
				else
					addon._ufFoTNameTextBaseline.point = "TOPLEFT"
					addon._ufFoTNameTextBaseline.relTo = nameFS and nameFS.GetParent and nameFS:GetParent()
					addon._ufFoTNameTextBaseline.relPoint = "TOPLEFT"
					addon._ufFoTNameTextBaseline.x = 0
					addon._ufFoTNameTextBaseline.y = 0
				end
			end
			return addon._ufFoTNameTextBaseline
		end

		-- Apply font styling
		local face = addon.ResolveFontFace(styleCfg and styleCfg.fontFace)
		local size = tonumber(styleCfg and styleCfg.size) or 10
		local outline = tostring((styleCfg and styleCfg.style) or "OUTLINE")
		if addon.ApplyFontStyle then
			addon.ApplyFontStyle(nameFS, face, size, outline)
		elseif nameFS.SetFont then
			pcall(nameFS.SetFont, nameFS, face, size, outline)
		end

		-- Apply color based on colorMode (no barKind: FoT name default is white)
		local colorMode = (styleCfg and styleCfg.colorMode) or "default"
		nameTextColorOpts.unitForClass = "focustarget"
		local r, g, b, a = addon.ResolveColorRGBA(colorMode, styleCfg and styleCfg.color, nameTextColorOpts)
		if nameFS.SetTextColor then pcall(nameFS.SetTextColor, nameFS, r, g, b, a) end

		-- Apply alignment
		local alignment = (styleCfg and styleCfg.alignment) or "LEFT"
		if nameFS.SetJustifyH then pcall(nameFS.SetJustifyH, nameFS, alignment) end

		-- Apply offset relative to baseline
		local ox = tonumber(styleCfg and styleCfg.offset and styleCfg.offset.x) or 0
		local oy = tonumber(styleCfg and styleCfg.offset and styleCfg.offset.y) or 0
		if nameFS.ClearAllPoints and nameFS.SetPoint then
			local b = ensureBaseline()
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
	addon.ApplyFoTNameText = applyFoTNameText

	-- Hook FocusFrameToT frame updates to reapply styling
	-- FoT frame is re-shown when focus target changes, so hook the FoT OnShow
	-- NOTE: Uses FrameState to avoid writing properties directly to Blizzard frames (causes taint).
	local function installFoTHooks()
		local fstate = FS
		if not fstate then return end
		local fot = _G.FocusFrameToT
		if fot and not fstate.IsHooked(fot, "fotNameTextHooked") then
			fstate.MarkHooked(fot, "fotNameTextHooked")
			if fot.HookScript then
				fot:HookScript("OnShow", function()
					if _G.C_Timer and _G.C_Timer.After then
						_G.C_Timer.After(0, applyFoTNameText)
					end
				end)
			end
		end
	end

	-- Install hooks after PLAYER_ENTERING_WORLD
	addon.Events.On("UnitFrames:Names", "PLAYER_ENTERING_WORLD", function()
		if _G.C_Timer and _G.C_Timer.After then
			_G.C_Timer.After(0.5, function()
				installFoTHooks()
				-- Apply initial styling
				applyFoTNameText()
			end)
		end
	end)
end
