-- debug/castz.lua - /scoot debug castz
--
-- Phase 0 validation probe for Cast Bar Z. Answers, against a live cast, the
-- questions the Cast Bar Z architecture rests on:
--
--   1. Does UnitCastingDuration -> StatusBar:SetTimerDuration animate a
--      Scoot-owned StatusBar from addon (tainted) context?
--   2. Does SetText(secretName) render on a Scoot-owned FontString, and can
--      addon.MeasureTextWidth still measure it via the UIParent ruler?
--   3. Is notInterruptible secret on a non-pet unit, and does
--      C_CurveUtil.EvaluateColorFromBoolean digest it?
--   4. Does UnitEmpoweredStagePercentages return usable (non-secret) numbers?
--   5. Do UNIT_SPELLCAST_* events fire for the "pet" unit token?
--
-- Every answer either confirms the design or selects a documented fallback.
-- Nothing here is shipped code; this file exists to de-risk phases 1-5.
--
-- Run 1 (player + a friendly raid member) settled 2, 3 and 4:
--   * The cast restriction covers friendly players too. name, displayName,
--     textureID, notInterruptible AND castingSpellID were all secret.
--   * SetText(secret) renders, but the FontString then measures SECRET -- the
--     UIParent ruler does not escape it, because anchoring was never the
--     mechanism (SetText adds Enum.SecretAspect.Text to the FontString itself).
--   * EvaluateColorFromBoolean digests a secret bool. Both variants pass.
--   * isEmpowered / numEmpowerStages really are plain on a restricted unit.
-- Question 1 was NOT answered: the rig was hidden, so nothing was ever laid out
-- and every sample read back the bar's static full width. Fixed below.

local addonName, addon = ...

--------------------------------------------------------------------------------
-- Test rig (Scoot-owned, VISIBLE, UIParent-anchored)
--------------------------------------------------------------------------------
--
-- Anchored only to UIParent, so the rig's own anchor chain can never be secret.
-- That isolates "is the DATA secret" from "is the FRAME anchored to something
-- secret".
--
-- The rig is SHOWN while probing. A hidden frame is never laid out, so its fill
-- texture rect never updates -- that defect is why the first run reported a
-- frozen 179.99990844727 on every sample, in both directions, on two different
-- units. Four measurements agreeing to 11 decimals were not measurements.
--
-- Two bars run side by side so one screenshot compares both paths:
--   A  SetTimerDuration      -- the Cast Bar Z design
--   B  ticker + SetValue     -- the documented fallback
--
-- Each carries a MARKER frame anchored to its fill texture. The marker IS Cast
-- Bar Z's reveal mechanism, so measuring the marker tests what Z depends on
-- rather than a stand-in for it.

local rig

local function MakeBar(holder, label, yOff)
    local lbl = holder:CreateFontString(nil, "OVERLAY")
    lbl:SetFont("Fonts\\FRIZQT__.TTF", 10, "")
    lbl:SetPoint("TOPLEFT", holder, "TOPLEFT", 8, yOff)
    lbl:SetText(label)

    local bar = CreateFrame("StatusBar", nil, holder)
    bar:SetSize(180, 12)
    bar:SetPoint("TOPLEFT", holder, "TOPLEFT", 14, yOff - 13)
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:SetStatusBarColor(0.25, 0.8, 1.0)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)

    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(bar)
    bg:SetColorTexture(0.15, 0.15, 0.15, 1)

    local marker = CreateFrame("Frame", nil, bar)
    marker:SetAllPoints(bar:GetStatusBarTexture())

    return { bar = bar, marker = marker, label = lbl }
end

local function EnsureRig()
    if rig then return rig end

    local holder = CreateFrame("Frame", nil, UIParent)
    holder:SetSize(210, 100)
    holder:SetPoint("CENTER", UIParent, "CENTER", 0, 240)
    holder:SetFrameStrata("TOOLTIP")
    holder:Hide()

    local bg = holder:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(holder)
    bg:SetColorTexture(0, 0, 0, 0.8)

    local title = holder:CreateFontString(nil, "OVERLAY")
    title:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
    title:SetPoint("TOP", holder, "TOP", 0, -5)
    title:SetText("Cast Bar Z probe")

    local a = MakeBar(holder, "A  SetTimerDuration", -22)
    local b = MakeBar(holder, "B  ticker + SetValue", -56)

    -- Text-measurement target. Deliberately NOT a child of either bar, so a
    -- poisoned FontString can never affect bar layout.
    local fs = holder:CreateFontString(nil, "OVERLAY")
    fs:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
    fs:SetPoint("BOTTOM", holder, "BOTTOM", 0, 3)

    rig = { holder = holder, a = a, b = b, fs = fs }
    return rig
end

local function ShowRig(seconds)
    local r = EnsureRig()
    r.holder:Show()
    r.showToken = (r.showToken or 0) + 1
    local token = r.showToken
    C_Timer.After(seconds or 6, function()
        if not rig or rig.showToken ~= token then return end
        rig.holder:Hide()
        if rig.b.ticker then rig.b.ticker:Cancel(); rig.b.ticker = nil end
        pcall(rig.a.bar.SetValue, rig.a.bar, 0)
        pcall(rig.b.bar.SetValue, rig.b.bar, 0)
    end)
end

--------------------------------------------------------------------------------
-- Secret-safe reporting helpers
--------------------------------------------------------------------------------

-- Returns true / false / nil(unknown). Never throws.
local function IsSecret(v)
    if issecretvalue then
        local ok, r = pcall(issecretvalue, v)
        if ok then return r end
    end
    return nil
end

-- Renders any value for display without ever comparing or boolean-testing it.
local function Fmt(v)
    if v == nil then return "nil" end
    local secret = IsSecret(v)
    if secret == true then return "<SECRET " .. type(v) .. ">" end
    if secret == nil then return "<unknown secrecy, type=" .. type(v) .. ">" end
    return tostring(v)
end

local function Mark(ok)
    if ok == true then return "PASS" end
    if ok == false then return "FAIL" end
    return "????"
end

-- Unwraps a pcall result WITHOUT the `ok and v or nil` idiom, which silently
-- collapses a legitimate `false` into `nil`. That idiom made an early run
-- report `dur:HasSecretValues() = nil` on the player when the real answer was
-- `false` -- a documented-impossible value that cost a round of analysis.
local function Ret(ok, v)
    if ok then return v end
    return nil
end

--------------------------------------------------------------------------------
-- Probe
--------------------------------------------------------------------------------

local VALID_UNITS = {
    player = true, pet = true, target = true, focus = true,
    boss1 = true, boss2 = true, boss3 = true, boss4 = true, boss5 = true,
}

