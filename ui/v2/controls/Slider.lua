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

local BORDER_WIDTH = 2
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

-- Dynamic height constants
local MAX_ROW_HEIGHT = 200        -- Cap to prevent excessively tall rows
local LABEL_LINE_HEIGHT = 16      -- Approximate label height
local DESC_PADDING_TOP = 2        -- Space between label and description
local DESC_PADDING_BOTTOM = 36    -- Space below description to border (doubled for center-anchored layout)

-- Slider: Numeric slider with arrows, text input, and optional end labels

function Controls:CreateSlider(options)
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

    -- Edit Mode sync support: debounced callback for expensive operations
    local onEditModeSync = options.onEditModeSync
    local debounceDelay = options.debounceDelay or 0.2
    local debounceKey = options.debounceKey or ("Slider_" .. tostring({}))

    local hasDesc = description and description ~= ""
    local hasEndLabels = (minLabel and minLabel ~= "") or (maxLabel and maxLabel ~= "")

    -- Calculate row height based on features
    local rowHeight = SLIDER_ROW_HEIGHT
    if hasDesc and hasEndLabels then
        rowHeight = SLIDER_ROW_HEIGHT_WITH_BOTH
    elseif hasDesc then
        rowHeight = SLIDER_ROW_HEIGHT_WITH_DESC
    elseif hasEndLabels then
        rowHeight = SLIDER_ROW_HEIGHT_WITH_LABELS
    end

    -- Get theme colors
    local ar, ag, ab = theme:GetAccentColor()
    local dimR, dimG, dimB
    if options.useLightDim then
        dimR, dimG, dimB = theme:GetDimTextLightColor()
    else
        dimR, dimG, dimB = theme:GetDimTextColor()
    end
    local bgR, bgG, bgB, bgA = theme:GetBackgroundSolidColor()

    -- Create the row frame
    local row = CreateFrame("Frame", name, parent)
    row:SetHeight(rowHeight)

    -- Row hover background
    local hoverBg = row:CreateTexture(nil, "BACKGROUND", nil, -8)
    hoverBg:SetAllPoints()
    hoverBg:SetColorTexture(ar, ag, ab, 0.08)
    hoverBg:Hide()
    row._hoverBg = hoverBg

    -- Row border (subtle line below)
    local rowBorder = row:CreateTexture(nil, "BORDER", nil, -1)
    rowBorder:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    rowBorder:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
    rowBorder:SetHeight(1)
    rowBorder:SetColorTexture(ar, ag, ab, 0.2)
    row._rowBorder = rowBorder

    -- Calculate vertical offset for label positioning
    local labelYOffset = 0
    if hasDesc then
        labelYOffset = hasEndLabels and 14 or 10
    elseif hasEndLabels then
        labelYOffset = 8
    end

    -- Label text (left side)
    local labelFS = row:CreateFontString(nil, "OVERLAY")
    local labelFont = theme:GetFont("LABEL")
    labelFS:SetFont(labelFont, 13, "")
    labelFS:SetPoint("LEFT", row, "LEFT", SLIDER_PADDING, labelYOffset)
    labelFS:SetText(label)
    labelFS:SetTextColor(ar, ag, ab, 1)
    row._label = labelFS

    -- Description text (below label, if provided)
    if hasDesc then
        local descFS = row:CreateFontString(nil, "OVERLAY")
        local descFont = theme:GetFont("VALUE")
        descFS:SetFont(descFont, 11, "")
        descFS:SetPoint("TOPLEFT", labelFS, "BOTTOMLEFT", 0, -2)
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
            local descAvailableWidth = rowWidth - sliderWidth - (SLIDER_ARROW_WIDTH * 2) - inputWidth - (SLIDER_PADDING * 3)
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

    -- Calculate total slider area width
    local totalSliderAreaWidth = SLIDER_ARROW_WIDTH + sliderWidth + SLIDER_ARROW_WIDTH + 8 + inputWidth

    -- Slider container (right side)
    local sliderContainer = CreateFrame("Frame", nil, row)
    sliderContainer:SetSize(totalSliderAreaWidth, SLIDER_HEIGHT + (hasEndLabels and 14 or 0))
    sliderContainer:SetPoint("RIGHT", row, "RIGHT", -SLIDER_PADDING, hasEndLabels and -4 or 0)

    -- Left arrow button (decrement)
    local leftArrow = CreateFrame("Button", nil, sliderContainer)
    leftArrow:SetSize(SLIDER_ARROW_WIDTH, SLIDER_HEIGHT)
    leftArrow:SetPoint("LEFT", sliderContainer, "LEFT", 0, hasEndLabels and 7 or 0)
    leftArrow:EnableMouse(true)
    leftArrow:RegisterForClicks("AnyUp")

    local leftArrowBg = leftArrow:CreateTexture(nil, "BACKGROUND", nil, -6)
    leftArrowBg:SetAllPoints()
    leftArrowBg:SetColorTexture(ar, ag, ab, 0)
    leftArrow._bg = leftArrowBg

    local leftArrowText = leftArrow:CreateFontString(nil, "OVERLAY")
    local arrowFont = theme:GetFont("BUTTON")
    leftArrowText:SetFont(arrowFont, 12, "")
    leftArrowText:SetPoint("CENTER", 0, 0)
    leftArrowText:SetText("◀")
    leftArrowText:SetTextColor(ar, ag, ab, 1)
    leftArrow._text = leftArrowText

    -- Slider track container
    local trackFrame = CreateFrame("Frame", nil, sliderContainer)
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
    local trackFill = trackFrame:CreateTexture(nil, "BACKGROUND", nil, -6)
    trackFill:SetHeight(SLIDER_TRACK_HEIGHT)
    trackFill:SetPoint("LEFT", trackFrame, "LEFT", 0, 0)
    trackFill:SetWidth(0)
    trackFill:SetColorTexture(ar, ag, ab, 0.6)
    trackFrame._trackFill = trackFill

    -- Thumb (draggable handle)
    local thumb = CreateFrame("Button", nil, trackFrame)
    thumb:SetSize(SLIDER_THUMB_WIDTH, SLIDER_THUMB_HEIGHT)
    thumb:SetPoint("CENTER", trackFrame, "LEFT", 0, 0)
    thumb:EnableMouse(true)
    thumb:RegisterForDrag("LeftButton")

    local thumbBg = thumb:CreateTexture(nil, "ARTWORK", nil, 0)
    thumbBg:SetAllPoints()
    thumbBg:SetColorTexture(ar, ag, ab, 1)
    thumb._bg = thumbBg

    -- Thumb border (darker outline)
    local thumbBorder = {}
    local tbw = 1  -- thumb border width

    local thumbTop = thumb:CreateTexture(nil, "ARTWORK", nil, 1)
    thumbTop:SetPoint("TOPLEFT", thumb, "TOPLEFT", 0, 0)
    thumbTop:SetPoint("TOPRIGHT", thumb, "TOPRIGHT", 0, 0)
    thumbTop:SetHeight(tbw)
    thumbTop:SetColorTexture(0, 0, 0, 0.5)
    thumbBorder.TOP = thumbTop

    local thumbBottom = thumb:CreateTexture(nil, "ARTWORK", nil, 1)
    thumbBottom:SetPoint("BOTTOMLEFT", thumb, "BOTTOMLEFT", 0, 0)
    thumbBottom:SetPoint("BOTTOMRIGHT", thumb, "BOTTOMRIGHT", 0, 0)
    thumbBottom:SetHeight(tbw)
    thumbBottom:SetColorTexture(0, 0, 0, 0.5)
    thumbBorder.BOTTOM = thumbBottom

    local thumbLeft = thumb:CreateTexture(nil, "ARTWORK", nil, 1)
    thumbLeft:SetPoint("TOPLEFT", thumb, "TOPLEFT", 0, -tbw)
    thumbLeft:SetPoint("BOTTOMLEFT", thumb, "BOTTOMLEFT", 0, tbw)
    thumbLeft:SetWidth(tbw)
    thumbLeft:SetColorTexture(0, 0, 0, 0.5)
    thumbBorder.LEFT = thumbLeft

    local thumbRight = thumb:CreateTexture(nil, "ARTWORK", nil, 1)
    thumbRight:SetPoint("TOPRIGHT", thumb, "TOPRIGHT", 0, -tbw)
    thumbRight:SetPoint("BOTTOMRIGHT", thumb, "BOTTOMRIGHT", 0, tbw)
    thumbRight:SetWidth(tbw)
    thumbRight:SetColorTexture(0, 0, 0, 0.5)
    thumbBorder.RIGHT = thumbRight

    thumb._border = thumbBorder
    trackFrame._thumb = thumb

    -- Right arrow button (increment)
    local rightArrow = CreateFrame("Button", nil, sliderContainer)
    rightArrow:SetSize(SLIDER_ARROW_WIDTH, SLIDER_HEIGHT)
    rightArrow:SetPoint("LEFT", trackFrame, "RIGHT", 0, 0)
    rightArrow:EnableMouse(true)
    rightArrow:RegisterForClicks("AnyUp")

    local rightArrowBg = rightArrow:CreateTexture(nil, "BACKGROUND", nil, -6)
    rightArrowBg:SetAllPoints()
    rightArrowBg:SetColorTexture(ar, ag, ab, 0)
    rightArrow._bg = rightArrowBg

    local rightArrowText = rightArrow:CreateFontString(nil, "OVERLAY")
    rightArrowText:SetFont(arrowFont, 12, "")
    rightArrowText:SetPoint("CENTER", 0, 0)
    rightArrowText:SetText("▶")
    rightArrowText:SetTextColor(ar, ag, ab, 1)
    rightArrow._text = rightArrowText

    -- Text input field (right of arrows)
    local inputFrame = CreateFrame("EditBox", nil, sliderContainer, "InputBoxTemplate")
    inputFrame:SetSize(inputWidth, SLIDER_HEIGHT)
    inputFrame:SetPoint("LEFT", rightArrow, "RIGHT", 8, 0)
    inputFrame:SetAutoFocus(false)
    inputFrame:SetNumeric(false)  -- Allow decimals
    inputFrame:SetMaxLetters(10)
    inputFrame:EnableMouse(true)

    -- Hide Blizzard's default InputBoxTemplate textures
    if inputFrame.Left then inputFrame.Left:Hide() end
    if inputFrame.Right then inputFrame.Right:Hide() end
    if inputFrame.Middle then inputFrame.Middle:Hide() end
    -- Also try legacy texture names
    local inputName = inputFrame:GetName()
    if inputName then
        local leftTex = _G[inputName .. "Left"]
        local rightTex = _G[inputName .. "Right"]
        local middleTex = _G[inputName .. "Middle"]
        if leftTex then leftTex:Hide() end
        if rightTex then rightTex:Hide() end
        if middleTex then middleTex:Hide() end
    end

    -- Style the input box for UI look
    local inputFont = theme:GetFont("VALUE")
    inputFrame:SetFont(inputFont, 12, "")
    inputFrame:SetTextColor(1, 1, 1, 1)
    inputFrame:SetJustifyH("CENTER")

    -- Set text insets and create custom border
    inputFrame:SetTextInsets(4, 4, 0, 0)

    -- Create custom border for input (replacing default look)
    local inputBorder = {}

    local inputTop = inputFrame:CreateTexture(nil, "BACKGROUND", nil, 1)
    inputTop:SetPoint("TOPLEFT", inputFrame, "TOPLEFT", -2, 2)
    inputTop:SetPoint("TOPRIGHT", inputFrame, "TOPRIGHT", 2, 2)
    inputTop:SetHeight(BORDER_WIDTH)
    inputTop:SetColorTexture(ar, ag, ab, 0.6)
    inputBorder.TOP = inputTop

    local inputBottom = inputFrame:CreateTexture(nil, "BACKGROUND", nil, 1)
    inputBottom:SetPoint("BOTTOMLEFT", inputFrame, "BOTTOMLEFT", -2, -2)
    inputBottom:SetPoint("BOTTOMRIGHT", inputFrame, "BOTTOMRIGHT", 2, -2)
    inputBottom:SetHeight(BORDER_WIDTH)
    inputBottom:SetColorTexture(ar, ag, ab, 0.6)
    inputBorder.BOTTOM = inputBottom

    local inputLeft = inputFrame:CreateTexture(nil, "BACKGROUND", nil, 1)
    inputLeft:SetPoint("TOPLEFT", inputFrame, "TOPLEFT", -2, 2 - BORDER_WIDTH)
    inputLeft:SetPoint("BOTTOMLEFT", inputFrame, "BOTTOMLEFT", -2, -2 + BORDER_WIDTH)
    inputLeft:SetWidth(BORDER_WIDTH)
    inputLeft:SetColorTexture(ar, ag, ab, 0.6)
    inputBorder.LEFT = inputLeft

    local inputRight = inputFrame:CreateTexture(nil, "BACKGROUND", nil, 1)
    inputRight:SetPoint("TOPRIGHT", inputFrame, "TOPRIGHT", 2, 2 - BORDER_WIDTH)
    inputRight:SetPoint("BOTTOMRIGHT", inputFrame, "BOTTOMRIGHT", 2, -2 + BORDER_WIDTH)
    inputRight:SetWidth(BORDER_WIDTH)
    inputRight:SetColorTexture(ar, ag, ab, 0.6)
    inputBorder.RIGHT = inputRight

    local inputBg = inputFrame:CreateTexture(nil, "BACKGROUND", nil, 0)
    inputBg:SetPoint("TOPLEFT", -2, 2)
    inputBg:SetPoint("BOTTOMRIGHT", 2, -2)
    inputBg:SetColorTexture(bgR, bgG, bgB, bgA)
    inputFrame._customBg = inputBg
    inputFrame._customBorder = inputBorder

    sliderContainer._inputFrame = inputFrame

    -- Optional end labels (tiny text under left/right of track)
    if hasEndLabels then
        if minLabel and minLabel ~= "" then
            local minLabelFS = trackFrame:CreateFontString(nil, "OVERLAY")
            local endLabelFont = theme:GetFont("VALUE")
            minLabelFS:SetFont(endLabelFont, SLIDER_END_LABEL_FONT_SIZE, "")
            minLabelFS:SetPoint("TOP", trackFrame, "BOTTOMLEFT", 0, -2)
            minLabelFS:SetText(minLabel)
            minLabelFS:SetTextColor(dimR, dimG, dimB, 0.8)
            trackFrame._minLabel = minLabelFS
        end

        if maxLabel and maxLabel ~= "" then
            local maxLabelFS = trackFrame:CreateFontString(nil, "OVERLAY")
            local endLabelFont = theme:GetFont("VALUE")
            maxLabelFS:SetFont(endLabelFont, SLIDER_END_LABEL_FONT_SIZE, "")
            maxLabelFS:SetPoint("TOP", trackFrame, "BOTTOMRIGHT", 0, -2)
            maxLabelFS:SetText(maxLabel)
            maxLabelFS:SetTextColor(dimR, dimG, dimB, 0.8)
            trackFrame._maxLabel = maxLabelFS
        end
    end

    sliderContainer._leftArrow = leftArrow
    sliderContainer._rightArrow = rightArrow
    sliderContainer._trackFrame = trackFrame
    row._sliderContainer = sliderContainer
    -- Store references for disabled state
    row._leftArrow = leftArrow
    row._rightArrow = rightArrow
    row._trackFrame = trackFrame
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
        local range = maxVal - minVal
        local percent = range > 0 and ((val - minVal) / range) or 0
        local trackWidth = sliderWidth - SLIDER_THUMB_WIDTH

        -- Position thumb
        local thumbX = percent * trackWidth + (SLIDER_THUMB_WIDTH / 2)
        thumb:ClearAllPoints()
        thumb:SetPoint("CENTER", trackFrame, "LEFT", thumbX, 0)

        -- Update fill width
        trackFill:SetWidth(math.max(1, thumbX))

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
        local r, g, b = theme:GetAccentColor()
        for _, tex in pairs(self._customBorder) do
            tex:SetColorTexture(r, g, b, 1)
        end
    end)

    inputFrame:HookScript("OnEditFocusLost", function(self)
        self:HighlightText(0, 0)
        local r, g, b = theme:GetAccentColor()
        for _, tex in pairs(self._customBorder) do
            tex:SetColorTexture(r, g, b, 0.6)
        end
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
        -- Update row border
        if row._rowBorder then
            row._rowBorder:SetColorTexture(r, g, b, 0.2)
        end
        -- Update hover bg
        if row._hoverBg then
            row._hoverBg:SetColorTexture(r, g, b, 0.08)
        end
        -- Update arrows
        if leftArrow._text then
            leftArrow._text:SetTextColor(r, g, b, 1)
        end
        if rightArrow._text then
            rightArrow._text:SetTextColor(r, g, b, 1)
        end
        -- Update track
        if trackFrame._trackBg then
            trackFrame._trackBg:SetColorTexture(r, g, b, 0.2)
        end
        if trackFrame._trackFill then
            trackFrame._trackFill:SetColorTexture(r, g, b, 0.6)
        end
        -- Update thumb
        if thumb._bg and not thumb._isDragging then
            thumb._bg:SetColorTexture(r, g, b, 1)
        end
        -- Update input border
        if inputFrame._customBorder then
            local alpha = inputFrame:HasFocus() and 1 or 0.6
            for _, tex in pairs(inputFrame._customBorder) do
                tex:SetColorTexture(r, g, b, alpha)
            end
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
