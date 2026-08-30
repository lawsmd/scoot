-- DualSlider.lua - Two compact sliders side-by-side for X/Y offset pairs
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

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

local BORDER_WIDTH = 2
local DUAL_SLIDER_TRACK_WIDTH = 70
local DUAL_SLIDER_INPUT_WIDTH = 36
local DUAL_SLIDER_ARROW_WIDTH = 16
local DUAL_SLIDER_ARROW_GAP = 0
local DUAL_SLIDER_INPUT_GAP = 6
local DUAL_SLIDER_GROUP_GAP = 20
local DUAL_SLIDER_AXIS_LABEL_HEIGHT = 14
local DUAL_SLIDER_ROW_HEIGHT = 52           -- With axis labels on top
local DUAL_SLIDER_ROW_HEIGHT_WITH_LABELS = 68  -- With axis labels AND end labels
local DUAL_SLIDER_PADDING = 12
local DUAL_SLIDER_THUMB_WIDTH = 10
local DUAL_SLIDER_THUMB_HEIGHT = 16
local DUAL_SLIDER_TRACK_HEIGHT = 4
local DUAL_SLIDER_SLIDER_HEIGHT = 18
local DUAL_SLIDER_END_LABEL_FONT_SIZE = 9

--------------------------------------------------------------------------------
-- DualSlider: Two compact sliders side-by-side for X/Y offset pairs
--------------------------------------------------------------------------------
-- Creates a dual slider control with:
--   - Two sliders (A and B) side-by-side
--   - Axis labels ("X", "Y") above each slider
--   - Left/right arrow buttons for increment/decrement
--   - Draggable slider tracks with thumbs
--   - Text input fields for direct value entry
--   - Optional tiny labels under each slider
--   - Label text on the left
--
-- Options table:
--   label         : Setting label text (string)
--   description   : Optional description text below (string)
--   sliderA       : Table with slider A options (see below)
--   sliderB       : Table with slider B options (see below)
--   parent        : Parent frame (required)
--   trackWidth    : Slider track width override (optional, default 70)
--   inputWidth    : Text input width override (optional, default 36)
--   debounceKey   : Unique key for debounce timer (optional)
--   onEditModeSync: Function(aVal, bVal) for Edit Mode sync (debounced)
--
-- Slider A/B options:
--   axisLabel     : Small prefix label (e.g., "X" or "Y")
--   min           : Minimum value (number, required)
--   max           : Maximum value (number, required)
--   step          : Step increment (number, default 1)
--   get           : Function returning current value
--   set           : Function(newValue) to save value
--   minLabel      : Optional tiny label under left end
--   maxLabel      : Optional tiny label under right end
--   precision     : Decimal places for display (number, default 0)
--------------------------------------------------------------------------------

