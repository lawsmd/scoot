-- DualBarStyleRow.lua - Compact bar texture + color selector in a single row
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

local MINI_LABEL_HEIGHT = 14
local MINI_LABEL_GAP = 3
local ROW_HEIGHT = 36 + MINI_LABEL_HEIGHT + MINI_LABEL_GAP
local ROW_HEIGHT_WITH_DESC = 80 + MINI_LABEL_HEIGHT + MINI_LABEL_GAP
local CONTROL_HEIGHT = 28
local ARROW_WIDTH = 28
local PADDING = 12
local GAP = 12
local BORDER_ALPHA = 0.5
local DEFAULT_CONTAINER_WIDTH = 340
local MAX_CONTAINER_WIDTH = 410
local LABEL_RIGHT_MARGIN = 12

local TEXTURE_WIDTH_PCT = 0.38   -- Texture gets 38%
local COLOR_WIDTH_PCT = 0.62     -- Color gets 62%

local SWATCH_WIDTH = 40
local SWATCH_HEIGHT = 16
local SWATCH_BORDER = 2

-- Dynamic height constants (match Selector.lua)
local MAX_ROW_HEIGHT = 200
local LABEL_LINE_HEIGHT = 16
local DESC_PADDING_TOP = 2
local DESC_PADDING_BOTTOM = 36

--------------------------------------------------------------------------------
-- Helper: GetTextureDisplayName (mirrors BarTexturePicker.lua logic)
--------------------------------------------------------------------------------

local function GetTextureDisplayName(key)
    if key == "default" then return "Default" end
    if addon.Media and addon.Media.GetBarTextureDisplayName then
        local displayName = addon.Media.GetBarTextureDisplayName(key)
        if displayName and displayName ~= "" then
            return displayName
        end
    end
    return key or "Default"
end

--------------------------------------------------------------------------------
-- Helper: CreateTextureMini
--------------------------------------------------------------------------------
-- Creates a compact texture selector box: bordered frame with a clickable
-- button showing texture name + dropdown arrow. No left/right arrows.
-- Clicking opens the BarTexturePicker popup.
--------------------------------------------------------------------------------

