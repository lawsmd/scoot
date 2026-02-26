-- MiscRenderer.lua - Miscellaneous settings renderer
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.Settings = addon.UI.Settings or {}
addon.UI.Settings.Misc = {}

local Misc = addon.UI.Settings.Misc
local SettingsBuilder = addon.UI.SettingsBuilder

--------------------------------------------------------------------------------
-- Render Function
--------------------------------------------------------------------------------

function Misc.Render(panel, scrollContent)
    panel:ClearContent()

    local builder = SettingsBuilder:CreateFor(scrollContent)
    panel._currentBuilder = builder

    -- Helper to get/set misc profile settings
    local function getMiscSetting(key)
        local profile = addon.db and addon.db.profile
        return profile and profile.misc and profile.misc[key]
    end

    local function setMiscSetting(key, value)
        if not (addon.db and addon.db.profile) then return end
        addon.db.profile.misc = addon.db.profile.misc or {}
        addon.db.profile.misc[key] = value
    end

    builder:AddToggle({
        label = "Custom Game Menu",
        description = "Replace the default Escape menu with a Scoot-themed version.",
        get = function()
            return getMiscSetting("customGameMenu") or false
        end,
        set = function(val)
            setMiscSetting("customGameMenu", val)
        end,
        infoIcon = {
            tooltipTitle = "Custom Game Menu",
            tooltipText = "When enabled, pressing Escape will open a Scoot-styled game menu instead of the default Blizzard menu. Disable this toggle to restore the original menu.",
        },
    })

    builder:Finalize()
end

--------------------------------------------------------------------------------
-- Self-register with settings panel
addon.UI.SettingsPanel:RegisterRenderer("misc", function(panel, scrollContent)
    Misc.Render(panel, scrollContent)
end)

-- Return module
--------------------------------------------------------------------------------

return Misc
