-- TargetFocusRenderer.lua - Target and Focus Unit Frame TUI renderers.
-- The two pages assemble the same UF.Sections builders in the same order; the
-- differences are the tokens in UNITS: the unit key, the Use Larger Frame
-- toggle, and Focus's Misc section.
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.UnitFrames = addon.UI.UnitFrames or {}
local UF = addon.UI.UnitFrames
local SettingsBuilder = addon.UI.SettingsBuilder
local Sections = UF.Sections

local CAST_BAR_ANCHOR_VALUES = {
    ["default"] = "Default (Blizzard)",
    ["nameTop"] = "Above Name",
    ["healthBottom"] = "Below Health Bar",
    ["powerTop"] = "Above Power Bar",
    ["powerBottom"] = "Below Power Bar",
}
local CAST_BAR_ANCHOR_ORDER = {"default", "nameTop", "healthBottom", "powerTop", "powerBottom"}

local UNITS = {
    {
        componentId = "ufTarget",
        unitKey = "Target",
    },
    {
        componentId = "ufFocus",
        unitKey = "Focus",
        useLargerFrame = { description = "Uses the larger Focus frame variant (Edit Mode setting)." },
        -- Focus's Misc section; always last.
        extraSections = function(B, builder, componentId)
            builder:AddCollapsibleSection({
                title = "Misc",
                componentId = componentId,
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
        end,
    },
}

local function CreateRenderer(unit)
    local COMPONENT_ID = unit.componentId
    local B = UF.BindUnit(unit.unitKey)

    local function render(panel, scrollContent)
        panel:ClearContent()

        local builder = SettingsBuilder:CreateFor(scrollContent)
        panel._currentBuilder = builder

        builder:SetOnRefresh(function()
            render(panel, scrollContent)
        end)

        Sections.BuildParentControls(B, {
            builder = builder, componentId = COMPONENT_ID,
            useLargerFrame = unit.useLargerFrame,
        })

        Sections.BuildHealthBarSection(B, {
            builder = builder, componentId = COMPONENT_ID,
            visibilityToggles = { "healthHideTextureOnly", "hideOverAbsorbGlow", "hideHealPrediction" },
        })

        Sections.BuildPowerBarSection(B, {
            builder = builder, componentId = COMPONENT_ID,
            visibilityToggles = { "powerBarHidden" },
        })

        Sections.BuildCastBarSection(B, {
            builder = builder, componentId = COMPONENT_ID,
            anchorValues = CAST_BAR_ANCHOR_VALUES,
            anchorOrder = CAST_BAR_ANCHOR_ORDER,
        })

        Sections.BuildBuffsDebuffsSection(B, { builder = builder, componentId = COMPONENT_ID })

        Sections.BuildNameLevelTextSection(B, { builder = builder, componentId = COMPONENT_ID })

        Sections.BuildPortraitSection(B, { builder = builder, componentId = COMPONENT_ID })

        if unit.extraSections then
            unit.extraSections(B, builder, COMPONENT_ID)
        end

        builder:Finalize()
    end

    return render
end

for _, unit in ipairs(UNITS) do
    addon.UI.SettingsPanel:RegisterRenderer(unit.componentId, CreateRenderer(unit))
end
