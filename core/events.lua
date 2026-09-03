-- events.lua - Shared event bus (refactor #33).
--
-- One private AceEvent listener registers a single trampoline per event name;
-- subscribers live in insertion-ordered arrays, so intra-Scoot dispatch order is
-- deterministic. CallbackHandler alone cannot provide that: it dispatches in
-- hash order and keeps one callback per (self, event) pair. Handlers receive
-- (event, ...) with the full payload and no frame self. Each handler is called
-- through securecallfunction so one erroring handler cannot kill the rest or
-- spread taint.
--
-- The public API exposes no frame-level unregister of any kind; frame
-- (un)registration happens only through AceEvent's refcounted OnUsed/OnUnused
-- (see the core/nativeframe.lua policy on UnregisterAllEvents).
local addonName, addon = ...

local Events = {}
addon.Events = Events

-- Private listener object. Embedding on the public table would let any caller's
-- RegisterEvent replace the trampoline, since CallbackHandler stores one
-- callback per (self, event). The addon-wide AceEvent mixin from Scoot.lua is a
-- different self in the same registry; both share AceEvent30Frame.
local listener = LibStub("AceEvent-3.0"):Embed({})

local securecallfunction = securecallfunction
local InCombatLockdown = InCombatLockdown

-- registry[event] = { list = { entry... }, live = n, dispatching = n, dirty = bool }
-- entry = { owner = string, event = string, fn = function, once = bool, dead = bool }
local registry = {}
local unsupported = {}     -- event names this client build rejects (PTR drift)
local componentOwners = {} -- owner ids registered via Component:On, for reset

local function isEventSupported(event)
    if unsupported[event] then return false end
    if C_EventUtils and C_EventUtils.IsEventValid and not C_EventUtils.IsEventValid(event) then
        unsupported[event] = true
        return false
    end
    return true
end

local compact -- forward declaration

local function trampoline(event, ...)
    local bucket = registry[event]
    if not bucket then return end
    bucket.dispatching = bucket.dispatching + 1
    local list = bucket.list
    local n = #list -- snapshot: handlers added during dispatch fire next time
    for i = 1, n do
        local entry = list[i]
        if entry and not entry.dead then
            if entry.once then
                -- Tombstone before the call so a re-entrant fire cannot run it twice.
                entry.dead = true
                bucket.live = bucket.live - 1
                bucket.dirty = true
            end
            securecallfunction(entry.fn, event, ...)
        end
    end
    bucket.dispatching = bucket.dispatching - 1
    if bucket.dispatching == 0 and bucket.dirty then
        compact(event, bucket)
    end
end

-- Rebuild a bucket's list without tombstones; drop the bucket (and the
-- underlying registration) when nothing live remains. Only called when no
-- dispatch is in flight.
compact = function(event, bucket)
    bucket.dirty = false
    if bucket.live <= 0 then
        registry[event] = nil
        pcall(listener.UnregisterEvent, listener, event)
        return
    end
    local list = bucket.list
    local kept = 0
    for i = 1, #list do
        local entry = list[i]
        if not entry.dead then
            kept = kept + 1
            list[kept] = entry
        end
    end
    for i = #list, kept + 1, -1 do
        list[i] = nil
    end
end

local HandleIndex = {}
local HandleMT = { __index = HandleIndex }

function HandleIndex:Off()
    if self.dead then return end
    self.dead = true
    local bucket = registry[self.event]
    if bucket then
        bucket.live = bucket.live - 1
        bucket.dirty = true
        if bucket.dispatching == 0 then
            compact(self.event, bucket)
        end
    end
end

function HandleIndex:IsActive()
    return not self.dead
end

-- Returned for events this client build rejects: inert, already dead.
local DEAD_HANDLE = setmetatable({ dead = true, event = "", owner = "" }, HandleMT)

