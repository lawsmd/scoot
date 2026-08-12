--------------------------------------------------------------------------------
-- core/debug/ufzauras.lua
-- Unit Frames Z aura row telemetry (/scoot debug ufzauras, alias ufza)
--
-- The UFZ rows are Blizzard AuraContainer intrinsics since the 12.1 port, so
-- there is nothing to read back and confirm: container geometry is secret, the
-- button list is ours only because initializeFrame handed it to us, and aura
-- presence must never be branched on. What CAN be observed is whether each
-- engine call we made succeeded, which is what this surface reports.
--
-- The open corners this exists to settle in-game, none of which the slot-shaped
-- classauras port exercised:
--   1. topology B for GROUPS: does a self-sizing container render correctly
--      inside a scaled, alpha'd Scoot frame?
--   2. SetFlowLayout* / SetAuraGroup* acceptance from addon context (no
--      first-party consumer of the Custom* inbound layer exists in 12.1)
--   3. AddDispelTypeTexture options-table acceptance, and whether
--      showWithoutDispelType lands the red non-dispellable fallback
--   4. anchoring the debuff container to the secret-sized buff container
--   5. draw order of engine buttons against the HUD band and the click overlay
--
-- Everything here is read-only except `apply` and `kick`, which re-run the
-- normal seam entries. Nothing persists.
--------------------------------------------------------------------------------

local addonName, addon = ...

local function UFZ()
    return addon.UnitFramesZ
end

local function Auras()
    local z = UFZ()
    return z and z.Auras
end

--------------------------------------------------------------------------------
-- State dump
--------------------------------------------------------------------------------

local function describeContainer(entry)
    if not entry then return "not built" end
    local c = entry.container
    if not c then return "no container" end
    local okShown, shown = pcall(c.IsShown, c)
    -- IsVisible, not just IsShown: the engine gates its event registrations on
    -- IsVisible() and IsEnabled(), so a container that is shown under a hidden
    -- ancestor is tracking nothing at all. That difference is the whole
    -- diagnosis when a row is built and wired but paints nothing.
    local okVis, visible = pcall(c.IsVisible, c)
    local okEnabled, enabled = pcall(c.IsEnabled, c)
    return ("shown=%s visible=%s enabled=%s buttons=%d"):format(
        okShown and tostring(shown) or "?",
        okVis and tostring(visible) or "?",
        okEnabled and tostring(enabled) or "?",
        #(entry.buttons or {}))
end

local function dumpState()
    local z, A = UFZ(), Auras()
    local lines = {}
    local function push(s) table.insert(lines, s) end

    push("=== Unit Frames Z: aura rows (12.1 AuraContainer) ===")
    push("")

    local inCombat = InCombatLockdown and InCombatLockdown() or false
    push("In combat: " .. tostring(inCombat))
    local okSecret, secretNow = pcall(function()
        return addon.AurasSecretNow and addon.AurasSecretNow()
    end)
    push("Auras secret now: " .. (okSecret and tostring(secretNow) or "unknown"))
    push("Structural work allowed: " .. tostring(A.CanDoStructuralWork()))

    local queued = 0
    for _ in pairs(A._pendingStyle or {}) do queued = queued + 1 end
    push("Queued for the restriction-lift drain: " .. queued .. " instance(s)")
    push("")

    push("--- Instances ---")
    local any = false
    for frameKey, inst in pairs(z._instances or {}) do
        any = true
        local cfg = inst.cfg or {}
        push(("[%s] unit=%s preview=%s auraStandIn=%s"):format(
            tostring(frameKey), tostring(inst.unit),
            inst.previewActive and (inst.previewStandIn and "stand-in" or "live") or "no",
            tostring(inst.auraStandIn and true or false)))
        push(("    config  buffs=%s/%s/max %s   debuffs=%s/%s/max %s   onlyMine=%s tooltips=%s"):format(
            tostring(cfg.auraBuffsShow and true or false), tostring(cfg.auraBuffsLoc or "bottom"),
            tostring(cfg.auraBuffsMax or 16),
            tostring(cfg.auraDebuffsShow and true or false), tostring(cfg.auraDebuffsLoc or "bottom"),
            tostring(cfg.auraDebuffsMax or 8),
            tostring(cfg.auraOnlyPlayerBuffs and true or false),
            tostring(cfg.auraTooltips and true or false)))
        local containers = inst.auraContainers
        if not containers then
            push("    rows    (none built: zero-touch until a row is enabled)")
        else
            push("    Buffs   " .. describeContainer(containers.Buffs))
            push("    Debuffs " .. describeContainer(containers.Debuffs))
        end
    end
    if not any then
        push("(no UFZ instances exist)")
    end
    push("")

    push("--- Recorded observations ---")
    local keys = {}
    for k in pairs(A._results or {}) do table.insert(keys, k) end
    table.sort(keys)
    if #keys == 0 then
        push("(none yet: no container has been built this session)")
    else
        for _, k in ipairs(keys) do
            push(k .. " = " .. tostring(A._results[k]))
        end
    end
    push("")

    push("--- Commands ---")
    push("/scoot debug ufzauras          (this dump)")
    push("/scoot debug ufzauras log      (build/wire breadcrumb ring)")
    push("/scoot debug ufzauras apply    (force a full pass on every instance)")
    push("/scoot debug ufzauras kick     (force UpdateAllAuras on every container)")

    addon.DebugShowWindow("Unit Frames Z Auras", table.concat(lines, "\n"))
end

local function dumpLog()
    local A = Auras()
    local entries = {}
    for _, e in pairs(A._log or {}) do table.insert(entries, e) end
    table.sort(entries, function(a, b) return a.seq < b.seq end)

    local lines = {}
    for _, e in ipairs(entries) do
        table.insert(lines, ("%.2f #%d [%s] %s"):format(
            e.t or 0, e.seq, tostring(e.tag), tostring(e.detail)))
    end
    if #lines == 0 then
        table.insert(lines, "(empty)")
    end
    addon.DebugShowWindow("Unit Frames Z Aura Log", table.concat(lines, "\n"))
end

--------------------------------------------------------------------------------
-- Dispatch
--------------------------------------------------------------------------------

function addon.DebugUFZAuras(sub)
    local z, A = UFZ(), Auras()
    if not z or not A then
        addon.DebugShowWindow("Unit Frames Z Auras", "Unit Frames Z aura module not loaded.")
        return
    end

    if sub == "log" then
        dumpLog()
        return
    end

    if sub == "apply" then
        local n = 0
        for _, inst in pairs(z._instances or {}) do
            A.ApplyAll(inst)
            n = n + 1
        end
        addon.DebugShowWindow("Unit Frames Z Auras",
            ("Forced a full pass on %d instance(s).\n\nStructural work allowed: %s\n\nRun the plain command for the resulting state.")
            :format(n, tostring(A.CanDoStructuralWork())))
        return
    end

    if sub == "kick" then
        local n = 0
        for _, inst in pairs(z._instances or {}) do
            A.ForceRefresh(inst)
            n = n + 1
        end
        addon.DebugShowWindow("Unit Frames Z Auras",
            ("Kicked UpdateAllAuras on %d instance(s).\n\nThis is the retarget path: SetUnit early-outs when the token is unchanged, so a target swap only repopulates because of this call.")
            :format(n))
        return
    end

    dumpState()
end
