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

    local tooltip = CreateFrame("Frame", "ScootInfoTooltip", UIParent)
    tooltip:SetFrameStrata("TOOLTIP")
    tooltip:SetFrameLevel(100)
    tooltip:Hide()

    -- Background
    tooltip._bg = Controls.AddBackground(tooltip, { inset = TOOLTIP_BORDER_WIDTH, alpha = 0.98 })

    -- Border (four edges)
    tooltip._border = Controls.CreateBorder(tooltip, {
        thickness = TOOLTIP_BORDER_WIDTH,
        corners = "overlap",
    })

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

-- Normalizes an info icon spec to the shape CreateInfoIcon reads. Accepts
-- tooltipText / tooltipTitle or the shorter text / title (UF.TOOLTIPS and
-- GF.TOOLTIPS use the latter). Returns nil when there is no text to show, so
-- a gate is "if spec then".
function Controls.InfoIconOptions(spec)
    if type(spec) ~= "table" then return nil end
    local text = spec.tooltipText or spec.text
    if type(text) ~= "string" or text == "" then return nil end
    return {
        tooltipText = text,
        tooltipTitle = spec.tooltipTitle or spec.title,
        size = spec.size,
    }
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
    local colorOverride = options.colorOverride
    local width = options.width or size

    local ar, ag, ab
    if colorOverride then
        ar, ag, ab = colorOverride[1], colorOverride[2], colorOverride[3]
    else
        ar, ag, ab = theme:GetAccentColor()
    end

    local icon = CreateFrame("Button", name, parent)
    icon:SetSize(width, size)
    icon:EnableMouse(true)
    icon._colorOverride = colorOverride

    local parentLevel = parent:GetFrameLevel() or 1
    icon:SetFrameLevel(parentLevel + 10)

    icon._bg = Controls.AddBackground(icon, { alpha = 0.6 })

    icon._border = Controls.CreateBorder(icon, {
        thickness = BORDER_WIDTH,
        color = colorOverride,
        alpha = 0.6,
        getAlpha = function(self) return self:IsMouseOver() and 1 or 0.6 end,
    })

    -- Hover highlight background
    icon._hoverBg = Controls.AddHoverFill(icon, { alpha = HOVER_ALPHA, inset = BORDER_WIDTH })

    local iconText = icon:CreateFontString(nil, "OVERLAY")
    local fontPath = theme:GetFont("BUTTON")
    local fontSize = math.max(size - 4, 8)  -- Scale font with icon size
    pcall(iconText.SetFont, iconText, fontPath, fontSize, "")
    iconText:SetPoint("CENTER", 0, -1)
    local displayText = options.customText or (iconType == "help" and "?" or "i")
    iconText:SetText(displayText)
    iconText:SetTextColor(ar, ag, ab, 1)
    icon._iconText = iconText

    icon._tooltipText = tooltipText
    icon._tooltipTitle = tooltipTitle
    icon._tooltipTint = options.tooltipTint

    icon:SetScript("OnEnter", function(self)
        local r, g, b
        if self._colorOverride then
            r, g, b = self._colorOverride[1], self._colorOverride[2], self._colorOverride[3]
        else
            r, g, b = theme:GetAccentColor()
        end
        self._hoverBg:SetColorTexture(r, g, b, HOVER_ALPHA)
        self._hoverBg:Show()

        self._border:Refresh()

        -- Position above icon to avoid cursor blocking
        local tooltip = GetOrCreateTooltip()
        tooltip:SetContent(self._tooltipTitle, self._tooltipText)
        -- The tooltip is shared; always retint it (or reset to accent) so a
        -- previous caller's variant tint never bleeds into this hover.
        local tr, tg, tb
        if self._tooltipTint then
            tr, tg, tb = self._tooltipTint[1], self._tooltipTint[2], self._tooltipTint[3]
        else
            tr, tg, tb = theme:GetAccentColor()
        end
        if tooltip._titleText then
            tooltip._titleText:SetTextColor(tr, tg, tb, 1)
        end
        if tooltip._border then
            for _, tex in pairs(tooltip._border) do
                tex:SetColorTexture(tr, tg, tb, 1)
            end
        end
        tooltip:ShowAtAnchor(self, "BOTTOMLEFT", "TOPLEFT", 0, 4)
    end)

    icon:SetScript("OnLeave", function(self)
        self._hoverBg:Hide()
        self._border:Refresh()

        local tooltip = GetOrCreateTooltip()
        tooltip:Hide()
    end)

    local subscribeKey = "InfoIcon_" .. (name or tostring(icon))
    icon._subscribeKey = subscribeKey

    if not colorOverride then
        theme:Subscribe(subscribeKey, function(r, g, b)
            if icon._iconText then
                icon._iconText:SetTextColor(r, g, b, 1)
            end
        end)
    end

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

function Controls:GetOrCreateTooltip()
    return GetOrCreateTooltip()
end
