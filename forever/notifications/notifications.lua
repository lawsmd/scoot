--------------------------------------------------------------------------------
-- forever/notifications/notifications.lua
-- Notifications: short toasts that fade in while rising to one Edit Mode
-- anchor, hold there and fade out. Any feature can send one. This file holds
-- the shared settings and the registry of sources; display.lua draws.
--
-- A source is a feature able to send. It registers in two halves:
--
--   Notifications.RegisterSource({ id, label, where, navKey, isEnabled })
--     at file scope of a file both clients load. label is the feature's name
--     and where its place in the menu ("Quality of Life > Professions"); the
--     Notifications page lists both, so a feature cannot send unlisted.
--     isEnabled() is the feature's own switch.
--
--   Notifications.SetPainter(id, painter)
--     from a file Forever alone loads, the drawing half:
--       build(toast)                the source's regions, once per pooled frame
--       show(toast, data, metrics)  fill the frame; returns its width, height
--       arrive(toast)               at the anchor; returns the seconds it
--                                   animates, which the hold waits out
--       update(toast, data, there)  the same data.key pushed while the toast
--                                   is live; `there` is false while it is
--                                   still rising; returns seconds as arrive
--       tick(toast, elapsed)        optional, every frame while live
--       sample()                    data for the Edit Mode preview and the
--                                   Test buttons
--
-- Notifications.Push(id, data) sends. data.key names what the toast is
-- about: a push whose key matches a live toast of the same source updates
-- that toast, and any other push stacks a new one.
--
-- The page's settings are the look every source shares: metrics carries the
-- text size, the icon side, the face and the style into show. What belongs
-- to one source alone is set in that feature's own section, which opens with
-- Notifications.AddSettingsLink.
--
-- Loads on both clients for the pages.
--------------------------------------------------------------------------------

local addonName, addon = ...

local DB = addon.DB

local Notifications = {}
addon.Notifications = Notifications

Notifications.NAV_KEY = "qolNotifications"

Notifications.DIRECTIONS = {
    values = { up = "Up", down = "Down", left = "Left", right = "Right" },
    order = { "up", "down", "left", "right" },
}
Notifications.SIZE = { min = 12, max = 48, step = 1 }
Notifications.HOLD = { min = 1, max = 10, step = 0.5, default = 3 }

-- The icon's side against the text size.
Notifications.ICON_RATIO = 1.25

local PREFIX = "notifications."

DB.RegisterDefaults({
    [PREFIX .. "direction"] = "up",
    [PREFIX .. "hold"] = Notifications.HOLD.default,
    -- The outline vanilla's own text over the world carries (the zone and
    -- PvP lines); a shadow alone is lost against the scene.
    [PREFIX .. "fontStyle"] = "THICKOUTLINE",
    -- fontFace and size carry no default: nil is the face and the size of the
    -- font object below, so the text follows the client's own face.
})

function Notifications.Get(key)
    return DB.Get(PREFIX .. key)
end

function Notifications.Set(key, value)
    DB.Set(PREFIX .. key, value)
    -- Forever only (display.lua); on retail the row stores alone.
    if Notifications.Apply then Notifications.Apply() end
end

--------------------------------------------------------------------------------
-- The shared look
--------------------------------------------------------------------------------

-- Vanilla's font object for a short line over the world.
local function fontObject()
    return _G.PVPInfoTextFont or _G.GameFontNormalHuge or _G.GameFontNormal
end

--- The face and size the font object carries, for the page's rows while
--- nothing is stored.
function Notifications.FontDefaults()
    local object = fontObject()
    local face, size
    if object and object.GetFont then face, size = object:GetFont() end
    size = tonumber(size) or 22
    return face, math.floor(size + 0.5)
end

local function clamp(value, range, fallback)
    value = tonumber(value) or fallback
    if value < range.min then return range.min end
    if value > range.max then return range.max end
    return value
end

