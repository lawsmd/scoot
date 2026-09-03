--------------------------------------------------------------------------------
-- catalogs.lua
-- Shared dropdown option catalogs (refactor #27)
-- Every catalog is { values = { key = "Label" }, order = { key, ... } }, the
-- shape every SettingsBuilder selector takes, plus infoIcons where a mode
-- carries a tooltip. The ui/v2 Helpers modules alias these by reference the
-- way they alias addon.FontStyles. Controls hold the tables by reference and
-- only read them, so every catalog is frozen once built; a write anywhere is
-- a shared-table mutation and should raise.
--------------------------------------------------------------------------------

local addonName, addon = ...

addon.Catalogs = addon.Catalogs or {}
local Catalogs = addon.Catalogs

local function make(values, order, infoIcons)
    if infoIcons then
        for _, icon in pairs(infoIcons) do
            table.freeze(icon)
        end
        table.freeze(infoIcons)
    end
    table.freeze(values)
    table.freeze(order)
    local catalog = { values = values, order = order, infoIcons = infoIcons }
    table.freeze(catalog)
    return catalog
end

-- A new catalog with (key, label) placed first, for selectors that put a
-- "Default"-style entry ahead of a shared list.
function Catalogs.WithLeading(base, key, label)
    local values = { [key] = label }
    for k, v in pairs(base.values) do
        values[k] = v
    end
    local order = { key }
    for _, k in ipairs(base.order) do
        order[#order + 1] = k
    end
    return make(values, order)
end

--------------------------------------------------------------------------------
-- Geometry
--------------------------------------------------------------------------------

Catalogs.Anchor9 = make({
    TOPLEFT = "Top-Left", TOP = "Top", TOPRIGHT = "Top-Right",
    LEFT = "Left", CENTER = "Center", RIGHT = "Right",
    BOTTOMLEFT = "Bottom-Left", BOTTOM = "Bottom", BOTTOMRIGHT = "Bottom-Right",
}, {
    "TOPLEFT", "TOP", "TOPRIGHT",
    "LEFT", "CENTER", "RIGHT",
    "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT",
})

-- Anchor9 without CENTER, as its own tables so Anchor8.values.CENTER is nil.
do
    local values, order = {}, {}
    for _, key in ipairs(Catalogs.Anchor9.order) do
        if key ~= "CENTER" then
            values[key] = Catalogs.Anchor9.values[key]
            order[#order + 1] = key
        end
    end
    Catalogs.Anchor8 = make(values, order)
end

Catalogs.Alignment = make(
    { LEFT = "Left", CENTER = "Center", RIGHT = "Right" },
    { "LEFT", "CENTER", "RIGHT" }
)

-- Text alignment relative to the bar or to the unit name (boss text).
Catalogs.AlignmentMode = make(
    { bar = "Within Bar", name = "Around Name" },
    { "bar", "name" }
)

-- Positions relative to a name FontString; the geometry per key lives in
-- core/components/unitframes/text/core.lua.
Catalogs.NameAnchor = make({
    LEFT_OF_NAME = "Left of Name", RIGHT_OF_NAME = "Right of Name",
    TOP_LEFT = "Top-Left", TOP = "Top", TOP_RIGHT = "Top-Right",
    BOTTOM_LEFT = "Bottom-Left", BOTTOM = "Bottom", BOTTOM_RIGHT = "Bottom-Right",
}, {
    "LEFT_OF_NAME", "RIGHT_OF_NAME",
    "TOP_LEFT", "TOP", "TOP_RIGHT",
    "BOTTOM_LEFT", "BOTTOM", "BOTTOM_RIGHT",
})

Catalogs.Orientation = make(
    { H = "Horizontal", V = "Vertical" },
    { "H", "V" }
)

Catalogs.Visibility = make(
    { always = "Always", combat = "Only in Combat", never = "Hidden" },
    { "always", "combat", "never" }
)

--------------------------------------------------------------------------------
-- Color modes. Keys are stored setting values; renderers whose stored keys
-- differ (original, power, gradient, rainbow, spellName) keep their own lists.
--------------------------------------------------------------------------------

local ColorMode = {}
Catalogs.ColorMode = ColorMode

ColorMode.Text = make(
    { default = "Default", class = "Class Color", custom = "Custom" },
    { "default", "class", "custom" }
)

ColorMode.TextHealth = make(
    { default = "Default", class = "Class Color", value = "Color by Value", custom = "Custom" },
    { "default", "class", "value", "custom" }
)

-- Power texts add Class Power Color, and on a Death Knight the spec-color
-- mode ahead of Custom. ReadColorMode/WriteColorMode in core/colors.lua own
-- the two-slot storage that mode implies.
do
    local values = { default = "Default", class = "Class Color", classPower = "Class Power Color", custom = "Custom" }
    local order = { "default", "class", "classPower", "custom" }
    local _, playerClass = UnitClass("player")
    if playerClass == "DEATHKNIGHT" then
        values.dkSpec = "Death Knight Spec"
        table.insert(order, #order, "dkSpec")
    end
    ColorMode.TextPower = make(values, order)
end

ColorMode.Health = make({
    default = "Default",
    texture = "Texture Original",
    class = "Class Color",
    value = "Color by Value",
    valueDark = "Color by Value (Dark)",
    custom = "Custom",
}, { "default", "texture", "class", "value", "valueDark", "custom" }, {
    valueDark = {
        tooltipText = "Dark bar at full health. Below 100%, uses the standard Color by Value color curve.",
    },
})

ColorMode.Background = make(
    { default = "Default", texture = "Texture Original", custom = "Custom" },
    { "default", "texture", "custom" }
)

-- Same keys as Background today; its own tables so power bars can diverge.
ColorMode.Power = make(
    { default = "Default", texture = "Texture Original", custom = "Custom" },
    { "default", "texture", "custom" }
)

ColorMode.CastBar = make(
    { default = "Default", texture = "Texture Original", class = "Class Color", custom = "Custom" },
    { "default", "texture", "class", "custom" }
)

-- Cast bar spell-name text on the player frame, gradient modes included.
ColorMode.CastBarText = make({
    default = "Default",
    class = "Class Color",
    custom = "Custom",
    classGradient = "Class Color (Gradient)",
    specGradient = "Spec Color (Gradient)",
    customGradient = "Custom (Gradient)",
}, { "default", "class", "custom", "classGradient", "specGradient", "customGradient" }, {
    specGradient = {
        tooltipTitle = "Spec Color (Gradient)",
        tooltipText = "Hand-picked gradient colors for each of WoW's 39 specializations. Designed to match each spec's identity while contrasting against its class color. These colors are curated and may be adjusted over time.",
    },
})

-- Non-player cast bars: no class or spec gradient.
ColorMode.CastBarTextNonPlayer = make(
    { default = "Default", class = "Class Color", custom = "Custom", customGradient = "Custom (Gradient)" },
    { "default", "class", "custom", "customGradient" }
)

ColorMode.PortraitBorder = make(
    { texture = "Texture Original", class = "Class Color", custom = "Custom" },
    { "texture", "class", "custom" }
)

ColorMode.DefaultCustom = make(
    { default = "Default", custom = "Custom" },
    { "default", "custom" }
)

ColorMode.ClassCustom = make(
    { class = "Class Color", custom = "Custom" },
    { "class", "custom" }
)

--------------------------------------------------------------------------------
-- Introspection for verification: /run ScootAddon.Catalogs.Dump()
-- One line per catalog part, then one per *Values/*Order/*InfoIcons field on
-- the three ui/v2 Helpers modules, each marked as an alias of a catalog (or
-- of addon.FontStyles) by reference, or LITERAL with its contents.
--------------------------------------------------------------------------------

local function describe(t)
    if #t > 0 then
        return table.concat(t, "|")
    end
    local keys = {}
    for k in pairs(t) do
        keys[#keys + 1] = tostring(k)
    end
    table.sort(keys)
    local parts = {}
    for _, k in ipairs(keys) do
        local v = t[k]
        if type(v) == "table" then
            v = v.tooltipText or v.text or "{...}"
        end
        parts[#parts + 1] = k .. "=" .. tostring(v)
    end
    return table.concat(parts, "|")
end

function Catalogs.Dump()
    local lines, byRef = {}, {}

    local function walk(prefix, node)
        local names = {}
        for name, entry in pairs(node) do
            if type(entry) == "table" then
                names[#names + 1] = name
            end
        end
        table.sort(names)
        for _, name in ipairs(names) do
            local entry = node[name]
            if entry.values and entry.order then
                for _, part in ipairs({ "values", "order", "infoIcons" }) do
                    if entry[part] then
                        local label = prefix .. name .. "." .. part
                        byRef[entry[part]] = label
                        lines[#lines + 1] = label .. ": " .. describe(entry[part])
                    end
                end
            else
                walk(prefix .. name .. ".", entry)
            end
        end
    end
    walk("Catalogs.", Catalogs)

    local FontStyles = addon.FontStyles
    if FontStyles then
        for _, part in ipairs({ "values", "order", "orderPaired", "orderOutlineFirst", "orderOutlineFirstPaired" }) do
            if FontStyles[part] then
                byRef[FontStyles[part]] = "FontStyles." .. part
            end
        end
    end

    local UI = addon.UI or {}
    local modules = {
        { "Helpers", UI.Settings and UI.Settings.Helpers },
        { "UF", UI.UnitFrames },
        { "GF", UI.GroupFrames },
    }
    for _, entry in ipairs(modules) do
        local modName, mod = entry[1], entry[2]
        if mod then
            local names = {}
            for k, v in pairs(mod) do
                if type(k) == "string" and type(v) == "table"
                    and (k:find("Values$") or k:find("Order$") or k:find("InfoIcons$")) then
                    names[#names + 1] = k
                end
            end
            table.sort(names)
            for _, k in ipairs(names) do
                local ref = byRef[mod[k]]
                lines[#lines + 1] = modName .. "." .. k .. ": "
                    .. (ref and ("= " .. ref) or ("LITERAL " .. describe(mod[k])))
            end
        end
    end

    if addon.DebugShowWindow then
        addon.DebugShowWindow(("Catalogs (%d)"):format(#lines), lines)
    end
    return lines
end
