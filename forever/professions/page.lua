--------------------------------------------------------------------------------
-- forever/professions/page.lua
-- The Professions page under Quality of Life (professions.lua holds the
-- settings): two sections, Professions Tracker and Skill Up Notifications,
-- each a switch over a tabbed section of the rows it governs.
--
-- A switch's rows stand in tabs of their own, so its set redraws the page;
-- the section stays open and the tab stays picked. The notification section
-- opens with the link to the Notifications page, where the look every
-- notification shares is set.
--------------------------------------------------------------------------------

local addonName, addon = ...

local Professions = addon.Professions
local Notifications = addon.Notifications
local SettingsBuilder = addon.UI.SettingsBuilder
local Helpers = addon.UI.Settings.Helpers
local Catalogs = addon.Catalogs

local NAV_KEY = Professions.NAV_KEY

local function trackerOff()
    return not Professions.TrackerOn()
end

local function iconOff()
    return trackerOff() or Professions.TrackerGet("showIcon") == false
end

local function skillUpsOff()
    return not Professions.SkillUpsOn()
end

-- The composites' field names are the stored key names under one group of
-- the tracker's keys ("bar", "textName"). TrackerSet redraws the tracker on
-- its own, so no block takes an apply.
local function group(name)
    return function(field) return Professions.TrackerGet(name .. "." .. field) end,
        function(field, value) Professions.TrackerSet(name .. "." .. field, value) end
end

local function slider(tab, label, key, range, disabled)
    tab:AddSlider({ label = label, min = range.min, max = range.max, step = range.step,
        minLabel = tostring(range.min), maxLabel = tostring(range.max), disabled = disabled,
        get = function() return Professions.Clamp(Professions.TrackerGet(key), range) end,
        set = function(v) Professions.TrackerSet(key, Professions.Clamp(v, range)) end })
end

--------------------------------------------------------------------------------
-- Professions Tracker
--------------------------------------------------------------------------------

local function textTab(tab, key)
    local get, set = group(key)
    local _, size, r, g, b = Professions.TextObject(key)
    tab:AddTextStyleBlock({
        get = get, set = set,
        disabled = trackerOff,
        defaults = { style = Professions.TEXT_STYLE, size = size, color = { r, g, b, 1 } },
        style = { order = Helpers.fontStyleOrderPaired },
        size = { min = 6, max = 24, minLabel = "6", maxLabel = "24" },
        color = { values = Catalogs.ColorMode.DefaultCustom.values,
                  order = Catalogs.ColorMode.DefaultCustom.order },
        offset = false,
    })
    tab:Finalize()
end

local TRACKER_TABS = {
    { key = "layout", label = "Layout" },
    { key = "bars", label = "Bars" },
    { key = "name", label = "Name Text" },
    { key = "level", label = "Level Text" },
    { key = "icon", label = "Icon" },
    { key = "visibility", label = "Visibility" },
}

-- Out of combat with no target the tracker is at full opacity, so the block
-- has no Out of Combat slider.
local OPACITY_TOOLTIP = {
    tooltipTitle = "Opacity Priority",
    tooltipText = "In Combat takes precedence over With Target. With neither, the tracker is at "
        .. "full opacity.",
}

local TRACKER_CONTENT = {
    layout = function(_, tab)
        slider(tab, "Width", "width", Professions.WIDTH, trackerOff)
        slider(tab, "Bar Height", "barHeight", Professions.BAR_HEIGHT, trackerOff)
        slider(tab, "Row Spacing", "spacing", Professions.SPACING, trackerOff)
        tab:AddSelector({ label = "Order", disabled = trackerOff,
            values = Professions.ORDER.values, order = Professions.ORDER.order,
            get = function() return Professions.TrackerGet("order") or "lowFirst" end,
            set = function(v) Professions.TrackerSet("order", v) end })
        tab:AddToggle({ label = "Show Secondary Professions", disabled = trackerOff,
            get = function() return Professions.TrackerGet("secondary") ~= false end,
            set = function(v) Professions.TrackerSet("secondary", v and true or false) end })
        tab:Finalize()
    end,

    bars = function(_, tab)
        local get, set = group("bar")
        tab:AddBarStyleBlock({
            get = get, set = set,
            disabled = trackerOff,
            foreground = { values = Catalogs.ColorMode.Background.values,
                           order = Catalogs.ColorMode.Background.order,
                           infoIcons = false, colorDefault = Professions.BAR_COLOR },
            background = { values = Catalogs.ColorMode.DefaultCustom.values,
                           order = Catalogs.ColorMode.DefaultCustom.order },
            opacity = { default = Professions.BACKGROUND_OPACITY, minLabel = "0%", maxLabel = "100%" },
        })
        tab:Finalize()
    end,

    name = function(_, tab) textTab(tab, "textName") end,
    level = function(_, tab) textTab(tab, "textLevel") end,

    icon = function(_, tab)
        tab:AddToggle({ label = "Show Icon", disabled = trackerOff,
            get = function() return Professions.TrackerGet("showIcon") ~= false end,
            set = function(v)
                Professions.TrackerSet("showIcon", v and true or false)
                tab:RefreshControls()
            end })
        slider(tab, "Icon Size", "iconSize", Professions.ICON_SIZE, iconOff)
        local get, set = Helpers.CreateIconBorderAccessors(
            function(key) return Professions.TrackerGet("icon." .. key) end,
            function(key, value) Professions.TrackerSet("icon." .. key, value) end,
            "border")
        tab:AddIconBorderBlock({
            get = get, set = set,
            disabled = iconOff,
            enableToggle = { label = "Show Icon Border" },
            style = { default = "blizzard" },
        })
        tab:Finalize()
    end,

    visibility = function(_, tab)
        local get, set = Helpers.CreateFlatAccessors(
            Professions.TrackerGet, Professions.TrackerSet, Professions.OPACITY_KEYS)
        tab:AddStateOpacityBlock({ get = get, set = set, disabled = trackerOff, min = 0, ooc = false,
            infoIcon = OPACITY_TOOLTIP })
        tab:AddToggle({ label = "Mouseover Mode", disabled = trackerOff,
            get = function() return Professions.TrackerGet("mouseoverMode") == true end,
            set = function(v) Professions.TrackerSet("mouseoverMode", v and true or false) end })
        tab:Finalize()
    end,
}

