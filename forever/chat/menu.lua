--------------------------------------------------------------------------------
-- forever/chat/menu.lua
-- The tab's right-click menu: rename, window color, copy, and the font size
-- per window; and the copy box a link click opens. Every write is the chat
-- cache's own C function, the write Blizzard's menu makes under its Lua:
-- SetChatWindowName, SetChatWindowSize, SetChatWindowColor and
-- SetChatWindowAlpha. The twin re-reads the cache at once; Blizzard's parked
-- window stays as it was until the next login, where FloatingChatFrame_Update
-- reads the cache for it anyway. Close and new window are not here: window
-- allocation and dock order are Lua fields on Blizzard's frames, and the send
-- path reads the dock's selected window, so neither has a clean route.
--------------------------------------------------------------------------------

local addonName, addon = ...

local CR = addon.ChatReplica
local Style = CR.Style

local Menu = {}
CR.Menu = Menu

local list          -- the popup list, built on the first open
local current       -- the entry the open menu is for

local SIZE_PREFIX = "size:"
local ACTIONS = { "rename", "color", "copy" }
local ACTIONS_TEMPORARY = { "color", "copy" }

-- Blizzard's rename popup takes this many letters.
local NAME_LETTERS = 31

local function isSecret(v)
    return issecretvalue and issecretvalue(v) or false
end

local function label(global, fallback)
    local s = _G[global]
    if type(s) == "string" and s ~= "" then return s end
    return fallback
end

--- Blizzard's list of sizes, the tab menu's own (FloatingChatFrame.lua:33-41).
local function fontHeights()
    local heights = _G.CHAT_FONT_HEIGHTS
    if type(heights) ~= "table" or #heights == 0 then
        heights = { 12, 14, 16, 18, 20, 24, 27 }
    end
    return heights
end

--- A whisper window Blizzard opened on its own carries the player's name,
--- which Blizzard's menu does not offer to rename. A plain read of a field.
local function isTemporary(entry)
    local ok, temporary = pcall(function() return entry.source.isTemporary end)
    return ok and temporary == true
end

local function sizeKey(height)
    return SIZE_PREFIX .. tostring(height)
end

--------------------------------------------------------------------------------
-- The list
--------------------------------------------------------------------------------

