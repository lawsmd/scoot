--------------------------------------------------------------------------------
-- forever/statusbars/editmode.lua
-- The host side of addon.EditMode.RegisterPositionable for the two status
-- bars: where each position is stored, how it is applied, and the branded
-- dialog's rows. The holders are unprotected, so a position applies in combat
-- too.
--------------------------------------------------------------------------------

local addonName, addon = ...

local SB = addon.StatusBars
local Style = SB.Style
local DB = addon.DB

local EditMode = {}
SB.EditMode = EditMode

--------------------------------------------------------------------------------
-- Store
--------------------------------------------------------------------------------
-- One layout entry per bar, with a position per Edit Mode layout inside it:
-- layout[key] = { positions = { [layoutName] = { point, x, y } } }

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
EditMode.Store = store

--------------------------------------------------------------------------------
-- Apply
--------------------------------------------------------------------------------

local function applyFor(index)
    return function(frame, point, x, y, reason)
        frame:ClearAllPoints()
        frame:SetPoint(point, x, y)
        -- A restore lands the base position; if Dynamic Layouts holds the
        -- dynamic state, it puts its own back on top.
        if reason == "restore" and SB.Dynamic then
            SB.Dynamic.Reassert(index)
        end
        return false
    end
end

--------------------------------------------------------------------------------
-- Registration
--------------------------------------------------------------------------------

local registered = {}
local hooked = false

function EditMode.Register(index, frame)
    if registered[index] or not frame then return end
    if not (addon.EditMode and addon.EditMode.RegisterPositionable) then return end
    registered[index] = true

    frame.editModeName = SB.Display.Label(index)
    addon.EditMode.RegisterPositionable(frame, {
        key = SB.KEYS[index],
        default = Style.DEFAULT_POSITIONS[index],
        restoreDefault = true,
        store = store,
        apply = applyFor(index),
        brand = { navKey = SB.NAV_KEY, componentId = SB.NAV_KEY, mirror = Style.EditModeMirror(index) },
    })

    if hooked then return end
    hooked = true
    -- Both callbacks run inside the window in which NativeFrame refuses to
    -- re-parent, so neither writes the park of Blizzard's manager: the call
    -- schedules NativeFrame's retry, which pays it once the window closes.
    addon.EditMode.OnEditMode(SB.OWNER, {
        enter = function()
            addon.NativeFrame:Reapply()
            SB.Display.SetEditing(true)
        end,
        exit = function()
            addon.NativeFrame:Reapply()
            SB.Display.SetEditing(false)
        end,
    })
end
