--------------------------------------------------------------------------------
-- casttrack.lua
-- The text-fill cast bar track
-- Cast Bar X's text-fill mode (unitframes/cast/textfill.lua) and Cast Bar Z
-- (castbarz/frames.lua) draw the same twelve textures: a gray unfilled line
-- with tick-style end caps, a colored filled line whose right edge tracks the
-- fill texture, filled caps inside a clip frame that reveals them with the
-- sweep, and a 1px black outline behind each. Z was a port of X and the two
-- copies had drifted by one outline offset; this is the one place the layers,
-- sublevels, anchors, and outlines are written.
--
-- Create(host, clipParent, into) makes the twelve textures, eight on `host`
-- and the four filled caps and their outlines on `clipParent`, and writes them
-- into `into` under the shared field names. Layout(el, host, fillTex, geom)
-- anchors and colors them; the filled line and caps take their fill texture
-- and tint from the caller afterwards, since X and Z color them differently.
--
--   geom = {
--     lineHeight, capW, capH,              -- numbers; snap them first if you snap
--     gray = { r, g, b },                  -- the unfilled color
--     unfilledCapOutline = "box" | "open", -- a full 1px box around each unfilled
--                                          -- cap (X), or the three-sided box the
--                                          -- filled caps use (Z)
--   }
--------------------------------------------------------------------------------

local addonName, addon = ...

addon.CastTrack = addon.CastTrack or {}
local CastTrack = addon.CastTrack

-- Draw order, low to high: unfilled outlines, unfilled line, filled outline,
-- filled line, all BACKGROUND on the host; the caps at ARTWORK so a cap draws
-- over the line it ends.
function CastTrack.Create(host, clipParent, into)
    into.unfilledLineOL     = host:CreateTexture(nil, "BACKGROUND", nil, 0)
    into.unfilledLeftCapOL  = host:CreateTexture(nil, "BACKGROUND", nil, 0)
    into.unfilledRightCapOL = host:CreateTexture(nil, "BACKGROUND", nil, 0)
    into.unfilledLine       = host:CreateTexture(nil, "BACKGROUND", nil, 1)
    into.unfilledLeftCap    = host:CreateTexture(nil, "ARTWORK", nil, 1)
    into.unfilledRightCap   = host:CreateTexture(nil, "ARTWORK", nil, 1)

    -- On the host rather than the clip frame: the line's RIGHT edge tracks the
    -- fill texture, so progress needs no clipping, and the line stays below
    -- the host's OVERLAY text.
    into.filledLineOL = host:CreateTexture(nil, "BACKGROUND", nil, 2)
    into.filledLine   = host:CreateTexture(nil, "BACKGROUND", nil, 3)

    -- Inside the clip frame, so the sweep reveals them.
    into.filledLeftCapOL  = clipParent:CreateTexture(nil, "BACKGROUND", nil, 1)
    into.filledRightCapOL = clipParent:CreateTexture(nil, "BACKGROUND", nil, 1)
    into.filledLeftCap    = clipParent:CreateTexture(nil, "ARTWORK", nil, 2)
    into.filledRightCap   = clipParent:CreateTexture(nil, "ARTWORK", nil, 2)
    return into
end

-- A 1px black box behind `target`, 1px past its top and bottom edges and
-- `left` / `right` past its sides: -1 and 1 close the box, 0 leaves that side
-- open where the line joins the cap.
local function outline(ol, target, left, right)
    ol:ClearAllPoints()
    ol:SetPoint("TOPLEFT", target, "TOPLEFT", left, 1)
    ol:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", right, -1)
    ol:SetColorTexture(0, 0, 0, 1)
    ol:Show()
end

function CastTrack.Layout(el, host, fillTex, geom)
    local lineH, capW, capH = geom.lineHeight, geom.capW, geom.capH
    local gr, gg, gb = geom.gray[1], geom.gray[2], geom.gray[3]
    local boxed = geom.unfilledCapOutline == "box"

    -- Unfilled line: full width, centered vertically
    local t = el.unfilledLine
    t:ClearAllPoints()
    t:SetPoint("LEFT", host, "LEFT", 0, 0)
    t:SetPoint("RIGHT", host, "RIGHT", 0, 0)
    t:SetHeight(lineH)
    t:SetColorTexture(gr, gg, gb, 1)
    t:Show()
    outline(el.unfilledLineOL, t, -1, 1)

    t = el.unfilledLeftCap
    t:ClearAllPoints()
    t:SetPoint("LEFT", host, "LEFT", 0, 0)
    t:SetSize(capW, capH)
    t:SetColorTexture(gr, gg, gb, 1)
    t:Show()
    outline(el.unfilledLeftCapOL, t, -1, boxed and 1 or 0)

    t = el.unfilledRightCap
    t:ClearAllPoints()
    t:SetPoint("RIGHT", host, "RIGHT", 0, 0)
    t:SetSize(capW, capH)
    t:SetColorTexture(gr, gg, gb, 1)
    t:Show()
    outline(el.unfilledRightCapOL, t, boxed and -1 or 0, 1)

    -- Filled line: LEFT on the host, RIGHT on the fill texture, so progress is
    -- an anchor and needs no GetValue. Without a fill texture it has no width.
    t = el.filledLine
    t:ClearAllPoints()
    t:SetPoint("LEFT", host, "LEFT", 0, 0)
    if fillTex then
        t:SetPoint("RIGHT", fillTex, "RIGHT", 0, 0)
    else
        t:SetPoint("RIGHT", host, "LEFT", 0, 0)
    end
    t:SetHeight(lineH)
    t:Show()
    outline(el.filledLineOL, t, -1, 1)

    t = el.filledLeftCap
    t:ClearAllPoints()
    t:SetPoint("LEFT", host, "LEFT", 0, 0)
    t:SetSize(capW, capH)
    t:Show()
    outline(el.filledLeftCapOL, t, -1, 0)

    t = el.filledRightCap
    t:ClearAllPoints()
    t:SetPoint("RIGHT", host, "RIGHT", 0, 0)
    t:SetSize(capW, capH)
    t:Show()
    outline(el.filledRightCapOL, t, 0, 1)
end
