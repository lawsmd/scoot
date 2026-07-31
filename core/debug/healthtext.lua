-- debug/healthtext.lua - /scoot debug healthtext
--
-- The Unit Frames Z health block, built the way it would ship: a large current-health
-- percent stacked over a smaller abbreviated current-health value, both colored by the
-- health color curve. Spec: ADDONCONTEXT/docs/unitframesZ/ufzhealthtext.md.
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
--
-- Width matching is config-driven: every font size is a plain number, tuned via
-- 'measure' against plain sample strings. The live FontStrings hold secrets and are
-- permanently unmeasurable, so no layout decision ever reads them. Digit mode picks
-- the percent size from a per-digit-count table; the count comes from the
-- SetAlphaGradient length oracle run against an invisible ruler, never from reading.
-- The value row can run its own face: cfg.valSquish maps a squish level to the
-- current family's TALL bake (faceFamily() strips _WIDE_/_TALL_ suffixes), and
-- cfg.valFace overrides with any registry key. The TALL bakes are y-only
-- squishes of each family's BASE face, cap-pinned (ink top fixed, shrink goes
-- upward): WoW holds the baseline at a fixed depth inside the rect, so a
-- baseline-pinned squish would sink the ink inside the TOP-anchored value row
-- and grow the gap to the percent. Their advance widths are byte-identical to
-- the base face -- but NOT to the wide bakes, so with a wide main face the
-- value size slider is what re-finds the width ratio.
--
-- Everything here is addon-owned and anchored to UIParent with plain numbers. No
-- Blizzard frame is read, written, hooked or anchored to.

local addonName, addon = ...

local cfg = {
    unit         = "player",
    -- Anton Wide 180: the crisp bake of the factor the user landed on. The
    -- shipped variant matrix (each family: base + WIDE 120/150/180 + TALL
    -- 90/80/70) lives in the font picker's Modified tab; the live 'stretch'
    -- command previews in-between factors (blurry by nature -- raster-space
    -- transform). Metrics table in docs/unitframesZ/ufzhealthtext.md.
    face         = "ANTON_WIDE_180",
    style        = "SHADOWTHICKOUTLINE",
    pctSize      = 32,
    valSize      = 13,               -- one under the width-match tune; 'val 14' restores the exact match
    -- Value row face: valSquish ("90"|"80"|"70"|"off") derives the current
    -- family's TALL bake and wins while non-off; valFace ("follow" or any
    -- registry key) is the explicit-face fallback path.
    valSquish    = "90",
    valFace      = "follow",
    gap          = 1,                -- px between the percent row and the value row
    -- Digit mode: the percent's point size follows its digit count (1-3), counted
    -- blind via the SetAlphaGradient oracle on an invisible ruler (probeDigits).
    -- Flat scalar keys on purpose: DEFAULTS is a shallow copy, so a nested table
    -- would survive Reset. pctSize stays as the digits-off static size.
    digits       = true,
    digitSize1   = 38,
    digitSize2   = 32,
    digitSize3   = 26,
    -- Centered column: both number rows share a vertical centerline instead of
    -- hanging edge-justified off the frame edge.
    center       = true,
    centerOffset = 65,               -- px from the anchored frame edge to the centerline
    -- Extra lift (share of the percent's point size) between the percent's rect
    -- bottom and the row boundary. IN-GAME FINDING 2026-07-31: WoW's rendered
    -- rect hugs the ink far tighter than the font's metric tables claim -- the
    -- hhea-derived 0.33 shoved the digits down INTO the value row. 0 = the rect
    -- bottom itself rides the boundary (pure bottom-alignment). If the gap reads
    -- slightly larger at one digit than at "100", raise in ~0.03 steps
    -- ('descent <ratio>') until it evens out.
    descent      = 0,
    stretch      = 1.0,              -- width-only render stretch (1 = off), see applyStretch
    symbol       = false,            -- the small '%' glyph (its own FontString)
    symbolSize   = 14,
    symbolGap    = 1,
    align        = "right",          -- right (player-style) | left (target-style)
    color        = "curve",          -- curve | dark | white
    round        = "floor",          -- floor | round (floor: never 100 until full)
    usePredicted = true,
    chrome       = false,
    width        = 140,
    height       = 64,               -- drag box only; text may overhang it
    -- The name row (UFZ wireframe: class-gradient name beside the number stack).
    -- Fixed point size on purpose: the certified blind fit stays in nametext,
    -- and a post-fit transform here would fight it later.
    nameSize     = 26,
    nameFace     = "follow",         -- "follow" = track cfg.face; any registry key overrides
    nameOffset   = 100,              -- px from the numbers' frame edge to the name's near edge
    nameY        = 0,                -- px nudge on the name's midline anchor (+ = up)
}

local DEFAULTS = {}
for k, v in pairs(cfg) do DEFAULTS[k] = v end

local frame, chromeBG, pctFS, valFS, symbolFS, nameFS, rulerFS

-- Digit-mode probe state. lastDigitCount is the cache the feature pivots on:
-- nil until the oracle answers, then 1-3.
local probePending, probeRetries, lastDigitCount = false, 0, nil

-- What the last update() actually did, per chain. Report material; never secrets.
local last = { pct = "never ran", val = "never ran", color = "never ran", name = "never ran", digits = "never ran" }

--------------------------------------------------------------------------------
-- Value chain: the four-character abbreviation config
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

local abbrevOpts, abbrevError, abbrevTier = nil, nil, nil
local abbrevBuildTried = false

local ABBREV_BITMASK_LEGEND =
    "InvalidBreakpoint=1 InvalidSignificandDivisor=2 InvalidFractionDivisor=4 NotMultipleOfTen=8"

local function rebuildAbbrevConfig()
    abbrevBuildTried = true
    abbrevOpts, abbrevError, abbrevTier = nil, nil, nil
    if not _G.CreateAbbreviateConfig then
        abbrevError = "CreateAbbreviateConfig API missing"
        return nil
    end
    local ok, result = pcall(CreateAbbreviateConfig, BuildHealthBreakpoints())
    if ok and result then
        abbrevOpts, abbrevTier = { config = result }, "bp=1"
        return abbrevOpts
    end
    abbrevError = "bp=1: " .. tostring(result)
    -- breakpoint=1 may trip restricted validation (NotMultipleOfTen); retry bp=10.
    -- Health is an integer, so values 0-9 then pass through raw and render fine.
    local retry = BuildHealthBreakpoints()
    retry[#retry].breakpoint = 10
    ok, result = pcall(CreateAbbreviateConfig, retry)
    if ok and result then
        abbrevOpts, abbrevTier = { config = result }, "bp=10"
    else
        abbrevError = abbrevError .. " | bp=10: " .. tostring(result)
    end
    return abbrevOpts
end

--------------------------------------------------------------------------------
-- Percent chain: the numeric curve
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
local function currentPctPoint()
    return (cfg.digits and lastDigitCount and cfg["digitSize" .. lastDigitCount]) or cfg.pctSize
end

-- Base face first, override on top: SetFont on a file this client session has
-- never loaded is a silent no-op (ApplyFontStyle pcalls it), and on a virgin
-- FontString that would mean NO font object at all -- an invisible row. Applying
-- the main face first guarantees the row always renders; a loadable override
-- then simply wins.
local function applyOverrideFace(fs, size, baseFace, overrideKey)
    addon.ApplyFontStyle(fs, baseFace, size, cfg.style)
    if overrideKey ~= "follow" then
        addon.ApplyFontStyle(fs, addon.ResolveFontFace(overrideKey), size, cfg.style)
    end
end

-- Variant keys are <BASE>[_WIDE_f|_TALL_f]; stripping the suffix yields the
-- family base, so a squish level can follow the main face across families.
local function faceFamily(key)
    return (tostring(key or ""):gsub("_WIDE_%d+$", ""):gsub("_TALL_%d+$", ""))
end

-- The value row's effective override key: an active squish level derives the
-- current family's TALL bake; if that family has no talls (e.g. a stock font as
-- the main face) or the level is "off", the explicit valFace path applies.
local function valOverrideKey()
    if cfg.valSquish ~= "off" then
        local key = faceFamily(cfg.face) .. "_TALL_" .. cfg.valSquish
        if addon.Fonts and addon.Fonts[key] then return key end
    end
    return cfg.valFace
