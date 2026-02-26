-- NotesRenderer.lua - Notes settings renderer
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.Settings = addon.UI.Settings or {}
addon.UI.Settings.Notes = {}

local Notes = addon.UI.Settings.Notes
local SettingsBuilder = addon.UI.SettingsBuilder
local Controls = addon.UI.Controls

local MAX_NOTES = 5

local INSERT_CHARS = {
    { char = "\226\128\148", label = "\226\128\148" },                                                                  -- em-dash
    { char = "\194\183",     label = "\194\183" },                                                                       -- middle dot
    { char = "|A:coin-gold:0:0|a",   label = "|A:coin-gold:12:12|a" },                                                  -- gold coin
    { char = "|A:coin-silver:0:0|a", label = "|A:coin-silver:12:12|a" },                                                -- silver coin
    { char = "|A:coin-copper:0:0|a", label = "|A:coin-copper:12:12|a" },                                                -- copper coin
    { char = "|A:Professions-ChatIcon-Quality-Tier1:0:0|a", label = "|A:Professions-ChatIcon-Quality-Tier1:12:12|a" },  -- quality 1
    { char = "|A:Professions-ChatIcon-Quality-Tier2:0:0|a", label = "|A:Professions-ChatIcon-Quality-Tier2:12:12|a" },  -- quality 2
    { char = "|A:Professions-ChatIcon-Quality-Tier3:0:0|a", label = "|A:Professions-ChatIcon-Quality-Tier3:12:12|a" },  -- quality 3
    { char = "|A:Professions-ChatIcon-Quality-Tier4:0:0|a", label = "|A:Professions-ChatIcon-Quality-Tier4:12:12|a" },  -- quality 4
    { char = "|A:Professions-ChatIcon-Quality-Tier5:0:0|a", label = "|A:Professions-ChatIcon-Quality-Tier5:12:12|a" },  -- quality 5
}
local CHAR_BTN_SIZE = 20
local CHAR_BTN_GAP = 4

--------------------------------------------------------------------------------
-- Insert-character buttons for Body Text
--------------------------------------------------------------------------------

local function CreateInsertButtons(editBoxControl, controlsList)
    local innerEditBox = editBoxControl._editBox
    if not innerEditBox then return end

    local prevBtn
    for i = #INSERT_CHARS, 1, -1 do
        local info = INSERT_CHARS[i]
        local btn = Controls:CreateButton({
            parent = editBoxControl,
            text = info.label,
            width = CHAR_BTN_SIZE,
            height = CHAR_BTN_SIZE,
            fontSize = 11,
            borderWidth = 1,
            borderAlpha = 0.4,
            onClick = function()
                local cursorPos = innerEditBox:GetCursorPosition() or 0
                innerEditBox:SetFocus()
                innerEditBox:SetCursorPosition(cursorPos)
                innerEditBox:Insert(info.char)
            end,
        })

        btn:ClearAllPoints()
        if not prevBtn then
            btn:SetPoint("TOPRIGHT", editBoxControl, "TOPRIGHT", 0, 0)
        else
            btn:SetPoint("RIGHT", prevBtn, "LEFT", -CHAR_BTN_GAP, 0)
        end
        prevBtn = btn

        table.insert(controlsList, btn)
    end
end

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
                                key = prefix .. "BodyEdit",
                                get = function() return h.get(prefix .. "BodyText") or "" end,
                                set = function(text) h.setAndApply(prefix .. "BodyText", text) end,
                            })

                            local editControl = tabBuilder:GetControl(prefix .. "BodyEdit")
                            if editControl then
                                CreateInsertButtons(editControl, tabBuilder._controls)
                            end

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
