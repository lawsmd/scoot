--------------------------------------------------------------------------------
-- core/dynamiclayouts/resolver.lua
-- The Dynamic Layouts trigger resolver: the one owner of the base-or-dynamic
-- answer. The dynamic state holds while every enabled trigger reads false;
-- any enabled trigger reading true means base. Subscribers hear edges, never
-- states: a callback fires only when the answer changes, and the current
-- answer is a getter.
--
-- Every event arms one deferred resolution and coalesces; the resolution
-- re-reads every probe and never trusts event arguments. The one synchronous
-- carve-out is PLAYER_REGEN_DISABLED, whose handler runs before lockdown
-- engages, so the combat-entry edge reaches subscribers while protected
-- writes are still legal.
--
-- Edit Mode outranks the triggers: while it is open the base state holds and
-- resolutions return early. Listed on Camelot.toc; written against shared
-- primitives only, so adoption by the other addon is a TOC listing.
--------------------------------------------------------------------------------

local addonName, addon = ...

addon.DynamicLayouts = addon.DynamicLayouts or {}
local DL = addon.DynamicLayouts

local Resolver = {}
DL.Resolver = Resolver

local OWNER = "camelotDynamicLayouts"

--------------------------------------------------------------------------------
-- Probes
--------------------------------------------------------------------------------

-- Instance types the insideInstance trigger counts. Whether pvp and arena
-- belong here is an open product question; the answer is one table edit.
local INSTANCE_TYPES = { party = true, raid = true }

-- A probe result counts only as a readable plain true: a throw or a secret
-- value reads as false, the guard the opacity resolver applies to its own.
local function plainTrue(ok, value)
    if not ok then return false end
    if issecretvalue and issecretvalue(value) then return false end
    return value == true
end

local function probeInCombat()
    if plainTrue(pcall(InCombatLockdown)) then return true end
    return plainTrue(pcall(UnitAffectingCombat, "player"))
end

local function probeTargetAcquired()
    return plainTrue(pcall(UnitExists, "target"))
end

local function probeInsideInstance()
    local ok, inInstance, instanceType = pcall(IsInInstance)
    if not ok then return false end
    -- Both returns are screened before the table index: a secret key throws.
    if issecretvalue and (issecretvalue(inInstance) or issecretvalue(instanceType)) then
        return false
    end
    if inInstance ~= true then return false end
    return INSTANCE_TYPES[instanceType] == true
end

-- Ordered so the display and the resolution walk the triggers the same way.
local TRIGGERS = {
    { name = "inCombat",       probe = probeInCombat },
    { name = "targetAcquired", probe = probeTargetAcquired },
    { name = "insideInstance", probe = probeInsideInstance },
}

local triggerByLower = {}
for _, trigger in ipairs(TRIGGERS) do
    triggerByLower[string.lower(trigger.name)] = trigger.name
end

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

local EDGE_LOG_MAX = 30

local answer            -- "base" or "dynamic"; nil until the first resolution
local suspended = false -- Edit Mode open: base holds
local pending = false   -- one deferred resolution armed
local armed = {}        -- { event, at } records since the last resolution
local suspendedResolves = 0

local enabled = { inCombat = true, targetAcquired = true, insideInstance = true }

local last = {}     -- per trigger: value, flippedAt, flippedWall
local edgeLog = {}  -- newest last; capped at EDGE_LOG_MAX
local armStats = {} -- per event: arms, quiet, lastAt
local handles = {}  -- registration handles, for the live/dead line

local subscribers = {}
local subscriberByOwner = {}

--------------------------------------------------------------------------------
-- Resolution
--------------------------------------------------------------------------------

