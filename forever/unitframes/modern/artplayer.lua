--------------------------------------------------------------------------------
-- forever/unitframes/modern/artplayer.lua
-- The Modern player frame's art, as data: the player frame this client draws
-- itself, transcribed from the Forever build's own files (build
-- 1.60.1.70450): retail's Mainline/PlayerFrame.xml and PlayerFrame.lua under
-- the Camelot override layer, Blizzard_UnitFrame/Camelot/PlayerFrame.lua and
-- PlayerFrameTemplates.xml. The format is in art.lua beside this folder,
-- with the Modern fields the Classic specs never use.
--
-- The XML is the frame at rest, and the override's load hook and its art
-- functions rewrite several numbers: the name is centred in a 116 box at
-- CENTER 149, -37; the level moves into a small circle at BOTTOMLEFT 13, 7
-- and goes white; the health container lands at TOPLEFT 87, -46, 15 tall,
-- with the bar itself 20 tall three up from its top, so the bar is at
-- TOPLEFT 87, -43, its mask at the bar's TOPLEFT -2, 6 at height 32; the
-- power bar is 124 by 10 at 87, -61 with its mask 128 wide; the status glow
-- sits at TOPLEFT 17, -14 and the flash at CENTER 0, 0; the PvP badge is the
-- circle with a crest at four fifths, TOP to TOPLEFT 22, -65. The override's
-- numbers are the ones below, with one departure.
--
-- The departure is LIFT. The client's player and target frames are both 232
-- by 100 with their art centred, and the player's art (198 by 71) is four
-- units taller than the target's (192 by 67), its bar area drawn two units
-- lower. The override's bars follow the art, so at one Edit Mode height the
-- client's own player frame sits its health bar 2 units under the target's
-- and its name and power bar 1 under. Here every piece bound to the art
-- lifts by LIFT, the name and the power bar take the target's heights, and
-- the level circle and the badge, which the client places alike on both
-- frames, stay, so the two frames line up at one y. The portrait keeps its
-- place in its ring, which is two units larger than the target's.
--
-- Host and layer follow the painter's three levels: PlayerFrameContainer's
-- regions (the portrait, the frame art, the flash) on the base frame, the
-- two bars one level up, and both PlayerFrameContent children on artFrame.
-- The client orders the two content children by creation, the contextual one
-- over the main one, so the contextual icons take OVERLAY sublevels above
-- the main child's circle and badge here; a FontString draws over every
-- texture of its own layer whatever the sublevels say, which is what the
-- name over its OVERLAY 2 glow relies on too.
--------------------------------------------------------------------------------

local addonName, addon = ...

local Art = addon.UnitFrames.Art
local Modern = Art.Modern

local FAMILY = Modern.FAMILY.Player
local Shared = Modern.Shared

-- The lift (the header): the units every art-bound piece rises by.
local LIFT = 2

