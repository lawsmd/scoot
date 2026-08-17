--------------------------------------------------------------------------------
-- castbarz/empowered.lua
-- Tier segments and pip dividers for empowered (charge) casts.
--
-- THE MECHANISM: PROGRESSION IS FREE.
--
-- Cast Bar Z already draws every element twice -- a dim copy on the bar and a
-- bright copy inside revealFrame, which is clipped to the swept portion. Tier
-- segments are that same trick applied to the line: N muted segments on the bar,
-- N full-strength segments inside the reveal. As the sweep crosses each divider,
-- that segment's bright copy finishes being revealed.
--
-- The semantics fall out exactly right. Segment i runs from divider i-1 to
-- divider i, so a FULLY LIT segment i means stage i completed means tier i
-- reached, and a partly lit one is the run-up to that tier. There is no stage
-- tracking here at all: no OnUpdate, no CurrSpellStage read, nothing polled.
--
-- That is not merely tidier than Cast Bar X, it is strictly more capable. X polls
-- frame.CurrSpellStage from a shared OnUpdate and bails when the value is secret
-- (styling.lua:1301-1310), so X's tier progression is player-only by
-- construction. Z's is geometric, and geometry does not care whose cast it is --
-- a targeted Evoker renders identically.
--
-- WHERE THE NUMBERS COME FROM.
--
-- UnitEmpoweredStagePercentages carries no secret restriction at all
-- (UnitDocumentation.lua:1142-1158) -- plain numbers on every unit, already
-- normalised. Multiply by the DB width and that is the whole geometry.
--
-- Blizzard's own AddStages cannot be copied: it reads GetUnitEmpowerStageDuration
-- (SecretWhenUnitSpellCastRestricted, :166-181) AND self:GetLeft()/GetRight()
-- (CastingBarFrame.lua:1040-1047), which is a geometry read on a frame that may
-- carry a secret duration. The percentages vector replaces both at once.
--
-- The segmentation follows Cast Bar X (textfill.lua:363, 376-385) rather than
-- Blizzard, whose ChargeTier i spans divider i -> divider i+1 and leaves the
-- run-up to tier 1 uncolored. On a fill bar the LIT state is the signal, not the
-- PRESENT state, so X's mapping is the correct one.
--------------------------------------------------------------------------------

local addonName, addon = ...
local CBZ = addon.CastBarZ

-- Blizzard tops out at 4 empower levels; the pool carries the hold window plus
-- one spare so a future fifth level is a data change rather than a code change.
local MAX_SEGMENTS = 6

-- Whether the percentages vector includes the hold-at-max window.
--
-- TRUE is the motivated default, not a coin flip: Blizzard's own bar adds
-- GetUnitEmpowerHoldAtMaxTime to endTime for every charge spell
-- (CastingBarFrame.lua:429-431), so the bar it drives spans the full window, and
-- UnitChannelDuration is the modern replacement for exactly that computation.
--
-- If it is wrong the failure is loud rather than subtle -- the sweep reaches the
-- right edge before the last divider -- and the fix is this one constant.
-- /scoot debug castz empower prints BOTH vectors side by side so a single cast
-- settles it.
local INCLUDE_HOLD_AT_MAX = true

-- The preview's synthetic stages, as CUMULATIVE edges -- the same form
-- _ResolveEmpowerStages hands back after accumulating a live vector, so both
-- paths reach LayoutSegments identically. Four equal stages plus a hold of the
-- same length, chosen so every tier color appears: a three-stage preview would
-- never show the red one, and the palette is the thing being previewed.
local PREVIEW_EDGES = { 0.20, 0.40, 0.60, 0.80, 1.00 }

-- Uninterruptible override for the dim half. LINE_COLOR_LOCKED's white is right for
-- the lit segments and far too bright for the unlit track behind them; the dim
-- segments need the same drained reading at the track's own value.
local LOCKED_DIM = { 0.40, 0.40, 0.40 }

--------------------------------------------------------------------------------
-- Tier palettes
--------------------------------------------------------------------------------

-- Fallbacks only. The live values come from Cast Bar X so the two components can
-- never disagree about a palette they visibly share; these exist for the case
-- where the CastBars namespace has not loaded, not as a second opinion.
local FALLBACK_NORMAL = {
    { 0.45, 0.95, 0.55 },
    { 1.00, 0.90, 0.30 },
    { 1.00, 0.55, 0.25 },
    { 1.00, 0.30, 0.20 },
}
local FALLBACK_DISABLED = {
    { 0.18, 0.40, 0.22 },
    { 0.40, 0.36, 0.12 },
    { 0.40, 0.22, 0.10 },
    { 0.40, 0.12, 0.08 },
}

