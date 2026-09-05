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
local DESC_PADDING_TOP = 2        -- Space between label and description
local DESC_PADDING_TOP_EMPH = 4   -- Space for emphasized controls

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
    -- disabledOptions = { [key] = true }: the option is listed but inert
    -- (dimmed, no hover, click ignored, arrows skip it). For "Coming Soon"
    -- entries that should be visible without being selectable.
    local disabledOptions = options.disabledOptions
    local function IsOptionDisabled(key)
        return disabledOptions ~= nil and disabledOptions[key] == true
    end
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

    -- Create the row frame
    local row = CreateFrame("Frame", name, parent)
    row:SetHeight(rowHeight)

    -- Row hover background
    row._hoverBg = Controls.AddHoverFill(row, { sublevel = Controls.SUBLEVEL_BG })

    -- Row border (subtle line below, plus left accent border for emphasized)
    row._emphasized = emphasized
    local rowSides = { "BOTTOM" }
    if emphasized and leftBorderWidth > 0 then
        table.insert(rowSides, "LEFT")
    end
    row._rowBorder = Controls.CreateBorder(row, {
        sides = rowSides,
        thickness = { BOTTOM = 1, LEFT = leftBorderWidth },
        alpha = 0.2,
        sideAlphas = { LEFT = 1 },
    })
    if noBottomBorder then row._rowBorder.BOTTOM:Hide() end

    if emphasized and leftBorderWidth > 0 then
        -- Faint background highlight for emphasized
        local emphBg = row:CreateTexture(nil, "BACKGROUND", nil, -7)
        emphBg:SetPoint("TOPLEFT", leftBorderWidth, 0)
        emphBg:SetPoint("BOTTOMRIGHT", 0, 0)
        emphBg:SetColorTexture(ar, ag, ab, 0.03)
        row._emphBg = emphBg
    end

    -- Calculate label padding (account for left border on emphasized)
    local labelLeftPad = sc(SELECTOR_PADDING) + leftBorderWidth

    -- Label and description
    local labelFS = Controls.AddRowChrome(row, {
        label = label,
        labelFontSize = labelFontSize,
        labelYOffset = hasDesc and (emphasized and 12 or 6) or 0,
        padLeft = labelLeftPad,
        description = description,
        descFontSize = emphasized and 12 or 11,
        padAbove = emphasized and DESC_PADDING_TOP_EMPH or DESC_PADDING_TOP,
        reserve = selectorWidth + SELECTOR_PADDING * 2,
        dimColor = { dimR, dimG, dimB },
    })

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
    selector._border = Controls.CreateBorder(selector, { alpha = SELECTOR_BORDER_ALPHA })

    -- Selector background
    selector._bg = Controls.AddBackground(selector, { inset = 1, sublevel = Controls.SUBLEVEL_FILL })

    -- Arrow buttons and separators
    local leftArrow, leftSep = Controls.CreateArrowButton(selector, {
        width = sc(SELECTOR_ARROW_WIDTH),
        height = sc(SELECTOR_HEIGHT) - 2,
        glyph = "◀",
        fontSize = sc(14),
        separator = "RIGHT",
    })
    leftArrow:SetPoint("LEFT", selector, "LEFT", 1, 0)
    selector._leftSep = leftSep

    local rightArrow, rightSep = Controls.CreateArrowButton(selector, {
        width = sc(SELECTOR_ARROW_WIDTH),
        height = sc(SELECTOR_HEIGHT) - 2,
        glyph = "▶",
        fontSize = sc(14),
        separator = "LEFT",
    })
    rightArrow:SetPoint("RIGHT", selector, "RIGHT", -1, 0)
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
        -- One hook covering every path that changes the value: both arrows, the
        -- dropdown, SetValue and Refresh all land here.
        if row._onDisplayChanged then
            row._onDisplayChanged(currentKey)
        end
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
        -- Step past inert options; give up after a full lap.
        for _ = 1, #kList do
            idx = idx - 1
            if idx < 1 then idx = #kList end
            if not IsOptionDisabled(kList[idx]) then break end
        end
        if IsOptionDisabled(kList[idx]) then return end
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
        for _ = 1, #kList do
            idx = idx + 1
            if idx > #kList then idx = 1 end
            if not IsOptionDisabled(kList[idx]) then break end
        end
        if IsOptionDisabled(kList[idx]) then return end
        row._currentKey = kList[idx]
        setValue(row._currentKey)
        UpdateDisplay()
        LockSync()  -- Lock after value change if syncCooldown is configured
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    end)

    -- Dropdown option list (rebuilt from row._keyList on every open)
    local dropdown = Controls.CreatePopupList({
        anchor = selector,
        width = selectorWidth,
        optionHeight = sc(26),
        fontSize = sc(12),
        levelFrom = row,
        infoIcons = optionInfoIcons,
        isInert = IsOptionDisabled,
        getKeys = function() return row._keyList end,
        getValues = function() return row._values end,
        getSelectedKey = function() return row._currentKey end,
        onSelect = function(key)
            row._currentKey = key
            setValue(key)
            UpdateDisplay()
            LockSync()  -- Lock after value change if syncCooldown is configured
        end,
    })
    row._dropdown = dropdown
    row._closeDropdown = function() dropdown:Close() end

    -- Value button click (show dropdown)
    valueBtn:SetScript("OnClick", function(btn, mouseButton)
        -- Don't allow dropdown if sync locked
        if row._syncLocked then
            return
        end
        dropdown:Toggle()
    end)

    -- Row hover
    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self)
        self._hoverBg:Show()
    end)
    row:SetScript("OnLeave", function(self)
        -- The in-field gear is a descendant, so entering it leaves the row.
        if self._gear and self._gear:IsMouseOver() then return end
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
        if self._dropdown then
            self._dropdown:Destroy()
        end
    end

    function row:GetDescriptionFontString()
        return self._description
    end

    -- In-field gear opening a per-option sub-options fly-out. The config is
    -- copied so the caller's table can be shared across rows, and the gear
    -- scales with a scaled control. See ui/v2/controls/SelectorGear.lua.
    if options.gear and Controls.AttachSelectorGear then
        local gearConfig = {}
        for k, v in pairs(options.gear) do
            gearConfig[k] = v
        end
        if gearConfig.sizeScale == nil then
            gearConfig.sizeScale = S
        end
        Controls.AttachSelectorGear(row, gearConfig)
    end

    return row
end
