-- PlayerSections.lua - Player-only conditional sections for PlayerRenderer
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.UnitFrames = addon.UI.UnitFrames or {}
local UF = addon.UI.UnitFrames

UF.PlayerSections = UF.PlayerSections or {}

-- Alternate Power Bar visibility toggles; the blocks are identical apart from
-- these fields.
local ALT_POWER_VISIBILITY_TOGGLES = {
    {
        key = "hidden", label = "Hide Alternate Power Bar",
        tooltipTitle = "Hide Alternate Power Bar",
        tooltipText = "Completely hides the alternate power bar (e.g., Maelstrom for Elemental Shaman, Insanity for Shadow Priest, Stagger for Brewmaster).",
    },
    {
        key = "hideTextureOnly", label = "Hide the Bar but not its Text",
        tooltipTitle = "Hide the Bar but not its Text",
        tooltipText = "Hides the bar texture and background, showing only the text overlay. Useful for a number-only display of your alternate power resource.",
    },
    {
        key = "hideFullSpikes", label = "Hide Full Bar Animations",
        tooltipTitle = "Full Bar Animations",
        tooltipText = "Disables Blizzard's full-bar celebration animations that play when the resource is full. These overlays can't be resized, so hiding them keeps custom bar heights consistent.",
    },
    {
        key = "hideFeedback", label = "Hide Power Feedback",
        tooltipTitle = "Power Feedback",
        tooltipText = "Disables the flash animation that plays when you spend or gain alternate power. This animation shows a quick highlight on the portion of the bar that changed.",
    },
    {
        key = "hideSpark", label = "Hide APB Spark",
        tooltipTitle = "APB Spark",
        tooltipText = "Hides the spark/glow indicator that appears at the current power level on the alternate power bar.",
    },
    {
        key = "hideManaCostPrediction", label = "Hide Mana Cost Predictions",
        tooltipTitle = "Mana Cost Predictions",
        tooltipText = "Hides the power cost prediction overlay that appears on the alternate power bar when casting a spell.",
    },
    {
        key = "percentHidden", label = "Hide Percent Text",
        tooltipTitle = "Hide Percent Text",
        tooltipText = "Hides the percentage text overlay on the alternate power bar.",
    },
    {
        key = "valueHidden", label = "Hide Value Text",
        tooltipTitle = "Hide Value Text",
        tooltipText = "Hides the numeric value text overlay on the alternate power bar.",
    },
}

--------------------------------------------------------------------------------
-- Alternate Power Bar Section
--------------------------------------------------------------------------------
-- Builds the full collapsible section for Alternate Power Bar.
-- Called from PlayerRenderer when addon.UnitFrames_PlayerHasAlternatePowerBar() is true.

