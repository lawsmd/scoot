-- BossRenderer.lua - Boss Unit Frames TUI renderer
-- Boss frames have special implementation with conditional settings
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.UnitFrames = addon.UI.UnitFrames or {}
local UF = addon.UI.UnitFrames
local SettingsBuilder = addon.UI.SettingsBuilder

local COMPONENT_ID = "ufBoss"
local UNIT_KEY = "Boss"

--------------------------------------------------------------------------------
-- Database Access
--------------------------------------------------------------------------------

local function ensureUFDB()
    return UF.ensureUFDB(UNIT_KEY)
end

local function ensureCastBarDB()
    return UF.ensureCastBarDB(UNIT_KEY)
end

local function ensureTextDB(key)
    return UF.ensureTextDB(UNIT_KEY, key)
end

local function ensureNameLevelDB(textKey)
    local t = UF.ensureUFDB(UNIT_KEY)
    if not t then return nil end
    t[textKey] = t[textKey] or {}
    return t[textKey]
end

local function ensureMiscDB()
    local t = UF.ensureUFDB(UNIT_KEY)
    if not t then return nil end
    t.misc = t.misc or {}
    return t.misc
end

-- Read-only accessors (no materialization — used in get callbacks)
local function getUFDB()
    return UF.getUFDB(UNIT_KEY)
end

local function getCastBarDB()
    return UF.getCastBarDB(UNIT_KEY)
end

local function getTextDB(key)
    return UF.getTextDB(UNIT_KEY, key)
end

local function getNameLevelDB(textKey)
    local t = UF.getUFDB(UNIT_KEY)
    return t and rawget(t, textKey) or nil
end

local function getMiscDB()
    return UF.getMiscDB(UNIT_KEY)
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

local function applyCastBar()
    if addon.ApplyBossCastBarFor then
        addon.ApplyBossCastBarFor()
    else
        UF.applyCastBar(UNIT_KEY)
    end
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
-- Shared Tab Builders
--------------------------------------------------------------------------------

local function buildStyleTab(inner, barPrefix, applyFn, colorValues, colorOrder, colorInfoIcons, dbFn, getDBFn)
    colorValues = colorValues or UF.healthColorValues
    colorOrder = colorOrder or UF.healthColorOrder
    colorInfoIcons = colorInfoIcons or UF.healthColorInfoIcons
    dbFn = dbFn or ensureUFDB
    getDBFn = getDBFn or getUFDB

    inner:AddDualBarStyleRow({
        label = "Foreground",
        getTexture = function() local t = getDBFn() or {}; return t[barPrefix .. "Texture"] or "default" end,
        setTexture = function(v) local t = dbFn(); if t then t[barPrefix .. "Texture"] = v or "default"; applyFn() end end,
        colorValues = colorValues, colorOrder = colorOrder, colorInfoIcons = colorInfoIcons,
        getColorMode = function() local t = getDBFn() or {}; return t[barPrefix .. "ColorMode"] or "default" end,
        setColorMode = function(v) local t = dbFn(); if t then t[barPrefix .. "ColorMode"] = v or "default"; applyFn() end end,
        getColor = function() local t = getDBFn() or {}; local c = t[barPrefix .. "Tint"] or {1,1,1,1}; return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 end,
        setColor = function(r,g,b,a) local t = dbFn(); if t then t[barPrefix .. "Tint"] = {r or 1, g or 1, b or 1, a or 1}; applyFn() end end,
        customColorValue = "custom", hasAlpha = true,
    })

    inner:AddSpacer(8)

    inner:AddDualBarStyleRow({
        label = "Background",
        getTexture = function() local t = getDBFn() or {}; return t[barPrefix .. "BackgroundTexture"] or "default" end,
        setTexture = function(v) local t = dbFn(); if t then t[barPrefix .. "BackgroundTexture"] = v or "default"; applyFn() end end,
        colorValues = UF.bgColorValues, colorOrder = UF.bgColorOrder,
        getColorMode = function() local t = getDBFn() or {}; return t[barPrefix .. "BackgroundColorMode"] or "default" end,
        setColorMode = function(v) local t = dbFn(); if t then t[barPrefix .. "BackgroundColorMode"] = v or "default"; applyFn() end end,
        getColor = function() local t = getDBFn() or {}; local c = t[barPrefix .. "BackgroundTint"] or {0,0,0,1}; return c[1] or 0, c[2] or 0, c[3] or 0, c[4] or 1 end,
        setColor = function(r,g,b,a) local t = dbFn(); if t then t[barPrefix .. "BackgroundTint"] = {r or 0, g or 0, b or 0, a or 1}; applyFn() end end,
        customColorValue = "custom", hasAlpha = true,
    })

    inner:AddSlider({
        label = "Background Opacity",
        min = 0, max = 100, step = 1,
        get = function() local t = getDBFn() or {}; return tonumber(t[barPrefix .. "BackgroundOpacity"]) or 50 end,
        set = function(v) local t = dbFn(); if t then t[barPrefix .. "BackgroundOpacity"] = tonumber(v) or 50; applyFn() end end,
    })

    inner:Finalize()
end

