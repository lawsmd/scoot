--------------------------------------------------------------------------------
-- forever/minimap/dynamic.lua
-- The Dynamic Layouts adapter for the minimap replica: a plain-tier frame
-- (no secure descendant), so every channel switches live in combat. The
-- engine's own writers apply the three channels; the base values are Map
-- Size and the stored position. The holder's children, the border and the
-- text, inherit its alpha and scale, which is why they are children.
--
-- The engine replaces alpha rather than multiplying it, and the replica has
-- no opacity setting of its own, so the base opacity is 1.
--------------------------------------------------------------------------------

local addonName, addon = ...

local MR = addon.MinimapReplica
local Style = MR.Style
local DL = addon.DynamicLayouts

local Dynamic = {}
MR.Dynamic = Dynamic

local ID = MR.KEY

local registered = false

-- The stored pair, converted by the store to the base scale, or the default
-- record, kept in that scale by editmode.lua.
local function basePosition()
    local stored = MR.EditMode and MR.EditMode.Store.get(ID, addon.EditMode.GetActiveLayoutName())
    local p = stored or (MR.EditMode and MR.EditMode.DEFAULT)
    if not p then return "TOPRIGHT", 0, 0 end
    return p.point, p.x, p.y
end

local function applyPosition(frame, point, x, y)
    frame:ClearAllPoints()
    frame:SetPoint(point, UIParent, point, x, y)
end

--- After the positionable, so its restore has landed before the adapter's
--- snap.
function Dynamic.Register(frame)
    if registered or not (DL and DL.Register) then return end
    registered = true
    DL.Register({
        id = ID,
        label = "Minimap",
        frame = frame,
        tier = "plain",
        channels = { "opacity", "scale", "position" },
        base = {
            opacity = function() return 1 end,
            scale = Style.Scale,
            position = basePosition,
        },
        apply = { position = applyPosition },
    })
end

--- The base geometry was just re-landed (a settings apply, a positionable
--- restore): put a held dynamic scale and position back on top.
function Dynamic.Reassert()
    if registered and DL and DL.Reassert then DL.Reassert(ID) end
end

--- Whether the dynamic state holds now.
function Dynamic.IsDynamic()
    return registered and DL and DL.IsDynamic and DL.IsDynamic(ID) or false
end

--- A line for /camelot map.
function Dynamic.Describe()
    if not registered then return "not registered" end
    return Dynamic.IsDynamic() and "dynamic" or "base"
end
