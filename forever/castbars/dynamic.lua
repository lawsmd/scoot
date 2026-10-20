--------------------------------------------------------------------------------
-- forever/castbars/dynamic.lua
-- The Dynamic Layouts adapter for the Classic cast bar: a plain-tier frame,
-- so every channel switches live in combat, on all three channels whatever
-- the position mode. The dynamic layout ignores a snap: a snapped bar keeps a
-- place of its own there, its regular spot until its record says otherwise,
-- so its unit frame's slide leaves it, and it snaps back at base. The bar's
-- lifecycle (core/components/castbarz/events.lua) resets alpha through the
-- resting seam this file fills, and its positionable restore calls back
-- through the restore seam, so the dynamic state survives both.
--------------------------------------------------------------------------------

local addonName, addon = ...

local CBZ = addon.CastBarZ
local DL = addon.DynamicLayouts

local Dynamic = {}
CBZ.Dynamic = Dynamic

local CHANNELS = { "opacity", "scale", "position" }

local resting = setmetatable({}, { __mode = "k" })    -- bar -> last final opacity
local registered = setmetatable({}, { __mode = "k" }) -- bar -> true once registered

-- The alpha the bar's own resets write (a cast start, the post-fade hide, a
-- reset): the engine's last final write, else 1. The tween's ticks bypass
-- the applier, so a reset mid-tween writes the stale value for one tick.
CBZ._RestingAlpha = function(bar)
    return resting[bar] or 1
end

-- A positionable restore just landed the base position (a layout switch).
CBZ._OnPositionRestored = function(bar)
    local row = CBZ._RowForBarKey(bar.barKey)
    if row and row.layoutKey then DL.Reassert(row.layoutKey) end
end

local function definition(bar, row)
    return {
        id = row.layoutKey,
        label = (CBZ.UNIT_LABELS[row.unitKey] or row.unitKey) .. " Cast Bar",
        group = "castBars",
        frame = bar,
        tier = "plain",
        channels = CHANNELS,
        attach = function() return CBZ._SnapSpec(bar) end,
        reattach = function(frame) CBZ._ApplySnap(frame) end,
        base = {
            opacity = function() return 1 end,
            scale = function() return CBZ._GetBarScale(row.unitKey) end,
            -- The store hands out the stored or default pair in the bar's
            -- own scale, what the positionable restore applies. The engine
            -- computes a snapped bar's spot from its unit frame instead.
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
            -- new one, unless the engine holds its position off the snap.
            -- Not snapped, _ApplySnap writes nothing.
            scale = function(frame, s)
                frame:SetScale(s)
                if not DL.HoldsChannel(row.layoutKey, "position") then
                    CBZ._ApplySnap(frame)
                end
            end,
            -- The free write alone: the engine re-snaps through reattach.
            position = function(frame, point, x, y)
                frame:ClearAllPoints()
                frame:SetPoint(point, UIParent, point, CBZ._SnapToPixels(x), CBZ._SnapToPixels(y))
            end,
        },
    }
end

--- From _ApplyBar, after the base layout and position are down: register on
--- the first call, else put the dynamic geometry back on top.
function Dynamic.Sync(bar)
    if not (DL and DL.Register) then return end
    local row = CBZ._RowForBarKey(bar.barKey)
    -- A hosted bar rides its host frame's adapter (the Resource Display's)
    -- and has no layout key of its own.
    if not row or row.hosted or not row.layoutKey then return end
    if not registered[bar] then
        registered[bar] = true
        DL.Register(definition(bar, row))
    else
        DL.Reassert(row.layoutKey)
    end
end
