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
-- key of the layout store and the Dynamic Layouts adapter; the two pages' nav
-- keys under the Chat group (forever/menu.lua): Customize, this file's
-- settings (page.lua), and Settings, Blizzard's Chat Config window rebuilt
-- (config.lua, configpage.lua); the global frames.xml declares.
CR.OWNER = "camelotChat"
CR.KEY = "chat"
CR.NAV_KEY = "chatCustomize"
CR.CONFIG_NAV_KEY = "chatSettings"
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
--- The key the Font row shows at stock: Arial Narrow, ChatFontNormal's own
--- face (Style.ObjectFace). The setting itself registers no default.
Style.STOCK_FONT_KEY = "ARIALN"
Style.BACKGROUND_OPACITY = { min = 0, max = 100, step = 5 }
-- Blizzard's inactive edit box sits at 0.35 in the im chat style
-- (ChatFrameEditBox.lua:551), the stock value; 0 leaves it invisible.
Style.EDIT_BOX_OPACITY = { min = 0, max = 100, step = 5, default = 35 }
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

-- Camelot's default spot, the owner's (19 October 2026): the window's bottom
-- left 16 in from the screen's left and 36 up, which leaves the edit box
-- below it 2 above the screen's bottom. In the holder's own units, as the
-- store keeps a pair at scale 100.
Style.CAMELOT_ANCHOR = { point = "BOTTOMLEFT", x = 16, y = 36 }

Style.CLASS_COLOR_CVAR = "chatClassColorOverride"
Style.TIMESTAMP_CVAR = "showTimestamps"
Style.MOUSE_SCROLL_CVAR = "chatMouseScroll"
Style.CHAT_STYLE_CVAR = "chatStyle"

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

-- The owner's setup (19 October 2026), with vanilla's chat window where the
-- owner kept it: Blizzard's font object at the window's own size from the
-- chat cache, 120 seconds visible with the fade, the box below. A width,
-- height or size of 0, or a background opacity of -1, means the value
-- Blizzard's ChatFrame1 had at the first build (display.lua, CaptureDefault).
-- Every departure has its Blizzard value in the stock map, which the Modern
-- and Classic starts write.
do
    local map = {}
    local function set(key, value) map[Style.Path(key)] = value end
    set("enabled", true)

    -- Window
    set("width", 500)                 -- vanilla: ChatFrame1's width at the first build
    set("height", 250)                -- vanilla: its height
    set("scale", Style.SCALE.default)
    set("backgroundOpacity", 0)       -- vanilla: the window's own alpha from the chat cache
    -- "camelot" is Style.CAMELOT_ANCHOR, "blizzard" where ChatFrame1 stood
    -- (editmode.lua, SyncDefault). No page writes it.
    set("defaultAnchor", "camelot")

    -- Edit box
    set("editBoxPosition", "below")   -- "below" | "above"
    set("editBoxOpacity", 0)          -- vanilla: Blizzard's 0.35 while nothing is typed

    -- Text
    -- fontFace registers no default: nil is ChatFontNormal's own face, read
    -- off the object (Style.FontFace), which the Font row shows as Arial Narrow.
    set("fontSize", 0)                -- 0: the window's own size from the chat cache
    -- Crisp Shadow Thick Outline; renders as SHADOWTHICKOUTLINE on a client
    -- without the SLUG flag (core/fonts.lua).
    set("fontStyle", "SHADOWTHICKOUTLINESLUG") -- vanilla: ChatFontNormal's own shadow
    set("fadeLines", true)
    set("timeVisible", Style.TIME_VISIBLE.default)

    -- Tabs
    set("showTabs", "mouseover")      -- "always" | "mouseover"; vanilla: always
    set("tabFlash", "all")            -- "never" | "all" | "whispers"

    -- Chrome
    set("idleFade", false)
    set("idleFadeDelay", Style.IDLE_FADE_DELAY.default)

    -- Formatting and alerts: vanilla's chat has none of these
    set("shortLabels", true)
    set("mentionHighlight", true)
    set("mentionSound", true)
    set("colorTimestamps", true)
    set("timestampColor", { 0.6, 0.6, 0.6, 1 })
    set("urlLinks", true)

    -- The EventRegistry callbacks on Blizzard's edit box, off until the beta
    -- has shown their dispatch stays secure (editbox.lua). No page writes it.
    set("editBoxCallbacks", false)

    DB.RegisterDefaults(map)

    -- Blizzard Default: ChatFrame1's own size, spot and alpha, the inactive
    -- box at 0.35, the font's shadow alone, the tabs always shown, the long
    -- channel labels, no highlight or sound, no stamp color and no links for
    -- addresses.
    local stock = {}
    local function blizzard(key, value) stock[Style.Path(key)] = value end
    blizzard("width", 0)
    blizzard("height", 0)
    blizzard("backgroundOpacity", -1)
    blizzard("defaultAnchor", "blizzard")
    blizzard("editBoxOpacity", Style.EDIT_BOX_OPACITY.default)
    blizzard("fontStyle", "SHADOW")
    blizzard("showTabs", "always")
    blizzard("mentionSound", false)
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

