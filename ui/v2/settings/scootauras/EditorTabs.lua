-- EditorTabs.lua - Styling tab bodies for the ScootAura editor
--
-- Generalized from the retired Class Auras renderer's per-aura tabs. Every body reads
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
--   shape()               -> "icon"|"bar"|"shape"|"text"|"icontext"
--   kind()                -> "buff"|"debuff"|"missingbuff"
--   missingVisual()       -> resolved missing-state token, "none" when unset
-- }
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.Settings = addon.UI.Settings or {}
addon.UI.Settings.ScootAuraEditorTabs = {}

local Tabs = addon.UI.Settings.ScootAuraEditorTabs

local OUTSIDE_ANCHOR_VALUES = { LEFT = "Left", RIGHT = "Right", ABOVE = "Above", BELOW = "Below" }
local OUTSIDE_ANCHOR_ORDER = { "LEFT", "RIGHT", "ABOVE", "BELOW" }

-- Text placement inside the host: the nine points; stack text outside: the
-- eight edges and corners. Both are the shared catalogs.
local INSIDE = addon.Catalogs.Anchor9
local OUTSIDE_8 = addon.Catalogs.Anchor8

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

-- Standalone X/Y offset pair over two flat ctx keys
local function AddCtxOffsetPair(tabBuilder, ctx, keyX, keyY)
    tabBuilder:AddOffsetPair({
        range = 50, minLabel = "-50", maxLabel = "+50",
        get = function(axis) return ctx.get(axis == "x" and keyX or keyY) end,
        set = function(axis, v) ctx.setAndApply(axis == "x" and keyX or keyY, v) end,
        apply = ctx.refreshPreview,
    })
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
        if not isBar then return false end
        if ctx.get("barShowIcon") then return false end
        -- A bar-icon missing visual consumes these settings even with Show
        -- Icon off (underlay.lua paints the centered icon from them).
        local traits = ctx.missingVisual
            and addon.ScootAuras.MissingVisualTraits(ctx.missingVisual())
        return not (traits and traits.art == "baricon")
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

    -- Cadence lock (scootauras/cadence.lua).
    tabBuilder:AddToggle({
        label = "Lock Drain to Original Duration",
        description = "Keeps the drain speed tied to the duration the aura was applied with. Refreshes and extensions add to the bar instead of refilling it. If the new duration is longer than the original, the bar still refills and drains at that longer speed. Takes effect the next time the aura is freshly applied.",
        get = function() return ctx.get("barLockCadence") or false end,
        set = function(v) ctx.setAndApply("barLockCadence", v) end,
    })

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
    -- Missing-buff trackers: the name IS the reminder, so there is no hide
    -- toggle; instead the text can carry a "missing!" suffix. It sits beside
    -- the icon (Icon & Text) or alone (Text), never on a bar.
    local isMissing = (ctx.kind and ctx.kind() == "missingbuff")

    if isMissing then
        tabBuilder:AddToggle({
            label = 'Add "___ missing!" to the text',
            description = 'Show the reminder as "<Aura Name> missing!" instead of the name alone.',
            get = function() return ctx.get("missingSuffix") == true end,
            set = function(v) ctx.setAndApply("missingSuffix", v) ctx.refreshPreview() end,
        })
    end

    -- Scoot Aura text is Scoot-drawn, so the paired Deep Shadow styles are
    -- offered on every text tab. The font default mirrors the registered
    -- component default, not a panel-local fallback.
    local get, set = Helpers.CreateFlatAccessors(ctx.get, ctx.setAndApply, {
        hidden = "hideNameText",
        fontFace = "nameTextFont",
        style = "nameTextStyle",
        size = "nameTextSize",
        color = "nameTextColor",
    })
    tabBuilder:AddTextStyleBlock({
        -- The hide toggle defaults on: nil reads as hidden
        get = function(field)
            if field == "hidden" then return ctx.get("hideNameText") ~= false end
            return get(field)
        end,
        set = set,
        apply = ctx.refreshPreview,
        defaults = { fontFace = "ROBOTO_SEMICOND_BLACK", size = 10 },
        hideToggle = (not isMissing) and {
            label = "Hide Aura Name",
            description = "Hide the aura name text on the bar.",
        } or nil,
        font = { description = "The font used for the aura name." },
        -- Deep Shadow needs a FontString Scoot both creates and writes: the
        -- copy is fed by hooks on SetText. Only the missing-buff reminder
        -- qualifies. On a buff or debuff tracker the aura container writes the
        -- spell name natively, so the copy would stay empty.
        style = { order = isMissing and Helpers.fontStyleOrderPaired
            or Helpers.fontStyleOrder },
        size = { min = 6, max = 48, minLabel = "6pt", maxLabel = "48pt" },
        color = { kind = "plain" },
        offset = false,
    })

    if isMissing then
        -- Text alone has nothing to position against; Icon & Text places the
        -- name on one side of the icon.
        if ctx.shape() == "icontext" then
            tabBuilder:AddSelector({
                label = "Position",
                description = "Which side of the icon the name sits on.",
                values = OUTSIDE_ANCHOR_VALUES,
                order = OUTSIDE_ANCHOR_ORDER,
                get = function() return ctx.get("nameTextOuterAnchor") or "RIGHT" end,
                set = function(v) ctx.setAndApply("nameTextOuterAnchor", v) ctx.refreshPreview() end,
            })

            AddCtxOffsetPair(tabBuilder, ctx, "nameTextOffsetX", "nameTextOffsetY")
        end

        tabBuilder:Finalize()
        return
    end

    local currentPos = ctx.get("nameTextPosition") or "inside"
    local bValues = currentPos == "outside" and OUTSIDE_ANCHOR_VALUES or INSIDE.values
    local bOrder = currentPos == "outside" and OUTSIDE_ANCHOR_ORDER or INSIDE.order

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
                        dual:SetOptionsB(INSIDE.values, INSIDE.order)
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

    AddCtxOffsetPair(tabBuilder, ctx, "nameTextOffsetX", "nameTextOffsetY")

    tabBuilder:Finalize()
