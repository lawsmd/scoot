--------------------------------------------------------------------------------
-- opacity.lua
-- State opacity resolution (refactor #23)
-- One resolver for the in-combat / with-target / out-of-combat opacity triple
-- that the CDM viewers, custom groups, PRD, ScootAuras, auras, action bars,
-- extra abilities, the damage meters, unit frame visibility, and Unit Frames Z
-- each wrote for themselves, plus the two player-state probes they open-coded.
-- The trigger side (addon:RefreshOpacityState in core/init.lua) is unchanged;
-- it asks DeclaresAny which components carry a triple.
-- Resolve works in percent space, clamps every value it reads, and converts
-- once, so a string, a nil, or a 250 in a profile never reaches SetAlpha.
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

-- Introspection for verification: /run ScootAddon.Opacity.Dump()
-- The two probes, then one line per configured component whose settings
-- declare a full key set: the raw values and the alpha and state Resolve
-- returns with default options (a site's own floors are not reflected).
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
    if addon.DebugShowWindow then
        addon.DebugShowWindow(("Opacity (%d components)"):format(#ids), lines)
    end
    return lines
end
