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
    -- Edit Mode mirror push (personal_resource_display/editmode.lua):
    -- hideBar (HideClassInfo), hideClassInfoOnPlayerFrame
    local syncEditModeSetting = h.sync

    ---------------------------------------------------------------------------
    -- Master Toggle: Hide Class Resource (mirrors Blizzard's Edit Mode setting)
    ---------------------------------------------------------------------------
    builder:AddToggle({
        label = "Hide Class Resource",
        description = "Removes the class resource (combo points, runes, holy power, etc.) from the Personal Resource Display. This is Blizzard's Edit Mode setting, kept in sync both ways.",
        emphasized = true,
        get = function() return getSetting("hideBar") or false end,
        set = function(v)
            setSetting("hideBar", v)
            syncEditModeSetting("hideBar")
        end,
    })

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
                label = "Hide on Player Frame",
                get = function() return getSetting("hideClassInfoOnPlayerFrame") or false end,
                set = function(v)
                    setSetting("hideClassInfoOnPlayerFrame", v)
                    syncEditModeSetting("hideClassInfoOnPlayerFrame")
                end,
                infoIcon = {
                    tooltipTitle = "Hide on Player Frame",
                    tooltipText = "Removes the class resource (combo points, runes, holy power, etc.) shown beneath your regular Player unit frame. This is separate from the Personal Resource Display above and does not affect it.",
                },
            })

            inner:AddSpacer(12)

            local get, set = Helpers.CreateFlatAccessors(getSetting, setSetting, addon.Opacity.Keys.InCombat)
            inner:AddStateOpacityBlock({
                get = get, set = set,
                apply = function()
                    if addon.RefreshPRDOpacity then addon.RefreshPRDOpacity("prdClassResource") end
                end,
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
