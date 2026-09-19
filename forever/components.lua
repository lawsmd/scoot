--------------------------------------------------------------------------------
-- forever/components.lua
-- Camelot's host for the component system (core/components/base/core.lua).
--
-- A component ported from the other addon reads component.db.<key> and its
-- settings page reads the same table through ui/v2/settings/Helpers.lua. This
-- file answers that table from forever/db.lua, so nothing a component stores
-- leaves the flat settings container:
--
--   component.db.tooltipScale     -> settings["tooltip.tooltipScale"]
--   component.db.textTitle.size   -> settings["tooltip.textTitle.size"]
--
-- A key is a group, and reads as a table of its own, when its registered
-- default is a table that is not a color. Groups nest as deep as the default
-- does. A group with no registered default has no shape to read back, so a
-- component that needs one registers the default.
--
-- Defaults stay in the component's own settings table: the first link walks it
-- into DB.RegisterDefaults. A component is on or off by its Features switch,
-- read for the session, and an enabled component applies its defaults. There
-- is no unconfigured state here.
--------------------------------------------------------------------------------

local addonName, addon = ...

local DB = addon.DB

--------------------------------------------------------------------------------
-- The features this host offers
--------------------------------------------------------------------------------

-- component id -> the category its Features switch carries
local CATEGORY = {
    minimapStyle = "minimap",
    tooltip = "tooltip",
}

local FEATURES = {
    { category = "minimap", label = "Minimap" },
    { category = "tooltip", label = "Tooltip" },
}

local function switchPath(category)
    return category .. ".enabled"
end

for _, row in ipairs(FEATURES) do
    DB.RegisterDefaults({ [switchPath(row.category)] = false })
    addon.Features.Register({ group = "interface", groupLabel = "Interface",
        id = row.category, label = row.label, path = switchPath(row.category) })
end

--------------------------------------------------------------------------------
-- The module gate
--------------------------------------------------------------------------------

function addon:GetComponentCategory(componentId)
    return CATEGORY[componentId]
end

-- Held for the session: the Features page changes it at the reload. A category
-- this host does not offer is off.
function addon:IsModuleEnabled(category)
    for _, row in ipairs(FEATURES) do
        if row.category == category then
            return DB.SessionGet(switchPath(category)) == true
        end
    end
    return false
end

--------------------------------------------------------------------------------
-- The store
--------------------------------------------------------------------------------

local function isColor(t)
    local n = #t
    if n < 3 or n > 4 then return false end
    for i = 1, n do
        if type(t[i]) ~= "number" then return false end
    end
    return true
end

local function isGroup(value)
    return type(value) == "table" and not isColor(value)
end

local function registerDefaults(prefix, value, out)
    if isGroup(value) then
        for k, v in pairs(value) do
            registerDefaults(prefix .. "." .. tostring(k), v, out)
        end
    elseif value ~= nil then
        out[prefix] = value
    end
end

local proxies = {}   -- dotted prefix -> proxy

-- shape: key -> registered default, for telling a group from a value.
local function proxyFor(prefix, shape)
    local proxy = proxies[prefix]
    if proxy then return proxy end

    proxy = setmetatable({}, {
        __index = function(_, key)
            local path = prefix .. "." .. tostring(key)
            local default = shape and shape[key]
            if isGroup(default) then
                return proxyFor(path, default)
            end
            return DB.Get(path)
        end,
        __newindex = function(_, key, value)
            local path = prefix .. "." .. tostring(key)
            if isGroup(value) then
                -- A group written whole is written field by field.
                local default = shape and shape[key]
                local group = proxyFor(path, isGroup(default) and default or value)
                for k, v in pairs(value) do group[k] = v end
                return
            end
            DB.Set(path, value)
        end,
    })
    proxies[prefix] = proxy
    return proxy
end

local shapes = {}    -- component id -> key -> default

local function shapeOf(component)
    local shape = shapes[component.id]
    if shape then return shape end

    shape = {}
    local flat = {}
    for key, meta in pairs(component.settings or {}) do
        if type(meta) == "table" and meta.default ~= nil then
            shape[key] = meta.default
            registerDefaults(component.id .. "." .. key, meta.default, flat)
        end
    end
    DB.RegisterDefaults(flat)
    shapes[component.id] = shape
    return shape
end

addon.ComponentStore = {
    link = function(component)
        return proxyFor(component.id, shapeOf(component))
    end,
    sub = function(component, key)
        local shape = shapeOf(component)
        local default = shape[key]
        return proxyFor(component.id .. "." .. key, isGroup(default) and default or nil)
    end,
}

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

-- forever/db.lua is listed first, so addon.db exists by the time this runs.
addon.Events.OnAddonLoaded(addonName, function()
    -- What the nav and the search read to grey out a page whose feature is off
    -- (ui/v2/Navigation.lua, IsNavModuleActive).
    addon._activeModules = {}
    for _, row in ipairs(FEATURES) do
        addon._activeModules[row.category] = addon:IsModuleEnabled(row.category)
    end

    addon:InitializeComponents()
    addon:LinkComponentsToDB()
end)

addon.Profiles.RegisterApplyStep("camelotComponents", function(_, ctx)
    if ctx.initial then return end
    addon:ApplyStyles()
end, 30)

addon.Events.OnWorldEntered(function()
    addon:ApplyStyles()
end)
