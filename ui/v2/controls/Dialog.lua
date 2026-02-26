-- Dialog.lua - TUI-styled modal dialog system
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.Controls = addon.UI.Controls or {}
local Controls = addon.UI.Controls
local Theme -- Lazy loaded

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

local DIALOG_WIDTH = 400
local DIALOG_HEIGHT = 160
local DIALOG_HEIGHT_EDITBOX = 200
local DIALOG_HEIGHT_LIST = 300
local LIST_HEIGHT_DEFAULT = 150
local LIST_ITEM_HEIGHT = 28
local BORDER_WIDTH = 3
local BUTTON_HEIGHT = 28
local BUTTON_MIN_WIDTH = 100
local BUTTON_PADDING = 16
local BUTTON_GAP = 12
local CONTENT_PADDING = 24
local MODAL_OPACITY = 0.80

-- Custom scrollbar constants
local SCROLLBAR_WIDTH = 8
local SCROLLBAR_THUMB_MIN_HEIGHT = 24
local SCROLLBAR_MARGIN = 4

--------------------------------------------------------------------------------
-- Module State
--------------------------------------------------------------------------------

local dialogFrame
local modalBackdrop
local dialogRegistry = {}

--------------------------------------------------------------------------------
-- Helper: Create Border
--------------------------------------------------------------------------------

local function CreateBorder(parent, borderWidth, r, g, b, a)
    local border = {}

    local top = parent:CreateTexture(nil, "BORDER", nil, 1)
    top:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    top:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)
    top:SetHeight(borderWidth)
    top:SetColorTexture(r, g, b, a)
    border.TOP = top

    local bottom = parent:CreateTexture(nil, "BORDER", nil, 1)
    bottom:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 0, 0)
    bottom:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
    bottom:SetHeight(borderWidth)
    bottom:SetColorTexture(r, g, b, a)
    border.BOTTOM = bottom

    local left = parent:CreateTexture(nil, "BORDER", nil, 1)
    left:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    left:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 0, 0)
    left:SetWidth(borderWidth)
    left:SetColorTexture(r, g, b, a)
    border.LEFT = left

    local right = parent:CreateTexture(nil, "BORDER", nil, 1)
    right:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)
    right:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
    right:SetWidth(borderWidth)
    right:SetColorTexture(r, g, b, a)
    border.RIGHT = right

    return border
end

--------------------------------------------------------------------------------
-- Helper: Create TUI-Styled Button
--------------------------------------------------------------------------------

local function CreateDialogButton(parent, text, width)
    local theme = GetTheme()
    local ar, ag, ab = theme:GetAccentColor()
    local bgR, bgG, bgB, bgA = theme:GetBackgroundSolidColor()

    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(width or BUTTON_MIN_WIDTH, BUTTON_HEIGHT)
    btn:EnableMouse(true)
    btn:RegisterForClicks("AnyUp", "AnyDown")

    -- Background
    local bg = btn:CreateTexture(nil, "BACKGROUND", nil, -8)
    bg:SetPoint("TOPLEFT", 2, -2)
    bg:SetPoint("BOTTOMRIGHT", -2, 2)
    bg:SetColorTexture(bgR, bgG, bgB, bgA)
    btn._bg = bg

    -- Hover fill (hidden by default)
    local hoverFill = btn:CreateTexture(nil, "BACKGROUND", nil, -7)
    hoverFill:SetPoint("TOPLEFT", 2, -2)
    hoverFill:SetPoint("BOTTOMRIGHT", -2, 2)
    hoverFill:SetColorTexture(ar, ag, ab, 1)
    hoverFill:Hide()
    btn._hoverFill = hoverFill

    -- Border
    btn._border = CreateBorder(btn, 2, ar, ag, ab, 1)

    -- Label
    local label = btn:CreateFontString(nil, "OVERLAY")
    local fontPath = theme:GetFont("BUTTON")
    label:SetFont(fontPath, 13, "")
    label:SetPoint("CENTER", 0, 0)
    label:SetText(text or "")
    label:SetTextColor(ar, ag, ab, 1)
    btn._label = label

    -- Hover handlers
    btn:SetScript("OnEnter", function(self)
        local r, g, b = theme:GetAccentColor()
        self._hoverFill:SetColorTexture(r, g, b, 1)
        self._hoverFill:Show()
        self._label:SetTextColor(0, 0, 0, 1)
    end)

    btn:SetScript("OnLeave", function(self)
        self._hoverFill:Hide()
        local r, g, b = theme:GetAccentColor()
        self._label:SetTextColor(r, g, b, 1)
    end)

    function btn:SetText(newText)
        self._label:SetText(newText)
    end

    function btn:UpdateTheme()
        local r, g, b = theme:GetAccentColor()
        for _, tex in pairs(self._border) do
            tex:SetColorTexture(r, g, b, 1)
        end
        self._hoverFill:SetColorTexture(r, g, b, 1)
        if not self:IsMouseOver() then
            self._label:SetTextColor(r, g, b, 1)
        end
    end

    return btn
end

--------------------------------------------------------------------------------
-- Helper: Create List Container for selectable options
--------------------------------------------------------------------------------

