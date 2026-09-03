-- AltPowerBarRenderer.lua - Personal Resource Display Alternate Power Bar settings renderer
--
-- The alternate power bar (12.0.7) exists for Devourer Demon Hunters (soul fragments),
-- Augmentation Evokers (Ebon Might), Brewmaster Monks (stagger), Shadow Priests and
-- Balance Druids (mana). Same PersonalResourceStatusBar template as the power bar,
-- value text only, height follows the Power Bar natively.
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.Settings = addon.UI.Settings or {}
addon.UI.Settings.PRD = addon.UI.Settings.PRD or {}
addon.UI.Settings.PRD.AltPowerBar = {}

local AltPowerBar = addon.UI.Settings.PRD.AltPowerBar
local SettingsBuilder = addon.UI.SettingsBuilder

local Helpers = addon.UI.Settings.Helpers

function AltPowerBar.Render(panel, scrollContent)
    panel:ClearContent()

    local builder = SettingsBuilder:CreateFor(scrollContent)
    panel._currentBuilder = builder

    builder:SetOnRefresh(function()
        AltPowerBar.Render(panel, scrollContent)
    end)

    local h = Helpers.CreateComponentHelpers("prdAltPower")
    local getSetting = h.get
    local setSetting = h.setAndApplyComponent
    -- Edit Mode mirror push (personal_resource_display/editmode.lua): hideBar
    local syncEditModeSetting = h.sync

    -- The apply half of h.setAndApplyComponent: defer the component's own
    -- ApplyStyling rather than the global styling pass.
    local function applyComponent()
        local comp = h.getComponent()
        if comp and comp.ApplyStyling then
            C_Timer.After(0, function()
                if comp and comp.ApplyStyling then comp:ApplyStyling() end
            end)
        end
    end

    ----------------------------------------------------------------------------
    -- Master Toggle: Hide Alternate Power Bar (mirrors Blizzard's Edit Mode setting)
    ----------------------------------------------------------------------------

    builder:AddToggle({
        label = "Hide Alternate Power Bar",
        description = "Only Devourer Demon Hunters, Augmentation Evokers, Brewmaster Monks, Shadow Priests and Balance Druids have an alternate power bar. Its height follows the Power Bar. This is Blizzard's Edit Mode setting, kept in sync both ways.",
        emphasized = true,
        get = function() return getSetting("hideBar") or false end,
        set = function(v)
            setSetting("hideBar", v)
            syncEditModeSetting("hideBar")
        end,
    })

    ----------------------------------------------------------------------------
    -- Style Section
    ----------------------------------------------------------------------------
    builder:AddCollapsibleSection({
        title = "Style",
        componentId = "prdAltPower",
        sectionKey = "style",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddDualBarStyleRow({
                label = "Foreground",
                getTexture = function() return getSetting("styleForegroundTexture") or "default" end,
                setTexture = function(v) setSetting("styleForegroundTexture", v) end,
                -- "Default" follows Blizzard's own colour for the resource (mana, Ebon
                -- Might, stagger thresholds, void metamorphosis).
                colorValues = addon.Catalogs.ColorMode.DefaultCustom.values,
                colorOrder = addon.Catalogs.ColorMode.DefaultCustom.order,
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

    ----------------------------------------------------------------------------
    -- Border Section
    ----------------------------------------------------------------------------
    builder:AddCollapsibleSection({
        title = "Border",
        componentId = "prdAltPower",
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

    ----------------------------------------------------------------------------
    -- Text Section (value only: the alternate power bar has no percent text)
    ----------------------------------------------------------------------------
    builder:AddCollapsibleSection({
        title = "Text",
        componentId = "prdAltPower",
        sectionKey = "text",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddTabbedSection({
                tabs = {
                    {
                        key = "valueText",
                        label = "Value Text",
                        infoIcon = {
                            tooltipTitle = "Value Text",
                            tooltipText = "Displays the alternate resource as a number on the bar (stagger amount, soul fragments, Ebon Might time, or mana).",
                        },
                    },
                },
                componentId = "prdAltPower",
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
                            alignment = { kind = "align", label = "Text Alignment",
                                default = "RIGHT", order = { "RIGHT", "LEFT", "CENTER" } },
                            offset = false,
                        })

                        tabInner:Finalize()
                    end,
                },
            })

            inner:Finalize()
        end,
    })

    ----------------------------------------------------------------------------
    -- Visibility Section
    ----------------------------------------------------------------------------
    builder:AddCollapsibleSection({
        title = "Visibility",
        componentId = "prdAltPower",
        sectionKey = "visibility",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddToggle({
                label = "Hide the Bar but not its Text",
                get = function() return getSetting("hideTextureOnly") or false end,
                set = function(v) setSetting("hideTextureOnly", v) end,
                infoIcon = {
                    tooltipTitle = "Hide the Bar but not its Text",
                    tooltipText = "Hides the bar texture and background, showing only the text overlay. Useful for a number-only display of your alternate resource.",
                },
            })

            inner:AddToggle({
                label = "Hide Bar Background",
                get = function() return getSetting("hideBarBackground") or false end,
                set = function(v) setSetting("hideBarBackground", v) end,
                infoIcon = {
                    tooltipTitle = "Hide Bar Background",
                    tooltipText = "Hides the Blizzard backdrop art behind the bar (the dark background and its frame edge), while keeping the bar fill visible. To add your own border instead, use the Border section.",
                },
            })

            inner:AddSpacer(12)

            inner:AddSlider({
                label = "Opacity in Combat",
                min = 1, max = 100, step = 1,
                get = function() return getSetting("opacityInCombat") or 100 end,
                set = function(v)
                    setSetting("opacityInCombat", v)
                    if addon.RefreshPRDOpacity then addon.RefreshPRDOpacity("prdAltPower") end
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
                    if addon.RefreshPRDOpacity then addon.RefreshPRDOpacity("prdAltPower") end
                end,
                minLabel = "1%", maxLabel = "100%",
            })

            inner:AddSlider({
                label = "Opacity Out of Combat",
                min = 1, max = 100, step = 1,
                get = function() return getSetting("opacityOutOfCombat") or 100 end,
                set = function(v)
                    setSetting("opacityOutOfCombat", v)
                    if addon.RefreshPRDOpacity then addon.RefreshPRDOpacity("prdAltPower") end
                end,
                minLabel = "1%", maxLabel = "100%",
            })

            inner:Finalize()
        end,
    })

    builder:Finalize()
end

--------------------------------------------------------------------------------
-- Self-register with settings panel
--------------------------------------------------------------------------------

addon.UI.SettingsPanel:RegisterRenderer("prdAltPowerBar", function(panel, scrollContent)
    AltPowerBar.Render(panel, scrollContent)
end)

return AltPowerBar
