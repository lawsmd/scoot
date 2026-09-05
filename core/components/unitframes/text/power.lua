--------------------------------------------------------------------------------
-- text/power.lua
-- Power text kind descriptor and forks for the shared text pipeline
-- (text/pipeline.lua): bar and FontString resolvers, the power color half with
-- its Death Knight companion slot, and the DK color-mode migration.
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

-- Shared frame resolvers (core/frames.lua)
local Frames = addon.Frames

-- Cross-file import: the shared text pipeline builder (text/pipeline.lua, loaded first in TOC)
local buildTextPipeline = addon.UnitFrameText._BuildTextPipeline

-- Hide-enforcement hooks (core/enforce.lua). The hidden flag stays in
-- FrameState, where the profile-switch reset in base/core.lua also clears it;
-- the keys read it live. Show and SetText re-assert at once, SetAlpha after a
-- stack break. The power hooks never bailed in Edit Mode, and still do not.
local POWER_TEXT_OPTS = {
	methods = { "Show", "SetAlpha", "SetText" },
	timing = { SetAlpha = "defer" },
	when = function(fs) return FS.IsHidden(fs, "powerText") end,
}
local POWER_TEXT_CENTER_OPTS = {
	methods = { "SetText" },
	when = function(fs) return FS.IsHidden(fs, "powerTextCenter") end,
}

-- Unit Frames: Toggle Power % (LeftText when present) and Value (RightText) visibility per unit
do
	-- Color half of the text styling: the DK companion slot merges into the
	-- effective mode before ResolveColorRGBA
	local function applyPowerTextColor(fs, styleCfg)
		local colorMode = addon.ReadColorMode(
			function() return styleCfg.colorMode end,
			function() return styleCfg.colorModeDK end
		)
		local cr, cg, cb, ca = addon.ResolveColorRGBA(colorMode, styleCfg.color, ufPowerTextColorOpts)
		if fs.SetTextColor then pcall(fs.SetTextColor, fs, cr, cg, cb, ca) end
	end

	-- First-rung left/right FontString paths (no scanning); the pipeline falls
	-- back to the hint scan when these miss. Pet uses standalone globals more often.
	local function directPowerTexts(frame, unit)
		local leftFS, rightFS
		if unit == "Pet" then
			leftFS = _G.PetFrameManaBarTextLeft
			rightFS = _G.PetFrameManaBarTextRight
		end
		leftFS = leftFS or (frame and frame.ManaBar and frame.ManaBar.LeftText)
		rightFS = rightFS or (frame and frame.ManaBar and frame.ManaBar.RightText)
		return leftFS, rightFS
	end

	-- Migrate dkSpec from base slot to DK companion slot (idempotent)
	local function migrateDKColorSlots(cfg)
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
	end

	local P = buildTextPipeline({
		resource = "Power",
		slug = "power",
		fontCache = "_ufPowerTextFonts",
		baselineTable = "_ufPowerTextBaselines",
		hookMarker = "powerBarUpdateTextString",
		visibilityForName = "ApplyUnitFramePowerTextVisibilityFor",
		hiddenKey = "powerText",
		hiddenCenterKey = "powerTextCenter",
		appliedProp = "powerTextAppliedHidden",
		keys = {
			barHidden = "powerBarHidden",
			percentHidden = "powerPercentHidden",
			valueHidden = "powerValueHidden",
			percentStyle = "textPowerPercent",
			valueStyle = "textPowerValue",
		},
		textOpts = POWER_TEXT_OPTS,
		centerOpts = POWER_TEXT_CENTER_OPTS,
		fontOpts = ufTextFontOpts,
		customizationOpts = ufTextCustomizationOpts,
		barResolver = Frames.resolvePowerBar,
		directTexts = directPowerTexts,
		hints = {
			left  = { "ManaBar.LeftText",  ".LeftText",  "ManaBarTextLeft" },
			right = { "ManaBar.RightText", ".RightText", "ManaBarTextRight" },
		},
		centerResolver = Frames.resolvePowerCenterText,
		bossContainer = Frames.resolveBossManaBar,
		bossBar = function(container) return container end,
		colorApplier = applyPowerTextColor,
		migrate = migrateDKColorSlots,
	})

	addon.ApplyBossPowerTextStyling = P.applyBossStyling
	addon.ApplyUnitFramePowerTextVisibilityFor = P.applyVisibilityFor
	addon.ApplyAllUnitFramePowerTextVisibility = P.applyAll
end
