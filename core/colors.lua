-- colors.lua - Class and power color lookup tables
local addonName, addon = ...

addon.ClassColors = {
	DEATHKNIGHT = { r = 0.77, g = 0.12, b = 0.23 },
	DEMONHUNTER = { r = 0.64, g = 0.19, b = 0.79 },
	DRUID       = { r = 1.00, g = 0.49, b = 0.04 },
	EVOKER      = { r = 0.20, g = 0.58, b = 0.50 },
	HUNTER      = { r = 0.67, g = 0.83, b = 0.45 },
	MAGE        = { r = 0.25, g = 0.78, b = 0.92 },
	MONK        = { r = 0.00, g = 1.00, b = 0.59 },
	PALADIN     = { r = 0.96, g = 0.55, b = 0.73 },
	PRIEST      = { r = 1.00, g = 1.00, b = 1.00 },
	ROGUE       = { r = 1.00, g = 0.96, b = 0.41 },
	SHAMAN      = { r = 0.00, g = 0.44, b = 0.87 },
	WARLOCK     = { r = 0.53, g = 0.53, b = 0.93 },
	WARRIOR     = { r = 0.78, g = 0.61, b = 0.43 },
}

-- Default stock colors used by Blizzard UI when bars are not class- or custom-colored
addon.HealthDefaultColor = { r = 0.00, g = 1.00, b = 0.00 }

-- Static fallback map for power colors (sourced from Blizzard UI: PowerBarColorUtil.lua)
-- Used only when the global PowerBarColor table is unavailable at runtime
addon.PowerColors = {
	MANA = { r = 0.00, g = 0.00, b = 1.00 },
	RAGE = { r = 1.00, g = 0.00, b = 0.00 },
	FOCUS = { r = 1.00, g = 0.50, b = 0.25 },
	ENERGY = { r = 1.00, g = 1.00, b = 0.00 },
	COMBO_POINTS = { r = 1.00, g = 0.96, b = 0.41 },
	RUNES = { r = 0.50, g = 0.50, b = 0.50 },
	RUNIC_POWER = { r = 0.00, g = 0.82, b = 1.00 },
	SOUL_SHARDS = { r = 0.50, g = 0.32, b = 0.55 },
	LUNAR_POWER = { r = 0.30, g = 0.52, b = 0.90 },
	HOLY_POWER = { r = 0.95, g = 0.90, b = 0.60 },
	MAELSTROM = { r = 0.00, g = 0.50, b = 1.00 },
	INSANITY = { r = 0.40, g = 0.00, b = 0.80 },
	CHI = { r = 0.71, g = 1.00, b = 0.92 },
	ARCANE_CHARGES = { r = 0.10, g = 0.10, b = 0.98 },
	FURY = { r = 0.788, g = 0.259, b = 0.992 },
	PAIN = { r = 1.00, g = 0.61176470588235, b = 0.00 }, -- 255/255,156/255,0
	-- Numeric fallbacks (indices from Blizzard)
	[0] = { r = 0.00, g = 0.00, b = 1.00 }, -- MANA
	[1] = { r = 1.00, g = 0.00, b = 0.00 }, -- RAGE
	[2] = { r = 1.00, g = 0.50, b = 0.25 }, -- FOCUS
	[3] = { r = 1.00, g = 1.00, b = 0.00 }, -- ENERGY
	[4] = { r = 0.71, g = 1.00, b = 0.92 }, -- CHI
	[5] = { r = 0.50, g = 0.50, b = 0.50 }, -- RUNES
	[6] = { r = 0.00, g = 0.82, b = 1.00 }, -- RUNIC_POWER
	[7] = { r = 0.50, g = 0.32, b = 0.55 }, -- SOUL_SHARDS
	[8] = { r = 0.30, g = 0.52, b = 0.90 }, -- LUNAR_POWER
	[9] = { r = 0.95, g = 0.90, b = 0.60 }, -- HOLY_POWER
	[11] = { r = 0.00, g = 0.50, b = 1.00 }, -- MAELSTROM
	[13] = { r = 0.40, g = 0.00, b = 0.80 }, -- INSANITY
	[17] = { r = 0.788, g = 0.259, b = 0.992 }, -- FURY
	[18] = { r = 1.00, g = 0.61176470588235, b = 0.00 }, -- PAIN
}

