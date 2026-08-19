--------------------------------------------------------------------------------
-- core/debug/scootauras.lua
-- ScootAuras phase-0 probe battery (/scoot debug scootauras, alias sa)
--
-- Throwaway harness that gates the ScootAuras engine design. Every probe is a
-- Scoot-owned frame holding an AuraContainer wired slot-first, unit-last:
--   create -> SetSize -> AddAuraSlot -> SetUnit -> UpdateAllAuras
-- Unit assignment finalizes event registration against current content;
-- unit-first containers look fine out of combat and go event-dead in it.
--
-- Probes:
--   1. slot-first wiring updates through a full combat (player and target)
--   2. SetEnabled(false) parks a container; SetEnabled(true) revives it
--   3. a fresh container inside an already-used frame works beside a parked one
--   4. SetAuraSlotCandidateFilters live re-point (spell-edit path) + latency
--   5. SetAuraSlotFilterString re-point to "HELPFUL|HARMFUL" (park filter)
--   6. SetUnit re-call on a slot-bearing container (recycling optimization gate)
--   7. container cost at 10/25/50 (budget; decides whether a cap is needed)
--   8. duplicate same-spell probes both render
--
-- Observations accumulate in a results table shown by the state dump. Session
-- only; nothing persists and nothing here ships past phase 0.
--------------------------------------------------------------------------------

local addonName, addon = ...

local issecretvalue = _G.issecretvalue
local debugprofilestop = _G.debugprofilestop

local SA = {
    probes = {},        -- [id] = probe
    order = {},         -- creation order of probe ids
    count = 0,
    results = {},
    log = {},
    seq = 0,
}

local function SafeToString(v)
    if issecretvalue and issecretvalue(v) then return "<secret>" end
    local ok, s = pcall(tostring, v)
    return ok and s or "<unprintable>"
end

local function SetResult(key, value)
    SA.results[key] = value
end

local function Record(tag, detail)
    SA.seq = SA.seq + 1
    table.insert(SA.log, { t = GetTime(), seq = SA.seq, tag = tag, detail = detail or "" })
    if #SA.log > 200 then table.remove(SA.log, 1) end
end

local function GateClosed()
    if InCombatLockdown() then return "in combat" end
    if addon.AurasSecretNow and addon.AurasSecretNow() then return "aura restrictions active" end
    return nil
end

--------------------------------------------------------------------------------
-- Wiring
--------------------------------------------------------------------------------

-- All regions are descendants of the aura button; the engine's access stamp
-- covers them as a unit and the bindings stay legal afterward.
local function WireProbeButton(probe, centry, button)
    button:SetSize(40, 40)
    button:SetPoint("CENTER", centry.container, "CENTER", 0, 0)

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local dur = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    dur:SetPoint("TOP", button, "BOTTOM", 0, -2)

    local stacks = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    stacks:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)

    local okIcon, errIcon = pcall(button.SetIcon, button, icon)
    local okDur, errDur = pcall(button.SetDurationText, button, dur, {})
    local okCount, errCount = pcall(button.SetApplicationCount, button, stacks)

    SetResult(centry.key .. ".bind.icon", okIcon and "ok" or ("FAILED: " .. SafeToString(errIcon)))
    SetResult(centry.key .. ".bind.duration", okDur and "ok" or ("FAILED: " .. SafeToString(errDur)))
    SetResult(centry.key .. ".bind.count", okCount and "ok" or ("FAILED: " .. SafeToString(errCount)))
end

-- Creates and wires one AuraContainer inside the probe's frame, slot first,
-- unit last. Returns the container entry or nil plus an error string.
local function AttachContainer(probe, spellId, unit, kind)
    local index = #probe.containers + 1
    local key = probe.id .. ".c" .. index
    local t0 = debugprofilestop()

    local ok, container = pcall(CreateFrame, "AuraContainer", nil, probe.frame, "CustomAuraContainerTemplate")
    if not ok or not container then
        SetResult(key .. ".create", "FAILED: " .. SafeToString(container))
        Record("create-fail", key)
        return nil, "container creation failed: " .. SafeToString(container)
    end

    pcall(container.SetFrameLevel, container, probe.frame:GetFrameLevel() + 5)
    pcall(container.SetSize, container, 44, 44)
    -- Containers process only while shown and anchored; an unanchored one is
    -- silently dead.
    pcall(container.SetPoint, container, "CENTER", probe.frame, "CENTER", 0, 0)

    local centry = {
        key = key,
        slotKey = key .. ".slot",
        container = container,
        spellId = spellId,
        unit = unit,
        kind = kind,
        enabled = true,
    }

    local filter = (kind == "debuff") and "HARMFUL" or "HELPFUL"
    local slotOk, slotErr = pcall(container.AddAuraSlot, container, centry.slotKey, filter, {
        candidateFilters = { includeSpellIDs = { [spellId] = true } },
        initializeFrame = function(button)
            centry.button = button
            local wok, werr = pcall(WireProbeButton, probe, centry, button)
            centry.wired = wok and true or false
            SetResult(key .. ".wire", wok and "ok" or ("FAILED: " .. SafeToString(werr)))
        end,
    })
    if not slotOk then
        SetResult(key .. ".slot", "FAILED: " .. SafeToString(slotErr))
        Record("slot-fail", key)
        return nil, "AddAuraSlot failed: " .. SafeToString(slotErr)
    end

    local uok, uerr = pcall(container.SetUnit, container, unit)
    local kok, kerr = pcall(container.UpdateAllAuras, container)
    local ms = debugprofilestop() - t0

    SetResult(key .. ".create", string.format("ok in %.2f ms (slot=%s unit=%s kick=%s)",
        ms, "ok",
        uok and unit or ("FAILED: " .. SafeToString(uerr)),
        kok and "ok" or ("FAILED: " .. SafeToString(kerr))))
    Record("created", key .. " spell=" .. tostring(spellId) .. " unit=" .. unit .. " kind=" .. kind)

    table.insert(probe.containers, centry)
    probe.active = index
    return centry
end

