-- StartHereRenderer.lua - Module toggles page ("Features")
-- Three-column flat layout with always-visible sub-toggles.
-- Static RELOAD button below the scrollable area inverts when changes are pending.
local _, addon = ...

addon.UI = addon.UI or {}
addon.UI.Settings = addon.UI.Settings or {}

local StartHere = {}
addon.UI.Settings.StartHere = StartHere

--------------------------------------------------------------------------------
-- Constants (sized for 3-column layout in ~850px scroll content)
--------------------------------------------------------------------------------

local ROW_HEIGHT = 24
local INDICATOR_WIDTH = 37
local INDICATOR_HEIGHT = 14
local INDICATOR_BORDER = 2
local ROW_PADDING = 8
local SUB_INDENT = 14
local COLUMN_GAP = 12
local RELOAD_AREA_HEIGHT = 46      -- single row: RELOAD button with caption to its right
local HEADER_TOP_PAD = 6           -- breathing room above the "Modules" title
-- Below this content width the module columns get crushed; the page locks the
-- scroll content to it and pans horizontally instead (~250px per column)
local FEATURES_MIN_CONTENT_WIDTH = 760
local HSCROLL_HEIGHT = 8
local HSCROLL_THUMB_MIN = 30
local LABEL_FONT_SIZE = 10
local SUB_LABEL_FONT_SIZE = 10
local INDICATOR_FONT_SIZE = 9
local NUM_COLUMNS = 3
local LEGEND_ICON_SIZE = 14
local LEGEND_TEXT_GAP = 6
local LEGEND_ROW_GAP = 6
local LEGEND_FONT_SIZE = 10
local HEADER_COL_GAP = 16          -- gap between the title/intro column and the legend column
local LEGEND_RIGHT_INSET = 14      -- keeps the top legend line clear of the panel close button
local VARIANT_ICON_SIZE = 10       -- tiny per-variant badges beside labels
local VARIANT_ICON_FONT_SIZE = 5   -- about half of LABEL_FONT_SIZE
-- This page raises the whole content pane into the title-bar dead space (normally
-- reserved at -80). The header buttons centered on the frame's top edge reach 13px
-- below it; -18 clears them, and the close button band (y -10..-34) only spans the
-- far-right 24px where this page draws nothing that high.
local PANE_TOP_OFFSET = -18

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function deepCopy(t)
    if type(t) ~= "table" then return t end
    local copy = {}
    for k, v in pairs(t) do copy[k] = deepCopy(v) end
    return copy
end

--- Compute the display row count for a category (header + sub-toggle rows).
local function CategoryRowCount(catDef)
    if catDef.mutuallyExclusive then
        return 1  -- single row with variant selector
    end
    if catDef.subToggles and #catDef.subToggles > 0 then
        return 1 + #catDef.subToggles  -- header row + one row per sub-toggle
    end
    return 1  -- single toggle row
end

--- Find optimal column split points for N columns that minimize max column height.
--- Returns an array of split indices: categories[1..splits[1]], [splits[1]+1..splits[2]], etc.
local function ComputeColumnSplits(categories, numCols)
    local n = #categories
    -- Compute heights
    local heights = {}
    for i = 1, n do
        local catDef = addon.MODULE_CATEGORIES[categories[i]]
        heights[i] = catDef and CategoryRowCount(catDef) or 1
    end
    -- Prefix sums
    local prefix = { [0] = 0 }
    for i = 1, n do prefix[i] = prefix[i - 1] + heights[i] end

    if numCols == 3 and n >= 3 then
        -- O(n^2) brute-force: try all (i, j) split points
        local bestMax = math.huge
        local bestI, bestJ = 1, 2
        for i = 1, n - 2 do
            for j = i + 1, n - 1 do
                local h1 = prefix[i]
                local h2 = prefix[j] - prefix[i]
                local h3 = prefix[n] - prefix[j]
                local maxH = math.max(h1, math.max(h2, h3))
                if maxH < bestMax then
                    bestMax = maxH
                    bestI = i
                    bestJ = j
                end
            end
        end
        return { bestI, bestJ, n }
    end

    -- Fallback: equal split
    local splits = {}
    for c = 1, numCols do
        splits[c] = math.floor(n * c / numCols)
    end
    return splits
end

--------------------------------------------------------------------------------
-- Page State (lives for the duration of a single Features page visit)
--------------------------------------------------------------------------------

local pageState = {
    dirty = false,
    rows = {},
    columns = {},   -- array of column frames
    snapshot = nil,
}

--------------------------------------------------------------------------------
-- ON/OFF Indicator (right-side toggle button)
--------------------------------------------------------------------------------

local function CreateIndicator(parent, theme)
    local ar, ag, ab = theme:GetAccentColor()
    local dimR, dimG, dimB = theme:GetDimTextColor()

    local indicator = CreateFrame("Button", nil, parent)
    indicator:SetSize(INDICATOR_WIDTH, INDICATOR_HEIGHT)
    indicator:RegisterForClicks("AnyUp")

    -- Border textures
    local border = {}

    local top = indicator:CreateTexture(nil, "BORDER", nil, -1)
    top:SetPoint("TOPLEFT", 0, 0)
    top:SetPoint("TOPRIGHT", 0, 0)
    top:SetHeight(INDICATOR_BORDER)
    top:SetColorTexture(ar, ag, ab, 1)
    border.TOP = top

    local bottom = indicator:CreateTexture(nil, "BORDER", nil, -1)
    bottom:SetPoint("BOTTOMLEFT", 0, 0)
    bottom:SetPoint("BOTTOMRIGHT", 0, 0)
    bottom:SetHeight(INDICATOR_BORDER)
    bottom:SetColorTexture(ar, ag, ab, 1)
    border.BOTTOM = bottom

    local left = indicator:CreateTexture(nil, "BORDER", nil, -1)
    left:SetPoint("TOPLEFT", 0, -INDICATOR_BORDER)
    left:SetPoint("BOTTOMLEFT", 0, INDICATOR_BORDER)
    left:SetWidth(INDICATOR_BORDER)
    left:SetColorTexture(ar, ag, ab, 1)
    border.LEFT = left

    local right = indicator:CreateTexture(nil, "BORDER", nil, -1)
    right:SetPoint("TOPRIGHT", 0, -INDICATOR_BORDER)
    right:SetPoint("BOTTOMRIGHT", 0, INDICATOR_BORDER)
    right:SetWidth(INDICATOR_BORDER)
    right:SetColorTexture(ar, ag, ab, 1)
    border.RIGHT = right

    indicator._border = border

    -- Fill background (visible when ON)
    local fill = indicator:CreateTexture(nil, "BACKGROUND", nil, -7)
    fill:SetPoint("TOPLEFT", INDICATOR_BORDER, -INDICATOR_BORDER)
    fill:SetPoint("BOTTOMRIGHT", -INDICATOR_BORDER, INDICATOR_BORDER)
    fill:SetColorTexture(ar, ag, ab, 1)
    fill:Hide()
    indicator._fill = fill

    -- ON/OFF text
    local text = indicator:CreateFontString(nil, "OVERLAY")
    text:SetFont(theme:GetFont("BUTTON"), INDICATOR_FONT_SIZE, "")
    text:SetPoint("CENTER", 0, 0)
    text:SetText("OFF")
    text:SetTextColor(dimR, dimG, dimB, 1)
    indicator._text = text

    function indicator:UpdateState(isOn, variant)
        local r, g, b = theme:GetAccentColor()
        local dR, dG, dB = theme:GetDimTextColor()
        -- Blizzard-owned features show their variant letter (green "X") when ON;
        -- addon-original features keep the plain accent "ON".
        local vc = variant and addon.VARIANT_COLORS and addon.VARIANT_COLORS[variant]
        local onR, onG, onB = r, g, b
        if vc then
            onR, onG, onB = vc[1], vc[2], vc[3]
        end
        if isOn then
            self._fill:SetColorTexture(onR, onG, onB, 1)
            self._fill:Show()
            self._text:SetText(vc and variant or "ON")
            self._text:SetTextColor(0, 0, 0, 1)
            for _, tex in pairs(self._border) do tex:SetColorTexture(onR, onG, onB, 1) end
        else
            self._fill:Hide()
            self._text:SetText("OFF")
            self._text:SetTextColor(dR, dG, dB, 1)
            for _, tex in pairs(self._border) do tex:SetColorTexture(r, g, b, 0.4) end
        end
    end

    return indicator
