-- ObjectiveTrackerRenderer.lua - Objective Tracker settings renderer
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.Settings = addon.UI.Settings or {}
addon.UI.Settings.ObjectiveTracker = {}

local ObjectiveTracker = addon.UI.Settings.ObjectiveTracker
local SettingsBuilder = addon.UI.SettingsBuilder

function ObjectiveTracker.Render(panel, scrollContent)
    -- Clear any existing content
    panel:ClearContent()

    -- Create builder for this content area
    local builder = SettingsBuilder:CreateFor(scrollContent)
    panel._currentBuilder = builder

    -- Store reference to this function for re-rendering on expand/collapse
    builder:SetOnRefresh(function()
        ObjectiveTracker.Render(panel, scrollContent)
    end)

    local Helpers = addon.UI.Settings.Helpers
    local h = Helpers.CreateComponentHelpers("objectiveTracker")
    local getComponent, getSetting = h.getComponent, h.get
    local setSetting = h.setAndApply
    local syncEditModeSetting = h.sync

    local function applyText()
        if addon and addon.ApplyStyles then
            addon:ApplyStyles()
        end
    end

    -- Collapsible section: Sizing
    builder:AddCollapsibleSection({
        title = "Sizing",
        componentId = "objectiveTracker",
        sectionKey = "sizing",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddSlider({
                label = "Scale",
                description = "Scale the entire Objective Tracker frame.",
                min = 0.5,
                max = 1.5,
                step = 0.05,
                get = function() return getSetting("scale") or 1.0 end,
                set = function(v) setSetting("scale", v) end,
                minLabel = "50%",
                maxLabel = "150%",
                precision = 0,
                displayMultiplier = 100,
                displaySuffix = "%",
            })

            inner:AddSlider({
                label = "Height",
                description = "Maximum height of the Objective Tracker frame.",
                min = 200,
                max = 1000,
                step = 10,
                get = function() return getSetting("height") or 400 end,
                set = function(v) setSetting("height", v) end,
                minLabel = "200",
                maxLabel = "1000",
                debounceKey = "UI_objectiveTracker_height",
                debounceDelay = 0.2,
                onEditModeSync = function(newValue)
                    syncEditModeSetting("height")
                end,
            })

            inner:AddSlider({
                label = "Text Size",
                description = "Size of text in the Objective Tracker.",
                min = 12,
                max = 20,
                step = 1,
                get = function() return getSetting("textSize") or 14 end,
                set = function(v) setSetting("textSize", v) end,
                minLabel = "12",
                maxLabel = "20",
                debounceKey = "UI_objectiveTracker_textSize",
                debounceDelay = 0.2,
                onEditModeSync = function(newValue)
                    syncEditModeSetting("textSize")
                end,
            })

            inner:Finalize()
        end,
    })

    -- Collapsible section: Style
    builder:AddCollapsibleSection({
        title = "Style",
        componentId = "objectiveTracker",
        sectionKey = "style",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddToggle({
                label = "Hide Header Backgrounds",
                description = "Remove the backgrounds behind section headers.",
                get = function()
                    return getSetting("hideHeaderBackgrounds") or false
                end,
                set = function(val)
                    setSetting("hideHeaderBackgrounds", val)
                end,
            })

            inner:AddToggleColorPicker({
                label = "Tint Header Background",
                description = "Apply a custom tint color to section header backgrounds.",
                get = function()
                    return getSetting("tintHeaderBackgroundEnable") or false
                end,
                set = function(val)
                    setSetting("tintHeaderBackgroundEnable", val)
                end,
                getColor = function()
                    local c = getSetting("tintHeaderBackgroundColor")
                    if c and type(c) == "table" then
                        return c[1] or c.r or 1, c[2] or c.g or 1, c[3] or c.b or 1, c[4] or c.a or 1
                    end
                    return 1, 1, 1, 1
                end,
                setColor = function(r, g, b, a)
                    setSetting("tintHeaderBackgroundColor", { r, g, b, a })
                end,
                hasAlpha = true,
            })

            inner:Finalize()
        end,
    })

    -- Shared text block for the three Text tabs: font/style/color only (text
    -- size comes from the Sizing section). Writes route through
    -- EnsureComponentSubTable so a fresh profile keeps its sibling defaults
    -- (the old rawset idiom dropped them).
    local function addTextStyleBlock(tabBuilder, dbKey, defaults)
        local s = Helpers.CreateSubTableHelpers("objectiveTracker", dbKey, { apply = applyText })
        tabBuilder:AddTextStyleBlock({
            get = s.get, set = s.set, apply = applyText,
            defaults = defaults,
            font = { description = "The font used for this text element." },
            style = { description = "The outline style for this text." },
            size = false,
            color = {
                values = addon.Catalogs.ColorMode.DefaultCustom.values, order = addon.Catalogs.ColorMode.DefaultCustom.order,
                description = "Color mode for this text. Select 'Custom' to choose a specific color.",
            },
            offset = false,
        })
        tabBuilder:Finalize()
    end

    -- Collapsible section: Text (with tabbed sub-sections)
    builder:AddCollapsibleSection({
        title = "Text",
        componentId = "objectiveTracker",
        sectionKey = "text",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddTabbedSection({
                tabs = {
                    { key = "header", label = "Header" },
                    { key = "questName", label = "Quest Name" },
                    { key = "questObjective", label = "Quest Objective" },
                },
                componentId = "objectiveTracker",
                sectionKey = "textTabs",
                buildContent = {
                    header = function(tabContent, tabBuilder)
                        addTextStyleBlock(tabBuilder, "textHeader", {
                            fontFace = "FRIZQT__",
                            style = "OUTLINE",
                            colorMode = "default",
                            color = { 1, 1, 1, 1 },
                        })
                    end,
                    questName = function(tabContent, tabBuilder)
                        addTextStyleBlock(tabBuilder, "textQuestName", {
                            fontFace = "FRIZQT__",
                            style = "OUTLINE",
                            colorMode = "default",
                            color = { 1, 1, 1, 1 },
                        })
                    end,
                    questObjective = function(tabContent, tabBuilder)
                        addTextStyleBlock(tabBuilder, "textQuestObjective", {
                            fontFace = "FRIZQT__",
                            style = "OUTLINE",
                            colorMode = "default",
                            color = { 0.8, 0.8, 0.8, 1 },
                        })
                    end,
                },
            })

            inner:Finalize()
        end,
    })

    -- -----------------------------------------------------------------------
    -- Collapsible section: Dungeon Tracker
    -- -----------------------------------------------------------------------

    -- Helpers to read/write from the dungeonTracker sub-table
    local function getDTConfig()
        local comp = getComponent()
        local db = comp and comp.db
        if db and type(db.dungeonTracker) == "table" then
            return db.dungeonTracker
        end
    end

    -- Seeds from the registered default on first write, so a fresh profile
    -- keeps its sibling defaults (the old rawset idiom dropped them).
    local function ensureDTConfig()
        local comp = getComponent()
        if not comp then return nil end
        return addon:EnsureComponentSubTable(comp, "dungeonTracker")
    end

    -- Generic read/write helpers for nested DT sub-tables (stageText, keyLevelText, timerText)
    local function getDTSubConfig(key)
        local dt = getDTConfig()
        if dt and type(dt[key]) == "table" then
            return dt[key]
        end
    end

    local function ensureDTSubConfig(key)
        local dt = ensureDTConfig()
        if not dt then return nil end
        local t = rawget(dt, key)
        if not t then
            t = {}
            rawset(dt, key, t)
        end
        return t
    end

    local function applyDT()
        if addon and addon.ApplyStyles then
            addon:ApplyStyles()
        end
    end

    builder:AddCollapsibleSection({
        title = "Dungeon Tracker",
        componentId = "objectiveTracker",
        sectionKey = "dungeonTracker",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            -- Toggle ABOVE the tabbed section
            inner:AddToggle({
                label = "Collapse Other Sections when Key Starts",
                description = "Automatically collapse all other Objective Tracker sections (quests, campaigns, etc.) when a Mythic+ keystone run begins.",
                get = function()
                    local dt = getDTConfig()
                    return dt and dt.collapseOtherOnKeyStart or false
                end,
                set = function(val)
                    local dt = ensureDTConfig()
                    if dt then
                        dt.collapseOtherOnKeyStart = val and true or false
                        applyDT()
                    end
                end,
            })

            -- Tabbed section: Instance Name | Key Level | Timer Text | Visibility
            -- Standard text-styling tab over the nested dungeonTracker sub-tables.
            -- These sit two levels down (component db > dungeonTracker > dbKey),
            -- below EnsureComponentSubTable's reach, so the accessors stay local.
            local function buildDTTextTab(tabBuilder, dbKey, defaults)
                tabBuilder:AddTextStyleBlock({
                    get = function(field)
                        local t = getDTSubConfig(dbKey)
                        return t and t[field]
                    end,
                    set = function(field, value)
                        local t = ensureDTSubConfig(dbKey)
                        if t then t[field] = value end
                    end,
                    apply = applyDT,
                    defaults = defaults,
                    font = { description = "The font used for this text element." },
                    style = { description = "The outline style for this text." },
                    size = { min = 6, max = 32, minLabel = "6", maxLabel = "32",
                        description = "Size of this text element." },
                    color = {
                        values = addon.Catalogs.ColorMode.DefaultCustom.values, order = addon.Catalogs.ColorMode.DefaultCustom.order,
                        description = "Color mode for this text. Select 'Custom' to choose a specific color.",
                    },
                    offset = false,
                })
                tabBuilder:Finalize()
            end

            inner:AddTabbedSection({
                tabs = {
                    { key = "instanceName", label = "Instance Name" },
                    { key = "keyLevel", label = "Key Level" },
                    { key = "timerText", label = "Timer Text" },
                    { key = "trashPercent", label = "Trash %" },
                    { key = "affixIcons", label = "Affix Icons" },
                    { key = "timerBar", label = "Timer Bar" },
                    { key = "visibility", label = "Visibility" },
                },
                componentId = "objectiveTracker",
                sectionKey = "dungeonTrackerTabs",
                buildContent = {
                    instanceName = function(tabContent, tabBuilder)
                        buildDTTextTab(tabBuilder, "stageText", {
                            fontFace = "FRIZQT__",
                            size = 18,
                            style = "NONE",
                            colorMode = "default",
                            color = { 1, 0.914, 0.682, 1 },
                        })
                    end,
                    keyLevel = function(tabContent, tabBuilder)
                        buildDTTextTab(tabBuilder, "keyLevelText", {
                            fontFace = "FRIZQT__",
                            size = 14,
                            style = "NONE",
                            colorMode = "default",
                            color = { 1, 1, 1, 1 },
                        })
                    end,
                    timerText = function(tabContent, tabBuilder)
                        buildDTTextTab(tabBuilder, "timerText", {
                            fontFace = "FRIZQT__",
                            size = 20,
                            style = "NONE",
                            colorMode = "default",
                            color = { 1, 1, 1, 1 },
                        })
                    end,
                    trashPercent = function(tabContent, tabBuilder)
                        buildDTTextTab(tabBuilder, "trashPercentText", {
                            fontFace = "FRIZQT__",
                            size = 14,
                            style = "NONE",
                            colorMode = "default",
                            color = { 1, 1, 1, 1 },
                        })
                    end,
                    affixIcons = function(tabContent, tabBuilder)
                        tabBuilder:AddSlider({
                            label = "Icon Scale",
                            description = "Scale the affix icons up or down.",
                            min = 0.5,
                            max = 3.0,
                            step = 0.05,
                            get = function()
                                local dt = getDTConfig()
                                return (dt and dt.affixIconScale) or 1.0
                            end,
                            set = function(v)
                                local dt = ensureDTConfig()
                                if dt then
                                    dt.affixIconScale = v
                                    applyDT()
                                end
                            end,
                            minLabel = "50%",
                            maxLabel = "300%",
                            precision = 0,
                            displayMultiplier = 100,
                            displaySuffix = "%",
                        })

                        local get, set = Helpers.CreateIconBorderAccessors(
                            function(key) local dt = getDTConfig(); return dt and dt[key] end,
                            function(key, v) local dt = ensureDTConfig(); if dt then dt[key] = v end end,
                            "affixBorder")
                        tabBuilder:AddIconBorderBlock({
                            get = get, set = set, apply = applyDT,
                            style = {
                                prefixEntries = { { "default", "Default" }, { "none", "No Border" } },
                                default = "default",
                                description = "Choose the border style for affix icons.",
                            },
                            tint = { description = "Apply a custom tint color to the affix icon border." },
                            thickness = false,
                            inset = false,
                        })

                        tabBuilder:Finalize()
                    end,
                    timerBar = function(tabContent, tabBuilder)
                        tabBuilder:AddToggle({
                            label = "Hide Timer Bar",
                            description = "Hide the Mythic+ timer progress bar entirely.",
                            get = function()
                                local dt = getDTConfig()
                                return dt and dt.hideTimerBar or false
                            end,
                            set = function(val)
                                local dt = ensureDTConfig()
                                if dt then
                                    dt.hideTimerBar = val and true or false
                                    applyDT()
                                end
                            end,
                        })

                        -- Foreground (bar fill)
                        local barGet, barSet = Helpers.CreateFlatAccessors(
                            function(key) local dt = getDTConfig(); return dt and dt[key] end,
                            function(key, value) local dt = ensureDTConfig(); if dt then dt[key] = value end end,
                            { texture = "timerBarForegroundTexture", colorMode = "timerBarForegroundColorMode", color = "timerBarForegroundColor" })
                        tabBuilder:AddBarStyleBlock({
                            get = barGet, set = barSet, apply = applyDT,
                            foreground = {
                                values = { default = "Default", original = "Texture Original", custom = "Custom" },
                                order = { "default", "original", "custom" },
                                infoIcons = false,
                            },
                            background = false,
                            opacity = false,
                        })

                        tabBuilder:Finalize()
                    end,
                    visibility = function(tabContent, tabBuilder)
                        tabBuilder:AddToggle({
                            label = "Hide Stage Background",
                            description = "Hide the background behind the dungeon/stage name header (non-M+ scenarios).",
                            get = function()
                                local dt = getDTConfig()
                                return dt and dt.hideStageBackground or false
                            end,
                            set = function(val)
                                local dt = ensureDTConfig()
                                if dt then
                                    dt.hideStageBackground = val and true or false
                                    applyDT()
                                end
                            end,
                        })

                        tabBuilder:AddToggle({
                            label = "Hide Timer Background",
                            description = "Hide the background textures behind the Mythic+ timer display.",
                            get = function()
                                local dt = getDTConfig()
                                return dt and dt.hideTimerBackground or false
                            end,
                            set = function(val)
                                local dt = ensureDTConfig()
                                if dt then
                                    dt.hideTimerBackground = val and true or false
                                    applyDT()
                                end
                            end,
                        })

                        tabBuilder:Finalize()
                    end,
                },
            })

            inner:Finalize()
        end,
    })

    -- Collapsible section: Visibility
    builder:AddCollapsibleSection({
        title = "Visibility",
        componentId = "objectiveTracker",
        sectionKey = "visibility",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddSlider({
                label = "Background Opacity",
                description = "Overall background opacity of the Objective Tracker.",
                min = 0,
                max = 100,
                step = 1,
                get = function() return getSetting("opacity") or 100 end,
                set = function(v) setSetting("opacity", v) end,
                minLabel = "0%",
                maxLabel = "100%",
                debounceKey = "UI_objectiveTracker_opacity",
                debounceDelay = 0.2,
                onEditModeSync = function(newValue)
                    syncEditModeSetting("opacity")
                end,
            })

            inner:AddSlider({
                label = "Opacity In-Instance-Combat",
                description = "Opacity when in combat inside an instance (dungeon/raid).",
                min = 0,
                max = 100,
                step = 1,
                get = function() return getSetting("opacityInInstanceCombat") or 100 end,
                set = function(v)
                    setSetting("opacityInInstanceCombat", v)
                    if addon and addon.RefreshOpacityState then
                        addon:RefreshOpacityState()
                    end
                end,
                minLabel = "0%",
                maxLabel = "100%",
            })

            inner:Finalize()
        end,
    })

    -- Finalize the layout
    builder:Finalize()
end

addon.UI.SettingsPanel:RegisterRenderer("objectiveTracker", function(panel, scrollContent)
    ObjectiveTracker.Render(panel, scrollContent)
end)

return ObjectiveTracker
