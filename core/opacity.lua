--------------------------------------------------------------------------------
-- opacity.lua
-- State opacity resolution (refactor #23)
-- One resolver for the in-combat / with-target / out-of-combat opacity triple
-- that the CDM viewers, custom groups, PRD, ScootAuras, auras, action bars,
-- extra abilities, the damage meters, unit frame visibility, and Unit Frames Z
-- each wrote for themselves, plus the two player-state probes they open-coded.
-- The component walk is RefreshComponents below. Scoot's trigger,
-- addon:RefreshOpacityState in core/init.lua, runs its unit frame lines and
-- then calls it; Camelot's host wires it to the same edges.
-- Resolve works in percent space, clamps every value it reads, and converts
-- once, so a string, a nil, or a 250 in a profile never reaches SetAlpha.
-- Fade carries a resolved value to the frame over the Dynamic Layouts
-- transition time where that engine is loaded ("The state fade", below).
--------------------------------------------------------------------------------

local addonName, addon = ...

addon.Opacity = addon.Opacity or {}
local Opacity = addon.Opacity

-- The setting names each storage dialect uses for the three states. A site
-- passes one of these to Resolve; the settings composite (AddStateOpacityBlock)
-- takes the same table as its field-to-key map.
local Keys = {
    Plain      = { combat = "opacity",         ooc = "opacityOutOfCombat",    target = "opacityWithTarget" },
    InCombat   = { combat = "opacityInCombat", ooc = "opacityOutOfCombat",    target = "opacityWithTarget" },
    Bar        = { combat = "barOpacity",      ooc = "barOpacityOutOfCombat", target = "barOpacityWithTarget" },
    -- The damage meters: an Edit Mode combat value and an addon out-of-combat
    -- value, no target state.
    CombatOnly = { combat = "opacity",         ooc = "opacityOutOfCombat" },
}
for _, set in pairs(Keys) do
    table.freeze(set)
end
table.freeze(Keys)
Opacity.Keys = Keys

-- Supersets first, so KeysFor reports the fullest dialect a component declares.
local KEY_SET_ORDER = { "InCombat", "Bar", "Plain", "CombatOnly" }

-- The key set whose every name a settings table declares, or nil.
function Opacity.KeysFor(settings)
    if type(settings) ~= "table" then return nil end
    for _, name in ipairs(KEY_SET_ORDER) do
        local set = Keys[name]
        local all = true
        for _, key in pairs(set) do
            if settings[key] == nil then
                all = false
                break
            end
        end
        if all then return set end
    end
    return nil
end

-- True when a settings table declares any catalog key. The dispatcher's gate:
-- a component with only a combat value (the PRD frame, the objective tracker's
-- background) still refreshes on a combat edge.
function Opacity.DeclaresAny(settings)
    if type(settings) ~= "table" then return false end
    for _, set in pairs(Keys) do
        for _, key in pairs(set) do
            if settings[key] ~= nil then return true end
        end
    end
    return false
end

-- True when the table sets any key of one given set. The narrow test for a
-- config table that also carries other dialects' keys (a per-unit table holds
-- the bar triple beside the frame triple).
function Opacity.DeclaresSet(settings, keys)
    if type(settings) ~= "table" or type(keys) ~= "table" then return false end
    for _, key in pairs(keys) do
        if settings[key] ~= nil then return true end
    end
    return false
end

-- Player state probes. InCombat is lockdown OR the unit flag: the regen events
-- that drive every refresh flip with lockdown, and the flag covers the pet
-- edge. HasTarget follows the Unit Frames Z doctrine: only a readable plain
-- true counts. UnitExists can throw or return a secret from a tainted context
-- (12.x), and boolean-testing a secret throws; both read as no target.
function Opacity.InCombat()
    if InCombatLockdown() then return true end
    if UnitAffectingCombat("player") then return true end
    return false
end

function Opacity.HasTarget()
    local ok, exists = pcall(UnitExists, "target")
    if not ok then return false end
    if issecretvalue and issecretvalue(exists) then return false end
    return exists == true
end

-- tonumber, floor, cap 100. A nil or non-numeric value stays nil so the
-- resolver can tell unset from 0.
local function clampPercent(value, floor)
    local v = tonumber(value)
    if v == nil then return nil end
    if v < floor then
        v = floor
    elseif v > 100 then
        v = 100
    end
    return v
end

local EMPTY = {}

