--------------------------------------------------------------------------------
-- forever/unitframes/modern/arttarget.lua
-- The Modern target frame's art, as data, and the focus frame's, which the
-- client builds from the same template: the target frame this client draws
-- itself, transcribed from the Forever build's own files (build
-- 1.60.1.70450): retail's Mainline/TargetFrame.xml and TargetFrame.lua under
-- the Camelot override layer, Blizzard_UnitFrame/Camelot/TargetFrame.lua,
-- TargetFrameTemplates.xml and TargetFrameUtils.lua. The format is in
-- art.lua beside this folder, with the Modern fields the Classic specs never
-- use.
--
-- The frame is the player's mirror: the portrait on the right, the XML
-- anchoring from TOPRIGHT. The XML is the frame at rest, and the override's
-- load hook and its one health shape rewrite several numbers; where the XML
-- anchors a piece to another piece, the number below is translated to the
-- frame's own corner:
--   the reputation strip sits at TOPRIGHT -82, -26, so its top-right corner
--   is at 150, -26; the name, 117 wide and centred, hangs TOPLEFT at that
--   corner -126, -4, so its box starts at 24, -30 and its centre is 82.5, -36;
--   the health container is 126 by 15 with its BOTTOMRIGHT at the frame's
--   LEFT 147, -9, so it runs from 21, -44 to 147, -59, and the bar, 126 by
--   20, sits at the container's TOPLEFT 0, 3: TOPLEFT 21, -41, with the mask
--   at the container's TOPLEFT -1, 9, which is the bar's TOPLEFT -1, 6;
--   the power bar, 134 by 10, hangs TOPRIGHT at the container's BOTTOMRIGHT
--   4, -1: TOPLEFT 17, -60; the level sits in a small circle at BOTTOMRIGHT
--   -13, 7 and the skull at the circle's centre; the flash is centred at
--   -1, 1; the PvP badge, the circle's crest at four fifths, hangs TOP at
--   TOPRIGHT -24, -65.
-- The one health shape is the override's too: every classification keeps
-- it, where live gives a minus mob a shorter bar. The frame art, the flash
-- and the power bar still change by classification (target.lua).
--
-- Host and layer follow the painter's three levels: TargetFrameContainer's
-- regions (the portrait, the frame art, the flash, the boss art) and the
-- main child's reputation strip on the base frame, the two bars one level
-- up, and the rest of both content children on artFrame. The client orders
-- the two content children by creation, the contextual one over the main
-- one, so the contextual icons take OVERLAY sublevels above the main child's
-- circle here; a FontString draws over every texture of its own layer.
--------------------------------------------------------------------------------

local addonName, addon = ...

local Art = addon.UnitFrames.Art
local Paths = Art.Paths
local Modern = Art.Modern

local FAMILY = Modern.FAMILY.Target
local Shared = Modern.Shared

