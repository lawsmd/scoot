--------------------------------------------------------------------------------
-- forever/castbars/dynamic.lua
-- The Dynamic Layouts adapter for the Classic cast bar: a plain-tier frame,
-- so every channel switches live in combat. The channel set follows the
-- position mode: a free bar carries opacity, scale and position; a snapped
-- bar carries opacity and scale and rides its unit frame's own slide, so the
-- record's point is ignored while it is snapped. The bar's lifecycle
-- (core/components/castbarz/events.lua) resets alpha through the resting
-- seam this file fills, and its positionable restore calls back through the
-- restore seam, so the dynamic state survives both.
--------------------------------------------------------------------------------

local addonName, addon = ...

local CBZ = addon.CastBarZ
local DL = addon.DynamicLayouts

local Dynamic = {}
CBZ.Dynamic = Dynamic

local FREE = { "opacity", "scale", "position" }
local SNAPPED = { "opacity", "scale" }

local resting = setmetatable({}, { __mode = "k" })   -- bar -> last final opacity
local mode = setmetatable({}, { __mode = "k" })      -- bar -> "free" | "snapped"

-- The alpha the bar's own resets write (a cast start, the post-fade hide, a
-- reset): the engine's last final write, else 1. The tween's ticks bypass
-- the applier, so a reset mid-tween writes the stale value for one tick.
CBZ._RestingAlpha = function(bar)
    return resting[bar] or 1
end

-- A positionable restore just landed the base position (a layout switch).
CBZ._OnPositionRestored = function(bar)
    local row = CBZ._RowForBarKey(bar.barKey)
    if row then DL.Reassert(row.layoutKey) end
end

local function modeOf(bar)
    return CBZ._GetPositionMode(bar.unitKey) == "free" and "free" or "snapped"
end

local function definition(bar, row, m)
    return {
        id = row.layoutKey,
        label = (CBZ.UNIT_LABELS[row.unitKey] or row.unitKey) .. " Cast Bar",
        frame = bar,
        tier = "plain",
        channels = m == "free" and FREE or SNAPPED,
        base = {
            opacity = function() return 1 end,
            scale = function() return CBZ._GetBarScale(row.unitKey) end,
            -- The store hands out the stored or default pair in the bar's
            -- own scale, what the positionable restore applies.
            position = function()
                return CBZ._PositionStore.get(row.barKey, addon.EditMode.GetActiveLayoutName())
            end,
        },
        apply = {
            opacity = function(frame, a)
                resting[frame] = a
                frame:SetAlpha(a)
            end,
            -- A snapped bar's offsets are in its own scale: re-anchor at the
            -- new one. Not snapped, _ApplySnap writes nothing.
            scale = function(frame, s)
                frame:SetScale(s)
                CBZ._ApplySnap(frame)
            end,
            position = CBZ._ApplyBarPosition,
        },
    }
end

--- From _ApplyBar, after the base layout and position are down: register on
--- the first call, re-register when the position mode changed (the channel
--- set follows it; the engine releases a dropped channel), else put the
--- dynamic geometry back on top.
function Dynamic.Sync(bar)
    if not (DL and DL.Register) then return end
    local row = CBZ._RowForBarKey(bar.barKey)
    if not row then return end
    local m = modeOf(bar)
    if mode[bar] ~= m then
        mode[bar] = m
        DL.Register(definition(bar, row, m))
    else
        DL.Reassert(row.layoutKey)
    end
end
