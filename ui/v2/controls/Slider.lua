-- Slider.lua - Numeric slider with arrows, text input, and optional end labels
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

-- Access utilities from Utils.lua
local function GetDebounce()
    return Controls.Debounce
end

local function GetCancelDebounce()
    return Controls.CancelDebounce
end

local function GetSetGlobalSyncLock()
    return Controls.SetGlobalSyncLock
end

local function GetClearGlobalSyncLock()
    return Controls.ClearGlobalSyncLock
end

local function GetIsGlobalSyncLocked()
    return Controls.IsGlobalSyncLocked
end

local function GetGlobalSyncPendingValue()
    return Controls.GetGlobalSyncPendingValue
end

-- Constants

local SLIDER_HEIGHT = 20
local SLIDER_ARROW_WIDTH = 20
local SLIDER_THUMB_WIDTH = 12
local SLIDER_THUMB_HEIGHT = 18
local SLIDER_TRACK_HEIGHT = 4
local SLIDER_DEFAULT_WIDTH = 200
local SLIDER_INPUT_WIDTH = 50
local SLIDER_ROW_HEIGHT = 40
local SLIDER_ROW_HEIGHT_WITH_DESC = 64
local SLIDER_ROW_HEIGHT_WITH_LABELS = 56
local SLIDER_ROW_HEIGHT_WITH_BOTH = 80
local SLIDER_PADDING = 12
local SLIDER_END_LABEL_FONT_SIZE = 9

-- Emphasized (hero) styling constants
local EMPHASIZED_EXTRA_HEIGHT = 12
local EMPHASIZED_LABEL_SIZE = 14
local EMPHASIZED_BORDER_WIDTH = 3


-- Slider: Numeric slider with arrows, text input, and optional end labels

