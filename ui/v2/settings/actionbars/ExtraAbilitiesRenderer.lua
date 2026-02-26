-- ExtraAbilitiesRenderer.lua - Extra Abilities settings renderer
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.Settings = addon.UI.Settings or {}
addon.UI.Settings.ExtraAbilities = {}

local ExtraAbilities = addon.UI.Settings.ExtraAbilities
local SettingsBuilder = addon.UI.SettingsBuilder

--------------------------------------------------------------------------------
-- Render Function
--------------------------------------------------------------------------------

function ExtraAbilities.Render(panel, scrollContent)
    panel:ClearContent()

    local builder = SettingsBuilder:CreateFor(scrollContent)
    panel._currentBuilder = builder

    builder:SetOnRefresh(function()
        ExtraAbilities.Render(panel, scrollContent)
    end)

    local Helpers = addon.UI.Settings.Helpers
    local h = Helpers.CreateComponentHelpers("extraAbilities")
    local getComponent, getSetting = h.getComponent, h.get
    local setSetting = h.setAndApply

    local function getIconBorderOptions()
        return Helpers.getIconBorderOptions({{"off","Off"},{"hidden","Hidden"}})
    end

    ---------------------------------------------------------------------------
    -- Sizing Section
    ---------------------------------------------------------------------------
    builder:AddCollapsibleSection({
        title = "Sizing",
        componentId = "extraAbilities",
        sectionKey = "sizing",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddSlider({
                label = "Scale", min = 25, max = 150, step = 5,
                get = function() return getSetting("scale") or 100 end,
                set = function(v) setSetting("scale", v) end,
                minLabel = "25%", maxLabel = "150%",
            })

            inner:Finalize()
        end,
    })

    ---------------------------------------------------------------------------
    -- Text Section (Tabbed: Charges and Cooldowns)
    ---------------------------------------------------------------------------
    builder:AddCollapsibleSection({
        title = "Text",
        componentId = "extraAbilities",
        sectionKey = "text",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            -- Helper to apply text styling
            local function applyText()
                if addon and addon.ApplyStyles then
                    C_Timer.After(0, function() addon:ApplyStyles() end)
                end
            end

            local fontStyleValues = Helpers.fontStyleValues
            local fontStyleOrder = Helpers.fontStyleOrder

            local tabs = {
                { key = "charges", label = "Charges" },
                { key = "cooldowns", label = "Cooldowns" },
            }

            inner:AddTabbedSection({
                tabs = tabs,
                componentId = "extraAbilities",
                sectionKey = "textTabs",
                buildContent = {
                    -------------------------------------------------------
                    -- Charges (textCharges) Tab
                    -------------------------------------------------------
                    charges = function(tabContent, tabBuilder)
                        local function getChargesSetting(key, default)
                            local tc = getSetting("textCharges")
                            if tc and tc[key] ~= nil then return tc[key] end
                            return default
                        end
                        local function setChargesSetting(key, value)
                            local comp = getComponent()
                            if comp and comp.db then
                                if addon.EnsureComponentDB then addon:EnsureComponentDB(comp) end
                                comp.db.textCharges = comp.db.textCharges or {}
                                comp.db.textCharges[key] = value
                            end
                            applyText()
                        end

                        tabBuilder:AddFontSelector({
                            label = "Font",
                            get = function() return getChargesSetting("fontFace", "FRIZQT__") end,
                            set = function(v) setChargesSetting("fontFace", v) end,
                        })

                        tabBuilder:AddSlider({
                            label = "Font Size",
                            min = 6, max = 32, step = 1,
                            get = function() return getChargesSetting("size", 16) end,
                            set = function(v) setChargesSetting("size", v) end,
                            minLabel = "6", maxLabel = "32",
                        })

                        tabBuilder:AddSelector({
                            label = "Font Style",
                            values = fontStyleValues,
                            order = fontStyleOrder,
                            get = function() return getChargesSetting("style", "OUTLINE") end,
                            set = function(v) setChargesSetting("style", v) end,
                        })

                        tabBuilder:AddColorPicker({
                            label = "Font Color",
                            get = function()
                                local c = getChargesSetting("color", {1,1,1,1})
                                return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
                            end,
                            set = function(r, g, b, a)
                                setChargesSetting("color", {r, g, b, a})
                            end,
                            hasAlpha = true,
                        })

                        tabBuilder:AddDualSlider({
                            label = "Offset",
                            sliderA = {
                                axisLabel = "X",
                                min = -50, max = 50, step = 1,
                                get = function()
                                    local offset = getChargesSetting("offset", {x=0, y=0})
                                    return (type(offset) == "table" and offset.x) or 0
                                end,
                                set = function(v)
                                    local comp = getComponent()
                                    if comp and comp.db then
                                        if addon.EnsureComponentDB then addon:EnsureComponentDB(comp) end
                                        comp.db.textCharges = comp.db.textCharges or {}
                                        comp.db.textCharges.offset = comp.db.textCharges.offset or {}
                                        comp.db.textCharges.offset.x = v
                                    end
                                    applyText()
                                end,
                            },
                            sliderB = {
                                axisLabel = "Y",
                                min = -50, max = 50, step = 1,
                                get = function()
                                    local offset = getChargesSetting("offset", {x=0, y=0})
                                    return (type(offset) == "table" and offset.y) or 0
                                end,
                                set = function(v)
                                    local comp = getComponent()
                                    if comp and comp.db then
                                        if addon.EnsureComponentDB then addon:EnsureComponentDB(comp) end
                                        comp.db.textCharges = comp.db.textCharges or {}
                                        comp.db.textCharges.offset = comp.db.textCharges.offset or {}
                                        comp.db.textCharges.offset.y = v
                                    end
                                    applyText()
                                end,
                            },
                        })

                        tabBuilder:Finalize()
                    end,

                    -------------------------------------------------------
                    -- Cooldowns (textCooldown) Tab
                    -------------------------------------------------------
                    cooldowns = function(tabContent, tabBuilder)
                        local function getCooldownSetting(key, default)
                            local tc = getSetting("textCooldown")
                            if tc and tc[key] ~= nil then return tc[key] end
                            return default
                        end
                        local function setCooldownSetting(key, value)
                            local comp = getComponent()
                            if comp and comp.db then
                                if addon.EnsureComponentDB then addon:EnsureComponentDB(comp) end
                                comp.db.textCooldown = comp.db.textCooldown or {}
                                comp.db.textCooldown[key] = value
                            end
                            applyText()
                        end

                        tabBuilder:AddFontSelector({
                            label = "Font",
                            get = function() return getCooldownSetting("fontFace", "FRIZQT__") end,
                            set = function(v) setCooldownSetting("fontFace", v) end,
                        })

                        tabBuilder:AddSlider({
                            label = "Font Size",
                            min = 6, max = 32, step = 1,
                            get = function() return getCooldownSetting("size", 16) end,
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

                        tabBuilder:AddColorPicker({
                            label = "Font Color",
                            get = function()
                                local c = getCooldownSetting("color", {1,1,1,1})
                                return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
                            end,
                            set = function(r, g, b, a)
                                setCooldownSetting("color", {r, g, b, a})
                            end,
                            hasAlpha = true,
                        })

                        tabBuilder:AddDualSlider({
                            label = "Offset",
                            sliderA = {
                                axisLabel = "X",
                                min = -50, max = 50, step = 1,
                                get = function()
                                    local offset = getCooldownSetting("offset", {x=0, y=0})
                                    return (type(offset) == "table" and offset.x) or 0
                                end,
                                set = function(v)
                                    local comp = getComponent()
                                    if comp and comp.db then
                                        if addon.EnsureComponentDB then addon:EnsureComponentDB(comp) end
                                        comp.db.textCooldown = comp.db.textCooldown or {}
                                        comp.db.textCooldown.offset = comp.db.textCooldown.offset or {}
                                        comp.db.textCooldown.offset.x = v
                                    end
                                    applyText()
                                end,
                            },
                            sliderB = {
                                axisLabel = "Y",
                                min = -50, max = 50, step = 1,
                                get = function()
                                    local offset = getCooldownSetting("offset", {x=0, y=0})
                                    return (type(offset) == "table" and offset.y) or 0
                                end,
                                set = function(v)
                                    local comp = getComponent()
                                    if comp and comp.db then
                                        if addon.EnsureComponentDB then addon:EnsureComponentDB(comp) end
                                        comp.db.textCooldown = comp.db.textCooldown or {}
                                        comp.db.textCooldown.offset = comp.db.textCooldown.offset or {}
                                        comp.db.textCooldown.offset.y = v
                                    end
                                    applyText()
                                end,
                            },
                        })

                        tabBuilder:Finalize()
                    end,
                },
            })

            inner:Finalize()
        end,
    })

    ---------------------------------------------------------------------------
    -- Border Section
    ---------------------------------------------------------------------------
    builder:AddCollapsibleSection({
        title = "Border",
        componentId = "extraAbilities",
        sectionKey = "border",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            local borderValues, borderOrder = getIconBorderOptions()
            inner:AddSelector({
                label = "Border Style",
                values = borderValues,
                order = borderOrder,
                get = function() return getSetting("borderStyle") or "off" end,
                set = function(v) setSetting("borderStyle", v) end,
                infoIcon = {
                    tooltipTitle = "Border Style",
                    tooltipText = "\"Off\" shows the default Blizzard border, which Scoot does not customize. \"Hidden\" removes all borders entirely.",
                },
            })

            inner:AddToggleColorPicker({
                label = "Border Tint",
                get = function() return getSetting("borderTintEnable") or false end,
                set = function(v) setSetting("borderTintEnable", v) end,
                getColor = function()
                    local c = getSetting("borderTintColor")
                    return c and c[1] or 1, c and c[2] or 1, c and c[3] or 1, c and c[4] or 1
                end,
                setColor = function(r, g, b, a) setSetting("borderTintColor", {r, g, b, a}) end,
            })

            inner:AddSlider({
                label = "Border Thickness", min = 1, max = 8, step = 0.5,
                precision = 1,
                get = function() return getSetting("borderThickness") or 1 end,
                set = function(v) setSetting("borderThickness", v) end,
                minLabel = "1", maxLabel = "8",
            })

            inner:AddDualSlider({
                label = "Border Inset",
                sliderA = {
                    axisLabel = "H",
                    min = -4, max = 4, step = 1,
                    get = function() return getSetting("borderInsetH") or getSetting("borderInset") or 0 end,
                    set = function(v) setSetting("borderInsetH", v) end,
                    minLabel = "-4", maxLabel = "4",
                },
                sliderB = {
                    axisLabel = "V",
                    min = -4, max = 4, step = 1,
                    get = function() return getSetting("borderInsetV") or getSetting("borderInset") or 0 end,
                    set = function(v) setSetting("borderInsetV", v) end,
                    minLabel = "-4", maxLabel = "4",
                },
            })

            inner:Finalize()
        end,
    })

    ---------------------------------------------------------------------------
    -- Visibility & Misc Section
    ---------------------------------------------------------------------------
    builder:AddCollapsibleSection({
        title = "Visibility & Misc",
        componentId = "extraAbilities",
        sectionKey = "misc",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddToggle({
                label = "Hide Blizzard Icon Art",
                get = function() return getSetting("hideBlizzardArt") or false end,
                set = function(v) setSetting("hideBlizzardArt", v) end,
            })

            inner:AddSlider({
                label = "Opacity in Combat", min = 1, max = 100, step = 1,
                get = function() return getSetting("barOpacity") or 100 end,
                set = function(v) setSetting("barOpacity", v) end,
                minLabel = "1%", maxLabel = "100%",
                infoIcon = {
                    tooltipTitle = "Opacity Priority",
                    tooltipText = "With Target takes precedence, then In Combat, then Out of Combat. The highest priority condition that applies determines the opacity.",
                },
            })

            inner:AddSlider({
                label = "Opacity Out of Combat", min = 1, max = 100, step = 1,
                get = function() return getSetting("barOpacityOutOfCombat") or 100 end,
                set = function(v) setSetting("barOpacityOutOfCombat", v) end,
                minLabel = "1%", maxLabel = "100%",
            })

            inner:AddSlider({
                label = "Opacity With Target", min = 1, max = 100, step = 1,
                get = function() return getSetting("barOpacityWithTarget") or 100 end,
                set = function(v) setSetting("barOpacityWithTarget", v) end,
                minLabel = "1%", maxLabel = "100%",
            })

            inner:Finalize()
        end,
    })

    builder:Finalize()
end

--------------------------------------------------------------------------------
-- Self-register with settings panel
addon.UI.SettingsPanel:RegisterRenderer("extraAbilities", function(panel, scrollContent)
    ExtraAbilities.Render(panel, scrollContent)
end)

-- Return module
--------------------------------------------------------------------------------

return ExtraAbilities
