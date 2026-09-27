--------------------------------------------------------------------------------
-- forever/unitframes/dynamic.lua
-- The Dynamic Layouts adapter for the Classic unit frames: each built frame
-- registers once, from Frame.Build, as a protected-tier adapter whose base
-- state is re-derived from the same sources the frame is built from.
--
-- Stage 2 exercises opacity alone, the one channel legal in every state.
-- The scale and position getters are written for stage 3, which adds those
-- channels to the list and hands the engine the harness's regen slot.
--------------------------------------------------------------------------------

local addonName, addon = ...

local UF = addon.UnitFrames
local DB = addon.DB

local Dynamic = {}
UF.Dynamic = Dynamic

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
        channels = { "opacity" },
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
    })
end
