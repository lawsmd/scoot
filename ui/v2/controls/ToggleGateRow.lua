-- ToggleGateRow.lua - A toggle that gates a toggle and a selector on one row
local _, addon = ...

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
-- ToggleGateRow: a gate toggle, then a toggle and a selector it greys out
--------------------------------------------------------------------------------
-- Creates a row with:
--   - Label text on the left, the gate's own name
--   - Mini-toggle, the gate
--   - Mini-toggle and mini-selector, each with an optional mini-label above,
--     both greyed out while the gate is closed
--
-- The pairing expresses "this, or else that and how": the gated pair is
-- live only while the gate is off (gateOpen "off", the default) or only
-- while it is on (gateOpen "on"). The row's own disabled state covers all
-- three.
--
-- Options:
--   label       : Row label text (left side, optional)
--   description : Optional description below label
--   gate        : Table with toggle options (get, set, label)
--   toggle      : Table with toggle options (get, set, label)
--   selector    : Table with selector options (values, order, get, set, label)
--   gateOpen    : "off" (default) or "on": the gate state that frees the pair
--   parent      : Parent frame (required)
--   disabled    : Function returning disabled state (optional)
--   name        : Optional global frame name
--------------------------------------------------------------------------------

-- Called with a colon as every row factory is; the receiver is unused, and
-- naming it keeps the row's own methods below from shadowing a self.
function Controls.CreateToggleGateRow(_, options)
    local override = Controls.SkinOverride("ToggleGateRow", options)
    if override then return override end
    local theme = GetTheme()
    if not options or not options.parent then return nil end

    local parent = options.parent
    local label = options.label
    local description = options.description
    local gateOpts = options.gate or {}
    local toggleOpts = options.toggle or {}
    local selectorOpts = options.selector or {}
    local openWhenOn = options.gateOpen == "on"
    local name = options.name
    local isDisabledFn = options.disabled or options.isDisabled
    local useLightDim = options.useLightDim
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

    -- Chrome and the three slots
    local container, slotFrames = Controls.BuildSlotRow(row, {
        rowWidth = rowWidth,
        label = label,
        description = description,
        dimColor = { dimR, dimG, dimB },
        slots = {
            { kind = "toggle", label = gateOpts.label },
            { kind = "toggle", label = toggleOpts.label },
            { kind = "selector", label = selectorOpts.label, need = Controls.MiniSelectorNeed(selectorOpts) },
        },
    })
    row._container = container
    row._toggleLabelFS = slotFrames[2]._miniLabel

    local CreateMiniToggle = Controls._CreateMiniToggle
    local gate = CreateMiniToggle(gateOpts, slotFrames[1], theme, useLightDim)
    gate:SetAllPoints(slotFrames[1])
    row._gate = gate

    local toggle = CreateMiniToggle(toggleOpts, slotFrames[2], theme, useLightDim)
    toggle:SetAllPoints(slotFrames[2])
    row._toggle = toggle

    -- The pair is closed while the gate stands in the state that closes it.
    local function PairClosed()
        return (gate._value and true or false) ~= openWhenOn
    end

    -- The selector's own disable reads the gate, so its field and caption
    -- dim beside the toggle while the row itself stays live; a disable the
    -- caller gave it still counts.
    local ownDisabled = selectorOpts.disabled
    local selectorBuild = {}
    for k, v in pairs(selectorOpts) do selectorBuild[k] = v end
    selectorBuild.disabled = function()
        if PairClosed() then return true end
        if type(ownDisabled) == "function" then return ownDisabled() and true or false end
        return ownDisabled and true or false
    end
    local selector = Controls._CreateMiniSelector(selectorBuild, slotFrames[3], theme, useLightDim)
    selector:SetAllPoints(slotFrames[3])
    row._selector = selector

    -- The pair follows the gate.
    local da = 0.35
    local function SyncPair()
        local closed = PairClosed()
        toggle._isDisabled = row._isDisabled or closed
        toggle._updateVisual()
        if row._toggleLabelFS then
            row._toggleLabelFS:SetAlpha((closed and not row._isDisabled) and da or 1)
        end
        if selector._applyDisabled then
            selector._applyDisabled(row._isDisabled)
        end
    end
    row._syncPair = SyncPair

    -- Each toggle's setter is wrapped so the pair re-evaluates on a flip.
    -- The visual update runs BEFORE the setter, and the setter is isolated
    -- in a pcall: a component that errors while applying must not leave the
    -- control looking dead. Errors go to the standard handler.
    local function WrapClick(mini, opts)
        local userSet = opts.set
        mini:SetScript("OnClick", function(self)
            if self._isDisabled then return end
            self._value = not self._value
            self._updateVisual()
            SyncPair()
            PlaySound(self._value and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
            if userSet then
                local ok, err = pcall(userSet, self._value)
                if not ok then geterrorhandler()(err) end
            end
        end)
    end
    WrapClick(gate, gateOpts)
    WrapClick(toggle, toggleOpts)

    row._isDisabled = false
    row._isDisabledFn = isDisabledFn
    SyncPair()

    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self) self._hoverBg:Show() end)
    row:SetScript("OnLeave", function(self) self._hoverBg:Hide() end)

    local subscribeKey = "ToggleGateRow_" .. (name or tostring(row))
    row._subscribeKey = subscribeKey

    theme:Subscribe(subscribeKey, function(r, g, b)
        if row._label then row._label:SetTextColor(r, g, b, 1) end
        if row._toggleLabelFS then row._toggleLabelFS:SetTextColor(r, g, b, 0.5) end
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
        if row._gate and row._gate._updateVisual then row._gate._updateVisual() end
        if row._toggle and row._toggle._updateVisual then row._toggle._updateVisual() end
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
        if self._gate then
            local getG = gateOpts.get or function() return false end
            self._gate._value = getG() and true or false
            self._gate._updateVisual()
        end
        if self._toggle then
            local getT = toggleOpts.get or function() return false end
            self._toggle._value = getT() and true or false
            self._toggle._updateVisual()
        end
        if self._selector then
            local getS = selectorOpts.get or function() return nil end
            self._selector._currentKey = getS()
            self._selector._updateDisplay()
        end
        if self._isDisabledFn then
            local newDisabled = self._isDisabledFn() and true or false
            if newDisabled ~= self._isDisabled then
                self:SetDisabled(newDisabled)
            end
        end
        if self._syncPair then
            self._syncPair()
        end
    end

    function row:SetDisabled(disabled)
        self._isDisabled = disabled and true or false
        local dR, dG, dB = theme:GetDimTextColor()
        local acR, acG, acB = theme:GetAccentColor()

        if self._gate then
            self._gate._isDisabled = self._isDisabled
            self._gate._updateVisual()
        end
        if self._syncPair then
            self._syncPair()
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
