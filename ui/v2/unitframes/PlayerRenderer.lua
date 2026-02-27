-- PlayerRenderer.lua - Player Unit Frame TUI renderer
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.UnitFrames = addon.UI.UnitFrames or {}
local UF = addon.UI.UnitFrames
local SettingsBuilder = addon.UI.SettingsBuilder

local COMPONENT_ID = "ufPlayer"
local UNIT_KEY = "Player"

--------------------------------------------------------------------------------
-- Database Access
--------------------------------------------------------------------------------

local function ensureUFDB()
    return UF.ensureUFDB(UNIT_KEY)
end

local function ensureTextDB(key)
    return UF.ensureTextDB(UNIT_KEY, key)
end

local function ensurePortraitDB()
    return UF.ensurePortraitDB(UNIT_KEY)
end

local function ensureCastBarDB()
    return UF.ensureCastBarDB(UNIT_KEY)
end

local function ensureMiscDB()
    return UF.ensureMiscDB(UNIT_KEY)
end

local function ensureNameLevelDB(textKey)
    local t = UF.ensureUFDB(UNIT_KEY)
    if not t then return nil end
    t[textKey] = t[textKey] or {}
    return t[textKey]
end

--------------------------------------------------------------------------------
-- Apply Functions
--------------------------------------------------------------------------------

local function applyBarTextures()
    UF.applyBarTextures(UNIT_KEY)
end

local function applyHealthText()
    UF.applyHealthText(UNIT_KEY)
end

local function applyPowerText()
    UF.applyPowerText(UNIT_KEY)
end

local function applyPortrait()
    UF.applyPortrait(UNIT_KEY)
end

local function applyCastBar()
    UF.applyCastBar(UNIT_KEY)
end

local function applyScaleMult()
    UF.applyScaleMult(UNIT_KEY)
end

local function applyVisibility()
    UF.applyVisibility(UNIT_KEY)
end

local function applyStyles()
    UF.applyStyles()
end

local function applyNameLevelText()
    if addon and addon.ApplyUnitFrameNameLevelTextFor then
        addon.ApplyUnitFrameNameLevelTextFor(UNIT_KEY)
    end
    UF.applyStyles()
end

-- Shared tab builders are in Builders.lua (UF.Builders.buildBarStyleContent, etc.)
-- Player-only sections are in PlayerSections.lua (UF.PlayerSections.*)

--------------------------------------------------------------------------------
-- Health Bar Visibility Tab (Player only)
--------------------------------------------------------------------------------