local function allKeys()
    local keys = {}
    for _, key in ipairs(ACTIONS) do keys[#keys + 1] = key end
    for _, height in ipairs(fontHeights()) do keys[#keys + 1] = sizeKey(height) end
    return keys
end

local function values()
    local map = {
        rename = label("RENAME_CHAT_WINDOW", "Rename Window"),
        color = "Window Color",
        copy = "Copy Window",
    }
    local template = label("FONT_SIZE_TEMPLATE", "%d Point")
    for _, height in ipairs(fontHeights()) do
        local ok, text = pcall(string.format, template, height)
        map[sizeKey(height)] = ok and text or tostring(height)
    end
    return map
end

local function sections()
    local actions = ACTIONS
    if current and isTemporary(current) then actions = ACTIONS_TEMPORARY end
    local sizes = {}
    for _, height in ipairs(fontHeights()) do sizes[#sizes + 1] = sizeKey(height) end
    return {
        { keys = actions },
        { label = label("FONT_SIZE", "Font Size"), keys = sizes },
    }
end

local function selectedKey()
    if not current then return nil end
    return sizeKey(math.floor(Style.FontSize(current.id) + 0.5))
end

local function build()
    local Controls = addon.UI and addon.UI.Controls
    if not (Controls and Controls.CreatePopupList) then return nil end
    return Controls.CreatePopupList({
        width = 190,
        getKeys = allKeys,
        getValues = values,
        getSections = sections,
        getSelectedKey = selectedKey,
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
    if key == "rename" then
        Menu.Rename(entry)
    elseif key == "color" then
        Menu.PickColor(entry)
    elseif key == "copy" then
        Menu.Copy(entry)
    elseif type(key) == "string" and key:sub(1, #SIZE_PREFIX) == SIZE_PREFIX then
        local height = tonumber(key:sub(#SIZE_PREFIX + 1))
        if height then Menu.SetFontSize(entry, height) end
    end
end

--------------------------------------------------------------------------------
-- Rename
--------------------------------------------------------------------------------

function Menu.Rename(entry)
    local Controls = addon.UI and addon.UI.Controls
    if not (Controls and Controls.ShowDialog) then return end
    local name = Style.Cache(entry.id)
    if type(name) ~= "string" or isSecret(name) then name = "" end
    Controls:ShowDialog(nil, {
        text = label("RENAME_CHAT_WINDOW", "Rename Window"),
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
    local write = _G.SetChatWindowName
    if not write then return end
    pcall(write, entry.id, text)
    if CR.Tabs then CR.Tabs.Refresh() end
end

--------------------------------------------------------------------------------
-- Window color
--------------------------------------------------------------------------------
-- Blizzard's own picker over the cache's color and alpha for the window, the
-- call FCF_Tab_SetupMenu makes. A change to the alpha clears the page's
-- Background Opacity override, so the window's own value shows.

function Menu.SetColor(entry, r, g, b)
    local write = _G.SetChatWindowColor
    if not write then return end
    pcall(write, entry.id, r, g, b)
    if CR.Display then CR.Display.ApplyChrome() end
end

function Menu.SetAlpha(entry, a)
    local write = _G.SetChatWindowAlpha
    if not (write and type(a) == "number") then return end
    pcall(write, entry.id, a)
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
    local write = _G.SetChatWindowSize
    if not (write and type(height) == "number") then return end
    pcall(write, entry.id, height)
    local override = tonumber(Style.Get("fontSize"))
    if override and override > 0 then Style.Set("fontSize", 0) end
    if CR.Display then CR.Display.ApplyText() end
    if CR.EditBox then CR.EditBox.ApplyFont() end
end

--------------------------------------------------------------------------------
-- Copy
--------------------------------------------------------------------------------
-- The twin's lines as plain text in the copy window every dump uses: colors,
-- links, textures and atlases stripped. A secret line is left out, since its
-- text cannot be read.

local function plainText(text)
    text = text:gsub("|c%x%x%x%x%x%x%x%x", "")
    text = text:gsub("|r", "")
    text = text:gsub("|H.-|h(.-)|h", "%1")
    text = text:gsub("|T.-|t", "")
    text = text:gsub("|A.-|a", "")
    text = text:gsub("|K.-|k", "")
    return text
end

function Menu.Copy(entry)
    local twin = entry.twin
    if not twin then return end
    local lines, push = addon.DebugLines()
    local skipped = 0
    pcall(function()
        for i = 1, twin:GetNumMessages() do
            local text = twin:GetMessageInfo(i)
            if type(text) == "string" and not isSecret(text) then
                push((plainText(text)))
            else
                skipped = skipped + 1
            end
        end
    end)
    if skipped > 0 then
        push("(%d lines the game keeps secret are not shown)", skipped)
    end
    local name = Style.Cache(entry.id)
    if type(name) ~= "string" or isSecret(name) then name = "Window " .. tostring(entry.id) end
    addon.DebugShowWindow("Chat: " .. name, lines)
end

--- A box with one text selected for Ctrl+C: the link click's copy of an
--- address (lines.lua, the url link kind).
function Menu.CopyText(title, text)
    local Controls = addon.UI and addon.UI.Controls
    if not (Controls and Controls.ShowDialog) or type(text) ~= "string" then return end
    Controls:ShowDialog(nil, {
        text = title or "Copy",
        hasEditBox = true, editBoxText = text, maxLetters = math.max(#text, 256),
        infoOnly = true, acceptText = label("CLOSE", "Close"),
    })
end

--- A line for /camelot chat.
function Menu.Describe(push)
    push("  tab menu: %s, for %s", list and "built" or "unbuilt", current and tostring(current.name) or "none")
end
