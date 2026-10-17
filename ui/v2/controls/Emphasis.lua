-- Emphasis.lua - The emphasized (hero) row's backdrop and numbers
-- Contract: a row control that takes `emphasized` calls
-- Controls.ResolveEmphasis(emphasized, rowWidth) once for the numbers it lays
-- itself out with (nil when the row is not emphasized), then
-- Controls.AddEmphasisChrome(row, emph) once the row frame exists, for the
-- backdrop. The `emphasis` chrome role decides the draw: flat is the accent
-- bar down the row's left edge over a faint accent wash; a sliced kind is the
-- skin's art around the whole row, and metrics.emphasis scales what the row
-- holds. The flat numbers are the skin's too, metrics.emphasisLabelSize and
-- metrics.emphasisBar, and the wash is Controls.ALPHA_EMPHASIS, on Utils'
-- accent registry so it retints with the theme. Selector.lua,
-- DualSelector.lua, Toggle.lua and Slider.lua read it.
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.Controls = addon.UI.Controls or {}
local Controls = addon.UI.Controls

--------------------------------------------------------------------------------
-- ResolveEmphasis
--------------------------------------------------------------------------------
-- Returns nil for a row that is not emphasized, else a table:
--   spec            the `emphasis` chrome role's spec
--   art             true when the role is drawn as art rather than flat
--   scale           metrics.emphasis.scale on an art row with a definite
--                   width, else 1: multiplies the name, the description and
--                   whatever else the caller scales
--   padX            the room inside the art's border left of the name and
--                   right of the control; nil on a flat row
--   padY            the room above the name and under the description, which
--                   the caller adds to its row height twice; 0 on a flat row
--   inner           the art border's depth, which the hover fill keeps inside
--   fillInset       where the role's fill starts, from the row's edge
--   labelFontRole   the name's font role on an art row; nil keeps the row role
--   labelFontSize   metrics.emphasisLabelSize, scaled
--   leftBorderWidth metrics.emphasisBar on a flat row, 0 on an art row
-- The scale and padY need a width-driven row (rowWidth), which every builder
-- row is; a direct caller without one keeps its fixed height table.
--------------------------------------------------------------------------------

function Controls.ResolveEmphasis(emphasized, rowWidth)
    if not emphasized then return nil end
    local spec = addon.UI.Chrome.Spec("emphasis")
    local art = spec ~= nil and spec.kind ~= "flat"
    local m = Controls.Metrics()
    local em = (art and m.emphasis) or {}
    local scale = (art and rowWidth and em.scale) or 1
    return {
        spec = spec,
        art = art,
        scale = scale,
        padX = art and em.padX or nil,
        padY = (art and rowWidth and em.padY) or 0,
        inner = art and em.inner or nil,
        fillInset = art and em.fillInset or nil,
        labelFontRole = art and em.labelFontRole or nil,
        labelFontSize = math.floor(m.emphasisLabelSize * scale + 0.5),
        leftBorderWidth = art and 0 or m.emphasisBar,
    }
end

--------------------------------------------------------------------------------
-- AddEmphasisChrome
--------------------------------------------------------------------------------
-- Draws the backdrop on the row frame and marks it. Writes row._emphasized,
-- and row._rowBorder and row._emphBg (flat) or row._emphArt and row._emphFill
-- (art); an art row also gets row._noDividerAfter, since the art closes it.
-- A nil `emph` draws nothing.
--------------------------------------------------------------------------------

function Controls.AddEmphasisChrome(row, emph)
    if not emph then return end
    row._emphasized = true

    if not emph.art then
        -- Kept off builder divider: left accent bar, not a row divider.
        row._rowBorder = Controls.CreateBorder(row, {
            sides = { "LEFT" },
            thickness = { LEFT = emph.leftBorderWidth },
            alpha = 1,
        })
        local emphBg = row:CreateTexture(nil, "BACKGROUND", nil, -7)
        emphBg:SetPoint("TOPLEFT", emph.leftBorderWidth, 0)
        emphBg:SetPoint("BOTTOMRIGHT", 0, 0)
        row._emphBg = Controls.RegisterThemedFill(emphBg, Controls.ALPHA_EMPHASIS)
        return
    end

    local Chrome = addon.UI.Chrome
    local art = Chrome.SlicedAtlas(row, emph.spec, "BACKGROUND", -8)
    if art then
        local pieces = emph.spec.pieces or {}
        art:ApplyOpacity(pieces.border or "cardBorder", pieces.fill or "cardFill")
        row._emphArt = art
        -- A fill replaces the art's own face, laid over the art's inner
        -- margin up to the border band: a color token, or a rect of an
        -- atlas member (in its own pixels) with a token to fall back on
        local fillSpec = emph.spec.fill
        if fillSpec then
            for _, t in ipairs(art.center) do t:Hide() end
            local fill = row:CreateTexture(nil, "BACKGROUND", nil, -7)
            local inset = emph.fillInset or 0
            fill:SetPoint("TOPLEFT", inset, -inset)
            fill:SetPoint("BOTTOMRIGHT", -inset, inset)
            local file, w, h, L, R, T, B
            if type(fillSpec) == "table" and fillSpec.atlas then
                file, w, h, L, R, T, B = Chrome.AtlasSource(fillSpec)
            end
            if file then
                local rect = fillSpec.rect or {}
                local du, dv = (R - L) / w, (B - T) / h
                fill:SetTexture(file)
                fill:SetTexCoord(L + (rect.left or 0) * du, L + (rect.right or w) * du,
                    T + (rect.top or 0) * dv, T + (rect.bottom or h) * dv)
                if fillSpec.piece then Chrome.ApplyOpacity(fillSpec.piece, fill) end
            else
                local token = type(fillSpec) == "table" and fillSpec.fallback or fillSpec
                fill:SetColorTexture(Chrome.Color(token))
            end
            row._emphFill = fill
        end
    end
    -- The art closes the row, so the builder's divider under it goes
    row._noDividerAfter = true
end
