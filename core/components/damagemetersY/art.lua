-- damagemetersY/art.lua - Art a window's backdrop, title bar or border draws in place of a flat color
local _, addon = ...
local DMY = addon.DamageMetersY

--------------------------------------------------------------------------------
-- The catalog
--------------------------------------------------------------------------------

-- The title bar's flat color, for a bar with no art (styling.lua, the preview).
DMY.TITLE_BAR_COLOR = { 0.08, 0.08, 0.10 }

-- The top edge of a metal-framed pane, as the member the Forever client serves
-- (atlas set 1, build 1.60.1.70790), two rows to a UI unit. Rows 26 to 35 are
-- the frame's thick border, 38 to 72 the title plate, 73 to 76 the bronze line
-- under it, 77 to 80 that line's dark outline and 81 to 85 its shadow.
local EDGE_TOP = "_UI-Frame-Metal-EdgeTop"
local EDGE_TOP_SIZE = { 256, 190 }

-- The plate's bottom line, drawn thinner than the member has it (2 units of
-- bronze over 2 of outline): each band is squeezed to `units`, and no thinner
-- than one screen pixel. The bronze is cut from its two brightest rows, which
-- still read as bronze at one pixel.
local BRONZE_LINE = { rows = { 75, 77 }, units = 1 }
local BRONZE_OUTLINE = { rows = { 77, 81 }, units = 0.5 }

-- key -> what one slot draws: "window" is the backdrop, "title" the title bar,
-- "border" the line around the window.
--
-- A file entry tiles both ways at the file's own size.
--
-- An atlas entry is read by rows of the member it was measured on: `measured`
-- is that member's size in its own pixels and perUnit its pixels per UI unit.
-- One atlas name answers with different art on each client, so an entry is
-- offered only where the member the client serves has the measured shape.
--   fill     the rows stretched over the title bar inside its line
--   line     the rows of the bronze line and how thick it draws
--   outline  the same for the dark line outside the bronze
--   shadow   the same for the shadow under the title bar
DMY.PanelArt = {
    -- The rock behind the class and level line of the Character pane
    -- (PaperDollFrame.TopBackgroundStripHost.TopBackgroundStrip).
    rock = {
        slot = "window", label = "Rock",
        file = "Interface\\FrameGeneral\\UI-Background-Rock",
    },
    -- The title plate inside its bottom line, drawn on all four sides. Around
    -- a window whose border is an art line the plate keeps the bottom line
    -- only: the window's line is its top and sides.
    titlePlate = {
        slot = "title", label = "Bronze Plate",
        atlas = EDGE_TOP, measured = EDGE_TOP_SIZE, perUnit = 2,
        fill = { 38, 73 }, line = BRONZE_LINE, outline = BRONZE_OUTLINE,
        shadow = { rows = { 81, 86 }, units = 1.25 },
    },
    -- The same line around the whole window, outside its rect.
    bronzeLine = {
        slot = "border", label = "Bronze Line",
        atlas = EDGE_TOP, measured = EDGE_TOP_SIZE, perUnit = 2,
        line = BRONZE_LINE, outline = BRONZE_OUTLINE,
    },
}

local ORDER = { "rock", "titlePlate", "bronzeLine" }
DMY._PanelArtOrder = ORDER

-- What an entry draws on this client: the entry, its file and, for an atlas
-- entry, the member's texcoords (L, R, T, B). nil where the client cannot draw
-- it. Chrome is read at call time: ui/v2/Chrome.lua loads after this file. An
-- answer is kept, since a client serves one member per name for a session.
local sources = {}
local function Source(entry)
    local src = sources[entry]
    if src then return src end
    if entry.file then
        src = { entry = entry, file = entry.file }
    else
        local Chrome = addon.UI and addon.UI.Chrome
        if not (Chrome and Chrome.AtlasSource) then return nil end
        local file, w, h, L, R, T, B = Chrome.AtlasSource({ atlas = entry.atlas })
        if not file then return nil end
        local measured = entry.measured
        if math.abs(w / h - measured[1] / measured[2]) > 0.02 then return nil end
        src = { entry = entry, file = file, L = L, R = R, T = T, B = B }
    end
    sources[entry] = src
    return src
end
DMY._PanelArtSource = Source

