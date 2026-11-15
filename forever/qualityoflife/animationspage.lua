--------------------------------------------------------------------------------
-- forever/qualityoflife/animationspage.lua
-- The Animations page under Quality of Life: one toggle per overhead bar
-- (animations.lua).
--------------------------------------------------------------------------------

local addonName, addon = ...

local Animations = addon.QualityOfLife.Animations
local SettingsBuilder = addon.UI.SettingsBuilder

local NAV_KEY = Animations.NAV_KEY

local ROWS = {
    { kind = "food", label = "Health Bar While Eating" },
    { kind = "drink", label = "Mana Bar While Drinking" },
    { kind = "campfire", label = "Campfire Bar" },
}

local function Render(panel, scrollContent)
    panel:ClearContent()
    local builder = SettingsBuilder:CreateFor(scrollContent)
    panel._currentBuilder = builder
    builder:SetOnRefresh(function() Render(panel, scrollContent) end)

    builder:AddCollapsibleSection({ title = "Overhead Bars", componentId = NAV_KEY,
        sectionKey = "overhead", defaultExpanded = true,
        buildContent = function(_, inner)
            local scale = Animations.SCALE
            inner:AddSlider({ label = "Scale",
                min = scale.min, max = scale.max, step = scale.step, precision = 0,
                minLabel = scale.min .. "%", maxLabel = scale.max .. "%",
                get = Animations.Scale,
                set = function(v) Animations.SetScale(v) end })
            for _, row in ipairs(ROWS) do
                inner:AddToggle({
                    label = row.label,
                    get = function() return Animations.IsOn(row.kind) end,
                    set = function(value) Animations.SetOn(row.kind, value) end,
                })
            end
            inner:Finalize()
        end })

    builder:Finalize()
end

addon.UI.SettingsPanel:RegisterRenderer(NAV_KEY, Render)
