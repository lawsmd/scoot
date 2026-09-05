-- UFSections.lua - Shared section and tab builders for the unit frame settings
-- renderers. Not UFZSections.lua, which holds the Unit Frames Z pages.
--
-- Every builder takes B (the UF.BindUnit table) and an options table. Tab
-- builders take the tab's inner builder as opts.inner and call Finalize on it;
-- section builders take the page builder as opts.builder plus opts.componentId
-- and own their section and tab keys, which the collapse and tab state and the
-- deep links depend on. get closures read through B.get*DB only; ensure* is
-- for set closures (the search scan renders every page).
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.UnitFrames = addon.UI.UnitFrames or {}
local UF = addon.UI.UnitFrames

UF.Sections = UF.Sections or {}
local Sections = UF.Sections

--------------------------------------------------------------------------------
-- Shared Toggle Copy
--------------------------------------------------------------------------------

-- Visibility-tab toggle entries consumed by BuildToggleListTab. A file whose
-- wording differs (Player speaks of "your health") passes its own entry table
-- in place of a name from this catalog.
Sections.TOGGLES = {
    healthHideTextureOnly = {
        key = "healthBarHideTextureOnly",
        label = "Hide the Bar but not its Text",
        infoIcon = {
            tooltipTitle = "Hide the Bar but not its Text",
            tooltipText = "Hides the bar texture and background, showing only the text overlay. Useful for a number-only display of health.",
        },
    },
    hideOverAbsorbGlow = {
        key = "healthBarHideOverAbsorbGlow",
        label = "Hide Over Absorb Glow",
        description = "Hides the glow effect when absorb shields exceed max health.",
        infoIcon = UF.TOOLTIPS.hideOverAbsorbGlow,
    },
    hideHealPrediction = {
        key = "healthBarHideHealPrediction",
        label = "Hide Heal Prediction",
        description = "Hides the green heal prediction bar when healing is incoming.",
        infoIcon = {
            tooltipTitle = "Hide Heal Prediction",
            tooltipText = "Hides the green heal prediction bar that appears on the health bar when a heal is incoming.",
        },
    },
    powerBarHidden = {
        key = "powerBarHidden",
        label = "Hide Power Bar",
    },
    powerHideTextureOnly = {
        key = "powerBarHideTextureOnly",
        label = "Hide the Bar but not its Text",
        infoIcon = {
            tooltipTitle = "Hide the Bar but not its Text",
            tooltipText = "Hides the bar texture and background, showing only the text overlay. Useful for a number-only display of power.",
        },
    },
}

--------------------------------------------------------------------------------
-- Tab Builders
--------------------------------------------------------------------------------

-- Bar style tab: one AddBarStyleBlock over the bar's prefixed key family.
-- opts: inner, barPrefix, apply, colorValues, colorOrder, colorInfoIcons.
function Sections.BuildStyleTab(B, opts)
    local get, set = B.barAccessors(opts.barPrefix)
    opts.inner:AddBarStyleBlock({
        get = get, set = set, apply = opts.apply,
        foreground = { values = opts.colorValues, order = opts.colorOrder, infoIcons = opts.colorInfoIcons },
    })
    opts.inner:Finalize()
end

-- Bar border tab: one AddBarBorderBlock.
-- opts: inner, barPrefix, apply, accessorOpts (forwarded to B.barAccessors),
-- enableToggle (nil omits the enable row).
function Sections.BuildBorderTab(B, opts)
    local get, set = B.barAccessors(opts.barPrefix, opts.accessorOpts)
    opts.inner:AddBarBorderBlock({ get = get, set = set, apply = opts.apply, enableToggle = opts.enableToggle })
    opts.inner:Finalize()
end

-- Text style tab: one AddTextStyleBlock over a text sub-table.
-- opts: inner, textKey, applyHidden, defaultAlignment, colorValues, colorOrder,
-- dkPair, offset (nil keeps the row, false drops it), alignmentKind ("align"
-- unless "bossDual", which derives the dual selector key from textKey),
-- hideToggle (true unless overridden). With neither alignmentKind nor
-- defaultAlignment the alignment field stays unset and the composite renders
-- its default row.
function Sections.BuildTextTab(B, opts)
    local get, set = B.textAccessors(opts.textKey)
    local alignment
    if opts.alignmentKind == "bossDual" then
        alignment = { kind = "bossDual", default = opts.defaultAlignment, key = opts.textKey .. "AlignmentDual" }
    elseif opts.defaultAlignment ~= nil then
        alignment = { kind = "align", default = opts.defaultAlignment }
    end
    local hideToggle = opts.hideToggle
    if hideToggle == nil then hideToggle = true end
    opts.inner:AddTextStyleBlock({
        get = get, set = set, apply = B.applyStyles,
        applyHidden = opts.applyHidden,
        hideToggle = hideToggle,
        color = { values = opts.colorValues, order = opts.colorOrder, dkPair = opts.dkPair },
        alignment = alignment,
        offset = opts.offset,
    })
    opts.inner:Finalize()
