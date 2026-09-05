-- SelectorColorPicker.lua - Selector with inline color swatch (visible when custom value selected)
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

local SELECTOR_SWATCH_WIDTH = 40
local SELECTOR_SWATCH_HEIGHT = 16
local SELECTOR_SWATCH_BORDER = 2


-- SelectorColorPicker: Selector with inline color swatch (visible when custom value selected)

function Controls:CreateSelectorColorPicker(options)
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
    local getColor = options.getColor or function() return 1, 1, 1, 1 end
    local setColor = options.setColor or function() end
    local customValue = options.customValue or "custom"
    local hasAlpha = options.hasAlpha or false
    local selectorWidth = options.width or SELECTOR_DEFAULT_WIDTH
    local name = options.name
    local syncCooldown = options.syncCooldown
    local isDisabledFn = options.isDisabled or options.disabled or function() return false end
    local optionInfoIcons = options.optionInfoIcons

    local hasDesc = description and description ~= ""
    local rowHeight = hasDesc and SELECTOR_ROW_HEIGHT_WITH_DESC or SELECTOR_ROW_HEIGHT

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

    -- Label and description
    Controls.AddRowChrome(row, {
        label = label,
        description = description,
        reserve = selectorWidth + SELECTOR_PADDING * 2,
        measureReserve = selectorWidth + (SELECTOR_PADDING * 2),
        dimColor = { dimR, dimG, dimB },
    })

    -- Selector container (right side)
    local selector = CreateFrame("Frame", nil, row)
    selector:SetSize(selectorWidth, SELECTOR_HEIGHT)
    selector:SetPoint("RIGHT", row, "RIGHT", -SELECTOR_PADDING, 0)

    -- Selector border
    selector._border = Controls.CreateBorder(selector, { alpha = SELECTOR_BORDER_ALPHA })

    -- Selector background
    selector._bg = Controls.AddBackground(selector, { inset = 1, sublevel = Controls.SUBLEVEL_FILL })

    -- Arrow buttons and separators
    local leftArrow, leftSep = Controls.CreateArrowButton(selector, {
        width = SELECTOR_ARROW_WIDTH,
        height = SELECTOR_HEIGHT - 2,
        glyph = "\226\151\128", -- ◀
        separator = "RIGHT",
    })
    leftArrow:SetPoint("LEFT", selector, "LEFT", 1, 0)
    selector._leftSep = leftSep

    local rightArrow, rightSep = Controls.CreateArrowButton(selector, {
        width = SELECTOR_ARROW_WIDTH,
        height = SELECTOR_HEIGHT - 2,
        glyph = "\226\150\182", -- ▶
        separator = "LEFT",
    })
    rightArrow:SetPoint("RIGHT", selector, "RIGHT", -1, 0)
    selector._rightSep = rightSep

    -- Value display (center, clickable for dropdown)
    local valueBtn = CreateFrame("Button", nil, selector)
    valueBtn:SetPoint("LEFT", leftArrow, "RIGHT", 1, 0)
    valueBtn:SetPoint("RIGHT", rightArrow, "LEFT", -1, 0)
    valueBtn:SetHeight(SELECTOR_HEIGHT - 2)
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
    dropIndicator:SetText("\226\150\188")
    dropIndicator:SetTextColor(dimR, dimG, dimB, 0.7)
    valueBtn._dropIndicator = dropIndicator

    selector._leftArrow = leftArrow
    selector._rightArrow = rightArrow
    selector._valueBtn = valueBtn
    row._selector = selector

    -- Color swatch (inside value area, visible when customValue is selected)
    local swatch = CreateFrame("Button", nil, valueBtn)
    swatch:SetSize(SELECTOR_SWATCH_WIDTH, SELECTOR_SWATCH_HEIGHT)
    swatch:SetPoint("LEFT", valueBtn, "LEFT", 6, 0)
    swatch:EnableMouse(true)
    swatch:RegisterForClicks("AnyUp")
    swatch:Hide()

    -- Swatch border
    swatch._border = Controls.CreateBorder(swatch, {
        thickness = SELECTOR_SWATCH_BORDER,
        sublevel = 1,
        getAlpha = function(self) return self:IsMouseOver() and 1 or 0.8 end,
    })

    -- Swatch background (checkerboard for alpha)
    local checkerBg = swatch:CreateTexture(nil, "BACKGROUND", nil, 0)
    checkerBg:SetPoint("TOPLEFT", SELECTOR_SWATCH_BORDER, -SELECTOR_SWATCH_BORDER)
    checkerBg:SetPoint("BOTTOMRIGHT", -SELECTOR_SWATCH_BORDER, SELECTOR_SWATCH_BORDER)
    checkerBg:SetColorTexture(0.3, 0.3, 0.3, 1)
    swatch._checkerBg = checkerBg

    -- Color fill
    local colorFill = swatch:CreateTexture(nil, "ARTWORK", nil, 1)
    colorFill:SetPoint("TOPLEFT", SELECTOR_SWATCH_BORDER, -SELECTOR_SWATCH_BORDER)
    colorFill:SetPoint("BOTTOMRIGHT", -SELECTOR_SWATCH_BORDER, SELECTOR_SWATCH_BORDER)
    swatch._colorFill = colorFill

    row._swatch = swatch

    -- State tracking
    row._currentKey = nil
    row._keyList = keyList
    row._values = values
    row._customValue = customValue
    row._syncLocked = false
    row._syncCooldown = syncCooldown
    row._syncLockTimer = nil
    row._isDisabled = false
    row._isDisabledFn = isDisabledFn

    -- Helper to read color
    local function ReadColor()
        local result = { getColor() }
        if type(result[1]) == "table" then
            local c = result[1]
            return c.r or c[1] or 1, c.g or c[2] or 1, c.b or c[3] or 1, c.a or c[4] or 1
        else
            return result[1] or 1, result[2] or 1, result[3] or 1, result[4] or 1
        end
    end

    -- Update swatch color display
    local function UpdateSwatchColor()
        local r, g, b, a = ReadColor()
        colorFill:SetColorTexture(r, g, b, hasAlpha and a or 1)
    end
    row._updateSwatchColor = UpdateSwatchColor

    -- Find index of key in keyList
    local function getKeyIndex(key)
        for i, k in ipairs(row._keyList) do
            if k == key then
                return i
            end
        end
        return 1
    end

    -- Update visual display
    local function UpdateDisplay()
        local currentKey = row._currentKey
        local displayText = row._values[currentKey] or currentKey or "\226\128\148"

        -- Check if custom value is selected
        local isCustom
        if type(row._customValue) == "table" then
            isCustom = false
            for _, val in ipairs(row._customValue) do
                if currentKey == val then isCustom = true; break end
            end
        else
            isCustom = (currentKey == row._customValue)
        end

        if isCustom then
            -- Show swatch, adjust text position
            swatch:Show()
            UpdateSwatchColor()
            valueText:ClearAllPoints()
            valueText:SetPoint("LEFT", swatch, "RIGHT", 4, 0)
            valueText:SetPoint("RIGHT", valueBtn, "RIGHT", -16, 0)
            valueText:SetJustifyH("LEFT")
        else
            -- Hide swatch, center text
            swatch:Hide()
            valueText:ClearAllPoints()
            valueText:SetPoint("CENTER", -6, 0)
            valueText:SetJustifyH("CENTER")
        end

        valueText:SetText(displayText)
    end
    row._updateDisplay = UpdateDisplay

    -- Initialize from getter
    row._currentKey = getValue()
    UpdateDisplay()

    -- Disabled state visual update
    local function UpdateDisabledState()
        local isDisabled = row._isDisabled
        local ar, ag, ab = theme:GetAccentColor()
        local dimR, dimG, dimB = theme:GetDimTextColor()

        if isDisabled then
            -- Gray out label
            if row._label then
                row._label:SetTextColor(dimR, dimG, dimB, 0.5)
            end
            -- Gray out description
            if row._description then
                row._description:SetTextColor(dimR, dimG, dimB, 0.4)
            end
            -- Disable arrows visually
            if leftArrow._text then
                leftArrow._text:SetTextColor(dimR, dimG, dimB, 0.3)
            end
            if rightArrow._text then
                rightArrow._text:SetTextColor(dimR, dimG, dimB, 0.3)
            end
            -- Gray out value text
            if valueText then
                valueText:SetTextColor(dimR, dimG, dimB, 0.5)
            end
            -- Dim the selector border
            if selector._border then
                for _, tex in pairs(selector._border) do
                    tex:SetColorTexture(dimR, dimG, dimB, 0.3)
                end
            end
            -- Disable mouse on interactive elements
            leftArrow:EnableMouse(false)
            rightArrow:EnableMouse(false)
            valueBtn:EnableMouse(false)
            swatch:EnableMouse(false)
        else
            -- Restore label
            if row._label then
                row._label:SetTextColor(ar, ag, ab, 1)
            end
            -- Restore description
            if row._description then
                row._description:SetTextColor(dimR, dimG, dimB, 1)
            end
            -- Restore arrows (respecting sync lock)
            if not row._syncLocked then
                if leftArrow._text then
                    leftArrow._text:SetTextColor(ar, ag, ab, 1)
                end
                if rightArrow._text then
                    rightArrow._text:SetTextColor(ar, ag, ab, 1)
                end
            end
            -- Restore value text
            if valueText then
                valueText:SetTextColor(1, 1, 1, 1)
            end
            -- Restore selector border
            if selector._border then
                for _, tex in pairs(selector._border) do
                    tex:SetColorTexture(ar, ag, ab, SELECTOR_BORDER_ALPHA)
                end
            end
            -- Enable mouse on interactive elements
            leftArrow:EnableMouse(true)
            rightArrow:EnableMouse(true)
            valueBtn:EnableMouse(true)
            swatch:EnableMouse(true)
        end
    end
    row._updateDisabledState = UpdateDisabledState

    -- Sync lock helper functions
    local function UpdateArrowVisuals()
        if row._isDisabled then return end -- Skip if disabled
        local r, g, b = theme:GetAccentColor()
        local dR, dG, dB = theme:GetDimTextColor()
        if row._syncLocked then
            leftArrow._text:SetTextColor(dR, dG, dB, 0.4)
            rightArrow._text:SetTextColor(dR, dG, dB, 0.4)
        else
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
        if not row._syncCooldown then return end

        if row._syncLockTimer then
            row._syncLockTimer:Cancel()
            row._syncLockTimer = nil
        end

        row._syncLocked = true
        UpdateArrowVisuals()

        row._syncLockTimer = C_Timer.NewTimer(row._syncCooldown, function()
            UnlockSync()
        end)
    end
    row._lockSync = LockSync
    row._unlockSync = UnlockSync

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

    -- Swatch hover handlers
    swatch:SetScript("OnEnter", function(self)
        row._hoverBg:Show()
        self._border:Refresh()
    end)
    swatch:SetScript("OnLeave", function(self)
        if not row:IsMouseOver() then
            row._hoverBg:Hide()
        end
        self._border:Refresh()
    end)

    -- Swatch click opens color picker
    swatch:SetScript("OnClick", function()
        local curR, curG, curB, curA = ReadColor()

        ColorPickerFrame:SetupColorPickerAndShow({
            r = curR,
            g = curG,
            b = curB,
            hasOpacity = hasAlpha,
            opacity = curA,
            swatchFunc = function()
                local newR, newG, newB = ColorPickerFrame:GetColorRGB()
                local newA = hasAlpha and ColorPickerFrame:GetColorAlpha() or 1
                setColor(newR, newG, newB, newA)
                colorFill:SetColorTexture(newR, newG, newB, hasAlpha and newA or 1)
            end,
            cancelFunc = function(prev)
                if prev then
                    local pR, pG, pB, pA = prev.r or 1, prev.g or 1, prev.b or 1, prev.a or 1
                    setColor(pR, pG, pB, pA)
                    colorFill:SetColorTexture(pR, pG, pB, hasAlpha and pA or 1)
                end
            end,
        })
    end)

    -- Left arrow click (previous)
    leftArrow:SetScript("OnClick", function(btn)
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
        LockSync()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    end)

    -- Right arrow click (next)
    rightArrow:SetScript("OnClick", function(btn)
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
        LockSync()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    end)

    -- Dropdown menu frame (created once, reused)
    local dropdown = CreateFrame("Frame", nil, UIParent)
    dropdown:SetFrameStrata("FULLSCREEN_DIALOG")
    dropdown:SetFrameLevel(100)
    dropdown:SetClampedToScreen(true)
    dropdown:Hide()
    row._dropdown = dropdown

    -- Dropdown chrome: solid fill plus a 1px accent border
    Controls.AddBackground(dropdown, { alpha = 0.98 })
    dropdown._border = Controls.CreateBorder(dropdown, { alpha = 0.8 })

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

    -- Build and show dropdown
    local function ShowDropdown()
        dropdown:ClearAllPoints()

        local kList = row._keyList
        local vMap = row._values
        local optionHeight = 26
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
            dropdown:SetPoint("TOPLEFT", selector, "BOTTOMLEFT", 0, -2)
        else
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

            local optBg = optBtn:CreateTexture(nil, "BACKGROUND", nil, -6)
            optBg:SetAllPoints()
            optBg:SetColorTexture(0, 0, 0, 0)
            optBtn._bg = optBg

            local optText = optBtn:CreateFontString(nil, "OVERLAY")
            local optFont = theme:GetFont("VALUE")
            optText:SetFont(optFont, 12, "")
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

            local isSelected = (key == row._currentKey)
            if isSelected then
                optBg:SetColorTexture(accentR, accentG, accentB, 0.3)
                optText:SetTextColor(accentR, accentG, accentB, 1)
            else
                optText:SetTextColor(1, 1, 1, 1)
            end

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

            optBtn:SetScript("OnClick", function(btn)
                row._currentKey = btn._key
                setValue(row._currentKey)
                UpdateDisplay()
                CloseDropdown()
                LockSync()
                PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
            end)

            table.insert(dropdown._optionButtons, optBtn)
        end

        closeListener:Show()
        closeListener:SetFrameLevel(dropdown:GetFrameLevel() - 1)

        dropdown:Show()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPEN)
    end

    -- Value button click (show dropdown)
    valueBtn:SetScript("OnClick", function(btn, mouseButton)
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
        if not swatch:IsMouseOver() then
            self._hoverBg:Hide()
        end
    end)

    -- Theme subscription
    local subscribeKey = "SelectorColorPicker_" .. (name or tostring(row))
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
    end)

    -- Public methods
    function row:SetValue(newKey)
        self._currentKey = newKey
        self._updateDisplay()
    end

    function row:GetValue()
        return self._currentKey
    end

    function row:SetColor(r, g, b, a)
        setColor(r, g, b, a or 1)
        self._updateSwatchColor()
    end

    function row:GetColor()
        return ReadColor()
    end

    function row:Refresh()
        self._currentKey = getValue()
        self._updateDisplay()
        self._updateSwatchColor()
        -- Check disabled state from function
        if self._isDisabledFn then
            local newDisabled = self._isDisabledFn() and true or false
            if newDisabled ~= self._isDisabled then
                self._isDisabled = newDisabled
                self._updateDisabledState()
            end
        end
    end

    function row:SetDisabled(disabled)
        self._isDisabled = disabled and true or false
        self._updateDisabledState()
    end

    function row:IsDisabled()
        return self._isDisabled
    end

    function row:SetLabel(newLabel)
        if self._label then
            self._label:SetText(newLabel)
        end
    end

    function row:SetOptions(newValues, newOrder)
        if not newValues then return end

        self._values = newValues

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

        self._updateDisplay()
    end

    function row:Cleanup()
        if self._subscribeKey then
            theme:Unsubscribe(self._subscribeKey)
        end
        if self._syncLockTimer then
            self._syncLockTimer:Cancel()
            self._syncLockTimer = nil
        end
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

    -- Initialize disabled state
    if row._isDisabledFn then
        row._isDisabled = row._isDisabledFn() and true or false
        if row._isDisabled then
            row._updateDisabledState()
        end
    end

    function row:GetDescriptionFontString()
        return self._description
    end

    return row
end
