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
    -- Collapsible Section: Name & Level Text
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
                            label = "Backdrop Color", values = UF.bgColorValues, order = UF.bgColorOrder,
                            get = function() local t = B.getUFDB() or {}; return t.nameBackdropColorMode or "default" end,
                            set = function(v) local t = B.ensureUFDB(); if t then t.nameBackdropColorMode = v or "default"; B.applyNameLevelText() end end,
                            getColor = function() local t = B.getUFDB() or {}; local c = t.nameBackdropTint or {1,1,1,1}; return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 end,
                            setColor = function(r,g,b,a) local t = B.ensureUFDB(); if t then t.nameBackdropTint = {r,g,b,a}; B.applyNameLevelText() end end,
                            customValue = "custom", hasAlpha = true,
                        })
                        tabInner:AddSlider({ label = "Backdrop Width (%)", min = 25, max = 300, step = 1,
                            get = function() local t = B.getUFDB() or {}; return tonumber(t.nameBackdropWidthPct) or 100 end,
                            set = function(v) local t = B.ensureUFDB(); if t then t.nameBackdropWidthPct = tonumber(v) or 100; B.applyNameLevelText() end end })
                        tabInner:AddSlider({ label = "Backdrop Opacity", min = 0, max = 100, step = 1,
                            get = function() local t = B.getUFDB() or {}; return tonumber(t.nameBackdropOpacity) or 50 end,
                            set = function(v) local t = B.ensureUFDB(); if t then t.nameBackdropOpacity = tonumber(v) or 50; B.applyNameLevelText() end end })
                        tabInner:Finalize()
                    end,
                    border = function(cf, tabInner)
                        local get, set = B.barAccessors("nameBackdrop", { suffixes = { enabled = "BorderEnabled" } })
                        tabInner:AddBarBorderBlock({ get = get, set = set, apply = B.applyNameLevelText, enableToggle = true })
                        tabInner:Finalize()
                    end,
                    nameText = function(cf, tabInner)
                        tabInner:AddToggle({ label = "Disable Name Text",
                            get = function() local t = B.getUFDB() or {}; return not not t.nameTextHidden end,
                            set = function(v) local t = B.ensureUFDB(); if t then t.nameTextHidden = v and true or false; B.applyNameLevelText() end end })
                        tabInner:AddSlider({ label = "Name Container Width", min = 80, max = 150, step = 5,
                            get = function() local s = B.getTextDB("textName") or {}; return tonumber(s.containerWidthPct) or 100 end,
                            set = function(v) local t = B.ensureTextDB("textName"); if t then t.containerWidthPct = tonumber(v) or 100; B.applyNameLevelText() end end })
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
    -- Collapsible Section: Portrait (Focus has 5 tabs - no Personal Text)
    --------------------------------------------------------------------------------

    builder:AddCollapsibleSection({
        title = "Portrait",
        componentId = COMPONENT_ID,
        sectionKey = "portrait",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddTabbedSection({
                tabs = {
                    { key = "positioning", label = "Positioning" },
                    { key = "sizing", label = "Sizing" },
                    { key = "mask", label = "Mask" },
                    { key = "border", label = "Border" },
                    { key = "visibility", label = "Visibility" },
                },
                componentId = COMPONENT_ID,
                sectionKey = "portrait_tabs",
                buildContent = {
                    positioning = function(cf, tabInner)
                        tabInner:AddOffsetPair({
                            get = function(axis) local t = B.getPortraitDB(); return t and t[axis == "x" and "offsetX" or "offsetY"] end,
                            set = function(axis, v) local t = B.ensurePortraitDB(); if t then t[axis == "x" and "offsetX" or "offsetY"] = v end end,
                            apply = B.applyPortrait,
                        })
                        tabInner:Finalize()
                    end,
                    sizing = function(cf, tabInner)
                        tabInner:AddSlider({ label = "Portrait Size (Scale)", min = 50, max = 200, step = 1,
                            get = function() local t = B.getPortraitDB() or {}; return tonumber(t.scale) or 100 end,
                            set = function(v) local t = B.ensurePortraitDB(); if t then t.scale = tonumber(v) or 100; B.applyPortrait() end end })
                        tabInner:Finalize()
                    end,
                    mask = function(cf, tabInner)
                        tabInner:AddSlider({ label = "Portrait Zoom", min = 100, max = 200, step = 1,
                            get = function() local t = B.getPortraitDB() or {}; return tonumber(t.zoom) or 100 end,
                            set = function(v) local t = B.ensurePortraitDB(); if t then t.zoom = tonumber(v) or 100; B.applyPortrait() end end })
                        tabInner:Finalize()
                    end,
                    border = function(cf, tabInner)
                        -- Kept off Builder:AddBarBorderBlock: a portrait border is a single texture with its own style list and color modes.
                        tabInner:AddToggle({ label = "Use Custom Border",
                            get = function() local t = B.getPortraitDB() or {}; return t.portraitBorderEnable == true end,
                            set = function(v) local t = B.ensurePortraitDB(); if t then t.portraitBorderEnable = (v == true); B.applyPortrait() end end })
                        local targetBorderValues = { texture_c = "Circle", texture_s = "Circle with Corner", rare_c = "Rare (Circle)", rare_s = "Rare (Square)" }
                        local targetBorderOrder = { "texture_c", "texture_s", "rare_c", "rare_s" }
                        tabInner:AddSelector({ label = "Border Style", values = targetBorderValues, order = targetBorderOrder,
                            get = function() local t = B.getPortraitDB() or {}; return t.portraitBorderStyle or "texture_c" end,
                            set = function(v) local t = B.ensurePortraitDB(); if t then t.portraitBorderStyle = v or "texture_c"; B.applyPortrait() end end })
                        tabInner:AddSlider({ label = "Border Inset", min = 1, max = 8, step = 0.5, precision = 1,
                            get = function() local t = B.getPortraitDB() or {}; local v = tonumber(t.portraitBorderThickness) or 1; return math.max(1, math.min(8, math.floor(v * 2 + 0.5) / 2)) end,
                            set = function(v) local t = B.ensurePortraitDB(); if t then t.portraitBorderThickness = math.max(1, math.min(8, math.floor((tonumber(v) or 1) * 2 + 0.5) / 2)); B.applyPortrait() end end })
                        tabInner:AddSelectorColorPicker({ label = "Border Color", values = UF.portraitBorderColorValues, order = UF.portraitBorderColorOrder,
                            get = function() local t = B.getPortraitDB() or {}; return t.portraitBorderColorMode or "texture" end,
                            set = function(v) local t = B.ensurePortraitDB(); if t then t.portraitBorderColorMode = v or "texture"; B.applyPortrait() end end,
                            getColor = function() local t = B.getPortraitDB() or {}; local c = t.portraitBorderTintColor or {1,1,1,1}; return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 end,
                            setColor = function(r,g,b,a) local t = B.ensurePortraitDB(); if t then t.portraitBorderTintColor = {r,g,b,a}; B.applyPortrait() end end,
                            customValue = "custom", hasAlpha = true })
                        tabInner:Finalize()
                    end,
                    visibility = function(cf, tabInner)
                        tabInner:AddToggle({ label = "Hide Portrait",
                            get = function() local t = B.getPortraitDB() or {}; return not not t.hidePortrait end,
                            set = function(v) local t = B.ensurePortraitDB(); if t then t.hidePortrait = v and true or false; B.applyPortrait() end end })
                        tabInner:Finalize()
                    end,
                },
            })
            inner:Finalize()
        end,
    })

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
