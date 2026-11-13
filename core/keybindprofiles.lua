-- keybindprofiles.lua - Named sets of keybindings the player swaps between
local addonName, addon = ...

--------------------------------------------------------------------------------
-- Keybind profiles live in db.global, outside every layout profile, and hold
-- the same rows core/keybinds.lua writes to its string. Selecting a profile
-- changes no keys and writes nothing into it: Apply puts its keys on the
-- account and Save puts the account's keys in it, and neither runs on its own.
--
-- The selection follows Blizzard's binding set, because the set is what holds
-- the live keys: characters on the Account set share one pointer, and a
-- character with its own set has its own. The saved field is still named
-- `loaded`, from when selecting a profile applied it.
--------------------------------------------------------------------------------

local Keybinds = addon.Keybinds
local Profiles = {}
Keybinds.Profiles = Profiles

local ACCOUNT_POINTER = "account"

local UNAVAILABLE = "Keybindings are not available."
local NO_NAME = "Enter a name for the keybind profile."
local NAME_TAKEN = "A keybind profile already has that name."
local GONE = "That keybind profile no longer exists."

-- The store is created on the first write, so a player who never makes a
-- profile keeps no table in the saved variables.
local function read()
    local global = addon.db and addon.db.global
    local store = global and global.keybindProfiles
    if type(store) == "table" then return store end
    return nil
end

local function ensure()
    local store = read()
    if store then return store end
    local global = addon.db and addon.db.global
    if not global then return nil end
    store = { nextId = 1, list = {}, loaded = {} }
    global.keybindProfiles = store
    return store
end

local function pointerKey()
    if Keybinds.IsCharacterSet() then
        return (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
    end
    return ACCOUNT_POINTER
end

local function cleanName(name)
    if type(name) ~= "string" then return nil end
    name = name:match("^%s*(.-)%s*$") or ""
    if name == "" then return nil end
    return name
end

local function nameTaken(store, name, exceptId)
    local wanted = name:lower()
    for id, entry in pairs(store.list) do
        if id ~= exceptId and entry.name:lower() == wanted then return true end
    end
    return false
end

-- A fresh snapshot plus the old rows for commands this client does not list
-- now, so a save in a session with an addon disabled does not erase that
-- addon's keys from the profile.
local function snapshotOver(oldRows)
    local rows = Keybinds.Snapshot()
    if #rows == 0 then return nil end
    local known = Keybinds.KnownActions()
    for _, row in ipairs(oldRows or {}) do
        if type(row) == "table" and type(row.a) == "string" and not known[row.a] then
            rows[#rows + 1] = row
        end
    end
    return rows
end

--- Every profile as { id, name }, sorted by name.
function Profiles.List()
    local out = {}
    local store = read()
    if not store then return out end
    for id, entry in pairs(store.list) do
        out[#out + 1] = { id = id, name = entry.name }
    end
    table.sort(out, function(a, b) return a.name:lower() < b.name:lower() end)
    return out
end

--- The id of the profile selected on the current binding set, or nil.
function Profiles.SelectedId()
    local store = read()
    if not store then return nil end
    local id = store.loaded[pointerKey()]
    if id and store.list[id] then return id end
    return nil
end

--- Moves the selection and touches no keys. Returns true, or nil and a message.
function Profiles.Select(id)
    local store = read()
    if not (store and store.list[id]) then return nil, GONE end
    store.loaded[pointerKey()] = id
    return true
end

function Profiles.Name(id)
    local store = read()
    local entry = store and store.list[id]
    return entry and entry.name or nil
end

--- True when the profile holds exactly the live keys, slot for slot. A command
-- the profile has no row for counts as unbound there; a row for a command this
-- client does not list is ignored.
function Profiles.Matches(id)
    local store = read()
    local entry = store and store.list[id]
    if not entry or not Keybinds.IsAvailable() then return false end
    local saved = {}
    for _, row in ipairs(entry.rows or {}) do
        if type(row) == "table" and type(row.a) == "string" then saved[row.a] = row end
    end
    local live = Keybinds.Snapshot()
    if #live == 0 then return false end
    for _, row in ipairs(live) do
        local want = saved[row.a]
        if (want and want.k1) ~= row.k1 or (want and want.k2) ~= row.k2 then return false end
    end
    return true
end

--- Writes the live keys into the profile. Returns true, or nil and a message.
function Profiles.Save(id)
    local store = read()
    local entry = store and store.list[id]
    if not entry then return nil, GONE end
    if not Keybinds.IsAvailable() then return nil, UNAVAILABLE end
    local rows = snapshotOver(entry.rows)
    if not rows then return nil, UNAVAILABLE end
    entry.rows = rows
    entry.savedAt = time()
    return true
end

--- Stores the live keys under a new name and selects that profile. Returns the
-- id, or nil and a message.
function Profiles.Create(name)
    local clean = cleanName(name)
    if not clean then return nil, NO_NAME end
    if not Keybinds.IsAvailable() then return nil, UNAVAILABLE end
    local store = ensure()
    if not store then return nil, UNAVAILABLE end
    if nameTaken(store, clean) then return nil, NAME_TAKEN end
    local id = store.nextId
    store.nextId = id + 1
    store.list[id] = { name = clean, rows = Keybinds.Snapshot(), savedAt = time() }
    store.loaded[pointerKey()] = id
    return id
end

--- Returns true, or nil and a message.
function Profiles.Rename(id, name)
    local clean = cleanName(name)
    if not clean then return nil, NO_NAME end
    local store = read()
    local entry = store and store.list[id]
    if not entry then return nil, GONE end
    if nameTaken(store, clean, id) then return nil, NAME_TAKEN end
    entry.name = clean
    return true
end

--- Removes a profile and every pointer naming it. The live keys stay bound.
function Profiles.Delete(id)
    local store = read()
    if not (store and store.list[id]) then return nil, GONE end
    store.list[id] = nil
    for pointer, loadedId in pairs(store.loaded) do
        if loadedId == id then store.loaded[pointer] = nil end
    end
    return true
end

--- Makes the live keys the profile's. A command the profile has no row for is
-- unbound, so that Matches holds afterwards. Out of combat only. Returns the
-- counts from Keybinds.Apply, or nil and a message.
function Profiles.Apply(id)
    if InCombatLockdown() then return nil, Keybinds.COMBAT_MESSAGE end
    local store = read()
    local target = store and store.list[id]
    if not target then return nil, GONE end
    if not Keybinds.IsAvailable() then return nil, UNAVAILABLE end
    local rows, named = {}, {}
    for _, row in ipairs(target.rows or {}) do
        rows[#rows + 1] = row
        if type(row) == "table" and type(row.a) == "string" then named[row.a] = true end
    end
    for action in pairs(Keybinds.KnownActions()) do
        if not named[action] then rows[#rows + 1] = { a = action } end
    end
    return Keybinds.Apply({ data = rows })
end
