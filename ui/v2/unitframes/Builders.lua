-- Builders.lua - Shared tab content builders for Unit Frame TUI renderers
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.UnitFrames = addon.UI.UnitFrames or {}
local UF = addon.UI.UnitFrames

UF.Builders = UF.Builders or {}

--------------------------------------------------------------------------------
-- Bar Style Content Builder
--------------------------------------------------------------------------------
-- Builds: Foreground Texture → Foreground Color → Spacer → Background Texture →
--         Background Color → Background Opacity
-- Does NOT call Finalize() — callers do.

function UF.Builders.buildBarStyleContent(inner, barPrefix, ensureDBFn, applyFn, colorValues, colorOrder, colorInfoIcons)
    colorValues = colorValues or UF.healthColorValues
    colorOrder = colorOrder or UF.healthColorOrder
    colorInfoIcons = colorInfoIcons or UF.healthColorInfoIcons

    inner:AddDualBarStyleRow({
        label = "Foreground",
        getTexture = function()
            local t = ensureDBFn() or {}
            return t[barPrefix .. "Texture"] or "default"
        end,
        setTexture = function(v)
            local t = ensureDBFn()
            if not t then return end
            t[barPrefix .. "Texture"] = v or "default"
            applyFn()
        end,
        colorValues = colorValues,
        colorOrder = colorOrder,
        colorInfoIcons = colorInfoIcons,
        getColorMode = function()
            local t = ensureDBFn() or {}
            return t[barPrefix .. "ColorMode"] or "default"
        end,
        setColorMode = function(v)
            local t = ensureDBFn()
            if not t then return end
            t[barPrefix .. "ColorMode"] = v or "default"
            applyFn()
        end,
        getColor = function()
            local t = ensureDBFn() or {}
            local c = t[barPrefix .. "Tint"] or {1, 1, 1, 1}
            return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
        end,
        setColor = function(r, g, b, a)
            local t = ensureDBFn()
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
            local t = ensureDBFn() or {}
            return t[barPrefix .. "BackgroundTexture"] or "default"
        end,
        setTexture = function(v)
            local t = ensureDBFn()
            if not t then return end
            t[barPrefix .. "BackgroundTexture"] = v or "default"
            applyFn()
        end,
        colorValues = UF.bgColorValues,
        colorOrder = UF.bgColorOrder,
        getColorMode = function()
            local t = ensureDBFn() or {}
            return t[barPrefix .. "BackgroundColorMode"] or "default"
        end,
        setColorMode = function(v)
            local t = ensureDBFn()
            if not t then return end
            t[barPrefix .. "BackgroundColorMode"] = v or "default"
            applyFn()
        end,
        getColor = function()
            local t = ensureDBFn() or {}
            local c = t[barPrefix .. "BackgroundTint"] or {0, 0, 0, 1}
            return c[1] or 0, c[2] or 0, c[3] or 0, c[4] or 1
        end,
        setColor = function(r, g, b, a)
            local t = ensureDBFn()
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
            local t = ensureDBFn() or {}
            return tonumber(t[barPrefix .. "BackgroundOpacity"]) or 50
        end,
        set = function(v)
            local t = ensureDBFn()
            if not t then return end
            t[barPrefix .. "BackgroundOpacity"] = tonumber(v) or 50
            applyFn()
        end,
    })
end

--------------------------------------------------------------------------------
-- Bar Border Content Builder
--------------------------------------------------------------------------------
-- Builds: Border Style → Border Tint → Border Thickness → Border Inset
-- Does NOT call Finalize() — callers do.

function UF.Builders.buildBarBorderContent(inner, barPrefix, ensureDBFn, applyFn)
    inner:AddBarBorderSelector({
        label = "Border Style",
        includeNone = true,
        get = function()
            local t = ensureDBFn() or {}
            return t[barPrefix .. "BorderStyle"] or "square"
        end,
        set = function(v)
            local t = ensureDBFn()
            if not t then return end
            t[barPrefix .. "BorderStyle"] = v or "square"
            applyFn()
        end,
    })

    inner:AddToggleColorPicker({
        label = "Border Tint",
        get = function()
            local t = ensureDBFn() or {}
            return not not t[barPrefix .. "BorderTintEnable"]
        end,
        set = function(v)
            local t = ensureDBFn()
            if not t then return end
            t[barPrefix .. "BorderTintEnable"] = not not v
            applyFn()
        end,
        getColor = function()
            local t = ensureDBFn() or {}
            local c = t[barPrefix .. "BorderTintColor"] or {1, 1, 1, 1}
            return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
        end,
        setColor = function(r, g, b, a)
            local t = ensureDBFn()
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
            local t = ensureDBFn() or {}
            local v = tonumber(t[barPrefix .. "BorderThickness"]) or 1
            return math.max(1, math.min(8, math.floor(v * 2 + 0.5) / 2))
        end,
        set = function(v)
            local t = ensureDBFn()
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
                local t = ensureDBFn() or {}
                return tonumber(t[barPrefix .. "BorderInsetH"]) or tonumber(t[barPrefix .. "BorderInset"]) or 0
            end,
            set = function(v)
                local t = ensureDBFn()
                if not t then return end
                t[barPrefix .. "BorderInsetH"] = tonumber(v) or 0
                applyFn()
            end,
            minLabel = "-4", maxLabel = "+4",
        },
        sliderB = {
            axisLabel = "V", min = -4, max = 4, step = 1,
            get = function()
                local t = ensureDBFn() or {}
                return tonumber(t[barPrefix .. "BorderInsetV"]) or tonumber(t[barPrefix .. "BorderInset"]) or 0
            end,
            set = function(v)
                local t = ensureDBFn()
                if not t then return end
                t[barPrefix .. "BorderInsetV"] = tonumber(v) or 0
                applyFn()
            end,
            minLabel = "-4", maxLabel = "+4",
        },
    })
