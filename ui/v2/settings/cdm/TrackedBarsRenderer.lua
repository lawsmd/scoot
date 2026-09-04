-- TrackedBarsRenderer.lua - Tracked Bars settings renderer
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.Settings = addon.UI.Settings or {}
addon.UI.Settings.CDM = addon.UI.Settings.CDM or {}
addon.UI.Settings.CDM.TrackedBars = {}

local TrackedBars = addon.UI.Settings.CDM.TrackedBars
local SettingsBuilder = addon.UI.SettingsBuilder

function TrackedBars.Render(panel, scrollContent)
    panel:ClearContent()

    local builder = SettingsBuilder:CreateFor(scrollContent)
    panel._currentBuilder = builder

    builder:SetOnRefresh(function()
        TrackedBars.Render(panel, scrollContent)
    end)

    local Helpers = addon.UI.Settings.Helpers
    local h = Helpers.CreateComponentHelpers("trackedBars")
    local getComponent, getSetting = h.getComponent, h.get
    local setSetting = h.setAndApply
    local syncEditModeSetting = h.sync

    local function getIconBorderOptions()
        return Helpers.getIconBorderOptions({{"none","None"}})
    end

    ---------------------------------------------------------------------------
    -- Mode Selector (parent level, emphasized)
    ---------------------------------------------------------------------------
    builder:AddSelector({
        label = "Mode",
        description = "Choose how tracked bars are displayed.",
        values = { default = "Default", vertical = "Vertical Bars" },
        order = { "default", "vertical" },
        emphasized = true,
        get = function() return getSetting("barMode") or "default" end,
        set = function(v)
            setSetting("barMode", v)
            builder:DeferredRefreshAll()   -- the row below exists only in vertical mode
        end,
    })

    if (getSetting("barMode") or "default") == "vertical" then
        builder:AddToggle({
            label = "Lock Drain to Original Duration",
            description = "When a tracked buff or debuff gets extended, keep draining at the speed set by its original duration and add the extra time as extra fill instead of refilling the bar. If the new duration is longer than the original, the bar still refills and drains at that longer speed.",
            get = function() return getSetting("verticalLockCadence") or false end,
            set = function(v) setSetting("verticalLockCadence", v) end,
        })
    end

    ---------------------------------------------------------------------------
    -- Positioning Section
    ---------------------------------------------------------------------------
    builder:AddCollapsibleSection({
        title = "Positioning",
        componentId = "trackedBars",
        sectionKey = "positioning",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddSlider({
                label = "Icon Padding", min = 2, max = 10, step = 1,
                get = function() return getSetting("iconPadding") or 3 end,
                set = function(v) setSetting("iconPadding", v) end,
                debounceKey = "trackedBars_iconPadding",
                debounceDelay = 0.3,
                onEditModeSync = function() syncEditModeSetting("iconPadding") end,
                minLabel = "2", maxLabel = "10",
            })

            inner:AddSlider({
                label = "Icon/Bar Padding", min = -20, max = 80, step = 1,
                get = function() return getSetting("iconBarPadding") or 0 end,
                set = function(v) setSetting("iconBarPadding", v) end,
                minLabel = "-20", maxLabel = "80",
            })

            inner:Finalize()
        end,
    })

    ---------------------------------------------------------------------------
    -- Sizing Section
    ---------------------------------------------------------------------------
    builder:AddCollapsibleSection({
        title = "Sizing",
        componentId = "trackedBars",
        sectionKey = "sizing",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddSlider({
                label = "Bar Scale", min = 50, max = 200, step = 10,
                get = function() return getSetting("iconSize") or 100 end,
                set = function(v) setSetting("iconSize", v) end,
                debounceKey = "trackedBars_iconSize",
                debounceDelay = 0.3,
                onEditModeSync = function() syncEditModeSetting("iconSize") end,
                minLabel = "50%", maxLabel = "200%",
            })

            inner:AddSlider({
                label = "Bar Width", min = 50, max = 200, step = 1,
                get = function() return getSetting("barWidth") or 100 end,
                set = function(v) setSetting("barWidth", v) end,
                debounceKey = "trackedBars_barWidth",
                debounceDelay = 0.3,
                onEditModeSync = function() syncEditModeSetting("barWidth") end,
                minLabel = "50%", maxLabel = "200%",
            })

            inner:Finalize()
        end,
    })

    ---------------------------------------------------------------------------
    -- Style Section
    ---------------------------------------------------------------------------
    builder:AddCollapsibleSection({
        title = "Style",
        componentId = "trackedBars",
        sectionKey = "style",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddToggle({
                label = "Enable Custom Textures",
                get = function() return getSetting("styleEnableCustom") ~= false end,
                set = function(v) setSetting("styleEnableCustom", v) end,
            })

            local styleGet, styleSet = Helpers.CreateFlatAccessors(getSetting, h.set, {
                texture = "styleForegroundTexture", colorMode = "styleForegroundColorMode", color = "styleForegroundTint",
                bgTexture = "styleBackgroundTexture", bgColorMode = "styleBackgroundColorMode", bgColor = "styleBackgroundTint",
                bgOpacity = "styleBackgroundOpacity",
            })
            local textModes = addon.Catalogs.ColorMode.Text
            inner:AddBarStyleBlock({
                get = styleGet, set = styleSet, apply = Helpers.applyStyles,
                spacer = false,
                foreground = { values = textModes.values, order = textModes.order, infoIcons = false, textureDefault = "bevelled" },
                background = { values = textModes.values, order = textModes.order, textureDefault = "bevelled" },
                opacity = { minLabel = "0%", maxLabel = "100%" },
            })

            inner:Finalize()
        end,
    })

    ---------------------------------------------------------------------------
    -- Border Section
    ---------------------------------------------------------------------------
    builder:AddCollapsibleSection({
        title = "Border",
        componentId = "trackedBars",
        sectionKey = "border",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            local borderGet, borderWrite = Helpers.CreateFlatAccessors(getSetting, h.set, {
                style = "borderStyle", hiddenEdges = "borderHiddenEdges",
                tintEnabled = "borderTintEnable", tintColor = "borderTintColor",
                thickness = "borderThickness", insetH = "borderInsetH", insetV = "borderInsetV",
            })
            -- Backward compat: a legacy borderEnable = true with no borderStyle reads
            -- as "square", and writing a style clears the legacy toggle. The inset
            -- axes fall back to the single-value borderInset.
            local function borderGetCompat(field)
                if field == "style" then
                    local comp = getComponent()
                    if comp and comp.db and rawget(comp.db, "borderEnable") == true and not rawget(comp.db, "borderStyle") then
                        return "square"
                    end
                elseif field == "insetH" or field == "insetV" then
                    return borderGet(field) or getSetting("borderInset")
                end
                return borderGet(field)
            end
            local function borderSetCompat(field, value)
                borderWrite(field, value)
                if field == "style" then
                    local comp = getComponent()
                    if comp and comp.db and rawget(comp.db, "borderEnable") ~= nil then
                        comp.db.borderEnable = nil
                    end
                end
            end
            inner:AddBarBorderBlock({
                get = borderGetCompat, set = borderSetCompat, apply = Helpers.applyStyles,
                style = { includeNone = false, includeBlizzardDefault = true, default = "blizzardDefault" },
                thickness = { minLabel = "1", maxLabel = "8" },
            })

            inner:Finalize()
        end,
    })

    ---------------------------------------------------------------------------
    -- Text Section (contains tabbed sub-sections for Spell Name and Timer)
    ---------------------------------------------------------------------------
    builder:AddCollapsibleSection({
        title = "Text",
        componentId = "trackedBars",
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
                    { key = "spellName", label = "Spell Name" },
                    { key = "timer", label = "Timer" },
                },
                componentId = "trackedBars",
                sectionKey = "textTabs",
                buildContent = {
                    spellName = function(tabContent, tabBuilder)
                        -- Styled in place on Blizzard FontStrings in default
                        -- mode, so the plain style order applies (no paired
                        -- Deep Shadow styles).
                        local s = Helpers.CreateSubTableHelpers("trackedBars", "textName", { apply = applyText })
                        tabBuilder:AddTextStyleBlock({
                            get = s.get, set = s.set, apply = applyText,
                            font = { description = "The font used for spell name text." },
                            size = { min = 6, max = 32, minLabel = "6", maxLabel = "32" },
                        })
                        tabBuilder:Finalize()
                    end,
                    timer = function(tabContent, tabBuilder)
                        -- Styled in place on Blizzard FontStrings in default
                        -- mode; plain style order, same as spell name.
                        local s = Helpers.CreateSubTableHelpers("trackedBars", "textDuration", { apply = applyText })
                        tabBuilder:AddTextStyleBlock({
                            get = s.get, set = s.set, apply = applyText,
                            font = { description = "The font used for timer/duration text." },
                            size = { min = 6, max = 32, minLabel = "6", maxLabel = "32" },
                        })
                        tabBuilder:Finalize()
                    end,
                },
            })

            inner:Finalize()
        end,
    })

    ---------------------------------------------------------------------------
    -- Icon Section
    ---------------------------------------------------------------------------
    builder:AddCollapsibleSection({
        title = "Icon",
        componentId = "trackedBars",
        sectionKey = "icon",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddSlider({
                label = "Icon Zoom",
                description = "Crops icon edges inward to reduce visible rounded corners.",
                min = 0, max = 30, step = 1,
                get = function() return getSetting("iconZoom") or 0 end,
                set = function(v) setSetting("iconZoom", v) end,
                minLabel = "0%", maxLabel = "30%",
            })

            inner:AddToggle({
                label = "Hide Decorative Ring",
                description = "Hides Blizzard's ornamental ring overlay around each icon.",
                get = function() return getSetting("iconHideDecorativeRing") or false end,
                set = function(v) setSetting("iconHideDecorativeRing", v) end,
            })

            inner:AddSlider({
                label = "Icon Shape",
                description = "Adjust icon aspect ratio. Center = square icons.",
                min = -67, max = 67, step = 1,
                get = function() return getSetting("iconTallWideRatio") or 0 end,
                set = function(v) setSetting("iconTallWideRatio", v) end,
                minLabel = "Wide", maxLabel = "Tall",
            })

            inner:AddToggleColorPicker({
                label = "Border Tint",
                get = function() return getSetting("iconBorderTintEnable") or false end,
                set = function(v) setSetting("iconBorderTintEnable", v) end,
                getColor = function()
                    local c = getSetting("iconBorderTintColor")
                    return c and c[1] or 1, c and c[2] or 1, c and c[3] or 1, c and c[4] or 1
                end,
                setColor = function(r, g, b, a) setSetting("iconBorderTintColor", {r, g, b, a}) end,
            })

            local iconBorderValues, iconBorderOrder = getIconBorderOptions()
            inner:AddSelector({
                label = "Border Style",
                values = iconBorderValues,
                order = iconBorderOrder,
                get = function()
                    if not getSetting("iconBorderEnable") then return "none" end
                    return getSetting("iconBorderStyle") or "square"
                end,
                set = function(v)
                    if v == "none" then
                        setSetting("iconBorderEnable", false)
                        setSetting("iconBorderStyle", "none")
                    else
                        setSetting("iconBorderEnable", true)
                        setSetting("iconBorderStyle", v)
                    end
                    builder:DeferredRefreshAll()
                end,
            })

            -- Thickness is square-style only; atlas art has no independent edge width
            local currentIconBorderStyle = (not getSetting("iconBorderEnable")) and "none"
                or (getSetting("iconBorderStyle") or "square")
            if addon.IconBorders.SupportsThickness(currentIconBorderStyle) then
                inner:AddSlider({
                    label = "Border Thickness", min = 1, max = 8, step = 0.5,
                    precision = 1,
                    get = function() local v = getSetting("iconBorderThickness") or 1; return math.max(1, math.min(8, math.floor(v * 2 + 0.5) / 2)) end,
                    set = function(v) setSetting("iconBorderThickness", math.max(1, math.min(8, math.floor((tonumber(v) or 1) * 2 + 0.5) / 2))) end,
                    minLabel = "1", maxLabel = "8",
                })
            end

            inner:AddInsetPair({
                step = 0.5, precision = 1,
                get = function(axis) return getSetting(axis == "h" and "iconBorderInsetH" or "iconBorderInsetV") or getSetting("iconBorderInset") end,
                set = function(axis, v) setSetting(axis == "h" and "iconBorderInsetH" or "iconBorderInsetV", v) end,
            })

            inner:Finalize()
        end,
    })

    ---------------------------------------------------------------------------
    -- Misc Section
    ---------------------------------------------------------------------------
    builder:AddCollapsibleSection({
        title = "Visibility & Misc",
        componentId = "trackedBars",
        sectionKey = "misc",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            local get, set = Helpers.CreateFlatAccessors(getSetting, setSetting, addon.Opacity.Keys.Plain)
            inner:AddStateOpacityBlock({
                get = get, set = set, combatMin = 50, min = 0,
                apply = function()
                    if addon and addon.RefreshCDMViewerOpacity then addon.RefreshCDMViewerOpacity("trackedBars") end
                end,
                combat = {
                    debounceKey = "trackedBars_opacity",
                    debounceDelay = 0.3,
                    onEditModeSync = function() syncEditModeSetting("opacity") end,
                },
            })

            inner:AddSelector({
                label = "Display Mode",
                values = {
                    both = "Icon & Name",
                    icon = "Icon Only",
                    name = "Name Only",
                },
                order = { "both", "icon", "name" },
                get = function() return getSetting("displayMode") or "both" end,
                set = function(v)
                    setSetting("displayMode", v)
                    syncEditModeSetting("displayMode")
                end,
                syncCooldown = 0.5,
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

addon.UI.SettingsPanel:RegisterRenderer("trackedBars", function(panel, scrollContent)
    TrackedBars.Render(panel, scrollContent)
end)

return TrackedBars
