--------------------------------------------------------------------------------
-- forever/unitframes/artplayer.lua
-- The Classic player frame's art, as data. Transcribed from
-- Classic/PlayerFrame.xml on origin/classic_era; the format is in art.lua.
--------------------------------------------------------------------------------

local addonName, addon = ...

local Art = addon.UnitFrames.Art
local Paths = Art.Paths

-- Frame rect and the hit rect the vanilla frame carries. The hit insets matter
-- because the border art is much smaller than the 232x100 button around it.
local spec = {
    width = 232,
    height = 100,
    hitInsets = { left = 21, right = 19, top = 12, bottom = 15 },
    -- Built on the base frame, under the bars. Everything else goes on artFrame.
    onBase = { flash = true, background = true, portrait = true },
}
Art.Frames.player = spec

-- The level disc, the small ring at the portrait's lower left. Vanilla's own
-- anchors miss it: measured off UI-TargetingFrame as the border draws it, the
-- disc centres 37.25 from the frame's left and 30.5 up from its bottom, while
-- PlayerLevelText centres at 35.25 and the art inside both state icons at 35.5.
-- The numbers below stay Blizzard's, and everything that sits in the disc
-- carries this nudge on top, so zeroing it gives the vanilla placement back.
local DISC_NUDGE = { x = 2, y = 0 }
spec.DiscNudge = DISC_NUDGE

spec.Regions = {
    -- BACKGROUND
    flash = {
        layer = "BACKGROUND",
        path = Paths.flash,
        w = 242, h = 93,
        point = "TOPLEFT", x = -3, y = -4,
        coords = { 0.9453125, 0, 0, 0.181640625 },
        hidden = true,
    },
    background = {
        layer = "BACKGROUND",
        w = 119, h = 41,
        point = "TOPLEFT", x = 89.5, y = -26,
        color = { 0, 0, 0, 0.5 },
    },

    -- ARTWORK: the portrait sits under the border so the ring frames it.
    portrait = {
        layer = "ARTWORK",
        w = 64, h = 64,
        point = "TOPLEFT", x = 24, y = -16,
    },

    -- BORDER: the frame itself, over the portrait and the bars.
    border = {
        layer = "BORDER",
        path = Paths.border,
        w = 193, h = 77,
        point = "CENTER", x = 0, y = 0,
        coords = { 0.85546875, 0.1015625, 0.0625, 0.6640625 },
        border = true,
    },

    -- ARTWORK over the bars: rested glow and the attacked backing.
    playerStatus = {
        layer = "ARTWORK",
        path = Paths.playerStatus,
        w = 190, h = 66,
        point = "TOPLEFT", x = 19, y = -12,
        coords = { 0, 0.74609375, 0, 0.53125 },
        blend = "ADD",
        pulse = true,
        hidden = true,
    },
    attackBackground = {
        layer = "ARTWORK",
        path = Paths.attackBG,
        w = 32, h = 32,
        point = "TOPLEFT", x = 19, y = -54,
        nudge = DISC_NUDGE,
        hidden = true,
    },

    -- OVERLAY: state icons. Rest and combat share one sheet, split left/right,
    -- with the glow pair on the sheet's lower half.
    restIcon = {
        layer = "OVERLAY",
        path = Paths.stateIcon,
        w = 31, h = 33,
        point = "TOPLEFT", x = 19.5, y = -52,
        coords = { 0, 0.5, 0, 0.421875 },
        nudge = DISC_NUDGE,
        hidden = true,
    },
    attackIcon = {
        layer = "OVERLAY",
        path = Paths.stateIcon,
        w = 32, h = 32,
        point = "TOPLEFT", x = 20.5, y = -52,
        coords = { 0.5, 1.0, 0, 0.484375 },
        nudge = DISC_NUDGE,
        hidden = true,
    },
    restGlow = {
        layer = "OVERLAY",
        path = Paths.stateIcon,
        w = 32, h = 32,
        point = "TOPLEFT", x = 19.5, y = -52,
        coords = { 0, 0.5, 0.5, 1.0 },
        blend = "ADD",
        nudge = DISC_NUDGE,
        pulse = true,
        hidden = true,
    },
    attackGlow = {
        layer = "OVERLAY",
        path = Paths.stateIcon,
        w = 32, h = 32,
        point = "TOPLEFT", x = 20.5, y = -52,
        coords = { 0.5, 1.0, 0.5, 1.0 },
        blend = "ADD",
        vertex = { 1.0, 0, 0 },
        nudge = DISC_NUDGE,
        pulse = true,
        hidden = true,
    },
    leaderIcon = {
        layer = "OVERLAY",
        path = Paths.leaderIcon,
        w = 16, h = 16,
        point = "TOPLEFT", x = 28, y = -14,
        hidden = true,
    },
    masterLooterIcon = {
        layer = "OVERLAY",
        path = Paths.masterLooter,
        w = 16, h = 16,
        point = "TOPLEFT", x = 64, y = -14,
        hidden = true,
    },
}

