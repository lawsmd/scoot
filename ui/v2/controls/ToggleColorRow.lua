-- ToggleColorRow.lua - Compact toggle + color swatch side-by-side in a single row
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

local function ReadColor(getColor)
    local result = { getColor() }
    if type(result[1]) == "table" then
        local c = result[1]
        return c.r or c[1] or 1, c.g or c[2] or 1, c.b or c[3] or 1, c.a or c[4] or 1
    end
    return result[1] or 1, result[2] or 1, result[3] or 1, result[4] or 1
end

--------------------------------------------------------------------------------
-- Helper: CreateMiniSwatch
--------------------------------------------------------------------------------
-- A color swatch that fills its slot and opens the color picker on click. A
-- gray ground shows through a translucent color.
--------------------------------------------------------------------------------

local function CreateMiniSwatch(opts, parentContainer)
    local getColor = opts.get or function() return 1, 1, 1, 1 end
    local setColor = opts.set or function() end
    local hasAlpha = opts.hasAlpha ~= false
    local inset = Controls.Metrics().borderWidth

    local swatch = CreateFrame("Button", nil, parentContainer)
    swatch:EnableMouse(true)
    swatch:RegisterForClicks("AnyUp")

    swatch._border = Controls.CreateBorder(swatch, {
        thickness = inset,
        getAlpha = function(self) return self:IsMouseOver() and 1 or 0.8 end,
    })

    local ground = swatch:CreateTexture(nil, "BACKGROUND", nil, -7)
    ground:SetPoint("TOPLEFT", inset, -inset)
    ground:SetPoint("BOTTOMRIGHT", -inset, inset)
    ground:SetColorTexture(0.3, 0.3, 0.3, 1)

    local colorFill = swatch:CreateTexture(nil, "ARTWORK")
    colorFill:SetPoint("TOPLEFT", inset, -inset)
    colorFill:SetPoint("BOTTOMRIGHT", -inset, inset)

    swatch._isDisabled = false

    local function UpdateVisual()
        local r, g, b, a = ReadColor(getColor)
        colorFill:SetColorTexture(r, g, b, hasAlpha and a or 1)
        swatch:SetAlpha(swatch._isDisabled and 0.35 or 1)
    end
    swatch._updateVisual = UpdateVisual
    UpdateVisual()

    swatch:SetScript("OnEnter", function(self) self._border:Refresh() end)
    swatch:SetScript("OnLeave", function(self) self._border:Refresh() end)

    swatch:SetScript("OnClick", function()
        if swatch._isDisabled then return end
        local curR, curG, curB, curA = ReadColor(getColor)

        ColorPickerFrame:SetupColorPickerAndShow({
            r = curR,
            g = curG,
            b = curB,
            hasOpacity = hasAlpha,
            opacity = curA,
            swatchFunc = function()
                local newR, newG, newB = ColorPickerFrame:GetColorRGB()
                local newA = hasAlpha and ColorPickerFrame:GetColorAlpha() or 1
                setColor(newR, newG, newB, newA)
                colorFill:SetColorTexture(newR, newG, newB, hasAlpha and newA or 1)
            end,
            cancelFunc = function(prev)
                if prev then
                    local pR, pG, pB, pA = prev.r or 1, prev.g or 1, prev.b or 1, prev.a or 1
                    setColor(pR, pG, pB, pA)
                    colorFill:SetColorTexture(pR, pG, pB, hasAlpha and pA or 1)
                end
            end,
        })
    end)

    return swatch
end

--------------------------------------------------------------------------------
-- ToggleColorRow: Compact toggle + color swatch side-by-side
--------------------------------------------------------------------------------
-- Creates a row with:
--   - Label text on the left
--   - Mini-toggle (left of container)
--   - Color swatch (right of container), as wide as the toggle
--   - Optional mini-labels above each control
--
-- The swatch is disabled whenever the toggle is OFF: the color belongs to the
-- thing the toggle turns on.
--
-- Options:
--   label       : Row label text (left side, optional)
--   description : Optional description below label
--   toggle      : Table with toggle options (get, set, label)
--   color       : Table with color options (get, set, label, hasAlpha); get
--                 returns {r, g, b, a} or r, g, b, a
--   parent      : Parent frame (required)
--   disabled    : Function returning disabled state (optional)
--   name        : Optional global frame name
--------------------------------------------------------------------------------