function UF.PlayerSections.buildAlternatePowerBar(builder, COMPONENT_ID, ensureUFDBFn, applyBarTexturesFn, getUFDBFn)
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

    local function getAltPowerBarDB()
        local t = getUFDBFn and getUFDBFn() or nil
        return t and rawget(t, "altPowerBar") or nil
    end

    local function getAltPowerTextDB(textKey)
        local apb = getAltPowerBarDB()
        return apb and rawget(apb, textKey) or nil
    end

    -- Bar fields for AddBarStyleBlock and AddBarBorderBlock on the lowercase
    -- keys this sub-table stores (texture, borderStyle, ...); insetH/insetV
    -- fall back to the legacy single-value borderInset.
    local ALT_POWER_BAR_KEYS = {
        texture = "texture", colorMode = "colorMode", color = "tint",
        bgTexture = "backgroundTexture", bgColorMode = "backgroundColorMode",
        bgColor = "backgroundTint", bgOpacity = "backgroundOpacity",
        style = "borderStyle", hiddenEdges = "borderHiddenEdges",
        tintEnabled = "borderTintEnable", tintColor = "borderTintColor",
        thickness = "borderThickness", insetH = "borderInsetH", insetV = "borderInsetV",
    }
    local altBarGet, altBarSet = addon.UI.Settings.Helpers.CreateFlatAccessors(
        function(key)
            local apb = getAltPowerBarDB()
            if not apb then return nil end
            local v = apb[key]
            if v == nil and (key == "borderInsetH" or key == "borderInsetV") then
                v = apb.borderInset
            end
            return v
        end,
        function(key, value)
            local apb = ensureAltPowerBarDB()
            if apb then apb[key] = value end
        end,
        ALT_POWER_BAR_KEYS)

    -- Alt power text tables sit two levels down (unit db > altPowerBar >
    -- textPercent/textValue), below UF.textAccessors' reach, so the field
    -- mapping is local. Hide toggles live in the Visibility tab.
    local function buildAltPowerTextTab(tabInner, textKey, defaultAlignment)
        tabInner:AddTextStyleBlock({
            get = function(field)
                local s = getAltPowerTextDB(textKey)
                if not s then return nil end
                if field == "offsetX" or field == "offsetY" then
                    local o = s.offset
                    return o and o[field == "offsetX" and "x" or "y"]
                end
                return s[field]
            end,
            set = function(field, value)
                local s = ensureAltPowerTextDB(textKey)
                if not s then return end
                if field == "offsetX" or field == "offsetY" then
                    s.offset = s.offset or {}
                    s.offset[field == "offsetX" and "x" or "y"] = value
                else
                    s[field] = value
                end
            end,
            apply = applyBarTexturesFn,
            color = { values = UF.fontColorPowerValues, order = UF.fontColorPowerOrder },
            alignment = { kind = "align", default = defaultAlignment },
        })
        tabInner:Finalize()
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
                        tabInner:AddOffsetPair({
                            range = 150,
                            get = function(axis) local apb = getAltPowerBarDB(); return apb and apb[axis == "x" and "offsetX" or "offsetY"] end,
                            set = function(axis, v) local apb = ensureAltPowerBarDB(); if apb then apb[axis == "x" and "offsetX" or "offsetY"] = v end end,
                            apply = applyBarTexturesFn,
                        })
                        tabInner:Finalize()
                    end,
                    sizing = function(cf, tabInner)
                        tabInner:AddSlider({
                            label = "Width %",
                            min = 10, max = 150, step = 1,
                            get = function()
                                local apb = getAltPowerBarDB() or {}
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
                        tabInner:AddBarStyleBlock({
                            get = altBarGet, set = altBarSet, apply = applyBarTexturesFn,
                            foreground = { infoIcons = false },
                        })
                        tabInner:Finalize()
                    end,
                    border = function(cf, tabInner)
                        tabInner:AddBarBorderBlock({ get = altBarGet, set = altBarSet, apply = applyBarTexturesFn })
                        tabInner:Finalize()
                    end,
                    visibility = function(cf, tabInner)
                        for _, entry in ipairs(ALT_POWER_VISIBILITY_TOGGLES) do
                            local key = entry.key
                            tabInner:AddToggle({
                                label = entry.label,
                                get = function()
                                    local apb = getAltPowerBarDB() or {}
                                    return apb[key] == true
                                end,
                                set = function(v)
                                    local apb = ensureAltPowerBarDB()
                                    if not apb then return end
                                    apb[key] = (v == true)
                                    applyBarTexturesFn()
                                end,
                                infoIcon = {
                                    tooltipTitle = entry.tooltipTitle,
                                    tooltipText = entry.tooltipText,
                                },
                            })
                        end
                        tabInner:Finalize()
                    end,
                    percentText = function(cf, tabInner)
                        buildAltPowerTextTab(tabInner, "textPercent", "LEFT")
                    end,
                    valueText = function(cf, tabInner)
                        buildAltPowerTextTab(tabInner, "textValue", "RIGHT")
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

function UF.PlayerSections.buildClassResource(builder, COMPONENT_ID, ensureUFDBFn, getUFDBFn)
    local function ensureClassResourceDB()
        local t = ensureUFDBFn()
        if not t then return nil end
        t.classResource = t.classResource or {}
        return t.classResource
    end

    local function getClassResourceDB()
        local t = getUFDBFn and getUFDBFn() or nil
        return t and rawget(t, "classResource") or nil
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
                        local cfg = getClassResourceDB() or {}
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
                tabInner:AddOffsetPair({
                    range = 150,
                    get = function(axis) local cfg = getClassResourceDB(); return cfg and cfg[axis == "x" and "offsetX" or "offsetY"] end,
                    set = function(axis, v) local cfg = ensureClassResourceDB(); if cfg then cfg[axis == "x" and "offsetX" or "offsetY"] = v end end,
                    apply = applyClassResource,
                })
                tabInner:Finalize()
            end

            crBuildContent.sizing = function(cf, tabInner)
                tabInner:AddSlider({
                    label = getClassResourceTitle() .. " Scale",
                    min = 50, max = 150, step = 1,
                    get = function()
                        local cfg = getClassResourceDB() or {}
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
                        local cfg = getClassResourceDB() or {}
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

    local function getTotemBarDB()
        local t = UF.getUFDB(UNIT_KEY)
        return t and rawget(t, "totemBar") or nil
    end

    local function getTotemBarIconBordersDB()
        local tb = getTotemBarDB()
        return tb and rawget(tb, "iconBorders") or nil
    end

    local function getTotemBarTimerTextDB()
        local tb = getTotemBarDB()
        return tb and rawget(tb, "timerText") or nil
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
                                local cfg = getTotemBarIconBordersDB() or {}
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
                        -- Timer text stores its hide flag inside its own
                        -- table (cfg.hidden), unlike unit text tables
                        tabInner:AddTextStyleBlock({
                            get = function(field)
                                local cfg = getTotemBarTimerTextDB()
                                if not cfg then return nil end
                                if field == "offsetX" or field == "offsetY" then
                                    local o = cfg.offset
                                    return o and o[field == "offsetX" and "x" or "y"]
                                end
                                return cfg[field]
                            end,
                            set = function(field, value)
                                local cfg = ensureTotemBarTimerTextDB()
                                if not cfg then return end
                                if field == "offsetX" or field == "offsetY" then
                                    cfg.offset = cfg.offset or {}
                                    cfg.offset[field == "offsetX" and "x" or "y"] = value
                                else
                                    cfg[field] = value
                                end
                            end,
                            apply = applyTotemBar,
                            defaults = { size = 12 },
                            hideToggle = { label = "Hide Timer Text" },
                            size = { min = 6, max = 24 },
                            color = { kind = "plain" },
                            offset = { range = 50 },
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
