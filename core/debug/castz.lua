-- debug/castz.lua - /scoot debug castz
--
-- Phase 0 validation probe for Cast Bar Z. Answers, against a live cast, the
-- questions the Cast Bar Z architecture rests on:
--
--   1. Does UnitCastingDuration -> StatusBar:SetTimerDuration actually animate a
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

local addonName, addon = ...

--------------------------------------------------------------------------------
-- Test rig (Scoot-owned, off-screen, UIParent-anchored)
--------------------------------------------------------------------------------

local rig

local function EnsureRig()
    if rig then return rig end

    local holder = CreateFrame("Frame", nil, UIParent)
    holder:SetSize(200, 24)
    -- Off-screen but anchored only to UIParent, so the rig's own anchor chain can
    -- never be secret. That is the whole point: it isolates "is the DATA secret"
    -- from "is the FRAME anchored to something secret".
    holder:SetPoint("CENTER", UIParent, "CENTER", 0, -10000)
    holder:Hide()

    local bar = CreateFrame("StatusBar", nil, holder)
    bar:SetSize(180, 16)
    bar:SetPoint("CENTER", holder, "CENTER", 0, 0)
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)

    local fs = bar:CreateFontString(nil, "OVERLAY")
    fs:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
    fs:SetPoint("CENTER", bar, "CENTER", 0, 0)

    rig = { holder = holder, bar = bar, fs = fs }
    return rig
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

    -- GetText on our OWN FontString: expected to carry the Text secret aspect once
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

    pcall(r.fs.SetText, r.fs, "")
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
        -- fine, SetVertexColor accepts them. We only report shape here.
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

local function ProbeDuration(lines, unit, cast, onDone)
    table.insert(lines, "")
    table.insert(lines, "-- 5. DurationObject -> SetTimerDuration ---------------")

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

    local dir = cast.channelled
        and Enum.StatusBarTimerDirection.RemainingTime
        or Enum.StatusBarTimerDirection.ElapsedTime

    local okT, err = pcall(r.bar.SetTimerDuration, r.bar, dur, nil, dir)
    table.insert(lines, "  " .. Mark(okT) .. "  StatusBar:SetTimerDuration(dur, nil, dir)")
    if not okT then
        table.insert(lines, "        error: " .. tostring(err))
        table.insert(lines, "        -> FALL BACK to OnUpdate + SetValue(dur:GetElapsedDuration()).")
        onDone()
        return
    end

    -- Did it actually move? Sample the fill texture width now and again shortly.
    local fill = r.bar:GetStatusBarTexture()
    local okW1, w1 = pcall(fill.GetWidth, fill)
    table.insert(lines, "        fill width t=0.0 : " .. Fmt(okW1 and w1 or nil))

    C_Timer.After(0.45, function()
        local okW2, w2 = pcall(fill.GetWidth, fill)
        table.insert(lines, "        fill width t=0.45: " .. Fmt(okW2 and w2 or nil))

        local s1, s2 = IsSecret(w1), IsSecret(w2)
        if okW1 and okW2 and s1 == false and s2 == false
           and type(w1) == "number" and type(w2) == "number" then
            local moved = math.abs(w2 - w1) > 0.5
            table.insert(lines, "  " .. Mark(moved) .. "  fill animated by C++ (delta "
                .. string.format("%.2f", w2 - w1) .. "px)")
            if not moved then
                table.insert(lines, "        -> bar did not move. Cast may have ended, or")
                table.insert(lines, "           SetTimerDuration silently no-op'd. Retry mid-cast.")
            end
        else
            table.insert(lines, "  ????  fill width is secret or unreadable.")
            table.insert(lines, "        NOT fatal: clipFrame anchors to the fill texture and")
            table.insert(lines, "        never reads its width. Reveal still works.")
        end

        onDone()
    end)
end

--------------------------------------------------------------------------------
-- Entry points
--------------------------------------------------------------------------------

function addon.DebugCastZProbe(unit)
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

function addon.DebugCastZPet()
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