-- Creation order, which is draw order for two regions sharing a layer. The
-- glows have to be built after the icons they sit on: vanilla gets that by
-- putting them in a frame raised three levels, and a flat rebuild gets it from
-- the order alone. Anything else here is ordered for readability.
spec.DrawOrder = {
    "flash", "background", "portrait",
    "border",
    "playerStatus", "attackBackground",
    "restIcon", "attackIcon",
    "restGlow", "attackGlow",
    "leaderIcon", "masterLooterIcon",
}

-- The two bars. Both take the same fill texture. The power bar's colour is in
-- the XML; the health bar's is not, because vanilla sets it from Lua in
-- UnitFrame.lua's health update: flat green, and grey while disconnected. There
-- is no class colouring on the vanilla player frame at all, so green is the
-- Classic-accurate default and a class-colour toggle is a Camelot addition.
spec.Bars = {
    health = {
        w = 119, h = 12,
        point = "TOPLEFT", x = 90, y = -45,
        texture = Paths.statusBar,
        color = { 0.0, 1.0, 0.0 },
    },
    power = {
        w = 119, h = 12,
        point = "TOPLEFT", x = 90, y = -56,
        texture = Paths.statusBar,
        color = { 0, 0, 1.0 },
    },
}

-- Text. Every one of these sits in the BORDER layer in the XML, in the same
-- block as the frame art and after it, so the border draws under them and both
-- the state art (ARTWORK) and the state icons (OVERLAY) draw over them.
--
-- That layering is load-bearing rather than incidental. The level number and
-- the rested zZz icon occupy the same spot by design: level centres at 35.25,
-- 30 up from the bottom, and the rest icon covers y -52 to -85 around it.
-- Vanilla never hides the level; it lets the OVERLAY icon cover the BORDER
-- text. Put the text in OVERLAY and the number draws through the icon instead.
--
-- The XML marks the name and the level "re-anchored in code". Only the vehicle
-- art swap does that, and it moves the name alone, so these anchors stand.
spec.Text = {
    name = {
        layer = "BORDER",
        font = "GameFontNormalSmall",
        w = 100, h = 12,
        point = "CENTER", x = 34, y = 15,
    },
    level = {
        layer = "BORDER",
        font = "GameNormalNumberFont",
        justifyH = "RIGHT", justifyV = "MIDDLE",
        point = "CENTER", relPoint = "BOTTOMLEFT", x = 35.25, y = 30,
        nudge = DISC_NUDGE,
    },
    healthValue = {
        layer = "BORDER",
        font = "TextStatusBarText",
        point = "CENTER", x = 34, y = -1,
    },
    powerValue = {
        layer = "BORDER",
        font = "TextStatusBarText",
        point = "CENTER", x = 34, y = -12,
    },
}
