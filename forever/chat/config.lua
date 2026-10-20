--------------------------------------------------------------------------------
-- forever/chat/config.lua
-- The model behind the Settings page (configpage.lua): Blizzard's Chat Config
-- window (Blizzard_ChatFrame/Mainline/ChatConfigFrame.lua) rebuilt on the
-- framework, with reads and writes that never touch a Blizzard chat frame.
--
-- A message group or a channel is per window and lives in the chat cache:
-- GetChatWindowMessages and GetChatWindowChannels read it, the Add and Remove
-- C functions write it. Blizzard's own checkbox makes the same C write beside
-- a write to messageTypeList on the frame and a RegisterEvent
-- (ChatFrameMixin:AddMessageGroup), which this addon never makes. The frame
-- registered its events from the cache at login, so a group it listened to
-- then is filtered at the twin (Shows): unchecking hides its lines at once.
-- A group it did not listen to arrives at the reload, and the page says so
-- (Pending).
--
-- A color is global: ChatTypeInfo holds it and ChangeChatColor writes it,
-- once per member event of the type's group, the swatch's own loop. The C
-- call fires UPDATE_CHAT_COLOR, Blizzard's handler rewrites ChatTypeInfo and
-- recolors every window's lines through AdjustMessageColors, a mutator the
-- bridge mirrors.
--
-- The rows are Blizzard's tables, read when the page draws: a row Blizzard
-- adds or drops arrives with no code change. Loads on retail too, where the
-- page writes Blizzard's live windows.
--------------------------------------------------------------------------------

local addonName, addon = ...

local CR = addon.ChatReplica
local Style = CR.Style

local Config = {}
CR.Config = Config

-- Blizzard's tables in the order the page draws them, each under the header
-- its box carries in Blizzard's window. `flash` marks the rows whose lines
-- flash a tab in the strip's Every Window mode (IsPlayerMessage).
Config.SECTIONS = {
    { key = "player", tab = "chat", table = "CHAT_CONFIG_CHAT_LEFT", header = "PLAYER_MESSAGES", fallback = "Player Messages", flash = true },
    { key = "combat", tab = "other", table = "CHAT_CONFIG_OTHER_COMBAT", header = "COMBAT", fallback = "Combat" },
    { key = "pvp", tab = "other", table = "CHAT_CONFIG_OTHER_PVP", header = "PVP", fallback = "Player vs. Player" },
    { key = "system", tab = "other", table = "CHAT_CONFIG_OTHER_SYSTEM", header = "OTHER", fallback = "Other" },
    { key = "creature", tab = "other", table = "CHAT_CONFIG_CHAT_CREATURE_LEFT", header = "CREATURE_MESSAGES", fallback = "Creature Messages" },
    { key = "colors", tab = "other", table = "CHAT_CONFIG_ADDITIONAL_COLORS", header = "CHAT_SETTINGS_ADDITIONAL_COLORS", fallback = "Additional Colors", swatchOnly = true },
}

-- The PvP rows label and color one key and toggle another
-- (CHAT_CONFIG_OTHER_PVP, ChatConfigFrame.lua:245-261).
local PVP_GROUPS = { BG_SYSTEM_HORDE = "BG_HORDE", BG_SYSTEM_ALLIANCE = "BG_ALLIANCE", BG_SYSTEM_NEUTRAL = "BG_NEUTRAL" }

local CHANNEL_EVENT = "CHAT_MSG_CHANNEL"

local groupSets = {}     -- id -> { [group] = true }
local channelSets = {}   -- id -> { list = { { name, zone } }, byName = {}, byZone = {} }
local flashGroups        -- { [group] = true } for the rows marked flash
local snapshot           -- the cache sets at login: { groups = {}, channels = {} } by id
local selectedWindow = 1 -- the window the page edits, for the session

local function isSecret(v)
    return issecretvalue and issecretvalue(v) or false
end

local function plainString(v)
    return type(v) == "string" and not isSecret(v)
end

--- A globalstring, or the fallback when the client lacks it.
local function label(global, fallback)
    local s = _G[global]
    if plainString(s) and s ~= "" then return s end
    return fallback
end
Config.Label = label

--- A C function by name, when the client has it.
local function call(name, ...)
    local fn = _G[name]
    if type(fn) ~= "function" then return false end
    return pcall(fn, ...)
end

--- A table field that is a value or a function, as a boolean.
local function flag(v)
    if type(v) == "function" then
        local ok, result = pcall(v)
        return ok and result == true
    end
    return v == true
end