--------------------------------------------------------------------------------
-- Retarget kicks (target/focus containers do not self-refresh)
--------------------------------------------------------------------------------

local kickFrame
local function EnsureKickFrame()
    if kickFrame then return end
    kickFrame = CreateFrame("Frame")
    kickFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
    kickFrame:RegisterEvent("PLAYER_FOCUS_CHANGED")
    kickFrame:SetScript("OnEvent", function(_, event)
        local unit = (event == "PLAYER_FOCUS_CHANGED") and "focus" or "target"
        for _, id in ipairs(SA.order) do
            local probe = SA.probes[id]
            if probe then
                for _, centry in ipairs(probe.containers) do
                    if centry.unit == unit and centry.enabled then
                        pcall(centry.container.UpdateAllAuras, centry.container)
                    end
                end
            end
        end
    end)
end

--------------------------------------------------------------------------------
-- Probe operations
--------------------------------------------------------------------------------

local PROBE_ANCHOR_X = -420
local PROBE_ANCHOR_Y = 240
local PROBE_STEP = 56
local PROBES_PER_COLUMN = 9

local function CreateProbe(spellId, unit, kind)
    local closed = GateClosed()
    if closed then return nil, "structural window closed (" .. closed .. "); run out of combat and outside restricted content" end

    EnsureKickFrame()
    SA.count = SA.count + 1
    local id = "p" .. SA.count

    local frame = CreateFrame("Frame", "ScootAurasProbe" .. SA.count, UIParent)
    frame:SetSize(44, 44)
    local column = math.floor((SA.count - 1) / PROBES_PER_COLUMN)
    local row = (SA.count - 1) % PROBES_PER_COLUMN
    frame:SetPoint("CENTER", UIParent, "CENTER", PROBE_ANCHOR_X + column * PROBE_STEP, PROBE_ANCHOR_Y - row * PROBE_STEP)
    if addon.Strata and addon.Strata.ApplyHUD then
        addon.Strata.ApplyHUD(frame, 25)
    end

    local label = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("RIGHT", frame, "LEFT", -4, 0)
    label:SetText(id)

    local probe = { id = id, frame = frame, containers = {} }
    SA.probes[id] = probe
    table.insert(SA.order, id)

    local centry, err = AttachContainer(probe, spellId, unit, kind)
    if not centry then return nil, err end
    return probe
end

local function ResolveProbe(arg)
    if not arg or arg == "" then return nil end
    local id = arg
    if not SA.probes[id] then id = "p" .. arg end
    return SA.probes[id]
end

local function ActiveEntry(probe)
    return probe and probe.containers[probe.active or 0] or nil
end

local function SetProbeEnabled(probe, enabled)
    local centry = ActiveEntry(probe)
    if not centry then return "no active container" end
    local ok, err = pcall(centry.container.SetEnabled, centry.container, enabled)
    centry.enabled = enabled and ok
    local verdict = ok and "ok" or ("FAILED: " .. SafeToString(err))
    SetResult(centry.key .. (enabled and ".revive" or ".park"), verdict)
    Record(enabled and "revive" or "park", centry.key .. " " .. verdict)
    return verdict
end

local function RepointSpell(probe, newSpellId)
    local centry = ActiveEntry(probe)
    if not centry then return "no active container" end
    local t0 = debugprofilestop()
    local ok, err = pcall(centry.container.SetAuraSlotCandidateFilters, centry.container, centry.slotKey,
        { includeSpellIDs = { [newSpellId] = true } })
    local ms = debugprofilestop() - t0
    local verdict
    if ok then
        centry.spellId = newSpellId
        verdict = string.format("ok in %.2f ms (call time; watch how fast the icon flips)", ms)
    else
        verdict = "FAILED: " .. SafeToString(err)
    end
    SetResult(centry.key .. ".repoint", verdict .. " -> " .. tostring(newSpellId))
    Record("repoint", centry.key .. " -> " .. tostring(newSpellId) .. " " .. verdict)
    return verdict
end

local function ParkFilter(probe)
    local centry = ActiveEntry(probe)
    if not centry then return "no active container" end
    if type(centry.container.SetAuraSlotFilterString) ~= "function" then
        SetResult(centry.key .. ".parkfilter", "method missing")
        return "SetAuraSlotFilterString missing on this build"
    end
    local ok, err = pcall(centry.container.SetAuraSlotFilterString, centry.container, centry.slotKey, "HELPFUL|HARMFUL")
    local verdict = ok and "ok (button should now stay empty forever)" or ("FAILED: " .. SafeToString(err))
    SetResult(centry.key .. ".parkfilter", verdict)
    Record("parkfilter", centry.key .. " " .. verdict)
    return verdict
end

local function ReUnit(probe, newUnit)
    local centry = ActiveEntry(probe)
    if not centry then return "no active container" end
    local ok, err = pcall(centry.container.SetUnit, centry.container, newUnit)
    local kok = pcall(centry.container.UpdateAllAuras, centry.container)
    local verdict
    if ok then
        centry.unit = newUnit
        verdict = "ok (kick=" .. tostring(kok) .. "); verify the display now tracks " .. newUnit
    else
        verdict = "FAILED: " .. SafeToString(err)
    end
    SetResult(centry.key .. ".reunit", verdict)
    Record("reunit", centry.key .. " -> " .. newUnit .. " " .. verdict)
    return verdict
end

