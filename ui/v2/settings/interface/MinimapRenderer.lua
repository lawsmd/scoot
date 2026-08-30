-- MinimapRenderer.lua - Minimap settings renderer
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.Settings = addon.UI.Settings or {}
addon.UI.Settings.Minimap = {}

local Minimap = addon.UI.Settings.Minimap
local SettingsBuilder = addon.UI.SettingsBuilder

--------------------------------------------------------------------------------
-- Helper Functions
--------------------------------------------------------------------------------

local Helpers = addon.UI.Settings.Helpers
local h = Helpers.CreateComponentHelpers("minimapStyle")
local getSetting = h.get
local setSetting = h.setAndApply

local applyStyles = Helpers.applyStyles

-- Maps the composite's field vocabulary onto this file's flat per-prefix
-- keys (zoneTextFont, clockFontSize, ...). Writes do not apply; the
-- composite calls apply after each write.
local function flatTextAccessors(map)
    local function get(field)
        local key = map[field]
        if not key then return nil end
        return getSetting(key)
    end
    local function set(field, value)
        local key = map[field]
        if key then h.set(key, value) end
    end
    return get, set
end

-- Time source options
local timeSourceValues = {
    ["local"] = "Local Time",
    ["server"] = "Server Time",
}
local timeSourceOrder = { "local", "server" }

-- Latency source options
local latencySourceValues = {
    ["home"] = "Home (Realm)",
    ["world"] = "World",
}
local latencySourceOrder = { "home", "world" }

-- Map shape options
local mapShapeValues = {
    ["default"] = "Default (Circle)",
    ["square"] = "Square",
}
local mapShapeOrder = { "default", "square" }

-- Zone text color mode (for SelectorColorPicker)
local zoneColorModeValues = {
    ["pvp"] = "PVP Type",
    ["custom"] = "Custom",
}
local zoneColorModeOrder = { "pvp", "custom" }

-- Position options (includes "dock" for Blizzard default)
local positionValues = {
    dock = "Default (Dock)",
    TOP = "Top",
    TOPRIGHT = "Top Right",
    RIGHT = "Right",
    BOTTOMRIGHT = "Bottom Right",
    BOTTOM = "Bottom",
    BOTTOMLEFT = "Bottom Left",
    LEFT = "Left",
    TOPLEFT = "Top Left",
    CENTER = "Center",
}
local positionOrder = { "dock", "TOP", "TOPRIGHT", "RIGHT", "BOTTOMRIGHT", "BOTTOM", "BOTTOMLEFT", "LEFT", "TOPLEFT", "CENTER" }

--------------------------------------------------------------------------------
-- Render Function
--------------------------------------------------------------------------------