local function stripEvent(event)
    return (event:gsub("^CHAT_MSG_", ""))
end

--------------------------------------------------------------------------------
-- The rows
--------------------------------------------------------------------------------

--- A row's label: its text, a string or a function, else the globalstring
--- named by its type (ChatConfig_CreateCheckboxes, ChatConfigFrame.lua:850).
local function rowLabel(entry)
    local text = entry.text
    if type(text) == "function" then
        local ok, s = pcall(text)
        if ok and plainString(s) then return s end
    elseif plainString(text) then
        return text
    end
    local s = entry.type and _G[entry.type]
    if plainString(s) then return s end
    return tostring(entry.type or "")
end

--- The color key of a type: the first member of its group with CHAT_MSG_
--- stripped, as GetMessageTypeColor reads it; the type itself when there is
--- no group (the PvP keys, CHANNELn, DISCORD_PLAYER_NAME).
function Config.ColorKey(chatType)
    local groups = _G.ChatTypeGroup
    local members = type(groups) == "table" and groups[chatType]
    local first = type(members) == "table" and members[1]
    if plainString(first) then return stripEvent(first) end
    return chatType
end

--- The rows of one section, read off Blizzard's table now.
function Config.Rows(section)
    local rows = {}
    local list = _G[section.table]
    if type(list) ~= "table" then return rows end
    for _, entry in ipairs(list) do
        if type(entry) == "table" then
            local chatType = entry.type
            rows[#rows + 1] = {
                type = chatType,
                group = PVP_GROUPS[chatType] or chatType,
                colorKey = chatType and Config.ColorKey(chatType) or nil,
                label = rowLabel(entry),
                disabled = flag(entry.disabled),
                hidden = flag(entry.hidden),
                blank = entry.isBlank == true,
                swatchOnly = section.swatchOnly == true,
            }
        end
    end
    return rows
end

--------------------------------------------------------------------------------
-- Colors
--------------------------------------------------------------------------------

--- r, g, b, 1 of a color key, white when the client has no entry for it.
function Config.Color(colorKey)
    local info = _G.ChatTypeInfo
    local entry = type(info) == "table" and info[colorKey]
    if type(entry) ~= "table" then
        local extra = _G.ChatAdditionalColors
        entry = type(extra) == "table" and extra[colorKey]
    end
    if type(entry) == "table" and type(entry.r) == "number" and type(entry.g) == "number" and type(entry.b) == "number" then
        return entry.r, entry.g, entry.b, 1
    end
    return 1, 1, 1, 1
end

--- The swatch's write: once per member of the type's group, else once on
--- the type (messageTypeColorSwatch, ChatConfigFrame.lua:1494-1505).
function Config.SetColor(chatType, r, g, b)
    local groups = _G.ChatTypeGroup
    local members = type(groups) == "table" and groups[chatType]
    if type(members) == "table" and #members > 0 then
        for _, event in ipairs(members) do
            if plainString(event) then call("ChangeChatColor", stripEvent(event), r, g, b) end
        end
    else
        call("ChangeChatColor", chatType, r, g, b)
    end
end

--------------------------------------------------------------------------------
-- The windows
--------------------------------------------------------------------------------

local function windowName(id)
    local name = Style.Cache(id)
    if plainString(name) and name ~= "" then return name end
    return "Window " .. tostring(id)
end

