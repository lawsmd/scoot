--------------------------------------------------------------------------------
-- forever/minimap/editmode.lua
-- The host side of addon.EditMode.RegisterPositionable for the minimap
-- replica: where its position is stored, how it is applied, and the branded
-- dialog's rows. The engine is core/editmode/positionables.lua and
-- ui/v2/editmode/, shared with Scoot. The holder has no secure child, so a
-- position applies in combat too.
--
-- Map Size is the holder's scale, and a positionable's offsets are in the
-- frame's own scale, so a stored pair re-applied at another scale would move
-- the anchor point: at TOPRIGHT (-19, -44) a map at 200 percent would land
-- twice as far from the corner. The store therefore records the scale a pair
-- was stored at and hands it back converted to the base scale of the moment,
-- and the default record is kept in the current scale by SyncDefault. The
-- anchor point stays on its spot through every Map Size change, as Blizzard's
-- cluster does by scaling its container alone.
--------------------------------------------------------------------------------

local addonName, addon = ...

local MR = addon.MinimapReplica
local Style = MR.Style
local DB = addon.DB

local EditMode = {}
MR.EditMode = EditMode

-- The record LibEditMode reads by reference for Reset To Default Position.
-- Its x and y are rewritten in the current scale from the captured base
-- (display.lua, CaptureDefault), which is in UIParent's scale.
local DEFAULT = { point = "TOPRIGHT", x = 0, y = 0 }
EditMode.DEFAULT = DEFAULT

--------------------------------------------------------------------------------
-- Store
--------------------------------------------------------------------------------
-- One layout entry, with a position per Edit Mode layout inside it:
-- layout[key] = { positions = { [layoutName] = { point, x, y, scale } } }

local function baseScale()
    return Style.Scale()
end

local store = {
    get = function(key, layoutName)
        local entry = DB.GetLayout(key)
        local positions = entry and entry.positions
        local pos = positions and positions[layoutName]
        if not pos then return nil end
        local from, to = tonumber(pos.scale) or 1, baseScale()
        if from == to or to == 0 then return { point = pos.point, x = pos.x, y = pos.y } end
        return { point = pos.point, x = (pos.x or 0) * from / to, y = (pos.y or 0) * from / to }
    end,
    set = function(key, layoutName, point, x, y)
        local entry = DB.GetLayout(key) or {}
        entry.positions = entry.positions or {}
        entry.positions[layoutName] = { point = point, x = x, y = y, scale = baseScale() }
        DB.SetLayout(key, entry)
    end,
}
EditMode.Store = store

--- The captured default in the current base scale, written into the record
--- the library and the restore read.
function EditMode.SyncDefault()
    local d = MR.Display and MR.Display.CaptureDefault()
    if not d then return end
    local scale = baseScale()
    if scale == 0 then scale = 1 end
    DEFAULT.point = d.point
    DEFAULT.x = d.x / scale
    DEFAULT.y = d.y / scale
end

--------------------------------------------------------------------------------
-- Apply
--------------------------------------------------------------------------------

local function ApplyPosition(frame, point, x, y, reason)
    frame:ClearAllPoints()
    frame:SetPoint(point, UIParent, point, x, y)
    -- A restore lands the base position; if Dynamic Layouts holds the
    -- dynamic state, it puts its own position and scale back on top.
    if reason == "restore" and MR.Dynamic then
        MR.Dynamic.Reassert()
    end
    return false
end

--- After a Map Size change: the default in the new scale, then the stored
--- or default position re-landed, which keeps the anchor point in place.
function EditMode.OnScaleChanged()
    EditMode.SyncDefault()
    local frame = Style.Frame()
    if frame and addon.EditMode and addon.EditMode.RestorePositionable then
        addon.EditMode.RestorePositionable(frame)
    end
end

--------------------------------------------------------------------------------
-- The selection box's reach
--------------------------------------------------------------------------------
-- The library anchors the box over the holder's rect, the map's 198 pixels;
-- the art is wider. A round map's ring overhangs by half the difference
-- between the ring atlas and the map on every side; a square one by the
-- band. The header plate stands above the map on both.

function EditMode.Reach()
    local reach
    if Style.IsSquare() then
        local band = tonumber(Style.SQUARE_BORDER.band) or 10
        reach = { left = band, right = band, top = band, bottom = band }
    else
        local w, h = Style.RingSize()
        local side = math.max(0, (w - Style.MAP_SIZE_PX) / 2)
        local vertical = math.max(0, (h - Style.MAP_SIZE_PX) / 2)
        reach = { left = side, right = side, top = vertical, bottom = vertical }
    end
    if Style.Get("dockHide") ~= true then
        local _, headerY = Style.HeaderOffset()
        reach.top = math.max(reach.top, headerY)
    end
    return reach
end

--------------------------------------------------------------------------------
-- Registration
--------------------------------------------------------------------------------

local registered = false

--- Register the built holder, after the lease and the park.
function EditMode.Register(frame)
    if registered then return end
    if not (addon.EditMode and addon.EditMode.RegisterPositionable) then return end
    registered = true

    EditMode.SyncDefault()
    frame.editModeName = "Minimap"
    addon.EditMode.RegisterPositionable(frame, {
        key = MR.KEY,
        default = DEFAULT,
        restoreDefault = true,
        reach = EditMode.Reach(),
        store = store,
        apply = ApplyPosition,
        brand = { navKey = MR.NAV_KEY, componentId = MR.NAV_KEY, mirror = Style.EditModeMirror() },
    })

    -- Both callbacks run inside the window in which NativeFrame refuses to
    -- re-parent, so neither writes the park of Blizzard's cluster: the call
    -- schedules NativeFrame's retry, which pays it once the window closes.
    -- The exit also re-runs the lease, in case a layout apply moved the
    -- widget; none is expected to.
    addon.EditMode.OnEditMode(MR.OWNER, {
        enter = function()
            addon.NativeFrame:Reapply()
        end,
        exit = function()
            addon.NativeFrame:Reapply()
            if MR.Display then MR.Display.Lease("editmode exit") end
        end,
    })
end
