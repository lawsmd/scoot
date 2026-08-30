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

local frame, nameFS, chromeBG
local slicePool = {}

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

local function safeStr(v)
    if v == nil then return "nil" end
    if issecretvalue and issecretvalue(v) then return "<SECRET>" end
    local ok, s = pcall(tostring, v)
    return ok and s or "<error>"
end

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

local function measure(method)
    return measureOn(nameFS, method)
end

local function hex(r, g, b)
    return string.format("%02x%02x%02x",
        math.floor((r or 0) * 255 + 0.5),
        math.floor((g or 0) * 255 + 0.5),
        math.floor((b or 0) * 255 + 0.5))
end

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

-- true / false, or nil plus a tag describing why it was not a plain boolean.
local function alphaProbe(fs, start, length)
    if not fs or type(fs.SetAlphaGradient) ~= "function" then return nil, "noAPI" end
    local ok, within = pcall(fs.SetAlphaGradient, fs, start, length or 1)
    if not ok then return nil, "err" end
    if issecretvalue and issecretvalue(within) then return nil, "SECRET" end
    if within == true or within == false then return within end
    return nil, "nonbool(" .. safeStr(within) .. ")"
end

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

local function ensureSlice(index)
    local s = slicePool[index]
    if s then return s end

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

    s = { clip = clip, fs = fs }
    slicePool[index] = s
    return s
end

local function hideSlices()
    for _, s in ipairs(slicePool) do s.clip:Hide() end
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
        local s = ensureSlice(i)

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

    for i = n + 1, #slicePool do slicePool[i].clip:Hide() end
    return true
end

--------------------------------------------------------------------------------
-- Display state
--------------------------------------------------------------------------------

-- True while nameFS holds the raw value rather than a |cff-coded gradient string.
local plainApplied = false

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

-- Rulers are created once and never destroyed, but the size range is user-editable and
-- nothing stops someone typing 'range 1 500'. Coarsen rather than allocate 500 regions.
local MAX_CANDIDATES = 64

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
        addon.DebugNameTextRefresh(event == "UNIT_NAME_UPDATE")
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
function addon.DebugNameTextRefresh(hold)
    if not frame or not frame:IsShown() then return end
    pullTargetName(hold)
    runFit()
end

function addon.DebugNameTextToggle()
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
    addon.DebugNameTextRefresh()
end

function addon.DebugNameTextSetSize(w, h)
    ensureShown()
    cfg.width  = tonumber(w) or cfg.width
    cfg.height = tonumber(h) or cfg.height
    frame:SetSize(cfg.width, cfg.height)
    scheduleFit()
    addon:Print(string.format("Container: %dx%d", cfg.width, cfg.height))
end

function addon.DebugNameTextSetLines(n)
    ensureShown()
    cfg.maxLines = math.max(1, math.floor(tonumber(n) or cfg.maxLines))
    scheduleFit()
    addon:Print("Max lines: " .. cfg.maxLines)
end

function addon.DebugNameTextSetRange(minSize, maxSize)
    ensureShown()
    cfg.minSize = tonumber(minSize) or cfg.minSize
    cfg.maxSize = tonumber(maxSize) or cfg.maxSize
    scheduleFit()
    addon:Print(string.format("Font size range: %s - %s", tostring(cfg.minSize), tostring(cfg.maxSize)))
end

-- The size used when nothing can be measured, which is every restricted name. On the
-- secret path this is not an error size, it IS the render size.
function addon.DebugNameTextSetFallback(n)
    ensureShown()
    cfg.fallbackSize = math.max(1, math.floor(tonumber(n) or cfg.fallbackSize))
    scheduleFit()
    addon:Print("Fallback size (unmeasurable text): " .. cfg.fallbackSize)
end

function addon.DebugNameTextSetMode(mode)
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

function addon.DebugNameTextSetFont(face)
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
function addon.DebugNameTextCaseProbe()
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
        local lines = {}
        local function push(s) lines[#lines + 1] = s end

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

        addon.DebugShowWindow("Name Text - Case Probe", table.concat(lines, "\n"))
    end)
end

local CASE_NOTE = {
    normal    = "  (the name exactly as the game handed it over)",
    upper     = "  (string.upper on the name -- works only if the engine allows it on secrets)",
    smallcaps = "  (no string touched: a font whose lowercase glyphs are small capitals)",
}

function addon.DebugNameTextSetCase(which, face)
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

function addon.DebugNameTextSample(n)
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

function addon.DebugNameTextSetGradient(mode)
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
function addon.DebugNameTextSetMargin(value)
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
function addon.DebugNameTextToggleChrome()
    ensureShown()
    cfg.chrome = not cfg.chrome
    if chromeBG then chromeBG:SetShown(cfg.chrome) end
    addon:Print(cfg.chrome
        and "Chrome ON - drag the panel to reposition, then turn it back off."
        or  "Chrome OFF - text only, as it would ship.")
end

function addon.DebugNameTextSetSlices(n)
    ensureShown()
    cfg.slices = math.max(1, math.min(64, math.floor(tonumber(n) or cfg.slices)))
    scheduleFit()
    addon:Print("Slice columns: " .. cfg.slices)
end

function addon.DebugNameTextSetClass(token)
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

function addon.DebugNameTextSetTreatment(which)
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

