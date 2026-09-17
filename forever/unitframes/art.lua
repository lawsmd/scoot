--------------------------------------------------------------------------------
-- forever/unitframes/art.lua
-- The Classic player frame's art, as data.
--
-- Every number here is Blizzard's own, read out of the vanilla PlayerFrame.xml
-- rather than measured off a screenshot, so the rebuild is a transcription. The
-- source is the classic_era branch of the UI source mirror:
--
--   git show origin/classic_era:Interface/AddOns/Blizzard_UnitFrame/Classic/PlayerFrame.xml
--
-- Every path below resolves by name in a 12.x client. Camelot references the
-- art and bundles none of it.
--
-- Two conventions carried over from the XML:
--
--   coords = { left, right, top, bottom } in SetTexCoord order. Where left is
--   GREATER than right the texture is mirrored horizontally. The border and the
--   flash are both authored that way, and the values are kept as written rather
--   than "corrected".
--
--   Offsets are TOPLEFT-relative with a negative Y running down the frame,
--   which is how the XML anchors them.
--------------------------------------------------------------------------------

local addonName, addon = ...

local Art = {}
addon.UnitFrames.Art = Art

--------------------------------------------------------------------------------
-- Paths
--------------------------------------------------------------------------------

local TARGETING = "Interface\\TargetingFrame\\"
local CHARACTER = "Interface\\CharacterFrame\\"
local GROUP     = "Interface\\GroupFrame\\"

Art.Paths = {
    border      = TARGETING .. "UI-TargetingFrame",
    flash       = TARGETING .. "UI-TargetingFrame-Flash",
    attackBG    = TARGETING .. "UI-TargetingFrame-AttackBackground",
    statusBar   = TARGETING .. "UI-StatusBar",
    playerStatus = CHARACTER .. "UI-Player-Status",
    stateIcon   = CHARACTER .. "UI-StateIcon",
    playTime    = CHARACTER .. "UI-Player-PlayTimeTired",
    leaderIcon  = GROUP .. "UI-Group-LeaderIcon",
    masterLooter = GROUP .. "UI-Group-MasterLooter",
}

-- Draw order for the art swatch dump. A path that fails to resolve draws blank,
-- which is the only way a missing file announces itself.
Art.ManifestOrder = {
    "border", "flash", "attackBG", "statusBar",
    "playerStatus", "stateIcon", "playTime",
    "leaderIcon", "masterLooter",
}

--------------------------------------------------------------------------------
-- The player frame
--------------------------------------------------------------------------------

-- Frame rect and the hit rect the vanilla frame carries. The hit insets matter
-- because the border art is much smaller than the 232x100 button around it.
Art.Player = {
    width = 232,
    height = 100,
    hitInsets = { left = 21, right = 19, top = 12, bottom = 15 },
}

Art.Player.Regions = {
    -- BACKGROUND
    flash = {
        layer = "BACKGROUND",
        path = Art.Paths.flash,
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
        path = Art.Paths.border,
        w = 193, h = 77,
        point = "CENTER", x = 0, y = 0,
        coords = { 0.85546875, 0.1015625, 0.0625, 0.6640625 },
    },

    -- ARTWORK over the bars: rested glow and the attacked backing.
    playerStatus = {
        layer = "ARTWORK",
        path = Art.Paths.playerStatus,
        w = 190, h = 66,
        point = "TOPLEFT", x = 19, y = -12,
        coords = { 0, 0.74609375, 0, 0.53125 },
        blend = "ADD",
        hidden = true,
    },
    attackBackground = {
        layer = "ARTWORK",
        path = Art.Paths.attackBG,
        w = 32, h = 32,
        point = "TOPLEFT", x = 19, y = -54,
        hidden = true,
    },

    -- OVERLAY: state icons. Rest and combat share one sheet, split left/right,
    -- with the glow pair on the sheet's lower half.
    restIcon = {
        layer = "OVERLAY",
        path = Art.Paths.stateIcon,
        w = 31, h = 33,
        point = "TOPLEFT", x = 19.5, y = -52,
        coords = { 0, 0.5, 0, 0.421875 },
        hidden = true,
    },
    attackIcon = {
        layer = "OVERLAY",
        path = Art.Paths.stateIcon,
        w = 32, h = 32,
        point = "TOPLEFT", x = 20.5, y = -52,
        coords = { 0.5, 1.0, 0, 0.484375 },
        hidden = true,
    },
    restGlow = {
        layer = "OVERLAY",
        path = Art.Paths.stateIcon,
        w = 32, h = 32,
        point = "TOPLEFT", x = 19.5, y = -52,
        coords = { 0, 0.5, 0.5, 1.0 },
        blend = "ADD",
        hidden = true,
    },
    attackGlow = {
        layer = "OVERLAY",
        path = Art.Paths.stateIcon,
        w = 32, h = 32,
        point = "TOPLEFT", x = 20.5, y = -52,
        coords = { 0.5, 1.0, 0.5, 1.0 },
        blend = "ADD",
        color = { 1.0, 0, 0 },
        hidden = true,
    },
    leaderIcon = {
        layer = "OVERLAY",
        path = Art.Paths.leaderIcon,
        w = 16, h = 16,
        point = "TOPLEFT", x = 28, y = -14,
        hidden = true,
    },
    masterLooterIcon = {
        layer = "OVERLAY",
        path = Art.Paths.masterLooter,
        w = 16, h = 16,
        point = "TOPLEFT", x = 64, y = -14,
        hidden = true,
    },
}

-- Creation order, which is draw order for two regions sharing a layer. The
-- glows have to be built after the icons they sit on: vanilla gets that by
-- putting them in a frame raised three levels, and a flat rebuild gets it from
-- the order alone. Anything else here is ordered for readability.
Art.Player.DrawOrder = {
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
Art.Player.Bars = {
    health = {
        w = 119, h = 12,
        point = "TOPLEFT", x = 90, y = -45,
        texture = Art.Paths.statusBar,
        color = { 0.0, 1.0, 0.0 },
    },
    power = {
        w = 119, h = 12,
        point = "TOPLEFT", x = 90, y = -56,
        texture = Art.Paths.statusBar,
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
Art.Player.Text = {
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

--------------------------------------------------------------------------------
-- The reader
--------------------------------------------------------------------------------

-- This file defines the region format, so it owns the one function that turns a
-- def into a texture.
function Art.BuildRegion(host, def)
    local tex = host:CreateTexture(nil, def.layer)
    if def.path then tex:SetTexture(def.path) end
    tex:SetSize(def.w, def.h)
    tex:SetPoint(def.point, host, def.point, def.x or 0, def.y or 0)
    if def.coords then
        tex:SetTexCoord(def.coords[1], def.coords[2], def.coords[3], def.coords[4])
    end
    if def.blend then tex:SetBlendMode(def.blend) end
    if def.color then
        tex:SetColorTexture(def.color[1], def.color[2], def.color[3], def.color[4] or 1)
    end
    if def.hidden then tex:Hide() end
    return tex
end
