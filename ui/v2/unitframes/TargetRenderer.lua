-- TargetRenderer.lua - Target Unit Frame TUI renderer
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.UnitFrames = addon.UI.UnitFrames or {}
local UF = addon.UI.UnitFrames
local SettingsBuilder = addon.UI.SettingsBuilder

local COMPONENT_ID = "ufTarget"
local UNIT_KEY = "Target"

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

local function ensureCastBarDB()
    return UF.ensureCastBarDB(UNIT_KEY)
end

local function ensureBuffsDebuffsDB()
    local t = UF.ensureUFDB(UNIT_KEY)
    if not t then return nil end
    t.buffsDebuffs = t.buffsDebuffs or {}
    return t.buffsDebuffs
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

local function applyScaleMult()
    UF.applyScaleMult(UNIT_KEY)
end

local function applyStyles()
    UF.applyStyles()
end

local function applyPortrait()
    UF.applyPortrait(UNIT_KEY)
end

local function applyCastBar()
    UF.applyCastBar(UNIT_KEY)
end

local function applyNameLevelText()
    if addon and addon.ApplyUnitFrameNameLevelTextFor then
        addon.ApplyUnitFrameNameLevelTextFor(UNIT_KEY)
    end
    UF.applyStyles()
end

local function applyBuffsDebuffs()
    if addon and addon.ApplyUnitFrameBuffsDebuffsFor then
        addon.ApplyUnitFrameBuffsDebuffsFor(UNIT_KEY)
    end
end

--------------------------------------------------------------------------------
-- Shared Tab Builders (reuse helpers from Player renderer pattern)
--------------------------------------------------------------------------------

local function buildStyleTab(inner, barPrefix, applyFn, colorValues, colorOrder, colorInfoIcons)
    colorValues = colorValues or UF.healthColorValues
    colorOrder = colorOrder or UF.healthColorOrder
    colorInfoIcons = colorInfoIcons or UF.healthColorInfoIcons

    inner:AddDualBarStyleRow({
        label = "Foreground",
        getTexture = function()
            local t = ensureUFDB() or {}
            return t[barPrefix .. "Texture"] or "default"
        end,
        setTexture = function(v)
            local t = ensureUFDB()
            if not t then return end
            t[barPrefix .. "Texture"] = v or "default"
            applyFn()
        end,
        colorValues = colorValues,
        colorOrder = colorOrder,
        colorInfoIcons = colorInfoIcons,
        getColorMode = function()
            local t = ensureUFDB() or {}
            return t[barPrefix .. "ColorMode"] or "default"
        end,
        setColorMode = function(v)
            local t = ensureUFDB()
            if not t then return end
            t[barPrefix .. "ColorMode"] = v or "default"
            applyFn()
        end,
        getColor = function()
            local t = ensureUFDB() or {}
            local c = t[barPrefix .. "Tint"] or {1, 1, 1, 1}
            return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
        end,
        setColor = function(r, g, b, a)
            local t = ensureUFDB()
            if not t then return end
            t[barPrefix .. "Tint"] = {r or 1, g or 1, b or 1, a or 1}
            applyFn()
        end,
        customColorValue = "custom",
        hasAlpha = true,
    })

    inner:AddSpacer(8)

    inner:AddDualBarStyleRow({
        label = "Background",
        getTexture = function()
            local t = ensureUFDB() or {}
            return t[barPrefix .. "BackgroundTexture"] or "default"
        end,
        setTexture = function(v)
            local t = ensureUFDB()
            if not t then return end
            t[barPrefix .. "BackgroundTexture"] = v or "default"
            applyFn()
        end,
        colorValues = UF.bgColorValues,
        colorOrder = UF.bgColorOrder,
        getColorMode = function()
            local t = ensureUFDB() or {}
            return t[barPrefix .. "BackgroundColorMode"] or "default"
        end,
        setColorMode = function(v)
            local t = ensureUFDB()
            if not t then return end
            t[barPrefix .. "BackgroundColorMode"] = v or "default"
            applyFn()
        end,
        getColor = function()
            local t = ensureUFDB() or {}
            local c = t[barPrefix .. "BackgroundTint"] or {0, 0, 0, 1}
            return c[1] or 0, c[2] or 0, c[3] or 0, c[4] or 1
        end,
        setColor = function(r, g, b, a)
            local t = ensureUFDB()
            if not t then return end
            t[barPrefix .. "BackgroundTint"] = {r or 0, g or 0, b or 0, a or 1}
            applyFn()
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
            return tonumber(t[barPrefix .. "BackgroundOpacity"]) or 50
        end,
        set = function(v)
            local t = ensureUFDB()
            if not t then return end
            t[barPrefix .. "BackgroundOpacity"] = tonumber(v) or 50
            applyFn()
        end,
    })

    inner:Finalize()
end

local function buildBorderTab(inner, barPrefix, applyFn)
    inner:AddBarBorderSelector({
        label = "Border Style",
        includeNone = true,
        get = function()
            local t = ensureUFDB() or {}
            return t[barPrefix .. "BorderStyle"] or "square"
        end,
        set = function(v)
            local t = ensureUFDB()
            if not t then return end
            t[barPrefix .. "BorderStyle"] = v or "square"
            applyFn()
        end,
    })

    inner:AddToggleColorPicker({
        label = "Border Tint",
        get = function()
            local t = ensureUFDB() or {}
            return not not t[barPrefix .. "BorderTintEnable"]
        end,
        set = function(v)
            local t = ensureUFDB()
            if not t then return end
            t[barPrefix .. "BorderTintEnable"] = not not v
            applyFn()
        end,
        getColor = function()
            local t = ensureUFDB() or {}
            local c = t[barPrefix .. "BorderTintColor"] or {1, 1, 1, 1}
            return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
        end,
        setColor = function(r, g, b, a)
            local t = ensureUFDB()
            if not t then return end
            t[barPrefix .. "BorderTintColor"] = {r or 1, g or 1, b or 1, a or 1}
            applyFn()
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
            local v = tonumber(t[barPrefix .. "BorderThickness"]) or 1
            return math.max(1, math.min(8, math.floor(v * 2 + 0.5) / 2))
        end,
        set = function(v)
            local t = ensureUFDB()
            if not t then return end
            t[barPrefix .. "BorderThickness"] = math.max(1, math.min(8, math.floor((tonumber(v) or 1) * 2 + 0.5) / 2))
            applyFn()
        end,
    })

    inner:AddDualSlider({
        label = "Border Inset",
        sliderA = {
            axisLabel = "H", min = -4, max = 4, step = 1,
            get = function()
                local t = ensureUFDB() or {}
                return tonumber(t[barPrefix .. "BorderInsetH"]) or tonumber(t[barPrefix .. "BorderInset"]) or 0
            end,
            set = function(v)
                local t = ensureUFDB()
                if not t then return end
                t[barPrefix .. "BorderInsetH"] = tonumber(v) or 0
                applyFn()
            end,
            minLabel = "-4", maxLabel = "+4",
        },
        sliderB = {
            axisLabel = "V", min = -4, max = 4, step = 1,
            get = function()
                local t = ensureUFDB() or {}
                return tonumber(t[barPrefix .. "BorderInsetV"]) or tonumber(t[barPrefix .. "BorderInset"]) or 0
            end,
            set = function(v)
                local t = ensureUFDB()
                if not t then return end
                t[barPrefix .. "BorderInsetV"] = tonumber(v) or 0
                applyFn()
            end,
            minLabel = "-4", maxLabel = "+4",
        },
    })

    inner:Finalize()
