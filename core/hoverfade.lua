--------------------------------------------------------------------------------
-- hoverfade.lua
-- The mouseover reveal: whether the cursor is over a frame or any of its
-- extra frames, polled for every watcher on one shared ticker.
--
--   HoverFade.Watch(key, { frame = f, extra = { ... }, onChange = fn })
--       Starts or replaces the watch under key and returns the answer now.
--       onChange(isOver) runs on each later change, never for that first
--       answer. A replaced watch keeps its last answer.
--   HoverFade.Unwatch(key)
--   HoverFade.IsOver(key)   the last answer; false when unwatched
--   HoverFade.Dump()        the registry in the copyable window
--
-- A frame that is not shown reads as not over. The ticker runs only while a
-- watch exists. It polls because HookScript("OnEnter") on a bar or an action
-- button taints its script handlers, and the button's own event handlers
-- then read secret values in combat. The caller owns every alpha write.
--------------------------------------------------------------------------------

local _, addon = ...

addon.HoverFade = addon.HoverFade or {}
local HoverFade = addon.HoverFade

local PERIOD = 0.15

local watches = {} -- key -> { frame, extra, onChange, over }
local ticker

local function isOver(w)
    local frame = w.frame
    if not (frame and frame:IsShown()) then return false end
    if frame:IsMouseOver() then return true end
    for _, f in ipairs(w.extra or {}) do
        if f:IsShown() and f:IsMouseOver() then return true end
    end
    return false
end

local function tick()
    if next(watches) == nil then
        if ticker then ticker:Cancel() end
        ticker = nil
        return
    end
    for _, w in pairs(watches) do
        local over = isOver(w)
        if over ~= w.over then
            w.over = over
            if w.onChange then pcall(w.onChange, over) end
        end
    end
end

function HoverFade.Watch(key, spec)
    if key == nil or type(spec) ~= "table" or not spec.frame then return false end
    local w = watches[key]
    if not w then
        w = {}
        watches[key] = w
    end
    w.frame, w.extra, w.onChange = spec.frame, spec.extra, spec.onChange
    w.over = isOver(w)
    if not ticker then ticker = C_Timer.NewTicker(PERIOD, tick) end
    return w.over
end

function HoverFade.Unwatch(key)
    if key == nil then return end
    watches[key] = nil
    if next(watches) == nil and ticker then
        ticker:Cancel()
        ticker = nil
    end
end

function HoverFade.IsOver(key)
    local w = key ~= nil and watches[key]
    return w and w.over or false
end

function HoverFade.Dump()
    local lines, push = addon.DebugLines()
    local n = 0
    for _ in pairs(watches) do n = n + 1 end
    push("ticker %s, %d watch(es), period %.2fs", ticker and "running" or "stopped", n, PERIOD)
    for key, w in pairs(watches) do
        local name = (type(key) == "table" and key.GetName and key:GetName()) or tostring(key)
        push("%s: frame %s, shown %s, extra %d, over %s", name,
            (w.frame and w.frame:GetName()) or tostring(w.frame),
            tostring(w.frame and w.frame:IsShown()), #(w.extra or {}), tostring(w.over))
    end
    addon.DebugShowWindow("Hover fade", lines)
end

addon:RegisterDebugCommand({
    name = "hoverfade",
    help = "Mouseover reveal: every watched frame and whether the cursor is over it",
    handler = function() HoverFade.Dump() end,
})
