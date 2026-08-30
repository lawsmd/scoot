-- CastBarZRenderer.lua - Cast Bar Z settings page
local _, addon = ...

addon.UI = addon.UI or {}
addon.UI.Settings = addon.UI.Settings or {}
addon.UI.Settings.CastBarZ = {}

local CBZSettings = addon.UI.Settings.CastBarZ
local SettingsBuilder = addon.UI.SettingsBuilder
local CBZ = addon.CastBarZ

local selectedUnit = "Player"

-- Panel state, deliberately not a saved setting: it changes what the PREVIEW
-- shows, not what the HUD draws, and a preview mode that survived /reload would
-- be a puzzle rather than a convenience. Same scope as selectedUnit.
local previewEmpowered = false

local function GetTheme() return addon.UI and addon.UI.Theme end

--------------------------------------------------------------------------------
-- Preview Pane
--------------------------------------------------------------------------------
-- Departure from every other Scoot preview, which render once and stay static.
-- A cast bar's whole point is the sweep, so this one animates on a
-- loop. The pane builds a real Cast Bar Z frame through CBZ._CreatePreviewBar and
-- lays it out with the same CBZ._LayoutBar the HUD uses, so it cannot drift from
-- what the live bar draws.
--
-- The one thing it does NOT share is the clock: SetTimerDuration needs a real
-- LuaDurationObject from a real cast. The preview drives progressBar:SetValue
-- directly, which is only possible because nothing here is secret.

local PREVIEW_LOOP_SECONDS = 5
local PREVIEW_TICK = 0.02
local PREVIEW_PAD = 14

--- The cast time readout, formatted by hand for the preview only.
---
--- The live bar hands its FontString to a C_DurationUtil binding, which needs a
--- real LuaDurationObject from a real cast. The preview has none -- the same
--- reason it drives progressBar:SetValue directly instead of SetTimerDuration --
--- so it formats the number itself. This is the one place the preview's mechanism
--- deviates from the HUD's; the breakpoints deliberately match casttime.lua's, so
--- what it shows is still what the bar will show.
local function PreviewCastTimeText(elapsed, total)
    local mode = CBZ._GetSetting("castTimeReadout") or "remaining"
    -- Empowered fills rather than drains, so it counts up whatever the setting is.
    if previewEmpowered and mode == "remaining" then mode = "elapsed" end

    local function fmt(v)
        if v >= 10 then return string.format("%.0f", v) end
        return string.format("%.1f", v)
    end

    if mode == "both" then return fmt(elapsed) .. " / " .. fmt(total) end
    if mode == "elapsed" then return fmt(elapsed) end
    return fmt(math.max(0, total - elapsed))
end

