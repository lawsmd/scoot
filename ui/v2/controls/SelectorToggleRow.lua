-- SelectorToggleRow.lua - Compact selector + toggle side-by-side in a single row
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
local MINI_TOGGLE_WIDTH = 70

--------------------------------------------------------------------------------
-- Helper: CreateMiniToggle
--------------------------------------------------------------------------------
-- The compact state box in a slot row: the pill with its hover fill, or the
-- skin's checkbox, through Controls.CreateToggleIndicator. Matches the height
-- of a mini-selector (28px). The frame carries _value, _isDisabled and
-- _updateVisual for the rows that drive it.
--------------------------------------------------------------------------------

local function CreateMiniToggle(opts, parentContainer, _, useLightDim)
    local getValue = opts.get or function() return false end
    local setValue = opts.set or function() end

    local indicator = Controls.CreateToggleIndicator(parentContainer, {
        width = MINI_TOGGLE_WIDTH,
        height = CONTROL_HEIGHT,
        fit = CONTROL_HEIGHT,
        clickable = true,
        hover = true,
        useLightDim = useLightDim,
    })
    local toggle = indicator.frame

    -- State
    toggle._value = getValue() or false
    toggle._isDisabled = false

    local function UpdateVisual()
        indicator:SetState(toggle._value, toggle._isDisabled)
    end
    toggle._updateVisual = UpdateVisual
    UpdateVisual()

    -- Click to toggle
    toggle:SetScript("OnClick", function(self)
        if self._isDisabled then return end
        self._value = not self._value
        setValue(self._value)
        UpdateVisual()
        PlaySound(self._value and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
    end)

    return toggle
end

-- Export for reuse by ToggleSliderRow
Controls._CreateMiniToggle = CreateMiniToggle

--------------------------------------------------------------------------------
-- SelectorToggleRow: Compact selector + toggle side-by-side
--------------------------------------------------------------------------------
-- Creates a row with:
--   - Label text on the left
--   - Mini-selector (left of container) — reuses DualSelector's CreateMiniSelector
--   - Mini-toggle (right of container) — compact ON/OFF indicator
--   - Optional mini-label above the toggle for context
--
-- Options:
--   label       : Row label text (left side, optional)
--   description : Optional description below label
--   selector    : Table with selector options (values, order, get, set)
--   toggle      : Table with toggle options (get, set, label)
--   parent      : Parent frame (required)
--   disabled    : Function returning disabled state (optional)
--   name        : Optional global frame name
--------------------------------------------------------------------------------

function Controls:CreateSelectorToggleRow(options)
    local override = Controls.SkinOverride("SelectorToggleRow", options)
    if override then return override end
    local theme = GetTheme()
    if not options or not options.parent then return nil end

    local parent = options.parent
    local label = options.label
    local description = options.description
    local selectorOpts = options.selector or {}
    local toggleOpts = options.toggle or {}
    local name = options.name
    local isDisabledFn = options.disabled or options.isDisabled
    local useLightDim = options.useLightDim

    local toggleLabel = toggleOpts.label
    -- Builder rows always pass rowWidth; the parent width is the fallback.
    local rowWidth = options.rowWidth or (parent:GetWidth() or 0)

    local dimR, dimG, dimB
    if useLightDim then
        dimR, dimG, dimB = theme:GetDimTextLightColor()
    else
        dimR, dimG, dimB = theme:GetDimTextColor()
    end

    -- Create the row frame
    local row = CreateFrame("Frame", name, parent)

    -- Row hover background
    row._hoverBg = Controls.AddHoverFill(row, { sublevel = Controls.SUBLEVEL_BG })

    -- Chrome, the selector slot, and the labeled toggle slot
    local container, slotFrames = Controls.BuildSlotRow(row, {
        rowWidth = rowWidth,
        label = label,
        description = description,
        dimColor = { dimR, dimG, dimB },
        slots = {
            { kind = "selector", need = Controls.MiniSelectorNeed(selectorOpts) },
            { kind = "toggle", label = toggleLabel },
        },
    })
    row._container = container
    row._toggleLabelFS = slotFrames[2]._miniLabel

    local CreateMiniSelector = Controls._CreateMiniSelector
    local miniSelector = CreateMiniSelector(selectorOpts, slotFrames[1], theme, useLightDim)
    miniSelector:SetAllPoints(slotFrames[1])
    row._selector = miniSelector

    local miniToggle = CreateMiniToggle(toggleOpts, slotFrames[2], theme, useLightDim)
    miniToggle:SetAllPoints(slotFrames[2])
    row._toggle = miniToggle

    -- State tracking
    row._isDisabled = false
    row._isDisabledFn = isDisabledFn

    -- Row hover
    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self)
        self._hoverBg:Show()
    end)
    row:SetScript("OnLeave", function(self)
        self._hoverBg:Hide()
    end)

    -- Theme subscription
    local subscribeKey = "SelectorToggleRow_" .. (name or tostring(row))
    row._subscribeKey = subscribeKey

    theme:Subscribe(subscribeKey, function(r, g, b)
        if row._label then row._label:SetTextColor(r, g, b, 1) end
        if row._toggleLabelFS then row._toggleLabelFS:SetTextColor(r, g, b, 0.5) end

        -- Update mini-selector
        local sel = row._selector
        if sel then
            if sel._leftSep then sel._leftSep:SetColorTexture(r, g, b, 0.4) end
            if sel._rightSep then sel._rightSep:SetColorTexture(r, g, b, 0.4) end
            if not sel._syncLocked then
                if sel._leftArrow and sel._leftArrow._text then
                    sel._leftArrow._text:SetTextColor(r, g, b, 1)
                end
                if sel._rightArrow and sel._rightArrow._text then
                    sel._rightArrow._text:SetTextColor(r, g, b, 1)
                end
            end
            if sel._dropdown and sel._dropdown.SetBackdropBorderColor then
                sel._dropdown:SetBackdropBorderColor(r, g, b, 0.8)
            end
        end

        -- Update mini-toggle
        if row._toggle and row._toggle._updateVisual then
            row._toggle._updateVisual()
        end
    end)

    -- Initialize disabled state
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
        if self._selector then
            local getA = selectorOpts.get or function() return nil end
            self._selector._currentKey = getA()
            self._selector._updateDisplay()
        end
        if self._toggle then
            local getB = toggleOpts.get or function() return false end
            self._toggle._value = getB() or false
            self._toggle._updateVisual()
        end
        if self._isDisabledFn then
            local newDisabled = self._isDisabledFn() and true or false
            if newDisabled ~= self._isDisabled then
                self:SetDisabled(newDisabled)
            end
        end
    end

    function row:SetDisabled(disabled)
        self._isDisabled = disabled and true or false
        local dR, dG, dB = theme:GetDimTextColor()
        local acR, acG, acB = theme:GetAccentColor()
        local da = 0.35

        if self._selector then self._selector._isDisabled = self._isDisabled end
        if self._toggle then
            self._toggle._isDisabled = self._isDisabled
            self._toggle._updateVisual()
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
        local sel = self._selector
        if sel then
            if sel._syncLockTimer then
                sel._syncLockTimer:Cancel()
            end
            if sel._dropdown then
                sel._dropdown:Destroy()
            end
        end
    end

    function row:GetDescriptionFontString()
        return self._description
    end

    return row
end
