-- keybinds.lua - Every keybinding as a string: the snapshot, the codec and the apply
local addonName, addon = ...

--------------------------------------------------------------------------------
-- The keys a player bound are engine state, not addon state: they live in the
-- client's binding set and never pass through saved variables. This file
-- carries them out as one prefixed string, on the profile codec
-- (addon.ImportExport), and back in, so a character on a fresh install gets
-- its keys without rebinding by hand. Nothing is stored: the page's two boxes
-- keep session text only.
--
-- The string is a full snapshot, a row per command the client enumerates,
-- keys absent where the command had none. An import makes every command the
-- string names and this client knows match the string exactly, in Blizzard's
-- order per command (free its keys, then bind), skips the commands this
-- client lacks, and saves the current binding set once. A binding context is
-- derived on the client making the call and never stored, since the contexts
-- differ between clients.
--------------------------------------------------------------------------------

local Keybinds = {}
addon.Keybinds = Keybinds

Keybinds.VERSION = 1

-- Session-only text behind the page's two boxes, so a collapse or a page
-- change keeps what was generated or pasted.
Keybinds.state = { exportText = "", importText = "" }

Keybinds.COMBAT_MESSAGE = "Keybinds cannot change in combat."

local FAILED_SHOWN = 8

local function codec()
    return addon.ImportExport
end

-- Blizzard's own skip: HEADER and PREFACE rows are the panel's spacers and
-- labels, not commands. The debug category is dropped as a guard; the client
-- is not expected to enumerate hidden rows.
local function isReal(action, category)
    return type(action) == "string" and action ~= ""
        and action:sub(1, 6) ~= "HEADER" and action:sub(1, 7) ~= "PREFACE"
        and category ~= "BINDING_HEADER_DEBUG"
end

-- A key is a non-empty string; anything else is "unbound".
local function key(k)
    if type(k) == "string" and k ~= "" then return k end
    return nil
end

local function contextFor(action)
    local kb = C_KeyBindings
    if kb and kb.GetBindingContextForAction then
        return kb.GetBindingContextForAction(action)
    end
    return nil
end

local function currentKeys(action, ctx)
    local k1, k2 = GetBindingKey(action, nil, ctx)
    return key(k1), key(k2)
end

local function currentSet()
    if type(GetCurrentBindingSet) == "function" then
        return GetCurrentBindingSet()
    end
    return nil
end

local function setName(set)
    local sets = Enum and Enum.BindingSet
    if sets and set == sets.Character then return "character" end
    if sets and set == sets.Account then return "account" end
    return "current"
end

local function available()
    return type(GetNumBindings) == "function" and type(GetBinding) == "function"
        and type(GetBindingKey) == "function"
end

--------------------------------------------------------------------------------
-- Export
--------------------------------------------------------------------------------