local function CreatePreviewPane(parentFrame, builder)
    local Theme = GetTheme()

    local pane = CreateFrame("Frame", nil, parentFrame)

    local bg = pane:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(pane)
    bg:SetColorTexture(0.06, 0.06, 0.08, 0.6)

    local label = pane:CreateFontString(nil, "OVERLAY")
    if Theme and Theme.ApplyValueFont then Theme:ApplyValueFont(label, 10)
    else label:SetFont("Fonts\\FRIZQT__.TTF", 10, "") end
    label:SetPoint("TOPLEFT", pane, "TOPLEFT", 8, -6)
    label:SetText("Preview")
    label:SetTextColor(0.6, 0.6, 0.6, 1)

    -- Bar height is driven by cap size and font size, so the pane grows with them
    -- rather than clipping a large font against a fixed box.
    local barWidth = 260
    local barHeight = math.max(CBZ._GetCapSize(), (tonumber(CBZ._GetSetting("fontSize")) or 14) + 2)
    local paneHeight = math.max(72, barHeight + 2 * PREVIEW_PAD + 24)

    -- nil only if the selected unit has no bar row, which means CBZ.UNITS and
    -- CBZ.BARS have drifted apart. Return the empty pane rather than erroring
    -- inside the settings panel.
    local bar = CBZ._CreatePreviewBar(pane, selectedUnit, barWidth)
    if not bar then
        pane:SetHeight(paneHeight)
        -- Builder:Clear() calls Cleanup() on every registered control
        -- unconditionally, so the empty pane still needs one.
        pane.Cleanup = function() end
        return pane, paneHeight
    end

    bar:SetPoint("CENTER", pane, "CENTER", 0, -6)
    CBZ._LayoutBar(bar)
    CBZ._ApplyBandFonts(bar)
    local line = CBZ._ResolveLineColor(selectedUnit)
    CBZ._ApplyLineColor(bar, line[1], line[2], line[3])
    CBZ._SetText(bar, CBZ.PREVIEW_SPELL_NAME)
    CBZ._SetStaticProgress(bar, 0)

    -- Empowered preview. Synthetic stages, because UnitEmpoweredStagePercentages
    -- only answers during a live empowered channel -- and because this is the only
    -- way anyone who is not currently playing an Evoker ever sees the tier palette
    -- they are being asked to have an opinion about.
    --
    -- bar.empowered is set as well as the preview flag so the spark override
    -- applies here too; the preview is meant to look like the real thing, and the
    -- spark riding across the dividers is most of what an empowered bar IS.
    if previewEmpowered and CBZ._GetSetting("empoweredTiers") ~= false then
        bar.empowerPreview = true
        bar.empowered = true
        CBZ._ApplyEmpowered(bar, true)
        CBZ._ApplyEmpoweredColors(bar, false)
        CBZ._RefreshSparkVisibility(bar)
    end

    -- _LayoutBar has already placed and styled the readout; it starts hidden, and
    -- only the preview's own ticker ever fills it.
    local castTimeFS = CBZ._IsCastTimeEnabled() and bar.castTimeText or nil
    if castTimeFS then
        castTimeFS:SetText(PreviewCastTimeText(0, PREVIEW_LOOP_SECONDS))
        castTimeFS:Show()
    end

    bar:Show()

    pane:SetHeight(paneHeight)

    ----------------------------------------------------------------------------
    -- Animation
    ----------------------------------------------------------------------------
    -- Two independent stops, because a ticker that outlives the panel keeps a
    -- destroyed frame alive and repaints into nothing:
    --   * Builder:Clear() calls Cleanup() on every registered control before each
    --     rebuild (SettingsBuilder.lua:65-77)
    --   * OnHide covers the panel being closed without a rebuild
    -- SetValue directly rather than _SetStaticProgress: the min/max were already
    -- established above and re-sending them 50 times a second buys nothing.
    local elapsed = 0
    bar.ticker = C_Timer.NewTicker(PREVIEW_TICK, function()
        elapsed = elapsed + PREVIEW_TICK
        if elapsed > PREVIEW_LOOP_SECONDS then
            elapsed = 0
            -- The loop wrapping is the preview's "cast completed" moment, so it
            -- is where the completion effect belongs. Without this the effect is
            -- the one setting with no preview, and the only way to judge it is to
            -- close the panel and cast something.
            CBZ._PlayFinishFX(bar)
        end
        bar.progressBar:SetValue(elapsed / PREVIEW_LOOP_SECONDS)
        if castTimeFS then
            castTimeFS:SetText(PreviewCastTimeText(elapsed, PREVIEW_LOOP_SECONDS))
        end
    end)

    local function StopTicker()
        if bar.ticker then
            bar.ticker:Cancel()
            bar.ticker = nil
        end
        CBZ._StopFinishFX(bar)
    end

    pane.Cleanup = StopTicker
    pane:SetScript("OnHide", StopTicker)

    return pane, paneHeight
end

--------------------------------------------------------------------------------
-- ON/OFF Indicator
--------------------------------------------------------------------------------