end

local function applyFonts()
    local face = addon.ResolveFontFace(cfg.face)
    addon.ApplyFontStyle(pctFS, face, currentPctPoint(), cfg.style)
    applyOverrideFace(valFS, cfg.valSize, face, valOverrideKey())
    addon.ApplyFontStyle(symbolFS, face, cfg.symbolSize, cfg.style)
    applyOverrideFace(nameFS, cfg.nameSize, face, cfg.nameFace)
end

--------------------------------------------------------------------------------
-- Width-only stretch (the Paint drag): the engine has no per-axis text scale,
-- but Scale animations take separate axes and apply while playing, so a looping
-- animation whose from and to scales are both (x, 1) holds a constant render
-- transform. It stretches the whole rendered output -- outline and shadow widen
-- with the glyphs, slightly soft -- so it is the live tuning tool; a settled
-- factor gets baked into a real font file for crisp rasterisation (ANTON_WIDE).
-- Animations transform rendering only, never the layout rect, so anchors and
-- the equal-width tuning are unaffected (both rows stretch by the same factor).
--------------------------------------------------------------------------------

local stretchAnims = {}
local stretchUnsupported = false

local function applyStretch()
    if stretchUnsupported or not frame then return end
    local fx = cfg.stretch or 1
    local edgeOrigin = (cfg.align == "left") and "LEFT" or "RIGHT"
    for _, fs in ipairs({ pctFS, valFS, symbolFS, nameFS }) do
        if fs then
            -- Centered number rows stretch about their shared centerline; the name
            -- (still edge-anchored) and the '%' keep the align edge as their origin.
            local origin = (cfg.center and (fs == pctFS or fs == valFS)) and "CENTER" or edgeOrigin
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
                        if (cfg.stretch or 1) ~= 1 and not group:IsPlaying() then
                            group:Play()
                        end
                    end)
                end
            end
        end
    end
end

-- Deterministic anchors only. The live FontStrings hold secrets and are permanently
-- unmeasurable, so nothing here may derive from their rendered geometry.
local function applyLayout()
    if not frame then return end
    pctFS:ClearAllPoints()
    valFS:ClearAllPoints()
    symbolFS:ClearAllPoints()
    nameFS:ClearAllPoints()
    -- 0.85 em, not the 1.2 em line height: digits have no descenders, so most of
    -- a full line box is empty space below the baseline. Using cap-height-ish
    -- spacing tucks the value row up against the percent digits (the sandwiched
    -- look the UFZ spec wants). cfg.gap fine-tunes from there; negative is legal.
    -- With digit mode on the row reserves space for the LARGEST digit size, so a
    -- big one-digit rendering never overlaps the value row. Still static config --
    -- the reserve never moves per tick; the sandwich just sits a little looser
    -- under the small three-digit rendering.
    local pctGlyphMax = cfg.pctSize
    if cfg.digits then
        pctGlyphMax = math.max(cfg.pctSize, cfg.digitSize1, cfg.digitSize2, cfg.digitSize3)
    end
    local pctRowH = math.ceil(pctGlyphMax * 0.85)
    -- The name centers on the GAP between the two number rows (the boundary at
    -- -pctRowH plus half the gap), not the whole stack's midline -- so neither
    -- the value row's size nor the digit count ever moves it. The name's near
    -- edge sits nameOffset px in from the same frame edge the numbers hang
    -- from, so the visual gap tracks the rendered number width (secret, never
    -- measured) rather than the arbitrary drag-box width; its RIGHT/LEFT point
    -- centers the line box on that midline, and nameY nudges from there
    -- (+ = up, the optical compensator for descender space in the line box).
    local nameMidY = -(pctRowH + cfg.gap / 2) + cfg.nameY
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
        -- size, fixed TOP anchor); the percent is bottom-aligned: its BOTTOM
        -- anchor rides the boundary, pinning the ink bottom at every size (the
        -- rect hugs the ink -- measured in-game; cfg.descent adds size-
        -- proportional lift only if a residual breathe shows). The old TOP
        -- anchor made the gap grow at "100": a smaller point size means a
        -- shorter line box, so the ink ended higher above the value row.
        local lift = math.floor(currentPctPoint() * cfg.descent + 0.5)
        pctFS:SetPoint("BOTTOM", frame, edge, dx, -pctRowH - lift)
        valFS:SetPoint("TOP", frame, edge, dx, -(pctRowH + cfg.gap))
        -- The digits' trailing edge is secret-width: same experiment left mode runs.
        symbolFS:SetPoint("BOTTOMLEFT", pctFS, "BOTTOMRIGHT", cfg.symbolGap, 0)
        if cfg.align == "left" then
            nameFS:SetJustifyH("LEFT")
            nameFS:SetPoint("LEFT", frame, "TOPLEFT", cfg.nameOffset, nameMidY)
        else
            nameFS:SetJustifyH("RIGHT")
            nameFS:SetPoint("RIGHT", frame, "TOPRIGHT", -cfg.nameOffset, nameMidY)
        end
    elseif cfg.align == "left" then
        pctFS:SetJustifyH("LEFT")
        valFS:SetJustifyH("LEFT")
        pctFS:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
        valFS:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -(pctRowH + cfg.gap))
        nameFS:SetJustifyH("LEFT")
        nameFS:SetPoint("LEFT", frame, "TOPLEFT", cfg.nameOffset, nameMidY)
        -- EXPERIMENT: the digits' right edge is secret-width. Anchor resolution is
        -- engine-side, so this may render correctly anyway -- observe via 'report',
        -- do not "fix". Right mode below is the deterministic layout.
        symbolFS:SetPoint("BOTTOMLEFT", pctFS, "BOTTOMRIGHT", cfg.symbolGap, 0)
    else
        pctFS:SetJustifyH("RIGHT")
        valFS:SetJustifyH("RIGHT")
        if cfg.symbol then
            -- The '%' owns the rightmost slot at a fixed frame anchor; the digits end
            -- flush against its left edge. No secret geometry involved.
            symbolFS:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -(cfg.pctSize - cfg.symbolSize))
            pctFS:SetPoint("TOPRIGHT", symbolFS, "TOPLEFT", -cfg.symbolGap, cfg.pctSize - cfg.symbolSize)
        else
            pctFS:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
        end
        valFS:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -(pctRowH + cfg.gap))
        nameFS:SetJustifyH("RIGHT")
        nameFS:SetPoint("RIGHT", frame, "TOPRIGHT", -cfg.nameOffset, nameMidY)
    end
    symbolFS:SetShown(cfg.symbol and true or false)
    applyStretch()
