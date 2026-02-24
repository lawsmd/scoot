-- DualSelector.lua - Two compact selectors side-by-side in a single row
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

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

local DUAL_SELECTOR_HEIGHT = 28
local DUAL_SELECTOR_ARROW_WIDTH = 28
local DUAL_SELECTOR_ROW_HEIGHT = 36
local DUAL_SELECTOR_ROW_HEIGHT_WITH_DESC = 80
local DUAL_SELECTOR_PADDING = 12
local DUAL_SELECTOR_BORDER_ALPHA = 0.5
local DUAL_SELECTOR_GAP = 12
local DUAL_SELECTOR_DEFAULT_CONTAINER_WIDTH = 400
local DUAL_SELECTOR_LABEL_RIGHT_MARGIN = 12

-- Dynamic height constants (match Selector.lua)
local MAX_ROW_HEIGHT = 200
local LABEL_LINE_HEIGHT = 16
local DESC_PADDING_TOP = 2
local DESC_PADDING_BOTTOM = 36

--------------------------------------------------------------------------------
-- Helper: CreateMiniSelector
--------------------------------------------------------------------------------
-- Creates a single self-contained selector box with border, background,
-- arrows, separators, value button, dropdown indicator, dropdown frame,
-- close listener, ESC handling, sync lock, and hover effects.
--
-- Returns the mini-selector frame with all refs attached.
--------------------------------------------------------------------------------

