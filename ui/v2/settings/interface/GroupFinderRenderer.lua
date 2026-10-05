-- GroupFinderRenderer.lua - the Group Finder page: the ways the window opens
--
-- Two switches, both on while nothing is stored: the /lfg word and the row
-- in the widget's click menu. Each is read at the moment it is used
-- (core/components/groupfinder/core.lua), so a change takes without a
-- reload. /scoot lfg opens the window whatever these say.
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.Settings = addon.UI.Settings or {}
addon.UI.Settings.GroupFinder = {}

local Page = addon.UI.Settings.GroupFinder
local SettingsBuilder = addon.UI.SettingsBuilder

function Page.Render(panel, scrollContent)
    panel:ClearContent()

    local builder = SettingsBuilder:CreateFor(scrollContent)
    panel._currentBuilder = builder

    builder:SetOnRefresh(function()
        Page.Render(panel, scrollContent)
    end)

    local Helpers = addon.UI.Settings.Helpers
    local h = Helpers.CreateComponentHelpers("groupfinder")

    builder:AddDescription(
        "Scoot's own Premade Groups window in place of Blizzard's. " ..
        "It opens from the widget's click menu and from /lfg; /scoot lfg always opens it."
    )

    builder:AddSection("Opening the window")

    builder:AddToggle({
        label = "Slash Command",
        description = "/lfg opens and closes the window.",
        get = function() return h.get("slashCommand") ~= false end,
        set = function(value) h.set("slashCommand", value and true or false) end,
    })

    builder:AddToggle({
        label = "Widget",
        description = "A Group Finder row in the widget's click menu. The widget is the Reports/Widget module on the Features page.",
        get = function() return h.get("widgetLaunch") ~= false end,
        set = function(value) h.set("widgetLaunch", value and true or false) end,
    })

    builder:Finalize()
end

addon.UI.SettingsPanel:RegisterRenderer("groupFinder", function(panel, scrollContent)
    Page.Render(panel, scrollContent)
end)

return Page
