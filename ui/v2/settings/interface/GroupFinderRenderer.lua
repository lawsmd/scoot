-- GroupFinderRenderer.lua - the Group Finder page: the ways the window opens
--
-- Four switches, all on while nothing is stored: the /lfg word, the row in
-- the widget's click menu, the button on Blizzard's PVEFrame and Scoot's
-- queue eye. Each is read at the moment it is used or refreshed on change
-- (core/components/groupfinder/core.lua, ui/v2/groupfinder/pvebutton.lua,
-- queueeye.lua), so a change takes without a reload. /scoot lfg opens the
-- window whatever these say.
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
        "It opens from the widget's click menu, /lfg, a button on Blizzard's Group Finder and the queue eye; " ..
        "/scoot lfg always opens it."
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

    local GF = addon.GroupFinder

    builder:AddToggle({
        label = "Group Finder Button",
        get = function() return h.get("pveButton") ~= false end,
        set = function(value)
            h.set("pveButton", value and true or false)
            if GF.PVEButton then GF.PVEButton.Refresh() end
        end,
    })

    builder:AddToggle({
        label = "Queue Eye",
        get = function() return h.get("queueEye") ~= false end,
        set = function(value)
            h.set("queueEye", value and true or false)
            if GF.QueueEye then GF.QueueEye.Refresh() end
        end,
    })

    builder:Finalize()
end

addon.UI.SettingsPanel:RegisterRenderer("groupFinder", function(panel, scrollContent)
    Page.Render(panel, scrollContent)
end)

return Page
