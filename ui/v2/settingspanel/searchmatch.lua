-- searchmatch.lua - Normalization, vocabulary expansion and scoring for the
-- settings search index.
--
-- Contract: this file knows nothing about what a setting is. It takes entries
-- carrying pre-normalized text fields plus a query string, and returns ranked
-- results. It creates no frames, reads no database, and names no module. The
-- product supplies its vocabulary in addon.SearchVocabulary; the default is
-- empty and the file works without one.
--
-- Entry point: Match.Run(index, query) -> results, parsed
local addonName, addon = ...

addon.UI = addon.UI or {}
local Match = {}
addon.UI.SearchMatch = Match

--------------------------------------------------------------------------------
-- Tuning
--------------------------------------------------------------------------------
-- Fields are OR: a term scores against the best field it reaches. Terms are
-- AND: an entry that misses one scores nothing. That combination is what makes
-- "unit frame" reach every setting whose page path carries both words, while
-- "unit portrait" does not reach a page that only answers to one.
local Field = {
    { key = "label",       weight = 10 },
    { key = "keywords",    weight = 8 },
    { key = "path",        weight = 6 },
    { key = "section",     weight = 5 },
    { key = "description", weight = 2 },
    { key = "type",        weight = 1 },
}

-- A field that names the setting itself rather than where it lives. An entry
-- matched only through path, section or type is context: the caller may fold it
-- into its page instead of listing it on its own.
local Strong = { label = true, keywords = true, description = true }

local Kind   = { exact = 1.0, prefix = 0.75, infix = 0.5 }
local Bonus  = { labelHead = 6, pathHead = 3, page = 4 }
local Factor = { synonym = 0.85, demoted = 0.6 }
local Limit  = { results = 200, terms = 8, infix = 3 }
local Rank   = { page = 1, section = 2, setting = 3 }

--------------------------------------------------------------------------------
-- Normalization
--------------------------------------------------------------------------------
-- A light plural fold, not a stemmer. Query text and indexed text run through
-- the same function, so the only requirement is that both sides land on the
-- same string. The two trailing-letter tests below leave "Boss", "Focus",
-- "Class" and "Status" whole rather than folding them to a false singular.
local function singular(word)
    local n = #word
    if n < 4 then return word end
    if word:sub(n - 2) == "ies" then return word:sub(1, n - 3) .. "y" end
    if word:sub(n - 1) == "es" then
        local c = word:sub(n - 2, n - 2)
        if c == "s" or c == "x" or c == "z" or c == "h" then return word:sub(1, n - 2) end
    end
    if word:sub(n) == "s" then
        local c = word:sub(n - 1, n - 1)
        if c ~= "s" and c ~= "u" then return word:sub(1, n - 1) end
    end
    return word
end

-- Two forms per string: the folded words, and every folded word run together.
-- The squashed form is what lets a typed "castbar" reach "Cast Bars" and
-- "unitframe" reach "Unit Frames". %w skips high bytes, so a non-ASCII
-- character splits a word rather than joining one, and lower() is ASCII only.
local cache = {}

