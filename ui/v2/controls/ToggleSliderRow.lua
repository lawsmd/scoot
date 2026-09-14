-- ToggleSliderRow.lua - Compact toggle + slider side-by-side in a single row
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.Controls = addon.UI.Controls or {}
local Controls = addon.UI.Controls
local Theme

local function GetTheme()
    if not Theme then
        Theme = addon.UI.Theme
    end
    return Theme
end

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

local CONTROL_HEIGHT = 28
local GAP = 12

local TRACK_HEIGHT = 4
local THUMB_WIDTH = 10
local THUMB_HEIGHT = 16
local VALUE_WIDTH = 42


--------------------------------------------------------------------------------
-- Helper: CreateMiniSlider
--------------------------------------------------------------------------------
-- A compact draggable slider with a numeric readout on its right. Deliberately
-- lighter than Slider.lua / DualSlider.lua: no arrows, no edit box, no Edit Mode
-- sync. This row is for a single bounded percentage, so a track plus a readout
-- is the whole interaction.
--------------------------------------------------------------------------------

local function CreateMiniSlider(opts, parentContainer, theme, useLightDim)
    local getValue = opts.get or function() return 0 end
    local setValue = opts.set or function() end
    local minVal = tonumber(opts.min) or 0
    local maxVal = tonumber(opts.max) or 100
    local step = tonumber(opts.step) or 1
    local suffix = opts.suffix or ""

    if maxVal <= minVal then maxVal = minVal + 1 end

    local ar, ag, ab = theme:GetAccentColor()
    local dimR, dimG, dimB
    if useLightDim then
        dimR, dimG, dimB = theme:GetDimTextLightColor()
    else
        dimR, dimG, dimB = theme:GetDimTextColor()
    end

    local slider = CreateFrame("Frame", nil, parentContainer)
    slider:SetHeight(CONTROL_HEIGHT)

    -- Numeric readout (right edge)
    local valueFS = slider:CreateFontString(nil, "OVERLAY")
    valueFS:SetFont(theme:GetFont("VALUE"), 11, "")
    valueFS:SetPoint("RIGHT", slider, "RIGHT", 0, 0)
    valueFS:SetWidth(VALUE_WIDTH)
    valueFS:SetJustifyH("RIGHT")
    valueFS:SetTextColor(ar, ag, ab, 1)
    slider._valueFS = valueFS

    -- Track (fills the space left of the readout)
    local track = slider:CreateTexture(nil, "ARTWORK")
    track:SetHeight(TRACK_HEIGHT)
    track:SetPoint("LEFT", slider, "LEFT", 0, 0)
    track:SetPoint("RIGHT", valueFS, "LEFT", -GAP, 0)
    track:SetColorTexture(ar, ag, ab, 0.25)
    slider._track = track

    -- Filled portion
    local fill = slider:CreateTexture(nil, "ARTWORK", nil, 1)
    fill:SetHeight(TRACK_HEIGHT)
    fill:SetPoint("LEFT", track, "LEFT", 0, 0)
    fill:SetColorTexture(ar, ag, ab, 0.9)
    slider._fill = fill

    -- Thumb
    local thumb = slider:CreateTexture(nil, "OVERLAY")
    thumb:SetSize(THUMB_WIDTH, THUMB_HEIGHT)
    thumb:SetColorTexture(ar, ag, ab, 1)
    slider._thumb = thumb

    slider._value = tonumber(getValue()) or minVal
    slider._isDisabled = false

    local function Clamp(v)
        if v < minVal then return minVal end
        if v > maxVal then return maxVal end
        return v
    end

    local function Snap(v)
        if step <= 0 then return v end
        return math.floor((v - minVal) / step + 0.5) * step + minVal
    end

    local function UpdateVisual()
        local trackWidth = track:GetWidth() or 0
        local pct = (slider._value - minVal) / (maxVal - minVal)
        if pct < 0 then pct = 0 elseif pct > 1 then pct = 1 end

        if trackWidth > 0 then
            local filled = trackWidth * pct
            if filled < 1 then
                fill:Hide()
            else
                fill:Show()
                fill:SetWidth(filled)
            end
            thumb:ClearAllPoints()
            thumb:SetPoint("CENTER", track, "LEFT", filled, 0)
        end

        valueFS:SetText(tostring(math.floor(slider._value + 0.5)) .. suffix)

        local a = slider._isDisabled and 0.35 or 1
        local r, g, b = theme:GetAccentColor()
        local dR, dG, dB = theme:GetDimTextColor()
        if slider._isDisabled then
            track:SetColorTexture(dR, dG, dB, 0.2 * a)
            fill:SetColorTexture(dR, dG, dB, 0.5)
            thumb:SetColorTexture(dR, dG, dB, 0.5)
            valueFS:SetTextColor(dR, dG, dB, a)
        else
            track:SetColorTexture(r, g, b, 0.25)
            fill:SetColorTexture(r, g, b, 0.9)
            thumb:SetColorTexture(r, g, b, 1)
            valueFS:SetTextColor(r, g, b, 1)
        end
    end
    slider._updateVisual = UpdateVisual

    -- Track width is not known until layout settles.
    C_Timer.After(0, UpdateVisual)

    local function ValueFromCursor()
        local trackWidth = track:GetWidth() or 0
        if trackWidth <= 0 then return slider._value end
        local scale = track:GetEffectiveScale()
        if not scale or scale <= 0 then return slider._value end
        local cursorX = GetCursorPosition() / scale
        local left = track:GetLeft()
        if not left then return slider._value end
        local pct = (cursorX - left) / trackWidth
        if pct < 0 then pct = 0 elseif pct > 1 then pct = 1 end
        return Clamp(Snap(minVal + pct * (maxVal - minVal)))
    end

    local function CommitFromCursor()
        local newValue = ValueFromCursor()
        if newValue ~= slider._value then
            slider._value = newValue
            UpdateVisual()
            -- Same reasoning as the toggle: paint first, then apply, and never
            -- let a throwing setter freeze the control mid-drag.
            local ok, err = pcall(setValue, newValue)
            if not ok then geterrorhandler()(err) end
        end
    end

    -- A transparent button over the track region handles click + drag.
    local hit = CreateFrame("Button", nil, slider)
    hit:SetPoint("TOPLEFT", track, "TOPLEFT", -THUMB_WIDTH / 2, THUMB_HEIGHT / 2)
    hit:SetPoint("BOTTOMRIGHT", track, "BOTTOMRIGHT", THUMB_WIDTH / 2, -THUMB_HEIGHT / 2)
    hit:RegisterForClicks("LeftButtonDown", "LeftButtonUp")
    slider._hit = hit

    hit:SetScript("OnMouseDown", function()
        if slider._isDisabled then return end
        slider._dragging = true
        CommitFromCursor()
        hit:SetScript("OnUpdate", function()
            if slider._dragging then
                CommitFromCursor()
            end
        end)
    end)

    local function StopDrag()
        if not slider._dragging then return end
        slider._dragging = false
        hit:SetScript("OnUpdate", nil)
    end

    hit:SetScript("OnMouseUp", StopDrag)
    hit:SetScript("OnHide", StopDrag)

    hit:SetScript("OnEnter", function()
        if not slider._isDisabled then
            local r, g, b = theme:GetAccentColor()
            thumb:SetColorTexture(r, g, b, 1)
            thumb:SetSize(THUMB_WIDTH + 2, THUMB_HEIGHT + 2)
        end
    end)
    hit:SetScript("OnLeave", function()
        thumb:SetSize(THUMB_WIDTH, THUMB_HEIGHT)
    end)

    return slider
