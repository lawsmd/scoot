-- forever.lua - the Forever skin: Blizzard's WoW Forever palette, and
-- Blizzard's own panel parts for the chrome.
--
-- The palette is measured out of the Forever build's art, and the comment
-- on each value names the atlas it came from. The chrome table takes the
-- retail construction and lets the client's art set do the work: every
-- template and atlas named below exists on retail too, so /camelot draws
-- gray Blizzard chrome on the retail client and bronze chrome on Forever
-- from this one table. None of it has been seen on either, so the numbers
-- that place the title, the toolbar and the close button are proposals.
--
-- Fonts and the row metrics are tui's: a proportional face waits on the
-- framework's content-fit phase. Metrics cannot be omitted, since
-- Controls.Metrics() returns Skin.Metrics() with no fallback.
--
-- Registration only, no SetActive here: forever/menu.lua activates it for
-- Camelot, and /scoot debug skin forever switches Scoot to it for a look.
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
        NOISE_OVERLAY = ROOT .. "media\\textures\\frosted-noise",
        SCOOT_ICON    = ROOT .. "ScootIcon",
        SCOOT_ICON_TRANSPARENT = ROOT .. "ScootIconTransparent",
    },

    -- The chrome: Blizzard's parts where a part exists, the framework's flat
    -- draw where the look is a fill. Every name resolves on retail, so
    -- nothing here needs a fallback; a name the running client lacks would
    -- fall to the flat default through Chrome.Spec.
    chrome = {
        -- Blizzard's own options border, the kit its Edit Mode dialog uses.
        window = { kind = "nineSlice", layout = "UniqueCornersLayout", textureKit = "OptionsFrame", background = "window" },
        -- The product name in Blizzard's panel title font, top-left of the band.
        titleBar = { kind = "text", fontObject = "GameFontNormal", point = "TOPLEFT", x = 24, y = -20 },
        closeButton = { kind = "template", template = "UIPanelCloseButton" },
        -- Raw texture files rather than atlases, so whether Forever redraws
        -- this one is the gallery's to answer.
        button = { kind = "template", template = "UIPanelButtonTemplate", font = "template" },
        resizeGrip = { kind = "flat" },
        scrollBar = { kind = "template", template = "MinimalScrollBar", frameType = "EventFrame" },
        -- The in-panel tab art, stretched to the label; the selected state is
        -- Forever's gold, so the label goes dark on it.
        tab = {
            kind = "atlas", normal = "common-internaltab", hover = "common-internaltab-hover",
            selected = "common-internaltab-selected",
            labelColors = { normal = "primary", hover = "primary", selected = "black" },
        },
        tabBody = { kind = "flat", fill = { 0, 0, 0, 0.15 } },
        -- List-row art under section headers and nav rows.
        sectionHeader = {
            kind = "atlas", normal = "common-button-list-mid", hover = "common-button-list-mid-hover",
            open = "common-button-list-mid-selected",
            glyphs = { expanded = "\226\150\188", collapsed = "\226\150\182" },
        },
        sectionBody = { kind = "flat", background = "collapsible" },
        navRow = {
            kind = "atlas", hover = "common-button-list-mid-hover", selected = "common-button-list-mid-selected",
            parent = { labelColors = { normal = "accent", hover = "primary", selected = "primary", disabled = { token = "dim", alpha = 0.35 } } },
            child  = { labelColors = { normal = "primary", hover = "accent", selected = "accent", disabled = { token = "dim", alpha = 0.35 } } },
        },
        navCard = { kind = "flat" },
        navDivider = { kind = "flat" },
        dropdown = { kind = "flat" },
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

        -- Dividers and borders. windowBorderWidth is the flat border the
        -- window falls back to when the nine-slice below is missing.
        dividerThickness = 1,
        dividerAlpha = 0.2,
        borderWidth = 2,
        windowBorderWidth = 3,

        -- Panel chrome. The OptionsFrame nine-slice pieces are 32x32 and
        -- Blizzard anchors the same kit 16px outside its content, so the
        -- panes stand 16 in from the frame edge. The title sits top-left in
        -- the band, the toolbar centered below it, the close button in the
        -- corner the way Blizzard's panels place theirs.
        windowInset = 16,
        panelWidth = 1125,
        panelHeight = 715,
        panelMinWidth = 800,
        panelMinHeight = 550,
        panelMaxWidth = 1600,
        panelMaxHeight = 1000,
        titleBarHeight = 56,
        logoFontSize = 6,
        contentHeaderHeight = 66,
        navWidth = 220,
        closeButton = { size = 24, x = -6, y = -6, fontSize = 16 },
        resizeGrip = { size = 16, x = -8, y = 8, dot = 2, step = 4, alpha = 0.7 },
        toolbar = { height = 22, spacing = 8, y = -34, fontSize = 11 },
        pulse = { period = 1.5, minAlpha = 0.3, tick = 0.016 },

        -- The panel's own numbers, per surface. paneInset is the scroll
        -- frame's inset inside the content pane.
        paneInset = 8,
        nav = {
            rowHeight = 24, parentRowHeight = 28, childIndent = 20,
            padLeft = 8, padTop = 8,
            treeLineWidth = 1, treeLineX = 10, treeLineLength = 10, treeLineAlpha = 0.4,
            dividerWidth = 1, dividerAlpha = 0.4,
            indicatorSize = 10,
            hoverAlpha = 0.15, selectedAlpha = 0.25,
        },
        scrollBar = { width = 8, thumbMin = 30, margin = 8, gap = 4,
                      trackAlpha = 0.1, thumbAlpha = 0.5, thumbHoverAlpha = 0.8, thumbDragAlpha = 1 },
        button = { height = 26, padding = 12, borderWidth = 2, fontSize = 12 },
        tab = {
            height = 26, padding = 16, spacing = 2, barPadding = 8, rowSpacing = 2,
            borderWidth = 1, borderAlpha = 0.6, contentPadding = 8, maxPerRow = 5,
            fontSize = 12, infoIconSize = 12, infoIconGap = 4, hoverAlpha = 0.15,
        },
        collapsible = {
            borderWidth = 1, borderAlpha = 0.6, contentPadding = 12,
            indicatorSize = 14, titleSize = 16,
        },
        dropdown = { width = 150, height = 22, borderAlpha = 0.6, borderHoverAlpha = 0.9, hoverAlpha = 0.15,
                     padding = 8, fontSize = 11, indicatorSize = 9 },
        home = {
            guideInset = 40, guideIconSize = 24, guideRowSpacing = 11, guideTextWidth = 304,
            guideTextSize = 11, guideIconTextGap = 8, accentInset = 6,
            logoFontSize = 26, mascotFontSize = 6, textSize = 13,
        },

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
