-- Dropdown.lua - Standalone compact dropdown control for header bars
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

local DROPDOWN_DEFAULT_WIDTH = 150
local DROPDOWN_DEFAULT_HEIGHT = 22
local DROPDOWN_BORDER_ALPHA = 0.6
local DROPDOWN_PADDING = 8

--------------------------------------------------------------------------------
-- Dropdown: Standalone compact dropdown control
--------------------------------------------------------------------------------
-- Creates a compact dropdown control suitable for header bars:
--   - No label or description (inline use)
--   - Clickable box with current value and dropdown indicator
--   - Dropdown menu with same styling as Selector
--   - Placeholder text when no value is selected
--
-- Options table:
--   values      : Table of { key = "Display Text" } pairs
--   order       : Optional array of keys for display order (otherwise alphabetical)
--   get         : Function returning current key (or nil for placeholder)
--   set         : Function(newKey) to save value
--   placeholder : Text to show when no value selected (default "Select...")
--   parent      : Parent frame (required)
--   width       : Dropdown width (optional, default 150)
--   height      : Dropdown height (optional, default 22)
--   name        : Global frame name (optional)
--------------------------------------------------------------------------------

function Controls:CreateDropdown(options)
    local theme = GetTheme()
    if not options or not options.parent then
        return nil
    end

    local parent = options.parent
    local values = options.values or {}
    local orderKeys = options.order
    local getValue = options.get or function() return nil end
    local setValue = options.set or function() end
    local placeholder = options.placeholder or "Select..."
    local dropdownWidth = options.width or DROPDOWN_DEFAULT_WIDTH
    local dropdownHeight = options.height or DROPDOWN_DEFAULT_HEIGHT
    local name = options.name

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
    local dimR, dimG, dimB = theme:GetDimTextColor()
    local bgR, bgG, bgB, bgA = theme:GetBackgroundSolidColor()

    -- Create the dropdown button frame
    local dropdown = CreateFrame("Button", name, parent)
    dropdown:SetSize(dropdownWidth, dropdownHeight)
    dropdown:EnableMouse(true)
    dropdown:RegisterForClicks("AnyUp")

    -- Dropdown border
    local border = {}

    local bTop = dropdown:CreateTexture(nil, "BORDER", nil, -1)
    bTop:SetPoint("TOPLEFT", dropdown, "TOPLEFT", 0, 0)
    bTop:SetPoint("TOPRIGHT", dropdown, "TOPRIGHT", 0, 0)
    bTop:SetHeight(1)
    bTop:SetColorTexture(ar, ag, ab, DROPDOWN_BORDER_ALPHA)
    border.TOP = bTop

    local bBottom = dropdown:CreateTexture(nil, "BORDER", nil, -1)
    bBottom:SetPoint("BOTTOMLEFT", dropdown, "BOTTOMLEFT", 0, 0)
    bBottom:SetPoint("BOTTOMRIGHT", dropdown, "BOTTOMRIGHT", 0, 0)
    bBottom:SetHeight(1)
    bBottom:SetColorTexture(ar, ag, ab, DROPDOWN_BORDER_ALPHA)
    border.BOTTOM = bBottom

    local bLeft = dropdown:CreateTexture(nil, "BORDER", nil, -1)
    bLeft:SetPoint("TOPLEFT", dropdown, "TOPLEFT", 0, -1)
    bLeft:SetPoint("BOTTOMLEFT", dropdown, "BOTTOMLEFT", 0, 1)
    bLeft:SetWidth(1)
    bLeft:SetColorTexture(ar, ag, ab, DROPDOWN_BORDER_ALPHA)
    border.LEFT = bLeft

    local bRight = dropdown:CreateTexture(nil, "BORDER", nil, -1)
    bRight:SetPoint("TOPRIGHT", dropdown, "TOPRIGHT", 0, -1)
    bRight:SetPoint("BOTTOMRIGHT", dropdown, "BOTTOMRIGHT", 0, 1)
    bRight:SetWidth(1)
    bRight:SetColorTexture(ar, ag, ab, DROPDOWN_BORDER_ALPHA)
    border.RIGHT = bRight

    dropdown._border = border

    -- Dropdown background
    local bg = dropdown:CreateTexture(nil, "BACKGROUND", nil, -7)
    bg:SetPoint("TOPLEFT", 1, -1)
    bg:SetPoint("BOTTOMRIGHT", -1, 1)
    bg:SetColorTexture(bgR, bgG, bgB, bgA)
    dropdown._bg = bg

    -- Hover background
    local hoverBg = dropdown:CreateTexture(nil, "BACKGROUND", nil, -6)
    hoverBg:SetPoint("TOPLEFT", 1, -1)
    hoverBg:SetPoint("BOTTOMRIGHT", -1, 1)
    hoverBg:SetColorTexture(ar, ag, ab, 0)
    dropdown._hoverBg = hoverBg

    -- Value text
    local valueText = dropdown:CreateFontString(nil, "OVERLAY")
    local valueFont = theme:GetFont("VALUE")
    valueText:SetFont(valueFont, 11, "")
    valueText:SetPoint("LEFT", dropdown, "LEFT", DROPDOWN_PADDING, 0)
    valueText:SetPoint("RIGHT", dropdown, "RIGHT", -DROPDOWN_PADDING - 12, 0)
    valueText:SetJustifyH("LEFT")
    valueText:SetTextColor(1, 1, 1, 1)
    dropdown._valueText = valueText

    -- Dropdown indicator arrow
    local dropIndicator = dropdown:CreateFontString(nil, "OVERLAY")
    dropIndicator:SetFont(valueFont, 9, "")
    dropIndicator:SetPoint("RIGHT", dropdown, "RIGHT", -DROPDOWN_PADDING, 0)
    dropIndicator:SetText("\226\150\188")
    dropIndicator:SetTextColor(dimR, dimG, dimB, 0.7)
    dropdown._dropIndicator = dropIndicator

    -- State tracking
    dropdown._currentKey = nil
    dropdown._keyList = keyList
    dropdown._values = values
    dropdown._placeholder = placeholder

    -- Update visual display
    local function UpdateDisplay()
        local currentKey = dropdown._currentKey
        if currentKey and dropdown._values[currentKey] then
            valueText:SetText(dropdown._values[currentKey])
            valueText:SetTextColor(1, 1, 1, 1)
        else
            valueText:SetText(dropdown._placeholder)
            valueText:SetTextColor(dimR, dimG, dimB, 0.7)
        end
    end
    dropdown._updateDisplay = UpdateDisplay

    -- Initialize from getter
    dropdown._currentKey = getValue()
    UpdateDisplay()

    -- Hover effects
    dropdown:SetScript("OnEnter", function(self)
        local r, g, b = theme:GetAccentColor()
        self._hoverBg:SetColorTexture(r, g, b, 0.15)
        self._dropIndicator:SetTextColor(r, g, b, 1)
        -- Brighten border on hover
        for _, tex in pairs(self._border) do
            tex:SetColorTexture(r, g, b, 0.9)
        end
    end)
    dropdown:SetScript("OnLeave", function(self)
        local r, g, b = theme:GetAccentColor()
        local dr, dg, db = theme:GetDimTextColor()
        self._hoverBg:SetColorTexture(r, g, b, 0)
        self._dropIndicator:SetTextColor(dr, dg, db, 0.7)
        for _, tex in pairs(self._border) do
            tex:SetColorTexture(r, g, b, DROPDOWN_BORDER_ALPHA)
        end
    end)

    -- Dropdown menu frame (created once, reused)
    local menu = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu:SetFrameLevel(100)
    menu:SetClampedToScreen(true)
    menu:Hide()
    dropdown._menu = menu

    -- Menu backdrop/border
    menu:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    local menuBgR, menuBgG, menuBgB = theme:GetBackgroundSolidColor()
    menu:SetBackdropColor(menuBgR, menuBgG, menuBgB, 0.98)
    menu:SetBackdropBorderColor(ar, ag, ab, 0.8)

    -- Track menu option buttons
    menu._optionButtons = {}

    -- Close menu function
    local function CloseMenu()
        menu:Hide()
        if menu._closeListener then
            menu._closeListener:Hide()
        end
    end
    dropdown._closeMenu = CloseMenu

    -- Invisible fullscreen listener to close menu on outside click
    local closeListener = CreateFrame("Button", nil, UIParent)
    closeListener:SetFrameStrata("FULLSCREEN")
    closeListener:SetFrameLevel(99)
    closeListener:SetAllPoints(UIParent)
    closeListener:EnableMouse(true)
    closeListener:RegisterForClicks("AnyUp", "AnyDown")
    closeListener:SetScript("OnClick", function()
        CloseMenu()
    end)
    closeListener:Hide()
    menu._closeListener = closeListener

    -- ESC key handling for menu
    addon.EscapeKey.Attach(menu, function()
        CloseMenu()
        PlaySound(SOUNDKIT.IG_MAINMENU_CLOSE)
    end)

    -- Build and show menu
    local function ShowMenu()
        menu:ClearAllPoints()

        local kList = dropdown._keyList
        local vMap = dropdown._values
        local optionHeight = 24
        local optionPadding = 4
        local totalHeight = (#kList * optionHeight) + (optionPadding * 2)
        local menuWidth = dropdownWidth

        menu:SetSize(menuWidth, totalHeight)

        -- Check if there's room below
        local dropdownBottom = select(2, dropdown:GetCenter()) - (dropdown:GetHeight() / 2)
        local screenHeight = GetScreenHeight()
        local scale = UIParent:GetEffectiveScale()
        local spaceBelow = dropdownBottom * scale

        if spaceBelow > totalHeight + 10 then
            menu:SetPoint("TOPLEFT", dropdown, "BOTTOMLEFT", 0, -2)
        else
            menu:SetPoint("BOTTOMLEFT", dropdown, "TOPLEFT", 0, 2)
        end

        -- Clear existing option buttons
        for _, btn in ipairs(menu._optionButtons) do
            btn:Hide()
            btn:SetParent(nil)
        end
        wipe(menu._optionButtons)

        -- Get current accent color
        local accentR, accentG, accentB = theme:GetAccentColor()

        -- Create option buttons
        for i, key in ipairs(kList) do
            local optBtn = CreateFrame("Button", nil, menu)
            optBtn:SetSize(menuWidth - 2, optionHeight)
            optBtn:SetPoint("TOPLEFT", menu, "TOPLEFT", 1, -optionPadding - ((i - 1) * optionHeight))
            optBtn:EnableMouse(true)
            optBtn:RegisterForClicks("AnyUp")

            local optBg = optBtn:CreateTexture(nil, "BACKGROUND", nil, -6)
            optBg:SetAllPoints()
            optBg:SetColorTexture(0, 0, 0, 0)
            optBtn._bg = optBg

            local optText = optBtn:CreateFontString(nil, "OVERLAY")
            local optFont = theme:GetFont("VALUE")
            optText:SetFont(optFont, 11, "")
            optText:SetPoint("LEFT", optBtn, "LEFT", 10, 0)
            optText:SetPoint("RIGHT", optBtn, "RIGHT", -10, 0)
            optText:SetJustifyH("LEFT")
            optText:SetText(vMap[key] or key)
            optBtn._text = optText
            optBtn._key = key

            local isSelected = (key == dropdown._currentKey)
            if isSelected then
                optBg:SetColorTexture(accentR, accentG, accentB, 0.3)
                optText:SetTextColor(accentR, accentG, accentB, 1)
            else
                optText:SetTextColor(1, 1, 1, 1)
            end

            optBtn:SetScript("OnEnter", function(btn)
                if btn._key ~= dropdown._currentKey then
                    btn._bg:SetColorTexture(accentR, accentG, accentB, 0.15)
                else
                    btn._bg:SetColorTexture(accentR, accentG, accentB, 0.35)
                end
            end)
            optBtn:SetScript("OnLeave", function(btn)
                if btn._key == dropdown._currentKey then
                    btn._bg:SetColorTexture(accentR, accentG, accentB, 0.3)
                else
                    btn._bg:SetColorTexture(0, 0, 0, 0)
                end
            end)

            optBtn:SetScript("OnClick", function(btn)
                dropdown._currentKey = btn._key
                setValue(dropdown._currentKey)
                UpdateDisplay()
                CloseMenu()
                PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
            end)

            table.insert(menu._optionButtons, optBtn)
        end

        closeListener:Show()
        closeListener:SetFrameLevel(menu:GetFrameLevel() - 1)

        menu:Show()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPEN)
    end

    -- Click to toggle menu
    dropdown:SetScript("OnClick", function(self, mouseButton)
        if menu:IsShown() then
            CloseMenu()
        else
            ShowMenu()
        end
    end)

    -- Theme subscription
    local subscribeKey = "Dropdown_" .. (name or tostring(dropdown))
    dropdown._subscribeKey = subscribeKey

    theme:Subscribe(subscribeKey, function(r, g, b)
        -- Update border
        if dropdown._border then
            local alpha = dropdown:IsMouseOver() and 0.9 or DROPDOWN_BORDER_ALPHA
            for _, tex in pairs(dropdown._border) do
                tex:SetColorTexture(r, g, b, alpha)
            end
        end
        -- Update menu border color
        if menu and menu.SetBackdropBorderColor then
            menu:SetBackdropBorderColor(r, g, b, 0.8)
        end
    end)

    -- Public methods
    function dropdown:SetValue(newKey)
        self._currentKey = newKey
        self._updateDisplay()
    end

    function dropdown:GetValue()
        return self._currentKey
    end

    function dropdown:Refresh()
        self._currentKey = getValue()
        self._updateDisplay()
    end

    function dropdown:ClearSelection()
        self._currentKey = nil
        self._updateDisplay()
    end

    function dropdown:HasSelection()
        return self._currentKey ~= nil and self._values[self._currentKey] ~= nil
    end

    function dropdown:SetOptions(newValues, newOrder)
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

        -- If current key is not in new options, clear selection
        if self._currentKey and not newValues[self._currentKey] then
            self._currentKey = nil
        end

        self._updateDisplay()
    end

    function dropdown:SetPlaceholder(newPlaceholder)
        self._placeholder = newPlaceholder or "Select..."
        self._updateDisplay()
    end

    function dropdown:Cleanup()
        if self._subscribeKey then
            theme:Unsubscribe(self._subscribeKey)
        end
        if self._closeMenu then
            self._closeMenu()
        end
        if self._menu then
            if self._menu._closeListener then
                self._menu._closeListener:Hide()
                self._menu._closeListener:SetParent(nil)
            end
            if self._menu._optionButtons then
                for _, btn in ipairs(self._menu._optionButtons) do
                    btn:Hide()
                    btn:SetParent(nil)
                end
            end
            self._menu:Hide()
            self._menu:SetParent(nil)
        end
    end

    return dropdown
end
