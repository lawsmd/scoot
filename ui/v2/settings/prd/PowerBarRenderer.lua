-- PowerBarRenderer.lua - Personal Resource Display Power Bar settings renderer
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.Settings = addon.UI.Settings or {}
addon.UI.Settings.PRD = addon.UI.Settings.PRD or {}
addon.UI.Settings.PRD.PowerBar = {}

local PowerBar = addon.UI.Settings.PRD.PowerBar
local SettingsBuilder = addon.UI.SettingsBuilder

local Helpers = addon.UI.Settings.Helpers
local textColorPowerValues = Helpers.textColorPowerValues
local textColorPowerOrder = Helpers.textColorPowerOrder

function PowerBar.Render(panel, scrollContent)
    panel:ClearContent()

    local builder = SettingsBuilder:CreateFor(scrollContent)
    panel._currentBuilder = builder

    builder:SetOnRefresh(function()
        PowerBar.Render(panel, scrollContent)
    end)

    local h = Helpers.CreateComponentHelpers("prdPower")
    local getComponent, getSetting = h.getComponent, h.get
    local setSetting = h.setAndApplyComponent

    -- Build border options
    local function getBorderOptions()
        local values = { none = "None", square = "Default (Square)" }
        local order = { "none", "square" }
        if addon.BuildBarBorderOptionsContainer then
            local data = addon.BuildBarBorderOptionsContainer()
            if data and #data > 0 then
                values = { none = "None" }
                order = { "none" }
                for _, entry in ipairs(data) do
                    local key = entry.value or entry.key
                    local label = entry.text or entry.label or key
                    if key then
                        values[key] = label
                        table.insert(order, key)
                    end
                end
            end
        end
        return values, order
    end

    ---------------------------------------------------------------------------
    -- Sizing Section
    ---------------------------------------------------------------------------
    builder:AddCollapsibleSection({
        title = "Sizing",
        componentId = "prdPower",
        sectionKey = "sizing",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddSlider({
                label = "Bar Height",
                min = 4, max = 40, step = 1,
                get = function() return getSetting("barHeight") or 8 end,
                set = function(v) setSetting("barHeight", v) end,
                minLabel = "4", maxLabel = "40",
                infoIcon = {
                    tooltipTitle = "Power Bar Height",
                    tooltipText = "Width automatically follows the Health Bar width.",
                },
            })

            inner:Finalize()
        end,
    })

    ---------------------------------------------------------------------------
    -- Style Section
    ---------------------------------------------------------------------------
    builder:AddCollapsibleSection({
        title = "Style",
        componentId = "prdPower",
        sectionKey = "style",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddDualBarStyleRow({
                label = "Foreground",
                getTexture = function() return getSetting("styleForegroundTexture") or "default" end,
                setTexture = function(v) setSetting("styleForegroundTexture", v) end,
                colorValues = {
                    default = "Default",
                    power = "Power Color",
                    custom = "Custom",
                },
                colorOrder = { "default", "power", "custom" },
                getColorMode = function() return getSetting("styleForegroundColorMode") or "default" end,
                setColorMode = function(v) setSetting("styleForegroundColorMode", v) end,
                getColor = function()
                    local c = getSetting("styleForegroundTint") or {1, 1, 1, 1}
                    return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
                end,
                setColor = function(r, g, b, a)
                    setSetting("styleForegroundTint", {r, g, b, a})
                end,
                customColorValue = "custom",
                hasAlpha = true,
            })

            inner:AddSpacer(8)

            inner:AddDualBarStyleRow({
                label = "Background",
                getTexture = function() return getSetting("styleBackgroundTexture") or "default" end,
                setTexture = function(v) setSetting("styleBackgroundTexture", v) end,
                colorValues = {
                    default = "Default",
                    custom = "Custom",
                },
                colorOrder = { "default", "custom" },
                getColorMode = function() return getSetting("styleBackgroundColorMode") or "default" end,
                setColorMode = function(v) setSetting("styleBackgroundColorMode", v) end,
                getColor = function()
                    local c = getSetting("styleBackgroundTint") or {0, 0, 0, 1}
                    return c[1] or 0, c[2] or 0, c[3] or 0, c[4] or 1
                end,
                setColor = function(r, g, b, a)
                    setSetting("styleBackgroundTint", {r, g, b, a})
                end,
                customColorValue = "custom",
                hasAlpha = true,
            })

            inner:AddSlider({
                label = "Background Opacity",
                min = 0, max = 100, step = 1,
                get = function() return getSetting("styleBackgroundOpacity") or 50 end,
                set = function(v) setSetting("styleBackgroundOpacity", v) end,
                minLabel = "0%", maxLabel = "100%",
            })

            inner:Finalize()
        end,
    })

    ---------------------------------------------------------------------------
    -- Border Section
    ---------------------------------------------------------------------------
    builder:AddCollapsibleSection({
        title = "Border",
        componentId = "prdPower",
        sectionKey = "border",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddBarBorderSelector({
                label = "Border Style",
                includeNone = true,
                get = function() return getSetting("borderStyle") or "square" end,
                set = function(v) setSetting("borderStyle", v) end,
            })

            inner:AddToggleColorPicker({
                label = "Border Tint",
                getToggle = function() return getSetting("borderTintEnable") or false end,
                setToggle = function(v) setSetting("borderTintEnable", v) end,
                getColor = function()
                    local c = getSetting("borderTintColor") or {1, 1, 1, 1}
                    return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
                end,
                setColor = function(r, g, b, a)
                    setSetting("borderTintColor", {r, g, b, a})
                end,
                hasAlpha = true,
            })

            inner:AddSlider({
                label = "Border Thickness",
                min = 1, max = 8, step = 0.5, precision = 1,
                get = function() return getSetting("borderThickness") or 1 end,
                set = function(v) setSetting("borderThickness", v) end,
                minLabel = "1", maxLabel = "8",
            })

            inner:Finalize()
        end,
    })

    ---------------------------------------------------------------------------
    -- Text Section (Tabbed: Value Text / % Text)
    ---------------------------------------------------------------------------
    builder:AddCollapsibleSection({
        title = "Text",
        componentId = "prdPower",
        sectionKey = "text",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            local textTabs = {
                {
                    key = "valueText",
                    label = "Value Text",
                    infoIcon = {
                        tooltipTitle = "Value Text",
                        tooltipText = "Displays current power as a number on the PRD power bar.",
                    },
                },
                {
                    key = "percentText",
                    label = "% Text",
                    infoIcon = {
                        tooltipTitle = "Percentage Text",
                        tooltipText = "Displays current power as a percentage on the PRD power bar.",
                    },
                },
            }

            inner:AddTabbedSection({
                tabs = textTabs,
                componentId = "prdPower",
                sectionKey = "textTabs",
                buildContent = {
                    valueText = function(cf, tabInner)
                        tabInner:AddToggle({
                            label = "Show Value Text",
                            get = function() return getSetting("valueTextShow") or false end,
                            set = function(v) setSetting("valueTextShow", v) end,
                        })

                        tabInner:AddFontSelector({
                            label = "Font",
                            get = function() return getSetting("valueTextFont") or "Friz Quadrata TT" end,
                            set = function(v) setSetting("valueTextFont", v) end,
                        })

                        tabInner:AddSlider({
                            label = "Font Size",
                            min = 6, max = 24, step = 1,
                            get = function() return getSetting("valueTextFontSize") or 10 end,
                            set = function(v) setSetting("valueTextFontSize", v) end,
                            minLabel = "6", maxLabel = "24",
                        })

                        tabInner:AddSelector({
                            label = "Font Style",
                            values = Helpers.fontStyleValues,
                            order = { "OUTLINE", "NONE", "THICKOUTLINE", "HEAVYTHICKOUTLINE", "SHADOW", "SHADOWOUTLINE", "SHADOWTHICKOUTLINE" },
                            get = function() return getSetting("valueTextFontFlags") or "OUTLINE" end,
                            set = function(v) setSetting("valueTextFontFlags", v) end,
                        })

                        tabInner:AddSelectorColorPicker({
                            label = "Font Color",
                            values = textColorPowerValues,
                            order = textColorPowerOrder,
                            get = function() return getSetting("valueTextColorMode") or "default" end,
                            set = function(v) setSetting("valueTextColorMode", v or "default") end,
                            getColor = function()
                                local c = getSetting("valueTextColor") or {1, 1, 1, 1}
                                return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
                            end,
                            setColor = function(r, g, b, a)
                                setSetting("valueTextColor", {r, g, b, a})
                            end,
                            customValue = "custom",
                            hasAlpha = true,
                        })

                        tabInner:AddSelector({
                            label = "Text Alignment",
                            values = {
                                LEFT = "Left",
                                CENTER = "Center",
                                RIGHT = "Right",
                            },
                            order = { "RIGHT", "LEFT", "CENTER" },
                            get = function() return getSetting("valueTextAlignment") or "RIGHT" end,
                            set = function(v) setSetting("valueTextAlignment", v) end,
                        })

                        tabInner:Finalize()
                    end,
                    percentText = function(cf, tabInner)
                        tabInner:AddToggle({
                            label = "Show % Text",
                            get = function() return getSetting("percentTextShow") or false end,
                            set = function(v) setSetting("percentTextShow", v) end,
                        })

                        tabInner:AddFontSelector({
                            label = "Font",
                            get = function() return getSetting("percentTextFont") or "Friz Quadrata TT" end,
                            set = function(v) setSetting("percentTextFont", v) end,
                        })

                        tabInner:AddSlider({
                            label = "Font Size",
                            min = 6, max = 24, step = 1,
                            get = function() return getSetting("percentTextFontSize") or 10 end,
                            set = function(v) setSetting("percentTextFontSize", v) end,
                            minLabel = "6", maxLabel = "24",
                        })

                        tabInner:AddSelector({
                            label = "Font Style",
                            values = Helpers.fontStyleValues,
                            order = { "OUTLINE", "NONE", "THICKOUTLINE", "HEAVYTHICKOUTLINE", "SHADOW", "SHADOWOUTLINE", "SHADOWTHICKOUTLINE" },
                            get = function() return getSetting("percentTextFontFlags") or "OUTLINE" end,
                            set = function(v) setSetting("percentTextFontFlags", v) end,
                        })

                        tabInner:AddSelectorColorPicker({
                            label = "Font Color",
                            values = textColorPowerValues,
                            order = textColorPowerOrder,
                            get = function() return getSetting("percentTextColorMode") or "default" end,
                            set = function(v) setSetting("percentTextColorMode", v or "default") end,
                            getColor = function()
                                local c = getSetting("percentTextColor") or {1, 1, 1, 1}
                                return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
                            end,
                            setColor = function(r, g, b, a)
                                setSetting("percentTextColor", {r, g, b, a})
                            end,
                            customValue = "custom",
                            hasAlpha = true,
                        })

                        tabInner:AddSelector({
                            label = "Text Alignment",
                            values = {
                                LEFT = "Left",
                                CENTER = "Center",
                                RIGHT = "Right",
                            },
                            order = { "LEFT", "RIGHT", "CENTER" },
                            get = function() return getSetting("percentTextAlignment") or "LEFT" end,
                            set = function(v) setSetting("percentTextAlignment", v) end,
                        })

                        tabInner:Finalize()
                    end,
                },
            })

            inner:Finalize()
        end,
    })

    ---------------------------------------------------------------------------
    -- Visibility Section
    ---------------------------------------------------------------------------
    builder:AddCollapsibleSection({
        title = "Visibility",
        componentId = "prdPower",
        sectionKey = "visibility",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddToggle({
                label = "Hide Power Bar",
                get = function() return getSetting("hideBar") or false end,
                set = function(v) setSetting("hideBar", v) end,
            })

            inner:AddToggle({
                label = "Hide the Bar but not its Text",
                get = function() return getSetting("hideTextureOnly") or false end,
                set = function(v) setSetting("hideTextureOnly", v) end,
                infoIcon = {
                    tooltipTitle = "Hide the Bar but not its Text",
                    tooltipText = "Hides the bar texture and background, showing only the text overlay. Useful for a number-only display of your power resource.",
                },
            })

            inner:AddToggle({
                label = "Hide Full Bar Animations",
                get = function() return getSetting("hideSpikeAnimations") or false end,
                set = function(v) setSetting("hideSpikeAnimations", v) end,
                infoIcon = {
                    tooltipTitle = "Hide Full Bar Animations",
                    tooltipText = "Hides the 'spike' animations that play when your power bar reaches full.",
                },
            })

            inner:AddToggle({
                label = "Hide Power Feedback",
                get = function() return getSetting("hidePowerFeedback") or false end,
                set = function(v) setSetting("hidePowerFeedback", v) end,
                infoIcon = {
                    tooltipTitle = "Hide Power Feedback",
                    tooltipText = "Hides the visual feedback animation when power is gained or spent.",
                },
            })

            inner:AddToggle({
                label = "Hide Mana Cost Predictions",
                get = function() return getSetting("hideManaCostPrediction") or false end,
                set = function(v) setSetting("hideManaCostPrediction", v) end,
                infoIcon = {
                    tooltipTitle = "Hide Mana Cost Predictions",
                    tooltipText = "Hides the mana cost prediction bar that appears when casting spells. This blue overlay shows how much power will be consumed by the current cast.",
                },
            })

            inner:AddSpacer(12)

            inner:AddSlider({
                label = "Opacity in Combat",
                min = 1, max = 100, step = 1,
                get = function() return getSetting("opacityInCombat") or 100 end,
                set = function(v)
                    setSetting("opacityInCombat", v)
                    if addon.RefreshPRDOpacity then addon.RefreshPRDOpacity("prdPower") end
                end,
                minLabel = "1%", maxLabel = "100%",
                infoIcon = {
                    tooltipTitle = "Opacity Priority",
                    tooltipText = "With Target takes precedence, then In Combat, then Out of Combat. The highest priority condition that applies determines the opacity.",
                },
            })

            inner:AddSlider({
                label = "Opacity with Target",
                min = 1, max = 100, step = 1,
                get = function() return getSetting("opacityWithTarget") or 100 end,
                set = function(v)
                    setSetting("opacityWithTarget", v)
                    if addon.RefreshPRDOpacity then addon.RefreshPRDOpacity("prdPower") end
                end,
                minLabel = "1%", maxLabel = "100%",
            })

            inner:AddSlider({
                label = "Opacity Out of Combat",
                min = 1, max = 100, step = 1,
                get = function() return getSetting("opacityOutOfCombat") or 100 end,
                set = function(v)
                    setSetting("opacityOutOfCombat", v)
                    if addon.RefreshPRDOpacity then addon.RefreshPRDOpacity("prdPower") end
                end,
                minLabel = "1%", maxLabel = "100%",
            })

            inner:Finalize()
        end,
    })

    builder:Finalize()
end

addon.UI.SettingsPanel:RegisterRenderer("prdPowerBar", function(panel, scrollContent)
    PowerBar.Render(panel, scrollContent)
end)

return PowerBar
