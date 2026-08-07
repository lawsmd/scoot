-- unitframes/UFZSections.lua - the Unit Frames Z settings pages
--
-- The shipped Unit Frames Z menu design, promoted whole from the Debug Menu's
-- production previews: an emphasized Overall Scale, then per-component
-- collapsibles (Name/Health/Power/Level) each holding a Font-Size/Positioning
-- tabbed section. The Player and Target pages are the SAME section body
-- parameterized by unitKey and componentId (independent collapse/tab state),
-- driving the production engine through UFZ.GetAPI -- every control reads and
-- writes the per-unit profile DB, so state saves with the profile.
--
-- Zero-touch: htCfg/call gate on the unit's Z mode, so a settings-search scan
-- pass (which renders every page, including ones the nav hides) can never
-- materialize the UFZ DB or build a frame on a profile that has Z off.

local addonName, addon = ...

local UIPanel = addon.UI.SettingsPanel

-- One UFZ unit page body. opts = { title, componentId, unitKey, unitWord }.
local function AddUnitSection(builder, opts)
    builder:AddSection(opts.title)

    local UFZ = addon.UnitFramesZ
    if not (UFZ and UFZ.GetConfig) then
        builder:AddDescription("Unit Frames Z is not loaded -- /reload and reopen this panel.")
        return
    end

    local function htCfg()
        if not addon:IsModuleEnabled("unitFramesZ", opts.unitKey) then return {} end
        return UFZ.GetConfig(opts.unitKey) or {}
    end
    local function call(name, ...)
        if not addon:IsModuleEnabled("unitFramesZ", opts.unitKey) then return end
        local api = UFZ.GetAPI(opts.unitKey)
        local fn = api and api[name]
        if fn then fn(...) end
    end

    -- The name-relative location system (anchorPowerFS): shared by the power,
    -- alternate power and level texts.
    local locValues = {
        bottomleft = "Below Name - Left",
        bottomright = "Below Name - Right",
        topleft = "Above Name - Left",
        topright = "Above Name - Right",
        nameside = "Beside Name (Far Side)",
    }
    local locOrder = { "bottomleft", "bottomright", "topleft", "topright", "nameside" }

    -- Keys must match DEAD_ICONS in unitframesz/engine.lua. Every entry is a
    -- Blizzard asset; they are offered as a choice rather than one hardcoded
    -- pick because their source art differs in size, and how sharp each stays
    -- at 40px can only be judged on screen.
    local deadIconValues = {
        bossbanner = "Boss Banner Skull",
        bossspikes = "Boss Banner Skull (Spiked)",
        torghast1  = "Torghast Skull 1",
        torghast2  = "Torghast Skull 2",
        torghast3  = "Torghast Skull 3",
        raidmarker = "Raid Marker Skull",
    }
    local deadIconOrder = { "bossbanner", "bossspikes", "torghast1", "torghast2", "torghast3", "raidmarker" }

    builder:AddDescription("Scoot's text-first " .. (opts.unitWord or "player") .. " frame. Controls apply live and save with your profile. Position the frame in Edit Mode, where Overall Scale is also mirrored.")

    builder:AddSlider({
        label = "Overall Scale",
        emphasized = true,
        min = 0.5,
        max = 2.0,
        step = 0.05,
        precision = 0,
        displayMultiplier = 100,
        displaySuffix = "%",
        get = function() return htCfg().scale or 1 end,
        set = function(v) call("SetScale", v) end,
    })

    builder:AddCollapsibleSection({
        title = "Name",
        componentId = opts.componentId,
        sectionKey = "name",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddTabbedSection({
                tabs = {
                    { key = "fontSize", label = "Font/Size" },
                    { key = "position", label = "Positioning" },
                },
                componentId = opts.componentId,
                sectionKey = "name_tabs",
                buildContent = {
                    fontSize = function(cf, tabInner)
                        tabInner:AddFontSelector({
                            label = "Font",
                            get = function()
                                local c = htCfg()
                                return (c.nameFace ~= "follow" and c.nameFace) or c.face
                            end,
                            set = function(key) call("SetNameFont", key) end,
                        })
                        tabInner:AddSlider({
                            label = "Size",
                            description = "The ceiling: the name auto-shrinks from here to fit its max width, never grows past it.",
                            min = 6, max = 48, step = 1,
                            get = function() return htCfg().nameSize or 26 end,
                            set = function(v) call("SetNameSize", v) end,
                        })
                        tabInner:AddSelectorColorPicker({
                            label = "Color",
                            values = {
                                gradient = "Class Gradient",
                                custom = "Custom",
                            },
                            order = { "gradient", "custom" },
                            get = function() return htCfg().nameColorMode or "gradient" end,
                            set = function(v) call("SetNameColorMode", v) end,
                            getColor = function()
                                local c = htCfg()
                                return c.nameColorR or 1, c.nameColorG or 1, c.nameColorB or 1, c.nameColorA or 1
                            end,
                            setColor = function(r, g, b, a) call("SetNameColor", r, g, b, a) end,
                            customValue = "custom",
                            hasAlpha = true,
                        })
                        tabInner:Finalize()
                    end,
                    position = function(cf, tabInner)
                        -- Offsets from the tuned baseline (0/0 = shipped
                        -- position); negative X pulls the name toward the
                        -- numbers, positive Y lifts it.
                        tabInner:AddDualSlider({
                            label = "Position",
                            sliderA = {
                                axisLabel = "X",
                                min = -100, max = 150, step = 1,
                                get = function() return htCfg().nameOffset or 0 end,
                                set = function(v) call("SetNameOffset", v) end,
                            },
                            sliderB = {
                                axisLabel = "Y",
                                min = -40, max = 40, step = 1,
                                get = function() return htCfg().nameY or 0 end,
                                set = function(v) call("SetNameY", v) end,
                            },
                        })
                        tabInner:AddSlider({
                            label = "Max Width",
                            description = "The auto-shrink fit box: names too wide for this at the set Size render smaller.",
                            min = 60, max = 300, step = 5,
                            get = function() return htCfg().nameMaxWidth or 150 end,
                            set = function(v) call("SetNameMaxWidth", v) end,
                        })
                        tabInner:AddSlider({
                            label = "Max Lines",
                            description = "How many lines the name may wrap onto inside its max width.",
                            min = 1, max = 4, step = 1,
                            get = function() return htCfg().nameMaxLines or 2 end,
                            set = function(v) call("SetNameMaxLines", v) end,
                        })
                        tabInner:Finalize()
                    end,
                },
            })
            inner:Finalize()
        end,
    })

    builder:AddCollapsibleSection({
        title = "Health",
        componentId = opts.componentId,
        sectionKey = "health",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddTabbedSection({
                tabs = {
                    { key = "fontSize", label = "Font/Size" },
                    { key = "position", label = "Positioning" },
                    { key = "dead", label = "Dead" },
                },
                componentId = opts.componentId,
                sectionKey = "health_tabs",
                buildContent = {
                    fontSize = function(cf, tabInner)
                        tabInner:AddFontSelector({
                            label = "Font",
                            description = "Shared by the percent and value rows.",
                            get = function() return htCfg().face or "ANTON_WIDE_150" end,
                            set = function(key) call("SetFont", key) end,
                        })
                        tabInner:AddSlider({
                            label = "% Font Size",
                            description = "Master size (the 2-digit rendering); the 1- and 3-digit sizes scale along proportionally.",
                            min = 16, max = 48, step = 1,
                            get = function() return htCfg().digitSize2 or 32 end,
                            set = function(v) call("SetPctSizeMaster", v) end,
                        })
                        tabInner:AddSlider({
                            label = "Value Font Size",
                            min = 6, max = 30, step = 0.5, precision = 1,
                            get = function() return htCfg().valSize or 10 end,
                            set = function(v) call("SetValSize", v) end,
                        })
                        tabInner:AddToggle({
                            label = "% Symbol",
                            description = "Small '%' at the top-right of the percent number, a fifth of its height -- it shrinks and grows with the digit-count sizes.",
                            get = function() return htCfg().symbol and true or false end,
                            set = function(v) call("SetSymbol", v and "on" or "off") end,
                        })
                        tabInner:AddToggle({
                            label = "Absorb Shield",
                            description = "Shield value on a soft glow above the percent number. Follows the value row's font and size; hides itself while the unit has no shield.",
                            get = function() return htCfg().absorbShow and true or false end,
                            set = function(v) call("SetAbsorbShow", v and "on" or "off") end,
                        })
                        tabInner:Finalize()
                    end,
                    position = function(cf, tabInner)
                        -- 0.1 px steps: under a fractional UI scale sub-px
                        -- anchor offsets land on different physical pixels,
                        -- so the fine steps are the real tuning knob.
                        tabInner:AddSlider({
                            label = "Number Row Gap",
                            description = "Vertical gap between the percent row and the value row. Negative overlaps the rows.",
                            min = -10, max = 10, step = 0.1, precision = 1,
                            get = function() return htCfg().gap or 0 end,
                            set = function(v) call("SetGap", v) end,
                        })
                        tabInner:AddSlider({
                            label = "% Symbol Gap",
                            description = "Space between the percent number and the '%' symbol. Negative tucks the symbol into the digits.",
                            min = -10, max = 10, step = 0.1, precision = 1,
                            get = function() return htCfg().symbolGap or -2 end,
                            set = function(v) call("SetSymbolGap", v) end,
                        })
                        tabInner:AddDualSlider({
                            label = "Absorb Offset",
                            sliderA = {
                                axisLabel = "X",
                                min = -40, max = 40, step = 1,
                                get = function() return htCfg().absorbX or 0 end,
                                set = function(v) call("SetAbsorbOffset", v) end,
                            },
                            sliderB = {
                                axisLabel = "Y",
                                min = -40, max = 40, step = 1,
                                get = function() return htCfg().absorbY or 0 end,
                                set = function(v) call("SetAbsorbOffset", nil, v) end,
                            },
                        })
                        tabInner:Finalize()
                    end,
                    dead = function(cf, tabInner)
                        tabInner:AddDescription("A dead or ghost unit shows a skull in place of both health numbers -- two stacked zeros read as a glitch, not as death.")
                        tabInner:AddToggle({
                            label = "Skull When Dead",
                            description = "Replaces the percent, the value and the '%' with a skull, centered on the space they occupied. Power, shield and level are unaffected.",
                            get = function() return htCfg().deadIconShow and true or false end,
                            set = function(v) call("SetDeadIconShow", v and "on" or "off") end,
                        })
                        tabInner:AddSelector({
                            label = "Skull Style",
                            description = "Blizzard artwork. They differ in how large the source art is, so they sharpen differently at big sizes -- pick the one that stays crisp at your scale.",
                            values = deadIconValues,
                            order = deadIconOrder,
                            get = function() return htCfg().deadIconAtlas or "bossbanner" end,
                            set = function(v) call("SetDeadIconAtlas", v) end,
                        })
                        tabInner:AddSlider({
                            label = "Skull Size",
                            description = "Percent of the height of the two number rows it replaces, so it tracks your health font sizes.",
                            min = 50, max = 200, step = 5,
                            displaySuffix = "%",
                            get = function() return htCfg().deadIconScale or 100 end,
                            set = function(v) call("SetDeadIconScale", v) end,
                        })
                        tabInner:AddDualSlider({
                            label = "Skull Offset",
                            sliderA = {
                                axisLabel = "X",
                                min = -60, max = 60, step = 1,
                                get = function() return htCfg().deadIconX or 0 end,
                                set = function(v) call("SetDeadIconOffset", v) end,
                            },
                            sliderB = {
                                axisLabel = "Y",
                                min = -60, max = 60, step = 1,
                                get = function() return htCfg().deadIconY or 0 end,
                                set = function(v) call("SetDeadIconOffset", nil, v) end,
                            },
                        })
                        tabInner:Finalize()
                    end,
                },
            })
            inner:Finalize()
        end,
    })

    -- Classification is a TARGET-side adornment: the player is never elite or
    -- rare, so the Player page never renders this section (the engine hard
    -- early-outs on the player unit too).
    if opts.unitKey ~= "Player" then
        builder:AddCollapsibleSection({
            title = "Elite & Rare",
            componentId = opts.componentId,
            sectionKey = "classify",
            defaultExpanded = false,
            buildContent = function(contentFrame, inner)
                inner:AddDescription("Blizzard wraps a dragon around the portrait to mark elite and rare mobs. This frame has no portrait, so the same artwork becomes a small icon beside the name.")
                inner:AddToggle({
                    label = "Show Elite/Rare Icon",
                    description = "Gold dragon for elites and world bosses, silver dragon for rare elites, silver star for rares -- Blizzard's own nameplate art and mapping. Normal mobs show nothing.",
                    get = function() return htCfg().classifyShow and true or false end,
                    set = function(v) call("SetClassifyShow", v and "on" or "off") end,
                })
                inner:AddSelector({
                    label = "Location",
                    description = "Where the icon sits relative to the name.",
                    values = locValues,
                    order = locOrder,
                    get = function() return htCfg().classifyLoc or "topright" end,
                    set = function(v) call("SetClassifyLoc", v) end,
                })
                inner:AddSlider({
                    label = "Icon Size",
                    min = 8, max = 48, step = 1,
                    get = function() return htCfg().classifySize or 20 end,
                    set = function(v) call("SetClassifySize", v) end,
                })
                inner:AddDualSlider({
                    label = "Offset",
                    sliderA = {
                        axisLabel = "X",
                        min = -60, max = 60, step = 1,
                        get = function() return htCfg().classifyX or 0 end,
                        set = function(v) call("SetClassifyOffset", v) end,
                    },
                    sliderB = {
                        axisLabel = "Y",
                        min = -60, max = 60, step = 1,
                        get = function() return htCfg().classifyY or 0 end,
                        set = function(v) call("SetClassifyOffset", nil, v) end,
                    },
                })
                inner:Finalize()
            end,
        })
    end

    builder:AddCollapsibleSection({
        title = "Power",
        componentId = opts.componentId,
        sectionKey = "power",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddTabbedSection({
                tabs = {
                    { key = "fontSize", label = "Font/Size" },
                    { key = "position", label = "Positioning" },
                },
                componentId = opts.componentId,
                sectionKey = "power_tabs",
                buildContent = {
                    fontSize = function(cf, tabInner)
                        tabInner:AddToggle({
                            label = "Primary Power",
                            description = "The unit's main resource as a flat value (mana, rage, energy...).",
                            get = function() return htCfg().powerShow and true or false end,
                            set = function(v) call("SetPowerShow", v and "on" or "off") end,
                        })
                        tabInner:AddSlider({
                            label = "Primary Size",
                            min = 6, max = 30, step = 0.5, precision = 1,
                            get = function() return htCfg().powerSize or 10 end,
                            set = function(v) call("SetPowerSize", v) end,
                        })
                        tabInner:AddSelectorColorPicker({
                            label = "Primary Color",
                            values = {
                                power = "Power Color",
                                custom = "Custom",
                            },
                            order = { "power", "custom" },
                            get = function() return htCfg().powerColorMode or "power" end,
                            set = function(v) call("SetPowerColorMode", v) end,
                            getColor = function()
                                local c = htCfg()
                                return c.powerColorR or 1, c.powerColorG or 1, c.powerColorB or 1, c.powerColorA or 1
                            end,
                            setColor = function(r, g, b, a) call("SetPowerColor", r, g, b, a) end,
                            customValue = "custom",
                            hasAlpha = true,
                        })
                        tabInner:AddToggle({
                            label = "Alternate Power",
                            description = "The secondary bar's resource (e.g. mana on a Shadow Priest). Hidden automatically when the spec has none.",
                            get = function() return htCfg().altPowerShow and true or false end,
                            set = function(v) call("SetAltPowerShow", v and "on" or "off") end,
                        })
                        tabInner:AddSlider({
                            label = "Alternate Size",
                            min = 6, max = 30, step = 0.5, precision = 1,
                            get = function() return htCfg().altPowerSize or 10 end,
                            set = function(v) call("SetAltPowerSize", v) end,
                        })
                        tabInner:AddSelectorColorPicker({
                            label = "Alternate Color",
                            values = {
                                power = "Power Color",
                                custom = "Custom",
                            },
                            order = { "power", "custom" },
                            get = function() return htCfg().altPowerColorMode or "power" end,
                            set = function(v) call("SetAltPowerColorMode", v) end,
                            getColor = function()
                                local c = htCfg()
                                return c.altPowerColorR or 1, c.altPowerColorG or 1, c.altPowerColorB or 1, c.altPowerColorA or 1
                            end,
                            setColor = function(r, g, b, a) call("SetAltPowerColor", r, g, b, a) end,
                            customValue = "custom",
                            hasAlpha = true,
                        })
                        tabInner:AddToggle({
                            label = "Percent Sign",
                            description = "The small % on percent-rendered resources (alternate mana). Drawn at half the number's size.",
                            get = function() return htCfg().powerSymbol and true or false end,
                            set = function(v) call("SetPowerSymbol", v and "on" or "off") end,
                        })
                        tabInner:Finalize()
                    end,
                    position = function(cf, tabInner)
                        tabInner:AddSelector({
                            label = "Primary Location",
                            description = "Relative to the name. 'Beside Name' sits on the side away from the health numbers.",
                            values = locValues,
                            order = locOrder,
                            get = function() return htCfg().powerLoc or "bottomright" end,
                            set = function(v) call("SetPowerLoc", v) end,
                        })
                        tabInner:AddDualSlider({
                            label = "Primary Offset",
                            sliderA = {
                                axisLabel = "X",
                                min = -40, max = 40, step = 1,
                                get = function() return htCfg().powerX or 0 end,
                                set = function(v) call("SetPowerOffset", v) end,
                            },
                            sliderB = {
                                axisLabel = "Y",
                                min = -40, max = 40, step = 1,
                                get = function() return htCfg().powerY or 0 end,
                                set = function(v) call("SetPowerOffset", nil, v) end,
                            },
                        })
                        tabInner:AddSelector({
                            label = "Alternate Location",
                            values = locValues,
                            order = locOrder,
                            get = function() return htCfg().altPowerLoc or "bottomleft" end,
                            set = function(v) call("SetAltPowerLoc", v) end,
                        })
                        tabInner:AddDualSlider({
                            label = "Alternate Offset",
                            sliderA = {
                                axisLabel = "X",
                                min = -40, max = 40, step = 1,
                                get = function() return htCfg().altPowerX or 0 end,
                                set = function(v) call("SetAltPowerOffset", v) end,
                            },
                            sliderB = {
                                axisLabel = "Y",
                                min = -40, max = 40, step = 1,
                                get = function() return htCfg().altPowerY or 0 end,
                                set = function(v) call("SetAltPowerOffset", nil, v) end,
                            },
                        })
                        tabInner:Finalize()
                    end,
                },
            })
            inner:Finalize()
        end,
    })

    builder:AddCollapsibleSection({
        title = "Level",
        componentId = opts.componentId,
        sectionKey = "level",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddTabbedSection({
                tabs = {
                    { key = "fontSize", label = "Font/Size" },
                    { key = "position", label = "Positioning" },
                },
                componentId = opts.componentId,
                sectionKey = "level_tabs",
                buildContent = {
                    fontSize = function(cf, tabInner)
                        tabInner:AddToggle({
                            label = "Hide at Max Level",
                            description = "Hides the level text while at the effective max level, including targets too high to read (lvl ??). The text has no other toggle.",
                            get = function() return htCfg().levelHideMax and true or false end,
                            set = function(v) call("SetLevelHideMax", v and "on" or "off") end,
                        })
                        tabInner:AddSlider({
                            label = "Size",
                            min = 6, max = 30, step = 0.5, precision = 1,
                            get = function() return htCfg().levelSize or 8 end,
                            set = function(v) call("SetLevelSize", v) end,
                        })
                        tabInner:Finalize()
                    end,
                    position = function(cf, tabInner)
                        tabInner:AddSelector({
                            label = "Location",
                            description = "Relative to the name. 'Beside Name' sits on the side away from the health numbers.",
                            values = locValues,
                            order = locOrder,
                            get = function() return htCfg().levelLoc or "topleft" end,
                            set = function(v) call("SetLevelLoc", v) end,
                        })
                        tabInner:AddDualSlider({
                            label = "Offset",
                            sliderA = {
                                axisLabel = "X",
                                min = -40, max = 40, step = 1,
                                get = function() return htCfg().levelX or 0 end,
                                set = function(v) call("SetLevelOffset", v) end,
                            },
                            sliderB = {
                                axisLabel = "Y",
                                min = -40, max = 40, step = 1,
                                get = function() return htCfg().levelY or 0 end,
                                set = function(v) call("SetLevelOffset", nil, v) end,
                            },
                        })
                        tabInner:Finalize()
                    end,
                },
            })
            inner:Finalize()
        end,
    })

    builder:AddCollapsibleSection({
        title = "Buffs & Debuffs",
        componentId = opts.componentId,
        sectionKey = "auras",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddTabbedSection({
                tabs = {
                    { key = "layout", label = "Layout" },
                    { key = "sizing", label = "Sizing" },
                    { key = "border", label = "Border" },
                    { key = "filters", label = "Filters" },
                },
                componentId = opts.componentId,
                sectionKey = "auras_tabs",
                buildContent = {
                    layout = function(cf, tabInner)
                        tabInner:AddToggle({
                            label = "Show Buffs",
                            description = "Icon row of the unit's buffs. Icons wrap to more lines when the row outgrows the frame.",
                            get = function() return htCfg().auraBuffsShow and true or false end,
                            set = function(v) call("SetAuraBuffsShow", v and "on" or "off") end,
                        })
                        tabInner:AddSlider({
                            label = "Buff Icon Limit",
                            min = 1, max = 32, step = 1,
                            get = function() return htCfg().auraBuffsMax or 16 end,
                            set = function(v) call("SetAuraBuffsMax", v) end,
                        })
                        tabInner:AddToggle({
                            label = "Show Debuffs",
                            description = "On the same side as the buffs, the debuff rows stack beyond them -- buffs always sit closer to the frame. Debuff icons always carry a red border.",
                            get = function() return htCfg().auraDebuffsShow and true or false end,
                            set = function(v) call("SetAuraDebuffsShow", v and "on" or "off") end,
                        })
                        tabInner:AddSlider({
                            label = "Debuff Icon Limit",
                            min = 1, max = 16, step = 1,
                            get = function() return htCfg().auraDebuffsMax or 8 end,
                            set = function(v) call("SetAuraDebuffsMax", v) end,
                        })
                        tabInner:AddDualSelector({
                            label = "Placement",
                            description = "Above or below the frame -- buffs on the left, debuffs on the right.",
                            selectorA = {
                                values = { bottom = "Buffs: Below", top = "Buffs: Above" },
                                order = { "bottom", "top" },
                                get = function() return htCfg().auraBuffsLoc or "bottom" end,
                                set = function(v) call("SetAuraBuffsLoc", v) end,
                            },
                            selectorB = {
                                values = { bottom = "Debuffs: Below", top = "Debuffs: Above" },
                                order = { "bottom", "top" },
                                get = function() return htCfg().auraDebuffsLoc or "bottom" end,
                                set = function(v) call("SetAuraDebuffsLoc", v) end,
                            },
                        })
                        tabInner:AddSlider({
                            label = "Y-Offset",
                            description = "Moves both rows up or down from their snug default position.",
                            min = -60, max = 60, step = 1,
                            get = function() return htCfg().auraOffsetY or 0 end,
                            set = function(v) call("SetAuraOffsetY", v) end,
                        })
                        tabInner:AddToggle({
                            label = "Hover Tooltips",
                            description = "Show the aura's tooltip on mouse-over. Clicks still pass straight through the icons, so click-to-target keeps working across the whole frame.",
                            get = function() return htCfg().auraTooltips and true or false end,
                            set = function(v) call("SetAuraTooltips", v and "on" or "off") end,
                        })
                        tabInner:Finalize()
                    end,
                    sizing = function(cf, tabInner)
                        tabInner:AddSlider({
                            label = "Icon Scale",
                            min = 20, max = 200, step = 5,
                            minLabel = "20%", maxLabel = "200%",
                            get = function() return htCfg().auraIconScale or 100 end,
                            set = function(v) call("SetAuraIconScale", v) end,
                        })
                        tabInner:AddSlider({
                            label = "Icon Shape",
                            description = "Adjust icon aspect ratio. Center = square icons.",
                            min = -67, max = 67, step = 1,
                            minLabel = "Wide", maxLabel = "Tall",
                            get = function() return htCfg().auraTallWideRatio or 0 end,
                            set = function(v) call("SetAuraShape", v) end,
                        })
                        tabInner:Finalize()
                    end,
                    border = function(cf, tabInner)
                        tabInner:AddToggle({
                            label = "Enable Custom Borders",
                            description = "Borders on the buff icons. Debuff icons always keep a red border to mark them as debuffs; the style and thickness below apply to both rows.",
                            get = function() return htCfg().auraBorderEnable and true or false end,
                            set = function(v) call("SetAuraBorderEnable", v and "on" or "off") end,
                        })
                        local UF = addon.UI.UnitFrames
                        local borderValues, borderOrder
                        if UF and UF.buildIconBorderOptions then
                            borderValues, borderOrder = UF.buildIconBorderOptions()
                        else
                            borderValues, borderOrder = { square = "Default (Square)" }, { "square" }
                        end
                        tabInner:AddSelector({
                            label = "Border Style",
                            values = borderValues,
                            order = borderOrder,
                            get = function() return htCfg().auraBorderStyle or "square" end,
                            set = function(v) call("SetAuraBorderStyle", v) end,
                        })
                        tabInner:AddSlider({
                            label = "Border Thickness",
                            min = 1, max = 8, step = 0.5, precision = 1,
                            get = function() return htCfg().auraBorderThickness or 1 end,
                            set = function(v) call("SetAuraBorderThickness", v) end,
                        })
                        tabInner:AddToggleColorPicker({
                            label = "Border Tint",
                            description = "Buff borders only -- debuff borders stay red so a debuff always reads as one.",
                            get = function() return htCfg().auraBorderTintEnable and true or false end,
                            set = function(v) call("SetAuraBorderTint", v and "on" or "off") end,
                            getColor = function()
                                local c = htCfg()
                                return c.auraBorderTintR or 1, c.auraBorderTintG or 1,
                                    c.auraBorderTintB or 1, c.auraBorderTintA or 1
                            end,
                            setColor = function(r, g, b, a) call("SetAuraBorderTintColor", r, g, b, a) end,
                            hasAlpha = true,
                        })
                        tabInner:Finalize()
                    end,
                    filters = function(cf, tabInner)
                        tabInner:AddToggle({
                            label = "Show Only My Buffs",
                            description = "Buff row only: show just the buffs you applied.",
                            get = function() return htCfg().auraOnlyPlayerBuffs and true or false end,
                            set = function(v) call("SetAuraOnlyPlayerBuffs", v and "on" or "off") end,
                        })
                        tabInner:Finalize()
                    end,
                },
            })
            inner:Finalize()
        end,
    })

    -- Player-only, matching the X pages exactly (the X Target page offers no
    -- opacity sliders either -- strict parity, user decision 2026-08-05).
    if opts.unitKey == "Player" then
        builder:AddCollapsibleSection({
            title = "Visibility",
            componentId = opts.componentId,
            sectionKey = "visibility",
            defaultExpanded = false,
            buildContent = function(contentFrame, inner)
                inner:AddSlider({
                    label = "Opacity - Out of Combat",
                    description = "Opacity priority: With Target takes precedence, then In Combat, then Out of Combat. The highest priority condition that applies determines the opacity.",
                    min = 0, max = 100, step = 1,
                    get = function() return htCfg().opacityOutOfCombat or 100 end,
                    set = function(v) call("SetOpacityOutOfCombat", v) end,
                })
                inner:AddSlider({
                    label = "Opacity - In Combat",
                    min = 0, max = 100, step = 1,
                    get = function() return htCfg().opacityInCombat or 100 end,
                    set = function(v) call("SetOpacityInCombat", v) end,
                })
                inner:AddSlider({
                    label = "Opacity - With Target",
                    min = 0, max = 100, step = 1,
                    get = function() return htCfg().opacityWithTarget or 100 end,
                    set = function(v) call("SetOpacityWithTarget", v) end,
                })
                inner:Finalize()
            end,
        })
    end
end

--------------------------------------------------------------------------------
-- Renderers
--------------------------------------------------------------------------------

local PAGES = {
    ufzPlayer = { title = "Player Frame Z", componentId = "ufzPlayer", unitKey = "Player", unitWord = "player" },
    ufzTarget = { title = "Target Frame Z", componentId = "ufzTarget", unitKey = "Target", unitWord = "target" },
}

for key, page in pairs(PAGES) do
    UIPanel:RegisterRenderer(key, function(panel, scrollContent)
        panel:ClearContent()

        local SettingsBuilder = addon.UI.SettingsBuilder
        local builder = SettingsBuilder:CreateFor(scrollContent)
        panel._currentBuilder = builder
        builder:SetOnRefresh(function()
            local render = UIPanel._renderers[key]
            if render then render(panel, scrollContent) end
        end)

        AddUnitSection(builder, page)

        builder:Finalize()
    end)
end
