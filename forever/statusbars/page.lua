--------------------------------------------------------------------------------
-- forever/statusbars/page.lua
-- The Status Bars page, under Interface in forever/menu.lua: a section per
-- bar with the rows the Edit Mode dialog carries. Loads on retail too, where
-- no bar is built: the controls still draw and write.
--------------------------------------------------------------------------------

local addonName, addon = ...

local SB = addon.StatusBars
local Style = SB.Style
local SettingsBuilder = addon.UI.SettingsBuilder

local NAV_KEY = SB.NAV_KEY

local SECTION_TITLES = { "Status Bar 1", "Status Bar 2" }

local function addBar(builder, index)
    builder:AddCollapsibleSection({
        title = SECTION_TITLES[index],
        componentId = NAV_KEY,
        sectionKey = "bar" .. index,
        defaultExpanded = index == 1,
        buildContent = function(_, inner)
            inner:AddSlider({
                label = "Width",
                min = Style.WIDTH.min, max = Style.WIDTH.max, step = Style.WIDTH.step, precision = 0,
                minLabel = Style.WIDTH.min .. "%", maxLabel = Style.WIDTH.max .. "%",
                get = function() return Style.Width(index) end,
                set = function(v)
                    Style.Set(index, "width", Style.Clamp(v, Style.WIDTH))
                    Style.Apply()
                end,
            })
            inner:AddSlider({
                label = "Opacity",
                min = Style.OPACITY.min, max = Style.OPACITY.max, step = Style.OPACITY.step, precision = 0,
                minLabel = "0%", maxLabel = "100%",
                get = function() return Style.Opacity(index) end,
                set = function(v)
                    Style.Set(index, "opacity", Style.Clamp(v, Style.OPACITY))
                    Style.Apply()
                end,
            })
            inner:AddToggle({
                label = "Always Show Text",
                get = function() return Style.AlwaysShowText(index) end,
                set = function(v)
                    Style.Set(index, "alwaysShowText", v and true or false)
                    Style.Apply()
                end,
            })
            inner:AddToggle({
                label = "Show Level",
                get = function() return Style.ShowLevel(index) end,
                set = function(v)
                    Style.Set(index, "showLevel", v and true or false)
                    Style.Apply()
                end,
            })
            inner:Finalize()
        end,
    })
end

local function Render(panel, scrollContent)
    panel:ClearContent()
    local builder = SettingsBuilder:CreateFor(scrollContent)
    panel._currentBuilder = builder
    builder:SetOnRefresh(function() Render(panel, scrollContent) end)
    addBar(builder, 1)
    addBar(builder, 2)
    builder:Finalize()
end

addon.UI.SettingsPanel:RegisterRenderer(NAV_KEY, Render)
