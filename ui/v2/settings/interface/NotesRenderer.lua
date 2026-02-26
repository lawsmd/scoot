-- NotesRenderer.lua - Notes settings renderer
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.Settings = addon.UI.Settings or {}
addon.UI.Settings.Notes = {}

local Notes = addon.UI.Settings.Notes
local SettingsBuilder = addon.UI.SettingsBuilder

local MAX_NOTES = 5

--------------------------------------------------------------------------------
-- Render Function
--------------------------------------------------------------------------------

function Notes.Render(panel, scrollContent)
    panel:ClearContent()

    local builder = SettingsBuilder:CreateFor(scrollContent)
    panel._currentBuilder = builder

    builder:SetOnRefresh(function()
        Notes.Render(panel, scrollContent)
    end)

    local Helpers = addon.UI.Settings.Helpers
    local h = Helpers.CreateComponentHelpers("notes")

    -- Explainer text
    builder:AddDescription(
        "Notes are static on-screen text fields styled like your tooltip. " ..
        "Font, size, style, and border tint are inherited from your Tooltip settings. " ..
        "Drag notes to reposition them in Edit Mode."
    )

    -- Per-note collapsible sections
    for i = 1, MAX_NOTES do
        local noteIndex = i
        local prefix = "note" .. noteIndex

        builder:AddCollapsibleSection({
            title = "Note " .. noteIndex,
            componentId = "notes",
            sectionKey = "note" .. noteIndex,
            defaultExpanded = false,
            buildContent = function(contentFrame, inner)

                -- Enable toggle
                inner:AddToggle({
                    key = prefix .. "Enabled",
                    label = "Enable Note " .. noteIndex,
                    description = "Show this note on your screen.",
                    emphasized = true,
                    get = function() return h.get(prefix .. "Enabled") or false end,
                    set = function(val) h.setAndApply(prefix .. "Enabled", val) end,
                })

                -- Tabbed section: Content + Settings
                inner:AddTabbedSection({
                    tabs = {
                        { key = "content", label = "Content" },
                        { key = "settings", label = "Settings" },
                    },
                    componentId = "notes",
                    sectionKey = prefix .. "Tabs",
                    buildContent = {
                        -- Content tab
                        content = function(tabContent, tabBuilder)
                            tabBuilder:AddTextInput({
                                label = "Header Text",
                                placeholder = "Enter header text...",
                                maxLetters = 100,
                                get = function() return h.get(prefix .. "HeaderText") or "" end,
                                set = function(text) h.setAndApply(prefix .. "HeaderText", text) end,
                            })

                            tabBuilder:AddMultiLineEditBox({
                                label = "Body Text",
                                placeholder = "Enter body text...",
                                height = 160,
                                get = function() return h.get(prefix .. "BodyText") or "" end,
                                set = function(text) h.setAndApply(prefix .. "BodyText", text) end,
                            })

                            tabBuilder:Finalize()
                        end,

                        -- Settings tab
                        settings = function(tabContent, tabBuilder)
                            tabBuilder:AddSlider({
                                label = "Scale",
                                min = 0.25,
                                max = 2.0,
                                step = 0.05,
                                precision = 2,
                                minLabel = "25%",
                                maxLabel = "200%",
                                get = function() return h.get(prefix .. "Scale") or 1.0 end,
                                set = function(val) h.setAndApply(prefix .. "Scale", val) end,
                            })

                            tabBuilder:AddColorPicker({
                                label = "Header Text Color",
                                get = function() return h.get(prefix .. "HeaderColor") or { 0.1, 1.0, 0.1, 1 } end,
                                set = function(r, g, b, a) h.setAndApply(prefix .. "HeaderColor", { r, g, b, a }) end,
                                hasAlpha = true,
                            })

                            tabBuilder:AddColorPicker({
                                label = "Body Text Color",
                                get = function() return h.get(prefix .. "BodyColor") or { 1, 1, 1, 1 } end,
                                set = function(r, g, b, a) h.setAndApply(prefix .. "BodyColor", { r, g, b, a }) end,
                                hasAlpha = true,
                            })

                            tabBuilder:Finalize()
                        end,
                    },
                })

                inner:Finalize()
            end,
        })
    end

    builder:Finalize()
end

--------------------------------------------------------------------------------
-- Self-register with settings panel
addon.UI.SettingsPanel:RegisterRenderer("notes", function(panel, scrollContent)
    Notes.Render(panel, scrollContent)
end)

--------------------------------------------------------------------------------
-- Return module
--------------------------------------------------------------------------------

return Notes
