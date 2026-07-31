-- inspect.lua - Centralized passive inspect service (group spec + item level)
--
-- One owner for every NotifyInspect the addon ever sends. Consumers (damage
-- meter export, reports) call addon.Inspect:EnsureStarted() and read the
-- cache; they never touch the inspect API themselves.
--
-- The service is aggressively passive. The player's own Inspect (right-click
-- or any other path) must always win: every foreign NotifyInspect is detected
-- through a hooksecurefunc and suspends scanning immediately, without calling
-- ClearInspectPlayer, and scanning resumes only after the InspectFrame is
-- closed and a quiet period has passed. The single invariant: NotifyInspect
-- is sent only from the ticker, behind CanSendNow() — never in combat, never
-- while the InspectFrame is shown, never during a quiet period, never with a
-- request already in flight.
local addonName, addon = ...

addon.Inspect = addon.Inspect or {}
local Inspect = addon.Inspect

--------------------------------------------------------------------------------
-- Tuning
--------------------------------------------------------------------------------

local CACHE_TTL        = 300   -- seconds before a cached member is re-queued
local CADENCE          = 4.0   -- ticker period; 39 members refresh in ~156s, inside the TTL
local FOREIGN_QUIET    = 10    -- seconds of silence after any foreign NotifyInspect
local CLOSE_GRACE      = 5     -- extra quiet after the InspectFrame closes (users chain-inspect)
local INFLIGHT_TIMEOUT = 8     -- give up on our own request if INSPECT_READY never arrives

-- Scan-cycle states. Foreign/combat suspensions keep the ticker alive so it
-- can observe the resume condition; IDLE means the ticker itself is stopped.
local STATE_IDLE              = "IDLE"
local STATE_SCANNING          = "SCANNING"
local STATE_AWAITING          = "AWAITING"
local STATE_SUSPENDED_FOREIGN = "SUSPENDED_FOREIGN"
local STATE_SUSPENDED_COMBAT  = "SUSPENDED_COMBAT"

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

local cache = {}          -- guid -> { name, itemLevel, specID, specName, classFilename, specIcon, role, time }
local queue = {}          -- array of { guid, unit }
local state = STATE_IDLE
local pending = nil       -- { guid, unit, sentAt } for our own in-flight request
local ticker = nil
local eventFrame = nil
local started = false
local serviceCallInProgress = false  -- discriminates our NotifyInspect from foreign ones in the hook
local quietUntil = 0
local frameWasShown = false          -- tracks the InspectFrame shown->hidden transition
local pauseReasons = {}              -- reason -> true; any entry blocks sends

--------------------------------------------------------------------------------
-- Guarded reads
--------------------------------------------------------------------------------

local function IsInspectFrameShown()
    -- Blizzard_InspectUI is load-on-demand; the frame may not exist yet.
    local f = _G["InspectFrame"]
    if not f then return false end
    local ok, shown = pcall(f.IsShown, f)
    return ok and shown or false
end

-- UnitName can return a secret in identity-restricted content; never operate
-- on the value until issecretvalue proves it plain.
local function SafeUnitName(unit)
    local ok, n = pcall(UnitName, unit)
    if not ok or n == nil then return nil end
    if issecretvalue and issecretvalue(n) then return nil end
    if type(n) ~= "string" then return nil end
    return n:match("^([^%-]+)") or n
end

-- UnitGUID returns a secret for identity-restricted units (nameplates in
-- instanced content). pcall success and even a passed truthiness test do not
-- prove the value plain — a secret key at cache[guid] still throws.
local function SafeUnitGUID(unit)
    local ok, guid = pcall(UnitGUID, unit)
    if not ok or guid == nil then return nil end
    if issecretvalue and issecretvalue(guid) then return nil end
    if type(guid) ~= "string" then return nil end
    return guid
end

local function IsGroupUnit(unit)
    local okP, inParty = pcall(UnitInParty, unit)
    if okP and inParty then return true end
    local okR, inRaid = pcall(UnitInRaid, unit)
    return okR and inRaid ~= nil
end

--------------------------------------------------------------------------------
-- Queue
--------------------------------------------------------------------------------

