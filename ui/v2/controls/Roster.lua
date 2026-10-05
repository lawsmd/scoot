-- Roster.lua - a group's members as lines: a role shape, then the member in
-- their class color, with the leader's mark and a trailing number on the
-- line that carries them. The grid is a fixed count of lines at a fixed
-- height, so a row of two members stands as tall as a row of five; a line
-- with no member is blank, or a hollow shape for a slot still open.
--
-- The role column is an icon per role when the caller names a set,
-- desaturated and tinted the line's color, else a dim font shape (a filled
-- square, a circled plus and a filled diamond for tank, healer and
-- damage). A slot with no member is a blank line. The leader's mark is
-- whatever texture the caller names, tinted the line's color; the control
-- names no art of its own.
--
-- opts:
--   lines       the grid's line count; default 5
--   lineHeight  default 13
--   width       default 150
--   fontSize    the text's size; default the desc role's
--   glyphWidth  the role column; default 14
--   gap         between the role column, the text, the mark and the
--               trailing text; default 4
--   icons       { TANK, HEALER, DAMAGER } atlas names for the role column
--   iconSize    default 12
--   glyphs      { TANK, HEALER, DAMAGER } shapes, without icons
--   leaderMark  { atlas } or { file, coords } for the leader's mark; none
--               draws no mark
--   markWidth, markHeight
--               the mark's size; default 14 and 9
--   markY       the mark's lift above the line's middle, for a mark that
--               should centre on the text's letters rather than its line
--               box; default 0
--
-- SetLines(list): entry i fills line i and a missing one blanks it. An
-- entry is { role, filled, color = { r, g, b }, text, leader, trailing }:
-- filled false blanks the line as a missing entry does; filled true draws
-- the role, the text in color (the primary text color without one), the
-- mark after the text when leader is set, and trailing after the mark in
-- the same color. No role draws no icon and starts the text at the
-- column's left. The text gives way to the mark and the trailing text when
-- the line is short. SetDimmed(on) halves the alpha; Repaint() re-reads
-- the skin's colors, and every roster repaints together on a skin change.
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.Controls = addon.UI.Controls or {}
local Controls = addon.UI.Controls

local DEFAULTS = {
    lines = 5, lineHeight = 13, width = 150,
    glyphWidth = 14, gap = 4, iconSize = 12,
    markWidth = 14, markHeight = 9,
    dimmedAlpha = 0.5,
}

-- A filled square, a circled plus and a filled diamond
local GLYPHS = { TANK = "\226\150\160", HEALER = "\226\138\149", DAMAGER = "\226\151\134" }

-- Every control, repainted together on a skin change
local live = setmetatable({}, { __mode = "k" })
local subscribed = false

local function EnsureSubscription()
    if subscribed then return end
    local Theme = addon.UI.Theme
    if not Theme then return end
    subscribed = true
    Theme:Subscribe("ControlsRoster", function()
        for control in pairs(live) do
            if control.Repaint then control:Repaint() end
        end
    end)
end

