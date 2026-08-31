--------------------------------------------------------------------------------
-- groupauras/engine.lua
-- Container and slot lifecycle for group-frame aura tracking (12.1 AuraContainer)
--
-- Patch 12.1 made aura data secret in combat, encounters, M+ and PvP. The old
-- AuraUtil.ForEachAura scan raised from addon context exactly when tracking
-- mattered, so the display froze at whatever it held when the pull started.
-- Nothing here reads an aura. The engine acquires, filters and displays; Scoot
-- supplies regions and geometry.
--
-- Identity filtering is permitted for this case, and only looks accidental:
-- AuraContainerUtil.CanApplyIdentityCandidateFilters refuses includeSpellIDs
-- for harmful auras on assistable units and helpful auras on NON-assistable
-- units. Helpful auras on party and raid members are the allowed combination,
-- which is exactly what this component tracks.
--
-- TOPOLOGY (B, the shape ScootAuras and UFZ Auras both use):
--
--   UIParent
--    +- host           Scoot-owned Frame, SetAllPoints(compactFrame)
--       +- proxy       one per slot, Scoot-owned, carries size and placement
--       +- container   AuraContainer
--          +- button   engine-created, SetAllPoints(its proxy) at wire time
--
-- The container must be a child of a Scoot frame; never parent to a
-- CompactUnitFrame. The proxy layer is what makes geometry combat-legal: a
-- button carries DenyTaintedAccessWhenAurasAreSecret, so writes to it are
-- refused while auras are secret, but it is anchored to a plain Scoot frame
-- that Scoot can move and resize at any time.
--
-- TIER SPLIT:
--   Tier 1, always legal: container SetPoint / Show / Hide / SetEnabled /
--     SetUnit / UpdateAllAuras, SetAuraSlotFilterString,
--     SetAuraSlotCandidateFilters, and everything on a host or a proxy.
--   Tier 2, gated on CanDoStructuralWork(): AddAuraSlot, and every write to a
--     button or its descendants. Refused work queues and drains on the
--     restriction lift.
--
-- Gate on aura secrecy as well as combat lockdown. An encounter can restrict
-- auras with no lockdown, and secrecy stays on between pulls inside a key, so
-- PLAYER_REGEN_ENABLED alone never recovers a Mythic+ run.
--------------------------------------------------------------------------------

local addonName, addon = ...

local HA = addon.AuraTracking
if not HA then return end

HA.Engine = HA.Engine or {}
local Engine = HA.Engine

--------------------------------------------------------------------------------
-- Telemetry
--------------------------------------------------------------------------------

local results = {}   -- [key] = latest observation string
local log = {}       -- ring of { t, seq, tag, detail }
local logSeq = 0
local LOG_MAX = 96

Engine._results = results
Engine._log = log

local function SafeToString(v)
    if issecretvalue and issecretvalue(v) then return "<SECRET>" end
    local ok, s = pcall(tostring, v)
    return ok and s or "<tostring failed>"
end
Engine.SafeToString = SafeToString

local function Record(tag, detail)
    logSeq = logSeq + 1
    log[(logSeq % LOG_MAX) + 1] = { t = GetTime(), seq = logSeq, tag = tag, detail = detail or "" }
end
Engine.Record = Record

local function SetResult(key, value)
    results[key] = value
end
Engine.SetResult = SetResult

--------------------------------------------------------------------------------
-- Gate and pending queue
--------------------------------------------------------------------------------

function Engine.CanDoStructuralWork()
    if InCombatLockdown() then return false end
    if addon.AurasSecretNow and addon.AurasSecretNow() then return false end
    return true
end

local pending = setmetatable({}, { __mode = "k" })  -- [frame] = true
Engine._pending = pending

local flushTicker = nil

local function UpdateFlushTicker()
    if next(pending) then
        if not flushTicker then
            -- Aura secrecy outlives combat inside a key or a raid instance, so
            -- regen alone would park queued work until the run ends. Re-probe
            -- the gate at low frequency while anything is waiting.
            flushTicker = C_Timer.NewTicker(5, function()
                Engine.Drain("ticker")
            end)
        end
    elseif flushTicker then
        flushTicker:Cancel()
        flushTicker = nil
    end
end

local function Queue(frame, reason)
    pending[frame] = true
    UpdateFlushTicker()
    Record("queued", reason or "?")
end

--------------------------------------------------------------------------------
-- Entries
--------------------------------------------------------------------------------
-- Keyed weakly by the Blizzard compact frame, and never written onto it.

local entries = setmetatable({}, { __mode = "k" })
Engine._entries = entries

local hostIndex = 0