local function CreateOnOffIndicator(parent, isOn, onClick)
    local Theme = GetTheme()
    local ar, ag, ab = 0.2, 0.9, 0.3
    if Theme and Theme.GetAccentColor then ar, ag, ab = Theme:GetAccentColor() end
    local dimR, dimG, dimB = 0.6, 0.6, 0.6
    if Theme and Theme.GetDimTextColor then dimR, dimG, dimB = Theme:GetDimTextColor() end

    local indicator = CreateFrame("Button", nil, parent)
    indicator:SetSize(50, 22)

    local bw = 2
    for _, info in ipairs({
        { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true },
        { "TOPLEFT", "BOTTOMLEFT", false }, { "TOPRIGHT", "BOTTOMRIGHT", false },
    }) do
        local t = indicator:CreateTexture(nil, "BORDER", nil, -1)
        t:SetPoint(info[1]); t:SetPoint(info[2])
        if info[3] then t:SetHeight(bw) else t:SetWidth(bw) end
        t:SetColorTexture(ar, ag, ab, 1)
    end

    local fill = indicator:CreateTexture(nil, "BACKGROUND", nil, -7)
    fill:SetPoint("TOPLEFT", bw, -bw); fill:SetPoint("BOTTOMRIGHT", -bw, bw)
    fill:SetColorTexture(ar, ag, ab, 1)

    local text = indicator:CreateFontString(nil, "OVERLAY")
    if Theme and Theme.GetFont then
        text:SetFont(Theme:GetFont("BUTTON"), 10, "")
    else
        text:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    end
    text:SetPoint("CENTER")

    if isOn then
        fill:Show(); text:SetText("ON"); text:SetTextColor(0, 0, 0, 1)
    else
        fill:Hide(); text:SetText("OFF"); text:SetTextColor(dimR, dimG, dimB, 1)
    end

    if onClick then indicator:SetScript("OnClick", onClick) end
    return indicator
end

--------------------------------------------------------------------------------
-- Unit Selector Row
--------------------------------------------------------------------------------

-- Two stacked rows: the unit tabs, and the selected unit's ON/OFF directly beneath
-- the tab it belongs to. Side by side (the original layout) the toggle read as a
-- page-level switch, which is exactly what it is not -- every unit carries its own.
-- Parking it under the selected tab makes it move as you change unit, and that
-- movement is the point: it says what it applies to without a label.
local UNIT_BTN_H     = 22
local UNIT_ROW_PAD   = 3
local UNIT_TOGGLE_GAP = 6
local UNIT_ROW_HEIGHT = UNIT_ROW_PAD + UNIT_BTN_H + UNIT_TOGGLE_GAP + UNIT_BTN_H + UNIT_ROW_PAD

