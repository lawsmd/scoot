--------------------------------------------------------------------------------
-- core/dynamiclayouts/resolver.lua
-- The Dynamic Layouts trigger resolver: the one owner of the base-or-dynamic
-- answer. The dynamic state holds while every enabled trigger reads false;
-- any enabled trigger reading true means base. Subscribers hear edges, never
-- states: a callback fires only when the answer changes, and the current
-- answer is a getter. A dynamic answer waits out the player's delay
-- (engine.lua, DL.Delay) after the last trigger clears, and the answer stays
-- base meanwhile, so every reader sees one answer and nothing moves twice.
--
-- Two rules of the owner's, 19 October 2026: the target trigger counts only
-- an NPC the player can attack while the engine's per-profile rule
-- (DL.TargetAttackableNPCs) is on; and a fourth trigger, fixed and off the
-- panel, holdingAction, reads true while something placeable on an action
-- bar is on the cursor and a frame that takes a drop takes part, so the
-- layout comes back for the placement, and its clearing never waits. A
-- fifth, menuOpen, fixed and no-wait the same way, reads true while the game
-- menu or Blizzard's settings window is shown.
--
-- Two lanes, 19 October 2026: the main answer every frame follows, and a
-- wide one that also counts a friendly unit target (friendlyUnit) while the
-- target trigger is on, for a frame whose record asks for it, the player
-- frame by default (engine.lua, the def's friendlyUnits). Each lane keeps its
-- own answer and its own wait, and an edge names its lane.
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
--
-- The engine (engine.lua) feeds the enabled mask from the per-profile store,
-- persists a trigger toggle through DL.PersistTrigger, and extends the debug
-- command through DL.DebugVerbs and DL.DebugSections, both read live.
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

-- Instance types the insideInstance trigger counts: every one, decided with
-- the owner 28 September 2026, since the requirement reads "Not in an
-- instance".
local INSTANCE_TYPES = { party = true, raid = true, pvp = true, arena = true, scenario = true }

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

-- The engine's read of the per-profile target rule; on before the engine
-- loads or with no store, the registered default.
local function attackableNPCsOnly()
    local fn = DL.TargetAttackableNPCs
    if type(fn) ~= "function" then return true end
    return fn() ~= false
end

-- Any target, or, under the rule, an NPC the player can attack: what the
-- client colors yellow or red. A player never counts under it, as the
-- panel's checkbox says.
local function probeTargetAcquired()
    if not plainTrue(pcall(UnitExists, "target")) then return false end
    if not attackableNPCsOnly() then return true end
    if plainTrue(pcall(UnitIsPlayer, "target")) then return false end
    return plainTrue(pcall(UnitCanAttack, "player", "target"))
end

-- A friendly target the target rule leaves out: a friendly NPC, a friendly
-- player, or the player themself. Only the wide lane reads it, and only while
-- the rule is on, since with the rule off the target trigger already counts
-- every target.
local function probeFriendlyUnit()
    if not attackableNPCsOnly() then return false end
    if not plainTrue(pcall(UnitExists, "target")) then return false end
    if plainTrue(pcall(UnitIsUnit, "target", "player")) then return true end
    return plainTrue(pcall(UnitIsFriend, "player", "target"))
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

-- Something placeable on an action bar is on the cursor: the client fires
-- ACTIONBAR_SHOWGRID on the pickup and ACTIONBAR_HIDEGRID on the drop or the
-- clear, the pair the bars' own grid reads. The flag is the events' (onEvent
-- below); the probe counts it only while a frame that takes a drop takes
-- part (engine.lua, DL.DropTargetParticipating), so a layout with no bars
-- in it never moves for a drag.
local heldAction = false

local function dropTargetParticipating()
    local fn = DL.DropTargetParticipating
    return type(fn) == "function" and fn() == true
end

local function probeHoldingAction()
    return heldAction and dropTargetParticipating()
end

-- The game menu or Blizzard's settings window is open, decided with the owner
-- 19 October 2026: the player is away from play, so the whole layout comes
-- back. The menu is Blizzard's GameMenuFrame or the branded replacement
-- ui/v2/GameMenu.lua shows in its place; the settings window opens from the
-- menu and hides it, and the swap lands in one frame, so the pair coalesces.
-- The frames have no events; installMenuHooks below arms on their shows and
-- hides.
local function menuFrames()
    return GameMenuFrame, SettingsPanel, _G[addon.Brand .. "GameMenuFrame"]
end

local function shown(frame)
    if not frame or not frame.IsShown then return false end
    return plainTrue(pcall(frame.IsShown, frame))
end

local function probeMenuOpen()
    local a, b, c = menuFrames()
    return shown(a) or shown(b) or shown(c)
end

-- Ordered so the display and the resolution walk the triggers the same way.
-- A fixed trigger is always enabled: no checkbox, no mask key, no verb. A
-- noWait trigger's clearing skips the delay. A wide trigger counts in the
-- wide lane only, under the target trigger's checkbox.
local TRIGGERS = {
    { name = "inCombat",       probe = probeInCombat },
    { name = "targetAcquired", probe = probeTargetAcquired },
    { name = "insideInstance", probe = probeInsideInstance },
    { name = "holdingAction",  probe = probeHoldingAction, fixed = true, noWait = true },
    { name = "menuOpen",       probe = probeMenuOpen, fixed = true, noWait = true },
    { name = "friendlyUnit",    probe = probeFriendlyUnit, fixed = true, wide = true },
}

local triggerByLower, fixedTrigger, wideTrigger = {}, {}, {}
for _, trigger in ipairs(TRIGGERS) do
    triggerByLower[string.lower(trigger.name)] = trigger.name
    if trigger.fixed then fixedTrigger[trigger.name] = true end
    if trigger.wide then wideTrigger[trigger.name] = true end
end

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

local EDGE_LOG_MAX = 30

local suspended = false -- Edit Mode open: base holds
local pending = false   -- one deferred resolution armed
local armed = {}        -- { event, at } records since the last resolution
local suspendedResolves = 0

local enabled = {
    inCombat = true, targetAcquired = true, insideInstance = true,
    holdingAction = true, menuOpen = true, friendlyUnit = true,
}

local last = {}     -- per trigger: value, flippedAt, flippedWall
local edgeLog = {}  -- newest last; capped at EDGE_LOG_MAX
local armStats = {} -- per event: arms, quiet, lastAt
local handles = {}  -- registration handles, for the live/dead line

local subscribers = {}
local subscriberByOwner = {}

-- Per lane: the answer, "base" or "dynamic", nil until the first
-- resolution; and the delay, one hold at a time, { ends, wait } while a
-- dynamic answer waits. The token retires a hold that a base answer, Edit
-- Mode or a later flip replaced, so its timer finds nothing to do.
local main = { name = "main", answer = nil, hold = nil, holdToken = 0 }
local wide = { name = "wide", wide = true, answer = nil, hold = nil, holdToken = 0 }
local LANES = { main, wide }
local LANE_BY_NAME = { main = main, wide = wide }

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

local function computeAnswer(lane, values)
    for _, trigger in ipairs(TRIGGERS) do
        local name = trigger.name
        if values[name] then
            if trigger.wide then
                if lane.wide and enabled.targetAcquired then return "base" end
            elseif enabled[name] then
                return "base"
            end
        end
    end
    return "dynamic"
end

-- The flips a lane hears: the main lane never hears a wide trigger's, so a
-- friendly unit targeted inside its wait does not start the wait over.
local function laneFlips(lane, flips)
    if lane.wide then return flips end
    local out = {}
    for _, flip in ipairs(flips) do
        if not wideTrigger[flip] then out[#out + 1] = flip end
    end
    return out
end

local noWaitTrigger = {}
for _, trigger in ipairs(TRIGGERS) do
    if trigger.noWait then noWaitTrigger[trigger.name] = true end
end

local function noWaitFlipped(flips)
    for _, flip in ipairs(flips) do
        if noWaitTrigger[flip] then return true end
    end
    return false
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

-- The engine's clamped read of the per-profile setting; 0 before the engine
-- loads or with no store.
local function delaySeconds()
    local fn = DL.Delay
    local v = type(fn) == "function" and tonumber(fn()) or 0
    return (v and v > 0) and v or 0
end

local function dropHold(lane)
    if not lane.hold then return false end
    lane.holdToken = lane.holdToken + 1
    lane.hold = nil
    return true
end

local resolve

-- The wait, then one more resolution. It re-reads every probe, so a target
-- acquired in the meantime answers base; its own arming entry flips nothing,
-- so it publishes rather than waiting again.
local function armHold(lane, wait, now)
    lane.holdToken = lane.holdToken + 1
    local token = lane.holdToken
    lane.hold = { ends = now + wait, wait = wait }
    C_Timer.After(wait, function()
        if token ~= lane.holdToken then return end
        lane.hold = nil
        armed[#armed + 1] = { event = "DELAY", at = GetTime() }
        resolve("delay")
    end)
end

-- One lane's step over the probes' values: the wait, the edge, the log.
-- Returns true when it logged.
local function step(lane, origin, events, values, allFlips, now)
    local flips = laneFlips(lane, allFlips)
    local answer = lane.answer
    local newAnswer = computeAnswer(lane, values)
    local function log(kind, extra)
        local record = {
            kind = kind,
            lane = lane.name,
            wall = date("%H:%M:%S"),
            at = now,
            to = answer,
            origin = origin,
            events = events,
            values = values,
            flips = flips,
            enabled = snapshotEnabled(),
        }
        for k, v in pairs(extra or {}) do record[k] = v end
        appendLog(record)
        return record
    end
    if newAnswer == "base" and lane.hold then
        -- A trigger set inside the wait: the answer never left base.
        dropHold(lane)
        log("drop")
        return true
    elseif newAnswer == "dynamic" and answer == "base" then
        local wait = delaySeconds()
        -- The cursor emptied or the menu closed: the layout goes back at once,
        -- the owner's call, since the delay is for looting and regrouping
        -- between pulls and neither is that.
        local dropped = noWaitFlipped(flips)
        if wait > 0 and #flips > 0 and not dropped then
            -- The last trigger cleared: the wait starts, or starts over.
            armHold(lane, wait, now)
            log("hold", { wait = wait })
            return true
        end
        -- Nothing flipped: a running wait goes on; with none, or with the
        -- delay set to 0 meanwhile, the answer changes now (Edit Mode
        -- closing, a mask change, the wait's own end).
        if lane.hold and wait > 0 and not dropped then return false end
        dropHold(lane)
    end
    if newAnswer ~= answer then
        local record = log("edge", { from = answer, to = newAnswer })
        lane.answer = newAnswer
        publish({
            lane = lane.name,
            answer = newAnswer,
            previous = answer,
            initial = answer == nil,
            origin = origin,
            at = now,
            wall = record.wall,
            events = events,
            triggers = values,
        })
        return true
    end
    -- A flip the answer survived still logs, so an instance edge stays
    -- visible when combat already held the answer at base. The wide lane
    -- logs only a flip of its own trigger, since the main lane logs the rest.
    for _, flip in ipairs(flips) do
        if not lane.wide or wideTrigger[flip] then
            log("flip")
            return true
        end
    end
    return false
end

resolve = function(origin)
    local events = takeArmed()
    if suspended or addon.EditMode.IsEditing() then
        suspendedResolves = suspendedResolves + 1
        return
    end
    local now = GetTime()
    local values, flips = readTriggers(now)
    local logged = false
    for _, lane in ipairs(LANES) do
        if step(lane, origin, events, values, flips, now) then logged = true end
    end
    if not logged then
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
    -- The cursor's pair keeps the one flag; a pickup and a drop inside one
    -- frame coalesce to nothing, as every event does.
    if event == "ACTIONBAR_SHOWGRID" then
        heldAction = true
    elseif event == "ACTIONBAR_HIDEGRID" then
        heldAction = false
    end
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
    -- The cursor taking and losing something a bar accepts (holdingAction).
    "ACTIONBAR_SHOWGRID",
    "ACTIONBAR_HIDEGRID",
}

for _, event in ipairs(EVENTS) do
    handles[event] = addon.Events.On(OWNER, event, onEvent)
end

-- The menu frames' shows and hides arm a resolution (menuOpen). Each frame is
-- hooked once, at the first world entry it exists by. The branded menu is
-- created on its first Show, so a hook on GameMenu.Show catches it there and
-- arms for that first show, which ran before the frame's own hook existed.
local menuHooked = {}

local function onMenuShow() onEvent("MENU_SHOW") end
local function onMenuHide() onEvent("MENU_HIDE") end

local function installMenuHooks()
    local frames = { menuFrames() }
    for i = 1, 3 do
        local frame = frames[i]
        if frame and not menuHooked[frame] and frame.HookScript then
            menuHooked[frame] = true
            -- Kept off addon.Enforce: the hooks read visibility, they hide nothing.
            frame:HookScript("OnShow", onMenuShow)
            frame:HookScript("OnHide", onMenuHide)
        end
    end
end

local brandMenuHooked = false
addon.Events.On(OWNER .. "Menu", "PLAYER_ENTERING_WORLD", function()
    installMenuHooks()
    local GameMenu = addon.UI and addon.UI.GameMenu
    if not brandMenuHooked and GameMenu and GameMenu.Show then
        brandMenuHooked = true
        hooksecurefunc(GameMenu, "Show", function()
            installMenuHooks()
            onMenuShow()
        end)
    end
end)

--------------------------------------------------------------------------------
-- Edit Mode
--------------------------------------------------------------------------------

-- Edit Mode outranks the triggers: base holds while it is open. Entry forces
-- the base edge at once; exit re-resolves on the deferred path, where the
-- editing flag already reads false.
addon.EditMode.OnEditMode(OWNER, {
    enter = function()
        suspended = true
        local now = GetTime()
        local events = { { event = "EDIT_MODE_ENTER", at = now } }
        local values, flips
        for _, lane in ipairs(LANES) do
            -- Base holds under Edit Mode, so a wait in progress has nothing to end in.
            dropHold(lane)
            local answer = lane.answer
            if answer == "dynamic" then
                if not values then values, flips = readTriggers(now) end
                local record = {
                    kind = "edge",
                    lane = lane.name,
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
                lane.answer = "base"
                appendLog(record)
                publish({
                    lane = lane.name,
                    answer = "base",
                    previous = answer,
                    initial = false,
                    origin = "editmode",
                    at = now,
                    wall = record.wall,
                    events = events,
                    triggers = values,
                })
            end
        end
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

--- The answer in one lane: "main", the default, or "wide", which also
--- counts a friendly unit target.
function Resolver.Answer(laneName)
    local lane = LANE_BY_NAME[laneName or "main"] or main
    return lane.answer
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

--- Arm one deferred resolution under an event name of the caller's, for a
--- setting a probe reads changing outside the client's events (the target
--- rule's setter in view.lua).
function Resolver.Rearm(event)
    armed[#armed + 1] = { event = tostring(event or "REARM"), at = GetTime() }
    armDeferred()
end

--- Flip one trigger for the session. Returns the canonical name, or nil for
--- an unknown or a fixed one. Persistence is the engine's: triggerVerb below
--- hands the canonical name to DL.PersistTrigger when the engine has set it.
function Resolver.SetTriggerEnabled(name, on)
    local canonical = triggerByLower[string.lower(tostring(name or ""))]
    if not canonical or fixedTrigger[canonical] then return nil end
    enabled[canonical] = on and true or false
    Resolver.Rearm("TRIGGER_TOGGLE")
    return canonical
end

--- Write the whole mask, from the per-profile store on every profile pass. A
--- resolution is armed only once something has resolved: at the initial pass
--- nothing has, and arming there would resolve pre-world against a stale
--- IsInInstance and play a visible transition at the world entry.
function Resolver.SetEnabledMask(mask)
    if type(mask) ~= "table" then return end
    for _, trigger in ipairs(TRIGGERS) do
        local on = mask[trigger.name]
        if on ~= nil then
            enabled[trigger.name] = on and true or false
        end
    end
    if main.answer ~= nil then
        armed[#armed + 1] = { event = "MASK_SET", at = GetTime() }
        armDeferred()
    end
end

function Resolver.IsTriggerEnabled(name)
    return enabled[name] and true or false
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
    for _, lane in ipairs(LANES) do
        local hold = lane.hold
        push("answer %-6s %s%s", lane.name .. ":", lane.answer or "(none)",
            hold and string.format("  (dynamic in %.1fs)", math.max(0, hold.ends - GetTime())) or "")
    end
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
        push("  %-15s %-5s %-6s last flip %s%s",
            name,
            wideTrigger[name] and "wide" or (fixedTrigger[name] and "fixed" or (enabled[name] and "on" or "OFF")),
            record and tostring(record.value) or "unread",
            flip,
            (name == "targetAcquired" and attackableNPCsOnly()) and "  attackable NPCs only" or "")
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
    for _, section in ipairs(DL.DebugSections) do
        push("")
        securecallfunction(section, push)
    end
    push("")
    push("edges, flips and holds (newest first, %d kept; arm offsets are seconds before the resolution)",
        EDGE_LOG_MAX)
    if #edgeLog == 0 then
        push("  (none)")
    end
    for i = #edgeLog, 1, -1 do
        local record = edgeLog[i]
        local head
        if record.kind == "flip" then
            head = string.format("flip, answer holds %s", record.to)
        elseif record.kind == "hold" then
            head = string.format("hold %.1fs, answer stays %s", record.wait, record.to)
        elseif record.kind == "drop" then
            head = string.format("hold dropped, answer holds %s", record.to)
        else
            head = string.format("%s -> %s", record.from or "(none)", record.to)
        end
        if record.lane == "wide" then head = "wide lane: " .. head end
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
    local canonical = Resolver.SetTriggerEnabled(name, on)
    if not canonical then
        return addon.Commands.USAGE
    end
    if DL.PersistTrigger then
        DL.PersistTrigger(canonical, on)
    end
end

-- Both tables are read live: the engine appends its verbs to the first and
-- its window section to the second when it loads, after this registration.
DL.DebugVerbs = {
    { word = "show", help = "open the Dynamic Layouts window", fn = showWindow },
    { word = "trigger", usage = "trigger <inCombat|targetAcquired|insideInstance> <on|off>",
      help = "flip a trigger; persists per profile once the engine is loaded", fn = triggerVerb },
    { word = "clear", help = "empty the edge log and the event tallies",
      fn = function()
          edgeLog = {}
          armStats = {}
          suspendedResolves = 0
      end },
}
DL.DebugSections = {}

addon:RegisterDebugCommand({
    name = "dynamic",
    help = "Dynamic Layouts: the resolver's answer, triggers, adapters, edge log",
    default = "show",
    verbs = DL.DebugVerbs,
})