end

-- Flat-key visibility toggles, one AddToggle per entry.
-- opts: inner; toggles, an ordered list of entry tables or names from
-- Sections.TOGGLES (entry fields: key, label, description, infoIcon); apply
-- (B.applyBarTextures unless overridden).
function Sections.BuildToggleListTab(B, opts)
    local apply = opts.apply or B.applyBarTextures
    for _, entry in ipairs(opts.toggles) do
        if type(entry) == "string" then entry = Sections.TOGGLES[entry] end
        local key = entry.key
        opts.inner:AddToggle({
            label = entry.label,
            description = entry.description,
            get = function()
                local t = B.getUFDB() or {}
                return not not t[key]
            end,
            set = function(v)
                local t = B.ensureUFDB()
                if not t then return end
                t[key] = v and true or false
                apply()
            end,
            infoIcon = entry.infoIcon,
        })
    end
    opts.inner:Finalize()
end

-- Name backdrop tab. The texture and color rows sit on one AddBarStyleBlock
-- foreground row, which the settings search indexes where the old hand-built
-- AddBarTextureSelector row was not. The enable toggle and the Width and
-- Opacity sliders stay hand-written, so the stored keys and the row order are
-- unchanged. opts: inner.
function Sections.BuildNameBackdropTab(B, opts)
    local inner = opts.inner
    inner:AddToggle({
        label = "Enable Backdrop",
        get = function() local t = B.getUFDB() or {}; return not not t.nameBackdropEnabled end,
        set = function(v) local t = B.ensureUFDB(); if t then t.nameBackdropEnabled = not not v; B.applyNameLevelText() end end,
    })
    local get, set = B.barAccessors("nameBackdrop")
    inner:AddBarStyleBlock({
        get = get, set = set, apply = B.applyNameLevelText,
        foreground = {
            label = "Backdrop",
            textureDefault = "",
            values = UF.bgColorValues, order = UF.bgColorOrder,
            infoIcons = false,
        },
        background = false,
        opacity = false,
    })
    inner:AddSlider({
        label = "Backdrop Width (%)", min = 25, max = 300, step = 1,
        get = function() local t = B.getUFDB() or {}; return tonumber(t.nameBackdropWidthPct) or 100 end,
        set = function(v) local t = B.ensureUFDB(); if t then t.nameBackdropWidthPct = tonumber(v) or 100; B.applyNameLevelText() end end,
    })
    inner:AddSlider({
        label = "Backdrop Opacity", min = 0, max = 100, step = 1,
        get = function() local t = B.getUFDB() or {}; return tonumber(t.nameBackdropOpacity) or 50 end,
        set = function(v) local t = B.ensureUFDB(); if t then t.nameBackdropOpacity = tonumber(v) or 50; B.applyNameLevelText() end end,
    })
    inner:Finalize()
end

