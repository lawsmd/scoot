--------------------------------------------------------------------------------
-- forever/minimap.lua
-- Camelot's side of the minimap button: its store seam. The icon is the
-- identity file's, forever/camelot.lua. The minimap itself is the replica
-- under forever/minimap/, which holds its own art constants; until 11
-- October 2026 this file also set the square border and button ring seams
-- the X component read.
--
-- The button itself is core/minimap.lua, listed on both TOCs. It reads the
-- store seam set here at login, so this file's place in the load order does
-- not matter.
--
-- Storage is a document. LibDBIcon writes minimapPos, hide and lock into the
-- table it was registered with, and `documents` is the container CamelotDB
-- keeps whole and never merges against a default, so the library owns the
-- shape (forever/db.lua). Scoot's fallback, db.profile.minimap, would put a
-- fifth key beside the four containers a profile is allowed.
--------------------------------------------------------------------------------

local addonName, addon = ...

local DOCUMENT = "minimapButton"

local DEFAULT_POSITION = 220

-- Called at login and again on every profile change, so it creates the
-- document for a profile that has never carried one.
addon.MinimapButtonStore = function()
    local doc = addon.DB and addon.DB.GetDocument(DOCUMENT)
    if type(doc) ~= "table" then
        doc = { hide = false, minimapPos = DEFAULT_POSITION }
        if addon.DB then addon.DB.SetDocument(DOCUMENT, doc) end
    end
    return doc
end
