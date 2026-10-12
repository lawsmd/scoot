--------------------------------------------------------------------------------
-- forever/actionbars/textpage.lua
-- The Text page under the Action Bars group: one section per action bar,
-- each with a Keybind tab. The controls are the ones Scoot's Keybind tab
-- offers (ui/v2/settings/actionbars/ActionBarRenderer.lua), and the tabbed
-- section leaves room for its Charges and Macro Name tabs.
--
-- The style list is the unpaired one: Blizzard's code writes the string with
-- SetText, Show and Hide, and a Deep Shadow copy would not follow them.
-- While nothing is stored the controls show the font object's values, which
-- are what the button draws (text.lua).
--------------------------------------------------------------------------------

local _, addon = ...

local ActionBars = addon.ActionBars
local Text = ActionBars.Text
local DB = addon.DB
local SettingsBuilder = addon.UI.SettingsBuilder
local Helpers = addon.UI.Settings.Helpers

local NAV_KEY = "actionBarText"

local BARS = { "bar1", "bar2", "bar3", "bar4", "bar5", "bar6", "bar7", "bar8" }

-- The composite's field names are the stored field names, one to one.
local IDENTITY_MAP = {}
for _, field in ipairs({ "hidden", "fontFace", "style", "size", "color", "offsetX", "offsetY" }) do
    IDENTITY_MAP[field] = field
end

-- What the controls show while nothing is stored: the template's font
-- object, Arial Narrow on every client the font families list.
local function fontObjectDefaults()
    local _, size = Text.FontObjectFont()
    local color = { 1, 1, 1, 1 }
    local fontObject = _G[Text.FONT_OBJECT]
    if fontObject then
        local r, g, b = fontObject:GetTextColor()
        color = { r, g, b, 1 }
    end
    return {
        fontFace = "ARIALN",
        size = size and math.floor(size + 0.5) or 12,
        style = Text.FontObjectStyle(),
        color = color,
    }
end

local function addKeybindTab(tab, token, defaults)
    local get, set = Helpers.CreateFlatAccessors(
        function(field) return DB.Get(Text.Path(token, field)) end,
        function(field, value) DB.Set(Text.Path(token, field), value) end,
        IDENTITY_MAP)
    tab:AddTextStyleBlock({
        get = get, set = set, apply = function() Text.Refresh(token) end,
        defaults = defaults,
        hideToggle = { label = "Hide Keybind Text" },
        style = { order = Helpers.fontStyleOrder },
        size = { min = 6, max = 32, minLabel = "6", maxLabel = "32" },
        color = { kind = "plain" },
        offset = { range = 50, minLabel = "-50", maxLabel = "+50" },
    })
    tab:Finalize()
end

local function barSection(builder, token, defaults)
    builder:AddCollapsibleSection({
        title = ActionBars.POOL[token].label, componentId = NAV_KEY,
        sectionKey = token, defaultExpanded = false,
        buildContent = function(_, inner)
            inner:AddTabbedSection({
                tabs = { { key = "keybind", label = "Keybind" } },
                componentId = NAV_KEY,
                sectionKey = token .. "_tabs",
                buildContent = {
                    keybind = function(_, tab) addKeybindTab(tab, token, defaults) end,
                },
            })
            inner:Finalize()
        end,
    })
end

local function Render(panel, scrollContent)
    panel:ClearContent()
    local builder = SettingsBuilder:CreateFor(scrollContent)
    panel._currentBuilder = builder
    builder:SetOnRefresh(function() Render(panel, scrollContent) end)

    if not ActionBars.IsEnabled() then
        builder:AddDescription("Action Bars is off on the Features page.")
        builder:Finalize()
        return
    end

    local defaults = fontObjectDefaults()
    for _, token in ipairs(BARS) do
        barSection(builder, token, defaults)
    end
    builder:Finalize()
end

addon.UI.SettingsPanel:RegisterRenderer(NAV_KEY, function(panel, scrollContent)
    Render(panel, scrollContent)
end)
