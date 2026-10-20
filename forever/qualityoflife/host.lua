--------------------------------------------------------------------------------
-- forever/qualityoflife/host.lua
-- Camelot's store for the Quality of Life files shared with Scoot (core/qol.lua,
-- core/smallfixes.lua, core/editmode/nudgearrows.lua, core/editmode/subgrid.lua,
-- ui/v2/settings/qol/): the keys under qol. in CamelotDB, every one off by
-- default, since each acts on a Blizzard frame or spends the player's gold.
--------------------------------------------------------------------------------

local addonName, addon = ...

local DB = addon.DB

DB.RegisterDefaults({
    ["qol.autoRepairMode"] = "off",
    ["qol.sellGreyItems"] = false,
    ["qol.quickLoot"] = false,
    ["qol.showMapCoordinates"] = false,
    ["qol.showQuestLogCount"] = false,
    ["qol.editModeNudgeArrows"] = false,
    ["qol.editModeSubGrid"] = false,
    ["qol.modifierTargetShift"] = false,
    ["qol.modifierTargetCtrl"] = false,
    ["qol.modifierTargetAlt"] = false,
})

addon.QoLHost = {
    Get = function(key) return DB.Get("qol." .. key) end,
    Set = function(key, value) DB.Set("qol." .. key, value) end,
}