end

--------------------------------------------------------------------------------
-- Text Tab Content Builder
--------------------------------------------------------------------------------
-- Builds: Disable toggle → Font → Style → Size → Color → Alignment → Offset X/Y
-- Does NOT call Finalize() — callers do.
-- Font/style/size/color/alignment/offset all call UF.applyStyles().
-- Disable toggle calls applyTextFn (the specific apply function).

function UF.Builders.buildTextTabContent(inner, textKey, ensureParentDBFn, ensureTextDBFn, applyTextFn, defaultAlignment, colorValues, colorOrder)
    defaultAlignment = defaultAlignment or "LEFT"
    colorValues = colorValues or UF.fontColorValues
    colorOrder = colorOrder or UF.fontColorOrder
    local hiddenKey = textKey:gsub("text", ""):lower() .. "Hidden"

    inner:AddToggle({
        label = "Disable Text",
        get = function()
            local t = ensureParentDBFn() or {}
            return not not t[hiddenKey]
        end,
        set = function(v)
            local t = ensureParentDBFn()
            if not t then return end
            t[hiddenKey] = v and true or false
            applyTextFn()
        end,
    })

    inner:AddFontSelector({
        label = "Font",
        get = function()
            local s = ensureTextDBFn(textKey) or {}
            return s.fontFace or "FRIZQT__"
        end,
        set = function(v)
            local t = ensureParentDBFn()
            if not t then return end
            t[textKey] = t[textKey] or {}
            t[textKey].fontFace = v
            UF.applyStyles()
        end,
    })

    inner:AddSelector({
        label = "Style",
        values = UF.fontStyleValues,
        order = UF.fontStyleOrder,
        get = function()
            local s = ensureTextDBFn(textKey) or {}
            return s.style or "OUTLINE"
        end,
        set = function(v)
            local t = ensureParentDBFn()
            if not t then return end
            t[textKey] = t[textKey] or {}
            t[textKey].style = v
            UF.applyStyles()
        end,
    })

    inner:AddSlider({
        label = "Size",
        min = 6,
        max = 48,
        step = 1,
        get = function()
            local s = ensureTextDBFn(textKey) or {}
            return tonumber(s.size) or 14
        end,
        set = function(v)
            local t = ensureParentDBFn()
            if not t then return end
            t[textKey] = t[textKey] or {}
            t[textKey].size = tonumber(v) or 14
            UF.applyStyles()
        end,
    })

    inner:AddSelectorColorPicker({
        label = "Color",
        values = colorValues,
        order = colorOrder,
        get = function()
            local s = ensureTextDBFn(textKey) or {}
            return s.colorMode or "default"
        end,
        set = function(v)
            local t = ensureParentDBFn()
            if not t then return end
            t[textKey] = t[textKey] or {}
            t[textKey].colorMode = v or "default"
            UF.applyStyles()
        end,
        getColor = function()
            local s = ensureTextDBFn(textKey) or {}
            local c = s.color or {1, 1, 1, 1}
            return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
        end,
        setColor = function(r, g, b, a)
            local t = ensureParentDBFn()
            if not t then return end
            t[textKey] = t[textKey] or {}
            t[textKey].color = {r or 1, g or 1, b or 1, a or 1}
            UF.applyStyles()
        end,
        customValue = "custom",
        hasAlpha = true,
    })

    inner:AddSelector({
        label = "Alignment",
        values = UF.alignmentValues,
        order = UF.alignmentOrder,
        get = function()
            local s = ensureTextDBFn(textKey) or {}
            return s.alignment or defaultAlignment
        end,
        set = function(v)
            local t = ensureParentDBFn()
            if not t then return end
            t[textKey] = t[textKey] or {}
            t[textKey].alignment = v or defaultAlignment
            UF.applyStyles()
        end,
    })

    inner:AddDualSlider({
        label = "Offset",
        sliderA = {
            axisLabel = "X",
            min = -100, max = 100, step = 1,
            get = function()
                local s = ensureTextDBFn(textKey) or {}
                local o = s.offset or {}
                return tonumber(o.x) or 0
            end,
            set = function(v)
                local t = ensureParentDBFn()
                if not t then return end
                t[textKey] = t[textKey] or {}
                t[textKey].offset = t[textKey].offset or {}
                t[textKey].offset.x = tonumber(v) or 0
                UF.applyStyles()
            end,
        },
        sliderB = {
            axisLabel = "Y",
            min = -100, max = 100, step = 1,
            get = function()
                local s = ensureTextDBFn(textKey) or {}
                local o = s.offset or {}
                return tonumber(o.y) or 0
            end,
            set = function(v)
                local t = ensureParentDBFn()
                if not t then return end
                t[textKey] = t[textKey] or {}
                t[textKey].offset = t[textKey].offset or {}
                t[textKey].offset.y = tonumber(v) or 0
                UF.applyStyles()
            end,
        },
    })
end

return UF.Builders
