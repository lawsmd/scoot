-- ReportsRenderer.lua - Reports: report list settings renderer
--
-- Settings that apply to every report sit under a Global header at the top,
-- followed by one collapsible section per registered report: an emphasized
-- enable toggle on top, that report's own settings in a tabbed section below.
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.Settings = addon.UI.Settings or {}
addon.UI.Settings.Reports = addon.UI.Settings.Reports or {}
addon.UI.Settings.Reports.ReportsList = {}

local ReportsListUI = addon.UI.Settings.Reports.ReportsList
local SettingsBuilder = addon.UI.SettingsBuilder

--------------------------------------------------------------------------------
-- Per-report settings tabs
--------------------------------------------------------------------------------
-- Keyed by report id. A report with no entry here renders as just its enable
-- toggle, so adding a report needs nothing in this file until it grows a
-- setting of its own. Values are read and written through Reports:GetSetting /
-- SetSetting, which stores them Zero-Touch and notifies open panels.
--------------------------------------------------------------------------------

local REPORT_TABS = {
    groupAnalysis = {
        {
            key = "roleIcons",
            label = "Role Icons",
            build = function(tabBuilder)
                local Reports = addon.Reports
                tabBuilder:AddSelector({
                    label = "Visibility",
                    description = "Show each player's assigned role beside their name, using the Raid Manager icon set.",
                    values = {
                        showAll = "Show All",
                        hideDPS = "Hide DPS Icons",
                        hideAll = "Hide All",
                    },
                    order = { "showAll", "hideDPS", "hideAll" },
                    get = function()
                        return Reports:GetSetting("groupAnalysis", "roleIconVisibility", "showAll")
                    end,
                    set = function(value)
                        -- Zero-Touch: the default is absence, not a stored value.
                        Reports:SetSetting("groupAnalysis", "roleIconVisibility",
                            value ~= "showAll" and value or nil)
                    end,
                })
            end,
        },
    },
}

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

    builder:AddDescription("Reports are on-demand summaries that open from the widget (the green diamond). Enable a report here to add it to the widget's click menu. Changes apply immediately, with no reload needed.")

    local Reports = addon.Reports
    if Reports then
        -- Settings that apply to every report, not to any one of them. Above
        -- the collapsibles so it stays visible once the list of reports grows.
        builder:AddSection("Global")
        builder:AddFontSelector({
            label = "Report Font",
            description = "Font used by every report panel.",
            get = function() return Reports:GetFontKey() end,
            set = function(value) Reports:SetFontKey(value) end,
        })
        builder:AddSlider({
            label = "Backdrop Opacity",
            description = "Opacity of the panel behind the widget's menu and every report. Text, borders and icons stay fully opaque. Defaults to match the Scoot settings window.",
            min = 1, max = 100, step = 1,
            get = function() return Reports:GetOpacity() end,
            set = function(value) Reports:SetOpacity(value) end,
        })

        for _, def in ipairs(Reports:GetAll()) do
            local componentId = "report_" .. def.id
            local tabs = REPORT_TABS[def.id]

            builder:AddCollapsibleSection({
                title = def.label,
                componentId = componentId,
                sectionKey = "main",
                defaultExpanded = false,
                buildContent = function(contentFrame, inner)
                    inner:AddToggle({
                        label = "Enable " .. def.label,
                        description = def.description,
                        emphasized = true,
                        get = function() return Reports:IsEnabled(def.id) end,
                        set = function(value) Reports:SetEnabled(def.id, value and true or false) end,
                    })

                    if tabs then
                        local tabDefs, buildContent = {}, {}
                        for _, tab in ipairs(tabs) do
                            table.insert(tabDefs, { key = tab.key, label = tab.label })
                            buildContent[tab.key] = function(cf, tabBuilder)
                                tab.build(tabBuilder)
                            end
                        end
                        inner:AddTabbedSection({
                            tabs = tabDefs,
                            componentId = componentId,
                            sectionKey = "tabs",
                            buildContent = buildContent,
                        })
                    end

                    inner:Finalize()
                end,
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
