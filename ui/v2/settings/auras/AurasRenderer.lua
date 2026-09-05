-- AurasRenderer.lua - Buffs and Debuffs settings renderers
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.Settings = addon.UI.Settings or {}
addon.UI.Settings.Auras = addon.UI.Settings.Auras or {}

local SettingsBuilder = addon.UI.SettingsBuilder

local AURAS = {
    {
        componentId = "buffs", noun = "buff",
        iconLimit = { min = 2, max = 32, default = 11 },
        hasBorderSection = true, hasCollapseToggle = true,
        miscTitle = "Visibility & Misc",
    },
    {
        componentId = "debuffs", noun = "debuff",
        iconLimit = { min = 1, max = 16, default = 8 },
        miscTitle = "Visibility",
    },
}

local function CreateRenderer(aura)
    local COMPONENT_ID = aura.componentId

    local function render(panel, scrollContent)
        panel:ClearContent()

        local builder = SettingsBuilder:CreateFor(scrollContent)
        panel._currentBuilder = builder

        builder:SetOnRefresh(function()
            render(panel, scrollContent)
        end)

        local Helpers = addon.UI.Settings.Helpers
        local h = Helpers.CreateComponentHelpers(COMPONENT_ID)
        local getComponent, getSetting, setSetting = h.getComponent, h.get, h.set
        local syncEditModeSetting = h.sync

        local function applyStyles()
            if addon.BumpAuraConfigVersion then
                addon.BumpAuraConfigVersion(COMPONENT_ID)
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
            componentId = COMPONENT_ID,
            sectionKey = "positioning",
            defaultExpanded = false,
            buildContent = function(contentFrame, inner)
                inner:AddSelector({
                    key = "orientation",
                    label = "Orientation",
                    description = "Horizontal arranges icons left-to-right, Vertical arranges top-to-bottom.",
                    values = addon.Catalogs.Orientation.values,
                    order = addon.Catalogs.Orientation.order,
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
                    description = "Space between " .. aura.noun .. " icons in pixels.",
                    min = 5,
                    max = 15,
                    step = 1,
                    get = function() return getSetting("iconPadding") or 10 end,
                    set = function(v) setSetting("iconPadding", v) end,
                    minLabel = "5px",
                    maxLabel = "15px",
                    debounceKey = "UI_" .. COMPONENT_ID .. "_iconPadding",
                    debounceDelay = 0.2,
                    onEditModeSync = function()
                        syncEditModeSetting("iconPadding")
                    end,
                })

                inner:AddSlider({
                    label = "Icon Limit",
                    description = "Maximum number of " .. aura.noun .. " icons to display.",
                    min = aura.iconLimit.min,
                    max = aura.iconLimit.max,
                    step = 1,
                    get = function() return getSetting("iconLimit") or aura.iconLimit.default end,
                    set = function(v) setSetting("iconLimit", v) end,
                    minLabel = tostring(aura.iconLimit.min),
                    maxLabel = tostring(aura.iconLimit.max),
                    debounceKey = "UI_" .. COMPONENT_ID .. "_iconLimit",
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
            componentId = COMPONENT_ID,
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
                    debounceKey = "UI_" .. COMPONENT_ID .. "_iconSize",
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

        -- Border section: buffs only - debuffs use Blizzard's red DebuffBorder
        if aura.hasBorderSection then
            builder:AddCollapsibleSection({
                title = "Border",
                componentId = COMPONENT_ID,
                sectionKey = "border",
                defaultExpanded = false,
                buildContent = function(contentFrame, inner)
                    local get, set = Helpers.CreateIconBorderAccessors(getSetting, setSetting, "border")
                    inner:AddIconBorderBlock({
                        get = get, set = set, apply = applyStyles,
                        enableToggle = { description = "Enable custom border styling for buff icons." },
                        style = { description = "Choose the visual style for icon borders." },
                        tint = { description = "Apply a custom tint color to the icon border." },
                        thickness = { description = "Thickness of the border in pixels." },
                        inset = false,
                    })

                    inner:Finalize()
                end,
            })
        end

        -- Collapsible section: Text (tabbed for Stacks and Duration)
        builder:AddCollapsibleSection({
            title = "Text",
            componentId = COMPONENT_ID,
            sectionKey = "text",
            defaultExpanded = false,
            buildContent = function(contentFrame, inner)
                inner:AddTabbedSection({
                    tabs = {
                        { key = "stacks", label = "Stacks" },
                        { key = "duration", label = "Duration" },
                    },
                    componentId = COMPONENT_ID,
                    sectionKey = "textTabs",
                    buildContent = {
                        stacks = function(tabContent, tabBuilder)
                            -- Stack and duration text are Blizzard FontStrings on
                            -- the aura buttons styled in place, so the plain style
                            -- order applies (no paired Deep Shadow styles).
                            local s = Helpers.CreateSubTableHelpers(COMPONENT_ID, "textStacks", { apply = applyStyles })
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
                            local s = Helpers.CreateSubTableHelpers(COMPONENT_ID, "textDuration", { apply = applyStyles })
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
            title = aura.miscTitle,
            componentId = COMPONENT_ID,
            sectionKey = "misc",
            defaultExpanded = false,
            buildContent = function(contentFrame, inner)
                local get, set = Helpers.CreateFlatAccessors(getSetting, setSetting, addon.Opacity.Keys.Plain)
                inner:AddStateOpacityBlock({ get = get, set = set, apply = applyStyles, combatMin = 50 })

                if aura.hasCollapseToggle then
                    inner:AddToggle({
                        label = "Hide Expand/Collapse Button",
                        description = "Hide the button that expands or collapses the buff frame.",
                        get = function() return getSetting("hideCollapseButton") or false end,
                        set = function(val)
                            setSetting("hideCollapseButton", val)
                            applyStyles()
                        end,
                    })
                end

                inner:Finalize()
            end,
        })

        builder:Finalize()
    end

    return render
end

for _, aura in ipairs(AURAS) do
    addon.UI.SettingsPanel:RegisterRenderer(aura.componentId, CreateRenderer(aura))
end