function Controls:CreateToggleColorRow(options)
    local override = Controls.SkinOverride("ToggleColorRow", options)
    if override then return override end
    local theme = GetTheme()
    if not options or not options.parent then return nil end

    local parent = options.parent
    local toggleOpts = options.toggle or {}
    local colorOpts = options.color or {}
    local name = options.name
    local isDisabledFn = options.disabled or options.isDisabled
    local useLightDim = options.useLightDim
    -- Builder rows always pass rowWidth; the parent width is the fallback.
    local rowWidth = options.rowWidth or (parent:GetWidth() or 0)
    local m = Controls.Metrics()

    local dimR, dimG, dimB
    if useLightDim then
        dimR, dimG, dimB = theme:GetDimTextLightColor()
    else
        dimR, dimG, dimB = theme:GetDimTextColor()
    end

    local row = CreateFrame("Frame", name, parent)

    row._hoverBg = Controls.AddHoverFill(row, { sublevel = Controls.SUBLEVEL_BG })

    -- The swatch slot takes the toggle's width, so the two controls match and
    -- the swatch's mini-label has room above it.
    local container, slotFrames = Controls.BuildSlotRow(row, {
        rowWidth = rowWidth,
        label = options.label,
        description = options.description,
        dimColor = { dimR, dimG, dimB },
        slots = {
            { kind = "toggle", label = toggleOpts.label },
            { kind = "swatch", label = colorOpts.label, width = m.slots.toggle },
        },
    })
    row._container = container

    local miniToggle = Controls._CreateMiniToggle(toggleOpts, slotFrames[1], theme, useLightDim)
    miniToggle:SetAllPoints(slotFrames[1])
    row._toggle = miniToggle

    local miniSwatch = CreateMiniSwatch(colorOpts, slotFrames[2])
    miniSwatch:SetAllPoints(slotFrames[2])
    row._swatch = miniSwatch

    local function SyncSwatchEnabled()
        miniSwatch._isDisabled = row._isDisabled or not miniToggle._value
        miniSwatch._updateVisual()
    end
    row._syncSwatchEnabled = SyncSwatchEnabled

    -- Paint first, then apply, with the setter isolated: a component that
    -- errors while applying must not leave the control looking dead.
    local userToggleSet = toggleOpts.set
    miniToggle:SetScript("OnClick", function(self)
        if self._isDisabled then return end
        self._value = not self._value
        self._updateVisual()
        SyncSwatchEnabled()
        PlaySound(self._value and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
        if userToggleSet then
            local ok, err = pcall(userToggleSet, self._value)
            if not ok then geterrorhandler()(err) end
        end
    end)

    row._isDisabled = false
    row._isDisabledFn = isDisabledFn
    SyncSwatchEnabled()

    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self) self._hoverBg:Show() end)
    row:SetScript("OnLeave", function(self) self._hoverBg:Hide() end)

    local subscribeKey = "ToggleColorRow_" .. (name or tostring(row))
    row._subscribeKey = subscribeKey

    theme:Subscribe(subscribeKey, function(r, g, b)
        if row._label and not row._isDisabled then row._label:SetTextColor(r, g, b, 1) end
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
        local getT = toggleOpts.get or function() return false end
        self._toggle._value = getT() or false
        self._toggle._updateVisual()
        if self._isDisabledFn then
            local newDisabled = self._isDisabledFn() and true or false
            if newDisabled ~= self._isDisabled then
                self:SetDisabled(newDisabled)
            end
        end
        self._syncSwatchEnabled()
    end

    function row:SetDisabled(disabled)
        self._isDisabled = disabled and true or false
        local dR, dG, dB = theme:GetDimTextColor()
        local acR, acG, acB = theme:GetAccentColor()
        local da = 0.35

        self._toggle._isDisabled = self._isDisabled
        self._toggle._updateVisual()
        self._syncSwatchEnabled()

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
    end

    function row:GetDescriptionFontString()
        return self._description
    end

    return row
end
