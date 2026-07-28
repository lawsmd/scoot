-- colorramp.lua - Per-character gradient text utility
local addonName, addon = ...

-- Lighten a color by mixing toward white.
-- ratio 0.0 = unchanged, 1.0 = white
function addon.LightenColor(r, g, b, ratio)
    local t = ratio or 0.45
    return r + (1.0 - r) * t, g + (1.0 - g) * t, b + (1.0 - b) * t
end

-- Darken a color by mixing toward black.
-- ratio 0.0 = unchanged, 1.0 = black
function addon.DarkenColor(r, g, b, ratio)
    local t = ratio or 0.15
    return r * (1 - t), g * (1 - t), b * (1 - t)
end

-- Curated gradient endpoint colors per class.
-- Each is a brighter, hue-shifted variant that creates a richer ramp than generic lightening.
addon.CLASS_GRADIENT_ENDPOINTS = {
    DEATHKNIGHT = { 1.00, 0.35, 0.30 },
    DEMONHUNTER = { 0.88, 0.45, 1.00 },
    DRUID       = { 1.00, 0.75, 0.35 },
    EVOKER      = { 0.40, 0.85, 0.75 },
    HUNTER      = { 0.85, 1.00, 0.60 },
    MAGE        = { 0.55, 0.92, 1.00 },
    MONK        = { 0.35, 1.00, 0.80 },
    PALADIN     = { 1.00, 0.78, 0.88 },
    PRIEST      = { 1.00, 1.00, 0.85 },
    ROGUE       = { 1.00, 1.00, 0.70 },
    SHAMAN      = { 0.30, 0.70, 1.00 },
    WARLOCK     = { 0.75, 0.55, 1.00 },
    WARRIOR     = { 0.95, 0.80, 0.60 },
}