local function buildTracker(builder)
    builder:AddCollapsibleSection({ title = "Professions Tracker", componentId = NAV_KEY,
        sectionKey = "tracker", defaultExpanded = false,
        buildContent = function(_, inner)
            inner:AddToggle({ label = "Enable Professions Tracker",
                get = Professions.TrackerOn,
                set = function(v)
                    Professions.TrackerSet("enabled", v and true or false)
                    inner:DeferredRefreshAll()
                end })
            inner:AddTabbedSection({
                tabs = TRACKER_TABS,
                componentId = NAV_KEY,
                sectionKey = "trackerTabs",
                buildContent = TRACKER_CONTENT,
            })
            inner:Finalize()
        end })
end

--------------------------------------------------------------------------------
-- Skill Up Notifications
--------------------------------------------------------------------------------

local function skillUpToggle(tab, label, key)
    tab:AddToggle({ label = label, disabled = skillUpsOff,
        get = function() return Professions.SkillUpsGet(key) ~= false end,
        set = function(v) Professions.SkillUpsSet(key, v and true or false) end })
end

local SKILL_UP_TABS = {
    { key = "content", label = "Content" },
    { key = "number", label = "Number" },
}

local SKILL_UP_CONTENT = {
    content = function(_, tab)
        skillUpToggle(tab, "Show Profession Icon", "showIcon")
        skillUpToggle(tab, "Include Secondary Professions", "secondary")
        tab:Finalize()
    end,

    number = function(_, tab)
        skillUpToggle(tab, "Roll From Previous Level", "roll")
        tab:AddColorPicker({ label = "Number Color", disabled = skillUpsOff,
            get = function() return Professions.NumberColor() end,
            set = function(r, g, b) Professions.SkillUpsSet("color", { r or 1, g or 1, b or 1, 1 }) end })
        tab:Finalize()
    end,
}

local function buildSkillUps(builder)
    builder:AddCollapsibleSection({ title = "Skill Up Notifications", componentId = NAV_KEY,
        sectionKey = "skillUps", defaultExpanded = false,
        buildContent = function(_, inner)
            Notifications.AddSettingsLink(inner)
            inner:AddToggle({ label = "Enable Skill Up Notifications",
                get = Professions.SkillUpsOn,
                set = function(v)
                    Professions.SkillUpsSet("enabled", v and true or false)
                    inner:DeferredRefreshAll()
                end })
            inner:AddTabbedSection({
                tabs = SKILL_UP_TABS,
                componentId = NAV_KEY,
                sectionKey = "skillUpsTabs",
                buildContent = SKILL_UP_CONTENT,
            })
            -- Forever only (forever/notifications/display.lua).
            if Notifications.ShowTest then
                inner:AddButtonRow({ buttons = {
                    { text = "Show Test Notification",
                      onClick = function() Notifications.ShowTest(Professions.SOURCE) end,
                      isDisabled = skillUpsOff },
                } })
            end
            inner:Finalize()
        end })
end

local function Render(panel, scrollContent)
    panel:ClearContent()
    local builder = SettingsBuilder:CreateFor(scrollContent)
    panel._currentBuilder = builder
    builder:SetOnRefresh(function() Render(panel, scrollContent) end)

    buildTracker(builder)
    buildSkillUps(builder)

    builder:Finalize()
end

addon.UI.SettingsPanel:RegisterRenderer(NAV_KEY, Render)
