-- TrackedBarsRenderer.lua - Tracked Bars settings renderer
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.Settings = addon.UI.Settings or {}
addon.UI.Settings.CDM = addon.UI.Settings.CDM or {}
addon.UI.Settings.CDM.TrackedBars = {}

local TrackedBars = addon.UI.Settings.CDM.TrackedBars
local SettingsBuilder = addon.UI.SettingsBuilder

function TrackedBars.Render(panel, scrollContent)
    panel:ClearContent()

    local builder = SettingsBuilder:CreateFor(scrollContent)
    panel._currentBuilder = builder

    builder:SetOnRefresh(function()
        TrackedBars.Render(panel, scrollContent)
    end)

    local Helpers = addon.UI.Settings.Helpers
    local h = Helpers.CreateComponentHelpers("trackedBars")
    local getComponent, getSetting = h.getComponent, h.get
    local setSetting = h.setAndApply
    local syncEditModeSetting = h.sync
    local textColorValues, textColorOrder = Helpers.textColorValues, Helpers.textColorOrder

    local function getIconBorderOptions()
        return Helpers.getIconBorderOptions({{"none","None"}})
    end

    ---------------------------------------------------------------------------
    -- Mode Selector (parent level, emphasized)
    ---------------------------------------------------------------------------
    builder:AddSelector({
        label = "Mode",
        description = "Choose how tracked bars are displayed.",
        values = { default = "Default", vertical = "Vertical Bars" },
        order = { "default", "vertical" },
        emphasized = true,
        get = function() return getSetting("barMode") or "default" end,
        set = function(v) setSetting("barMode", v) end,
    })

    ---------------------------------------------------------------------------
    -- Positioning Section
    ---------------------------------------------------------------------------
    builder:AddCollapsibleSection({
        title = "Positioning",
        componentId = "trackedBars",
        sectionKey = "positioning",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddSlider({
                label = "Icon Padding", min = 2, max = 10, step = 1,
                get = function() return getSetting("iconPadding") or 3 end,
                set = function(v) setSetting("iconPadding", v) end,
                debounceKey = "trackedBars_iconPadding",
                debounceDelay = 0.3,
                onEditModeSync = function() syncEditModeSetting("iconPadding") end,
                minLabel = "2", maxLabel = "10",
            })

            inner:AddSlider({
                label = "Icon/Bar Padding", min = -20, max = 80, step = 1,
                get = function() return getSetting("iconBarPadding") or 0 end,
                set = function(v) setSetting("iconBarPadding", v) end,
                minLabel = "-20", maxLabel = "80",
            })

            inner:Finalize()
        end,
    })

    ---------------------------------------------------------------------------
    -- Sizing Section
    ---------------------------------------------------------------------------
    builder:AddCollapsibleSection({
        title = "Sizing",
        componentId = "trackedBars",
        sectionKey = "sizing",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddSlider({
                label = "Bar Scale", min = 50, max = 200, step = 10,
                get = function() return getSetting("iconSize") or 100 end,
                set = function(v) setSetting("iconSize", v) end,
                debounceKey = "trackedBars_iconSize",
                debounceDelay = 0.3,
                onEditModeSync = function() syncEditModeSetting("iconSize") end,
                minLabel = "50%", maxLabel = "200%",
            })

            inner:AddSlider({
                label = "Bar Width", min = 50, max = 200, step = 1,
                get = function() return getSetting("barWidth") or 100 end,
                set = function(v) setSetting("barWidth", v) end,
                debounceKey = "trackedBars_barWidth",
                debounceDelay = 0.3,
                onEditModeSync = function() syncEditModeSetting("barWidth") end,
                minLabel = "50%", maxLabel = "200%",
            })

            inner:Finalize()
        end,
    })

    ---------------------------------------------------------------------------
    -- Style Section
    ---------------------------------------------------------------------------
    builder:AddCollapsibleSection({
        title = "Style",
        componentId = "trackedBars",
        sectionKey = "style",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddToggle({
                label = "Enable Custom Textures",
                get = function() return getSetting("styleEnableCustom") ~= false end,
                set = function(v) setSetting("styleEnableCustom", v) end,
            })

            inner:AddBarTextureSelector({
                label = "Foreground Texture",
                get = function() return getSetting("styleForegroundTexture") or "bevelled" end,
                set = function(v) setSetting("styleForegroundTexture", v) end,
            })

            inner:AddSelectorColorPicker({
                label = "Foreground Color",
                values = {
                    default = "Default",
                    class = "Class Color",
                    custom = "Custom",
                },
                order = { "default", "class", "custom" },
                get = function() return getSetting("styleForegroundColorMode") or "default" end,
                set = function(v) setSetting("styleForegroundColorMode", v) end,
                getColor = function()
                    local c = getSetting("styleForegroundTint") or {1, 1, 1, 1}
                    return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
                end,
                setColor = function(r, g, b, a)
                    setSetting("styleForegroundTint", {r, g, b, a})
                end,
                customValue = "custom",
                hasAlpha = true,
            })

            inner:AddBarTextureSelector({
                label = "Background Texture",
                get = function() return getSetting("styleBackgroundTexture") or "bevelled" end,
                set = function(v) setSetting("styleBackgroundTexture", v) end,
            })

            inner:AddSelectorColorPicker({
                label = "Background Color",
                values = {
                    default = "Default",
                    class = "Class Color",
                    custom = "Custom",
                },
                order = { "default", "class", "custom" },
                get = function() return getSetting("styleBackgroundColorMode") or "default" end,
                set = function(v) setSetting("styleBackgroundColorMode", v) end,
                getColor = function()
                    local c = getSetting("styleBackgroundTint") or {0, 0, 0, 1}
                    return c[1] or 0, c[2] or 0, c[3] or 0, c[4] or 1
                end,
                setColor = function(r, g, b, a)
                    setSetting("styleBackgroundTint", {r, g, b, a})
                end,
                customValue = "custom",
                hasAlpha = true,
            })

            inner:AddSlider({
                label = "Background Opacity", min = 0, max = 100, step = 1,
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
        componentId = "trackedBars",
        sectionKey = "border",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddToggle({
                label = "Use Custom Border",
                get = function() return getSetting("borderEnable") or false end,
                set = function(v) setSetting("borderEnable", v) end,
            })

            inner:AddToggleColorPicker({
                label = "Border Tint",
                get = function() return getSetting("borderTintEnable") or false end,
                set = function(v) setSetting("borderTintEnable", v) end,
                getColor = function()
                    local c = getSetting("borderTintColor")
                    return c and c[1] or 1, c and c[2] or 1, c and c[3] or 1, c and c[4] or 1
                end,
                setColor = function(r, g, b, a) setSetting("borderTintColor", {r, g, b, a}) end,
            })

            inner:AddBarBorderSelector({
                label = "Border Style",
                includeNone = false,
                get = function() return getSetting("borderStyle") or "square" end,
                set = function(v) setSetting("borderStyle", v) end,
            })

            inner:AddSlider({
                label = "Border Thickness", min = 1, max = 8, step = 0.5,
                precision = 1,
                get = function() local v = getSetting("borderThickness") or 1; return math.max(1, math.min(8, math.floor(v * 2 + 0.5) / 2)) end,
                set = function(v) setSetting("borderThickness", math.max(1, math.min(8, math.floor((tonumber(v) or 1) * 2 + 0.5) / 2))) end,
                minLabel = "1", maxLabel = "8",
            })

            inner:AddDualSlider({
                label = "Border Inset",
                sliderA = {
                    axisLabel = "H", min = -4, max = 4, step = 1,
                    get = function() return getSetting("borderInsetH") or getSetting("borderInset") or 0 end,
                    set = function(v) setSetting("borderInsetH", v) end,
                    minLabel = "-4", maxLabel = "+4",
                },
                sliderB = {
                    axisLabel = "V", min = -4, max = 4, step = 1,
                    get = function() return getSetting("borderInsetV") or getSetting("borderInset") or 0 end,
                    set = function(v) setSetting("borderInsetV", v) end,
                    minLabel = "-4", maxLabel = "+4",
                },
            })

            inner:Finalize()
        end,
    })

    ---------------------------------------------------------------------------
    -- Text Section (contains tabbed sub-sections for Spell Name and Timer)
    ---------------------------------------------------------------------------
    builder:AddCollapsibleSection({
        title = "Text",
        componentId = "trackedBars",
        sectionKey = "text",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            -- Helper to apply text styling
            local function applyText()
                if addon and addon.ApplyStyles then
                    C_Timer.After(0, function() addon:ApplyStyles() end)
                end
            end

            local fontStyleValues = Helpers.fontStyleValues
            local fontStyleOrder = Helpers.fontStyleOrder

            -- Tabbed section for Spell Name and Timer text settings
            inner:AddTabbedSection({
                tabs = {
                    { key = "spellName", label = "Spell Name" },
                    { key = "timer", label = "Timer" },
                },
                componentId = "trackedBars",
                sectionKey = "textTabs",
                buildContent = {
                    spellName = function(tabContent, tabBuilder)
                        -- Helper to get/set textName sub-properties
                        local function getNameSetting(key, default)
                            local tn = getSetting("textName")
                            if tn and tn[key] ~= nil then return tn[key] end
                            return default
                        end
                        local function setNameSetting(key, value)
                            local comp = getComponent()
                            if comp and comp.db then
                                comp.db.textName = comp.db.textName or {}
                                comp.db.textName[key] = value
                            end
                            applyText()
                        end

                        -- Font selector
                        tabBuilder:AddFontSelector({
                            label = "Font",
                            description = "The font used for spell name text.",
                            get = function() return getNameSetting("fontFace", "FRIZQT__") end,
                            set = function(v) setNameSetting("fontFace", v) end,
                        })

                        -- Font Size slider
                        tabBuilder:AddSlider({
                            label = "Font Size",
                            min = 6,
                            max = 32,
                            step = 1,
                            get = function() return getNameSetting("size", 14) end,
                            set = function(v) setNameSetting("size", v) end,
                            minLabel = "6",
                            maxLabel = "32",
                        })

                        -- Font Style selector
                        tabBuilder:AddSelector({
                            label = "Font Style",
                            values = fontStyleValues,
                            order = fontStyleOrder,
                            get = function() return getNameSetting("style", "OUTLINE") end,
                            set = function(v) setNameSetting("style", v) end,
                        })

                        -- Font Color picker
                        tabBuilder:AddSelectorColorPicker({
                            label = "Font Color",
                            values = textColorValues,
                            order = textColorOrder,
                            get = function() return getNameSetting("colorMode", "default") end,
                            set = function(v) setNameSetting("colorMode", v or "default") end,
                            getColor = function()
                                local c = getNameSetting("color", {1,1,1,1})
                                return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
                            end,
                            setColor = function(r, g, b, a)
                                setNameSetting("color", {r, g, b, a})
                            end,
                            customValue = "custom",
                            hasAlpha = true,
                        })

                        -- Offset X/Y dual slider
                        tabBuilder:AddDualSlider({
                            label = "Offset",
                            sliderA = {
                                axisLabel = "X",
                                min = -100,
                                max = 100,
                                step = 1,
                                get = function()
                                    local offset = getNameSetting("offset", {x=0, y=0})
                                    return offset.x or 0
                                end,
                                set = function(v)
                                    local comp = getComponent()
                                    if comp and comp.db then
                                        comp.db.textName = comp.db.textName or {}
                                        comp.db.textName.offset = comp.db.textName.offset or {}
                                        comp.db.textName.offset.x = v
                                    end
                                    applyText()
                                end,
                            },
                            sliderB = {
                                axisLabel = "Y",
                                min = -100,
                                max = 100,
                                step = 1,
                                get = function()
                                    local offset = getNameSetting("offset", {x=0, y=0})
                                    return offset.y or 0
                                end,
                                set = function(v)
                                    local comp = getComponent()
                                    if comp and comp.db then
                                        comp.db.textName = comp.db.textName or {}
                                        comp.db.textName.offset = comp.db.textName.offset or {}
                                        comp.db.textName.offset.y = v
                                    end
                                    applyText()
                                end,
                            },
                        })

                        tabBuilder:Finalize()
                    end,
                    timer = function(tabContent, tabBuilder)
                        -- Helper to get/set textDuration sub-properties
                        local function getDurationSetting(key, default)
                            local td = getSetting("textDuration")
                            if td and td[key] ~= nil then return td[key] end
                            return default
                        end
                        local function setDurationSetting(key, value)
                            local comp = getComponent()
                            if comp and comp.db then
                                comp.db.textDuration = comp.db.textDuration or {}
                                comp.db.textDuration[key] = value
                            end
                            applyText()
                        end

                        -- Font selector
                        tabBuilder:AddFontSelector({
                            label = "Font",
                            description = "The font used for timer/duration text.",
                            get = function() return getDurationSetting("fontFace", "FRIZQT__") end,
                            set = function(v) setDurationSetting("fontFace", v) end,
                        })

                        -- Font Size slider
                        tabBuilder:AddSlider({
                            label = "Font Size",
                            min = 6,
                            max = 32,
                            step = 1,
                            get = function() return getDurationSetting("size", 14) end,
                            set = function(v) setDurationSetting("size", v) end,
                            minLabel = "6",
                            maxLabel = "32",
                        })

                        -- Font Style selector
                        tabBuilder:AddSelector({
                            label = "Font Style",
                            values = fontStyleValues,
                            order = fontStyleOrder,
                            get = function() return getDurationSetting("style", "OUTLINE") end,
                            set = function(v) setDurationSetting("style", v) end,
                        })

                        -- Font Color picker
                        tabBuilder:AddSelectorColorPicker({
                            label = "Font Color",
                            values = textColorValues,
                            order = textColorOrder,
                            get = function() return getDurationSetting("colorMode", "default") end,
                            set = function(v) setDurationSetting("colorMode", v or "default") end,
                            getColor = function()
                                local c = getDurationSetting("color", {1,1,1,1})
                                return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
                            end,
                            setColor = function(r, g, b, a)
                                setDurationSetting("color", {r, g, b, a})
                            end,
                            customValue = "custom",
                            hasAlpha = true,
                        })

                        -- Offset X/Y dual slider
                        tabBuilder:AddDualSlider({
                            label = "Offset",
                            sliderA = {
                                axisLabel = "X",
                                min = -100,
                                max = 100,
                                step = 1,
                                get = function()
                                    local offset = getDurationSetting("offset", {x=0, y=0})
                                    return offset.x or 0
                                end,
                                set = function(v)
                                    local comp = getComponent()
                                    if comp and comp.db then
                                        comp.db.textDuration = comp.db.textDuration or {}
                                        comp.db.textDuration.offset = comp.db.textDuration.offset or {}
                                        comp.db.textDuration.offset.x = v
                                    end
                                    applyText()
                                end,
                            },
                            sliderB = {
                                axisLabel = "Y",
                                min = -100,
                                max = 100,
                                step = 1,
                                get = function()
                                    local offset = getDurationSetting("offset", {x=0, y=0})
                                    return offset.y or 0
                                end,
                                set = function(v)
                                    local comp = getComponent()
                                    if comp and comp.db then
                                        comp.db.textDuration = comp.db.textDuration or {}
                                        comp.db.textDuration.offset = comp.db.textDuration.offset or {}
                                        comp.db.textDuration.offset.y = v
                                    end
                                    applyText()
                                end,
                            },
                        })

                        tabBuilder:Finalize()
                    end,
                },
            })

            inner:Finalize()
        end,
    })

    ---------------------------------------------------------------------------
    -- Icon Section
    ---------------------------------------------------------------------------
    builder:AddCollapsibleSection({
        title = "Icon",
        componentId = "trackedBars",
        sectionKey = "icon",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddSlider({
                label = "Icon Shape",
                description = "Adjust icon aspect ratio. Center = square icons.",
                min = -67, max = 67, step = 1,
                get = function() return getSetting("iconTallWideRatio") or 0 end,
                set = function(v) setSetting("iconTallWideRatio", v) end,
                minLabel = "Wide", maxLabel = "Tall",
            })

            inner:AddToggleColorPicker({
                label = "Border Tint",
                get = function() return getSetting("iconBorderTintEnable") or false end,
                set = function(v) setSetting("iconBorderTintEnable", v) end,
                getColor = function()
                    local c = getSetting("iconBorderTintColor")
                    return c and c[1] or 1, c and c[2] or 1, c and c[3] or 1, c and c[4] or 1
                end,
                setColor = function(r, g, b, a) setSetting("iconBorderTintColor", {r, g, b, a}) end,
            })

            local iconBorderValues, iconBorderOrder = getIconBorderOptions()
            inner:AddSelector({
                label = "Border Style",
                values = iconBorderValues,
                order = iconBorderOrder,
                get = function()
                    if not getSetting("iconBorderEnable") then return "none" end
                    return getSetting("iconBorderStyle") or "square"
                end,
                set = function(v)
                    if v == "none" then
                        setSetting("iconBorderEnable", false)
                        setSetting("iconBorderStyle", "none")
                    else
                        setSetting("iconBorderEnable", true)
                        setSetting("iconBorderStyle", v)
                    end
                end,
            })

            inner:AddSlider({
                label = "Border Thickness", min = 1, max = 8, step = 0.5,
                precision = 1,
                get = function() local v = getSetting("iconBorderThickness") or 1; return math.max(1, math.min(8, math.floor(v * 2 + 0.5) / 2)) end,
                set = function(v) setSetting("iconBorderThickness", math.max(1, math.min(8, math.floor((tonumber(v) or 1) * 2 + 0.5) / 2))) end,
                minLabel = "1", maxLabel = "8",
            })

            inner:AddDualSlider({
                label = "Border Inset",
                sliderA = {
                    axisLabel = "H", min = -4, max = 4, step = 1,
                    get = function() return getSetting("iconBorderInsetH") or getSetting("iconBorderInset") or 0 end,
                    set = function(v) setSetting("iconBorderInsetH", v) end,
                    minLabel = "-4", maxLabel = "+4",
                },
                sliderB = {
                    axisLabel = "V", min = -4, max = 4, step = 1,
                    get = function() return getSetting("iconBorderInsetV") or getSetting("iconBorderInset") or 0 end,
                    set = function(v) setSetting("iconBorderInsetV", v) end,
                    minLabel = "-4", maxLabel = "+4",
                },
            })

            inner:Finalize()
        end,
    })

    ---------------------------------------------------------------------------
    -- Misc Section
    ---------------------------------------------------------------------------
    builder:AddCollapsibleSection({
        title = "Visibility & Misc",
        componentId = "trackedBars",
        sectionKey = "misc",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            -- Priority system header + explainer
            inner:AddDescription("Priority System", { color = {1, 0.82, 0}, fontSize = 14, topPadding = 4 })
            inner:AddDescription("With Target > In Combat > Out of Combat. Only the highest active condition applies.", { color = {1, 0.82, 0}, topPadding = -8, bottomPadding = -4 })

            inner:AddSlider({
                label = "Opacity With Target", min = 0, max = 100, step = 1,
                get = function() return getSetting("opacityWithTarget") or 100 end,
                set = function(v)
                    setSetting("opacityWithTarget", v)
                    if addon and addon.RefreshCDMViewerOpacity then addon.RefreshCDMViewerOpacity("trackedBars") end
                end,
                minLabel = "Hidden", maxLabel = "100%",
            })

            inner:AddSlider({
                label = "Opacity in Combat", min = 50, max = 100, step = 1,
                get = function() return getSetting("opacity") or 100 end,
                set = function(v)
                    setSetting("opacity", v)
                    if addon and addon.RefreshCDMViewerOpacity then addon.RefreshCDMViewerOpacity("trackedBars") end
                end,
                debounceKey = "trackedBars_opacity",
                debounceDelay = 0.3,
                onEditModeSync = function() syncEditModeSetting("opacity") end,
                minLabel = "50%", maxLabel = "100%",
            })

            inner:AddSlider({
                label = "Opacity Out of Combat", min = 0, max = 100, step = 1,
                get = function() return getSetting("opacityOutOfCombat") or 100 end,
                set = function(v)
                    setSetting("opacityOutOfCombat", v)
                    if addon and addon.RefreshCDMViewerOpacity then addon.RefreshCDMViewerOpacity("trackedBars") end
                end,
                minLabel = "Hidden", maxLabel = "100%",
            })

            inner:AddSelector({
                label = "Display Mode",
                values = {
                    both = "Icon & Name",
                    icon = "Icon Only",
                    name = "Name Only",
                },
                order = { "both", "icon", "name" },
                get = function() return getSetting("displayMode") or "both" end,
                set = function(v)
                    setSetting("displayMode", v)
                    syncEditModeSetting("displayMode")
                end,
                syncCooldown = 0.5,
            })

            inner:AddToggle({
                label = "Hide When Inactive",
                get = function() return getSetting("hideWhenInactive") or false end,
                set = function(v)
                    setSetting("hideWhenInactive", v)
                    syncEditModeSetting("hideWhenInactive")
                end,
            })

            inner:AddToggle({
                label = "Show Timer",
                get = function() return getSetting("showTimer") ~= false end,
                set = function(v)
                    setSetting("showTimer", v)
                    syncEditModeSetting("showTimer")
                end,
            })

            inner:AddToggle({
                label = "Show Tooltips",
                get = function() return getSetting("showTooltip") ~= false end,
                set = function(v)
                    setSetting("showTooltip", v)
                    syncEditModeSetting("showTooltip")
                end,
            })

            inner:Finalize()
        end,
    })

    builder:Finalize()
end

addon.UI.SettingsPanel:RegisterRenderer("trackedBars", function(panel, scrollContent)
    TrackedBars.Render(panel, scrollContent)
end)

return TrackedBars