local function ProbeCastInfo(lines, unit)
    table.insert(lines, "-- 1. UnitCastingInfo / UnitChannelInfo ------------------")

    -- Try cast first, then channel. Return lists differ past index 6, so the two
    -- branches are kept separate rather than sharing one assignment.
    local okC, name, displayName, textureID, _, _, _, _,
          notInterruptible, castingSpellID, _, delayMs = pcall(UnitCastingInfo, unit)

    local channelled, isEmpowered, numEmpowerStages = false, nil, nil

    if not okC or name == nil then
        local okH, hName, hDisplay, hTexture, _, _, _,
              hNotInt, hSpellID, hEmpowered, hStages = pcall(UnitChannelInfo, unit)
        if okH and hName ~= nil then
            channelled = true
            okC, name, displayName, textureID = true, hName, hDisplay, hTexture
            notInterruptible, castingSpellID = hNotInt, hSpellID
            isEmpowered, numEmpowerStages = hEmpowered, hStages
            delayMs = nil
        elseif not okC then
            table.insert(lines, "  UnitCastingInfo pcall FAILED: " .. tostring(name))
            return nil
        end
    end

    if name == nil then
        table.insert(lines, "  No active cast or channel on '" .. unit .. "'.")
        table.insert(lines, "  Start a cast on this unit and re-run.")
        return nil
    end

    table.insert(lines, "  kind             : " .. (channelled and "CHANNEL" or "CAST"))
    table.insert(lines, "  name             : " .. Fmt(name))
    table.insert(lines, "  displayName      : " .. Fmt(displayName))
    table.insert(lines, "  textureID        : " .. Fmt(textureID))
    table.insert(lines, "  notInterruptible : " .. Fmt(notInterruptible))
    table.insert(lines, "  castingSpellID   : " .. Fmt(castingSpellID))
    if channelled then
        table.insert(lines, "  isEmpowered      : " .. Fmt(isEmpowered) .. "   (doc: NeverSecret)")
        table.insert(lines, "  numEmpowerStages : " .. Fmt(numEmpowerStages) .. "   (doc: NeverSecret)")
    else
        table.insert(lines, "  delayTimeMs      : " .. Fmt(delayMs) .. "   (doc: NeverSecret)")
    end
    table.insert(lines, "")
    table.insert(lines, "  EXPECT per SecretWhenUnitSpellCastRestricted:")
    table.insert(lines, "    player/pet -> all plain;  anything else -> name/texture/notInterruptible SECRET")

    return {
        name = name,
        notInterruptible = notInterruptible,
        channelled = channelled,
        isEmpowered = isEmpowered,
        numEmpowerStages = numEmpowerStages,
    }
end

local function ProbeTextPath(lines, cast)
    table.insert(lines, "")
    table.insert(lines, "-- 2. Secret text: render + measure ----------------------")

    local r = EnsureRig()

    local okSet = pcall(r.fs.SetText, r.fs, cast.name)
    table.insert(lines, "  " .. Mark(okSet) .. "  FontString:SetText(name)")
    if not okSet then
        table.insert(lines, "        -> SetText rejected the value. Expected AllowedWhenTainted.")
    end

    -- GetText on a Scoot-OWNED FontString: expected to carry the Text secret aspect once
    -- a secret string was poured in. This is the claim the old castbarZ doc got wrong.
    local okGet, got = pcall(r.fs.GetText, r.fs)
    if okGet then
        table.insert(lines, "        GetText() back  : " .. Fmt(got))
    else
        table.insert(lines, "        GetText() back  : threw (" .. tostring(got) .. ")")
    end

    -- The measurement path Cast Bar Z's shrink-to-fit depends on.
    if addon.MeasureTextWidth then
        local okM, w = pcall(addon.MeasureTextWidth, cast.name, "Fonts\\FRIZQT__.TTF", 12, "")
        local usable = okM and type(w) == "number" and IsSecret(w) == false
        table.insert(lines, "  " .. Mark(usable) .. "  addon.MeasureTextWidth(name) = " .. Fmt(okM and w or nil))
        if not usable then
            table.insert(lines, "        -> shrink-to-fit cannot size this name; would fall back to unscaled.")
        end
    else
        table.insert(lines, "  ????  addon.MeasureTextWidth missing (core/fonts.lua not loaded?)")
    end

    -- Local measurement on the rig FontString, for contrast. The rig is
    -- UIParent-anchored so this SHOULD also work; if it does not, the ruler is
    -- doing more than isolating the anchor chain.
    local okU, uw = pcall(r.fs.GetUnboundedStringWidth, r.fs)
    table.insert(lines, "        rig GetUnboundedStringWidth = " .. Fmt(okU and uw or nil))

    -- ClearText drops the Text secret aspect; SetText("") does NOT. Without this
    -- the rig FontString stays poisoned and every later run measures garbage.
    if r.fs.ClearText then
        pcall(r.fs.ClearText, r.fs)
    else
        pcall(r.fs.SetText, r.fs, "")
    end
end

local function ProbeInterruptible(lines, cast)
    table.insert(lines, "")
    table.insert(lines, "-- 3. notInterruptible -> color ------------------------")

    local ni = cast.notInterruptible
    if ni == nil then
        table.insert(lines, "  notInterruptible was nil; treating as false (Blizzard does the same).")
        ni = false
    end

    local secret = IsSecret(ni)
    table.insert(lines, "  secret? " .. Fmt(secret == nil and "unknown" or secret))

    if not (C_CurveUtil and C_CurveUtil.EvaluateColorFromBoolean) then
        table.insert(lines, "  ????  C_CurveUtil.EvaluateColorFromBoolean unavailable.")
        return
    end

    local white = CreateColor(1, 1, 1, 1)
    local gold  = CreateColor(1, 0.7, 0, 1)
    local okC, color = pcall(C_CurveUtil.EvaluateColorFromBoolean, ni, white, gold)
    table.insert(lines, "  " .. Mark(okC) .. "  EvaluateColorFromBoolean(notInterruptible, white, gold)")
    if okC and color then
        -- The returned color's components are secret when the input was; that is
        -- fine, SetVertexColor accepts them. Only the shape is reported here.
        local okR, rr = pcall(function() return color.r end)
        table.insert(lines, "        color.r = " .. Fmt(okR and rr or nil))
        table.insert(lines, "        -> feed straight into texture:SetVertexColor(); never compare it.")
    elseif not okC then
        table.insert(lines, "        error: " .. tostring(color))
    end

    -- Cross-check with the single-component variant. This is the one with a known
    -- production call site (Platynator/Display/CastBar.lua:128), so if the color
    -- variant above misbehaves, per-component evaluation is the proven fallback.
    if C_CurveUtil.EvaluateColorValueFromBoolean then
        local okV, v = pcall(C_CurveUtil.EvaluateColorValueFromBoolean, ni, 1, 0.7)
        table.insert(lines, "  " .. Mark(okV) .. "  EvaluateColorValueFromBoolean(notInterruptible, 1, 0.7) = "
            .. Fmt(okV and v or nil))
        if not okV then
            table.insert(lines, "        error: " .. tostring(v))
        end
    end
end

