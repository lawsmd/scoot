--------------------------------------------------------------------------------
-- forever/chat/menu.lua
-- The tab's right-click menu in the shape of Blizzard's (FCF_Tab_SetupMenu,
-- Blizzard_ChatFrameBase/Mainline/FloatingChatFrame.lua): Edit Mode on the
-- first window, Make Noninteractive, Rename Window, Create New Window on the
-- first window, Close Window on a window the player opened, then the Display
-- title over the Font Size submenu and the Background swatch, and the
-- Filters title over Settings. The framework's popup list draws it in the
-- contextMenu chrome role, Blizzard's own menu box on the forever skin.
--
-- Every write is the chat cache's own C function, the write Blizzard's menu
-- makes under its Lua-field writes: SetChatWindowName, SetChatWindowSize,
-- SetChatWindowColor, SetChatWindowAlpha, SetChatWindowUninteractable,
-- SetChatWindowShown, SetChatWindowDocked and the message group writes. The
-- twin re-reads the cache at once; Blizzard's parked window reads it at the
-- next login. A new window and a closed one are cache writes too, and the
-- frame itself is Blizzard's login pass's to build or close from the cache,
-- so both offer the reload that finishes them: window allocation, dock
-- order and the message groups a frame listens for are Lua on Blizzard's
-- frames, read by its secure formatter and send path. Edit Mode opens
-- through a secure click (/editmode), as the panel's button does. Undock
-- and Lock stay off: an undocked window as its own holder is a later phase.
-- Settings opens the panel on the Settings page for the window (config.lua).
--------------------------------------------------------------------------------

local addonName, addon = ...

local CR = addon.ChatReplica
local Style = CR.Style

local Menu = {}
CR.Menu = Menu

local list          -- the popup list, built on the first open
local current       -- the entry the open menu is for

local SIZE_PREFIX = "size:"

-- Blizzard's name popup takes this many letters.
local NAME_LETTERS = 31

-- The groups FCF_OpenNewWindow gives a new window.
local DEFAULT_GROUPS = { "SAY", "YELL", "GUILD", "WHISPER", "BN_WHISPER", "PARTY", "PARTY_LEADER", "CHANNEL" }

-- The rows that are not a plain button.
local KINDS = { display = "title", filters = "title", fontsize = "submenu", background = "swatch" }

local function isSecret(v)
    return issecretvalue and issecretvalue(v) or false
end

local function label(global, fallback)
    local s = _G[global]
    if type(s) == "string" and s ~= "" then return s end
    return fallback
end

local function controls()
    return addon.UI and addon.UI.Controls
end

--- A cache write by name, when the client has it.
local function write(name, ...)
    local fn = _G[name]
    if type(fn) ~= "function" then return false end
    return pcall(fn, ...)
end

--- Blizzard's list of sizes, the tab menu's own (FloatingChatFrame.lua:33-41).
local function fontHeights()
    local heights = _G.CHAT_FONT_HEIGHTS
    if type(heights) ~= "table" or #heights == 0 then
        heights = { 12, 14, 16, 18, 20, 24, 27 }
    end
    return heights
end

--- A plain read of a field on the window's frame, nil when it is secret.
local function plainField(entry, field)
    local ok, v = pcall(function() return entry.source[field] end)
    if ok and not isSecret(v) then return v end
    return nil
end

--- A whisper window Blizzard opened on its own carries the player's name,
--- which Blizzard's menu does not offer to rename.
local function isTemporary(entry)
    return plainField(entry, "isTemporary") == true
end

--- A window with a slot in the chat cache; a pop-out is numbered past them.
local function inCache(entry)
    return type(entry.id) == "number" and entry.id <= Style.MaxWindows()
end

--- IsBuiltinChatWindow: the first window, the combat log and the voice
--- window, which Blizzard's menu never closes.
local function isBuiltin(entry)
    return type(entry.id) == "number" and entry.id <= 3
end

local function sizeKey(height)
    return SIZE_PREFIX .. tostring(height)
end

