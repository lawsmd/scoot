-- commands.lua - /scoot command registry (refactor #32).
--
-- Two scopes: "slash" for /scoot <name> and "debug" for /scoot debug <name>.
-- A file registers at its end with addon:RegisterSlashCommand(def) or
-- addon:RegisterDebugCommand(def). The registration must follow every
-- definition it references: a registration error aborts the chunk.
--
-- def = {
--   name    = "dmY",                    -- matched case-insensitively, shown as written
--   aliases = { "tb" },                 -- optional
--   help    = "one line",
--   handler = function(sub, rest) end,  -- rest = raw tokens after the name, from 1;
--                                       -- sub = lower(rest[1] or "")
--   -- or --
--   verbs = {                           -- ordered; matched on lower(rest[1])
--     { word = "state", help = "...", fn = function(...) end },  -- fn(unpack(rest, 2))
--     { word = "trace", usage = "trace <on|off>", help = "...", fn = ... },
--   },
--   default = "state",                  -- verb used when rest[1] is empty (optional)
--   usage   = { "extra help line" },    -- optional, under the entry in generated help
-- }
--
-- A handler or verb that returns Commands.USAGE asks for its usage block.
-- The dispatcher lowercases only the words it matches on; everything after
-- passes raw (font keys, class tokens, and layout names are case-sensitive).
-- Help and usage open the copy window; one-line results stay on addon:Print.
-- This file loads before addon:Print and addon.DebugShowWindow exist and
-- calls neither at load time.
local addonName, addon = ...

local Commands = {}
addon.Commands = Commands

-- Sentinel a handler or verb returns to request its usage block.
Commands.USAGE = {}

local scopes = {
    slash = { list = {}, byName = {}, prefix = "/scoot " },
    debug = { list = {}, byName = {}, prefix = "/scoot debug " },
}

local function register(scope, def)
    local s = scopes[scope]
    if type(def) ~= "table" then
        error("Commands: definition must be a table", 3)
    end
    if type(def.name) ~= "string" or def.name == "" then
        error("Commands: name must be a non-empty string", 3)
    end
    if type(def.help) ~= "string" then
        error(("Commands: '%s' needs a help string"):format(def.name), 3)
    end
    if (def.handler == nil) == (def.verbs == nil) then
        error(("Commands: '%s' needs exactly one of handler or verbs"):format(def.name), 3)
    end
    if def.handler ~= nil and type(def.handler) ~= "function" then
        error(("Commands: '%s' handler must be a function"):format(def.name), 3)
    end
    if def.verbs ~= nil and type(def.verbs) ~= "table" then
        error(("Commands: '%s' verbs must be a table"):format(def.name), 3)
    end
    local keys = { def.name }
    for _, alias in ipairs(def.aliases or {}) do
        keys[#keys + 1] = alias
    end
    for _, key in ipairs(keys) do
        if s.byName[string.lower(key)] then
            error(("Commands: '%s' is already registered in the %s scope"):format(key, scope), 3)
        end
    end
    for _, key in ipairs(keys) do
        s.byName[string.lower(key)] = def
    end
    s.list[#s.list + 1] = def
end

function addon:RegisterSlashCommand(def)
    register("slash", def)
end

function addon:RegisterDebugCommand(def)
    register("debug", def)
end

--------------------------------------------------------------------------------
-- Parsing
--------------------------------------------------------------------------------

local function trim(s)
    if type(s) ~= "string" then return "" end
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Splits on whitespace; a double-quoted run is one token. Moved verbatim from
-- the old handler, including the skip of the character after a closing quote.
function Commands.Parse(msg)
    local s = trim(msg)
    local args = {}
    local i = 1
    while i <= #s do
        local c = s:sub(i, i)
        if c == '"' then
            local j = i + 1
            while j <= #s and s:sub(j, j) ~= '"' do j = j + 1 end
            table.insert(args, s:sub(i + 1, j - 1))
            i = (j < #s) and (j + 2) or (j + 1)
        else
            local j = i
            while j <= #s and not s:sub(j, j):match("%s") do j = j + 1 end
            table.insert(args, s:sub(i, j - 1))
            i = j + 1
        end
    end
    return args
end

--------------------------------------------------------------------------------
-- Help
--------------------------------------------------------------------------------

local function entryLines(scope, def, lines)
    local head = scopes[scope].prefix .. def.name
    if def.aliases and #def.aliases > 0 then
        head = head .. " (" .. table.concat(def.aliases, ", ") .. ")"
    end
    lines[#lines + 1] = head .. " - " .. def.help
    for _, verb in ipairs(def.verbs or {}) do
        local text = verb.usage or verb.word
        if verb.help then text = text .. " - " .. verb.help end
        lines[#lines + 1] = "    " .. text
    end
    for _, text in ipairs(def.usage or {}) do
        lines[#lines + 1] = "    " .. text
    end
end

-- Every entry in the scope, sorted by name.
function Commands.HelpLines(scope)
    local sorted = {}
    for i, def in ipairs(scopes[scope].list) do sorted[i] = def end
    table.sort(sorted, function(a, b) return string.lower(a.name) < string.lower(b.name) end)
    local lines = {}
    for _, def in ipairs(sorted) do
        entryLines(scope, def, lines)
    end
    return lines
end

function Commands.ShowHelp(scope, title, extraLines)
    local lines = Commands.HelpLines(scope)
    for _, text in ipairs(extraLines or {}) do
        lines[#lines + 1] = text
    end
    addon.DebugShowWindow(title, lines)
end

function Commands.ShowUsage(scope, def)
    local lines = {}
    entryLines(scope, def, lines)
    addon.DebugShowWindow(scopes[scope].prefix .. def.name, lines)
end

-- One line for a command whose owning module is disabled this session.
function Commands.NotAvailable(label)
    addon:Print(label .. " is not loaded (module disabled).")
end

--------------------------------------------------------------------------------
-- Dispatch
--------------------------------------------------------------------------------

local function findVerb(def, sub)
    if sub == "" then
        if not def.default then return nil end
        sub = string.lower(def.default)
    end
    for _, verb in ipairs(def.verbs) do
        if string.lower(verb.word) == sub then return verb end
    end
    return nil
end

-- tokens[at] is the command word. Returns false when nothing matched it.
local function dispatch(scope, tokens, at)
    local def = scopes[scope].byName[string.lower(tokens[at] or "")]
    if not def then return false end
    local rest = {}
    for i = at + 1, #tokens do
        rest[#rest + 1] = tokens[i]
    end
    local sub = string.lower(rest[1] or "")
    local result
    if def.handler then
        result = def.handler(sub, rest)
    else
        local verb = findVerb(def, sub)
        if verb then
            result = verb.fn(unpack(rest, 2))
        else
            result = Commands.USAGE
        end
    end
    if result == Commands.USAGE then
        Commands.ShowUsage(scope, def)
    end
    return true
end

-- args is the parsed /scoot line: args[1] names a slash command, args[2] a
-- debug command. Returns false when nothing matched.
function Commands.Dispatch(scope, args)
    return dispatch(scope, args, scope == "debug" and 2 or 1)
end

--------------------------------------------------------------------------------
-- Shared verb sets
--------------------------------------------------------------------------------

-- Verbs for a buffered trace log: trace <on|off>, log, clear.
-- opts = { label = "Power Bar", set = function(enabled) end, show = function() end,
--          clear = function() end }. Appends to `into` when given.
function Commands.TraceVerbs(opts, into)
    local verbs = into or {}
    verbs[#verbs + 1] = {
        word = "trace", usage = "trace <on|off>",
        help = "start or stop buffering " .. opts.label .. " events",
        fn = function(token)
            token = string.lower(token or "")
            if token == "on" then
                opts.set(true)
            elseif token == "off" then
                opts.set(false)
            else
                return Commands.USAGE
            end
        end,
    }
    verbs[#verbs + 1] = { word = "log", help = "show the trace buffer in the copy window", fn = function() opts.show() end }
    verbs[#verbs + 1] = { word = "clear", help = "empty the trace buffer", fn = function() opts.clear() end }
    return verbs
end

--------------------------------------------------------------------------------
-- /scoot debug gateway
--------------------------------------------------------------------------------

addon:RegisterSlashCommand({
    name = "debug",
    help = "diagnostic dumps and probes; /scoot debug alone lists them",
    handler = function(sub, rest)
        if sub == "" or sub == "help" then
            local extra = {}
            if addon.DebugDumpTargets then
                extra[1] = ""
                extra[2] = "/scoot debug <target> - Edit Mode settings dump of a frame; target is one of "
                    .. table.concat(addon.DebugDumpTargets(), ", ") .. ", or any global frame name"
            end
            Commands.ShowHelp("debug", "Scoot debug commands", extra)
            return
        end
        if dispatch("debug", rest, 1) then return end
        addon.DebugDump(rest[1])
    end,
})
