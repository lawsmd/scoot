-- GeneralRenderer.lua - Personal Resource Display General settings renderer
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.Settings = addon.UI.Settings or {}
addon.UI.Settings.PRD = addon.UI.Settings.PRD or {}
addon.UI.Settings.PRD.General = {}

local General = addon.UI.Settings.PRD.General
local SettingsBuilder = addon.UI.SettingsBuilder
local Helpers = addon.UI.Settings.Helpers

--------------------------------------------------------------------------------
-- Render Function
--------------------------------------------------------------------------------

function General.Render(panel, scrollContent)
    panel:ClearContent()

    local builder = SettingsBuilder:CreateFor(scrollContent)
    panel._currentBuilder = builder

    builder:SetOnRefresh(function()
        General.Render(panel, scrollContent)
    end)

    -- CVar helpers
    local function getPRDEnabledFromCVar()
        if GetCVarBool then
            return GetCVarBool("nameplateShowSelf")
        end
        if C_CVar and C_CVar.GetCVar then
            return C_CVar.GetCVar("nameplateShowSelf") == "1"
        end
        return false
    end

    -- Profile data helpers
    local function getProfilePRDSettings()
        local profile = addon and addon.db and addon.db.profile
        return profile and profile.prdSettings
    end

    local function ensureProfilePRDSettings()
        if not (addon and addon.db and addon.db.profile) then return nil end
        addon.db.profile.prdSettings = addon.db.profile.prdSettings or {}
        return addon.db.profile.prdSettings
    end

    builder:AddToggle({
        label = "Enable Personal Resource Display",
        description = "Show or hide the Personal Resource Display on this profile. Overrides Blizzard's per-character setting in Options > Gameplay > Interface.",
        emphasized = true,
        get = function()
            local s = getProfilePRDSettings()
            if s and s.enablePRD ~= nil then
                return s.enablePRD
            end
            return getPRDEnabledFromCVar()
        end,
        set = function(value)
            local s = ensureProfilePRDSettings()
            if not s then return end
            s.enablePRD = value
            if addon.ApplyPRDEnabled then
                addon.ApplyPRDEnabled("toggle")
            end
            -- Re-apply styling on enable; the applier queues the disable re-apply itself
            if value and addon and addon.ApplyStyles then
                if C_Timer and C_Timer.After then
                    C_Timer.After(0, function()
                        if addon and addon.ApplyStyles then
                            addon:ApplyStyles()
                        end
                    end)
                else
                    addon:ApplyStyles()
                end
            end
        end,
    })

    ---------------------------------------------------------------------------
    -- Display: Blizzard's PRD-wide Edit Mode settings, kept in sync both ways
    -- (personal_resource_display/editmode.lua). Native applies them; Scoot stores
    -- the value and pushes it on change.
    ---------------------------------------------------------------------------
    local h = Helpers.CreateComponentHelpers("prdGlobal")
    local getSetting = h.get
    local setSetting = h.setAndApplyComponent
    local syncEditModeSetting = h.sync

    builder:AddCollapsibleSection({
        title = "Display",
        componentId = "prdGlobal",
        sectionKey = "display",
        defaultExpanded = true,
        infoIcon = {
            tooltipTitle = "Edit Mode Settings",
            tooltipText = "These are Blizzard's Edit Mode settings for the Personal Resource Display. Changing them here or inside Edit Mode keeps both in step.",
        },
        buildContent = function(contentFrame, inner)
            inner:AddSelector({
                label = "Visibility",
                description = "When the Personal Resource Display is shown.",
                values = {
                    always = "Always",
                    combat = "Only in Combat",
                    never = "Hidden",
                },
                order = { "always", "combat", "never" },
                get = function() return getSetting("visibleSetting") or "always" end,
                set = function(v)
                    setSetting("visibleSetting", v or "always")
                    syncEditModeSetting("visibleSetting")
                end,
            })

            inner:AddSlider({
                label = "Scale",
                min = 70, max = 150, step = 10,
                get = function() return getSetting("scale") or 100 end,
                set = function(v) setSetting("scale", v) end,
                minLabel = "70%", maxLabel = "150%",
                debounceKey = "UI_prdGlobal_scale",
                debounceDelay = 0.2,
                onEditModeSync = function() syncEditModeSetting("scale") end,
            })

            inner:AddSlider({
                label = "Bar Width",
                min = 50, max = 150, step = 10,
                get = function() return getSetting("barWidth") or 100 end,
                set = function(v) setSetting("barWidth", v) end,
                minLabel = "50%", maxLabel = "150%",
                debounceKey = "UI_prdGlobal_barWidth",
                debounceDelay = 0.2,
                onEditModeSync = function() syncEditModeSetting("barWidth") end,
                infoIcon = {
                    tooltipTitle = "Bar Width",
                    tooltipText = "Width of every bar in the Personal Resource Display, as a percentage of Blizzard's default width.",
                },
            })

            inner:AddSlider({
                label = "Bar Spacing",
                min = 0, max = 10, step = 1,
                get = function() return getSetting("barPadding") or 0 end,
                set = function(v) setSetting("barPadding", v) end,
                minLabel = "0", maxLabel = "10",
                debounceKey = "UI_prdGlobal_barPadding",
                debounceDelay = 0.2,
                onEditModeSync = function() syncEditModeSetting("barPadding") end,
                infoIcon = {
                    tooltipTitle = "Bar Spacing",
                    tooltipText = "Extra gap between the health, power, alternate power and class resource rows.",
                },
            })

            inner:AddSlider({
                label = "Opacity",
                min = 50, max = 100, step = 1,
                get = function() return getSetting("opacity") or 100 end,
                set = function(v) setSetting("opacity", v) end,
                minLabel = "50%", maxLabel = "100%",
                debounceKey = "UI_prdGlobal_opacity",
                debounceDelay = 0.2,
                onEditModeSync = function() syncEditModeSetting("opacity") end,
                infoIcon = {
                    tooltipTitle = "Opacity",
                    tooltipText = "Blizzard's opacity for the whole Personal Resource Display. Each bar's own In Combat / With Target / Out of Combat opacity (under Visibility) multiplies on top of it.",
                },
            })

            inner:Finalize()
        end,
    })

    builder:Finalize()
end

--------------------------------------------------------------------------------
-- Self-register with settings panel
addon.UI.SettingsPanel:RegisterRenderer("prdGeneral", function(panel, scrollContent)
    General.Render(panel, scrollContent)
end)

-- Return module
--------------------------------------------------------------------------------

return General
