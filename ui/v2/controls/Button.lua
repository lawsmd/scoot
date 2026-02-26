-- Button.lua - Reusable button controls with UI styling
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

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

local DEFAULT_BUTTON_HEIGHT = 26
local DEFAULT_BUTTON_PADDING = 12  -- Horizontal padding on each side of text
local BORDER_WIDTH = 2

--------------------------------------------------------------------------------
-- Button: Reusable button with UI styling
--------------------------------------------------------------------------------
-- Creates a simple rectangular button with:
--   - Square outline border (accent color)
--   - Dark background
--   - Centered text (accent color, inverts on hover)
--   - Hover effect: filled background with dark text
--
-- Options table:
--   text         : Button label (string)
--   width        : Fixed width (number, optional - auto-sizes to text if nil)
--   height       : Button height (number, default 26)
--   fontSize     : Font size (number, default 12)
--   onClick      : Click handler function(button, mouseButton)
--   parent       : Parent frame (required)
--   name         : Global frame name (optional)
--   template     : Optional frame template (string, e.g. "SecureActionButtonTemplate")
--   secureAction : Optional table of SecureActionButton attributes
--------------------------------------------------------------------------------

function Controls:CreateButton(options)
    local theme = GetTheme()
    if not options or not options.parent then
        return nil
    end

    local parent = options.parent
    local text = options.text or ""
    local height = options.height or DEFAULT_BUTTON_HEIGHT
    local fontSize = options.fontSize or 12
    local name = options.name
    local borderWidth = options.borderWidth or BORDER_WIDTH
    local borderAlpha = options.borderAlpha or 1

    -- Create the button frame (optionally secure action)
    local template = options.template
    if options.secureAction and not template then
        template = "SecureActionButtonTemplate"
    end
    local btn = CreateFrame("Button", name, parent, template)
    btn:SetHeight(height)
    btn:EnableMouse(true)
    if options.secureAction then
        btn:RegisterForClicks("AnyUp")
        btn:SetAttribute("useOnKeyDown", false)
    else
        btn:RegisterForClicks("AnyUp", "AnyDown")
    end

    -- Store border settings for theme updates and SetEnabled
    btn._borderWidth = borderWidth
    btn._borderAlpha = borderAlpha

    -- Get theme colors
    local ar, ag, ab = theme:GetAccentColor()
    local bgR, bgG, bgB, bgA = theme:GetBackgroundSolidColor()

    -- Background (dark, shown always)
    local bg = btn:CreateTexture(nil, "BACKGROUND", nil, -8)
    bg:SetPoint("TOPLEFT", borderWidth, -borderWidth)
    bg:SetPoint("BOTTOMRIGHT", -borderWidth, borderWidth)
    bg:SetColorTexture(bgR, bgG, bgB, bgA)
    btn._bg = bg

    -- Hover fill (accent color, hidden by default)
    local hoverFill = btn:CreateTexture(nil, "BACKGROUND", nil, -7)
    hoverFill:SetPoint("TOPLEFT", borderWidth, -borderWidth)
    hoverFill:SetPoint("BOTTOMRIGHT", -borderWidth, borderWidth)
    hoverFill:SetColorTexture(ar, ag, ab, 1)
    hoverFill:Hide()
    btn._hoverFill = hoverFill

    -- Border (four edges)
    local border = {}

    -- TOP
    local top = btn:CreateTexture(nil, "BORDER", nil, -1)
    top:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
    top:SetPoint("TOPRIGHT", btn, "TOPRIGHT", 0, 0)
    top:SetHeight(borderWidth)
    top:SetColorTexture(ar, ag, ab, borderAlpha)
    border.TOP = top

    -- BOTTOM
    local bottom = btn:CreateTexture(nil, "BORDER", nil, -1)
    bottom:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 0, 0)
    bottom:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
    bottom:SetHeight(borderWidth)
    bottom:SetColorTexture(ar, ag, ab, borderAlpha)
    border.BOTTOM = bottom

    -- LEFT
    local left = btn:CreateTexture(nil, "BORDER", nil, -1)
    left:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
    left:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 0, 0)
    left:SetWidth(borderWidth)
    left:SetColorTexture(ar, ag, ab, borderAlpha)
    border.LEFT = left

    -- RIGHT
    local right = btn:CreateTexture(nil, "BORDER", nil, -1)
    right:SetPoint("TOPRIGHT", btn, "TOPRIGHT", 0, 0)
    right:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
    right:SetWidth(borderWidth)
    right:SetColorTexture(ar, ag, ab, borderAlpha)
    border.RIGHT = right

    btn._border = border

    -- Label text
    local label = btn:CreateFontString(nil, "OVERLAY")
    local fontPath = theme:GetFont("BUTTON")
    label:SetFont(fontPath, fontSize, "")
    label:SetPoint("CENTER", 0, 0)
    label:SetText(text)
    label:SetTextColor(ar, ag, ab, 1)
    btn._label = label

    -- Auto-size width based on text if not specified
    if options.width then
        btn:SetWidth(options.width)
    else
        -- Set a reasonable initial width immediately (prevents square buttons)
        local textWidth = label:GetStringWidth()
        if textWidth and textWidth > 0 then
            btn:SetWidth(textWidth + (DEFAULT_BUTTON_PADDING * 2))
        else
            -- Font not loaded yet (first game launch) - use fallback then re-measure
            -- Estimate: ~7px per character for JetBrains Mono at 12pt
            local estimatedWidth = (#text * 7) + (DEFAULT_BUTTON_PADDING * 2)
            btn:SetWidth(math.max(estimatedWidth, 50))

            -- Re-measure after font loads
            C_Timer.After(0, function()
                if btn and btn._label then
                    local actualWidth = btn._label:GetStringWidth()
                    if actualWidth and actualWidth > 0 then
                        btn:SetWidth(actualWidth + (DEFAULT_BUTTON_PADDING * 2))
                    end
                end
            end)
        end
    end

    -- Store original text for reference
    btn._text = text

    -- Hover handlers
    btn:SetScript("OnEnter", function(self)
        local r, g, b = theme:GetAccentColor()
        self._hoverFill:SetColorTexture(r, g, b, 1)
        self._hoverFill:Show()
        self._label:SetTextColor(0, 0, 0, 1)  -- Dark text on accent bg
    end)

    btn:SetScript("OnLeave", function(self)
        self._hoverFill:Hide()
        local r, g, b = theme:GetAccentColor()
        self._label:SetTextColor(r, g, b, 1)  -- Accent text on dark bg
    end)

    -- Secure action setup (if requested)
    if options.secureAction and type(options.secureAction) == "table" then
        local action = options.secureAction
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
            btn._pendingSecureAction = applySecureAction
            btn:RegisterEvent("PLAYER_REGEN_ENABLED")
            btn:HookScript("OnEvent", function(self, event)
                if event == "PLAYER_REGEN_ENABLED" then
                    if self._pendingSecureAction then
                        self._pendingSecureAction()
                        self._pendingSecureAction = nil
                    end
                    self:UnregisterEvent("PLAYER_REGEN_ENABLED")
                end
            end)
        else
            applySecureAction()
        end
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

    -- Generate unique subscription key
    local subscribeKey = "Button_" .. (name or tostring(btn))
    btn._subscribeKey = subscribeKey

    -- Subscribe to theme updates
    theme:Subscribe(subscribeKey, function(r, g, b)
        -- Update border (using stored alpha)
        if btn._border then
            local alpha = btn._borderAlpha or 1
            for _, tex in pairs(btn._border) do
                tex:SetColorTexture(r, g, b, alpha)
            end
        end
        -- Update hover fill color (in case it's showing)
        if btn._hoverFill then
            btn._hoverFill:SetColorTexture(r, g, b, 1)
        end
        -- Update label if not hovering
        if btn._label and not btn:IsMouseOver() then
            btn._label:SetTextColor(r, g, b, 1)
        end
    end)

    -- Public methods
    function btn:SetText(newText)
        self._text = newText
        self._label:SetText(newText)
        -- Optionally resize if auto-width
        if not options.width then
            local textWidth = self._label:GetStringWidth()
            if textWidth and textWidth > 0 then
                self:SetWidth(textWidth + (DEFAULT_BUTTON_PADDING * 2))
            else
                -- Font not loaded yet - estimate then re-measure
                local estimatedWidth = (#newText * 7) + (DEFAULT_BUTTON_PADDING * 2)
                self:SetWidth(math.max(estimatedWidth, 50))
                local selfRef = self
                C_Timer.After(0, function()
                    if selfRef and selfRef._label then
                        local actualWidth = selfRef._label:GetStringWidth()
                        if actualWidth and actualWidth > 0 then
                            selfRef:SetWidth(actualWidth + (DEFAULT_BUTTON_PADDING * 2))
                        end
                    end
                end)
            end
        end
    end

    function btn:GetText()
        return self._text
    end

    function btn:SetEnabled(enabled)
        if enabled then
            self:Enable()
            local r, g, b = theme:GetAccentColor()
            local alpha = self._borderAlpha or 1
            for _, tex in pairs(self._border) do
                tex:SetColorTexture(r, g, b, alpha)
            end
            self._label:SetTextColor(r, g, b, 1)
        else
            self:Disable()
            -- Dim the button when disabled (relative to base alpha)
            local baseAlpha = self._borderAlpha or 1
            local dimAlpha = baseAlpha * 0.4
            for _, tex in pairs(self._border) do
                local r, g, b = theme:GetAccentColor()
                tex:SetColorTexture(r, g, b, dimAlpha)
            end
            local r, g, b = theme:GetAccentColor()
            self._label:SetTextColor(r, g, b, 0.4)
        end
    end

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
