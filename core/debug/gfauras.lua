--------------------------------------------------------------------------------
-- core/debug/gfauras.lua
-- Group Frame aura tracking telemetry (/scoot debug gfauras, alias gfa)
--
-- Since the 12.1 port the tracked icons are AuraContainer slots, so there is
-- nothing to read back and confirm: a button's shown state is a secret, its
-- duration object is a secret, and aura presence must never be branched on.
-- What CAN be observed is whether each engine call succeeded and what the
-- filters were built from, which is what this surface reports.
--
-- The questions it exists to answer in game:
--   1. Did a container get built for each visible group frame, and is it
--      VISIBLE and ENABLED (the engine gates its event registrations on both,
--      so a shown container under a hidden host tracks nothing)?
--   2. Did every enabled spell get a slot, and did its initializeFrame wire?
--   3. What is in each slot's includeSpellIDs after the CDM expansion? A slot
--      matching nothing is nearly always a missing variant ID.
--   4. Is anything queued behind the structural gate, and is the gate closed
--      because of combat or because auras are secret? Those are not the same
--      condition and only one of them ends at PLAYER_REGEN_ENABLED.
--
-- Everything here is read-only except `refresh`, which re-runs the normal seam.
--------------------------------------------------------------------------------

local addonName, addon = ...

local function HA()
    return addon.AuraTracking
end

local function Engine()
    local ha = HA()
    return ha and ha.Engine
end

--------------------------------------------------------------------------------
-- State dump
--------------------------------------------------------------------------------

local function describeContainer(entry)
    local c = entry.container
    if not c then return "no container" end
    local okShown, shown = pcall(c.IsShown, c)
    -- IsVisible, not just IsShown: a container shown under a hidden host is
    -- tracking nothing at all, and that difference is the whole diagnosis when
    -- slots are built and wired but nothing ever paints.
    local okVis, visible = pcall(c.IsVisible, c)
    local okEnabled, enabled = pcall(c.IsEnabled, c)
    local okUnit, unit = pcall(c.GetUnit, c)
    return ("shown=%s visible=%s enabled=%s unit=%s"):format(
        okShown and tostring(shown) or "?",
        okVis and tostring(visible) or "?",
        okEnabled and tostring(enabled) or "?",
        okUnit and tostring(unit) or "?")
end

local function describeSlot(E, slot)
    local bits = {}
    table.insert(bits, ("      %s  key=%s"):format(
        tostring(HA().SPELL_NAMES and HA().SPELL_NAMES[slot.spellId] or slot.spellId), slot.key))
    table.insert(bits, ("        active=%s wired=%s button=%s anim=%s"):format(
        tostring(slot.active), tostring(slot.wired),
        slot.button and "yes" or "NO", tostring(slot.animId or "static")))
    table.insert(bits, ("        filters=%s"):format(tostring(slot.filterKey or "<retired>")))
    local wire = E._results["wire." .. slot.spellId]
    if wire and wire ~= "ok" then
        table.insert(bits, "        wire: " .. wire)
    end
    for key, value in pairs(E._results) do
        if key:find("^bind%." .. slot.spellId .. "%.") then
            table.insert(bits, "        " .. key .. " = " .. tostring(value))
        end
    end
    return table.concat(bits, "\n")
end

