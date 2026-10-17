--------------------------------------------------------------------------------
-- forever/chat/style.lua
-- The chat replica's module: its switch, its settings and their defaults, and
-- what applies them to CamelotChat. The frame, the park of Blizzard's windows
-- and the bridge are display.lua; the tab strip tabs.lua; Blizzard's edit box
-- editbox.lua; the tab menu menu.lua; the line transforms lines.lua; the
-- page page.lua.
--
-- First of the feature's files, and on both clients: retail loads Camelot.toc
-- for the settings panel and excludes the HUD, and the page draws its
-- controls there. Nothing here reads the frame at file scope; every apply
-- runs against it when it exists and returns when it does not.
--
-- Two switches are Blizzard's own CVars, the minimap's rule for the
-- coordinates: Class Colors is chatClassColorOverride and Timestamps is
-- showTimestamps, both read by Blizzard's secure formatter, which is the one
-- place a line is formatted (display.lua, the bridge).
--------------------------------------------------------------------------------

local addonName, addon = ...

local DB = addon.DB

addon.ChatReplica = addon.ChatReplica or {}
local CR = addon.ChatReplica

-- The owner string every claim, event and Edit Mode registration carries; the
-- key of the layout store and the Dynamic Layouts adapter; the page's nav key,
-- the Interface group's Chat row (forever/menu.lua); the global frames.xml
-- declares.
CR.OWNER = "camelotChat"
CR.KEY = "chat"
CR.NAV_KEY = "chat"
CR.FRAME_NAME = "CamelotChat"

local Style = {}
CR.Style = Style

--------------------------------------------------------------------------------
-- Module and switch
--------------------------------------------------------------------------------

DB.RegisterModule("chat", true)

addon.Features.Register({
    group = "interface", groupLabel = "Interface",
    id = "chat", label = "Chat",
    path = "chat.enabled",
})

-- Held for the session: the Features page changes it at the reload, and a
-- feature off at login never touches Blizzard's frames.
function CR.IsEnabled()
    return DB.IsModuleEnabled("chat")
        and DB.SessionGet("chat.enabled") == true
end

--------------------------------------------------------------------------------
-- Ranges, paths and defaults
--------------------------------------------------------------------------------

