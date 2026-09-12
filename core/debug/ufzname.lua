--------------------------------------------------------------------------------
-- core/debug/ufzname.lua
-- Unit Frames Z name sizing telemetry (/scoot debug ufzname, alias ufzn)
--
-- A UFZ name is sized by a blind fit that nothing can read back: RunBlindFit
-- measures the string on off-screen rulers through SetAlphaGradient and hands
-- the engine a point size. Every outcome is already recorded on the instance and
-- none of it was visible, so a name drawn at the wrong size had no way to say
-- which of the three outcomes produced it:
--
--   [fit <tier>@<size>]      the fit landed
--   [fit overflow@<size>]    nothing in range fits; rendered at the floor and
--                            left to ellipsize
--   [fit FALLBACK: <reason>] the oracle failed; rendered at cfg.nameSize, the
--                            un-shrunk ceiling, which on screen looks exactly
--                            like a name that was never resized
--
-- Target of Target is the row this was written for. It receives no unit events,
-- so its name refreshes only on PLAYER_TARGET_CHANGED, UNIT_TARGET filtered to
-- "target", and OnShow; the 0.25s poll deliberately never touches a name
-- (engine.lua, the poll block). A ToT whose name was not resolvable when those
-- fired gets no later correction, so "the fit landed on a stale subject" and
-- "the fit fell back" are different bugs behind one symptom. The verdict, the
-- sequence counter and the recorded derivation separate them.
--
-- Read-only except `refit`, which re-runs the engine's own refreshName.
--------------------------------------------------------------------------------

local addonName, addon = ...

local function UFZ()
    return addon.UnitFramesZ
end

--------------------------------------------------------------------------------
-- Secret-safe formatting
--------------------------------------------------------------------------------

-- type() then issecretvalue() then use: every getter below can meet a FontString
-- holding a secret name, where GetWidth and its neighbours return secrets.
local function safe(v)
    if v == nil then return "-" end
    if issecretvalue and issecretvalue(v) then return "<SECRET>" end
    if type(v) == "number" then
        if v == math.floor(v) then return tostring(v) end
        return string.format("%.2f", v)
    end
    return tostring(v)
end

-- A widget getter rendered straight to its display string, so a secret return
-- announces itself instead of vanishing into a nil.
local function probe(obj, method)
    if not obj then return "-" end
    local fn = obj[method]
    if type(fn) ~= "function" then return "-" end
    local ok, v = pcall(fn, obj)
    if not ok then return "err" end
    return safe(v)
end

--------------------------------------------------------------------------------
-- State dump
--------------------------------------------------------------------------------

-- The whole derivation: F is the character count the oracle read, spaces the
-- break count from the two squeezed rulers, and FTag the reason
-- a count came back unusable (SECRET, saturated, nonbool, err, noAPI).
local function pushFit(push, st)
    if not st then
        push("    fit     (none recorded: no fit has landed on this instance)")
        return
    end
    push("    fit     tier=%s size=%s lines=%s budget=%s   range=%s..%s step=%s",
        safe(st.tier), safe(st.size), safe(st.lines), safe(st.budget),
        safe(st.lo), safe(st.hi), safe(st.step))
    push("            F=%s spaces=%s (A=%s B=%s) FTag=%s   calls=%s frames=%s",
        safe(st.F), safe(st.spaces), safe(st.spacesA), safe(st.spacesB),
        safe(st.FTag), safe(st.calls), safe(st.frames))
    if st.reason then
        push("            reason=%s", safe(st.reason))
    end
end