--- The shared green -> yellow -> orange -> red progression, and its muted twin.
---
--- Resolved per call rather than cached at load: castbarz TOCs after the cast
--- files today, but a cached upvalue would turn a future TOC reorder into a
--- silently wrong palette instead of an error.
---
--- Note for tuning: X's values are documented as brightened to survive vertex
--- color multiplication on a custom bar texture. Z paints with SetColorTexture,
--- which does no multiplication, so they render hotter here.
local function TierPalettes()
    local CB = addon.CastBars
    local normal = CB and CB._TIER_COLORS_NORMAL
    local disabled = CB and CB._TIER_COLORS_DISABLED
    if type(normal) == "table" and type(disabled) == "table"
        and #normal > 0 and #disabled > 0 then
        return normal, disabled
    end
    return FALLBACK_NORMAL, FALLBACK_DISABLED
end

--- Which tier color segment `i` of `count` should wear.
---
--- The final segment is the hold-at-max window rather than a new tier, so it
--- repeats the tier it is holding at -- holding at max is still max. Without the
--- repeat a four-stage empower would ask for a fifth color that does not exist.
local function TierIndex(i, count)
    local tiers = INCLUDE_HOLD_AT_MAX and math.max(1, count - 1) or count
    return math.min(i, tiers)
end