function Controls:CreateSlider(options)
    local override = Controls.SkinOverride("Slider", options)
    if override then return override end
    local theme = GetTheme()
    local Debounce = GetDebounce()
    local CancelDebounce = GetCancelDebounce()
    local SetGlobalSyncLock = GetSetGlobalSyncLock()
    local ClearGlobalSyncLock = GetClearGlobalSyncLock()
    local IsGlobalSyncLocked = GetIsGlobalSyncLocked()
    local GetGlobalSyncPendingValueFn = GetGlobalSyncPendingValue()

    if not options or not options.parent then
        return nil
    end

    local parent = options.parent
    local label = options.label or "Slider"
    local description = options.description
    local minVal = options.min or 0
    local maxVal = options.max or 100
    local step = options.step or 1
    local getValue = options.get or function() return minVal end
    local setValue = options.set or function() end
    local minLabel = options.minLabel
    local maxLabel = options.maxLabel
    local sliderWidth = options.width or SLIDER_DEFAULT_WIDTH
    local inputWidth = options.inputWidth or SLIDER_INPUT_WIDTH
    local precision = options.precision or 0
    local displayMultiplier = options.displayMultiplier or 1
    local displaySuffix = options.displaySuffix or ""
    local name = options.name
    local isDisabledFn = options.disabled or options.isDisabled
    local emphasized = options.emphasized or false

    -- Edit Mode sync support: debounced callback for expensive operations
    local onEditModeSync = options.onEditModeSync
    local debounceDelay = options.debounceDelay or 0.2
    local debounceKey = options.debounceKey or ("Slider_" .. tostring({}))

    local hasDesc = description and description ~= ""
    local hasEndLabels = (minLabel and minLabel ~= "") or (maxLabel and maxLabel ~= "")
    local rowWidth = options.rowWidth

    -- Width-driven rows take the base height from the metrics, end labels
    -- adding the mini-label band; the chrome measure grows description rows
    -- synchronously. Direct callers without a rowWidth keep the fixed height
    -- table until they convert.
    local rowHeight
    if rowWidth then
        local m = Controls.Metrics()
        rowHeight = m.rowHeight + (hasEndLabels and m.miniLabelHeight or 0)
    else
        rowHeight = SLIDER_ROW_HEIGHT
        if hasDesc and hasEndLabels then
            rowHeight = SLIDER_ROW_HEIGHT_WITH_BOTH
        elseif hasDesc then
            rowHeight = SLIDER_ROW_HEIGHT_WITH_DESC
        elseif hasEndLabels then
            rowHeight = SLIDER_ROW_HEIGHT_WITH_LABELS
        end
    end
    if emphasized then
        rowHeight = rowHeight + EMPHASIZED_EXTRA_HEIGHT
    end

    local labelFontSize = emphasized and EMPHASIZED_LABEL_SIZE or 13
    local leftBorderWidth = emphasized and EMPHASIZED_BORDER_WIDTH or 0

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

    row._emphasized = emphasized

    -- Left accent border + faint background highlight for emphasized sliders
    if emphasized then
        local leftAccent = row:CreateTexture(nil, "BORDER", nil, -1)
        leftAccent:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
        leftAccent:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
        leftAccent:SetWidth(leftBorderWidth)
        leftAccent:SetColorTexture(ar, ag, ab, 1)
        row._leftAccent = leftAccent

        local emphBg = row:CreateTexture(nil, "BACKGROUND", nil, -7)
        emphBg:SetPoint("TOPLEFT", leftBorderWidth, 0)
        emphBg:SetPoint("BOTTOMRIGHT", 0, 0)
        emphBg:SetColorTexture(ar, ag, ab, 0.03)
        row._emphBg = emphBg
    end

    -- Calculate total slider area width
    local totalSliderAreaWidth = SLIDER_ARROW_WIDTH + sliderWidth + SLIDER_ARROW_WIDTH + 8 + inputWidth + Controls.ValueInputReach()

    -- Calculate vertical offset for label positioning (legacy path only)
    local labelYOffset = 0
    if hasDesc then
        labelYOffset = hasEndLabels and 14 or 10
    elseif hasEndLabels then
        labelYOffset = 8
    end

    -- Label and description
    local chromeOpts
    if rowWidth then
        chromeOpts = {
            rowWidth = rowWidth,
            baseHeight = rowHeight,
            label = label,
            labelFontSize = emphasized and EMPHASIZED_LABEL_SIZE or nil,
            padLeft = SLIDER_PADDING + leftBorderWidth,
            description = description,
            descFontSize = emphasized and 12 or nil,
            controlReserve = totalSliderAreaWidth + SLIDER_PADDING * 2,
            dimColor = { dimR, dimG, dimB },
        }
    else
        chromeOpts = {
            label = label,
            labelFontSize = labelFontSize,
            labelYOffset = labelYOffset,
            padLeft = SLIDER_PADDING + leftBorderWidth,
            description = description,
            descFontSize = emphasized and 12 or 11,
            padAbove = emphasized and 4 or 2,
            measureReserve = sliderWidth + (SLIDER_ARROW_WIDTH * 2) + inputWidth + (SLIDER_PADDING * 3) + leftBorderWidth,
            dimColor = { dimR, dimG, dimB },
        }
    end
    Controls.AddRowChrome(row, chromeOpts)

    -- Slider container (right side, centered in the top band on width-driven
    -- rows)
    local sliderContainer = CreateFrame("Frame", nil, row)
    sliderContainer:SetSize(totalSliderAreaWidth, SLIDER_HEIGHT + (hasEndLabels and 14 or 0))
    if rowWidth then
        Controls.AnchorCluster(row, sliderContainer, {
            x = -SLIDER_PADDING,
            y = hasEndLabels and -4 or 0,
        })
    else
        sliderContainer:SetPoint("RIGHT", row, "RIGHT", -SLIDER_PADDING, hasEndLabels and -4 or 0)
    end

    -- The skin's slider role. A template kind is Blizzard's slider with
    -- steppers, which stands where the two arrows, the track and the thumb do;
    -- those four stay nil and every later use of them is guarded.
    local widget
    local leftArrow, rightArrow, trackFrame, trackFill, thumb
    local sliderSpec = addon.UI.Chrome.Spec("slider")
    if sliderSpec.kind == "template" then
        -- The template insets its Slider 19 each side for the steppers, so
        -- the two arrow widths make the track the width the caller asked for.
        widget = addon.UI.Chrome.CreateFrame(sliderSpec, "Frame", nil, sliderContainer)
        widget:SetSize(sliderWidth + SLIDER_ARROW_WIDTH * 2, SLIDER_HEIGHT)
        widget:SetPoint("LEFT", sliderContainer, "LEFT", 0, hasEndLabels and 7 or 0)
        local range = maxVal - minVal
        local steps = (step > 0 and range > 0) and math.max(1, math.floor(range / step + 0.5)) or 1
        widget:Init(minVal, minVal, maxVal, steps)
    else

    -- Left arrow button (decrement)
    leftArrow = Controls.CreateArrowButton(sliderContainer, {
        width = SLIDER_ARROW_WIDTH,
        height = SLIDER_HEIGHT,
        glyph = "◀",
        direction = "prev",
        fontSize = 12,
        noHover = true,
    })
    leftArrow:SetPoint("LEFT", sliderContainer, "LEFT", 0, hasEndLabels and 7 or 0)

    -- Slider track container
    trackFrame = CreateFrame("Frame", nil, sliderContainer)
    trackFrame:SetSize(sliderWidth, SLIDER_HEIGHT)
    trackFrame:SetPoint("LEFT", leftArrow, "RIGHT", 0, 0)

    -- Track background (dark line)
    local trackBg = trackFrame:CreateTexture(nil, "BACKGROUND", nil, -7)
    trackBg:SetHeight(SLIDER_TRACK_HEIGHT)
    trackBg:SetPoint("LEFT", trackFrame, "LEFT", 0, 0)
    trackBg:SetPoint("RIGHT", trackFrame, "RIGHT", 0, 0)
    trackBg:SetColorTexture(ar, ag, ab, 0.2)
    trackFrame._trackBg = trackBg

    -- Track fill (accent color, from left to thumb)
    trackFill = trackFrame:CreateTexture(nil, "BACKGROUND", nil, -6)
    trackFill:SetHeight(SLIDER_TRACK_HEIGHT)
    trackFill:SetPoint("LEFT", trackFrame, "LEFT", 0, 0)
    trackFill:SetWidth(0)
    trackFill:SetColorTexture(ar, ag, ab, 0.6)
    trackFrame._trackFill = trackFill

    -- Thumb (draggable handle)
    thumb = CreateFrame("Button", nil, trackFrame)
    thumb:SetSize(SLIDER_THUMB_WIDTH, SLIDER_THUMB_HEIGHT)
    thumb:SetPoint("CENTER", trackFrame, "LEFT", 0, 0)
    thumb:EnableMouse(true)
    thumb:RegisterForDrag("LeftButton")

    local thumbBg = thumb:CreateTexture(nil, "ARTWORK", nil, 0)
    thumbBg:SetAllPoints()
    thumbBg:SetColorTexture(ar, ag, ab, 1)
    thumb._bg = thumbBg

    -- Thumb border (darker outline)
    thumb._border = Controls.CreateBorder(thumb, {
        layer = "ARTWORK",
        sublevel = 1,
        color = { 0, 0, 0, 0.5 },
    })
    trackFrame._thumb = thumb

    -- Right arrow button (increment)
    rightArrow = Controls.CreateArrowButton(sliderContainer, {
        width = SLIDER_ARROW_WIDTH,
        height = SLIDER_HEIGHT,
        glyph = "▶",
        direction = "next",
        fontSize = 12,
        noHover = true,
    })
    rightArrow:SetPoint("LEFT", trackFrame, "RIGHT", 0, 0)

    end

    -- The typed value box (right of the steppers)
    local inputFrame = Controls.CreateValueInput(sliderContainer, { width = inputWidth, height = SLIDER_HEIGHT })
    inputFrame:SetPoint("LEFT", widget or rightArrow, "RIGHT", 8 + inputFrame._artLeft, 0)

    sliderContainer._inputFrame = inputFrame

    -- Optional end labels (tiny text under left/right of track)
    if hasEndLabels then
        local labelHost = widget and widget.Slider or trackFrame
        if minLabel and minLabel ~= "" then
            local minLabelFS = labelHost:CreateFontString(nil, "OVERLAY")
            local endLabelFont = theme:GetFont("VALUE")
            minLabelFS:SetFont(endLabelFont, SLIDER_END_LABEL_FONT_SIZE, "")
            minLabelFS:SetPoint("TOP", labelHost, "BOTTOMLEFT", 0, -2)
            minLabelFS:SetText(minLabel)
            minLabelFS:SetTextColor(dimR, dimG, dimB, 0.8)
            labelHost._minLabel = minLabelFS
        end

        if maxLabel and maxLabel ~= "" then
            local maxLabelFS = labelHost:CreateFontString(nil, "OVERLAY")
            local endLabelFont = theme:GetFont("VALUE")
            maxLabelFS:SetFont(endLabelFont, SLIDER_END_LABEL_FONT_SIZE, "")
            maxLabelFS:SetPoint("TOP", labelHost, "BOTTOMRIGHT", 0, -2)
            maxLabelFS:SetText(maxLabel)
            maxLabelFS:SetTextColor(dimR, dimG, dimB, 0.8)
            labelHost._maxLabel = maxLabelFS
        end
    end

    sliderContainer._leftArrow = leftArrow
    sliderContainer._rightArrow = rightArrow
    sliderContainer._trackFrame = trackFrame or widget
    row._sliderContainer = sliderContainer
    -- Store references for disabled state
    row._leftArrow = leftArrow
    row._rightArrow = rightArrow
    row._trackFrame = trackFrame or widget
    row._sliderWidget = widget
    row._inputFrame = inputFrame
    row._isDisabled = false
    row._isDisabledFn = isDisabledFn

    -- State tracking
    row._currentValue = minVal
    row._minVal = minVal
    row._maxVal = maxVal
    row._step = step
    row._precision = precision
    row._sliderWidth = sliderWidth

    -- Format value for display
    local function FormatValue(val)
        local displayVal = val * displayMultiplier
        local formatted
        if precision == 0 then
            formatted = tostring(math.floor(displayVal + 0.5))
        else
            formatted = string.format("%." .. precision .. "f", displayVal)
        end
        return formatted .. displaySuffix
    end

    -- Clamp value to min/max and snap to step
    local function ClampValue(val)
        val = math.max(minVal, math.min(maxVal, val))
        -- Snap to step
        val = math.floor((val - minVal) / step + 0.5) * step + minVal
        return math.max(minVal, math.min(maxVal, val))
    end

    -- Update visual display (thumb position, fill, input text)
    local function UpdateDisplay()
        local val = row._currentValue
        if widget then
            -- Guarded: the widget reports every SetValue, this one included
            row._settingWidget = true
            widget.Slider:SetValue(val)
            row._settingWidget = false
        else
            local range = maxVal - minVal
            local percent = range > 0 and ((val - minVal) / range) or 0
            local trackWidth = sliderWidth - SLIDER_THUMB_WIDTH

            -- Position thumb
            local thumbX = percent * trackWidth + (SLIDER_THUMB_WIDTH / 2)
            thumb:ClearAllPoints()
            thumb:SetPoint("CENTER", trackFrame, "LEFT", thumbX, 0)

            -- Update fill width
            trackFill:SetWidth(math.max(1, thumbX))
        end

        -- Update input text
        inputFrame:SetText(FormatValue(val))
    end
    row._updateDisplay = UpdateDisplay

    -- Re-assert the value box's text once the row has a rect.
    -- An EditBox lays its text out at SetText time, against whatever rect it
    -- has right then; a FontString re-lays out every render pass. So when a
    -- page is built before its rows have been through a layout pass -- the
    -- first panel open after a reload -- the value is stored (GetText returns
    -- it) but nothing draws, while the label, description and thumb all look
    -- correct. Re-opening the panel rebuilds into an already-laid-out pane,
    -- which is why the second look was always fine.
    -- Clearing first is deliberate: SetText with the identical string can be
    -- a no-op internally, and a no-op would not re-lay-out anything.
    local function RepaintInput()
        if not inputFrame or inputFrame:HasFocus() then return end
        inputFrame:SetText("")
        inputFrame:SetText(FormatValue(row._currentValue))
        inputFrame:SetCursorPosition(0)
    end
    row._repaintInput = RepaintInput

    -- Initialize from getter, but respect global sync lock
    -- If a sync is pending for this debounceKey (from a previous slider instance),
    -- use the pending value instead of re-fetching (which would get the old value)
    if debounceKey and IsGlobalSyncLocked(debounceKey) then
        row._currentValue = ClampValue(GetGlobalSyncPendingValueFn(debounceKey) or minVal)
    else
        row._currentValue = ClampValue(getValue() or minVal)
    end
    UpdateDisplay()
    -- Covers both ways a row can miss its first layout: built into a pane that
    -- has not laid out yet (the timer), and built inside a hidden container --
    -- a collapsed section or an inactive tab page -- that is shown later (OnShow;
    -- the script is set after creation, so it never fires for the initial show).
    C_Timer.After(0, RepaintInput)
    row:SetScript("OnShow", RepaintInput)

    -- Sync lock state for Edit Mode sync protection
    row._syncLocked = false  -- Only used for non-debounceKey sliders

    -- Helper to check if slider is locked
    local function IsSyncLocked()
        if debounceKey then
            return IsGlobalSyncLocked(debounceKey)
        else
            return row._syncLocked
        end
    end

    -- Helper to update visual state when locked/unlocked
    local function UpdateSyncLockVisuals()
        local locked = IsSyncLocked()
        if widget then
            widget:SetEnabled(not locked and not row._isDisabled)
            return
        end
        local r, g, b = theme:GetAccentColor()
        if locked then
            -- Dim controls when locked
            leftArrow._text:SetTextColor(r * 0.4, g * 0.4, b * 0.4, 0.5)
            rightArrow._text:SetTextColor(r * 0.4, g * 0.4, b * 0.4, 0.5)
            -- Dim thumb (unless actively dragging)
            if thumb._bg and not thumb._isDragging then
                thumb._bg:SetColorTexture(r * 0.4, g * 0.4, b * 0.4, 0.5)
            end
        else
            -- Restore full brightness when unlocked
            leftArrow._text:SetTextColor(r, g, b, 1)
            rightArrow._text:SetTextColor(r, g, b, 1)
            -- Restore thumb (unless actively dragging)
            if thumb._bg and not thumb._isDragging then
                thumb._bg:SetColorTexture(r, g, b, 1)
            end
        end
    end

    -- Debounced Edit Mode sync helper
    local function TriggerDebouncedSync()
        if onEditModeSync then
            if debounceKey then
                SetGlobalSyncLock(debounceKey, row._currentValue)
            else
                row._syncLocked = true
            end
            UpdateSyncLockVisuals()

            Debounce(debounceKey, debounceDelay, function()
                onEditModeSync(row._currentValue)
                if debounceKey then
                    ClearGlobalSyncLock(debounceKey)
                else
                    row._syncLocked = false
                end
                UpdateSyncLockVisuals()
            end)
        end
    end
    row._triggerDebouncedSync = TriggerDebouncedSync

    if widget then
        -- A stepper click reports on mouse-up and commits at once. A drag or
        -- a track click reports while the button is down: the display follows
        -- and the value commits on release, as the flat thumb's drag does.
        local pendingCommit = false
        local function Commit()
            pendingCommit = false
            setValue(row._currentValue)
            TriggerDebouncedSync()
        end
        widget:RegisterCallback(widget.Event.OnValueChanged, function(_, value)
            if row._settingWidget then return end
            if row._isDisabled or IsSyncLocked() then
                UpdateDisplay()
                return
            end
            local newValue = ClampValue(value)
            if newValue == row._currentValue then return end
            row._currentValue = newValue
            if not inputFrame:HasFocus() then
                inputFrame:SetText(FormatValue(newValue))
            end
            if IsMouseButtonDown("LeftButton") then
                pendingCommit = true
            else
                Commit()
            end
        end, row)
        widget.Slider:HookScript("OnMouseUp", function()
            if pendingCommit then Commit() end
        end)
    else

    -- Arrow hover effects
    leftArrow:SetScript("OnEnter", function(btn)
        if IsSyncLocked() then return end
        local r, g, b = theme:GetAccentColor()
        btn._bg:SetColorTexture(r, g, b, 0.2)
    end)
    leftArrow:SetScript("OnLeave", function(btn)
        btn._bg:SetColorTexture(0, 0, 0, 0)
    end)

    rightArrow:SetScript("OnEnter", function(btn)
        if IsSyncLocked() then return end
        local r, g, b = theme:GetAccentColor()
        btn._bg:SetColorTexture(r, g, b, 0.2)
    end)
    rightArrow:SetScript("OnLeave", function(btn)
        btn._bg:SetColorTexture(0, 0, 0, 0)
    end)

    -- Left arrow click (decrement)
    leftArrow:SetScript("OnClick", function(btn)
        if row._isDisabled or IsSyncLocked() then return end
        row._currentValue = ClampValue(row._currentValue - step)
        setValue(row._currentValue)
        UpdateDisplay()
        TriggerDebouncedSync()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    end)

    -- Right arrow click (increment)
    rightArrow:SetScript("OnClick", function(btn)
        if row._isDisabled or IsSyncLocked() then return end
        row._currentValue = ClampValue(row._currentValue + step)
        setValue(row._currentValue)
        UpdateDisplay()
        TriggerDebouncedSync()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    end)

    -- Thumb dragging
    local dragStartX, dragStartValue

    thumb:SetScript("OnDragStart", function(btn)
        if row._isDisabled or IsSyncLocked() then return end
        btn._isDragging = true
        local r, g, b = theme:GetAccentColor()
        btn._bg:SetColorTexture(r, g, b, 0.6)

        local cursorX = GetCursorPosition()
        local scale = btn:GetEffectiveScale()
        dragStartX = cursorX / scale
        dragStartValue = row._currentValue
    end)

    thumb:SetScript("OnDragStop", function(btn)
        btn._isDragging = false
        local r, g, b = theme:GetAccentColor()
        btn._bg:SetColorTexture(r, g, b, 1)
        setValue(row._currentValue)
        TriggerDebouncedSync()
    end)

    thumb:SetScript("OnUpdate", function(btn)
        if not btn._isDragging then return end

        local cursorX = GetCursorPosition()
        local scale = btn:GetEffectiveScale()
        cursorX = cursorX / scale

        local deltaX = cursorX - dragStartX
        local trackWidth = sliderWidth - SLIDER_THUMB_WIDTH
        local range = maxVal - minVal

        if trackWidth > 0 and range > 0 then
            local valueDelta = (deltaX / trackWidth) * range
            row._currentValue = ClampValue(dragStartValue + valueDelta)
            UpdateDisplay()
        end
    end)

    -- Track click (jump to position)
    trackFrame:EnableMouse(true)
    trackFrame:SetScript("OnMouseDown", function(frame, button)
        if button ~= "LeftButton" then return end
        if row._isDisabled or IsSyncLocked() then return end

        local cursorX = GetCursorPosition()
        local scale = frame:GetEffectiveScale()
        cursorX = cursorX / scale

        local frameLeft = frame:GetLeft() or 0
        local clickX = cursorX - frameLeft
        local trackWidth = sliderWidth - SLIDER_THUMB_WIDTH
        local range = maxVal - minVal

        local percent = math.max(0, math.min(1, (clickX - SLIDER_THUMB_WIDTH / 2) / trackWidth))
        row._currentValue = ClampValue(minVal + percent * range)
        setValue(row._currentValue)
        UpdateDisplay()
        TriggerDebouncedSync()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    end)

    end

    -- Helper to parse input value (handles displayMultiplier and displaySuffix)
    local function ParseInputValue(text)
        -- Strip suffix if present
        if displaySuffix ~= "" and text:sub(-#displaySuffix) == displaySuffix then
            text = text:sub(1, -#displaySuffix - 1)
        end
        local val = tonumber(text)
        if val and displayMultiplier ~= 0 then
            return val / displayMultiplier
        end
        return val
    end

    -- Input field handlers
    inputFrame:SetScript("OnEnterPressed", function(self)
        if IsSyncLocked() then
            UpdateDisplay()
            self:ClearFocus()
            return
        end

        local text = self:GetText()
        local val = ParseInputValue(text)
        if val then
            row._currentValue = ClampValue(val)
            setValue(row._currentValue)
            TriggerDebouncedSync()
        end
        UpdateDisplay()
        self:ClearFocus()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    end)

    inputFrame:SetScript("OnEscapePressed", function(self)
        UpdateDisplay()
        self:ClearFocus()
    end)

    inputFrame:SetScript("OnEditFocusLost", function(self)
        if IsSyncLocked() then
            UpdateDisplay()
            return
        end

        local text = self:GetText()
        local val = ParseInputValue(text)
        if val then
            row._currentValue = ClampValue(val)
            setValue(row._currentValue)
            TriggerDebouncedSync()
        end
        UpdateDisplay()
    end)

    -- Input focus highlight
    inputFrame:SetScript("OnEditFocusGained", function(self)
        self:HighlightText()
        self._setFocusLook(true)
    end)

    inputFrame:HookScript("OnEditFocusLost", function(self)
        self:HighlightText(0, 0)
        self._setFocusLook(false)
    end)

    -- Row hover
    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self)
        self._hoverBg:Show()
    end)
    row:SetScript("OnLeave", function(self)
        self._hoverBg:Hide()
    end)

    -- Theme subscription
    local subscribeKey = "Slider_" .. (name or tostring(row))
    row._subscribeKey = subscribeKey

    theme:Subscribe(subscribeKey, function(r, g, b)
        -- Update label
        if row._label then
            row._label:SetTextColor(r, g, b, 1)
        end
        -- Update emphasized accents
        if row._leftAccent then
            row._leftAccent:SetColorTexture(r, g, b, 1)
        end
        if row._emphBg then
            row._emphBg:SetColorTexture(r, g, b, 0.03)
        end
        -- Update arrows
        if leftArrow and leftArrow._text then
            leftArrow._text:SetTextColor(r, g, b, 1)
        end
        if rightArrow and rightArrow._text then
            rightArrow._text:SetTextColor(r, g, b, 1)
        end
        -- Update track
        if trackFrame and trackFrame._trackBg then
            trackFrame._trackBg:SetColorTexture(r, g, b, 0.2)
        end
        if trackFrame and trackFrame._trackFill then
            trackFrame._trackFill:SetColorTexture(r, g, b, 0.6)
        end
        -- Update thumb
        if thumb and thumb._bg and not thumb._isDragging then
            thumb._bg:SetColorTexture(r, g, b, 1)
        end
    end)

    -- Public methods
    function row:SetValue(newValue)
        self._currentValue = ClampValue(newValue)
        self._updateDisplay()
    end

    function row:GetValue()
        return self._currentValue
    end

    function row:Refresh()
        self._currentValue = ClampValue(getValue() or self._minVal)
        -- Check disabled state from function
        if self._isDisabledFn then
            local newDisabled = self._isDisabledFn() and true or false
            if newDisabled ~= self._isDisabled then
                self:SetDisabled(newDisabled)
            end
        end
        self._updateDisplay()
    end

    function row:SetDisabled(disabled)
        self._isDisabled = disabled and true or false
        if self._sliderWidget then
            self._sliderWidget:SetEnabled(not self._isDisabled and not IsSyncLocked())
        end
        local disabledAlpha = 0.35
        local ar, ag, ab = theme:GetAccentColor()
        local dR, dG, dB = theme:GetDimTextColor()

        if self._isDisabled then
            -- Gray out all elements
            if self._label then self._label:SetTextColor(dR, dG, dB, disabledAlpha) end
            if self._description then self._description:SetAlpha(disabledAlpha) end
            if self._leftArrow then self._leftArrow:SetAlpha(disabledAlpha) end
            if self._rightArrow then self._rightArrow:SetAlpha(disabledAlpha) end
            if self._trackFrame then self._trackFrame:SetAlpha(disabledAlpha) end
            if self._inputFrame then
                self._inputFrame:SetAlpha(disabledAlpha)
                self._inputFrame:EnableMouse(false)
            end
        else
            -- Restore normal appearance
            if self._label then self._label:SetTextColor(ar, ag, ab, 1) end
            if self._description then self._description:SetAlpha(1) end
            if self._leftArrow then self._leftArrow:SetAlpha(1) end
            if self._rightArrow then self._rightArrow:SetAlpha(1) end
            if self._trackFrame then self._trackFrame:SetAlpha(1) end
            if self._inputFrame then
                self._inputFrame:SetAlpha(1)
                self._inputFrame:EnableMouse(true)
            end
        end
    end

    function row:IsDisabled()
        return self._isDisabled
    end

    function row:SetMinMax(newMin, newMax)
        self._minVal = newMin
        self._maxVal = newMax
        self._currentValue = ClampValue(self._currentValue)
        self._updateDisplay()
    end

    function row:SetLabel(newLabel)
        if self._label then
            self._label:SetText(newLabel)
        end
    end

    function row:Cleanup()
        if self._subscribeKey then
            theme:Unsubscribe(self._subscribeKey)
        end
        CancelDebounce(debounceKey)
    end

    function row:GetDescriptionFontString()
        return self._description
    end

    row._debounceKey = debounceKey

    -- Initialize disabled state from function (must be after SetDisabled is defined)
    if isDisabledFn then
        row._isDisabled = isDisabledFn() and true or false
        if row._isDisabled then
            row:SetDisabled(true)
        end
    end

    return row
end
