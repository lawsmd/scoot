-- Toggle.lua - Full-row toggle control with ON/OFF state indicator
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

-- Constants

local BORDER_WIDTH = 2
local TOGGLE_HEIGHT = 36
local TOGGLE_HEIGHT_WITH_DESC = 60  -- Increased for better description spacing
local TOGGLE_INDICATOR_WIDTH = 60
local TOGGLE_INDICATOR_HEIGHT = 22
local TOGGLE_PADDING = 12

-- Dynamic height constants
local DESC_PADDING_TOP = 2        -- Space between label and description
local DESC_PADDING_TOP_EMPH = 4   -- Space for emphasized controls

-- Emphasized toggle constants (Hero Toggle styling)
local EMPHASIZED_HEIGHT = 72
local EMPHASIZED_HEIGHT_WITH_DESC = 92
local EMPHASIZED_BORDER_WIDTH = 3
local EMPHASIZED_LABEL_SIZE = 16
local EMPHASIZED_INDICATOR_WIDTH = 70
local EMPHASIZED_INDICATOR_HEIGHT = 26

--------------------------------------------------------------------------------
-- The indicator: the ON/OFF pill, or a Blizzard checkbox
--------------------------------------------------------------------------------

-- Controls.CreateToggleIndicator(parent, opts) builds the box that shows a
-- toggle's state, wherever one is drawn: a settings row's indicator, the
-- compact pill in a selector row, the Features page's. The toggle chrome role
-- decides what it is. Flat is the framework's pill: an accent border, a fill
-- while on, and the word in the toggle font role. A template kind is a
-- Blizzard CheckButton on the skin's template, centered in a frame of the
-- box's drawn size; the template's tooltip scripts are replaced by the
-- caller's hover, and the checked flag the button flips on its own is put
-- back from the caller's value on every SetState.
--
-- opts:
--   width, height   the pill's box; a template keeps the template's own size
--   fit             a height the box must fit: a taller template scales down
--   clickable       the frame takes clicks itself (a Button); otherwise a
--                   Frame with no mouse, which a row clicks through
--   onClick, onEnter, onLeave
--                   the box's scripts. A template's box always carries all
--                   three, and one left out forwards to the frame's own
--                   script of that name, so a caller that sets its handlers on
--                   the frame afterwards is reached from the box as well
--   hover           the pill lights a faint fill under the cursor while off
--   fontSize        the pill's text size where the skin names no toggle role
--   useLightDim     the pill's first dim text from the light dim color
-- Returns a handle: frame (the region to anchor), width and height (the drawn
-- size), kind ("flat" or "template"), SetState(isOn, isDisabled, tint) with
-- tint an { r, g, b } that colors the lit pill or the check, and
-- SetText(word) for the lit pill's word, "ON" unless a caller says otherwise;
-- a template ignores it.
function Controls.CreateToggleIndicator(parent, opts)
    opts = opts or {}
    local theme = GetTheme()
    local Chrome = addon.UI.Chrome
    local spec = (Chrome and Chrome.Spec) and Chrome.Spec("toggle") or { kind = "flat" }
    local handle = { kind = spec.kind, _word = "ON" }

    -- The frame's own script of a name, run from the box
    local function Forward(frame, script)
        return function(_, ...)
            if not frame:HasScript(script) then return end
            local fn = frame:GetScript(script)
            if fn then fn(frame, ...) end
        end
    end

    local function TintRGB(tint, r, g, b)
        if type(tint) ~= "table" then return r, g, b end
        return tint[1] or tint.r or r, tint[2] or tint.g or g, tint[3] or tint.b or b
    end

    if spec.kind == "template" then
        local frame = CreateFrame(opts.clickable and "Button" or "Frame", nil, parent)
        local box = Chrome.CreateFrame(spec, "CheckButton", nil, frame)
        box:RegisterForClicks("AnyUp")
        if box.HoverBackground then box.HoverBackground:Hide() end
        local w, h = box:GetSize()
        local scale = 1
        if opts.fit and h > opts.fit then scale = opts.fit / h end
        box:SetScale(scale)
        box:SetPoint("CENTER", frame, "CENTER", 0, 0)
        frame:SetSize(w * scale, h * scale)
        if opts.clickable then
            frame:RegisterForClicks("AnyUp")
            if opts.onClick then frame:SetScript("OnClick", opts.onClick) end
            if opts.onEnter then frame:SetScript("OnEnter", opts.onEnter) end
            if opts.onLeave then frame:SetScript("OnLeave", opts.onLeave) end
        end
        local function BoxScript(name)
            local fn = opts[name]
            if fn then
                return function(_, ...) fn(frame, ...) end
            end
            return Forward(frame, (name:gsub("^on", "On")))
        end
        box:SetScript("OnClick", BoxScript("onClick"))
        box:SetScript("OnEnter", BoxScript("onEnter"))
        box:SetScript("OnLeave", BoxScript("onLeave"))

        handle.frame, handle.box = frame, box
        handle.width, handle.height = w * scale, h * scale

        function handle:SetState(isOn, isDisabled, tint)
            box:SetChecked(isOn and true or false)
            box:SetEnabled(not isDisabled)
            box:SetAlpha(isDisabled and 0.35 or 1)
            local check = box:GetCheckedTexture()
            if check then
                check:SetVertexColor(TintRGB(tint, 1, 1, 1))
            end
        end

        function handle:SetText() end
        return handle
    end

    local width = opts.width or TOGGLE_INDICATOR_WIDTH
    local height = opts.height or TOGGLE_INDICATOR_HEIGHT
    local frame = CreateFrame(opts.clickable and "Button" or "Frame", nil, parent)
    frame:SetSize(width, height)
    if opts.clickable then
        frame:EnableMouse(true)
        frame:RegisterForClicks("AnyUp")
    end

    local ar, ag, ab = theme:GetAccentColor()
    local dimR, dimG, dimB
    if opts.useLightDim then
        dimR, dimG, dimB = theme:GetDimTextLightColor()
    else
        dimR, dimG, dimB = theme:GetDimTextColor()
    end

    -- Border and fill. Static colors: SetState owns every tint.
    local border = Controls.CreateBorder(frame, {
        thickness = BORDER_WIDTH,
        color = { ar, ag, ab },
    })
    local fill = frame:CreateTexture(nil, "BACKGROUND", nil, Controls.SUBLEVEL_FILL)
    fill:SetPoint("TOPLEFT", frame, "TOPLEFT", BORDER_WIDTH, -BORDER_WIDTH)
    fill:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -BORDER_WIDTH, BORDER_WIDTH)
    fill:Hide()
    local hoverFill
    if opts.hover then
        hoverFill = Controls.AddHoverFill(frame, {
            alpha = 0.15,
            inset = BORDER_WIDTH,
            sublevel = Controls.SUBLEVEL_HOVER,
        })
    end

    -- The word. The font carries the state's style, so SetState re-applies
    -- it on every state change.
    local text = frame:CreateFontString(nil, "OVERLAY")
    Controls.ApplyToggleFont(text, false, opts.fontSize)
    text:SetPoint("CENTER", frame, "CENTER", 0, 0)
    text:SetText("OFF")
    text:SetTextColor(dimR, dimG, dimB, 1)

    local on, disabled = false, false
    if opts.clickable then
        if opts.onClick then frame:SetScript("OnClick", opts.onClick) end
        frame:SetScript("OnEnter", function(self, ...)
            if hoverFill and not disabled and not on then hoverFill:Show() end
            if opts.onEnter then opts.onEnter(self, ...) end
        end)
        frame:SetScript("OnLeave", function(self, ...)
            if hoverFill then hoverFill:Hide() end
            if opts.onLeave then opts.onLeave(self, ...) end
        end)
    end

    handle.frame = frame
    handle.width, handle.height = width, height

    function handle:SetState(isOn, isDisabled, tint)
        on, disabled = isOn and true or false, isDisabled and true or false
        local r, g, b = theme:GetAccentColor()
        local dR, dG, dB = theme:GetDimTextColor()
        -- Disabled hides the fill, so only an enabled ON draws black on accent
        Controls.ApplyToggleFont(text, on and not disabled, opts.fontSize)
        if disabled then
            local disabledAlpha = 0.35
            fill:Hide()
            text:SetText(on and self._word or "OFF")
            text:SetTextColor(dR, dG, dB, disabledAlpha)
            for _, tex in pairs(border) do
                tex:SetColorTexture(dR, dG, dB, disabledAlpha * 0.5)
            end
        elseif on then
            local lr, lg, lb = TintRGB(tint, r, g, b)
            fill:SetColorTexture(lr, lg, lb, 1)
            fill:Show()
            if hoverFill then hoverFill:Hide() end
            text:SetText(self._word)
            text:SetTextColor(0, 0, 0, 1)  -- Dark text on the fill
            for _, tex in pairs(border) do
                tex:SetColorTexture(lr, lg, lb, 1)
            end
        else
            fill:Hide()
            text:SetText("OFF")
            text:SetTextColor(dR, dG, dB, 1)
            for _, tex in pairs(border) do
                tex:SetColorTexture(r, g, b, 0.4)
            end
        end
    end

    function handle:SetText(word)
        self._word = word or "ON"
    end

    return handle