local function CreateListContainer(parent, height)
    local theme = GetTheme()
    local ar, ag, ab = theme:GetAccentColor()

    -- Calculate dimensions explicitly (don't rely on GetWidth/GetHeight before layout)
    local listHeight = height or LIST_HEIGHT_DEFAULT
    local containerWidth = DIALOG_WIDTH - (CONTENT_PADDING * 2)
    local contentWidth = containerWidth - SCROLLBAR_WIDTH - SCROLLBAR_MARGIN - 8  -- Account for insets

    -- Container frame
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(containerWidth, listHeight)
    container._listHeight = listHeight
    container._contentWidth = contentWidth

    -- Background (slightly lighter than dialog background)
    local bg = container:CreateTexture(nil, "BACKGROUND", nil, -7)
    bg:SetAllPoints()
    bg:SetColorTexture(0.06, 0.06, 0.08, 1)
    container._bg = bg

    -- Border
    container._border = CreateBorder(container, 1, ar, ag, ab, 0.6)

    -- Scroll frame for items (no template - custom scrollbar built below)
    local scrollFrame = CreateFrame("ScrollFrame", nil, container)
    scrollFrame:SetPoint("TOPLEFT", 2, -2)
    scrollFrame:SetPoint("BOTTOMRIGHT", -(SCROLLBAR_WIDTH + SCROLLBAR_MARGIN + 4), 2)

    -- Content frame (holds the list items) - use explicit width, not GetWidth()
    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(contentWidth, listHeight)
    scrollFrame:SetScrollChild(content)
    container._content = content
    container._scrollFrame = scrollFrame

    ----------------------------------------------------------------------------
    -- Custom TUI Scrollbar
    ----------------------------------------------------------------------------
    local scrollbar = CreateFrame("Frame", nil, container)
    scrollbar:SetWidth(SCROLLBAR_WIDTH)
    scrollbar:SetPoint("TOPRIGHT", container, "TOPRIGHT", -SCROLLBAR_MARGIN, -2)
    scrollbar:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -SCROLLBAR_MARGIN, 2)
    scrollbar:Hide()  -- Hidden until needed
    container._scrollbar = scrollbar

    -- Scrollbar track background
    local track = scrollbar:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints()
    track:SetColorTexture(ar, ag, ab, 0.1)
    scrollbar._track = track

    -- Scrollbar thumb (draggable)
    local thumb = CreateFrame("Button", nil, scrollbar)
    thumb:SetWidth(SCROLLBAR_WIDTH)
    thumb:SetHeight(SCROLLBAR_THUMB_MIN_HEIGHT)
    thumb:SetPoint("TOP", scrollbar, "TOP", 0, 0)
    thumb:EnableMouse(true)
    thumb:RegisterForDrag("LeftButton")
    scrollbar._thumb = thumb

    local thumbTex = thumb:CreateTexture(nil, "ARTWORK")
    thumbTex:SetAllPoints()
    thumbTex:SetColorTexture(ar, ag, ab, 0.5)
    thumb._tex = thumbTex
    thumb._isDragging = false

    -- Thumb hover/drag visual states
    thumb:SetScript("OnEnter", function(self)
        if not self._isDragging then
            local r, g, b = theme:GetAccentColor()
            self._tex:SetColorTexture(r, g, b, 0.8)
        end
    end)

    thumb:SetScript("OnLeave", function(self)
        if not self._isDragging then
            local r, g, b = theme:GetAccentColor()
            self._tex:SetColorTexture(r, g, b, 0.5)
        end
    end)

    -- Thumb dragging
    thumb:SetScript("OnDragStart", function(self)
        self._isDragging = true
        local r, g, b = theme:GetAccentColor()
        self._tex:SetColorTexture(r, g, b, 1.0)
        self._dragStartY = select(2, GetCursorPosition()) / UIParent:GetEffectiveScale()
        self._dragStartScroll = scrollFrame:GetVerticalScroll() or 0
    end)

    thumb:SetScript("OnDragStop", function(self)
        self._isDragging = false
        local r, g, b = theme:GetAccentColor()
        if self:IsMouseOver() then
            self._tex:SetColorTexture(r, g, b, 0.8)
        else
            self._tex:SetColorTexture(r, g, b, 0.5)
        end
    end)

    thumb:SetScript("OnUpdate", function(self)
        if not self._isDragging then return end

        local currentY = select(2, GetCursorPosition()) / UIParent:GetEffectiveScale()
        local deltaY = self._dragStartY - currentY

        local trackHeight = scrollbar:GetHeight()
        local thumbHeight = self:GetHeight()
        local maxThumbTravel = trackHeight - thumbHeight

        if maxThumbTravel <= 0 then return end

        local contentHeight = content:GetHeight()
        local visibleHeight = scrollFrame:GetHeight()
        local maxScroll = math.max(0, contentHeight - visibleHeight)

        -- Convert pixel drag to scroll amount
        local scrollPerPixel = maxScroll / maxThumbTravel
        local newScroll = self._dragStartScroll + (deltaY * scrollPerPixel)
        newScroll = math.max(0, math.min(maxScroll, newScroll))

        scrollFrame:SetVerticalScroll(newScroll)
        container:UpdateScrollbar()
    end)

    -- Click on track to jump
    scrollbar:EnableMouse(true)
    scrollbar:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" then return end

        local _, cursorY = GetCursorPosition()
        cursorY = cursorY / UIParent:GetEffectiveScale()
        local trackTop = self:GetTop()
        local clickOffset = trackTop - cursorY

        local trackHeight = self:GetHeight()
        local thumbHeight = thumb:GetHeight()
        local maxThumbTravel = trackHeight - thumbHeight

        if maxThumbTravel <= 0 then return end

        local contentHeight = content:GetHeight()
        local visibleHeight = scrollFrame:GetHeight()
        local maxScroll = math.max(0, contentHeight - visibleHeight)

        -- Calculate target scroll based on click position
        local targetThumbOffset = clickOffset - (thumbHeight / 2)
        targetThumbOffset = math.max(0, math.min(maxThumbTravel, targetThumbOffset))
        local scrollPercent = targetThumbOffset / maxThumbTravel
        local newScroll = scrollPercent * maxScroll

        scrollFrame:SetVerticalScroll(newScroll)
        container:UpdateScrollbar()
    end)

    -- Mouse wheel scrolling
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local contentHeight = content:GetHeight()
        local visibleHeight = self:GetHeight()
        local maxScroll = math.max(0, contentHeight - visibleHeight)

        if maxScroll <= 0 then return end

        local current = self:GetVerticalScroll() or 0
        local step = LIST_ITEM_HEIGHT * 2  -- Scroll 2 items at a time
        local newScroll = current - (delta * step)
        newScroll = math.max(0, math.min(maxScroll, newScroll))

        self:SetVerticalScroll(newScroll)
        container:UpdateScrollbar()
    end)

    -- Also enable mouse wheel on container itself
    container:EnableMouseWheel(true)
    container:SetScript("OnMouseWheel", function(self, delta)
        scrollFrame:GetScript("OnMouseWheel")(scrollFrame, delta)
    end)

    -- Update scrollbar visibility and thumb position
    function container:UpdateScrollbar()
        -- Use GetHeight with fallback to stored dimensions (for before layout completes)
        local contentHeight = content:GetHeight()
        if contentHeight == 0 then
            contentHeight = #self._items * LIST_ITEM_HEIGHT
        end

        local visibleHeight = scrollFrame:GetHeight()
        if visibleHeight == 0 then
            visibleHeight = self._listHeight - 4  -- Account for insets
        end

        if contentHeight <= visibleHeight or contentHeight == 0 then
            scrollbar:Hide()
            return
        end

        scrollbar:Show()

        local trackHeight = scrollbar:GetHeight()
        if trackHeight == 0 then
            trackHeight = self._listHeight - 4  -- Account for insets
        end

        local thumbHeight = math.max(SCROLLBAR_THUMB_MIN_HEIGHT, (visibleHeight / contentHeight) * trackHeight)
        thumb:SetHeight(thumbHeight)

        local maxScroll = contentHeight - visibleHeight
        local currentScroll = scrollFrame:GetVerticalScroll() or 0
        local scrollPercent = maxScroll > 0 and (currentScroll / maxScroll) or 0
        local maxThumbOffset = trackHeight - thumbHeight
        local thumbOffset = scrollPercent * maxThumbOffset

        thumb:ClearAllPoints()
        thumb:SetPoint("TOP", scrollbar, "TOP", 0, -thumbOffset)
    end

    -- Item storage
    container._items = {}
    container._selectedValue = nil
    container._onSelect = nil

    -- Method to populate the list
    function container:SetListOptions(options, selectedValue, onSelect)
        self._onSelect = onSelect
        self._selectedValue = nil

        -- Clear existing items
        for _, item in ipairs(self._items) do
            item:Hide()
            item:SetParent(nil)
        end
        wipe(self._items)

        if not options or #options == 0 then
            C_Timer.After(0, function() self:UpdateScrollbar() end)
            return
        end

        -- Calculate content height using stored dimensions (not GetHeight which may return 0)
        local contentHeight = #options * LIST_ITEM_HEIGHT
        local visibleHeight = self._listHeight - 4  -- Account for insets
        self._content:SetHeight(math.max(contentHeight, visibleHeight))

        -- Use stored content width (not GetWidth which may return 0 before layout)
        self._content:SetWidth(self._contentWidth)

        -- Create list items
        for i, opt in ipairs(options) do
            local item = self:CreateListItem(opt.value, opt.label, i)
            self._items[i] = item

            -- Pre-select if matches
            if selectedValue and opt.value == selectedValue then
                self._selectedValue = opt.value
                item:SetSelected(true)
            end
        end

        -- Default to first if none selected
        if not self._selectedValue and #options > 0 then
            self._selectedValue = options[1].value
            if self._items[1] then
                self._items[1]:SetSelected(true)
            end
        end

        -- Reset scroll position and defer scrollbar update until frame is laid out
        self._scrollFrame:SetVerticalScroll(0)
        C_Timer.After(0, function() self:UpdateScrollbar() end)
    end

    -- Method to create a single list item
    function container:CreateListItem(value, label, index)
        local item = CreateFrame("Button", nil, self._content)
        -- Use stored width instead of GetWidth() which may return 0 before layout
        item:SetSize(self._contentWidth, LIST_ITEM_HEIGHT)
        item:SetPoint("TOPLEFT", self._content, "TOPLEFT", 0, -((index - 1) * LIST_ITEM_HEIGHT))

        item._value = value
        item._isSelected = false

        -- Background (hidden by default, shown on hover/select)
        local itemBg = item:CreateTexture(nil, "BACKGROUND", nil, -6)
        itemBg:SetAllPoints()
        itemBg:SetColorTexture(ar, ag, ab, 0)
        item._bg = itemBg

        -- Bottom border (dim separator)
        local separator = item:CreateTexture(nil, "ARTWORK", nil, 1)
        separator:SetPoint("BOTTOMLEFT", 0, 0)
        separator:SetPoint("BOTTOMRIGHT", 0, 0)
        separator:SetHeight(1)
        separator:SetColorTexture(ar, ag, ab, 0.2)
        item._separator = separator

        -- Label text
        local labelText = item:CreateFontString(nil, "OVERLAY")
        local fontPath = theme:GetFont("VALUE")
        labelText:SetFont(fontPath, 13, "")
        labelText:SetPoint("LEFT", item, "LEFT", 10, 0)
        labelText:SetPoint("RIGHT", item, "RIGHT", -10, 0)
        labelText:SetJustifyH("LEFT")
        labelText:SetText(label or value)
        labelText:SetTextColor(1, 1, 1, 1)
        item._label = labelText

        -- Selection indicator (right side)
        local selIndicator = item:CreateFontString(nil, "OVERLAY")
        selIndicator:SetFont(fontPath, 11, "")
        selIndicator:SetPoint("RIGHT", item, "RIGHT", -10, 0)
        selIndicator:SetText("[sel]")
        selIndicator:SetTextColor(ar, ag, ab, 1)
        selIndicator:Hide()
        item._selIndicator = selIndicator

        function item:SetSelected(selected)
            self._isSelected = selected
            local r, g, b = theme:GetAccentColor()
            if selected then
                self._bg:SetColorTexture(r, g, b, 0.25)
                self._selIndicator:Show()
            else
                if self:IsMouseOver() then
                    self._bg:SetColorTexture(r, g, b, 0.15)
                else
                    self._bg:SetColorTexture(r, g, b, 0)
                end
                self._selIndicator:Hide()
            end
        end

        -- Hover handlers
        item:SetScript("OnEnter", function(self)
            if not self._isSelected then
                local r, g, b = theme:GetAccentColor()
                self._bg:SetColorTexture(r, g, b, 0.15)
            end
        end)

        item:SetScript("OnLeave", function(self)
            if not self._isSelected then
                self._bg:SetColorTexture(0, 0, 0, 0)
            end
        end)

        -- Click handler
        item:SetScript("OnClick", function(self)
            -- Deselect all others
            for _, otherItem in ipairs(container._items) do
                otherItem:SetSelected(false)
            end
            -- Select this one
            self:SetSelected(true)
            container._selectedValue = self._value
            if container._onSelect then
                container._onSelect(self._value)
            end
        end)

        return item
    end

    function container:GetSelectedValue()
        return self._selectedValue
    end

    function container:UpdateTheme()
        local r, g, b = theme:GetAccentColor()
        -- Update container border
        for _, tex in pairs(self._border) do
            tex:SetColorTexture(r, g, b, 0.6)
        end
        -- Update scrollbar
        if self._scrollbar then
            self._scrollbar._track:SetColorTexture(r, g, b, 0.1)
            local thumb = self._scrollbar._thumb
            if thumb and thumb._tex and not thumb._isDragging then
                if thumb:IsMouseOver() then
                    thumb._tex:SetColorTexture(r, g, b, 0.8)
                else
                    thumb._tex:SetColorTexture(r, g, b, 0.5)
                end
            end
        end
        -- Update list items
        for _, item in ipairs(self._items) do
            item._separator:SetColorTexture(r, g, b, 0.2)
            item._selIndicator:SetTextColor(r, g, b, 1)
            if item._isSelected then
                item._bg:SetColorTexture(r, g, b, 0.25)
            end
        end
    end

    return container
