-- EditorTabs.lua - Styling tab bodies for the ScootAura editor
--
-- Generalized from the Class Auras renderer's per-aura tabs. Every body reads
-- and writes through ctx (draft-aware), never through component helpers
-- directly, so the same tabs serve a materialized tracker and an unsaved
-- draft.
--
-- ctx = {
--   get(key)              -> value        (draft table or component db)
--   setAndApply(key, v)                   (writes + restyles when live)
--   refresh()                             (deferred editor re-render; use for
--                                          sets that add, remove, or disable
--                                          other rows)
--   refreshPreview()                      (preview-only re-render; use for
--                                          value edits, so the tab body is
--                                          not rebuilt under the cursor)
--   shape()               -> "icon"|"bar"|"shape"
--   spellId()             -> number|nil   (tracker spell, or the validated
--                                          draft spell)
-- }
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.Settings = addon.UI.Settings or {}
addon.UI.Settings.ScootAuraEditorTabs = {}

local Tabs = addon.UI.Settings.ScootAuraEditorTabs

local OUTSIDE_ANCHOR_VALUES = { LEFT = "Left", RIGHT = "Right", ABOVE = "Above", BELOW = "Below" }
local OUTSIDE_ANCHOR_ORDER = { "LEFT", "RIGHT", "ABOVE", "BELOW" }

-- All 8 edges + corners for outside placement (stack text).
local OUTSIDE_8_ANCHOR_VALUES = {
    TOPLEFT = "Top-Left", TOP = "Top", TOPRIGHT = "Top-Right",
    LEFT = "Left", RIGHT = "Right",
    BOTTOMLEFT = "Bottom-Left", BOTTOM = "Bottom", BOTTOMRIGHT = "Bottom-Right",
}
local OUTSIDE_8_ANCHOR_ORDER = { "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" }

local INSIDE_ANCHOR_VALUES = {
    TOPLEFT = "Top-Left", TOP = "Top", TOPRIGHT = "Top-Right",
    LEFT = "Left", CENTER = "Center", RIGHT = "Right",
    BOTTOMLEFT = "Bottom-Left", BOTTOM = "Bottom", BOTTOMRIGHT = "Bottom-Right",
}
local INSIDE_ANCHOR_ORDER = { "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" }

local function ColorGet(ctx, key, fallback)
    return function()
        local c = ctx.get(key)
        if type(c) == "table" then
            return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
        end
        local f = fallback or { 1, 1, 1, 1 }
        return f[1], f[2], f[3], f[4]
    end
end

local function ColorSet(ctx, key)
    return function(r, g, b, a)
        ctx.setAndApply(key, { r, g, b, a })
        ctx.refreshPreview()
    end
end

--------------------------------------------------------------------------------
-- Icon tab (icon trackers always; bar trackers behind the Show Icon toggle)
--------------------------------------------------------------------------------

