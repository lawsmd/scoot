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
--
-- The beta badge is a third role, badge, on a factory of its own at the end
-- of this file: the word beside the name of a feature under test, with the
-- same tooltip.
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
    local tooltip = CreateFrame("Frame", addon.Brand .. "InfoTooltip", UIParent)
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

-- Show the shared tooltip above owner. The tooltip is shared, so every show
-- retints it (or resets it to the accent) and a previous caller's variant
-- tint never carries into this hover. A variant tint reaches the flat border
-- only: the nine-slice carries the client's own border and its fill in one
-- set of pieces, and tinting them would take the fill with it.
local function ShowTooltipAbove(owner, title, text, tint)
    local tooltip = GetOrCreateTooltip()
    tooltip:SetContent(title, text)
    local tr, tg, tb
    if tint then
        tr, tg, tb = tint[1], tint[2], tint[3]
    else
        tr, tg, tb = GetTheme():GetAccentColor()
    end
    if tooltip._titleText then
        tooltip._titleText:SetTextColor(tr, tg, tb, 1)
    end
    if tooltip._border then
        for _, tex in pairs(tooltip._border) do
            tex:SetColorTexture(tr, tg, tb, 1)
        end
    end
    -- Above the owner, clear of the cursor
    tooltip:ShowAtAnchor(owner, "BOTTOMLEFT", "TOPLEFT", 0, 4)
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

        ShowTooltipAbove(self, self._tooltipTitle, self._tooltipText, self._tooltipTint)
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

-- The beta badge: the word a feature under test carries beside its name, on
-- a nav row and on a window's title, with a note under the cursor. The badge
-- role draws it.
--
--   flat   the word in the role's color inside a box of that color, built as
--          an info icon is: text, color, width, height, fontSize, fontStyle
--   label  the word alone in the role's font role, sized to the word: text,
--          fontRole, color, shadow (the drop shadow's color), copyOffset (a
--          second string in the shadow color that far off the first) and
--          glow, an atlas descriptor drawn reach past the word. The glow is
--          outside the frame's rect, so a neighbour that anchors to the badge
--          anchors to the word. Clicks pass through to what is under it, and
--          opts.onHover(over) tells the owner the cursor is on the word, so a
--          row the badge stands on can keep its hover art.
--
-- Returns the frame, or nil with no parent. It carries gap, the room the
-- role asks a neighbour to leave before it; Fit(), which sizes a label to
-- its word again; SetDimmed(on), for a row whose module is off; Cleanup().
local BETA_TITLE = "Beta Feature"
local BETA_TEXT = "This feature is new and may need additional testing. Please report any issues you encounter."

function Controls.CreateBetaBadge(parent, opts)
    if not parent then return nil end
    local onHover = opts and opts.onHover
    local theme = GetTheme()
    local Chrome = addon.UI.Chrome
    local spec = Chrome.Spec("badge")
    local flat = Chrome.FLAT.badge

    if spec.kind ~= "label" then
        local r, g, b = Chrome.Color(spec.color or flat.color)
        local badge = Controls:CreateInfoIcon({
            parent = parent,
            tooltipTitle = BETA_TITLE,
            tooltipText = BETA_TEXT,
            size = spec.height or flat.height,
            width = spec.width or flat.width,
            iconType = "info",
            customText = spec.text or flat.text,
            colorOverride = { r, g, b },
        })
        if not badge then return nil end
        theme:ApplyFont(badge._iconText, "button", spec.fontSize or flat.fontSize, spec.fontStyle or flat.fontStyle)
        badge.gap = spec.gap or flat.gap

        function badge:Fit() end

        function badge:SetDimmed(on)
            if on then
                local dr, dg, db = theme:GetDimTextColor()
                self._iconText:SetTextColor(dr, dg, db, 0.35)
                for _, tex in pairs(self._border) do
                    tex:SetColorTexture(dr, dg, db, 0.15)
                end
            else
                self._iconText:SetTextColor(r, g, b, 1)
                self._border:Refresh()
            end
        end

        return badge
    end

    local badge = CreateFrame("Frame", nil, parent)
    badge:SetFrameLevel((parent:GetFrameLevel() or 1) + 10)
    badge.gap = spec.gap or flat.gap

    local word = spec.text or flat.text
    local text = badge:CreateFontString(nil, "OVERLAY")
    theme:ApplyFont(text, spec.fontRole or "miniLabel")
    text:SetPoint("CENTER", badge, "CENTER", 0, 0)
    text:SetWordWrap(false)
    text:SetTextColor(Chrome.Color(spec.color or "white"))
    if spec.shadow then
        text:SetShadowColor(Chrome.Color(spec.shadow))
    end
    text:SetText(word)
    badge._text = text

    -- The copy sits a draw layer under the word: two strings on one layer
    -- have no order between them.
    local offset = spec.shadow and spec.copyOffset
    if offset then
        local copy = badge:CreateFontString(nil, "ARTWORK")
        theme:ApplyFont(copy, spec.fontRole or "miniLabel", nil, "NONE")
        copy:SetPoint("CENTER", text, "CENTER", offset[1] or 0, offset[2] or 0)
        copy:SetWordWrap(false)
        copy:SetTextColor(Chrome.Color(spec.shadow))
        copy:SetText(word)
    end

    -- A glow the client lacks resolves to nothing and the word stands alone
    local glowSpec = spec.glow and Chrome.Resolve(spec.glow)
    if glowSpec and glowSpec.kind == "atlas" and glowSpec.atlas then
        local reach = glowSpec.reach or {}
        local glow = badge:CreateTexture(nil, "BORDER")
        glow:SetAtlas(glowSpec.atlas)
        glow:SetPoint("TOPLEFT", text, "TOPLEFT", -(reach.left or 0), reach.top or 0)
        glow:SetPoint("BOTTOMRIGHT", text, "BOTTOMRIGHT", reach.right or 0, -(reach.bottom or 0))
        glow:SetAlpha(glowSpec.alpha or 1)
    end

    -- A string measured before its first layout can read 0, and a frame with
    -- no size has no rect, so the floor is 1 and a caller measures again.
    function badge:Fit()
        self:SetSize(math.max(text:GetStringWidth() or 0, 1), math.max(text:GetStringHeight() or 0, 1))
    end
    badge:Fit()

    function badge:SetDimmed(on)
        self:SetAlpha(on and 0.35 or 1)
    end

    function badge:Cleanup() end

    -- The scripts go on first: SetScript turns clicks back on.
    badge:SetScript("OnEnter", function(self)
        if onHover then onHover(true) end
        ShowTooltipAbove(self, BETA_TITLE, BETA_TEXT)
    end)
    badge:SetScript("OnLeave", function()
        if onHover then onHover(false) end
        GetOrCreateTooltip():Hide()
    end)
    badge:SetMouseClickEnabled(false)

    return badge
end
