-- unitframesz/compact.lua - Unit Frames Z: the compact arrangement
--
-- Name and health percent, nothing else -- the Target of Target frame. A frame
-- row marks itself compact (core.lua) and the engine dispatches here from
-- applyLayout, envelopeFor and layoutDeadIcon; everything optional (value row,
-- power texts, absorb, level, classification, aura rows) is skipped
-- structurally, so no config key can bring it back. Loads right after
-- engine.lua: the engine locals below are captured from its promotions, and
-- the engine reaches this file only at call time through UFZ._Name.
--
-- The coordinate model. inst.box is the NAME's one-line box at the fit ceiling
-- (nameMaxWidth x nameSize line height), so the stored Edit Mode position keeps
-- pinning the box's TOPLEFT and the name is literally the frame's anchor. The
-- name is pinned on its number-facing edge by a single point, so extra wrapped
-- lines grow AWAY from the number; the percent anchors to the BOX edge on the
-- side cfg.align names, never to the name's rect. That keeps the number pure
-- config: it does not move when a refit lands at a smaller size, and during the
-- new-subject hold (refreshName blanks the name until the fit lands) it is not
-- drawn at the previous subject's geometry and then snapped. The dead skull
-- takes the percent's anchor. Anchor resolution is engine-side throughout, so
-- nothing here reads secret geometry.
--
-- cfg.align takes four values here: bottom (number below the name, the
-- default), top, left, right. The full layout keeps left/right only; setAlign
-- coerces the vertical pair away on a non-compact instance.

local addonName, addon = ...
local UFZ = addon.UnitFramesZ

local pctGlyphCeiling = UFZ._PctGlyphCeiling
local pctRowHeight = UFZ._PctRowHeight
local currentSymbolPoint = UFZ._CurrentSymbolPoint
local applyStretch = UFZ._ApplyStretch
local ENV_LINE_H = UFZ._ENV_LINE_H
local AURA_GLYPH_EM = UFZ._AURA_GLYPH_EM

-- Base gap between the name box and the number, per side; cfg.gap adds to it.
-- Vertical: by the font's own metrics Anton Wide 1.5x at 20pt leaves 6.6px of
-- descender air under the name and 6.3px of rect above the digits' caps, so
-- the two rects touching already read about 13px apart. The thick outline
-- and the shadow copy's drop draw into that air, and a zero gap looked tight
-- in game, so bottom adds 6. Top stays 4 under bottom: digits have no
-- descenders, names do. Tuned in game.
local COMPACT_GAP = { bottom = 6, top = 2, left = 4, right = 4 }

local ALIGNS = { bottom = true, top = true, left = true, right = true }

local function alignOf(cfg)
    local a = cfg.align
    if not ALIGNS[a] then return "bottom" end
    return a
end

local function compactGap(cfg)
    return (COMPACT_GAP[alignOf(cfg)] or 0) + (cfg.gap or 0)
end

local function lineHeight(cfg)
    return math.ceil(cfg.nameSize * ENV_LINE_H)
end

-- The '%' companion's width and its gap off the digits, both zero when the sign
-- is off. Plain readable text, so the shared ruler measures it synchronously;
-- the estimate only covers a missing ruler (the powerSymbolReserve shape).
local function symbolReserve(inst)
    local cfg = inst.cfg
    if not cfg.symbol then return 0, 0 end
    local size = currentSymbolPoint(inst)
    local w
    if addon.MeasureTextWidth then
        w = addon.MeasureTextWidth("%", addon.ResolveFontFace(cfg.face), size, cfg.style)
    end
    if type(w) ~= "number" or w <= 0 then w = size * 0.9 end
    return w, cfg.symbolGap or 0
end

-- Width estimate for the number and its sign: three digits at the largest
-- configured rendering, the same size-based doctrine as the envelope.
local function numberWidth(inst)
    local cfg = inst.cfg
    local symW, symGap = symbolReserve(inst)
    return math.ceil(pctGlyphCeiling(cfg) * 3 * AURA_GLYPH_EM * (cfg.stretch or 1) + symGap + symW)
end

--- The envelope, in the engine's box-local down-positive coordinates: the
--- one-line name box, the (lines - 1) extra lines in the growth direction, and
--- the number row on its side. Returns the same shape envelopeFor does, with L
--- the box's left offset inside the rect.
function UFZ._CompactEnvelope(inst, lines)
    local cfg = inst.cfg
    local align = alignOf(cfg)
    local boxW, lineH = cfg.nameMaxWidth, lineHeight(cfg)
    local extra = (lines - 1) * cfg.nameSize * ENV_LINE_H
    local numH = math.ceil(pctGlyphCeiling(cfg) * ENV_LINE_H)
    local numW = numberWidth(inst)
    local gap = compactGap(cfg)
    local top, bottom, left, right
    if align == "bottom" then
        top, bottom = -extra, lineH + gap + numH
        left, right = math.min(0, (boxW - numW) / 2), math.max(boxW, (boxW + numW) / 2)
    elseif align == "top" then
        top, bottom = -(gap + numH), lineH + extra
        left, right = math.min(0, (boxW - numW) / 2), math.max(boxW, (boxW + numW) / 2)
    else
        -- A single LEFT/RIGHT point centers the wrapped block on the box's
        -- midline, so extra lines grow both ways.
        top = math.min(-extra / 2, (lineH - numH) / 2)
        bottom = math.max(lineH + extra / 2, (lineH + numH) / 2)
        if align == "left" then
            left, right = -(gap + numW), boxW
        else
            left, right = 0, boxW + gap + numW
        end
    end
    top, left = math.floor(top), math.floor(left)
    bottom, right = math.ceil(bottom), math.ceil(right)
    return { align = align, W = right - left, H = bottom - top, T = -top, L = -left }