local function RebuildQueue()
    wipe(queue)
    local now = GetTime()

    local prefix, count
    if IsInRaid() then
        prefix, count = "raid", GetNumGroupMembers()
    elseif IsInGroup() then
        prefix, count = "party", GetNumGroupMembers() - 1
    else
        return
    end

    for i = 1, count do
        local unit = prefix .. i
        local guid = SafeUnitGUID(unit)
        if guid then
            local isSelfOk, isSelf = pcall(UnitIsUnit, unit, "player")
            if not (isSelfOk and isSelf) then
                local cached = cache[guid]
                if not cached or (now - (cached.time or 0)) > CACHE_TTL then
                    local canOk, canInspect = pcall(CanInspect, unit, false)
                    if canOk and canInspect then
                        table.insert(queue, { guid = guid, unit = unit })
                    end
                end
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Sending
--------------------------------------------------------------------------------

local function CanSendNow()
    return started
        and state == STATE_SCANNING
        and pending == nil
        and next(pauseReasons) == nil
        and not InCombatLockdown()
        and not IsInspectFrameShown()
        and GetTime() >= quietUntil
end

local function SendNextInspect()
    if #queue == 0 then return end
    local entry = table.remove(queue, 1)

    -- The roster can shift between queue build and send; a unit token that no
    -- longer holds this GUID would inspect the wrong player.
    local guid = SafeUnitGUID(entry.unit)
    if not guid or guid ~= entry.guid then return end

    local canOk, canInspect = pcall(CanInspect, entry.unit, false)
    if not canOk or not canInspect then return end

    -- hooksecurefunc post-hooks run synchronously inside NotifyInspect, so the
    -- flag window exactly brackets our own call; pcall guarantees the clear
    -- even if another hook on NotifyInspect errors.
    pending = { guid = entry.guid, unit = entry.unit, sentAt = GetTime() }
    state = STATE_AWAITING
    serviceCallInProgress = true
    pcall(NotifyInspect, entry.unit)
    serviceCallInProgress = false
end

--------------------------------------------------------------------------------
-- Foreign inspect detection
--------------------------------------------------------------------------------

local function EnterForeignBackoff()
    quietUntil = GetTime() + FOREIGN_QUIET
    -- Abandon our in-flight request without ClearInspectPlayer: the loaded
    -- inspect data now belongs to whoever asked for it.
    pending = nil
    if state == STATE_SCANNING or state == STATE_AWAITING then
        state = STATE_SUSPENDED_FOREIGN
    end
end

local function OnNotifyInspectHook()
    if serviceCallInProgress then return end
    if not started then return end
    EnterForeignBackoff()
end

--------------------------------------------------------------------------------
-- Harvest
--------------------------------------------------------------------------------

-- Reads whatever inspect data is currently loaded for `unit` into the cache.
-- Used for our own completed requests and, opportunistically, for foreign
-- INSPECT_READY events — the data is already loaded either way, so reading it
-- costs no additional inspect request.
local function HarvestInspectData(guid, unit)
    local entry = cache[guid] or {}
    local captured = false

    local ilvlOk, ilvl = pcall(C_PaperDollInfo.GetInspectItemLevel, unit)
    if ilvlOk and type(ilvl) == "number" and ilvl > 0 then
        entry.itemLevel = math.floor(ilvl)
        captured = true
    end

    local specOk, specID = pcall(GetInspectSpecialization, unit)
    if specOk and type(specID) == "number" and specID > 0 then
        entry.specID = specID
        -- Static spec data (never secret): id, name, description, icon, role, classFile
        local infoOk, _, specName, _, specIcon, role, classFile = pcall(GetSpecializationInfoByID, specID)
        if infoOk and specName then
            entry.specName = specName
            entry.specIcon = specIcon
            entry.role = role
            entry.classFilename = classFile
        end
        captured = true
    end

    local name = SafeUnitName(unit)
    if name then
        entry.name = name
        captured = true
    end

    if not captured then return false end

    entry.time = GetTime()
    cache[guid] = entry
    addon:SendMessage("SCOOT_INSPECT_UPDATED", guid, entry)
    return true
end

--------------------------------------------------------------------------------
-- INSPECT_READY
--------------------------------------------------------------------------------

