--------------------------------------------------------------------------------
-- forever/unitframes/arttarget.lua
-- The Classic target frame's art, as data, and the focus frame's, which is the
-- same template. Transcribed from TargetFrameTemplate in Classic/TargetFrame.xml
-- on origin/classic_era; the format is in art.lua.
--
-- The frame is the player's mirror: the portrait is on the right, and the XML
-- anchors everything from TOPRIGHT. The border is not a mirrored draw of the
-- player's, though. It reads the art the way it is authored, and its quad runs
-- 17.5 past the frame's right edge and 3.5 below it, which is the room the
-- elite dragon needs. All four border files share one size and one quad, so a
-- classification change is a texture swap and nothing else.
--------------------------------------------------------------------------------

local addonName, addon = ...

local Art = addon.UnitFrames.Art
local Paths = Art.Paths

-- The level ring. The target's level anchor resolves to the same texel of
-- UI-TargetingFrame as the player's (203.25, 66.5), mirrored, so it carries the
-- player's correction with the sign flipped (artplayer.lua, DISC_NUDGE).
local DISC_NUDGE = { x = -2, y = 0 }

local function build(hitInsets)
    local spec = {
        width = 232,
        height = 100,
        hitInsets = hitInsets,
        onBase = { flash = true, background = true, nameBackground = true, portrait = true },
        DiscNudge = DISC_NUDGE,
    }

    spec.Regions = {
        flash = {
            layer = "BACKGROUND",
            path = Paths.flash,
            w = 242, h = 93,
            point = "TOPLEFT", x = -6, y = -3,
            coords = { 0, 0.9453125, 0, 0.181640625 },
            hidden = true,
        },
        background = {
            layer = "BACKGROUND",
            w = 119, h = 41,
            point = "TOPRIGHT", x = -89.5, y = -26,
            color = { 0, 0, 0, 0.5 },
        },
        -- The strip behind the name, coloured by reaction (target.lua).
        nameBackground = {
            layer = "BORDER",
            path = Paths.nameBG,
            w = 119, h = 19,
            point = "TOPRIGHT", x = -90, y = -26,
        },
        portrait = {
            layer = "BORDER",
            w = 64, h = 64,
            point = "TOPRIGHT", x = -24, y = -16,
        },

        border = {
            layer = "BACKGROUND",
            path = Paths.border,
            w = 230, h = 99,
            point = "CENTER", x = 18.5, y = -4,
            coords = { 0.1015625, 1.0, 0.0078125, 0.78125 },
            border = true,
        },

        -- ARTWORK, all hidden until target.lua says otherwise. The skull is
        -- anchored to the level text in the XML; it takes the level's own
        -- numbers here, which is the same spot.
        skull = {
            layer = "ARTWORK",
            path = Paths.skull,
            w = 16, h = 16,
            point = "CENTER", relPoint = "BOTTOMRIGHT", x = -35.25, y = 30,
            nudge = DISC_NUDGE,
            hidden = true,
        },
        leaderIcon = {
            layer = "ARTWORK",
            path = Paths.leaderIcon,
            w = 16, h = 16,
            point = "TOPRIGHT", x = -28, y = -14,
            hidden = true,
        },
        pvpIcon = {
            layer = "ARTWORK",
            w = 64, h = 64,
            point = "TOPRIGHT", x = 19, y = -24,
            hidden = true,
        },
        raidTargetIcon = {
            layer = "ARTWORK",
            path = Paths.raidIcons,
            w = 26, h = 26,
            point = "CENTER", relPoint = "TOPRIGHT", x = -57, y = -18,
            hidden = true,
        },
    }

    spec.DrawOrder = {
        "flash", "background", "nameBackground", "portrait",
        "border",
        "skull", "leaderIcon", "pvpIcon", "raidTargetIcon",
    }

    spec.Bars = {
        health = {
            w = 119, h = 12,
            point = "TOPRIGHT", x = -90, y = -45,
            texture = Paths.statusBar,
            color = { 0.0, 1.0, 0.0 },
        },
        power = {
            w = 119, h = 12,
            point = "TOPRIGHT", x = -90, y = -56,
            texture = Paths.statusBar,
            color = { 0, 0, 1.0 },
        },
    }

    -- BACKGROUND in the XML, in the border's own block and after it.
    spec.Text = {
        name = {
            layer = "BACKGROUND",
            font = "GameFontNormalSmall",
            w = 100, h = 12,
            point = "CENTER", x = -34, y = 15,
        },
        level = {
            layer = "BACKGROUND",
            font = "GameNormalNumberFont",
            justifyH = "LEFT", justifyV = "MIDDLE",
            point = "CENTER", relPoint = "BOTTOMRIGHT", x = -35.25, y = 30,
            nudge = DISC_NUDGE,
        },
        healthValue = {
            layer = "BACKGROUND",
            font = "TextStatusBarText",
            point = "CENTER", x = -33, y = -1,
        },
        powerValue = {
            layer = "BACKGROUND",
            font = "TextStatusBarText",
            point = "CENTER", x = -33, y = -12,
        },
        -- Shares the health value's spot, as the XML has it. target.lua shows
        -- one or the other.
        dead = {
            layer = "BACKGROUND",
            font = "GameFontNormalSmall",
            point = "CENTER", x = -33, y = -1,
        },
    }

    return spec
end

-- The template's insets for both. TargetFrame's OnLoad narrows its own to
-- (96, 40, 10, 9), which suits a frame whose bars are mouse-enabled children
-- of their own. Here the click child is the one thing that takes a click, so
-- it covers the art.
Art.Frames.target = build({ left = 19, right = 21, top = 12, bottom = 15 })
Art.Frames.focus = build({ left = 19, right = 21, top = 12, bottom = 15 })
