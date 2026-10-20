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

-- The bar background's anchors past its bar (frames.xml), the shadow side of
-- the atlas, which the frame's own rect leaves out on every side.
local ART_REACH = { left = 2, right = 6, top = 3, bottom = 7 }

--- The selection box's reach: the background's overhang, grown over the
--- combo point row while it shows (combopoints.lua) and over the cast bar on
--- the side it hangs while it is on (castbar.lua).
function EditMode.Reach()
    local reach = ART_REACH
    if PRD.Combo then reach = PRD.Combo.Reach(reach) end
    if PRD.CastBar and PRD.CastBar.Reach then reach = PRD.CastBar.Reach(reach) end
    return reach
end

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
        reach = EditMode.Reach(),
        store = store,
        apply = ApplyPosition,
        -- Wider than the default 340: the dialog lays the four bar sections
        -- in two columns under Display (Style.EditModeMirror).
        brand = { navKey = PRD.NAV_KEY, componentId = PRD.NAV_KEY, mirror = Style.EditModeMirror(),
            dialogWidth = 520 },
    })

    -- Both callbacks run inside the window in which NativeFrame refuses to
    -- re-parent, so neither writes the park of Blizzard's frame: the call
    -- schedules NativeFrame's retry, which pays it once the window closes.
    -- Edit Mode shows the display in every visibility mode.
    addon.EditMode.OnEditMode(PRD.OWNER, {
        enter = function()
            addon.NativeFrame:Reapply()
            PRD.Display.UpdateShownState()
            PRD.Display.RefreshComboPoints()
        end,
        exit = function()
            addon.NativeFrame:Reapply()
            PRD.Display.UpdateShownState()
            PRD.Display.RefreshComboPoints()
        end,
    })
end

--- Re-fit the box after the cast bar is switched, flipped or resized. A
--- no-op before registration.
function EditMode.UpdateReach()
    local frame = Style.Frame()
    if registered and frame and addon.EditMode.UpdateReach then
        addon.EditMode.UpdateReach(frame, EditMode.Reach())
    end
end
