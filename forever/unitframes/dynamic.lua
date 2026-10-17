--------------------------------------------------------------------------------
-- forever/unitframes/dynamic.lua
-- The Dynamic Layouts adapter for Camelot's unit frames: one adapter per unit
-- key, registered from Frame.Build as a protected-tier adapter on all three
-- channels, whose base state is re-derived from the same sources the frame
-- is built from. The frame it drives is whichever style's instance is on
-- screen (UF.Frames), read through a getter, so a style swap re-registers the
-- same id and snaps. Opacity is legal in every state; a position or scale that
-- misses the regen-disabled window pays at regen through the harness's
-- `dynamic` slot, which runs the engine's re-derive closures in channel order.
--------------------------------------------------------------------------------

local addonName, addon = ...

local UF = addon.UnitFrames
local DB = addon.DB
local Harness = UF.Harness

local Dynamic = {}
UF.Dynamic = Dynamic

local GEOMETRY = { "scale", "position" }

-- The engine's re-derive closures owed per instance, by channel. The harness
-- keeps flags only; a closure re-reads everything at drain time, which is the
-- same rule. Each runs isolated, so a throw reaches the error handler and the
-- drain's later slots still run.
local pending = {}

Harness.RegisterAction("dynamic", function(inst)
    local fns = pending[inst]
    if not fns then return end
    pending[inst] = nil
    for _, ch in ipairs(GEOMETRY) do
        if fns[ch] then securecallfunction(fns[ch]) end
    end
end)

-- The instance on screen for a unit, or the one being registered while none
-- is up yet (a first build: the engine's snap then lands on nothing, and the
-- activation's Resync lands it once UF.Frames points at the frame).
local function active(key, inst)
    return UF.Frames[key] or inst
end

--- Register the unit's adapter from a built instance. Called after the
--- positionable exists, so the engine's Reassert finds a stored position to
--- stand on. A second instance of the same key re-registers the id, which
--- keeps the state and snaps.
function Dynamic.Register(inst)
    local DL = addon.DynamicLayouts
    if not (DL and DL.Register) then return end
    if not (inst and inst.frame and inst.key) then return end
    local key = inst.key

    DL.Register({
        id = key,
        label = inst.def and inst.def.label or key,
        group = "unitFrames",
        frame = function()
            local a = UF.Frames[key]
            return a and a.frame or nil
        end,
        tier = "protected",
        channels = { "opacity", "scale", "position" },
        base = {
            opacity = function() return 1 end,
            scale = function()
                return DB.Get("unitFrames." .. key .. ".scale") or 1
            end,
            -- The stored position for the active layout, else the active
            -- style's default: what the positionable restore applies
            -- (core/editmode/positionables.lua).
            position = function()
                local entry = DB.GetLayout(key)
                local layoutName = addon.EditMode.GetActiveLayoutName()
                local pos = entry and entry.positions and layoutName and entry.positions[layoutName]
                if pos and pos.point then
                    return pos.point, pos.x or 0, pos.y or 0
                end
                local a = active(key, inst)
                local d = a.def and a.def.default
                if not d then return nil end
                return d.point, d.x or 0, d.y or 0
            end,
        },
        queue = function(channel, reapply)
            local a = active(key, inst)
            local fns = pending[a]
            if not fns then
                fns = {}
                pending[a] = fns
            end
            fns[channel] = reapply
            Harness.QueueRegen(a, "dynamic")
        end,
    })
end

--- The swap's snap: land every held dynamic channel on the frame now on
--- screen for the unit, over the base the activation re-landed.
function Dynamic.Resync(key)
    local DL = addon.DynamicLayouts
    if not (DL and DL.Refresh) then return end
    DL.Refresh(key, "snap")
end
