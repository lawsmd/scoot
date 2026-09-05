-- debug/nametext.lua - /scoot debug nametext
--
-- The Unit Frames Z name box, built the way it would ship.
--
-- Three rounds of probing settled what is possible on a name the addon is not allowed
-- to read, and this file is now the answer rather than the investigation:
--
--   Sizing      works on secret text, via the SetAlphaGradient character-count oracle.
--               ONE code path for every unit -- a secret NPC name and a party member's
--               name go through exactly the same measurement.
--   Wrapping    works on secret text. The engine breaks at spaces and ellipsizes on
--               overflow whether or not anyone can read the string.
--   Coloring    is the only thing that branches. Per-character |cff gradients are
--               string operations, so they are permanently impossible on a secret
--               name. Players get the class ramp; everything else gets solid white.
--   Appearance  is atomic. Nothing is drawn between a target change and a finished
--               fit: the box is simply empty for three or four frames, then the name
--               appears once, already sized, wrapped and coloured. A name painted
--               before its size is known has to move when the size lands, and a move
--               reads as a bug where a short delay reads as latency.
--
-- The probe subcommands (scan / lengthprobe / fitprobe / autofit) are kept: they are
-- how the above was established, and they are the fastest way to re-check it if a
-- patch changes the rules.
--
-- Everything here is addon-owned and anchored to UIParent with plain numbers. No
-- Blizzard frame is read, written, hooked or anchored to.

local addonName, addon = ...

addon.DebugNameText = addon.DebugNameText or {}
local NT = addon.DebugNameText

-- Defined below, referenced above their definitions.
local DebugNameTextRefresh

local cfg = {
    width    = 150,
    -- Tall enough for one line at maxSize. The line budget is derived from
    -- height/lineHeight per size, so extra lines unlock as the text shrinks.
    height   = 70,
    maxLines = 2,
    minSize  = 9,
    maxSize  = 52,
    -- What renders when the oracle itself fails -- not when the text merely does not
    -- fit. Deliberately NOT maxSize: at maxSize a bail is indistinguishable from a fit
    -- that decided the text already fitted, which is exactly how an earlier round of
    -- testing read as working when nothing had run.
    fallbackSize = 20,
    mode     = "font",
    face     = "ROBOTO_BLACK",
    style    = "SHADOWTHICKOUTLINE",

    -- Safety margin for the oracle's blind spot (see the sizing header). "auto" = the
    -- measured pixel width of "...", a number = that many pixels, "off" = none, which
    -- restores the behaviour that renders 'Chrysalius' as 'Chrysal...'.
    margin   = "auto",

    -- No backdrop, no border. The whole point of this build is to judge the text on
    -- its own, against the world behind it.
    chrome   = false,

    -- Gradient
    gradient    = "auto",   -- auto | off | white | line | block | slice
    slices      = 16,
    forcedClass = nil,      -- nil = read the target's class
    treatment   = "cast",   -- cast (darken start 25%, as CastBar X) | raw
    identity    = "player", -- player (class ramp only for real players) | class

    -- Letter case. See the CASE header below -- the three modes reach the same screen
    -- by two completely different mechanisms, and only one of them touches the string.
    case   = "normal",      -- normal | upper | smallcaps
    scFace = "PIXELOP_SC",  -- the face 'smallcaps' swaps to; the mode IS this font
}
NT._cfg = cfg

-- NPC placeholder ramp: near-white into a light gray.
local NPC_START = { 1.00, 1.00, 1.00 }
local NPC_END   = { 0.62, 0.64, 0.68 }

-- Edge cases that are tedious to find in the world on demand.
local SAMPLES = {
    "Bob",
    "Grand Magistrix Elisande",
    "Hulking Bloodthirsty Blackrock Battlemaster",
    "High General Brashthorn of the Broken Shore Vanguard",
    "Supercalifragilisticexpialidociousaurus",
    "Verylongcharactername-Verylongrealmnamehere",
    -- Heavily accented: 25 bytes but 18 characters, so any index-based API that
    -- reports a length reveals which of the two it counts. Nothing else here
    -- separates them -- every other sample is pure ASCII.
    "Ëlïsändë Vörthälâk",
}

--------------------------------------------------------------------------------
-- CASE: two mechanisms, and the difference between them is the whole point
--------------------------------------------------------------------------------
-- The instinct is that changing a name's case is a string operation, and therefore
-- dead on a secret name for the same reason per-character |cff ramps are dead. That is
-- only half right, and the half that is wrong is the useful half.
--
-- What killed the ramps was never "touching the string". Concatenation, string.format
-- and string.join all accept secrets and hand back a secret result, as the
-- restriction table records. What killed the ramps is that building one requires
-- knowing WHERE THE CHARACTERS ARE: you need #text to count them and text:sub() to cut
-- between them, and both of those are refused. A ramp has to take the string apart.
--
-- string.upper does not. It is a whole-string transform with no index arithmetic and no
-- decision made on content -- exactly the shape of string.format, which is allowed. So
-- whether it works is an open question about Blizzard's whitelist, not a foregone
-- conclusion, and 'upper' below asks the engine rather than assuming. If the answer is
-- no, caseMethod records the refusal and the render falls back to normal case rather
-- than silently doing nothing.
--
-- 'smallcaps' never asks. It swaps to a font whose lowercase codepoints CONTAIN small
-- capital glyphs, so the transform happens in the rasteriser where secrecy has no
-- opinion. It is guaranteed to work on a name nobody can read, and it is also the only
-- route to a first-letter-larger look for ANYONE: WoW's markup has |cff for colour and
-- nothing whatsoever for size, so a single FontString cannot mix two sizes even when
-- the text is fully readable. Two FontStrings cannot do it either -- the slice trick
-- works only because every copy is glyph-identical, and two sizes are not.
--
-- The catch worth seeing on screen: a small-caps font enlarges every letter that was
-- uppercase in the SOURCE string, so 'Penumbral Custodian' comes back with two large
-- letters, not one. Which is a look to judge, not a bug to fix: there is no knowing which
-- letters those are, only that the font will treat them differently.
local function effectiveFaceKey()
    if cfg.case == "smallcaps" then return cfg.scFace end
    return cfg.face
end
NT._EffectiveFaceKey = effectiveFaceKey

local frame, nameFS, chromeBG

local lastResult, lastSource, lastFit
-- currentRaw is what UnitName returned; currentValue is what goes to the
-- rulers and the screen. They differ only when a case transform succeeded, and keeping
-- both is what lets the report say which one you are looking at.
local currentRaw, currentValue, currentIsSecret
local caseMethod, caseError, caseOutSecret
local lastColors, lastLines, lastDiscovery, lastGradientMode, lastGradientNote
local lastRamped
-- Bumped by every render pass and every SetText on the display. A deferred step that
-- finds either number changed is describing a target that is no longer on screen, and
-- finishing it would paint the previous name over the current one.
local renderSeq, paintSeq = 0, 0
-- What applySlices replayed onto the copies, recorded rather than recomputed
-- so the report shows the values that were used, not the values that would be used now.
local lastSliceSize, lastSliceScale, lastSliceMaxLines, lastSliceFallback

--------------------------------------------------------------------------------
-- Safe formatting
--------------------------------------------------------------------------------

local safeStr = NT._SafeStr

-- Report a single measurement API as ok / SECRET / error. This per-API tagging is
-- the deliverable of the harness.
local function measureOn(obj, method)
    if not obj then return "<no fontstring>" end
    local fn = obj[method]
    if type(fn) ~= "function" then return "<API not present>" end
    local ok, v = pcall(fn, obj)
    if not ok then return "<error: " .. safeStr(v) .. ">" end
    if issecretvalue and issecretvalue(v) then return "SECRET" end
    if type(v) == "number" then return string.format("%.2f", v) end
    return safeStr(v)
end
NT._MeasureOn = measureOn

local function measure(method)
    return measureOn(nameFS, method)
end
NT._Measure = measure

local function hex(r, g, b)
    return string.format("%02x%02x%02x",
        math.floor((r or 0) * 255 + 0.5),
        math.floor((g or 0) * 255 + 0.5),
        math.floor((b or 0) * 255 + 0.5))
end
NT._Hex = hex

--------------------------------------------------------------------------------
-- The oracle
--------------------------------------------------------------------------------
-- SetAlphaGradient(start, length) -> isWithinText is the only FontString function
-- that reports something about a SECRET string's content and is not annotated to go
-- secret itself: no SecretReturnsForAspect, no SecretWhenAnchoringSecret, only
-- SecretArguments = "AllowedWhenUntainted" -- which constrains what goes in (plain
-- integers), not what comes back (SimpleFontStringAPIDocumentation.lua:463). It has
-- zero callers in Blizzard's source and no Documentation field, so everything below
-- was measured rather than read.
--
-- Measured semantics: 0-based and inclusive, so count = lastTrueIndex + 1. Counts
-- UTF-8 CHARACTERS, not bytes. Layout-sensitive: on a constrained FontString it
-- reports the characters that RENDERED, which is what makes it a fitter
-- rather than a strlen.

local PROBE_LIMIT = 128
NT._PROBE_LIMIT = PROBE_LIMIT
local probeFS

local function ensureProbeFS()
    if probeFS then return probeFS end

    local holder = CreateFrame("Frame", nil, UIParent)
    holder:SetSize(1, 1)
    holder:SetPoint("CENTER", UIParent, "CENTER", 0, -300)
    -- Shown but transparent, not hidden. A hidden region may skip layout entirely,
    -- and a layout-sensitive oracle would then answer about nothing at all.
    holder:SetAlpha(0)

    probeFS = holder:CreateFontString(nil, "OVERLAY")
    probeFS:SetPoint("CENTER", holder, "CENTER", 0, 0)  -- single point => natural width
    probeFS:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
    if probeFS.SetWidth then probeFS:SetWidth(0) end
    if probeFS.SetWordWrap then probeFS:SetWordWrap(false) end
    if probeFS.SetTextScale then probeFS:SetTextScale(1) end

    return probeFS
end
NT._EnsureProbeFS = ensureProbeFS

-- true / false, or nil plus a tag describing why it was not a plain boolean.
local function alphaProbe(fs, start, length)
    if not fs or type(fs.SetAlphaGradient) ~= "function" then return nil, "noAPI" end
    local ok, within = pcall(fs.SetAlphaGradient, fs, start, length or 1)
    if not ok then return nil, "err" end
    if issecretvalue and issecretvalue(within) then return nil, "SECRET" end
    if within == true or within == false then return within end
    return nil, "nonbool(" .. safeStr(within) .. ")"
end
NT._AlphaProbe = alphaProbe

-- Largest n in [0, limit] with isWithinText true. The index is 0-based and inclusive,
-- so the character count is best + 1, and best == -1 means the string is empty.
-- Bisecting from 1 instead would report 0 for both a one-character string and an
-- empty one.
local function alphaBisect(fs, limit)
    local lo, hi, best, calls = 0, limit, -1, 0
    while lo <= hi do
        local mid = math.floor((lo + hi) / 2)
        calls = calls + 1
        if alphaProbe(fs, mid, 1) == true then
            best = mid
            lo = mid + 1
        else
            hi = mid - 1
        end
    end
    return best, calls
