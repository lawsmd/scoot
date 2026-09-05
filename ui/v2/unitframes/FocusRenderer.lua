-- FocusRenderer.lua - Focus Unit Frame TUI renderer
-- Similar to Target but adds "Use Larger Frame" and "Hide Threat Meter"
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.UnitFrames = addon.UI.UnitFrames or {}
local UF = addon.UI.UnitFrames
local SettingsBuilder = addon.UI.SettingsBuilder

local COMPONENT_ID = "ufFocus"
local UNIT_KEY = "Focus"

--------------------------------------------------------------------------------
-- Bound Helpers
--------------------------------------------------------------------------------

local B = UF.BindUnit(UNIT_KEY)
local Sections = UF.Sections

--------------------------------------------------------------------------------
-- Renderer Function
--------------------------------------------------------------------------------

function UF.RenderFocus(panel, scrollContent)
    panel:ClearContent()

    local builder = SettingsBuilder:CreateFor(scrollContent)
    panel._currentBuilder = builder

    builder:SetOnRefresh(function()
        UF.RenderFocus(panel, scrollContent)
    end)

    --------------------------------------------------------------------------------
    -- Parent-Level Settings (Focus-specific additions)
    --------------------------------------------------------------------------------

    Sections.BuildParentControls(B, {
        builder = builder, componentId = COMPONENT_ID,
        useLargerFrame = { description = "Uses the larger Focus frame variant (Edit Mode setting)." },
    })

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
    -- Misc (Focus-specific: Hide Threat Meter) - ALWAYS LAST
    --------------------------------------------------------------------------------

    builder:AddCollapsibleSection({
        title = "Misc",
        componentId = COMPONENT_ID,
        sectionKey = "misc",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddToggle({
                label = "Hide Threat Meter",
                get = function() local t = B.getUFDB() or {}; return not not t.hideThreatMeter end,
                set = function(v) local t = B.ensureUFDB(); if t then t.hideThreatMeter = v and true or false; B.applyStyles() end end,
            })
            inner:Finalize()
        end,
    })

    builder:Finalize()
end

addon.UI.SettingsPanel:RegisterRenderer("ufFocus", function(panel, scrollContent)
    UF.RenderFocus(panel, scrollContent)
end)

return UF.RenderFocus
