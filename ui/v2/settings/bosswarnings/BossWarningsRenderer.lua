-- BossWarningsRenderer.lua - Boss Warnings settings page
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.Settings = addon.UI.Settings or {}
addon.UI.Settings.BossWarnings = {}

local BossWarnings = addon.UI.Settings.BossWarnings
local SettingsBuilder = addon.UI.SettingsBuilder
local Helpers = addon.UI.Settings.Helpers

--------------------------------------------------------------------------------
-- Edit Mode Setting IDs
--------------------------------------------------------------------------------

local function getSettingEnum()
    local e = _G.Enum and _G.Enum.EditModeEncounterEventsSetting
    return e
end

--------------------------------------------------------------------------------
-- DB Helpers
--------------------------------------------------------------------------------

local function getDB()
    local profile = addon.db and addon.db.profile
    return profile and rawget(profile, "bossWarnings") or nil
end

local function setDB(key, value)
    if not addon.db or not addon.db.profile then return end
    if not addon.db.profile.bossWarnings then
        addon.db.profile.bossWarnings = {}
    end
    addon.db.profile.bossWarnings[key] = value
end

--------------------------------------------------------------------------------
-- Selector Values
--------------------------------------------------------------------------------

local visibilityValues = {
    ["0"] = "Always",
    ["1"] = "In Encounter",
}
local visibilityOrder = { "0", "1" }

local tooltipValues = {
    ["0"] = "Hidden",
    ["1"] = "Default",
    ["2"] = "Cursor",
}
local tooltipOrder = { "0", "1", "2" }

--------------------------------------------------------------------------------
-- Render Function
--------------------------------------------------------------------------------

function BossWarnings.Render(panel, scrollContent)
    panel:ClearContent()

    local builder = SettingsBuilder:CreateFor(scrollContent)
    panel._currentBuilder = builder

    builder:SetOnRefresh(function()
        BossWarnings.Render(panel, scrollContent)
    end)

    local e = getSettingEnum()
    if not e then
        builder:AddDescription("Boss Warning settings require the Encounter Events system (12.0+).")
        builder:Finalize()
        return
    end

    ----------------------------------------------------------------------------
    -- Size (top-level, outside collapsible sections)
    ----------------------------------------------------------------------------
    builder:AddSlider({
        label = "Size",
        description = "Overall scale of all boss warning frames.",
        min = 50,
        max = 200,
        step = 10,
        get = function()
            return addon.getBossWarningsSetting(e.OverallSize) or 100
        end,
        set = function(v)
            addon.setBossWarningsSetting(e.OverallSize, v)
        end,
        minLabel = "50%",
        maxLabel = "200%",
    })

    ----------------------------------------------------------------------------
    -- Section: Text
    ----------------------------------------------------------------------------
    builder:AddCollapsibleSection({
        title = "Text",
        componentId = "bossWarnings",
        sectionKey = "text",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            local get, set = Helpers.CreateFlatAccessors(
                function(key) local db = getDB(); return db and db[key] end,
                setDB,
                { fontFace = "textFontFace", style = "textFontStyle" })
            inner:AddTextStyleBlock({
                get = get, set = set,
                apply = function()
                    if addon.refreshBossWarningsText then
                        addon.refreshBossWarningsText()
                    end
                end,
                font = { description = "The font used for boss warning text. Applies to all severity levels." },
                style = { label = "Font Style", description = "Outline style for boss warning text." },
                size = false,
                color = false,
                offset = false,
            })

            inner:Finalize()
        end,
    })

    ----------------------------------------------------------------------------
    -- Section: Icons
    ----------------------------------------------------------------------------
    builder:AddCollapsibleSection({
        title = "Icons",
        componentId = "bossWarnings",
        sectionKey = "icons",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddSlider({
                label = "Icon Size",
                description = "Scale of the spell icons flanking the warning text.",
                min = 50,
                max = 200,
                step = 10,
                get = function()
                    return addon.getBossWarningsSetting(e.IconSize) or 100
                end,
                set = function(v)
                    addon.setBossWarningsSetting(e.IconSize, v)
                end,
                minLabel = "50%",
                maxLabel = "200%",
            })
            inner:Finalize()
        end,
    })

    ----------------------------------------------------------------------------
    -- Section: Visibility & Misc
    ----------------------------------------------------------------------------
    builder:AddCollapsibleSection({
        title = "Visibility & Misc",
        componentId = "bossWarnings",
        sectionKey = "visibilityMisc",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddSlider({
                label = "Opacity",
                description = "Transparency of boss warning frames.",
                min = 50,
                max = 100,
                step = 1,
                get = function()
                    return addon.getBossWarningsSetting(e.Transparency) or 100
                end,
                set = function(v)
                    addon.setBossWarningsSetting(e.Transparency, v)
                end,
                minLabel = "50%",
                maxLabel = "100%",
            })

            inner:AddSelector({
                label = "Visibility",
                description = "When boss warning frames are visible.",
                values = visibilityValues,
                order = visibilityOrder,
                get = function()
                    local v = addon.getBossWarningsSetting(e.Visibility)
                    return tostring(v or 0)
                end,
                set = function(v)
                    addon.setBossWarningsSetting(e.Visibility, tonumber(v) or 0)
                end,
            })

            inner:AddSelector({
                label = "Tooltips",
                description = "Tooltip display mode for boss warning icons.",
                values = tooltipValues,
                order = tooltipOrder,
                get = function()
                    local v = addon.getBossWarningsSetting(e.TooltipAnchor)
                    return tostring(v or 2)
                end,
                set = function(v)
                    addon.setBossWarningsSetting(e.TooltipAnchor, tonumber(v) or 2)
                end,
            })

            inner:Finalize()
        end,
    })

    builder:Finalize()
end

--------------------------------------------------------------------------------
-- Register Renderer
--------------------------------------------------------------------------------

addon.UI.SettingsPanel:RegisterRenderer("bwWarnings", function(panel, scrollContent)
    BossWarnings.Render(panel, scrollContent)
end)
