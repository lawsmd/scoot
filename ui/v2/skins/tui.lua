-- tui.lua - the default skin: the terminal look the settings panel shipped
-- with. The tables here are the single source for the panel's palette, font
-- roles, texture paths, and chrome metrics; Skin.SetActive pushes them into
-- the Theme and Controls facades at the end of this file.
local addonName, addon = ...

local Skin = addon.UI.Skin

local FONT_BASE = "Interface\\AddOns\\Scoot\\media\\fonts\\"

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
        NOISE_OVERLAY = "Interface\\AddOns\\Scoot\\media\\textures\\noise-overlay",
        SCOOT_ICON    = "Interface\\AddOns\\Scoot\\ScootIcon",
        -- The logo with the black backdrop keyed out, for surfaces that are
        -- not black.
        SCOOT_ICON_TRANSPARENT = "Interface\\AddOns\\Scoot\\ScootIconTransparent",
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

        -- Dual-row slots
        slotGap = 12,
        miniLabelHeight = 14,
        miniLabelGap = 3,
        maxClusterWidth = 410,
        slots = { toggle = 70, slider = 130, selector = 140, swatch = 28, input = 36 },

        -- Background z-stack and house alphas. The three sublevels are
        -- load-bearing: base fill below, emphasis fill above it, hover fill
        -- on top.
        sublevels = { bg = -8, fill = -7, hover = -6 },
        alphas = { hover = 0.08, emphasis = 0.03, selected = 0.12, borderNormal = 0.6, borderFocus = 1.0 },
    },
})

Skin.SetActive("tui")