local function TierColor(palette, i, count)
    return palette[math.min(TierIndex(i, count), #palette)] or palette[#palette]
end

--------------------------------------------------------------------------------
-- Stage resolution
--------------------------------------------------------------------------------

--- Cumulative fractions of the bar, ending at exactly 1, or nil.
---
--- Every element is guarded type() -> issecretvalue() -> use even though the
--- documentation says these are plain. The guard costs one comparison per stage
--- and the alternative is throwing from inside a live cast; and if the annotation
--- ever changes, this degrades to a plain bar instead of an error.
function CBZ._ResolveEmpowerStages(bar)
    -- `true` takes the fixed preview vector; a table is a caller-supplied edge
    -- vector (the local showcase models real three-stage empowers). Copied, and
    -- closed on 1 like the live path below, so a caller's table is never mutated
    -- and can never leave a dead strip of track.
    if bar.empowerPreview then
        local src = type(bar.empowerPreview) == "table" and bar.empowerPreview or PREVIEW_EDGES
        local fracs = {}
        for i, v in ipairs(src) do
            fracs[i] = v
            if i >= MAX_SEGMENTS then break end
        end
        if #fracs == 0 then return nil end
        fracs[#fracs] = 1
        return fracs
    end

    if not UnitEmpoweredStagePercentages then return nil end

    local ok, pcts = pcall(UnitEmpoweredStagePercentages, bar.unit, INCLUDE_HOLD_AT_MAX)
    if not ok or pcts == nil then return nil end

    local okLen, count = pcall(function() return #pcts end)
    if not okLen or type(count) ~= "number" or count < 1 then return nil end
    if count > MAX_SEGMENTS then count = MAX_SEGMENTS end

    local fracs, cum = {}, 0
    for i = 1, count do
        local okV, v = pcall(function() return pcts[i] end)
        if not okV or type(v) ~= "number" then return nil end
        if issecretvalue and issecretvalue(v) then return nil end
        cum = cum + v
        fracs[i] = cum
    end

    -- A vector that does not reach the bar's end would leave a dead strip of
    -- track no cast can ever fill. Closing it on 1 is the same backstop the band
    -- layout applies to its last column.
    fracs[count] = 1
    return fracs
end

--------------------------------------------------------------------------------
-- Element pools
--------------------------------------------------------------------------------

-- Built on first use, never torn down. An empowered cast is rare enough that
-- paying for six segments up front on every bar would be wasteful, and common
-- enough on an Evoker that rebuilding them per cast would be too.
local function EnsurePools(bar)
    if bar.tierSegs then return end

    bar.tierSegs = {}         -- dim, on the bar, where unfilledLine sits
    bar.tierSegsBright = {}   -- bright, inside revealFrame, so the sweep clips them
    bar.tierPips = {}

    for i = 1, MAX_SEGMENTS do
        -- Same layer and sublevel as unfilledLine (BACKGROUND:1), so the shared
        -- black outline at sublevel 0 still frames them.
        local dim = bar:CreateTexture(nil, "BACKGROUND", nil, 1)
        dim:Hide()
        bar.tierSegs[i] = dim

        -- Inside revealFrame but anchored to the BAR, exactly as the filled caps
        -- and the bright text bands are. Clipping is by the parent's rect and does
        -- not care what the child is anchored to; anchoring to revealFrame instead
        -- would make every segment slide as the clip narrows.
        local bright = bar.revealFrame:CreateTexture(nil, "BACKGROUND", nil, 2)
        bright:Hide()
        bar.tierSegsBright[i] = bright
    end

    for i = 1, MAX_SEGMENTS - 1 do
        local pip = bar.pipFrame:CreateTexture(nil, "ARTWORK", nil, 3)
        pip:SetColorTexture(0, 0, 0, 1)
        pip:Hide()
        bar.tierPips[i] = pip
    end
end

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

--- True while this bar is drawing tier segments.
--- Distinct from bar.empowered, which says only that the CAST is empowered: the
--- stages can fail to resolve, or the user can have the feature switched off.
function CBZ._IsEmpoweredActive(bar)
    local n = bar and bar.empowerSegCount
    return (type(n) == "number" and n > 0) or false
end

--------------------------------------------------------------------------------
-- Colors
--------------------------------------------------------------------------------

--- Paint the tier palette onto the segments and the end caps.
---
--- `ni` is the possibly-secret notInterruptible flag and is never examined --
--- CBZ._PickColor resolves the branch inside the engine, per segment, exactly as
--- it already does per text band. So an unkickable empowered cast on a targeted
--- Evoker greys out correctly without anything here learning that it did.
function CBZ._ApplyEmpoweredColors(bar, ni)
    if not CBZ._IsEmpoweredActive(bar) then return end
    local count = bar.empowerSegCount

    -- Normalised here as well as in _ApplyInterruptState, because the relayout
    -- path can arrive with nothing recorded yet. nil is never secret, and type()
    -- is the only test safe to run first. Left as nil it would cost two failed
    -- pcalls per segment before landing on the same answer.
    if type(ni) == "nil" then ni = false end

    local normal, disabled = TierPalettes()
    local pick = CBZ._PickColor

    for i = 1, count do
        local bright = pick(ni, CBZ.LINE_COLOR_LOCKED, TierColor(normal, i, count))
        local dim = pick(ni, LOCKED_DIM, TierColor(disabled, i, count))
        bar.tierSegsBright[i]:SetColorTexture(bright[1], bright[2], bright[3], 1)
        bar.tierSegs[i]:SetColorTexture(dim[1], dim[2], dim[3], 1)
    end

    -- End caps take the first and last tiers, matching textfill.lua:430-449. The
    -- unfilled pair takes the muted palette so the track reads as one design
    -- rather than as tier segments dropped onto a gray bar.
    local firstN = pick(ni, CBZ.LINE_COLOR_LOCKED, TierColor(normal, 1, count))
    local lastN  = pick(ni, CBZ.LINE_COLOR_LOCKED, TierColor(normal, count, count))
    local firstD = pick(ni, LOCKED_DIM, TierColor(disabled, 1, count))
    local lastD  = pick(ni, LOCKED_DIM, TierColor(disabled, count, count))

    bar.filledLeftCap:SetColorTexture(firstN[1], firstN[2], firstN[3], 1)
    bar.filledRightCap:SetColorTexture(lastN[1], lastN[2], lastN[3], 1)
    bar.unfilledLeftCap:SetColorTexture(firstD[1], firstD[2], firstD[3], 1)
    bar.unfilledRightCap:SetColorTexture(lastD[1], lastD[2], lastD[3], 1)
end

--------------------------------------------------------------------------------
-- Layout
--------------------------------------------------------------------------------

--- Place the segments and dividers from DB numbers and the stage fractions.
--- Never reads the bar's geometry -- the hard rule this component is built on.
local function LayoutSegments(bar, fracs)
    EnsurePools(bar)

    local cfg = CBZ._GetUnitConfig(bar.unitKey)
    local barW = tonumber(bar.widthOverride) or tonumber(cfg and cfg.barWidth) or 200
    local lineH = CBZ._SnapToPixels(CBZ._GetLineHeight())
    local capH = CBZ._SnapToPixels(CBZ._GetCapSize())
    local pipW = math.max(1, CBZ._SnapToPixels(1))

    local count = math.min(#fracs, MAX_SEGMENTS)

    -- The plain line is what tiers replace. Its OUTLINES stay up: they span the
    -- full bar and frame the whole segmented run, which is why X keeps them too
    -- (textfill.lua:324). A hidden texture keeps its rect, so filledLineOL still
    -- tracks the sweep from the line it is anchored to.
    bar.unfilledLine:Hide()
    bar.filledLine:Hide()

    local prev = 0
    for i = 1, count do
        -- Snapped for the same reason band edges are: an unsnapped boundary leaves
        -- a sub-pixel gap or overlap between adjacent segments, and on a 2px line
        -- that reads as a hairline break rather than as a rounding artifact.
        local edge = CBZ._SnapToPixels(barW * fracs[i])
        if i == count then edge = barW end
        if edge <= prev then edge = prev + 1 end

        for _, tex in ipairs({ bar.tierSegs[i], bar.tierSegsBright[i] }) do
            tex:ClearAllPoints()
            tex:SetPoint("LEFT", bar, "LEFT", prev, 0)
            tex:SetPoint("RIGHT", bar, "LEFT", edge, 0)
            tex:SetHeight(lineH)
            tex:Show()
        end

        -- No divider on the last boundary -- that is the bar's right end cap. The
        -- second-to-last one is the most useful mark on the whole bar: with
        -- hold-at-max included it is the instant max tier is reached.
        if i < count then
            local pip = bar.tierPips[i]
            pip:ClearAllPoints()
            pip:SetSize(pipW, capH)
            pip:SetPoint("CENTER", bar, "LEFT", edge, 0)
            pip:Show()
        end

        prev = edge
    end

    for i = count + 1, MAX_SEGMENTS do
        bar.tierSegs[i]:Hide()
        bar.tierSegsBright[i]:Hide()
    end
    for i = math.max(count, 1), MAX_SEGMENTS - 1 do
        bar.tierPips[i]:Hide()
    end

    bar.empowerSegCount = count
end

--------------------------------------------------------------------------------
-- Public entry points
--------------------------------------------------------------------------------

--- Tear the tier palette down and hand the plain line back.
--- Safe on a bar that never had one; that is the common case.
function CBZ._ClearEmpowered(bar)
    local was = CBZ._IsEmpoweredActive(bar)
    bar.empowerSegCount = nil
    bar.empowerInfo = nil

    if bar.tierSegs then
        for i = 1, MAX_SEGMENTS do
            bar.tierSegs[i]:Hide()
            bar.tierSegsBright[i]:Hide()
        end
        for i = 1, MAX_SEGMENTS - 1 do
            bar.tierPips[i]:Hide()
        end
    end

    if not was then return end

    bar.unfilledLine:Show()
    bar.filledLine:Show()
    CBZ._ApplyTrackGray(bar)

    -- Ordered after the flag is cleared, because _ApplyLineColor deliberately
    -- refuses to write while tiers are active.
    local line = CBZ._GetLineColor(bar)
    CBZ._ApplyLineColor(bar, line[1], line[2], line[3])
end

--- Decide whether this cast draws tiers, and draw them if so.
--- Returns true when tiers are on screen.
---
--- @param empowered boolean  from UnitChannelInfo's isEmpowered (NeverSecret)
--- @param numStages number|nil  from numEmpowerStages (NeverSecret), for the log
function CBZ._ApplyEmpowered(bar, empowered, numStages)
    if not empowered or CBZ._GetSetting("empoweredTiers") == false then
        CBZ._ClearEmpowered(bar)
        return false
    end

    local fracs = CBZ._ResolveEmpowerStages(bar)
    if not fracs or #fracs < 1 then
        -- No usable stage data. A plain filling bar is a correct-looking cast bar
        -- with less information on it, which beats half a tier run.
        CBZ._ClearEmpowered(bar)
        return false
    end

    LayoutSegments(bar, fracs)

    -- Recorded, never branched on. numEmpowerStages is the independent cross-check
    -- on INCLUDE_HOLD_AT_MAX: with the hold counted, the vector should be one
    -- longer than the stage count. A mismatch means the constant is wrong, and
    -- this is where /scoot debug castz empower reads it from.
    bar.empowerInfo = {
        segments = bar.empowerSegCount,
        numStages = (type(numStages) == "number"
            and not (issecretvalue and issecretvalue(numStages))) and numStages or nil,
        includeHold = INCLUDE_HOLD_AT_MAX,
        fracs = fracs,
    }

    return true
end

--- Re-place the segments after a layout pass has rebuilt the plain line under
--- them. Called unconditionally from _LayoutBar; a no-op unless tiers are live.
function CBZ._RelayoutEmpowered(bar)
    if not CBZ._IsEmpoweredActive(bar) then return end

    local fracs = bar.empowerInfo and bar.empowerInfo.fracs
    if not fracs then
        -- Should not happen: the two are written together. Falling back to a plain
        -- bar is the honest outcome, since re-resolving mid-charge could return a
        -- different vector than the one the sweep was started against.
        CBZ._ClearEmpowered(bar)
        return
    end

    LayoutSegments(bar, fracs)
    CBZ._ApplyEmpoweredColors(bar, bar.interruptFlag)
end
