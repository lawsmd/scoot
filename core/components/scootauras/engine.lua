-- scootauras/engine.lua - Frame pool, AuraContainer wiring, structural gate
--
-- Physical frames are pooled because engine slots and LibEditMode
-- registrations are session-permanent. Per pool entry: a shell (LEM-registered
-- drag unit) and a visual (child of the shell; owns the AuraContainer and all
-- elements). Containers are per-occupancy, never recycled across content
-- changes: retiring one is SetEnabled(false), and a claim with different
-- content builds a fresh container beside the parked ones.
--
-- Wiring order is create -> size -> AddAuraSlot -> SetUnit -> UpdateAllAuras.
-- Unit assignment finalizes event registration against current content;
-- unit-first containers look fine out of combat and go event-dead in it.
local addonName, addon = ...

local SAU = addon.ScootAuras
local Engine = {}
SAU.Engine = Engine

local pool = {}          -- array of entries, session-permanent
local byTracker = {}     -- [trackerId] = entry
local byShell = {}       -- [shell frame] = entry (Edit Mode mirror lookup)
local pendingWire = {}   -- [trackerId] = true (structural work blocked when queued)
local flushTicker
local initialized = false

Engine._pool = pool
Engine._byTracker = byTracker

--------------------------------------------------------------------------------
-- Telemetry
--------------------------------------------------------------------------------

local results = {}
local log = {}
local logSeq = 0
local LOG_MAX = 100

local function SafeToString(v)
    if issecretvalue(v) then return "<secret>" end
    local ok, s = pcall(tostring, v)
    return ok and s or "<unprintable>"
end

local function Record(tag, detail)
    logSeq = logSeq + 1
    table.insert(log, { seq = logSeq, tag = tag, detail = detail or "" })
    if #log > LOG_MAX then table.remove(log, 1) end
end

local function SetResult(key, value)
    results[key] = value
end

Engine._results = results
Engine._log = log
Engine.Record = Record
Engine._SafeToString = SafeToString
Engine._SetResult = SetResult

--------------------------------------------------------------------------------
-- Gates
--------------------------------------------------------------------------------

-- Container/slot/element work touches the engine button tree, which carries
-- access restrictions while aura information is secret.
function Engine.CanDoStructuralWork()
    if InCombatLockdown() then return false end
    if addon.AurasSecretNow and addon.AurasSecretNow() then return false end
    return true
end

function Engine.IsInitialized()
    return initialized
end

function Engine.SetInitialized()
    initialized = true
end

function Engine.IsWired(trackerId)
    local entry = byTracker[trackerId]
    return (entry and entry.wired) or false
end

function Engine.HasPendingWork()
    return next(pendingWire) ~= nil
end

--------------------------------------------------------------------------------
-- Candidate filters (CDM as a data source for spell variants)
--------------------------------------------------------------------------------

-- Spell-variant expansion lives in base/utilities.lua as addon.AuraIds so the
-- group-frame tracker shares it. The rationale it encodes (union every CDM
-- entry, never early-return) was learned here: Flame Shock's CDM base is
-- 470411, the debuff is 188389 and is only a linked ID on some entries.

-- Returns the filters and the key that identifies them: the sorted id list,
-- joined. The key is stamped on the entry at build so a later catalog move can
-- be detected without recomputing anything in the acquire path.
local function BuildCandidateFilters(tracker, trackerId)
    local include = addon.AuraIds.BuildIncludeSet(tracker.spellId)
    local ids = {}
    for id in pairs(include) do table.insert(ids, id) end
    table.sort(ids)
    local key = table.concat(ids, ",")
    if trackerId then
        SetResult("filters.t" .. trackerId, key)
    end
    return { includeSpellIDs = include }, key
end

Engine._BuildCandidateFilters = BuildCandidateFilters

--------------------------------------------------------------------------------
-- Positions
--------------------------------------------------------------------------------

-- LibEditMode's name, or the AceDB profile name before the first layout
-- callback: SnapShellToVisual saves under this name, so the store can hold
-- profile-name records and the claim-time restore must read them.
local function GetActiveLayoutName()
    local name = addon.EditMode.GetActiveLayoutName()
    if name then return name end
    return addon.db and addon.db.GetCurrentProfile and addon.db:GetCurrentProfile() or nil
end

local function DefaultPositionFor(entry)
    return {
        point = "CENTER",
        x = 0,
        y = -260 - ((entry.index - 1) % 6) * 50,
    }