-- Portrait personal (damage) text tab (Player, Pet): the hide flag and text
-- table live in the portrait sub-table, not the unit table. opts: inner.
function Sections.BuildPortraitPersonalTextTab(B, opts)
    opts.inner:AddTextStyleBlock({
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
    opts.inner:Finalize()
end

--------------------------------------------------------------------------------
-- Section Builders
--------------------------------------------------------------------------------

-- Health Bar section: tabs from UF.getHealthBarTabs, style and border on the
-- healthBar prefix, texts on the health color catalog.
-- opts: builder, componentId; visibilityToggles (entries for
-- BuildToggleListTab); alignmentKind (Boss); textHideLabels = { percent,
-- value } for Pet's labeled hide toggles.
function Sections.BuildHealthBarSection(B, opts)
    local componentId = opts.componentId
    local hideLabels = opts.textHideLabels
    opts.builder:AddCollapsibleSection({
        title = "Health Bar",
        componentId = componentId,
        sectionKey = "healthBar",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddTabbedSection({
                tabs = UF.getHealthBarTabs(componentId),
                componentId = componentId,
                sectionKey = "healthBar_tabs",
                buildContent = {
                    style = function(cf, tabInner)
                        Sections.BuildStyleTab(B, { inner = tabInner, barPrefix = "healthBar", apply = B.applyBarTextures })
                    end,
                    border = function(cf, tabInner)
                        Sections.BuildBorderTab(B, { inner = tabInner, barPrefix = "healthBar", apply = B.applyBarTextures })
                    end,
                    visibility = function(cf, tabInner)
                        Sections.BuildToggleListTab(B, { inner = tabInner, toggles = opts.visibilityToggles })
                    end,
                    percentText = function(cf, tabInner)
                        Sections.BuildTextTab(B, {
                            inner = tabInner, textKey = "textHealthPercent", applyHidden = B.applyHealthText,
                            defaultAlignment = "LEFT", colorValues = UF.fontColorHealthValues, colorOrder = UF.fontColorHealthOrder,
                            alignmentKind = opts.alignmentKind,
                            hideToggle = hideLabels and { label = hideLabels.percent } or nil,
                        })
                    end,
                    valueText = function(cf, tabInner)
                        Sections.BuildTextTab(B, {
                            inner = tabInner, textKey = "textHealthValue", applyHidden = B.applyHealthText,
                            defaultAlignment = "RIGHT", colorValues = UF.fontColorHealthValues, colorOrder = UF.fontColorHealthOrder,
                            alignmentKind = opts.alignmentKind,
                            hideToggle = hideLabels and { label = hideLabels.value } or nil,
                        })
                    end,
                },
            })
            inner:Finalize()
        end,
    })
end

-- Parent-level controls above the sections: the Hide Blizzard Art toggle, then
-- Use Larger Frame, Frame Size or the Boss Scale slider, and Scale Multiplier
-- as the unit carries them.
-- opts: builder, componentId; useCustomBorders = { clearHealthBorder = false
-- to skip the healthBarHideBorder reset (Boss), onDisable = function(t,
-- wasEnabled) for extra resets (Player) }; useLargerFrame = { description }
-- (Focus, Boss); frameSize/scaleMult = false to skip (Boss); bossScale = true
-- for the Boss db scale slider.
function Sections.BuildParentControls(B, opts)
    local builder = opts.builder
    local ucb = opts.useCustomBorders or {}
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
                if ucb.clearHealthBorder ~= false then t.healthBarHideBorder = false end
                if ucb.onDisable then ucb.onDisable(t, wasEnabled) end
            end
            B.applyBarTextures()
        end,
        infoIcon = UF.TOOLTIPS.hideBlizzardArt,
    })
    if opts.useLargerFrame then
        builder:AddToggle({
            label = "Use Larger Frame",
            description = opts.useLargerFrame.description,
            get = function()
                return UF.getUseLargerFrame(opts.componentId)
            end,
            set = function(v)
                UF.setUseLargerFrame(opts.componentId, v)
            end,
        })
    end
    if opts.frameSize ~= false then
        builder:AddSlider({
            label = "Frame Size (Scale)",
            description = "Blizzard's Edit Mode scale (100-200%).",
            min = 100,
            max = 200,
            step = 5,
            get = function()
                return UF.getEditModeFrameSize(opts.componentId)
            end,
            set = function(v)
                UF.setEditModeFrameSize(opts.componentId, v)
            end,
            minLabel = "100%",
            maxLabel = "200%",
            infoIcon = UF.TOOLTIPS.frameSize,
        })
    end
    if opts.bossScale then
        builder:AddSlider({
            label = "Scale",
            description = "Overall scale of boss frames.",
            min = 0.5, max = 2.0, step = 0.05, precision = 2,
            get = function() local t = B.getUFDB() or {}; return tonumber(t.scale) or 1.0 end,
            set = function(v) local t = B.ensureUFDB(); if t then t.scale = tonumber(v) or 1.0; B.applyStyles() end end,
            minLabel = "0.5x", maxLabel = "2.0x",
        })
    end
    if opts.scaleMult ~= false then
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
    end
end

