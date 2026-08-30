-- PlayerRenderer.lua - Player Unit Frame TUI renderer
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.UnitFrames = addon.UI.UnitFrames or {}
local UF = addon.UI.UnitFrames
local SettingsBuilder = addon.UI.SettingsBuilder

local COMPONENT_ID = "ufPlayer"
local UNIT_KEY = "Player"

--------------------------------------------------------------------------------
-- Bound Helpers
--------------------------------------------------------------------------------

local B = UF.BindUnit(UNIT_KEY)

-- Shared tab builders are in Builders.lua (UF.Builders.buildBarStyleContent, etc.)
-- Player-only sections are in PlayerSections.lua (UF.PlayerSections.*)

--------------------------------------------------------------------------------
-- Text Tab Builder
--------------------------------------------------------------------------------

-- dkPair: only the power value/percent texts route their color mode through
-- the colorMode/colorModeDK pair (Death Knight spec coloring).
local function buildTextTab(inner, textKey, applyFn, defaultAlignment, colorValues, colorOrder, dkPair)
    local get, set = B.textAccessors(textKey)
    inner:AddTextStyleBlock({
        get = get, set = set, apply = B.applyStyles,
        applyHidden = applyFn,
        hideToggle = true,
        color = { values = colorValues, order = colorOrder, dkPair = dkPair },
        alignment = { kind = "align", default = defaultAlignment },
    })
    inner:Finalize()
end

--------------------------------------------------------------------------------
-- Health Bar Visibility Tab (Player only)
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
            tooltipText = "Hides the bar texture and background, showing only the text overlay. Useful for a number-only display of your health.",
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
            tooltipText = "Hides the green heal prediction bar that appears on your health bar when you or a party member is casting a heal on you.",
        },
    })

    inner:AddToggle({
        label = "Hide Health Loss Animation",
        get = function()
            local t = B.getUFDB() or {}
            return not not t.healthBarHideHealthLossAnimation
        end,
        set = function(v)
            local t = B.ensureUFDB()
            if not t then return end
            t.healthBarHideHealthLossAnimation = v and true or false
            B.applyBarTextures()
        end,
        infoIcon = {
            tooltipTitle = "Health Loss Animation",
            tooltipText = "The dark red bar that appears briefly when you take damage, showing the amount of health lost. Hide this to remove the damage flash effect.",
        },
    })

    inner:Finalize()
end

--------------------------------------------------------------------------------
-- Renderer Function
--------------------------------------------------------------------------------

