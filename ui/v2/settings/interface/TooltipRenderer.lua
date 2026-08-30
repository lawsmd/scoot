-- TooltipRenderer.lua - Tooltip settings renderer
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.Settings = addon.UI.Settings or {}
addon.UI.Settings.Tooltip = {}

local Tooltip = addon.UI.Settings.Tooltip
local SettingsBuilder = addon.UI.SettingsBuilder

function Tooltip.Render(panel, scrollContent)
    -- Clear any existing content
    panel:ClearContent()

    -- Create builder for this content area
    local builder = SettingsBuilder:CreateFor(scrollContent)
    panel._currentBuilder = builder

    -- Store reference to this function for re-rendering on expand/collapse
    builder:SetOnRefresh(function()
        Tooltip.Render(panel, scrollContent)
    end)

    local Helpers = addon.UI.Settings.Helpers
    local h = Helpers.CreateComponentHelpers("tooltip")
    local getSetting = h.get
    local setSetting = h.setAndApply

    local function applyText()
        if addon and addon.ApplyStyles then
            addon:ApplyStyles()
        end
    end

    -- Shared text block for all three tabs: font/size/style only, no color
    -- or offset. Tooltip text is Blizzard-drawn and styled in place, so the
    -- plain style order applies and the style default is NONE. Writes route
    -- through EnsureComponentSubTable so a fresh profile keeps its sibling
    -- defaults (the old rawset idiom dropped them).
    local function addTextStyleBlock(tabBuilder, dbKey)
        local s = Helpers.CreateSubTableHelpers("tooltip", dbKey, { apply = applyText })
        tabBuilder:AddTextStyleBlock({
            get = s.get, set = s.set, apply = applyText,
            defaults = { style = "NONE", size = 12 },
            font = { description = "The font used for this text element." },
            style = { description = "The outline style for this text." },
            size = { min = 6, max = 32, minLabel = "6", maxLabel = "32",
                description = "The size of this text element." },
            color = false,
            offset = false,
        })
    end

    -- Parent-level toggle: Show Tooltip IDs
    builder:AddToggle({
        label = "Show Tooltip IDs",
        description = "Display spell, item, quest, and other IDs in tooltips.",
        get = function() return getSetting("showTooltipIDs") or false end,
        set = function(val) setSetting("showTooltipIDs", val) end,
    })


    -- Collapsible section: Sizing
    builder:AddCollapsibleSection({
        title = "Sizing",
        componentId = "tooltip",
        sectionKey = "sizing",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddSlider({
                label = "Tooltip Scale",
                description = "Scale the size of tooltips. Affects GameTooltip and comparison tooltips.",
                min = 0.5,
                max = 1.5,
                step = 0.05,
                get = function()
                    return getSetting("tooltipScale") or 1.0
                end,
                set = function(v)
                    setSetting("tooltipScale", v)
                end,
                minLabel = "50%",
                maxLabel = "150%",
                precision = 0,
                displayMultiplier = 100,
                displaySuffix = "%",
            })

            inner:Finalize()
        end,
    })

    -- Collapsible section: Border
    builder:AddCollapsibleSection({
        title = "Border",
        componentId = "tooltip",
        sectionKey = "border",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddToggleColorPicker({
                label = "Border Tint",
                get = function() return getSetting("borderTintEnable") or false end,
                set = function(v) setSetting("borderTintEnable", v) end,
                getColor = function()
                    local c = getSetting("borderTintColor") or {1, 1, 1, 1}
                    return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
                end,
                setColor = function(r, g, b, a)
                    setSetting("borderTintColor", {r, g, b, a})
                end,
                hasAlpha = true,
            })
            inner:Finalize()
        end,
    })

    -- Collapsible section: Text (with tabbed sub-sections)
    builder:AddCollapsibleSection({
        title = "Text",
        componentId = "tooltip",
        sectionKey = "text",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddTabbedSection({
                tabs = {
                    { key = "nameTitle", label = "Name & Title" },
                    { key = "everythingElse", label = "Everything Else" },
                    { key = "comparison", label = "Comparison" },
                },
                componentId = "tooltip",
                sectionKey = "textTabs",
                buildContent = {
                    nameTitle = function(tabContent, tabBuilder)
                        addTextStyleBlock(tabBuilder, "textTitle")

                        -- Class color toggle for player names
                        tabBuilder:AddToggle({
                            label = "Class Color Player Names",
                            description = "Color player character names by their class color. Does not affect NPCs.",
                            get = function()
                                return getSetting("classColorPlayerNames") or false
                            end,
                            set = function(val)
                                setSetting("classColorPlayerNames", val)
                            end,
                        })

                        tabBuilder:Finalize()
                    end,
                    everythingElse = function(tabContent, tabBuilder)
                        addTextStyleBlock(tabBuilder, "textEverythingElse")
                        tabBuilder:Finalize()
                    end,
                    comparison = function(tabContent, tabBuilder)
                        addTextStyleBlock(tabBuilder, "textComparison")
                        tabBuilder:Finalize()
                    end,
                },
            })

            inner:Finalize()
        end,
    })

    -- Collapsible section: Visibility
    builder:AddCollapsibleSection({
        title = "Visibility",
        componentId = "tooltip",
        sectionKey = "visibility",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddToggle({
                label = "Hide Tooltip Health Bar",
                description = "Hide the health bar that appears on unit tooltips.",
                get = function()
                    return getSetting("hideHealthBar") or false
                end,
                set = function(val)
                    setSetting("hideHealthBar", val)
                end,
            })

            inner:Finalize()
        end,
    })

    -- Finalize the layout
    builder:Finalize()
end

addon.UI.SettingsPanel:RegisterRenderer("tooltip", function(panel, scrollContent)
    Tooltip.Render(panel, scrollContent)
end)

return Tooltip
