--------------------------------------------------------------------------------
-- core/debug/auracontainer.lua
-- AuraContainer pilot probe surface (/scoot debug auracontainer)
--
-- Drives the Target/Focus replacement-container pilot in
-- core/components/unitframes/auracontainer.lua and runs the in-game probe
-- battery that gates the 12.1 migration phases:
--   1. bounds-rect trio callable from addon context despite IsProtectedFunction?
--   2. inbound SetMaxBuffs(0) on Blizzard's container accepted, and does the
--      event-driven re-assert hold? (suppress maxzero)
--   3. GetChildren() on a Scoot-owned container as a button-handle fallback?
--   4. do plain aura instance IDs reach the public button surface? (probe
--      instance, plus the hover path records automatically)
--   5. isFromPlayerOrPlayerPet candidate-filter behavior? (filters on|off,
--      verified visually: only your own debuffs should remain)
--
-- All probe observations accumulate in the engine's results table and are
-- shown by the state dump. Everything here is session-only; nothing persists.
--------------------------------------------------------------------------------

local addonName, addon = ...

local issecretvalue = _G.issecretvalue

local function AC()
    return addon.AuraContainers
end

--------------------------------------------------------------------------------
-- Probe implementations
--------------------------------------------------------------------------------

local function probeBoundsRect(push)
    local ac = AC()
    local scratch = CreateFrame("Frame", nil, UIParent)
    scratch:SetSize(10, 10)
    scratch:SetPoint("CENTER")

    local function tryCall(obj, label, method, ...)
        local fn = obj[method]
        if type(fn) ~= "function" then
            push(("  %s.%s: method missing"):format(label, method))
            return
        end
        local ok, err = pcall(fn, obj, ...)
        if ok then
            push(("  %s.%s: OK"):format(label, method))
            ac.SetResult("probe.bounds." .. label .. "." .. method, "ok")
        else
            push(("  %s.%s: FAILED (%s)"):format(label, method, ac.SafeToString(err)))
            ac.SetResult("probe.bounds." .. label .. "." .. method, "FAILED: " .. ac.SafeToString(err))
        end
    end

    push("Bounds-rect trio on a plain Scoot frame:")
    tryCall(scratch, "frame", "SetCollapsesLayout", true)
    tryCall(scratch, "frame", "SetIgnoringChildrenForBounds", true)
    tryCall(scratch, "frame", "ResizeToBoundsRect")
    scratch:Hide()

    local entry = ac.containers.Target or ac.containers.Focus
    local button = entry and entry.buttons and entry.buttons[1]
    if button then
        push("Bounds-rect trio on an engine-created aura button:")
        tryCall(button, "button", "SetCollapsesLayout", true)
        tryCall(button, "button", "SetIgnoringChildrenForBounds", true)
        tryCall(button, "button", "ResizeToBoundsRect")
        -- Leave layout flags off so the pilot's flow layout is unaffected.
        pcall(function() button:SetCollapsesLayout(false) end)
        pcall(function() button:SetIgnoringChildrenForBounds(false) end)
    else
        push("No aura button available (run 'start' first) so the button half was skipped.")
    end
end

local function probeChildren(push)
    local ac = AC()
    local any = false
    for unitKey, entry in pairs(ac.containers) do
        any = true
        local results = { pcall(entry.container.GetChildren, entry.container) }
        local ok = results[1]
        if not ok then
            push(("  %s: GetChildren FAILED (%s)"):format(unitKey, ac.SafeToString(results[2])))
            ac.SetResult("probe.children." .. unitKey, "FAILED: " .. ac.SafeToString(results[2]))
        else
            local count = #results - 1
            local secretCount, frameCount = 0, 0
            for i = 2, #results do
                local child = results[i]
                if issecretvalue and issecretvalue(child) then
                    secretCount = secretCount + 1
                elseif type(child) == "table" then
                    frameCount = frameCount + 1
                end
            end
            local summary = ("returned %d children (%d frame handles, %d secret); initializeFrame saw %d buttons"):format(
                count, frameCount, secretCount, entry.buttonCount or 0)
            push(("  %s: %s"):format(unitKey, summary))
            ac.SetResult("probe.children." .. unitKey, summary)
        end
    end
    if not any then
        push("  No containers built (run 'start' first).")
    end
end

local function probeInstance(push)
    local ac = AC()
    local any = false
    for unitKey, entry in pairs(ac.containers) do
        any = true
        local missing, errored, secret, plain, empty = 0, 0, 0, 0, 0
        local sampleIID = nil
        for _, button in ipairs(entry.buttons) do
            local fn = button.GetAuraInstance
            if type(fn) ~= "function" then
                missing = missing + 1
            else
                local ok, unitToken, auraData = pcall(fn, button)
                if not ok then
                    errored = errored + 1
                elseif issecretvalue and (issecretvalue(unitToken) or issecretvalue(auraData)) then
                    secret = secret + 1
                elseif type(auraData) == "table" then
                    local iid = auraData.auraInstanceID
                    if issecretvalue and issecretvalue(iid) then
                        secret = secret + 1
                    elseif iid then
                        plain = plain + 1
                        sampleIID = sampleIID or iid
                    else
                        empty = empty + 1
                    end
                else
                    empty = empty + 1
                end
            end
        end
        local summary = ("%d buttons: %d plain instance IDs, %d unassigned, %d secret, %d errored, %d method-missing%s"):format(
            #entry.buttons, plain, empty, secret, errored, missing,
            sampleIID and (" (sample iid " .. tostring(sampleIID) .. ")") or "")
        push(("  %s: %s"):format(unitKey, summary))
        ac.SetResult("probe.instance." .. unitKey, summary)
    end
    if not any then
        push("  No containers built (run 'start' first).")
    end
end