function Engine.GetEntry(frame)
    return frame and entries[frame] or nil
end

local function EnsureHost(frame)
    local entry = entries[frame]
    if entry then return entry end

    hostIndex = hostIndex + 1
    local host = CreateFrame("Frame", "ScootGroupAuraHost" .. hostIndex, UIParent)
    -- MEDIUM, not HIGH: Blizzard's compact frames are LOW, so MEDIUM covers
    -- them while still letting an open Blizzard panel sit on top.
    if addon.Strata and addon.Strata.ApplyHUD then
        addon.Strata.ApplyHUD(host, 20)
    end
    host:SetAllPoints(frame)
    host:Hide()

    entry = {
        frame = frame,
        host = host,
        index = hostIndex,
        container = nil,
        unit = nil,
        slots = {},      -- [spellId] = slot
        slotSeq = 0,
        frameHeight = 36,
    }
    entries[frame] = entry
    return entry
end

--- Icon size is derived from the group frame's height, and GetHeight on a
--- tainted compact frame is not dependable in combat. Cache it while the read
--- is safe.
function Engine.CacheHeight(frame)
    local entry = entries[frame]
    if not entry or InCombatLockdown() then return end
    local ok, h = pcall(frame.GetHeight, frame)
    if ok and type(h) == "number" and not issecretvalue(h) and h > 0 then
        entry.frameHeight = h
    end
end

--------------------------------------------------------------------------------
-- Container
--------------------------------------------------------------------------------

local function BuildContainer(entry)
    if entry.container then return entry.container end

    local ok, container = pcall(CreateFrame, "AuraContainer", nil, entry.host, "CustomAuraContainerTemplate")
    if not ok or not container then
        SetResult("build.container", "FAILED: " .. SafeToString(container))
        Record("build-fail", "container")
        return nil
    end

    -- A container with no rect, or one that is not shown, binds its slots and
    -- then processes nothing at all, in silence.
    container:SetAllPoints(entry.host)
    container:Show()

    entry.container = container
    SetResult("build.container", "ok")
    Record("built", "container " .. entry.index)
    return container
end

--------------------------------------------------------------------------------
-- Slots
--------------------------------------------------------------------------------

local function EmptyFilters()
    -- How a slot is retired. Blizzard exposes no public slot removal (its
    -- pooled frames would become unreachable), so a disabled aura's slot is
    -- re-pointed at nothing and its button stays engine-hidden.
    --
    -- Two filters, because one is conditional. An empty includeSpellIDs rejects
    -- every candidate, but identity filters are skipped entirely when
    -- CanApplyIdentityCandidateFilters says no, which happens the moment a unit
    -- stops being assistable (a mind-controlled group member). maxDuration is
    -- applied unconditionally, and 0 rejects both branches of its test: a timed
    -- aura fails duration > 0, and a permanent one fails duration == 0.
    return { includeSpellIDs = {}, maxDuration = 0 }
end

local function LinkedIdsFor(spellId)
    local reg = HA.SPELL_REGISTRY_BY_ID and HA.SPELL_REGISTRY_BY_ID[spellId]
    return reg and reg.linkedIds or nil
end

-- Cached per spell. The Cooldown Manager expansion walks every category and
-- every cooldown ID, and the reconcile path would otherwise re-run it once per
-- slot per frame: forty raid frames times six auras is 240 full walks for one
-- refresh. The result only changes with the player's spec, so it is memoized
-- and dropped on the events that can change it.
local filterCache = {}

function Engine.InvalidateFilters()
    wipe(filterCache)
end

local function FiltersFor(spellId)
    local cached = filterCache[spellId]
    if cached then return cached.include, cached.summary end

    -- Registry links plus the Cooldown Manager expansion. Without the latter,
    -- talent overrides and rank variants silently never match.
    local include = addon.AuraIds.BuildIncludeSet(spellId, LinkedIdsFor(spellId))
    local ids = {}
    for id in pairs(include) do table.insert(ids, id) end
    table.sort(ids)
    local summary = table.concat(ids, ",")

    filterCache[spellId] = { include = include, summary = summary }
    return include, summary
end

--- Points a live slot at its real spell. Tier 1, so a mid-combat enable lands.
local function ActivateSlot(entry, slot)
    local container = entry.container
    if not container then return end
    local filter = HA.SlotFilterString(slot.spellId)
    local include, summary = FiltersFor(slot.spellId)
    local key = filter .. "#" .. summary
    if slot.active and slot.filterKey == key then return end

    pcall(container.SetAuraSlotFilterString, container, slot.key, filter)
    local ok, err = pcall(container.SetAuraSlotCandidateFilters, container, slot.key,
        { includeSpellIDs = include })
    if ok then
        slot.active = true
        slot.filterKey = key
        SetResult("filters." .. slot.spellId, key)
    else
        SetResult("filters." .. slot.spellId, "FAILED: " .. SafeToString(err))
    end
