--------------------------------------------------------------------------------
-- forever/unitframes/arttot.lua
-- The Classic target-of-target frame's art, as data. Transcribed from
-- TargetofTargetFrameTemplate in Classic/TargetFrame.xml on origin/classic_era;
-- the format is in art.lua.
--
-- The small frame: a portrait, a name, two thin bars. It has no level, no
-- icons and no bar text. The border has no size in the XML and fills the
-- frame, which draws 91 texels across 93 units.
--------------------------------------------------------------------------------

local addonName, addon = ...

local Art = addon.UnitFrames.Art
local Paths = Art.Paths

local spec = {
    width = 93,
    height = 45,
    -- The Art.Paths key the border starts on. Nothing swaps this frame's file,
    -- so without it Art.ApplyBorder falls back to the large frame's.
    borderKey = "borderToT",
    onBase = { background = true, nameBackdrop = true, portrait = true },
}
Art.Frames.targettarget = spec

spec.Regions = {
    background = {
        layer = "BACKGROUND",
        w = 46, h = 15,
        point = "BOTTOMLEFT", x = 42, y = 13,
        color = { 0, 0, 0, 0.5 },
    },
    -- Camelot: the leather over the black fill (art.lua, "Backdrops"). The
    -- dead-unit dimming tot.lua puts on the fill is hidden under it and stays
    -- as the transcription.
    nameBackdrop = {
        layer = "BACKGROUND", sublevel = 1,
        atlas = Art.BACKDROP_SOURCE.smallStrip,
        w = 46, h = 15,
        point = "BOTTOMLEFT", x = 42, y = 13,
        vertex = { 1, 1, 1, Art.BACKDROP_ALPHA },
        lift = true,
    },
    portrait = {
        layer = "BORDER",
        w = 35, h = 35,
        point = "TOPLEFT", x = 6, y = -6,
    },
    border = {
        layer = "BORDER",
        path = Paths.borderToT,
        w = 93, h = 45,
        point = "TOPLEFT", x = 0, y = 0,
        coords = { 0.015625, 0.7265625, 0, 0.703125 },
        border = true,
    },
}

spec.DrawOrder = { "background", "nameBackdrop", "portrait", "border" }

spec.Bars = {
    health = {
        w = 46, h = 7,
        point = "TOPRIGHT", x = -2, y = -15,
        texture = Paths.statusBar,
        color = { 0.0, 1.0, 0.0 },
    },
    power = {
        w = 46, h = 7,
        point = "TOPRIGHT", x = -2, y = -23,
        texture = Paths.statusBar,
        color = { 0, 0, 1.0 },
    },
}

-- The name in ARTWORK for the Deep Shadow style (artplayer.lua, "Text").
spec.Text = {
    name = {
        layer = "ARTWORK",
        font = "GameFontNormalSmall",
        w = 100, h = 10,
        justifyH = "LEFT",
        point = "BOTTOMLEFT", x = 42, y = 2,
    },
    dead = {
        layer = "BORDER",
        font = "GameFontNormalSmall",
        point = "LEFT", x = 48, y = 1,
    },
}
