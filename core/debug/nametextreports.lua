-- nametextreports.lua - report builders for /scoot debug nametext
local addonName, addon = ...

addon.DebugNameText = addon.DebugNameText or {}
local NT = addon.DebugNameText

local function safeStr(v)
    if v == nil then return "nil" end
    if issecretvalue and issecretvalue(v) then return "<SECRET>" end
    local ok, s = pcall(tostring, v)
    return ok and s or "<error>"
end
NT._SafeStr = safeStr

local function buildReport()
    local rs = NT._State()
    local lastResult, lastColors, lastFit, lastSource = rs.lastResult, rs.lastColors, rs.lastFit, rs.lastSource
    local lastLines, lastDiscovery = rs.lastLines, rs.lastDiscovery
    local lastGradientMode, lastGradientNote = rs.lastGradientMode, rs.lastGradientNote
    local lastRamped, lastSliceSize, lastSliceScale = rs.lastRamped, rs.lastSliceSize, rs.lastSliceScale
    local lastSliceMaxLines, lastSliceFallback = rs.lastSliceMaxLines, rs.lastSliceFallback
    local currentIsSecret, caseMethod, caseError, caseOutSecret = rs.currentIsSecret, rs.caseMethod, rs.caseError, rs.caseOutSecret
    local plainApplied, nameFS, frame = rs.plainApplied, rs.nameFS, rs.frame
    local cfg, slicePool = NT._cfg, NT._slicePool
    local SQUEEZE_A, SQUEEZE_B = NT._SQUEEZE_A, NT._SQUEEZE_B
    local measure, measureOn, hex = NT._Measure, NT._MeasureOn, NT._Hex
    local effectiveFaceKey, targetIsPlayer = NT._EffectiveFaceKey, NT._TargetIsPlayer
    local lines, push = addon.DebugLines()

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
    local s1 = slicePool.items[1]
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
        push("  slices built:                 " .. slicePool:Count())
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
NT._BuildReport = buildReport

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

-- Formats the length-oracle probe: it runs the scans itself, so it is a measurement
-- pass as much as a report. The probe rationale and the scan and bisect primitives
-- live with the oracle helpers in nametext.lua.
local function buildProbeReport()
    local rs = NT._State()
    local lastSource, lastResult = rs.lastSource, rs.lastResult
    local currentIsSecret, currentValue, nameFS = rs.currentIsSecret, rs.currentValue, rs.nameFS
    local PROBE_LIMIT = NT._PROBE_LIMIT
    local ensureProbeFS, alphaProbe = NT._EnsureProbeFS, NT._AlphaProbe
    local alphaScan, alphaBisect = NT._AlphaScan, NT._AlphaBisect
    local measure, measureOn = NT._Measure, NT._MeasureOn
    local out, push = addon.DebugLines()

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
NT._BuildProbeReport = buildProbeReport

-- Renders the settling verdict: whether D(size) read in the same frame agrees with
-- the one- and two-frame columns, and what a bisecting fitter would pick from each.
-- The driver and the settling rationale live with the fitprobe machinery in
-- nametext.lua.
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
    local rs = NT._State()
    local lastSource, lastResult, currentIsSecret = rs.lastSource, rs.lastResult, rs.currentIsSecret
    local cfg, PROBE_LIMIT, measure = NT._cfg, NT._PROBE_LIMIT, NT._Measure
    local out, push = addon.DebugLines()

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
NT._BuildFitProbeReport = buildFitProbeReport

local function buildAutoFitReport(st)
    local rs = NT._State()
    local lastSource, currentIsSecret = rs.lastSource, rs.currentIsSecret
    local currentValue, currentRaw = rs.currentValue, rs.currentRaw
    local caseMethod, caseError = rs.caseMethod, rs.caseError
    local cfg, effectiveFaceKey = NT._cfg, NT._EffectiveFaceKey
    local SQUEEZE_A, SQUEEZE_B = NT._SQUEEZE_A, NT._SQUEEZE_B
    local out, push = addon.DebugLines()

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
NT._BuildAutoFitReport = buildAutoFitReport
