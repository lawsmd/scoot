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

-- Layout numbers come from the active skin's metrics.dropdown table.
local function M()
    return Controls.Metrics()
end

--------------------------------------------------------------------------------
-- Dropdown: Standalone compact dropdown control
--------------------------------------------------------------------------------
-- Creates a compact dropdown control suitable for header bars:
--   - No label or description (inline use)
--   - Clickable box with current value and dropdown indicator
--   - Dropdown menu with same styling as Selector
--   - Placeholder text when no value is selected
--   - A stepper each side of the field where the skin names
--     metrics.dropdown.steppers = { width, gap }, as Blizzard's own options
--     dropdown has; they walk the list, past a disabled entry and around
--     the ends, inside the caller's width
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
--   disabledOptions : Optional { key = true }: the entry is listed dimmed and
--                 ignores hover and clicks
--------------------------------------------------------------------------------

function Controls:CreateDropdown(options)
    local override = Controls.SkinOverride("Dropdown", options)
    if override then return override end

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
    local dropdownWidth = options.width or M().dropdown.width
    local dropdownHeight = options.height or M().dropdown.height
    local name = options.name
    local disabledOptions = options.disabledOptions or {}
    local steppers = M().dropdown.steppers

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
    local dimR, dimG, dimB = theme:GetDimTextColor()

    -- The control's frame is the caller's width. With steppers the field
    -- is a button of its own between them and the frame takes no mouse;
    -- without, the frame is the field.
    local dropdown = CreateFrame("Button", name, parent)
    dropdown:SetSize(dropdownWidth, dropdownHeight)
    local field = dropdown
    if steppers then
        dropdown:EnableMouse(false)
        local prev = Controls.CreateArrowButton(dropdown, {
            width = steppers.width, height = dropdownHeight,
            glyph = "\226\151\128", direction = "prev", fontSize = 14,
        })
        prev:SetPoint("LEFT", dropdown, "LEFT", 0, 0)
        local nextBtn = Controls.CreateArrowButton(dropdown, {
            width = steppers.width, height = dropdownHeight,
            glyph = "\226\150\182", direction = "next", fontSize = 14,
        })
        nextBtn:SetPoint("RIGHT", dropdown, "RIGHT", 0, 0)
        field = CreateFrame("Button", nil, dropdown)
        field:SetPoint("LEFT", prev, "RIGHT", steppers.gap or 0, 0)
        field:SetPoint("RIGHT", nextBtn, "LEFT", -(steppers.gap or 0), 0)
        field:SetHeight(dropdownHeight)
        dropdown._prev, dropdown._next = prev, nextBtn
    end
    field:EnableMouse(true)
    field:RegisterForClicks("AnyUp")
    dropdown._field = field

    -- Border, fill and hover fill come from the dropdown role
    dropdown._backdrop = addon.UI.Chrome.Backdrop("dropdown", field)

    -- Value text. dropdown.fontRole is the field's own role where a skin
    -- declares one, so a font style can sit on the value a field shows
    -- without reaching every other white string; the value role otherwise.
    local valueText = field:CreateFontString(nil, "OVERLAY")
    theme:ApplyFont(valueText, M().dropdown.fontRole or "value", M().dropdown.fontSize)
    -- A skin that centers the value keeps its arrow off the right edge, so
    -- the text takes the same padding on both sides.
    local justify = addon.UI.Chrome.Spec("dropdown").justify or "LEFT"
    local arrowRoom = justify == "CENTER" and 0 or 12
    valueText:SetPoint("LEFT", field, "LEFT", M().dropdown.padding, 0)
    valueText:SetPoint("RIGHT", field, "RIGHT", -M().dropdown.padding - arrowRoom, 0)
    valueText:SetJustifyH(justify)
    valueText:SetTextColor(1, 1, 1, 1)
    dropdown._valueText = valueText

    -- Dropdown indicator arrow
    local dropIndicator = field:CreateFontString(nil, "OVERLAY")
    theme:ApplyFont(dropIndicator, "value", M().dropdown.indicatorSize)
    dropIndicator:SetPoint("RIGHT", field, "RIGHT", -M().dropdown.padding, 0)
    dropIndicator:SetText("\226\150\188")
    dropIndicator:SetTextColor(dimR, dimG, dimB, 0.7)
    dropdown._dropIndicator = Controls.AddFieldIndicator(field, dropIndicator, "dropdown")

    -- State tracking
    dropdown._currentKey = nil
    dropdown._keyList = keyList
    dropdown._values = values
    dropdown._placeholder = placeholder
    dropdown._disabledOptions = disabledOptions

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
    field:SetScript("OnEnter", function()
        local r, g, b = theme:GetAccentColor()
        dropdown._backdrop:SetHover(true)
        dropdown._dropIndicator:SetTextColor(r, g, b, 1)
    end)
    field:SetScript("OnLeave", function()
        local dr, dg, db = theme:GetDimTextColor()
        dropdown._backdrop:SetHover(false)
        dropdown._dropIndicator:SetTextColor(dr, dg, db, 0.7)
    end)

    -- Dropdown menu (one shared popup list, rebuilt on every open). With
    -- steppers the list takes the field's own width, measured at open.
    local menu = Controls.CreatePopupList({
        anchor = field,
        width = (not steppers) and dropdownWidth or nil,
        optionHeight = 24,
        fontSize = 11,
        textInset = 10,
        getKeys = function() return dropdown._keyList end,
        getValues = function() return dropdown._values end,
        getSelectedKey = function() return dropdown._currentKey end,
        isInert = function(key) return dropdown._disabledOptions[key] == true end,
        onSelect = function(key)
            dropdown._currentKey = key
            setValue(key)
            UpdateDisplay()
        end,
    })
    dropdown._menu = menu
    dropdown._closeMenu = function() menu:Close() end
    -- The role's open art follows the list, whichever path shows or hides it
    menu.frame:HookScript("OnShow", function() dropdown._backdrop:SetOpen(true) end)
    menu.frame:HookScript("OnHide", function() dropdown._backdrop:SetOpen(false) end)

    -- Click to toggle menu
    field:SetScript("OnClick", function()
        menu:Toggle()
    end)

    -- The steppers walk the list, past a disabled entry and around the
    -- ends; from the placeholder, the first step lands on an end.
    local function Step(dir)
        local list = dropdown._keyList
        if #list == 0 then return end
        local idx = 0
        for i, k in ipairs(list) do
            if k == dropdown._currentKey then idx = i break end
        end
        for _ = 1, #list do
            idx = idx + dir
            if idx < 1 then idx = #list elseif idx > #list then idx = 1 end
            if not dropdown._disabledOptions[list[idx]] then break end
        end
        local key = list[idx]
        if dropdown._disabledOptions[key] or key == dropdown._currentKey then return end
        dropdown._currentKey = key
        setValue(key)
        UpdateDisplay()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    end
    if dropdown._prev then
        dropdown._prev:SetScript("OnClick", function() Step(-1) end)
        dropdown._next:SetScript("OnClick", function() Step(1) end)
    end

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

    -- newDisabled is optional; passed, it replaces the entries' disabled set.
    function dropdown:SetOptions(newValues, newOrder, newDisabled)
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
        if newDisabled then self._disabledOptions = newDisabled end

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
        if self._menu then
            self._menu:Destroy()
        end
    end

    return dropdown
end
