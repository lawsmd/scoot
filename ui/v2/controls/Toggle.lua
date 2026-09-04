-- Toggle.lua - Full-row toggle control with ON/OFF state indicator
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
local TOGGLE_HEIGHT_WITH_DESC = 60  -- Increased for better description spacing
local TOGGLE_BORDER = 1
local TOGGLE_INDICATOR_WIDTH = 60
local TOGGLE_INDICATOR_HEIGHT = 22
local TOGGLE_PADDING = 12

-- Dynamic height constants
local MAX_ROW_HEIGHT = 200        -- Cap to prevent excessively tall rows
local LABEL_LINE_HEIGHT = 16      -- Approximate label height
local DESC_PADDING_TOP = 2        -- Space between label and description
local DESC_PADDING_TOP_EMPH = 4   -- Space for emphasized controls
local DESC_PADDING_BOTTOM = 36    -- Space below description to border (doubled for center-anchored layout)

-- Emphasized toggle constants (Hero Toggle styling)
local EMPHASIZED_HEIGHT = 72
local EMPHASIZED_HEIGHT_WITH_DESC = 92
local EMPHASIZED_BORDER_WIDTH = 3
local EMPHASIZED_LABEL_SIZE = 16
local EMPHASIZED_INDICATOR_WIDTH = 70
local EMPHASIZED_INDICATOR_HEIGHT = 26

-- Toggle: Full-row toggle control with ON/OFF state indicator

