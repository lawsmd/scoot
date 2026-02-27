-- PlayerSections.lua - Player-only conditional sections for PlayerRenderer
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.UnitFrames = addon.UI.UnitFrames or {}
local UF = addon.UI.UnitFrames

UF.PlayerSections = UF.PlayerSections or {}

--------------------------------------------------------------------------------
-- Alternate Power Bar Section
--------------------------------------------------------------------------------
-- Builds the full collapsible section for Alternate Power Bar.
-- Called from PlayerRenderer when addon.UnitFrames_PlayerHasAlternatePowerBar() is true.

function UF.PlayerSections.buildAlternatePowerBar(builder, COMPONENT_ID, ensureUFDBFn, applyBarTexturesFn)
    local function ensureAltPowerBarDB()
        local t = ensureUFDBFn()
        if not t then return nil end
        if not t.altPowerBar then
            t.altPowerBar = {}
        end
        return t.altPowerBar
    end

    local function ensureAltPowerTextDB(textKey)
        local apb = ensureAltPowerBarDB()
        if not apb then return nil end
        if not apb[textKey] then
            apb[textKey] = {}
        end
        return apb[textKey]
    end

    local altPowerTabs = {
        { key = "positioning", label = "Positioning" },
        { key = "sizing", label = "Sizing" },
        { key = "style", label = "Style" },
        { key = "border", label = "Border" },
        { key = "visibility", label = "Visibility" },
        { key = "percentText", label = "% Text" },
        { key = "valueText", label = "Value Text" },
    }

    builder:AddCollapsibleSection({
        title = "Alternate Power Bar",
        componentId = COMPONENT_ID,
        sectionKey = "altPowerBar",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddTabbedSection({
                tabs = altPowerTabs,
                componentId = COMPONENT_ID,
                sectionKey = "altPowerBar_tabs",
                buildContent = {
                    positioning = function(cf, tabInner)
                        tabInner:AddDualSlider({
                            label = "Offset",
                            sliderA = {
                                axisLabel = "X",
                                min = -150, max = 150, step = 1,
                                get = function()
                                    local apb = ensureAltPowerBarDB() or {}
                                    return tonumber(apb.offsetX) or 0
                                end,
                                set = function(v)
                                    local apb = ensureAltPowerBarDB()
                                    if not apb then return end
                                    apb.offsetX = tonumber(v) or 0
                                    applyBarTexturesFn()
                                end,
                            },
                            sliderB = {
                                axisLabel = "Y",
                                min = -150, max = 150, step = 1,
                                get = function()
                                    local apb = ensureAltPowerBarDB() or {}
                                    return tonumber(apb.offsetY) or 0
                                end,
                                set = function(v)
                                    local apb = ensureAltPowerBarDB()
                                    if not apb then return end
                                    apb.offsetY = tonumber(v) or 0
                                    applyBarTexturesFn()
                                end,
                            },
                        })
                        tabInner:Finalize()
                    end,
                    sizing = function(cf, tabInner)
                        tabInner:AddSlider({
                            label = "Width %",
                            min = 10, max = 150, step = 1,
                            get = function()
                                local apb = ensureAltPowerBarDB() or {}
                                return tonumber(apb.widthPct) or 100
                            end,
                            set = function(v)
                                local apb = ensureAltPowerBarDB()
                                if not apb then return end
                                apb.widthPct = tonumber(v) or 100
                                applyBarTexturesFn()
                            end,
                        })
                        tabInner:Finalize()
                    end,
                    style = function(cf, tabInner)
                        tabInner:AddDualBarStyleRow({
                            label = "Foreground",
                            getTexture = function()
                                local apb = ensureAltPowerBarDB() or {}
                                return apb.texture or "default"
                            end,
                            setTexture = function(v)
                                local apb = ensureAltPowerBarDB()
                                if not apb then return end
                                apb.texture = v or "default"
                                applyBarTexturesFn()
                            end,
                            colorValues = UF.healthColorValues,
                            colorOrder = UF.healthColorOrder,
                            getColorMode = function()
                                local apb = ensureAltPowerBarDB() or {}
                                return apb.colorMode or "default"
                            end,
                            setColorMode = function(v)
                                local apb = ensureAltPowerBarDB()
                                if not apb then return end
                                apb.colorMode = v or "default"
                                applyBarTexturesFn()
                            end,
                            getColor = function()
                                local apb = ensureAltPowerBarDB() or {}
                                local c = apb.tint or {1, 1, 1, 1}
                                return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
                            end,
                            setColor = function(r, g, b, a)
                                local apb = ensureAltPowerBarDB()
                                if not apb then return end
                                apb.tint = {r or 1, g or 1, b or 1, a or 1}
                                applyBarTexturesFn()
                            end,
                            customColorValue = "custom",
                            hasAlpha = true,
                        })

                        tabInner:AddSpacer(8)

                        tabInner:AddDualBarStyleRow({
                            label = "Background",
                            getTexture = function()
                                local apb = ensureAltPowerBarDB() or {}
                                return apb.backgroundTexture or "default"
                            end,
                            setTexture = function(v)
                                local apb = ensureAltPowerBarDB()
                                if not apb then return end
                                apb.backgroundTexture = v or "default"
                                applyBarTexturesFn()
                            end,
                            colorValues = UF.bgColorValues,
                            colorOrder = UF.bgColorOrder,
                            getColorMode = function()
                                local apb = ensureAltPowerBarDB() or {}
                                return apb.backgroundColorMode or "default"
                            end,
                            setColorMode = function(v)
                                local apb = ensureAltPowerBarDB()
                                if not apb then return end
                                apb.backgroundColorMode = v or "default"
                                applyBarTexturesFn()
                            end,
                            getColor = function()
                                local apb = ensureAltPowerBarDB() or {}
                                local c = apb.backgroundTint or {0, 0, 0, 1}
                                return c[1] or 0, c[2] or 0, c[3] or 0, c[4] or 1
                            end,
                            setColor = function(r, g, b, a)
                                local apb = ensureAltPowerBarDB()
                                if not apb then return end
                                apb.backgroundTint = {r or 0, g or 0, b or 0, a or 1}
                                applyBarTexturesFn()
                            end,
                            customColorValue = "custom",
                            hasAlpha = true,
                        })

                        tabInner:AddSlider({
                            label = "Background Opacity",
                            min = 0, max = 100, step = 1,
                            get = function()
                                local apb = ensureAltPowerBarDB() or {}
                                return tonumber(apb.backgroundOpacity) or 50
                            end,
                            set = function(v)
                                local apb = ensureAltPowerBarDB()
                                if not apb then return end
                                apb.backgroundOpacity = tonumber(v) or 50
                                applyBarTexturesFn()
                            end,
                        })

                        tabInner:Finalize()
                    end,
                    border = function(cf, tabInner)
                        tabInner:AddBarBorderSelector({
                            label = "Border Style",
                            includeNone = true,
                            get = function()
                                local apb = ensureAltPowerBarDB() or {}
                                return apb.borderStyle or "square"
                            end,
                            set = function(v)
                                local apb = ensureAltPowerBarDB()
                                if not apb then return end
                                apb.borderStyle = v or "square"
                                applyBarTexturesFn()
                            end,
                        })

                        tabInner:AddToggleColorPicker({
                            label = "Border Tint",
                            get = function()
                                local apb = ensureAltPowerBarDB() or {}
                                return not not apb.borderTintEnable
                            end,
                            set = function(v)
                                local apb = ensureAltPowerBarDB()
                                if not apb then return end
                                apb.borderTintEnable = not not v
                                applyBarTexturesFn()
                            end,
                            getColor = function()
                                local apb = ensureAltPowerBarDB() or {}
                                local c = apb.borderTintColor or {1, 1, 1, 1}
                                return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
                            end,
                            setColor = function(r, g, b, a)
                                local apb = ensureAltPowerBarDB()
                                if not apb then return end
                                apb.borderTintColor = {r or 1, g or 1, b or 1, a or 1}
                                applyBarTexturesFn()
                            end,
                            hasAlpha = true,
                        })

                        tabInner:AddSlider({
                            label = "Border Thickness",
                            min = 1, max = 8, step = 0.5, precision = 1,
                            get = function()
                                local apb = ensureAltPowerBarDB() or {}
                                local v = tonumber(apb.borderThickness) or 1
                                return math.max(1, math.min(8, math.floor(v * 2 + 0.5) / 2))
                            end,
                            set = function(v)
                                local apb = ensureAltPowerBarDB()
                                if not apb then return end
                                apb.borderThickness = math.max(1, math.min(8, math.floor((tonumber(v) or 1) * 2 + 0.5) / 2))
                                applyBarTexturesFn()
                            end,
                        })

                        tabInner:AddDualSlider({
                            label = "Border Inset",
                            sliderA = {
                                axisLabel = "H", min = -4, max = 4, step = 1,
                                get = function()
                                    local apb = ensureAltPowerBarDB() or {}
                                    return tonumber(apb.borderInsetH) or tonumber(apb.borderInset) or 0
                                end,
                                set = function(v)
                                    local apb = ensureAltPowerBarDB()
                                    if not apb then return end
                                    apb.borderInsetH = tonumber(v) or 0
                                    applyBarTexturesFn()
                                end,
                                minLabel = "-4", maxLabel = "+4",
                            },
                            sliderB = {
                                axisLabel = "V", min = -4, max = 4, step = 1,
                                get = function()
                                    local apb = ensureAltPowerBarDB() or {}
                                    return tonumber(apb.borderInsetV) or tonumber(apb.borderInset) or 0
                                end,
                                set = function(v)
                                    local apb = ensureAltPowerBarDB()
                                    if not apb then return end
                                    apb.borderInsetV = tonumber(v) or 0
                                    applyBarTexturesFn()
                                end,
                                minLabel = "-4", maxLabel = "+4",
                            },
                        })

                        tabInner:Finalize()
                    end,
                    visibility = function(cf, tabInner)
                        tabInner:AddToggle({
                            label = "Hide Alternate Power Bar",
                            get = function()
                                local apb = ensureAltPowerBarDB() or {}
                                return apb.hidden == true
                            end,
                            set = function(v)
                                local apb = ensureAltPowerBarDB()
                                if not apb then return end
                                apb.hidden = (v == true)
                                applyBarTexturesFn()
                            end,
                            infoIcon = {
                                tooltipTitle = "Hide Alternate Power Bar",
                                tooltipText = "Completely hides the alternate power bar (e.g., Maelstrom for Elemental Shaman, Insanity for Shadow Priest, Stagger for Brewmaster).",
                            },
                        })

                        tabInner:AddToggle({
                            label = "Hide the Bar but not its Text",
                            get = function()
                                local apb = ensureAltPowerBarDB() or {}
                                return apb.hideTextureOnly == true
                            end,
                            set = function(v)
                                local apb = ensureAltPowerBarDB()
                                if not apb then return end
                                apb.hideTextureOnly = (v == true)
                                applyBarTexturesFn()
                            end,
                            infoIcon = {
                                tooltipTitle = "Hide the Bar but not its Text",
                                tooltipText = "Hides the bar texture and background, showing only the text overlay. Useful for a number-only display of your alternate power resource.",
                            },
                        })

                        tabInner:AddToggle({
                            label = "Hide Full Bar Animations",
                            get = function()
                                local apb = ensureAltPowerBarDB() or {}
                                return apb.hideFullSpikes == true
                            end,
                            set = function(v)
                                local apb = ensureAltPowerBarDB()
                                if not apb then return end
                                apb.hideFullSpikes = (v == true)
                                applyBarTexturesFn()
                            end,
                            infoIcon = {
                                tooltipTitle = "Full Bar Animations",
                                tooltipText = "Disables Blizzard's full-bar celebration animations that play when the resource is full. These overlays can't be resized, so hiding them keeps custom bar heights consistent.",
                            },
                        })

                        tabInner:AddToggle({
                            label = "Hide Power Feedback",
                            get = function()
                                local apb = ensureAltPowerBarDB() or {}
                                return apb.hideFeedback == true
                            end,
                            set = function(v)
                                local apb = ensureAltPowerBarDB()
                                if not apb then return end
                                apb.hideFeedback = (v == true)
                                applyBarTexturesFn()
                            end,
                            infoIcon = {
                                tooltipTitle = "Power Feedback",
                                tooltipText = "Disables the flash animation that plays when you spend or gain alternate power. This animation shows a quick highlight on the portion of the bar that changed.",
                            },
                        })

                        tabInner:AddToggle({
                            label = "Hide APB Spark",
                            get = function()
                                local apb = ensureAltPowerBarDB() or {}
                                return apb.hideSpark == true
                            end,
                            set = function(v)
                                local apb = ensureAltPowerBarDB()
                                if not apb then return end
                                apb.hideSpark = (v == true)
                                applyBarTexturesFn()
                            end,
                            infoIcon = {
                                tooltipTitle = "APB Spark",
                                tooltipText = "Hides the spark/glow indicator that appears at the current power level on the alternate power bar.",
                            },
                        })

                        tabInner:AddToggle({
                            label = "Hide Mana Cost Predictions",
                            get = function()
                                local apb = ensureAltPowerBarDB() or {}
                                return apb.hideManaCostPrediction == true
                            end,
                            set = function(v)
                                local apb = ensureAltPowerBarDB()
                                if not apb then return end
                                apb.hideManaCostPrediction = (v == true)
                                applyBarTexturesFn()
                            end,
                            infoIcon = {
                                tooltipTitle = "Mana Cost Predictions",
                                tooltipText = "Hides the power cost prediction overlay that appears on the alternate power bar when casting a spell.",
                            },
                        })

                        tabInner:AddToggle({
                            label = "Hide Percent Text",
                            get = function()
                                local apb = ensureAltPowerBarDB() or {}
                                return apb.percentHidden == true
                            end,
                            set = function(v)
                                local apb = ensureAltPowerBarDB()
                                if not apb then return end
                                apb.percentHidden = (v == true)
                                applyBarTexturesFn()
                            end,
                            infoIcon = {
                                tooltipTitle = "Hide Percent Text",
                                tooltipText = "Hides the percentage text overlay on the alternate power bar.",
                            },
                        })

                        tabInner:AddToggle({
                            label = "Hide Value Text",
                            get = function()
                                local apb = ensureAltPowerBarDB() or {}
                                return apb.valueHidden == true
                            end,
                            set = function(v)
                                local apb = ensureAltPowerBarDB()
                                if not apb then return end
                                apb.valueHidden = (v == true)
                                applyBarTexturesFn()
                            end,
                            infoIcon = {
                                tooltipTitle = "Hide Value Text",
                                tooltipText = "Hides the numeric value text overlay on the alternate power bar.",
                            },
                        })

                        tabInner:Finalize()
                    end,
                    percentText = function(cf, tabInner)
                        tabInner:AddFontSelector({
                            label = "Font",
                            get = function()
                                local s = ensureAltPowerTextDB("textPercent") or {}
                                return s.fontFace or "FRIZQT__"
                            end,
                            set = function(v)
                                local s = ensureAltPowerTextDB("textPercent")
                                if not s then return end
                                s.fontFace = v
                                applyBarTexturesFn()
                            end,
                        })

                        tabInner:AddSelector({
                            label = "Style",
                            values = UF.fontStyleValues,
                            order = UF.fontStyleOrder,
                            get = function()
                                local s = ensureAltPowerTextDB("textPercent") or {}
                                return s.style or "OUTLINE"
                            end,
                            set = function(v)
                                local s = ensureAltPowerTextDB("textPercent")
                                if not s then return end
                                s.style = v
                                applyBarTexturesFn()
                            end,
                        })

                        tabInner:AddSlider({
                            label = "Size",
                            min = 6, max = 48, step = 1,
                            get = function()
                                local s = ensureAltPowerTextDB("textPercent") or {}
                                return tonumber(s.size) or 14
                            end,
                            set = function(v)
                                local s = ensureAltPowerTextDB("textPercent")
                                if not s then return end
                                s.size = tonumber(v) or 14
                                applyBarTexturesFn()
                            end,
                        })

                        tabInner:AddSelectorColorPicker({
                            label = "Color",
                            values = UF.fontColorPowerValues,
                            order = UF.fontColorPowerOrder,
                            get = function()
                                local s = ensureAltPowerTextDB("textPercent") or {}
                                return s.colorMode or "default"
                            end,
                            set = function(v)
                                local s = ensureAltPowerTextDB("textPercent")
                                if not s then return end
                                s.colorMode = v or "default"
                                applyBarTexturesFn()
                            end,
                            getColor = function()
                                local s = ensureAltPowerTextDB("textPercent") or {}
                                local c = s.color or {1, 1, 1, 1}
                                return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
                            end,
                            setColor = function(r, g, b, a)
                                local s = ensureAltPowerTextDB("textPercent")
                                if not s then return end
                                s.color = {r or 1, g or 1, b or 1, a or 1}
                                applyBarTexturesFn()
                            end,
                            customValue = "custom",
                            hasAlpha = true,
                        })

                        tabInner:AddSelector({
                            label = "Alignment",
                            values = UF.alignmentValues,
                            order = UF.alignmentOrder,
                            get = function()
                                local s = ensureAltPowerTextDB("textPercent") or {}
                                return s.alignment or "LEFT"
                            end,
                            set = function(v)
                                local s = ensureAltPowerTextDB("textPercent")
                                if not s then return end
                                s.alignment = v or "LEFT"
                                applyBarTexturesFn()
                            end,
                        })

                        tabInner:AddDualSlider({
                            label = "Offset",
                            sliderA = {
                                axisLabel = "X",
                                min = -100, max = 100, step = 1,
                                get = function()
                                    local s = ensureAltPowerTextDB("textPercent") or {}
                                    local o = s.offset or {}
                                    return tonumber(o.x) or 0
                                end,
                                set = function(v)
                                    local s = ensureAltPowerTextDB("textPercent")
                                    if not s then return end
                                    s.offset = s.offset or {}
                                    s.offset.x = tonumber(v) or 0
                                    applyBarTexturesFn()
                                end,
                            },
                            sliderB = {
                                axisLabel = "Y",
                                min = -100, max = 100, step = 1,
                                get = function()
                                    local s = ensureAltPowerTextDB("textPercent") or {}
                                    local o = s.offset or {}
                                    return tonumber(o.y) or 0
                                end,
                                set = function(v)
                                    local s = ensureAltPowerTextDB("textPercent")
                                    if not s then return end
                                    s.offset = s.offset or {}
                                    s.offset.y = tonumber(v) or 0
                                    applyBarTexturesFn()
                                end,
                            },
                        })

                        tabInner:Finalize()
                    end,
                    valueText = function(cf, tabInner)
                        tabInner:AddFontSelector({
                            label = "Font",
                            get = function()
                                local s = ensureAltPowerTextDB("textValue") or {}
                                return s.fontFace or "FRIZQT__"
                            end,
                            set = function(v)
                                local s = ensureAltPowerTextDB("textValue")
                                if not s then return end
                                s.fontFace = v
                                applyBarTexturesFn()
                            end,
                        })

                        tabInner:AddSelector({
                            label = "Style",
                            values = UF.fontStyleValues,
                            order = UF.fontStyleOrder,
                            get = function()
                                local s = ensureAltPowerTextDB("textValue") or {}
                                return s.style or "OUTLINE"
                            end,
                            set = function(v)
                                local s = ensureAltPowerTextDB("textValue")
                                if not s then return end
                                s.style = v
                                applyBarTexturesFn()
                            end,
                        })

                        tabInner:AddSlider({
                            label = "Size",
                            min = 6, max = 48, step = 1,
                            get = function()
                                local s = ensureAltPowerTextDB("textValue") or {}
                                return tonumber(s.size) or 14
                            end,
                            set = function(v)
                                local s = ensureAltPowerTextDB("textValue")
                                if not s then return end
                                s.size = tonumber(v) or 14
                                applyBarTexturesFn()
                            end,
                        })

                        tabInner:AddSelectorColorPicker({
                            label = "Color",
                            values = UF.fontColorPowerValues,
                            order = UF.fontColorPowerOrder,
                            get = function()
                                local s = ensureAltPowerTextDB("textValue") or {}
                                return s.colorMode or "default"
                            end,
                            set = function(v)
                                local s = ensureAltPowerTextDB("textValue")
                                if not s then return end
                                s.colorMode = v or "default"
                                applyBarTexturesFn()
                            end,
                            getColor = function()
                                local s = ensureAltPowerTextDB("textValue") or {}
                                local c = s.color or {1, 1, 1, 1}
                                return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
                            end,
                            setColor = function(r, g, b, a)
                                local s = ensureAltPowerTextDB("textValue")
                                if not s then return end
                                s.color = {r or 1, g or 1, b or 1, a or 1}
                                applyBarTexturesFn()
                            end,
                            customValue = "custom",
                            hasAlpha = true,
                        })

                        tabInner:AddSelector({
                            label = "Alignment",
                            values = UF.alignmentValues,
                            order = UF.alignmentOrder,
                            get = function()
                                local s = ensureAltPowerTextDB("textValue") or {}
                                return s.alignment or "RIGHT"
                            end,
                            set = function(v)
                                local s = ensureAltPowerTextDB("textValue")
                                if not s then return end
                                s.alignment = v or "RIGHT"
                                applyBarTexturesFn()
                            end,
                        })

                        tabInner:AddDualSlider({
                            label = "Offset",
                            sliderA = {
                                axisLabel = "X",
                                min = -100, max = 100, step = 1,
                                get = function()
                                    local s = ensureAltPowerTextDB("textValue") or {}
                                    local o = s.offset or {}
                                    return tonumber(o.x) or 0
                                end,
                                set = function(v)
                                    local s = ensureAltPowerTextDB("textValue")
                                    if not s then return end
                                    s.offset = s.offset or {}
                                    s.offset.x = tonumber(v) or 0
                                    applyBarTexturesFn()
                                end,
                            },
                            sliderB = {
                                axisLabel = "Y",
                                min = -100, max = 100, step = 1,
                                get = function()
                                    local s = ensureAltPowerTextDB("textValue") or {}
                                    local o = s.offset or {}
                                    return tonumber(o.y) or 0
                                end,
                                set = function(v)
                                    local s = ensureAltPowerTextDB("textValue")
                                    if not s then return end
                                    s.offset = s.offset or {}
                                    s.offset.y = tonumber(v) or 0
                                    applyBarTexturesFn()
                                end,
                            },
                        })

                        tabInner:Finalize()
                    end,
                },
            })
            inner:Finalize()
        end,
    })