function Tabs.BuildIconTab(tabBuilder, ctx)
    local Helpers = addon.UI.Settings.Helpers
    local isBar = ctx.shape() == "bar"

    if isBar then
        tabBuilder:AddToggle({
            label = "Show Icon",
            description = "Show the aura's icon beside the bar.",
            emphasized = true,
            get = function() return ctx.get("barShowIcon") or false end,
            set = function(v)
                ctx.setAndApply("barShowIcon", v)
                ctx.refresh()   -- gates the icon controls and the side/gap row
            end,
        })
    end

    if isBar and ctx.get("barShowIcon") then
        -- The bar is the anchor; these place the icon beside it. One row,
        -- half a width each, standalone controls spliced into the builder
        -- flow (the shape-row idiom). Show Icon rebuilds the tab, so the row
        -- is simply absent while the icon is off.
        local content = tabBuilder._scrollContent
        local Controls = addon.UI.Controls
        local sideSel = Controls:CreateSelector({
            parent = content,
            label = "Icon Position",
            values = { LEFT = "Left of Bar", RIGHT = "Right of Bar" },
            order = { "LEFT", "RIGHT" },
            width = 180,
            noBottomBorder = true,
            get = function() return ctx.get("barIconSide") or "LEFT" end,
            set = function(v) ctx.setAndApply("barIconSide", v) ctx.refreshPreview() end,
        })
        local gapSlider = Controls:CreateSlider({
            parent = content,
            label = "Bar/Icon Gap",
            min = 0, max = 30, step = 1,
            width = 100,
            inputWidth = 40,
            noBottomBorder = true,
            get = function() return ctx.get("barIconGap") or 2 end,
            set = function(v) ctx.setAndApply("barIconGap", v) ctx.refreshPreview() end,
        })
        if #tabBuilder._controls > 0 then
            tabBuilder._currentY = tabBuilder._currentY - 12
        end
        local y = tabBuilder._currentY
        sideSel:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
        sideSel:SetPoint("TOPRIGHT", content, "TOP", -8, y)
        gapSlider:SetPoint("TOPLEFT", content, "TOP", 8, y)
        gapSlider:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, y)
        table.insert(tabBuilder._controls, sideSel)
        table.insert(tabBuilder._controls, gapSlider)
        local rowH = math.max(sideSel:GetHeight() or 36, gapSlider:GetHeight() or 36)
        -- One full-width divider under the whole row with clearance, replacing
        -- the controls' own per-half bottom borders (suppressed above, which
        -- left a tight line under the slider half only). Parented to the
        -- selector row so Builder:Clear takes it along on tab rebuilds.
        local theme = addon.UI.Theme
        local dr, dg, db2 = theme:GetAccentColor()
        local divider = sideSel:CreateTexture(nil, "BORDER", nil, -1)
        divider:SetHeight(1)
        divider:SetColorTexture(dr, dg, db2, 0.2)
        divider:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y - rowH - 10)
        divider:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, y - rowH - 10)
        tabBuilder._currentY = y - rowH - 11
    end

    local function iconControlsDisabled()
        return isBar and not ctx.get("barShowIcon")
    end

    tabBuilder:AddSlider({
        label = "Icon Size",
        description = "Base size of the icon in pixels.",
        min = 16, max = 64, step = 1,
        get = function() return ctx.get("iconSize") or 32 end,
        set = function(v) ctx.setAndApply("iconSize", v) ctx.refreshPreview() end,
        minLabel = "16", maxLabel = "64",
        disabled = iconControlsDisabled,
    })

    tabBuilder:AddSlider({
        label = "Icon Shape",
        description = "Adjust icon aspect ratio. Center = square icons.",
        min = -67, max = 67, step = 1,
        get = function() return ctx.get("iconShape") or 0 end,
        set = function(v) ctx.setAndApply("iconShape", v) ctx.refreshPreview() end,
        minLabel = "Wide", maxLabel = "Tall",
        disabled = iconControlsDisabled,
    })

    local borderStyleValues, borderStyleOrder = Helpers.getIconBorderOptions({ { "none", "None" } })

    tabBuilder:AddSelector({
        label = "Border Style",
        description = "Choose the visual style for icon borders.",
        values = borderStyleValues,
        order = borderStyleOrder,
        get = function() return ctx.get("borderStyle") or "none" end,
        set = function(v) ctx.setAndApply("borderStyle", v) ctx.refresh() end,   -- thickness row appears per style
        disabled = iconControlsDisabled,
    })

    tabBuilder:AddToggleColorPicker({
        label = "Border Tint",
        description = "Apply a custom tint color to the icon border.",
        get = function() return ctx.get("borderTintEnable") or false end,
        set = function(v) ctx.setAndApply("borderTintEnable", v) ctx.refresh() end,   -- enables its swatch
        getColor = ColorGet(ctx, "borderTintColor"),
        setColor = ColorSet(ctx, "borderTintColor"),
        hasAlpha = true,
        disabled = iconControlsDisabled,
    })

    if addon.IconBorders.SupportsThickness(ctx.get("borderStyle") or "none") then
        tabBuilder:AddSlider({
            label = "Border Thickness",
            description = "Thickness of the border in pixels.",
            min = 1, max = 8, step = 0.5, precision = 1,
            get = function() return ctx.get("borderThickness") or 1 end,
            set = function(v) ctx.setAndApply("borderThickness", v) ctx.refreshPreview() end,
            minLabel = "1", maxLabel = "8",
            disabled = iconControlsDisabled,
        })
    end

    tabBuilder:AddDualSlider({
        label = "Border Inset",
        disabled = iconControlsDisabled,
        sliderA = {
            axisLabel = "H", min = -4, max = 4, step = 0.5, precision = 1,
            get = function() return ctx.get("borderInsetH") or 0 end,
            set = function(v) ctx.setAndApply("borderInsetH", v) ctx.refreshPreview() end,
            minLabel = "-4", maxLabel = "+4",
        },
        sliderB = {
            axisLabel = "V", min = -4, max = 4, step = 0.5, precision = 1,
            get = function() return ctx.get("borderInsetV") or 0 end,
            set = function(v) ctx.setAndApply("borderInsetV", v) ctx.refreshPreview() end,
            minLabel = "-4", maxLabel = "+4",
        },
    })

    tabBuilder:Finalize()
end

