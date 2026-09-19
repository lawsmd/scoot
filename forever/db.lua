--------------------------------------------------------------------------------
-- forever/db.lua
-- CamelotDB: profiles from AceDB, values from a defaults registry.
--
-- AceDB manages the profile list, profileKeys, copy, reset, and the callbacks
-- the settings UI listens to. It does not manage defaults. Its defaults
-- mechanism is a metatable proxy, and a write through that proxy materializes
-- the table it walked, which is where the other addon's partial sub-tables and
-- its unset-versus-set-to-the-default ambiguity came from. So defaults live in
-- a registry keyed by the same dotted paths the profile stores, Get resolves
-- against it, and there is one read path.
--
-- A profile holds four tables, each with one rule:
--
--   modules    enabled-ness, nothing else
--   settings   scalars at flat dotted paths; a color is four numbers
--   documents  tables the player authored, stored whole, never merged
--   layout     one position per movable frame, always the same shape
--
-- nil means one thing: this key was never set, so the registered default
-- answers. A setting that defers to a game CVar stores the string "inherit".
-- A setting that has an off state stores false.
--------------------------------------------------------------------------------

local addonName, addon = ...

local DB = {}
addon.DB = DB

--------------------------------------------------------------------------------
-- Schema and migrations
--------------------------------------------------------------------------------

local SCHEMA_VERSION = 1

-- Numbered, run in order against the raw saved variable before AceDB sees it,
-- so a migration can move a key without fighting a live proxy. Migration 1 is
-- the empty one that stamps a fresh file, written before there is anything to
-- move because writing the first one later is what makes the rest expensive.
local MIGRATIONS = {
    [1] = function(sv)
        sv.global = sv.global or {}
        sv.profiles = sv.profiles or {}
    end,
}

local function runMigrations(sv)
    local from = tonumber(sv.schemaVersion) or 0
    for v = from + 1, SCHEMA_VERSION do
        local fn = MIGRATIONS[v]
        if fn then fn(sv) end
        sv.schemaVersion = v
    end
    -- A file written by a newer build is left alone rather than downgraded.
    if (tonumber(sv.schemaVersion) or 0) < SCHEMA_VERSION then
        sv.schemaVersion = SCHEMA_VERSION
    end
end

--------------------------------------------------------------------------------
-- The defaults registry
--------------------------------------------------------------------------------

local defaults = {}
local moduleDefaults = {}

--- Register defaults as a flat map of dotted path to value. Called by a module
--- at load, before the database is read, so Get answers the same way at any
--- point in the load order.
function DB.RegisterDefaults(map)
    if type(map) ~= "table" then return false end
    for path, value in pairs(map) do
        if type(path) == "string" then defaults[path] = value end
    end
    return true
end

--- Register a module and whether it is on for a profile that never said.
function DB.RegisterModule(id, enabledByDefault)
    if type(id) ~= "string" then return false end
    moduleDefaults[id] = enabledByDefault and true or false
    return true
end

function DB.Default(path)
    return defaults[path]
end

--------------------------------------------------------------------------------
-- Initialization
--------------------------------------------------------------------------------

local CONTAINERS = { "modules", "settings", "documents", "layout" }

-- Created here rather than through AceDB defaults, so no proxy stands between
-- a read and the stored value. Re-run on every profile transition, because a
-- new or reset profile arrives empty.
local function ensureContainers(profile)
    if type(profile) ~= "table" then return end
    for _, key in ipairs(CONTAINERS) do
        profile[key] = profile[key] or {}
    end
end

function DB.Initialize()
    if addon.db then return addon.db end

    local sv = _G.CamelotDB
    if type(sv) ~= "table" then
        sv = {}
        _G.CamelotDB = sv
    end
    runMigrations(sv)

    -- nil defaults on purpose. The third argument picks the shared "Default"
    -- profile rather than one per character.
    addon.db = LibStub("AceDB-3.0"):New("CamelotDB", nil, true)
    ensureContainers(addon.db.profile)

    -- The Global Font and Bar Texture values behind the media tokens. The
    -- shared resolvers (core/fonts.lua, core/media.lua) and core/apply_all.lua
    -- read and write this one table on both hosts, under Scoot's key names:
    -- headerFont, bodyFont, barTexture. Empty means every global answers from
    -- the getter fallbacks in apply_all.lua, so nil still reads as never set.
    addon.db.global.media = addon.db.global.media or {}

    local watcher = {}
    local function onProfile()
        ensureContainers(addon.db.profile)
        DB.ClearSession()
        if DB.OnProfileChanged then DB.OnProfileChanged() end
    end
    addon.db.RegisterCallback(watcher, "OnProfileChanged", onProfile)
    addon.db.RegisterCallback(watcher, "OnProfileCopied", onProfile)
    addon.db.RegisterCallback(watcher, "OnProfileReset", onProfile)
    addon.db.RegisterCallback(watcher, "OnNewProfile", onProfile)
    DB._watcher = watcher

    return addon.db
end

addon.Events.OnAddonLoaded(addonName, function() DB.Initialize() end)

--------------------------------------------------------------------------------
-- Access
--------------------------------------------------------------------------------

local function profileTable()
    return addon.db and addon.db.profile or nil
end

function DB.Global()
    return addon.db and addon.db.global or nil
end

function DB.Profile()
    return profileTable()
end

-- A color is the one table shape settings accepts: three or four numbers,
-- copied in and copied out so no caller holds a reference into the saved
-- variable.
local function colorCopy(t)
    local n = #t
    if n < 3 or n > 4 then return nil end
    for i = 1, n do
        if type(t[i]) ~= "number" then return nil end
    end
    return { t[1], t[2], t[3], t[4] }