end
NT._AlphaBisect = alphaBisect

-- count, calls, tag. The leading probe(0) is not redundant: alphaBisect treats any
-- non-true return as false, so a SECRET or errored return would silently shorten the
-- count instead of announcing itself. Cheap per-call integrity check.
local function measureCount(fs)
    local _, tag = alphaProbe(fs, 0, 1)
    if tag then return nil, 1, tag end

    local best, calls = alphaBisect(fs, PROBE_LIMIT)
    if type(fs.ClearAlphaGradient) == "function" then
        pcall(fs.ClearAlphaGradient, fs)
    end
    -- True at the very top of the range is not a count, it is the absence of one: a
    -- FontString whose layout is dirty answers "yes, inside the text" at every index.
    -- That is exactly what a read taken in the same frame as the SetFont returns.
    -- Reporting it as PROBE_LIMIT+1 characters invents a number, and an invented
    -- number that large silently poisons every comparison downstream.
    if best >= PROBE_LIMIT then return nil, calls + 1, "saturated" end
    return best + 1, calls + 1
end

local function plainNumber(fs, method)
    local fn = fs and fs[method]
    if type(fn) ~= "function" then return nil end
    local ok, v = pcall(fn, fs)
    if not ok then return nil end
    if issecretvalue and issecretvalue(v) then return nil end
    if type(v) ~= "number" then return nil end
    return v
end
NT._PlainNumber = plainNumber

--------------------------------------------------------------------------------
-- Colors
--------------------------------------------------------------------------------