end

--------------------------------------------------------------------------------
-- Helper: Create Close Button (X)
--------------------------------------------------------------------------------

local function CreateCloseButton(parent)
    local theme = GetTheme()
    local ar, ag, ab = theme:GetAccentColor()

    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(28, 28)
    btn:EnableMouse(true)
    btn:RegisterForClicks("AnyUp", "AnyDown")

    -- Hover fill (hidden by default)
    local hoverFill = btn:CreateTexture(nil, "BACKGROUND", nil, -7)
    hoverFill:SetAllPoints()
    hoverFill:SetColorTexture(ar, ag, ab, 1)
    hoverFill:Hide()
    btn._hoverFill = hoverFill

    -- X label
    local label = btn:CreateFontString(nil, "OVERLAY")
    local fontPath = theme:GetFont("BUTTON")
    label:SetFont(fontPath, 16, "")
    label:SetPoint("CENTER", 0, 0)
    label:SetText("X")
    label:SetTextColor(ar, ag, ab, 1)
    btn._label = label

    -- Hover handlers
    btn:SetScript("OnEnter", function(self)
        local r, g, b = theme:GetAccentColor()
        self._hoverFill:SetColorTexture(r, g, b, 1)
        self._hoverFill:Show()
        self._label:SetTextColor(0, 0, 0, 1)
    end)

    btn:SetScript("OnLeave", function(self)
        self._hoverFill:Hide()
        local r, g, b = theme:GetAccentColor()
        self._label:SetTextColor(r, g, b, 1)
    end)

    function btn:UpdateTheme()
        local r, g, b = theme:GetAccentColor()
        self._hoverFill:SetColorTexture(r, g, b, 1)
        if not self:IsMouseOver() then
            self._label:SetTextColor(r, g, b, 1)
        end
    end

    return btn
