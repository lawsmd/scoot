-- qolhost.lua - Scoot's store for the shared Quality of Life files
-- The shared files (core/qol.lua, core/smallfixes.lua, core/editmode/nudgearrows.lua,
-- core/editmode/subgrid.lua, ui/v2/settings/qol/) read and write their keys through
-- addon.QoLHost; Camelot's host is forever/qualityoflife/host.lua.
local addonName, addon = ...

addon.QoLHost = {
    -- rawget, so browsing a page never creates profile.qol (zero-touch).
    Get = function(key)
        local profile = addon.db and addon.db.profile
        local qol = profile and rawget(profile, "qol")
        if qol then return qol[key] end
        return nil
    end,
    Set = function(key, value)
        local profile = addon.db and addon.db.profile
        if not profile then return end
        profile.qol = profile.qol or {}
        profile.qol[key] = value
    end,
}
