-- MultiLineEditBox.lua - TUI-styled scrollable multi-line text input
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
local SCROLLBAR_WIDTH = 6
local SCROLLBAR_THUMB_MIN_HEIGHT = 20
local SCROLLBAR_MARGIN = 4
local DEFAULT_FONT_SIZE = 12

-- MultiLineEditBox

function Controls:CreateMultiLineEditBox(options)
    local theme = GetTheme()
    if not options or not options.parent then
        return nil
    end

    local parent = options.parent
    local width = options.width or 400
    local height = options.height or 120
    local labelText = options.label
    local placeholder = options.placeholder
    local readOnly = options.readOnly or false
    local initialText = options.text or ""
    local fontSize = options.fontSize or DEFAULT_FONT_SIZE

    -- Theme colors
    local ar, ag, ab = theme:GetAccentColor()
    local dimR, dimG, dimB = theme:GetDimTextColor()

    -- Calculate total height including optional label
    local labelHeight = labelText and 20 or 0
    local totalHeight = height + labelHeight

    -- Container frame
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(width, totalHeight)
    container._isFocused = false
    container._readOnly = readOnly

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

    -- ScrollFrame + EditBox
    local scrollFrame = CreateFrame("ScrollFrame", nil, bordered)
    scrollFrame:SetPoint("TOPLEFT", bordered, "TOPLEFT", BORDER_WIDTH + CONTENT_PADDING, -(BORDER_WIDTH + CONTENT_PADDING))
    scrollFrame:SetPoint("BOTTOMRIGHT", bordered, "BOTTOMRIGHT", -(BORDER_WIDTH + CONTENT_PADDING + SCROLLBAR_WIDTH + SCROLLBAR_MARGIN), BORDER_WIDTH + CONTENT_PADDING)
    scrollFrame:EnableMouseWheel(true)
    container._scrollFrame = scrollFrame

    local editBox = CreateFrame("EditBox", nil, scrollFrame)
    editBox:SetMultiLine(true)
    editBox:SetAutoFocus(false)
    editBox:SetWidth(scrollFrame:GetWidth() or (width - 2 * (BORDER_WIDTH + CONTENT_PADDING) - SCROLLBAR_WIDTH - SCROLLBAR_MARGIN))

    local fontPath = theme:GetFont("VALUE")
    editBox:SetFont(fontPath, fontSize, "")
    editBox:SetTextColor(1, 1, 1, 1)
    editBox:SetText(initialText)
    editBox:SetMaxLetters(0) -- unlimited

    scrollFrame:SetScrollChild(editBox)
    container._editBox = editBox

    -- Adjust editbox width when scroll frame resizes
    scrollFrame:SetScript("OnSizeChanged", function(self, w, h)
        if w and w > 0 then
            editBox:SetWidth(w)
        end
    end)

    -- Placeholder text
    if placeholder then
        local placeholderFS = bordered:CreateFontString(nil, "OVERLAY")
        placeholderFS:SetFont(fontPath, fontSize, "")
        placeholderFS:SetPoint("TOPLEFT", scrollFrame, "TOPLEFT", 2, 0)
        placeholderFS:SetText(placeholder)
        placeholderFS:SetTextColor(dimR, dimG, dimB, 0.6)
        placeholderFS:SetJustifyH("LEFT")
        placeholderFS:SetJustifyV("TOP")
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

    -- Scrollbar
    local scrollbar = CreateFrame("Frame", nil, bordered)
    scrollbar:SetWidth(SCROLLBAR_WIDTH)
    scrollbar:SetPoint("TOPRIGHT", bordered, "TOPRIGHT", -(BORDER_WIDTH + SCROLLBAR_MARGIN), -(BORDER_WIDTH + CONTENT_PADDING))
    scrollbar:SetPoint("BOTTOMRIGHT", bordered, "BOTTOMRIGHT", -(BORDER_WIDTH + SCROLLBAR_MARGIN), BORDER_WIDTH + CONTENT_PADDING)

    local track = scrollbar:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints()
    track:SetColorTexture(ar, ag, ab, 0.1)
    scrollbar._track = track

    local thumb = CreateFrame("Button", nil, scrollbar)
    thumb:SetWidth(SCROLLBAR_WIDTH)
    thumb:SetHeight(SCROLLBAR_THUMB_MIN_HEIGHT)
    thumb:SetPoint("TOP", scrollbar, "TOP", 0, 0)
    thumb:EnableMouse(true)
    thumb:RegisterForDrag("LeftButton")

    local thumbTex = thumb:CreateTexture(nil, "ARTWORK")
    thumbTex:SetAllPoints()
    thumbTex:SetColorTexture(ar, ag, ab, 0.4)
    thumb._tex = thumbTex

    scrollbar._thumb = thumb
    scrollbar:Hide() -- hidden until content overflows

    local function UpdateScrollbar()
        local contentH = editBox:GetHeight() or 0
        local visibleH = scrollFrame:GetHeight() or 1
        local trackH = scrollbar:GetHeight() or 1

        if contentH <= visibleH then
            scrollbar:Hide()
            return
        end
        scrollbar:Show()

        local thumbH = math.max(SCROLLBAR_THUMB_MIN_HEIGHT, (visibleH / contentH) * trackH)
        thumb:SetHeight(thumbH)

        local maxScroll = contentH - visibleH
        local current = scrollFrame:GetVerticalScroll() or 0
        local pct = maxScroll > 0 and (current / maxScroll) or 0
        local maxOffset = trackH - thumbH
        thumb:ClearAllPoints()
        thumb:SetPoint("TOP", scrollbar, "TOP", 0, -(pct * maxOffset))
    end

    container._updateScrollbar = UpdateScrollbar

    -- Thumb hover
    thumb:SetScript("OnEnter", function(self)
        local r, g, b = GetTheme():GetAccentColor()
        self._tex:SetColorTexture(r, g, b, 0.7)
    end)
    thumb:SetScript("OnLeave", function(self)
        if not self._isDragging then
            local r, g, b = GetTheme():GetAccentColor()
            self._tex:SetColorTexture(r, g, b, 0.4)
        end
    end)

    -- Thumb dragging
    local dragStartY, dragStartScroll
    thumb:SetScript("OnDragStart", function(self)
        self._isDragging = true
        local r, g, b = GetTheme():GetAccentColor()
        self._tex:SetColorTexture(r, g, b, 1)
        local _, cursorY = GetCursorPosition()
        local scale = self:GetEffectiveScale()
        dragStartY = cursorY / scale
        dragStartScroll = scrollFrame:GetVerticalScroll() or 0
    end)
    thumb:SetScript("OnDragStop", function(self)
        self._isDragging = false
        local r, g, b = GetTheme():GetAccentColor()
        self._tex:SetColorTexture(r, g, b, self:IsMouseOver() and 0.7 or 0.4)
    end)
    thumb:SetScript("OnUpdate", function(self)
        if not self._isDragging then return end
        local _, cursorY = GetCursorPosition()
        local scale = self:GetEffectiveScale()
        cursorY = cursorY / scale
        local deltaY = dragStartY - cursorY

        local contentH = editBox:GetHeight() or 0
        local visibleH = scrollFrame:GetHeight() or 1
        local trackH = scrollbar:GetHeight() or 1
        local thumbH = thumb:GetHeight()
        local maxScroll = contentH - visibleH
        local maxOffset = trackH - thumbH

        if maxOffset > 0 and maxScroll > 0 then
            local scrollDelta = (deltaY / maxOffset) * maxScroll
            local newScroll = math.max(0, math.min(maxScroll, dragStartScroll + scrollDelta))
            scrollFrame:SetVerticalScroll(newScroll)
            UpdateScrollbar()
        end
    end)

    -- Mouse wheel
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local contentH = editBox:GetHeight() or 0
        local visibleH = self:GetHeight() or 1
        local maxScroll = math.max(0, contentH - visibleH)
        local step = fontSize * 3
        local newScroll = math.max(0, math.min(maxScroll, (self:GetVerticalScroll() or 0) - delta * step))
        self:SetVerticalScroll(newScroll)
        UpdateScrollbar()
    end)

    -- Update scrollbar on scroll change
    scrollFrame:SetScript("OnScrollRangeChanged", function()
        UpdateScrollbar()
    end)

    editBox:SetScript("OnEditFocusGained", function(self)
        container._isFocused = true
        bordered._border:Refresh()
        if container._updatePlaceholder then container._updatePlaceholder() end
    end)

    editBox:SetScript("OnEditFocusLost", function(self)
        container._isFocused = false
        bordered._border:Refresh()
        if container._updatePlaceholder then container._updatePlaceholder() end
    end)

    -- Update scrollbar when text changes
    editBox:SetScript("OnTextChanged", function(self, userInput)
        -- Defer to let the editbox recalculate height
        C_Timer.After(0, function()
            UpdateScrollbar()
            if container._updatePlaceholder then container._updatePlaceholder() end
        end)
    end)

    -- Click on bordered area focuses the editbox (unless readOnly)
    bordered:EnableMouse(true)
    bordered:SetScript("OnMouseDown", function()
        if not readOnly then
            editBox:SetFocus()
        end
    end)

    -- Read-only mode: allow Ctrl+A / Ctrl+C but block typing
    if readOnly then
        editBox:SetScript("OnChar", function(self)
            -- Block all character input
        end)
        editBox:EnableKeyboard(true)
        editBox:SetScript("OnKeyDown", function(self, key)
            local ctrl = IsControlKeyDown()
            if ctrl and (key == "A" or key == "C") then
                return  -- Allow select-all and copy
            end
            if key == "ESCAPE" then
                self:ClearFocus()
                return
            end
        end)
        editBox:SetScript("OnTextChanged", function(self, userInput)
            if userInput and not container._reverting then
                local stored = container._storedText
                if stored and self:GetText() ~= stored then
                    container._reverting = true
                    self:SetText(stored)
                    container._reverting = false
                end
            end
            C_Timer.After(0, function()
                UpdateScrollbar()
                if container._updatePlaceholder then container._updatePlaceholder() end
            end)
        end)
    end

    -- Theme subscription
    local subscribeKey = "MultiLineEditBox_" .. tostring(container)
    container._subscribeKey = subscribeKey

    theme:Subscribe(subscribeKey, function(r, g, b)
        scrollbar._track:SetColorTexture(r, g, b, 0.1)
        if not thumb._isDragging then
            thumb._tex:SetColorTexture(r, g, b, 0.4)
        end
    end)

    -- Public API

    function container:GetText()
        return self._editBox:GetText()
    end

    function container:SetText(text)
        text = text or ""
        self._storedText = text
        self._editBox:SetText(text)
        C_Timer.After(0, function()
            if self._updateScrollbar then self._updateScrollbar() end
            if self._updatePlaceholder then self._updatePlaceholder() end
        end)
    end

    function container:SetReadOnly(ro)
        self._readOnly = ro
        -- Re-creating scripts is complex; this flag is for reference
    end

    function container:SelectAll()
        self._editBox:HighlightText()
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

    -- Store initial text for readOnly revert
    container._storedText = initialText

    return container
end