-- Blizzard's resize floor for a chat window is 250 by 120
-- (FloatingChatFrameTemplate's minResize); its ceiling 800 by 800.
Style.WIDTH = { min = 250, max = 1200, step = 10, default = 430 }
Style.HEIGHT = { min = 120, max = 800, step = 10, default = 170 }
Style.SCALE = { min = 50, max = 200, step = 5, default = 100 }
Style.FONT_SIZE = { min = 8, max = 24 }
Style.BACKGROUND_OPACITY = { min = 0, max = 100, step = 5 }
Style.TIME_VISIBLE = { min = 10, max = 600, step = 10, default = 120 }
Style.IDLE_FADE_DELAY = { min = 1, max = 60, step = 1, default = 10 }

-- The stamp's color when Color Timestamps is on: a grey a step under the
-- line's white.
Style.TIMESTAMP_COLOR = { 0.6, 0.6, 0.6, 1 }

-- The strip's tabs are ChatTabArtTemplate's 32 high and stand 3 above the
-- window, as Blizzard's dock stands above ChatFrame1; the edit box is 32 high
-- and hangs 2 below it (FloatingChatFrame.xml:540-545).
Style.TAB_HEIGHT = 32
Style.STRIP_GAP = 3
Style.EDIT_BOX_HEIGHT = 32
Style.EDIT_BOX_GAP = 2

-- The scroll bar's gutter at the window's right: MinimalScrollBar's 8 plus
-- the 7 Blizzard's background reaches past it
-- (FloatingChatFrame_UpdateBackgroundAnchors).
Style.SCROLL_GUTTER = 15

-- Blizzard's XML anchor for ChatFrame1 and the Edit Mode preset's size: the
-- fallback default when the frame's rect cannot be read at the first build.
Style.XML_ANCHOR = { point = "BOTTOMLEFT", x = 32, y = 95 }
Style.XML_SIZE = { width = 430, height = 170 }

Style.CLASS_COLOR_CVAR = "chatClassColorOverride"
Style.TIMESTAMP_CVAR = "showTimestamps"
Style.MOUSE_SCROLL_CVAR = "chatMouseScroll"

--- The dotted path of a setting: Style.Path("width").
function Style.Path(key)
    return "chat." .. key
end

function Style.Get(key)
    return DB.Get(Style.Path(key))
end

function Style.Set(key, value)
    DB.Set(Style.Path(key), value)
end

--- A color setting as r, g, b, a, or the fallback table when none is set.
function Style.Color(key, fallback)
    local c = Style.Get(key)
    if type(c) ~= "table" then c = fallback end
    return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
end

-- Vanilla's chat window where it has a value: Blizzard's font object at the
-- window's own size from the chat cache, 120 seconds visible with the fade,
-- the tabs always shown, the box below. A width, height, size or background
-- opacity below zero means the value Blizzard's ChatFrame1 had at the first
-- build (display.lua, CaptureDefault), so a fresh install lands exactly where
-- the player's layout had the chat. The departures are the owner's
-- quality-of-life layers, each with its Blizzard value in the stock map.
do
    local map = {}
    local function set(key, value) map[Style.Path(key)] = value end
    set("enabled", true)

    -- Window
    set("width", 0)                   -- 0: ChatFrame1's width at the first build
    set("height", 0)                  -- 0: its height
    set("scale", Style.SCALE.default)
    set("backgroundOpacity", -1)      -- -1: the window's own alpha from the chat cache
    set("editBoxPosition", "below")   -- "below" | "above"

    -- Text
    set("fontFace", "FRIZQT__")       -- ChatFontNormal's face
    set("fontSize", 0)                -- 0: the window's own size from the chat cache
    set("fontStyle", "SHADOW")        -- ChatFontNormal's own shadow
    set("fadeLines", true)
    set("timeVisible", Style.TIME_VISIBLE.default)

    -- Tabs
    set("showTabs", "always")         -- "always" | "mouseover"
    set("tabFlash", "all")            -- "never" | "all" | "whispers"

    -- Chrome
    set("idleFade", false)
    set("idleFadeDelay", Style.IDLE_FADE_DELAY.default)

    -- Formatting and alerts: vanilla's chat has none of these
    set("shortLabels", true)
    set("mentionHighlight", true)
    set("mentionSound", false)
    set("colorTimestamps", true)
    set("timestampColor", { 0.6, 0.6, 0.6, 1 })
    set("urlLinks", true)

    -- The EventRegistry callbacks on Blizzard's edit box, off until the beta
    -- has shown their dispatch stays secure (editbox.lua). No page writes it.
    set("editBoxCallbacks", false)

    DB.RegisterDefaults(map)

    -- Blizzard Default: the long channel labels, no highlight, no stamp
    -- color and no links for addresses.
    local stock = {}
    local function blizzard(key, value) stock[Style.Path(key)] = value end
    blizzard("shortLabels", false)
    blizzard("mentionHighlight", false)
    blizzard("colorTimestamps", false)
    blizzard("urlLinks", false)
    DB.RegisterStock(stock)
end

--------------------------------------------------------------------------------
-- Reads
--------------------------------------------------------------------------------

local function clamp(value, range)
    local v = tonumber(value) or range.default or range.min
    if v < range.min then v = range.min elseif v > range.max then v = range.max end
    return v
end
Style.Clamp = clamp

--- The frame, or nil: on retail none is built.
function Style.Frame()
    return _G[CR.FRAME_NAME]
end

--- What the first build read off Blizzard's ChatFrame1, or nil before it.
local function captured()
    return CR.Display and CR.Display.CaptureDefault and CR.Display.CaptureDefault() or nil
end

--- The window's width in its own units: the setting, or ChatFrame1's.
function Style.Width()
    local v = tonumber(Style.Get("width")) or 0
    if v <= 0 then
        local c = captured()
        v = c and c.width or Style.XML_SIZE.width
    end
    return clamp(v, Style.WIDTH)
end

function Style.Height()
    local v = tonumber(Style.Get("height")) or 0
    if v <= 0 then
        local c = captured()
        v = c and c.height or Style.XML_SIZE.height
    end
    return clamp(v, Style.HEIGHT)
end

--- 50 to 200, in steps of 5.
function Style.ScalePercent()
    local v = clamp(Style.Get("scale"), Style.SCALE)
    return math.floor(v / Style.SCALE.step + 0.5) * Style.SCALE.step
end

--- The holder's scale, the base the Dynamic Layouts adapter reports.
function Style.Scale()
    return Style.ScalePercent() / 100
end

--- Window 1's own values from the chat cache: name, font size, color, alpha,
--- shown, locked, docked, uninteractable. Every value is a plain read.
local function cache(id)
    local read = _G.GetChatWindowInfo
    if not read then return nil end
    local ok, name, size, r, g, b, a, shown, locked, docked, uninteractable = pcall(read, id or 1)
    if not ok then return nil end
    return name, size, r, g, b, a, shown, locked, docked, uninteractable
end
Style.Cache = cache

--- A window id for a cache read: the argument when it is a number, else 1.
local function windowId(id)
    if type(id) == "number" then return id end
    return 1
end

--- The background's alpha, 0 to 1: the setting, or the window's own from the
--- chat cache (id, window 1 by default).
function Style.BackgroundOpacity(id)
    local v = tonumber(Style.Get("backgroundOpacity"))
    if v == nil or v < 0 then
        local _, _, _, _, _, a = cache(windowId(id))
        if type(a) == "number" then return a end
        return tonumber(_G.DEFAULT_CHATFRAME_ALPHA) or 0.25
    end
    return clamp(v, Style.BACKGROUND_OPACITY) / 100
end

--- The tint of the background and the borders, r, g, b: the window's color in
--- the chat cache (id, window 1 by default), else the Blizzard default, black.
--- The value FCF_SetWindowColor writes on the Blizzard window.
function Style.BackgroundColor(id)
    local _, _, r, g, b = cache(windowId(id))
    if type(r) == "number" and type(g) == "number" and type(b) == "number" then return r, g, b end
    local c = _G.DEFAULT_CHATFRAME_COLOR
    if type(c) == "table" and type(c.r) == "number" then return c.r, c.g, c.b end
    return 0, 0, 0
end

--- The text size: the setting, or the window's own from the chat cache (id,
--- window 1 by default).
function Style.FontSize(id)
    local v = tonumber(Style.Get("fontSize")) or 0
    if v <= 0 then
        local _, size = cache(windowId(id))
        if type(size) == "number" and size > 0 then
            v = size
        else
            v = tonumber(_G.CHAT_FRAME_DEFAULT_FONT_SIZE) or 14
        end
    end
    return clamp(v, Style.FONT_SIZE)