local function buildHealthVisibilityTab(inner)
    inner:AddToggle({
        label = "Hide the Bar but not its Text",
        get = function()
            local t = ensureUFDB() or {}
            return not not t.healthBarHideTextureOnly
        end,
        set = function(v)
            local t = ensureUFDB()
            if not t then return end
            t.healthBarHideTextureOnly = v and true or false
            applyBarTextures()
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
            local t = ensureUFDB() or {}
            return not not t.healthBarHideOverAbsorbGlow
        end,
        set = function(v)
            local t = ensureUFDB()
            if not t then return end
            t.healthBarHideOverAbsorbGlow = v and true or false
            applyBarTextures()
        end,
        infoIcon = UF.TOOLTIPS.hideOverAbsorbGlow,
    })

    inner:AddToggle({
        label = "Hide Heal Prediction",
        description = "Hides the green heal prediction bar when healing is incoming.",
        get = function()
            local t = ensureUFDB() or {}
            return not not t.healthBarHideHealPrediction
        end,
        set = function(v)
            local t = ensureUFDB()
            if not t then return end
            t.healthBarHideHealPrediction = v and true or false
            applyBarTextures()
        end,
        infoIcon = {
            tooltipTitle = "Hide Heal Prediction",
            tooltipText = "Hides the green heal prediction bar that appears on your health bar when you or a party member is casting a heal on you.",
        },
    })

    inner:AddToggle({
        label = "Hide Health Loss Animation",
        get = function()
            local t = ensureUFDB() or {}
            return not not t.healthBarHideHealthLossAnimation
        end,
        set = function(v)
            local t = ensureUFDB()
            if not t then return end
            t.healthBarHideHealthLossAnimation = v and true or false
            applyBarTextures()
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
            local t = ensureUFDB() or {}
            return not not t.useCustomBorders
        end,
        set = function(v)
            local t = ensureUFDB()
            if not t then return end
            local wasEnabled = t.useCustomBorders
            t.useCustomBorders = not not v
            if not v then
                t.healthBarHideBorder = false
                if wasEnabled then
                    t.powerBarHeightPct = 100
                end
            end
            applyBarTextures()
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
            local t = ensureUFDB() or {}
            return tonumber(t.scaleMult) or 1.0
        end,
        set = function(v)
            local t = ensureUFDB()
            if not t then return end
            t.scaleMult = tonumber(v) or 1.0
            applyScaleMult()
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
                    sizing = function(cf, tabInner)
                        tabInner:AddSlider({
                            label = "Height %",
                            min = 10,
                            max = 100,
                            step = 5,
                            get = function()
                                local t = ensureUFDB() or {}
                                return tonumber(t.healthBarOverlayHeightPct) or 100
                            end,
                            set = function(v)
                                local t = ensureUFDB()
                                if not t then return end
                                t.healthBarOverlayHeightPct = tonumber(v) or 100
                                applyBarTextures()
                            end,
                            infoIcon = {
                                tooltipTitle = "Health Bar Height",
                                tooltipText = "Reduces the visible height of the health bar. The bar fill still tracks health correctly, but is cropped to this percentage of its normal height (centered vertically).",
                            },
                        })
                        tabInner:Finalize()
                    end,
                    style = function(cf, tabInner)
                        UF.Builders.buildBarStyleContent(tabInner, "healthBar", ensureUFDB, applyBarTextures)
                        tabInner:Finalize()
                    end,
                    border = function(cf, tabInner)
                        UF.Builders.buildBarBorderContent(tabInner, "healthBar", ensureUFDB, applyBarTextures)
                        tabInner:Finalize()
                    end,
                    visibility = function(cf, tabInner)
                        buildHealthVisibilityTab(tabInner)
                    end,
                    percentText = function(cf, tabInner)
                        UF.Builders.buildTextTabContent(tabInner, "textHealthPercent", ensureUFDB, ensureTextDB, applyHealthText, "LEFT")
                        tabInner:Finalize()
                    end,
                    valueText = function(cf, tabInner)
                        UF.Builders.buildTextTabContent(tabInner, "textHealthValue", ensureUFDB, ensureTextDB, applyHealthText, "RIGHT")
                        tabInner:Finalize()
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
                                    local t = ensureUFDB() or {}
                                    return tonumber(t.powerBarOffsetX) or 0
                                end,
                                set = function(v)
                                    local t = ensureUFDB()
                                    if not t then return end
                                    t.powerBarOffsetX = tonumber(v) or 0
                                    applyBarTextures()
                                end,
                            },
                            sliderB = {
                                axisLabel = "Y",
                                min = -100, max = 100, step = 1,
                                get = function()
                                    local t = ensureUFDB() or {}
                                    return tonumber(t.powerBarOffsetY) or 0
                                end,
                                set = function(v)
                                    local t = ensureUFDB()
                                    if not t then return end
                                    t.powerBarOffsetY = tonumber(v) or 0
                                    applyBarTextures()
                                end,
                            },
                        })
                        tabInner:Finalize()
                    end,
                    sizing = function(cf, tabInner)
                        tabInner:AddSlider({
                            label = "Height %",
                            min = 10,
                            max = 200,
                            step = 5,
                            get = function()
                                local t = ensureUFDB() or {}
                                return tonumber(t.powerBarHeightPct) or 100
                            end,
                            set = function(v)
                                local t = ensureUFDB()
                                if not t then return end
                                t.powerBarHeightPct = tonumber(v) or 100
                                applyBarTextures()
                            end,
                        })
                        tabInner:Finalize()
                    end,
                    style = function(cf, tabInner)
                        UF.Builders.buildBarStyleContent(tabInner, "powerBar", ensureUFDB, applyBarTextures, UF.powerColorValues, UF.powerColorOrder)
                        tabInner:Finalize()
                    end,
                    border = function(cf, tabInner)
                        UF.Builders.buildBarBorderContent(tabInner, "powerBar", ensureUFDB, applyBarTextures)
                        tabInner:Finalize()
                    end,
                    visibility = function(cf, tabInner)
                        tabInner:AddToggle({
                            label = "Hide Power Bar",
                            get = function()
                                local t = ensureUFDB() or {}
                                return not not t.powerBarHidden
                            end,
                            set = function(v)
                                local t = ensureUFDB()
                                if not t then return end
                                t.powerBarHidden = v and true or false
                                applyBarTextures()
                            end,
                        })
                        tabInner:AddToggle({
                            label = "Hide the Bar but not its Text",
                            get = function()
                                local t = ensureUFDB() or {}
                                return not not t.powerBarHideTextureOnly
                            end,
                            set = function(v)
                                local t = ensureUFDB()
                                if not t then return end
                                t.powerBarHideTextureOnly = v and true or false
                                applyBarTextures()
                            end,
                            infoIcon = {
                                tooltipTitle = "Hide the Bar but not its Text",
                                tooltipText = "Hides the bar texture and background, showing only the text overlay. Useful for a number-only display of your power resource.",
                            },
                        })
                        tabInner:AddToggle({
                            label = "Hide Full Bar Animations",
                            get = function()
                                local t = ensureUFDB() or {}
                                return not not t.powerBarHideFullSpikes
                            end,
                            set = function(v)
                                local t = ensureUFDB()
                                if not t then return end
                                t.powerBarHideFullSpikes = v and true or false
                                applyBarTextures()
                            end,
                            infoIcon = {
                                tooltipTitle = "Full Bar Animations",
                                tooltipText = "Disables Blizzard's full-bar celebration animations that play when the resource is full. These overlays can't be resized, so hiding them keeps custom bar heights consistent.",
                            },
                        })
                        tabInner:AddToggle({
                            label = "Hide Power Feedback",
                            get = function()
                                local t = ensureUFDB() or {}
                                return not not t.powerBarHideFeedback
                            end,
                            set = function(v)
                                local t = ensureUFDB()
                                if not t then return end
                                t.powerBarHideFeedback = v and true or false
                                applyBarTextures()
                            end,
                            infoIcon = {
                                tooltipTitle = "Power Feedback",
                                tooltipText = "Disables the flash animation that plays when you spend or gain power (energy, mana, rage, etc.). This animation shows a quick highlight on the portion of the bar that changed.",
                            },
                        })
                        tabInner:AddToggle({
                            label = "Hide Power Bar Spark",
                            get = function()
                                local t = ensureUFDB() or {}
                                return not not t.powerBarHideSpark
                            end,
                            set = function(v)
                                local t = ensureUFDB()
                                if not t then return end
                                t.powerBarHideSpark = v and true or false
                                applyBarTextures()
                            end,
                            infoIcon = {
                                tooltipTitle = "Power Bar Spark",
                                tooltipText = "Hides the spark/glow indicator that appears at the current power level on certain classes (e.g., Elemental Shaman).",
                            },
                        })
                        tabInner:AddToggle({
                            label = "Hide Mana Cost Predictions",
                            get = function()
                                local t = ensureUFDB() or {}
                                return not not t.powerBarHideManaCostPrediction
                            end,
                            set = function(v)
                                local t = ensureUFDB()
                                if not t then return end
                                t.powerBarHideManaCostPrediction = v and true or false
                                applyBarTextures()
                            end,
                            infoIcon = {
                                tooltipTitle = "Mana Cost Predictions",
                                tooltipText = "Hides the mana/power cost prediction overlay that appears on the power bar when casting a spell. This blue overlay shows how much power will be consumed by the current cast.",
                            },
                        })
                        tabInner:Finalize()
                    end,
                    percentText = function(cf, tabInner)
                        UF.Builders.buildTextTabContent(tabInner, "textPowerPercent", ensureUFDB, ensureTextDB, applyPowerText, "LEFT", UF.fontColorPowerValues, UF.fontColorPowerOrder)
                        tabInner:Finalize()
                    end,
                    valueText = function(cf, tabInner)
                        UF.Builders.buildTextTabContent(tabInner, "textPowerValue", ensureUFDB, ensureTextDB, applyPowerText, "RIGHT", UF.fontColorPowerValues, UF.fontColorPowerOrder)
                        tabInner:Finalize()
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
        UF.PlayerSections.buildAlternatePowerBar(builder, COMPONENT_ID, ensureUFDB, applyBarTextures)
    end

    --------------------------------------------------------------------------------
    -- Collapsible Section: Class Resource (Player only - dynamic title)
    --------------------------------------------------------------------------------

    UF.PlayerSections.buildClassResource(builder, COMPONENT_ID, ensureUFDB)

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
                                local t = ensureUFDB() or {}
                                return not not t.nameBackdropEnabled
                            end,
                            set = function(v)
                                local t = ensureUFDB()
                                if not t then return end
                                t.nameBackdropEnabled = not not v
                                applyNameLevelText()
                            end,
                        })
                        tabInner:AddBarTextureSelector({
                            label = "Backdrop Texture",
                            get = function()
                                local t = ensureUFDB() or {}
                                return t.nameBackdropTexture or ""
                            end,
                            set = function(v)
                                local t = ensureUFDB()
                                if not t then return end
                                t.nameBackdropTexture = v
                                applyNameLevelText()
                            end,
                        })
                        tabInner:AddSelectorColorPicker({
                            label = "Backdrop Color",
                            values = UF.bgColorValues,
                            order = UF.bgColorOrder,
                            get = function()
                                local t = ensureUFDB() or {}
                                return t.nameBackdropColorMode or "default"
                            end,
                            set = function(v)
                                local t = ensureUFDB()
                                if not t then return end
                                t.nameBackdropColorMode = v or "default"
                                applyNameLevelText()
                            end,
                            getColor = function()
                                local t = ensureUFDB() or {}
                                local c = t.nameBackdropTint or {1, 1, 1, 1}
                                return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
                            end,
                            setColor = function(r, g, b, a)
                                local t = ensureUFDB()
                                if not t then return end
                                t.nameBackdropTint = {r, g, b, a}
                                applyNameLevelText()
                            end,
                            customValue = "custom",
                            hasAlpha = true,
                        })
                        tabInner:AddSlider({
                            label = "Backdrop Width (%)",
                            min = 25, max = 300, step = 1,
                            get = function()
                                local t = ensureUFDB() or {}
                                return tonumber(t.nameBackdropWidthPct) or 100
                            end,
                            set = function(v)
                                local t = ensureUFDB()
                                if not t then return end
                                t.nameBackdropWidthPct = tonumber(v) or 100
                                applyNameLevelText()
                            end,
                        })
                        tabInner:AddSlider({
                            label = "Backdrop Opacity",
                            min = 0, max = 100, step = 1,
                            get = function()
                                local t = ensureUFDB() or {}
                                return tonumber(t.nameBackdropOpacity) or 50
                            end,
                            set = function(v)
                                local t = ensureUFDB()
                                if not t then return end
                                t.nameBackdropOpacity = tonumber(v) or 50
                                applyNameLevelText()
                            end,
                        })
                        tabInner:Finalize()
                    end,
                    border = function(cf, tabInner)
                        tabInner:AddToggle({
                            label = "Enable Border",
                            get = function()
                                local t = ensureUFDB() or {}
                                return not not t.nameBackdropBorderEnabled
                            end,
                            set = function(v)
                                local t = ensureUFDB()
                                if not t then return end
                                t.nameBackdropBorderEnabled = not not v
                                applyNameLevelText()
                            end,
                        })
                        UF.Builders.buildBarBorderContent(tabInner, "nameBackdrop", ensureUFDB, applyNameLevelText)
                        tabInner:Finalize()
                    end,
                    nameText = function(cf, tabInner)
                        tabInner:AddToggle({
                            label = "Disable Name Text",
                            get = function()
                                local t = ensureUFDB() or {}
                                return not not t.nameTextHidden
                            end,
                            set = function(v)
                                local t = ensureUFDB()
                                if not t then return end
                                t.nameTextHidden = v and true or false
                                applyNameLevelText()
                            end,
                        })
                        tabInner:AddFontSelector({
                            label = "Name Text Font",
                            get = function()
                                local s = ensureNameLevelDB("textName") or {}
                                return s.fontFace or "FRIZQT__"
                            end,
                            set = function(v)
                                local t = ensureNameLevelDB("textName")
                                if not t then return end
                                t.fontFace = v
                                applyNameLevelText()
                            end,
                        })
                        tabInner:AddSelector({
                            label = "Name Text Style",
                            values = UF.fontStyleValues,
                            order = UF.fontStyleOrder,
                            get = function()
                                local s = ensureNameLevelDB("textName") or {}
                                return s.style or "OUTLINE"
                            end,
                            set = function(v)
                                local t = ensureNameLevelDB("textName")
                                if not t then return end
                                t.style = v
                                applyNameLevelText()
                            end,
                        })
                        tabInner:AddSlider({
                            label = "Name Text Size",
                            min = 6, max = 48, step = 1,
                            get = function()
                                local s = ensureNameLevelDB("textName") or {}
                                return tonumber(s.size) or 14
                            end,
                            set = function(v)
                                local t = ensureNameLevelDB("textName")
                                if not t then return end
                                t.size = tonumber(v) or 14
                                applyNameLevelText()
                            end,
                        })
                        tabInner:AddSelectorColorPicker({
                            label = "Name Text Color",
                            values = UF.fontColorValues,
                            order = UF.fontColorOrder,
                            get = function()
                                local s = ensureNameLevelDB("textName") or {}
                                return s.colorMode or "default"
                            end,
                            set = function(v)
                                local t = ensureNameLevelDB("textName")
                                if not t then return end
                                t.colorMode = v or "default"
                                applyNameLevelText()
                            end,
                            getColor = function()
                                local s = ensureNameLevelDB("textName") or {}
                                local c = s.color or {1, 0.82, 0, 1}
                                return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
                            end,
                            setColor = function(r, g, b, a)
                                local t = ensureNameLevelDB("textName")
                                if not t then return end
                                t.color = {r, g, b, a}
                                applyNameLevelText()
                            end,
                            customValue = "custom",
                            hasAlpha = true,
                        })
                        tabInner:AddDualSlider({
                            label = "Name Text Offset",
                            sliderA = {
                                axisLabel = "X",
                                min = -100, max = 100, step = 1,
                                get = function() local s = ensureNameLevelDB("textName") or {}; local o = s.offset or {}; return tonumber(o.x) or 0 end,
                                set = function(v) local t = ensureNameLevelDB("textName"); if t then t.offset = t.offset or {}; t.offset.x = tonumber(v) or 0; applyNameLevelText() end end,
                            },
                            sliderB = {
                                axisLabel = "Y",
                                min = -100, max = 100, step = 1,
                                get = function() local s = ensureNameLevelDB("textName") or {}; local o = s.offset or {}; return tonumber(o.y) or 0 end,
                                set = function(v) local t = ensureNameLevelDB("textName"); if t then t.offset = t.offset or {}; t.offset.y = tonumber(v) or 0; applyNameLevelText() end end,
                            },
                        })
                        tabInner:Finalize()
                    end,
                    levelText = function(cf, tabInner)
                        tabInner:AddToggle({
                            label = "Disable Level Text",
                            get = function()
                                local t = ensureUFDB() or {}
                                return not not t.levelTextHidden
                            end,
                            set = function(v)
                                local t = ensureUFDB()
                                if not t then return end
                                t.levelTextHidden = v and true or false
                                applyNameLevelText()
                            end,
                        })
                        tabInner:AddFontSelector({
                            label = "Level Text Font",
                            get = function()
                                local s = ensureNameLevelDB("textLevel") or {}
                                return s.fontFace or "FRIZQT__"
                            end,
                            set = function(v)
                                local t = ensureNameLevelDB("textLevel")
                                if not t then return end
                                t.fontFace = v
                                applyNameLevelText()
                            end,
                        })
                        tabInner:AddSelector({
                            label = "Level Text Style",
                            values = UF.fontStyleValues,
                            order = UF.fontStyleOrder,
                            get = function()
                                local s = ensureNameLevelDB("textLevel") or {}
                                return s.style or "OUTLINE"
                            end,
                            set = function(v)
                                local t = ensureNameLevelDB("textLevel")
                                if not t then return end
                                t.style = v
                                applyNameLevelText()
                            end,
                        })
                        tabInner:AddSlider({
                            label = "Level Text Size",
                            min = 6, max = 48, step = 1,
                            get = function()
                                local s = ensureNameLevelDB("textLevel") or {}
                                return tonumber(s.size) or 14
                            end,
                            set = function(v)
                                local t = ensureNameLevelDB("textLevel")
                                if not t then return end
                                t.size = tonumber(v) or 14
                                applyNameLevelText()
                            end,
                        })
                        tabInner:AddSelectorColorPicker({
                            label = "Level Text Color",
                            values = UF.fontColorValues,
                            order = UF.fontColorOrder,
                            get = function()
                                local s = ensureNameLevelDB("textLevel") or {}
                                return s.colorMode or "default"
                            end,
                            set = function(v)
                                local t = ensureNameLevelDB("textLevel")
                                if not t then return end
                                t.colorMode = v or "default"
                                applyNameLevelText()
                            end,
                            getColor = function()
                                local s = ensureNameLevelDB("textLevel") or {}
                                local c = s.color or {1, 0.82, 0, 1}
                                return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
                            end,
                            setColor = function(r, g, b, a)
                                local t = ensureNameLevelDB("textLevel")
                                if not t then return end
                                t.color = {r, g, b, a}
                                applyNameLevelText()
                            end,
                            customValue = "custom",
                            hasAlpha = true,
                        })
                        tabInner:AddDualSlider({
                            label = "Level Text Offset",
                            sliderA = {
                                axisLabel = "X",
                                min = -100, max = 100, step = 1,
                                get = function() local s = ensureNameLevelDB("textLevel") or {}; local o = s.offset or {}; return tonumber(o.x) or 0 end,
                                set = function(v) local t = ensureNameLevelDB("textLevel"); if t then t.offset = t.offset or {}; t.offset.x = tonumber(v) or 0; applyNameLevelText() end end,
                            },
                            sliderB = {
                                axisLabel = "Y",
                                min = -100, max = 100, step = 1,
                                get = function() local s = ensureNameLevelDB("textLevel") or {}; local o = s.offset or {}; return tonumber(o.y) or 0 end,
                                set = function(v) local t = ensureNameLevelDB("textLevel"); if t then t.offset = t.offset or {}; t.offset.y = tonumber(v) or 0; applyNameLevelText() end end,
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
                                    local t = ensurePortraitDB() or {}
                                    return tonumber(t.offsetX) or 0
                                end,
                                set = function(v)
                                    local t = ensurePortraitDB()
                                    if not t then return end
                                    t.offsetX = tonumber(v) or 0
                                    applyPortrait()
                                end,
                            },
                            sliderB = {
                                axisLabel = "Y",
                                min = -100, max = 100, step = 1,
                                get = function()
                                    local t = ensurePortraitDB() or {}
                                    return tonumber(t.offsetY) or 0
                                end,
                                set = function(v)
                                    local t = ensurePortraitDB()
                                    if not t then return end
                                    t.offsetY = tonumber(v) or 0
                                    applyPortrait()
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
                                local t = ensurePortraitDB() or {}
                                return tonumber(t.scale) or 100
                            end,
                            set = function(v)
                                local t = ensurePortraitDB()
                                if not t then return end
                                t.scale = tonumber(v) or 100
                                applyPortrait()
                            end,
                        })
                        tabInner:Finalize()
                    end,
                    mask = function(cf, tabInner)
                        tabInner:AddSlider({
                            label = "Portrait Zoom",
                            min = 100, max = 200, step = 1,
                            get = function()
                                local t = ensurePortraitDB() or {}
                                return tonumber(t.zoom) or 100
                            end,
                            set = function(v)
                                local t = ensurePortraitDB()
                                if not t then return end
                                t.zoom = tonumber(v) or 100
                                applyPortrait()
                            end,
                        })
                        tabInner:AddToggle({
                            label = "Use Full Circle Mask",
                            get = function()
                                local t = ensurePortraitDB() or {}
                                return t.useFullCircleMask == true
                            end,
                            set = function(v)
                                local t = ensurePortraitDB()
                                if not t then return end
                                t.useFullCircleMask = (v == true)
                                applyPortrait()
                            end,
                        })
                        tabInner:Finalize()
                    end,
                    border = function(cf, tabInner)
                        tabInner:AddToggle({
                            label = "Use Custom Border",
                            get = function()
                                local t = ensurePortraitDB() or {}
                                return t.portraitBorderEnable == true
                            end,
                            set = function(v)
                                local t = ensurePortraitDB()
                                if not t then return end
                                t.portraitBorderEnable = (v == true)
                                applyPortrait()
                            end,
                        })
                        tabInner:AddSelector({
                            label = "Border Style",
                            values = UF.portraitBorderValues,
                            order = UF.portraitBorderOrder,
                            get = function()
                                local t = ensurePortraitDB() or {}
                                return t.portraitBorderStyle or "texture_c"
                            end,
                            set = function(v)
                                local t = ensurePortraitDB()
                                if not t then return end
                                t.portraitBorderStyle = v or "texture_c"
                                applyPortrait()
                            end,
                        })
                        tabInner:AddSlider({
                            label = "Border Inset",
                            min = 1, max = 8, step = 0.5, precision = 1,
                            get = function()
                                local t = ensurePortraitDB() or {}
                                local v = tonumber(t.portraitBorderThickness) or 1
                                return math.max(1, math.min(8, math.floor(v * 2 + 0.5) / 2))
                            end,
                            set = function(v)
                                local t = ensurePortraitDB()
                                if not t then return end
                                t.portraitBorderThickness = math.max(1, math.min(8, math.floor((tonumber(v) or 1) * 2 + 0.5) / 2))
                                applyPortrait()
                            end,
                        })
                        tabInner:AddSelectorColorPicker({
                            label = "Border Color",
                            values = UF.portraitBorderColorValues,
                            order = UF.portraitBorderColorOrder,
                            get = function()
                                local t = ensurePortraitDB() or {}
                                return t.portraitBorderColorMode or "texture"
                            end,
                            set = function(v)
                                local t = ensurePortraitDB()
                                if not t then return end
                                t.portraitBorderColorMode = v or "texture"
                                applyPortrait()
                            end,
                            getColor = function()
                                local t = ensurePortraitDB() or {}
                                local c = t.portraitBorderTintColor or {1, 1, 1, 1}
                                return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
                            end,
                            setColor = function(r, g, b, a)
                                local t = ensurePortraitDB()
                                if not t then return end
                                t.portraitBorderTintColor = {r, g, b, a}
                                applyPortrait()
                            end,
                            customValue = "custom",
                            hasAlpha = true,
                        })
                        tabInner:Finalize()
                    end,
                    personalText = function(cf, tabInner)
                        tabInner:AddToggle({
                            label = "Hide Personal Text",
                            get = function()
                                local t = ensurePortraitDB() or {}
                                return not not t.personalTextHidden
                            end,
                            set = function(v)
                                local t = ensurePortraitDB()
                                if not t then return end
                                t.personalTextHidden = v and true or false
                                applyPortrait()
                            end,
                        })
                        tabInner:AddFontSelector({
                            label = "Personal Text Font",
                            get = function()
                                local t = ensurePortraitDB() or {}
                                local s = t.personalText or {}
                                return s.fontFace or "FRIZQT__"
                            end,
                            set = function(v)
                                local t = ensurePortraitDB()
                                if not t then return end
                                t.personalText = t.personalText or {}
                                t.personalText.fontFace = v
                                applyPortrait()
                            end,
                        })
                        tabInner:AddSelector({
                            label = "Personal Text Style",
                            values = UF.fontStyleValues,
                            order = UF.fontStyleOrder,
                            get = function()
                                local t = ensurePortraitDB() or {}
                                local s = t.personalText or {}
                                return s.style or "OUTLINE"
                            end,
                            set = function(v)
                                local t = ensurePortraitDB()
                                if not t then return end
                                t.personalText = t.personalText or {}
                                t.personalText.style = v
                                applyPortrait()
                            end,
                        })
                        tabInner:AddSlider({
                            label = "Personal Text Size",
                            min = 6, max = 48, step = 1,
                            get = function()
                                local t = ensurePortraitDB() or {}
                                local s = t.personalText or {}
                                return tonumber(s.size) or 14
                            end,
                            set = function(v)
                                local t = ensurePortraitDB()
                                if not t then return end
                                t.personalText = t.personalText or {}
                                t.personalText.size = tonumber(v) or 14
                                applyPortrait()
                            end,
                        })
                        tabInner:AddColorPicker({
                            label = "Personal Text Color",
                            get = function()
                                local t = ensurePortraitDB() or {}
                                local s = t.personalText or {}
                                local c = s.color or {1, 1, 1, 1}
                                return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
                            end,
                            set = function(r, g, b, a)
                                local t = ensurePortraitDB()
                                if not t then return end
                                t.personalText = t.personalText or {}
                                t.personalText.color = {r, g, b, a}
                                applyPortrait()
                            end,
                            hasAlpha = true,
                        })
                        tabInner:Finalize()
                    end,
                    visibility = function(cf, tabInner)
                        tabInner:AddToggle({
                            label = "Hide Portrait",
                            get = function()
                                local t = ensurePortraitDB() or {}
                                return not not t.hidePortrait
                            end,
                            set = function(v)
                                local t = ensurePortraitDB()
                                if not t then return end
                                t.hidePortrait = v and true or false
                                applyPortrait()
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
    -- Collapsible Section: Cast Bar (8 tabs for Player)
    --------------------------------------------------------------------------------

    local castBarTabs = UF.getCastBarTabs(COMPONENT_ID)

    builder:AddCollapsibleSection({
        title = "Cast Bar",
        componentId = COMPONENT_ID,
        sectionKey = "castBar",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddTabbedSection({
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
                                    local t = ensureCastBarDB() or {}
                                    return tonumber(t.offsetX) or 0
                                end,
                                set = function(v)
                                    local t = ensureCastBarDB()
                                    if not t then return end
                                    t.offsetX = tonumber(v) or 0
                                    applyCastBar()
                                end,
                            },
                            sliderB = {
                                axisLabel = "Y",
                                min = -200, max = 200, step = 1,
                                get = function()
                                    local t = ensureCastBarDB() or {}
                                    return tonumber(t.offsetY) or 0
                                end,
                                set = function(v)
                                    local t = ensureCastBarDB()
                                    if not t then return end
                                    t.offsetY = tonumber(v) or 0
                                    applyCastBar()
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
                                local t = ensureCastBarDB() or {}
                                return tonumber(t.widthPct) or 100
                            end,
                            set = function(v)
                                local t = ensureCastBarDB()
                                if not t then return end
                                t.widthPct = tonumber(v) or 100
                                applyCastBar()
                            end,
                        })
                        tabInner:AddSlider({
                            label = "Height",
                            min = 5, max = 50, step = 1,
                            get = function()
                                local t = ensureCastBarDB() or {}
                                return tonumber(t.castBarHeight) or 13
                            end,
                            set = function(v)
                                local t = ensureCastBarDB()
                                if not t then return end
                                t.castBarHeight = tonumber(v) or 13
                                applyCastBar()
                            end,
                        })
                        tabInner:Finalize()
                    end,
                    style = function(cf, tabInner)
                        UF.Builders.buildBarStyleContent(tabInner, "castBar", ensureCastBarDB, applyCastBar)
                        tabInner:AddSpacer(8)
                        tabInner:AddToggle({
                            label = "Hide Spark",
                            get = function()
                                local t = ensureCastBarDB() or {}
                                return not not t.castBarSparkHidden
                            end,
                            set = function(v)
                                local t = ensureCastBarDB()
                                if not t then return end
                                t.castBarSparkHidden = v and true or false
                                applyCastBar()
                            end,
                        })
                        tabInner:AddSelectorColorPicker({
                            label = "Spark Color",
                            values = { ["default"] = "Default", ["custom"] = "Custom" },
                            order = { "default", "custom" },
                            get = function()
                                local t = ensureCastBarDB() or {}
                                return t.castBarSparkColorMode or "default"
                            end,
                            set = function(v)
                                local t = ensureCastBarDB()
                                if not t then return end
                                t.castBarSparkColorMode = v or "default"
                                applyCastBar()
                            end,
                            getColor = function()
                                local t = ensureCastBarDB() or {}
                                local c = t.castBarSparkTint or {1, 1, 1, 1}
                                return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
                            end,
                            setColor = function(r, g, b, a)
                                local t = ensureCastBarDB()
                                if not t then return end
                                t.castBarSparkTint = {r, g, b, a}
                                applyCastBar()
                            end,
                            customValue = "custom",
                            hasAlpha = true,
                        })
                        tabInner:Finalize()
                    end,
                    border = function(cf, tabInner)
                        tabInner:AddToggle({
                            label = "Enable Border",
                            get = function()
                                local t = ensureCastBarDB() or {}
                                return not not t.castBarBorderEnable
                            end,
                            set = function(v)
                                local t = ensureCastBarDB()
                                if not t then return end
                                t.castBarBorderEnable = not not v
                                applyCastBar()
                            end,
                        })
                        UF.Builders.buildBarBorderContent(tabInner, "castBar", ensureCastBarDB, applyCastBar)
                        tabInner:Finalize()
                    end,
                    icon = function(cf, tabInner)
                        tabInner:AddToggle({
                            label = "Hide Icon",
                            get = function()
                                local t = ensureCastBarDB() or {}
                                return not not t.iconDisabled
                            end,
                            set = function(v)
                                local t = ensureCastBarDB()
                                if not t then return end
                                t.iconDisabled = v and true or false
                                applyCastBar()
                            end,
                        })
                        tabInner:AddSlider({
                            label = "Icon Size",
                            min = 10, max = 64, step = 1,
                            get = function()
                                local t = ensureCastBarDB() or {}
                                return tonumber(t.iconWidth) or tonumber(t.iconHeight) or 24
                            end,
                            set = function(v)
                                local t = ensureCastBarDB()
                                if not t then return end
                                t.iconWidth = tonumber(v) or 24
                                t.iconHeight = tonumber(v) or 24
                                applyCastBar()
                            end,
                        })
                        tabInner:AddDualSlider({
                            label = "Icon Offset",
                            sliderA = {
                                axisLabel = "X",
                                min = -100, max = 100, step = 1,
                                get = function()
                                    local t = ensureCastBarDB() or {}
                                    return tonumber(t.castBarIconOffsetX) or 0
                                end,
                                set = function(v)
                                    local t = ensureCastBarDB()
                                    if not t then return end
                                    t.castBarIconOffsetX = tonumber(v) or 0
                                    applyCastBar()
                                end,
                            },
                            sliderB = {
                                axisLabel = "Y",
                                min = -100, max = 100, step = 1,
                                get = function()
                                    local t = ensureCastBarDB() or {}
                                    return tonumber(t.castBarIconOffsetY) or 0
                                end,
                                set = function(v)
                                    local t = ensureCastBarDB()
                                    if not t then return end
                                    t.castBarIconOffsetY = tonumber(v) or 0
                                    applyCastBar()
                                end,
                            },
                        })
                        tabInner:Finalize()
                    end,
                    spellName = function(cf, tabInner)
                        tabInner:AddToggle({
                            label = "Hide Spell Name",
                            get = function()
                                local t = ensureCastBarDB() or {}
                                return not not t.castBarSpellNameHidden
                            end,
                            set = function(v)
                                local t = ensureCastBarDB()
                                if not t then return end
                                t.castBarSpellNameHidden = v and true or false
                                applyCastBar()
                            end,
                        })
                        tabInner:AddFontSelector({
                            label = "Spell Name Font",
                            get = function()
                                local t = ensureCastBarDB() or {}
                                local s = t.spellNameText or {}
                                return s.fontFace or "FRIZQT__"
                            end,
                            set = function(v)
                                local t = ensureCastBarDB()
                                if not t then return end
                                t.spellNameText = t.spellNameText or {}
                                t.spellNameText.fontFace = v
                                applyCastBar()
                            end,
                        })
                        tabInner:AddSelector({
                            label = "Spell Name Style",
                            values = UF.fontStyleValues,
                            order = UF.fontStyleOrder,
                            get = function()
                                local t = ensureCastBarDB() or {}
                                local s = t.spellNameText or {}
                                return s.style or "OUTLINE"
                            end,
                            set = function(v)
                                local t = ensureCastBarDB()
                                if not t then return end
                                t.spellNameText = t.spellNameText or {}
                                t.spellNameText.style = v
                                applyCastBar()
                            end,
                        })
                        tabInner:AddSlider({
                            label = "Spell Name Size",
                            min = 6, max = 32, step = 1,
                            get = function()
                                local t = ensureCastBarDB() or {}
                                local s = t.spellNameText or {}
                                return tonumber(s.size) or 12
                            end,
                            set = function(v)
                                local t = ensureCastBarDB()
                                if not t then return end
                                t.spellNameText = t.spellNameText or {}
                                t.spellNameText.size = tonumber(v) or 12
                                applyCastBar()
                            end,
                        })
                        tabInner:AddColorPicker({
                            label = "Spell Name Color",
                            get = function()
                                local t = ensureCastBarDB() or {}
                                local s = t.spellNameText or {}
                                local c = s.color or {1, 1, 1, 1}
                                return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
                            end,
                            set = function(r, g, b, a)
                                local t = ensureCastBarDB()
                                if not t then return end
                                t.spellNameText = t.spellNameText or {}
                                t.spellNameText.color = {r, g, b, a}
                                applyCastBar()
                            end,
                            hasAlpha = true,
                        })
                        tabInner:Finalize()
                    end,
                    castTime = function(cf, tabInner)
                        tabInner:AddToggle({
                            label = "Hide Cast Time",
                            get = function()
                                local t = ensureCastBarDB() or {}
                                return not not t.castBarTimeHidden
                            end,
                            set = function(v)
                                local t = ensureCastBarDB()
                                if not t then return end
                                t.castBarTimeHidden = v and true or false
                                applyCastBar()
                            end,
                        })
                        tabInner:AddFontSelector({
                            label = "Cast Time Font",
                            get = function()
                                local t = ensureCastBarDB() or {}
                                local s = t.castTimeText or {}
                                return s.fontFace or "FRIZQT__"
                            end,
                            set = function(v)
                                local t = ensureCastBarDB()
                                if not t then return end
                                t.castTimeText = t.castTimeText or {}
                                t.castTimeText.fontFace = v
                                applyCastBar()
                            end,
                        })
                        tabInner:AddSelector({
                            label = "Cast Time Style",
                            values = UF.fontStyleValues,
                            order = UF.fontStyleOrder,
                            get = function()
                                local t = ensureCastBarDB() or {}
                                local s = t.castTimeText or {}
                                return s.style or "OUTLINE"
                            end,
                            set = function(v)
                                local t = ensureCastBarDB()
                                if not t then return end
                                t.castTimeText = t.castTimeText or {}
                                t.castTimeText.style = v
                                applyCastBar()
                            end,
                        })
                        tabInner:AddSlider({
                            label = "Cast Time Size",
                            min = 6, max = 32, step = 1,
                            get = function()
                                local t = ensureCastBarDB() or {}
                                local s = t.castTimeText or {}
                                return tonumber(s.size) or 12
                            end,
                            set = function(v)
                                local t = ensureCastBarDB()
                                if not t then return end
                                t.castTimeText = t.castTimeText or {}
                                t.castTimeText.size = tonumber(v) or 12
                                applyCastBar()
                            end,
                        })
                        tabInner:AddColorPicker({
                            label = "Cast Time Color",
                            get = function()
                                local t = ensureCastBarDB() or {}
                                local s = t.castTimeText or {}
                                local c = s.color or {1, 1, 1, 1}
                                return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
                            end,
                            set = function(r, g, b, a)
                                local t = ensureCastBarDB()
                                if not t then return end
                                t.castTimeText = t.castTimeText or {}
                                t.castTimeText.color = {r, g, b, a}
                                applyCastBar()
                            end,
                            hasAlpha = true,
                        })
                        tabInner:Finalize()
                    end,
                    visibility = function(cf, tabInner)
                        tabInner:AddToggle({
                            label = "Hide Cast Bar",
                            get = function()
                                local t = ensureCastBarDB() or {}
                                return not not t.castBarHidden
                            end,
                            set = function(v)
                                local t = ensureCastBarDB()
                                if not t then return end
                                t.castBarHidden = v and true or false
                                applyCastBar()
                            end,
                        })
                        tabInner:AddToggle({
                            label = "Hide Text Border",
                            get = function()
                                local t = ensureCastBarDB() or {}
                                return not not t.hideTextBorder
                            end,
                            set = function(v)
                                local t = ensureCastBarDB()
                                if not t then return end
                                t.hideTextBorder = v and true or false
                                applyCastBar()
                            end,
                            tooltip = {
                                tooltipTitle = "Text Border",
                                tooltipText = "Hides the text border frame that appears when the cast bar is unlocked from the Player frame.",
                            },
                        })
                        tabInner:AddToggle({
                            label = "Hide Channel Shadow",
                            get = function()
                                local t = ensureCastBarDB() or {}
                                return not not t.hideChannelingShadow
                            end,
                            set = function(v)
                                local t = ensureCastBarDB()
                                if not t then return end
                                t.hideChannelingShadow = v and true or false
                                applyCastBar()
                            end,
                            tooltip = {
                                tooltipTitle = "Channel Shadow",
                                tooltipText = "Hides the shadow effect behind the cast bar during channeled spells.",
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
                    local t = ensureUFDB() or {}
                    return tonumber(t.opacityOutOfCombat) or 100
                end,
                set = function(v)
                    local t = ensureUFDB()
                    if not t then return end
                    t.opacityOutOfCombat = tonumber(v) or 100
                    applyVisibility()
                end,
                infoIcon = UF.TOOLTIPS.visibilityPriority,
            })

            inner:AddSlider({
                label = "Opacity - In Combat",
                min = 0,
                max = 100,
                step = 1,
                get = function()
                    local t = ensureUFDB() or {}
                    return tonumber(t.opacityInCombat) or 100
                end,
                set = function(v)
                    local t = ensureUFDB()
                    if not t then return end
                    t.opacityInCombat = tonumber(v) or 100
                    applyVisibility()
                end,
            })

            inner:AddSlider({
                label = "Opacity - With Target",
                min = 0,
                max = 100,
                step = 1,
                get = function()
                    local t = ensureUFDB() or {}
                    return tonumber(t.opacityWithTarget) or 100
                end,
                set = function(v)
                    local t = ensureUFDB()
                    if not t then return end
                    t.opacityWithTarget = tonumber(v) or 100
                    applyVisibility()
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
                    local t = ensureMiscDB() or {}
                    return not not t.hideRoleIcon
                end,
                set = function(v)
                    local t = ensureMiscDB()
                    if not t then return end
                    t.hideRoleIcon = v and true or false
                    applyStyles()
                end,
            })

            inner:AddToggle({
                label = "Hide Group Number",
                get = function()
                    local t = ensureMiscDB() or {}
                    return not not t.hideGroupNumber
                end,
                set = function(v)
                    local t = ensureMiscDB()
                    if not t then return end
                    t.hideGroupNumber = v and true or false
                    applyStyles()
                end,
            })

            inner:AddToggle({
                label = "Hide PvP Icons",
                get = function()
                    local t = ensureMiscDB() or {}
                    return not not t.hidePvPIcons
                end,
                set = function(v)
                    local t = ensureMiscDB()
                    if not t then return end
                    t.hidePvPIcons = v and true or false
                    applyStyles()
                end,
            })

            inner:AddToggle({
                label = "Allow Off-Screen Dragging",
                description = "Allows moving frames closer to screen edges.",
                get = function()
                    local t = ensureMiscDB() or {}
                    return not not t.allowOffscreenDrag
                end,
                set = function(v)
                    local t = ensureMiscDB()
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
