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
    selector._border = Controls.CreateBorder(selector, { alpha = DUAL_SELECTOR_BORDER_ALPHA })

    -- Selector background
    selector._bg = Controls.AddBackground(selector, { inset = 1, sublevel = Controls.SUBLEVEL_FILL })

    -- Arrow buttons and separators
    local leftArrow, leftSep = Controls.CreateArrowButton(selector, {
        width = DUAL_SELECTOR_ARROW_WIDTH,
        height = DUAL_SELECTOR_HEIGHT - 2,
        glyph = "\226\151\128", -- ◀
        separator = "RIGHT",
    })
    leftArrow:SetPoint("LEFT", selector, "LEFT", 1, 0)
    selector._leftSep = leftSep

    local rightArrow, rightSep = Controls.CreateArrowButton(selector, {
        width = DUAL_SELECTOR_ARROW_WIDTH,
        height = DUAL_SELECTOR_HEIGHT - 2,
        glyph = "\226\150\182", -- ▶
        separator = "LEFT",
    })
    rightArrow:SetPoint("RIGHT", selector, "RIGHT", -1, 0)
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

    -- Dropdown option list (rebuilt from selector._keyList on every open)
    local dropdown = Controls.CreatePopupList({
        anchor = selector,
        getKeys = function() return selector._keyList end,
        getValues = function() return selector._values end,
        getSelectedKey = function() return selector._currentKey end,
        onSelect = function(key)
            selector._currentKey = key
            setValue(key)
            UpdateDisplay()
            LockSync()
        end,
    })
    selector._dropdown = dropdown
    selector._closeDropdown = function() dropdown:Close() end
    selector._showDropdown = function() dropdown:Open() end

    -- Value button click (show dropdown)
    valueBtn:SetScript("OnClick", function(btn, mouseButton)
        if selector._syncLocked then return end
        dropdown:Toggle()
    end)

    return selector
end

-- Export for reuse by SelectorToggleRow
Controls._CreateMiniSelector = CreateMiniSelector

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
    row._hoverBg = Controls.AddHoverFill(row, { sublevel = Controls.SUBLEVEL_BG })

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
        -- RIGHT anchor comes after the dual container exists: the description
        -- column must end where the selectors begin, not at the row edge --
        -- full-width text rendered straight through the selector gaps.
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

    if row._description then
        row._description:SetPoint("RIGHT", dualContainer, "LEFT",
            -DUAL_SELECTOR_LABEL_RIGHT_MARGIN, 0)
    end

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
        -- A description needs a readable wrap column, not just the label's
        -- string width (the selectors would otherwise cover most of it).
        if row._description then
            local descReserve = 200 + DUAL_SELECTOR_LABEL_RIGHT_MARGIN
            if descReserve > labelWidth then labelWidth = descReserve end
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
        -- Update both mini selectors
        for _, miniSel in ipairs({row._selectorA, row._selectorB}) do
            if miniSel then
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
                if miniSel._dropdown then
                    miniSel._dropdown:Destroy()
                end
            end
        end
    end

    function row:GetDescriptionFontString()
        return self._description
    end

    return row
end
