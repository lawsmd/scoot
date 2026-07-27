-- ReportStyleRenderer.lua - Reports: Report Style settings renderer
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.Settings = addon.UI.Settings or {}
addon.UI.Settings.Reports = addon.UI.Settings.Reports or {}
addon.UI.Settings.Reports.ReportStyle = {}

local ReportStyleUI = addon.UI.Settings.Reports.ReportStyle
local SettingsBuilder = addon.UI.SettingsBuilder

--------------------------------------------------------------------------------
-- Render
--------------------------------------------------------------------------------

function ReportStyleUI.Render(panel, scrollContent)
    panel:ClearContent()

    local builder = SettingsBuilder:CreateFor(scrollContent)
    panel._currentBuilder = builder

    -- Re-render on collapsible toggle so Y positions recompute and sections don't overlap.
    builder:SetOnRefresh(function()
        ReportStyleUI.Render(panel, scrollContent)
    end)

    builder:AddDescription("Controls for the appearance and style of reports will live here.")

    builder:Finalize()
end

--------------------------------------------------------------------------------
-- Register Renderer
--------------------------------------------------------------------------------

addon.UI.SettingsPanel:RegisterRenderer("reportsStyle", function(panel, scrollContent)
    ReportStyleUI.Render(panel, scrollContent)
end)

return ReportStyleUI
