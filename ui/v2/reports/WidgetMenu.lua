-- WidgetMenu.lua - Click menu for the widget diamond: lists enabled reports
--
-- Transient surface: a themed flyout anchored to the diamond, rebuilt on
-- every open so it always reflects the current enabled set (no reload
-- needed). Deliberately NOT a widget flyout child — RegisterFlyoutChild is
-- reserved for persistent surfaces (report panels, future notifications), so
-- the menu never disturbs that chain.
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.Reports = addon.UI.Reports or {}
local Menu = {}
addon.UI.Reports.WidgetMenu = Menu

local MENU_WIDTH = 220
local ROW_HEIGHT = 26
local ROW_FONT_SIZE = 11
local EXPLANATION_FONT_SIZE = 10

-- Widget flyoutDirection is lowercase; the flyout control expects uppercase.
local DIR_MAP = { down = "DOWN", up = "UP", left = "LEFT", right = "RIGHT" }

local flyout = nil
local rowPool = {}
local explanationText = nil

local function getFont()
    local face = addon.GetDefaultFontFace and addon.GetDefaultFontFace()
    if face then return face end
    return _G.GameFontNormal and _G.GameFontNormal:GetFont() or "Fonts\\FRIZQT__.TTF"
end

--------------------------------------------------------------------------------
-- Content
--------------------------------------------------------------------------------

local function acquireRow(content, index)
    local btn = rowPool[index]
    if not btn then
        btn = CreateFrame("Button", nil, content)
        btn:SetHeight(ROW_HEIGHT)

        local bg = btn:CreateTexture(nil, "BACKGROUND", nil, -6)
        bg:SetAllPoints()
        bg:SetColorTexture(1, 1, 1, 0)
        btn._bg = bg

        local txt = btn:CreateFontString(nil, "OVERLAY")
        txt:SetFont(getFont(), ROW_FONT_SIZE, "OUTLINE")
        txt:SetPoint("LEFT", 8, 0)
        txt:SetJustifyH("LEFT")
        btn._text = txt

        btn:SetScript("OnEnter", function(self)
            local theme = addon.UI.Theme
            local r, g, b = 1, 1, 1
            if theme and theme.GetAccentColor then r, g, b = theme:GetAccentColor() end
            self._bg:SetColorTexture(r, g, b, 0.12)
        end)
        btn:SetScript("OnLeave", function(self)
            self._bg:SetColorTexture(1, 1, 1, 0)
        end)

        rowPool[index] = btn
    end
    btn:SetParent(content)
    btn:ClearAllPoints()
    btn:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -((index - 1) * ROW_HEIGHT))
    btn:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -((index - 1) * ROW_HEIGHT))
    btn:Show()
    return btn
end

local function hideAllRows()
    for _, btn in ipairs(rowPool) do
        btn:Hide()
    end
    if explanationText then
        explanationText:Hide()
    end
end

-- Rebuilds the menu body and returns the content height it needs.
local function buildContent()
    local content = flyout:GetContent()
    hideAllRows()

    local enabled = addon.Reports and addon.Reports:GetEnabled() or {}

    if #enabled > 0 then
        for i, def in ipairs(enabled) do
            local btn = acquireRow(content, i)
            btn._text:SetText(def.label)
            btn:SetScript("OnClick", function()
                flyout:Close()
                addon.Reports:Run(def.id, { source = "widgetMenu" })
            end)
        end
        return #enabled * ROW_HEIGHT
    end

    -- Empty state: the widget is on but no report is — explain the diamond.
    if not explanationText then
        explanationText = content:CreateFontString(nil, "OVERLAY")
        explanationText:SetFont(getFont(), EXPLANATION_FONT_SIZE, "")
        explanationText:SetJustifyH("LEFT")
        explanationText:SetJustifyV("TOP")
        explanationText:SetWordWrap(true)
        explanationText:SetTextColor(0.85, 0.85, 0.85, 1)
    end
    explanationText:ClearAllPoints()
    explanationText:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
    explanationText:SetWidth(MENU_WIDTH - 2 * 8 - 2)
    explanationText:SetText((addon.Reports and addon.Reports.WIDGET_EXPLANATION or "")
        .. "\n\nNo reports are enabled yet. Enable them in Scoot Settings under Reports.")
    explanationText:Show()
    return math.ceil(explanationText:GetStringHeight()) + 4
end

--------------------------------------------------------------------------------
-- Open / close
--------------------------------------------------------------------------------

local function ensureFlyout()
    if flyout then return flyout end
    local W = addon.Widget
    local anchorFrame = W and W:GetFrame()
    if not anchorFrame then return nil end

    flyout = addon.UI.Controls:CreateFlyout({
        anchor = anchorFrame,
        direction = DIR_MAP[W:GetFlyoutDirection()] or "DOWN",
        width = MENU_WIDTH,
        height = 100,
        name = "ScootReportsMenu",
    })
    return flyout
end

function Menu:Toggle()
    if not ensureFlyout() then return end

    if flyout:IsOpen() then
        flyout:Close()
        return
    end

    local W = addon.Widget
    flyout:SetAnchor(W:GetFrame())
    flyout:SetDirection(DIR_MAP[W:GetFlyoutDirection()] or "DOWN")

    local contentHeight = buildContent()
    -- Content is inset by padding + border on each side (see Flyout.lua).
    flyout:SetFlyoutSize(MENU_WIDTH, contentHeight + 2 * (8 + 1))

    flyout:Open()
end

function Menu:Close()
    if flyout and flyout:IsOpen() then
        flyout:Close()
    end
end

--------------------------------------------------------------------------------
-- Wire the widget click
--------------------------------------------------------------------------------

addon.Widget:SetClickHandler(function()
    Menu:Toggle()
end)
