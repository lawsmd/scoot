--------------------------------------------------------------------------------
-- forever/features.lua
-- What Camelot's Features page lists.
--
-- The page is Scoot's (ui/v2/settings/StartHereRenderer.lua), drawn from
-- addon.UI.SettingsPanel.FeaturesModel. A feature's owning file registers its
-- row here, so the list is never a second copy of the product:
--
--   addon.Features.Register({
--       group = "unitFrames", groupLabel = "Unit Frames",
--       id = "player", label = "Player",
--       path = "unitFrames.player.enabled",
--   })
--
-- `path` is a boolean setting in forever/db.lua. The page writes it and calls
-- nothing: the owner reads it through DB.SessionGet, so the change lands at the
-- reload. A feature that replaces a Blizzard frame claims addon.NativeFrame
-- from that same read, so a feature off at login never parks the frame.
--------------------------------------------------------------------------------

local addonName, addon = ...

local DB = addon.DB

addon.Features = addon.Features or {}
local Features = addon.Features

local order = {}        -- group ids, first-registration order
local categories = {}   -- group id -> { label, subToggles }
local paths = {}        -- group id -> row id -> settings path

function Features.Register(row)
    local cat = categories[row.group]
    if not cat then
        cat = { label = row.groupLabel or row.group, subToggles = {} }
        categories[row.group] = cat
        paths[row.group] = {}
        order[#order + 1] = row.group
    end
    cat.subToggles[#cat.subToggles + 1] = { id = row.id, label = row.label }
    paths[row.group][row.id] = row.path
end

local function pathFor(group, id)
    return paths[group] and paths[group][id]
end

--- The model the renderer reads. forever/menu.lua assigns it once the settings
--- panel exists; the tables fill as owners register.
function Features.BuildModel()
    return {
        pageKey = "features",
        title = "Features",
        intro = "Turn a Camelot feature off and the game's own frame takes its place after a reload.",
        columns = 2,
        order = order,
        categories = categories,

        isEnabled = function(group, id)
            local path = pathFor(group, id)
            return path ~= nil and DB.Get(path) and true or false
        end,
        setEnabled = function(group, id, value)
            local path = pathFor(group, id)
            if path then DB.Set(path, value and true or false) end
        end,

        snapshot = function()
            local snap = {}
            for _, rows in pairs(paths) do
                for _, path in pairs(rows) do
                    snap[path] = DB.Get(path) and true or false
                end
            end
            return snap
        end,
        restore = function(snap)
            for path, value in pairs(snap or {}) do
                DB.Set(path, value)
            end
        end,
    }
end
