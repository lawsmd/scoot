-- forever.lua - the Forever skin: Blizzard's WoW Forever palette, and
-- Blizzard's own panel parts for the chrome.
--
-- The palette is measured out of the Forever build's art, and the comment
-- on each value names the atlas it came from. The chrome table takes the
-- retail construction and lets the client's art set do the work: the window
-- is Blizzard's portrait panel, the template Forever's own Legacy pane is
-- built on, and its parts exist on retail too, so /camelot draws a gray
-- portrait panel on the retail client and a bronze one on Forever from this
-- one table. The Legacy pane's own atlases exist only on Forever; each is
-- declared with a fallback the retail client takes. None of it has been
-- seen lit, so the numbers that place the toolbar and the panes are
-- proposals.
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
        -- The window's portrait: the question mark every client has, the
        -- same placeholder the minimap button draws. Both change together
        -- when Camelot has an emblem.
        PLACEHOLDER_ICON = "Interface\\ICONS\\INV_Misc_QuestionMark",
    },

    -- The chrome: Blizzard's parts where a part exists, the framework's flat
    -- draw where the look is a fill. A name only Forever carries declares
    -- the fallback the retail client takes; a name the running client lacks
    -- with no fallback falls to the flat default through Chrome.Spec.
    chrome = {
        -- Blizzard's portrait panel: the frame is the template, and its
        -- metal border, title plate, close button and portrait ring come
        -- with it. The dark page under the title band is the Legacy pane's
        -- own background. Its art bakes in a lighter column on the left,
        -- a streak band across the top and a bordered panel filling the
        -- rest, so it is cut at the panel's edges (column 121; rows 52 and
        -- 60 bracket the top border) and each cell stretched to its own
        -- pane, which puts the baked edges on the nav's right edge and the
        -- title band's bottom whatever the window's size. Retail has no
        -- such atlas and fills the rect flat. The options border stands in
        -- if a client ever lacks the template.
        window = {
            kind = "template", template = "PortraitFrameTemplate",
            portrait = { texture = "PLACEHOLDER_ICON" },
            contentBackground = {
                kind = "atlas", atlas = "Legacy-Tree-Frame-background",
                grid = { cols = { 121 }, rows = { 52, 60 } },
                inset = { left = 2, top = 21, right = 2, bottom = 2 }, sublevel = -5,
                fallback = { kind = "flat", fill = "window" },
            },
            fallback = { kind = "nineSlice", layout = "UniqueCornersLayout", textureKit = "OptionsFrame", background = "window" },
        },
        -- The title and the close button are the window template's own.
        -- The title reads from the left, starting where the portrait ring
        -- ends; the template centers it by default.
        titleBar = {
            kind = "window", justify = "LEFT", offsets = { left = 62, right = -24 },
            fallback = { kind = "text", fontObject = "GameFontNormal", point = "TOPLEFT", x = 24, y = -20 },
        },
        closeButton = { kind = "window", fallback = { kind = "template", template = "UIPanelCloseButton" } },
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
        -- The Legacy pane's group cards: the group's name centered on the
        -- header band, the child rows inside the same card while it is
        -- open, and the gold glow at the right edge while open. The face is
        -- cut into nine slices by texcoords; the slices hold the corner
        -- knots, which reach 10 pixels in, and the edge is the margin the
        -- art keeps outside its border (a clear column or two and the
        -- knots' tips), so the border's outer edge is the row's edge. The
        -- glow's arrow sits in rows 17 to 59 of its atlas and keeps its own
        -- scale on a tall card. Neither atlas exists on retail, where the
        -- group is the text row navRow draws.
        navCard = {
            kind = "card", atlas = "Legacy-Tree-Frame-Card",
            slice = { left = 12, right = 12, top = 12, bottom = 12 },
            edge = { left = 3, right = 3, top = 3, bottom = 2 },
            glow = { kind = "atlas", atlas = "Legacy-Tree-Frame-Card-Glow", fixed = { top = 17, bottom = 59 } },
            labelColors = { normal = "primary", hover = "accent", open = "accent", selected = "accent",
                            disabled = { token = "dim", alpha = 0.35 } },
            fallback = { kind = "flat" },
        },
        -- The Legacy pane's divider between its column and its content, its
        -- caps (4 rows at the top, 5 at the bottom) kept at their own size.
        navDivider = {
            kind = "atlas", normal = "Legacy-Tree-Frame-divider-Vertical",
            slice = { top = 4, bottom = 5 },
            fallback = { kind = "flat" },
        },
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

        -- Panel chrome. The portrait panel's metal border draws outside the
        -- frame rect and its own background sits 2px inside it, so the
        -- panes stand a few pixels in. The title band is the template's
        -- 21px title plate, the toolbar row under it, and the page
        -- background's top border, 8 pixels ending at the band's bottom;
        -- the close button keeps the template's corner. The closeButton
        -- offsets are read only if the chain falls past the window kind.
        windowInset = 6,
        panelWidth = 1125,
        panelHeight = 715,
        panelMinWidth = 800,
        panelMinHeight = 550,
        panelMaxWidth = 1600,
        panelMaxHeight = 1000,
        titleBarHeight = 60,
        logoFontSize = 6,
        -- The page header is the title line: the action buttons sit at its
        -- right end, the page background's own border is the divider under
        -- it, and the copy-from field waits on a dropdown in this chrome.
        contentHeaderHeight = 48,
        contentHeader = { actions = "right", separator = false, copyFrom = false, padRight = 8, gap = 8, iconGap = 6 },
        navWidth = 220,
        closeButton = { size = 24, x = -6, y = -6, fontSize = 16 },
        resizeGrip = { size = 16, x = -8, y = 8, dot = 2, step = 4, alpha = 0.7 },
        toolbar = { height = 22, spacing = 8, y = -38, fontSize = 11 },
        pulse = { period = 1.5, minAlpha = 0.3, tick = 0.016 },

        -- The panel's own numbers, per surface. paneInset is the scroll
        -- frame's inset inside the content pane.
        paneInset = 8,
        nav = {
            rowHeight = 24, parentRowHeight = 28, childIndent = 20,
            padLeft = 8, padTop = 8,
            treeLineWidth = 0, treeLineX = 10, treeLineLength = 10, treeLineAlpha = 0.4,
            -- The divider is 12 wide and centered on the nav's edge; the
            -- content pane starts past its far half
            dividerWidth = 1, dividerAlpha = 0.4, dividerGap = 6,
            indicatorSize = 10,
            hoverAlpha = 0.15, selectedAlpha = 0.25,
            -- The group cards. height is the header band; inner is the
            -- border's depth, which the child rows and the hover fill keep
            -- inside; padBottom closes the card under the last child. The
            -- card's right edge is the nav's edge, so padRight is 0 and the
            -- glow's bar hugs the border's inner edge at glowOffset. The
            -- glow reaches glowOverhang past the card top and bottom.
            card = { height = 40, spacing = 6, padLeft = 4, padRight = 0, inner = 8, padBottom = 8,
                     glowOffset = -7, glowOverhang = 4, hoverAlpha = 0.08, disabledAlpha = 0.75,
                     labelFontRole = "label", labelSize = 12 },
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
