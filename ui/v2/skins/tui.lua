-- tui.lua - the default skin: the terminal look the settings panel shipped
-- with. The tables here are the single source for the panel's palette, font
-- roles, texture paths, and chrome metrics; Skin.SetActive pushes them into
-- the Theme and Controls facades at the end of this file.
local addonName, addon = ...

local Skin = addon.UI.Skin

-- The loading addon's folder, not a literal: the Forever client has no Scoot
-- folder to resolve against. The JetBrains registrations below are what the
-- other two skins read back, so this root serves all three.
local ROOT = addon.MediaPath or "Interface\\AddOns\\Scoot\\"
local FONT_BASE = ROOT .. "media\\fonts\\"

-- JetBrains Mono registration alongside the faces core/fonts.lua registers.
addon.Fonts = addon.Fonts or {}
addon.Fonts.JETBRAINS_REG  = FONT_BASE .. "JetBrainsMono-Regular.ttf"
addon.Fonts.JETBRAINS_MED  = FONT_BASE .. "JetBrainsMono-Medium.ttf"
addon.Fonts.JETBRAINS_BOLD = FONT_BASE .. "JetBrainsMono-Bold.ttf"

local MONO_REG  = addon.Fonts.JETBRAINS_REG
local MONO_MED  = addon.Fonts.JETBRAINS_MED
local MONO_BOLD = addon.Fonts.JETBRAINS_BOLD
local PROP_REG  = addon.Fonts.ROBOTO_REG or (FONT_BASE .. "Roboto-Regular.ttf")
local PROP_MED  = addon.Fonts.ROBOTO_MED or (FONT_BASE .. "Roboto-Medium.ttf")