local function FreshContainer(probe, spellId, unit, kind)
    local closed = GateClosed()
    if closed then return "structural window closed (" .. closed .. ")" end
    -- Park the current occupant first: the claim path always retires the old
    -- container rather than reusing it.
    local old = ActiveEntry(probe)
    if old and old.enabled then
        SetProbeEnabled(probe, false)
    end
    local centry, err = AttachContainer(probe, spellId, unit, kind)
    if not centry then return err end
    return "ok: container #" .. tostring(probe.active) .. " live beside " .. tostring(#probe.containers - 1) .. " parked"
end

local function RunBudget(count, spellId)
    local closed = GateClosed()
    if closed then return nil, "structural window closed (" .. closed .. ")" end
    local t0 = debugprofilestop()
    local made = 0
    for _ = 1, count do
        local probe = CreateProbe(spellId, "player", "buff")
        if not probe then break end
        made = made + 1
    end
    local ms = debugprofilestop() - t0
    local summary = string.format("%d containers in %.2f ms (%.2f ms each)", made, ms, made > 0 and (ms / made) or 0)
    SetResult("budget." .. count, summary)
    Record("budget", summary)
    return summary
end

local function ClearAll()
    for _, id in ipairs(SA.order) do
        local probe = SA.probes[id]
        if probe then
            for _, centry in ipairs(probe.containers) do
                pcall(centry.container.SetEnabled, centry.container, false)
                centry.enabled = false
            end
            probe.frame:Hide()
        end
    end
    Record("clear", "all probes parked and hidden (frames persist until reload)")
end

--------------------------------------------------------------------------------
-- Dumps
--------------------------------------------------------------------------------

local function DumpState()
    local lines = {}
    local function push(s) table.insert(lines, s) end

    push("=== ScootAuras Probe Battery ===")
    push("")
    push("In combat: " .. tostring(InCombatLockdown()))
    local secretNow = addon.AurasSecretNow and addon.AurasSecretNow()
    push("Aura restrictions active: " .. tostring(secretNow))
    push("")

    if #SA.order == 0 then
        push("No probes. Start with: /scoot debug sa create <spellId> [unit] [buff|debuff]")
    end
    for _, id in ipairs(SA.order) do
        local probe = SA.probes[id]
        if probe then
            push(("[%s] shown=%s containers=%d active=#%d"):format(
                id, tostring(probe.frame:IsShown()), #probe.containers, probe.active or 0))
            for i, centry in ipairs(probe.containers) do
                push(("    #%d spell=%s unit=%s kind=%s enabled=%s wired=%s"):format(
                    i, tostring(centry.spellId), centry.unit, centry.kind,
                    tostring(centry.enabled), tostring(centry.wired)))
            end
        end
    end
    push("")

    push("--- Recorded observations ---")
    local keys = {}
    for k in pairs(SA.results) do table.insert(keys, k) end
    table.sort(keys)
    if #keys == 0 then
        push("(none yet)")
    else
        for _, k in ipairs(keys) do
            push(k .. " = " .. tostring(SA.results[k]))
        end
    end
    push("")

    -- Pipes are doubled: a bare "|t" in display text parses as a texture escape.
    push("--- Commands (alias: sa) ---")
    push("/scoot debug scootauras create <spellId> [player||target||focus] [buff||debuff]")
    push("/scoot debug scootauras park <n> || revive <n>")
    push("/scoot debug scootauras fresh <n> <spellId> [unit] [kind]")
    push("/scoot debug scootauras repoint <n> <spellId>")
    push("/scoot debug scootauras parkfilter <n>")
    push("/scoot debug scootauras setunit <n> <unit>")
    push("/scoot debug scootauras budget <count> <spellId>")
    push("/scoot debug scootauras clear || log || state")
    push("Lifecycle commands: /scoot debug sa list")

    addon.DebugShowWindow("ScootAuras Probes", table.concat(lines, "\n"))
end

local function DumpLog()
    local lines = {}
    for _, e in ipairs(SA.log) do
        table.insert(lines, ("%.2f #%d [%s] %s"):format(e.t or 0, e.seq, e.tag, e.detail))
    end
    if #lines == 0 then lines[1] = "(empty)" end
    addon.DebugShowWindow("ScootAuras Probe Log", table.concat(lines, "\n"))
end

--------------------------------------------------------------------------------
-- Phase 1 lifecycle commands (drive the real ScootAuras API)
--------------------------------------------------------------------------------

local function LifecycleDump()
    local SAU = addon.ScootAuras
    local lines = {}
    local function push(s) table.insert(lines, s) end

    push("=== ScootAuras Lifecycle ===")
    push("")
    push("Module enabled: " .. tostring(SAU.IsModuleActive()))
    push("In combat: " .. tostring(InCombatLockdown()))
    push("Aura restrictions active: " .. tostring(addon.AurasSecretNow and addon.AurasSecretNow()))
    push("Engine initialized: " .. tostring(SAU.Engine.IsInitialized()))
    push("Pending queue: " .. tostring(SAU.Engine.HasPendingWork()))
    push("Current spec: " .. tostring(SAU.CurrentSpecID()))
    push("")

    local store = SAU.GetStore()
    local rows = SAU.SortedTrackers()
    if not store or not next(store.trackers or {}) then
        push("No trackers. Start with: /scoot debug sa add <spellId> [unit] [buff|debuff] [icon|bar|shape]")
    else
        local loaded, notLoaded = 0, 0
        push("--- Trackers (account-wide) ---")
        for _, row in ipairs(rows) do
            local t = row.tracker
            local active = SAU.IsTrackerActive(row.id, t)
            if active then loaded = loaded + 1 else notLoaded = notLoaded + 1 end
            push(("t%d '%s': spell=%s %s on %s as %s enabled=%s wired=%s loaded=%s"):format(
                row.id, tostring(t.name), tostring(t.spellId), t.kind, t.unit, t.shape,
                tostring(t.enabled), tostring(SAU.Engine.IsWired(row.id)), tostring(active)))
        end
        push(("(%d loaded / %d not loaded; see /scoot debug sa specs)"):format(loaded, notLoaded))
    end
    push("")

    push("--- Pool ---")
    if #SAU.Engine._pool == 0 then
        push("(empty)")
    end
    for _, entry in ipairs(SAU.Engine._pool) do
        push(("shell%d occupant=%s wired=[spell=%s unit=%s kind=%s] retired=%d lem=%s shown=%s grouped=%s"):format(
            entry.index, tostring(entry.occupantId), tostring(entry.wiredSpellId),
            tostring(entry.wiredUnit), tostring(entry.wiredKind), #entry.containers,
            tostring(entry.lemRegistered or false), tostring(entry.shell:IsShown()),
            tostring(entry.grouped or false)))
    end
    push("")

    if SAU.Groups then
        push("--- Groups (profile) ---")
        local groupRows = SAU.SortedGroups()
        if #groupRows == 0 then
            push("(none)")
        end
        for _, row in ipairs(groupRows) do
            local g = row.group
            local s = g.settings or {}
            push(("g%d '%s': grow=%s spacing=%s members=[%s] owner=%s"):format(
                row.id, tostring(g.name), tostring(s.grow), tostring(s.spacing),
                table.concat(g.memberOrder or {}, ","), tostring(g.owner)))
        end
        push("")
        push("--- Group pool ---")
        if #SAU.Groups._pool == 0 then
            push("(empty)")
        end
        for _, entry in ipairs(SAU.Groups._pool) do
            push(("group%d occupant=%s lem=%s shown=%s"):format(
                entry.index, tostring(entry.occupantId),
                tostring(entry.lemRegistered or false), tostring(entry.frame:IsShown())))
        end
        push("Group parenting queued: " .. tostring(SAU.Groups.HasPendingWork()))
        push("")
    end

    push("--- Engine observations ---")
    local keys = {}
    for k in pairs(SAU.Engine._results) do table.insert(keys, k) end
    table.sort(keys)
    if #keys == 0 then push("(none yet)") end
    for _, k in ipairs(keys) do
        push(k .. " = " .. tostring(SAU.Engine._results[k]))
    end
    push("")

    -- Pipes are doubled: a bare "|t" in display text parses as a texture escape.
    push("--- Commands (alias: sa) ---")
    push("/scoot debug sa add <spellId> [player||group||target||focus] [buff||debuff||missingbuff] [icon||bar||shape||text||icontext]")
    push("/scoot debug sa del <id> || enable <id> || disable <id>")
    push("/scoot debug sa edit [id]  (editor: existing tracker, or fresh draft)")
    push("/scoot debug sa gadd [name] || gdel <gid> (delete keeps members)")
    push("/scoot debug sa join <id> <gid> [index] || leave <id>")
    push("/scoot debug sa reconcile || flush || list")
    push("/scoot debug sa specs  (per record: stored specs, current spec, gate verdict)")
    push("/scoot debug sa methods <id>  (button binding inventory)")
    push("/scoot debug sa missing <id>  (missing-buff reminder: gate container, clip, secrecy, group scan)")
    push("/scoot debug sa spell <N||spellId>  (N from a tN row above; include set, CDM entries, picker cell, live aura check)")
    push("/scoot debug sa catalog  (every picker cell: shown name, stored base)")
    push("/scoot debug sa cadence <id||spellId> [on || off || set <0..1> || alpha <0..1> || mirror <y||off>]  (cadence lock record / probes)")

    addon.DebugShowWindow("ScootAuras Lifecycle", table.concat(lines, "\n"))
end

-- Why a tracker does or does not load in the current spec. This mirrors
-- SpecAllows branch by branch, so the two must move together.
local function SpecsDump()
    local SAU = addon.ScootAuras
    local lines = {}
    local function push(str) table.insert(lines, str) end

    local current = SAU.CurrentSpecID()
    push("=== ScootAuras Spec Gate ===")
    push("")
    push("Current spec: " .. tostring(current)
        .. (current and (" (" .. SAU.SpecName(current) .. ")") or ""))
    local named = {}
    for _, id in ipairs(SAU.DefaultSpecsForPlayer()) do
        table.insert(named, id .. "=" .. SAU.SpecName(id))
    end
    push("This class: " .. ((#named > 0) and table.concat(named, ", ") or "(not loaded)"))
    push("")

    local function reason(record)
        local specs = record and record.specs
        if record and record._pendingSpecClass ~= nil then
            return "migration stamp pending (" .. tostring(record._pendingSpecClass) .. ")"
        end
        if type(specs) ~= "table" or #specs == 0 then return "no specs (loads nowhere)" end
        if not current then return "current spec unknown" end
        for _, id in ipairs(specs) do
            if id == current then return "match" end
        end
        return "blocked"
    end

    push("--- Trackers ---")
    local trackerIds = {}
    for id in pairs(SAU.AllTrackers()) do table.insert(trackerIds, id) end
    table.sort(trackerIds)
    if #trackerIds == 0 then push("(none)") end
    for _, id in ipairs(trackerIds) do
        local t = SAU.GetTracker(id)
        push(("t%d '%s' specs=%s -> %s | enabled=%s group=%s active=%s"):format(
            id, tostring(t.name), SAU.DescribeSpecs(t.specs) or "none", reason(t),
            tostring(t.enabled), tostring(t.groupId),
            tostring(SAU.IsTrackerActive(id, t))))
    end

    push("")
    push("--- Groups ---")
    local groupIds = {}
    for gid in pairs(SAU.AllGroups()) do table.insert(groupIds, gid) end
    table.sort(groupIds)
    if #groupIds == 0 then push("(none)") end
    for _, gid in ipairs(groupIds) do
        local g = SAU.GetGroup(gid)
        push(("g%d '%s' specs=%s -> %s | members=%d"):format(
            gid, tostring(g.name), SAU.DescribeSpecs(g.specs) or "none", reason(g),
            #(g.memberOrder or {})))
    end

    addon.DebugShowWindow("ScootAuras Spec Gate", table.concat(lines, "\n"))
end

-- Binding-method inventory on a live tracker's engine button; gates the Shape
-- drain-swipe design (SetDurationCooldown) without guesswork.
local function DumpButtonMethods(trackerId)
    local entry = addon.ScootAuras.Engine._byTracker[trackerId]
    if not entry or not entry.button then
        addon:Print("Tracker t" .. tostring(trackerId) .. " has no wired button.")
        return
    end
    local names = {
        "SetIcon", "ClearIcon", "SetDurationText", "ClearDurationText",
        "SetDurationBar", "ClearDurationBar", "SetDurationCooldown", "ClearDurationCooldown",
        "SetApplicationCount", "ClearApplicationCount", "SetApplicationBar", "ClearApplicationBar",
        "SetSpellName", "ClearSpellName", "SetAuraBorder", "ClearAuraBorder",
        "SetDispelTypeText", "ClearDispelTypeText",
    }
    local lines = { "=== Engine button methods (t" .. trackerId .. ") ===", "" }
    for _, n in ipairs(names) do
        table.insert(lines, n .. " = " .. type(entry.button[n]))
    end
    addon.DebugShowWindow("ScootAuras Button Methods", table.concat(lines, "\n"))
end

--------------------------------------------------------------------------------
-- Spell resolution: what a tracker (or a bare spell ID) expands to, and every
-- CDM entry that touches those IDs. Built for the Flame Shock case, where the
-- CDM keys its entries on a hidden base spell (470411) and the real debuff
-- (188389) is only a linked spell on some of them.
--------------------------------------------------------------------------------

local function PlainNum(v)
    if type(v) == "number" and not issecretvalue(v) and v > 0 then return v end
    return nil
end

local function SpellLabel(spellId)
    local ok, name = pcall(C_Spell.GetSpellName, spellId)
    if ok and type(name) == "string" and not issecretvalue(name) and name ~= "" then
        return name
    end
    return "?"
end

local function CategoryName(value)
    local enum = Enum and Enum.CooldownViewerCategory
    if type(enum) == "table" then
        for k, v in pairs(enum) do
            if v == value then return k end
        end
    end
    return tostring(value)
end

-- Every CDM entry (all categories, unlearned included) as plain fields.
local function ScanCDMEntries()
    local out = {}
    local enum = Enum and Enum.CooldownViewerCategory
    if not enum or not C_CooldownViewer
        or not C_CooldownViewer.GetCooldownViewerCategorySet
        or not C_CooldownViewer.GetCooldownViewerCooldownInfo then
        return out
    end
    local cats = {}
    for _, v in pairs(enum) do
        if type(v) == "number" then table.insert(cats, v) end
    end
    table.sort(cats)
    for _, cat in ipairs(cats) do
        local ok, ids = pcall(C_CooldownViewer.GetCooldownViewerCategorySet, cat, true)
        if ok and type(ids) == "table" and not issecretvalue(ids) then
            for _, cooldownID in ipairs(ids) do
                if not issecretvalue(cooldownID) then
                    local iok, info = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, cooldownID)
                    if iok and type(info) == "table" and not issecretvalue(info) then
                        local linked = {}
                        if type(info.linkedSpellIDs) == "table" and not issecretvalue(info.linkedSpellIDs) then
                            for _, lid in ipairs(info.linkedSpellIDs) do
                                lid = PlainNum(lid)
                                if lid then table.insert(linked, lid) end
                            end
                        end
                        table.insert(out, {
                            category = cat,
                            cooldownID = cooldownID,
                            base = PlainNum(info.spellID),
                            override = PlainNum(info.overrideSpellID),
                            tooltip = PlainNum(info.overrideTooltipSpellID),
                            linked = linked,
                            isKnown = info.isKnown,
                            hasAura = info.hasAura,
                            selfAura = info.selfAura,
                            isInvisible = info.isInvisible,
                        })
                    end
                end
            end
        end
    end
    return out
end

local function SpellDump(arg)
    local SAU = addon.ScootAuras
    local Engine = SAU.Engine
    local lines = {}
    local function push(s) table.insert(lines, s) end

    local n = tonumber(arg)
    if not n then
        addon:Print("Usage: /scoot debug sa spell <N|spellId>  (N from a tN row in /scoot debug sa list)")
        return
    end

    -- Tracker ids are small profile counters; anything else is a spell id.
    local trackerId, tracker = nil, SAU.GetTracker(n)
    local spellId
    if tracker then
        trackerId = n
        spellId = tracker.spellId
    else
        spellId = n
    end

    push("=== ScootAuras spell resolution ===")
    push("")
    push("In combat: " .. tostring(InCombatLockdown())
        .. "  aura restrictions: " .. tostring(addon.AurasSecretNow and addon.AurasSecretNow())
        .. "  structural gate open: " .. tostring(Engine.CanDoStructuralWork()))
    push("")

    if tracker then
        push(("Tracker t%d '%s': spell=%d kind=%s unit=%s shape=%s enabled=%s owner=%s"):format(
            trackerId, tostring(tracker.name), spellId, tostring(tracker.kind), tostring(tracker.unit),
            tostring(tracker.shape), tostring(tracker.enabled), tostring(tracker.owner)))
        push("Filter string: " .. tostring(SAU.FilterForKind(tracker.kind)))
        local entry = Engine._byTracker[trackerId]
        if entry then
            push(("Pool entry shell%d: container=%s button=%s wired=%s wiredSpell=%s wiredUnit=%s wiredKind=%s retired=%d desiredEnabled=%s enabledDirty=%s"):format(
                entry.index, tostring(entry.container ~= nil), tostring(entry.button ~= nil),
                tostring(entry.wired), tostring(entry.wiredSpellId), tostring(entry.wiredUnit),
                tostring(entry.wiredKind), #(entry.containers or {}), tostring(entry.desiredEnabled),
                tostring(entry.enabledDirty)))
            local shown = entry.shell and entry.shell:IsShown()
            push("Shell shown: " .. tostring(shown) .. "  grouped: " .. tostring(entry.grouped or false))
        else
            push("Pool entry: NONE (tracker not claimed)")
        end
        push("Pending wire: " .. tostring(Engine.HasPendingWork()))
        for _, key in ipairs({ "build.t" .. trackerId, "wire.t" .. trackerId, "filters.t" .. trackerId,
                               "cadence.t" .. trackerId }) do
            if Engine._results[key] ~= nil then
                push(key .. " = " .. tostring(Engine._results[key]))
            end
        end
    else
        push("Spell " .. spellId .. " (no tracker with that id; treated as a spell ID)")
    end
    push("")

    -- What the player sees for this ID (fresh override state).
    SAU.InvalidateSpellDescriptions()
    local dname, dicon, dshown = SAU.DescribeSpell(spellId)
    push(("Described as: '%s' icon=%s via spell %d%s"):format(
        dname, tostring(dicon), dshown, (dshown ~= spellId) and (" (override of " .. spellId .. ")") or ""))
    local ook, ov = pcall(C_Spell.GetOverrideSpell, spellId)
    push("C_Spell.GetOverrideSpell(" .. spellId .. ") = " .. (ook and tostring(ov) or ("ERR " .. tostring(ov))))
    local bok, bs = pcall(C_Spell.GetBaseSpell, spellId)
    push("C_Spell.GetBaseSpell(" .. spellId .. ") = " .. (bok and tostring(bs) or ("ERR " .. tostring(bs))))
    push("Own name/icon: '" .. SpellLabel(spellId) .. "'")
    push("")

    -- The include set the engine would build right now.
    local filters = Engine._BuildCandidateFilters({ spellId = spellId })
    local include = filters and filters.includeSpellIDs or {}
    local ids = {}
    for id in pairs(include) do table.insert(ids, id) end
    table.sort(ids)
    push("--- includeSpellIDs (" .. #ids .. ") ---")
    for _, id in ipairs(ids) do
        push(("  %d  %s"):format(id, SpellLabel(id)))
    end
    push("")

    -- Every CDM entry touching any included ID.
    local wanted = {}
    for id in pairs(include) do wanted[id] = true end
    push("--- CDM entries touching these IDs ---")
    local entries = ScanCDMEntries()
    local hits = 0
    for _, e in ipairs(entries) do
        local touch = (e.base and wanted[e.base]) or (e.override and wanted[e.override])
            or (e.tooltip and wanted[e.tooltip])
        if not touch then
            for _, lid in ipairs(e.linked) do
                if wanted[lid] then touch = true break end
            end
        end
        if touch then
            hits = hits + 1
            local linkedStr = {}
            for _, lid in ipairs(e.linked) do
                table.insert(linkedStr, lid .. " " .. SpellLabel(lid))
            end
            push(("  [%s] cooldownID=%s base=%s '%s' override=%s%s tooltipOverride=%s linked=[%s] known=%s hasAura=%s selfAura=%s invisible=%s"):format(
                CategoryName(e.category), tostring(e.cooldownID), tostring(e.base),
                e.base and SpellLabel(e.base) or "?",
                tostring(e.override), e.override and (" '" .. SpellLabel(e.override) .. "'") or "",
                tostring(e.tooltip), table.concat(linkedStr, ", "),
                tostring(e.isKnown), tostring(e.hasAura), tostring(e.selfAura), tostring(e.isInvisible)))
        end
    end
    if hits == 0 then
        push("  (none: the ID is off-catalog; the include set is the raw ID only)")
    end
    push("Catalog scanned: " .. #entries .. " entries")
    push("")

    -- What the picker shows for this ID, if it is a catalog base.
    local Picker = addon.UI and addon.UI.ScootAuraCDMPicker
    if Picker and Picker.BuildCatalog then
        local cell
        for _, c in ipairs(Picker.BuildCatalog()) do
            if c.spellId == spellId or c.shownSpellId == spellId or c.baseSpellId == spellId then
                cell = c
                break
            end
        end
        if cell then
            push(("Picker cell: '%s' stores %d (entry base %s) shows %d icon=%s"):format(
                cell.name, cell.spellId, tostring(cell.baseSpellId), tostring(cell.shownSpellId),
                tostring(cell.icon)))
        else
            push("Picker cell: none (not a CDM entry identity for this character)")
        end
    end

    -- Live aura check (plain outside restrictions; a debuff tracker wants a target).
    if tracker and not (addon.AurasSecretNow and addon.AurasSecretNow()) then
        push("")
        local unit = tracker.unit or "target"
        if UnitExists(unit) then
            push("--- Auras on " .. unit .. " matching the include set (plain read, out of restrictions) ---")
            local found = 0
            for _, id in ipairs(ids) do
                local aok, data = pcall(C_UnitAuras.GetUnitAuraBySpellID, unit, id)
                if aok and type(data) == "table" and not issecretvalue(data) then
                    found = found + 1
                    push(("  %d %s source=%s"):format(id, tostring(data.name), tostring(data.sourceUnit)))
                end
            end
            if found == 0 then push("  (none present right now)") end
        else
            push("No " .. unit .. "; target something with the aura up and re-run for a live match check.")
        end
    end

    addon.DebugShowWindow("ScootAuras Spell Resolution", table.concat(lines, "\n"))
end

local function CatalogDump()
    local Picker = addon.UI and addon.UI.ScootAuraCDMPicker
    if not (Picker and Picker.BuildCatalog) then
        addon:Print("CDM picker not loaded.")
        return
    end
    local lines = { "=== ScootAuras CDM picker catalog (as the grid shows it) ===", "" }
    local cells = Picker.BuildCatalog()
    for _, c in ipairs(cells) do
        local notes = {}
        if c.baseSpellId and c.baseSpellId ~= c.spellId then
            table.insert(notes, "tooltip override of base " .. c.baseSpellId)
        end
        if c.shownSpellId and c.shownSpellId ~= c.spellId then
            table.insert(notes, "shown as " .. c.shownSpellId)
        end
        local via = (#notes > 0) and ("  (" .. table.concat(notes, "; ") .. ")") or ""
        table.insert(lines, ("%-32s stores %d%s"):format(c.name, c.spellId, via))
    end
    table.insert(lines, "")
    table.insert(lines, #cells .. " cells")
    addon.DebugShowWindow("ScootAuras Catalog", table.concat(lines, "\n"))
end

--------------------------------------------------------------------------------
-- Dispatch
--------------------------------------------------------------------------------

local VALID_UNITS = { player = true, group = true, target = true, focus = true }
local VALID_SHAPES = { icon = true, bar = true, shape = true, text = true, icontext = true }
local VALID_KINDS = { buff = true, debuff = true, missingbuff = true }

function addon.DebugScootAuras(sub, a1, a2, a3, a4)
    sub = sub or ""

    -- Phase 1 lifecycle commands (real trackers, persisted in the profile).
    if sub == "add" then
        local spellId = tonumber(a1)
        if not spellId then
            addon:Print("Usage: /scoot debug sa add <spellId> [player|group|target|focus] [buff|debuff|missingbuff] [icon|bar|shape|text|icontext]")
            return
        end
        -- Arguments after the spell ID are order-free: any of unit/kind/shape.
        local unit, shape, kind = nil, nil, "buff"
        for _, a in ipairs({ a2, a3, a4 }) do
            if VALID_UNITS[a or ""] then unit = a end
            if VALID_SHAPES[a or ""] then shape = a end
            if VALID_KINDS[a or ""] then kind = a end
        end
        unit = unit or addon.ScootAuras.DefaultUnitForKind(kind)
        shape = shape or addon.ScootAuras.DefaultShapeForKind(kind)
        local trackerId, err = addon.ScootAuras.CreateTracker({
            spellId = spellId, kind = kind, unit = unit, shape = shape,
        })
        if trackerId then
            addon:Print(("ScootAuras t%d created: spell %d (%s on %s as %s)"):format(
                trackerId, spellId, kind, unit, shape))
            if not addon.ScootAuras.Engine.CanDoStructuralWork() then
                addon:Print("Wiring queued; it applies when combat or instance restrictions end.")
            end
        else
            addon:Print("ScootAuras add failed: " .. tostring(err))
        end
        return
    end

    if sub == "del" then
        local trackerId = tonumber(a1)
        local ok, err = addon.ScootAuras.DeleteTracker(trackerId or -1)
        addon:Print(ok and ("ScootAuras t" .. trackerId .. " deleted.") or ("Delete failed: " .. tostring(err)))
        return
    end

    if sub == "enable" or sub == "disable" then
        local trackerId = tonumber(a1)
        local ok, err = addon.ScootAuras.SetTrackerEnabled(trackerId or -1, sub == "enable")
        addon:Print(ok and ("ScootAuras t" .. trackerId .. " " .. sub .. "d.") or (sub .. " failed: " .. tostring(err)))
        return
    end

    if sub == "edit" then
        if not addon.ShowScootAuraEditor then
            addon:Print("Editor unavailable.")
            return
        end
        if not addon.ScootAuras.IsModuleActive() then
            addon:Print("ScootAuras module is disabled (enable it on the Features page, then reload).")
            return
        end
        local trackerId = tonumber(a1)
        addon.ShowScootAuraEditor(trackerId)
        addon:Print(trackerId and ("ScootAuras editor opened for t" .. trackerId)
            or "ScootAuras editor opened with a fresh draft.")
        return
    end

    if sub == "gadd" then
        local name = a1
        if name and a2 then name = name .. " " .. a2 end
        if name and a3 then name = name .. " " .. a3 end
        local gid, err = addon.ScootAuras.CreateGroup(name)
        addon:Print(gid and ("ScootAuras g" .. gid .. " created.") or ("Group add failed: " .. tostring(err)))
        return
    end

    if sub == "gdel" then
        local gid = tonumber(a1)
        local ok, err = addon.ScootAuras.DeleteGroup(gid or -1)
        addon:Print(ok and ("ScootAuras g" .. gid .. " deleted; members kept.") or ("Group delete failed: " .. tostring(err)))
        return
    end

    if sub == "join" then
        local trackerId, gid = tonumber(a1), tonumber(a2)
        if not trackerId or not gid then
            addon:Print("Usage: /scoot debug sa join <trackerId> <gid> [index]")
            return
        end
        local ok, err = addon.ScootAuras.SetTrackerGroup(trackerId, gid, tonumber(a3))
        addon:Print(ok and ("ScootAuras t" .. trackerId .. " joined g" .. gid .. ".") or ("Join failed: " .. tostring(err)))
        if ok and not addon.ScootAuras.Engine.CanDoStructuralWork() then
            addon:Print("The move applies when combat or instance restrictions end.")
        end
        return
    end

    if sub == "leave" then
        local trackerId = tonumber(a1)
        local ok, err = addon.ScootAuras.SetTrackerGroup(trackerId or -1, nil)
        addon:Print(ok and ("ScootAuras t" .. trackerId .. " left its group.") or ("Leave failed: " .. tostring(err)))
        return
    end

    if sub == "reconcile" then
        addon.ScootAuras.ReconcileForActiveProfile("debug")
        addon:Print("ScootAuras reconcile ran. See /scoot debug sa list")
        return
    end

    if sub == "flush" then
        addon.ScootAuras.Engine.TryFlush("debug")
        addon:Print("ScootAuras flush attempted (no-op while the structural window is closed).")
        return
    end

    if sub == "list" then
        LifecycleDump()
        return
    end


    if sub == "specs" then
        SpecsDump()
        return
    end

    if sub == "methods" then
        local trackerId = tonumber(a1)
        if not trackerId then
            addon:Print("Usage: /scoot debug sa methods <id>")
            return
        end
        DumpButtonMethods(trackerId)
        return
    end

    if sub == "spell" then
        SpellDump(a1)
        return
    end

    if sub == "catalog" then
        CatalogDump()
        return
    end

    -- Missing-buff reminder: gate container, clip/blink state, secrecy of the
    -- tracked spell, and a plain read for cross-checking.
    if sub == "missing" then
        local SAU = addon.ScootAuras
        local trackerId = tonumber(a1)
        if not trackerId or not SAU.Missing then
            addon:Print("Usage: /scoot debug sa missing <trackerId>")
            return
        end
        local lines = SAU.Missing.DebugInfo(trackerId)
        addon.DebugShowWindow("ScootAuras Missing Buff t" .. trackerId, table.concat(lines, "\n"))
        return
    end

    -- Cadence lock probes: dump the record, force the lock bar's value
    -- (geometry check), or show the lock bar (alpha) to watch it drain.
    if sub == "cadence" then
        local SAU = addon.ScootAuras
        local trackerId = tonumber(a1)
        local Cadence = SAU.Cadence
        if not trackerId or not Cadence then
            addon:Print("Usage: /scoot debug sa cadence <trackerId|spellId> [on | off | set <0..1> | alpha <0..1> | mirror <y|off>]")
            return
        end
        -- Tracker ids are small profile counters; a spell id (e.g. 589 for
        -- Shadow Word: Pain) resolves to every bar tracker on that spell.
        local ids = {}
        if SAU.GetTracker(trackerId) then
            ids[1] = trackerId
        else
            for _, row in ipairs(SAU.SortedTrackers()) do
                if row.tracker.spellId == trackerId and row.tracker.shape == "bar" then
                    table.insert(ids, row.id)
                end
            end
            if #ids == 0 then
                addon:Print("ScootAuras cadence: no tracker with id " .. trackerId
                    .. " and no bar tracker on spell " .. trackerId .. " (ids: /scoot debug sa)")
                return
            end
        end
        -- on/off: flip the tracker's toggle without the editor (same db key
        -- the Bar tab writes), then re-apply so Configure grabs the object.
        if a2 == "on" or a2 == "off" then
            local want = (a2 == "on")
            for _, id in ipairs(ids) do
                local db = SAU.GetDB(id)
                if db then db.barLockCadence = want end
                local comp = addon.Components and addon.Components[SAU.GetComponentId(id)]
                if comp and comp.ApplyStyling then
                    C_Timer.After(0, function() comp:ApplyStyling() end)
                end
                addon:Print(("ScootAuras cadence t%d barLockCadence=%s%s"):format(
                    id, tostring(want), db and "" or " (no db)"))
            end
            return
        end
        if a2 == "set" or a2 == "alpha" or a2 == "mirror" then
            for _, id in ipairs(ids) do
                local ok, err = Cadence.DebugSet(id, a2, a3)
                addon:Print(ok and ("ScootAuras cadence t" .. id .. " " .. a2 .. " " .. tostring(a3))
                    or ("cadence t" .. id .. " " .. a2 .. " failed: " .. tostring(err)))
            end
            return
        end
        local out = {}
        for _, id in ipairs(ids) do
            local t = SAU.GetTracker(id)
            local db = SAU.GetDB(id)
            table.insert(out, ("=== Cadence lock (t%d '%s' spell=%s %s on %s) ==="):format(
                id, tostring(t and t.name), tostring(t and t.spellId), tostring(t and t.kind), tostring(t and t.unit)))
            table.insert(out, "barLockCadence(db)=" .. tostring(db and db.barLockCadence)
                .. " barFillMode(db)=" .. tostring(db and db.barFillMode))
            local lines, err = Cadence.DebugInfo(id)
            if lines then
                for _, l in ipairs(lines) do table.insert(out, l) end
            else
                table.insert(out, tostring(err))
            end
            table.insert(out, "")
        end
        addon.DebugShowWindow("ScootAuras Cadence", table.concat(out, "\n"))
        return
    end

    if sub == "create" or sub == "dupe" then
        local spellId = tonumber(a1)
        if not spellId then
            addon:Print("Usage: /scoot debug sa create <spellId> [player|target|focus] [buff|debuff]")
            return
        end
        local unit = VALID_UNITS[a2 or ""] and a2 or "player"
        local kind = (a3 == "debuff" or a2 == "debuff") and "debuff" or "buff"
        local times = (sub == "dupe") and 2 or 1
        for _ = 1, times do
            local probe, err = CreateProbe(spellId, unit, kind)
            if probe then
                addon:Print(("ScootAuras probe %s: spell %d on %s (%s)"):format(probe.id, spellId, unit, kind))
            else
                addon:Print("ScootAuras probe failed: " .. tostring(err))
                return
            end
        end
        return
    end

    if sub == "park" or sub == "revive" then
        local probe = ResolveProbe(a1)
        if not probe then addon:Print("Unknown probe. See /scoot debug sa state") return end
        addon:Print("ScootAuras " .. sub .. " " .. probe.id .. ": " .. SetProbeEnabled(probe, sub == "revive"))
        return
    end

    if sub == "fresh" then
        local probe = ResolveProbe(a1)
        local spellId = tonumber(a2)
        if not probe or not spellId then
            addon:Print("Usage: /scoot debug sa fresh <n> <spellId> [unit] [kind]")
            return
        end
        local unit = VALID_UNITS[a3 or ""] and a3 or "player"
        local kind = (a4 == "debuff" or a3 == "debuff") and "debuff" or "buff"
        addon:Print("ScootAuras fresh " .. probe.id .. ": " .. FreshContainer(probe, spellId, unit, kind))
        return
    end

    if sub == "repoint" then
        local probe = ResolveProbe(a1)
        local spellId = tonumber(a2)
        if not probe or not spellId then
            addon:Print("Usage: /scoot debug sa repoint <n> <spellId>")
            return
        end
        addon:Print("ScootAuras repoint " .. probe.id .. ": " .. RepointSpell(probe, spellId))
        return
    end

    if sub == "parkfilter" then
        local probe = ResolveProbe(a1)
        if not probe then addon:Print("Unknown probe. See /scoot debug sa state") return end
        addon:Print("ScootAuras parkfilter " .. probe.id .. ": " .. ParkFilter(probe))
        return
    end

    if sub == "setunit" then
        local probe = ResolveProbe(a1)
        if not probe or not VALID_UNITS[a2 or ""] then
            addon:Print("Usage: /scoot debug sa setunit <n> <player|target|focus>")
            return
        end
        addon:Print("ScootAuras setunit " .. probe.id .. ": " .. ReUnit(probe, a2))
        return
    end

    if sub == "budget" then
        local count = tonumber(a1)
        local spellId = tonumber(a2)
        if not count or not spellId then
            addon:Print("Usage: /scoot debug sa budget <count> <spellId>")
            return
        end
        local summary, err = RunBudget(count, spellId)
        addon:Print("ScootAuras budget: " .. tostring(summary or err))
        return
    end

    if sub == "clear" then
        ClearAll()
        addon:Print("ScootAuras probes cleared (parked + hidden; reload to fully remove).")
        return
    end

    if sub == "log" then
        DumpLog()
        return
    end

    DumpState()
end
