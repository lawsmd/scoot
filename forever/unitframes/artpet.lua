--------------------------------------------------------------------------------
-- forever/unitframes/artpet.lua
-- The Classic pet frame's art, as data. Transcribed from Classic/PetFrame.xml
-- on origin/classic_era; the format is in art.lua.
--
-- The border is drawn whole, 128x64, two units below the frame's top, so it
-- runs 13 past the frame's bottom edge. A pet with no power bar takes the
-- NoMana file, which is the same art with the lower slot closed (pet.lua).
--------------------------------------------------------------------------------

local addonName, addon = ...

local Art = addon.UnitFrames.Art
local Paths = Art.Paths

local spec = {
    width = 128,
    height = 53,
    borderKey = "borderSmall",
    hitInsets = { left = 7, right = 66, top = 6, bottom = 7 },
    onBase = { portrait = true },
}
Art.Frames.pet = spec

-- The happiness face's three cells on UI-PetHappiness, by GetPetHappiness value.
spec.HappinessCoords = {
    [3] = { 0, 0.1875, 0, 0.359375 },
    [2] = { 0.1875, 0.375, 0, 0.359375 },
    [1] = { 0.375, 0.5625, 0, 0.359375 },
}

spec.Regions = {
    portrait = {
        layer = "BACKGROUND",
        w = 37, h = 37,
        point = "TOPLEFT", x = 7, y = -6,
    },
    border = {
        layer = "BORDER",
        path = Paths.borderSmall,
        w = 128, h = 64,
        point = "TOPLEFT", x = 0, y = -2,
        border = true,
    },
    -- The red wash over the portrait while the pet is attacking.
    attackMode = {
        layer = "ARTWORK",
        path = Paths.petAttack,
        w = 76, h = 64,
        point = "TOPLEFT", x = 6, y = -9,
        coords = { 0.703125, 1.0, 0, 1.0 },
        blend = "ADD",
        pulse = true,
        hidden = true,
    },
    -- A frame of its own in the XML, hanging off the pet frame's right edge.
    happiness = {
        layer = "ARTWORK",
        path = Paths.petHappiness,
        w = 24, h = 23,
        point = "LEFT", relPoint = "RIGHT", x = -7, y = -4,
        coords = spec.HappinessCoords[3],
        hidden = true,
    },
}

spec.DrawOrder = { "portrait", "border", "attackMode", "happiness" }

spec.Bars = {
    health = {
        w = 69, h = 8,
        point = "TOPLEFT", x = 47, y = -22,
        texture = Paths.statusBar,
        color = { 0.0, 1.0, 0.0 },
    },
    power = {
        w = 69, h = 8,
        point = "TOPLEFT", x = 47, y = -29,
        texture = Paths.statusBar,
        color = { 0, 0, 1.0 },
    },
}

spec.Text = {
    name = {
        layer = "ARTWORK",
        font = "GameFontNormalSmall",
        point = "BOTTOMLEFT", x = 52, y = 33,
    },
    healthValue = {
        layer = "BORDER",
        font = "TextStatusBarText",
        point = "CENTER", relPoint = "TOPLEFT", x = 82, y = -26,
    },
    powerValue = {
        layer = "BORDER",
        font = "TextStatusBarText",
        point = "CENTER", relPoint = "TOPLEFT", x = 82, y = -38,
    },
}