addon.DKSpecColors = {
    [1] = { r = 0.77, g = 0.12, b = 0.23 }, -- Blood
    [2] = { r = 0.41, g = 0.80, b = 0.94 }, -- Frost
    [3] = { r = 0.55, g = 0.78, b = 0.25 }, -- Unholy
}

function addon.GetDKSpecColorRGB()
    local specIndex = GetSpecialization and GetSpecialization()
    local c = specIndex and addon.DKSpecColors[specIndex]
    if c then return c.r, c.g, c.b end
    return 1, 1, 1
end

-- Two-slot color mode helpers for DK "dkSpec" isolation across shared profiles.
-- Each color mode setting has a base slot (used by non-DK) and a DK companion slot.
-- Parameters are getter/setter closures so the same logic works for both PRD and UF storage.

function addon.ReadColorMode(getBase, getDK)
    local _, playerClass = UnitClass("player")
    if playerClass == "DEATHKNIGHT" then
        local dk = getDK()
        if dk ~= nil then return dk end
        return getBase() or "default"
    else
        local base = getBase() or "default"
        if base == "dkSpec" then return "default" end
        return base
    end
end

function addon.WriteColorMode(value, getBase, setBase, getDK, setDK)
    local _, playerClass = UnitClass("player")
    if playerClass == "DEATHKNIGHT" then
        setDK(value)
        if value ~= "dkSpec" then
            setBase(value)
        end
    else
        setBase(value)
        local currentDK = getDK()
        if currentDK ~= "dkSpec" then
            setDK(value)
        end
    end
end

function addon.MigrateDKColorMode(getBase, setBase, getDK, setDK)
    local base = getBase()
    local dk = getDK()
    if base == "dkSpec" and dk == nil then
        setDK("dkSpec")
        setBase("default")
    end
end

function addon.GetDefaultHealthColorRGB()
	local c = addon.HealthDefaultColor
	if c and c.r and c.g and c.b then return c.r, c.g, c.b end
	return 0, 1, 0
end

function addon.GetPowerColorRGB(unitOrPower)
	local tokenOrIndex = nil
	if type(unitOrPower) == "string" then
		if UnitPowerType and (unitOrPower == "player" or unitOrPower == "target" or unitOrPower == "focus" or unitOrPower == "pet" or unitOrPower:match("^boss%d+$")) then
			local idx, tok = UnitPowerType(unitOrPower)
			tokenOrIndex = tok or idx
		else
			tokenOrIndex = unitOrPower
		end
	elseif type(unitOrPower) == "number" then
		tokenOrIndex = unitOrPower
	end

	local c = nil
	if _G.PowerBarColor and tokenOrIndex ~= nil then
		c = _G.PowerBarColor[tokenOrIndex] or _G.PowerBarColor[tonumber(tokenOrIndex) or -1]
	end
	if not c and tokenOrIndex ~= nil then
		c = addon.PowerColors[tokenOrIndex] or addon.PowerColors[tonumber(tokenOrIndex) or -1]
	end
	if c and c.r and c.g and c.b then return c.r, c.g, c.b end
	return 1, 1, 1
end

