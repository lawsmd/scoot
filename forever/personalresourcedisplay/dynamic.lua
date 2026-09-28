--------------------------------------------------------------------------------
-- forever/personalresourcedisplay/dynamic.lua
-- The Dynamic Layouts adapter for the Personal Resource Display: a plain-tier
-- frame (no secure descendant, clicks off), so every channel switches live
-- in combat, which is where a PRD lives. The engine's own writers apply the
-- three channels; the base values are the settings and the stored position.
--
-- The engine replaces alpha rather than multiplying it, so the base opacity
-- is the Opacity setting and style.lua leaves the frame's alpha alone while
-- the dynamic state holds.
--------------------------------------------------------------------------------

local addonName, addon = ...

local PRD = addon.PersonalResourceDisplay
local Style = PRD.Style
local DL = addon.DynamicLayouts

local Dynamic = {}
PRD.Dynamic = Dynamic

local ID = PRD.NAV_KEY

local registered = false

local function basePosition()
    local stored = PRD.EditMode and PRD.EditMode.Store.get(ID, addon.EditMode.GetActiveLayoutName())
    local p = stored or Style.DEFAULT_POSITION
    return p.point, p.x, p.y
end

--- After the positionable, so its restore has landed before the adapter's
--- snap.
function Dynamic.Register(frame)
    if registered or not (DL and DL.Register) then return end
    registered = true
    DL.Register({
        id = ID,
        label = "Personal Resource Display",
        frame = frame,
        tier = "plain",
        channels = { "opacity", "scale", "position" },
        base = {
            opacity = function() return Style.Opacity() / 100 end,
            scale = function() return Style.Scale() / 100 end,
            position = basePosition,
        },
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

--- A line for /camelot prd.
function Dynamic.Describe()
    if not registered then return "not registered" end
    return Dynamic.IsDynamic() and "dynamic" or "base"
end
