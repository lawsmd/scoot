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

--------------------------------------------------------------------------------
-- Shared Tab Builders (reuse helpers from Player renderer pattern)
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
        alignment = { kind = "align", default = defaultAlignment },
    })
    inner:Finalize()
end

--------------------------------------------------------------------------------
-- Health Bar Visibility Tab (Target/Focus: 3 toggles, no Health Loss Animation)
--------------------------------------------------------------------------------

local function buildHealthVisibilityTab(inner)
    inner:AddToggle({
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

    inner:AddToggle({
        label = "Hide Over Absorb Glow",
        description = "Hides the glow effect when absorb shields exceed max health.",
        get = function()
            local t = B.getUFDB() or {}
            return not not t.healthBarHideOverAbsorbGlow
        end,
        set = function(v)
            local t = B.ensureUFDB()
            if not t then return end
            t.healthBarHideOverAbsorbGlow = v and true or false
            B.applyBarTextures()
        end,
        infoIcon = UF.TOOLTIPS.hideOverAbsorbGlow,
    })

    inner:AddToggle({
        label = "Hide Heal Prediction",
        description = "Hides the green heal prediction bar when healing is incoming.",
        get = function()
            local t = B.getUFDB() or {}
            return not not t.healthBarHideHealPrediction
        end,
        set = function(v)
            local t = B.ensureUFDB()
            if not t then return end
            t.healthBarHideHealPrediction = v and true or false
            B.applyBarTextures()
        end,
        infoIcon = {
            tooltipTitle = "Hide Heal Prediction",
            tooltipText = "Hides the green heal prediction bar that appears on the health bar when a heal is incoming.",
        },
    })

    inner:Finalize()
end

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

    builder:AddToggle({
        label = "Hide Blizzard Frame Art & Animations",
        description = "REQUIRED for custom borders. Hides default frame art.",
        emphasized = true,
        get = function()
            local t = B.getUFDB() or {}
            return not not t.useCustomBorders
        end,
        set = function(v)
            local t = B.ensureUFDB()
            if not t then return end
            t.useCustomBorders = not not v
            if not v then t.healthBarHideBorder = false end
            B.applyBarTextures()
        end,
        infoIcon = UF.TOOLTIPS.hideBlizzardArt,
    })

    builder:AddSlider({
        label = "Frame Size (Scale)",
        description = "Blizzard's Edit Mode scale (100-200%).",
        min = 100,
        max = 200,
        step = 5,
        get = function()
            return UF.getEditModeFrameSize(COMPONENT_ID)
        end,
        set = function(v)
            UF.setEditModeFrameSize(COMPONENT_ID, v)
        end,
        minLabel = "100%",
        maxLabel = "200%",
        infoIcon = UF.TOOLTIPS.frameSize,
    })

    builder:AddSlider({
        label = "Scale Multiplier",
        description = "Addon multiplier on top of Edit Mode scale.",
        min = 1.0,
        max = 2.0,
        step = 0.05,
        precision = 2,
        get = function()
            local t = B.getUFDB() or {}
            return tonumber(t.scaleMult) or 1.0
        end,
        set = function(v)
            local t = B.ensureUFDB()
            if not t then return end
            t.scaleMult = tonumber(v) or 1.0
            B.applyScaleMult()
        end,
        minLabel = "1.0x",
        maxLabel = "2.0x",
        infoIcon = UF.TOOLTIPS.scaleMult,
    })

    --------------------------------------------------------------------------------
    -- Health Bar
    --------------------------------------------------------------------------------

    local healthTabs = UF.getHealthBarTabs(COMPONENT_ID)

    builder:AddCollapsibleSection({
        title = "Health Bar",
        componentId = COMPONENT_ID,
        sectionKey = "healthBar",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddTabbedSection({
                tabs = healthTabs,
                componentId = COMPONENT_ID,
                sectionKey = "healthBar_tabs",
                buildContent = {
                    style = function(cf, tabInner)
                        buildStyleTab(tabInner, "healthBar", B.applyBarTextures)
                    end,
                    border = function(cf, tabInner)
                        buildBorderTab(tabInner, "healthBar", B.applyBarTextures)
                    end,
                    visibility = function(cf, tabInner)
                        buildHealthVisibilityTab(tabInner)
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
    -- Power Bar (7 tabs)
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
                    style = function(cf, tabInner)
                        buildStyleTab(tabInner, "powerBar", B.applyBarTextures, UF.powerColorValues, UF.powerColorOrder)
                    end,
                    border = function(cf, tabInner)
                        buildBorderTab(tabInner, "powerBar", B.applyBarTextures)
                    end,
                    visibility = function(cf, tabInner)
                        tabInner:AddToggle({
                            label = "Hide Power Bar",
                            get = function() local t = B.getUFDB() or {}; return not not t.powerBarHidden end,
                            set = function(v) local t = B.ensureUFDB(); if t then t.powerBarHidden = v and true or false; B.applyBarTextures() end end,
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
    -- Collapsible Section: Cast Bar (7 tabs for Target - no Cast Time)
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
                                ["default"] = "Default (Blizzard)",
                                ["nameTop"] = "Above Name",
                                ["healthBottom"] = "Below Health Bar",
                                ["powerTop"] = "Above Power Bar",
                                ["powerBottom"] = "Below Power Bar",
                            },
                            order = {"default", "nameTop", "healthBottom", "powerTop", "powerBottom"},
                            get = function() local t = B.getCastBarDB() or {}; return t.anchorMode or "default" end,
                            set = function(v) local t = B.ensureCastBarDB(); if t then t.anchorMode = v; B.applyCastBar() end end,
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
                        -- Kept off Builder:AddBarStyleBlock: texture and color sit on separate rows, not the dual row the block emits.
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
    -- Buffs & Debuffs (Target only - 5 tabs)
    --------------------------------------------------------------------------------

    local buffsTabs = UF.getBuffsDebuffsTabs()

    builder:AddCollapsibleSection({
        title = "Buffs & Debuffs",
        componentId = COMPONENT_ID,
        sectionKey = "buffsDebuffs",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddTabbedSection({
                tabs = buffsTabs,
                componentId = COMPONENT_ID,
                sectionKey = "buffsDebuffs_tabs",
                buildContent = {
                    sizing = function(cf, tabInner)
                        tabInner:AddSlider({
                            label = "Icon Scale",
                            min = 20, max = 200, step = 5,
                            get = function() local t = B.getBuffsDebuffsDB() or {}; return tonumber(t.iconScale) or 100 end,
                            set = function(v) local t = B.ensureBuffsDebuffsDB(); if t then t.iconScale = tonumber(v) or 100; B.applyBuffsDebuffs() end end,
                            minLabel = "20%", maxLabel = "200%",
                        })
                        tabInner:AddSlider({
                            label = "Icon Shape",
                            description = "Adjust icon aspect ratio. Center = square icons.",
                            min = -67, max = 67, step = 1,
                            get = function() local t = B.getBuffsDebuffsDB() or {}; return tonumber(t.tallWideRatio) or 0 end,
                            set = function(v) local t = B.ensureBuffsDebuffsDB(); if t then t.tallWideRatio = tonumber(v) or 0; B.applyBuffsDebuffs() end end,
                            minLabel = "Wide", maxLabel = "Tall",
                        })
                        tabInner:Finalize()
                    end,
                    border = function(cf, tabInner)
                        local get, set = B.auraBorderAccessors()
                        tabInner:AddIconBorderBlock({
                            get = get, set = set, apply = B.applyBuffsDebuffs,
                            enableToggle = { label = "Enable Custom Borders" },
                            inset = false,
                        })
                        tabInner:Finalize()
                    end,
                    visibility = function(cf, tabInner)
                        tabInner:AddToggle({
                            label = "Hide Buffs & Debuffs",
                            get = function() local t = B.getBuffsDebuffsDB() or {}; return not not t.hideBuffsDebuffs end,
                            set = function(v) local t = B.ensureBuffsDebuffsDB(); if t then t.hideBuffsDebuffs = v and true or false; B.applyBuffsDebuffs() end end,
                        })
                        tabInner:Finalize()
                    end,
                    filters = function(cf, tabInner)
                        tabInner:AddToggle({
                            label = "Show Only Player Buffs",
                            get = function() local t = B.getBuffsDebuffsDB() or {}; return not not t.onlyPlayerBuffs end,
                            set = function(v) local t = B.ensureBuffsDebuffsDB(); if t then t.onlyPlayerBuffs = v and true or false; B.applyBuffsDebuffs() end end,
                        })
                        tabInner:Finalize()
                    end,
                },
            })
            inner:Finalize()
        end,
    })

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
                            label = "Name Container Width", min = 80, max = 150, step = 5,
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
    -- Collapsible Section: Portrait (Target has 5 tabs - no Personal Text)
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
                        tabInner:AddSlider({
                            label = "Portrait Size (Scale)", min = 50, max = 200, step = 1,
                            get = function() local t = B.getPortraitDB() or {}; return tonumber(t.scale) or 100 end,
                            set = function(v) local t = B.ensurePortraitDB(); if t then t.scale = tonumber(v) or 100; B.applyPortrait() end end,
                        })
                        tabInner:Finalize()
                    end,
                    mask = function(cf, tabInner)
                        tabInner:AddSlider({
                            label = "Portrait Zoom", min = 100, max = 200, step = 1,
                            get = function() local t = B.getPortraitDB() or {}; return tonumber(t.zoom) or 100 end,
                            set = function(v) local t = B.ensurePortraitDB(); if t then t.zoom = tonumber(v) or 100; B.applyPortrait() end end,
                        })
                        tabInner:Finalize()
                    end,
                    border = function(cf, tabInner)
                        -- Kept off Builder:AddBarBorderBlock: a portrait border is a single texture with its own style list and color modes.
                        tabInner:AddToggle({
                            label = "Use Custom Border",
                            get = function() local t = B.getPortraitDB() or {}; return t.portraitBorderEnable == true end,
                            set = function(v) local t = B.ensurePortraitDB(); if t then t.portraitBorderEnable = (v == true); B.applyPortrait() end end,
                        })
                        -- Target/Focus have rare_s option
                        local targetBorderValues = { texture_c = "Circle", texture_s = "Circle with Corner", rare_c = "Rare (Circle)", rare_s = "Rare (Square)" }
                        local targetBorderOrder = { "texture_c", "texture_s", "rare_c", "rare_s" }
                        tabInner:AddSelector({
                            label = "Border Style", values = targetBorderValues, order = targetBorderOrder,
                            get = function() local t = B.getPortraitDB() or {}; return t.portraitBorderStyle or "texture_c" end,
                            set = function(v) local t = B.ensurePortraitDB(); if t then t.portraitBorderStyle = v or "texture_c"; B.applyPortrait() end end,
                        })
                        tabInner:AddSlider({
                            label = "Border Inset", min = 1, max = 8, step = 0.5, precision = 1,
                            get = function() local t = B.getPortraitDB() or {}; local v = tonumber(t.portraitBorderThickness) or 1; return math.max(1, math.min(8, math.floor(v * 2 + 0.5) / 2)) end,
                            set = function(v) local t = B.ensurePortraitDB(); if t then t.portraitBorderThickness = math.max(1, math.min(8, math.floor((tonumber(v) or 1) * 2 + 0.5) / 2)); B.applyPortrait() end end,
                        })
                        tabInner:AddSelectorColorPicker({
                            label = "Border Color", values = UF.portraitBorderColorValues, order = UF.portraitBorderColorOrder,
                            get = function() local t = B.getPortraitDB() or {}; return t.portraitBorderColorMode or "texture" end,
                            set = function(v) local t = B.ensurePortraitDB(); if t then t.portraitBorderColorMode = v or "texture"; B.applyPortrait() end end,
                            getColor = function() local t = B.getPortraitDB() or {}; local c = t.portraitBorderTintColor or {1,1,1,1}; return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 end,
                            setColor = function(r,g,b,a) local t = B.ensurePortraitDB(); if t then t.portraitBorderTintColor = {r,g,b,a}; B.applyPortrait() end end,
                            customValue = "custom", hasAlpha = true,
                        })
                        tabInner:Finalize()
                    end,
                    visibility = function(cf, tabInner)
                        tabInner:AddToggle({
                            label = "Hide Portrait",
                            get = function() local t = B.getPortraitDB() or {}; return not not t.hidePortrait end,
                            set = function(v) local t = B.ensurePortraitDB(); if t then t.hidePortrait = v and true or false; B.applyPortrait() end end,
                        })
                        tabInner:Finalize()
                    end,
                },
            })
            inner:Finalize()
        end,
    })

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
