-- CustomGroupsRenderer.lua - Parameterized settings renderer for Custom CDM Groups 1-5
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.Settings = addon.UI.Settings or {}
addon.UI.Settings.CDM = addon.UI.Settings.CDM or {}
addon.UI.Settings.CDM.CustomGroups = {}

local CustomGroups = addon.UI.Settings.CDM.CustomGroups
local SettingsBuilder = addon.UI.SettingsBuilder

--------------------------------------------------------------------------------
-- Factory: create a Render function for a given group index (1-5)
--------------------------------------------------------------------------------

local function CreateCustomGroupRenderer(groupIndex)
    local componentId = "customGroup" .. groupIndex

    return function(panel, scrollContent)
        local groupLabel = addon.CustomGroups and addon.CustomGroups.GetGroupDisplayName(groupIndex) or ("Custom Group " .. groupIndex)
        panel:ClearContent()

        local builder = SettingsBuilder:CreateFor(scrollContent)
        panel._currentBuilder = builder

        builder:SetOnRefresh(function()
            CustomGroups["RenderGroup" .. groupIndex](panel, scrollContent)
        end)

        local Helpers = addon.UI.Settings.Helpers
        local h = Helpers.CreateComponentHelpers(componentId)
        local getSetting = h.get

        -- Enable toggle
        builder:AddToggle({
            label = "Enable " .. groupLabel,
            description = "Show this group on the HUD and in Edit Mode.",
            emphasized = true,
            get = function() return getSetting("enabled") or false end,
            set = function(v)
                h.setAndApply("enabled", v)
                if addon.RefreshCustomGroupsTabVisibility then
                    addon.RefreshCustomGroupsTabVisibility()
                end
                builder:DeferredRefreshAll()
            end,
        })

        -- Preview
        builder:AddPreview({
            componentId = componentId,
            mode = "icon",
            borderPath = "customGroups",
            settingKeys = {
                iconShape = "tallWideRatio",
                _showCDMText = true,
            },
        })

        --------------------------------------------------------------------
        -- Layout
        --------------------------------------------------------------------
        builder:AddCollapsibleSection({
            title = "Positioning",
            componentId = componentId,
            sectionKey = "positioning",
            defaultExpanded = false,
            buildContent = function(contentFrame, inner)
                local OrientationPatterns = addon.UI.SettingPatterns.Orientation
                local currentOrientation = getSetting("orientation") or "H"
                local initialDirValues, initialDirOrder = OrientationPatterns.getDirectionOptions(currentOrientation)

                inner:AddSelector({
                    key = "anchorPosition",
                    label = "Edit Mode Anchor Position",
                    description = "Controls which edge of the group stays fixed when the icon count changes across characters. Changing this may require re-positioning in Edit Mode.",
                    values = {
                        left   = "Left",
                        right  = "Right",
                        center = "Center",
                        top    = "Top",
                        bottom = "Bottom",
                    },
                    order = { "left", "center", "right", "top", "bottom" },
                    get = function() return getSetting("anchorPosition") or "center" end,
                    set = function(v) h.setAndApply("anchorPosition", v) end,
                })

                inner:AddSelector({
                    key = "orientation",
                    label = "Orientation",
                    description = "Horizontal arranges icons left-to-right, Vertical arranges top-to-bottom.",
                    values = addon.Catalogs.Orientation.values,
                    order = addon.Catalogs.Orientation.order,
                    get = function() return getSetting("orientation") or "H" end,
                    set = function(v)
                        h.setAndApply("orientation", v)

                        -- Reset direction to valid default for new orientation
                        local newDefault = OrientationPatterns.getDefaultDirection(v)
                        local currentDir = getSetting("direction")
                        local validDirs = OrientationPatterns.getDirectionOptions(v)
                        if not validDirs[currentDir] then
                            h.setAndApply("direction", newDefault)
                        end

                        -- Dynamically update dependent controls
                        local dirSelector = inner:GetControl("iconDirection")
                        if dirSelector then
                            local newValues, newOrder = OrientationPatterns.getDirectionOptions(v)
                            dirSelector:SetOptions(newValues, newOrder)
                        end

                        local columnsSlider = inner:GetControl("columnsRows")
                        if columnsSlider then
                            columnsSlider:SetLabel(OrientationPatterns.getColumnsLabel(v))
                        end
                    end,
                })

                inner:AddSelector({
                    key = "iconDirection",
                    label = "Icon Direction",
                    description = "Direction icons grow from the anchor point.",
                    values = initialDirValues,
                    order = initialDirOrder,
                    get = function() return getSetting("direction") or OrientationPatterns.getDefaultDirection(currentOrientation) end,
                    set = function(v) h.setAndApply("direction", v) end,
                })

                inner:AddSlider({
                    key = "columnsRows",
                    label = OrientationPatterns.getColumnsLabel(currentOrientation),
                    description = "Number of icons per row (horizontal) or column (vertical) before wrapping.",
                    min = 1,
                    max = 20,
                    step = 1,
                    get = function() return getSetting("columns") or 12 end,
                    set = function(v) h.setAndApply("columns", v) end,
                    minLabel = "1",
                    maxLabel = "20",
                })

                inner:AddSlider({
                    label = "Icon Padding",
                    description = "Space between icons in pixels.",
                    min = 0,
                    max = 16,
                    step = 1,
                    get = function() return getSetting("iconPadding") or 2 end,
                    set = function(v) h.setAndApply("iconPadding", v) end,
                    minLabel = "0px",
                    maxLabel = "16px",
                })

                inner:Finalize()
            end,
        })

        --------------------------------------------------------------------
        -- Sizing
        --------------------------------------------------------------------
        builder:AddCollapsibleSection({
            title = "Sizing",
            componentId = componentId,
            sectionKey = "sizing",
            defaultExpanded = false,
            buildContent = function(contentFrame, inner)
                inner:AddSlider({
                    label = "Icon Size",
                    description = "Size of each icon in pixels (16-64).",
                    min = 16,
                    max = 64,
                    step = 1,
                    get = function() return getSetting("iconSize") or 30 end,
                    set = function(v) h.setAndApply("iconSize", v) end,
                    minLabel = "16px",
                    maxLabel = "64px",
                })

                inner:AddSlider({
                    label = "Icon Shape",
                    description = "Adjust icon aspect ratio. Center = square icons.",
                    min = -67,
                    max = 67,
                    step = 1,
                    get = function() return getSetting("tallWideRatio") or 0 end,
                    set = function(v) h.setAndApply("tallWideRatio", v) builder:DeferredRefreshAll() end,
                    minLabel = "Wide",
                    maxLabel = "Tall",
                })

                inner:Finalize()
            end,
        })

        --------------------------------------------------------------------
        -- Icons
        --------------------------------------------------------------------
        builder:AddCollapsibleSection({
            title = "Icons",
            componentId = componentId,
            sectionKey = "icons",
            defaultExpanded = false,
            buildContent = function(contentFrame, inner)
                inner:AddSlider({
                    label = "Icon Zoom",
                    description = "Crops icon edges inward. Adds to the baseline border-art removal crop.",
                    min = 0, max = 30, step = 1,
                    get = function() return getSetting("iconZoom") or 0 end,
                    set = function(v) h.setAndApply("iconZoom", v) end,
                    minLabel = "0%", maxLabel = "30%",
                })

                inner:Finalize()
            end,
        })

        --------------------------------------------------------------------
        -- Border
        --------------------------------------------------------------------
        builder:AddCollapsibleSection({
            title = "Border",
            componentId = componentId,
            sectionKey = "border",
            defaultExpanded = false,
            buildContent = function(contentFrame, inner)
                local borderStyleValues, borderStyleOrder = Helpers.getIconBorderOptions({ { "none", "None" } })

                inner:AddSelector({
                    key = "borderStyle",
                    label = "Border Style",
                    description = "Choose the visual style for icon borders.",
                    values = borderStyleValues,
                    order = borderStyleOrder,
                    get = function()
                        if not getSetting("borderEnable") then return "none" end
                        return getSetting("borderStyle") or "square"
                    end,
                    set = function(v)
                        if v == "none" then
                            h.set("borderEnable", false)
                            h.setAndApply("borderStyle", "none")
                        else
                            h.set("borderEnable", true)
                            h.setAndApply("borderStyle", v)
                        end
                        builder:DeferredRefreshAll()
                    end,
                })

                inner:AddToggleColorPicker({
                    label = "Border Tint",
                    description = "Apply a custom tint color to the icon border.",
                    get = function() return getSetting("borderTintEnable") or false end,
                    set = function(val) h.setAndApply("borderTintEnable", val) builder:DeferredRefreshAll() end,
                    getColor = function()
                        local c = getSetting("borderTintColor")
                        if c then
                            return c.r or c[1] or 1, c.g or c[2] or 1, c.b or c[3] or 1, c.a or c[4] or 1
                        end
                        return 1, 1, 1, 1
                    end,
                    setColor = function(r, g, b, a)
                        h.setAndApply("borderTintColor", {r, g, b, a})
                        builder:DeferredRefreshAll()
                    end,
                    hasAlpha = true,
                })

                -- Thickness only applies to the square style; atlas art has no edge width
                local currentBorderStyle = (not getSetting("borderEnable")) and "none"
                    or (getSetting("borderStyle") or "square")
                if addon.IconBorders.SupportsThickness(currentBorderStyle) then
                    inner:AddSlider({
                        label = "Border Thickness",
                        description = "Thickness of the border in pixels.",
                        min = 1,
                        max = 8,
                        step = 0.5,
                        precision = 1,
                        get = function() return getSetting("borderThickness") or 1 end,
                        set = function(v) h.setAndApply("borderThickness", v) builder:DeferredRefreshAll() end,
                        minLabel = "1",
                        maxLabel = "8",
                    })
                end

                inner:AddDualSlider({
                    label = "Border Inset",
                    sliderA = {
                        axisLabel = "H", min = -4, max = 4, step = 0.5, precision = 1,
                        get = function() return getSetting("borderInsetH") or getSetting("borderInset") or 0 end,
                        set = function(v) h.setAndApply("borderInsetH", v) builder:DeferredRefreshAll() end,
                        minLabel = "-4", maxLabel = "+4",
                    },
                    sliderB = {
                        axisLabel = "V", min = -4, max = 4, step = 0.5, precision = 1,
                        get = function() return getSetting("borderInsetV") or getSetting("borderInset") or 0 end,
                        set = function(v) h.setAndApply("borderInsetV", v) builder:DeferredRefreshAll() end,
                        minLabel = "-4", maxLabel = "+4",
                    },
                })

                inner:Finalize()
            end,
        })

        --------------------------------------------------------------------
        -- Text (Tabbed: Charges + Cooldowns, no Keybinds)
        --------------------------------------------------------------------
        builder:AddCollapsibleSection({
            title = "Text",
            componentId = componentId,
            sectionKey = "text",
            defaultExpanded = false,
            buildContent = function(contentFrame, inner)
                local function applyText()
                    h.setAndApply("_textDirty", true) -- trigger ApplyStyling
                    builder:DeferredRefreshAll()
                end

                inner:AddTabbedSection({
                    tabs = {
                        { key = "charges", label = "Charges" },
                        { key = "cooldowns", label = "Cooldowns" },
                        { key = "bindings", label = "Keybinds", infoIcon = {
                            tooltipTitle = "Keybind Labels",
                            tooltipText = "Addon-generated text showing your keybind for each ability. Enable with the toggle below.",
                        }},
                    },
                    componentId = componentId,
                    sectionKey = "textTabs",
                    buildContent = {
                        charges = function(tabContent, tabBuilder)
                            -- Charge text is a Scoot-created FontString
                            -- (icons.lua CountText), so the paired Deep
                            -- Shadow styles are offered here.
                            local s = Helpers.CreateSubTableHelpers(componentId, "textStacks", { apply = applyText })
                            tabBuilder:AddTextStyleBlock({
                                get = s.get, set = s.set, apply = applyText,
                                defaults = { size = 16 },
                                font = { description = "The font used for charges/stacks text." },
                                style = { order = Helpers.fontStyleOrderPaired },
                                size = { min = 6, max = 32, minLabel = "6", maxLabel = "32" },
                            })
                            tabBuilder:Finalize()
                        end,

                        cooldowns = function(tabContent, tabBuilder)
                            -- Cooldown countdown numbers are drawn by the
                            -- Blizzard Cooldown widget and styled in place,
                            -- so the plain style order applies.
                            local s = Helpers.CreateSubTableHelpers(componentId, "textCooldown", { apply = applyText })
                            tabBuilder:AddTextStyleBlock({
                                get = s.get, set = s.set, apply = applyText,
                                font = { description = "The font used for cooldown timer text." },
                                size = { min = 6, max = 32, minLabel = "6", maxLabel = "32" },
                            })
                            tabBuilder:Finalize()
                        end,

                        bindings = function(tabContent, tabBuilder)
                            local s = Helpers.CreateSubTableHelpers(componentId, "textBindings", { apply = applyText })

                            -- Enable toggle
                            tabBuilder:AddToggle({
                                label = "Show Keybinds",
                                description = "Display keybind text on cooldown icons.",
                                get = function() return not not s.get("enabled") end,
                                set = function(v) s.setAndApply("enabled", v) end,
                            })

                            -- Keybind text is Scoot-drawn, so the paired Deep
                            -- Shadow styles are offered here
                            tabBuilder:AddTextStyleBlock({
                                get = s.get, set = s.set, apply = applyText,
                                defaults = { size = 12 },
                                font = { description = "The font used for keybind text." },
                                style = { order = Helpers.fontStyleOrderPaired },
                                size = { min = 6, max = 32, minLabel = "6", maxLabel = "32" },
                                alignment = { kind = "anchor9", default = "TOPLEFT" },
                            })

                            tabBuilder:Finalize()
                        end,
                    },
                })

                inner:Finalize()
            end,
        })

        --------------------------------------------------------------------
        -- Visibility
        --------------------------------------------------------------------
        builder:AddCollapsibleSection({
            title = "Visibility & Misc",
            componentId = componentId,
            sectionKey = "misc",
            defaultExpanded = false,
            buildContent = function(contentFrame, inner)
                -- Priority system header + explainer (dynamic based on mode)
                local cdMode = getSetting("cooldownOpacityMode") or "onCooldown"
                local isOffCD = (cdMode == "offCooldown")
                local modeWord = isOffCD and "Off Cooldown" or "On Cooldown"

                inner:AddDescription("Priority System", { color = {1, 0.82, 0}, fontSize = 14, topPadding = 4 })
                inner:AddDescription("With Target > In Combat > Out of Combat. Only the highest active condition applies. "
                    .. modeWord .. " competes with the result \226\128\148 whichever is the stronger dim takes effect.", { color = {1, 0.82, 0}, topPadding = -8, bottomPadding = -4 })

                -- Mode selector: On Cooldown vs Off Cooldown
                inner:AddSelector({
                    label = "Reduce Opacity While...",
                    values = { onCooldown = "On Cooldown", offCooldown = "Off Cooldown" },
                    order = { "onCooldown", "offCooldown" },
                    get = function() return getSetting("cooldownOpacityMode") or "onCooldown" end,
                    set = function(v)
                        h.setAndApply("cooldownOpacityMode", v == "onCooldown" and nil or v)
                        builder:DeferredRefreshAll()
                    end,
                })

                -- Opacity slider(s): DualSlider (icon+text) for on-CD mode, single Slider for off-CD mode
                if isOffCD then
                    inner:AddSlider({
                        label = "Opacity While off Cooldown",
                        description = "Dim icons when ready (off cooldown).",
                        min = 0, max = 100, step = 1,
                        get = function() return getSetting("opacityOnCooldown") or 100 end,
                        set = function(v) h.setAndApply("opacityOnCooldown", v) end,
                        minLabel = "Hidden", maxLabel = "100%",
                    })
                else
                    inner:AddDualSlider({
                        label = "Opacity While on Cooldown",
                        description = "Dim icons when on cooldown. Text slider keeps the countdown timer readable.",
                        sliderA = {
                            axisLabel = "Icon",
                            min = 0, max = 100, step = 1,
                            get = function() return getSetting("opacityOnCooldown") or 100 end,
                            set = function(v) h.setAndApply("opacityOnCooldown", v) end,
                            minLabel = "Hidden", maxLabel = "100%",
                        },
                        sliderB = {
                            axisLabel = "Text",
                            min = 0, max = 100, step = 1,
                            get = function() return getSetting("opacityOnCooldownText") or 100 end,
                            set = function(v) h.setAndApply("opacityOnCooldownText", v) end,
                            minLabel = "Hidden", maxLabel = "100%",
                        },
                    })
                end

                inner:AddSlider({
                    label = "Opacity With Target",
                    description = "Opacity when you have a target.",
                    min = 0, max = 100, step = 1,
                    get = function() return getSetting("opacityWithTarget") or 100 end,
                    set = function(v) h.setAndApply("opacityWithTarget", v) end,
                    minLabel = "Hidden", maxLabel = "100%",
                })

                inner:AddSlider({
                    label = "Opacity in Combat",
                    description = "Opacity when in combat.",
                    min = 0, max = 100, step = 1,
                    get = function() return getSetting("opacity") or 100 end,
                    set = function(v) h.setAndApply("opacity", v) end,
                    minLabel = "Hidden", maxLabel = "100%",
                })

                inner:AddSlider({
                    label = "Opacity Out of Combat",
                    description = "Opacity when not in combat.",
                    min = 0, max = 100, step = 1,
                    get = function() return getSetting("opacityOutOfCombat") or 100 end,
                    set = function(v) h.setAndApply("opacityOutOfCombat", v) end,
                    minLabel = "Hidden", maxLabel = "100%",
                })

                inner:Finalize()
            end,
        })

        builder:Finalize()
    end
end

--------------------------------------------------------------------------------
-- Register renderers
--------------------------------------------------------------------------------

for i = 1, 5 do
    local renderFn = CreateCustomGroupRenderer(i)
    CustomGroups["RenderGroup" .. i] = renderFn

    addon.UI.SettingsPanel:RegisterRenderer("customGroup" .. i, function(panel, scrollContent)
        renderFn(panel, scrollContent)
    end)
end

return CustomGroups
