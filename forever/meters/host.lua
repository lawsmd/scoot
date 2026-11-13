--------------------------------------------------------------------------------
-- forever/meters/host.lua
-- Camelot's host for the damage meter (core/components/damagemetersY/).
--
-- The meter reads addon.MetersHost at the moment of use and, with none set,
-- falls back to the other addon's keys. This file holds the values and
-- nothing else: what the meter is called here, where its window configs and
-- window positions are stored, and the record of Blizzard's meter.
--
-- The store, in CamelotDB:
--
--   settings   damageMeter.enabled, the Features switch (forever/
--              components.lua), and damageMeterV2.<key> for each styling key,
--              through addon.ComponentStore
--   documents  meterWindows, the five window configs with their column lists.
--              A document is stored by reference, so the meter edits it in
--              place.
--   layout     meterWindow1 to meterWindow5, one position per Edit Mode layout
--   global     metersHidBlizzard, set while this addon is the one that turned
--              Blizzard's meter off. Switching the feature off then turns
--              Blizzard's back on, and a meter the player had off stays off.
--
-- The component id (damageMeterV2) and the module category (damageMeter) are
-- the other addon's tokens, kept: neither names an addon.
--------------------------------------------------------------------------------

local _, addon = ...

local DB = addon.DB

local WINDOWS_DOCUMENT = "meterWindows"
local BLIZZARD_RECORD = "metersHidBlizzard"

local function layoutKey(windowIndex)
    return "meterWindow" .. windowIndex
end

addon.MetersHost = {
    name        = addon.Brand .. " Meters",
    windowLabel = addon.Brand .. " Meter",

    -- The first sample player on the settings page's preview.
    previewName = "Arthur",

    -- The face of the menus and of every string before its first styling
    -- pass. The five text groups start on the same face (forever/
    -- components.lua, CAMELOT_LOOKS).
    fallbackFont = "FRIZQT__",

    -- The High Score window's banner: the whole 1024x512 file, the logo with
    -- clear canvas around it, at the window's own banner size.
    banner = addon.MediaPath .. "forever\\media\\CamelotBanner.png",

    -- For the debug window (dmY host): where each piece is stored.
    where = {
        windows   = "documents." .. WINDOWS_DOCUMENT,
        positions = "layout." .. layoutKey("<i>") .. ".positions[layoutName]",
        record    = "global." .. BLIZZARD_RECORD,
    },

    -- The five window configs, created empty on the first read; the meter
    -- fills each window's defaults.
    GetWindows = function()
        local doc = DB.GetDocument(WINDOWS_DOCUMENT)
        if type(doc) ~= "table" then
            doc = {}
            if not DB.SetDocument(WINDOWS_DOCUMENT, doc) then return nil end
        end
        return doc
    end,

    GetPosition = function(windowIndex, layoutName)
        local entry = DB.GetLayout(layoutKey(windowIndex))
        local positions = entry and entry.positions
        return positions and positions[layoutName] or nil
    end,

    SetPosition = function(windowIndex, layoutName, point, x, y)
        local key = layoutKey(windowIndex)
        local entry = DB.GetLayout(key) or {}
        entry.positions = entry.positions or {}
        entry.positions[layoutName] = { point = point, x = x, y = y }
        DB.SetLayout(key, entry)
    end,

    GetHidBlizzardMeter = function()
        local g = DB.Global()
        return g ~= nil and g[BLIZZARD_RECORD] == true
    end,

    SetHidBlizzardMeter = function(flag)
        local g = DB.Global()
        if g then g[BLIZZARD_RECORD] = flag and true or nil end
    end,
}
