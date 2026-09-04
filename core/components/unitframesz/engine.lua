-- unitframesz/engine.lua - the Unit Frames Z rendering engine
--
-- The whole UFZ frame: a large current-health percent stacked over a smaller
-- abbreviated current-health value, both colored by the health color curve,
-- with the class-gradient name beside the stack, power/level texts riding the
-- name, and the absorb halo above the numbers. Built and certified in the
-- healthtext debug harness; this file IS that engine, promoted.
--
-- ONE INSTANCE PER FRAME (core.lua's UFZ.FRAMES), on the AceDB-backed config
-- of its unit: inst.cfg IS profile.unitFramesZUnits[inst.unitKey], so every cfg
-- read and setter write in this file persists with no translation layer.
--
-- Frames and configs are NOT 1:1. Boss is five frames sharing one config, so
-- this file never reads a unit token out of cfg -- inst.unit carries it, minted
-- from the frame row. Everything else an instance owns (FontStrings, the digit
-- probe, the name fit) is genuinely per frame. The public API is per CONFIG and
-- fans out across that config's instances (UFZ.GetAPI(unitKey)).
--
-- UnitHealth is SecretReturns = true unconditionally -- every unit including "player",
-- in and out of combat -- so nothing here ever reads a health number. The engine does
-- all the work through secret-tolerant formatters:
--
--   Value    AbbreviateNumbers(secret, {config}) with a custom breakpoint table that
--            encodes the four-character scheme (9000, 99.9k, 100k, 1.15m, 10.5m).
--            Proven on secret combat values by damagemetersY/data.lua.
--   Percent  A numeric curve (0->0, 1->100) handed to UnitHealthPercent, whose secret
--            result goes through C_StringUtil.FloorToNearestString into SetText.
--            UNPROVEN as a composed chain -- 'probe' validates it end to end and
--            cross-checks the curve input domain.
--   Color    UnitHealthPercent(unit, true, colorCurve) returns a readable Color even
--            though the percentage is secret; applied via FontString:SetTextColor.
--   Name     The certified blind fit (core/blindfit.lua, ported from nametext.lua)
--            chooses the largest point size <= nameSize at which the possibly-secret
--            name fits a nameMaxWidth x nameMaxLines box; the paint is a per-line
--            class ramp for readable player names, raw solid white for secrets.
--   Power    Primary + alternate resource as flat values through the same
--            AbbreviateNumbers chain (UnitPower is only conditionally secret, but
--            the chain never needs it readable), anchored to the name box and
--            colored by the readable UnitPowerType resource color.
--
-- Width matching is config-driven: every font size is a plain number, tuned in
-- the harness against plain sample strings. The live FontStrings hold secrets
-- and are permanently unmeasurable, so no layout decision ever reads them.
-- Digit mode picks the percent size from a per-digit-count table; the count
-- comes from the SetAlphaGradient length oracle run against an invisible ruler,
-- never from reading. The value row shares the main face by default; cfg.valFace
-- ("follow" or any registry key) can run it on its own face.
--
-- Everything here is addon-owned and anchored to UIParent with plain numbers. No
-- Blizzard frame is read, written, hooked or anchored to. (Parking Blizzard's
-- own frame for a Z unit is suppression.lua's job, through addon.NativeFrame.)

local addonName, addon = ...
local UFZ = addon.UnitFramesZ


--------------------------------------------------------------------------------
-- Value chain: the four-character abbreviation config (shared by both instances)
--------------------------------------------------------------------------------
-- Engine formula per tier: floor(value / significandDivisor) / fractionDivisor,
-- then the abbreviation is appended. Largest breakpoint first, every field
-- required -- omitting significandDivisor is the DMY sub-1K bug. The base entry
-- keeps 1000-9999 raw and floors float noise out of sub-1K values.

local function BuildHealthBreakpoints()
    return {
        { breakpoint = 1e11, abbreviation = "b", significandDivisor = 1e9, fractionDivisor = 1,   abbreviationIsGlobal = false }, -- "105b"
        { breakpoint = 1e10, abbreviation = "b", significandDivisor = 1e8, fractionDivisor = 10,  abbreviationIsGlobal = false }, -- "10.5b"
        { breakpoint = 1e9,  abbreviation = "b", significandDivisor = 1e7, fractionDivisor = 100, abbreviationIsGlobal = false }, -- "1.05b"
        { breakpoint = 1e8,  abbreviation = "m", significandDivisor = 1e6, fractionDivisor = 1,   abbreviationIsGlobal = false }, -- "105m"
        { breakpoint = 1e7,  abbreviation = "m", significandDivisor = 1e5, fractionDivisor = 10,  abbreviationIsGlobal = false }, -- "10.5m"
        { breakpoint = 1e6,  abbreviation = "m", significandDivisor = 1e4, fractionDivisor = 100, abbreviationIsGlobal = false }, -- "1.15m"
        { breakpoint = 1e5,  abbreviation = "k", significandDivisor = 1e3, fractionDivisor = 1,   abbreviationIsGlobal = false }, -- "100k"
        { breakpoint = 1e4,  abbreviation = "k", significandDivisor = 1e2, fractionDivisor = 10,  abbreviationIsGlobal = false }, -- "45.6k"
        { breakpoint = 1,    abbreviation = "",  significandDivisor = 1,   fractionDivisor = 1,   abbreviationIsGlobal = false }, -- raw below 10k
    }
end

local abbrevOpts = nil
local abbrevBuildTried = false

-- Idempotent, so one instance's Probe re-running it while the other instance's
-- update() reads it is harmless: abbrevBuildTried is set synchronously and the
-- rebuilt config is equivalent. The retry ladder lives in core/abbrev.lua; on
-- the bp=10 degraded shape, health is an integer, so values 0-9 pass through
-- raw and render fine. The error string is discarded here (the old abbrevError
-- and abbrevTier locals were write-only, vestiges of the retired debug
-- harness).
local function rebuildAbbrevConfig()
    abbrevBuildTried = true
    abbrevOpts = addon.CreateAbbrevConfig(BuildHealthBreakpoints)
    return abbrevOpts
end

--------------------------------------------------------------------------------
-- Percent chain: the numeric curve (shared -- curves are stateless evaluators)
--------------------------------------------------------------------------------

local pctCurve = nil

local function ensurePctCurve()
    if pctCurve then return pctCurve end
    if not (_G.C_CurveUtil and _G.C_CurveUtil.CreateCurve) then return nil end
    local ok, c = pcall(C_CurveUtil.CreateCurve)
    if not ok or not c then return nil end
    if c.SetType and _G.Enum and _G.Enum.LuaCurveType then
        pcall(c.SetType, c, Enum.LuaCurveType.Linear)
    end
    -- UnitHealthPercent feeds the curve the normalized 0-1 percentage (established by
    -- the color curves in unitframes/bars/textures.lua); map it to 0-100 so the string
    -- formatter sees a percent. 'probe' P13 cross-checks this domain on screen.
    pcall(c.AddPoint, c, 0, 0)
    pcall(c.AddPoint, c, 1, 100)
    pctCurve = c
    return c
end

--------------------------------------------------------------------------------
-- Color curves (local copies of the bars/textures.lua builds; that module keeps
-- its table local, so a debug file cannot reach applyHealthTextColor)
--------------------------------------------------------------------------------

local colorCurve, colorDarkCurve

local function buildColorCurve(dark)
    if not (_G.C_CurveUtil and _G.C_CurveUtil.CreateColorCurve and _G.CreateColor) then return nil end
    local ok, c = pcall(C_CurveUtil.CreateColorCurve)
    if not ok or not c then return nil end
    if c.SetType and _G.Enum and _G.Enum.LuaCurveType then
        pcall(c.SetType, c, Enum.LuaCurveType.Linear)
    end
    pcall(c.AddPoint, c, 0.0, CreateColor(1, 0, 0, 1))
    pcall(c.AddPoint, c, 0.5, CreateColor(1, 1, 0, 1))
    if dark then
        pcall(c.AddPoint, c, 0.9999, CreateColor(0, 1, 0, 1))
        pcall(c.AddPoint, c, 1.0, CreateColor(0.23, 0.23, 0.23, 1))
    else
        pcall(c.AddPoint, c, 1.0, CreateColor(0, 1, 0, 1))
    end
    return c
end

local function ensureColorCurve(mode)
    if mode == "dark" then
        colorDarkCurve = colorDarkCurve or buildColorCurve(true)
        return colorDarkCurve
    end
    colorCurve = colorCurve or buildColorCurve(false)
    return colorCurve
end

--------------------------------------------------------------------------------
-- Fonts and layout
--------------------------------------------------------------------------------

-- With digit mode on, the fitted size wins over cfg.pctSize so that font/style
-- commands re-applying fonts do not stomp the current fit. applyLayout shares
-- this: the percent's BOTTOM anchor lift is proportional to the same size.
local function currentPctPoint(inst)
    local cfg = inst.cfg
    return (cfg.digits and inst.lastDigitCount and cfg["digitSize" .. inst.lastDigitCount]) or cfg.pctSize
end

-- The percent row's ink-bottom compensation (see DEFAULTS.descent): positive
-- pushes the rect down (sizes above the master), negative lifts it, zero at the
-- master size itself -- so the tuned 2-digit look never moves and the other
-- digit modes match its visible gap. 0.1-px snapped, same contract as the gap
-- setters (sub-px offsets land on different physical pixels under fractional
-- UI scale). Shared by applyLayout and 'report' so the two never disagree.
local function currentPctLift(inst)
    local cfg = inst.cfg
    local ref = cfg.digits and cfg.digitSize2 or cfg.pctSize
    return math.floor((currentPctPoint(inst) - ref) * cfg.descent * 10 + 0.5) / 10
end

-- Base face first, override on top: SetFont on a file this client session has
-- never loaded is a silent no-op (ApplyFontStyle pcalls it), and on a virgin
-- FontString that would mean NO font object at all -- an invisible row. Applying
-- the main face first guarantees the row always renders; a loadable override
-- then simply wins.
local function applyOverrideFace(fs, size, baseFace, overrideKey, style)
    addon.ApplyFontStyle(fs, baseFace, size, style)
    if overrideKey ~= "follow" then
        addon.ApplyFontStyle(fs, addon.ResolveFontFace(overrideKey), size, style)
    end
end

-- The '%' rides at a fifth of the percent's current point size, FRACTIONAL on
-- purpose: digit-mode size changes carry it along (the probe's applyFonts()
-- re-derives it), and the old integer rounding ate the 2->3-digit step down to
-- a near-invisible single point. SetFont takes float heights (the value row's
-- 0.5 steps ride the same path). An explicit symbolSize > 0 overrides, fixed.
local function currentSymbolPoint(inst)
    if inst.cfg.symbolSize and inst.cfg.symbolSize > 0 then return inst.cfg.symbolSize end
    return math.max(1, currentPctPoint(inst) / 5)
end

-- With the name fit on, the fitted size wins over cfg.nameSize so font/style
-- commands re-applying fonts do not stomp the current fit -- the same
-- lastDigitCount pattern the percent uses. The fit writes inst.nameFitSize;
-- everything else only reads it through here.
local function currentNamePoint(inst)
    return (inst.cfg.nameFit and inst.nameFitSize) or inst.cfg.nameSize
end

-- The level pair: "lvl" leads the number on its own FontString (no inline
-- size markup exists -- the '%' companion precedent) at 75% of the number's
-- size, separated by a small sub-space gap expressed as a
-- fraction of the number's point size (roughly half a space glyph).
local LEVEL_PREFIX_SCALE  = 0.75
local LEVEL_PREFIX_GAP_EM = 0.08

-- Style keys are per text block: cfg.style covers the health block (percent,
-- '%', value and absorb rows); nameStyle, powerStyle and levelStyle cover
-- their own blocks. Every measurement of a block's text below uses the same
-- key, so the rulers always answer for what is actually rendered.
local function applyFonts(inst)
    local cfg = inst.cfg
    local face = addon.ResolveFontFace(cfg.face)
    addon.ApplyFontStyle(inst.pctFS, face, currentPctPoint(inst), cfg.style)
    applyOverrideFace(inst.valFS, cfg.valSize, face, cfg.valFace, cfg.style)
    addon.ApplyFontStyle(inst.symbolFS, face, currentSymbolPoint(inst), cfg.style)
    applyOverrideFace(inst.nameFS, currentNamePoint(inst), face, cfg.nameFace, cfg.nameStyle)
    addon.ApplyFontStyle(inst.powerFS, face, cfg.powerSize, cfg.powerStyle)
    addon.ApplyFontStyle(inst.altPowerFS, face, cfg.altPowerSize, cfg.powerStyle)
    -- The '%' companions ride at half their number's size, min 1. Both power
    -- rows have one: either can render as a percent (mana).
    addon.ApplyFontStyle(inst.powerSymbolFS, face, math.max(1, cfg.powerSize * 0.5), cfg.powerStyle)
    addon.ApplyFontStyle(inst.altPowerSymbolFS, face, math.max(1, cfg.altPowerSize * 0.5), cfg.powerStyle)
    -- The absorb text shares the value row's settings outright:
    -- same size, same face override, same style. No keys of its own.
    applyOverrideFace(inst.absorbFS, cfg.valSize, face, cfg.valFace, cfg.style)
    addon.ApplyFontStyle(inst.levelFS, face, cfg.levelSize, cfg.levelStyle)
    -- The "lvl" prefix rides at 75% of the number's size, min 1.
    addon.ApplyFontStyle(inst.levelPrefixFS, face, math.max(1, cfg.levelSize * LEVEL_PREFIX_SCALE), cfg.levelStyle)
end

--------------------------------------------------------------------------------
-- Width-only stretch (the Paint drag): the engine has no per-axis text scale,
-- but Scale animations take separate axes and apply while playing, so a looping
-- animation whose from and to scales are both (x, 1) holds a constant render
-- transform. It stretches the whole rendered output -- outline and shadow widen
-- with the glyphs, slightly soft -- so it is the live tuning tool; a settled
-- factor gets baked into a real font file for crisp rasterisation (the shipped
-- Anton Wide 1.5x).
-- Animations transform rendering only, never the layout rect, so anchors and
-- the equal-width tuning are unaffected (both rows stretch by the same factor).
--------------------------------------------------------------------------------

-- Keyed by FontString, so records from both instances coexist. The capability
-- flag is session-wide.
local stretchAnims = {}
local stretchUnsupported = false

local function applyStretch(inst)
    if stretchUnsupported or not inst.frame then return end
    local cfg = inst.cfg
    local fx = cfg.stretch or 1
    local edgeOrigin = (cfg.align == "left") and "LEFT" or "RIGHT"
    for _, fs in ipairs({ inst.pctFS, inst.valFS, inst.symbolFS, inst.nameFS,
        inst.powerFS, inst.powerSymbolFS, inst.altPowerFS, inst.altPowerSymbolFS, inst.absorbFS,
        inst.levelFS, inst.levelPrefixFS }) do
        if fs then
            -- Centered number rows stretch about their shared centerline; the name
            -- (still edge-anchored) and the '%' keep the align edge as their origin.
            -- The absorb text centers on the same column, so it shares the origin.
            -- Known limit: its box textures track the layout rect, and the stretch
            -- transform is render-only -- the box does not widen with the glyphs.
            local origin = (cfg.center and (fs == inst.pctFS or fs == inst.valFS or fs == inst.absorbFS))
                and "CENTER" or edgeOrigin
            local rec = stretchAnims[fs]
            if fx == 1 then
                if rec then rec.group:Stop() end
            else
                if not rec then
                    local group = fs:CreateAnimationGroup()
                    group:SetLooping("REPEAT")
                    local anim = group:CreateAnimation("Scale")
                    anim:SetDuration(0.05)
                    if not (anim.SetScaleFrom and anim.SetScaleTo) then
                        stretchUnsupported = true
                        addon:Print("Stretch unavailable: this client's Scale animation lacks per-axis SetScaleFrom/SetScaleTo.")
                        return
                    end
                    rec = { group = group, anim = anim }
                    stretchAnims[fs] = rec
                end
                rec.group:Stop()
                pcall(rec.anim.SetOrigin, rec.anim, origin, 0, 0)
                pcall(rec.anim.SetScaleFrom, rec.anim, fx, 1)
                pcall(rec.anim.SetScaleTo, rec.anim, fx, 1)
                rec.group:Play()
                -- Play in the same frame as Stop (or creation) occasionally
                -- does not take; re-arm one frame later if the group is idle.
                if rec.group.IsPlaying and not rec.group:IsPlaying() then
                    local group = rec.group
                    C_Timer.After(0, function()
                        if (inst.cfg.stretch or 1) ~= 1 and not group:IsPlaying() then
                            group:Play()
                        end
                    end)
                end
            end
        end
    end
end

-- The tuned name baseline. cfg.nameOffset/nameY are offsets FROM this, so the
-- shipped Position sliders read 0/0 at the settled position and negatives pull
-- the name tighter toward the numbers.
local NAME_BASE_X = 100
local NAME_BASE_Y = 5

-- The number-row geometry three call sites have to agree on: applyLayout
-- anchors from it, envelopeFor reserves from it, and the dead skull sits on it.
-- Derived once here so they cannot drift -- the classifySeatY precedent.
--
-- The percent row reserves the LARGEST configured digit rendering, so a big
-- one-digit paint never overlaps the value row. nameSeatY is the resulting
-- gap-midline between the two number rows plus the name's own tuned lift, in
-- up-positive box coords (envelopeFor flips the sign for its own convention).
local function pctGlyphCeiling(cfg)
    if not cfg.digits then return cfg.pctSize end
    return math.max(cfg.pctSize, cfg.digitSize1, cfg.digitSize2, cfg.digitSize3)
end

local function pctRowHeight(cfg)
    return math.ceil(pctGlyphCeiling(cfg) * 0.85)
end

local function nameSeatY(cfg)
    return -(pctRowHeight(cfg) + cfg.gap / 2) + NAME_BASE_Y + cfg.nameY
end

-- Where the name's INK sits, as opposed to where its rect is anchored. The
-- name's single-point LEFT/RIGHT anchor pins its RECT's vertical center, and
-- the rect reserves descender space the glyphs never use, so the visible ink
-- centers HIGHER than the anchor by half that share. That is anchorAbsorbFS's
-- halo mechanism verbatim -- same calibrated cfg.descent ratio -- taken
-- against the FITTED point size rather than the fit ceiling, because a
-- shrunken name's ink closes back toward its rect center.
--
-- Anything that has to look CENTERED ON the name, rather than merely sit
-- beside it, aims here. Satellites do not: they anchor to the rect edges on
-- purpose, so a wrapped second line pushes them out of the way.
local function nameInkMidY(inst)
    local cfg = inst.cfg
    return nameSeatY(cfg) + currentNamePoint(inst) * cfg.descent * 0.5
end

-- Base separation for the "nameside" power location; powerX/powerY offset from
-- it, so the offset sliders read 0 at the tuned look.
local POWER_SIDE_GAP = 6

-- Inward inset for the four name-edge locations: below/above-name text starts
-- slightly inside the name box's outer edge instead of flush with it. Baked
-- into the anchor, so the offset sliders still read 0 at the default look.
local POWER_EDGE_INSET = 5

-- Vertical clearance for the same four locations: below-name text drops (and
-- above-name text rises) further so a two-line wrapped name -- which
-- overhangs the rect edge the anchor tracks -- never crowds the power text.
-- Universal by request: no per-line-count logic. Baked in like the inset, so
-- the offset sliders still read 0 at the default look.
local POWER_EDGE_DROP = 5

-- The classification icon's fixed vertical seat, in the same sign convention as
-- the offset sliders it replaces (positive = up). It rides the name-relative
-- locations but has no user offsets: a texture only needs to look centred, and
-- the value that centres it is a constant, tuned in-game.
-- Derived rather than baked so applyPowerLayout and computeEnvelope cannot
-- drift apart -- both call this.
--
-- POWER_EDGE_DROP is clearance for TEXT, and the icon does not want it. That
-- went unnoticed because the drop is applied OUTWARD: on a bottom location the
-- tuned +5 cancelled it exactly, and only the top locations were left paying it
-- twice -- 10px above the name's rect, plus the font's own ascent reserve above
-- the cap line on top of that. Hence "the icon hovers too high above the name"
-- on a topright frame while a bottom one looked right, on Boss and Target
-- alike. The seat now cancels the drop on all four
-- corner locations, so the icon's near edge lands on the name's rect edge and
-- the only gap left is the font's ascent reserve -- which scales with nameSize,
-- as it should. nameside takes no drop at all, so it keeps the tuned value.
--
-- CLASSIFY_TUCK is the knob for going further: it moves the icon TOWARD the
-- name, into the ascent reserve and then into the caps. Slight overlap is
-- sanctioned, since the name is not the thing that must stay legible
-- at the corner.
local CLASSIFY_TUCK       = 0
local CLASSIFY_NAMESIDE_Y = 5

local function classifySeatY(cfg)
    local loc = cfg.classifyLoc
    if loc == "topleft" or loc == "topright" then
        return -POWER_EDGE_DROP - CLASSIFY_TUCK
    elseif loc == "bottomleft" or loc == "bottomright" then
        return POWER_EDGE_DROP + CLASSIFY_TUCK
    end
    return CLASSIFY_NAMESIDE_Y
end

-- The power texts anchor DIRECTLY to nameFS: its LEFT/RIGHT edges are
-- deterministic (applyLayout gives it an explicit SetWidth), and TOP/BOTTOM
-- riding the wrap is the point -- a two-line name pushes below-name text down
-- with it. Anchor resolution is engine-side (the symbolFS->pctFS precedent), so
-- nothing reads the possibly-secret content. Natural width on the power FS
-- itself: a width would engage the truncation engine. Uniform sign convention
-- +x = right, +y = up.
-- The name box is cfg.nameMaxWidth wide, but the ink hugs its justified
-- (numbers-facing) edge -- the box's far edge is mostly empty air on short
-- names, and a power text anchored there floats outside the name (user round
-- 3). The justified edge is deterministic; the far edge is ink-true whenever
-- the name could be measured at all (inst.nameInkWidth -- measureNameInk rules
-- both the how and the when: synchronously on the shared ruler, in the same
-- step as the paint, so this function never sees a half-settled answer). With a
-- measurement, far-side locations anchor to the justified edge offset by the
-- ink width, tracking the first and last letter; without one -- a secret
-- name, which no getter and no ruler in 12.0 can size -- they fall back to the
-- box edge, the pre-round-3 behavior, documented, not fixable blind.
-- trailW reserves room on the right for a trailing companion (the half-size
-- '%'): right-justified locations pull the NUMBER left by that much so the
-- companion, not the digits, lands on the alignment edge. Left-justified
-- locations need nothing -- the companion grows the block away from the edge.
-- leadW is its mirror for a LEADING companion (the level pair's "lvl"):
-- left-justified locations push the number right so the prefix, not the
-- digits, lands on the alignment edge; right-justified locations need
-- nothing.
-- anchorPowerFS also anchors the classification TEXTURE, which has no
-- JustifyH. Every anchor point below resolves correctly against an
-- explicitly-sized Texture, so one guard is the whole generalization.
local function setJustify(fs, justify)
    if fs.SetJustifyH then fs:SetJustifyH(justify) end
end

local function anchorPowerFS(inst, fs, loc, x, y, trailW, leadW)
    trailW = trailW or 0
    leadW = leadW or 0
    fs:ClearAllPoints()
    local nameFS = inst.nameFS
    local nearRight = inst.cfg.align ~= "left"   -- JustifyH tracks align in every layout mode
    local inkW = inst.nameInkWidth
    if type(inkW) ~= "number" or inkW <= 0 then inkW = nil end
    if loc == "bottomleft" then
        setJustify(fs, "LEFT")
        if nearRight and inkW then
            fs:SetPoint("TOPLEFT", nameFS, "BOTTOMRIGHT", -inkW + POWER_EDGE_INSET + leadW + x, y - POWER_EDGE_DROP)
        else
            fs:SetPoint("TOPLEFT", nameFS, "BOTTOMLEFT", POWER_EDGE_INSET + leadW + x, y - POWER_EDGE_DROP)
        end
    elseif loc == "bottomright" then
        setJustify(fs, "RIGHT")
        if not nearRight and inkW then
            fs:SetPoint("TOPRIGHT", nameFS, "BOTTOMLEFT", inkW - POWER_EDGE_INSET + x - trailW, y - POWER_EDGE_DROP)
        else
            fs:SetPoint("TOPRIGHT", nameFS, "BOTTOMRIGHT", -POWER_EDGE_INSET + x - trailW, y - POWER_EDGE_DROP)
        end
    elseif loc == "topleft" then
        setJustify(fs, "LEFT")
        if nearRight and inkW then
            fs:SetPoint("BOTTOMLEFT", nameFS, "TOPRIGHT", -inkW + POWER_EDGE_INSET + leadW + x, y + POWER_EDGE_DROP)
        else
            fs:SetPoint("BOTTOMLEFT", nameFS, "TOPLEFT", POWER_EDGE_INSET + leadW + x, y + POWER_EDGE_DROP)
        end
    elseif loc == "topright" then
        setJustify(fs, "RIGHT")
        if not nearRight and inkW then
            fs:SetPoint("BOTTOMRIGHT", nameFS, "TOPLEFT", inkW - POWER_EDGE_INSET + x - trailW, y + POWER_EDGE_DROP)
        else
            fs:SetPoint("BOTTOMRIGHT", nameFS, "TOPRIGHT", -POWER_EDGE_INSET + x - trailW, y + POWER_EDGE_DROP)
        end
    else
        -- nameside: on the name row, the side away from the numbers -- which is
        -- the ink's FAR side, so this location benefits most from the ink width.
        -- The single-point LEFT/RIGHT anchor centers the power text vertically
        -- on the name row's midline, same mechanism as the name's own anchor.
        if not nearRight then
            setJustify(fs, "LEFT")
            if inkW then
                fs:SetPoint("LEFT", nameFS, "LEFT", inkW + POWER_SIDE_GAP + leadW + x, y)
            else
                fs:SetPoint("LEFT", nameFS, "RIGHT", POWER_SIDE_GAP + leadW + x, y)
            end
        else
            setJustify(fs, "RIGHT")
            if inkW then
                fs:SetPoint("RIGHT", nameFS, "RIGHT", -inkW - POWER_SIDE_GAP + x - trailW, y)
            else
                fs:SetPoint("RIGHT", nameFS, "LEFT", -POWER_SIDE_GAP + x - trailW, y)
            end
        end
    end
end

--------------------------------------------------------------------------------
-- The classification icon's step-aside
--------------------------------------------------------------------------------
-- The icon and the level pair ride the same five locations, and the icon has no
-- positioning of its own, so a shared location stacks one on top of the other.
-- Fresh Target profiles dodge it by defaulting the level to topleft, but every
-- Target profile saved before that change still has both on topright. The icon
-- steps RIGHT until it clears the level block and sits immediately beside it;
-- the level itself never moves.
--
-- How far depends on which way the blocks grow. Left-justified locations pin
-- their LEFT edge and grow right, so the icon has to clear the level's whole
-- width. Right-justified ones pin their RIGHT edge and grow left, so stepping
-- right by the icon's OWN width already lands its left edge exactly on the
-- level's right edge -- the level's width does not enter into it.
local CLASSIFY_LEVEL_GAP = 3

-- Two characters is the entire domain of the digit field: the level cap is two
-- digits and the unknown-level fallback is "??". Fixed, never the live level --
-- computeEnvelope reserves this step, and a reservation that moved with the
-- target would be a protected SetSize the moment it happened in combat.
local LEVEL_DIGIT_FIELDS = { "00", "??" }

local function levelBlockWidth(cfg)
    local prefixSize = math.max(1, cfg.levelSize * LEVEL_PREFIX_SCALE)
    local face = addon.ResolveFontFace and addon.ResolveFontFace(cfg.face)
    local prefixW, digitsW = nil, 0
    if addon.MeasureTextWidth then
        prefixW = addon.MeasureTextWidth("lvl", face, prefixSize, cfg.levelStyle)
        for _, field in ipairs(LEVEL_DIGIT_FIELDS) do
            local w = addon.MeasureTextWidth(field, face, cfg.levelSize, cfg.levelStyle)
            if type(w) == "number" and w > digitsW then digitsW = w end
        end
    end
    -- Same fallback shape applyPowerLayout uses for its own "lvl" measurement:
    -- the ruler is plain readable text, so this only covers a missing ruler.
    if type(prefixW) ~= "number" or prefixW <= 0 then prefixW = prefixSize * 1.2 end
    if digitsW <= 0 then digitsW = cfg.levelSize * 1.2 end
    return prefixW + cfg.levelSize * LEVEL_PREFIX_GAP_EM + digitsW
end

-- The step a fully painted level demands. PURE CONFIG, so computeEnvelope can
-- reserve it without ever consulting the live target.
local function classifyShiftReserved(inst)
    local cfg = inst.cfg
    if not cfg.classifyShow then return 0 end
    if cfg.classifyLoc ~= cfg.levelLoc then return 0 end
    -- Justification per anchorPowerFS: the four corners justify by name, and
    -- nameside follows the frame's handedness.
    local growsRight = cfg.classifyLoc == "topleft" or cfg.classifyLoc == "bottomleft"
        or (cfg.classifyLoc == "nameside" and cfg.align == "left")
    local clear = growsRight and levelBlockWidth(cfg) or cfg.classifySize
    -- levelX rides along: the user can nudge the level, and the icon has to
    -- clear where it sits. Clamped at 0 so a level nudged far enough
    -- left simply frees the icon rather than dragging it off its own corner.
    return math.max(0, cfg.levelX + clear + CLASSIFY_LEVEL_GAP)
end

-- What the icon uses: the same step, dropped when the level painted
-- nothing (hide-at-max, a hidden unknown level, a missing API). Only ever
-- SMALLER than the reserved step, so an un-stepped icon still lands inside the
-- envelope and following it never needs a resize.
local function anchorClassify(inst)
    local tex = inst.classifyTex
    if not tex then return end
    local cfg = inst.cfg
    local shift = (inst.levelPainted == false) and 0 or classifyShiftReserved(inst)
    tex:SetSize(cfg.classifySize, cfg.classifySize)
    anchorPowerFS(inst, tex, cfg.classifyLoc, shift, classifySeatY(cfg), 0, 0)
end

-- The width a '%' companion takes off a right-justified power row, so the
-- SIGN lands on the alignment edge instead of poking past it. '%' is plain
-- readable text, so the shared ruler measures it synchronously; the estimate
-- only covers a missing ruler. Zero when the row is not a percent or the sign
-- is off.
local function powerSymbolReserve(inst, size, isPct)
    local cfg = inst.cfg
    if not (cfg.powerSymbol and isPct) then return 0 end
    local symSize = math.max(1, size * 0.5)
    local w
    if addon.MeasureTextWidth then
        w = addon.MeasureTextWidth("%", addon.ResolveFontFace(cfg.face), symSize, cfg.powerStyle)
    end
    if type(w) ~= "number" or w <= 0 then w = symSize * 0.9 end
    return w
end

-- The sign always hangs off its number's trailing edge, superscript
-- top-aligned (the health row's symbol treatment). Anchor resolution is
-- engine-side, so the number's secret rendered width is never read; the sign
-- only draws when updatePower gave it text.
local function anchorPowerSymbol(symFS, numFS)
    if not symFS then return end
    symFS:ClearAllPoints()
    symFS:SetPoint("TOPLEFT", numFS, "TOPRIGHT", 0, 0)
end

-- Separate from applyLayout so the loc/offset setters can re-anchor the power
-- texts alone -- applyLayout restarts the stretch animations (see probeDigits),
-- churn a positioning nudge does not need.
local function applyPowerLayout(inst)
    if not inst.frame then return end
    local cfg = inst.cfg
    anchorPowerFS(inst, inst.powerFS, cfg.powerLoc, cfg.powerX, cfg.powerY,
        powerSymbolReserve(inst, cfg.powerSize, inst.powerIsPct))
    anchorPowerSymbol(inst.powerSymbolFS, inst.powerFS)
    -- The level pair rides the same location system. The "lvl"
    -- prefix leads the number, so left-justified locations reserve its width
    -- plus the sub-space gap (leadW, the trailW mirror). "lvl" is plain
    -- readable text, so the shared ruler measures it synchronously; the
    -- estimate only covers a missing ruler.
    local lvlPrefixSize = math.max(1, cfg.levelSize * LEVEL_PREFIX_SCALE)
    local lvlGap = cfg.levelSize * LEVEL_PREFIX_GAP_EM
    local leadW = 0
    if addon.MeasureTextWidth then
        leadW = addon.MeasureTextWidth("lvl", addon.ResolveFontFace(cfg.face), lvlPrefixSize, cfg.levelStyle)
    end
    if type(leadW) ~= "number" or leadW <= 0 then leadW = lvlPrefixSize * 1.2 end
    anchorPowerFS(inst, inst.levelFS, cfg.levelLoc, cfg.levelX, cfg.levelY, 0, leadW + lvlGap)
    -- The prefix hangs off the number's leading edge. Rect-bottom alignment
    -- would leave the smaller prefix's baseline low by the descent share of
    -- the size difference (both rects reserve descent the glyphs never use);
    -- lift it back to a true shared baseline -- the file's descent doctrine.
    local pre = inst.levelPrefixFS
    if pre then
        pre:ClearAllPoints()
        pre:SetPoint("BOTTOMRIGHT", inst.levelFS, "BOTTOMLEFT", -lvlGap,
            (cfg.levelSize - lvlPrefixSize) * cfg.descent)
    end
    anchorPowerFS(inst, inst.altPowerFS, cfg.altPowerLoc, cfg.altPowerX, cfg.altPowerY,
        powerSymbolReserve(inst, cfg.altPowerSize, inst.altPowerIsPct))
    anchorPowerSymbol(inst.altPowerSymbolFS, inst.altPowerFS)
    -- The classification icon rides the same five locations as the texts it
    -- sits among -- name-relative, not frame-edge. No
    -- trailW/leadW: a texture has no companion glyph.
    anchorClassify(inst)
end

-- The absorb shield text (the glow-only look won the style experiment over a
-- boxed pill): white number on a soft gold
-- halo, above the percent. Fixed look -- constants, not config; only
-- show/offsets are configurable.
local ABSORB_GAP    = 15  -- ink-true: the number's INK bottom above the
                          -- percent's rect top (anchorAbsorbFS folds the
                          -- below-ink descent share out of the anchor, so the
                          -- eye-measured gap holds at every value size);
                          -- baked 0,0 origin of the offset sliders (the
                          -- POWER_EDGE_* pattern)
local ABSORB_GLOW_X = 18  -- halo texture overreach past the FontString rect,
local ABSORB_GLOW_Y = 13  -- per side -- the file's visible ring sits well
                          -- inside its rect, so the reach is larger than the
                          -- halo the eye sees
local ABSORB_GLOW_ALPHA = 0.70  -- the halo IS the backdrop, so it carries
                                -- real presence (ADD light over the dark
                                -- chrome/world still reads gentle)

-- The halo anchors to the absorb FontString's rect, and a CLEARED FontString
-- collapses its rect -- the glow would shrink to a bare overreach-sized blob.
-- So visibility is driven exclusively by updateAbsorb's paint verdict (a
-- plain Lua bool, never a secret), and the halo is NEVER left shown while
-- the text is empty.
local function setAbsorbGlowShown(inst, shown)
    if inst.absorbGlowTex then
        inst.absorbGlowTex:SetShown(shown and true or false)
    end
end

-- PCT-anchored, replacing an earlier frame-top anchor:
-- the percent's rect top rises with digit-mode size changes, and a fixed spot
-- let the taller 2-digit rendering climb into it. Riding the rect top keeps
-- the visual gap constant instead -- the text now moves at the 100->99 and
-- 10->9 transitions, which is the accepted cost. Anchor resolution is
-- engine-side, so the secret percent's rect is a legal relative region (the
-- symbolFS precedent), and a single BOTTOM->TOP point centers the text on
-- the rendered digits in every align mode.
local function anchorAbsorbFS(inst)
    local fs, pctFS = inst.absorbFS, inst.pctFS
    if not fs or not pctFS then return end
    local cfg = inst.cfg
    -- The ink sits HIGH in the FS rect: the abbreviated value is digits and
    -- cap suffixes (no descenders), the face's top leading is near zero, and
    -- the descent share below the baseline is dead space. Fold that share out
    -- of the anchor so ABSORB_GAP measures what the eye measures -- ink
    -- bottom to percent rect top -- at every value size (the same calibrated
    -- cfg.descent ratio the percent lift uses, scaled by the value point
    -- size). Size-dependent, so the anchors live here (re-run by every
    -- font/layout setter), not in ensureFrame.
    local inkDrop = cfg.valSize * cfg.descent
    fs:ClearAllPoints()
    fs:SetPoint("BOTTOM", pctFS, "TOP", cfg.absorbX, ABSORB_GAP - inkDrop + cfg.absorbY)
    -- The halo centers on the ink, not the rect, for the same reason: shift
    -- its window UP by half the descent share.
    if inst.absorbGlowTex then
        local shift = inkDrop * 0.5
        inst.absorbGlowTex:ClearAllPoints()
        inst.absorbGlowTex:SetPoint("TOPLEFT", fs, "TOPLEFT",
            -ABSORB_GLOW_X, ABSORB_GLOW_Y + shift)
        inst.absorbGlowTex:SetPoint("BOTTOMRIGHT", fs, "BOTTOMRIGHT",
            ABSORB_GLOW_X, -ABSORB_GLOW_Y + shift)
    end
end

--------------------------------------------------------------------------------
-- Adornment art: the dead skull and the elite/rare classification icon
--------------------------------------------------------------------------------
-- BOTH of these branch on a plain Lua value. Verified against
-- Blizzard_APIDocumentationGenerated/UnitDocumentation.lua (12.0.7): neither
-- UnitIsDeadOrGhost nor UnitClassification carries a SecretReturns annotation,
-- unlike UnitHealth which does. So no issecretvalue dance, no
-- SetAlphaFromBoolean, no isZeroAmount launder -- the pcall below is house
-- style against a missing/erroring API, not a secrecy guard. This is what
-- closed the "readability under restrictions: measure first" open item.
--
-- SetAtlas fails SILENTLY on an unknown name -- it leaves an invisible or
-- white region rather than erroring -- so every name here is gated on
-- C_Texture.GetAtlasInfo first, the same doctrine Cast Bar Z follows.

-- Six candidates shipped for the in-game sharpness bake-off (the boss banner
-- medallion and spikes, three Torghast layer skulls, this one). The raid marker
-- won outright at the size Scoot renders at -- everything else read soft -- so the
-- others are gone and the style selector with them. The table keeps its shape
-- because this is provisional: re-adding a candidate is one entry.
local DEAD_ICONS = {
    -- 64px inside a 256x256 sheet; `file` is a raw path, not an atlas.
    raidmarker = {
        file = "Interface\\TargetingFrame\\UI-RaidTargetingIcons",
        coords = { 0.75, 1, 0.25, 0.5 },                 -- icon 8, bottom-right quadrant
    },
}
local DEAD_ICON_FALLBACK = "raidmarker"

-- Blizzard's live mapping, lifted verbatim from
-- Blizzard_NamePlateClassificationFrame.lua:120-125 (duplicated in
-- Blizzard_DamageMeter/DamageMeterEntry.lua:69-77). Note plain "rare" gets a
-- STAR, not a dragon -- that asymmetry is Blizzard's, and matching it is the
-- point: the game already trains the read.
local CLASSIFICATION_ATLAS = {
    elite     = "nameplates-icon-elite-gold",
    worldboss = "nameplates-icon-elite-gold",
    rareelite = "nameplates-icon-elite-silver",
    rare      = "UI-HUD-UnitFrame-Target-PortraitOn-Boss-Rare-Star",
}
-- The Edit Mode stand-in: the icon is positionable, so it must be visible at
-- the exact moment the user is placing it, even on a targetless preview.
local CLASSIFY_PREVIEW_ATLAS = "nameplates-icon-elite-gold"

local function atlasExists(name)
    if not name or not C_Texture or not C_Texture.GetAtlasInfo then return false end
    local ok, info = pcall(C_Texture.GetAtlasInfo, name)
    return ok and info ~= nil
end

-- Paint one texture from a DEAD_ICONS entry. Returns true on a successful
-- paint so the caller can fall back.
local function applyDeadIconArt(tex, key)
    local entry = DEAD_ICONS[key]
    if not entry then return false end
    if entry.atlas then
        if not atlasExists(entry.atlas) then return false end
        if not tex.SetAtlas then return false end
        tex:SetTexCoord(0, 1, 0, 1)
        return pcall(tex.SetAtlas, tex, entry.atlas) and true or false
    end
    local ok = pcall(tex.SetTexture, tex, entry.file)
    if not ok then return false end
    if entry.coords then
        pcall(tex.SetTexCoord, tex, unpack(entry.coords))
    end
    return true
end

-- Memoized: re-running SetTexture every health tick would be pure churn. The
-- key is read from config so a second candidate can return without touching
-- this path; with one entry it always resolves to the fallback.
local function applyDeadIconTexture(inst)
    local tex = inst.deadTex
    if not tex then return end
    local key = inst.cfg.deadIconAtlas or DEAD_ICON_FALLBACK
    if not DEAD_ICONS[key] then key = DEAD_ICON_FALLBACK end
    if inst.appliedDeadIcon == key then return end
    if not applyDeadIconArt(tex, key) then
        -- A missing atlas is silent, so land on something that always exists
        -- rather than leaving an invisible or white block on the frame.
        applyDeadIconArt(tex, DEAD_ICON_FALLBACK)
    end
    inst.appliedDeadIcon = key
end

local function setDeadIconShown(inst, shown)
    if inst.deadTex then
        inst.deadTex:SetShown(shown and true or false)
    end
end

--------------------------------------------------------------------------------
-- The envelope: the frame rect covers the WHOLE element
--------------------------------------------------------------------------------
-- Content does not anchor to the outer frame -- it anchors to inst.box, the
-- tuned numbers box (cfg.width x cfg.height) floating inside it. The outer
-- frame resizes here to a config-derived envelope around the box, the name's
-- wrap box, and every satellite text, so everything that treats the frame as
-- "the element" -- LibEditMode's selection outline (SetAllPoints), the secure
-- click overlay, a snapped Cast Bar Z (bar edge to frame edge) -- fits the
-- whole visual without ever measuring it. Config-derived on purpose: the live
-- FontStrings hold secrets and are permanently unmeasurable (the applyLayout
-- doctrine below). The envelope is a deterministic SUPERSET: satellite widths
-- are size-based estimates, the name contributes its full wrap box at the fit
-- ceiling, and the level row reserves space even when hide-at-max blanks it
-- (a box that breathes on level-up reads as a bug). Absorb text is the one
-- deliberate omission -- transient combat text above the numbers, unboxed the
-- way Blizzard leaves its own combat feedback unboxed.

local ENV_LINE_H = 1.25   -- conservative line box per point of text size
local ENV_PAD    = 6      -- breathing room past the name-side extents

-- One satellite text's contribution, in box-local down-positive coordinates.
-- Mirrors anchorPowerFS's five locations against the same name-box geometry
-- (offsets there are up-positive, hence the sign flips on y).
local function envelopeSatellite(acc, loc, size, x, y, leadW, box)
    -- box overrides the text estimates for a satellite that is not text: the
    -- classification icon is a square texture of known size, and running it
    -- through the "3.5 em wide, 1.25 em tall line box" heuristic would
    -- over-reserve nearly 3x its width on the nameside location.
    local h = box and size or size * ENV_LINE_H
    local w = box and size or (size * 3.5 + (leadW or 0))
    local t, b
    if loc == "topleft" or loc == "topright" then
        b = acc.nameTop - POWER_EDGE_DROP - y
        t = b - h
        acc.far = math.max(acc.far, acc.nameFar + math.max(0, x))
    elseif loc == "nameside" then
        local mid = acc.nameMidY - y
        t, b = mid - h / 2, mid + h / 2
        acc.far = math.max(acc.far, acc.nameFar + POWER_SIDE_GAP + w + math.max(0, x))
    else -- bottomleft | bottomright
        t = acc.nameBottom + POWER_EDGE_DROP - y
        b = t + h
        acc.far = math.max(acc.far, acc.nameFar + math.max(0, x))
    end
    acc.top = math.min(acc.top, t)
    acc.bottom = math.max(acc.bottom, b)
end

local function envelopeFor(inst, lines)
    local cfg = inst.cfg

    -- The same row geometry applyLayout derives, in down-positive box coords.
    local nameX = NAME_BASE_X + cfg.nameOffset
    local nameMidY = -nameSeatY(cfg)   -- shared seat, flipped to down-positive
    local nameHalf = lines * cfg.nameSize * ENV_LINE_H / 2

    local acc = {
        nameMidY = nameMidY,
        nameTop = nameMidY - nameHalf,
        nameBottom = nameMidY + nameHalf,
        nameFar = nameX + cfg.nameMaxWidth,
        top = 0, bottom = cfg.height, far = cfg.width,
    }
    acc.top = math.min(acc.top, acc.nameTop)
    acc.bottom = math.max(acc.bottom, acc.nameBottom)
    acc.far = math.max(acc.far, acc.nameFar)

    if cfg.powerShow then
        envelopeSatellite(acc, cfg.powerLoc, cfg.powerSize, cfg.powerX, cfg.powerY)
    end
    if cfg.altPowerShow then
        envelopeSatellite(acc, cfg.altPowerLoc, cfg.altPowerSize, cfg.altPowerX, cfg.altPowerY)
    end
    envelopeSatellite(acc, cfg.levelLoc, cfg.levelSize, cfg.levelX, cfg.levelY,
        cfg.levelSize * 1.5)
    -- Unconditional while the feature is on, exactly like the level row above:
    -- the contribution is PURE CONFIG (size x loc x offsets), never a function
    -- of the live classification. That is what keeps a mob-to-mob target swap
    -- from moving the envelope -- and the envelope's SetSize is protected once
    -- the secure click child SetAllPoints the frame, so a classification-driven
    -- resize would be an ADDON_ACTION_BLOCKED in combat. No regen slot exists
    -- here because none can be needed.
    if cfg.classifyShow then
        -- box=true: a square texture, so its own size IS its box on both axes.
        -- The step-aside is reserved at its full config-derived width, never at
        -- the live one: the icon may sit un-stepped when the level paints
        -- nothing, and that only ever moves it further INSIDE this reservation.
        envelopeSatellite(acc, cfg.classifyLoc, cfg.classifySize,
            classifyShiftReserved(inst), classifySeatY(cfg), 0, true)
    end
    -- The dead skull is deliberately absent: it is half the number stack it
    -- replaces, centred on the name row that sits between the two, so it lives
    -- inside the overlap of two spans already reserved above (the numbers box
    -- and the name's own band) and can never grow the envelope.

    local far = math.ceil(acc.far + ENV_PAD)
    local top = math.floor(math.min(0, acc.top))
    local bottom = math.ceil(acc.bottom)
    return {
        align = cfg.align,
        W = far, H = bottom - top, T = -top,
    }
end

-- How much of the envelope's HEIGHT is reserved for name lines that a given
-- unit usually does not use. The rect has to hold a wrapped name -- and every
-- satellite anchors to the name, so a second line pushes the top ones up and
-- the bottom ones down -- but most names are one line, which leaves a band of
-- reserved-and-empty rect above and below the visible content.
--
-- Nobody can see that band on a lone frame. Stacked, it is the whole distance
-- between two frames, which is why boss frames looked far apart at every
-- spacing the slider offered. stack.lua subtracts this
-- from the chain step, so the Spacing slider measures the gap between what is
-- on screen rather than between two reservations.
--
-- Measured as the difference between the real envelope and a one-line one, not
-- estimated: that way a config with no satellites -- where the extra line
-- changes far less, because the name box is not what drives the edges -- gets
-- the smaller number it deserves, and the correction can never exceed the
-- reservation it removes. A name that DOES wrap therefore lands its content
-- exactly against its neighbour's rather than overlapping it.
-- The one-line recompute now runs for every instance rather than stacked ones
-- only, and splits the reserve per edge: the ping receiver needs to know how
-- much empty rect sits above the content and how much below, where stack.lua
-- only ever needed the total. Pure config arithmetic, and applyEnvelope's cache
-- absorbs the repeats.
local function computeEnvelope(inst)
    local env = envelopeFor(inst, inst.cfg.nameMaxLines)
    local one = envelopeFor(inst, 1)
    env.snug = math.max(0, env.H - one.H)
    env.snugTop = math.max(0, env.T - one.T)
    env.snugBottom = math.max(0, env.H - env.T + one.T - one.H)
    return env
end

-- The aura rows' alignment span: the content's horizontal extent, as offsets
-- from the frame's LEFT edge. The envelope is a deterministic SUPERSET, so a
-- row aligned to the frame edge floats past the visible content, so
-- the rows align to the leftmost ELEMENT instead. Box side: the
-- centered column's near ink edge, estimated from config -- half the widest
-- configured rendering at ~0.55 em per glyph (the same size-based-estimate
-- doctrine as the envelope satellites; non-center layouts are already flush).
-- Name side: the ink-true far edge when the name could be measured at all
-- (inst.nameInkWidth, the anchorPowerFS mechanism -- every readable name
-- measures), the full wrap box when it could not.
local AURA_GLYPH_EM  = 0.55  -- rendered width per digit glyph, in em
local AURA_VAL_GLYPHS = 4.5  -- glyph budget of a "505k"-style abbreviated value

function UFZ._AuraContentSpan(inst)
    local cfg = inst.cfg
    -- appliedEnv mirrors the frame's real rect; cfg.width is the documented
    -- combat-staleness fallback (self-heals on the regen drain).
    local W = (inst.appliedEnv and inst.appliedEnv.W) or cfg.width or 140
    local numInset = 0
    if cfg.center then
        local pctW
        if cfg.digits then
            pctW = math.max(cfg.digitSize1, cfg.digitSize2 * 2, cfg.digitSize3 * 3)
        else
            pctW = cfg.pctSize * 3
        end
        local half = math.max(pctW, (cfg.valSize or 0) * AURA_VAL_GLYPHS)
            * AURA_GLYPH_EM * (cfg.stretch or 1) / 2
        numInset = math.max(0, math.floor((cfg.centerOffset or 0) - half))
    end
    if cfg.align == "left" then
        -- Numbers on the left: rows start at the column's ink edge and may run
        -- under the name out to the far edge.
        return numInset, W
    end
    -- Numbers on the right: rows start at the name's left edge and stop at the
    -- column's ink edge.
    local nameX = NAME_BASE_X + (cfg.nameOffset or 0)
    local inkW = inst.nameInkWidth
    if type(inkW) ~= "number" or inkW <= 0 then inkW = cfg.nameMaxWidth or 150 end
    return math.max(0, math.floor(W - nameX - inkW)), W - numInset
end

--------------------------------------------------------------------------------
-- Ping receiver (12.1)
--------------------------------------------------------------------------------
-- 12.1 rebuilt the ping system around an opt-in attribute.
-- C_PingSecure.GetTargetPingReceiver runs a C-side hit test for the frame under
-- the cursor carrying "ping-receiver", then PingManager calls GetIsPingable /
-- GetAllowRadialWheel / GetTargetInfo on it inside securecallfunction and
-- securecopies the answer (Blizzard_PingManager.lua:109-134). C_PingSecure is
-- SecureOnly, so Scoot can never SEND a ping; it can only satisfy the contract
-- and let Blizzard's own code send it. UFZ parks PlayerFrame, TargetFrame and
-- BossTargetFrameContainer, so without this the frames it replaces lose both the
-- plain unit ping and 12.1's health/mana callout.
--
-- MIXIN PURITY, every unit but the player. Blizzard's PingableType_UnitFrameMixin
-- is used verbatim and never overridden. Addon Lua in that gather makes a SECRET
-- GUID inaccessible to the securecopy at the secure boundary, which hard-errors
-- and wedges the ping listener; guarding with issecretvalue instead kills pings
-- outright in every restricted instance. Both shapes were tried in the field by
-- another addon and both failed. For the same reason the receiver must never
-- carry a .unit FIELD: the mixin reads self.unit before it reads the attribute,
-- and the field is the tainted read. The attribute is the channel that works.
--
-- The receiver is a PLAIN frame seated on the VISIBLE CONTENT rather than the
-- click overlay. The ping hit test is a separate channel from the mouse
-- (PingListenerFrame owns the mouse while the key is held, and Blizzard's CDM
-- items stay receivers with tooltips off, which leaves them fully mouse-dead,
-- CooldownViewer.lua:322-325), so the two rects are free to differ: clicks keep
-- the whole envelope, pings fall through its reserve to the world. And the
-- content rect moves with the subject where the envelope never does, so a
-- protected frame could not be resized for it in combat.

-- The player's split mirrors PlayerFrame's, and the direction of that split is
-- the part worth stating plainly:
--
--   isPlayerResource = self.unit == "player"
--       and not self.PlayerFrameContainer.PlayerPortrait:IsMouseOver()
--       (PingableType.lua:43-58)
--
-- One carve-out inside a resource default, not a resource carve-out inside a
-- plain default. Everywhere on PlayerFrame except the portrait reports a
-- resource. UFZ has no portrait, so the NAME ROW plays it: the name identifies
-- the player where every other part of the element reports a number, and it is
-- the part the user chose to keep the radial wheel on (decision 2026-08-27).
-- Everything else -- health, primary power, alternate power, absorb, level, and
-- the empty rect between them -- reports.
--
-- An earlier round had this inverted, resource ONLY over the numbers box, which
-- put the alternate power number (mana on a Shadow Priest) on the wrong side of
-- the line: pinging it announced the player rather than the resource (reported
-- in-game 2026-08-27). There is no per-resource ping to reach for instead.
-- isPlayerResource is a single bool and the client composes the sentence,
-- "the player's health and in some cases mana"
-- (PingManagerSecureDocumentation.lua:122), so every number on the element gives
-- the same callout and none of them can ask for a specific resource.
--
-- The carve-out is tested through a PLAIN PROXY, inst.pingNameBox, and never
-- through the FontStrings themselves. IsMouseOver is SecretWhenAnchoringSecret
-- (SimpleScriptRegionAPIDocumentation.lua:469-472), and by this addon's own live
-- proof that predicate means "secret when the OBJECT holds a secret aspect"
-- rather than "anchored to something secret" (docs/debugging/secrets.md,
-- "Anchor Secrecy Propagation"): a FontString holding a secret string poisons
-- itself, so powerFS:IsMouseOver() answers with a SECRET bool. A secret in the
-- returned table is precisely what breaks the securecopy at the secure boundary.
-- The proxy is anchored to the outer frame with pure-config numbers and holds
-- nothing secret, so its answer is plain by construction; overNameRow normalises
-- it to a literal true or false regardless, so nothing else can reach the
-- gather's result.
--
-- This is the one Scoot GetTargetInfo that runs inside the gather, and it is safe
-- for the reason the purity rule exists: the local player's own identity is never
-- restricted, so UnitGUID("player") is plain and nothing secret reaches
-- securecopy. IsMouseOver is rect containment and needs no mouse flag, which is
-- how Blizzard can call it on a Texture.
local function overNameRow(rec)
    local box = rec._pingNameBox
    if not box or type(box.IsMouseOver) ~= "function" then return false end
    local ok, over = pcall(box.IsMouseOver, box)
    if not ok then return false end
    if issecretvalue and issecretvalue(over) then return false end
    return over == true
end

local UFZ_PLAYER_PING = {}

function UFZ_PLAYER_PING:GetIsPingable()
    return true
end

function UFZ_PLAYER_PING:GetAllowRadialWheel()
    return overNameRow(self)
end

function UFZ_PLAYER_PING:GetTargetInfo()
    return {
        guid = UnitGUID("player"),
        isPlayerResource = not overNameRow(self),
    }
end

-- Below this the span is treated as no measurement at all and the receiver falls
-- back to the whole envelope: a receiver nobody can hit is the worse failure, and
-- a zero-size region has no rect for the engine to test at all.
local PING_MIN_SPAN = 8

--- The name row's rect, frame-local, x from the LEFT edge and y DOWN from the
--- top. Pure config plus inst.nameInkWidth, the shared ruler's plain measurement
--- rather than a read off the live FontString, mirroring applyLayout's own
--- anchors: the name's rect centre sits nameSeatY below the numbers box's top,
--- and its ink runs inward from NAME_BASE_X + nameOffset off the align edge.
--- Sized for ONE line at the FITTED point size on purpose. The satellites hang
--- off the live rect's top and bottom edges, so a band sized for the wrapped
--- ceiling would reach past them and swallow the very numbers this carve-out
--- exists to leave outside itself.
local function nameRowRect(inst, env)
    local cfg = inst.cfg
    local nameX = NAME_BASE_X + (cfg.nameOffset or 0)
    local inkW = inst.nameInkWidth
    if type(inkW) ~= "number" or inkW <= 0 then inkW = cfg.nameMaxWidth or 150 end
    local l, r
    if cfg.align == "left" then
        l, r = nameX, nameX + inkW
    else
        l, r = env.W - nameX - inkW, env.W - nameX
    end
    -- Clamped into the frame the same way the aura span is: a long name's ink
    -- edge is the only thing that can reach past an edge, and the part outside
    -- is unreachable anyway (the receiver has to be hit before this is asked).
    l = math.max(0, math.floor(l))
    r = math.min(env.W, math.ceil(r))
    local half = math.max(1, currentNamePoint(inst) * ENV_LINE_H / 2)
    local mid = env.T - nameSeatY(cfg)
    return l, math.max(l + 1, r), mid - half, mid + half
end

--- Seats the receiver on the visible content: _AuraContentSpan horizontally (the
--- same ink-true span the aura rows align to), the one-line envelope band
--- vertically (computeEnvelope's snugTop/snugBottom). Then seats the name-row
--- proxy inside it, which is the player's radial-wheel carve-out. Both are
--- skip-compared separately -- the name's ink moves on a subject change that
--- leaves the envelope alone -- and both are unprotected throughout, so neither
--- needs a regen slot.
local function applyPingRect(inst)
    local rec, frame, env = inst.pingReceiver, inst.frame, inst.appliedEnv
    if not (rec and frame and env) then return end

    local l, r = UFZ._AuraContentSpan(inst)
    local top, bottom = env.snugTop or 0, env.snugBottom or 0
    if (r - l) < PING_MIN_SPAN or (env.H - top - bottom) < PING_MIN_SPAN then
        l, r, top, bottom = 0, env.W, 0, 0
    end
    local applied = inst.appliedPingRect
    if not (applied and applied.l == l and applied.r == r
        and applied.top == top and applied.bottom == bottom) then
        rec:ClearAllPoints()
        rec:SetPoint("TOPLEFT", frame, "TOPLEFT", l, -top)
        rec:SetPoint("BOTTOMRIGHT", frame, "BOTTOMLEFT", r, bottom)
        inst.appliedPingRect = { l = l, r = r, top = top, bottom = bottom }
    end

    local nb = inst.pingNameBox
    if not nb then return end
    local nl, nr, nt, nbot = nameRowRect(inst, env)
    local an = inst.appliedPingName
    if an and an.l == nl and an.r == nr and an.t == nt and an.b == nbot then
        return
    end
    nb:ClearAllPoints()
    nb:SetPoint("TOPLEFT", frame, "TOPLEFT", nl, -nt)
    nb:SetPoint("BOTTOMRIGHT", frame, "TOPLEFT", nr, -nbot)
    inst.appliedPingName = { l = nl, r = nr, t = nt, b = nbot }
end

--- Creation-time wiring, idempotent so _ApplyAll can use it as a self-heal. The
--- whole receiver contract lives in this one function: if a plain frame ever
--- turns out not to be honoured by the hit test, the fallback is to point these
--- two writes at inst.clickButton (the shape two other addons ship) and accept
--- the envelope-sized ping area.
local function wirePingReceiver(inst)
    local rec = inst.pingReceiver
    if not rec then return end
    if not rec._pingWired then
        if inst.unit == "player" then
            Mixin(rec, UFZ_PLAYER_PING)
        elseif PingableType_UnitFrameMixin then
            Mixin(rec, PingableType_UnitFrameMixin)
        else
            return  -- no ping system on this client; retry on the next _ApplyAll
        end
        rec:SetAttribute("ping-receiver", true)
        rec._pingWired = true
    end
    -- Re-asserted rather than set once at wire time: ensureFrame wires the
    -- receiver before it builds the proxy, and _ApplyAll heals both.
    rec._pingNameBox = inst.pingNameBox
    -- The attribute, never a field. Unprotected frame, so the write is legal in
    -- combat and needs no queue.
    if rec:GetAttribute("unit") ~= inst.unit then
        rec:SetAttribute("unit", inst.unit)
    end
end

--------------------------------------------------------------------------------
-- Combat-deferred work
--------------------------------------------------------------------------------
-- The secure click button is anchored to the outer frame (SetAllPoints), which
-- makes the frame ANCHOR-PROTECTED: in combat, insecure code cannot resize,
-- move, or rescale it. Its VISIBILITY is protected too -- hiding the parent
-- would hide the protected child, so Show/Hide from insecure code is blocked
-- in lockdown just like geometry (first combat target-drop proved it:
-- ADDON_ACTION_BLOCKED on ScootUnitFrameZTarget:Hide()). In-combat show/hide
-- on unit existence is therefore delegated to Blizzard's secure unit watch
-- (applyUnitWatch below); Scoot's own Show/Hide calls run OOC only. Every worker
-- that touches protected state queues itself here when it lands in lockdown
-- and pays on PLAYER_REGEN_ENABLED. Flags only, never values: the drain
-- re-runs the worker, which recomputes fresh.
local pendingRegen = {}
-- Populated beside each worker's definition; drained in this order so a
-- restored position lands before the resize that happens around it, the watch
-- settles before the visibility recheck that trusts it, and the Edit Mode
-- stand-in paints last, onto a frame that is finally shown.
local regenActions = {}
local REGEN_ORDER = {
    "position", "scale", "envelope", "stack",
    "click", "clickShown", "watch", "visibility", "preview",
}

local function drainInst(inst)
    local flags = pendingRegen[inst]
    if not flags then return end
    if InCombatLockdown() then
        -- Lockdown at drain time: re-queue for the next edge rather than run
        -- protected work now.
        addon.Events.RunOutOfCombat(function() drainInst(inst) end, inst)
        return
    end
    -- Cleared before the workers run so a worker's own re-queue starts a
    -- fresh flag set for the next cycle.
    pendingRegen[inst] = nil
    for _, name in ipairs(REGEN_ORDER) do
        if flags[name] and regenActions[name] then
            regenActions[name](inst)
        end
    end
end

local function queueRegen(inst, what)
    -- Callers that resolve an instance from a config key can legitimately come
    -- up empty (a frame not built yet). Nothing to defer, and pendingRegen[nil]
    -- would throw rather than no-op.
    if not inst then return end
    local flags = pendingRegen[inst]
    if not flags then
        flags = {}
        pendingRegen[inst] = flags
    end
    flags[what] = true
    -- Keyed on the instance table: repeat queues coalesce onto one drain,
    -- which pays this instance's flags out in REGEN_ORDER. Cross-instance
    -- order is first-queued; the old single watcher's pairs() walk gave no
    -- order at all.
    addon.Events.RunOutOfCombat(function() drainInst(inst) end, inst)
end
UFZ._QueueRegen = queueRegen

-- _RestorePosition lives in editmode.lua; _ApplyStack in stack.lua. Both are
-- resolved at drain time, so their load order behind this file does not matter.
regenActions.position = function(inst) UFZ._RestorePosition(inst) end
-- Drains after "envelope" because the stack's box is sized from the envelope
-- the frames just took.
regenActions.stack = function(inst) UFZ._ApplyStack(inst.unitKey) end

-- Resize the outer frame to the envelope and seat the numbers box inside it,
-- flush against the align edge, T below the top. Stateless recompute-and-set.
-- When a setting changes the extents, the frame resizes around whatever anchor
-- Edit Mode stored, so the content can shift slightly on screen until the
-- user re-drags. Accepted: an analytic keep-the-numbers-still
-- rebase existed briefly and was deleted as a layer of position-store-writing
-- logic a settings nudge does not justify.
--
-- The applied-envelope cache is what keeps combat quiet: the envelope is pure
-- config, so the digit-probe path (health events -> applyLayout) recomputes an
-- identical rect every time and skips out here without touching the protected
-- SetSize. Only a genuine config change in combat queues.
local function applyEnvelope(inst)
    local frame, box = inst.frame, inst.box
    if not frame or not box then return end

    local env = computeEnvelope(inst)
    local applied = inst.appliedEnv
    -- snug rides along in the compare even though it changes nothing the frame
    -- itself draws: stack.lua reads it off appliedEnv, so a stale one there
    -- would be a stale chain step.
    if applied and applied.W == env.W and applied.H == env.H
        and applied.T == env.T and applied.align == env.align
        and applied.snug == env.snug then
        -- The rect is unchanged, but the content inside it may not be: the ping
        -- receiver tracks the name's ink, which moves per subject.
        applyPingRect(inst)
        return
    end
    if InCombatLockdown() then
        queueRegen(inst, "envelope")
        return
    end
    frame:SetSize(env.W, env.H)
    box:ClearAllPoints()
    if env.align == "left" then
        box:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -env.T)
    else
        box:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -env.T)
    end
    inst.appliedEnv = env
    applyPingRect(inst)
    -- The rect just changed shape, and the stored position anchors the CONTENT
    -- inside it rather than the rect itself (editmode.lua), so the frame's own
    -- anchor has to be re-derived against the new envelope. Without this the
    -- growth is paid out of the name's position instead of the frame's edges:
    -- a vertically centred anchor point splits it, lifting the name and the
    -- number stack by half of it while the aura rows below drop by the other
    -- half. Stateless -- _RestorePosition recomputes
    -- from the store and the envelope above, so nothing is written back.
    --
    -- A stacked frame's new height also moves every frame below it and resizes
    -- the Edit Mode box around them; the box is what carries the position there,
    -- and it is not resized until _ApplyStack runs, so it re-anchors from inside
    -- that call instead. Only reached on a genuine change (the cache above
    -- absorbs the digit-probe path), and _ApplyStack skip-compares again.
    if inst.stackIndex then
        UFZ._ApplyStack(inst.unitKey)
    else
        UFZ._RestorePosition(inst)
    end
end
regenActions.envelope = applyEnvelope

-- The skull sits where the two numbers were: horizontally on the same column
-- the digits hang from, vertically on the NAME ROW's ink centerline.
--
-- The first bake seated it on the stack's bare gap-midline, -(pctRowH+gap/2),
-- reasoning that NAME_BASE_Y and cfg.nameY are a text compensator and a user
-- nudge that "mean nothing to a texture". Wrong twice over -- the skull read
-- visibly low against the name on Player and Target alike, both at nameY 0
-- First: the icon replaces the health readout, and
-- the thing the eye lines it up against is the name beside it, so the name's
-- seat is exactly what it has to inherit. Second: even that seat is the name
-- RECT's midline, and a rect is not its ink. Measured off a screenshot,
-- the two errors compound to ~10px of droop at the shipped
-- defaults, and nameInkMidY answers both at once:
--     NAME_BASE_Y + cfg.nameY      the name's own lift off the gap-midline
--     namePoint * descent / 2      the rect's dead descender space, which
--                                  seats the ink above the rect center
-- Still no user offset on this icon: it follows the name, and the name has the
-- sliders. Computed here rather than fed from applyLayout, so the name fit
-- can re-seat it when a long name lands at a smaller point size.
--
-- Size: 100% is HALF the stack it replaces. Filling the whole stack height was
-- the first bake (far too big in-game), so the slider's
-- 100% was rebased rather than its range re-centred -- a saved 100 keeps
-- meaning "the default", and the old look is still reachable at 200.
local DEAD_ICON_BASE = 0.5
local function layoutDeadIcon(inst)
    local tex = inst.deadTex
    if not tex then return end
    local box = inst.box or inst.frame
    if not box then return end
    local cfg = inst.cfg
    local stackH = pctGlyphCeiling(cfg) * ENV_LINE_H + cfg.gap + cfg.valSize * ENV_LINE_H
    local side = math.max(8, math.floor(stackH * DEAD_ICON_BASE * (cfg.deadIconScale or 100) / 100))
    tex:SetSize(side, side)
    tex:ClearAllPoints()
    local midY = nameInkMidY(inst)
    if cfg.center then
        -- Centered mode: the column's horizontal centre IS the box edge offset
        -- by dx, because the digit rows hang from a single centre-x point there.
        local edge, dx = "TOPRIGHT", -cfg.centerOffset
        if cfg.align == "left" then edge, dx = "TOPLEFT", cfg.centerOffset end
        tex:SetPoint("CENTER", box, edge, dx, midY)
    elseif cfg.align == "left" then
        tex:SetPoint("LEFT", box, "TOPLEFT", 0, midY)
    else
        tex:SetPoint("RIGHT", box, "TOPRIGHT", 0, midY)
    end
end

-- Deterministic anchors only. The live FontStrings hold secrets and are permanently
-- unmeasurable, so nothing here may derive from their rendered geometry.
local function applyLayout(inst)
    local frame = inst.frame
    if not frame then return end
    -- Envelope first: content anchors to the numbers box this seats.
    applyEnvelope(inst)
    local box = inst.box or frame
    local cfg = inst.cfg
    local pctFS, valFS, symbolFS, nameFS = inst.pctFS, inst.valFS, inst.symbolFS, inst.nameFS
    pctFS:ClearAllPoints()
    valFS:ClearAllPoints()
    symbolFS:ClearAllPoints()
    nameFS:ClearAllPoints()
    -- The name's wrap box: the display carries the same box the fit measures
    -- against, so wrapping happens exactly where the rulers said it would. The
    -- single-point LEFT/RIGHT anchors below pin the rect's edge-CENTER, so a
    -- two-line block centers vertically on the same gap-midline a one-line
    -- block does, and JustifyH keeps the ink hugging the numbers-facing edge --
    -- one-line renders are pixel-identical to the pre-wrap layout.
    nameFS:SetWidth(cfg.nameMaxWidth)
    if nameFS.SetMaxLines then pcall(nameFS.SetMaxLines, nameFS, cfg.nameMaxLines) end
    -- 0.85 em, not the 1.2 em line height: digits have no descenders, so most of
    -- a full line box is empty space below the baseline. Using cap-height-ish
    -- spacing tucks the value row up against the percent digits (the sandwiched
    -- look the UFZ spec wants). cfg.gap fine-tunes from there; negative is legal.
    -- With digit mode on the row reserves space for the LARGEST digit size, so a
    -- big one-digit rendering never overlaps the value row. Still static config --
    -- the reserve never moves per tick; the sandwich sits slightly looser
    -- under the small three-digit rendering.
    local pctRowH = pctRowHeight(cfg)
    -- The name centers on the GAP between the two number rows (the boundary at
    -- -pctRowH plus half the gap), not the whole stack's midline -- so neither
    -- the value row's size nor the digit count ever moves it. The name's near
    -- edge sits NAME_BASE_X + nameOffset px in from the same frame edge the
    -- numbers hang from, so the visual gap tracks the rendered number width
    -- (secret, never measured) rather than the arbitrary drag-box width; its
    -- RIGHT/LEFT point centers the line box on that midline, and NAME_BASE_Y +
    -- nameY nudges from there (+ = up, the optical compensator for descender
    -- space in the line box).
    local nameX = NAME_BASE_X + cfg.nameOffset
    local nameMidY = nameSeatY(cfg)
    if cfg.center then
        -- Shared centerline: single-point TOP anchors on natural-width FontStrings.
        -- The engine centers the rect on the point -- anchor resolution is engine-
        -- side, so the secret width never has to be read (same mechanism as the
        -- nametext probe ruler). Deliberately no SetWidth: a width would engage the
        -- truncation engine; a natural-width rect cannot truncate.
        pctFS:SetJustifyH("CENTER")
        valFS:SetJustifyH("CENTER")
        local edge, dx = "TOPRIGHT", -cfg.centerOffset
        if cfg.align == "left" then edge, dx = "TOPLEFT", cfg.centerOffset end
        -- The rows hug a shared boundary so the gap stays constant while digit
        -- mode changes the percent's size. The value row is top-aligned (fixed
        -- size, fixed TOP anchor); the percent is bottom-aligned, its BOTTOM
        -- anchor riding the boundary -- but the rect bottom is NOT the ink
        -- bottom: the font's descent whitespace under the digits scales with
        -- point size (0.28 px/pt for Anton Wide 1.5x), so the lift
        -- shifts the off-master digit modes to re-pin the INK instead. The old
        -- TOP anchor was worse still: the whole line-box delta moved the ink,
        -- not just the descent share.
        local lift = currentPctLift(inst)
        pctFS:SetPoint("BOTTOM", box, edge, dx, -pctRowH - lift)
        valFS:SetPoint("TOP", box, edge, dx, -(pctRowH + cfg.gap))
        -- Superscript '%': top-aligned off the digits' trailing edge. That edge
        -- is secret-width (same experiment left mode runs) -- anchor resolution
        -- is engine-side, so it renders without reading it.
        symbolFS:SetPoint("TOPLEFT", pctFS, "TOPRIGHT", cfg.symbolGap, 0)
        if cfg.align == "left" then
            nameFS:SetJustifyH("LEFT")
            nameFS:SetPoint("LEFT", box, "TOPLEFT", nameX, nameMidY)
        else
            nameFS:SetJustifyH("RIGHT")
            nameFS:SetPoint("RIGHT", box, "TOPRIGHT", -nameX, nameMidY)
        end
    elseif cfg.align == "left" then
        pctFS:SetJustifyH("LEFT")
        valFS:SetJustifyH("LEFT")
        pctFS:SetPoint("TOPLEFT", box, "TOPLEFT", 0, 0)
        valFS:SetPoint("TOPLEFT", box, "TOPLEFT", 0, -(pctRowH + cfg.gap))
        nameFS:SetJustifyH("LEFT")
        nameFS:SetPoint("LEFT", box, "TOPLEFT", nameX, nameMidY)
        -- EXPERIMENT: the digits' right edge is secret-width. Anchor resolution is
        -- engine-side, so this may render correctly anyway -- observe via 'report',
        -- do not "fix". Right mode below is the deterministic layout.
        symbolFS:SetPoint("TOPLEFT", pctFS, "TOPRIGHT", cfg.symbolGap, 0)
    else
        pctFS:SetJustifyH("RIGHT")
        valFS:SetJustifyH("RIGHT")
        if cfg.symbol then
            -- The '%' owns the rightmost slot at a fixed box anchor, top-aligned
            -- (superscript); the digits end flush against its left edge. No secret
            -- geometry involved.
            symbolFS:SetPoint("TOPRIGHT", box, "TOPRIGHT", 0, 0)
            pctFS:SetPoint("TOPRIGHT", symbolFS, "TOPLEFT", -cfg.symbolGap, 0)
        else
            pctFS:SetPoint("TOPRIGHT", box, "TOPRIGHT", 0, 0)
        end
        valFS:SetPoint("TOPRIGHT", box, "TOPRIGHT", 0, -(pctRowH + cfg.gap))
        nameFS:SetJustifyH("RIGHT")
        nameFS:SetPoint("RIGHT", box, "TOPRIGHT", -nameX, nameMidY)
    end
    symbolFS:SetShown(cfg.symbol and true or false)
    layoutDeadIcon(inst)
    applyPowerLayout(inst)
    anchorAbsorbFS(inst)
    -- Aura rows re-seat around the (possibly resized) envelope. Unboxed: they
    -- never feed applyEnvelope, they only read its result.
    if UFZ.Auras then UFZ.Auras.ApplyLayout(inst) end
    applyStretch(inst)
