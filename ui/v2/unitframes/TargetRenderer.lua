-- TargetRenderer.lua - Target Unit Frame TUI renderer
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.UnitFrames = addon.UI.UnitFrames or {}
local UF = addon.UI.UnitFrames
local SettingsBuilder = addon.UI.SettingsBuilder

local COMPONENT_ID = "ufTarget"
local UNIT_KEY = "Target"

--------------------------------------------------------------------------------
-- Bound Helpers
--------------------------------------------------------------------------------

local B = UF.BindUnit(UNIT_KEY)
local Sections = UF.Sections

--------------------------------------------------------------------------------
-- Renderer Function
--------------------------------------------------------------------------------

function UF.RenderTarget(panel, scrollContent)
    panel:ClearContent()

    local builder = SettingsBuilder:CreateFor(scrollContent)
    panel._currentBuilder = builder

    builder:SetOnRefresh(function()
        UF.RenderTarget(panel, scrollContent)
    end)

    --------------------------------------------------------------------------------
    -- Parent-Level Settings
    --------------------------------------------------------------------------------

    Sections.BuildParentControls(B, { builder = builder, componentId = COMPONENT_ID })

    --------------------------------------------------------------------------------
    -- Health Bar
    --------------------------------------------------------------------------------

    Sections.BuildHealthBarSection(B, {
        builder = builder, componentId = COMPONENT_ID,
        visibilityToggles = { "healthHideTextureOnly", "hideOverAbsorbGlow", "hideHealPrediction" },
    })

    --------------------------------------------------------------------------------
    -- Power Bar
    --------------------------------------------------------------------------------

    Sections.BuildPowerBarSection(B, {
        builder = builder, componentId = COMPONENT_ID,
        visibilityToggles = { "powerBarHidden" },
    })

    --------------------------------------------------------------------------------
    -- Cast Bar
    --------------------------------------------------------------------------------

    Sections.BuildCastBarSection(B, {
        builder = builder, componentId = COMPONENT_ID,
        anchorValues = {
            ["default"] = "Default (Blizzard)",
            ["nameTop"] = "Above Name",
            ["healthBottom"] = "Below Health Bar",
            ["powerTop"] = "Above Power Bar",
            ["powerBottom"] = "Below Power Bar",
        },
        anchorOrder = {"default", "nameTop", "healthBottom", "powerTop", "powerBottom"},
    })

    --------------------------------------------------------------------------------
    -- Buffs & Debuffs
    --------------------------------------------------------------------------------

    Sections.BuildBuffsDebuffsSection(B, { builder = builder, componentId = COMPONENT_ID })

    --------------------------------------------------------------------------------
    -- Name & Level Text
    --------------------------------------------------------------------------------

    Sections.BuildNameLevelTextSection(B, { builder = builder, componentId = COMPONENT_ID })

    --------------------------------------------------------------------------------
    -- Portrait
    --------------------------------------------------------------------------------

    Sections.BuildPortraitSection(B, { builder = builder, componentId = COMPONENT_ID })

    --------------------------------------------------------------------------------
    -- Finalize
    --------------------------------------------------------------------------------

    builder:Finalize()
end

--------------------------------------------------------------------------------
-- Self-register with settings panel
addon.UI.SettingsPanel:RegisterRenderer("ufTarget", function(panel, scrollContent)
    UF.RenderTarget(panel, scrollContent)
end)

-- Return renderer for registration
--------------------------------------------------------------------------------

return UF.RenderTarget
