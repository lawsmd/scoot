-- fontpair.lua -- Diagnostic dump of Deep Shadow pairs: where the black copy
-- actually landed relative to the string it mirrors.
--
-- Draw order is the whole job of core/fontpair.lua and it is not readable from
-- a screenshot once the copy is fat enough to bury the original, so read it
-- back from the engine instead. "Copy layer" must sort BELOW "Real layer".
-- Usage: /scoot debug fontpair
local addonName, addon = ...

local LAYER_RANK = {
    BACKGROUND = 1,
    BORDER = 2,
    ARTWORK = 3,
    OVERLAY = 4,
    HIGHLIGHT = 5,
}

local function drawLayerOf(region)
    if not region or not region.GetDrawLayer then return "?", "?" end
    local ok, layer, sublevel = pcall(region.GetDrawLayer, region)
    if not ok then return "<restricted>", "?" end
    return tostring(layer), tostring(sublevel)
end

-- IsShown and GetAlpha return secret values on a string an engine binding has
-- claimed, and tostring on a secret raises, so name the secret instead.
local function boolOf(region, method)
    if not region or not region[method] then return "?" end
    local ok, value = pcall(region[method], region)
    if not ok then return "<restricted>" end
    if type(issecretvalue) == "function" and issecretvalue(value) then return "secret" end
    return tostring(value)
end

-- The taper the copy is running at (core/fontpair.lua copyAlphaFor). A copy
-- alpha still at 0.80 while the drawn alpha is below 1 means a fade path is not
-- calling RefreshInheritedAlpha, unless the text is white, where 0.80 is right
-- at every alpha.
local function taperOf(fs, companion)
    local lum, drawn, copyAlpha = "?", "?", "?"
    if fs and fs.GetTextColor then
        local ok, r, g, b = pcall(fs.GetTextColor, fs)
        if ok and type(r) == "number" and type(g) == "number" and type(b) == "number" then
            lum = string.format("%.2f", 0.2126 * r + 0.7152 * g + 0.0722 * b)
        end
    end
    local okP, parent = pcall(fs.GetParent, fs)
    if okP and parent and parent.GetEffectiveAlpha then
        local okA, a = pcall(parent.GetEffectiveAlpha, parent)
        if okA and type(a) == "number" then drawn = string.format("%.2f", a) end
    end
    if companion and companion.GetTextColor then
        local ok, _, _, _, a = pcall(companion.GetTextColor, companion)
        if ok and type(a) == "number" then copyAlpha = string.format("%.2f", a) end
    end
    return lum, drawn, copyAlpha
end

-- Every damage meter row, name clip and column cell is an anonymous frame, so
-- the immediate parent prints as a table address and no two pairs can be told
-- apart. Walk up to the first named ancestor and say how many hops that took.
local function parentNameOf(region)
    if not region or not region.GetParent then return "?" end
    local ok, parent = pcall(region.GetParent, region)
    if not ok or not parent then return "?" end
    local node, hops = parent, 0
    while node and hops < 6 do
        local okName, name = pcall(node.GetName, node)
        if okName and name then
            if hops == 0 then return name end
            return string.format("%s (+%d)", name, hops)
        end
        local okUp, up = pcall(node.GetParent, node)
        if not okUp then break end
        node = up
        hops = hops + 1
    end
    return tostring(parent):gsub("table: ", "")
end

