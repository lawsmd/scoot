--------------------------------------------------------------------------------
-- forever/unitframes/modern/arttot.lua
-- The Modern target-of-target frame's art, as data: the small frame this
-- client draws itself, transcribed from the Forever build's own files (build
-- 1.60.1.70450): TargetofTargetFrameTemplate in retail's
-- Mainline/TargetFrame.xml, created by TargetFrame.lua, under the Camelot
-- override layer's TargetOfTargetMixin:OnLoad in
-- Blizzard_UnitFrame/Camelot/TargetFrame.lua. The format is in art.lua
-- beside this folder, with the Modern fields the Classic specs never use.
--
-- The small frame: a portrait, a name, two thin bars, four debuffs. It has
-- no level, no icons, no bar text and no heal prediction. The XML anchors
-- each piece to another piece and the override's load hook moves three of
-- them; the numbers below are translated to the frame's own corner, with the
-- portrait 37 by 37 at TOPLEFT 5, -5:
--   the name, centred by the override, hangs TOPLEFT at the portrait's
--   TOPRIGHT 2, -1, so its 68 by 10 box starts at 44, -6 and its centre is
--   78, -11;
--   the health bar, 70 by 10, hangs BOTTOMRIGHT at the frame's RIGHT -5, -3,
--   so it starts at TOPLEFT 45, -17.5 (the XML's own 44, -17), with its mask
--   at the bar's TOPLEFT -26, 3 (the XML's -29);
--   the power bar, 74 by 7, hangs TOPLEFT at the health bar's BOTTOMLEFT
--   -2, -2: TOPLEFT 43, -29.5 (the XML's 40, -28), its mask at the XML's
--   TOPLEFT -27, 4;
--   the dead and unconscious texts sit at the health bar's centre, 80, -22.5.
-- The pet frame's spec (artpet.lua beside this file) lands on the same
-- spots from its own override.
--
-- Host and layer follow the painter's three levels: the portrait and the
-- frame art on the base frame, the two bars one level up, the strings on
-- artFrame. The two bar masks are the party frame's members, which the XML
-- says is on purpose.
--------------------------------------------------------------------------------

local addonName, addon = ...

local Art = addon.UnitFrames.Art
local Modern = Art.Modern

local FAMILY = Modern.FAMILY.TargetofTarget
local PARTY = Modern.FAMILY.Party

local spec = {
    width = 120,
    height = 49,
    onBase = { portrait = true, frameTexture = true },
}
Art.Frames.modern.targettarget = spec

spec.Regions = {
    -- BACKGROUND. The portrait under CircleMask over its own rect, as the
    -- XML anchors the mask; the engine's own round crop stays on (values.lua,
    -- ApplyPortrait). The frame art at its atlas size, centred.
    portrait = {
        layer = "BACKGROUND", sublevel = 1,
        w = 37, h = 37,
        point = "TOPLEFT", x = 5, y = -5,
        mask = { atlas = "CircleMask" },
    },
    frameTexture = {
        layer = "BACKGROUND", sublevel = 2,
        atlas = FAMILY,
        point = "CENTER", x = 0, y = 0,
    },
}

spec.DrawOrder = { "portrait", "frameTexture" }

-- The two bars. Each fill is the family's member for it, white, since the
-- colour is in the art (retail's lockColor), and the class, value and custom
-- modes tint it as they tint a file. Each mask stands off its bar as the
-- override and the XML anchor it, at the member's size. The power bar names
-- its family prefix, and the state picks the member for the unit's power
-- (values.lua, ApplyPowerAtlas); the mana fill is the one at build and the
-- fallback. No predictionAtlas: the client builds this frame with no heal
-- prediction.
spec.Bars = {
    health = {
        w = 70, h = 10,
        point = "TOPLEFT", x = 45, y = -17.5,
        atlas = FAMILY .. "-Bar-Health",
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

-- Text. The name is the override's: centred, 68 wide, its centre at 78, -11;
-- the box's width and alignment are the style's settings, whose defaults
-- are these numbers (text.lua, MODERN_NAME). The dead and unconscious texts
-- sit at the health bar's centre in the bar's own layer, and tot.lua shows
-- one or the other.
spec.Text = {
    name = {
        layer = "OVERLAY",
        font = "GameFontNormalSmall",
        w = 68, h = 10,
        justifyH = "CENTER",
        point = "CENTER", relPoint = "TOPLEFT", x = 78, y = -11,
    },
    dead = {
        layer = "ARTWORK",
        font = "GameFontNormalSmall",
        justifyH = "CENTER", justifyV = "MIDDLE",
        point = "CENTER", relPoint = "TOPLEFT", x = 80, y = -22.5,
    },
    unconscious = {
        layer = "ARTWORK",
        font = "GameFontNormalSmall",
        justifyH = "CENTER", justifyV = "MIDDLE",
        point = "CENTER", relPoint = "TOPLEFT", x = 80, y = -22.5,
    },
}

-- Four debuffs in a 2 by 2 grid off the right edge, from the Debuff1 to
-- Debuff4 anchors of the template: the first TOPLEFT to the frame's TOPRIGHT
-- at 4, -10, each next 1 to the right or 1 below. The same grid as the
-- Classic frame's, off a wider frame.
spec.Auras = {
    point = "TOPLEFT", relPoint = "TOPRIGHT", x = 4, y = -10,
    spacing = 1, lineSpacing = 1, perLine = 2,
}

-- The manifest: what this spec can ask for. The pet's spec adds the
-- family's members it alone draws.
do
    local names = {
        FAMILY, "CircleMask",
        FAMILY .. "-Bar-Health",
        PARTY .. "-Bar-Health-Mask", PARTY .. "-Bar-Mana-Mask",
    }
    for _, name in ipairs(Modern.PowerFills(FAMILY)) do names[#names + 1] = name end
    Modern.Register(names)
end