local function dumpState(z)
    local lines, push = addon.DebugLines()

    push("=== Unit Frames Z: name sizing ===")
    push("")
    push("In combat: %s", tostring(InCombatLockdown and InCombatLockdown() or false))
    local okR, restricted = pcall(function()
        return C_Secrets and C_Secrets.HasSecretRestrictions and C_Secrets.HasSecretRestrictions()
    end)
    push("Secret restrictions: %s", okR and safe(restricted) or "unknown")
    push("")
    push("Verdict key:")
    push("  [fit <tier>@<size>]      the fit landed")
    push("  [fit overflow@<size>]    nothing in range fits; floor plus ellipsis")
    push("  [fit FALLBACK: <reason>] oracle failed; drawn at the ceiling, unshrunk")
    push("")

    local keys = {}
    for frameKey in pairs(z._instances or {}) do keys[#keys + 1] = frameKey end
    table.sort(keys)
    if #keys == 0 then
        push("(no UFZ instances exist)")
    end

    for _, frameKey in ipairs(keys) do
        local inst = z._instances[frameKey]
        local cfg = inst.cfg or {}
        push("[%s] unit=%s shown=%s visible=%s compact=%s poll=%s",
            tostring(frameKey), tostring(inst.unit),
            probe(inst.frame, "IsShown"), probe(inst.frame, "IsVisible"),
            tostring(inst.compact and true or false),
            tostring(inst.poll and true or false))
        push("    config  fit=%s ceiling=%s floor=%s box=%sx%s face=%s style=%s",
            tostring(cfg.nameFit and true or false),
            safe(cfg.nameSize), safe(cfg.nameMinSize),
            safe(cfg.nameMaxWidth), safe(cfg.nameMaxLines),
            safe(cfg.nameFace), safe(cfg.nameStyle))
        -- applied is the size the font carries; a nil with fit on means no
        -- fit has landed and the name is drawn at the plain ceiling. alpha 0 is
        -- a hold that was never released, which is a different failure from a
        -- wrong size and reads the same way in a screenshot of a blank row.
        push("    state   applied=%s seq=%s alpha=%s ink=%s pool=%s",
            safe(inst.nameFitSize), safe(inst.nameFitSeq),
            probe(inst.nameFS, "GetAlpha"),
            safe(inst.nameInkWidth), safe(inst.poolKey))
        push("    verdict %s", safe(inst.last and inst.last.name))
        pushFit(push, inst.lastNameFit)
        push("")
    end

    push("--- Commands ---")
    push("/scoot debug ufzname         (this dump)")
    push("/scoot debug ufzname refit   (re-run refreshName on every instance)")

    addon.DebugShowWindow("Unit Frames Z Names", lines)
end

--------------------------------------------------------------------------------
-- Forced refit
--------------------------------------------------------------------------------

-- The one write in this file, and the test that splits the two hypotheses: if a
-- forced refit sizes a name the live path left at the ceiling, the fit works and
-- the trigger was missing; if it falls back again, the oracle is the problem.
local function refit(z)
    if not z._RefreshName then
        addon.DebugShowWindow("Unit Frames Z Names",
            "UFZ._RefreshName is not available; nothing was refit.")
        return
    end
    local n = 0
    for _, inst in pairs(z._instances or {}) do
        -- hold: keep the current picture up rather than blanking every name on
        -- screen for a diagnostic.
        z._RefreshName(inst, true)
        n = n + 1
    end
    addon.DebugShowWindow("Unit Frames Z Names", string.format(
        "Re-ran refreshName on %d instance(s).\n\n"
        .. "A fit lands two deferred frames later, so run the plain command again "
        .. "to read the result.\n\n"
        .. "If a name the live path left at its ceiling now carries a real "
        .. "[fit tier@size], the fit itself is sound and the miss was a missing "
        .. "refresh trigger. If the verdict is FALLBACK again, read FTag: that is "
        .. "the oracle refusing, not the trigger.", n))
end

--------------------------------------------------------------------------------
-- Dispatch
--------------------------------------------------------------------------------

local Commands = addon.Commands

local function withZ(fn)
    return function(...)
        local z = UFZ()
        if not z then
            Commands.NotAvailable("Unit Frames Z")
            return
        end
        return fn(z, ...)
    end
end

addon:RegisterDebugCommand({
    name = "ufzname", aliases = { "ufzn" }, help = "Unit Frames Z name sizing",
    default = "state",
    verbs = {
        { word = "state", help = "per-instance fit verdict and derivation", fn = withZ(dumpState) },
        { word = "refit", help = "re-run refreshName on every instance", fn = withZ(refit) },
    },
})
