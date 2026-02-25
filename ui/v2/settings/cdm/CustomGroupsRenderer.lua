-- CustomGroupsRenderer.lua - Parameterized settings renderer for Custom CDM Groups 1-3
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.Settings = addon.UI.Settings or {}
addon.UI.Settings.CDM = addon.UI.Settings.CDM or {}
addon.UI.Settings.CDM.CustomGroups = {}

local CustomGroups = addon.UI.Settings.CDM.CustomGroups
local SettingsBuilder = addon.UI.SettingsBuilder

--------------------------------------------------------------------------------
-- Factory: create a Render function for a given group index (1-3)
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
        local getComponent, getSetting, setSetting = h.getComponent, h.get, h.set
        local textColorValues, textColorOrder = Helpers.textColorValues, Helpers.textColorOrder

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
                    values = { H = "Horizontal", V = "Vertical" },
                    order = { "H", "V" },
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
                    set = function(v) h.setAndApply("tallWideRatio", v) end,
                    minLabel = "Wide",
                    maxLabel = "Tall",
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
                inner:AddToggle({
                    key = "borderEnable",
                    label = "Use Custom Border",
                    description = "Enable custom border styling for cooldown icons.",
                    get = function() return getSetting("borderEnable") or false end,
                    set = function(val) h.setAndApply("borderEnable", val) end,
                })

                inner:AddToggleColorPicker({
                    label = "Border Tint",
                    description = "Apply a custom tint color to the icon border.",
                    get = function() return getSetting("borderTintEnable") or false end,
                    set = function(val) h.setAndApply("borderTintEnable", val) end,
                    getColor = function()
                        local c = getSetting("borderTintColor")
                        if c then
                            return c.r or c[1] or 1, c.g or c[2] or 1, c.b or c[3] or 1, c.a or c[4] or 1
                        end
                        return 1, 1, 1, 1
                    end,
                    setColor = function(r, g, b, a)
                        h.setAndApply("borderTintColor", {r, g, b, a})
                    end,
                    hasAlpha = true,
                })

                local borderStyleValues, borderStyleOrder = Helpers.getIconBorderOptions()

                inner:AddSelector({
                    key = "borderStyle",
                    label = "Border Style",
                    description = "Choose the visual style for icon borders.",
                    values = borderStyleValues,
                    order = borderStyleOrder,
                    get = function() return getSetting("borderStyle") or "square" end,
                    set = function(v) h.setAndApply("borderStyle", v) end,
                })

                inner:AddSlider({
                    label = "Border Thickness",
                    description = "Thickness of the border in pixels.",
                    min = 1,
                    max = 8,
                    step = 0.5,
                    precision = 1,
                    get = function() return getSetting("borderThickness") or 1 end,
                    set = function(v) h.setAndApply("borderThickness", v) end,
                    minLabel = "1",
                    maxLabel = "8",
                })

                inner:AddDualSlider({
                    label = "Border Inset",
                    sliderA = {
                        axisLabel = "H", min = -4, max = 4, step = 1,
                        get = function() return getSetting("borderInsetH") or getSetting("borderInset") or 0 end,
                        set = function(v) h.setAndApply("borderInsetH", v) end,
                        minLabel = "-4", maxLabel = "+4",
                    },
                    sliderB = {
                        axisLabel = "V", min = -4, max = 4, step = 1,
                        get = function() return getSetting("borderInsetV") or getSetting("borderInset") or 0 end,
                        set = function(v) h.setAndApply("borderInsetV", v) end,
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
                end

                local fontStyleValues = Helpers.fontStyleValues
                local fontStyleOrder = Helpers.fontStyleOrder

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
                            local function getStacksSetting(key, default)
                                return h.getSubSetting("textStacks", key, default)
                            end
                            local function setStacksSetting(key, value)
                                h.setSubSetting("textStacks", key, value)
                            end

                            tabBuilder:AddFontSelector({
                                label = "Font",
                                description = "The font used for charges/stacks text.",
                                get = function() return getStacksSetting("fontFace", "FRIZQT__") end,
                                set = function(v) setStacksSetting("fontFace", v) end,
                            })

                            tabBuilder:AddSlider({
                                label = "Font Size",
                                min = 6, max = 32, step = 1,
                                get = function() return getStacksSetting("size", 16) end,
                                set = function(v) setStacksSetting("size", v) end,
                                minLabel = "6", maxLabel = "32",
                            })

                            tabBuilder:AddSelector({
                                label = "Font Style",
                                values = fontStyleValues,
                                order = fontStyleOrder,
                                get = function() return getStacksSetting("style", "OUTLINE") end,
                                set = function(v) setStacksSetting("style", v) end,
                            })

                            tabBuilder:AddSelectorColorPicker({
                                label = "Font Color",
                                values = textColorValues,
                                order = textColorOrder,
                                get = function() return getStacksSetting("colorMode", "default") end,
                                set = function(v) setStacksSetting("colorMode", v or "default") end,
                                getColor = function()
                                    local c = getStacksSetting("color", {1,1,1,1})
                                    return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
                                end,
                                setColor = function(r, g, b, a)
                                    setStacksSetting("color", {r, g, b, a})
                                end,
                                customValue = "custom",
                                hasAlpha = true,
                            })

                            tabBuilder:AddDualSlider({
                                label = "Offset",
                                sliderA = {
                                    axisLabel = "X",
                                    min = -100, max = 100, step = 1,
                                    get = function()
                                        local offset = getStacksSetting("offset", {x=0, y=0})
                                        return offset.x or 0
                                    end,
                                    set = function(v)
                                        local comp = getComponent()
                                        if comp and comp.db then
                                            comp.db.textStacks = comp.db.textStacks or {}
                                            comp.db.textStacks.offset = comp.db.textStacks.offset or {}
                                            comp.db.textStacks.offset.x = v
                                        end
                                        applyText()
                                    end,
                                    minLabel = "-100", maxLabel = "+100",
                                },
                                sliderB = {
                                    axisLabel = "Y",
                                    min = -100, max = 100, step = 1,
                                    get = function()
                                        local offset = getStacksSetting("offset", {x=0, y=0})
                                        return offset.y or 0
                                    end,
                                    set = function(v)
                                        local comp = getComponent()
                                        if comp and comp.db then
                                            comp.db.textStacks = comp.db.textStacks or {}
                                            comp.db.textStacks.offset = comp.db.textStacks.offset or {}
                                            comp.db.textStacks.offset.y = v
                                        end
                                        applyText()
                                    end,
                                    minLabel = "-100", maxLabel = "+100",
                                },
                            })

                            tabBuilder:Finalize()
                        end,

                        cooldowns = function(tabContent, tabBuilder)
                            local function getCooldownSetting(key, default)
                                return h.getSubSetting("textCooldown", key, default)
                            end
                            local function setCooldownSetting(key, value)
                                h.setSubSetting("textCooldown", key, value)
                            end

                            tabBuilder:AddFontSelector({
                                label = "Font",
                                description = "The font used for cooldown timer text.",
                                get = function() return getCooldownSetting("fontFace", "FRIZQT__") end,
                                set = function(v) setCooldownSetting("fontFace", v) end,
                            })

                            tabBuilder:AddSlider({
                                label = "Font Size",
                                min = 6, max = 32, step = 1,
                                get = function() return getCooldownSetting("size", 14) end,
                                set = function(v) setCooldownSetting("size", v) end,
                                minLabel = "6", maxLabel = "32",
                            })

                            tabBuilder:AddSelector({
                                label = "Font Style",
                                values = fontStyleValues,
                                order = fontStyleOrder,
                                get = function() return getCooldownSetting("style", "OUTLINE") end,
                                set = function(v) setCooldownSetting("style", v) end,
                            })

                            tabBuilder:AddSelectorColorPicker({
                                label = "Font Color",
                                values = textColorValues,
                                order = textColorOrder,
                                get = function() return getCooldownSetting("colorMode", "default") end,
                                set = function(v) setCooldownSetting("colorMode", v or "default") end,
                                getColor = function()
                                    local c = getCooldownSetting("color", {1,1,1,1})
                                    return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
                                end,
                                setColor = function(r, g, b, a)
                                    setCooldownSetting("color", {r, g, b, a})
                                end,
                                customValue = "custom",
                                hasAlpha = true,
                            })

                            tabBuilder:AddDualSlider({
                                label = "Offset",
                                sliderA = {
                                    axisLabel = "X",
                                    min = -100, max = 100, step = 1,
                                    get = function()
                                        local offset = getCooldownSetting("offset", {x=0, y=0})
                                        return offset.x or 0
                                    end,
                                    set = function(v)
                                        local comp = getComponent()
                                        if comp and comp.db then
                                            comp.db.textCooldown = comp.db.textCooldown or {}
                                            comp.db.textCooldown.offset = comp.db.textCooldown.offset or {}
                                            comp.db.textCooldown.offset.x = v
                                        end
                                        applyText()
                                    end,
                                    minLabel = "-100", maxLabel = "+100",
                                },
                                sliderB = {
                                    axisLabel = "Y",
                                    min = -100, max = 100, step = 1,
                                    get = function()
                                        local offset = getCooldownSetting("offset", {x=0, y=0})
                                        return offset.y or 0
                                    end,
                                    set = function(v)
                                        local comp = getComponent()
                                        if comp and comp.db then
                                            comp.db.textCooldown = comp.db.textCooldown or {}
                                            comp.db.textCooldown.offset = comp.db.textCooldown.offset or {}
                                            comp.db.textCooldown.offset.y = v
                                        end
                                        applyText()
                                    end,
                                    minLabel = "-100", maxLabel = "+100",
                                },
                            })

                            tabBuilder:Finalize()
                        end,

                        bindings = function(tabContent, tabBuilder)
                            local function getBindingSetting(key, default)
                                return h.getSubSetting("textBindings", key, default)
                            end
                            local function setBindingSetting(key, value)
                                local comp = getComponent()
                                if comp and comp.db then
                                    comp.db.textBindings = comp.db.textBindings or {}
                                    comp.db.textBindings[key] = value
                                end
                                applyText()
                            end

                            tabBuilder:AddToggle({
                                label = "Show Keybinds",
                                description = "Display keybind text on cooldown icons.",
                                get = function() return getBindingSetting("enabled", false) end,
                                set = function(v) setBindingSetting("enabled", v) end,
                            })

                            tabBuilder:AddFontSelector({
                                label = "Font",
                                description = "The font used for keybind text.",
                                get = function() return getBindingSetting("fontFace", "FRIZQT__") end,
                                set = function(v) setBindingSetting("fontFace", v) end,
                            })

                            tabBuilder:AddSlider({
                                label = "Font Size",
                                min = 6, max = 32, step = 1,
                                get = function() return getBindingSetting("size", 12) end,
                                set = function(v) setBindingSetting("size", v) end,
                                minLabel = "6", maxLabel = "32",
                            })

                            tabBuilder:AddSelector({
                                label = "Font Style",
                                values = fontStyleValues,
                                order = fontStyleOrder,
                                get = function() return getBindingSetting("style", "OUTLINE") end,
                                set = function(v) setBindingSetting("style", v) end,
                            })

                            tabBuilder:AddSelectorColorPicker({
                                label = "Font Color",
                                values = textColorValues,
                                order = textColorOrder,
                                get = function() return getBindingSetting("colorMode", "default") end,
                                set = function(v) setBindingSetting("colorMode", v or "default") end,
                                getColor = function()
                                    local c = getBindingSetting("color", {1,1,1,1})
                                    return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
                                end,
                                setColor = function(r, g, b, a)
                                    setBindingSetting("color", {r, g, b, a})
                                end,
                                customValue = "custom",
                                hasAlpha = true,
                            })

                            local anchorPoints = {
                                TOPLEFT = "Top-Left", TOP = "Top-Center", TOPRIGHT = "Top-Right",
                                LEFT = "Left", CENTER = "Center", RIGHT = "Right",
                                BOTTOMLEFT = "Bottom-Left", BOTTOM = "Bottom-Center", BOTTOMRIGHT = "Bottom-Right",
                            }
                            local anchorPointOrder = { "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" }

                            tabBuilder:AddSelector({
                                label = "Anchor",
                                values = anchorPoints,
                                order = anchorPointOrder,
                                get = function() return getBindingSetting("anchor", "TOPLEFT") end,
                                set = function(v) setBindingSetting("anchor", v) end,
                            })

                            tabBuilder:AddDualSlider({
                                label = "Offset",
                                sliderA = {
                                    axisLabel = "X",
                                    min = -100, max = 100, step = 1,
                                    get = function()
                                        local offset = getBindingSetting("offset", {x=0, y=0})
                                        return offset.x or 0
                                    end,
                                    set = function(v)
                                        local comp = getComponent()
                                        if comp and comp.db then
                                            comp.db.textBindings = comp.db.textBindings or {}
                                            comp.db.textBindings.offset = comp.db.textBindings.offset or {}
                                            comp.db.textBindings.offset.x = v
                                        end
                                        applyText()
                                    end,
                                    minLabel = "-100", maxLabel = "+100",
                                },
                                sliderB = {
                                    axisLabel = "Y",
                                    min = -100, max = 100, step = 1,
                                    get = function()
                                        local offset = getBindingSetting("offset", {x=0, y=0})
                                        return offset.y or 0
                                    end,
                                    set = function(v)
                                        local comp = getComponent()
                                        if comp and comp.db then
                                            comp.db.textBindings = comp.db.textBindings or {}
                                            comp.db.textBindings.offset = comp.db.textBindings.offset or {}
                                            comp.db.textBindings.offset.y = v
                                        end
                                        applyText()
                                    end,
                                    minLabel = "-100", maxLabel = "+100",
                                },
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
                -- Priority system header + explainer
                inner:AddDescription("Priority System", { color = {1, 0.82, 0}, fontSize = 14, topPadding = 4 })
                inner:AddDescription("With Target > In Combat > Out of Combat. Only the highest active condition applies. On Cooldown competes with the result \226\128\148 whichever is the stronger dim takes effect.", { color = {1, 0.82, 0}, topPadding = -8, bottomPadding = -4 })

                -- Opacity While on Cooldown slider (per-icon dimming) — most used
                inner:AddSlider({
                    label = "Opacity While on Cooldown",
                    description = "Dim individual icons when their ability is on cooldown. 100% = no dimming.",
                    min = 0, max = 100, step = 1,
                    get = function() return getSetting("opacityOnCooldown") or 100 end,
                    set = function(v) h.setAndApply("opacityOnCooldown", v) end,
                    minLabel = "Hidden", maxLabel = "100%",
                })

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
-- Register 3 renderers
--------------------------------------------------------------------------------

for i = 1, 3 do
    local renderFn = CreateCustomGroupRenderer(i)
    CustomGroups["RenderGroup" .. i] = renderFn

    addon.UI.SettingsPanel:RegisterRenderer("customGroup" .. i, function(panel, scrollContent)
        renderFn(panel, scrollContent)
    end)
end

return CustomGroups
