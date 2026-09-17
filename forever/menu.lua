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
