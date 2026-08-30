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
-- getDBFn: read-only accessor (no materialization), used in get callbacks
-- ensureDBFn: materializing accessor, used in set callbacks

function UF.Builders.buildBarStyleContent(inner, barPrefix, ensureDBFn, applyFn, colorValues, colorOrder, colorInfoIcons, getDBFn)
    colorValues = colorValues or UF.healthColorValues
    colorOrder = colorOrder or UF.healthColorOrder
    colorInfoIcons = colorInfoIcons or UF.healthColorInfoIcons
    local readFn = getDBFn or ensureDBFn

    inner:AddDualBarStyleRow({
        label = "Foreground",
        getTexture = function()
            local t = readFn() or {}
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
            local t = readFn() or {}
            return t[barPrefix .. "ColorMode"] or "default"
        end,
        setColorMode = function(v)
            local t = ensureDBFn()
            if not t then return end
            t[barPrefix .. "ColorMode"] = v or "default"
            applyFn()
        end,
        getColor = function()
            local t = readFn() or {}
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
            local t = readFn() or {}
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
            local t = readFn() or {}
            return t[barPrefix .. "BackgroundColorMode"] or "default"
        end,
        setColorMode = function(v)
            local t = ensureDBFn()
            if not t then return end
            t[barPrefix .. "BackgroundColorMode"] = v or "default"
            applyFn()
        end,
        getColor = function()
            local t = readFn() or {}
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
            local t = readFn() or {}
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
-- getDBFn: read-only accessor (no materialization), used in get callbacks

function UF.Builders.buildBarBorderContent(inner, barPrefix, ensureDBFn, applyFn, getDBFn)
    local readFn = getDBFn or ensureDBFn

    inner:AddBarBorderSelector({
        label = "Border Style",
        includeNone = true,
        get = function()
            local t = readFn() or {}
            return t[barPrefix .. "BorderStyle"] or "square"
        end,
        set = function(v)
            local t = ensureDBFn()
            if not t then return end
            t[barPrefix .. "BorderStyle"] = v or "square"
            applyFn()
        end,
        getHiddenEdges = function()
            local t = readFn() or {}
            return t[barPrefix .. "BorderHiddenEdges"]
        end,
        setHiddenEdges = function(v)
            local t = ensureDBFn()
            if not t then return end
            t[barPrefix .. "BorderHiddenEdges"] = v
            applyFn()
        end,
    })

    inner:AddToggleColorPicker({
        label = "Border Tint",
        get = function()
            local t = readFn() or {}
            return not not t[barPrefix .. "BorderTintEnable"]
        end,
        set = function(v)
            local t = ensureDBFn()
            if not t then return end
            t[barPrefix .. "BorderTintEnable"] = not not v
            applyFn()
        end,
        getColor = function()
            local t = readFn() or {}
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
            local t = readFn() or {}
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
                local t = readFn() or {}
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
                local t = readFn() or {}
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

-- Text tabs build through Builder:AddTextStyleBlock (BuilderComposites.lua)
-- with accessors from UF.textAccessors (Helpers.lua).

return UF.Builders
