--------------------------------------------------------------------------------
-- forever/chat/dynamic.lua
-- The Dynamic Layouts adapter for the chat replica: a plain-tier frame (no
-- secure descendant; nothing in Blizzard's chat tree is protected either),
-- so every channel switches live in combat. The holder's children, the
-- twins, the strip and the chrome, inherit its alpha and scale; Blizzard's
-- edit box, a UIParent child anchored to the holder, follows a slide by its
-- anchors and takes the scale from the final writer below. Its alpha is
-- Blizzard's own on every activate and deactivate, so the opacity channel
-- leaves it alone.
--
-- The engine replaces alpha rather than multiplying it, and the replica's
-- background opacity lives on the inner chrome layer, so the base opacity
-- is 1.
--------------------------------------------------------------------------------

local addonName, addon = ...

local CR = addon.ChatReplica
local Style = CR.Style
local DL = addon.DynamicLayouts

local Dynamic = {}
CR.Dynamic = Dynamic

local ID = CR.KEY

local registered = false

-- The stored pair, converted by the store to the base scale, or the default
-- record, kept in that scale by editmode.lua.
local function basePosition()
    local stored = CR.EditMode and CR.EditMode.Store.get(ID, addon.EditMode.GetActiveLayoutName())
    local p = stored or (CR.EditMode and CR.EditMode.DEFAULT)
    if not p then return "BOTTOMLEFT", 32, 95 end
    return p.point, p.x, p.y
end

local function applyPosition(frame, point, x, y)
    frame:ClearAllPoints()
    frame:SetPoint(point, UIParent, point, x, y)
end

local function applyScale(frame, scale)
    frame:SetScale(scale)
    if CR.EditBox then CR.EditBox.SetScale(scale) end
end

--- After the positionable, so its restore has landed before the adapter's
--- snap.
function Dynamic.Register(frame)
    if registered or not (DL and DL.Register) then return end
    registered = true
    DL.Register({
        id = ID,
        label = "Chat",
        frame = frame,
        tier = "plain",
        channels = { "opacity", "scale", "position" },
        base = {
            opacity = function() return 1 end,
            scale = Style.Scale,
            position = basePosition,
        },
        apply = { position = applyPosition, scale = applyScale },
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

--- A line for /camelot chat.
function Dynamic.Describe()
    if not registered then return "not registered" end
    return Dynamic.IsDynamic() and "dynamic" or "base"
end