--- FCF_GetNextOpenChatWindowIndex: the first window past the reserved ones
--- that is neither shown in the cache nor docked on its frame.
function Menu.NextOpenIndex()
    for i = Style.ReservedWindows() + 1, Style.MaxWindows() do
        local _, _, _, _, _, _, shown = Style.Cache(i)
        local frame = _G["ChatFrame" .. i]
        local ok, docked = pcall(function() return frame and frame.isDocked end)
        if shown ~= true and not (ok and docked) then return i end
    end
    return nil
end

local function canOpenNewWindow()
    return Menu.NextOpenIndex() ~= nil
end

--------------------------------------------------------------------------------
-- The list
--------------------------------------------------------------------------------

--- Blizzard's rows for the window, in its order.
local function keys()
    local entry = current
    local out = {}
    if not entry then return out end
    local temporary = isTemporary(entry)
    if entry.id == 1 then out[#out + 1] = "editmode" end
    out[#out + 1] = "interact"
    if not temporary then out[#out + 1] = "rename" end
    if entry.id == 1 then out[#out + 1] = "new" end
    if not isBuiltin(entry) then out[#out + 1] = "close" end
    out[#out + 1] = "display"
    out[#out + 1] = "fontsize"
    out[#out + 1] = "background"
    if not temporary then
        out[#out + 1] = "filters"
        out[#out + 1] = "settings"
    end
    return out
end

local function values()
    local entry = current
    local closeText = label("CLOSE_CHAT_WINDOW", "Close Window")
    if entry and isTemporary(entry) then
        local kind = plainField(entry, "chatType")
        if kind == "WHISPER" or kind == "BN_WHISPER" then
            closeText = label("CLOSE_CHAT_WHISPER_WINDOW", "Close Whisper Window")
        end
    end
    local interact
    if entry and Style.Uninteractable(entry) then
        interact = label("MAKE_INTERACTABLE", "Make Interactive")
    else
        interact = label("MAKE_UNINTERACTABLE", "Make Noninteractive")
    end
    return {
        editmode = label("HUD_EDIT_MODE_MENU", "Edit Mode"),
        interact = interact,
        rename = label("RENAME_CHAT_WINDOW", "Rename Window"),
        new = label("NEW_CHAT_WINDOW", "Create New Window"),
        close = closeText,
        display = label("DISPLAY", "Display"),
        fontsize = label("FONT_SIZE", "Font Size"),
        background = label("BACKGROUND", "Background"),
        filters = label("FILTERS", "Filters"),
        settings = label("CHAT_CONFIGURATION", "Settings"),
    }
end

--- Settings needs the model; Create New Window needs a free slot; Edit Mode
--- asks Blizzard's manager, as its own menu button does.
local function isInert(key)
    if key == "settings" then return not (CR.Config and CR.Config.Open) end
    if key == "new" then return not canOpenNewWindow() end
    if key == "editmode" then
        local mgr = _G.EditModeManagerFrame
        local ok, can = pcall(function() return mgr and mgr.CanEnterEditMode and mgr:CanEnterEditMode() end)
        return not (ok and can == true)
    end
    return false
end

--- The Font Size submenu: Blizzard's sizes as radio rows, the window's own
--- size marked. isChecked reads at every open, so the mark follows a pick.
local function sizeSubmenu()
    local sizes, map = {}, {}
    local template = label("FONT_SIZE_TEMPLATE", "%d pt")
    for _, height in ipairs(fontHeights()) do
        local key = sizeKey(height)
        sizes[#sizes + 1] = key
        local ok, text = pcall(string.format, template, height)
        map[key] = ok and text or tostring(height)
    end
    return {
        getKeys = function() return sizes end,
        getValues = function() return map end,
        getKind = function() return "radio" end,
        isChecked = function(key)
            return current ~= nil and key == sizeKey(math.floor(Style.FontSize(current.id) + 0.5))
        end,
        onSelect = function(key) Menu.Select(key) end,
    }
end

local function build()
    local Controls = controls()
    if not (Controls and Controls.CreatePopupList) then return nil end
    local Panel = addon.UI.SettingsPanel
    local editMode = Panel and Panel.EditModeSecureAction and Panel.EditModeSecureAction()
        or { type = "macro", macrotext = "/editmode" }
    return Controls.CreatePopupList({
        role = "contextMenu",
        getKeys = keys,
        getValues = values,
        getKind = function(key) return KINDS[key] end,
        isInert = isInert,
        getSubmenu = function(key)
            if key == "fontsize" then return sizeSubmenu() end
            return nil
        end,
        getSwatch = function(key)
            if key == "background" and current then return Style.BackgroundColor(current.id) end
            return 0, 0, 0
        end,
        secureActions = { editmode = editMode },
        openSound = SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or nil,
        onSelect = function(key) Menu.Select(key) end,
    })
end

--- The strip's right-click. No menu in combat: no editing surface opens there.
function Menu.Open(entry)
    if not entry or InCombatLockdown() then return end
    current = entry
    if not list then list = build() end
    if list then list:OpenAtCursor() end
end

function Menu.Select(key)
    local entry = current
    if not entry then return end
    if key == "editmode" then
        -- The secure click has run; the panel's own hook on its button
        if addon.EditMode and addon.EditMode.MarkOpeningEditMode then addon.EditMode.MarkOpeningEditMode() end
    elseif key == "interact" then
        Menu.ToggleInteractable(entry)
    elseif key == "rename" then
        Menu.Rename(entry)
    elseif key == "new" then
        Menu.NewWindow()
    elseif key == "close" then
        Menu.Close(entry)
    elseif key == "background" then
        Menu.PickColor(entry)
    elseif key == "settings" then
        if CR.Config then CR.Config.Open(entry) end
    elseif type(key) == "string" and key:sub(1, #SIZE_PREFIX) == SIZE_PREFIX then
        local height = tonumber(key:sub(#SIZE_PREFIX + 1))
        if height then Menu.SetFontSize(entry, height) end
    end
end

--------------------------------------------------------------------------------
-- Make Noninteractive
--------------------------------------------------------------------------------
-- FCF_SetExpandedUninteractable: a docked window's flag goes on every docked
-- window, and the strip is the one dock here. The cache takes the flag for a
-- cached window; a pop-out keeps it on its entry. The twins follow.

function Menu.ToggleInteractable(entry)
    local off = not Style.Uninteractable(entry)
    local targets = CR.Tabs and CR.Tabs.Ordered() or { entry }
    for _, e in ipairs(targets) do
        if inCache(e) then
            write("SetChatWindowUninteractable", e.id, off)
        else
            e.uninteractable = off
        end
    end
    if CR.Display then CR.Display.ApplyInteractable() end
end

--------------------------------------------------------------------------------
-- Rename
--------------------------------------------------------------------------------

function Menu.Rename(entry)
    local Controls = controls()
    if not (Controls and Controls.ShowDialog) then return end
    local name = Style.Cache(entry.id)
    if type(name) ~= "string" or isSecret(name) then name = "" end
    Controls:ShowDialog(nil, {
        text = label("NAME_CHAT_WINDOW", "Enter a name for the chat window:"),
        hasEditBox = true, editBoxText = name, maxLetters = NAME_LETTERS,
        acceptText = label("ACCEPT", "Accept"), cancelText = label("CANCEL", "Cancel"),
        onAccept = function(_, text) Menu.SetName(entry, text) end,
    })
end

--- The cache's name for the window; the tab re-reads it. An empty name keeps
--- the old one, where Blizzard would assign "Window N".
function Menu.SetName(entry, text)
    if type(text) ~= "string" then return end
    text = text:match("^%s*(.-)%s*$") or ""
    if text == "" then return end
    write("SetChatWindowName", entry.id, text)
    if CR.Tabs then CR.Tabs.Refresh() end
end

--------------------------------------------------------------------------------
-- Create New Window and Close Window
--------------------------------------------------------------------------------
-- FCF_OpenNewWindow and FCF_CopyChatSettings as cache writes: the window
-- named, with the first window's color, alpha, size and interactivity,
-- shown, docked last, listening to the default groups, and the message
-- groups and channels a closed window left in its slot cleared first.
-- FCF_PopInWindow likewise: the window's groups and channels back to the
-- first window, then the window closed in the cache. Blizzard's login pass
-- builds or closes the frame from the cache, so each offers the reload.

local function dialogText(global, fallback)
    return label(global, fallback)
end

function Menu.NewWindow()
    local Controls = controls()
    if not (Controls and Controls.ShowDialog and canOpenNewWindow()) then return end
    Controls:ShowDialog(nil, {
        text = dialogText("NAME_CHAT_WINDOW", "Enter a name for the chat window:"),
        hasEditBox = true, editBoxText = "", maxLetters = NAME_LETTERS,
        acceptText = label("ACCEPT", "Accept"), cancelText = label("CANCEL", "Cancel"),
        onAccept = function(_, text) Menu.OpenNewWindow(text) end,
    })
end

--- The cache's docked indexes written again in order, FCF_SaveDock, so a
--- closed window leaves no gap for the login pass to dock into.
function Menu.SaveDock()
    local docked = {}
    for i = 1, Style.MaxWindows() do
        local _, _, _, _, _, _, shown, _, index = Style.Cache(i)
        if shown == true and type(index) == "number" and index > 0 then
            docked[#docked + 1] = { id = i, index = index }
        end
    end
    table.sort(docked, function(a, b) return a.index < b.index end)
    for position, item in ipairs(docked) do
        write("SetChatWindowDocked", item.id, position)
    end
    return #docked
end

local function groupsOf(id)
    local ok, groups = pcall(function() return { _G.GetChatWindowMessages(id) } end)
    return ok and groups or {}
end

local function channelsOf(id)
    local ok, pairsList = pcall(function() return { _G.GetChatWindowChannels(id) } end)
    local names = {}
    if ok then
        -- name, zone id, name, zone id...
        for i = 1, #pairsList, 2 do
            if type(pairsList[i]) == "string" then names[#names + 1] = pairsList[i] end
        end
    end
    return names
end

function Menu.OpenNewWindow(name)
    local id = Menu.NextOpenIndex()
    if not id then return end
    name = type(name) == "string" and (name:match("^%s*(.-)%s*$") or "") or ""
    if name == "" then
        local ok, text = pcall(string.format, label("CHAT_NAME_TEMPLATE", "Window %d"), id)
        name = ok and text or ("Window " .. tostring(id))
    end
    local _, size, r, g, b, a, _, _, _, uninteractable = Style.Cache(1)
    write("SetChatWindowName", id, name)
    write("SetChatWindowColor", id, r or 0, g or 0, b or 0)
    write("SetChatWindowAlpha", id, a or tonumber(_G.DEFAULT_CHATFRAME_ALPHA) or 0.25)
    write("SetChatWindowSize", id, size or 0)
    write("SetChatWindowLocked", id, false)
    write("SetChatWindowUninteractable", id, uninteractable == true)
    for _, group in ipairs(groupsOf(id)) do write("RemoveChatWindowMessages", id, group) end
    for _, channel in ipairs(channelsOf(id)) do write("RemoveChatWindowChannel", id, channel) end
    for _, group in ipairs(DEFAULT_GROUPS) do write("AddChatWindowMessages", id, group) end
    write("SetChatWindowShown", id, true)
    write("SetChatWindowDocked", id, Menu.SaveDock() + 1)
    Menu.OfferReload("The new window opens when the interface reloads.")
end

function Menu.Close(entry)
    if not entry or isBuiltin(entry) then return end
    if inCache(entry) then
        for _, group in ipairs(groupsOf(entry.id)) do write("AddChatWindowMessages", 1, group) end
        for _, channel in ipairs(channelsOf(entry.id)) do write("AddChatWindowChannel", 1, channel) end
        write("SetChatWindowShown", entry.id, false)
        write("SetChatWindowDocked", entry.id, nil)
        Menu.SaveDock()
        if CR.Display then CR.Display.CloseWindow(entry, false) end
        Menu.OfferReload("The window closes, and its chat moves to the first window, when the interface reloads.")
    else
        -- A pop-out has no slot; its lines go to the first window from here
        if CR.Display then CR.Display.CloseWindow(entry, true) end
    end
end

function Menu.OfferReload(text)
    local Controls = controls()
    if not (Controls and Controls.ShowDialog) then return end
    Controls:ShowDialog(nil, {
        text = text,
        acceptText = "Reload", cancelText = "Later",
        onAccept = function()
            local api = _G.C_UI
            local reload = (api and api.Reload) or _G.ReloadUI
            if reload then pcall(reload) end
        end,
    })
end

--------------------------------------------------------------------------------
-- Background
--------------------------------------------------------------------------------
-- Blizzard's own picker over the cache's color and alpha for the window, the
-- call FCF_Tab_SetupMenu makes from its swatch row. A change to the alpha
-- clears the page's Background Opacity override, so the window's own value
-- shows.

function Menu.SetColor(entry, r, g, b)
    write("SetChatWindowColor", entry.id, r, g, b)
    if CR.Display then CR.Display.ApplyChrome() end
end

function Menu.SetAlpha(entry, a)
    if type(a) ~= "number" then return end
    write("SetChatWindowAlpha", entry.id, a)
    local override = tonumber(Style.Get("backgroundOpacity"))
    if override and override >= 0 then Style.Set("backgroundOpacity", -1) end
    if CR.Display then CR.Display.ApplyChrome() end
end

function Menu.PickColor(entry)
    local picker = _G.ColorPickerFrame
    if not (picker and picker.SetupColorPickerAndShow) then return end
    local r, g, b = Style.BackgroundColor(entry.id)
    local a = Style.BackgroundOpacity(entry.id)
    local previous = { r = r, g = g, b = b, a = a }
    picker:SetupColorPickerAndShow({
        r = r, g = g, b = b,
        hasOpacity = true, opacity = a,
        swatchFunc = function()
            local nr, ng, nb = picker:GetColorRGB()
            Menu.SetColor(entry, nr, ng, nb)
        end,
        opacityFunc = function()
            Menu.SetAlpha(entry, picker:GetColorAlpha())
        end,
        cancelFunc = function()
            Menu.SetColor(entry, previous.r, previous.g, previous.b)
            Menu.SetAlpha(entry, previous.a)
        end,
    })
end

--------------------------------------------------------------------------------
-- Font size
--------------------------------------------------------------------------------
-- The cache's size for the window, the write FCF_SetChatWindowFontSize makes
-- beside its SetFont on the Blizzard frame; the twin takes it from the cache.
-- The page's Size row is an override for every window, so a pick here clears
-- it and the per-window sizes show.

function Menu.SetFontSize(entry, height)
    if type(height) ~= "number" then return end
    write("SetChatWindowSize", entry.id, height)
    local override = tonumber(Style.Get("fontSize"))
    if override and override > 0 then Style.Set("fontSize", 0) end
    if CR.Display then CR.Display.ApplyText() end
    if CR.EditBox then CR.EditBox.ApplyFont() end
end

--------------------------------------------------------------------------------
-- The copy box
--------------------------------------------------------------------------------

--- A box with one text selected for Ctrl+C: the link click's copy of an
--- address (lines.lua, the url link kind).
function Menu.CopyText(title, text)
    local Controls = controls()
    if not (Controls and Controls.ShowDialog) or type(text) ~= "string" then return end
    Controls:ShowDialog(nil, {
        text = title or "Copy",
        hasEditBox = true, editBoxText = text, maxLetters = math.max(#text, 256),
        infoOnly = true, acceptText = label("CLOSE", "Close"),
    })
end

--- A line for /camelot chat.
function Menu.Describe(push)
    push("  tab menu: %s, for %s; next free window %s", list and "built" or "unbuilt",
        current and tostring(current.name) or "none", tostring(Menu.NextOpenIndex()))
end
