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

--------------------------------------------------------------------------------
-- Shared Tab Builders
--------------------------------------------------------------------------------

local function buildStyleTab(inner, barPrefix, applyFn, colorValues, colorOrder, colorInfoIcons)
    local get, set = B.barAccessors(barPrefix)
    inner:AddBarStyleBlock({
        get = get, set = set, apply = applyFn,
        foreground = { values = colorValues, order = colorOrder, infoIcons = colorInfoIcons },
    })
    inner:Finalize()
end

local function buildBorderTab(inner, barPrefix, applyFn)
    local get, set = B.barAccessors(barPrefix)
    inner:AddBarBorderBlock({ get = get, set = set, apply = applyFn })
    inner:Finalize()
end

local function buildTextTab(inner, textKey, applyFn, defaultAlignment, colorValues, colorOrder)
    local get, set = B.textAccessors(textKey)
    inner:AddTextStyleBlock({
        get = get, set = set, apply = B.applyStyles,
        applyHidden = applyFn,
        hideToggle = true,
        color = { values = colorValues, order = colorOrder },
        alignment = { kind = "bossDual", default = defaultAlignment, key = textKey .. "AlignmentDual" },
    })
    inner:Finalize()
end

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

    builder:AddToggle({
        label = "Hide Blizzard Frame Art & Animations",
        description = "REQUIRED for custom borders. Hides default frame art.",
        emphasized = true,
        get = function() local t = B.getUFDB() or {}; return not not t.useCustomBorders end,
        set = function(v) local t = B.ensureUFDB(); if t then t.useCustomBorders = not not v; B.applyBarTextures() end end,
        infoIcon = UF.TOOLTIPS.hideBlizzardArt,
    })

    builder:AddToggle({
        label = "Use Larger Frame",
        description = "Uses the larger Boss frame variant (Edit Mode setting).",
        get = function()
            return UF.getUseLargerFrame(COMPONENT_ID)
        end,
        set = function(v)
            UF.setUseLargerFrame(COMPONENT_ID, v)
        end,
    })

    builder:AddSlider({
        label = "Scale",
        description = "Overall scale of boss frames.",
        min = 0.5, max = 2.0, step = 0.05, precision = 2,
        get = function() local t = B.getUFDB() or {}; return tonumber(t.scale) or 1.0 end,
        set = function(v) local t = B.ensureUFDB(); if t then t.scale = tonumber(v) or 1.0; B.applyStyles() end end,
        minLabel = "0.5x", maxLabel = "2.0x",
    })

    --------------------------------------------------------------------------------
    -- Health Bar (4 tabs: Style, Border, % Text, Value Text)
    --------------------------------------------------------------------------------

    builder:AddCollapsibleSection({
        title = "Health Bar",
        componentId = COMPONENT_ID,
        sectionKey = "healthBar",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddTabbedSection({
                tabs = {
                    { key = "style", label = "Style" },
                    { key = "border", label = "Border" },
                    { key = "percentText", label = "% Text" },
                    { key = "valueText", label = "Value Text" },
                    { key = "visibility", label = "Visibility" },
                },
                componentId = COMPONENT_ID,
                sectionKey = "healthBar_tabs",
                buildContent = {
                    style = function(cf, tabInner) buildStyleTab(tabInner, "healthBar", B.applyBarTextures) end,
                    border = function(cf, tabInner) buildBorderTab(tabInner, "healthBar", B.applyBarTextures) end,
                    visibility = function(cf, tabInner)
                        tabInner:AddToggle({
                            label = "Hide the Bar but not its Text",
                            get = function()
                                local t = B.getUFDB() or {}
                                return not not t.healthBarHideTextureOnly
                            end,
                            set = function(v)
                                local t = B.ensureUFDB()
                                if not t then return end
                                t.healthBarHideTextureOnly = v and true or false
                                B.applyBarTextures()
                            end,
                            infoIcon = {
                                tooltipTitle = "Hide the Bar but not its Text",
                                tooltipText = "Hides the bar texture and background, showing only the text overlay. Useful for a number-only display of health.",
                            },
                        })
                        tabInner:Finalize()
                    end,
                    percentText = function(cf, tabInner)
                        buildTextTab(tabInner, "textHealthPercent", B.applyHealthText, "LEFT", UF.fontColorHealthValues, UF.fontColorHealthOrder)
                    end,
                    valueText = function(cf, tabInner)
                        buildTextTab(tabInner, "textHealthValue", B.applyHealthText, "RIGHT", UF.fontColorHealthValues, UF.fontColorHealthOrder)
                    end,
                },
            })
            inner:Finalize()
        end,
    })

    --------------------------------------------------------------------------------
    -- Power Bar (7 tabs: Positioning, Sizing, Style, Border, Visibility, % Text, Value Text)
    --------------------------------------------------------------------------------

    local powerTabs = UF.getPowerBarTabs()

    builder:AddCollapsibleSection({
        title = "Power Bar",
        componentId = COMPONENT_ID,
        sectionKey = "powerBar",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddTabbedSection({
                tabs = powerTabs,
                componentId = COMPONENT_ID,
                sectionKey = "powerBar_tabs",
                buildContent = {
                    positioning = function(cf, tabInner)
                        tabInner:AddOffsetPair({
                            get = function(axis) local t = B.getUFDB(); return t and t[axis == "x" and "powerBarOffsetX" or "powerBarOffsetY"] end,
                            set = function(axis, v) local t = B.ensureUFDB(); if t then t[axis == "x" and "powerBarOffsetX" or "powerBarOffsetY"] = v end end,
                            apply = B.applyBarTextures,
                        })
                        tabInner:Finalize()
                    end,
                    sizing = function(cf, tabInner)
                        tabInner:AddSlider({
                            label = "Height %",
                            min = 10, max = 200, step = 5,
                            get = function() local t = B.getUFDB() or {}; return tonumber(t.powerBarHeightPct) or 100 end,
                            set = function(v) local t = B.ensureUFDB(); if t then t.powerBarHeightPct = tonumber(v) or 100; B.applyBarTextures() end end,
                        })
                        tabInner:Finalize()
                    end,
                    style = function(cf, tabInner) buildStyleTab(tabInner, "powerBar", B.applyBarTextures, UF.powerColorValues, UF.powerColorOrder) end,
                    border = function(cf, tabInner) buildBorderTab(tabInner, "powerBar", B.applyBarTextures) end,
                    visibility = function(cf, tabInner)
                        tabInner:AddToggle({
                            label = "Hide Power Bar",
                            get = function() local t = B.getUFDB() or {}; return not not t.powerBarHidden end,
                            set = function(v) local t = B.ensureUFDB(); if t then t.powerBarHidden = v and true or false; B.applyBarTextures() end end,
                        })
                        tabInner:AddToggle({
                            label = "Hide the Bar but not its Text",
                            get = function()
                                local t = B.getUFDB() or {}
                                return not not t.powerBarHideTextureOnly
                            end,
                            set = function(v)
                                local t = B.ensureUFDB()
                                if not t then return end
                                t.powerBarHideTextureOnly = v and true or false
                                B.applyBarTextures()
                            end,
                            infoIcon = {
                                tooltipTitle = "Hide the Bar but not its Text",
                                tooltipText = "Hides the bar texture and background, showing only the text overlay. Useful for a number-only display of power.",
                            },
                        })
                        tabInner:Finalize()
                    end,
                    percentText = function(cf, tabInner)
                        buildTextTab(tabInner, "textPowerPercent", B.applyPowerText, "LEFT")
                    end,
                    valueText = function(cf, tabInner)
                        buildTextTab(tabInner, "textPowerValue", B.applyPowerText, "RIGHT")
                    end,
                },
            })
            inner:Finalize()
        end,
    })

    --------------------------------------------------------------------------------
    -- Cast Bar (7 tabs: Positioning, Sizing, Style, Border, Icon, Spell Name, Visibility)
    --------------------------------------------------------------------------------

    local castBarTabs = UF.getCastBarTabs(COMPONENT_ID, {
        fillLineVisible = function()
            local t = B.getCastBarDB() or {}
            return (t.castBarMode or "default") == "textFill"
        end,
    })

    builder:AddCollapsibleSection({
        title = "Cast Bar",
        componentId = COMPONENT_ID,
        sectionKey = "castBar",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            local tabbedRef
            inner:AddSelector({
                label = "Mode",
                description = "Choose how the cast bar is displayed.",
                values = { default = "Default Cast Bar", textFill = "Text-Fill Cast Bar" },
                order = { "default", "textFill" },
                emphasized = true,
                get = function() local t = B.getCastBarDB() or {}; return t.castBarMode or "default" end,
                set = function(v)
                    local t = B.ensureCastBarDB()
                    if t then t.castBarMode = v; B.applyCastBar() end
                    if tabbedRef and tabbedRef.RefreshTabVisibility then
                        tabbedRef:RefreshTabVisibility()
                    end
                end,
            })
            tabbedRef = inner:AddTabbedSection({
                tabs = castBarTabs,
                componentId = COMPONENT_ID,
                sectionKey = "castBar_tabs",
                buildContent = {
                    positioning = function(cf, tabInner)
                        tabInner:AddSelector({
                            label = "Anchor To",
                            values = {
                                ["default"] = "Under Frame (Default)",
                                ["leftOfFrame"] = "Left of Frame",
                                ["centeredUnderPower"] = "Centered Under Power Bar",
                                ["underBossName"] = "Under Boss Name",
                            },
                            order = {"default", "leftOfFrame", "centeredUnderPower", "underBossName"},
                            get = function() local t = B.getCastBarDB() or {}; return t.anchorMode or "default" end,
                            set = function(v) local t = B.ensureCastBarDB(); if t then t.anchorMode = v; if addon.MarkBossCastBarOnSideDirty then addon.MarkBossCastBarOnSideDirty() end; B.applyCastBar() end end,
                        })
                        tabInner:AddOffsetPair({
                            range = 200,
                            get = function(axis) local t = B.getCastBarDB(); return t and t[axis == "x" and "offsetX" or "offsetY"] end,
                            set = function(axis, v) local t = B.ensureCastBarDB(); if t then t[axis == "x" and "offsetX" or "offsetY"] = v end end,
                            apply = B.applyCastBar,
                        })
                        tabInner:Finalize()
                    end,
                    sizing = function(cf, tabInner)
                        tabInner:AddSlider({
                            label = "Scale %", min = 50, max = 150, step = 1,
                            get = function() local t = B.getCastBarDB() or {}; return tonumber(t.castBarScale) or 100 end,
                            set = function(v) local t = B.ensureCastBarDB(); if t then t.castBarScale = tonumber(v) or 100; B.applyCastBar() end end,
                        })
                        tabInner:Finalize()
                    end,
                    style = function(cf, tabInner)
                        tabInner:AddBarTextureSelector({
                            label = "Foreground Texture",
                            get = function() local t = B.getCastBarDB() or {}; return t.castBarTexture or "default" end,
                            set = function(v) local t = B.ensureCastBarDB(); if t then t.castBarTexture = v or "default"; B.applyCastBar() end end,
                        })
                        tabInner:AddSelectorColorPicker({
                            label = "Foreground Color", values = UF.castBarColorValues, order = UF.castBarColorOrder,
                            get = function() local t = B.getCastBarDB() or {}; return t.castBarColorMode or "default" end,
                            set = function(v) local t = B.ensureCastBarDB(); if t then t.castBarColorMode = v or "default"; B.applyCastBar() end end,
                            getColor = function() local t = B.getCastBarDB() or {}; local c = t.castBarTint or {1,1,1,1}; return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 end,
                            setColor = function(r,g,b,a) local t = B.ensureCastBarDB(); if t then t.castBarTint = {r,g,b,a}; B.applyCastBar() end end,
                            customValue = "custom", hasAlpha = true,
                        })
                        tabInner:AddSpacer(8)
                        tabInner:AddBarTextureSelector({
                            label = "Background Texture",
                            get = function() local t = B.getCastBarDB() or {}; return t.castBarBackgroundTexture or "default" end,
                            set = function(v) local t = B.ensureCastBarDB(); if t then t.castBarBackgroundTexture = v or "default"; B.applyCastBar() end end,
                        })
                        tabInner:AddSelectorColorPicker({
                            label = "Background Color", values = UF.bgColorValues, order = UF.bgColorOrder,
                            get = function() local t = B.getCastBarDB() or {}; return t.castBarBackgroundColorMode or "default" end,
                            set = function(v) local t = B.ensureCastBarDB(); if t then t.castBarBackgroundColorMode = v or "default"; B.applyCastBar() end end,
                            getColor = function() local t = B.getCastBarDB() or {}; local c = t.castBarBackgroundTint or {0,0,0,1}; return c[1] or 0, c[2] or 0, c[3] or 0, c[4] or 1 end,
                            setColor = function(r,g,b,a) local t = B.ensureCastBarDB(); if t then t.castBarBackgroundTint = {r,g,b,a}; B.applyCastBar() end end,
                            customValue = "custom", hasAlpha = true,
                        })
                        tabInner:AddSlider({
                            label = "Background Opacity", min = 0, max = 100, step = 1,
                            get = function() local t = B.getCastBarDB() or {}; return tonumber(t.castBarBackgroundOpacity) or 50 end,
                            set = function(v) local t = B.ensureCastBarDB(); if t then t.castBarBackgroundOpacity = tonumber(v) or 50; B.applyCastBar() end end,
                        })
                        tabInner:Finalize()
                    end,
                    fillLine = function(cf, tabInner)
                        tabInner:AddDescription(
                            "The fill color used in Text-Fill Mode is decided by the Spell Name text's font color.",
                            { color = {1, 0.82, 0}, fontSize = 14, topPadding = 4 }
                        )
                        tabInner:AddColorPicker({
                            label = "Unfilled Text Color",
                            get = function()
                                local t = B.getCastBarDB() or {}
                                local c = t.textFillUnfilledTextColor or {0.5, 0.5, 0.5, 1}
                                return c[1] or 0.5, c[2] or 0.5, c[3] or 0.5, c[4] or 1
                            end,
                            set = function(r, g, b, a)
                                local t = B.ensureCastBarDB()
                                if t then
                                    t.textFillUnfilledTextColor = {r, g, b, a}
                                    B.applyCastBar()
                                end
                            end,
                            hasAlpha = true,
                        })
                        tabInner:AddSlider({
                            label = "Line Height", min = 1, max = 10, step = 1,
                            get = function() local t = B.getCastBarDB() or {}; return tonumber(t.textFillLineHeight) or 2 end,
                            set = function(v) local t = B.ensureCastBarDB(); if t then t.textFillLineHeight = tonumber(v) or 2; B.applyCastBar() end end,
                        })
                        tabInner:AddSlider({
                            label = "End Cap Size", min = 2, max = 20, step = 1,
                            get = function() local t = B.getCastBarDB() or {}; return tonumber(t.textFillEndCapSize) or 6 end,
                            set = function(v) local t = B.ensureCastBarDB(); if t then t.textFillEndCapSize = tonumber(v) or 6; B.applyCastBar() end end,
                        })
                        tabInner:Finalize()
                    end,
                    spark = function(cf, tabInner)
                        tabInner:AddToggle({
                            label = "Hide Spark",
                            get = function() local t = B.getCastBarDB() or {}; return not not t.castBarSparkHidden end,
                            set = function(v) local t = B.ensureCastBarDB(); if t then t.castBarSparkHidden = v and true or false; B.applyCastBar() end end,
                        })
                        tabInner:AddSelectorColorPicker({
                            label = "Spark Color",
                            values = { ["default"] = "Default", ["custom"] = "Custom" },
                            order = { "default", "custom" },
                            get = function() local t = B.getCastBarDB() or {}; return t.castBarSparkColorMode or "default" end,
                            set = function(v) local t = B.ensureCastBarDB(); if t then t.castBarSparkColorMode = v or "default"; B.applyCastBar() end end,
                            getColor = function() local t = B.getCastBarDB() or {}; local c = t.castBarSparkTint or {1,1,1,1}; return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 end,
                            setColor = function(r,g,b,a) local t = B.ensureCastBarDB(); if t then t.castBarSparkTint = {r,g,b,a}; B.applyCastBar() end end,
                            customValue = "custom", hasAlpha = true,
                        })
                        tabInner:Finalize()
                    end,
                    border = function(cf, tabInner)
                        local get, set = B.barAccessors("castBar", { store = "castBar" })
                        tabInner:AddBarBorderBlock({ get = get, set = set, apply = B.applyCastBar, enableToggle = true })
                        tabInner:Finalize()
                    end,
                    icon = function(cf, tabInner)
                        tabInner:AddToggle({
                            label = "Hide Icon",
                            get = function() local t = B.getCastBarDB() or {}; return not not t.iconDisabled end,
                            set = function(v) local t = B.ensureCastBarDB(); if t then t.iconDisabled = v and true or false; B.applyCastBar() end end,
                        })
                        tabInner:AddToggle({
                            label = "Hide Icon Backdrop (Shield)",
                            get = function() local t = B.getCastBarDB() or {}; return not not t.castBarBorderShieldHidden end,
                            set = function(v) local t = B.ensureCastBarDB(); if t then t.castBarBorderShieldHidden = v and true or false; B.applyCastBar() end end,
                        })
                        tabInner:AddSlider({
                            label = "Icon Size", min = 10, max = 64, step = 1,
                            get = function() local t = B.getCastBarDB() or {}; return tonumber(t.iconWidth) or tonumber(t.iconHeight) or 24 end,
                            set = function(v) local t = B.ensureCastBarDB(); if t then t.iconWidth = tonumber(v) or 24; t.iconHeight = tonumber(v) or 24; B.applyCastBar() end end,
                        })
                        tabInner:AddOffsetPair({
                            label = "Icon Offset",
                            get = function(axis) local t = B.getCastBarDB(); return t and t[axis == "x" and "castBarIconOffsetX" or "castBarIconOffsetY"] end,
                            set = function(axis, v) local t = B.ensureCastBarDB(); if t then t[axis == "x" and "castBarIconOffsetX" or "castBarIconOffsetY"] = v end end,
                            apply = B.applyCastBar,
                        })
                        tabInner:Finalize()
                    end,
                    spellName = function(cf, tabInner)
                        tabInner:AddToggle({
                            label = "Hide Spell Name",
                            get = function() local t = B.getCastBarDB() or {}; return not not t.castBarSpellNameHidden end,
                            set = function(v) local t = B.ensureCastBarDB(); if t then t.castBarSpellNameHidden = v and true or false; B.applyCastBar() end end,
                        })
                        tabInner:AddToggle({
                            label = "Hide Spell Name Border",
                            get = function() local t = B.getCastBarDB() or {}; return not not t.hideSpellNameBorder end,
                            set = function(v) local t = B.ensureCastBarDB(); if t then t.hideSpellNameBorder = v and true or false; B.applyCastBar() end end,
                        })
                        local get, set = B.castBarTextAccessors("spellNameText")
                        tabInner:AddTextStyleBlock({
                            get = get, set = set, apply = B.applyCastBar,
                            defaults = { size = 10 },
                            size = { min = 6, max = 32 },
                            color = {
                                values = UF.fontColorCastBarNonPlayerValues,
                                order = UF.fontColorCastBarNonPlayerOrder,
                                customValue = { "custom", "customGradient" },
                            },
                            offset = false,
                        })
                        tabInner:Finalize()
                    end,
                    castTime = function(cf, tabInner)
                        local get, set = B.castBarTextAccessors("castTimeText")
                        tabInner:AddTextStyleBlock({
                            get = get, set = set, apply = B.applyCastBar,
                            defaults = { size = 10 },
                            size = { min = 6, max = 32 },
                            color = { kind = "plain" },
                            offset = false,
                        })
                        tabInner:Finalize()
                    end,
                    visibility = function(cf, tabInner)
                        tabInner:AddToggle({
                            label = "Hide Cast Bar",
                            get = function() local t = B.getCastBarDB() or {}; return not not t.castBarHidden end,
                            set = function(v) local t = B.ensureCastBarDB(); if t then t.castBarHidden = v and true or false; B.applyCastBar() end end,
                        })
                        tabInner:Finalize()
                    end,
                },
            })
            inner:Finalize()
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