end

--------------------------------------------------------------------------------
-- Update
--------------------------------------------------------------------------------

local function applyColor()
    if cfg.color == "white" then
        pcall(pctFS.SetTextColor, pctFS, 1, 1, 1, 1)
        pcall(valFS.SetTextColor, valFS, 1, 1, 1, 1)
        pcall(symbolFS.SetTextColor, symbolFS, 1, 1, 1, 1)
        last.color = "white"
        return
    end
    local curve = ensureColorCurve(cfg.color)
    if not curve or not _G.UnitHealthPercent then
        last.color = "curve unavailable"
        return
    end
    local ok, color = pcall(UnitHealthPercent, cfg.unit, true, curve)
    if not ok or not color then
        last.color = "eval failed"
        return
    end
    if type(color) == "number" or not color.GetRGB then
        last.color = "not a color object"
        return
    end
    local r, g, b = color:GetRGB()
    pcall(pctFS.SetTextColor, pctFS, r, g, b, 1)
    pcall(valFS.SetTextColor, valFS, r, g, b, 1)
    pcall(symbolFS.SetTextColor, symbolFS, r, g, b, 1)
    last.color = "curve (" .. cfg.color .. ")"
end

--------------------------------------------------------------------------------
-- The name row. Rules from docs/unitframesZ/unitNames.md: gradient start is the
-- class color darkened 25%, end is the hand-picked class endpoint lightened 10%
-- (the CastBar X treatment), applied per-character -- which needs readable text,
-- so a secret name renders raw in solid white (the documented fallback, not a
-- failure). Gradient eligibility gates on UnitIsPlayer, never on class-token
-- resolution: NPCs carry real class tokens. Readable NPC names get the neutral
-- white-to-grey placeholder ramp nametext.lua uses.
--
-- update() never touches this FontString: health ticks must not rebuild the
-- ramp. Name refresh is event- and command-driven only.
--------------------------------------------------------------------------------

local NPC_RAMP_START = { 1, 1, 1 }
local NPC_RAMP_END   = { 0.62, 0.64, 0.68 }

local function refreshName()
    if not nameFS then return end
    -- ClearText before every SetText (readable->secret unit switches need the
    -- Text aspect released), and white first: |cff codes multiply against the
    -- text color, and every non-ramp path below wants white anyway.
    if nameFS.ClearText then nameFS:ClearText() end
    pcall(nameFS.SetTextColor, nameFS, 1, 1, 1, 1)

    local okEx, ex = pcall(UnitExists, cfg.unit)
    local exSecret = okEx and issecretvalue and issecretvalue(ex)
    if not okEx or (not exSecret and ex == false) then
        last.name = "no unit"
        return
    end

    local okN, name = pcall(UnitName, cfg.unit)
    if not okN or type(name) == "nil" then
        last.name = "no name"
        return
    end
    local readable = type(name) == "string" and not (issecretvalue and issecretvalue(name))
    if not readable then
        -- Per-character ramps are permanently impossible on secret text.
        pcall(nameFS.SetText, nameFS, name)
        last.name = "secret (solid white)"
        return
    end

    local isPlayer = cfg.unit == "player"
    if not isPlayer then
        local okP, p = pcall(UnitIsPlayer, cfg.unit)
        isPlayer = okP and not (issecretvalue and issecretvalue(p)) and p == true
    end

    local r1, g1, b1, r2, g2, b2
    if isPlayer then
        local token = addon.GetClassTokenForUnit(cfg.unit)
        local cr, cg, cb = addon.GetClassColorRGB(token)
        if not (token and cr) then
            pcall(nameFS.SetText, nameFS, name)
            last.name = "no class color (solid white)"
            return
        end
        r1, g1, b1 = addon.DarkenColor(cr, cg, cb, 0.25)
        local ep = addon.CLASS_GRADIENT_ENDPOINTS and addon.CLASS_GRADIENT_ENDPOINTS[token]
        if ep then
            r2, g2, b2 = addon.LightenColor(ep[1], ep[2], ep[3], 0.10)
        else
            r2, g2, b2 = addon.LightenColor(cr, cg, cb, 0.45)
        end
        last.name = "class ramp (" .. tostring(token) .. ")"
    else
        r1, g1, b1 = NPC_RAMP_START[1], NPC_RAMP_START[2], NPC_RAMP_START[3]
        r2, g2, b2 = NPC_RAMP_END[1], NPC_RAMP_END[2], NPC_RAMP_END[3]
        last.name = "NPC ramp"
    end
    pcall(nameFS.SetText, nameFS, addon.BuildColorRampString(name, r1, g1, b1, r2, g2, b2))
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
local function readDigitCount()
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

local function probeDigits()
    probePending = false
    if not frame or not frame:IsShown() or not cfg.digits then return end
    local count, tag = readDigitCount()
    if count then
        probeRetries = 0
        last.digits = string.format("count=%d -> size %d", count, cfg["digitSize" .. count])
        if count ~= lastDigitCount then
            lastDigitCount = count
            applyFonts()
            -- With a descent lift in play the BOTTOM anchor tracks the point
            -- size, so re-anchor. At descent 0 the anchor is static -- skip the
            -- churn (applyLayout restarts the stretch animations).
            if cfg.descent > 0 then applyLayout() end
        end
        return
    end
    if tag == "saturated" and probeRetries < 3 then
        -- Unit events dispatch before timers within a frame, so a second health
        -- tick can rewrite the ruler after this probe was scheduled. Waiting for
        -- the next event instead of retrying would strand a stale size at exactly
        -- the quiet moments (heal-to-full ending combat).
        probeRetries = probeRetries + 1
        probePending = true
        last.digits = "saturated (retry " .. probeRetries .. ")"
        C_Timer.After(0, probeDigits)
        return
    end
    probeRetries = 0
    last.digits = tag or "?"
end

-- Coalesced: one pending probe at a time; a retry chain in flight keeps its slot.
local function scheduleDigitProbe()
    if probePending or not cfg.digits then return end
    probePending = true
    probeRetries = 0
    C_Timer.After(0, probeDigits)
end

local function update()
    if not frame or not frame:IsShown() then return end

    -- "No unit" only when UnitExists comes back a readable false. Never boolean-test
    -- a possibly-secret return.
    local okEx, ex = pcall(UnitExists, cfg.unit)
    local exSecret = okEx and issecretvalue and issecretvalue(ex)
    if not okEx or (not exSecret and ex == false) then
        if pctFS.ClearText then pctFS:ClearText() end
        if valFS.ClearText then valFS:ClearText() end
        pcall(pctFS.SetText, pctFS, "--")
        pcall(pctFS.SetTextColor, pctFS, 1, 1, 1, 1)
        last.pct, last.val = "no unit", "no unit"
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
        local ok, num = pcall(UnitHealthPercent, cfg.unit, cfg.usePredicted, curve)
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

    -- Feed the digit ruler only from a successful chain. The "--" no-unit path and
    -- the probe command never touch it, so nothing else can contaminate the count.
    if cfg.digits and pctStr and rulerFS then
        if rulerFS.ClearText then rulerFS:ClearText() end
        pcall(rulerFS.SetText, rulerFS, pctStr)
        scheduleDigitProbe()
    end

    -- Value.
    if valFS.ClearText then valFS:ClearText() end
    last.val = "?"
    if not abbrevBuildTried then rebuildAbbrevConfig() end
    local okH, hp = pcall(UnitHealth, cfg.unit)
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

    applyColor()
