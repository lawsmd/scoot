--------------------------------------------------------------------------------
-- forever/castbars/art.lua
-- The cast bar's art, as data: one look per Cast Bar Style value.
--
-- CLASSIC is transcribed from Blizzard's CastingBarFrameTemplate
-- (Blizzard_UIPanels_Game/Classic/CastingBarFrame.xml on classic_era) and the
-- CLASSIC branch of CastingBarMixin:SetLook (Shared/CastingBarFrame.lua:1026).
-- MODERN is Blizzard's current bar, the one Forever ships, from
-- Mainline/CastingBarFrame.xml. Every path and atlas resolves in Forever by
-- name, measured in the client.
--
-- Classic's region defs are the format forever/unitframes/art.lua defines,
-- read by its Art.BuildRegion, for a 195-wide native bar; painter.lua grows
-- the three wide regions with the Bar Width setting. Modern's regions hug the
-- bar by `edges` and are built by modern.lua.
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

-- Each look carries `key`, its own name in this table, and `recolor`, whether
-- the Frame Color row dresses it: Classic's border file takes the bronze,
-- Modern's atlases draw as the client ships them.
Art.Looks = {}

Art.Looks.CLASSIC = {
    key = "CLASSIC", recolor = true,
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

    -- The border's drawn edge past the bar: each side, then above and below.
    -- Read off the screen at the stock size, since the file's transparent
    -- margins are not in the anchor numbers; the box's ends are the check.
    reach  = { left = 3, right = 3, top = 13, bottom = 15 },

    spark  = { layer = "OVERLAY", sublevel = 1, path = Art.Paths.spark, blend = "ADD",
               w = 32, h = 32, y = 2 },

    text   = { layer = "ARTWORK", sublevel = 2, fontObject = "GameFontHighlight",
               w = 185, h = 16, point = "TOP", x = 0, y = 5 },
}