-- The text is often secret, so report only whether it reads, never the value.
-- Pass strip for the real string: the copy is fed through StripEscapes, so a
-- name carrying a color escape is shorter in the copy by construction and the
-- two lengths would never line up.
local function textStateOf(region, strip)
    if not region or not region.GetText then return "?" end
    local ok, text = pcall(region.GetText, region)
    if not ok then return "<throws>" end
    if text == nil then return "nil" end
    if type(issecretvalue) == "function" and issecretvalue(text) then return "secret" end
    if text == "" then return "empty" end
    local s = tostring(text)
    if strip and addon.FontPair and addon.FontPair.StripEscapes then
        local okStrip, stripped = pcall(addon.FontPair.StripEscapes, s)
        if okStrip then s = stripped end
    end
    if s == "" then return "empty" end
    return string.format("plain (%d chars)", #s)
end

-- The real string and its copy must hold the same text. The copy is box-anchored
-- to the real string's rect, so one left holding an older value is drawn clipped
-- or ellipsized inside that rect: a smear rather than a shadow. Two secrets
-- cannot be compared, so that pair reports as unverifiable instead of OK.
local BLANK_STATE = { ["nil"] = true, ["empty"] = true }

local function syncOf(realState, copyState)
    if realState == "secret" and copyState == "secret" then
        return "secret on both, contents not comparable", false
    end
    if BLANK_STATE[realState] and BLANK_STATE[copyState] then
        return "OK, both blank", false
    end
    if realState == copyState then return "OK", false end
    return string.format("DESYNC -- real %s, copy %s", realState, copyState), true
end

local function DebugFontPair()
    local registry = addon.FontPair and addon.FontPair.registry
    local lines = {}

    table.insert(lines, "Deep Shadow pairs -- core/fontpair.lua")
    table.insert(lines, string.rep("=", 64))
    table.insert(lines, "The copy must sort BELOW the real string. Layer beats sublevel:")
    table.insert(lines, "BACKGROUND < BORDER < ARTWORK < OVERLAY < HIGHLIGHT.")
    table.insert(lines, "Copy alpha tapers with text luminance and drawn alpha: dark text")
    table.insert(lines, "at reduced opacity gets a lighter copy, white text never tapers.")
    table.insert(lines, "Sync compares the two text states. A DESYNC means the copy kept an")
    table.insert(lines, "older value, which draws as a smear inside the real string's box.")
    table.insert(lines, "")

    if not registry then
        table.insert(lines, "No registry -- core/fontpair.lua did not load.")
        addon.DebugShowWindow("Deep Shadow pairs", lines)
        return
    end

    local count, wrong, desynced = 0, 0, 0
    for fs, companion in pairs(registry) do
        count = count + 1
        local realLayer, realSub = drawLayerOf(fs)
        local copyLayer, copySub = drawLayerOf(companion)
        local realText, copyText = textStateOf(fs, true), textStateOf(companion)

        local verdict
        local realRank, copyRank = LAYER_RANK[realLayer], LAYER_RANK[copyLayer]
        if not realRank or not copyRank then
            verdict = "UNKNOWN (layer did not read)"
        elseif copyRank < realRank then
            verdict = "OK -- copy is behind"
        elseif copyRank > realRank then
            verdict = "WRONG -- copy is in front"
            wrong = wrong + 1
        else
            verdict = "SAME LAYER -- sublevel decides, and it does not sort two strings"
            wrong = wrong + 1
        end

        -- An inactive pair has been blanked on purpose by FontPair.Hide, so its
        -- copy is empty while the real string still reads. Not a desync.
        local active = fs.__scootPairActive and true or false
        local sync, isDesync = syncOf(realText, copyText)
        if not active then
            sync = "n/a, pair inactive"
        elseif isDesync then
            desynced = desynced + 1
        end

        table.insert(lines, string.format("[%d] parent: %s", count, parentNameOf(fs)))
        table.insert(lines, string.format("    Real layer: %s %s   shown=%s alpha=%s text=%s",
            realLayer, realSub, boolOf(fs, "IsShown"), boolOf(fs, "GetAlpha"), realText))
        table.insert(lines, string.format("    Copy layer: %s %s   shown=%s alpha=%s text=%s",
            copyLayer, copySub, boolOf(companion, "IsShown"), boolOf(companion, "GetAlpha"),
            copyText))
        local lum, drawn, copyAlpha = taperOf(fs, companion)
        table.insert(lines, string.format("    Taper: text luminance %s   drawn alpha %s   copy alpha %s",
            lum, drawn, copyAlpha))
        table.insert(lines, string.format("    Sync: %s", sync))
        table.insert(lines, string.format("    Active: %s   %s",
            tostring(active), verdict))
        table.insert(lines, "")
    end

    if count == 0 then
        table.insert(lines, "No pairs built. Nothing is set to a Deep Shadow style,")
        table.insert(lines, "or the strings using one have not been styled yet.")
    else
        table.insert(lines, string.rep("-", 64))
        table.insert(lines, string.format("%d pair(s), %d misordered, %d desynced.",
            count, wrong, desynced))
    end

    addon.DebugShowWindow("Deep Shadow pairs", lines)
end

addon:RegisterDebugCommand({
    name = "fontpair", help = "Deep Shadow copy draw order and text sync",
    handler = function() DebugFontPair() end,
})