local function CreateTextureMini(opts, parentContainer, theme, useLightDim)
    local getTexture = opts.getTexture or function() return "default" end
    local setTexture = opts.setTexture or function() end

    -- Get theme colors
    local ar, ag, ab = theme:GetAccentColor()
    local dimR, dimG, dimB
    if useLightDim then
        dimR, dimG, dimB = theme:GetDimTextLightColor()
    else
        dimR, dimG, dimB = theme:GetDimTextColor()
    end
    local bgR, bgG, bgB, bgA = theme:GetBackgroundSolidColor()

    -- Create the selector frame
    local mini = CreateFrame("Frame", nil, parentContainer)
    mini:SetHeight(CONTROL_HEIGHT)

    -- Border
    local border = {}

    local bTop = mini:CreateTexture(nil, "BORDER", nil, -1)
    bTop:SetPoint("TOPLEFT", mini, "TOPLEFT", 0, 0)
    bTop:SetPoint("TOPRIGHT", mini, "TOPRIGHT", 0, 0)
    bTop:SetHeight(1)
    bTop:SetColorTexture(ar, ag, ab, BORDER_ALPHA)
    border.TOP = bTop

    local bBottom = mini:CreateTexture(nil, "BORDER", nil, -1)
    bBottom:SetPoint("BOTTOMLEFT", mini, "BOTTOMLEFT", 0, 0)
    bBottom:SetPoint("BOTTOMRIGHT", mini, "BOTTOMRIGHT", 0, 0)
    bBottom:SetHeight(1)
    bBottom:SetColorTexture(ar, ag, ab, BORDER_ALPHA)
    border.BOTTOM = bBottom

    local bLeft = mini:CreateTexture(nil, "BORDER", nil, -1)
    bLeft:SetPoint("TOPLEFT", mini, "TOPLEFT", 0, -1)
    bLeft:SetPoint("BOTTOMLEFT", mini, "BOTTOMLEFT", 0, 1)
    bLeft:SetWidth(1)
    bLeft:SetColorTexture(ar, ag, ab, BORDER_ALPHA)
    border.LEFT = bLeft

    local bRight = mini:CreateTexture(nil, "BORDER", nil, -1)
    bRight:SetPoint("TOPRIGHT", mini, "TOPRIGHT", 0, -1)
    bRight:SetPoint("BOTTOMRIGHT", mini, "BOTTOMRIGHT", 0, 1)
    bRight:SetWidth(1)
    bRight:SetColorTexture(ar, ag, ab, BORDER_ALPHA)
    border.RIGHT = bRight

    mini._border = border

    -- Background
    local bg = mini:CreateTexture(nil, "BACKGROUND", nil, -7)
    bg:SetPoint("TOPLEFT", 1, -1)
    bg:SetPoint("BOTTOMRIGHT", -1, 1)
    bg:SetColorTexture(bgR, bgG, bgB, bgA)
    mini._bg = bg

    -- Value button (full width, shows texture name + dropdown arrow)
    local valueBtn = CreateFrame("Button", nil, mini)
    valueBtn:SetPoint("TOPLEFT", mini, "TOPLEFT", 1, -1)
    valueBtn:SetPoint("BOTTOMRIGHT", mini, "BOTTOMRIGHT", -1, 1)
    valueBtn:EnableMouse(true)
    valueBtn:RegisterForClicks("AnyUp")

    local valueBg = valueBtn:CreateTexture(nil, "BACKGROUND", nil, -6)
    valueBg:SetAllPoints()
    valueBg:SetColorTexture(ar, ag, ab, 0)
    valueBtn._bg = valueBg

    local valueFont = theme:GetFont("VALUE")
    local valueText = valueBtn:CreateFontString(nil, "OVERLAY")
    valueText:SetFont(valueFont, 12, "")
    valueText:SetPoint("LEFT", valueBtn, "LEFT", 8, 0)
    valueText:SetPoint("RIGHT", valueBtn, "RIGHT", -20, 0)
    valueText:SetJustifyH("LEFT")
    valueText:SetWordWrap(false)
    valueText:SetTextColor(1, 1, 1, 1)
    valueBtn._text = valueText

    -- Dropdown indicator arrow
    local arrowFont = theme:GetFont("BUTTON")
    local dropArrow = valueBtn:CreateFontString(nil, "OVERLAY")
    dropArrow:SetFont(arrowFont, 10, "")
    dropArrow:SetPoint("RIGHT", valueBtn, "RIGHT", -4, 0)
    dropArrow:SetText("\226\150\188")  -- ▼
    dropArrow:SetTextColor(dimR, dimG, dimB, 0.7)
    valueBtn._dropArrow = dropArrow

    mini._valueBtn = valueBtn

    -- State
    mini._currentValue = getTexture() or "default"
    mini._getTexture = getTexture
    mini._setTexture = setTexture

    -- Update display
    local function UpdateDisplay()
        valueText:SetText(GetTextureDisplayName(mini._currentValue))
    end
    mini._updateDisplay = UpdateDisplay
    UpdateDisplay()

    -- Hover effects
    valueBtn:SetScript("OnEnter", function(btn)
        local r, g, b = theme:GetAccentColor()
        btn._bg:SetColorTexture(r, g, b, 0.1)
        for _, tex in pairs(mini._border) do
            tex:SetColorTexture(r, g, b, 0.8)
        end
        if btn._dropArrow then
            btn._dropArrow:SetTextColor(r, g, b, 1)
        end
    end)
    valueBtn:SetScript("OnLeave", function(btn)
        local bgRc, bgGc, bgBc, bgAc = theme:GetBackgroundSolidColor()
        btn._bg:SetColorTexture(bgRc, bgGc, bgBc, 0)
        local r, g, b = theme:GetAccentColor()
        for _, tex in pairs(mini._border) do
            tex:SetColorTexture(r, g, b, BORDER_ALPHA)
        end
        local dr, dg, db = theme:GetDimTextColor()
        if btn._dropArrow then
            btn._dropArrow:SetTextColor(dr, dg, db, 0.7)
        end
    end)

    -- Click to open bar texture picker popup
    valueBtn:SetScript("OnClick", function(self)
        if mini._isDisabled then return end
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)

        local pseudoSetting = {
            GetValue = function()
                return mini._currentValue
            end,
            SetValue = function(_, value)
                mini._currentValue = value
                mini._setTexture(value)
                UpdateDisplay()
            end
        }

        addon.ShowBarTexturePicker(self, pseudoSetting, nil, function(selectedValue)
            mini._currentValue = selectedValue
            mini._setTexture(selectedValue)
            UpdateDisplay()
        end)
    end)

    return mini
end