end

--------------------------------------------------------------------------------
-- Update
--------------------------------------------------------------------------------

local function applyColor(inst)
    local cfg = inst.cfg
    local pctFS, valFS, symbolFS = inst.pctFS, inst.valFS, inst.symbolFS
    if cfg.color == "white" then
        pcall(pctFS.SetTextColor, pctFS, 1, 1, 1, 1)
        pcall(valFS.SetTextColor, valFS, 1, 1, 1, 1)
        pcall(symbolFS.SetTextColor, symbolFS, 1, 1, 1, 1)
        inst.last.color = "white"
        return
    end
    local curve = ensureColorCurve(cfg.color)
    if not curve or not _G.UnitHealthPercent then
        inst.last.color = "curve unavailable"
        return
    end
    local ok, color = pcall(UnitHealthPercent, inst.unit, true, curve)
    if not ok or not color then
        inst.last.color = "eval failed"
        return
    end
    if type(color) == "number" or not color.GetRGB then
        inst.last.color = "not a color object"
        return
    end
    local r, g, b = color:GetRGB()
    pcall(pctFS.SetTextColor, pctFS, r, g, b, 1)
    pcall(valFS.SetTextColor, valFS, r, g, b, 1)
    pcall(symbolFS.SetTextColor, symbolFS, r, g, b, 1)
    inst.last.color = "curve (" .. cfg.color .. ")"
