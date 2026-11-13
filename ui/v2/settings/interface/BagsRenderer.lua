-- BagsRenderer.lua - the Bags page: the bag window's lines and the pieces
-- around them. Every value takes at once through the component's
-- ApplyStyling (core/components/bags/core.lua).
local _, addon = ...

addon.UI = addon.UI or {}
addon.UI.Settings = addon.UI.Settings or {}
addon.UI.Settings.Bags = {}

local Page = addon.UI.Settings.Bags
local SettingsBuilder = addon.UI.SettingsBuilder

function Page.Render(panel, scrollContent)
    panel:ClearContent()

    local builder = SettingsBuilder:CreateFor(scrollContent)
    panel._currentBuilder = builder

    builder:SetOnRefresh(function()
        Page.Render(panel, scrollContent)
    end)

    local Helpers = addon.UI.Settings.Helpers
    local h = Helpers.CreateComponentHelpers("bags")

    builder:AddSlider({
        label = "Slots per Row",
        min = 6,
        max = 16,
        step = 1,
        get = function() return h.get("columns") or 8 end,
        set = function(v) h.setAndApplyComponent("columns", v) end,
    })

    builder:AddSlider({
        label = "Size",
        min = 50,
        max = 200,
        step = 5,
        get = function() return h.get("scale") or 90 end,
        set = function(v) h.setAndApplyComponent("scale", v) end,
    })

    builder:AddToggle({
        label = "Show Free Slots",
        get = function() return h.get("showFreeSlots") ~= false end,
        set = function(value) h.setAndApplyComponent("showFreeSlots", value and true or false) end,
    })

    builder:AddToggle({
        label = "Show Sort Button",
        get = function() return h.get("showSortButton") ~= false end,
        set = function(value) h.setAndApplyComponent("showSortButton", value and true or false) end,
    })

    builder:AddToggle({
        label = "Show Delete Button",
        get = function() return h.get("showDelete") ~= false end,
        set = function(value) h.setAndApplyComponent("showDelete", value and true or false) end,
    })

    builder:Finalize()
end

addon.UI.SettingsPanel:RegisterRenderer("bags", function(panel, scrollContent)
    Page.Render(panel, scrollContent)
end)

return Page
