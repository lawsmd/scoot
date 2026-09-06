--------------------------------------------------------------------------------
-- cast/text.lua
-- Spell-name and cast-time text styling for the Player/Target/Focus cast bars:
-- fonts, mode-aware colors (via the cast/core.lua gradient helpers),
-- baseline-relative offsets, and the text-fill text sync. Called from
-- cast/styling.lua's apply pass.
--------------------------------------------------------------------------------

local addonName, addon = ...
local CB = addon.CastBars
local installGradientHook = CB._installGradientHook
local applySpellNameColor = CB._applySpellNameColor
local syncTextFillText = CB._syncTextFillText

function CB._applyCastBarTextStyling(frame, cfg, unit, castBarMode)
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
				local face = addon.ResolveFontFace(styleCfg.fontFace)
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
				local face = addon.ResolveFontFace(styleCfg.fontFace)
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
