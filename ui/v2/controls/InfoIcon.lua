-- InfoIcon.lua - Compact info icon with TUI-styled tooltip
-- Provides help/info icons for tabs, headers, and other compact UI elements
-- Default position: LEFT side of labels (matching TUI convention)
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

local DEFAULT_ICON_SIZE = 16
local TOOLTIP_FONT_SIZE = 11
local TOOLTIP_TITLE_FONT_SIZE = 12
local TOOLTIP_PADDING = 10
local TOOLTIP_BORDER_WIDTH = 2
local TOOLTIP_MAX_WIDTH = 280
local HOVER_ALPHA = 0.25
local BORDER_WIDTH = 1

-- Custom TUI Tooltip Frame (themed border, dark background, monospace fonts)

local ScootTooltip = nil

local function GetOrCreateTooltip()
    if ScootTooltip then return ScootTooltip end

    local theme = GetTheme()
    local ar, ag, ab = theme:GetAccentColor()
    local bgR, bgG, bgB = theme:GetBackgroundSolidColor()

    local tooltip = CreateFrame("Frame", "ScootInfoTooltip", UIParent)
    tooltip:SetFrameStrata("TOOLTIP")
    tooltip:SetFrameLevel(100)
    tooltip:Hide()

    -- Background
    local bg = tooltip:CreateTexture(nil, "BACKGROUND", nil, -8)
    bg:SetPoint("TOPLEFT", TOOLTIP_BORDER_WIDTH, -TOOLTIP_BORDER_WIDTH)
    bg:SetPoint("BOTTOMRIGHT", -TOOLTIP_BORDER_WIDTH, TOOLTIP_BORDER_WIDTH)
    bg:SetColorTexture(bgR, bgG, bgB, 0.98)
    tooltip._bg = bg

    -- Border (four edges)
    local border = {}

    local top = tooltip:CreateTexture(nil, "BORDER", nil, -1)
    top:SetPoint("TOPLEFT", tooltip, "TOPLEFT", 0, 0)
    top:SetPoint("TOPRIGHT", tooltip, "TOPRIGHT", 0, 0)
    top:SetHeight(TOOLTIP_BORDER_WIDTH)
    top:SetColorTexture(ar, ag, ab, 1)
    border.TOP = top

    local bottom = tooltip:CreateTexture(nil, "BORDER", nil, -1)
    bottom:SetPoint("BOTTOMLEFT", tooltip, "BOTTOMLEFT", 0, 0)
    bottom:SetPoint("BOTTOMRIGHT", tooltip, "BOTTOMRIGHT", 0, 0)
    bottom:SetHeight(TOOLTIP_BORDER_WIDTH)
    bottom:SetColorTexture(ar, ag, ab, 1)
    border.BOTTOM = bottom

    local left = tooltip:CreateTexture(nil, "BORDER", nil, -1)
    left:SetPoint("TOPLEFT", tooltip, "TOPLEFT", 0, 0)
    left:SetPoint("BOTTOMLEFT", tooltip, "BOTTOMLEFT", 0, 0)
    left:SetWidth(TOOLTIP_BORDER_WIDTH)
    left:SetColorTexture(ar, ag, ab, 1)
    border.LEFT = left

    local right = tooltip:CreateTexture(nil, "BORDER", nil, -1)
    right:SetPoint("TOPRIGHT", tooltip, "TOPRIGHT", 0, 0)
    right:SetPoint("BOTTOMRIGHT", tooltip, "BOTTOMRIGHT", 0, 0)
    right:SetWidth(TOOLTIP_BORDER_WIDTH)
    right:SetColorTexture(ar, ag, ab, 1)
    border.RIGHT = right

    tooltip._border = border

    -- Title text (accent colored)
    local titleFont = theme:GetFont("BUTTON")
    local titleText = tooltip:CreateFontString(nil, "OVERLAY")
    pcall(titleText.SetFont, titleText, titleFont, TOOLTIP_TITLE_FONT_SIZE, "")
    titleText:SetPoint("TOPLEFT", tooltip, "TOPLEFT", TOOLTIP_PADDING + TOOLTIP_BORDER_WIDTH, -TOOLTIP_PADDING - TOOLTIP_BORDER_WIDTH)
    titleText:SetTextColor(ar, ag, ab, 1)
    titleText:SetJustifyH("LEFT")
    titleText:SetWidth(TOOLTIP_MAX_WIDTH - (TOOLTIP_PADDING * 2) - (TOOLTIP_BORDER_WIDTH * 2))
    titleText:SetWordWrap(true)
    tooltip._titleText = titleText

    -- Body text (white)
    local bodyFont = theme:GetFont("VALUE")
    local bodyText = tooltip:CreateFontString(nil, "OVERLAY")
    pcall(bodyText.SetFont, bodyText, bodyFont, TOOLTIP_FONT_SIZE, "")
    bodyText:SetPoint("TOPLEFT", titleText, "BOTTOMLEFT", 0, -4)
    bodyText:SetTextColor(1, 1, 1, 1)
    bodyText:SetJustifyH("LEFT")
    bodyText:SetWidth(TOOLTIP_MAX_WIDTH - (TOOLTIP_PADDING * 2) - (TOOLTIP_BORDER_WIDTH * 2))
    bodyText:SetWordWrap(true)
    tooltip._bodyText = bodyText

    theme:Subscribe("ScootInfoTooltip", function(r, g, b)
        for _, tex in pairs(tooltip._border) do
            tex:SetColorTexture(r, g, b, 1)
        end
        tooltip._titleText:SetTextColor(r, g, b, 1)
    end)

    function tooltip:SetContent(title, body)
        if title and title ~= "" then
            self._titleText:SetText(title)
            self._titleText:Show()
            self._bodyText:SetPoint("TOPLEFT", self._titleText, "BOTTOMLEFT", 0, -4)
        else
            self._titleText:SetText("")
            self._titleText:Hide()
            self._bodyText:SetPoint("TOPLEFT", self, "TOPLEFT", TOOLTIP_PADDING + TOOLTIP_BORDER_WIDTH, -TOOLTIP_PADDING - TOOLTIP_BORDER_WIDTH)
        end

        self._bodyText:SetText(body or "")

        local titleHeight = (title and title ~= "") and (self._titleText:GetStringHeight() + 4) or 0
        local bodyHeight = self._bodyText:GetStringHeight()
        local totalHeight = TOOLTIP_PADDING * 2 + TOOLTIP_BORDER_WIDTH * 2 + titleHeight + bodyHeight

        local titleWidth = (title and title ~= "") and self._titleText:GetStringWidth() or 0
        local bodyWidth = self._bodyText:GetStringWidth()
        local contentWidth = math.max(titleWidth, bodyWidth)
        local totalWidth = math.min(TOOLTIP_MAX_WIDTH, contentWidth + TOOLTIP_PADDING * 2 + TOOLTIP_BORDER_WIDTH * 2)

        self:SetSize(totalWidth, totalHeight)
    end

    function tooltip:ShowAtAnchor(anchor, point, relPoint, offsetX, offsetY)
        self:ClearAllPoints()
        self:SetPoint(point or "TOPLEFT", anchor, relPoint or "BOTTOMLEFT", offsetX or 0, offsetY or -4)
        self:Show()
    end

    ScootTooltip = tooltip
    return tooltip
