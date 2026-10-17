--------------------------------------------------------------------------------
-- forever/statusbars/dynamic.lua
-- The Dynamic Layouts adapters for the two status bars, one per holder, both
-- under the view's Status Bars checkbox. Plain tier: nothing in the bars is
-- protected, so every channel switches live in combat. The engine's own
-- writers apply the three channels; the base values are the Opacity setting
-- and the stored position.
--
-- The engine replaces alpha rather than multiplying it, so display.lua leaves
-- a holder's alpha alone while its dynamic state holds. Blizzard's fades run
-- on the container inside, so the two never write the same frame.
--------------------------------------------------------------------------------

local addonName, addon = ...

local SB = addon.StatusBars
local Style = SB.Style
local DL = addon.DynamicLayouts

local Dynamic = {}
SB.Dynamic = Dynamic

local registered = {}

local function basePosition(index)
    return function()
        local stored = SB.EditMode and SB.EditMode.Store.get(SB.KEYS[index], addon.EditMode.GetActiveLayoutName())
        local p = stored or Style.DEFAULT_POSITIONS[index]
        return p.point, p.x, p.y
    end
end

local function applyPosition(frame, point, x, y)
    frame:ClearAllPoints()
    frame:SetPoint(point, UIParent, point, x, y)
end

function Dynamic.Register(index, frame)
    if registered[index] or not frame or not (DL and DL.Register) then return end
    registered[index] = true
    DL.Register({
        id = SB.KEYS[index],
        label = "Status Bar " .. index,
        group = SB.GROUP,
        frame = frame,
        tier = "plain",
        channels = { "opacity", "scale", "position" },
        base = {
            opacity = function() return Style.Opacity(index) / 100 end,
            scale = function() return 1 end,
            position = basePosition(index),
        },
        apply = { position = applyPosition },
    })
end

--- Re-lands the dynamic state over a base write: one bar, or both with no
--- index.
function Dynamic.Reassert(index)
    if not (DL and DL.Reassert) then return end
    for i = 1, 2 do
        if registered[i] and (index == nil or index == i) then DL.Reassert(SB.KEYS[i]) end
    end
end

function Dynamic.IsDynamic(index)
    return registered[index] and DL and DL.IsDynamic and DL.IsDynamic(SB.KEYS[index]) or false
end

function Dynamic.Describe(index)
    if not registered[index] then return "not registered" end
    return Dynamic.IsDynamic(index) and "dynamic" or "base"
end
