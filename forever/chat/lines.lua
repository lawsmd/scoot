--------------------------------------------------------------------------------
-- forever/chat/lines.lua
-- What a mirrored line may take on its way from Blizzard's window to
-- Camelot's: the short channel labels, the links for addresses, the mention
-- highlight and the timestamp color. Pure functions over the formatted
-- string, each gated on issecretvalue, so a line Blizzard formatted from a
-- secret payload (the chat messaging lockdown) passes through whole and
-- shows as Blizzard drew it. The bridge in display.lua calls Transform once
-- per line.
--------------------------------------------------------------------------------

local addonName, addon = ...

local CR = addon.ChatReplica
local Style = CR.Style

local Lines = {}
CR.Lines = Lines

local function isSecret(v)
    return issecretvalue and issecretvalue(v) or false
end

local function escapePattern(s)
    return (s:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0"))
end

--- fn applied to every stretch of the text outside a |H...|h...|h link, so
--- a pass never writes inside a link's address or its shown text.
local function outsideLinks(text, fn)
    local out, pos = {}, 1
    while true do
        local s, e = text:find("|H.-|h.-|h", pos)
        if not s then break end
        out[#out + 1] = fn(text:sub(pos, s - 1))
        out[#out + 1] = text:sub(s, e)
        pos = e + 1
    end
    out[#out + 1] = fn(text:sub(pos))
    return table.concat(out)
end

--------------------------------------------------------------------------------
-- Short channel labels
--------------------------------------------------------------------------------
-- Blizzard's format strings carry the label in brackets inside the channel
-- link ("|Hchannel:GUILD|h[Guild]|h %s:"). The label is read off each global
-- at load, so a localized client gets its own, and only the first bracket on
-- the line is replaced: the prefix comes first and the body is left alone.
-- Numbered channels ("[1. General]") keep the number.

local LABELS = {
    { global = "CHAT_GUILD_GET", short = "G" },
    { global = "CHAT_OFFICER_GET", short = "O" },
    { global = "CHAT_PARTY_GET", short = "P" },
    { global = "CHAT_PARTY_LEADER_GET", short = "PL" },
    { global = "CHAT_PARTY_GUIDE_GET", short = "PG" },
    { global = "CHAT_RAID_GET", short = "R" },
    { global = "CHAT_RAID_LEADER_GET", short = "RL" },
    { global = "CHAT_RAID_WARNING_GET", short = "RW" },
    { global = "CHAT_INSTANCE_CHAT_GET", short = "I" },
    { global = "CHAT_INSTANCE_CHAT_LEADER_GET", short = "IL" },
    { global = "CHAT_BATTLEGROUND_GET", short = "BG" },
    { global = "CHAT_BATTLEGROUND_LEADER_GET", short = "BGL" },
}

local shortMap   -- { pattern = replacement }, built once

local function buildShortMap()
    shortMap = {}
    for _, entry in ipairs(LABELS) do
        local format = _G[entry.global]
        if type(format) == "string" then
            local label = format:match("%[(.-)%]")
            if label and label ~= "" then
                shortMap[#shortMap + 1] = { pattern = "%[" .. escapePattern(label) .. "%]", replacement = "[" .. entry.short .. "]" }
            end
        end
    end
end

local function shorten(text)
    if not shortMap then buildShortMap() end
    local changed
    text, changed = text:gsub("%[(%d+)%. [^%]]-%]", "[%1]", 1)
    if changed > 0 then return text end
    for _, entry in ipairs(shortMap) do
        text, changed = text:gsub(entry.pattern, entry.replacement, 1)
        if changed > 0 then return text end
    end
    return text
end

--------------------------------------------------------------------------------
-- Links for addresses
--------------------------------------------------------------------------------
-- An address in a line becomes a |Hurl:...|h link in the link color, outside
-- any link the line already carries. The twin's OnHyperlinkClick opens the
-- copy box for the url kind (display.lua, menu.lua), since the client cannot
-- open a browser. Trailing punctuation stays outside the link.

local URL_COLOR = "|cff3399ff"
local URL_PATTERNS = {
    "%f[%S]https?://[^%s|]+",
    "%f[%S]www%.[%w%-]+%.[^%s|]+",
}

local function linkify(segment)
    for _, pattern in ipairs(URL_PATTERNS) do
        segment = segment:gsub(pattern, function(url)
            local tail = url:match("[%.,;:!%?%)%]]+$") or ""
            if tail ~= "" then url = url:sub(1, #url - #tail) end
            return URL_COLOR .. "|Hurl:" .. url .. "|h" .. url .. "|h|r" .. tail
        end)
    end
    return segment
end

local function urls(text)
    if not (text:find("://", 1, true) or text:find("www.", 1, true)) then return text end
    return outsideLinks(text, linkify)
end

--------------------------------------------------------------------------------
-- Mention highlight
--------------------------------------------------------------------------------
-- The player's name found in the body of a player chat line, after the sender
-- link, so a line the player sent never highlights itself. The name is wrapped
-- in gold outside any link, since a `|r` inside another color run would end
-- that run early; the search starts after the last player link, where the
-- body is in the line's own color.

local HIGHLIGHT = "|cffFFD100"
local MENTION_EVENTS = {
    CHAT_MSG_SAY = true, CHAT_MSG_YELL = true, CHAT_MSG_PARTY = true, CHAT_MSG_PARTY_LEADER = true,
    CHAT_MSG_RAID = true, CHAT_MSG_RAID_LEADER = true, CHAT_MSG_RAID_WARNING = true,
    CHAT_MSG_INSTANCE_CHAT = true, CHAT_MSG_INSTANCE_CHAT_LEADER = true,
    CHAT_MSG_GUILD = true, CHAT_MSG_OFFICER = true, CHAT_MSG_CHANNEL = true,
    CHAT_MSG_EMOTE = true, CHAT_MSG_TEXT_EMOTE = true,
}
local SOUND_THROTTLE = 2
local lastSound = 0

local playerName

local function mention(text)
    if not playerName then
        local ok, name = pcall(UnitName, "player")
        if ok and type(name) == "string" and name ~= "" and not isSecret(name) then playerName = name end
        if not playerName then return text, false end
    end
    local head, body = "", text
    local last
    local pos = 1
    while true do
        local s, e = text:find("|H[Bn]?[Pp]layer:.-|h.-|h", pos)
        if not s then break end
        last = e
        pos = e + 1
    end
    if last then
        head, body = text:sub(1, last), text:sub(last + 1)
    end
    local namePattern = escapePattern(playerName)
    local replaced = 0
    body = outsideLinks(body, function(segment)
        local count
        segment, count = segment:gsub(namePattern, HIGHLIGHT .. playerName .. "|r")
        replaced = replaced + count
        return segment
    end)
    if replaced == 0 then return text, false end
    return head .. body, true
end

--------------------------------------------------------------------------------
-- Timestamp color
--------------------------------------------------------------------------------
-- Blizzard's formatter prepends TimeUtil.BetterDate(format, time()) to the
-- line when the showTimestamps CVar is not "none"
-- (ChatFrameOverrides.lua:659-663). The format's directives become a pattern
-- once per format: digits for %H, %I, %M and %S, letters for the %p
-- BetterDate writes, the rest literal. The stamp matched at the line's start
-- takes the color; the `|r` after it returns the line to its own color.

local stampFormat, stampPattern

local function timestampPattern()
    local format = Style.Timestamps()
    if format == "none" then return nil end
    if format ~= stampFormat then
        stampFormat = format
        local p = format:gsub("[%^%$%(%)%.%[%]%*%+%-%?]", "%%%0")
        p = p:gsub("%%(%a)", function(c)
            if c == "p" then return "%a+" end
            if c == "H" or c == "I" or c == "M" or c == "S" or c == "d" or c == "m" or c == "y" or c == "Y" or c == "j" then
                return "%d+"
            end
            return ".-"
        end)
        stampPattern = "^(" .. p .. ")"
    end
    return stampPattern
end

local function colorStamp(text)
    local pattern = timestampPattern()
    if not pattern then return text end
    local stamp = text:match(pattern)
    if not stamp or stamp == "" then return text end
    local r, g, b = Style.Color("timestampColor", Style.TIMESTAMP_COLOR)
    local hex = string.format("|cff%02x%02x%02x",
        math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
    return hex .. stamp .. "|r" .. text:sub(#stamp + 1)
end

--------------------------------------------------------------------------------
-- The pass
--------------------------------------------------------------------------------

--- The line as Camelot's window draws it. `event` is the chat event the line
--- came from, when Blizzard's formatter passed one along, else nil.
function Lines.Transform(text, r, g, b, event)
    if type(text) ~= "string" or isSecret(text) then return text, r, g, b end
    if Style.Get("shortLabels") == true then
        text = shorten(text)
    end
    if Style.Get("urlLinks") == true then
        text = urls(text)
    end
    if Style.Get("mentionHighlight") == true and type(event) == "string" and not isSecret(event) and MENTION_EVENTS[event] then
        local hit
        text, hit = mention(text)
        if hit and Style.Get("mentionSound") == true then
            local now = GetTime()
            if now - lastSound > SOUND_THROTTLE then
                lastSound = now
                pcall(PlaySound, SOUNDKIT and SOUNDKIT.TELL_MESSAGE or 3081)
            end
        end
    end
    if Style.Get("colorTimestamps") == true then
        text = colorStamp(text)
    end
    return text, r, g, b
end

--- Forget the cached name, labels and stamp pattern, for a /reload-free
--- character swap in tests.
function Lines.Reset()
    playerName = nil
    shortMap = nil
    stampFormat, stampPattern = nil, nil
end