end

--------------------------------------------------------------------------------
-- Duration tab (remaining-time text)
--------------------------------------------------------------------------------

function Tabs.BuildDurationTab(tabBuilder, ctx)
    local Helpers = addon.UI.Settings.Helpers

    -- Scoot Aura text is Scoot-drawn, so the paired Deep Shadow styles are
    -- offered here.
    local get, set = Helpers.CreateFlatAccessors(ctx.get, ctx.setAndApply, {
        hidden = "hideText",
        fontFace = "textFont",
        style = "textStyle",
        size = "textSize",
        color = "textColor",
    })
    tabBuilder:AddTextStyleBlock({
        get = get, set = set, apply = ctx.refreshPreview,
        defaults = { fontFace = "ROBOTO_SEMICOND_BLACK", size = 24 },
        hideToggle = {
            label = "Hide Duration Text",
            description = "Hide the remaining-time text.",
        },
        font = { description = "The font used for the duration text." },
        -- Engine-written text: no Deep Shadow (see the aura name block).
        style = { order = Helpers.fontStyleOrder },
        size = { min = 6, max = 48, minLabel = "6pt", maxLabel = "48pt",
            description = "Size of the duration text in points." },
        color = { kind = "plain" },
        offset = false,
    })

    local shape = ctx.shape()
    local host = (shape == "bar") and "Bar" or (shape == "shape") and "Shape" or "Icon"
    local currentPos = ctx.get("textPosition") or "inside"
    local bValues = currentPos == "outside" and OUTSIDE_ANCHOR_VALUES or INSIDE.values
    local bOrder = currentPos == "outside" and OUTSIDE_ANCHOR_ORDER or INSIDE.order

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
                        dual:SetOptionsB(INSIDE.values, INSIDE.order)
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

    AddCtxOffsetPair(tabBuilder, ctx, "textOffsetX", "textOffsetY")

    tabBuilder:Finalize()