--- The windows the page offers, in strip order: the strip's entries when the
--- holder is built, else the cache's shown windows by dock index. A pop-out
--- has no cache slot to write and is left out.
function Config.Windows()
    local max = Style.MaxWindows()
    local list = {}
    local ordered = CR.Tabs and CR.Tabs.Ordered and CR.Tabs.Ordered()
    if type(ordered) == "table" and #ordered > 0 then
        for _, entry in ipairs(ordered) do
            if type(entry.id) == "number" and entry.id <= max then
                list[#list + 1] = { id = entry.id, name = windowName(entry.id) }
            end
        end
        return list
    end
    for id = 1, max do
        local _, _, _, _, _, _, shown, _, index = Style.Cache(id)
        if id == 1 or shown == true then
            list[#list + 1] = { id = id, name = windowName(id), index = type(index) == "number" and index or math.huge }
        end
    end
    table.sort(list, function(a, b)
        if a.index == b.index then return a.id < b.id end
        return a.index < b.index
    end)
    return list
end

--- The window the page edits, window 1 when the pick is gone.
function Config.SelectedWindow(windows)
    for _, w in ipairs(windows or Config.Windows()) do
        if w.id == selectedWindow then return selectedWindow end
    end
    selectedWindow = 1
    return 1
end

function Config.SetSelectedWindow(id)
    if type(id) == "number" then selectedWindow = id end
end

--------------------------------------------------------------------------------
-- Groups and channels per window
--------------------------------------------------------------------------------

--- The window's message groups from the chat cache, as a set.
function Config.Groups(id)
    local set = groupSets[id]
    if set then return set end
    set = {}
    local ok, list = pcall(function() return { _G.GetChatWindowMessages(id) } end)
    if ok then
        for _, group in ipairs(list) do
            if plainString(group) then set[group] = true end
        end
    end
    groupSets[id] = set
    return set
end

--- The window's channels from the chat cache: name and zone id pairs, and
--- the two indexes the filter matches a line against.
function Config.Channels(id)
    local set = channelSets[id]
    if set then return set end
    set = { list = {}, byName = {}, byZone = {} }
    local ok, pairsList = pcall(function() return { _G.GetChatWindowChannels(id) } end)
    if ok then
        for i = 1, #pairsList, 2 do
            local name, zone = pairsList[i], pairsList[i + 1]
            if plainString(name) then
                set.list[#set.list + 1] = { name = name, zone = zone }
                set.byName[name:upper()] = true
                if type(zone) == "number" and not isSecret(zone) and zone > 0 then set.byZone[zone] = true end
            end
        end
    end
    channelSets[id] = set
    return set
end

function Config.HasChannel(id, name)
    return plainString(name) and Config.Channels(id).byName[name:upper()] == true
end

--- Drop the cached sets: one window's, or every window's.
function Config.Invalidate(id)
    if id then
        groupSets[id], channelSets[id] = nil, nil
    else
        groupSets, channelSets, flashGroups = {}, {}, nil
    end
end

--- The window's twin rebuilt from its source through the filter.
local function resync(id)
    local Display = CR.Display
    if not (Display and Display.Entries) then return end
    for _, entry in ipairs(Display.Entries()) do
        if entry.id == id then Display.Resync(entry.source) end
    end
end

function Config.SetGroup(id, group, on)
    if not plainString(group) then return end
    if on then
        call("AddChatWindowMessages", id, group)
    else
        call("RemoveChatWindowMessages", id, group)
    end
    Config.Invalidate(id)
    resync(id)
end

function Config.SetChannel(id, name, on)
    if not plainString(name) then return end
    if on then
        call("AddChatWindowChannel", id, name)
    else
        call("RemoveChatWindowChannel", id, name)
    end
    Config.Invalidate(id)
    resync(id)
end

--------------------------------------------------------------------------------
-- The snapshot and what waits on the reload
--------------------------------------------------------------------------------

--- Each window's cache sets as they are now: at Display.Build, what the
--- frames registered at login; on retail, at the page's first open.
function Config.Snapshot()
    Config.Invalidate()
    snapshot = { groups = {}, channels = {} }
    for id = 1, Style.MaxWindows() do
        local groups = {}
        for group in pairs(Config.Groups(id)) do groups[group] = true end
        local channels = {}
        for name in pairs(Config.Channels(id).byName) do channels[name] = true end
        snapshot.groups[id] = groups
        snapshot.channels[id] = channels
    end
end

function Config.EnsureSnapshot()
    if not snapshot then Config.Snapshot() end
end

--- The groups and channels checked this session that the window's frame did
--- not listen to at login: they arrive at the reload.
function Config.Pending(id)
    Config.EnsureSnapshot()
    local out = {}
    local hadGroups = snapshot.groups[id] or {}
    for group in pairs(Config.Groups(id)) do
        if not hadGroups[group] then out[#out + 1] = group end
    end
    local hadChannels = snapshot.channels[id] or {}
    for name in pairs(Config.Channels(id).byName) do
        if not hadChannels[name] then out[#out + 1] = name end
    end
    table.sort(out)
    return out
end

function Config.PendingCount()
    local n = 0
    for id = 1, Style.MaxWindows() do n = n + #Config.Pending(id) end
    return n
end

--------------------------------------------------------------------------------
-- The twin filter
--------------------------------------------------------------------------------

--- Whether the window's twin shows a mirrored line: the bridge's question
--- before AddMessage and in the resync. The event is the eighth argument
--- Blizzard's formatter passes, the payload its ninth, a SafePack of the
--- event's arguments (ChatFrameOverrides.lua:675). A line that cannot be
--- placed passes: no event (print), a secret one, a group no table names, a
--- pop-out's line, a channel payload neither field of which reads plain.
function Config.Shows(entry, event, eventArgs)
    if not plainString(event) then return true end
    local id = entry and entry.id
    if type(id) ~= "number" or id > Style.MaxWindows() then return true end
    if event == CHANNEL_EVENT then
        -- Blizzard's own match: the zone channel id against zoneChannelList,
        -- else the base name against channelList (ChatFrameOverrides.lua:337-345)
        if type(eventArgs) ~= "table" then return true end
        local ok, zone, base = pcall(function() return eventArgs[7], eventArgs[9] end)
        if not ok then return true end
        local zoneOk = type(zone) == "number" and not isSecret(zone)
        local baseOk = plainString(base)
        if not zoneOk and not baseOk then return true end
        local set = Config.Channels(id)
        if zoneOk and zone > 0 and set.byZone[zone] then return true end
        if baseOk and set.byName[base:upper()] then return true end
        return false
    end
    local inverted = _G.ChatTypeGroupInverted
    local group = type(inverted) == "table" and inverted[event]
    if not plainString(group) then return true end
    return Config.Groups(id)[group] == true
end

--------------------------------------------------------------------------------
-- The flash
--------------------------------------------------------------------------------

--- The groups whose lines flash a tab: the rows of the sections marked
--- flash, Blizzard's Player Messages, read off the table once and dropped
--- with the other sets (VOICE_TEXT joins that table at PLAYER_ENTERING_WORLD).
function Config.FlashGroups()
    if flashGroups then return flashGroups end
    local set = {}
    for _, section in ipairs(Config.SECTIONS) do
        if section.flash then
            for _, row in ipairs(Config.Rows(section)) do
                if plainString(row.group) and not row.blank then set[row.group] = true end
            end
        end
    end
    flashGroups = set
    return set
end

--- Whether a mirrored line is a player's message: a channel message, or an
--- event whose group is a Player Messages row. The strip's Every Window mode
--- flashes for these alone (tabs.lua): a combat, loot, tradeskill or system
--- line is a log, and the combat log window carries nothing else. Blizzard's
--- own tabs flash for whispers only (ChatFrameUtil.FlashTabIfNotShown), the
--- Whispers Only mode. No event (print) or a secret one flashes nothing.
function Config.IsPlayerMessage(event)
    if not plainString(event) then return false end
    if event == CHANNEL_EVENT then return true end
    local inverted = _G.ChatTypeGroupInverted
    local group = type(inverted) == "table" and inverted[event]
    return plainString(group) and Config.FlashGroups()[group] == true
end

--------------------------------------------------------------------------------
-- The channel list
--------------------------------------------------------------------------------

--- The joined channels as Blizzard's CreateChatChannelList builds them
--- (ChatConfigFrame.lua:1690-1730): one row per slot, a blank row for every
--- gap in the numbering, a regional channel disabled while the regional
--- service is off, leave offered on a channel with no ruleset.
function Config.ChannelList()
    local rows = {}
    local ok, list = pcall(function() return { _G.GetChannelList() } end)
    if not ok then return rows end
    local api = _G.C_ChatInfo
    local util = _G.ChatFrameUtil
    local none = _G.Enum and _G.Enum.ChatChannelRuleset and _G.Enum.ChatChannelRuleset.None
    local count = 1
    for i = 1, #list, 3 do
        local id, name, disabled = list[i], list[i + 1], list[i + 2]
        if type(id) == "number" and plainString(name) then
            while count < id do
                rows[#rows + 1] = { id = count, blank = true, label = count .. ". " .. label("EMPTY", "Empty") }
                count = count + 1
            end
            disabled = disabled == true
            if api and api.IsChannelRegional and api.IsRegionalServiceAvailable then
                local okR, regional = pcall(api.IsChannelRegional, id)
                if okR and regional == true then
                    local okS, available = pcall(api.IsRegionalServiceAvailable)
                    if not (okS and available == true) then disabled = true end
                end
            end
            local shown = name
            if util and util.ResolveChannelName then
                local okN, resolved = pcall(util.ResolveChannelName, name)
                if okN and plainString(resolved) and resolved ~= "" then shown = resolved end
            end
            local canLeave = false
            if not disabled and api and api.GetChannelRuleset and none ~= nil then
                local okRs, ruleset = pcall(api.GetChannelRuleset, id)
                canLeave = okRs and ruleset == none
            end
            rows[#rows + 1] = {
                id = id, name = name, label = id .. ". " .. shown,
                disabled = disabled, canLeave = canLeave, colorKey = "CHANNEL" .. id,
            }
            count = count + 1
        end
    end
    return rows
end

--- Two slots swapped, the colors following their channels: Blizzard swaps
--- the two ChatTypeInfo tables in Lua before its C call
--- (ChatConfigFrame.lua:2256-2265); here the C write carries the colors.
function Config.SwapChannels(a, b)
    local api = _G.C_ChatInfo
    if not (api and api.SwapChatChannelsByChannelIndex) then return false end
    local ar, ag, ab = Config.Color("CHANNEL" .. a)
    local br, bg, bb = Config.Color("CHANNEL" .. b)
    local ok = pcall(api.SwapChatChannelsByChannelIndex, a, b)
    if not ok then return false end
    Config.SetColor("CHANNEL" .. a, br, bg, bb)
    Config.SetColor("CHANNEL" .. b, ar, ag, ab)
    Config.Invalidate()
    return true
end

function Config.LeaveChannel(id)
    return call("LeaveChannelByLocalID", id)
end

--------------------------------------------------------------------------------
-- Chat Defaults, Reset Chat Positions, the reload
--------------------------------------------------------------------------------

local function controls()
    return addon.UI and addon.UI.Controls
end

function Config.Reload()
    local api = _G.C_UI
    local reload = (api and api.Reload) or _G.ReloadUI
    if reload then pcall(reload) end
end

--- Chat Defaults: the two C calls FCF_ResetChatWindows ends in, behind
--- Blizzard's own question. The frame-side cleanup it does first is the
--- login pass's work, which the reload runs.
function Config.ResetChat()
    local Controls = controls()
    if not (Controls and Controls.ShowDialog) then return end
    Controls:ShowDialog(nil, {
        text = label("RESET_CHAT_WINDOW", "Reset every chat window to the default settings?") .. " The interface reloads.",
        acceptText = "Reset and Reload", cancelText = label("CANCEL", "Cancel"),
        onAccept = function()
            call("ResetChatWindows", tonumber(_G.CHAT_FRAME_DEFAULT_FONT_SIZE) or 14)
            local api = _G.C_ChatInfo
            if api and api.ResetDefaultZoneChannels then pcall(api.ResetDefaultZoneChannels) end
            Config.Reload()
        end,
    })
end

--- Reset Chat Positions: the CONFIRM_REDOCK_CHAT popup's call.
function Config.RedockWindows()
    local Controls = controls()
    if not (Controls and Controls.ShowDialog) then return end
    Controls:ShowDialog(nil, {
        text = label("CONFIRM_REDOCK_CHAT", "Reset every chat window's position?"),
        acceptText = label("ACCEPT", "Accept"), cancelText = label("CANCEL", "Cancel"),
        onAccept = function() call("RedockChatWindows") end,
    })
end

--------------------------------------------------------------------------------
-- The menu's Settings row, the Combat Log tab's gate, /camelot chat
--------------------------------------------------------------------------------

--- The tab menu's Settings row: the page on the window. The menu never
--- opens in combat, and OpenToPage returns on its own there.
function Config.Open(entry)
    if entry and type(entry.id) == "number" then selectedWindow = entry.id end
    if addon.UI and addon.UI.OpenToPage then addon.UI:OpenToPage(CR.CONFIG_NAV_KEY) end
end

--- The Combat Log tab draws on the combat log window once Blizzard's filter
--- addon has loaded; its rows are a later pass.
function Config.CombatLogAvailable(id)
    return id == 2 and type(_G.Blizzard_CombatLog_Filters) == "table"
end

function Config.Describe(push)
    local parts = {}
    for _, section in ipairs(Config.SECTIONS) do
        parts[#parts + 1] = string.format("%s %d", section.key, #Config.Rows(section))
    end
    local flashes = 0
    for _ in pairs(Config.FlashGroups()) do flashes = flashes + 1 end
    push("  config rows: %s; channels %d; snapshot %s; pending %d; flash groups %d",
        table.concat(parts, ", "), #Config.ChannelList(), snapshot and "taken" or "none", Config.PendingCount(), flashes)
    for _, w in ipairs(Config.Windows()) do
        local n = 0
        for _ in pairs(Config.Groups(w.id)) do n = n + 1 end
        push("    window %d (%s): %d groups, %d channels, %d pending",
            w.id, w.name, n, #Config.Channels(w.id).list, #Config.Pending(w.id))
    end
end

-- A change Blizzard announces drops the cached sets; the page re-reads.
addon.Events.On(CR.OWNER .. "Config", "UPDATE_CHAT_WINDOWS", function() Config.Invalidate() end)
