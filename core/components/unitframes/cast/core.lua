--------------------------------------------------------------------------------
-- cast/core.lua
-- Cast bar subsystem initialization: shared state, event routing, and per-unit
-- cast bar module registration.
--------------------------------------------------------------------------------

local addonName, addon = ...

-- Namespace for cast bar decomposition (pattern: addon.DamageMetersX, addon.PRD)
local CB = {}
addon.CastBars = CB

-- Reference to FrameState module for safe property storage (avoids writing to Blizzard frames)
local FS = addon.FrameState

function CB._getState(frame)
	return FS.Get(frame)
end

function CB._getProp(frame, key)
	local st = FS.Get(frame)
	return st and st[key] or nil
end

function CB._setProp(frame, key, value)
	local st = FS.Get(frame)
	if st then
		st[key] = value
	end
end

function CB._getIconBorderContainer(frame)
	local st = CB._getState(frame)
	return st and st.ScootIconBorderContainer or nil
end

-- =========================================================================
-- Gradient text helpers (spell name color ramp)
-- =========================================================================

CB.SPELL_LIGHTEN_RATIO = 0.45

function CB._resolveGradientColors(colorMode, styleCfg)
	local r1, g1, b1
	if colorMode == "classGradient" and addon.GetClassColorRGB then
		r1, g1, b1 = addon.GetClassColorRGB("player")
		r1, g1, b1 = r1 or 1, g1 or 1, b1 or 1
		-- Curated per-class endpoints with darkened start for richer gradients
		local _, classToken = UnitClass("player")
		local endpoints = classToken and addon.CLASS_GRADIENT_ENDPOINTS and addon.CLASS_GRADIENT_ENDPOINTS[classToken]
		if endpoints then
			local dr, dg, db = addon.DarkenColor(r1, g1, b1, 0.25)
			local er, eg, eb = addon.LightenColor(endpoints[1], endpoints[2], endpoints[3], 0.10)
			return dr, dg, db, er, eg, eb
		end
		-- Fallback: generic lighten formula
		local r2, g2, b2 = addon.LightenColor(r1, g1, b1, CB.SPELL_LIGHTEN_RATIO)
		return r1, g1, b1, r2, g2, b2
	end
	if colorMode == "specGradient" then
		local specIndex = GetSpecialization and GetSpecialization()
		local specID = specIndex and GetSpecializationInfo and select(1, GetSpecializationInfo(specIndex))
		local specData = specID and addon.SPEC_GRADIENT_COLORS and addon.SPEC_GRADIENT_COLORS[specID]
		if specData then
			local dr, dg, db = addon.DarkenColor(specData.base[1], specData.base[2], specData.base[3], 0.25)
			local er, eg, eb = addon.LightenColor(specData.endpoint[1], specData.endpoint[2], specData.endpoint[3], 0.10)
			return dr, dg, db, er, eg, eb
		end
		-- Fallback: use class gradient if spec not found
		if addon.GetClassColorRGB then
			r1, g1, b1 = addon.GetClassColorRGB("player")
			r1, g1, b1 = r1 or 1, g1 or 1, b1 or 1
			local r2, g2, b2 = addon.LightenColor(r1, g1, b1, CB.SPELL_LIGHTEN_RATIO)
			return r1, g1, b1, r2, g2, b2
		end
	end
	if colorMode == "customGradient" then
		local c = styleCfg.color or {1, 1, 1, 1}
		r1, g1, b1 = c[1] or 1, c[2] or 1, c[3] or 1
	end
	r1, g1, b1 = r1 or 1, g1 or 1, b1 or 1
	local r2, g2, b2 = addon.LightenColor(r1, g1, b1, CB.SPELL_LIGHTEN_RATIO)
	return r1, g1, b1, r2, g2, b2
end

-- File-level guard for re-entrant SetText during gradient application
CB._rampApplying = false

