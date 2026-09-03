-- Helpers.lua - Shared helpers for Settings Panel TUI renderers
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.Settings = addon.UI.Settings or {}
local Settings = addon.UI.Settings

-- Make Helpers available as a sub-table
Settings.Helpers = {}
local Helpers = Settings.Helpers

--------------------------------------------------------------------------------
-- Component Database Access
--------------------------------------------------------------------------------

-- Get a component by ID
function Helpers.getComponent(componentId)
    return addon.Components and addon.Components[componentId]
end

-- Get a setting from a component's database (canonical resolution lives in
-- addon.GetComponentSetting, base/core.lua)
function Helpers.getSetting(componentId, key)
    return addon.GetComponentSetting(componentId, key)
end

-- Set a setting in a component's database
function Helpers.setSetting(componentId, key, value)
    local comp = Helpers.getComponent(componentId)
    if comp and comp.db then
        if addon.EnsureComponentDB then
            addon:EnsureComponentDB(comp)
        end
        comp.db[key] = value
    else
        -- Fallback to profile.components
        local profile = addon.db and addon.db.profile
        if profile then
            local comp = addon.Components and addon.Components[componentId]
            if comp and addon.EnsureComponentDB then
                local db = addon:EnsureComponentDB(comp)
                if db then
                    db[key] = value
                end
            end
        end
    end
end

-- Set a setting and apply styles afterward
function Helpers.setSettingAndApply(componentId, key, value)
    Helpers.setSetting(componentId, key, value)
    Helpers.applyStyles()
end

--------------------------------------------------------------------------------
-- Apply Functions
--------------------------------------------------------------------------------

function Helpers.applyStyles()
    if addon and addon.ApplyStyles then
        C_Timer.After(0, function()
            if addon and addon.ApplyStyles then
                addon:ApplyStyles()
            end
        end)
    end
end

--------------------------------------------------------------------------------
-- Edit Mode Integration
--------------------------------------------------------------------------------

-- Sync a component setting to Edit Mode (debounced)
function Helpers.syncEditModeSetting(componentId, settingId)
    local comp = Helpers.getComponent(componentId)
    if comp and addon.EditMode and addon.EditMode.SyncComponentSettingToEditMode then
        addon.EditMode.SyncComponentSettingToEditMode(comp, settingId, { skipApply = true })
    end
end

--------------------------------------------------------------------------------
-- Component Helper Factory
--------------------------------------------------------------------------------
-- Creates a set of helper functions bound to a specific componentId.
-- Usage:
--   local helpers = Helpers.CreateComponentHelpers("actionBar1")
--   local value = helpers.get("iconSize")
--   helpers.set("iconSize", 100)
--   helpers.sync("iconSize")
--------------------------------------------------------------------------------

function Helpers.CreateComponentHelpers(componentId)
    local h = {}

    h.getComponent = function()
        return Helpers.getComponent(componentId)
    end

    h.get = function(key)
        return Helpers.getSetting(componentId, key)
    end

    h.set = function(key, value)
        Helpers.setSetting(componentId, key, value)
    end

    h.setAndApply = function(key, value)
        Helpers.setSettingAndApply(componentId, key, value)
    end

    h.setAndApplyComponent = function(key, value)
        Helpers.setSetting(componentId, key, value)
        local comp = Helpers.getComponent(componentId)
        if comp and comp.ApplyStyling then
            C_Timer.After(0, function()
                if comp and comp.ApplyStyling then
                    comp:ApplyStyling()
                end
            end)
        end
    end

    h.sync = function(settingId)
        Helpers.syncEditModeSetting(componentId, settingId)
    end

    -- Nested table helpers (e.g., for textStacks, textCooldown sub-tables)
    h.getSubSetting = function(tableKey, key, default)
        local t = Helpers.getSetting(componentId, tableKey)
        if t and t[key] ~= nil then return t[key] end
        return default
    end

    -- Writes go through EnsureComponentSubTable, which seeds the group from a
    -- COPY of its registered default. Seeding matters: the old
    -- `comp.db[tableKey] = comp.db[tableKey] or {}` idiom wrote a bare table on
    -- a fresh profile, so editing one property (say font size) silently dropped
    -- every sibling -- including fontFace, which then rendered as Friz Quadrata
    -- while the panel still displayed the real default.
    h.setSubSetting = function(tableKey, key, value)
        local comp = Helpers.getComponent(componentId)
        if comp then
            local t = addon:EnsureComponentSubTable(comp, tableKey)
            if t then t[key] = value end
        end
        Helpers.applyStyles()
    end

    return h