local function buildReport()
    local lines = {}
    local function push(s) lines[#lines + 1] = s end

    local r = lastResult or {}
    local c = lastColors or {}

    push("== Scoot name box: what is on screen and why ==")
    push("")

    local verdict
    local tierNote = (r.tier == "loose")
        and " LOOSE tier: no size breaks this only at spaces, so it will break mid-word "
            .. "or at a hyphen."
        or ""
    if r.measurable == true and currentIsSecret then
        verdict = string.format(
            "SIZED A SECRET NAME - %s pt, %s line(s), chosen by the oracle alone.%s",
            safeStr(r.size), safeStr(r.lines), tierNote)
    elseif r.measurable == true then
        verdict = string.format(
            "SIZED - %s pt, %s line(s). This name was READABLE, so it does not exercise "
            .. "the restricted path; target an NPC in an instance for that.%s",
            safeStr(r.size), safeStr(r.lines), tierNote)
    elseif r.overflow then
        verdict = string.format(
            "DOES NOT FIT - no size in range clears this box, so it is rendering at %s "
            .. "and the engine's own '...' takes over. %s",
            safeStr(r.size), safeStr(r.reason))
    else
        verdict = string.format(
            "NOT MEASURED - rendering at the fallback size (%s), which was DECLARED, not "
            .. "measured. Reason: %s", safeStr(r.size), safeStr(r.reason))
    end
    push("SIZE VERDICT:     " .. verdict)

    local gverdict
    if lastGradientMode == "white" then
        gverdict = "solid white - " .. safeStr(lastGradientNote)
    elseif lastGradientMode == "slice" then
        gverdict = "slice stack active (" .. cfg.slices .. " columns) - works on secret text, "
                 .. "banded, ramp spans the box not each line"
    elseif lastRamped and lastLines and #lastLines > 1 then
        gverdict = #lastLines .. " lines, each with its own class ramp (via "
                 .. safeStr(lastDiscovery) .. ")"
    elseif lastRamped then
        gverdict = "single-line class ramp (via " .. safeStr(lastDiscovery)
                 .. ") - force a wrap to see the per-line behaviour"
    else
        gverdict = "no |cff ramp: " .. safeStr(lastGradientNote)
    end
    push("COLOR VERDICT:    " .. gverdict)
    push("")

    push("-- Restriction state --")
    if C_Secrets then
        if C_Secrets.HasSecretRestrictions then
            local ok, v = pcall(C_Secrets.HasSecretRestrictions)
            push("  HasSecretRestrictions():              " .. (ok and safeStr(v) or "<error>"))
        end
        if C_Secrets.ShouldUnitIdentityBeSecret then
            local ok, v = pcall(C_Secrets.ShouldUnitIdentityBeSecret, "target")
            push("  ShouldUnitIdentityBeSecret('target'): " .. (ok and safeStr(v) or "<error>"))
        end
    else
        push("  C_Secrets not present")
    end
    push("  InCombatLockdown():                   " .. safeStr(InCombatLockdown()))
    push("")

    push("-- Text source --")
    push("  source:            " .. safeStr(lastSource))
    push("  name was secret:   " .. safeStr(currentIsSecret))
    push("  GetText():         " .. measure("GetText"))
    push("")

    push("-- Anchoring (the gate) --")
    if type(nameFS.IsAnchoringSecret) == "function" then
        push("  fs:IsAnchoringSecret():   " .. measure("IsAnchoringSecret"))
    else
        push("  fs:IsAnchoringSecret():   <API not present>")
    end
    if frame.IsAnchoringSecret then
        local ok, v = pcall(frame.IsAnchoringSecret, frame)
        push("  frame:IsAnchoringSecret(): " .. (ok and safeStr(v) or "<error>"))
    end
    push("")

    -- The oracle decided this layout without being able to read a thing. On a READABLE
    -- name the engine will answer the same questions directly, so the two can be put
    -- side by side -- and any disagreement is the fit being wrong, stated in one line
    -- instead of inferred from four numbers further down. This is only possible on a
    -- readable name, which is exactly why readable names are worth targeting.
    push("-- Cross-check: the oracle's answer against what the engine did --")
    if currentIsSecret then
        push("  n/a - the name is secret, so the engine will not answer either. That is the")
        push("        condition the oracle exists for; calibrate on a readable name.")
    elseif not plainApplied then
        push("  n/a - a |cff ramp is on the FontString, so every count below is markup.")
    else
        local engineLines = addon.FitSafeNumber and addon.FitSafeNumber(nameFS, "GetNumLines")
        local engineTrunc = addon.FitSafeBool and addon.FitSafeBool(nameFS, "IsTruncated")
        local engineWidth = addon.FitSafeNumber and addon.FitSafeNumber(nameFS, "GetStringWidth")

        push("  fit predicted:      " .. safeStr(r.lines) .. " line(s) at " .. safeStr(r.size) .. " pt")
        push("  engine reports:     " .. safeStr(engineLines) .. " line(s), truncated "
            .. safeStr(engineTrunc))
        push("  widest line vs box: " .. safeStr(engineWidth) .. " / " .. cfg.width)

        local problems = {}
        if type(engineLines) == "number" and type(r.lines) == "number"
           and engineLines ~= r.lines then
            problems[#problems + 1] = string.format(
                "line count disagrees (%d vs %d) -- a break that ate no character",
                engineLines, r.lines)
        end
        if engineTrunc == true and r.overflow ~= true then
            problems[#problems + 1] = "the engine truncated a layout the fit accepted"
        end
        if type(engineLines) == "number" and lastFit and lastFit.spaces
           and engineLines > lastFit.spaces + 1 and r.tier ~= "loose" then
            problems[#problems + 1] = string.format(
                "%d line(s) for %d word(s) -- a word was broken in half",
                engineLines, lastFit.spaces + 1)
        end

        if #problems == 0 then
            push("  AGREES. The blind fit and the sighted engine describe the same layout.")
        else
            for _, p in ipairs(problems) do push("  *** DISAGREES: " .. p) end
        end
    end
    push("")

    push("-- Measurements --")
    push("  GetStringWidth():          " .. measure("GetStringWidth"))
    push("  GetUnboundedStringWidth(): " .. measure("GetUnboundedStringWidth"))
    push("  GetStringHeight():         " .. measure("GetStringHeight"))
    push("  GetWrappedWidth():         " .. measure("GetWrappedWidth"))
    push("  GetNumLines():             " .. measure("GetNumLines"))
    push("  IsTruncated():             " .. measure("IsTruncated"))
    push("  GetLineHeight():           " .. measure("GetLineHeight"))
    push("  GetMaxLines():             " .. measure("GetMaxLines"))
    push("  GetTextScale():            " .. measure("GetTextScale"))
    push("  fs GetWidth()/GetHeight(): " .. measure("GetWidth") .. " x " .. measure("GetHeight"))
    push("")

    push("-- Fit result --")
    push("  box:         " .. string.format("%dx%d", cfg.width, cfg.height))
    push("  size range:  " .. safeStr(cfg.minSize) .. " - " .. safeStr(cfg.maxSize))
    push("  fallback:    " .. safeStr(cfg.fallbackSize) .. "  (used only when the oracle fails)")
    push("  max lines:   " .. safeStr(cfg.maxLines))
    push("  font face:   " .. safeStr(cfg.face) .. " (" .. safeStr(cfg.style) .. ")")
    if effectiveFaceKey() ~= cfg.face then
        push("  rendering as: " .. safeStr(effectiveFaceKey())
            .. "  (case mode '" .. safeStr(cfg.case) .. "' overrides the face)")
    end
    push("  case:        " .. safeStr(cfg.case) .. "  via " .. safeStr(caseMethod)
        .. (caseError and ("  -- " .. safeStr(caseError)) or ""))
    if caseMethod == "string.upper" then
        push("  -> upper on secret: result still secret = " .. safeStr(caseOutSecret))
    end
    push("  -> measurable:  " .. safeStr(r.measurable))
    push("  -> fallback:    " .. safeStr(r.fallback)
        .. (r.fallback and "  (size below was DECLARED, not measured)" or ""))
    push("  -> overflow:    " .. safeStr(r.overflow)
        .. (r.overflow and "  (measured fine; the name simply does not fit)" or ""))
    push("  -> secretText:  " .. safeStr(r.secretText))
    push("  -> applied size:" .. safeStr(r.size))
    push("  -> lines:       " .. safeStr(r.lines)
        .. "  (F - D + 1, verified by re-rendering under that exact cap)")
    push("  -> line budget: " .. safeStr(r.budget)
        .. "  (min of maxLines and boxHeight/lineHeight at the chosen size)")
    push("  -> tier:        " .. safeStr(r.tier)
        .. ((r.tier == "clean") and "  (breaks only at spaces)"
            or (r.tier == "loose") and "  (had to allow a mid-word or hyphen break)" or ""))
    push("  -> first rejection:  " .. safeStr(r.stopped)
        .. "  (not where the scan stopped -- phase 2 keeps going past it)")
    if r.reason then push("  -> reason:      " .. safeStr(r.reason)) end

    local f = lastFit
    if f then
        push("  -- oracle inputs --")
        push("     F (characters):  " .. safeStr(f.F))
        push("     spaces:          " .. safeStr(f.spaces)
            .. "  (@" .. SQUEEZE_A .. "px " .. safeStr(f.spacesA)
            .. ", @" .. SQUEEZE_B .. "px " .. safeStr(f.spacesB) .. ")")
        if f.F and f.spaces then
            push("     valid D range:   [" .. (f.F - f.spaces) .. ", " .. f.F .. "]")
        end
        push("     candidates:      " .. #(f.sizes or {}) .. " sizes, step " .. safeStr(f.step))
        push("     cost:            " .. safeStr(f.calls) .. " oracle calls over "
            .. safeStr(f.frames) .. " deferred frames")
        push("     (full scan table: /scoot debug nametext autofit)")
    end
    push("")

    push("-- Gradient --")
    push("  requested:      " .. safeStr(cfg.gradient))
    push("  effective:      " .. safeStr(lastGradientMode))
    push("  treatment:      " .. safeStr(cfg.treatment))
    push("  identity:       " .. safeStr(cfg.identity))
    push("  UnitIsPlayer('target'): " .. safeStr(targetIsPlayer()))
    push("  class token:    " .. safeStr(c.token) .. (cfg.forcedClass and "  (forced)" or ""))
    push("  ramp start:     #" .. hex(c.r1, c.g1, c.b1))
    push("  ramp end:       #" .. hex(c.r2, c.g2, c.b2))
    push("  discovery path: " .. safeStr(lastDiscovery))
    push("  on the FontString: " .. (plainApplied and "the plain name"
        or "a |cff-coded ramp string"))
    if lastGradientNote then push("  note:           " .. safeStr(lastGradientNote)) end
    push("  slice columns:  " .. safeStr(cfg.slices)
        .. ((lastGradientMode == "slice") and "  (live)" or "  (idle)"))
    push("")

    -- Everything under "Measurements" above describes the MASTER FontString, which is
    -- held at alpha 0 while the slice stack is drawing. So the master can fit perfectly
    -- and the screen can still be wrong. These are the copies you are looking
    -- at; any disagreement with the master localises the bug to the replay.
    push("-- Slice stack (what is on screen in slice mode) --")
    local s1 = slicePool[1]
    if lastGradientMode ~= "slice" then
        push("  idle - the master FontString above is what is drawing")
    elseif not s1 then
        push("  slice mode active but no slices were built")
    else
        push("  replayed size:      " .. safeStr(lastSliceSize)
            .. "   scale " .. safeStr(lastSliceScale)
            .. (lastSliceFallback and "   *** FROM A FALLBACK FIT, not a measurement ***" or ""))
        push("  replayed maxLines:  " .. safeStr(lastSliceMaxLines)
            .. "   (from result.maxLines - what the fit applied, not a read-back)")
        push("  slice[1] GetNumLines():       " .. measureOn(s1.fs, "GetNumLines"))
        push("  slice[1] IsTruncated():       " .. measureOn(s1.fs, "IsTruncated"))
        push("  slice[1] GetMaxLines():       " .. measureOn(s1.fs, "GetMaxLines"))
        push("  slice[1] GetLineHeight():     " .. measureOn(s1.fs, "GetLineHeight"))
        push("  slice[1] GetStringWidth():    " .. measureOn(s1.fs, "GetStringWidth"))
        push("  slice[1] GetStringHeight():   " .. measureOn(s1.fs, "GetStringHeight"))
        push("  slice[1] GetWordWrap():       " .. measureOn(s1.fs, "GetWordWrap"))
        push("  slice[1] fs W/H:              " .. measureOn(s1.fs, "GetWidth")
            .. " x " .. measureOn(s1.fs, "GetHeight"))
        push("  slice[1] IsAnchoringSecret(): " .. measureOn(s1.fs, "IsAnchoringSecret"))
        push("  clip[1] W/H:                  " .. measureOn(s1.clip, "GetWidth")
            .. " x " .. measureOn(s1.clip, "GetHeight"))
        push("  slices built:                 " .. #slicePool)
    end
    push("")

    push("-- Discovered lines --")
    if lastLines then
        for i, ln in ipairs(lastLines) do
            push(string.format("  [%d] bytes %s-%s  left=%s width=%s%s",
                i, safeStr(ln.first), safeStr(ln.last),
                ln.left and string.format("%.1f", ln.left) or "n/a",
                ln.width and string.format("%.1f", ln.width) or "n/a",
                ln.overflow and "  OVERFLOW" or ""))
            push("      \"" .. safeStr(ln.text) .. "\"")
        end
    else
        push("  none")
    end
    push("")

    -- What went onto the FontString. Per-character |cff markup turns every
    -- glyph into its own shaping run, so the ramped width is not automatically the
    -- plain width -- compare them here rather than assume.
    push("-- Ramped string --")
    if lastRamped then
        push("  total bytes:   " .. #lastRamped)
        local face = addon.ResolveFontFace(effectiveFaceKey())
        local size = (lastResult and lastResult.size) or cfg.maxSize
        local seg = 0
        for chunk in (lastRamped .. "\n"):gmatch("(.-)\n") do
            seg = seg + 1
            local stripped = chunk:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
            local rw = addon.MeasureTextWidth(chunk, face, size, cfg.style)
            local pw = addon.MeasureTextWidth(stripped, face, size, cfg.style)
            push(string.format("  [%d] %d chars  plain=%s  ramped=%s  box=%d",
                seg, #stripped,
                pw and string.format("%.1f", pw) or "nil",
                rw and string.format("%.1f", rw) or "nil",
                cfg.width))
            push("      \"" .. stripped .. "\"")
        end
        push("  segments:      " .. seg)
    else
        push("  none")
    end
    push("")

    push("-- Environment --")
    push("  AutoScalingFontStringMixin present: " .. safeStr(_G.AutoScalingFontStringMixin ~= nil))
    push("  ScaleTextToFit present:             "
        .. safeStr(_G.AutoScalingFontStringMixin ~= nil
                   and type(_G.AutoScalingFontStringMixin.ScaleTextToFit) == "function"))
    push("  fs.ClearText present:               " .. safeStr(type(nameFS.ClearText) == "function"))
    push("  fs.SetSmoothScaling present:        " .. safeStr(type(nameFS.SetSmoothScaling) == "function"))
    push("  fs.CalculateScreenAreaFromCharacterSpan: "
        .. safeStr(type(nameFS.CalculateScreenAreaFromCharacterSpan) == "function"))
    push("  fs.GetUnboundedStringWidthForText:  "
        .. safeStr(type(nameFS.GetUnboundedStringWidthForText) == "function"))

    -- Diagnostic only, no render path uses it. isWithinText is a way to probe a
    -- SECRET string's length without reading it, which may matter later.
    if type(nameFS.SetAlphaGradient) == "function" then
        local ok, within = pcall(nameFS.SetAlphaGradient, nameFS, 1, 1)
        push("  SetAlphaGradient(1,1) -> isWithinText: " .. (ok and safeStr(within) or "<error>"))
        if nameFS.ClearAlphaGradient then pcall(nameFS.ClearAlphaGradient, nameFS) end
    else
        push("  fs.SetAlphaGradient:                <API not present>")
    end

    addon.DebugShowWindow("Name Auto-Fit + Gradient Feasibility", lines)
end

function addon.DebugNameTextSetIdentity(which)
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

function addon.DebugNameTextScan()
    local lines = {}
    local function push(s) lines[#lines + 1] = s end

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

-- Run-length encoded so a 129-entry sweep reads as one line.
local function formatSeq(seq, limit)
    local parts, i = {}, 0
    while i <= limit do
        local ch, j = seq[i], i
        while j + 1 <= limit and seq[j + 1] == ch do j = j + 1 end
        parts[#parts + 1] = (j > i) and string.format("%s[%d..%d]", tostring(ch), i, j)
                                     or string.format("%s[%d]", tostring(ch), i)
        i = j + 1
    end
    return table.concat(parts, "  ")
end

-- Continuation bytes are 0x80..0xBF; everything else starts a character.
local function utf8Count(s)
    local n = 0
    for i = 1, #s do
        local b = string.byte(s, i)
        if b < 0x80 or b >= 0xC0 then n = n + 1 end
    end
    return n
end

local function buildProbeReport()
    local out = {}
    local function push(s) out[#out + 1] = s end

    push("== SetAlphaGradient length-oracle probe ==")
    push("")

    if type(nameFS.SetAlphaGradient) ~= "function" then
        push("FontString:SetAlphaGradient is not present in this build.")
        push("The oracle does not exist; auto-fit on secret names is closed.")
        addon.DebugShowWindow("Length Oracle Probe", out)
        return
    end

    local free = ensureProbeFS()

    -- Everything is measured before anything is cleared.
    local freeScan = alphaScan(free, PROBE_LIMIT)
    local freeBest, freeCalls = alphaBisect(free, PROBE_LIMIT)
    local dispScan = alphaScan(nameFS, PROBE_LIMIT)
    local dispBest, dispCalls = alphaBisect(nameFS, PROBE_LIMIT)

    -- Does the second argument influence the answer, or is it purely a render knob?
    local lengthCtl = {}
    for _, L in ipairs({ 0, 1, 8, 1000 }) do
        local v, tag = alphaProbe(free, 1, L)
        lengthCtl[#lengthCtl + 1] = string.format("start=1 length=%-4d -> %s",
            L, (v == nil) and (tag or "?") or safeStr(v))
    end

    -- A gradient is render state, not a query. Put both subjects back.
    local canClear = type(nameFS.ClearAlphaGradient) == "function"
    if canClear then
        pcall(nameFS.ClearAlphaGradient, nameFS)
        pcall(free.ClearAlphaGradient, free)
    end

    local bytes, chars
    local readable = type(currentValue) == "string"
        and not (issecretvalue and issecretvalue(currentValue))
    if readable then
        bytes = #currentValue
        chars = utf8Count(currentValue)
    end

    ----------------------------------------------------------------------------
    -- Verdict
    ----------------------------------------------------------------------------
    local verdict
    if freeScan.firstSecret then
        verdict = "DEAD - isWithinText returned SECRET at start=" .. freeScan.firstSecret
            .. ". The oracle is annotated non-secret but does not behave that way."
    elseif freeScan.firstBad then
        verdict = "DEAD - probe failed at index " .. freeScan.firstBad
    elseif not freeScan.monotonic then
        verdict = "UNUSABLE - isWithinText is not monotonic in start. "
            .. "Bisection cannot recover a length from a non-monotonic predicate."
    elseif freeBest ~= (freeScan.lastTrue or -1) then
        verdict = string.format(
            "UNUSABLE - bisection says %d, exhaustive scan says %s. They must agree.",
            freeBest, safeStr(freeScan.lastTrue))
    elseif freeBest < 0 then
        verdict = "NO SIGNAL - isWithinText was false at every index, including 0. "
            .. "Either the FontString had not laid out, or the text is empty."
    elseif readable then
        -- The index is 0-based and inclusive, so the count is one more than the last
        -- true index. Checked against BOTH units: only an accented name separates
        -- them, which is what sample 7 exists for.
        local count = freeBest + 1
        local unit
        if bytes == chars and count == bytes then
            unit = "bytes and characters are equal for this name (pure ASCII) - "
                .. "re-run on sample 7 to tell them apart"
        elseif count == chars then
            unit = "counts CHARACTERS (UTF-8 aware) - accented names do not skew it"
        elseif count == bytes then
            unit = "counts BYTES - accented names will over-report"
        else
            unit = string.format("count %d matches NEITHER #text (%d) nor the UTF-8 count (%d)",
                count, bytes, chars)
        end
        verdict = string.format(
            "ORACLE RESPONDS on a readable name: last true index %d -> count %d, "
            .. "in %d bisection calls; %s", freeBest, count, freeCalls, unit)
        verdict = verdict .. "  --  now re-run while targeting a unit whose name IS secret."
    else
        verdict = string.format(
            "ORACLE HOLDS ON A SECRET NAME: %d characters, recovered in %d bisection calls "
            .. "without reading a byte.", freeBest + 1, freeCalls)
    end
    push("ORACLE VERDICT:  " .. verdict)
    push("")

    ----------------------------------------------------------------------------
    push("-- Subject --")
    push("  source:            " .. safeStr(lastSource))
    push("  name was secret:   " .. safeStr(currentIsSecret))
    push("  GetText():         " .. measure("GetText"))
    push("  #text (bytes):     " .. (bytes and tostring(bytes) or "unreadable"))
    push("  UTF-8 characters:  " .. (chars and tostring(chars) or "unreadable"))
    push("  probe limit:       " .. PROBE_LIMIT)
    push("  ClearAlphaGradient present: " .. safeStr(canClear)
        .. (canClear and "" or "   <- a gradient has been LEFT on both FontStrings"))
    push("")

    push("-- Probe A: free FontString (no width, wrap off, whole string on one line) --")
    push("  fs:IsAnchoringSecret():  " .. measureOn(free, "IsAnchoringSecret"))
    push("  fs:GetStringWidth():     " .. measureOn(free, "GetStringWidth"))
    push("  last true index:         " .. safeStr(freeScan.lastTrue))
    push("  first false index:       " .. safeStr(freeScan.firstFalse))
    push("  monotonic:               " .. safeStr(freeScan.monotonic))
    push("  first SECRET return:     " .. (freeScan.firstSecret and tostring(freeScan.firstSecret) or "none"))
    push("  first bad return:        " .. (freeScan.firstBad or "none"))
    push("  bisection:               last true " .. freeBest .. " => count "
        .. (freeBest + 1) .. ", in " .. freeCalls .. " calls"
        .. ((freeBest == (freeScan.lastTrue or -1)) and "   (agrees with scan)"
                                                     or "   *** DISAGREES WITH SCAN ***"))
    push("  sweep (" .. freeScan.calls .. " calls):")
    push("    " .. formatSeq(freeScan.seq, PROBE_LIMIT))
    push("")

    push("-- Probe B: display FontString (box-constrained, wrapped, may be ellipsized) --")
    push("  fs:IsAnchoringSecret():  " .. measure("IsAnchoringSecret"))
    push("  last true index:         " .. safeStr(dispScan.lastTrue))
    push("  first false index:       " .. safeStr(dispScan.firstFalse))
    push("  monotonic:               " .. safeStr(dispScan.monotonic))
    push("  first SECRET return:     " .. (dispScan.firstSecret and tostring(dispScan.firstSecret) or "none"))
    push("  first bad return:        " .. (dispScan.firstBad or "none"))
    push("  bisection:               last true " .. dispBest .. " => count "
        .. (dispBest + 1) .. ", in " .. dispCalls .. " calls")
    push("  sweep (" .. dispScan.calls .. " calls):")
    push("    " .. formatSeq(dispScan.seq, PROBE_LIMIT))
    push("")

    push("-- What the second argument does --")
    for _, s in ipairs(lengthCtl) do push("  " .. s) end
    push("")

    push("-- Interpretation --")
    local layoutNote
    if dispBest == freeBest then
        layoutNote = string.format(
            "identical (%d) -> nothing was dropped: the name fits on one line at this "
            .. "size and no break character was consumed", freeBest + 1)
    elseif dispBest < freeBest then
        -- Measured: a wrap CONSUMES the space it breaks on, so a clean
        -- two-line layout already reads one short. The gap is dropped characters of
        -- any kind -- breaks plus ellipsis -- not truncation alone.
        layoutNote = string.format(
            "display %d < free %d, %d character(s) dropped -> counts RENDERED "
            .. "characters. Each wrap eats its space, so expect (lines - 1) of the gap "
            .. "to be breaks; anything beyond that is ellipsis.",
            dispBest + 1, freeBest + 1, freeBest - dispBest)
    else
        layoutNote = string.format(
            "display %d > free %d -> unexplained; both hold the same value, so this "
            .. "should not happen", dispBest + 1, freeBest + 1)
    end
    push("  layout sensitivity: " .. layoutNote)
    push("  index base:         probe(0) = " .. safeStr(freeScan.seq[0])
        .. "   probe(1) = " .. safeStr(freeScan.seq[1])
        .. "   (0-based inclusive: count = lastTrue + 1)")
    if readable then
        push(string.format("  units:              oracle count=%d  bytes=%d  utf8=%d",
            freeBest + 1, bytes, chars))
    else
        push("  units:              cannot be checked - the name is secret, which is the point. "
            .. "Calibrate on a readable name first.")
    end
    push("")

    push("-- Fit state at probe time --")
    local r = lastResult or {}
    push("  measurable:  " .. safeStr(r.measurable))
    push("  fallback:    " .. safeStr(r.fallback))
    push("  applied size:" .. safeStr(r.size))
    push("  max lines:   " .. safeStr(r.maxLines))
    push("  reason:      " .. safeStr(r.reason))

    addon.DebugShowWindow("Length Oracle Probe", out)
end

function addon.DebugNameTextLengthProbe()
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

local function fmtCount(v, tag)
    if v ~= nil then return tostring(v) end
    return "<" .. (tag or "?") .. ">"
end

-- Largest ladder size whose count still equals the ceiling -- i.e. exactly what a
-- bisecting fitter would land on, computed from one column of the table. Running it
-- over each column separately is the point: if the same-frame column picks a different
-- size than the settled one, that difference IS the cost of trusting same-frame reads.
local function pickFromColumn(rows, key, ceiling)
    local best
    for _, row in ipairs(rows) do
        if row[key] ~= nil and row[key] == ceiling then best = row.size end
    end
    return best
end

local function buildFitProbeReport(rows, freeCount, freeTag, calls, frames)
    local out = {}
    local function push(s) out[#out + 1] = s end

    ----------------------------------------------------------------------------
    -- Analysis
    ----------------------------------------------------------------------------
    local anyTag, varied, monotonic = nil, false, true
    local deferAgree, deferChecked = 0, 0
    local sameAgree, sameChecked = 0, 0
    local staleByOne, staleChecked = 0, 0
    local sameSaturated = 0
    local prevTruth

    -- Saturation is an expected answer, not a malfunction -- it is the finding. Only a
    -- genuinely broken return (SECRET, error, non-boolean) invalidates the run.
    local function realTag(t)
        if t and t ~= "saturated" then return t end
        return nil
    end

    for i, row in ipairs(rows) do
        anyTag = anyTag or realTag(row.sameTag) or realTag(row.d1Tag) or realTag(row.d2Tag)
        if row.sameTag == "saturated" then sameSaturated = sameSaturated + 1 end

        -- d2 is the settled value; d1 is only trustworthy if it matches.
        if row.d1 ~= nil and row.d2 ~= nil then
            deferChecked = deferChecked + 1
            if row.d1 == row.d2 then deferAgree = deferAgree + 1 end
        end

        if row.same ~= nil and row.d2 ~= nil then
            sameChecked = sameChecked + 1
            if row.same == row.d2 then
                sameAgree = sameAgree + 1
            elseif i > 1 and prevTruth ~= nil then
                -- The signature of a one-frame lag: the "new" reading is the previous
                -- size's answer. Distinguishing that from generic disagreement is the
                -- difference between "add a frame" and "the oracle is unreliable".
                staleChecked = staleChecked + 1
                if row.same == prevTruth then staleByOne = staleByOne + 1 end
            end
        end

        if row.d2 ~= nil then
            if prevTruth ~= nil then
                if row.d2 ~= prevTruth then varied = true end
                if row.d2 > prevTruth then monotonic = false end
            end
            prevTruth = row.d2
        end
    end

    local ceiling = rows[1] and rows[1].d2
    local pickTruth = ceiling and pickFromColumn(rows, "d2", ceiling)
    local pickSame  = ceiling and pickFromColumn(rows, "same", ceiling)
    local pickD1    = ceiling and pickFromColumn(rows, "d1", ceiling)

    local sameFrameOK = (sameChecked > 0) and (sameAgree == sameChecked)
    local oneFrameOK  = (deferChecked > 0) and (deferAgree == deferChecked)

    -- What the shipping fitter would cost: a bisection over the size range, each
    -- candidate itself a bisection over the character index.
    local function log2(n) return math.ceil(math.log(n) / math.log(2)) end
    local sizeCandidates    = math.max(1, log2(math.abs(cfg.maxSize - cfg.minSize) + 1))
    local callsPerCandidate = log2(PROBE_LIMIT + 1)

    ----------------------------------------------------------------------------
    -- Verdict
    ----------------------------------------------------------------------------
    local verdict
    if anyTag then
        verdict = "BROKEN - the oracle stopped returning a plain boolean (" .. anyTag
            .. "). Every count below is suspect; re-run 'lengthprobe' first."
    elseif not oneFrameOK then
        verdict = string.format(
            "UNSETTLED - the +1 frame and +2 frame columns disagree at %d of %d sizes. "
            .. "Even a deferred read is not stable, so there is no trustworthy column "
            .. "here and the fitter needs a settle loop, not a fixed delay.",
            deferChecked - deferAgree, deferChecked)
    elseif not varied then
        verdict = string.format(
            "INCONCLUSIVE - D never changed across the whole ladder (always %s). The "
            .. "box never forced the engine to drop a character, so nothing was under "
            .. "test. Use a longer name (sample 4 or 5) or narrow the box "
            .. "('/scoot debug nametext size 90 40') and re-run.",
            safeStr(ceiling))
    elseif not monotonic then
        -- Measured cause: the truncation ellipsis is itself three rendered
        -- characters. The instant the engine starts ellipsizing, D jumps by +3 and then
        -- resumes falling, so the curve has a step back up in it.
        verdict = "NON-MONOTONIC - a larger font reported MORE rendered characters. The "
            .. "known cause is the ellipsis: '...' is three rendered characters, so D "
            .. "gains +3 the moment truncation starts. 'Largest size that still keeps "
            .. "the full count' is therefore UNSOUND -- an ellipsized layout that "
            .. "dropped exactly 3 characters reads as a perfect fit. Size the text from "
            .. "a scratch FontString with maxLines unbounded, where nothing is ever "
            .. "ellipsized, rather than from the display one."
    elseif sameFrameOK then
        verdict = string.format(
            "SAME-FRAME READS ARE TRUSTWORTHY - all %d sizes agree with the settled "
            .. "value. A blind shrink-to-fit is one synchronous function: ~%d size "
            .. "candidates x ~%d oracle calls = ~%d calls, ZERO extra frames.",
            sameChecked, sizeCandidates, callsPerCandidate,
            sizeCandidates * callsPerCandidate)
    elseif sameSaturated > 0 then
        verdict = string.format(
            "ONE FRAME PER CANDIDATE - the same-frame reads are not stale, they are "
            .. "SATURATED: %d of %d answered true at EVERY index, which is what a dirty "
            .. "layout reports. They carry no information at all, so there is nothing to "
            .. "trust or distrust. The +1f and +2f columns agree at all %d sizes, so one "
            .. "frame settles it cleanly: a ~%d-step size search costs ~%d frames per "
            .. "target change.",
            sameSaturated, #rows, deferChecked, sizeCandidates, sizeCandidates)
    else
        local stale = (staleChecked > 0 and staleByOne == staleChecked)
        verdict = string.format(
            "SAME-FRAME READS ARE STALE - they disagree with the settled value at %d of "
            .. "%d sizes.%s Each candidate costs a frame, so a ~%d-step bisection means "
            .. "~%d frames per target change and the name steps through sizes on screen.",
            sameChecked - sameAgree, sameChecked,
            stale and " Every disagreement equals the PREVIOUS size's answer, so the read"
                .. " is exactly one frame behind -- not noisy, just late." or "",
            sizeCandidates, sizeCandidates)
    end

    push("== Oracle fit probe: does D(size) settle in the same frame? ==")
    push("")
    push("VERDICT:  " .. verdict)
    push("")

    ----------------------------------------------------------------------------
    push("-- Subject --")
    push("  source:            " .. safeStr(lastSource))
    push("  name was secret:   " .. safeStr(currentIsSecret))
    push("  GetText():         " .. measure("GetText"))
    push("  free-string count: " .. fmtCount(freeCount, freeTag)
        .. "   (unconstrained FontString = the true character count)")
    push(string.format("  box:               %d x %d, maxLines %d, %s %s",
        cfg.width, cfg.height, cfg.maxLines, cfg.face, cfg.style))
    push(string.format("  ladder:            %d sizes from %d to %d",
        #rows, cfg.minSize, cfg.maxSize))
    push(string.format("  cost:              %d oracle calls over %d frames", calls, frames))
    push("")

    ----------------------------------------------------------------------------
    push("-- D(size): characters that survived layout, at each font size --")
    push("   size    same-frame    +1 frame    +2 frames   same == +2f?")
    for _, row in ipairs(rows) do
        local mark
        if row.same == nil or row.d2 == nil then
            mark = "-"
        elseif row.same == row.d2 then
            mark = "yes"
        else
            mark = "NO"
        end
        push(string.format("   %4d    %10s    %8s    %9s   %s",
            row.size,
            fmtCount(row.same, row.sameTag),
            fmtCount(row.d1, row.d1Tag),
            fmtCount(row.d2, row.d2Tag),
            mark))
    end
    push("")

    ----------------------------------------------------------------------------
    push("-- Settling --")
    push(string.format("  +1f vs +2f:         %d of %d agree%s",
        deferAgree, deferChecked,
        oneFrameOK and "   (one frame is enough to settle)" or "   *** NOT SETTLED ***"))
    push(string.format("  same-frame vs +2f:  %d of %d agree", sameAgree, sameChecked))
    if staleChecked > 0 then
        push(string.format("  stale-by-one:       %d of %d disagreements equal the PREVIOUS "
            .. "size's answer", staleByOne, staleChecked))
    end
    push("  note: row 1's same-frame read follows whatever size the fit left behind, so")
    push("        it is excluded from the stale-by-one signature.")
    push("")

    ----------------------------------------------------------------------------
    push("-- What a bisecting fitter would pick --")
    push("  ceiling (D at size " .. (rows[1] and rows[1].size or "?") .. "): "
        .. safeStr(ceiling))
    push("  largest size holding the ceiling:")
    push("     using +2 frame reads (truth):  " .. safeStr(pickTruth))
    push("     using +1 frame reads:          " .. safeStr(pickD1)
        .. ((pickD1 == pickTruth) and "   (matches)" or "   *** DIFFERS ***"))
    push("     using same-frame reads:        " .. safeStr(pickSame)
        .. ((pickSame == pickTruth) and "   (matches)" or "   *** DIFFERS ***"))
    if freeCount and ceiling then
        if ceiling == freeCount then
            push("  ceiling == free count -> nothing is dropped even at the smallest size,")
            push("     so the ceiling really is the whole name.")
        else
            push(string.format("  ceiling %d < free count %d -> even the smallest size loses %d "
                .. "character(s).", ceiling, freeCount, freeCount - ceiling))
            push("     The fit can only ever be 'least bad'; widen the box or raise maxLines")
            push("     if that matters.")
        end
    end
    push("")

    ----------------------------------------------------------------------------
    push("-- Fit state before the probe ran --")
    local r = lastResult or {}
    push("  measurable:   " .. safeStr(r.measurable))
    push("  fallback:     " .. safeStr(r.fallback))
    push("  applied size: " .. safeStr(r.size))
    push("  reason:       " .. safeStr(r.reason))

    addon.DebugShowWindow("Oracle Fit Probe", out)
end

function addon.DebugNameTextFitProbe(steps)
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

local function buildAutoFitReport(st)
    local out = {}
    local function push(s) out[#out + 1] = s end

    push("== Auto-fit: every candidate size, and what rejected it ==")
    push("")
    push("-- Subject --")
    push("  source:              " .. safeStr(lastSource))
    push("  name was secret:     " .. safeStr(currentIsSecret))
    -- What was MEASURED, which is the case-transformed string, not what UnitName said.
    -- Printing the raw name here would explain a size that was never derived from it.
    push("  measured text:       " .. safeStr(currentValue))
    if caseMethod == "string.upper" then
        push("  (as handed over:     " .. safeStr(currentRaw) .. ")")
    end
    push("  box:                 " .. string.format("%d x %d, line cap %d",
        cfg.width, cfg.height, cfg.maxLines))
    push("  font:                " .. safeStr(effectiveFaceKey()) .. " " .. safeStr(cfg.style))
    push("  case:                " .. safeStr(cfg.case) .. "  via " .. safeStr(caseMethod)
        .. (caseError and ("  -- " .. safeStr(caseError)) or ""))
    push("  size range:          " .. string.format("%s..%s step %s",
        safeStr(st.lo), safeStr(st.hi), safeStr(st.step)))
    local chosenRow
    for _, row in ipairs(st.rows or {}) do
        if row.size == st.size then chosenRow = row end
    end
    push("  blind-spot margin:   " .. safeStr(cfg.margin)
        .. (chosenRow and chosenRow.margin
            and string.format("  -> %dpx at the chosen size, so the fit had to hold in "
                .. "%dpx not %d", chosenRow.margin, chosenRow.narrowWidth, cfg.width)
            or "")
        .. ((cfg.margin == "off")
            and "   *** OFF: a name clipped by exactly three characters will read as a "
                .. "perfect fit ***" or ""))
    push("")

    push("-- What the oracle recovered, without reading a byte --")
    push("  F  (characters):     " .. (st.F and tostring(st.F) or ("<" .. tostring(st.FTag) .. ">")))
    push("  spaces @ width " .. SQUEEZE_A .. ":   " .. (st.spacesA and tostring(st.spacesA) or "<failed>"))
    push("  spaces @ width " .. SQUEEZE_B .. ":   " .. (st.spacesB and tostring(st.spacesB) or "<failed>"))
    if st.spacesA and st.spacesB then
        push("  agree:               " .. (st.spacesA == st.spacesB
            and "yes -- the squeeze is saturated, so the space count is trustworthy"
            or  "NO -- the wider ruler still fits two words on a line; count is a FLOOR"))
    end
    if st.F and st.spaces then
        push("  => words:            " .. tostring(st.spaces + 1))
        push("  => valid D range:    [" .. tostring(st.F - st.spaces) .. ", " .. tostring(st.F) .. "]")
    end
    push("")

    if not st.rows or #st.rows == 0 then
        push("No sizes were measured; nothing to conclude. " .. safeStr(st.reason))
        addon.DebugShowWindow("Auto Fit", out)
        return
    end

    push("-- The scan --")
    push("  Phase 1, on the count alone:")
    push("    1. D must not RISE above the running minimum  (the '...' is 3 characters)")
    push("    2. D must not fall below F - spaces           (characters were destroyed)")
    push("  Phase 2, by re-rendering under a forced cap:")
    push("    3. Lpred = F - D + 1 must be within the budget")
    push("    4. capping at exactly Lpred must not change the count -- if it does, the")
    push("       engine broke somewhere that eats no character (mid-word, or a hyphen)")
    push("    5. it must still hold in a box narrowed by one ellipsis width -- the")
    push("       blind spot, where a full render and one clipped by three look the same")
    push("")
    push("  Phase 1 stops at its first failure; phase 2 does not. A rejection in phase 2")
    push("  says nothing about the size above it -- the layout changes shape as the text")
    push("  grows -- so read this table for its LARGEST pass, not its first failure.")
    push("")
    push("  size    D  Lpred  budget  cap@L  cap@bud  narrow   verdict")
    for _, row in ipairs(st.rows) do
        local verdict
        if row.skipped then
            verdict = "-- not reached"
        elseif row.clean then
            verdict = "fits, breaks only at spaces"
        elseif row.loose then
            -- Loose but not clean: row.why is the reason it missed CLEAN, which is the
            -- interesting half. Printing it as a flat FAIL hides that it still renders.
            verdict = "loose only -- " .. (row.why or "breaks mid-word or at a hyphen")
        elseif row.why then
            verdict = "FAIL: " .. row.why
        else
            verdict = "does not render in full"
        end
        if st.size and row.size == st.size then
            verdict = verdict .. "   <== CHOSEN"
        end
        push(string.format("  %4s %4s %6s %7s %6s %8s %7s   %s",
            tostring(row.size),
            row.d and tostring(row.d) or "?",
            row.lpred and tostring(row.lpred) or "-",
            row.budget and tostring(row.budget) or "-",
            row.dAtLpred and tostring(row.dAtLpred) or "-",
            row.dAtBudget and tostring(row.dAtBudget) or "-",
            row.dNarrow and tostring(row.dNarrow) or "-",
            verdict))
    end
    push("")

    push("-- Result --")
    if st.size then
        push("  chosen size:         " .. tostring(st.size)
            .. "  (" .. tostring(st.lines) .. " line(s), " .. safeStr(st.tier) .. " tier)")
        if st.tier == "loose" then
            push("     No size in range breaks this name only at spaces, so it fell back to")
            push("     the largest that still renders in full. Expect a hyphen or mid-word")
            push("     break on screen -- that is the engine's choice, not a bug.")
        end
        push("  largest clean size:  " .. (st.clean and tostring(st.clean) or "none in range"))
        push("  largest loose size:  " .. (st.loose and tostring(st.loose) or "none in range"))
        push("  first rejection:     " .. (st.cleanStop and tostring(st.cleanStop) or "none")
            .. "  (informational -- phase 2 keeps scanning past it)")
        push("  phase 1 stopped at:  " .. (st.phase1Stop and tostring(st.phase1Stop)
            or "never -- every size in range was measured"))
        push("  APPLIED to the box. Look at it -- that is the whole test.")
        push("    * whole words, no '...', nothing sawn in half -> the algorithm is right")
        push("    * one point larger would have spilled          -> it is also tight")
    else
        push("  NO SIZE FITS. " .. safeStr(st.reason))
        push("  The display is at " .. safeStr(st.lo) .. "; the engine's own ellipsis takes over.")
    end
    push("")
    push("  oracle calls:        " .. tostring(st.calls))
    push("  frames spent:        " .. tostring(st.frames)
        .. "  (every size is its own ruler, so this does not grow with the range)")
    push("")

    push("-- Known limits of this table --")
    push("  * The space count is a floor if the two squeeze widths disagree above.")
    push("  * 'Lpred' is what the line count WOULD be if every break ate a character.")
    push("    Check 4 is precisely the test of whether that assumption held, so a row")
    push("    that passes has a correct Lpred and a row that fails does not.")
    push("  * Check 5 over-rejects a narrow band of multi-word sizes. Taking width away")
    push("    can push a word onto a line that Lpred does not allow for, and under that")
    push("    cap the dropped line reads as a truncation. It costs a point or two at the")
    push("    top of each wrap band -- and it is why phase 2 scans the whole range")
    push("    instead of stopping at the first rejection.")

    addon.DebugShowWindow("Auto Fit", out)
end

-- Renders exactly as normal, then prints the derivation. No separate measurement pass:
-- a report that measured things its own way would be describing a different fit.
function addon.DebugNameTextAutoFit()
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

function addon.DebugNameTextReport()
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
