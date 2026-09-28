--------------------------------------------------------------------------------
-- forever/personalresourcedisplay/page.lua
-- The Resource Display pages, Global, Health Bar and Power Bar, their own
-- section of the nav (forever/menu.lua).
--
-- Laid out after Scoot's pages (ui/v2/settings/prd/), so a setting both
-- products have sits on the same page in the same section under the same
-- label: the Global page holds what Scoot's General page holds, plus
-- Blizzard's Show Bar Text as one switch, and each bar page runs Sizing,
-- Style, Border, Text and Visibility under its Hide toggle.
-- Loads on retail too, where no display is built: the controls still draw
-- and write, and a stored value can be checked across a reload there while
-- the beta keeps none.
--------------------------------------------------------------------------------

local addonName, addon = ...

local PRD = addon.PersonalResourceDisplay
local Style = PRD.Style
local DB = addon.DB
local SettingsBuilder = addon.UI.SettingsBuilder
local Helpers = addon.UI.Settings.Helpers
local Catalogs = addon.Catalogs

local NAV_KEYS = PRD.NAV_KEYS

local function apply()
    Style.Apply()
end

-- The composites' field names against the stored keys under one base path.
local STYLE_MAP = {
    texture = "foregroundTexture", colorMode = "foregroundColorMode", color = "foregroundTint",
    bgTexture = "backgroundTexture", bgColorMode = "backgroundColorMode", bgColor = "backgroundTint",
    bgOpacity = "backgroundOpacity",
}
local BORDER_MAP = {
    style = "borderStyle", tintEnabled = "borderTintEnabled", tintColor = "borderTintColor",
    thickness = "borderThickness",
}
local TEXT_MAP = {}
for _, field in ipairs({ "fontFace", "style", "size", "colorMode", "color", "alignment" }) do
    TEXT_MAP[field] = field
end

local function accessors(base, map)
    return Helpers.CreateFlatAccessors(
        function(key) return DB.Get(base .. "." .. key) end,
        function(key, value) DB.Set(base .. "." .. key, value) end,
        map)
end

local function addSlider(inner, label, range, path, minLabel, maxLabel)
    inner:AddSlider({ label = label,
        min = range.min, max = range.max, step = range.step, precision = 0,
        minLabel = minLabel, maxLabel = maxLabel,
        get = function() return Style.Clamp(DB.Get(path), range) end,
        set = function(v)
            DB.Set(path, Style.Clamp(v, range))
            apply()
        end })
end

local function addToggle(inner, label, path, opts)
    opts = opts or {}
    inner:AddToggle({ label = label, description = opts.description, emphasized = opts.emphasized,
        disabled = opts.disabled,
        get = function() return DB.Get(path) == true end,
        set = function(v)
            DB.Set(path, v and true or false)
            apply()
            if opts.refresh then inner:RefreshControls() end
        end })
end

local function beginPage(panel, scrollContent, render)
    panel:ClearContent()
    local builder = SettingsBuilder:CreateFor(scrollContent)
    panel._currentBuilder = builder
    builder:SetOnRefresh(function() render(panel, scrollContent) end)
    return builder
end

--------------------------------------------------------------------------------
-- Global
--------------------------------------------------------------------------------

local function RenderGlobal(panel, scrollContent)
    local builder = beginPage(panel, scrollContent, RenderGlobal)
    local navKey = NAV_KEYS.global

    builder:AddCollapsibleSection({ title = "Display", componentId = navKey,
        sectionKey = "display", defaultExpanded = true,
        buildContent = function(_, inner)
            inner:AddSelector({ label = "Visibility",
                values = Catalogs.Visibility.values, order = Catalogs.Visibility.order,
                get = Style.Visibility,
                set = function(v)
                    DB.Set(Style.Path("visibility"), v)
                    apply()
                end })
            addSlider(inner, "Scale", Style.SCALE, Style.Path("scale"), "70%", "150%")
            addSlider(inner, "Bar Width", Style.BAR_WIDTH, Style.Path("barWidth"), "50%", "150%")
            addSlider(inner, "Bar Spacing", Style.PADDING, Style.Path("padding"), "0", "10")
            addSlider(inner, "Opacity", Style.OPACITY, Style.Path("opacity"), "50%", "100%")
            -- Blizzard's one switch over the four texts; each text's own
            -- show mode is on its bar page.
            inner:AddToggle({ label = "Show Bar Text",
                get = Style.BarTextShown,
                set = function(v)
                    Style.SetBarTextShown(v and true or false)
                    apply()
                end })
            inner:Finalize()
        end })

    -- The Classic unit frames' four switches, on the health bar.
    builder:AddCollapsibleSection({ title = "Heal Prediction", componentId = navKey,
        sectionKey = "healPrediction", defaultExpanded = true,
        buildContent = function(_, inner)
            local function healthToggle(label, field, disabledBy)
                addToggle(inner, label, Style.Path("health", field), {
                    refresh = true,
                    disabled = disabledBy and function() return Style.Get("health", disabledBy) == false end,
                })
            end
            healthToggle("Show Incoming Heals", "incomingHeals")
            healthToggle("Show Absorb Shield", "absorb")
            healthToggle("Show Over-Absorb Glow", "overAbsorbGlow", "absorb")
            healthToggle("Show Heal Absorbs", "healAbsorb")
            inner:Finalize()
        end })

    builder:Finalize()
end

--------------------------------------------------------------------------------
-- The bar pages
--------------------------------------------------------------------------------
-- Scoot's section order per bar: the health page draws Border before Style,
-- the power page Style before Border.