local function probeFilters(push, enable)
    local ac = AC()
    local filters = enable and { isFromPlayerOrPlayerPet = true } or {}
    local any = false
    for unitKey, entry in pairs(ac.containers) do
        any = true
        local ok, err = pcall(entry.container.SetAuraGroupCandidateFilters, entry.container, "Debuffs", filters)
        local verdict = ok and "ok" or ("FAILED: " .. ac.SafeToString(err))
        push(("  %s: SetAuraGroupCandidateFilters(Debuffs, isFromPlayerOrPlayerPet=%s): %s"):format(
            unitKey, tostring(enable), verdict))
        ac.SetResult("probe.filters." .. unitKey, ("isFromPlayerOrPlayerPet=%s %s"):format(tostring(enable), verdict))
    end
    if any and enable then
        push("")
        push("Visual check: the debuff row on Target/Focus should now show ONLY")
        push("debuffs you or your pet applied. Run 'filters off' to restore.")
    end
    if not any then
        push("  No containers built (run 'start' first).")
    end
end

--------------------------------------------------------------------------------
-- State dump
--------------------------------------------------------------------------------

local function dumpState()
    local ac = AC()
    local lines = {}
    local function push(s) table.insert(lines, s) end

    push("=== Aura Container Pilot ===")
    push("")
    push("Engine started: " .. tostring(ac.enabled))
    local inCombat = InCombatLockdown and InCombatLockdown() or false
    push("In combat: " .. tostring(inCombat))
    local secretFn = C_Secrets and C_Secrets.ShouldAurasBeSecret
    local okS, secretNow = pcall(function() return secretFn and secretFn() end)
    push("Auras secret now: " .. (okS and tostring(secretNow) or "unknown"))
    push("")

    for unitKey, entry in pairs(ac.containers) do
        push(("[%s] token=%s shown=%s buttons=%d suppression=%s%s"):format(
            unitKey, entry.unitToken,
            tostring(entry.container:IsShown()),
            entry.buttonCount or 0,
            ac.suppression[unitKey] or "off",
            ac.suppressionTouched[unitKey] and " (touched)" or ""))
    end
    if not next(ac.containers) then
        push("No containers built. Run: /scoot debug auracontainer start")
    end
    push("")

    push("--- Recorded observations ---")
    local keys = {}
    for k in pairs(ac.results) do table.insert(keys, k) end
    table.sort(keys)
    if #keys == 0 then
        push("(none yet)")
    else
        for _, k in ipairs(keys) do
            push(k .. " = " .. tostring(ac.results[k]))
        end
    end
    push("")

    push("--- Commands ---")
    push("/scoot debug auracontainer start|stop")
    push("/scoot debug auracontainer probes      (bounds trio + children + instance IDs)")
    push("/scoot debug auracontainer filters on|off")
    push("/scoot debug auracontainer suppress off|maxzero|alpha")
    push("/scoot debug auracontainer log")

    addon.DebugShowWindow("Aura Container Pilot", table.concat(lines, "\n"))
end

local function dumpLog()
    local ac = AC()
    local lines = {}
    local entries = {}
    for _, e in pairs(ac.log) do table.insert(entries, e) end
    table.sort(entries, function(a, b) return a.seq < b.seq end)
    for _, e in ipairs(entries) do
        table.insert(lines, ("%.2f #%d [%s] %s"):format(e.t or 0, e.seq, e.tag, e.detail))
    end
    if #lines == 0 then
        table.insert(lines, "(empty)")
    end
    addon.DebugShowWindow("Aura Container Log", table.concat(lines, "\n"))
end

--------------------------------------------------------------------------------
-- Dispatch
--------------------------------------------------------------------------------

local function DebugAuraContainer(sub, arg)
    local ac = AC()
    if not ac then
        addon.DebugShowWindow("Aura Container Pilot", "Aura container module not loaded.")
        return
    end

    sub = sub or ""

    if sub == "start" then
        local ok, msg = ac.Start()
        addon:Print("Aura containers: " .. msg .. (ok and "" or " (not started)"))
        return
    end

    if sub == "stop" then
        local _, msg = ac.Stop()
        addon:Print("Aura containers: " .. msg)
        return
    end

    if sub == "probes" then
        local lines = {}
        local function push(s) table.insert(lines, s) end
        push("=== Probe Battery ===")
        push("")
        probeBoundsRect(push)
        push("")
        push("GetChildren on Scoot-owned containers:")
        probeChildren(push)
        push("")
        push("Aura instance IDs on public buttons:")
        probeInstance(push)
        push("")
        push("Results are also recorded in the state dump.")
        addon.DebugShowWindow("Aura Container Probes", table.concat(lines, "\n"))
        return
    end

    if sub == "filters" then
        local lines = {}
        local function push(s) table.insert(lines, s) end
        push("=== Candidate Filter Probe ===")
        push("")
        probeFilters(push, arg == "on")
        addon.DebugShowWindow("Aura Container Probes", table.concat(lines, "\n"))
        return
    end

    if sub == "suppress" then
        local mode = arg
        if mode ~= "off" and mode ~= "maxzero" and mode ~= "alpha" then
            addon:Print("Usage: /scoot debug auracontainer suppress <off|maxzero|alpha>")
            return
        end
        ac.SetSuppressionAll(mode)
        addon:Print("Aura containers: suppression mode set to " .. mode .. " (see state dump for results)")
        return
    end

    if sub == "log" then
        dumpLog()
        return
    end

    dumpState()
end

addon:RegisterDebugCommand({
    name = "auracontainer", aliases = { "aurac" }, help = "12.1 aura container pilot",
    usage = { "auracontainer [start|stop|probes|filters|suppress|log]" },
    handler = function(sub, rest) DebugAuraContainer(sub, string.lower(rest[2] or "")) end,
})
