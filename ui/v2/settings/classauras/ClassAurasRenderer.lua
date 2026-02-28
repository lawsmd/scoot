-- ClassAurasRenderer.lua - Parameterized settings renderer for Class Auras
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.Settings = addon.UI.Settings or {}
addon.UI.Settings.ClassAuras = {}

local ClassAurasSettings = addon.UI.Settings.ClassAuras
local SettingsBuilder = addon.UI.SettingsBuilder

--------------------------------------------------------------------------------
-- Class-to-Navigation-Key Mapping
--------------------------------------------------------------------------------

local CLASS_NAV_MAP = {
    classAurasDeathKnight = "DEATHKNIGHT",
    classAurasDemonHunter = "DEMONHUNTER",
    classAurasDruid       = "DRUID",
    classAurasEvoker      = "EVOKER",
    classAurasHunter      = "HUNTER",
    classAurasMage        = "MAGE",
    classAurasMonk        = "MONK",
    classAurasPaladin     = "PALADIN",
    classAurasPriest      = "PRIEST",
    classAurasRogue       = "ROGUE",
    classAurasShaman      = "SHAMAN",
    classAurasWarlock     = "WARLOCK",
    classAurasWarrior     = "WARRIOR",
}

--------------------------------------------------------------------------------
-- Shared Render Function
--------------------------------------------------------------------------------

-- Anchor option tables for the Position DualSelector
local OUTSIDE_ANCHOR_VALUES = { LEFT = "Left", RIGHT = "Right", ABOVE = "Above", BELOW = "Below" }
local OUTSIDE_ANCHOR_ORDER = { "LEFT", "RIGHT", "ABOVE", "BELOW" }

local INSIDE_ANCHOR_VALUES = {
    TOPLEFT = "Top-Left", TOP = "Top", TOPRIGHT = "Top-Right",
    LEFT = "Left", CENTER = "Center", RIGHT = "Right",
    BOTTOMLEFT = "Bottom-Left", BOTTOM = "Bottom", BOTTOMRIGHT = "Bottom-Right",
}
local INSIDE_ANCHOR_ORDER = { "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" }