end

--------------------------------------------------------------------------------
-- Dialog Frame Creation
--------------------------------------------------------------------------------

local function CreateDialogFrame()
    if dialogFrame then
        return dialogFrame, modalBackdrop
    end

    local theme = GetTheme()
    local ar, ag, ab = theme:GetAccentColor()
    local bgR, bgG, bgB, bgA = theme:GetBackgroundSolidColor()

    -- Modal backdrop (fullscreen dimmer)
    modalBackdrop = CreateFrame("Frame", "ScootDialogBackdrop", UIParent)
    modalBackdrop:SetFrameStrata("FULLSCREEN_DIALOG")
    modalBackdrop:SetFrameLevel(0)
    modalBackdrop:SetAllPoints(UIParent)
    modalBackdrop:EnableMouse(true)  -- Block clicks to content behind
    modalBackdrop:Hide()

    local dimmer = modalBackdrop:CreateTexture(nil, "BACKGROUND")
    dimmer:SetAllPoints()
    dimmer:SetColorTexture(0, 0, 0, MODAL_OPACITY)
    modalBackdrop._dimmer = dimmer

    -- Dialog frame
    local f = CreateFrame("Frame", "ScootDialog", modalBackdrop)
    f:SetSize(DIALOG_WIDTH, DIALOG_HEIGHT)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 50)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetFrameLevel(10)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)

    -- Background
    local bg = f:CreateTexture(nil, "BACKGROUND", nil, -8)
    bg:SetPoint("TOPLEFT", BORDER_WIDTH, -BORDER_WIDTH)
    bg:SetPoint("BOTTOMRIGHT", -BORDER_WIDTH, BORDER_WIDTH)
    bg:SetColorTexture(bgR, bgG, bgB, 1)  -- Full opacity for dialog
    f._bg = bg

    -- Border
    f._border = CreateBorder(f, BORDER_WIDTH, ar, ag, ab, 1)

    -- Title bar area (for dragging)
    local titleBar = CreateFrame("Frame", nil, f)
    titleBar:SetPoint("TOPLEFT", f, "TOPLEFT", BORDER_WIDTH, -BORDER_WIDTH)
    titleBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -BORDER_WIDTH - 30, -BORDER_WIDTH)
    titleBar:SetHeight(30)
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function() f:StartMoving() end)
    titleBar:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)

    -- Title text
    local title = f:CreateFontString(nil, "OVERLAY")
    local fontPath = theme:GetFont("HEADER")
    title:SetFont(fontPath, 14, "")
    title:SetPoint("TOPLEFT", f, "TOPLEFT", CONTENT_PADDING, -12)
    title:SetText("Scoot")
    title:SetTextColor(ar, ag, ab, 1)
    f._title = title

    -- Close button
    local closeBtn = CreateCloseButton(f)
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -6)
    f._closeBtn = closeBtn

    -- Message text
    local text = f:CreateFontString(nil, "ARTWORK")
    local valueFontPath = theme:GetFont("VALUE")
    text:SetFont(valueFontPath, 13, "")
    text:SetPoint("TOP", f, "TOP", 0, -45)
    text:SetPoint("LEFT", f, "LEFT", CONTENT_PADDING, 0)
    text:SetPoint("RIGHT", f, "RIGHT", -CONTENT_PADDING, 0)
    text:SetJustifyH("CENTER")
    text:SetJustifyV("TOP")
    text:SetWordWrap(true)
    text:SetTextColor(1, 1, 1, 1)
    f._text = text

    -- Edit box (hidden by default)
    local editBox = CreateFrame("EditBox", nil, f)
    editBox:SetSize(DIALOG_WIDTH - (CONTENT_PADDING * 2), 28)
    editBox:SetPoint("TOP", f._text, "BOTTOM", 0, -12)
    editBox:SetAutoFocus(false)
    editBox:SetMaxLetters(32)
    editBox:SetFont(valueFontPath, 13, "")
    editBox:SetTextColor(1, 1, 1, 1)
    editBox:SetTextInsets(8, 8, 0, 0)
    editBox:Hide()

    -- Edit box background
    local editBg = editBox:CreateTexture(nil, "BACKGROUND", nil, -8)
    editBg:SetAllPoints()
    editBg:SetColorTexture(0.08, 0.08, 0.10, 1)
    editBox._bg = editBg

    -- Edit box border
    editBox._border = CreateBorder(editBox, 1, ar, ag, ab, 0.6)

    -- Edit box focus highlight
    editBox:SetScript("OnEditFocusGained", function(self)
        local r, g, b = theme:GetAccentColor()
        for _, tex in pairs(self._border) do
            tex:SetColorTexture(r, g, b, 1)
        end
    end)

    editBox:SetScript("OnEditFocusLost", function(self)
        local r, g, b = theme:GetAccentColor()
        for _, tex in pairs(self._border) do
            tex:SetColorTexture(r, g, b, 0.6)
        end
    end)

    f._editBox = editBox

    -- List container (hidden by default, created lazily)
    f._listContainer = nil

    -- Accept button
    local acceptBtn = CreateDialogButton(f, "Yes", BUTTON_MIN_WIDTH)
    f._acceptBtn = acceptBtn

    -- Cancel button
    local cancelBtn = CreateDialogButton(f, "No", BUTTON_MIN_WIDTH)
    f._cancelBtn = cancelBtn

    -- ESC to close (via OnKeyDown)
    f:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            self:Hide()
            modalBackdrop:Hide()
            if self._onCancel then
                self._onCancel(self._data)
            end
        end
    end)

    -- Store defaults for locked dialog restoration
    f._defaultOnKeyDown = f:GetScript("OnKeyDown")

    -- Theme subscription
    local subscribeKey = "Dialog_Main"
    theme:Subscribe(subscribeKey, function(r, g, b)
        -- Update border
        for _, tex in pairs(f._border) do
            tex:SetColorTexture(r, g, b, 1)
        end
        -- Update title
        f._title:SetTextColor(r, g, b, 1)
        -- Update buttons
        f._acceptBtn:UpdateTheme()
        f._cancelBtn:UpdateTheme()
        f._closeBtn:UpdateTheme()
        -- Update edit box border
        if f._editBox._border then
            for _, tex in pairs(f._editBox._border) do
                tex:SetColorTexture(r, g, b, 0.6)
            end
        end
        -- Update list container if present
        if f._listContainer and f._listContainer.UpdateTheme then
            f._listContainer:UpdateTheme()
        end
    end)

    dialogFrame = f
    return f, modalBackdrop
