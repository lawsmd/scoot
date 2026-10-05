-- CheckBox.lua - the square mark of a check list or a radio choice: an
-- empty square while off, and while on the same square with a smaller
-- filled square inside it, a line of clear space between the two. No art
-- and no word; the caller colors it with the text it stands beside, so the
-- mark reads as part of the row under every skin.
--
-- The row's own toggle is the ON/OFF pill (Toggle.lua); this is the mark
-- for a list where several rows are on at once, or one of several is.
--
-- opts:
--   size       the square's edge; default 11
--   border     the outer square's line; default 1
--   gap        the clear line between the square and the inner fill;
--              default 2
--   clickable  a Button that takes the click itself; otherwise a Frame with
--              no mouse, which the row under it clicks through
--   onClick    the Button's click
--   color      { r, g, b, a } to start on; default the accent
-- Returns the frame, with SetChecked(on), IsChecked(), SetColor(r, g, b, a),
-- SetEdge(size), which re-insets the fill, and Repaint().
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.Controls = addon.UI.Controls or {}
local Controls = addon.UI.Controls

local DEFAULTS = { size = 11, border = 1, gap = 2 }

function Controls.CreateCheckBox(parent, opts)
    opts = opts or {}
    local Theme = addon.UI.Theme
    local size = opts.size or DEFAULTS.size
    local borderWidth = opts.border or DEFAULTS.border
    local gap = opts.gap or DEFAULTS.gap

    local frame = CreateFrame(opts.clickable and "Button" or "Frame", nil, parent)
    frame:SetSize(size, size)
    if opts.clickable then
        frame:EnableMouse(true)
        frame:RegisterForClicks("AnyUp")
        if opts.onClick then frame:SetScript("OnClick", opts.onClick) end
    end

    local r, g, b, a = 1, 1, 1, 1
    if type(opts.color) == "table" then
        r, g, b, a = opts.color[1] or 1, opts.color[2] or 1, opts.color[3] or 1, opts.color[4] or 1
    elseif Theme then
        r, g, b = Theme:GetAccentColor()
    end

    -- Static colors: SetColor owns every tint
    local border = Controls.CreateBorder(frame, {
        thickness = borderWidth,
        corners = "overlap",
        layer = "ARTWORK",
        sublevel = 0,
        color = { r, g, b, a },
    })
    local fill = frame:CreateTexture(nil, "ARTWORK", nil, 1)
    fill:SetColorTexture(r, g, b, a)
    fill:Hide()

    local function InsetFill()
        local inset = borderWidth + gap
        fill:ClearAllPoints()
        fill:SetPoint("TOPLEFT", frame, "TOPLEFT", inset, -inset)
        fill:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -inset, inset)
    end
    InsetFill()

    frame._checked = false
    frame._color = { r, g, b, a }

    function frame:Repaint()
        local c = self._color
        for _, tex in pairs(border) do
            tex:SetColorTexture(c[1], c[2], c[3], c[4])
        end
        fill:SetColorTexture(c[1], c[2], c[3], c[4])
        fill:SetShown(self._checked)
    end

    function frame:SetChecked(on)
        self._checked = on and true or false
        fill:SetShown(self._checked)
    end

    function frame:IsChecked()
        return self._checked
    end

    function frame:SetColor(cr, cg, cb, ca)
        local c = self._color
        c[1], c[2], c[3], c[4] = cr or 1, cg or 1, cb or 1, ca or 1
        self:Repaint()
    end

    function frame:SetEdge(edge)
        size = edge or size
        self:SetSize(size, size)
        InsetFill()
    end

    return frame
end
