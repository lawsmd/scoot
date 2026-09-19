--------------------------------------------------------------------------------
-- forever/castbars/art.lua
-- The Classic cast bar's art, as data.
--
-- Transcribed from Blizzard's CastingBarFrameTemplate
-- (Blizzard_UIPanels_Game/Classic/CastingBarFrame.xml on classic_era) and the
-- CLASSIC branch of CastingBarMixin:SetLook (Shared/CastingBarFrame.lua:1026).
-- Every path resolves in Forever by name, measured in the client.
--
-- Region defs are the format forever/unitframes/art.lua defines, read by its
-- Art.BuildRegion. Widths here are the 195-wide native bar; painter.lua scales
-- the three wide regions with the Bar Width setting.
--------------------------------------------------------------------------------

local addonName, addon = ...

local CASTING = "Interface\\CastingBar\\"

local Art = {}
addon.CastBarArt = Art

Art.Paths = {
    border      = CASTING .. "UI-CastingBar-Border",
    borderSmall = CASTING .. "UI-CastingBar-Border-Small",
    flash       = CASTING .. "UI-CastingBar-Flash",
    flashSmall  = CASTING .. "UI-CastingBar-Flash-Small",
    shield      = CASTING .. "UI-CastingBar-Small-Shield",
    spark       = CASTING .. "UI-CastingBar-Spark",
    fill        = "Interface\\TargetingFrame\\UI-StatusBar",
}

-- The colors the vanilla client set in CastingBarFrame_OnLoad
-- (Blizzard_CastingBar/Vanilla/CastingBarFrame.lua:7-11, 1.15.8).
Art.Colors = {
    cast     = { 1.0, 0.7, 0.0 },
    channel  = { 0.0, 1.0, 0.0 },
    finished = { 0.0, 1.0, 0.0 },
    failed   = { 1.0, 0.0, 0.0 },
    locked   = { 0.7, 0.7, 0.7 },
}

-- CASTING_BAR_HOLD_TIME is 1; the fade steps 0.05 alpha a frame, a third of a
-- second at 60 fps; the flash steps 0.2 a frame, which classic_era's FlashAnim
-- writes as 0.08 s.
Art.Timing = {
    holdFailed   = 1.0,
    holdComplete = 0.2,
    fade         = 0.3,
    flashIn      = 0.08,
}

-- The additive share of the Forever bronze. UI-CastingBar-Border is a darker
-- gray than the unit frame borders, so the shared 0.30 read dark and heavy
-- beside them. Tune this one number; the hue stays put.
Art.BronzeLightAlpha = 0.45

Art.Looks = {}

Art.Looks.CLASSIC = {
    width = 195, height = 13,

    background = { layer = "BACKGROUND", color = { 0, 0, 0, 0.5 } },

    -- The regions drawn larger than the bar. `w` and `h` are for a 195 x 13
    -- bar. `slice` is left, top, right, bottom in file pixels: the part of the
    -- picture that keeps its drawn size when the bar grows. The opening sits
    -- 30.5 in from each side, 28 down and 23 up, and each margin reaches a
    -- little past it to cover the drawn edge. Unmeasured against the file:
    -- check the corners in game at height 40 and width 500.
    border = { layer = "ARTWORK", sublevel = 1, path = Art.Paths.border,
               w = 256, h = 64, point = "TOP", x = 0, y = 28, slice = { 40, 30, 40, 25 } },
    flash  = { layer = "OVERLAY", path = Art.Paths.flash, blend = "ADD",
               w = 256, h = 64, point = "TOP", x = 0, y = 28, hidden = true, slice = { 40, 30, 40, 25 } },

    spark  = { layer = "OVERLAY", sublevel = 1, path = Art.Paths.spark, blend = "ADD",
               w = 32, h = 32, y = 2 },

    text   = { layer = "ARTWORK", sublevel = 2, fontObject = "GameFontHighlight",
               w = 185, h = 16, point = "TOP", x = 0, y = 5 },
}
