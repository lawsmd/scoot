-- InfoIcon.lua - Compact info icon with a themed tooltip
-- Provides help/info icons for tabs, headers, and other compact UI elements
-- Default position: LEFT side of labels (matching TUI convention)
--
-- Two chrome roles draw it: infoIcon is the icon, tooltip is the box its text
-- opens in. Flat, the default both roles take, is the bordered square with a
-- character in it and the accent-bordered box under it. A skin that declares
-- kind "glyph" on infoIcon draws art alone, no box, at the role's scale times
-- the size the caller asks for; a skin that declares kind "nineSlice" on
-- tooltip hands the box to the client's own tooltip art. A badge, the letter
-- in its own color that marks a component variant, stays flat under every
-- skin: the letter is the content, not the chrome.
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

-- The tooltip frame: the panel's own text on the surface the tooltip role
-- draws. Flat is the accent border over a near-black fill; a nineSlice role
-- is the client's tooltip art, border and fill together, on a child a level
-- under the frame so the text keeps the top. _pad is the inset the text
-- keeps off the edge, and the size math reads it.
--
-- One frame, built on the first hover and kept. A skin switch rebuilds the
-- panel around it and never reaches it, so the surface, the two fonts and the
-- padding are reapplied here instead: the resolved descriptor is memoized per
-- role and invalidated with the switch, so a table that is not the one that
-- drew the box means a new skin.

local ScootTooltip = nil

local function ApplySurface(tooltip, spec)
    if tooltip._nine then
        tooltip._nine:Destroy()
        tooltip._nine = nil
    end
    if tooltip._border then
        tooltip._border:Destroy()
        tooltip._border = nil
    end
    if tooltip._bg then
        tooltip._bg:Hide()
        tooltip._bg = nil
    end

    local pad = TOOLTIP_PADDING + TOOLTIP_BORDER_WIDTH
    if spec.kind == "nineSlice" then
        local nine = addon.UI.Chrome.NineSlice(tooltip, spec)
        nine:SetFrameLevel(math.max(tooltip:GetFrameLevel() - 1, 0))
        tooltip._nine = nine
        pad = spec.padding or pad
    else
        tooltip._bg = Controls.AddBackground(tooltip, { inset = TOOLTIP_BORDER_WIDTH, alpha = 0.98 })
        tooltip._border = Controls.CreateBorder(tooltip, {
            thickness = TOOLTIP_BORDER_WIDTH,
            corners = "overlap",
        })
    end
    tooltip._pad = pad
    tooltip._spec = spec

    local theme = GetTheme()
    local titleText, bodyText = tooltip._titleText, tooltip._bodyText
    pcall(titleText.SetFont, titleText, theme:GetFont("BUTTON"), TOOLTIP_TITLE_FONT_SIZE, "")
    pcall(bodyText.SetFont, bodyText, theme:GetFont("VALUE"), TOOLTIP_FONT_SIZE, "")
    titleText:ClearAllPoints()
    titleText:SetPoint("TOPLEFT", tooltip, "TOPLEFT", pad, -pad)
    titleText:SetWidth(TOOLTIP_MAX_WIDTH - pad * 2)
    bodyText:SetWidth(TOOLTIP_MAX_WIDTH - pad * 2)
end

