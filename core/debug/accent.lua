-- accent.lua -- The accent color and the Theme subscriber roster.
--
-- Every piece of chrome that repaints on an accent change holds one key in
-- Theme._subscribers. Keys minted per frame (UISection_, Button_, Scrollbar_)
-- have to be released when their frame is torn down, so the roster is the only
-- place a missed release shows: open the settings panel, run this, navigate ten
-- pages, run it again. The counts must match.
-- Usage: /scoot debug accent
local addonName, addon = ...

-- Keys are named <family>_<frame> or a bare singleton name. Bucket on the first
-- underscore so a family that grows across navigations is one row, not thirty.
local function familyOf(key)
    local head = key:match("^([^_]+)_")
    return head and (head .. "_") or key
end

local function DebugAccent()
    local theme = addon.UI and addon.UI.Theme
    local lines, push = addon.DebugLines()

    if not theme then
        push("ui/v2/Theme.lua has not loaded.")
        addon.DebugShowWindow("Accent color", lines)
        return
    end

    local r, g, b = theme:GetAccentColor()
    local mode = theme.GetAccentColorMode and theme:GetAccentColorMode() or "?"
    push("Mode:   %s", tostring(mode))
    push("Accent: %.3f %.3f %.3f   #%s", r or 0, g or 0, b or 0, addon.GetAccentHex())
    push("")

    local subs = theme._subscribers or {}
    local keys, families = {}, {}
    for key in pairs(subs) do
        keys[#keys + 1] = key
        local fam = familyOf(key)
        families[fam] = (families[fam] or 0) + 1
    end
    table.sort(keys)

    local famNames = {}
    for fam in pairs(families) do famNames[#famNames + 1] = fam end
    table.sort(famNames, function(x, y)
        if families[x] ~= families[y] then return families[x] > families[y] end
        return x < y
    end)

    push("Subscribers: %d in %d famil%s", #keys, #famNames, #famNames == 1 and "y" or "ies")
    push("")
    for _, fam in ipairs(famNames) do
        push("%5d  %s", families[fam], fam)
    end

    push("")
    push(string.rep("-", 64))
    for _, key in ipairs(keys) do
        push(key)
    end

    addon.DebugShowWindow("Accent color", lines)
end

addon:RegisterDebugCommand({
    name = "accent", help = "accent color and the Theme subscriber roster",
    handler = function() DebugAccent() end,
})
