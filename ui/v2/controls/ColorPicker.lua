-- ColorPicker.lua - Standalone color swatch button
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

local COLOR_SWATCH_WIDTH = 54
local COLOR_SWATCH_HEIGHT = 22
local COLOR_SWATCH_BORDER = 2
local COLOR_ROW_HEIGHT = 36
local COLOR_ROW_HEIGHT_WITH_DESC = 60
local COLOR_PADDING = 12

-- Dynamic height constants
local MAX_ROW_HEIGHT = 200        -- Cap to prevent excessively tall rows
local LABEL_LINE_HEIGHT = 16      -- Approximate label height
local DESC_PADDING_TOP = 2        -- Space between label and description
local DESC_PADDING_BOTTOM = 36    -- Space below description to border (doubled for center-anchored layout)

--------------------------------------------------------------------------------
-- ColorPicker: Standalone color swatch button
--------------------------------------------------------------------------------

function Controls:CreateColorPicker(options)
    local theme = GetTheme()
    if not options or not options.parent then
        return nil
    end

    local parent = options.parent
    local label = options.label or "Color"
    local description = options.description
    local getColor = options.get or function() return 1, 1, 1, 1 end
    local setColor = options.set or function() end
    local hasAlpha = options.hasAlpha or false
    local swatchWidth = options.swatchWidth or COLOR_SWATCH_WIDTH
    local swatchHeight = options.swatchHeight or COLOR_SWATCH_HEIGHT
    local name = options.name
    local isDisabledFn = options.disabled or options.isDisabled

    local hasDesc = description and description ~= ""
    local height = hasDesc and COLOR_ROW_HEIGHT_WITH_DESC or COLOR_ROW_HEIGHT

    -- Get theme colors
    local ar, ag, ab = theme:GetAccentColor()
    local dimR, dimG, dimB
    if options.useLightDim then
        dimR, dimG, dimB = theme:GetDimTextLightColor()
    else
        dimR, dimG, dimB = theme:GetDimTextColor()
    end

    -- Main row frame
    local row = CreateFrame("Frame", name, parent)
    row:SetHeight(height)

    -- Row hover background
    row._hoverBg = Controls.AddHoverFill(row, { sublevel = Controls.SUBLEVEL_BG })

    -- Row bottom border
    row._rowBorder = Controls.CreateBorder(row, { sides = {"BOTTOM"}, alpha = 0.2 })

    -- Label text (left side)
    local labelFS = row:CreateFontString(nil, "OVERLAY")
    local labelFont = theme:GetFont("LABEL")
    labelFS:SetFont(labelFont, 13, "")
    labelFS:SetPoint("LEFT", row, "LEFT", COLOR_PADDING, hasDesc and 6 or 0)
    labelFS:SetText(label)
    labelFS:SetTextColor(ar, ag, ab, 1)
    row._label = labelFS

    -- Description text (if provided)
    if hasDesc then
        local descFS = row:CreateFontString(nil, "OVERLAY")
        local descFont = theme:GetFont("VALUE")
        descFS:SetFont(descFont, 11, "")
        descFS:SetPoint("TOPLEFT", labelFS, "BOTTOMLEFT", 0, -2)
        descFS:SetPoint("RIGHT", row, "RIGHT", -(swatchWidth + COLOR_PADDING * 2 + 8), 0)
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
            local descAvailableWidth = rowWidth - swatchWidth - (COLOR_PADDING * 2) - 8
            if descAvailableWidth <= 0 then return false end

            -- Explicitly set description width so GetStringHeight returns wrapped height
            descFS:SetWidth(descAvailableWidth)

            local textHeight = descFS:GetStringHeight() or 0
            local requiredHeight = LABEL_LINE_HEIGHT + DESC_PADDING_TOP + textHeight + DESC_PADDING_BOTTOM
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

    -- Color swatch button (right side)
    local swatch = CreateFrame("Button", nil, row)
    swatch:SetSize(swatchWidth, swatchHeight)
    swatch:SetPoint("RIGHT", row, "RIGHT", -COLOR_PADDING, 0)
    swatch:EnableMouse(true)
    swatch:RegisterForClicks("AnyUp")

    -- Swatch border (four edges)
    swatch._border = Controls.CreateBorder(swatch, {
        thickness = COLOR_SWATCH_BORDER,
        getAlpha = function(self) return self:IsMouseOver() and 1 or 0.8 end,
    })

    -- Inner color display (checkerboard background for alpha visualization)
    local checkerBg = swatch:CreateTexture(nil, "BACKGROUND", nil, -7)
    checkerBg:SetPoint("TOPLEFT", COLOR_SWATCH_BORDER, -COLOR_SWATCH_BORDER)
    checkerBg:SetPoint("BOTTOMRIGHT", -COLOR_SWATCH_BORDER, COLOR_SWATCH_BORDER)
    checkerBg:SetColorTexture(0.3, 0.3, 0.3, 1)
    swatch._checkerBg = checkerBg

    -- Color fill
    local colorFill = swatch:CreateTexture(nil, "ARTWORK", nil, 0)
    colorFill:SetPoint("TOPLEFT", COLOR_SWATCH_BORDER, -COLOR_SWATCH_BORDER)
    colorFill:SetPoint("BOTTOMRIGHT", -COLOR_SWATCH_BORDER, COLOR_SWATCH_BORDER)
    swatch._colorFill = colorFill

    row._swatch = swatch

    -- Helper to read color (handles both table and multi-return)
    local function ReadColor()
        local result = { getColor() }
        if type(result[1]) == "table" then
            local c = result[1]
            return c.r or c[1] or 1, c.g or c[2] or 1, c.b or c[3] or 1, c.a or c[4] or 1
        else
            return result[1] or 1, result[2] or 1, result[3] or 1, result[4] or 1
        end
    end

    -- Update swatch display
    local function UpdateSwatchColor()
        local r, g, b, a = ReadColor()
        colorFill:SetColorTexture(r, g, b, hasAlpha and a or 1)
    end
    row._updateSwatchColor = UpdateSwatchColor

    -- State tracking for disabled
    row._isDisabled = false
    row._isDisabledFn = isDisabledFn

    -- Initialize color
    UpdateSwatchColor()

    -- Initialize disabled state from function
    if isDisabledFn then
        row._isDisabled = isDisabledFn() and true or false
        if row._isDisabled then
            local dR, dG, dB = theme:GetDimTextColor()
            local disabledAlpha = 0.35
            labelFS:SetTextColor(dR, dG, dB, disabledAlpha)
            if row._description then
                row._description:SetAlpha(disabledAlpha)
            end
            swatch:SetAlpha(disabledAlpha)
        end
    end

    -- Hover handlers for row
    row:SetScript("OnEnter", function(self)
        self._hoverBg:Show()
    end)
    row:SetScript("OnLeave", function(self)
        if not swatch:IsMouseOver() then
            self._hoverBg:Hide()
        end
    end)
    row:EnableMouse(true)

    -- Hover handlers for swatch (highlight border)
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

    -- Click to open color picker
    swatch:SetScript("OnClick", function()
        -- Don't respond to clicks when disabled
        if row._isDisabled then
            return
        end
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
    local subscribeKey = "ColorPicker_" .. (name or tostring(row))
    theme:Subscribe(subscribeKey, function(r, g, b)
        if row._label then
            row._label:SetTextColor(r, g, b, 1)
        end
    end)
    row._subscribeKey = subscribeKey

    -- Public methods
    function row:SetColor(r, g, b, a)
        setColor(r, g, b, a or 1)
        self._updateSwatchColor()
    end

    function row:GetColor()
        return ReadColor()
    end

    function row:Refresh()
        -- Check disabled state from function
        if self._isDisabledFn then
            local newDisabled = self._isDisabledFn() and true or false
            if newDisabled ~= self._isDisabled then
                self:SetDisabled(newDisabled)
            end
        end
        self._updateSwatchColor()
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
            if self._swatch then self._swatch:SetAlpha(disabledAlpha) end
        else
            -- Restore normal appearance
            if self._label then self._label:SetTextColor(ar, ag, ab, 1) end
            if self._description then self._description:SetAlpha(1) end
            if self._swatch then self._swatch:SetAlpha(1) end
        end
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