end

-- InfoIcon: Small "i" or "?" icon that shows a tooltip on hover.
-- Default position: left side of labels (use CreateInfoIconForLabel).

function Controls:CreateInfoIcon(options)
    local theme = GetTheme()
    if not options or not options.parent then
        return nil
    end
    if not options.tooltipText or options.tooltipText == "" then
        return nil
    end

    local parent = options.parent
    local tooltipText = options.tooltipText
    local tooltipTitle = options.tooltipTitle
    local size = options.size or DEFAULT_ICON_SIZE
    local iconType = options.iconType or "info"
    local name = options.name

    local ar, ag, ab = theme:GetAccentColor()
    local bgR, bgG, bgB, bgA = theme:GetBackgroundSolidColor()

    local icon = CreateFrame("Button", name, parent)
    icon:SetSize(size, size)
    icon:EnableMouse(true)

    local parentLevel = parent:GetFrameLevel() or 1
    icon:SetFrameLevel(parentLevel + 10)

    local bg = icon:CreateTexture(nil, "BACKGROUND", nil, -8)
    bg:SetAllPoints(icon)
    bg:SetColorTexture(bgR, bgG, bgB, 0.6)
    icon._bg = bg

    local border = {}

    local top = icon:CreateTexture(nil, "BORDER", nil, -1)
    top:SetPoint("TOPLEFT", icon, "TOPLEFT", 0, 0)
    top:SetPoint("TOPRIGHT", icon, "TOPRIGHT", 0, 0)
    top:SetHeight(BORDER_WIDTH)
    top:SetColorTexture(ar, ag, ab, 0.6)
    border.TOP = top

    local bottom = icon:CreateTexture(nil, "BORDER", nil, -1)
    bottom:SetPoint("BOTTOMLEFT", icon, "BOTTOMLEFT", 0, 0)
    bottom:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 0, 0)
    bottom:SetHeight(BORDER_WIDTH)
    bottom:SetColorTexture(ar, ag, ab, 0.6)
    border.BOTTOM = bottom

    local left = icon:CreateTexture(nil, "BORDER", nil, -1)
    left:SetPoint("TOPLEFT", icon, "TOPLEFT", 0, 0)
    left:SetPoint("BOTTOMLEFT", icon, "BOTTOMLEFT", 0, 0)
    left:SetWidth(BORDER_WIDTH)
    left:SetColorTexture(ar, ag, ab, 0.6)
    border.LEFT = left

    local right = icon:CreateTexture(nil, "BORDER", nil, -1)
    right:SetPoint("TOPRIGHT", icon, "TOPRIGHT", 0, 0)
    right:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 0, 0)
    right:SetWidth(BORDER_WIDTH)
    right:SetColorTexture(ar, ag, ab, 0.6)
    border.RIGHT = right

    icon._border = border

    -- Hover highlight background
    local hoverBg = icon:CreateTexture(nil, "BACKGROUND", nil, -7)
    hoverBg:SetPoint("TOPLEFT", BORDER_WIDTH, -BORDER_WIDTH)
    hoverBg:SetPoint("BOTTOMRIGHT", -BORDER_WIDTH, BORDER_WIDTH)
    hoverBg:SetColorTexture(ar, ag, ab, HOVER_ALPHA)
    hoverBg:Hide()
    icon._hoverBg = hoverBg

    local iconText = icon:CreateFontString(nil, "OVERLAY")
    local fontPath = theme:GetFont("BUTTON")
    local fontSize = math.max(size - 4, 8)  -- Scale font with icon size
    pcall(iconText.SetFont, iconText, fontPath, fontSize, "")
    iconText:SetPoint("CENTER", 0, 0)
    iconText:SetText(iconType == "help" and "?" or "i")
    iconText:SetTextColor(ar, ag, ab, 1)
    icon._iconText = iconText

    icon._tooltipText = tooltipText
    icon._tooltipTitle = tooltipTitle

    icon:SetScript("OnEnter", function(self)
        local r, g, b = theme:GetAccentColor()
        self._hoverBg:SetColorTexture(r, g, b, HOVER_ALPHA)
        self._hoverBg:Show()

        for _, tex in pairs(self._border) do
            tex:SetColorTexture(r, g, b, 1)
        end

        -- Position above icon to avoid cursor blocking
        local tooltip = GetOrCreateTooltip()
        tooltip:SetContent(self._tooltipTitle, self._tooltipText)
        tooltip:ShowAtAnchor(self, "BOTTOMLEFT", "TOPLEFT", 0, 4)
    end)

    icon:SetScript("OnLeave", function(self)
        self._hoverBg:Hide()
        local r, g, b = theme:GetAccentColor()
        for _, tex in pairs(self._border) do
            tex:SetColorTexture(r, g, b, 0.6)
        end

        local tooltip = GetOrCreateTooltip()
        tooltip:Hide()
    end)

    local subscribeKey = "InfoIcon_" .. (name or tostring(icon))
    icon._subscribeKey = subscribeKey

    theme:Subscribe(subscribeKey, function(r, g, b)
        if icon._border then
            local alpha = icon:IsMouseOver() and 1 or 0.6
            for _, tex in pairs(icon._border) do
                tex:SetColorTexture(r, g, b, alpha)
            end
        end
        if icon._hoverBg then
            icon._hoverBg:SetColorTexture(r, g, b, HOVER_ALPHA)
        end
        if icon._iconText then
            icon._iconText:SetTextColor(r, g, b, 1)
        end
    end)

    function icon:SetTooltipText(text)
        self._tooltipText = text
    end

    function icon:SetTooltipTitle(title)
        self._tooltipTitle = title
    end

    function icon:GetTooltipText()
        return self._tooltipText
    end

    function icon:Cleanup()
        if self._subscribeKey then
            theme:Unsubscribe(self._subscribeKey)
        end
    end

    return icon
end

-- Create info icon anchored to a FontString label (default: left side)

function Controls:CreateInfoIconForLabel(options)
    if not options or not options.label then
        return nil
    end

    local label = options.label
    local parent = label:GetParent()
    if not parent then
        return nil
    end

    local offsetX = options.offsetX or -4
    local offsetY = options.offsetY or 0
    local position = options.position or "left"
    local iconSize = options.size or 14

    local icon = self:CreateInfoIcon({
        parent = parent,
        tooltipText = options.tooltipText,
        tooltipTitle = options.tooltipTitle,
        size = iconSize,
        iconType = options.iconType,
        name = options.name,
    })

    if not icon then return nil end

    if position == "right" then
        icon:SetPoint("LEFT", label, "RIGHT", math.abs(offsetX), offsetY)
    else
        icon:SetPoint("RIGHT", label, "LEFT", offsetX, offsetY)
    end

    return icon
end

-- Quick info icon creation for tabs/headers

function Controls:QuickInfoIcon(parent, tooltipText, size)
    return self:CreateInfoIcon({
        parent = parent,
        tooltipText = tooltipText,
        size = size or 14,
    })
end