end

--- The skull replaces the one number row: sized from that row alone (no
--- two-row stack factor) and centred where the digits sit.
function UFZ._LayoutCompactDeadIcon(inst)
    local tex, box, cfg = inst.deadTex, inst.box, inst.cfg
    if not tex or not box then return end
    local align = alignOf(cfg)
    local pctRowH = pctRowHeight(cfg)
    local side = math.max(8, math.floor(pctRowH * (cfg.deadIconScale or 100) / 100))
    tex:SetSize(side, side)
    tex:ClearAllPoints()
    local gap = compactGap(cfg)
    if align == "bottom" then
        tex:SetPoint("CENTER", box, "BOTTOM", 0, -(gap + pctRowH / 2))
    elseif align == "top" then
        tex:SetPoint("CENTER", box, "TOP", 0, gap + pctRowH / 2)
    elseif align == "left" then
        tex:SetPoint("CENTER", box, "LEFT", -(gap + numberWidth(inst) / 2), 0)
    else
        tex:SetPoint("CENTER", box, "RIGHT", gap + numberWidth(inst) / 2, 0)
    end
end

-- The regions the compact arrangement never draws, hidden once per layout pass
-- (creation shows them; nothing else in the compact path touches them).
local function hideOptionalRegions(inst)
    local regions = {
        inst.valFS, inst.powerFS, inst.powerSymbolFS, inst.altPowerFS,
        inst.altPowerSymbolFS, inst.absorbFS, inst.absorbGlowTex,
        inst.levelFS, inst.levelPrefixFS, inst.classifyTex,
    }
    for _, region in ipairs(regions) do
        region:Hide()
    end
end

--- The layout, called by applyLayout after the envelope has seated the box.
function UFZ._ApplyCompactLayout(inst)
    local frame, box, cfg = inst.frame, inst.box, inst.cfg
    if not frame or not box then return end
    local pctFS, symbolFS, nameFS = inst.pctFS, inst.symbolFS, inst.nameFS
    hideOptionalRegions(inst)

    -- The box IS the name's one-line box; the envelope sized the frame around
    -- it. A plain child with no protected descendants, so this resize stays
    -- legal in combat (the outer frame's is the queued one).
    box:SetSize(cfg.nameMaxWidth, lineHeight(cfg))

    nameFS:ClearAllPoints()
    pctFS:ClearAllPoints()
    symbolFS:ClearAllPoints()
    -- The wrap box the fit measures against, as in the full layout.
    nameFS:SetWidth(cfg.nameMaxWidth)
    if nameFS.SetMaxLines then pcall(nameFS.SetMaxLines, nameFS, cfg.nameMaxLines) end
    -- Natural width on the percent: a width would engage the truncation engine.
    pctFS:SetJustifyH("CENTER")

    local align = alignOf(cfg)
    local gap = compactGap(cfg)
    local symW, symGap = symbolReserve(inst)
    if align == "bottom" then
        nameFS:SetJustifyH("CENTER")
        nameFS:SetPoint("BOTTOM", box, "BOTTOM", 0, 0)
        -- Shifted left by half the sign's reserve so digits and sign read as
        -- one centred block.
        pctFS:SetPoint("TOP", box, "BOTTOM", -(symGap + symW) / 2, -gap)
    elseif align == "top" then
        nameFS:SetJustifyH("CENTER")
        nameFS:SetPoint("TOP", box, "TOP", 0, 0)
        pctFS:SetPoint("BOTTOM", box, "TOP", -(symGap + symW) / 2, gap)
    elseif align == "left" then
        -- The name hugs the number: justified toward it, the box's far side
        -- is the empty air.
        nameFS:SetJustifyH("LEFT")
        nameFS:SetPoint("LEFT", box, "LEFT", 0, 0)
        -- The sign, not the digits, lands gap px off the box.
        pctFS:SetPoint("RIGHT", box, "LEFT", -(gap + symGap + symW), 0)
    else
        nameFS:SetJustifyH("RIGHT")
        nameFS:SetPoint("RIGHT", box, "RIGHT", 0, 0)
        pctFS:SetPoint("LEFT", box, "RIGHT", gap, 0)
    end
    -- Superscript '%' off the digits' trailing edge, the full layout's treatment.
    symbolFS:SetPoint("TOPLEFT", pctFS, "TOPRIGHT", cfg.symbolGap, 0)
    symbolFS:SetShown(cfg.symbol and true or false)

    UFZ._LayoutCompactDeadIcon(inst)
    -- No rows on a compact frame; the call keeps the seam whole and no-ops.
    if UFZ.Auras then UFZ.Auras.ApplyLayout(inst) end
    applyStretch(inst)
end
