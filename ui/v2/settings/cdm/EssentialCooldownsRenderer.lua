-- EssentialCooldownsRenderer.lua - Essential Cooldowns settings renderer
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.Settings = addon.UI.Settings or {}
addon.UI.Settings.CDM = addon.UI.Settings.CDM or {}
addon.UI.Settings.CDM.EssentialCooldowns = {}

local EssentialCooldowns = addon.UI.Settings.CDM.EssentialCooldowns
local SettingsBuilder = addon.UI.SettingsBuilder

function EssentialCooldowns.Render(panel, scrollContent)
    -- Clear any existing content
    panel:ClearContent()

    -- Create builder for this content area
    local builder = SettingsBuilder:CreateFor(scrollContent)
    panel._currentBuilder = builder

    -- Store reference to this function for re-rendering on expand/collapse
    builder:SetOnRefresh(function()
        EssentialCooldowns.Render(panel, scrollContent)
    end)

    local Helpers = addon.UI.Settings.Helpers
    local h = Helpers.CreateComponentHelpers("essentialCooldowns")
    local getComponent, getSetting, setSetting = h.getComponent, h.get, h.set
    local syncEditModeSetting = h.sync
    local textColorValues, textColorOrder = Helpers.textColorValues, Helpers.textColorOrder

    -- Collapsible section: Positioning
    builder:AddCollapsibleSection({
        title = "Positioning",
        componentId = "essentialCooldowns",
        sectionKey = "positioning",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            -- Use centralized setting patterns for orientation-dependent settings
            local OrientationPatterns = addon.UI.SettingPatterns.Orientation

            -- Get current orientation for initial values
            local currentOrientation = getSetting("orientation") or "H"
            local initialDirValues, initialDirOrder = OrientationPatterns.getDirectionOptions(currentOrientation)

            -- Center Anchor toggle - changes how the first row expands
            inner:AddToggle({
                key = "centerAnchor",
                label = "Center Icons on Edit Mode Anchor",
                description = "Centers icons on the anchor point. Useful when sharing profiles across characters with different cooldown counts.",
                get = function() return getSetting("centerAnchor") or false end,
                set = function(v)
                    setSetting("centerAnchor", v)
                    if addon.RefreshCDMCenterAnchor then
                        addon.RefreshCDMCenterAnchor("essentialCooldowns")
                    end
                end,
            })

            -- Center Additional Rows toggle - changes how overflow rows are positioned
            inner:AddToggle({
                key = "centerAdditionalRows",
                label = "Center Additional Rows",
                description = "Centers overflow rows under the first row for a balanced appearance.",
                get = function() return getSetting("centerAdditionalRows") or false end,
                set = function(v)
                    setSetting("centerAdditionalRows", v)
                    if addon.RefreshCDMCenterAnchor then
                        addon.RefreshCDMCenterAnchor("essentialCooldowns")
                    end
                end,
            })

            inner:AddSelector({
                key = "orientation",
                label = "Orientation",
                description = "Horizontal arranges icons left-to-right, Vertical arranges top-to-bottom.",
                values = { H = "Horizontal", V = "Vertical" },
                order = { "H", "V" },
                get = function() return getSetting("orientation") or "H" end,
                set = function(v)
                    setSetting("orientation", v)
                    syncEditModeSetting("orientation")

                    -- Dynamically update dependent controls
                    local dirSelector = inner:GetControl("iconDirection")
                    if dirSelector then
                        local newValues, newOrder = OrientationPatterns.getDirectionOptions(v)
                        dirSelector:SetOptions(newValues, newOrder)
                    end

                    local columnsSlider = inner:GetControl("columnsRows")
                    if columnsSlider then
                        columnsSlider:SetLabel(OrientationPatterns.getColumnsLabel(v))
                    end

                    -- Update centering for new orientation if either feature is enabled
                    if (getSetting("centerAnchor") or getSetting("centerAdditionalRows")) and addon.RefreshCDMCenterAnchor then
                        addon.RefreshCDMCenterAnchor("essentialCooldowns")
                    end
                end,
                -- Prevent rapid changes during Edit Mode sync (orientation changes trigger
                -- expensive Apply operations; allow 400ms for sync to complete)
                syncCooldown = 0.4,
            })

            inner:AddSlider({
                key = "columnsRows",
                label = OrientationPatterns.getColumnsLabel(currentOrientation),
                description = OrientationPatterns.getColumnsDescription(currentOrientation),
                min = 1,
                max = 20,
                step = 1,
                get = function() return getSetting("columns") or 12 end,
                set = function(v) setSetting("columns", v) end,
                minLabel = "1",
                maxLabel = "20",
                -- Debounced Edit Mode sync for slider performance
                debounceKey = "UI_essentialCooldowns_columns",
                debounceDelay = 0.2,
                onEditModeSync = function(newValue)
                    syncEditModeSetting("columns")
                end,
            })

            inner:AddSelector({
                key = "iconDirection",
                label = "Icon Direction",
                description = "Direction icons grow from the anchor point.",
                values = initialDirValues,
                order = initialDirOrder,
                get = function() return getSetting("direction") or "right" end,
                set = function(v)
                    setSetting("direction", v)
                    syncEditModeSetting("direction")
                end,
                -- Prevent rapid changes during Edit Mode sync
                syncCooldown = 0.4,
            })

            inner:AddSlider({
                label = "Icon Padding",
                description = "Space between cooldown icons in pixels.",
                min = 2,
                max = 14,
                step = 1,
                get = function() return getSetting("iconPadding") or 2 end,
                set = function(v) setSetting("iconPadding", v) end,
                minLabel = "2px",
                maxLabel = "14px",
                -- Debounced Edit Mode sync for slider performance
                debounceKey = "UI_essentialCooldowns_iconPadding",
                debounceDelay = 0.2,
                onEditModeSync = function(newValue)
                    syncEditModeSetting("iconPadding")
                end,
            })

            inner:Finalize()
        end,
    })

    -- Collapsible section: Sizing
    builder:AddCollapsibleSection({
        title = "Sizing",
        componentId = "essentialCooldowns",
        sectionKey = "sizing",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            -- Icon Size (Scale) - Edit Mode setting
            inner:AddSlider({
                label = "Icon Size (Scale)",
                description = "Scale the icons in Edit Mode (50-200%).",
                min = 50,
                max = 200,
                step = 10,
                get = function() return getSetting("iconSize") or 100 end,
                set = function(v) setSetting("iconSize", v) end,
                minLabel = "50%",
                maxLabel = "200%",
                debounceKey = "UI_essentialCooldowns_iconSize",
                debounceDelay = 0.2,
                onEditModeSync = function(newValue)
                    syncEditModeSetting("iconSize")
                end,
            })

            -- Icon Shape (Tall/Wide Ratio)
            inner:AddSlider({
                label = "Icon Shape",
                description = "Adjust icon aspect ratio. Center = square icons.",
                min = -67,
                max = 67,
                step = 1,
                get = function() return getSetting("tallWideRatio") or 0 end,
                set = function(v)
                    setSetting("tallWideRatio", v)
                    if addon and addon.ApplyStyles then
                        C_Timer.After(0, function() addon:ApplyStyles() end)
                    end
                end,
                minLabel = "Wide",
                maxLabel = "Tall",
            })

            inner:Finalize()
        end,
    })

    -- Collapsible section: Border
    builder:AddCollapsibleSection({
        title = "Border",
        componentId = "essentialCooldowns",
        sectionKey = "border",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            -- Use Custom Border toggle
            inner:AddToggle({
                key = "borderEnable",
                label = "Use Custom Border",
                description = "Enable custom border styling for cooldown icons.",
                get = function() return getSetting("borderEnable") or false end,
                set = function(val)
                    setSetting("borderEnable", val)
                    if addon and addon.ApplyStyles then
                        C_Timer.After(0, function() addon:ApplyStyles() end)
                    end
                end,
            })

            -- Border Tint toggle+color
            inner:AddToggleColorPicker({
                label = "Border Tint",
                description = "Apply a custom tint color to the icon border.",
                get = function()
                    return getSetting("borderTintEnable") or false
                end,
                set = function(val)
                    setSetting("borderTintEnable", val)
                    if addon and addon.ApplyStyles then
                        C_Timer.After(0, function() addon:ApplyStyles() end)
                    end
                end,
                getColor = function()
                    local c = getSetting("borderTintColor")
                    if c then
                        return c.r or c[1] or 1, c.g or c[2] or 1, c.b or c[3] or 1, c.a or c[4] or 1
                    end
                    return 1, 1, 1, 1
                end,
                setColor = function(r, g, b, a)
                    setSetting("borderTintColor", {r, g, b, a})
                    if addon and addon.ApplyStyles then
                        C_Timer.After(0, function() addon:ApplyStyles() end)
                    end
                end,
                hasAlpha = true,
            })

            -- Border Style selector
            local borderStyleValues, borderStyleOrder = Helpers.getIconBorderOptions()

            inner:AddSelector({
                key = "borderStyle",
                label = "Border Style",
                description = "Choose the visual style for icon borders.",
                values = borderStyleValues,
                order = borderStyleOrder,
                get = function() return getSetting("borderStyle") or "square" end,
                set = function(v)
                    setSetting("borderStyle", v)
                    if addon and addon.ApplyStyles then
                        C_Timer.After(0, function() addon:ApplyStyles() end)
                    end
                end,
            })

            -- Border Thickness slider
            inner:AddSlider({
                label = "Border Thickness",
                description = "Thickness of the border in pixels.",
                min = 1,
                max = 8,
                step = 0.5,
                precision = 1,
                get = function() return getSetting("borderThickness") or 1 end,
                set = function(v)
                    setSetting("borderThickness", v)
                    if addon and addon.ApplyStyles then
                        C_Timer.After(0, function() addon:ApplyStyles() end)
                    end
                end,
                minLabel = "1",
                maxLabel = "8",
            })

            -- Border Inset dual slider (H/V)
            inner:AddDualSlider({
                label = "Border Inset",
                sliderA = {
                    axisLabel = "H", min = -4, max = 4, step = 1,
                    get = function() return getSetting("borderInsetH") or getSetting("borderInset") or -1 end,
                    set = function(v)
                        setSetting("borderInsetH", v)
                        if addon and addon.ApplyStyles then
                            C_Timer.After(0, function() addon:ApplyStyles() end)
                        end
                    end,
                    minLabel = "-4", maxLabel = "+4",
                },
                sliderB = {
                    axisLabel = "V", min = -4, max = 4, step = 1,
                    get = function() return getSetting("borderInsetV") or getSetting("borderInset") or -1 end,
                    set = function(v)
                        setSetting("borderInsetV", v)
                        if addon and addon.ApplyStyles then
                            C_Timer.After(0, function() addon:ApplyStyles() end)
                        end
                    end,
                    minLabel = "-4", maxLabel = "+4",
                },
            })

            inner:Finalize()
        end,
    })

    -- Collapsible section: Text (contains tabbed sub-sections)
    builder:AddCollapsibleSection({
        title = "Text",
        componentId = "essentialCooldowns",
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

            -- Tabbed section for Charges, Cooldowns, and Keybinds text settings
            inner:AddTabbedSection({
                tabs = {
                    { key = "charges", label = "Charges" },
                    { key = "cooldowns", label = "Cooldowns" },
                    { key = "bindings", label = "Keybinds", infoIcon = {
                        tooltipTitle = "Keybind Labels",
                        tooltipText = "Addon-generated text showing your keybind for each ability. Enable with the toggle below.",
                    }},
                },
                componentId = "essentialCooldowns",
                sectionKey = "textTabs",
                buildContent = {
                    charges = function(tabContent, tabBuilder)
                        -- Helper to get/set textStacks sub-properties
                        local function getStacksSetting(key, default)
                            local ts = getSetting("textStacks")
                            if ts and ts[key] ~= nil then return ts[key] end
                            return default
                        end
                        local function setStacksSetting(key, value)
                            local comp = getComponent()
                            if comp and comp.db then
                                comp.db.textStacks = comp.db.textStacks or {}
                                comp.db.textStacks[key] = value
                            end
                            applyText()
                        end

                        -- Font selector
                        tabBuilder:AddFontSelector({
                            label = "Font",
                            description = "The font used for charges/stacks text.",
                            get = function() return getStacksSetting("fontFace", "FRIZQT__") end,
                            set = function(v) setStacksSetting("fontFace", v) end,
                        })

                        -- Font Size slider
                        tabBuilder:AddSlider({
                            label = "Font Size",
                            min = 6,
                            max = 32,
                            step = 1,
                            get = function() return getStacksSetting("size", 16) end,
                            set = function(v) setStacksSetting("size", v) end,
                            minLabel = "6",
                            maxLabel = "32",
                        })

                        -- Font Style selector
                        tabBuilder:AddSelector({
                            label = "Font Style",
                            values = fontStyleValues,
                            order = fontStyleOrder,
                            get = function() return getStacksSetting("style", "OUTLINE") end,
                            set = function(v) setStacksSetting("style", v) end,
                        })

                        -- Font Color picker
                        tabBuilder:AddSelectorColorPicker({
                            label = "Font Color",
                            values = textColorValues,
                            order = textColorOrder,
                            get = function() return getStacksSetting("colorMode", "default") end,
                            set = function(v) setStacksSetting("colorMode", v or "default") end,
                            getColor = function()
                                local c = getStacksSetting("color", {1,1,1,1})
                                return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
                            end,
                            setColor = function(r, g, b, a)
                                setStacksSetting("color", {r, g, b, a})
                            end,
                            customValue = "custom",
                            hasAlpha = true,
                        })

                        -- Offset dual slider (X and Y side-by-side)
                        tabBuilder:AddDualSlider({
                            label = "Offset",
                            sliderA = {
                                axisLabel = "X",
                                min = -100,
                                max = 100,
                                step = 1,
                                get = function()
                                    local offset = getStacksSetting("offset", {x=0, y=0})
                                    return offset.x or 0
                                end,
                                set = function(v)
                                    local comp = getComponent()
                                    if comp and comp.db then
                                        comp.db.textStacks = comp.db.textStacks or {}
                                        comp.db.textStacks.offset = comp.db.textStacks.offset or {}
                                        comp.db.textStacks.offset.x = v
                                    end
                                    applyText()
                                end,
                                minLabel = "-100",
                                maxLabel = "+100",
                            },
                            sliderB = {
                                axisLabel = "Y",
                                min = -100,
                                max = 100,
                                step = 1,
                                get = function()
                                    local offset = getStacksSetting("offset", {x=0, y=0})
                                    return offset.y or 0
                                end,
                                set = function(v)
                                    local comp = getComponent()
                                    if comp and comp.db then
                                        comp.db.textStacks = comp.db.textStacks or {}
                                        comp.db.textStacks.offset = comp.db.textStacks.offset or {}
                                        comp.db.textStacks.offset.y = v
                                    end
                                    applyText()
                                end,
                                minLabel = "-100",
                                maxLabel = "+100",
                            },
                        })

                        tabBuilder:Finalize()
                    end,
                    cooldowns = function(tabContent, tabBuilder)
                        -- Helper to get/set textCooldown sub-properties
                        local function getCooldownSetting(key, default)
                            local tc = getSetting("textCooldown")
                            if tc and tc[key] ~= nil then return tc[key] end
                            return default
                        end
                        local function setCooldownSetting(key, value)
                            local comp = getComponent()
                            if comp and comp.db then
                                comp.db.textCooldown = comp.db.textCooldown or {}
                                comp.db.textCooldown[key] = value
                            end
                            applyText()
                        end

                        -- Font selector
                        tabBuilder:AddFontSelector({
                            label = "Font",
                            description = "The font used for cooldown timer text.",
                            get = function() return getCooldownSetting("fontFace", "FRIZQT__") end,
                            set = function(v) setCooldownSetting("fontFace", v) end,
                        })

                        -- Font Size slider
                        tabBuilder:AddSlider({
                            label = "Font Size",
                            min = 6,
                            max = 32,
                            step = 1,
                            get = function() return getCooldownSetting("size", 14) end,
                            set = function(v) setCooldownSetting("size", v) end,
                            minLabel = "6",
                            maxLabel = "32",
                        })

                        -- Font Style selector
                        tabBuilder:AddSelector({
                            label = "Font Style",
                            values = fontStyleValues,
                            order = fontStyleOrder,
                            get = function() return getCooldownSetting("style", "OUTLINE") end,
                            set = function(v) setCooldownSetting("style", v) end,
                        })

                        -- Font Color picker
                        tabBuilder:AddSelectorColorPicker({
                            label = "Font Color",
                            values = textColorValues,
                            order = textColorOrder,
                            get = function() return getCooldownSetting("colorMode", "default") end,
                            set = function(v) setCooldownSetting("colorMode", v or "default") end,
                            getColor = function()
                                local c = getCooldownSetting("color", {1,1,1,1})
                                return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
                            end,
                            setColor = function(r, g, b, a)
                                setCooldownSetting("color", {r, g, b, a})
                            end,
                            customValue = "custom",
                            hasAlpha = true,
                        })

                        tabBuilder:AddDualSlider({
                            label = "Offset",
                            sliderA = {
                                axisLabel = "X",
                                min = -100, max = 100, step = 1,
                                get = function()
                                    local offset = getCooldownSetting("offset", {x=0, y=0})
                                    return offset.x or 0
                                end,
                                set = function(v)
                                    local comp = getComponent()
                                    if comp and comp.db then
                                        comp.db.textCooldown = comp.db.textCooldown or {}
                                        comp.db.textCooldown.offset = comp.db.textCooldown.offset or {}
                                        comp.db.textCooldown.offset.x = v
                                    end
                                    applyText()
                                end,
                                minLabel = "-100", maxLabel = "+100",
                            },
                            sliderB = {
                                axisLabel = "Y",
                                min = -100, max = 100, step = 1,
                                get = function()
                                    local offset = getCooldownSetting("offset", {x=0, y=0})
                                    return offset.y or 0
                                end,
                                set = function(v)
                                    local comp = getComponent()
                                    if comp and comp.db then
                                        comp.db.textCooldown = comp.db.textCooldown or {}
                                        comp.db.textCooldown.offset = comp.db.textCooldown.offset or {}
                                        comp.db.textCooldown.offset.y = v
                                    end
                                    applyText()
                                end,
                                minLabel = "-100", maxLabel = "+100",
                            },
                        })

                        tabBuilder:Finalize()
                    end,
                    bindings = function(tabContent, tabBuilder)
                        -- Helper to get/set textBindings sub-properties
                        local function getBindingSetting(key, default)
                            local tb = getSetting("textBindings")
                            if tb and tb[key] ~= nil then return tb[key] end
                            return default
                        end
                        local function setBindingSetting(key, value)
                            local comp = getComponent()
                            if comp and comp.db then
                                comp.db.textBindings = comp.db.textBindings or {}
                                comp.db.textBindings[key] = value
                            end
                            applyText()
                        end

                        -- Enable toggle
                        tabBuilder:AddToggle({
                            label = "Show Keybinds",
                            description = "Display keybind text on cooldown icons.",
                            get = function() return getBindingSetting("enabled", false) end,
                            set = function(v) setBindingSetting("enabled", v) end,
                        })

                        -- Font selector
                        tabBuilder:AddFontSelector({
                            label = "Font",
                            description = "The font used for keybind text.",
                            get = function() return getBindingSetting("fontFace", "FRIZQT__") end,
                            set = function(v) setBindingSetting("fontFace", v) end,
                        })

                        -- Font Size slider
                        tabBuilder:AddSlider({
                            label = "Font Size",
                            min = 6,
                            max = 32,
                            step = 1,
                            get = function() return getBindingSetting("size", 12) end,
                            set = function(v) setBindingSetting("size", v) end,
                            minLabel = "6",
                            maxLabel = "32",
                        })

                        -- Font Style selector
                        tabBuilder:AddSelector({
                            label = "Font Style",
                            values = fontStyleValues,
                            order = fontStyleOrder,
                            get = function() return getBindingSetting("style", "OUTLINE") end,
                            set = function(v) setBindingSetting("style", v) end,
                        })

                        -- Font Color picker
                        tabBuilder:AddSelectorColorPicker({
                            label = "Font Color",
                            values = textColorValues,
                            order = textColorOrder,
                            get = function() return getBindingSetting("colorMode", "default") end,
                            set = function(v) setBindingSetting("colorMode", v or "default") end,
                            getColor = function()
                                local c = getBindingSetting("color", {1,1,1,1})
                                return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
                            end,
                            setColor = function(r, g, b, a)
                                setBindingSetting("color", {r, g, b, a})
                            end,
                            customValue = "custom",
                            hasAlpha = true,
                        })

                        -- Anchor selector (9-point)
                        local anchorPoints = {
                            TOPLEFT = "Top-Left", TOP = "Top-Center", TOPRIGHT = "Top-Right",
                            LEFT = "Left", CENTER = "Center", RIGHT = "Right",
                            BOTTOMLEFT = "Bottom-Left", BOTTOM = "Bottom-Center", BOTTOMRIGHT = "Bottom-Right",
                        }
                        local anchorPointOrder = { "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" }

                        tabBuilder:AddSelector({
                            label = "Anchor",
                            values = anchorPoints,
                            order = anchorPointOrder,
                            get = function() return getBindingSetting("anchor", "TOPLEFT") end,
                            set = function(v) setBindingSetting("anchor", v) end,
                        })

                        -- Offset dual slider (X and Y)
                        tabBuilder:AddDualSlider({
                            label = "Offset",
                            sliderA = {
                                axisLabel = "X",
                                min = -100,
                                max = 100,
                                step = 1,
                                get = function()
                                    local offset = getBindingSetting("offset", {x=0, y=0})
                                    return offset.x or 0
                                end,
                                set = function(v)
                                    local comp = getComponent()
                                    if comp and comp.db then
                                        comp.db.textBindings = comp.db.textBindings or {}
                                        comp.db.textBindings.offset = comp.db.textBindings.offset or {}
                                        comp.db.textBindings.offset.x = v
                                    end
                                    applyText()
                                end,
                                minLabel = "-100",
                                maxLabel = "+100",
                            },
                            sliderB = {
                                axisLabel = "Y",
                                min = -100,
                                max = 100,
                                step = 1,
                                get = function()
                                    local offset = getBindingSetting("offset", {x=0, y=0})
                                    return offset.y or 0
                                end,
                                set = function(v)
                                    local comp = getComponent()
                                    if comp and comp.db then
                                        comp.db.textBindings = comp.db.textBindings or {}
                                        comp.db.textBindings.offset = comp.db.textBindings.offset or {}
                                        comp.db.textBindings.offset.y = v
                                    end
                                    applyText()
                                end,
                                minLabel = "-100",
                                maxLabel = "+100",
                            },
                        })

                        tabBuilder:Finalize()
                    end,
                },
            })

            inner:Finalize()
        end,
    })

    -- Collapsible section: Visibility & Misc
    builder:AddCollapsibleSection({
        title = "Visibility & Misc",
        componentId = "essentialCooldowns",
        sectionKey = "misc",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            -- Priority system header + explainer
            inner:AddDescription("Priority System", { color = {1, 0.82, 0}, fontSize = 14, topPadding = 4 })
            inner:AddDescription("With Target > In Combat > Out of Combat. Only the highest active condition applies. On Cooldown competes with the result \226\128\148 whichever is the stronger dim takes effect.", { color = {1, 0.82, 0}, topPadding = -8, bottomPadding = -4 })

            -- Opacity While on Cooldown dual slider (icon + text)
            inner:AddDualSlider({
                label = "Opacity While on Cooldown",
                description = "Dim icons when on cooldown. Text slider keeps the countdown timer readable.",
                sliderA = {
                    axisLabel = "Icon",
                    min = 0, max = 100, step = 1,
                    get = function() return getSetting("opacityOnCooldown") or 100 end,
                    set = function(v)
                        setSetting("opacityOnCooldown", v)
                        if addon and addon.RefreshCDMCooldownOpacity then
                            addon.RefreshCDMCooldownOpacity("EssentialCooldownViewer", "essentialCooldowns")
                        end
                    end,
                    minLabel = "Hidden", maxLabel = "100%",
                },
                sliderB = {
                    axisLabel = "Text",
                    min = 0, max = 100, step = 1,
                    get = function() return getSetting("opacityOnCooldownText") or 100 end,
                    set = function(v)
                        setSetting("opacityOnCooldownText", v)
                        if addon and addon.RefreshCDMCooldownOpacity then
                            addon.RefreshCDMCooldownOpacity("EssentialCooldownViewer", "essentialCooldowns")
                        end
                    end,
                    minLabel = "Hidden", maxLabel = "100%",
                },
            })

            -- Opacity With Target slider (addon-only) — highest priority
            inner:AddSlider({
                label = "Opacity With Target",
                description = "Opacity when you have a target.",
                min = 0,
                max = 100,
                step = 1,
                get = function() return getSetting("opacityWithTarget") or 100 end,
                set = function(v)
                    setSetting("opacityWithTarget", v)
                    if addon and addon.RefreshCDMViewerOpacity then
                        addon.RefreshCDMViewerOpacity("essentialCooldowns")
                    end
                end,
                minLabel = "Hidden",
                maxLabel = "100%",
            })

            -- Opacity in Combat slider (Edit Mode setting)
            inner:AddSlider({
                label = "Opacity in Combat",
                description = "Opacity when in combat (50-100%).",
                min = 50,
                max = 100,
                step = 1,
                get = function() return getSetting("opacity") or 100 end,
                set = function(v) setSetting("opacity", v) end,
                minLabel = "50%",
                maxLabel = "100%",
                debounceKey = "UI_essentialCooldowns_opacity",
                debounceDelay = 0.2,
                onEditModeSync = function(newValue)
                    syncEditModeSetting("opacity")
                end,
            })

            -- Opacity Out of Combat slider (addon-only)
            inner:AddSlider({
                label = "Opacity Out of Combat",
                description = "Opacity when not in combat.",
                min = 0,
                max = 100,
                step = 1,
                get = function() return getSetting("opacityOutOfCombat") or 100 end,
                set = function(v)
                    setSetting("opacityOutOfCombat", v)
                    if addon and addon.RefreshCDMViewerOpacity then
                        addon.RefreshCDMViewerOpacity("essentialCooldowns")
                    end
                end,
                minLabel = "Hidden",
                maxLabel = "100%",
            })

            -- Visibility Mode selector (Edit Mode setting)
            local visibilityValues = {
                always = "Always",
                combat = "Only in Combat",
                never = "Hidden",
            }
            local visibilityOrder = { "always", "combat", "never" }

            inner:AddSelector({
                label = "Visibility",
                description = "When the cooldown tracker is visible.",
                values = visibilityValues,
                order = visibilityOrder,
                get = function() return getSetting("visibilityMode") or "always" end,
                set = function(v)
                    setSetting("visibilityMode", v)
                    syncEditModeSetting("visibilityMode")
                end,
                syncCooldown = 0.4,
            })

            -- Show Timer toggle (Edit Mode setting)
            inner:AddToggle({
                label = "Show Timer",
                description = "Display cooldown timer text on icons.",
                get = function() return getSetting("showTimer") ~= false end,
                set = function(v)
                    setSetting("showTimer", v)
                    syncEditModeSetting("showTimer")
                end,
            })

            -- Show Tooltips toggle (Edit Mode setting)
            inner:AddToggle({
                label = "Show Tooltips",
                description = "Display tooltips when hovering over icons.",
                get = function() return getSetting("showTooltip") ~= false end,
                set = function(v)
                    setSetting("showTooltip", v)
                    syncEditModeSetting("showTooltip")
                end,
            })

            inner:Finalize()
        end,
    })

    -- Finalize the layout
    builder:Finalize()
end

addon.UI.SettingsPanel:RegisterRenderer("essentialCooldowns", function(panel, scrollContent)
    EssentialCooldowns.Render(panel, scrollContent)
end)

return EssentialCooldowns
