--------------------------------------------------------------------------------
-- forever/notes/host.lua
-- Camelot's host for the Notes component (core/components/notes/).
--
-- The component reads addon.NotesHost at the moment of use. This file holds
-- where the notes and their positions are stored and nothing else.
--
-- The store, in CamelotDB:
--
--   documents  notes.list, the notes in the order made:
--              { { id, text, collapsed }, ... }
--   settings   notes.nextNoteId, the id the next note takes, and notes.<key>
--              for the look every note shares, through addon.ComponentStore
--              (forever/components.lua, where CAMELOT_LOOKS.notes is the look)
--   layout     note.<id>, the note's place: { point, x, y }
--------------------------------------------------------------------------------

local _, addon = ...

local DB = addon.DB

local LIST = "notes.list"
local NEXT_ID = "notes.nextNoteId"

local EMPTY = {}

local function layoutKey(id)
    return "note." .. tostring(id)
end

local function list()
    local doc = DB.GetDocument(LIST)
    return type(doc) == "table" and doc or nil
end

addon.NotesHost = {
    --- The live list. Read only when it is the empty stand-in.
    GetNotes = function()
        return list() or EMPTY
    end,

    --- A new empty record, appended to the list.
    NewNote = function()
        local doc = list() or {}
        local id = tonumber(DB.Get(NEXT_ID)) or 1
        DB.Set(NEXT_ID, id + 1)
        local record = { id = id, text = "" }
        doc[#doc + 1] = record
        if not DB.SetDocument(LIST, doc) then return nil end
        return record
    end,

    --- Removes the record and its layout entry.
    RemoveNote = function(id)
        local doc = list()
        if doc then
            for index, record in ipairs(doc) do
                if record.id == id then
                    table.remove(doc, index)
                    break
                end
            end
            DB.SetDocument(LIST, doc)
        end
        DB.SetLayout(layoutKey(id), nil)
    end,

    --- Writes the list back after a record was edited in place.
    Commit = function()
        local doc = list()
        if doc then DB.SetDocument(LIST, doc) end
    end,

    GetPosition = function(id)
        local entry = DB.GetLayout(layoutKey(id))
        if type(entry) ~= "table" then return nil end
        if type(entry.point) == "string" then return entry end
        -- A place stored per Edit Mode layout, the shape of 15 November 2026.
        if type(entry.positions) == "table" then
            for _, old in pairs(entry.positions) do
                if type(old) == "table" and type(old.point) == "string" then return old end
            end
        end
        return nil
    end,

    SetPosition = function(id, point, x, y)
        if id == nil then return end
        DB.SetLayout(layoutKey(id), { point = point, x = x, y = y })
    end,
}