--- The client's count of cached chat windows, and of the reserved ones at
--- the front (General and the combat log), Blizzard's own constants; a
--- whisper pop-out is numbered past the count and keeps its state on its
--- frame.
function Style.MaxWindows()
    local c = _G.Constants
    local n = c and c.ChatFrameConstants and c.ChatFrameConstants.MaxChatWindows
    if type(n) == "number" then return n end
    return tonumber(_G.NUM_CHAT_WINDOWS) or 10
end

function Style.ReservedWindows()
    local api = _G.C_ChatInfo
    local ok, n = pcall(function() return api and api.GetNumReservedChatWindows and api.GetNumReservedChatWindows() end)
    if ok and type(n) == "number" then return n end
    return 2
end

--- Whether a window's links take no click (Make Noninteractive): the
--- cache's flag for a cached window; a pop-out's is the flag the menu set
--- on its entry, else the one on its frame, a plain read.
function Style.Uninteractable(entry)
    if type(entry) ~= "table" then return false end
    if type(entry.id) == "number" and entry.id <= Style.MaxWindows() then
        local _, _, _, _, _, _, _, _, _, off = cache(entry.id)
        return off == true
    end
    if entry.uninteractable ~= nil then return entry.uninteractable == true end
    local ok, off = pcall(function() return entry.source and entry.source.isUninteractable end)
    return ok and off == true
end

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

--- ChatFontNormal's own face: NumberFont_Shadow_Med's roman member,
--- Fonts\ARIALN.TTF on an English client, read off the object so a client in
--- another locale draws its own file, the rule for every font object here.
function Style.ObjectFace()
    local ok, face = pcall(function() return (ChatFontNormal:GetFont()) end)
    if ok and type(face) == "string" and face ~= "" then return face end
    return (addon.Fonts and addon.Fonts.ARIALN) or "Fonts\\ARIALN.TTF"
end

--- The face of every line and of the edit box: the Font row's pick, or the
--- object's face at stock. Arial Narrow is the one stock face with Cyrillic
--- glyphs on an English client; the engine draws a line its face cannot shape
--- in the client's fallback font whole, so a log of Latin and Cyrillic names
--- on Friz Quadrata shows two fonts (seen on the beta, 18 October 2026).
function Style.FontFace()
    local key = Style.Get("fontFace")
    if type(key) ~= "string" or key == "" then return Style.ObjectFace() end
    return addon.ResolveFontFace(key)
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

--- The box's alpha while nothing is typed, 0 to 1.
function Style.EditBoxOpacity()
    return clamp(Style.Get("editBoxOpacity"), Style.EDIT_BOX_OPACITY) / 100
end

--- Blizzard's classic chat style hides the inactive box
--- (ChatFrameEditBox.lua:545), so an opacity has nothing to draw on there.
function Style.ChatStyleClassic()
    return GetCVar(Style.CHAT_STYLE_CVAR) == "classic"
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
    Display.ApplyInteractable()
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
