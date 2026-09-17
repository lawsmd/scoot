-- forever.lua - the Forever skin: Blizzard's WoW Forever palette on the
-- settings panel. Everything but the palette repeats the tui default, so
-- switching between the two changes color and nothing else. That is the
-- point of this first pass: if the panel reads wrong, the seven values below
-- are the only thing that can be responsible.
--
-- Each value is measured out of the Forever build's own art, not read off
-- footage, and the comment on each one names the atlas it came from. None of
-- it has been seen lit, scaled, or beside another frame, so these are
-- proposals.
--
-- Fonts, textures and metrics are tui's. Metrics cannot be omitted:
-- Controls.Metrics() returns Skin.Metrics() with no fallback, so a skin
-- without the table makes every row throw. They are also where this skin
-- diverges next, once a nine-slice window needs its own border and corner
-- numbers.
--
-- Registration only, no SetActive: tui stays the default, and this skin is
-- reached with /scoot debug skin forever. When the framework moves to
-- shared/, the file becomes forever/skin.lua under the Camelot TOC and the
-- registry name stays.
local addonName, addon = ...

local Skin = addon.UI.Skin

-- The addon that loaded this file, not a literal: the Forever client has no
-- Scoot folder to resolve against, only whichever junction points at this one.
-- core/fonts.lua takes the same fallback.
local ROOT = addon.MediaPath or "Interface\\AddOns\\Scoot\\"
local FONT_BASE = ROOT .. "media\\fonts\\"

-- The tui faces, held so this pass changes one variable. A proportional face
-- waits on framework phase 7: metrics.slots below are fixed pixel widths
-- tuned to a monospace grid, and a proportional face clips option labels
-- until a field measures its widest option.
local MONO_REG  = addon.Fonts.JETBRAINS_REG
local MONO_MED  = addon.Fonts.JETBRAINS_MED
local MONO_BOLD = addon.Fonts.JETBRAINS_BOLD
local PROP_REG  = addon.Fonts.ROBOTO_REG or (FONT_BASE .. "Roboto-Regular.ttf")
local PROP_MED  = addon.Fonts.ROBOTO_MED or (FONT_BASE .. "Roboto-Medium.ttf")

Skin.Register("forever", {
    -- Kept off Theme accent: contrast floor. The near black and the warm
    -- grays are what the accent is read against; they cannot move with it.
    -- Forever's chrome carries its color through lighting rather than tint,
    -- so the dark roles sit lower than tui's greens do and the accent has to
    -- carry the bronze on its own.
    palette = {
        -- #a78151, the lit edge of ui-frame-metal-cornertopleft-2x and the
        -- brightest bronze Blizzard draws. A player who never opens the
        -- color picker gets Forever's own metal.
        accentDefault   = { r = 0.655, g = 0.506, b = 0.318, a = 1 },
        -- #0d0805, heavybronze-frame-background-c60 at body luminance.
        -- Forever is darker behind its panels than retail is.
        background      = { r = 0.051, g = 0.031, b = 0.020, a = 0.96 },
        backgroundSolid = { r = 0.051, g = 0.031, b = 0.020, a = 0.99 },
        textPrimary     = { r = 1, g = 1, b = 1, a = 1 },
        -- #9b8a7b, the common-search-border-middle highlight: a warm gray
        -- that sits with the chrome instead of against it.
        textDim         = { r = 0.608, g = 0.541, b = 0.482, a = 1 },
        -- #cbbeab, the lightest pixel in heavybronze-frame-basic-c60.
        textDimLight    = { r = 0.796, g = 0.745, b = 0.671, a = 1 },
        -- #1d1611, the lit edge of a common-button-list-mid-c60 row.
        collapsibleBg   = { r = 0.114, g = 0.086, b = 0.067, a = 1 },
    },

    fonts = {
        label     = { path = MONO_MED,  size = 13 },
        value     = { path = MONO_REG,  size = 12 },
        desc      = { path = MONO_REG,  size = 11 },
        header    = { path = MONO_BOLD, size = 16 },
        button    = { path = MONO_MED,  size = 13 },
        miniLabel = { path = MONO_REG,  size = 11 },
        proportional    = { path = PROP_REG, size = 12 },
        proportionalMed = { path = PROP_MED, size = 12 },
    },

    -- The icon keys still name the other addon's art because Camelot has none
    -- of its own yet. Both resolve through the junction, so the panel draws a
    -- Scoot logo until Camelot ships a file to put here.
    textures = {
        NOISE_OVERLAY = ROOT .. "media\\textures\\noise-overlay",
        SCOOT_ICON    = ROOT .. "ScootIcon",
        SCOOT_ICON_TRANSPARENT = ROOT .. "ScootIconTransparent",
    },

    metrics = {
        -- Row layout
        rowHeight = 36,
        rowHeightField = 42,
        rowHeightEmphasized = 72,
        dualRowHeight = 53,
        controlHeight = 28,
        rowPadding = 12,
        labelTopPad = 10,
        labelLineHeight = 16,
        descGap = 2,
        descPadBottom = 10,
        maxRowHeight = 200,

        -- Page spine
        itemSpacing = 12,
        contentPadding = 8,
        sectionSpacing = 16,
        sectionHeaderHeight = 32,
        firstItemOffset = 8,

        -- Dividers and borders. The nine-slice window override moves these:
        -- optionsframe-nineslice pieces are 32x32 against this 3px flat
        -- border, and the content inset follows whichever frame is picked.
        dividerThickness = 1,
        dividerAlpha = 0.2,
        borderWidth = 2,
        windowBorderWidth = 3,

        -- Dual-row slots
        slotGap = 12,
        miniLabelHeight = 14,
        miniLabelGap = 3,
        maxClusterWidth = 410,
        slots = { toggle = 70, slider = 130, selector = 140, selectorWide = 240, swatch = 28, input = 36 },
        minDescWidth = 200,

        field = {
            arrowWidth = 28,
            indicatorWidth = 8,
            indicatorGap = 4,
            textInset = 8,
            gearWidth = 22,
            tokenIconWidth = 10,
            widthStep = 20,
            popupMaxWidth = 360,
        },

        sublevels = { bg = -8, fill = -7, hover = -6 },
        alphas = { hover = 0.08, emphasis = 0.03, selected = 0.12, borderNormal = 0.6, borderFocus = 1.0 },
    },
})
