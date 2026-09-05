-- ToggleColorPicker.lua - Toggle with inline color swatch (visible when ON)
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

local BORDER_WIDTH = 2
local TOGGLE_HEIGHT = 36
local TOGGLE_HEIGHT_WITH_DESC = 60
local TOGGLE_BORDER = 1
local TOGGLE_INDICATOR_WIDTH = 60
local TOGGLE_INDICATOR_HEIGHT = 22
local TOGGLE_PADDING = 12

local TOGGLE_COLOR_SWATCH_WIDTH = 42
local TOGGLE_COLOR_SWATCH_HEIGHT = 18
local TOGGLE_COLOR_SWATCH_BORDER = 2
local TOGGLE_COLOR_SWATCH_GAP = 10


-- ToggleColorPicker: Toggle with inline color swatch (visible when ON)

function Controls:CreateToggleColorPicker(options)
    local theme = GetTheme()
    if not options or not options.parent then
        return nil
    end

    local parent = options.parent
    local label = options.label or "Toggle"
    local description = options.description
    local getValue = options.get or function() return false end
    local setValue = options.set or function() end
    local getColor = options.getColor or function() return 1, 1, 1, 1 end
    local setColor = options.setColor or function() end
    local hasAlpha = options.hasAlpha ~= false  -- Default true
    local swatchWidth = options.swatchWidth or TOGGLE_COLOR_SWATCH_WIDTH
    local swatchHeight = options.swatchHeight or TOGGLE_COLOR_SWATCH_HEIGHT
    local name = options.name
    local isDisabledFn = options.disabled or options.isDisabled

    local hasDesc = description and description ~= ""
    local height = hasDesc and TOGGLE_HEIGHT_WITH_DESC or TOGGLE_HEIGHT

    -- Get theme colors
    local ar, ag, ab = theme:GetAccentColor()
    local dimR, dimG, dimB
    if options.useLightDim then
        dimR, dimG, dimB = theme:GetDimTextLightColor()
    else
        dimR, dimG, dimB = theme:GetDimTextColor()
    end

    -- Main row frame (Button for click handling)
    local row = CreateFrame("Button", name, parent)
    row:SetHeight(height)
    row:EnableMouse(true)
    row:RegisterForClicks("AnyUp")

    -- Row hover background
    row._hoverBg = Controls.AddHoverFill(row, { sublevel = Controls.SUBLEVEL_BG })

    -- Row bottom border
    row._rowBorder = Controls.CreateBorder(row, {
        sides = {"BOTTOM"},
        thickness = TOGGLE_BORDER,
        alpha = 0.2,
    })

    -- Label and description
    local labelFS = Controls.AddRowChrome(row, {
        label = label,
        padLeft = TOGGLE_PADDING,
        description = description,
        reserve = TOGGLE_INDICATOR_WIDTH + swatchWidth + TOGGLE_COLOR_SWATCH_GAP + TOGGLE_PADDING * 2 + 8,
        measureReserve = TOGGLE_INDICATOR_WIDTH + swatchWidth + TOGGLE_COLOR_SWATCH_GAP + (TOGGLE_PADDING * 2) + 8,
        dimColor = { dimR, dimG, dimB },
    })

    -- State indicator (right side)
    local indicator = CreateFrame("Frame", nil, row)
    indicator:SetSize(TOGGLE_INDICATOR_WIDTH, TOGGLE_INDICATOR_HEIGHT)
    indicator:SetPoint("RIGHT", row, "RIGHT", -TOGGLE_PADDING, 0)

    -- Indicator border. Static color: UpdateVisual owns all indicator tinting
    -- (state-dependent color and alpha).
    indicator._border = Controls.CreateBorder(indicator, {
        thickness = BORDER_WIDTH,
        color = { ar, ag, ab },
    })

    -- Indicator background (shown when ON)
    indicator._bg = Controls.AddHoverFill(indicator, { alpha = 1, inset = BORDER_WIDTH })

    -- Indicator text
    local indText = indicator:CreateFontString(nil, "OVERLAY")
    local btnFont = theme:GetFont("BUTTON")
    indText:SetFont(btnFont, 11, "")
    indText:SetPoint("CENTER", indicator, "CENTER", 0, 0)
    indText:SetText("OFF")
    indText:SetTextColor(dimR, dimG, dimB, 1)
    indicator._text = indText

    row._indicator = indicator

    -- Color swatch (between indicator and content, hidden when OFF)
    local swatch = CreateFrame("Button", nil, row)
    swatch:SetSize(swatchWidth, swatchHeight)
    swatch:SetPoint("RIGHT", indicator, "LEFT", -TOGGLE_COLOR_SWATCH_GAP, 0)
    swatch:EnableMouse(true)
    swatch:RegisterForClicks("AnyUp")
    swatch:Hide()

    -- Swatch border
    swatch._border = Controls.CreateBorder(swatch, {
        thickness = TOGGLE_COLOR_SWATCH_BORDER,
        getAlpha = function(self) return self:IsMouseOver() and 1 or 0.8 end,
    })

    -- Swatch background (checkerboard for alpha)
    local checkerBg = swatch:CreateTexture(nil, "BACKGROUND", nil, -7)
    checkerBg:SetPoint("TOPLEFT", TOGGLE_COLOR_SWATCH_BORDER, -TOGGLE_COLOR_SWATCH_BORDER)
    checkerBg:SetPoint("BOTTOMRIGHT", -TOGGLE_COLOR_SWATCH_BORDER, TOGGLE_COLOR_SWATCH_BORDER)
    checkerBg:SetColorTexture(0.3, 0.3, 0.3, 1)
    swatch._checkerBg = checkerBg

    -- Color fill
    local colorFill = swatch:CreateTexture(nil, "ARTWORK", nil, 0)
    colorFill:SetPoint("TOPLEFT", TOGGLE_COLOR_SWATCH_BORDER, -TOGGLE_COLOR_SWATCH_BORDER)
    colorFill:SetPoint("BOTTOMRIGHT", -TOGGLE_COLOR_SWATCH_BORDER, TOGGLE_COLOR_SWATCH_BORDER)
    swatch._colorFill = colorFill

    row._swatch = swatch

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

    -- State tracking
    row._value = false
    row._isDisabled = false
    row._isDisabledFn = isDisabledFn

    -- Update visual state for toggle and swatch visibility
    local function UpdateVisual()
        local isOn = row._value
        local isDisabled = row._isDisabled
        local r, g, b = theme:GetAccentColor()
        local dR, dG, dB = theme:GetDimTextColor()

        if isDisabled then
            -- Disabled state: everything grayed out
            local disabledAlpha = 0.35
            labelFS:SetTextColor(dR, dG, dB, disabledAlpha)
            if row._description then
                row._description:SetAlpha(disabledAlpha)
            end
            indicator._bg:Hide()
            indicator._text:SetText(isOn and "ON" or "OFF")
            indicator._text:SetTextColor(dR, dG, dB, disabledAlpha)
            for _, tex in pairs(indicator._border) do
                tex:SetColorTexture(dR, dG, dB, disabledAlpha * 0.5)
            end
            swatch:Hide()
        else
            -- Restore description alpha
            if row._description then
                row._description:SetAlpha(1)
            end
            -- Label always uses accent color
            labelFS:SetTextColor(r, g, b, 1)

            if isOn then
                -- ON state
                indicator._bg:Show()
                indicator._text:SetText("ON")
                indicator._text:SetTextColor(0, 0, 0, 1)
                for _, tex in pairs(indicator._border) do
                    tex:SetColorTexture(r, g, b, 1)
                end
                -- Show color swatch
                swatch:Show()
                UpdateSwatchColor()
            else
                -- OFF state
                indicator._bg:Hide()
                indicator._text:SetText("OFF")
                indicator._text:SetTextColor(dR, dG, dB, 1)
                for _, tex in pairs(indicator._border) do
                    tex:SetColorTexture(r, g, b, 0.4)
                end
                -- Hide color swatch
                swatch:Hide()
            end
        end
    end
    row._updateVisual = UpdateVisual

    -- Initialize
    row._value = getValue() or false
    -- Initialize disabled state from function
    if isDisabledFn then
        row._isDisabled = isDisabledFn() and true or false
    end
    UpdateVisual()

    -- Row hover handlers
    row:SetScript("OnEnter", function(self)
        self._hoverBg:Show()
    end)
    row:SetScript("OnLeave", function(self)
        if not swatch:IsMouseOver() then
            self._hoverBg:Hide()
        end
    end)

    -- Row click toggles state (but not if clicking swatch or disabled)
    row:SetScript("OnClick", function(self, mouseButton)
        -- Don't respond to clicks when disabled
        if self._isDisabled then
            return
        end
        self._value = not self._value
        setValue(self._value)
        UpdateVisual()
        PlaySound(self._value and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
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

    -- Theme subscription
    local subscribeKey = "ToggleColorPicker_" .. (name or tostring(row))
    theme:Subscribe(subscribeKey, function(r, g, b)
        UpdateVisual()
    end)
    row._subscribeKey = subscribeKey

    -- Public methods
    function row:SetValue(newValue)
        self._value = newValue or false
        self._updateVisual()
    end

    function row:GetValue()
        return self._value
    end

    function row:SetColor(r, g, b, a)
        setColor(r, g, b, a or 1)
        self._updateSwatchColor()
    end

    function row:GetColor()
        return ReadColor()
    end

    function row:Refresh()
        self._value = getValue() or false
        -- Check disabled state from function
        if self._isDisabledFn then
            local wasDisabled = self._isDisabled
            self._isDisabled = self._isDisabledFn() and true or false
        end
        self._updateVisual()
        self._updateSwatchColor()
    end

    function row:SetDisabled(disabled)
        self._isDisabled = disabled and true or false
        self._updateVisual()
    end

    function row:IsDisabled()
        return self._isDisabled
    end

    function row:Cleanup()
        if self._subscribeKey then
            theme:Unsubscribe(self._subscribeKey)
        end
    end

    function row:GetDescriptionFontString()
        return self._description
    end

    return row
end