--------------------------------------------------------------------------------
-- Bar tab
--------------------------------------------------------------------------------

function Tabs.BuildBarTab(tabBuilder, ctx)
    tabBuilder:AddDualSlider({
        label = "Bar Size",
        sliderA = {
            axisLabel = "W", min = 20, max = 400, step = 1,
            get = function() return ctx.get("barWidth") or 250 end,
            set = function(v) ctx.setAndApply("barWidth", v) ctx.refreshPreview() end,
            minLabel = "20", maxLabel = "400",
        },
        sliderB = {
            axisLabel = "H", min = 4, max = 48, step = 1,
            get = function() return ctx.get("barHeight") or 32 end,
            set = function(v) ctx.setAndApply("barHeight", v) ctx.refreshPreview() end,
            minLabel = "4", maxLabel = "48",
        },
    })

    tabBuilder:AddSelector({
        label = "Fill Direction",
        description = "Deplete drains the bar as time runs out. Fill grows it as time passes.",
        values = { deplete = "Deplete", fill = "Fill" },
        order = { "deplete", "fill" },
        get = function() return ctx.get("barFillMode") or "deplete" end,
        set = function(v) ctx.setAndApply("barFillMode", v) ctx.refreshPreview() end,
    })

    -- Cadence lock (scootauras/cadence.lua). The detected value is per spell;
    -- a draft without a validated spell has none yet.
    tabBuilder:AddToggle({
        label = "Lock Drain to Original Duration",
        description = "Keeps the drain speed tied to the aura's original duration. Refreshes and extensions add to the bar instead of refilling it. If the new duration is longer than the original, the bar still refills and drains at that longer speed.",
        get = function() return ctx.get("barLockCadence") or false end,
        set = function(v)
            ctx.setAndApply("barLockCadence", v)
            ctx.refresh()   -- gates the duration rows below
        end,
    })
    if ctx.get("barLockCadence") then
        tabBuilder:AddSlider({
            label = "Original Duration (seconds)",
            description = "0 uses the detected duration.",
            min = 0, max = 120, step = 0.5, precision = 1,
            get = function() return ctx.get("barLockDuration") or 0 end,
            set = function(v) ctx.setAndApply("barLockDuration", v) end,
            minLabel = "Auto", maxLabel = "120s",
        })
        local spellId = ctx.spellId and ctx.spellId() or nil
        local learned = spellId and addon.ScootAuras.GetLearnedDuration(spellId) or nil
        local detectedText
        if learned then
            detectedText = ("Detected duration for this spell: %.1f seconds."):format(learned)
        else
            detectedText = "No duration detected yet. Auto-detect learns the duration the first time the aura is applied outside restricted content."
        end
        tabBuilder:AddDescription(detectedText, { fontSize = 11, bottomPadding = 2 })
    end

    tabBuilder:AddDualBarStyleRow({
        label = "Foreground",
        getTexture = function() return ctx.get("barForegroundTexture") or "bevelled" end,
        setTexture = function(v) ctx.setAndApply("barForegroundTexture", v) ctx.refreshPreview() end,
        colorValues = {
            custom = "Custom",
            class = "Class Color",
            original = "Texture Original",
        },
        colorOrder = { "custom", "class", "original" },
        getColorMode = function() return ctx.get("barForegroundColorMode") or "class" end,
        setColorMode = function(v) ctx.setAndApply("barForegroundColorMode", v) ctx.refresh() end,   -- swatch follows the mode
        getColor = ColorGet(ctx, "barForegroundTint"),
        setColor = ColorSet(ctx, "barForegroundTint"),
        customColorValue = "custom",
        hasAlpha = true,
    })

    tabBuilder:AddSpacer(8)

    tabBuilder:AddDualBarStyleRow({
        label = "Background",
        getTexture = function() return ctx.get("barBackgroundTexture") or "bevelled" end,
        setTexture = function(v) ctx.setAndApply("barBackgroundTexture", v) ctx.refreshPreview() end,
        colorValues = {
            custom = "Custom",
            original = "Texture Original",
        },
        colorOrder = { "custom", "original" },
        getColorMode = function() return ctx.get("barBackgroundColorMode") or "custom" end,
        setColorMode = function(v) ctx.setAndApply("barBackgroundColorMode", v) ctx.refresh() end,   -- swatch follows the mode
        getColor = ColorGet(ctx, "barBackgroundTint", { 0, 0, 0, 1 }),
        setColor = ColorSet(ctx, "barBackgroundTint"),
        customColorValue = "custom",
        hasAlpha = true,
    })

    tabBuilder:AddSlider({
        label = "Background Opacity",
        min = 0, max = 100, step = 1,
        get = function() return ctx.get("barBackgroundOpacity") or 50 end,
        set = function(v) ctx.setAndApply("barBackgroundOpacity", v) ctx.refreshPreview() end,
        minLabel = "0%", maxLabel = "100%",
    })

    tabBuilder:AddBarBorderSelector({
        label = "Border Style",
        includeNone = true,
        get = function() return ctx.get("barBorderStyle") or "none" end,
        set = function(v) ctx.setAndApply("barBorderStyle", v) ctx.refresh() end,   -- edge controls follow the style
        getHiddenEdges = function() return ctx.get("barBorderHiddenEdges") end,
        setHiddenEdges = function(v) ctx.setAndApply("barBorderHiddenEdges", v) ctx.refreshPreview() end,
    })

    tabBuilder:AddToggleColorPicker({
        label = "Border Tint",
        get = function() return ctx.get("barBorderTintEnable") or false end,
        set = function(v) ctx.setAndApply("barBorderTintEnable", v) ctx.refresh() end,   -- enables its swatch
        getColor = ColorGet(ctx, "barBorderTintColor"),
        setColor = ColorSet(ctx, "barBorderTintColor"),
        hasAlpha = true,
    })

    tabBuilder:AddSlider({
        label = "Border Thickness",
        min = 1, max = 8, step = 0.5, precision = 1,
        get = function() return ctx.get("barBorderThickness") or 1 end,
        set = function(v) ctx.setAndApply("barBorderThickness", v) ctx.refreshPreview() end,
        minLabel = "1", maxLabel = "8",
    })

    tabBuilder:AddDualSlider({
        label = "Border Inset",
        sliderA = {
            axisLabel = "H", min = -4, max = 4, step = 1,
            get = function() return ctx.get("barBorderInsetH") or 0 end,
            set = function(v) ctx.setAndApply("barBorderInsetH", v) ctx.refreshPreview() end,
            minLabel = "-4", maxLabel = "+4",
        },
        sliderB = {
            axisLabel = "V", min = -4, max = 4, step = 1,
            get = function() return ctx.get("barBorderInsetV") or 0 end,
            set = function(v) ctx.setAndApply("barBorderInsetV", v) ctx.refreshPreview() end,
            minLabel = "-4", maxLabel = "+4",
        },
    })

    tabBuilder:Finalize()
