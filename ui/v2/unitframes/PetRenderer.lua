-- PetRenderer.lua - Pet Unit Frame TUI renderer
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.UnitFrames = addon.UI.UnitFrames or {}
local UF = addon.UI.UnitFrames
local SettingsBuilder = addon.UI.SettingsBuilder

local COMPONENT_ID = "ufPet"
local UNIT_KEY = "Pet"

--------------------------------------------------------------------------------
-- Bound Helpers
--------------------------------------------------------------------------------

local B = UF.BindUnit(UNIT_KEY)

--------------------------------------------------------------------------------
-- Health Bar Tab Builders
--------------------------------------------------------------------------------

local function buildHealthStyleTab(inner)
    local get, set = B.barAccessors("healthBar")
    inner:AddBarStyleBlock({ get = get, set = set, apply = B.applyBarTextures })
    inner:Finalize()
end

local function buildHealthBorderTab(inner)
    local get, set = B.barAccessors("healthBar")
    inner:AddBarBorderBlock({ get = get, set = set, apply = B.applyBarTextures })
    inner:Finalize()
end

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

    inner:Finalize()
end

local function buildHealthPercentTextTab(inner)
    local get, set = B.textAccessors("textHealthPercent")
    inner:AddTextStyleBlock({
        get = get, set = set, apply = B.applyStyles,
        applyHidden = B.applyHealthText,
        hideToggle = { label = "Disable % Text" },
        color = { values = UF.fontColorHealthValues, order = UF.fontColorHealthOrder },
        alignment = { kind = "align", default = "LEFT" },
    })
    inner:Finalize()
end

local function buildHealthValueTextTab(inner)
    local get, set = B.textAccessors("textHealthValue")
    inner:AddTextStyleBlock({
        get = get, set = set, apply = B.applyStyles,
        applyHidden = B.applyHealthText,
        hideToggle = { label = "Disable Value Text" },
        color = { values = UF.fontColorHealthValues, order = UF.fontColorHealthOrder },
        alignment = { kind = "align", default = "RIGHT" },
    })
    inner:Finalize()
end

--------------------------------------------------------------------------------
-- Renderer Function
--------------------------------------------------------------------------------