local function CreateUnitSelector(parentFrame, builder)
    local row = CreateFrame("Frame", nil, parentFrame)
    row:SetHeight(UNIT_ROW_HEIGHT)

    local Theme = GetTheme()
    local ar, ag, ab = 0.2, 0.9, 0.3
    if Theme and Theme.GetAccentColor then ar, ag, ab = Theme:GetAccentColor() end

    -- Where the selected tab sits, so the toggle can be centred under it.
    local selX, selW = 4, 50

    local x = 4
    for _, unitKey in ipairs(CBZ.UNITS) do
        local label = CBZ.UNIT_LABELS[unitKey] or unitKey
        local isSel = (unitKey == selectedUnit)
        local width = math.max(48, 12 + #label * 7)
        if isSel then selX, selW = x, width end

        local btn = CreateFrame("Button", nil, row)
        btn:SetSize(width, UNIT_BTN_H)
        btn:SetPoint("TOPLEFT", row, "TOPLEFT", x, -UNIT_ROW_PAD)
        x = x + width + 4

        local btnBg = btn:CreateTexture(nil, "BACKGROUND")
        btnBg:SetAllPoints()
        btnBg:SetColorTexture(isSel and ar or 0.15, isSel and ag or 0.15,
            isSel and ab or 0.18, isSel and 0.3 or 1)

        local fs = btn:CreateFontString(nil, "OVERLAY")
        if Theme and Theme.ApplyValueFont then Theme:ApplyValueFont(fs, 11)
        else fs:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE") end
        fs:SetPoint("CENTER"); fs:SetText(label)
        fs:SetTextColor(isSel and ar or 0.6, isSel and ag or 0.6, isSel and ab or 0.6, 1)

        local bw = 1
        local bc = isSel and { ar, ag, ab, 0.6 } or { 0.3, 0.3, 0.35, 0.5 }
        for _, s in ipairs({ "TOP", "BOTTOM" }) do
            local t = btn:CreateTexture(nil, "BORDER")
            t:SetPoint(s .. "LEFT"); t:SetPoint(s .. "RIGHT"); t:SetHeight(bw)
            t:SetColorTexture(bc[1], bc[2], bc[3], bc[4])
        end
        for _, s in ipairs({ "LEFT", "RIGHT" }) do
            local t = btn:CreateTexture(nil, "BORDER")
            t:SetPoint("TOP" .. s); t:SetPoint("BOTTOM" .. s); t:SetWidth(bw)
            t:SetColorTexture(bc[1], bc[2], bc[3], bc[4])
        end

        btn:SetScript("OnClick", function()
            selectedUnit = unitKey
            -- Mirrored onto the panel so an Edit Mode deep link can preselect a
            -- unit, the same way _damageMeterYSelectedWindow works.
            addon.UI.SettingsPanel._castBarZSelectedUnit = unitKey
            if builder then builder:DeferredRefreshAll() end
        end)
    end

    local cfg = CBZ._GetUnitConfig(selectedUnit)
    local indicator = CreateOnOffIndicator(row, cfg and cfg.enabled, function()
        if cfg then
            cfg.enabled = not cfg.enabled
            if CBZ._comp then CBZ._ApplyStyling(CBZ._comp) end
            if builder then builder:DeferredRefreshAll() end
        end
    end)

    -- Widened to the tab above when that tab is wider, so the two read as one
    -- column rather than as a button that happens to be nearby. Floored at the
    -- indicator's own 50 so "OFF" never crowds its border.
    local indW = math.max(50, selW)
    indicator:SetWidth(indW)
    -- Floored: a half-pixel offset on a 1px border draws it at two weights on
    -- opposite sides of the button (subpixel-font-outline).
    indicator:SetPoint("TOPLEFT", row, "TOPLEFT",
        selX + math.floor((selW - indW) / 2), -(UNIT_ROW_PAD + UNIT_BTN_H + UNIT_TOGGLE_GAP))

    return row, UNIT_ROW_HEIGHT
end

--------------------------------------------------------------------------------
-- Main Renderer
--------------------------------------------------------------------------------

function CBZSettings.Render(panel, scrollContent)
    selectedUnit = panel._castBarZSelectedUnit or selectedUnit
    if not CBZ._GetUnitConfig(selectedUnit) then
        selectedUnit = CBZ.UNITS[1]
    end

    panel:ClearContent()
    local builder = SettingsBuilder:CreateFor(scrollContent)
    panel._currentBuilder = builder
    builder:SetOnRefresh(function() CBZSettings.Render(panel, scrollContent) end)

    local Helpers = addon.UI.Settings.Helpers
    local h = Helpers.CreateComponentHelpers("castBarZ")
    local getSetting = h.get

    -- Every visual setter refreshes the panel, which rebuilds the preview with
    -- the new value: setters call DeferredRefreshAll after the write.
    local function setSetting(key, value)
        h.setAndApply(key, value)
        if CBZ._comp then CBZ._ApplyStyling(CBZ._comp) end
        builder:DeferredRefreshAll()
    end

    local function getUnit(key, default)
        local cfg = CBZ._GetUnitConfig(selectedUnit)
        local v = cfg and cfg[key]
        if v == nil then return default end
        return v
    end
    local function setUnit(key, value)
        local cfg = CBZ._GetUnitConfig(selectedUnit)
        if cfg then cfg[key] = value end
        if CBZ._comp then CBZ._ApplyStyling(CBZ._comp) end
        builder:DeferredRefreshAll()
    end

    ----------------------------------------------------------------------------
    -- Unit selector
    ----------------------------------------------------------------------------
    local sel, selHeight = CreateUnitSelector(scrollContent, builder)
    sel:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", 12, -8)
    sel:SetPoint("TOPRIGHT", scrollContent, "TOPRIGHT", -12, -8)
    table.insert(builder._controls, sel)
    builder._currentY = -8 - selHeight - 8

    ----------------------------------------------------------------------------
    -- Preview
    ----------------------------------------------------------------------------
    if CBZ._comp then
        local pane, ph = CreatePreviewPane(scrollContent, builder)
        if pane then
            pane:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", 12, builder._currentY)
            pane:SetPoint("TOPRIGHT", scrollContent, "TOPRIGHT", -12, builder._currentY)
            table.insert(builder._controls, pane)
            builder._currentY = builder._currentY - ph - 8
        end
    end

    ----------------------------------------------------------------------------
    -- Sections
    ----------------------------------------------------------------------------

    -- Stated rather than offered as a toggle. Two bars drawing the same cast is
    -- not a configuration, so the only thing left to do is say so before the user
    -- goes looking for the switch.
    builder:AddDescription(
        "Blizzard's own cast bar is hidden for every unit switched on above, in Edit Mode as well as in play, and comes back the moment one is switched off.")

    builder:AddCollapsibleSection({ title = "Bar", componentId = "castBarZ", sectionKey = "bar", defaultExpanded = true,
        infoIcon = {
            tooltipTitle = "Per-Unit Setting",
            tooltipText = "Width applies only to the selected unit. Everything below the Bar section applies to every cast bar.",
        },
        buildContent = function(_, inner)
            inner:AddSlider({ label = "Bar Width", min = 100, max = 500, step = 5,
                get = function() return getUnit("barWidth", 260) end,
                set = function(v) setUnit("barWidth", v) end })
            inner:AddSelector({ label = "Line Thickness",
                values = { thin = "Thin", medium = "Medium", thick = "Thick" },
                order = { "thin", "medium", "thick" },
                get = function() return getSetting("lineHeight") or "medium" end,
                set = function(v) setSetting("lineHeight", v) end })
            inner:AddSelector({ label = "End Tick Height",
                values = { short = "Short", medium = "Medium", tall = "Tall" },
                order = { "short", "medium", "tall" },
                get = function() return getSetting("capSize") or "medium" end,
                set = function(v) setSetting("capSize", v) end })
            inner:Finalize()
        end })

    ----------------------------------------------------------------------------
    -- Position
    ----------------------------------------------------------------------------
    -- Per-unit, like Bar Width. Boss is the one unit with no Free entry: a floating
    -- boss bar cannot say which boss it belongs to. Hiding it here is presentation
    -- only -- CBZ._GetPositionMode coerces the value itself, so a profile that
    -- somehow holds "free" for Boss still renders snapped.
    local snapOnly = CBZ._IsSnapOnly(selectedUnit)

    builder:AddCollapsibleSection({ title = "Position", componentId = "castBarZ", sectionKey = "position", defaultExpanded = false,
        infoIcon = {
            tooltipTitle = "Per-Unit Setting",
            tooltipText = "Position applies only to the selected unit.",
        },
        buildContent = function(_, inner)
            local values = {
                above = "Above Frame", below = "Below Frame",
                left  = "Left of Frame", right = "Right of Frame",
            }
            local order = { "above", "below", "left", "right" }
            if not snapOnly then
                values.free = "Free"
                table.insert(order, 1, "free")
            end

            inner:AddSelector({ label = "Snap To",
                description = snapOnly
                    and "Boss cast bars are always attached to their boss frame, so they can be told apart."
                    or "Free lets you drag the bar anywhere in Edit Mode. The others attach it to this unit's frame, and it follows when that frame moves.",
                values = values, order = order,
                get = function() return CBZ._GetPositionMode(selectedUnit) end,
                set = function(v) setUnit("positionMode", v) end })

            -- Offsets are meaningless on a free bar, which is positioned by
            -- dragging. Each (direction, X/Z frame variant) combination keeps
            -- its own remembered pair -- these sliders read and write the pair
            -- currently in effect (CBZ._GetSnapOffsets resolves it).
            if CBZ._GetPositionMode(selectedUnit) ~= "free" then
                local function setOffset(axis, v)
                    CBZ._SetSnapOffset(selectedUnit, axis, v)
                    if CBZ._comp then CBZ._ApplyStyling(CBZ._comp) end
                    builder:DeferredRefreshAll()
                end
                inner:AddSlider({ label = "Offset X", min = -200, max = 200, step = 1,
                    description = "Remembered separately for each snap direction, and for the X and Z unit frames.",
                    get = function() return (CBZ._GetSnapOffsets(selectedUnit)) end,
                    set = function(v) setOffset("x", v) end })
                inner:AddSlider({ label = "Offset Y", min = -200, max = 200, step = 1,
                    get = function() return select(2, CBZ._GetSnapOffsets(selectedUnit)) end,
                    set = function(v) setOffset("y", v) end })
            end
            inner:Finalize()
        end })

    ----------------------------------------------------------------------------
    -- Spark and Cast Completion
    ----------------------------------------------------------------------------
    -- The bar's two flourishes, adjacent because they now share a Color row built
    -- the same way. Both offer exactly two modes: there is no third "Default"
    -- entry because there is no single behaviour it could name -- Blizzard's pip
    -- draws in its own gold and the other three sparks draw in the cast's ramp, so
    -- one option covering both would mean two different things depending on the
    -- style selected above it.
    -- The stored key stays "spellName" while the label reads "Spec Color". Only the
    -- label changed; the key is what a profile already holds,
    -- and it still describes what the value resolves through.
    local COLOR_VALUES = { spellName = "Spec Color", custom = "Custom" }
    local COLOR_ORDER  = { "spellName", "custom" }

    local COLOR_DESC = "Takes the brightest stop of the gradient the spell name is drawn in: your specialization's on your own bar, the unit's class color on someone else's."

    builder:AddCollapsibleSection({ title = "Spark", componentId = "castBarZ", sectionKey = "spark", defaultExpanded = false,
        buildContent = function(_, inner)
            inner:AddToggle({ label = "Show Spark",
                description = "The moving pip that rides the leading edge of the fill.",
                get = function() return getSetting("showSpark") ~= false end,
                set = function(v) setSetting("showSpark", v) end })
            inner:AddSelector({ label = "Spark Style",
                description = "Third Tick matches the end ticks. Ember Trail replaces the pip with a glow along the line. Playhead Caret brackets the line above and below.",
                values = {
                    blizzard = "Blizzard Pip",
                    tick     = "Third Tick",
                    trail    = "Ember Trail",
                    caret    = "Playhead Caret",
                },
                order = { "blizzard", "tick", "trail", "caret" },
                get = function() return getSetting("sparkStyle") or "caret" end,
                set = function(v) setSetting("sparkStyle", v) end })
            -- No alpha on either picker. On the completion effects the alpha is
            -- already driven by the animation, so a vertex alpha would multiply
            -- into it and read as a dimmer effect rather than a transparent one.
            inner:AddSelectorColorPicker({ label = "Color", hasAlpha = false,
                description = COLOR_DESC,
                values = COLOR_VALUES, order = COLOR_ORDER,
                get = function() return getSetting("sparkColorMode") or "spellName" end,
                set = function(v) setSetting("sparkColorMode", v or "spellName") end,
                getColor = function()
                    local c = getSetting("sparkColor")
                    if type(c) ~= "table" then return 1, 1, 1, 1 end
                    return c[1] or 1, c[2] or 1, c[3] or 1, 1
                end,
                setColor = function(r, g, b) setSetting("sparkColor", { r, g, b, 1 }) end })
            inner:Finalize()
        end })

    builder:AddCollapsibleSection({ title = "Cast Completion", componentId = "castBarZ", sectionKey = "completion", defaultExpanded = false,
        buildContent = function(_, inner)
            inner:AddSelector({ label = "Completion Effect",
                description = "Plays when a cast finishes successfully. Interrupted and failed casts keep their red flash regardless.",
                values = {
                    none   = "None",
                    glow   = "Success Glow",
                    sweep  = "Wisp Sweep",
                    wipe   = "Shine Wipe",
                    embers = "Rising Embers",
                },
                order = { "none", "glow", "sweep", "wipe", "embers" },
                get = function() return getSetting("completionFX") or "glow" end,
                set = function(v) setSetting("completionFX", v) end })
            -- Hidden with the effect off, matching how Position hides its offsets on
            -- a free bar: a color for something that does not play is noise.
            if (getSetting("completionFX") or "glow") ~= "none" then
                inner:AddSelectorColorPicker({ label = "Color", hasAlpha = false,
                    description = COLOR_DESC,
                    values = COLOR_VALUES, order = COLOR_ORDER,
                    get = function() return getSetting("completionColorMode") or "spellName" end,
                    set = function(v) setSetting("completionColorMode", v or "spellName") end,
                    getColor = function()
                        local c = getSetting("completionColor")
                        if type(c) ~= "table" then return 1, 1, 1, 1 end
                        return c[1] or 1, c[2] or 1, c[3] or 1, 1
                    end,
                    setColor = function(r, g, b) setSetting("completionColor", { r, g, b, 1 }) end })
            end
            inner:Finalize()
        end })

    ----------------------------------------------------------------------------
    -- Empowered
    ----------------------------------------------------------------------------
    -- Evoker-only in practice, so the section stays collapsed and carries its own
    -- preview switch -- otherwise it is a feature nobody can see the effect of
    -- while they are configuring it.
    builder:AddCollapsibleSection({ title = "Empowered Casts", componentId = "castBarZ", sectionKey = "empowered", defaultExpanded = false,
        buildContent = function(_, inner)
            inner:AddToggle({ label = "Tier Segments",
                description = "Split the line into the cast's empower tiers, green through red, with a divider at each boundary. The last divider marks where maximum tier is reached. Off draws a plain filling bar.",
                get = function() return getSetting("empoweredTiers") ~= false end,
                set = function(v) setSetting("empoweredTiers", v) end })
            inner:AddToggle({ label = "Preview Empowered Cast",
                description = "Draws the preview above as an empowered cast. Affects this panel only, and is not saved.",
                get = function() return previewEmpowered end,
                set = function(v)
                    previewEmpowered = (v == true)
                    builder:DeferredRefreshAll()
                end })
            inner:Finalize()
        end })

    ----------------------------------------------------------------------------
    -- Text
    ----------------------------------------------------------------------------
    -- Both strings a Cast Bar Z draws live here, on tabs: the spell name across
    -- the bar, and the numeric readout beside it. They are separate tabs rather
    -- than one flat list because they share a Font Style and nothing else -- two
    -- "Font" and two "Font Size" rows stacked in one column would be a guessing
    -- game about which belongs to which.
    --
    -- Font Style is deliberately on the Spell Name tab alone and applies to both.
    -- Duplicating it would invite a readout in a different weight to the name
    -- beside it, which reads as a rendering fault rather than a choice.
    builder:AddCollapsibleSection({ title = "Text", componentId = "castBarZ", sectionKey = "text", defaultExpanded = false,
        buildContent = function(_, inner)
            local TextHelpers = addon.UI.Settings.Helpers

            inner:AddTabbedSection({
                tabs = {
                    { key = "spellName", label = "Spell Name" },
                    { key = "castTime",  label = "Cast Time" },
                },
                componentId = "castBarZ",
                sectionKey = "textTabs",
                buildContent = {
                    spellName = function(_, tab)
                        tab:AddFontSelector({ label = "Font",
                            get = function() return getSetting("fontFace") or "ROBOTO_SEMICOND_BLACK" end,
                            set = function(v) setSetting("fontFace", v) end })
                        tab:AddSelector({ label = "Font Style",
                            description = "Shared with the cast time readout, so the two cannot disagree about weight.",
                            values = TextHelpers.fontStyleValues, order = TextHelpers.fontStyleOrderPaired,
                            get = function() return getSetting("fontStyle") or "SHADOWTHICKOUTLINE" end,
                            set = function(v) setSetting("fontStyle", v) end })
                        tab:AddSlider({ label = "Font Size", min = 8, max = 32, step = 1,
                            get = function() return tonumber(getSetting("fontSize")) or 14 end,
                            set = function(v) setSetting("fontSize", v) end })
                        tab:AddToggle({ label = "Gradient",
                            description = "Ramp the spell name across your specialization's colors. Off uses a single solid color.",
                            get = function() return getSetting("gradient") ~= false end,
                            set = function(v) setSetting("gradient", v) end })
                        tab:Finalize()
                    end,

                    -- Everything below the toggle is hidden while the readout is
                    -- off, matching how Position hides its offset sliders on a
                    -- free bar: six controls for a feature that is not on is
                    -- noise, not configurability.
                    castTime = function(_, tab)
                        tab:AddToggle({ label = "Show Cast Time",
                            description = "A live readout beside the bar, updated every frame by the game itself. Empowered casts always count up, matching the way their bar fills.",
                            get = function() return getSetting("castTime") == true end,
                            set = function(v) setSetting("castTime", v) end })

                        if CBZ._IsCastTimeEnabled() then
                            tab:AddSelector({ label = "Readout",
                                description = "Remaining counts down to zero. Elapsed counts up from zero. Both shows elapsed and total together.",
                                values = { remaining = "Remaining", elapsed = "Elapsed", both = "Both" },
                                order = { "remaining", "elapsed", "both" },
                                get = function() return getSetting("castTimeReadout") or "remaining" end,
                                set = function(v) setSetting("castTimeReadout", v) end })
                            -- Follows the Spell Name font until you pick one here,
                            -- which is what an untouched profile does. The getter
                            -- shows the face in use either way, so the
                            -- control never reads as empty.
                            tab:AddFontSelector({ label = "Font",
                                description = "Matches the spell name font until you choose one here.",
                                get = function() return CBZ._GetCastTimeFontFace() or "ROBOTO_SEMICOND_BLACK" end,
                                set = function(v) setSetting("castTimeFont", v) end })
                            tab:AddSlider({ label = "Font Size", min = 8, max = 24, step = 1,
                                get = function() return tonumber(getSetting("castTimeSize")) or 12 end,
                                set = function(v) setSetting("castTimeSize", v) end })
                            tab:AddSelector({ label = "Side",
                                description = "Which end of the bar the number sits beside. Applies to the selected unit only. Boss defaults to the left, so the readout clears the boss frame its bar attaches to.",
                                values = { right = "Right", left = "Left" },
                                order = { "right", "left" },
                                get = function() return CBZ._GetCastTimeSide(selectedUnit) end,
                                set = function(v) setUnit("castTimeSide", v) end })
                            tab:AddColorPicker({ label = "Color", hasAlpha = true,
                                get = function()
                                    local c = CBZ._GetCastTimeColor()
                                    return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
                                end,
                                set = function(r, g, b, a) setSetting("castTimeColor", { r, g, b, a }) end })
                            tab:AddSlider({ label = "Gap", min = 0, max = 60, step = 1,
                                description = "Distance from the end of the bar.",
                                get = function() return tonumber(getSetting("castTimeGap")) or 10 end,
                                set = function(v) setSetting("castTimeGap", v) end })
                            tab:AddSlider({ label = "Vertical Offset", min = -40, max = 40, step = 1,
                                get = function() return tonumber(getSetting("castTimeOffsetY")) or 0 end,
                                set = function(v) setSetting("castTimeOffsetY", v) end })
                        end
                        tab:Finalize()
                    end,
                },
            })

            inner:Finalize()
        end })

    builder:Finalize()
end

addon.UI.SettingsPanel:RegisterRenderer("castBarZ", function(panel, scrollContent)
    CBZSettings.Render(panel, scrollContent)
end)