end

--------------------------------------------------------------------------------
-- Public API: Register dialog definition
--------------------------------------------------------------------------------

function Controls:RegisterDialog(name, definition)
    if not name or not definition then return end
    dialogRegistry[name] = definition
end

--------------------------------------------------------------------------------
-- Public API: Show dialog
--------------------------------------------------------------------------------

function Controls:ShowDialog(name, options)
    options = options or {}
    local def = dialogRegistry[name]
    if not def then
        -- Fallback: treat name as text if not registered
        def = { text = name }
    end

    local f, backdrop = CreateDialogFrame()
    local theme = GetTheme()
    local ar, ag, ab = theme:GetAccentColor()

    local locked = options.locked or def.locked

    -- Set text (with optional format arguments)
    local displayText = options.text or def.text or "Are you sure?"
    local formatArgs = options.formatArgs or def.formatArgs
    if formatArgs and type(formatArgs) == "table" and #formatArgs > 0 then
        displayText = string.format(displayText, unpack(formatArgs))
    end
    f._text:SetText(displayText)

    -- Reset text anchors
    f._text:ClearAllPoints()
    f._text:SetPoint("TOP", f, "TOP", 0, -45)
    f._text:SetPoint("LEFT", f, "LEFT", CONTENT_PADDING, 0)
    f._text:SetPoint("RIGHT", f, "RIGHT", -CONTENT_PADDING, 0)

    -- Handle edit box
    local hasEditBox = options.hasEditBox or def.hasEditBox
    if hasEditBox then
        f._editBox:Show()
        f._editBox:SetText(options.editBoxText or def.editBoxText or "")
        f._editBox:SetMaxLetters(options.maxLetters or def.maxLetters or 32)
        f._editBox:HighlightText()
        f._editBox:SetFocus()
        f:SetHeight(options.height or def.height or DIALOG_HEIGHT_EDITBOX)
    else
        f._editBox:Hide()
        f._editBox:SetText("")
        f:SetHeight(options.height or def.height or DIALOG_HEIGHT)
    end

    -- Handle list options
    local listOptions = options.listOptions or def.listOptions
    local hasList = listOptions and #listOptions > 0
    if hasList then
        local listHeight = options.listHeight or def.listHeight or LIST_HEIGHT_DEFAULT
        -- Create list container lazily
        if not f._listContainer then
            f._listContainer = CreateListContainer(f, listHeight)
        end
        f._listContainer:SetSize(DIALOG_WIDTH - (CONTENT_PADDING * 2), listHeight)
        f._listContainer:Show()

        local selectedValue = options.selectedValue or def.selectedValue
        f._listContainer:SetListOptions(listOptions, selectedValue, nil)

        f:SetHeight(options.height or def.height or DIALOG_HEIGHT_LIST)
    else
        if f._listContainer then
            f._listContainer:Hide()
        end
    end

    -- Determine if info-only (just OK, no cancel)
    local infoOnly = locked and true or (options.infoOnly or def.infoOnly)

    -- Set button text
    local acceptText = options.acceptText or def.acceptText or (infoOnly and (OKAY or "OK")) or YES or "Yes"
    local cancelText = options.cancelText or def.cancelText or NO or "No"
    f._acceptBtn:SetText(acceptText)
    f._cancelBtn:SetText(cancelText)

    -- Calculate button widths
    local acceptWidth = options.acceptWidth or def.acceptWidth or BUTTON_MIN_WIDTH
    local cancelWidth = options.cancelWidth or def.cancelWidth or BUTTON_MIN_WIDTH
    f._acceptBtn:SetSize(acceptWidth, BUTTON_HEIGHT)
    f._cancelBtn:SetSize(cancelWidth, BUTTON_HEIGHT)

    -- Position buttons
    f._acceptBtn:ClearAllPoints()
    f._cancelBtn:ClearAllPoints()

    if infoOnly then
        -- Single centered button
        f._acceptBtn:SetPoint("BOTTOM", f, "BOTTOM", 0, CONTENT_PADDING)
        f._cancelBtn:Hide()
    else
        -- Two buttons side by side, centered
        local totalWidth = acceptWidth + cancelWidth + BUTTON_GAP
        f._cancelBtn:SetPoint("BOTTOMLEFT", f, "BOTTOM", -totalWidth/2, CONTENT_PADDING)
        f._acceptBtn:SetPoint("BOTTOMLEFT", f._cancelBtn, "BOTTOMRIGHT", BUTTON_GAP, 0)
        f._cancelBtn:Show()
    end

    -- Layout: text above buttons (or list/editbox above buttons, text above those)
    if hasList then
        f._listContainer:ClearAllPoints()
        f._listContainer:SetPoint("LEFT", f, "LEFT", CONTENT_PADDING, 0)
        f._listContainer:SetPoint("RIGHT", f, "RIGHT", -CONTENT_PADDING, 0)
        f._listContainer:SetPoint("BOTTOM", f._acceptBtn, "TOP", 0, 16)
        f._text:SetPoint("BOTTOM", f._listContainer, "TOP", 0, 12)
    elseif hasEditBox then
        f._editBox:ClearAllPoints()
        f._editBox:SetPoint("LEFT", f, "LEFT", CONTENT_PADDING, 0)
        f._editBox:SetPoint("RIGHT", f, "RIGHT", -CONTENT_PADDING, 0)
        f._editBox:SetPoint("BOTTOM", f._acceptBtn, "TOP", 0, 16)
        f._text:SetPoint("BOTTOM", f._editBox, "TOP", 0, 12)
    else
        f._text:SetPoint("BOTTOM", f._acceptBtn, "TOP", 0, 16)
    end

    -- Lockdown behavior (cannot dismiss without primary action)
    if locked then
        f._closeBtn:Hide()
        f:SetScript("OnKeyDown", function(self, key)
            -- Ignore ESC for locked dialogs
        end)
    else
        f._closeBtn:Show()
        f:SetScript("OnKeyDown", f._defaultOnKeyDown)
    end

    -- Store callbacks and data
    f._onAccept = options.onAccept
    f._onCancel = options.onCancel
    f._data = options.data
    f._hasEditBox = hasEditBox
    f._hasList = hasList

    -- Helper to get edit box text
    local function getEditBoxText()
        return hasEditBox and f._editBox:GetText() or nil
    end

    -- Helper to get selected list value
    local function getSelectedValue()
        return hasList and f._listContainer and f._listContainer:GetSelectedValue() or nil
    end

    -- Wire up buttons
    f._acceptBtn:SetScript("OnClick", function()
        local editText = getEditBoxText()
        local selectedValue = getSelectedValue()
        f:Hide()
        backdrop:Hide()
        if f._onAccept then
            f._onAccept(f._data, editText, selectedValue)
        end
    end)

    f._cancelBtn:SetScript("OnClick", function()
        f:Hide()
        backdrop:Hide()
        if f._onCancel then
            f._onCancel(f._data)
        end
    end)

    f._closeBtn:SetScript("OnClick", function()
        f:Hide()
        backdrop:Hide()
        if f._onCancel then
            f._onCancel(f._data)
        end
    end)

    -- Wire up Enter/Escape in edit box
    if hasEditBox then
        f._editBox:SetScript("OnEnterPressed", function()
            local editText = f._editBox:GetText()
            f:Hide()
            backdrop:Hide()
            if f._onAccept then
                f._onAccept(f._data, editText)
            end
        end)
        f._editBox:SetScript("OnEscapePressed", function()
            if not locked then
                f:Hide()
                backdrop:Hide()
                if f._onCancel then
                    f._onCancel(f._data)
                end
            end
        end)
    end

    -- Show the dialog
    backdrop:Show()
    f:Show()
    f:Raise()

    return f