end

local function SavePosition(key, layoutName, point, x, y)
    if not key or not layoutName then return end
    local store = SAU.GetPositionStore(true)
    if type(store) ~= "table" then return end
    store[key] = store[key] or {}
    store[key][layoutName] = { point = point, x = x, y = y }
end

local function GetStoredPosition(key, layoutName)
    local store = SAU.GetPositionStore(false)
    local perKey = store and store[key]
    return perKey and perKey[layoutName] or nil
end

-- Shared with groups.lua ("g<gid>" keys live in the same store).
Engine.SavePosition = SavePosition
Engine._GetStoredPosition = GetStoredPosition
Engine.GetActiveLayoutName = GetActiveLayoutName

-- The helper restores at registration, but a re-claimed entry carries a new
-- occupant, so every claim restores explicitly against the name above.
local function ApplySavedPosition(entry)
    if not entry.occupantId then return end
    addon.EditMode.RestorePositionable(entry.shell, GetActiveLayoutName())
end

function Engine.ApplyPositionsForActiveLayout()
    for _, entry in pairs(byTracker) do
        ApplySavedPosition(entry)
    end
    if SAU.Groups then
        SAU.Groups.ApplyPositionsForActiveLayout()
    end
end

--------------------------------------------------------------------------------
-- Edit Mode registration (once per shell, occupant-agnostic)
--------------------------------------------------------------------------------

-- Mirror provider for the branded Edit Mode dialog: the Sizing tab's Scale
-- slider on a standalone tracker's shell. Resolved at BUILD time: pool
-- shells are occupant-agnostic and entry.occupantId changes over the
-- session, so the tracker id is re-read on every build and the spec closures
-- capture it. Writes go through SAU.SetTrackerStyling, which ends where the
-- editor's setAndApply ends (component db, then the restyle), so the two
-- surfaces cannot drift. Grouped trackers scale through their group's mirror
-- (groups.lua); their shells are hidden and never selected.
local function TrackerEditModeMirror(frame)
    local entry = byShell[frame]
    local trackerId = entry and entry.occupantId
    local tracker = trackerId and SAU.GetTracker(trackerId)
    if not tracker or entry.grouped then return nil end

    return {
        {
            kind = "slider", label = "Scale",
            min = 25, max = 200, step = 5, precision = 0,
            get = function()
                local db = SAU.GetDB(trackerId)
                return tonumber(db and db.scale) or 100
            end,
            set = function(v)
                SAU.SetTrackerStyling(trackerId, { scale = v })
            end,
        },
    }
end

Engine._EditModeMirror = TrackerEditModeMirror

-- One positionable per shell (core/editmode/positionables.lua). Storage stays
-- positions["t" .. id][layoutName]; the key follows the occupant, so a shell
-- with no occupant neither saves nor restores.
local function EnsureLEMFrame(entry)
    if entry.lemRegistered then return end
    local selection = addon.EditMode.RegisterPositionable(entry.shell, {
        key = function() return entry.occupantId and ("t" .. entry.occupantId) or nil end,
        default = DefaultPositionFor(entry),
        store = { get = GetStoredPosition, set = SavePosition },
        restoreDefault = true,
        brand = { navKey = SAU.NAV_KEY, mirror = TrackerEditModeMirror },
    })
    -- Read by /scoot debug sa.
    entry.lemRegistered = selection ~= nil
end

function Engine.UpdateEditModeName(trackerId)
    local entry = byTracker[trackerId]
    local tracker = SAU.GetTracker(trackerId)
    if entry and tracker then
        entry.shell.editModeName = tracker.name or ("ScootAura " .. trackerId)
    end
end

--------------------------------------------------------------------------------
-- Pool
--------------------------------------------------------------------------------

local function CreateEntry()
    local index = #pool + 1
    local shell = CreateFrame("Frame", "ScootAuraShell" .. index, UIParent)
    addon.Strata.ApplyHUD(shell, 25)
    shell:SetSize(32, 32)
    shell:SetMovable(true)
    shell:SetClampedToScreen(true)
    shell:Hide()
    addon.RegisterPetBattleFrame(shell)

    local visual = CreateFrame("Frame", nil, shell)
    visual:SetAllPoints(shell)

    local entry = {
        index = index,
        shell = shell,
        visual = visual,
        containers = {},   -- retired (parked) containers, kept dormant
        elements = {},
    }
    -- Cadence lock bar: Scoot-owned, outside every button tree, driven by
    -- cadence.lua. Created per entry so it survives pool reclaim.
    if SAU.Cadence then
        entry.lockBar = SAU.Cadence.CreateLockBar(visual)
    end
    pool[index] = entry
    byShell[shell] = entry
    return entry
