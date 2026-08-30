-- FontSelector.lua - Font selection row with popup picker
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

local FONT_SELECTOR_HEIGHT = 28
local FONT_SELECTOR_ROW_HEIGHT = 42
local FONT_SELECTOR_ROW_HEIGHT_WITH_DESC = 60
local FONT_SELECTOR_WIDTH = 200
local FONT_SELECTOR_PADDING = 12
local FONT_SELECTOR_BORDER_ALPHA = 0.6

--------------------------------------------------------------------------------
-- FontSelector: Font selection row with popup picker
--------------------------------------------------------------------------------

function Controls:CreateFontSelector(options)
    local theme = GetTheme()
    if not options or not options.parent then
        return nil
    end

    local parent = options.parent
    local label = options.label or "Font"
    local description = options.description
    local getValue = options.get or function() return "FRIZQT__" end
    local setValue = options.set or function() end
    local selectorWidth = options.width or FONT_SELECTOR_WIDTH
    local selectorHeight = options.selectorHeight or FONT_SELECTOR_HEIGHT
    local labelFontSize = options.labelFontSize or 13
    local name = options.name

    local hasDesc = description and description ~= ""
    local defaultRowHeight = hasDesc and FONT_SELECTOR_ROW_HEIGHT_WITH_DESC or FONT_SELECTOR_ROW_HEIGHT
    local rowHeight = options.rowHeight or defaultRowHeight

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

    -- Label text (left side)
    local labelFS = row:CreateFontString(nil, "OVERLAY")
    local labelFont = theme:GetFont("LABEL")
    labelFS:SetFont(labelFont, labelFontSize, "")
    labelFS:SetPoint("LEFT", row, "LEFT", FONT_SELECTOR_PADDING, hasDesc and 6 or 0)
    labelFS:SetText(label)
    labelFS:SetTextColor(ar, ag, ab, 1)
    row._label = labelFS

    -- Description text (below label, if provided)
    if hasDesc then
        local descFS = row:CreateFontString(nil, "OVERLAY")
        local descFont = theme:GetFont("VALUE")
        descFS:SetFont(descFont, 11, "")
        descFS:SetPoint("TOPLEFT", labelFS, "BOTTOMLEFT", 0, -2)
        descFS:SetPoint("RIGHT", row, "RIGHT", -(selectorWidth + FONT_SELECTOR_PADDING * 2), 0)
        descFS:SetText(description)
        descFS:SetTextColor(dimR, dimG, dimB, 1)
        descFS:SetJustifyH("LEFT")
        descFS:SetWordWrap(true)
        row._description = descFS
    end

    -- Selector button (right side, clickable to open popup)
    local selector = CreateFrame("Button", nil, row)
    selector:SetSize(selectorWidth, selectorHeight)
    selector:SetPoint("RIGHT", row, "RIGHT", -FONT_SELECTOR_PADDING, 0)
    selector:EnableMouse(true)
    selector:RegisterForClicks("AnyUp")

    -- Selector border (brightens on hover)
    selector._border = Controls.CreateBorder(selector, {
        alpha = FONT_SELECTOR_BORDER_ALPHA,
        getAlpha = function(self) return self:IsMouseOver() and 0.8 or FONT_SELECTOR_BORDER_ALPHA end,
    })

    -- Selector background
    selector._bg = Controls.AddBackground(selector, { inset = 1, sublevel = Controls.SUBLEVEL_FILL })

    -- Font value display text (shows font name in that font)
    local valueText = selector:CreateFontString(nil, "OVERLAY")
    local valueFont = theme:GetFont("VALUE")
    valueText:SetFont(valueFont, 12, "")
    valueText:SetPoint("LEFT", selector, "LEFT", 8, 0)
    valueText:SetPoint("RIGHT", selector, "RIGHT", -24, 0)
    valueText:SetJustifyH("LEFT")
    valueText:SetWordWrap(false)
    valueText:SetTextColor(1, 1, 1, 1)
    selector._text = valueText

    -- Dropdown indicator arrow
    local arrowText = selector:CreateFontString(nil, "OVERLAY")
    local arrowFont = theme:GetFont("BUTTON")
    arrowText:SetFont(arrowFont, 10, "")
    arrowText:SetPoint("RIGHT", selector, "RIGHT", -6, 0)
    arrowText:SetText("▼")
    arrowText:SetTextColor(ar, ag, ab, 0.8)
    selector._arrow = arrowText

    row._selector = selector

    -- State tracking
    row._currentValue = getValue() or "FRIZQT__"
    row._getValue = getValue
    row._setValue = setValue

    -- Get display text and update font rendering
    local function UpdateDisplay()
        local currentValue = row._currentValue
        local displayText
        if addon.IsLSMKey and addon.IsLSMKey(currentValue) then
            displayText = addon.LSMKeyToName(currentValue)
            if not addon.LSMAvailable then
                displayText = displayText .. " (missing)"
            end
        else
            displayText = addon.FontDisplayNames and addon.FontDisplayNames[currentValue] or currentValue
        end
        valueText:SetText(displayText)

        -- Try to render the text in the selected font
        local fontFace = addon.ResolveFontFace(currentValue)
        if fontFace then
            pcall(valueText.SetFont, valueText, fontFace, 12, "")
        end
    end

    -- Initial display update
    UpdateDisplay()

    -- Hover effects
    selector:SetScript("OnEnter", function(self)
        local r, g, b = theme:GetAccentColor()
        self._bg:SetColorTexture(r, g, b, 0.1)
        self._border:Refresh()
        row._hoverBg:Show()
    end)

    selector:SetScript("OnLeave", function(self)
        local bgRc, bgGc, bgBc, bgAc = theme:GetBackgroundSolidColor()
        self._bg:SetColorTexture(bgRc, bgGc, bgBc, bgAc)
        self._border:Refresh()
        row._hoverBg:Hide()
    end)

    -- Click to open font picker popup
    selector:SetScript("OnClick", function(self)
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)

        -- Create a pseudo-setting object for the font picker
        local pseudoSetting = {
            GetValue = function()
                return row._currentValue
            end,
            SetValue = function(_, value)
                row._currentValue = value
                row._setValue(value)
                UpdateDisplay()
            end
        }

        -- Show the font picker anchored to this selector
        addon.ShowFontPicker(self, pseudoSetting, nil, function(selectedValue)
            row._currentValue = selectedValue
            row._setValue(selectedValue)
            UpdateDisplay()
        end)
    end)

    -- Row hover effects (for entire row)
    row:SetScript("OnEnter", function(self)
        self._hoverBg:Show()
    end)
    row:SetScript("OnLeave", function(self)
        -- Only hide if mouse isn't over the selector
        if not selector:IsMouseOver() then
            self._hoverBg:Hide()
        end
    end)

    -- Theme subscription
    local subscribeKey = "FontSelector_" .. tostring(row)
    theme:Subscribe(subscribeKey, function(r, g, b)
        labelFS:SetTextColor(r, g, b, 1)
        rowBorder:SetColorTexture(r, g, b, 0.2)
        arrowText:SetTextColor(r, g, b, 0.8)
    end)
    row._subscribeKey = subscribeKey

    -- Public methods
    function row:GetValue()
        return self._currentValue
    end

    function row:SetValue(value)
        self._currentValue = value
        self._setValue(value)
        UpdateDisplay()
    end

    function row:Refresh()
        self._currentValue = self._getValue() or "FRIZQT__"
        UpdateDisplay()
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
