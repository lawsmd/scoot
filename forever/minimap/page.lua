--------------------------------------------------------------------------------
-- forever/minimap/page.lua
-- The Minimap page, under Interface in forever/menu.lua.
--
-- Laid out after Scoot's page (ui/v2/settings/interface/MinimapRenderer.lua),
-- so a setting both products have sits in the same section under the same
-- label: Map Style, then Text with its Dock, Zone Text, Coordinates, Clock
-- and System Data tabs. Buttons and the node-hunting overlay follow with
-- phase 2. Loads on retail too, where no holder is built: the controls still
-- draw and write.
--------------------------------------------------------------------------------

local addonName, addon = ...

local MR = addon.MinimapReplica
local Style = MR.Style
local SettingsBuilder = addon.UI.SettingsBuilder
local Helpers = addon.UI.Settings.Helpers
local Catalogs = addon.Catalogs

local NAV_KEY = MR.NAV_KEY

local function apply()
    Style.Apply()
end

local function getSetting(key)
    return Style.Get(key)
end

local function setSetting(key, value)
    Style.Set(key, value)
    apply()
end

-- Position options: the shared nine points behind the header plate
local POSITION = Catalogs.WithLeading(Catalogs.Anchor9, "dock", "Default (Dock)")
-- The coordinates' default is Blizzard's own spot under the map, not the dock
local COORDS_POSITION = Catalogs.WithLeading(Catalogs.Anchor9, "default", "Default (Below Map)")

local MAP_SHAPE = {
    values = { default = "Default (Circle)", square = "Square" },
    order = { "default", "square" },
}
local ZONE_COLOR_MODE = {
    values = { pvp = "PVP Type", custom = "Custom" },
    order = { "pvp", "custom" },
}
local TIME_SOURCE = {
    values = { ["local"] = "Local Time", server = "Server Time" },
    order = { "local", "server" },
}
local LATENCY_SOURCE = {
    values = { home = "Home (Realm)", world = "World" },
    order = { "home", "world" },
}

local TEXT_SIZE = { min = Style.TEXT_SIZE.min, max = Style.TEXT_SIZE.max,
    minLabel = tostring(Style.TEXT_SIZE.min), maxLabel = tostring(Style.TEXT_SIZE.max) }

local function textAccessors(prefix)
    return Helpers.CreateFlatAccessors(getSetting, Style.Set, {
        fontFace = prefix .. "Font",
        style = prefix .. "FontStyle",
        size = prefix .. "FontSize",
        colorMode = prefix .. "ColorMode",
        color = prefix .. "CustomColor",
        anchor = prefix .. "Anchor",
        offsetX = prefix .. "OffsetX",
        offsetY = prefix .. "OffsetY",
    })
end

local OFFSET = { range = 50, minLabel = "-50", maxLabel = "+50" }

--------------------------------------------------------------------------------
-- Render
--------------------------------------------------------------------------------