end

--------------------------------------------------------------------------------
-- Aura Name tab (bar trackers: the name renders on the bar)
--------------------------------------------------------------------------------

function Tabs.BuildAuraNameTab(tabBuilder, ctx)
    local Helpers = addon.UI.Settings.Helpers

    tabBuilder:AddToggle({
        label = "Hide Aura Name",
        description = "Hide the aura name text on the bar.",
        get = function() return ctx.get("hideNameText") ~= false end,
        set = function(v) ctx.setAndApply("hideNameText", v) ctx.refreshPreview() end,
    })

    tabBuilder:AddFontSelector({
        label = "Font",
        description = "The font used for the aura name.",
        get = function() return ctx.get("nameTextFont") or "FRIZQT__" end,
        set = function(v) ctx.setAndApply("nameTextFont", v) ctx.refreshPreview() end,
    })

    tabBuilder:AddSelector({
        label = "Font Style",
        values = Helpers.fontStyleValues,
        order = Helpers.fontStyleOrder,
        get = function() return ctx.get("nameTextStyle") or "OUTLINE" end,
        set = function(v) ctx.setAndApply("nameTextStyle", v) ctx.refreshPreview() end,
    })

    tabBuilder:AddSlider({
        label = "Font Size",
        min = 6, max = 48, step = 1,
        get = function() return ctx.get("nameTextSize") or 10 end,
        set = function(v) ctx.setAndApply("nameTextSize", v) ctx.refreshPreview() end,
        minLabel = "6pt", maxLabel = "48pt",
    })

    tabBuilder:AddColorPicker({
        label = "Font Color",
        get = ColorGet(ctx, "nameTextColor"),
        set = ColorSet(ctx, "nameTextColor"),
        hasAlpha = true,
    })

    local currentPos = ctx.get("nameTextPosition") or "inside"
    local bValues = currentPos == "outside" and OUTSIDE_ANCHOR_VALUES or INSIDE_ANCHOR_VALUES
    local bOrder = currentPos == "outside" and OUTSIDE_ANCHOR_ORDER or INSIDE_ANCHOR_ORDER

    tabBuilder:AddDualSelector({
        label = "Position",
        key = "saNameTextPositionDual",
        maxContainerWidth = 420,
        selectorA = {
            values = { inside = "Inside the Bar", outside = "Outside of Bar" },
            order = { "inside", "outside" },
            get = function() return ctx.get("nameTextPosition") or "inside" end,
            set = function(v)
                ctx.setAndApply("nameTextPosition", v)
                local dual = tabBuilder:GetControl("saNameTextPositionDual")
                if dual then
                    if v == "outside" then
                        dual:SetOptionsB(OUTSIDE_ANCHOR_VALUES, OUTSIDE_ANCHOR_ORDER)
                    else
                        dual:SetOptionsB(INSIDE_ANCHOR_VALUES, INSIDE_ANCHOR_ORDER)
                    end
                end
                ctx.refreshPreview()
            end,
        },
        selectorB = {
            values = bValues,
            order = bOrder,
            get = function()
                if (ctx.get("nameTextPosition") or "inside") == "outside" then
                    return ctx.get("nameTextOuterAnchor") or "ABOVE"
                end
                return ctx.get("nameTextInnerAnchor") or "LEFT"
            end,
            set = function(v)
                if (ctx.get("nameTextPosition") or "inside") == "outside" then
                    ctx.setAndApply("nameTextOuterAnchor", v)
                else
                    ctx.setAndApply("nameTextInnerAnchor", v)
                end
                ctx.refreshPreview()
            end,
        },
    })

    tabBuilder:AddDualSlider({
        label = "Offset",
        sliderA = {
            axisLabel = "X", min = -50, max = 50, step = 1,
            get = function() return ctx.get("nameTextOffsetX") or 0 end,
            set = function(v) ctx.setAndApply("nameTextOffsetX", v) ctx.refreshPreview() end,
            minLabel = "-50", maxLabel = "+50",
        },
        sliderB = {
            axisLabel = "Y", min = -50, max = 50, step = 1,
            get = function() return ctx.get("nameTextOffsetY") or 0 end,
            set = function(v) ctx.setAndApply("nameTextOffsetY", v) ctx.refreshPreview() end,
            minLabel = "-50", maxLabel = "+50",
        },
    })

    tabBuilder:Finalize()