end

function Style.FontFace()
    return addon.ResolveFontFace(Style.Get("fontFace") or "FRIZQT__")
end

--- The lines are engine-fed FontStrings the message frame pools, so a Deep
--- Shadow value renders as its base style (core/fonts.lua, Unpaired).
function Style.FontStyle()
    return addon.FontStyles.Unpaired(Style.Get("fontStyle") or "SHADOW")
end

function Style.TimeVisible()
    return clamp(Style.Get("timeVisible"), Style.TIME_VISIBLE)
end

function Style.IdleFadeDelay()
    return clamp(Style.Get("idleFadeDelay"), Style.IDLE_FADE_DELAY)
end

function Style.EditBoxAbove()
    return Style.Get("editBoxPosition") == "above"
end

--------------------------------------------------------------------------------
-- The CVar switches
--------------------------------------------------------------------------------
-- chatClassColorOverride: "0" colors every chat type by class, "1" none, any
-- other value leaves each type's own flag (ChatFrameUtil.lua:880-895).
-- showTimestamps: "none" or a strftime format the formatter prepends.

function Style.ClassColors()
    return GetCVar(Style.CLASS_COLOR_CVAR) == "0"
end

-- Kept off core/profiles/cvars.lua: a passthrough to Blizzard's own option,
-- stored nowhere in the profile.
function Style.SetClassColors(on)
    local value
    if on then
        value = "0"
    else
        value = GetCVarDefault and GetCVarDefault(Style.CLASS_COLOR_CVAR) or "2"
        if value == "0" then value = "2" end
    end
    pcall(SetCVar, Style.CLASS_COLOR_CVAR, value)
end

