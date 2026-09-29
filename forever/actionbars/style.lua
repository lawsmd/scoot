--------------------------------------------------------------------------------
-- forever/actionbars/style.lua
-- The action bars module: its switch, its defaults and the namespace every
-- other file in forever/actionbars/ hangs off. The presentation settings
-- (borders, text, fade) land here in the later phase.
--------------------------------------------------------------------------------

local _, addon = ...

local DB = addon.DB

addon.ActionBars = addon.ActionBars or {}
local ActionBars = addon.ActionBars

-- The owner string every claim, event and Edit Mode registration carries.
ActionBars.OWNER = "camelotActionBars"

DB.RegisterModule("actionBars", true)
DB.RegisterDefaults({
    ["actionBars.enabled"] = true,
    -- Cluster ids are handed out from here and never reused, so a deleted
    -- cluster's layout entry can never reattach to a new one. The five
    -- default clusters take 1 to 5.
    ["actionBars.nextClusterId"] = 6,
})

addon.Features.Register({
    group = "actionBars", groupLabel = "Action Bars",
    id = "actionBars", label = "Action Bars",
    path = "actionBars.enabled",
})

-- Held for the session: the Features page changes it at the reload, and a
-- feature off at login never touches a Blizzard bar.
function ActionBars.IsEnabled()
    return DB.IsModuleEnabled("actionBars")
        and DB.SessionGet("actionBars.enabled") == true
end