end

--------------------------------------------------------------------------------
-- Frame
--------------------------------------------------------------------------------

local UNIT_EVENTS = { "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_HEAL_PREDICTION", "UNIT_NAME_UPDATE" }

-- Re-registering a unit event replaces its unit filter, so a unit switch is a
-- plain re-register of the whole list.
local function registerUnitEvents()
    if not frame then return end
    for _, ev in ipairs(UNIT_EVENTS) do
        pcall(frame.RegisterUnitEvent, frame, ev, cfg.unit)
    end
end

local function ensureFrame()
    if frame then return frame end

    frame = CreateFrame("Frame", "ScootHealthTextTest", UIParent)
    frame:SetSize(cfg.width, cfg.height)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, -180)
    frame:SetFrameStrata("HIGH")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)

    -- No backdrop by design: the numbers are judged against the world behind them.
    -- Built anyway and left hidden because an invisible frame cannot be dragged.
    chromeBG = frame:CreateTexture(nil, "BACKGROUND")
    chromeBG:SetAllPoints()
    chromeBG:SetColorTexture(0, 0, 0, 0.55)
    chromeBG:SetShown(cfg.chrome)

    pctFS = frame:CreateFontString(nil, "OVERLAY")
    valFS = frame:CreateFontString(nil, "OVERLAY")
    symbolFS = frame:CreateFontString(nil, "OVERLAY")
    nameFS = frame:CreateFontString(nil, "OVERLAY")

    -- The digit ruler: free-standing (single point => natural width), so the oracle
    -- reports the true string length; one fixed font set ONCE and never touched
    -- again -- the count is font-independent on an unconstrained FontString, and
    -- never re-fonting removes the main source of saturated reads. Alpha 0 but
    -- SHOWN: a hidden region may skip layout entirely, and a layout-sensitive
    -- oracle would then answer about nothing (the nametext probe-ruler finding).
    local rulerHolder = CreateFrame("Frame", nil, UIParent)
    rulerHolder:SetSize(1, 1)
    rulerHolder:SetPoint("CENTER", UIParent, "CENTER", 0, -320)
    rulerHolder:SetAlpha(0)
    rulerFS = rulerHolder:CreateFontString(nil, "OVERLAY")
    rulerFS:SetPoint("CENTER", rulerHolder, "CENTER", 0, 0)
    rulerFS:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
    rulerFS:SetWordWrap(false)
    -- Fonts before any SetText: a template-less FontString has no font object at all
    -- (same reason as nametext.lua and the measurement ruler).
    applyFonts()
    symbolFS:SetText("%")
    -- Single line: ramped strings and word wrap disagree (colorramp.lua) and the
    -- midline centering assumes one line box.
    nameFS:SetWordWrap(false)
    applyLayout()
    refreshName()

    registerUnitEvents()
    frame:RegisterEvent("PLAYER_TARGET_CHANGED")
    frame:RegisterEvent("PLAYER_FOCUS_CHANGED")
    frame:SetScript("OnEvent", function(_, event)
        if event == "UNIT_NAME_UPDATE" then
            -- Late name arrival for the watched unit (RegisterUnitEvent filters
            -- to cfg.unit). Name only; health has its own events.
            refreshName()
            return
        end
        if event == "PLAYER_TARGET_CHANGED" and cfg.unit ~= "target" then return end
        if event == "PLAYER_FOCUS_CHANGED" and cfg.unit ~= "focus" then return end
        update()
        if event == "PLAYER_TARGET_CHANGED" or event == "PLAYER_FOCUS_CHANGED" then
            refreshName()
        end
    end)

    -- CreateFrame returns a shown frame; start hidden so the first toggle reveals it.
    frame:Hide()

    return frame
end

-- A never-laid-out region cannot be trusted, so every mutator shows the harness
-- rather than silently styling a hidden box.
local function ensureShown()
    ensureFrame()
    if not frame:IsShown() then frame:Show() end
    return frame
end

--------------------------------------------------------------------------------
-- Commands
--------------------------------------------------------------------------------

function addon.DebugHealthTextToggle()
    ensureFrame()
    if frame:IsShown() then
        frame:Hide()
        addon:Print("Health text harness hidden.")
        return
    end
    frame:Show()
    update()
    refreshName()
    addon:Print("Health block shown (no backdrop by design - '/scoot debug healthtext chrome' to drag it).")
    addon:Print("Start with: /scoot debug healthtext probe")
end

-- Read-only snapshot of the current config, for the temporary font-switcher
-- block in the settings panel's Debug Menu. cfg holds plain values only, so
-- nothing secret can leak through this.
function addon.DebugHealthTextGetConfig()
    local snapshot = {}
    for k, v in pairs(cfg) do snapshot[k] = v end
    return snapshot
end

function addon.DebugHealthTextSetUnit(u)
    ensureShown()
    u = tostring(u or ""):lower()
    if u ~= "player" and u ~= "target" and u ~= "focus" then
        addon:Print("Unit must be one of: player | target | focus")
        return
    end
    cfg.unit = u
    lastDigitCount = nil
    registerUnitEvents()
    update()
    refreshName()
    addon:Print("Unit: " .. cfg.unit)
end

-- The applied-vs-requested check exists because both failure modes here are
-- silent: an unknown key makes ResolveFontFace fall back to the default face,
-- and SetFont on a file the client has not loaded fails inside a pcall. Either
-- way the harness would print success while rendering Friz Quadrata.
--
-- The read-back is deferred and then re-checked a frame later: GetFont reports
-- the OLD face for about a frame after SetFont touches a fresh file (the same
-- settling the nametext caseprobe hit), so a same-frame check fired a false
-- warning naming the previous font on every first switch to a new face.
local function verifyAppliedFace(fs, wantedFn)
    fs = fs or pctFS
    wantedFn = wantedFn or function() return addon.ResolveFontFace(cfg.face) end
    local wanted = wantedFn()
    if type(wanted) ~= "string" then return end
    local function check(finalCheck)
        -- Stale guard: the user may have switched faces again while we waited.
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

function addon.DebugHealthTextSetFont(face)
    ensureShown()
    if face and face ~= "" then cfg.face = face end
    local isPath = type(cfg.face) == "string" and cfg.face:find("[/\\]") ~= nil
    local isLSM = addon.IsLSMKey and addon.IsLSMKey(cfg.face)
    if not isPath and not isLSM and not addon.Fonts[cfg.face] then
        addon:Print("Warning: '" .. cfg.face .. "' is not in this session's font registry, so the resolver falls back to the default face. Registry changes need /reload; new font files need a full client restart.")
    end
    applyFonts()
    applyLayout()
    update()
    refreshName()
    verifyAppliedFace()
    addon:Print("Font face: " .. cfg.face)
end

