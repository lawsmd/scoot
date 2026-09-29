--------------------------------------------------------------------------------
-- forever/unitframes/page.lua
-- The five Classic unit frame settings pages, one renderer over the frame key.
--
-- Laid out after Unit Frames X's pages (ui/v2/unitframes/UFSections.lua), so
-- a setting both have sits in the same section under the same label. Loads on
-- retail too, where no frame is built: the controls still draw and write, and
-- a stored value can be checked across a reload there while the beta keeps
-- none. UF.RefreshText is a no-op without a frame.
--------------------------------------------------------------------------------

local addonName, addon = ...

local UF = addon.UnitFrames
local Text = UF.Text
local Settings = UF.Settings
local DB = addon.DB
local SettingsBuilder = addon.UI.SettingsBuilder
local Helpers = addon.UI.Settings.Helpers

-- The composite's field names are the stored field names, one to one.
local IDENTITY_MAP = {}
for _, field in ipairs({ "hidden", "fontFace", "style", "size", "colorMode", "color",
                         "alignment", "offsetX", "offsetY" }) do
    IDENTITY_MAP[field] = field
end

-- The font object each string is built on (the art specs), for the size the
-- Size slider shows while none is stored.
local FONT_OBJECTS = { name = "GameFontNormalSmall", level = "GameNormalNumberFont" }

local function fontObjectSize(slot)
    local fontObject = _G[FONT_OBJECTS[slot]]
    if not fontObject then return 12 end
    local _, size = fontObject:GetFont()
    return size and math.floor(size + 0.5) or 12
end

local function addTextBlock(tab, key, slot, opts)
    local get, set = Helpers.CreateFlatAccessors(
        function(field) return DB.Get(Text.Path(key, slot, field)) end,
        function(field, value) DB.Set(Text.Path(key, slot, field), value) end,
        IDENTITY_MAP)
    tab:AddTextStyleBlock({
        get = get, set = set, apply = function() UF.RefreshText(key) end,
        defaults = { size = fontObjectSize(slot) },
        hideToggle = { label = opts.hideLabel },
        -- The paired order offers Deep Shadow: these strings are Camelot's own
        -- and fed through SetText, which the copy hooks.
        style = { order = Helpers.fontStyleOrderPaired },
        size = { min = 6, max = 24, minLabel = "6", maxLabel = "24" },
        color = {
            values = addon.Catalogs.ColorMode.Text.values,
            order = addon.Catalogs.ColorMode.Text.order,
            description = opts.colorDescription,
        },
        alignment = opts.alignment,
        offset = { range = 50, minLabel = "-50", maxLabel = "+50" },
    })
end

--------------------------------------------------------------------------------
-- Health Bar
--------------------------------------------------------------------------------
-- Unit Frames X's tabs less Border: the frame art is the border here. The
-- style has no background row, because vanilla's backing is one black fill
-- behind both bars. The two text tabs are X's % Text and Value Text with
-- a Show choice in place of the hide switch; vanilla places them (text.lua,
-- "Bar texts").

-- The composites' field names against the stored names under one path.
local BAR_STYLE_MAP = { texture = "texture", colorMode = "colorMode", color = "color" }
local BAR_TEXT_MAP = {}
for _, field in ipairs({ "fontFace", "style", "size", "colorMode", "color", "offsetX", "offsetY" }) do
    BAR_TEXT_MAP[field] = field
end

local VALUE_FORMAT = {
    values = { current = "Current", currentMax = "Current / Max" },
    order = { "current", "currentMax" },
}

local function barAccessors(key, map, ...)
    local base = Settings.BarPath(key, ...)
    return Helpers.CreateFlatAccessors(
        function(field) return DB.Get(base .. "." .. field) end,
        function(field, value) DB.Set(base .. "." .. field, value) end,
        map)
end