end

--------------------------------------------------------------------------------
-- Duration tab (remaining-time text)
--------------------------------------------------------------------------------

function Tabs.BuildDurationTab(tabBuilder, ctx)
    local Helpers = addon.UI.Settings.Helpers

    tabBuilder:AddToggle({
        label = "Hide Duration Text",
        description = "Hide the remaining-time text.",
        get = function() return ctx.get("hideText") or false end,
        set = function(v) ctx.setAndApply("hideText", v) ctx.refreshPreview() end,
    })

    tabBuilder:AddFontSelector({
        label = "Font",
        description = "The font used for the duration text.",
        get = function() return ctx.get("textFont") end,
        set = function(v) ctx.setAndApply("textFont", v) ctx.refreshPreview() end,
    })

    tabBuilder:AddSelector({
        label = "Font Style",
        values = Helpers.fontStyleValues,
        order = Helpers.fontStyleOrder,
        get = function() return ctx.get("textStyle") or "OUTLINE" end,
        set = function(v) ctx.setAndApply("textStyle", v) ctx.refreshPreview() end,
    })

    tabBuilder:AddSlider({
        label = "Font Size",
        description = "Size of the duration text in points.",
        min = 6, max = 48, step = 1,
        get = function() return ctx.get("textSize") or 24 end,
        set = function(v) ctx.setAndApply("textSize", v) ctx.refreshPreview() end,
        minLabel = "6pt", maxLabel = "48pt",
    })

    tabBuilder:AddColorPicker({
        label = "Font Color",
        get = ColorGet(ctx, "textColor"),
        set = ColorSet(ctx, "textColor"),
        hasAlpha = true,
    })

    local shape = ctx.shape()
    local host = (shape == "bar") and "Bar" or (shape == "shape") and "Shape" or "Icon"
    local currentPos = ctx.get("textPosition") or "inside"
    local bValues = currentPos == "outside" and OUTSIDE_ANCHOR_VALUES or INSIDE_ANCHOR_VALUES
    local bOrder = currentPos == "outside" and OUTSIDE_ANCHOR_ORDER or INSIDE_ANCHOR_ORDER

    tabBuilder:AddDualSelector({
        label = "Position",
        key = "saTextPositionDual",
        maxContainerWidth = 420,
        selectorA = {
            values = { inside = "Inside the " .. host, outside = "Outside of " .. host },
            order = { "inside", "outside" },
            get = function() return ctx.get("textPosition") or "inside" end,
            set = function(v)
                ctx.setAndApply("textPosition", v)
                local dual = tabBuilder:GetControl("saTextPositionDual")
                if dual then
                    if v == "outside" then
                        dual:SetOptionsB(OUTSIDE_ANCHOR_VALUES, OUTSIDE_ANCHOR_ORDER)
                    else
                        dual:SetOptionsB(INSIDE_ANCHOR_VALUES, INSIDE_ANCHOR_ORDER)
                    end
                end
                ctx.refreshPreview()
            end,
        },
        selectorB = {
            values = bValues,
            order = bOrder,
            get = function()
                if (ctx.get("textPosition") or "inside") == "outside" then
                    return ctx.get("textOuterAnchor") or "RIGHT"
                end
                return ctx.get("textInnerAnchor") or "CENTER"
            end,
            set = function(v)
                if (ctx.get("textPosition") or "inside") == "outside" then
                    ctx.setAndApply("textOuterAnchor", v)
                else
                    ctx.setAndApply("textInnerAnchor", v)
                end
                ctx.refreshPreview()
            end,
        },
    })

    tabBuilder:AddDualSlider({
        label = "Offset",
        sliderA = {
            axisLabel = "X", min = -50, max = 50, step = 1,
            get = function() return ctx.get("textOffsetX") or 0 end,
            set = function(v) ctx.setAndApply("textOffsetX", v) ctx.refreshPreview() end,
            minLabel = "-50", maxLabel = "+50",
        },
        sliderB = {
            axisLabel = "Y", min = -50, max = 50, step = 1,
            get = function() return ctx.get("textOffsetY") or 0 end,
            set = function(v) ctx.setAndApply("textOffsetY", v) ctx.refreshPreview() end,
            minLabel = "-50", maxLabel = "+50",
        },
    })

    tabBuilder:Finalize()