function Controls:CreateToggle(options)
    local theme = GetTheme()
    if not options or not options.parent then
        return nil
    end

    local parent = options.parent
    local label = options.label or "Toggle"
    local description = options.description
    local getValue = options.get or function() return false end
    local setValue = options.set or function() end
    local name = options.name
    local emphasized = options.emphasized or false
    local infoIconOpts = options.infoIcon
    local isDisabledFn = options.disabled or options.isDisabled

    local hasDesc = description and description ~= ""
    local height
    if emphasized then
        height = hasDesc and EMPHASIZED_HEIGHT_WITH_DESC or EMPHASIZED_HEIGHT
    else
        height = hasDesc and TOGGLE_HEIGHT_WITH_DESC or TOGGLE_HEIGHT
    end

    -- Use appropriate sizes for emphasized vs normal
    local indicatorWidth = emphasized and EMPHASIZED_INDICATOR_WIDTH or TOGGLE_INDICATOR_WIDTH
    local indicatorHeight = emphasized and EMPHASIZED_INDICATOR_HEIGHT or TOGGLE_INDICATOR_HEIGHT
    local labelFontSize = emphasized and EMPHASIZED_LABEL_SIZE or 13
    local leftBorderWidth = emphasized and EMPHASIZED_BORDER_WIDTH or 0

    -- Create the row frame
    local row = CreateFrame("Button", name, parent)
    row:SetHeight(height)
    row:EnableMouse(true)
    row:RegisterForClicks("AnyUp")

    -- Get theme colors
    local ar, ag, ab = theme:GetAccentColor()
    local dimR, dimG, dimB
    if options.useLightDim then
        dimR, dimG, dimB = theme:GetDimTextLightColor()
    else
        dimR, dimG, dimB = theme:GetDimTextColor()
    end

    -- Row hover background (hidden by default)
    row._hoverBg = Controls.AddHoverFill(row, { sublevel = Controls.SUBLEVEL_BG })

    -- Row border (subtle line below only, plus left accent border for emphasized)
    local rowSides = { "BOTTOM" }
    if emphasized and leftBorderWidth > 0 then
        table.insert(rowSides, "LEFT")
    end
    row._rowBorder = Controls.CreateBorder(row, {
        sides = rowSides,
        thickness = { BOTTOM = TOGGLE_BORDER, LEFT = leftBorderWidth },
        alpha = 0.2,
        sideAlphas = { LEFT = 1 },
    })

    if emphasized and leftBorderWidth > 0 then
        -- Faint background highlight for emphasized
        local emphBg = row:CreateTexture(nil, "BACKGROUND", nil, -7)
        emphBg:SetPoint("TOPLEFT", leftBorderWidth, 0)
        emphBg:SetPoint("BOTTOMRIGHT", 0, 0)
        emphBg:SetColorTexture(ar, ag, ab, 0.03)
        row._emphBg = emphBg
    end
    row._emphasized = emphasized

    -- Calculate label padding (account for left border on emphasized)
    local labelLeftPad = TOGGLE_PADDING + leftBorderWidth

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
        descFS:SetPoint("RIGHT", row, "RIGHT", -(indicatorWidth + TOGGLE_PADDING * 2), 0)
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
            local descAvailableWidth = rowWidth - indicatorWidth - (TOGGLE_PADDING * 2) - labelLeftPad
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

    -- State indicator container (right side)
    local indicator = CreateFrame("Frame", nil, row)
    indicator:SetSize(indicatorWidth, indicatorHeight)
    indicator:SetPoint("RIGHT", row, "RIGHT", -TOGGLE_PADDING, 0)

    -- Indicator border (edges inset to avoid corner overlap). Static color:
    -- UpdateVisual owns all indicator tinting (state-dependent color and alpha).
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

    -- State tracking
    row._value = false
    row._isDisabled = false
    row._isDisabledFn = isDisabledFn

    -- Update visual state
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
        else
            -- Restore description alpha
            if row._description then
                row._description:SetAlpha(1)
            end
            -- Label always uses accent color for consistency
            labelFS:SetTextColor(r, g, b, 1)

            if isOn then
                -- ON state: lit indicator
                indicator._bg:Show()
                indicator._text:SetText("ON")
                indicator._text:SetTextColor(0, 0, 0, 1)  -- Dark text on accent bg
                -- Bright border on indicator
                for _, tex in pairs(indicator._border) do
                    tex:SetColorTexture(r, g, b, 1)
                end
            else
                -- OFF state: dim indicator
                indicator._bg:Hide()
                indicator._text:SetText("OFF")
                indicator._text:SetTextColor(dR, dG, dB, 1)
                -- Dimmer border on indicator
                for _, tex in pairs(indicator._border) do
                    tex:SetColorTexture(r, g, b, 0.4)
                end
            end
        end
    end
    row._updateVisual = UpdateVisual

    -- Initialize from getter
    row._value = getValue() or false
    -- Initialize disabled state from function
    if isDisabledFn then
        row._isDisabled = isDisabledFn() and true or false
    end
    UpdateVisual()

    -- Hover handlers
    row:SetScript("OnEnter", function(self)
        self._hoverBg:Show()
    end)

    row:SetScript("OnLeave", function(self)
        self._hoverBg:Hide()
    end)

    -- Click to toggle
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

    -- Generate unique subscription key
    local subscribeKey = "Toggle_" .. (name or tostring(row))
    row._subscribeKey = subscribeKey

    -- Subscribe to theme updates (hover fill and row border retint via Utils)
    theme:Subscribe(subscribeKey, function(r, g, b)
        -- Update emphasized background
        if row._emphBg then
            row._emphBg:SetColorTexture(r, g, b, 0.03)
        end
        -- Re-run visual update to apply new accent color
        UpdateVisual()
    end)

    -- Add info icon if specified (positioned after label)
    local infoSpec = Controls.InfoIconOptions(infoIconOpts)
    if infoSpec then
        local infoIcon = Controls:CreateInfoIcon({
            parent = row,
            tooltipText = infoSpec.tooltipText,
            tooltipTitle = infoSpec.tooltipTitle,
            size = infoSpec.size or (emphasized and 14 or 12),
        })
        if infoIcon then
            -- Position icon after the label text
            infoIcon:SetPoint("LEFT", labelFS, "RIGHT", 4, 0)
            row._infoIcon = infoIcon
        end
    end

    -- Public methods
    function row:SetValue(newValue)
        self._value = newValue or false
        self._updateVisual()
    end

    function row:GetValue()
        return self._value
    end

    function row:Refresh()
        self._value = getValue() or false
        -- Check disabled state from function
        if self._isDisabledFn then
            local wasDisabled = self._isDisabled
            self._isDisabled = self._isDisabledFn() and true or false
        end
        self._updateVisual()
    end

    function row:SetDisabled(disabled)
        self._isDisabled = disabled and true or false
        self._updateVisual()
    end

    function row:IsDisabled()
        return self._isDisabled
    end

    -- Dynamic label update (for orientation-dependent labels)
    function row:SetLabel(newLabel)
        if self._label then
            self._label:SetText(newLabel)
        end
    end

    function row:Cleanup()
        if self._subscribeKey then
            theme:Unsubscribe(self._subscribeKey)
        end
        if self._infoIcon and self._infoIcon.Cleanup then
            self._infoIcon:Cleanup()
        end
    end

    function row:GetDescriptionFontString()
        return self._description
    end

    return row
end
