-- noteshost.lua - Scoot's store for the shared Notes component
-- (core/components/notes/). The component reads addon.NotesHost at the moment
-- of use; Camelot's host is forever/notes/host.lua.
--
-- profile.noteData = {
--     list      = { { id, text, collapsed }, ... }   the notes, in the order made
--     nextId    = number                             the id the next note takes
--     positions = { [id] = { point, x, y } }         one place per note
-- }
-- The table is made when the first note is, so a profile with no note holds
-- nothing. The five fixed notes that came before kept their text in
-- profile.components.notes and their places in profile.notePositions; both
-- are left where they are, unread.
local addonName, addon = ...

local EMPTY = {}

local function data(create)
    local profile = addon.db and addon.db.profile
    if not profile then return nil end
    local store = rawget(profile, "noteData")
    if type(store) ~= "table" then
        if not create then return nil end
        store = { list = {}, nextId = 1, positions = {} }
        profile.noteData = store
    end
    store.list = store.list or {}
    store.positions = store.positions or {}
    return store
end

addon.NotesHost = {
    --- The live list. Read only when it is the empty stand-in.
    GetNotes = function()
        local store = data(false)
        return store and store.list or EMPTY
    end,

    --- A new empty record, appended to the list.
    NewNote = function()
        local store = data(true)
        if not store then return nil end
        local id = tonumber(store.nextId) or 1
        store.nextId = id + 1
        local record = { id = id, text = "" }
        store.list[#store.list + 1] = record
        return record
    end,

    --- Removes the record and every position stored for it.
    RemoveNote = function(id)
        local store = data(false)
        if not store then return end
        for index, record in ipairs(store.list) do
            if record.id == id then
                table.remove(store.list, index)
                break
            end
        end
        store.positions[id] = nil
    end,

    --- The records are edited in place, so there is nothing to write back.
    Commit = function() end,

    GetPosition = function(id)
        local store = data(false)
        local place = store and store.positions[id]
        if type(place) ~= "table" then return nil end
        if type(place.point) == "string" then return place end
        -- A place stored per Edit Mode layout, the shape of 15 November 2026.
        for _, old in pairs(place) do
            if type(old) == "table" and type(old.point) == "string" then return old end
        end
        return nil
    end,

    SetPosition = function(id, point, x, y)
        local store = data(false)
        if not store or id == nil then return end
        store.positions[id] = { point = point, x = x, y = y }
    end,
}