local function buildBorderTab(inner, barPrefix, applyFn, dbFn, getDBFn)
    dbFn = dbFn or ensureUFDB
    getDBFn = getDBFn or getUFDB

    inner:AddBarBorderSelector({
        label = "Border Style",
        includeNone = true,
        get = function() local t = getDBFn() or {}; return t[barPrefix .. "BorderStyle"] or "square" end,
        set = function(v) local t = dbFn(); if t then t[barPrefix .. "BorderStyle"] = v or "square"; applyFn() end end,
        getHiddenEdges = function() local t = getDBFn() or {}; return t[barPrefix .. "BorderHiddenEdges"] end,
        setHiddenEdges = function(v) local t = dbFn(); if t then t[barPrefix .. "BorderHiddenEdges"] = v; applyFn() end end,
    })

    inner:AddToggleColorPicker({
        label = "Border Tint",
        get = function() local t = getDBFn() or {}; return not not t[barPrefix .. "BorderTintEnable"] end,
        set = function(v) local t = dbFn(); if t then t[barPrefix .. "BorderTintEnable"] = not not v; applyFn() end end,
        getColor = function() local t = getDBFn() or {}; local c = t[barPrefix .. "BorderTintColor"] or {1,1,1,1}; return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 end,
        setColor = function(r,g,b,a) local t = dbFn(); if t then t[barPrefix .. "BorderTintColor"] = {r or 1, g or 1, b or 1, a or 1}; applyFn() end end,
        hasAlpha = true,
    })

    inner:AddSlider({
        label = "Border Thickness",
        min = 1, max = 8, step = 0.5, precision = 1,
        get = function() local t = getDBFn() or {}; local v = tonumber(t[barPrefix .. "BorderThickness"]) or 1; return math.max(1, math.min(8, math.floor(v * 2 + 0.5) / 2)) end,
        set = function(v) local t = dbFn(); if t then t[barPrefix .. "BorderThickness"] = math.max(1, math.min(8, math.floor((tonumber(v) or 1) * 2 + 0.5) / 2)); applyFn() end end,
    })

    inner:AddDualSlider({
        label = "Border Inset",
        sliderA = {
            axisLabel = "H", min = -4, max = 4, step = 1,
            get = function() local t = getDBFn() or {}; return tonumber(t[barPrefix .. "BorderInsetH"]) or tonumber(t[barPrefix .. "BorderInset"]) or 0 end,
            set = function(v) local t = dbFn(); if t then t[barPrefix .. "BorderInsetH"] = tonumber(v) or 0; applyFn() end end,
            minLabel = "-4", maxLabel = "+4",
        },
        sliderB = {
            axisLabel = "V", min = -4, max = 4, step = 1,
            get = function() local t = getDBFn() or {}; return tonumber(t[barPrefix .. "BorderInsetV"]) or tonumber(t[barPrefix .. "BorderInset"]) or 0 end,
            set = function(v) local t = dbFn(); if t then t[barPrefix .. "BorderInsetV"] = tonumber(v) or 0; applyFn() end end,
            minLabel = "-4", maxLabel = "+4",
        },
    })

    inner:Finalize()
end

