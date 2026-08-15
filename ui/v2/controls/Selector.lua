-- Selector.lua - Dropdown/selector with arrow buttons on each side
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.Controls = addon.UI.Controls or {}
local Controls = addon.UI.Controls
local Theme -- Will be set after Theme.lua loads

-- Lazy Theme accessor
local function GetTheme()
    if not Theme then
        Theme = addon.UI.Theme
    end
    return Theme
end

-- Constants

local SELECTOR_HEIGHT = 28
local SELECTOR_ARROW_WIDTH = 28
local SELECTOR_DEFAULT_WIDTH = 270
local SELECTOR_ROW_HEIGHT = 36
local SELECTOR_ROW_HEIGHT_WITH_DESC = 80
local SELECTOR_PADDING = 12
local SELECTOR_BORDER_ALPHA = 0.5

-- Emphasized (hero) styling constants
local EMPHASIZED_ROW_HEIGHT = 48
local EMPHASIZED_ROW_HEIGHT_WITH_DESC = 90
local EMPHASIZED_LABEL_SIZE = 14
local EMPHASIZED_BORDER_WIDTH = 3

-- Dynamic height constants
local MAX_ROW_HEIGHT = 200        -- Cap to prevent excessively tall rows
local LABEL_LINE_HEIGHT = 16      -- Approximate label height
local DESC_PADDING_TOP = 2        -- Space between label and description
local DESC_PADDING_TOP_EMPH = 4   -- Space for emphasized controls
local DESC_PADDING_BOTTOM = 36    -- Space below description to border (doubled for center-anchored layout)

-- Selector: Dropdown/selector with arrow buttons on each side

