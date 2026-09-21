--------------------------------------------------------------------------------
-- forever/objectivetracker/page.lua
-- The Objective Tracker settings page, and the sections it shares with the
-- Current Objectives page (currentpage.lua).
--
-- Laid out after Scoot's page (ui/v2/settings/interface/ObjectiveTrackerRenderer.lua),
-- so a setting both products have sits in the same section under the same
-- label: Sizing, Style, Text, Visibility. Scoot's Dungeon Tracker section
-- addresses the Mythic+ blocks of the Scenario module, which Forever does
-- not run, and has no counterpart here. Loads on retail too, where no
-- tracker is built: the controls still draw and write, and a stored value
-- can be checked across a reload there while the beta keeps none.
--
-- The four sections are one function over a pane descriptor (style.lua,
-- Style.PANES), so the pane's page draws the same controls over its own keys.
--------------------------------------------------------------------------------

local addonName, addon = ...

local OT = addon.ObjectiveTracker
local Style = OT.Style
local DB = addon.DB
local SettingsBuilder = addon.UI.SettingsBuilder
local Helpers = addon.UI.Settings.Helpers

local Page = {}
OT.Page = Page

local NAV_KEY = "objectiveTracker"

-- The composite's field names are the stored field names, one to one.
local IDENTITY_MAP = {}
for _, field in ipairs({ "fontFace", "style", "colorMode", "color" }) do
    IDENTITY_MAP[field] = field
end

local function apply()
    Style.Apply()
end

function Page.GetNumber(pane, key, range)
    local v = tonumber(Style.PaneGet(pane, key))
    return v or range.default
end

function Page.SetNumber(pane, key, range, value)
    DB.Set(Style.PanePath(pane, key), tonumber(value) or range.default)
    apply()
end

-- Font, style and color over one text's fields. Size is the Sizing
-- section's, shared by all three, so the block draws none. The paired order
-- offers Deep Shadow: the strings are Camelot's own frames' and fed through
-- SetText, the call the copy hooks.
function Page.AddTextBlock(tab, pane, key, description)
    local get, set = Helpers.CreateFlatAccessors(
        function(field) return Style.PaneGet(pane, key, field) end,
        function(field, value) DB.Set(Style.PanePath(pane, key, field), value) end,
        IDENTITY_MAP)
    tab:AddTextStyleBlock({
        get = get, set = set, apply = apply,
        -- What the selectors show while nothing is stored: the roman font
        -- object's face and shadow.
        defaults = { fontFace = "FRIZQT__", style = "SHADOW" },
        font = { description = description },
        style = { order = Helpers.fontStyleOrderPaired },
        size = false,
        color = {
            values = addon.Catalogs.ColorMode.DefaultCustom.values,
            order = addon.Catalogs.ColorMode.DefaultCustom.order,
            description = "Default keeps Blizzard's color, which changes with the objective's state and on hover.",
        },
        offset = false,
    })
    tab:Finalize()
end

