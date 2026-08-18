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

local CDM_CATEGORIES = (function()
    local cat = Enum and Enum.CooldownViewerCategory
    if cat then
        local out = {}
        for _, v in pairs(cat) do
            if type(v) == "number" then table.insert(out, v) end
        end
        table.sort(out)
        if #out > 0 then return out end
    end
    return { 0, 1, 2, 3 }
end)()

local function PlainId(v)
    if type(v) == "number" and not issecretvalue(v) and v > 0 then return v end
    return nil
end

-- Every CDM entry whose identity (base spell, override, or tooltip override)
-- is the looked-up ID contributes its whole aura family: base, override,
-- tooltip override, and every linked aura ID. The union across entries is the
-- point. Blizzard keys several entries on one hidden base spell and only some
-- of them carry the real aura as a linked spell: Flame Shock's CDM base is
-- 470411 (the debuff is 188389, never a base anywhere), and for Elemental the
-- Essential entry lists no linked spells while the Tracked Bar entry links
-- 188389. Stopping at the first match built {470411, 470057} and the tracker
-- never fired.
local function ExpandFromCDM(include, lookupSpellId)
    if not lookupSpellId or not C_CooldownViewer then return end
    if not C_CooldownViewer.GetCooldownViewerCategorySet
        or not C_CooldownViewer.GetCooldownViewerCooldownInfo then
        return
    end
    for _, category in ipairs(CDM_CATEGORIES) do
        local ok, cooldownIDs = pcall(C_CooldownViewer.GetCooldownViewerCategorySet, category, true)
        if ok and type(cooldownIDs) == "table" and not issecretvalue(cooldownIDs) then
            for _, cooldownID in ipairs(cooldownIDs) do
                if not issecretvalue(cooldownID) then
                    local iok, info = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, cooldownID)
                    if iok and type(info) == "table" and not issecretvalue(info) then
                        local sid = PlainId(info.spellID)
                        local oid = PlainId(info.overrideSpellID)
                        local tid = PlainId(info.overrideTooltipSpellID)
                        if sid == lookupSpellId or oid == lookupSpellId or tid == lookupSpellId then
                            if sid then include[sid] = true end
                            if oid then include[oid] = true end
                            if tid then include[tid] = true end
                            local linked = info.linkedSpellIDs
                            if type(linked) == "table" and not issecretvalue(linked) then
                                for _, lid in ipairs(linked) do
                                    lid = PlainId(lid)
                                    if lid then include[lid] = true end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

local function BuildCandidateFilters(tracker, trackerId)
    local include = { [tracker.spellId] = true }
    pcall(ExpandFromCDM, include, tracker.spellId)
    if trackerId then
        local ids = {}
        for id in pairs(include) do table.insert(ids, id) end
        table.sort(ids)
        SetResult("filters.t" .. trackerId, table.concat(ids, ","))
    end
    return { includeSpellIDs = include }
end

Engine._BuildCandidateFilters = BuildCandidateFilters

--------------------------------------------------------------------------------
-- Positions
--------------------------------------------------------------------------------

local function GetActiveLayoutName()
    local lib = LibStub("LibEditMode", true)
    local name = lib and lib:GetActiveLayoutName()
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
    local profile = addon.db and addon.db.profile
    if not profile or not key or not layoutName then return end
    local store = rawget(profile, "scootAuraPositions")
    if type(store) ~= "table" then
        store = {}
        profile.scootAuraPositions = store
    end
    store[key] = store[key] or {}
    store[key][layoutName] = { point = point, x = x, y = y }
end

-- Shared with groups.lua ("g<gid>" keys live in the same store).
Engine.SavePosition = SavePosition
Engine.GetActiveLayoutName = GetActiveLayoutName

-- LibEditMode applies nothing at AddFrame time, so every claim explicitly
-- restores the occupant's saved position (or the entry default).
local function ApplySavedPosition(entry)
    if not entry.occupantId then return end
    local profile = addon.db and addon.db.profile
    local store = profile and rawget(profile, "scootAuraPositions")
    local perKey = store and store["t" .. entry.occupantId]
    local layoutName = GetActiveLayoutName()
    local pos = layoutName and perKey and perKey[layoutName]
    if not (pos and pos.point) then
        pos = DefaultPositionFor(entry)
    end
    entry.shell:ClearAllPoints()
    entry.shell:SetPoint(pos.point, pos.x or 0, pos.y or 0)
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

local function EnsureLEMFrame(entry)
    if entry.lemRegistered then return end
    local lib = LibStub("LibEditMode", true)
    if not lib then return end
    entry.lemRegistered = true

    local dp = DefaultPositionFor(entry)
    lib:AddFrame(entry.shell, function(frame, layoutName, point, x, y)
        if point and x and y then
            frame:ClearAllPoints()
            frame:SetPoint(point, x, y)
        end
        if layoutName and entry.occupantId then
            local savedPoint, _, _, savedX, savedY = frame:GetPoint(1)
            if savedPoint then
                SavePosition("t" .. entry.occupantId, layoutName, savedPoint, savedX, savedY)
            else
                SavePosition("t" .. entry.occupantId, layoutName, point, x, y)
            end
        end
    end, { point = dp.point, x = dp.x, y = dp.y }, nil)

    local Brand = addon.EditMode and addon.EditMode.Brand
    if Brand then
        Brand:Register(entry.shell, { navKey = SAU.NAV_KEY, mirror = TrackerEditModeMirror })
    end

    -- Frames added while Edit Mode is open miss the enter pass; without this
    -- the new frame is undraggable until Edit Mode bounces.
    if lib.isEditing then
        local sel = lib.frameSelections and lib.frameSelections[entry.shell]
        if sel then pcall(sel.ShowHighlighted, sel) end
    end
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

local function ContentMatches(entry, tracker)
    return entry.container ~= nil
        and entry.wiredSpellId == tracker.spellId
        and entry.wiredUnit == tracker.unit
        and entry.wiredKind == tracker.kind
end

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

    if isMissing then
        -- No slot and no button: nothing inside the container is ever bound
        -- or drawn. The group's frames only feed the layout's size.
        local gok, gerr = SAU.Missing.AddGateGroup(trackerId, tracker, entry, container,
            BuildCandidateFilters(tracker, trackerId))
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
            candidateFilters = BuildCandidateFilters(tracker, trackerId),
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

    -- Unit LAST, then one kick to sync against current auras.
    local uok, uerr = pcall(container.SetUnit, container, tracker.unit)
    if not uok then
        SetResult("build.t" .. trackerId, "SetUnit FAILED: " .. SafeToString(uerr))
    end
    pcall(container.UpdateAllAuras, container)

    entry.wiredSpellId = tracker.spellId
    entry.wiredUnit = tracker.unit
    entry.wiredKind = tracker.kind
    SetResult("build.t" .. trackerId, "ok (" .. (isMissing and ("group=" .. tostring(entry.gateGroupKey))
        or ("slot=" .. slotKey)) .. " unit=" .. tracker.unit .. ")")
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
