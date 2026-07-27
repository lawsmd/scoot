-- ReportsRenderer.lua - Reports: report list settings renderer
--
-- v1: one enable toggle per registered report. This page will grow into
-- three groups — per-report toggles, per-report settings, global report
-- settings — once reports have settings of their own.
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.Settings = addon.UI.Settings or {}
addon.UI.Settings.Reports = addon.UI.Settings.Reports or {}
addon.UI.Settings.Reports.ReportsList = {}

local ReportsListUI = addon.UI.Settings.Reports.ReportsList
local SettingsBuilder = addon.UI.SettingsBuilder

--------------------------------------------------------------------------------
-- Render
--------------------------------------------------------------------------------

function ReportsListUI.Render(panel, scrollContent)
    panel:ClearContent()

    local builder = SettingsBuilder:CreateFor(scrollContent)
    panel._currentBuilder = builder

    -- Re-render on collapsible toggle so Y positions recompute and sections don't overlap.
    builder:SetOnRefresh(function()
        ReportsListUI.Render(panel, scrollContent)
    end)

    builder:AddDescription("Reports are on-demand summaries that open from the widget (the green diamond). Enable a report here to add it to the widget's click menu. Changes apply immediately — no reload needed.")

    local Reports = addon.Reports
    if Reports then
        for _, def in ipairs(Reports:GetAll()) do
            builder:AddToggle({
                label = def.label,
                description = def.description,
                get = function() return Reports:IsEnabled(def.id) end,
                set = function(value) Reports:SetEnabled(def.id, value and true or false) end,
            })
        end
    end

    builder:Finalize()
end

--------------------------------------------------------------------------------
-- Register Renderer
--------------------------------------------------------------------------------

addon.UI.SettingsPanel:RegisterRenderer("reportsList", function(panel, scrollContent)
    ReportsListUI.Render(panel, scrollContent)
end)

return ReportsListUI