function Controls:CreateSelector(options)
    local theme = GetTheme()
    if not options or not options.parent then
        return nil
    end

    local parent = options.parent
    local label = options.label or "Selector"
    local description = options.description
    local values = options.values or {}
    local orderKeys = options.order
    local getValue = options.get or function() return nil end
    local setValue = options.set or function() end
    local selectorWidth = options.width or SELECTOR_DEFAULT_WIDTH
    local name = options.name
    local syncCooldown = options.syncCooldown  -- Optional cooldown for Edit Mode sync
    local emphasized = options.emphasized or false
    local isDisabledFn = options.disabled or options.isDisabled
    local optionInfoIcons = options.optionInfoIcons
    -- labelAlign = "field" right-aligns the label against the field's left
    -- edge (for description-less selectors; the description anchors to the
    -- label and would follow it rightward).
    local labelAlign = options.labelAlign
    local noBottomBorder = options.noBottomBorder
    -- sizeScale scales the whole control (fonts, field height, arrows, row
    -- height). Field width stays the caller's `width`. Not supported together
    -- with description or emphasized rows.
    local S = options.sizeScale or 1
    local function sc(v) return math.floor(v * S + 0.5) end

    local hasDesc = description and description ~= ""
    local rowHeight
    if emphasized then
        rowHeight = hasDesc and EMPHASIZED_ROW_HEIGHT_WITH_DESC or sc(EMPHASIZED_ROW_HEIGHT)
    else
        rowHeight = hasDesc and SELECTOR_ROW_HEIGHT_WITH_DESC or sc(SELECTOR_ROW_HEIGHT)
    end

    -- Use appropriate sizes for emphasized vs normal
    local labelFontSize = sc(emphasized and EMPHASIZED_LABEL_SIZE or 13)
    local leftBorderWidth = emphasized and EMPHASIZED_BORDER_WIDTH or 0

    -- Build ordered key list
    local keyList = {}
    if orderKeys then
        for _, k in ipairs(orderKeys) do
            if values[k] then
                table.insert(keyList, k)
            end
        end
    else
        for k in pairs(values) do
            table.insert(keyList, k)
        end
        table.sort(keyList)
    end

    -- Get theme colors
    local ar, ag, ab = theme:GetAccentColor()
    local dimR, dimG, dimB
    if options.useLightDim then
        dimR, dimG, dimB = theme:GetDimTextLightColor()
    else
        dimR, dimG, dimB = theme:GetDimTextColor()
    end
    local bgR, bgG, bgB, bgA = theme:GetBackgroundSolidColor()

    -- Create the row frame
    local row = CreateFrame("Frame", name, parent)
    row:SetHeight(rowHeight)

    -- Row hover background
    local hoverBg = row:CreateTexture(nil, "BACKGROUND", nil, -8)
    hoverBg:SetAllPoints()
    hoverBg:SetColorTexture(ar, ag, ab, 0.08)
    hoverBg:Hide()
    row._hoverBg = hoverBg

    -- Row border (subtle line below, plus left accent border for emphasized)
    local rowBorder = {}
    row._emphasized = emphasized

    local bottom = row:CreateTexture(nil, "BORDER", nil, -1)
    bottom:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    bottom:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
    bottom:SetHeight(1)
    bottom:SetColorTexture(ar, ag, ab, 0.2)
    if noBottomBorder then bottom:Hide() end
    rowBorder.BOTTOM = bottom

    -- Add left accent border for emphasized selectors
    if emphasized and leftBorderWidth > 0 then
        local leftBorder = row:CreateTexture(nil, "BORDER", nil, -1)
        leftBorder:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
        leftBorder:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
        leftBorder:SetWidth(leftBorderWidth)
        leftBorder:SetColorTexture(ar, ag, ab, 1)
        rowBorder.LEFT = leftBorder

        -- Faint background highlight for emphasized
        local emphBg = row:CreateTexture(nil, "BACKGROUND", nil, -7)
        emphBg:SetPoint("TOPLEFT", leftBorderWidth, 0)
        emphBg:SetPoint("BOTTOMRIGHT", 0, 0)
        emphBg:SetColorTexture(ar, ag, ab, 0.03)
        row._emphBg = emphBg
    end

    row._rowBorder = rowBorder

    -- Calculate label padding (account for left border on emphasized)
    local labelLeftPad = sc(SELECTOR_PADDING) + leftBorderWidth

    -- Label text (left side)
    local labelFS = row:CreateFontString(nil, "OVERLAY")
    local labelFont = theme:GetFont("LABEL")
    labelFS:SetFont(labelFont, labelFontSize, "")
    labelFS:SetPoint("LEFT", row, "LEFT", labelLeftPad, hasDesc and (emphasized and 12 or 6) or 0)
    labelFS:SetText(label)
    labelFS:SetTextColor(ar, ag, ab, 1)
    row._label = labelFS

    -- Description text (below label, if provided)
    if hasDesc then
        local descFS = row:CreateFontString(nil, "OVERLAY")
        local descFont = theme:GetFont("VALUE")
        local descFontSize = emphasized and 12 or 11
        descFS:SetFont(descFont, descFontSize, "")
        descFS:SetPoint("TOPLEFT", labelFS, "BOTTOMLEFT", 0, emphasized and -4 or -2)
        descFS:SetPoint("RIGHT", row, "RIGHT", -(selectorWidth + SELECTOR_PADDING * 2), 0)
        descFS:SetText(description)
        descFS:SetTextColor(dimR, dimG, dimB, 1)
        descFS:SetJustifyH("LEFT")
        descFS:SetWordWrap(true)
        row._description = descFS

        -- Deferred height measurement after text layout completes
        local function MeasureAndAdjustHeight()
            if not row or not descFS then return false end

            -- Get the row's effective width (try row, then parent)
            local rowWidth = row:GetWidth()
            if rowWidth == 0 and row:GetParent() then
                rowWidth = row:GetParent():GetWidth() or 0
            end
            if rowWidth == 0 then return false end

            -- Calculate available width for description text
            local descAvailableWidth = rowWidth - selectorWidth - (SELECTOR_PADDING * 2) - labelLeftPad
            if descAvailableWidth <= 0 then return false end

            -- Explicitly set description width so GetStringHeight returns wrapped height
            descFS:SetWidth(descAvailableWidth)

            local textHeight = descFS:GetStringHeight() or 0
            local paddingAbove = emphasized and DESC_PADDING_TOP_EMPH or DESC_PADDING_TOP
            local requiredHeight = LABEL_LINE_HEIGHT + paddingAbove + textHeight + DESC_PADDING_BOTTOM
            requiredHeight = math.min(requiredHeight, MAX_ROW_HEIGHT)

            local currentHeight = row:GetHeight()
            if requiredHeight > currentHeight then
                row:SetHeight(requiredHeight)
                if row._onHeightChanged then
                    row._onHeightChanged(requiredHeight - currentHeight)
                end
            end
            return true
        end

        -- Try immediate measurement, fall back to deferred
        if not MeasureAndAdjustHeight() then
            C_Timer.After(0.1, MeasureAndAdjustHeight)
        end
    end

    -- Selector container (right side)
    local selector = CreateFrame("Frame", nil, row)
    selector:SetSize(selectorWidth, sc(SELECTOR_HEIGHT))
    selector:SetPoint("RIGHT", row, "RIGHT", -sc(SELECTOR_PADDING), 0)

    if labelAlign == "field" then
        labelFS:ClearAllPoints()
        labelFS:SetPoint("RIGHT", selector, "LEFT", -sc(16), hasDesc and (emphasized and 12 or 6) or 0)
        labelFS:SetJustifyH("RIGHT")
    end

    -- Selector border
    local selBorder = {}

    local selTop = selector:CreateTexture(nil, "BORDER", nil, -1)
    selTop:SetPoint("TOPLEFT", selector, "TOPLEFT", 0, 0)
    selTop:SetPoint("TOPRIGHT", selector, "TOPRIGHT", 0, 0)
    selTop:SetHeight(1)
    selTop:SetColorTexture(ar, ag, ab, SELECTOR_BORDER_ALPHA)
    selBorder.TOP = selTop

    local selBottom = selector:CreateTexture(nil, "BORDER", nil, -1)
    selBottom:SetPoint("BOTTOMLEFT", selector, "BOTTOMLEFT", 0, 0)
    selBottom:SetPoint("BOTTOMRIGHT", selector, "BOTTOMRIGHT", 0, 0)
    selBottom:SetHeight(1)
    selBottom:SetColorTexture(ar, ag, ab, SELECTOR_BORDER_ALPHA)
    selBorder.BOTTOM = selBottom

    local selLeft = selector:CreateTexture(nil, "BORDER", nil, -1)
    selLeft:SetPoint("TOPLEFT", selector, "TOPLEFT", 0, -1)
    selLeft:SetPoint("BOTTOMLEFT", selector, "BOTTOMLEFT", 0, 1)
    selLeft:SetWidth(1)
    selLeft:SetColorTexture(ar, ag, ab, SELECTOR_BORDER_ALPHA)
    selBorder.LEFT = selLeft

    local selRight = selector:CreateTexture(nil, "BORDER", nil, -1)
    selRight:SetPoint("TOPRIGHT", selector, "TOPRIGHT", 0, -1)
    selRight:SetPoint("BOTTOMRIGHT", selector, "BOTTOMRIGHT", 0, 1)
    selRight:SetWidth(1)
    selRight:SetColorTexture(ar, ag, ab, SELECTOR_BORDER_ALPHA)
    selBorder.RIGHT = selRight

    selector._border = selBorder

    -- Selector background
    local selBg = selector:CreateTexture(nil, "BACKGROUND", nil, -7)
    selBg:SetPoint("TOPLEFT", 1, -1)
    selBg:SetPoint("BOTTOMRIGHT", -1, 1)
    selBg:SetColorTexture(bgR, bgG, bgB, bgA)
    selector._bg = selBg

    -- Left arrow button
    local leftArrow = CreateFrame("Button", nil, selector)
    leftArrow:SetSize(sc(SELECTOR_ARROW_WIDTH), sc(SELECTOR_HEIGHT) - 2)
    leftArrow:SetPoint("LEFT", selector, "LEFT", 1, 0)
    leftArrow:EnableMouse(true)
    leftArrow:RegisterForClicks("AnyUp")

    local leftArrowBg = leftArrow:CreateTexture(nil, "BACKGROUND", nil, -6)
    leftArrowBg:SetAllPoints()
    leftArrowBg:SetColorTexture(ar, ag, ab, 0)
    leftArrow._bg = leftArrowBg

    local leftArrowText = leftArrow:CreateFontString(nil, "OVERLAY")
    local arrowFont = theme:GetFont("BUTTON")
    leftArrowText:SetFont(arrowFont, sc(14), "")
    leftArrowText:SetPoint("CENTER", 0, 0)
    leftArrowText:SetText("◀")
    leftArrowText:SetTextColor(ar, ag, ab, 1)
    leftArrow._text = leftArrowText

    -- Separator line after left arrow
    local leftSep = selector:CreateTexture(nil, "BORDER", nil, 0)
    leftSep:SetPoint("TOPLEFT", leftArrow, "TOPRIGHT", 0, 0)
    leftSep:SetPoint("BOTTOMLEFT", leftArrow, "BOTTOMRIGHT", 0, 0)
    leftSep:SetWidth(1)
    leftSep:SetColorTexture(ar, ag, ab, 0.4)
    selector._leftSep = leftSep

    -- Right arrow button
    local rightArrow = CreateFrame("Button", nil, selector)
    rightArrow:SetSize(sc(SELECTOR_ARROW_WIDTH), sc(SELECTOR_HEIGHT) - 2)
    rightArrow:SetPoint("RIGHT", selector, "RIGHT", -1, 0)
    rightArrow:EnableMouse(true)
    rightArrow:RegisterForClicks("AnyUp")

    local rightArrowBg = rightArrow:CreateTexture(nil, "BACKGROUND", nil, -6)
    rightArrowBg:SetAllPoints()
    rightArrowBg:SetColorTexture(ar, ag, ab, 0)
    rightArrow._bg = rightArrowBg

    local rightArrowText = rightArrow:CreateFontString(nil, "OVERLAY")
    rightArrowText:SetFont(arrowFont, sc(14), "")
    rightArrowText:SetPoint("CENTER", 0, 0)
    rightArrowText:SetText("▶")
    rightArrowText:SetTextColor(ar, ag, ab, 1)
    rightArrow._text = rightArrowText

    -- Separator line before right arrow
    local rightSep = selector:CreateTexture(nil, "BORDER", nil, 0)
    rightSep:SetPoint("TOPRIGHT", rightArrow, "TOPLEFT", 0, 0)
    rightSep:SetPoint("BOTTOMRIGHT", rightArrow, "BOTTOMLEFT", 0, 0)
    rightSep:SetWidth(1)
    rightSep:SetColorTexture(ar, ag, ab, 0.4)
    selector._rightSep = rightSep

    -- Value display (center, clickable for dropdown)
    local valueBtn = CreateFrame("Button", nil, selector)
    valueBtn:SetPoint("LEFT", leftArrow, "RIGHT", 1, 0)
    valueBtn:SetPoint("RIGHT", rightArrow, "LEFT", -1, 0)
    valueBtn:SetHeight(sc(SELECTOR_HEIGHT) - 2)
    valueBtn:EnableMouse(true)
    valueBtn:RegisterForClicks("AnyUp")

    local valueBg = valueBtn:CreateTexture(nil, "BACKGROUND", nil, -6)
    valueBg:SetAllPoints()
    valueBg:SetColorTexture(ar, ag, ab, 0)
    valueBtn._bg = valueBg

    local valueText = valueBtn:CreateFontString(nil, "OVERLAY")
    local valueFont = theme:GetFont("VALUE")
    valueText:SetFont(valueFont, sc(12), "")
    valueText:SetPoint("CENTER", 0, 0)
    valueText:SetTextColor(1, 1, 1, 1)
    valueBtn._text = valueText

    -- Small dropdown indicator arrow, pinned to the field's right edge
    local dropIndicator = valueBtn:CreateFontString(nil, "OVERLAY")
    dropIndicator:SetFont(valueFont, sc(9), "")
    dropIndicator:SetPoint("RIGHT", valueBtn, "RIGHT", -sc(8), -1)
    dropIndicator:SetText("▼")
    dropIndicator:SetTextColor(dimR, dimG, dimB, 0.7)
    valueBtn._dropIndicator = dropIndicator

    selector._leftArrow = leftArrow
    selector._rightArrow = rightArrow
    selector._valueBtn = valueBtn
    row._selector = selector

    -- State tracking
    row._currentKey = nil
    row._keyList = keyList
    row._values = values
    row._syncLocked = false
    row._syncCooldown = syncCooldown
    row._syncLockTimer = nil
    row._isDisabled = false
    row._isDisabledFn = isDisabledFn
    row._selectorContainer = selector

    -- Find index of key in keyList (uses row._keyList for dynamic updates)
    local function getKeyIndex(key)
        for i, k in ipairs(row._keyList) do
            if k == key then
                return i
            end
        end
        return 1
    end

    -- Update visual display (uses row._values for dynamic updates)
    local function UpdateDisplay()
        local currentKey = row._currentKey
        local displayText = row._values[currentKey] or currentKey or "—"
        valueText:SetText(displayText)
    end
    row._updateDisplay = UpdateDisplay

    -- Initialize from getter
    row._currentKey = getValue()
    UpdateDisplay()

    -- Initialize disabled state from function
    if isDisabledFn then
        row._isDisabled = isDisabledFn() and true or false
        if row._isDisabled then
            C_Timer.After(0, function()
                if row and row.SetDisabled then
                    row:SetDisabled(true)
                end
            end)
        end
    end

    -- Sync lock helper functions (for Edit Mode sync protection)
    -- When locked, arrow clicks are ignored to prevent rapid changes from causing state desync
    local function UpdateArrowVisuals()
        local r, g, b = theme:GetAccentColor()
        local dimR, dimG, dimB = theme:GetDimTextColor()
        if row._syncLocked then
            -- Dim arrows when locked
            leftArrow._text:SetTextColor(dimR, dimG, dimB, 0.4)
            rightArrow._text:SetTextColor(dimR, dimG, dimB, 0.4)
        else
            -- Restore accent color when unlocked
            leftArrow._text:SetTextColor(r, g, b, 1)
            rightArrow._text:SetTextColor(r, g, b, 1)
        end
    end

    local function UnlockSync()
        row._syncLocked = false
        row._syncLockTimer = nil
        UpdateArrowVisuals()
    end

    local function LockSync()
        if not row._syncCooldown then return end  -- Only lock if syncCooldown is set

        -- Cancel any existing unlock timer
        if row._syncLockTimer then
            row._syncLockTimer:Cancel()
            row._syncLockTimer = nil
        end

        -- Lock and dim arrows
        row._syncLocked = true
        UpdateArrowVisuals()

        -- Schedule unlock after cooldown
        row._syncLockTimer = C_Timer.NewTimer(row._syncCooldown, function()
            UnlockSync()
        end)
    end
    row._lockSync = LockSync
    row._unlockSync = UnlockSync

    -- Arrow hover effects
    leftArrow:SetScript("OnEnter", function(btn)
        local r, g, b = theme:GetAccentColor()
        btn._bg:SetColorTexture(r, g, b, 0.2)
    end)
    leftArrow:SetScript("OnLeave", function(btn)
        btn._bg:SetColorTexture(0, 0, 0, 0)
    end)

    rightArrow:SetScript("OnEnter", function(btn)
        local r, g, b = theme:GetAccentColor()
        btn._bg:SetColorTexture(r, g, b, 0.2)
    end)
    rightArrow:SetScript("OnLeave", function(btn)
        btn._bg:SetColorTexture(0, 0, 0, 0)
    end)

    -- Value button hover
    valueBtn:SetScript("OnEnter", function(btn)
        local r, g, b = theme:GetAccentColor()
        btn._bg:SetColorTexture(r, g, b, 0.1)
        -- Highlight dropdown indicator on hover
        if btn._dropIndicator then
            btn._dropIndicator:SetTextColor(r, g, b, 1)
        end
    end)
    valueBtn:SetScript("OnLeave", function(btn)
        btn._bg:SetColorTexture(0, 0, 0, 0)
        -- Restore dropdown indicator color
        if btn._dropIndicator then
            local dr, dg, db = theme:GetDimTextColor()
            btn._dropIndicator:SetTextColor(dr, dg, db, 0.7)
        end
    end)

    -- Left arrow click (previous)
    leftArrow:SetScript("OnClick", function(btn)
        -- Check disabled or sync lock
        if row._isDisabled or row._syncLocked then
            return
        end
        local kList = row._keyList
        local idx = getKeyIndex(row._currentKey)
        idx = idx - 1
        if idx < 1 then idx = #kList end
        row._currentKey = kList[idx]
        setValue(row._currentKey)
        UpdateDisplay()
        LockSync()  -- Lock after value change if syncCooldown is configured
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    end)

    -- Right arrow click (next)
    rightArrow:SetScript("OnClick", function(btn)
        -- Check disabled or sync lock
        if row._isDisabled or row._syncLocked then
            return
        end
        local kList = row._keyList
        local idx = getKeyIndex(row._currentKey)
        idx = idx + 1
        if idx > #kList then idx = 1 end
        row._currentKey = kList[idx]
        setValue(row._currentKey)
        UpdateDisplay()
        LockSync()  -- Lock after value change if syncCooldown is configured
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    end)

    -- Dropdown menu frame (created once, reused)
    local dropdown = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    dropdown:SetFrameStrata("FULLSCREEN_DIALOG")
    dropdown:SetFrameLevel(100)
    dropdown:SetClampedToScreen(true)
    dropdown:Hide()
    row._dropdown = dropdown

    -- Dropdown backdrop/border
    dropdown:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    local ddBgR, ddBgG, ddBgB = theme:GetBackgroundSolidColor()
    dropdown:SetBackdropColor(ddBgR, ddBgG, ddBgB, 0.98)
    dropdown:SetBackdropBorderColor(ar, ag, ab, 0.8)

    -- Track dropdown option buttons
    dropdown._optionButtons = {}

    -- Close dropdown function
    local function CloseDropdown()
        dropdown:Hide()
        if dropdown._closeListener then
            dropdown._closeListener:Hide()
        end
    end
    row._closeDropdown = CloseDropdown

    -- Invisible fullscreen listener to close dropdown on outside click
    local closeListener = CreateFrame("Button", nil, UIParent)
    closeListener:SetFrameStrata("FULLSCREEN")
    closeListener:SetFrameLevel(99)
    closeListener:SetAllPoints(UIParent)
    closeListener:EnableMouse(true)
    closeListener:RegisterForClicks("AnyUp", "AnyDown")
    closeListener:SetScript("OnClick", function()
        CloseDropdown()
    end)
    closeListener:Hide()
    dropdown._closeListener = closeListener

    -- ESC key handling for dropdown
    addon.EscapeKey.Attach(dropdown, function()
        CloseDropdown()
        PlaySound(SOUNDKIT.IG_MAINMENU_CLOSE)
    end)

    -- Build and show dropdown (uses row._keyList and row._values for dynamic updates)
    local function ShowDropdown()
        -- The host surface can sit at or above this strata's level 100 (a
        -- Flyout raises itself on open); track the row's level so the list
        -- opens on top of whatever hosts the selector.
        dropdown:SetFrameLevel(math.max(100, row:GetFrameLevel() + 10))

        -- Position dropdown below the selector (or above if not enough space)
        dropdown:ClearAllPoints()

        local kList = row._keyList
        local vMap = row._values
        local optionHeight = sc(26)
        local optionPadding = 4
        local totalHeight = (#kList * optionHeight) + (optionPadding * 2)
        local dropdownWidth = selectorWidth

        dropdown:SetSize(dropdownWidth, totalHeight)

        -- Check if there's room below
        local selectorBottom = select(2, selector:GetCenter()) - (selector:GetHeight() / 2)
        local screenHeight = GetScreenHeight()
        local scale = UIParent:GetEffectiveScale()
        local spaceBelow = selectorBottom * scale

        if spaceBelow > totalHeight + 10 then
            -- Position below
            dropdown:SetPoint("TOPLEFT", selector, "BOTTOMLEFT", 0, -2)
        else
            -- Position above
            dropdown:SetPoint("BOTTOMLEFT", selector, "TOPLEFT", 0, 2)
        end

        -- Clear existing option buttons
        for _, btn in ipairs(dropdown._optionButtons) do
            if btn._infoIcon then
                btn._infoIcon:Cleanup()
            end
            btn:Hide()
            btn:SetParent(nil)
        end
        wipe(dropdown._optionButtons)

        -- Get current accent color
        local accentR, accentG, accentB = theme:GetAccentColor()

        -- Determine text offset based on whether any info icons exist
        local hasAnyInfoIcons = optionInfoIcons and next(optionInfoIcons)
        local textLeftOffset = hasAnyInfoIcons and 28 or 12

        -- Create option buttons
        for i, key in ipairs(kList) do
            local optBtn = CreateFrame("Button", nil, dropdown)
            optBtn:SetSize(dropdownWidth - 2, optionHeight)
            optBtn:SetPoint("TOPLEFT", dropdown, "TOPLEFT", 1, -optionPadding - ((i - 1) * optionHeight))
            optBtn:EnableMouse(true)
            optBtn:RegisterForClicks("AnyUp")

            -- Option background (for hover/selection)
            local optBg = optBtn:CreateTexture(nil, "BACKGROUND", nil, -6)
            optBg:SetAllPoints()
            optBg:SetColorTexture(0, 0, 0, 0)
            optBtn._bg = optBg

            -- Option text
            local optText = optBtn:CreateFontString(nil, "OVERLAY")
            local optFont = theme:GetFont("VALUE")
            optText:SetFont(optFont, sc(12), "")
            optText:SetPoint("LEFT", optBtn, "LEFT", textLeftOffset, 0)
            optText:SetPoint("RIGHT", optBtn, "RIGHT", -12, 0)
            optText:SetJustifyH("LEFT")
            optText:SetText(vMap[key] or key)
            optBtn._text = optText
            optBtn._key = key

            -- Add info icon if configured for this option key
            if optionInfoIcons and optionInfoIcons[key] then
                local iconData = optionInfoIcons[key]
                local infoIcon = Controls:CreateInfoIcon({
                    parent = optBtn,
                    tooltipText = iconData.tooltipText,
                    tooltipTitle = iconData.tooltipTitle,
                    size = 14,
                })
                if infoIcon then
                    infoIcon:SetPoint("LEFT", optBtn, "LEFT", 8, 0)
                    optBtn._infoIcon = infoIcon
                end
            end

            -- Highlight current selection
            local isSelected = (key == row._currentKey)
            if isSelected then
                optBg:SetColorTexture(accentR, accentG, accentB, 0.3)
                optText:SetTextColor(accentR, accentG, accentB, 1)
            else
                optText:SetTextColor(1, 1, 1, 1)
            end

            -- Hover effects
            optBtn:SetScript("OnEnter", function(btn)
                if btn._key ~= row._currentKey then
                    btn._bg:SetColorTexture(accentR, accentG, accentB, 0.15)
                else
                    btn._bg:SetColorTexture(accentR, accentG, accentB, 0.35)
                end
            end)
            optBtn:SetScript("OnLeave", function(btn)
                if btn._key == row._currentKey then
                    btn._bg:SetColorTexture(accentR, accentG, accentB, 0.3)
                else
                    btn._bg:SetColorTexture(0, 0, 0, 0)
                end
            end)

            -- Click to select
            optBtn:SetScript("OnClick", function(btn)
                row._currentKey = btn._key
                setValue(row._currentKey)
                UpdateDisplay()
                CloseDropdown()
                LockSync()  -- Lock after value change if syncCooldown is configured
                PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
            end)

            table.insert(dropdown._optionButtons, optBtn)
        end

        -- Show the close listener first (behind dropdown)
        closeListener:Show()
        closeListener:SetFrameLevel(dropdown:GetFrameLevel() - 1)

        -- Show dropdown
        dropdown:Show()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPEN)
    end

    -- Value button click (show dropdown)
    valueBtn:SetScript("OnClick", function(btn, mouseButton)
        -- Don't allow dropdown if sync locked
        if row._syncLocked then
            return
        end
        if dropdown:IsShown() then
            CloseDropdown()
        else
            ShowDropdown()
        end
    end)

    -- Row hover
    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self)
        self._hoverBg:Show()
    end)
    row:SetScript("OnLeave", function(self)
        self._hoverBg:Hide()
    end)

    -- Theme subscription
    local subscribeKey = "Selector_" .. (name or tostring(row))
    row._subscribeKey = subscribeKey

    theme:Subscribe(subscribeKey, function(r, g, b)
        -- Update label
        if row._label then
            row._label:SetTextColor(r, g, b, 1)
        end
        -- Update row border (_rowBorder is a table of textures, not a texture)
        if row._rowBorder then
            if row._rowBorder.BOTTOM then
                row._rowBorder.BOTTOM:SetColorTexture(r, g, b, 0.2)
            end
            if row._rowBorder.LEFT then
                row._rowBorder.LEFT:SetColorTexture(r, g, b, 1)
            end
        end
        -- Update hover bg
        if row._hoverBg then
            row._hoverBg:SetColorTexture(r, g, b, 0.08)
        end
        -- Update selector border
        if selector._border then
            for _, tex in pairs(selector._border) do
                tex:SetColorTexture(r, g, b, SELECTOR_BORDER_ALPHA)
            end
        end
        -- Update separators
        if selector._leftSep then
            selector._leftSep:SetColorTexture(r, g, b, 0.4)
        end
        if selector._rightSep then
            selector._rightSep:SetColorTexture(r, g, b, 0.4)
        end
        -- Update arrow text
        if leftArrow._text then
            leftArrow._text:SetTextColor(r, g, b, 1)
        end
        if rightArrow._text then
            rightArrow._text:SetTextColor(r, g, b, 1)
        end
        -- Update dropdown border color
        if dropdown and dropdown.SetBackdropBorderColor then
            dropdown:SetBackdropBorderColor(r, g, b, 0.8)
        end
    end)

    -- Public methods
    function row:SetValue(newKey)
        self._currentKey = newKey
        self._updateDisplay()
    end

    function row:GetValue()
        return self._currentKey
    end

    function row:Refresh()
        self._currentKey = getValue()
        -- Check disabled state from function
        if self._isDisabledFn then
            local newDisabled = self._isDisabledFn() and true or false
            if newDisabled ~= self._isDisabled then
                self:SetDisabled(newDisabled)
            end
        end
        self._updateDisplay()
    end

    function row:SetDisabled(disabled)
        self._isDisabled = disabled and true or false
        local disabledAlpha = 0.35
        local ar, ag, ab = theme:GetAccentColor()
        local dR, dG, dB = theme:GetDimTextColor()

        if self._isDisabled then
            -- Gray out all elements
            if self._label then self._label:SetTextColor(dR, dG, dB, disabledAlpha) end
            if self._description then self._description:SetAlpha(disabledAlpha) end
            if self._selectorContainer then self._selectorContainer:SetAlpha(disabledAlpha) end
        else
            -- Restore normal appearance
            if self._label then self._label:SetTextColor(ar, ag, ab, 1) end
            if self._description then self._description:SetAlpha(1) end
            if self._selectorContainer then self._selectorContainer:SetAlpha(1) end
        end
    end

    function row:IsDisabled()
        return self._isDisabled
    end

    -- Dynamic label update (for orientation-dependent labels like "# Rows" vs "# Columns")
    function row:SetLabel(newLabel)
        if self._label then
            self._label:SetText(newLabel)
        end
    end

    -- Dynamic options update (for orientation-dependent options like Left/Right vs Up/Down)
    -- newValues: table of { key = "Display Text" } pairs
    -- newOrder: optional array of keys for display order
    function row:SetOptions(newValues, newOrder)
        if not newValues then return end

        -- Update stored values and keyList
        self._values = newValues

        -- Rebuild keyList
        local newKeyList = {}
        if newOrder then
            for _, k in ipairs(newOrder) do
                if newValues[k] then
                    table.insert(newKeyList, k)
                end
            end
        else
            for k in pairs(newValues) do
                table.insert(newKeyList, k)
            end
            table.sort(newKeyList)
        end
        self._keyList = newKeyList

        -- If current key is not in new options, select first valid option
        local currentValid = false
        for _, k in ipairs(newKeyList) do
            if k == self._currentKey then
                currentValid = true
                break
            end
        end

        if not currentValid and #newKeyList > 0 then
            self._currentKey = newKeyList[1]
            setValue(self._currentKey)
        end

        -- Update display
        self._updateDisplay()
    end

    function row:Cleanup()
        if self._subscribeKey then
            theme:Unsubscribe(self._subscribeKey)
        end
        -- Cancel any pending sync lock timer
        if self._syncLockTimer then
            self._syncLockTimer:Cancel()
            self._syncLockTimer = nil
        end
        -- Clean up dropdown
        if self._closeDropdown then
            self._closeDropdown()
        end
        if self._dropdown then
            if self._dropdown._closeListener then
                self._dropdown._closeListener:Hide()
                self._dropdown._closeListener:SetParent(nil)
            end
            if self._dropdown._optionButtons then
                for _, btn in ipairs(self._dropdown._optionButtons) do
                    if btn._infoIcon then
                        btn._infoIcon:Cleanup()
                    end
                    btn:Hide()
                    btn:SetParent(nil)
                end
            end
            self._dropdown:Hide()
            self._dropdown:SetParent(nil)
        end
    end

    function row:GetDescriptionFontString()
        return self._description
    end

    return row
end