end

--------------------------------------------------------------------------------
-- Sub-table Helper Factory
--------------------------------------------------------------------------------
-- Curries one component sub-table (textStacks, textCooldown, ...) into the
-- get/set field pair that SettingsBuilder:AddTextStyleBlock consumes. Reads
-- never materialize; writes route through EnsureComponentSubTable (see
-- setSubSetting above for why seeding from the registered default matters).
-- The offsetX/offsetY fields map to x/y of the nested offset table.
-- Usage:
--   local s = Helpers.CreateSubTableHelpers("utilityCooldowns", "textStacks",
--       { apply = applyText })
--   s.get("size")                -- nil if unset (caller supplies the default)
--   s.set("size", 16)            -- no apply
--   s.setAndApply("enabled", v)  -- set + opts.apply (default Helpers.applyStyles)
--------------------------------------------------------------------------------

function Helpers.CreateSubTableHelpers(componentId, subKey, opts)
    opts = opts or {}
    local apply = opts.apply or Helpers.applyStyles
    local s = {}

    s.getTable = function()
        return Helpers.getSetting(componentId, subKey)
    end

    s.ensure = function()
        local comp = Helpers.getComponent(componentId)
        if not comp then return nil end
        return addon:EnsureComponentSubTable(comp, subKey)
    end

    s.get = function(field)
        local t = s.getTable()
        if not t then return nil end
        if field == "offsetX" or field == "offsetY" then
            local o = t.offset
            if type(o) ~= "table" then return nil end
            return o[field == "offsetX" and "x" or "y"]
        end
        return t[field]
    end

    s.set = function(field, value)
        local t = s.ensure()
        if not t then return end
        if field == "offsetX" or field == "offsetY" then
            if type(t.offset) ~= "table" then t.offset = {} end
            t.offset[field == "offsetX" and "x" or "y"] = value
        else
            t[field] = value
        end
    end

    s.setAndApply = function(field, value)
        s.set(field, value)
        apply()
    end

    s.apply = apply
    return s
end

--------------------------------------------------------------------------------
-- Common Dropdown/Selector Options
--------------------------------------------------------------------------------

-- Font style options. The catalog in core/fonts.lua is the source of truth;
-- the *Paired orders add the Deep Shadow keys and are used only by dropdowns
-- whose every targeted FontString is Scoot-created with Scoot-fed text.
Helpers.fontStyleValues = addon.FontStyles.values
Helpers.fontStyleOrder = addon.FontStyles.order
Helpers.fontStyleOrderPaired = addon.FontStyles.orderPaired
Helpers.fontStyleOrderOutlineFirst = addon.FontStyles.orderOutlineFirst
Helpers.fontStyleOrderOutlineFirstPaired = addon.FontStyles.orderOutlineFirstPaired


-- Text color mode options
Helpers.textColorValues = {
    default = "Default",
    class = "Class Color",
    custom = "Custom",
}
Helpers.textColorOrder = { "default", "class", "custom" }

-- Text color mode options for health value/percentage text (adds "Color by Value")
Helpers.textColorHealthValues = {
    default = "Default",
    class = "Class Color",
    value = "Color by Value",
    custom = "Custom",
}
Helpers.textColorHealthOrder = { "default", "class", "value", "custom" }

-- Text color mode options with class power color
Helpers.textColorPowerValues = {
    default = "Default",
    class = "Class Color",
    classPower = "Class Power Color",
    custom = "Custom",
}
Helpers.textColorPowerOrder = { "default", "class", "classPower", "custom" }

