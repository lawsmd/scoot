--------------------------------------------------------------------------------
-- forever/unitframes/modern/artpet.lua
-- The Modern pet frame's art, as data: the pet frame this client draws
-- itself, transcribed from the Forever build's own files (build
-- 1.60.1.70450): retail's Mainline/PetFrame.xml and PetFrame.lua under the
-- Camelot override layer's PetFrameMixin:OnLoad in
-- Blizzard_UnitFrame/Camelot/PetFrame.lua. The format is in art.lua beside
-- this folder, with the Modern fields the Classic specs never use.
--
-- The pet frame draws the target-of-target's art, which its XML says is on
-- purpose, and the override puts its pieces on the same spots the
-- target-of-target's override does (arttot.lua beside this file): the
-- portrait 37 by 37 at TOPLEFT 5, -5; the name, centred by the override, at
-- the portrait's TOPRIGHT 2, -1, so its 68 by 10 box starts at 44, -6 and
-- its centre is 78, -11; the health bar, 70 by 10, BOTTOMLEFT at the
-- portrait's RIGHT 3, -4, so TOPLEFT 45, -17.5 (the XML's own 44, -17), its
-- mask at the bar's TOPLEFT -26, 3; the power bar, 74 by 7, TOPLEFT at the
-- health bar's BOTTOMLEFT -2, -2, so 43, -29.5, its mask at the XML's
-- TOPLEFT -27, 4; the threat flash and the attack wash both at the frame's
-- TOPLEFT 0, 0. The bar strings sit at their bar's centre: the health
-- strings at 80, -22.5 with Left and Right at the bar's ends, the power
-- strings on 80, -33. The XML nudges the power text 2 right and its Left 4
-- in; the nudge is dropped so the two numbers share a centre, as the Modern
-- target's do, and the client's own power number sits 2 right of its health
-- number.
--
-- The happiness face is the one piece the client's Mainline XML adds to
-- retail's: a frame of its own at LEFT to the frame's RIGHT 0, -4, which
-- the override leaves in place. Its template is the client's own and not
-- in the pulled files, so the face takes the vanilla frame's 24 by 23 and
-- the Classic spec's cells on the same sheet.
--
-- Host and layer follow the painter's three levels: the portrait, the frame
-- art, the flash and the wash on the base frame, the two bars one level up,
-- the strings and the face on artFrame.
--------------------------------------------------------------------------------

local addonName, addon = ...

local Art = addon.UnitFrames.Art
local Paths = Art.Paths
local Modern = Art.Modern

local FAMILY = Modern.FAMILY.TargetofTarget
local PARTY = Modern.FAMILY.Party

local spec = {
    width = 120,
    height = 49,
    hitInsets = { left = 7, right = 66, top = 6, bottom = 7 },
    onBase = { portrait = true, frameTexture = true, frameFlash = true, attackMode = true },
}
Art.Frames.modern.pet = spec

-- The face's three cells by GetPetHappiness value, the Classic spec's table
-- (artpet.lua beside this folder), since both styles draw the same sheet.
spec.HappinessCoords = Art.Frames.camelot.pet.HappinessCoords

spec.Regions = {
    -- BACKGROUND and BORDER, the button's own layers. The portrait under
    -- CircleMask over its own rect, as the XML anchors the mask; the
    -- engine's own round crop stays on (values.lua, ApplyPortrait). The
    -- frame art at its atlas size, centred.
    portrait = {
        layer = "BACKGROUND",
        w = 37, h = 37,
        point = "TOPLEFT", x = 5, y = -5,
        mask = { atlas = "CircleMask" },
    },
    frameTexture = {
        layer = "BORDER",
        atlas = FAMILY,
        point = "CENTER", x = 0, y = 0,
    },
    -- OVERLAY on the button: the threat flash, hidden, which nothing drives
    -- until the threat read is known plain on the beta; the attack wash,
    -- additive and red, which pet.lua pulses while the pet is attacking.
    -- The XML's own alpha ramp is the pulse the painter plays.
    frameFlash = {
        layer = "OVERLAY",
        atlas = FAMILY .. "-InCombat",
        point = "TOPLEFT", x = 0, y = 0,
        hidden = true,
    },
    attackMode = {
        layer = "OVERLAY",
        atlas = FAMILY .. "-Status",
        point = "TOPLEFT", x = 0, y = 0,
        blend = "ADD",
        vertex = { 1, 0, 0 },
        pulse = true,
        hidden = true,
    },
    -- The happiness face, hanging off the frame's right edge; pet.lua shows
    -- it for a pet that reports a happiness.
    happiness = {
        layer = "ARTWORK",
        path = Paths.petHappiness,
        w = 24, h = 23,
        point = "LEFT", relPoint = "RIGHT", x = 0, y = -4,
        coords = spec.HappinessCoords[3],
        hidden = true,
    },
}