--- The entries one slot offers on this client, in catalog order, and their
--- labels.
function DMY.PanelArtEntries(slot)
    local order, values = {}, {}
    for _, key in ipairs(ORDER) do
        local entry = DMY.PanelArt[key]
        if entry.slot == slot and Source(entry) then
            order[#order + 1] = key
            values[key] = entry.label
        end
    end
    return order, values
end

--- The keys a backdrop selector offers: "solid", then the slot's entries.
function DMY.PanelArtKeys(slot)
    local order, values = DMY.PanelArtEntries(slot)
    table.insert(order, 1, "solid")
    values.solid = "Solid"
    return order, values
end

--------------------------------------------------------------------------------
-- The painter
--------------------------------------------------------------------------------

-- A host is a frame this addon made (a window, its title bar, the settings
-- preview), so the art's regions are kept on it. `build` makes a slot's
-- regions once, through piece(layer, sublevel). A slot with a layout runs it
-- again when the host changes size, while its art is shown.
local function Art(host, slot, build)
    local state = host._dmyPanelArt
    if not state then
        state = {}
        host._dmyPanelArt = state
    end
    local art = state[slot]
    if art then return art end
    art = { textures = {} }
    state[slot] = art
    build(art, function(layer, sublevel)
        local tex = host:CreateTexture(nil, layer, nil, sublevel)
        art.textures[#art.textures + 1] = tex
        return tex
    end)
    host:HookScript("OnSizeChanged", function()
        if art.shown and art.layout then art.layout() end
    end)
    return art
end

function DMY.HidePanelArt(host, slot)
    local state = host and host._dmyPanelArt
    local art = state and state[slot]
    if not art then return end
    art.shown = false
    for _, tex in ipairs(art.textures) do tex:Hide() end
end

--- Is `slot`'s art drawn on `host` right now?
function DMY.PanelArtShown(host, slot)
    local state = host and host._dmyPanelArt
    local art = state and state[slot]
    return (art and art.shown) == true
end

-- Sets `tex` to a band of the member's rows, `length` units long, lying along
-- one side of a rect with the band's first row toward the rect's middle. The
-- member crosses its whole sheet, so a band repeats along its length by
-- texcoords past 1 at the art's own scale; a member that does not cross its
-- sheet is stretched instead. A band is cut half a texel inside its rows, so
-- filtering never reads the band beside it.
local function SetBand(tex, src, rows, side, length)
    local entry = src.entry
    local u0, u1 = src.L, src.R
    if (src.R - src.L) > 0.999 then
        u0, u1 = 0, length / (entry.measured[1] / entry.perUnit)
    end
    local dv = (src.B - src.T) / entry.measured[2]
    local inner = src.T + (rows[1] + 0.5) * dv
    local outer = src.T + (rows[2] - 0.5) * dv
    if side == "bottom" then
        tex:SetTexCoord(u0, u1, inner, outer)
    elseif side == "top" then
        tex:SetTexCoord(u0, u1, outer, inner)
    -- Eight arguments: the upper left, lower left, upper right and lower right
    -- corners of the region, each as u, v. The band's length runs down the
    -- screen.
    elseif side == "left" then
        tex:SetTexCoord(u0, outer, u1, outer, u0, inner, u1, inner)
    else
        tex:SetTexCoord(u0, inner, u1, inner, u0, outer, u1, outer)
    end
end

local function LinePieces(piece)
    return { left = piece("BORDER", 1), right = piece("BORDER", 1),
        top = piece("BORDER", 1), bottom = piece("BORDER", 1) }
end

-- The art line on the host's rect: the bronze inside its dark outline, each a
-- band of four pieces. The side pieces run a band's full height and the top
-- and bottom pieces fit between them, and the bronze sits wholly inside the
-- outline, so no piece draws over another's translucency.
--   outside     the line draws around the rect; otherwise on its inner edge
--   bottomOnly  the bottom pieces alone, across the rect's whole width
-- Returns the line's thickness, both bands.
local function LayoutLine(art, host, src, width, height, outside, bottomOnly)
    local entry = src.entry
    local snap = DMY._SnapToPixels
    local outline = snap(entry.outline.units, host, 1)
    local bronze = snap(entry.line.units, host, 1)

    -- `out` is how far the band's own rect reaches past the host's.
    local function band(pieces, rows, thick, out)
        local corner = bottomOnly and 0 or (thick - out)
        pieces.bottom:ClearAllPoints()
        pieces.bottom:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT", corner, -out)
        pieces.bottom:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -corner, -out)
        pieces.bottom:SetHeight(thick)
        SetBand(pieces.bottom, src, rows, "bottom", width - 2 * corner)
        pieces.bottom:Show()
        if bottomOnly then
            pieces.top:Hide()
            pieces.left:Hide()
            pieces.right:Hide()
            return
        end
        pieces.top:ClearAllPoints()
        pieces.top:SetPoint("TOPLEFT", host, "TOPLEFT", corner, out)
        pieces.top:SetPoint("TOPRIGHT", host, "TOPRIGHT", -corner, out)
        pieces.top:SetHeight(thick)
        SetBand(pieces.top, src, rows, "top", width - 2 * corner)
        pieces.top:Show()
        pieces.left:ClearAllPoints()
        pieces.left:SetPoint("TOPLEFT", host, "TOPLEFT", -out, out)
        pieces.left:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT", -out, -out)
        pieces.left:SetWidth(thick)
        SetBand(pieces.left, src, rows, "left", height + 2 * out)
        pieces.left:Show()
        pieces.right:ClearAllPoints()
        pieces.right:SetPoint("TOPRIGHT", host, "TOPRIGHT", out, out)
        pieces.right:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", out, -out)
        pieces.right:SetWidth(thick)
        SetBand(pieces.right, src, rows, "right", height + 2 * out)
        pieces.right:Show()
    end

    local grow = outside and (outline + bronze) or 0
    band(art.outline, entry.outline.rows, outline, grow)
    band(art.line, entry.line.rows, bronze, grow - outline)
    return outline + bronze
end

-- Sets every region of a slot to the source's file at `alpha` and lays the
-- slot out.
local function Show(art, src, alpha)
    for _, tex in ipairs(art.textures) do
        tex:SetTexture(src.file, "REPEAT", "CLAMP")
        tex:SetAlpha(alpha)
        tex:Show()
    end
    art.shown = true
    art.layout()
end

-- The backdrop: one texture the client tiles at the file's own size.
local function PaintWindow(host, src, alpha, below)
    local art = Art(host, "window", function(made, piece)
        made.tex = piece("BACKGROUND", -7)
    end)
    local tex = art.tex
    tex:SetTexCoord(0, 1, 0, 1)
    tex:SetTexture(src.file, "REPEAT", "REPEAT")
    tex:SetHorizTile(true)
    tex:SetVertTile(true)
    tex:ClearAllPoints()
    if below then
        tex:SetPoint("TOPLEFT", below, "BOTTOMLEFT", 0, 0)
        tex:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", 0, 0)
    else
        tex:SetAllPoints(host)
    end
    tex:SetAlpha(alpha)
    tex:Show()
    art.shown = true
end

-- The title bar: the plate inside the art line, and the shadow under the bar.
-- `framed` says the window's border is an art line too: the bar then keeps
-- its bottom line and the plate reaches the bar's top and sides.
local function PaintTitle(host, src, alpha, framed)
    local entry = src.entry
    local art = Art(host, "title", function(made, piece)
        made.fill = piece("BACKGROUND", -5)
        made.shadow = piece("BACKGROUND", -5)
        made.outline = LinePieces(piece)
        made.line = LinePieces(piece)
    end)
    art.layout = function()
        local width, height = host:GetWidth() or 0, host:GetHeight() or 0
        if width <= 0 or height <= 0 then return end
        local edge = LayoutLine(art, host, src, width, height, false, framed)
        local side = framed and 0 or edge

        art.fill:ClearAllPoints()
        art.fill:SetPoint("TOPLEFT", host, "TOPLEFT", side, -side)
        art.fill:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -side, edge)
        SetBand(art.fill, src, entry.fill, "bottom", width - 2 * side)

        art.shadow:ClearAllPoints()
        art.shadow:SetPoint("TOPLEFT", host, "BOTTOMLEFT", 0, 0)
        art.shadow:SetPoint("TOPRIGHT", host, "BOTTOMRIGHT", 0, 0)
        art.shadow:SetHeight(DMY._SnapToPixels(entry.shadow.units, host, 1))
        SetBand(art.shadow, src, entry.shadow.rows, "bottom", width)
    end
    Show(art, src, alpha)