end

--------------------------------------------------------------------------------
-- Public API: Hide dialog
--------------------------------------------------------------------------------

function Controls:HideDialog()
    if dialogFrame and dialogFrame:IsShown() then
        dialogFrame:Hide()
    end
    if modalBackdrop and modalBackdrop:IsShown() then
        modalBackdrop:Hide()
    end
end

--------------------------------------------------------------------------------
-- Public API: Quick confirmation dialog
--------------------------------------------------------------------------------

function Controls:ConfirmDialog(message, onAccept, onCancel)
    return self:ShowDialog(nil, {
        text = message,
        onAccept = onAccept,
        onCancel = onCancel,
    })
end

--------------------------------------------------------------------------------
-- Public API: Quick info dialog (OK only)
--------------------------------------------------------------------------------

function Controls:InfoDialog(message, onDismiss)
    return self:ShowDialog(nil, {
        text = message,
        onAccept = onDismiss,
        infoOnly = true,
    })
end

--------------------------------------------------------------------------------
-- Integration: Override addon.Dialogs to use TUI dialogs when v2 UI is active
--------------------------------------------------------------------------------

-- Store reference to original Dialogs module
local originalDialogs = addon.Dialogs

-- Create a wrapper that delegates to TUI dialogs
local function SetupDialogIntegration()
    if not originalDialogs then return end

    -- Override Show to use TUI dialogs
    local originalShow = originalDialogs.Show
    originalDialogs.Show = function(self, name, options)
        -- Check if TUI settings panel exists and use TUI dialogs
        if addon.UI and addon.UI.Controls and addon.UI.Controls.ShowDialog then
            -- Copy registrations from old system to new
            if dialogRegistry[name] == nil and originalDialogs._registry and originalDialogs._registry[name] then
                dialogRegistry[name] = originalDialogs._registry[name]
            end
            return Controls:ShowDialog(name, options)
        end
        -- Fallback to original
        return originalShow(self, name, options)
    end

    -- Override Confirm
    local originalConfirm = originalDialogs.Confirm
    originalDialogs.Confirm = function(self, message, onAccept, onCancel)
        if addon.UI and addon.UI.Controls and addon.UI.Controls.ConfirmDialog then
            return Controls:ConfirmDialog(message, onAccept, onCancel)
        end
        return originalConfirm(self, message, onAccept, onCancel)
    end

    -- Override Info
    local originalInfo = originalDialogs.Info
    originalDialogs.Info = function(self, message, onDismiss)
        if addon.UI and addon.UI.Controls and addon.UI.Controls.InfoDialog then
            return Controls:InfoDialog(message, onDismiss)
        end
        return originalInfo(self, message, onDismiss)
    end

    -- Override Hide
    local originalHide = originalDialogs.Hide
    originalDialogs.Hide = function(self)
        if addon.UI and addon.UI.Controls and addon.UI.Controls.HideDialog then
            Controls:HideDialog()
        end
        if originalHide then
            originalHide(self)
        end
    end

    -- Override Register to populate both systems
    local originalRegister = originalDialogs.Register
    originalDialogs.Register = function(self, name, definition)
        if originalRegister then
            originalRegister(self, name, definition)
        end
        -- Also register in TUI system
        if name and definition then
            dialogRegistry[name] = definition
        end
    end