end

-- filtersStale is a flag, never a recomputation. Rebuilding the include set
-- here would walk the whole Cooldown Manager catalog on every acquire, and it
-- would thrash: mid-spec-change the catalog is briefly empty, the expansion
-- degenerates to the bare spell id, the key flips, a rebuild fires, the catalog
-- settles and the key flips back. MarkStaleFilters does the comparison once per
-- settle event instead.
local function ContentMatches(entry, tracker)
    return entry.container ~= nil
        and entry.wiredSpellId == tracker.spellId
        and entry.wiredUnit == SAU.EngineUnitFor(tracker)
        and entry.wiredKind == tracker.kind
        and not entry.filtersStale
end

-- Kept off addon.Pool: slot allocator; acquire scans occupantId by content affinity, release is an ordered teardown.
-- Prefer a free entry whose parked container already matches the tracker's
-- content: reviving it is SetEnabled(true), which stays legal in combat.
local function AcquireEntry(tracker)
    for _, entry in ipairs(pool) do
        if not entry.occupantId and ContentMatches(entry, tracker) then
            return entry
        end
    end
    for _, entry in ipairs(pool) do
        if not entry.occupantId then
            return entry
        end
    end
    return CreateEntry()
end

--------------------------------------------------------------------------------
-- Enabled state (Tier 1-adjacent: pcall + dirty retry)
--------------------------------------------------------------------------------

local function ApplyEnabledState(entry, enabled)
    entry.desiredEnabled = enabled
    if not entry.container then return end
    local ok = pcall(entry.container.SetEnabled, entry.container, enabled)
    entry.enabledDirty = not ok
    if not ok then
        Record("enable-deferred", "entry" .. entry.index .. "=" .. tostring(enabled))
    end
end

function Engine.SetEnabledState(trackerId, enabled)
    local entry = byTracker[trackerId]
    if not entry then return end
    ApplyEnabledState(entry, enabled)
end

--------------------------------------------------------------------------------
-- Build
--------------------------------------------------------------------------------

