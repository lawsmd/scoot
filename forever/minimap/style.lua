--------------------------------------------------------------------------------
-- forever/minimap/style.lua
-- The minimap replica's module: its switch, its settings and their defaults,
-- and what applies them to CamelotMinimap. The frame, the lease of Blizzard's
-- Minimap widget and the park of MinimapCluster are display.lua; the text is
-- text.lua; the page is page.lua.
--
-- First of the feature's files, and on both clients: retail loads Camelot.toc
-- for the settings panel and excludes the HUD, and the page draws its
-- controls there. Nothing here reads the frame at file scope; every apply
-- runs against it when it exists and returns when it does not.
--
-- The keys are the X minimap component's (core/components/minimap/core.lua),
-- under `minimap.` instead of `minimapStyle.`, so a later Scoot adoption
-- reads Scoot's profile through a store seam with no rename. Map Size is the
-- one key the X component does not store: there it is Blizzard's Edit Mode
-- setting on the cluster; here it is the holder's scale.
--------------------------------------------------------------------------------

local addonName, addon = ...

local DB = addon.DB

addon.MinimapReplica = addon.MinimapReplica or {}
local MR = addon.MinimapReplica

-- The owner string every claim, event and Edit Mode registration carries; the
-- key of the layout store and the Dynamic Layouts adapter; the page's nav key,
-- the Interface group's Minimap row (forever/menu.lua); the global frames.xml
-- declares.
MR.OWNER = "camelotMinimap"
MR.KEY = "minimap"
MR.NAV_KEY = "minimap"
MR.FRAME_NAME = "CamelotMinimap"

local Style = {}
MR.Style = Style

--------------------------------------------------------------------------------
-- Module and switch
--------------------------------------------------------------------------------

DB.RegisterModule("minimap", true)

-- The row the components host registered while the X component served
-- Camelot, on the same path, so a stored switch carries over.
addon.Features.Register({
    group = "interface", groupLabel = "Interface",
    id = "minimap", label = "Minimap",
    path = "minimap.enabled",
})

-- Held for the session: the Features page changes it at the reload, and a
-- feature off at login never touches Blizzard's frames.
function MR.IsEnabled()
    return DB.IsModuleEnabled("minimap")
        and DB.SessionGet("minimap.enabled") == true
end

--------------------------------------------------------------------------------
-- Ranges, paths and defaults
--------------------------------------------------------------------------------

-- Blizzard's Edit Mode range for the cluster's Size setting.
Style.MAP_SIZE = { min = 50, max = 200, step = 10, default = 100 }
Style.BORDER_THICKNESS = { min = 1, max = 8, step = 1, default = 2 }
Style.TEXT_SIZE = { min = 8, max = 24 }

-- The Minimap widget's own size on every client (Minimap.xml); the holder is
-- the same rect.
Style.MAP_SIZE_PX = 198

-- The square border: Forever's tipless ring unwrapped into a mitred square
-- and shipped as it came. `band` is the overhang in pixels outside the map
-- that puts the band's inner edge on the map edge.
Style.SQUARE_BORDER = {
    texture = addon.MediaPath .. "forever\\media\\minimap\\square-border.png",
    band = 10,
}

-- The ring art Blizzard draws around the map, by its atlas name: retail's
-- silver ring and Forever's bronze one answer the same name at different
-- sizes, and the cluster sizes its container to it (Blizzard's Camelot
-- skin.lua). The header's offset and the selection box's reach read it.
Style.RING_ATLAS = "UI-HUD-Minimap-Frame"

-- Blizzard's own masks. The round one is the atlas Forever's skin applies on
-- every rotateMinimap change, where the client has it, else retail's file.
Style.SQUARE_MASK = "Interface\\BUTTONS\\WHITE8X8"
Style.ROUND_MASK_ATLAS = "ui-hud-minimap-frame-generic-mask"
Style.ROUND_MASK_FILE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

-- The cluster's geometry in Blizzard's XML: the header plate sits TOP of the
-- cluster at (15, -4) and the map's container TOP at (10, -30), 226 high on
-- retail, so the plate's top is 40 above the map's top and 5 right of its
-- centre. A client whose ring is taller moves the map down by half the
-- difference (display.lua, HeaderOffset).
Style.HEADER_X = 5
Style.HEADER_Y_RETAIL = 40
Style.RING_HEIGHT_RETAIL = 226

