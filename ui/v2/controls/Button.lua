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

    -- Background (dark, shown always)
    btn._bg = Controls.AddBackground(btn, { inset = borderWidth })

    -- Hover fill (accent color, hidden by default)
    btn._hoverFill = Controls.AddHoverFill(btn, { alpha = 1, inset = borderWidth })

    -- Border (four edges)
    btn._border = Controls.CreateBorder(btn, {
        thickness = borderWidth,
        corners = "overlap",
        alpha = borderAlpha,
    })

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
            -- Queue on the shared regen drain instead of registering events on
            -- the secure button itself. Keyed per button: a reconfigure before
            -- regen replaces the queued attribute batch.
            addon.Events.RunOutOfCombat(applySecureAction, btn)
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

    -- Subscribe to theme updates (border and hover fill retint via Utils)
    theme:Subscribe(subscribeKey, function(r, g, b)
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
        local r, g, b = theme:GetAccentColor()
        if enabled then
            self:Enable()
            self._border:SetAlpha(self._borderAlpha or 1)
            self._label:SetTextColor(r, g, b, 1)
        else
            self:Disable()
            -- Dim the button when disabled (relative to base alpha)
            self._border:SetAlpha((self._borderAlpha or 1) * 0.4)
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