-- Install a SetText hook on a spell name FontString for live gradient updates.
-- cfgResolver: function() returning the spellNameText sub-table (or nil).
-- parentFrame: the cast bar frame (for text-fill mode awareness).
function CB._installGradientHook(spellFS, cfgResolver, parentFrame)
	if not spellFS or CB._getProp(spellFS, "_rampHooked") then return end
	hooksecurefunc(spellFS, "SetText", function(self, text)
		if CB._rampApplying then return end
		if type(text) ~= "string" then return end
		if issecretvalue and issecretvalue(text) then
			-- Clear stale gradient cache so syncTextFillText won't use old text
			CB._setProp(self, "_rampRawText", nil)
			-- In text-fill mode, pass secret directly to filledText (SetText is AllowedWhenTainted)
			if parentFrame and CB._getProp(parentFrame, "textFillActive") then
				local els = CB._getProp(parentFrame, "textFillElements")
				if els and els.filledText then
					pcall(els.filledText.SetText, els.filledText, text)
				end
				-- Re-fit for the new name. Indexed at call time: textfill.lua loads
				-- AFTER this file (TOC 123 vs 122), so CB._fitTextFillScale does not
				-- exist yet at definition time and must never be cached in a local.
				if CB._fitTextFillScale then
					CB._fitTextFillScale(parentFrame, CB._getProp(parentFrame, "textFillSpellNameCfg"), text)
				end
			end
			return
		end
		-- Cache the raw (uncolored) text for re-application on settings change
		CB._setProp(self, "_rampRawText", text)
		local styleCfg = cfgResolver()
		if not styleCfg then return end
		local mode = styleCfg.colorMode
		if mode ~= "classGradient" and mode ~= "specGradient" and mode ~= "customGradient" then return end
		if not addon.BuildColorRampString then return end
		local r1, g1, b1, r2, g2, b2 = CB._resolveGradientColors(mode, styleCfg)
		-- Text-fill mode: apply IDENTICAL gradient to both filledText and frame.Text.
		-- Byte-identical |cff codes are what eliminate shaper-run kerning drift
		-- (pitfall #28). frame.Text is dimmed via SetAlpha in syncTextFillText.
		if parentFrame and CB._getProp(parentFrame, "textFillActive") then
			local els = CB._getProp(parentFrame, "textFillElements")
			local gradientStr = addon.BuildColorRampString(text, r1, g1, b1, r2, g2, b2)
			if els and els.filledText then
				pcall(els.filledText.SetText, els.filledText, gradientStr)
			end
			CB._rampApplying = true
			pcall(self.SetText, self, gradientStr)
			CB._rampApplying = false
			-- Re-fit against the gradient bytes (|cff hex values affect kerning,
			-- so the gradient string's natural width differs from the plain one's)
			if CB._fitTextFillScale then
				CB._fitTextFillScale(parentFrame, styleCfg, gradientStr)
			end
			return
		end
		-- Normal mode: apply gradient to frame.Text
		CB._rampApplying = true
		pcall(self.SetText, self, addon.BuildColorRampString(text, r1, g1, b1, r2, g2, b2))
		CB._rampApplying = false
	end)
	CB._setProp(spellFS, "_rampHooked", true)
end

-- Apply spell name color based on colorMode setting.
-- Handles: default, class, custom, classGradient, customGradient.
-- parentFrame: the cast bar frame (for text-fill mode awareness).
function CB._applySpellNameColor(spellFS, styleCfg, parentFrame)
	if not spellFS then return end
	local colorMode = styleCfg.colorMode or "default"
	local isTextFill = parentFrame and CB._getProp(parentFrame, "textFillActive")

	if colorMode == "classGradient" or colorMode == "specGradient" or colorMode == "customGradient" then
		local cachedText = CB._getProp(spellFS, "_rampRawText")
		if cachedText and not (issecretvalue and issecretvalue(cachedText)) and addon.BuildColorRampString then
			local r1, g1, b1, r2, g2, b2 = CB._resolveGradientColors(colorMode, styleCfg)
			local rampText = addon.BuildColorRampString(cachedText, r1, g1, b1, r2, g2, b2)
			if isTextFill then
				-- Text-fill: apply IDENTICAL gradient to both filledText and frame.Text.
				-- Byte-identical |cff codes eliminate shaper-run kerning drift
				-- (pitfall #28). frame.Text is dimmed via SetAlpha in syncTextFillText.
				local els = CB._getProp(parentFrame, "textFillElements")
				if els and els.filledText then
					pcall(els.filledText.SetText, els.filledText, rampText)
				end
				CB._rampApplying = true
				pcall(spellFS.SetText, spellFS, rampText)
				CB._rampApplying = false
				-- Re-fit: a colorMode change alters the |cff bytes and therefore
				-- the measured natural width
				if CB._fitTextFillScale then
					CB._fitTextFillScale(parentFrame, styleCfg, rampText)
				end
			else
				-- Normal mode: gradient on frame.Text, white base color
				if spellFS.SetTextColor then
					pcall(spellFS.SetTextColor, spellFS, 1, 1, 1, 1)
				end
				CB._rampApplying = true
				pcall(spellFS.SetText, spellFS, rampText)
				CB._rampApplying = false
			end
		end
	elseif colorMode == "class" then
		local cr, cg, cb
		if addon.GetClassColorRGB then
			cr, cg, cb = addon.GetClassColorRGB("player")
		end
		cr, cg, cb = cr or 1, cg or 1, cb or 1
		if spellFS.SetTextColor then
			pcall(spellFS.SetTextColor, spellFS, cr, cg, cb, 1)
		end
	elseif colorMode == "custom" then
		local c = styleCfg.color or {1, 1, 1, 1}
		if spellFS.SetTextColor then
			pcall(spellFS.SetTextColor, spellFS, c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
		end
	else -- "default"
		if spellFS.SetTextColor then
			pcall(spellFS.SetTextColor, spellFS, 1, 1, 1, 1)
		end
	end

	-- When switching FROM gradient to non-gradient, restore plain text
	if colorMode ~= "classGradient" and colorMode ~= "specGradient" and colorMode ~= "customGradient" then
		local cachedText = CB._getProp(spellFS, "_rampRawText")
		if cachedText and spellFS.GetText then
			local ok, current = pcall(spellFS.GetText, spellFS)
			if ok and type(current) == "string" and not issecretvalue(current) and current:find("|cff") then
				CB._rampApplying = true
				pcall(spellFS.SetText, spellFS, cachedText)
				CB._rampApplying = false
			end
		end
	end
end

-- Baseline anchors for Cast Time text (Player only)
addon._ufCastTimeTextBaselines = addon._ufCastTimeTextBaselines or {}
-- Baseline anchors for Spell Name text (Player only)
addon._ufCastSpellNameBaselines = addon._ufCastSpellNameBaselines or {}