end

Controls._CreateMiniSlider = CreateMiniSlider

--------------------------------------------------------------------------------
-- ToggleSliderRow: Compact toggle + slider side-by-side
--------------------------------------------------------------------------------
-- Creates a row with:
--   - Label text on the left
--   - Mini-toggle (left of container) — compact ON/OFF indicator
--   - Mini-slider (right of container) — track + numeric readout
--   - Optional mini-labels above each control for context
--
-- The slider is disabled automatically whenever the toggle is OFF, since the
-- pairing exists to express "enable this, and how strongly".
--
-- Options:
--   label       : Row label text (left side, optional)
--   description : Optional description below label
--   toggle      : Table with toggle options (get, set, label)
--   slider      : Table with slider options (get, set, min, max, step, suffix, label)
--   parent      : Parent frame (required)
--   disabled    : Function returning disabled state (optional)
--   name        : Optional global frame name
--------------------------------------------------------------------------------

function Controls:CreateToggleSliderRow(options)
    local theme = GetTheme()
    if not options or not options.parent then return nil end

    local parent = options.parent
    local label = options.label
    local description = options.description
    local toggleOpts = options.toggle or {}
    local sliderOpts = options.slider or {}
    local name = options.name
    local isDisabledFn = options.disabled or options.isDisabled
    local useLightDim = options.useLightDim

    local toggleLabel = toggleOpts.label
    local sliderLabel = sliderOpts.label
    -- Builder rows always pass rowWidth; the parent width is the fallback.
    local rowWidth = options.rowWidth or (parent:GetWidth() or 0)

    local dimR, dimG, dimB
    if useLightDim then
        dimR, dimG, dimB = theme:GetDimTextLightColor()
    else
        dimR, dimG, dimB = theme:GetDimTextColor()
    end

    local row = CreateFrame("Frame", name, parent)

    row._hoverBg = Controls.AddHoverFill(row, { sublevel = Controls.SUBLEVEL_BG })

    -- Chrome and the labeled toggle and slider slots
    local container, slotFrames = Controls.BuildSlotRow(row, {
        rowWidth = rowWidth,
        label = label,
        description = description,
        dimColor = { dimR, dimG, dimB },
        slots = {
            { kind = "toggle", label = toggleLabel },
            { kind = "slider", label = sliderLabel },
        },
    })
    row._container = container
    row._toggleLabelFS = slotFrames[1]._miniLabel
    row._sliderLabelFS = slotFrames[2]._miniLabel

    local CreateMiniToggle = Controls._CreateMiniToggle
    local miniToggle = CreateMiniToggle(toggleOpts, slotFrames[1], theme, useLightDim)
    miniToggle:SetAllPoints(slotFrames[1])
    row._toggle = miniToggle

    local miniSlider = CreateMiniSlider(sliderOpts, slotFrames[2], theme, useLightDim)
    miniSlider:SetAllPoints(slotFrames[2])
    row._slider = miniSlider

    -- The slider follows the toggle: off means nothing to tune.
    local function SyncSliderEnabled()
        local off = not miniToggle._value
        miniSlider._isDisabled = row._isDisabled or off
        if miniSlider._updateVisual then
            miniSlider._updateVisual()
        end
    end
    row._syncSliderEnabled = SyncSliderEnabled

    -- Wrap the toggle's setter so flipping it re-evaluates the slider.
    --
    -- The visual update runs BEFORE the setter, and the setter is isolated in a
    -- pcall. A component that errors while applying must not leave the control
    -- looking dead -- that reads as "the button is broken" rather than "the
    -- thing it drives is broken". Errors are forwarded to the standard handler
    -- so BugSack still catches them.
    local userToggleSet = toggleOpts.set
    miniToggle:SetScript("OnClick", function(self)
        if self._isDisabled then return end
        self._value = not self._value
        self._updateVisual()
        SyncSliderEnabled()
        PlaySound(self._value and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
        if userToggleSet then
            local ok, err = pcall(userToggleSet, self._value)
            if not ok then geterrorhandler()(err) end
        end
    end)

    SyncSliderEnabled()

    row._isDisabled = false
    row._isDisabledFn = isDisabledFn

    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self) self._hoverBg:Show() end)
    row:SetScript("OnLeave", function(self) self._hoverBg:Hide() end)

    local subscribeKey = "ToggleSliderRow_" .. (name or tostring(row))
    row._subscribeKey = subscribeKey

    theme:Subscribe(subscribeKey, function(r, g, b)
        if row._label then row._label:SetTextColor(r, g, b, 1) end
        if row._toggle and row._toggle._updateVisual then row._toggle._updateVisual() end
        if row._slider and row._slider._updateVisual then row._slider._updateVisual() end
    end)

    if isDisabledFn then
        row._isDisabled = isDisabledFn() and true or false
        if row._isDisabled then
            C_Timer.After(0, function()
                if row and row.SetDisabled then
                    row:SetDisabled(true)
                end
            end)
        end
    end

    -- Public methods

    function row:Refresh()
        if self._toggle then
            local getT = toggleOpts.get or function() return false end
            self._toggle._value = getT() or false
            self._toggle._updateVisual()
        end
        if self._slider then
            local getS = sliderOpts.get or function() return 0 end
            self._slider._value = tonumber(getS()) or 0
            self._slider._updateVisual()
        end
        if self._isDisabledFn then
            local newDisabled = self._isDisabledFn() and true or false
            if newDisabled ~= self._isDisabled then
                self:SetDisabled(newDisabled)
            end
        end
        if self._syncSliderEnabled then
            self._syncSliderEnabled()
        end
    end

    function row:SetDisabled(disabled)
        self._isDisabled = disabled and true or false
        local dR, dG, dB = theme:GetDimTextColor()
        local acR, acG, acB = theme:GetAccentColor()
        local da = 0.35

        if self._toggle then
            self._toggle._isDisabled = self._isDisabled
            self._toggle._updateVisual()
        end
        if self._syncSliderEnabled then
            self._syncSliderEnabled()
        end

        if self._isDisabled then
            if self._label then self._label:SetTextColor(dR, dG, dB, da) end
            if self._description then self._description:SetAlpha(da) end
            if self._container then self._container:SetAlpha(da) end
        else
            if self._label then self._label:SetTextColor(acR, acG, acB, 1) end
            if self._description then self._description:SetAlpha(1) end
            if self._container then self._container:SetAlpha(1) end
        end
    end

    function row:IsDisabled()
        return self._isDisabled
    end

    function row:SetLabel(newLabel)
        if self._label then self._label:SetText(newLabel) end
    end

    function row:Cleanup()
        if self._subscribeKey then
            theme:Unsubscribe(self._subscribeKey)
        end
        if self._slider and self._slider._hit then
            self._slider._hit:SetScript("OnUpdate", nil)
        end
    end

    function row:GetDescriptionFontString()
        return self._description
    end

    return row
end
