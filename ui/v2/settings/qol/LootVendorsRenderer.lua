-- LootVendorsRenderer.lua - Quality of Life: Loot & Vendors settings renderer
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.Settings = addon.UI.Settings or {}
addon.UI.Settings.QoL = addon.UI.Settings.QoL or {}
addon.UI.Settings.QoL.LootVendors = {}

local LootVendors = addon.UI.Settings.QoL.LootVendors
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

function LootVendors.Render(panel, scrollContent)
    panel:ClearContent()

    local builder = SettingsBuilder:CreateFor(scrollContent)
    panel._currentBuilder = builder

    -- Repair mode selector
    builder:AddSelector({
        label = "Repair Automatically",
        description = "Automatically repair all gear when visiting a merchant.",
        values = {
            off = "Off",
            personal = "Personal",
            guild = "Guild Bank",
        },
        order = { "off", "personal", "guild" },
        get = function()
            return getSetting("autoRepairMode") or "off"
        end,
        set = function(value)
            setSetting("autoRepairMode", value)
        end,
    })

    -- Sell grey items toggle
    builder:AddToggle({
        label = "Automatically Sell Grey Items",
        description = "Sell all poor-quality (grey) items when visiting a merchant.",
        get = function()
            return getSetting("sellGreyItems") or false
        end,
        set = function(value)
            setSetting("sellGreyItems", value)
        end,
    })

    -- Faster auto loot toggle
    builder:AddToggle({
        label = "Faster Auto Loot",
        description = "Speed up looting by automatically picking up all items.",
        infoIcon = {
            tooltipTitle = "Faster Auto Loot",
            tooltipText = "Enables Blizzard's auto loot and adds a quick retry to pick up any items the game misses on the first pass.",
        },
        get = function()
            return getSetting("quickLoot") or false
        end,
        set = function(value)
            setSetting("quickLoot", value)
        end,
    })

    builder:Finalize()
end

--------------------------------------------------------------------------------
-- Register Renderer
--------------------------------------------------------------------------------

addon.UI.SettingsPanel:RegisterRenderer("qolLootVendors", function(panel, scrollContent)
    LootVendors.Render(panel, scrollContent)
end)

return LootVendors
