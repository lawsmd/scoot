-- ClassResourceRenderer.lua - Personal Resource Display Class Resource settings renderer
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.Settings = addon.UI.Settings or {}
addon.UI.Settings.PRD = addon.UI.Settings.PRD or {}
addon.UI.Settings.PRD.ClassResource = {}

local ClassResource = addon.UI.Settings.PRD.ClassResource
local SettingsBuilder = addon.UI.SettingsBuilder

function ClassResource.Render(panel, scrollContent)
    panel:ClearContent()

    local builder = SettingsBuilder:CreateFor(scrollContent)
    panel._currentBuilder = builder

    builder:SetOnRefresh(function()
        ClassResource.Render(panel, scrollContent)
    end)

    local Helpers = addon.UI.Settings.Helpers
    local h = Helpers.CreateComponentHelpers("prdClassResource")
    local getComponent, getSetting = h.getComponent, h.get
    local setSetting = h.setAndApplyComponent

    ---------------------------------------------------------------------------
    -- Textures Section (DK / Mage)
    ---------------------------------------------------------------------------
    local _, playerClass = UnitClass("player")
    if playerClass == "DEATHKNIGHT" or playerClass == "MAGE" then
        local textureLabel = (playerClass == "DEATHKNIGHT") and "Rune Style"
            or (playerClass == "MAGE") and "Arcane Charge Style"
            or "Texture Style"
        builder:AddCollapsibleSection({
            title = "Textures",
            componentId = "prdClassResource",
            sectionKey = "textures",
            defaultExpanded = false,
            buildContent = function(contentFrame, inner)
                local textureKey = "textureStyle_" .. playerClass
                inner:AddSelector({
                    label = textureLabel,
                    values = { default = "Blizzard Default", pixel = "Pixel Art" },
                    order = { "default", "pixel" },
                    get = function() return getSetting(textureKey) or "default" end,
                    set = function(v) setSetting(textureKey, v or "default") end,
                })
                inner:Finalize()
            end,
        })
    end

    ---------------------------------------------------------------------------
    -- Sizing Section
    ---------------------------------------------------------------------------
    builder:AddCollapsibleSection({
        title = "Sizing",
        componentId = "prdClassResource",
        sectionKey = "sizing",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddSlider({
                label = "Scale",
                min = 50, max = 150, step = 1,
                get = function() return getSetting("scale") or 100 end,
                set = function(v) setSetting("scale", v) end,
                minLabel = "50%", maxLabel = "150%",
                infoIcon = {
                    tooltipTitle = "Class Resource Scale",
                    tooltipText = "Adjusts the size of the class resource display (combo points, runes, holy power, etc.).",
                },
            })

            inner:Finalize()
        end,
    })

    ---------------------------------------------------------------------------
    -- Visibility Section
    ---------------------------------------------------------------------------
    builder:AddCollapsibleSection({
        title = "Visibility",
        componentId = "prdClassResource",
        sectionKey = "visibility",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddToggle({
                label = "Hide Class Resource",
                get = function() return getSetting("hideBar") or false end,
                set = function(v) setSetting("hideBar", v) end,
            })

            inner:AddSpacer(12)

            inner:AddSlider({
                label = "Opacity in Combat",
                min = 1, max = 100, step = 1,
                get = function() return getSetting("opacityInCombat") or 100 end,
                set = function(v)
                    setSetting("opacityInCombat", v)
                    if addon.RefreshPRDOpacity then addon.RefreshPRDOpacity("prdClassResource") end
                end,
                minLabel = "1%", maxLabel = "100%",
                infoIcon = {
                    tooltipTitle = "Opacity Priority",
                    tooltipText = "With Target takes precedence, then In Combat, then Out of Combat. The highest priority condition that applies determines the opacity.",
                },
            })

            inner:AddSlider({
                label = "Opacity with Target",
                min = 1, max = 100, step = 1,
                get = function() return getSetting("opacityWithTarget") or 100 end,
                set = function(v)
                    setSetting("opacityWithTarget", v)
                    if addon.RefreshPRDOpacity then addon.RefreshPRDOpacity("prdClassResource") end
                end,
                minLabel = "1%", maxLabel = "100%",
            })

            inner:AddSlider({
                label = "Opacity Out of Combat",
                min = 1, max = 100, step = 1,
                get = function() return getSetting("opacityOutOfCombat") or 100 end,
                set = function(v)
                    setSetting("opacityOutOfCombat", v)
                    if addon.RefreshPRDOpacity then addon.RefreshPRDOpacity("prdClassResource") end
                end,
                minLabel = "1%", maxLabel = "100%",
            })

            inner:Finalize()
        end,
    })

    builder:Finalize()
end

addon.UI.SettingsPanel:RegisterRenderer("prdClassResource", function(panel, scrollContent)
    ClassResource.Render(panel, scrollContent)
end)

return ClassResource
