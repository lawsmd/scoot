-- PetRenderer.lua - Pet Unit Frame TUI renderer
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.UnitFrames = addon.UI.UnitFrames or {}
local UF = addon.UI.UnitFrames
local SettingsBuilder = addon.UI.SettingsBuilder
local Controls = addon.UI.Controls

local COMPONENT_ID = "ufPet"
local UNIT_KEY = "Pet"

--------------------------------------------------------------------------------
-- Database Access
--------------------------------------------------------------------------------

local function ensureUFDB()
    return UF.ensureUFDB(UNIT_KEY)
end

local function ensureTextDB(key)
    return UF.ensureTextDB(UNIT_KEY, key)
end

local function ensurePortraitDB()
    return UF.ensurePortraitDB(UNIT_KEY)
end

local function ensureNameLevelDB(textKey)
    local t = UF.ensureUFDB(UNIT_KEY)
    if not t then return nil end
    t[textKey] = t[textKey] or {}
    return t[textKey]
end

--------------------------------------------------------------------------------
-- Apply Functions
--------------------------------------------------------------------------------

local function applyBarTextures()
    UF.applyBarTextures(UNIT_KEY)
end

local function applyHealthText()
    UF.applyHealthText(UNIT_KEY)
end

local function applyPowerText()
    UF.applyPowerText(UNIT_KEY)
end

local function applyPortrait()
    UF.applyPortrait(UNIT_KEY)
end

local function applyScaleMult()
    UF.applyScaleMult(UNIT_KEY)
end

local function applyVisibility()
    UF.applyVisibility(UNIT_KEY)
end

local function applyStyles()
    UF.applyStyles()
end

local function applyNameLevelText()
    if addon and addon.ApplyUnitFrameNameLevelTextFor then
        addon.ApplyUnitFrameNameLevelTextFor(UNIT_KEY)
    end
    UF.applyStyles()
end

--------------------------------------------------------------------------------
-- Health Bar Tab Builders
--------------------------------------------------------------------------------

local function buildHealthStyleTab(inner)
    inner:AddDualBarStyleRow({
        label = "Foreground",
        getTexture = function()
            local t = ensureUFDB() or {}
            return t.healthBarTexture or "default"
        end,
        setTexture = function(v)
            local t = ensureUFDB()
            if not t then return end
            t.healthBarTexture = v or "default"
            applyBarTextures()
        end,
        colorValues = UF.healthColorValues,
        colorOrder = UF.healthColorOrder,
        colorInfoIcons = UF.healthColorInfoIcons,
        getColorMode = function()
            local t = ensureUFDB() or {}
            return t.healthBarColorMode or "default"
        end,
        setColorMode = function(v)
            local t = ensureUFDB()
            if not t then return end
            t.healthBarColorMode = v or "default"
            applyBarTextures()
        end,
        getColor = function()
            local t = ensureUFDB() or {}
            local c = t.healthBarTint or {1, 1, 1, 1}
            return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
        end,
        setColor = function(r, g, b, a)
            local t = ensureUFDB()
            if not t then return end
            t.healthBarTint = {r or 1, g or 1, b or 1, a or 1}
            applyBarTextures()
        end,
        customColorValue = "custom",
        hasAlpha = true,
    })

    inner:AddSpacer(8)

    inner:AddDualBarStyleRow({
        label = "Background",
        getTexture = function()
            local t = ensureUFDB() or {}
            return t.healthBarBackgroundTexture or "default"
        end,
        setTexture = function(v)
            local t = ensureUFDB()
            if not t then return end
            t.healthBarBackgroundTexture = v or "default"
            applyBarTextures()
        end,
        colorValues = UF.bgColorValues,
        colorOrder = UF.bgColorOrder,
        getColorMode = function()
            local t = ensureUFDB() or {}
            return t.healthBarBackgroundColorMode or "default"
        end,
        setColorMode = function(v)
            local t = ensureUFDB()
            if not t then return end
            t.healthBarBackgroundColorMode = v or "default"
            applyBarTextures()
        end,
        getColor = function()
            local t = ensureUFDB() or {}
            local c = t.healthBarBackgroundTint or {0, 0, 0, 1}
            return c[1] or 0, c[2] or 0, c[3] or 0, c[4] or 1
        end,
        setColor = function(r, g, b, a)
            local t = ensureUFDB()
            if not t then return end
            t.healthBarBackgroundTint = {r or 0, g or 0, b or 0, a or 1}
            applyBarTextures()
        end,
        customColorValue = "custom",
        hasAlpha = true,
    })

    inner:AddSlider({
        label = "Background Opacity",
        min = 0,
        max = 100,
        step = 1,
        get = function()
            local t = ensureUFDB() or {}
            return tonumber(t.healthBarBackgroundOpacity) or 50
        end,
        set = function(v)
            local t = ensureUFDB()
            if not t then return end
            t.healthBarBackgroundOpacity = tonumber(v) or 50
            applyBarTextures()
        end,
    })

    inner:Finalize()
end

local function buildHealthBorderTab(inner)
    local function isEnabled()
        local t = ensureUFDB() or {}
        return not not t.useCustomBorders
    end

    inner:AddBarBorderSelector({
        label = "Border Style",
        includeNone = true,
        get = function()
            local t = ensureUFDB() or {}
            return t.healthBarBorderStyle or "square"
        end,
        set = function(v)
            local t = ensureUFDB()
            if not t then return end
            t.healthBarBorderStyle = v or "square"
            applyBarTextures()
        end,
    })

    inner:AddToggleColorPicker({
        label = "Border Tint",
        get = function()
            local t = ensureUFDB() or {}
            return not not t.healthBarBorderTintEnable
        end,
        set = function(v)
            local t = ensureUFDB()
            if not t then return end
            t.healthBarBorderTintEnable = not not v
            applyBarTextures()
        end,
        getColor = function()
            local t = ensureUFDB() or {}
            local c = t.healthBarBorderTintColor or {1, 1, 1, 1}
            return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
        end,
        setColor = function(r, g, b, a)
            local t = ensureUFDB()
            if not t then return end
            t.healthBarBorderTintColor = {r or 1, g or 1, b or 1, a or 1}
            applyBarTextures()
        end,
        hasAlpha = true,
    })

    inner:AddSlider({
        label = "Border Thickness",
        min = 1,
        max = 8,
        step = 0.5,
        precision = 1,
        get = function()
            local t = ensureUFDB() or {}
            local v = tonumber(t.healthBarBorderThickness) or 1
            return math.max(1, math.min(8, math.floor(v * 2 + 0.5) / 2))
        end,
        set = function(v)
            local t = ensureUFDB()
            if not t then return end
            t.healthBarBorderThickness = math.max(1, math.min(8, math.floor((tonumber(v) or 1) * 2 + 0.5) / 2))
            applyBarTextures()
        end,
    })

    inner:AddDualSlider({
        label = "Border Inset",
        sliderA = {
            axisLabel = "H", min = -4, max = 4, step = 1,
            get = function()
                local t = ensureUFDB() or {}
                return tonumber(t.healthBarBorderInsetH) or tonumber(t.healthBarBorderInset) or 0
            end,
            set = function(v)
                local t = ensureUFDB()
                if not t then return end
                t.healthBarBorderInsetH = tonumber(v) or 0
                applyBarTextures()
            end,
            minLabel = "-4", maxLabel = "+4",
        },
        sliderB = {
            axisLabel = "V", min = -4, max = 4, step = 1,
            get = function()
                local t = ensureUFDB() or {}
                return tonumber(t.healthBarBorderInsetV) or tonumber(t.healthBarBorderInset) or 0
            end,
            set = function(v)
                local t = ensureUFDB()
                if not t then return end
                t.healthBarBorderInsetV = tonumber(v) or 0
                applyBarTextures()
            end,
            minLabel = "-4", maxLabel = "+4",
        },
    })

    inner:Finalize()