-- alpha, state = Opacity.Resolve(db, keys, opts)
-- db    any table holding the keys (component.db, a tracker db, a unit cfg);
--       nil reads as empty.
-- keys  one of Opacity.Keys, or { combat =, ooc =, target = } with ooc or
--       target omitted for a two-state site.
-- opts  nil, or:
--   combatMin    percent floor on the combat value (default 0)
--   min          percent floor on the ooc and target values (default 0)
--   fallback     "combat": a missing ooc or target value reads as the clamped
--                combat value (default: 100)
--   alphaFloor   final floor in alpha space (default 0)
--   probeTarget  "whenSet": probe the target only when db[keys.target] ~= nil
--                (default: always)
--   inCombat, hasTarget  booleans that replace the probes when not nil (Dump)
-- Returns alpha in 0..1 and the state that won: "combat", "target", or "ooc".
function Opacity.Resolve(db, keys, opts)
    db = db or EMPTY
    opts = opts or EMPTY
    local combatMin = opts.combatMin or 0
    local minV = opts.min or 0

    local combatV = clampPercent(db[keys.combat], combatMin) or clampPercent(100, combatMin)
    local fb = (opts.fallback == "combat") and combatV or 100
    local oocV = keys.ooc and clampPercent(db[keys.ooc], minV) or nil
    if oocV == nil then oocV = clampPercent(fb, minV) end
    local targetSet = keys.target ~= nil and db[keys.target] ~= nil
    local targetV = targetSet and clampPercent(db[keys.target], minV) or nil
    if targetV == nil then targetV = clampPercent(fb, minV) end

    local inCombat = opts.inCombat
    if inCombat == nil then inCombat = Opacity.InCombat() end
    local hasTarget = false
    if keys.target ~= nil and (opts.probeTarget ~= "whenSet" or targetSet) then
        hasTarget = opts.hasTarget
        if hasTarget == nil then hasTarget = Opacity.HasTarget() end
    end

    -- Combat, then target, then out of combat: the one order every site uses.
    local pct, state
    if inCombat then
        pct, state = combatV, "combat"
    elseif hasTarget then
        pct, state = targetV, "target"
    else
        pct, state = oocV, "ooc"
    end

    local alpha = pct / 100
    if alpha > 1 then alpha = 1 end
    local alphaFloor = opts.alphaFloor or 0
    if alpha < alphaFloor then alpha = alphaFloor end
    return alpha, state
end

-- The component walk behind the triple: every configured component whose
-- settings declare a state opacity key (or the objective tracker's compound
-- key) gets RefreshOpacity when it defines one and ApplyStyling otherwise,
-- each inside pcall. Unconfigured components are skipped: the zero-touch gate
-- belongs to this styling site, not to event delivery. SetAlpha is
-- unprotected, so the walk runs in combat.
function Opacity.RefreshComponents()
    for _, component in pairs(addon.Components or EMPTY) do
        if not addon.IsComponentUnconfigured(component)
            and (component.RefreshOpacity or component.ApplyStyling)
            and component.settings then
            local hasOpacity = Opacity.DeclaresAny(component.settings) or
                component.settings.opacityInInstanceCombat
            if hasOpacity then
                if component.RefreshOpacity then
                    pcall(component.RefreshOpacity, component)
                else
                    pcall(component.ApplyStyling, component)
                end
            end
        end
    end
end

--------------------------------------------------------------------------------
-- The state fade
--------------------------------------------------------------------------------
-- A change of state carries the alpha to its new value over the Dynamic
-- Layouts "when leaving" duration, and a change that leaves combat or a
-- target first waits out that panel's delay while the feature is on
-- (DL.FadeTiming, core/dynamiclayouts/engine.lua). Everything else is written
-- at once: the first value a key takes, a new value under the same state (a
-- slider, a profile switch), and any change to or from no state, which is how
-- a caller names Edit Mode, a mouseover reveal or a preview.
--
-- The engine is read at the moment of use: one host lists it and the other
-- does not, and both list this file. Without it Fade answers the alpha it was
-- handed, so every site writes as it did before the fade existed.

local RANK = { ooc = 0, target = 1, combat = 2 }
local fades = {} -- key -> { key, value, target, state, wait, onTick, tick }

local function Tweens()
    local DL = addon.DynamicLayouts
    if type(DL) ~= "table" or type(DL.Tween) ~= "table" then return nil end
    return DL.Tween
end

local function Transitions()
    local DL = addon.DynamicLayouts
    if not Tweens() or type(DL.FadeTiming) ~= "function" then return nil end
    return DL
end

local function always() return true end

local function writeFade(rec, value)
    rec.value = value
    if rec.onTick then
        rec.onTick(value)
    else
        rec.key:SetAlpha(value)
    end
end

local function cancelWait(rec)
    if not rec.wait then return end
    rec.wait.timer:Cancel()
    rec.wait = nil
end

-- At once: the value is the caller's to write, from Fade's return.
local function landFade(rec, alpha, state)
    local tweens = Tweens()
    if tweens then tweens.Cancel(rec) end
    rec.value, rec.target, rec.state = alpha, alpha, state
    return alpha
end

-- The record is the tween's id, so a fade never shares a clock with an
-- adapter's channels on the same frame.
local function startFade(rec, DL, alpha, state, seconds)
    rec.target, rec.state = alpha, state
    DL.Tween.Start(rec, {
        duration = seconds,
        legal = always,
        write = rec.tick,
        finish = rec.tick,
        channels = { opacity = { from = rec.value, to = alpha } },
    })
end

