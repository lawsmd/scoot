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
    local getSetting = h.get
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

            local tabs = {
                { key = "charges", label = "Charges" },
                { key = "cooldowns", label = "Cooldowns" },
                { key = "hotkey", label = "Keybind" },
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
                        -- Charge text is a Blizzard FontString on the button
                        -- styled in place, so the plain style order applies
                        -- (no paired Deep Shadow styles).
                        local s = Helpers.CreateSubTableHelpers("extraAbilities", "textCharges", { apply = applyText })
                        tabBuilder:AddTextStyleBlock({
                            get = s.get, set = s.set, apply = applyText,
                            defaults = { size = 16 },
                            size = { min = 6, max = 32, minLabel = "6", maxLabel = "32" },
                            color = { kind = "plain" },
                            offset = { range = 50 },
                        })
                        tabBuilder:Finalize()
                    end,

                    -------------------------------------------------------
                    -- Cooldowns (textCooldown) Tab
                    -------------------------------------------------------
                    cooldowns = function(tabContent, tabBuilder)
                        -- Cooldown text is a Blizzard FontString styled in
                        -- place; plain style order, same as charges.
                        local s = Helpers.CreateSubTableHelpers("extraAbilities", "textCooldown", { apply = applyText })
                        tabBuilder:AddTextStyleBlock({
                            get = s.get, set = s.set, apply = applyText,
                            defaults = { size = 16 },
                            size = { min = 6, max = 32, minLabel = "6", maxLabel = "32" },
                            color = { kind = "plain" },
                            offset = { range = 50 },
                        })
                        tabBuilder:Finalize()
                    end,

                    -------------------------------------------------------
                    -- Hotkey (textHotkey) Tab
                    -------------------------------------------------------
                    hotkey = function(tabContent, tabBuilder)
                        local s = Helpers.CreateSubTableHelpers("extraAbilities", "textHotkey", { apply = applyText })
                        tabBuilder:AddTextStyleBlock({
                            -- The hide flag is a flat component key
                            -- (textHotkeyHidden), not a sub-table field
                            get = function(field)
                                if field == "hidden" then return getSetting("textHotkeyHidden") end
                                return s.get(field)
                            end,
                            set = function(field, value)
                                if field == "hidden" then
                                    h.set("textHotkeyHidden", value)
                                else
                                    s.set(field, value)
                                end
                            end,
                            apply = applyText,
                            hideToggle = { label = "Hide Hotkey Text" },
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
                set = function(v) setSetting("borderStyle", v) builder:DeferredRefreshAll() end,
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

            -- Thickness is square-style only; atlas art has no independent edge width
            if addon.IconBorders.SupportsThickness(getSetting("borderStyle") or "off") then
                inner:AddSlider({
                    label = "Border Thickness", min = 1, max = 8, step = 0.5,
                    precision = 1,
                    get = function() return getSetting("borderThickness") or 1 end,
                    set = function(v) setSetting("borderThickness", v) end,
                    minLabel = "1", maxLabel = "8",
                })
            end

            inner:AddDualSlider({
                label = "Border Inset",
                sliderA = {
                    axisLabel = "H",
                    min = -4, max = 4, step = 0.5, precision = 1,
                    get = function() return getSetting("borderInsetH") or getSetting("borderInset") or 0 end,
                    set = function(v) setSetting("borderInsetH", v) end,
                    minLabel = "-4", maxLabel = "4",
                },
                sliderB = {
                    axisLabel = "V",
                    min = -4, max = 4, step = 0.5, precision = 1,
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
                label = "Opacity", min = 1, max = 100, step = 1,
                get = function() return getSetting("barOpacity") or 100 end,
                set = function(v) setSetting("barOpacity", v) end,
                minLabel = "1%", maxLabel = "100%",
                infoIcon = {
                    tooltipTitle = "Opacity Priority",
                    tooltipText = "With Target takes precedence over base Opacity.",
                },
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
