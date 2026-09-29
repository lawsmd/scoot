--------------------------------------------------------------------------------
-- forever/objectivetracker/currentpage.lua
-- The Current Objectives settings page: the style, the pane's behaviour,
-- then the look of the style picked. Classic draws the four look sections the
-- tracker page draws, over the pane's own keys (objectiveTracker.current.*);
-- Camelot draws the cards' sections over objectiveTracker.current.cards.*.
-- The behaviour serves both. Loads on retail too, like page.lua.
--------------------------------------------------------------------------------

local addonName, addon = ...

local OT = addon.ObjectiveTracker
local Style = OT.Style
local Page = OT.Page
local DB = addon.DB
local SettingsBuilder = addon.UI.SettingsBuilder

local NAV_KEY = "currentObjectives"
local PANE = Style.CURRENT
local CARDS = Style.CARDS

local function apply()
    Style.Apply()
end

local function addToggle(inner, label, description, key)
    inner:AddToggle({ label = label, description = description,
        get = function() return Style.Get("current", key) and true or false end,
        set = function(v)
            DB.Set(Style.Path("current", key), v and true or false)
            apply()
        end })
end

local function cardSlider(inner, label, description, key, range, opts)
    opts = opts or {}
    inner:AddSlider({ label = label, description = description,
        min = range.min, max = range.max, step = range.step,
        minLabel = opts.minLabel or tostring(range.min), maxLabel = opts.maxLabel or tostring(range.max),
        precision = 0, displayMultiplier = opts.multiplier, displaySuffix = opts.suffix,
        debounceKey = "UI_camelotObjectiveTracker_cards_" .. key, debounceDelay = 0.2,
        get = function() return Page.GetNumber(CARDS, key, range) end,
        set = function(v) Page.SetNumber(CARDS, key, range, v) end })
end

-- The Camelot style's look: the cards' size and count, their two texts, and
-- their opacity.
local function addCardSections(builder)
    builder:AddCollapsibleSection({ title = "Sizing", componentId = NAV_KEY,
        sectionKey = "cardSizing", defaultExpanded = false,
        buildContent = function(_, inner)
            inner:AddSelector({ label = "Layout",
                values = Style.CARD_LAYOUTS, order = Style.CARD_LAYOUT_ORDER,
                get = function() return Style.CardLayout() end,
                set = function(v) if OT.Cards then OT.Cards.SetLayout(v) end end })
            cardSlider(inner, "Card Width", "A card's height follows its width, at a playing card's shape.",
                "width", Style.CARD_WIDTH)
            cardSlider(inner, "Spacing", nil, "spacing", Style.CARD_SPACING)
            cardSlider(inner, "Max Cards", "Quests past this many show as a count after the last card.",
                "maxCards", Style.CARD_MAX)
            cardSlider(inner, "Scale", nil, "scale", Style.SCALE,
                { minLabel = "50%", maxLabel = "150%", multiplier = 100, suffix = "%" })
            cardSlider(inner, "Title Size", nil, "titleSize", Style.CARD_TITLE_SIZE)
            cardSlider(inner, "Objective Size", nil, "objectiveSize", Style.CARD_OBJECTIVE_SIZE)
            inner:Finalize()
        end })

    builder:AddCollapsibleSection({ title = "Text", componentId = NAV_KEY,
        sectionKey = "cardText", defaultExpanded = false,
        buildContent = function(_, inner)
            inner:AddTabbedSection({
                tabs = {
                    { key = "title", label = "Quest Name" },
                    { key = "objective", label = "Objective" },
                },
                componentId = NAV_KEY,
                sectionKey = "cardTextTabs",
                buildContent = {
                    title = function(_, tab)
                        Page.AddTextBlock(tab, CARDS, "textTitle", "The quest's name at the top of each card.")
                    end,
                    objective = function(_, tab)
                        Page.AddTextBlock(tab, CARDS, "textObjective", "The objective rows and the counts in their bars.")
                    end,
                },
            })
            inner:Finalize()
        end })

    builder:AddCollapsibleSection({ title = "Visibility", componentId = NAV_KEY,
        sectionKey = "cardVisibility", defaultExpanded = false,
        buildContent = function(_, inner)
            cardSlider(inner, "Opacity", nil, "opacity", Style.OPACITY,
                { minLabel = "0%", maxLabel = "100%", suffix = "%" })
            inner:Finalize()
        end })
end

local function Render(panel, scrollContent)
    panel:ClearContent()
    local builder = SettingsBuilder:CreateFor(scrollContent)
    panel._currentBuilder = builder
    builder:SetOnRefresh(function() Render(panel, scrollContent) end)

    builder:AddSelector({
        label = "Style",
        description = "Classic lists the quests in a pane like the tracker's. Camelot draws each quest as a card, in a row or a column of cards.",
        values = Style.STYLES,
        order = Style.STYLE_ORDER,
        emphasized = true,
        get = function() return Style.CurrentStyle() end,
        set = function(v)
            DB.Set(Style.Path("current", "style"), v == "camelot" and "camelot" or "classic")
            apply()
            -- The sections below the behaviour belong to the style.
            builder:DeferredRefreshAll()
        end,
    })

    builder:AddCollapsibleSection({ title = "Behaviour", componentId = NAV_KEY,
        sectionKey = "behaviour", defaultExpanded = true,
        buildContent = function(_, inner)
            addToggle(inner, "Enable",
                "Draw a second pane that takes a tracked quest out of the tracker while it is the one you are working on. Off, every quest stays in the tracker.",
                "enabled")
            addToggle(inner, "Mark Current On Entering Area",
                "A quest moves to the pane while you stand inside the area the map marks for it, and returns when you leave.",
                "onEnterArea")
            addToggle(inner, "Mark Current On Progress",
                "A quest moves to the pane when one of its objectives advances, and stays for the hold below.",
                "onProgress")
            inner:AddSlider({ label = "Hold",
                description = "How long a quest stays in the pane after progress on it, in seconds. Another advance restarts the hold.",
                min = Style.HOLD.min, max = Style.HOLD.max, step = Style.HOLD.step,
                minLabel = Style.HOLD.min .. "s", maxLabel = Style.HOLD.max .. "s",
                precision = 0, displaySuffix = "s",
                get = function() return Style.HoldSeconds() end,
                set = function(v)
                    DB.Set(Style.Path("current", "holdSeconds"), tonumber(v) or Style.HOLD.default)
                    apply()
                end })
            inner:AddSlider({ label = "Fade",
                description = "How long a quest takes to fade into the pane and out of it, in seconds. 0 moves it at once.",
                min = Style.FADE.min, max = Style.FADE.max, step = Style.FADE.step,
                minLabel = Style.FADE.min .. "s", maxLabel = Style.FADE.max .. "s",
                precision = 1, displaySuffix = "s",
                get = function() return Style.FadeSeconds() end,
                set = function(v)
                    v = tonumber(v) or Style.FADE.default
                    -- One decimal: the slider's step lands on binary fractions.
                    DB.Set(Style.Path("current", "fadeSeconds"), math.floor(v * 10 + 0.5) / 10)
                    apply()
                end })
            addToggle(inner, "Flash Progress", nil, "flashProgress")
            inner:Finalize()
        end })

    if Style.CurrentStyle() == "camelot" then
        addCardSections(builder)
    else
        Page.AddLookSections(builder, PANE, NAV_KEY, "pane")
    end

    builder:Finalize()
end

addon.UI.SettingsPanel:RegisterRenderer(NAV_KEY, function(panel, scrollContent)
    Render(panel, scrollContent)
end)
