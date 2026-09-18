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
    {
        key = "unitFrames",
        label = "Unit Frames",
        collapsible = true,
        children = {
            { key = "ufPlayer", label = "Player" },
        },
    },
}

-- The title bar and the toolbar. The skin's titleBar role picks how the
-- title is presented; Camelot has no ASCII art, so the text stands. Search
-- and Edit Mode are the toolbar: the Features and Cooldown Manager pages are
-- Scoot's.
addon.UI.SettingsPanel.HeaderModel = {
    title = { text = "Camelot" },
    toolbar = {
        { key = "search", label = "Search", action = { kind = "page", page = "search" } },
        { key = "editMode", label = "Edit Mode", action = { kind = "editMode" } },
    },
}

-- The Forever skin is Camelot's default. tui stays registered so
-- /camelot debug skin tui can show the framework's own look when a difference
-- has to be told apart from the skin's.
addon.UI.Skin.SetActive("forever")
