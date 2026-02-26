-- SingleLineEditBox.lua - TUI-styled single-line text input
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.Controls = addon.UI.Controls or {}
local Controls = addon.UI.Controls
local Theme -- Lazy loaded

local function GetTheme()
    if not Theme then
        Theme = addon.UI.Theme
    end
    return Theme
end

-- Constants

local BORDER_WIDTH = 1
local BORDER_ALPHA_NORMAL = 0.6
local BORDER_ALPHA_FOCUS = 1.0
local CONTENT_PADDING = 8
local DEFAULT_FONT_SIZE = 12
local INPUT_HEIGHT = 32

-- SingleLineEditBox

function Controls:CreateSingleLineEditBox(options)
    local theme = GetTheme()
    if not options or not options.parent then
        return nil
    end

    local parent = options.parent
    local width = options.width or 400
    local labelText = options.label
    local placeholder = options.placeholder
    local initialText = options.text or ""
    local fontSize = options.fontSize or DEFAULT_FONT_SIZE
    local maxLetters = options.maxLetters or 0

    -- Theme colors
    local ar, ag, ab = theme:GetAccentColor()
    local bgR, bgG, bgB, bgA = theme:GetBackgroundSolidColor()
    local dimR, dimG, dimB = theme:GetDimTextColor()

    -- Calculate total height including optional label
    local labelHeight = labelText and 20 or 0
    local totalHeight = INPUT_HEIGHT + labelHeight

    -- Container frame
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(width, totalHeight)
    container._isFocused = false

    -- Optional label
    if labelText then
        local label = container:CreateFontString(nil, "OVERLAY")
        local fontPath = theme:GetFont("LABEL")
        label:SetFont(fontPath, 12, "")
        label:SetPoint("TOPLEFT", container, "TOPLEFT", 2, 0)
        label:SetText(labelText)
        label:SetTextColor(dimR, dimG, dimB, 1)
        container._label = label
    end

    -- Bordered frame
    local bordered = CreateFrame("Frame", nil, container)
    bordered:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -labelHeight)
    bordered:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", 0, 0)
    bordered:SetSize(width, INPUT_HEIGHT)

    -- Background
    local bg = bordered:CreateTexture(nil, "BACKGROUND", nil, -8)
    bg:SetPoint("TOPLEFT", BORDER_WIDTH, -BORDER_WIDTH)
    bg:SetPoint("BOTTOMRIGHT", -BORDER_WIDTH, BORDER_WIDTH)
    bg:SetColorTexture(bgR, bgG, bgB, bgA)
    bordered._bg = bg

    -- Border textures
    local border = {}

    local bTop = bordered:CreateTexture(nil, "BORDER", nil, -1)
    bTop:SetPoint("TOPLEFT", bordered, "TOPLEFT", 0, 0)
    bTop:SetPoint("TOPRIGHT", bordered, "TOPRIGHT", 0, 0)
    bTop:SetHeight(BORDER_WIDTH)
    bTop:SetColorTexture(ar, ag, ab, BORDER_ALPHA_NORMAL)
    border.TOP = bTop

    local bBottom = bordered:CreateTexture(nil, "BORDER", nil, -1)
    bBottom:SetPoint("BOTTOMLEFT", bordered, "BOTTOMLEFT", 0, 0)
    bBottom:SetPoint("BOTTOMRIGHT", bordered, "BOTTOMRIGHT", 0, 0)
    bBottom:SetHeight(BORDER_WIDTH)
    bBottom:SetColorTexture(ar, ag, ab, BORDER_ALPHA_NORMAL)
    border.BOTTOM = bBottom

    local bLeft = bordered:CreateTexture(nil, "BORDER", nil, -1)
    bLeft:SetPoint("TOPLEFT", bordered, "TOPLEFT", 0, -BORDER_WIDTH)
    bLeft:SetPoint("BOTTOMLEFT", bordered, "BOTTOMLEFT", 0, BORDER_WIDTH)
    bLeft:SetWidth(BORDER_WIDTH)
    bLeft:SetColorTexture(ar, ag, ab, BORDER_ALPHA_NORMAL)
    border.LEFT = bLeft

    local bRight = bordered:CreateTexture(nil, "BORDER", nil, -1)
    bRight:SetPoint("TOPRIGHT", bordered, "TOPRIGHT", 0, -BORDER_WIDTH)
    bRight:SetPoint("BOTTOMRIGHT", bordered, "BOTTOMRIGHT", 0, BORDER_WIDTH)
    bRight:SetWidth(BORDER_WIDTH)
    bRight:SetColorTexture(ar, ag, ab, BORDER_ALPHA_NORMAL)
    border.RIGHT = bRight

    bordered._border = border
    container._bordered = bordered

    -- EditBox (single-line, no ScrollFrame)
    local editBox = CreateFrame("EditBox", nil, bordered)
    editBox:SetMultiLine(false)
    editBox:SetAutoFocus(false)
    editBox:SetPoint("TOPLEFT", bordered, "TOPLEFT", BORDER_WIDTH + CONTENT_PADDING, 0)
    editBox:SetPoint("BOTTOMRIGHT", bordered, "BOTTOMRIGHT", -(BORDER_WIDTH + CONTENT_PADDING), 0)

    local fontPath = theme:GetFont("VALUE")
    editBox:SetFont(fontPath, fontSize, "")
    editBox:SetTextColor(1, 1, 1, 1)
    editBox:SetText(initialText)
    if maxLetters > 0 then
        editBox:SetMaxLetters(maxLetters)
    end

    container._editBox = editBox

    -- Store original text for revert on Escape
    container._committedText = initialText

    -- Placeholder text
    if placeholder then
        local placeholderFS = bordered:CreateFontString(nil, "OVERLAY")
        placeholderFS:SetFont(fontPath, fontSize, "")
        placeholderFS:SetPoint("LEFT", editBox, "LEFT", 2, 0)
        placeholderFS:SetText(placeholder)
        placeholderFS:SetTextColor(dimR, dimG, dimB, 0.6)
        placeholderFS:SetJustifyH("LEFT")
        container._placeholder = placeholderFS

        local function UpdatePlaceholder()
            if container._placeholder then
                local text = editBox:GetText()
                if (text and text ~= "") or container._isFocused then
                    container._placeholder:Hide()
                else
                    container._placeholder:Show()
                end
            end
        end
        container._updatePlaceholder = UpdatePlaceholder
        UpdatePlaceholder()
    end

    -- Focus / border highlight
    local function SetBorderAlpha(alpha)
        for _, tex in pairs(bordered._border) do
            local r, g, b = GetTheme():GetAccentColor()
            tex:SetColorTexture(r, g, b, alpha)
        end
    end

    editBox:SetScript("OnEditFocusGained", function(self)
        container._isFocused = true
        container._committedText = self:GetText()
        SetBorderAlpha(BORDER_ALPHA_FOCUS)
        if container._updatePlaceholder then container._updatePlaceholder() end
    end)

    editBox:SetScript("OnEditFocusLost", function(self)
        container._isFocused = false
        SetBorderAlpha(BORDER_ALPHA_NORMAL)
        if container._updatePlaceholder then container._updatePlaceholder() end
        -- Commit text on focus loss (same as Enter)
        container._committedText = self:GetText()
        if container._onChange then
            container._onChange(self:GetText())
        end
    end)

    editBox:SetScript("OnEnterPressed", function(self)
        container._committedText = self:GetText()
        if container._onChange then
            container._onChange(self:GetText())
        end
        self:ClearFocus()
    end)

    editBox:SetScript("OnEscapePressed", function(self)
        -- Revert to committed text
        self:SetText(container._committedText or "")
        self:ClearFocus()
    end)

    editBox:SetScript("OnTextChanged", function(self, userInput)
        if container._updatePlaceholder then container._updatePlaceholder() end
    end)

    -- Click on bordered area focuses the editbox
    bordered:EnableMouse(true)
    bordered:SetScript("OnMouseDown", function()
        editBox:SetFocus()
    end)

    -- Theme subscription
    local subscribeKey = "SingleLineEditBox_" .. tostring(container)
    container._subscribeKey = subscribeKey

    theme:Subscribe(subscribeKey, function(r, g, b)
        for _, tex in pairs(bordered._border) do
            tex:SetColorTexture(r, g, b, container._isFocused and BORDER_ALPHA_FOCUS or BORDER_ALPHA_NORMAL)
        end
    end)

    -- Public API

    function container:GetText()
        return self._editBox:GetText()
    end

    function container:SetText(text)
        text = text or ""
        self._committedText = text
        self._editBox:SetText(text)
        if self._updatePlaceholder then self._updatePlaceholder() end
    end

    function container:SetOnChange(fn)
        self._onChange = fn
    end

    function container:SetFocus()
        self._editBox:SetFocus()
    end

    function container:ClearFocus()
        self._editBox:ClearFocus()
    end

    function container:Cleanup()
        if self._subscribeKey then
            GetTheme():Unsubscribe(self._subscribeKey)
        end
    end

    return container
end
