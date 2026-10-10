-- scootauras/pips.lua - Segment and row geometry shared by the pip displays
--
-- The Class Resource kind (classresource.lua) and the stacks kinds
-- (stacks.lua) both draw N segments across a bar or N shapes in a row. The
-- arithmetic lives here once, so the two displays tile the same way.
local addonName, addon = ...

local SAU = addon.ScootAuras

local Pips = {}
SAU.Pips = Pips

--- Segment i of n across innerW pixels, with a tick of `tick` px between
-- neighbours: the segment's left and right edges from the left, rounded.
-- The segments tile the width exactly, so the right edge of segment i is
-- where the tick after it starts. A continuous fill at i/n of the width
-- ends inside that tick (i * innerW / n = x1 + tick * (1 - i / n)), which
-- is what lets one engine-fed fill read as i whole segments under the ticks.
function Pips.SegmentEdges(innerW, n, tick, i)
    n = math.max(1, n or 1)
    tick = math.max(0, tick or 0)
    local segW = (innerW - (n - 1) * tick) / n
    if segW < 1 then segW = 1 end
    local x0 = math.floor((i - 1) * (segW + tick) + 0.5)
    local x1 = math.floor(i * segW + (i - 1) * tick + 0.5)
    return x0, x1
end

--- The width of n shapes of `size` px with `gap` px between neighbours.
function Pips.RowWidth(n, size, gap)
    n = math.max(1, n or 1)
    return n * size + (n - 1) * (gap or 0)
end

--- The border of a bordered shape key: 0 for a plain key, else 1 px per 20
-- px of shape, at least 1. A fixed 1 px ring vanishes on a large shape under
-- a UI scale below 1.
function Pips.BorderWidth(key, size)
    if not SAU._ShapeKeyIsBordered(key) then return 0 end
    return math.max(1, math.floor((size or 16) / 20 + 0.5))
end

--- The ring of a bordered shape: the same atlas in black, at the full cell,
-- beneath the inset shape. Hidden when `width` is 0.
function Pips.PaintRing(ring, atlas, width)
    if width <= 0 then
        ring:Hide()
        return
    end
    if pcall(ring.SetAtlas, ring, atlas) then
        -- A white mask ignores desaturation alone, so both calls.
        ring:SetDesaturated(true)
        ring:SetVertexColor(0, 0, 0, 1)
    else
        ring:SetColorTexture(0, 0, 0, 1)
    end
    ring:SetAlpha(1)
    ring:Show()
end
