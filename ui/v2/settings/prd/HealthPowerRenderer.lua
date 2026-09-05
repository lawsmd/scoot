-- HealthPowerRenderer.lua - Personal Resource Display Health Bar and Power Bar settings renderers
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.Settings = addon.UI.Settings or {}
addon.UI.Settings.PRD = addon.UI.Settings.PRD or {}

local SettingsBuilder = addon.UI.SettingsBuilder
local Helpers = addon.UI.Settings.Helpers

local BARS = {
    {
        key = "prdHealthBar",
        componentId = "prdHealth",
        title = "Health Bar",
        noun = "health",
        sections = { "sizing", "border", "style", "text", "visibility" },
        sizingTooltipExtra = "",
        styleForeground = { values = addon.Catalogs.ColorMode.Text.values, order = addon.Catalogs.ColorMode.Text.order, infoIcons = false },
        syncForegroundColorMode = true,
        textColor = { values = Helpers.textColorHealthValues, order = Helpers.textColorHealthOrder },
        textureOnlyNoun = "health",
        visibilityToggles = {
            { key = "hideHealthLossAnimation", label = "Hide Health Loss Animation",
              tooltipTitle = "Health Loss Animation",
              tooltipText = "The dark red bar that appears briefly when you take damage, showing the amount of health lost. Hide this to remove the damage flash effect." },
        },
    },
    {
        key = "prdPowerBar",
        componentId = "prdPower",
        title = "Power Bar",
        noun = "power",
        sections = { "sizing", "style", "border", "text", "visibility" },
        sizingTooltipExtra = "Also sets the Alternate Power Bar height. ",
        styleForeground = {
            values = { default = "Default", power = "Power Color", custom = "Custom" },
            order = { "default", "power", "custom" },
            infoIcons = false,
        },
        textColor = { values = Helpers.textColorPowerValues, order = Helpers.textColorPowerOrder, dkPair = true },
        hasDruidFormsFlyout = true,
        textureOnlyNoun = "power resource",
        visibilityToggles = {
            { key = "hideSpikeAnimations", label = "Hide Full Bar Animations",
              tooltipTitle = "Hide Full Bar Animations",
              tooltipText = "Hides the 'spike' animations that play when your power bar reaches full." },
            { key = "hidePowerFeedback", label = "Hide Power Feedback",
              tooltipTitle = "Hide Power Feedback",
              tooltipText = "Hides the visual feedback animation when power is gained or spent." },
            { key = "hideManaCostPrediction", label = "Hide Mana Cost Predictions",
              tooltipTitle = "Hide Mana Cost Predictions",
              tooltipText = "Hides the mana cost prediction bar that appears when casting spells. This blue overlay shows how much power will be consumed by the current cast." },
        },
    },
}

