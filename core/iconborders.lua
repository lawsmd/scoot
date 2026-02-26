local addonName, addon = ...

addon.IconBorders = addon.IconBorders or {}
local IconBorders = addon.IconBorders

local function isAddonLoaded(name)
    if not name then return false end
    if C_AddOns and C_AddOns.IsAddOnLoaded then
        local loaded = C_AddOns.IsAddOnLoaded(name)
        if type(loaded) == "boolean" then
            return loaded
        end
    elseif IsAddOnLoaded then
        local loaded = IsAddOnLoaded(name)
        if type(loaded) == "boolean" then
            return loaded
        end
    end
    return false
end

local ICON_BORDER_DEFINITIONS = {
    -- Scoot defaults
    { key = "square", label = "Square", type = "square", order = 10, defaultColor = {0, 0, 0, 1} },

    -- Blizzard atlas selections (always available)
    { key = "blizzard", label = "Blizzard Default", type = "atlas", atlas = "UI-HUD-ActionBar-IconFrame", order = 100, expandX = 0, expandY = 0, defaultColor = {1, 1, 1, 1}, allowThicknessInset = true, insetStep = 0.2, insetCenter = 8, defaultThickness = 8, adjustLeft = 1, adjustRight = 3, adjustTop = 1, adjustBottom = 2 },
    { key = "cooldownOverlay", label = "Cooldown Manager Overlay", type = "atlas", atlas = "UI-HUD-CoolDownManager-IconOverlay", order = 110, expandX = 8, expandY = 8, defaultColor = {1, 1, 1, 1}, allowThicknessInset = true, insetStep = 0.2, insetCenter = 8, defaultThickness = 8 },
    { key = "bagsGlow", label = "Bags Glow", type = "atlas", atlas = "bags-glow-white", order = 120, expandX = 2, expandY = 2, defaultColor = {1, 1, 1, 1}, allowThicknessInset = true, insetStep = 0.2, insetCenter = 8, defaultThickness = 8 },
    { key = "gearEnchant", label = "Gear Enchant", type = "atlas", atlas = "GearEnchant_IconBorder", order = 130, expandX = 1.5, expandY = 1.5, defaultColor = {1, 1, 1, 1}, allowThicknessInset = true, insetStep = 0.2, insetCenter = 8, defaultThickness = 8 },
    { key = "talentsGray", label = "Talents Gray", type = "atlas", atlas = "talents-node-choiceflyout-square-gray", order = 140, expandX = 1.5, expandY = 1.5, defaultColor = {1, 1, 1, 1}, allowThicknessInset = true, insetStep = 0.2, insetCenter = 8, defaultThickness = 8 },
    { key = "spellbook", label = "Spellbook Glow", type = "atlas", atlas = "spellbook-item-unassigned-glow", order = 150, expandX = 1.5, expandY = 1.5, defaultColor = {1, 1, 1, 1}, allowThicknessInset = true, insetStep = 0.2, insetCenter = 8, defaultThickness = 8 },
    { key = "professions", label = "Professions Frame", type = "atlas", atlas = "Professions-ChoiceReagent-Frame", order = 160, expandX = 1.5, expandY = 1.5, defaultColor = {1, 1, 1, 1}, allowThicknessInset = true, insetStep = 0.2, insetCenter = 8, defaultThickness = 8 },
    { key = "azerite", label = "Azerite", type = "atlas", atlas = "AzeriteIconFrame", order = 170, expandX = 1.5, expandY = 1.5, defaultColor = {1, 1, 1, 1}, allowThicknessInset = true, insetStep = 0.2, insetCenter = 8, defaultThickness = 8 },
    { key = "wowlabs", label = "Wowlabs Ability", type = "atlas", atlas = "wowlabs-ability-icon-frame", order = 180, expandX = 2.5, expandY = 2.5, defaultColor = {1, 1, 1, 1}, allowThicknessInset = true, insetStep = 0.2, insetCenter = 8, defaultThickness = 8 },
    { key = "plunderstorm", label = "Plunderstorm", type = "atlas", atlas = "plunderstorm-actionbar-slot-border", order = 190, expandX = 4, expandY = 4, defaultColor = {1, 1, 1, 1}, allowThicknessInset = true, insetStep = 0.2, insetCenter = 8, defaultThickness = 8 },

}

-- Always apply borders through addon.ApplyIconBorderStyle, not addon.Borders.Apply* directly.
-- ApplyIconBorderStyle clears existing border attachments before applying new styles,
-- preventing stuck overlays when swapping between border types.

local STYLE_MAP = {}
for _, def in ipairs(ICON_BORDER_DEFINITIONS) do
    STYLE_MAP[def.key] = def
end

local aliasMap = {
    ["style_tooltip"] = "cooldownOverlay",
    ["dialog"] = "blizzard",
    ["atlas:UI-HUD-CoolDownManager-IconOverlay"] = "cooldownOverlay",
    ["atlas:UI-HUD-ActionBar-IconFrame"] = "blizzard",
    ["square_default"] = "square",
    ["none"] = "square",
}

local function resolveStyleKey(key)
    if not key or key == "" then
        return "square"
    end
    if STYLE_MAP[key] then
        return key
    end
    if aliasMap[key] then
        return aliasMap[key]
    end
    -- Legacy atlas:<name> support
    if type(key) == "string" then
        local atlas = key:match("^atlas:(.+)")
        if atlas and atlas ~= "" then
            local alias = "atlas_" .. atlas
            if not STYLE_MAP[alias] then
                STYLE_MAP[alias] = {
                    key = alias,
                    label = atlas,
                    type = "atlas",
                    atlas = atlas,
                    order = 500,
                    expandX = 0,
                    expandY = 0,
                    defaultColor = {1, 1, 1, 1},
                }
            end
            return alias
        end
    end
    return key
end

function IconBorders.GetStyle(key)
    local resolved = resolveStyleKey(key)
    return STYLE_MAP[resolved]
end

function IconBorders.GetDropdownEntries()
    local entries = {}
    for _, def in ipairs(ICON_BORDER_DEFINITIONS) do
        if not def.requiresAddon or isAddonLoaded(def.requiresAddon) then
            entries[#entries + 1] = { value = def.key, text = def.label, order = def.order or 500 }
        end
    end

    table.sort(entries, function(a, b)
        local oa = a.order or 500
        local ob = b.order or 500
        if oa == ob then
            return (a.text or "") < (b.text or "")
        end
        return oa < ob
    end)

    if Settings and Settings.CreateControlTextContainer then
        local container = Settings.CreateControlTextContainer()
        for _, entry in ipairs(entries) do
            container:Add(entry.value, entry.text)
        end
        return container:GetData()
    end

    return entries
end