end

--------------------------------------------------------------------------------
-- Stacks tab (stack counter text)
--------------------------------------------------------------------------------

function Tabs.BuildStacksTab(tabBuilder, ctx)
    local Helpers = addon.UI.Settings.Helpers

    tabBuilder:AddToggle({
        label = "Hide Stacks Text",
        description = "Hide the stack counter.",
        get = function() return ctx.get("hideStackText") or false end,
        set = function(v) ctx.setAndApply("hideStackText", v) ctx.refreshPreview() end,
    })

    tabBuilder:AddFontSelector({
        label = "Font",
        description = "The font used for the stack counter.",
        get = function() return ctx.get("stackTextFont") end,
        set = function(v) ctx.setAndApply("stackTextFont", v) ctx.refreshPreview() end,
    })

    tabBuilder:AddSelector({
        label = "Font Style",
        values = Helpers.fontStyleValues,
        order = Helpers.fontStyleOrder,
        get = function() return ctx.get("stackTextStyle") or "OUTLINE" end,
        set = function(v) ctx.setAndApply("stackTextStyle", v) ctx.refreshPreview() end,
    })

    tabBuilder:AddSlider({
        label = "Font Size",
        description = "Size of the stack counter in points.",
        min = 6, max = 48, step = 1,
        get = function() return ctx.get("stackTextSize") or 14 end,
        set = function(v) ctx.setAndApply("stackTextSize", v) ctx.refreshPreview() end,
        minLabel = "6pt", maxLabel = "48pt",
    })

    tabBuilder:AddColorPicker({
        label = "Font Color",
        get = ColorGet(ctx, "stackTextColor"),
        set = ColorSet(ctx, "stackTextColor"),
        hasAlpha = true,
    })

    local shape = ctx.shape()
    local host = (shape == "bar") and "Bar" or (shape == "shape") and "Shape" or "Icon"
    local currentPos = ctx.get("stackTextPosition") or "inside"
    local bValues = currentPos == "outside" and OUTSIDE_8_ANCHOR_VALUES or INSIDE_ANCHOR_VALUES
    local bOrder = currentPos == "outside" and OUTSIDE_8_ANCHOR_ORDER or INSIDE_ANCHOR_ORDER

    tabBuilder:AddDualSelector({
        label = "Position",
        key = "saStackPositionDual",
        maxContainerWidth = 420,
        selectorA = {
            values = { inside = "Inside the " .. host, outside = "Outside of " .. host },
            order = { "inside", "outside" },
            get = function() return ctx.get("stackTextPosition") or "inside" end,
            set = function(v)
                ctx.setAndApply("stackTextPosition", v)
                local dual = tabBuilder:GetControl("saStackPositionDual")
                if dual then
                    if v == "outside" then
                        dual:SetOptionsB(OUTSIDE_8_ANCHOR_VALUES, OUTSIDE_8_ANCHOR_ORDER)
                    else
                        dual:SetOptionsB(INSIDE_ANCHOR_VALUES, INSIDE_ANCHOR_ORDER)
                    end
                end
                ctx.refreshPreview()
            end,
        },
        selectorB = {
            values = bValues,
            order = bOrder,
            get = function()
                if (ctx.get("stackTextPosition") or "inside") == "outside" then
                    return ctx.get("stackTextOuterAnchor") or "TOPRIGHT"
                end
                return ctx.get("stackTextInnerAnchor") or "BOTTOMRIGHT"
            end,
            set = function(v)
                if (ctx.get("stackTextPosition") or "inside") == "outside" then
                    ctx.setAndApply("stackTextOuterAnchor", v)
                else
                    ctx.setAndApply("stackTextInnerAnchor", v)
                end
                ctx.refreshPreview()
            end,
        },
    })

    tabBuilder:AddDualSlider({
        label = "Offset",
        sliderA = {
            axisLabel = "X", min = -50, max = 50, step = 1,
            get = function() return ctx.get("stackTextOffsetX") or 0 end,
            set = function(v) ctx.setAndApply("stackTextOffsetX", v) ctx.refreshPreview() end,
            minLabel = "-50", maxLabel = "+50",
        },
        sliderB = {
            axisLabel = "Y", min = -50, max = 50, step = 1,
            get = function() return ctx.get("stackTextOffsetY") or 0 end,
            set = function(v) ctx.setAndApply("stackTextOffsetY", v) ctx.refreshPreview() end,
            minLabel = "-50", maxLabel = "+50",
        },
    })

    tabBuilder:Finalize()