local function CreateRenderer(bar)
    local COMPONENT_ID = bar.componentId

    local function render(panel, scrollContent)
        panel:ClearContent()

        local builder = SettingsBuilder:CreateFor(scrollContent)
        panel._currentBuilder = builder

        builder:SetOnRefresh(function()
            render(panel, scrollContent)
        end)

        local h = Helpers.CreateComponentHelpers(COMPONENT_ID)
        local getComponent, getSetting = h.getComponent, h.get
        local setSetting = h.setAndApplyComponent
        -- Edit Mode mirror push (personal_resource_display/editmode.lua): hideBar,
        -- barHeight, and for the health bar styleForegroundColorMode (native ShowClassColor)
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

        -----------------------------------------------------------------------
        -- Master Toggle: Hide the bar (mirrors Blizzard's Edit Mode setting)
        -----------------------------------------------------------------------
        builder:AddToggle({
            label = "Hide " .. bar.title,
            description = "Removes the " .. bar.noun .. " bar from the Personal Resource Display; the other bars move up to fill the gap. This is Blizzard's Edit Mode setting, kept in sync both ways.",
            emphasized = true,
            get = function() return getSetting("hideBar") or false end,
            set = function(v)
                setSetting("hideBar", v)
                syncEditModeSetting("hideBar")
            end,
        })

        local sectionBuilders = {}

        -----------------------------------------------------------------------
        -- Sizing Section (native Edit Mode height; width is PRD-wide under General)
        -----------------------------------------------------------------------
        function sectionBuilders.sizing()
            builder:AddCollapsibleSection({
                title = "Sizing",
                componentId = COMPONENT_ID,
                sectionKey = "sizing",
                defaultExpanded = false,
                buildContent = function(contentFrame, inner)
                    inner:AddSlider({
                        label = "Bar Height",
                        min = 10, max = 30, step = 1,
                        get = function() return getSetting("barHeight") or 15 end,
                        set = function(v) setSetting("barHeight", v) end,
                        minLabel = "10", maxLabel = "30",
                        debounceKey = "UI_" .. COMPONENT_ID .. "_barHeight",
                        debounceDelay = 0.2,
                        onEditModeSync = function() syncEditModeSetting("barHeight") end,
                        infoIcon = {
                            tooltipTitle = bar.title .. " Height",
                            tooltipText = "Blizzard's Edit Mode setting, kept in sync both ways. " .. bar.sizingTooltipExtra .. "Width follows General > Bar Width.",
                        },
                    })

                    inner:Finalize()
                end,
            })
        end

        -----------------------------------------------------------------------
        -- Border Section
        -----------------------------------------------------------------------
        function sectionBuilders.border()
            builder:AddCollapsibleSection({
                title = "Border",
                componentId = COMPONENT_ID,
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
        end

        -----------------------------------------------------------------------
        -- Style Section
        -----------------------------------------------------------------------
        function sectionBuilders.style()
            builder:AddCollapsibleSection({
                title = "Style",
                componentId = COMPONENT_ID,
                sectionKey = "style",
                defaultExpanded = false,
                buildContent = function(contentFrame, inner)
                    local styleGet, styleSet = Helpers.CreateFlatAccessors(getSetting, h.set, {
                        texture = "styleForegroundTexture", colorMode = "styleForegroundColorMode", color = "styleForegroundTint",
                        bgTexture = "styleBackgroundTexture", bgColorMode = "styleBackgroundColorMode", bgColor = "styleBackgroundTint",
                        bgOpacity = "styleBackgroundOpacity",
                    })
                    local setForStyle = styleSet
                    if bar.syncForegroundColorMode then
                        -- "Class Color" is also pushed as Blizzard's Edit Mode "Show Class Color" for
                        -- this bar (two-way), so Edit Mode shows the same state.
                        setForStyle = function(field, value)
                            styleSet(field, value)
                            if field == "colorMode" then syncEditModeSetting("styleForegroundColorMode") end
                        end
                    end
                    inner:AddBarStyleBlock({
                        get = styleGet, set = setForStyle, apply = applyComponent,
                        foreground = bar.styleForeground,
                        background = { values = addon.Catalogs.ColorMode.DefaultCustom.values, order = addon.Catalogs.ColorMode.DefaultCustom.order },
                        opacity = { minLabel = "0%", maxLabel = "100%" },
                    })

                    inner:Finalize()
                end,
            })
        end

        -----------------------------------------------------------------------
        -- Text Section (Tabbed: Value Text / % Text)
        -----------------------------------------------------------------------
        function sectionBuilders.text()
            builder:AddCollapsibleSection({
                title = "Text",
                componentId = COMPONENT_ID,
                sectionKey = "text",
                defaultExpanded = false,
                buildContent = function(contentFrame, inner)
                    local textTabs = {
                        {
                            key = "valueText",
                            label = "Value Text",
                            infoIcon = {
                                tooltipTitle = "Value Text",
                                tooltipText = "Displays current " .. bar.noun .. " as a number on the PRD " .. bar.noun .. " bar.",
                            },
                        },
                        {
                            key = "percentText",
                            label = "% Text",
                            infoIcon = {
                                tooltipTitle = "Percentage Text",
                                tooltipText = "Displays current " .. bar.noun .. " as a percentage on the PRD " .. bar.noun .. " bar.",
                            },
                        },
                    }

                    inner:AddTabbedSection({
                        tabs = textTabs,
                        componentId = COMPONENT_ID,
                        sectionKey = "textTabs",
                        buildContent = {
                            valueText = function(cf, tabInner)
                                tabInner:AddToggle({
                                    label = "Show Value Text",
                                    key = bar.hasDruidFormsFlyout and "valueTextShowToggle" or nil,
                                    get = function() return getSetting("valueTextShow") or false end,
                                    set = function(v) setSetting("valueTextShow", v) end,
                                })

                                if bar.hasDruidFormsFlyout then
                                    -- Druid per-form visibility: button + flyout (Druids only)
                                    Helpers.AddDruidFormsFlyout(tabInner, {
                                        toggleKey = "valueTextShowToggle",
                                        settingKey = "valueTextDruidForms",
                                        getSetting = getSetting,
                                        setSetting = setSetting,
                                    })
                                end

                                -- PRD text is Scoot-drawn, so the paired Deep Shadow
                                -- styles are offered (outline-first order). dkPair
                                -- routes the mode through the colorMode/colorModeDK
                                -- pair for Death Knight spec coloring.
                                local map = {
                                    fontFace = "valueTextFont",
                                    style = "valueTextFontFlags",
                                    size = "valueTextFontSize",
                                    colorMode = "valueTextColorMode",
                                    color = "valueTextColor",
                                    alignment = "valueTextAlignment",
                                }
                                if bar.textColor.dkPair then map.colorModeDK = "valueTextColorModeDK" end
                                local get, set = Helpers.CreateFlatAccessors(getSetting, h.set, map)
                                tabInner:AddTextStyleBlock({
                                    get = get, set = set, apply = applyComponent,
                                    defaults = { fontFace = "Friz Quadrata TT", size = 10 },
                                    style = { order = Helpers.fontStyleOrderOutlineFirstPaired },
                                    size = { min = 6, max = 36, minLabel = "6", maxLabel = "36" },
                                    color = bar.textColor,
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

                                local map = {
                                    fontFace = "percentTextFont",
                                    style = "percentTextFontFlags",
                                    size = "percentTextFontSize",
                                    colorMode = "percentTextColorMode",
                                    color = "percentTextColor",
                                    alignment = "percentTextAlignment",
                                }
                                if bar.textColor.dkPair then map.colorModeDK = "percentTextColorModeDK" end
                                local get, set = Helpers.CreateFlatAccessors(getSetting, h.set, map)
                                tabInner:AddTextStyleBlock({
                                    get = get, set = set, apply = applyComponent,
                                    defaults = { fontFace = "Friz Quadrata TT", size = 10 },
                                    style = { order = Helpers.fontStyleOrderOutlineFirstPaired },
                                    size = { min = 6, max = 36, minLabel = "6", maxLabel = "36" },
                                    color = bar.textColor,
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
        end

        -----------------------------------------------------------------------
        -- Visibility Section
        -----------------------------------------------------------------------
        function sectionBuilders.visibility()
            builder:AddCollapsibleSection({
                title = "Visibility",
                componentId = COMPONENT_ID,
                sectionKey = "visibility",
                defaultExpanded = false,
                buildContent = function(contentFrame, inner)
                    inner:AddToggle({
                        label = "Hide the Bar but not its Text",
                        get = function() return getSetting("hideTextureOnly") or false end,
                        set = function(v) setSetting("hideTextureOnly", v) end,
                        infoIcon = {
                            tooltipTitle = "Hide the Bar but not its Text",
                            tooltipText = "Hides the bar texture and background, showing only the text overlay. Useful for a number-only display of your " .. bar.textureOnlyNoun .. ".",
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

                    for _, t in ipairs(bar.visibilityToggles) do
                        inner:AddToggle({
                            label = t.label,
                            get = function() return getSetting(t.key) or false end,
                            set = function(v) setSetting(t.key, v) end,
                            infoIcon = {
                                tooltipTitle = t.tooltipTitle,
                                tooltipText = t.tooltipText,
                            },
                        })
                    end

                    inner:AddSpacer(12)

                    local get, set = Helpers.CreateFlatAccessors(getSetting, setSetting, addon.Opacity.Keys.InCombat)
                    inner:AddStateOpacityBlock({
                        get = get, set = set,
                        apply = function()
                            if addon.RefreshPRDOpacity then addon.RefreshPRDOpacity(COMPONENT_ID) end
                        end,
                    })

                    inner:Finalize()
                end,
            })
        end

        for _, name in ipairs(bar.sections) do
            sectionBuilders[name]()
        end

        builder:Finalize()
    end

    return render
end

for _, bar in ipairs(BARS) do
    addon.UI.SettingsPanel:RegisterRenderer(bar.key, CreateRenderer(bar))
end