local spec = {
    width = 232,
    height = 100,
    hitInsets = { left = 6, right = 0, top = 4 - LIFT, bottom = 9 + LIFT },
    onBase = { portrait = true, frameTexture = true, frameFlash = true },
    lift = LIFT, -- for the pieces player.lua anchors to the frame itself
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
        point = "TOPLEFT", x = 24, y = -19 + LIFT,
        mask = { atlas = "UI-HUD-UnitFrame-Player-Portrait-Mask" },
        disableMasking = true,
    },
    frameTexture = {
        layer = "BACKGROUND", sublevel = 2,
        atlas = FAMILY,
        point = "CENTER", x = 0, y = LIFT,
        snap = false,
    },
    -- The threat flash, hidden; nothing drives it until the threat read is
    -- known plain on the beta. The override centres it on the frame.
    frameFlash = {
        layer = "OVERLAY",
        atlas = FAMILY .. "-InCombat",
        point = "CENTER", x = 0, y = LIFT,
        snap = false,
        hidden = true,
    },

    -- OVERLAY on artFrame, the main child first. The status glow breathes in
    -- the state's colour (player.lua); the rest loop is a 42-frame sheet, 30
    -- by 30 centred where the XML's 20 by 20 holder puts it (TOPLEFT 64, -6,
    -- so its centre at 74, -16). The level circle is shown by the override's
    -- load hook and the level string hangs in it (spec.Text.level); the PvP
    -- badge takes a crest by faction at runtime, at the template's scale.
    statusTexture = {
        layer = "OVERLAY", sublevel = 1,
        atlas = FAMILY .. "-Status",
        point = "TOPLEFT", x = 17, y = -14 + LIFT,
        pulse = true,
        hidden = true,
    },
    restLoop = {
        layer = "OVERLAY", sublevel = 2,
        atlas = "UI-HUD-UnitFrame-Player-Rest-Flipbook",
        w = 30, h = 30,
        point = "CENTER", relPoint = "TOPLEFT", x = 74, y = -16 + LIFT,
        flipbook = { rows = 7, columns = 6, frames = 42, duration = 1.5 },
        hidden = true,
    },
    levelCircle = {
        layer = "OVERLAY", sublevel = 3,
        atlas = Shared.levelCircle,
        point = "BOTTOMLEFT", x = 13, y = 7,
    },
    pvpIcon = {
        layer = "OVERLAY", sublevel = 4,
        point = "TOP", relPoint = "TOPLEFT", x = 22, y = -65,
        scale = 0.8,
        hidden = true,
    },
    -- The contextual child. Leader and guide share a spot; the attack icon
    -- and the corner embellishment nearly share one, and one of each pair
    -- shows. No role icon: the override never shows one on this client.
    leaderIcon = {
        layer = "OVERLAY", sublevel = 5,
        atlas = Shared.leaderIcon,
        point = "TOPLEFT", x = 86, y = -10 + LIFT,
        hidden = true,
    },
    guideIcon = {
        layer = "OVERLAY", sublevel = 5,
        atlas = Shared.guideIcon,
        point = "TOPLEFT", x = 86, y = -10 + LIFT,
        hidden = true,
    },
    cornerIcon = {
        layer = "OVERLAY", sublevel = 5,
        atlas = FAMILY .. "-CornerEmbellishment",
        point = "TOPLEFT", x = 58.5, y = -53.5 + LIFT,
    },
    attackIcon = {
        layer = "OVERLAY", sublevel = 6,
        atlas = "UI-HUD-UnitFrame-Player-CombatIcon",
        point = "TOPLEFT", x = 64, y = -62 + LIFT,
        hidden = true,
    },
}

spec.DrawOrder = {
    "portrait", "frameTexture", "frameFlash",
    "statusTexture", "restLoop", "levelCircle", "pvpIcon",
    "leaderIcon", "guideIcon", "cornerIcon", "attackIcon",
}