--- Returns { tokens = {...}, squashed = "..." }, or nil for text with no words.
function Match.Normalize(text)
    if type(text) ~= "string" or text == "" then return nil end
    local hit = cache[text]
    if hit ~= nil then
        if hit == false then return nil end
        return hit
    end
    local tokens = {}
    for word in text:gmatch("[%w]+") do
        tokens[#tokens + 1] = singular(word:lower())
    end
    if #tokens == 0 then
        cache[text] = false
        return nil
    end
    local norm = { tokens = tokens, squashed = table.concat(tokens) }
    cache[text] = norm
    return norm
end

-- Keyed by the raw string, so the hundreds of rows labelled "Size" and the one
-- page path shared by every row on a page each normalize once.
function Match.ResetCache()
    cache = {}
end

--------------------------------------------------------------------------------
-- Vocabulary
--------------------------------------------------------------------------------
-- addon.SearchVocabulary.synonyms maps a word someone types to the words the
-- index carries. Expansion runs on the query and never on the index, so a
-- synonym costs nothing until it is typed and an edit needs no index rebuild.
local alternates

local function buildVocabulary()
    alternates = {}
    local vocab = addon.SearchVocabulary
    local synonyms = vocab and vocab.synonyms
    if type(synonyms) ~= "table" then return end
    for word, phrases in pairs(synonyms) do
        if type(word) == "string" and type(phrases) == "table" then
            local key = singular(word:lower())
            local list = alternates[key] or {}
            for i = 1, #phrases do
                local norm = Match.Normalize(phrases[i])
                if norm then list[#list + 1] = norm end
            end
            if #list > 0 then alternates[key] = list end
        end
    end
end

function Match.InvalidateVocabulary()
    alternates = nil
end

--------------------------------------------------------------------------------
-- Field matching
--------------------------------------------------------------------------------
local function matchToken(norm, token)
    local tokens = norm.tokens
    for i = 1, #tokens do
        if tokens[i] == token then return Kind.exact end
    end
    if #token > 1 then
        for i = 1, #tokens do
            if tokens[i]:find(token, 1, true) == 1 then return Kind.prefix end
        end
        if #token >= Limit.infix and norm.squashed:find(token, 1, true) then return Kind.infix end
    end
    return nil
end

-- A synonym may be a phrase, such as "cdm" standing for "cooldown manager".
-- Every word of the phrase has to land in the same field, and the weakest word
-- is what the phrase scores. Failing that, the phrase run together is tried
-- against the squashed field.
local function matchPhrase(norm, phrase)
    local words = phrase.tokens
    if #words == 1 then return matchToken(norm, words[1]) end
    local worst
    for i = 1, #words do
        local kind = matchToken(norm, words[i])
        if not kind then
            if #phrase.squashed >= Limit.infix and norm.squashed:find(phrase.squashed, 1, true) then
                return Kind.infix
            end
            return nil
        end
        if not worst or kind < worst then worst = kind end
    end
    return worst
end

local function scoreTerm(fields, term)
    local best, bestKey = 0, nil
    for i = 1, #Field do
        local spec = Field[i]
        local norm = fields[spec.key]
        if norm then
            local kind, factor = matchToken(norm, term.token), 1
            local list = term.alternates
            if list then
                for a = 1, #list do
                    local alt = matchPhrase(norm, list[a])
                    if alt and (not kind or alt * Factor.synonym > kind * factor) then
                        kind, factor = alt, Factor.synonym
                    end
                end
            end
            if kind then
                local value = spec.weight * kind * factor
                if value > best then best, bestKey = value, spec.key end
            end
        end
    end
    return best, bestKey
end

--------------------------------------------------------------------------------
-- Scoring
--------------------------------------------------------------------------------
--- Score one entry against a parsed query. Returns nil when the entry misses
--- any term, else the score, the set of field keys that carried it, and whether
--- every term landed on a context field only.
function Match.ScoreEntry(entry, parsed)
    local fields = entry.fields
    if not fields then return nil end

    local total, hit, strong = 0, nil, false
    local terms = parsed.terms
    for i = 1, #terms do
        local value, key = scoreTerm(fields, terms[i])
        if value == 0 then return nil end
        total = total + value
        hit = hit or {}
        hit[key] = true
        if Strong[key] then strong = true end
    end

    local label = fields.label
    if label and label.squashed:find(parsed.head, 1, true) == 1 then
        total = total + Bonus.labelHead
    end
    local path = fields.path
    if path and path.squashed:find(parsed.head, 1, true) then
        total = total + Bonus.pathHead
    end
    if entry.kind == "page" then total = total + Bonus.page end
    if entry.demoted then total = total * Factor.demoted end

    return total, hit, not strong
end

--------------------------------------------------------------------------------
-- Query
--------------------------------------------------------------------------------
--- Trim, split on anything that is not a word character, fold, and attach the
--- vocabulary alternates. Returns nil for a query too short to rank.
function Match.ParseQuery(query)
    if type(query) ~= "string" then return nil end
    local trimmed = query:match("^%s*(.-)%s*$") or ""
    if #trimmed < 2 then return nil end
    if not alternates then buildVocabulary() end

    local terms, head = {}, {}
    for word in trimmed:gmatch("[%w]+") do
        if #terms >= Limit.terms then break end
        local token = singular(word:lower())
        terms[#terms + 1] = { token = token, alternates = alternates[token] }
        head[#head + 1] = token
    end
    if #terms == 0 then return nil end

    return { terms = terms, head = table.concat(head), text = trimmed }
end

--------------------------------------------------------------------------------
-- Run
--------------------------------------------------------------------------------
-- A strict chain ending on a string compare, so table.sort cannot raise
-- "invalid order function": rows equal on every key compare false both ways.
local function byScore(a, b)
    if a.score ~= b.score then return a.score > b.score end
    if a.rank ~= b.rank then return a.rank < b.rank end
    local la, lb = #a.entry.label, #b.entry.label
    if la ~= lb then return la < lb end
    if a.entry.breadcrumb ~= b.entry.breadcrumb then return a.entry.breadcrumb < b.entry.breadcrumb end
    return a.entry.label < b.entry.label
end

--- Rank an index against a query. A result is
---   { entry = <index entry>, score = <number>, fields = <set of field keys>,
---     rank = <sort class>, contextOnly = <bool> }
--- and the parsed query comes back beside it, for a caller that highlights the
--- matched run: the folded tokens are what the score was computed from, not the
--- raw query text.
function Match.Run(index, query)
    local parsed = Match.ParseQuery(query)
    if not parsed or not index then return {}, nil end

    local results = {}
    for i = 1, #index do
        local entry = index[i]
        local score, hit, contextOnly = Match.ScoreEntry(entry, parsed)
        if score then
            results[#results + 1] = {
                entry = entry,
                score = score,
                fields = hit,
                contextOnly = contextOnly,
                rank = Rank[entry.kind or "setting"] or Rank.setting,
            }
        end
    end

    table.sort(results, byScore)
    for i = #results, Limit.results + 1, -1 do
        results[i] = nil
    end
    return results, parsed
end
