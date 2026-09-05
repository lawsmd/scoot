-- nametextprobe.lua - case probe and unit secrecy scan for /scoot debug nametext
local addonName, addon = ...

addon.DebugNameText = addon.DebugNameText or {}
local NT = addon.DebugNameText

local safeStr = NT._SafeStr

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
        local rs = NT._State()
        local lastSource, currentIsSecret, currentRaw = rs.lastSource, rs.currentIsSecret, rs.currentRaw
        local plainNumber = NT._PlainNumber
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
NT._CaseProbe = DebugNameTextCaseProbe

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
NT._Scan = DebugNameTextScan