-- value = Opacity.Fade(key, alpha, state, onTick)
-- key     the frame, or any table that stands for one faded value
-- alpha   the value Resolve returned
-- state   the state Resolve returned, or nil for a value outside the triple
-- onTick  function(value), the writer for the ticks that follow; without one
--         the key is a frame and takes SetAlpha
-- Returns the value to write now: the alpha itself, or where a fade or a
-- wait stands. The caller writes it, so a site that multiplies the state
-- opacity into another alpha does so in its own writer.
function Opacity.Fade(key, alpha, state, onTick)
    local rec = fades[key]
    if not rec then
        rec = { key = key }
        rec.tick = function(_, value) writeFade(rec, value) end
        fades[key] = rec
    end
    rec.onTick = onTick

    local wait = rec.wait
    if wait then
        if wait.state == state and wait.alpha == alpha then return rec.value end
        cancelWait(rec)
        -- The value the wait was for changed under it: a setting.
        if wait.state == state then return landFade(rec, alpha, state) end
    end

    local from, to = RANK[rec.state], RANK[state]
    local DL = Transitions()
    if not DL or rec.value == nil or not from or not to then
        return landFade(rec, alpha, state)
    end
    if from == to then
        -- A second call on one edge, which leaves a fade in flight alone, or
        -- a setting.
        if rec.target == alpha then return rec.value end
        return landFade(rec, alpha, state)
    end
    if rec.target == alpha then
        rec.state = state
        return rec.value
    end

    local seconds, hold = DL.FadeTiming()
    if to < from and hold > 0 then
        local pending = { alpha = alpha, state = state }
        pending.timer = C_Timer.NewTimer(hold, function()
            if rec.wait ~= pending then return end
            rec.wait = nil
            local engine = Transitions()
            if engine then
                startFade(rec, engine, alpha, state, (engine.FadeTiming()))
            else
                writeFade(rec, landFade(rec, alpha, state))
            end
        end)
        rec.wait = pending
        return rec.value
    end
    startFade(rec, DL, alpha, state, seconds)
    return rec.value
end

--- Where a key's fade stands now, or nil for a key Fade never saw. For a
--- site that divides the state opacity out of another alpha.
function Opacity.FadeValue(key)
    local rec = fades[key]
    return rec and rec.value or nil
end

--- Drop a key: its fade and its wait end with no write. For a frame that
--- leaves the screen or changes hands.
function Opacity.FadeForget(key)
    local rec = fades[key]
    if not rec then return end
    cancelWait(rec)
    local tweens = Tweens()
    if tweens then tweens.Cancel(rec) end
    fades[key] = nil
end

local function fadeLabel(key)
    if type(key) == "table" and type(key.GetName) == "function" then
        local ok, name = pcall(key.GetName, key)
        if ok and type(name) == "string" then return name end
    end
    return tostring(key)
end

-- Introspection for verification: /run ScootAddon.Opacity.Dump()
-- The two probes, then one line per configured component whose settings
-- declare a full key set: the raw values and the alpha and state Resolve
-- returns with default options (a site's own floors are not reflected). Then
-- one line per key the state fade holds.
function Opacity.Dump()
    local inCombat, hasTarget = Opacity.InCombat(), Opacity.HasTarget()
    local lines = {
        ("inCombat: %s"):format(tostring(inCombat)),
        ("hasTarget: %s"):format(tostring(hasTarget)),
    }
    local ids = {}
    for id, component in pairs(addon.Components or EMPTY) do
        if component.settings and not addon.IsComponentUnconfigured(component)
            and Opacity.KeysFor(component.settings) then
            ids[#ids + 1] = id
        end
    end
    table.sort(ids)
    local probes = { inCombat = inCombat, hasTarget = hasTarget }
    for _, id in ipairs(ids) do
        local component = addon.Components[id]
        local keys = Opacity.KeysFor(component.settings)
        local db = component.db or EMPTY
        local alpha, state = Opacity.Resolve(db, keys, probes)
        lines[#lines + 1] = ("%s: combat=%s target=%s ooc=%s -> %.2f (%s)"):format(
            id,
            tostring(db[keys.combat]),
            tostring(keys.target and db[keys.target]),
            tostring(keys.ooc and db[keys.ooc]),
            alpha, state)
    end
    lines[#lines + 1] = ("components: %d"):format(#ids)
    local tweens = Tweens()
    local fadeLines = {}
    for key, rec in pairs(fades) do
        local note = ""
        if rec.wait then
            note = (", waiting for %s at %.2f"):format(rec.wait.state, rec.wait.alpha)
        elseif tweens and tweens.IsActive(rec) then
            note = ", fading"
        end
        fadeLines[#fadeLines + 1] = ("fade %s: %.2f -> %.2f (%s)%s"):format(
            fadeLabel(key), rec.value or 0, rec.target or 0, tostring(rec.state), note)
    end
    table.sort(fadeLines)
    for _, line in ipairs(fadeLines) do
        lines[#lines + 1] = line
    end
    if addon.DebugShowWindow then
        addon.DebugShowWindow(("Opacity (%d components)"):format(#ids), lines)
    end
    return lines
end