--- One row per command the client enumerates, { a, k1, k2 }, keys absent when
-- unbound. Named fields, so a nil key leaves no array hole for the serializer.
function Keybinds.Snapshot()
    local rows = {}
    for i = 1, GetNumBindings() do
        local action, category = GetBinding(i)
        if isReal(action, category) then
            local k1, k2 = currentKeys(action, contextFor(action))
            rows[#rows + 1] = { a = action, k1 = k1, k2 = k2 }
        end
    end
    return rows
end

--- The prefixed string, or nil and a message.
function Keybinds.Export()
    if not available() then return nil, "Keybindings are not available." end
    local IE = codec()
    if not (IE and IE.EncodeEnvelope) then return nil, "Import/export is not available." end
    local rows = Keybinds.Snapshot()
    local envelope = {
        version = Keybinds.VERSION,
        bindingSet = currentSet(),
        character = (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?"),
        count = #rows,
        data = rows,
    }
    return IE:EncodeEnvelope(envelope, IE.PREFIX_KEYBINDS)
end

--------------------------------------------------------------------------------
-- Decode
--------------------------------------------------------------------------------

local function startsWith(str, prefix)
    return type(prefix) == "string" and prefix ~= "" and str:sub(1, #prefix) == prefix
end

--- Trims, names a string meant for another importer, decodes and checks the
-- shape. The other addon's string is accepted on purpose: the command names
-- overlap, and a command this client lacks is skipped at import. Returns the
-- envelope, or nil and a message.
function Keybinds.Decode(str)
    local IE = codec()
    if not (IE and IE.DecodeEnvelope) then return nil, "Import/export is not available." end
    if type(str) ~= "string" then return nil, "No import string provided." end
    str = str:match("^%s*(.-)%s*$") or ""
    if str == "" then return nil, "No import string provided." end
    if startsWith(str, IE.PREFIX_PROFILE) then
        return nil, "That is a " .. addon.Brand .. " profile string. Import it under Profiles > Import/Export."
    end
    if startsWith(str, IE.PREFIX_AURA) then
        return nil, "That is a " .. addon.Brand .. " aura string. Import it from the Aura List."
    end
    local ok, envelope = IE:DecodeEnvelope(str, IE.PREFIX_KEYBINDS, "keybind")
    if not ok then return nil, envelope end
    if type(envelope.version) ~= "number" or type(envelope.data) ~= "table" then
        return nil, "The string holds no keybinds."
    end
    if envelope.version > Keybinds.VERSION then
        return nil, "This keybind string was written by a newer version of " .. addon.Brand .. ". Update the addon."
    end
    return envelope
end

--------------------------------------------------------------------------------
-- Apply
--------------------------------------------------------------------------------

local function knownActions()
    local known = {}
    for i = 1, GetNumBindings() do
        local action, category = GetBinding(i)
        if isReal(action, category) then known[action] = true end
    end
    return known
end

-- Binds one slot. A false return is the client refusing the key, a name it
-- does not know; Blizzard's listener puts the old key back, so this does the
-- same while that key is still free.
local function bindSlot(action, ctx, want, old, failed)
    if not want then return end
    if SetBinding(want, action, ctx) then return end
    if old and type(GetBindingAction) == "function" and GetBindingAction(old, nil, ctx) == "" then
        SetBinding(old, action, ctx)
    end
    failed[#failed + 1] = action .. ": " .. want
end

-- One walk over the string's rows against this client, counting; `write`
-- makes the changes. A command whose keys already match is skipped, so a
-- re-import changes nothing and the binding events stay bounded. A key held
-- by another command moves on SetBinding, as in Blizzard's panel; the string
-- is one consistent snapshot, so that command gets its own keys when its row
-- comes up. Both slots are cleared before either is bound, which keeps slot
-- order: the engine fills slots in binding order.
local function walk(envelope, write)
    local known = knownActions()
    local r = { changed = 0, unchanged = 0, unknown = 0, failed = {} }
    for _, row in ipairs(envelope.data) do
        local action = type(row) == "table" and row.a or nil
        if type(action) ~= "string" or not known[action] then
            r.unknown = r.unknown + 1
        else
            local ctx = contextFor(action)
            local cur1, cur2 = currentKeys(action, ctx)
            local want1, want2 = key(row.k1), key(row.k2)
            if cur1 == want1 and cur2 == want2 then
                r.unchanged = r.unchanged + 1
            else
                r.changed = r.changed + 1
                if write then
                    if cur1 then SetBinding(cur1, nil, ctx) end
                    if cur2 then SetBinding(cur2, nil, ctx) end
                    bindSlot(action, ctx, want1, cur1, r.failed)
                    bindSlot(action, ctx, want2, cur2, r.failed)
                end
            end
        end
    end
    return r
end

--- The counts an import would produce; nothing written.
function Keybinds.Preview(envelope)
    if not available() then return nil, "Keybindings are not available." end
    return walk(envelope, false)
end

--- Writes the string's keys and saves the current binding set once. Out of
-- combat only. Returns the counts, or nil and a message.
function Keybinds.Apply(envelope)
    if InCombatLockdown() then return nil, Keybinds.COMBAT_MESSAGE end
    if not available() or type(SetBinding) ~= "function" or type(SaveBindings) ~= "function" then
        return nil, "Keybindings are not available."
    end
    local r = walk(envelope, true)
    if r.changed > 0 then
        local set = currentSet() or (Enum and Enum.BindingSet and Enum.BindingSet.Account) or 1
        SaveBindings(set)
    end
    return r
end

--------------------------------------------------------------------------------
-- Dialog text
--------------------------------------------------------------------------------

local function origin(envelope)
    local parts = {}
    if envelope.bindingSet ~= nil then
        parts[#parts + 1] = setName(envelope.bindingSet) .. " bindings"
    end
    if type(envelope.addon) == "string" then
        local writer = "written by " .. envelope.addon
        if type(envelope.addonVersion) == "string" then writer = writer .. " " .. envelope.addonVersion end
        if type(envelope.exportedAt) == "string" then writer = writer .. " on " .. envelope.exportedAt end
        parts[#parts + 1] = writer
    end
    if #parts == 0 then return "" end
    return " (" .. table.concat(parts, ", ") .. ")"
end

local function character(envelope)
    if type(envelope.character) == "string" and envelope.character ~= "" then
        return envelope.character
    end
    return "an unknown character"
end

function Keybinds.ConfirmText(envelope, preview)
    local count = type(envelope.count) == "number" and envelope.count or #envelope.data
    return string.format(
        "Apply %d keybinds from %s%s?\n\n%d will change, %d already match, %d are not on this client."
            .. "\n\nYour %s bindings are overwritten and saved.",
        count, character(envelope), origin(envelope),
        preview.changed, preview.unchanged, preview.unknown, setName(currentSet()))
end

function Keybinds.ResultText(envelope, r)
    local text = string.format(
        "Keybinds imported from %s.\n\nChanged: %d\nAlready matching: %d\nNot on this client: %d",
        character(envelope), r.changed, r.unchanged, r.unknown)
    if #r.failed > 0 then
        text = text .. "\n\nCould not bind:"
        for i = 1, math.min(#r.failed, FAILED_SHOWN) do
            text = text .. "\n" .. r.failed[i]
        end
        if #r.failed > FAILED_SHOWN then
            text = text .. "\nand " .. (#r.failed - FAILED_SHOWN) .. " more"
        end
    end
    return text
end