end

--------------------------------------------------------------------------------
-- Variant Selector (compact cycling selector for mutuallyExclusive categories)
--------------------------------------------------------------------------------

--- @param allowOff boolean|nil  false = the selector always shows a variant and
---        cycles between them; nil/true keeps the OFF state in the cycle.
local function CreateVariantSelector(parent, theme, subToggles, allowOff)
    allowOff = (allowOff ~= false)
    local ar, ag, ab = theme:GetAccentColor()
    local dimR, dimG, dimB = theme:GetDimTextColor()

    local selector = CreateFrame("Button", nil, parent)
    selector:SetSize(INDICATOR_WIDTH, INDICATOR_HEIGHT)
    selector:RegisterForClicks("AnyUp")

    -- Border textures (same pattern as CreateIndicator)
    local border = {}

    local top = selector:CreateTexture(nil, "BORDER", nil, -1)
    top:SetPoint("TOPLEFT", 0, 0)
    top:SetPoint("TOPRIGHT", 0, 0)
    top:SetHeight(INDICATOR_BORDER)
    top:SetColorTexture(ar, ag, ab, 0.4)
    border.TOP = top

    local bottom = selector:CreateTexture(nil, "BORDER", nil, -1)
    bottom:SetPoint("BOTTOMLEFT", 0, 0)
    bottom:SetPoint("BOTTOMRIGHT", 0, 0)
    bottom:SetHeight(INDICATOR_BORDER)
    bottom:SetColorTexture(ar, ag, ab, 0.4)
    border.BOTTOM = bottom

    local left = selector:CreateTexture(nil, "BORDER", nil, -1)
    left:SetPoint("TOPLEFT", 0, -INDICATOR_BORDER)
    left:SetPoint("BOTTOMLEFT", 0, INDICATOR_BORDER)
    left:SetWidth(INDICATOR_BORDER)
    left:SetColorTexture(ar, ag, ab, 0.4)
    border.LEFT = left

    local right = selector:CreateTexture(nil, "BORDER", nil, -1)
    right:SetPoint("TOPRIGHT", 0, -INDICATOR_BORDER)
    right:SetPoint("BOTTOMRIGHT", 0, INDICATOR_BORDER)
    right:SetWidth(INDICATOR_BORDER)
    right:SetColorTexture(ar, ag, ab, 0.4)
    border.RIGHT = right

    selector._border = border

    -- Fill background
    local fill = selector:CreateTexture(nil, "BACKGROUND", nil, -7)
    fill:SetPoint("TOPLEFT", INDICATOR_BORDER, -INDICATOR_BORDER)
    fill:SetPoint("BOTTOMRIGHT", -INDICATOR_BORDER, INDICATOR_BORDER)
    fill:Hide()
    selector._fill = fill

    -- Center text
    local text = selector:CreateFontString(nil, "OVERLAY")
    text:SetFont(theme:GetFont("BUTTON"), INDICATOR_FONT_SIZE, "")
    text:SetPoint("CENTER", 0, 0)
    text:SetText("OFF")
    text:SetTextColor(dimR, dimG, dimB, 1)
    selector._text = text

    -- Build options list: index 0 = OFF, then each sub-toggle with a variant
    local options = {}
    for _, sub in ipairs(subToggles) do
        if sub.variant then
            options[#options + 1] = sub
        end
    end
    selector._options = options
    selector._allowOff = allowOff
    selector._currentIndex = allowOff and 0 or 1  -- 0 = OFF

    function selector:UpdateState(activeSubId)
        local r, g, b = theme:GetAccentColor()
        local dR, dG, dB = theme:GetDimTextColor()

        -- With no OFF state, an unset or unrecognized id resolves to the first
        -- variant — the same default the rest of the addon assumes when nothing
        -- has been stored yet.
        if not self._allowOff then
            local known = false
            for _, opt in ipairs(self._options) do
                if opt.id == activeSubId then known = true break end
            end
            if not known then
                activeSubId = self._options[1] and self._options[1].id or nil
            end
        end

        if not activeSubId then
            -- OFF state
            self._currentIndex = 0
            self._fill:Hide()
            self._text:SetText("OFF")
            self._text:SetTextColor(dR, dG, dB, 1)
            for _, tex in pairs(self._border) do tex:SetColorTexture(r, g, b, 0.4) end
            return
        end

        for i, opt in ipairs(self._options) do
            if opt.id == activeSubId then
                self._currentIndex = i
                local vc = addon.VARIANT_COLORS and addon.VARIANT_COLORS[opt.variant]
                local vr, vg, vb = r, g, b
                if vc then vr, vg, vb = vc[1], vc[2], vc[3] end
                self._fill:SetColorTexture(vr, vg, vb, 1)
                self._fill:Show()
                self._text:SetText(opt.variant)
                self._text:SetTextColor(0, 0, 0, 1)
                for _, tex in pairs(self._border) do tex:SetColorTexture(vr, vg, vb, 1) end
                return
            end
        end

        -- Fallback: unknown sub ID, treat as OFF
        self._currentIndex = 0
        self._fill:Hide()
        self._text:SetText("OFF")
        self._text:SetTextColor(dR, dG, dB, 1)
        for _, tex in pairs(self._border) do tex:SetColorTexture(r, g, b, 0.4) end
    end

    function selector:CycleNext()
        local nextIdx = self._currentIndex + 1
        if nextIdx > #self._options then
            nextIdx = self._allowOff and 0 or 1
        end
        self._currentIndex = nextIdx
        if nextIdx == 0 then
            self:UpdateState(nil)
            return nil
        else
            local opt = self._options[nextIdx]
            self:UpdateState(opt.id)
            return opt.id
        end
    end

    function selector:GetActiveSubId()
        if self._currentIndex == 0 then return nil end
        local opt = self._options[self._currentIndex]
        return opt and opt.id or nil
    end

    -- Tooltip on hover showing current variant info (colored to match variant)
    selector:SetScript("OnEnter", function(self)
        local C = addon.UI and addon.UI.Controls
        if not (C and C.GetOrCreateTooltip) then return end

        if self._currentIndex == 0 then
            -- OFF is where every new profile starts, so saying nothing here hides
            -- the variants from the people most likely to need them named. Reset
            -- the shared tooltip's accent, which the variant branch below tints.
            local tip = C:GetOrCreateTooltip()
            local names = {}
            for _, o in ipairs(self._options) do names[#names + 1] = o.variant end
            tip:SetContent("Off", "Scoot leaves this alone. Click to cycle through the available variants ("
                .. table.concat(names, ", ") .. ") and hover one to see what it does.")
            local r, g, b = theme:GetAccentColor()
            if tip._titleText then tip._titleText:SetTextColor(r, g, b, 1) end
            if tip._border then
                for _, tex in pairs(tip._border) do tex:SetColorTexture(r, g, b, 1) end
            end
            tip:ShowAtAnchor(self, "BOTTOMLEFT", "TOPLEFT", 0, 4)
            return
        end

        local opt = self._options[self._currentIndex]
        if not opt or not opt.versionBadge then return end

        local tip = C:GetOrCreateTooltip()
        tip:SetContent(opt.versionBadge.title or "", opt.versionBadge.text or "")
        -- Color tooltip title and border to match variant
        local vc = opt.variant and addon.VARIANT_COLORS and addon.VARIANT_COLORS[opt.variant]
        if vc and tip._titleText then
            tip._titleText:SetTextColor(vc[1], vc[2], vc[3], 1)
        end
        if vc and tip._border then
            for _, tex in pairs(tip._border) do
                tex:SetColorTexture(vc[1], vc[2], vc[3], 1)
            end
        end
        tip:ShowAtAnchor(self, "BOTTOMLEFT", "TOPLEFT", 0, 4)
    end)
    selector:SetScript("OnLeave", function()
        local C = addon.UI and addon.UI.Controls
        if C and C.GetOrCreateTooltip then
            C:GetOrCreateTooltip():Hide()
        end
    end)

    return selector
end

--------------------------------------------------------------------------------
-- Module Row (label left, optional indicator right)
--------------------------------------------------------------------------------

local function CreateModuleRow(parent, options)
    local theme = options.theme
    local ar, ag, ab = theme:GetAccentColor()
    local indent = options.indent or 0

    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(ROW_HEIGHT)

    -- Bottom border line
    local borderLine = row:CreateTexture(nil, "BORDER", nil, -1)
    borderLine:SetPoint("BOTTOMLEFT", indent, 0)
    borderLine:SetPoint("BOTTOMRIGHT", 0, 0)
    borderLine:SetHeight(1)
    borderLine:SetColorTexture(ar, ag, ab, 0.2)

    -- Hover background (only for toggleable rows)
    local hoverBg
    if not options.isHeader then
        hoverBg = row:CreateTexture(nil, "BACKGROUND", nil, -8)
        hoverBg:SetPoint("TOPLEFT", indent, 0)
        hoverBg:SetPoint("BOTTOMRIGHT", 0, 0)
        hoverBg:SetColorTexture(ar, ag, ab, 0.08)
        hoverBg:Hide()
    end

    -- Label button (covers left portion of row)
    local labelBtn = CreateFrame("Button", nil, row)
    labelBtn:SetPoint("TOPLEFT", row, "TOPLEFT", indent, 0)
    labelBtn:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", indent, 0)
    if options.isHeader then
        labelBtn:SetPoint("RIGHT", row, "RIGHT", -ROW_PADDING, 0)
    else
        labelBtn:SetPoint("RIGHT", row, "RIGHT", -(INDICATOR_WIDTH + ROW_PADDING * 2), 0)
    end
    labelBtn:RegisterForClicks("AnyUp")

    -- Label text
    local fontSize = options.isHeader and LABEL_FONT_SIZE or SUB_LABEL_FONT_SIZE
    local labelFS = labelBtn:CreateFontString(nil, "OVERLAY")
    labelFS:SetFont(theme:GetFont("LABEL"), fontSize, "")
    labelFS:SetPoint("LEFT", ROW_PADDING, 0)
    labelFS:SetText(options.label or "")
    if options.isHeader then
        labelFS:SetTextColor(ar, ag, ab, 1)
    else
        labelFS:SetTextColor(ar, ag, ab, 0.75)
    end

    -- Tiny per-variant letter badges (multi-variant rows: X/Y or X/Z). Each
    -- badge hover-shows that variant's versionBadge tooltip, so a user can read
    -- every variant without clicking the selector through its cycle.
    if options.variantOptions and addon.UI and addon.UI.Controls and addon.UI.Controls.CreateInfoIcon then
        local prevIcon
        for _, opt in ipairs(options.variantOptions) do
            local vb = opt.versionBadge
            local vc = opt.variant and addon.VARIANT_COLORS and addon.VARIANT_COLORS[opt.variant]
            if vb and vc then
                local badge = addon.UI.Controls:CreateInfoIcon({
                    parent = row,
                    size = VARIANT_ICON_SIZE,
                    customText = vb.label or opt.variant,
                    colorOverride = vc,
                    tooltipTitle = vb.title or "",
                    tooltipText = vb.text or "",
                    tooltipTint = vc,
                })
                if badge then
                    if badge._iconText then
                        local fontPath = badge._iconText:GetFont()
                        if fontPath then
                            pcall(badge._iconText.SetFont, badge._iconText, fontPath, VARIANT_ICON_FONT_SIZE, "OUTLINE")
                        end
                    end
                    if prevIcon then
                        badge:SetPoint("LEFT", prevIcon, "RIGHT", 3, 0)
                    else
                        badge:SetPoint("LEFT", labelFS, "RIGHT", 4, 0)
                    end
                    prevIcon = badge
                end
            end
        end
    end

    -- ON/OFF indicator (right side) — hidden for header and variantSelector rows
    local indicator
    if not options.isHeader and not options.variantSelector then
        indicator = CreateIndicator(row, theme)
        indicator:SetPoint("RIGHT", row, "RIGHT", -ROW_PADDING, 0)
        indicator:UpdateState(options.isOn, options.variant)

        indicator:SetScript("OnClick", function()
            if options.onToggle then options.onToggle() end
        end)
    end

    -- Click: label toggles (for non-header, non-variantSelector rows)
    labelBtn:SetScript("OnClick", function()
        if not options.isHeader and not options.variantSelector and options.onToggle then
            options.onToggle()
        end
    end)

    -- Hover handlers
    if hoverBg then
        labelBtn:SetScript("OnEnter", function() hoverBg:Show() end)
        labelBtn:SetScript("OnLeave", function() hoverBg:Hide() end)
        if indicator then
            indicator:SetScript("OnEnter", function() hoverBg:Show() end)
            indicator:SetScript("OnLeave", function() hoverBg:Hide() end)
        end
    end

    return row
end

--------------------------------------------------------------------------------
-- Grouped Toggle Helpers
--------------------------------------------------------------------------------

--- Read the enabled state for a sub-toggle (handles grouped members).
local function IsSubToggleOn(catId, sub)
    if sub.members then
        return addon:IsModuleEnabled(catId, sub.members[1])
    end
    return addon:IsModuleEnabled(catId, sub.id)
end

--- Toggle a sub-toggle (handles grouped members).
local function SetSubToggle(catId, sub, value)
    if sub.members then
        for _, memberId in ipairs(sub.members) do
            addon:SetModuleEnabled(catId, memberId, value)
        end
    else
        addon:SetModuleEnabled(catId, sub.id, value)
    end
end

--- The variant currently selected for a category, or nil if none is stored.
local function ActiveVariant(varCatId, variants)
    for _, v in ipairs(variants) do
        if IsSubToggleOn(varCatId, v) then return v end
    end
    return nil
end

--- Apply a variant selection: exactly one variant ends up true, or none when the
--- selector cycled to OFF.
local function ApplyVariantSelection(varCatId, variants, chosenId)
    for _, v in ipairs(variants) do
        SetSubToggle(varCatId, v, false)
    end
    if not chosenId then return end
    for _, v in ipairs(variants) do
        if v.id == chosenId then
            SetSubToggle(varCatId, v, true)
            return
        end
    end
end

--------------------------------------------------------------------------------
-- Per-sub mode cycles (OFF / X / Z on one unit)
--------------------------------------------------------------------------------
-- The modeCycle contract (modules.lua, unitFrames Player/Target): each option
-- names the category+subId that holds its state, so one row can span two
-- categories -- X lives in unitFrames.<unit>, Z in unitFramesZ.<unit>. Clearing
-- every option's key before setting the chosen one is what keeps the modes
-- exclusive; there is no mutuallyExclusive category behind this.

--- The mode currently active for a modeCycle sub-toggle, or nil (= OFF).
local function ActiveModeOption(sub)
    for _, opt in ipairs(sub.modeCycle) do
        if addon:IsModuleEnabled(opt.category, opt.subId) then return opt end
    end
    return nil
end

--- Apply a mode selection: exactly one option's key ends up true, or none when
--- the selector cycled to OFF.
local function ApplyModeSelection(sub, chosenOptId)
    for _, opt in ipairs(sub.modeCycle) do
        addon:SetModuleEnabled(opt.category, opt.subId, opt.id == chosenOptId)
    end
end

--------------------------------------------------------------------------------
-- Column Builder
--------------------------------------------------------------------------------

local function BuildColumnContent(column, categories, startIdx, endIdx, state, theme, rebuild)
    local yOffset = 0
    for i = startIdx, endIdx do
        local catId = categories[i]
        local catDef = addon.MODULE_CATEGORIES[catId]
        if not catDef then break end

        local hasSubToggles = catDef.subToggles and #catDef.subToggles > 0

        if catDef.mutuallyExclusive and hasSubToggles then
            -- Mutually exclusive: single row with compact variant selector
            local variantRow = CreateModuleRow(column, {
                label = catDef.label,
                theme = theme,
                variantSelector = true,
                variantOptions = catDef.subToggles,
            })
            variantRow:SetPoint("TOPLEFT", column, "TOPLEFT", 0, -yOffset)
            variantRow:SetPoint("TOPRIGHT", column, "TOPRIGHT", 0, -yOffset)

            local selector = CreateVariantSelector(variantRow, theme, catDef.subToggles)
            selector:SetPoint("RIGHT", variantRow, "RIGHT", -ROW_PADDING, 0)

            local activeSub = ActiveVariant(catId, catDef.subToggles)
            selector:UpdateState(activeSub and activeSub.id or nil)

            selector:SetScript("OnClick", function()
                ApplyVariantSelection(catId, catDef.subToggles, selector:CycleNext())
                state.dirty = true
                if state.registerGuard then state.registerGuard() end
                rebuild()
            end)

            table.insert(state.rows, variantRow)
            yOffset = yOffset + ROW_HEIGHT
        elseif hasSubToggles then
            -- Header row (no toggle indicator)
            local headerRow = CreateModuleRow(column, {
                label = catDef.label,
                isHeader = true,
                theme = theme,
            })
            headerRow:SetPoint("TOPLEFT", column, "TOPLEFT", 0, -yOffset)
            headerRow:SetPoint("TOPRIGHT", column, "TOPRIGHT", 0, -yOffset)
            table.insert(state.rows, headerRow)
            yOffset = yOffset + ROW_HEIGHT

            -- Sub-toggle rows (always visible)
            for _, sub in ipairs(catDef.subToggles) do
                if sub.modeCycle then
                    -- A per-unit OFF/X/Z cycle: the options span categories (see
                    -- ActiveModeOption above), so this reuses the variant
                    -- selector widget with its default allowOff = true -- OFF
                    -- is a real state here, unlike the variantCategory rows.
                    local modeRow = CreateModuleRow(column, {
                        label = sub.label,
                        indent = SUB_INDENT,
                        variantSelector = true,
                        variantOptions = sub.modeCycle,
                        theme = theme,
                    })
                    modeRow:SetPoint("TOPLEFT", column, "TOPLEFT", 0, -yOffset)
                    modeRow:SetPoint("TOPRIGHT", column, "TOPRIGHT", 0, -yOffset)

                    local modeSelector = CreateVariantSelector(modeRow, theme, sub.modeCycle)
                    modeSelector:SetPoint("RIGHT", modeRow, "RIGHT", -ROW_PADDING, 0)

                    local activeOpt = ActiveModeOption(sub)
                    modeSelector:UpdateState(activeOpt and activeOpt.id or nil)

                    modeSelector:SetScript("OnClick", function()
                        ApplyModeSelection(sub, modeSelector:CycleNext())
                        state.dirty = true
                        if state.registerGuard then state.registerGuard() end
                        rebuild()
                    end)

                    table.insert(state.rows, modeRow)
                    yOffset = yOffset + ROW_HEIGHT
                elseif sub.variantCategory then
                    -- A variant selector nested in someone else's list. It reads
                    -- and writes the category it points at, never this one, and
                    -- has no OFF: one of its variants is always in effect.
                    local varCatId = sub.variantCategory
                    local varCatDef = addon.MODULE_CATEGORIES[varCatId]
                    local variants = (varCatDef and varCatDef.subToggles) or {}

                    local varRow = CreateModuleRow(column, {
                        label = sub.label,
                        indent = SUB_INDENT,
                        variantSelector = true,
                        variantOptions = variants,
                        theme = theme,
                    })
                    varRow:SetPoint("TOPLEFT", column, "TOPLEFT", 0, -yOffset)
                    varRow:SetPoint("TOPRIGHT", column, "TOPRIGHT", 0, -yOffset)

                    local varSelector = CreateVariantSelector(varRow, theme, variants, false)
                    varSelector:SetPoint("RIGHT", varRow, "RIGHT", -ROW_PADDING, 0)

                    local activeVar = ActiveVariant(varCatId, variants)
                    varSelector:UpdateState(activeVar and activeVar.id or nil)

                    varSelector:SetScript("OnClick", function()
                        ApplyVariantSelection(varCatId, variants, varSelector:CycleNext())
                        state.dirty = true
                        if state.registerGuard then state.registerGuard() end
                        rebuild()
                    end)

                    table.insert(state.rows, varRow)
                    yOffset = yOffset + ROW_HEIGHT
                else
                    local subIsOn = IsSubToggleOn(catId, sub)
                    local subRow = CreateModuleRow(column, {
                        label = sub.label,
                        isOn = subIsOn,
                        indent = SUB_INDENT,
                        variant = sub.variant,
                        theme = theme,
                        onToggle = function()
                            local newValue = not IsSubToggleOn(catId, sub)
                            SetSubToggle(catId, sub, newValue)
                            state.dirty = true
                            if state.registerGuard then state.registerGuard() end
                            rebuild()
                        end,
                    })
                    subRow:SetPoint("TOPLEFT", column, "TOPLEFT", 0, -yOffset)
                    subRow:SetPoint("TOPRIGHT", column, "TOPRIGHT", 0, -yOffset)
                    table.insert(state.rows, subRow)
                    yOffset = yOffset + ROW_HEIGHT
                end
            end
        else
            -- Simple category: single row with toggle
            local isOn = addon:IsModuleEnabled(catId)
            local simpleRow = CreateModuleRow(column, {
                label = catDef.label,
                isOn = isOn,
                variant = catDef.variant,
                theme = theme,
                onToggle = function()
                    addon:SetModuleEnabled(catId, nil, not addon:IsModuleEnabled(catId))
                    state.dirty = true
                    if state.registerGuard then state.registerGuard() end
                    rebuild()
                end,
            })
            simpleRow:SetPoint("TOPLEFT", column, "TOPLEFT", 0, -yOffset)
            simpleRow:SetPoint("TOPRIGHT", column, "TOPRIGHT", 0, -yOffset)
            table.insert(state.rows, simpleRow)
            yOffset = yOffset + ROW_HEIGHT
        end
    end
    column:SetHeight(math.max(yOffset, 1))
end

--------------------------------------------------------------------------------
-- Reload Area (static, below scroll frame)
--------------------------------------------------------------------------------

local function EnsureReloadArea(panel, contentPane)
    if panel._startHereReloadArea then
        panel._startHereReloadArea:Show()
        return panel._startHereReloadArea
    end

    local theme = addon.UI.Theme
    local Controls = addon.UI.Controls
    local ar, ag, ab = theme:GetAccentColor()
    local dimR, dimG, dimB = theme:GetDimTextColor()

    local area = CreateFrame("Frame", nil, contentPane)
    area:SetHeight(RELOAD_AREA_HEIGHT)
    area:SetPoint("BOTTOMLEFT", contentPane, "BOTTOMLEFT", 8, 8)
    area:SetPoint("BOTTOMRIGHT", contentPane, "BOTTOMRIGHT", -8, 8)

    -- Top separator
    local sep = area:CreateTexture(nil, "BORDER", nil, -1)
    sep:SetPoint("TOPLEFT", 0, 0)
    sep:SetPoint("TOPRIGHT", 0, 0)
    sep:SetHeight(1)
    sep:SetColorTexture(ar, ag, ab, 0.3)

    -- RELOAD button (centered) with its caption to the right
    local btn = Controls:CreateButton({
        parent = area,
        text = "RELOAD",
        width = 140,
        height = 30,
        fontSize = 13,
    })
    btn:SetPoint("TOP", area, "TOP", 0, -8)
    btn:SetScript("OnClick", function()
        if ReloadUI then ReloadUI() end
    end)
    area._reloadBtn = btn

    -- Explainer text
    local explainer = area:CreateFontString(nil, "OVERLAY")
    explainer:SetFont(theme:GetFont("VALUE"), 10, "")
    explainer:SetPoint("LEFT", btn, "RIGHT", 10, 0)
    explainer:SetText("to apply changes")
    explainer:SetTextColor(dimR, dimG, dimB, 0.8)
    explainer:SetJustifyH("LEFT")

    panel._startHereReloadArea = area
    return area
end

local function UpdateReloadButtonVisual(area, isDirty)
    local btn = area and area._reloadBtn
    if not btn then return end
    local theme = addon.UI.Theme
    local ar, ag, ab = theme:GetAccentColor()

    if isDirty then
        -- Inverted: accent fill shown permanently, dark text
        btn._hoverFill:Show()
        btn._label:SetTextColor(0, 0, 0, 1)
        btn:SetScript("OnEnter", function() end)
        btn:SetScript("OnLeave", function() end)
    else
        -- Normal: dark background, accent text, standard hover
        btn._hoverFill:Hide()
        btn._label:SetTextColor(ar, ag, ab, 1)
        btn:SetScript("OnEnter", function(self)
            local r, g, b = theme:GetAccentColor()
            self._hoverFill:SetColorTexture(r, g, b, 1)
            self._hoverFill:Show()
            self._label:SetTextColor(0, 0, 0, 1)
        end)
        btn:SetScript("OnLeave", function(self)
            self._hoverFill:Hide()
            local r, g, b = theme:GetAccentColor()
            self._label:SetTextColor(r, g, b, 1)
        end)
    end
end

--------------------------------------------------------------------------------
-- Horizontal Scrollbar (shown when the window is too narrow for 3 columns)
--------------------------------------------------------------------------------

local function EnsureHScrollbar(panel, contentPane)
    if panel._startHereHScroll then
        panel._startHereHScroll.Update()
        return panel._startHereHScroll
    end

    local theme = addon.UI.Theme
    local ar, ag, ab = theme:GetAccentColor()
    local scrollFrame = contentPane._scrollFrame

    local bar = CreateFrame("Frame", nil, contentPane)
    bar:SetHeight(HSCROLL_HEIGHT)
    bar:SetPoint("BOTTOMLEFT", contentPane, "BOTTOMLEFT", 8, 8 + RELOAD_AREA_HEIGHT + 2)
    bar:SetPoint("BOTTOMRIGHT", contentPane, "BOTTOMRIGHT", -24, 8 + RELOAD_AREA_HEIGHT + 2)
    bar:EnableMouse(true)

    local track = bar:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints()
    track:SetColorTexture(ar, ag, ab, 0.12)
    bar._track = track

    local thumb = CreateFrame("Button", nil, bar)
    thumb:SetHeight(HSCROLL_HEIGHT)
    thumb:SetPoint("LEFT", bar, "LEFT", 0, 0)
    thumb:EnableMouse(true)
    thumb:RegisterForDrag("LeftButton")

    local thumbTex = thumb:CreateTexture(nil, "ARTWORK")
    thumbTex:SetAllPoints()
    thumbTex:SetColorTexture(ar, ag, ab, 0.5)
    thumb._tex = thumbTex

    thumb:SetScript("OnEnter", function(self)
        local r, g, b = theme:GetAccentColor()
        self._tex:SetColorTexture(r, g, b, 0.8)
    end)
    thumb:SetScript("OnLeave", function(self)
        if not self._isDragging then
            local r, g, b = theme:GetAccentColor()
            self._tex:SetColorTexture(r, g, b, 0.5)
        end
    end)

    local function Metrics()
        local visW = scrollFrame:GetWidth() or 1
        local scrollChild = scrollFrame:GetScrollChild()
        local contentW = (scrollChild and scrollChild:GetWidth()) or 1
        return visW, contentW, math.max(0, contentW - visW)
    end

    function bar.Update()
        local visW, contentW, maxScroll = Metrics()
        if maxScroll <= 1 then
            bar:Hide()
            scrollFrame:SetHorizontalScroll(0)
            scrollFrame:SetPoint("BOTTOMRIGHT", contentPane, "BOTTOMRIGHT", -24, 8 + RELOAD_AREA_HEIGHT)
        else
            bar:Show()
            -- Reserve a slice of the viewport for the bar while it's visible
            scrollFrame:SetPoint("BOTTOMRIGHT", contentPane, "BOTTOMRIGHT", -24, 8 + RELOAD_AREA_HEIGHT + HSCROLL_HEIGHT + 6)
            local trackW = bar:GetWidth() or 1
            local thumbW = math.max(HSCROLL_THUMB_MIN, (visW / contentW) * trackW)
            thumb:SetWidth(thumbW)
            local cur = scrollFrame:GetHorizontalScroll() or 0
            if cur > maxScroll then
                cur = maxScroll
                scrollFrame:SetHorizontalScroll(cur)
            end
            local pct = maxScroll > 0 and (cur / maxScroll) or 0
            thumb:ClearAllPoints()
            thumb:SetPoint("LEFT", bar, "LEFT", pct * (trackW - thumbW), 0)
        end
        -- Viewport height changes with the bar's visibility
        if contentPane._scrollbar and contentPane._scrollbar.Update then
            contentPane._scrollbar:Update()
        end
    end

    local dragStartX, dragStartScroll

    thumb:SetScript("OnDragStart", function(self)
        self._isDragging = true
        local r, g, b = theme:GetAccentColor()
        self._tex:SetColorTexture(r, g, b, 1)
        local cursorX = GetCursorPosition()
        dragStartX = cursorX / self:GetEffectiveScale()
        dragStartScroll = scrollFrame:GetHorizontalScroll() or 0
    end)

    thumb:SetScript("OnDragStop", function(self)
        self._isDragging = false
        local r, g, b = theme:GetAccentColor()
        self._tex:SetColorTexture(r, g, b, self:IsMouseOver() and 0.8 or 0.5)
    end)

    thumb:SetScript("OnUpdate", function(self)
        if not self._isDragging then return end
        local cursorX = GetCursorPosition()
        cursorX = cursorX / self:GetEffectiveScale()
        local _, _, maxScroll = Metrics()
        local maxThumbOffset = (bar:GetWidth() or 1) - self:GetWidth()
        if maxThumbOffset > 0 and maxScroll > 0 then
            local scrollDelta = ((cursorX - dragStartX) / maxThumbOffset) * maxScroll
            scrollFrame:SetHorizontalScroll(math.max(0, math.min(maxScroll, dragStartScroll + scrollDelta)))
            bar.Update()
        end
    end)

    -- Track click: jump the thumb center to the cursor
    bar:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" or thumb:IsMouseOver() then return end
        local cursorX = GetCursorPosition()
        cursorX = cursorX / self:GetEffectiveScale()
        local left = self:GetLeft() or 0
        local _, _, maxScroll = Metrics()
        local thumbW = thumb:GetWidth() or HSCROLL_THUMB_MIN
        local maxThumbOffset = (self:GetWidth() or 1) - thumbW
        if maxThumbOffset > 0 and maxScroll > 0 then
            local pct = math.max(0, math.min(1, (cursorX - left - thumbW / 2) / maxThumbOffset))
            scrollFrame:SetHorizontalScroll(pct * maxScroll)
            bar.Update()
        end
    end)

    panel._startHereHScroll = bar
    bar.Update()
    return bar
end

--------------------------------------------------------------------------------
-- Cleanup (called from ClearContent when navigating away)
--------------------------------------------------------------------------------

local function Cleanup(panel)
    -- Hide reload area and horizontal scrollbar
    if panel._startHereReloadArea then
        panel._startHereReloadArea:Hide()
    end
    if panel._startHereHScroll then
        panel._startHereHScroll:Hide()
    end

    -- Restore scroll frame, scrollbar anchors, header separator, and scroll top anchor
    local contentPane = panel.frame and panel.frame._contentPane
    if contentPane then
        local scrollFrame = contentPane._scrollFrame
        if scrollFrame then
            scrollFrame:SetPoint("BOTTOMRIGHT", contentPane, "BOTTOMRIGHT", -24, 8)
        end
        local scrollbar = contentPane._scrollbar
        if scrollbar then
            scrollbar:SetPoint("BOTTOMRIGHT", contentPane, "BOTTOMRIGHT", -8, 24)
        end
        if contentPane._headerSep then
            contentPane._headerSep:Show()
        end
        -- Restore scroll frame top anchor (overridden in Render to sit at the
        -- pane top; the blanked header title is re-set by navigation on the
        -- next page select)
        if scrollFrame and contentPane._header then
            scrollFrame:SetPoint("TOPLEFT", contentPane._header, "BOTTOMLEFT", 8, -8)
        end
        -- Restore the content pane's top (raised in Render into the title bar)
        if pageState.paneAnchor then
            local a = pageState.paneAnchor
            contentPane:SetPoint("TOPLEFT", a.relTo, a.relPoint, a.x, a.y)
            pageState.paneAnchor = nil
        end
        -- Horizontal-scroll teardown: unlock the content width and reset pan
        contentPane._minContentWidth = nil
        if scrollFrame then
            scrollFrame:SetHorizontalScroll(0)
            local sc = contentPane._scrollContent
            if sc then
                local w = scrollFrame:GetWidth()
                if w and w > 0 then sc:SetWidth(w - 16) end
            end
        end
    end

    -- Destroy rows
    for _, row in ipairs(pageState.rows) do
        row:Hide()
        row:SetParent(nil)
    end
    if wipe then wipe(pageState.rows) else pageState.rows = {} end

    -- Destroy columns
    for _, col in ipairs(pageState.columns) do
        col:Hide()
        col:SetParent(nil)
    end
    if wipe then wipe(pageState.columns) else pageState.columns = {} end

    pageState.dirty = false
    pageState.snapshot = nil
    pageState.registerGuard = nil
    pageState.rebuild = nil
    pageState.resizeToken = (pageState.resizeToken or 0) + 1  -- cancel pending reflow
    panel._navigationGuard = nil
    panel._startHereCleanup = nil
end

--------------------------------------------------------------------------------
-- Render
--------------------------------------------------------------------------------

function StartHere.Render(panel, scrollContent)
    local contentPane = panel.frame._contentPane
    local scrollFrame = contentPane._scrollFrame
    local theme = addon.UI.Theme

    -- Reset state for this visit
    pageState.dirty = false

    -- Snapshot moduleEnabled so "Discard Changes" can restore it
    pageState.snapshot = nil
    local me = addon.db and addon.db.profile and addon.db.profile.moduleEnabled
    if me then
        pageState.snapshot = deepCopy(me)
    end

    -- Register navigate-away dialog (idempotent)
    addon.Dialogs:Register("SCOOT_START_HERE_RELOAD", {
        text = "A Reload is required to apply your changes.",
        acceptText = "Reload",
        cancelText = "Discard Changes",
    })

    -- Raise the content pane into the title-bar dead space so the module grid fits
    -- without scrolling (Cleanup restores the original offset)
    if not pageState.paneAnchor then
        local point, relTo, relPoint, x, y = contentPane:GetPoint(1)
        if point == "TOPLEFT" then
            pageState.paneAnchor = { relTo = relTo, relPoint = relPoint, x = x, y = y }
            contentPane:SetPoint("TOPLEFT", relTo, relPoint, x, PANE_TOP_OFFSET)
        end
    end

    -- The page title renders inside the scroll content (left header column), so
    -- blank the pane's own title; navigation re-sets it on the next page select
    if contentPane._headerTitle then
        contentPane._headerTitle:SetText("")
    end

    -- Hide the default header separator — a custom one renders below the header columns
    if contentPane._headerSep then
        contentPane._headerSep:Hide()
    end

    -- Pull the scroll frame to the pane top: the two-column header (title +
    -- explainer left, X/Y/Z legend right) owns the full vertical space
    scrollFrame:SetPoint("TOPLEFT", contentPane, "TOPLEFT", 8, -8)

    -- Create/show reload area
    local reloadArea = EnsureReloadArea(panel, contentPane)
    UpdateReloadButtonVisual(reloadArea, false)

    -- Shrink scroll frame to leave room for reload area
    scrollFrame:SetPoint("BOTTOMRIGHT", contentPane, "BOTTOMRIGHT", -24, 8 + RELOAD_AREA_HEIGHT)
    if contentPane._scrollbar then
        contentPane._scrollbar:SetPoint("BOTTOMRIGHT", contentPane, "BOTTOMRIGHT", -8, 24 + RELOAD_AREA_HEIGHT)
    end

    -- Lock the scroll content to a 3-column minimum width; when the window is
    -- narrower the page pans horizontally via the h-scrollbar instead of
    -- crushing the columns
    contentPane._minContentWidth = FEATURES_MIN_CONTENT_WIDTH
    local sfWidth = scrollFrame:GetWidth() or 0
    if sfWidth > 0 then
        scrollContent:SetWidth(math.max(sfWidth - 16, FEATURES_MIN_CONTENT_WIDTH))
    end
    EnsureHScrollbar(panel, contentPane)

    -- Register cleanup for when user navigates away
    panel._startHereCleanup = function() Cleanup(panel) end

    -- Reflow on window resize (debounced): recompute the locked width from the
    -- new viewport, rebuild the columns for it, and refresh the h-scrollbar
    if not panel._startHereResizeHooked then
        panel._startHereResizeHooked = true
        panel.frame:HookScript("OnSizeChanged", function()
            if not panel._startHereCleanup then return end
            pageState.resizeToken = (pageState.resizeToken or 0) + 1
            local token = pageState.resizeToken
            C_Timer.After(0.15, function()
                if token ~= pageState.resizeToken then return end
                if not panel._startHereCleanup then return end
                local cp = panel.frame and panel.frame._contentPane
                local sf = cp and cp._scrollFrame
                local sc = cp and cp._scrollContent
                if sf and sc then
                    local w = sf:GetWidth() or 0
                    if w > 0 then
                        sc:SetWidth(math.max(w - 16, FEATURES_MIN_CONTENT_WIDTH))
                    end
                end
                if pageState.rebuild then pageState.rebuild() end
                if panel._startHereHScroll then panel._startHereHScroll.Update() end
            end)
        end)
    end

    -- Navigation guard: called by toggle handlers when dirty to register a
    -- confirmation dialog before allowing navigation away from Features page.
    pageState.registerGuard = function()
        if panel._navigationGuard then return end
        panel._navigationGuard = function(_, proceed)
            addon.Dialogs:Show("SCOOT_START_HERE_RELOAD", {
                cancelWidth = 140,
                onAccept = function()
                    ReloadUI()
                end,
                onCancel = function()
                    -- Restore original moduleEnabled state
                    local profile = addon.db and addon.db.profile
                    if profile and pageState.snapshot then
                        profile.moduleEnabled = deepCopy(pageState.snapshot)
                    end
                    panel._navigationGuard = nil
                    proceed()
                end,
            })
        end
    end

    -- Panel close guard: intercept close/ESC/combat when dirty.
    -- HookScript persists across visits; pageState.dirty gates behavior.
    if not panel._startHereOnHideHooked then
        panel._startHereOnHideHooked = true
        panel.frame:HookScript("OnHide", function(self)
            if not pageState.dirty then return end
            if pageState._hideGuardActive then return end

            local UIPanel = addon.UI.SettingsPanel
            if UIPanel._closedByCombat or (InCombatLockdown and InCombatLockdown()) then
                -- Combat: silently discard changes and clean up
                local profile = addon.db and addon.db.profile
                if profile and pageState.snapshot then
                    profile.moduleEnabled = deepCopy(pageState.snapshot)
                end
                if panel._startHereCleanup then panel._startHereCleanup() end
                return
            end

            -- User close (close button / ESC): re-show and prompt
            pageState._hideGuardActive = true
            self:Show()
            pageState._hideGuardActive = false

            addon.Dialogs:Show("SCOOT_START_HERE_RELOAD", {
                cancelWidth = 140,
                onAccept = function()
                    ReloadUI()
                end,
                onCancel = function()
                    local profile = addon.db and addon.db.profile
                    if profile and pageState.snapshot then
                        profile.moduleEnabled = deepCopy(pageState.snapshot)
                    end
                    if panel._startHereCleanup then panel._startHereCleanup() end
                    pageState._hideGuardActive = true
                    self:Hide()
                    pageState._hideGuardActive = false
                end,
            })
        end)
    end

    -- Rebuild function (called on toggle changes)
    local function rebuild()
        -- Destroy existing rows and columns
        for _, row in ipairs(pageState.rows) do
            row:Hide()
            row:SetParent(nil)
        end
        if wipe then wipe(pageState.rows) else pageState.rows = {} end
        for _, col in ipairs(pageState.columns) do
            col:Hide()
            col:SetParent(nil)
        end
        if wipe then wipe(pageState.columns) else pageState.columns = {} end

        -- Lock the pan range to the width this layout is built for, so live
        -- window shrinks keep the full horizontal reach until the debounced
        -- reflow rebuilds at the new width
        contentPane._minContentWidth = math.max(scrollContent:GetWidth() or 0, FEATURES_MIN_CONTENT_WIDTH)

        -- Two-column header inside the scroll content: page title + explainer on
        -- the left (~1/4 of the width), X/Y/Z legend rows on the right (~3/4)
        local availWidth = (scrollContent:GetWidth() or 300) - ROW_PADDING * 2
        local leftColWidth = math.floor(availWidth * 0.25)
        local legendWidth = availWidth - leftColWidth - HEADER_COL_GAP
        local ar, ag, ab = theme:GetAccentColor()

        local titleFS = scrollContent:CreateFontString(nil, "OVERLAY")
        theme:ApplyHeaderFont(titleFS, 20)
        titleFS:SetTextColor(ar, ag, ab, 1)
        titleFS:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", ROW_PADDING, -HEADER_TOP_PAD)
        titleFS:SetText("Modules")
        table.insert(pageState.rows, titleFS)

        local introFS = scrollContent:CreateFontString(nil, "OVERLAY")
        introFS:SetFont(theme:GetFont("VALUE"), 11, "")
        introFS:SetPoint("TOPLEFT", titleFS, "BOTTOMLEFT", 0, -6)
        introFS:SetWidth(leftColWidth)
        introFS:SetWordWrap(true)
        introFS:SetJustifyH("LEFT")
        introFS:SetText("Enable or disable Scoot modules. Disabled modules do not load, freeing them for other addons.")
        introFS:SetTextColor(theme:GetDimTextColor())
        table.insert(pageState.rows, introFS)

        -- X/Y/Z legend: one row per feature-set letter in the right column.
        -- Chain-anchored (each icon hangs below the previous row's summary text)
        -- so wrapped text self-spaces without any string-height measurement.
        local legendLabels = {}
        local prevFS
        local legendX = ROW_PADDING + leftColWidth + HEADER_COL_GAP
        for _, entry in ipairs(addon.FEATURE_GUIDE or {}) do
            local icon = addon.UI.Controls:CreateInfoIcon({
                parent = scrollContent,
                size = LEGEND_ICON_SIZE,
                customText = entry.letter,
                colorOverride = entry.color,
                tooltipTitle = entry.tooltipTitle,
                tooltipText = entry.tooltipText,
                tooltipTint = entry.color,
            })
            if icon then
                if prevFS then
                    icon:SetPoint("TOPLEFT", prevFS, "BOTTOMLEFT", -(LEGEND_ICON_SIZE + LEGEND_TEXT_GAP), -LEGEND_ROW_GAP)
                else
                    icon:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", legendX, -(HEADER_TOP_PAD + 2))
                end
                local fs = scrollContent:CreateFontString(nil, "OVERLAY")
                fs:SetFont(theme:GetFont("LABEL"), LEGEND_FONT_SIZE, "")
                fs:SetTextColor(entry.color[1], entry.color[2], entry.color[3], 0.8)
                fs:SetText(entry.summary)
                fs:SetJustifyH("LEFT")
                fs:SetWordWrap(true)
                fs:SetWidth(legendWidth - LEGEND_ICON_SIZE - LEGEND_TEXT_GAP - LEGEND_RIGHT_INSET)
                fs:SetPoint("TOPLEFT", icon, "TOPRIGHT", LEGEND_TEXT_GAP, -1)
                table.insert(pageState.rows, icon)
                table.insert(pageState.rows, fs)
                legendLabels[#legendLabels + 1] = fs
                prevFS = fs
            end
        end

        -- Separator below the header columns. The legend column is the taller
        -- side in practice (3 wrapped rows vs a title + short explainer), so
        -- chain to its last label; falls back to below the intro if the legend
        -- produced nothing. Offsets stretch the line to the full content width.
        local sep = scrollContent:CreateTexture(nil, "BORDER", nil, -1)
        sep:SetHeight(1)
        local sepAnchor = legendLabels[#legendLabels]
        if sepAnchor then
            sep:SetPoint("TOPLEFT", sepAnchor, "BOTTOMLEFT", -(leftColWidth + HEADER_COL_GAP + LEGEND_ICON_SIZE + LEGEND_TEXT_GAP) - 4, -8)
            sep:SetPoint("TOPRIGHT", sepAnchor, "BOTTOMRIGHT", LEGEND_RIGHT_INSET + 4, -8)
        else
            sep:SetPoint("TOPLEFT", introFS, "BOTTOMLEFT", -4, -6)
            sep:SetPoint("TOPRIGHT", introFS, "BOTTOMRIGHT", 4, -6)
        end
        sep:SetColorTexture(ar, ag, ab, 0.3)
        table.insert(pageState.rows, sep)

        -- Compute optimal column splits. Categories that render as a variant row
        -- inside another category are skipped here but keep their place in
        -- MODULE_CATEGORY_ORDER, which init.lua walks for the session snapshot.
        local categories = {}
        for _, catId in ipairs(addon.MODULE_CATEGORY_ORDER) do
            local catDef = addon.MODULE_CATEGORIES[catId]
            if not (catDef and catDef.hiddenFromFeatures) then
                categories[#categories + 1] = catId
            end
        end
        local splits = ComputeColumnSplits(categories, NUM_COLUMNS)

        -- Compute column width
        local scrollWidth = scrollContent:GetWidth() or 850
        local colWidth = (scrollWidth - (NUM_COLUMNS - 1) * COLUMN_GAP) / NUM_COLUMNS

        -- Create columns
        local prevCol
        for c = 1, NUM_COLUMNS do
            local col = CreateFrame("Frame", nil, scrollContent)
            col:SetWidth(colWidth)
            if c == 1 then
                col:SetPoint("TOPLEFT", sep, "BOTTOMLEFT", -8, -4)
            else
                col:SetPoint("TOPLEFT", prevCol, "TOPRIGHT", COLUMN_GAP, 0)
            end
            table.insert(pageState.columns, col)
            prevCol = col

            local startIdx = c == 1 and 1 or (splits[c - 1] + 1)
            local endIdx = splits[c]
            BuildColumnContent(col, categories, startIdx, endIdx, pageState, theme, rebuild)
        end

        -- Set scroll content height. Sync estimate first (string heights may
        -- under-report before first render), then a deferred pass corrects it
        -- from actual geometry.
        -- Header height = the taller of the two columns (legend wins in practice)
        local legendUsed = HEADER_TOP_PAD + 2
        for _, fs in ipairs(legendLabels) do
            legendUsed = legendUsed + math.max(LEGEND_ICON_SIZE, fs:GetStringHeight() or 12) + LEGEND_ROW_GAP
        end
        local leftUsed = HEADER_TOP_PAD + (titleFS:GetStringHeight() or 20) + 6 + (introFS:GetStringHeight() or 14)
        local headerUsed = math.max(legendUsed, leftUsed) + 2 + 1 + 4  -- remaining sep gap, sep line, gap to columns
        local maxColHeight = 0
        for _, col in ipairs(pageState.columns) do
            local h = col:GetHeight()
            if h > maxColHeight then maxColHeight = h end
        end
        scrollContent:SetHeight(headerUsed + maxColHeight + 8)

        local col1 = pageState.columns[1]
        C_Timer.After(0, function()
            -- Superseded rebuild or navigation away unparents the column; no-op then
            if not col1 or col1:GetParent() ~= scrollContent then return end
            local sTop, cTop = scrollContent:GetTop(), col1:GetTop()
            if not (sTop and cTop) then return end
            scrollContent:SetHeight((sTop - cTop) + maxColHeight + 8)
            if contentPane._scrollbar and contentPane._scrollbar.Update then
                contentPane._scrollbar:Update()
            end
        end)

        -- Update reload button visual
        UpdateReloadButtonVisual(reloadArea, pageState.dirty)

        -- Update scrollbars (the h-bar also re-slots the viewport bottom)
        if contentPane._scrollbar and contentPane._scrollbar.Update then
            contentPane._scrollbar:Update()
        end
        if panel._startHereHScroll then
            panel._startHereHScroll.Update()
        end
    end

    pageState.rebuild = rebuild
    rebuild()
end

--------------------------------------------------------------------------------
-- Register
--------------------------------------------------------------------------------

addon.UI.SettingsPanel:RegisterRenderer("startHere", function(panel, scrollContent)
    StartHere.Render(panel, scrollContent)
end)