end

--------------------------------------------------------------------------------
-- Shape tab (shape trackers)
--------------------------------------------------------------------------------

-- Bespoke row: atlas preview + a button that opens the shared icon picker.
-- The picker hides its Animated tab and the "spell" entry for this caller
-- (the callback rejects both as a backstop): shape trackers need a plain
-- atlas (animated shapes ride scripts, which never fire on denied button
-- subtrees in combat).
local function CreateShapeStyleRow(parent, ctx)
    local theme = addon.UI.Theme
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(36)

    local label = row:CreateFontString(nil, "OVERLAY")
    label:SetFont(theme:GetFont("LABEL"), 13, "")
    label:SetPoint("LEFT", row, "LEFT", 8, 0)
    label:SetText("Shape")
    label:SetTextColor(theme:GetAccentColor())

    local preview = row:CreateTexture(nil, "ARTWORK")
    preview:SetSize(26, 26)
    preview:SetPoint("LEFT", row, "LEFT", 120, 0)

    local function UpdatePreview()
        local key = ctx.get("shapeStyle") or "border:SquareMask"
        local atlas = addon.ScootAuras._AtlasFromShapeKey(key) or "SquareMask"
        local ok = pcall(preview.SetAtlas, preview, atlas)
        preview:SetShown(ok)
    end
    UpdatePreview()

    local btn = CreateFrame("Button", nil, row)
    btn:SetSize(160, 24)
    btn:SetPoint("LEFT", preview, "RIGHT", 12, 0)
    local btnBg = btn:CreateTexture(nil, "BACKGROUND")
    btnBg:SetAllPoints()
    local ar, ag, ab = theme:GetAccentColor()
    btnBg:SetColorTexture(ar, ag, ab, 0.12)
    local btnText = btn:CreateFontString(nil, "OVERLAY")
    btnText:SetFont(theme:GetFont("BUTTON"), 12, "")
    btnText:SetPoint("CENTER", 0, 0)
    btnText:SetText("Change Shape")
    btnText:SetTextColor(ar, ag, ab, 1)
    btn:SetScript("OnEnter", function() btnBg:SetColorTexture(ar, ag, ab, 0.25) end)
    btn:SetScript("OnLeave", function() btnBg:SetColorTexture(ar, ag, ab, 0.12) end)
    btn:SetScript("OnClick", function(self)
        if not addon.ShowIconPicker then return end
        -- The picker hides the "use the spell's icon" entry and the Animated
        -- tab for this caller; the callback rejection stays as the backstop.
        addon.ShowIconPicker(self, ctx.get("shapeStyle") or "border:SquareMask", function(selectedKey)
            if type(selectedKey) ~= "string" then return end
            if selectedKey == "spell" or selectedKey:sub(1, 5) == "anim:" then return end
            ctx.setAndApply("shapeStyle", selectedKey)
            UpdatePreview()
            ctx.refreshPreview()
        end, { hideSpellEntry = true, hideAnimatedTab = true })
    end)

    return row
end