-- Player class never changes during a session; cache at load time (untainted context).
-- From tainted addon context UnitExists() can return nil, causing GetClassColorRGB
-- to misinterpret "player" as a class token (which doesn't exist in the color tables).
local _playerClassTokenCache = select(2, UnitClass("player"))

-- Resolve a unit token (or a class token passed through) to a class token string.
-- Returns nil when the class cannot be resolved -- callers decide the fallback.
--
-- Split out of GetClassColorRGB because the gradient endpoint tables
-- (addon.CLASS_GRADIENT_ENDPOINTS, addon.SPEC_GRADIENT_COLORS) are keyed by token,
-- and the RGB triple alone can't be turned back into one.
function addon.GetClassTokenForUnit(unitOrClassToken)
	local classToken = nil
	-- A secret input cannot be compared or used as a table key below; bail
	-- before the first comparison (tooltip unit tokens can arrive secret)
	if issecretvalue(unitOrClassToken) then return nil end
	if type(unitOrClassToken) == "string" then
		-- Fast path: "player" uses load-time cache (immune to taint/secrets)
		if unitOrClassToken == "player" and _playerClassTokenCache then
			classToken = _playerClassTokenCache
		else
			-- UnitClassBase (12.0): returns nothing from tainted context (not secrets)
			if UnitClassBase then
				local token = UnitClassBase(unitOrClassToken)
				-- issecretvalue before any truthiness test: boolean-testing a
				-- secret throws (12.1, seen on group members)
				if not issecretvalue(token) and token and type(token) == "string" then
					classToken = token
				end
			end
			-- Fallback: UnitClass with secret guard
			if not classToken and UnitClass then
				local ok, _, token = pcall(function() return UnitClass(unitOrClassToken) end)
				if ok and not issecretvalue(token) and token and type(token) == "string" then
					classToken = token
				end
			end
			-- Last resort: input might be a class token directly (e.g., "WARRIOR")
			if not classToken and not issecretvalue(unitOrClassToken) then
				if addon.ClassColors[unitOrClassToken] or (_G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[unitOrClassToken]) then
					classToken = unitOrClassToken
				end
			end
		end
	end
	if type(classToken) ~= "string" or issecretvalue(classToken) then
		return nil
	end
	return classToken
end

-- Class color table for a bare class token, or nil. For consumers that keep
-- the {r,g,b} object (keyed data rows); unit tokens are not resolved here.
-- CUSTOM_CLASS_COLORS must come before the static table: the static table
-- covers all 13 classes, so any later position would mask it. Without a
-- class-color addon the global is nil and the chain behaves as before.
function addon.GetClassColorObj(classToken)
	if type(classToken) ~= "string" or issecretvalue(classToken) then return nil end
	return (_G.CUSTOM_CLASS_COLORS and _G.CUSTOM_CLASS_COLORS[classToken])
		or addon.ClassColors[classToken]
		or (_G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[classToken])
end

function addon.GetClassColorRGB(unitOrClassToken)
	local classToken = addon.GetClassTokenForUnit(unitOrClassToken)
	if not classToken then
		return nil, nil, nil -- no class resolved; callers decide fallback
	end
	local c = addon.GetClassColorObj(classToken)
	if c and c.r and c.g and c.b then return c.r, c.g, c.b end
	return nil, nil, nil
end

--------------------------------------------------------------------------------
-- Shared colorMode resolution
--------------------------------------------------------------------------------

-- Stock cast bar yellow from the CastingBarFrame mixin
addon.CastDefaultColor = { r = 1.0, g = 0.7, b = 0.0 }

function addon.GetCastDefaultColorRGB()
	local c = addon.CastDefaultColor
	if c and c.r and c.g and c.b then return c.r, c.g, c.b end
	return 1.0, 0.7, 0.0
end

-- value/valueDark are live-update machinery (color-by-value hooks), never a
-- static color; callers detect them with this and run their own applier.
function addon.IsValueColorMode(mode)
	return mode == "value" or mode == "valueDark"
end

local NON_DEFAULT_COLOR_MODES = {
	custom = true, class = true, texture = true,
	value = true, valueDark = true,
	power = true, classPower = true, dkSpec = true,
	classGradient = true, specGradient = true, customGradient = true,
	rainbow = true,
}

-- True for any mode that asks for something other than the stock default.
function addon.IsNonDefaultColorMode(mode)
	return NON_DEFAULT_COLOR_MODES[mode] == true
end

local function legacyNonWhite(tint)
	return type(tint) == "table"
		and (tint[1] ~= 1 or tint[2] ~= 1 or tint[3] ~= 1 or (tint[4] or 1) ~= 1)
end

-- One resolver for the custom/class/texture/default colorMode switch.
-- Returns r, g, b, a, source as a tuple: several callers sit inside
-- SetStatusBarColor-hook hot paths and must not allocate. For the same reason
-- opts at hot sites is a file-scope scratch table whose per-call fields are
-- overwritten before each call; the resolver never calls back into caller code.
--
-- opts (all optional; opts itself may be nil):
--   barKind        "health"|"power"|"altpower"|"cast" - stock color for the
--                  default branch, and the class-miss fallback (health only)
--   unitForClass   unit token or bare class token; default "player"
--   unitForPower   power-color unit; cascade unitForPower, unitForClass, "player"
--   fbR..fbA       default-branch fallback, four scalars returned verbatim
--                  (no arithmetic or compares, so secret-tagged values survive)
--   classPowerMode, dkSpecMode
--                  enable those branches; left off, the modes fall through to
--                  the default branch like any unknown mode
--   lightenMana    classPower only: lighten mana blue by 0.25 for readability
--   legacySniff    nil mode with a stored non-white tint resolves as custom
--   legacySniffDefault
--                  extends the sniff to an explicit "default" mode
--
-- source is one of "custom", "legacy", "class", "classDefault", "classMiss",
-- "texture", "classPower", "dkSpec", "default", "fallback". "classMiss" lets
-- the party/raid text fingerprints suppress caching on unresolved class data.
--
-- Never handled here: value/valueDark (IsValueColorMode), the gradient modes
-- (6-tuple resolvers; colorramp.lua loads after this file), texture-restore
-- else-branches, and dialects whose default writes nothing.
function addon.ResolveColorRGBA(colorMode, tint, opts)
	local mode = colorMode
	if mode == nil or mode == "" then
		if opts and opts.legacySniff and legacyNonWhite(tint) then
			return tint[1] or 1, tint[2] or 1, tint[3] or 1, tint[4] or 1, "legacy"
		end
		mode = "default"
	elseif mode == "default" and opts and opts.legacySniffDefault and legacyNonWhite(tint) then
		return tint[1] or 1, tint[2] or 1, tint[3] or 1, tint[4] or 1, "legacy"
	end

	if mode == "custom" then
		if type(tint) == "table" then
			return tint[1] or 1, tint[2] or 1, tint[3] or 1, tint[4] or 1, "custom"
		end
		return 1, 1, 1, 1, "custom"
	end

	if mode == "class" then
		local r, g, b = addon.GetClassColorRGB((opts and opts.unitForClass) or "player")
		if r ~= nil then
			return r, g, b, 1, "class"
		end
		if opts and opts.barKind == "health" then
			r, g, b = addon.GetDefaultHealthColorRGB()
			return r, g, b, 1, "classDefault"
		end
		return 1, 1, 1, 1, "classMiss"
	end

	if mode == "texture" then
		return 1, 1, 1, 1, "texture"
	end

	if opts and mode == "classPower" and opts.classPowerMode then
		local unit = opts.unitForPower or opts.unitForClass or "player"
		local r, g, b = addon.GetPowerColorRGB(unit)
		if opts.lightenMana then
			local ok, powerType = pcall(UnitPowerType, unit)
			if ok and powerType == 0 then -- MANA
				r = (r or 0) + (1 - (r or 0)) * 0.25
				g = (g or 0) + (1 - (g or 0)) * 0.25
				b = (b or 0) + (1 - (b or 0)) * 0.25
			end
		end
		return r or 1, g or 1, b or 1, 1, "classPower"
	end

	if opts and mode == "dkSpec" and opts.dkSpecMode then
		local r, g, b = addon.GetDKSpecColorRGB()
		return r, g, b, 1, "dkSpec"
	end

	-- Default branch: "default", its legacy "power" alias, gated-off modes,
	-- unknown modes. barKind stock outranks the caller fallback; that matches
	-- bars/textures.lua, where the captured original vertex is the final else.
	local barKind = opts and opts.barKind
	if barKind == "cast" then
		local r, g, b = addon.GetCastDefaultColorRGB()
		return r, g, b, 1, "default"
	elseif barKind == "health" then
		local r, g, b = addon.GetDefaultHealthColorRGB()
		return r, g, b, 1, "default"
	elseif barKind == "power" or barKind == "altpower" then
		local r, g, b = addon.GetPowerColorRGB(opts.unitForPower or opts.unitForClass or "player")
		return r or 1, g or 1, b or 1, 1, "default"
	end
	if opts and opts.fbR ~= nil then
		return opts.fbR, opts.fbG, opts.fbB, opts.fbA, "fallback"
	end
	return 1, 1, 1, 1, "default"
end

-- Convenience wrapper for cfg tables using exactly the colorMode/color keys.
function addon.ResolveColor(cfg, opts)
	return addon.ResolveColorRGBA(cfg and cfg.colorMode, cfg and cfg.color, opts)
end
