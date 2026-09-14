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
--   shape()               -> "icon"|"bar"|"shape"|"text"|"icontext"|"icons"
--   kind()                -> "buff"|"debuff"|"missingbuff"|"classpower"|"classresource"
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
            get = function() return ctx.get("barIconSide") or "LEFT" end,
            set = function(v) ctx.setAndApply("barIconSide", v) ctx.refreshPreview() end,
        })
        local gapSlider = Controls:CreateSlider({
            parent = content,
            label = "Bar/Icon Gap",
            min = 0, max = 30, step = 1,
            width = 100,
            inputWidth = 40,
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

    local get, set = Helpers.CreateIconBorderAccessors(ctx.get, ctx.setAndApply, "border")
    tabBuilder:AddIconBorderBlock({
        get = get, set = set, apply = ctx.refreshPreview,
        refresh = ctx.refresh,   -- the thickness row appears per style
        disabled = iconControlsDisabled,
        style = { prefixEntries = { { "none", "None" } }, default = "none", description = "Choose the visual style for icon borders." },
        tint = { description = "Apply a custom tint color to the icon border." },
        thickness = { description = "Thickness of the border in pixels." },
    })

    tabBuilder:Finalize()
end

--------------------------------------------------------------------------------
-- Bar tab
--------------------------------------------------------------------------------

-- Bar Size, shared by the aura bar and the Class Power bar.
-- Kept off Builder:AddOffsetPair: the pair is bar width and bar height, each with its own range.
local function AddBarSizeRow(tabBuilder, ctx)
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
end

-- The style and border blocks, shared by the aura bar and the Class Power
-- bar. `foreground` is the fill's color-mode list; `mapFillMode`, when given,
-- coerces a stored mode onto that list.
local function AddBarStyleAndBorderBlocks(tabBuilder, ctx, foreground, mapFillMode)
    local Helpers = addon.UI.Settings.Helpers
    local rawGet, barWrite = Helpers.CreateFlatAccessors(ctx.get, ctx.setAndApply, {
        texture = "barForegroundTexture", colorMode = "barForegroundColorMode", color = "barForegroundTint",
        bgTexture = "barBackgroundTexture", bgColorMode = "barBackgroundColorMode", bgColor = "barBackgroundTint",
        bgOpacity = "barBackgroundOpacity",
        style = "barBorderStyle", hiddenEdges = "barBorderHiddenEdges",
        tintEnabled = "barBorderTintEnable", tintColor = "barBorderTintColor",
        thickness = "barBorderThickness", insetH = "barBorderInsetH", insetV = "barBorderInsetV",
    })
    local function barGet(field)
        local v = rawGet(field)
        if field == "colorMode" and mapFillMode then return mapFillMode(v) end
        return v
    end
    -- ctx.setAndApply writes and applies. A color mode, border style, or tint
    -- toggle change re-renders the tab (the swatch and edge controls follow
    -- it); anything else refreshes the preview.
    local REFRESHES_TAB = { colorMode = true, bgColorMode = true, style = true, tintEnabled = true }
    local function barSet(field, value)
        barWrite(field, value)
        if REFRESHES_TAB[field] then ctx.refresh() else ctx.refreshPreview() end
    end

    tabBuilder:AddBarStyleBlock({
        get = barGet, set = barSet,
        foreground = foreground,
        background = {
            values = { custom = "Custom", original = "Texture Original" },
            order = { "custom", "original" },
            textureDefault = "bevelled", colorModeDefault = "custom",
        },
        opacity = { minLabel = "0%", maxLabel = "100%" },
    })

    tabBuilder:AddBarBorderBlock({
        get = barGet, set = barSet,
        style = { default = "none" },
        thickness = { clamp = false, minLabel = "1", maxLabel = "8" },
    })
end

function Tabs.BuildBarTab(tabBuilder, ctx)
    AddBarSizeRow(tabBuilder, ctx)

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

    AddBarStyleAndBorderBlocks(tabBuilder, ctx, {
        values = { custom = "Custom", class = "Class Color", original = "Texture Original" },
        order = { "custom", "class", "original" },
        infoIcons = false, textureDefault = "bevelled", colorModeDefault = "class",
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

local AddTextPositionControls

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

    AddTextPositionControls(tabBuilder, ctx)

    tabBuilder:Finalize()
end

-- Position (inside or outside the host, with the anchor) and the offset pair
-- for the duration-slot text: the aura Duration tab and the Class Power
-- number on a bar.
function AddTextPositionControls(tabBuilder, ctx)
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
-- subtrees in combat). `opts` names the key, label, button text and default
-- so the Class Resource Icons tab can share the row.
local function CreateShapeStyleRow(parent, ctx, opts)
    opts = opts or {}
    local key = opts.key or "shapeStyle"
    local default = opts.default or "border:SquareMask"
    local theme = addon.UI.Theme
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(36)

    local label = row:CreateFontString(nil, "OVERLAY")
    label:SetFont(theme:GetFont("LABEL"), 13, "")
    label:SetPoint("LEFT", row, "LEFT", 8, 0)
    label:SetText(opts.label or "Shape")
    label:SetTextColor(theme:GetAccentColor())

    local preview = row:CreateTexture(nil, "ARTWORK")
    preview:SetSize(26, 26)
    preview:SetPoint("LEFT", row, "LEFT", 120, 0)

    local function UpdatePreview()
        local atlas = addon.ScootAuras._AtlasFromShapeKey(ctx.get(key) or default) or "SquareMask"
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
    btnText:SetText(opts.button or "Change Shape")
    btnText:SetTextColor(ar, ag, ab, 1)
    btn:SetScript("OnEnter", function() btnBg:SetColorTexture(ar, ag, ab, 0.25) end)
    btn:SetScript("OnLeave", function() btnBg:SetColorTexture(ar, ag, ab, 0.12) end)
    btn:SetScript("OnClick", function(self)
        if not addon.ShowIconPicker then return end
        -- The picker hides the "use the spell's icon" entry and the Animated
        -- tab for this caller; the callback rejection stays as the backstop.
        addon.ShowIconPicker(self, ctx.get(key) or default, function(selectedKey)
            if type(selectedKey) ~= "string" then return end
            if selectedKey == "spell" or selectedKey:sub(1, 5) == "anim:" then return end
            ctx.setAndApply(key, selectedKey)
            UpdatePreview()
            ctx.refreshPreview()
        end, { hideSpellEntry = true, hideAnimatedTab = true })
    end)

    return row
end

-- Splices a bespoke row into the builder's flow.
local function SpliceRow(tabBuilder, row)
    local content = tabBuilder._scrollContent
    if #tabBuilder._controls > 0 then
        tabBuilder._currentY = tabBuilder._currentY - 12
    end
    row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, tabBuilder._currentY)
    row:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, tabBuilder._currentY)
    table.insert(tabBuilder._controls, row)
    tabBuilder._currentY = tabBuilder._currentY - row:GetHeight()
end

function Tabs.BuildShapeTab(tabBuilder, ctx)
    SpliceRow(tabBuilder, CreateShapeStyleRow(tabBuilder._scrollContent, ctx))

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
-- Class Power tabs (scootauras/classpower.lua): the bar and the number
--------------------------------------------------------------------------------

local POWER_COLOR_VALUES = { power = "Power Color", custom = "Custom" }
local POWER_COLOR_ORDER = { "power", "custom" }
-- The number adds Default (white) and names the power color the way the
-- power texts do (core/catalogs.lua).
local POWER_TEXT_COLOR_VALUES = { default = "Default", power = "Class Power Color", custom = "Custom" }
local POWER_TEXT_COLOR_ORDER = { "default", "power", "custom" }

-- Any mode but Custom reads as Power Color on this kind: the fill key's
-- registered default is the aura bars' Class Color, and a value a spell
-- tracker set before a kind flip must not leave the selector on an option
-- it lacks.
local function PowerOrCustom(mode)
    return (mode == "custom") and "custom" or "power"
end

-- The number's three modes; anything else reads as Default.
local function DefaultPowerOrCustom(mode)
    if mode == "custom" or mode == "power" then return mode end
    return "default"
end

function Tabs.BuildClassPowerBarTab(tabBuilder, ctx)
    AddBarSizeRow(tabBuilder, ctx)

    tabBuilder:AddToggle({
        label = "Smooth Fill",
        description = "Ease the bar toward each new value instead of snapping to it.",
        get = function() return ctx.get("barSmoothFill") ~= false end,
        set = function(v) ctx.setAndApply("barSmoothFill", v) end,
    })

    AddBarStyleAndBorderBlocks(tabBuilder, ctx, {
        values = POWER_COLOR_VALUES,
        order = POWER_COLOR_ORDER,
        infoIcons = false, textureDefault = "bevelled", colorModeDefault = "power",
    }, PowerOrCustom)

    tabBuilder:Finalize()
end

function Tabs.BuildClassPowerTextTab(tabBuilder, ctx)
    local Helpers = addon.UI.Settings.Helpers
    local isBar = ctx.shape() == "bar"

    local rawGet, set = Helpers.CreateFlatAccessors(ctx.get, ctx.setAndApply, {
        hidden = "hideText",
        fontFace = "textFont",
        style = "textStyle",
        size = "textSize",
        colorMode = "textColorMode",
        color = "textColor",
    })
    local function get(field)
        local v = rawGet(field)
        if field == "colorMode" then return DefaultPowerOrCustom(v) end
        return v
    end
    tabBuilder:AddTextStyleBlock({
        get = get, set = set, apply = ctx.refreshPreview,
        -- The number alone starts in Anton Wide 1.5x and the power color
        -- (SAU.ClassPowerNumberStartingValues); the bar's number in the
        -- registered face and white.
        defaults = { fontFace = isBar and "ROBOTO_SEMICOND_BLACK" or "ANTON_WIDE_150",
            style = "SHADOWTHICKOUTLINESLUG", size = isBar and 12 or 24,
            colorMode = isBar and "default" or "power" },
        -- The number alone is the whole tracker; only on the bar can it hide.
        hideToggle = isBar and {
            label = "Hide Number",
            description = "Hide the number on the bar.",
        } or nil,
        font = { description = "The font used for the number." },
        -- Scoot writes this string itself (classpower.lua), so the paired
        -- Deep Shadow styles render here.
        style = { order = Helpers.fontStyleOrderPaired },
        size = { min = 6, max = 48, minLabel = "6pt", maxLabel = "48pt",
            description = "Size of the number in points." },
        color = { kind = "selector", values = POWER_TEXT_COLOR_VALUES, order = POWER_TEXT_COLOR_ORDER },
        offset = false,
    })

    if isBar then
        AddTextPositionControls(tabBuilder, ctx)
    else
        AddCtxOffsetPair(tabBuilder, ctx, "textOffsetX", "textOffsetY")
    end

    tabBuilder:Finalize()
end

--------------------------------------------------------------------------------
-- Class Resource tabs (scootauras/classresource.lua): the segmented bar and
-- its ticks, or the icon row and its backdrop; the fill list follows the
-- character's resource
--------------------------------------------------------------------------------

-- The fill: the resource's own color, the class color, or a tint. Class Power
-- keeps its two-entry list above.
local RESOURCE_COLOR_VALUES = { power = "Power Color", class = "Class Color", custom = "Custom" }
local RESOURCE_COLOR_ORDER = { "power", "class", "custom" }

-- Any other stored mode reads as Power Color: a value a spell tracker set
-- before a kind flip must not leave the selector on an option it lacks.
local function PowerClassOrCustom(mode)
    if mode == "class" or mode == "custom" then return mode end
    return "power"
end

-- Combo Points have no power color of their own: the fill is the class color
-- or a tint, and the list offers those two alone. A stored `power` (the
-- kind's starting value) reads here, and paints in the engine, as Class
-- Color.
local COMBO_COLOR_VALUES = { class = "Class Color", custom = "Custom" }
local COMBO_COLOR_ORDER = { "class", "custom" }

local function ClassOrCustom(mode)
    if mode == "custom" then return "custom" end
    return "class"
end

-- Sub-option on the Combo Points fill selectors, opened by the gear inside
-- the field (ui/v2/controls/SelectorGear.lua): the last two points in their
-- own colors. One page for both options, since the tail applies whatever the
-- base color is. The toggle writes through ctx.setAndApply and refreshes the
-- preview alone; a page that re-rendered the tab would destroy the gear its
-- own fly-out is anchored to.
local function VariedTailGear(ctx)
    local page = {
        tooltip = "Options for the combo point colors",
        width = 340,
        height = 96,
        build = function(content)
            local Controls = addon.UI.Controls
            local theme = addon.UI.Theme
            local toggle = Controls:CreateToggle({
                parent = content,
                label = "Varied Color for Last 2 Combo Points",
                get = function() return ctx.get("variedLastPoints") ~= false end,
                set = function(v)
                    ctx.setAndApply("variedLastPoints", v and true or false)
                    ctx.refreshPreview()
                end,
            })
            if not toggle then return end
            toggle:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
            toggle:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, 0)

            local hint = content:CreateFontString(nil, "OVERLAY")
            hint:SetFont(theme:GetFont("VALUE"), 11, "")
            hint:SetPoint("TOPLEFT", toggle, "BOTTOMLEFT", 12, -2)
            hint:SetPoint("TOPRIGHT", toggle, "BOTTOMRIGHT", -12, -2)
            hint:SetJustifyH("LEFT")
            hint:SetWordWrap(true)
            hint:SetText("The last point is crimson; the one before it sits halfway between the fill color and that crimson.")
            local dimR, dimG, dimB = theme:GetDimTextColor()
            hint:SetTextColor(dimR, dimG, dimB, 1)
        end,
    }
    return { direction = "DOWN", gap = 8, pages = { class = page, custom = page } }
end

-- The character's resource decides the fill list, the coercion of a stored
-- mode, and the gear: Combo Points offer Class Color and Custom with the
-- varied-tail gear on both; every other resource offers Power Color, Class
-- Color and Custom with none.
local function ResourceColorOptions(ctx)
    local CR = addon.ScootAuras and addon.ScootAuras.ClassResource
    local rec = CR and CR.CurrentResource and CR.CurrentResource()
    local res = rec and rec.res
    if res and res.classColor then
        local gear = res.variedTail and VariedTailGear(ctx) or nil
        return COMBO_COLOR_VALUES, COMBO_COLOR_ORDER, ClassOrCustom, gear
    end
    return RESOURCE_COLOR_VALUES, RESOURCE_COLOR_ORDER, PowerClassOrCustom, nil
end

function Tabs.BuildClassResourceBarTab(tabBuilder, ctx)
    AddBarSizeRow(tabBuilder, ctx)

    local values, order, coerce, gear = ResourceColorOptions(ctx)
    AddBarStyleAndBorderBlocks(tabBuilder, ctx, {
        values = values,
        order = order,
        colorGear = gear,
        infoIcons = false, textureDefault = "bevelled", colorModeDefault = order[1],
    }, coerce)

    tabBuilder:Finalize()
end

function Tabs.BuildClassResourceTicksTab(tabBuilder, ctx)
    tabBuilder:AddSlider({
        label = "Tick Thickness",
        description = "Width of the line between segments, in pixels. 0 draws no ticks.",
        min = 0, max = 8, step = 1,
        get = function() return ctx.get("tickThickness") or 2 end,
        set = function(v) ctx.setAndApply("tickThickness", v); ctx.refreshPreview() end,
        minLabel = "None", maxLabel = "8",
    })

    tabBuilder:AddColorPicker({
        label = "Tick Color",
        description = "Color of the lines between segments.",
        hasAlpha = true,
        get = ColorGet(ctx, "tickColor", { 0, 0, 0, 1 }),
        set = ColorSet(ctx, "tickColor"),
    })

    tabBuilder:Finalize()
end

function Tabs.BuildClassResourceIconsTab(tabBuilder, ctx)
    SpliceRow(tabBuilder, CreateShapeStyleRow(tabBuilder._scrollContent, ctx, {
        key = "pipStyle", label = "Icon", button = "Change Icon", default = "border:SquareMask",
    }))

    tabBuilder:AddSlider({
        label = "Icon Size",
        description = "Size of each icon in pixels.",
        min = 8, max = 48, step = 1,
        get = function() return ctx.get("pipSize") or 16 end,
        set = function(v) ctx.setAndApply("pipSize", v); ctx.refreshPreview() end,
        minLabel = "8", maxLabel = "48",
    })

    tabBuilder:AddSlider({
        label = "Icon Spacing",
        description = "Gap between icons in pixels. Negative values overlap them.",
        min = -4, max = 20, step = 1,
        get = function() return ctx.get("pipSpacing") or 2 end,
        set = function(v) ctx.setAndApply("pipSpacing", v); ctx.refreshPreview() end,
        minLabel = "-4", maxLabel = "20",
    })

    local values, order, coerce, gear = ResourceColorOptions(ctx)
    tabBuilder:AddSelectorColorPicker({
        label = "Color",
        values = values,
        order = order,
        get = function() return coerce(ctx.get("pipColorMode")) end,
        set = function(v) ctx.setAndApply("pipColorMode", v) ctx.refreshPreview() end,
        getColor = ColorGet(ctx, "pipTint"),
        setColor = ColorSet(ctx, "pipTint"),
        hasAlpha = true,
        gear = gear,
    })

    tabBuilder:Finalize()
end

function Tabs.BuildClassResourceBackdropTab(tabBuilder, ctx)
    tabBuilder:AddColorPicker({
        label = "Backdrop Color",
        description = "Drawn beneath every icon; an empty point shows it alone.",
        hasAlpha = false,
        get = ColorGet(ctx, "pipBackdropTint", { 0, 0, 0, 1 }),
        set = ColorSet(ctx, "pipBackdropTint"),
    })

    tabBuilder:AddSlider({
        label = "Backdrop Opacity",
        description = "Opacity of the backdrop beneath the icons.",
        min = 0, max = 100, step = 1,
        get = function() return ctx.get("pipBackdropOpacity") or 100 end,
        set = function(v) ctx.setAndApply("pipBackdropOpacity", v); ctx.refreshPreview() end,
        minLabel = "0%", maxLabel = "100%",
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
    local Helpers = addon.UI.Settings.Helpers
    local get, set = Helpers.CreateFlatAccessors(ctx.get, ctx.setAndApply, addon.Opacity.Keys.InCombat)
    tabBuilder:AddStateOpacityBlock({ get = get, set = set, min = 0 })

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
-- Misc tab (buff and debuff icon trackers)
--------------------------------------------------------------------------------

function Tabs.BuildMiscTab(tabBuilder, ctx)
    -- Pandemic border (styling.lua ApplyBorders, regions.lua PreCreatePandemic):
    -- the engine's own refresh window on a buff or debuff icon. No preview
    -- refresh: neither preview draws it.
    tabBuilder:AddToggle({
        label = "Pandemic Border",
        description = "Pulse a red border during the pandemic window.",
        get = function() return ctx.get("pandemicBorder") ~= false end,
        set = function(v) ctx.setAndApply("pandemicBorder", v) end,
    })

    -- Icon swipe (styling.lua ApplyIconSwipe); both previews draw it.
    tabBuilder:AddToggle({
        label = "Show Duration Swipe",
        description = "The icon sweeps away clockwise as the aura runs out, uncovering a desaturated copy.",
        get = function() return ctx.get("iconShowSwipe") ~= false end,
        set = function(v) ctx.setAndApply("iconShowSwipe", v) ctx.refreshPreview() end,
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

    if kind == "classpower" then
        -- No aura: the bar (Bar shape) and the number, then Visibility, since
        -- the frame is up whether or not anything is happening to it.
        if shape == "bar" then
            add("bar", "Bar", Tabs.BuildClassPowerBarTab)
        end
        add("text", "Text", Tabs.BuildClassPowerTextTab)
        add("visibility", "Visibility", Tabs.BuildVisibilityTab)
        return tabs, buildContent
    end

    if kind == "classresource" then
        -- One point per pip: the segmented bar and its ticks, or the icon
        -- row over its backdrop; then Visibility, since the frame is up
        -- regardless.
        if shape == "icons" then
            add("icons", "Icons", Tabs.BuildClassResourceIconsTab)
            add("backdrop", "Backdrop", Tabs.BuildClassResourceBackdropTab)
        else
            add("bar", "Bar", Tabs.BuildClassResourceBarTab)
            add("ticks", "Ticks", Tabs.BuildClassResourceTicksTab)
        end
        add("visibility", "Visibility", Tabs.BuildVisibilityTab)
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
    if shape == "icon" then
        add("misc", "Misc", Tabs.BuildMiscTab)
    end
    -- No Visibility tab for buff/debuff tracking: an aura is its own
    -- visibility condition. BuildVisibilityTab serves the kinds whose frame
    -- is always up (Class Power above; cooldowns later).

    return tabs, buildContent
end

return Tabs