local function dumpState()
    local ha, E = HA(), Engine()
    local lines, push = addon.DebugLines()

    push("=== Group Frames: aura tracking (12.1 AuraContainer) ===")
    push("")

    local inCombat = InCombatLockdown and InCombatLockdown() or false
    local okSecret, secretNow = pcall(function()
        return addon.AurasSecretNow and addon.AurasSecretNow()
    end)
    push("In combat:            " .. tostring(inCombat))
    push("Auras secret:         " .. (okSecret and tostring(secretNow) or "probe failed"))
    push("Structural work OK:   " .. tostring(E.CanDoStructuralWork()))
    push("")

    local enabled = ha.EnabledSpellList()
    if #enabled == 0 then
        push("No auras enabled. Zero-Touch: nothing is built until one is.")
    else
        local names = {}
        for _, item in ipairs(enabled) do
            local cfg = item.config
            table.insert(names, ("%s (anchor=%s priority=%s style=%s sources=%s)"):format(
                tostring(ha.SPELL_NAMES and ha.SPELL_NAMES[item.spellId] or item.spellId),
                tostring(cfg.anchor or "BOTTOMRIGHT"),
                tostring(cfg.rank or 1),
                tostring(cfg.iconStyle or "spell"),
                cfg.trackAllSources and "all" or "player"))
        end
        push(("Enabled auras (%d):"):format(#enabled))
        for _, n in ipairs(names) do push("  " .. n) end
    end

    -- Enabled in the profile but filtered out of the layout. This is the one
    -- state that is invisible in the settings page, which shows one class tab
    -- at a time, and it used to be harmless: before positions were fixed an
    -- unreachable spell simply never drew. Now it would hold an empty slot.
    local live = {}
    for _, item in ipairs(enabled) do live[item.spellId] = true end
    local db = addon.db and addon.db.profile
    local spells = db and db.groupFrames and db.groupFrames.auraTracking
        and db.groupFrames.auraTracking.spells
    local filtered = {}
    if spells then
        for spellId, config in pairs(spells) do
            if config.enabled and not live[spellId] and ha.SPELL_REGISTRY_BY_ID[spellId] then
                table.insert(filtered, ("%s (%s, own casts only, this character is %s)"):format(
                    tostring(ha.SPELL_NAMES and ha.SPELL_NAMES[spellId] or spellId),
                    tostring(ha.SPELL_CLASS_BY_ID and ha.SPELL_CLASS_BY_ID[spellId] or "?"),
                    tostring(select(2, UnitClass("player")))))
            end
        end
    end
    if #filtered > 0 then
        push("")
        push(("Enabled but not tracked on this character (%d):"):format(#filtered))
        for _, n in ipairs(filtered) do push("  " .. n) end
    end
    push("")

    local queued = 0
    for _ in pairs(E._pending) do queued = queued + 1 end
    push("Queued frames:        " .. queued)
    push("")

    local count = 0
    E.ForEachEntry(function(frame, entry)
        count = count + 1
        local okName, name = pcall(frame.GetName, frame)
        if not okName or type(name) ~= "string" then name = "<unnamed>" end
        local okVis, vis = pcall(frame.IsVisible, frame)
        push(("--- %s  host=%s"):format(name, entry.host:GetName() or "?"))
        push(("    frame visible=%s  unit=%s  cachedHeight=%.1f"):format(
            okVis and tostring(vis) or "?", tostring(entry.unit), entry.frameHeight or 0))
        push("    container: " .. describeContainer(entry))
        local slotCount = 0
        for _, slot in pairs(entry.slots) do
            slotCount = slotCount + 1
            push(describeSlot(E, slot))
        end
        if slotCount == 0 then push("      (no slots)") end
    end)
    if count == 0 then
        push("No group frames tracked yet. Join a group, or run: /scoot debug gfauras refresh")
    end

    push("")
    push("Build results:")
    for key, value in pairs(E._results) do
        if key:find("^build%.") or key:find("^slot%.") then
            push(("  %-28s %s"):format(key, tostring(value)))
        end
    end

    addon.DebugShowWindow("Group Frame Aura Tracking", lines)
end

--------------------------------------------------------------------------------
-- Log dump
--------------------------------------------------------------------------------

local function dumpLog()
    local E = Engine()
    local rows = {}
    for _, item in pairs(E._log) do
        table.insert(rows, item)
    end
    table.sort(rows, function(a, b) return a.seq < b.seq end)

    local lines = { "=== Group Frame aura tracking: breadcrumbs ===", "" }
    if #rows == 0 then
        table.insert(lines, "(nothing recorded yet)")
    end
    for _, item in ipairs(rows) do
        table.insert(lines, ("[%7.1f] %-12s %s"):format(item.t, item.tag, tostring(item.detail)))
    end
    addon.DebugShowWindow("Group Frame Aura Tracking", lines)
end

--------------------------------------------------------------------------------
-- Entry point
--------------------------------------------------------------------------------

local function DebugGroupAuras(sub)
    local ha, E = HA(), Engine()
    if not ha or not E then
        addon.DebugShowWindow("Group Frame Aura Tracking", "Group aura tracking module not loaded.")
        return
    end

    if sub == "log" then
        dumpLog()
        return
    end

    if sub == "refresh" then
        ha.RefreshAllAuraDisplays()
        addon.DebugShowWindow("Group Frame Aura Tracking",
            ("Re-ran discovery and a full pass.\n\nStructural work allowed: %s\n\nRun the plain command for the resulting state.")
            :format(tostring(E.CanDoStructuralWork())))
        return
    end

    if sub == "filters" then
        local lines = { "=== Slot include sets (after CDM expansion) ===", "" }
        for _, item in ipairs(ha.EnabledSpellList()) do
            local include = addon.AuraIds.BuildIncludeSet(item.spellId,
                ha.SPELL_REGISTRY_BY_ID[item.spellId] and ha.SPELL_REGISTRY_BY_ID[item.spellId].linkedIds)
            local ids = {}
            for id in pairs(include) do table.insert(ids, id) end
            table.sort(ids)
            table.insert(lines, ("%s (%d)"):format(
                tostring(ha.SPELL_NAMES[item.spellId] or item.spellId), item.spellId))
            table.insert(lines, "   filter: " .. ha.SlotFilterString(item.spellId))
            table.insert(lines, "   ids:    " .. table.concat(ids, ", "))
            table.insert(lines, "")
        end
        if #lines == 2 then table.insert(lines, "(no auras enabled)") end
        addon.DebugShowWindow("Group Frame Aura Tracking", lines)
        return
    end

    dumpState()
end

addon:RegisterDebugCommand({
    name = "gfauras", aliases = { "gfa" }, help = "group frame aura tracking",
    usage = { "gfauras [log|filters|refresh]" },
    handler = function(sub) DebugGroupAuras(sub) end,
})