end

local function buildTextTab(inner, textKey, applyFn, defaultAlignment, colorValues, colorOrder)
    defaultAlignment = defaultAlignment or "LEFT"
    colorValues = colorValues or UF.fontColorValues
    colorOrder = colorOrder or UF.fontColorOrder
    local hiddenKey = textKey:gsub("text", ""):lower() .. "Hidden"

    inner:AddToggle({
        label = "Disable Text",
        get = function()
            local t = ensureUFDB() or {}
            return not not t[hiddenKey]
        end,
        set = function(v)
            local t = ensureUFDB()
            if not t then return end
            t[hiddenKey] = v and true or false
            applyFn()
        end,
    })

    inner:AddFontSelector({
        label = "Font",
        get = function()
            local s = ensureTextDB(textKey) or {}
            return s.fontFace or "FRIZQT__"
        end,
        set = function(v)
            local t = ensureUFDB()
            if not t then return end
            t[textKey] = t[textKey] or {}
            t[textKey].fontFace = v
            applyStyles()
        end,
    })

    inner:AddSelector({
        label = "Style",
        values = UF.fontStyleValues,
        order = UF.fontStyleOrder,
        get = function()
            local s = ensureTextDB(textKey) or {}
            return s.style or "OUTLINE"
        end,
        set = function(v)
            local t = ensureUFDB()
            if not t then return end
            t[textKey] = t[textKey] or {}
            t[textKey].style = v
            applyStyles()
        end,
    })

    inner:AddSlider({
        label = "Size",
        min = 6,
        max = 48,
        step = 1,
        get = function()
            local s = ensureTextDB(textKey) or {}
            return tonumber(s.size) or 14
        end,
        set = function(v)
            local t = ensureUFDB()
            if not t then return end
            t[textKey] = t[textKey] or {}
            t[textKey].size = tonumber(v) or 14
            applyStyles()
        end,
    })

    inner:AddSelectorColorPicker({
        label = "Color",
        values = colorValues,
        order = colorOrder,
        get = function()
            local s = ensureTextDB(textKey) or {}
            return s.colorMode or "default"
        end,
        set = function(v)
            local t = ensureUFDB()
            if not t then return end
            t[textKey] = t[textKey] or {}
            t[textKey].colorMode = v or "default"
            applyStyles()
        end,
        getColor = function()
            local s = ensureTextDB(textKey) or {}
            local c = s.color or {1, 1, 1, 1}
            return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
        end,
        setColor = function(r, g, b, a)
            local t = ensureUFDB()
            if not t then return end
            t[textKey] = t[textKey] or {}
            t[textKey].color = {r or 1, g or 1, b or 1, a or 1}
            applyStyles()
        end,
        customValue = "custom",
        hasAlpha = true,
    })

    inner:AddSelector({
        label = "Alignment",
        values = UF.alignmentValues,
        order = UF.alignmentOrder,
        get = function()
            local s = ensureTextDB(textKey) or {}
            return s.alignment or defaultAlignment
        end,
        set = function(v)
            local t = ensureUFDB()
            if not t then return end
            t[textKey] = t[textKey] or {}
            t[textKey].alignment = v or defaultAlignment
            applyStyles()
        end,
    })

    inner:AddDualSlider({
        label = "Offset",
        sliderA = {
            axisLabel = "X",
            min = -100, max = 100, step = 1,
            get = function()
                local s = ensureTextDB(textKey) or {}
                local o = s.offset or {}
                return tonumber(o.x) or 0
            end,
            set = function(v)
                local t = ensureUFDB()
                if not t then return end
                t[textKey] = t[textKey] or {}
                t[textKey].offset = t[textKey].offset or {}
                t[textKey].offset.x = tonumber(v) or 0
                applyStyles()
            end,
        },
        sliderB = {
            axisLabel = "Y",
            min = -100, max = 100, step = 1,
            get = function()
                local s = ensureTextDB(textKey) or {}
                local o = s.offset or {}
                return tonumber(o.y) or 0
            end,
            set = function(v)
                local t = ensureUFDB()
                if not t then return end
                t[textKey] = t[textKey] or {}
                t[textKey].offset = t[textKey].offset or {}
                t[textKey].offset.y = tonumber(v) or 0
                applyStyles()
            end,
        },
    })

    inner:Finalize()
end

--------------------------------------------------------------------------------
-- Health Bar Visibility Tab (Target/Focus: 3 toggles, no Health Loss Animation)
--------------------------------------------------------------------------------

local function buildHealthVisibilityTab(inner)
    inner:AddToggle({
        label = "Hide the Bar but not its Text",
        get = function()
            local t = ensureUFDB() or {}
            return not not t.healthBarHideTextureOnly
        end,
        set = function(v)
            local t = ensureUFDB()
            if not t then return end
            t.healthBarHideTextureOnly = v and true or false
            applyBarTextures()
        end,
        infoIcon = {
            tooltipTitle = "Hide the Bar but not its Text",
            tooltipText = "Hides the bar texture and background, showing only the text overlay. Useful for a number-only display of health.",
        },
    })

    inner:AddToggle({
        label = "Hide Over Absorb Glow",
        description = "Hides the glow effect when absorb shields exceed max health.",
        get = function()
            local t = ensureUFDB() or {}
            return not not t.healthBarHideOverAbsorbGlow
        end,
        set = function(v)
            local t = ensureUFDB()
            if not t then return end
            t.healthBarHideOverAbsorbGlow = v and true or false
            applyBarTextures()
        end,
        infoIcon = UF.TOOLTIPS.hideOverAbsorbGlow,
    })

    inner:AddToggle({
        label = "Hide Heal Prediction",
        description = "Hides the green heal prediction bar when healing is incoming.",
        get = function()
            local t = ensureUFDB() or {}
            return not not t.healthBarHideHealPrediction
        end,
        set = function(v)
            local t = ensureUFDB()
            if not t then return end
            t.healthBarHideHealPrediction = v and true or false
            applyBarTextures()
        end,
        infoIcon = {
            tooltipTitle = "Hide Heal Prediction",
            tooltipText = "Hides the green heal prediction bar that appears on the health bar when a heal is incoming.",
        },
    })

    inner:Finalize()