do
    local _, playerClass = UnitClass("player")
    if playerClass == "DEATHKNIGHT" then
        Helpers.textColorPowerValues.dkSpec = "Death Knight Spec"
        table.insert(Helpers.textColorPowerOrder, #Helpers.textColorPowerOrder, "dkSpec")
    end
end

-- Visibility mode options
Helpers.visibilityValues = {
    show = "Always Show",
    hide = "Always Hide",
    combat = "Show In Combat",
    nocombat = "Hide In Combat",
}
Helpers.visibilityOrder = { "show", "hide", "combat", "nocombat" }

-- Text alignment options
Helpers.alignmentValues = {
    LEFT = "Left",
    CENTER = "Center",
    RIGHT = "Right",
}
Helpers.alignmentOrder = { "LEFT", "CENTER", "RIGHT" }

-- Nine-point anchor options
Helpers.anchorValues = {
    TOPLEFT = "Top-Left", TOP = "Top-Center", TOPRIGHT = "Top-Right",
    LEFT = "Left", CENTER = "Center", RIGHT = "Right",
    BOTTOMLEFT = "Bottom-Left", BOTTOM = "Bottom-Center", BOTTOMRIGHT = "Bottom-Right",
}
Helpers.anchorOrder = {
    "TOPLEFT", "TOP", "TOPRIGHT",
    "LEFT", "CENTER", "RIGHT",
    "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT",
}

--------------------------------------------------------------------------------
-- Icon Border & Backdrop Options Builders
--------------------------------------------------------------------------------

-- Build icon border options for selector (returns values and order)
-- prefixEntries: optional array of {key, label} pairs to prepend before dynamic entries
-- e.g. Helpers.getIconBorderOptions({{"off","Off"},{"hidden","Hidden"}})
function Helpers.getIconBorderOptions(prefixEntries)
    local values = {}
    local order = {}
    if prefixEntries then
        for _, entry in ipairs(prefixEntries) do
            values[entry[1]] = entry[2]
            table.insert(order, entry[1])
        end
    end
    values["square"] = "Default (Square)"
    table.insert(order, "square")

    if addon.IconBorders and addon.IconBorders.GetDropdownEntries then
        local data = addon.IconBorders.GetDropdownEntries()
        if data and #data > 0 then
            values = {}
            order = {}
            if prefixEntries then
                for _, entry in ipairs(prefixEntries) do
                    values[entry[1]] = entry[2]
                    table.insert(order, entry[1])
                end
            end
            for _, entry in ipairs(data) do
                local key = entry.value or entry.key
                local label = entry.text or entry.label or key
                if key then
                    values[key] = label
                    table.insert(order, key)
                end
            end
        end
    end
    return values, order
end

-- Build backdrop options for selector (returns values and order)
function Helpers.getBackdropOptions()
    local values = { blizzardBg = "Default Blizzard Backdrop" }
    local order = { "blizzardBg" }
    if addon.BuildIconBackdropOptionsContainer then
        local data = addon.BuildIconBackdropOptionsContainer()
        if data and #data > 0 then
            values = {}
            order = {}
            for _, entry in ipairs(data) do
                local key = entry.value or entry.key
                local label = entry.text or entry.label or key
                if key then
                    values[key] = label
                    table.insert(order, key)
                end
            end
        end
    end
    return values, order
end

-- Build bar border options from addon
function Helpers.getBarBorderOptions()
    local values = { none = "None" }
    local order = { "none" }

    if addon and addon.BuildBarBorderOptionsContainer then
        local base = addon.BuildBarBorderOptionsContainer()
        if type(base) == "table" then
            for _, entry in ipairs(base) do
                if entry and entry.value and entry.text then
                    values[entry.value] = entry.text
                    table.insert(order, entry.value)
                end
            end
        end
    else
        -- Fallback
        values.square = "Default (Square)"
        table.insert(order, "square")
    end

    return values, order
end

--------------------------------------------------------------------------------
-- Info Icon Tooltip Definitions
--------------------------------------------------------------------------------

Helpers.TOOLTIPS = {
    -- Common tooltips that may be shared across multiple renderers
    editModeScale = {
        title = "Edit Mode Scale",
        text = "This is Blizzard's Edit Mode scale setting (max 200%). If you need larger frames, use the Scale Multiplier below.",
    },
    scaleMult = {
        title = "Addon Scale Multiplier",
        text = "This addon-only multiplier layers on top of Edit Mode's scale. Use this for larger UI needs.",
    },
}

--------------------------------------------------------------------------------
-- Druid per-form text visibility fly-out (Personal Resource Display text tabs)
--------------------------------------------------------------------------------
-- Adds a small "Druid Forms" button beside an existing toggle row and a fly-out of
-- per-form toggles. Storage is per-spec: setting[specIndex][formID] = false to hide.
-- Only rendered for Druids. Options:
--   toggleKey  : builder key of the toggle row the button attaches to
--   settingKey : component setting holding the per-spec form table
--   getSetting / setSetting : component helpers (Helpers.CreateComponentHelpers)
function Helpers.AddDruidFormsFlyout(builder, options)
    local _, playerClass = UnitClass("player")
    if playerClass ~= "DRUID" then return end
    if not builder or not options then return end
    local Controls = addon.UI and addon.UI.Controls
    if not Controls then return end

    local showToggle = builder:GetControl(options.toggleKey)
    if not (showToggle and showToggle._label) then return end
    local getSetting, setSetting, settingKey = options.getSetting, options.setSetting, options.settingKey

    local druidBtn = Controls:CreateButton({
        parent = showToggle,
        text = "Druid Forms",
        height = 20,
        fontSize = 10,
        borderWidth = 1,
        borderAlpha = 0.35,
    })
    druidBtn._label:SetTextColor(0.6, 0.6, 0.6, 1)
    druidBtn:SetWidth(druidBtn._label:GetStringWidth() + 16)
    druidBtn:SetPoint("LEFT", showToggle._label, "RIGHT", 8, 0)
    druidBtn:SetFrameLevel(showToggle:GetFrameLevel() + 5)

    local flyout = Controls:CreateFlyout({
        anchor = druidBtn,
        direction = "DOWN",
        width = 260,
        height = 160,
        padding = 10,
        gap = 4,
    })

    local content = flyout:GetContent()
    local forms = {
        { id = 0,  label = "Base / Flight Form" },
        { id = 1,  label = "Cat Form" },
        { id = 5,  label = "Bear Form" },
        { id = 31, label = "Moonkin Form" },
    }

    local yOff = 0
    for _, form in ipairs(forms) do
        local formToggle = Controls:CreateToggle({
            parent = content,
            label = form.label,
            get = function()
                local tbl = getSetting(settingKey) or {}
                local specIndex = GetSpecialization and GetSpecialization() or 1
                local specTbl = tbl[specIndex] or {}
                return specTbl[form.id] ~= false
            end,
            set = function(v)
                local tbl = getSetting(settingKey) or {}
                local specIndex = GetSpecialization and GetSpecialization() or 1
                if not tbl[specIndex] then tbl[specIndex] = {} end
                if v then
                    tbl[specIndex][form.id] = nil
                else
                    tbl[specIndex][form.id] = false
                end
                setSetting(settingKey, tbl)
            end,
        })
        if formToggle then
            formToggle:SetPoint("TOPLEFT", content, "TOPLEFT", 0, yOff)
            formToggle:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, yOff)
            yOff = yOff - formToggle:GetHeight()
        end
    end

    druidBtn:SetScript("OnClick", function()
        flyout:Toggle()
    end)

    table.insert(builder._controls, druidBtn)
    table.insert(builder._controls, flyout)
end

--------------------------------------------------------------------------------
-- Return module
--------------------------------------------------------------------------------

return Settings.Helpers