-- Where Blizzard's coordinates readout sits, for the default position.
Style.COORDS_DEFAULT = { point = "BOTTOM", x = 0, y = -18 }

-- The zone text's colors by PVP type, the X component's table.
Style.PVP_COLORS = {
    sanctuary = { 0.41, 0.8, 0.94, 1 },
    friendly = { 0.1, 1, 0.1, 1 },
    hostile = { 1, 0.1, 0.1, 1 },
    arena = { 1, 0.1, 0.1, 1 },
    contested = { 1, 0.7, 0, 1 },
    combat = { 1, 0.1, 0.1, 1 },
    normal = { 1, 0.82, 0, 1 },
}

--- The dotted path of a setting: Style.Path("mapShape").
function Style.Path(key)
    return "minimap." .. key
end

function Style.Get(key)
    return DB.Get(Style.Path(key))
end

function Style.Set(key, value)
    DB.Set(Style.Path(key), value)
end

do
    local map = {}
    local function set(key, value) map[Style.Path(key)] = value end
    set("enabled", true)

    -- Map Style
    set("mapShape", "default")            -- "default" (round) | "square"
    set("mapSize", Style.MAP_SIZE.default)
    set("borderEnabled", false)           -- square: the solid custom border instead of the art border
    set("borderHidden", false)            -- square: no border at all
    set("borderTintEnabled", false)
    set("borderColor", { 0, 0, 0, 1 })
    set("borderThickness", Style.BORDER_THICKNESS.default)

    -- Dock: the header plate and, with phase 2, its buttons
    set("dockHide", false)

    -- Zone Text
    set("zoneTextHide", false)
    set("zoneTextPosition", "dock")       -- "dock" is the header plate; else one of the nine points
    set("zoneTextColorMode", "pvp")       -- "pvp" | "custom"
    set("zoneTextCustomColor", { 1, 0.82, 0, 1 })
    set("zoneTextFont", "FRIZQT__")
    set("zoneTextFontSize", 12)
    set("zoneTextFontStyle", "OUTLINE")
    set("zoneTextOffsetX", 0)
    set("zoneTextOffsetY", 0)

    -- Coordinates. coordsEnabled and coordsTenths are read only on a client
    -- without the minimapShowPlayerCoords and coordsByTenths CVars.
    set("coordsEnabled", false)
    set("coordsTenths", true)
    set("coordsPosition", "default")      -- "default" is Blizzard's spot below the map
    set("coordsFont", "FRIZQT__")
    set("coordsFontSize", 10)
    set("coordsFontStyle", "SHADOW")
    set("coordsColorMode", "default")
    set("coordsCustomColor", { 1, 1, 1, 1 })
    set("coordsOffsetX", 0)
    set("coordsOffsetY", 0)

    -- Clock
    set("clockHide", false)
    set("clockPosition", "dock")
    set("clockTimeSource", "local")       -- "local" | "server"
    set("clockUse24Hour", false)
    set("clockFont", "FRIZQT__")
    set("clockFontSize", 12)
    set("clockFontStyle", "OUTLINE")
    set("clockColorMode", "default")
    set("clockCustomColor", { 1, 1, 1, 1 })
    set("clockOffsetX", 0)
    set("clockOffsetY", 0)

    -- System Data
    set("systemDataShowFPS", false)
    set("systemDataShowLatency", false)
    set("systemDataLatencySource", "home") -- "home" | "world"
    set("systemDataFont", "FRIZQT__")
    set("systemDataFontSize", 11)
    set("systemDataFontStyle", "OUTLINE")
    set("systemDataColorMode", "default")
    set("systemDataCustomColor", { 1, 1, 1, 1 })
    set("systemDataAnchor", "BOTTOM")
    set("systemDataOffsetX", 0)
    set("systemDataOffsetY", -18)

    DB.RegisterDefaults(map)
end

--------------------------------------------------------------------------------
-- Reads
--------------------------------------------------------------------------------

local function clamp(value, range)
    local v = tonumber(value) or range.default
    if v < range.min then v = range.min elseif v > range.max then v = range.max end
    return v
end
Style.Clamp = clamp

--- 50 to 200, in steps of 10.
function Style.MapSize()
    local v = clamp(Style.Get("mapSize"), Style.MAP_SIZE)
    return math.floor(v / Style.MAP_SIZE.step + 0.5) * Style.MAP_SIZE.step