--- Sizing, Style, Text and Visibility over a pane's keys. `noun` names the
--- frame in the descriptions: "tracker" or "pane". The main page's Visibility
--- section also carries the instance combat fade, one setting for both.
function Page.AddLookSections(builder, pane, navKey, noun, opts)
    opts = opts or {}
    local debounce = "UI_camelotObjectiveTracker_" .. pane.key .. "_"

    builder:AddCollapsibleSection({ title = "Sizing", componentId = navKey,
        sectionKey = "sizing", defaultExpanded = false,
        buildContent = function(_, inner)
            inner:AddSlider({ label = "Scale",
                description = "Scale the whole " .. noun .. ".",
                min = Style.SCALE.min, max = Style.SCALE.max, step = Style.SCALE.step,
                minLabel = "50%", maxLabel = "150%",
                precision = 0, displayMultiplier = 100, displaySuffix = "%",
                get = function() return Page.GetNumber(pane, "scale", Style.SCALE) end,
                set = function(v) Page.SetNumber(pane, "scale", Style.SCALE, v) end })
            local height = pane.heightRange
            inner:AddSlider({ label = "Height",
                description = "The most height the " .. noun .. " takes before its modules collapse to fit.",
                min = height.min, max = height.max, step = height.step,
                minLabel = tostring(height.min), maxLabel = tostring(height.max),
                debounceKey = debounce .. "height", debounceDelay = 0.2,
                get = function() return Page.GetNumber(pane, "height", height) end,
                set = function(v) Page.SetNumber(pane, "height", height, v) end })
            inner:AddSlider({ label = "Text Size",
                description = "The size of every line. Headers draw two points larger.",
                min = Style.TEXT_SIZE.min, max = Style.TEXT_SIZE.max, step = Style.TEXT_SIZE.step,
                minLabel = tostring(Style.TEXT_SIZE.min), maxLabel = tostring(Style.TEXT_SIZE.max),
                debounceKey = debounce .. "textSize", debounceDelay = 0.2,
                get = function() return Page.GetNumber(pane, "textSize", Style.TEXT_SIZE) end,
                set = function(v) Page.SetNumber(pane, "textSize", Style.TEXT_SIZE, v) end })
            inner:Finalize()
        end })

    builder:AddCollapsibleSection({ title = "Style", componentId = navKey,
        sectionKey = "style", defaultExpanded = false,
        buildContent = function(_, inner)
            inner:AddToggle({ label = "Hide Header Backgrounds",
                description = "Remove the backgrounds behind the " .. noun .. "'s header and each section header.",
                get = function() return Style.PaneGet(pane, "hideHeaderBackgrounds") and true or false end,
                set = function(v)
                    DB.Set(Style.PanePath(pane, "hideHeaderBackgrounds"), v and true or false)
                    apply()
                end })
            inner:AddToggleColorPicker({ label = "Tint Header Background",
                description = "Tint the header backgrounds.",
                get = function() return Style.PaneGet(pane, "tintHeaderBackgroundEnable") and true or false end,
                set = function(v)
                    DB.Set(Style.PanePath(pane, "tintHeaderBackgroundEnable"), v and true or false)
                    apply()
                end,
                getColor = function()
                    local c = Style.PaneGet(pane, "tintHeaderBackgroundColor")
                    if type(c) ~= "table" then return 1, 1, 1, 1 end
                    return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
                end,
                setColor = function(r, g, b, a)
                    DB.Set(Style.PanePath(pane, "tintHeaderBackgroundColor"), { r or 1, g or 1, b or 1, a or 1 })
                    apply()
                end,
                hasAlpha = true })
            inner:Finalize()
        end })

    builder:AddCollapsibleSection({ title = "Text", componentId = navKey,
        sectionKey = "text", defaultExpanded = false,
        buildContent = function(_, inner)
            inner:AddTabbedSection({
                tabs = {
                    { key = "header", label = "Header" },
                    { key = "questName", label = "Quest Name" },
                    { key = "questObjective", label = "Quest Objective" },
                },
                componentId = navKey,
                sectionKey = "textTabs",
                buildContent = {
                    header = function(_, tab)
                        Page.AddTextBlock(tab, pane, "textHeader", "The " .. noun .. "'s header and each section header.")
                    end,
                    questName = function(_, tab)
                        Page.AddTextBlock(tab, pane, "textQuestName", "The name line of each quest, achievement or task.")
                    end,
                    questObjective = function(_, tab)
                        Page.AddTextBlock(tab, pane, "textQuestObjective", "The objective lines under a name, dash included.")
                    end,
                },
            })
            inner:Finalize()
        end })

    builder:AddCollapsibleSection({ title = "Visibility", componentId = navKey,
        sectionKey = "visibility", defaultExpanded = false,
        buildContent = function(_, inner)
            inner:AddSlider({ label = "Background Opacity",
                description = "The opacity of the background behind the whole " .. noun .. ".",
                min = Style.OPACITY.min, max = Style.OPACITY.max, step = Style.OPACITY.step,
                minLabel = "0%", maxLabel = "100%",
                debounceKey = debounce .. "opacity", debounceDelay = 0.2,
                get = function() return Page.GetNumber(pane, "opacity", Style.OPACITY) end,
                set = function(v) Page.SetNumber(pane, "opacity", Style.OPACITY, v) end })
            if opts.combatFade then
                inner:AddSlider({ label = "Opacity In-Instance-Combat",
                    description = "The tracker's and the Current Objectives pane's opacity in combat inside a dungeon or raid. The dungeon's own progress block keeps full opacity.",
                    min = 0, max = 100, step = 1,
                    minLabel = "0%", maxLabel = "100%",
                    get = function() return Style.Clamp(Style.Get("opacityInInstanceCombat"), Style.OPACITY) end,
                    set = function(v)
                        DB.Set(Style.Path("opacityInInstanceCombat"), tonumber(v) or 100)
                        apply()
                    end })
            end
            inner:Finalize()
        end })
end

local function Render(panel, scrollContent)
    panel:ClearContent()
    local builder = SettingsBuilder:CreateFor(scrollContent)
    panel._currentBuilder = builder
    builder:SetOnRefresh(function() Render(panel, scrollContent) end)

    Page.AddLookSections(builder, Style.MAIN, NAV_KEY, "tracker", { combatFade = true })

    builder:Finalize()
end

addon.UI.SettingsPanel:RegisterRenderer(NAV_KEY, function(panel, scrollContent)
    Render(panel, scrollContent)
end)