local function Render(panel, scrollContent)
    panel:ClearContent()
    local builder = SettingsBuilder:CreateFor(scrollContent)
    panel._currentBuilder = builder
    builder:SetOnRefresh(function() Render(panel, scrollContent) end)

    -- A control whose change greys or reveals others re-renders the page.
    local function rerender()
        C_Timer.After(0.05, function()
            if panel then Render(panel, scrollContent) end
        end)
    end

    ----------------------------------------------------------------------------
    -- Map Style
    ----------------------------------------------------------------------------
    builder:AddCollapsibleSection({
        title = "Map Style",
        componentId = NAV_KEY,
        sectionKey = "mapStyle",
        defaultExpanded = false,
        buildContent = function(_, inner)
            inner:AddSelector({
                label = "Map Shape",
                description = "Change the minimap shape. Square removes the circular mask.",
                values = MAP_SHAPE.values, order = MAP_SHAPE.order,
                get = function() return Style.IsSquare() and "square" or "default" end,
                set = function(v)
                    setSetting("mapShape", v == "square" and "square" or "default")
                    rerender()
                end,
            })

            inner:AddSlider({
                label = "Map Size",
                description = "The map's scale. The game's own Edit Mode Size slider acts on the parked Blizzard frame, not on this map; its Icon Scale slider still does.",
                min = Style.MAP_SIZE.min, max = Style.MAP_SIZE.max, step = Style.MAP_SIZE.step,
                get = Style.MapSize,
                set = function(v) setSetting("mapSize", Style.Clamp(v, Style.MAP_SIZE)) end,
                minLabel = "50%", maxLabel = "200%",
            })

            -- Kept off Builder:AddBarBorderBlock: a partial with enable, tint, and thickness and no style selector.
            inner:AddToggle({
                label = "Enable Custom Border",
                description = "Replace the default square border with a solid one you can tint and size.",
                get = function() return getSetting("borderEnabled") == true end,
                set = function(v)
                    setSetting("borderEnabled", v and true or false)
                    rerender()
                end,
                isDisabled = function()
                    return not Style.IsSquare() or getSetting("borderHidden") == true
                end,
            })

            inner:AddToggleColorPicker({
                label = "Border Tint",
                description = "Apply a custom color to the border.",
                get = function() return getSetting("borderTintEnabled") == true end,
                set = function(v) setSetting("borderTintEnabled", v and true or false) end,
                getColor = function() return Style.Color("borderColor", { 0, 0, 0, 1 }) end,
                setColor = function(r, g, b, a) setSetting("borderColor", { r, g, b, a }) end,
                hasAlpha = true,
                isDisabled = function()
                    return not Style.IsSquare() or getSetting("borderEnabled") ~= true
                end,
            })

            inner:AddSlider({
                label = "Border Thickness",
                description = "The thickness of the border in pixels.",
                min = Style.BORDER_THICKNESS.min, max = Style.BORDER_THICKNESS.max, step = Style.BORDER_THICKNESS.step,
                get = Style.BorderThickness,
                set = function(v) setSetting("borderThickness", Style.Clamp(v, Style.BORDER_THICKNESS)) end,
                minLabel = "1", maxLabel = "8",
                isDisabled = function()
                    return not Style.IsSquare() or getSetting("borderEnabled") ~= true
                end,
            })

            inner:AddToggle({
                label = "Hide Border",
                description = "Draw no border around a square map.",
                get = function() return getSetting("borderHidden") == true end,
                set = function(v)
                    setSetting("borderHidden", v and true or false)
                    rerender()
                end,
                isDisabled = function() return not Style.IsSquare() end,
            })

            inner:Finalize()
        end,
    })

    ----------------------------------------------------------------------------
    -- Text
    ----------------------------------------------------------------------------
    builder:AddCollapsibleSection({
        title = "Text",
        componentId = NAV_KEY,
        sectionKey = "text",
        defaultExpanded = false,
        buildContent = function(_, inner)
            inner:AddTabbedSection({
                tabs = {
                    { key = "dock", label = "Dock" },
                    { key = "zoneText", label = "Zone Text" },
                    { key = "coords", label = "Coordinates" },
                    { key = "clock", label = "Clock" },
                    { key = "systemData", label = "System Data" },
                },
                componentId = NAV_KEY,
                sectionKey = "textTabs",
                buildContent = {
                    dock = function(_, tab)
                        tab:AddToggle({
                            label = "Hide Dock",
                            description = "Hide the plate above the map. The zone text and the clock hide with it while they sit on it.",
                            get = function() return getSetting("dockHide") == true end,
                            set = function(v) setSetting("dockHide", v and true or false) end,
                        })
                        tab:Finalize()
                    end,

                    zoneText = function(_, tab)
                        tab:AddToggle({
                            label = "Hide Zone Text",
                            description = "Hide the zone name display completely.",
                            get = function() return getSetting("zoneTextHide") == true end,
                            set = function(v) setSetting("zoneTextHide", v and true or false) end,
                        })
                        tab:AddSelector({
                            label = "Position",
                            description = "Where to show the zone text. 'Default (Dock)' is the plate above the map; the other options pin it to a side of the map.",
                            values = POSITION.values, order = POSITION.order,
                            get = function() return getSetting("zoneTextPosition") or "dock" end,
                            set = function(v)
                                setSetting("zoneTextPosition", v)
                                rerender()
                            end,
                        })
                        local get, set = textAccessors("zoneText")
                        local position = getSetting("zoneTextPosition") or "dock"
                        tab:AddTextStyleBlock({
                            get = get, set = set, apply = apply,
                            defaults = { size = 12, colorMode = "pvp", color = { 1, 0.82, 0, 1 } },
                            font = { description = "The font used for the zone text." },
                            style = { order = Helpers.fontStyleOrderPaired,
                                description = "The outline style for the zone text." },
                            size = { min = TEXT_SIZE.min, max = TEXT_SIZE.max, minLabel = TEXT_SIZE.minLabel, maxLabel = TEXT_SIZE.maxLabel,
                                description = "The size of the zone text." },
                            color = { values = ZONE_COLOR_MODE.values, order = ZONE_COLOR_MODE.order,
                                description = "How to color the zone text. PVP Type colors by the zone's rule." },
                            offset = position ~= "dock" and OFFSET or false,
                        })
                        tab:Finalize()
                    end,

                    coords = function(_, tab)
                        -- Where the client has Blizzard's own readout (12.1.5,
                        -- Forever) the two switches are its CVars, the same
                        -- checkboxes as Options > Interface; elsewhere they
                        -- are profile keys (text.lua).
                        local Text = MR.Text
                        local function switchGet(name, key)
                            local v = Text and Text.CoordsCVar(name)
                            if v == nil then v = getSetting(key) end
                            return v == true
                        end
                        local function switchSet(name, key, v)
                            if Text and Text.CoordsCVar(name) ~= nil then
                                Text.SetCoordsCVar(name, v)
                                apply()
                            else
                                setSetting(key, v and true or false)
                            end
                        end
                        tab:AddToggle({
                            label = "Show Coordinates",
                            description = "Show your position on the map as coordinates. Where the game has its own readout, this is its Show Player Coordinates option.",
                            get = function() return switchGet("show", "coordsEnabled") end,
                            set = function(v) switchSet("show", "coordsEnabled", v) end,
                        })
                        tab:AddToggle({
                            label = "Tenths",
                            description = "Show coordinates to one decimal place.",
                            get = function() return switchGet("tenths", "coordsTenths") end,
                            set = function(v) switchSet("tenths", "coordsTenths", v) end,
                        })
                        tab:AddSelector({
                            label = "Position",
                            description = "Where to show the coordinates. 'Default (Below Map)' is the game's own spot under the map.",
                            values = COORDS_POSITION.values, order = COORDS_POSITION.order,
                            get = function() return getSetting("coordsPosition") or "default" end,
                            set = function(v)
                                setSetting("coordsPosition", v)
                                rerender()
                            end,
                        })
                        local get, set = textAccessors("coords")
                        local position = getSetting("coordsPosition") or "default"
                        tab:AddTextStyleBlock({
                            get = get, set = set, apply = apply,
                            defaults = { size = 10 },
                            font = { description = "The font used for the coordinates." },
                            style = { order = Helpers.fontStyleOrderPaired,
                                description = "The outline style for the coordinates." },
                            size = { min = TEXT_SIZE.min, max = TEXT_SIZE.max, minLabel = TEXT_SIZE.minLabel, maxLabel = TEXT_SIZE.maxLabel,
                                description = "The size of the coordinates text." },
                            color = { description = "The color of the coordinates text." },
                            offset = position ~= "default" and OFFSET or false,
                        })
                        tab:Finalize()
                    end,

                    clock = function(_, tab)
                        tab:AddToggle({
                            label = "Hide Clock",
                            description = "Hide the clock display completely.",
                            get = function() return getSetting("clockHide") == true end,
                            set = function(v) setSetting("clockHide", v and true or false) end,
                        })
                        tab:AddSelector({
                            label = "Position",
                            description = "Where to show the clock. 'Default (Dock)' is the plate above the map; the other options pin it to a side of the map.",
                            values = POSITION.values, order = POSITION.order,
                            get = function() return getSetting("clockPosition") or "dock" end,
                            set = function(v)
                                setSetting("clockPosition", v)
                                rerender()
                            end,
                        })
                        tab:AddSelector({
                            label = "Time Source",
                            description = "Show local time or server time.",
                            values = TIME_SOURCE.values, order = TIME_SOURCE.order,
                            get = function() return getSetting("clockTimeSource") or "local" end,
                            set = function(v) setSetting("clockTimeSource", v) end,
                        })
                        tab:AddToggle({
                            label = "24-Hour Format",
                            description = "Use 24-hour time format instead of 12-hour with AM/PM.",
                            get = function() return getSetting("clockUse24Hour") == true end,
                            set = function(v) setSetting("clockUse24Hour", v and true or false) end,
                        })
                        local get, set = textAccessors("clock")
                        local position = getSetting("clockPosition") or "dock"
                        tab:AddTextStyleBlock({
                            get = get, set = set, apply = apply,
                            defaults = { size = 12 },
                            font = { description = "The font used for the clock." },
                            style = { order = Helpers.fontStyleOrderPaired,
                                description = "The outline style for the clock." },
                            size = { min = TEXT_SIZE.min, max = TEXT_SIZE.max, minLabel = TEXT_SIZE.minLabel, maxLabel = TEXT_SIZE.maxLabel,
                                description = "The size of the clock text." },
                            color = { description = "The color of the clock text." },
                            offset = position ~= "dock" and OFFSET or false,
                        })
                        tab:Finalize()
                    end,

                    systemData = function(_, tab)
                        tab:AddToggle({
                            label = "Show FPS",
                            description = "Display frames per second near the minimap.",
                            get = function() return getSetting("systemDataShowFPS") == true end,
                            set = function(v) setSetting("systemDataShowFPS", v and true or false) end,
                        })
                        tab:AddToggle({
                            label = "Show Latency",
                            description = "Display network latency near the minimap.",
                            get = function() return getSetting("systemDataShowLatency") == true end,
                            set = function(v)
                                setSetting("systemDataShowLatency", v and true or false)
                                rerender()
                            end,
                        })
                        tab:AddSelector({
                            label = "Latency Source",
                            description = "Which latency value to display.",
                            values = LATENCY_SOURCE.values, order = LATENCY_SOURCE.order,
                            get = function() return getSetting("systemDataLatencySource") or "home" end,
                            set = function(v) setSetting("systemDataLatencySource", v) end,
                            isDisabled = function() return getSetting("systemDataShowLatency") ~= true end,
                        })
                        local get, set = textAccessors("systemData")
                        tab:AddTextStyleBlock({
                            get = get, set = set, apply = apply,
                            defaults = { size = 11 },
                            font = { description = "The font used for system data." },
                            style = { order = Helpers.fontStyleOrderPaired,
                                description = "The outline style for system data." },
                            size = { min = TEXT_SIZE.min, max = TEXT_SIZE.max, minLabel = TEXT_SIZE.minLabel, maxLabel = TEXT_SIZE.maxLabel,
                                description = "The size of the system data text." },
                            color = { description = "The color of the system data text." },
                            alignment = { kind = "anchor9", default = "BOTTOM",
                                values = Catalogs.Anchor9.values, order = Catalogs.Anchor9.order,
                                description = "Where to position the system data relative to the minimap." },
                            offset = OFFSET,
                        })
                        tab:Finalize()
                    end,
                },
            })
            inner:Finalize()
        end,
    })

    builder:Finalize()
end

--------------------------------------------------------------------------------
-- Registration
--------------------------------------------------------------------------------

addon.UI.SettingsPanel:RegisterRenderer(NAV_KEY, Render)