local function OnInspectReady(inspecteeGUID)
    -- The payload is compared against pending.guid and used as a cache key;
    -- reject secrets before either. type() is safe on nil and on secrets.
    if type(inspecteeGUID) ~= "string" then return end
    if issecretvalue and issecretvalue(inspecteeGUID) then return end

    if pending and pending.guid == inspecteeGUID then
        local unit = pending.unit
        pending = nil
        if state == STATE_AWAITING then
            state = STATE_SCANNING
        end
        HarvestInspectData(inspecteeGUID, unit)

        -- Release the inspect slot only when it is provably still ours: the
        -- InspectFrame is not up and no foreign inspect claimed it meanwhile.
        if not IsInspectFrameShown() and GetTime() >= quietUntil then
            pcall(ClearInspectPlayer)
        end
        return
    end

    -- Not ours: the user's own inspect, or one of our abandoned requests
    -- arriving late. Either way the data is loaded — harvest it for free.
    -- Never ClearInspectPlayer here; the slot belongs to that session.
    local okTok, unit = pcall(UnitTokenFromGUID, inspecteeGUID)
    if okTok and unit and IsGroupUnit(unit) then
        local isSelfOk, isSelf = pcall(UnitIsUnit, unit, "player")
        if not (isSelfOk and isSelf) then
            local guid = SafeUnitGUID(unit)
            if guid == inspecteeGUID then
                HarvestInspectData(inspecteeGUID, unit)
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Ticker
--------------------------------------------------------------------------------

local function StartTicker()
    if ticker then return end
    if state == STATE_IDLE or state == STATE_SUSPENDED_COMBAT then
        state = STATE_SCANNING
    end
    ticker = C_Timer.NewTicker(CADENCE, function()
        if InCombatLockdown() then return end

        -- Poll the InspectFrame: a shown frame suspends scanning outright;
        -- the shown->hidden transition arms the close grace so we don't steal
        -- the slot between the user's consecutive inspects.
        if IsInspectFrameShown() then
            frameWasShown = true
            if state == STATE_SCANNING or state == STATE_AWAITING then
                pending = nil
                state = STATE_SUSPENDED_FOREIGN
            end
            return
        elseif frameWasShown then
            frameWasShown = false
            local graceEnd = GetTime() + CLOSE_GRACE
            if graceEnd > quietUntil then quietUntil = graceEnd end
        end

        if state == STATE_SUSPENDED_FOREIGN and GetTime() >= quietUntil then
            state = STATE_SCANNING
        end

        if state == STATE_AWAITING and pending
            and (GetTime() - pending.sentAt) > INFLIGHT_TIMEOUT then
            -- INSPECT_READY never came (target out of range, etc.). Release
            -- our slot bookkeeping; a late event is still harvested as
            -- foreign. No ClearInspectPlayer — nothing of ours is loaded.
            pending = nil
            state = STATE_SCANNING
        end

        if CanSendNow() then
            if #queue == 0 then
                RebuildQueue()
            end
            SendNextInspect()
        end
    end)
end

local function StopTicker()
    if ticker then
        ticker:Cancel()
        ticker = nil
    end
    pending = nil
    state = STATE_IDLE
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

local function OnEvent(self, event, ...)
    if event == "INSPECT_READY" then
        OnInspectReady(...)
    elseif event == "GROUP_ROSTER_UPDATE" then
        RebuildQueue()
        if IsInGroup() and not InCombatLockdown() then
            StartTicker()
        elseif not IsInGroup() then
            StopTicker()
        end
    elseif event == "PLAYER_REGEN_DISABLED" then
        wipe(queue)
        StopTicker()
        state = STATE_SUSPENDED_COMBAT
    elseif event == "PLAYER_REGEN_ENABLED" then
        C_Timer.After(2, function()
            if not InCombatLockdown() and IsInGroup() then
                RebuildQueue()
                StartTicker()
            end
        end)
    elseif event == "PLAYER_ENTERING_WORLD" then
        C_Timer.After(5, function()
            if not InCombatLockdown() and IsInGroup() then
                RebuildQueue()
                StartTicker()
            end
        end)
    elseif event == "UNIT_INVENTORY_CHANGED" then
        -- Freshness only: mark the member stale and let the slow scan pick
        -- them up. Never triggers an immediate inspect. Fires for EVERY unit
        -- token (frame-wide RegisterEvent), including nameplates whose GUIDs
        -- are secret in identity-restricted content — SafeUnitGUID drops
        -- those; a secret GUID can never be a cache hit anyway.
        local unit = ...
        if unit then
            local guid = SafeUnitGUID(unit)
            if guid and cache[guid] then
                local isSelfOk, isSelf = pcall(UnitIsUnit, unit, "player")
                if not (isSelfOk and isSelf) then
                    cache[guid].time = 0
                end
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

