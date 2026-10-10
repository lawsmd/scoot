-- media.lua - Bar texture registry and status bar styling
local addonName, addon = ...

addon.Media = addon.Media or {}

-- Global media tokens: virtual keys a font/texture setting can hold instead of
-- a concrete media key. They resolve through db.global.media at the resolver
-- choke points (ResolveFontFace, ResolveBarTexturePath), so every consumer
-- follows the account-wide globals without per-feature registration.
addon.MediaTokens = {
	PREFIX      = "global:",
	HEADER_FONT = "global:header",
	BODY_FONT   = "global:body",
	BAR_TEXTURE = "global:barTexture",
}

local TOKEN_PREFIX = addon.MediaTokens.PREFIX

function addon.IsMediaToken(key)
	return type(key) == "string" and key:sub(1, #TOKEN_PREFIX) == TOKEN_PREFIX
end

function addon.IsFontToken(key)
	return key == addon.MediaTokens.HEADER_FONT or key == addon.MediaTokens.BODY_FONT
end

function addon.IsBarTextureToken(key)
	return key == addon.MediaTokens.BAR_TEXTURE
end

-- The addon that loaded this file, not a literal: the Forever client has no
-- Scoot folder to resolve against. core/fonts.lua takes the same fallback.
local BAR_MEDIA_PREFIX = addon.MediaPath .. "media\\bar\\"

-- Per-bar state (weak keys). Local table avoids tainting Blizzard frames.
local barFrameState = setmetatable({}, { __mode = "k" })

-- Registry of bar textures bundled with Scoot. Keys are stable identifiers.
local BAR_TEXTURES = {
	-- Flat series (legacy "A1-A3", renamed for clarity)
	a1                     = BAR_MEDIA_PREFIX .. "a1.tga",
	a2                     = BAR_MEDIA_PREFIX .. "a2.tga",
	a3                     = BAR_MEDIA_PREFIX .. "a3.tga",
	bevelled               = BAR_MEDIA_PREFIX .. "bevelled.png",
	bevelledGrey           = BAR_MEDIA_PREFIX .. "bevelled-grey.png",
	fadeTop                = BAR_MEDIA_PREFIX .. "fade-top.png",
	fadeBottom             = BAR_MEDIA_PREFIX .. "fade-bottom.png",
	fadeLeft               = BAR_MEDIA_PREFIX .. "fade-left.png",
	blizzardCastBar        = BAR_MEDIA_PREFIX .. "blizzard-cast-bar.png",
	-- Blizzard resource bar textures (bundled art assets)
	blizzardEbonMight      = BAR_MEDIA_PREFIX .. "EvokerEbonMight.tga",
	blizzardEnergy         = BAR_MEDIA_PREFIX .. "BlizzardUnitframe1.tga",
	blizzardFocus          = BAR_MEDIA_PREFIX .. "BlizzardUnitframe2.tga",
	blizzardFury           = BAR_MEDIA_PREFIX .. "DemonHunterFury.tga",
	blizzardInsanity       = BAR_MEDIA_PREFIX .. "PriestInsanity1.tga",
	blizzardInsanity2      = BAR_MEDIA_PREFIX .. "PriestInsanity2.tga",
	blizzardLunarPower     = BAR_MEDIA_PREFIX .. "DruidStarPower.tga",
	blizzardMaelstrom      = BAR_MEDIA_PREFIX .. "ShamanMaelstrom.tga",
	blizzardMana           = BAR_MEDIA_PREFIX .. "BlizzardUnitframe3.tga",
	blizzardPain           = BAR_MEDIA_PREFIX .. "MonkStagger1.tga",
	blizzardPain2          = BAR_MEDIA_PREFIX .. "MonkStagger2.tga",
	blizzardPain3          = BAR_MEDIA_PREFIX .. "MonkStagger3.tga",
	blizzardRage           = BAR_MEDIA_PREFIX .. "BlizzardUnitframe4.tga",
	blizzardRaidBar        = BAR_MEDIA_PREFIX .. "BlizzardUnitframe5.tga",
	blizzardRunicPower     = BAR_MEDIA_PREFIX .. "BlizzardUnitframe6.tga",
	-- Additional Blizzard unitframe textures
	blizzardUnitframe7     = BAR_MEDIA_PREFIX .. "BlizzardUnitframe7.tga",
	blizzardUnitframe8     = BAR_MEDIA_PREFIX .. "BlizzardUnitframe8.tga",
	-- Blizzard experience bar textures
	blizzardExperience1   = BAR_MEDIA_PREFIX .. "BlizzardExperience1.tga",
	blizzardExperience2    = BAR_MEDIA_PREFIX .. "BlizzardExperience2.tga",
	blizzardExperience3   = BAR_MEDIA_PREFIX .. "BlizzardExperience3.tga",
	-- Blizzard labs textures
	blizzardLabs1          = BAR_MEDIA_PREFIX .. "BlizzardLabs1.tga",
	blizzardLabs2          = BAR_MEDIA_PREFIX .. "BlizzardLabs2.tga",
}

local BAR_DISPLAY_NAMES = {
	-- Flat series (legacy "A1-A3", renamed for clarity)
	a1 = "Flat 1",
	a2 = "Flat 2",
	a3 = "Flat 3",
	bevelled = "Bevelled",
	bevelledGrey = "Bevelled Grey",
	fadeTop = "Fade Top",
	fadeBottom = "Fade Bottom",
	fadeLeft = "Fade Left",
	blizzardCastBar = "Blizzard Cast Bar",
	-- Blizzard resource bar textures
	blizzardEbonMight = "Blizzard Ebon Might",
	blizzardEnergy = "Blizzard Energy",
	blizzardFocus = "Blizzard Focus",
	blizzardFury = "Blizzard Fury",
	blizzardInsanity = "Blizzard Insanity",
	blizzardInsanity2 = "Blizzard Insanity 2",
	blizzardLunarPower = "Blizzard Lunar Power",
	blizzardMaelstrom = "Blizzard Maelstrom",
	blizzardMana = "Blizzard Mana",
	blizzardPain = "Blizzard Pain",
	blizzardPain2 = "Blizzard Pain 2",
	blizzardPain3 = "Blizzard Pain 3",
	blizzardRage = "Blizzard Rage",
	blizzardRaidBar = "Blizzard Raid Bar",
	blizzardRunicPower = "Blizzard Runic Power",
	-- Additional Blizzard unitframe textures
	blizzardUnitframe7 = "Blizzard Unitframe 7",
	blizzardUnitframe8 = "Blizzard Unitframe 8",
	-- Blizzard experience bar textures
	blizzardExperience1 = "Blizzard Experience 1",
	blizzardExperience2 = "Blizzard Experience 2",
	blizzardExperience3 = "Blizzard Experience 3",
	-- Blizzard labs textures
	blizzardLabs1 = "Blizzard Labs 1",
	blizzardLabs2 = "Blizzard Labs 2",
}

local BAR_TEXTURE_ORDER = {
	-- Keep the most commonly used "flat" textures immediately after "Default" in dropdowns
	"a1",
	"a2",
	"a3",
	"bevelled",
	"bevelledGrey",
	"fadeTop",
	"fadeBottom",
	"fadeLeft",
	"blizzardCastBar",
	-- Blizzard resource bar textures (grouped together)
	"blizzardEbonMight",
	"blizzardEnergy",
	"blizzardFocus",
	"blizzardFury",
	"blizzardInsanity",
	"blizzardInsanity2",
	"blizzardLunarPower",
	"blizzardMaelstrom",
	"blizzardMana",
	"blizzardPain",
	"blizzardPain2",
	"blizzardPain3",
	"blizzardRage",
	"blizzardRaidBar",
	"blizzardRunicPower",
	"blizzardUnitframe7",
	"blizzardUnitframe8",
	"blizzardExperience1",
	"blizzardExperience2",
	"blizzardExperience3",
	"blizzardLabs1",
	"blizzardLabs2",
}

-- Public: build a Settings container for dropdowns listing bar textures
function addon.BuildBarTextureOptionsContainer()
    local create = Settings and Settings.CreateControlTextContainer
    if not create then
        local fallback = {}
        -- Insert a Default option that restores Blizzard's stock textures
        table.insert(fallback, { value = "default", text = "Default" })
        for _, key in ipairs(BAR_TEXTURE_ORDER) do
            fallback[#fallback + 1] = { value = key, text = addon.Media.GetBarTextureDisplayName(key) or key }
        end
        return fallback
    end

    local container = create()
    -- Add Default option at the top
    container:Add("default", "Default")
    for _, key in ipairs(BAR_TEXTURE_ORDER) do
        local path = BAR_TEXTURES[key]
        if path then
            local label = addon.Media.GetBarTextureDisplayName(key)
            local preview = string.format("%s  |T%s:%d:%d|t", label, path, 12, 180)
            container:Add(key, preview)
        end
    end
    return container:GetData()
end

-- Swap a Global Bar Texture token for the account-wide value it points at.
-- One level only: a token stored as the global's own value (blocked by the
-- ApplyAll setters, but guarded here) degrades to "default". Safe before DB
-- init: no db means "default".
function addon.Media.NormalizeBarTextureKey(key)
	if not addon.IsBarTextureToken(key) then return key end
	local media = addon.db and addon.db.global and addon.db.global.media
	local value = media and media.barTexture
	if type(value) ~= "string" or value == "" or addon.IsMediaToken(value) then
		return "default"
	end
	return value
end

-- Zero-Touch gate: a key counts as "default" (leave Blizzard's bar alone) when
-- the key itself, or the global a token points at, is the stock value. Every
-- customization gate must use this instead of comparing the raw key against
-- "default", or a token default would build overlays on untouched frames.
function addon.Media.IsDefaultBarTexture(key)
	local k = addon.Media.NormalizeBarTextureKey(key)
	return type(k) ~= "string" or k == "" or k == "default"
end

function addon.Media.ResolveBarTexturePath(key)
	if type(key) ~= "string" or key == "" then return nil end
	-- Token swap must precede the "default" early-return so a global of
	-- "default" still yields nil (stock texture).
	key = addon.Media.NormalizeBarTextureKey(key)
	if key == "default" then return nil end
	-- LSM-sourced statusbar texture
	if addon.IsLSMKey and addon.IsLSMKey(key) then
		return addon.LSMFetch and addon.LSMFetch("statusbar", key)
	end
	return BAR_TEXTURES[key]
end

function addon.Media.GetBarTextureDisplayName(key)
	if key == addon.MediaTokens.BAR_TEXTURE then
		return "Global Bar Texture"
	end
	if addon.IsLSMKey and addon.IsLSMKey(key) then
		return addon.LSMKeyToName(key)
	end
	return BAR_DISPLAY_NAMES[key] or key or ""
end

-- The built-in bar texture keys in dropdown order, a copy; a settings field
-- sizes itself to their display names
function addon.Media.BarTextureKeys()
	local keys = {}
	for i, key in ipairs(BAR_TEXTURE_ORDER) do keys[i] = key end
	return keys
end

-- Accessor for other modules (e.g., cooldowns.lua) to get the background texture
-- without reading directly from the Blizzard frame table
function addon.Media.GetBarFrameState(barFrame)
	return barFrameState[barFrame]
end