end

--------------------------------------------------------------------------------
-- The power texts: primary + alternate resource, flat values through the exact
-- value-row chain (UnitPower is only conditionally secret, but the chain never
-- needs it readable -- AbbreviateNumbers is secret-whitelisted); the one
-- exception is MANA on EITHER row, which renders as a percent via
-- UnitPowerPercent (user round 3 -- a flat mana pool number is
-- meaningless -- extended to the primary 2026-08-22, where a healer's mana
-- lives). Alternate
-- power IS UnitPower(unit, secondary type): Blizzard's readable global
-- GetUnitSecondaryPowerInfo maps class + primary type to the secondary bar
-- (DRUID/PRIEST/SHAMAN -> MANA, TRAVELER -> ENERGY); two plain returns
-- (powerType, powerName), nothing when the spec has none -- never a
-- hand-maintained spec list.
--------------------------------------------------------------------------------

-- The shared tail of the flat-value chains (power, absorb): pcall'd formatter
-- into pcall'd SetText, verdict into last[lastKey]. The caller has already
-- ClearText'd. getterName labels the verdict strings (default: the power
-- chain's getter). Returns true only when text landed -- the absorb
-- chain gates its box visibility on it.
local function paintPowerValue(inst, fs, lastKey, getterOk, value, getterName)
    getterName = getterName or "UnitPower"
    local last = inst.last
    if getterOk and type(value) == "number" then
        local okA, str
        if abbrevOpts and _G.AbbreviateNumbers then
            okA, str = pcall(AbbreviateNumbers, value, abbrevOpts)
        elseif _G.AbbreviateNumbers then
            -- Degraded: engine-default breakpoints, deliberately visible.
            okA, str = pcall(AbbreviateNumbers, value)
        end
        if okA and type(str) == "string" then
            local okS = pcall(fs.SetText, fs, str)
            if okS then
                last[lastKey] = abbrevOpts and "ok" or "ok (degraded: engine defaults)"
                return true
            else
                last[lastKey] = "SetText failed"
            end
        else
            last[lastKey] = okA and ("AbbreviateNumbers returned " .. type(str))
                or ("AbbreviateNumbers error: " .. tostring(str))
        end
    else
        last[lastKey] = getterOk and (getterName .. " returned " .. type(value))
            or (getterName .. " error: " .. tostring(value))
    end
    return false