-- Idempotent. The file loads inert; nothing is hooked, registered, or
-- scheduled until the first consumer calls this. The NotifyInspect hook is
-- irreversible, so it must only ever install here.
function Inspect:EnsureStarted()
    if started then return end
    started = true

    hooksecurefunc("NotifyInspect", OnNotifyInspectHook)

    eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("INSPECT_READY")
    eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("UNIT_INVENTORY_CHANGED")
    eventFrame:SetScript("OnEvent", OnEvent)

    if IsInGroup() and not InCombatLockdown() then
        RebuildQueue()
        StartTicker()
    end
end

function Inspect:IsStarted()
    return started
end

-- Returns the cache entry (read-only by convention) or nil. No TTL filtering:
-- stale data beats a blank cell for display; entry.time lets callers decide.
function Inspect:GetUnitInfo(guid)
    -- Callers pass raw UnitGUID results; a secret key would throw on index.
    if type(guid) ~= "string" then return nil end
    if issecretvalue and issecretvalue(guid) then return nil end
    return cache[guid]
end

function Inspect:GetAll()
    return cache
end

-- Name-based fallback for callers whose GUIDs may not match the cache (the
-- damage meter's historic segments can outlive roster GUID mappings).
function Inspect:FindByName(name)
    if type(name) ~= "string" then return nil end
    if issecretvalue and issecretvalue(name) then return nil end
    if name == "" then return nil end
    for _, entry in pairs(cache) do
        if entry.name == name and entry.itemLevel then
            return entry
        end
    end
    return nil
end

function Inspect:IsScanning()
    return started and ticker ~= nil
        and (state == STATE_SCANNING or state == STATE_AWAITING)
end

-- True while the service still has members it intends to reach: the ticker is
-- alive (so combat, solo, and a never-started service all read false) and
-- either work is queued or a request is in flight. Going false is exact, not a
-- guess: RebuildQueue only enqueues members who are stale AND CanInspect,
-- SendNextInspect removes each on send, and a timeout clears pending without
-- re-queueing — so empty + nothing in flight means anyone still blank is not
-- coming. The tick's own refill (rebuild then send) happens inside one
-- callback, so an outside reader can never catch a false-empty.
--
-- Deliberately true through SUSPENDED_FOREIGN, which resumes on its own: a
-- display that blinked off for the backoff would be claiming the scan had
-- finished. That, and never going false at all, is why IsScanning is the wrong
-- predicate for a progress indicator.
function Inspect:HasPendingWork()
    -- ticker ~= nil is load-bearing: GROUP_ROSTER_UPDATE rebuilds the queue
    -- unconditionally, even in combat, so a battle-rez mid-fight refills it
    -- while nothing can send.
    return started and ticker ~= nil and (#queue > 0 or pending ~= nil)
end

function Inspect:MarkStale(guid)
    if type(guid) ~= "string" then return end
    if issecretvalue and issecretvalue(guid) then return end
    local entry = cache[guid]
    if entry then entry.time = 0 end
end

function Inspect:Pause(reason)
    pauseReasons[reason or "default"] = true
end

function Inspect:Resume(reason)
    pauseReasons[reason or "default"] = nil
end

-- Debug snapshot for /scoot debug inspect.
function Inspect:_DebugState()
    local count = 0
    for _ in pairs(cache) do count = count + 1 end
    local reasons = {}
    for r in pairs(pauseReasons) do table.insert(reasons, tostring(r)) end
    return {
        started = started,
        state = state,
        tickerRunning = ticker ~= nil,
        queueLength = #queue,
        pendingGuid = pending and pending.guid or nil,
        pendingUnit = pending and pending.unit or nil,
        quietRemaining = math.max(0, quietUntil - GetTime()),
        frameShown = IsInspectFrameShown(),
        cacheCount = count,
        pauseReasons = table.concat(reasons, ", "),
    }
end