-- Blizzard's current bar, the one Forever ships: PlayerCastingBarFrame as
-- Blizzard_UIPanels_Game/Mainline/CastingBarFrame.xml declares it (the
-- CastingBarFrameBaseTemplate regions at :188-385, the frame at :468-482) with
-- classicStyleCastBar unset, the geometry SetLook never touches. Every part is
-- an atlas, referenced by name. `edges` is left, top, right, bottom: offsets
-- from the bar's own corners for a region that hugs the bar and grows with it,
-- Blizzard's TOPLEFT and BOTTOMRIGHT pairs. The choreography that plays these
-- regions is modern.lua.
Art.Looks.MODERN = {
    key = "MODERN", recolor = false,
    width = 208, height = 11,

    -- The fill is an atlas per cast state, white (CastingBarTypeInfo,
    -- Shared/CastingBarFrame.lua:16-84; UpdateBarFillTexture :640-655):
    -- `filling` while the cast runs, `full` once it has finished or failed,
    -- `glow` the flash over the frame at the finish. Crafting is a
    -- profession's cast, Blizzard's ApplyingCrafting.
    fill = {
        standard        = { filling = "ui-castingbar-filling-standard", full = "ui-castingbar-full-standard",
                            glow = "ui-castingbar-full-glow-standard" },
        channel         = { filling = "ui-castingbar-filling-channel", full = "ui-castingbar-full-channel",
                            glow = "ui-castingbar-full-glow-channel" },
        crafting        = { filling = "ui-castingbar-filling-applyingcrafting", full = "ui-castingbar-full-applyingcrafting",
                            glow = "ui-castingbar-full-glow-applyingcrafting" },
        uninterruptable = { filling = "ui-castingbar-uninterruptable", full = "ui-castingbar-uninterruptable",
                            glow = "ui-castingbar-full-glow-standard" },
        interrupted     = { filling = "ui-castingbar-interrupted", full = "ui-castingbar-interrupted" },
    },

    -- Under the fill: the plate the name sits on, 12 below the bar, and the
    -- background a unit inside the frame.
    textPlate  = { layer = "BACKGROUND", sublevel = 0, atlas = "ui-castingbar-textbox", edges = { 0, 0, 0, -12 } },
    background = { layer = "BACKGROUND", sublevel = 2, atlas = "ui-castingbar-background", edges = { -1, 1, 1, -1 } },

    -- Over it: the frame two units past the bar, and the flash the finish
    -- lights, whose atlas follows the cast state.
    border = { layer = "ARTWORK", sublevel = 4, atlas = "ui-castingbar-frame", edges = { -2, 2, 2, -2 } },
    flash  = { layer = "OVERLAY", sublevel = 1, atlas = "ui-castingbar-full-glow-standard", blend = "ADD",
               edges = { -1, 1, 1, -1 }, hidden = true, fadeIn = 0.2 },

    -- The frame's 2 past the bar each way, and the plate's 12 below: Blizzard's
    -- own selection runs to editModeSelectionBottomOffset -12.
    reach  = { left = 2, right = 2, top = 2, bottom = 12 },

    -- The pip on the leading edge and what trails it, each RIGHT to the pip's
    -- LEFT: a glow on a cast, a shadow on a channel.
    spark   = { layer = "OVERLAY", sublevel = 2, atlas = "ui-castingbar-pip", w = 8, h = 20, y = 0 },
    sparkFx = {
        standard = { layer = "OVERLAY", sublevel = 3, atlas = "cast_standard_pipglow", blend = "ADD", w = 37, h = 12, x = 2 },
        channel  = { layer = "OVERLAY", sublevel = 3, atlas = "cast_channel_pipshadow", w = 11, h = 11, x = 1 },
    },
    -- The bar-shaped mask every effect is clipped to, 256 x 13 for the
    -- 208 x 11 bar; the painter grows it with the bar.
    barMask = { atlas = "cast_standard_barmask", w = 256, h = 13 },

    -- The name on the plate: Blizzard anchors it TOP at -10 from an 11-tall
    -- bar's top, which is 1 below the bar's bottom. Anchored to the bottom
    -- here, so it stays on the plate at any height; the box keeps its height
    -- and grows with the width alone.
    text = { layer = "OVERLAY", sublevel = 1, fontObject = "GameFontHighlightSmall",
             w = 185, h = 16, point = "TOP", relPoint = "BOTTOM", x = 0, y = 1, growH = false },

    -- The effects' members, each a 2x asset drawn at its own size at half
    -- scale (`useAtlasSize="true" scale="0.5"`), anchored to the bar. The
    -- standard finish (CastingBarFrameAnimsFXTemplate, xml:138-144) sweeps the
    -- line and three flakes up through the mask; the crafting finish
    -- (:145-148) wipes a shine up through it; the channel finish (:149-168)
    -- crosses a wisp and two sparkles left to right; the interrupt lights the
    -- outer glow.
    fx = {
        energyGlow = { layer = "ARTWORK", sublevel = 1, atlas = "Cast_Standard_GlowLine", blend = "ADD",
                       scale = 0.5, point = "CENTER", x = 0, y = -100, alpha = 0 },
        energyMask = { atlas = "Cast_Standard_LineTextureMask", scale = 0.5, point = "CENTER", x = 0, y = 0 },
        flakes = {
            { layer = "ARTWORK", sublevel = 5, atlas = "Cast_Standard_Flakes01", blend = "ADD",
              scale = 0.5, point = "CENTER", x = 0, y = -25 },
            { layer = "ARTWORK", sublevel = 5, atlas = "Cast_Standard_Flakes02", blend = "ADD",
              scale = 0.5, point = "CENTER", x = 0, y = -45 },
            { layer = "ARTWORK", sublevel = 5, atlas = "Cast_Standard_Flakes03", blend = "ADD",
              scale = 0.5, point = "CENTER", x = 0, y = -25 },
        },
        shine        = { layer = "OVERLAY", sublevel = 2, atlas = "Cast_Crafting_ShineWipe", blend = "ADD",
                         scale = 0.5, point = "CENTER", x = 0, y = -110, alpha = 0 },
        craftingMask = { atlas = "Cast_Crafting_LineTextureMask", scale = 0.5, point = "CENTER", x = 0, y = 0 },
        baseGlow   = { layer = "ARTWORK", sublevel = 5, atlas = "Channel_WispGlow2", blend = "ADD",
                       scale = 0.5, point = "LEFT", x = 0, y = 0, alpha = 0 },
        wispGlow   = { layer = "ARTWORK", sublevel = 5, atlas = "Cast_Channel_WispGlow", blend = "ADD",
                       scale = 0.5, point = "LEFT", x = 25, y = 0, alpha = 0 },
        wispMask   = { atlas = "Cast_Channel_WispMask", scale = 0.5, point = "LEFT", x = -90, y = -2 },
        sparkles01 = { layer = "ARTWORK", sublevel = 5, atlas = "Cast_Channel_Sparkles_01",
                       scale = 0.5, point = "LEFT", x = 0, y = 0, alpha = 0 },
        sparkles02 = { layer = "ARTWORK", sublevel = 5, atlas = "Cast_Channel_Sparkles_02",
                       scale = 0.5, point = "LEFT", x = 0, y = 0, alpha = 0 },
        interruptGlow = { layer = "BACKGROUND", sublevel = 1, atlas = "cast_interrupt_outerglow", blend = "ADD",
                          scale = 0.5, point = "CENTER", x = 0, y = 0, alpha = 0 },
    },
}

-- The look a Cast Bar Style value names. Classic is the default and the
-- fallback for a value the table does not know.
Art.LOOK_FOR_STYLE = { classic = "CLASSIC", modern = "MODERN" }

function Art.LookForStyle(style)
    return Art.Looks[Art.LOOK_FOR_STYLE[style] or "CLASSIC"]
end
