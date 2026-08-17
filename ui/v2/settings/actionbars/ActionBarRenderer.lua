-- ActionBarRenderer.lua - Action Bar settings renderer (parameterized for bars 1-8, Pet Bar, Stance Bar)
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.Settings = addon.UI.Settings or {}
addon.UI.Settings.ActionBar = {}

local ActionBar = addon.UI.Settings.ActionBar
local SettingsBuilder = addon.UI.SettingsBuilder
local Helpers = addon.UI.Settings.Helpers

-- Runtime state: which bar is selected in the consolidated page
ActionBar._selectedBar = "actionBar1"

--------------------------------------------------------------------------------
-- Render Function
--------------------------------------------------------------------------------

function ActionBar.Render(panel, scrollContent, componentId, opts)
    opts = opts or {}

    if not opts.skipClear then
        panel:ClearContent()
    end

    local builder = opts.builder or SettingsBuilder:CreateFor(scrollContent)
    panel._currentBuilder = builder

    local refreshFn = opts.onRefresh or function()
        ActionBar.Render(panel, scrollContent, componentId)
    end
    builder:SetOnRefresh(refreshFn)

    local h = Helpers.CreateComponentHelpers(componentId)
    local getComponent, getSetting = h.getComponent, h.get
    local setSetting = h.setAndApply
    local syncEditModeSetting = h.sync

    local function getIconBorderOptions()
        return Helpers.getIconBorderOptions({{"off","Off"},{"hidden","Hidden"}})
    end

    local function getBackdropOptions()
        return Helpers.getBackdropOptions()
    end

    -- Determine bar type characteristics
    local isBar1 = (componentId == "actionBar1")
    local isBar2to8 = componentId:match("^actionBar[2-8]$") ~= nil
    local isPetBar = (componentId == "petBar")
    local isStanceBar = (componentId == "stanceBar")
    local hasNumIcons = isBar1 or isBar2to8  -- Only action bars 1-8 have numIcons
    local hasBorderBackdrop = not isStanceBar  -- Stance bar doesn't have backdrop in this UI
    local hasBorder = true  -- All bars including Stance Bar have border settings

    ---------------------------------------------------------------------------
    -- Enable Action Bar Toggle (bars 2-8 only)
    ---------------------------------------------------------------------------
    if isBar2to8 then
        local barNum = tonumber(componentId:match("actionBar(%d)"))

        -- Live-state fallback, used only before the profile has been backfilled.
        local function getBarEnabledFromSettings()
            if not Settings or not Settings.GetSetting then return true end
            local ok, setting = pcall(Settings.GetSetting, "PROXY_SHOW_ACTIONBAR_" .. barNum)
            if ok and setting and setting.GetValue then
                local vOk, val = pcall(setting.GetValue, setting)
                if vOk then return val end
            end
            return true
        end

        -- Profile data helpers
        local function getProfileActionBarSettings()
            local profile = addon and addon.db and addon.db.profile
            return profile and profile.actionBarSettings
        end

        local function ensureProfileActionBarSettings()
            if not (addon and addon.db and addon.db.profile) then return nil end
            addon.db.profile.actionBarSettings = addon.db.profile.actionBarSettings or {}
            return addon.db.profile.actionBarSettings
        end

        builder:AddToggle({
            label = "Enable Action Bar " .. barNum,
            get = function()
                local s = getProfileActionBarSettings()
                local key = "enableBar" .. barNum
                if s and s[key] ~= nil then
                    return s[key]
                end
                return getBarEnabledFromSettings()
            end,
            set = function(value)
                local s = ensureProfileActionBarSettings()
                if not s then return end
                s["enableBar" .. barNum] = value
                -- Delegate the actual write: the reconciler carries the combat guard,
                -- the settings-readiness check and the deferred verify pass.
                if addon and addon.ReconcileActionBarsEnabled then
                    addon.ReconcileActionBarsEnabled("UIToggleBar" .. barNum)
                end
                if addon and addon.ApplyStyles then
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
    end

    ---------------------------------------------------------------------------
    -- Positioning Section
    ---------------------------------------------------------------------------
    builder:AddCollapsibleSection({
        title = "Positioning",
        componentId = componentId,
        sectionKey = "positioning",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddSelector({
                key = "orientationSelector",
                label = "Orientation",
                values = { H = "Horizontal", V = "Vertical" },
                order = { "H", "V" },
                get = function() return getSetting("orientation") or "H" end,
                set = function(v)
                    setSetting("orientation", v)
                    syncEditModeSetting("orientation")
                    local columnsControl = inner:GetControl("columnsSlider")
                    if columnsControl and columnsControl.SetLabel then
                        columnsControl:SetLabel((v == "V") and "# of Rows" or "# of Columns")
                    end
                end,
                syncCooldown = 0.5,
            })

            local orientation = getSetting("orientation") or "H"
            inner:AddSlider({
                key = "columnsSlider",
                label = (orientation == "V") and "# of Rows" or "# of Columns",
                min = 1, max = 4, step = 1,
                get = function() return getSetting("columns") or 1 end,
                set = function(v) setSetting("columns", v) end,
                debounceKey = componentId .. "_columns",
                debounceDelay = 0.3,
                onEditModeSync = function() syncEditModeSetting("columns") end,
                minLabel = "1", maxLabel = "4",
            })

            if hasNumIcons then
                inner:AddSlider({
                    label = "# of Icons", min = 6, max = 12, step = 1,
                    get = function() return getSetting("numIcons") or 12 end,
                    set = function(v) setSetting("numIcons", v) end,
                    debounceKey = componentId .. "_numIcons",
                    debounceDelay = 0.3,
                    onEditModeSync = function() syncEditModeSetting("numIcons") end,
                    minLabel = "6", maxLabel = "12",
                })
            end

            inner:AddSlider({
                label = "Icon Padding", min = 2, max = 10, step = 1,
                get = function() return getSetting("iconPadding") or 2 end,
                set = function(v) setSetting("iconPadding", v) end,
                debounceKey = componentId .. "_iconPadding",
                debounceDelay = 0.3,
                onEditModeSync = function() syncEditModeSetting("iconPadding") end,
                minLabel = "2", maxLabel = "10",
            })

            inner:Finalize()
        end,
    })

    ---------------------------------------------------------------------------
    -- Sizing Section
    ---------------------------------------------------------------------------
    builder:AddCollapsibleSection({
        title = "Sizing",
        componentId = componentId,
        sectionKey = "sizing",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddSlider({
                label = "Icon Size (Scale)", min = 50, max = 200, step = 10,
                get = function() return getSetting("iconSize") or 100 end,
                set = function(v) setSetting("iconSize", v) end,
                debounceKey = componentId .. "_iconSize",
                debounceDelay = 0.3,
                onEditModeSync = function() syncEditModeSetting("iconSize") end,
                minLabel = "50%", maxLabel = "200%",
            })

            inner:AddSlider({
                label = "Icon Shape",
                description = "Adjust icon aspect ratio. Center = square icons.",
                min = -67, max = 67, step = 1,
                get = function() return getSetting("tallWideRatio") or 0 end,
                set = function(v) setSetting("tallWideRatio", v) end,
                debounceKey = componentId .. "_tallWideRatio",
                debounceDelay = 0.15,
                minLabel = "Wide", maxLabel = "Tall",
            })

            inner:Finalize()
        end,
    })

    ---------------------------------------------------------------------------
    -- Text Section (Action Bars 1-8 and Pet Bar only, NOT Stance Bar)
    ---------------------------------------------------------------------------
    local hasTextSection = isBar1 or isBar2to8 or isPetBar
    if hasTextSection then
        builder:AddCollapsibleSection({
            title = "Text",
            componentId = componentId,
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

                -- Determine tabs based on bar type
                -- Action Bars and Pet Bar have 4 tabs: Charges, Cooldowns, Hotkey, Macro Name
                local tabs = {
                    { key = "charges", label = "Charges" },
                    { key = "cooldowns", label = "Cooldowns" },
                    { key = "hotkey", label = "Keybind" },
                    { key = "macroName", label = "Macro Name" },
                }

                inner:AddTabbedSection({
                    tabs = tabs,
                    componentId = componentId,
                    sectionKey = "textTabs",
                    buildContent = {
                        -------------------------------------------------------
                        -- Charges (textStacks) Tab
                        -------------------------------------------------------
                        charges = function(tabContent, tabBuilder)
                            local function getStacksSetting(key, default)
                                local ts = getSetting("textStacks")
                                if ts and ts[key] ~= nil then return ts[key] end
                                return default
                            end
                            local function setStacksSetting(key, value)
                                local comp = getComponent()
                                if comp and comp.db then
                                    if addon.EnsureComponentDB then addon:EnsureComponentDB(comp) end
                                    addon:EnsureComponentSubTable(comp, "textStacks")
                                    comp.db.textStacks[key] = value
                                end
                                applyText()
                            end

                            tabBuilder:AddFontSelector({
                                label = "Font",
                                get = function() return getStacksSetting("fontFace", "FRIZQT__") end,
                                set = function(v) setStacksSetting("fontFace", v) end,
                            })

                            tabBuilder:AddSlider({
                                label = "Font Size",
                                min = 6, max = 32, step = 1,
                                get = function() return getStacksSetting("size", 16) end,
                                set = function(v) setStacksSetting("size", v) end,
                                minLabel = "6", maxLabel = "32",
                            })

                            tabBuilder:AddSelector({
                                label = "Font Style",
                                values = fontStyleValues,
                                order = fontStyleOrder,
                                get = function() return getStacksSetting("style", "OUTLINE") end,
                                set = function(v) setStacksSetting("style", v) end,
                            })

                            tabBuilder:AddColorPicker({
                                label = "Font Color",
                                get = function()
                                    local c = getStacksSetting("color", {1,1,1,1})
                                    return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
                                end,
                                set = function(r, g, b, a)
                                    setStacksSetting("color", {r, g, b, a})
                                end,
                                hasAlpha = true,
                            })

                            tabBuilder:AddDualSlider({
                                label = "Offset",
                                sliderA = {
                                    axisLabel = "X",
                                    min = -50, max = 50, step = 1,
                                    get = function()
                                        local offset = getStacksSetting("offset", {x=0, y=0})
                                        return (type(offset) == "table" and offset.x) or 0
                                    end,
                                    set = function(v)
                                        local comp = getComponent()
                                        if comp and comp.db then
                                            if addon.EnsureComponentDB then addon:EnsureComponentDB(comp) end
                                            addon:EnsureComponentSubTable(comp, "textStacks")
                                            comp.db.textStacks.offset = comp.db.textStacks.offset or {}
                                            comp.db.textStacks.offset.x = v
                                        end
                                        applyText()
                                    end,
                                },
                                sliderB = {
                                    axisLabel = "Y",
                                    min = -50, max = 50, step = 1,
                                    get = function()
                                        local offset = getStacksSetting("offset", {x=0, y=0})
                                        return (type(offset) == "table" and offset.y) or 0
                                    end,
                                    set = function(v)
                                        local comp = getComponent()
                                        if comp and comp.db then
                                            if addon.EnsureComponentDB then addon:EnsureComponentDB(comp) end
                                            addon:EnsureComponentSubTable(comp, "textStacks")
                                            comp.db.textStacks.offset = comp.db.textStacks.offset or {}
                                            comp.db.textStacks.offset.y = v
                                        end
                                        applyText()
                                    end,
                                },
                            })

                            tabBuilder:Finalize()
                        end,

                        -------------------------------------------------------
                        -- Cooldowns (textCooldown) Tab
                        -------------------------------------------------------
                        cooldowns = function(tabContent, tabBuilder)
                            local function getCooldownSetting(key, default)
                                local tc = getSetting("textCooldown")
                                if tc and tc[key] ~= nil then return tc[key] end
                                return default
                            end
                            local function setCooldownSetting(key, value)
                                local comp = getComponent()
                                if comp and comp.db then
                                    if addon.EnsureComponentDB then addon:EnsureComponentDB(comp) end
                                    addon:EnsureComponentSubTable(comp, "textCooldown")
                                    comp.db.textCooldown[key] = value
                                end
                                applyText()
                            end

                            tabBuilder:AddFontSelector({
                                label = "Font",
                                get = function() return getCooldownSetting("fontFace", "FRIZQT__") end,
                                set = function(v) setCooldownSetting("fontFace", v) end,
                            })

                            tabBuilder:AddSlider({
                                label = "Font Size",
                                min = 6, max = 32, step = 1,
                                get = function() return getCooldownSetting("size", 14) end,
                                set = function(v) setCooldownSetting("size", v) end,
                                minLabel = "6", maxLabel = "32",
                            })

                            tabBuilder:AddSelector({
                                label = "Font Style",
                                values = fontStyleValues,
                                order = fontStyleOrder,
                                get = function() return getCooldownSetting("style", "OUTLINE") end,
                                set = function(v) setCooldownSetting("style", v) end,
                            })

                            tabBuilder:AddColorPicker({
                                label = "Font Color",
                                get = function()
                                    local c = getCooldownSetting("color", {1,1,1,1})
                                    return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
                                end,
                                set = function(r, g, b, a)
                                    setCooldownSetting("color", {r, g, b, a})
                                end,
                                hasAlpha = true,
                            })

                            tabBuilder:AddDualSlider({
                                label = "Offset",
                                sliderA = {
                                    axisLabel = "X",
                                    min = -50, max = 50, step = 1,
                                    get = function()
                                        local offset = getCooldownSetting("offset", {x=0, y=0})
                                        return (type(offset) == "table" and offset.x) or 0
                                    end,
                                    set = function(v)
                                        local comp = getComponent()
                                        if comp and comp.db then
                                            if addon.EnsureComponentDB then addon:EnsureComponentDB(comp) end
                                            addon:EnsureComponentSubTable(comp, "textCooldown")
                                            comp.db.textCooldown.offset = comp.db.textCooldown.offset or {}
                                            comp.db.textCooldown.offset.x = v
                                        end
                                        applyText()
                                    end,
                                },
                                sliderB = {
                                    axisLabel = "Y",
                                    min = -50, max = 50, step = 1,
                                    get = function()
                                        local offset = getCooldownSetting("offset", {x=0, y=0})
                                        return (type(offset) == "table" and offset.y) or 0
                                    end,
                                    set = function(v)
                                        local comp = getComponent()
                                        if comp and comp.db then
                                            if addon.EnsureComponentDB then addon:EnsureComponentDB(comp) end
                                            addon:EnsureComponentSubTable(comp, "textCooldown")
                                            comp.db.textCooldown.offset = comp.db.textCooldown.offset or {}
                                            comp.db.textCooldown.offset.y = v
                                        end
                                        applyText()
                                    end,
                                },
                            })

                            tabBuilder:Finalize()
                        end,

                        -------------------------------------------------------
                        -- Hotkey (textHotkey) Tab
                        -------------------------------------------------------
                        hotkey = function(tabContent, tabBuilder)
                            local function getHotkeySetting(key, default)
                                local th = getSetting("textHotkey")
                                if th and th[key] ~= nil then return th[key] end
                                return default
                            end
                            local function setHotkeySetting(key, value)
                                local comp = getComponent()
                                if comp and comp.db then
                                    if addon.EnsureComponentDB then addon:EnsureComponentDB(comp) end
                                    addon:EnsureComponentSubTable(comp, "textHotkey")
                                    comp.db.textHotkey[key] = value
                                end
                                applyText()
                            end

                            -- Hide Hotkey toggle (stored as textHotkeyHidden)
                            tabBuilder:AddToggle({
                                label = "Hide Hotkey Text",
                                get = function() return getSetting("textHotkeyHidden") or false end,
                                set = function(v)
                                    local comp = getComponent()
                                    if comp and comp.db then
                                        if addon.EnsureComponentDB then addon:EnsureComponentDB(comp) end
                                        comp.db.textHotkeyHidden = v
                                    end
                                    applyText()
                                end,
                            })

                            tabBuilder:AddFontSelector({
                                label = "Font",
                                get = function() return getHotkeySetting("fontFace", "FRIZQT__") end,
                                set = function(v) setHotkeySetting("fontFace", v) end,
                            })

                            tabBuilder:AddSlider({
                                label = "Font Size",
                                min = 6, max = 32, step = 1,
                                get = function() return getHotkeySetting("size", 14) end,
                                set = function(v) setHotkeySetting("size", v) end,
                                minLabel = "6", maxLabel = "32",
                            })

                            tabBuilder:AddSelector({
                                label = "Font Style",
                                values = fontStyleValues,
                                order = fontStyleOrder,
                                get = function() return getHotkeySetting("style", "OUTLINE") end,
                                set = function(v) setHotkeySetting("style", v) end,
                            })

                            tabBuilder:AddColorPicker({
                                label = "Font Color",
                                get = function()
                                    local c = getHotkeySetting("color", {1,1,1,1})
                                    return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
                                end,
                                set = function(r, g, b, a)
                                    setHotkeySetting("color", {r, g, b, a})
                                end,
                                hasAlpha = true,
                            })

                            tabBuilder:AddDualSlider({
                                label = "Offset",
                                sliderA = {
                                    axisLabel = "X",
                                    min = -50, max = 50, step = 1,
                                    get = function()
                                        local offset = getHotkeySetting("offset", {x=0, y=0})
                                        return (type(offset) == "table" and offset.x) or 0
                                    end,
                                    set = function(v)
                                        local comp = getComponent()
                                        if comp and comp.db then
                                            if addon.EnsureComponentDB then addon:EnsureComponentDB(comp) end
                                            addon:EnsureComponentSubTable(comp, "textHotkey")
                                            comp.db.textHotkey.offset = comp.db.textHotkey.offset or {}
                                            comp.db.textHotkey.offset.x = v
                                        end
                                        applyText()
                                    end,
                                },
                                sliderB = {
                                    axisLabel = "Y",
                                    min = -50, max = 50, step = 1,
                                    get = function()
                                        local offset = getHotkeySetting("offset", {x=0, y=0})
                                        return (type(offset) == "table" and offset.y) or 0
                                    end,
                                    set = function(v)
                                        local comp = getComponent()
                                        if comp and comp.db then
                                            if addon.EnsureComponentDB then addon:EnsureComponentDB(comp) end
                                            addon:EnsureComponentSubTable(comp, "textHotkey")
                                            comp.db.textHotkey.offset = comp.db.textHotkey.offset or {}
                                            comp.db.textHotkey.offset.y = v
                                        end
                                        applyText()
                                    end,
                                },
                            })

                            tabBuilder:Finalize()
                        end,

                        -------------------------------------------------------
                        -- Macro Name (textMacro) Tab
                        -------------------------------------------------------
                        macroName = function(tabContent, tabBuilder)
                            local function getMacroSetting(key, default)
                                local tm = getSetting("textMacro")
                                if tm and tm[key] ~= nil then return tm[key] end
                                return default
                            end
                            local function setMacroSetting(key, value)
                                local comp = getComponent()
                                if comp and comp.db then
                                    if addon.EnsureComponentDB then addon:EnsureComponentDB(comp) end
                                    addon:EnsureComponentSubTable(comp, "textMacro")
                                    comp.db.textMacro[key] = value
                                end
                                applyText()
                            end

                            -- Hide Macro Name toggle (stored as textMacroHidden)
                            tabBuilder:AddToggle({
                                label = "Hide Macro Name",
                                get = function() return getSetting("textMacroHidden") or false end,
                                set = function(v)
                                    local comp = getComponent()
                                    if comp and comp.db then
                                        if addon.EnsureComponentDB then addon:EnsureComponentDB(comp) end
                                        comp.db.textMacroHidden = v
                                    end
                                    applyText()
                                end,
                            })

                            tabBuilder:AddFontSelector({
                                label = "Font",
                                get = function() return getMacroSetting("fontFace", "FRIZQT__") end,
                                set = function(v) setMacroSetting("fontFace", v) end,
                            })

                            tabBuilder:AddSlider({
                                label = "Font Size",
                                min = 6, max = 32, step = 1,
                                get = function() return getMacroSetting("size", 14) end,
                                set = function(v) setMacroSetting("size", v) end,
                                minLabel = "6", maxLabel = "32",
                            })

                            tabBuilder:AddSelector({
                                label = "Font Style",
                                values = fontStyleValues,
                                order = fontStyleOrder,
                                get = function() return getMacroSetting("style", "OUTLINE") end,
                                set = function(v) setMacroSetting("style", v) end,
                            })

                            tabBuilder:AddColorPicker({
                                label = "Font Color",
                                get = function()
                                    local c = getMacroSetting("color", {1,1,1,1})
                                    return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
                                end,
                                set = function(r, g, b, a)
                                    setMacroSetting("color", {r, g, b, a})
                                end,
                                hasAlpha = true,
                            })

                            tabBuilder:AddDualSlider({
                                label = "Offset",
                                sliderA = {
                                    axisLabel = "X",
                                    min = -50, max = 50, step = 1,
                                    get = function()
                                        local offset = getMacroSetting("offset", {x=0, y=0})
                                        return (type(offset) == "table" and offset.x) or 0
                                    end,
                                    set = function(v)
                                        local comp = getComponent()
                                        if comp and comp.db then
                                            if addon.EnsureComponentDB then addon:EnsureComponentDB(comp) end
                                            addon:EnsureComponentSubTable(comp, "textMacro")
                                            comp.db.textMacro.offset = comp.db.textMacro.offset or {}
                                            comp.db.textMacro.offset.x = v
                                        end
                                        applyText()
                                    end,
                                },
                                sliderB = {
                                    axisLabel = "Y",
                                    min = -50, max = 50, step = 1,
                                    get = function()
                                        local offset = getMacroSetting("offset", {x=0, y=0})
                                        return (type(offset) == "table" and offset.y) or 0
                                    end,
                                    set = function(v)
                                        local comp = getComponent()
                                        if comp and comp.db then
                                            if addon.EnsureComponentDB then addon:EnsureComponentDB(comp) end
                                            addon:EnsureComponentSubTable(comp, "textMacro")
                                            comp.db.textMacro.offset = comp.db.textMacro.offset or {}
                                            comp.db.textMacro.offset.y = v
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
    end

    ---------------------------------------------------------------------------
    -- Border Section (all bars including Stance Bar)
    ---------------------------------------------------------------------------
    if hasBorder then
        builder:AddCollapsibleSection({
            title = "Border",
            componentId = componentId,
            sectionKey = "border",
            defaultExpanded = false,
            buildContent = function(contentFrame, inner)
                local borderValues, borderOrder = getIconBorderOptions()
                inner:AddSelector({
                    label = "Border Style",
                    values = borderValues,
                    order = borderOrder,
                    get = function() return getSetting("borderStyle") or "off" end,
                    set = function(v) setSetting("borderStyle", v) builder:DeferredRefreshAll() end,
                    infoIcon = {
                        tooltipTitle = "Border Style",
                        tooltipText = "\"Off\" shows the default Blizzard border, which Scoot does not customize. \"Hidden\" removes all borders entirely.",
                    },
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

                -- Thickness is square-style only; atlas art has no independent edge width
                if addon.IconBorders.SupportsThickness(getSetting("borderStyle") or "off") then
                    inner:AddSlider({
                        label = "Border Thickness", min = 1, max = 8, step = 0.5,
                        get = function() local v = getSetting("borderThickness") or 1; return math.max(1, math.min(8, math.floor(v * 2 + 0.5) / 2)) end,
                        set = function(v) setSetting("borderThickness", math.max(1, math.min(8, math.floor((tonumber(v) or 1) * 2 + 0.5) / 2))) end,
                        minLabel = "1", maxLabel = "8",
                    })
                end

                inner:AddDualSlider({
                    label = "Border Inset",
                    sliderA = {
                        axisLabel = "H",
                        min = -4, max = 4, step = 0.5, precision = 1,
                        get = function() return getSetting("borderInsetH") or getSetting("borderInset") or 0 end,
                        set = function(v) setSetting("borderInsetH", v) end,
                        minLabel = "-4", maxLabel = "4",
                    },
                    sliderB = {
                        axisLabel = "V",
                        min = -4, max = 4, step = 0.5, precision = 1,
                        get = function() return getSetting("borderInsetV") or getSetting("borderInset") or 0 end,
                        set = function(v) setSetting("borderInsetV", v) end,
                        minLabel = "-4", maxLabel = "4",
                    },
                })

                inner:Finalize()
            end,
        })
    end

    ---------------------------------------------------------------------------
    -- Backdrop Section (not for Stance Bar)
    ---------------------------------------------------------------------------
    if hasBorderBackdrop then
        builder:AddCollapsibleSection({
            title = "Backdrop",
            componentId = componentId,
            sectionKey = "backdrop",
            defaultExpanded = false,
            buildContent = function(contentFrame, inner)
                inner:AddToggle({
                    label = "Disable Backdrop",
                    get = function() return getSetting("backdropDisable") or false end,
                    set = function(v) setSetting("backdropDisable", v) end,
                })

                local backdropValues, backdropOrder = getBackdropOptions()
                inner:AddSelector({
                    label = "Backdrop Style",
                    values = backdropValues,
                    order = backdropOrder,
                    get = function() return getSetting("backdropStyle") or "blizzardBg" end,
                    set = function(v) setSetting("backdropStyle", v) end,
                })

                inner:AddSlider({
                    label = "Backdrop Opacity", min = 0, max = 100, step = 1,
                    get = function() return getSetting("backdropOpacity") or 100 end,
                    set = function(v) setSetting("backdropOpacity", v) end,
                    minLabel = "Hidden", maxLabel = "100%",
                })

                inner:AddToggleColorPicker({
                    label = "Backdrop Tint",
                    getToggle = function() return getSetting("backdropTintEnable") or false end,
                    setToggle = function(v) setSetting("backdropTintEnable", v) end,
                    getColor = function()
                        local c = getSetting("backdropTintColor")
                        return c and c[1] or 1, c and c[2] or 1, c and c[3] or 1, c and c[4] or 1
                    end,
                    setColor = function(r, g, b, a) setSetting("backdropTintColor", {r, g, b, a}) end,
                })

                inner:AddSlider({
                    label = "Backdrop Inset", min = -4, max = 4, step = 1,
                    get = function() return getSetting("backdropInset") or 0 end,
                    set = function(v) setSetting("backdropInset", v) end,
                    minLabel = "-4", maxLabel = "4",
                })

                inner:Finalize()
            end,
        })
    end

    ---------------------------------------------------------------------------
    -- Misc/Visibility Section
    ---------------------------------------------------------------------------
    builder:AddCollapsibleSection({
        title = "Visibility & Misc",
        componentId = componentId,
        sectionKey = "misc",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            if isBar2to8 then
                inner:AddSelector({
                    label = "Bar Visible",
                    values = {
                        always = "Always",
                        combat = "In Combat",
                        not_in_combat = "Not In Combat",
                        hidden = "Hidden",
                    },
                    order = { "always", "combat", "not_in_combat", "hidden" },
                    get = function() return getSetting("barVisibility") or "always" end,
                    set = function(v)
                        setSetting("barVisibility", v)
                        syncEditModeSetting("barVisibility")
                    end,
                    syncCooldown = 0.5,
                })
            end

            if isBar1 or isBar2to8 or isPetBar then
                inner:AddToggle({
                    label = "Always Show Buttons",
                    get = function() return getSetting("alwaysShowButtons") ~= false end,
                    set = function(v)
                        setSetting("alwaysShowButtons", v)
                        syncEditModeSetting("alwaysShowButtons")
                    end,
                })
            end

            if isBar1 then
                inner:AddToggle({
                    label = "Hide Bar Art",
                    get = function() return getSetting("hideBarArt") or false end,
                    set = function(v)
                        setSetting("hideBarArt", v)
                        syncEditModeSetting("hideBarArt")
                    end,
                })

                inner:AddToggle({
                    label = "Hide Bar Scrolling",
                    get = function() return getSetting("hideBarScrolling") or false end,
                    set = function(v)
                        setSetting("hideBarScrolling", v)
                        syncEditModeSetting("hideBarScrolling")
                    end,
                })
            end

            inner:AddSlider({
                label = "Opacity in Combat", min = 0, max = 100, step = 1,
                get = function() return getSetting("barOpacity") or 100 end,
                set = function(v) setSetting("barOpacity", v) end,
                minLabel = "Hidden", maxLabel = "100%",
                infoIcon = {
                    tooltipTitle = "Opacity Priority",
                    tooltipText = "With Target takes precedence, then In Combat, then Out of Combat. The highest priority condition that applies determines the opacity.",
                },
            })

            inner:AddSlider({
                label = "Opacity Out of Combat", min = 0, max = 100, step = 1,
                get = function() return getSetting("barOpacityOutOfCombat") or 100 end,
                set = function(v) setSetting("barOpacityOutOfCombat", v) end,
                minLabel = "Hidden", maxLabel = "100%",
            })

            inner:AddSlider({
                label = "Opacity With Target", min = 0, max = 100, step = 1,
                get = function() return getSetting("barOpacityWithTarget") or 100 end,
                set = function(v) setSetting("barOpacityWithTarget", v) end,
                minLabel = "Hidden", maxLabel = "100%",
            })

            inner:AddToggle({
                label = "Mouseover Mode",
                get = function() return getSetting("mouseoverMode") or false end,
                set = function(v) setSetting("mouseoverMode", v) end,
            })

            inner:Finalize()
        end,
    })

    builder:Finalize()
end

--------------------------------------------------------------------------------
-- Consolidated Render (Action Bars 1-8 with bar selector)
--------------------------------------------------------------------------------

function ActionBar.RenderConsolidated(panel, scrollContent)
    panel:ClearContent()

    local builder = SettingsBuilder:CreateFor(scrollContent)
    panel._currentBuilder = builder

    -- Build selector options
    local selectorValues = {}
    local selectorOrder = {}
    for i = 1, 8 do
        local key = "actionBar" .. i
        selectorValues[key] = "Action Bar " .. i
        table.insert(selectorOrder, key)
    end

    -- Add bar selector via builder (emphasized, wider, empty label)
    builder:AddSelector({
        key = "barSelector",
        label = "",
        emphasized = true,
        values = selectorValues,
        order = selectorOrder,
        width = 400,
        get = function() return ActionBar._selectedBar end,
        set = function(v)
            ActionBar._selectedBar = v
            addon.UI.SettingsPanel._actionBarSelectedBar = v
            ActionBar.RenderConsolidated(panel, scrollContent)
        end,
    })

    -- Center the selector widget (post-creation re-anchor)
    local selectorRow = builder._controls[#builder._controls]
    if selectorRow then
        -- Find the internal selector frame (the child with _border)
        local children = { selectorRow:GetChildren() }
        for _, child in ipairs(children) do
            if child._border then
                child:ClearAllPoints()
                child:SetPoint("CENTER", selectorRow, "CENTER", 0, 0)
                break
            end
        end
        -- Hide the empty label
        if selectorRow._label then
            selectorRow._label:Hide()
        end
        -- Hide emphasized accent border and background (centered control doesn't need them)
        if selectorRow._rowBorder and selectorRow._rowBorder.LEFT then
            selectorRow._rowBorder.LEFT:Hide()
        end
        if selectorRow._emphBg then
            selectorRow._emphBg:Hide()
        end
    end

    -- Store selected bar for navigation.lua (Copy From, Defaults)
    addon.UI.SettingsPanel._actionBarSelectedBar = ActionBar._selectedBar

    -- Render the selected bar's settings using the same builder
    ActionBar.Render(panel, scrollContent, ActionBar._selectedBar, {
        skipClear = true,
        builder = builder,
        onRefresh = function()
            ActionBar.RenderConsolidated(panel, scrollContent)
        end,
    })
end

--------------------------------------------------------------------------------
-- Self-register with settings panel
-- Consolidated entry for Action Bars 1-8
addon.UI.SettingsPanel:RegisterRenderer("actionBars18", function(panel, scrollContent)
    ActionBar.RenderConsolidated(panel, scrollContent)
end)

-- Pet and Stance bars keep individual registrations
for _, barKey in ipairs({"petBar", "stanceBar"}) do
    addon.UI.SettingsPanel:RegisterRenderer(barKey, function(panel, scrollContent)
        ActionBar.Render(panel, scrollContent, barKey)
    end)
end

-- Return module
--------------------------------------------------------------------------------

return ActionBar