local function addBarTextTab(tab, key, bar, slot)
    local function apply() UF.RefreshBarText(key) end
    local showPath = Settings.BarPath(key, bar, "text", slot, "show")
    tab:AddSelector({ label = "Show Text",
        values = addon.Catalogs.ShowText.values, order = addon.Catalogs.ShowText.order,
        get = function() return Text.BarTextShow(key, bar, slot) end,
        set = function(v) DB.Set(showPath, v); apply() end })
    if slot == "value" then
        local formatPath = Settings.BarPath(key, bar, "text", "value", "format")
        tab:AddSelector({ label = "Value Format",
            values = VALUE_FORMAT.values, order = VALUE_FORMAT.order,
            get = function() return DB.Get(formatPath) or "current" end,
            set = function(v) DB.Set(formatPath, v); apply() end })
    end
    local get, set = barAccessors(key, BAR_TEXT_MAP, bar, "text", slot)
    local fontObject = _G.TextStatusBarText
    local size = fontObject and select(2, fontObject:GetFont())
    tab:AddTextStyleBlock({
        get = get, set = set, apply = apply,
        -- What the selectors show while nothing is stored: the
        -- TextStatusBarText font object's face, size and outline.
        defaults = { fontFace = "FRIZQT__", size = size and math.floor(size + 0.5) or 10, style = "OUTLINE" },
        -- The paired order offers Deep Shadow: these strings are Camelot's
        -- own and fed through SetText, which the copy hooks.
        style = { order = Helpers.fontStyleOrderOutlineFirstPaired },
        size = { min = 6, max = 24, minLabel = "6", maxLabel = "24" },
        color = { values = addon.Catalogs.ColorMode.Text.values, order = addon.Catalogs.ColorMode.Text.order },
        offset = { range = 50, minLabel = "-50", maxLabel = "+50" },
    })
    tab:Finalize()
end

