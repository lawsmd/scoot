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

local function parentNameOf(region)
    if not region or not region.GetParent then return "?" end
    local ok, parent = pcall(region.GetParent, region)
    if not ok or not parent then return "?" end
    local okName, name = pcall(parent.GetName, parent)
    if okName and name then return name end
    return tostring(parent):gsub("table: ", "")
end

-- The text is often secret, so report only whether it reads, never the value.
local function textStateOf(region)
    if not region or not region.GetText then return "?" end
    local ok, text = pcall(region.GetText, region)
    if not ok then return "<throws>" end
    if text == nil then return "nil" end
    if type(issecretvalue) == "function" and issecretvalue(text) then return "secret" end
    if text == "" then return "empty" end
    return string.format("plain (%d chars)", #tostring(text))
end

function addon.DebugFontPair()
    local registry = addon.FontPair and addon.FontPair.registry
    local lines = {}

    table.insert(lines, "Deep Shadow pairs -- core/fontpair.lua")
    table.insert(lines, string.rep("=", 64))
    table.insert(lines, "The copy must sort BELOW the real string. Layer beats sublevel:")
    table.insert(lines, "BACKGROUND < BORDER < ARTWORK < OVERLAY < HIGHLIGHT.")
    table.insert(lines, "Copy alpha tapers with text luminance and drawn alpha: dark text")
    table.insert(lines, "at reduced opacity gets a lighter copy, white text never tapers.")
    table.insert(lines, "")

    if not registry then
        table.insert(lines, "No registry -- core/fontpair.lua did not load.")
        addon.DebugShowWindow("Deep Shadow pairs", table.concat(lines, "\n"))
        return
    end

    local count, wrong = 0, 0
    for fs, companion in pairs(registry) do
        count = count + 1
        local realLayer, realSub = drawLayerOf(fs)
        local copyLayer, copySub = drawLayerOf(companion)

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

        table.insert(lines, string.format("[%d] parent: %s", count, parentNameOf(fs)))
        table.insert(lines, string.format("    Real layer: %s %s   shown=%s alpha=%s text=%s",
            realLayer, realSub, boolOf(fs, "IsShown"), boolOf(fs, "GetAlpha"), textStateOf(fs)))
        table.insert(lines, string.format("    Copy layer: %s %s   shown=%s alpha=%s text=%s",
            copyLayer, copySub, boolOf(companion, "IsShown"), boolOf(companion, "GetAlpha"),
            textStateOf(companion)))
        local lum, drawn, copyAlpha = taperOf(fs, companion)
        table.insert(lines, string.format("    Taper: text luminance %s   drawn alpha %s   copy alpha %s",
            lum, drawn, copyAlpha))
        table.insert(lines, string.format("    Active: %s   %s",
            tostring(fs.__scootPairActive and true or false), verdict))
        table.insert(lines, "")
    end

    if count == 0 then
        table.insert(lines, "No pairs built. Nothing is set to a Deep Shadow style,")
        table.insert(lines, "or the strings using one have not been styled yet.")
    else
        table.insert(lines, string.rep("-", 64))
        table.insert(lines, string.format("%d pair(s), %d misordered.", count, wrong))
    end

    addon.DebugShowWindow("Deep Shadow pairs", table.concat(lines, "\n"))
end

addon:RegisterDebugCommand({
    name = "fontpair", help = "Deep Shadow copy draw order",
    handler = function() addon.DebugFontPair() end,
})