end

-- Is the unit's CURRENT primary resource mana? UnitPowerType is readable (no
-- secret annotation) but MayReturnNothing, and mana is power type 0, so the
-- file's guard order applies in full: type -> issecretvalue -> compare.
local function primaryIsMana(unit)
    local ok, pt = pcall(UnitPowerType, unit)
    if not ok or type(pt) ~= "number" then return false end
    if issecretvalue and issecretvalue(pt) then return false end
    return pt == 0
end

-- The percent chain both power rows share. Same shape as the health percent
-- row: UnitPowerPercent is the documented power analog (secret-tolerant, takes
-- the shared 0->0/1->100 curve) and the C_StringUtil formatter honors
-- cfg.round. The '%' sign is its own half-size FontString (cfg.powerSymbol
-- toggles it), never part of the number's string. The caller has already
-- ClearText'd both; returns the verdict for last[lastKey].
local function paintPowerPercent(inst, fs, symFS, powerType)
    local cfg = inst.cfg
    local curve = ensurePctCurve()
    if not (curve and _G.UnitPowerPercent and _G.C_StringUtil) then
        return "percent API missing (C_CurveUtil / UnitPowerPercent / C_StringUtil)"
    end
    local okP, num = pcall(UnitPowerPercent, inst.unit, powerType, false, curve)
    if not okP or type(num) ~= "number" then
        return okP and ("UnitPowerPercent returned " .. type(num))
            or ("UnitPowerPercent error: " .. tostring(num))
    end
    local fmt = (cfg.round == "round") and C_StringUtil.RoundToNearestString
        or C_StringUtil.FloorToNearestString
    if not fmt then return "C_StringUtil formatter missing" end
    local okF, str = pcall(fmt, num)
    if not (okF and type(str) == "string") then
        return okF and ("formatter returned " .. type(str))
            or ("formatter error: " .. tostring(str))
    end
    if not pcall(fs.SetText, fs, str) then return "SetText failed" end
    if cfg.powerSymbol and symFS then
        pcall(symFS.SetText, symFS, "%")
    end
    return cfg.powerSymbol and "ok (mana %)" or "ok (mana %, sign off)"
end

local function updatePower(inst)
    local cfg, last = inst.cfg, inst.last
    if not abbrevBuildTried then rebuildAbbrevConfig() end

    -- Primary. ClearText first, always: a failed chain or a gate must show an
    -- empty row, and ClearText is the only call that releases the Text aspect.
    -- The '%' companion clears with it and is re-set only by a successful
    -- percent paint.
    if inst.powerFS.ClearText then inst.powerFS:ClearText() end
    if inst.powerSymbolFS and inst.powerSymbolFS.ClearText then inst.powerSymbolFS:ClearText() end
    local wasPrimaryPct = inst.powerIsPct
    inst.powerIsPct = false
    if not cfg.powerShow then
        last.power = "off"
    else
        -- Readable-zero gate: UnitPowerMax is readable for the player and many
        -- units, and a READABLE 0 means "no resource at all" (training dummies)
        -- -- blank the row instead of painting a dead 0. Secret or non-number:
        -- display anyway. Secrecy check BEFORE the comparison, always.
        local gated = false
        local okM, pmax = pcall(UnitPowerMax, inst.unit)
        if okM and type(pmax) == "number"
            and not (issecretvalue and issecretvalue(pmax)) and pmax == 0 then
            gated = true
            last.power = "max 0 (no resource)"
        end
        if not gated then
            if primaryIsMana(inst.unit) then
                -- A healer's own mana: the pool number says nothing at a
                -- glance, so the primary reads as a percent too (same rule the
                -- alternate row has followed since round 3).
                inst.powerIsPct = true
                last.power = paintPowerPercent(inst, inst.powerFS, inst.powerSymbolFS, 0)
            else
                local okP, pv = pcall(UnitPower, inst.unit)  -- no type arg = current primary
                paintPowerValue(inst, inst.powerFS, "power", okP, pv)
            end
        end
    end

    -- Alternate. Stays cleared when the spec has no secondary bar. The '%'
    -- companion clears with it and is re-set only by a successful percent
    -- paint; percent-ness re-anchors on change (the right-edge sign reserve).
    if inst.altPowerFS.ClearText then inst.altPowerFS:ClearText() end
    if inst.altPowerSymbolFS and inst.altPowerSymbolFS.ClearText then inst.altPowerSymbolFS:ClearText() end
    local wasPct = inst.altPowerIsPct
    inst.altPowerIsPct = false
    inst.altPowerName = nil
    if not cfg.altPowerShow then
        last.altPower = "off"
    elseif not _G.GetUnitSecondaryPowerInfo then
        last.altPower = "GetUnitSecondaryPowerInfo missing"
    else
        -- Two plain returns (powerType, powerName), NOT an info table; returns
        -- nothing when the class + primary-power pair has no secondary bar.
        local okI, altType, altName = pcall(GetUnitSecondaryPowerInfo, inst.unit)
        if not okI then
            last.altPower = "GetUnitSecondaryPowerInfo error: " .. tostring(altType)
        elseif type(altType) ~= "number" then
            last.altPower = "no alt bar"
        elseif altName == "MANA" then
            -- Alt mana reads as a PERCENT (user round 3): a flat mana pool
            -- number is meaningless at a glance.
            inst.altPowerName = altName   -- color cache for applyPowerColor
            inst.altPowerIsPct = true
            last.altPower = paintPowerPercent(inst, inst.altPowerFS, inst.altPowerSymbolFS, altType)
        else
            inst.altPowerName = altName   -- color cache for applyPowerColor
            local okP, pv = pcall(UnitPower, inst.unit, altType)
            paintPowerValue(inst, inst.altPowerFS, "altPower", okP, pv)
        end
    end

    -- Percent-ness flipped on either row (spec swap, shapeshift, unit change):
    -- the sign reserve baked into the right-justified anchors is stale --
    -- re-anchor once, both rows together.
    if inst.altPowerIsPct ~= wasPct or inst.powerIsPct ~= wasPrimaryPct then
        applyPowerLayout(inst)
    end
end

local function applyPowerColor(inst)
    local cfg = inst.cfg
    if cfg.powerColorMode == "custom" then
        pcall(inst.powerFS.SetTextColor, inst.powerFS,
            cfg.powerColorR, cfg.powerColorG, cfg.powerColorB, cfg.powerColorA)
        pcall(inst.powerSymbolFS.SetTextColor, inst.powerSymbolFS,
            cfg.powerColorR, cfg.powerColorG, cfg.powerColorB, cfg.powerColorA)
        inst.last.powerColor = "custom"
    else
        local r, g, b = addon.GetPowerColorRGB(inst.unit)
        local tag = "power"
        -- Mana gets the same +0.25 lighten the UFX classPower text mode uses --
        -- the bar blue is too dark for text. Re-resolved every pass through
        -- primaryIsMana, never cached (UnitPowerType MayReturnNothing).
        if primaryIsMana(inst.unit) then
            r, g, b = addon.LightenColor(r, g, b, 0.25)
            tag = "power (mana +0.25)"
        end
        pcall(inst.powerFS.SetTextColor, inst.powerFS, r, g, b, 1)
        pcall(inst.powerSymbolFS.SetTextColor, inst.powerSymbolFS, r, g, b, 1)
        inst.last.powerColor = tag
    end
    if cfg.altPowerColorMode == "custom" then
        pcall(inst.altPowerFS.SetTextColor, inst.altPowerFS,
            cfg.altPowerColorR, cfg.altPowerColorG, cfg.altPowerColorB, cfg.altPowerColorA)
        pcall(inst.altPowerSymbolFS.SetTextColor, inst.altPowerSymbolFS,
            cfg.altPowerColorR, cfg.altPowerColorG, cfg.altPowerColorB, cfg.altPowerColorA)
        inst.last.altPowerColor = "custom"
    else
        local token = inst.altPowerName or "MANA"
        local r, g, b = addon.GetPowerColorRGB(token)
        local tag = "power (" .. tostring(token) .. ")"
        if token == "MANA" then
            r, g, b = addon.LightenColor(r, g, b, 0.25)
            tag = tag .. " +0.25"
        end
        pcall(inst.altPowerFS.SetTextColor, inst.altPowerFS, r, g, b, 1)
        pcall(inst.altPowerSymbolFS.SetTextColor, inst.altPowerSymbolFS, r, g, b, 1)
        inst.last.altPowerColor = tag
    end
end

--------------------------------------------------------------------------------
-- The zero launder. C_StringUtil.TruncateWhenZero is AllowedWhenTainted and
-- returns blank for a zero amount -- secret or not. Poured through a scratch
-- FontString, GetText() then comes back PLAIN nil for the blank; a non-zero
-- amount comes back as a string (possibly secret). That nil is the one bit of
-- a secret number this addon can legally observe -- emptiness has nothing to
-- keep secret -- and it is exactly the bit hide-at-zero needs. The technique
-- is established across the ecosystem, and traces back to Blizzard's own
-- legacy health-deficit text. Its rules, honored below: never == on the
-- GetText result (comparing a secret string throws), truthiness/nil test only;
-- and a secret-tainted empty string compared to "" also throws, which is why
-- the FontString round-trip exists at all.
--------------------------------------------------------------------------------

local zeroScratchFS = nil

local function ensureZeroScratch()
    if zeroScratchFS then return zeroScratchFS end
    -- Hidden is fine here: GetText reports the assigned string, not layout
    -- (unlike the SetAlphaGradient oracle, whose ruler must stay shown).
    local holder = CreateFrame("Frame", nil, UIParent)
    holder:SetSize(1, 1)
    holder:SetPoint("CENTER", UIParent, "CENTER", 0, -340)
    holder:Hide()
    zeroScratchFS = holder:CreateFontString(nil, "BACKGROUND")
    zeroScratchFS:SetPoint("CENTER", holder, "CENTER", 0, 0)
    -- A font MUST be set before any SetText on a template-less FontString.
    zeroScratchFS:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
    return zeroScratchFS
end

-- true = provably zero, false = provably non-zero, nil = route unavailable
-- (callers fail open and show). The == comparisons run only on values
-- issecretvalue has cleared as plain (guard ordering rule).
local function isZeroAmount(v)
    if not (_G.C_StringUtil and C_StringUtil.TruncateWhenZero) then return nil end
    local okT, trunc = pcall(C_StringUtil.TruncateWhenZero, v)
    if not okT then return nil end
    if not (issecretvalue and issecretvalue(trunc)) then
        return (trunc == nil or trunc == "") and true or false
    end
    local scratch = ensureZeroScratch()
    -- ClearText, not SetText(""): only ClearText releases the Text aspect
    -- (the fonts.lua ruler rule), keeping the scratch reusable forever.
    if scratch.ClearText then scratch:ClearText() end
    if not pcall(scratch.SetText, scratch, trunc) then return nil end
    local okG, text = pcall(scratch.GetText, scratch)
    if not okG then return nil end
    -- Truthiness only; the pcall is the parachute in case a future build walls
    -- off boolean tests on secret strings too -- the gate then degrades to
    -- fail-open instead of erroring in the update path.
    local okB, blank = pcall(function() return not text end)
    if not okB then return nil end
    return blank and true or false
end

--------------------------------------------------------------------------------
-- The absorb shield text. UnitGetTotalAbsorbs is SecretReturns UNCONDITIONALLY
-- (the UnitHealth tier -- the 12.0.7 API docs; no SecretWhenUnit*
-- predicate exists for absorbs), so the display chain is the value row's
-- (AbbreviateNumbers is secret-whitelisted). Hide-at-zero is always on and
-- has two routes: a plain value compares directly; a secret one goes through
-- the zero launder above, so the text hides in either world. last.absorb
-- records the route per pass; probe P15-P17 carry the secrecy + launder
-- measurements.
--------------------------------------------------------------------------------

local function updateAbsorb(inst)
    local cfg, last = inst.cfg, inst.last
    local fs = inst.absorbFS
    -- ClearText first, always (the power chain's rule); the halo follows the
    -- text -- hidden until a paint verdict says there is something to light.
    if fs.ClearText then fs:ClearText() end
    setAbsorbGlowShown(inst, false)
    if not cfg.absorbShow then
        last.absorb = "off"
        return
    end
    if not _G.UnitGetTotalAbsorbs then
        last.absorb = "UnitGetTotalAbsorbs missing"
        return
    end
    if not abbrevBuildTried then rebuildAbbrevConfig() end
    local ok, v = pcall(UnitGetTotalAbsorbs, inst.unit)
    -- Guard ordering, always: type first, THEN secrecy, THEN compare.
    local plain = ok and type(v) == "number" and not (issecretvalue and issecretvalue(v))
    local suffix = plain and " (plain)" or " (secret)"
    if ok then
        if plain then
            if v == 0 then
                last.absorb = "zero (hidden, plain)"
                return
            end
        else
            local zero = isZeroAmount(v)
            if zero == true then
                last.absorb = "zero (hidden, laundered)"
                return
            end
            -- nil = launder unavailable -> fail open and say so.
            suffix = (zero == false) and " (secret, laundered non-zero)"
                or " (secret, launder n/a)"
        end
    end
    if paintPowerValue(inst, fs, "absorb", ok, v, "UnitGetTotalAbsorbs") then
        setAbsorbGlowShown(inst, true)
        last.absorb = last.absorb .. suffix
    end
end

--------------------------------------------------------------------------------
-- The level pair: "lvl <N>" from UnitEffectiveLevel (what Blizzard's own frames
-- display; UnitLevel differs only under level-scaling), the prefix on its own
-- 75%-size FontString (applyPowerLayout owns the pair's geometry; this chain
-- owns the text). The 12.0.7 docs carry no secrecy flags on either getter --
-- Blizzard's IsPlayerAtEffectiveMaxLevel does a raw >= on the return from
-- plain Lua -- so the compares below are legal; the secret branch is
-- belt-and-braces only. A target above the cap reads -1 ("too high to tell"),
-- which paints "lvl ??" -- unless hide-at-max is on: -1 means AT LEAST the
-- cap (bosses, skull mobs), so the toggle hides it too; it originally
-- painted regardless.
--------------------------------------------------------------------------------

-- The sanctioned max test: min(expansion cap for this account,
-- GetMaxPlayerLevel) -- handles Timerunning and capped accounts. Shared with
-- the Edit Mode stand-in, which has no unit to read and asks the same question
-- of the player instead.
local function effectiveMaxLevel()
    if _G.GameRulesUtil and GameRulesUtil.GetEffectiveMaxLevelForPlayer then
        local ok, m = pcall(GameRulesUtil.GetEffectiveMaxLevelForPlayer)
        if ok and type(m) == "number" then return m end
    elseif _G.GetMaxPlayerLevel then
        local ok, m = pcall(GetMaxPlayerLevel)
        if ok and type(m) == "number" then return m end
    end
    return nil
end

-- Returns true when it left text on screen; every blank exit falls through as
-- nil. updateLevel below turns that into the classification icon's step-aside.
local function paintLevel(inst)
    local cfg, last = inst.cfg, inst.last
    local fs, pre = inst.levelFS, inst.levelPrefixFS
    -- ClearText BOTH first, always: the prefix must never outlive the number
    -- (hidden-at-max, no-unit, a failed chain).
    if fs.ClearText then fs:ClearText() end
    if pre and pre.ClearText then pre:ClearText() end
    local getter = _G.UnitEffectiveLevel or _G.UnitLevel
    if not getter then
        last.level = "level API missing"
        return
    end
    local ok, lvl = pcall(getter, inst.unit)
    if not ok then
        last.level = "error: " .. tostring(lvl)
        return
    end
    -- Guard ordering, always: type first, THEN secrecy, THEN compare.
    if type(lvl) ~= "number" then
        last.level = "returned " .. type(lvl)
        return
    end
    if issecretvalue and issecretvalue(lvl) then
        -- Concatenation launders a secret number into a legal secret string;
        -- skip every compare.
        pcall(fs.SetText, fs, "" .. lvl)
        if pre then pcall(pre.SetText, pre, "lvl") end
        last.level = "ok (secret)"
        return true
    end
    if lvl <= 0 then
        if cfg.levelHideMax then
            last.level = "above cap (hidden)"
            return
        end
        pcall(fs.SetText, fs, "??")
        if pre then pcall(pre.SetText, pre, "lvl") end
        last.level = "unknown (??)"
        return true
    end
    if cfg.levelHideMax then
        local effMax = effectiveMaxLevel()
        if effMax and lvl >= effMax then
            last.level = "max (hidden)"
            return
        end
    end
    pcall(fs.SetText, fs, string.format("%d", lvl))
    if pre then pcall(pre.SetText, pre, "lvl") end
    last.level = "ok"
    return true
end

-- The Edit Mode stand-in's level, and the reason it is not just a sample
-- string: hide-at-max has to hold in the preview too, or the user is placing a
-- frame whose settings are not the ones they set.
--
-- paintLevel asks the SUBJECT's level, and the stand-in has no subject. The
-- player is the honest stand-in for one, in both directions: a boss never
-- outlevels you, so "the player is capped" is exactly when a boss level stops
-- carrying information -- and when it is NOT hidden, the player's own level is
-- what a scaled encounter would put on the frame anyway. (Target's stand-in
-- takes the same answer; a level worth reading is one below yours, and the
-- toggle is off by default.)
--
-- Returns paintLevel's verdict -- true when it left text on screen -- so the
-- caller can drive the same classification step-aside.
local function previewLevel(inst)
    local fs, pre = inst.levelFS, inst.levelPrefixFS
    if fs.ClearText then fs:ClearText() end
    if pre and pre.ClearText then pre:ClearText() end

    local lvl
    local getter = _G.UnitEffectiveLevel or _G.UnitLevel
    if getter then
        local ok, v = pcall(getter, "player")
        -- Guard ordering, always: type, then secrecy, then compare.
        if ok and type(v) == "number"
            and not (issecretvalue and issecretvalue(v)) and v > 0 then
            lvl = v
        end
    end

    if inst.cfg.levelHideMax and lvl then
        local effMax = effectiveMaxLevel()
        if effMax and lvl >= effMax then return end
    end
    -- Unreadable player level: fail open on the sample, the way paintLevel
    -- fails open on a secret one. A blank preview is the worse lie -- it looks
    -- like a setting rather than a missing measurement.
    pcall(fs.SetText, fs, string.format("%d", lvl or 80))
    if pre then pcall(pre.SetText, pre, "lvl") end
    return true
end

-- The classification icon only steps aside while the level is on
-- screen, so a blank level (hide-at-max is the common one) hands the corner
-- back. Re-anchored on the FLIP only: this runs on every level and target
-- event, and the anchor is unchanged in between.
--
-- The stand-in owns the level while it is up, the updateClassification
-- precedent: every live setter routes its repaint through here, and against a
-- unit that is not there paintLevel would answer "??" (or nothing) and blank
-- the stand-in the moment the user touched a setting. previewStandIn, not
-- previewActive -- previewing a frame that DOES have a unit keeps the live
-- paint, which is the more accurate preview of the two.
local function updateLevel(inst)
    local paint = inst.previewStandIn and previewLevel or paintLevel
    local painted = paint(inst) and true or false
    if inst.levelPainted ~= painted then
        inst.levelPainted = painted
        anchorClassify(inst)
    end
end

-- The elite/rare adornment. Blizzard draws this as a dragon wrapped around the
-- portrait; UFZ has neither portrait nor frame art, so it becomes a satellite
-- glyph on the same location system as the level and power texts.
--
-- The player is a hard early-out: UnitClassification("player") is "normal"
-- anyway, and the settings page hides the section, so this is belt-and-braces.
local function updateClassification(inst)
    local cfg, tex = inst.cfg, inst.classifyTex
    if not tex then return end
    local last = inst.last
    -- Edit Mode owns the texture while previewing (a positionable adornment
    -- must be visible while it is being positioned); do not fight it.
    if inst.previewActive then return end
    if not cfg.classifyShow or inst.unit == "player" then
        tex:Hide()
        inst.classifyAtlas = nil
        last.classify = "off"
        return
    end
    local ok, class = pcall(UnitClassification, inst.unit)
    if not ok then
        tex:Hide()
        inst.classifyAtlas = nil
        last.classify = "error: " .. tostring(class)
        return
    end
    -- Plain string in 12.0, so a direct table lookup is legal.
    local atlas = type(class) == "string" and CLASSIFICATION_ATLAS[class] or nil
    if not atlas or not atlasExists(atlas) then
        tex:Hide()
        inst.classifyAtlas = nil
        last.classify = atlas and ("atlas missing: " .. atlas)
            or ("none (" .. tostring(class) .. ")")
        return
    end
    -- Skip-compare: every target swap runs this, and SetAtlas is not free.
    if inst.classifyAtlas ~= atlas then
        pcall(tex.SetAtlas, tex, atlas)
        inst.classifyAtlas = atlas
    end
    tex:Show()
    last.classify = class
end

--------------------------------------------------------------------------------
-- The name row. Gradient start is the
-- class color darkened 25%, end is the hand-picked class endpoint lightened 10%
-- (the CastBar X treatment), applied per-character -- which needs readable text,
-- so a secret name renders raw in solid white (the documented fallback, not a
-- failure). Gradient eligibility gates on UnitIsPlayer, never on class-token
-- resolution: NPCs carry real class tokens. Readable NPC names get the neutral
-- white-to-grey placeholder ramp nametext.lua uses.
--
-- Sizing: the certified blind fit (core/blindfit.lua) picks the point size
-- asynchronously; refreshName launches it and the paint lands in onDone. The
-- fit measures the PLAIN string and the paint may apply the ramped one --
-- certified safe (widths byte-identical).
--
-- update() never touches this FontString: health ticks must not rebuild the
-- ramp or refit. Name refresh is event- and command-driven only.
--------------------------------------------------------------------------------

local NPC_RAMP_START = { 1, 1, 1 }
local NPC_RAMP_END   = { 0.62, 0.64, 0.68 }

-- The name's own face key, resolved identically in the three places that need
-- it: the blind fit's ruler, the greedy wrapper's ruler, and the ink
-- measurement. Derived rather than repeated so the three cannot drift onto
-- different fonts and disagree about where the name ends.
local function nameFaceKey(cfg)
    return (cfg.nameFace ~= "follow") and cfg.nameFace or cfg.face
end

-- The rendered ink's width: the one geometric fact the ink-true satellite
-- anchors need, because the name BOX is nameMaxWidth wide and a short name
-- leaves the far half of it empty air.
--
-- Measured SYNCHRONOUSLY on the shared ruler, from the string and the point
-- size -- never read back off the live name FontString. That is the round-5
-- correction for the alt power sitting way outside the
-- name. The old path read nameFS:GetWrappedWidth one deferred frame after the
-- paint, and a single deferred shot is wrong twice over:
--
--   * It cannot land before the paint it describes. Every far-side satellite
--     was therefore drawn at least one frame at the BOX edge and then seen to
--     snap onto the name -- on every target change, visibly.
--   * A shot that misses has nothing behind it. The read needs the FontString's
--     layout to have settled, the frame to have rendered once, and the seq to
--     still match; when any of that failed the guard wrote nil, anchorPowerFS
--     read that as "no measurement", and the satellite stayed parked at the box
--     edge for the whole life of that target. Nothing was scheduled to retry.
--
-- The ruler has neither failure mode. addon.MeasureTextWidth takes the string
-- and the size as ARGUMENTS, so no layout has to have settled and there is
-- nothing that can be stale -- it is the same primitive applyPowerLayout
-- already measures "lvl" and "%" with, and it answers before the name is
-- painted at all.
--
-- A name wider than the box wraps, and then the far edge is the widest LINE
-- rather than the whole string, so the greedy wrapper (applyNameText's own ramp
-- fallback, which already carries a per-line width) splits it and the widest
-- allowed line wins. A single unbreakable word has nowhere to break and
-- ellipsizes against the box instead, which fills it -- hence the box-width
-- answer, which is the truth in that case rather than a fallback.
--
-- Secret names stay unmeasurable in every form:
-- every width getter on a FontString holding one is secret, and the ruler
-- refuses the string outright rather than poisoning itself for every other
-- caller in the addon). nil, and the box-edge fallback stands -- documented,
-- not fixable blind.
local function measureNameInk(inst, name)
    local cfg = inst.cfg
    if not addon.MeasureTextWidth then return nil end
    local face = addon.ResolveFontFace(nameFaceKey(cfg))
    local size = currentNamePoint(inst)
    local w = addon.MeasureTextWidth(name, face, size, cfg.nameStyle)
    if type(w) ~= "number" or w <= 0 then return nil end
    if w <= cfg.nameMaxWidth then return w end
    local lines = addon.WrapTextGreedy and addon.WrapTextGreedy(name, {
        width = cfg.nameMaxWidth, face = face, size = size, style = cfg.nameStyle,
    })
    local widest = 0
    if lines then
        for i = 1, math.min(#lines, cfg.nameMaxLines) do
            local lw = lines[i].width
            if type(lw) == "number" and lw > widest then widest = lw end
        end
    end
    if widest <= 0 then return cfg.nameMaxWidth end
    return math.min(widest, cfg.nameMaxWidth)
end

-- Every name-relative satellite -- the two power texts and the '%' companion,
-- the level pair, the classification icon -- anchors to nameFS. All of them
-- move when a refit changes the name's point size or line count (the rect
-- centers on a fixed midline, so both its edges travel), and the far-side
-- locations move again with the ink width. None of that is known until the fit
-- lands.
--
-- So they ride the name's own hold. On a NEW subject refreshName blanks the
-- name until its fit lands, and a satellite left visible across that window is
-- drawn for those frames at the PREVIOUS subject's geometry and then seen to
-- correct itself -- the other half of the same problem, and the reason the
-- synchronous measurement above is not enough on its own. The whole name
-- row now appears at once instead.
--
-- Alpha, never Hide: Show/Hide on these belongs to updateClassification and
-- applyLayout, and a hold must not fight the state they own. Nothing else in
-- the file writes alpha on any of them (inst.symbolFS, which update() does
-- drive by alpha, is the health percent's '%', not the power rows' companions).
local function satelliteAlpha(inst, a)
    for _, region in ipairs({ inst.powerFS, inst.powerSymbolFS, inst.altPowerFS,
        inst.altPowerSymbolFS, inst.levelFS, inst.levelPrefixFS, inst.classifyTex }) do
        if region then region:SetAlpha(a) end
    end
