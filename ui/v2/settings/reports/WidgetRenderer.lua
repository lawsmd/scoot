-- WidgetRenderer.lua - Reports: Widget settings renderer
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.Settings = addon.UI.Settings or {}
addon.UI.Settings.Reports = addon.UI.Settings.Reports or {}
addon.UI.Settings.Reports.Widget = {}

local WidgetUI = addon.UI.Settings.Reports.Widget
local SettingsBuilder = addon.UI.SettingsBuilder
local Helpers = addon.UI.Settings.Helpers

--------------------------------------------------------------------------------
-- Render
--------------------------------------------------------------------------------

function WidgetUI.Render(panel, scrollContent)
    panel:ClearContent()

    local builder = SettingsBuilder:CreateFor(scrollContent)
    panel._currentBuilder = builder

    -- Re-render on collapsible toggle so Y positions recompute and sections don't overlap.
    builder:SetOnRefresh(function()
        WidgetUI.Render(panel, scrollContent)
    end)

    local h = Helpers.CreateComponentHelpers("widget")
    local get, setApply = h.get, h.setAndApply

    -- Pane-wide explanation: the widget can be enabled alone from the
    -- Features page, and a lone diamond needs explaining.
    if addon.Reports and addon.Reports.WIDGET_EXPLANATION then
        builder:AddDescription(addon.Reports.WIDGET_EXPLANATION)
    end

    -- Appearance
    builder:AddCollapsibleSection({
        title = "Appearance",
        componentId = "widget",
        sectionKey = "appearance",
        defaultExpanded = false,
        buildContent = function(_, inner)
            inner:AddSlider({
                label = "Icon Size",
                description = "Pixel size of the diamond.",
                min = 16, max = 40, step = 2,
                get = function() return tonumber(get("iconSize")) or 20 end,
                set = function(v) setApply("iconSize", tonumber(v) or 20) end,
            })
        end,
    })

    -- Position & Behavior
    builder:AddCollapsibleSection({
        title = "Position & Behavior",
        componentId = "widget",
        sectionKey = "behavior",
        defaultExpanded = false,
        buildContent = function(_, inner)
            inner:AddSelector({
                label = "Flyout Direction",
                description = "Which way notifications and reports grow out of the diamond.",
                values = {
                    down  = "Down",
                    up    = "Up",
                    right = "Right",
                    left  = "Left",
                },
                order = { "down", "up", "right", "left" },
                get = function() return get("flyoutDirection") or "down" end,
                set = function(v) setApply("flyoutDirection", v) end,
            })

            inner:AddSelector({
                label = "Frame Strata",
                description = "Layer the diamond renders on. Raise this if other UI is drawing over it.",
                values = {
                    BACKGROUND = "Background",
                    LOW        = "Low",
                    MEDIUM     = "Medium",
                    HIGH       = "High",
                    DIALOG     = "Dialog",
                },
                order = { "BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG" },
                get = function() return get("frameStrata") or "MEDIUM" end,
                set = function(v) setApply("frameStrata", v) end,
            })

            inner:AddDescription("Drag the diamond on screen to reposition. Run /scoot widget reset to return it to the default location.")
        end,
    })

    -- Combat Visibility
    builder:AddCollapsibleSection({
        title = "Combat Visibility",
        componentId = "widget",
        sectionKey = "visibility",
        defaultExpanded = false,
        buildContent = function(_, inner)
            inner:AddSlider({
                label = "Opacity in Combat",
                description = "Percent opacity while in combat. Set to 0 to hide entirely during fights.",
                min = 0, max = 100, step = 5,
                get = function() return tonumber(get("opacity")) or 40 end,
                set = function(v) setApply("opacity", tonumber(v) or 40) end,
            })
            inner:AddSlider({
                label = "Opacity Out of Combat",
                description = "Percent opacity outside of combat.",
                min = 0, max = 100, step = 5,
                get = function() return tonumber(get("opacityOutOfCombat")) or 100 end,
                set = function(v) setApply("opacityOutOfCombat", tonumber(v) or 100) end,
            })
            inner:AddSlider({
                label = "Opacity on Mouseover",
                description = "Percent opacity while the mouse is over the diamond. Use this to keep the icon faint in combat but visible when you reach for it.",
                min = 0, max = 100, step = 5,
                get = function() return tonumber(get("opacityHover")) or 100 end,
                set = function(v) setApply("opacityHover", tonumber(v) or 100) end,
            })
        end,
    })

    builder:Finalize()
end

--------------------------------------------------------------------------------
-- Register Renderer
--------------------------------------------------------------------------------

addon.UI.SettingsPanel:RegisterRenderer("reportsWidget", function(panel, scrollContent)
    WidgetUI.Render(panel, scrollContent)
end)

return WidgetUI
