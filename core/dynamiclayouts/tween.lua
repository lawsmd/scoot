--------------------------------------------------------------------------------
-- core/dynamiclayouts/tween.lua
-- The Dynamic Layouts transition driver: one OnUpdate on one hidden frame,
-- interpolating alpha, scale and a center-relative position on frames the
-- addon owns, through the real setters each tick. The engine (engine.lua)
-- decides what moves and where; this file only carries a value from A to B
-- over a duration and reports where it is.
--
-- One clock per frame id. A retarget restarts the clock with the retargeted
-- channels' new endpoints and the untouched channels re-based from where they
-- are now, so nothing jumps. A channel whose legality check fails on a tick
-- leaves the tween at once and its finish runs with ok=false, which the engine
-- turns into a deferred write. Finished ids are collected and paid after the
-- loop, because a finish may start a new tween.
--
-- Easing is smoothstep, p*p*(3-2p): zero velocity at both ends, and a peak of
-- 1.5 against cubic in-out's 3, so a mid-flight retarget, which restarts from
-- rest, shows half the discontinuity. The engine-side animation group is the
-- recorded upgrade if this reads choppy at low frame rates.
--------------------------------------------------------------------------------

local addonName, addon = ...

addon.DynamicLayouts = addon.DynamicLayouts or {}
local DL = addon.DynamicLayouts

local Tween = {}
DL.Tween = Tween

-- Parentless on purpose: a child of UIParent stops updating when the UI is
-- hidden, and a transition should land wherever it was headed regardless.
local driver = CreateFrame("Frame")
driver:Hide()

local active = {}   -- id -> tween
local finished = {} -- ids collected during a tick

local function ease(p)
    return p * p * (3 - 2 * p)
end

local function lerp(a, b, e)
    return a + (b - a) * e
end

-- Scale ticks before position: the position tick divides by the scale the
-- frame is at, which the scale tick has just set.
local ORDER = { "opacity", "scale", "position" }

--------------------------------------------------------------------------------
-- Ticking
--------------------------------------------------------------------------------

local function currentScale(t)
    local c = t.channels.scale
    if c then return c.current end
    return t.scale
end

local function tickChannel(t, ch, e)
    local c = t.channels[ch]
    if not c then return end
    if not t.legal(ch) then
        t.channels[ch] = nil
        -- The final value is the stored record for position, the number otherwise.
        t.finish(ch, c.record or c.to, c.base, false)
        return
    end
    if ch == "position" then
        c.current = { lerp(c.from[1], c.to[1], e), lerp(c.from[2], c.to[2], e) }
        local s = currentScale(t) or 1
        t.write(ch, c.current[1] / s, c.current[2] / s)
    else
        c.current = lerp(c.from, c.to, e)
        t.write(ch, c.current)
    end
end

local function tick(_, elapsed)
    for i = #finished, 1, -1 do finished[i] = nil end
    for id, t in pairs(active) do
        t.elapsed = t.elapsed + elapsed
        local p = t.elapsed / t.duration
        if p > 1 then p = 1 end
        t.progress = p
        local e = ease(p)
        for _, ch in ipairs(ORDER) do
            tickChannel(t, ch, e)
        end
        if p >= 1 or next(t.channels) == nil then
            finished[#finished + 1] = id
        end
    end
    for _, id in ipairs(finished) do
        Tween.Finish(id)
    end
    if next(active) == nil then
        driver:Hide()
    end
end

driver:SetScript("OnUpdate", tick)

--------------------------------------------------------------------------------
-- API
--------------------------------------------------------------------------------

--- spec = {
---   frame    = Frame,
---   duration = seconds,
---   scale    = the frame's scale now, for a position tween with no scale channel,
---   legal    = function(channel) -> boolean, checked every tick,
---   write    = function(channel, ...)  the per-tick writer,
---   finish   = function(channel, to, base, ok)  the final writer; ok=false means
---              the channel yielded to a failed legality check,
---   channels = {
---     opacity  = { from = a0, to = a1, base = bool },
---     scale    = { from = s0, to = s1, base = bool },
---     position = { from = { cx, cy }, to = { cx, cy }, base = bool, record = { point, x, y } },
---   },
--- }
--- On an active id the named channels are replaced and the rest re-based from
--- their current values; the clock restarts.
function Tween.Start(id, spec)
    if id == nil or type(spec) ~= "table" or type(spec.channels) ~= "table" then return end
    if next(spec.channels) == nil then return end
    local t = active[id]
    if t then
        for ch, c in pairs(t.channels) do
            if not spec.channels[ch] then
                -- Re-based: the remaining travel starts from here.
                c.from = c.current or c.from
                spec.channels[ch] = c
            end
        end
    end
    local channels = {}
    for ch, c in pairs(spec.channels) do
        channels[ch] = {
            from = c.from,
            to = c.to,
            base = c.base,
            record = c.record,
            current = c.from,
        }
    end
    active[id] = {
        frame = spec.frame,
        duration = (spec.duration and spec.duration > 0) and spec.duration or 0.35,
        scale = spec.scale or 1,
        legal = spec.legal,
        write = spec.write,
        finish = spec.finish,
        channels = channels,
        elapsed = 0,
        progress = 0,
    }
    driver:Show()
end

--- The interpolated value now, or nil when the channel is not in flight.
function Tween.Current(id, channel)
    local t = active[id]
    local c = t and t.channels[channel]
    if not c then return nil end
    if channel == "position" then
        return c.current[1], c.current[2]
    end
    return c.current
end

function Tween.IsActive(id, channel)
    local t = active[id]
    if not t then return false end
    if channel == nil then return true end
    return t.channels[channel] ~= nil
end

local function drop(id)
    active[id] = nil
    if next(active) == nil then
        driver:Hide()
    end
end

--- Remove one channel with no write.
function Tween.Drop(id, channel)
    local t = active[id]
    if not t then return end
    t.channels[channel] = nil
    if next(t.channels) == nil then
        drop(id)
    end
end

--- Remove every channel with no write.
function Tween.Cancel(id)
    if active[id] then
        drop(id)
    end
end

--- Run the final writes now for the channels in `only`, or all of them, and
--- remove them. The finish runs after the channel is out of the table, so a
--- finish that starts a new tween sees a clean slate.
function Tween.Finish(id, only)
    local t = active[id]
    if not t then return end
    for _, ch in ipairs(ORDER) do
        local c = t.channels[ch]
        if c and (not only or only[ch]) then
            t.channels[ch] = nil
            t.finish(ch, c.record or c.to, c.base, true)
        end
    end
    if active[id] == t and next(t.channels) == nil then
        drop(id)
    end
end

--- For the window: progress and the per-channel endpoints, or nil.
function Tween.Get(id)
    local t = active[id]
    if not t then return nil end
    return {
        progress = t.progress,
        elapsed = t.elapsed,
        duration = t.duration,
        channels = t.channels,
    }
end