local function GetOrCreateTooltip()
    local spec = addon.UI.Chrome.Spec("tooltip")
    if ScootTooltip then
        if ScootTooltip._spec ~= spec then ApplySurface(ScootTooltip, spec) end
        return ScootTooltip
    end

    local theme = GetTheme()
    local ar, ag, ab = theme:GetAccentColor()

    -- Brand-named: both addons load this file in the retail client.
    local tooltip = CreateFrame("Frame", (addon.Brand or "Scoot") .. "InfoTooltip", UIParent)
    tooltip:SetFrameStrata("TOOLTIP")
    tooltip:SetFrameLevel(100)
    tooltip:Hide()

    -- Title text (accent colored)
    local titleText = tooltip:CreateFontString(nil, "OVERLAY")
    titleText:SetTextColor(ar, ag, ab, 1)
    titleText:SetJustifyH("LEFT")
    titleText:SetWordWrap(true)
    tooltip._titleText = titleText

    -- Body text (white)
    local bodyText = tooltip:CreateFontString(nil, "OVERLAY")
    bodyText:SetPoint("TOPLEFT", titleText, "BOTTOMLEFT", 0, -4)
    bodyText:SetTextColor(1, 1, 1, 1)
    bodyText:SetJustifyH("LEFT")
    bodyText:SetWordWrap(true)
    tooltip._bodyText = bodyText

    ApplySurface(tooltip, spec)

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
            self._bodyText:SetPoint("TOPLEFT", self, "TOPLEFT", self._pad, -self._pad)
        end

        self._bodyText:SetText(body or "")

        local titleHeight = (title and title ~= "") and (self._titleText:GetStringHeight() + 4) or 0
        local bodyHeight = self._bodyText:GetStringHeight()
        local totalHeight = self._pad * 2 + titleHeight + bodyHeight

        local titleWidth = (title and title ~= "") and self._titleText:GetStringWidth() or 0
        local bodyWidth = self._bodyText:GetStringWidth()
        local contentWidth = math.max(titleWidth, bodyWidth)
        local totalWidth = math.min(TOOLTIP_MAX_WIDTH, contentWidth + self._pad * 2)

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

    local icon = CreateFrame("Button", name, parent)
    icon:EnableMouse(true)
    icon._colorOverride = colorOverride

    local parentLevel = parent:GetFrameLevel() or 1
    icon:SetFrameLevel(parentLevel + 10)

    -- A badge carries its own letter in its own color, so it keeps the flat
    -- box whatever the skin says; only the plain help icon takes the art.
    local Chrome = addon.UI.Chrome
    local spec = Chrome.Spec("infoIcon")
    local glyphs = spec.glyphs or {}
    local art = spec.kind == "glyph" and not colorOverride and not options.customText

    -- The color of the character or the art, by state. A colorOverride is the
    -- caller's and outranks the skin; a flat skin names no glyph color and
    -- takes the accent, which is the color the icon has always drawn in.
    local function GlyphColor(state)
        if colorOverride then
            return colorOverride[1], colorOverride[2], colorOverride[3], 1
        end
        local colors = spec.glyphColors
        local token = colors and (colors[state] or colors.normal)
        if token then return Chrome.Color(token) end
        local r, g, b = theme:GetAccentColor()
        return r, g, b, 1
    end

    if art then
        -- The art's letter is drawn in the middle of its texture, so the
        -- button takes the role's scale of the size asked for and every
        -- layout that measures the icon follows it.
        local drawn = size * (spec.scale or 1)
        icon:SetSize(drawn, drawn)
        icon._glyph = Chrome.Glyph(icon, glyphs[iconType] or glyphs.info, {
            layer = "OVERLAY", size = drawn,
        })
        icon._glyph.region:SetPoint("CENTER")
    else
        icon:SetSize(width, size)
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
        local displayText = options.customText
            or (type(glyphs[iconType]) == "string" and glyphs[iconType])
            or (iconType == "help" and "?" or "i")
        iconText:SetText(displayText)
        icon._iconText = iconText
    end

    -- Repaint under the cursor and off it, and whenever the accent moves.
    local function Repaint(hover)
        local r, g, b, a = GlyphColor(hover and "hover" or "normal")
        if icon._glyph then
            icon._glyph:SetColor(r, g, b, a)
        elseif icon._iconText then
            icon._iconText:SetTextColor(r, g, b, a or 1)
        end
    end
    Repaint(false)

    icon._tooltipText = tooltipText
    icon._tooltipTitle = tooltipTitle
    icon._tooltipTint = options.tooltipTint

    icon:SetScript("OnEnter", function(self)
        Repaint(true)
        if self._hoverBg then
            local r, g, b
            if self._colorOverride then
                r, g, b = self._colorOverride[1], self._colorOverride[2], self._colorOverride[3]
            else
                r, g, b = theme:GetAccentColor()
            end
            self._hoverBg:SetColorTexture(r, g, b, HOVER_ALPHA)
            self._hoverBg:Show()
        end

        if self._border then self._border:Refresh() end

        -- Position above icon to avoid cursor blocking
        local tooltip = GetOrCreateTooltip()
        tooltip:SetContent(self._tooltipTitle, self._tooltipText)
        -- The tooltip is shared; always retint it (or reset to accent) so a
        -- previous caller's variant tint never bleeds into this hover. A
        -- variant tint reaches the flat border only: the nine-slice carries
        -- the client's own border and its fill in one set of pieces, and
        -- tinting them would take the fill with it.
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
        Repaint(false)
        if self._hoverBg then self._hoverBg:Hide() end
        if self._border then self._border:Refresh() end

        local tooltip = GetOrCreateTooltip()
        tooltip:Hide()
    end)

    local subscribeKey = "InfoIcon_" .. (name or tostring(icon))
    icon._subscribeKey = subscribeKey

    if not colorOverride then
        theme:Subscribe(subscribeKey, function()
            Repaint(icon:IsMouseOver())
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
