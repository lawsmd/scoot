--------------------------------------------------------------------------------
-- forever/qualityoflife/messages.lua
-- The place of Blizzard's error and quest progress text: the two settings,
-- their defaults, and the row two pages draw over them. The text is
-- UIErrorsFrame, one MessageFrame for the red error lines ("Not enough mana")
-- and the yellow quest progress lines ("Bears slain: 4/5"), anchored TOP 0,
-- -122 on UIParent by Blizzard's XML (Blizzard_UIErrorsFrame/Mainline/
-- UIErrorsFrame.xml) and never re-anchored by its Lua. The Current Objectives
-- cards stand in the same band, so the Misc page and the Current Objectives
-- page both carry the row.
--
-- Loads on both clients for the pages. The apply that moves the frame is
-- messagesdisplay.lua, Forever only; the row calls it when it exists.
--------------------------------------------------------------------------------

local addonName, addon = ...

local DB = addon.DB

addon.QualityOfLife = addon.QualityOfLife or {}
local Messages = {}
addon.QualityOfLife.Messages = Messages

Messages.NAV_KEY = "qolMisc"

-- The frame's XML anchor, the spot the offsets count from.
Messages.XML_ANCHOR = { point = "TOP", x = 0, y = -122 }

Messages.OFFSET = { min = -400, max = 400, step = 1, default = 0 }

Messages.PATH_X = "qol.messagesOffsetX"
Messages.PATH_Y = "qol.messagesOffsetY"

-- 0 and 0: Blizzard's own spot, and the frame untouched until a move, the
-- rule for a feature that restyles a Blizzard frame in place.
DB.RegisterDefaults({ [Messages.PATH_X] = 0, [Messages.PATH_Y] = 0 })

local function clamp(value)
    value = tonumber(value) or Messages.OFFSET.default
    if value < Messages.OFFSET.min then return Messages.OFFSET.min end
    if value > Messages.OFFSET.max then return Messages.OFFSET.max end
    return value
end

--- The stored offsets from the XML anchor, x then y. Positive y is up.
function Messages.Offsets()
    return clamp(DB.Get(Messages.PATH_X)), clamp(DB.Get(Messages.PATH_Y))
end

function Messages.SetOffset(axis, value)
    DB.Set(axis == "y" and Messages.PATH_Y or Messages.PATH_X, clamp(value))
end

-- The info icon both rows carry. `other` names the page that holds the
-- row's twin.
local function infoIcon(other)
    return {
        tooltipTitle = "Error & Quest Text",
        tooltipText = "The yellow quest progress lines (\"Bears slain: 4/5\") and the red error messages (\"Not enough mana\") are one Blizzard element, so moving one moves both.\n\nThe same slider is on " .. other .. ". A change on either page changes both.",
    }
end

--- The Position row, X and Y over the two keys. opts.other names the other
--- page for the info icon.
function Messages.AddPositionRow(builder, opts)
    opts = opts or {}
    return builder:AddOffsetPair({
        label = "Position",
        min = Messages.OFFSET.min, max = Messages.OFFSET.max, step = Messages.OFFSET.step,
        infoIcon = infoIcon(opts.other or "the other page"),
        get = function(axis)
            local x, y = Messages.Offsets()
            return axis == "y" and y or x
        end,
        set = function(axis, value) Messages.SetOffset(axis, value) end,
        apply = function()
            -- Forever only (messagesdisplay.lua); on retail the row stores alone.
            if Messages.Apply then Messages.Apply() end
        end,
    })
end