end

--------------------------------------------------------------------------------
-- Stacks tab (stack counter text)
--------------------------------------------------------------------------------

function Tabs.BuildStacksTab(tabBuilder, ctx)
    local Helpers = addon.UI.Settings.Helpers

    -- Scoot Aura text is Scoot-drawn, so the paired Deep Shadow styles are
    -- offered here.
    local get, set = Helpers.CreateFlatAccessors(ctx.get, ctx.setAndApply, {
        hidden = "hideStackText",
        fontFace = "stackTextFont",
        style = "stackTextStyle",
        size = "stackTextSize",
        color = "stackTextColor",
    })
    tabBuilder:AddTextStyleBlock({
        get = get, set = set, apply = ctx.refreshPreview,
        defaults = { fontFace = "ROBOTO_SEMICOND_BLACK", size = 14 },
        hideToggle = {
            label = "Hide Stacks Text",
            description = "Hide the stack counter.",
        },
        font = { description = "The font used for the stack counter." },
        -- Engine-written text: no Deep Shadow (see the aura name block).
        style = { order = Helpers.fontStyleOrder },
        size = { min = 6, max = 48, minLabel = "6pt", maxLabel = "48pt",
            description = "Size of the stack counter in points." },
        color = { kind = "plain" },
        offset = false,
    })

    local shape = ctx.shape()
    local host = (shape == "bar") and "Bar" or (shape == "shape") and "Shape" or "Icon"
    local currentPos = ctx.get("stackTextPosition") or "inside"
    local bValues = currentPos == "outside" and OUTSIDE_8.values or INSIDE.values
    local bOrder = currentPos == "outside" and OUTSIDE_8.order or INSIDE.order

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
                        dual:SetOptionsB(OUTSIDE_8.values, OUTSIDE_8.order)
                    else
                        dual:SetOptionsB(INSIDE.values, INSIDE.order)
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

    AddCtxOffsetPair(tabBuilder, ctx, "stackTextOffsetX", "stackTextOffsetY")

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
        values = addon.Catalogs.ColorMode.ClassCustom.values,
        order = addon.Catalogs.ColorMode.ClassCustom.order,
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

--------------------------------------------------------------------------------
-- Animations tab (missing-buff trackers)
--------------------------------------------------------------------------------

function Tabs.BuildAnimationsTab(tabBuilder, ctx)
    tabBuilder:AddToggle({
        label = "Make the tracker blink when present",
        description = "Pulse the reminder while it is showing, so a missing buff is harder to overlook.",
        get = function() return ctx.get("blinkWhenShown") == true end,
        set = function(v) ctx.setAndApply("blinkWhenShown", v) ctx.refreshPreview() end,
    })

    tabBuilder:Finalize()
end

--------------------------------------------------------------------------------
-- Tab assembly per shape
--------------------------------------------------------------------------------

--- Returns tabs, buildContent for the editor's tabbed section.
function Tabs.BuildTabSet(ctx)
    local shape = ctx.shape()
    local kind = ctx.kind and ctx.kind() or "buff"
    local tabs = {}
    local buildContent = {}

    local function add(key, label, buildFn)
        table.insert(tabs, { key = key, label = label })
        buildContent[key] = function(tabContent, tabBuilder)
            buildFn(tabBuilder, ctx)
        end
    end

    add("sizing", "Sizing", Tabs.BuildSizingTab)

    if kind == "missingbuff" then
        -- A reminder has no duration or stacks. Icon and/or Aura Name follow
        -- the shape; Animations carries the blink.
        if shape ~= "text" then
            add("icon", "Icon", Tabs.BuildIconTab)
        end
        if shape ~= "icon" then
            add("auraName", "Aura Name", Tabs.BuildAuraNameTab)
        end
        add("animations", "Animations", Tabs.BuildAnimationsTab)
        return tabs, buildContent
    end

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