-- Start color is the target's class color; end color is the curated per-class
-- endpoint. Same treatment CastBar X applies to spell names, so the cadence matches.
-- No class (every NPC, and any player whose class won't resolve) falls to the
-- white -> gray placeholder.
-- UnitIsPlayer carries no secret annotation at all -- SecretArguments only -- so it
-- is a plain boolean for any unit, and it is the only honest test for "is this a
-- player". A resolvable class token is NOT: Blizzard assigns internal classes to
-- NPCs, so most of a capital city reads back as WARRIOR / PALADIN / MAGE and would
-- otherwise pick up a class ramp it has no business wearing.
local function targetIsPlayer()
    local ok, v = pcall(UnitIsPlayer, "target")
    return ok and v == true
end
NT._TargetIsPlayer = targetIsPlayer

local function resolveColors()
    local token = cfg.forcedClass
    if not token and addon.GetClassTokenForUnit then
        if cfg.identity ~= "player" or targetIsPlayer() then
            token = addon.GetClassTokenForUnit("target")
        end
    end

    local cr, cg, cb
    if token and addon.GetClassColorRGB then
        cr, cg, cb = addon.GetClassColorRGB(token)
    end

    if not cr then
        return {
            token = nil,
            r1 = NPC_START[1], g1 = NPC_START[2], b1 = NPC_START[3],
            r2 = NPC_END[1],   g2 = NPC_END[2],   b2 = NPC_END[3],
        }
    end

    local r1, g1, b1 = cr, cg, cb
    if cfg.treatment == "cast" and addon.DarkenColor then
        r1, g1, b1 = addon.DarkenColor(cr, cg, cb, 0.25)
    end

    local ep = addon.CLASS_GRADIENT_ENDPOINTS and addon.CLASS_GRADIENT_ENDPOINTS[token]
    local r2, g2, b2
    if ep and addon.LightenColor then
        r2, g2, b2 = addon.LightenColor(ep[1], ep[2], ep[3], 0.10)
    elseif addon.LightenColor then
        r2, g2, b2 = addon.LightenColor(cr, cg, cb, 0.45)
    else
        r2, g2, b2 = cr, cg, cb
    end

    return { token = token, r1 = r1, g1 = g1, b1 = b1, r2 = r2, g2 = g2, b2 = b2 }
end

local function rampAt(c, t)
    return c.r1 + (c.r2 - c.r1) * t,
           c.g1 + (c.g2 - c.g1) * t,
           c.b1 + (c.b2 - c.b1) * t
end

--------------------------------------------------------------------------------
-- Slice stack (the only technique that works on a secret name)
--------------------------------------------------------------------------------
-- N column-shaped clip frames tiled across the box, each holding an identical copy
-- of the same FontString at a different solid color. Each copy shows only its own
-- column, so left-to-right the stack reads as a banded gradient. No string is ever
-- read, split or measured -- SetText is AllowedWhenTainted, so a secret pours in fine.
--
-- The ramp necessarily spans the box rather than each line: per-line ramps need each
-- line's own horizontal extent, and that comes only from
-- CalculateScreenAreaFromCharacterSpan, which is dead once the text is secret.

local function createSlice()
    local clip = CreateFrame("Frame", nil, frame)
    clip:SetClipsChildren(true)
    -- Frame level left to auto-inherit from the parent, as cast/textfill.lua does.

    -- Anchored to the container, not to the clip frame, so every copy lays out
    -- identically and the clip only decides which slice of it is visible. Same
    -- relationship as filledText -> clipFrame -> cast bar in cast/textfill.lua.
    local fs = clip:CreateFontString(nil, "OVERLAY")
    fs:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    fs:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    fs:SetJustifyH("CENTER")
    fs:SetJustifyV("MIDDLE")
    fs:SetFont("Fonts\\FRIZQT__.TTF", 12, "")

    return { clip = clip, fs = fs }
end

local slicePool = addon.Pool.NewIndexed(createSlice, function(s) s.clip:Hide() end)
NT._slicePool = slicePool

local function hideSlices()
    slicePool:HideFrom(1)
end

local function applySlices(result, colors)
    local n = math.max(1, math.floor(cfg.slices))
    local face = addon.ResolveFontFace(effectiveFaceKey())

    -- Take the fit's own report and nothing else. The old form was
    --   size = result.size or cfg.maxSize
    --   maxLines = GetMaxLines(nameFS) or cfg.maxLines
    -- which papered over a fit that never ran: the copies rendered at cfg.maxSize
    -- with an unlimited line budget and looked like a deliberate layout. If the fit
    -- did not produce numbers, draw nothing and say why.
    local size     = result and result.size
    local scale    = (result and result.scale) or 1
    local maxLines = result and result.maxLines

    lastSliceSize, lastSliceScale, lastSliceMaxLines = size, scale, maxLines
    lastSliceFallback = result and result.fallback or false

    if not size or not maxLines then
        hideSlices()
        return false, "fit reported no size/maxLines"
    end

    for i = 1, n do
        local s = slicePool:Get(i)

        -- Snap column edges to whole pixels. Fractional edges under a fractional UI
        -- scale leave visible seams between columns.
        local left  = math.floor(cfg.width * (i - 1) / n + 0.5)
        local right = math.floor(cfg.width * i / n + 0.5)

        s.clip:ClearAllPoints()
        s.clip:SetPoint("TOPLEFT", frame, "TOPLEFT", left, 0)
        s.clip:SetPoint("BOTTOMRIGHT", frame, "TOPLEFT", right, -cfg.height)

        -- Replay the fit the way it was applied, not the way it reads. "scale" and
        -- "blizzard" leave the font at maxSize and shrink via SetTextScale, so
        -- applying result.size AND result.scale would shrink twice.
        --
        -- A fallback bail is the exception: it applies the point size directly at
        -- scale 1 whatever the mode, so replaying it through the scale branch would
        -- put the copies at maxSize while the master sits at fallbackSize.
        if cfg.mode == "font" or lastSliceFallback then
            addon.ApplyFontStyle(s.fs, face, size, cfg.style)
            if s.fs.SetTextScale then pcall(s.fs.SetTextScale, s.fs, 1) end
        else
            addon.ApplyFontStyle(s.fs, face, cfg.maxSize, cfg.style)
            if s.fs.SetTextScale then pcall(s.fs.SetTextScale, s.fs, scale) end
        end
        if s.fs.SetSmoothScaling then pcall(s.fs.SetSmoothScaling, s.fs, cfg.mode ~= "font") end
        pcall(s.fs.SetWordWrap, s.fs, true)
        pcall(s.fs.SetNonSpaceWrap, s.fs, false)
        pcall(s.fs.SetMaxLines, s.fs, maxLines)

        -- Sample the ramp at the column's centre so the bands sit symmetrically.
        local t = (n == 1) and 0 or ((i - 0.5) / n)
        s.fs:SetTextColor(rampAt(colors, t))

        if s.fs.ClearText then pcall(s.fs.ClearText, s.fs) end
        pcall(s.fs.SetText, s.fs, currentValue)

        s.clip:Show()
    end

    slicePool:HideFrom(n + 1)
    return true
end

--------------------------------------------------------------------------------
-- Display state
--------------------------------------------------------------------------------

-- True while nameFS holds the raw value rather than a |cff-coded gradient string.
local plainApplied = false

-- One snapshot per cross-file call: the moved builders and the case probe read these
-- at entry, on the same tick as the upvalue reads they replace. nameFS and frame are
-- created lazily, after load, so a load-time capture would hold nil.
function NT._State()
    return {
        lastResult = lastResult, lastColors = lastColors, lastFit = lastFit,
        lastSource = lastSource, lastLines = lastLines, lastDiscovery = lastDiscovery,
        lastGradientMode = lastGradientMode, lastGradientNote = lastGradientNote,
        lastRamped = lastRamped, lastSliceSize = lastSliceSize,
        lastSliceScale = lastSliceScale, lastSliceMaxLines = lastSliceMaxLines,
        lastSliceFallback = lastSliceFallback, currentIsSecret = currentIsSecret,
        currentValue = currentValue, currentRaw = currentRaw,
        caseMethod = caseMethod, caseError = caseError, caseOutSecret = caseOutSecret,
        plainApplied = plainApplied, nameFS = nameFS, frame = frame,
    }
end

local function applyValue()
    if nameFS.ClearText then pcall(nameFS.ClearText, nameFS) end
    pcall(nameFS.SetText, nameFS, currentValue)
    plainApplied = true
    paintSeq = paintSeq + 1
end

-- The name is NOT painted here, and that is the whole anti-flicker design. There is no
-- size to paint it at until the fit has run, so painting it now means painting it at the
-- previous target's size -- which is the movement you see a few frames later when the
-- real size lands. Nothing reaches nameFS until renderName has an answer.
--
--   hold = false  the subject changed. Clear the box immediately and show nothing until
--                 the new fit is ready. A few frames of empty reads as latency; a name
--                 that appears and then resizes reads as a bug.
--   hold = true   same subject, re-measured (a late UNIT_NAME_UPDATE, a config change).
--                 Leave what is on screen alone and swap to the new fit atomically --
--                 blanking here would be a flicker invented for no reason.
-- Recomputes currentValue from currentRaw. Called on every new value and whenever the
-- case mode changes, because the transform has to be redone against the new mode -- and
-- it has to run BEFORE the fit, since 'PENUMBRAL CUSTODIAN' is far wider than
-- 'Penumbral Custodian' and the size that fits one does not fit the other.
--
-- Every branch sets currentValue. A transform that refuses leaves the original text in
-- place and says so through caseMethod; it never leaves the box empty, because an empty
-- box here would be indistinguishable from the render pipeline failing somewhere else.
local function applyCaseTransform()
    caseMethod, caseError, caseOutSecret = "none", nil, currentIsSecret
    currentValue = currentRaw

    if cfg.case == "normal" then return end

    -- type() answers honestly for secrets, so this only rejects nil -- never a boolean
    -- test on the name itself. "no name" is its own outcome and must not be reported as
    -- a refusal: nothing was handed to string.upper, so the engine expressed no opinion.
    -- Collapsing the two is how the first run of this read as a definitive REFUSED with
    -- no target selected.
    if type(currentRaw) ~= "string" then
        caseMethod = "no name"
        return
    end

    if cfg.case == "smallcaps" then
        -- Nothing to do to the text. The font is the transform.
        caseMethod = "font"
        return
    end

    -- The open question, asked directly. pcall catches the refusal if string.upper is
    -- not on the whitelist for secrets; the type check catches a silent nil, which
    -- would otherwise blank the name and read as a rendering bug three layers away.
    local ok, upper = pcall(string.upper, currentRaw)
    if ok and type(upper) == "string" then
        currentValue = upper
        caseMethod = "string.upper"
        caseOutSecret = (issecretvalue and issecretvalue(upper)) and true or false
    else
        caseMethod = "refused"
        caseError = ok and ("returned " .. type(upper)) or tostring(upper)
    end
end

local function setValue(value, isSecret, source, hold)
    currentRaw = value
    currentIsSecret = isSecret and true or false
    lastSource = source
    applyCaseTransform()

    if not hold and nameFS then
        nameFS:SetAlpha(0)
        hideSlices()
    end
end

local function applySolid(colors, note)
    nameFS:SetTextColor(colors.r1, colors.g1, colors.b1, 1)
    lastGradientNote = note
end

-- The one place the box stops being blank. Every colour path has to end here, so a path
-- that forgets to shows up as an empty box -- loud, and impossible to mistake for a
-- styling problem.
local function reveal()
    if nameFS then nameFS:SetAlpha(1) end
end

--------------------------------------------------------------------------------
-- Sizing: a shrink-to-fit that is sound on text nobody can read
--------------------------------------------------------------------------------
-- addon.FitTextToBox is not used here and cannot be. It measures with GetStringWidth,
-- and a FontString holding a secret string returns SECRET for every geometry getter it
-- owns -- the string poisons its own region, so there is no ruler to escape to.
--
-- What survives is the character-count oracle, and three numbers built out of it:
--
--   F     the name's true character count. Free-standing ruler: no width, no wrap, so
--         nothing can ever be dropped. Independent of font size.
--   S     how many spaces the name contains. Same oracle on a ruler squeezed so narrow
--         that every space is forced to break -- and a break EATS the space it broke
--         on, so the count falls by exactly one per space. A secret string's word
--         count, without reading it.
--   D(s)  the count on a box-width ruler at font size s, line cap far above anything a
--         name could reach, so overflow wraps instead of ellipsizing.
--
-- A size fits when all of these hold. They are independent, and each catches a failure
-- the others let through:
--
--   1. D(s) is not ABOVE the running minimum. A layout can lose a wrap and gain an
--      ellipsis at once, and the count then steps back up. The scan runs ascending
--      because that running minimum is the detector, and a bisection carries no
--      history to compare against.
--   2. D(s) is not BELOW F - S. Every space break costs exactly one character, so a
--      layout that broke only at spaces can never fall under that floor. Going under it
--      means characters were destroyed rather than consumed by a break.
--   3. Lpred = F - D + 1 is within the line budget, min(maxLines, boxHeight /
--      GetLineHeight). GetLineHeight carries no secret annotation, which is what makes
--      that budget a measurement rather than an assumption.
--   4. Rendering the same text again with the cap set to EXACTLY Lpred produces the
--      same count. This is the check that matters, and it is subtler than it looks.
--
-- Check 4 exists because D can only see breaks that EAT a character, and not every
-- break does. A space break consumes the space; a break inside a word consumes nothing,
-- and so does a break at a hyphen. So a name with no spaces at all can render across
-- two lines while D still reports the full character count, and every count-based test
-- passes on a layout that is visibly split down the middle. Measured on 'Chrysalius':
-- F = 10, spaces = 0, D = 10 at 32pt, and the engine reported two lines for one word.
--
-- Capping at Lpred is what exposes it. Lpred is the line count the name WOULD occupy if
-- every break were a space break. If the engine needed more lines than that,
-- forcing the cap down to Lpred makes it ellipsize, and the count moves. If Lpred was
-- right, the cap changes nothing and the count holds. It is a direct question -- "did
-- you break anywhere I cannot see?" -- rather than an inference from a number.
--
-- Note that capping at the BUDGET instead does not work, and that is exactly the bug
-- this replaced: Chrysalius broke into two lines and the budget was two, so capping
-- changed nothing and the split went unnoticed.
--
--   5. The whole thing still holds with the box narrowed by one ellipsis width. This
--      is the blind spot, and it is the reason the other four are not enough.
--
-- THE BLIND SPOT. The ellipsis is three glyphs long and roughly three characters WIDE,
-- and those two facts cancel. When the text stops fitting, the engine has to drop
-- enough characters to make room for the dots it is about to add -- and dropping one or
-- two cannot work, because one or two characters replaced by three dots is WIDER than
-- what it started with and still does not fit. So the first reachable truncated state
-- drops exactly three, gains exactly three, and reports a count identical to F.
--
-- Measured on 'Chrysalius' (F = 10, one word, Roboto Black, 150px box): D was 10 at
-- every size from 9 to 32, and the screen said 'Chrysal...' -- seven characters and
-- three dots. The +1 and +2 rises that check 1 exists to catch are not merely rare
-- here, they are geometrically unreachable. No count-based test can see this. The
-- oracle cannot distinguish a name from the same name truncated by three.
--
-- So instead of detecting it, stay out of its range: require the layout to survive a
-- box one ellipsis narrower than the real one. A name that renders fully in W - E has
-- E pixels of slack in W, which is more than the blind spot can hide. It costs about
-- three characters of width -- names come out slightly smaller than the box could
-- strictly hold -- and it is exactly the price of not being able to see the last three
-- characters. '/scoot debug nametext margin off' turns it off to see the difference.
--
-- TWO TIERS. A size that passes all five breaks only at spaces: whole words, no
-- hyphenation, no words sawn in half, nothing clipped. That is the answer whenever one
-- exists. But a long Name-Realm string has no spaces and will not fit on one line at
-- any readable size, and refusing to render it at all would be worse than the hyphen
-- break WoW offers. So the scan also tracks a LOOSE tier -- capped at the budget rather
-- than at Lpred, and without the margin, accepting any break as long as the whole name
-- still renders -- and falls back to it only when no clean size exists.
--
-- WHERE THE SEARCH MAY STOP, AND WHERE IT MAY NOT. Phase 1 stops at its first failure,
-- because both of its checks are monotone in size: a word too wide to render at s is
-- too wide at s+1, and the running minimum that detects it is only meaningful scanned in
-- order. Phase 2 must NOT stop, because its checks are per-size facts about a layout
-- that changes shape as the size grows. The largest clean size is a maximum over the
-- whole range, not the top of an unbroken run -- a name that is one point short of
-- needing a second line gets rejected for sitting too near the edge, and the very next
-- size, now on two lines with room around both words, is clean again. Treating that
-- first rejection as the end of the search is what stopped multi-word names from
-- wrapping at all: 'Penumbral Custodian' settled on one line at 11pt when 24pt on two
-- lines was available and passing.
--
-- COST: three frames, whatever the size range. A layout does not settle inside the
-- frame it was armed in -- a same-frame read is saturated, answering "yes" at every
-- index -- but that is one frame per FONTSTRING, not one per candidate size. So every
-- size gets its own ruler, all of them are armed at once, and all of them are read
-- together: frame 0 arms the free/squeeze/uncapped rulers, frame 1 reads them and arms
-- the capped pass, frame 2 reads that and decides. ~50ms end to end for a 44-point
-- range, against ~750ms for the one-ruler-stepped-through-sizes version this replaces.

-- Far past any name; a stand-in for "no line cap" that does not depend on 0 meaning
-- unlimited. Whether it does is not worth a second unknown in a soundness argument.
local UNCAPPED_LINES = 64

-- Two squeeze widths for the space count, purely so the two can be compared. The count
-- is only correct if the ruler is narrow enough that no two words share a line, and the
-- way that assumption fails is silently -- it returns a smaller number, not an error.
local SQUEEZE_A, SQUEEZE_B = 20, 10
NT._SQUEEZE_A, NT._SQUEEZE_B = SQUEEZE_A, SQUEEZE_B

-- Rulers are created once and never destroyed, but the size range is user-editable and
-- nothing stops someone typing 'range 1 500'. Coarsen rather than allocate 500 regions.
local MAX_CANDIDATES = 64

-- Kept off addon.Pool: fixed slots capped at MAX_CANDIDATES and never hidden, since a hidden region skips layout.
local rulerHolder, rulerPool = nil, {}

-- One holder, N FontStrings stacked on the same point. They overlap, which does not
-- matter: a FontString's layout is its own, and the holder is transparent. Shown, not
-- hidden -- a hidden region may skip layout, and then the oracle answers about nothing.
local function ensureRuler(i)
    if not rulerHolder then
        rulerHolder = CreateFrame("Frame", nil, UIParent)
        rulerHolder:SetSize(1, 1)
        rulerHolder:SetPoint("CENTER", UIParent, "CENTER", 0, -360)
        rulerHolder:SetAlpha(0)
    end

    local fs = rulerPool[i]
    if fs then return fs end

    fs = rulerHolder:CreateFontString(nil, "OVERLAY")
    -- One anchor only. Width is set per-probe; height stays free so the line cap is the
    -- only thing that can ever limit the line count.
    fs:SetPoint("TOP", rulerHolder, "TOP", 0, 0)
    fs:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
    fs:SetJustifyH("CENTER")
    rulerPool[i] = fs
    return fs
end

-- Every field is written every time. A ruler that carried one setting over from a
-- previous probe measures a different question, and nothing about the number that comes
-- back would look wrong.
local function armRuler(fs, value, size, width, wrap, nonSpaceWrap, maxLines)
    addon.ApplyFontStyle(fs, addon.ResolveFontFace(effectiveFaceKey()), size, cfg.style)
    if fs.SetTextScale then pcall(fs.SetTextScale, fs, 1) end
    if fs.SetWidth then pcall(fs.SetWidth, fs, width) end
    if fs.SetWordWrap then pcall(fs.SetWordWrap, fs, wrap) end
    if fs.SetNonSpaceWrap then pcall(fs.SetNonSpaceWrap, fs, nonSpaceWrap) end
    if fs.SetMaxLines then pcall(fs.SetMaxLines, fs, maxLines) end
    if fs.ClearText then pcall(fs.ClearText, fs) end
    pcall(fs.SetText, fs, value)
end

-- The pixel width of "..." at a given size. That is a harness-authored literal, so no
-- secret is involved and MeasureTextWidth can do its ordinary SetText/GetStringWidth on
-- it -- the one part of a truncated render that stays readable, and by luck the
-- exact size of the thing that cannot be seen. Falls back to a size-proportional estimate,
-- because a nil here would silently switch off the check that catches the blind spot.
local function marginFor(size)
    if cfg.margin == "off" then return 0 end

    local fixed = tonumber(cfg.margin)
    if fixed then return math.max(0, math.floor(fixed)) end

    local w = addon.MeasureTextWidth and addon.MeasureTextWidth(
        "...", addon.ResolveFontFace(effectiveFaceKey()), size, cfg.style)
    if type(w) == "number" and w > 0 then return math.floor(w + 0.5) end
    return math.floor(size + 0.5)
end

-- onDone(st). st carries the whole derivation, not just the answer, because the
-- 'autofit' report renders it verbatim and a number with no working shown is exactly
-- what made the earlier rounds of this so hard to trust.
local function sizeName(value, onDone)
    local st = { calls = 0, frames = 0, rows = {}, sizes = {} }

    local lo = math.max(1, math.floor(tonumber(cfg.minSize) or 9))
    local hi = math.max(1, math.floor(tonumber(cfg.maxSize) or 52))
    if hi < lo then lo, hi = hi, lo end

    st.step = math.max(1, math.ceil((hi - lo + 1) / MAX_CANDIDATES))
    for s = lo, hi, st.step do st.sizes[#st.sizes + 1] = s end
    st.lo, st.hi = lo, hi

    local n = #st.sizes
    -- Three probe slots per size: capped at Lpred, capped at the budget, and capped at
    -- Lpred again in a box narrowed by the margin. Slots that would duplicate another
    -- are simply not armed.
    local cappedBase = 3 + n

    -- Frame 0: arm everything that does not depend on a measurement.
    armRuler(ensureRuler(1), value, hi, 0, false, false, 1)
    armRuler(ensureRuler(2), value, lo, SQUEEZE_A, true, true, UNCAPPED_LINES)
    armRuler(ensureRuler(3), value, lo, SQUEEZE_B, true, true, UNCAPPED_LINES)
    for i = 1, n do
        armRuler(ensureRuler(3 + i), value, st.sizes[i], cfg.width, true, false, UNCAPPED_LINES)
    end

    local function read(i)
        local count, calls, tag = measureCount(ensureRuler(i))
        st.calls = st.calls + (calls or 0)
        return count, tag
    end

    C_Timer.After(0, function()
        st.frames = st.frames + 1

        st.F, st.FTag = read(1)
        local dA = read(2)
        local dB = read(3)
        if st.F and dA then st.spacesA = st.F - dA end
        if st.F and dB then st.spacesB = st.F - dB end
        -- The larger of the two is the better floor: a squeeze that was not tight enough
        -- can only ever UNDER-count breaks, never over-count them.
        if st.spacesA and st.spacesB then
            st.spaces = math.max(st.spacesA, st.spacesB)
        else
            st.spaces = st.spacesA or st.spacesB
        end

        if not st.F or not st.spaces then
            st.reason = "oracle unavailable ("
                .. tostring(st.FTag or "no space count") .. ")"
            onDone(st)
            return
        end

        -- Phase 1: the count-only checks, which need nothing but D. Every failure here
        -- is monotone in size -- a word that will not fit at s will not fit at s+1 --
        -- so the first one ends the search, and no capped ruler is armed past it.
        local floorD, runningMin = st.F - st.spaces, st.F
        local live = {}

        for i = 1, n do
            local row = { size = st.sizes[i] }
            st.rows[i] = row

            local ruler = ensureRuler(3 + i)
            row.d = read(3 + i)

            local lh = plainNumber(ruler, "GetLineHeight")
            row.lineHeight  = lh
            row.heightLines = (lh and lh > 0) and math.floor(cfg.height / lh) or nil
            row.budget = math.max(1, math.min(cfg.maxLines, row.heightLines or cfg.maxLines))

            if st.phase1Stop then
                row.skipped = true
            elseif not row.d then
                row.why = "uncapped ruler returned nothing"
            elseif row.d > runningMin then
                row.why = string.format("count ROSE %d->%d; the '...' is 3 characters",
                    runningMin, row.d)
            elseif row.d < floorD then
                row.why = string.format("count %d under floor %d; characters were lost",
                    row.d, floorD)
            else
                runningMin = math.min(runningMin, row.d)
                -- The line count this name would occupy IF every break were a space
                -- break. Checking it is the whole of phase 2.
                row.lpred = st.F - row.d + 1

                -- The margin is the width of "..." at this size. That is a literal
                -- three-character literal of the harness, so measuring it involves no secret
                -- at all -- it is the one piece of the truncated render that stays
                -- readable, and it happens to be the exact size of the blind spot.
                row.margin = marginFor(row.size)
                row.narrowWidth = math.max(8, cfg.width - row.margin)

                local base = cappedBase + (i - 1) * 3
                armRuler(ensureRuler(base + 1), value, row.size,
                    cfg.width, true, false, row.lpred)
                if row.budget ~= row.lpred then
                    armRuler(ensureRuler(base + 2), value, row.size,
                        cfg.width, true, false, row.budget)
                end
                if row.margin > 0 then
                    armRuler(ensureRuler(base + 3), value, row.size,
                        row.narrowWidth, true, false, row.lpred)
                end
                live[#live + 1] = i
            end

            if row.why and not st.phase1Stop then st.phase1Stop = row.size end
        end

        C_Timer.After(0, function()
            st.frames = st.frames + 1

            for _, i in ipairs(live) do
                local row = st.rows[i]
                local base = cappedBase + (i - 1) * 3

                row.dAtLpred = read(base + 1)
                row.dAtBudget = (row.budget ~= row.lpred) and read(base + 2) or row.dAtLpred
                row.dNarrow = (row.margin > 0) and read(base + 3) or row.dAtLpred

                -- CLEAN: every break was a space break, it stays inside the budget, and
                -- it still holds with the box narrowed by the blind spot.
                row.clean = (row.lpred <= row.budget)
                    and (row.dAtLpred == row.d)
                    and (row.dNarrow == row.d)
                -- LOOSE: the whole name still renders within the budget, however it
                -- chose to break -- hyphen or mid-word included, and no margin. This is
                -- the fallback, so it buys coverage by giving up the guarantee.
                row.loose = (row.dAtBudget == row.d)

                -- Phase 2 rejections do NOT end the search, and that is the whole
                -- difference between this and phase 1. Phase 1's checks are cross-size
                -- (a running minimum) and monotone: a word too wide at s is too wide at
                -- s+1, so the first failure is final. Phase 2's are per-size facts with
                -- no history behind them, and they are emphatically NOT monotone -- the
                -- layout changes shape as the size grows. A name one point away from
                -- needing a second line is rejected for sitting too near the edge; one
                -- point later it has moved onto two lines with room to spare and is
                -- clean again. Stopping at the first rejection is what kept 'Penumbral
                -- Custodian' on one line at 11pt when it wraps happily at 24.
                if row.clean then
                    if not st.clean or row.size > st.clean then
                        st.clean, st.cleanLines, st.cleanBudget = row.size, row.lpred, row.budget
                    end
                else
                    st.cleanStop = st.cleanStop or row.size
                    if row.lpred > row.budget then
                        row.why = string.format("needs %d line(s), budget %d",
                            row.lpred, row.budget)
                    elseif row.dAtLpred ~= row.d then
                        row.why = string.format(
                            "capping at %d changed the render (%s vs %d) -- it broke somewhere "
                            .. "that is not a space", row.lpred, safeStr(row.dAtLpred), row.d)
                    else
                        row.why = string.format(
                            "fails with %dpx less width (%s vs %d) -- too close to the edge to "
                            .. "tell a full render from one clipped by three",
                            row.margin, safeStr(row.dNarrow), row.d)
                    end
                end

                if row.loose then
                    if not st.loose or row.size > st.loose then
                        st.loose, st.looseLines, st.looseBudget = row.size, row.lpred, row.budget
                    end
                else
                    st.looseStop = st.looseStop or row.size
                end
            end

            if st.clean then
                st.size, st.lines, st.budget, st.tier = st.clean, st.cleanLines, st.cleanBudget, "clean"
            elseif st.loose then
                st.size, st.lines, st.budget, st.tier = st.loose, st.looseLines, st.looseBudget, "loose"
                st.reason = "no size breaks only at spaces; fell back to the largest that "
                    .. "renders in full however it breaks"
            else
                st.reason = string.format("nothing in %d..%d fits a %dx%d box",
                    lo, hi, cfg.width, cfg.height)
            end
            st.stopped = st.cleanStop or st.phase1Stop

            onDone(st)
        end)
    end)
end

--------------------------------------------------------------------------------
-- Coloring: the one thing that has to branch
--------------------------------------------------------------------------------

local runFit  -- forward declaration; the probe commands re-enter it

-- Second half of the readable path, deferred by one frame. DiscoverTextLines asks the
-- engine where it broke the lines, and that is a question about the LAYOUT, so the
-- display has to have been laid out at its final size before it can be asked.
local function applyRamp(result, colors, mode, seq, ps)
    -- Superseded: a newer pass owns the box and will reveal it. Revealing here would
    -- paint the previous target's name.
    if seq ~= renderSeq or ps ~= paintSeq then return end

    local lines = addon.DiscoverTextLines and addon.DiscoverTextLines(nameFS, currentValue)
    if lines then
        lastDiscovery = "span API"
    elseif addon.WrapTextGreedy then
        lines = addon.WrapTextGreedy(currentValue, {
            width = cfg.width,
            face  = addon.ResolveFontFace(effectiveFaceKey()),
            size  = (result and result.size) or cfg.maxSize,
            style = cfg.style,
        })
        lastDiscovery = lines and "greedy fallback" or "none"
    end
    lastLines = lines

    if not lines then
        lastGradientNote = "line discovery failed - solid start color"
        reveal()
        return
    end

    local ramped = addon.BuildPerLineRampString and addon.BuildPerLineRampString(
        lines, colors.r1, colors.g1, colors.b1, colors.r2, colors.g2, colors.b2,
        { mode = (mode == "block") and "block" or "line" })

    if not ramped then
        lastGradientNote = "ramp build failed - solid start color"
        reveal()
        return
    end
    lastRamped = ramped

    -- Inline |cff codes multiply against the text color, so it has to be white.
    nameFS:SetTextColor(1, 1, 1, 1)
    -- Word wrap stays ON. The explicit "\n" already forces the breaks, so wrap only
    -- ever adds one -- and that is the safety net: |cff hex values shift sub-pixel
    -- kerning by 1-2px (castbarX pitfall #28), so a line sitting on the boundary can
    -- come out fractionally wider than the plain text it was measured from. With wrap
    -- off that is a guaranteed "...", with wrap on it is a reflow at worst.
    pcall(nameFS.SetWordWrap, nameFS, true)
    pcall(nameFS.SetText, nameFS, ramped)
    plainApplied = false
    reveal()
    -- Deliberately no paintSeq bump: this IS the paint that ps was guarding.
end

local function applyColor(result, seq)
    local readable = type(currentValue) == "string"
        and not (issecretvalue and issecretvalue(currentValue))
    local isPlayer = targetIsPlayer()

    local mode = cfg.gradient
    if mode == "auto" then
        -- The shipping policy. A class ramp needs BOTH a readable string (per-character
        -- |cff is a string operation, and there is no way around that) and a real
        -- player -- NPCs carry class tokens too, so most of a capital city resolves to
        -- WARRIOR or MAGE and would otherwise wear a ramp it has no business in.
        -- Everything else is white, which is a deliberate choice and not a failure.
        --
        -- Two deliberate overrides: 'class <TOKEN>' is the only way the canned samples
        -- can be evaluated at all, since there is no unit behind them, and
        -- 'identity class' is the A/B for whether UnitIsPlayer is really the right gate.
        local classAllowed = isPlayer or cfg.forcedClass ~= nil or cfg.identity ~= "player"
        mode = (readable and classAllowed) and "line" or "white"
    end

    lastGradientMode = mode
    lastGradientNote = nil
    lastLines, lastDiscovery, lastRamped = nil, nil, nil

    local colors = resolveColors()
    lastColors = colors

    hideSlices()

    if mode == "white" then
        nameFS:SetTextColor(1, 1, 1, 1)
        lastGradientNote = (not readable) and "name is secret - solid white"
            or (not isPlayer) and "not a player - solid white"
            or "solid white"
        reveal()
        return
    end

    if mode == "off" then
        applySolid(colors, "solid (control)")
        reveal()
        return
    end

    if mode == "slice" then
        local drawn, why = applySlices(result, colors)
        if drawn then
            nameFS:SetAlpha(0)   -- the copies are the picture now
        else
            -- Nothing was drawn. Show the master: an empty box is indistinguishable
            -- from having no target, which is the failure mode this whole pass exists
            -- to stop.
            applySolid(colors, "slices not drawn - " .. tostring(why))
            reveal()
        end
        return
    end

    -- line / block, forced or chosen.
    if not readable then
        nameFS:SetTextColor(1, 1, 1, 1)
        lastGradientNote = "text is secret - no string ops possible, solid white"
        reveal()
        return
    end

    -- Stay hidden. The ramp lands one frame from now, and revealing the solid start
    -- colour first would make the name appear and then change colour a frame later --
    -- the same class of blip as appearing and then resizing. This solid paint is the
    -- colour applyRamp falls back to if the ramp cannot be built, not a first draft.
    applySolid(colors, nil)
    local ps = paintSeq
    C_Timer.After(0, function() applyRamp(result, colors, mode, seq, ps) end)
end

--------------------------------------------------------------------------------
-- Render
--------------------------------------------------------------------------------

local function renderName(onDone)
    if not nameFS then return end
    if type(currentValue) == "nil" then return end

    renderSeq = renderSeq + 1
    local seq = renderSeq
    local value = currentValue

    -- Deliberately does NOT blank the box. Whether the previous picture stays up during
    -- the fit is a decision about the SUBJECT, not about the fit, so setValue makes it:
    -- a new target clears immediately, a re-measure of the same one holds. Blanking here
    -- would flicker every config change and every late UNIT_NAME_UPDATE for nothing.
    sizeName(value, function(st)
        -- A newer target landed while this one was measuring. Its own pass owns the box
        -- now, and finishing this one would paint the previous target's name.
        if seq ~= renderSeq then return end

        lastFit = st

        local applied, fallback, overflow
        if st.size then
            applied = st.size
        elseif st.F and st.spaces then
            -- The measurement worked and the answer is "it does not fit". Render at the
            -- floor and let the engine's own ellipsis take it from there -- that is the
            -- honest result, and it is not the same thing as a failed measurement.
            applied, overflow = st.lo, true
        else
            applied, fallback = cfg.fallbackSize, true
        end

        lastResult = {
            size       = applied,
            scale      = 1,
            lines      = st.lines,
            maxLines   = cfg.maxLines,
            budget     = st.budget,
            tier       = st.tier,
            measurable = (st.size ~= nil),
            fallback   = fallback or false,
            overflow   = overflow or false,
            secretText = currentIsSecret,
            stopped    = st.stopped,
            reason     = st.reason,
        }

        applyValue()
        addon.ApplyFontStyle(nameFS, addon.ResolveFontFace(effectiveFaceKey()), applied, cfg.style)
        if nameFS.SetTextScale then pcall(nameFS.SetTextScale, nameFS, 1) end
        if nameFS.SetWordWrap then pcall(nameFS.SetWordWrap, nameFS, true) end
        if nameFS.SetNonSpaceWrap then pcall(nameFS.SetNonSpaceWrap, nameFS, false) end
        if nameFS.SetMaxLines then pcall(nameFS.SetMaxLines, nameFS, cfg.maxLines) end

        applyColor(lastResult, seq)
        if onDone then onDone() end
    end)
end

function runFit(onDone)
    renderName(onDone)
end

-- For callers that just changed the box or the font: let their own SetSize land before
-- the rulers read cfg back.
local function scheduleFit()
    C_Timer.After(0, function() runFit() end)
end

--------------------------------------------------------------------------------
-- Frame
--------------------------------------------------------------------------------

local function ensureFrame()
    if frame then return frame end

    frame = CreateFrame("Frame", "ScootNameTextTest", UIParent)
    frame:SetSize(cfg.width, cfg.height)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 220)
    frame:SetFrameStrata("HIGH")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)

    -- No backdrop and no border: the text is being judged against the world behind it,
    -- and a panel around it changes how every weight and outline reads. The fill is
    -- built anyway and left hidden, purely because an invisible frame cannot be
    -- dragged -- '/scoot debug nametext chrome' brings it back to reposition the box.
    chromeBG = frame:CreateTexture(nil, "BACKGROUND")
    chromeBG:SetAllPoints()
    chromeBG:SetColorTexture(0, 0, 0, 0.55)
    chromeBG:SetShown(cfg.chrome)

    nameFS = frame:CreateFontString(nil, "OVERLAY")
    -- A font at creation time, before any text is ever set. CreateFontString with no
    -- template leaves the region with no font object at all, so the first SetText has
    -- nothing to lay out against -- and the first fit then measures a FontString whose
    -- font was assigned microseconds earlier. Same reason cast/textfill.lua:206 and
    -- the measurement ruler both set a default font up front.
    addon.ApplyFontStyle(nameFS, addon.ResolveFontFace(effectiveFaceKey()), cfg.fallbackSize, cfg.style)
    nameFS:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    nameFS:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    nameFS:SetJustifyH("CENTER")
    nameFS:SetJustifyV("MIDDLE")
    nameFS:SetTextColor(1, 1, 1, 1)

    -- A name is not always known the instant the unit is: for anything not yet cached
    -- the first UnitName comes back "Unknown" and the real one arrives by event. Without
    -- UNIT_NAME_UPDATE the box would size and render "Unknown" and then never correct itself.
    local function onEvent(event, unit)
        if event == "UNIT_NAME_UPDATE" and unit ~= "target" then return end
        -- A name update is the SAME unit arriving late, so hold whatever is on screen
        -- and swap when the new fit lands. Blanking on it would mean two flickers for
        -- every uncached target instead of none.
        DebugNameTextRefresh(event == "UNIT_NAME_UPDATE")
    end
    addon.Events.On("Debug:NameText", "PLAYER_TARGET_CHANGED", onEvent)
    addon.Events.On("Debug:NameText", "UNIT_NAME_UPDATE", onEvent)

    -- CreateFrame returns a shown frame; start hidden so the first toggle reveals it.
    frame:Hide()

    return frame
end

-- Measurements are unreliable on a never-laid-out region, so every mutator shows the
-- harness rather than silently fitting into a hidden box.
local function ensureShown()
    ensureFrame()
    if not frame:IsShown() then frame:Show() end
    return frame
end

local function pullTargetName(hold)
    local name = UnitName("target")

    -- type() reports the real type for secrets, so this only separates "no target"
    -- from "has a name". Never boolean-test the name itself.
    if type(name) == "nil" then
        setValue("(no target)", false, "no target", hold)
    else
        local secret = (issecretvalue and issecretvalue(name)) and true or false
        setValue(name, secret, "UnitName('target')", hold)
    end
end

--------------------------------------------------------------------------------
-- Commands
--------------------------------------------------------------------------------

-- hold: keep the current picture up while the new fit runs. Correct for a re-measure of
-- the same unit, wrong for a new one.
--
-- Fits directly rather than through scheduleFit: nothing here changes the box geometry,
-- so the deferred frame scheduleFit exists to wait for would be one more frame of empty
-- box for no reason.
function DebugNameTextRefresh(hold)
    if not frame or not frame:IsShown() then return end
    pullTargetName(hold)
    runFit()
end

local function DebugNameTextToggle()
    ensureFrame()
    if frame:IsShown() then
        frame:Hide()
        hideSlices()
        addon:Print("Name text harness hidden.")
        return
    end
    frame:Show()
    addon:Print("Name box shown (no backdrop by design - '/scoot debug nametext chrome' to drag it).")
    addon:Print("Target something, or try: /scoot debug nametext sample 4")
    DebugNameTextRefresh()
end

local function DebugNameTextSetSize(w, h)
    ensureShown()
    cfg.width  = tonumber(w) or cfg.width
    cfg.height = tonumber(h) or cfg.height
    frame:SetSize(cfg.width, cfg.height)
    scheduleFit()
    addon:Print(string.format("Container: %dx%d", cfg.width, cfg.height))
end

local function DebugNameTextSetLines(n)
    ensureShown()
    cfg.maxLines = math.max(1, math.floor(tonumber(n) or cfg.maxLines))
    scheduleFit()
    addon:Print("Max lines: " .. cfg.maxLines)
end

local function DebugNameTextSetRange(minSize, maxSize)
    ensureShown()
    cfg.minSize = tonumber(minSize) or cfg.minSize
    cfg.maxSize = tonumber(maxSize) or cfg.maxSize
    scheduleFit()
    addon:Print(string.format("Font size range: %s - %s", tostring(cfg.minSize), tostring(cfg.maxSize)))
end

-- The size used when nothing can be measured, which is every restricted name. On the
-- secret path this is not an error size, it IS the render size.
local function DebugNameTextSetFallback(n)
    ensureShown()
    cfg.fallbackSize = math.max(1, math.floor(tonumber(n) or cfg.fallbackSize))
    scheduleFit()
    addon:Print("Fallback size (unmeasurable text): " .. cfg.fallbackSize)
end

local function DebugNameTextSetMode(mode)
    ensureShown()
    mode = tostring(mode or ""):lower()
    if mode ~= "font" and mode ~= "scale" and mode ~= "blizzard" then
        addon:Print("Mode must be one of: font | scale | blizzard")
        return
    end
    cfg.mode = mode
    -- "scale" leaves a residual text scale behind; reset before switching away.
    if nameFS and nameFS.SetTextScale then pcall(nameFS.SetTextScale, nameFS, 1) end
    scheduleFit()
    addon:Print("Fit mode: " .. cfg.mode)
end

local function DebugNameTextSetFont(face)
    ensureShown()
    if face and face ~= "" then cfg.face = face end
    scheduleFit()
    addon:Print("Font face: " .. cfg.face)
end

-- Harness literals, so every measurement in the case probe is on readable text and the
-- ordinary GetStringWidth path applies. Nothing here goes near a name.
local ALPHA_LOWER = "abcdefghijklmnopqrstuvwxyz"
local ALPHA_UPPER = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
-- The narrowest and widest letters in most faces. Equal advances mean the font is
-- monospaced, which matters because a monospaced font reports the two alphabets as
-- exactly equal without capitalising anything -- 26 characters times one advance,
-- whatever the glyphs look like. Without this column the ratio test flags every
-- monospaced face as all-caps, which is what the first run of this probe did.
local NARROW_RUN = "iiiiiiiiii"
local WIDE_RUN   = "WWWWWWWWWW"
local CASE_PROBE_STRINGS = { ALPHA_LOWER, ALPHA_UPPER, NARROW_RUN, WIDE_RUN }

-- addon.MeasureTextWidth cannot answer this question. It is one shared FontString that
-- applies a font, sets text and reads the width in a single frame, and across a loop of
-- seventy faces the font change does not reach the rasteriser before the read -- so runs
-- of unrelated fonts come back with byte-identical widths. That is the same one-frame
-- settling the length oracle needs, in a place it was not expected.
--
-- So: a private FontString per (face, string), all armed in one frame and all read in
-- the next. One ruler measures one thing exactly once, and nothing it reports can have
-- come from a previous font.
local caseProbeHolder, caseProbeRulers = nil, {}

local function caseProbeRuler(i)
    if not caseProbeHolder then
        caseProbeHolder = CreateFrame("Frame", nil, UIParent)
        caseProbeHolder:SetSize(1, 1)
        caseProbeHolder:SetPoint("CENTER", UIParent, "CENTER", 0, -420)
        caseProbeHolder:SetAlpha(0)
    end

    local fs = caseProbeRulers[i]
    if fs then return fs end

    fs = caseProbeHolder:CreateFontString(nil, "OVERLAY")
    fs:SetPoint("TOP", caseProbeHolder, "TOP", 0, 0)
    fs:SetJustifyH("LEFT")
    caseProbeRulers[i] = fs
    return fs
end

-- Answers the two questions the case feature rests on, neither of which is safe to
-- assume: does the engine let string.upper touch a secret, and does Scoot ship a font that
-- capitalises without one.
--
-- Arms every ruler, then reads them all one frame later. The wait is not politeness --
-- read in the same frame, the font has not reached the rasteriser and the widths are
-- whichever face happened to be resident.
local function DebugNameTextCaseProbe()
    local keys = {}
    for k in pairs(addon.Fonts or {}) do keys[#keys + 1] = k end
    table.sort(keys)

    for i, key in ipairs(keys) do
        local face = addon.ResolveFontFace(key)
        for j = 1, #CASE_PROBE_STRINGS do
            local fs = caseProbeRuler((i - 1) * #CASE_PROBE_STRINGS + j)
            addon.ApplyFontStyle(fs, face, 24, "")
            if fs.SetTextScale then pcall(fs.SetTextScale, fs, 1) end
            if fs.SetWordWrap then pcall(fs.SetWordWrap, fs, false) end
            pcall(fs.SetText, fs, CASE_PROBE_STRINGS[j])
        end
    end

    C_Timer.After(0, function()
        local lines, push = addon.DebugLines()

        push("NAME TEXT -- CASE PROBE")
        push("")
        push("QUESTION 1: does string.upper accept a secret value?")
        push("  This is the one that decides whether 'all caps' can work on any font, or")
        push("  only on fonts that capitalise by themselves. It is a question about")
        push("  Blizzard's whitelist, so it is asked, not reasoned about.")
        push("")
        push("  current name source:  " .. safeStr(lastSource))
        push("  name is secret:       " .. tostring(currentIsSecret and true or false))

        if type(currentRaw) ~= "string" then
            push("")
            push("  NOT ASKED -- there is no name loaded. This is not a refusal and it is")
            push("  not a result: nothing was passed to string.upper at all. Target a")
            push("  restricted NPC and run this again.")
        else
            local ok, upper = pcall(string.upper, currentRaw)
            if ok and type(upper) == "string" then
                local stillSecret = (issecretvalue and issecretvalue(upper)) and true or false
                push("  RESULT: ACCEPTED -- returned a string.")
                push("  result is secret:     " .. tostring(stillSecret))
                if currentIsSecret then
                    push("")
                    push("  This is the interesting case. A secret went in and a secret came out,")
                    push("  which is the same contract string.format and concatenation already")
                    push("  have: the value is transformed without ever being exposed. All-caps")
                    push("  works on restricted names, on any font.")
                else
                    push("")
                    push("  Readable name, readable result -- expected, and it proves nothing")
                    push("  about the restricted case. Re-run while targeting a dungeon NPC.")
                end
            else
                push("  RESULT: REFUSED -- " .. safeStr(ok and ("returned " .. type(upper))
                    or (upper ~= nil and tostring(upper) or "error carried no message")))
                push("")
                push("  All-caps by string transform is dead. The only remaining route is a")
                push("  font whose lowercase codepoints hold capital glyphs -- see below.")
            end

            -- The refusal message names its mechanism -- "string CONVERSION" -- so the
            -- boundary is worth mapping rather than inferring from one data point. Every
            -- row runs against the live name; nothing here uses a result, only its type
            -- and its secrecy, so no row can throw a second time downstream.
            push("")
            push("  Which string operations survive, measured on this name:")
            push("")
            push(string.format("    %-28s %-10s %s", "OPERATION", "RESULT", "detail"))
            push("    " .. string.rep("-", 72))

            local OPS = {
                { "a .. name",            function(s) return "a" .. s end },
                { "string.format('%s',_)", function(s) return string.format("%s", s) end },
                { "string.join('',_)",    function(s) return string.join("", s) end },
                { "tostring(_)",          function(s) return tostring(s) end },
                { "string.upper(_)",      function(s) return string.upper(s) end },
                { "strupper(_)",          function(s) return strupper(s) end },
                { "string.lower(_)",      function(s) return string.lower(s) end },
                { "string.rep(_,1)",      function(s) return string.rep(s, 1) end },
                { "string.sub(_,1,1)",    function(s) return string.sub(s, 1, 1) end },
                { "string.gsub(_,'a','a')", function(s) return (string.gsub(s, "a", "a")) end },
                { "#_",                   function(s) return #s end },
            }

            for _, op in ipairs(OPS) do
                local okOp, res = pcall(op[2], currentRaw)
                local verdict, detail
                if not okOp then
                    verdict = "ERROR"
                    detail  = safeStr(res ~= nil and tostring(res) or "no message")
                    -- The interesting half of the message is the reason, not the
                    -- traceback; keep it to one line so the table stays readable.
                    detail  = detail:gsub("^.-:%d+:%s*", "")
                else
                    local sec = (issecretvalue and issecretvalue(res)) and true or false
                    verdict = sec and "ok (secret)" or "ok (PLAIN)"
                    detail  = "returned " .. type(res)
                        .. (sec and "" or "  <== readable result from a secret input")
                end
                push(string.format("    %-28s %-10s %s", op[1], verdict, detail))
            end

            push("")
            push("  Read the pattern, not the rows. The operations that survive are the")
            push("  ones Blizzard taught to PROPAGATE secrecy; the ones that fail all")
            push("  coerce their argument to a string first, and that conversion is the")
            push("  gate. It is not about indices or arithmetic -- string.upper needs")
            push("  neither and is still refused.")
        end

        push("")
        push("QUESTION 2: which shipped fonts capitalise on their own?")
        push("  Measured on a private ruler per face, read one frame after arming. The")
        push("  lowercase alphabet against the uppercase one: a face that maps lowercase")
        push("  to capital glyphs reports them exactly equal.")
        push("")
        push("  The i/W columns are the guard against reading that backwards. A")
        push("  MONOSPACED face also reports the two alphabets as equal -- 26 characters")
        push("  times one advance, whatever the glyphs are -- so equal alphabet widths")
        push("  only mean capitals when the face is NOT monospaced. 'i' and 'W' equal")
        push("  means monospaced, and its ratio column carries no information.")
        push("")
        push(string.format("  %-22s %8s %8s %7s %7s %7s  %s",
            "FACE", "lower", "UPPER", "ratio", "i-run", "W-run", "verdict"))
        push("  " .. string.rep("-", 84))

        local allCaps, mono, unmeasured = {}, {}, {}
        for i, key in ipairs(keys) do
            local base = (i - 1) * #CASE_PROBE_STRINGS
            local wl = plainNumber(caseProbeRuler(base + 1), "GetUnboundedStringWidth")
            local wu = plainNumber(caseProbeRuler(base + 2), "GetUnboundedStringWidth")
            local wn = plainNumber(caseProbeRuler(base + 3), "GetUnboundedStringWidth")
            local ww = plainNumber(caseProbeRuler(base + 4), "GetUnboundedStringWidth")

            if wl and wu and wn and ww and wu > 0 and ww > 0 then
                local ratio = wl / wu
                -- Sub-pixel rasterisation means "identical" is not bit-exact; a
                -- thousandth is far tighter than any real gap, which runs 10-20%.
                local sameAlpha = math.abs(ratio - 1) < 0.001
                -- 10%, not 0.1%. Measured: monospaced faces come back 0.4-2.5% apart
                -- (JetBrains 147.1/147.7, Dogica 236.9/242.9) because ten glyphs of
                -- sub-pixel rounding accumulate, while the nearest PROPORTIONAL face is
                -- 33% apart and most are 3-4x. The gap between the two populations is
                -- enormous, so the threshold only has to land inside it -- and at 0.1%
                -- it landed below both, catching nothing and passing six monospaced
                -- faces through as all-caps.
                local spread    = math.min(wn, ww) / math.max(wn, ww)
                local isMono    = spread > 0.90

                local verdict = ""
                if isMono then
                    verdict = sameAlpha and "monospaced -- ratio proves nothing"
                                        or "monospaced (uneven alphabets?)"
                    mono[#mono + 1] = key
                elseif sameAlpha then
                    verdict = "lowercase renders as CAPITALS"
                    allCaps[#allCaps + 1] = key
                end

                push(string.format("  %-22s %8.1f %8.1f %7.3f %7.1f %7.1f  %s",
                    key, wl, wu, ratio, wn, ww, verdict))
            else
                unmeasured[#unmeasured + 1] = key
                push(string.format("  %-22s %8s %8s %7s %7s %7s  %s",
                    key, "-", "-", "-", "-", "-", "unmeasurable"))
            end
        end

        push("")
        if #allCaps > 0 then
            push("  All-caps faces: " .. table.concat(allCaps, ", "))
            push("  Any of these renders an unreadable name in capitals with no string")
            push("  transform at all: '/scoot debug nametext font <FACE>'.")
        else
            push("  NO shipped face maps lowercase to full capitals. If question 1 refused,")
            push("  all-caps needs a new font file, not new code.")
        end
        if #mono > 0 then
            push("")
            push("  Monospaced (excluded, not candidates): " .. table.concat(mono, ", "))
        end
        if #unmeasured > 0 then
            push("")
            push("  Unmeasurable: " .. table.concat(unmeasured, ", "))
        end

        push("")
        push("  On the small-caps pair: PIXELOP_SC and PIXELOP_SCBOLD report 1.000 while")
        push("  being clearly proportional, so they DO capitalise. What width cannot say")
        push("  is at what height -- small capitals sharing the advance widths of full")
        push("  ones look identical from here. Whether they read as 'all caps' or as")
        push("  'first letter larger' is a screen question, and it is the only question")
        push("  this table leaves open rather than answers.")
        push("")
        push("  There is no third route to mixed sizing. WoW's text markup has |cff for")
        push("  colour and nothing for size, so one FontString cannot mix two sizes even")
        push("  on readable text, and the clipped-copy trick needs every copy")
        push("  glyph-identical, which two sizes are not.")

        addon.DebugShowWindow("Name Text - Case Probe", lines)
    end)
end

local CASE_NOTE = {
    normal    = "  (the name exactly as the game handed it over)",
    upper     = "  (string.upper on the name -- works only if the engine allows it on secrets)",
    smallcaps = "  (no string touched: a font whose lowercase glyphs are small capitals)",
}

local function DebugNameTextSetCase(which, face)
    ensureShown()
    which = tostring(which or ""):lower()
    if which ~= "normal" and which ~= "upper" and which ~= "smallcaps" then
        addon:Print("Case must be one of: normal | upper | smallcaps")
        return
    end

    cfg.case = which
    if which == "smallcaps" and face and face ~= "" then cfg.scFace = face end

    -- Redo the transform against the new mode before anything measures the result.
    applyCaseTransform()
    scheduleFit()

    addon:Print("Case: " .. cfg.case .. (CASE_NOTE[which] or ""))
    if which == "smallcaps" then
        addon:Print("  rendering face: " .. cfg.scFace
            .. "  ('/scoot debug nametext case smallcaps <FACE>' to try another)")
    elseif which == "upper" then
        if caseMethod == "string.upper" then
            addon:Print("  result: accepted"
                .. (caseOutSecret and " (result is still secret, as expected)" or ""))
        elseif caseMethod == "no name" then
            addon:Print("  result: not asked -- no name loaded. Target something first;")
            addon:Print("          the transform runs on the next name, not on nothing.")
        else
            addon:Print("  result: REFUSED -- " .. safeStr(caseError or "no message")
                .. "; rendering unchanged case")
        end
    end
end

local function DebugNameTextSample(n)
    ensureShown()
    n = math.floor(tonumber(n) or 1)
    local index = ((n - 1) % #SAMPLES) + 1
    setValue(SAMPLES[index], false, "sample " .. index)
    scheduleFit()
    addon:Print(string.format("Sample %d/%d: %s", index, #SAMPLES, SAMPLES[index]))
end

local GRADIENT_NOTE = {
    auto  = "  (class ramp on players, solid white on everything else)",
    off   = "  (solid start color)",
    white = "  (solid white for every unit)",
    line  = "  (force the per-line ramp; white if the name is secret)",
    block = "  (force one ramp across the whole name)",
    slice = "  (force the clipped-column stack; works on secret text, bands the box)",
}

local function DebugNameTextSetGradient(mode)
    ensureShown()
    mode = tostring(mode or ""):lower()
    if not GRADIENT_NOTE[mode] then
        addon:Print("Gradient must be one of: auto | off | white | line | block | slice")
        return
    end
    cfg.gradient = mode
    scheduleFit()
    addon:Print("Gradient: " .. cfg.gradient .. (GRADIENT_NOTE[mode] or ""))
end

-- The size the fit gives up to stay clear of the blind spot. Exposed because it is a
-- genuine trade -- 'off' renders every name as large as the box allows and occasionally
-- clips three characters off one; 'auto' never clips and runs slightly smaller.
local function DebugNameTextSetMargin(value)
    ensureShown()
    value = tostring(value or ""):lower()

    if value == "off" or value == "auto" then
        cfg.margin = value
    else
        local n = tonumber(value)
        if not n or n < 0 then
            addon:Print("Margin must be: auto | off | <pixels>")
            return
        end
        cfg.margin = math.floor(n)
    end

    scheduleFit()
    addon:Print("Blind-spot margin: " .. tostring(cfg.margin)
        .. ((cfg.margin == "auto") and "  (the measured width of \"...\")"
            or (cfg.margin == "off") and "  (names run larger; one clipped by exactly "
                .. "three characters will look like a perfect fit)"
            or "px"))
end

-- The box has no backdrop and no border by design. This exists only so it can be
-- found and dragged.
local function DebugNameTextToggleChrome()
    ensureShown()
    cfg.chrome = not cfg.chrome
    if chromeBG then chromeBG:SetShown(cfg.chrome) end
    addon:Print(cfg.chrome
        and "Chrome ON - drag the panel to reposition, then turn it back off."
        or  "Chrome OFF - text only, as it would ship.")
end

local function DebugNameTextSetSlices(n)
    ensureShown()
    cfg.slices = math.max(1, math.min(64, math.floor(tonumber(n) or cfg.slices)))
    scheduleFit()
    addon:Print("Slice columns: " .. cfg.slices)
end

local function DebugNameTextSetClass(token)
    ensureShown()
    token = token and token ~= "" and token or "auto"
    if token:lower() == "auto" then
        cfg.forcedClass = nil
        addon:Print("Class: auto (read from target)")
    else
        cfg.forcedClass = token:upper()
        addon:Print("Class forced to: " .. cfg.forcedClass)
    end
    scheduleFit()
end

local function DebugNameTextSetTreatment(which)
    ensureShown()
    which = tostring(which or ""):lower()
    if which ~= "cast" and which ~= "raw" then
        addon:Print("Treatment must be one of: cast | raw")
        return
    end
    cfg.treatment = which
    scheduleFit()
    addon:Print("Treatment: " .. cfg.treatment
        .. (which == "cast" and "  (start = class color darkened 25%)"
                             or "  (start = class color untouched)"))
end

local buildReport = NT._BuildReport

local function DebugNameTextSetIdentity(which)
    ensureShown()
    which = tostring(which or ""):lower()
    if which ~= "player" and which ~= "class" then
        addon:Print("Identity must be one of: player | class")
        return
    end
    cfg.identity = which
    scheduleFit()
    addon:Print("Identity: " .. cfg.identity
        .. (which == "player" and "  (class ramp only when UnitIsPlayer)"
                               or "  (class ramp whenever a class token resolves)"))
end

-- Which units, right now, report restricted identity? Capital-city NPCs come
-- back unrestricted, so "target an NPC" is not a reliable way to exercise the secret
-- path. This sweeps every unit token worth trying and says which ones qualify.
local SCAN_UNITS = {
    "player", "target", "targettarget", "focus", "mouseover", "pet",
    "boss1", "boss2", "boss3", "boss4", "boss5",
    "arena1", "arena2", "arena3",
    "party1", "party2", "party3", "party4",
    "nameplate1", "nameplate2", "nameplate3", "nameplate4", "nameplate5",
    "nameplate6", "nameplate7", "nameplate8", "nameplate9", "nameplate10",
}

local function DebugNameTextScan()
    local lines, push = addon.DebugLines()

    push("== Unit identity secrecy sweep ==")
    push("")
    if C_Secrets and C_Secrets.HasSecretRestrictions then
        local ok, v = pcall(C_Secrets.HasSecretRestrictions)
        push("HasSecretRestrictions(): " .. (ok and safeStr(v) or "<error>"))
    end
    push("InCombatLockdown():      " .. safeStr(InCombatLockdown()))
    push("")
    push("unit            exists  isPlayer  shouldBeSecret  nameIsSecret")
    push(string.rep("-", 64))

    local secretCount = 0
    for _, unit in ipairs(SCAN_UNITS) do
        local okE, exists = pcall(UnitExists, unit)
        if okE and exists then
            local _, isPlayer = pcall(UnitIsPlayer, unit)

            local shouldSecret = "n/a"
            if C_Secrets and C_Secrets.ShouldUnitIdentityBeSecret then
                local okS, v = pcall(C_Secrets.ShouldUnitIdentityBeSecret, unit)
                shouldSecret = okS and safeStr(v) or "<error>"
            end

            -- The ground truth: ask for the name and see what comes back.
            local nameSecret = "n/a"
            local okN, name = pcall(UnitName, unit)
            if okN and type(name) ~= "nil" then
                nameSecret = (issecretvalue and issecretvalue(name)) and "SECRET" or "plain"
                if nameSecret == "SECRET" then secretCount = secretCount + 1 end
            end

            push(string.format("%-15s %-7s %-9s %-15s %s",
                unit, "yes", safeStr(isPlayer), shouldSecret, nameSecret))
        end
    end

    push("")
    if secretCount > 0 then
        push(secretCount .. " unit(s) returned a SECRET name. Target one and run "
            .. "'/scoot debug nametext report' to exercise the secret path.")
    else
        push("No unit currently returns a secret name. Retry in combat, in an instance,")
        push("or against hostile/boss units -- restriction level is contextual.")
    end

    addon.DebugShowWindow("Unit Identity Secrecy Sweep", lines)
end

--------------------------------------------------------------------------------
-- SetAlphaGradient length oracle probe
--------------------------------------------------------------------------------
-- The calibration pass that established the oracle's semantics. The primitives it
-- exercises now live at the top of the file, because the renderer depends on them.
--
-- Probed on two subjects, because which one answers reveals what it counts:
--   free    -- no width, wrap off: holds the whole string, so its transition is the
--              STRING length
--   display -- the harness box: wrapped and possibly ellipsized. A lower transition
--              here means the oracle counts RENDERED characters, which makes it a
--              truncation detector rather than a strlen. Both turned out to be true,
--              and the second is the one the fitter is built on.

-- Exhaustive sweep. Bisection is what a shipping fitter would use, but it only gives
-- the right answer if the predicate is monotonic, and that is exactly the assumption
-- under test -- so measure every index once and check.
local function alphaScan(fs, limit)
    local out = { seq = {}, calls = 0, monotonic = true }
    local sawFalse = false
    for i = 0, limit do
        local v, tag = alphaProbe(fs, i, 1)
        out.calls = out.calls + 1
        out.seq[i] = (v == true and "T") or (v == false and "F") or tag
        if tag then
            if tag == "SECRET" and not out.firstSecret then out.firstSecret = i end
            if not out.firstBad then out.firstBad = i .. ":" .. tag end
        elseif v then
            out.lastTrue = i
            if sawFalse then out.monotonic = false end
        else
            sawFalse = true
            if not out.firstFalse then out.firstFalse = i end
        end
    end
    return out
end
NT._AlphaScan = alphaScan

local buildProbeReport = NT._BuildProbeReport

local function DebugNameTextLengthProbe()
    ensureShown()
    if not lastSource then pullTargetName() end

    -- Fit first, so Probe B describes the layout the harness renders. Then
    -- force the PLAIN value back on: under a |cff ramp every index is a markup byte
    -- and both counts become meaningless.
    runFit(function()
        applyValue()

        local free = ensureProbeFS()
        addon.ApplyFontStyle(free, addon.ResolveFontFace(effectiveFaceKey()), cfg.maxSize, cfg.style)
        if free.SetTextScale then pcall(free.SetTextScale, free, 1) end
        if free.ClearText then pcall(free.ClearText, free) end
        pcall(free.SetText, free, currentValue)

        -- Both subjects were just re-texted. A FontString that has not been laid out
        -- since its last SetText reports stale geometry, and if the oracle turns out
        -- to be layout-driven it would answer about the previous string. Same
        -- one-frame settle the fitter needs.
        C_Timer.After(0, function()
            buildProbeReport()
            runFit()  -- repaint whatever the gradient mode was drawing
        end)
    end)
end

--------------------------------------------------------------------------------
-- Oracle-driven fit probe: does D(size) settle within the same frame?
--------------------------------------------------------------------------------
-- The length probe established two things: SetAlphaGradient answers on a secret
-- string, and its answer is LAYOUT-sensitive -- on a box-constrained FontString it
-- counts the characters that rendered. So as the font grows and the engine
-- starts consuming break characters and ellipsizing, the count falls. Call that
-- D(size).
--
-- D being monotonic in size is what makes a blind shrink-to-fit possible: read D at
-- the smallest size to get the ceiling, then bisect for the largest size that still
-- hits it. That is the largest size which loses nothing -- computed without reading a
-- byte and without asking for a single dimension.
--
-- Whether it is PRACTICAL comes down to settling. If D reflects a size change in the
-- same frame, the entire search is one synchronous function costing ~40 oracle calls.
-- If it lags a frame, every candidate costs a frame and the name visibly steps through
-- ~6 sizes after each target change. Both are workable, but they are different
-- designs, and assuming the convenient one is exactly how the previous round of this
-- work went wrong. So measure D three times per size -- immediately, one frame later,
-- two frames later -- and compare the columns.
--
-- The +2 frame column is the control on the control. If it disagrees with +1, the
-- deferred reads are not settled either and neither column can be treated as truth.

local FITPROBE_STEPS = 12

-- Whatever layout the fitter would have applied, applied by hand. The probe drives the
-- point size directly rather than SetTextScale whatever cfg.mode says, because a
-- size-bisecting fitter is a point-size design -- scaling a fitted string is a
-- different question.
local function fitProbeLayout()
    if nameFS.SetWordWrap then pcall(nameFS.SetWordWrap, nameFS, true) end
    if nameFS.SetMaxLines then pcall(nameFS.SetMaxLines, nameFS, cfg.maxLines) end
    if nameFS.SetTextScale then pcall(nameFS.SetTextScale, nameFS, 1) end
end

local function buildSizeLadder(steps)
    local lo, hi = cfg.minSize, cfg.maxSize
    if hi < lo then lo, hi = hi, lo end

    steps = math.max(3, math.min(math.floor(tonumber(steps) or FITPROBE_STEPS), 44))

    local out, seen = {}, {}
    for i = 0, steps - 1 do
        local s = math.floor(lo + (hi - lo) * i / (steps - 1) + 0.5)
        if not seen[s] then
            seen[s] = true
            out[#out + 1] = s
        end
    end
    return out
end

local buildFitProbeReport = NT._BuildFitProbeReport

local function DebugNameTextFitProbe(steps)
    ensureShown()
    if not lastSource then pullTargetName() end

    if not nameFS or type(nameFS.SetAlphaGradient) ~= "function" then
        addon.DebugShowWindow("Oracle Fit Probe", {
            "FontString:SetAlphaGradient is not present in this build.",
            "There is no oracle to drive a fit with.",
        })
        return
    end

    local ladder = buildSizeLadder(steps)
    local face = addon.ResolveFontFace(effectiveFaceKey())
    local rows, calls, frames = {}, 0, 0

    -- Fit first so the harness is in a known state, then force the PLAIN value back on:
    -- under a |cff ramp every index is a markup byte and D counts nothing meaningful.
    runFit(function()
        applyValue()
        fitProbeLayout()

        local free = ensureProbeFS()
        addon.ApplyFontStyle(free, face, cfg.maxSize, cfg.style)
        if free.SetTextScale then pcall(free.SetTextScale, free, 1) end
        if free.ClearText then pcall(free.ClearText, free) end
        pcall(free.SetText, free, currentValue)

        -- Both subjects were just re-texted; let that land before anything is measured,
        -- or the first row reports on the previous string rather than the previous size.
        C_Timer.After(0, function()
            frames = frames + 1

            local freeCount, freeCalls, freeTag = measureCount(free)
            calls = calls + freeCalls

            local i = 1
            local function step()
                if i > #ladder then
                    buildFitProbeReport(rows, freeCount, freeTag, calls, frames)
                    runFit()   -- hand the box back to the normal fit + gradient path
                    return
                end

                local row = { size = ladder[i] }
                rows[i] = row

                addon.ApplyFontStyle(nameFS, face, row.size, cfg.style)
                fitProbeLayout()

                -- No yield between the size change and this read. That is the question.
                local c
                row.same, c, row.sameTag = measureCount(nameFS)
                calls = calls + c

                C_Timer.After(0, function()
                    frames = frames + 1
                    row.d1, c, row.d1Tag = measureCount(nameFS)
                    calls = calls + c

                    C_Timer.After(0, function()
                        frames = frames + 1
                        row.d2, c, row.d2Tag = measureCount(nameFS)
                        calls = calls + c
                        i = i + 1
                        step()
                    end)
                end)
            end
            step()
        end)
    end)
end

--------------------------------------------------------------------------------
-- autofit: the sizing pass, with its working shown
--------------------------------------------------------------------------------
-- Same code as the normal render -- this command adds no measurement of its own. It
-- runs a render and then prints the derivation the renderer threw away: every
-- candidate size, the uncapped count, the capped count, the line budget, and which of
-- the three checks rejected it. If the box looks wrong, this is the table that says
-- why.

local buildAutoFitReport = NT._BuildAutoFitReport

-- Renders exactly as normal, then prints the derivation. No separate measurement pass:
-- a report that measured things its own way would be describing a different fit.
local function DebugNameTextAutoFit()
    ensureShown()
    if not lastSource then pullTargetName() end

    if not nameFS or type(nameFS.SetAlphaGradient) ~= "function" then
        addon.DebugShowWindow("Auto Fit", {
            "FontString:SetAlphaGradient is not present in this build.",
            "Without the oracle there is nothing to size from.",
        })
        return
    end

    renderName(function()
        if lastFit then
            buildAutoFitReport(lastFit)
        else
            addon.DebugShowWindow("Auto Fit", { "No fit was produced." })
        end
    end)
end

local function DebugNameTextReport()
    ensureShown()
    if not lastSource then pullTargetName() end

    runFit(function()
        -- Two reasons this cannot be dumped inline. The cross-check has to look at the
        -- PLAIN name, because under a |cff ramp every count is markup and GetNumLines
        -- would be answering about a different string. And a read taken in the same
        -- frame as the paint describes the layout BEFORE it -- which is how a report can
        -- show GetNumLines from the previous target and read as a contradiction.
        applyValue()
        C_Timer.After(0, function()
            buildReport()
            runFit()   -- hand the box back to the normal colour path
        end)
    end)
end

-- The Unit Frames Z name box, built as it would ship.
addon:RegisterDebugCommand({
    name = "nametext", help = "Unit Frames Z name box", default = "toggle",
    verbs = {
        { word = "toggle", help = "show or hide the box", fn = DebugNameTextToggle },
        { word = "size", usage = "size <w> <h>", fn = DebugNameTextSetSize },
        { word = "lines", usage = "lines <n>", fn = DebugNameTextSetLines },
        { word = "range", usage = "range <min> <max>", fn = DebugNameTextSetRange },
        { word = "fallback", usage = "fallback <n>", help = "size when unmeasurable", fn = DebugNameTextSetFallback },
        { word = "mode", usage = "mode <font|scale|blizzard>", fn = DebugNameTextSetMode },
        { word = "font", usage = "font <FACE>", help = "font keys are case-sensitive", fn = DebugNameTextSetFont },
        { word = "case", usage = "case <normal|upper|smallcaps> [FACE]", fn = DebugNameTextSetCase },
        { word = "caseprobe", help = "can string.upper touch a secret?", fn = DebugNameTextCaseProbe },
        { word = "sample", usage = "sample <n>", fn = DebugNameTextSample },
        { word = "gradient", usage = "gradient <auto|off|white|line|block|slice>", fn = DebugNameTextSetGradient },
        { word = "chrome", help = "backdrop on/off, to drag the box", fn = DebugNameTextToggleChrome },
        { word = "margin", usage = "margin <auto|off|px>", help = "blind-spot safety margin", fn = DebugNameTextSetMargin },
        { word = "slices", usage = "slices <n>", fn = DebugNameTextSetSlices },
        { word = "class", usage = "class <TOKEN|auto>", help = "class tokens are uppercase", fn = DebugNameTextSetClass },
        { word = "treatment", usage = "treatment <cast|raw>", fn = DebugNameTextSetTreatment },
        { word = "identity", usage = "identity <player|class>", fn = DebugNameTextSetIdentity },
        { word = "scan", fn = DebugNameTextScan },
        { word = "lengthprobe", fn = DebugNameTextLengthProbe },
        { word = "fitprobe", usage = "fitprobe [steps]", help = "does D(size) settle?", fn = DebugNameTextFitProbe },
        { word = "autofit", help = "render, then show the size derivation", fn = DebugNameTextAutoFit },
        { word = "report", fn = DebugNameTextReport },
    },
})
