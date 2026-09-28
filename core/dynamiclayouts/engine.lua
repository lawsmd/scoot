--------------------------------------------------------------------------------
-- core/dynamiclayouts/engine.lua
-- The Dynamic Layouts engine: the adapter registry, the state each adapter is
-- in, and the one apply routine that carries a frame between its base state
-- and its dynamic state through the tween (tween.lua) or a snap.
--
-- A component participates by registering an adapter: the frame, its tier
-- (plain or protected), the channels it supports, and a base
-- getter per channel. The base state is never captured: every restore
-- re-derives it from the getters. The dynamic state comes only from the
-- store seam, addon.DynamicLayoutsStore, which the host file sets and this
-- file reads at the moment of use. The `applied` values kept per adapter are
-- the tween's starting points and the window's readout, never a restore
-- source.
--
-- Zero-touch: a base value is written only on a channel the engine holds, so
-- a frame that never participated never receives a write. Legality follows
-- the channel matrix: opacity is always legal, a plain frame takes every
-- channel in combat, and a protected frame's position and scale skip
-- lockdown and pay at regen through a keyed RunOutOfCombat closure (or the
-- adapter's own regen slot when it names one). Inside PLAYER_REGEN_DISABLED
-- protected writes are still legal, so the combat-entry edge snaps those two
-- channels and tweens alpha.
--------------------------------------------------------------------------------

local addonName, addon = ...

addon.DynamicLayouts = addon.DynamicLayouts or {}
local DL = addon.DynamicLayouts
local Resolver = DL.Resolver
local Tween = DL.Tween

local OWNER = "dynamicLayoutsEngine"

local CHANNELS = { "opacity", "scale", "position" }
local CHANNEL_SET = { opacity = true, scale = true, position = true }
local TIERS = { plain = true, protected = true }

local SPEED_MIN, SPEED_MAX, SPEED_DEFAULT = 0.1, 1.5, 0.35
DL.SPEED_MIN, DL.SPEED_MAX, DL.SPEED_DEFAULT = SPEED_MIN, SPEED_MAX, SPEED_DEFAULT

local ANCHORS = {
    TOPLEFT = true, TOP = true, TOPRIGHT = true,
    LEFT = true, CENTER = true, RIGHT = true,
    BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true,
}

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

local adapters = {}   -- id -> state record
local registered = {} -- ids in registration order
local forced = nil    -- "base" | "dynamic" | nil, session only

-- The host seam, read at call time so the host file can load after this one.
local function Store()
    local store = addon.DynamicLayoutsStore
    if type(store) == "table" and type(store.GetRecord) == "function" then
        return store
    end
    return nil
end

local function record(id)
    local store = Store()
    return store and store.GetRecord(id) or nil
end

local function speed()
    local store = Store()
    local value = store and store.GetSpeed and store.GetSpeed()
    value = tonumber(value) or SPEED_DEFAULT
    if value < SPEED_MIN then value = SPEED_MIN end
    if value > SPEED_MAX then value = SPEED_MAX end
    return value
end

local function frameOf(st)
    local frame = st.def.frame
    if type(frame) == "function" then
        local ok, result = pcall(frame)
        return ok and result or nil
    end
    return frame
end

local DEFAULT_APPLY = {
    opacity = function(frame, a) frame:SetAlpha(a) end,
    scale = function(frame, s) frame:SetScale(s) end,
    position = function(frame, point, x, y)
        frame:ClearAllPoints()
        frame:SetPoint(point, x, y)
    end,
}

--------------------------------------------------------------------------------
-- Decisions and values
--------------------------------------------------------------------------------

--- What this adapter should be in: the forced override, then the resolver's
--- answer, with dynamic only for a record that says enabled. nil before the
--- first resolution.
local function decide(id)
    if forced then return forced end
    local answer = Resolver.Answer()
    if answer ~= "dynamic" then return answer end
    local rec = record(id)
    return (rec and rec.enabled) and "dynamic" or "base"
end

local function plainNumber(v)
    if type(v) ~= "number" then return nil end
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end

--- The base value for a channel, from the adapter's getter. nil on a throw or
--- a value of the wrong shape.
local function baseValue(st, channel)
    local getter = st.def.base and st.def.base[channel]
    if type(getter) ~= "function" then return nil end
    local ok, a, b, c = pcall(getter)
    if not ok then
        st.lastError = "base." .. channel .. ": " .. tostring(a)
        return nil
    end
    if channel == "position" then
        if type(a) == "table" then a, b, c = a.point, a.x, a.y end
        if ANCHORS[a] and plainNumber(b) and plainNumber(c) then
            return { point = a, x = b, y = c }
        end
        return nil
    end
    return plainNumber(a)
end

--- The dynamic value for a channel from the store record, or nil when the
--- record leaves the channel at base.
local function dynamicValue(id, channel)
    local rec = record(id)
    if not rec then return nil end
    if channel == "position" then
        if ANCHORS[rec.point] and plainNumber(rec.x) and plainNumber(rec.y) then
            return { point = rec.point, x = rec.x, y = rec.y }
        end
        return nil
    end
    return plainNumber(rec[channel])
end

--- Target value and whether it is the base. A dynamic state whose record is
--- silent on a channel targets the base for that channel, with one
--- re-expression: a silent position under a dynamic scale keeps the anchor
--- point on its screen spot, so the frame scales in place. Offsets are in the
--- frame's own scale, so the base pair is multiplied by base over dynamic.
local function valueFor(st, channel, state)
    if state == "dynamic" then
        local value = dynamicValue(st.def.id, channel)
        if value ~= nil then return value, false end
        if channel == "position" and st.channelSet.scale then
            local b = baseValue(st, "position")
            local bs, ds = baseValue(st, "scale"), dynamicValue(st.def.id, "scale")
            if b and bs and ds and bs ~= ds and bs > 0 and ds > 0 then
                return { point = b.point, x = b.x * bs / ds, y = b.y * bs / ds }, false
            end
        end
    end
    return baseValue(st, channel), true
end

local function channelLegal(st, channel)
    if channel == "opacity" then return true end
    if st.def.tier ~= "protected" then return true end
    return not InCombatLockdown()
end

--- A channel the engine has a hand on: written to a non-base value, or in
--- flight. A deferred channel alone does not count; its closure re-derives.
local function isHeld(st, channel)
    return st.holds[channel] or Tween.IsActive(st.def.id, channel)
end

--------------------------------------------------------------------------------
-- Writes
--------------------------------------------------------------------------------

local function applier(st, channel)
    local apply = st.def.apply and st.def.apply[channel]
    if type(apply) == "function" then return apply end
    return DEFAULT_APPLY[channel]
end

--- The final write for a channel, through the adapter's applier.
local function writeFinal(st, channel, value, isBase)
    local frame = frameOf(st)
    if not frame then return false end
    local ok, err
    if channel == "position" then
        ok, err = pcall(applier(st, channel), frame, value.point, value.x, value.y)
    else
        ok, err = pcall(applier(st, channel), frame, value)
    end
    if channel == "position" then st.centered = nil end
    if not ok then
        st.lastError = channel .. ": " .. tostring(err)
        return false
    end
    st.applied[channel] = value
    st.holds[channel] = not isBase
    st.deferred[channel] = nil
    return true
end

local function frameScaleOf(frame)
    local ok, s = pcall(frame.GetScale, frame)
    s = ok and plainNumber(s) or nil
    return (s and s > 0) and s or 1
end

--- The per-tick write. Position ticks hold one CENTER anchor against the
--- screen center, in the frame's own scale; the finish sets the real point.
local function writeTick(st, channel, a, b)
    local frame = frameOf(st)
    if not frame then return end
    if channel == "position" then
        if not st.centered then
            frame:ClearAllPoints()
            st.centered = true
        end
        frame:SetPoint("CENTER", UIParent, "CENTER", a, b)
        -- The slide's last center in UI units, so a yield to lockdown mid-slide
        -- resumes from here at regen rather than from the base record.
        local s = frameScaleOf(frame)
        st.applied.position = { center = { a * s, b * s } }
    elseif channel == "opacity" then
        frame:SetAlpha(a)
        st.applied.opacity = a
    else
        frame:SetScale(a)
        st.applied.scale = a
    end
end

local applyState

--- Pay a channel that missed its window: at regen, through the adapter's own
--- slot when it names one, else the keyed RunOutOfCombat queue. The closure
--- re-derives everything at drain time rather than replaying a value.
local function defer(st, channel)
    st.deferred[channel] = true
    local id = st.def.id
    local function reapply()
        DL.Reapply(id, channel)
    end
    if type(st.def.queue) == "function" then
        local ok, err = pcall(st.def.queue, channel, reapply)
        if ok then return end
        st.lastError = "queue: " .. tostring(err)
    end
    addon.Events.RunOutOfCombat(reapply, "DL:" .. tostring(id) .. ":" .. channel)
end

--- Where a channel is now, as the tween's starting point: in flight, then the
--- last write, then the base. Never a live read off the frame.
local function currentValue(st, channel)
    local id = st.def.id
    if Tween.IsActive(id, channel) then
        if channel == "position" then
            local cx, cy = Tween.Current(id, channel)
            return { center = { cx, cy } }
        end
        return Tween.Current(id, channel)
    end
    local applied = st.applied[channel]
    if st.holds[channel] and applied ~= nil then
        return applied
    end
    return baseValue(st, channel)
end

--- Build the position endpoints as center pairs. `fromScale` and `toScale`
--- are the scale channel's endpoints when it travels too, else the frame's.
local function positionEndpoints(st, frame, fromValue, toRecord, fromScale, toScale)
    local EM = addon.EditMode
    if not (EM and EM.CenterFromRecord) then return nil end
    local from
    if type(fromValue) == "table" and fromValue.center then
        from = fromValue.center
    elseif type(fromValue) == "table" and fromValue.point then
        local cx, cy = EM.CenterFromRecord(frame, fromValue.point, fromValue.x, fromValue.y, fromScale)
        if cx then from = { cx, cy } end
    end
    local tx, ty = EM.CenterFromRecord(frame, toRecord.point, toRecord.x, toRecord.y, toScale)
    if not (from and tx) then return nil end
    return from, { tx, ty }
end

--- The one apply routine. mode is "snap" (no tween), "tween", or "sync" (the
--- regen-disabled window: protected position and scale snap while they are
--- still legal, opacity tweens). `only` limits the pass to a channel set.
applyState = function(st, state, mode, only)
    if state == nil then return end
    st.target = state
    local id = st.def.id
    local frame = frameOf(st)
    if not frame then return end

    local plan = {}
    for _, ch in ipairs(st.def.channels) do
        if not only or only[ch] then
            local value, isBase = valueFor(st, ch, state)
            if value ~= nil and not (isBase and not isHeld(st, ch)) then
                plan[ch] = { to = value, base = isBase }
            end
        end
    end

    local tweenChannels = nil
    for _, ch in ipairs(CHANNELS) do
        local p = plan[ch]
        if p then
            local snapThis = mode == "snap"
                or (mode == "sync" and ch ~= "opacity" and st.def.tier == "protected")
            if snapThis then
                Tween.Drop(id, ch)
                if channelLegal(st, ch) then
                    writeFinal(st, ch, p.to, p.base)
                else
                    defer(st, ch)
                end
            else
                tweenChannels = tweenChannels or {}
                tweenChannels[ch] = p
            end
        end
    end
    if not tweenChannels then return end

    local frameScale = frameScaleOf(frame)
    local spec = { channels = {} }
    local scaleP = tweenChannels.scale
    local fromScale, toScale = frameScale, frameScale
    if scaleP then
        local from = currentValue(st, "scale") or frameScale
        spec.channels.scale = { from = from, to = scaleP.to, base = scaleP.base }
        fromScale, toScale = from, scaleP.to
    end
    local opacityP = tweenChannels.opacity
    if opacityP then
        spec.channels.opacity = {
            from = currentValue(st, "opacity") or 1,
            to = opacityP.to,
            base = opacityP.base,
        }
    end
    local positionP = tweenChannels.position
    if positionP then
        local from, to = positionEndpoints(st, frame, currentValue(st, "position"),
            positionP.to, fromScale, toScale)
        if from then
            spec.channels.position = { from = from, to = to, base = positionP.base, record = positionP.to }
            -- A fresh slide clears the anchors on its first tick, whatever
            -- wrote them since the last one.
            st.centered = nil
        else
            -- No readable rect: land it without the slide.
            Tween.Drop(id, "position")
            if channelLegal(st, "position") then
                writeFinal(st, "position", positionP.to, positionP.base)
            else
                defer(st, "position")
            end
        end
    end
    if next(spec.channels) == nil then return end

    spec.frame = frame
    spec.duration = speed()
    spec.scale = frameScale
    spec.legal = function(ch) return channelLegal(st, ch) end
    spec.write = function(ch, a, b) writeTick(st, ch, a, b) end
    spec.finish = function(ch, to, isBase, ok)
        if ok then
            writeFinal(st, ch, to, isBase)
        else
            -- Yielded mid-flight: the frame sits off base, so the channel is
            -- held and the regen reapply starts from the last tick.
            if st.applied[ch] ~= nil then st.holds[ch] = true end
            defer(st, ch)
        end
    end
    Tween.Start(id, spec)
end

--------------------------------------------------------------------------------
-- API
--------------------------------------------------------------------------------

--- def = {
---   id       = string, the layout key the record sits beside,
---   label    = string, window text,
---   frame    = Frame | function() -> Frame,
---   tier     = "plain" | "protected",
---   channels = ordered subset of { "opacity", "scale", "position" },
---   base     = { [channel] = function() -> value }; position returns point, x, y,
---   apply    = { [channel] = function(frame, ...) }, optional final writers,
---   queue    = function(channel, reapply), optional, the protected tier's slot,
--- }
--- Re-registering an id replaces the def and keeps the state. A bad def
--- leaves the adapter inert with its reason in lastError.
function DL.Register(def)
    if type(def) ~= "table" or type(def.id) ~= "string" then return nil end
    local id = def.id
    local st = adapters[id]
    if not st then
        st = {
            def = def,
            order = #registered + 1,
            holds = {},
            applied = {},
            deferred = {},
        }
        adapters[id] = st
        registered[#registered + 1] = id
    else
        st.def = def
    end
    st.lastError = nil
    st.inert = nil

    if not TIERS[def.tier] then
        st.inert = "tier " .. tostring(def.tier)
    elseif type(def.channels) ~= "table" or #def.channels == 0 then
        st.inert = "no channels"
    else
        for _, ch in ipairs(def.channels) do
            if not CHANNEL_SET[ch] then
                st.inert = "channel " .. tostring(ch)
                break
            end
            if type(def.base) ~= "table" or type(def.base[ch]) ~= "function" then
                st.inert = "no base getter for " .. ch
                break
            end
        end
    end
    if st.inert then
        st.lastError = st.inert
        return st
    end
    st.channelSet = {}
    for _, ch in ipairs(def.channels) do st.channelSet[ch] = true end

    -- A frame registered after the first resolution lands in its state at
    -- once, as a snap; before it, the initial edge does the same.
    if Resolver.Answer() ~= nil then
        applyState(st, decide(id), "snap")
    end
    return st
end

function DL.Get(id)
    return adapters[id]
end

function DL.Ids()
    return registered
end

--- Re-run the decision for one adapter. mode: "snap" or "tween".
function DL.Refresh(id, mode)
    local st = adapters[id]
    if not st or st.inert then return end
    applyState(st, decide(id), mode or "tween")
end

function DL.RefreshAll(mode)
    for _, id in ipairs(registered) do
        DL.Refresh(id, mode)
    end
end

--- The deferred closure's entry. One call pays every channel still owed, in
--- one pass, so a position that missed its window slides to endpoints
--- computed at the scale it travels with; the other channel's closure then
--- finds nothing owed and returns.
function DL.Reapply(id, channel)
    local st = adapters[id]
    if not st or st.inert then return end
    if channel and not st.deferred[channel] then return end
    local only = {}
    for ch in pairs(st.deferred) do only[ch] = true end
    if next(only) == nil then return end
    for ch in pairs(only) do st.deferred[ch] = nil end
    applyState(st, decide(id), "tween", only)
end

--- For a component that has just re-applied its own base geometry (a
--- positionable restore on a layout switch). The restore replaced every
--- anchor, so a slide in flight clears them again on its next tick. Then the
--- two geometry channels snap to the current target: both when it is dynamic,
--- and whichever is in flight when it is base, so a base-ward slide does not
--- finish on the position it was started from. A no-op on an adapter without
--- those channels.
function DL.Reassert(id)
    local st = adapters[id]
    if not st or st.inert or st.target == nil then return end
    st.centered = nil
    local only = {}
    for _, ch in ipairs({ "scale", "position" }) do
        if st.target == "dynamic" or Tween.IsActive(id, ch) then only[ch] = true end
    end
    if next(only) then applyState(st, st.target, "snap", only) end
end

function DL.IsDynamic(id)
    local st = adapters[id]
    return st and st.target == "dynamic" or false
end

--- The forced state, session only: "base", "dynamic" or nil.
function DL.SetForced(state)
    if state ~= "base" and state ~= "dynamic" then state = nil end
    forced = state
    DL.RefreshAll("tween")
end

--- Set by the resolver's trigger verb; the host's store persists it.
function DL.PersistTrigger(name, on)
    local store = Store()
    if store and store.SetTrigger then
        store.SetTrigger(name, on)
    end
end

--------------------------------------------------------------------------------
-- Edges
--------------------------------------------------------------------------------

--- Snap every adapter to its decided state, then cancel whatever the snap did
--- not take. Snap first: a channel tweening away from base is unheld, and
--- once cancelled it is no longer in flight either, so the snap would skip it
--- and leave the frame partway.
local function landAll(edge)
    for _, id in ipairs(registered) do
        local st = adapters[id]
        if not st.inert then
            if edge then st.lastEdge = edge end
            applyState(st, decide(id), "snap")
            Tween.Cancel(id)
        end
    end
end

Resolver.Subscribe(OWNER, function(_, info)
    local mode
    if info.initial or info.origin == "editmode" then
        mode = "snap"
    elseif info.origin == "sync" then
        mode = "sync"
    else
        mode = "tween"
    end
    if info.origin == "editmode" then
        forced = nil
    end
    local edge = { wall = info.wall, origin = info.origin, answer = info.answer, mode = mode }
    if mode == "snap" then
        landAll(edge)
        return
    end
    for _, id in ipairs(registered) do
        local st = adapters[id]
        if not st.inert then
            st.lastEdge = edge
            applyState(st, decide(id), mode)
        end
    end
end)

-- Edit Mode outranks everything, the forced state included. The resolver's
-- own enter hook publishes the base edge only when its answer changes, so a
-- forced dynamic held against a base answer would survive entry without this
-- hook, which runs second (first-registration order) and clears it. After a
-- published edge the pass finds nothing held or moving and writes nothing.
addon.EditMode.OnEditMode(OWNER, {
    enter = function()
        forced = nil
        landAll()
    end,
})

-- Registered after the resolver's own handler, so it runs second inside the
-- pre-lockdown window: a protected frame's position and scale still in
-- flight land now, while the writes are legal. This is the case no edge
-- covers, a base tween still running when combat starts, or the inCombat
-- trigger switched off.
addon.Events.On(OWNER, "PLAYER_REGEN_DISABLED", function()
    for _, id in ipairs(registered) do
        local st = adapters[id]
        if st.def.tier == "protected" then
            Tween.Finish(id, { position = true, scale = true })
        end
    end
end)

--------------------------------------------------------------------------------
-- Debug: verbs on the resolver's command, a section in its window
--------------------------------------------------------------------------------

local function describeValue(channel, value)
    if value == nil then return "-" end
    if channel == "position" then
        if value.center then
            return string.format("sliding %.0f,%.0f", value.center[1], value.center[2])
        end
        return string.format("%s %.0f,%.0f", tostring(value.point), value.x or 0, value.y or 0)
    end
    return string.format("%.2f", value)
end

local function section(push)
    local store = Store()
    push("adapters (%d registered, speed %.2fs, force %s, store %s)",
        #registered, speed(), forced or "off", store and "set" or "MISSING")
    if #registered == 0 then
        push("  (none)")
        return
    end
    for _, id in ipairs(registered) do
        local st = adapters[id]
        local def = st.def
        local rec = record(id)
        if st.inert then
            push("  [%s] %s  INERT: %s", id, tostring(def.label), st.inert)
        else
            local edge = st.lastEdge
            push("  [%s] %s  %s  enabled %s  channels %s  target %s  edge %s",
                id, tostring(def.label), def.tier,
                (rec and rec.enabled) and "on" or "off",
                table.concat(def.channels, ","),
                st.target or "(none)",
                edge and string.format("%s %s/%s", edge.wall, edge.origin, edge.mode) or "-")
            local flight = Tween.Get(id)
            for _, ch in ipairs(def.channels) do
                push("      %-9s applied %-14s %-6s dynamic %-14s base %s",
                    ch,
                    describeValue(ch, st.applied[ch]),
                    st.holds[ch] and "holds" or "",
                    describeValue(ch, dynamicValue(id, ch)),
                    describeValue(ch, baseValue(st, ch)))
            end
            if flight then
                local parts = {}
                for ch, c in pairs(flight.channels) do
                    if ch == "position" then
                        parts[#parts + 1] = string.format("position -> %s", describeValue(ch, c.record))
                    else
                        parts[#parts + 1] = string.format("%s %.2f -> %.2f", ch, c.current or c.from, c.to)
                    end
                end
                push("      tween     %3.0f%%  %s", (flight.progress or 0) * 100, table.concat(parts, "  "))
            end
            local owed = {}
            for _, ch in ipairs(CHANNELS) do
                if st.deferred[ch] then owed[#owed + 1] = ch end
            end
            if #owed > 0 then
                push("      queued    %s (%s)", table.concat(owed, ", "),
                    type(def.queue) == "function" and "adapter slot" or "RunOutOfCombat")
            end
            if st.lastError then
                push("      error     %s", st.lastError)
            end
        end
    end
end

local function resolveId(id)
    if type(id) ~= "string" then return nil end
    if adapters[id] then return id end
    local lowered = string.lower(id)
    for _, known in ipairs(registered) do
        if string.lower(known) == lowered then return known end
    end
    return nil
end

local function onOff(word)
    local lowered = string.lower(tostring(word or ""))
    if lowered == "on" then return true end
    if lowered == "off" then return false end
    return nil
end

local function enableVerb(id, state)
    id = resolveId(id)
    local on = onOff(state)
    local store = Store()
    if not (id and on ~= nil and store) then return addon.Commands.USAGE end
    store.SetRecord(id, { enabled = on })
    DL.Refresh(id, "tween")
end

local function valueVerb(id, field, raw)
    id = resolveId(id)
    local store = Store()
    if not (id and store) then return addon.Commands.USAGE end
    field = string.lower(tostring(field or ""))
    local fields
    if string.lower(tostring(raw or "")) == "off" then
        -- The store merges, so false is how a field clears; the readers
        -- type-check and read it as absent.
        if not (field == "opacity" or field == "scale" or field == "x" or field == "y" or field == "point") then
            return addon.Commands.USAGE
        end
        fields = { [field] = false }
    elseif field == "opacity" then
        local v = tonumber(raw)
        if not v or v < 0 or v > 1 then return addon.Commands.USAGE end
        fields = { opacity = v }
    elseif field == "scale" then
        local v = tonumber(raw)
        if not v or v < 0.25 or v > 4 then return addon.Commands.USAGE end
        fields = { scale = v }
    elseif field == "x" or field == "y" then
        local v = tonumber(raw)
        if not v then return addon.Commands.USAGE end
        fields = { [field] = v }
    elseif field == "point" then
        local point = string.upper(tostring(raw or ""))
        if not ANCHORS[point] then return addon.Commands.USAGE end
        fields = { point = point }
    else
        return addon.Commands.USAGE
    end
    store.SetRecord(id, fields)
    DL.Refresh(id, "tween")
end

local function speedVerb(raw)
    local v = tonumber(raw)
    local store = Store()
    if not (v and store and store.SetSpeed) then return addon.Commands.USAGE end
    if v < SPEED_MIN then v = SPEED_MIN end
    if v > SPEED_MAX then v = SPEED_MAX end
    store.SetSpeed(v)
end

local function forceVerb(state)
    local lowered = string.lower(tostring(state or ""))
    if lowered == "base" or lowered == "dynamic" then
        DL.SetForced(lowered)
    elseif lowered == "off" then
        DL.SetForced(nil)
    else
        return addon.Commands.USAGE
    end
end

local verbs = DL.DebugVerbs
verbs[#verbs + 1] = { word = "enable", usage = "enable <id> <on|off>",
    help = "let a frame take its dynamic state; ids are the window's adapter rows", fn = enableVerb }
verbs[#verbs + 1] = { word = "value", usage = "value <id> <opacity|scale|x|y|point> <value|off>",
    help = "set one field of a frame's dynamic record (opacity 0..1, scale 0.25..4); off clears it", fn = valueVerb }
verbs[#verbs + 1] = { word = "speed", usage = "speed <0.1..1.5>",
    help = "the transition duration in seconds, per profile", fn = speedVerb }
verbs[#verbs + 1] = { word = "force", usage = "force <base|dynamic|off>",
    help = "hold a state regardless of the triggers, this session; Edit Mode clears it", fn = forceVerb }

DL.DebugSections[#DL.DebugSections + 1] = section
