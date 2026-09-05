-- BossRenderer.lua - Boss Unit Frames TUI renderer
-- Boss frames have special implementation with conditional settings
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.UnitFrames = addon.UI.UnitFrames or {}
local UF = addon.UI.UnitFrames
local SettingsBuilder = addon.UI.SettingsBuilder

local COMPONENT_ID = "ufBoss"
local UNIT_KEY = "Boss"

--------------------------------------------------------------------------------
-- Bound Helpers
--------------------------------------------------------------------------------

local B = UF.BindUnit(UNIT_KEY, {
    -- Boss cast bars apply through their own path covering all five frames.
    applyCastBar = function()
        if addon.ApplyBossCastBarFor then
            addon.ApplyBossCastBarFor()
        else
            UF.applyCastBar(UNIT_KEY)
        end
    end,
})

local Sections = UF.Sections

--------------------------------------------------------------------------------
-- Renderer Function
--------------------------------------------------------------------------------

function UF.RenderBoss(panel, scrollContent)
    panel:ClearContent()

    local builder = SettingsBuilder:CreateFor(scrollContent)
    panel._currentBuilder = builder

    builder:SetOnRefresh(function()
        UF.RenderBoss(panel, scrollContent)
    end)

    --------------------------------------------------------------------------------
    -- Parent-Level Settings
    --------------------------------------------------------------------------------

    Sections.BuildParentControls(B, {
        builder = builder, componentId = COMPONENT_ID,
        useCustomBorders = { clearHealthBorder = false },
        useLargerFrame = { description = "Uses the larger Boss frame variant (Edit Mode setting)." },
        frameSize = false, scaleMult = false, bossScale = true,
    })

    --------------------------------------------------------------------------------
    -- Health Bar
    --------------------------------------------------------------------------------

    Sections.BuildHealthBarSection(B, {
        builder = builder, componentId = COMPONENT_ID,
        visibilityToggles = { "healthHideTextureOnly" },
        alignmentKind = "bossDual",
    })

    --------------------------------------------------------------------------------
    -- Power Bar
    --------------------------------------------------------------------------------

    Sections.BuildPowerBarSection(B, {
        builder = builder, componentId = COMPONENT_ID,
        visibilityToggles = { "powerBarHidden", "powerHideTextureOnly" },
        alignmentKind = "bossDual",
    })

    --------------------------------------------------------------------------------
    -- Cast Bar
    --------------------------------------------------------------------------------

    Sections.BuildCastBarSection(B, {
        builder = builder, componentId = COMPONENT_ID,
        anchorValues = {
            ["default"] = "Under Frame (Default)",
            ["leftOfFrame"] = "Left of Frame",
            ["centeredUnderPower"] = "Centered Under Power Bar",
            ["underBossName"] = "Under Boss Name",
        },
        anchorOrder = {"default", "leftOfFrame", "centeredUnderPower", "underBossName"},
        onAnchorSet = function()
            if addon.MarkBossCastBarOnSideDirty then addon.MarkBossCastBarOnSideDirty() end
        end,
    })

    --------------------------------------------------------------------------------
    -- Name & Level Text
    --------------------------------------------------------------------------------

    Sections.BuildNameLevelTextSection(B, {
        builder = builder, componentId = COMPONENT_ID,
        nameText = { containerWidthMax = 500 },
    })

    --------------------------------------------------------------------------------
    -- Visibility & Misc
    --------------------------------------------------------------------------------

    builder:AddCollapsibleSection({
        title = "Visibility & Misc",
        componentId = COMPONENT_ID,
        sectionKey = "visibilityMisc",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddToggle({
                label = "Hide Threat Tracker",
                get = function()
                    local t = B.getMiscDB() or {}
                    return not not t.hideBossThreatCounter
                end,
                set = function(v)
                    local t = B.ensureMiscDB()
                    if not t then return end
                    t.hideBossThreatCounter = v and true or false
                    if addon.ApplyBossThreatCounterVisibility then
                        addon.ApplyBossThreatCounterVisibility()
                    end
                end,
            })
            inner:AddToggle({
                label = "Hide Skull Icon",
                get = function()
                    local t = B.getMiscDB() or {}
                    return not not t.hideHighLevelIcon
                end,
                set = function(v)
                    local t = B.ensureMiscDB()
                    if not t then return end
                    t.hideHighLevelIcon = v and true or false
                    if addon.ApplyBossHighLevelIconVisibility then
                        addon.ApplyBossHighLevelIconVisibility()
                    end
                end,
            })
            inner:Finalize()
        end,
    })

    builder:Finalize()
end

addon.UI.SettingsPanel:RegisterRenderer("ufBoss", function(panel, scrollContent)
    UF.RenderBoss(panel, scrollContent)
end)

return UF.RenderBoss
