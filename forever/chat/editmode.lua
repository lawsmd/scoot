--------------------------------------------------------------------------------
-- forever/chat/editmode.lua
-- The host side of addon.EditMode.RegisterPositionable for the chat replica:
-- where its position is stored, how it is applied, and the branded dialog's
-- rows. The engine is core/editmode/positionables.lua and ui/v2/editmode/,
-- shared with Scoot. The holder has no secure child, so a position applies
-- in combat too.
--
-- Scale is the holder's scale, and a positionable's offsets are in the
-- frame's own scale, so the store records the scale a pair was stored at and
-- hands it back converted to the base scale of the moment, the minimap's
-- rule, and the default record is kept in the current scale by SyncDefault.
--------------------------------------------------------------------------------

local addonName, addon = ...

local CR = addon.ChatReplica
local Style = CR.Style
local DB = addon.DB

local EditMode = {}
CR.EditMode = EditMode

-- The record LibEditMode reads by reference for Reset To Default Position.
-- Its x and y are rewritten in the current scale from the captured base
-- (display.lua, CaptureDefault), which is in UIParent's scale.
local DEFAULT = { point = "BOTTOMLEFT", x = 32, y = 95 }
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

--- The default in the current base scale, written into the record the
--- library and the restore read: Camelot's spot, in the holder's own units
--- already, or where Blizzard's ChatFrame1 stood, in UIParent's units, over
--- the holder's scale.
function EditMode.SyncDefault()
    if Style.Get("defaultAnchor") ~= "blizzard" then
        local a = Style.CAMELOT_ANCHOR
        DEFAULT.point, DEFAULT.x, DEFAULT.y = a.point, a.x, a.y
        return
    end
    local d = CR.Display and CR.Display.CaptureDefault()
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
    if reason == "restore" and CR.Dynamic then
        CR.Dynamic.Reassert()
    end
    return false
end

--- After a Scale change: the default in the new scale, then the stored or
--- default position re-landed, which keeps the anchor point in place.
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
-- The library anchors the box over the holder's rect, the window's text; the
-- tabs stand above it and the edit box below, or both above, and the scroll
-- bar's gutter at the right.

function EditMode.Reach()
    local strip = Style.TAB_HEIGHT + Style.STRIP_GAP
    local boxH = Style.EDIT_BOX_HEIGHT + Style.EDIT_BOX_GAP
    local reach = { left = 5, right = Style.SCROLL_GUTTER + 8, top = strip, bottom = 0 }
    if Style.EditBoxAbove() then
        reach.top = reach.top + boxH
    else
        reach.bottom = boxH
    end
    return reach
end

--------------------------------------------------------------------------------
-- Registration
--------------------------------------------------------------------------------

local registered = false

--- Register the built holder, after the park.
function EditMode.Register(frame)
    if registered then return end
    if not (addon.EditMode and addon.EditMode.RegisterPositionable) then return end
    registered = true

    EditMode.SyncDefault()
    frame.editModeName = "Chat"
    addon.EditMode.RegisterPositionable(frame, {
        key = CR.KEY,
        default = DEFAULT,
        restoreDefault = true,
        reach = EditMode.Reach(),
        store = store,
        apply = ApplyPosition,
        brand = { navKey = CR.NAV_KEY, componentId = CR.NAV_KEY, mirror = Style.EditModeMirror() },
    })

    -- Both callbacks run inside the window in which NativeFrame refuses to
    -- re-parent, so neither writes the park of Blizzard's windows: the call
    -- schedules NativeFrame's retry, which pays it once the window closes.
    -- Edit Mode's own enter selects ChatFrame1 in Blizzard's dock and shows
    -- it, invisible under the park; the exit re-locks it.
    addon.EditMode.OnEditMode(CR.OWNER, {
        enter = function()
            addon.NativeFrame:Reapply()
        end,
        exit = function()
            addon.NativeFrame:Reapply()
        end,
    })
end
