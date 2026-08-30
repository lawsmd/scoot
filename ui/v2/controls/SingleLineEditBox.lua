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
    local numeric = options.numeric
    local justifyH = options.justifyH

    -- Theme colors
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
    bordered._bg = Controls.AddBackground(bordered, { inset = BORDER_WIDTH })

    -- Border textures
    bordered._border = Controls.CreateBorder(bordered, {
        thickness = BORDER_WIDTH,
        alpha = BORDER_ALPHA_NORMAL,
        getAlpha = function() return container._isFocused and BORDER_ALPHA_FOCUS or BORDER_ALPHA_NORMAL end,
    })
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
    if numeric then
        editBox:SetNumeric(true)
    end
    if justifyH then
        editBox:SetJustifyH(justifyH)
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
        placeholderFS:SetJustifyH(justifyH or "LEFT")
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

    editBox:SetScript("OnEditFocusGained", function(self)
        container._isFocused = true
        container._committedText = self:GetText()
        bordered._border:Refresh()
        if container._updatePlaceholder then container._updatePlaceholder() end
    end)

    editBox:SetScript("OnEditFocusLost", function(self)
        container._isFocused = false
        bordered._border:Refresh()
        if container._updatePlaceholder then container._updatePlaceholder() end
        -- Commit text on focus loss (same as Enter)
        container._committedText = self:GetText()
        if container._onChange then
            container._onChange(self:GetText())
        end
    end)

    editBox:SetScript("OnEnterPressed", function(self)
        -- ClearFocus fires OnEditFocusLost, which commits; committing here
        -- too would fire the change callback twice per Enter.
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

    container.HasFocus = function()
        return editBox:HasFocus()
    end

    function container:Cleanup()
        if self._subscribeKey then
            GetTheme():Unsubscribe(self._subscribeKey)
        end
    end

    -- Re-assert the text once the container has a rect -- same EditBox layout
    -- timing as the slider value boxes (see the note in Slider.lua). Repaints
    -- from the committed text, never from mid-typing state, and never while
    -- the box has focus.
    local function RepaintText()
        if editBox:HasFocus() then return end
        local text = container._committedText or ""
        editBox:SetText("")
        editBox:SetText(text)
        editBox:SetCursorPosition(0)
        if container._updatePlaceholder then container._updatePlaceholder() end
    end
    container._repaintText = RepaintText
    C_Timer.After(0, RepaintText)
    container:SetScript("OnShow", RepaintText)

    return container
end