end

-- Setup integration when addon loads
-- Use a frame to defer setup until ADDON_LOADED
local integrationFrame = CreateFrame("Frame")
integrationFrame:RegisterEvent("ADDON_LOADED")
integrationFrame:SetScript("OnEvent", function(self, event, loadedAddon)
    if loadedAddon == addonName then
        -- Defer slightly to ensure all modules are loaded
        C_Timer.After(0, function()
            SetupDialogIntegration()
            -- Copy existing registrations
            if originalDialogs and type(originalDialogs) == "table" then
                -- The original dialogs.lua stores registrations in a local table
                -- Pre-registered dialogs are re-registered automatically when Show is called
            end
        end)
        self:UnregisterEvent("ADDON_LOADED")
    end
end)

--------------------------------------------------------------------------------
-- Pre-register common dialogs (mirrors dialogs.lua registrations)
--------------------------------------------------------------------------------

Controls:RegisterDialog("SCOOT_DELETE_RULE", {
    text = "Are you sure you want to delete this rule?",
    acceptText = YES or "Yes",
    cancelText = NO or "No",
})

Controls:RegisterDialog("SCOOT_RESET_DEFAULTS", {
    text = "Are you sure you want to reset %s to all default settings and location?",
    acceptText = YES or "Yes",
    cancelText = CANCEL or "Cancel",
})