end

local function RetireSlot(entry, slot)
    local container = entry.container
    if not container or not slot.active then return end
    if pcall(container.SetAuraSlotCandidateFilters, container, slot.key, EmptyFilters()) then
        slot.active = false
        slot.filterKey = nil
        Record("retired", tostring(slot.spellId))
    end
end

--- Creates one slot and its proxy. TIER 2: AddAuraSlot runs initializeFrame
--- synchronously, which is the only moment the button tree may be touched.
local function AddSlot(entry, spellId)
    local container = entry.container
    if not container then return nil end

    entry.slotSeq = entry.slotSeq + 1

    local slot = {
        spellId = spellId,
        key = "scootGA" .. spellId .. "_" .. entry.slotSeq,
        animId = HA.SlotAnimId(spellId),
        active = true,
    }

    -- The proxy exists BEFORE the slot, because initializeFrame fires inside
    -- AddAuraSlot and the button anchors to it there.
    local proxy = CreateFrame("Frame", nil, entry.host)
    proxy:SetSize(16, 16)
    proxy:SetPoint("CENTER", entry.host, "CENTER", 0, 0)
    proxy:EnableMouse(false)
    slot.proxy = proxy

    local filter = HA.SlotFilterString(spellId)
    local include, summary = FiltersFor(spellId)
    slot.filterKey = filter .. "#" .. summary

    local ok, buttonOrErr = pcall(container.AddAuraSlot, container, slot.key, filter, {
        candidateFilters = { includeSpellIDs = include },
        -- Never candidateFilters.maxDuration: any non-nil value implicitly
        -- hides permanent auras, which is most of the raid-buff registry.
        initializeFrame = function(button)
            slot.button = button
            local wok, werr = pcall(HA.WireButton, entry, slot, button)
            slot.wired = wok and true or false
            SetResult("wire." .. spellId, wok and "ok" or ("FAILED: " .. SafeToString(werr)))
            if not wok then Record("wire-fail", tostring(spellId)) end
        end,
    })
    if not ok then
        SetResult("slot." .. spellId, "FAILED: " .. SafeToString(buttonOrErr))
        Record("slot-fail", tostring(spellId))
        proxy:Hide()
        return nil
    end
    if not slot.button and buttonOrErr then slot.button = buttonOrErr end

    entry.slots[spellId] = slot
    SetResult("slot." .. spellId, "ok (" .. slot.key .. ")")
    SetResult("filters." .. spellId, slot.filterKey)
    Record("slot-added", tostring(spellId))
    return slot
end

--- Reconciles one frame's slots against the enabled config. Returns true when
--- everything the config asks for exists.
local function SyncSlots(entry)
    if not entry.container then return false end

    local desired = HA.EnabledSpellList()
    local wanted = {}
    for _, item in ipairs(desired) do wanted[item.spellId] = true end

    -- Retire anything no longer wanted. Tier 1, so a disable lands in combat.
    for spellId, slot in pairs(entry.slots) do
        if not wanted[spellId] then RetireSlot(entry, slot) end
    end

    local complete = true
    for _, item in ipairs(desired) do
        local spellId = item.spellId
        local slot = entry.slots[spellId]
        -- A change of animated style is the one edit that cannot be re-styled
        -- in place: an animation's textures exist only if they were created
        -- inside initializeFrame. Retire and re-slot instead.
        if slot and slot.animId ~= HA.SlotAnimId(spellId) then
            if Engine.CanDoStructuralWork() then
                RetireSlot(entry, slot)
                entry.slots[spellId] = nil
                slot = nil
            else
                complete = false
            end
        end
        if slot then
            ActivateSlot(entry, slot)
        elseif Engine.CanDoStructuralWork() then
            if not AddSlot(entry, spellId) then complete = false end
        else
            complete = false
        end
    end
    return complete
end

--------------------------------------------------------------------------------
-- Subject and visibility
--------------------------------------------------------------------------------

--- Re-assert, never a bare kick. Hiding a container drops its event
--- registrations outright (ShouldRegisterForDynamicEvents is IsVisible() and
--- IsEnabled()), and SetUnit early-outs on an unchanged token without
--- re-parsing, so a subject change needs all of these or the frame goes dead
--- until a reload. Every call here is Tier 1.
local function ApplySubject(entry, unit, shown)
    local container = entry.container
    if not container then return end

    if shown then
        entry.host:Show()
        pcall(container.SetEnabled, container, true)
        pcall(container.Show, container)
        if unit then pcall(container.SetUnit, container, unit) end
        pcall(container.UpdateAllAuras, container)
    else
        pcall(container.SetEnabled, container, false)
        pcall(container.Hide, container)
        entry.host:Hide()
    end