end

--------------------------------------------------------------------------------
-- Class Resource Section
--------------------------------------------------------------------------------
-- Builds the full collapsible section for Class Resource.
-- Always shown for Player (dynamic title based on class).

function UF.PlayerSections.buildClassResource(builder, COMPONENT_ID, ensureUFDBFn)
    local function ensureClassResourceDB()
        local t = ensureUFDBFn()
        if not t then return nil end
        t.classResource = t.classResource or {}
        return t.classResource
    end

    local function applyClassResource()
        if addon and addon.ApplyUnitFrameClassResource then
            addon.ApplyUnitFrameClassResource()
        elseif addon and addon.ApplyStyles then
            addon:ApplyStyles()
        end
    end

    local function getClassResourceTitle()
        if addon and addon.UnitFrames_GetPlayerClassResourceTitle then
            return addon.UnitFrames_GetPlayerClassResourceTitle()
        end
        return "Class Resource"
    end

    builder:AddCollapsibleSection({
        title = getClassResourceTitle(),
        componentId = COMPONENT_ID,
        sectionKey = "classResource",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            local _, playerClass = UnitClass("player")
            local crTabs = {}
            if playerClass == "DEATHKNIGHT" or playerClass == "MAGE" then
                crTabs[#crTabs + 1] = { key = "textures", label = "Textures" }
            end
            crTabs[#crTabs + 1] = { key = "positioning", label = "Positioning" }
            crTabs[#crTabs + 1] = { key = "sizing", label = "Sizing" }
            crTabs[#crTabs + 1] = { key = "visibility", label = "Visibility" }

            local crBuildContent = {}

            crBuildContent.textures = function(cf, tabInner)
                local textureLabel = (playerClass == "DEATHKNIGHT") and "Rune Style"
                    or (playerClass == "MAGE") and "Arcane Charge Style"
                    or "Texture Style"
                local textureKey = "textureStyle_" .. playerClass
                tabInner:AddSelector({
                    label = textureLabel,
                    values = { default = "Blizzard Default", pixel = "Pixel Art" },
                    order = { "default", "pixel" },
                    get = function()
                        local cfg = ensureClassResourceDB() or {}
                        return cfg[textureKey] or "default"
                    end,
                    set = function(v)
                        local cfg = ensureClassResourceDB()
                        if not cfg then return end
                        cfg[textureKey] = v or "default"
                        applyClassResource()
                    end,
                })
                tabInner:Finalize()
            end

            crBuildContent.positioning = function(cf, tabInner)
                tabInner:AddDualSlider({
                    label = "Offset",
                    sliderA = {
                        axisLabel = "X",
                        min = -150, max = 150, step = 1,
                        get = function()
                            local cfg = ensureClassResourceDB() or {}
                            return tonumber(cfg.offsetX) or 0
                        end,
                        set = function(v)
                            local cfg = ensureClassResourceDB()
                            if not cfg then return end
                            cfg.offsetX = tonumber(v) or 0
                            applyClassResource()
                        end,
                    },
                    sliderB = {
                        axisLabel = "Y",
                        min = -150, max = 150, step = 1,
                        get = function()
                            local cfg = ensureClassResourceDB() or {}
                            return tonumber(cfg.offsetY) or 0
                        end,
                        set = function(v)
                            local cfg = ensureClassResourceDB()
                            if not cfg then return end
                            cfg.offsetY = tonumber(v) or 0
                            applyClassResource()
                        end,
                    },
                })
                tabInner:Finalize()
            end

            crBuildContent.sizing = function(cf, tabInner)
                tabInner:AddSlider({
                    label = getClassResourceTitle() .. " Scale",
                    min = 50, max = 150, step = 1,
                    get = function()
                        local cfg = ensureClassResourceDB() or {}
                        return tonumber(cfg.scale) or 100
                    end,
                    set = function(v)
                        local cfg = ensureClassResourceDB()
                        if not cfg then return end
                        cfg.scale = tonumber(v) or 100
                        applyClassResource()
                    end,
                })
                tabInner:Finalize()
            end

            crBuildContent.visibility = function(cf, tabInner)
                tabInner:AddToggle({
                    label = "Hide " .. getClassResourceTitle(),
                    get = function()
                        local cfg = ensureClassResourceDB() or {}
                        return cfg.hide == true
                    end,
                    set = function(v)
                        local cfg = ensureClassResourceDB()
                        if not cfg then return end
                        cfg.hide = (v == true)
                        applyClassResource()
                    end,
                })
                tabInner:Finalize()
            end

            inner:AddTabbedSection({
                tabs = crTabs,
                componentId = COMPONENT_ID,
                sectionKey = "classResource_tabs",
                buildContent = crBuildContent,
            })
            inner:Finalize()
        end,
    })
end

--------------------------------------------------------------------------------
-- Totem Bar Section
--------------------------------------------------------------------------------
-- Builds the full collapsible section for Totem Bar.
-- Called from PlayerRenderer when addon.UnitFrames_TotemBar_ShouldShow() is true.

function UF.PlayerSections.buildTotemBar(builder, COMPONENT_ID)
    local UNIT_KEY = UF.getUnitKey(COMPONENT_ID)

    local function ensureTotemBarDB()
        local t = UF.ensureUFDB(UNIT_KEY)
        if not t then return nil end
        t.totemBar = t.totemBar or {}
        return t.totemBar
    end

    local function ensureTotemBarIconBordersDB()
        local tb = ensureTotemBarDB()
        if not tb then return nil end
        tb.iconBorders = tb.iconBorders or {}
        return tb.iconBorders
    end

    local function ensureTotemBarTimerTextDB()
        local tb = ensureTotemBarDB()
        if not tb then return nil end
        tb.timerText = tb.timerText or {}
        return tb.timerText
    end

    local function applyTotemBar()
        if addon.ApplyTotemBarStyling then
            addon.ApplyTotemBarStyling()
        end
    end

    builder:AddCollapsibleSection({
        title = "Totem Bar",
        componentId = COMPONENT_ID,
        sectionKey = "totemBar",
        defaultExpanded = false,
        infoIcon = {
            tooltipTitle = "Totem Bar",
            tooltipText = "Displays temporary summons: Shaman totems, DK ghouls/Abomination Limb, Druid Grove Guardians/Efflorescence, and Monk statues.",
        },
        buildContent = function(contentFrame, inner)
            inner:AddTabbedSection({
                tabs = {
                    { key = "icons", label = "Icons" },
                    { key = "iconBorders", label = "Icon Borders" },
                    { key = "timerText", label = "Timer Text" },
                },
                componentId = COMPONENT_ID,
                sectionKey = "totemBar_tabs",
                buildContent = {
                    icons = function(cf, tabInner)
                        tabInner:AddDescription("Icon styling options coming soon.")
                        tabInner:Finalize()
                    end,
                    iconBorders = function(cf, tabInner)
                        tabInner:AddToggle({
                            label = "Hide Icon Borders",
                            get = function()
                                local cfg = ensureTotemBarIconBordersDB() or {}
                                return cfg.hidden == true
                            end,
                            set = function(v)
                                local cfg = ensureTotemBarIconBordersDB()
                                if not cfg then return end
                                cfg.hidden = (v == true)
                                applyTotemBar()
                            end,
                        })
                        tabInner:Finalize()
                    end,
                    timerText = function(cf, tabInner)
                        tabInner:AddToggle({
                            label = "Hide Timer Text",
                            get = function()
                                local cfg = ensureTotemBarTimerTextDB() or {}
                                return cfg.hidden == true
                            end,
                            set = function(v)
                                local cfg = ensureTotemBarTimerTextDB()
                                if not cfg then return end
                                cfg.hidden = (v == true)
                                applyTotemBar()
                            end,
                        })
                        tabInner:AddFontSelector({
                            label = "Font Face",
                            get = function()
                                local cfg = ensureTotemBarTimerTextDB() or {}
                                return cfg.fontFace or "FRIZQT__"
                            end,
                            set = function(v)
                                local cfg = ensureTotemBarTimerTextDB()
                                if not cfg then return end
                                cfg.fontFace = v or "FRIZQT__"
                                applyTotemBar()
                            end,
                        })
                        tabInner:AddSlider({
                            label = "Font Size",
                            min = 6, max = 24, step = 1,
                            get = function()
                                local cfg = ensureTotemBarTimerTextDB() or {}
                                return tonumber(cfg.size) or 12
                            end,
                            set = function(v)
                                local cfg = ensureTotemBarTimerTextDB()
                                if not cfg then return end
                                cfg.size = tonumber(v) or 12
                                applyTotemBar()
                            end,
                        })
                        tabInner:AddSelector({
                            label = "Font Style",
                            values = UF.fontStyleValues,
                            order = UF.fontStyleOrder,
                            get = function()
                                local cfg = ensureTotemBarTimerTextDB() or {}
                                return cfg.style or "OUTLINE"
                            end,
                            set = function(v)
                                local cfg = ensureTotemBarTimerTextDB()
                                if not cfg then return end
                                cfg.style = v or "OUTLINE"
                                applyTotemBar()
                            end,
                        })
                        tabInner:AddColorPicker({
                            label = "Font Color",
                            hasAlpha = true,
                            get = function()
                                local cfg = ensureTotemBarTimerTextDB() or {}
                                local c = cfg.color or { 1, 1, 1, 1 }
                                return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
                            end,
                            set = function(r, g, b, a)
                                local cfg = ensureTotemBarTimerTextDB()
                                if not cfg then return end
                                cfg.color = { r or 1, g or 1, b or 1, a or 1 }
                                applyTotemBar()
                            end,
                        })
                        tabInner:AddDualSlider({
                            label = "Offset",
                            sliderA = {
                                axisLabel = "X",
                                min = -50, max = 50, step = 1,
                                get = function()
                                    local cfg = ensureTotemBarTimerTextDB() or {}
                                    local o = cfg.offset or {}
                                    return tonumber(o.x) or 0
                                end,
                                set = function(v)
                                    local cfg = ensureTotemBarTimerTextDB()
                                    if not cfg then return end
                                    cfg.offset = cfg.offset or {}
                                    cfg.offset.x = tonumber(v) or 0
                                    applyTotemBar()
                                end,
                            },
                            sliderB = {
                                axisLabel = "Y",
                                min = -50, max = 50, step = 1,
                                get = function()
                                    local cfg = ensureTotemBarTimerTextDB() or {}
                                    local o = cfg.offset or {}
                                    return tonumber(o.y) or 0
                                end,
                                set = function(v)
                                    local cfg = ensureTotemBarTimerTextDB()
                                    if not cfg then return end
                                    cfg.offset = cfg.offset or {}
                                    cfg.offset.y = tonumber(v) or 0
                                    applyTotemBar()
                                end,
                            },
                        })
                        tabInner:Finalize()
                    end,
                },
            })
            inner:Finalize()
        end,
    })
end

return UF.PlayerSections