end

local function buildHealthPercentTextTab(inner)
    inner:AddToggle({
        label = "Disable % Text",
        get = function()
            local t = ensureUFDB() or {}
            return not not t.healthPercentHidden
        end,
        set = function(v)
            local t = ensureUFDB()
            if not t then return end
            t.healthPercentHidden = v and true or false
            applyHealthText()
        end,
    })

    inner:AddFontSelector({
        label = "% Text Font",
        get = function()
            local s = ensureTextDB("textHealthPercent") or {}
            return s.fontFace or "FRIZQT__"
        end,
        set = function(v)
            local t = ensureUFDB()
            if not t then return end
            t.textHealthPercent = t.textHealthPercent or {}
            t.textHealthPercent.fontFace = v
            applyStyles()
        end,
    })

    inner:AddSelector({
        label = "% Text Style",
        values = UF.fontStyleValues,
        order = UF.fontStyleOrder,
        get = function()
            local s = ensureTextDB("textHealthPercent") or {}
            return s.style or "OUTLINE"
        end,
        set = function(v)
            local t = ensureUFDB()
            if not t then return end
            t.textHealthPercent = t.textHealthPercent or {}
            t.textHealthPercent.style = v
            applyStyles()
        end,
    })

    inner:AddSlider({
        label = "% Text Size",
        min = 6,
        max = 48,
        step = 1,
        get = function()
            local s = ensureTextDB("textHealthPercent") or {}
            return tonumber(s.size) or 14
        end,
        set = function(v)
            local t = ensureUFDB()
            if not t then return end
            t.textHealthPercent = t.textHealthPercent or {}
            t.textHealthPercent.size = tonumber(v) or 14
            applyStyles()
        end,
    })

    inner:AddSelectorColorPicker({
        label = "% Text Color",
        values = UF.fontColorValues,
        order = UF.fontColorOrder,
        get = function()
            local s = ensureTextDB("textHealthPercent") or {}
            return s.colorMode or "default"
        end,
        set = function(v)
            local t = ensureUFDB()
            if not t then return end
            t.textHealthPercent = t.textHealthPercent or {}
            t.textHealthPercent.colorMode = v or "default"
            applyStyles()
        end,
        getColor = function()
            local s = ensureTextDB("textHealthPercent") or {}
            local c = s.color or {1, 1, 1, 1}
            return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
        end,
        setColor = function(r, g, b, a)
            local t = ensureUFDB()
            if not t then return end
            t.textHealthPercent = t.textHealthPercent or {}
            t.textHealthPercent.color = {r or 1, g or 1, b or 1, a or 1}
            applyStyles()
        end,
        customValue = "custom",
        hasAlpha = true,
    })

    inner:AddSelector({
        label = "% Text Alignment",
        values = UF.alignmentValues,
        order = UF.alignmentOrder,
        get = function()
            local s = ensureTextDB("textHealthPercent") or {}
            return s.alignment or "LEFT"
        end,
        set = function(v)
            local t = ensureUFDB()
            if not t then return end
            t.textHealthPercent = t.textHealthPercent or {}
            t.textHealthPercent.alignment = v or "LEFT"
            applyStyles()
        end,
    })

    inner:AddDualSlider({
        label = "% Text Offset",
        sliderA = {
            axisLabel = "X",
            min = -100, max = 100, step = 1,
            get = function()
                local s = ensureTextDB("textHealthPercent") or {}
                local o = s.offset or {}
                return tonumber(o.x) or 0
            end,
            set = function(v)
                local t = ensureUFDB()
                if not t then return end
                t.textHealthPercent = t.textHealthPercent or {}
                t.textHealthPercent.offset = t.textHealthPercent.offset or {}
                t.textHealthPercent.offset.x = tonumber(v) or 0
                applyStyles()
            end,
        },
        sliderB = {
            axisLabel = "Y",
            min = -100, max = 100, step = 1,
            get = function()
                local s = ensureTextDB("textHealthPercent") or {}
                local o = s.offset or {}
                return tonumber(o.y) or 0
            end,
            set = function(v)
                local t = ensureUFDB()
                if not t then return end
                t.textHealthPercent = t.textHealthPercent or {}
                t.textHealthPercent.offset = t.textHealthPercent.offset or {}
                t.textHealthPercent.offset.y = tonumber(v) or 0
                applyStyles()
            end,
        },
    })

    inner:Finalize()
end