end

--------------------------------------------------------------------------------
-- Public entry points
--------------------------------------------------------------------------------

local function AnyEnabled()
    return HA.EnabledSpellList()[1] ~= nil
end

--- The host is UIParent-parented, so it does not inherit the compact frame's
--- visibility and has to be told. Checked on every path rather than only at the
--- call sites, because the drain re-enters long after the frame may have gone.
local function FrameShowing(frame)
    local ok, vis = pcall(frame.IsVisible, frame)
    return ok and vis == true
end

--- Bring one group frame up to date. Safe to call from anywhere, at any time.
function Engine.SyncFrame(frame, unit)
    if not frame then return end

    -- Zero-Touch: nothing is created until the user enables an aura.
    if not entries[frame] and not AnyEnabled() then return end

    local entry = EnsureHost(frame)
    entry.unit = unit
    Engine.CacheHeight(frame)

    if not entry.container then
        if not Engine.CanDoStructuralWork() then
            Queue(frame, "container")
            return
        end
        if not BuildContainer(entry) then return end
    end

    local complete = SyncSlots(entry)
    HA.LayoutFrame(entry)
    if not HA.ApplyFrameStyle(entry) then complete = false end

    -- SetUnit LAST, after the slots exist: it re-evaluates the container's
    -- event registrations and those are gated on the container having content.
    -- Unit-first looks correct out of combat and then never updates again.
    ApplySubject(entry, unit, unit ~= nil and FrameShowing(frame))

    if not complete then Queue(frame, "slots") end
end

--- The frame has no subject, or is not visible. Park it.
function Engine.HideFrame(frame)
    local entry = entries[frame]
    if not entry then return end
    entry.unit = nil
    ApplySubject(entry, nil, false)
end

--- Subject swap from the CompactUnitFrame_SetUnit hook. Tier 1 throughout, so
--- this is the path that keeps working through a mid-combat roster change.
function Engine.SetSubject(frame, unit)
    local entry = entries[frame]
    if not entry then
        Engine.SyncFrame(frame, unit)
        return
    end
    entry.unit = unit
    Engine.CacheHeight(frame)
    ApplySubject(entry, unit, unit ~= nil and FrameShowing(frame))
end

function Engine.Drain(reason)
    if not Engine.CanDoStructuralWork() then return end
    local queued = pending
    pending = setmetatable({}, { __mode = "k" })
    Engine._pending = pending
    local any = false
    for frame in pairs(queued) do
        any = true
        local entry = entries[frame]
        if entry then Engine.SyncFrame(frame, entry.unit) end
    end
    UpdateFlushTicker()
    if any then Record("drain", reason or "?") end
end

--- Walk every entry, for the debug surface.
function Engine.ForEachEntry(fn)
    for frame, entry in pairs(entries) do
        fn(frame, entry)
    end
end

--------------------------------------------------------------------------------
-- Restriction-lift watcher
--------------------------------------------------------------------------------
-- Aura secrecy lifts on more edges than combat ends on, so listen to all of
-- them and re-probe rather than assume.

local function onRestrictionLift(event, unit)
    if event == "PLAYER_SPECIALIZATION_CHANGED" then
        if unit and unit ~= "player" then return end
        Engine.InvalidateFilters()
        for frame, entry in pairs(entries) do
            for _, slot in pairs(entry.slots) do
                if slot.active then
                    slot.filterKey = nil
                    ActivateSlot(entry, slot)
                end
            end
            if entry.container then pcall(entry.container.UpdateAllAuras, entry.container) end
        end
        Record("respec", "filters rebuilt")
    end
    Engine.Drain(event)
end

addon.Events.On("UnitFrames:GroupAurasEngine", "PLAYER_REGEN_ENABLED", onRestrictionLift)
addon.Events.On("UnitFrames:GroupAurasEngine", "ENCOUNTER_END", onRestrictionLift)
addon.Events.On("UnitFrames:GroupAurasEngine", "ZONE_CHANGED_NEW_AREA", onRestrictionLift)
-- A spec change rewrites the Cooldown Manager rows the include sets are built
-- from, so the memo has to go with it and every live slot re-point.
addon.Events.On("UnitFrames:GroupAurasEngine", "PLAYER_SPECIALIZATION_CHANGED", onRestrictionLift)