function addon.DebugHealthTextSetStyle(style)
    ensureShown()
    if style and style ~= "" then cfg.style = style end
    applyFonts()
    applyLayout()
    update()
    refreshName()
    addon:Print("Style: " .. cfg.style)
end

function addon.DebugHealthTextSetPctSize(n)
    ensureShown()
    cfg.pctSize = math.max(1, math.floor(tonumber(n) or cfg.pctSize))
    applyFonts()
    applyLayout()
    update()
    addon:Print("Percent size: " .. cfg.pctSize)
    if cfg.digits then
        addon:Print("Note: digit mode is on, so the rendered size comes from digitsize 1/2/3; pct sets row geometry and the digits-off fallback.")
    end
end

function addon.DebugHealthTextSetValSize(n)
    ensureShown()
    -- Half-point steps: the ratio hunt trades point size against squish level,
    -- and whole-point jumps are too coarse near the match point.
    local v = tonumber(n) or cfg.valSize
    cfg.valSize = math.max(1, math.floor(v * 2 + 0.5) / 2)
    applyFonts()
    applyLayout()
    update()
    addon:Print(string.format("Value size: %g", cfg.valSize))
end

-- The resolved value face for read-back verification and the report: the
-- squish-derived TALL key when one is active AND registered for the current
-- family, else the explicit valFace, else the main face.
local function resolveValFace()
    local key = valOverrideKey()
    return addon.ResolveFontFace(key ~= "follow" and key or cfg.face)
end

-- Human-readable account of how the value face resolved, for report/prints.
local function describeValFace()
    if cfg.valSquish ~= "off" then
        local key = faceFamily(cfg.face) .. "_TALL_" .. cfg.valSquish
        if addon.Fonts and addon.Fonts[key] then
            return string.format("squish %s -> %s", cfg.valSquish, key)
        end
        return string.format("squish %s (no tall bakes for family %s -- using %s)",
            cfg.valSquish, faceFamily(cfg.face), cfg.valFace)
    end
    return "off -> " .. cfg.valFace
end

function addon.DebugHealthTextSetValFont(face)
    ensureShown()
    if not face or face == "" then
        addon:Print("Usage: /scoot debug healthtext valfont <FACE|follow>   (current: " .. describeValFace() .. ")")
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
    -- An explicit face (or an explicit follow) beats the derived tall bake.
    cfg.valSquish = "off"
    applyFonts()
    verifyAppliedFace(valFS, resolveValFace)
    addon:Print("Value face: " .. describeValFace())
end

-- Squish front-end: maps a level to the current family's cap-pinned TALL bake
-- (ink shrinks upward from a fixed top, so the gap to the percent row above
-- never moves with the level). Family-matched: switching the main face
-- re-derives the tall face on the next applyFonts with no re-selection.
function addon.DebugHealthTextSetValSquish(v)
    v = tostring(v or ""):lower()
    if v == "follow" then v = "off" end
    if v ~= "off" and v ~= "90" and v ~= "80" and v ~= "70" then
        addon:Print("Usage: /scoot debug healthtext valsquish <90|80|70|off>   (glyph height as a percent of full)")
        return
    end
    ensureShown()
    cfg.valSquish = v
    applyFonts()
    verifyAppliedFace(valFS, resolveValFace)
    addon:Print("Value face: " .. describeValFace())
end

function addon.DebugHealthTextSetDescent(n)
    ensureShown()
    local r = tonumber(n)
    if not r then
        addon:Print(string.format("Usage: /scoot debug healthtext descent <ratio>   (current: %.3f; rect-bottom-to-baseline share of the percent size)", cfg.descent))
        return
    end
    cfg.descent = math.max(0, math.min(1, r))
    applyLayout()
    addon:Print(string.format("Descent ratio: %.3f -- the percent/value gap should now hold steady across 1/2/3-digit sizes; nudge until it does.", cfg.descent))
end

function addon.DebugHealthTextSetGap(n)
    ensureShown()
    -- Fractional gaps are legal: under a fractional UI scale a 0.1 px anchor
    -- offset can land on a different physical pixel, so sub-px steps are the
    -- fine-tuning knob (snapped to 0.1 to keep the report readable).
    local v = tonumber(n) or cfg.gap
    cfg.gap = math.floor(v * 10 + 0.5) / 10
    applyLayout()
    update()
    addon:Print(string.format("Row gap: %.1f", cfg.gap))
end

function addon.DebugHealthTextSetCenter(state)
    ensureShown()
    state = tostring(state or ""):lower()
    if state ~= "on" and state ~= "off" then
        addon:Print("Usage: /scoot debug healthtext center <on|off>")
        return
    end
    cfg.center = (state == "on")
    applyLayout()
    update()
    if cfg.center then
        addon:Print("Center: on (centerline " .. cfg.centerOffset .. "px in from the " .. cfg.align .. " edge; tune with centeroffset)")
    else
        addon:Print("Center: off (edge-justified)")
    end
end

function addon.DebugHealthTextSetCenterOffset(n)
    ensureShown()
    cfg.centerOffset = math.floor(tonumber(n) or cfg.centerOffset)
    applyLayout()
    addon:Print("Center offset: " .. cfg.centerOffset)
end

function addon.DebugHealthTextSetDigits(state)
    ensureShown()
    state = tostring(state or ""):lower()
    if state ~= "on" and state ~= "off" then
        addon:Print("Usage: /scoot debug healthtext digits <on|off>")
        return
    end
    cfg.digits = (state == "on")
    lastDigitCount = nil
    applyFonts()
    applyLayout()
    update()
    if cfg.digits then
        addon:Print(string.format("Digit mode: on (sizes %d/%d/%d for 1/2/3 digits; validate with digitprobe)",
            cfg.digitSize1, cfg.digitSize2, cfg.digitSize3))
    else
        addon:Print("Digit mode: off (static size " .. cfg.pctSize .. ")")
    end
end

function addon.DebugHealthTextSetDigitSize(which, size)
    ensureShown()
    local n = tonumber(which)
    if n ~= 1 and n ~= 2 and n ~= 3 then
        addon:Print("Usage: /scoot debug healthtext digitsize <1|2|3> <size>")
        return
    end
    local key = "digitSize" .. n
    cfg[key] = math.max(1, math.floor(tonumber(size) or cfg[key]))
    -- applyFonts so a change to the currently rendered count lands now; applyLayout
    -- because the row reserve tracks the largest digit size.
    applyFonts()
    applyLayout()
    addon:Print(string.format("Digit size %d: %d", n, cfg[key]))
end

function addon.DebugHealthTextSetNameSize(n)
    ensureShown()
    cfg.nameSize = math.max(1, math.floor(tonumber(n) or cfg.nameSize))
    -- No applyLayout: the name's anchor sits on the row-gap midline, which is
    -- name-size-independent by design.
    applyFonts()
    refreshName()
    addon:Print("Name size: " .. cfg.nameSize)
end

function addon.DebugHealthTextSetNameFont(face)
    ensureShown()
    if not face or face == "" then
        addon:Print("Usage: /scoot debug healthtext namefont <FACE|follow>   (current: " .. cfg.nameFace .. ")")
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
    applyFonts()
    refreshName()
    addon:Print("Name face: " .. cfg.nameFace)
end