local function ProbeEmpowered(lines, unit, cast)
    table.insert(lines, "")
    table.insert(lines, "-- 4. Empowered stages ---------------------------------")

    -- numEmpowerStages off UnitChannelInfo is NeverSecret, so it is the cheap
    -- cross-check: if it disagrees with the percentages vector, trust this one.
    if cast and cast.channelled then
        table.insert(lines, "  numEmpowerStages (NeverSecret) : " .. Fmt(cast.numEmpowerStages))
    end

    if not UnitEmpoweredStagePercentages then
        table.insert(lines, "  ????  UnitEmpoweredStagePercentages missing on this build.")
        return
    end

    local ok, pcts = pcall(UnitEmpoweredStagePercentages, unit)
    if not ok then
        table.insert(lines, "  pcall FAILED: " .. tostring(pcts))
        return
    end
    if pcts == nil then
        table.insert(lines, "  No empowered channel active (Evoker only). Re-run mid-empower.")
        return
    end

    local okLen, n = pcall(function() return #pcts end)
    table.insert(lines, "  stage count : " .. Fmt(okLen and n or nil))
    if okLen and type(n) == "number" then
        for i = 1, n do
            local okV, v = pcall(function() return pcts[i] end)
            table.insert(lines, string.format("    [%d] = %s", i, Fmt(okV and v or nil)))
        end
        table.insert(lines, "  -> pip position = barWidth(DB) * pct.  NEVER GetWidth() on the Z frame.")
    end
end

-- No sample at t=0: a read taken in the same frame the rig is shown hits a dirty
-- layout, which answers unconditionally rather than correctly (the same
-- one-frame settling the alpha-gradient oracle needs). Every sample is deferred.
local SAMPLE_T = { 0.05, 0.3, 0.8, 1.5 }

local function ProbeDuration(lines, unit, cast, onDone)
    table.insert(lines, "")
    table.insert(lines, "-- 5. DurationObject -> bar animation ------------------")

    local r = EnsureRig()

    local getter = cast.channelled and UnitChannelDuration or UnitCastingDuration
    local getterName = cast.channelled and "UnitChannelDuration" or "UnitCastingDuration"

    local okD, dur = pcall(getter, unit)
    if not okD then
        table.insert(lines, "  " .. getterName .. " pcall FAILED: " .. tostring(dur))
        onDone()
        return
    end
    if dur == nil then
        table.insert(lines, "  " .. getterName .. " returned nothing.")
        onDone()
        return
    end

    table.insert(lines, "  " .. getterName .. " -> " .. Fmt(dur))

    -- HasSecretValues is ReturnsNeverSecret, so this is a plain bool safe to
    -- branch on. It is the supported way to know whether SetTimerDuration
    -- (SecretArguments = AllowedWhenUntainted) will accept this object from a
    -- tainted context. Cast Bar Z gates its path on exactly this call.
    if dur.HasSecretValues then
        local okH, hasSecrets = pcall(dur.HasSecretValues, dur)
        table.insert(lines, "  dur:HasSecretValues()    = " .. Fmt(Ret(okH, hasSecrets))
            .. "   (doc: ReturnsNeverSecret, Nilable = false -- nil here is a bug)")
    else
        table.insert(lines, "  ????  dur:HasSecretValues missing on this build.")
    end

    local okTot, total = pcall(dur.GetTotalDuration, dur)
    local okEl, elapsed = pcall(dur.GetElapsedDuration, dur)
    table.insert(lines, "  dur:GetTotalDuration()   = " .. Fmt(okTot and total or nil))
    table.insert(lines, "  dur:GetElapsedDuration() = " .. Fmt(okEl and elapsed or nil))

    local dir = cast.channelled
        and Enum.StatusBarTimerDirection.RemainingTime
        or Enum.StatusBarTimerDirection.ElapsedTime

    -- Bar A: the design under test. interpolation is Nilable = false in the docs
    -- (SimpleStatusBarAPIDocumentation.lua:317), so pass it explicitly instead of
    -- relying on nil falling through to the default.
    local okT, err = pcall(r.a.bar.SetTimerDuration, r.a.bar, dur,
        Enum.StatusBarInterpolation.Immediate, dir)
    table.insert(lines, "  " .. Mark(okT) .. "  A: SetTimerDuration(dur, Immediate, dir)")
    if not okT then
        table.insert(lines, "        error: " .. tostring(err))
    end

    -- Bar B: the documented fallback, running concurrently. SetMinMaxValues and
    -- SetValue are both AllowedWhenTainted and accept secrets, so B should work
    -- even where A cannot.
    local okB = pcall(function()
        r.b.bar:SetMinMaxValues(0, dur:GetTotalDuration())
    end)
    if r.b.ticker then r.b.ticker:Cancel() end
    r.b.ticker = C_Timer.NewTicker(0.02, function()
        pcall(function()
            if cast.channelled then
                r.b.bar:SetValue(dur:GetRemainingDuration())
            else
                r.b.bar:SetValue(dur:GetElapsedDuration())
            end
        end)
    end)
    table.insert(lines, "  " .. Mark(okB) .. "  B: SetMinMaxValues(0, total) + ticker SetValue()")

    ShowRig(6)

    -- Sample the MARKER (a frame anchored to the fill texture), not the fill
    -- texture itself -- the marker is Cast Bar Z's reveal mechanism.
    local widths = { a = {}, b = {} }

    local function Sample(idx)
        local okA, wa = pcall(r.a.marker.GetWidth, r.a.marker)
        local okBw, wb = pcall(r.b.marker.GetWidth, r.b.marker)
        widths.a[idx] = okA and wa or nil
        widths.b[idx] = okBw and wb or nil
    end

    -- Returns moved(true/false/nil-unreadable) and a rendered trace.
    local function Movement(list)
        local parts, first, last, readable = {}, nil, nil, true
        for i = 1, #SAMPLE_T do
            local v = list[i]
            table.insert(parts, string.format("t=%.1f %s", SAMPLE_T[i], Fmt(v)))
            if type(v) == "number" and IsSecret(v) == false then
                if first == nil then first = v end
                last = v
            else
                readable = false
            end
        end
        local verdict
        if readable and first ~= nil and last ~= nil then
            verdict = math.abs(last - first) > 0.5
        end
        return verdict, table.concat(parts, "  ")
    end

    C_Timer.After(SAMPLE_T[1], function() Sample(1) end)
    C_Timer.After(SAMPLE_T[2], function() Sample(2) end)
    C_Timer.After(SAMPLE_T[3], function() Sample(3) end)
    C_Timer.After(SAMPLE_T[4], function()
        Sample(4)

        local va, ta = Movement(widths.a)
        local vb, tb = Movement(widths.b)

        table.insert(lines, "")
        table.insert(lines, "  marker width = frame anchored to the fill texture")
        table.insert(lines, "  A  " .. ta)
        table.insert(lines, "  " .. Mark(va) .. "  A animated by C++")
        table.insert(lines, "  B  " .. tb)
        table.insert(lines, "  " .. Mark(vb) .. "  B animated by ticker")
        table.insert(lines, "")

        if va == true then
            table.insert(lines, "  -> SetTimerDuration works. Cast Bar Z uses it, no OnUpdate.")
        elseif vb == true then
            table.insert(lines, "  -> A static, B moving: build on the SetValue fallback.")
        elseif va == nil or vb == nil then
            table.insert(lines, "  -> marker width is secret, so the numbers cannot answer this.")
            table.insert(lines, "     Watch the on-screen rig instead: whichever bar visibly")
            table.insert(lines, "     swept is the answer. Both staying empty means neither works.")
        else
            table.insert(lines, "  -> NEITHER moved. Cast likely ended before t=1.5.")
            table.insert(lines, "     Re-run early in a long cast.")
        end

        onDone()
    end)
end

--------------------------------------------------------------------------------
-- Entry points
--------------------------------------------------------------------------------

local function DebugCastZProbe(unit)
    unit = (unit and unit ~= "" and unit:lower()) or "target"
    if not VALID_UNITS[unit] then
        addon.DebugShowWindow("Cast Bar Z Probe",
            "Unknown unit '" .. unit .. "'.\n\nValid: player, pet, target, focus, boss1..boss5")
        return
    end

    local lines = {
        "== Cast Bar Z - Phase 0 API probe ==",
        "unit          : " .. unit,
        "exists        : " .. tostring(UnitExists(unit)),
        "UnitIsPlayer  : " .. Fmt(UnitIsPlayer(unit)) .. "   (doc: plain bool, safe to branch on)",
        "InCombatLockdown: " .. tostring(InCombatLockdown()),
        "",
    }

    local cast = ProbeCastInfo(lines, unit)
    if not cast then
        addon.DebugShowWindow("Cast Bar Z Probe", lines)
        return
    end

    ProbeTextPath(lines, cast)
    ProbeInterruptible(lines, cast)
    ProbeEmpowered(lines, unit, cast)

    -- Duration test finishes asynchronously, then shows the window.
    ProbeDuration(lines, unit, cast, function()
        table.insert(lines, "")
        table.insert(lines, "== end ==")
        addon.DebugShowWindow("Cast Bar Z Probe", lines)
    end)
end

--------------------------------------------------------------------------------
-- Pet cast event watcher
--------------------------------------------------------------------------------

local petWatcher, petLog

local PET_EVENTS = {
    "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP",
    "UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_FAILED",
    "UNIT_SPELLCAST_INTERRUPTED",
    "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP",
    "UNIT_SPELLCAST_INTERRUPTIBLE", "UNIT_SPELLCAST_NOT_INTERRUPTIBLE",
}

local function DebugCastZPet()
    if petWatcher then
        petWatcher:UnregisterAllEvents()
        petWatcher = nil
        local out = petLog or {}
        table.insert(out, 1, "== Pet cast event watch (stopped) ==")
        if #out == 1 then
            table.insert(out, "")
            table.insert(out, "NO EVENTS CAPTURED.")
            table.insert(out, "If your pet cast something during the watch, the 'pet'")
            table.insert(out, "token does not deliver UNIT_SPELLCAST_* and the Pet bar")
            table.insert(out, "needs a different source.")
        end
        petLog = nil
        addon.DebugShowWindow("Cast Bar Z - Pet Events", out)
        return
    end

    petLog = {}
    -- Kept off addon.Events: RegisterUnitEvent filters the pet token C-side; the bus registers by name only.
    petWatcher = CreateFrame("Frame")
    for _, ev in ipairs(PET_EVENTS) do
        -- RegisterUnitEvent is the pattern Cast Bar Z will use in production.
        pcall(petWatcher.RegisterUnitEvent, petWatcher, ev, "pet")
    end
    petWatcher:SetScript("OnEvent", function(_, event, unit, ...)
        table.insert(petLog, string.format("%.1f  %s  unit=%s", GetTime() % 1000, event, tostring(unit)))
        if #petLog > 200 then table.remove(petLog, 1) end
    end)

    addon.DebugShowWindow("Cast Bar Z - Pet Events",
        "Watching UNIT_SPELLCAST_* on the 'pet' token.\n\n"
        .. "Have your pet cast something (Growl, Claw, a channel), then run\n"
        .. "  /scoot debug castz petevents\n"
        .. "again to stop the watch and dump what was captured.")
end

--------------------------------------------------------------------------------
-- Player cast-end event order watcher
--------------------------------------------------------------------------------
--
-- Added after three failed tries at reasoning out which of
-- UNIT_SPELLCAST_STOP / _INTERRUPTED / _FAILED arrives first when a cast is
-- cancelled, and how far apart they land. Blizzard's own bar does not answer it:
-- CastingBarMixin branches on a cached `casting` flag and a castID comparison, so
-- it is immune to the ordering rather than documentation of it.
--
-- Cast Bar Z cannot use castID (a WOWGUID, secret on restricted units), so the
-- ordering and the gap are load-bearing facts for it. This measures both, plus
-- what UnitCastingInfo answers at the instant of each event -- which is the other
-- half of the question, since Z re-queries where Blizzard consults a flag.

local endWatcher, endLog, endT0

local END_EVENTS = {
    "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP",
    "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED",
    "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP",
    "UNIT_SPELLCAST_EMPOWER_START", "UNIT_SPELLCAST_EMPOWER_STOP",
    "UNIT_SPELLCAST_DELAYED",
}

-- Which payload slot carries the outcome, per stop event. Empowered and channelled
-- casts do NOT fire UNIT_SPELLCAST_INTERRUPTED -- Blizzard reads the verdict off
-- these fields instead (CastingBarFrame.lua:266-274) -- so a watcher that logs only
-- the event NAME cannot see the difference between a released empower and one
-- cancelled by moving. Added after exactly that went unnoticed.
local END_PAYLOAD = {
    UNIT_SPELLCAST_CHANNEL_STOP = { interruptedBy = 4 },
    UNIT_SPELLCAST_EMPOWER_STOP = { complete = 4, interruptedBy = 5 },
    UNIT_SPELLCAST_INTERRUPTED  = { interruptedBy = 4 },
}

--- Describe a payload field without ever comparing it. On a restricted unit these
--- are secret, so the answer is "what sort of thing is it", not "what is it".
local function DescribeArg(v)
    if type(v) == "nil" then return "nil" end
    if issecretvalue and issecretvalue(v) then return "SECRET " .. type(v) end
    return tostring(v)
end

local endUnit

local VALID_END_UNITS = {
    player = true, pet = true, target = true, focus = true,
    boss1 = true, boss2 = true, boss3 = true, boss4 = true, boss5 = true,
}

--- @param unitArg string|nil  any unit token Cast Bar Z draws; defaults to player.
--------------------------------------------------------------------------------
-- /scoot debug castz fit
--------------------------------------------------------------------------------
-- "The name did not shrink" has three causes that look identical on screen: the
-- ruler answered nothing, it answered a width small enough to pass for a fit, or
-- the shrink floor clamped. This reports which, per bar, from the last fit each
-- one performed -- plus an independent measurement of a known string, so a broken
-- ruler is distinguishable from a bar that simply never had a long name.
local function DebugCastZFit()
    local CBZ = addon.CastBarZ
    if not CBZ then
        addon.DebugShowWindow("Cast Bar Z - Fit", "Cast Bar Z is not loaded.")
        return
    end

    local face  = addon.ResolveFontFace(CBZ._GetSetting("fontFace"))
    local size  = tonumber(CBZ._GetSetting("fontSize")) or 14
    local style = tostring(CBZ._GetSetting("fontStyle") or "OUTLINE")

    local lines = {
        "== Cast Bar Z shrink-to-fit ==",
        "",
        string.format("font: %s  size: %s  style: %s", tostring(face), tostring(size), style),
    }

    -- Ruler health, measured here rather than trusted. Same call the fit makes.
    local probe = "Trader's Gilded Brutosaur"
    local probeW = addon.MeasureTextWidth and addon.MeasureTextWidth(probe, face, size, style)
    table.insert(lines, string.format(
        "ruler: \"%s\" at %spt measures %s",
        probe, tostring(size), probeW and string.format("%.1fpx", probeW) or "NOTHING (ruler is not answering)"))
    table.insert(lines, "")

    local any = false
    for _, row in ipairs(CBZ.BARS) do
        local bar = CBZ._bars[row.barKey]
        if bar then
            any = true
            local info = bar.fitInfo
            table.insert(lines, "-- " .. row.barKey .. " (unit " .. row.token .. ")")
            if not info then
                table.insert(lines, "   no fit recorded yet -- nothing has been cast on this unit.")
            else
                table.insert(lines, string.format("   avail    %s px  (bar width minus end caps)",
                    info.avail and string.format("%.1f", info.avail) or "n/a"))
                table.insert(lines, string.format("   secret   %s", tostring(info.secret)))
                table.insert(lines, string.format("   natural  %s",
                    info.natural and string.format("%.1f px", info.natural)
                    or (info.secret and "not measured (secret name)" or "MEASUREMENT FAILED")))
                table.insert(lines, string.format("   rendered %s pt", tostring(info.size)))
                local verdict
                if info.secret or not info.natural then
                    verdict = "engine ellipsis (no measurement available)"
                elseif info.size == size then
                    verdict = "fit at full size, no shrink needed"
                else
                    verdict = "shrunk from " .. tostring(size) .. "pt"
                end
                table.insert(lines, "   -> " .. verdict)
            end

            local ramp = bar.rampInfo
            if ramp then
                local function Swatch(c)
                    if not c then return "?" end
                    return string.format("%.2f %.2f %.2f", c[1], c[2], c[3])
                end
                table.insert(lines, string.format("   ramp     %s", ramp.source))
                table.insert(lines, string.format("            %s  ->  %s",
                    Swatch(ramp.first), Swatch(ramp.last)))
                table.insert(lines, string.format("   line     %s", Swatch(ramp.line)))
            end
            table.insert(lines, "")
        end
    end

    if not any then
        table.insert(lines, "No bars exist. Enable a unit on the Cast Bars page first.")
    end

    addon.DebugShowWindow("Cast Bar Z - Fit", lines)
end

local function DebugCastZEndOrder(unitArg)
    if endWatcher then
        endWatcher:UnregisterAllEvents()
        endWatcher = nil

        local out = endLog or {}
        table.insert(out, 1, "== Cast end event order (stopped) -- unit: " .. tostring(endUnit) .. " ==")
        table.insert(out, 2, "ms = milliseconds since the first event captured.")
        table.insert(out, 3, "casting/chan = what UnitCastingInfo/UnitChannelInfo")
        table.insert(out, 4, "               answered AT THAT INSTANT.")
        table.insert(out, 5, "secret = whether the spell NAME was a secret value then.")
        table.insert(out, 6, "complete/interruptedBy = the stop event's own payload;")
        table.insert(out, 7, "               the ONLY place a channel or empower")
        table.insert(out, 8, "               reports that it did not go off.")
        table.insert(out, 9, "")
        if #out == 9 then
            table.insert(out, "NO EVENTS CAPTURED.")
        end
        endLog, endT0, endUnit = nil, nil, nil
        addon.DebugShowWindow("Cast Bar Z - Cast End Order", out)
        return
    end

    local unit = string.lower(tostring(unitArg or "player"))
    if not VALID_END_UNITS[unit] then
        addon.DebugShowWindow("Cast Bar Z - Cast End Order",
            "Unknown unit: " .. unit .. "\n\n"
            .. "Usage: /scoot debug castz endorder [player|pet|target|focus|boss1..5]")
        return
    end

    endLog, endT0, endUnit = {}, nil, unit
    -- Kept off addon.Events: RegisterUnitEvent filters the chosen unit C-side; the bus registers by name only.
    endWatcher = CreateFrame("Frame")
    for _, ev in ipairs(END_EVENTS) do
        pcall(endWatcher.RegisterUnitEvent, endWatcher, ev, unit)
    end

    endWatcher:SetScript("OnEvent", function(_, event, ...)
        local now = GetTime()
        endT0 = endT0 or now

        local payload = ""
        local slots = END_PAYLOAD[event]
        if slots then
            local parts = {}
            for _, field in ipairs({ "complete", "interruptedBy" }) do
                local slot = slots[field]
                if slot then
                    table.insert(parts, field .. "=" .. DescribeArg((select(slot, ...))))
                end
            end
            payload = "  " .. table.concat(parts, " ")
        end

        -- type(), never a comparison: on a restricted unit these are secret, and
        -- comparing a secret throws. The player never produces one, but the guard
        -- order is the rule regardless (secret-guard-ordering) -- and from here on
        -- this watcher is pointed at units that do.
        local name    = UnitCastingInfo(unit)
        local casting = type(name) ~= "nil"
        local chan    = type(UnitChannelInfo(unit)) ~= "nil"

        -- The half the UI source cannot answer. Blizzard consults a cached flag and
        -- a castID; Z re-queries, so what the getter says AT EVENT TIME -- and
        -- whether it says it in the clear -- is the fact the code depends
        -- on. On a restricted unit `casting` stays readable while `secret` goes
        -- true, which is exactly the state Z has to render from.
        local secret = casting and issecretvalue and issecretvalue(name) or false

        table.insert(endLog, string.format(
            "%6.1fms  %-32s casting=%-5s chan=%-5s secret=%s%s",
            (now - endT0) * 1000, event,
            tostring(casting), tostring(chan), tostring(secret), payload))
        if #endLog > 200 then table.remove(endLog, 1) end
    end)

    addon.DebugShowWindow("Cast Bar Z - Cast End Order",
        "Watching UNIT_SPELLCAST_* on '" .. unit .. "'.\n\n"
        .. "1. Get that unit casting something with a cast time.\n"
        .. "2. Let ONE cast finish normally.\n"
        .. "3. Have another one cancelled (move, or kick it).\n"
        .. "4. On an Evoker, do both again with an empowered cast.\n"
        .. "5. Run  /scoot debug castz endorder  again to stop and dump.\n\n"
        .. "What matters is the order of STOP vs INTERRUPTED/FAILED, the gap\n"
        .. "in ms between them, whether casting= was still true when the first\n"
        .. "of them arrived, and -- on a non-player unit -- that secret=true\n"
        .. "without anything having thrown.")
end

--------------------------------------------------------------------------------
-- /scoot debug castz empower
--------------------------------------------------------------------------------
--
-- Phase 3's step 0. Two facts decide how empowered casts are drawn, and neither
-- is answerable from the API documentation:
--
--   1. Does UnitChannelDuration span the hold-at-max window, or stop at the last
--      stage? That selects the includeHoldAtMaxTime argument, and getting it
--      wrong puts every pip in the wrong place. Both vectors are printed side by
--      side so one cast settles it.
--   2. Does StatusBar:GetValue() report the value the C++ timer is animating
--      through right now, or the value it is animating TOWARD? A released
--      empowered cast has to freeze where the player let go, and the only way to
--      freeze an engine-driven timer is to write its current value back to it.
--      If GetValue answers with the target, the bar snaps to full instead.
--
-- Question 2 is tested by DOING it: the round trip below will freeze the live
-- bar if it works. That is the pass condition, not a side effect.
--
-- Player-only for the freeze half. On any other unit the bar's value is secret,
-- so the three samples cannot be compared -- which is the secret system working,
-- not a gap here. The percentages half works on every unit.

local function EmpowerRowForToken(unit)
    local CBZ = addon.CastBarZ
    if not CBZ or not CBZ.BARS then return nil end
    for _, row in ipairs(CBZ.BARS) do
        if row.token == unit then return row end
    end
    return nil
end

--- Print one percentages vector, its running total, and the pixel positions it
--- implies at `barW`. Pixel positions are what matter -- a vector that
--- looks reasonable can still place every pip in the left half.
local function DumpPercentages(lines, unit, includeHold, barW)
    local label = includeHold and "includeHoldAtMaxTime = true (default)"
                              or "includeHoldAtMaxTime = false"
    table.insert(lines, "  " .. label)

    local ok, pcts = pcall(UnitEmpoweredStagePercentages, unit, includeHold)
    if not ok then
        table.insert(lines, "    pcall FAILED: " .. tostring(pcts))
        return
    end
    if pcts == nil then
        table.insert(lines, "    returned nothing -- no empowered channel on this unit right now.")
        return
    end

    local okLen, n = pcall(function() return #pcts end)
    if not okLen or type(n) ~= "number" then
        table.insert(lines, "    length unreadable: " .. Fmt(n))
        return
    end

    table.insert(lines, string.format("    %d entries", n))
    local cum = 0
    for i = 1, n do
        local okV, v = pcall(function() return pcts[i] end)
        local value = Ret(okV, v)
        -- Only accumulate once the value is known plain. A secret here would be a
        -- documentation error rather than an expected case, so say so loudly
        -- instead of quietly producing wrong pixel numbers.
        if type(value) == "number" and IsSecret(value) ~= true then
            cum = cum + value
            table.insert(lines, string.format(
                "      [%d] %.4f   cumulative %.4f   ->  x = %.1f px",
                i, value, cum, barW * cum))
        else
            table.insert(lines, string.format(
                "      [%d] %s   <-- NOT A PLAIN NUMBER; the pip geometry cannot use this",
                i, Fmt(value)))
        end
    end
    table.insert(lines, string.format("    total %.4f  (expect 1.0000)", cum))
end

--- @param unitArg string|nil  defaults to player.
local function DebugCastZEmpower(unitArg)
    local unit = unitArg
    if not unit or not VALID_UNITS[unit] then unit = "player" end

    local CBZ = addon.CastBarZ
    local row = EmpowerRowForToken(unit)
    local cfg = row and CBZ and CBZ._GetUnitConfig(row.unitKey)
    local barW = tonumber(cfg and cfg.barWidth) or 200

    local lines = {
        "== Cast Bar Z empowered stages ==",
        "",
        "unit      : " .. unit,
        string.format("bar width : %d px (from the DB -- never GetWidth)", barW),
        "",
        "-- 1. Is this an empowered channel? ---------------------",
    }

    -- isEmpowered and numEmpowerStages are both NeverSecret (UnitDocumentation
    -- :877-878), so they answer on any unit and are the branch Phase 3 keys on.
    local okCh, name, _, _, _, _, _, notInterruptible, spellID, isEmpowered, numStages =
        pcall(UnitChannelInfo, unit)
    if not okCh then
        table.insert(lines, "  UnitChannelInfo threw: " .. tostring(name))
    else
        table.insert(lines, "  name             : " .. Fmt(name))
        table.insert(lines, "  spellID          : " .. Fmt(spellID))
        table.insert(lines, "  notInterruptible : " .. Fmt(notInterruptible))
        table.insert(lines, "  isEmpowered      : " .. Fmt(isEmpowered) .. "   (NeverSecret)")
        table.insert(lines, "  numEmpowerStages : " .. Fmt(numStages) .. "   (NeverSecret)")
    end

    table.insert(lines, "")
    table.insert(lines, "-- 2. Stage percentages -------------------------------")
    table.insert(lines, "  Segment i spans x[i-1]..x[i]; a pip sits at every x except the last.")
    table.insert(lines, "")
    DumpPercentages(lines, unit, true, barW)
    table.insert(lines, "")
    DumpPercentages(lines, unit, false, barW)
    table.insert(lines, "")
    table.insert(lines, "  Which one is right: whichever puts the LAST pip inboard of the bar's")
    table.insert(lines, "  right edge while the sweep still reaches that edge. If the sweep")
    table.insert(lines, "  arrives early, the duration excludes hold-at-max -> use false.")

    table.insert(lines, "")
    table.insert(lines, "-- 3. Channel duration --------------------------------")
    local okD, dur = pcall(UnitChannelDuration, unit)
    if not okD then
        table.insert(lines, "  UnitChannelDuration threw: " .. tostring(dur))
    elseif dur == nil then
        table.insert(lines, "  returned nothing (MayReturnNothing) -- not channelling.")
    else
        local okS, hasSecret = pcall(dur.HasSecretValues, dur)
        table.insert(lines, "  HasSecretValues  : " .. Fmt(Ret(okS, hasSecret))
            .. "   (informational only -- never gate the render path on it)")
    end

    ----------------------------------------------------------------------------
    -- 4. What the bar drew
    ----------------------------------------------------------------------------
    table.insert(lines, "")
    table.insert(lines, "-- 4. Segments as drawn --------------------------------")

    local bar = row and CBZ and CBZ._bars and CBZ._bars[row.barKey]
    local info = bar and bar.empowerInfo
    if not info then
        table.insert(lines, "  No tier segments on this bar right now.")
    else
        table.insert(lines, string.format("  segments drawn   : %s", tostring(info.segments)))
        table.insert(lines, string.format("  includeHold used : %s", tostring(info.includeHold)))
        table.insert(lines, string.format("  numEmpowerStages : %s", tostring(info.numStages)))
        -- The cross-check. With the hold window counted, the vector should be
        -- exactly one longer than the stage count; anything else means
        -- INCLUDE_HOLD_AT_MAX in empowered.lua is set the wrong way.
        if type(info.numStages) == "number" and type(info.segments) == "number" then
            local expected = info.includeHold and (info.numStages + 1) or info.numStages
            table.insert(lines, string.format("  -> expected %d segment(s); %s",
                expected,
                (expected == info.segments) and "MATCHES"
                    or "MISMATCH -- flip INCLUDE_HOLD_AT_MAX"))
        end
    end

    ----------------------------------------------------------------------------
    -- 5. The freeze round trip
    ----------------------------------------------------------------------------
    table.insert(lines, "")
    table.insert(lines, "-- 5. Freeze-on-release round trip ---------------------")

    local pb = bar and bar.progressBar
    if not pb then
        table.insert(lines, "  No live Cast Bar Z for this unit -- enable it and re-run mid-cast.")
    else
        local okG, before = pcall(pb.GetValue, pb)
        table.insert(lines, "  GetValue before  : " .. Fmt(Ret(okG, before)))

        -- SetValue is AllowedWhenTainted and GetValue's result is passed straight
        -- back without ever being compared or used in arithmetic, so this is legal
        -- even when the value is secret. It is only the READBACK that needs a
        -- plain value, which is why the verdict below is player-only.
        local okSet = pcall(pb.SetValue, pb, Ret(okG, before))
        table.insert(lines, "  SetValue(same)   : " .. Mark(okSet))

        local okA, after = pcall(pb.GetValue, pb)
        table.insert(lines, "  GetValue after   : " .. Fmt(Ret(okA, after)))

        local first = Ret(okG, before)
        table.insert(lines, "")
        table.insert(lines, "  Watch the bar. If it stopped dead, the freeze works and")
        table.insert(lines, "  _FinishCast can use it. If it kept filling, GetValue is")
        table.insert(lines, "  reporting the timer's TARGET and the fallback applies.")

        -- Third sample, a fifth of a second later, so the window is dumped with the
        -- verdict already in it rather than leaving it to the eye.
        C_Timer.After(0.2, function()
            local okL, later = pcall(pb.GetValue, pb)
            local verdict
            if type(first) == "number" and type(Ret(okL, later)) == "number"
                and IsSecret(first) ~= true and IsSecret(later) ~= true then
                verdict = (later == first)
                    and "FROZEN -- the round trip stopped the timer."
                    or  string.format("STILL MOVING (%.4f -> %.4f) -- the freeze does not hold.", first, later)
            else
                verdict = "value is secret on this unit; compare by eye instead."
            end
            table.insert(lines, string.format("  GetValue +0.2s   : %s", Fmt(Ret(okL, later))))
            table.insert(lines, "  -> " .. verdict)
            addon.DebugShowWindow("Cast Bar Z - Empowered", lines)
        end)
        return
    end

    addon.DebugShowWindow("Cast Bar Z - Empowered", lines)
end

--------------------------------------------------------------------------------
-- /scoot debug castz time
--------------------------------------------------------------------------------
--
-- Phase 5's step 0. Cast time text is drawn by a DurationTextBinding
-- (C_DurationUtil.CreateDurationTextBinding) rather than by Lua arithmetic:
-- Blizzard's own UpdateCastTimeText does `max - GetValue()` (CastingBarFrame.lua
-- :761-780), which is arithmetic on a secret the moment the unit is restricted,
-- and is event-driven besides -- so it is not even a live ticker. The binding
-- samples the duration object engine-side and writes the FontString on its own
-- schedule, which also keeps Cast Bar Z's no-OnUpdate property intact.
--
-- Two things are measured here, and only the first can invalidate the design:
--
--   1. Does the binding ACCEPT a duration that holds secrets? SetDuration is
--      SecretArguments = "AllowedWhenUntainted", the same annotation carried by
--      SetTimerDuration -- which Phase 0 finding 6 measured as NOT a gate, because
--      a LuaDurationObject is plain userdata that merely holds secrets internally,
--      so the argument check never sees them. The reasoning transfers, but it is
--      one call to confirm rather than assume.
--
--   2. Is the resulting TEXT readable? The annotations disagree with each other:
--      dur:FormatRemainingDuration is SecretWhenNumericFormatterSecret and nothing
--      else (LuaDurationObjectAPIDocumentation.lua:144-160), which reads as "plain
--      even from a secret duration", while binding:GetFormattedText is
--      ConditionalSecret (DurationTextBindingObjectAPIDocumentation.lua:98-110).
--      Both cannot be the whole story, and a readable remaining-time on an enemy
--      cast is exactly the leak the restriction exists to prevent -- so the
--      annotation is the suspect, not the behaviour. This does NOT gate the build:
--      the binding writes the FontString either way. It decides only whether the
--      time text can be MEASURED (shrink-to-fit, centering) or must be laid out
--      blind, which is the same fork the spell name already lives on.

local timeRig

local function EnsureTimeRig()
    if timeRig then return timeRig end

    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(220, 30)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, -140)

    local fs = f:CreateFontString(nil, "OVERLAY")
    fs:SetFont("Fonts\\FRIZQT__.TTF", 18, "OUTLINE")
    fs:SetPoint("CENTER")
    fs:SetText("--")

    -- Anchored to UIParent only, exactly like the Phase 0 rig: that isolates "is
    -- the DATA secret" from "is the FRAME anchored to something secret".
    timeRig = { frame = f, fs = fs }
    return timeRig