function Controls:CreateDualSlider(options)
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
    local label = options.label or "Dual Slider"
    local description = options.description
    local sliderAOpts = options.sliderA or {}
    local sliderBOpts = options.sliderB or {}
    local trackWidth = options.trackWidth or DUAL_SLIDER_TRACK_WIDTH
    local inputWidth = options.inputWidth or DUAL_SLIDER_INPUT_WIDTH
    local name = options.name
    local isDisabledFn = options.disabled or options.isDisabled

    -- Edit Mode sync support
    local onEditModeSync = options.onEditModeSync
    local debounceDelay = options.debounceDelay or 0.2
    local debounceKey = options.debounceKey or ("DualSlider_" .. tostring({}))

    local hasDesc = description and description ~= ""
    local hasEndLabelsA = (sliderAOpts.minLabel and sliderAOpts.minLabel ~= "") or (sliderAOpts.maxLabel and sliderAOpts.maxLabel ~= "")
    local hasEndLabelsB = (sliderBOpts.minLabel and sliderBOpts.minLabel ~= "") or (sliderBOpts.maxLabel and sliderBOpts.maxLabel ~= "")
    local hasEndLabels = hasEndLabelsA or hasEndLabelsB

    -- Calculate row height (always has axis labels on top now)
    local rowHeight = hasEndLabels and DUAL_SLIDER_ROW_HEIGHT_WITH_LABELS or DUAL_SLIDER_ROW_HEIGHT

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
    row._hoverBg = Controls.AddHoverFill(row, { sublevel = Controls.SUBLEVEL_BG })

    -- Row border (subtle line below)
    local rowBorder = row:CreateTexture(nil, "BORDER", nil, -1)
    rowBorder:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    rowBorder:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
    rowBorder:SetHeight(1)
    rowBorder:SetColorTexture(ar, ag, ab, 0.2)
    row._rowBorder = rowBorder

    -- Calculate vertical offset for label positioning (center vertically)
    local labelYOffset = 0

    -- Label text (left side)
    local labelFS = row:CreateFontString(nil, "OVERLAY")
    local labelFont = theme:GetFont("LABEL")
    labelFS:SetFont(labelFont, 13, "")
    labelFS:SetPoint("LEFT", row, "LEFT", DUAL_SLIDER_PADDING, labelYOffset)
    labelFS:SetText(label)
    labelFS:SetTextColor(ar, ag, ab, 1)
    row._label = labelFS

    -- Calculate total width for both sliders
    -- Each slider: arrow + track + arrow + gap + input
    local singleSliderWidth = DUAL_SLIDER_ARROW_WIDTH + DUAL_SLIDER_ARROW_GAP + trackWidth + DUAL_SLIDER_ARROW_GAP + DUAL_SLIDER_ARROW_WIDTH + DUAL_SLIDER_INPUT_GAP + inputWidth
    local totalDualWidth = singleSliderWidth * 2 + DUAL_SLIDER_GROUP_GAP

    -- Dual slider container (right side)
    local dualContainer = CreateFrame("Frame", nil, row)
    local containerHeight = DUAL_SLIDER_AXIS_LABEL_HEIGHT + DUAL_SLIDER_SLIDER_HEIGHT + (hasEndLabels and 14 or 0)
    dualContainer:SetSize(totalDualWidth, containerHeight)
    dualContainer:SetPoint("RIGHT", row, "RIGHT", -DUAL_SLIDER_PADDING, hasEndLabels and -4 or 0)
    row._dualSliderContainer = dualContainer

    -- Helper function to create a single mini-slider within the dual container
    local function CreateMiniSlider(sliderOpts, anchorFrame, anchorPoint, xOffset)
        local miniSlider = CreateFrame("Frame", nil, dualContainer)
        miniSlider:SetSize(singleSliderWidth, containerHeight)

        if anchorFrame then
            miniSlider:SetPoint("LEFT", anchorFrame, anchorPoint, xOffset, 0)
        else
            miniSlider:SetPoint("LEFT", dualContainer, "LEFT", 0, 0)
        end

        local axisLabel = sliderOpts.axisLabel or ""
        local minVal = sliderOpts.min or 0
        local maxVal = sliderOpts.max or 100
        local step = sliderOpts.step or 1
        local getValue = sliderOpts.get or function() return minVal end
        local setValue = sliderOpts.set or function() end
        local minLabel = sliderOpts.minLabel
        local maxLabel = sliderOpts.maxLabel
        local precision = sliderOpts.precision or 0
        local displayMultiplier = sliderOpts.displayMultiplier or 1
        local displaySuffix = sliderOpts.displaySuffix or ""

        local hasLabels = (minLabel and minLabel ~= "") or (maxLabel and maxLabel ~= "")

        -- Slider controls container (at bottom of miniSlider, full width)
        local controlsFrame = CreateFrame("Frame", nil, miniSlider)
        controlsFrame:SetSize(singleSliderWidth, DUAL_SLIDER_SLIDER_HEIGHT)
        controlsFrame:SetPoint("BOTTOMLEFT", miniSlider, "BOTTOMLEFT", 0, hasLabels and 14 or 0)

        -- Left arrow button (decrement)
        local leftArrow = CreateFrame("Button", nil, controlsFrame)
        leftArrow:SetSize(DUAL_SLIDER_ARROW_WIDTH, DUAL_SLIDER_SLIDER_HEIGHT)
        leftArrow:SetPoint("LEFT", controlsFrame, "LEFT", 0, 0)
        leftArrow:EnableMouse(true)
        leftArrow:RegisterForClicks("AnyUp")

        local leftArrowBg = leftArrow:CreateTexture(nil, "BACKGROUND", nil, -6)
        leftArrowBg:SetAllPoints()
        leftArrowBg:SetColorTexture(ar, ag, ab, 0)
        leftArrow._bg = leftArrowBg

        local leftArrowText = leftArrow:CreateFontString(nil, "OVERLAY")
        local arrowFont = theme:GetFont("BUTTON")
        leftArrowText:SetFont(arrowFont, 10, "")
        leftArrowText:SetPoint("CENTER", 0, 0)
        leftArrowText:SetText("<")
        leftArrowText:SetTextColor(ar, ag, ab, 1)
        leftArrow._text = leftArrowText

        miniSlider._leftArrow = leftArrow

        -- Track container
        local trackFrame = CreateFrame("Frame", nil, controlsFrame)
        trackFrame:SetSize(trackWidth, DUAL_SLIDER_SLIDER_HEIGHT)
        trackFrame:SetPoint("LEFT", leftArrow, "RIGHT", DUAL_SLIDER_ARROW_GAP, 0)

        -- Axis label ("X" or "Y") - centered above the track (not the input)
        local axisFS = miniSlider:CreateFontString(nil, "OVERLAY")
        local axisFont = theme:GetFont("VALUE")
        axisFS:SetFont(axisFont, 11, "")
        axisFS:SetPoint("BOTTOM", trackFrame, "TOP", 0, 2)
        axisFS:SetText(axisLabel)
        axisFS:SetTextColor(ar, ag, ab, 0.9)
        miniSlider._axisLabel = axisFS

        -- Track background
        local trackBg = trackFrame:CreateTexture(nil, "BACKGROUND", nil, -7)
        trackBg:SetHeight(DUAL_SLIDER_TRACK_HEIGHT)
        trackBg:SetPoint("LEFT", trackFrame, "LEFT", 0, 0)
        trackBg:SetPoint("RIGHT", trackFrame, "RIGHT", 0, 0)
        trackBg:SetColorTexture(ar, ag, ab, 0.2)
        trackFrame._trackBg = trackBg

        -- Track fill
        local trackFill = trackFrame:CreateTexture(nil, "BACKGROUND", nil, -6)
        trackFill:SetHeight(DUAL_SLIDER_TRACK_HEIGHT)
        trackFill:SetPoint("LEFT", trackFrame, "LEFT", 0, 0)
        trackFill:SetWidth(0)
        trackFill:SetColorTexture(ar, ag, ab, 0.6)
        trackFrame._trackFill = trackFill

        -- Thumb
        local thumb = CreateFrame("Button", nil, trackFrame)
        thumb:SetSize(DUAL_SLIDER_THUMB_WIDTH, DUAL_SLIDER_THUMB_HEIGHT)
        thumb:SetPoint("CENTER", trackFrame, "LEFT", 0, 0)
        thumb:EnableMouse(true)
        thumb:RegisterForDrag("LeftButton")

        local thumbBg = thumb:CreateTexture(nil, "ARTWORK", nil, 0)
        thumbBg:SetAllPoints()
        thumbBg:SetColorTexture(ar, ag, ab, 1)
        thumb._bg = thumbBg

        -- Thumb border
        thumb._border = Controls.CreateBorder(thumb, {
            layer = "ARTWORK",
            sublevel = 1,
            color = { 0, 0, 0, 0.5 },
        })
        trackFrame._thumb = thumb

        -- Right arrow button (increment)
        local rightArrow = CreateFrame("Button", nil, controlsFrame)
        rightArrow:SetSize(DUAL_SLIDER_ARROW_WIDTH, DUAL_SLIDER_SLIDER_HEIGHT)
        rightArrow:SetPoint("LEFT", trackFrame, "RIGHT", DUAL_SLIDER_ARROW_GAP, 0)
        rightArrow:EnableMouse(true)
        rightArrow:RegisterForClicks("AnyUp")

        local rightArrowBg = rightArrow:CreateTexture(nil, "BACKGROUND", nil, -6)
        rightArrowBg:SetAllPoints()
        rightArrowBg:SetColorTexture(ar, ag, ab, 0)
        rightArrow._bg = rightArrowBg

        local rightArrowText = rightArrow:CreateFontString(nil, "OVERLAY")
        rightArrowText:SetFont(arrowFont, 10, "")
        rightArrowText:SetPoint("CENTER", 0, 0)
        rightArrowText:SetText(">")
        rightArrowText:SetTextColor(ar, ag, ab, 1)
        rightArrow._text = rightArrowText

        miniSlider._rightArrow = rightArrow

        -- Text input
        local inputFrame = CreateFrame("EditBox", nil, controlsFrame, "InputBoxTemplate")
        inputFrame:SetSize(inputWidth, DUAL_SLIDER_SLIDER_HEIGHT)
        inputFrame:SetPoint("LEFT", rightArrow, "RIGHT", DUAL_SLIDER_INPUT_GAP, 0)
        inputFrame:SetAutoFocus(false)
        inputFrame:SetNumeric(false)
        inputFrame:SetMaxLetters(8)
        inputFrame:EnableMouse(true)

        -- Hide Blizzard's default InputBoxTemplate textures
        if inputFrame.Left then inputFrame.Left:Hide() end
        if inputFrame.Right then inputFrame.Right:Hide() end
        if inputFrame.Middle then inputFrame.Middle:Hide() end
        local inputName = inputFrame:GetName()
        if inputName then
            local leftTex = _G[inputName .. "Left"]
            local rightTex = _G[inputName .. "Right"]
            local middleTex = _G[inputName .. "Middle"]
            if leftTex then leftTex:Hide() end
            if rightTex then rightTex:Hide() end
            if middleTex then middleTex:Hide() end
        end

        -- Style input
        local inputFont = theme:GetFont("VALUE")
        inputFrame:SetFont(inputFont, 11, "")
        inputFrame:SetTextColor(1, 1, 1, 1)
        inputFrame:SetJustifyH("CENTER")
        inputFrame:SetTextInsets(2, 2, 0, 0)

        -- Custom input border
        local inputBorder = {}

        local inputTop = inputFrame:CreateTexture(nil, "BACKGROUND", nil, 1)
        inputTop:SetPoint("TOPLEFT", inputFrame, "TOPLEFT", -1, 1)
        inputTop:SetPoint("TOPRIGHT", inputFrame, "TOPRIGHT", 1, 1)
        inputTop:SetHeight(BORDER_WIDTH)
        inputTop:SetColorTexture(ar, ag, ab, 0.6)
        inputBorder.TOP = inputTop

        local inputBottom = inputFrame:CreateTexture(nil, "BACKGROUND", nil, 1)
        inputBottom:SetPoint("BOTTOMLEFT", inputFrame, "BOTTOMLEFT", -1, -1)
        inputBottom:SetPoint("BOTTOMRIGHT", inputFrame, "BOTTOMRIGHT", 1, -1)
        inputBottom:SetHeight(BORDER_WIDTH)
        inputBottom:SetColorTexture(ar, ag, ab, 0.6)
        inputBorder.BOTTOM = inputBottom

        local inputLeft = inputFrame:CreateTexture(nil, "BACKGROUND", nil, 1)
        inputLeft:SetPoint("TOPLEFT", inputFrame, "TOPLEFT", -1, 1 - BORDER_WIDTH)
        inputLeft:SetPoint("BOTTOMLEFT", inputFrame, "BOTTOMLEFT", -1, -1 + BORDER_WIDTH)
        inputLeft:SetWidth(BORDER_WIDTH)
        inputLeft:SetColorTexture(ar, ag, ab, 0.6)
        inputBorder.LEFT = inputLeft

        local inputRight = inputFrame:CreateTexture(nil, "BACKGROUND", nil, 1)
        inputRight:SetPoint("TOPRIGHT", inputFrame, "TOPRIGHT", 1, 1 - BORDER_WIDTH)
        inputRight:SetPoint("BOTTOMRIGHT", inputFrame, "BOTTOMRIGHT", 1, -1 + BORDER_WIDTH)
        inputRight:SetWidth(BORDER_WIDTH)
        inputRight:SetColorTexture(ar, ag, ab, 0.6)
        inputBorder.RIGHT = inputRight

        local inputBg = inputFrame:CreateTexture(nil, "BACKGROUND", nil, 0)
        inputBg:SetPoint("TOPLEFT", -1, 1)
        inputBg:SetPoint("BOTTOMRIGHT", 1, -1)
        inputBg:SetColorTexture(bgR, bgG, bgB, bgA)
        inputFrame._customBg = inputBg
        inputFrame._customBorder = inputBorder

        miniSlider._inputFrame = inputFrame
        miniSlider._trackFrame = trackFrame
        miniSlider._controlsFrame = controlsFrame

        -- Optional end labels (under the track)
        if hasLabels then
            if minLabel and minLabel ~= "" then
                local minLabelFS = trackFrame:CreateFontString(nil, "OVERLAY")
                local endLabelFont = theme:GetFont("VALUE")
                minLabelFS:SetFont(endLabelFont, DUAL_SLIDER_END_LABEL_FONT_SIZE, "")
                minLabelFS:SetPoint("TOP", trackFrame, "BOTTOMLEFT", 0, -2)
                minLabelFS:SetText(minLabel)
                minLabelFS:SetTextColor(dimR, dimG, dimB, 0.8)
                trackFrame._minLabel = minLabelFS
            end

            if maxLabel and maxLabel ~= "" then
                local maxLabelFS = trackFrame:CreateFontString(nil, "OVERLAY")
                local endLabelFont = theme:GetFont("VALUE")
                maxLabelFS:SetFont(endLabelFont, DUAL_SLIDER_END_LABEL_FONT_SIZE, "")
                maxLabelFS:SetPoint("TOP", trackFrame, "BOTTOMRIGHT", 0, -2)
                maxLabelFS:SetText(maxLabel)
                maxLabelFS:SetTextColor(dimR, dimG, dimB, 0.8)
                trackFrame._maxLabel = maxLabelFS
            end
        end

        -- State
        miniSlider._currentValue = minVal
        miniSlider._minVal = minVal
        miniSlider._maxVal = maxVal
        miniSlider._step = step
        miniSlider._precision = precision
        miniSlider._trackWidth = trackWidth

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

        -- Clamp value
        local function ClampValue(val)
            val = math.max(minVal, math.min(maxVal, val))
            val = math.floor((val - minVal) / step + 0.5) * step + minVal
            return math.max(minVal, math.min(maxVal, val))
        end
        miniSlider._clampValue = ClampValue

        -- Update display
        local function UpdateDisplay()
            local val = miniSlider._currentValue
            local range = maxVal - minVal
            local percent = range > 0 and ((val - minVal) / range) or 0
            local usableTrackWidth = trackWidth - DUAL_SLIDER_THUMB_WIDTH

            local thumbX = percent * usableTrackWidth + (DUAL_SLIDER_THUMB_WIDTH / 2)
            thumb:ClearAllPoints()
            thumb:SetPoint("CENTER", trackFrame, "LEFT", thumbX, 0)

            trackFill:SetWidth(math.max(1, thumbX))
            inputFrame:SetText(FormatValue(val))
        end
        miniSlider._updateDisplay = UpdateDisplay

        -- Initialize value
        miniSlider._currentValue = ClampValue(getValue() or minVal)
        UpdateDisplay()

        -- Re-assert the value box's text once the row has a rect -- see the
        -- long note in Slider.lua: an EditBox lays out at SetText time, so a
        -- row built before its pane's first layout pass stores the value but
        -- draws nothing. Clearing first forces the re-layout an identical
        -- SetText would skip.
        miniSlider._repaintInput = function()
            if not inputFrame or inputFrame:HasFocus() then return end
            inputFrame:SetText("")
            inputFrame:SetText(FormatValue(miniSlider._currentValue))
            inputFrame:SetCursorPosition(0)
        end

        -- Parse input value
        local function ParseInputValue(text)
            if displaySuffix ~= "" and text:sub(-#displaySuffix) == displaySuffix then
                text = text:sub(1, -#displaySuffix - 1)
            end
            local val = tonumber(text)
            if val and displayMultiplier ~= 0 then
                return val / displayMultiplier
            end
            return val
        end

        -- Store references for external use
        miniSlider._getValue = getValue
        miniSlider._setValue = setValue
        miniSlider._parseInputValue = ParseInputValue
        miniSlider._formatValue = FormatValue

        return miniSlider
    end

    -- Create slider A (left)
    local sliderA = CreateMiniSlider(sliderAOpts, nil, nil, 0)
    row._sliderA = sliderA

    -- Create slider B (right)
    local sliderB = CreateMiniSlider(sliderBOpts, sliderA, "RIGHT", DUAL_SLIDER_GROUP_GAP)
    row._sliderB = sliderB

    -- Both boxes repaint on the row's first laid-out frame and on any later
    -- show (collapsed section expanding, tab page switching in).
    local function RepaintInputs()
        if sliderA and sliderA._repaintInput then sliderA._repaintInput() end
        if sliderB and sliderB._repaintInput then sliderB._repaintInput() end
    end
    row._repaintInput = RepaintInputs
    C_Timer.After(0, RepaintInputs)
    row:SetScript("OnShow", RepaintInputs)

    -- State tracking
    row._isDisabled = false
    row._isDisabledFn = isDisabledFn

    -- Helper to check if either slider is sync locked
    local function IsSyncLocked()
        if debounceKey then
            return IsGlobalSyncLocked(debounceKey)
        end
        return row._syncLocked
    end

    -- Debounced Edit Mode sync helper
    local function TriggerDebouncedSync()
        if onEditModeSync then
            if debounceKey then
                SetGlobalSyncLock(debounceKey, {sliderA._currentValue, sliderB._currentValue})
            else
                row._syncLocked = true
            end

            Debounce(debounceKey, debounceDelay, function()
                onEditModeSync(sliderA._currentValue, sliderB._currentValue)
                if debounceKey then
                    ClearGlobalSyncLock(debounceKey)
                else
                    row._syncLocked = false
                end
            end)
        end
    end
    row._triggerDebouncedSync = TriggerDebouncedSync

    -- Setup interactions for a mini slider
    local function SetupMiniSliderInteraction(miniSlider)
        local trackFrame = miniSlider._trackFrame
        local thumb = trackFrame._thumb
        local inputFrame = miniSlider._inputFrame
        local leftArrow = miniSlider._leftArrow
        local rightArrow = miniSlider._rightArrow

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
            miniSlider._currentValue = miniSlider._clampValue(miniSlider._currentValue - miniSlider._step)
            miniSlider._setValue(miniSlider._currentValue)
            miniSlider._updateDisplay()
            TriggerDebouncedSync()
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        end)

        -- Right arrow click (increment)
        rightArrow:SetScript("OnClick", function(btn)
            if row._isDisabled or IsSyncLocked() then return end
            miniSlider._currentValue = miniSlider._clampValue(miniSlider._currentValue + miniSlider._step)
            miniSlider._setValue(miniSlider._currentValue)
            miniSlider._updateDisplay()
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
            dragStartValue = miniSlider._currentValue
        end)

        thumb:SetScript("OnDragStop", function(btn)
            btn._isDragging = false
            local r, g, b = theme:GetAccentColor()
            btn._bg:SetColorTexture(r, g, b, 1)
            miniSlider._setValue(miniSlider._currentValue)
            TriggerDebouncedSync()
        end)

        thumb:SetScript("OnUpdate", function(btn)
            if not btn._isDragging then return end

            local cursorX = GetCursorPosition()
            local scale = btn:GetEffectiveScale()
            cursorX = cursorX / scale

            local deltaX = cursorX - dragStartX
            local usableTrackWidth = miniSlider._trackWidth - DUAL_SLIDER_THUMB_WIDTH
            local range = miniSlider._maxVal - miniSlider._minVal

            if usableTrackWidth > 0 and range > 0 then
                local valueDelta = (deltaX / usableTrackWidth) * range
                miniSlider._currentValue = miniSlider._clampValue(dragStartValue + valueDelta)
                miniSlider._updateDisplay()
            end
        end)

        -- Track click
        trackFrame:EnableMouse(true)
        trackFrame:SetScript("OnMouseDown", function(frame, button)
            if button ~= "LeftButton" then return end
            if row._isDisabled or IsSyncLocked() then return end

            local cursorX = GetCursorPosition()
            local scale = frame:GetEffectiveScale()
            cursorX = cursorX / scale

            local frameLeft = frame:GetLeft() or 0
            local clickX = cursorX - frameLeft
            local usableTrackWidth = miniSlider._trackWidth - DUAL_SLIDER_THUMB_WIDTH
            local range = miniSlider._maxVal - miniSlider._minVal

            local percent = math.max(0, math.min(1, (clickX - DUAL_SLIDER_THUMB_WIDTH / 2) / usableTrackWidth))
            miniSlider._currentValue = miniSlider._clampValue(miniSlider._minVal + percent * range)
            miniSlider._setValue(miniSlider._currentValue)
            miniSlider._updateDisplay()
            TriggerDebouncedSync()
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        end)

        -- Input handlers
        inputFrame:SetScript("OnEnterPressed", function(self)
            if IsSyncLocked() then
                miniSlider._updateDisplay()
                self:ClearFocus()
                return
            end

            local text = self:GetText()
            local val = miniSlider._parseInputValue(text)
            if val then
                miniSlider._currentValue = miniSlider._clampValue(val)
                miniSlider._setValue(miniSlider._currentValue)
                TriggerDebouncedSync()
            end
            miniSlider._updateDisplay()
            self:ClearFocus()
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        end)

        inputFrame:SetScript("OnEscapePressed", function(self)
            miniSlider._updateDisplay()
            self:ClearFocus()
        end)

        inputFrame:SetScript("OnEditFocusLost", function(self)
            if IsSyncLocked() then
                miniSlider._updateDisplay()
                return
            end

            local text = self:GetText()
            local val = miniSlider._parseInputValue(text)
            if val then
                miniSlider._currentValue = miniSlider._clampValue(val)
                miniSlider._setValue(miniSlider._currentValue)
                TriggerDebouncedSync()
            end
            miniSlider._updateDisplay()
        end)

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
    end

    -- Setup interactions for both sliders
    SetupMiniSliderInteraction(sliderA)
    SetupMiniSliderInteraction(sliderB)

    -- Row hover
    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self)
        self._hoverBg:Show()
    end)
    row:SetScript("OnLeave", function(self)
        self._hoverBg:Hide()
    end)

    -- Theme subscription
    local subscribeKey = "DualSlider_" .. (name or tostring(row))
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
        -- Update both mini sliders
        for _, miniSlider in ipairs({row._sliderA, row._sliderB}) do
            if miniSlider then
                local trackFrame = miniSlider._trackFrame
                local inputFrame = miniSlider._inputFrame

                -- Update axis label
                if miniSlider._axisLabel then
                    miniSlider._axisLabel:SetTextColor(r, g, b, 0.9)
                end

                -- Update arrows
                if miniSlider._leftArrow and miniSlider._leftArrow._text then
                    miniSlider._leftArrow._text:SetTextColor(r, g, b, 1)
                end
                if miniSlider._rightArrow and miniSlider._rightArrow._text then
                    miniSlider._rightArrow._text:SetTextColor(r, g, b, 1)
                end

                if trackFrame then
                    if trackFrame._trackBg then
                        trackFrame._trackBg:SetColorTexture(r, g, b, 0.2)
                    end
                    if trackFrame._trackFill then
                        trackFrame._trackFill:SetColorTexture(r, g, b, 0.6)
                    end
                    if trackFrame._thumb and trackFrame._thumb._bg and not trackFrame._thumb._isDragging then
                        trackFrame._thumb._bg:SetColorTexture(r, g, b, 1)
                    end
                end

                if inputFrame and inputFrame._customBorder then
                    local alpha = inputFrame:HasFocus() and 1 or 0.6
                    for _, tex in pairs(inputFrame._customBorder) do
                        tex:SetColorTexture(r, g, b, alpha)
                    end
                end
            end
        end
    end)

    -- Public methods
    function row:SetValues(aValue, bValue)
        if self._sliderA then
            self._sliderA._currentValue = self._sliderA._clampValue(aValue)
            self._sliderA._updateDisplay()
        end
        if self._sliderB then
            self._sliderB._currentValue = self._sliderB._clampValue(bValue)
            self._sliderB._updateDisplay()
        end
    end

    function row:GetValues()
        local aVal = self._sliderA and self._sliderA._currentValue or 0
        local bVal = self._sliderB and self._sliderB._currentValue or 0
        return aVal, bVal
    end

    function row:Refresh()
        if self._sliderA then
            self._sliderA._currentValue = self._sliderA._clampValue(self._sliderA._getValue() or self._sliderA._minVal)
            self._sliderA._updateDisplay()
        end
        if self._sliderB then
            self._sliderB._currentValue = self._sliderB._clampValue(self._sliderB._getValue() or self._sliderB._minVal)
            self._sliderB._updateDisplay()
        end
        -- Check disabled state from function
        if self._isDisabledFn then
            local newDisabled = self._isDisabledFn() and true or false
            if newDisabled ~= self._isDisabled then
                self:SetDisabled(newDisabled)
            end
        end
    end

    function row:SetDisabled(disabled)
        self._isDisabled = disabled and true or false
        local disabledAlpha = 0.35
        local r, g, b = theme:GetAccentColor()
        local dR, dG, dB = theme:GetDimTextColor()

        if self._isDisabled then
            if self._label then self._label:SetTextColor(dR, dG, dB, disabledAlpha) end
            for _, miniSlider in ipairs({self._sliderA, self._sliderB}) do
                if miniSlider then
                    if miniSlider._axisLabel then miniSlider._axisLabel:SetAlpha(disabledAlpha) end
                    if miniSlider._leftArrow then miniSlider._leftArrow:SetAlpha(disabledAlpha) end
                    if miniSlider._rightArrow then miniSlider._rightArrow:SetAlpha(disabledAlpha) end
                    if miniSlider._trackFrame then miniSlider._trackFrame:SetAlpha(disabledAlpha) end
                    if miniSlider._inputFrame then
                        miniSlider._inputFrame:SetAlpha(disabledAlpha)
                        miniSlider._inputFrame:EnableMouse(false)
                    end
                end
            end
        else
            if self._label then self._label:SetTextColor(r, g, b, 1) end
            for _, miniSlider in ipairs({self._sliderA, self._sliderB}) do
                if miniSlider then
                    if miniSlider._axisLabel then miniSlider._axisLabel:SetAlpha(1) end
                    if miniSlider._leftArrow then miniSlider._leftArrow:SetAlpha(1) end
                    if miniSlider._rightArrow then miniSlider._rightArrow:SetAlpha(1) end
                    if miniSlider._trackFrame then miniSlider._trackFrame:SetAlpha(1) end
                    if miniSlider._inputFrame then
                        miniSlider._inputFrame:SetAlpha(1)
                        miniSlider._inputFrame:EnableMouse(true)
                    end
                end
            end
        end
    end

    function row:IsDisabled()
        return self._isDisabled
    end

    function row:Cleanup()
        if self._subscribeKey then
            theme:Unsubscribe(self._subscribeKey)
        end
        CancelDebounce(debounceKey)
    end

    row._debounceKey = debounceKey

    -- Initialize disabled state from function
    if isDisabledFn then
        row._isDisabled = isDisabledFn() and true or false
        if row._isDisabled then
            row:SetDisabled(true)
        end
    end

    return row
end
