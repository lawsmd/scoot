--------------------------------------------------------------------------------
-- markdown.lua - a small markdown reader, for text a player types.
--
-- Text in, blocks out; no frames. A caller draws one row per block and runs
-- a block's text through Markdown.Inline for the marks inside a line.
--
--   Markdown.Lines(text)            the text split into its lines
--   Markdown.Parse(text)            an array of blocks, one per line:
--       kind     "heading" | "bullet" | "number" | "task" | "rule" |
--                "quote" | "text" | "blank"
--       text     the line with its marker removed
--       level    1 to 3 for a heading
--       indent   0 to 3 for a bullet, number or task: two spaces a level
--       number   the digits of a numbered line, as typed
--       checked  true for "[x]"
--       line     the index of the source line in Markdown.Lines(text)
--   Markdown.Inline(text, colors)   the line with **bold** and `code` as color
--                                   escapes and the :name: shortcodes as
--                                   atlas markup; colors = { strong, dim },
--                                   each a six digit hex string
--   Markdown.RemoveLine(text, index) the text without that line
--   Markdown.ListPrefix(line)       the marker that continues a list after
--                                   this line, and whether the line holds
--                                   nothing but its marker
--
-- A checkbox line is "[ ] " and its text. A list marker in front ("- [ ] ")
-- and a box with no space in it ("[]") read the same.
--
-- What a FontString cannot draw is left out: italics (no italic face ships)
-- and bold inside a wrapped line, which is why ** is a color.
--------------------------------------------------------------------------------

local _, addon = ...

local Markdown = {}
addon.Markdown = Markdown

local MAX_INDENT = 3

-- :name: -> an atlas drawn at the text's own height.
local SHORTCODES = {
    gold = "coin-gold",
    silver = "coin-silver",
    copper = "coin-copper",
    q1 = "Professions-ChatIcon-Quality-Tier1",
    q2 = "Professions-ChatIcon-Quality-Tier2",
    q3 = "Professions-ChatIcon-Quality-Tier3",
    q4 = "Professions-ChatIcon-Quality-Tier4",
    q5 = "Professions-ChatIcon-Quality-Tier5",
}

function Markdown.Lines(text)
    local lines = {}
    if type(text) ~= "string" or text == "" then return lines end
    text = text:gsub("\r", "")
    for line in (text .. "\n"):gmatch("(.-)\n") do
        lines[#lines + 1] = line
    end
    return lines
end

function Markdown.RemoveLine(text, index)
    local lines = Markdown.Lines(text)
    if not lines[index] then return text end
    table.remove(lines, index)
    -- Kept off addon.DebugShowWindow: the joined string is the note's text, not a dump.
    return table.concat(lines, "\n")
end

local function indentOf(lead)
    local width = 0
    for i = 1, #lead do
        width = width + (lead:sub(i, i) == "\t" and 2 or 1)
    end
    return math.min(MAX_INDENT, math.floor(width / 2))
end

local function parseLine(line)
    if line:match("^%s*$") then
        return { kind = "blank", text = "" }
    end

    local hashes, heading = line:match("^(#+)%s+(.*)$")
    if hashes and #hashes <= 3 then
        return { kind = "heading", level = #hashes, text = heading }
    end

    if line:match("^%s*%-%-%-+%s*$") or line:match("^%s*%*%*%*+%s*$") then
        return { kind = "rule", text = "" }
    end

    local lead, mark, task = line:match("^(%s*)[%-%*]?%s*%[([ xX]?)%]%s*(.*)$")
    if lead then
        return { kind = "task", indent = indentOf(lead), checked = mark == "x" or mark == "X", text = task }
    end

    local bulletLead, bullet = line:match("^(%s*)[%-%*]%s+(.*)$")
    if bulletLead then
        return { kind = "bullet", indent = indentOf(bulletLead), text = bullet }
    end

    local numberLead, digits, numbered = line:match("^(%s*)(%d+)[%.%)]%s+(.*)$")
    if numberLead then
        return { kind = "number", indent = indentOf(numberLead), number = digits, text = numbered }
    end

    local quote = line:match("^>%s?(.*)$")
    if quote then
        return { kind = "quote", text = quote }
    end

    return { kind = "text", text = line }
end

function Markdown.Parse(text)
    local blocks = {}
    for index, line in ipairs(Markdown.Lines(text)) do
        local block = parseLine(line)
        block.line = index
        blocks[#blocks + 1] = block
    end
    return blocks
end

function Markdown.Inline(text, colors)
    if type(text) ~= "string" or text == "" then return "" end
    local strong = colors and colors.strong
    local dim = colors and colors.dim

    text = text:gsub(":(%w+):", function(name)
        local atlas = SHORTCODES[name:lower()]
        if atlas then return "|A:" .. atlas .. ":0:0|a" end
    end)
    text = text:gsub("%*%*(.-)%*%*", function(inner)
        if inner == "" then return nil end
        return strong and ("|cff" .. strong .. inner .. "|r") or inner
    end)
    text = text:gsub("`(.-)`", function(inner)
        if inner == "" then return nil end
        return dim and ("|cff" .. dim .. inner .. "|r") or inner
    end)
    return text
end

function Markdown.ListPrefix(line)
    if type(line) ~= "string" then return nil end

    local lead, dash, rest = line:match("^(%s*)([%-%*]?%s*)%[[ xX]?%]%s*(.*)$")
    if lead then
        return lead .. dash .. "[ ] ", rest == ""
    end

    local bulletLead, mark, bulletRest = line:match("^(%s*)([%-%*])%s+(.*)$")
    if bulletLead then
        return bulletLead .. mark .. " ", bulletRest == ""
    end

    local numberLead, digits, close, numberRest = line:match("^(%s*)(%d+)([%.%)])%s+(.*)$")
    if numberLead then
        return numberLead .. (tonumber(digits) + 1) .. close .. " ", numberRest == ""
    end

    return nil
end