function UF.RenderPet(panel, scrollContent)
    panel:ClearContent()

    local builder = SettingsBuilder:CreateFor(scrollContent)
    panel._currentBuilder = builder

    builder:SetOnRefresh(function()
        UF.RenderPet(panel, scrollContent)
    end)

    --------------------------------------------------------------------------------
    -- Parent-Level Settings (no X/Y Position - handled by Edit Mode)
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
    -- Collapsible Section: Health Bar
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
                    style = function(cf, tabInner) buildHealthStyleTab(tabInner) end,
                    border = function(cf, tabInner) buildHealthBorderTab(tabInner) end,
                    visibility = function(cf, tabInner) buildHealthVisibilityTab(tabInner) end,
                    percentText = function(cf, tabInner) buildHealthPercentTextTab(tabInner) end,
                    valueText = function(cf, tabInner) buildHealthValueTextTab(tabInner) end,
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
                        tabInner:AddOffsetPair({
                            get = function(axis) local t = B.getUFDB(); return t and t[axis == "x" and "powerBarOffsetX" or "powerBarOffsetY"] end,
                            set = function(axis, v) local t = B.ensureUFDB(); if t then t[axis == "x" and "powerBarOffsetX" or "powerBarOffsetY"] = v end end,
                            apply = B.applyBarTextures,
                        })
                        tabInner:Finalize()
                    end,
                    sizing = function(cf, tabInner)
                        tabInner:AddSlider({ label = "Height %", min = 10, max = 200, step = 5,
                            get = function() local t = B.getUFDB() or {}; return tonumber(t.powerBarHeightPct) or 100 end,
                            set = function(v) local t = B.ensureUFDB(); if t then t.powerBarHeightPct = tonumber(v) or 100; B.applyBarTextures() end end })
                        tabInner:Finalize()
                    end,
                    style = function(cf, tabInner)
                        -- Kept off Builder:AddBarStyleBlock: texture and color sit on separate rows, not the dual row the block emits.
                        tabInner:AddBarTextureSelector({ label = "Foreground Texture",
                            get = function() local t = B.getUFDB() or {}; return t.powerBarTexture or "default" end,
                            set = function(v) local t = B.ensureUFDB(); if t then t.powerBarTexture = v or "default"; B.applyBarTextures() end end })
                        tabInner:AddSelectorColorPicker({ label = "Foreground Color", values = UF.powerColorValues, order = UF.powerColorOrder,
                            get = function() local t = B.getUFDB() or {}; return t.powerBarColorMode or "default" end,
                            set = function(v) local t = B.ensureUFDB(); if t then t.powerBarColorMode = v or "default"; B.applyBarTextures() end end,
                            getColor = function() local t = B.getUFDB() or {}; local c = t.powerBarTint or {1,1,1,1}; return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 end,
                            setColor = function(r,g,b,a) local t = B.ensureUFDB(); if t then t.powerBarTint = {r,g,b,a}; B.applyBarTextures() end end,
                            customValue = "custom", hasAlpha = true })
                        tabInner:AddSpacer(8)
                        tabInner:AddBarTextureSelector({ label = "Background Texture",
                            get = function() local t = B.getUFDB() or {}; return t.powerBarBackgroundTexture or "default" end,
                            set = function(v) local t = B.ensureUFDB(); if t then t.powerBarBackgroundTexture = v or "default"; B.applyBarTextures() end end })
                        tabInner:AddSelectorColorPicker({ label = "Background Color", values = UF.bgColorValues, order = UF.bgColorOrder,
                            get = function() local t = B.getUFDB() or {}; return t.powerBarBackgroundColorMode or "default" end,
                            set = function(v) local t = B.ensureUFDB(); if t then t.powerBarBackgroundColorMode = v or "default"; B.applyBarTextures() end end,
                            getColor = function() local t = B.getUFDB() or {}; local c = t.powerBarBackgroundTint or {0,0,0,1}; return c[1] or 0, c[2] or 0, c[3] or 0, c[4] or 1 end,
                            setColor = function(r,g,b,a) local t = B.ensureUFDB(); if t then t.powerBarBackgroundTint = {r,g,b,a}; B.applyBarTextures() end end,
                            customValue = "custom", hasAlpha = true })
                        tabInner:AddSlider({ label = "Background Opacity", min = 0, max = 100, step = 1,
                            get = function() local t = B.getUFDB() or {}; return tonumber(t.powerBarBackgroundOpacity) or 50 end,
                            set = function(v) local t = B.ensureUFDB(); if t then t.powerBarBackgroundOpacity = tonumber(v) or 50; B.applyBarTextures() end end })
                        tabInner:Finalize()
                    end,
                    border = function(cf, tabInner)
                        local get, set = B.barAccessors("powerBar")
                        tabInner:AddBarBorderBlock({ get = get, set = set, apply = B.applyBarTextures })
                        tabInner:Finalize()
                    end,
                    visibility = function(cf, tabInner)
                        tabInner:AddToggle({ label = "Hide Power Bar",
                            get = function() local t = B.getUFDB() or {}; return not not t.powerBarHidden end,
                            set = function(v) local t = B.ensureUFDB(); if t then t.powerBarHidden = v and true or false; B.applyBarTextures() end end })
                        tabInner:Finalize()
                    end,
                    percentText = function(cf, tabInner)
                        local get, set = B.textAccessors("textPowerPercent")
                        tabInner:AddTextStyleBlock({
                            get = get, set = set, apply = B.applyStyles,
                            applyHidden = B.applyPowerText,
                            hideToggle = { label = "Disable % Text" },
                            offset = false,
                        })
                        tabInner:Finalize()
                    end,
                    valueText = function(cf, tabInner)
                        local get, set = B.textAccessors("textPowerValue")
                        tabInner:AddTextStyleBlock({
                            get = get, set = set, apply = B.applyStyles,
                            applyHidden = B.applyPowerText,
                            hideToggle = { label = "Disable Value Text" },
                            offset = false,
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
                        tabInner:AddToggle({ label = "Enable Backdrop",
                            get = function() local t = B.getUFDB() or {}; return not not t.nameBackdropEnabled end,
                            set = function(v) local t = B.ensureUFDB(); if t then t.nameBackdropEnabled = not not v; B.applyNameLevelText() end end })
                        tabInner:AddBarTextureSelector({ label = "Backdrop Texture",
                            get = function() local t = B.getUFDB() or {}; return t.nameBackdropTexture or "" end,
                            set = function(v) local t = B.ensureUFDB(); if t then t.nameBackdropTexture = v; B.applyNameLevelText() end end })
                        tabInner:AddSelectorColorPicker({ label = "Backdrop Color", values = UF.bgColorValues, order = UF.bgColorOrder,
                            get = function() local t = B.getUFDB() or {}; return t.nameBackdropColorMode or "default" end,
                            set = function(v) local t = B.ensureUFDB(); if t then t.nameBackdropColorMode = v or "default"; B.applyNameLevelText() end end,
                            getColor = function() local t = B.getUFDB() or {}; local c = t.nameBackdropTint or {1,1,1,1}; return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 end,
                            setColor = function(r,g,b,a) local t = B.ensureUFDB(); if t then t.nameBackdropTint = {r,g,b,a}; B.applyNameLevelText() end end,
                            customValue = "custom", hasAlpha = true })
                        tabInner:AddSlider({ label = "Backdrop Width (%)", min = 25, max = 300, step = 1,
                            get = function() local t = B.getUFDB() or {}; return tonumber(t.nameBackdropWidthPct) or 100 end,
                            set = function(v) local t = B.ensureUFDB(); if t then t.nameBackdropWidthPct = tonumber(v) or 100; B.applyNameLevelText() end end })
                        tabInner:AddSlider({ label = "Backdrop Opacity", min = 0, max = 100, step = 1,
                            get = function() local t = B.getUFDB() or {}; return tonumber(t.nameBackdropOpacity) or 50 end,
                            set = function(v) local t = B.ensureUFDB(); if t then t.nameBackdropOpacity = tonumber(v) or 50; B.applyNameLevelText() end end })
                        tabInner:Finalize()
                    end,
                    border = function(cf, tabInner)
                        tabInner:AddToggle({ label = "Enable Border",
                            get = function() local t = B.getUFDB() or {}; return not not t.nameBackdropBorderEnabled end,
                            set = function(v) local t = B.ensureUFDB(); if t then t.nameBackdropBorderEnabled = not not v; B.applyNameLevelText() end end })
                        local borderValues, borderOrder = UF.buildBarBorderOptions()
                        tabInner:AddSelector({ label = "Border Style", values = borderValues, order = borderOrder,
                            get = function() local t = B.getUFDB() or {}; return t.nameBackdropBorderStyle or "square" end,
                            set = function(v) local t = B.ensureUFDB(); if t then t.nameBackdropBorderStyle = v or "square"; B.applyNameLevelText() end end })
                        tabInner:AddToggleColorPicker({ label = "Border Tint",
                            get = function() local t = B.getUFDB() or {}; return not not t.nameBackdropBorderTintEnable end,
                            set = function(v) local t = B.ensureUFDB(); if t then t.nameBackdropBorderTintEnable = not not v; B.applyNameLevelText() end end,
                            getColor = function() local t = B.getUFDB() or {}; local c = t.nameBackdropBorderTintColor or {1,1,1,1}; return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 end,
                            setColor = function(r,g,b,a) local t = B.ensureUFDB(); if t then t.nameBackdropBorderTintColor = {r,g,b,a}; B.applyNameLevelText() end end,
                            hasAlpha = true })
                        tabInner:AddSlider({ label = "Border Thickness", min = 1, max = 8, step = 0.5, precision = 1,
                            get = function() local t = B.getUFDB() or {}; local v = tonumber(t.nameBackdropBorderThickness) or 1; return math.max(1, math.min(8, math.floor(v * 2 + 0.5) / 2)) end,
                            set = function(v) local t = B.ensureUFDB(); if t then t.nameBackdropBorderThickness = math.max(1, math.min(8, math.floor((tonumber(v) or 1) * 2 + 0.5) / 2)); B.applyNameLevelText() end end })
                        local insetGet, insetSet = B.barAccessors("nameBackdrop")
                        tabInner:AddInsetPair({
                            apply = B.applyNameLevelText,
                            get = function(axis) return insetGet(axis == "h" and "insetH" or "insetV") end,
                            set = function(axis, v) insetSet(axis == "h" and "insetH" or "insetV", v) end,
                        })
                        tabInner:Finalize()
                    end,
                    nameText = function(cf, tabInner)
                        local get, set = B.textAccessors("textName", { hiddenKey = "nameTextHidden" })
                        tabInner:AddTextStyleBlock({
                            get = get, set = set, apply = B.applyNameLevelText,
                            defaults = { color = {1, 0.82, 0, 1} },
                            hideToggle = { label = "Disable Name Text" },
                            -- Pet name text has no class-color mode
                            color = {
                                values = addon.Catalogs.ColorMode.DefaultCustom.values,
                                order = addon.Catalogs.ColorMode.DefaultCustom.order,
                            },
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

    -- Portrait tab builders
    local function buildPortraitSizingTab(inner)
        inner:AddSlider({
            label = "Portrait Size (Scale)",
            min = 50,
            max = 200,
            step = 1,
            get = function()
                local t = B.getPortraitDB() or {}
                return tonumber(t.scale) or 100
            end,
            set = function(v)
                local t = B.ensurePortraitDB()
                if t then t.scale = tonumber(v) or 100; B.applyPortrait() end
            end,
            minLabel = "50%",
            maxLabel = "200%",
        })
        inner:Finalize()
    end

    local function buildPortraitZoomTab(inner)
        inner:AddSlider({
            label = "Portrait Zoom",
            min = 100,
            max = 200,
            step = 1,
            get = function()
                local t = B.getPortraitDB() or {}
                return tonumber(t.zoom) or 100
            end,
            set = function(v)
                local t = B.ensurePortraitDB()
                if t then t.zoom = tonumber(v) or 100; B.applyPortrait() end
            end,
            minLabel = "100%",
            maxLabel = "200%",
        })
        inner:Finalize()
    end

    -- Kept off Builder:AddBarBorderBlock: a portrait border is a single texture with its own style list and color modes.
    local function buildPortraitBorderTab(inner)
        inner:AddToggle({
            label = "Use Custom Border",
            get = function()
                local t = B.getPortraitDB() or {}
                return not not t.portraitBorderEnable
            end,
            set = function(v)
                local t = B.ensurePortraitDB()
                if t then t.portraitBorderEnable = not not v; B.applyPortrait() end
            end,
        })

        local borderStyleValues = {
            texture_c = "Circle",
            texture_s = "Circle with Corner",
            rare_c = "Rare (Circle)",
        }
        local borderStyleOrder = { "texture_c", "texture_s", "rare_c" }

        inner:AddSelector({
            label = "Border Style",
            values = borderStyleValues,
            order = borderStyleOrder,
            get = function()
                local t = B.getPortraitDB() or {}
                local current = t.portraitBorderStyle or "texture_c"
                if current == "default" then return "texture_c" end
                return current
            end,
            set = function(v)
                local t = B.ensurePortraitDB()
                if t then
                    t.portraitBorderStyle = v or "texture_c"
                    B.applyPortrait()
                end
            end,
        })

        inner:AddSlider({
            label = "Border Inset",
            min = 1,
            max = 8,
            step = 0.5,
            precision = 1,
            get = function()
                local t = B.getPortraitDB() or {}
                local v = tonumber(t.portraitBorderThickness) or 1
                return math.max(1, math.min(8, math.floor(v * 2 + 0.5) / 2))
            end,
            set = function(v)
                local t = B.ensurePortraitDB()
                if t then t.portraitBorderThickness = math.max(1, math.min(8, math.floor((tonumber(v) or 1) * 2 + 0.5) / 2)); B.applyPortrait() end
            end,
        })

        inner:AddSelectorColorPicker({
            label = "Border Color",
            values = UF.portraitBorderColorValues,
            order = UF.portraitBorderColorOrder,
            get = function()
                local t = B.getPortraitDB() or {}
                return t.portraitBorderColorMode or "texture"
            end,
            set = function(v)
                local t = B.ensurePortraitDB()
                if t then t.portraitBorderColorMode = v or "texture"; B.applyPortrait() end
            end,
            getColor = function()
                local t = B.getPortraitDB() or {}
                local c = t.portraitBorderTintColor or {1, 1, 1, 1}
                return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
            end,
            setColor = function(r, g, b, a)
                local t = B.ensurePortraitDB()
                if t then t.portraitBorderTintColor = {r or 1, g or 1, b or 1, a or 1}; B.applyPortrait() end
            end,
            customValue = "custom",
            hasAlpha = true,
        })

        inner:Finalize()
    end

    local function buildPortraitVisibilityTab(inner)
        inner:AddToggle({
            label = "Hide Portrait",
            get = function()
                local t = B.getPortraitDB() or {}
                return not not t.hidePortrait
            end,
            set = function(v)
                local t = B.ensurePortraitDB()
                if t then t.hidePortrait = v and true or false; B.applyPortrait() end
            end,
        })

        inner:AddSlider({
            label = "Portrait Opacity",
            min = 1,
            max = 100,
            step = 1,
            get = function()
                local t = B.getPortraitDB() or {}
                return tonumber(t.opacity) or 100
            end,
            set = function(v)
                local t = B.ensurePortraitDB()
                if t then t.opacity = tonumber(v) or 100; B.applyPortrait() end
            end,
        })

        inner:Finalize()
    end

    local function buildPortraitPersonalTextTab(inner)
        -- Portrait damage text: the hide flag and text table live in the
        -- portrait sub-table, not the unit table
        inner:AddTextStyleBlock({
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
        inner:Finalize()
    end

    builder:AddCollapsibleSection({
        title = "Portrait",
        componentId = COMPONENT_ID,
        sectionKey = "portrait",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddTabbedSection({
                tabs = {
                    { key = "sizing", label = "Sizing" },
                    { key = "zoom", label = "Zoom" },
                    { key = "border", label = "Border" },
                    { key = "personalText", label = "Personal Text" },
                    { key = "visibility", label = "Visibility" },
                },
                componentId = COMPONENT_ID,
                sectionKey = "portrait_tabs",
                buildContent = {
                    sizing = function(cf, tabInner) buildPortraitSizingTab(tabInner) end,
                    zoom = function(cf, tabInner) buildPortraitZoomTab(tabInner) end,
                    border = function(cf, tabInner) buildPortraitBorderTab(tabInner) end,
                    personalText = function(cf, tabInner) buildPortraitPersonalTextTab(tabInner) end,
                    visibility = function(cf, tabInner) buildPortraitVisibilityTab(tabInner) end,
                },
            })
            inner:Finalize()
        end,
    })

    --------------------------------------------------------------------------------
    -- Collapsible Section: Visibility
    --------------------------------------------------------------------------------

    builder:AddCollapsibleSection({
        title = "Visibility",
        componentId = COMPONENT_ID,
        sectionKey = "visibility",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddToggle({
                label = "Hide Entire Pet Frame",
                description = "Completely hides the Pet frame. Useful for ConsolePort users who prefer the Pet Ring.",
                get = function()
                    local t = B.getUFDB() or {}
                    return t.hideEntireFrame == true
                end,
                set = function(v)
                    local t = B.ensureUFDB()
                    if not t then return end
                    t.hideEntireFrame = v
                    if addon.ApplyPetFrameVisibility then
                        addon.ApplyPetFrameVisibility()
                    end
                end,
            })

            local get, set = B.opacityAccessors()
            inner:AddStateOpacityBlock({
                get = get, set = set, apply = B.applyVisibility,
                min = 0, endLabels = false,
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
addon.UI.SettingsPanel:RegisterRenderer("ufPet", function(panel, scrollContent)
    UF.RenderPet(panel, scrollContent)
end)

-- Return renderer for registration
--------------------------------------------------------------------------------

return UF.RenderPet