spec.DrawOrder = { "portrait", "frameTexture", "frameFlash", "attackMode", "happiness" }

-- The two bars. Each fill is the family's member for it, white, since the
-- colour is in the art (retail's lockColor), and the class, value and custom
-- modes tint it as they tint a file. Each mask stands off its bar as the
-- override and the XML anchor it, at the member's size. The power bar names
-- its family prefix, and the state picks the member for the unit's power
-- (values.lua, ApplyPowerAtlas); the mana fill is the one at build and the
-- fallback. predictionAtlas is the heal prediction segments' fill, the one
-- PetFrameBarSegmentTemplate names.
spec.Bars = {
    health = {
        w = 70, h = 10,
        point = "TOPLEFT", x = 45, y = -17.5,
        atlas = FAMILY .. "-Bar-Health",
        predictionAtlas = FAMILY .. "-Bar-Health-Status",
        color = { 1, 1, 1 },
        mask = { atlas = PARTY .. "-Bar-Health-Mask", point = "TOPLEFT", x = -26, y = 3 },
    },
    power = {
        w = 74, h = 7,
        point = "TOPLEFT", x = 43, y = -29.5,
        atlas = FAMILY .. "-Bar-Mana",
        atlasPrefix = FAMILY .. "-Bar-",
        color = { 1, 1, 1 },
        mask = { atlas = PARTY .. "-Bar-Mana-Mask", point = "TOPLEFT", x = -27, y = 4 },
    },
}

-- Text. The name is the override's: centred, 68 wide, its centre at 78, -11,
-- sat on the box's bottom edge as the XML justifies it; the box's width and
-- alignment are the style's settings, whose defaults are these numbers
-- (text.lua, MODERN_NAME). The bar strings sit at their bar's centre, the
-- Left and Right at the bar's ends.
spec.Text = {
    name = {
        layer = "ARTWORK",
        font = "GameFontNormalSmall",
        w = 68, h = 10,
        justifyH = "CENTER", justifyV = "BOTTOM",
        point = "CENTER", relPoint = "TOPLEFT", x = 78, y = -11,
    },
    healthValue = {
        layer = "OVERLAY",
        font = "TextStatusBarText",
        point = "CENTER", relPoint = "TOPLEFT", x = 80, y = -22.5,
        sides = {
            left = { point = "LEFT", relPoint = "TOPLEFT", x = 45, y = -22.5 },
            right = { point = "RIGHT", relPoint = "TOPLEFT", x = 115, y = -22.5 },
        },
    },
    powerValue = {
        layer = "OVERLAY",
        font = "TextStatusBarText",
        point = "CENTER", relPoint = "TOPLEFT", x = 80, y = -33,
        sides = {
            left = { point = "LEFT", relPoint = "TOPLEFT", x = 47, y = -33 },
            right = { point = "RIGHT", relPoint = "TOPLEFT", x = 117, y = -33 },
        },
    },
}

-- Four debuffs in a row, from the aura container in the client's own pet
-- XML: TOPLEFT 48, -42 with a spacing of 2, the Classic frame's row.
spec.Auras = {
    point = "TOPLEFT", relPoint = "TOPLEFT", x = 48, y = -42,
    spacing = 2, lineSpacing = 2, perLine = 4,
}

-- The manifest: the family's members this spec alone draws; arttot.lua
-- lists the rest.
Modern.Register({
    FAMILY .. "-InCombat", FAMILY .. "-Status", FAMILY .. "-Bar-Health-Status",
})