-- Power Bar section: tabs from UF.getPowerBarTabs, style and border on the
-- powerBar prefix, texts on the power text keys.
-- opts: builder, componentId; widthSlider = true for Player's Width % row;
-- visibilityToggles; alignmentKind (Boss); styleTab = function(cf, tabInner)
-- replacing the style tab (Pet's kept hand-rolled pair); textOpts =
-- { colorValues, colorOrder, dkPair, offset, hideLabels = { percent, value },
-- defaultAlignments = false to leave the alignment row on composite defaults }.
function Sections.BuildPowerBarSection(B, opts)
    local componentId = opts.componentId
    local textOpts = opts.textOpts or {}
    local hideLabels = textOpts.hideLabels
    local function buildTextTab(tabInner, textKey, defaultAlignment, hideLabel)
        Sections.BuildTextTab(B, {
            inner = tabInner, textKey = textKey, applyHidden = B.applyPowerText,
            defaultAlignment = textOpts.defaultAlignments ~= false and defaultAlignment or nil,
            colorValues = textOpts.colorValues, colorOrder = textOpts.colorOrder,
            dkPair = textOpts.dkPair, offset = textOpts.offset,
            alignmentKind = opts.alignmentKind,
            hideToggle = hideLabel and { label = hideLabel } or nil,
        })
    end
    opts.builder:AddCollapsibleSection({
        title = "Power Bar",
        componentId = componentId,
        sectionKey = "powerBar",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddTabbedSection({
                tabs = UF.getPowerBarTabs(),
                componentId = componentId,
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
                        if opts.widthSlider then
                            tabInner:AddSlider({
                                label = "Width %", min = 10, max = 200, step = 5,
                                get = function() local t = B.getUFDB() or {}; return tonumber(t.powerBarWidthPct) or 100 end,
                                set = function(v) local t = B.ensureUFDB(); if t then t.powerBarWidthPct = tonumber(v) or 100; B.applyBarTextures() end end,
                            })
                        end
                        tabInner:AddSlider({
                            label = "Height %", min = 10, max = 200, step = 5,
                            get = function() local t = B.getUFDB() or {}; return tonumber(t.powerBarHeightPct) or 100 end,
                            set = function(v) local t = B.ensureUFDB(); if t then t.powerBarHeightPct = tonumber(v) or 100; B.applyBarTextures() end end,
                        })
                        tabInner:Finalize()
                    end,
                    style = opts.styleTab or function(cf, tabInner)
                        Sections.BuildStyleTab(B, {
                            inner = tabInner, barPrefix = "powerBar", apply = B.applyBarTextures,
                            colorValues = UF.powerColorValues, colorOrder = UF.powerColorOrder,
                        })
                    end,
                    border = function(cf, tabInner)
                        Sections.BuildBorderTab(B, { inner = tabInner, barPrefix = "powerBar", apply = B.applyBarTextures })
                    end,
                    visibility = function(cf, tabInner)
                        Sections.BuildToggleListTab(B, { inner = tabInner, toggles = opts.visibilityToggles })
                    end,
                    percentText = function(cf, tabInner)
                        buildTextTab(tabInner, "textPowerPercent", "LEFT", hideLabels and hideLabels.percent)
                    end,
                    valueText = function(cf, tabInner)
                        buildTextTab(tabInner, "textPowerValue", "RIGHT", hideLabels and hideLabels.value)
                    end,
                },
            })
            inner:Finalize()
        end,
    })
end