function UF.RenderPlayer(panel, scrollContent)
    panel:ClearContent()

    local builder = SettingsBuilder:CreateFor(scrollContent)
    panel._currentBuilder = builder

    builder:SetOnRefresh(function()
        UF.RenderPlayer(panel, scrollContent)
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
            local wasEnabled = t.useCustomBorders
            t.useCustomBorders = not not v
            if not v then
                t.healthBarHideBorder = false
                if wasEnabled then
                    t.powerBarHeightPct = 100
                end
            end
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
    -- Collapsible Section: Health Bar (5 tabs for Player)
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
                        UF.Builders.buildBarStyleContent(tabInner, "healthBar", B.ensureUFDB, B.applyBarTextures, nil, nil, nil, B.getUFDB)
                        tabInner:Finalize()
                    end,
                    border = function(cf, tabInner)
                        UF.Builders.buildBarBorderContent(tabInner, "healthBar", B.ensureUFDB, B.applyBarTextures, B.getUFDB)
                        tabInner:Finalize()
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
    -- Collapsible Section: Power Bar (7 tabs)
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
                        tabInner:AddDualSlider({
                            label = "Offset",
                            sliderA = {
                                axisLabel = "X",
                                min = -100, max = 100, step = 1,
                                get = function()
                                    local t = B.getUFDB() or {}
                                    return tonumber(t.powerBarOffsetX) or 0
                                end,
                                set = function(v)
                                    local t = B.ensureUFDB()
                                    if not t then return end
                                    t.powerBarOffsetX = tonumber(v) or 0
                                    B.applyBarTextures()
                                end,
                            },
                            sliderB = {
                                axisLabel = "Y",
                                min = -100, max = 100, step = 1,
                                get = function()
                                    local t = B.getUFDB() or {}
                                    return tonumber(t.powerBarOffsetY) or 0
                                end,
                                set = function(v)
                                    local t = B.ensureUFDB()
                                    if not t then return end
                                    t.powerBarOffsetY = tonumber(v) or 0
                                    B.applyBarTextures()
                                end,
                            },
                        })
                        tabInner:Finalize()
                    end,
                    sizing = function(cf, tabInner)
                        tabInner:AddSlider({
                            label = "Width %",
                            min = 10,
                            max = 200,
                            step = 5,
                            get = function()
                                local t = B.getUFDB() or {}
                                return tonumber(t.powerBarWidthPct) or 100
                            end,
                            set = function(v)
                                local t = B.ensureUFDB()
                                if not t then return end
                                t.powerBarWidthPct = tonumber(v) or 100
                                B.applyBarTextures()
                            end,
                        })
                        tabInner:AddSlider({
                            label = "Height %",
                            min = 10,
                            max = 200,
                            step = 5,
                            get = function()
                                local t = B.getUFDB() or {}
                                return tonumber(t.powerBarHeightPct) or 100
                            end,
                            set = function(v)
                                local t = B.ensureUFDB()
                                if not t then return end
                                t.powerBarHeightPct = tonumber(v) or 100
                                B.applyBarTextures()
                            end,
                        })
                        tabInner:Finalize()
                    end,
                    style = function(cf, tabInner)
                        UF.Builders.buildBarStyleContent(tabInner, "powerBar", B.ensureUFDB, B.applyBarTextures, UF.powerColorValues, UF.powerColorOrder, nil, B.getUFDB)
                        tabInner:Finalize()
                    end,
                    border = function(cf, tabInner)
                        UF.Builders.buildBarBorderContent(tabInner, "powerBar", B.ensureUFDB, B.applyBarTextures, B.getUFDB)
                        tabInner:Finalize()
                    end,
                    visibility = function(cf, tabInner)
                        tabInner:AddToggle({
                            label = "Hide Power Bar",
                            get = function()
                                local t = B.getUFDB() or {}
                                return not not t.powerBarHidden
                            end,
                            set = function(v)
                                local t = B.ensureUFDB()
                                if not t then return end
                                t.powerBarHidden = v and true or false
                                B.applyBarTextures()
                            end,
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
                                tooltipText = "Hides the bar texture and background, showing only the text overlay. Useful for a number-only display of your power resource.",
                            },
                        })
                        tabInner:AddToggle({
                            label = "Hide Full Bar Animations",
                            get = function()
                                local t = B.getUFDB() or {}
                                return not not t.powerBarHideFullSpikes
                            end,
                            set = function(v)
                                local t = B.ensureUFDB()
                                if not t then return end
                                t.powerBarHideFullSpikes = v and true or false
                                B.applyBarTextures()
                            end,
                            infoIcon = {
                                tooltipTitle = "Full Bar Animations",
                                tooltipText = "Disables Blizzard's full-bar celebration animations that play when the resource is full. These overlays can't be resized, so hiding them keeps custom bar heights consistent.",
                            },
                        })
                        tabInner:AddToggle({
                            label = "Hide Power Feedback",
                            get = function()
                                local t = B.getUFDB() or {}
                                return not not t.powerBarHideFeedback
                            end,
                            set = function(v)
                                local t = B.ensureUFDB()
                                if not t then return end
                                t.powerBarHideFeedback = v and true or false
                                B.applyBarTextures()
                            end,
                            infoIcon = {
                                tooltipTitle = "Power Feedback",
                                tooltipText = "Disables the flash animation that plays when you spend or gain power (energy, mana, rage, etc.). This animation shows a quick highlight on the portion of the bar that changed.",
                            },
                        })
                        tabInner:AddToggle({
                            label = "Hide Power Bar Spark",
                            get = function()
                                local t = B.getUFDB() or {}
                                return not not t.powerBarHideSpark
                            end,
                            set = function(v)
                                local t = B.ensureUFDB()
                                if not t then return end
                                t.powerBarHideSpark = v and true or false
                                B.applyBarTextures()
                            end,
                            infoIcon = {
                                tooltipTitle = "Power Bar Spark",
                                tooltipText = "Hides the spark/glow indicator that appears at the current power level on certain classes (e.g., Elemental Shaman).",
                            },
                        })
                        tabInner:AddToggle({
                            label = "Hide Mana Cost Predictions",
                            get = function()
                                local t = B.getUFDB() or {}
                                return not not t.powerBarHideManaCostPrediction
                            end,
                            set = function(v)
                                local t = B.ensureUFDB()
                                if not t then return end
                                t.powerBarHideManaCostPrediction = v and true or false
                                B.applyBarTextures()
                            end,
                            infoIcon = {
                                tooltipTitle = "Mana Cost Predictions",
                                tooltipText = "Hides the mana/power cost prediction overlay that appears on the power bar when casting a spell. This blue overlay shows how much power will be consumed by the current cast.",
                            },
                        })
                        tabInner:Finalize()
                    end,
                    percentText = function(cf, tabInner)
                        buildTextTab(tabInner, "textPowerPercent", B.applyPowerText, "LEFT", UF.fontColorPowerValues, UF.fontColorPowerOrder, true)
                    end,
                    valueText = function(cf, tabInner)
                        buildTextTab(tabInner, "textPowerValue", B.applyPowerText, "RIGHT", UF.fontColorPowerValues, UF.fontColorPowerOrder, true)
                    end,
                },
            })
            inner:Finalize()
        end,
    })

    --------------------------------------------------------------------------------
    -- Collapsible Section: Alternate Power Bar (Player only - conditional)
    --------------------------------------------------------------------------------

    if addon.UnitFrames_PlayerHasAlternatePowerBar and addon.UnitFrames_PlayerHasAlternatePowerBar() then
        UF.PlayerSections.buildAlternatePowerBar(builder, COMPONENT_ID, B.ensureUFDB, B.applyBarTextures, B.getUFDB)
    end

    --------------------------------------------------------------------------------
    -- Collapsible Section: Cast Bar (8 tabs for Player)
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
            local tabbedRef  -- forward declaration for closure
            inner:AddSelector({
                label = "Mode",
                description = "Choose how the cast bar is displayed.",
                values = { default = "Default Cast Bar", textFill = "Text-Fill Cast Bar" },
                order = { "default", "textFill" },
                emphasized = true,
                get = function() local t = B.getCastBarDB() or {}; return t.castBarMode or "default" end,
                set = function(v)
                    local t = B.ensureCastBarDB()
                    if not t then return end
                    local prevMode = t.castBarMode or "default"
                    t.castBarMode = v
                    -- Auto-toggle effect textures for textFill mode (Player only)
                    local hideKeys = { "hideChargeFlash", "hideCastShine", "hideWispGlow", "hideStandardGlow", "hideChannelSparkles", "hideBaseGlow", "hideCastFlash", "hideCompletionFlare" }
                    if v == "textFill" and prevMode ~= "textFill" then
                        -- Entering textFill: backup current state, force all hidden
                        t._preTextFillHides = {}
                        for _, key in ipairs(hideKeys) do
                            t._preTextFillHides[key] = { existed = (t[key] ~= nil), value = t[key] }
                            t[key] = true
                        end
                    elseif v ~= "textFill" and prevMode == "textFill" then
                        -- Leaving textFill: restore prior state or default to ON
                        if t._preTextFillHides then
                            for _, key in ipairs(hideKeys) do
                                local info = t._preTextFillHides[key]
                                if info and info.existed then
                                    t[key] = info.value
                                else
                                    t[key] = true
                                end
                            end
                            t._preTextFillHides = nil
                        end
                    end
                    B.applyCastBar()
                    -- Refresh tab visibility after mode change
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
                        tabInner:AddDualSlider({
                            label = "Offset",
                            sliderA = {
                                axisLabel = "X",
                                min = -200, max = 200, step = 1,
                                get = function()
                                    local t = B.getCastBarDB() or {}
                                    return tonumber(t.offsetX) or 0
                                end,
                                set = function(v)
                                    local t = B.ensureCastBarDB()
                                    if not t then return end
                                    t.offsetX = tonumber(v) or 0
                                    B.applyCastBar()
                                end,
                            },
                            sliderB = {
                                axisLabel = "Y",
                                min = -200, max = 200, step = 1,
                                get = function()
                                    local t = B.getCastBarDB() or {}
                                    return tonumber(t.offsetY) or 0
                                end,
                                set = function(v)
                                    local t = B.ensureCastBarDB()
                                    if not t then return end
                                    t.offsetY = tonumber(v) or 0
                                    B.applyCastBar()
                                end,
                            },
                        })
                        tabInner:Finalize()
                    end,
                    sizing = function(cf, tabInner)
                        tabInner:AddSlider({
                            label = "Width %",
                            min = 50, max = 150, step = 1,
                            get = function()
                                local t = B.getCastBarDB() or {}
                                return tonumber(t.widthPct) or 100
                            end,
                            set = function(v)
                                local t = B.ensureCastBarDB()
                                if not t then return end
                                t.widthPct = tonumber(v) or 100
                                B.applyCastBar()
                            end,
                        })
                        tabInner:AddSlider({
                            label = "Height",
                            min = 5, max = 50, step = 1,
                            get = function()
                                local t = B.getCastBarDB() or {}
                                return tonumber(t.castBarHeight) or 13
                            end,
                            set = function(v)
                                local t = B.ensureCastBarDB()
                                if not t then return end
                                t.castBarHeight = tonumber(v) or 13
                                B.applyCastBar()
                            end,
                        })
                        tabInner:Finalize()
                    end,
                    style = function(cf, tabInner)
                        UF.Builders.buildBarStyleContent(tabInner, "castBar", B.ensureCastBarDB, B.applyCastBar, UF.castBarColorValues, UF.castBarColorOrder, nil, B.getCastBarDB)
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
                            get = function()
                                local t = B.getCastBarDB() or {}
                                return not not t.castBarSparkHidden
                            end,
                            set = function(v)
                                local t = B.ensureCastBarDB()
                                if not t then return end
                                t.castBarSparkHidden = v and true or false
                                B.applyCastBar()
                            end,
                        })
                        tabInner:AddSelectorColorPicker({
                            label = "Spark Color",
                            values = { ["default"] = "Default", ["custom"] = "Custom" },
                            order = { "default", "custom" },
                            get = function()
                                local t = B.getCastBarDB() or {}
                                return t.castBarSparkColorMode or "default"
                            end,
                            set = function(v)
                                local t = B.ensureCastBarDB()
                                if not t then return end
                                t.castBarSparkColorMode = v or "default"
                                B.applyCastBar()
                            end,
                            getColor = function()
                                local t = B.getCastBarDB() or {}
                                local c = t.castBarSparkTint or {1, 1, 1, 1}
                                return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
                            end,
                            setColor = function(r, g, b, a)
                                local t = B.ensureCastBarDB()
                                if not t then return end
                                t.castBarSparkTint = {r, g, b, a}
                                B.applyCastBar()
                            end,
                            customValue = "custom",
                            hasAlpha = true,
                        })
                        tabInner:AddToggle({
                            label = "Hide Spark Glow",
                            get = function()
                                local t = B.getCastBarDB() or {}
                                return not not t.hideStandardGlow
                            end,
                            set = function(v)
                                local t = B.ensureCastBarDB()
                                if not t then return end
                                t.hideStandardGlow = v and true or false
                                B.applyCastBar()
                            end,
                            infoIcon = {
                                tooltipTitle = "Spark Glow",
                                tooltipText = "The bright glow that trails behind the spark (progress indicator) during casting. Covers both standard and crafting cast bar types. Automatically hidden in Text-Fill mode.",
                            },
                        })
                        tabInner:Finalize()
                    end,
                    border = function(cf, tabInner)
                        tabInner:AddToggle({
                            label = "Enable Border",
                            get = function()
                                local t = B.getCastBarDB() or {}
                                return not not t.castBarBorderEnable
                            end,
                            set = function(v)
                                local t = B.ensureCastBarDB()
                                if not t then return end
                                t.castBarBorderEnable = not not v
                                B.applyCastBar()
                            end,
                        })
                        UF.Builders.buildBarBorderContent(tabInner, "castBar", B.ensureCastBarDB, B.applyCastBar, B.getCastBarDB)
                        tabInner:Finalize()
                    end,
                    icon = function(cf, tabInner)
                        tabInner:AddToggle({
                            label = "Hide Icon",
                            get = function()
                                local t = B.getCastBarDB() or {}
                                return not not t.iconDisabled
                            end,
                            set = function(v)
                                local t = B.ensureCastBarDB()
                                if not t then return end
                                t.iconDisabled = v and true or false
                                B.applyCastBar()
                            end,
                        })
                        tabInner:AddToggle({
                            label = "Hide Icon Backdrop (Shield)",
                            get = function()
                                local t = B.getCastBarDB() or {}
                                return not not t.castBarBorderShieldHidden
                            end,
                            set = function(v)
                                local t = B.ensureCastBarDB()
                                if not t then return end
                                t.castBarBorderShieldHidden = v and true or false
                                B.applyCastBar()
                            end,
                        })
                        tabInner:AddSlider({
                            label = "Icon Size",
                            min = 10, max = 64, step = 1,
                            get = function()
                                local t = B.getCastBarDB() or {}
                                return tonumber(t.iconWidth) or tonumber(t.iconHeight) or 24
                            end,
                            set = function(v)
                                local t = B.ensureCastBarDB()
                                if not t then return end
                                t.iconWidth = tonumber(v) or 24
                                t.iconHeight = tonumber(v) or 24
                                B.applyCastBar()
                            end,
                        })
                        tabInner:AddDualSlider({
                            label = "Icon Offset",
                            sliderA = {
                                axisLabel = "X",
                                min = -100, max = 100, step = 1,
                                get = function()
                                    local t = B.getCastBarDB() or {}
                                    return tonumber(t.castBarIconOffsetX) or 0
                                end,
                                set = function(v)
                                    local t = B.ensureCastBarDB()
                                    if not t then return end
                                    t.castBarIconOffsetX = tonumber(v) or 0
                                    B.applyCastBar()
                                end,
                            },
                            sliderB = {
                                axisLabel = "Y",
                                min = -100, max = 100, step = 1,
                                get = function()
                                    local t = B.getCastBarDB() or {}
                                    return tonumber(t.castBarIconOffsetY) or 0
                                end,
                                set = function(v)
                                    local t = B.ensureCastBarDB()
                                    if not t then return end
                                    t.castBarIconOffsetY = tonumber(v) or 0
                                    B.applyCastBar()
                                end,
                            },
                        })
                        tabInner:Finalize()
                    end,
                    spellName = function(cf, tabInner)
                        tabInner:AddToggle({
                            label = "Hide Spell Name",
                            get = function()
                                local t = B.getCastBarDB() or {}
                                return not not t.castBarSpellNameHidden
                            end,
                            set = function(v)
                                local t = B.ensureCastBarDB()
                                if not t then return end
                                t.castBarSpellNameHidden = v and true or false
                                B.applyCastBar()
                            end,
                        })
                        local get, set = B.castBarTextAccessors("spellNameText")
                        tabInner:AddTextStyleBlock({
                            get = get, set = set, apply = B.applyCastBar,
                            defaults = { size = 10 },
                            size = { min = 6, max = 32 },
                            color = {
                                values = UF.fontColorCastBarValues,
                                order = UF.fontColorCastBarOrder,
                                customValue = { "custom", "customGradient" },
                                optionInfoIcons = UF.fontColorCastBarInfoIcons,
                            },
                            offset = false,
                        })
                        tabInner:Finalize()
                    end,
                    castTime = function(cf, tabInner)
                        tabInner:AddToggle({
                            label = "Show Cast Time",
                            get = function()
                                if addon and addon.EditMode and addon.EditMode.GetSetting then
                                    local mgr = _G.EditModeManagerFrame
                                    local EMSys = _G.Enum and _G.Enum.EditModeSystem
                                    local sid = _G.Enum and _G.Enum.EditModeCastBarSetting
                                        and _G.Enum.EditModeCastBarSetting.ShowCastTime
                                    if mgr and EMSys and sid and mgr.GetRegisteredSystemFrame then
                                        local emFrame = mgr:GetRegisteredSystemFrame(EMSys.CastBar, nil)
                                        if emFrame then
                                            local v = addon.EditMode.GetSetting(emFrame, sid)
                                            return (tonumber(v) or 0) ~= 0
                                        end
                                    end
                                end
                                return false
                            end,
                            set = function(v)
                                if addon and addon.EditMode and addon.EditMode.WriteSetting then
                                    local mgr = _G.EditModeManagerFrame
                                    local EMSys = _G.Enum and _G.Enum.EditModeSystem
                                    local sid = _G.Enum and _G.Enum.EditModeCastBarSetting
                                        and _G.Enum.EditModeCastBarSetting.ShowCastTime
                                    if mgr and EMSys and sid and mgr.GetRegisteredSystemFrame then
                                        local emFrame = mgr:GetRegisteredSystemFrame(EMSys.CastBar, nil)
                                        if emFrame then
                                            addon.EditMode.WriteSetting(emFrame, sid, v and 1 or 0)
                                        end
                                    end
                                end
                            end,
                        })
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
                            get = function()
                                local t = B.getCastBarDB() or {}
                                return not not t.castBarHidden
                            end,
                            set = function(v)
                                local t = B.ensureCastBarDB()
                                if not t then return end
                                t.castBarHidden = v and true or false
                                B.applyCastBar()
                            end,
                        })
                        tabInner:AddToggle({
                            label = "Hide Text Border",
                            get = function()
                                local t = B.getCastBarDB() or {}
                                return not not t.hideTextBorder
                            end,
                            set = function(v)
                                local t = B.ensureCastBarDB()
                                if not t then return end
                                t.hideTextBorder = v and true or false
                                B.applyCastBar()
                            end,
                            infoIcon = {
                                tooltipTitle = "Text Border",
                                tooltipText = "Hides the text border frame that appears when the cast bar is unlocked from the Player frame.",
                            },
                        })
                        tabInner:AddToggle({
                            label = "Hide Channel Shadow",
                            get = function()
                                local t = B.getCastBarDB() or {}
                                return not not t.hideChannelingShadow
                            end,
                            set = function(v)
                                local t = B.ensureCastBarDB()
                                if not t then return end
                                t.hideChannelingShadow = v and true or false
                                B.applyCastBar()
                            end,
                            infoIcon = {
                                tooltipTitle = "Channel Shadow",
                                tooltipText = "Hides the shadow effect behind the cast bar during channeled spells.",
                            },
                        })
                        tabInner:AddToggle({
                            label = "Hide Charge Flash",
                            get = function()
                                local t = B.getCastBarDB() or {}
                                return not not t.hideChargeFlash
                            end,
                            set = function(v)
                                local t = B.ensureCastBarDB()
                                if not t then return end
                                t.hideChargeFlash = v and true or false
                                B.applyCastBar()
                            end,
                            infoIcon = {
                                tooltipTitle = "Charge Flash",
                                tooltipText = "A bright flash effect that plays when progressing through stages of an empowered cast (e.g., Evoker abilities). Automatically hidden in Text-Fill mode.",
                            },
                        })
                        tabInner:AddToggle({
                            label = "Hide Cast Shine",
                            get = function()
                                local t = B.getCastBarDB() or {}
                                return not not t.hideCastShine
                            end,
                            set = function(v)
                                local t = B.ensureCastBarDB()
                                if not t then return end
                                t.hideCastShine = v and true or false
                                B.applyCastBar()
                            end,
                            infoIcon = {
                                tooltipTitle = "Cast Shine",
                                tooltipText = "A bright shine that sweeps upward across the cast bar when a crafting or trade skill cast completes. Automatically hidden in Text-Fill mode.",
                            },
                        })
                        tabInner:AddToggle({
                            label = "Hide Wisp Glow",
                            get = function()
                                local t = B.getCastBarDB() or {}
                                return not not t.hideWispGlow
                            end,
                            set = function(v)
                                local t = B.ensureCastBarDB()
                                if not t then return end
                                t.hideWispGlow = v and true or false
                                B.applyCastBar()
                            end,
                            infoIcon = {
                                tooltipTitle = "Wisp Glow",
                                tooltipText = "A wispy glow effect that briefly appears on the cast bar when a channeled spell finishes. Automatically hidden in Text-Fill mode.",
                            },
                        })
                        tabInner:AddToggle({
                            label = "Hide Channel Sparkles",
                            get = function()
                                local t = B.getCastBarDB() or {}
                                return not not t.hideChannelSparkles
                            end,
                            set = function(v)
                                local t = B.ensureCastBarDB()
                                if not t then return end
                                t.hideChannelSparkles = v and true or false
                                B.applyCastBar()
                            end,
                            infoIcon = {
                                tooltipTitle = "Channel Sparkles",
                                tooltipText = "Animated sparkle particles that briefly appear when a channeled spell finishes. Automatically hidden in Text-Fill mode.",
                            },
                        })
                        tabInner:AddToggle({
                            label = "Hide Base Glow",
                            get = function()
                                local t = B.getCastBarDB() or {}
                                return not not t.hideBaseGlow
                            end,
                            set = function(v)
                                local t = B.ensureCastBarDB()
                                if not t then return end
                                t.hideBaseGlow = v and true or false
                                B.applyCastBar()
                            end,
                            infoIcon = {
                                tooltipTitle = "Base Glow",
                                tooltipText = "A wispy glow anchored to the left edge of the cast bar that briefly expands outward when a channeled spell finishes. Automatically hidden in Text-Fill mode.",
                            },
                        })
                        tabInner:AddToggle({
                            label = "Hide Cast Flash",
                            get = function()
                                local t = B.getCastBarDB() or {}
                                return not not t.hideCastFlash
                            end,
                            set = function(v)
                                local t = B.ensureCastBarDB()
                                if not t then return end
                                t.hideCastFlash = v and true or false
                                B.applyCastBar()
                            end,
                            infoIcon = {
                                tooltipTitle = "Cast Flash",
                                tooltipText = "Hides the bright flash that fills the cast bar when a spell completes. Automatically hidden in Text-Fill mode.",
                            },
                        })
                        tabInner:AddToggle({
                            label = "Hide Interrupt Glow",
                            get = function()
                                local t = B.getCastBarDB() or {}
                                return not not t.hideInterruptGlow
                            end,
                            set = function(v)
                                local t = B.ensureCastBarDB()
                                if not t then return end
                                t.hideInterruptGlow = v and true or false
                                B.applyCastBar()
                            end,
                            infoIcon = {
                                tooltipTitle = "Interrupt Glow",
                                tooltipText = "Hides the red glow outline that surrounds the cast bar when a spell is interrupted.",
                            },
                        })
                        tabInner:AddToggle({
                            label = "Hide Completion Flare",
                            get = function()
                                local t = B.getCastBarDB() or {}
                                return not not t.hideCompletionFlare
                            end,
                            set = function(v)
                                local t = B.ensureCastBarDB()
                                if not t then return end
                                t.hideCompletionFlare = v and true or false
                                B.applyCastBar()
                            end,
                            infoIcon = {
                                tooltipTitle = "Completion Flare",
                                tooltipText = "Hides the upward flame and particle effects that rise from the cast bar when a standard spell finishes casting. Automatically hidden in Text-Fill mode.",
                            },
                        })
                        tabInner:Finalize()
                    end,
                },
            })
            inner:Finalize()
        end,
    })

    --------------------------------------------------------------------------------
    -- Collapsible Section: Class Resource (Player only - dynamic title)
    --------------------------------------------------------------------------------

    UF.PlayerSections.buildClassResource(builder, COMPONENT_ID, B.ensureUFDB, B.getUFDB)

    --------------------------------------------------------------------------------
    -- Collapsible Section: Totem Bar (conditional visibility)
    --------------------------------------------------------------------------------

    if addon.UnitFrames_TotemBar_ShouldShow and addon.UnitFrames_TotemBar_ShouldShow() then
        UF.PlayerSections.buildTotemBar(builder, COMPONENT_ID)
    end

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
                            get = function()
                                local t = B.getUFDB() or {}
                                return not not t.nameBackdropEnabled
                            end,
                            set = function(v)
                                local t = B.ensureUFDB()
                                if not t then return end
                                t.nameBackdropEnabled = not not v
                                B.applyNameLevelText()
                            end,
                        })
                        tabInner:AddBarTextureSelector({
                            label = "Backdrop Texture",
                            get = function()
                                local t = B.getUFDB() or {}
                                return t.nameBackdropTexture or ""
                            end,
                            set = function(v)
                                local t = B.ensureUFDB()
                                if not t then return end
                                t.nameBackdropTexture = v
                                B.applyNameLevelText()
                            end,
                        })
                        tabInner:AddSelectorColorPicker({
                            label = "Backdrop Color",
                            values = UF.bgColorValues,
                            order = UF.bgColorOrder,
                            get = function()
                                local t = B.getUFDB() or {}
                                return t.nameBackdropColorMode or "default"
                            end,
                            set = function(v)
                                local t = B.ensureUFDB()
                                if not t then return end
                                t.nameBackdropColorMode = v or "default"
                                B.applyNameLevelText()
                            end,
                            getColor = function()
                                local t = B.getUFDB() or {}
                                local c = t.nameBackdropTint or {1, 1, 1, 1}
                                return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
                            end,
                            setColor = function(r, g, b, a)
                                local t = B.ensureUFDB()
                                if not t then return end
                                t.nameBackdropTint = {r, g, b, a}
                                B.applyNameLevelText()
                            end,
                            customValue = "custom",
                            hasAlpha = true,
                        })
                        tabInner:AddSlider({
                            label = "Backdrop Width (%)",
                            min = 25, max = 300, step = 1,
                            get = function()
                                local t = B.getUFDB() or {}
                                return tonumber(t.nameBackdropWidthPct) or 100
                            end,
                            set = function(v)
                                local t = B.ensureUFDB()
                                if not t then return end
                                t.nameBackdropWidthPct = tonumber(v) or 100
                                B.applyNameLevelText()
                            end,
                        })
                        tabInner:AddSlider({
                            label = "Backdrop Opacity",
                            min = 0, max = 100, step = 1,
                            get = function()
                                local t = B.getUFDB() or {}
                                return tonumber(t.nameBackdropOpacity) or 50
                            end,
                            set = function(v)
                                local t = B.ensureUFDB()
                                if not t then return end
                                t.nameBackdropOpacity = tonumber(v) or 50
                                B.applyNameLevelText()
                            end,
                        })
                        tabInner:Finalize()
                    end,
                    border = function(cf, tabInner)
                        tabInner:AddToggle({
                            label = "Enable Border",
                            get = function()
                                local t = B.getUFDB() or {}
                                return not not t.nameBackdropBorderEnabled
                            end,
                            set = function(v)
                                local t = B.ensureUFDB()
                                if not t then return end
                                t.nameBackdropBorderEnabled = not not v
                                B.applyNameLevelText()
                            end,
                        })
                        UF.Builders.buildBarBorderContent(tabInner, "nameBackdrop", B.ensureUFDB, B.applyNameLevelText, B.getUFDB)
                        tabInner:Finalize()
                    end,
                    nameText = function(cf, tabInner)
                        local get, set = B.textAccessors("textName", { hiddenKey = "nameTextHidden" })
                        tabInner:AddTextStyleBlock({
                            get = get, set = set, apply = B.applyNameLevelText,
                            defaults = { color = {1, 0.82, 0, 1} },
                            hideToggle = { label = "Disable Name Text" },
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
    -- Collapsible Section: Portrait
    --------------------------------------------------------------------------------

    local portraitTabs = UF.getPortraitTabs(COMPONENT_ID)

    builder:AddCollapsibleSection({
        title = "Portrait",
        componentId = COMPONENT_ID,
        sectionKey = "portrait",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddTabbedSection({
                tabs = portraitTabs,
                componentId = COMPONENT_ID,
                sectionKey = "portrait_tabs",
                buildContent = {
                    positioning = function(cf, tabInner)
                        tabInner:AddDualSlider({
                            label = "Offset",
                            sliderA = {
                                axisLabel = "X",
                                min = -100, max = 100, step = 1,
                                get = function()
                                    local t = B.getPortraitDB() or {}
                                    return tonumber(t.offsetX) or 0
                                end,
                                set = function(v)
                                    local t = B.ensurePortraitDB()
                                    if not t then return end
                                    t.offsetX = tonumber(v) or 0
                                    B.applyPortrait()
                                end,
                            },
                            sliderB = {
                                axisLabel = "Y",
                                min = -100, max = 100, step = 1,
                                get = function()
                                    local t = B.getPortraitDB() or {}
                                    return tonumber(t.offsetY) or 0
                                end,
                                set = function(v)
                                    local t = B.ensurePortraitDB()
                                    if not t then return end
                                    t.offsetY = tonumber(v) or 0
                                    B.applyPortrait()
                                end,
                            },
                        })
                        tabInner:Finalize()
                    end,
                    sizing = function(cf, tabInner)
                        tabInner:AddSlider({
                            label = "Portrait Size (Scale)",
                            min = 50, max = 200, step = 1,
                            get = function()
                                local t = B.getPortraitDB() or {}
                                return tonumber(t.scale) or 100
                            end,
                            set = function(v)
                                local t = B.ensurePortraitDB()
                                if not t then return end
                                t.scale = tonumber(v) or 100
                                B.applyPortrait()
                            end,
                        })
                        tabInner:Finalize()
                    end,
                    mask = function(cf, tabInner)
                        tabInner:AddSlider({
                            label = "Portrait Zoom",
                            min = 100, max = 200, step = 1,
                            get = function()
                                local t = B.getPortraitDB() or {}
                                return tonumber(t.zoom) or 100
                            end,
                            set = function(v)
                                local t = B.ensurePortraitDB()
                                if not t then return end
                                t.zoom = tonumber(v) or 100
                                B.applyPortrait()
                            end,
                        })
                        tabInner:AddToggle({
                            label = "Use Full Circle Mask",
                            get = function()
                                local t = B.getPortraitDB() or {}
                                return t.useFullCircleMask == true
                            end,
                            set = function(v)
                                local t = B.ensurePortraitDB()
                                if not t then return end
                                t.useFullCircleMask = (v == true)
                                B.applyPortrait()
                            end,
                        })
                        tabInner:Finalize()
                    end,
                    border = function(cf, tabInner)
                        tabInner:AddToggle({
                            label = "Use Custom Border",
                            get = function()
                                local t = B.getPortraitDB() or {}
                                return t.portraitBorderEnable == true
                            end,
                            set = function(v)
                                local t = B.ensurePortraitDB()
                                if not t then return end
                                t.portraitBorderEnable = (v == true)
                                B.applyPortrait()
                            end,
                        })
                        tabInner:AddSelector({
                            label = "Border Style",
                            values = UF.portraitBorderValues,
                            order = UF.portraitBorderOrder,
                            get = function()
                                local t = B.getPortraitDB() or {}
                                return t.portraitBorderStyle or "texture_c"
                            end,
                            set = function(v)
                                local t = B.ensurePortraitDB()
                                if not t then return end
                                t.portraitBorderStyle = v or "texture_c"
                                B.applyPortrait()
                            end,
                        })
                        tabInner:AddSlider({
                            label = "Border Inset",
                            min = 1, max = 8, step = 0.5, precision = 1,
                            get = function()
                                local t = B.getPortraitDB() or {}
                                local v = tonumber(t.portraitBorderThickness) or 1
                                return math.max(1, math.min(8, math.floor(v * 2 + 0.5) / 2))
                            end,
                            set = function(v)
                                local t = B.ensurePortraitDB()
                                if not t then return end
                                t.portraitBorderThickness = math.max(1, math.min(8, math.floor((tonumber(v) or 1) * 2 + 0.5) / 2))
                                B.applyPortrait()
                            end,
                        })
                        tabInner:AddSelectorColorPicker({
                            label = "Border Color",
                            values = UF.portraitBorderColorValues,
                            order = UF.portraitBorderColorOrder,
                            get = function()
                                local t = B.getPortraitDB() or {}
                                return t.portraitBorderColorMode or "texture"
                            end,
                            set = function(v)
                                local t = B.ensurePortraitDB()
                                if not t then return end
                                t.portraitBorderColorMode = v or "texture"
                                B.applyPortrait()
                            end,
                            getColor = function()
                                local t = B.getPortraitDB() or {}
                                local c = t.portraitBorderTintColor or {1, 1, 1, 1}
                                return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
                            end,
                            setColor = function(r, g, b, a)
                                local t = B.ensurePortraitDB()
                                if not t then return end
                                t.portraitBorderTintColor = {r, g, b, a}
                                B.applyPortrait()
                            end,
                            customValue = "custom",
                            hasAlpha = true,
                        })
                        tabInner:Finalize()
                    end,
                    personalText = function(cf, tabInner)
                        -- Portrait damage text: the hide flag and text table
                        -- live in the portrait sub-table, not the unit table
                        tabInner:AddTextStyleBlock({
                            get = function(field)
                                local t = B.getPortraitDB()
                                if not t then return nil end
                                if field == "hidden" then return t.damageTextDisabled end
                                local s = rawget(t, "damageText")
                                if not s then return nil end
                                return s[field]
                            end,
                            set = function(field, value)
                                local t = B.ensurePortraitDB()
                                if not t then return end
                                if field == "hidden" then
                                    t.damageTextDisabled = value
                                    return
                                end
                                t.damageText = t.damageText or {}
                                t.damageText[field] = value
                            end,
                            apply = B.applyPortrait,
                            hideToggle = { label = "Hide Personal Text" },
                            color = { kind = "plain" },
                            offset = false,
                        })
                        tabInner:Finalize()
                    end,
                    visibility = function(cf, tabInner)
                        tabInner:AddToggle({
                            label = "Hide Portrait",
                            get = function()
                                local t = B.getPortraitDB() or {}
                                return not not t.hidePortrait
                            end,
                            set = function(v)
                                local t = B.ensurePortraitDB()
                                if not t then return end
                                t.hidePortrait = v and true or false
                                B.applyPortrait()
                            end,
                        })
                        tabInner:Finalize()
                    end,
                },
            })
            inner:Finalize()
        end,
    })

    --------------------------------------------------------------------------------
    -- Collapsible Section: Visibility (moved before Misc)
    --------------------------------------------------------------------------------

    builder:AddCollapsibleSection({
        title = "Visibility",
        componentId = COMPONENT_ID,
        sectionKey = "visibility",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddSlider({
                label = "Opacity - Out of Combat",
                min = 0,
                max = 100,
                step = 1,
                get = function()
                    local t = B.getUFDB() or {}
                    return tonumber(t.opacityOutOfCombat) or 100
                end,
                set = function(v)
                    local t = B.ensureUFDB()
                    if not t then return end
                    t.opacityOutOfCombat = tonumber(v) or 100
                    B.applyVisibility()
                end,
                infoIcon = UF.TOOLTIPS.visibilityPriority,
            })

            inner:AddSlider({
                label = "Opacity - In Combat",
                min = 0,
                max = 100,
                step = 1,
                get = function()
                    local t = B.getUFDB() or {}
                    return tonumber(t.opacityInCombat) or 100
                end,
                set = function(v)
                    local t = B.ensureUFDB()
                    if not t then return end
                    t.opacityInCombat = tonumber(v) or 100
                    B.applyVisibility()
                end,
            })

            inner:AddSlider({
                label = "Opacity - With Target",
                min = 0,
                max = 100,
                step = 1,
                get = function()
                    local t = B.getUFDB() or {}
                    return tonumber(t.opacityWithTarget) or 100
                end,
                set = function(v)
                    local t = B.ensureUFDB()
                    if not t then return end
                    t.opacityWithTarget = tonumber(v) or 100
                    B.applyVisibility()
                end,
            })

            inner:Finalize()
        end,
    })

    --------------------------------------------------------------------------------
    -- Collapsible Section: Misc (Player-specific) - ALWAYS LAST
    --------------------------------------------------------------------------------

    builder:AddCollapsibleSection({
        title = "Misc",
        componentId = COMPONENT_ID,
        sectionKey = "misc",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddToggle({
                label = "Hide Role Icon",
                get = function()
                    local t = B.getMiscDB() or {}
                    return not not t.hideRoleIcon
                end,
                set = function(v)
                    local t = B.ensureMiscDB()
                    if not t then return end
                    t.hideRoleIcon = v and true or false
                    B.applyStyles()
                end,
            })

            inner:AddToggle({
                label = "Hide Group Number",
                get = function()
                    local t = B.getMiscDB() or {}
                    return not not t.hideGroupNumber
                end,
                set = function(v)
                    local t = B.ensureMiscDB()
                    if not t then return end
                    t.hideGroupNumber = v and true or false
                    B.applyStyles()
                end,
            })

            inner:AddToggle({
                label = "Hide PvP Icons",
                get = function()
                    local t = B.getMiscDB() or {}
                    return not not t.hidePvPIcons
                end,
                set = function(v)
                    local t = B.ensureMiscDB()
                    if not t then return end
                    t.hidePvPIcons = v and true or false
                    B.applyStyles()
                end,
            })

            inner:AddToggle({
                label = "Allow Off-Screen Dragging",
                description = "Allows moving frames closer to screen edges.",
                get = function()
                    local t = B.getMiscDB() or {}
                    return not not t.allowOffscreenDrag
                end,
                set = function(v)
                    local t = B.ensureMiscDB()
                    if not t then return end
                    t.allowOffscreenDrag = v and true or false
                    if addon.ApplyOffScreenUnlock then
                        addon.ApplyOffScreenUnlock(UNIT_KEY, v)
                    end
                end,
                infoIcon = UF.TOOLTIPS.offScreenDragging,
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
addon.UI.SettingsPanel:RegisterRenderer("ufPlayer", function(panel, scrollContent)
    UF.RenderPlayer(panel, scrollContent)
end)

-- Return renderer for registration
--------------------------------------------------------------------------------

return UF.RenderPlayer
