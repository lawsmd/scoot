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

local MINI_LABEL_HEIGHT = 14
local MINI_LABEL_GAP = 3
local CONTROL_HEIGHT = 28
local ROW_HEIGHT = 36 + MINI_LABEL_HEIGHT + MINI_LABEL_GAP
local ROW_HEIGHT_WITH_DESC = 80 + MINI_LABEL_HEIGHT + MINI_LABEL_GAP
local PADDING = 12
local GAP = 12
local MINI_TOGGLE_WIDTH = 70

-- Dynamic height, same contract as ToggleSliderRow.lua: the description gets
-- the row width MINUS the control column, then the row grows to whatever that
-- wrapping costs. DESC_PADDING_BOTTOM is doubled (36, not 18) because the label
-- is CENTER-anchored, so the description hangs below a block that stays centred
-- and needs its own slack at the bottom.
local MAX_ROW_HEIGHT = 200
local LABEL_LINE_HEIGHT = 16
local DESC_PADDING_TOP = 2
local DESC_PADDING_BOTTOM = 36

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

    local hasLabel = label and label ~= ""
    local hasDesc = description and description ~= ""
    local rowHeight = hasDesc and ROW_HEIGHT_WITH_DESC or ROW_HEIGHT

    local count = #toggleDefs
    local containerWidth = count * MINI_TOGGLE_WIDTH + (count - 1) * GAP

    local ar, ag, ab = theme:GetAccentColor()
    local dimR, dimG, dimB
    if useLightDim then
        dimR, dimG, dimB = theme:GetDimTextLightColor()
    else
        dimR, dimG, dimB = theme:GetDimTextColor()
    end

    local row = CreateFrame("Frame", name, parent)
    row:SetHeight(rowHeight)

    local hoverBg = row:CreateTexture(nil, "BACKGROUND", nil, -8)
    hoverBg:SetAllPoints()
    hoverBg:SetColorTexture(ar, ag, ab, 0.08)
    hoverBg:Hide()
    row._hoverBg = hoverBg

    local rowBorder = row:CreateTexture(nil, "BORDER", nil, -1)
    rowBorder:SetPoint("BOTTOMLEFT", 0, 0)
    rowBorder:SetPoint("BOTTOMRIGHT", 0, 0)
    rowBorder:SetHeight(1)
    rowBorder:SetColorTexture(ar, ag, ab, 0.2)
    row._rowBorder = rowBorder

    local labelFS
    if hasLabel then
        labelFS = row:CreateFontString(nil, "OVERLAY")
        labelFS:SetFont(theme:GetFont("LABEL"), 13, "")
        labelFS:SetPoint("LEFT", row, "LEFT", PADDING, hasDesc and 6 or 0)
        labelFS:SetText(label)
        labelFS:SetTextColor(ar, ag, ab, 1)
        row._label = labelFS
    end

    -- Static reservation for the control column. It holds even if the deferred
    -- measurement below never gets a width to work with, which is what keeps
    -- the wrapped explainer from ever reaching under the toggles.
    local CONTROL_RESERVE = PADDING + containerWidth + GAP

    if hasDesc and labelFS then
        local descFS = row:CreateFontString(nil, "OVERLAY")
        descFS:SetFont(theme:GetFont("VALUE"), 11, "")
        descFS:SetPoint("TOPLEFT", labelFS, "BOTTOMLEFT", 0, -DESC_PADDING_TOP)
        descFS:SetPoint("RIGHT", row, "RIGHT", -CONTROL_RESERVE, 0)
        descFS:SetText(description)
        descFS:SetTextColor(dimR, dimG, dimB, 1)
        descFS:SetJustifyH("LEFT")
        descFS:SetWordWrap(true)
        row._description = descFS

        -- Grow the row to fit the wrapped text. Immediate first: the builder
        -- reads GetHeight() the instant this returns, and a height that lands
        -- later would leave the rows below overlapping this one.
        local function MeasureAndAdjustHeight()
            if not row or not descFS then return false end

            local rowWidth = row:GetWidth()
            if rowWidth == 0 and row:GetParent() then
                rowWidth = row:GetParent():GetWidth() or 0
            end
            if rowWidth == 0 then return false end

            local descAvailableWidth = rowWidth - PADDING - CONTROL_RESERVE
            if descAvailableWidth <= 0 then return false end

            -- Explicit width first: GetStringHeight only reports the WRAPPED
            -- height once the FontString has one to wrap against.
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
        row._measureDesc = MeasureAndAdjustHeight

        if not MeasureAndAdjustHeight() then
            C_Timer.After(0.1, MeasureAndAdjustHeight)
        end
    end

    local containerHeight = MINI_LABEL_HEIGHT + MINI_LABEL_GAP + CONTROL_HEIGHT
    local container = CreateFrame("Frame", nil, row)
    container:SetSize(containerWidth, containerHeight)
    container:SetPoint("RIGHT", row, "RIGHT", -PADDING, 0)
    row._container = container

    local CreateMiniToggle = Controls._CreateMiniToggle
    local toggles = {}
    row._toggles = toggles

    for i, def in ipairs(toggleDefs) do
        local miniToggle = CreateMiniToggle(def, container, theme, useLightDim)

        if i == 1 then
            miniToggle:SetPoint("BOTTOMLEFT", container, "BOTTOMLEFT", 0, 0)
        else
            miniToggle:SetPoint("BOTTOMLEFT", toggles[i - 1], "BOTTOMRIGHT", GAP, 0)
        end

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

        -- Mini-labels sit centred over the control they name.
        if def.label and def.label ~= "" then
            local fs = container:CreateFontString(nil, "OVERLAY")
            fs:SetFont(theme:GetFont("VALUE"), 11, "")
            fs:SetPoint("BOTTOM", miniToggle, "TOP", 0, MINI_LABEL_GAP)
            fs:SetText(def.label)
            fs:SetTextColor(dimR, dimG, dimB, 0.8)
            miniToggle._labelFS = fs
        end

        toggles[i] = miniToggle
    end

    C_Timer.After(0, function()
        if not row or not row:GetParent() then return end
        -- Last chance for a row that had no width at creation: the description
        -- anchor already stops any overlap, this only recovers the height.
        if row._measureDesc then row._measureDesc() end
    end)

    row._isDisabled = false
    row._isDisabledFn = isDisabledFn

    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self) self._hoverBg:Show() end)
    row:SetScript("OnLeave", function(self) self._hoverBg:Hide() end)

    local subscribeKey = "MultiToggleRow_" .. (name or tostring(row))
    row._subscribeKey = subscribeKey

    theme:Subscribe(subscribeKey, function(r, g, b)
        if row._label then row._label:SetTextColor(r, g, b, 1) end
        if row._rowBorder then row._rowBorder:SetColorTexture(r, g, b, 0.2) end
        if row._hoverBg then row._hoverBg:SetColorTexture(r, g, b, 0.08) end
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
