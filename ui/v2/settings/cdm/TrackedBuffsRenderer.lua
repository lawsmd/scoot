-- TrackedBuffsRenderer.lua - Tracked Buffs settings renderer
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.Settings = addon.UI.Settings or {}
addon.UI.Settings.CDM = addon.UI.Settings.CDM or {}
addon.UI.Settings.CDM.TrackedBuffs = {}

local TrackedBuffs = addon.UI.Settings.CDM.TrackedBuffs
local SettingsBuilder = addon.UI.SettingsBuilder

function TrackedBuffs.Render(panel, scrollContent)
    panel:ClearContent()
    local builder = SettingsBuilder:CreateFor(scrollContent)
    panel._currentBuilder = builder

    builder:SetOnRefresh(function() TrackedBuffs.Render(panel, scrollContent) end)

    local Helpers = addon.UI.Settings.Helpers
    local h = Helpers.CreateComponentHelpers("trackedBuffs")
    local getSetting, setSetting = h.get, h.set
    local syncEditModeSetting = h.sync

    -- Positioning Section (different from Essential/Utility - has orientation but no columns)
    builder:AddCollapsibleSection({
        title = "Positioning",
        componentId = "trackedBuffs",
        sectionKey = "positioning",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            local OrientationPatterns = addon.UI.SettingPatterns.Orientation
            local currentOrientation = getSetting("orientation") or "H"
            local initialDirValues, initialDirOrder = OrientationPatterns.getDirectionOptions(currentOrientation)

            inner:AddSelector({
                key = "orientation",
                label = "Orientation",
                values = addon.Catalogs.Orientation.values,
                order = addon.Catalogs.Orientation.order,
                get = function() return getSetting("orientation") or "H" end,
                set = function(v)
                    setSetting("orientation", v)
                    syncEditModeSetting("orientation")
                    local dirSelector = inner:GetControl("iconDirection")
                    if dirSelector then
                        local newValues, newOrder = OrientationPatterns.getDirectionOptions(v)
                        dirSelector:SetOptions(newValues, newOrder)
                    end
                end,
                syncCooldown = 0.4,
            })

            inner:AddSelector({
                key = "iconDirection",
                label = "Icon Direction",
                values = initialDirValues,
                order = initialDirOrder,
                get = function() return getSetting("direction") or "right" end,
                set = function(v)
                    setSetting("direction", v)
                    syncEditModeSetting("direction")
                end,
                syncCooldown = 0.4,
            })

            inner:AddSlider({
                label = "Icon Padding",
                min = 2, max = 14, step = 1,
                get = function() return getSetting("iconPadding") or 2 end,
                set = function(v) setSetting("iconPadding", v) end,
                minLabel = "2px", maxLabel = "14px",
                debounceKey = "UI_trackedBuffs_iconPadding",
                debounceDelay = 0.2,
                onEditModeSync = function() syncEditModeSetting("iconPadding") end,
            })

            inner:Finalize()
        end,
    })

    -- Sizing Section
    builder:AddCollapsibleSection({
        title = "Sizing",
        componentId = "trackedBuffs",
        sectionKey = "sizing",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddSlider({
                label = "Icon Size (Scale)", min = 50, max = 200, step = 10,
                get = function() return getSetting("iconSize") or 100 end,
                set = function(v) setSetting("iconSize", v) end,
                minLabel = "50%", maxLabel = "200%",
                debounceKey = "UI_trackedBuffs_iconSize",
                debounceDelay = 0.2,
                onEditModeSync = function() syncEditModeSetting("iconSize") end,
            })

            inner:AddSlider({
                label = "Icon Shape",
                description = "Adjust icon aspect ratio. Center = square icons.",
                min = -67, max = 67, step = 1,
                get = function() return getSetting("tallWideRatio") or 0 end,
                set = function(v)
                    setSetting("tallWideRatio", v)
                    if addon and addon.ApplyStyles then C_Timer.After(0, function() addon:ApplyStyles() end) end
                end,
                minLabel = "Wide", maxLabel = "Tall",
            })

            -- Swipe Inset
            inner:AddSlider({
                label = "Swipe Inset",
                description = "Shrinks the cooldown swipe area inward to prevent protrusion outside borders on non-square icons.",
                min = 0, max = 10, step = 1,
                get = function() return getSetting("swipeInset") or 0 end,
                set = function(v)
                    setSetting("swipeInset", v)
                    if addon and addon.ApplyStyles then C_Timer.After(0, function() addon:ApplyStyles() end) end
                end,
            })

            inner:Finalize()
        end,
    })

    -- Icons Section
    builder:AddCollapsibleSection({
        title = "Icons",
        componentId = "trackedBuffs",
        sectionKey = "icons",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddSlider({
                label = "Icon Zoom",
                description = "Crops icon edges inward to reduce visible rounded corners from Blizzard's icon mask.",
                min = 0, max = 30, step = 1,
                get = function() return getSetting("iconZoom") or 0 end,
                set = function(v)
                    setSetting("iconZoom", v)
                    if addon and addon.ApplyStyles then
                        C_Timer.After(0, function() addon:ApplyStyles() end)
                    end
                end,
                minLabel = "0%", maxLabel = "30%",
            })

            inner:AddToggle({
                label = "Square Cooldown Swipe",
                description = "Replaces the circular cooldown animation with a square one.",
                get = function() return getSetting("squareCooldownSwipe") or false end,
                set = function(v)
                    setSetting("squareCooldownSwipe", v)
                    if addon and addon.ApplyStyles then
                        C_Timer.After(0, function() addon:ApplyStyles() end)
                    end
                end,
            })

            inner:AddToggle({
                label = "Hide Decorative Ring",
                description = "Hides Blizzard's ornamental ring overlay around each icon.",
                get = function() return getSetting("hideDecorativeRing") or false end,
                set = function(v)
                    setSetting("hideDecorativeRing", v)
                    if addon and addon.ApplyStyles then
                        C_Timer.After(0, function() addon:ApplyStyles() end)
                    end
                end,
            })

            inner:Finalize()
        end,
    })

    -- Border Section
    builder:AddCollapsibleSection({
        title = "Border",
        componentId = "trackedBuffs",
        sectionKey = "border",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddToggle({
                label = "Use Custom Border",
                get = function() return getSetting("borderEnable") or false end,
                set = function(v)
                    setSetting("borderEnable", v)
                    if addon and addon.ApplyStyles then C_Timer.After(0, function() addon:ApplyStyles() end) end
                end,
            })

            inner:AddToggleColorPicker({
                label = "Border Tint",
                get = function() return getSetting("borderTintEnable") or false end,
                set = function(v)
                    setSetting("borderTintEnable", v)
                    if addon and addon.ApplyStyles then C_Timer.After(0, function() addon:ApplyStyles() end) end
                end,
                getColor = function()
                    local c = getSetting("borderTintColor")
                    if c then return c.r or c[1] or 1, c.g or c[2] or 1, c.b or c[3] or 1, c.a or c[4] or 1 end
                    return 1, 1, 1, 1
                end,
                setColor = function(r, g, b, a)
                    setSetting("borderTintColor", {r, g, b, a})
                    if addon and addon.ApplyStyles then C_Timer.After(0, function() addon:ApplyStyles() end) end
                end,
                hasAlpha = true,
            })

            local borderStyleValues, borderStyleOrder = Helpers.getIconBorderOptions()

            inner:AddSelector({
                label = "Border Style",
                values = borderStyleValues, order = borderStyleOrder,
                get = function() return getSetting("borderStyle") or "square" end,
                set = function(v)
                    setSetting("borderStyle", v)
                    if addon and addon.ApplyStyles then C_Timer.After(0, function() addon:ApplyStyles() end) end
                    builder:DeferredRefreshAll()
                end,
            })

            -- Thickness is square-style only; atlas art has no independent edge width
            if addon.IconBorders.SupportsThickness(getSetting("borderStyle") or "square") then
                inner:AddSlider({
                    label = "Border Thickness", min = 1, max = 8, step = 0.5, precision = 1,
                    get = function() return getSetting("borderThickness") or 1 end,
                    set = function(v)
                        setSetting("borderThickness", v)
                        if addon and addon.ApplyStyles then C_Timer.After(0, function() addon:ApplyStyles() end) end
                    end,
                    minLabel = "1", maxLabel = "8",
                })
            end

            inner:AddDualSlider({
                label = "Border Inset",
                sliderA = {
                    axisLabel = "H", min = -4, max = 4, step = 0.5, precision = 1,
                    get = function() return getSetting("borderInsetH") or getSetting("borderInset") or -1 end,
                    set = function(v)
                        setSetting("borderInsetH", v)
                        if addon and addon.ApplyStyles then C_Timer.After(0, function() addon:ApplyStyles() end) end
                    end,
                    minLabel = "-4", maxLabel = "+4",
                },
                sliderB = {
                    axisLabel = "V", min = -4, max = 4, step = 0.5, precision = 1,
                    get = function() return getSetting("borderInsetV") or getSetting("borderInset") or -1 end,
                    set = function(v)
                        setSetting("borderInsetV", v)
                        if addon and addon.ApplyStyles then C_Timer.After(0, function() addon:ApplyStyles() end) end
                    end,
                    minLabel = "-4", maxLabel = "+4",
                },
            })

            inner:Finalize()
        end,
    })

    -- Text Section (contains tabbed sub-sections for Charges and Cooldowns)
    builder:AddCollapsibleSection({
        title = "Text",
        componentId = "trackedBuffs",
        sectionKey = "text",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            local function applyText()
                if addon and addon.ApplyStyles then
                    C_Timer.After(0, function() addon:ApplyStyles() end)
                end
            end

            inner:AddTabbedSection({
                tabs = {
                    { key = "charges", label = "Charges" },
                    { key = "cooldowns", label = "Cooldowns" },
                },
                componentId = "trackedBuffs",
                sectionKey = "textTabs",
                buildContent = {
                    charges = function(tabContent, tabBuilder)
                        -- Charge/stack text is a Blizzard FontString styled in
                        -- place, so the plain style order applies (no paired
                        -- Deep Shadow styles).
                        local s = Helpers.CreateSubTableHelpers("trackedBuffs", "textStacks", { apply = applyText })
                        tabBuilder:AddTextStyleBlock({
                            get = s.get, set = s.set, apply = applyText,
                            defaults = { size = 16 },
                            font = { description = "The font used for charges/stacks text." },
                            size = { min = 6, max = 32, minLabel = "6", maxLabel = "32" },
                        })
                        tabBuilder:Finalize()
                    end,
                    cooldowns = function(tabContent, tabBuilder)
                        -- Cooldown text is a Blizzard FontString styled in
                        -- place; plain style order, same as charges.
                        local s = Helpers.CreateSubTableHelpers("trackedBuffs", "textCooldown", { apply = applyText })
                        tabBuilder:AddTextStyleBlock({
                            get = s.get, set = s.set, apply = applyText,
                            font = { description = "The font used for cooldown timer text." },
                            size = { min = 6, max = 32, minLabel = "6", maxLabel = "32" },
                        })
                        tabBuilder:Finalize()
                    end,
                },
            })

            inner:Finalize()
        end,
    })

    -- Visibility & Misc Section
    builder:AddCollapsibleSection({
        title = "Visibility & Misc",
        componentId = "trackedBuffs",
        sectionKey = "misc",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            -- Priority system header + explainer
            inner:AddDescription("Priority System", { color = {1, 0.82, 0}, fontSize = 14, topPadding = 4 })
            inner:AddDescription("With Target > In Combat > Out of Combat. Only the highest active condition applies.", { color = {1, 0.82, 0}, topPadding = -8, bottomPadding = -4 })

            inner:AddSlider({
                label = "Opacity With Target", min = 0, max = 100, step = 1,
                get = function() return getSetting("opacityWithTarget") or 100 end,
                set = function(v)
                    setSetting("opacityWithTarget", v)
                    if addon and addon.RefreshCDMViewerOpacity then addon.RefreshCDMViewerOpacity("trackedBuffs") end
                end,
                minLabel = "Hidden", maxLabel = "100%",
            })

            inner:AddSlider({
                label = "Opacity in Combat", min = 50, max = 100, step = 1,
                get = function() return getSetting("opacity") or 100 end,
                set = function(v) setSetting("opacity", v) end,
                minLabel = "50%", maxLabel = "100%",
                debounceKey = "UI_trackedBuffs_opacity",
                debounceDelay = 0.2,
                onEditModeSync = function() syncEditModeSetting("opacity") end,
            })

            inner:AddSlider({
                label = "Opacity Out of Combat", min = 0, max = 100, step = 1,
                get = function() return getSetting("opacityOutOfCombat") or 100 end,
                set = function(v)
                    setSetting("opacityOutOfCombat", v)
                    if addon and addon.RefreshCDMViewerOpacity then addon.RefreshCDMViewerOpacity("trackedBuffs") end
                end,
                minLabel = "Hidden", maxLabel = "100%",
            })

            inner:AddSelector({
                label = "Visibility",
                values = addon.Catalogs.Visibility.values, order = addon.Catalogs.Visibility.order,
                get = function() return getSetting("visibilityMode") or "always" end,
                set = function(v)
                    setSetting("visibilityMode", v)
                    syncEditModeSetting("visibilityMode")
                end,
                syncCooldown = 0.4,
            })

            inner:AddToggle({
                label = "Hide When Inactive",
                get = function() return getSetting("hideWhenInactive") or false end,
                set = function(v)
                    setSetting("hideWhenInactive", v)
                    syncEditModeSetting("hideWhenInactive")
                end,
            })

            inner:AddToggle({
                label = "Show Timer",
                get = function() return getSetting("showTimer") ~= false end,
                set = function(v)
                    setSetting("showTimer", v)
                    syncEditModeSetting("showTimer")
                end,
            })

            inner:AddToggle({
                label = "Show Tooltips",
                get = function() return getSetting("showTooltip") ~= false end,
                set = function(v)
                    setSetting("showTooltip", v)
                    syncEditModeSetting("showTooltip")
                end,
            })

            inner:Finalize()
        end,
    })

    builder:Finalize()
end

addon.UI.SettingsPanel:RegisterRenderer("trackedBuffs", function(panel, scrollContent)
    TrackedBuffs.Render(panel, scrollContent)
end)

return TrackedBuffs