Controls:RegisterDialog("SCOOT_COPY_UF_CONFIRM", {
    text = "Copy supported Unit Frame settings from %s to %s?",
    acceptText = "Copy",
    cancelText = CANCEL or "Cancel",
})

Controls:RegisterDialog("SCOOT_COPY_UF_ERROR", {
    text = "%s",
    infoOnly = true,
})

Controls:RegisterDialog("SCOOT_COPY_ACTIONBAR_CONFIRM", {
    text = "Copy settings from %s to %s?\nThis will overwrite all settings on the destination.",
    acceptText = "Copy",
    cancelText = CANCEL or "Cancel",
})

Controls:RegisterDialog("SCOOT_COPY_CUSTOMGROUP_CONFIRM", {
    text = "Copy settings from %s to %s?\nThis will overwrite all settings on the destination.",
    acceptText = "Copy",
    cancelText = CANCEL or "Cancel",
})

Controls:RegisterDialog("SCOOT_COMBAT_FONT_RESTART", {
    text = "In order for Combat Font changes to take effect, you'll need to fully exit and re-open World of Warcraft.",
    infoOnly = true,
})

Controls:RegisterDialog("SCOOT_DELETE_LAYOUT", {
    text = "Delete layout '%s'?",
    acceptText = OKAY or "OK",
    cancelText = CANCEL or "Cancel",
})

Controls:RegisterDialog("SCOOT_CLONE_PRESET", {
    text = "Enter a name for the new layout based on %s:",
    hasEditBox = true,
    maxLetters = 32,
    acceptText = ACCEPT or "Accept",
    cancelText = CANCEL or "Cancel",
})

Controls:RegisterDialog("SCOOT_RENAME_LAYOUT", {
    text = "Rename layout:",
    hasEditBox = true,
    maxLetters = 32,
    acceptText = ACCEPT or "Accept",
    cancelText = CANCEL or "Cancel",
})

Controls:RegisterDialog("SCOOT_COPY_LAYOUT", {
    text = "Copy layout %s:",
    hasEditBox = true,
    maxLetters = 32,
    acceptText = ACCEPT or "Accept",
    cancelText = CANCEL or "Cancel",
})

Controls:RegisterDialog("SCOOT_CREATE_LAYOUT", {
    text = "Create layout:",
    hasEditBox = true,
    maxLetters = 32,
    acceptText = ACCEPT or "Accept",
    cancelText = CANCEL or "Cancel",
})

Controls:RegisterDialog("SCOOT_SPEC_PROFILE_RELOAD", {
    text = "Switching profiles for a spec change requires a UI reload so Blizzard can rebuild a clean baseline.\n\nReload now?",
    acceptText = "Reload",
    cancelText = CANCEL or "Cancel",
    height = 200,
})

Controls:RegisterDialog("SCOOT_PROFILE_RELOAD", {
    text = "Switching profiles requires a UI reload so Blizzard can rebuild a clean baseline.\n\nReload now?",
    acceptText = "Reload",
    cancelText = CANCEL or "Cancel",
    height = 200,
})

Controls:RegisterDialog("SCOOT_APPLY_PRESET", {
    text = "Enter a name for the new profile/layout based on %s:",
    hasEditBox = true,
    maxLetters = 32,
    acceptText = "Create",
    cancelText = CANCEL or "Cancel",
})

Controls:RegisterDialog("SCOOT_PRESET_TARGET_CHOICE", {
    text = "How would you like to apply the %s preset?",
    acceptText = "Create New Profile",
    cancelText = "Apply to Existing",
    acceptWidth = 180,
    cancelWidth = 180,
    height = 160,
})

Controls:RegisterDialog("SCOOT_PRESET_OVERWRITE_CONFIRM", {
    text = "This will overwrite both the Edit Mode layout settings AND the Scoot profile for '%s'.\n\nAll existing customizations will be replaced with %s preset data.\n\nContinue?",
    acceptText = "Overwrite",
    cancelText = CANCEL or "Cancel",
    height = 200,
})

Controls:RegisterDialog("SCOOT_IMPORT_CONSOLEPORT", {
    text = "This preset includes a ConsolePort profile.\n\nImport it too?\n\n(If you select Yes, your current ConsolePort profile/settings may be overwritten.)",
    acceptText = YES or "Yes",
    cancelText = NO or "No",
    height = 210,
})

Controls:RegisterDialog("SCOOT_EXTERNAL_LAYOUT_DELETED", {
    text = "The Edit Mode layout '%s' was deleted outside of Scoot.\n\nA UI reload is required to properly sync your profile state.",
    acceptText = "Reload UI",
    locked = true,
    height = 180,
})

Controls:RegisterDialog("SCOOT_APPLYALL_FONTS", {
    text = "Apply '%s' to ALL Scoot font settings?\n\nThis will overwrite every font face across all components. A UI reload is required to apply the changes.",
    acceptText = "Apply & Reload",
    acceptWidth = 130,
    cancelText = CANCEL or "Cancel",
    height = 180,
})

Controls:RegisterDialog("SCOOT_APPLYALL_TEXTURES", {
    text = "Apply '%s' to ALL Scoot bar textures?\n\nThis will overwrite every bar texture across all components. A UI reload is required to apply the changes.",
    acceptText = "Apply & Reload",
    acceptWidth = 130,
    cancelText = CANCEL or "Cancel",
    height = 180,
})

Controls:RegisterDialog("SCOOT_SELECT_EXISTING_LAYOUT", {
    text = "Select an existing layout to apply the %s preset to:",
    acceptText = "Apply",
    cancelText = CANCEL or "Cancel",
    height = 300,
    listHeight = 150,
})