end

--- @param unitArg string|nil  defaults to player.
local function DebugCastZTime(unitArg)
    local unit = string.lower(tostring(unitArg or "player"))
    if not VALID_UNITS[unit] then
        addon.DebugShowWindow("Cast Bar Z - Cast Time",
            "Unknown unit: " .. unit .. "\n\n"
            .. "Usage: /scoot debug castz time [player|pet|target|focus|boss1..5]")
        return
    end

    local lines = {
        "== Cast Bar Z cast time text ==",
        "",
        "unit : " .. unit,
        "",
        "-- 1. Does the API exist? ------------------------------",
    }

    local durUtil = C_DurationUtil
    local strUtil = C_StringUtil
    table.insert(lines, "  C_DurationUtil.CreateDurationTextBinding : "
        .. Mark(type(durUtil and durUtil.CreateDurationTextBinding) == "function"))
    table.insert(lines, "  C_StringUtil.CreateNumericRuleFormatter   : "
        .. Mark(type(strUtil and strUtil.CreateNumericRuleFormatter) == "function"))
    table.insert(lines, "  C_StringUtil.CreateSecondsFormatter       : "
        .. Mark(type(strUtil and strUtil.CreateSecondsFormatter) == "function"))

    if type(durUtil and durUtil.CreateDurationTextBinding) ~= "function" then
        table.insert(lines, "")
        table.insert(lines, "  The binding API is absent. Phase 5 needs a different design;")
        table.insert(lines, "  the only other tickers available are OnUpdate and C_Timer.")
        addon.DebugShowWindow("Cast Bar Z - Cast Time", lines)
        return
    end

    ----------------------------------------------------------------------------
    -- 2. Build the formatter and the binding
    ----------------------------------------------------------------------------
    table.insert(lines, "")
    table.insert(lines, "-- 2. Build ------------------------------------------")

    local okF, fmtr = pcall(strUtil.CreateNumericRuleFormatter)
    table.insert(lines, "  CreateNumericRuleFormatter : " .. Mark(okF))
    if not okF then
        table.insert(lines, "    threw: " .. tostring(fmtr))
        addon.DebugShowWindow("Cast Bar Z - Cast Time", lines)
        return
    end

    -- One breakpoint from zero: round to tenths and print one decimal. This is
    -- the shape the shipped formatter uses, so a failure here is a failure of the
    -- real thing rather than of a stand-in.
    local okR = pcall(fmtr.SetBreakpoints, fmtr, {
        { threshold = 0, step = 0.1, format = "%.1f" },
    })
    table.insert(lines, "  SetBreakpoints             : " .. Mark(okR))

    local okB, binding = pcall(durUtil.CreateDurationTextBinding)
    table.insert(lines, "  CreateDurationTextBinding  : " .. Mark(okB))
    if not okB then
        table.insert(lines, "    threw: " .. tostring(binding))
        addon.DebugShowWindow("Cast Bar Z - Cast Time", lines)
        return
    end

    local rig = EnsureTimeRig()
    rig.frame:Show()
    table.insert(lines, "  SetFontString              : "
        .. Mark(pcall(binding.SetFontString, binding, rig.fs)))
    table.insert(lines, "  SetFormatter               : "
        .. Mark(pcall(binding.SetFormatter, binding, fmtr)))
    table.insert(lines, "  SetUpdateInterval(0)       : "
        .. Mark(pcall(binding.SetUpdateInterval, binding, 0)))

    ----------------------------------------------------------------------------
    -- 3. The gating question: does it take a secret-holding duration?
    ----------------------------------------------------------------------------
    table.insert(lines, "")
    table.insert(lines, "-- 3. SetDuration on a live cast ----------------------")

    local okDur, dur = pcall(UnitCastingDuration, unit)
    if not okDur or dur == nil then
        okDur, dur = pcall(UnitChannelDuration, unit)
    end

    if not okDur then
        table.insert(lines, "  duration getter threw: " .. tostring(dur))
    elseif dur == nil then
        table.insert(lines, "  Not casting. Re-run DURING a cast -- both getters are")
        table.insert(lines, "  MayReturnNothing, so nothing here is measurable idle.")
    else
        local okH, hasSecret = pcall(dur.HasSecretValues, dur)
        table.insert(lines, "  dur:HasSecretValues        : " .. Fmt(Ret(okH, hasSecret)))

        local okSD = pcall(binding.SetDuration, binding, dur)
        table.insert(lines, "  SetDuration                : " .. Mark(okSD)
            .. "   <- the gating call")

        table.insert(lines, "  SetTextFormat(remaining)   : "
            .. Mark(pcall(binding.SetTextFormat, binding, "{}", {
                { property = Enum.DurationTextBindingProperty.RemainingDuration,
                  formatter = fmtr },
            })))
        table.insert(lines, "  Enable                     : "
            .. Mark(pcall(binding.Enable, binding)))

        local okBS, bindSecret = pcall(binding.HasSecretValues, binding)
        table.insert(lines, "  binding:HasSecretValues    : " .. Fmt(Ret(okBS, bindSecret))
            .. "   (ReturnsNeverSecret)")

        ------------------------------------------------------------------------
        -- 4. Readability -- informational, not a gate
        ------------------------------------------------------------------------
        table.insert(lines, "")
        table.insert(lines, "-- 4. Is the text readable? ---------------------------")

        local okT, text = pcall(binding.GetFormattedText, binding)
        table.insert(lines, "  binding:GetFormattedText   : " .. Fmt(Ret(okT, text)))

        local okFR, remaining = pcall(dur.FormatRemainingDuration, dur, fmtr)
        table.insert(lines, "  dur:FormatRemainingDuration: " .. Fmt(Ret(okFR, remaining)))
        table.insert(lines, "")
        table.insert(lines, "  The annotations disagree about these two: the second claims")
        table.insert(lines, "  SecretWhenNumericFormatterSecret only. If it comes back plain")
        table.insert(lines, "  on a restricted unit, the annotation is right and remaining")
        table.insert(lines, "  time is measurable there -- surprising, and worth recording.")
    end

    ----------------------------------------------------------------------------
    -- 5. Is it ticking?
    ----------------------------------------------------------------------------
    table.insert(lines, "")
    table.insert(lines, "-- 5. Live tick ---------------------------------------")
    table.insert(lines, "  A rig is on screen below centre. Watch it, then read the")
    table.insert(lines, "  two samples below -- the eye is the instrument on a")
    table.insert(lines, "  restricted unit, where no sample can be compared.")

    C_Timer.After(0.4, function()
        local okS, sample = pcall(binding.GetFormattedText, binding)
        table.insert(lines, "  GetFormattedText +0.4s     : " .. Fmt(Ret(okS, sample)))
        table.insert(lines, "")
        table.insert(lines, "  Rig stays up. Run  /scoot debug castz time  again to refresh it.")
        addon.DebugShowWindow("Cast Bar Z - Cast Time", lines)
    end)
end

addon:RegisterDebugCommand({
    name = "castz", help = "Cast Bar Z live-cast probes",
    usage = {
        "castz [player|pet|target|focus|boss1..5] - API probe for that unit",
        "castz petevents - toggle the pet cast-event watch",
        "castz endorder [unit] - toggle the cast-end event order watch",
        "castz fit - shrink-to-fit state of each live bar",
        "castz empower [unit] - empowered cast stages",
        "castz time [unit] - cast timing",
    },
    handler = function(sub, rest)
        -- "petevents", not "pet": "pet" is a valid unit to probe.
        if sub == "petevents" then DebugCastZPet()
        elseif sub == "endorder" then DebugCastZEndOrder(rest[2])
        elseif sub == "fit" then DebugCastZFit()
        elseif sub == "empower" then DebugCastZEmpower(rest[2])
        elseif sub == "time" then DebugCastZTime(rest[2])
        else DebugCastZProbe(sub) end
    end,
})