local function appendLog(record)
    edgeLog[#edgeLog + 1] = record
    if #edgeLog > EDGE_LOG_MAX then
        table.remove(edgeLog, 1)
    end
end

-- Snapshot and reset the arm list first, so the deferred pass that follows a
-- synchronous resolve runs against an empty one.
local function takeArmed()
    local events = armed
    armed = {}
    return events
end

-- Runs every probe, enabled or not, so the window shows live values for
-- disabled triggers too. Returns the value map and the names that flipped.
local function readTriggers(now)
    local values, flips = {}, {}
    for _, trigger in ipairs(TRIGGERS) do
        local name = trigger.name
        local value = trigger.probe()
        values[name] = value
        local record = last[name]
        if not record then
            last[name] = { value = value }
        elseif record.value ~= value then
            record.value = value
            record.flippedAt = now
            record.flippedWall = date("%H:%M:%S")
            flips[#flips + 1] = name
        end
    end
    return values, flips
end

local function computeAnswer(values)
    for _, trigger in ipairs(TRIGGERS) do
        if enabled[trigger.name] and values[trigger.name] then
            return "base"
        end
    end
    return "dynamic"
end

local function snapshotEnabled()
    local copy = {}
    for name, on in pairs(enabled) do copy[name] = on end
    return copy
end

local function publish(info)
    -- Snapshot: a subscribe from inside a callback lands on the next edge.
    local n = #subscribers
    for i = 1, n do
        local sub = subscribers[i]
        if sub then
            securecallfunction(sub.fn, info.answer, info)
        end
    end
end

local function resolve(origin)
    local events = takeArmed()
    if suspended or addon.EditMode.IsEditing() then
        suspendedResolves = suspendedResolves + 1
        return
    end
    local now = GetTime()
    local values, flips = readTriggers(now)
    local newAnswer = computeAnswer(values)
    if newAnswer ~= answer then
        local record = {
            kind = "edge",
            wall = date("%H:%M:%S"),
            at = now,
            from = answer,
            to = newAnswer,
            origin = origin,
            events = events,
            values = values,
            flips = flips,
            enabled = snapshotEnabled(),
        }
        local previous = answer
        answer = newAnswer
        appendLog(record)
        publish({
            answer = newAnswer,
            previous = previous,
            initial = previous == nil,
            origin = origin,
            at = now,
            wall = record.wall,
            events = events,
            triggers = values,
        })
    elseif #flips > 0 then
        -- A flip the answer survived still logs, so an instance edge stays
        -- visible when combat already held the answer at base.
        appendLog({
            kind = "flip",
            wall = date("%H:%M:%S"),
            at = now,
            to = answer,
            origin = origin,
            events = events,
            values = values,
            flips = flips,
            enabled = snapshotEnabled(),
        })
    else
        -- Nothing changed: tally the arming events instead of eating the log.
        for _, arm in ipairs(events) do
            local stats = armStats[arm.event]
            if stats then stats.quiet = stats.quiet + 1 end
        end
    end
end

--------------------------------------------------------------------------------
-- Dispatch
--------------------------------------------------------------------------------

local function onDeferred()
    pending = false
    resolve("deferred")
end

local function armDeferred()
    if pending then return end
    pending = true
    C_Timer.After(0, onDeferred)
end

local function recordArm(event)
    local at = GetTime()
    armed[#armed + 1] = { event = event, at = at }
    local stats = armStats[event]
    if not stats then
        stats = { arms = 0, quiet = 0 }
        armStats[event] = stats
    end
    stats.arms = stats.arms + 1
    stats.lastAt = at
end

local function onEvent(event)
    recordArm(event)
    -- The regen-disabled handler runs before lockdown engages; resolving here
    -- puts the combat-entry edge inside that window. The deferred pass that
    -- follows finds nothing changed and stays quiet.
    if event == "PLAYER_REGEN_DISABLED" then
        resolve("sync")
    end
    armDeferred()
end

local EVENTS = {
    "PLAYER_REGEN_DISABLED",
    "PLAYER_REGEN_ENABLED",
    "PLAYER_TARGET_CHANGED",
    "PLAYER_ENTERING_WORLD",
    -- Registered beside PLAYER_ENTERING_WORLD to measure which of the two
    -- delivers instance edges; the loser drops once the log answers it.
    "ZONE_CHANGED_NEW_AREA",
}

for _, event in ipairs(EVENTS) do
    handles[event] = addon.Events.On(OWNER, event, onEvent)
end

--------------------------------------------------------------------------------
-- Edit Mode
--------------------------------------------------------------------------------

-- Edit Mode outranks the triggers: base holds while it is open. Entry forces
-- the base edge at once; exit re-resolves on the deferred path, where the
-- editing flag already reads false.
addon.EditMode.OnEditMode(OWNER, {
    enter = function()
        suspended = true
        if answer == nil or answer == "base" then return end
        local now = GetTime()
        local events = { { event = "EDIT_MODE_ENTER", at = now } }
        local values, flips = readTriggers(now)
        local record = {
            kind = "edge",
            wall = date("%H:%M:%S"),
            at = now,
            from = answer,
            to = "base",
            origin = "editmode",
            events = events,
            values = values,
            flips = flips,
            enabled = snapshotEnabled(),
        }
        local previous = answer
        answer = "base"
        appendLog(record)
        publish({
            answer = "base",
            previous = previous,
            initial = false,
            origin = "editmode",
            at = now,
            wall = record.wall,
            events = events,
            triggers = values,
        })
    end,
    exit = function()
        suspended = false
        armed[#armed + 1] = { event = "EDIT_MODE_EXIT", at = GetTime() }
        armDeferred()
    end,
})

--------------------------------------------------------------------------------
-- API
--------------------------------------------------------------------------------

function Resolver.Answer()
    return answer
end

function Resolver.IsSuspended()
    return suspended
end

-- Re-registering an owner replaces its callback in place, so a second init
-- pass never doubles it. The callback receives (answer, info); the current
-- answer at subscribe time comes from Answer().
function Resolver.Subscribe(owner, fn)
    if type(owner) ~= "string" or type(fn) ~= "function" then return end
    local sub = subscriberByOwner[owner]
    if not sub then
        sub = { owner = owner }
        subscriberByOwner[owner] = sub
        subscribers[#subscribers + 1] = sub
    end
    sub.fn = fn
end

-- Session-local; the per-layout record is the engine's schema work.
function Resolver.SetTriggerEnabled(name, on)
    local canonical = triggerByLower[string.lower(tostring(name or ""))]
    if not canonical then return false end
    enabled[canonical] = on and true or false
    armed[#armed + 1] = { event = "TRIGGER_TOGGLE", at = GetTime() }
    armDeferred()
    return true
end

--------------------------------------------------------------------------------
-- Debug window
--------------------------------------------------------------------------------

local function formatArms(record)
    local parts = {}
    for _, arm in ipairs(record.events or {}) do
        parts[#parts + 1] = string.format("%s(%+.3f)", arm.event, arm.at - record.at)
    end
    if #parts == 0 then return "(none)" end
    return table.concat(parts, ", ")
end

local function formatValues(record)
    local flipped = {}
    for _, name in ipairs(record.flips or {}) do
        flipped[name] = true
    end
    local parts = {}
    for _, trigger in ipairs(TRIGGERS) do
        local name = trigger.name
        local mark = flipped[name] and "!" or ""
        local off = (record.enabled and record.enabled[name] == false) and "(off)" or ""
        local value = record.values and record.values[name]
        parts[#parts + 1] = string.format("%s=%s%s%s", name, tostring(value), mark, off)
    end
    return table.concat(parts, "  ")
end

local function showWindow()
    local lines, push = addon.DebugLines("=== Camelot dynamic layouts ===", "")
    push("answer:       %s", answer or "(none)")
    push("suspended:    %s", suspended and "yes" or "no")
    push("subscribers:  %d", #subscribers)
    if suspendedResolves > 0 then
        push("resolutions held by Edit Mode: %d", suspendedResolves)
    end
    push("")
    push("triggers (dynamic while every enabled trigger is false)")
    for _, trigger in ipairs(TRIGGERS) do
        local name = trigger.name
        local record = last[name]
        local flip = "never"
        if record and record.flippedAt then
            flip = string.format("%s (t=%.3f)", record.flippedWall, record.flippedAt)
        end
        push("  %-15s %-4s %-6s last flip %s",
            name,
            enabled[name] and "on" or "OFF",
            record and tostring(record.value) or "unread",
            flip)
    end
    push("")
    push("events")
    for _, event in ipairs(EVENTS) do
        local handle = handles[event]
        local stats = armStats[event]
        push("  %-22s %-5s arms %-4d quiet %-4d last %s",
            event,
            (handle and handle:IsActive()) and "live" or "dead",
            stats and stats.arms or 0,
            stats and stats.quiet or 0,
            (stats and stats.lastAt) and string.format("t=%.3f", stats.lastAt) or "-")
    end
    push("")
    push("edges and flips (newest first, %d kept; arm offsets are seconds before the resolution)",
        EDGE_LOG_MAX)
    if #edgeLog == 0 then
        push("  (none)")
    end
    for i = #edgeLog, 1, -1 do
        local record = edgeLog[i]
        local head
        if record.kind == "flip" then
            head = string.format("flip, answer holds %s", record.to)
        else
            head = string.format("%s -> %s", record.from or "(none)", record.to)
        end
        push("  %s t=%.3f  %s  %s  armed %s",
            record.wall, record.at, head, record.origin, formatArms(record))
        push("      %s", formatValues(record))
    end
    addon.DebugShowWindow("Camelot", lines)
end

local function triggerVerb(name, state)
    local lowered = string.lower(tostring(state or ""))
    local on
    if lowered == "on" then
        on = true
    elseif lowered == "off" then
        on = false
    else
        return addon.Commands.USAGE
    end
    if not Resolver.SetTriggerEnabled(name, on) then
        return addon.Commands.USAGE
    end
end

addon:RegisterDebugCommand({
    name = "dynamic",
    help = "the Dynamic Layouts resolver: answer, triggers, edge log",
    default = "show",
    verbs = {
        { word = "show", help = "open the resolver window", fn = showWindow },
        { word = "trigger", usage = "trigger <inCombat|targetAcquired|insideInstance> <on|off>",
          help = "flip a trigger for this session", fn = triggerVerb },
        { word = "clear", help = "empty the edge log and the event tallies",
          fn = function()
              edgeLog = {}
              armStats = {}
              suspendedResolves = 0
          end },
    },
})
