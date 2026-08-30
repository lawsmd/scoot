-- blindfit.lua - Shrink-to-fit sizing for text nobody can read (secret-safe)
--------------------------------------------------------------------------------
-- Ported verbatim from the certified fit in core/debug/nametext.lua (the harness
-- stays untouched as the reference implementation; disagreement between the two
-- on the same inputs is a port defect, not a judgment call). The algorithm was
-- settled over multiple in-game certification rounds -- treat every rule below
-- as measured, not designed.
--
-- addon.RunBlindFit(value, opts, onDone)
--   value : the string to size (plain or secret). Any transform (case, realm
--           split) must happen BEFORE the fit -- the fit sizes exactly the
--           string it is given, and the caller must paint that same string.
--   opts  : {
--     poolKey  = string  (REQUIRED. One ruler pool per caller; fits on
--                         different poolKeys are fully independent.)
--     face     = string  (font registry KEY; resolved once at entry)
--     style    = string  (default "")
--     width    = number  (REQUIRED, > 0 -- the fit box width in px)
--     height   = number  (REQUIRED, > 0 -- only feeds the line budget)
--     maxLines = number  (REQUIRED, >= 1)
--     minSize  = number  (default 9)
--     maxSize  = number  (default 52)
--     margin   = "auto" | number | "off"  (default "auto")
--   }
--   onDone(st): fires exactly once per NON-superseded pass, two deferred frames
--   after the call. st carries the whole derivation (F, spaces, rows, size,
--   lines, budget, tier, reason, ...), not just the answer -- a number with no
--   working shown is what made the early rounds of this impossible to trust.
--
-- SUPERSESSION. A new RunBlindFit on the SAME poolKey abandons any in-flight
-- pass on that pool: the old pass's callbacks bail at a generation check and
-- its onDone is NEVER called. Launching a new fit therefore cancels interest
-- in the old one. That covers replacement -- it does NOT cover disappearance:
-- if the caller's subject goes away and no new fit is launched, the in-flight
-- pass still lands. Callers must keep their own sequence counter, bumped on
-- EVERY subject change, and discard stale results in onDone.
--
-- Opts are snapshotted at entry (the pass spans three frames; a caller editing
-- its config mid-pass must not change the question being measured), and the
-- face is resolved to a file path once at entry -- the one deliberate
-- divergence from the reference, which re-resolves per arm. Identical behavior
-- while the font registry is stable, and it guarantees all three frames of a
-- pass measure one consistent face.
--
-- KNOWN HAZARD (inherited, not engineered around): SetFont on a font FILE that
-- is not yet resident is a silent no-op, so on a virgin session a ruler could
-- measure in its creation font while the display renders the fallback. All
-- shipped faces load at startup; verifyAppliedFace-style checks are the
-- caller's concern.
--------------------------------------------------------------------------------

local addonName, addon = ...

--------------------------------------------------------------------------------
-- Safe formatting
--------------------------------------------------------------------------------

local function safeStr(v)
    if v == nil then return "nil" end
    if issecretvalue and issecretvalue(v) then return "<SECRET>" end
    local ok, s = pcall(tostring, v)
    return ok and s or "<error>"
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
-- characters. margin = "off" turns it off to see the difference.
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

-- Rulers are created once and never destroyed, but size ranges are caller-editable.
-- Coarsen rather than allocate hundreds of regions.
local MAX_CANDIDATES = 64

-- One pool per poolKey: { holder, rulers, gen }. Rulers of different pools never
-- alias, so fits on different keys are fully independent. gen is the supersession
-- counter -- bumped per pass, checked in both deferred callbacks.
local pools = {}

local function ensurePool(poolKey)
    local pool = pools[poolKey]
    if not pool then
        pool = { rulers = {}, gen = 0 }
        pools[poolKey] = pool
    end
    return pool
end

-- One holder per pool, N FontStrings stacked on the same point. They overlap, which
-- does not matter: a FontString's layout is its own, and the holder is transparent.
-- Shown, not hidden -- a hidden region may skip layout, and then the oracle answers
-- about nothing.
local function ensureRuler(pool, i)
    if not pool.holder then
        pool.holder = CreateFrame("Frame", nil, UIParent)
        pool.holder:SetSize(1, 1)
        pool.holder:SetPoint("CENTER", UIParent, "CENTER", 0, -360)
        pool.holder:SetAlpha(0)
    end

    local fs = pool.rulers[i]
    if fs then return fs end

    fs = pool.holder:CreateFontString(nil, "OVERLAY")
    -- One anchor only. Width is set per-probe; height stays free so the line cap is the
    -- only thing that can ever limit the line count.
    fs:SetPoint("TOP", pool.holder, "TOP", 0, 0)
    fs:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
    fs:SetJustifyH("CENTER")
    pool.rulers[i] = fs
    return fs
end

-- Every field is written every time. A ruler that carried one setting over from a
-- previous probe measures a different question, and nothing about the number that comes
-- back would look wrong.
local function armRuler(fs, value, size, width, wrap, nonSpaceWrap, maxLines, facePath, style)
    -- MetricStyle: a DEEPSHADOW style must not build companion copies on rulers.
    addon.ApplyFontStyle(fs, facePath, size, addon.FontStyles.MetricStyle(style))
    if fs.SetTextScale then pcall(fs.SetTextScale, fs, 1) end
    if fs.SetWidth then pcall(fs.SetWidth, fs, width) end
    if fs.SetWordWrap then pcall(fs.SetWordWrap, fs, wrap) end
    if fs.SetNonSpaceWrap then pcall(fs.SetNonSpaceWrap, fs, nonSpaceWrap) end
    if fs.SetMaxLines then pcall(fs.SetMaxLines, fs, maxLines) end
    if fs.ClearText then pcall(fs.ClearText, fs) end
    pcall(fs.SetText, fs, value)