function Tabs.BuildShapeTab(tabBuilder, ctx)
    -- Splice the bespoke row into the builder's flow.
    local content = tabBuilder._scrollContent
    local row = CreateShapeStyleRow(content, ctx)
    if #tabBuilder._controls > 0 then
        tabBuilder._currentY = tabBuilder._currentY - 12
    end
    row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, tabBuilder._currentY)
    row:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, tabBuilder._currentY)
    table.insert(tabBuilder._controls, row)
    tabBuilder._currentY = tabBuilder._currentY - row:GetHeight()

    tabBuilder:AddSelectorColorPicker({
        label = "Color",
        values = { class = "Class Color", custom = "Custom" },
        order = { "class", "custom" },
        get = function() return ctx.get("shapeColorMode") or "class" end,
        set = function(v) ctx.setAndApply("shapeColorMode", v) ctx.refreshPreview() end,
        getColor = ColorGet(ctx, "shapeTint"),
        setColor = ColorSet(ctx, "shapeTint"),
        hasAlpha = true,
    })

    tabBuilder:AddToggle({
        label = "Show Drain Sweep",
        description = "Darken the shape progressively as the aura's remaining time runs out.",
        get = function() return ctx.get("shapeShowDrain") ~= false end,
        set = function(v) ctx.setAndApply("shapeShowDrain", v) ctx.refreshPreview() end,
    })

    tabBuilder:Finalize()
end

--------------------------------------------------------------------------------
-- Sizing and Visibility tabs
--------------------------------------------------------------------------------

function Tabs.BuildSizingTab(tabBuilder, ctx)
    tabBuilder:AddSlider({
        label = "Scale",
        description = "Overall scale of the tracker frame (25-200%).",
        min = 25, max = 200, step = 5,
        get = function() return ctx.get("scale") or 100 end,
        set = function(v) ctx.setAndApply("scale", v); ctx.refreshPreview() end,
        minLabel = "25%", maxLabel = "200%",
    })

    tabBuilder:Finalize()
end

function Tabs.BuildVisibilityTab(tabBuilder, ctx)
    tabBuilder:AddDescription(
        "Priority: In Combat > With Target > Out of Combat",
        { color = { 1, 0.82, 0 }, fontSize = 13, topPadding = 4, bottomPadding = 2 }
    )

    tabBuilder:AddSlider({
        label = "Opacity in Combat",
        min = 0, max = 100, step = 1,
        get = function() return ctx.get("opacityInCombat") or 100 end,
        set = function(v) ctx.setAndApply("opacityInCombat", v) end,
        minLabel = "Hidden", maxLabel = "100%",
    })

    tabBuilder:AddSlider({
        label = "Opacity With Target",
        min = 0, max = 100, step = 1,
        get = function() return ctx.get("opacityWithTarget") or 100 end,
        set = function(v) ctx.setAndApply("opacityWithTarget", v) end,
        minLabel = "Hidden", maxLabel = "100%",
    })

    tabBuilder:AddSlider({
        label = "Opacity Out of Combat",
        min = 0, max = 100, step = 1,
        get = function() return ctx.get("opacityOutOfCombat") or 100 end,
        set = function(v) ctx.setAndApply("opacityOutOfCombat", v) end,
        minLabel = "Hidden", maxLabel = "100%",
    })

    tabBuilder:Finalize()
end

--------------------------------------------------------------------------------
-- Tab assembly per shape
--------------------------------------------------------------------------------

--- Returns tabs, buildContent for the editor's tabbed section.
function Tabs.BuildTabSet(ctx)
    local shape = ctx.shape()
    local tabs = {}
    local buildContent = {}

    local function add(key, label, buildFn)
        table.insert(tabs, { key = key, label = label })
        buildContent[key] = function(tabContent, tabBuilder)
            buildFn(tabBuilder, ctx)
        end
    end

    add("sizing", "Sizing", Tabs.BuildSizingTab)

    if shape == "bar" then
        add("bar", "Bar", Tabs.BuildBarTab)
        add("icon", "Icon", Tabs.BuildIconTab)
        add("auraName", "Aura Name", Tabs.BuildAuraNameTab)
    elseif shape == "shape" then
        add("shapeTab", "Shape", Tabs.BuildShapeTab)
    else
        add("icon", "Icon", Tabs.BuildIconTab)
    end

    add("duration", "Duration", Tabs.BuildDurationTab)
    add("stacks", "Stacks", Tabs.BuildStacksTab)
    -- No Visibility tab for buff/debuff tracking: an aura is its own
    -- visibility condition. BuildVisibilityTab stays for the cooldown
    -- tracking mode, where the frame exists with nothing to show.

    return tabs, buildContent
end

return Tabs