-- Curated gradient colors per specialization (keyed by specID).
-- Each has a base (starting hue) and endpoint (ending hue); darkening/lightening
-- is applied in resolveGradientColors() to match the class gradient treatment.
addon.SPEC_GRADIENT_COLORS = {
    -- Death Knight (class: 0.77, 0.12, 0.23 — red)
    [250] = { base = { 0.82, 0.30, 0.38 }, endpoint = { 1.00, 0.35, 0.30 } },  -- Blood
    [251] = { base = { 0.41, 0.80, 0.94 }, endpoint = { 0.65, 0.92, 1.00 } },  -- Frost
    [252] = { base = { 0.55, 0.78, 0.25 }, endpoint = { 0.75, 0.95, 0.45 } },  -- Unholy

    -- Demon Hunter (class: 0.64, 0.19, 0.79 — purple)
    [577] = { base = { 0.55, 0.85, 0.15 }, endpoint = { 0.75, 1.00, 0.40 } },  -- Havoc (fel green)
    [581] = { base = { 0.85, 0.30, 0.15 }, endpoint = { 1.00, 0.55, 0.35 } },  -- Vengeance (fiery red-orange)

    -- Druid (class: 1.00, 0.49, 0.04 — orange)
    [102] = { base = { 0.35, 0.40, 0.80 }, endpoint = { 0.60, 0.65, 1.00 } },  -- Balance (lunar blue)
    [103] = { base = { 0.85, 0.65, 0.10 }, endpoint = { 1.00, 0.85, 0.35 } },  -- Feral (golden amber)
    [104] = { base = { 0.60, 0.40, 0.20 }, endpoint = { 0.82, 0.65, 0.40 } },  -- Guardian (earthy brown)
    [105] = { base = { 0.20, 0.75, 0.35 }, endpoint = { 0.45, 0.95, 0.55 } },  -- Restoration (nature green)

    -- Evoker (class: 0.20, 0.58, 0.50 — teal)
    [1467] = { base = { 0.88, 0.40, 0.32 }, endpoint = { 1.00, 0.50, 0.35 } },  -- Devastation (fire red)
    [1468] = { base = { 0.20, 0.78, 0.30 }, endpoint = { 0.45, 0.95, 0.50 } },  -- Preservation (emerald green)
    [1473] = { base = { 0.80, 0.65, 0.20 }, endpoint = { 0.95, 0.85, 0.45 } },  -- Augmentation (bronze gold)

    -- Hunter (class: 0.67, 0.83, 0.45 — green)
    [253] = { base = { 0.84, 0.40, 0.36 }, endpoint = { 1.00, 0.50, 0.35 } },  -- Beast Mastery (wild red)
    [254] = { base = { 0.25, 0.50, 0.80 }, endpoint = { 0.50, 0.72, 1.00 } },  -- Marksmanship (steel blue)
    [255] = { base = { 0.55, 0.50, 0.20 }, endpoint = { 0.78, 0.75, 0.40 } },  -- Survival (earthy olive)

    -- Mage (class: 0.25, 0.78, 0.92 — light blue)
    [62]  = { base = { 0.64, 0.40, 0.88 }, endpoint = { 0.75, 0.50, 1.00 } },  -- Arcane (arcane purple)
    [63]  = { base = { 0.90, 0.30, 0.10 }, endpoint = { 1.00, 0.55, 0.30 } },  -- Fire (fire red-orange)
    [64]  = { base = { 0.30, 0.52, 0.76 }, endpoint = { 0.55, 0.55, 1.00 } },  -- Frost (navy → frosty violet)

    -- Monk (class: 0.00, 1.00, 0.59 — jade green)
    [268] = { base = { 0.80, 0.60, 0.15 }, endpoint = { 0.95, 0.80, 0.40 } },  -- Brewmaster (amber gold)
    [269] = { base = { 0.50, 0.70, 0.85 }, endpoint = { 0.72, 0.88, 1.00 } },  -- Windwalker (sky blue)
    [270] = { base = { 0.10, 0.65, 0.65 }, endpoint = { 0.35, 0.88, 0.82 } },  -- Mistweaver (blue-jade)

    -- Paladin (class: 0.96, 0.55, 0.73 — pink)
    [65]  = { base = { 0.85, 0.75, 0.20 }, endpoint = { 1.00, 0.92, 0.45 } },  -- Holy (holy gold)
    [66]  = { base = { 0.80, 0.40, 0.40 }, endpoint = { 0.95, 0.48, 0.40 } },  -- Protection (defensive red)
    [70]  = { base = { 0.90, 0.55, 0.10 }, endpoint = { 1.00, 0.78, 0.35 } },  -- Retribution (fiery gold)

    -- Priest (class: 1.00, 1.00, 1.00 — white)
    [256] = { base = { 0.80, 0.70, 0.25 }, endpoint = { 0.95, 0.88, 0.50 } },  -- Discipline (golden radiance)
    [257] = { base = { 0.90, 0.80, 0.40 }, endpoint = { 1.00, 0.92, 0.65 } },  -- Holy (warm gold)
    [258] = { base = { 0.60, 0.36, 0.80 }, endpoint = { 0.72, 0.45, 0.95 } },  -- Shadow (void purple)

    -- Rogue (class: 1.00, 0.96, 0.41 — yellow)
    [259] = { base = { 0.30, 0.75, 0.25 }, endpoint = { 0.55, 0.92, 0.45 } },  -- Assassination (poison green)
    [260] = { base = { 0.84, 0.40, 0.36 }, endpoint = { 1.00, 0.48, 0.38 } },  -- Outlaw (pirate red)
    [261] = { base = { 0.56, 0.36, 0.76 }, endpoint = { 0.68, 0.45, 0.92 } },  -- Subtlety (shadow purple)

    -- Shaman (class: 0.00, 0.44, 0.87 — blue)
    [262] = { base = { 0.75, 0.20, 0.05 }, endpoint = { 1.00, 0.45, 0.10 } },  -- Elemental (molten lava)
    [263] = { base = { 0.80, 0.75, 0.20 }, endpoint = { 0.95, 0.92, 0.45 } },  -- Enhancement (storm yellow)
    [264] = { base = { 0.08, 0.50, 0.30 }, endpoint = { 0.25, 0.75, 0.50 } },  -- Restoration (dark emerald)

    -- Warlock (class: 0.53, 0.53, 0.93 — purple/blue)
    [265] = { base = { 0.45, 0.65, 0.20 }, endpoint = { 0.68, 0.85, 0.42 } },  -- Affliction (sickly green)
    [266] = { base = { 0.68, 0.40, 0.84 }, endpoint = { 0.80, 0.50, 1.00 } },  -- Demonology (demon purple)
    [267] = { base = { 0.85, 0.30, 0.10 }, endpoint = { 1.00, 0.55, 0.30 } },  -- Destruction (chaos fire)

    -- Warrior (class: 0.78, 0.61, 0.43 — tan)
    [71]  = { base = { 0.76, 0.36, 0.36 }, endpoint = { 0.92, 0.42, 0.35 } },  -- Arms (blood red)
    [72]  = { base = { 0.85, 0.40, 0.10 }, endpoint = { 1.00, 0.65, 0.32 } },  -- Fury (rage orange)
    [73]  = { base = { 0.35, 0.50, 0.70 }, endpoint = { 0.58, 0.72, 0.92 } },  -- Protection (steel blue)
}

-- Strip WoW escape sequences (|cff..., |r, |T...|t, |A...|a, |n) from a string.
local function stripEscapes(text)
    local s = text
    s = s:gsub("|c%x%x%x%x%x%x%x%x", "")  -- |cffRRGGBB or |cAARRGGBB
    s = s:gsub("|r", "")
    s = s:gsub("|T.-|t", "")                -- texture escapes
    s = s:gsub("|A.-|a", "")                -- atlas escapes
    s = s:gsub("|n", "\n")                  -- newline escape
    return s