function addon.DebugHealthTextSetNameOffset(n)
    ensureShown()
    cfg.nameOffset = math.floor(tonumber(n) or cfg.nameOffset)
    applyLayout()
    addon:Print("Name offset: " .. cfg.nameOffset)
end

function addon.DebugHealthTextSetNameY(n)
    ensureShown()
    cfg.nameY = math.floor(tonumber(n) or cfg.nameY)
    applyLayout()
    addon:Print("Name Y nudge: " .. cfg.nameY .. " (+ = up)")
end

function addon.DebugHealthTextSetStretch(n)
    ensureShown()
    local fx = tonumber(n)
    if not fx then
        addon:Print("Usage: /scoot debug healthtext stretch <factor>   (1 = off; e.g. 1.35)")
        return
    end
    cfg.stretch = math.max(0.5, math.min(3, fx))
    applyStretch()
    addon:Print(string.format("Stretch: %.2fx wide%s", cfg.stretch, cfg.stretch == 1 and " (off)" or ""))
end

function addon.DebugHealthTextSetSymbol(state, size)
    ensureShown()
    state = tostring(state or ""):lower()
    if state == "on" then
        cfg.symbol = true
    elseif state == "off" then
        cfg.symbol = false
    else
        addon:Print("Usage: /scoot debug healthtext symbol <on|off> [size]")
        return
    end
    if size then
        cfg.symbolSize = math.max(1, math.floor(tonumber(size) or cfg.symbolSize))
    end
    applyFonts()
    applyLayout()
    update()
    if cfg.symbol and cfg.align == "left" then
        addon:Print("Left mode with symbol on anchors '%' to a secret-width edge (the experiment). Check 'report'.")
    end
    addon:Print(string.format("Symbol: %s (size %d)", cfg.symbol and "on" or "off", cfg.symbolSize))
end

function addon.DebugHealthTextSetAlign(a)
    ensureShown()
    a = tostring(a or ""):lower()
    if a ~= "right" and a ~= "left" then
        addon:Print("Align must be one of: right | left")
        return
    end
    cfg.align = a
    applyLayout()
    update()
    if cfg.symbol and cfg.align == "left" then
        addon:Print("Left mode with symbol on anchors '%' to a secret-width edge (the experiment). Check 'report'.")
    end
    addon:Print("Align: " .. cfg.align)
end

function addon.DebugHealthTextSetColor(m)
    ensureShown()
    m = tostring(m or ""):lower()
    if m ~= "curve" and m ~= "dark" and m ~= "white" then
        addon:Print("Color must be one of: curve | dark | white")
        return
    end
    cfg.color = m
    update()
    addon:Print("Color: " .. cfg.color)
end

function addon.DebugHealthTextSetRound(m)
    ensureShown()
    m = tostring(m or ""):lower()
    if m ~= "floor" and m ~= "round" then
        addon:Print("Round must be one of: floor | round")
        return
    end
    cfg.round = m
    update()
    addon:Print("Percent rounding: " .. cfg.round)
end

function addon.DebugHealthTextToggleChrome()
    ensureShown()
    cfg.chrome = not cfg.chrome
    chromeBG:SetShown(cfg.chrome)
    addon:Print("Chrome: " .. (cfg.chrome and "on (drag the box)" or "off"))
end

function addon.DebugHealthTextReset()
    ensureShown()
    for k, v in pairs(DEFAULTS) do cfg[k] = v end
    lastDigitCount = nil
    chromeBG:SetShown(cfg.chrome)
    registerUnitEvents()
    applyFonts()
    applyLayout()
    update()
    refreshName()
    addon:Print("Health text harness reset to defaults.")
end