end

-- The name and its satellites reveal TOGETHER, never separately: the satellites
-- are the name row, and a row that arrives in two pieces is the same visible
-- churn the hold exists to remove. The ramp path makes this concrete -- it
-- paints one frame and reveals the next, so a satellite revealed at placement
-- time would beat the name it is anchored to onto the screen. Every terminal
-- path in applyNameText, paintStandInName and refreshName ends here instead.
local function revealNameRow(inst)
    if inst.nameFS then inst.nameFS:SetAlpha(1) end
    satelliteAlpha(inst, 1)
end

-- Measurement and placement are one step, and both happen before the paint: no
-- frame exists in which a satellite is drawn at a stale anchor. The reveal is
-- deliberately NOT here -- it belongs with the name's own, above.
local function resolveNameInk(inst, name)
    inst.nameInkWidth = measureNameInk(inst, name)
    applyPowerLayout(inst)
    -- The name-side aura span reads the same measurement.
    if UFZ.Auras then UFZ.Auras.ApplyLayout(inst) end
    -- So does the ping receiver's content rect.
    applyPingRect(inst)
end

-- The paint path: text + color for an already-sized FontString, and the owner
-- of the reveal -- every terminal path ends at SetAlpha(1). ClearText before
-- every SetText (readable->secret unit switches need the Text aspect released),
-- and white first: |cff codes multiply against the text color.
--
-- The certified nametext display application in full (the old "no wrap
-- machinery" divergence was REVERSED). Ramp branches
-- are two-phase, exactly nametext's applyColor/applyRamp: paint the PLAIN
-- string in the ramp's solid start color at the final size, then one frame
-- later ask the engine where it broke the lines (DiscoverTextLines reads the
-- laid-out display; WrapTextGreedy is the off-frame fallback) and swap in the
-- per-line ramp with the breaks baked in as "\n". Wrap stays ON through the
-- swap: |cff codes shift kerning 1-2px (castbarX pitfall #28), so a boundary
-- line can come out fractionally wider than the plain text it was measured
-- from -- with wrap off that is a guaranteed "...", with wrap on a reflow at
-- worst.
--
-- seq is the caller's captured inst.nameFitSeq; the deferred swap bails when a
-- newer pass owns the box.
local function applyNameText(inst, name, seq)
    local cfg = inst.cfg
    local nameFS = inst.nameFS
    -- Before a single glyph of this name is drawn. One call covers every branch
    -- below, including the two that return early -- the old per-branch deferred
    -- measure was four call sites that had to stay in step.
    resolveNameInk(inst, name)
    if nameFS.ClearText then nameFS:ClearText() end
    pcall(nameFS.SetTextColor, nameFS, 1, 1, 1, 1)

    -- Custom mode: raw SetText plus a plain text color. No string ops, so a
    -- secret name renders identically to a readable one (the engine wraps both).
    if cfg.nameColorMode == "custom" then
        pcall(nameFS.SetTextColor, nameFS, cfg.nameColorR, cfg.nameColorG, cfg.nameColorB, cfg.nameColorA)
        pcall(nameFS.SetText, nameFS, name)
        inst.last.name = "custom color"
        revealNameRow(inst)
        return
    end

    local readable = type(name) == "string" and not (issecretvalue and issecretvalue(name))
    if not readable then
        -- Per-character ramps are permanently impossible on secret text. The
        -- engine still wraps it -- layout never needed to read the string.
        pcall(nameFS.SetText, nameFS, name)
        inst.last.name = "secret (solid white)"
        revealNameRow(inst)
        return
    end

    local isPlayer = inst.unit == "player"
    if not isPlayer then
        local okP, p = pcall(UnitIsPlayer, inst.unit)
        isPlayer = okP and not (issecretvalue and issecretvalue(p)) and p == true
    end

    local r1, g1, b1, r2, g2, b2
    if isPlayer then
        local token = addon.GetClassTokenForUnit(inst.unit)
        local cr, cg, cb = addon.GetClassColorRGB(token)
        if not (token and cr) then
            pcall(nameFS.SetText, nameFS, name)
            inst.last.name = "no class color (solid white)"
            revealNameRow(inst)
            return
        end
        r1, g1, b1 = addon.DarkenColor(cr, cg, cb, 0.25)
        local ep = addon.CLASS_GRADIENT_ENDPOINTS and addon.CLASS_GRADIENT_ENDPOINTS[token]
        if ep then
            r2, g2, b2 = addon.LightenColor(ep[1], ep[2], ep[3], 0.10)
        else
            r2, g2, b2 = addon.LightenColor(cr, cg, cb, 0.45)
        end
        inst.last.name = "class ramp (" .. tostring(token) .. ")"
    else
        r1, g1, b1 = NPC_RAMP_START[1], NPC_RAMP_START[2], NPC_RAMP_START[3]
        r2, g2, b2 = NPC_RAMP_END[1], NPC_RAMP_END[2], NPC_RAMP_END[3]
        inst.last.name = "NPC ramp"
    end

    -- Phase 1: the plain string in the solid start color -- the layout the line
    -- discovery reads one frame from now, and the documented fallback color if
    -- the ramp cannot be built. No reveal yet: revealing the solid first would
    -- make a blanked name appear and then change color a frame later (a hold
    -- shows one solid frame instead -- nametext-identical).
    pcall(nameFS.SetTextColor, nameFS, r1, g1, b1, 1)
    pcall(nameFS.SetText, nameFS, name)

    C_Timer.After(0, function()
        if seq ~= inst.nameFitSeq then return end          -- a newer pass owns the box
        local lines = addon.DiscoverTextLines and addon.DiscoverTextLines(nameFS, name)
        local route = lines and "span"
        if not lines and addon.WrapTextGreedy then
            lines = addon.WrapTextGreedy(name, {
                width = cfg.nameMaxWidth,
                face  = addon.ResolveFontFace(nameFaceKey(cfg)),
                size  = currentNamePoint(inst),
                style = cfg.nameStyle,
            })
            route = lines and "greedy"
        end
        local ramped = lines and addon.BuildPerLineRampString
            and addon.BuildPerLineRampString(lines, r1, g1, b1, r2, g2, b2, { mode = "line" })
        if ramped then
            pcall(nameFS.SetTextColor, nameFS, 1, 1, 1, 1)
            if nameFS.ClearText then nameFS:ClearText() end
            pcall(nameFS.SetText, nameFS, ramped)
            inst.last.name = tostring(inst.last.name)
                .. string.format("  [%d line(s), %s]", #lines, route)
        else
            -- The solid start color stays up -- a fallback, not a failure.
            inst.last.name = tostring(inst.last.name) .. "  [solid fallback: no line discovery]"
        end
        revealNameRow(inst)
    end)
end

-- The Edit Mode stand-in's name -- the frame's whole handle while it is up, so
-- it is worth as much care as the live one. Painted straight onto the
-- FontString because there is no unit: the blind fit and the class ramp both
-- need a subject. The two side jobs refreshName does AROUND them still have to
-- happen, or the preview is not the frame:
--
-- One, the fit's cached point size belongs to whatever unit was last here, and
-- a short stand-in belongs at the full nameSize. The seq bump goes with it, so
-- an in-flight fit for that unit cannot land on top of this.
--
-- Two, and the one the eye catches: every FAR-side satellite -- the level pair,
-- the classification icon, the alt power -- anchors to the name's last letter,
-- and only a measurement knows where that is. Without one they fall back to the
-- name BOX edge (nameMaxWidth from the justified side) and float out past the
-- end of a short stand-in. resolveNameInk places them; frameKey is plain text,
-- so the ruler always answers here.
local function paintStandInName(inst)
    local nameFS = inst.nameFS
    if not nameFS then return end
    inst.nameFitSeq = inst.nameFitSeq + 1
    if inst.nameFitSize then
        inst.nameFitSize = nil
        applyFonts(inst)
    end
    if nameFS.ClearText then nameFS:ClearText() end
    pcall(nameFS.SetTextColor, nameFS, 1, 1, 1, 1)
    -- frameKey, not unitKey: five boss stand-ins all reading "Boss" would give
    -- the user no way to tell which slot they are placing.
    pcall(nameFS.SetText, nameFS, inst.frameKey)
    revealNameRow(inst)
    inst.last.name = "edit mode stand-in"
    resolveNameInk(inst, inst.frameKey)
end

-- hold: nil/true = keep the current picture up until the new one is ready
-- (same subject re-measured); false = new subject, blank the name AND its
-- satellites until the fit lands (never draw at a stale size, and never at a
-- stale place). The blank is ALPHA, not ClearText -- a hold must not destroy
-- the picture it is holding, and ClearText would release the Text aspect
-- mid-hold. Every terminal path ends at alpha 1: the no-unit paths below, the
-- painted paths inside applyNameText via resolveNameInk.
local function refreshName(inst, hold)
    local cfg = inst.cfg
    local nameFS = inst.nameFS
    if not nameFS then return end

    -- The stand-in owns the name while it is up, the updateLevel precedent.
    -- Without this, every setter that refreshes the name (size, face, fit,
    -- width, lines...) would take the no-unit path and blank the frame's whole
    -- handle mid-preview -- the one thing the stand-in exists to prevent.
    if inst.previewStandIn then
        paintStandInName(inst)
        return
    end

    -- Unconditional: any in-flight fit is for a subject this call replaces --
    -- including the no-unit path, which launches no new fit and is exactly the
    -- case the fit module's per-pool supersession cannot cover.
    inst.nameFitSeq = inst.nameFitSeq + 1
    local seq = inst.nameFitSeq

    local okEx, ex = pcall(UnitExists, inst.unit)
    local exSecret = okEx and issecretvalue and issecretvalue(ex)
    if not okEx or (not exSecret and ex == false) then
        if nameFS.ClearText then nameFS:ClearText() end
        pcall(nameFS.SetTextColor, nameFS, 1, 1, 1, 1)
        inst.last.name = "no unit"
        inst.nameInkWidth = nil
        applyPowerLayout(inst)
        revealNameRow(inst)   -- also drops a hold left by the pass this replaces
        return
    end

    local okN, name = pcall(UnitName, inst.unit)
    if not okN or type(name) == "nil" then
        if nameFS.ClearText then nameFS:ClearText() end
        pcall(nameFS.SetTextColor, nameFS, 1, 1, 1, 1)
        inst.last.name = "no name"
        inst.nameInkWidth = nil
        applyPowerLayout(inst)
        revealNameRow(inst)   -- also drops a hold left by the pass this replaces
        return
    end

    if not cfg.nameFit or not addon.RunBlindFit then
        -- Fit off: the pre-fit synchronous path at the plain cfg.nameSize.
        -- applyNameText owns the reveal.
        if inst.nameFitSize then
            inst.nameFitSize = nil
            applyFonts(inst)
        end
        applyNameText(inst, name, seq)
        return
    end

    if hold == false then
        nameFS:SetAlpha(0)
        satelliteAlpha(inst, 0)
        -- The release rides a callback that is ALLOWED not to fire: RunBlindFit
        -- abandons a superseded same-pool pass silently. A
        -- superseding pass bumps the seq and owns its own release, so this only
        -- fires when nothing did -- and it drops the hold rather than leaving a
        -- satellite invisible, which would be a worse failure than a misplaced
        -- one. A fit that landed normally leaves the seq alone and re-asserts an
        -- alpha already at 1; idempotent either way.
        C_Timer.After(1, function()
            if inst.nameFitSeq == seq then satelliteAlpha(inst, 1) end
        end)
    end

    addon.RunBlindFit(name, {
        poolKey  = inst.poolKey,
        face     = nameFaceKey(cfg),
        style    = cfg.nameStyle,
        width    = cfg.nameMaxWidth,
        height   = 200,   -- generous: nameMaxLines is what governs the budget
        maxLines = cfg.nameMaxLines,
        minSize  = cfg.nameMinSize,
        maxSize  = cfg.nameSize,
        margin   = "auto",
    }, function(st)
        if seq ~= inst.nameFitSeq then return end              -- superseded
        if not inst.frame or not inst.frame:IsShown() then return end
        local applied, verdict
        if st.size then
            applied, verdict = st.size, string.format("[fit %s@%d]", st.tier, st.size)
        elseif st.F and st.spaces then
            -- Overflow: nothing in range fits the box. Render at the floor and
            -- let the display box ellipsize at the last line -- the honest
            -- nametext overflow.
            applied, verdict = st.lo, string.format("[fit overflow@%d]", st.lo)
        else
            -- Oracle failed: the pre-fit fixed behavior, diagnosable via report.
            applied, verdict = cfg.nameSize, "[fit FALLBACK: " .. tostring(st.reason) .. "]"
        end
        inst.nameFitSize, inst.lastNameFit = applied, st
        applyFonts(inst)
        -- The skull seats on the name's INK midline, which closes back toward
        -- the rect center as the fit shrinks the point size. Re-seat here
        -- rather than re-running applyLayout: this is two calls on a Scoot-owned
        -- texture, against a full relayout that restarts the stretch animations.
        layoutDeadIcon(inst)
        -- The certified belt-and-braces from nametext: re-assert the wrap state
        -- alongside the size before the paint (cheap, idempotent).
        pcall(nameFS.SetWordWrap, nameFS, true)
        if nameFS.SetNonSpaceWrap then pcall(nameFS.SetNonSpaceWrap, nameFS, false) end
        if nameFS.SetMaxLines then pcall(nameFS.SetMaxLines, nameFS, cfg.nameMaxLines) end
        -- Paint the SAME string the fit measured -- never re-read the unit
        -- here. applyNameText owns the reveal (ramp branches land it one frame
        -- later, after the per-line swap).
        applyNameText(inst, name, seq)
        inst.last.name = tostring(inst.last.name) .. "  " .. verdict
    end)
end

--------------------------------------------------------------------------------
-- Digit mode: the percent size follows the digit count
--------------------------------------------------------------------------------
-- SetAlphaGradient(start, length) -> isWithinText is the one FontString call that
-- reports something about a secret string's content without going secret itself.
-- Measured semantics (nametext.lua, "The oracle"): 0-based and inclusive, counts
-- UTF-8 characters, a free-standing FontString gives the true string length, and a
-- read in the same frame as a layout-dirtying write is SATURATED -- true at every
-- index. The percent is 1-3 characters, so three linear probes replace nametext's
-- bisection, and an index-3 true is the saturation tell rather than a count.
--
-- The probes run against a dedicated invisible ruler, never the live pctFS: a
-- gradient is render state, and a bailed probe would leave a visible alpha fade on
-- the number the user is looking at. The oracle is proven on secret NAMES; number-
-- derived secret strings are presumed identical -- 'digitprobe' is the gate.
--
-- Fully separate from the name fit: this ruler's font is set once and never
-- shared with core/blindfit.lua's pools.

-- true / false, or nil plus a tag describing why it was not a plain boolean.
local function alphaProbe(fs, start)
    if not fs or type(fs.SetAlphaGradient) ~= "function" then return nil, "noAPI" end
    local ok, within = pcall(fs.SetAlphaGradient, fs, start, 1)
    if not ok then return nil, "err" end
    if issecretvalue and issecretvalue(within) then return nil, "SECRET" end
    if within == true or within == false then return within end
    return nil, "nonbool(" .. type(within) .. ")"
end

local function clearGradient(fs)
    if fs and type(fs.ClearAlphaGradient) == "function" then
        pcall(fs.ClearAlphaGradient, fs)
    end
end

-- count (1-3), or nil plus a verdict tag. Clears the gradient on every exit.
local function readDigitCount(inst)
    local rulerFS = inst.rulerFS
    local v0, tag = alphaProbe(rulerFS, 0)
    if tag then clearGradient(rulerFS); return nil, tag end
    if v0 == false then clearGradient(rulerFS); return nil, "empty" end
    local count = 1
    if alphaProbe(rulerFS, 1) == true then count = 2 end
    if count == 2 and alphaProbe(rulerFS, 2) == true then count = 3 end
    local over = alphaProbe(rulerFS, 3)
    clearGradient(rulerFS)
    -- True past the longest legitimate string ("100") is not a count, it is a
    -- dirty layout answering yes at every index.
    if over == true then return nil, "saturated" end
    return count
end

local function probeDigits(inst)
    local cfg = inst.cfg
    inst.probePending = false
    if not inst.frame or not inst.frame:IsShown() or not cfg.digits then return end
    local count, tag = readDigitCount(inst)
    if count then
        inst.probeRetries = 0
        inst.last.digits = string.format("count=%d -> size %d", count, cfg["digitSize" .. count])
        if count ~= inst.lastDigitCount then
            inst.lastDigitCount = count
            applyFonts(inst)
            -- With a descent lift in play the BOTTOM anchor tracks the point
            -- size, so re-anchor. At descent 0 the anchor is static -- skip the
            -- churn (applyLayout restarts the stretch animations).
            if cfg.descent > 0 then applyLayout(inst) end
        end
        return
    end
    if tag == "saturated" and inst.probeRetries < 3 then
        -- Unit events dispatch before timers within a frame, so a second health
        -- tick can rewrite the ruler after this probe was scheduled. Waiting for
        -- the next event instead of retrying would strand a stale size at exactly
        -- the quiet moments (heal-to-full ending combat).
        inst.probeRetries = inst.probeRetries + 1
        inst.probePending = true
        inst.last.digits = "saturated (retry " .. inst.probeRetries .. ")"
        C_Timer.After(0, inst.probeDigitsFn)
        return
    end
    inst.probeRetries = 0
    inst.last.digits = tag or "?"
end

-- Coalesced: one pending probe at a time; a retry chain in flight keeps its slot.
local function scheduleDigitProbe(inst)
    if inst.probePending or not inst.cfg.digits then return end
    inst.probePending = true
    inst.probeRetries = 0
    C_Timer.After(0, inst.probeDigitsFn)
end

-- Everything downstream of the health numbers. Factored out because the dead
-- branch skips the number chains but must still run all of it -- the skull
-- replaces the health readout, not the frame.
local function updateTail(inst)
    applyColor(inst)
    updatePower(inst)
    applyPowerColor(inst)
    updateAbsorb(inst)
    updateLevel(inst)
    updateClassification(inst)
end

local function update(inst)
    if not inst.frame or not inst.frame:IsShown() then return end
    local cfg = inst.cfg
    local last = inst.last
    local pctFS, valFS, symbolFS, rulerFS = inst.pctFS, inst.valFS, inst.symbolFS, inst.rulerFS

    -- "No unit" only when UnitExists comes back a readable false. Never boolean-test
    -- a possibly-secret return.
    local okEx, ex = pcall(UnitExists, inst.unit)
    local exSecret = okEx and issecretvalue and issecretvalue(ex)
    if not okEx or (not exSecret and ex == false) then
        -- Nothing renders without a unit -- no placeholder, and the '%' goes
        -- dark too. Alpha, not SetShown: applyLayout owns SetShown for
        -- cfg.symbol, so the two mechanisms compose instead of fighting.
        if pctFS.ClearText then pctFS:ClearText() end
        if valFS.ClearText then valFS:ClearText() end
        if inst.powerFS.ClearText then inst.powerFS:ClearText() end
        if inst.powerSymbolFS and inst.powerSymbolFS.ClearText then inst.powerSymbolFS:ClearText() end
        if inst.altPowerFS.ClearText then inst.altPowerFS:ClearText() end
        if inst.altPowerSymbolFS and inst.altPowerSymbolFS.ClearText then inst.altPowerSymbolFS:ClearText() end
        if inst.absorbFS and inst.absorbFS.ClearText then inst.absorbFS:ClearText() end
        setAbsorbGlowShown(inst, false)
        if inst.levelFS and inst.levelFS.ClearText then inst.levelFS:ClearText() end
        if inst.levelPrefixFS and inst.levelPrefixFS.ClearText then inst.levelPrefixFS:ClearText() end
        if UFZ.Auras then UFZ.Auras.HideAll(inst) end
        setDeadIconShown(inst, false)
        if inst.classifyTex and not inst.previewActive then inst.classifyTex:Hide() end
        symbolFS:SetAlpha(0)
        last.pct, last.val = "no unit", "no unit"
        last.power, last.altPower = "no unit", "no unit"
        last.absorb = "no unit"
        last.level = "no unit"
        return
    end
    symbolFS:SetAlpha(1)

    -- Dead / ghost: the skull REPLACES both numbers and the '%'. Two stacked
    -- zeros at two point sizes read as a rendering fault, not as death.
    -- UnitIsDeadOrGhost is a plain bool in 12.0 (no SecretReturns annotation),
    -- so this compares directly -- the pcall guards a missing API, not secrecy.
    -- Ghost is deliberately included: a ghost has health but is not alive.
    local okDead, isDead = pcall(UnitIsDeadOrGhost, inst.unit)
    local dead = okDead and isDead == true
    if not dead then
        setDeadIconShown(inst, false)
    else
        -- Texture BEFORE Show, always: the first death of a session is the one
        -- paint where the memo is cold, and showing an untextured region first
        -- flashes a white block.
        applyDeadIconTexture(inst)
        setDeadIconShown(inst, true)
        -- ClearText, not SetAlpha: it is the only call that releases the Text
        -- secret aspect (the no-unit branch precedent). The '%' uses alpha
        -- because applyLayout owns its SetShown.
        if pctFS.ClearText then pctFS:ClearText() end
        if valFS.ClearText then valFS:ClearText() end
        symbolFS:SetAlpha(0)
        last.pct, last.val = "dead", "dead"
        -- The digit ruler is deliberately NOT fed: the blank paths never touch
        -- it, so lastDigitCount simply holds until revival re-fires the probe.
        -- Power / absorb / level keep their normal behavior -- the scope of
        -- this replacement is the two health numbers.
        updateTail(inst)
        return
    end

    -- Percent. ClearText first: a failed chain must show an empty row, not last
    -- tick's stale number, and ClearText is the only call that releases the Text
    -- secret aspect.
    if pctFS.ClearText then pctFS:ClearText() end
    last.pct = "?"
    local pctStr = nil  -- the secret string, held only to feed the digit ruler
    local curve = ensurePctCurve()
    if curve and _G.UnitHealthPercent and _G.C_StringUtil then
        local ok, num = pcall(UnitHealthPercent, inst.unit, cfg.usePredicted, curve)
        if ok and type(num) == "number" then
            local fmt = (cfg.round == "round") and C_StringUtil.RoundToNearestString
                or C_StringUtil.FloorToNearestString
            if fmt then
                local ok2, str = pcall(fmt, num)
                if ok2 and type(str) == "string" then
                    local ok3 = pcall(pctFS.SetText, pctFS, str)
                    last.pct = ok3 and "ok" or "SetText failed"
                    if ok3 then pctStr = str end
                else
                    last.pct = ok2 and ("formatter returned " .. type(str))
                        or ("formatter error: " .. tostring(str))
                end
            else
                last.pct = "C_StringUtil formatter missing"
            end
        else
            last.pct = ok and ("UnitHealthPercent returned " .. type(num))
                or ("UnitHealthPercent error: " .. tostring(num))
        end
    else
        last.pct = "API missing (C_CurveUtil / UnitHealthPercent / C_StringUtil)"
    end

    -- Feed the digit ruler only from a successful chain. The blank no-unit path and
    -- the probe command never touch it, so nothing else can contaminate the count.
    if cfg.digits and pctStr and rulerFS then
        if rulerFS.ClearText then rulerFS:ClearText() end
        pcall(rulerFS.SetText, rulerFS, pctStr)
        scheduleDigitProbe(inst)
    end

    -- Value.
    if valFS.ClearText then valFS:ClearText() end
    last.val = "?"
    if not abbrevBuildTried then rebuildAbbrevConfig() end
    local okH, hp = pcall(UnitHealth, inst.unit)
    if okH and type(hp) == "number" then
        local okA, str
        if abbrevOpts and _G.AbbreviateNumbers then
            okA, str = pcall(AbbreviateNumbers, hp, abbrevOpts)
        elseif _G.AbbreviateNumbers then
            -- Degraded: engine-default breakpoints (uppercase K/M, different tiers).
            -- Deliberately visible so a broken config never looks correct.
            okA, str = pcall(AbbreviateNumbers, hp)
        end
        if okA and type(str) == "string" then
            local okS = pcall(valFS.SetText, valFS, str)
            if okS then
                last.val = abbrevOpts and "ok" or "ok (degraded: engine defaults)"
            else
                last.val = "SetText failed"
            end
        else
            last.val = okA and ("AbbreviateNumbers returned " .. type(str))
                or ("AbbreviateNumbers error: " .. tostring(str))
        end
    else
        last.val = okH and ("UnitHealth returned " .. type(hp))
            or ("UnitHealth error: " .. tostring(hp))
    end

    updateTail(inst)
end

--------------------------------------------------------------------------------
-- Frame
--------------------------------------------------------------------------------

local UNIT_EVENTS = {
    "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_HEAL_PREDICTION", "UNIT_NAME_UPDATE",
    "UNIT_POWER_UPDATE", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER",
    "UNIT_ABSORB_AMOUNT_CHANGED", "UNIT_LEVEL",
    -- The event Blizzard's own classification frame registers.
    "UNIT_CLASSIFICATION_CHANGED",
}

-- Re-registering a unit event replaces its unit filter, so a unit switch is a
-- plain re-register of the whole list. Registration is per-frame, so the two
-- instances never collide; both receive PLAYER_TARGET_CHANGED and self-filter.
local function registerUnitEvents(inst)
    if not inst.frame then return end
    for _, ev in ipairs(UNIT_EVENTS) do
        pcall(inst.frame.RegisterUnitEvent, inst.frame, ev, inst.unit)
    end
end

-- Whole-block scale (the shipped "Overall Scale"): every row is a child of the
-- one container frame and every layout number resolves in its coordinate space,
-- so a single SetScale scales the assembled block. The ruler lives outside on
-- purpose -- the oracle counts characters, not pixels. SetScale is geometry on
-- the anchor-protected frame, so it takes the same cache + regen-queue path as
-- the envelope.
local function applyScale(inst)
    if not inst.frame then return end
    local scale = inst.cfg.scale or 1
    if inst.appliedScale == scale then return end
    if InCombatLockdown() then
        queueRegen(inst, "scale")
        return
    end
    inst.frame:SetScale(scale)
    inst.appliedScale = scale
    -- The stack's anchor box carries the same scale, so it stays an exact fit
    -- around frames whose spacing is expressed in their own coordinate space.
    if inst.stackIndex then UFZ._ApplyStack(inst.unitKey) end
end
regenActions.scale = applyScale

-- Whole-frame conditional opacity, the UFX Visibility offering ported (strict
-- parity: Player-only -- a Target cfg carries no opacity keys and
-- resolves to full alpha). Priority: In Combat > With Target > Out of Combat,
-- the order every state-opacity site resolves (core/opacity.lua). SetAlpha is
-- unprotected, so unlike the geometry workers this applies live in combat, no
-- queue. 0 is honored -- deliberately not replicating X's silent 50-percent
-- floor on In Combat.
-- Only units that offer the With Target slider pay for the target probe.
local UFZ_OPACITY_OPTS = { probeTarget = "whenSet" }

local function applyOpacity(inst)
    local frame = inst.frame
    if not frame then return end
    -- Edit Mode must never offer a dimmed or invisible grab target.
    if inst.previewActive then
        frame:SetAlpha(1)
        if addon.FontPair then addon.FontPair.RefreshInheritedAlpha() end
        return
    end
    local alpha = addon.Opacity.Resolve(inst.cfg, addon.Opacity.Keys.InCombat, UFZ_OPACITY_OPTS)
    frame:SetAlpha(alpha)
    -- A Deep Shadow name copy tapers itself against the alpha it inherits, and
    -- the alpha above just moved. core/fontpair.lua coalesces the pass, so a
    -- whole party fading at once costs one walk.
    if addon.FontPair then addon.FontPair.RefreshInheritedAlpha() end
end

-- Anchors + attributes for the secure click overlay. Both are combat-blocked
-- on the protected button, so a call that lands in lockdown queues itself and
-- pays on PLAYER_REGEN_ENABLED (creation paths are OOC in practice; this
-- covers a reload straight into combat and a combat setUnit).
local function applyClickAttributes(inst)
    local click = inst.clickButton
    if not click then return end
    if InCombatLockdown() then
        queueRegen(inst, "click")
        return
    end
    -- Anchored here rather than at creation: SetAllPoints on the protected
    -- button is itself blocked in lockdown, so a frame born in combat pays
    -- anchors and attributes together on regen. Idempotent OOC.
    click:SetAllPoints(inst.frame)
    -- The Blizzard loader: AnyUp clicks, *type1 = target, unit attribute.
    if SecureUnitButton_OnLoad then
        SecureUnitButton_OnLoad(click, inst.unit)
    else
        click:RegisterForClicks("AnyUp")
        click:SetAttribute("*type1", "target")
        click:SetAttribute("unit", inst.unit)
    end
    -- togglemenu, not menu: the self-contained secure action Blizzard retains
    -- for addon frames (SecureTemplates.lua) -- it resolves the right menu per
    -- unit (SELF/TARGET/...) and opens it via UnitPopup_OpenMenu, no
    -- menu-function attribute needed.
    click:SetAttribute("*type2", "togglemenu")
    -- The Scoot overlay inherits the 12.0.7 regression that SmallFixes exists to
    -- undo: *type1 = "target" above is exactly the value SecureUnitButton_OnClick
    -- refuses to act on while a modifier is held. No-ops unless the user turned
    -- a modifier on.
    if addon.SmallFixes and addon.SmallFixes.ApplyModifierProxies then
        addon.SmallFixes.ApplyModifierProxies(click)
    end
end
regenActions.click = applyClickAttributes

--- The overlay yields the mouse to the LEM selection for exactly as long as Edit
--- Mode is open, and Hide/Show on the protected button is combat-blocked. Edit
--- Mode opens AND closes in combat (CanEnterEditMode, EditModeManager.lua:1636-1655,
--- has no lockdown check), so this queues like every other protected worker rather
--- than dropping the write: an exit that landed in combat used to leave the overlay
--- hidden, which kills click-to-target until the next _ApplyAll.
local function applyClickShown(inst)
    local click = inst.clickButton
    if not click then return end
    local want = not addon.EditMode.IsEditing()
    -- The receiver is plain, so it never has to wait: Edit Mode must not be able
    -- to fire a ping mid-drag even when the protected Hide below queues.
    if inst.pingReceiver then inst.pingReceiver:SetShown(want) end
    if click:IsShown() == want then return end
    if InCombatLockdown() then
        queueRegen(inst, "clickShown")
        return
    end
    click:SetShown(want)
end
regenActions.clickShown = applyClickShown
UFZ._ApplyClickOverlayShown = applyClickShown

--- Re-applies the modifier delegates on every live overlay. Called when a
--- Small Fixes toggle changes; combat-blocked writes ride the existing click
--- regen action rather than a second deferral of their own.
function UFZ._RefreshClickModifiers()
    for _, inst in pairs(UFZ._instances) do
        if inst.clickButton then
            if InCombatLockdown() then
                queueRegen(inst, "click")
            else
                applyClickAttributes(inst)
            end
        end
    end
end

-- Secure unit watch: Blizzard's SecureStateDriverManager shows/hides watched
-- frames on unit existence from its own secure context -- the one channel
-- that stays legal in combat for a frame whose visibility is protected by the
-- secure click child. The player unit always exists, so only target/focus
-- frames register; register/unregister writes attributes on the protected
-- manager frame, so this worker is OOC-only and queues like the others.
-- The watch also drops for the Edit Mode stand-in: a targetless preview
-- would otherwise be re-hidden by the manager's next scan.
local function applyUnitWatch(inst)
    local frame = inst.frame
    if not frame then return end
    local wantWatch = UFZ._IsUnitEnabled(inst.unitKey)
        and inst.unit ~= "player"
        and not inst.previewActive
    if InCombatLockdown() then
        -- Steady state needs nothing; only a real transition queues (every
        -- combat target change routes through here via _UpdateVisibility).
        if (not wantWatch) == (not inst.watchRegistered)
            and (not wantWatch or inst.watchUnit == inst.unit) then
            return
        end
        queueRegen(inst, "watch")
        return
    end
    if wantWatch then
        -- The manager resolves the unit via SecureButton_GetUnit on the
        -- watched frame itself; registration settles visibility synchronously.
        frame:SetAttribute("unit", inst.unit)
        RegisterUnitWatch(frame)
        inst.watchRegistered = true
        inst.watchUnit = inst.unit
    elseif inst.watchRegistered then
        UnregisterUnitWatch(frame)
        inst.watchRegistered = nil
        inst.watchUnit = nil
    end
end
regenActions.watch = applyUnitWatch

-- Scoot's own Show/Hide on the outer frame (enable/disable transitions, the
-- always-existing player unit): protected in lockdown by the click child, so
-- combat calls queue a fresh visibility pass for regen instead.
local function setShownSafe(inst, show)
    local frame = inst.frame
    if not frame then return end
    if frame:IsShown() == show then return end
    if InCombatLockdown() then
        queueRegen(inst, "visibility")
        return
    end
    if show then frame:Show() else frame:Hide() end
end
regenActions.visibility = function(inst) UFZ._UpdateVisibility(inst) end

local function ensureFrame(inst)
    if inst.frame then return inst.frame end
    local cfg = inst.cfg

    local frame = CreateFrame("Frame", inst.frameName, UIParent)
    inst.frame = frame
    frame:SetSize(cfg.width, cfg.height)
    -- A stand-in point only: _RestorePosition at the tail (and every LEM layout
    -- callback after it) replaces this with the per-layout stored position.
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, -180)
    -- MEDIUM, not HIGH: Blizzard's full-screen panes live inside MEDIUM and are
    -- only Raise()d within it, so anything above MEDIUM draws over an open
    -- talent pane forever (core/strata.lua carries the evidence and the level
    -- ladder). The level is explicit because a child of UIParent otherwise
    -- lands at 1, the floor of the band, under every other Scoot overlay.
    -- Both calls MUST stay above the SecureUnitButtonTemplate child created
    -- below -- once that child SetAllPoints the frame, it is protected.
    addon.Strata.ApplyHUD(frame, 10)
    -- The frame itself stays mouse-dead: Edit Mode dragging is the LibEditMode
    -- selection overlay's job (editmode.lua), and unit interactivity is the
    -- secure click overlay's below. Neither wants the insecure frame in the
    -- hit-test.
    frame:EnableMouse(false)

    -- The numbers box: the tuned cfg.width x cfg.height rect every content
    -- anchor in applyLayout targets. Invisible geometry -- the outer frame
    -- resizes around it to the full-content envelope (applyEnvelope), which is
    -- what Edit Mode, the click overlay, and snapped cast bars see.
    local box = CreateFrame("Frame", nil, frame)
    inst.box = box
    box:SetSize(cfg.width, cfg.height)
    box:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)

    -- Unit interactivity rides a secure overlay covering the whole envelope:
    -- click anywhere on the element to target, exactly like a Blizzard unit
    -- frame. Every click routes through SecureUnitButton_OnClick, which
    -- consults the user's click bindings FIRST -- a spell bound to right-click
    -- casts, and Open Menu fires on whichever button/modifier the user bound
    -- it to -- so no mouse button is hard-coded anywhere in Scoot. The
    -- template is protected; keeping it a CHILD of the insecure frame means
    -- visibility and geometry ride the parent implicitly, which stays legal in
    -- combat (the overlay doctrine, inverted). Hidden during Edit Mode so the
    -- LEM selection gets the mouse (editmode.lua).
    local click = CreateFrame("Button", inst.frameName .. "Click", frame, "SecureUnitButtonTemplate")
    inst.clickButton = click
    -- CLICK-ONLY: motion events pass straight through to whatever is underneath.
    --
    -- The overlay spans the whole config-derived envelope, which is a deliberate
    -- superset of the visible ink -- so it sits on top of a large rectangle of
    -- apparently-empty screen that users reasonably fill with other frames. As a
    -- Button it defaults to click+motion, and the motion half was silently eating
    -- every hover in that reserve: Blizzard's Cooldown Viewer icons (MEDIUM level
    -- 2, and motion-only themselves -- CooldownViewer.lua:350-351) lost their
    -- tooltips to this frame at level 11, as did anything else parked there.
    --
    -- Disabling motion costs nothing: SecureUnitButtonTemplate declares an
    -- OnClick and nothing else (SecureTemplates.xml:21-25), and Scoot never wired
    -- OnEnter/OnLeave here, so no tooltip or highlight is lost. Clicks are
    -- unaffected -- the two flags are independent, which is exactly how Blizzard
    -- runs the Cooldown Viewer in the opposite direction. Click-to-target still
    -- covers the entire envelope; only hover falls through.
    --
    -- Fixing this by frame level instead would not work: the level must stay high
    -- enough for the UFZ text to draw over a CDM icon (the sixth-pass decision),
    -- and drawing and hit-testing share the one number. Splitting click from
    -- motion is the only lever that separates them.
    click:SetMouseMotionEnabled(false)
    applyClickAttributes(inst)  -- anchors + attributes (queued if born in combat)

    -- Ping receiver: plain, mouse-dead, and seated on the visible content rather
    -- than on this overlay's envelope (the ping section above carries the whole
    -- rationale). The full-frame anchors here are a stand-in; applyPingRect
    -- replaces them as soon as an envelope has been applied.
    local ping = CreateFrame("Frame", inst.frameName .. "Ping", frame)
    inst.pingReceiver = ping
    ping:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    ping:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    -- The name row's plain stand-in, the player's radial-wheel carve-out. Never
    -- drawn, never mouse-enabled: its rect exists only so IsMouseOver has a plain
    -- region to answer about. A child of the receiver so it follows it into and
    -- out of Edit Mode, anchored to the outer frame so nothing secret is in its
    -- chain. nameRowRect replaces these stand-in anchors on the first apply.
    inst.pingNameBox = CreateFrame("Frame", nil, ping)
    inst.pingNameBox:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    inst.pingNameBox:SetSize(1, 1)
    wirePingReceiver(inst)

    -- No backdrop by design: the numbers are judged against the world behind
    -- them. Kept (hidden) for cfg.chrome, the harness's visualization aid --
    -- it paints the full envelope now, which is the more useful picture.
    inst.chromeBG = frame:CreateTexture(nil, "BACKGROUND")
    inst.chromeBG:SetAllPoints()
    inst.chromeBG:SetColorTexture(0, 0, 0, 0.55)
    inst.chromeBG:SetShown(cfg.chrome)

    inst.pctFS = frame:CreateFontString(nil, "OVERLAY")
    inst.valFS = frame:CreateFontString(nil, "OVERLAY")
    inst.symbolFS = frame:CreateFontString(nil, "OVERLAY")
    inst.nameFS = frame:CreateFontString(nil, "OVERLAY")
    inst.powerFS = frame:CreateFontString(nil, "OVERLAY")
    inst.powerSymbolFS = frame:CreateFontString(nil, "OVERLAY")
    inst.altPowerFS = frame:CreateFontString(nil, "OVERLAY")
    inst.altPowerSymbolFS = frame:CreateFontString(nil, "OVERLAY")
    -- The absorb text: fixed white (spec), set once -- applyColor never touches
    -- it. Natural width like the number rows (a SetWidth would engage the
    -- truncation engine, and the halo must track the true rect).
    inst.absorbFS = frame:CreateFontString(nil, "OVERLAY")
    inst.absorbFS:SetJustifyH("CENTER")
    inst.absorbFS:SetTextColor(1, 1, 1, 1)
    -- The halo: a soft white-gold glow carrying the
    -- number, echoing how the base UI paints absorbs. Blizzard's classic
    -- soft-edged gold ring file; its visible ring sits well inside the
    -- texture rect, hence the generous overreach constants. BACKGROUND
    -- sublevel 2 stacks it above the chromeBG (sublevel 0) and below the
    -- text; not masked -- the art is already soft. It rides the FontString's
    -- rect: anchor resolution is engine-side, so a secret number's width is
    -- never read (the symbolFS->pctFS precedent). Hidden until updateAbsorb's
    -- paint verdict shows it (a cleared FS collapses its rect, and an empty
    -- halo must never linger). Its anchors are size-dependent (ink-centering
    -- shift) and live in anchorAbsorbFS, which every init/setter path reaches
    -- via applyLayout.
    inst.absorbGlowTex = frame:CreateTexture(nil, "BACKGROUND", nil, 2)
    inst.absorbGlowTex:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    inst.absorbGlowTex:SetBlendMode("ADD")
    inst.absorbGlowTex:SetAlpha(ABSORB_GLOW_ALPHA)
    inst.absorbGlowTex:Hide()
    -- The level pair: baked light gray (spec), set once -- applyColor and
    -- applyPowerColor never touch either. Natural width (anchorPowerFS's
    -- contract); JustifyH is set per-location by the anchor worker. The "lvl"
    -- prefix is its own FontString at 75% size (the '%' companion precedent);
    -- applyPowerLayout hangs it off the number's leading edge and only
    -- updateLevel gives it text, so it vanishes with the number.
    inst.levelFS = frame:CreateFontString(nil, "OVERLAY")
    inst.levelFS:SetTextColor(0.8, 0.8, 0.8, 1)
    inst.levelPrefixFS = frame:CreateFontString(nil, "OVERLAY")
    inst.levelPrefixFS:SetTextColor(0.8, 0.8, 0.8, 1)

    -- The two adornment textures. OVERLAY sublevel 1 puts both above the number
    -- FontStrings (plain OVERLAY) -- the skull must cover the space the numbers
    -- vacated even if a paint races it. Neither is anchor-protected: they are
    -- children of the frame, not the frame, so Show/Hide/SetSize/SetAtlas on
    -- them all stay legal in combat and the adornment path needs no regen slot.
    inst.deadTex = frame:CreateTexture(nil, "OVERLAY", nil, 1)
    inst.deadTex:Hide()
    inst.classifyTex = frame:CreateTexture(nil, "OVERLAY", nil, 1)
    inst.classifyTex:Hide()

    -- The digit ruler: free-standing (single point => natural width), so the oracle
    -- reports the true string length; one fixed font set ONCE and never touched
    -- again -- the count is font-independent on an unconstrained FontString, and
    -- never re-fonting removes the main source of saturated reads. Alpha 0 but
    -- SHOWN: a hidden region may skip layout entirely, and a layout-sensitive
    -- oracle would then answer about nothing (the nametext probe-ruler finding).
    -- Per instance; both holders overlap at the same point, which is fine (alpha
    -- 0, mouse-dead, each FontString lays out independently).
    local rulerHolder = CreateFrame("Frame", nil, UIParent)
    rulerHolder:SetSize(1, 1)
    rulerHolder:SetPoint("CENTER", UIParent, "CENTER", 0, -320)
    rulerHolder:SetAlpha(0)
    inst.rulerFS = rulerHolder:CreateFontString(nil, "OVERLAY")
    inst.rulerFS:SetPoint("CENTER", rulerHolder, "CENTER", 0, 0)
    inst.rulerFS:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
    inst.rulerFS:SetWordWrap(false)
    -- Fonts before any SetText: a template-less FontString has no font object at all
    -- (same reason as nametext.lua and the measurement ruler).
    applyFonts(inst)
    inst.symbolFS:SetText("%")
    -- The certified nametext display settings: wrap ON (applyLayout bounds it
    -- with the fit box), no mid-word breaks. Ramped strings never rely on the
    -- engine's wrap decision -- applyNameText bakes the discovered breaks in as
    -- "\n"; wrap-on is the reflow safety net (nametext.lua "Word wrap stays ON").
    inst.nameFS:SetWordWrap(true)
    if inst.nameFS.SetNonSpaceWrap then pcall(inst.nameFS.SetNonSpaceWrap, inst.nameFS, false) end
    applyScale(inst)
    applyLayout(inst)
    refreshName(inst)

    registerUnitEvents(inst)
    frame:RegisterEvent("PLAYER_TARGET_CHANGED")
    frame:RegisterEvent("PLAYER_FOCUS_CHANGED")
    -- The alternate power bar appears/disappears with the spec (the secondary
    -- info is keyed off class + primary power type). Falls through the handler
    -- to update(inst), which re-resolves it.
    frame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    -- Level: PLAYER_LEVEL_CHANGED is the PlayerFrame-canonical event (UNIT_LEVEL
    -- is the target frames'; it is not what Blizzard trusts for the player), and
    -- PLAYER_MAX_LEVEL_UPDATE re-evaluates hide-at-max on cap changes. Both
    -- fall through the handler to update(inst).
    frame:RegisterEvent("PLAYER_LEVEL_CHANGED")
    frame:RegisterEvent("PLAYER_MAX_LEVEL_UPDATE")
    -- Death: UNIT_HEALTH covers the fall to zero, but the ghost->alive
    -- transition does not always move health, so the PlayerFrame-canonical trio
    -- is the reliable signal. Registered on both instances (they are cheap,
    -- non-unit events and the handler is a plain update).
    frame:RegisterEvent("PLAYER_DEAD")
    frame:RegisterEvent("PLAYER_ALIVE")
    frame:RegisterEvent("PLAYER_UNGHOST")
    -- Boss slots change occupant without changing existence: a phase transition
    -- or an add swap re-points boss3 at a different creature while the frame
    -- stays shown, and the unit watch -- which answers existence only -- sees
    -- nothing. This is Blizzard's own signal for it (BossTargetFrameMixin:OnLoad
    -- registers it, TargetFrame.lua) and Cast Bar Z's boss changeEvent. It is
    -- not a unit event and carries no argument to filter on, so each frame
    -- takes it plainly and the handler self-filters.
    frame:RegisterEvent("INSTANCE_ENCOUNTER_ENGAGE_UNIT")
    frame:SetScript("OnEvent", function(_, event)
        -- The Edit Mode stand-in paints static sample text; live data must not
        -- overwrite it mid-drag. Everything re-syncs on _EndEditModePreview.
        if inst.previewActive then return end
        -- inst.cfg, never a captured local: on a profile switch the instance is
        -- re-pointed at the new profile's table and this closure must follow.
        if event == "UNIT_NAME_UPDATE" then
            -- Late name arrival for the watched unit (RegisterUnitEvent filters
            -- to inst.unit). Name only; health has its own events. Same subject:
            -- hold the old picture while the refit runs.
            refreshName(inst, true)
            return
        end
        if event == "PLAYER_TARGET_CHANGED" and inst.unit ~= "target" then return end
        if event == "PLAYER_FOCUS_CHANGED" and inst.unit ~= "focus" then return end
        if event == "INSTANCE_ENCOUNTER_ENGAGE_UNIT" and not inst.stackIndex then return end
        if event == "PLAYER_TARGET_CHANGED" or event == "PLAYER_FOCUS_CHANGED"
            or event == "INSTANCE_ENCOUNTER_ENGAGE_UNIT" then
            -- The subject itself changed. Show/hide on existence is the secure
            -- unit watch's (combat-legal); this settles the watch and repaints
            -- a currently-shown frame. A frame the watch shows a beat later
            -- repaints via its OnShow hook instead.
            UFZ._UpdateVisibility(inst)
            -- New subject: blank the name until its fit lands.
            refreshName(inst, false)
            -- Force, not Refresh: a new subject can coincidentally reuse aura
            -- instance-ID values, and a dropped target must clear its rows.
            if UFZ.Auras then UFZ.Auras.ForceRefresh(inst) end
            return
        end
        update(inst)
    end)

    -- The secure unit watch shows this frame from Blizzard's manager when the
    -- watched unit appears (the only combat-legal channel). update() gates on
    -- IsShown, so the paint that _UpdateVisibility used to run "on the way to
    -- showing" must re-run here instead. Idempotent for Scoot's own OOC shows.
    frame:SetScript("OnShow", function()
        if inst.previewActive then return end
        update(inst)
        refreshName(inst, false)
        -- Force: the subject usually changed while hidden, and a new subject
        -- can coincidentally reuse aura instance-ID values.
        if UFZ.Auras then UFZ.Auras.ForceRefresh(inst) end
        applyOpacity(inst)
    end)

    -- CreateFrame returns a shown frame; start hidden -- _UpdateVisibility is
    -- the only shower. A frame born in combat cannot (visibility-protected by
    -- the click child); it stays put until the watch or the regen drain
    -- settles it, blank via update()'s no-unit paint at worst.
    if not InCombatLockdown() then frame:Hide() end

    -- Into Edit Mode at the moment of creation, so a unit enabled mid-session is
    -- draggable without a /reload. Registration restores the stored position
    -- when a layout is already loaded; the restore below covers a frame that
    -- was registered earlier (a stacked unit's box) and no-ops before the
    -- first layout callback.
    UFZ._RegisterFrameEditMode(inst)
    UFZ._RestorePosition(inst)

    return frame
end

-- A never-laid-out region cannot be trusted, so every mutator ensures the frame
-- exists before styling it. Visibility stays _UpdateVisibility's call alone --
-- the harness's force-show is the one behavior that did not survive promotion.
local function ensureApplied(inst)
    ensureFrame(inst)
    return inst.frame
end

--------------------------------------------------------------------------------
-- Commands (instance-bound implementations; the API table at the bottom
-- publishes them through UFZ.GetAPI(unitKey))
--------------------------------------------------------------------------------

-- Read-only snapshot of the current config, for the settings pages. cfg holds
-- plain values only, so nothing secret can leak through this.
local function getConfig(inst)
    local snapshot = {}
    for k, v in pairs(inst.cfg) do snapshot[k] = v end
    return snapshot
end

-- setUnit is gone. The unit token is structural now -- minted from
-- the frame row into inst.unit -- so there is nothing for a setter to write:
-- five boss frames read one config table and each needs its own token. It was
-- a harness relic with no caller outside the API table.

-- The applied-vs-requested check exists because both failure modes here are
-- silent: an unknown key makes ResolveFontFace fall back to the default face,
-- and SetFont on a file the client has not loaded fails inside a pcall. Either
-- way the harness would print success while rendering Friz Quadrata.
--
-- The read-back is deferred and then re-checked a frame later: GetFont reports
-- the OLD face for about a frame after SetFont touches a fresh file (the same
-- settling the nametext caseprobe hit), so a same-frame check fired a false
-- warning naming the previous font on every first switch to a new face.
local function verifyAppliedFace(inst, fs, wantedFn)
    fs = fs or inst.pctFS
    wantedFn = wantedFn or function() return addon.ResolveFontFace(inst.cfg.face) end
    local wanted = wantedFn()
    if type(wanted) ~= "string" then return end
    local function check(finalCheck)
        -- Stale guard: the player may have switched faces while this waited.
        if wantedFn() ~= wanted then return end
        local ok, applied = pcall(fs.GetFont, fs)
        if not ok or type(applied) ~= "string" then return end
        if issecretvalue and issecretvalue(applied) then return end
        local a = applied:lower():gsub("/", "\\")
        local r = wanted:lower():gsub("/", "\\")
        if a == r then return end
        if not finalCheck then
            C_Timer.After(0, function() check(true) end)
            return
        end
        addon:Print("Warning: the client did not load '" .. wanted .. "' (rendering '" .. applied .. "' instead). A brand-new font file requires a FULL client restart, not /reload.")
    end
    C_Timer.After(0, function() check(false) end)
end

local function setFont(inst, face)
    ensureApplied(inst)
    local cfg = inst.cfg
    if face and face ~= "" then cfg.face = face end
    local isPath = type(cfg.face) == "string" and cfg.face:find("[/\\]") ~= nil
    local isLSM = addon.IsLSMKey and addon.IsLSMKey(cfg.face)
    if not isPath and not isLSM and not addon.Fonts[cfg.face] then
        addon:Print("Warning: '" .. cfg.face .. "' is not in this session's font registry, so the resolver falls back to the default face. Registry changes need /reload; new font files need a full client restart.")
    end
    applyFonts(inst)
    applyLayout(inst)
    update(inst)
    refreshName(inst)
    verifyAppliedFace(inst)
end

-- One impl for all four style keys: an outline flag changes glyph metrics, so
-- the full worker list runs -- setFont's, minus the face verification.
local function setStyleImpl(inst, key, style)
    ensureApplied(inst)
    if style and style ~= "" then inst.cfg[key] = style end
    applyFonts(inst)
    applyLayout(inst)
    update(inst)
    refreshName(inst)
end

local function setPctSize(inst, n)
    ensureApplied(inst)
    local cfg = inst.cfg
    cfg.pctSize = math.max(1, math.floor(tonumber(n) or cfg.pctSize))
    applyFonts(inst)
    applyLayout(inst)
    update(inst)
    addon:Print("Percent size: " .. cfg.pctSize)
    if cfg.digits then
        addon:Print("Note: digit mode is on, so the rendered size comes from digitsize 1/2/3; pct sets row geometry and the digits-off fallback.")
    end
end

local function setValSize(inst, n)
    ensureApplied(inst)
    -- Half-point steps: whole-point jumps are too coarse near the width match.
    local v = tonumber(n) or inst.cfg.valSize
    inst.cfg.valSize = math.max(1, math.floor(v * 2 + 0.5) / 2)
    applyFonts(inst)
    applyLayout(inst)
    update(inst)
end

-- The resolved value face for read-back verification and the report.
local function resolveValFace(inst)
    return addon.ResolveFontFace(inst.cfg.valFace ~= "follow" and inst.cfg.valFace or inst.cfg.face)
end

local function setValFont(inst, face)
    ensureApplied(inst)
    local cfg = inst.cfg
    if not face or face == "" then
        addon:Print("UFZ setter usage: valfont <FACE|follow>   (current: " .. cfg.valFace .. ")")
        return
    end
    local lowered = tostring(face):lower()
    if lowered == "follow" or lowered == "off" or lowered == "reset" then
        cfg.valFace = "follow"
    else
        cfg.valFace = face
        local isPath = cfg.valFace:find("[/\\]") ~= nil
        local isLSM = addon.IsLSMKey and addon.IsLSMKey(cfg.valFace)
        if not isPath and not isLSM and not addon.Fonts[cfg.valFace] then
            addon:Print("Warning: '" .. cfg.valFace .. "' is not in this session's font registry, so the resolver falls back to the default face. Registry changes need /reload; new font files need a full client restart.")
        end
    end
    applyFonts(inst)
    verifyAppliedFace(inst, inst.valFS, function() return resolveValFace(inst) end)
    addon:Print("Value face: " .. cfg.valFace)
end

local function setDescent(inst, n)
    ensureApplied(inst)
    local r = tonumber(n)
    if not r then
        addon:Print(string.format("UFZ setter usage: descent <ratio>   (current: %.3f; per-point ink lift for off-master digit sizes -- the font's below-ink descent share)", inst.cfg.descent))
        return
    end
    inst.cfg.descent = math.max(0, math.min(1, r))
    applyLayout(inst)
    addon:Print(string.format("Descent ratio: %.3f -- the 2-digit master look is the anchor; nudge until the '100' gap matches it.", inst.cfg.descent))
end

local function setGap(inst, n)
    ensureApplied(inst)
    -- Fractional gaps are legal: under a fractional UI scale a 0.1 px anchor
    -- offset can land on a different physical pixel, so sub-px steps are the
    -- fine-tuning knob (snapped to 0.1 to keep the report readable).
    local v = tonumber(n) or inst.cfg.gap
    inst.cfg.gap = math.floor(v * 10 + 0.5) / 10
    applyLayout(inst)
    update(inst)
end

local function setCenter(inst, state)
    ensureApplied(inst)
    local cfg = inst.cfg
    state = tostring(state or ""):lower()
    if state ~= "on" and state ~= "off" then
        addon:Print("UFZ setter usage: center <on|off>")
        return
    end
    cfg.center = (state == "on")
    applyLayout(inst)
    update(inst)
    if cfg.center then
        addon:Print("Center: on (centerline " .. cfg.centerOffset .. "px in from the " .. cfg.align .. " edge; tune with centeroffset)")
    else
        addon:Print("Center: off (edge-justified)")
    end
end

local function setCenterOffset(inst, n)
    ensureApplied(inst)
    inst.cfg.centerOffset = math.floor(tonumber(n) or inst.cfg.centerOffset)
    applyLayout(inst)
    addon:Print("Center offset: " .. inst.cfg.centerOffset)
end

local function setDigits(inst, state)
    ensureApplied(inst)
    local cfg = inst.cfg
    state = tostring(state or ""):lower()
    if state ~= "on" and state ~= "off" then
        addon:Print("UFZ setter usage: digits <on|off>")
        return
    end
    cfg.digits = (state == "on")
    inst.lastDigitCount = nil
    applyFonts(inst)
    applyLayout(inst)
    update(inst)
    if cfg.digits then
        addon:Print(string.format("Digit mode: on (sizes %d/%d/%d for 1/2/3 digits; validate with digitprobe)",
            cfg.digitSize1, cfg.digitSize2, cfg.digitSize3))
    else
        addon:Print("Digit mode: off (static size " .. cfg.pctSize .. ")")
    end
end

local function setDigitSize(inst, which, size)
    ensureApplied(inst)
    local cfg = inst.cfg
    local n = tonumber(which)
    if n ~= 1 and n ~= 2 and n ~= 3 then
        addon:Print("UFZ setter usage: digitsize <1|2|3> <size>")
        return
    end
    local key = "digitSize" .. n
    cfg[key] = math.max(1, math.floor(tonumber(size) or cfg[key]))
    -- applyFonts so a change to the currently rendered count lands now; applyLayout
    -- because the row reserve tracks the largest digit size.
    applyFonts(inst)
    applyLayout(inst)
    addon:Print(string.format("Digit size %d: %d", n, cfg[key]))
end

-- One knob for the digit-size triple (the shipped "% Font Size"): the 2-digit
-- size is the master and the 1/3-digit sizes ride the tuned 38/32 and 26/32
-- ratios. Also feeds pctSize (the digits-off fallback and applyLayout's
-- row-geometry basis).
local function setPctSizeMaster(inst, n)
    ensureApplied(inst)
    local cfg = inst.cfg
    local v = math.max(1, math.floor(tonumber(n) or cfg.digitSize2))
    cfg.digitSize2 = v
    cfg.digitSize1 = math.floor(v * 38 / 32 + 0.5)
    cfg.digitSize3 = math.floor(v * 26 / 32 + 0.5)
    cfg.pctSize = v
    applyFonts(inst)
    applyLayout(inst)
    update(inst)
end

local function setNameSize(inst, n)
    ensureApplied(inst)
    inst.cfg.nameSize = math.max(1, math.floor(tonumber(n) or inst.cfg.nameSize))
    -- No applyLayout: the name's anchor sits on the row-gap midline, which is
    -- name-size-independent by design. refreshName refits (nameSize is the fit
    -- ceiling), so the change lands through the fit when it is on. The envelope
    -- DOES track the ceiling (reserved wrap-box height), hence the refresh.
    applyFonts(inst)
    applyEnvelope(inst)
    refreshName(inst)
end

local function setNameFont(inst, face)
    ensureApplied(inst)
    local cfg = inst.cfg
    if not face or face == "" then
        addon:Print("UFZ setter usage: namefont <FACE|follow>   (current: " .. cfg.nameFace .. ")")
        return
    end
    local lowered = tostring(face):lower()
    if lowered == "follow" or lowered == "off" or lowered == "reset" then
        cfg.nameFace = "follow"
    else
        cfg.nameFace = face
        local isPath = cfg.nameFace:find("[/\\]") ~= nil
        local isLSM = addon.IsLSMKey and addon.IsLSMKey(cfg.nameFace)
        if not isPath and not isLSM and not addon.Fonts[cfg.nameFace] then
            addon:Print("Warning: '" .. cfg.nameFace .. "' is not in this session's font registry, so the resolver falls back to the default face. Registry changes need /reload; new font files need a full client restart.")
        end
    end
    applyFonts(inst)
    refreshName(inst)
end

local function setNameOffset(inst, n)
    ensureApplied(inst)
    inst.cfg.nameOffset = math.floor(tonumber(n) or inst.cfg.nameOffset)
    applyLayout(inst)
end

local function setNameY(inst, n)
    ensureApplied(inst)
    inst.cfg.nameY = math.floor(tonumber(n) or inst.cfg.nameY)
    applyLayout(inst)
end

local function setNameColorMode(inst, mode)
    ensureApplied(inst)
    mode = tostring(mode or ""):lower()
    if mode ~= "gradient" and mode ~= "custom" then
        addon:Print("Name color mode must be one of: gradient | custom")
        return
    end
    inst.cfg.nameColorMode = mode
    refreshName(inst)
end

local function setNameColor(inst, r, g, b, a)
    ensureApplied(inst)
    local cfg = inst.cfg
    cfg.nameColorR = tonumber(r) or 1
    cfg.nameColorG = tonumber(g) or 1
    cfg.nameColorB = tonumber(b) or 1
    cfg.nameColorA = tonumber(a) or 1
    refreshName(inst)
end

local function setNameMaxWidth(inst, n)
    ensureApplied(inst)
    local v = tonumber(n)
    if not v then
        addon:Print(string.format("UFZ setter usage: namemaxwidth <px>   (current: %d)", inst.cfg.nameMaxWidth))
        return
    end
    inst.cfg.nameMaxWidth = math.max(40, math.min(600, math.floor(v)))
    -- The display FS carries the same box the fit measures against.
    applyLayout(inst)
    refreshName(inst)
end

local function setNameMaxLines(inst, n)
    ensureApplied(inst)
    local v = tonumber(n)
    if not v then
        addon:Print(string.format("UFZ setter usage: namemaxlines <n>   (current: %d)", inst.cfg.nameMaxLines))
        return
    end
    inst.cfg.nameMaxLines = math.max(1, math.min(4, math.floor(v)))
    applyLayout(inst)
    refreshName(inst)
end

local function setNameFit(inst, state)
    ensureApplied(inst)
    state = tostring(state or ""):lower()
    if state ~= "on" and state ~= "off" then
        addon:Print("UFZ setter usage: namefit <on|off>")
        return
    end
    inst.cfg.nameFit = (state == "on")
    refreshName(inst)
end

local function setNameMinSize(inst, n)
    ensureApplied(inst)
    local v = tonumber(n)
    if not v then
        addon:Print(string.format("UFZ setter usage: nameminsize <n>   (current: %d)", inst.cfg.nameMinSize))
        return
    end
    -- The fit swaps a floor above the ceiling internally, so any value is safe;
    -- clamp to something readable anyway.
    inst.cfg.nameMinSize = math.max(4, math.floor(v))
    refreshName(inst)
end

local function setStretch(inst, n)
    ensureApplied(inst)
    local fx = tonumber(n)
    if not fx then
        addon:Print("UFZ setter usage: stretch <factor>   (1 = off; e.g. 1.35)")
        return
    end
    inst.cfg.stretch = math.max(0.5, math.min(3, fx))
    applyStretch(inst)
    addon:Print(string.format("Stretch: %.2fx wide%s", inst.cfg.stretch, inst.cfg.stretch == 1 and " (off)" or ""))
end

local function setScale(inst, n)
    ensureApplied(inst)
    local s = tonumber(n)
    if not s then
        addon:Print(string.format("UFZ setter usage: scale <0.5-2.0>   (current: %.2f)", inst.cfg.scale))
        return
    end
    inst.cfg.scale = math.max(0.5, math.min(2, s))
    applyScale(inst)
end

local function setOpacityImpl(inst, key, v)
    ensureApplied(inst)
    local pct = tonumber(v)
    if not pct then return end
    inst.cfg[key] = math.max(0, math.min(100, pct))
    applyOpacity(inst)
end

local function setSymbol(inst, state, size)
    ensureApplied(inst)
    local cfg = inst.cfg
    state = tostring(state or ""):lower()
    if state == "on" then
        cfg.symbol = true
    elseif state == "off" then
        cfg.symbol = false
    else
        addon:Print("UFZ setter usage: symbol <on|off> [size|auto]   (auto = a fifth of the percent size, tracks digit mode)")
        return
    end
    if size then
        if tostring(size):lower() == "auto" then
            cfg.symbolSize = 0
        else
            local n = tonumber(size)
            if n then cfg.symbolSize = math.max(1, math.floor(n)) end
        end
    end
    applyFonts(inst)
    applyLayout(inst)
    update(inst)
    -- The experimental secret-width anchor only exists in the NON-centered left
    -- branch; centered mode anchors the '%' identically for both aligns, and the
    -- target instance defaults to centered-left -- no warning noise there.
    if cfg.symbol and cfg.align == "left" and not cfg.center then
        addon:Print("Left mode with symbol on anchors '%' to a secret-width edge (the experiment). Check 'report'.")
    end
end

-- Same 0.1-snapping contract as setGap: sub-px offsets land on different
-- physical pixels under a fractional UI scale. Negative pulls the '%' into the
-- digits' side bearing (the glyph rects carry whitespace, so ink-tight needs
-- overlap).
local function setSymbolGap(inst, n)
    ensureApplied(inst)
    local v = tonumber(n)
    if not v then
        addon:Print(string.format("UFZ setter usage: symbolgap <px>   (current: %.1f; negative tightens)", inst.cfg.symbolGap))
        return
    end
    inst.cfg.symbolGap = math.floor(v * 10 + 0.5) / 10
    applyLayout(inst)
    update(inst)