--- What every source draws with: { size, iconSize, face, style }.
function Notifications.Metrics()
    local objectFace, objectSize = Notifications.FontDefaults()
    local size = clamp(Notifications.Get("size"), Notifications.SIZE, objectSize)
    local stored = Notifications.Get("fontFace")
    local face = stored and addon.ResolveFontFace and addon.ResolveFontFace(stored) or objectFace
    return {
        size = size,
        iconSize = math.floor(size * Notifications.ICON_RATIO + 0.5),
        face = face,
        style = Notifications.Get("fontStyle") or "THICKOUTLINE",
    }
end

function Notifications.Direction()
    local direction = Notifications.Get("direction")
    if Notifications.DIRECTIONS.values[direction] then return direction end
    return "up"
end

function Notifications.Hold()
    return clamp(Notifications.Get("hold"), Notifications.HOLD, Notifications.HOLD.default)
end

--------------------------------------------------------------------------------
-- Sources
--------------------------------------------------------------------------------

local sources = {}
local byId = {}

function Notifications.RegisterSource(def)
    if type(def) ~= "table" or type(def.id) ~= "string" or def.id == "" then
        error("Notifications.RegisterSource: id must be a non-empty string", 2)
    end
    if type(def.label) ~= "string" or def.label == "" or type(def.where) ~= "string" or def.where == "" then
        error(("Notifications.RegisterSource: '%s' needs label and where"):format(def.id), 2)
    end
    if byId[def.id] then
        error(("Notifications.RegisterSource: '%s' is already registered"):format(def.id), 2)
    end
    local source = {
        id = def.id, label = def.label, where = def.where,
        navKey = def.navKey, isEnabled = def.isEnabled,
    }
    byId[def.id] = source
    sources[#sources + 1] = source
    return source
end

function Notifications.SetPainter(id, painter)
    local source = byId[id]
    if not source then
        error(("Notifications.SetPainter: '%s' is not a registered source"):format(tostring(id)), 2)
    end
    if type(painter) ~= "table" or type(painter.build) ~= "function" or type(painter.show) ~= "function" then
        error(("Notifications.SetPainter: '%s' needs build and show"):format(id), 2)
    end
    source.painter = painter
end

function Notifications.Source(id)
    return byId[id]
end

--- The registered sources in registration order, a copy.
function Notifications.Sources()
    local list = {}
    for i, source in ipairs(sources) do list[i] = source end
    return list
end

function Notifications.IsEnabled(source)
    if not source then return false end
    if source.isEnabled then return source.isEnabled() and true or false end
    return true
end

function Notifications.AnyEnabled()
    for _, source in ipairs(sources) do
        if Notifications.IsEnabled(source) then return true end
    end
    return false
end

--- The body of the Notifications page's info icon, built from the registry.
function Notifications.SourcesText()
    local text
    if #sources == 0 then
        text = "No feature sends notifications yet."
    else
        text = "These features can send notifications:\n"
        for _, source in ipairs(sources) do
            text = text .. "\n" .. source.label .. " (" .. source.where .. ")"
        end
    end
    return text .. "\n\nEach feature's switch and its own options are in its section. "
        .. "This page sets how every notification looks and moves."
end

--- Send one. Returns true when a toast showed or an existing one took the
--- update. An unregistered id is a programming error and raises.
function Notifications.Push(id, data)
    local source = byId[id]
    if not source then
        error(("Notifications.Push: '%s' is not a registered source"):format(tostring(id)), 2)
    end
    if not Notifications.IsEnabled(source) then return false end
    -- Forever only (display.lua).
    if not Notifications.Show then return false end
    return Notifications.Show(source, data or {})
end

--------------------------------------------------------------------------------
-- The link every source's section opens with
--------------------------------------------------------------------------------

--- A button row that opens the Notifications page. The first row of a
--- notifiable feature's own section.
function Notifications.AddSettingsLink(builder)
    return builder:AddButtonRow({ buttons = {
        { text = "Notification Settings", onClick = function()
            if addon.UI and addon.UI.OpenToPage then
                addon.UI:OpenToPage(Notifications.NAV_KEY)
            end
        end },
    } })
end