--------------------------------------------------------------------------------
-- Helper: CreateColorMini
--------------------------------------------------------------------------------
-- Creates a compact color selector with left/right arrows, dropdown,
-- and optional inline color swatch (shown when custom value is selected).
-- This is a miniaturized version of SelectorColorPicker.
--------------------------------------------------------------------------------

local function CreateColorMini(opts, parentContainer, theme, useLightDim)
    local values = opts.colorValues or {}
    local orderKeys = opts.colorOrder
    local getValue = opts.getColorMode or function() return nil end
    local setValue = opts.setColorMode or function() end
    local getColor = opts.getColor or function() return 1, 1, 1, 1 end
    local setColor = opts.setColor or function() end
    local customValue = opts.customColorValue or "custom"
    local hasAlpha = opts.hasAlpha or false
    local optionInfoIcons = opts.colorInfoIcons

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
    local mini = CreateFrame("Frame", nil, parentContainer)
    mini:SetHeight(CONTROL_HEIGHT)

    -- Border
    local border = {}

    local bTop = mini:CreateTexture(nil, "BORDER", nil, -1)
    bTop:SetPoint("TOPLEFT", mini, "TOPLEFT", 0, 0)
    bTop:SetPoint("TOPRIGHT", mini, "TOPRIGHT", 0, 0)
    bTop:SetHeight(1)
    bTop:SetColorTexture(ar, ag, ab, BORDER_ALPHA)
    border.TOP = bTop

    local bBottom = mini:CreateTexture(nil, "BORDER", nil, -1)
    bBottom:SetPoint("BOTTOMLEFT", mini, "BOTTOMLEFT", 0, 0)
    bBottom:SetPoint("BOTTOMRIGHT", mini, "BOTTOMRIGHT", 0, 0)
    bBottom:SetHeight(1)
    bBottom:SetColorTexture(ar, ag, ab, BORDER_ALPHA)
    border.BOTTOM = bBottom

    local bLeft = mini:CreateTexture(nil, "BORDER", nil, -1)
    bLeft:SetPoint("TOPLEFT", mini, "TOPLEFT", 0, -1)
    bLeft:SetPoint("BOTTOMLEFT", mini, "BOTTOMLEFT", 0, 1)
    bLeft:SetWidth(1)
    bLeft:SetColorTexture(ar, ag, ab, BORDER_ALPHA)
    border.LEFT = bLeft

    local bRight = mini:CreateTexture(nil, "BORDER", nil, -1)
    bRight:SetPoint("TOPRIGHT", mini, "TOPRIGHT", 0, -1)
    bRight:SetPoint("BOTTOMRIGHT", mini, "BOTTOMRIGHT", 0, 1)
    bRight:SetWidth(1)
    bRight:SetColorTexture(ar, ag, ab, BORDER_ALPHA)
    border.RIGHT = bRight

    mini._border = border

    -- Background
    local bg = mini:CreateTexture(nil, "BACKGROUND", nil, -7)
    bg:SetPoint("TOPLEFT", 1, -1)
    bg:SetPoint("BOTTOMRIGHT", -1, 1)
    bg:SetColorTexture(bgR, bgG, bgB, bgA)
    mini._bg = bg

    -- Left arrow button
    local leftArrow = CreateFrame("Button", nil, mini)
    leftArrow:SetSize(ARROW_WIDTH, CONTROL_HEIGHT - 2)
    leftArrow:SetPoint("LEFT", mini, "LEFT", 1, 0)
    leftArrow:EnableMouse(true)
    leftArrow:RegisterForClicks("AnyUp")

    local leftArrowBg = leftArrow:CreateTexture(nil, "BACKGROUND", nil, -6)
    leftArrowBg:SetAllPoints()
    leftArrowBg:SetColorTexture(ar, ag, ab, 0)
    leftArrow._bg = leftArrowBg

    local arrowFont = theme:GetFont("BUTTON")
    local leftArrowText = leftArrow:CreateFontString(nil, "OVERLAY")
    leftArrowText:SetFont(arrowFont, 14, "")
    leftArrowText:SetPoint("CENTER", 0, 0)
    leftArrowText:SetText("\226\151\128")  -- ◀
    leftArrowText:SetTextColor(ar, ag, ab, 1)
    leftArrow._text = leftArrowText

    -- Separator after left arrow
    local leftSep = mini:CreateTexture(nil, "BORDER", nil, 0)
    leftSep:SetPoint("TOPLEFT", leftArrow, "TOPRIGHT", 0, 0)
    leftSep:SetPoint("BOTTOMLEFT", leftArrow, "BOTTOMRIGHT", 0, 0)
    leftSep:SetWidth(1)
    leftSep:SetColorTexture(ar, ag, ab, 0.4)
    mini._leftSep = leftSep

    -- Right arrow button
    local rightArrow = CreateFrame("Button", nil, mini)
    rightArrow:SetSize(ARROW_WIDTH, CONTROL_HEIGHT - 2)
    rightArrow:SetPoint("RIGHT", mini, "RIGHT", -1, 0)
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

    -- Separator before right arrow
    local rightSep = mini:CreateTexture(nil, "BORDER", nil, 0)
    rightSep:SetPoint("TOPRIGHT", rightArrow, "TOPLEFT", 0, 0)
    rightSep:SetPoint("BOTTOMRIGHT", rightArrow, "BOTTOMLEFT", 0, 0)
    rightSep:SetWidth(1)
    rightSep:SetColorTexture(ar, ag, ab, 0.4)
    mini._rightSep = rightSep

    -- Value display (center, clickable for dropdown)
    local valueBtn = CreateFrame("Button", nil, mini)
    valueBtn:SetPoint("LEFT", leftArrow, "RIGHT", 1, 0)
    valueBtn:SetPoint("RIGHT", rightArrow, "LEFT", -1, 0)
    valueBtn:SetHeight(CONTROL_HEIGHT - 2)
    valueBtn:EnableMouse(true)
    valueBtn:RegisterForClicks("AnyUp")

    local valueBg = valueBtn:CreateTexture(nil, "BACKGROUND", nil, -6)
    valueBg:SetAllPoints()
    valueBg:SetColorTexture(ar, ag, ab, 0)
    valueBtn._bg = valueBg

    local valueFont = theme:GetFont("VALUE")
    local valueText = valueBtn:CreateFontString(nil, "OVERLAY")
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

    mini._leftArrow = leftArrow
    mini._rightArrow = rightArrow
    mini._valueBtn = valueBtn

    -- Color swatch (inside value area, visible when customValue is selected)
    local swatch = CreateFrame("Button", nil, valueBtn)
    swatch:SetSize(SWATCH_WIDTH, SWATCH_HEIGHT)
    swatch:SetPoint("LEFT", valueBtn, "LEFT", 6, 0)
    swatch:EnableMouse(true)
    swatch:RegisterForClicks("AnyUp")
    swatch:Hide()

    -- Swatch border
    local swatchBorder = {}

    local sTop = swatch:CreateTexture(nil, "BORDER", nil, 1)
    sTop:SetPoint("TOPLEFT", swatch, "TOPLEFT", 0, 0)
    sTop:SetPoint("TOPRIGHT", swatch, "TOPRIGHT", 0, 0)
    sTop:SetHeight(SWATCH_BORDER)
    sTop:SetColorTexture(ar, ag, ab, 1)
    swatchBorder.TOP = sTop

    local sBottom = swatch:CreateTexture(nil, "BORDER", nil, 1)
    sBottom:SetPoint("BOTTOMLEFT", swatch, "BOTTOMLEFT", 0, 0)
    sBottom:SetPoint("BOTTOMRIGHT", swatch, "BOTTOMRIGHT", 0, 0)
    sBottom:SetHeight(SWATCH_BORDER)
    sBottom:SetColorTexture(ar, ag, ab, 1)
    swatchBorder.BOTTOM = sBottom

    local sLeft = swatch:CreateTexture(nil, "BORDER", nil, 1)
    sLeft:SetPoint("TOPLEFT", swatch, "TOPLEFT", 0, -SWATCH_BORDER)
    sLeft:SetPoint("BOTTOMLEFT", swatch, "BOTTOMLEFT", 0, SWATCH_BORDER)
    sLeft:SetWidth(SWATCH_BORDER)
    sLeft:SetColorTexture(ar, ag, ab, 1)
    swatchBorder.LEFT = sLeft

    local sRight = swatch:CreateTexture(nil, "BORDER", nil, 1)
    sRight:SetPoint("TOPRIGHT", swatch, "TOPRIGHT", 0, -SWATCH_BORDER)
    sRight:SetPoint("BOTTOMRIGHT", swatch, "BOTTOMRIGHT", 0, SWATCH_BORDER)
    sRight:SetWidth(SWATCH_BORDER)
    sRight:SetColorTexture(ar, ag, ab, 1)
    swatchBorder.RIGHT = sRight

    swatch._border = swatchBorder

    -- Swatch background (checkerboard for alpha)
    local checkerBg = swatch:CreateTexture(nil, "BACKGROUND", nil, 0)
    checkerBg:SetPoint("TOPLEFT", SWATCH_BORDER, -SWATCH_BORDER)
    checkerBg:SetPoint("BOTTOMRIGHT", -SWATCH_BORDER, SWATCH_BORDER)
    checkerBg:SetColorTexture(0.3, 0.3, 0.3, 1)
    swatch._checkerBg = checkerBg

    -- Color fill
    local colorFill = swatch:CreateTexture(nil, "ARTWORK", nil, 1)
    colorFill:SetPoint("TOPLEFT", SWATCH_BORDER, -SWATCH_BORDER)
    colorFill:SetPoint("BOTTOMRIGHT", -SWATCH_BORDER, SWATCH_BORDER)
    swatch._colorFill = colorFill

    mini._swatch = swatch

    -- State tracking
    mini._currentKey = nil
    mini._keyList = keyList
    mini._values = values
    mini._customValue = customValue
    mini._syncLocked = false

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
    mini._updateSwatchColor = UpdateSwatchColor

    -- Find index of key in keyList
    local function getKeyIndex(key)
        for i, k in ipairs(mini._keyList) do
            if k == key then
                return i
            end
        end
        return 1
    end

    -- Update visual display
    local function UpdateDisplay()
        local currentKey = mini._currentKey
        local displayText = mini._values[currentKey] or currentKey or "\226\128\148"  -- —

        -- Check if custom value is selected
        local isCustom
        if type(mini._customValue) == "table" then
            isCustom = false
            for _, val in ipairs(mini._customValue) do
                if currentKey == val then isCustom = true; break end
            end
        else
            isCustom = (currentKey == mini._customValue)
        end

        if isCustom then
            swatch:Show()
            UpdateSwatchColor()
            valueText:ClearAllPoints()
            valueText:SetPoint("LEFT", swatch, "RIGHT", 4, 0)
            valueText:SetPoint("RIGHT", valueBtn, "RIGHT", -16, 0)
            valueText:SetJustifyH("LEFT")
        else
            swatch:Hide()
            valueText:ClearAllPoints()
            valueText:SetPoint("CENTER", -6, 0)
            valueText:SetJustifyH("CENTER")
        end

        valueText:SetText(displayText)
    end
    mini._updateDisplay = UpdateDisplay

    -- Initialize from getter
    mini._currentKey = getValue()
    UpdateDisplay()

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

    -- Swatch hover handlers
    swatch:SetScript("OnEnter", function(self)
        local r, g, b = theme:GetAccentColor()
        for _, tex in pairs(self._border) do
            tex:SetColorTexture(r, g, b, 1)
        end
    end)
    swatch:SetScript("OnLeave", function(self)
        local r, g, b = theme:GetAccentColor()
        for _, tex in pairs(self._border) do
            tex:SetColorTexture(r, g, b, 0.8)
        end
    end)

    -- Swatch click opens color picker
    swatch:SetScript("OnClick", function()
        if mini._isDisabled then return end
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
        if mini._isDisabled or mini._syncLocked then return end
        local kList = mini._keyList
        if #kList == 0 then return end
        local idx = getKeyIndex(mini._currentKey)
        idx = idx - 1
        if idx < 1 then idx = #kList end
        mini._currentKey = kList[idx]
        setValue(mini._currentKey)
        UpdateDisplay()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    end)

    -- Right arrow click (next)
    rightArrow:SetScript("OnClick", function(btn)
        if mini._isDisabled or mini._syncLocked then return end
        local kList = mini._keyList
        if #kList == 0 then return end
        local idx = getKeyIndex(mini._currentKey)
        idx = idx + 1
        if idx > #kList then idx = 1 end
        mini._currentKey = kList[idx]
        setValue(mini._currentKey)
        UpdateDisplay()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    end)

    -- Dropdown menu frame
    local dropdown = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    dropdown:SetFrameStrata("FULLSCREEN_DIALOG")
    dropdown:SetFrameLevel(100)
    dropdown:SetClampedToScreen(true)
    dropdown:Hide()
    mini._dropdown = dropdown

    dropdown:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    local ddBgR, ddBgG, ddBgB = theme:GetBackgroundSolidColor()
    dropdown:SetBackdropColor(ddBgR, ddBgG, ddBgB, 0.98)
    dropdown:SetBackdropBorderColor(ar, ag, ab, 0.8)

    dropdown._optionButtons = {}

    local function CloseDropdown()
        dropdown:Hide()
        if dropdown._closeListener then
            dropdown._closeListener:Hide()
        end
    end
    mini._closeDropdown = CloseDropdown

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

    -- ESC key handling
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

        local kList = mini._keyList
        local vMap = mini._values
        local optionHeight = 26
        local optionPadding = 4
        local totalHeight = (#kList * optionHeight) + (optionPadding * 2)

        local dropdownWidth = mini:GetWidth()
        if dropdownWidth < 60 then dropdownWidth = 150 end

        dropdown:SetSize(dropdownWidth, totalHeight)

        -- Check if there's room below
        local selectorBottom = select(2, mini:GetCenter()) - (mini:GetHeight() / 2)
        local scale = UIParent:GetEffectiveScale()
        local spaceBelow = selectorBottom * scale

        if spaceBelow > totalHeight + 10 then
            dropdown:SetPoint("TOPLEFT", mini, "BOTTOMLEFT", 0, -2)
        else
            dropdown:SetPoint("BOTTOMLEFT", mini, "TOPLEFT", 0, 2)
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

        local accentR, accentG, accentB = theme:GetAccentColor()

        -- Determine text offset based on whether any info icons exist
        local hasAnyInfoIcons = optionInfoIcons and next(optionInfoIcons)
        local textLeftOffset = hasAnyInfoIcons and 28 or 12

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

            -- Add info icon if configured
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

            local isSelected = (key == mini._currentKey)
            if isSelected then
                optBg:SetColorTexture(accentR, accentG, accentB, 0.3)
                optText:SetTextColor(accentR, accentG, accentB, 1)
            else
                optText:SetTextColor(1, 1, 1, 1)
            end

            optBtn:SetScript("OnEnter", function(btn)
                if btn._key ~= mini._currentKey then
                    btn._bg:SetColorTexture(accentR, accentG, accentB, 0.15)
                else
                    btn._bg:SetColorTexture(accentR, accentG, accentB, 0.35)
                end
            end)
            optBtn:SetScript("OnLeave", function(btn)
                if btn._key == mini._currentKey then
                    btn._bg:SetColorTexture(accentR, accentG, accentB, 0.3)
                else
                    btn._bg:SetColorTexture(0, 0, 0, 0)
                end
            end)

            optBtn:SetScript("OnClick", function(btn)
                mini._currentKey = btn._key
                setValue(mini._currentKey)
                UpdateDisplay()
                CloseDropdown()
                PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
            end)

            table.insert(dropdown._optionButtons, optBtn)
        end

        closeListener:Show()
        closeListener:SetFrameLevel(dropdown:GetFrameLevel() - 1)

        dropdown:Show()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPEN)
    end
    mini._showDropdown = ShowDropdown

    -- Value button click (show dropdown)
    valueBtn:SetScript("OnClick", function(btn, mouseButton)
        if mini._isDisabled or mini._syncLocked then return end
        if dropdown:IsShown() then
            CloseDropdown()
        else
            ShowDropdown()
        end
    end)

    return mini
