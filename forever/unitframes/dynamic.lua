--------------------------------------------------------------------------------
-- forever/unitframes/dynamic.lua
-- The Dynamic Layouts adapter for the Classic unit frames: each built frame
-- registers once, from Frame.Build, as a protected-tier adapter on all three
-- channels, whose base state is re-derived from the same sources the frame
-- is built from. Opacity is legal in every state; a position or scale that
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

--- Register one built unit frame. Called after the positionable exists, so
--- the engine's Reassert finds a stored position to stand on.
function Dynamic.Register(inst)
    local DL = addon.DynamicLayouts
    if not (DL and DL.Register) then return end
    if not (inst and inst.frame and inst.key) then return end
    local key = inst.key

    DL.Register({
        id = key,
        label = inst.def and inst.def.label or key,
        frame = inst.frame,
        tier = "protected",
        channels = { "opacity", "scale", "position" },
        base = {
            opacity = function() return 1 end,
            scale = function()
                return DB.Get("unitFrames." .. key .. ".scale") or 1
            end,
            -- The stored position for the active layout, else the default:
            -- what the positionable restore applies (core/editmode/positionables.lua).
            position = function()
                local entry = DB.GetLayout(key)
                local layoutName = addon.EditMode.GetActiveLayoutName()
                local pos = entry and entry.positions and layoutName and entry.positions[layoutName]
                if pos and pos.point then
                    return pos.point, pos.x or 0, pos.y or 0
                end
                local d = inst.def and inst.def.default
                if not d then return nil end
                return d.point, d.x or 0, d.y or 0
            end,
        },
        queue = function(channel, reapply)
            local fns = pending[inst]
            if not fns then
                fns = {}
                pending[inst] = fns
            end
            fns[channel] = reapply
            Harness.QueueRegen(inst, "dynamic")
        end,
    })
end
