--------------------------------------------------------------------------------
-- forever/actionbars/dynamic.lua
-- The Dynamic Layouts adapter per cluster. A container is the protected
-- tier: its members' secure buttons make it implicitly protected, so its
-- position and scale are blocked in lockdown and paid in the regen-disabled
-- window or at regen through the engine's keyed closure, while opacity is
-- legal always. The engine's own writers apply the three channels on the
-- container, and every member inherits them. The base values are 1, 1 and
-- the stored position or the cluster's captured default.
--------------------------------------------------------------------------------

local _, addon = ...

local ActionBars = addon.ActionBars
local Clusters = ActionBars.Clusters
local DL = addon.DynamicLayouts

local Dynamic = {}
ActionBars.Dynamic = Dynamic

local registered = {}

local function basePosition(id)
    return function()
        local store = ActionBars.EditMode and ActionBars.EditMode.Store
        local layoutName = addon.EditMode and addon.EditMode.GetActiveLayoutName
            and addon.EditMode.GetActiveLayoutName() or nil
        local stored = store and layoutName and store.get(Clusters.Key(id), layoutName) or nil
        if stored and stored.point then
            return stored.point, stored.x or 0, stored.y or 0
        end
        local d = Clusters.DefaultPosition(id)
        return d.point, d.x, d.y
    end
end

--- After the positionable on every layout, so its restore has landed before
--- the adapter's snap. A later pass re-registers, which refreshes the label
--- and snaps the current state onto the laid-out container.
function Dynamic.Register(cluster, container)
    if not (DL and DL.Register) then return false end
    local id = cluster.id
    registered[id] = true
    DL.Register({
        id = Clusters.Key(id),
        label = Clusters.Label(cluster),
        frame = container,
        tier = "protected",
        channels = { "opacity", "scale", "position" },
        base = {
            opacity = function() return 1 end,
            scale = function() return 1 end,
            position = basePosition(id),
        },
    })
    return true
end

--- The base geometry was just re-landed (a positionable restore): put a
--- held dynamic scale and position back on top.
function Dynamic.Reassert(id)
    if registered[id] and DL and DL.Reassert then DL.Reassert(Clusters.Key(id)) end
end

--- Whether the dynamic state holds on a cluster now.
function Dynamic.IsDynamic(id)
    return registered[id] and DL and DL.IsDynamic and DL.IsDynamic(Clusters.Key(id)) or false
end

--- A word for /camelot actionbars.
function Dynamic.Describe(id)
    if not registered[id] then return "not registered" end
    return Dynamic.IsDynamic(id) and "dynamic" or "base"
end