local function buildHealthSection(builder, key, navKey)
    local surface = Settings.SURFACE[key]

    local function predictionToggle(inner, label, field, disabledBy)
        local path = Settings.HealthPath(key, field)
        inner:AddToggle({ label = label,
            disabled = disabledBy and function() return Settings.Health(key, disabledBy) == false end,
            get = function() return DB.Get(path) ~= false end,
            set = function(v)
                DB.Set(path, v and true or false)
                UF.RefreshHealth(key)
                inner:RefreshControls()
            end })
    end

    local tabs = { { key = "style", label = "Style" }, { key = "visibility", label = "Visibility" } }
    local content = {}

    content.style = function(_, tab)
        local get, set = barAccessors(key, BAR_STYLE_MAP, "health")
        tab:AddBarStyleBlock({ get = get, set = set, apply = function() UF.RefreshBarStyle(key) end,
            foreground = { colorDefault = { 0, 1, 0, 1 } },
            background = false, opacity = false })
        tab:Finalize()
    end

    content.visibility = function(_, tab)
        local hidePath = Settings.BarPath(key, "health", "hideTextureOnly")
        tab:AddToggle({ label = "Hide the Bar but not its Text",
            get = function() return DB.Get(hidePath) == true end,
            set = function(v)
                DB.Set(hidePath, v and true or false)
                UF.RefreshBarStyle(key)
            end })
        -- Unit Frames X's heal switches hide Blizzard's overlays; these
        -- frames draw their own, and each switch shows one.
        if surface.health then
            predictionToggle(tab, "Show Incoming Heals", "incomingHeals")
            predictionToggle(tab, "Show Absorb Shield", "absorb")
            predictionToggle(tab, "Show Over-Absorb Glow", "overAbsorbGlow", "absorb")
            predictionToggle(tab, "Show Heal Absorbs", "healAbsorb")
        end
        tab:Finalize()
    end

    if surface.barText then
        tabs[#tabs + 1] = { key = "percentText", label = "% Text" }
        tabs[#tabs + 1] = { key = "valueText", label = "Value Text" }
        content.percentText = function(_, tab) addBarTextTab(tab, key, "health", "percent") end
        content.valueText = function(_, tab) addBarTextTab(tab, key, "health", "value") end
    end

    builder:AddCollapsibleSection({ title = "Health Bar", componentId = navKey,
        sectionKey = "healthBar", defaultExpanded = false,
        buildContent = function(_, inner)
            inner:AddTabbedSection({
                tabs = tabs,
                componentId = navKey,
                sectionKey = "healthBar_tabs",
                buildContent = content,
            })
            inner:Finalize()
        end })
end

--------------------------------------------------------------------------------
-- Buffs & Debuffs
--------------------------------------------------------------------------------

-- The count's font object, for what the controls show while nothing is stored.
local function countDefaults()
    local fontObject = _G.NumberFontNormalSmall
    local size, flags
    if fontObject then
        local _
        _, size, flags = fontObject:GetFont()
    end
    local style = "NONE"
    if flags and flags:find("THICK") then
        style = "THICKOUTLINE"
    elseif flags and flags:find("OUTLINE") then
        style = "OUTLINE"
    end
    return { size = size and math.floor(size + 0.5) or 12, style = style, color = { 1, 1, 1, 1 } }
end

local function buildAuraSection(builder, key, navKey)
    local full = Settings.SURFACE[key].auras == "full"
    local defaults = Settings.AURA_DEFAULTS[key]
    local function apply() UF.RefreshAuras(key) end
    local function path(...) return Settings.AuraPath(key, ...) end
    local function off() return not DB.Get(path("enabled")) end

    local function toggle(tab, label, fields)
        local p = path(unpack(fields))
        tab:AddToggle({ label = label, disabled = off,
            get = function() return DB.Get(p) ~= false end,
            set = function(v) DB.Set(p, v and true or false); apply() end })
    end
    local function slider(tab, label, fields, min, max, fallback, labels)
        local p = path(unpack(fields))
        tab:AddSlider({ label = label, min = min, max = max, step = 1, disabled = off,
            minLabel = labels and labels[1] or tostring(min),
            maxLabel = labels and labels[2] or tostring(max),
            get = function() return tonumber(DB.Get(p)) or fallback end,
            set = function(v) DB.Set(p, tonumber(v) or fallback); apply() end })
    end

    local tabs, content = {}, {}

    if full then
        tabs[#tabs + 1] = { key = "buffs", label = "Buffs" }
        content.buffs = function(_, tab)
            toggle(tab, "Show Buffs", { "buffs", "show" })
            slider(tab, "Max Buffs", { "buffs", "max" }, 1, Settings.MAX_BUFFS, defaults.buffs)
            toggle(tab, "Only My Buffs", { "buffs", "onlyMine" })
            if key ~= "player" then
                toggle(tab, "Show Stealable Glow", { "buffs", "stealable" })
            end
            tab:Finalize()
        end
    end

    tabs[#tabs + 1] = { key = "debuffs", label = "Debuffs" }
    content.debuffs = function(_, tab)
        if full then toggle(tab, "Show Debuffs", { "debuffs", "show" }) end
        slider(tab, "Max Debuffs", { "debuffs", "max" }, 1,
            full and Settings.MAX_DEBUFFS or Settings.MAX_SMALL_DEBUFFS, defaults.debuffs)
        toggle(tab, "Only My Debuffs", { "debuffs", "onlyMine" })
        toggle(tab, "Color Borders by Dispel Type", { "debuffs", "dispelColors" })
        tab:Finalize()
    end

    tabs[#tabs + 1] = { key = "layout", label = "Layout" }
    content.layout = function(_, tab)
        slider(tab, "Icon Size", { "iconSize" }, 10, 40, defaults.iconSize)
        slider(tab, "Icon Shape", { "shape" }, -67, 67, 0, { "Wide", "Tall" })
        if full then
            slider(tab, "Row Width", { "rowWidth" }, 60, 240, defaults.rowWidth)
            local positionPath = path("position")
            tab:AddSelector({ label = "Position", disabled = off,
                values = { below = "Below the Frame", above = "Above the Frame" },
                order = { "below", "above" },
                get = function() return DB.Get(positionPath) or "below" end,
                set = function(v) DB.Set(positionPath, v); apply() end })
        end
        tab:Finalize()
    end

    -- Vanilla's target of target icons carry no count.
    if key ~= "targettarget" then
        tabs[#tabs + 1] = { key = "count", label = "Stack Count" }
        content.count = function(_, tab)
            local get, set = Helpers.CreateFlatAccessors(
                function(field) return DB.Get(path("count", field)) end,
                function(field, value) DB.Set(path("count", field), value) end,
                IDENTITY_MAP)
            tab:AddTextStyleBlock({
                get = get, set = set, apply = apply,
                disabled = off,
                defaults = countDefaults(),
                hideToggle = { label = "Disable Stack Count" },
                style = { order = Helpers.fontStyleOrder },
                size = { min = 6, max = 24, minLabel = "6", maxLabel = "24" },
                color = { kind = "plain" },
                offset = { range = 20, minLabel = "-20", maxLabel = "+20" },
            })
            tab:Finalize()
        end
    end

    tabs[#tabs + 1] = { key = "misc", label = "Misc" }
    content.misc = function(_, tab)
        toggle(tab, "Show Cooldown Swipe", { "swipe" })
        toggle(tab, "Show Tooltips", { "tooltips" })
        tab:Finalize()
    end

    builder:AddCollapsibleSection({ title = "Buffs & Debuffs", componentId = navKey,
        sectionKey = "auras", defaultExpanded = false,
        buildContent = function(_, inner)
            local enabledPath = path("enabled")
            inner:AddToggle({ label = "Show Buffs & Debuffs",
                get = function() return DB.Get(enabledPath) and true or false end,
                set = function(v)
                    DB.Set(enabledPath, v and true or false)
                    apply()
                    inner:RefreshControls()
                end })
            inner:AddTabbedSection({
                tabs = tabs,
                componentId = navKey,
                sectionKey = "auras_tabs",
                buildContent = content,
            })
            inner:Finalize()
        end })
end

local function Render(panel, scrollContent, key, navKey)
    panel:ClearContent()
    local builder = SettingsBuilder:CreateFor(scrollContent)
    panel._currentBuilder = builder
    builder:SetOnRefresh(function() Render(panel, scrollContent, key, navKey) end)

    local surface = Text.SURFACE[key]
    local function apply() UF.RefreshText(key) end
    local function getNumber(path, fallback)
        return tonumber(DB.Get(path)) or fallback
    end

    buildHealthSection(builder, key, navKey)
    buildAuraSection(builder, key, navKey)

    local tabs, content = {}, {}

    if surface.backdrop then
        tabs[#tabs + 1] = { key = "backdrop", label = "Backdrop" }
        content.backdrop = function(_, tab)
            local enabledPath = Text.Path(key, "backdrop", "enabled")
            local opacityPath = Text.Path(key, "backdrop", "opacity")
            tab:AddToggle({ label = "Enable Backdrop",
                description = "The leather behind the name and inside the level ring.",
                get = function() return DB.Get(enabledPath) ~= false end,
                set = function(v) DB.Set(enabledPath, v and true or false); apply() end })
            tab:AddSlider({ label = "Backdrop Opacity", min = 0, max = 100, step = 1,
                minLabel = "0%", maxLabel = "100%",
                get = function() return getNumber(opacityPath, Text.BACKDROP_OPACITY) end,
                set = function(v) DB.Set(opacityPath, tonumber(v) or Text.BACKDROP_OPACITY); apply() end })
            if surface.strip then
                local stripPath = Text.Path(key, "stripOpacity")
                tab:AddSlider({ label = "Reaction Strip Opacity", min = 0, max = 100, step = 1,
                    description = "The strip behind the name, colored by reaction. Vanilla draws it opaque.",
                    minLabel = "0%", maxLabel = "100%",
                    get = function() return getNumber(stripPath, Text.STRIP_OPACITY) end,
                    set = function(v) DB.Set(stripPath, tonumber(v) or Text.STRIP_OPACITY); apply() end })
            end
            tab:Finalize()
        end
    end

    tabs[#tabs + 1] = { key = "nameText", label = "Name Text" }
    content.nameText = function(_, tab)
        addTextBlock(tab, key, "name", {
            hideLabel = "Disable Name Text",
            alignment = surface.width and {
                kind = "align", default = key == "targettarget" and "LEFT" or "CENTER",
            } or nil,
        })
        if surface.surname then
            local surnamePath = Text.Path(key, "name", "hideSurname")
            tab:AddToggle({ label = "Hide Last Name",
                get = function() return DB.Get(surnamePath) and true or false end,
                set = function(v) DB.Set(surnamePath, v and true or false); apply() end })
        end
        if surface.fit then
            local fitPath = Text.Path(key, "name", "fit")
            local fitMinPath = Text.Path(key, "name", "fitMin")
            tab:AddToggle({ label = "Shrink Long Names",
                get = function() return DB.Get(fitPath) ~= false end,
                set = function(v)
                    DB.Set(fitPath, v and true or false)
                    apply()
                    tab:RefreshControls()
                end })
            tab:AddSlider({ label = "Smallest Name Size", min = 6, max = 12, step = 1,
                minLabel = "6", maxLabel = "12",
                disabled = function() return DB.Get(fitPath) == false end,
                get = function() return getNumber(fitMinPath, Text.FIT_MIN) end,
                set = function(v) DB.Set(fitMinPath, tonumber(v) or Text.FIT_MIN); apply() end })
        end
        if surface.width then
            local widthPath = Text.Path(key, "name", "width")
            tab:AddSlider({ label = "Name Width", min = 60, max = 160, step = 1,
                description = "The box the name is cut to. Vanilla's is 100.",
                get = function() return getNumber(widthPath, 100) end,
                set = function(v) DB.Set(widthPath, tonumber(v) or 100); apply() end })
        end
        tab:Finalize()
    end

    if surface.level then
        tabs[#tabs + 1] = { key = "levelText", label = "Level Text" }
        content.levelText = function(_, tab)
            addTextBlock(tab, key, "level", {
                hideLabel = "Disable Level Text",
                colorDescription = key ~= "player" and "Default is the level's difficulty color." or nil,
            })
            tab:Finalize()
        end
    end

    builder:AddCollapsibleSection({ title = "Name & Level Text", componentId = navKey,
        sectionKey = "nameLevelText", defaultExpanded = false,
        buildContent = function(_, inner)
            inner:AddTabbedSection({
                tabs = tabs,
                componentId = navKey,
                sectionKey = "nameLevelText_tabs",
                buildContent = content,
            })
            inner:Finalize()
        end })

    builder:Finalize()
end

for key, navKey in pairs(Text.NAV_KEYS) do
    addon.UI.SettingsPanel:RegisterRenderer(navKey, function(panel, scrollContent)
        Render(panel, scrollContent, key, navKey)
    end)
end