end

local function setAlign(inst, a)
    ensureApplied(inst)
    local cfg = inst.cfg
    a = tostring(a or ""):lower()
    if a ~= "right" and a ~= "left" then
        addon:Print("Align must be one of: right | left")
        return
    end
    cfg.align = a
    applyLayout(inst)
    update(inst)
    if cfg.symbol and cfg.align == "left" and not cfg.center then
        addon:Print("Left mode with symbol on anchors '%' to a secret-width edge (the experiment). Check 'report'.")
    end
    addon:Print("Align: " .. cfg.align)
end

local function setColor(inst, m)
    ensureApplied(inst)
    m = tostring(m or ""):lower()
    if m ~= "curve" and m ~= "dark" and m ~= "white" then
        addon:Print("Color must be one of: curve | dark | white")
        return
    end
    inst.cfg.color = m
    update(inst)
    addon:Print("Color: " .. inst.cfg.color)
end

local function setRound(inst, m)
    ensureApplied(inst)
    m = tostring(m or ""):lower()
    if m ~= "floor" and m ~= "round" then
        addon:Print("Round must be one of: floor | round")
        return
    end
    inst.cfg.round = m
    update(inst)
    addon:Print("Percent rounding: " .. inst.cfg.round)
end

--------------------------------------------------------------------------------
-- Power text setters: one implementation per knob, keyed by which power
-- ("power" | "altPower") composes the cfg keys. Published through the API table
-- as SetPower*/SetAltPower* closures.
--------------------------------------------------------------------------------