end

--------------------------------------------------------------------------------
-- Toggle: Full-row toggle control with ON/OFF state indicator
--------------------------------------------------------------------------------

function Controls:CreateToggle(options)
    local override = Controls.SkinOverride("Toggle", options)
    if override then return override end
    local theme = GetTheme()
    if not options or not options.parent then
        return nil
    end

    local parent = options.parent
    local label = options.label or "Toggle"
    local description = options.description
    local getValue = options.get or function() return false end
    local setValue = options.set or function() end
    local name = options.name
    local emphasized = options.emphasized or false
    local infoIconOpts = options.infoIcon
    local isDisabledFn = options.disabled or options.isDisabled

    local hasDesc = description and description ~= ""
    local rowWidth = options.rowWidth
    -- Width-driven rows take the base height from the metrics; the chrome
    -- measure grows description rows synchronously. Direct callers without a
    -- rowWidth keep the fixed height table until they convert.
    local height
    if rowWidth then
        height = emphasized and EMPHASIZED_HEIGHT or Controls.Metrics().rowHeight
    elseif emphasized then
        height = hasDesc and EMPHASIZED_HEIGHT_WITH_DESC or EMPHASIZED_HEIGHT
    else
        height = hasDesc and TOGGLE_HEIGHT_WITH_DESC or TOGGLE_HEIGHT
    end

    -- Use appropriate sizes for emphasized vs normal
    local indicatorWidth = emphasized and EMPHASIZED_INDICATOR_WIDTH or TOGGLE_INDICATOR_WIDTH
    local indicatorHeight = emphasized and EMPHASIZED_INDICATOR_HEIGHT or TOGGLE_INDICATOR_HEIGHT
    local labelFontSize = emphasized and EMPHASIZED_LABEL_SIZE or 13
    local leftBorderWidth = emphasized and EMPHASIZED_BORDER_WIDTH or 0

    -- Create the row frame
    local row = CreateFrame("Button", name, parent)
    row:SetHeight(height)
    row:EnableMouse(true)
    row:RegisterForClicks("AnyUp")

    -- Get theme colors
    local ar, ag, ab = theme:GetAccentColor()
    local dimR, dimG, dimB
    if options.useLightDim then
        dimR, dimG, dimB = theme:GetDimTextLightColor()
    else
        dimR, dimG, dimB = theme:GetDimTextColor()
    end

    -- Row hover background (hidden by default)
    row._hoverBg = Controls.AddHoverFill(row, { sublevel = Controls.SUBLEVEL_BG })

    -- The divider under a row is builder-drawn; the row keeps only the
    -- emphasized left accent bar.
    if emphasized and leftBorderWidth > 0 then
        -- Kept off builder divider: left accent bar, not a row divider.
        row._rowBorder = Controls.CreateBorder(row, {
            sides = { "LEFT" },
            thickness = { LEFT = leftBorderWidth },
            alpha = 1,
        })
    end

    if emphasized and leftBorderWidth > 0 then
        -- Faint background highlight for emphasized
        local emphBg = row:CreateTexture(nil, "BACKGROUND", nil, -7)
        emphBg:SetPoint("TOPLEFT", leftBorderWidth, 0)
        emphBg:SetPoint("BOTTOMRIGHT", 0, 0)
        emphBg:SetColorTexture(ar, ag, ab, 0.03)
        row._emphBg = emphBg
    end
    row._emphasized = emphasized

    -- Calculate label padding (account for left border on emphasized)
    local labelLeftPad = TOGGLE_PADDING + leftBorderWidth

    -- State tracking
    row._value = false
    row._isDisabled = false
    row._isDisabledFn = isDisabledFn

    local UpdateVisual  -- defined once the label exists

    -- The row's own flip, reached from a click anywhere on the row and from
    -- the state box, which takes the mouse itself when it is a checkbox
    local function Toggle()
        if row._isDisabled then
            return
        end
        row._value = not row._value
        setValue(row._value)
        UpdateVisual()
        PlaySound(row._value and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
    end

    -- State indicator (right side), built before the label so the chrome
    -- keeps the width it draws at free
    local indicator = Controls.CreateToggleIndicator(row, {
        width = indicatorWidth,
        height = indicatorHeight,
        onClick = Toggle,
        onEnter = function() row._hoverBg:Show() end,
        onLeave = function() row._hoverBg:Hide() end,
        useLightDim = options.useLightDim,
    })
    row._indicator = indicator.frame

    -- Label and description
    local chromeOpts
    if rowWidth then
        chromeOpts = {
            rowWidth = rowWidth,
            baseHeight = height,
            label = label,
            labelFontSize = emphasized and EMPHASIZED_LABEL_SIZE or nil,
            padLeft = labelLeftPad,
            description = description,
            descFontSize = emphasized and 12 or nil,
            controlReserve = indicator.width + TOGGLE_PADDING * 2,
            dimColor = { dimR, dimG, dimB },
        }
    else
        chromeOpts = {
            label = label,
            labelFontSize = labelFontSize,
            labelYOffset = hasDesc and (emphasized and 12 or 6) or 0,
            padLeft = labelLeftPad,
            description = description,
            descFontSize = emphasized and 12 or 11,
            padAbove = emphasized and DESC_PADDING_TOP_EMPH or DESC_PADDING_TOP,
            reserve = indicator.width + TOGGLE_PADDING * 2,
            dimColor = { dimR, dimG, dimB },
        }
    end
    local labelFS = Controls.AddRowChrome(row, chromeOpts)

    -- Centered in the top band on width-driven rows
    if rowWidth then
        Controls.AnchorCluster(row, indicator.frame, { x = -TOGGLE_PADDING })
    else
        indicator.frame:SetPoint("RIGHT", row, "RIGHT", -TOGGLE_PADDING, 0)
    end

    -- Update visual state
    UpdateVisual = function()
        local isOn = row._value
        local isDisabled = row._isDisabled
        local r, g, b = theme:GetAccentColor()
        local dR, dG, dB = theme:GetDimTextColor()

        if isDisabled then
            -- Disabled state: everything grayed out
            local disabledAlpha = 0.35
            labelFS:SetTextColor(dR, dG, dB, disabledAlpha)
            if row._description then
                row._description:SetAlpha(disabledAlpha)
            end
        else
            -- Restore description alpha
            if row._description then
                row._description:SetAlpha(1)
            end
            -- Label always uses accent color for consistency
            labelFS:SetTextColor(r, g, b, 1)
        end
        indicator:SetState(isOn, isDisabled)
    end
    row._updateVisual = UpdateVisual

    -- Initialize from getter
    row._value = getValue() or false
    -- Initialize disabled state from function
    if isDisabledFn then
        row._isDisabled = isDisabledFn() and true or false
    end
    UpdateVisual()

    -- Hover handlers. The cursor passing onto the state box leaves the row,
    -- and the box shows the same fill, so the row hides it only once the
    -- cursor is off both.
    row:SetScript("OnEnter", function(self)
        self._hoverBg:Show()
    end)

    row:SetScript("OnLeave", function(self)
        if not self._indicator:IsMouseOver() then
            self._hoverBg:Hide()
        end
    end)

    -- Click to toggle
    row:SetScript("OnClick", Toggle)

    -- Generate unique subscription key
    local subscribeKey = "Toggle_" .. (name or tostring(row))
    row._subscribeKey = subscribeKey

    -- Subscribe to theme updates (hover fill and row border retint via Utils)
    theme:Subscribe(subscribeKey, function(r, g, b)
        -- Update emphasized background
        if row._emphBg then
            row._emphBg:SetColorTexture(r, g, b, 0.03)
        end
        -- Re-run visual update to apply new accent color
        UpdateVisual()
    end)

    -- Add info icon if specified (positioned after label)
    local infoSpec = Controls.InfoIconOptions(infoIconOpts)
    if infoSpec then
        local infoIcon = Controls:CreateInfoIcon({
            parent = row,
            tooltipText = infoSpec.tooltipText,
            tooltipTitle = infoSpec.tooltipTitle,
            size = infoSpec.size or (emphasized and 14 or 12),
        })
        if infoIcon then
            -- Position icon after the label text
            infoIcon:SetPoint("LEFT", labelFS, "RIGHT", 4, 0)
            row._infoIcon = infoIcon
        end
    end

    -- Public methods
    function row:SetValue(newValue)
        self._value = newValue or false
        self._updateVisual()
    end

    function row:GetValue()
        return self._value
    end

    function row:Refresh()
        self._value = getValue() or false
        -- Check disabled state from function
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

    -- Dynamic label update (for orientation-dependent labels)
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
