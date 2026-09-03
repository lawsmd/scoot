-- DamageMeterXRenderer.lua - Damage Meters X settings renderer
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.Settings = addon.UI.Settings or {}
addon.UI.Settings.DamageMetersX = {}

local DamageMetersX = addon.UI.Settings.DamageMetersX
local SettingsBuilder = addon.UI.SettingsBuilder

function DamageMetersX.Render(panel, scrollContent)
    -- Clear any existing content
    panel:ClearContent()

    -- Create builder for this content area
    local builder = SettingsBuilder:CreateFor(scrollContent)
    panel._currentBuilder = builder

    -- Store reference to this function for re-rendering on expand/collapse
    builder:SetOnRefresh(function()
        DamageMetersX.Render(panel, scrollContent)
    end)

    local Helpers = addon.UI.Settings.Helpers
    local h = Helpers.CreateComponentHelpers("damageMeter")
    local getSetting = h.get
    local setSetting = h.setAndApply
    local syncEditModeSetting = h.sync

    -- Style selector (parent level, Edit Mode synced, emphasized)
    builder:AddSelector({
        label = "Style",
        description = "Choose the visual style for the damage meter frame. This setting syncs with Edit Mode.",
        values = { [0] = "Default", [1] = "Thin", [2] = "Bordered" },
        order = { 0, 1, 2 },
        emphasized = true,
        get = function() return getSetting("style") or 0 end,
        set = function(value)
            setSetting("style", value)
            syncEditModeSetting("style")
        end,
    })

    -- CVar helpers for per-profile damage meter enable
    local function getDamageMeterEnabledFromCVar()
        local v
        if C_CVar and C_CVar.GetCVar then
            v = C_CVar.GetCVar("damageMeterEnabled")
        elseif GetCVar then
            v = GetCVar("damageMeterEnabled")
        end
        return (v == "1") or false
    end

    local function setDamageMeterEnabledCVar(enabled)
        local value = (enabled and "1") or "0"
        if C_CVar and C_CVar.SetCVar then
            pcall(C_CVar.SetCVar, "damageMeterEnabled", value)
        elseif SetCVar then
            pcall(SetCVar, "damageMeterEnabled", value)
        end
    end

    local function getProfileDamageMeterSettings()
        local profile = addon and addon.db and addon.db.profile
        return profile and profile.damageMeterSettings
    end

    local function ensureProfileDamageMeterSettings()
        if not (addon and addon.db and addon.db.profile) then return nil end
        addon.db.profile.damageMeterSettings = addon.db.profile.damageMeterSettings or {}
        return addon.db.profile.damageMeterSettings
    end

    builder:AddToggle({
        label = "Enable Damage Meter",
        description = "Show or hide the Damage Meter on this profile. Overrides Blizzard's per-character setting in Options > Gameplay > Combat.",
        get = function()
            local s = getProfileDamageMeterSettings()
            if s and s.enableDamageMeter ~= nil then
                return s.enableDamageMeter
            end
            return getDamageMeterEnabledFromCVar()
        end,
        set = function(value)
            local s = ensureProfileDamageMeterSettings()
            if not s then return end
            s.enableDamageMeter = value
            setDamageMeterEnabledCVar(value)
            -- Re-apply styling if enabling
            if value and addon and addon.ApplyStyles then
                if C_Timer and C_Timer.After then
                    C_Timer.After(0, function()
                        if addon and addon.ApplyStyles then
                            addon:ApplyStyles()
                        end
                    end)
                else
                    addon:ApplyStyles()
                end
            end
        end,
    })

    -- Quality of Life section
    builder:AddCollapsibleSection({
        title = "Quality of Life",
        componentId = "damageMeter",
        sectionKey = "qol",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddSelector({
                label = "Automatic Reset Data",
                description = "Automatically reset all Damage Meter session data when a trigger condition is met.",
                values = { ["off"] = "Off", ["instance"] = "When Entering an Instance" },
                order = { "off", "instance" },
                get = function() return getSetting("autoResetData") or "off" end,
                set = function(value)
                    setSetting("autoResetData", value)
                    -- Re-render to update disabled state of prompt toggle
                    C_Timer.After(0.05, function()
                        if panel and DamageMetersX.Render then
                            DamageMetersX.Render(panel, scrollContent)
                        end
                    end)
                end,
            })

            inner:AddToggle({
                label = "Prompt Me Before Resetting Data",
                description = "When enabled, a confirmation dialog will appear asking you to approve the data reset before it happens. If disabled, data resets automatically without asking.",
                get = function()
                    return getSetting("autoResetPrompt") ~= false
                end,
                set = function(value) setSetting("autoResetPrompt", value) end,
                isDisabled = function()
                    return (getSetting("autoResetData") or "off") == "off"
                end,
            })

            inner:AddToggle({
                label = "Enable /dmshow and /dmreset commands",
                description = "Type /dmshow to toggle the Damage Meter on or off. Type /dmreset to reset all session data.",
                get = function() return getSetting("enableSlashDM") or false end,
                set = function(value) setSetting("enableSlashDM", value) end,
            })

            inner:Finalize()
        end,
    })

    -- Exports section
    builder:AddCollapsibleSection({
        title = "Exports",
        componentId = "damageMeter",
        sectionKey = "exports",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddToggle({
                label = "Enable Meter Exports",
                description = "Show an export button on each damage meter window's title bar. Lets you export meter data to a High Score window or to chat.",
                get = function() return getSetting("exportEnabled") or false end,
                set = function(value)
                    setSetting("exportEnabled", value)
                end,
            })

            inner:AddTabbedSection({
                componentId = "damageMeter",
                sectionKey = "exportsTabs",
                tabs = {
                    { key = "windowExport", label = "Window Export" },
                    { key = "titleBarButton", label = "Title Bar Button" },
                },
                buildContent = {
                    windowExport = function(tabContent, tabInner)
                        tabInner:AddDescription("Settings coming soon.")
                        tabInner:Finalize()
                    end,
                    titleBarButton = function(tabContent, tabInner)
                        tabInner:AddDescription("Customize this button in the Damage Meters > Title Bar > Buttons section.")
                        tabInner:AddSlider({
                            label = "X-Offset",
                            description = "Adjust the horizontal position of the export button on the title bar.",
                            min = -50, max = 50, step = 1,
                            get = function() return getSetting("exportButtonXOffset") or 0 end,
                            set = function(value) setSetting("exportButtonXOffset", value) end,
                        })
                        tabInner:Finalize()
                    end,
                },
            })

            inner:Finalize()
        end,
    })

    -- Layout section
    builder:AddCollapsibleSection({
        title = "Layout",
        componentId = "damageMeter",
        sectionKey = "layout",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddSlider({
                label = "Frame Width",
                min = 300, max = 600, step = 10,
                get = function() return getSetting("frameWidth") or 300 end,
                set = function(value)
                    setSetting("frameWidth", value)
                    syncEditModeSetting("frameWidth")
                end,
            })
            inner:AddSlider({
                label = "Frame Height",
                min = 120, max = 400, step = 10,
                get = function() return getSetting("frameHeight") or 200 end,
                set = function(value)
                    setSetting("frameHeight", value)
                    syncEditModeSetting("frameHeight")
                end,
            })
            inner:AddSlider({
                label = "Padding",
                min = 2, max = 10, step = 1,
                get = function() return getSetting("padding") or 4 end,
                set = function(value)
                    setSetting("padding", value)
                    syncEditModeSetting("padding")
                end,
            })
        end,
    })

    local function applyText()
        if addon and addon.ApplyStyles then
            C_Timer.After(0, function()
                if addon and addon.ApplyStyles then addon:ApplyStyles() end
            end)
        end
    end

    -- The text sub-tables store the style under "fontStyle" rather than
    -- "style"; the accessors translate the composite's field names.
    local function subTextAccessors(subKey)
        local s = Helpers.CreateSubTableHelpers("damageMeter", subKey, { apply = applyText })
        local function get(field)
            if field == "style" then field = "fontStyle" end
            return s.get(field)
        end
        local function set(field, value)
            if field == "style" then field = "fontStyle" end
            s.set(field, value)
        end
        return get, set, s
    end

    -- Bars section (collapsible with tabs inside)
    builder:AddCollapsibleSection({
        title = "Bars",
        componentId = "damageMeter",
        sectionKey = "bars",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddTabbedSection({
                componentId = "damageMeter",
                sectionKey = "barsTabs",
                tabs = {
                    { key = "sizing", label = "Sizing" },
                    { key = "style", label = "Style" },
                    { key = "border", label = "Border" },
                    { key = "namesText", label = "Names Text" },
                    { key = "numbersText", label = "Numbers Text" },
                },
                buildContent = {
                    sizing = function(tabContent, tabInner)
                        tabInner:AddSlider({
                            label = "Bar Height",
                            min = 18, max = 40, step = 1,
                            get = function() return getSetting("barHeight") or 20 end,
                            set = function(value)
                                setSetting("barHeight", value)
                                syncEditModeSetting("barHeight")
                            end,
                        })
                        tabInner:Finalize()
                    end,
                    style = function(tabContent, tabInner)
                        tabInner:AddBarTextureSelector({
                            label = "Bar Texture",
                            get = function() return getSetting("barTexture") or "pointed" end,
                            set = function(value)
                                setSetting("barTexture", value)
                            end,
                        })
                        tabInner:AddToggle({
                            label = "Show Class Color",
                            description = "Use player class colors for bars instead of a single color. Syncs with Edit Mode.",
                            get = function() return getSetting("showClassColor") end,
                            set = function(value)
                                setSetting("showClassColor", value)
                                syncEditModeSetting("showClassColor")
                                -- Refresh the Foreground Color selector disabled state
                                local fgColorControl = tabInner:GetControl("barForegroundColor")
                                if fgColorControl and fgColorControl.Refresh then
                                    fgColorControl:Refresh()
                                end
                            end,
                        })
                        tabInner:AddSelectorColorPicker({
                            label = "Foreground Color",
                            description = "Bar fill color when 'Show Class Color' is disabled. Disabled when class colors are enabled above.",
                            key = "barForegroundColor",
                            values = addon.Catalogs.ColorMode.DefaultCustom.values,
                            order = addon.Catalogs.ColorMode.DefaultCustom.order,
                            get = function()
                                return getSetting("barForegroundColorMode") or "default"
                            end,
                            set = function(value)
                                setSetting("barForegroundColorMode", value)
                            end,
                            getColor = function()
                                local c = getSetting("barForegroundTint")
                                if c then
                                    return c.r or c[1] or 1, c.g or c[2] or 0.8, c.b or c[3] or 0, c.a or c[4] or 1
                                end
                                return 1, 0.8, 0, 1
                            end,
                            setColor = function(r, g, b, a)
                                setSetting("barForegroundTint", { r = r, g = g, b = b, a = a or 1 })
                            end,
                            customValue = "custom",
                            hasAlpha = false,
                            disabled = function() return getSetting("showClassColor") end,
                        })
                        tabInner:AddSelectorColorPicker({
                            label = "Background Color",
                            description = "Bar background color mode.",
                            values = addon.Catalogs.ColorMode.DefaultCustom.values,
                            order = addon.Catalogs.ColorMode.DefaultCustom.order,
                            get = function()
                                return getSetting("barBackgroundColorMode") or "default"
                            end,
                            set = function(value)
                                setSetting("barBackgroundColorMode", value)
                            end,
                            getColor = function()
                                local c = getSetting("barBackgroundTint")
                                if c then
                                    return c.r or c[1] or 0.1, c.g or c[2] or 0.1, c.b or c[3] or 0.1, c.a or c[4] or 0.8
                                end
                                return 0.1, 0.1, 0.1, 0.8
                            end,
                            setColor = function(r, g, b, a)
                                setSetting("barBackgroundTint", { r = r, g = g, b = b, a = a or 1 })
                            end,
                            customValue = "custom",
                            hasAlpha = true,
                        })
                        tabInner:Finalize()
                    end,
                    border = function(tabContent, tabInner)
                        tabInner:AddBarBorderSelector({
                            label = "Border Style",
                            description = "Select 'No Border' to use Blizzard's default, or choose a custom border style.",
                            includeNone = true,
                            get = function() return getSetting("barBorderStyle") or "none" end,
                            set = function(value)
                                setSetting("barBorderStyle", value)
                            end,
                            getHiddenEdges = function() return getSetting("barBorderHiddenEdges") end,
                            setHiddenEdges = function(value) setSetting("barBorderHiddenEdges", value) end,
                        })
                        tabInner:AddToggleColorPicker({
                            label = "Border Tint",
                            description = "Apply a custom color tint to the border.",
                            get = function() return getSetting("barBorderTintEnabled") end,
                            set = function(value)
                                setSetting("barBorderTintEnabled", value)
                            end,
                            getColor = function()
                                local c = getSetting("barBorderTintColor")
                                if c then return c.r, c.g, c.b, c.a end
                                return 1, 1, 1, 1
                            end,
                            setColor = function(r, g, b, a)
                                setSetting("barBorderTintColor", { r = r, g = g, b = b, a = a or 1 })
                            end,
                        })
                        tabInner:AddSlider({
                            label = "Border Thickness",
                            min = 0.5, max = 4, step = 0.5,
                            get = function() return getSetting("barBorderThickness") or 1 end,
                            set = function(value)
                                setSetting("barBorderThickness", value)
                            end,
                        })
                        tabInner:Finalize()
                    end,
                    namesText = function(tabContent, tabInner)
                        local get, set, s = subTextAccessors("textNames")

                        tabInner:AddSlider({
                            label = "Text Size",
                            description = "Scale for bar text. Syncs with Edit Mode.",
                            min = 50, max = 150, step = 10,
                            get = function() return getSetting("textSize") or 100 end,
                            set = function(value) setSetting("textSize", value) end,
                            debounceKey = "UI_damageMeter_textSize",
                            debounceDelay = 0.2,
                            onEditModeSync = function(newValue)
                                syncEditModeSetting("textSize")
                            end,
                        })
                        tabInner:AddSlider({
                            label = "Scale Multiplier",
                            description = "Multiplies the Edit Mode 'Text Size' setting.",
                            min = 0.5, max = 1.5, step = 0.05,
                            precision = 2,
                            get = function() return get("scaleMultiplier") or 1.0 end,
                            set = function(value) s.setAndApply("scaleMultiplier", value) end,
                        })
                        -- Bar names render on Scoot-drawn overlay FontStrings,
                        -- so the paired Deep Shadow styles are offered here.
                        tabInner:AddTextStyleBlock({
                            get = get, set = set, apply = applyText,
                            style = { order = Helpers.fontStyleOrderPaired },
                            size = false,
                            color = {
                                values = { ["default"] = "Default", ["custom"] = "Custom" },
                                order = { "default", "custom" },
                            },
                            offset = false,
                        })
                        tabInner:Finalize()
                    end,
                    numbersText = function(tabContent, tabInner)
                        local get, set, s = subTextAccessors("textNumbers")

                        tabInner:AddSlider({
                            label = "Text Size",
                            description = "Scale for bar text. Syncs with Edit Mode.",
                            min = 50, max = 150, step = 10,
                            get = function() return getSetting("textSize") or 100 end,
                            set = function(value) setSetting("textSize", value) end,
                            debounceKey = "UI_damageMeter_textSize",
                            debounceDelay = 0.2,
                            onEditModeSync = function(newValue)
                                syncEditModeSetting("textSize")
                            end,
                        })
                        tabInner:AddSlider({
                            label = "Scale Multiplier",
                            description = "Multiplies the Edit Mode 'Text Size' setting.",
                            min = 0.5, max = 1.5, step = 0.05,
                            precision = 2,
                            get = function() return get("scaleMultiplier") or 1.0 end,
                            set = function(value) s.setAndApply("scaleMultiplier", value) end,
                        })
                        -- Bar numbers render on Scoot-drawn overlay FontStrings,
                        -- so the paired Deep Shadow styles are offered here.
                        tabInner:AddTextStyleBlock({
                            get = get, set = set, apply = applyText,
                            style = { order = Helpers.fontStyleOrderPaired },
                            size = false,
                            color = {
                                values = { ["default"] = "Default", ["custom"] = "Custom" },
                                order = { "default", "custom" },
                            },
                            offset = false,
                        })
                        tabInner:Finalize()
                    end,
                },
            })
        end,
    })

    -- Title Bar section (collapsible with tabs inside)
    builder:AddCollapsibleSection({
        title = "Title Bar",
        componentId = "damageMeter",
        sectionKey = "titleBar",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddTabbedSection({
                componentId = "damageMeter",
                sectionKey = "titleBarTabs",
                tabs = {
                    { key = "titleText", label = "Title Text" },
                    { key = "timerText", label = "Timer Text" },
                    { key = "buttons", label = "Buttons" },
                    { key = "backdrop", label = "Backdrop" },
                },
                buildContent = {
                    titleText = function(tabContent, tabInner)
                        local get, set, s = subTextAccessors("textTitle")

                        -- Scale Multiplier slider (0.5-1.5)
                        tabInner:AddSlider({
                            label = "Scale Multiplier",
                            description = "Adjusts the size of title text.",
                            min = 0.5, max = 1.5, step = 0.05,
                            precision = 2,
                            get = function() return get("scaleMultiplier") or 1.0 end,
                            set = function(value) s.setAndApply("scaleMultiplier", value) end,
                        })

                        -- Blizzard default is GameFontNormalMed1 gold: r=1.0, g=0.82, b=0
                        tabInner:AddTextStyleBlock({
                            get = get, set = set, apply = applyText,
                            defaults = { color = { 1.0, 0.82, 0, 1 } },
                            size = false,
                            color = {
                                values = { ["default"] = "Default (Gold)", ["custom"] = "Custom" },
                                order = { "default", "custom" },
                            },
                            offset = false,
                        })

                        -- Show Session in Title toggle
                        tabInner:AddToggle({
                            label = "Show Session in Title",
                            description = "Display the session type alongside the meter type (e.g., 'DPS (Current)', 'HPS (Overall)', 'Interrupts (Segment 3)').",
                            get = function()
                                return getSetting("showSessionInTitle") or false
                            end,
                            set = function(value)
                                setSetting("showSessionInTitle", value)
                            end,
                        })

                        -- Right-click title to open meter type menu
                        tabInner:AddToggle({
                            label = "Right-Click to Switch Meter Type",
                            description = "Right-click the title text to open the meter type menu (DPS, HPS, Interrupts, etc.).",
                            get = function()
                                return getSetting("titleTextRightClickMeterType") or false
                            end,
                            set = function(value)
                                setSetting("titleTextRightClickMeterType", value)
                            end,
                        })
                        tabInner:Finalize()
                    end,
                    timerText = function(tabContent, tabInner)
                        local get, set = subTextAccessors("textTimer")

                        -- Default is GameFontNormalMed1 gold, same as the title
                        tabInner:AddTextStyleBlock({
                            get = get, set = set, apply = applyText,
                            defaults = { color = { 1.0, 0.82, 0, 1 } },
                            size = false,
                            color = {
                                values = { ["default"] = "Default (Gold)", ["custom"] = "Custom" },
                                order = { "default", "custom" },
                            },
                            offset = false,
                        })
                        tabInner:Finalize()
                    end,
                    buttons = function(tabContent, tabInner)
                        tabInner:AddToggle({
                            label = "Use Custom Icons",
                            description = "Removes button backgrounds for a cleaner look. Replaces the dropdown arrow and gear icons with tintable overlays, hides the session button background.",
                            get = function()
                                return getSetting("buttonIconOverlaysEnabled") or false
                            end,
                            set = function(value)
                                setSetting("buttonIconOverlaysEnabled", value)
                            end,
                        })
                        tabInner:AddSelectorColorPicker({
                            label = "Icon Tint",
                            description = "Apply a color tint to all buttons. Works best with 'Use Custom Icons' enabled for uniform results.",
                            values = {
                                ["default"] = "Default",
                                ["custom"] = "Custom",
                            },
                            order = { "default", "custom" },
                            get = function()
                                return getSetting("buttonTintMode") or "default"
                            end,
                            set = function(value)
                                setSetting("buttonTintMode", value)
                            end,
                            getColor = function()
                                local c = getSetting("buttonTint")
                                if c then return c.r or c[1] or 1, c.g or c[2] or 0.82, c.b or c[3] or 0, c.a or c[4] or 1 end
                                return 1, 0.82, 0, 1  -- Default to gold like title text
                            end,
                            setColor = function(r, g, b, a)
                                setSetting("buttonTint", { r = r, g = g, b = b, a = a or 1 })
                            end,
                            customValue = "custom",
                            hasAlpha = true,
                        })
                        tabInner:Finalize()
                    end,
                    backdrop = function(tabContent, tabInner)
                        tabInner:AddToggle({
                            label = "Show Header Backdrop",
                            description = "Show or hide the header bar background texture.",
                            get = function()
                                local v = getSetting("headerBackdropShow")
                                return v == nil or v  -- Default to true
                            end,
                            set = function(value)
                                setSetting("headerBackdropShow", value)
                            end,
                        })
                        tabInner:AddColorPicker({
                            label = "Backdrop Tint",
                            description = "Apply a color tint to the header backdrop.",
                            get = function()
                                local c = getSetting("headerBackdropTint")
                                if c then return c.r or c[1] or 1, c.g or c[2] or 1, c.b or c[3] or 1, c.a or c[4] or 1 end
                                return 1, 1, 1, 1
                            end,
                            set = function(r, g, b, a)
                                setSetting("headerBackdropTint", { r = r, g = g, b = b, a = a or 1 })
                            end,
                            hasAlpha = true,
                            disabled = function()
                                local show = getSetting("headerBackdropShow")
                                return show == false
                            end,
                        })
                        tabInner:Finalize()
                    end,
                },
            })
        end,
    })

    -- Icons section
    builder:AddCollapsibleSection({
        title = "Icons",
        componentId = "damageMeter",
        sectionKey = "icons",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            -- Helper to check if icons are disabled (showSpecIcon is off)
            local function iconsDisabled()
                return not getSetting("showSpecIcon")
            end

            inner:AddToggle({
                label = "Show Spec Icon",
                description = "Display specialization icons next to player names. Syncs with Edit Mode.",
                get = function() return getSetting("showSpecIcon") end,
                set = function(value)
                    setSetting("showSpecIcon", value)
                    syncEditModeSetting("showSpecIcon")
                    -- Refresh all controls in this section to update disabled states
                    C_Timer.After(0, function()
                        if inner and inner._controls then
                            for _, control in ipairs(inner._controls) do
                                if control and control.Refresh then
                                    pcall(control.Refresh, control)
                                end
                            end
                        end
                    end)
                end,
            })

            -- Use Custom Border toggle
            inner:AddToggle({
                key = "iconBorderEnable",
                label = "Use Custom Border",
                description = "Enable custom border styling for spec icons.",
                get = function() return getSetting("iconBorderEnable") or false end,
                set = function(val)
                    setSetting("iconBorderEnable", val)
                end,
                disabled = iconsDisabled,
            })

            -- Border Tint toggle+color
            inner:AddToggleColorPicker({
                label = "Border Tint",
                description = "Apply a custom tint color to the icon border.",
                get = function()
                    return getSetting("iconBorderTintEnable") or false
                end,
                set = function(val)
                    setSetting("iconBorderTintEnable", val)
                end,
                getColor = function()
                    local c = getSetting("iconBorderTintColor")
                    if c then
                        return c.r or c[1] or 1, c.g or c[2] or 1, c.b or c[3] or 1, c.a or c[4] or 1
                    end
                    return 1, 1, 1, 1
                end,
                setColor = function(r, g, b, a)
                    setSetting("iconBorderTintColor", { r = r, g = g, b = b, a = a })
                end,
                hasAlpha = true,
                disabled = iconsDisabled,
            })

            -- Border Thickness slider
            inner:AddSlider({
                label = "Border Thickness",
                description = "Thickness of the border in pixels.",
                min = 1,
                max = 8,
                step = 0.5,
                precision = 1,
                get = function() return getSetting("iconBorderThickness") or 1 end,
                set = function(v)
                    setSetting("iconBorderThickness", v)
                end,
                minLabel = "1",
                maxLabel = "8",
                disabled = iconsDisabled,
            })

            -- Border Inset (H/V)
            inner:AddDualSlider({
                label = "Border Inset",
                disabled = iconsDisabled,
                sliderA = {
                    axisLabel = "H", min = -4, max = 4, step = 1,
                    get = function() return getSetting("iconBorderInsetH") or 0 end,
                    set = function(v) setSetting("iconBorderInsetH", v) end,
                    minLabel = "-4", maxLabel = "+4",
                },
                sliderB = {
                    axisLabel = "V", min = -4, max = 4, step = 1,
                    get = function() return getSetting("iconBorderInsetV") or 2 end,
                    set = function(v) setSetting("iconBorderInsetV", v) end,
                    minLabel = "-4", maxLabel = "+4",
                },
            })

            -- JiberishIcons Integration
            inner:AddDescription("JiberishIcons Integration")

            local jiAvailable = addon.IsJiberishIconsAvailable and addon.IsJiberishIconsAvailable()

            if not jiAvailable then
                inner:AddDescription("Install ElvUI_JiberishIcons to enable custom class icons.")
            else
                inner:AddToggle({
                    label = "Use JiberishIcons Class Icons",
                    description = "Replace spec icons with styled class icons from ElvUI_JiberishIcons.",
                    get = function() return getSetting("jiberishIconsEnabled") or false end,
                    set = function(value)
                        setSetting("jiberishIconsEnabled", value)
                    end,
                    disabled = iconsDisabled,
                })

                inner:AddSelector({
                    label = "Icon Style",
                    description = "Choose the JiberishIcons style for class icons.",
                    values = addon.GetJiberishIconsStyles and addon.GetJiberishIconsStyles() or {},
                    get = function() return getSetting("jiberishIconsStyle") or "fabled" end,
                    set = function(value)
                        setSetting("jiberishIconsStyle", value)
                    end,
                    disabled = function()
                        return iconsDisabled() or not getSetting("jiberishIconsEnabled")
                    end,
                })
            end
        end,
    })

    -- Windows section (collapsible with tabs inside)
    builder:AddCollapsibleSection({
        title = "Windows",
        componentId = "damageMeter",
        sectionKey = "windows",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddTabbedSection({
                componentId = "damageMeter",
                sectionKey = "windowsTabs",
                tabs = {
                    { key = "border", label = "Border" },
                    { key = "background", label = "Background" },
                },
                buildContent = {
                    border = function(tabContent, tabInner)
                        tabInner:AddToggle({
                            label = "Show Border",
                            description = "Display a border around the damage meter window.",
                            get = function() return getSetting("windowShowBorder") end,
                            set = function(value)
                                setSetting("windowShowBorder", value)
                            end,
                        })
                        tabInner:AddBarBorderSelector({
                            label = "Border Style",
                            get = function() return getSetting("windowBorderStyle") or "pointed" end,
                            set = function(value)
                                setSetting("windowBorderStyle", value)
                            end,
                        })
                        tabInner:AddColorPicker({
                            label = "Border Color",
                            get = function()
                                local c = getSetting("windowBorderColor")
                                if c then return c.r, c.g, c.b, c.a end
                                return 0.3, 0.3, 0.3, 1
                            end,
                            set = function(r, g, b, a)
                                setSetting("windowBorderColor", { r = r, g = g, b = b, a = a or 1 })
                            end,
                        })
                        tabInner:AddSlider({
                            label = "Border Thickness",
                            min = 1, max = 4, step = 1,
                            get = function() return getSetting("windowBorderThickness") or 2 end,
                            set = function(value)
                                setSetting("windowBorderThickness", value)
                            end,
                        })
                        tabInner:Finalize()
                    end,
                    background = function(tabContent, tabInner)
                        tabInner:AddSlider({
                            label = "Background Opacity",
                            description = "Window background transparency. Syncs with Edit Mode.",
                            min = 0, max = 100, step = 5,
                            get = function() return getSetting("background") or 80 end,
                            set = function(value)
                                setSetting("background", value)
                                syncEditModeSetting("background")
                            end,
                        })
                        tabInner:AddToggle({
                            label = "Custom Backdrop",
                            description = "Use a custom backdrop texture instead of the default.",
                            get = function() return getSetting("windowCustomBackdrop") end,
                            set = function(value)
                                setSetting("windowCustomBackdrop", value)
                            end,
                        })
                        tabInner:AddBarTextureSelector({
                            label = "Backdrop Texture",
                            get = function() return getSetting("windowBackdropTexture") or "pointed" end,
                            set = function(value)
                                setSetting("windowBackdropTexture", value)
                            end,
                        })
                        tabInner:AddColorPicker({
                            label = "Backdrop Color",
                            get = function()
                                local c = getSetting("windowBackdropColor")
                                if c then return c.r, c.g, c.b, c.a end
                                return 0.1, 0.1, 0.1, 0.9
                            end,
                            set = function(r, g, b, a)
                                setSetting("windowBackdropColor", { r = r, g = g, b = b, a = a or 1 })
                            end,
                            hasAlpha = true,
                        })
                        tabInner:Finalize()
                    end,
                },
            })
        end,
    })

    -- Visibility & Misc section
    builder:AddCollapsibleSection({
        title = "Visibility & Misc",
        componentId = "damageMeter",
        sectionKey = "visibility",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddSelector({
                label = "Visibility",
                values = { [0] = "Always", [1] = "In Combat", [2] = "Hidden" },
                order = { 0, 1, 2 },
                get = function() return getSetting("visibility") or 0 end,
                set = function(value)
                    setSetting("visibility", value)
                    syncEditModeSetting("visibility")
                end,
            })
            inner:AddSlider({
                label = "Opacity Out of Combat",
                min = 0, max = 100, step = 5,
                minLabel = "0%", maxLabel = "100%",
                get = function() return getSetting("opacityOutOfCombat") or 100 end,
                set = function(value)
                    setSetting("opacityOutOfCombat", value)
                    local comp = addon.Components and addon.Components["damageMeter"]
                    if comp and addon.DamageMetersX._RefreshDamageMeterOpacity then
                        addon.DamageMetersX._RefreshDamageMeterOpacity(comp)
                    end
                end,
            })
            inner:AddSlider({
                label = "Opacity",
                min = 50, max = 100, step = 5,
                minLabel = "50%", maxLabel = "100%",
                get = function() return getSetting("opacity") or 100 end,
                set = function(value)
                    setSetting("opacity", value)
                    syncEditModeSetting("opacity")
                end,
                infoIcon = {
                    tooltipTitle = "Opacity",
                    tooltipText = "Sets the base window opacity (Edit Mode setting). When out of combat, the 'Opacity Out of Combat' slider takes precedence.",
                },
            })
        end,
    })

    -- Finalize the layout
    builder:Finalize()
end

addon.UI.SettingsPanel:RegisterRenderer("damageMeter", function(panel, scrollContent)
    DamageMetersX.Render(panel, scrollContent)
end)

return DamageMetersX
