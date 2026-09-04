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
            local styleGet, styleSet = Helpers.CreateFlatAccessors(getSetting, h.set, {
                texture = "styleForegroundTexture", colorMode = "styleForegroundColorMode", color = "styleForegroundTint",
                bgTexture = "styleBackgroundTexture", bgColorMode = "styleBackgroundColorMode", bgColor = "styleBackgroundTint",
                bgOpacity = "styleBackgroundOpacity",
            })
            inner:AddBarStyleBlock({
                get = styleGet, set = styleSet, apply = applyComponent,
                foreground = {
                    values = { default = "Default", power = "Power Color", custom = "Custom" },
                    order = { "default", "power", "custom" },
                    infoIcons = false,
                },
                background = { values = addon.Catalogs.ColorMode.DefaultCustom.values, order = addon.Catalogs.ColorMode.DefaultCustom.order },
                opacity = { minLabel = "0%", maxLabel = "100%" },
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
            local borderGet, borderSet = Helpers.CreateFlatAccessors(getSetting, h.set, {
                style = "borderStyle", hiddenEdges = "borderHiddenEdges",
                tintEnabled = "borderTintEnable", tintColor = "borderTintColor",
                thickness = "borderThickness",
            })
            inner:AddBarBorderBlock({
                get = borderGet, set = borderSet, apply = applyComponent,
                thickness = { clamp = false, minLabel = "1", maxLabel = "8" },
                inset = false,
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
                        local get, set = Helpers.CreateFlatAccessors(getSetting, h.set, {
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

                        local get, set = Helpers.CreateFlatAccessors(getSetting, h.set, {
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
