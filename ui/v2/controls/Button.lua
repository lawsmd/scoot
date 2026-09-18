-- Button.lua - the framework's button and close button: behavior here, the
-- draw from the active skin's chrome roles.
--
-- Controls:CreateButton(options) and Controls:CreateCloseButton(options)
-- dispatch through Controls.SkinOverride first ("Button", "CloseButton") and
-- then read Chrome.Spec("button") and Spec("closeButton"). A flat role is
-- the framework's own draw: a fill, a hover fill, a four-edge border and a
-- label in the button font role. A template role builds the frame on a
-- Blizzard template, whose art and states come with it; the skin's template
-- goes first in the list and the caller's own (a secure handler) after it.
--
-- Public contract, satisfied by every kind and every override:
--   SetText(text), GetText()
--   SetEnabled(bool)
--   SetActive(bool), IsActive()   the pressed-in look while the button's page is open
--   SetPulsing(bool)              the attention pulse (skin metrics.pulse)
--   SetLabelColor(r, g, b, a)     a caller-owned label color, until the next SetActive
--   Cleanup()
-- Fields under an underscore belong to the flat draw and no caller reads them.
--
-- CreateButton options:
--   text, width (nil auto-sizes to the text), height, fontSize, padding,
--   onClick(button, mouseButton), parent (required), name,
--   template (the caller's own templates, e.g. a secure handler),
--   secureAction (a table of SecureActionButton attributes),
--   borderWidth, borderAlpha (flat kind)
-- CreateCloseButton options: parent (required), name, onClick, size
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.Controls = addon.UI.Controls or {}
local Controls = addon.UI.Controls
local Theme -- Will be set after Theme.lua loads

-- Lazy Theme accessor (Theme loads before controls but namespace may not exist yet)
local function GetTheme()
    if not Theme then
        Theme = addon.UI.Theme
    end
    return Theme
end

-- Layout numbers come from the active skin's metrics.button table.
local function M()
    return Controls.Metrics()
end

local function Chrome()
    return addon.UI.Chrome
end

-- The label colors a flat button draws with when its role declares none.
local FLAT_LABEL_COLORS = { normal = "accent", hover = "black", active = "background", disabled = "accent" }

--------------------------------------------------------------------------------
-- Shared behavior
--------------------------------------------------------------------------------

-- Width from the label, with the first-launch retry: a font the client has
-- not loaded yet measures zero, so an estimate stands until the next frame.
local function AutoSize(btn, label, text, padding)
    local textWidth = label:GetStringWidth()
    if textWidth and textWidth > 0 then
        btn:SetWidth(textWidth + padding * 2)
        return
    end
    local estimatedWidth = (#text * 7) + padding * 2
    btn:SetWidth(math.max(estimatedWidth, 50))
    C_Timer.After(0, function()
        if btn and label then
            local actualWidth = label:GetStringWidth()
            if actualWidth and actualWidth > 0 then
                btn:SetWidth(actualWidth + padding * 2)
            end
        end
    end)
end

-- The attention pulse: alpha on a cosine between minAlpha and 1, applied by
-- the kind's paint function every tick.
local function InstallPulse(btn, paint)
    function btn:SetPulsing(on)
        if on then
            if self._pulseTicker then return end
            local elapsed = 0
            self._pulseTicker = C_Timer.NewTicker(M().pulse.tick, function()
                local m = M().pulse
                elapsed = elapsed + m.tick
                local phase = (elapsed % m.period) / m.period
                paint(self, m.minAlpha + (1 - m.minAlpha) * (0.5 + 0.5 * math.cos(phase * 2 * math.pi)))
            end)
        else
            if self._pulseTicker then
                self._pulseTicker:Cancel()
                self._pulseTicker = nil
            end
            paint(self, 1)
        end
    end
end

local function InstallSecureAction(btn, action)
    local function applySecureAction()
        local actionType = action.type
        if not actionType then
            if action.macrotext then
                actionType = "macro"
            elseif action.spell then
                actionType = "spell"
            elseif action.item then
                actionType = "item"
            elseif action.action then
                actionType = "action"
            end
        end
        if actionType then btn:SetAttribute("type", actionType) end
        if action.macrotext then btn:SetAttribute("macrotext", action.macrotext) end
        if action.spell then btn:SetAttribute("spell", action.spell) end
        if action.item then btn:SetAttribute("item", action.item) end
        if action.action then btn:SetAttribute("action", action.action) end
        if action.binding then btn:SetAttribute("binding", action.binding) end
        if action.unit then btn:SetAttribute("unit", action.unit) end
        if action.clickbutton then btn:SetAttribute("clickbutton", action.clickbutton) end
    end

    if _G.InCombatLockdown and _G.InCombatLockdown() then
        -- Queue on the shared regen drain instead of registering events on
        -- the secure button itself. Keyed per button: a reconfigure before
        -- regen replaces the queued attribute batch.
        addon.Events.RunOutOfCombat(applySecureAction, btn)
    else
        applySecureAction()
    end
end

--------------------------------------------------------------------------------
-- Button
--------------------------------------------------------------------------------

function Controls:CreateButton(options)
    local override = Controls.SkinOverride("Button", options)
    if override then return override end

    local theme = GetTheme()
    if not options or not options.parent then
        return nil
    end

    local parent = options.parent
    local text = options.text or ""
    local height = options.height or M().button.height
    local fontSize = options.fontSize or M().button.fontSize
    local padding = options.padding or M().button.padding
    local name = options.name

    -- The skin's template first, the caller's own after it, so a secure
    -- handler keeps its templates under any skin.
    local template = options.template
    if options.secureAction and not template then
        template = "SecureActionButtonTemplate"
    end
    local btn, spec = Chrome().CreateFrame("button", "Button", name, parent, template)
    btn:SetHeight(height)
    btn:EnableMouse(true)
    if options.secureAction then
        btn:RegisterForClicks("AnyUp")
        btn:SetAttribute("useOnKeyDown", false)
    else
        btn:RegisterForClicks("AnyUp", "AnyDown")
    end
    btn._text = text
    btn._isActive = false

    if spec.kind == "template" then
        self:_DrawTemplateButton(btn, spec, options, text, fontSize, padding)
    else
        self:_DrawFlatButton(btn, spec, options, text, fontSize, padding)
    end

    if options.secureAction and type(options.secureAction) == "table" then
        InstallSecureAction(btn, options.secureAction)
    end

    -- Click handler (avoid overriding secure OnClick)
    if options.onClick then
        if options.secureAction then
            -- Use PostClick so the secure action fires before addon code runs.
            btn:HookScript("PostClick", function(self, mouseButton, down)
                options.onClick(self, mouseButton)
            end)
        else
            btn:SetScript("OnClick", function(self, mouseButton, down)
                if not down then
                    options.onClick(self, mouseButton)
                end
            end)
        end
    end

    function btn:GetText()
        return self._text
    end

    function btn:IsActive()
        return self._isActive == true
    end

    return btn
end

-- The flat draw: fill, hover fill, four-edge border, label in the button
-- role. Label colors come from the role's labelColors tokens.
function Controls:_DrawFlatButton(btn, spec, options, text, fontSize, padding)
    local theme = GetTheme()
    local colors = spec.labelColors or FLAT_LABEL_COLORS
    local borderWidth = options.borderWidth or M().button.borderWidth
    local borderAlpha = options.borderAlpha or 1

    -- Kept for the callers that inset something against the border.
    btn._borderWidth = borderWidth
    btn._borderAlpha = borderAlpha

    btn._bg = Controls.AddBackground(btn, { inset = borderWidth })
    btn._hoverFill = Controls.AddHoverFill(btn, { alpha = 1, inset = borderWidth })
    btn._border = Controls.CreateBorder(btn, {
        thickness = borderWidth,
        corners = "overlap",
        alpha = borderAlpha,
    })

    local label = btn:CreateFontString(nil, "OVERLAY")
    theme:ApplyFont(label, "button", fontSize)
    label:SetPoint("CENTER", 0, 0)
    label:SetText(text)
    btn._label = label

    local function paintLabel(state)
        if btn._customLabel and state == "normal" then
            local c = btn._customLabel
            label:SetTextColor(c[1], c[2], c[3], c[4])
            return
        end
        label:SetTextColor(Chrome().Color(colors[state] or colors.normal))
    end
    btn._paintLabel = paintLabel
    paintLabel("normal")

    if options.width then
        btn:SetWidth(options.width)
    else
        AutoSize(btn, label, text, padding)
    end

    btn:SetScript("OnEnter", function(self)
        self._hoverFill:Show()
        paintLabel("hover")
    end)

    btn:SetScript("OnLeave", function(self)
        if self._isActive then
            paintLabel("active")
        else
            self._hoverFill:Hide()
            paintLabel("normal")
        end
    end)

    -- Borders and fills retint through the shared Utils subscription; the
    -- label is the one piece that needs its state re-read.
    local subscribeKey = "Button_" .. (options.name or tostring(btn))
    btn._subscribeKey = subscribeKey
    theme:Subscribe(subscribeKey, function()
        if btn:IsMouseOver() then return end
        paintLabel(btn._isActive and "active" or "normal")
    end)

    function btn:SetText(newText)
        self._text = newText
        self._label:SetText(newText)
        if not options.width then
            AutoSize(self, self._label, newText, padding)
        end
    end

    function btn:SetEnabled(enabled)
        if enabled then
            self:Enable()
            self._border:SetAlpha(self._borderAlpha or 1)
            paintLabel(self._isActive and "active" or "normal")
        else
            self:Disable()
            -- Dim the button when disabled (relative to base alpha)
            self._border:SetAlpha((self._borderAlpha or 1) * 0.4)
            local r, g, b = Chrome().Color(colors.disabled or colors.normal)
            self._label:SetTextColor(r, g, b, 0.4)
        end
    end

    function btn:SetActive(active)
        self._isActive = active and true or false
        self._customLabel = nil
        if self._isActive then
            self._hoverFill:Show()
            paintLabel("active")
        else
            if not self:IsMouseOver() then self._hoverFill:Hide() end
            paintLabel(self:IsMouseOver() and "hover" or "normal")
        end
    end

    function btn:SetLabelColor(r, g, b, a)
        self._customLabel = { r, g, b, a or 1 }
        paintLabel("normal")
    end

    InstallPulse(btn, function(self, alpha)
        if self._border then
            for _, tex in pairs(self._border) do
                tex:SetAlpha(alpha)
            end
        end
        if self._label then
            self._label:SetAlpha(alpha)
        end
    end)

    function btn:Cleanup()
        if self._pulseTicker then
            self._pulseTicker:Cancel()
            self._pulseTicker = nil
        end
        if self._subscribeKey then
            theme:Unsubscribe(self._subscribeKey)
        end
    end
end

-- The template draw: Blizzard's art and states, the label the template
-- carries, and the framework's sizing on top.
function Controls:_DrawTemplateButton(btn, spec, options, text, fontSize, padding)
    local theme = GetTheme()
    local label = btn.Text or (btn.GetFontString and btn:GetFontString())
    btn._label = label

    -- The widget method, before the contract's SetText shadows it.
    local nativeSetText = btn.SetText
    nativeSetText(btn, text)

    if label and spec.font == "role" then
        theme:ApplyFont(label, "button", fontSize)
    end

    if options.width then
        btn:SetWidth(options.width)
    elseif label then
        AutoSize(btn, label, text, padding)
    end

    function btn:SetText(newText)
        self._text = newText
        nativeSetText(self, newText)
        if not options.width and self._label then
            AutoSize(self, self._label, newText, padding)
        end
    end

    -- SetEnabled stays the widget's own: the template swaps its art and font
    -- through OnEnable and OnDisable.

    function btn:SetActive(active)
        self._isActive = active and true or false
        if self._isActive then
            self:SetButtonState("PUSHED", true)
        else
            self:SetButtonState("NORMAL", false)
        end
    end

    function btn:SetLabelColor(r, g, b, a)
        if self._label then self._label:SetTextColor(r, g, b, a or 1) end
    end

    InstallPulse(btn, function(self, alpha)
        self:SetAlpha(alpha)
    end)

    function btn:Cleanup()
        if self._pulseTicker then
            self._pulseTicker:Cancel()
            self._pulseTicker = nil
        end
    end
end

--------------------------------------------------------------------------------
-- Close button
--------------------------------------------------------------------------------

function Controls:CreateCloseButton(options)
    local override = Controls.SkinOverride("CloseButton", options)
    if override then return override end

    local theme = GetTheme()
    if not options or not options.parent then
        return nil
    end

    local size = options.size or M().closeButton.size
    local btn, spec = Chrome().CreateFrame("closeButton", "Button", options.name, options.parent)
    btn:SetSize(size, size)
    btn:EnableMouse(true)
    btn:RegisterForClicks("AnyUp")

    if spec.kind ~= "template" then
        local bg = btn:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        local ar, ag, ab = theme:GetAccentColor()
        bg:SetColorTexture(ar, ag, ab, 1)
        bg:Hide()
        btn._bg = bg

        local label = btn:CreateFontString(nil, "OVERLAY")
        theme:ApplyFont(label, "button", M().closeButton.fontSize)
        label:SetPoint("CENTER", 0, -1)
        label:SetText(spec.glyph or "X")
        label:SetTextColor(ar, ag, ab, 1)
        btn._label = label

        btn:SetScript("OnEnter", function(self)
            local r, g, b = theme:GetAccentColor()
            self._bg:SetColorTexture(r, g, b, 1)
            self._bg:Show()
            self._label:SetTextColor(0, 0, 0, 1)
        end)
        btn:SetScript("OnLeave", function(self)
            self._bg:Hide()
            local r, g, b = theme:GetAccentColor()
            self._label:SetTextColor(r, g, b, 1)
        end)

        local subscribeKey = "CloseButton_" .. (options.name or tostring(btn))
        btn._subscribeKey = subscribeKey
        theme:Subscribe(subscribeKey, function(r, g, b)
            if btn._bg then
                btn._bg:SetColorTexture(r, g, b, 1)
            end
            if btn._label and not btn:IsMouseOver() then
                btn._label:SetTextColor(r, g, b, 1)
            end
        end)
    end

    -- Replaces the template's own click, which hides its parent.
    btn:SetScript("OnClick", function(self, mouseButton)
        if options.onClick then options.onClick(self, mouseButton) end
    end)

    function btn:Cleanup()
        if self._subscribeKey then
            theme:Unsubscribe(self._subscribeKey)
        end
    end

    return btn
end

--------------------------------------------------------------------------------
-- Convenience: Create a button anchored to straddle a frame's edge
--------------------------------------------------------------------------------
-- This positions the button so it's centered vertically on the specified edge.
-- For "TOP" edge: half the button is above the parent, half below.
--
-- Options (in addition to CreateButton options):
--   edge      : "TOP", "BOTTOM", "LEFT", "RIGHT" (default "TOP")
--   offsetX   : Horizontal offset from anchor point
--   offsetY   : Vertical offset (usually 0 for straddling)
--   anchor    : Anchor point on parent edge (e.g., "CENTER", "LEFT", "RIGHT")
--------------------------------------------------------------------------------

function Controls:CreateEdgeButton(options)
    local btn = self:CreateButton(options)
    if not btn then return nil end

    local edge = options.edge or "TOP"
    local offsetX = options.offsetX or 0
    local offsetY = options.offsetY or 0
    local anchor = options.anchor or "CENTER"
    local parent = options.parent

    btn:ClearAllPoints()

    if edge == "TOP" then
        -- Center button vertically on top edge
        if anchor == "CENTER" then
            btn:SetPoint("CENTER", parent, "TOP", offsetX, offsetY)
        elseif anchor == "LEFT" then
            btn:SetPoint("LEFT", parent, "TOPLEFT", offsetX, offsetY)
        elseif anchor == "RIGHT" then
            btn:SetPoint("RIGHT", parent, "TOPRIGHT", offsetX, offsetY)
        end
    elseif edge == "BOTTOM" then
        if anchor == "CENTER" then
            btn:SetPoint("CENTER", parent, "BOTTOM", offsetX, offsetY)
        elseif anchor == "LEFT" then
            btn:SetPoint("LEFT", parent, "BOTTOMLEFT", offsetX, offsetY)
        elseif anchor == "RIGHT" then
            btn:SetPoint("RIGHT", parent, "BOTTOMRIGHT", offsetX, offsetY)
        end
    elseif edge == "LEFT" then
        if anchor == "CENTER" then
            btn:SetPoint("CENTER", parent, "LEFT", offsetX, offsetY)
        end
    elseif edge == "RIGHT" then
        if anchor == "CENTER" then
            btn:SetPoint("CENTER", parent, "RIGHT", offsetX, offsetY)
        end
    end

    -- Elevate frame level to ensure visibility above parent border
    btn:SetFrameLevel((parent:GetFrameLevel() or 0) + 15)

    return btn
end
