-- Tag.lua - a short word in a thin box: APPLIED, PRIVATE, VOICE, a status a
-- row carries beside its text.
--
-- opts:
--   text        the word
--   tone        "accent" (default), "dim", another color token, or a
--               { r, g, b, a } literal; the box and the word take it
--   fontRole    default "miniLabel"
--   padX, padY  the room inside the box; default 4 and 1
--   filled      the box painted in the tone and the word in the window's
--               solid background color, a key to press next
--
-- Returns a frame sized to its word, carrying _text and the methods
-- SetText(text), SetTone(tone), GetTone(), SetFilled(on). An accent tag
-- follows the accent through one shared subscription; the rest hold their
-- color.
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.Controls = addon.UI.Controls or {}
local Controls = addon.UI.Controls

-- The tags on the accent, repainted together when it changes
local accentTags = setmetatable({}, { __mode = "k" })
local subscribed = false

local function EnsureSubscription()
    if subscribed then return end
    local Theme = addon.UI.Theme
    if not Theme then return end
    subscribed = true
    Theme:Subscribe("ControlsTags", function()
        for tag in pairs(accentTags) do
            tag:Paint()
        end
    end)
end

function Controls.CreateTag(parent, opts)
    opts = opts or {}
    local Theme = addon.UI.Theme
    local Chrome = addon.UI.Chrome
    local padX = opts.padX or 4
    local padY = opts.padY or 1

    local tag = CreateFrame("Frame", nil, parent)
    local text = tag:CreateFontString(nil, "OVERLAY")
    Theme:ApplyFont(text, opts.fontRole or "miniLabel")
    text:SetPoint("CENTER", tag, "CENTER", 0, 0)
    text:SetJustifyH("CENTER")
    text:SetWordWrap(false)
    tag._text = text

    local fill = tag:CreateTexture(nil, "BACKGROUND")
    fill:SetAllPoints(tag)
    fill:SetColorTexture(1, 1, 1, 1)
    fill:Hide()
    tag._fill = fill

    local function Fit()
        local w = (text:GetStringWidth() or 0) + padX * 2
        local h = (text:GetStringHeight() or 0) + padY * 2
        tag:SetSize(math.max(w, 1), math.max(h, 1))
    end

    local function ToneColor(tone)
        if tone == "accent" then
            local r, g, b = Theme:GetAccentColor()
            return r, g, b, 1
        end
        return Chrome.Color(tone)
    end

    -- The word and the fill from the tone; the border paints itself
    function tag:Paint()
        local r, g, b, a = ToneColor(self._tone)
        if self._filled then
            fill:SetVertexColor(r, g, b, a or 1)
            fill:Show()
            local br, bg, bb = Theme:GetBackgroundSolidColor()
            text:SetTextColor(br, bg, bb, 1)
        else
            fill:Hide()
            text:SetTextColor(r, g, b, a or 1)
        end
    end

    function tag:SetTone(tone)
        tone = tone or "accent"
        self._tone = tone
        if self._border and self._border.Destroy then self._border:Destroy() end
        if tone == "accent" then
            -- A themed border follows the accent on its own
            self._border = Controls.CreateBorder(self, { thickness = 1, alpha = 0.8 })
            accentTags[self] = true
            EnsureSubscription()
        else
            accentTags[self] = nil
            local r, g, b, a = Chrome.Color(tone)
            self._border = Controls.CreateBorder(self, { thickness = 1, color = { r, g, b }, alpha = (a or 1) * 0.8 })
        end
        self:Paint()
    end

    function tag:SetFilled(on)
        on = on and true or false
        if self._filled == on then return end
        self._filled = on
        self:Paint()
    end

    function tag:GetTone()
        return self._tone
    end

    function tag:SetText(value)
        text:SetText(value or "")
        Fit()
    end

    tag._filled = opts.filled and true or false
    tag:SetTone(opts.tone)
    tag:SetText(opts.text)
    return tag
end
