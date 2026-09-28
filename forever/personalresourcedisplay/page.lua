--------------------------------------------------------------------------------
-- forever/personalresourcedisplay/page.lua
-- The Personal Resource Display settings page, under Interface.
--
-- Laid out after Scoot's five pages (ui/v2/settings/prd/), folded into three
-- sections, so a setting both products have sits under the same label:
-- General, then one section per bar with its height, style, border, text
-- and visibility rows. Loads on retail too, where no display is built: the
-- controls still draw and write, and a stored value can be checked across a
-- reload there while the beta keeps none.
--------------------------------------------------------------------------------

local addonName, addon = ...

local PRD = addon.PersonalResourceDisplay
local Style = PRD.Style
local DB = addon.DB
local SettingsBuilder = addon.UI.SettingsBuilder
local Helpers = addon.UI.Settings.Helpers
local Catalogs = addon.Catalogs

local NAV_KEY = PRD.NAV_KEY

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

--------------------------------------------------------------------------------
-- General
--------------------------------------------------------------------------------

local function buildGeneral(builder)
    builder:AddCollapsibleSection({ title = "General", componentId = NAV_KEY,
        sectionKey = "general", defaultExpanded = true,
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
            inner:AddSpacer(8)
            -- The Classic unit frames' four switches, on the health bar.
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
end

--------------------------------------------------------------------------------
-- A bar
--------------------------------------------------------------------------------

local function buildBar(builder, key, title, opts)
    local base = Style.Path(key)
    builder:AddCollapsibleSection({ title = title, componentId = NAV_KEY,
        sectionKey = key, defaultExpanded = false,
        buildContent = function(_, inner)
            addToggle(inner, "Hide " .. title, Style.Path(key, "hide"), { emphasized = true })
            addSlider(inner, "Bar Height", Style.HEIGHT, Style.Path(key, "height"), "10", "30")

            -- Style
            inner:AddSpacer(8)
            local sget, sset = accessors(base, STYLE_MAP)
            inner:AddBarStyleBlock({ get = sget, set = sset, apply = apply,
                foreground = { values = opts.foreground.values, order = opts.foreground.order, infoIcons = false },
                background = { values = Catalogs.ColorMode.DefaultCustom.values,
                               order = Catalogs.ColorMode.DefaultCustom.order },
                opacity = { default = Style.BACKGROUND_OPACITY.default, minLabel = "0%", maxLabel = "100%" } })

            -- Border. Off is the picker's own "none".
            inner:AddSpacer(8)
            local bget, bset = accessors(base, BORDER_MAP)
            inner:AddBarBorderBlock({ get = bget, set = bset, apply = apply,
                style = { default = "none", hiddenEdges = false },
                thickness = { minLabel = "1", maxLabel = "8" },
                inset = false })

            -- Text: the value. The percent arrives with the percent chain.
            inner:AddSpacer(8)
            inner:AddSelector({ label = "Show Text",
                values = Style.SHOW_TEXT.values, order = Style.SHOW_TEXT.order,
                get = function() return Style.TextShow(key) end,
                set = function(v)
                    DB.Set(Style.Path(key, "text", "value", "show"), v)
                    apply()
                end })
            local tget, tset = accessors(Style.Path(key, "text", "value"), TEXT_MAP)
            local _, fontSize = Style.FontObjectFont()
            inner:AddTextStyleBlock({ get = tget, set = tset, apply = apply,
                -- What the selectors show while nothing is stored: the
                -- TextStatusBarText font object's face, size and outline.
                defaults = { fontFace = "FRIZQT__", size = fontSize, style = "OUTLINE" },
                -- The paired order offers Deep Shadow: these strings are
                -- Camelot's own and fed through SetText, which the copy hooks.
                style = { order = Helpers.fontStyleOrderOutlineFirstPaired },
                size = { min = Style.TEXT_SIZE.min, max = Style.TEXT_SIZE.max,
                         minLabel = tostring(Style.TEXT_SIZE.min), maxLabel = tostring(Style.TEXT_SIZE.max) },
                color = { values = Catalogs.ColorMode.Text.values, order = Catalogs.ColorMode.Text.order },
                alignment = { kind = "align", label = "Text Alignment", default = "RIGHT",
                              order = { "RIGHT", "LEFT", "CENTER" } },
                offset = false })

            -- Visibility
            inner:AddSpacer(8)
            addToggle(inner, "Hide the Bar but not its Text", Style.Path(key, "hideTextureOnly"))
            addToggle(inner, "Hide Bar Background", Style.Path(key, "hideBackground"))
            if opts.manaCost then
                addToggle(inner, "Hide Mana Cost Prediction", Style.Path(key, "hideManaCostPrediction"), {
                    description = "The cost of the spell being cast, drawn over the end of the fill.",
                })
            end
            inner:Finalize()
        end })
end

--------------------------------------------------------------------------------
-- Render
--------------------------------------------------------------------------------

local function Render(panel, scrollContent)
    panel:ClearContent()
    local builder = SettingsBuilder:CreateFor(scrollContent)
    panel._currentBuilder = builder
    builder:SetOnRefresh(function() Render(panel, scrollContent) end)

    buildGeneral(builder)
    buildBar(builder, "health", "Health Bar", { foreground = Catalogs.ColorMode.Text })
    buildBar(builder, "power", "Power Bar", { foreground = Catalogs.ColorMode.DefaultCustom, manaCost = true })

    builder:Finalize()
end

addon.UI.SettingsPanel:RegisterRenderer(NAV_KEY, function(panel, scrollContent)
    Render(panel, scrollContent)
end)