end

-- The pixel width of "..." at a given size. That is a Scoot-authored literal, so no
-- secret is involved and MeasureTextWidth can do its ordinary SetText/GetStringWidth on
-- it -- the one part of a truncated render that stays readable, and by luck the
-- exact size of the thing that cannot be seen. Falls back to a size-proportional estimate,
-- because a nil here would silently switch off the check that catches the blind spot.
local function marginFor(size, margin, facePath, style)
    if margin == "off" then return 0 end

    local fixed = tonumber(margin)
    if fixed then return math.max(0, math.floor(fixed)) end

    local w = addon.MeasureTextWidth and addon.MeasureTextWidth(
        "...", facePath, size, style)
    if type(w) == "number" and w > 0 then return math.floor(w + 0.5) end
    return math.floor(size + 0.5)
end

-- onDone(st). st carries the whole derivation, not just the answer, because reports
-- render it verbatim and a number with no working shown is exactly what made the
-- earlier rounds of this so hard to trust.
function addon.RunBlindFit(value, opts, onDone)
    -- Validate loudly, fail asynchronously through the caller's fallback branch. A nil
    -- width would reach pcall(fs.SetWidth, fs, nil), fail silently inside the pcall,
    -- leave the ruler at its previous width, and produce a PLAUSIBLE WRONG fit -- the
    -- worst failure shape there is.
    local badOpt
    if type(opts) ~= "table" then
        badOpt = "opts not a table"
    elseif type(opts.poolKey) ~= "string" or opts.poolKey == "" then
        badOpt = "poolKey missing"
    elseif type(opts.width) ~= "number" or opts.width <= 0 then
        badOpt = "width missing"
    elseif type(opts.height) ~= "number" or opts.height <= 0 then
        badOpt = "height missing"
    elseif type(opts.maxLines) ~= "number" or opts.maxLines < 1 then
        badOpt = "maxLines missing"
    end
    if badOpt then
        C_Timer.After(0, function()
            onDone({ reason = "bad opts: " .. badOpt })
        end)
        return
    end

    -- Snapshot: the pass spans three frames; a caller editing its config mid-pass
    -- must not change the question being measured. Face resolved once, here.
    local facePath = addon.ResolveFontFace(opts.face)
    local style    = opts.style or ""
    local width    = opts.width
    local height   = opts.height
    local maxLines = math.max(1, math.floor(opts.maxLines))
    local margin   = (opts.margin == nil) and "auto" or opts.margin

    local pool = ensurePool(opts.poolKey)
    pool.gen = pool.gen + 1
    local gen = pool.gen

    local st = { calls = 0, frames = 0, rows = {}, sizes = {} }

    local lo = math.max(1, math.floor(tonumber(opts.minSize) or 9))
    local hi = math.max(1, math.floor(tonumber(opts.maxSize) or 52))
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
    armRuler(ensureRuler(pool, 1), value, hi, 0, false, false, 1, facePath, style)
    armRuler(ensureRuler(pool, 2), value, lo, SQUEEZE_A, true, true, UNCAPPED_LINES, facePath, style)
    armRuler(ensureRuler(pool, 3), value, lo, SQUEEZE_B, true, true, UNCAPPED_LINES, facePath, style)
    for i = 1, n do
        armRuler(ensureRuler(pool, 3 + i), value, st.sizes[i], width, true, false, UNCAPPED_LINES, facePath, style)
    end

    local function read(i)
        local count, calls, tag = measureCount(ensureRuler(pool, i))
        st.calls = st.calls + (calls or 0)
        return count, tag
    end

    C_Timer.After(0, function()
        -- Superseded: a newer pass owns this pool's rulers now. Abandon without
        -- onDone -- the caller launched a new fit and lost interest in this one.
        if pool.gen ~= gen then return end
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

            local ruler = ensureRuler(pool, 3 + i)
            row.d = read(3 + i)

            local lh = plainNumber(ruler, "GetLineHeight")
            row.lineHeight  = lh
            row.heightLines = (lh and lh > 0) and math.floor(height / lh) or nil
            row.budget = math.max(1, math.min(maxLines, row.heightLines or maxLines))

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
                -- three-character literal of Scoot's own, so measuring it involves no secret
                -- at all -- it is the one piece of the truncated render that stays
                -- readable, and it happens to be the exact size of the blind spot.
                row.margin = marginFor(row.size, margin, facePath, style)
                row.narrowWidth = math.max(8, width - row.margin)

                local base = cappedBase + (i - 1) * 3
                armRuler(ensureRuler(pool, base + 1), value, row.size,
                    width, true, false, row.lpred, facePath, style)
                if row.budget ~= row.lpred then
                    armRuler(ensureRuler(pool, base + 2), value, row.size,
                        width, true, false, row.budget, facePath, style)
                end
                if row.margin > 0 then
                    armRuler(ensureRuler(pool, base + 3), value, row.size,
                        row.narrowWidth, true, false, row.lpred, facePath, style)
                end
                live[#live + 1] = i
            end

            if row.why and not st.phase1Stop then st.phase1Stop = row.size end
        end

        C_Timer.After(0, function()
            if pool.gen ~= gen then return end
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
                    lo, hi, width, height)
            end
            st.stopped = st.cleanStop or st.phase1Stop

            onDone(st)
        end)
    end)
end
