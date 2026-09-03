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
    -- Edit Mode mirror push (personal_resource_display/editmode.lua): hideBar, barHeight
    local syncEditModeSetting = h.sync

    -- Maps the composite's field vocabulary onto this file's flat per-prefix
    -- keys (valueTextFont, percentTextFontSize, ...). Writes do not apply;
    -- the composite calls apply after each write.
    local function flatTextAccessors(map)
        local function get(field)
            local key = map[field]
            if not key then return nil end
            return getSetting(key)
        end
        local function set(field, value)
            local key = map[field]
            if key then h.set(key, value) end
        end
        return get, set
    end

    -- The apply half of h.setAndApplyComponent: defer the component's own
    -- ApplyStyling rather than the global styling pass.
    local function applyComponent()
        local comp = getComponent()
        if comp and comp.ApplyStyling then
            C_Timer.After(0, function()
                if comp and comp.ApplyStyling then comp:ApplyStyling() end
            end)
        end
    end
    ---------------------------------------------------------------------------
    -- Sizing Section
    ---------------------------------------------------------------------------
    ----------------------------------------------------------------------------
    -- Master Toggle: Hide Power Bar (mirrors Blizzard's Edit Mode setting)
    ----------------------------------------------------------------------------

    builder:AddToggle({
        label = "Hide Power Bar",
        description = "Removes the power bar from the Personal Resource Display; the other bars move up to fill the gap. This is Blizzard's Edit Mode setting, kept in sync both ways.",
        emphasized = true,
        get = function() return getSetting("hideBar") or false end,
        set = function(v)
            setSetting("hideBar", v)
            syncEditModeSetting("hideBar")
        end,
    })

    builder:AddCollapsibleSection({
        title = "Sizing",
        componentId = "prdPower",
        sectionKey = "sizing",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddSlider({
                label = "Bar Height",
                min = 10, max = 30, step = 1,
                get = function() return getSetting("barHeight") or 15 end,
                set = function(v) setSetting("barHeight", v) end,
                minLabel = "10", maxLabel = "30",
                debounceKey = "UI_prdPower_barHeight",
                debounceDelay = 0.2,
                onEditModeSync = function() syncEditModeSetting("barHeight") end,
                infoIcon = {
                    tooltipTitle = "Power Bar Height",
                    tooltipText = "Blizzard's Edit Mode setting, kept in sync both ways. Also sets the Alternate Power Bar height. Width follows General > Bar Width.",
                },
            })

            inner:Finalize()
        end,
    })

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
                colorValues = addon.Catalogs.ColorMode.DefaultCustom.values,
                colorOrder = addon.Catalogs.ColorMode.DefaultCustom.order,
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
                getHiddenEdges = function() return getSetting("borderHiddenEdges") end,
                setHiddenEdges = function(v) setSetting("borderHiddenEdges", v) end,
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
                            key = "valueTextShowToggle",
                            get = function() return getSetting("valueTextShow") or false end,
                            set = function(v) setSetting("valueTextShow", v) end,
                        })

                        -- Druid per-form visibility: button + flyout (Druids only)
                        Helpers.AddDruidFormsFlyout(tabInner, {
                            toggleKey = "valueTextShowToggle",
                            settingKey = "valueTextDruidForms",
                            getSetting = getSetting,
                            setSetting = setSetting,
                        })

                        -- PRD text is Scoot-drawn, so the paired Deep Shadow
                        -- styles are offered (outline-first order). dkPair
                        -- routes the mode through the colorMode/colorModeDK
                        -- pair for Death Knight spec coloring.
                        local get, set = flatTextAccessors({
                            fontFace = "valueTextFont",
                            style = "valueTextFontFlags",
                            size = "valueTextFontSize",
                            colorMode = "valueTextColorMode",
                            colorModeDK = "valueTextColorModeDK",
                            color = "valueTextColor",
                            alignment = "valueTextAlignment",
                        })
                        tabInner:AddTextStyleBlock({
                            get = get, set = set, apply = applyComponent,
                            defaults = { fontFace = "Friz Quadrata TT", size = 10 },
                            style = { order = Helpers.fontStyleOrderOutlineFirstPaired },
                            size = { min = 6, max = 36, minLabel = "6", maxLabel = "36" },
                            color = { values = textColorPowerValues, order = textColorPowerOrder,
                                dkPair = true },
                            alignment = { kind = "align", label = "Text Alignment",
                                default = "RIGHT", order = { "RIGHT", "LEFT", "CENTER" } },
                            offset = false,
                        })

                        tabInner:Finalize()
                    end,
                    percentText = function(cf, tabInner)
                        tabInner:AddToggle({
                            label = "Show % Text",
                            get = function() return getSetting("percentTextShow") or false end,
                            set = function(v) setSetting("percentTextShow", v) end,
                        })

                        local get, set = flatTextAccessors({
                            fontFace = "percentTextFont",
                            style = "percentTextFontFlags",
                            size = "percentTextFontSize",
                            colorMode = "percentTextColorMode",
                            colorModeDK = "percentTextColorModeDK",
                            color = "percentTextColor",
                            alignment = "percentTextAlignment",
                        })
                        tabInner:AddTextStyleBlock({
                            get = get, set = set, apply = applyComponent,
                            defaults = { fontFace = "Friz Quadrata TT", size = 10 },
                            style = { order = Helpers.fontStyleOrderOutlineFirstPaired },
                            size = { min = 6, max = 36, minLabel = "6", maxLabel = "36" },
                            color = { values = textColorPowerValues, order = textColorPowerOrder,
                                dkPair = true },
                            alignment = { kind = "align", label = "Text Alignment",
                                default = "LEFT", order = { "LEFT", "RIGHT", "CENTER" } },
                            offset = false,
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
                label = "Hide the Bar but not its Text",
                get = function() return getSetting("hideTextureOnly") or false end,
                set = function(v) setSetting("hideTextureOnly", v) end,
                infoIcon = {
                    tooltipTitle = "Hide the Bar but not its Text",
                    tooltipText = "Hides the bar texture and background, showing only the text overlay. Useful for a number-only display of your power resource.",
                },
            })

            inner:AddToggle({
                label = "Hide Bar Background",
                get = function() return getSetting("hideBarBackground") or false end,
                set = function(v) setSetting("hideBarBackground", v) end,
                infoIcon = {
                    tooltipTitle = "Hide Bar Background",
                    tooltipText = "Hides the Blizzard backdrop art behind the bar (the dark background and its frame edge added in patch 12.0.7), while keeping the bar fill visible. To add your own border instead, use the Border section.",
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