end

--- The holder's scale, the base the Dynamic Layouts adapter reports.
function Style.Scale()
    return Style.MapSize() / 100
end

function Style.IsSquare()
    return Style.Get("mapShape") == "square"
end

function Style.BorderThickness()
    return clamp(Style.Get("borderThickness"), Style.BORDER_THICKNESS)
end

--- The frame, or nil: on retail none is built.
function Style.Frame()
    return _G[MR.FRAME_NAME]
end

--- A color table's four numbers, with a fallback.
function Style.Color(key, fallback)
    local c = Style.Get(key)
    if type(c) ~= "table" then c = fallback end
    return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
end

--- The ring atlas's size, or retail's numbers where the atlas does not
--- resolve.
function Style.RingSize()
    local info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(Style.RING_ATLAS)
    if info and info.width and info.height then return info.width, info.height end
    return 215, Style.RING_HEIGHT_RETAIL
end

--- The header plate's TOP offset from the map's TOP.
function Style.HeaderOffset()
    local _, h = Style.RingSize()
    return Style.HEADER_X, Style.HEADER_Y_RETAIL + (h - Style.RING_HEIGHT_RETAIL) / 2
end

--- The round mask the client draws: Forever's atlas, else retail's file.
function Style.RoundMask()
    local info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(Style.ROUND_MASK_ATLAS)
    if info then return Style.ROUND_MASK_ATLAS end
    return Style.ROUND_MASK_FILE
end

--------------------------------------------------------------------------------
-- Apply
--------------------------------------------------------------------------------

--- Every setting, in the order the frame takes them: the lease and the park
--- first, then the map's shape and size, the borders, the header, the text,
--- and the dynamic state back on top. The page's apply, the Edit Mode
--- dialog's and the profile engine's.
function Style.Apply()
    if not Style.Frame() then return end
    local Display, Text = MR.Display, MR.Text
    if not (Display and Display.IsBuilt()) then return end
    Display.Lease("apply")
    Display.Claim()
    Display.ApplyShape()
    Display.ApplySize()
    Display.ApplyBorder()
    Display.ApplyHeader()
    if Text then
        Text.ApplyZoneText()
        Text.ApplyCoordinates()
        Text.ApplyClock()
        Text.ApplySystemData()
    end
    if MR.Dynamic then MR.Dynamic.Reassert() end
end

-- After a profile switch the frame re-reads the new profile. A resync pass
-- keeps the profile it had; re-landing the base there would cut short the
-- Dynamic Layouts tween that leaving Edit Mode starts.
addon.Profiles.RegisterApplyStep(MR.OWNER, function(_, ctx)
    if ctx.initial or ctx.resync then return end
    Style.Apply()
end, 30)

--------------------------------------------------------------------------------
-- Edit Mode dialog
--------------------------------------------------------------------------------
-- Blizzard's Edit Mode settings for the cluster that the replica carries:
-- Size as Map Size, and the map's shape beside it. Header Underneath waits for
-- phase 3; Rotate Minimap stays Blizzard's own option, a CVar. Labels only:
-- the dialog has no room for descriptions.

--- The mirror for the branded Edit Mode dialog. Returns a function, the
--- shape the positionable's brand.mirror takes. The engine puts the
--- position row in front of the list.
function Style.EditModeMirror()
    return function()
        return {
            {
                kind = "slider", label = "Map Size",
                min = Style.MAP_SIZE.min, max = Style.MAP_SIZE.max, step = Style.MAP_SIZE.step, precision = 0,
                get = Style.MapSize,
                set = function(v)
                    Style.Set("mapSize", clamp(v, Style.MAP_SIZE))
                    Style.Apply()
                end,
            },
            {
                kind = "selector", label = "Map Shape",
                values = { default = "Default (Circle)", square = "Square" },
                order = { "default", "square" },
                get = function() return Style.IsSquare() and "square" or "default" end,
                set = function(v)
                    Style.Set("mapShape", v == "square" and "square" or "default")
                    Style.Apply()
                end,
            },
            {
                kind = "toggle", label = "Hide Dock",
                get = function() return Style.Get("dockHide") == true end,
                set = function(v)
                    Style.Set("dockHide", v and true or false)
                    Style.Apply()
                end,
            },
        }
    end
end
