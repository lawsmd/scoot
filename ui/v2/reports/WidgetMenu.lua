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

-- Mirrors Flyout.lua's content inset (FLYOUT_CONTENT_PADDING + border width).
local FLYOUT_INSET = 9

-- Widget flyoutDirection is lowercase; the flyout control expects uppercase.
local DIR_MAP = { down = "DOWN", up = "UP", left = "LEFT", right = "RIGHT" }

local flyout = nil
local rowPool = {}
local explanationText = nil
local savedStrata, savedLevel = nil, nil

-- Scoot's proportional UI face in Medium: the settings panel's face, a touch
-- heavier because this text is read against the game world. Theme validates
-- the path and owns the fallback chain; addon.GetDefaultFontFace resolves to
-- GameFontNormal (Friz Quadrata) and would not match.
local function getFont()
    local theme = addon.UI and addon.UI.Theme
    if theme and theme.GetFont then return theme:GetFont("PROPORTIONAL_MED") end
    return (addon.Fonts and addon.Fonts.ROBOTO_MED) or "Fonts\\FRIZQT__.TTF"
end

-- The panel overlaps the diamond's near half, so the diamond has to draw on
-- top of it; otherwise the box simply swallows half the icon. Both values are
-- restored on close, and the frame is Scoot-owned so re-strata'ing is safe.
local function setWidgetAbovePanel(above)
    local W = addon.Widget
    local frame = W and W:GetFrame()
    if not frame then return end
    if above then
        if savedStrata then return end
        savedStrata = frame:GetFrameStrata()
        savedLevel = frame:GetFrameLevel()
        frame:SetFrameStrata("FULLSCREEN_DIALOG")
        frame:SetFrameLevel(flyout:GetFrameLevel() + 10)
    elseif savedStrata then
        frame:SetFrameStrata(savedStrata)
        frame:SetFrameLevel(savedLevel)
        savedStrata, savedLevel = nil, nil
        -- Any flyout child (a report panel) has its level pinned relative to
        -- the widget's; re-derive it now that the widget is back where it was.
        W:_ReflowFlyoutChildren()
    end
end

--------------------------------------------------------------------------------
-- Content
--------------------------------------------------------------------------------

local function acquireRow(content, index, padTop, padLeft)
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
    local y = -(padTop + (index - 1) * ROW_HEIGHT)
    btn:SetParent(content)
    btn:ClearAllPoints()
    btn:SetPoint("TOPLEFT", content, "TOPLEFT", padLeft, y)
    btn:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, y)
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

-- Rebuilds the menu body and returns the content height it needs, padTop
-- included. padTop/padLeft push content clear of the overlapping diamond.
local function buildContent(padTop, padLeft)
    local content = flyout:GetContent()
    hideAllRows()

    local enabled = addon.Reports and addon.Reports:GetEnabled() or {}

    if #enabled > 0 then
        for i, def in ipairs(enabled) do
            local btn = acquireRow(content, i, padTop, padLeft)
            btn._text:SetText(def.label)
            btn:SetScript("OnClick", function()
                flyout:Close()
                addon.Reports:Run(def.id, { source = "widgetMenu" })
            end)
        end
        return padTop + #enabled * ROW_HEIGHT
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
    explanationText:SetPoint("TOPLEFT", content, "TOPLEFT", padLeft, -padTop)
    explanationText:SetWidth(MENU_WIDTH - 2 * FLYOUT_INSET)
    explanationText:SetText(addon.Reports and addon.Reports.WIDGET_EXPLANATION or "")
    explanationText:Show()
    return padTop + math.ceil(explanationText:GetStringHeight()) + 4
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
        -- The diamond itself is the pointer; a nub would double up on it.
        showNub = false,
        onShow = function() setWidgetAbovePanel(true) end,
        onHide = function() setWidgetAbovePanel(false) end,
    })
    return flyout
end

-- Rebuilds content and resizes the panel to fit it, for one direction.
-- Idempotent: safe to run again on an already-open menu.
local function layoutMenu(dir)
    -- The diamond's near half sits inside the panel. The widget owns this
    -- geometry so every surface it spawns overlaps the same way; the flyout's
    -- content frame is already inset, so that much of the intrusion is free.
    local padTop, padLeft, extraH, extraW = addon.Widget:GetHeadInset(dir, FLYOUT_INSET)

    -- Reports > Config owns one backdrop opacity for every surface the diamond
    -- spawns, and the menu is one of them. Applied here rather than once at
    -- creation: the menu rebuilds on every open, which is also the only moment
    -- it can have gone stale (the click-away listener means it can never be
    -- open while the user is dragging the slider).
    local Reports = addon.Reports
    if Reports and Reports.GetBackdropAlpha then
        flyout:SetBackdropAlpha(Reports:GetBackdropAlpha())
    end

    local contentHeight = buildContent(padTop, padLeft)
    -- Content is inset by padding + border on each side (see Flyout.lua).
    flyout:SetFlyoutSize(MENU_WIDTH + extraW, contentHeight + 2 * FLYOUT_INSET + extraH)
end

function Menu:Toggle()
    if not ensureFlyout() then return end

    if flyout:IsOpen() then
        flyout:Close()
        return
    end

    local W = addon.Widget

    -- A running report occupies the same space this menu opens into, so
    -- clicking the diamond again dismisses it and returns to the list. The
    -- diamond is the way back out of anything it spawned.
    if W.HasFlyoutChildren and W:HasFlyoutChildren() then
        W:ReleaseAllFlyoutChildren()
    end

    local dir = DIR_MAP[W:GetFlyoutDirection()] or "DOWN"
    flyout:SetAnchor(W:GetFrame())
    flyout:SetDirection(dir)

    -- Pull the panel back onto the diamond by its centre-to-corner distance,
    -- so the panel's near edge runs exactly through the diamond's two side
    -- corners and the diamond reads as the panel's head.
    flyout:SetGap(-W:GetHeadOffset())

    layoutMenu(dir)
    flyout:Open()

    -- GetStringHeight() reports a single-line height until the FontString has
    -- been rendered once, and the panel is still hidden during the
    -- layout pass above. On the first open after a reload that sizes the panel
    -- to one line and the rest of the text clips out through the bottom border
    -- (later opens reuse an already-laid-out FontString, so they measure
    -- correctly, which is what makes the bug look intermittent). Re-measure now
    -- that the panel has been shown. Same deferred-measure pattern as
    -- SettingsBuilder:AddDescription and notes.lua.
    C_Timer.After(0, function()
        if flyout and flyout:IsOpen() then
            layoutMenu(dir)
        end
    end)
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