end

--- The stored value at path, or the registered default when nothing is stored.
function DB.Get(path)
    local p = profileTable()
    local stored = p and p.settings[path]
    if stored == nil then return defaults[path] end
    if type(stored) == "table" then return colorCopy(stored) or defaults[path] end
    return stored
end

--- Write the whole value at path. nil clears it back to the default. A nested
--- table is refused: a scalar has no parts, and anything the player authored
--- belongs in documents.
function DB.Set(path, value)
    local p = profileTable()
    if not p or type(path) ~= "string" then return false, "no profile" end

    local t = type(value)
    if value == nil then
        p.settings[path] = nil
        return true
    elseif t == "string" or t == "number" or t == "boolean" then
        p.settings[path] = value
        return true
    elseif t == "table" then
        local color = colorCopy(value)
        if not color then return false, "settings takes scalars and colors; use a document" end
        p.settings[path] = color
        return true
    end
    return false, "unsupported value type " .. t
end

-- What a feature switch read the first time it was asked, this session. The
-- Features page writes the stored value and the running session keeps the
-- old one, so a feature turns on or off at the reload and not under a later
-- reconcile. A profile change starts over.
local session = {}

--- DB.Get, held for the session from the first read after the profile loads.
function DB.SessionGet(path)
    if session[path] ~= nil then return session[path] end
    local value = DB.Get(path)
    if profileTable() and value ~= nil then
        session[path] = value
    end
    return value
end

--- Drop one held value, or all of them with no path.
function DB.ClearSession(path)
    if path then
        session[path] = nil
    else
        wipe(session)
    end
end

--- A document is returned exactly as it was written and is never merged
--- against a default.
function DB.GetDocument(key)
    local p = profileTable()
    return p and p.documents[key] or nil
end

function DB.SetDocument(key, doc)
    local p = profileTable()
    if not p or type(key) ~= "string" then return false end
    p.documents[key] = doc
    return true
end

function DB.GetLayout(key)
    local p = profileTable()
    return p and p.layout[key] or nil
end

function DB.SetLayout(key, entry)
    local p = profileTable()
    if not p or type(key) ~= "string" then return false end
    p.layout[key] = entry
    return true
end

function DB.IsModuleEnabled(id)
    local p = profileTable()
    local row = p and p.modules[id]
    if row == nil or row.enabled == nil then
        return moduleDefaults[id] and true or false
    end
    return row.enabled and true or false
end

function DB.SetModuleEnabled(id, on)
    local p = profileTable()
    if not p or type(id) ~= "string" then return false end
    p.modules[id] = p.modules[id] or {}
    p.modules[id].enabled = on and true or false
    return true
end

--------------------------------------------------------------------------------
-- The dump
--------------------------------------------------------------------------------

local function sortedKeys(t)
    local keys = {}
    for k in pairs(t or {}) do keys[#keys + 1] = tostring(k) end
    table.sort(keys)
    return keys
end

function DB.Dump()
    local lines, push = addon.DebugLines("=== CamelotDB ===", "")

    if not addon.db then
        push("Not initialized. The saved variable arrives with ADDON_LOADED.")
        addon.DebugShowWindow("Camelot", lines)
        return
    end

    local sv = _G.CamelotDB
    push("schemaVersion:  %s  (code expects %d)",
        tostring(sv and sv.schemaVersion), SCHEMA_VERSION)
    push("active profile: %s", tostring(addon.db:GetCurrentProfile()))
    push("profiles:       %s", table.concat(addon.db:GetProfiles() or {}, ", "))

    push("")
    push("global")
    for _, k in ipairs(sortedKeys(addon.db.global)) do
        local v = addon.db.global[k]
        if type(v) == "table" then
            -- One level down, so media's three values and the window
            -- geometry read without a second command.
            local inner = sortedKeys(v)
            push("  %-22s %s", k, #inner == 0 and "{}" or "")
            for _, ik in ipairs(inner) do
                local iv = v[ik]
                push("    %-20s %s", ik, type(iv) == "table" and "{table}" or tostring(iv))
            end
        else
            push("  %-22s %s", k, tostring(v))
        end
    end

    local p = profileTable()
    push("")
    push("modules")
    local mods = sortedKeys(p.modules)
    if #mods == 0 then
        push("  nothing stored; every module answers from its registered default")
    end
    for _, id in ipairs(mods) do
        push("  %-22s enabled=%s", id, tostring(p.modules[id].enabled))
    end

    push("")
    push("settings (%d stored, %d defaults registered)",
        #sortedKeys(p.settings), #sortedKeys(defaults))
    for _, path in ipairs(sortedKeys(p.settings)) do
        local v = p.settings[path]
        push("  %-40s %s", path, type(v) == "table" and "{color}" or tostring(v))
    end

    push("")
    push("documents (%d)", #sortedKeys(p.documents))
    for _, key in ipairs(sortedKeys(p.documents)) do
        local doc = p.documents[key]
        push("  %-40s %s", key, type(doc) == "table" and ("#" .. #doc) or tostring(doc))
    end

    push("")
    push("layout (%d)", #sortedKeys(p.layout))
    for _, key in ipairs(sortedKeys(p.layout)) do
        -- One position per Edit Mode layout (forever/unitframes/editmode.lua).
        local e = p.layout[key] or {}
        push("  %-30s scale %s", key, tostring(e.scale))
        for _, layoutName in ipairs(sortedKeys(e.positions or {})) do
            local pos = e.positions[layoutName]
            push("    %-28s %s %.0f, %.0f",
                layoutName, tostring(pos.point), pos.x or 0, pos.y or 0)
        end
    end

    addon.DebugShowWindow("Camelot", lines)
end
