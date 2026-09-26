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
        sectionKey = "nameLevelText", defaultExpanded = true,
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
