-- QuestsRenderer.lua - Quality of Life: Quests settings renderer
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.Settings = addon.UI.Settings or {}
addon.UI.Settings.QoL = addon.UI.Settings.QoL or {}
addon.UI.Settings.QoL.Quests = {}

local Quests = addon.UI.Settings.QoL.Quests
local SettingsBuilder = addon.UI.SettingsBuilder

--------------------------------------------------------------------------------
-- DB Helpers
--------------------------------------------------------------------------------

-- Each addon sets addon.QoLHost in its own host file (core/qolhost.lua,
-- forever/qualityoflife/host.lua).
local function getSetting(key)
    return addon.QoLHost.Get(key)
end

local function setSetting(key, value)
    addon.QoLHost.Set(key, value)
end

--------------------------------------------------------------------------------
-- Render Function
--------------------------------------------------------------------------------

function Quests.Render(panel, scrollContent)
    panel:ClearContent()

    local builder = SettingsBuilder:CreateFor(scrollContent)
    panel._currentBuilder = builder

    builder:AddToggle({
        label = "Show Coordinates on Map",
        description = "Display cursor coordinates on the World Map when hovering over the map area.",
        get = function()
            return getSetting("showMapCoordinates") or false
        end,
        set = function(value)
            setSetting("showMapCoordinates", value)
            if addon.QoL and addon.QoL.updateMapCoordinates then
                addon.QoL.updateMapCoordinates()
            end
        end,
    })

    builder:AddToggle({
        label = "Show Quest Log Count",
        description = "Displays a quest count in the Quest Log showing how many quests you have toward the cap.",
        infoIcon = {
            tooltipTitle = "Quest Log Count",
            tooltipText = "Shows a count like \"12 / 35\" next to the gear icon in the Quest Log header. The text turns yellow when you have 3 or fewer slots remaining and red when you've reached the cap. World quests and bonus objectives do not count toward the cap.",
        },
        get = function()
            return getSetting("showQuestLogCount") or false
        end,
        set = function(value)
            setSetting("showQuestLogCount", value)
            if addon.QoL and addon.QoL.updateQuestCount then
                addon.QoL.updateQuestCount()
            end
        end,
    })

    builder:Finalize()
end

--------------------------------------------------------------------------------
-- Register Renderer
--------------------------------------------------------------------------------

addon.UI.SettingsPanel:RegisterRenderer("qolQuests", function(panel, scrollContent)
    Quests.Render(panel, scrollContent)
end)

return Quests