local POWER_LOCS = {
    bottomleft = true, bottomright = true, topleft = true, topright = true, nameside = true,
}

local function powerWord(which)
    if which == "altPower" then return "altpower" end
    if which == "level" then return "level" end
    return "power"
end

local function setPowerShowImpl(inst, which, state)
    ensureApplied(inst)
    state = tostring(state or ""):lower()
    if state ~= "on" and state ~= "off" then
        addon:Print("UFZ setter usage: " .. powerWord(which) .. " <on|off>")
        return
    end
    inst.cfg[which .. "Show"] = (state == "on")
    applyEnvelope(inst)  -- a hidden satellite stops reserving envelope space
    update(inst)
end

-- One shared toggle, not per-power: it governs the '%' companion on every
-- power text that renders as a percent (mana, primary or alternate).
local function setPowerSymbolImpl(inst, state)
    ensureApplied(inst)
    state = tostring(state or ""):lower()
    if state ~= "on" and state ~= "off" then
        addon:Print("UFZ setter usage: powersymbol <on|off>")
        return
    end
    inst.cfg.powerSymbol = (state == "on")
    updatePower(inst)       -- sets/clears the sign's text
    applyPowerLayout(inst)  -- the right-edge sign reserve changed
end

local function setPowerLocImpl(inst, which, loc)
    ensureApplied(inst)
    loc = tostring(loc or ""):lower()
    if not POWER_LOCS[loc] then
        addon:Print("Location must be one of: bottomleft | bottomright | topleft | topright | nameside")
        return
    end
    inst.cfg[which .. "Loc"] = loc
    applyEnvelope(inst)
    applyPowerLayout(inst)
end

local function setPowerSizeImpl(inst, which, n)
    ensureApplied(inst)
    -- Half-point steps, the setValSize contract.
    local key = which .. "Size"
    local v = tonumber(n) or inst.cfg[key]
    inst.cfg[key] = math.max(1, math.floor(v * 2 + 0.5) / 2)
    applyFonts(inst)
    applyEnvelope(inst)
    applyPowerLayout(inst)  -- the '%' sign's right-edge reserve tracks the size
end

-- nil leaves an axis unchanged -- the dual-slider shape (each sub-slider sets
-- one axis). 0.1 snap, the setGap contract.
local function setPowerOffsetImpl(inst, which, x, y)
    ensureApplied(inst)
    local kx, ky = which .. "X", which .. "Y"
    local vx, vy = tonumber(x), tonumber(y)
    if not vx and not vy then
        addon:Print(string.format("UFZ %soffset usage: <x> [y]   (current: %.1f, %.1f)",
            powerWord(which), inst.cfg[kx], inst.cfg[ky]))
        return
    end
    if vx then inst.cfg[kx] = math.floor(vx * 10 + 0.5) / 10 end
    if vy then inst.cfg[ky] = math.floor(vy * 10 + 0.5) / 10 end
    applyEnvelope(inst)
    applyPowerLayout(inst)
end

local function setPowerColorModeImpl(inst, which, mode)
    ensureApplied(inst)
    mode = tostring(mode or ""):lower()
    if mode ~= "power" and mode ~= "custom" then
        addon:Print("Power color mode must be one of: power | custom")
        return
    end
    inst.cfg[which .. "ColorMode"] = mode
    applyPowerColor(inst)
end

local function setPowerColorImpl(inst, which, r, g, b, a)
    ensureApplied(inst)
    local cfg = inst.cfg
    cfg[which .. "ColorR"] = tonumber(r) or 1
    cfg[which .. "ColorG"] = tonumber(g) or 1
    cfg[which .. "ColorB"] = tonumber(b) or 1
    cfg[which .. "ColorA"] = tonumber(a) or 1
    applyPowerColor(inst)
end

local function setAbsorbShow(inst, state)
    ensureApplied(inst)
    state = tostring(state or ""):lower()
    if state ~= "on" and state ~= "off" then
        addon:Print("UFZ setter usage: absorb <on|off>")
        return
    end
    inst.cfg.absorbShow = (state == "on")
    updateAbsorb(inst)
end

-- nil leaves an axis unchanged -- the dual-slider shape. 0.1 snap, the setGap
-- contract. Re-anchors alone: an offset nudge needs none of applyLayout's
-- stretch churn.
local function setAbsorbOffset(inst, x, y)
    ensureApplied(inst)
    local cfg = inst.cfg
    local vx, vy = tonumber(x), tonumber(y)
    if not vx and not vy then
        addon:Print(string.format("UFZ setter usage: absorboffset <x> [y]   (current: %.1f, %.1f)",
            cfg.absorbX, cfg.absorbY))
        return
    end
    if vx then cfg.absorbX = math.floor(vx * 10 + 0.5) / 10 end
    if vy then cfg.absorbY = math.floor(vy * 10 + 0.5) / 10 end
    anchorAbsorbFS(inst)
end

-- The level text's ONE toggle: no regular on/off exists.
local function setLevelHideMax(inst, state)
    ensureApplied(inst)
    state = tostring(state or ""):lower()
    if state ~= "on" and state ~= "off" then
        addon:Print("UFZ setter usage: levelhidemax <on|off>")
        return
    end
    inst.cfg.levelHideMax = (state == "on")
    updateLevel(inst)
end

--------------------------------------------------------------------------------
-- Adornment setters: the dead skull and the classification icon
--------------------------------------------------------------------------------

local function setDeadIconScale(inst, pct)
    ensureApplied(inst)
    local v = tonumber(pct)
    if not v then
        addon:Print(string.format("UFZ setter usage: deadiconscale <50-200>   (current: %d)",
            inst.cfg.deadIconScale))
        return
    end
    inst.cfg.deadIconScale = math.max(50, math.min(200, math.floor(v + 0.5)))
    applyLayout(inst)
end

local function setClassifyShow(inst, state)
    ensureApplied(inst)
    state = tostring(state or ""):lower()
    if state ~= "on" and state ~= "off" then
        addon:Print("UFZ setter usage: classify <on|off>")
        return
    end
    inst.cfg.classifyShow = (state == "on")
    -- This one DOES move the envelope: the icon is a satellite, and its
    -- reservation appears and disappears with the toggle.
    applyEnvelope(inst)
    applyPowerLayout(inst)
    updateClassification(inst)
end

local function setClassifyLoc(inst, loc)
    ensureApplied(inst)
    loc = tostring(loc or ""):lower()
    if not POWER_LOCS[loc] then
        addon:Print("Location must be one of: bottomleft | bottomright | topleft | topright | nameside")
        return
    end
    inst.cfg.classifyLoc = loc
    applyEnvelope(inst)
    applyPowerLayout(inst)
end

local function setClassifySize(inst, px)
    ensureApplied(inst)
    local v = tonumber(px)
    if not v then
        addon:Print(string.format("UFZ setter usage: classifysize <8-48>   (current: %d)",
            inst.cfg.classifySize))
        return
    end
    inst.cfg.classifySize = math.max(8, math.min(48, math.floor(v + 0.5)))
    applyEnvelope(inst)
    applyPowerLayout(inst)
end

--------------------------------------------------------------------------------
-- Stack setters (Boss only)
--------------------------------------------------------------------------------
-- The keys exist only on a config whose defaults declare them (core.lua), so
-- these are no-ops on Player and Target rather than a way to grow them a
-- stack. _ApplyStack owns the combat guard.

local function setStackSpacing(inst, px)
    ensureApplied(inst)
    if inst.cfg.stackSpacing == nil then return end
    local v = tonumber(px)
    if not v then
        addon:Print(string.format("UFZ setter usage: stackspacing <-20-40>   (current: %d)",
            inst.cfg.stackSpacing))
        return
    end
    inst.cfg.stackSpacing = math.max(-20, math.min(40, math.floor(v + 0.5)))
    UFZ._ApplyStack(inst.unitKey)
end

local function setStackGrowth(inst, dir)
    ensureApplied(inst)
    if inst.cfg.stackGrowth == nil then return end
    dir = tostring(dir or ""):lower()
    if dir ~= "down" and dir ~= "up" then
        addon:Print("Stack growth must be one of: down | up")
        return
    end
    inst.cfg.stackGrowth = dir
    UFZ._ApplyStack(inst.unitKey)
end

--------------------------------------------------------------------------------
-- Aura row setters: cfg writers only -- auras.lua owns the workers, reached
-- through the UFZ.Auras seam. Unboxed by design: no aura setter ever calls
-- applyEnvelope.
--------------------------------------------------------------------------------

local function auraSeam(inst, hook)
    local A = UFZ.Auras
    local fn = A and A[hook]
    if fn then fn(inst) end
end

local function setAuraShowImpl(inst, which, state)
    ensureApplied(inst)
    state = tostring(state or ""):lower()
    if state ~= "on" and state ~= "off" then
        addon:Print("UFZ setter usage: " .. which:lower() .. " <on|off>")
        return
    end
    inst.cfg["aura" .. which .. "Show"] = (state == "on")
    auraSeam(inst, "ApplyAll")
end

local function setAuraLocImpl(inst, which, loc)
    ensureApplied(inst)
    loc = tostring(loc or ""):lower()
    if loc ~= "top" and loc ~= "bottom" then
        addon:Print("Placement must be one of: top | bottom")
        return
    end
    inst.cfg["aura" .. which .. "Loc"] = loc
    auraSeam(inst, "ApplyLayout")
end

-- One shared vertical nudge for both rows (+ = up), 0 = the snug FRAME_GAP
-- default. Arrangement, not styling: excluded from Copy From beside the Locs.
local function setAuraOffsetY(inst, n)
    ensureApplied(inst)
    local v = tonumber(n)
    if not v then return end
    v = math.floor(v + 0.5)
    if v < -60 then v = -60 elseif v > 60 then v = 60 end
    inst.cfg.auraOffsetY = v
    auraSeam(inst, "ApplyLayout")
end

local AURA_MAX_CAP = { Buffs = 32, Debuffs = 16 }

local function setAuraMaxImpl(inst, which, n)
    ensureApplied(inst)
    local v = tonumber(n)
    if not v then return end
    v = math.floor(v + 0.5)
    local cap = AURA_MAX_CAP[which]
    if v < 1 then v = 1 elseif v > cap then v = cap end
    inst.cfg["aura" .. which .. "Max"] = v
    -- ApplyAll, not ForceRefresh: the cap is the group's maxFrameCount, and
    -- only the group-config pass writes it. A kick would repaint the same cap.
    auraSeam(inst, "ApplyAll")
end

local function setAuraIconScale(inst, n)
    ensureApplied(inst)
    local v = tonumber(n)
    if not v then return end
    if v < 20 then v = 20 elseif v > 200 then v = 200 end
    inst.cfg.auraIconScale = v
    auraSeam(inst, "ApplyStyle")
end

local function setAuraShape(inst, n)
    ensureApplied(inst)
    local v = tonumber(n)
    if not v then return end
    v = math.floor(v + 0.5)
    if v < -67 then v = -67 elseif v > 67 then v = 67 end
    inst.cfg.auraTallWideRatio = v
    auraSeam(inst, "ApplyStyle")
end

local function setAuraBorderEnable(inst, state)
    ensureApplied(inst)
    state = tostring(state or ""):lower()
    if state ~= "on" and state ~= "off" then
        addon:Print("UFZ setter usage: auraborder <on|off>")
        return
    end
    inst.cfg.auraBorderEnable = (state == "on")
    auraSeam(inst, "ApplyStyle")
end

