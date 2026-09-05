-- GlyphButton.lua - Small widgets for hand-rolled list rows: a hover-revealed
-- flat glyph button and a compact ON/OFF indicator.
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

-- An atlas name that does not resolve leaves the texture blank rather than
-- erroring, so a failed set falls back to art that resolves everywhere.
local FALLBACK_ATLAS = "common-icon-undo"

local DEFAULT_SIZE = 16

-- Flat glyph button: desaturated atlas tinted accent, brightening on hover,
-- named by tooltip. glyphScale grows the art without changing the button's
-- layout box (some atlases carry padding inside the glyph box and render
-- smaller than their neighbors). Starts hidden unless opts.shown: rows that
-- reveal their buttons on hover own the Show. The hover poke reads
-- parent.UpdateHover at event time, nil-guarded, because callers attach the
-- hover painter after the buttons exist.
-- opts: parent, atlas, tooltip, size (16), glyphScale (1), shown (false)
function Controls:CreateGlyphButton(opts)
    local theme = GetTheme()
    local ar, ag, ab = theme:GetAccentColor()
    local parent = opts.parent
    local tooltip = opts.tooltip
    local btn = CreateFrame("Button", nil, parent)
    local size = opts.size or DEFAULT_SIZE
    btn:SetSize(size, size)
    local tex = btn:CreateTexture(nil, "ARTWORK")
    local glyph = size * (opts.glyphScale or 1)
    tex:SetSize(glyph, glyph)
    tex:SetPoint("CENTER", 0, 0)
    if not pcall(tex.SetAtlas, tex, opts.atlas) or not tex:GetAtlas() then
        pcall(tex.SetAtlas, tex, FALLBACK_ATLAS)
    end
    tex:SetDesaturated(true)
    tex:SetVertexColor(ar, ag, ab)
    tex:SetAlpha(0.6)
    btn._tex = tex
    btn:SetScript("OnEnter", function()
        tex:SetAlpha(1)
        if parent.UpdateHover then parent.UpdateHover() end
        if tooltip then
            GameTooltip:SetOwner(btn, "ANCHOR_TOP")
            GameTooltip:SetText(tooltip, 1, 1, 1)
            GameTooltip:Show()
        end
    end)
    btn:SetScript("OnLeave", function()
        tex:SetAlpha(0.6)
        GameTooltip:Hide()
        if parent.UpdateHover then parent.UpdateHover() end
    end)
    if not opts.shown then btn:Hide() end
    return btn
end

-- Compact ON/OFF state indicator: bordered box with an accent fill and black
-- "ON" when on, dim hollow "OFF" when off. Returns the button carrying
-- btn:SetOn(isOn). Starts hidden unless opts.shown, for the same hover-reveal
-- rows the glyph button serves.
-- opts: parent, width (27), height (13), border (2), shown (false)
function Controls:CreateOnOffIndicator(opts)
    local theme = GetTheme()
    local ar, ag, ab = theme:GetAccentColor()
    local dimR, dimG, dimB = theme:GetDimTextColor()
    local btn = CreateFrame("Button", nil, opts.parent)
    local w = opts.width or 27
    local h = opts.height or 13
    local bw = opts.border or 2
    btn:SetSize(w, h)

    local border = Controls.CreateBorder(btn, {
        thickness = bw,
        color = { ar, ag, ab },
    })

    local fill = btn:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("TOPLEFT", bw, -bw)
    fill:SetPoint("BOTTOMRIGHT", -bw, bw)
    fill:SetColorTexture(ar, ag, ab, 1)

    local text = btn:CreateFontString(nil, "OVERLAY")
    text:SetFont(theme:GetFont("BUTTON"), 8, "")
    text:SetPoint("CENTER", 0, 0)

    btn.SetOn = function(_, isOn)
        border:SetAlpha(isOn and 1 or 0.4)
        fill:SetShown(isOn)
        if isOn then
            text:SetText("ON")
            text:SetTextColor(0, 0, 0, 1)
        else
            text:SetText("OFF")
            text:SetTextColor(dimR, dimG, dimB, 1)
        end
    end
    if not opts.shown then btn:Hide() end
    return btn
end
