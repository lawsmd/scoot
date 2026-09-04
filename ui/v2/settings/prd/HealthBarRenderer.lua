-- HealthBarRenderer.lua - Personal Resource Display Health Bar settings renderer
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.Settings = addon.UI.Settings or {}
addon.UI.Settings.PRD = addon.UI.Settings.PRD or {}
addon.UI.Settings.PRD.HealthBar = {}

local HealthBar = addon.UI.Settings.PRD.HealthBar
local SettingsBuilder = addon.UI.SettingsBuilder

function HealthBar.Render(panel, scrollContent)
    panel:ClearContent()

    local builder = SettingsBuilder:CreateFor(scrollContent)
    panel._currentBuilder = builder

    builder:SetOnRefresh(function()
        HealthBar.Render(panel, scrollContent)
    end)

    local Helpers = addon.UI.Settings.Helpers
    local h = Helpers.CreateComponentHelpers("prdHealth")
    local getComponent, getSetting = h.getComponent, h.get
    local setSetting = h.setAndApplyComponent
    -- Edit Mode mirror push (personal_resource_display/editmode.lua):
    -- hideBar, barHeight, styleForegroundColorMode (native ShowClassColor)
    local syncEditModeSetting = h.sync
    local textColorValues, textColorOrder = Helpers.textColorHealthValues, Helpers.textColorHealthOrder

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
    -- Master Toggle: Hide Health Bar (mirrors Blizzard's Edit Mode setting)
    ---------------------------------------------------------------------------
    builder:AddToggle({
        label = "Hide Health Bar",
        description = "Removes the health bar from the Personal Resource Display; the other bars move up to fill the gap. This is Blizzard's Edit Mode setting, kept in sync both ways.",
        emphasized = true,
        get = function() return getSetting("hideBar") or false end,
        set = function(v)
            setSetting("hideBar", v)
            syncEditModeSetting("hideBar")
        end,
    })

    ---------------------------------------------------------------------------
    -- Sizing Section (native Edit Mode height; width is PRD-wide under General)
    ---------------------------------------------------------------------------
    builder:AddCollapsibleSection({
        title = "Sizing",
        componentId = "prdHealth",
        sectionKey = "sizing",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddSlider({
                label = "Bar Height",
                min = 10, max = 30, step = 1,
                get = function() return getSetting("barHeight") or 15 end,
                set = function(v) setSetting("barHeight", v) end,
                minLabel = "10", maxLabel = "30",
                debounceKey = "UI_prdHealth_barHeight",
                debounceDelay = 0.2,
                onEditModeSync = function() syncEditModeSetting("barHeight") end,
                infoIcon = {
                    tooltipTitle = "Health Bar Height",
                    tooltipText = "Blizzard's Edit Mode setting, kept in sync both ways. Width follows General > Bar Width.",
                },
            })

            inner:Finalize()
        end,
    })

    ---------------------------------------------------------------------------
    -- Border Section
    ---------------------------------------------------------------------------
    builder:AddCollapsibleSection({
        title = "Border",
        componentId = "prdHealth",
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
    -- Style Section
    ---------------------------------------------------------------------------
    builder:AddCollapsibleSection({
        title = "Style",
        componentId = "prdHealth",
        sectionKey = "style",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            local styleGet, styleSet = Helpers.CreateFlatAccessors(getSetting, h.set, {
                texture = "styleForegroundTexture", colorMode = "styleForegroundColorMode", color = "styleForegroundTint",
                bgTexture = "styleBackgroundTexture", bgColorMode = "styleBackgroundColorMode", bgColor = "styleBackgroundTint",
                bgOpacity = "styleBackgroundOpacity",
            })
            -- "Class Color" is also pushed as Blizzard's Edit Mode "Show Class Color" for
            -- this bar (two-way), so Edit Mode shows the same state.
            local function styleSetSync(field, value)
                styleSet(field, value)
                if field == "colorMode" then syncEditModeSetting("styleForegroundColorMode") end
            end
            inner:AddBarStyleBlock({
                get = styleGet, set = styleSetSync, apply = applyComponent,
                foreground = { values = addon.Catalogs.ColorMode.Text.values, order = addon.Catalogs.ColorMode.Text.order, infoIcons = false },
                background = { values = addon.Catalogs.ColorMode.DefaultCustom.values, order = addon.Catalogs.ColorMode.DefaultCustom.order },
                opacity = { minLabel = "0%", maxLabel = "100%" },
            })

            inner:Finalize()
        end,
    })

    ---------------------------------------------------------------------------
    -- Text Section (Tabbed: Value Text / % Text)
    ---------------------------------------------------------------------------
    builder:AddCollapsibleSection({
        title = "Text",
        componentId = "prdHealth",
        sectionKey = "text",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            local textTabs = {
                {
                    key = "valueText",
                    label = "Value Text",
                    infoIcon = {
                        tooltipTitle = "Value Text",
                        tooltipText = "Displays current health as a number on the PRD health bar.",
                    },
                },
                {
                    key = "percentText",
                    label = "% Text",
                    infoIcon = {
                        tooltipTitle = "Percentage Text",
                        tooltipText = "Displays current health as a percentage on the PRD health bar.",
                    },
                },
            }

            inner:AddTabbedSection({
                tabs = textTabs,
                componentId = "prdHealth",
                sectionKey = "textTabs",
                buildContent = {
                    valueText = function(cf, tabInner)
                        tabInner:AddToggle({
                            label = "Show Value Text",
                            get = function() return getSetting("valueTextShow") or false end,
                            set = function(v) setSetting("valueTextShow", v) end,
                        })

                        -- PRD text is Scoot-drawn, so the paired Deep Shadow
                        -- styles are offered (outline-first order).
                        local get, set = Helpers.CreateFlatAccessors(getSetting, h.set, {
                            fontFace = "valueTextFont",
                            style = "valueTextFontFlags",
                            size = "valueTextFontSize",
                            colorMode = "valueTextColorMode",
                            color = "valueTextColor",
                            alignment = "valueTextAlignment",
                        })
                        tabInner:AddTextStyleBlock({
                            get = get, set = set, apply = applyComponent,
                            defaults = { fontFace = "Friz Quadrata TT", size = 10 },
                            style = { order = Helpers.fontStyleOrderOutlineFirstPaired },
                            size = { min = 6, max = 36, minLabel = "6", maxLabel = "36" },
                            color = { values = textColorValues, order = textColorOrder },
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
                            color = "percentTextColor",
                            alignment = "percentTextAlignment",
                        })
                        tabInner:AddTextStyleBlock({
                            get = get, set = set, apply = applyComponent,
                            defaults = { fontFace = "Friz Quadrata TT", size = 10 },
                            style = { order = Helpers.fontStyleOrderOutlineFirstPaired },
                            size = { min = 6, max = 36, minLabel = "6", maxLabel = "36" },
                            color = { values = textColorValues, order = textColorOrder },
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
        componentId = "prdHealth",
        sectionKey = "visibility",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddToggle({
                label = "Hide the Bar but not its Text",
                get = function() return getSetting("hideTextureOnly") or false end,
                set = function(v) setSetting("hideTextureOnly", v) end,
                infoIcon = {
                    tooltipTitle = "Hide the Bar but not its Text",
                    tooltipText = "Hides the bar texture and background, showing only the text overlay. Useful for a number-only display of your health.",
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
                label = "Hide Health Loss Animation",
                get = function() return getSetting("hideHealthLossAnimation") or false end,
                set = function(v) setSetting("hideHealthLossAnimation", v) end,
                infoIcon = {
                    tooltipTitle = "Health Loss Animation",
                    tooltipText = "The dark red bar that appears briefly when you take damage, showing the amount of health lost. Hide this to remove the damage flash effect.",
                },
            })

            inner:AddSpacer(12)

            local get, set = Helpers.CreateFlatAccessors(getSetting, setSetting, addon.Opacity.Keys.InCombat)
            inner:AddStateOpacityBlock({
                get = get, set = set,
                apply = function()
                    if addon.RefreshPRDOpacity then addon.RefreshPRDOpacity("prdHealth") end
                end,
            })

            inner:Finalize()
        end,
    })

    builder:Finalize()
end

addon.UI.SettingsPanel:RegisterRenderer("prdHealthBar", function(panel, scrollContent)
    HealthBar.Render(panel, scrollContent)
end)

return HealthBar
