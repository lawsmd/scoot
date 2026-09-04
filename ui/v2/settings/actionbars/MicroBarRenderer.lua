-- MicroBarRenderer.lua - Micro Bar settings renderer
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.Settings = addon.UI.Settings or {}
addon.UI.Settings.MicroBar = {}

local MicroBar = addon.UI.Settings.MicroBar
local SettingsBuilder = addon.UI.SettingsBuilder

--------------------------------------------------------------------------------
-- Render Function
--------------------------------------------------------------------------------

function MicroBar.Render(panel, scrollContent)
    panel:ClearContent()

    local builder = SettingsBuilder:CreateFor(scrollContent)
    panel._currentBuilder = builder

    builder:SetOnRefresh(function()
        MicroBar.Render(panel, scrollContent)
    end)

    local Helpers = addon.UI.Settings.Helpers
    local h = Helpers.CreateComponentHelpers("microBar")
    local getComponent, getSetting = h.getComponent, h.get
    local setSetting = h.setAndApply
    local syncEditModeSetting = h.sync

    ---------------------------------------------------------------------------
    -- Positioning Section
    ---------------------------------------------------------------------------
    builder:AddCollapsibleSection({
        title = "Positioning",
        componentId = "microBar",
        sectionKey = "positioning",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddSelector({
                label = "Orientation",
                values = addon.Catalogs.Orientation.values,
                order = addon.Catalogs.Orientation.order,
                get = function() return getSetting("orientation") or "H" end,
                set = function(v)
                    setSetting("orientation", v)
                    syncEditModeSetting("orientation")
                end,
                syncCooldown = 0.5,
            })

            inner:AddSelector({
                label = "Direction",
                values = {
                    left = "Left",
                    right = "Right",
                    up = "Up",
                    down = "Down",
                },
                order = { "left", "right", "up", "down" },
                get = function() return getSetting("direction") or "right" end,
                set = function(v)
                    setSetting("direction", v)
                    syncEditModeSetting("direction")
                end,
                syncCooldown = 0.5,
            })

            inner:Finalize()
        end,
    })

    ---------------------------------------------------------------------------
    -- Sizing Section
    ---------------------------------------------------------------------------
    builder:AddCollapsibleSection({
        title = "Sizing",
        componentId = "microBar",
        sectionKey = "sizing",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddSlider({
                label = "Menu Size (Scale)", min = 70, max = 200, step = 5,
                get = function() return getSetting("menuSize") or 100 end,
                set = function(v) setSetting("menuSize", v) end,
                debounceKey = "microBar_menuSize",
                debounceDelay = 0.3,
                onEditModeSync = function() syncEditModeSetting("menuSize") end,
                minLabel = "70%", maxLabel = "200%",
            })

            inner:AddSlider({
                label = "Eye Size", min = 50, max = 150, step = 5,
                get = function() return getSetting("eyeSize") or 100 end,
                set = function(v) setSetting("eyeSize", v) end,
                debounceKey = "microBar_eyeSize",
                debounceDelay = 0.3,
                onEditModeSync = function() syncEditModeSetting("eyeSize") end,
                minLabel = "50%", maxLabel = "150%",
            })

            inner:Finalize()
        end,
    })

    ---------------------------------------------------------------------------
    -- Visibility Section
    ---------------------------------------------------------------------------
    builder:AddCollapsibleSection({
        title = "Visibility",
        componentId = "microBar",
        sectionKey = "visibility",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            local get, set = Helpers.CreateFlatAccessors(getSetting, setSetting, addon.Opacity.Keys.Bar)
            inner:AddStateOpacityBlock({ get = get, set = set })

            inner:AddToggle({
                label = "Mouseover Mode",
                get = function() return getSetting("mouseoverMode") or false end,
                set = function(v) setSetting("mouseoverMode", v) end,
            })

            inner:Finalize()
        end,
    })

    builder:Finalize()
end

--------------------------------------------------------------------------------
-- Self-register with settings panel
addon.UI.SettingsPanel:RegisterRenderer("microBar", function(panel, scrollContent)
    MicroBar.Render(panel, scrollContent)
end)

-- Return module
--------------------------------------------------------------------------------

return MicroBar
