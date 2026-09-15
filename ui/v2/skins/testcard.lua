-- testcard.lua - the throwaway proof skin for the skin seam. Different
-- palette, faces, sizes, and metrics than the tui default, plus one draw
-- override, so switching to it exercises every part of the contract:
-- /scoot debug skin testcard, and back with /scoot debug skin tui. It stays
-- in-tree until the sibling addon ships its real skin.
local addonName, addon = ...

local Skin = addon.UI.Skin

local FONT_BASE = "Interface\\AddOns\\Scoot\\media\\fonts\\"

local PROP_REG  = addon.Fonts.ROBOTO_REG or (FONT_BASE .. "Roboto-Regular.ttf")
local PROP_MED  = addon.Fonts.ROBOTO_MED or (FONT_BASE .. "Roboto-Medium.ttf")
local MONO_BOLD = addon.Fonts.JETBRAINS_BOLD

-- Override Toggle: testcard seam proof. A glyph checkbox drawn in place of
-- the stock ON/OFF indicator, satisfying the stock control's public methods
-- and the fields the framework reads.
local function TestcardToggle(options)
    local theme = addon.UI.Theme
    local Controls = addon.UI.Controls
    if not options or not options.parent then return nil end
    local m = Controls.Metrics()

    local parent = options.parent
    local getValue = options.get or function() return false end
    local setValue = options.set or function() end
    local isDisabledFn = options.disabled or options.isDisabled

    local dimR, dimG, dimB
    if options.useLightDim then
        dimR, dimG, dimB = theme:GetDimTextLightColor()
    else
        dimR, dimG, dimB = theme:GetDimTextColor()
    end

    local row = CreateFrame("Button", options.name, parent)
    row:EnableMouse(true)
    row:RegisterForClicks("AnyUp")
    row._hoverBg = Controls.AddHoverFill(row, { sublevel = Controls.SUBLEVEL_BG })

    local boxSize = m.controlHeight - 6
    local labelFS = Controls.AddRowChrome(row, {
        rowWidth = options.rowWidth or (parent:GetWidth() or 0),
        baseHeight = m.rowHeight,
        label = options.label or "Toggle",
        description = options.description,
        controlReserve = boxSize + m.rowPadding * 2,
        dimColor = { dimR, dimG, dimB },
    })

    local box = CreateFrame("Frame", nil, row)
    box:SetSize(boxSize, boxSize)
    Controls.AnchorCluster(row, box, { x = -m.rowPadding })
    box._border = Controls.CreateBorder(box, { thickness = m.borderWidth })

    local glyph = box:CreateFontString(nil, "OVERLAY")
    theme:ApplyFont(glyph, "button")
    glyph:SetPoint("CENTER", 0, 0)
    glyph:SetText("\226\156\148")  -- ✔
    row._indicator = box

    row._value = false
    row._isDisabled = false
    row._isDisabledFn = isDisabledFn

    local function UpdateVisual()
        local r, g, b = theme:GetAccentColor()
        local dR, dG, dB = theme:GetDimTextColor()
        if row._isDisabled then
            labelFS:SetTextColor(dR, dG, dB, 0.35)
            if row._description then row._description:SetAlpha(0.35) end
            glyph:SetShown(row._value)
            glyph:SetTextColor(dR, dG, dB, 0.35)
        else
            labelFS:SetTextColor(r, g, b, 1)
            if row._description then row._description:SetAlpha(1) end
            glyph:SetShown(row._value)
            glyph:SetTextColor(r, g, b, 1)
        end
    end
    row._updateVisual = UpdateVisual

    row._value = getValue() or false
    if isDisabledFn then
        row._isDisabled = isDisabledFn() and true or false
    end
    UpdateVisual()

    row:SetScript("OnEnter", function(self) self._hoverBg:Show() end)
    row:SetScript("OnLeave", function(self) self._hoverBg:Hide() end)
    row:SetScript("OnClick", function(self)
        if self._isDisabled then return end
        self._value = not self._value
        setValue(self._value)
        UpdateVisual()
        PlaySound(self._value and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON
            or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
    end)

    local subscribeKey = "TestcardToggle_" .. (options.name or tostring(row))
    row._subscribeKey = subscribeKey
    theme:Subscribe(subscribeKey, UpdateVisual)

    function row:SetValue(newValue)
        self._value = newValue or false
        self._updateVisual()
    end

    function row:GetValue()
        return self._value
    end

    function row:Refresh()
        self._value = getValue() or false
        if self._isDisabledFn then
            self._isDisabled = self._isDisabledFn() and true or false
        end
        self._updateVisual()
    end

    function row:SetDisabled(disabled)
        self._isDisabled = disabled and true or false
        self._updateVisual()
    end

    function row:IsDisabled()
        return self._isDisabled
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
        if self._infoIcon and self._infoIcon.Cleanup then
            self._infoIcon:Cleanup()
        end
    end

    function row:GetDescriptionFontString()
        return self._description
    end

    return row
end

Skin.Register("testcard", {
    palette = {
        -- Amber on deep blue, far from the tui greens on near black.
        accentDefault   = { r = 1, g = 0.72, b = 0.2, a = 1 },
        background      = { r = 0.03, g = 0.05, b = 0.1, a = 0.96 },
        backgroundSolid = { r = 0.03, g = 0.05, b = 0.1, a = 0.99 },
        textPrimary     = { r = 0.98, g = 0.96, b = 0.9, a = 1 },
        textDim         = { r = 0.6, g = 0.62, b = 0.68, a = 1 },
        textDimLight    = { r = 0.76, g = 0.78, b = 0.82, a = 1 },
        collapsibleBg   = { r = 0.1, g = 0.13, b = 0.2, a = 1 },
    },

    fonts = {
        label     = { path = PROP_MED,  size = 14 },
        value     = { path = PROP_REG,  size = 12 },
        desc      = { path = PROP_REG,  size = 12 },
        header    = { path = MONO_BOLD, size = 17 },
        button    = { path = PROP_MED,  size = 13 },
        miniLabel = { path = PROP_REG,  size = 10 },
        proportional    = { path = PROP_REG, size = 12 },
        proportionalMed = { path = PROP_MED, size = 12 },
    },

    textures = {
        NOISE_OVERLAY = "Interface\\AddOns\\Scoot\\media\\textures\\noise-overlay",
        SCOOT_ICON    = "Interface\\AddOns\\Scoot\\ScootIcon",
        SCOOT_ICON_TRANSPARENT = "Interface\\AddOns\\Scoot\\ScootIconTransparent",
    },

    metrics = {
        rowHeight = 44,
        rowHeightField = 48,
        rowHeightEmphasized = 76,
        dualRowHeight = 61,
        controlHeight = 28,
        rowPadding = 14,
        labelTopPad = 12,
        labelLineHeight = 17,
        descGap = 3,
        descPadBottom = 12,
        maxRowHeight = 220,

        itemSpacing = 10,
        contentPadding = 10,
        sectionSpacing = 20,
        sectionHeaderHeight = 34,
        firstItemOffset = 10,

        dividerThickness = 1,
        dividerAlpha = 0.45,
        borderWidth = 1,
        windowBorderWidth = 2,

        slotGap = 16,
        miniLabelHeight = 14,
        miniLabelGap = 3,
        maxClusterWidth = 430,
        slots = { toggle = 70, slider = 130, selector = 140, selectorWide = 240, swatch = 28, input = 36 },
        minDescWidth = 200,

        field = {
            arrowWidth = 28,
            indicatorWidth = 8,
            indicatorGap = 6,
            textInset = 10,
            gearWidth = 22,
            tokenIconWidth = 10,
            widthStep = 20,
            popupMaxWidth = 380,
        },

        sublevels = { bg = -8, fill = -7, hover = -6 },
        alphas = { hover = 0.1, emphasis = 0.04, selected = 0.15, borderNormal = 0.7, borderFocus = 1.0 },
    },

    overrides = {
        Toggle = TestcardToggle,
    },
})
