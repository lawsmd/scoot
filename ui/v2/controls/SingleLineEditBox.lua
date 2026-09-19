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
--
-- Options: parent (required), width (400), height (32), label, placeholder,
-- text, fontSize (12), maxLetters, numeric, justifyH. The raw EditBox is
-- container._editBox for callers that hook OnTextChanged per keystroke;
-- SetOnChange fires on Enter and on focus loss only.

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
    local height = options.height or INPUT_HEIGHT

    -- Theme colors
    local dimR, dimG, dimB = theme:GetDimTextColor()

    -- Calculate total height including optional label
    local labelHeight = labelText and 20 or 0
    local totalHeight = height + labelHeight

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
    bordered:SetSize(width, height)

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

-- SearchBox
--
-- The query box on the search page. The searchBox chrome role decides the
-- draw. Flat is CreateSingleLineEditBox above. A template kind builds the
-- EditBox on the skin's template, Blizzard's SearchBoxTemplate: the options
-- search bar, the same three border pieces the slider value box draws, with
-- the magnifying glass at the left and the clear button at the right, both
-- shown and colored by the template's own scripts. The skin's searchBox
-- metric holds the art's geometry: height, and reach, how far the art
-- stands left of the EditBox, so the container is the art's rect and the
-- EditBox stands inside it; the caller anchors the container. fontRole is
-- the typed text's role, value when the metric names none.
--
-- Options: parent (required), width (400), placeholder, text, fontSize,
-- height (flat only). Both draws return a container with the same surface:
-- _editBox, GetText, SetText, SetFocus, ClearFocus, HasFocus, SetOnClear,
-- Cleanup. SetOnClear's function runs after the clear button has emptied the
-- box, which it does without userInput, so a caller hooking OnTextChanged
-- per keystroke hears the clear through this and nowhere else.
function Controls:CreateSearchBox(options)
    if not options or not options.parent then return nil end

    local Chrome = addon.UI.Chrome
    local spec = Chrome.Spec("searchBox")
    local metric = Controls.Metrics().searchBox
    if spec.kind ~= "template" or not metric then
        local container = Controls:CreateSingleLineEditBox(options)
        if container then
            container.SetOnClear = function(c, fn) c._onClear = fn end
        end
        return container
    end

    local theme = GetTheme()
    local fontRole = metric.fontRole or "value"

    local container = CreateFrame("Frame", nil, options.parent)
    container:SetSize(options.width or 400, metric.height)

    local editBox = Chrome.CreateFrame(spec, "EditBox", nil, container)
    editBox:SetPoint("TOPLEFT", container, "TOPLEFT", metric.reach, 0)
    editBox:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", 0, 0)
    editBox:SetAutoFocus(false)
    theme:ApplyFont(editBox, fontRole, options.fontSize)
    editBox:SetTextColor(1, 1, 1, 1)
    editBox:SetText(options.text or "")
    container._editBox = editBox

    for _, key in ipairs({ "Left", "Middle", "Right" }) do
        if editBox[key] then Chrome.ApplyOpacity("searchField", editBox[key]) end
    end

    -- The template's placeholder string, in the panel's face and the
    -- template's own gray. Its OnLoad has already set Blizzard's SEARCH.
    if editBox.Instructions then
        theme:ApplyFont(editBox.Instructions, fontRole, options.fontSize)
        editBox.Instructions:SetText(options.placeholder or "")
    end

    -- Blizzard's OnClick has emptied the box and dropped focus by the time
    -- this runs.
    if editBox.clearButton then
        editBox.clearButton:HookScript("OnClick", function()
            if container._onClear then container._onClear() end
        end)
    end

    container.GetText = function(c) return c._editBox:GetText() end
    container.SetText = function(c, text) c._editBox:SetText(text or "") end
    container.SetFocus = function(c) c._editBox:SetFocus() end
    container.ClearFocus = function(c) c._editBox:ClearFocus() end
    container.HasFocus = function(c) return c._editBox:HasFocus() end
    container.SetOnClear = function(c, fn) c._onClear = fn end
    container.Cleanup = function() end

    -- The same layout timing as the flat box above: re-assert the text once
    -- the container has a rect, never while the box has focus.
    local function RepaintText()
        if editBox:HasFocus() then return end
        local text = editBox:GetText() or ""
        editBox:SetText("")
        editBox:SetText(text)
        editBox:SetCursorPosition(0)
    end
    C_Timer.After(0, RepaintText)
    container:SetScript("OnShow", RepaintText)

    return container
end