end

--------------------------------------------------------------------------------
-- Direction Tab (Target/Focus only)
--------------------------------------------------------------------------------

local function buildDirectionTab(inner)
    inner:AddSelector({
        label = "Bar Fill Direction",
        values = UF.fillDirectionValues,
        order = UF.fillDirectionOrder,
        get = function()
            local t = ensureUFDB() or {}
            return t.healthBarReverseFill and "reverse" or "default"
        end,
        set = function(v)
            local t = ensureUFDB()
            if not t then return end
            t.healthBarReverseFill = (v == "reverse")
            applyStyles()
        end,
    })

    inner:Finalize()
end

--------------------------------------------------------------------------------
-- Renderer Function
--------------------------------------------------------------------------------

function UF.RenderTarget(panel, scrollContent)
    panel:ClearContent()

    local builder = SettingsBuilder:CreateFor(scrollContent)
    panel._currentBuilder = builder

    builder:SetOnRefresh(function()
        UF.RenderTarget(panel, scrollContent)
    end)

    --------------------------------------------------------------------------------
    -- Parent-Level Settings
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
    -- Health Bar (5 tabs with Direction first)
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
                    sizing = function(cf, tabInner)
                        tabInner:AddSlider({
                            label = "Height %",
                            min = 10,
                            max = 100,
                            step = 5,
                            get = function()
                                local t = ensureUFDB() or {}
                                return tonumber(t.healthBarOverlayHeightPct) or 100
                            end,
                            set = function(v)
                                local t = ensureUFDB()
                                if not t then return end
                                t.healthBarOverlayHeightPct = tonumber(v) or 100
                                applyBarTextures()
                            end,
                            infoIcon = {
                                tooltipTitle = "Health Bar Height",
                                tooltipText = "Reduces the visible height of the health bar. The bar fill still tracks health correctly, but is cropped to this percentage of its normal height (centered vertically).",
                            },
                        })
                        tabInner:Finalize()
                    end,
                    direction = function(cf, tabInner)
                        buildDirectionTab(tabInner)
                    end,
                    style = function(cf, tabInner)
                        buildStyleTab(tabInner, "healthBar", applyBarTextures)
                    end,
                    border = function(cf, tabInner)
                        buildBorderTab(tabInner, "healthBar", applyBarTextures)
                    end,
                    visibility = function(cf, tabInner)
                        buildHealthVisibilityTab(tabInner)
                    end,
                    percentText = function(cf, tabInner)
                        buildTextTab(tabInner, "textHealthPercent", applyHealthText, "LEFT")
                    end,
                    valueText = function(cf, tabInner)
                        buildTextTab(tabInner, "textHealthValue", applyHealthText, "RIGHT")
                    end,
                },
            })
            inner:Finalize()
        end,
    })

    --------------------------------------------------------------------------------
    -- Power Bar (7 tabs)
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
                        tabInner:AddSlider({
                            label = "Height %",
                            min = 10, max = 200, step = 5,
                            get = function() local t = ensureUFDB() or {}; return tonumber(t.powerBarHeightPct) or 100 end,
                            set = function(v) local t = ensureUFDB(); if t then t.powerBarHeightPct = tonumber(v) or 100; applyBarTextures() end end,
                        })
                        tabInner:Finalize()
                    end,
                    style = function(cf, tabInner)
                        buildStyleTab(tabInner, "powerBar", applyBarTextures, UF.powerColorValues, UF.powerColorOrder)
                    end,
                    border = function(cf, tabInner)
                        buildBorderTab(tabInner, "powerBar", applyBarTextures)
                    end,
                    visibility = function(cf, tabInner)
                        tabInner:AddToggle({
                            label = "Hide Power Bar",
                            get = function() local t = ensureUFDB() or {}; return not not t.powerBarHidden end,
                            set = function(v) local t = ensureUFDB(); if t then t.powerBarHidden = v and true or false; applyBarTextures() end end,
                        })
                        tabInner:Finalize()
                    end,
                    percentText = function(cf, tabInner)
                        buildTextTab(tabInner, "textPowerPercent", applyPowerText, "LEFT")
                    end,
                    valueText = function(cf, tabInner)
                        buildTextTab(tabInner, "textPowerValue", applyPowerText, "RIGHT")
                    end,
                },
            })
            inner:Finalize()
        end,
    })

    --------------------------------------------------------------------------------
    -- Buffs & Debuffs (Target only - 5 tabs)
    --------------------------------------------------------------------------------

    local buffsTabs = UF.getBuffsDebuffsTabs()

    builder:AddCollapsibleSection({
        title = "Buffs & Debuffs",
        componentId = COMPONENT_ID,
        sectionKey = "buffsDebuffs",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddTabbedSection({
                tabs = buffsTabs,
                componentId = COMPONENT_ID,
                sectionKey = "buffsDebuffs_tabs",
                buildContent = {
                    sizing = function(cf, tabInner)
                        tabInner:AddSlider({
                            label = "Icon Scale",
                            min = 20, max = 200, step = 5,
                            get = function() local t = ensureBuffsDebuffsDB() or {}; return tonumber(t.iconScale) or 100 end,
                            set = function(v) local t = ensureBuffsDebuffsDB(); if t then t.iconScale = tonumber(v) or 100; applyBuffsDebuffs() end end,
                            minLabel = "20%", maxLabel = "200%",
                        })
                        tabInner:AddSlider({
                            label = "Icon Shape",
                            description = "Adjust icon aspect ratio. Center = square icons.",
                            min = -67, max = 67, step = 1,
                            get = function() local t = ensureBuffsDebuffsDB() or {}; return tonumber(t.tallWideRatio) or 0 end,
                            set = function(v) local t = ensureBuffsDebuffsDB(); if t then t.tallWideRatio = tonumber(v) or 0; applyBuffsDebuffs() end end,
                            minLabel = "Wide", maxLabel = "Tall",
                        })
                        tabInner:Finalize()
                    end,
                    border = function(cf, tabInner)
                        tabInner:AddToggle({
                            label = "Enable Custom Borders",
                            get = function() local t = ensureBuffsDebuffsDB() or {}; return not not t.borderEnable end,
                            set = function(v) local t = ensureBuffsDebuffsDB(); if t then t.borderEnable = v and true or false; applyBuffsDebuffs() end end,
                        })
                        local borderValues, borderOrder = UF.buildIconBorderOptions()
                        tabInner:AddSelector({
                            label = "Border Style",
                            values = borderValues, order = borderOrder,
                            get = function() local t = ensureBuffsDebuffsDB() or {}; return t.borderStyle or "square" end,
                            set = function(v) local t = ensureBuffsDebuffsDB(); if t then t.borderStyle = v or "square"; applyBuffsDebuffs() end end,
                        })
                        tabInner:AddSlider({
                            label = "Border Thickness",
                            min = 1, max = 8, step = 0.5, precision = 1,
                            get = function() local t = ensureBuffsDebuffsDB() or {}; local v = tonumber(t.borderThickness) or 1; return math.max(1, math.min(8, math.floor(v * 2 + 0.5) / 2)) end,
                            set = function(v) local t = ensureBuffsDebuffsDB(); if t then t.borderThickness = math.max(1, math.min(8, math.floor((tonumber(v) or 1) * 2 + 0.5) / 2)); applyBuffsDebuffs() end end,
                        })
                        tabInner:AddToggleColorPicker({
                            label = "Border Tint",
                            get = function() local t = ensureBuffsDebuffsDB() or {}; return not not t.borderTintEnable end,
                            set = function(v) local t = ensureBuffsDebuffsDB(); if t then t.borderTintEnable = not not v; applyBuffsDebuffs() end end,
                            getColor = function() local t = ensureBuffsDebuffsDB() or {}; local c = t.borderTintColor or {1,1,1,1}; return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 end,
                            setColor = function(r,g,b,a) local t = ensureBuffsDebuffsDB(); if t then t.borderTintColor = {r or 1, g or 1, b or 1, a or 1}; applyBuffsDebuffs() end end,
                            hasAlpha = true,
                        })
                        tabInner:Finalize()
                    end,
                    visibility = function(cf, tabInner)
                        tabInner:AddToggle({
                            label = "Hide Buffs & Debuffs",
                            get = function() local t = ensureBuffsDebuffsDB() or {}; return not not t.hideBuffsDebuffs end,
                            set = function(v) local t = ensureBuffsDebuffsDB(); if t then t.hideBuffsDebuffs = v and true or false; applyBuffsDebuffs() end end,
                        })
                        tabInner:Finalize()
                    end,
                    filters = function(cf, tabInner)
                        tabInner:AddToggle({
                            label = "Show Only Player Buffs",
                            get = function() local t = ensureBuffsDebuffsDB() or {}; return not not t.onlyPlayerBuffs end,
                            set = function(v) local t = ensureBuffsDebuffsDB(); if t then t.onlyPlayerBuffs = v and true or false; applyBuffsDebuffs() end end,
                        })
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
                        tabInner:AddToggle({
                            label = "Enable Backdrop",
                            get = function() local t = ensureUFDB() or {}; return not not t.nameBackdropEnabled end,
                            set = function(v) local t = ensureUFDB(); if t then t.nameBackdropEnabled = not not v; applyNameLevelText() end end,
                        })
                        tabInner:AddBarTextureSelector({
                            label = "Backdrop Texture",
                            get = function() local t = ensureUFDB() or {}; return t.nameBackdropTexture or "" end,
                            set = function(v) local t = ensureUFDB(); if t then t.nameBackdropTexture = v; applyNameLevelText() end end,
                        })
                        tabInner:AddSelectorColorPicker({
                            label = "Backdrop Color",
                            values = UF.bgColorValues, order = UF.bgColorOrder,
                            get = function() local t = ensureUFDB() or {}; return t.nameBackdropColorMode or "default" end,
                            set = function(v) local t = ensureUFDB(); if t then t.nameBackdropColorMode = v or "default"; applyNameLevelText() end end,
                            getColor = function() local t = ensureUFDB() or {}; local c = t.nameBackdropTint or {1,1,1,1}; return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 end,
                            setColor = function(r,g,b,a) local t = ensureUFDB(); if t then t.nameBackdropTint = {r,g,b,a}; applyNameLevelText() end end,
                            customValue = "custom", hasAlpha = true,
                        })
                        tabInner:AddSlider({
                            label = "Backdrop Width (%)", min = 25, max = 300, step = 1,
                            get = function() local t = ensureUFDB() or {}; return tonumber(t.nameBackdropWidthPct) or 100 end,
                            set = function(v) local t = ensureUFDB(); if t then t.nameBackdropWidthPct = tonumber(v) or 100; applyNameLevelText() end end,
                        })
                        tabInner:AddSlider({
                            label = "Backdrop Opacity", min = 0, max = 100, step = 1,
                            get = function() local t = ensureUFDB() or {}; return tonumber(t.nameBackdropOpacity) or 50 end,
                            set = function(v) local t = ensureUFDB(); if t then t.nameBackdropOpacity = tonumber(v) or 50; applyNameLevelText() end end,
                        })
                        tabInner:Finalize()
                    end,
                    border = function(cf, tabInner)
                        tabInner:AddToggle({
                            label = "Enable Border",
                            get = function() local t = ensureUFDB() or {}; return not not t.nameBackdropBorderEnabled end,
                            set = function(v) local t = ensureUFDB(); if t then t.nameBackdropBorderEnabled = not not v; applyNameLevelText() end end,
                        })
                        tabInner:AddBarBorderSelector({
                            label = "Border Style",
                            includeNone = true,
                            get = function() local t = ensureUFDB() or {}; return t.nameBackdropBorderStyle or "square" end,
                            set = function(v) local t = ensureUFDB(); if t then t.nameBackdropBorderStyle = v or "square"; applyNameLevelText() end end,
                        })
                        tabInner:AddToggleColorPicker({
                            label = "Border Tint",
                            get = function() local t = ensureUFDB() or {}; return not not t.nameBackdropBorderTintEnable end,
                            set = function(v) local t = ensureUFDB(); if t then t.nameBackdropBorderTintEnable = not not v; applyNameLevelText() end end,
                            getColor = function() local t = ensureUFDB() or {}; local c = t.nameBackdropBorderTintColor or {1,1,1,1}; return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 end,
                            setColor = function(r,g,b,a) local t = ensureUFDB(); if t then t.nameBackdropBorderTintColor = {r,g,b,a}; applyNameLevelText() end end,
                            hasAlpha = true,
                        })
                        tabInner:AddSlider({
                            label = "Border Thickness", min = 1, max = 8, step = 0.5, precision = 1,
                            get = function() local t = ensureUFDB() or {}; local v = tonumber(t.nameBackdropBorderThickness) or 1; return math.max(1, math.min(8, math.floor(v * 2 + 0.5) / 2)) end,
                            set = function(v) local t = ensureUFDB(); if t then t.nameBackdropBorderThickness = math.max(1, math.min(8, math.floor((tonumber(v) or 1) * 2 + 0.5) / 2)); applyNameLevelText() end end,
                        })
                        tabInner:AddDualSlider({
                            label = "Border Inset",
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
                        tabInner:AddToggle({
                            label = "Disable Name Text",
                            get = function() local t = ensureUFDB() or {}; return not not t.nameTextHidden end,
                            set = function(v) local t = ensureUFDB(); if t then t.nameTextHidden = v and true or false; applyNameLevelText() end end,
                        })
                        tabInner:AddSlider({
                            label = "Name Container Width", min = 80, max = 150, step = 5,
                            get = function() local s = ensureNameLevelDB("textName") or {}; return tonumber(s.containerWidthPct) or 100 end,
                            set = function(v) local t = ensureNameLevelDB("textName"); if t then t.containerWidthPct = tonumber(v) or 100; applyNameLevelText() end end,
                        })
                        tabInner:AddFontSelector({
                            label = "Name Text Font",
                            get = function() local s = ensureNameLevelDB("textName") or {}; return s.fontFace or "FRIZQT__" end,
                            set = function(v) local t = ensureNameLevelDB("textName"); if t then t.fontFace = v; applyNameLevelText() end end,
                        })
                        tabInner:AddSelector({
                            label = "Name Text Style", values = UF.fontStyleValues, order = UF.fontStyleOrder,
                            get = function() local s = ensureNameLevelDB("textName") or {}; return s.style or "OUTLINE" end,
                            set = function(v) local t = ensureNameLevelDB("textName"); if t then t.style = v; applyNameLevelText() end end,
                        })
                        tabInner:AddSlider({
                            label = "Name Text Size", min = 6, max = 48, step = 1,
                            get = function() local s = ensureNameLevelDB("textName") or {}; return tonumber(s.size) or 14 end,
                            set = function(v) local t = ensureNameLevelDB("textName"); if t then t.size = tonumber(v) or 14; applyNameLevelText() end end,
                        })
                        tabInner:AddSelectorColorPicker({
                            label = "Name Text Color",
                            values = UF.fontColorValues, order = UF.fontColorOrder,
                            get = function() local s = ensureNameLevelDB("textName") or {}; return s.colorMode or "default" end,
                            set = function(v) local t = ensureNameLevelDB("textName"); if t then t.colorMode = v or "default"; applyNameLevelText() end end,
                            getColor = function() local s = ensureNameLevelDB("textName") or {}; local c = s.color or {1,0.82,0,1}; return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 end,
                            setColor = function(r,g,b,a) local t = ensureNameLevelDB("textName"); if t then t.color = {r,g,b,a}; applyNameLevelText() end end,
                            customValue = "custom", hasAlpha = true,
                        })
                        tabInner:AddSelector({
                            label = "Name Text Alignment", values = UF.alignmentValues, order = UF.alignmentOrder,
                            get = function() local s = ensureNameLevelDB("textName") or {}; return s.alignment or "LEFT" end,
                            set = function(v) local t = ensureNameLevelDB("textName"); if t then t.alignment = v or "LEFT"; applyNameLevelText() end end,
                        })
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
                        tabInner:AddToggle({
                            label = "Disable Level Text",
                            get = function() local t = ensureUFDB() or {}; return not not t.levelTextHidden end,
                            set = function(v) local t = ensureUFDB(); if t then t.levelTextHidden = v and true or false; applyNameLevelText() end end,
                        })
                        tabInner:AddFontSelector({
                            label = "Level Text Font",
                            get = function() local s = ensureNameLevelDB("textLevel") or {}; return s.fontFace or "FRIZQT__" end,
                            set = function(v) local t = ensureNameLevelDB("textLevel"); if t then t.fontFace = v; applyNameLevelText() end end,
                        })
                        tabInner:AddSelector({
                            label = "Level Text Style", values = UF.fontStyleValues, order = UF.fontStyleOrder,
                            get = function() local s = ensureNameLevelDB("textLevel") or {}; return s.style or "OUTLINE" end,
                            set = function(v) local t = ensureNameLevelDB("textLevel"); if t then t.style = v; applyNameLevelText() end end,
                        })
                        tabInner:AddSlider({
                            label = "Level Text Size", min = 6, max = 48, step = 1,
                            get = function() local s = ensureNameLevelDB("textLevel") or {}; return tonumber(s.size) or 14 end,
                            set = function(v) local t = ensureNameLevelDB("textLevel"); if t then t.size = tonumber(v) or 14; applyNameLevelText() end end,
                        })
                        tabInner:AddSelectorColorPicker({
                            label = "Level Text Color", values = UF.fontColorValues, order = UF.fontColorOrder,
                            get = function() local s = ensureNameLevelDB("textLevel") or {}; return s.colorMode or "default" end,
                            set = function(v) local t = ensureNameLevelDB("textLevel"); if t then t.colorMode = v or "default"; applyNameLevelText() end end,
                            getColor = function() local s = ensureNameLevelDB("textLevel") or {}; local c = s.color or {1,0.82,0,1}; return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 end,
                            setColor = function(r,g,b,a) local t = ensureNameLevelDB("textLevel"); if t then t.color = {r,g,b,a}; applyNameLevelText() end end,
                            customValue = "custom", hasAlpha = true,
                        })
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
    -- Collapsible Section: Portrait (Target has 5 tabs - no Personal Text)
    --------------------------------------------------------------------------------

    builder:AddCollapsibleSection({
        title = "Portrait",
        componentId = COMPONENT_ID,
        sectionKey = "portrait",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddTabbedSection({
                tabs = {
                    { key = "positioning", label = "Positioning" },
                    { key = "sizing", label = "Sizing" },
                    { key = "mask", label = "Mask" },
                    { key = "border", label = "Border" },
                    { key = "visibility", label = "Visibility" },
                },
                componentId = COMPONENT_ID,
                sectionKey = "portrait_tabs",
                buildContent = {
                    positioning = function(cf, tabInner)
                        tabInner:AddDualSlider({
                            label = "Offset",
                            sliderA = {
                                axisLabel = "X",
                                min = -100, max = 100, step = 1,
                                get = function() local t = ensurePortraitDB() or {}; return tonumber(t.offsetX) or 0 end,
                                set = function(v) local t = ensurePortraitDB(); if t then t.offsetX = tonumber(v) or 0; applyPortrait() end end,
                            },
                            sliderB = {
                                axisLabel = "Y",
                                min = -100, max = 100, step = 1,
                                get = function() local t = ensurePortraitDB() or {}; return tonumber(t.offsetY) or 0 end,
                                set = function(v) local t = ensurePortraitDB(); if t then t.offsetY = tonumber(v) or 0; applyPortrait() end end,
                            },
                        })
                        tabInner:Finalize()
                    end,
                    sizing = function(cf, tabInner)
                        tabInner:AddSlider({
                            label = "Portrait Size (Scale)", min = 50, max = 200, step = 1,
                            get = function() local t = ensurePortraitDB() or {}; return tonumber(t.scale) or 100 end,
                            set = function(v) local t = ensurePortraitDB(); if t then t.scale = tonumber(v) or 100; applyPortrait() end end,
                        })
                        tabInner:Finalize()
                    end,
                    mask = function(cf, tabInner)
                        tabInner:AddSlider({
                            label = "Portrait Zoom", min = 100, max = 200, step = 1,
                            get = function() local t = ensurePortraitDB() or {}; return tonumber(t.zoom) or 100 end,
                            set = function(v) local t = ensurePortraitDB(); if t then t.zoom = tonumber(v) or 100; applyPortrait() end end,
                        })
                        tabInner:Finalize()
                    end,
                    border = function(cf, tabInner)
                        tabInner:AddToggle({
                            label = "Use Custom Border",
                            get = function() local t = ensurePortraitDB() or {}; return t.portraitBorderEnable == true end,
                            set = function(v) local t = ensurePortraitDB(); if t then t.portraitBorderEnable = (v == true); applyPortrait() end end,
                        })
                        -- Target/Focus have rare_s option
                        local targetBorderValues = { texture_c = "Circle", texture_s = "Circle with Corner", rare_c = "Rare (Circle)", rare_s = "Rare (Square)" }
                        local targetBorderOrder = { "texture_c", "texture_s", "rare_c", "rare_s" }
                        tabInner:AddSelector({
                            label = "Border Style", values = targetBorderValues, order = targetBorderOrder,
                            get = function() local t = ensurePortraitDB() or {}; return t.portraitBorderStyle or "texture_c" end,
                            set = function(v) local t = ensurePortraitDB(); if t then t.portraitBorderStyle = v or "texture_c"; applyPortrait() end end,
                        })
                        tabInner:AddSlider({
                            label = "Border Inset", min = 1, max = 8, step = 0.5, precision = 1,
                            get = function() local t = ensurePortraitDB() or {}; local v = tonumber(t.portraitBorderThickness) or 1; return math.max(1, math.min(8, math.floor(v * 2 + 0.5) / 2)) end,
                            set = function(v) local t = ensurePortraitDB(); if t then t.portraitBorderThickness = math.max(1, math.min(8, math.floor((tonumber(v) or 1) * 2 + 0.5) / 2)); applyPortrait() end end,
                        })
                        tabInner:AddSelectorColorPicker({
                            label = "Border Color", values = UF.portraitBorderColorValues, order = UF.portraitBorderColorOrder,
                            get = function() local t = ensurePortraitDB() or {}; return t.portraitBorderColorMode or "texture" end,
                            set = function(v) local t = ensurePortraitDB(); if t then t.portraitBorderColorMode = v or "texture"; applyPortrait() end end,
                            getColor = function() local t = ensurePortraitDB() or {}; local c = t.portraitBorderTintColor or {1,1,1,1}; return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 end,
                            setColor = function(r,g,b,a) local t = ensurePortraitDB(); if t then t.portraitBorderTintColor = {r,g,b,a}; applyPortrait() end end,
                            customValue = "custom", hasAlpha = true,
                        })
                        tabInner:Finalize()
                    end,
                    visibility = function(cf, tabInner)
                        tabInner:AddToggle({
                            label = "Hide Portrait",
                            get = function() local t = ensurePortraitDB() or {}; return not not t.hidePortrait end,
                            set = function(v) local t = ensurePortraitDB(); if t then t.hidePortrait = v and true or false; applyPortrait() end end,
                        })
                        tabInner:Finalize()
                    end,
                },
            })
            inner:Finalize()
        end,
    })

    --------------------------------------------------------------------------------
    -- Collapsible Section: Cast Bar (7 tabs for Target - no Cast Time)
    --------------------------------------------------------------------------------

    local castBarTabs = UF.getCastBarTabs(COMPONENT_ID)

    builder:AddCollapsibleSection({
        title = "Cast Bar",
        componentId = COMPONENT_ID,
        sectionKey = "castBar",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddTabbedSection({
                tabs = castBarTabs,
                componentId = COMPONENT_ID,
                sectionKey = "castBar_tabs",
                buildContent = {
                    positioning = function(cf, tabInner)
                        tabInner:AddSelector({
                            label = "Anchor To",
                            values = {
                                ["default"] = "Default (Blizzard)",
                                ["healthTop"] = "Above Health Bar",
                                ["healthBottom"] = "Below Health Bar",
                                ["powerTop"] = "Above Power Bar",
                                ["powerBottom"] = "Below Power Bar",
                            },
                            order = {"default", "healthTop", "healthBottom", "powerTop", "powerBottom"},
                            get = function() local t = ensureCastBarDB() or {}; return t.anchorMode or "default" end,
                            set = function(v) local t = ensureCastBarDB(); if t then t.anchorMode = v; applyCastBar() end end,
                        })
                        tabInner:AddDualSlider({
                            label = "Offset",
                            sliderA = {
                                axisLabel = "X",
                                min = -200, max = 200, step = 1,
                                get = function() local t = ensureCastBarDB() or {}; return tonumber(t.offsetX) or 0 end,
                                set = function(v) local t = ensureCastBarDB(); if t then t.offsetX = tonumber(v) or 0; applyCastBar() end end,
                            },
                            sliderB = {
                                axisLabel = "Y",
                                min = -200, max = 200, step = 1,
                                get = function() local t = ensureCastBarDB() or {}; return tonumber(t.offsetY) or 0 end,
                                set = function(v) local t = ensureCastBarDB(); if t then t.offsetY = tonumber(v) or 0; applyCastBar() end end,
                            },
                        })
                        tabInner:Finalize()
                    end,
                    sizing = function(cf, tabInner)
                        tabInner:AddSlider({
                            label = "Scale %", min = 50, max = 150, step = 1,
                            get = function() local t = ensureCastBarDB() or {}; return tonumber(t.castBarScale) or 100 end,
                            set = function(v) local t = ensureCastBarDB(); if t then t.castBarScale = tonumber(v) or 100; applyCastBar() end end,
                        })
                        tabInner:AddSlider({
                            label = "Width %", min = 50, max = 150, step = 1,
                            get = function() local t = ensureCastBarDB() or {}; return tonumber(t.widthPct) or 100 end,
                            set = function(v) local t = ensureCastBarDB(); if t then t.widthPct = tonumber(v) or 100; applyCastBar() end end,
                        })
                        tabInner:AddSlider({
                            label = "Height", min = 5, max = 50, step = 1,
                            get = function() local t = ensureCastBarDB() or {}; return tonumber(t.castBarHeight) or 13 end,
                            set = function(v) local t = ensureCastBarDB(); if t then t.castBarHeight = tonumber(v) or 13; applyCastBar() end end,
                        })
                        tabInner:Finalize()
                    end,
                    style = function(cf, tabInner)
                        tabInner:AddBarTextureSelector({
                            label = "Foreground Texture",
                            get = function() local t = ensureCastBarDB() or {}; return t.castBarTexture or "default" end,
                            set = function(v) local t = ensureCastBarDB(); if t then t.castBarTexture = v or "default"; applyCastBar() end end,
                        })
                        tabInner:AddSelectorColorPicker({
                            label = "Foreground Color", values = UF.healthColorValues, order = UF.healthColorOrder,
                            get = function() local t = ensureCastBarDB() or {}; return t.castBarColorMode or "default" end,
                            set = function(v) local t = ensureCastBarDB(); if t then t.castBarColorMode = v or "default"; applyCastBar() end end,
                            getColor = function() local t = ensureCastBarDB() or {}; local c = t.castBarTint or {1,1,1,1}; return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 end,
                            setColor = function(r,g,b,a) local t = ensureCastBarDB(); if t then t.castBarTint = {r,g,b,a}; applyCastBar() end end,
                            customValue = "custom", hasAlpha = true,
                        })
                        tabInner:AddSpacer(8)
                        tabInner:AddBarTextureSelector({
                            label = "Background Texture",
                            get = function() local t = ensureCastBarDB() or {}; return t.castBarBackgroundTexture or "default" end,
                            set = function(v) local t = ensureCastBarDB(); if t then t.castBarBackgroundTexture = v or "default"; applyCastBar() end end,
                        })
                        tabInner:AddSelectorColorPicker({
                            label = "Background Color", values = UF.bgColorValues, order = UF.bgColorOrder,
                            get = function() local t = ensureCastBarDB() or {}; return t.castBarBackgroundColorMode or "default" end,
                            set = function(v) local t = ensureCastBarDB(); if t then t.castBarBackgroundColorMode = v or "default"; applyCastBar() end end,
                            getColor = function() local t = ensureCastBarDB() or {}; local c = t.castBarBackgroundTint or {0,0,0,1}; return c[1] or 0, c[2] or 0, c[3] or 0, c[4] or 1 end,
                            setColor = function(r,g,b,a) local t = ensureCastBarDB(); if t then t.castBarBackgroundTint = {r,g,b,a}; applyCastBar() end end,
                            customValue = "custom", hasAlpha = true,
                        })
                        tabInner:AddSlider({
                            label = "Background Opacity", min = 0, max = 100, step = 1,
                            get = function() local t = ensureCastBarDB() or {}; return tonumber(t.castBarBackgroundOpacity) or 50 end,
                            set = function(v) local t = ensureCastBarDB(); if t then t.castBarBackgroundOpacity = tonumber(v) or 50; applyCastBar() end end,
                        })
                        tabInner:AddSpacer(8)
                        tabInner:AddToggle({
                            label = "Hide Spark",
                            get = function() local t = ensureCastBarDB() or {}; return not not t.castBarSparkHidden end,
                            set = function(v) local t = ensureCastBarDB(); if t then t.castBarSparkHidden = v and true or false; applyCastBar() end end,
                        })
                        tabInner:AddSelectorColorPicker({
                            label = "Spark Color",
                            values = { ["default"] = "Default", ["custom"] = "Custom" },
                            order = { "default", "custom" },
                            get = function() local t = ensureCastBarDB() or {}; return t.castBarSparkColorMode or "default" end,
                            set = function(v) local t = ensureCastBarDB(); if t then t.castBarSparkColorMode = v or "default"; applyCastBar() end end,
                            getColor = function() local t = ensureCastBarDB() or {}; local c = t.castBarSparkTint or {1,1,1,1}; return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 end,
                            setColor = function(r,g,b,a) local t = ensureCastBarDB(); if t then t.castBarSparkTint = {r,g,b,a}; applyCastBar() end end,
                            customValue = "custom", hasAlpha = true,
                        })
                        tabInner:Finalize()
                    end,
                    border = function(cf, tabInner)
                        tabInner:AddToggle({
                            label = "Enable Border",
                            get = function() local t = ensureCastBarDB() or {}; return not not t.castBarBorderEnable end,
                            set = function(v) local t = ensureCastBarDB(); if t then t.castBarBorderEnable = not not v; applyCastBar() end end,
                        })
                        tabInner:AddBarBorderSelector({
                            label = "Border Style",
                            includeNone = true,
                            get = function() local t = ensureCastBarDB() or {}; return t.castBarBorderStyle or "square" end,
                            set = function(v) local t = ensureCastBarDB(); if t then t.castBarBorderStyle = v or "square"; applyCastBar() end end,
                        })
                        tabInner:AddToggleColorPicker({
                            label = "Border Tint",
                            get = function() local t = ensureCastBarDB() or {}; return not not t.castBarBorderTintEnable end,
                            set = function(v) local t = ensureCastBarDB(); if t then t.castBarBorderTintEnable = not not v; applyCastBar() end end,
                            getColor = function() local t = ensureCastBarDB() or {}; local c = t.castBarBorderTintColor or {1,1,1,1}; return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 end,
                            setColor = function(r,g,b,a) local t = ensureCastBarDB(); if t then t.castBarBorderTintColor = {r,g,b,a}; applyCastBar() end end,
                            hasAlpha = true,
                        })
                        tabInner:AddSlider({
                            label = "Border Thickness", min = 1, max = 8, step = 0.5, precision = 1,
                            get = function() local t = ensureCastBarDB() or {}; local v = tonumber(t.castBarBorderThickness) or 1; return math.max(1, math.min(8, math.floor(v * 2 + 0.5) / 2)) end,
                            set = function(v) local t = ensureCastBarDB(); if t then t.castBarBorderThickness = math.max(1, math.min(8, math.floor((tonumber(v) or 1) * 2 + 0.5) / 2)); applyCastBar() end end,
                        })
                        tabInner:AddDualSlider({
                            label = "Border Inset",
                            sliderA = {
                                axisLabel = "H", min = -4, max = 4, step = 1,
                                get = function() local t = ensureCastBarDB() or {}; return tonumber(t.castBarBorderInsetH) or tonumber(t.castBarBorderInset) or 0 end,
                                set = function(v) local t = ensureCastBarDB(); if t then t.castBarBorderInsetH = tonumber(v) or 0; applyCastBar() end end,
                                minLabel = "-4", maxLabel = "+4",
                            },
                            sliderB = {
                                axisLabel = "V", min = -4, max = 4, step = 1,
                                get = function() local t = ensureCastBarDB() or {}; return tonumber(t.castBarBorderInsetV) or tonumber(t.castBarBorderInset) or 0 end,
                                set = function(v) local t = ensureCastBarDB(); if t then t.castBarBorderInsetV = tonumber(v) or 0; applyCastBar() end end,
                                minLabel = "-4", maxLabel = "+4",
                            },
                        })
                        tabInner:Finalize()
                    end,
                    icon = function(cf, tabInner)
                        tabInner:AddToggle({
                            label = "Hide Icon",
                            get = function() local t = ensureCastBarDB() or {}; return not not t.iconDisabled end,
                            set = function(v) local t = ensureCastBarDB(); if t then t.iconDisabled = v and true or false; applyCastBar() end end,
                        })
                        tabInner:AddSlider({
                            label = "Icon Size", min = 10, max = 64, step = 1,
                            get = function() local t = ensureCastBarDB() or {}; return tonumber(t.iconWidth) or tonumber(t.iconHeight) or 24 end,
                            set = function(v) local t = ensureCastBarDB(); if t then t.iconWidth = tonumber(v) or 24; t.iconHeight = tonumber(v) or 24; applyCastBar() end end,
                        })
                        tabInner:AddDualSlider({
                            label = "Icon Offset",
                            sliderA = {
                                axisLabel = "X",
                                min = -100, max = 100, step = 1,
                                get = function() local t = ensureCastBarDB() or {}; return tonumber(t.castBarIconOffsetX) or 0 end,
                                set = function(v) local t = ensureCastBarDB(); if t then t.castBarIconOffsetX = tonumber(v) or 0; applyCastBar() end end,
                            },
                            sliderB = {
                                axisLabel = "Y",
                                min = -100, max = 100, step = 1,
                                get = function() local t = ensureCastBarDB() or {}; return tonumber(t.castBarIconOffsetY) or 0 end,
                                set = function(v) local t = ensureCastBarDB(); if t then t.castBarIconOffsetY = tonumber(v) or 0; applyCastBar() end end,
                            },
                        })
                        tabInner:Finalize()
                    end,
                    spellName = function(cf, tabInner)
                        tabInner:AddToggle({
                            label = "Hide Spell Name",
                            get = function() local t = ensureCastBarDB() or {}; return not not t.castBarSpellNameHidden end,
                            set = function(v) local t = ensureCastBarDB(); if t then t.castBarSpellNameHidden = v and true or false; applyCastBar() end end,
                        })
                        tabInner:AddFontSelector({
                            label = "Spell Name Font",
                            get = function() local t = ensureCastBarDB() or {}; local s = t.spellNameText or {}; return s.fontFace or "FRIZQT__" end,
                            set = function(v) local t = ensureCastBarDB(); if t then t.spellNameText = t.spellNameText or {}; t.spellNameText.fontFace = v; applyCastBar() end end,
                        })
                        tabInner:AddSelector({
                            label = "Spell Name Style", values = UF.fontStyleValues, order = UF.fontStyleOrder,
                            get = function() local t = ensureCastBarDB() or {}; local s = t.spellNameText or {}; return s.style or "OUTLINE" end,
                            set = function(v) local t = ensureCastBarDB(); if t then t.spellNameText = t.spellNameText or {}; t.spellNameText.style = v; applyCastBar() end end,
                        })
                        tabInner:AddSlider({
                            label = "Spell Name Size", min = 6, max = 32, step = 1,
                            get = function() local t = ensureCastBarDB() or {}; local s = t.spellNameText or {}; return tonumber(s.size) or 12 end,
                            set = function(v) local t = ensureCastBarDB(); if t then t.spellNameText = t.spellNameText or {}; t.spellNameText.size = tonumber(v) or 12; applyCastBar() end end,
                        })
                        tabInner:AddColorPicker({
                            label = "Spell Name Color",
                            get = function() local t = ensureCastBarDB() or {}; local s = t.spellNameText or {}; local c = s.color or {1,1,1,1}; return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 end,
                            set = function(r,g,b,a) local t = ensureCastBarDB(); if t then t.spellNameText = t.spellNameText or {}; t.spellNameText.color = {r,g,b,a}; applyCastBar() end end,
                            hasAlpha = true,
                        })
                        tabInner:Finalize()
                    end,
                    visibility = function(cf, tabInner)
                        tabInner:AddToggle({
                            label = "Hide Cast Bar",
                            get = function() local t = ensureCastBarDB() or {}; return not not t.castBarHidden end,
                            set = function(v) local t = ensureCastBarDB(); if t then t.castBarHidden = v and true or false; applyCastBar() end end,
                        })
                        tabInner:Finalize()
                    end,
                },
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
addon.UI.SettingsPanel:RegisterRenderer("ufTarget", function(panel, scrollContent)
    UF.RenderTarget(panel, scrollContent)
end)

-- Return renderer for registration
--------------------------------------------------------------------------------

return UF.RenderTarget