local SECTION_ORDER = {
    health = { "sizing", "border", "style", "text", "visibility" },
    power = { "sizing", "style", "border", "text", "visibility" },
}

local TITLES = { sizing = "Sizing", style = "Style", border = "Border", text = "Text", visibility = "Visibility" }

local SECTIONS = {}

function SECTIONS.sizing(inner, key)
    addSlider(inner, "Bar Height", Style.HEIGHT, Style.Path(key, "height"), "10", "30")
end

function SECTIONS.style(inner, key, opts)
    local get, set = accessors(Style.Path(key), STYLE_MAP)
    inner:AddBarStyleBlock({ get = get, set = set, apply = apply,
        foreground = { values = opts.foreground.values, order = opts.foreground.order, infoIcons = false },
        background = { values = Catalogs.ColorMode.DefaultCustom.values,
                       order = Catalogs.ColorMode.DefaultCustom.order },
        opacity = { default = Style.BACKGROUND_OPACITY.default, minLabel = "0%", maxLabel = "100%" } })
end

-- Off is the picker's own "none".
function SECTIONS.border(inner, key)
    local get, set = accessors(Style.Path(key), BORDER_MAP)
    inner:AddBarBorderBlock({ get = get, set = set, apply = apply,
        style = { default = "none", hiddenEdges = false },
        thickness = { minLabel = "1", maxLabel = "8" },
        inset = false })
end

-- One text's tab: its show mode and its style block. The alignment order
-- leads with the side the text starts on.
local ALIGN_ORDER = {
    value = { "RIGHT", "LEFT", "CENTER" },
    percent = { "LEFT", "RIGHT", "CENTER" },
}

local function addTextTab(tab, key, slot)
    tab:AddSelector({ label = "Show Text",
        values = Style.SHOW_TEXT.values, order = Style.SHOW_TEXT.order,
        get = function() return Style.TextShow(key, slot) end,
        set = function(v)
            DB.Set(Style.Path(key, "text", slot, "show"), v)
            apply()
        end })
    local get, set = accessors(Style.Path(key, "text", slot), TEXT_MAP)
    local _, fontSize = Style.FontObjectFont()
    tab:AddTextStyleBlock({ get = get, set = set, apply = apply,
        -- What the selectors show while nothing is stored: the
        -- TextStatusBarText font object's face, size and outline.
        defaults = { fontFace = "FRIZQT__", size = fontSize, style = "OUTLINE" },
        -- The paired order offers Deep Shadow: these strings are Camelot's
        -- own and fed through SetText, which the copy hooks.
        style = { order = Helpers.fontStyleOrderOutlineFirstPaired },
        size = { min = Style.TEXT_SIZE.min, max = Style.TEXT_SIZE.max,
                 minLabel = tostring(Style.TEXT_SIZE.min), maxLabel = tostring(Style.TEXT_SIZE.max) },
        color = { values = Catalogs.ColorMode.Text.values, order = Catalogs.ColorMode.Text.order },
        alignment = { kind = "align", label = "Text Alignment", default = Style.TEXT_ALIGN[slot],
                      order = ALIGN_ORDER[slot] },
        offset = false })
    tab:Finalize()
end

-- Value Text and % Text, Scoot's two tabs.
function SECTIONS.text(inner, key)
    inner:AddTabbedSection({
        tabs = {
            { key = "value", label = "Value Text" },
            { key = "percent", label = "% Text" },
        },
        componentId = NAV_KEYS[key],
        sectionKey = "textTabs",
        buildContent = {
            value = function(_, tab) addTextTab(tab, key, "value") end,
            percent = function(_, tab) addTextTab(tab, key, "percent") end,
        },
    })
end

function SECTIONS.visibility(inner, key, opts)
    addToggle(inner, "Hide the Bar but not its Text", Style.Path(key, "hideTextureOnly"))
    addToggle(inner, "Hide Bar Background", Style.Path(key, "hideBackground"))
    if opts.manaCost then
        addToggle(inner, "Hide Mana Cost Prediction", Style.Path(key, "hideManaCostPrediction"), {
            description = "The cost of the spell being cast, drawn over the end of the fill.",
        })
    end
end

local function RenderBar(panel, scrollContent, key, title, opts, render)
    local builder = beginPage(panel, scrollContent, render)
    local navKey = NAV_KEYS[key]

    addToggle(builder, "Hide " .. title, Style.Path(key, "hide"), { emphasized = true })

    for _, section in ipairs(SECTION_ORDER[key]) do
        builder:AddCollapsibleSection({ title = TITLES[section], componentId = navKey,
            sectionKey = section, defaultExpanded = false,
            buildContent = function(_, inner)
                SECTIONS[section](inner, key, opts)
                inner:Finalize()
            end })
    end

    builder:Finalize()
end

local function RenderHealth(panel, scrollContent)
    RenderBar(panel, scrollContent, "health", "Health Bar",
        { foreground = Catalogs.ColorMode.Text }, RenderHealth)
end

local function RenderPower(panel, scrollContent)
    RenderBar(panel, scrollContent, "power", "Power Bar",
        { foreground = Catalogs.ColorMode.DefaultCustom, manaCost = true }, RenderPower)
end

--------------------------------------------------------------------------------
-- Registration
--------------------------------------------------------------------------------

addon.UI.SettingsPanel:RegisterRenderer(NAV_KEYS.global, RenderGlobal)
addon.UI.SettingsPanel:RegisterRenderer(NAV_KEYS.health, RenderHealth)
addon.UI.SettingsPanel:RegisterRenderer(NAV_KEYS.power, RenderPower)