function Minimap.Render(panel, scrollContent)
    -- Clear any existing content
    panel:ClearContent()

    -- Create builder for this content area
    local builder = SettingsBuilder:CreateFor(scrollContent)
    panel._currentBuilder = builder

    -- Store reference for re-rendering on expand/collapse
    builder:SetOnRefresh(function()
        Minimap.Render(panel, scrollContent)
    end)

    -- Get anchor options from component
    local anchorOptions = addon.MinimapAnchorOptions or {
        TOP = "Top",
        TOPRIGHT = "Top Right",
        RIGHT = "Right",
        BOTTOMRIGHT = "Bottom Right",
        BOTTOM = "Bottom",
        BOTTOMLEFT = "Bottom Left",
        LEFT = "Left",
        TOPLEFT = "Top Left",
        CENTER = "Center",
    }
    local anchorOrder = addon.MinimapAnchorOrder or { "TOP", "TOPRIGHT", "RIGHT", "BOTTOMRIGHT", "BOTTOM", "BOTTOMLEFT", "LEFT", "TOPLEFT", "CENTER" }

    ----------------------------------------------------------------------------
    -- Section 1: Map Style
    ----------------------------------------------------------------------------
    builder:AddCollapsibleSection({
        title = "Map Style",
        componentId = "minimapStyle",
        sectionKey = "mapStyle",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            -- Map Shape selector
            inner:AddSelector({
                label = "Map Shape",
                description = "Change the minimap shape. Square removes the circular mask.",
                values = mapShapeValues,
                order = mapShapeOrder,
                get = function()
                    return getSetting("mapShape") or "default"
                end,
                set = function(v)
                    setSetting("mapShape", v)
                    -- Re-render to update disabled states of border controls
                    C_Timer.After(0.05, function()
                        if panel and Minimap.Render then
                            Minimap.Render(panel, scrollContent)
                        end
                    end)
                end,
            })

            -- Map Size slider (Edit Mode setting - read/write directly)
            inner:AddSlider({
                label = "Map Size",
                description = "Blizzard's Edit Mode scale (50-200%).",
                min = 50,
                max = 200,
                step = 10,
                get = function()
                    return addon.getEditModeMinimapSize and addon.getEditModeMinimapSize() or 100
                end,
                set = function(v)
                    if addon.setEditModeMinimapSize then
                        addon.setEditModeMinimapSize(v)
                    end
                end,
                minLabel = "50%",
                maxLabel = "200%",
            })

            -- Border options (only for square)
            inner:AddToggle({
                label = "Enable Custom Border",
                description = "Draw a custom border around the minimap.",
                get = function()
                    return getSetting("borderEnabled") or false
                end,
                set = function(v)
                    setSetting("borderEnabled", v)
                    -- Re-render to update disabled states of Border Tint and Thickness
                    C_Timer.After(0.05, function()
                        if panel and Minimap.Render then
                            Minimap.Render(panel, scrollContent)
                        end
                    end)
                end,
                isDisabled = function()
                    return getSetting("mapShape") ~= "square"
                end,
            })

            inner:AddToggleColorPicker({
                label = "Border Tint",
                description = "Apply a custom color to the border.",
                get = function()
                    return getSetting("borderTintEnabled") or false
                end,
                set = function(v)
                    setSetting("borderTintEnabled", v)
                end,
                getColor = function()
                    local c = getSetting("borderColor") or {0, 0, 0, 1}
                    return c[1], c[2], c[3], c[4]
                end,
                setColor = function(r, g, b, a)
                    setSetting("borderColor", {r, g, b, a})
                end,
                hasAlpha = true,
                isDisabled = function()
                    return getSetting("mapShape") ~= "square" or not getSetting("borderEnabled")
                end,
            })

            inner:AddSlider({
                label = "Border Thickness",
                description = "The thickness of the border in pixels.",
                min = 1,
                max = 8,
                step = 1,
                get = function()
                    return getSetting("borderThickness") or 2
                end,
                set = function(v)
                    setSetting("borderThickness", v)
                end,
                minLabel = "1",
                maxLabel = "8",
                isDisabled = function()
                    return getSetting("mapShape") ~= "square" or not getSetting("borderEnabled")
                end,
            })

            inner:Finalize()
        end,
    })

    ----------------------------------------------------------------------------
    -- Section 2: Text (Tabbed)
    ----------------------------------------------------------------------------
    builder:AddCollapsibleSection({
        title = "Text",
        componentId = "minimapStyle",
        sectionKey = "text",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddTabbedSection({
                tabs = {
                    { key = "dock", label = "Dock" },
                    { key = "zoneText", label = "Zone Text" },
                    { key = "clock", label = "Clock" },
                    { key = "systemData", label = "System Data" },
                },
                componentId = "minimapStyle",
                sectionKey = "textTabs",
                buildContent = {
                    ----------------------------------------------------------------
                    -- Tab 0: Dock
                    ----------------------------------------------------------------
                    dock = function(tabContent, tabBuilder)
                        tabBuilder:AddToggle({
                            label = "Hide Dock",
                            description = "Hide the minimap dock area: zone text bar, calendar, tracking button, and addon compartment.",
                            get = function()
                                return getSetting("dockHide") or false
                            end,
                            set = function(v)
                                setSetting("dockHide", v)
                            end,
                        })

                        tabBuilder:Finalize()
                    end,

                    ----------------------------------------------------------------
                    -- Tab 1: Zone Text
                    ----------------------------------------------------------------
                    zoneText = function(tabContent, tabBuilder)
                        tabBuilder:AddToggle({
                            label = "Hide Zone Text",
                            description = "Hide the zone name display completely.",
                            get = function()
                                return getSetting("zoneTextHide") or false
                            end,
                            set = function(v)
                                setSetting("zoneTextHide", v)
                            end,
                        })

                        tabBuilder:AddToggle({
                            label = "Enable Zone Coordinates",
                            description = "Show your current zone coordinates centered below the zone text.",
                            get = function()
                                return getSetting("zoneCoordinatesEnabled") or false
                            end,
                            set = function(v)
                                setSetting("zoneCoordinatesEnabled", v)
                            end,
                        })

                        tabBuilder:AddSelector({
                            label = "Position",
                            description = "Where to show zone text. 'Default (Dock)' uses Blizzard's dock bar, other options use a custom overlay.",
                            values = positionValues,
                            order = positionOrder,
                            get = function()
                                return getSetting("zoneTextPosition") or "dock"
                            end,
                            set = function(v)
                                setSetting("zoneTextPosition", v)
                                -- Re-render to update offset visibility
                                C_Timer.After(0.05, function()
                                    if panel and Minimap.Render then
                                        Minimap.Render(panel, scrollContent)
                                    end
                                end)
                            end,
                        })

                        local zoneGet, zoneSet = flatTextAccessors({
                            fontFace = "zoneTextFont",
                            style = "zoneTextFontStyle",
                            size = "zoneTextFontSize",
                            colorMode = "zoneTextColorMode",
                            color = "zoneTextCustomColor",
                            offsetX = "zoneTextOffsetX",
                            offsetY = "zoneTextOffsetY",
                        })
                        -- Offset applies only to the custom overlay, not the dock
                        local currentPosition = getSetting("zoneTextPosition") or "dock"
                        tabBuilder:AddTextStyleBlock({
                            get = zoneGet, set = zoneSet, apply = applyStyles,
                            defaults = { size = 12, colorMode = "pvp", color = { 1, 0.82, 0, 1 } },
                            font = { description = "The font used for zone text." },
                            style = { description = "The outline style for zone text." },
                            size = { min = 8, max = 24, minLabel = "8", maxLabel = "24",
                                description = "The size of the zone text." },
                            color = {
                                values = zoneColorModeValues, order = zoneColorModeOrder,
                                description = "How to color the zone text. PVP Type colors based on zone type.",
                            },
                            offset = currentPosition ~= "dock"
                                and { range = 50, minLabel = "-50", maxLabel = "+50" }
                                or false,
                        })

                        tabBuilder:Finalize()
                    end,

                    ----------------------------------------------------------------
                    -- Tab 2: Clock
                    ----------------------------------------------------------------
                    clock = function(tabContent, tabBuilder)
                        tabBuilder:AddToggle({
                            label = "Hide Clock",
                            description = "Hide the clock display completely.",
                            get = function()
                                return getSetting("clockHide") or false
                            end,
                            set = function(v)
                                setSetting("clockHide", v)
                            end,
                        })

                        tabBuilder:AddSelector({
                            label = "Position",
                            description = "Where to show the clock. 'Default (Dock)' uses Blizzard's dock bar, other options use a custom overlay.",
                            values = positionValues,
                            order = positionOrder,
                            get = function()
                                return getSetting("clockPosition") or "dock"
                            end,
                            set = function(v)
                                setSetting("clockPosition", v)
                                -- Re-render to update offset visibility
                                C_Timer.After(0.05, function()
                                    if panel and Minimap.Render then
                                        Minimap.Render(panel, scrollContent)
                                    end
                                end)
                            end,
                        })

                        tabBuilder:AddSelector({
                            label = "Time Source",
                            description = "Show local time or server time.",
                            values = timeSourceValues,
                            order = timeSourceOrder,
                            get = function()
                                return getSetting("clockTimeSource") or "local"
                            end,
                            set = function(v)
                                setSetting("clockTimeSource", v)
                            end,
                        })

                        tabBuilder:AddToggle({
                            label = "24-Hour Format",
                            description = "Use 24-hour time format instead of 12-hour with AM/PM.",
                            get = function()
                                return getSetting("clockUse24Hour") or false
                            end,
                            set = function(v)
                                setSetting("clockUse24Hour", v)
                            end,
                        })

                        local clockGet, clockSet = flatTextAccessors({
                            fontFace = "clockFont",
                            style = "clockFontStyle",
                            size = "clockFontSize",
                            colorMode = "clockColorMode",
                            color = "clockCustomColor",
                            offsetX = "clockOffsetX",
                            offsetY = "clockOffsetY",
                        })
                        -- Offset applies only to the custom overlay, not the dock
                        local currentPosition = getSetting("clockPosition") or "dock"
                        tabBuilder:AddTextStyleBlock({
                            get = clockGet, set = clockSet, apply = applyStyles,
                            defaults = { size = 12 },
                            font = { description = "The font used for the clock." },
                            style = { description = "The outline style for the clock." },
                            size = { min = 8, max = 24, minLabel = "8", maxLabel = "24",
                                description = "The size of the clock text." },
                            color = { description = "The color of the clock text." },
                            offset = currentPosition ~= "dock"
                                and { range = 50, minLabel = "-50", maxLabel = "+50" }
                                or false,
                        })

                        tabBuilder:Finalize()
                    end,

                    ----------------------------------------------------------------
                    -- Tab 3: System Data (FPS/Latency)
                    ----------------------------------------------------------------
                    systemData = function(tabContent, tabBuilder)
                        tabBuilder:AddToggle({
                            label = "Show FPS",
                            description = "Display frames per second near the minimap.",
                            get = function()
                                return getSetting("systemDataShowFPS") or false
                            end,
                            set = function(v)
                                setSetting("systemDataShowFPS", v)
                            end,
                        })

                        tabBuilder:AddToggle({
                            label = "Show Latency",
                            description = "Display network latency near the minimap.",
                            get = function()
                                return getSetting("systemDataShowLatency") or false
                            end,
                            set = function(v)
                                setSetting("systemDataShowLatency", v)
                            end,
                        })

                        tabBuilder:AddSelector({
                            label = "Latency Source",
                            description = "Which latency value to display.",
                            values = latencySourceValues,
                            order = latencySourceOrder,
                            get = function()
                                return getSetting("systemDataLatencySource") or "home"
                            end,
                            set = function(v)
                                setSetting("systemDataLatencySource", v)
                            end,
                            isDisabled = function()
                                return not getSetting("systemDataShowLatency")
                            end,
                        })

                        local sdGet, sdSet = flatTextAccessors({
                            fontFace = "systemDataFont",
                            style = "systemDataFontStyle",
                            size = "systemDataFontSize",
                            colorMode = "systemDataColorMode",
                            color = "systemDataCustomColor",
                            anchor = "systemDataAnchor",
                            offsetX = "systemDataOffsetX",
                            offsetY = "systemDataOffsetY",
                        })
                        -- System data always renders on the Scoot-drawn
                        -- overlay, so the paired Deep Shadow styles are
                        -- offered here (unlike zone text and clock, which can
                        -- style Blizzard's own FontStrings in dock mode).
                        tabBuilder:AddTextStyleBlock({
                            get = function(field)
                                -- Y offset defaults below the minimap
                                if field == "offsetY" then
                                    local v = sdGet("offsetY")
                                    if v == nil then return -18 end
                                    return v
                                end
                                return sdGet(field)
                            end,
                            set = sdSet, apply = applyStyles,
                            defaults = { size = 11 },
                            font = { description = "The font used for system data." },
                            style = { order = Helpers.fontStyleOrderPaired,
                                description = "The outline style for system data." },
                            size = { min = 8, max = 24, minLabel = "8", maxLabel = "24",
                                description = "The size of the system data text." },
                            color = { description = "The color of the system data text." },
                            alignment = { kind = "anchor9", default = "BOTTOM",
                                values = anchorOptions, order = anchorOrder,
                                description = "Where to position the system data relative to the minimap." },
                            offset = { range = 50, minLabel = "-50", maxLabel = "+50" },
                        })

                        tabBuilder:Finalize()
                    end,
                },
            })

            inner:Finalize()
        end,
    })

    ----------------------------------------------------------------------------
    -- Section 3: Buttons (Tabbed - Addon Buttons)
    ----------------------------------------------------------------------------
    builder:AddCollapsibleSection({
        title = "Buttons",
        componentId = "minimapStyle",
        sectionKey = "buttons",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddTabbedSection({
                tabs = {
                    { key = "addonButtons", label = "Addon Buttons" },
                    { key = "mail", label = "Mail" },
                    { key = "tracking", label = "Tracking" },
                },
                componentId = "minimapStyle",
                sectionKey = "buttonsTabs",
                buildContent = {
                    ----------------------------------------------------------------
                    -- Tab: Addon Buttons
                    ----------------------------------------------------------------
                    addonButtons = function(tabContent, tabBuilder)
                        -- Addon Button Container toggle
                        tabBuilder:AddToggle({
                            label = "Use Addon Button Container",
                            description = "Consolidate minimap addon buttons into a dropdown menu.",
                            get = function()
                                return getSetting("addonButtonContainerEnabled") or false
                            end,
                            set = function(v)
                                setSetting("addonButtonContainerEnabled", v)
                                -- Re-render to update disabled states
                                C_Timer.After(0.05, function()
                                    if panel and Minimap.Render then
                                        Minimap.Render(panel, scrollContent)
                                    end
                                end)
                            end,
                        })

                        -- Keep Scoot Button Separate toggle
                        tabBuilder:AddToggle({
                            label = "Keep Scoot Button Separate",
                            description = "Keep Scoot's minimap button visible outside the container.",
                            get = function()
                                return getSetting("scootButtonSeparate") or false
                            end,
                            set = function(v)
                                setSetting("scootButtonSeparate", v)
                            end,
                            isDisabled = function()
                                return not getSetting("addonButtonContainerEnabled")
                            end,
                        })

                        -- Container Position selector
                        tabBuilder:AddSelector({
                            label = "Container Position",
                            description = "Where to place the addon button container relative to the minimap.",
                            values = anchorOptions,
                            order = anchorOrder,
                            get = function()
                                return getSetting("addonButtonContainerAnchor") or "BOTTOMRIGHT"
                            end,
                            set = function(v)
                                setSetting("addonButtonContainerAnchor", v)
                            end,
                            isDisabled = function()
                                return not getSetting("addonButtonContainerEnabled")
                            end,
                        })

                        -- Container Offset (Dual Slider for X/Y)
                        tabBuilder:AddDualSlider({
                            label = "Container Offset",
                            sliderA = {
                                axisLabel = "X",
                                min = -100,
                                max = 100,
                                step = 1,
                                get = function()
                                    return getSetting("addonButtonContainerOffsetX") or 0
                                end,
                                set = function(v)
                                    setSetting("addonButtonContainerOffsetX", v)
                                end,
                            },
                            sliderB = {
                                axisLabel = "Y",
                                min = -100,
                                max = 100,
                                step = 1,
                                get = function()
                                    return getSetting("addonButtonContainerOffsetY") or 0
                                end,
                                set = function(v)
                                    setSetting("addonButtonContainerOffsetY", v)
                                end,
                            },
                            isDisabled = function()
                                return not getSetting("addonButtonContainerEnabled")
                            end,
                        })

                        -- Hide Addon Button Borders toggle
                        tabBuilder:AddToggle({
                            label = "Hide Addon Button Borders",
                            description = "Hide borders, background mask, and hover glow on addon minimap buttons.",
                            get = function()
                                return getSetting("hideAddonButtonBorders") or false
                            end,
                            set = function(v)
                                setSetting("hideAddonButtonBorders", v)
                                -- Re-render to update tint disabled state
                                C_Timer.After(0.05, function()
                                    if panel and Minimap.Render then
                                        Minimap.Render(panel, scrollContent)
                                    end
                                end)
                            end,
                        })

                        -- Border Tint (ToggleColorPicker)
                        tabBuilder:AddToggleColorPicker({
                            label = "Border Tint",
                            description = "Apply a custom tint color to addon button borders.",
                            get = function()
                                return getSetting("addonButtonBorderTintEnabled") or false
                            end,
                            set = function(v)
                                setSetting("addonButtonBorderTintEnabled", v)
                            end,
                            getColor = function()
                                local c = getSetting("addonButtonBorderTintColor") or {1, 1, 1, 1}
                                return c[1], c[2], c[3], c[4]
                            end,
                            setColor = function(r, g, b, a)
                                setSetting("addonButtonBorderTintColor", {r, g, b, a})
                            end,
                            hasAlpha = true,
                            isDisabled = function()
                                return getSetting("hideAddonButtonBorders")
                            end,
                        })

                        tabBuilder:Finalize()
                    end,

                    ----------------------------------------------------------------
                    -- Tab: Mail
                    ----------------------------------------------------------------
                    mail = function(tabContent, tabBuilder)
                        tabBuilder:AddToggle({
                            label = "Enable Mail Notification Button",
                            description = "Show a mail notification button near the minimap when you have unread mail. Useful when the dock is hidden.",
                            get = function()
                                return getSetting("mailButtonEnabled") or false
                            end,
                            set = function(v)
                                setSetting("mailButtonEnabled", v)
                                -- Re-render to update disabled states
                                C_Timer.After(0.05, function()
                                    if panel and Minimap.Render then
                                        Minimap.Render(panel, scrollContent)
                                    end
                                end)
                            end,
                        })

                        tabBuilder:AddSelector({
                            label = "Button Position",
                            description = "Where to place the mail button relative to the minimap.",
                            values = anchorOptions,
                            order = anchorOrder,
                            get = function()
                                return getSetting("mailButtonAnchor") or "TOPRIGHT"
                            end,
                            set = function(v)
                                setSetting("mailButtonAnchor", v)
                            end,
                            isDisabled = function()
                                return not getSetting("mailButtonEnabled")
                            end,
                        })

                        tabBuilder:AddDualSlider({
                            label = "Button Offset",
                            sliderA = {
                                axisLabel = "X",
                                min = -100,
                                max = 100,
                                step = 1,
                                get = function()
                                    return getSetting("mailButtonOffsetX") or 0
                                end,
                                set = function(v)
                                    setSetting("mailButtonOffsetX", v)
                                end,
                            },
                            sliderB = {
                                axisLabel = "Y",
                                min = -100,
                                max = 100,
                                step = 1,
                                get = function()
                                    return getSetting("mailButtonOffsetY") or 0
                                end,
                                set = function(v)
                                    setSetting("mailButtonOffsetY", v)
                                end,
                            },
                            isDisabled = function()
                                return not getSetting("mailButtonEnabled")
                            end,
                        })

                        tabBuilder:Finalize()
                    end,

                    ----------------------------------------------------------------
                    -- Tab: Tracking
                    ----------------------------------------------------------------
                    tracking = function(tabContent, tabBuilder)
                        tabBuilder:AddToggle({
                            label = "Enable Custom Tracking Button",
                            description = "Show a standalone tracking button near the minimap. Useful when the dock is hidden.",
                            get = function()
                                return getSetting("trackingButtonEnabled") or false
                            end,
                            set = function(v)
                                setSetting("trackingButtonEnabled", v)
                                -- Re-render to update disabled states
                                C_Timer.After(0.05, function()
                                    if panel and Minimap.Render then
                                        Minimap.Render(panel, scrollContent)
                                    end
                                end)
                            end,
                        })

                        tabBuilder:AddSelector({
                            label = "Button Position",
                            description = "Where to place the tracking button relative to the minimap.",
                            values = anchorOptions,
                            order = anchorOrder,
                            get = function()
                                return getSetting("trackingButtonAnchor") or "TOPLEFT"
                            end,
                            set = function(v)
                                setSetting("trackingButtonAnchor", v)
                            end,
                            isDisabled = function()
                                return not getSetting("trackingButtonEnabled")
                            end,
                        })

                        tabBuilder:AddDualSlider({
                            label = "Button Offset",
                            sliderA = {
                                axisLabel = "X",
                                min = -100,
                                max = 100,
                                step = 1,
                                get = function()
                                    return getSetting("trackingButtonOffsetX") or 0
                                end,
                                set = function(v)
                                    setSetting("trackingButtonOffsetX", v)
                                end,
                            },
                            sliderB = {
                                axisLabel = "Y",
                                min = -100,
                                max = 100,
                                step = 1,
                                get = function()
                                    return getSetting("trackingButtonOffsetY") or 0
                                end,
                                set = function(v)
                                    setSetting("trackingButtonOffsetY", v)
                                end,
                            },
                            isDisabled = function()
                                return not getSetting("trackingButtonEnabled")
                            end,
                        })

                        tabBuilder:Finalize()
                    end,
                },
            })

            inner:Finalize()
        end,
    })

    ----------------------------------------------------------------------------
    -- Section 4: Visibility & Misc
    ----------------------------------------------------------------------------
    builder:AddCollapsibleSection({
        title = "Visibility & Misc",
        componentId = "minimapStyle",
        sectionKey = "visibility",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddToggle({
                label = "Enable Off-Screen Edit Mode Dragging",
                description = "Allows moving the minimap closer to or past screen edges during Edit Mode. Useful for Steam Deck and handheld setups.",
                get = function()
                    return getSetting("allowOffScreenDragging") or false
                end,
                set = function(v)
                    setSetting("allowOffScreenDragging", v)
                end,
            })

            inner:Finalize()
        end,
    })

    ----------------------------------------------------------------------------
    -- Section 5: Minimap Overlay System
    ----------------------------------------------------------------------------

    local overlayButtonPositionValues = {
        TOPLEFT = "Top Left",
        TOP = "Top",
        TOPRIGHT = "Top Right",
        LEFT = "Left",
        RIGHT = "Right",
        BOTTOMLEFT = "Bottom Left",
        BOTTOM = "Bottom",
        BOTTOMRIGHT = "Bottom Right",
    }
    local overlayButtonPositionOrder = {
        "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT",
    }

    builder:AddCollapsibleSection({
        title = "Minimap Overlay System",
        componentId = "minimapStyle",
        sectionKey = "minimapOverlay",
        defaultExpanded = false,
        infoIcon = {
            tooltipTitle = "Minimap Overlay",
            tooltipText = "Centers the minimap on your screen with terrain hidden, so the game world shows through while tracking blips, nodes, and your player arrow stay visible. Great for node hunting while flying.\n\nBackdrop controls the dark circular backing behind blips (higher = more opaque, lower = more transparent).\n\nNodes controls blip and node brightness.",
        },
        buildContent = function(contentFrame, inner)

            -- Master toggle (emphasized)
            inner:AddToggle({
                label = "Enable Minimap Overlay",
                description = "Show a toggle button on the minimap to activate the centered overlay.",
                emphasized = true,
                get = function()
                    return getSetting("overlayEnabled") or false
                end,
                set = function(v)
                    setSetting("overlayEnabled", v)
                    C_Timer.After(0.05, function()
                        if panel and Minimap.Render then
                            Minimap.Render(panel, scrollContent)
                        end
                    end)
                end,
            })

            inner:AddTabbedSection({
                tabs = {
                    { key = "overlaySizing", label = "Sizing" },
                    { key = "overlayVisibility", label = "Visibility" },
                    { key = "overlayNodes", label = "Nodes" },
                    { key = "overlayButton", label = "Minimap Button" },
                },
                componentId = "minimapStyle",
                sectionKey = "overlayTabs",
                buildContent = {
                    -- Tab: Sizing
                    overlaySizing = function(tabContent, tabBuilder)
                        tabBuilder:AddSlider({
                            label = "Overlay Scale",
                            description = "Size of the centered minimap overlay.",
                            min = 50, max = 300, step = 10,
                            get = function()
                                return math.floor((getSetting("overlayScale") or 1.0) * 100)
                            end,
                            set = function(v)
                                setSetting("overlayScale", v / 100)
                            end,
                            minLabel = "50%", maxLabel = "300%",
                            isDisabled = function()
                                return not getSetting("overlayEnabled")
                            end,
                        })

                        tabBuilder:Finalize()
                    end,

                    -- Tab: Visibility
                    overlayVisibility = function(tabContent, tabBuilder)
                        tabBuilder:AddToggle({
                            label = "Hide Overlay During Combat",
                            description = "Automatically deactivate the overlay when entering combat and restore it after.",
                            get = function()
                                return getSetting("overlayCombatHide")
                            end,
                            set = function(v)
                                setSetting("overlayCombatHide", v)
                            end,
                            isDisabled = function()
                                return not getSetting("overlayEnabled")
                            end,
                        })

                        tabBuilder:AddDualSlider({
                            label = "Opacity",
                            sliderA = {
                                axisLabel = "Backdrop",
                                min = 0, max = 100, step = 5,
                                get = function()
                                    return math.floor((1 - (getSetting("overlayMapOpacity") or 0.85)) * 100)
                                end,
                                set = function(v)
                                    setSetting("overlayMapOpacity", 1 - (v / 100))
                                end,
                                minLabel = "0%", maxLabel = "100%",
                            },
                            sliderB = {
                                axisLabel = "Nodes",
                                min = 0, max = 100, step = 5,
                                get = function()
                                    return math.floor((getSetting("overlayNodesOpacity") or 1.0) * 100)
                                end,
                                set = function(v)
                                    setSetting("overlayNodesOpacity", v / 100)
                                end,
                                minLabel = "0%", maxLabel = "100%",
                            },
                            isDisabled = function()
                                return not getSetting("overlayEnabled")
                            end,
                        })

                        tabBuilder:Finalize()
                    end,

                    -- Tab: Nodes
                    overlayNodes = function(tabContent, tabBuilder)
                        tabBuilder:AddDescription("Coming Soon \226\128\148 All minimap tracking nodes are visible by default when the overlay is active. Per-node type filtering will be available in a future update.")

                        tabBuilder:Finalize()
                    end,

                    -- Tab: Minimap Button
                    overlayButton = function(tabContent, tabBuilder)
                        tabBuilder:AddSelector({
                            label = "Button Position",
                            description = "Where to place the overlay toggle button relative to the minimap.",
                            values = overlayButtonPositionValues,
                            order = overlayButtonPositionOrder,
                            get = function()
                                return getSetting("overlayButtonPosition") or "TOPRIGHT"
                            end,
                            set = function(v)
                                setSetting("overlayButtonPosition", v)
                            end,
                            isDisabled = function()
                                return not getSetting("overlayEnabled")
                            end,
                        })

                        tabBuilder:Finalize()
                    end,
                },
            })

            inner:Finalize()
        end,
    })

    -- Finalize the layout
    builder:Finalize()
end

--------------------------------------------------------------------------------
-- Self-register with settings panel
addon.UI.SettingsPanel:RegisterRenderer("minimap", function(panel, scrollContent)
    Minimap.Render(panel, scrollContent)
end)

-- Return module
--------------------------------------------------------------------------------

return Minimap