end

--------------------------------------------------------------------------------
-- DualBarStyleRow: Texture + Color in a single row
--------------------------------------------------------------------------------

function Controls:CreateDualBarStyleRow(options)
    local theme = GetTheme()
    if not options or not options.parent then
        return nil
    end

    local parent = options.parent
    local label = options.label
    local description = options.description
    local name = options.name
    local isDisabledFn = options.disabled or options.isDisabled
    local useLightDim = options.useLightDim

    local hasLabel = label and label ~= ""
    local hasDesc = description and description ~= ""
    local rowHeight = hasDesc and ROW_HEIGHT_WITH_DESC or ROW_HEIGHT

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
        labelFS:SetPoint("LEFT", row, "LEFT", PADDING, hasDesc and 6 or 0)
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
        descFS:SetPoint("RIGHT", row, "RIGHT", -PADDING, 0)
        descFS:SetText(description)
        descFS:SetTextColor(dimR, dimG, dimB, 1)
        descFS:SetJustifyH("LEFT")
        descFS:SetWordWrap(true)
        row._description = descFS
    end

    -- Dual container (right side) — tall enough for mini-label + control
    local dualContainerHeight = MINI_LABEL_HEIGHT + MINI_LABEL_GAP + CONTROL_HEIGHT
    local dualContainer = CreateFrame("Frame", nil, row)
    dualContainer:SetSize(DEFAULT_CONTAINER_WIDTH, dualContainerHeight)
    dualContainer:SetPoint("RIGHT", row, "RIGHT", -PADDING, 0)
    row._dualContainer = dualContainer

    -- Mini-labels above each selector
    local miniLabelFont = theme:GetFont("VALUE")

    local textureLabelFS = dualContainer:CreateFontString(nil, "OVERLAY")
    textureLabelFS:SetFont(miniLabelFont, 11, "")
    textureLabelFS:SetPoint("TOPLEFT", dualContainer, "TOPLEFT", 2, 0)
    textureLabelFS:SetText("Texture")
    textureLabelFS:SetTextColor(dimR, dimG, dimB, 0.8)
    row._textureLabelFS = textureLabelFS

    local colorLabelFS = dualContainer:CreateFontString(nil, "OVERLAY")
    colorLabelFS:SetFont(miniLabelFont, 11, "")
    colorLabelFS:SetText("Color")
    colorLabelFS:SetTextColor(dimR, dimG, dimB, 0.8)
    row._colorLabelFS = colorLabelFS
    -- colorLabelFS position is set after textureMini is created (needs anchor)

    -- Create texture mini (left within container, below label)
    local textureMini = CreateTextureMini({
        getTexture = options.getTexture,
        setTexture = options.setTexture,
    }, dualContainer, theme, useLightDim)
    textureMini:SetPoint("TOPLEFT", dualContainer, "TOPLEFT", 0, -(MINI_LABEL_HEIGHT + MINI_LABEL_GAP))
    -- Set initial width so text is visible before deferred measurement
    local initTextureW = (DEFAULT_CONTAINER_WIDTH - GAP) * TEXTURE_WIDTH_PCT
    textureMini:SetWidth(initTextureW)
    row._textureMini = textureMini

    -- Position color label above the color mini area
    colorLabelFS:SetPoint("TOPLEFT", textureMini, "TOPRIGHT", GAP + 2, MINI_LABEL_HEIGHT + MINI_LABEL_GAP)

    -- Create color mini (right of texture with gap, below label)
    local colorMini = CreateColorMini({
        colorValues = options.colorValues,
        colorOrder = options.colorOrder,
        colorInfoIcons = options.colorInfoIcons,
        getColorMode = options.getColorMode,
        setColorMode = options.setColorMode,
        getColor = options.getColor,
        setColor = options.setColor,
        customColorValue = options.customColorValue or "custom",
        hasAlpha = options.hasAlpha,
    }, dualContainer, theme, useLightDim)
    colorMini:SetPoint("LEFT", textureMini, "RIGHT", GAP, 0)
    -- Set initial width so text is visible before deferred measurement
    local initColorW = (DEFAULT_CONTAINER_WIDTH - GAP) * COLOR_WIDTH_PCT
    colorMini:SetWidth(initColorW)
    row._colorMini = colorMini

    -- Cross-wire: opening one closes the other
    local origColorShow = colorMini._showDropdown
    colorMini._showDropdown = function()
        addon.CloseBarTexturePicker()
        origColorShow()
    end

    -- Re-wire color value button click to use cross-wired show
    colorMini._valueBtn:SetScript("OnClick", function(btn, mouseButton)
        if colorMini._isDisabled or colorMini._syncLocked then return end
        if colorMini._dropdown:IsShown() then
            colorMini._closeDropdown()
        else
            colorMini._showDropdown()
        end
    end)

    -- Texture mini already closes its own picker via ShowBarTexturePicker;
    -- also close color dropdown when texture is clicked
    local origTextureClick = textureMini._valueBtn:GetScript("OnClick")
    textureMini._valueBtn:SetScript("OnClick", function(self)
        colorMini._closeDropdown()
        if origTextureClick then
            origTextureClick(self)
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
            labelWidth = labelFS:GetStringWidth() + LABEL_RIGHT_MARGIN
        end
        local containerWidth = rowWidth - labelWidth - (PADDING * 2)
        if containerWidth < 100 then containerWidth = DEFAULT_CONTAINER_WIDTH end
        if containerWidth > MAX_CONTAINER_WIDTH then containerWidth = MAX_CONTAINER_WIDTH end

        dualContainer:SetWidth(containerWidth)

        -- Split: texture 38%, color 62%
        local textureWidth = (containerWidth - GAP) * TEXTURE_WIDTH_PCT
        local colorWidth = (containerWidth - GAP) * COLOR_WIDTH_PCT
        textureMini:SetWidth(textureWidth)
        colorMini:SetWidth(colorWidth)

        -- Re-trigger display updates now that frames have proper width
        if textureMini._updateDisplay then textureMini._updateDisplay() end
        if colorMini._updateDisplay then colorMini._updateDisplay() end
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
    local subscribeKey = "DualBarStyleRow_" .. (name or tostring(row))
    row._subscribeKey = subscribeKey

    theme:Subscribe(subscribeKey, function(r, g, b)
        -- Update label
        if row._label and not row._isDisabled then
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
        -- Update mini-labels
        local dr, dg, db = theme:GetDimTextColor()
        if row._textureLabelFS then
            row._textureLabelFS:SetTextColor(dr, dg, db, 0.8)
        end
        if row._colorLabelFS then
            row._colorLabelFS:SetTextColor(dr, dg, db, 0.8)
        end

        -- Update texture mini
        local tMini = row._textureMini
        if tMini then
            if tMini._border then
                for _, tex in pairs(tMini._border) do
                    tex:SetColorTexture(r, g, b, BORDER_ALPHA)
                end
            end
            if tMini._valueBtn and tMini._valueBtn._dropArrow then
                local dr, dg, db = theme:GetDimTextColor()
                tMini._valueBtn._dropArrow:SetTextColor(dr, dg, db, 0.7)
            end
        end

        -- Update color mini
        local cMini = row._colorMini
        if cMini then
            if cMini._border then
                for _, tex in pairs(cMini._border) do
                    tex:SetColorTexture(r, g, b, BORDER_ALPHA)
                end
            end
            if cMini._leftSep then
                cMini._leftSep:SetColorTexture(r, g, b, 0.4)
            end
            if cMini._rightSep then
                cMini._rightSep:SetColorTexture(r, g, b, 0.4)
            end
            if not cMini._syncLocked then
                if cMini._leftArrow and cMini._leftArrow._text then
                    cMini._leftArrow._text:SetTextColor(r, g, b, 1)
                end
                if cMini._rightArrow and cMini._rightArrow._text then
                    cMini._rightArrow._text:SetTextColor(r, g, b, 1)
                end
            end
            if cMini._dropdown and cMini._dropdown.SetBackdropBorderColor then
                cMini._dropdown:SetBackdropBorderColor(r, g, b, 0.8)
            end
            -- Update swatch border
            if cMini._swatch and cMini._swatch:IsShown() and cMini._swatch._border then
                for _, tex in pairs(cMini._swatch._border) do
                    tex:SetColorTexture(r, g, b, 0.8)
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

    function row:Refresh()
        -- Refresh texture
        local tMini = self._textureMini
        if tMini then
            tMini._currentValue = tMini._getTexture() or "default"
            tMini._updateDisplay()
        end
        -- Refresh color
        local cMini = self._colorMini
        if cMini then
            local getMode = options.getColorMode or function() return nil end
            cMini._currentKey = getMode()
            cMini._updateDisplay()
            cMini._updateSwatchColor()
        end
        -- Check disabled state
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

        -- Propagate to minis
        if self._textureMini then
            self._textureMini._isDisabled = self._isDisabled
        end
        if self._colorMini then
            self._colorMini._isDisabled = self._isDisabled
        end

        if self._isDisabled then
            if self._label then self._label:SetTextColor(dR, dG, dB, disabledAlpha) end
            if self._description then self._description:SetAlpha(disabledAlpha) end
            if self._dualContainer then self._dualContainer:SetAlpha(disabledAlpha) end
        else
            if self._label then self._label:SetTextColor(acR, acG, acB, 1) end
            if self._description then self._description:SetAlpha(1) end
            if self._dualContainer then self._dualContainer:SetAlpha(1) end
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

    function row:Cleanup()
        if self._subscribeKey then
            theme:Unsubscribe(self._subscribeKey)
        end
        -- Clean up color mini
        local cMini = self._colorMini
        if cMini then
            if cMini._closeDropdown then
                cMini._closeDropdown()
            end
            if cMini._dropdown then
                if cMini._dropdown._closeListener then
                    cMini._dropdown._closeListener:Hide()
                    cMini._dropdown._closeListener:SetParent(nil)
                end
                if cMini._dropdown._optionButtons then
                    for _, btn in ipairs(cMini._dropdown._optionButtons) do
                        if btn._infoIcon then
                            btn._infoIcon:Cleanup()
                        end
                        btn:Hide()
                        btn:SetParent(nil)
                    end
                end
                cMini._dropdown:Hide()
                cMini._dropdown:SetParent(nil)
            end
        end
    end

    function row:GetDescriptionFontString()
        return self._description
    end

    return row
end
