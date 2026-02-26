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

local function getQoL()
    local profile = addon and addon.db and addon.db.profile
    return profile and profile.qol
end

local function ensureQoL()
    if not (addon and addon.db and addon.db.profile) then return nil end
    addon.db.profile.qol = addon.db.profile.qol or {}
    return addon.db.profile.qol
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
            local q = getQoL()
            return (q and q.showMapCoordinates) or false
        end,
        set = function(value)
            local q = ensureQoL()
            if not q then return end
            q.showMapCoordinates = value
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
            local q = getQoL()
            return (q and q.showQuestLogCount) or false
        end,
        set = function(value)
            local q = ensureQoL()
            if not q then return end
            q.showQuestLogCount = value
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