function Controls.CreateRoster(parent, opts)
    opts = opts or {}
    local Theme = addon.UI.Theme
    local lines = opts.lines or DEFAULTS.lines
    local lineHeight = opts.lineHeight or DEFAULTS.lineHeight
    local width = opts.width or DEFAULTS.width
    local fontSize = opts.fontSize
    local glyphWidth = opts.glyphWidth or DEFAULTS.glyphWidth
    local gap = opts.gap or DEFAULTS.gap
    local glyphs = opts.glyphs or GLYPHS
    local icons = type(opts.icons) == "table" and opts.icons or nil
    local iconSize = opts.iconSize or DEFAULTS.iconSize
    local leaderMark = type(opts.leaderMark) == "table" and opts.leaderMark or nil
    local markWidth = opts.markWidth or DEFAULTS.markWidth
    local markHeight = opts.markHeight or DEFAULTS.markHeight
    local markY = opts.markY or 0

    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(width, lines * lineHeight)
    frame._entries = {}
    frame._lines = {}

    local function Font(fs)
        Theme:ApplyFont(fs, "desc", fontSize)
    end

    -- Each line's regions hang off the frame's top left at the line's
    -- middle, so the grid reads from the top down
    for i = 1, lines do
        local y = -((i - 1) * lineHeight) - lineHeight / 2
        local glyph = frame:CreateFontString(nil, "OVERLAY")
        Font(glyph)
        glyph:SetPoint("LEFT", frame, "TOPLEFT", 0, y)
        glyph:SetWidth(glyphWidth)
        glyph:SetJustifyH("CENTER")
        glyph:Hide()

        local icon = frame:CreateTexture(nil, "OVERLAY")
        icon:SetSize(iconSize, iconSize)
        icon:SetPoint("CENTER", frame, "TOPLEFT", glyphWidth / 2, y)
        icon:Hide()

        local text = frame:CreateFontString(nil, "OVERLAY")
        Font(text)
        text:SetPoint("LEFT", frame, "TOPLEFT", glyphWidth + gap, y)
        text:SetJustifyH("LEFT")
        text:SetWordWrap(false)
        text:Hide()

        local mark = frame:CreateTexture(nil, "OVERLAY")
        mark:SetSize(markWidth, markHeight)
        if leaderMark then
            if leaderMark.atlas then
                mark:SetAtlas(leaderMark.atlas)
                mark:SetDesaturated(true)
            elseif leaderMark.file then
                mark:SetTexture(leaderMark.file)
                local c = leaderMark.coords
                if type(c) == "table" then mark:SetTexCoord(c[1], c[2], c[3], c[4]) end
            end
        end
        mark:Hide()

        local trailing = frame:CreateFontString(nil, "OVERLAY")
        Font(trailing)
        trailing:SetJustifyH("LEFT")
        trailing:Hide()

        frame._lines[i] = { y = y, glyph = glyph, icon = icon, text = text, mark = mark, trailing = trailing }
    end

    local function Blank(line)
        line.glyph:Hide()
        line.icon:Hide()
        line.text:Hide()
        line.mark:Hide()
        line.trailing:Hide()
    end

    -- The shape is dim; the icon, the text, the mark and the trailing text
    -- take the line's color
    local function Paint(line, entry)
        local dr, dg, db = Theme:GetDimTextColor()
        line.glyph:SetTextColor(dr, dg, db, 1)
        local c = entry.color
        local r, g, b
        if type(c) == "table" then
            r, g, b = c[1] or 1, c[2] or 1, c[3] or 1
        else
            r, g, b = Theme:GetPrimaryTextColor()
        end
        line.icon:SetVertexColor(r, g, b, 1)
        line.text:SetTextColor(r, g, b, 1)
        line.trailing:SetTextColor(r, g, b, 1)
        line.mark:SetVertexColor(r, g, b, 1)
    end

    -- An empty string has no rect, so what follows it hangs off the frame
    local function Fill(line, entry)
        local role = entry.role
        local atlas = role and icons and icons[role] or nil
        local shape = role and not atlas and glyphs[role] or nil
        if atlas then
            line.icon:SetAtlas(atlas)
            line.icon:SetDesaturated(true)
            line.icon:Show()
            line.glyph:Hide()
        elseif shape then
            Font(line.glyph)
            line.glyph:SetText(shape)
            line.glyph:Show()
            line.icon:Hide()
        else
            line.glyph:Hide()
            line.icon:Hide()
        end

        local left = role and (glyphWidth + gap) or 0
        local text = entry.text
        local hasText = type(text) == "string" and text ~= ""
        line.text:ClearAllPoints()
        line.text:SetPoint("LEFT", frame, "TOPLEFT", left, line.y)
        line.text:SetWidth(0)
        if hasText then
            Font(line.text)
            line.text:SetText(text)
            line.text:Show()
        else
            line.text:SetText("")
            line.text:Hide()
        end

        local showMark = entry.leader and leaderMark and true or false
        local trailingText = entry.trailing
        local hasTrailing = type(trailingText) == "string" and trailingText ~= ""
        local room = width - left

        local after, afterPoint, offset = frame, "TOPLEFT", left
        if hasText then after, afterPoint, offset = line.text, "RIGHT", gap end

        line.mark:ClearAllPoints()
        if showMark then
            line.mark:SetPoint("LEFT", after, afterPoint, offset, (hasText and 0 or line.y) + markY)
            line.mark:Show()
            room = room - markWidth - gap
            after, afterPoint, offset = line.mark, "RIGHT", gap
        else
            line.mark:Hide()
        end

        line.trailing:ClearAllPoints()
        if hasTrailing then
            Font(line.trailing)
            line.trailing:SetText(trailingText)
            line.trailing:SetPoint("LEFT", after, afterPoint, offset, after == frame and line.y or 0)
            line.trailing:Show()
            room = room - (line.trailing:GetStringWidth() or 0) - gap
        else
            line.trailing:SetText("")
            line.trailing:Hide()
        end

        if hasText and (line.text:GetStringWidth() or 0) > room then
            line.text:SetWidth(math.max(1, room))
        end
        Paint(line, entry)
    end

    function frame:SetLines(list)
        self._entries = list or {}
        for i = 1, lines do
            local entry = self._entries[i]
            if entry and entry.filled then
                Fill(self._lines[i], entry)
            else
                Blank(self._lines[i])
            end
        end
    end

    function frame:Repaint()
        for i = 1, lines do
            local entry = self._entries[i]
            if entry and entry.filled then Paint(self._lines[i], entry) end
        end
    end

    function frame:SetDimmed(on)
        self:SetAlpha(on and DEFAULTS.dimmedAlpha or 1)
    end

    live[frame] = true
    EnsureSubscription()
    return frame
end
