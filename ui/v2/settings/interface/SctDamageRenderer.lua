-- SctDamageRenderer.lua - Scrolling Combat Text Damage Numbers renderer
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.Settings = addon.UI.Settings or {}
addon.UI.Settings.SctDamage = {}

local SctDamage = addon.UI.Settings.SctDamage
local SettingsBuilder = addon.UI.SettingsBuilder

--------------------------------------------------------------------------------
-- Render Function
--------------------------------------------------------------------------------

function SctDamage.Render(panel, scrollContent)
    panel:ClearContent()

    local builder = SettingsBuilder:CreateFor(scrollContent)
    panel._currentBuilder = builder

    local Helpers = addon.UI.Settings.Helpers
    local h = Helpers.CreateComponentHelpers("sctDamage")
    local getComponent, getSetting, setSetting = h.getComponent, h.get, h.set

    builder:AddDescription(
        "Changes to the damage number font require a full game restart (not just a reload) to take effect. " ..
        "The scale slider applies immediately."
    )

    -- Kept off Builder:AddTextStyleBlock: the damage font pairs with a scale percentage; the block has no scale slider.
    builder:AddFontSelector({
        label = "Font",
        description = "The font used for floating combat text damage numbers.",
        get = function()
            return getSetting("fontFace") or "FRIZQT__"
        end,
        set = function(fontKey)
            setSetting("fontFace", fontKey or "FRIZQT__")
            local comp = getComponent()
            if comp and comp.ApplyStyling then
                comp:ApplyStyling()
            end
        end,
    })

    builder:AddSlider({
        label = "Font Scale",
        description = "Scale of floating combat text numbers (affects all world text).",
        min = 20,
        max = 150,
        step = 1,
        get = function()
            return getSetting("fontScale") or 100
        end,
        set = function(v)
            setSetting("fontScale", v)
            local comp = getComponent()
            if comp and comp.ApplyStyling then
                comp:ApplyStyling()
            end
        end,
        minLabel = "20%",
        maxLabel = "150%",
    })

    builder:Finalize()
end

--------------------------------------------------------------------------------
-- Self-register with settings panel
addon.UI.SettingsPanel:RegisterRenderer("sctDamage", function(panel, scrollContent)
    SctDamage.Render(panel, scrollContent)
end)

-- Return module
--------------------------------------------------------------------------------

return SctDamage