local function setAuraBorderStyle(inst, styleKey)
    ensureApplied(inst)
    if type(styleKey) ~= "string" or styleKey == "" then return end
    inst.cfg.auraBorderStyle = styleKey
    auraSeam(inst, "ApplyStyle")
end

local function setAuraBorderThickness(inst, n)
    ensureApplied(inst)
    local v = tonumber(n)
    if not v then return end
    -- Half steps, the border slider contract.
    v = math.floor(v * 2 + 0.5) / 2
    if v < 1 then v = 1 elseif v > 8 then v = 8 end
    inst.cfg.auraBorderThickness = v
    auraSeam(inst, "ApplyStyle")
end

local function setAuraBorderTint(inst, state)
    ensureApplied(inst)
    state = tostring(state or ""):lower()
    if state ~= "on" and state ~= "off" then
        addon:Print("UFZ setter usage: auratint <on|off>")
        return
    end
    inst.cfg.auraBorderTintEnable = (state == "on")
    auraSeam(inst, "ApplyStyle")
end

local function setAuraBorderTintColor(inst, r, g, b, a)
    ensureApplied(inst)
    inst.cfg.auraBorderTintR = tonumber(r) or 1
    inst.cfg.auraBorderTintG = tonumber(g) or 1
    inst.cfg.auraBorderTintB = tonumber(b) or 1
    inst.cfg.auraBorderTintA = tonumber(a) or 1
    auraSeam(inst, "ApplyStyle")
end

local function setAuraOnlyPlayerBuffs(inst, state)
    ensureApplied(inst)
    state = tostring(state or ""):lower()
    if state ~= "on" and state ~= "off" then
        addon:Print("UFZ setter usage: aurafilter <on|off>")
        return
    end
    inst.cfg.auraOnlyPlayerBuffs = (state == "on")
    -- ApplyAll, not ForceRefresh: the PLAYER token lives in the group's filter
    -- string, and only the group-config pass writes it.
    auraSeam(inst, "ApplyAll")
end

-- Hover tooltips: motion-only mouse on the icons (clicks always fall through
-- to the secure click-to-target overlay). ApplyStyle re-applies the memoized
-- per-icon mouse state; the mouse APIs are unrestricted, so combat-legal.
local function setAuraTooltips(inst, state)
    ensureApplied(inst)
    state = tostring(state or ""):lower()
    if state ~= "on" and state ~= "off" then
        addon:Print("UFZ setter usage: auratooltips <on|off>")
        return
    end
    inst.cfg.auraTooltips = (state == "on")
    auraSeam(inst, "ApplyStyle")
end

local function reset(inst)
    ensureApplied(inst)
    -- Wipe-and-refill through core.lua, which re-applies the shared defaults
    -- plus this unit's overrides (the target instance must not reset into a
    -- second player frame). The table object survives -- inst.cfg and the DB
    -- hold the same reference. Called once per instance by the GetAPI fan-out,
    -- which is harmless: the second wipe refills the same defaults.
    UFZ._ResetUnitDB(inst.unitKey)
    local cfg = inst.cfg
    inst.lastDigitCount = nil
    inst.nameFitSize = nil
    inst.chromeBG:SetShown(cfg.chrome)
    registerUnitEvents(inst)
    applyClickAttributes(inst)
    applyScale(inst)
    applyFonts(inst)
    applyLayout(inst)
    update(inst)
    refreshName(inst)
    -- Reset runs its own worker list, not _ApplyAll, so the aura pass is
    -- repeated here (defaults turn the rows off; this clears them).
    if UFZ.Auras then UFZ.Auras.ApplyAll(inst) end
    applyOpacity(inst)
    -- Explicit, not via the applyEnvelope/applyScale hooks: a reset restores
    -- the default spacing and growth, and those two move the stack without
    -- moving any frame's envelope or scale.
    UFZ._ApplyStack(inst.unitKey)
end

--------------------------------------------------------------------------------
-- Instances and the public API
--------------------------------------------------------------------------------

-- Identity fields live OUTSIDE cfg on purpose: Reset and GetConfig iterate cfg
-- and must never see or clobber them. cfg is NOT copied from anywhere: it is
-- the AceDB-backed per-unit table itself, so every write persists and every
-- read sees the active profile.
--
-- The three identifiers come from the frame ROW (core.lua), never from cfg --
-- five boss instances share one cfg table, so the unit token in particular
-- cannot be a config value:
--   unitKey  "Boss"   which config this frame reads
--   frameKey "Boss3"  which frame this is
--   unit     "boss3"  the token every unit API call takes
local function newInstance(row, cfg)
    local inst = {
        cfg = cfg,
        unitKey = row.unitKey,
        frameKey = row.frameKey,
        unit = row.token,
        stackIndex = row.stackIndex,
        frameName = "ScootUnitFrameZ" .. row.frameKey,
        label = row.token,
        poolKey = "ufz:" .. row.frameKey,   -- one blind-fit ruler pool per instance
        frame = nil,
        chromeBG = nil,
        pctFS = nil, valFS = nil, symbolFS = nil, nameFS = nil, rulerFS = nil,
        powerFS = nil, powerSymbolFS = nil, altPowerFS = nil, altPowerSymbolFS = nil,
        -- 12.1 ping: the receiver and the name-row carve-out inside it.
        pingReceiver = nil, pingNameBox = nil,
        appliedPingRect = nil, appliedPingName = nil,
        -- The absorb text FS and the rect-riding soft halo behind it.
        absorbFS = nil, absorbGlowTex = nil,
        -- The level pair: the number and its 75%-size "lvl" prefix.
        levelFS = nil, levelPrefixFS = nil,
        -- The adornment textures, plus the memos that keep their SetAtlas calls
        -- off the per-tick path (appliedDeadIcon = the chosen style key,
        -- classifyAtlas = the atlas currently painted).
        deadTex = nil, appliedDeadIcon = nil,
        classifyTex = nil, classifyAtlas = nil,
        -- The alternate power's token ("MANA"/"ENERGY"), written by updatePower
        -- and read by applyPowerColor. Readable string, never a secret.
        altPowerName = nil,
        -- Whether each power text currently renders as a percent (mana, either
        -- row); drives the '%' companion and its right-edge anchor reserve.
        powerIsPct = false,
        altPowerIsPct = false,
        -- Digit-mode probe state. lastDigitCount is the cache the feature pivots
        -- on: nil until the oracle answers, then 1-3.
        probePending = false, probeRetries = 0, lastDigitCount = nil,
        -- Name-fit state: seq kills stale async passes, nameFitSize is the cache
        -- currentNamePoint pivots on, lastNameFit is report material.
        nameFitSeq = 0, nameFitSize = nil, lastNameFit = nil,
        -- Measured ink width of the painted name (widest wrapped line); nil =
        -- unmeasurable (secret name) -> power anchors fall back to box edges.
        nameInkWidth = nil,
        -- Buff/debuff AuraContainers, created lazily by auras.lua the first
        -- time a row is enabled and never destroyed after that (the engine
        -- exposes no group removal). { Buffs = entry, Debuffs = entry }.
        auraContainers = nil,
        -- Secure unit watch bookkeeping (applyUnitWatch): whether the frame is
        -- registered with Blizzard's existence watcher, and for which unit.
        watchRegistered = nil, watchUnit = nil,
        -- What the last update() did, per chain. Report material; never
        -- secrets.
        last = {
            pct = "never ran", val = "never ran", color = "never ran",
            name = "never ran", digits = "never ran",
            power = "never ran", altPower = "never ran",
            powerColor = "never ran", altPowerColor = "never ran",
            absorb = "never ran", level = "never ran",
        },
    }
    -- One stable closure for the probe's timer chain (C_Timer.After cannot pass
    -- arguments, and allocating a closure per schedule would defeat coalescing).
    inst.probeDigitsFn = function() probeDigits(inst) end
    return inst
end

local API = {
    GetConfig = getConfig,
    SetFont = setFont,
    SetStyle = function(inst, s) return setStyleImpl(inst, "style", s) end,
    SetNameStyle = function(inst, s) return setStyleImpl(inst, "nameStyle", s) end,
    SetPowerStyle = function(inst, s) return setStyleImpl(inst, "powerStyle", s) end,
    SetLevelStyle = function(inst, s) return setStyleImpl(inst, "levelStyle", s) end,
    SetPctSize = setPctSize,
    SetValSize = setValSize,
    SetValFont = setValFont,
    SetDescent = setDescent,
    SetGap = setGap,
    SetCenter = setCenter,
    SetCenterOffset = setCenterOffset,
    SetDigits = setDigits,
    SetDigitSize = setDigitSize,
    SetPctSizeMaster = setPctSizeMaster,
    SetNameSize = setNameSize,
    SetNameFont = setNameFont,
    SetNameOffset = setNameOffset,
    SetNameY = setNameY,
    SetNameColorMode = setNameColorMode,
    SetNameColor = setNameColor,
    SetNameMaxWidth = setNameMaxWidth,
    SetNameMaxLines = setNameMaxLines,
    SetNameFit = setNameFit,
    SetNameMinSize = setNameMinSize,
    SetStretch = setStretch,
    SetScale = setScale,
    SetOpacityOutOfCombat = function(inst, v) return setOpacityImpl(inst, "opacityOutOfCombat", v) end,
    SetOpacityInCombat = function(inst, v) return setOpacityImpl(inst, "opacityInCombat", v) end,
    SetOpacityWithTarget = function(inst, v) return setOpacityImpl(inst, "opacityWithTarget", v) end,
    SetSymbol = setSymbol,
    SetSymbolGap = setSymbolGap,
    SetAlign = setAlign,
    SetColor = setColor,
    SetRound = setRound,
    SetPowerSymbol = setPowerSymbolImpl,
    SetPowerShow = function(inst, s) return setPowerShowImpl(inst, "power", s) end,
    SetPowerLoc = function(inst, l) return setPowerLocImpl(inst, "power", l) end,
    SetPowerSize = function(inst, n) return setPowerSizeImpl(inst, "power", n) end,
    SetPowerOffset = function(inst, x, y) return setPowerOffsetImpl(inst, "power", x, y) end,
    SetPowerColorMode = function(inst, m) return setPowerColorModeImpl(inst, "power", m) end,
    SetPowerColor = function(inst, r, g, b, a) return setPowerColorImpl(inst, "power", r, g, b, a) end,
    SetAltPowerShow = function(inst, s) return setPowerShowImpl(inst, "altPower", s) end,
    SetAltPowerLoc = function(inst, l) return setPowerLocImpl(inst, "altPower", l) end,
    SetAltPowerSize = function(inst, n) return setPowerSizeImpl(inst, "altPower", n) end,
    SetAltPowerOffset = function(inst, x, y) return setPowerOffsetImpl(inst, "altPower", x, y) end,
    SetAltPowerColorMode = function(inst, m) return setPowerColorModeImpl(inst, "altPower", m) end,
    SetAltPowerColor = function(inst, r, g, b, a) return setPowerColorImpl(inst, "altPower", r, g, b, a) end,
    SetAbsorbShow = setAbsorbShow,
    SetAbsorbOffset = setAbsorbOffset,
    SetLevelHideMax = setLevelHideMax,
    SetLevelLoc = function(inst, l) return setPowerLocImpl(inst, "level", l) end,
    SetLevelSize = function(inst, n) return setPowerSizeImpl(inst, "level", n) end,
    SetLevelOffset = function(inst, x, y) return setPowerOffsetImpl(inst, "level", x, y) end,
    SetDeadIconScale = setDeadIconScale,
    SetClassifyShow = setClassifyShow,
    SetClassifyLoc = setClassifyLoc,
    SetClassifySize = setClassifySize,
    SetStackSpacing = setStackSpacing,
    SetStackGrowth = setStackGrowth,
    SetAuraBuffsShow = function(inst, s) return setAuraShowImpl(inst, "Buffs", s) end,
    SetAuraDebuffsShow = function(inst, s) return setAuraShowImpl(inst, "Debuffs", s) end,
    SetAuraBuffsLoc = function(inst, l) return setAuraLocImpl(inst, "Buffs", l) end,
    SetAuraDebuffsLoc = function(inst, l) return setAuraLocImpl(inst, "Debuffs", l) end,
    SetAuraBuffsMax = function(inst, n) return setAuraMaxImpl(inst, "Buffs", n) end,
    SetAuraDebuffsMax = function(inst, n) return setAuraMaxImpl(inst, "Debuffs", n) end,
    SetAuraOffsetY = setAuraOffsetY,
    SetAuraIconScale = setAuraIconScale,
    SetAuraShape = setAuraShape,
    SetAuraBorderEnable = setAuraBorderEnable,
    SetAuraBorderStyle = setAuraBorderStyle,
    SetAuraBorderThickness = setAuraBorderThickness,
    SetAuraBorderTint = setAuraBorderTint,
    SetAuraBorderTintColor = setAuraBorderTintColor,
    SetAuraOnlyPlayerBuffs = setAuraOnlyPlayerBuffs,
    SetAuraTooltips = setAuraTooltips,
    Reset = reset,
}

--------------------------------------------------------------------------------
-- Instance lifecycle (called by core.lua's ApplyStyling)
--------------------------------------------------------------------------------

--- A frame row's instance, created on first request. On every later call the
--- cfg reference is re-pointed at the active profile's table -- a profile
--- switch swaps addon.db.profile out from under a cached reference, and every
--- closure in this file reads through inst.cfg for exactly this moment.
---
--- Takes a ROW, not a unit key: the config comes from row.unitKey (shared by
--- all five boss frames) while the instance is keyed by row.frameKey.
function UFZ._EnsureInstance(row)
    if not row then return nil end
    local cfg = UFZ._GetUnitConfig(row.unitKey)
    if not cfg then return nil end

    local inst = UFZ._instances[row.frameKey]
    local switchedProfile = false
    if not inst then
        inst = newInstance(row, cfg)
        UFZ._instances[row.frameKey] = inst
    elseif inst.cfg ~= cfg then
        inst.cfg = cfg
        -- The caches pivot on config that just changed wholesale.
        inst.lastDigitCount = nil
        inst.nameFitSize = nil
        switchedProfile = true
    end

    ensureFrame(inst)
    if switchedProfile then
        -- The new profile stores its own positions, and nothing else re-reads
        -- them on an AceDB switch (LEM's layout callback fires only on Edit
        -- Mode layout changes).
        UFZ._RestorePosition(inst)
    end
    return inst
end

--- The full apply pipeline, in the reset/settings-change order. update and
--- refreshName no-op while the frame is hidden; _UpdateVisibility runs them on
--- the way to showing it.
function UFZ._ApplyAll(inst)
    if not inst then return end
    ensureApplied(inst)
    registerUnitEvents(inst)
    inst.chromeBG:SetShown(inst.cfg.chrome)
    -- Click overlay self-heal: the unit attribute tracks inst.unit, and the
    -- overlay stays hidden for exactly as long as Edit Mode is open --
    -- editmode.lua's enter/exit callbacks are the primary writer, this is the
    -- backstop for an overlay created mid-session. Both workers carry their own
    -- lockdown guard and queue, so an _ApplyAll that lands in combat defers the
    -- writes rather than dropping them.
    if inst.clickButton then
        if inst.clickButton:GetAttribute("unit") ~= inst.unit then
            applyClickAttributes(inst)
        end
        applyClickShown(inst)
    end
    -- Same self-heal for the ping receiver. Unprotected, so no lockdown guard.
    wirePingReceiver(inst)
    applyScale(inst)
    applyFonts(inst)
    applyLayout(inst)
    update(inst)
    refreshName(inst)
    -- Full aura pass: covers profile switch, Copy From and mid-session enable
    -- (all wholesale-change paths funnel through here).
    if UFZ.Auras then UFZ.Auras.ApplyAll(inst) end
    applyOpacity(inst)
    -- A unit enabled while Edit Mode is already open builds its frame on this
    -- pass, and would otherwise stand there with no stand-in until Edit Mode was
    -- re-entered: the enter callback's loop reads _instances and never builds.
    -- The Cast Bar Z precedent (castbarz/frames.lua:615-623). It has to be the
    -- tail -- the stand-in paints sample strings that update() and refreshName()
    -- above would overwrite if it ran any earlier.
    if addon.EditMode.IsEditing() and UFZ._IsUnitEnabled(inst.unitKey) then
        UFZ._ShowEditModePreview(inst)
    end
end

--- The one visibility resolver. The existence axis for target/focus belongs
--- to the secure unit watch (the click child makes the frame's visibility
--- combat-protected, and the watch is the sanctioned secure channel); this
--- function settles the watch, handles the axes the watch does not know
--- (enabled toggle, the always-existing player unit, the Edit Mode stand-in),
--- and repaints whatever is currently shown. It never needs UnitExists: the
--- watch answers existence by having shown or hidden the frame already.
function UFZ._UpdateVisibility(inst)
    if not inst or not inst.frame then return end

    if inst.previewActive then
        -- The watch was dropped by _ShowEditModePreview, so the manager cannot
        -- re-hide the stand-in. The show still goes through setShownSafe: Edit
        -- Mode opens in combat and this frame's visibility is protected, so a
        -- call that lands in lockdown queues rather than throwing.
        setShownSafe(inst, true)
        applyOpacity(inst)
        return
    end

    applyUnitWatch(inst)

    if not UFZ._IsUnitEnabled(inst.unitKey) then
        setShownSafe(inst, false)
        return
    end

    if inst.unit == "player" then
        setShownSafe(inst, true)
    end

    if inst.frame:IsShown() then
        update(inst)
        refreshName(inst)
        applyOpacity(inst)
    end
end

--- Central opacity dispatch: init.lua's RefreshOpacityState calls this beside
--- ApplyAllUnitFrameVisibility, so combat and target transitions re-settle
--- every live Z frame's alpha with zero engine event wiring. Walks only
--- instances that already exist -- zero-touch safe.
function UFZ.RefreshOpacity()
    for unitKey, inst in pairs(UFZ._instances) do
        if UFZ._IsUnitEnabled(unitKey) then
            applyOpacity(inst)
        end
    end
end

--------------------------------------------------------------------------------
-- Edit Mode stand-in
--------------------------------------------------------------------------------
-- A targetless Target frame draws nothing (update()'s no-unit blank), and Edit
-- Mode has nothing to grab without a stand-in. The health, power and alt power
-- samples are plain static strings -- no unit APIs, no secret hazards --
-- painted straight onto the FontStrings the frame already laid out. The player
-- frame has live data and takes the normal paint.
--
-- Two flags, deliberately not one. previewActive means "Edit Mode is holding
-- this frame": it gates the event handler, the OnShow paint and
-- _UpdateVisibility, so live churn cannot overwrite the stand-in mid-drag.
-- previewStandIn is the narrower claim -- "this frame has no subject at all" --
-- and it is what routes refreshName and updateLevel to their stand-in paints
-- (paintStandInName, previewLevel). A previewed frame that DOES have a unit
-- sets only the first and keeps every live paint, which is the more accurate
-- preview of the two.
--
-- The bar the stand-in has to clear: outside an encounter this IS the boss
-- frame, so a setting that changes nothing here reads as a setting that does
-- nothing. Hence the level's hide-at-max and the name's ink measurement both
-- reach the preview, and every setter's repaint stays on the stand-in.

function UFZ._ShowEditModePreview(inst)
    ensureApplied(inst)
    inst.previewActive = true
    -- Drop the unit watch first (previewActive makes it unwanted): a watched
    -- targetless frame would be re-hidden by the manager's next scan, right
    -- out from under the stand-in. applyUnitWatch queues its own transition in
    -- lockdown, so it is safe to call either way.
    applyUnitWatch(inst)
    -- Edit Mode CAN be entered in combat. CanEnterEditMode
    -- (EditModeManager.lua:1636-1655) tests the EditModeDisabled game rule, NPE
    -- restriction and account settings, and nothing else, so the Game Menu
    -- button stays live in a fight and LibEditMode's OnShow hook fires straight
    -- into here. The click child makes this frame's visibility protected, so the
    -- show has to queue like every other protected write.
    setShownSafe(inst, true)
    -- Nothing below can land on a frame that is still hidden: update() and
    -- refreshName() no-op there, and every other paint would be invisible. Re-run
    -- the whole stand-in on regen rather than half-painting one now.
    if not inst.frame:IsShown() then
        queueRegen(inst, "preview")
        return
    end
    applyOpacity(inst)  -- previewActive branch: a dimmed frame snaps to full

    local okEx, ex = pcall(UnitExists, inst.unit)
    local exSecret = okEx and issecretvalue and issecretvalue(ex)
    local noUnit = not okEx or (not exSecret and ex == false)
    -- Distinct from previewActive: the stand-in only owns the chains that have
    -- no subject to read. A previewed frame that DOES have a unit keeps every
    -- live paint, which is the more accurate preview of the two.
    inst.previewStandIn = noUnit or nil
    -- Aura rows follow the same split. Engine-managed buttons cannot be made to
    -- fake auras, so a subject-less stand-in hides its containers; a previewed
    -- frame that DOES have a unit keeps its live rows.
    if UFZ.Auras then UFZ.Auras.SetPreviewStandIn(inst, noUnit) end
    if noUnit then
        local SAMPLE = { 0.55, 0.90, 0.35 }  -- a healthy green, the curve's home stretch
        inst.pctFS:SetText("72")
        inst.pctFS:SetTextColor(SAMPLE[1], SAMPLE[2], SAMPLE[3], 1)
        inst.valFS:SetText("324.5k")
        inst.valFS:SetTextColor(SAMPLE[1], SAMPLE[2], SAMPLE[3], 1)
        inst.symbolFS:SetAlpha(1)
        inst.symbolFS:SetTextColor(SAMPLE[1], SAMPLE[2], SAMPLE[3], 1)
        inst.powerFS:SetText("25.3k")
        inst.powerFS:SetTextColor(0.35, 0.55, 1.0, 1)
        inst.altPowerFS:SetText("100")
        inst.altPowerFS:SetTextColor(0.55, 0.65, 1.0, 1)
        -- Both samples are flat numbers, so a '%' left over from the last live
        -- mana paint would contradict them.
        if inst.powerSymbolFS and inst.powerSymbolFS.ClearText then inst.powerSymbolFS:ClearText() end
        if inst.altPowerSymbolFS and inst.altPowerSymbolFS.ClearText then inst.altPowerSymbolFS:ClearText() end

        -- The name and the level both go through the normal chains, which
        -- previewStandIn has just routed to their stand-in paints: the name
        -- lands ink-measured (so the far-side satellites sit against its last
        -- letter, not the box edge) and the level honours hide-at-max. Routed
        -- rather than painted inline so an entry paint and a live setter's
        -- repaint can never disagree.
        refreshName(inst)
        updateLevel(inst)
    else
        update(inst)
        refreshName(inst)
    end

    -- The two adornments, settled the same way in both branches.
    --
    -- Skull: always hidden. Preview paints live-looking numbers, and a skull
    -- sitting on top of "72 / 324.5k" contradicts them. (This also covers
    -- previewing while genuinely dead, which the update() branch above would
    -- otherwise have shown.)
    setDeadIconShown(inst, false)
    -- Classification: always SHOWN, with a stand-in. It is a positionable
    -- adornment, so it has to be visible at the exact moment the user is
    -- placing it -- an invisible icon cannot be dragged into place. Nothing
    -- else in the component paints it during preview: updateClassification
    -- early-outs on previewActive.
    if inst.classifyTex and inst.cfg.classifyShow and inst.unit ~= "player" then
        if atlasExists(CLASSIFY_PREVIEW_ATLAS) then
            pcall(inst.classifyTex.SetAtlas, inst.classifyTex, CLASSIFY_PREVIEW_ATLAS)
            inst.classifyAtlas = CLASSIFY_PREVIEW_ATLAS
            inst.classifyTex:Show()
        end
    elseif inst.classifyTex then
        inst.classifyTex:Hide()
    end
end

-- The drain for a preview whose frame could not be shown in combat. Flags only,
-- like every other slot, and previewActive is re-read here because Edit Mode may
-- have closed while the fight was still running.
regenActions.preview = function(inst)
    if inst.previewActive then UFZ._ShowEditModePreview(inst) end
end

function UFZ._EndEditModePreview(inst)
    if not inst or not inst.previewActive then return end
    inst.previewActive = nil
    inst.previewStandIn = nil
    if UFZ.Auras then UFZ.Auras.SetPreviewStandIn(inst, false) end
    -- Drop the stand-in's memo so updateClassification's skip-compare re-fires
    -- against the live unit instead of trusting the preview atlas.
    inst.classifyAtlas = nil
    -- Repaint from live data while still shown -- with no unit this runs the
    -- no-unit blank, clearing the sample strings -- then let visibility settle.
    if inst.frame and inst.frame:IsShown() then
        update(inst)
        refreshName(inst)
    end
    UFZ._UpdateVisibility(inst)
end

--------------------------------------------------------------------------------
-- The public per-unit API
--------------------------------------------------------------------------------
-- Settings pages and the Edit Mode mirror call the engine through this: every
-- API function applied to EVERY instance the config key drives. One for Player
-- and Target, five for Boss -- so a single settings page stays indifferent to
-- how many frames sit behind it, and the boss frames cannot drift apart.
--
-- The instance is resolved per call rather than captured once: profile
-- switches re-point inst.cfg, and a boss frame may not exist yet when the
-- page first binds.

local boundAPIs = {}

function UFZ.GetAPI(unitKey)
    local bound = boundAPIs[unitKey]
    if bound then return bound end
    if not UFZ._GetUnitConfig(unitKey) then return nil end

    local rows = UFZ._RowsForUnitKey(unitKey)
    if #rows == 0 then return nil end

    bound = {}
    for suffix, fn in pairs(API) do
        bound[suffix] = function(...)
            local result
            for _, row in ipairs(rows) do
                local inst = UFZ._EnsureInstance(row)
                if inst then result = fn(inst, ...) end
            end
            return result
        end
    end
    boundAPIs[unitKey] = bound
    return bound
end

--- Read-only config snapshot for the settings pages (plain values only).
--- Straight off the DB: the page reads the config, not a frame, and
--- materializing five boss instances to answer a getter would be backwards.
function UFZ.GetConfig(unitKey)
    local cfg = UFZ._GetUnitConfig(unitKey)
    if not cfg then return nil end
    local snapshot = {}
    for k, v in pairs(cfg) do snapshot[k] = v end
    return snapshot
end