Skin.Register("tui", {
    -- Kept off Theme accent: contrast floor. The near black and the greys are
    -- what the accent is read against; they cannot move with it.
    palette = {
        -- Matrix green #00FF41, the default the accent picker starts from.
        accentDefault   = { r = 0, g = 1, b = 0.255, a = 1 },
        background      = { r = 0.004, g = 0.004, b = 0.006, a = 0.96 },
        backgroundSolid = { r = 0.004, g = 0.004, b = 0.006, a = 0.99 },
        textPrimary     = { r = 1, g = 1, b = 1, a = 1 },
        textDim         = { r = 0.6, g = 0.6, b = 0.6, a = 1 },
        -- Lighter dim for text on the gray collapsible background.
        textDimLight    = { r = 0.75, g = 0.75, b = 0.75, a = 1 },
        collapsibleBg   = { r = 0.12, g = 0.12, b = 0.14, a = 1 },
    },

    fonts = {
        label     = { path = MONO_MED,  size = 13 },
        value     = { path = MONO_REG,  size = 12 },
        desc      = { path = MONO_REG,  size = 11 },
        header    = { path = MONO_BOLD, size = 16 },
        button    = { path = MONO_MED,  size = 13 },
        miniLabel = { path = MONO_REG,  size = 11 },
        -- Proportional faces for text read against the game world rather
        -- than a panel background.
        proportional    = { path = PROP_REG, size = 12 },
        proportionalMed = { path = PROP_MED, size = 12 },
    },

    textures = {
        NOISE_OVERLAY = ROOT .. "media\\textures\\frosted-noise",
        SCOOT_ICON    = ROOT .. "ScootIcon",
        -- The logo with the black backdrop keyed out, for surfaces that are
        -- not black.
        SCOOT_ICON_TRANSPARENT = ROOT .. "ScootIconTransparent",
    },

    -- How each surface is drawn. Every role here is the framework's own flat
    -- draw, which is the look the panel shipped with; a role left out resolves
    -- to the same flat default in Chrome.FLAT, so this table is the catalog
    -- rather than a requirement. The window's noise is the frosted layer over
    -- the background fill.
    chrome = {
        window = {
            kind = "flat", corners = "outset", background = "window",
            noise = { texture = "NOISE_OVERLAY", size = 2048, alpha = 0.25, blend = "ADD" },
        },
        titleBar      = { kind = "ascii", fontRole = "label" },
        closeButton   = { kind = "flat", glyph = "X" },
        button        = { kind = "flat", labelColors = { normal = "accent", hover = "black", active = "background", disabled = "accent" } },
        resizeGrip    = { kind = "flat" },
        scrollBar     = { kind = "flat" },
        tab           = { kind = "flat", labelColors = { normal = "accent", hover = "accent", selected = "black" } },
        tabBody       = { kind = "flat", fill = { 0, 0, 0, 0.15 } },
        sectionHeader = { kind = "flat", background = "collapsible",
                          glyphs = { expanded = "\226\150\188", collapsed = "\226\150\182" } },
        sectionBody   = { kind = "flat", background = "collapsible" },
        navRow        = {
            kind = "flat",
            parent = { labelColors = { normal = "accent", hover = "primary", selected = "primary", disabled = { token = "dim", alpha = 0.35 } } },
            child  = { labelColors = { normal = "primary", hover = "accent", selected = "accent", disabled = { token = "dim", alpha = 0.35 } } },
        },
        navCard       = { kind = "flat" },
        navDivider    = { kind = "flat" },
        dropdown      = { kind = "flat" },
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

        -- Dividers and borders
        dividerThickness = 1,
        dividerAlpha = 0.2,
        borderWidth = 2,
        windowBorderWidth = 3,

        -- Panel chrome. windowInset is the content inset the panes anchor
        -- from; with a flat border it equals windowBorderWidth, and a
        -- nine-slice window moves it to wherever that art reaches.
        windowInset = 3,
        panelWidth = 1125,
        panelHeight = 715,
        panelMinWidth = 800,
        panelMinHeight = 550,
        panelMaxWidth = 1600,
        panelMaxHeight = 1000,
        titleBarHeight = 80,
        logoFontSize = 6,
        contentHeaderHeight = 66,
        -- The page header's layout: the action buttons under the title, the
        -- separator under the header, the copy-from field present
        contentHeader = { placement = "pane", top = 0, padLeft = 16, actions = "left",
                          separator = true, copyFrom = true, padRight = 8, gap = 8, iconGap = 6 },
        navWidth = 220,
        closeButton = { size = 24, x = -10, y = -10, fontSize = 16 },
        resizeGrip = { size = 16, x = -4, y = 4, dot = 2, step = 4, alpha = 0.7 },
        toolbar = { height = 26, spacing = 10, y = 0, fontSize = 11 },
        pulse = { period = 1.5, minAlpha = 0.3, tick = 0.016 },

        -- The panel's own numbers, per surface. paneInset is the scroll
        -- frame's inset inside the content pane.
        paneInset = 8,
        nav = {
            rowHeight = 24, parentRowHeight = 28, childIndent = 20,
            padLeft = 8, padTop = 8,
            treeLineWidth = 1, treeLineX = 10, treeLineLength = 10, treeLineAlpha = 0.4,
            dividerWidth = 1, dividerAlpha = 0.4, dividerGap = 1,
            indicatorSize = 10,
            hoverAlpha = 0.15, selectedAlpha = 0.25,
            -- The card a parent row becomes under a card navCard role; unused
            -- while the role is flat, carried so every skin has the keys
            card = { height = 40, spacing = 6, padLeft = 4, padRight = 0, reach = 0, inner = 8, padBottom = 8,
                     glowOffset = -7, glowInset = 5, hoverAlpha = 0.08, disabledAlpha = 0.75,
                     labelFontRole = "label", labelSize = 14, labelPadLeft = 16 },
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
            logoFontSize = 10, mascotFontSize = 6, textSize = 13,
        },

        -- Dual-row slots
        slotGap = 12,
        miniLabelHeight = 14,
        miniLabelGap = 3,
        maxClusterWidth = 410,
        slots = { toggle = 70, slider = 130, selector = 140, selectorWide = 240, swatch = 28, input = 36 },
        -- The narrowest description wrap /scoot debug fit accepts beside a
        -- control cluster.
        minDescWidth = 200,

        -- Field chrome around a selector's value text, per side where it
        -- flanks the text. Controls.FieldNeed adds it to the widest option
        -- label and rounds up to widthStep.
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

        -- Background z-stack and house alphas. The three sublevels are
        -- load-bearing: base fill below, emphasis fill above it, hover fill
        -- on top.
        sublevels = { bg = -8, fill = -7, hover = -6 },
        alphas = { hover = 0.08, emphasis = 0.03, selected = 0.12, borderNormal = 0.6, borderFocus = 1.0 },
    },
})

Skin.SetActive("tui")