local function RenderClassAuras(panel, scrollContent, classToken)
    panel:ClearContent()

    local builder = SettingsBuilder:CreateFor(scrollContent)
    panel._currentBuilder = builder

    local CA = addon.ClassAuras
    local auras = CA and CA.GetClassAuras(classToken) or {}

    -- No auras registered for this class
    if #auras == 0 then
        builder:AddDescription("Coming soon...")
        builder:Finalize()
        return
    end

    local Helpers = addon.UI.Settings.Helpers
    local fontStyleValues = Helpers.fontStyleValues
    local fontStyleOrder = Helpers.fontStyleOrder

    -- Explainer note
    builder:AddDescription("PLEASE NOTE:", { color = {1, 0.82, 0}, fontSize = 14, topPadding = 4 })
    builder:AddDescription("Class Auras require the Buff/Debuff they track to be added to your Cooldown Manager > Tracked Buffs. Scoot will HIDE the icon from that group and use its info to power our Class Aura. This means it will still hold an empty spot in your Tracked Buffs list, so put it either in the first or last slot(s).", { color = {1, 0.82, 0}, topPadding = -8, bottomPadding = -4 })

    for _, aura in ipairs(auras) do
        local componentId = "classAura_" .. aura.id
        local h = Helpers.CreateComponentHelpers(componentId)
        local getSetting = h.get

        -- Refresh callback for this renderer
        builder:SetOnRefresh(function()
            RenderClassAuras(panel, scrollContent, classToken)
        end)

        builder:AddCollapsibleSection({
            title = aura.label,
            componentId = componentId,
            sectionKey = "main",
            defaultExpanded = false,
            buildContent = function(contentFrame, inner)

                -- Enable toggle (emphasized, off by default)
                inner:AddToggle({
                    key = "enabled",
                    label = aura.enableLabel or ("Enable " .. aura.label),
                    description = aura.enableDescription or ("Show the " .. aura.label .. " aura on your HUD."),
                    emphasized = true,
                    get = function() return getSetting("enabled") or false end,
                    set = function(val) h.setAndApply("enabled", val) end,
                })

                -- Mode selector (emphasized)
                local hasBarElement = false
                for _, elemDef in ipairs(aura.elements or {}) do
                    if elemDef.type == "bar" then hasBarElement = true; break end
                end
                if hasBarElement then
                    inner:AddSelector({
                        label = "Mode",
                        emphasized = true,
                        values = {
                            icon    = "Icon",
                            bar     = "Bar",
                            iconbar = "Icon & Bar",
                            text    = "Text Only",
                        },
                        order = { "icon", "bar", "iconbar", "text" },
                        get = function() return getSetting("mode") or "icon" end,
                        set = function(v)
                            h.setAndApply("mode", v)
                            builder:DeferredRefreshAll()
                        end,
                    })
                end

                -- Preview
                local currentMode = getSetting("mode") or "icon"

                -- Resolve icon texture from aura elements
                local previewIconTex
                local iconMode = getSetting("iconMode") or "default"
                if iconMode == "custom" then
                    for _, elemDef in ipairs(aura.elements or {}) do
                        if elemDef.type == "texture" and elemDef.customPath then
                            previewIconTex = elemDef.customPath
                            break
                        end
                    end
                end
                -- Default mode: use spell icon if available
                if not previewIconTex and aura.auraSpellId then
                    local spellInfo = C_Spell and C_Spell.GetSpellInfo(aura.auraSpellId)
                    if spellInfo and spellInfo.iconID then
                        previewIconTex = spellInfo.iconID
                    end
                end

                -- Determine if this aura has text elements
                local auraHasText = false
                for _, elemDef in ipairs(aura.elements or {}) do
                    if elemDef.type == "text" then auraHasText = true; break end
                end

                inner:AddPreview({
                    componentId = componentId,
                    mode = currentMode,
                    iconTexture = previewIconTex,
                    auraDefaultBarColor = aura.defaultBarColor,
                    settingKeys = auraHasText and { _showCAText = true } or nil,
                    rowHeight = 152,
                })

                -- Tabbed section
                local tabs = {}
                local buildContent = {}

                -- Tab 1: Icon
                local hasTexture = false
                for _, elemDef in ipairs(aura.elements or {}) do
                    if elemDef.type == "texture" then
                        hasTexture = true
                        break
                    end
                end

                if hasTexture then
                    table.insert(tabs, { key = "icon", label = "Icon" })
                    buildContent.icon = function(tabContent, tabBuilder)
                        -- Disabled function: controls are disabled when Custom Pixel Icon is selected
                        local function iconControlsDisabled()
                            return (getSetting("iconMode") or "default") ~= "default"
                        end

                        tabBuilder:AddSelector({
                            label = "Icon Style",
                            values = { default = "Default Icon", custom = "Custom Pixel Icon" },
                            order = { "default", "custom" },
                            get = function() return getSetting("iconMode") or "default" end,
                            set = function(v)
                                h.setAndApply("iconMode", v)
                                builder:DeferredRefreshAll()
                            end,
                        })

                        tabBuilder:AddSlider({
                            label = "Icon Shape",
                            description = "Adjust icon aspect ratio. Center = square icons.",
                            min = -67, max = 67, step = 1,
                            get = function() return getSetting("iconShape") or 0 end,
                            set = function(v) h.setAndApply("iconShape", v) builder:DeferredRefreshAll() end,
                            minLabel = "Wide", maxLabel = "Tall",
                            disabled = iconControlsDisabled,
                        })

                        local borderStyleValues, borderStyleOrder = Helpers.getIconBorderOptions({ { "none", "None" } })

                        tabBuilder:AddSelector({
                            label = "Border Style",
                            description = "Choose the visual style for icon borders.",
                            values = borderStyleValues,
                            order = borderStyleOrder,
                            get = function() return getSetting("borderStyle") or "none" end,
                            set = function(v) h.setAndApply("borderStyle", v) builder:DeferredRefreshAll() end,
                            disabled = iconControlsDisabled,
                        })

                        tabBuilder:AddToggleColorPicker({
                            label = "Border Tint",
                            description = "Apply a custom tint color to the icon border.",
                            get = function() return getSetting("borderTintEnable") or false end,
                            set = function(val) h.setAndApply("borderTintEnable", val) builder:DeferredRefreshAll() end,
                            getColor = function()
                                local c = getSetting("borderTintColor")
                                if c then return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 end
                                return 1, 1, 1, 1
                            end,
                            setColor = function(r, g, b, a) h.setAndApply("borderTintColor", {r, g, b, a}) builder:DeferredRefreshAll() end,
                            hasAlpha = true,
                            disabled = iconControlsDisabled,
                        })

                        tabBuilder:AddSlider({
                            label = "Border Thickness",
                            description = "Thickness of the border in pixels.",
                            min = 1, max = 8, step = 0.5, precision = 1,
                            get = function() return getSetting("borderThickness") or 1 end,
                            set = function(v) h.setAndApply("borderThickness", v) builder:DeferredRefreshAll() end,
                            minLabel = "1", maxLabel = "8",
                            disabled = iconControlsDisabled,
                        })

                        tabBuilder:AddDualSlider({
                            label = "Border Inset",
                            disabled = iconControlsDisabled,
                            sliderA = {
                                axisLabel = "H", min = -4, max = 4, step = 1,
                                get = function() return getSetting("borderInsetH") or 0 end,
                                set = function(v) h.setAndApply("borderInsetH", v) builder:DeferredRefreshAll() end,
                                minLabel = "-4", maxLabel = "+4",
                            },
                            sliderB = {
                                axisLabel = "V", min = -4, max = 4, step = 1,
                                get = function() return getSetting("borderInsetV") or 0 end,
                                set = function(v) h.setAndApply("borderInsetV", v) builder:DeferredRefreshAll() end,
                                minLabel = "-4", maxLabel = "+4",
                            },
                        })

                        tabBuilder:Finalize()
                    end
                end

                -- Tab 2: Bar (only if aura has bar elements)
                if hasBarElement then
                    local currentMode = getSetting("mode") or "icon"
                    local barTabDisabled = (currentMode == "icon" or currentMode == "text")

                    table.insert(tabs, { key = "bar", label = "Bar" })
                    buildContent.bar = function(tabContent, tabBuilder)
                        local function barControlsDisabled()
                            local m = getSetting("mode") or "icon"
                            return (m == "icon" or m == "text")
                        end

                        -- Bar Size
                        tabBuilder:AddDualSlider({
                            label = "Bar Size",
                            disabled = barControlsDisabled,
                            sliderA = {
                                axisLabel = "W", min = 20, max = 300, step = 1,
                                get = function() return getSetting("barWidth") or 120 end,
                                set = function(v) h.setAndApply("barWidth", v) builder:DeferredRefreshAll() end,
                                minLabel = "20", maxLabel = "300",
                            },
                            sliderB = {
                                axisLabel = "H", min = 4, max = 40, step = 1,
                                get = function() return getSetting("barHeight") or 12 end,
                                set = function(v) h.setAndApply("barHeight", v) builder:DeferredRefreshAll() end,
                                minLabel = "4", maxLabel = "40",
                            },
                        })

                        -- Foreground
                        tabBuilder:AddDualBarStyleRow({
                            label = "Foreground",
                            disabled = barControlsDisabled,
                            getTexture = function() return getSetting("barForegroundTexture") or "bevelled" end,
                            setTexture = function(v) h.setAndApply("barForegroundTexture", v) builder:DeferredRefreshAll() end,
                            colorValues = {
                                custom = "Custom",
                                class = "Class Color",
                                original = "Texture Original",
                            },
                            colorOrder = { "custom", "class", "original" },
                            getColorMode = function() return getSetting("barForegroundColorMode") or "custom" end,
                            setColorMode = function(v) h.setAndApply("barForegroundColorMode", v) builder:DeferredRefreshAll() end,
                            getColor = function()
                                local c = getSetting("barForegroundTint") or { 0.68, 0.85, 1.0, 1.0 }
                                return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
                            end,
                            setColor = function(r, g, b, a)
                                h.setAndApply("barForegroundTint", { r, g, b, a })
                                builder:DeferredRefreshAll()
                            end,
                            customColorValue = "custom",
                            hasAlpha = true,
                        })

                        tabBuilder:AddSpacer(8)

                        -- Background
                        tabBuilder:AddDualBarStyleRow({
                            label = "Background",
                            disabled = barControlsDisabled,
                            getTexture = function() return getSetting("barBackgroundTexture") or "bevelled" end,
                            setTexture = function(v) h.setAndApply("barBackgroundTexture", v) builder:DeferredRefreshAll() end,
                            colorValues = {
                                custom = "Custom",
                                original = "Texture Original",
                            },
                            colorOrder = { "custom", "original" },
                            getColorMode = function() return getSetting("barBackgroundColorMode") or "custom" end,
                            setColorMode = function(v) h.setAndApply("barBackgroundColorMode", v) builder:DeferredRefreshAll() end,
                            getColor = function()
                                local c = getSetting("barBackgroundTint") or { 0, 0, 0, 1 }
                                return c[1] or 0, c[2] or 0, c[3] or 0, c[4] or 1
                            end,
                            setColor = function(r, g, b, a)
                                h.setAndApply("barBackgroundTint", { r, g, b, a })
                                builder:DeferredRefreshAll()
                            end,
                            customColorValue = "custom",
                            hasAlpha = true,
                        })

                        -- Background Opacity
                        tabBuilder:AddSlider({
                            label = "Background Opacity",
                            disabled = barControlsDisabled,
                            min = 0, max = 100, step = 1,
                            get = function() return getSetting("barBackgroundOpacity") or 50 end,
                            set = function(v) h.setAndApply("barBackgroundOpacity", v) builder:DeferredRefreshAll() end,
                            minLabel = "0%", maxLabel = "100%",
                        })

                        -- Border Style
                        tabBuilder:AddBarBorderSelector({
                            label = "Border Style",
                            disabled = barControlsDisabled,
                            includeNone = true,
                            get = function() return getSetting("barBorderStyle") or "none" end,
                            set = function(v) h.setAndApply("barBorderStyle", v) builder:DeferredRefreshAll() end,
                        })

                        -- Border Tint
                        tabBuilder:AddToggleColorPicker({
                            label = "Border Tint",
                            disabled = barControlsDisabled,
                            getToggle = function() return getSetting("barBorderTintEnable") or false end,
                            setToggle = function(v) h.setAndApply("barBorderTintEnable", v) builder:DeferredRefreshAll() end,
                            getColor = function()
                                local c = getSetting("barBorderTintColor") or { 1, 1, 1, 1 }
                                return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
                            end,
                            setColor = function(r, g, b, a)
                                h.setAndApply("barBorderTintColor", { r, g, b, a })
                                builder:DeferredRefreshAll()
                            end,
                            hasAlpha = true,
                        })

                        -- Border Thickness
                        tabBuilder:AddSlider({
                            label = "Border Thickness",
                            disabled = barControlsDisabled,
                            min = 1, max = 8, step = 0.5, precision = 1,
                            get = function() return getSetting("barBorderThickness") or 1 end,
                            set = function(v) h.setAndApply("barBorderThickness", v) builder:DeferredRefreshAll() end,
                            minLabel = "1", maxLabel = "8",
                        })

                        -- Border Inset
                        tabBuilder:AddDualSlider({
                            label = "Border Inset",
                            disabled = barControlsDisabled,
                            sliderA = {
                                axisLabel = "H", min = -4, max = 4, step = 1,
                                get = function() return getSetting("barBorderInsetH") or 0 end,
                                set = function(v) h.setAndApply("barBorderInsetH", v) builder:DeferredRefreshAll() end,
                                minLabel = "-4", maxLabel = "+4",
                            },
                            sliderB = {
                                axisLabel = "V", min = -4, max = 4, step = 1,
                                get = function() return getSetting("barBorderInsetV") or 0 end,
                                set = function(v) h.setAndApply("barBorderInsetV", v) builder:DeferredRefreshAll() end,
                                minLabel = "-4", maxLabel = "+4",
                            },
                        })

                        -- Position
                        tabBuilder:AddSelector({
                            label = "Position",
                            disabled = barControlsDisabled,
                            values = { LEFT = "Left of Icon", RIGHT = "Right of Icon" },
                            order = { "LEFT", "RIGHT" },
                            get = function() return getSetting("barPosition") or "LEFT" end,
                            set = function(v)
                                h.setAndApply("barPosition", v)
                                builder:DeferredRefreshAll()
                            end,
                        })

                        -- Offset
                        tabBuilder:AddDualSlider({
                            label = "Offset",
                            disabled = barControlsDisabled,
                            sliderA = {
                                axisLabel = "X", min = -50, max = 50, step = 1,
                                get = function() return getSetting("barOffsetX") or 0 end,
                                set = function(v) h.setAndApply("barOffsetX", v) builder:DeferredRefreshAll() end,
                                minLabel = "-50", maxLabel = "+50",
                            },
                            sliderB = {
                                axisLabel = "Y", min = -50, max = 50, step = 1,
                                get = function() return getSetting("barOffsetY") or 0 end,
                                set = function(v) h.setAndApply("barOffsetY", v) builder:DeferredRefreshAll() end,
                                minLabel = "-50", maxLabel = "+50",
                            },
                        })

                        tabBuilder:Finalize()
                    end
                end

                -- Tab 3: Sizing
                table.insert(tabs, { key = "sizing", label = "Sizing" })
                buildContent.sizing = function(tabContent, tabBuilder)
                    tabBuilder:AddSlider({
                        label = "Scale",
                        description = "Overall scale of the aura frame (25-200%).",
                        min = 25,
                        max = 200,
                        step = 5,
                        get = function() return getSetting("scale") or 100 end,
                        set = function(v) h.setAndApply("scale", v) end,
                        minLabel = "25%",
                        maxLabel = "200%",
                    })

                    tabBuilder:Finalize()
                end

                -- Tab 4: Text (only if aura has text elements)
                local hasText = false
                for _, elemDef in ipairs(aura.elements or {}) do
                    if elemDef.type == "text" then
                        hasText = true
                        break
                    end
                end

                if hasText then
                    table.insert(tabs, { key = "text", label = "Text" })
                    buildContent.text = function(tabContent, tabBuilder)
                        tabBuilder:AddFontSelector({
                            label = "Font",
                            description = "The font used for aura text.",
                            get = function() return getSetting("textFont") or "FRIZQT__" end,
                            set = function(v)
                                h.setAndApply("textFont", v)
                                builder:DeferredRefreshAll()
                            end,
                        })

                        tabBuilder:AddSelector({
                            label = "Font Style",
                            description = "Outline style for aura text.",
                            values = fontStyleValues,
                            order = fontStyleOrder,
                            get = function() return getSetting("textStyle") or "OUTLINE" end,
                            set = function(v)
                                h.setAndApply("textStyle", v)
                                builder:DeferredRefreshAll()
                            end,
                        })

                        tabBuilder:AddSlider({
                            label = "Font Size",
                            description = "Size of the aura text in points (6-48).",
                            min = 6,
                            max = 48,
                            step = 1,
                            get = function() return getSetting("textSize") or 24 end,
                            set = function(v) h.setAndApply("textSize", v) builder:DeferredRefreshAll() end,
                            minLabel = "6pt",
                            maxLabel = "48pt",
                        })

                        tabBuilder:AddColorPicker({
                            label = "Font Color",
                            description = "Color for aura text.",
                            get = function()
                                local c = getSetting("textColor")
                                if c and type(c) == "table" then
                                    return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
                                end
                                return 1, 1, 1, 1
                            end,
                            set = function(r, g, b, a)
                                h.setAndApply("textColor", { r, g, b, a })
                                builder:DeferredRefreshAll()
                            end,
                            hasAlpha = true,
                        })

                        -- Position DualSelector
                        local currentPos = getSetting("textPosition") or "inside"
                        local initialBValues = currentPos == "outside" and OUTSIDE_ANCHOR_VALUES or INSIDE_ANCHOR_VALUES
                        local initialBOrder = currentPos == "outside" and OUTSIDE_ANCHOR_ORDER or INSIDE_ANCHOR_ORDER

                        tabBuilder:AddDualSelector({
                            label = "Position",
                            key = "textPositionDual",
                            maxContainerWidth = 420,
                            selectorA = {
                                values = { inside = "Inside the Icon", outside = "Outside of Icon" },
                                order = { "inside", "outside" },
                                get = function() return getSetting("textPosition") or "inside" end,
                                set = function(v)
                                    h.setAndApply("textPosition", v)
                                    local dualSelector = tabBuilder:GetControl("textPositionDual")
                                    if dualSelector then
                                        if v == "outside" then
                                            dualSelector:SetOptionsB(OUTSIDE_ANCHOR_VALUES, OUTSIDE_ANCHOR_ORDER)
                                        else
                                            dualSelector:SetOptionsB(INSIDE_ANCHOR_VALUES, INSIDE_ANCHOR_ORDER)
                                        end
                                    end
                                    builder:DeferredRefreshAll()
                                end,
                            },
                            selectorB = {
                                values = initialBValues,
                                order = initialBOrder,
                                get = function()
                                    local pos = getSetting("textPosition") or "inside"
                                    if pos == "outside" then
                                        return getSetting("textOuterAnchor") or "RIGHT"
                                    else
                                        return getSetting("textInnerAnchor") or "CENTER"
                                    end
                                end,
                                set = function(v)
                                    local pos = getSetting("textPosition") or "inside"
                                    if pos == "outside" then
                                        h.setAndApply("textOuterAnchor", v)
                                    else
                                        h.setAndApply("textInnerAnchor", v)
                                    end
                                    builder:DeferredRefreshAll()
                                end,
                            },
                        })

                        tabBuilder:AddDualSlider({
                            label = "Offset",
                            sliderA = {
                                axisLabel = "X", min = -50, max = 50, step = 1,
                                get = function() return getSetting("textOffsetX") or 0 end,
                                set = function(v) h.setAndApply("textOffsetX", v) builder:DeferredRefreshAll() end,
                                minLabel = "-50", maxLabel = "+50",
                            },
                            sliderB = {
                                axisLabel = "Y", min = -50, max = 50, step = 1,
                                get = function() return getSetting("textOffsetY") or 0 end,
                                set = function(v) h.setAndApply("textOffsetY", v) builder:DeferredRefreshAll() end,
                                minLabel = "-50", maxLabel = "+50",
                            },
                        })

                        tabBuilder:Finalize()
                    end
                end

                inner:AddTabbedSection({
                    tabs = tabs,
                    componentId = componentId,
                    sectionKey = "auraTabs",
                    buildContent = buildContent,
                })

                inner:Finalize()
            end,
        })
    end

    builder:Finalize()
end

--------------------------------------------------------------------------------
-- Register one renderer per nav key
--------------------------------------------------------------------------------

for navKey, classToken in pairs(CLASS_NAV_MAP) do
    addon.UI.SettingsPanel:RegisterRenderer(navKey, function(panel, scrollContent)
        RenderClassAuras(panel, scrollContent, classToken)
    end)
end

return ClassAurasSettings