-- Ensures the entry's live container matches the tracker's content, building a
-- fresh container (and retiring the old one) when it does not. Caller must
-- hold the structural gate.
local function EnsureBuilt(trackerId, tracker, state, entry)
    if ContentMatches(entry, tracker) then
        return true
    end

    -- Retire the mismatched container in place.
    if entry.container then
        pcall(entry.container.SetEnabled, entry.container, false)
        table.insert(entry.containers, entry.container)
        entry.container = nil
        entry.button = nil
        entry.wired = false
        if SAU.Cadence then
            SAU.Cadence.OnRetire(entry)
        end
        if SAU.Missing then
            SAU.Missing.OnRetire(entry)
        end
    end

    local ok, container = pcall(CreateFrame, "AuraContainer", nil, entry.visual, "CustomAuraContainerTemplate")
    if not ok or not container then
        SetResult("build.t" .. trackerId, "FAILED: " .. SafeToString(container))
        Record("build-fail", "t" .. trackerId)
        return false
    end

    local isMissing = tracker.kind == "missingbuff" and SAU.Missing ~= nil

    pcall(container.SetFrameLevel, container, entry.visual:GetFrameLevel() + 5)
    -- Containers process only while shown and anchored; an unanchored one is
    -- silently dead.
    if isMissing then
        -- Missing-buff kind: the container itself is the presence gate. Its
        -- aura group resizes it and the reminder hangs off its right edge
        -- (missing.lua), so it sits 1 x 1 at the visual's left edge.
        SAU.Missing.PlaceContainer(entry, container)
    else
        pcall(container.SetSize, container, 32, 32)
        pcall(container.SetPoint, container, "CENTER", entry.visual, "CENTER", 0, 0)
    end

    entry.container = container
    entry.elements = {}
    state.elements = entry.elements
    entry.slotSeq = (entry.slotSeq or 0) + 1
    local slotKey = "scootAura" .. trackerId .. "_" .. entry.slotSeq
    local filters, filterKey = BuildCandidateFilters(tracker, trackerId)

    if isMissing then
        -- No slot and no button: nothing inside the container is ever bound
        -- or drawn. The group's frames only feed the layout's size.
        local gok, gerr = SAU.Missing.AddGateGroup(trackerId, tracker, entry, container, filters)
        if not gok then
            SetResult("build.t" .. trackerId, "group FAILED: " .. SafeToString(gerr))
            Record("group-fail", "t" .. trackerId)
            return false
        end
        entry.button = nil
        entry.wired = true
        SetResult("wire.t" .. trackerId, "gate group (no button)")
    else
        local slotOk, buttonOrErr = pcall(container.AddAuraSlot, container, slotKey, SAU.FilterForKind(tracker.kind), {
            candidateFilters = filters,
            initializeFrame = function(button)
                entry.button = button
                local wok, werr = pcall(Engine.WireButton, trackerId, tracker, state, entry, button)
                entry.wired = wok and true or false
                SetResult("wire.t" .. trackerId, wok and "ok" or ("FAILED: " .. SafeToString(werr)))
            end,
        })
        if not slotOk then
            SetResult("build.t" .. trackerId, "slot FAILED: " .. SafeToString(buttonOrErr))
            Record("slot-fail", "t" .. trackerId)
            return false
        end
        if not entry.button and buttonOrErr then
            entry.button = buttonOrErr
        end
    end

    -- Unit LAST, then one kick to sync against current auras. "group" binds the
    -- container to the player; the rest of the group is read in plain Lua.
    local engineUnit = SAU.EngineUnitFor(tracker)
    local uok, uerr = pcall(container.SetUnit, container, engineUnit)
    if not uok then
        SetResult("build.t" .. trackerId, "SetUnit FAILED: " .. SafeToString(uerr))
    end
    pcall(container.UpdateAllAuras, container)

    entry.wiredSpellId = tracker.spellId
    entry.wiredUnit = engineUnit
    entry.wiredKind = tracker.kind
    entry.wiredFilterKey = filterKey
    entry.filtersStale = nil
    SetResult("build.t" .. trackerId, "ok (" .. (isMissing and ("group=" .. tostring(entry.gateGroupKey))
        or ("slot=" .. slotKey)) .. " unit=" .. tostring(tracker.unit)
        .. " engine=" .. tostring(engineUnit) .. ")")
    Record("built", "t" .. trackerId)
    return true
end

--------------------------------------------------------------------------------
-- Apply (gated) and the pending queue
--------------------------------------------------------------------------------

local function UpdateFlushTicker()
    if next(pendingWire) then
        if not flushTicker then
            -- AurasSecretNow stays true between pulls in restricted instances;
            -- regen alone would park a mid-key create until the key ends. Poll
            -- the gate at low frequency while anything is queued.
            flushTicker = C_Timer.NewTicker(5, function()
                Engine.TryFlush("ticker")
            end)
        end
    elseif flushTicker then
        flushTicker:Cancel()
        flushTicker = nil
    end
end

-- Full build + element styling pass for one tracker. Queues itself while the
-- button tree is untouchable.
function Engine.ApplyAll(trackerId)
    local tracker = SAU.GetTracker(trackerId)
    local state = SAU._activeStates[trackerId]
    local entry = byTracker[trackerId]
    if not tracker or not state or not entry then return end

    if not Engine.CanDoStructuralWork() then
        pendingWire[trackerId] = true
        UpdateFlushTicker()
        Record("apply-queued", "t" .. trackerId)
        return
    end

    if not EnsureBuilt(trackerId, tracker, state, entry) or not entry.wired then return end
    state.elements = entry.elements
    state.textFrame = entry.textFrame

    -- The same test the styling pass uses: the manual toggle plus the
    -- tracker's and its group's spec gates. ApplyAll also runs from claim,
    -- flush, and Edit Mode entry, so reading tracker.enabled alone here
    -- would revive a container the spec gate had just parked.
    ApplyEnabledState(entry, SAU.IsTrackerActive(trackerId, tracker))

    if tracker.kind == "missingbuff" then
        -- Nothing is bound: the container's own layout size is the gate and
        -- the visible reminder is Scoot-owned, restyled outside the structural
        -- gate (missing.lua). Building the group above was the gated work.
        if SAU.Missing then
            SAU.Missing.Restyle(trackerId, tracker, state)
        end
        Record("applied", "t" .. trackerId)
        return
    end

    -- Static art first, then engine bindings, then fonts/colors, then geometry.
    SAU._ApplyIconMode(trackerId, tracker, state)
    SAU._ApplyShapeStyling(trackerId, tracker, state)
    SAU._ApplyBorders(trackerId, tracker, state)
    SAU._ApplyBarStyling(trackerId, tracker, state)
    Engine.BindForMode(trackerId, tracker, state)
    -- Cadence lock config rides the same gate as the bindings: it asks the
    -- bar just bound for its duration object and sets the lock bar's fill
    -- direction to match the clips BindForMode anchored.
    if SAU.Cadence then
        SAU.Cadence.Configure(trackerId, tracker, state)
    end
    SAU._ApplyTextStyling(trackerId, tracker, state)
    SAU._LayoutElements(trackerId, tracker, state)
    Record("applied", "t" .. trackerId)