--------------------------------------------------------------------------------
-- Report / measure / probe (window dumps carry verdicts only, never secrets --
-- DebugShowWindow table.concat's the payload and a secret line would error it)
--------------------------------------------------------------------------------

function addon.DebugHealthTextReport()
    ensureFrame()
    local out = {}
    out[#out + 1] = "cfg:"
    local keys = {}
    for k in pairs(cfg) do keys[#keys + 1] = k end
    table.sort(keys)
    for _, k in ipairs(keys) do
        out[#out + 1] = string.format("  %-13s %s", k, tostring(cfg[k]))
    end
    out[#out + 1] = ""
    out[#out + 1] = "resolved face: " .. tostring(addon.ResolveFontFace(cfg.face))
    out[#out + 1] = "name face:     " .. tostring(addon.ResolveFontFace(cfg.nameFace ~= "follow" and cfg.nameFace or cfg.face))
    out[#out + 1] = "value face:    " .. describeValFace() .. " = " .. tostring(resolveValFace())
    local okF, appliedF = pcall(pctFS.GetFont, pctFS)
    if okF and type(appliedF) == "string" and not (issecretvalue and issecretvalue(appliedF)) then
        out[#out + 1] = "applied face:  " .. appliedF
    else
        out[#out + 1] = "applied face:  unknown"
    end
    out[#out + 1] = ""
    out[#out + 1] = "frame: " .. (frame:IsShown() and "shown" or "hidden")
    if abbrevOpts then
        out[#out + 1] = "abbrev config: built (" .. tostring(abbrevTier) .. ")"
    else
        out[#out + 1] = "abbrev config: " .. (abbrevBuildTried and "FAILED" or "not built yet")
    end
    if abbrevError then
        out[#out + 1] = "abbrev error: " .. abbrevError
        out[#out + 1] = "  bitmask: " .. ABBREV_BITMASK_LEGEND
    end
    out[#out + 1] = ""
    out[#out + 1] = "last update:"
    out[#out + 1] = "  percent: " .. tostring(last.pct)
    out[#out + 1] = "  value:   " .. tostring(last.val)
    out[#out + 1] = "  color:   " .. tostring(last.color)
    out[#out + 1] = "  name:    " .. tostring(last.name)
    out[#out + 1] = "  digits:  " .. tostring(last.digits)
    out[#out + 1] = ""
    out[#out + 1] = "digit cache: count=" .. tostring(lastDigitCount)
        .. string.format("  (sizes %d/%d/%d)", cfg.digitSize1, cfg.digitSize2, cfg.digitSize3)
    out[#out + 1] = string.format("pct anchor: point=%d  baseline lift=%d  (descent %.3f)",
        currentPctPoint(), math.floor(currentPctPoint() * cfg.descent + 0.5), cfg.descent)
    out[#out + 1] = ""
    out[#out + 1] = "IsAnchoringSecret (misnamed: reports 'holds any secret aspect'):"
    local fsEntries = { { "pctFS", pctFS }, { "valFS", valFS }, { "symbolFS", symbolFS }, { "nameFS", nameFS }, { "rulerFS", rulerFS } }
    for _, e in ipairs(fsEntries) do
        local fs, v = e[2], "n/a"
        if fs and fs.IsAnchoringSecret then
            local ok, r = pcall(fs.IsAnchoringSecret, fs)
            if not ok then
                v = "error"
            elseif issecretvalue and issecretvalue(r) then
                v = "secret"
            else
                v = tostring(r)
            end
        end
        out[#out + 1] = string.format("  %-9s %s", e[1], v)
    end
    addon.DebugShowWindow("Health Text Report", out)
end

function addon.DebugHealthTextMeasure()
    ensureShown()
    local face = addon.ResolveFontFace(cfg.face)
    local valFace = resolveValFace()
    local function w(text, size, f)
        local px = addon.MeasureTextWidth and addon.MeasureTextWidth(text, f or face, size, cfg.style)
        return px and string.format("%.1f", px) or "n/a"
    end
    local out = {}
    out[#out + 1] = string.format("Face %s, style %s (plain samples on the shared ruler;", cfg.face, cfg.style)
    out[#out + 1] = "the live FontStrings hold secrets and cannot be measured)"
    if (cfg.stretch or 1) ~= 1 then
        out[#out + 1] = string.format("NOTE: stretch %.2fx is active; on-screen widths are these values times %.2f.", cfg.stretch, cfg.stretch)
    end
    out[#out + 1] = ""
    out[#out + 1] = string.format("Percent row @ %d:", cfg.pctSize)
    out[#out + 1] = string.format("  1 digit  '9'    %s px", w("9", cfg.pctSize))
    out[#out + 1] = string.format("  2 digits '47'   %s px   <- tuning target", w("47", cfg.pctSize))
    out[#out + 1] = string.format("  3 digits '100'  %s px", w("100", cfg.pctSize))
    out[#out + 1] = string.format("  '%%' glyph @ %d: %s px", cfg.symbolSize, w("%", cfg.symbolSize))
    if cfg.digits then
        out[#out + 1] = ""
        out[#out + 1] = "Digit mode on - the sizes that actually render:"
        out[#out + 1] = string.format("  1 digit  '9'   @ %d: %s px", cfg.digitSize1, w("9", cfg.digitSize1))
        out[#out + 1] = string.format("  2 digits '47'  @ %d: %s px", cfg.digitSize2, w("47", cfg.digitSize2))
        out[#out + 1] = string.format("  3 digits '100' @ %d: %s px", cfg.digitSize3, w("100", cfg.digitSize3))
    end
    out[#out + 1] = ""
    out[#out + 1] = string.format("Tabular check @ %d ('1111' vs '9999'; equal = digit widths are stable):", cfg.pctSize)
    out[#out + 1] = string.format("  '1111' %s px   '9999' %s px", w("1111", cfg.pctSize), w("9999", cfg.pctSize))
    out[#out + 1] = ""
    out[#out + 1] = string.format("Value samples by size (current val size %g marked *; measured with", cfg.valSize)
    out[#out + 1] = string.format("the value face, %s):", tostring(valFace))
    local samples = { "9999", "99.9k", "999k", "1.15m", "10.5m", "105m" }
    for size = 10, 20 do
        local row = {}
        for _, s in ipairs(samples) do
            row[#row + 1] = string.format("%s=%s", s, w(s, size, valFace))
        end
        out[#out + 1] = string.format("%s%2d  %s", size == cfg.valSize and "*" or " ", size, table.concat(row, "  "))
    end
    out[#out + 1] = ""
    out[#out + 1] = "Pick the val size whose 99.9k width matches the 2-digit percent width above;"
    out[#out + 1] = "the widest sample governs the block. Apply with: /scoot debug healthtext val <n>"
    addon.DebugShowWindow("Health Text Measure", out)
end

local function fmtVerdict(label, ok, val)
    if not ok then
        return string.format("[%s] FAILED: %s", label, tostring(val))
    end
    local secret = (issecretvalue and issecretvalue(val)) and "yes" or "no"
    return string.format("[%s] ok  type=%s  secret=%s", label, type(val), secret)
end

local function pointCount(c)
    if not (c and c.GetPointCount) then return "?" end
    local ok, n = pcall(c.GetPointCount, c)
    return ok and tostring(n) or "?"
end

function addon.DebugHealthTextProbe()
    ensureShown()
    local unit = cfg.unit
    local out = {}
    out[#out + 1] = "Health text probe - unit: " .. unit
    out[#out + 1] = "Verdicts only; the rendered secrets appear on the harness frame itself."
    out[#out + 1] = ""

    local apis = {
        { "issecretvalue", _G.issecretvalue },
        { "C_CurveUtil.CreateCurve", _G.C_CurveUtil and _G.C_CurveUtil.CreateCurve },
        { "C_CurveUtil.CreateColorCurve", _G.C_CurveUtil and _G.C_CurveUtil.CreateColorCurve },
        { "UnitHealthPercent", _G.UnitHealthPercent },
        { "C_StringUtil.FloorToNearestString", _G.C_StringUtil and _G.C_StringUtil.FloorToNearestString },
        { "C_StringUtil.RoundToNearestString", _G.C_StringUtil and _G.C_StringUtil.RoundToNearestString },
        { "AbbreviateNumbers", _G.AbbreviateNumbers },
        { "CreateAbbreviateConfig", _G.CreateAbbreviateConfig },
    }
    for _, api in ipairs(apis) do
        out[#out + 1] = string.format("[P0] %-36s %s", api[1], api[2] and "present" or "MISSING")
    end
    out[#out + 1] = ""

    local okH, hp = pcall(UnitHealth, unit)
    out[#out + 1] = fmtVerdict("P1 UnitHealth", okH, hp) .. "   (expect: number, secret=yes)"
    local okM, hpMax = pcall(UnitHealthMax, unit)
    out[#out + 1] = fmtVerdict("P2 UnitHealthMax", okM, hpMax) .. "   (player: expect secret=no)"
    out[#out + 1] = ""

    rebuildAbbrevConfig()
    out[#out + 1] = string.format("[P3] abbrev config: %s", abbrevOpts and ("built (" .. tostring(abbrevTier) .. ")") or "FAILED")
    if abbrevError then
        out[#out + 1] = "     error: " .. abbrevError
        out[#out + 1] = "     bitmask: " .. ABBREV_BITMASK_LEGEND
    end

    if okH and type(hp) == "number" and abbrevOpts and _G.AbbreviateNumbers then
        local okA, abbr = pcall(AbbreviateNumbers, hp, abbrevOpts)
        out[#out + 1] = fmtVerdict("P4 AbbreviateNumbers(health, config)", okA, abbr) .. "   (expect: string, secret=yes)"
        if okA and type(abbr) == "string" then
            if valFS.ClearText then valFS:ClearText() end
            local okS = pcall(valFS.SetText, valFS, abbr)
            out[#out + 1] = string.format("[P5] valFS:SetText(secret): %s", okS and "ok" or "FAILED")
        end
    else
        out[#out + 1] = "[P4] skipped (no health number or no config)"
    end
    out[#out + 1] = ""

    local function buildNumericCurve(x0, y0, x1, y1)
        if not (_G.C_CurveUtil and _G.C_CurveUtil.CreateCurve) then return nil, "C_CurveUtil.CreateCurve missing" end
        local ok, c = pcall(C_CurveUtil.CreateCurve)
        if not ok or not c then return nil, tostring(c) end
        if c.SetType and _G.Enum and _G.Enum.LuaCurveType then
            pcall(c.SetType, c, Enum.LuaCurveType.Linear)
        end
        local ok1 = pcall(c.AddPoint, c, x0, y0)
        local ok2 = pcall(c.AddPoint, c, x1, y1)
        if not (ok1 and ok2) then return nil, "AddPoint failed" end
        return c
    end

    local curveA, errA = buildNumericCurve(0, 0, 1, 100)
    out[#out + 1] = string.format("[P6] curveA (0,0)-(1,100): %s",
        curveA and ("built, points=" .. pointCount(curveA)) or ("FAILED: " .. tostring(errA)))
    local curveB, errB = buildNumericCurve(0, 0, 100, 100)
    out[#out + 1] = string.format("[P7] curveB (0,0)-(100,100): %s",
        curveB and ("built, points=" .. pointCount(curveB)) or ("FAILED: " .. tostring(errB)))

    local okP8, p8 = pcall(UnitHealthPercent, unit, true)
    out[#out + 1] = fmtVerdict("P8 UnitHealthPercent(unit, true)", okP8, p8) .. "   (expect: number, secret=yes)"

    local okP9, p9 = false, nil
    if curveA then
        okP9, p9 = pcall(UnitHealthPercent, unit, true, curveA)
        out[#out + 1] = fmtVerdict("P9 UnitHealthPercent(unit, true, curveA)", okP9, p9)
            .. "   << THE UNPROVEN LINK (expect: number, secret=yes)"
    else
        out[#out + 1] = "[P9] skipped (no curveA)"
    end

    if okP9 and type(p9) ~= "nil" and _G.C_StringUtil then
        if _G.C_StringUtil.FloorToNearestString then
            local ok10, s10 = pcall(C_StringUtil.FloorToNearestString, p9)
            out[#out + 1] = fmtVerdict("P10 FloorToNearestString(P9)", ok10, s10) .. "   (expect: string, secret=yes)"
        end
        if _G.C_StringUtil.RoundToNearestString then
            local ok11, s11 = pcall(C_StringUtil.RoundToNearestString, p9)
            out[#out + 1] = fmtVerdict("P11 RoundToNearestString(P9)", ok11, s11)
        end
        if abbrevOpts and _G.AbbreviateNumbers then
            local ok12, s12 = pcall(AbbreviateNumbers, p9, abbrevOpts)
            out[#out + 1] = fmtVerdict("P12 AbbreviateNumbers(P9, config) [fallback]", ok12, s12)
        end
    end

    if curveA and curveB and okP9 and _G.C_StringUtil and _G.C_StringUtil.FloorToNearestString then
        local okB, pB = pcall(UnitHealthPercent, unit, true, curveB)
        local okSa, sA = pcall(C_StringUtil.FloorToNearestString, p9)
        local okSb, sB = false, nil
        if okB then okSb, sB = pcall(C_StringUtil.FloorToNearestString, pB) end
        if okSa and type(sA) == "string" then
            if pctFS.ClearText then pctFS:ClearText() end
            pcall(pctFS.SetText, pctFS, sA)
        end
        if okSb and type(sB) == "string" then
            if valFS.ClearText then valFS:ClearText() end
            pcall(valFS.SetText, valFS, sB)
        end
        out[#out + 1] = ""
        out[#out + 1] = "[P13] DOMAIN CHECK - look at the harness frame NOW:"
        out[#out + 1] = "  big slot = curveA result, small slot = curveB result."
        out[#out + 1] = "  At full health: big=100 small=1 means the curve input is 0-1 (expected)."
        out[#out + 1] = "  Reversed (big=1 small=100) means the input is 0-100: flip the percent"
        out[#out + 1] = "  curve points to (0,0) and (100,100) in core/debug/healthtext.lua."
        out[#out + 1] = "  (The next health event overwrites both slots - re-run to re-check.)"
    end

    local cCurve = ensureColorCurve("curve")
    if cCurve and _G.UnitHealthPercent then
        local okC, col = pcall(UnitHealthPercent, unit, true, cCurve)
        local desc
        if not okC then
            desc = "FAILED: " .. tostring(col)
        elseif type(col) == "number" then
            desc = "returned a number (unexpected; want a Color)"
        elseif type(col) == "table" or type(col) == "userdata" then
            desc = string.format("ok  type=%s  GetRGB=%s  secret=%s", type(col),
                col.GetRGB and "yes" or "no",
                (issecretvalue and issecretvalue(col)) and "yes" or "no")
        else
            desc = "returned " .. type(col)
        end
        out[#out + 1] = ""
        out[#out + 1] = "[P14] color curve eval: " .. desc .. "   (expect: Color with GetRGB, secret=no)"
    end

    out[#out + 1] = ""
    out[#out + 1] = "SUCCESS = P9 ok+secret number, P10 ok+secret string, P5 ok, and P13 shows"
    out[#out + 1] = "100 in the big slot at full health. If P9 fails, the composed percent chain"
    out[#out + 1] = "is dead by this route; the remaining path is harvesting Blizzard-rendered"
    out[#out + 1] = "text (PRD-style), which is out of scope for this harness."
    addon.DebugShowWindow("Health Text Probe", out)
end

-- The digit-mode validation gate. The SetAlphaGradient oracle is proven on secret
-- NAMES (UnitName); this dumps its raw verdicts against a number-derived secret
-- string (FloorToNearestString) sitting in the ruler. Deliberately does NOT run
-- update() first: a same-frame SetText would saturate the very reads being judged,
-- so it probes whatever the last health tick left in the ruler.
function addon.DebugHealthTextDigitProbe()
    ensureShown()
    local out = {}
    out[#out + 1] = "Digit oracle probe - raw SetAlphaGradient verdicts on the ruler."
    out[#out + 1] = ""
    out[#out + 1] = "digits mode:    " .. (cfg.digits and "on"
        or "OFF - the ruler only feeds while on; toggle on and let a health tick land first")
    out[#out + 1] = "last verdict:   " .. tostring(last.digits)
    out[#out + 1] = "cached count:   " .. tostring(lastDigitCount)
    out[#out + 1] = string.format("sizes 1/2/3:    %d / %d / %d", cfg.digitSize1, cfg.digitSize2, cfg.digitSize3)
    out[#out + 1] = ""
    if not rulerFS or type(rulerFS.SetAlphaGradient) ~= "function" then
        out[#out + 1] = "FontString:SetAlphaGradient is not present - the oracle does not exist."
        addon.DebugShowWindow("Digit Oracle Probe", out)
        return
    end
    for i = 0, 3 do
        local v, tag = alphaProbe(rulerFS, i)
        out[#out + 1] = string.format("probe(%d):       %s", i, v ~= nil and tostring(v) or (tag or "?"))
    end
    clearGradient(rulerFS)
    local count, tag = readDigitCount()
    out[#out + 1] = "inferred count: " .. (count and tostring(count) or ("none (" .. tostring(tag) .. ")"))
    if rulerFS.IsAnchoringSecret then
        local ok, r = pcall(rulerFS.IsAnchoringSecret, rulerFS)
        local v = (not ok and "error")
            or ((issecretvalue and issecretvalue(r)) and "secret")
            or tostring(r)
        out[#out + 1] = "ruler IsAnchoringSecret: " .. v .. "   (true = has held a secret, expected)"
    end
    out[#out + 1] = ""
    out[#out + 1] = "PASS = plain booleans throughout, true up to (digits-1) and false past"
    out[#out + 1] = "it, inferred count matching the digits on screen. A SECRET verdict or"
    out[#out + 1] = "permanent saturation means the oracle does not transfer to number-"
    out[#out + 1] = "derived strings, and digit mode is dead by this route."
    addon.DebugShowWindow("Digit Oracle Probe", out)
end
