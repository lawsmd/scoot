--------------------------------------------------------------------------------
-- forever/castbars/page.lua
-- The Cast Bar settings page.
--
-- Laid out after Cast Bar Z's page (ui/v2/settings/castbars/CastBarZRenderer.lua)
-- so a setting both bars have sits in the same section under the same label.
-- Built from single rows: the builder's composite blocks are not on this TOC.
--------------------------------------------------------------------------------

local addonName, addon = ...

local CBZ = addon.CastBarZ
local DB = addon.DB
local SettingsBuilder = addon.UI.SettingsBuilder

local UNIT = "Player"
local SECTION_OWNER = "castBarPlayer"

local SNAP_LABELS = {
    free = "Free (Edit Mode)", above = "Above Frame", below = "Below Frame",
    left = "Left of Frame", right = "Right of Frame",
}

local FRAME_STYLE_LABELS = { classic = "Classic" }
local FRAME_STYLE_ORDER = { "classic" }

local FRAME_COLOR_LABELS = { forever = "Forever", classic = "Classic" }
local FRAME_COLOR_ORDER = { "forever", "classic" }

-- The keys are the engine's (CBZ.CAST_TIME_POSITIONS in casttime.lua); the
-- labels are this page's, because Cast Bar Z offers two of them under shorter
-- names. A local table rather than a catalog: core/catalogs.lua is not on
-- Camelot.toc.
local CAST_TIME_POSITION_LABELS = {
    right = "Right of Bar", left = "Left of Bar",
    above = "Above Bar", below = "Below Bar",
    insideLeft = "Inside Left", insideCenter = "Inside Center", insideRight = "Inside Right",
}
local CAST_TIME_POSITION_ORDER = {
    "right", "left", "above", "below", "insideLeft", "insideCenter", "insideRight",
}

local READOUT_LABELS = { remaining = "Remaining", elapsed = "Elapsed", both = "Elapsed / Total" }
local READOUT_ORDER = { "remaining", "elapsed", "both" }

