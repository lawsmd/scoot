--------------------------------------------------------------------------------
-- forever/unitframes/modern/artplayer.lua
-- The Modern player frame's art, as data: retail's PlayerFrame, transcribed
-- from Mainline/PlayerFrame.xml and PlayerFrame.lua on the live 12.1.5
-- source. The format is in art.lua beside this folder, with the Modern
-- fields the Classic specs never use.
--
-- The XML is the frame at rest, and PlayerFrame_ToPlayerArt rewrites several
-- numbers on world entry: the health bar lands at TOPLEFT 85, -41 at height
-- 19 (the XML's -40 and 20), its mask at the bar's TOPLEFT -2, 6 at height
-- 31, the power bar 124 by 10 at 85, -61 with its mask 128 wide, the status
-- glow at TOPLEFT 18, -14 (the XML's 17), and the flash at CENTER -1.5, 1.
-- The Lua's numbers are the ones below.
--
-- Host and layer follow the painter's three levels: PlayerFrameContainer's
-- regions (the portrait, the frame art, the flash) on the base frame, the
-- two bars one level up, and both PlayerFrameContent children on artFrame.
-- Retail orders the two content children by creation, the contextual one
-- over the main one, so the contextual icons take OVERLAY sublevels above
-- the status glow here; a FontString draws over every texture of its own
-- layer whatever the sublevels say, which is what retail's name over its
-- OVERLAY 2 glow relies on too.
--------------------------------------------------------------------------------

local addonName, addon = ...

local Art = addon.UnitFrames.Art
local Modern = Art.Modern

local FAMILY = Modern.FAMILY.Player
local Shared = Modern.Shared

local spec = {
    width = 232,
    height = 100,
    hitInsets = { left = 6, right = 0, top = 4, bottom = 9 },
    onBase = { portrait = true, frameTexture = true, frameFlash = true },
}
Art.Frames.modern.player = spec

spec.Regions = {
    -- BACKGROUND, the container. The portrait under its own atlas mask over
    -- the same rect; disableMasking keeps the engine's round crop off it, as
    -- the XML's key does, so the mask alone shapes the face. The frame art
    -- at its atlas size, unsnapped as the XML has it.
    portrait = {
        layer = "BACKGROUND", sublevel = 1,
        w = 60, h = 60,
        point = "TOPLEFT", x = 24, y = -19,
        mask = { atlas = "UI-HUD-UnitFrame-Player-Portrait-Mask" },
        disableMasking = true,
    },
    frameTexture = {
        layer = "BACKGROUND", sublevel = 2,
        atlas = FAMILY,
        point = "CENTER", x = 0, y = 0,
        snap = false,
    },
    -- The threat flash, hidden; nothing drives it until the threat read is
    -- known plain on the beta.
    frameFlash = {
        layer = "OVERLAY",
        atlas = FAMILY .. "-InCombat",
        point = "CENTER", x = -1.5, y = 1,
        snap = false,
        hidden = true,
    },

    -- OVERLAY on artFrame. The status glow breathes in the state's colour
    -- (player.lua); the rest loop is a 42-frame sheet, 30 by 30 centred
    -- where retail's 20 by 20 holder puts it (TOPLEFT 64, -6, so its centre
    -- at 74, -16).
    statusTexture = {
        layer = "OVERLAY", sublevel = 1,
        atlas = FAMILY .. "-Status",
        point = "TOPLEFT", x = 18, y = -14,
        pulse = true,
        hidden = true,
    },
    restLoop = {
        layer = "OVERLAY", sublevel = 2,
        atlas = "UI-HUD-UnitFrame-Player-Rest-Flipbook",
        w = 30, h = 30,
        point = "CENTER", relPoint = "TOPLEFT", x = 74, y = -16,
        flipbook = { rows = 7, columns = 6, frames = 42, duration = 1.5 },
        hidden = true,
    },
    -- The contextual icons. Leader and guide share a spot; attack and the
    -- corner embellishment nearly share one, and one of each pair shows.
    leaderIcon = {
        layer = "OVERLAY", sublevel = 3,
        atlas = Shared.leaderIcon,
        point = "TOPLEFT", x = 86, y = -10,
        hidden = true,
    },
    guideIcon = {
        layer = "OVERLAY", sublevel = 3,
        atlas = Shared.guideIcon,
        point = "TOPLEFT", x = 86, y = -10,
        hidden = true,
    },
    roleIcon = {
        layer = "OVERLAY", sublevel = 3,
        atlas = Shared.roleTank, useAtlasSize = false,
        w = 12, h = 12,
        point = "TOPLEFT", x = 196, y = -27,
        hidden = true,
    },
    attackIcon = {
        layer = "OVERLAY", sublevel = 3,
        atlas = "UI-HUD-UnitFrame-Player-CombatIcon",
        point = "TOPLEFT", x = 64, y = -62,
        hidden = true,
    },
    cornerIcon = {
        layer = "OVERLAY", sublevel = 3,
        atlas = FAMILY .. "-CornerEmbellishment",
        point = "TOPLEFT", x = 58.5, y = -53.5,
    },
    -- No atlas at build: the faction's badge is written by the state.
    pvpIcon = {
        layer = "OVERLAY", sublevel = 4,
        point = "TOP", relPoint = "TOPLEFT", x = 25, y = -50,
        hidden = true,
    },
}

spec.DrawOrder = {
    "portrait", "frameTexture", "frameFlash",
    "statusTexture", "restLoop",
    "leaderIcon", "guideIcon", "roleIcon", "attackIcon", "cornerIcon", "pvpIcon",
}

-- The two bars. Each fill is the family's member for it, white, since the
-- colour is in the art (retail's lockColor), and the class, value and custom
-- modes tint it as they tint a file. Each mask stands off its bar as
-- PlayerFrame_ToPlayerArt anchors it and takes the size that function
-- writes. The power bar names its family prefix, and the state picks the
-- member for the unit's power (values.lua, ApplyPowerAtlas); the mana fill
-- is the one at build and the fallback. predictionAtlas is the heal
-- prediction segments' fill, the one PlayerFrameBarSegmentTemplate names.
spec.Bars = {
    health = {
        w = 124, h = 19,
        point = "TOPLEFT", x = 85, y = -41,
        atlas = FAMILY .. "-Bar-Health",
        predictionAtlas = FAMILY .. "-Bar-Health-Status",
        color = { 1, 1, 1 },
        snap = false,
        mask = { atlas = FAMILY .. "-Bar-Health-Mask", point = "TOPLEFT", x = -2, y = 6, h = 31 },
    },
    power = {
        w = 124, h = 10,
        point = "TOPLEFT", x = 85, y = -61,
        atlas = FAMILY .. "-Bar-Mana",
        atlasPrefix = FAMILY .. "-Bar-",
        statusAtlas = FAMILY .. "-Bar-Mana-Status",
        color = { 1, 1, 1 },
        snap = false,
        mask = { atlas = FAMILY .. "-Bar-Mana-Mask", point = "TOPLEFT", x = -2, y = 2, w = 128 },
    },
}

-- Text, every string in OVERLAY as retail has it. The bar values sit at
-- their container's centre, translated to the frame: the health container
-- is 124 by 19 at 85, -41, so its centre is 147, -50.5, and its Left and
-- Right strings 2 in from its ends; the power bar's centre is 147, -66. The
-- name's box is retail's 96, which the spec answers while no width is
-- stored (text.lua, NameWidth), and reads left as retail's does.
spec.Text = {
    name = {
        layer = "OVERLAY",
        font = "GameFontNormalSmall",
        w = 96, h = 12,
        justifyH = "LEFT", justifyV = "MIDDLE",
        point = "TOPLEFT", x = 88, y = -27,
    },
    level = {
        layer = "OVERLAY",
        font = "GameNormalNumberFont",
        justifyH = "RIGHT", justifyV = "MIDDLE",
        point = "TOPRIGHT", x = -24.5, y = -28,
    },
    healthValue = {
        layer = "OVERLAY",
        font = "TextStatusBarText",
        point = "CENTER", relPoint = "TOPLEFT", x = 147, y = -50.5,
        sides = {
            left = { point = "LEFT", relPoint = "TOPLEFT", x = 87, y = -50.5 },
            right = { point = "RIGHT", relPoint = "TOPLEFT", x = 207, y = -50.5 },
        },
    },
    powerValue = {
        layer = "OVERLAY",
        font = "TextStatusBarText",
        point = "CENTER", relPoint = "TOPLEFT", x = 147, y = -66,
        sides = {
            left = { point = "LEFT", relPoint = "TOPLEFT", x = 87, y = -66 },
            right = { point = "RIGHT", relPoint = "TOPLEFT", x = 207, y = -66 },
        },
    },
}

-- The aura rows, off by default: retail's player auras are BuffFrame's, as
-- vanilla's are. A Camelot addition laid out as retail lays the target's
-- rows: the first icon 5 in and 9 up from the frame art's bottom-left
-- corner (TargetFrame.lua's AURA_START_X and AURA_START_Y against art
-- centred on the frame; the player's is 198 by 71, so its bottom edge sits
-- 14.5 up), carried right to the bars' edge plus 2 as the target's rows
-- stand off its bar, since the portrait is on the left here. Mirrored, the
-- rows hang 6 under the art's top edge.
spec.Auras = {
    x = 87, y = 23.5, mirrorY = -20.5,
    spacing = 3, lineSpacing = 3, blockGap = 3,
}

-- The manifest: what this spec and player.lua can ask for.
do
    local names = {
        FAMILY, FAMILY .. "-InCombat", FAMILY .. "-Status", FAMILY .. "-CornerEmbellishment",
        "UI-HUD-UnitFrame-Player-Portrait-Mask",
        "UI-HUD-UnitFrame-Player-Rest-Flipbook",
        "UI-HUD-UnitFrame-Player-CombatIcon",
        FAMILY .. "-Bar-Health", FAMILY .. "-Bar-Health-Status", FAMILY .. "-Bar-Health-Mask",
        FAMILY .. "-Bar-Mana-Status", FAMILY .. "-Bar-Mana-Mask",
        "UI-HUD-UnitFrame-Player-GroupIndicatorLeft",
        "UI-HUD-UnitFrame-Player-GroupIndicatorRight",
        "_UI-HUD-UnitFrame-Player-GroupIndicatorMid",
    }
    for _, name in ipairs(Modern.PowerFills(FAMILY)) do names[#names + 1] = name end
    Modern.Register(names)
end