local function buildTextTab(inner, textKey, applyFn, defaultAlignment, colorValues, colorOrder)
    defaultAlignment = defaultAlignment or "LEFT"
    colorValues = colorValues or UF.fontColorValues
    colorOrder = colorOrder or UF.fontColorOrder
    local stripped = textKey:gsub("^text", "")
    local hiddenKey = stripped:sub(1,1):lower() .. stripped:sub(2) .. "Hidden"

    inner:AddToggle({
        label = "Disable Text",
        get = function()
            local t = getUFDB() or {}
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
            local s = getTextDB(textKey) or {}
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
            local s = getTextDB(textKey) or {}
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
        min = 6, max = 48, step = 1,
        get = function()
            local s = getTextDB(textKey) or {}
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
            local s = getTextDB(textKey) or {}
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
            local s = getTextDB(textKey) or {}
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

    -- Determine initial mode and matching B-selector options
    local initialMode = (getTextDB(textKey) or {}).alignmentMode or "bar"
    local initialBValues = initialMode == "name" and UF.nameAnchorValues or UF.alignmentValues
    local initialBOrder  = initialMode == "name" and UF.nameAnchorOrder  or UF.alignmentOrder

    inner:AddDualSelector({
        label = "Alignment",
        key = textKey .. "AlignmentDual",
        selectorA = {
            values = UF.alignmentModeValues,
            order = UF.alignmentModeOrder,
            get = function()
                local s = getTextDB(textKey) or {}
                return s.alignmentMode or "bar"
            end,
            set = function(v)
                local t = ensureUFDB()
                if not t then return end
                t[textKey] = t[textKey] or {}
                t[textKey].alignmentMode = v or "bar"
                applyStyles()
                local dualSelector = inner:GetControl(textKey .. "AlignmentDual")
                if dualSelector then
                    if v == "name" then
                        dualSelector:SetOptionsB(UF.nameAnchorValues, UF.nameAnchorOrder)
                    else
                        dualSelector:SetOptionsB(UF.alignmentValues, UF.alignmentOrder)
                    end
                end
            end,
        },
        selectorB = {
            values = initialBValues,
            order = initialBOrder,
            get = function()
                local s = getTextDB(textKey) or {}
                local mode = s.alignmentMode or "bar"
                if mode == "name" then
                    return s.nameAnchor or "RIGHT_OF_NAME"
                else
                    return s.alignment or defaultAlignment
                end
            end,
            set = function(v)
                local t = ensureUFDB()
                if not t then return end
                t[textKey] = t[textKey] or {}
                local mode = t[textKey].alignmentMode or "bar"
                if mode == "name" then
                    t[textKey].nameAnchor = v or "RIGHT_OF_NAME"
                else
                    t[textKey].alignment = v or defaultAlignment
                end
                applyStyles()
            end,
        },
    })

    inner:AddDualSlider({
        label = "Offset",
        sliderA = {
            axisLabel = "X",
            min = -100, max = 100, step = 1,
            get = function()
                local s = getTextDB(textKey) or {}
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
                local s = getTextDB(textKey) or {}
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
-- Renderer Function
--------------------------------------------------------------------------------

function UF.RenderBoss(panel, scrollContent)
    panel:ClearContent()

    local builder = SettingsBuilder:CreateFor(scrollContent)
    panel._currentBuilder = builder

    builder:SetOnRefresh(function()
        UF.RenderBoss(panel, scrollContent)
    end)

    --------------------------------------------------------------------------------
    -- Parent-Level Settings
    --------------------------------------------------------------------------------

    builder:AddToggle({
        label = "Hide Blizzard Frame Art & Animations",
        description = "REQUIRED for custom borders. Hides default frame art.",
        emphasized = true,
        get = function() local t = getUFDB() or {}; return not not t.useCustomBorders end,
        set = function(v) local t = ensureUFDB(); if t then t.useCustomBorders = not not v; applyBarTextures() end end,
        infoIcon = UF.TOOLTIPS.hideBlizzardArt,
    })

    builder:AddToggle({
        label = "Use Larger Frame",
        description = "Uses the larger Boss frame variant (Edit Mode setting).",
        get = function()
            return UF.getUseLargerFrame(COMPONENT_ID)
        end,
        set = function(v)
            UF.setUseLargerFrame(COMPONENT_ID, v)
        end,
    })

    builder:AddSlider({
        label = "Scale",
        description = "Overall scale of boss frames.",
        min = 0.5, max = 2.0, step = 0.05, precision = 2,
        get = function() local t = getUFDB() or {}; return tonumber(t.scale) or 1.0 end,
        set = function(v) local t = ensureUFDB(); if t then t.scale = tonumber(v) or 1.0; applyStyles() end end,
        minLabel = "0.5x", maxLabel = "2.0x",
    })

    --------------------------------------------------------------------------------
    -- Health Bar (4 tabs: Style, Border, % Text, Value Text)
    --------------------------------------------------------------------------------

    builder:AddCollapsibleSection({
        title = "Health Bar",
        componentId = COMPONENT_ID,
        sectionKey = "healthBar",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddTabbedSection({
                tabs = {
                    { key = "style", label = "Style" },
                    { key = "border", label = "Border" },
                    { key = "percentText", label = "% Text" },
                    { key = "valueText", label = "Value Text" },
                    { key = "visibility", label = "Visibility" },
                },
                componentId = COMPONENT_ID,
                sectionKey = "healthBar_tabs",
                buildContent = {
                    style = function(cf, tabInner) buildStyleTab(tabInner, "healthBar", applyBarTextures) end,
                    border = function(cf, tabInner) buildBorderTab(tabInner, "healthBar", applyBarTextures) end,
                    visibility = function(cf, tabInner)
                        tabInner:AddToggle({
                            label = "Hide the Bar but not its Text",
                            get = function()
                                local t = getUFDB() or {}
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
                        tabInner:Finalize()
                    end,
                    percentText = function(cf, tabInner)
                        buildTextTab(tabInner, "textHealthPercent", applyHealthText, "LEFT", UF.fontColorHealthValues, UF.fontColorHealthOrder)
                    end,
                    valueText = function(cf, tabInner)
                        buildTextTab(tabInner, "textHealthValue", applyHealthText, "RIGHT", UF.fontColorHealthValues, UF.fontColorHealthOrder)
                    end,
                },
            })
            inner:Finalize()
        end,
    })

    --------------------------------------------------------------------------------
    -- Power Bar (7 tabs: Positioning, Sizing, Style, Border, Visibility, % Text, Value Text)
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
                                get = function() local t = getUFDB() or {}; return tonumber(t.powerBarOffsetX) or 0 end,
                                set = function(v) local t = ensureUFDB(); if t then t.powerBarOffsetX = tonumber(v) or 0; applyBarTextures() end end,
                            },
                            sliderB = {
                                axisLabel = "Y",
                                min = -100, max = 100, step = 1,
                                get = function() local t = getUFDB() or {}; return tonumber(t.powerBarOffsetY) or 0 end,
                                set = function(v) local t = ensureUFDB(); if t then t.powerBarOffsetY = tonumber(v) or 0; applyBarTextures() end end,
                            },
                        })
                        tabInner:Finalize()
                    end,
                    sizing = function(cf, tabInner)
                        tabInner:AddSlider({
                            label = "Height %",
                            min = 10, max = 200, step = 5,
                            get = function() local t = getUFDB() or {}; return tonumber(t.powerBarHeightPct) or 100 end,
                            set = function(v) local t = ensureUFDB(); if t then t.powerBarHeightPct = tonumber(v) or 100; applyBarTextures() end end,
                        })
                        tabInner:Finalize()
                    end,
                    style = function(cf, tabInner) buildStyleTab(tabInner, "powerBar", applyBarTextures, UF.powerColorValues, UF.powerColorOrder) end,
                    border = function(cf, tabInner) buildBorderTab(tabInner, "powerBar", applyBarTextures) end,
                    visibility = function(cf, tabInner)
                        tabInner:AddToggle({
                            label = "Hide Power Bar",
                            get = function() local t = getUFDB() or {}; return not not t.powerBarHidden end,
                            set = function(v) local t = ensureUFDB(); if t then t.powerBarHidden = v and true or false; applyBarTextures() end end,
                        })
                        tabInner:AddToggle({
                            label = "Hide the Bar but not its Text",
                            get = function()
                                local t = getUFDB() or {}
                                return not not t.powerBarHideTextureOnly
                            end,
                            set = function(v)
                                local t = ensureUFDB()
                                if not t then return end
                                t.powerBarHideTextureOnly = v and true or false
                                applyBarTextures()
                            end,
                            infoIcon = {
                                tooltipTitle = "Hide the Bar but not its Text",
                                tooltipText = "Hides the bar texture and background, showing only the text overlay. Useful for a number-only display of power.",
                            },
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
    -- Cast Bar (7 tabs: Positioning, Sizing, Style, Border, Icon, Spell Name, Visibility)
    --------------------------------------------------------------------------------

    local castBarTabs = UF.getCastBarTabs(COMPONENT_ID, {
        fillLineVisible = function()
            local t = getCastBarDB() or {}
            return (t.castBarMode or "default") == "textFill"
        end,
    })

    builder:AddCollapsibleSection({
        title = "Cast Bar",
        componentId = COMPONENT_ID,
        sectionKey = "castBar",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            local tabbedRef
            inner:AddSelector({
                label = "Mode",
                description = "Choose how the cast bar is displayed.",
                values = { default = "Default Cast Bar", textFill = "Text-Fill Cast Bar" },
                order = { "default", "textFill" },
                emphasized = true,
                get = function() local t = getCastBarDB() or {}; return t.castBarMode or "default" end,
                set = function(v)
                    local t = ensureCastBarDB()
                    if t then t.castBarMode = v; applyCastBar() end
                    if tabbedRef and tabbedRef.RefreshTabVisibility then
                        tabbedRef:RefreshTabVisibility()
                    end
                end,
            })
            tabbedRef = inner:AddTabbedSection({
                tabs = castBarTabs,
                componentId = COMPONENT_ID,
                sectionKey = "castBar_tabs",
                buildContent = {
                    positioning = function(cf, tabInner)
                        tabInner:AddSelector({
                            label = "Anchor To",
                            values = {
                                ["default"] = "Under Frame (Default)",
                                ["leftOfFrame"] = "Left of Frame",
                                ["centeredUnderPower"] = "Centered Under Power Bar",
                                ["underBossName"] = "Under Boss Name",
                            },
                            order = {"default", "leftOfFrame", "centeredUnderPower", "underBossName"},
                            get = function() local t = getCastBarDB() or {}; return t.anchorMode or "default" end,
                            set = function(v) local t = ensureCastBarDB(); if t then t.anchorMode = v; if addon.MarkBossCastBarOnSideDirty then addon.MarkBossCastBarOnSideDirty() end; applyCastBar() end end,
                        })
                        tabInner:AddDualSlider({
                            label = "Offset",
                            sliderA = {
                                axisLabel = "X",
                                min = -200, max = 200, step = 1,
                                get = function() local t = getCastBarDB() or {}; return tonumber(t.offsetX) or 0 end,
                                set = function(v) local t = ensureCastBarDB(); if t then t.offsetX = tonumber(v) or 0; applyCastBar() end end,
                            },
                            sliderB = {
                                axisLabel = "Y",
                                min = -200, max = 200, step = 1,
                                get = function() local t = getCastBarDB() or {}; return tonumber(t.offsetY) or 0 end,
                                set = function(v) local t = ensureCastBarDB(); if t then t.offsetY = tonumber(v) or 0; applyCastBar() end end,
                            },
                        })
                        tabInner:Finalize()
                    end,
                    sizing = function(cf, tabInner)
                        tabInner:AddSlider({
                            label = "Scale %", min = 50, max = 150, step = 1,
                            get = function() local t = getCastBarDB() or {}; return tonumber(t.castBarScale) or 100 end,
                            set = function(v) local t = ensureCastBarDB(); if t then t.castBarScale = tonumber(v) or 100; applyCastBar() end end,
                        })
                        tabInner:Finalize()
                    end,
                    style = function(cf, tabInner)
                        tabInner:AddBarTextureSelector({
                            label = "Foreground Texture",
                            get = function() local t = getCastBarDB() or {}; return t.castBarTexture or "default" end,
                            set = function(v) local t = ensureCastBarDB(); if t then t.castBarTexture = v or "default"; applyCastBar() end end,
                        })
                        tabInner:AddSelectorColorPicker({
                            label = "Foreground Color", values = UF.castBarColorValues, order = UF.castBarColorOrder,
                            get = function() local t = getCastBarDB() or {}; return t.castBarColorMode or "default" end,
                            set = function(v) local t = ensureCastBarDB(); if t then t.castBarColorMode = v or "default"; applyCastBar() end end,
                            getColor = function() local t = getCastBarDB() or {}; local c = t.castBarTint or {1,1,1,1}; return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 end,
                            setColor = function(r,g,b,a) local t = ensureCastBarDB(); if t then t.castBarTint = {r,g,b,a}; applyCastBar() end end,
                            customValue = "custom", hasAlpha = true,
                        })
                        tabInner:AddSpacer(8)
                        tabInner:AddBarTextureSelector({
                            label = "Background Texture",
                            get = function() local t = getCastBarDB() or {}; return t.castBarBackgroundTexture or "default" end,
                            set = function(v) local t = ensureCastBarDB(); if t then t.castBarBackgroundTexture = v or "default"; applyCastBar() end end,
                        })
                        tabInner:AddSelectorColorPicker({
                            label = "Background Color", values = UF.bgColorValues, order = UF.bgColorOrder,
                            get = function() local t = getCastBarDB() or {}; return t.castBarBackgroundColorMode or "default" end,
                            set = function(v) local t = ensureCastBarDB(); if t then t.castBarBackgroundColorMode = v or "default"; applyCastBar() end end,
                            getColor = function() local t = getCastBarDB() or {}; local c = t.castBarBackgroundTint or {0,0,0,1}; return c[1] or 0, c[2] or 0, c[3] or 0, c[4] or 1 end,
                            setColor = function(r,g,b,a) local t = ensureCastBarDB(); if t then t.castBarBackgroundTint = {r,g,b,a}; applyCastBar() end end,
                            customValue = "custom", hasAlpha = true,
                        })
                        tabInner:AddSlider({
                            label = "Background Opacity", min = 0, max = 100, step = 1,
                            get = function() local t = getCastBarDB() or {}; return tonumber(t.castBarBackgroundOpacity) or 50 end,
                            set = function(v) local t = ensureCastBarDB(); if t then t.castBarBackgroundOpacity = tonumber(v) or 50; applyCastBar() end end,
                        })
                        tabInner:Finalize()
                    end,
                    fillLine = function(cf, tabInner)
                        tabInner:AddDescription(
                            "The fill color used in Text-Fill Mode is decided by the Spell Name text's font color.",
                            { color = {1, 0.82, 0}, fontSize = 14, topPadding = 4 }
                        )
                        tabInner:AddColorPicker({
                            label = "Unfilled Text Color",
                            get = function()
                                local t = getCastBarDB() or {}
                                local c = t.textFillUnfilledTextColor or {0.5, 0.5, 0.5, 1}
                                return c[1] or 0.5, c[2] or 0.5, c[3] or 0.5, c[4] or 1
                            end,
                            set = function(r, g, b, a)
                                local t = ensureCastBarDB()
                                if t then
                                    t.textFillUnfilledTextColor = {r, g, b, a}
                                    applyCastBar()
                                end
                            end,
                            hasAlpha = true,
                        })
                        tabInner:AddSlider({
                            label = "Line Height", min = 1, max = 10, step = 1,
                            get = function() local t = getCastBarDB() or {}; return tonumber(t.textFillLineHeight) or 2 end,
                            set = function(v) local t = ensureCastBarDB(); if t then t.textFillLineHeight = tonumber(v) or 2; applyCastBar() end end,
                        })
                        tabInner:AddSlider({
                            label = "End Cap Size", min = 2, max = 20, step = 1,
                            get = function() local t = getCastBarDB() or {}; return tonumber(t.textFillEndCapSize) or 6 end,
                            set = function(v) local t = ensureCastBarDB(); if t then t.textFillEndCapSize = tonumber(v) or 6; applyCastBar() end end,
                        })
                        tabInner:Finalize()
                    end,
                    spark = function(cf, tabInner)
                        tabInner:AddToggle({
                            label = "Hide Spark",
                            get = function() local t = getCastBarDB() or {}; return not not t.castBarSparkHidden end,
                            set = function(v) local t = ensureCastBarDB(); if t then t.castBarSparkHidden = v and true or false; applyCastBar() end end,
                        })
                        tabInner:AddSelectorColorPicker({
                            label = "Spark Color",
                            values = { ["default"] = "Default", ["custom"] = "Custom" },
                            order = { "default", "custom" },
                            get = function() local t = getCastBarDB() or {}; return t.castBarSparkColorMode or "default" end,
                            set = function(v) local t = ensureCastBarDB(); if t then t.castBarSparkColorMode = v or "default"; applyCastBar() end end,
                            getColor = function() local t = getCastBarDB() or {}; local c = t.castBarSparkTint or {1,1,1,1}; return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 end,
                            setColor = function(r,g,b,a) local t = ensureCastBarDB(); if t then t.castBarSparkTint = {r,g,b,a}; applyCastBar() end end,
                            customValue = "custom", hasAlpha = true,
                        })
                        tabInner:Finalize()
                    end,
                    border = function(cf, tabInner)
                        tabInner:AddToggle({
                            label = "Enable Border",
                            get = function() local t = getCastBarDB() or {}; return not not t.castBarBorderEnable end,
                            set = function(v) local t = ensureCastBarDB(); if t then t.castBarBorderEnable = not not v; applyCastBar() end end,
                        })
                        tabInner:AddBarBorderSelector({
                            label = "Border Style",
                            includeNone = true,
                            get = function() local t = getCastBarDB() or {}; return t.castBarBorderStyle or "square" end,
                            set = function(v) local t = ensureCastBarDB(); if t then t.castBarBorderStyle = v or "square"; applyCastBar() end end,
                            getHiddenEdges = function() local t = getCastBarDB() or {}; return t.castBarBorderHiddenEdges end,
                            setHiddenEdges = function(v) local t = ensureCastBarDB(); if t then t.castBarBorderHiddenEdges = v; applyCastBar() end end,
                        })
                        tabInner:AddToggleColorPicker({
                            label = "Border Tint",
                            get = function() local t = getCastBarDB() or {}; return not not t.castBarBorderTintEnable end,
                            set = function(v) local t = ensureCastBarDB(); if t then t.castBarBorderTintEnable = not not v; applyCastBar() end end,
                            getColor = function() local t = getCastBarDB() or {}; local c = t.castBarBorderTintColor or {1,1,1,1}; return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 end,
                            setColor = function(r,g,b,a) local t = ensureCastBarDB(); if t then t.castBarBorderTintColor = {r,g,b,a}; applyCastBar() end end,
                            hasAlpha = true,
                        })
                        tabInner:AddSlider({
                            label = "Border Thickness", min = 1, max = 8, step = 0.5, precision = 1,
                            get = function() local t = getCastBarDB() or {}; local v = tonumber(t.castBarBorderThickness) or 1; return math.max(1, math.min(8, math.floor(v * 2 + 0.5) / 2)) end,
                            set = function(v) local t = ensureCastBarDB(); if t then t.castBarBorderThickness = math.max(1, math.min(8, math.floor((tonumber(v) or 1) * 2 + 0.5) / 2)); applyCastBar() end end,
                        })
                        tabInner:AddDualSlider({
                            label = "Border Inset",
                            sliderA = {
                                axisLabel = "H", min = -4, max = 4, step = 1,
                                get = function() local t = getCastBarDB() or {}; return tonumber(t.castBarBorderInsetH) or tonumber(t.castBarBorderInset) or 0 end,
                                set = function(v) local t = ensureCastBarDB(); if t then t.castBarBorderInsetH = tonumber(v) or 0; applyCastBar() end end,
                                minLabel = "-4", maxLabel = "+4",
                            },
                            sliderB = {
                                axisLabel = "V", min = -4, max = 4, step = 1,
                                get = function() local t = getCastBarDB() or {}; return tonumber(t.castBarBorderInsetV) or tonumber(t.castBarBorderInset) or 0 end,
                                set = function(v) local t = ensureCastBarDB(); if t then t.castBarBorderInsetV = tonumber(v) or 0; applyCastBar() end end,
                                minLabel = "-4", maxLabel = "+4",
                            },
                        })
                        tabInner:Finalize()
                    end,
                    icon = function(cf, tabInner)
                        tabInner:AddToggle({
                            label = "Hide Icon",
                            get = function() local t = getCastBarDB() or {}; return not not t.iconDisabled end,
                            set = function(v) local t = ensureCastBarDB(); if t then t.iconDisabled = v and true or false; applyCastBar() end end,
                        })
                        tabInner:AddToggle({
                            label = "Hide Icon Backdrop (Shield)",
                            get = function() local t = getCastBarDB() or {}; return not not t.castBarBorderShieldHidden end,
                            set = function(v) local t = ensureCastBarDB(); if t then t.castBarBorderShieldHidden = v and true or false; applyCastBar() end end,
                        })
                        tabInner:AddSlider({
                            label = "Icon Size", min = 10, max = 64, step = 1,
                            get = function() local t = getCastBarDB() or {}; return tonumber(t.iconWidth) or tonumber(t.iconHeight) or 24 end,
                            set = function(v) local t = ensureCastBarDB(); if t then t.iconWidth = tonumber(v) or 24; t.iconHeight = tonumber(v) or 24; applyCastBar() end end,
                        })
                        tabInner:AddDualSlider({
                            label = "Icon Offset",
                            sliderA = {
                                axisLabel = "X",
                                min = -100, max = 100, step = 1,
                                get = function() local t = getCastBarDB() or {}; return tonumber(t.castBarIconOffsetX) or 0 end,
                                set = function(v) local t = ensureCastBarDB(); if t then t.castBarIconOffsetX = tonumber(v) or 0; applyCastBar() end end,
                            },
                            sliderB = {
                                axisLabel = "Y",
                                min = -100, max = 100, step = 1,
                                get = function() local t = getCastBarDB() or {}; return tonumber(t.castBarIconOffsetY) or 0 end,
                                set = function(v) local t = ensureCastBarDB(); if t then t.castBarIconOffsetY = tonumber(v) or 0; applyCastBar() end end,
                            },
                        })
                        tabInner:Finalize()
                    end,
                    spellName = function(cf, tabInner)
                        tabInner:AddToggle({
                            label = "Hide Spell Name",
                            get = function() local t = getCastBarDB() or {}; return not not t.castBarSpellNameHidden end,
                            set = function(v) local t = ensureCastBarDB(); if t then t.castBarSpellNameHidden = v and true or false; applyCastBar() end end,
                        })
                        tabInner:AddToggle({
                            label = "Hide Spell Name Border",
                            get = function() local t = getCastBarDB() or {}; return not not t.hideSpellNameBorder end,
                            set = function(v) local t = ensureCastBarDB(); if t then t.hideSpellNameBorder = v and true or false; applyCastBar() end end,
                        })
                        tabInner:AddFontSelector({
                            label = "Spell Name Font",
                            get = function() local t = getCastBarDB() or {}; local s = t.spellNameText or {}; return s.fontFace or "FRIZQT__" end,
                            set = function(v) local t = ensureCastBarDB(); if t then t.spellNameText = t.spellNameText or {}; t.spellNameText.fontFace = v; applyCastBar() end end,
                        })
                        tabInner:AddSelector({
                            label = "Spell Name Style", values = UF.fontStyleValues, order = UF.fontStyleOrder,
                            get = function() local t = getCastBarDB() or {}; local s = t.spellNameText or {}; return s.style or "OUTLINE" end,
                            set = function(v) local t = ensureCastBarDB(); if t then t.spellNameText = t.spellNameText or {}; t.spellNameText.style = v; applyCastBar() end end,
                        })
                        tabInner:AddSlider({
                            label = "Spell Name Size", min = 6, max = 32, step = 1,
                            get = function() local t = getCastBarDB() or {}; local s = t.spellNameText or {}; return tonumber(s.size) or 10 end,
                            set = function(v) local t = ensureCastBarDB(); if t then t.spellNameText = t.spellNameText or {}; t.spellNameText.size = tonumber(v) or 10; applyCastBar() end end,
                        })
                        tabInner:AddSelectorColorPicker({
                            label = "Spell Name Color",
                            values = UF.fontColorCastBarNonPlayerValues, order = UF.fontColorCastBarNonPlayerOrder,
                            get = function() local t = getCastBarDB() or {}; local s = t.spellNameText or {}; return s.colorMode or "default" end,
                            set = function(v) local t = ensureCastBarDB(); if t then t.spellNameText = t.spellNameText or {}; t.spellNameText.colorMode = v or "default"; applyCastBar() end end,
                            getColor = function() local t = getCastBarDB() or {}; local s = t.spellNameText or {}; local c = s.color or {1,1,1,1}; return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 end,
                            setColor = function(r,g,b,a) local t = ensureCastBarDB(); if t then t.spellNameText = t.spellNameText or {}; t.spellNameText.color = {r,g,b,a}; applyCastBar() end end,
                            customValue = {"custom", "customGradient"},
                            hasAlpha = true,
                        })
                        tabInner:Finalize()
                    end,
                    castTime = function(cf, tabInner)
                        tabInner:AddFontSelector({
                            label = "Cast Time Font",
                            get = function() local t = getCastBarDB() or {}; local s = t.castTimeText or {}; return s.fontFace or "FRIZQT__" end,
                            set = function(v) local t = ensureCastBarDB(); if t then t.castTimeText = t.castTimeText or {}; t.castTimeText.fontFace = v; applyCastBar() end end,
                        })
                        tabInner:AddSelector({
                            label = "Cast Time Style", values = UF.fontStyleValues, order = UF.fontStyleOrder,
                            get = function() local t = getCastBarDB() or {}; local s = t.castTimeText or {}; return s.style or "OUTLINE" end,
                            set = function(v) local t = ensureCastBarDB(); if t then t.castTimeText = t.castTimeText or {}; t.castTimeText.style = v; applyCastBar() end end,
                        })
                        tabInner:AddSlider({
                            label = "Cast Time Size", min = 6, max = 32, step = 1,
                            get = function() local t = getCastBarDB() or {}; local s = t.castTimeText or {}; return tonumber(s.size) or 10 end,
                            set = function(v) local t = ensureCastBarDB(); if t then t.castTimeText = t.castTimeText or {}; t.castTimeText.size = tonumber(v) or 10; applyCastBar() end end,
                        })
                        tabInner:AddColorPicker({
                            label = "Cast Time Color",
                            get = function() local t = getCastBarDB() or {}; local s = t.castTimeText or {}; local c = s.color or {1,1,1,1}; return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 end,
                            set = function(r,g,b,a) local t = ensureCastBarDB(); if t then t.castTimeText = t.castTimeText or {}; t.castTimeText.color = {r,g,b,a}; applyCastBar() end end,
                            hasAlpha = true,
                        })
                        tabInner:Finalize()
                    end,
                    visibility = function(cf, tabInner)
                        tabInner:AddToggle({
                            label = "Hide Cast Bar",
                            get = function() local t = getCastBarDB() or {}; return not not t.castBarHidden end,
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
    -- Name & Level Text (4 tabs: Backdrop, Border, Name Text, Level Text)
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
                            get = function() local t = getUFDB() or {}; return not not t.nameBackdropEnabled end,
                            set = function(v) local t = ensureUFDB(); if t then t.nameBackdropEnabled = not not v; applyNameLevelText() end end,
                        })
                        tabInner:AddBarTextureSelector({
                            label = "Backdrop Texture",
                            get = function() local t = getUFDB() or {}; return t.nameBackdropTexture or "" end,
                            set = function(v) local t = ensureUFDB(); if t then t.nameBackdropTexture = v; applyNameLevelText() end end,
                        })
                        tabInner:AddSelectorColorPicker({
                            label = "Backdrop Color",
                            values = UF.bgColorValues, order = UF.bgColorOrder,
                            get = function() local t = getUFDB() or {}; return t.nameBackdropColorMode or "default" end,
                            set = function(v) local t = ensureUFDB(); if t then t.nameBackdropColorMode = v or "default"; applyNameLevelText() end end,
                            getColor = function() local t = getUFDB() or {}; local c = t.nameBackdropTint or {1,1,1,1}; return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 end,
                            setColor = function(r,g,b,a) local t = ensureUFDB(); if t then t.nameBackdropTint = {r,g,b,a}; applyNameLevelText() end end,
                            customValue = "custom", hasAlpha = true,
                        })
                        tabInner:AddSlider({
                            label = "Backdrop Width (%)", min = 25, max = 300, step = 1,
                            get = function() local t = getUFDB() or {}; return tonumber(t.nameBackdropWidthPct) or 100 end,
                            set = function(v) local t = ensureUFDB(); if t then t.nameBackdropWidthPct = tonumber(v) or 100; applyNameLevelText() end end,
                        })
                        tabInner:AddSlider({
                            label = "Backdrop Opacity", min = 0, max = 100, step = 1,
                            get = function() local t = getUFDB() or {}; return tonumber(t.nameBackdropOpacity) or 50 end,
                            set = function(v) local t = ensureUFDB(); if t then t.nameBackdropOpacity = tonumber(v) or 50; applyNameLevelText() end end,
                        })
                        tabInner:Finalize()
                    end,
                    border = function(cf, tabInner)
                        tabInner:AddToggle({
                            label = "Enable Border",
                            get = function() local t = getUFDB() or {}; return not not t.nameBackdropBorderEnabled end,
                            set = function(v) local t = ensureUFDB(); if t then t.nameBackdropBorderEnabled = not not v; applyNameLevelText() end end,
                        })
                        tabInner:AddBarBorderSelector({
                            label = "Border Style",
                            includeNone = true,
                            get = function() local t = getUFDB() or {}; return t.nameBackdropBorderStyle or "square" end,
                            set = function(v) local t = ensureUFDB(); if t then t.nameBackdropBorderStyle = v or "square"; applyNameLevelText() end end,
                            getHiddenEdges = function() local t = getUFDB() or {}; return t.nameBackdropBorderHiddenEdges end,
                            setHiddenEdges = function(v) local t = ensureUFDB(); if t then t.nameBackdropBorderHiddenEdges = v; applyNameLevelText() end end,
                        })
                        tabInner:AddToggleColorPicker({
                            label = "Border Tint",
                            get = function() local t = getUFDB() or {}; return not not t.nameBackdropBorderTintEnable end,
                            set = function(v) local t = ensureUFDB(); if t then t.nameBackdropBorderTintEnable = not not v; applyNameLevelText() end end,
                            getColor = function() local t = getUFDB() or {}; local c = t.nameBackdropBorderTintColor or {1,1,1,1}; return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 end,
                            setColor = function(r,g,b,a) local t = ensureUFDB(); if t then t.nameBackdropBorderTintColor = {r,g,b,a}; applyNameLevelText() end end,
                            hasAlpha = true,
                        })
                        tabInner:AddSlider({
                            label = "Border Thickness", min = 1, max = 8, step = 0.5, precision = 1,
                            get = function() local t = getUFDB() or {}; local v = tonumber(t.nameBackdropBorderThickness) or 1; return math.max(1, math.min(8, math.floor(v * 2 + 0.5) / 2)) end,
                            set = function(v) local t = ensureUFDB(); if t then t.nameBackdropBorderThickness = math.max(1, math.min(8, math.floor((tonumber(v) or 1) * 2 + 0.5) / 2)); applyNameLevelText() end end,
                        })
                        tabInner:AddDualSlider({
                            label = "Border Inset",
                            sliderA = {
                                axisLabel = "H", min = -4, max = 4, step = 1,
                                get = function() local t = getUFDB() or {}; return tonumber(t.nameBackdropBorderInsetH) or tonumber(t.nameBackdropBorderInset) or 0 end,
                                set = function(v) local t = ensureUFDB(); if t then t.nameBackdropBorderInsetH = tonumber(v) or 0; applyNameLevelText() end end,
                                minLabel = "-4", maxLabel = "+4",
                            },
                            sliderB = {
                                axisLabel = "V", min = -4, max = 4, step = 1,
                                get = function() local t = getUFDB() or {}; return tonumber(t.nameBackdropBorderInsetV) or tonumber(t.nameBackdropBorderInset) or 0 end,
                                set = function(v) local t = ensureUFDB(); if t then t.nameBackdropBorderInsetV = tonumber(v) or 0; applyNameLevelText() end end,
                                minLabel = "-4", maxLabel = "+4",
                            },
                        })
                        tabInner:Finalize()
                    end,
                    nameText = function(cf, tabInner)
                        tabInner:AddToggle({
                            label = "Disable Name Text",
                            get = function() local t = getUFDB() or {}; return not not t.nameTextHidden end,
                            set = function(v) local t = ensureUFDB(); if t then t.nameTextHidden = v and true or false; applyNameLevelText() end end,
                        })
                        tabInner:AddSlider({
                            label = "Name Container Width", min = 80, max = 500, step = 5,
                            get = function() local s = getNameLevelDB("textName") or {}; return tonumber(s.containerWidthPct) or 100 end,
                            set = function(v) local t = ensureNameLevelDB("textName"); if t then t.containerWidthPct = tonumber(v) or 100; applyNameLevelText() end end,
                        })
                        tabInner:AddFontSelector({
                            label = "Name Text Font",
                            get = function() local s = getNameLevelDB("textName") or {}; return s.fontFace or "FRIZQT__" end,
                            set = function(v) local t = ensureNameLevelDB("textName"); if t then t.fontFace = v; applyNameLevelText() end end,
                        })
                        tabInner:AddSelector({
                            label = "Name Text Style", values = UF.fontStyleValues, order = UF.fontStyleOrder,
                            get = function() local s = getNameLevelDB("textName") or {}; return s.style or "OUTLINE" end,
                            set = function(v) local t = ensureNameLevelDB("textName"); if t then t.style = v; applyNameLevelText() end end,
                        })
                        tabInner:AddSlider({
                            label = "Name Text Size", min = 6, max = 48, step = 1,
                            get = function() local s = getNameLevelDB("textName") or {}; return tonumber(s.size) or 14 end,
                            set = function(v) local t = ensureNameLevelDB("textName"); if t then t.size = tonumber(v) or 14; applyNameLevelText() end end,
                        })
                        tabInner:AddSelectorColorPicker({
                            label = "Name Text Color",
                            values = UF.fontColorValues, order = UF.fontColorOrder,
                            get = function() local s = getNameLevelDB("textName") or {}; return s.colorMode or "default" end,
                            set = function(v) local t = ensureNameLevelDB("textName"); if t then t.colorMode = v or "default"; applyNameLevelText() end end,
                            getColor = function() local s = getNameLevelDB("textName") or {}; local c = s.color or {1,0.82,0,1}; return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 end,
                            setColor = function(r,g,b,a) local t = ensureNameLevelDB("textName"); if t then t.color = {r,g,b,a}; applyNameLevelText() end end,
                            customValue = "custom", hasAlpha = true,
                        })
                        tabInner:AddSelector({
                            label = "Name Text Alignment", values = UF.alignmentValues, order = UF.alignmentOrder,
                            get = function() local s = getNameLevelDB("textName") or {}; return s.alignment or "LEFT" end,
                            set = function(v) local t = ensureNameLevelDB("textName"); if t then t.alignment = v or "LEFT"; applyNameLevelText() end end,
                        })
                        tabInner:AddDualSlider({
                            label = "Name Text Offset",
                            sliderA = {
                                axisLabel = "X",
                                min = -100, max = 100, step = 1,
                                get = function() local s = getNameLevelDB("textName") or {}; local o = s.offset or {}; return tonumber(o.x) or 0 end,
                                set = function(v) local t = ensureNameLevelDB("textName"); if t then t.offset = t.offset or {}; t.offset.x = tonumber(v) or 0; applyNameLevelText() end end,
                            },
                            sliderB = {
                                axisLabel = "Y",
                                min = -100, max = 100, step = 1,
                                get = function() local s = getNameLevelDB("textName") or {}; local o = s.offset or {}; return tonumber(o.y) or 0 end,
                                set = function(v) local t = ensureNameLevelDB("textName"); if t then t.offset = t.offset or {}; t.offset.y = tonumber(v) or 0; applyNameLevelText() end end,
                            },
                        })
                        tabInner:Finalize()
                    end,
                    levelText = function(cf, tabInner)
                        tabInner:AddToggle({
                            label = "Disable Level Text",
                            get = function() local t = getUFDB() or {}; return not not t.levelTextHidden end,
                            set = function(v) local t = ensureUFDB(); if t then t.levelTextHidden = v and true or false; applyNameLevelText() end end,
                        })
                        tabInner:AddFontSelector({
                            label = "Level Text Font",
                            get = function() local s = getNameLevelDB("textLevel") or {}; return s.fontFace or "FRIZQT__" end,
                            set = function(v) local t = ensureNameLevelDB("textLevel"); if t then t.fontFace = v; applyNameLevelText() end end,
                        })
                        tabInner:AddSelector({
                            label = "Level Text Style", values = UF.fontStyleValues, order = UF.fontStyleOrder,
                            get = function() local s = getNameLevelDB("textLevel") or {}; return s.style or "OUTLINE" end,
                            set = function(v) local t = ensureNameLevelDB("textLevel"); if t then t.style = v; applyNameLevelText() end end,
                        })
                        tabInner:AddSlider({
                            label = "Level Text Size", min = 6, max = 48, step = 1,
                            get = function() local s = getNameLevelDB("textLevel") or {}; return tonumber(s.size) or 14 end,
                            set = function(v) local t = ensureNameLevelDB("textLevel"); if t then t.size = tonumber(v) or 14; applyNameLevelText() end end,
                        })
                        tabInner:AddSelectorColorPicker({
                            label = "Level Text Color", values = UF.fontColorValues, order = UF.fontColorOrder,
                            get = function() local s = getNameLevelDB("textLevel") or {}; return s.colorMode or "default" end,
                            set = function(v) local t = ensureNameLevelDB("textLevel"); if t then t.colorMode = v or "default"; applyNameLevelText() end end,
                            getColor = function() local s = getNameLevelDB("textLevel") or {}; local c = s.color or {1,0.82,0,1}; return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 end,
                            setColor = function(r,g,b,a) local t = ensureNameLevelDB("textLevel"); if t then t.color = {r,g,b,a}; applyNameLevelText() end end,
                            customValue = "custom", hasAlpha = true,
                        })
                        tabInner:AddDualSlider({
                            label = "Level Text Offset",
                            sliderA = {
                                axisLabel = "X",
                                min = -100, max = 100, step = 1,
                                get = function() local s = getNameLevelDB("textLevel") or {}; local o = s.offset or {}; return tonumber(o.x) or 0 end,
                                set = function(v) local t = ensureNameLevelDB("textLevel"); if t then t.offset = t.offset or {}; t.offset.x = tonumber(v) or 0; applyNameLevelText() end end,
                            },
                            sliderB = {
                                axisLabel = "Y",
                                min = -100, max = 100, step = 1,
                                get = function() local s = getNameLevelDB("textLevel") or {}; local o = s.offset or {}; return tonumber(o.y) or 0 end,
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
    -- Visibility & Misc
    --------------------------------------------------------------------------------

    builder:AddCollapsibleSection({
        title = "Visibility & Misc",
        componentId = COMPONENT_ID,
        sectionKey = "visibilityMisc",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddToggle({
                label = "Hide Threat Tracker",
                get = function()
                    local t = getMiscDB() or {}
                    return not not t.hideBossThreatCounter
                end,
                set = function(v)
                    local t = ensureMiscDB()
                    if not t then return end
                    t.hideBossThreatCounter = v and true or false
                    if addon.ApplyBossThreatCounterVisibility then
                        addon.ApplyBossThreatCounterVisibility()
                    end
                end,
            })
            inner:AddToggle({
                label = "Hide Skull Icon",
                get = function()
                    local t = getMiscDB() or {}
                    return not not t.hideHighLevelIcon
                end,
                set = function(v)
                    local t = ensureMiscDB()
                    if not t then return end
                    t.hideHighLevelIcon = v and true or false
                    if addon.ApplyBossHighLevelIconVisibility then
                        addon.ApplyBossHighLevelIconVisibility()
                    end
                end,
            })
            inner:Finalize()
        end,
    })

    builder:Finalize()
end

addon.UI.SettingsPanel:RegisterRenderer("ufBoss", function(panel, scrollContent)
    UF.RenderBoss(panel, scrollContent)
end)

return UF.RenderBoss