end

function Engine.FlushPending(reason)
    if not Engine.CanDoStructuralWork() then return end
    local queued = pendingWire
    pendingWire = {}
    for trackerId in pairs(queued) do
        if SAU.GetTracker(trackerId) and byTracker[trackerId] then
            Engine.ApplyAll(trackerId)
        end
    end
    -- Sweep the whole pool, not just occupied entries: a park that failed
    -- during release leaves its dirty flag on an entry outside byTracker.
    for _, entry in ipairs(pool) do
        if entry.enabledDirty then
            ApplyEnabledState(entry, entry.desiredEnabled)
        end
    end
    if SAU.Groups then
        SAU.Groups.FlushPending()
    end
    Engine.KickAll(reason or "flush")
    UpdateFlushTicker()
end

function Engine.TryFlush(reason)
    if Engine.CanDoStructuralWork() then
        Engine.FlushPending(reason)
    end
end

local markStalePending = false

--- Settle events only: recompute each live entry's filter key once, flag the
-- ones whose Cooldown Manager expansion has actually moved, and let the normal
-- gate rebuild them. A container used to keep the include set it was built
-- with for its whole life, so a talent change left the engine matching the
-- wrong ids with nothing to notice.
--
-- Deferred by a frame on purpose. The expansion memo is invalidated by its own
-- event frame in base/utilities.lua, and two frames registered for one event
-- have no defined order, so comparing in the handler could read the memo the
-- settle event was meant to drop.
function Engine.MarkStaleFilters(reason)
    if markStalePending then return end
    markStalePending = true
    C_Timer.After(0, function()
        markStalePending = false
        local marked = {}
        for trackerId, entry in pairs(byTracker) do
            local tracker = SAU.GetTracker(trackerId)
            if tracker and entry.container and entry.wiredFilterKey then
                local _, key = BuildCandidateFilters(tracker, nil)
                -- Never rebuild toward a degenerate key. An empty or partial
                -- catalog expands to the bare spell id, and acting on that
                -- would retire a good container only to rebuild it again once
                -- the catalog settled.
                local degenerate = key == tostring(tracker.spellId)
                    and #entry.wiredFilterKey > #key
                if key ~= entry.wiredFilterKey and not degenerate then
                    entry.filtersStale = true
                    table.insert(marked, trackerId)
                end
            end
        end
        SetResult("markstale", (reason or "?") .. ": " .. #marked)
        -- ApplyAll rebuilds now when the structural window is open and queues
        -- into pendingWire when it is not, so a respec mid-key lands on regen.
        for _, trackerId in ipairs(marked) do
            Engine.ApplyAll(trackerId)
        end
    end)
end

--------------------------------------------------------------------------------
-- Claim / release
--------------------------------------------------------------------------------

--- Brings a tracker live on a pool entry. Idempotent; safe to call from the
-- reconcile loop. Shell/LEM/position work is combat-legal and happens
-- immediately; only container work routes through the gate.
function Engine.ClaimForTracker(trackerId)
    local tracker = SAU.GetTracker(trackerId)
    if not tracker then return end

    local entry = byTracker[trackerId]
    if not entry then
        entry = AcquireEntry(tracker)
        entry.occupantId = trackerId
        byTracker[trackerId] = entry
    end

    -- Never display a mismatched container while the rebuild waits on the
    -- gate: parking is combat-legal (phase 0 verified), rebuilding is not.
    if entry.container and not ContentMatches(entry, tracker) then
        ApplyEnabledState(entry, false)
    end

    local state = SAU._activeStates[trackerId] or {}
    state.container = entry.visual
    state.shell = entry.shell
    state.entry = entry
    state.elements = entry.elements
    state.textFrame = entry.textFrame
    state.lockBar = entry.lockBar
    SAU._activeStates[trackerId] = state

    entry.shell.editModeName = tracker.name or ("ScootAura " .. trackerId)
    EnsureLEMFrame(entry)
    ApplySavedPosition(entry)

    if SAU._ApplyStyling then
        SAU._ApplyStyling(trackerId, tracker)
    end
    return entry
end

--- Parks a tracker's container and frees its pool entry. The container stays
-- dormant on the entry with its wired-content stamp, so a later claim with
-- identical content can revive it without structural work.
function Engine.ReleaseForTracker(trackerId)
    local entry = byTracker[trackerId]
    pendingWire[trackerId] = nil
    UpdateFlushTicker()
    if not entry then
        SAU._activeStates[trackerId] = nil
        return
    end

    ApplyEnabledState(entry, false)
    if SAU.Cadence then
        SAU.Cadence.OnRelease(entry)
    end
    local state = SAU._activeStates[trackerId]
    if state and Engine.HideEditModePreview then
        Engine.HideEditModePreview(state)
    end
    -- After the preview hide, which re-evaluates the reminder's gate.
    if SAU.Missing then
        SAU.Missing.OnEntryReleased(entry)
    end
    if SAU.Underlay then
        SAU.Underlay.OnEntryReleased(entry)
    end
    -- A grouped visual must not stay parented in the group: the next occupant
    -- of this entry would render inside it.
    if SAU.Groups then
        SAU.Groups.OnEntryReleased(entry)
    end
    entry.shell:Hide()
    entry.occupantId = nil
    byTracker[trackerId] = nil
    SAU._activeStates[trackerId] = nil
    Record("released", "t" .. trackerId)
end

--- Releases every pool occupant whose tracker id is absent from the given
-- live set, or whose entry no longer serves the same content family. Used by
-- the profile reconcile (claim re-verifies content for survivors).
function Engine.ReleaseAllExcept(liveTrackers)
    local toRelease = {}
    for trackerId in pairs(byTracker) do
        if not liveTrackers[trackerId] then
            table.insert(toRelease, trackerId)
        end
    end
    for _, trackerId in ipairs(toRelease) do
        Engine.ReleaseForTracker(trackerId)
    end
end

--------------------------------------------------------------------------------
-- Host sizing (called by the layout pass)
--------------------------------------------------------------------------------

function Engine.SetHostSize(state, w, h)
    local entry = state and state.entry
    if not entry then return end
    -- Stored so the group layout can size members without widget reads.
    entry.hostW, entry.hostH = w, h
    if entry.grouped then
        -- Grouped visuals size themselves; the group layout anchors them.
        entry.visual:SetSize(w, h)
        if SAU.Groups then SAU.Groups.RequestReflow() end
    else
        -- Standalone: the shell is the drag unit; the visual follows via
        -- SetAllPoints.
        entry.shell:SetSize(w, h)
    end
end

--------------------------------------------------------------------------------
-- Kicks (target/focus containers do not self-refresh on retarget)
--------------------------------------------------------------------------------

function Engine.KickUnit(unitToken, reason)
    for trackerId, entry in pairs(byTracker) do
        local tracker = SAU.GetTracker(trackerId)
        if tracker and tracker.unit == unitToken and entry.container then
            local ok, err = pcall(entry.container.UpdateAllAuras, entry.container)
            if not ok then
                SetResult("kick.t" .. trackerId, "FAILED (" .. (reason or "?") .. "): " .. SafeToString(err))
            end
        end
    end
end

--- Resyncs one tracker's container. A container processes only while shown, so
-- a tracker hidden by the combat gate has parsed nothing since it went dark;
-- UpdateAllAuras is the same call KickUnit already makes in combat.
function Engine.KickTracker(trackerId, reason)
    local entry = byTracker[trackerId]
    if not entry or not entry.container then return end
    local ok, err = pcall(entry.container.UpdateAllAuras, entry.container)
    if not ok then
        SetResult("kick.t" .. trackerId, "FAILED (" .. (reason or "?") .. "): " .. SafeToString(err))
    end
end

function Engine.KickAll(reason)
    for trackerId, entry in pairs(byTracker) do
        if entry.container then
            local ok, err = pcall(entry.container.UpdateAllAuras, entry.container)
            if not ok then
                SetResult("kick.t" .. trackerId, "FAILED (" .. (reason or "?") .. "): " .. SafeToString(err))
            end
        end
    end
end