local function buildHealthValueTextTab(inner)
    inner:AddToggle({
        label = "Disable Value Text",
        get = function()
            local t = ensureUFDB() or {}
            return not not t.healthValueHidden
        end,
        set = function(v)
            local t = ensureUFDB()
            if not t then return end
            t.healthValueHidden = v and true or false
            applyHealthText()
        end,
    })

    inner:AddFontSelector({
        label = "Value Text Font",
        get = function()
            local s = ensureTextDB("textHealthValue") or {}
            return s.fontFace or "FRIZQT__"
        end,
        set = function(v)
            local t = ensureUFDB()
            if not t then return end
            t.textHealthValue = t.textHealthValue or {}
            t.textHealthValue.fontFace = v
            applyStyles()
        end,
    })

    inner:AddSelector({
        label = "Value Text Style",
        values = UF.fontStyleValues,
        order = UF.fontStyleOrder,
        get = function()
            local s = ensureTextDB("textHealthValue") or {}
            return s.style or "OUTLINE"
        end,
        set = function(v)
            local t = ensureUFDB()
            if not t then return end
            t.textHealthValue = t.textHealthValue or {}
            t.textHealthValue.style = v
            applyStyles()
        end,
    })

    inner:AddSlider({
        label = "Value Text Size",
        min = 6,
        max = 48,
        step = 1,
        get = function()
            local s = ensureTextDB("textHealthValue") or {}
            return tonumber(s.size) or 14
        end,
        set = function(v)
            local t = ensureUFDB()
            if not t then return end
            t.textHealthValue = t.textHealthValue or {}
            t.textHealthValue.size = tonumber(v) or 14
            applyStyles()
        end,
    })

    inner:AddSelectorColorPicker({
        label = "Value Text Color",
        values = UF.fontColorValues,
        order = UF.fontColorOrder,
        get = function()
            local s = ensureTextDB("textHealthValue") or {}
            return s.colorMode or "default"
        end,
        set = function(v)
            local t = ensureUFDB()
            if not t then return end
            t.textHealthValue = t.textHealthValue or {}
            t.textHealthValue.colorMode = v or "default"
            applyStyles()
        end,
        getColor = function()
            local s = ensureTextDB("textHealthValue") or {}
            local c = s.color or {1, 1, 1, 1}
            return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
        end,
        setColor = function(r, g, b, a)
            local t = ensureUFDB()
            if not t then return end
            t.textHealthValue = t.textHealthValue or {}
            t.textHealthValue.color = {r or 1, g or 1, b or 1, a or 1}
            applyStyles()
        end,
        customValue = "custom",
        hasAlpha = true,
    })

    inner:AddSelector({
        label = "Value Text Alignment",
        values = UF.alignmentValues,
        order = UF.alignmentOrder,
        get = function()
            local s = ensureTextDB("textHealthValue") or {}
            return s.alignment or "RIGHT"
        end,
        set = function(v)
            local t = ensureUFDB()
            if not t then return end
            t.textHealthValue = t.textHealthValue or {}
            t.textHealthValue.alignment = v or "RIGHT"
            applyStyles()
        end,
    })

    inner:AddDualSlider({
        label = "Value Text Offset",
        sliderA = {
            axisLabel = "X",
            min = -100, max = 100, step = 1,
            get = function()
                local s = ensureTextDB("textHealthValue") or {}
                local o = s.offset or {}
                return tonumber(o.x) or 0
            end,
            set = function(v)
                local t = ensureUFDB()
                if not t then return end
                t.textHealthValue = t.textHealthValue or {}
                t.textHealthValue.offset = t.textHealthValue.offset or {}
                t.textHealthValue.offset.x = tonumber(v) or 0
                applyStyles()
            end,
        },
        sliderB = {
            axisLabel = "Y",
            min = -100, max = 100, step = 1,
            get = function()
                local s = ensureTextDB("textHealthValue") or {}
                local o = s.offset or {}
                return tonumber(o.y) or 0
            end,
            set = function(v)
                local t = ensureUFDB()
                if not t then return end
                t.textHealthValue = t.textHealthValue or {}
                t.textHealthValue.offset = t.textHealthValue.offset or {}
                t.textHealthValue.offset.y = tonumber(v) or 0
                applyStyles()
            end,
        },
    })

    inner:Finalize()
end

--------------------------------------------------------------------------------
-- Renderer Function
--------------------------------------------------------------------------------

