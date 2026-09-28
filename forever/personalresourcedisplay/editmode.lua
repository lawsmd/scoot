--------------------------------------------------------------------------------
-- forever/personalresourcedisplay/editmode.lua
-- The host side of addon.EditMode.RegisterPositionable for the Personal
-- Resource Display: where its position is stored, how it is applied, and
-- the branded dialog's rows. The engine is core/editmode/positionables.lua
-- and ui/v2/editmode/, shared with Scoot. The frame is unprotected, so a
-- position applies in combat too.
--------------------------------------------------------------------------------

local addonName, addon = ...

local PRD = addon.PersonalResourceDisplay
local Style = PRD.Style
local DB = addon.DB

local EditMode = {}
PRD.EditMode = EditMode

--------------------------------------------------------------------------------
-- Store
--------------------------------------------------------------------------------
-- One layout entry, with a position per Edit Mode layout inside it:
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

local function ApplyPosition(frame, point, x, y, reason)
    frame:ClearAllPoints()
    frame:SetPoint(point, x, y)
    -- A restore lands the base position; if Dynamic Layouts holds the
    -- dynamic state, it puts its own position and scale back on top.
    if reason == "restore" and PRD.Dynamic then
        PRD.Dynamic.Reassert()
    end
    return false
end

--------------------------------------------------------------------------------
-- Registration
--------------------------------------------------------------------------------

local registered = false

--- Register the built frame. The default is the Modern preset's anchor for
--- Blizzard's system, kept by reference: it is what Reset To Default
--- Position returns the frame to.
function EditMode.Register(frame)
    if registered then return end
    if not (addon.EditMode and addon.EditMode.RegisterPositionable) then return end
    registered = true

    frame.editModeName = "Personal Resource Display"
    addon.EditMode.RegisterPositionable(frame, {
        key = PRD.KEY,
        default = Style.DEFAULT_POSITION,
        restoreDefault = true,
        store = store,
        apply = ApplyPosition,
        brand = { navKey = PRD.NAV_KEY, componentId = PRD.NAV_KEY, mirror = Style.EditModeMirror() },
    })

    -- NativeFrame skips the re-parent while the manager is open, so entering
    -- defers the park of Blizzard's frame and leaving pays it. Edit Mode
    -- shows the display in every visibility mode.
    addon.EditMode.OnEditMode(PRD.OWNER, {
        enter = function()
            addon.NativeFrame:Reapply()
            PRD.Display.UpdateShownState()
        end,
        exit = function()
            addon.NativeFrame:Reapply()
            PRD.Display.UpdateShownState()
        end,
    })
end