-- The two bars. Each fill is the family's member for it, white, since the
-- colour is in the art (retail's lockColor), and the class, value and custom
-- modes tint it as they tint a file. Each mask stands off its bar as the
-- override anchors it and takes the size the override writes. The power bar
-- names its family prefix, and the state picks the member for the unit's
-- power (values.lua, ApplyPowerAtlas); the mana fill is the one at build and
-- the fallback. predictionAtlas is the heal prediction segments' fill, the
-- one PlayerFrameBarSegmentTemplate names. The health bar lifts with the
-- art; the power bar sits at the target's -60, one unit above the client's
-- own -61 (LIFT, the header). The max health loss spans the health
-- container, 3 under the bar's top and 15 tall, with the divider at its
-- seam; the cost segment is the client's ManaCostPredictionBar on the
-- statusAtlas member (barsegments.lua).
spec.Bars = {
    health = {
        w = 124, h = 20,
        point = "TOPLEFT", x = 87, y = -43 + LIFT,
        atlas = FAMILY .. "-Bar-Health",
        predictionAtlas = FAMILY .. "-Bar-Health-Status",
        color = { 1, 1, 1 },
        snap = false,
        mask = { atlas = FAMILY .. "-Bar-Health-Mask", point = "TOPLEFT", x = -2, y = 6, h = 32 },
        loss = {
            atlas = FAMILY .. "-Bar-TempHPLoss",
            y = -3, h = 15,
            divider = {
                atlas = FAMILY .. "-Bar-TempHPLoss-Divider",
                shadow = FAMILY .. "-Bar-TempHPLoss-Divider-Shadow",
                mask = FAMILY .. "-Bar-TempHPLoss-Divider-Mask",
            },
        },
    },
    power = {
        w = 124, h = 10,
        point = "TOPLEFT", x = 87, y = -60,
        atlas = FAMILY .. "-Bar-Mana",
        atlasPrefix = FAMILY .. "-Bar-",
        statusAtlas = FAMILY .. "-Bar-Mana-Status",
        cost = true,
        color = { 1, 1, 1 },
        snap = false,
        mask = { atlas = FAMILY .. "-Bar-Mana-Mask", point = "TOPLEFT", x = -2, y = 2, w = 128 },
    },
}

-- Text, every string in OVERLAY as the client has it. The name is the
-- override's: centred, 116 wide, its centre at 149, -37 on the client and at
-- the target's -36 here (LIFT, the header). The level hangs at the circle's
-- centre half a unit down, on the client's large white number font, and its
-- default colour is that white (text.lua, DefaultColor). The bar values sit
-- at their container's centre, translated to the frame: the health container
-- is 124 by 15 at 87, -46, so its centre is 149, -53.5, lifted with its bar,
-- and its Left and Right strings 2 in from its ends; the power bar's centre
-- is 149, -66 on the client and -65 here, with its bar. The name box's width
-- and alignment are the style's settings, whose defaults are these numbers
-- (text.lua, MODERN_NAME).
spec.Text = {
    name = {
        layer = "OVERLAY",
        font = "GameFontNormalSmall",
        w = 116, h = 12,
        justifyH = "CENTER", justifyV = "MIDDLE",
        point = "CENTER", relPoint = "TOPLEFT", x = 149, y = -36,
    },
    level = {
        layer = "OVERLAY",
        font = "WhiteLargeNumberFont",
        justifyH = "CENTER", justifyV = "MIDDLE",
        point = "CENTER", relTo = "levelCircle", x = 0, y = -0.5,
        defaultColor = { 1, 1, 1 },
    },
    healthValue = {
        layer = "OVERLAY",
        font = "TextStatusBarText",
        point = "CENTER", relPoint = "TOPLEFT", x = 149, y = -53.5 + LIFT,
        sides = {
            left = { point = "LEFT", relPoint = "TOPLEFT", x = 89, y = -53.5 + LIFT },
            right = { point = "RIGHT", relPoint = "TOPLEFT", x = 209, y = -53.5 + LIFT },
        },
    },
    powerValue = {
        layer = "OVERLAY",
        font = "TextStatusBarText",
        point = "CENTER", relPoint = "TOPLEFT", x = 149, y = -65,
        sides = {
            left = { point = "LEFT", relPoint = "TOPLEFT", x = 89, y = -65 },
            right = { point = "RIGHT", relPoint = "TOPLEFT", x = 209, y = -65 },
        },
    },
}

-- The aura rows, off by default: the client's player auras are BuffFrame's,
-- as vanilla's are. A Camelot addition laid out as the target's rows are:
-- the first icon 5 in and 9 up from the frame art's bottom-left corner
-- (TargetFrame.lua's AURA_START_X and AURA_START_Y against art centred on
-- the frame; the player's is 198 by 71, so its bottom edge sits 14.5 up,
-- lifted with the art), carried right to the bars' edge plus 2 as the
-- target's rows stand off its bar, since the portrait is on the left here.
-- Mirrored, the rows hang 6 under the art's top edge.
spec.Auras = {
    x = 89, y = 23.5 + LIFT, mirrorY = -20.5 + LIFT,
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
