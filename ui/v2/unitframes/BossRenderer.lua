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
    -- Name & Level Text (4 tabs: Backdrop, Border, Name Text, Level Text)
    --------------------------------------------------------------------------------

    builder:AddCollapsibleSection({
        title = "Name & Level Text",
        componentId = COMPONENT_ID,
        sectionKey = "nameLevelText",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddTabbedSection({
                tabs = {
                    { key = "backdrop", label = "Backdrop" },
                    { key = "border", label = "Border" },
                    { key = "nameText", label = "Name Text" },
                    { key = "levelText", label = "Level Text" },
                },
                componentId = COMPONENT_ID,
                sectionKey = "nameLevelText_tabs",
                buildContent = {
                    backdrop = function(cf, tabInner)
                        tabInner:AddToggle({
                            label = "Enable Backdrop",
                            get = function() local t = B.getUFDB() or {}; return not not t.nameBackdropEnabled end,
                            set = function(v) local t = B.ensureUFDB(); if t then t.nameBackdropEnabled = not not v; B.applyNameLevelText() end end,
                        })
                        tabInner:AddBarTextureSelector({
                            label = "Backdrop Texture",
                            get = function() local t = B.getUFDB() or {}; return t.nameBackdropTexture or "" end,
                            set = function(v) local t = B.ensureUFDB(); if t then t.nameBackdropTexture = v; B.applyNameLevelText() end end,
                        })
                        tabInner:AddSelectorColorPicker({
                            label = "Backdrop Color",
                            values = UF.bgColorValues, order = UF.bgColorOrder,
                            get = function() local t = B.getUFDB() or {}; return t.nameBackdropColorMode or "default" end,
                            set = function(v) local t = B.ensureUFDB(); if t then t.nameBackdropColorMode = v or "default"; B.applyNameLevelText() end end,
                            getColor = function() local t = B.getUFDB() or {}; local c = t.nameBackdropTint or {1,1,1,1}; return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 end,
                            setColor = function(r,g,b,a) local t = B.ensureUFDB(); if t then t.nameBackdropTint = {r,g,b,a}; B.applyNameLevelText() end end,
                            customValue = "custom", hasAlpha = true,
                        })
                        tabInner:AddSlider({
                            label = "Backdrop Width (%)", min = 25, max = 300, step = 1,
                            get = function() local t = B.getUFDB() or {}; return tonumber(t.nameBackdropWidthPct) or 100 end,
                            set = function(v) local t = B.ensureUFDB(); if t then t.nameBackdropWidthPct = tonumber(v) or 100; B.applyNameLevelText() end end,
                        })
                        tabInner:AddSlider({
                            label = "Backdrop Opacity", min = 0, max = 100, step = 1,
                            get = function() local t = B.getUFDB() or {}; return tonumber(t.nameBackdropOpacity) or 50 end,
                            set = function(v) local t = B.ensureUFDB(); if t then t.nameBackdropOpacity = tonumber(v) or 50; B.applyNameLevelText() end end,
                        })
                        tabInner:Finalize()
                    end,
                    border = function(cf, tabInner)
                        local get, set = B.barAccessors("nameBackdrop", { suffixes = { enabled = "BorderEnabled" } })
                        tabInner:AddBarBorderBlock({ get = get, set = set, apply = B.applyNameLevelText, enableToggle = true })
                        tabInner:Finalize()
                    end,
                    nameText = function(cf, tabInner)
                        tabInner:AddToggle({
                            label = "Disable Name Text",
                            get = function() local t = B.getUFDB() or {}; return not not t.nameTextHidden end,
                            set = function(v) local t = B.ensureUFDB(); if t then t.nameTextHidden = v and true or false; B.applyNameLevelText() end end,
                        })
                        tabInner:AddSlider({
                            label = "Name Container Width", min = 80, max = 500, step = 5,
                            get = function() local s = B.getTextDB("textName") or {}; return tonumber(s.containerWidthPct) or 100 end,
                            set = function(v) local t = B.ensureTextDB("textName"); if t then t.containerWidthPct = tonumber(v) or 100; B.applyNameLevelText() end end,
                        })
                        local get, set = B.textAccessors("textName")
                        tabInner:AddTextStyleBlock({
                            get = get, set = set, apply = B.applyNameLevelText,
                            defaults = { color = {1, 0.82, 0, 1} },
                            alignment = { kind = "align", default = "LEFT" },
                        })
                        tabInner:Finalize()
                    end,
                    levelText = function(cf, tabInner)
                        local get, set = B.textAccessors("textLevel", { hiddenKey = "levelTextHidden" })
                        tabInner:AddTextStyleBlock({
                            get = get, set = set, apply = B.applyNameLevelText,
                            defaults = { color = {1, 0.82, 0, 1} },
                            hideToggle = { label = "Disable Level Text" },
                        })
                        tabInner:Finalize()
                    end,
                },
            })
            inner:Finalize()
        end,
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
