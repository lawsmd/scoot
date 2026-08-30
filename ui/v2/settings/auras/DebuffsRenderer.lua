-- DebuffsRenderer.lua - Debuffs settings renderer
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.Settings = addon.UI.Settings or {}
addon.UI.Settings.Auras = addon.UI.Settings.Auras or {}
addon.UI.Settings.Auras.Debuffs = {}

local Debuffs = addon.UI.Settings.Auras.Debuffs
local SettingsBuilder = addon.UI.SettingsBuilder

function Debuffs.Render(panel, scrollContent)
    panel:ClearContent()

    local builder = SettingsBuilder:CreateFor(scrollContent)
    panel._currentBuilder = builder

    builder:SetOnRefresh(function()
        Debuffs.Render(panel, scrollContent)
    end)

    local Helpers = addon.UI.Settings.Helpers
    local h = Helpers.CreateComponentHelpers("debuffs")
    local getComponent, getSetting, setSetting = h.getComponent, h.get, h.set
    local syncEditModeSetting = h.sync

    local function applyStyles()
        if addon.BumpAuraConfigVersion then
            addon.BumpAuraConfigVersion("debuffs")
        end
        if addon and addon.ApplyAuraFrameVisualsFor then
            C_Timer.After(0, function()
                local comp = getComponent()
                if comp then
                    addon.ApplyAuraFrameVisualsFor(comp)
                end
            end)
        end
    end

    -- Collapsible section: Positioning
    builder:AddCollapsibleSection({
        title = "Positioning",
        componentId = "debuffs",
        sectionKey = "positioning",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            local orientationValues = { H = "Horizontal", V = "Vertical" }
            local orientationOrder = { "H", "V" }

            inner:AddSelector({
                key = "orientation",
                label = "Orientation",
                description = "Horizontal arranges icons left-to-right, Vertical arranges top-to-bottom.",
                values = orientationValues,
                order = orientationOrder,
                get = function() return getSetting("orientation") or "H" end,
                set = function(v)
                    setSetting("orientation", v)
                    syncEditModeSetting("orientation")
                end,
                syncCooldown = 0.4,
            })

            local wrapValues = { down = "Down", up = "Up" }
            local wrapOrder = { "down", "up" }

            inner:AddSelector({
                key = "iconWrap",
                label = "Icon Wrap",
                description = "Direction icons wrap when reaching the limit per row/column.",
                values = wrapValues,
                order = wrapOrder,
                get = function() return getSetting("iconWrap") or "down" end,
                set = function(v)
                    setSetting("iconWrap", v)
                    syncEditModeSetting("iconWrap")
                end,
                syncCooldown = 0.4,
            })

            local dirValues = { left = "Left", right = "Right" }
            local dirOrder = { "left", "right" }

            inner:AddSelector({
                key = "direction",
                label = "Icon Direction",
                description = "Direction icons grow from the anchor point.",
                values = dirValues,
                order = dirOrder,
                get = function() return getSetting("direction") or "left" end,
                set = function(v)
                    setSetting("direction", v)
                    syncEditModeSetting("direction")
                end,
                syncCooldown = 0.4,
            })

            inner:AddSlider({
                label = "Icon Padding",
                description = "Space between debuff icons in pixels.",
                min = 5,
                max = 15,
                step = 1,
                get = function() return getSetting("iconPadding") or 10 end,
                set = function(v) setSetting("iconPadding", v) end,
                minLabel = "5px",
                maxLabel = "15px",
                debounceKey = "UI_debuffs_iconPadding",
                debounceDelay = 0.2,
                onEditModeSync = function()
                    syncEditModeSetting("iconPadding")
                end,
            })

            inner:AddSlider({
                label = "Icon Limit",
                description = "Maximum number of debuff icons to display.",
                min = 1,
                max = 16,
                step = 1,
                get = function() return getSetting("iconLimit") or 8 end,
                set = function(v) setSetting("iconLimit", v) end,
                minLabel = "1",
                maxLabel = "16",
                debounceKey = "UI_debuffs_iconLimit",
                debounceDelay = 0.2,
                onEditModeSync = function()
                    syncEditModeSetting("iconLimit")
                end,
            })

            inner:Finalize()
        end,
    })

    -- Collapsible section: Sizing
    builder:AddCollapsibleSection({
        title = "Sizing",
        componentId = "debuffs",
        sectionKey = "sizing",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddSlider({
                label = "Icon Size (Scale)",
                description = "Scale the icons in Edit Mode (50-200%).",
                min = 50,
                max = 200,
                step = 10,
                get = function() return getSetting("iconSize") or 100 end,
                set = function(v) setSetting("iconSize", v) end,
                minLabel = "50%",
                maxLabel = "200%",
                debounceKey = "UI_debuffs_iconSize",
                debounceDelay = 0.2,
                onEditModeSync = function()
                    syncEditModeSetting("iconSize")
                end,
            })

            inner:AddSlider({
                label = "Icon Shape",
                description = "Adjust icon aspect ratio. Center = square icons.",
                min = -67,
                max = 67,
                step = 1,
                get = function() return getSetting("tallWideRatio") or 0 end,
                set = function(v)
                    setSetting("tallWideRatio", v)
                    applyStyles()
                end,
                minLabel = "Wide",
                maxLabel = "Tall",
            })

            inner:Finalize()
        end,
    })

    -- Note: Debuffs do NOT have a Border section - they use Blizzard's red DebuffBorder

    -- Collapsible section: Text (tabbed for Stacks and Duration)
    builder:AddCollapsibleSection({
        title = "Text",
        componentId = "debuffs",
        sectionKey = "text",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddTabbedSection({
                tabs = {
                    { key = "stacks", label = "Stacks" },
                    { key = "duration", label = "Duration" },
                },
                componentId = "debuffs",
                sectionKey = "textTabs",
                buildContent = {
                    stacks = function(tabContent, tabBuilder)
                        -- Stack and duration text are Blizzard FontStrings on
                        -- the aura buttons styled in place, so the plain style
                        -- order applies (no paired Deep Shadow styles).
                        local s = Helpers.CreateSubTableHelpers("debuffs", "textStacks", { apply = applyStyles })
                        tabBuilder:AddTextStyleBlock({
                            get = s.get, set = s.set, apply = applyStyles,
                            defaults = { size = 16 },
                            font = { description = "The font used for stack count text." },
                            size = { min = 6, max = 32, minLabel = "6", maxLabel = "32" },
                            color = { kind = "plain" },
                            offset = { range = 50 },
                        })
                        tabBuilder:Finalize()
                    end,
                    duration = function(tabContent, tabBuilder)
                        local s = Helpers.CreateSubTableHelpers("debuffs", "textDuration", { apply = applyStyles })
                        tabBuilder:AddTextStyleBlock({
                            get = s.get, set = s.set, apply = applyStyles,
                            font = { description = "The font used for remaining time text." },
                            size = { min = 6, max = 32, minLabel = "6", maxLabel = "32" },
                            color = { kind = "plain" },
                            offset = { range = 50 },
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
        componentId = "debuffs",
        sectionKey = "misc",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddSlider({
                label = "Opacity in Combat",
                description = "Opacity when in combat (50-100%).",
                min = 50,
                max = 100,
                step = 1,
                get = function() return getSetting("opacity") or 100 end,
                set = function(v)
                    setSetting("opacity", v)
                    applyStyles()
                end,
                minLabel = "50%",
                maxLabel = "100%",
                infoIcon = {
                    tooltipTitle = "Opacity Priority",
                    tooltipText = "With Target takes precedence, then In Combat, then Out of Combat.",
                },
            })

            inner:AddSlider({
                label = "Opacity Out of Combat",
                description = "Opacity when not in combat.",
                min = 1,
                max = 100,
                step = 1,
                get = function() return getSetting("opacityOutOfCombat") or 100 end,
                set = function(v)
                    setSetting("opacityOutOfCombat", v)
                    applyStyles()
                end,
                minLabel = "1%",
                maxLabel = "100%",
            })

            inner:AddSlider({
                label = "Opacity With Target",
                description = "Opacity when you have a target.",
                min = 1,
                max = 100,
                step = 1,
                get = function() return getSetting("opacityWithTarget") or 100 end,
                set = function(v)
                    setSetting("opacityWithTarget", v)
                    applyStyles()
                end,
                minLabel = "1%",
                maxLabel = "100%",
            })

            inner:Finalize()
        end,
    })

    builder:Finalize()
end

addon.UI.SettingsPanel:RegisterRenderer("debuffs", function(panel, scrollContent)
    Debuffs.Render(panel, scrollContent)
end)

return Debuffs