function UF.RenderPet(panel, scrollContent)
    panel:ClearContent()

    local builder = SettingsBuilder:CreateFor(scrollContent)
    panel._currentBuilder = builder

    builder:SetOnRefresh(function()
        UF.RenderPet(panel, scrollContent)
    end)

    --------------------------------------------------------------------------------
    -- Parent-Level Settings (no X/Y Position - handled by Edit Mode)
    --------------------------------------------------------------------------------

    builder:AddToggle({
        label = "Hide Blizzard Frame Art & Animations",
        description = "REQUIRED for custom borders. Hides default frame art.",
        emphasized = true,
        get = function()
            local t = ensureUFDB() or {}
            return not not t.useCustomBorders
        end,
        set = function(v)
            local t = ensureUFDB()
            if not t then return end
            t.useCustomBorders = not not v
            if not v then t.healthBarHideBorder = false end
            applyBarTextures()
        end,
        infoIcon = UF.TOOLTIPS.hideBlizzardArt,
    })

    builder:AddSlider({
        label = "Frame Size (Scale)",
        description = "Blizzard's Edit Mode scale (100-200%).",
        min = 100,
        max = 200,
        step = 5,
        get = function()
            return UF.getEditModeFrameSize(COMPONENT_ID)
        end,
        set = function(v)
            UF.setEditModeFrameSize(COMPONENT_ID, v)
        end,
        minLabel = "100%",
        maxLabel = "200%",
        infoIcon = UF.TOOLTIPS.frameSize,
    })

    builder:AddSlider({
        label = "Scale Multiplier",
        description = "Addon multiplier on top of Edit Mode scale.",
        min = 1.0,
        max = 2.0,
        step = 0.05,
        precision = 2,
        get = function()
            local t = ensureUFDB() or {}
            return tonumber(t.scaleMult) or 1.0
        end,
        set = function(v)
            local t = ensureUFDB()
            if not t then return end
            t.scaleMult = tonumber(v) or 1.0
            applyScaleMult()
        end,
        minLabel = "1.0x",
        maxLabel = "2.0x",
        infoIcon = UF.TOOLTIPS.scaleMult,
    })

    --------------------------------------------------------------------------------
    -- Collapsible Section: Health Bar
    --------------------------------------------------------------------------------

    local healthTabs = UF.getHealthBarTabs(COMPONENT_ID)

    builder:AddCollapsibleSection({
        title = "Health Bar",
        componentId = COMPONENT_ID,
        sectionKey = "healthBar",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddTabbedSection({
                tabs = healthTabs,
                componentId = COMPONENT_ID,
                sectionKey = "healthBar_tabs",
                buildContent = {
                    style = function(cf, tabInner) buildHealthStyleTab(tabInner) end,
                    border = function(cf, tabInner) buildHealthBorderTab(tabInner) end,
                    percentText = function(cf, tabInner) buildHealthPercentTextTab(tabInner) end,
                    valueText = function(cf, tabInner) buildHealthValueTextTab(tabInner) end,
                },
            })
            inner:Finalize()
        end,
    })

    --------------------------------------------------------------------------------
    -- Collapsible Section: Power Bar (7 tabs)
    --------------------------------------------------------------------------------

    local powerTabs = UF.getPowerBarTabs()

    builder:AddCollapsibleSection({
        title = "Power Bar",
        componentId = COMPONENT_ID,
        sectionKey = "powerBar",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddTabbedSection({
                tabs = powerTabs,
                componentId = COMPONENT_ID,
                sectionKey = "powerBar_tabs",
                buildContent = {
                    positioning = function(cf, tabInner)
                        tabInner:AddDualSlider({
                            label = "Offset",
                            sliderA = {
                                axisLabel = "X",
                                min = -100, max = 100, step = 1,
                                get = function() local t = ensureUFDB() or {}; return tonumber(t.powerBarOffsetX) or 0 end,
                                set = function(v) local t = ensureUFDB(); if t then t.powerBarOffsetX = tonumber(v) or 0; applyBarTextures() end end,
                            },
                            sliderB = {
                                axisLabel = "Y",
                                min = -100, max = 100, step = 1,
                                get = function() local t = ensureUFDB() or {}; return tonumber(t.powerBarOffsetY) or 0 end,
                                set = function(v) local t = ensureUFDB(); if t then t.powerBarOffsetY = tonumber(v) or 0; applyBarTextures() end end,
                            },
                        })
                        tabInner:Finalize()
                    end,
                    sizing = function(cf, tabInner)
                        tabInner:AddSlider({ label = "Height %", min = 10, max = 200, step = 5,
                            get = function() local t = ensureUFDB() or {}; return tonumber(t.powerBarHeightPct) or 100 end,
                            set = function(v) local t = ensureUFDB(); if t then t.powerBarHeightPct = tonumber(v) or 100; applyBarTextures() end end })
                        tabInner:Finalize()
                    end,
                    style = function(cf, tabInner)
                        tabInner:AddBarTextureSelector({ label = "Foreground Texture",
                            get = function() local t = ensureUFDB() or {}; return t.powerBarTexture or "default" end,
                            set = function(v) local t = ensureUFDB(); if t then t.powerBarTexture = v or "default"; applyBarTextures() end end })
                        tabInner:AddSelectorColorPicker({ label = "Foreground Color", values = UF.powerColorValues, order = UF.powerColorOrder,
                            get = function() local t = ensureUFDB() or {}; return t.powerBarColorMode or "default" end,
                            set = function(v) local t = ensureUFDB(); if t then t.powerBarColorMode = v or "default"; applyBarTextures() end end,
                            getColor = function() local t = ensureUFDB() or {}; local c = t.powerBarTint or {1,1,1,1}; return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 end,
                            setColor = function(r,g,b,a) local t = ensureUFDB(); if t then t.powerBarTint = {r,g,b,a}; applyBarTextures() end end,
                            customValue = "custom", hasAlpha = true })
                        tabInner:AddSpacer(8)
                        tabInner:AddBarTextureSelector({ label = "Background Texture",
                            get = function() local t = ensureUFDB() or {}; return t.powerBarBackgroundTexture or "default" end,
                            set = function(v) local t = ensureUFDB(); if t then t.powerBarBackgroundTexture = v or "default"; applyBarTextures() end end })
                        tabInner:AddSelectorColorPicker({ label = "Background Color", values = UF.bgColorValues, order = UF.bgColorOrder,
                            get = function() local t = ensureUFDB() or {}; return t.powerBarBackgroundColorMode or "default" end,
                            set = function(v) local t = ensureUFDB(); if t then t.powerBarBackgroundColorMode = v or "default"; applyBarTextures() end end,
                            getColor = function() local t = ensureUFDB() or {}; local c = t.powerBarBackgroundTint or {0,0,0,1}; return c[1] or 0, c[2] or 0, c[3] or 0, c[4] or 1 end,
                            setColor = function(r,g,b,a) local t = ensureUFDB(); if t then t.powerBarBackgroundTint = {r,g,b,a}; applyBarTextures() end end,
                            customValue = "custom", hasAlpha = true })
                        tabInner:AddSlider({ label = "Background Opacity", min = 0, max = 100, step = 1,
                            get = function() local t = ensureUFDB() or {}; return tonumber(t.powerBarBackgroundOpacity) or 50 end,
                            set = function(v) local t = ensureUFDB(); if t then t.powerBarBackgroundOpacity = tonumber(v) or 50; applyBarTextures() end end })
                        tabInner:Finalize()
                    end,
                    border = function(cf, tabInner)
                        tabInner:AddBarBorderSelector({ label = "Border Style", includeNone = true,
                            get = function() local t = ensureUFDB() or {}; return t.powerBarBorderStyle or "square" end,
                            set = function(v) local t = ensureUFDB(); if t then t.powerBarBorderStyle = v or "square"; applyBarTextures() end end })
                        tabInner:AddToggleColorPicker({ label = "Border Tint",
                            get = function() local t = ensureUFDB() or {}; return not not t.powerBarBorderTintEnable end,
                            set = function(v) local t = ensureUFDB(); if t then t.powerBarBorderTintEnable = not not v; applyBarTextures() end end,
                            getColor = function() local t = ensureUFDB() or {}; local c = t.powerBarBorderTintColor or {1,1,1,1}; return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 end,
                            setColor = function(r,g,b,a) local t = ensureUFDB(); if t then t.powerBarBorderTintColor = {r,g,b,a}; applyBarTextures() end end,
                            hasAlpha = true })
                        tabInner:AddSlider({ label = "Border Thickness", min = 1, max = 8, step = 0.5, precision = 1,
                            get = function() local t = ensureUFDB() or {}; local v = tonumber(t.powerBarBorderThickness) or 1; return math.max(1, math.min(8, math.floor(v * 2 + 0.5) / 2)) end,
                            set = function(v) local t = ensureUFDB(); if t then t.powerBarBorderThickness = math.max(1, math.min(8, math.floor((tonumber(v) or 1) * 2 + 0.5) / 2)); applyBarTextures() end end })
                        tabInner:AddDualSlider({ label = "Border Inset",
                            sliderA = {
                                axisLabel = "H", min = -4, max = 4, step = 1,
                                get = function() local t = ensureUFDB() or {}; return tonumber(t.powerBarBorderInsetH) or tonumber(t.powerBarBorderInset) or 0 end,
                                set = function(v) local t = ensureUFDB(); if t then t.powerBarBorderInsetH = tonumber(v) or 0; applyBarTextures() end end,
                                minLabel = "-4", maxLabel = "+4",
                            },
                            sliderB = {
                                axisLabel = "V", min = -4, max = 4, step = 1,
                                get = function() local t = ensureUFDB() or {}; return tonumber(t.powerBarBorderInsetV) or tonumber(t.powerBarBorderInset) or 0 end,
                                set = function(v) local t = ensureUFDB(); if t then t.powerBarBorderInsetV = tonumber(v) or 0; applyBarTextures() end end,
                                minLabel = "-4", maxLabel = "+4",
                            },
                        })
                        tabInner:Finalize()
                    end,
                    visibility = function(cf, tabInner)
                        tabInner:AddToggle({ label = "Hide Power Bar",
                            get = function() local t = ensureUFDB() or {}; return not not t.powerBarHidden end,
                            set = function(v) local t = ensureUFDB(); if t then t.powerBarHidden = v and true or false; applyBarTextures() end end })
                        tabInner:Finalize()
                    end,
                    percentText = function(cf, tabInner)
                        tabInner:AddToggle({ label = "Disable % Text",
                            get = function() local t = ensureUFDB() or {}; return not not t.powerPercentHidden end,
                            set = function(v) local t = ensureUFDB(); if t then t.powerPercentHidden = v and true or false; applyPowerText() end end })
                        tabInner:AddFontSelector({ label = "% Text Font",
                            get = function() local s = ensureTextDB("textPowerPercent") or {}; return s.fontFace or "FRIZQT__" end,
                            set = function(v) local t = ensureUFDB(); if t then t.textPowerPercent = t.textPowerPercent or {}; t.textPowerPercent.fontFace = v; applyStyles() end end })
                        tabInner:AddSelector({ label = "% Text Style", values = UF.fontStyleValues, order = UF.fontStyleOrder,
                            get = function() local s = ensureTextDB("textPowerPercent") or {}; return s.style or "OUTLINE" end,
                            set = function(v) local t = ensureUFDB(); if t then t.textPowerPercent = t.textPowerPercent or {}; t.textPowerPercent.style = v; applyStyles() end end })
                        tabInner:AddSlider({ label = "% Text Size", min = 6, max = 48, step = 1,
                            get = function() local s = ensureTextDB("textPowerPercent") or {}; return tonumber(s.size) or 14 end,
                            set = function(v) local t = ensureUFDB(); if t then t.textPowerPercent = t.textPowerPercent or {}; t.textPowerPercent.size = tonumber(v) or 14; applyStyles() end end })
                        tabInner:AddSelectorColorPicker({ label = "% Text Color",
                            values = UF.fontColorValues, order = UF.fontColorOrder,
                            get = function() local s = ensureTextDB("textPowerPercent") or {}; return s.colorMode or "default" end,
                            set = function(v) local t = ensureUFDB(); if t then t.textPowerPercent = t.textPowerPercent or {}; t.textPowerPercent.colorMode = v or "default"; applyStyles() end end,
                            getColor = function() local s = ensureTextDB("textPowerPercent") or {}; local c = s.color or {1,1,1,1}; return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 end,
                            setColor = function(r,g,b,a) local t = ensureUFDB(); if t then t.textPowerPercent = t.textPowerPercent or {}; t.textPowerPercent.color = {r,g,b,a}; applyStyles() end end,
                            customValue = "custom", hasAlpha = true })
                        tabInner:Finalize()
                    end,
                    valueText = function(cf, tabInner)
                        tabInner:AddToggle({ label = "Disable Value Text",
                            get = function() local t = ensureUFDB() or {}; return not not t.powerValueHidden end,
                            set = function(v) local t = ensureUFDB(); if t then t.powerValueHidden = v and true or false; applyPowerText() end end })
                        tabInner:AddFontSelector({ label = "Value Text Font",
                            get = function() local s = ensureTextDB("textPowerValue") or {}; return s.fontFace or "FRIZQT__" end,
                            set = function(v) local t = ensureUFDB(); if t then t.textPowerValue = t.textPowerValue or {}; t.textPowerValue.fontFace = v; applyStyles() end end })
                        tabInner:AddSelector({ label = "Value Text Style", values = UF.fontStyleValues, order = UF.fontStyleOrder,
                            get = function() local s = ensureTextDB("textPowerValue") or {}; return s.style or "OUTLINE" end,
                            set = function(v) local t = ensureUFDB(); if t then t.textPowerValue = t.textPowerValue or {}; t.textPowerValue.style = v; applyStyles() end end })
                        tabInner:AddSlider({ label = "Value Text Size", min = 6, max = 48, step = 1,
                            get = function() local s = ensureTextDB("textPowerValue") or {}; return tonumber(s.size) or 14 end,
                            set = function(v) local t = ensureUFDB(); if t then t.textPowerValue = t.textPowerValue or {}; t.textPowerValue.size = tonumber(v) or 14; applyStyles() end end })
                        tabInner:AddSelectorColorPicker({ label = "Value Text Color",
                            values = UF.fontColorValues, order = UF.fontColorOrder,
                            get = function() local s = ensureTextDB("textPowerValue") or {}; return s.colorMode or "default" end,
                            set = function(v) local t = ensureUFDB(); if t then t.textPowerValue = t.textPowerValue or {}; t.textPowerValue.colorMode = v or "default"; applyStyles() end end,
                            getColor = function() local s = ensureTextDB("textPowerValue") or {}; local c = s.color or {1,1,1,1}; return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 end,
                            setColor = function(r,g,b,a) local t = ensureUFDB(); if t then t.textPowerValue = t.textPowerValue or {}; t.textPowerValue.color = {r,g,b,a}; applyStyles() end end,
                            customValue = "custom", hasAlpha = true })
                        tabInner:Finalize()
                    end,
                },
            })
            inner:Finalize()
        end,
    })

    --------------------------------------------------------------------------------
    -- Collapsible Section: Name & Level Text
    --------------------------------------------------------------------------------

    builder:AddCollapsibleSection({
        title = "Name & Level Text",
        componentId = COMPONENT_ID,
        sectionKey = "nameLevelText",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddTabbedSection({
                tabs = {
                    { key = "backdrop", label = "Backdrop" },
                    { key = "border", label = "Border" },
                    { key = "nameText", label = "Name Text" },
                    { key = "levelText", label = "Level Text" },
                },
                componentId = COMPONENT_ID,
                sectionKey = "nameLevelText_tabs",
                buildContent = {
                    backdrop = function(cf, tabInner)
                        tabInner:AddToggle({ label = "Enable Backdrop",
                            get = function() local t = ensureUFDB() or {}; return not not t.nameBackdropEnabled end,
                            set = function(v) local t = ensureUFDB(); if t then t.nameBackdropEnabled = not not v; applyNameLevelText() end end })
                        tabInner:AddBarTextureSelector({ label = "Backdrop Texture",
                            get = function() local t = ensureUFDB() or {}; return t.nameBackdropTexture or "" end,
                            set = function(v) local t = ensureUFDB(); if t then t.nameBackdropTexture = v; applyNameLevelText() end end })
                        tabInner:AddSelectorColorPicker({ label = "Backdrop Color", values = UF.bgColorValues, order = UF.bgColorOrder,
                            get = function() local t = ensureUFDB() or {}; return t.nameBackdropColorMode or "default" end,
                            set = function(v) local t = ensureUFDB(); if t then t.nameBackdropColorMode = v or "default"; applyNameLevelText() end end,
                            getColor = function() local t = ensureUFDB() or {}; local c = t.nameBackdropTint or {1,1,1,1}; return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 end,
                            setColor = function(r,g,b,a) local t = ensureUFDB(); if t then t.nameBackdropTint = {r,g,b,a}; applyNameLevelText() end end,
                            customValue = "custom", hasAlpha = true })
                        tabInner:AddSlider({ label = "Backdrop Width (%)", min = 25, max = 300, step = 1,
                            get = function() local t = ensureUFDB() or {}; return tonumber(t.nameBackdropWidthPct) or 100 end,
                            set = function(v) local t = ensureUFDB(); if t then t.nameBackdropWidthPct = tonumber(v) or 100; applyNameLevelText() end end })
                        tabInner:AddSlider({ label = "Backdrop Opacity", min = 0, max = 100, step = 1,
                            get = function() local t = ensureUFDB() or {}; return tonumber(t.nameBackdropOpacity) or 50 end,
                            set = function(v) local t = ensureUFDB(); if t then t.nameBackdropOpacity = tonumber(v) or 50; applyNameLevelText() end end })
                        tabInner:Finalize()
                    end,
                    border = function(cf, tabInner)
                        tabInner:AddToggle({ label = "Enable Border",
                            get = function() local t = ensureUFDB() or {}; return not not t.nameBackdropBorderEnabled end,
                            set = function(v) local t = ensureUFDB(); if t then t.nameBackdropBorderEnabled = not not v; applyNameLevelText() end end })
                        local borderValues, borderOrder = UF.buildBarBorderOptions()
                        tabInner:AddSelector({ label = "Border Style", values = borderValues, order = borderOrder,
                            get = function() local t = ensureUFDB() or {}; return t.nameBackdropBorderStyle or "square" end,
                            set = function(v) local t = ensureUFDB(); if t then t.nameBackdropBorderStyle = v or "square"; applyNameLevelText() end end })
                        tabInner:AddToggleColorPicker({ label = "Border Tint",
                            get = function() local t = ensureUFDB() or {}; return not not t.nameBackdropBorderTintEnable end,
                            set = function(v) local t = ensureUFDB(); if t then t.nameBackdropBorderTintEnable = not not v; applyNameLevelText() end end,
                            getColor = function() local t = ensureUFDB() or {}; local c = t.nameBackdropBorderTintColor or {1,1,1,1}; return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 end,
                            setColor = function(r,g,b,a) local t = ensureUFDB(); if t then t.nameBackdropBorderTintColor = {r,g,b,a}; applyNameLevelText() end end,
                            hasAlpha = true })
                        tabInner:AddSlider({ label = "Border Thickness", min = 1, max = 8, step = 0.5, precision = 1,
                            get = function() local t = ensureUFDB() or {}; local v = tonumber(t.nameBackdropBorderThickness) or 1; return math.max(1, math.min(8, math.floor(v * 2 + 0.5) / 2)) end,
                            set = function(v) local t = ensureUFDB(); if t then t.nameBackdropBorderThickness = math.max(1, math.min(8, math.floor((tonumber(v) or 1) * 2 + 0.5) / 2)); applyNameLevelText() end end })
                        tabInner:AddDualSlider({ label = "Border Inset",
                            sliderA = {
                                axisLabel = "H", min = -4, max = 4, step = 1,
                                get = function() local t = ensureUFDB() or {}; return tonumber(t.nameBackdropBorderInsetH) or tonumber(t.nameBackdropBorderInset) or 0 end,
                                set = function(v) local t = ensureUFDB(); if t then t.nameBackdropBorderInsetH = tonumber(v) or 0; applyNameLevelText() end end,
                                minLabel = "-4", maxLabel = "+4",
                            },
                            sliderB = {
                                axisLabel = "V", min = -4, max = 4, step = 1,
                                get = function() local t = ensureUFDB() or {}; return tonumber(t.nameBackdropBorderInsetV) or tonumber(t.nameBackdropBorderInset) or 0 end,
                                set = function(v) local t = ensureUFDB(); if t then t.nameBackdropBorderInsetV = tonumber(v) or 0; applyNameLevelText() end end,
                                minLabel = "-4", maxLabel = "+4",
                            },
                        })
                        tabInner:Finalize()
                    end,
                    nameText = function(cf, tabInner)
                        tabInner:AddToggle({ label = "Disable Name Text",
                            get = function() local t = ensureUFDB() or {}; return not not t.nameTextHidden end,
                            set = function(v) local t = ensureUFDB(); if t then t.nameTextHidden = v and true or false; applyNameLevelText() end end })
                        tabInner:AddFontSelector({ label = "Name Text Font",
                            get = function() local s = ensureNameLevelDB("textName") or {}; return s.fontFace or "FRIZQT__" end,
                            set = function(v) local t = ensureNameLevelDB("textName"); if t then t.fontFace = v; applyNameLevelText() end end })
                        tabInner:AddSelector({ label = "Name Text Style", values = UF.fontStyleValues, order = UF.fontStyleOrder,
                            get = function() local s = ensureNameLevelDB("textName") or {}; return s.style or "OUTLINE" end,
                            set = function(v) local t = ensureNameLevelDB("textName"); if t then t.style = v; applyNameLevelText() end end })
                        tabInner:AddSlider({ label = "Name Text Size", min = 6, max = 48, step = 1,
                            get = function() local s = ensureNameLevelDB("textName") or {}; return tonumber(s.size) or 14 end,
                            set = function(v) local t = ensureNameLevelDB("textName"); if t then t.size = tonumber(v) or 14; applyNameLevelText() end end })
                        tabInner:AddSelectorColorPicker({ label = "Name Text Color",
                            values = { default = "Default", custom = "Custom" }, order = { "default", "custom" },
                            get = function() local s = ensureNameLevelDB("textName") or {}; return s.colorMode or "default" end,
                            set = function(v) local t = ensureNameLevelDB("textName"); if t then t.colorMode = v or "default"; applyNameLevelText() end end,
                            getColor = function() local s = ensureNameLevelDB("textName") or {}; local c = s.color or {1,0.82,0,1}; return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 end,
                            setColor = function(r,g,b,a) local t = ensureNameLevelDB("textName"); if t then t.color = {r,g,b,a}; applyNameLevelText() end end,
                            customValue = "custom", hasAlpha = true })
                        tabInner:AddDualSlider({
                            label = "Name Text Offset",
                            sliderA = {
                                axisLabel = "X",
                                min = -100, max = 100, step = 1,
                                get = function() local s = ensureNameLevelDB("textName") or {}; local o = s.offset or {}; return tonumber(o.x) or 0 end,
                                set = function(v) local t = ensureNameLevelDB("textName"); if t then t.offset = t.offset or {}; t.offset.x = tonumber(v) or 0; applyNameLevelText() end end,
                            },
                            sliderB = {
                                axisLabel = "Y",
                                min = -100, max = 100, step = 1,
                                get = function() local s = ensureNameLevelDB("textName") or {}; local o = s.offset or {}; return tonumber(o.y) or 0 end,
                                set = function(v) local t = ensureNameLevelDB("textName"); if t then t.offset = t.offset or {}; t.offset.y = tonumber(v) or 0; applyNameLevelText() end end,
                            },
                        })
                        tabInner:Finalize()
                    end,
                    levelText = function(cf, tabInner)
                        tabInner:AddToggle({ label = "Disable Level Text",
                            get = function() local t = ensureUFDB() or {}; return not not t.levelTextHidden end,
                            set = function(v) local t = ensureUFDB(); if t then t.levelTextHidden = v and true or false; applyNameLevelText() end end })
                        tabInner:AddFontSelector({ label = "Level Text Font",
                            get = function() local s = ensureNameLevelDB("textLevel") or {}; return s.fontFace or "FRIZQT__" end,
                            set = function(v) local t = ensureNameLevelDB("textLevel"); if t then t.fontFace = v; applyNameLevelText() end end })
                        tabInner:AddSelector({ label = "Level Text Style", values = UF.fontStyleValues, order = UF.fontStyleOrder,
                            get = function() local s = ensureNameLevelDB("textLevel") or {}; return s.style or "OUTLINE" end,
                            set = function(v) local t = ensureNameLevelDB("textLevel"); if t then t.style = v; applyNameLevelText() end end })
                        tabInner:AddSlider({ label = "Level Text Size", min = 6, max = 48, step = 1,
                            get = function() local s = ensureNameLevelDB("textLevel") or {}; return tonumber(s.size) or 14 end,
                            set = function(v) local t = ensureNameLevelDB("textLevel"); if t then t.size = tonumber(v) or 14; applyNameLevelText() end end })
                        tabInner:AddSelectorColorPicker({ label = "Level Text Color", values = UF.fontColorValues, order = UF.fontColorOrder,
                            get = function() local s = ensureNameLevelDB("textLevel") or {}; return s.colorMode or "default" end,
                            set = function(v) local t = ensureNameLevelDB("textLevel"); if t then t.colorMode = v or "default"; applyNameLevelText() end end,
                            getColor = function() local s = ensureNameLevelDB("textLevel") or {}; local c = s.color or {1,0.82,0,1}; return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 end,
                            setColor = function(r,g,b,a) local t = ensureNameLevelDB("textLevel"); if t then t.color = {r,g,b,a}; applyNameLevelText() end end,
                            customValue = "custom", hasAlpha = true })
                        tabInner:AddDualSlider({
                            label = "Level Text Offset",
                            sliderA = {
                                axisLabel = "X",
                                min = -100, max = 100, step = 1,
                                get = function() local s = ensureNameLevelDB("textLevel") or {}; local o = s.offset or {}; return tonumber(o.x) or 0 end,
                                set = function(v) local t = ensureNameLevelDB("textLevel"); if t then t.offset = t.offset or {}; t.offset.x = tonumber(v) or 0; applyNameLevelText() end end,
                            },
                            sliderB = {
                                axisLabel = "Y",
                                min = -100, max = 100, step = 1,
                                get = function() local s = ensureNameLevelDB("textLevel") or {}; local o = s.offset or {}; return tonumber(o.y) or 0 end,
                                set = function(v) local t = ensureNameLevelDB("textLevel"); if t then t.offset = t.offset or {}; t.offset.y = tonumber(v) or 0; applyNameLevelText() end end,
                            },
                        })
                        tabInner:Finalize()
                    end,
                },
            })
            inner:Finalize()
        end,
    })

    --------------------------------------------------------------------------------
    -- Collapsible Section: Portrait
    --------------------------------------------------------------------------------

    -- Portrait tab builders
    local function buildPortraitSizingTab(inner)
        inner:AddSlider({
            label = "Portrait Size (Scale)",
            min = 50,
            max = 200,
            step = 1,
            get = function()
                local t = ensurePortraitDB() or {}
                return tonumber(t.scale) or 100
            end,
            set = function(v)
                local t = ensurePortraitDB()
                if t then t.scale = tonumber(v) or 100; applyPortrait() end
            end,
            minLabel = "50%",
            maxLabel = "200%",
        })
        inner:Finalize()
    end

    local function buildPortraitZoomTab(inner)
        inner:AddSlider({
            label = "Portrait Zoom",
            min = 100,
            max = 200,
            step = 1,
            get = function()
                local t = ensurePortraitDB() or {}
                return tonumber(t.zoom) or 100
            end,
            set = function(v)
                local t = ensurePortraitDB()
                if t then t.zoom = tonumber(v) or 100; applyPortrait() end
            end,
            minLabel = "100%",
            maxLabel = "200%",
        })
        inner:Finalize()
    end

    local function buildPortraitBorderTab(inner)
        inner:AddToggle({
            label = "Use Custom Border",
            get = function()
                local t = ensurePortraitDB() or {}
                return not not t.portraitBorderEnable
            end,
            set = function(v)
                local t = ensurePortraitDB()
                if t then t.portraitBorderEnable = not not v; applyPortrait() end
            end,
        })

        local borderStyleValues = {
            texture_c = "Circle",
            texture_s = "Circle with Corner",
            rare_c = "Rare (Circle)",
        }
        local borderStyleOrder = { "texture_c", "texture_s", "rare_c" }

        inner:AddSelector({
            label = "Border Style",
            values = borderStyleValues,
            order = borderStyleOrder,
            get = function()
                local t = ensurePortraitDB() or {}
                local current = t.portraitBorderStyle or "texture_c"
                if current == "default" then return "texture_c" end
                return current
            end,
            set = function(v)
                local t = ensurePortraitDB()
                if t then
                    t.portraitBorderStyle = v or "texture_c"
                    applyPortrait()
                end
            end,
        })

        inner:AddSlider({
            label = "Border Inset",
            min = 1,
            max = 8,
            step = 0.5,
            precision = 1,
            get = function()
                local t = ensurePortraitDB() or {}
                local v = tonumber(t.portraitBorderThickness) or 1
                return math.max(1, math.min(8, math.floor(v * 2 + 0.5) / 2))
            end,
            set = function(v)
                local t = ensurePortraitDB()
                if t then t.portraitBorderThickness = math.max(1, math.min(8, math.floor((tonumber(v) or 1) * 2 + 0.5) / 2)); applyPortrait() end
            end,
        })

        local colorModeValues = {
            texture = "Texture Original",
            class = "Class Color",
            custom = "Custom",
        }
        local colorModeOrder = { "texture", "class", "custom" }

        inner:AddSelectorColorPicker({
            label = "Border Color",
            values = colorModeValues,
            order = colorModeOrder,
            get = function()
                local t = ensurePortraitDB() or {}
                return t.portraitBorderColorMode or "texture"
            end,
            set = function(v)
                local t = ensurePortraitDB()
                if t then t.portraitBorderColorMode = v or "texture"; applyPortrait() end
            end,
            getColor = function()
                local t = ensurePortraitDB() or {}
                local c = t.portraitBorderTintColor or {1, 1, 1, 1}
                return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
            end,
            setColor = function(r, g, b, a)
                local t = ensurePortraitDB()
                if t then t.portraitBorderTintColor = {r or 1, g or 1, b or 1, a or 1}; applyPortrait() end
            end,
            customValue = "custom",
            hasAlpha = true,
        })

        inner:Finalize()
    end

    local function buildPortraitVisibilityTab(inner)
        inner:AddToggle({
            label = "Hide Portrait",
            get = function()
                local t = ensurePortraitDB() or {}
                return not not t.hidePortrait
            end,
            set = function(v)
                local t = ensurePortraitDB()
                if t then t.hidePortrait = v and true or false; applyPortrait() end
            end,
        })

        inner:AddSlider({
            label = "Portrait Opacity",
            min = 1,
            max = 100,
            step = 1,
            get = function()
                local t = ensurePortraitDB() or {}
                return tonumber(t.opacity) or 100
            end,
            set = function(v)
                local t = ensurePortraitDB()
                if t then t.opacity = tonumber(v) or 100; applyPortrait() end
            end,
        })

        inner:Finalize()
    end

    builder:AddCollapsibleSection({
        title = "Portrait",
        componentId = COMPONENT_ID,
        sectionKey = "portrait",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddTabbedSection({
                tabs = {
                    { key = "sizing", label = "Sizing" },
                    { key = "zoom", label = "Zoom" },
                    { key = "border", label = "Border" },
                    { key = "visibility", label = "Visibility" },
                },
                componentId = COMPONENT_ID,
                sectionKey = "portrait_tabs",
                buildContent = {
                    sizing = function(cf, tabInner) buildPortraitSizingTab(tabInner) end,
                    zoom = function(cf, tabInner) buildPortraitZoomTab(tabInner) end,
                    border = function(cf, tabInner) buildPortraitBorderTab(tabInner) end,
                    visibility = function(cf, tabInner) buildPortraitVisibilityTab(tabInner) end,
                },
            })
            inner:Finalize()
        end,
    })

    --------------------------------------------------------------------------------
    -- Collapsible Section: Visibility
    --------------------------------------------------------------------------------

    builder:AddCollapsibleSection({
        title = "Visibility",
        componentId = COMPONENT_ID,
        sectionKey = "visibility",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddToggle({
                label = "Hide Entire Pet Frame",
                description = "Completely hides the Pet frame. Useful for ConsolePort users who prefer the Pet Ring.",
                get = function()
                    local t = ensureUFDB() or {}
                    return t.hideEntireFrame == true
                end,
                set = function(v)
                    local t = ensureUFDB()
                    if not t then return end
                    t.hideEntireFrame = v
                    if addon.ApplyPetFrameVisibility then
                        addon.ApplyPetFrameVisibility()
                    end
                end,
            })

            -- Out of Combat Opacity
            inner:AddSlider({
                label = "Opacity - Out of Combat",
                description = "Opacity when out of combat.",
                min = 0,
                max = 100,
                step = 1,
                get = function()
                    local t = ensureUFDB() or {}
                    return tonumber(t.opacityOutOfCombat) or 100
                end,
                set = function(v)
                    local t = ensureUFDB()
                    if not t then return end
                    t.opacityOutOfCombat = tonumber(v) or 100
                    applyVisibility()
                end,
                infoIcon = UF.TOOLTIPS.visibilityPriority,
            })

            inner:AddSlider({
                label = "Opacity - In Combat",
                description = "Opacity when in combat.",
                min = 0,
                max = 100,
                step = 1,
                get = function()
                    local t = ensureUFDB() or {}
                    return tonumber(t.opacityInCombat) or 100
                end,
                set = function(v)
                    local t = ensureUFDB()
                    if not t then return end
                    t.opacityInCombat = tonumber(v) or 100
                    applyVisibility()
                end,
            })

            inner:AddSlider({
                label = "Opacity - With Target",
                description = "Opacity when you have a target.",
                min = 0,
                max = 100,
                step = 1,
                get = function()
                    local t = ensureUFDB() or {}
                    return tonumber(t.opacityWithTarget) or 100
                end,
                set = function(v)
                    local t = ensureUFDB()
                    if not t then return end
                    t.opacityWithTarget = tonumber(v) or 100
                    applyVisibility()
                end,
            })

            inner:Finalize()
        end,
    })

    --------------------------------------------------------------------------------
    -- Finalize
    --------------------------------------------------------------------------------

    builder:Finalize()
end

--------------------------------------------------------------------------------
-- Self-register with settings panel
addon.UI.SettingsPanel:RegisterRenderer("ufPet", function(panel, scrollContent)
    UF.RenderPet(panel, scrollContent)
end)

-- Return renderer for registration
--------------------------------------------------------------------------------

return UF.RenderPet
