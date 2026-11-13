-- BonusAurasRenderer.lua - The BonusAuras page: one section per bonus aura
--
-- A bonus aura (core/components/scootauras/bonus.lua) is a tracker the addon
-- defines whole, so its page is a short list of rows and not the Aura List's
-- editor. Each aura this host can run gets one collapsible section, its
-- tooltip on the header's info icon and its rows from the table below. A host
-- that can run none adds no row: the search scan runs every renderer, and a
-- row here would point at a page whose nav row is hidden.
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.Settings = addon.UI.Settings or {}
addon.UI.Settings.BonusAuras = {}

local Page = addon.UI.Settings.BonusAuras
local SettingsBuilder = addon.UI.SettingsBuilder

-- [bonus aura key] = function(inner, componentId): the section's rows.
local sections = {}

-- All Cooldowns: the group's own rows, then the tracker editor's Duration
-- tab over the same keys. That tab finalizes the builder it is given, so it
-- is the last call on this one.
sections.bonusAllCooldowns = function(inner, componentId)
    local Helpers = addon.UI.Settings.Helpers
    local Tabs = addon.UI.Settings.ScootAuraEditorTabs
    local h = Helpers.CreateComponentHelpers(componentId)
    local get, set = h.get, h.setAndApplyComponent

    inner:AddToggle({
        label = "Enable",
        get = function() return get("bonusEnabled") ~= false end,
        set = function(v) set("bonusEnabled", v and true or false) end,
    })

    inner:AddSlider({
        label = "Icon Size",
        min = 16, max = 64, step = 1, precision = 0,
        get = function() return get("iconSize") or 32 end,
        set = function(v) set("iconSize", v) end,
        minLabel = "16", maxLabel = "64",
    })

    inner:AddSlider({
        label = "Icon Spacing",
        min = 0, max = 20, step = 1, precision = 0,
        get = function() return get("bonusSpacing") or 4 end,
        set = function(v) set("bonusSpacing", v) end,
        minLabel = "0", maxLabel = "20",
    })

    inner:AddSlider({
        label = "Columns",
        min = 1, max = 20, step = 1, precision = 0,
        get = function() return get("bonusColumns") or 12 end,
        set = function(v) set("bonusColumns", v) end,
        minLabel = "1", maxLabel = "20",
    })

    inner:AddSelector({
        label = "Alignment",
        values = { left = "Left", center = "Center", right = "Right" },
        order = { "left", "center", "right" },
        get = function() return get("bonusAlign") or "center" end,
        set = function(v) set("bonusAlign", v) end,
    })

    inner:AddSlider({
        label = "Opacity",
        min = 1, max = 100, step = 1, precision = 0,
        get = function() return get("bonusOpacity") or 50 end,
        set = function(v) set("bonusOpacity", v) end,
        minLabel = "1%", maxLabel = "100%",
        displaySuffix = "%",
    })

    Tabs.BuildDurationTab(inner, {
        get = get,
        setAndApply = set,
        refreshPreview = function() end,
        shape = function() return "icon" end,
    })
end

function Page.Render(panel, scrollContent)
    panel:ClearContent()

    local builder = SettingsBuilder:CreateFor(scrollContent)
    panel._currentBuilder = builder
    builder:SetOnRefresh(function()
        Page.Render(panel, scrollContent)
    end)

    -- Read at call time, as the Aura List page reads the tracker namespace.
    local SAU = addon.ScootAuras
    local Bonus = SAU and SAU.Bonus
    local list = Bonus and Bonus.List() or {}

    -- A bonus aura's settings component registers only while the feature is on.
    if #list > 0 and not SAU.IsModuleActive() then
        builder:AddDescription(SAU.ModuleOffMessage(),
            { color = { 1, 0.82, 0 }, fontSize = 13, topPadding = 8 })
        builder:Finalize()
        return
    end

    for _, def in ipairs(list) do
        local build = sections[def.key]
        local componentId = Bonus.ComponentId(def.key)
        if build and componentId then
            builder:AddCollapsibleSection({
                title = def.title,
                componentId = Bonus.NAV_KEY,
                sectionKey = def.key,
                infoIcon = { tooltipTitle = def.title, tooltipText = def.info },
                buildContent = function(_, inner)
                    build(inner, componentId)
                end,
            })
        end
    end

    builder:Finalize()
end

-- The nav key both hosts' nav models carry (Bonus.NAV_KEY).
addon.UI.SettingsPanel:RegisterRenderer("bonusAuras", function(panel, scrollContent)
    Page.Render(panel, scrollContent)
end)

return Page