local function register(owner, event, fn, once)
    if type(owner) ~= "string" then error("Events: owner must be a string id", 3) end
    if type(event) ~= "string" then error("Events: event must be a string", 3) end
    if type(fn) ~= "function" then error("Events: handler must be a function", 3) end
    if not isEventSupported(event) then return DEAD_HANDLE end

    local bucket = registry[event]
    if not bucket then
        -- pcall: frame:RegisterEvent hard-errors on names the client rejects,
        -- the same contract as safeRegisterEvent in core/init.lua.
        local ok = pcall(listener.RegisterEvent, listener, event, trampoline)
        if not ok then
            pcall(listener.UnregisterEvent, listener, event) -- purge a half-registration
            unsupported[event] = true
            return DEAD_HANDLE
        end
        bucket = { list = {}, live = 0, dispatching = 0, dirty = false }
        registry[event] = bucket
    end

    local entry = setmetatable({ owner = owner, event = event, fn = fn, once = once or nil }, HandleMT)
    bucket.list[#bucket.list + 1] = entry
    bucket.live = bucket.live + 1
    return entry
end

-- Persistent subscription. Returns a handle with :Off() and :IsActive().
function Events.On(owner, event, fn)
    return register(owner, event, fn, false)
end

-- One-shot subscription; the entry is tombstoned before its only call.
function Events.Once(owner, event, fn)
    return register(owner, event, fn, true)
end

function Events.UnregisterAll(owner)
    for event, bucket in pairs(registry) do
        local changed = false
        for i = 1, #bucket.list do
            local entry = bucket.list[i]
            if not entry.dead and entry.owner == owner then
                entry.dead = true
                bucket.live = bucket.live - 1
                changed = true
            end
        end
        if changed then
            bucket.dirty = true
            if bucket.dispatching == 0 then
                compact(event, bucket)
            end
        end
    end
end

-- Component:On registrations mark their owner here so InitializeComponents'
-- wipe-and-rerun tears the previous generation down before initializers re-run.
function Events._MarkComponentOwner(id)
    componentOwners[id] = true
end

function Events.ResetComponentOwners()
    for id in pairs(componentOwners) do
        Events.UnregisterAll(id)
    end
    componentOwners = {}
end

--------------------------------------------------------------------------------
-- Combat deferral. This is refactor #28's phase-1 primitive, shipped here; #28
-- migrates the remaining pending-set watcher frames onto it.
--------------------------------------------------------------------------------
local combatQueue = {}
local combatKeyed = {}
local combatHandle = nil

local function drainCombatQueue()
    -- Regen can fire with lockdown already re-engaged; run nothing and leave the
    -- queue and armed listener intact for the next edge.
    if InCombatLockdown and InCombatLockdown() then return end
    -- Swap before draining so a re-queue from inside a drained fn lands in the
    -- next combat cycle instead of extending this loop.
    local q = combatQueue
    combatQueue, combatKeyed = {}, {}
    if combatHandle then
        combatHandle:Off()
        combatHandle = nil
    end
    for i = 1, #q do
        securecallfunction(q[i].fn)
    end
end

-- Runs fn NOW (synchronously) if out of combat and returns true; otherwise
-- queues it for the next PLAYER_REGEN_ENABLED and returns false. A queued entry
-- with the same key is replaced in place: latest fn wins, queue position kept.
function Events.RunOutOfCombat(fn, key)
    if type(fn) ~= "function" then error("Events.RunOutOfCombat: fn must be a function", 2) end
    if not (InCombatLockdown and InCombatLockdown()) then
        fn()
        return true
    end
    if key then
        local entry = combatKeyed[key]
        if entry then
            entry.fn = fn
            return false
        end
        entry = { fn = fn }
        combatKeyed[key] = entry
        combatQueue[#combatQueue + 1] = entry
    else
        combatQueue[#combatQueue + 1] = { fn = fn }
    end
    if not combatHandle then
        combatHandle = Events.On("ScootEvents", "PLAYER_REGEN_ENABLED", drainCombatQueue)
    end
    return false
end

--------------------------------------------------------------------------------
-- World-entered bootstrap latch. Each callback fires once, on the first
-- PLAYER_ENTERING_WORLD of the session; a late subscriber runs immediately with
-- the recorded arguments (the LibEditMode late-'layout' subscriber precedent).
-- For per-zone-in behavior use Events.On(owner, "PLAYER_ENTERING_WORLD", fn).
--------------------------------------------------------------------------------
local worldEntered = false
local worldLogin, worldReload
local worldQueue = {}

Events.Once("ScootEvents", "PLAYER_ENTERING_WORLD", function(_, isInitialLogin, isReloadingUi)
    worldEntered = true
    worldLogin, worldReload = isInitialLogin, isReloadingUi
    local q = worldQueue
    worldQueue = nil
    for i = 1, #q do
        securecallfunction(q[i], isInitialLogin, isReloadingUi)
    end
end)

-- fn(isInitialLogin, isReloadingUi); returns true if run immediately.
function Events.OnWorldEntered(fn)
    if type(fn) ~= "function" then error("Events.OnWorldEntered: fn must be a function", 2) end
    if worldEntered then
        fn(worldLogin, worldReload)
        return true
    end
    worldQueue[#worldQueue + 1] = fn
    return false
end

--------------------------------------------------------------------------------
-- Keyed ADDON_LOADED. Runs fn(name) NOW if that addon is already loaded;
-- otherwise queues it for the addon's ADDON_LOADED. The underlying registration
-- is dropped once the pending map drains, so ADDON_LOADED (which fires for
-- every addon) stops waking the module.
--------------------------------------------------------------------------------
local pendingAddons = nil -- [name] = { fn, ... }
local pendingAddonCount = 0
local addonLoadedHandle = nil

local function isAddonLoaded(name)
    if C_AddOns and C_AddOns.IsAddOnLoaded then
        return C_AddOns.IsAddOnLoaded(name)
    end
    if IsAddOnLoaded then
        return IsAddOnLoaded(name)
    end
    return false
end

local function onAddonLoaded(_, loadedName)
    local list = pendingAddons and pendingAddons[loadedName]
    if not list then return end
    pendingAddons[loadedName] = nil
    pendingAddonCount = pendingAddonCount - 1
    if pendingAddonCount == 0 and addonLoadedHandle then
        addonLoadedHandle:Off()
        addonLoadedHandle = nil
    end
    for i = 1, #list do
        securecallfunction(list[i], loadedName)
    end
end

-- fn(name); returns true if run immediately.
function Events.OnAddonLoaded(name, fn)
    if type(name) ~= "string" then error("Events.OnAddonLoaded: name must be a string", 2) end
    if type(fn) ~= "function" then error("Events.OnAddonLoaded: fn must be a function", 2) end
    if isAddonLoaded(name) then
        fn(name)
        return true
    end
    pendingAddons = pendingAddons or {}
    local list = pendingAddons[name]
    if not list then
        list = {}
        pendingAddons[name] = list
        pendingAddonCount = pendingAddonCount + 1
    end
    list[#list + 1] = fn
    if not addonLoadedHandle then
        addonLoadedHandle = Events.On("ScootEvents", "ADDON_LOADED", onAddonLoaded)
    end
    return false
end

--------------------------------------------------------------------------------
-- Introspection for verification: /run ScootAddon.Events.Dump()
--------------------------------------------------------------------------------
function Events.Dump()
    local lines = {}
    local shown = false
    for event, bucket in pairs(registry) do
        lines[#lines + 1] = ("%s: %d live"):format(event, bucket.live)
        shown = true
    end
    if not shown then
        lines[#lines + 1] = "(no live registrations)"
    end
    table.sort(lines)
    lines[#lines + 1] = ("combat queue: %d"):format(#combatQueue)
    if pendingAddons then
        for name, list in pairs(pendingAddons) do
            lines[#lines + 1] = ("pending addon: %s (%d)"):format(name, #list)
        end
    end
    for event in pairs(unsupported) do
        lines[#lines + 1] = "unsupported: " .. event
    end
    if addon.DebugShowWindow then
        addon.DebugShowWindow(("Events (%d)"):format(#lines), lines)
    else
        for _, line in ipairs(lines) do print(line) end
    end
end