local function Render(panel, scrollContent)
    panel:ClearContent()
    local builder = SettingsBuilder:CreateFor(scrollContent)
    panel._currentBuilder = builder
    builder:SetOnRefresh(function() Render(panel, scrollContent) end)

    local cfg = CBZ._GetUnitConfig(UNIT)

    local function setSetting(key, value)
        DB.Set("castBars." .. key, value)
        CBZ._Reconcile()
    end
    local function setUnit(key, value)
        cfg[key] = value
        CBZ._Reconcile()
    end

    -- On and off is the Features page (forever/features.lua). The three rows
    -- below sit on the page itself, above the sections.
    builder:AddDualSelector({ label = "Cast Bar Style", wideSlots = true,
        selectorA = { caption = "Frame Style", values = FRAME_STYLE_LABELS, order = FRAME_STYLE_ORDER,
            get = function() return FRAME_STYLE_LABELS[cfg.frameStyle] and cfg.frameStyle or "classic" end,
            set = function(v) setUnit("frameStyle", v) end },
        selectorB = { caption = "Frame Color", values = FRAME_COLOR_LABELS, order = FRAME_COLOR_ORDER,
            get = function() return cfg.frameColor == "classic" and "classic" or "forever" end,
            set = function(v) setUnit("frameColor", v) end } })

    builder:AddSlider({ label = "Cast Bar Scale", min = 50, max = 150, step = 1,
        minLabel = "50%", maxLabel = "150%",
        get = function() return tonumber(cfg.scale) or 100 end,
        set = function(v) setUnit("scale", v) end })

    -- Kept off Builder:AddOffsetPair: width and height are sizes with different ranges, and BuilderComposites.lua is not on Camelot.toc.
    builder:AddDualSlider({ label = "Cast Bar Size",
        sliderA = { axisLabel = "W", min = 100, max = 500, step = 5,
            get = function() return tonumber(cfg.barWidth) or 195 end,
            set = function(v) setUnit("barWidth", v) end },
        sliderB = { axisLabel = "H", min = 8, max = 40, step = 1,
            get = function() return tonumber(cfg.barHeight) or 13 end,
            set = function(v) setUnit("barHeight", v) end } })

    -- Kept off Builder:AddTextStyleBlock: ui/v2/settings/BuilderComposites.lua and Helpers.lua are not on Camelot.toc.
    --
    -- Both strings the bar draws live here, on tabs: the spell name above the
    -- bar, and the readout. Flat, they would stack two Font rows and two Font
    -- Size rows in one column and make the user guess which belongs to which.
    -- Font Style sits on the Spell Name tab and applies to both.
    builder:AddCollapsibleSection({ title = "Text", componentId = SECTION_OWNER, sectionKey = "text", defaultExpanded = false,
        buildContent = function(_, inner)
            inner:AddTabbedSection({
                tabs = {
                    { key = "spellName", label = "Spell Name" },
                    { key = "castTime",  label = "Cast Time" },
                },
                componentId = SECTION_OWNER,
                sectionKey = "textTabs",
                buildContent = {
                    spellName = function(_, tab)
                        tab:AddFontSelector({ label = "Font",
                            get = function() return CBZ._GetSetting("fontFace") or "FRIZQT__" end,
                            set = function(v) setSetting("fontFace", v) end })
                        tab:AddSelector({ label = "Font Style",
                            description = "Shared with the cast time readout, which draws it without the Deep Shadow copy.",
                            values = addon.FontStyles.values, order = addon.FontStyles.orderPaired,
                            get = function() return CBZ._GetSetting("fontStyle") or "SHADOW" end,
                            set = function(v) setSetting("fontStyle", v) end })
                        tab:AddSlider({ label = "Font Size", min = 8, max = 32, step = 1,
                            get = function() return tonumber(CBZ._GetSetting("fontSize")) or 12 end,
                            set = function(v) setSetting("fontSize", v) end })
                        tab:Finalize()
                    end,

                    -- Everything under the toggle draws only while the readout is
                    -- on, the way Position hides its offset sliders on a free bar.
                    castTime = function(_, tab)
                        tab:AddToggle({ label = "Show Cast Time",
                            get = function() return CBZ._GetSetting("castTime") == true end,
                            set = function(v)
                                setSetting("castTime", v)
                                builder:DeferredRefreshAll()
                            end })

                        if CBZ._IsCastTimeEnabled() then
                            tab:AddSelector({ label = "Readout",
                                values = READOUT_LABELS, order = READOUT_ORDER,
                                get = function() return CBZ._GetSetting("castTimeReadout") or "remaining" end,
                                set = function(v) setSetting("castTimeReadout", v) end })
                            -- Kept off Builder:AddTextStyleBlock: the face is inherited, the style shared, and BuilderComposites.lua is not on Camelot.toc.
                            -- No face stored means "follow the spell name", so the
                            -- getter resolves the face in use and the control
                            -- never reads as empty.
                            tab:AddFontSelector({ label = "Font",
                                get = function() return CBZ._GetCastTimeFontFace() or "FRIZQT__" end,
                                set = function(v) setSetting("castTimeFont", v) end })
                            tab:AddSlider({ label = "Font Size", min = 8, max = 24, step = 1,
                                get = function() return tonumber(CBZ._GetSetting("castTimeSize")) or 12 end,
                                set = function(v) setSetting("castTimeSize", v) end })
                            tab:AddSelector({ label = "Position",
                                values = CAST_TIME_POSITION_LABELS, order = CAST_TIME_POSITION_ORDER,
                                get = function() return CBZ._GetCastTimePosition(UNIT) end,
                                set = function(v) setUnit("castTimeSide", v) end })
                            tab:AddColorPicker({ label = "Color", hasAlpha = true,
                                get = function()
                                    local c = CBZ._GetCastTimeColor()
                                    return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
                                end,
                                set = function(r, g, b, a) setSetting("castTimeColor", { r, g, b, a }) end })
                            tab:AddSlider({ label = "Distance From Edge", min = 0, max = 60, step = 1,
                                get = function() return tonumber(CBZ._GetSetting("castTimeGap")) or 10 end,
                                set = function(v) setSetting("castTimeGap", v) end })
                            tab:AddSlider({ label = "Vertical Offset", min = -40, max = 40, step = 1,
                                get = function() return tonumber(CBZ._GetSetting("castTimeOffsetY")) or 0 end,
                                set = function(v) setSetting("castTimeOffsetY", v) end })
                        end
                        tab:Finalize()
                    end,
                },
            })
            inner:Finalize()
        end })

    builder:AddCollapsibleSection({ title = "Position", componentId = SECTION_OWNER, sectionKey = "position", defaultExpanded = false,
        buildContent = function(_, inner)
            inner:AddSelector({ label = "Snap To",
                description = "Free places the bar in Edit Mode. The others attach it to the player frame.",
                values = SNAP_LABELS, order = CBZ.POSITION_MODES,
                get = function() return CBZ._GetPositionMode(UNIT) end,
                set = function(v)
                    setUnit("positionMode", v)
                    builder:DeferredRefreshAll()
                end })
            if CBZ._GetPositionMode(UNIT) ~= "free" then
                inner:AddSlider({ label = "Offset X", min = -200, max = 200, step = 1,
                    get = function() return (CBZ._GetSnapOffsets(UNIT)) end,
                    set = function(v) CBZ._SetSnapOffset(UNIT, "x", v); CBZ._Reconcile() end })
                inner:AddSlider({ label = "Offset Y", min = -200, max = 200, step = 1,
                    get = function() return select(2, CBZ._GetSnapOffsets(UNIT)) end,
                    set = function(v) CBZ._SetSnapOffset(UNIT, "y", v); CBZ._Reconcile() end })
            end
            inner:Finalize()
        end })

    builder:AddCollapsibleSection({ title = "Spark", componentId = SECTION_OWNER, sectionKey = "spark", defaultExpanded = false,
        buildContent = function(_, inner)
            inner:AddToggle({ label = "Show Spark",
                description = "The glow that rides the leading edge of the fill.",
                get = function() return CBZ._GetSetting("showSpark") ~= false end,
                set = function(v) setSetting("showSpark", v) end })
            inner:Finalize()
        end })

    builder:Finalize()
end

addon.UI.SettingsPanel:RegisterRenderer("castBarPlayer", function(panel, scrollContent)
    Render(panel, scrollContent)
end)