end

-- Extract individual UTF-8 characters from a string into a table.
local function utf8Chars(text)
    local chars = {}
    local i = 1
    local len = #text
    while i <= len do
        local byte = text:byte(i)
        local charLen
        if byte < 0x80 then
            charLen = 1
        elseif byte < 0xE0 then
            charLen = 2
        elseif byte < 0xF0 then
            charLen = 3
        else
            charLen = 4
        end
        chars[#chars + 1] = text:sub(i, i + charLen - 1)
        i = i + charLen
    end
    return chars
end

-- Build a string with per-character |cffRRGGBB color codes for a two-stop gradient.
-- r1,g1,b1 = start color (0-1), r2,g2,b2 = end color (0-1)
function addon.BuildColorRampString(text, r1, g1, b1, r2, g2, b2)
    if type(text) ~= "string" or (issecretvalue and issecretvalue(text)) or text == "" then return text end

    local clean = stripEscapes(text)
    if clean == "" then return text end

    local chars = utf8Chars(clean)
    local total = #chars
    if total == 0 then return text end

    -- Single character: just use start color
    if total == 1 then
        return string.format("|cff%02x%02x%02x%s|r",
            math.floor(r1 * 255 + 0.5),
            math.floor(g1 * 255 + 0.5),
            math.floor(b1 * 255 + 0.5),
            chars[1])
    end

    -- All characters (including spaces) participate in gradient and get |cff codes.
    -- Wrapping every character uniformly ensures identical escape code structure
    -- between gradient and uniform-color versions, preventing WoW's text shaper
    -- from producing different glyph positioning at run boundaries.
    local parts = {}
    local denom = math.max(total - 1, 1)
    for idx = 1, total do
        local ch = chars[idx]
        local t = (idx - 1) / denom
        local cr = r1 + (r2 - r1) * t
        local cg = g1 + (g2 - g1) * t
        local cb = b1 + (b2 - b1) * t
        parts[#parts + 1] = string.format("|cff%02x%02x%02x%s|r",
            math.floor(cr * 255 + 0.5),
            math.floor(cg * 255 + 0.5),
            math.floor(cb * 255 + 0.5),
            ch)
    end

    return table.concat(parts)
end

-- Build a multi-line ramped string from pre-split lines, joined with explicit "\n".
--
-- `lines` is the array returned by addon.DiscoverTextLines / addon.WrapTextGreedy
-- (entries with a .text field), or a plain array of strings.
--
-- opts.mode:
--   "line"  (default) each line runs the full start->end ramp on its own
--   "block"           one continuous ramp across the whole name, split at the
--                     line breaks -- for A/B comparison against "line"
--
-- Returns nil when any line is secret or unusable, so callers can fall back to a
-- solid color instead of rendering half a gradient.
--
-- Callers should SetWordWrap(false) before applying the result. The breaks are
-- already baked in as "\n", and per-character |cff codes shift sub-pixel kerning by
-- 1-2px (castbarX pitfall #28) -- enough to re-flow a line that sat on the boundary.
function addon.BuildPerLineRampString(lines, r1, g1, b1, r2, g2, b2, opts)
    if type(lines) ~= "table" or #lines == 0 then return nil end
    opts = opts or {}
    local blockMode = (opts.mode == "block")

    local texts, counts, total = {}, {}, 0
    for idx = 1, #lines do
        local entry = lines[idx]
        local text = (type(entry) == "table") and entry.text or entry
        if type(text) ~= "string" or text == "" then return nil end
        if issecretvalue and issecretvalue(text) then return nil end
        texts[idx] = text
        counts[idx] = #utf8Chars(text)
        total = total + counts[idx]
    end
    if total == 0 then return nil end

    if not blockMode then
        local parts = {}
        for idx = 1, #texts do
            parts[idx] = addon.BuildColorRampString(texts[idx], r1, g1, b1, r2, g2, b2)
        end
        return table.concat(parts, "\n")
    end

    -- Block mode: give each line the slice of the global ramp its characters occupy.
    -- BuildColorRampString is linear in character index within a line, and the global
    -- ramp is linear in the same index, so slicing the endpoints reproduces it exactly.
    local denom = math.max(total - 1, 1)
    local function lerp(t)
        return r1 + (r2 - r1) * t, g1 + (g2 - g1) * t, b1 + (b2 - b1) * t
    end

    local parts = {}
    local consumed = 0
    for idx = 1, #texts do
        local n = counts[idx]
        local sr, sg, sb = lerp(consumed / denom)
        local er, eg, eb = lerp((consumed + math.max(n - 1, 0)) / denom)
        parts[idx] = addon.BuildColorRampString(texts[idx], sr, sg, sb, er, eg, eb)
        consumed = consumed + n
    end
    return table.concat(parts, "\n")
end
