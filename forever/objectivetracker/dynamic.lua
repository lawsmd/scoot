--------------------------------------------------------------------------------
-- forever/objectivetracker/dynamic.lua
-- The Dynamic Layouts adapters for the objective tracker's two panes. The
-- roots are unprotected, but the secure quest item buttons stand on the
-- blocks by screen coordinate and follow only out of lockdown, so each
-- adapter takes the engine's protected posture: position and scale snap
-- inside the regen-disabled window on combat entry, with the item pass run
-- at once, and a mid-combat edge pays at regen through the engine's keyed
-- closure. Opacity is live in every state. The tracker's own instance-combat
-- fade writes the headers, never the root, so the root alpha here multiplies
-- over it.
--------------------------------------------------------------------------------

local addonName, addon = ...

local OT = addon.ObjectiveTracker
local DB = addon.DB

local Dynamic = {}
OT.Dynamic = Dynamic

local paneByFrame = setmetatable({}, { __mode = "k" })

-- The stored position for the active layout, else the pane's default: what
-- the positionable restore applies (tracker.lua).
local function basePosition(pane)
    local entry = DB.GetLayout(pane.key)
    local layoutName = addon.EditMode.GetActiveLayoutName()
    local pos = entry and entry.positions and layoutName and entry.positions[layoutName]
    if pos and pos.point then
        return pos.point, pos.x or 0, pos.y or 0
    end
    local d = pane.default
    return d.point, d.x or 0, d.y or 0
end

-- The buttons re-place on every final write: at once when they are writable,
-- which inside the regen-disabled window is before lockdown.
local function replaceItems()
    if OT.Items then OT.Items.Reposition(true) end
end

--- From RegisterEditMode, after the pane's positionable.
function Dynamic.Register(pane, frame)
    local DL = addon.DynamicLayouts
    if not (DL and DL.Register and pane and frame) then return end
    paneByFrame[frame] = pane
    local Style = OT.Style
    DL.Register({
        id = pane.key,
        label = pane.name,
        frame = frame,
        tier = "protected",
        channels = { "opacity", "scale", "position" },
        base = {
            opacity = function() return 1 end,
            scale = function() return Style.Scale(Style[pane.styleKey]) end,
            position = function() return basePosition(pane) end,
        },
        apply = {
            scale = function(f, s)
                f:SetScale(s)
                replaceItems()
            end,
            position = function(f, point, x, y)
                f:ClearAllPoints()
                f:SetPoint(point, UIParent, point, x, y)
                replaceItems()
            end,
        },
    })
end

--- After a component pass re-landed a base: one pane's frame, or every pane.
function Dynamic.Reassert(frame)
    local DL = addon.DynamicLayouts
    if not (DL and DL.Reassert) then return end
    if frame then
        local pane = paneByFrame[frame]
        if pane then DL.Reassert(pane.key) end
        return
    end
    for _, pane in pairs(paneByFrame) do
        DL.Reassert(pane.key)
    end
end