end

-- The window's border: the art line around the window, outside its rect, so
-- it draws over neither backdrop.
local function PaintBorder(host, src, alpha)
    local art = Art(host, "border", function(made, piece)
        made.outline = LinePieces(piece)
        made.line = LinePieces(piece)
    end)
    art.layout = function()
        local width, height = host:GetWidth() or 0, host:GetHeight() or 0
        if width <= 0 or height <= 0 then return end
        LayoutLine(art, host, src, width, height, true, false)
    end
    Show(art, src, alpha)
end

--- Paints `key`'s art for `slot` on `host` at `alpha`. Returns false, with
--- the slot's art hidden, for a key that is no entry of that slot and for art
--- this client cannot draw; the caller then paints what it drew before.
---   below   a window's art runs from under this frame to the host's bottom;
---           nil fills the host
---   framed  a title bar's art keeps its bottom line only
function DMY.ApplyPanelArt(host, slot, key, alpha, below, framed)
    if not host then return false end
    local entry = type(key) == "string" and DMY.PanelArt[key] or nil
    local src = entry and entry.slot == slot and Source(entry) or nil
    if not src then
        DMY.HidePanelArt(host, slot)
        return false
    end
    alpha = tonumber(alpha) or 1
    if slot == "window" then
        PaintWindow(host, src, alpha, below)
    elseif slot == "title" then
        PaintTitle(host, src, alpha, framed == true)
    else
        PaintBorder(host, src, alpha)
    end
    return true
end
