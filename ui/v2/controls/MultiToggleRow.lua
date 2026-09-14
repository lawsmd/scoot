-- MultiToggleRow.lua - Several compact toggles side-by-side in a single row
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



--------------------------------------------------------------------------------
-- MultiToggleRow
--
-- Options:
--   parent      : Frame  - Parent frame (required)
--   label       : Row label text (left side, optional)
--   description : Optional explainer below the label
--   toggles     : Array of { key, label, get, set } (required, 1 or more)
--   disabled    : Function returning disabled state (optional)
--   name        : Optional global frame name
--
-- Unlike ToggleSliderRow the control column is a FIXED width computed from the
-- toggle count, so the description reservation below is exact rather than a
-- worst case, and the column never needs resizing after layout settles.
--------------------------------------------------------------------------------

function Controls:CreateMultiToggleRow(options)
    local theme = GetTheme()
    if not options or not options.parent then return nil end

    local toggleDefs = options.toggles
    if type(toggleDefs) ~= "table" or #toggleDefs == 0 then return nil end

    local parent = options.parent
    local label = options.label
    local description = options.description
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

    -- Chrome and one labeled toggle slot per definition
    local slots = {}
    for _, def in ipairs(toggleDefs) do
        table.insert(slots, { kind = "toggle", label = def.label })
    end
    local container, slotFrames = Controls.BuildSlotRow(row, {
        rowWidth = rowWidth,
        label = label,
        description = description,
        dimColor = { dimR, dimG, dimB },
        slots = slots,
    })
    row._container = container

    local CreateMiniToggle = Controls._CreateMiniToggle
    local toggles = {}
    row._toggles = toggles

    for i, def in ipairs(toggleDefs) do
        local miniToggle = CreateMiniToggle(def, slotFrames[i], theme, useLightDim)
        miniToggle:SetAllPoints(slotFrames[i])
        miniToggle._labelFS = slotFrames[i]._miniLabel

        -- The visual update runs BEFORE the setter, and the setter is isolated
        -- in a pcall. A setter that errors while applying must not leave the
        -- control looking dead: that reads as "the button is broken" rather
        -- than "the thing it drives is broken". Errors still reach the standard
        -- handler so they remain visible.
        local userSet = def.set
        miniToggle:SetScript("OnClick", function(self)
            if self._isDisabled then return end
            self._value = not self._value
            self._updateVisual()
            PlaySound(self._value and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
            if userSet then
                local ok, err = pcall(userSet, self._value)
                if not ok then geterrorhandler()(err) end
            end
        end)

        toggles[i] = miniToggle
    end

    row._isDisabled = false
    row._isDisabledFn = isDisabledFn

    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self) self._hoverBg:Show() end)
    row:SetScript("OnLeave", function(self) self._hoverBg:Hide() end)

    local subscribeKey = "MultiToggleRow_" .. (name or tostring(row))
    row._subscribeKey = subscribeKey

    theme:Subscribe(subscribeKey, function(r, g, b)
        if row._label then row._label:SetTextColor(r, g, b, 1) end
        for _, toggle in ipairs(row._toggles) do
            if toggle._updateVisual then toggle._updateVisual() end
        end
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
        for i, toggle in ipairs(self._toggles) do
            local def = toggleDefs[i]
            local getVal = def and def.get or function() return false end
            toggle._value = getVal() or false
            toggle._updateVisual()
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

        for _, toggle in ipairs(self._toggles) do
            toggle._isDisabled = self._isDisabled
            toggle._updateVisual()
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

    function row:GetToggle(key)
        for i, def in ipairs(toggleDefs) do
            if def.key == key then return self._toggles[i] end
        end
    end

    function row:Cleanup()
        if self._subscribeKey then
            theme:Unsubscribe(self._subscribeKey)
        end
    end

    function row:GetDescriptionFontString()
        return self._description
    end

    return row
end

return Controls
