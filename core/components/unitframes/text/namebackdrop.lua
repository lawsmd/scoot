--------------------------------------------------------------------------------
-- text/namebackdrop.lua
-- The name backdrop texture strip and its border, shared by every unit-frame
-- name-text applier. Callers resolve the content-main frame and health bar and
-- pass them in; nothing here spells a Blizzard frame path.
--------------------------------------------------------------------------------

local addonName, addon = ...

local UFT = addon.UnitFrameText

-- Reference to FrameState module for safe property storage (avoids writing to Blizzard frames)
local FS = addon.FrameState

local function getState(frame)
	return FS.Get(frame)
end

local safeGetWidth = addon.SecretSafe.safeGetWidth

-- `key` names both the holder slot on the main frame's state and the session
-- base-width slot ("Player".."Pet" or "Boss1".."Boss5"; the key spaces are
-- disjoint, so one store holds both). `growLeft` anchors the strip to the
-- health bar's right edge so it grows toward the portrait. The base-width
-- store is re-read through addon on every call: the style revert in
-- base/core.lua replaces the table. Both functions return false only when the
-- health-bar width cannot be safely read (secret-value environment); the
-- caller decides whether false aborts its pass (the generic tail in names.lua
-- does) or continues (the Boss branch does).
function UFT._ApplyNameBackdrop(main, hb, cfg, key, growLeft)
	local holderKey = "ScootNameBackdrop_" .. key
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
		return true
	end

	local texKey = cfg.nameBackdropTexture or ""
	-- Default to disabled backdrop unless explicitly enabled in the profile.
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
	if not tex then return true end

	if hb and resolvedPath and enabledBackdrop then
		-- Compute a baseline width per-session (do NOT persist baselines into SavedVariables).
		addon._ufNameBackdropBaseWidth = addon._ufNameBackdropBaseWidth or {}
		local base = tonumber(addon._ufNameBackdropBaseWidth[key])
		if not base or base <= 0 then
			base = safeGetWidth(hb)
			if base and base > 0 then
				addon._ufNameBackdropBaseWidth[key] = base
			end
		end
		-- If the width can't be safely read (secret-value environment), skip cosmetics.
		if not base or base <= 0 then
			tex:Hide()
			return false
		end
		local wPct = tonumber(cfg.nameBackdropWidthPct) or 100
		if wPct < 25 then wPct = 25 elseif wPct > 300 then wPct = 300 end
		local desiredWidth = math.max(1, math.floor((base * wPct / 100) + 0.5))

		tex:ClearAllPoints()
		if growLeft then
			tex:SetPoint("BOTTOMRIGHT", hb, "TOPRIGHT", 0, 0)
		else
			tex:SetPoint("BOTTOMLEFT", hb, "TOPLEFT", 0, 0)
		end
		tex:SetSize(desiredWidth, 16)
		tex:SetTexture(resolvedPath)
		if tex.SetDrawLayer then tex:SetDrawLayer("BACKGROUND", -8) end
		if tex.SetHorizTile then tex:SetHorizTile(false) end
		if tex.SetVertTile then tex:SetVertTile(false) end
		if tex.SetTexCoord then tex:SetTexCoord(0, 1, 0, 1) end

		-- Kept off addon.ResolveColorRGBA: three-mode switch with a black default; a wrapper would outgrow these six lines.
		-- Color behavior mirrors bar backgrounds:
		--  - texture  => preserve original colors (white vertex)
		--  - default  => use default background color (black)
		--  - custom   => use tint (including alpha)
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
	return true
end

function UFT._ApplyNameBackdropBorder(main, hb, cfg, key, growLeft)
	local borderKey = "ScootNameBackdropBorder_" .. key
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
		return true
	end

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
	local tintColor = cfg.nameBackdropBorderTintColor or { 1, 1, 1, 1 }

	local borderFrame = existingBorderFrame
	if main and not borderFrame then
		local template = BackdropTemplateMixin and "BackdropTemplate" or nil
		borderFrame = CreateFrame("Frame", nil, main, template)
		if mainState then mainState[borderKey] = borderFrame end
	end
	if not borderFrame then return true end

	if hb and useBorders then
		-- Match border width to the same baseline-derived width as the backdrop.
		addon._ufNameBackdropBaseWidth = addon._ufNameBackdropBaseWidth or {}
		local base = tonumber(addon._ufNameBackdropBaseWidth[key])
		if not base or base <= 0 then
			base = safeGetWidth(hb)
			if base and base > 0 then
				addon._ufNameBackdropBaseWidth[key] = base
			end
		end
		-- If the width can't be safely read (secret-value environment), skip cosmetics.
		if not base or base <= 0 then
			borderFrame:Hide()
			return false
		end
		local wPct = tonumber(cfg.nameBackdropWidthPct) or 100
		if wPct < 25 then wPct = 25 elseif wPct > 300 then wPct = 300 end
		local desiredWidth = math.max(1, math.floor((base * wPct / 100) + 0.5))

		borderFrame:ClearAllPoints()
		if growLeft then
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
		-- Fully clear both border types on disable
		if addon.Borders and addon.Borders.HideAll then addon.Borders.HideAll(borderFrame) end
		if borderFrame.SetBackdrop then pcall(borderFrame.SetBackdrop, borderFrame, nil) end
		borderFrame:Hide()
	end
	return true
end