local function CreateMiniSelector(opts, parentContainer, theme, useLightDim)
    local values = opts.values or {}
    local orderKeys = opts.order
    local getValue = opts.get or function() return nil end
    local setValue = opts.set or function() end
    local syncCooldown = opts.syncCooldown

    -- Get theme colors
    local ar, ag, ab = theme:GetAccentColor()
    local dimR, dimG, dimB
    if useLightDim then
        dimR, dimG, dimB = theme:GetDimTextLightColor()
    else
        dimR, dimG, dimB = theme:GetDimTextColor()
    end
    local bgR, bgG, bgB, bgA = theme:GetBackgroundSolidColor()

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

    -- Create the selector frame
    local selector = CreateFrame("Frame", nil, parentContainer)
    selector:SetHeight(DUAL_SELECTOR_HEIGHT)
    -- Width will be set by the parent after deferred measurement

    -- Selector border
    local selBorder = {}

    local selTop = selector:CreateTexture(nil, "BORDER", nil, -1)
    selTop:SetPoint("TOPLEFT", selector, "TOPLEFT", 0, 0)
    selTop:SetPoint("TOPRIGHT", selector, "TOPRIGHT", 0, 0)
    selTop:SetHeight(1)
    selTop:SetColorTexture(ar, ag, ab, DUAL_SELECTOR_BORDER_ALPHA)
    selBorder.TOP = selTop

    local selBottom = selector:CreateTexture(nil, "BORDER", nil, -1)
    selBottom:SetPoint("BOTTOMLEFT", selector, "BOTTOMLEFT", 0, 0)
    selBottom:SetPoint("BOTTOMRIGHT", selector, "BOTTOMRIGHT", 0, 0)
    selBottom:SetHeight(1)
    selBottom:SetColorTexture(ar, ag, ab, DUAL_SELECTOR_BORDER_ALPHA)
    selBorder.BOTTOM = selBottom

    local selLeft = selector:CreateTexture(nil, "BORDER", nil, -1)
    selLeft:SetPoint("TOPLEFT", selector, "TOPLEFT", 0, -1)
    selLeft:SetPoint("BOTTOMLEFT", selector, "BOTTOMLEFT", 0, 1)
    selLeft:SetWidth(1)
    selLeft:SetColorTexture(ar, ag, ab, DUAL_SELECTOR_BORDER_ALPHA)
    selBorder.LEFT = selLeft

    local selRight = selector:CreateTexture(nil, "BORDER", nil, -1)
    selRight:SetPoint("TOPRIGHT", selector, "TOPRIGHT", 0, -1)
    selRight:SetPoint("BOTTOMRIGHT", selector, "BOTTOMRIGHT", 0, 1)
    selRight:SetWidth(1)
    selRight:SetColorTexture(ar, ag, ab, DUAL_SELECTOR_BORDER_ALPHA)
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
    leftArrow:SetSize(DUAL_SELECTOR_ARROW_WIDTH, DUAL_SELECTOR_HEIGHT - 2)
    leftArrow:SetPoint("LEFT", selector, "LEFT", 1, 0)
    leftArrow:EnableMouse(true)
    leftArrow:RegisterForClicks("AnyUp")

    local leftArrowBg = leftArrow:CreateTexture(nil, "BACKGROUND", nil, -6)
    leftArrowBg:SetAllPoints()
    leftArrowBg:SetColorTexture(ar, ag, ab, 0)
    leftArrow._bg = leftArrowBg

    local leftArrowText = leftArrow:CreateFontString(nil, "OVERLAY")
    local arrowFont = theme:GetFont("BUTTON")
    leftArrowText:SetFont(arrowFont, 14, "")
    leftArrowText:SetPoint("CENTER", 0, 0)
    leftArrowText:SetText("\226\151\128")  -- ◀
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
    rightArrow:SetSize(DUAL_SELECTOR_ARROW_WIDTH, DUAL_SELECTOR_HEIGHT - 2)
    rightArrow:SetPoint("RIGHT", selector, "RIGHT", -1, 0)
    rightArrow:EnableMouse(true)
    rightArrow:RegisterForClicks("AnyUp")

    local rightArrowBg = rightArrow:CreateTexture(nil, "BACKGROUND", nil, -6)
    rightArrowBg:SetAllPoints()
    rightArrowBg:SetColorTexture(ar, ag, ab, 0)
    rightArrow._bg = rightArrowBg

    local rightArrowText = rightArrow:CreateFontString(nil, "OVERLAY")
    rightArrowText:SetFont(arrowFont, 14, "")
    rightArrowText:SetPoint("CENTER", 0, 0)
    rightArrowText:SetText("\226\150\182")  -- ▶
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
    valueBtn:SetHeight(DUAL_SELECTOR_HEIGHT - 2)
    valueBtn:EnableMouse(true)
    valueBtn:RegisterForClicks("AnyUp")

    local valueBg = valueBtn:CreateTexture(nil, "BACKGROUND", nil, -6)
    valueBg:SetAllPoints()
    valueBg:SetColorTexture(ar, ag, ab, 0)
    valueBtn._bg = valueBg

    local valueText = valueBtn:CreateFontString(nil, "OVERLAY")
    local valueFont = theme:GetFont("VALUE")
    valueText:SetFont(valueFont, 12, "")
    valueText:SetPoint("CENTER", -6, 0)
    valueText:SetTextColor(1, 1, 1, 1)
    valueBtn._text = valueText

    -- Small dropdown indicator arrow
    local dropIndicator = valueBtn:CreateFontString(nil, "OVERLAY")
    dropIndicator:SetFont(valueFont, 9, "")
    dropIndicator:SetPoint("LEFT", valueText, "RIGHT", 4, -1)
    dropIndicator:SetText("\226\150\188")  -- ▼
    dropIndicator:SetTextColor(dimR, dimG, dimB, 0.7)
    valueBtn._dropIndicator = dropIndicator

    selector._leftArrow = leftArrow
    selector._rightArrow = rightArrow
    selector._valueBtn = valueBtn

    -- State tracking
    selector._currentKey = nil
    selector._keyList = keyList
    selector._values = values
    selector._syncLocked = false
    selector._syncCooldown = syncCooldown
    selector._syncLockTimer = nil

    -- Find index of key in keyList
    local function getKeyIndex(key)
        for i, k in ipairs(selector._keyList) do
            if k == key then
                return i
            end
        end
        return 1
    end

    -- Update visual display
    local function UpdateDisplay()
        local currentKey = selector._currentKey
        local displayText = selector._values[currentKey] or currentKey or "\226\128\148"  -- —
        valueText:SetText(displayText)
    end
    selector._updateDisplay = UpdateDisplay

    -- Initialize from getter
    selector._currentKey = getValue()
    UpdateDisplay()

    -- Sync lock helper functions
    local function UpdateArrowVisuals()
        local r, g, b = theme:GetAccentColor()
        local dR, dG, dB = theme:GetDimTextColor()
        if selector._syncLocked then
            leftArrow._text:SetTextColor(dR, dG, dB, 0.4)
            rightArrow._text:SetTextColor(dR, dG, dB, 0.4)
        else
            leftArrow._text:SetTextColor(r, g, b, 1)
            rightArrow._text:SetTextColor(r, g, b, 1)
        end
    end

    local function UnlockSync()
        selector._syncLocked = false
        selector._syncLockTimer = nil
        UpdateArrowVisuals()
    end

    local function LockSync()
        if not selector._syncCooldown then return end

        if selector._syncLockTimer then
            selector._syncLockTimer:Cancel()
            selector._syncLockTimer = nil
        end

        selector._syncLocked = true
        UpdateArrowVisuals()

        selector._syncLockTimer = C_Timer.NewTimer(selector._syncCooldown, function()
            UnlockSync()
        end)
    end
    selector._lockSync = LockSync
    selector._unlockSync = UnlockSync

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
        if btn._dropIndicator then
            btn._dropIndicator:SetTextColor(r, g, b, 1)
        end
    end)
    valueBtn:SetScript("OnLeave", function(btn)
        btn._bg:SetColorTexture(0, 0, 0, 0)
        if btn._dropIndicator then
            local dr, dg, db = theme:GetDimTextColor()
            btn._dropIndicator:SetTextColor(dr, dg, db, 0.7)
        end
    end)

    -- Left arrow click (previous)
    leftArrow:SetScript("OnClick", function(btn)
        if selector._isDisabled or selector._syncLocked then return end
        local kList = selector._keyList
        if #kList == 0 then return end
        local idx = getKeyIndex(selector._currentKey)
        idx = idx - 1
        if idx < 1 then idx = #kList end
        selector._currentKey = kList[idx]
        setValue(selector._currentKey)
        UpdateDisplay()
        LockSync()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    end)

    -- Right arrow click (next)
    rightArrow:SetScript("OnClick", function(btn)
        if selector._isDisabled or selector._syncLocked then return end
        local kList = selector._keyList
        if #kList == 0 then return end
        local idx = getKeyIndex(selector._currentKey)
        idx = idx + 1
        if idx > #kList then idx = 1 end
        selector._currentKey = kList[idx]
        setValue(selector._currentKey)
        UpdateDisplay()
        LockSync()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    end)

    -- Dropdown menu frame (created once, reused)
    local dropdown = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    dropdown:SetFrameStrata("FULLSCREEN_DIALOG")
    dropdown:SetFrameLevel(100)
    dropdown:SetClampedToScreen(true)
    dropdown:Hide()
    selector._dropdown = dropdown

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
    selector._closeDropdown = CloseDropdown

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
    dropdown:EnableKeyboard(true)
    dropdown:SetPropagateKeyboardInput(true)
    dropdown:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            self:SetPropagateKeyboardInput(false)
            CloseDropdown()
            PlaySound(SOUNDKIT.IG_MAINMENU_CLOSE)
        else
            self:SetPropagateKeyboardInput(true)
        end
    end)

    -- Build and show dropdown
    local function ShowDropdown()
        dropdown:ClearAllPoints()

        local kList = selector._keyList
        local vMap = selector._values
        local optionHeight = 26
        local optionPadding = 4
        local totalHeight = (#kList * optionHeight) + (optionPadding * 2)

        -- Read width from current selector size at show time
        local dropdownWidth = selector:GetWidth()
        if dropdownWidth < 60 then dropdownWidth = 150 end

        dropdown:SetSize(dropdownWidth, totalHeight)

        -- Check if there's room below
        local selectorBottom = select(2, selector:GetCenter()) - (selector:GetHeight() / 2)
        local scale = UIParent:GetEffectiveScale()
        local spaceBelow = selectorBottom * scale

        if spaceBelow > totalHeight + 10 then
            dropdown:SetPoint("TOPLEFT", selector, "BOTTOMLEFT", 0, -2)
        else
            dropdown:SetPoint("BOTTOMLEFT", selector, "TOPLEFT", 0, 2)
        end

        -- Clear existing option buttons
        for _, btn in ipairs(dropdown._optionButtons) do
            btn:Hide()
            btn:SetParent(nil)
        end
        wipe(dropdown._optionButtons)

        -- Get current accent color
        local accentR, accentG, accentB = theme:GetAccentColor()

        -- Create option buttons
        for i, key in ipairs(kList) do
            local optBtn = CreateFrame("Button", nil, dropdown)
            optBtn:SetSize(dropdownWidth - 2, optionHeight)
            optBtn:SetPoint("TOPLEFT", dropdown, "TOPLEFT", 1, -optionPadding - ((i - 1) * optionHeight))
            optBtn:EnableMouse(true)
            optBtn:RegisterForClicks("AnyUp")

            -- Option background
            local optBg = optBtn:CreateTexture(nil, "BACKGROUND", nil, -6)
            optBg:SetAllPoints()
            optBg:SetColorTexture(0, 0, 0, 0)
            optBtn._bg = optBg

            -- Option text
            local optText = optBtn:CreateFontString(nil, "OVERLAY")
            local optFont = theme:GetFont("VALUE")
            optText:SetFont(optFont, 12, "")
            optText:SetPoint("LEFT", optBtn, "LEFT", 12, 0)
            optText:SetPoint("RIGHT", optBtn, "RIGHT", -12, 0)
            optText:SetJustifyH("LEFT")
            optText:SetText(vMap[key] or key)
            optBtn._text = optText
            optBtn._key = key

            -- Highlight current selection
            local isSelected = (key == selector._currentKey)
            if isSelected then
                optBg:SetColorTexture(accentR, accentG, accentB, 0.3)
                optText:SetTextColor(accentR, accentG, accentB, 1)
            else
                optText:SetTextColor(1, 1, 1, 1)
            end

            -- Hover effects
            optBtn:SetScript("OnEnter", function(btn)
                if btn._key ~= selector._currentKey then
                    btn._bg:SetColorTexture(accentR, accentG, accentB, 0.15)
                else
                    btn._bg:SetColorTexture(accentR, accentG, accentB, 0.35)
                end
            end)
            optBtn:SetScript("OnLeave", function(btn)
                if btn._key == selector._currentKey then
                    btn._bg:SetColorTexture(accentR, accentG, accentB, 0.3)
                else
                    btn._bg:SetColorTexture(0, 0, 0, 0)
                end
            end)

            -- Click to select
            optBtn:SetScript("OnClick", function(btn)
                selector._currentKey = btn._key
                setValue(selector._currentKey)
                UpdateDisplay()
                CloseDropdown()
                LockSync()
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
    selector._showDropdown = ShowDropdown

    -- Value button click (show dropdown)
    valueBtn:SetScript("OnClick", function(btn, mouseButton)
        if selector._syncLocked then return end
        if dropdown:IsShown() then
            CloseDropdown()
        else
            ShowDropdown()
        end
    end)

    return selector
end

--------------------------------------------------------------------------------
-- DualSelector: Two compact selectors side-by-side
--------------------------------------------------------------------------------
-- Creates a dual selector control with:
--   - Two selectors (A and B) side-by-side
--   - Each with left/right arrow buttons and dropdown
--   - Label text on the left
--   - Optional description below label
--   - Deferred width measurement to fill available space
--
-- Options table:
--   label       : Setting label text (string, optional)
--   description : Optional description text below (string)
--   selectorA   : Table with selector A options (see below)
--   selectorB   : Table with selector B options (see below)
--   parent      : Parent frame (required)
--   disabled    : Function returning disabled state (optional)
--   name        : Optional global frame name
--
-- Selector A/B options:
--   values      : Table of { key = "Display Text" }
--   order       : Optional array of keys for display order
--   get         : Function returning current key
--   set         : Function(newKey) to save value
--   syncCooldown: Optional cooldown for sync lock
--------------------------------------------------------------------------------

function Controls:CreateDualSelector(options)
    local theme = GetTheme()
    if not options or not options.parent then
        return nil
    end

    local parent = options.parent
    local label = options.label
    local description = options.description
    local selectorAOpts = options.selectorA or {}
    local selectorBOpts = options.selectorB or {}
    local name = options.name
    local isDisabledFn = options.disabled or options.isDisabled
    local useLightDim = options.useLightDim
    local maxContainerWidth = options.maxContainerWidth

    local hasLabel = label and label ~= ""
    local hasDesc = description and description ~= ""
    local rowHeight = hasDesc and DUAL_SELECTOR_ROW_HEIGHT_WITH_DESC or DUAL_SELECTOR_ROW_HEIGHT

    -- Get theme colors
    local ar, ag, ab = theme:GetAccentColor()
    local dimR, dimG, dimB
    if useLightDim then
        dimR, dimG, dimB = theme:GetDimTextLightColor()
    else
        dimR, dimG, dimB = theme:GetDimTextColor()
    end

    -- Create the row frame
    local row = CreateFrame("Frame", name, parent)
    row:SetHeight(rowHeight)

    -- Row hover background
    local hoverBg = row:CreateTexture(nil, "BACKGROUND", nil, -8)
    hoverBg:SetAllPoints()
    hoverBg:SetColorTexture(ar, ag, ab, 0.08)
    hoverBg:Hide()
    row._hoverBg = hoverBg

    -- Row border (subtle line below)
    local rowBorder = row:CreateTexture(nil, "BORDER", nil, -1)
    rowBorder:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    rowBorder:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
    rowBorder:SetHeight(1)
    rowBorder:SetColorTexture(ar, ag, ab, 0.2)
    row._rowBorder = rowBorder

    -- Label text (left side, if provided)
    local labelFS
    if hasLabel then
        labelFS = row:CreateFontString(nil, "OVERLAY")
        local labelFont = theme:GetFont("LABEL")
        labelFS:SetFont(labelFont, 13, "")
        labelFS:SetPoint("LEFT", row, "LEFT", DUAL_SELECTOR_PADDING, hasDesc and 6 or 0)
        labelFS:SetText(label)
        labelFS:SetTextColor(ar, ag, ab, 1)
        row._label = labelFS
    end

    -- Description text (below label, if provided)
    if hasDesc and labelFS then
        local descFS = row:CreateFontString(nil, "OVERLAY")
        local descFont = theme:GetFont("VALUE")
        descFS:SetFont(descFont, 11, "")
        descFS:SetPoint("TOPLEFT", labelFS, "BOTTOMLEFT", 0, -2)
        descFS:SetPoint("RIGHT", row, "RIGHT", -DUAL_SELECTOR_PADDING, 0)
        descFS:SetText(description)
        descFS:SetTextColor(dimR, dimG, dimB, 1)
        descFS:SetJustifyH("LEFT")
        descFS:SetWordWrap(true)
        row._description = descFS
    end

    -- Dual container (right side)
    local dualContainer = CreateFrame("Frame", nil, row)
    dualContainer:SetSize(DUAL_SELECTOR_DEFAULT_CONTAINER_WIDTH, DUAL_SELECTOR_HEIGHT)
    dualContainer:SetPoint("RIGHT", row, "RIGHT", -DUAL_SELECTOR_PADDING, 0)
    row._dualSelectorContainer = dualContainer

    -- Create mini-selector A (left within container)
    local miniSelectorA = CreateMiniSelector(selectorAOpts, dualContainer, theme, useLightDim)
    miniSelectorA:SetPoint("LEFT", dualContainer, "LEFT", 0, 0)
    row._selectorA = miniSelectorA

    -- Create mini-selector B (right of A with gap)
    local miniSelectorB = CreateMiniSelector(selectorBOpts, dualContainer, theme, useLightDim)
    miniSelectorB:SetPoint("LEFT", miniSelectorA, "RIGHT", DUAL_SELECTOR_GAP, 0)
    row._selectorB = miniSelectorB

    -- Cross-wire dropdowns: opening one closes the other
    local origShowA = miniSelectorA._showDropdown
    local origShowB = miniSelectorB._showDropdown
    miniSelectorA._showDropdown = function()
        miniSelectorB._closeDropdown()
        origShowA()
    end
    miniSelectorB._showDropdown = function()
        miniSelectorA._closeDropdown()
        origShowB()
    end

    -- Re-wire value button clicks to use cross-wired show functions
    miniSelectorA._valueBtn:SetScript("OnClick", function(btn, mouseButton)
        if miniSelectorA._syncLocked then return end
        if miniSelectorA._dropdown:IsShown() then
            miniSelectorA._closeDropdown()
        else
            miniSelectorA._showDropdown()
        end
    end)
    miniSelectorB._valueBtn:SetScript("OnClick", function(btn, mouseButton)
        if miniSelectorB._syncLocked then return end
        if miniSelectorB._dropdown:IsShown() then
            miniSelectorB._closeDropdown()
        else
            miniSelectorB._showDropdown()
        end
    end)

    -- Deferred width measurement
    C_Timer.After(0, function()
        if not row or not row:GetParent() then return end

        local rowWidth = row:GetWidth()
        if rowWidth == 0 and row:GetParent() then
            rowWidth = row:GetParent():GetWidth() or 0
        end
        if rowWidth == 0 then return end

        -- Calculate available container width
        local labelWidth = 0
        if labelFS then
            labelWidth = labelFS:GetStringWidth() + DUAL_SELECTOR_LABEL_RIGHT_MARGIN
        end
        local containerWidth = rowWidth - labelWidth - (DUAL_SELECTOR_PADDING * 2)
        if containerWidth < 100 then containerWidth = DUAL_SELECTOR_DEFAULT_CONTAINER_WIDTH end
        if maxContainerWidth and containerWidth > maxContainerWidth then
            containerWidth = maxContainerWidth
        end

        dualContainer:SetWidth(containerWidth)

        -- Each selector gets half the container minus the gap
        local eachWidth = (containerWidth - DUAL_SELECTOR_GAP) / 2
        miniSelectorA:SetWidth(eachWidth)
        miniSelectorB:SetWidth(eachWidth)
    end)

    -- State tracking
    row._isDisabled = false
    row._isDisabledFn = isDisabledFn

    -- Row hover
    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self)
        self._hoverBg:Show()
    end)
    row:SetScript("OnLeave", function(self)
        self._hoverBg:Hide()
    end)

    -- Theme subscription
    local subscribeKey = "DualSelector_" .. (name or tostring(row))
    row._subscribeKey = subscribeKey

    theme:Subscribe(subscribeKey, function(r, g, b)
        -- Update label
        if row._label then
            row._label:SetTextColor(r, g, b, 1)
        end
        -- Update row border
        if row._rowBorder then
            row._rowBorder:SetColorTexture(r, g, b, 0.2)
        end
        -- Update hover bg
        if row._hoverBg then
            row._hoverBg:SetColorTexture(r, g, b, 0.08)
        end

        -- Update both mini selectors
        for _, miniSel in ipairs({row._selectorA, row._selectorB}) do
            if miniSel then
                -- Update selector border
                if miniSel._border then
                    for _, tex in pairs(miniSel._border) do
                        tex:SetColorTexture(r, g, b, DUAL_SELECTOR_BORDER_ALPHA)
                    end
                end
                -- Update separators
                if miniSel._leftSep then
                    miniSel._leftSep:SetColorTexture(r, g, b, 0.4)
                end
                if miniSel._rightSep then
                    miniSel._rightSep:SetColorTexture(r, g, b, 0.4)
                end
                -- Update arrow text (only if not sync locked)
                if not miniSel._syncLocked then
                    if miniSel._leftArrow and miniSel._leftArrow._text then
                        miniSel._leftArrow._text:SetTextColor(r, g, b, 1)
                    end
                    if miniSel._rightArrow and miniSel._rightArrow._text then
                        miniSel._rightArrow._text:SetTextColor(r, g, b, 1)
                    end
                end
                -- Update dropdown border color
                if miniSel._dropdown and miniSel._dropdown.SetBackdropBorderColor then
                    miniSel._dropdown:SetBackdropBorderColor(r, g, b, 0.8)
                end
            end
        end
    end)

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

    -- Public methods

    function row:SetValues(keyA, keyB)
        if self._selectorA then
            self._selectorA._currentKey = keyA
            self._selectorA._updateDisplay()
        end
        if self._selectorB then
            self._selectorB._currentKey = keyB
            self._selectorB._updateDisplay()
        end
    end

    function row:GetValues()
        local aKey = self._selectorA and self._selectorA._currentKey or nil
        local bKey = self._selectorB and self._selectorB._currentKey or nil
        return aKey, bKey
    end

    function row:Refresh()
        if self._selectorA then
            local getA = selectorAOpts.get or function() return nil end
            self._selectorA._currentKey = getA()
            self._selectorA._updateDisplay()
        end
        if self._selectorB then
            local getB = selectorBOpts.get or function() return nil end
            self._selectorB._currentKey = getB()
            self._selectorB._updateDisplay()
        end
        -- Check disabled state from function
        if self._isDisabledFn then
            local newDisabled = self._isDisabledFn() and true or false
            if newDisabled ~= self._isDisabled then
                self:SetDisabled(newDisabled)
            end
        end
    end

    function row:SetDisabled(disabled)
        self._isDisabled = disabled and true or false
        local disabledAlpha = 0.35
        local acR, acG, acB = theme:GetAccentColor()
        local dR, dG, dB = theme:GetDimTextColor()

        -- Propagate to mini selectors
        for _, miniSel in ipairs({self._selectorA, self._selectorB}) do
            if miniSel then
                miniSel._isDisabled = self._isDisabled
            end
        end

        if self._isDisabled then
            if self._label then self._label:SetTextColor(dR, dG, dB, disabledAlpha) end
            if self._description then self._description:SetAlpha(disabledAlpha) end
            if self._dualSelectorContainer then self._dualSelectorContainer:SetAlpha(disabledAlpha) end
        else
            if self._label then self._label:SetTextColor(acR, acG, acB, 1) end
            if self._description then self._description:SetAlpha(1) end
            if self._dualSelectorContainer then self._dualSelectorContainer:SetAlpha(1) end
        end
    end

    function row:IsDisabled()
        return self._isDisabled
    end

    function row:SetLabel(newLabel)
        if self._label then
            self._label:SetText(newLabel)
        end
    end

    function row:SetOptionsA(newValues, newOrder)
        if not self._selectorA or not newValues then return end
        local miniSel = self._selectorA
        miniSel._values = newValues

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
        miniSel._keyList = newKeyList

        -- If current key is not in new options, select first valid option
        local currentValid = false
        for _, k in ipairs(newKeyList) do
            if k == miniSel._currentKey then
                currentValid = true
                break
            end
        end
        if not currentValid and #newKeyList > 0 then
            miniSel._currentKey = newKeyList[1]
            local setA = selectorAOpts.set or function() end
            setA(miniSel._currentKey)
        end

        miniSel._updateDisplay()
    end

    function row:SetOptionsB(newValues, newOrder)
        if not self._selectorB or not newValues then return end
        local miniSel = self._selectorB
        miniSel._values = newValues

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
        miniSel._keyList = newKeyList

        -- If current key is not in new options, select first valid option
        local currentValid = false
        for _, k in ipairs(newKeyList) do
            if k == miniSel._currentKey then
                currentValid = true
                break
            end
        end
        if not currentValid and #newKeyList > 0 then
            miniSel._currentKey = newKeyList[1]
            local setB = selectorBOpts.set or function() end
            setB(miniSel._currentKey)
        end

        miniSel._updateDisplay()
    end

    function row:Cleanup()
        if self._subscribeKey then
            theme:Unsubscribe(self._subscribeKey)
        end
        -- Clean up both mini selectors
        for _, miniSel in ipairs({self._selectorA, self._selectorB}) do
            if miniSel then
                -- Cancel sync lock timer
                if miniSel._syncLockTimer then
                    miniSel._syncLockTimer:Cancel()
                    miniSel._syncLockTimer = nil
                end
                -- Close dropdown
                if miniSel._closeDropdown then
                    miniSel._closeDropdown()
                end
                if miniSel._dropdown then
                    if miniSel._dropdown._closeListener then
                        miniSel._dropdown._closeListener:Hide()
                        miniSel._dropdown._closeListener:SetParent(nil)
                    end
                    if miniSel._dropdown._optionButtons then
                        for _, btn in ipairs(miniSel._dropdown._optionButtons) do
                            btn:Hide()
                            btn:SetParent(nil)
                        end
                    end
                    miniSel._dropdown:Hide()
                    miniSel._dropdown:SetParent(nil)
                end
            end
        end
    end

    function row:GetDescriptionFontString()
        return self._description
    end

    return row
end