function Style.Timestamps()
    local v = GetCVar(Style.TIMESTAMP_CVAR)
    if type(v) ~= "string" or v == "" then return "none" end
    return v
end

-- Kept off core/profiles/cvars.lua: a passthrough to Blizzard's own option,
-- stored nowhere in the profile.
function Style.SetTimestamps(format)
    pcall(SetCVar, Style.TIMESTAMP_CVAR, format or "none")
end

--- The formats Blizzard's Social options offer, labelled as that page labels
--- them: the format applied to one example time.
function Style.TimestampOptions()
    local values, order = { none = _G.TIMESTAMP_FORMAT_NONE or "None" }, { "none" }
    local example = time({ year = 2026, month = 10, day = 17, hour = 15, min = 27, sec = 32 })
    local timeUtil, betterDate = _G.TimeUtil, _G.BetterDate
    for _, name in ipairs({
        "TIMESTAMP_FORMAT_HHMM", "TIMESTAMP_FORMAT_HHMMSS",
        "TIMESTAMP_FORMAT_HHMM_AMPM", "TIMESTAMP_FORMAT_HHMMSS_AMPM",
        "TIMESTAMP_FORMAT_HHMM_24HR", "TIMESTAMP_FORMAT_HHMMSS_24HR",
    }) do
        local format = _G[name]
        if type(format) == "string" and format ~= "" then
            local ok, label = pcall(function()
                if timeUtil and timeUtil.BetterDate then return timeUtil.BetterDate(format, example) end
                if betterDate then return betterDate(format, example) end
                return date(format, example)
            end)
            values[format] = ok and label or format
            order[#order + 1] = format
        end
    end
    return values, order
end

--------------------------------------------------------------------------------
-- Apply
--------------------------------------------------------------------------------

--- Every setting, in the order the frame takes them: the park first, then the
--- window's size and scale, the chrome, the text, the tabs, the box, and the
--- dynamic state back on top. The page's apply, the Edit Mode dialog's and the
--- profile engine's.
function Style.Apply()
    if not Style.Frame() then return end
    local Display = CR.Display
    if not (Display and Display.IsBuilt()) then return end
    Display.Claim()
    Display.ApplySize()
    Display.ApplyScale()
    Display.ApplyChrome()
    Display.ApplyText()
    if CR.Tabs then CR.Tabs.Apply() end
    if CR.EditBox then CR.EditBox.Apply() end
    if CR.EditMode then CR.EditMode.SyncDefault() end
    if CR.Dynamic then CR.Dynamic.Reassert() end
end

-- After a profile switch the frame re-reads the new profile. A resync pass
-- keeps the profile it had; re-landing the base there would cut short the
-- Dynamic Layouts tween that leaving Edit Mode starts.
addon.Profiles.RegisterApplyStep(CR.OWNER, function(_, ctx)
    if ctx.initial or ctx.resync then return end
    Style.Apply()
end, 30)

--------------------------------------------------------------------------------
-- Edit Mode dialog
--------------------------------------------------------------------------------
-- Blizzard's Edit Mode settings for the chat frame, Width and Height, plus
-- the font size Blizzard keeps in the tab menu. Labels only.

function Style.EditModeMirror()
    return function()
        return {
            {
                kind = "slider", label = "Width",
                min = Style.WIDTH.min, max = Style.WIDTH.max, step = Style.WIDTH.step, precision = 0,
                get = Style.Width,
                set = function(v)
                    Style.Set("width", clamp(v, Style.WIDTH))
                    Style.Apply()
                end,
            },
            {
                kind = "slider", label = "Height",
                min = Style.HEIGHT.min, max = Style.HEIGHT.max, step = Style.HEIGHT.step, precision = 0,
                get = Style.Height,
                set = function(v)
                    Style.Set("height", clamp(v, Style.HEIGHT))
                    Style.Apply()
                end,
            },
            {
                kind = "slider", label = "Font Size",
                min = Style.FONT_SIZE.min, max = Style.FONT_SIZE.max, step = 1, precision = 0,
                get = Style.FontSize,
                set = function(v)
                    Style.Set("fontSize", clamp(v, Style.FONT_SIZE))
                    Style.Apply()
                end,
            },
        }
    end
end
