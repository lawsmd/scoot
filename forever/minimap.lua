--------------------------------------------------------------------------------
-- forever/minimap.lua
-- Camelot's side of the minimap: the button's two seams and the square
-- border's art.
--
-- The button itself is core/minimap.lua, listed on both TOCs. It reads the
-- two seams set here at login, and the minimap component reads the border
-- seam at apply time, so this file's place in the load order does not
-- matter.
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

-- The mark. addon.Logo holds the colourways (forever/camelot.lua), and this is
-- the one line that picks one; the paths read through addon.MediaPath, which
-- resolves through whichever junction loaded the addon.
addon.MinimapIcon = addon.Logo.bronze

-- The square border. core/components/minimap/core.lua draws this file around
-- a square map unless the player picks the custom border or none. It is
-- Forever's own tipless ring, ui-hud-minimap-frame-circle-c60-2x, unwrapped
-- into a mitred square by docs/tools/minimapsquare.py and shipped as it came;
-- Scoot's fallback is the same cut of retail's silver ring. `band` is the
-- overhang in pixels outside the 198 px Minimap that puts the band's inner
-- edge on the map edge (the file's band is 0.0488 of its opening).
addon.MinimapSquareBorder = {
    texture = addon.MediaPath .. "forever\\media\\minimap\\square-border",
    band = 10,
}

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