local function build(hitInsets)
    local spec = {
        width = 232,
        height = 100,
        hitInsets = hitInsets,
        onBase = {
            portrait = true, frameTexture = true, reputationColor = true,
            frameFlash = true, bossArt = true,
        },
    }

    spec.Regions = {
        -- BACKGROUND, the container. The portrait under CircleMask a unit in
        -- from its top and its right, as the XML anchors the mask; the
        -- engine's own round crop stays on (values.lua, ApplyPortrait). The
        -- frame art at its atlas size, unsnapped as the XML has it, swapped
        -- for a rare or a minus mob. The reputation strip, the main child's,
        -- coloured by reaction (target.lua).
        portrait = {
            layer = "BACKGROUND", sublevel = 1,
            w = 58, h = 58,
            point = "TOPRIGHT", x = -26, y = -19,
            mask = { atlas = "CircleMask", point = "TOPLEFT", x = 0, y = -1, w = 57, h = 57 },
        },
        frameTexture = {
            layer = "BACKGROUND", sublevel = 2,
            atlas = FAMILY,
            atlasByState = {
                rare = "UI-HUD-UnitFrame-Target-Rare-PortraitOn",
                minus = "UI-HUD-UnitFrame-Target-MinusMob-PortraitOn",
            },
            point = "CENTER", x = 0, y = 0,
            snap = false,
        },
        reputationColor = {
            layer = "BACKGROUND", sublevel = 3,
            atlas = FAMILY .. "-Type",
            point = "TOPRIGHT", x = -82, y = -26,
        },
        -- ARTWORK on the container: the threat flash, hidden, which nothing
        -- drives until the threat read is known plain on the beta; the boss
        -- art, shown and re-anchored by classification (target.lua).
        frameFlash = {
            layer = "ARTWORK", sublevel = 1,
            atlas = FAMILY .. "-InCombat",
            atlasByState = { minus = "UI-HUD-UnitFrame-Target-MinusMob-PortraitOn-InCombat" },
            point = "CENTER", x = -1, y = 1,
            snap = false,
            hidden = true,
        },
        bossArt = {
            layer = "ARTWORK", sublevel = 2,
            atlas = FAMILY .. "-Boss-Gold",
            point = "TOPRIGHT", x = 0, y = 1,
            hidden = true,
        },

        -- OVERLAY on artFrame, the main child's circle first, then the
        -- contextual child's badge and icons. The skull sits at the circle's
        -- centre in place of the level; the raid marker at the portrait's
        -- top edge and the quest icon at its bottom edge, as the XML anchors
        -- them. No rare star and no battle pet icon: the override shows
        -- neither.
        levelCircle = {
            layer = "OVERLAY", sublevel = 1,
            atlas = Shared.levelCircle,
            point = "BOTTOMRIGHT", x = -13, y = 7,
        },
        pvpIcon = {
            layer = "OVERLAY", sublevel = 2,
            point = "TOP", relPoint = "TOPRIGHT", x = -24, y = -65,
            scale = 0.8,
            hidden = true,
        },
        skull = {
            layer = "OVERLAY", sublevel = 3,
            atlas = "UI-HUD-UnitFrame-Target-HighLevelTarget_Icon",
            point = "CENTER", relTo = "levelCircle", x = 0, y = 0,
            hidden = true,
        },
        leaderIcon = {
            layer = "OVERLAY", sublevel = 3,
            atlas = Shared.leaderIcon,
            point = "TOPRIGHT", x = -85, y = -8,
            hidden = true,
        },
        guideIcon = {
            layer = "OVERLAY", sublevel = 3,
            atlas = Shared.guideIcon,
            point = "TOPRIGHT", x = -85, y = -8,
            hidden = true,
        },
        raidTargetIcon = {
            layer = "OVERLAY", sublevel = 3,
            path = Paths.raidIcons,
            w = 26, h = 26,
            point = "CENTER", relTo = "portrait", relPoint = "TOP", x = 0, y = 0,
            hidden = true,
        },
        questIcon = {
            layer = "OVERLAY", sublevel = 3,
            atlas = FAMILY .. "-Boss-Quest",
            point = "CENTER", relTo = "portrait", relPoint = "BOTTOM", x = 0, y = 0,
            hidden = true,
        },
    }

    spec.DrawOrder = {
        "portrait", "frameTexture", "reputationColor", "frameFlash", "bossArt",
        "levelCircle", "pvpIcon", "skull", "leaderIcon", "guideIcon", "raidTargetIcon", "questIcon",
    }

    -- The two bars. Each fill is the family's member for it, white, since the
    -- colour is in the art (retail's lockColor), and the class, value and
    -- custom modes tint it as they tint a file. Each mask stands off its bar
    -- as the override and the XML anchor it, at the member's size. The power
    -- bar names its family prefix, and the state picks the member for the
    -- unit's power (values.lua, ApplyPowerAtlas); the mana fill is the one at
    -- build and the fallback. predictionAtlas is the heal prediction
    -- segments' fill, the one TargetFrameBarSegmentTemplate names. The max
    -- health loss spans the health container, 3 under the bar's top and 15
    -- tall, which the override sets; the override keeps one loss atlas for
    -- every classification (barsegments.lua).
    spec.Bars = {
        health = {
            w = 126, h = 20,
            point = "TOPLEFT", x = 21, y = -41,
            atlas = FAMILY .. "-Bar-Health",
            predictionAtlas = FAMILY .. "-Bar-Health-Status",
            color = { 1, 1, 1 },
            snap = false,
            mask = { atlas = FAMILY .. "-Bar-Health-Mask", point = "TOPLEFT", x = -1, y = 6 },
            loss = { atlas = FAMILY .. "-Bar-TempHPLoss", y = -3, h = 15 },
        },
        power = {
            w = 134, h = 10,
            point = "TOPLEFT", x = 17, y = -60,
            atlas = FAMILY .. "-Bar-Mana",
            atlasPrefix = FAMILY .. "-Bar-",
            statusAtlas = FAMILY .. "-Bar-Mana-Status",
            color = { 1, 1, 1 },
            snap = false,
            mask = { atlas = FAMILY .. "-Bar-Mana-Mask", point = "TOPLEFT", x = -61, y = 3 },
        },
    }

    -- Text, every string in OVERLAY as the client has it. The name is the
    -- override's: centred, 117 wide, its centre at 82.5, -36. The level
    -- hangs at the circle's centre half a unit down, on the client's large
    -- number font; its colour is the difficulty's or the gold (target.lua),
    -- which the client's CheckLevel writes over the font's white. The health
    -- strings sit at their container's centre, 84, -51.5, its Left 2 in and
    -- its Right 5 in from the container's ends; the power strings on the
    -- same centre line, 84, -65, its Left 2 in and its Right 3 in, the
    -- override's. The XML nudges the mana text 4 left of its bar, which on
    -- retail cancels the bar standing 4 right of the container; the
    -- override centres the bar on the container and keeps the nudge, so
    -- the client's own power number sits 4 left of its health number. The
    -- nudge is dropped here and the two numbers share a centre, the first
    -- look's one correction. The dead and unconscious texts share the
    -- health value's spot, and target.lua shows one or the other. The name
    -- box's width and alignment are the style's settings, whose defaults
    -- are these numbers (text.lua, MODERN_NAME).
    spec.Text = {
        name = {
            layer = "OVERLAY",
            font = "GameFontNormalSmall",
            w = 117, h = 12,
            justifyH = "CENTER", justifyV = "MIDDLE",
            point = "CENTER", relPoint = "TOPLEFT", x = 82.5, y = -36,
        },
        level = {
            layer = "OVERLAY",
            font = "WhiteLargeNumberFont",
            justifyH = "CENTER", justifyV = "MIDDLE",
            point = "CENTER", relTo = "levelCircle", x = 0, y = -0.5,
        },
        healthValue = {
            layer = "OVERLAY",
            font = "TextStatusBarText",
            point = "CENTER", relPoint = "TOPLEFT", x = 84, y = -51.5,
            sides = {
                left = { point = "LEFT", relPoint = "TOPLEFT", x = 23, y = -51.5 },
                right = { point = "RIGHT", relPoint = "TOPLEFT", x = 142, y = -51.5 },
            },
        },
        powerValue = {
            layer = "OVERLAY",
            font = "TextStatusBarText",
            point = "CENTER", relPoint = "TOPLEFT", x = 84, y = -65,
            sides = {
                left = { point = "LEFT", relPoint = "TOPLEFT", x = 19, y = -65 },
                right = { point = "RIGHT", relPoint = "TOPLEFT", x = 148, y = -65 },
            },
        },
        dead = {
            layer = "OVERLAY",
            font = "GameFontNormalSmall",
            justifyH = "CENTER", justifyV = "MIDDLE",
            point = "CENTER", relPoint = "TOPLEFT", x = 84, y = -51.5,
        },
        unconscious = {
            layer = "OVERLAY",
            font = "GameFontNormalSmall",
            justifyH = "CENTER", justifyV = "MIDDLE",
            point = "CENTER", relPoint = "TOPLEFT", x = 84, y = -51.5,
        },
    }

    -- The aura rows (auras.lua): the client anchors its container TOPLEFT to
    -- the frame art's BOTTOMLEFT at 5, 9, or BOTTOMLEFT to its TOPLEFT at -6
    -- with buffsOnTop, and the rows here hang off the same region, so they
    -- follow the art's size, which differs between the client's own set and
    -- retail's and changes for a minus mob. Icons 3 apart, lines 3 apart,
    -- the second block 3 below the first, the container's own line spacing.
    spec.Auras = {
        relTo = "frameTexture",
        x = 5, y = 9, mirrorY = -6,
        spacing = 3, lineSpacing = 3, blockGap = 3,
    }

    return spec
end

-- The template's insets for both.
Art.Frames.modern.target = build({ left = 0, right = 5, top = 4, bottom = 9 })
Art.Frames.modern.focus = build({ left = 0, right = 5, top = 4, bottom = 9 })

-- The manifest: what this spec and target.lua can ask for.
do
    local names = {
        FAMILY, FAMILY .. "-InCombat", FAMILY .. "-Type",
        "UI-HUD-UnitFrame-Target-Rare-PortraitOn",
        "UI-HUD-UnitFrame-Target-MinusMob-PortraitOn",
        "UI-HUD-UnitFrame-Target-MinusMob-PortraitOn-InCombat",
        FAMILY .. "-Boss-Gold", FAMILY .. "-Boss-Gold-Winged", FAMILY .. "-Boss-Rare-Silver-Winged",
        FAMILY .. "-Boss-Quest",
        "UI-HUD-UnitFrame-Target-HighLevelTarget_Icon",
        "CircleMask",
        FAMILY .. "-Bar-Health", FAMILY .. "-Bar-Health-Status", FAMILY .. "-Bar-Health-Mask",
        FAMILY .. "-Bar-Mana-Status", FAMILY .. "-Bar-Mana-Mask",
    }
    for _, name in ipairs(Modern.PowerFills(FAMILY)) do names[#names + 1] = name end
    Modern.Register(names)
end
