--------------------------------------------------------------------------------
-- forever/statusbars/style.lua
-- The status bars replica's module: its switch, its settings and their
-- defaults, and what applies them to the two Camelot bars. The frames are
-- frames.xml and display.lua; the page is page.lua.
--
-- First of the feature's files, and on both clients: retail loads Camelot.toc
-- for the settings panel and excludes the HUD, and the page draws its
-- controls there. Nothing here reads a frame at file scope.
--------------------------------------------------------------------------------

local addonName, addon = ...

local DB = addon.DB

addon.StatusBars = addon.StatusBars or {}
local SB = addon.StatusBars

-- The owner string every claim, event and Edit Mode registration carries; the
-- page's nav key, the Interface group's Status Bars row (forever/menu.lua);
-- the Dynamic Layouts group both adapters join; each bar's layout store key
-- and adapter id, by index.
SB.OWNER = "camelotStatusBars"
SB.NAV_KEY = "statusBars"
SB.GROUP = "statusBars"
SB.KEYS = { "statusBar1", "statusBar2" }
SB.HOLDER_NAMES = { "CamelotStatusBar1", "CamelotStatusBar2" }

local Style = {}
SB.Style = Style

--------------------------------------------------------------------------------
-- Module and switch
--------------------------------------------------------------------------------

DB.RegisterModule("statusBars", true)

addon.Features.Register({
    group = "interface", groupLabel = "Interface",
    id = "statusBars", label = "Status Bars",
    path = "statusBars.enabled",
})

-- Held for the session: the Features page changes it at the reload, and a
-- feature off at login never touches Blizzard's frames.
function SB.IsEnabled()
    return DB.IsModuleEnabled("statusBars")
        and DB.SessionGet("statusBars.enabled") == true
end

--------------------------------------------------------------------------------
-- Ranges, paths and defaults
--------------------------------------------------------------------------------

-- Width is a percent of the client's container width, as Blizzard's Edit Mode
-- Size setting is on Forever (EditModeStatusTrackingBarSystemMixin:
-- UpdateSystemSetting sets the width, not the scale). Blizzard's floor is 50;
-- the replica's is 25.
Style.WIDTH = { min = 25, max = 130, step = 5, default = 100 }
Style.OPACITY = { min = 0, max = 100, step = 1, default = 100 }

-- Forever's preset anchors for the two systems (Blizzard_EditMode/Camelot/
-- EditModePresetLayoutConstants.lua, STATUS_BAR_1 and STATUS_BAR_2), which
-- Blizzard's bottom stack overrides at run time. Kept by reference: Reset To
-- Default Position returns a bar here.
Style.DEFAULT_POSITIONS = {
    { point = "BOTTOM", x = 0, y = 0 },
    { point = "BOTTOM", x = 0, y = 17 },
}

--- The dotted path of a bar's setting: Style.Path(1, "width").
function Style.Path(index, key)
    return "statusBars.bar" .. index .. "." .. key
end

function Style.Get(index, key)
    return DB.Get(Style.Path(index, key))
end

function Style.Set(index, key, value)
    DB.Set(Style.Path(index, key), value)
end

do
    local map = {}
    map["statusBars.enabled"] = true
    for index = 1, 2 do
        map[Style.Path(index, "width")] = Style.WIDTH.default
        map[Style.Path(index, "opacity")] = Style.OPACITY.default
        map[Style.Path(index, "alwaysShowText")] = false
        map[Style.Path(index, "showLevel")] = true
    end
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

--- 25 to 130, in steps of 5.
function Style.Width(index)
    local v = clamp(Style.Get(index, "width"), Style.WIDTH)
    return math.floor(v / Style.WIDTH.step + 0.5) * Style.WIDTH.step
end

function Style.Opacity(index)
    return clamp(Style.Get(index, "opacity"), Style.OPACITY)
end

function Style.AlwaysShowText(index)
    return Style.Get(index, "alwaysShowText") == true
end

--- The player's level in front of the experience text, while the bar shows
--- experience. On by default.
function Style.ShowLevel(index)
    return Style.Get(index, "showLevel") ~= false
end

--- A bar's holder, or nil: on retail none is built.
function Style.Holder(index)
    return _G[SB.HOLDER_NAMES[index]]
end

--------------------------------------------------------------------------------
-- Apply
--------------------------------------------------------------------------------

--- Every setting on both bars, then the dynamic state back on top. The page's
--- apply, the Edit Mode dialog's and the profile engine's.
function Style.Apply()
    local Display = SB.Display
    if not (Display and Display.IsBuilt()) then return end
    for index = 1, 2 do
        Display.ApplyWidth(index)
        Display.ApplyOpacity(index)
        Display.ApplyText(index)
    end
    if SB.Dynamic then SB.Dynamic.Reassert() end
end

-- After a profile switch the bars re-read the new profile. A resync pass
-- keeps the profile it had; re-landing the base there would cut short the
-- Dynamic Layouts tween that leaving Edit Mode starts.
addon.Profiles.RegisterApplyStep(SB.OWNER, function(_, ctx)
    if ctx.initial or ctx.resync then return end
    Style.Apply()
end, 30)

--------------------------------------------------------------------------------
-- Edit Mode dialog
--------------------------------------------------------------------------------
-- Blizzard's one Edit Mode setting for the system, Size, carried as Width,
-- with the replica's own three beside it. Labels only.

--- The mirror for one bar's branded Edit Mode dialog. The engine puts the
--- position row in front of the list.
function Style.EditModeMirror(index)
    return function()
        return {
            {
                kind = "slider", label = "Width",
                min = Style.WIDTH.min, max = Style.WIDTH.max, step = Style.WIDTH.step, precision = 0,
                get = function() return Style.Width(index) end,
                set = function(v)
                    Style.Set(index, "width", clamp(v, Style.WIDTH))
                    Style.Apply()
                end,
            },
            {
                kind = "slider", label = "Opacity",
                min = Style.OPACITY.min, max = Style.OPACITY.max, step = Style.OPACITY.step, precision = 0,
                get = function() return Style.Opacity(index) end,
                set = function(v)
                    Style.Set(index, "opacity", clamp(v, Style.OPACITY))
                    Style.Apply()
                end,
            },
            {
                kind = "toggle", label = "Always Show Text",
                get = function() return Style.AlwaysShowText(index) end,
                set = function(v)
                    Style.Set(index, "alwaysShowText", v and true or false)
                    Style.Apply()
                end,
            },
            {
                kind = "toggle", label = "Show Level",
                get = function() return Style.ShowLevel(index) end,
                set = function(v)
                    Style.Set(index, "showLevel", v and true or false)
                    Style.Apply()
                end,
            },
        }
    end
end