-- Cast Bar section (Target, Focus, Boss): the Mode selector and the tabbed
-- section share one scope so the selector's RefreshTabVisibility closure
-- reaches the tabbed ref.
-- opts: builder, componentId; anchorValues, anchorOrder (the per-unit Anchor
-- To catalog); onAnchorSet, run after the anchorMode write and before
-- B.applyCastBar (Boss marks the on-side layout dirty). Boss's five-frame
-- cast applier rides in B.applyCastBar through its BindUnit override.
function Sections.BuildCastBarSection(B, opts)
    local componentId = opts.componentId
    local castBarTabs = UF.getCastBarTabs(componentId, {
        fillLineVisible = function()
            local t = B.getCastBarDB() or {}
            return (t.castBarMode or "default") == "textFill"
        end,
    })
    opts.builder:AddCollapsibleSection({
        title = "Cast Bar",
        componentId = componentId,
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
                componentId = componentId,
                sectionKey = "castBar_tabs",
                buildContent = {
                    positioning = function(cf, tabInner)
                        tabInner:AddSelector({
                            label = "Anchor To",
                            values = opts.anchorValues,
                            order = opts.anchorOrder,
                            get = function() local t = B.getCastBarDB() or {}; return t.anchorMode or "default" end,
                            set = function(v)
                                local t = B.ensureCastBarDB()
                                if t then
                                    t.anchorMode = v
                                    if opts.onAnchorSet then opts.onAnchorSet() end
                                    B.applyCastBar()
                                end
                            end,
                        })
                        tabInner:AddOffsetPair({
                            range = 200,
                            get = function(axis) local t = B.getCastBarDB(); return t and t[axis == "x" and "offsetX" or "offsetY"] end,
                            set = function(axis, v) local t = B.ensureCastBarDB(); if t then t[axis == "x" and "offsetX" or "offsetY"] = v end end,
                            apply = B.applyCastBar,
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
end

-- Buffs & Debuffs section (Target, Focus): identical on both pages.
-- opts: builder, componentId.
function Sections.BuildBuffsDebuffsSection(B, opts)
    local componentId = opts.componentId
    opts.builder:AddCollapsibleSection({
        title = "Buffs & Debuffs",
        componentId = componentId,
        sectionKey = "buffsDebuffs",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddTabbedSection({
                tabs = UF.getBuffsDebuffsTabs(),
                componentId = componentId,
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
end

-- Name & Level Text section.
-- opts: builder, componentId; nameText = { containerWidthMax } for the
-- Target/Focus/Boss shape (separate Disable toggle, Name Container Width,
-- left-aligned block) or { hideToggleInBlock = true, colorValues, colorOrder }
-- for the Player/Pet shape (hide toggle inside the block, no width row);
-- borderTab = function(cf, tabInner) replacing the border tab (Pet's plain
-- selector without hidden edges).
function Sections.BuildNameLevelTextSection(B, opts)
    local componentId = opts.componentId
    local nameOpts = opts.nameText or {}
    opts.builder:AddCollapsibleSection({
        title = "Name & Level Text",
        componentId = componentId,
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
                componentId = componentId,
                sectionKey = "nameLevelText_tabs",
                buildContent = {
                    backdrop = function(cf, tabInner)
                        Sections.BuildNameBackdropTab(B, { inner = tabInner })
                    end,
                    border = opts.borderTab or function(cf, tabInner)
                        Sections.BuildBorderTab(B, {
                            inner = tabInner, barPrefix = "nameBackdrop", apply = B.applyNameLevelText,
                            accessorOpts = { suffixes = { enabled = "BorderEnabled" } },
                            enableToggle = true,
                        })
                    end,
                    nameText = function(cf, tabInner)
                        if nameOpts.hideToggleInBlock then
                            local get, set = B.textAccessors("textName", { hiddenKey = "nameTextHidden" })
                            tabInner:AddTextStyleBlock({
                                get = get, set = set, apply = B.applyNameLevelText,
                                defaults = { color = {1, 0.82, 0, 1} },
                                hideToggle = { label = "Disable Name Text" },
                                color = nameOpts.colorValues and { values = nameOpts.colorValues, order = nameOpts.colorOrder } or nil,
                            })
                            tabInner:Finalize()
                        else
                            tabInner:AddToggle({
                                label = "Disable Name Text",
                                get = function() local t = B.getUFDB() or {}; return not not t.nameTextHidden end,
                                set = function(v) local t = B.ensureUFDB(); if t then t.nameTextHidden = v and true or false; B.applyNameLevelText() end end,
                            })
                            tabInner:AddSlider({
                                label = "Name Container Width", min = 80, max = nameOpts.containerWidthMax or 150, step = 5,
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
                        end
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
end

-- Portrait section (Target, Focus, Player; Pet's diverges and stays in its
-- file). opts: builder, componentId; fullCircleMask = true for Player's mask
-- toggle; personalText = true for Player's damage text tab (getPortraitTabs
-- lists that tab for Player and Pet only).
function Sections.BuildPortraitSection(B, opts)
    local componentId = opts.componentId
    opts.builder:AddCollapsibleSection({
        title = "Portrait",
        componentId = componentId,
        sectionKey = "portrait",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddTabbedSection({
                tabs = UF.getPortraitTabs(componentId),
                componentId = componentId,
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
                        if opts.fullCircleMask then
                            tabInner:AddToggle({
                                label = "Use Full Circle Mask",
                                get = function() local t = B.getPortraitDB() or {}; return t.useFullCircleMask == true end,
                                set = function(v) local t = B.ensurePortraitDB(); if t then t.useFullCircleMask = (v == true); B.applyPortrait() end end,
                            })
                        end
                        tabInner:Finalize()
                    end,
                    border = function(cf, tabInner)
                        -- Kept off Builder:AddBarBorderBlock: a portrait border is a single texture with its own style list and color modes.
                        tabInner:AddToggle({
                            label = "Use Custom Border",
                            get = function() local t = B.getPortraitDB() or {}; return t.portraitBorderEnable == true end,
                            set = function(v) local t = B.ensurePortraitDB(); if t then t.portraitBorderEnable = (v == true); B.applyPortrait() end end,
                        })
                        tabInner:AddSelector({
                            label = "Border Style", values = UF.portraitBorderValues, order = UF.portraitBorderOrder,
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
                    personalText = opts.personalText and function(cf, tabInner)
                        Sections.BuildPortraitPersonalTextTab(B, { inner = tabInner })
                    end or nil,
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
end

return UF.Sections
