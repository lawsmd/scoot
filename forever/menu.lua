--------------------------------------------------------------------------------
-- forever/menu.lua
-- Camelot's page tree for the settings panel.
--
-- The framework in ui/v2 reads addon.UI.Navigation.NavModel at call time and
-- draws whatever it holds; Scoot fills it from ui/v2/settings/NavModel.lua
-- and this file fills it for Camelot. A child key with no renderer draws the
-- framework's "not yet implemented" placeholder, which is the honest state
-- of every page until its renderer registers through
-- addon.UI.SettingsPanel:RegisterRenderer.
--------------------------------------------------------------------------------

local addonName, addon = ...

local Navigation = addon.UI.Navigation

Navigation.NavModel = {
    -- The two pages of Scoot's Profiles section that stand on the shared
    -- engine alone. Presets and Rules read Scoot's preset and rules engines.
    {
        key = "profiles",
        label = "Profiles",
        collapsible = true,
        children = {
            { key = "profilesManage", label = "Manage Profiles" },
            { key = "profilesImportExport", label = "Import/Export" },
        },
    },
    -- The Global Font values behind the font picker's token band. The
    -- renderer registers the Bar Texture page too; it joins this list with
    -- Camelot's first bar texture field.
    {
        key = "applyAll",
        label = "Apply All",
        collapsible = true,
        children = {
            { key = "applyAllFonts", label = "Font" },
        },
    },
    {
        key = "unitFrames",
        label = "Unit Frames",
        collapsible = true,
        children = {
            { key = "ufPlayer", label = "Player" },
            { key = "ufTarget", label = "Target" },
            { key = "ufFocus", label = "Focus" },
            { key = "ufTargetOfTarget", label = "Target of Target" },
            { key = "ufPet", label = "Pet" },
        },
    },
    {
        key = "castBars",
        label = "Cast Bars",
        collapsible = true,
        children = {
            { key = "castBarPlayer", label = "Player" },
        },
    },
}

-- The title bar and the toolbar. The skin's titleBar role picks how the
-- title is presented. The texture is the banner logo, which fills the
-- texCoord rectangle of its 1024x512 file with clear canvas around it; the
-- text stands where a skin draws no texture. The toolbar is Scoot's four
-- buttons in Scoot's order.
addon.UI.SettingsPanel.HeaderModel = {
    title = {
        text = "Camelot",
        texture = addon.MediaPath .. "forever\\media\\CamelotBanner",
        texCoord = { 4/1024, 1020/1024, 113/512, 399/512 },
        aspect = 1016 / 286,
    },
    toolbar = {
        { key = "features", label = "Features", action = { kind = "page", page = "features" } },
        { key = "search", label = "Search", action = { kind = "page", page = "search" } },
        { key = "editMode", label = "Edit Mode", action = { kind = "editMode" } },
        {
            key = "cdm", label = "Cooldown Manager",
            action = {
                kind = "call",
                fn = function(panel)
                    addon:OpenCooldownManagerSettings()
                    if panel.frame and panel.frame:IsShown() then
                        panel.frame:Hide()
                    end
                end,
            },
        },
    },
}

-- The Features page is Scoot's renderer over Camelot's list
-- (forever/features.lua), which the owning files have filled by now.
addon.UI.SettingsPanel.FeaturesModel = addon.Features.BuildModel()

-- The home page, the panel's first screen. Camelot has not designed one, so
-- the three pieces the framework draws there stay off: the product title with
-- its version beside it, the feature guide, and the accent color picker in the
-- bottom-left corner. Deleting a line brings that piece back.
addon.UI.SettingsPanel.HomeModel = {
    title = false,
    featureGuide = false,
    accentColor = false,
}

-- The Apply All fonts page's explainer takes this as its second sentence. The renderer
-- is shared and its own text is generic; what Camelot's elements do with the
-- Global Fonts is Camelot's to say.
addon.UI.SettingsPanel.ApplyAllModel = {
    fontsNote = "Most Camelot elements use these fonts by default.",
}

-- The Forever skin is Camelot's default. tui stays registered so
-- /camelot debug skin tui can show the framework's own look when a difference
-- has to be told apart from the skin's.
addon.UI.Skin.SetActive("forever")
