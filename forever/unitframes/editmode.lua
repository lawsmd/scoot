--------------------------------------------------------------------------------
-- forever/unitframes/editmode.lua
-- The host side of addon.EditMode.RegisterPositionable for Camelot's unit
-- frames: where a position is stored, how it is applied around combat, and
-- which settings page the dialog's Configure button opens. The engine is
-- core/editmode/positionables.lua and ui/v2/editmode/, shared with Scoot.
--------------------------------------------------------------------------------

local addonName, addon = ...

local Harness = addon.UnitFrames.Harness
local DB = addon.DB

local EditMode = {}
addon.UnitFrames.EditMode = EditMode

-- unit key -> settings page key (forever/menu.lua)
local NAV_KEYS = addon.UnitFrames.Text.NAV_KEYS

local instByFrame = setmetatable({}, { __mode = "k" })

--------------------------------------------------------------------------------
-- Store
--------------------------------------------------------------------------------
-- One layout entry per frame, with a position per Edit Mode layout inside it:
-- layout[key] = { scale, positions = { [layoutName] = { point, x, y } } }

local store = {
    get = function(key, layoutName)
        local entry = DB.GetLayout(key)
        local positions = entry and entry.positions
        return positions and positions[layoutName] or nil
    end,
    set = function(key, layoutName, point, x, y)
        local entry = DB.GetLayout(key) or {}
        entry.positions = entry.positions or {}
        entry.positions[layoutName] = { point = point, x = x, y = y }
        DB.SetLayout(key, entry)
    end,
}

--------------------------------------------------------------------------------
-- Apply
--------------------------------------------------------------------------------
-- The secure click child makes the frame anchor-protected, so a move in combat
-- is blocked. A drop cannot happen in combat (the library refuses the drag); a
-- restore can, on a reload or a layout switch. That one queues the harness's
-- position slot, whose worker re-reads the store when combat drops.

local function ApplyPosition(frame, point, x, y)
    if InCombatLockdown() then
        Harness.QueueRegen(instByFrame[frame], "position")
        return true
    end
    frame:ClearAllPoints()
    frame:SetPoint(point, x, y)
    return false
end

Harness.RegisterAction("position", function(inst)
    if inst and inst.frame then
        addon.EditMode.RestorePositionable(inst.frame)
    end
end)

--------------------------------------------------------------------------------
-- Registration
--------------------------------------------------------------------------------

--- Register one built unit frame. `default` is kept by reference: it is what
--- Reset To Default Position returns the frame to.
function EditMode.Register(inst, opts)
    if not (inst and inst.frame) then return end
    if not (addon.EditMode and addon.EditMode.RegisterPositionable) then return end

    local navKey = NAV_KEYS[opts.key]
    instByFrame[inst.frame] = inst
    inst.frame.editModeName = opts.label

    addon.EditMode.RegisterPositionable(inst.frame, {
        key = opts.key,
        default = opts.default,
        restoreDefault = true,
        store = store,
        apply = ApplyPosition,
        brand = { navKey = navKey, componentId = navKey },
    })
end
