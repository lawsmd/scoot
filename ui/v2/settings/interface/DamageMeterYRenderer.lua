-- DamageMeterYRenderer.lua - Damage Meters Y settings renderer
local _, addon = ...

addon.UI = addon.UI or {}
addon.UI.Settings = addon.UI.Settings or {}
addon.UI.Settings.DamageMetersY = {}

local DMYSettings = addon.UI.Settings.DamageMetersY
local SettingsBuilder = addon.UI.SettingsBuilder
local DMY = addon.DamageMetersY

local selectedWindow = 1

local function GetTheme() return addon.UI and addon.UI.Theme end
local function GetControls() return addon.UI and addon.UI.Controls end

local function ResolveFont(key)
    if addon.ResolveFontFace then return addon.ResolveFontFace(key or "ROBOTO_SEMICOND_BOLD") end
    return "Fonts\\FRIZQT__.TTF"
end

--------------------------------------------------------------------------------
-- Fake preview data (sorted by DPS descending)
--------------------------------------------------------------------------------

local PREVIEW_PLAYERS = {
    { name = "Scooter",    classFilename = "MAGE",    dps = 48200, damage = 1580000, deaths = 0 },
    { name = "Theodesius", classFilename = "WARRIOR",  dps = 45100, damage = 1478000, deaths = 0 },
    { name = "Sniggles",   classFilename = "WARLOCK",  dps = 38900, damage = 1274000, deaths = 1 },
    { name = "Aetheris",   classFilename = "PALADIN",  dps = 31800, damage = 1042000, deaths = 0 },
    { name = "Ikealtea",   classFilename = "SHAMAN",   dps = 24500, damage = 803000,  deaths = 0 },
}

local PREVIEW_HEADER_HEIGHT = 28
local PREVIEW_BAR_HEIGHT = 20
local PREVIEW_BAR_SPACING = 2
local PREVIEW_ICON_SIZE = 18
local PREVIEW_NAME_WIDTH = 80
local PREVIEW_PADDING = 6
local PREVIEW_THIN_BAR_HEIGHT = 4

--------------------------------------------------------------------------------
-- Metric dropdown values
--------------------------------------------------------------------------------

local function BuildMetricDropdownValues()
    local values, order = {}, {}
    if DMY and DMY.COLUMN_FORMATS then
        for key, def in pairs(DMY.COLUMN_FORMATS) do
            values[key] = def.headerText
            table.insert(order, key)
        end
        table.sort(order, function(a, b)
            return DMY.COLUMN_FORMATS[a].headerText < DMY.COLUMN_FORMATS[b].headerText
        end)
    end
    return values, order
end

-- Returns numeric value for bar fill (primary metric)
local function GetPlayerValue(player, formatKey)
    local map = {
        dps = player.dps, damage = player.damage, deaths = player.deaths,
        hps = math.floor(player.dps * 0.4), healing = math.floor(player.damage * 0.3),
        heal_hps = math.floor(player.damage * 0.3), hps_heal = math.floor(player.dps * 0.4),
        dmg_dps = player.damage, dps_dmg = player.dps,
        interrupts = math.max(0, 3 - player.deaths), dispels = math.max(0, 2 - player.deaths),
        absorbs = math.floor(player.damage * 0.1),
        dmgTaken = math.floor(player.damage * 0.15), avoidable = math.floor(player.damage * 0.05),
        enemyDmg = math.floor(player.damage * 0.8),
    }
    return map[formatKey] or player.dps
end

-- Returns formatted display string (handles combo formats like "1.2M (45.3K)")
local function FormatPlayerValue(player, formatKey)
    local fmt = DMY and DMY._FormatCompact
    if not fmt then return "" end
    local def = DMY and DMY.COLUMN_FORMATS and DMY.COLUMN_FORMATS[formatKey]
    if not def then return fmt(GetPlayerValue(player, formatKey)) end

    if def.primary then
        -- Combo format
        local pVal = GetPlayerValue(player, formatKey)
        local sMap = {
            dmg_dps = player.dps, dps_dmg = player.damage,
            heal_hps = math.floor(player.dps * 0.4), hps_heal = math.floor(player.damage * 0.3),
        }
        local sVal = sMap[formatKey] or 0
        return fmt(pVal) .. " (" .. fmt(sVal) .. ")"
    end
    return fmt(GetPlayerValue(player, formatKey))
end

--------------------------------------------------------------------------------
-- Preview Pane
--------------------------------------------------------------------------------

local function CreatePreviewPane(parentFrame, comp, windowIndex, builder)
    local db = comp and comp.db
    if not db then return nil, 0 end

    local cfg = DMY and DMY._GetWindowConfig and DMY._GetWindowConfig(windowIndex)
    local columns = cfg and cfg.columns or { { format = "dps" } }
    local numColumns = math.min(#columns, 5)
    if cfg and cfg.sessionType ~= 0 then numColumns = 1 end  -- Current/Expired: show only primary
    local Controls = GetControls()
    local Theme = GetTheme()
    local ar, ag, ab = 0.2, 0.9, 0.3
    if Theme and Theme.GetAccentColor then ar, ag, ab = Theme:GetAccentColor() end

    -- Resolved the same way the live window resolves them, so a partially
    -- stored group (or a fresh Zero-Touch profile that stores nothing) previews
    -- exactly what the HUD will render.
    local fontNames = addon:ResolveComponentSubTable(comp, "textNames") or {}
    local fontValues = addon:ResolveComponentSubTable(comp, "textValues") or {}
    local nameFontPath = ResolveFont(fontNames.fontFace)
    local valueFontPath = ResolveFont(fontValues.fontFace)

    local totalHeight = PREVIEW_HEADER_HEIGHT + (#PREVIEW_PLAYERS * (PREVIEW_BAR_HEIGHT + PREVIEW_BAR_SPACING)) + PREVIEW_PADDING * 2 + 4

    -- Container (no border)
    local container = CreateFrame("Frame", nil, parentFrame)
    container:SetHeight(totalHeight)

    local bgc = db.windowBackdropColor or { 0.06, 0.06, 0.08, 0.95 }
    local bgAlpha = db.windowBackdropOpacity and (db.windowBackdropOpacity / 100) or bgc[4] or 0.95
    local bg = container:CreateTexture(nil, "BACKGROUND", nil, -8)
    bg:SetAllPoints()
    bg:SetColorTexture(bgc[1] or 0.06, bgc[2] or 0.06, bgc[3] or 0.08, bgAlpha)

    -- Window border preview (same code path as the real windows)
    if DMY and DMY._ApplyWindowBorder then
        DMY._ApplyWindowBorder(container, db)
    end

    -- Use parent width for layout (read after anchoring, fall back to estimate)
    local containerWidth = parentFrame:GetWidth()
    if containerWidth < 100 then containerWidth = 500 end
    containerWidth = containerWidth - 24 -- account for outer padding

    -- Column widths. The name column is a dragged fraction of the pool like
    -- every other column, so the preview runs the same math at its own scale.
    local nameAreaLeft = PREVIEW_PADDING + PREVIEW_ICON_SIZE + 4
    local poolRight = containerWidth - PREVIEW_PADDING
    local previewPool = math.max(poolRight - nameAreaLeft, 1)
    local nameFraction = (DMY and DMY._GetNameFraction)
        and DMY._GetNameFraction(cfg, previewPool, PREVIEW_NAME_WIDTH + 2)
        or ((PREVIEW_NAME_WIDTH + 2) / previewPool)
    local barAreaLeft = nameAreaLeft + math.floor(previewPool * nameFraction)
    -- The preview is narrower than the real window, so keep the value columns
    -- legible even when the live name fraction is large
    local maxBarAreaLeft = poolRight - numColumns * 20
    if barAreaLeft > maxBarAreaLeft then barAreaLeft = math.max(nameAreaLeft + 20, maxBarAreaLeft) end
    local barAreaWidth = math.max(poolRight - barAreaLeft, 1)

    -- Per-column edges mirroring the live window's fraction layout, so widths
    -- dragged via the Edit Mode dividers are visible in the preview
    local previewEdges = { [0] = barAreaLeft }
    do
        local fractions = (DMY and DMY._GetColumnFractions and cfg)
            and DMY._GetColumnFractions(cfg, numColumns) or nil
        local acc = 0
        for c = 1, numColumns do
            acc = acc + (fractions and fractions[c] or (1 / math.max(numColumns, 1)))
            previewEdges[c] = barAreaLeft + math.floor(barAreaWidth * math.min(acc, 1))
        end
        previewEdges[numColumns] = poolRight
    end

    -- Header bg
    local headerBg = container:CreateTexture(nil, "BACKGROUND", nil, -6)
    headerBg:SetPoint("TOPLEFT"); headerBg:SetPoint("TOPRIGHT")
    headerBg:SetHeight(PREVIEW_HEADER_HEIGHT)
    headerBg:SetColorTexture(0.08, 0.08, 0.10, 0.9)

    -- Session dropdown (Overall / Current only)
    if Controls and Controls.CreateDropdown then
        local sessionDropdown = Controls:CreateDropdown({
            parent = container,
            values = { [0] = "Overall", [1] = "Current" },
            order = { 0, 1 },
            get = function() return cfg and cfg.sessionType or 0 end,
            set = function(val)
                if cfg then cfg.sessionType = val end
                if builder then builder:DeferredRefreshAll() end
                if DMY and DMY._comp then DMY._ApplyStyling(DMY._comp) end
            end,
            width = 90, height = 20,
        })
        sessionDropdown:SetPoint("LEFT", container, "LEFT", PREVIEW_PADDING, 0)
        sessionDropdown:SetPoint("TOP", container, "TOP", 0, -4)
    end

    -- Column header dropdowns
    local metricValues, metricOrder = BuildMetricDropdownValues()
    for c = 1, numColumns do
        local colDef = columns[c]
        if colDef and Controls and Controls.CreateDropdown then
            -- Add "Remove Column" as first option (only for non-primary columns)
            local dropValues = {}
            local dropOrder = {}
            if c > 1 then
                dropValues["_remove"] = "|cffff4444Remove Column|r"
                table.insert(dropOrder, "_remove")
            end
            for _, key in ipairs(metricOrder) do
                dropValues[key] = metricValues[key]
                table.insert(dropOrder, key)
            end

            local colIdx = c -- capture for closure
            local isPrimary = (c == 1)
            local dropWidth = math.max(60, (previewEdges[c] - previewEdges[c - 1]) - 4)

            local colDropdown = Controls:CreateDropdown({
                parent = container,
                values = dropValues,
                order = dropOrder,
                get = function() return colDef.format end,
                set = function(val)
                    if val == "_remove" then
                        table.remove(cfg.columns, colIdx)
                        -- Redistribute the removed column's width share
                        if DMY.NormalizeColumnFractions then DMY.NormalizeColumnFractions(cfg) end
                    else
                        colDef.format = val
                    end
                    if builder then builder:DeferredRefreshAll() end
                    if DMY and DMY._comp then DMY._ApplyStyling(DMY._comp) end
                end,
                width = dropWidth, height = 20,
            })

            colDropdown:SetPoint("TOPRIGHT", container, "TOPLEFT", previewEdges[c], -4)
        end
    end

    -- Header divider
    local div = container:CreateTexture(nil, "ARTWORK")
    div:SetHeight(1)
    div:SetPoint("TOPLEFT", 0, -PREVIEW_HEADER_HEIGHT)
    div:SetPoint("TOPRIGHT", 0, -PREVIEW_HEADER_HEIGHT)
    div:SetColorTexture(0.3, 0.3, 0.35, 0.5)

    -- Bar styling
    local barTexPath = addon.Media and addon.Media.ResolveBarTexturePath and addon.Media.ResolveBarTexturePath(db.barTexture or "default") or nil
    local barBgColor = db.barBackgroundColor or { 0.1, 0.1, 0.1, 0.8 }
    local primaryFormatKey = columns[1] and columns[1].format or "dps"
    local maxPrimaryVal = GetPlayerValue(PREVIEW_PLAYERS[1], primaryFormatKey)
    if maxPrimaryVal <= 0 then maxPrimaryVal = 1 end

    local barMode = db.barMode or "default"
    local showBars = barMode ~= "hidden"

    -- Bar rows
    for rowIdx, player in ipairs(PREVIEW_PLAYERS) do
        local yTop = -(PREVIEW_HEADER_HEIGHT + 1 + PREVIEW_PADDING + (rowIdx - 1) * (PREVIEW_BAR_HEIGHT + PREVIEW_BAR_SPACING))

        -- Class color
        local classColor = addon.ClassColors and addon.ClassColors[player.classFilename]
        local cr, cg, cb = 0.6, 0.6, 0.6
        if db.barForegroundColorMode == "custom" then
            local cc = db.barCustomColor or { 0.8, 0.7, 0.2, 1 }
            cr, cg, cb = cc[1] or 0.8, cc[2] or 0.7, cc[3] or 0.2
        elseif classColor then
            cr, cg, cb = classColor.r or 0.6, classColor.g or 0.6, classColor.b or 0.6
        end

        -- Icon
        local icon = container:CreateTexture(nil, "ARTWORK")
        icon:SetSize(PREVIEW_ICON_SIZE, PREVIEW_ICON_SIZE)
        icon:SetPoint("TOPLEFT", container, "TOPLEFT", PREVIEW_PADDING, yTop - 1)
        local atlas = GetClassAtlas and GetClassAtlas(player.classFilename)
        if atlas then icon:SetAtlas(atlas)
        else icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark") end

        -- Name
        local nameText = container:CreateFontString(nil, "OVERLAY")
        -- Via ApplyFontStyle, not SetFont: the SHADOW*/HEAVY* styles are Scoot
        -- compounds, and SetFont only substring-matches OUTLINE/THICKOUTLINE out
        -- of them -- the shadow half would silently vanish from the preview.
        addon.ApplyFontStyle(nameText, nameFontPath, fontNames.fontSize or 12, fontNames.fontStyle or "OUTLINE")
        nameText:SetPoint("LEFT", icon, "RIGHT", 3, 0)
        nameText:SetWidth(math.max(20, barAreaLeft - nameAreaLeft - 2))
        nameText:SetJustifyH("LEFT"); nameText:SetWordWrap(false)
        nameText:SetText(player.name)

        -- Name color: respect colorMode setting
        local nameColorMode = fontNames.colorMode or "default"
        if nameColorMode == "class" then
            local classColor = addon.ClassColors and addon.ClassColors[player.classFilename]
            if classColor then
                nameText:SetTextColor(classColor.r or 1, classColor.g or 1, classColor.b or 1, 1)
            else
                nameText:SetTextColor(1, 1, 1, 1)
            end
        elseif nameColorMode == "custom" and fontNames.color then
            local nc = fontNames.color
            nameText:SetTextColor(nc[1] or 1, nc[2] or 1, nc[3] or 1, nc[4] or 1)
        else
            nameText:SetTextColor(1, 1, 1, 1)
        end

        -- Bar background (full width of bar area)
        local barBg = container:CreateTexture(nil, "BACKGROUND", nil, -4)
        if barMode == "thin" then
            barBg:SetPoint("TOPLEFT", container, "TOPLEFT", barAreaLeft, yTop - PREVIEW_BAR_HEIGHT + PREVIEW_THIN_BAR_HEIGHT)
            barBg:SetPoint("TOPRIGHT", container, "TOPRIGHT", -PREVIEW_PADDING, yTop - PREVIEW_BAR_HEIGHT + PREVIEW_THIN_BAR_HEIGHT)
            barBg:SetHeight(PREVIEW_THIN_BAR_HEIGHT)
        else
            barBg:SetPoint("TOPLEFT", container, "TOPLEFT", barAreaLeft, yTop)
            barBg:SetPoint("TOPRIGHT", container, "TOPRIGHT", -PREVIEW_PADDING, yTop)
            barBg:SetHeight(PREVIEW_BAR_HEIGHT)
        end
        barBg:SetColorTexture(barBgColor[1] or 0.1, barBgColor[2] or 0.1, barBgColor[3] or 0.1, barBgColor[4] or 0.8)

        -- Single full-width StatusBar (primary column data)
        local bar = CreateFrame("StatusBar", nil, container)
        if barMode == "thin" then
            bar:SetPoint("TOPLEFT", container, "TOPLEFT", barAreaLeft, yTop - PREVIEW_BAR_HEIGHT + PREVIEW_THIN_BAR_HEIGHT)
            bar:SetPoint("TOPRIGHT", container, "TOPRIGHT", -PREVIEW_PADDING, yTop - PREVIEW_BAR_HEIGHT + PREVIEW_THIN_BAR_HEIGHT)
            bar:SetHeight(PREVIEW_THIN_BAR_HEIGHT)
        else
            bar:SetPoint("TOPLEFT", container, "TOPLEFT", barAreaLeft, yTop)
            bar:SetPoint("TOPRIGHT", container, "TOPRIGHT", -PREVIEW_PADDING, yTop)
            bar:SetHeight(PREVIEW_BAR_HEIGHT)
        end
        bar:SetStatusBarTexture(barTexPath or "Interface\\Buttons\\WHITE8x8")
        bar:SetStatusBarColor(cr, cg, cb)
        local primaryVal = GetPlayerValue(player, primaryFormatKey)
        bar:SetMinMaxValues(0, maxPrimaryVal)
        bar:SetValue(primaryVal)

        -- Mode-aware visibility
        if barMode == "hollow" then
            bar:SetShown(showBars)
            barBg:SetShown(false)
            local barTex = bar:GetStatusBarTexture()
            if barTex then barTex:SetAlpha(0) end
        else
            bar:SetShown(showBars)
            barBg:SetShown(showBars)
        end

        -- Hollow outline (4 edge textures tracking the fill region)
        if barMode == "hollow" and showBars then
            local barTex = bar:GetStatusBarTexture()
            local outlineFrame = CreateFrame("Frame", nil, container)
            outlineFrame:SetFrameLevel(container:GetFrameLevel())
            outlineFrame:SetAllPoints(bar)

            local t = 1
            local edgeTop = outlineFrame:CreateTexture(nil, "ARTWORK")
            edgeTop:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
            edgeTop:SetPoint("TOPRIGHT", barTex, "TOPRIGHT", 0, 0)
            edgeTop:SetHeight(t)
            edgeTop:SetColorTexture(cr, cg, cb, 1)

            local edgeBottom = outlineFrame:CreateTexture(nil, "ARTWORK")
            edgeBottom:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
            edgeBottom:SetPoint("BOTTOMRIGHT", barTex, "BOTTOMRIGHT", 0, 0)
            edgeBottom:SetHeight(t)
            edgeBottom:SetColorTexture(cr, cg, cb, 1)

            local edgeLeft = outlineFrame:CreateTexture(nil, "ARTWORK")
            edgeLeft:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
            edgeLeft:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
            edgeLeft:SetWidth(t)
            edgeLeft:SetColorTexture(cr, cg, cb, 1)

            local edgeRight = outlineFrame:CreateTexture(nil, "ARTWORK")
            edgeRight:SetPoint("TOPRIGHT", barTex, "TOPRIGHT", 0, 0)
            edgeRight:SetPoint("BOTTOMRIGHT", barTex, "BOTTOMRIGHT", 0, 0)
            edgeRight:SetWidth(t)
            edgeRight:SetColorTexture(cr, cg, cb, 1)
        end

        -- Column value texts overlaid on the bar. Center-anchored like the live
        -- windows (which hard-clip at the column edges); the preview's bounded
        -- width stands in for the clip frame.
        for c = 1, numColumns do
            local colDef = columns[c]
            if colDef then
                local textParent = showBars and bar or container
                local valText = textParent:CreateFontString(nil, "OVERLAY")
                addon.ApplyFontStyle(valText, valueFontPath, fontValues.fontSize or 11, fontValues.fontStyle or "OUTLINE")
                valText:SetJustifyH("CENTER")
                valText:SetWordWrap(false)
                valText:SetWidth(math.max((previewEdges[c] - previewEdges[c - 1]) - 6, 10))
                valText:SetPoint("CENTER", container, "TOPLEFT", (previewEdges[c - 1] + previewEdges[c]) / 2, yTop - PREVIEW_BAR_HEIGHT / 2)
                valText:SetText(FormatPlayerValue(player, colDef.format))

                -- Subtle primary column indicator: slightly brighter text on first column
                if c == 1 then
                    valText:SetTextColor(1, 1, 1, 1)
                else
                    valText:SetTextColor(0.9, 0.9, 0.9, 0.85)
                end
            end
        end
    end

    return container, totalHeight
end

--------------------------------------------------------------------------------
-- ON/OFF Indicator (compact, from StartHere pattern)
--------------------------------------------------------------------------------

local function CreateOnOffIndicator(parent, isOn, onClick)
    local Theme = GetTheme()
    local ar, ag, ab = 0.2, 0.9, 0.3
    if Theme and Theme.GetAccentColor then ar, ag, ab = Theme:GetAccentColor() end
    local dimR, dimG, dimB = 0.6, 0.6, 0.6
    if Theme and Theme.GetDimTextColor then dimR, dimG, dimB = Theme:GetDimTextColor() end

    local indicator = CreateFrame("Button", nil, parent)
    indicator:SetSize(50, 22)

    -- Border
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
-- Window Selector Row
--------------------------------------------------------------------------------

local function CreateWindowSelector(parentFrame, builder)
    local row = CreateFrame("Frame", nil, parentFrame)
    row:SetHeight(28)

    local Theme = GetTheme()
    local Controls = GetControls()
    local ar, ag, ab = 0.2, 0.9, 0.3
    if Theme and Theme.GetAccentColor then ar, ag, ab = Theme:GetAccentColor() end

    -- [1]-[5] buttons
    for i = 1, (DMY and DMY.MAX_WINDOWS or 5) do
        local btn = CreateFrame("Button", nil, row)
        btn:SetSize(28, 22)
        btn:SetPoint("LEFT", row, "LEFT", (i - 1) * 32 + 4, 0)

        local btnBg = btn:CreateTexture(nil, "BACKGROUND")
        btnBg:SetAllPoints()
        btnBg:SetColorTexture(i == selectedWindow and ar or 0.15, i == selectedWindow and ag or 0.15, i == selectedWindow and ab or 0.18, i == selectedWindow and 0.3 or 1)

        local label = btn:CreateFontString(nil, "OVERLAY")
        if Theme and Theme.ApplyValueFont then Theme:ApplyValueFont(label, 11)
        else label:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE") end
        label:SetPoint("CENTER"); label:SetText(tostring(i))
        label:SetTextColor(i == selectedWindow and ar or 0.6, i == selectedWindow and ag or 0.6, i == selectedWindow and ab or 0.6, 1)

        local bw, bc = 1, (i == selectedWindow) and { ar, ag, ab, 0.6 } or { 0.3, 0.3, 0.35, 0.5 }
        for _, s in ipairs({ "TOP", "BOTTOM" }) do
            local t = btn:CreateTexture(nil, "BORDER"); t:SetPoint(s.."LEFT"); t:SetPoint(s.."RIGHT"); t:SetHeight(bw); t:SetColorTexture(bc[1], bc[2], bc[3], bc[4])
        end
        for _, s in ipairs({ "LEFT", "RIGHT" }) do
            local t = btn:CreateTexture(nil, "BORDER"); t:SetPoint("TOP"..s); t:SetPoint("BOTTOM"..s); t:SetWidth(bw); t:SetColorTexture(bc[1], bc[2], bc[3], bc[4])
        end

        btn:SetScript("OnClick", function()
            selectedWindow = i
            -- Mirrored onto the panel so deep links can target a window, the
            -- same way _actionBarSelectedBar works.
            addon.UI.SettingsPanel._damageMeterYSelectedWindow = i
            if builder then builder:DeferredRefreshAll() end
        end)
    end

    -- ON/OFF indicator
    local cfg = DMY and DMY._GetWindowConfig and DMY._GetWindowConfig(selectedWindow)
    local indicator = CreateOnOffIndicator(row, cfg and cfg.enabled, function()
        if cfg then
            cfg.enabled = not cfg.enabled
            if DMY._comp then DMY._ApplyStyling(DMY._comp) end
            if builder then builder:DeferredRefreshAll() end
        end
    end)
    indicator:SetPoint("LEFT", row, "LEFT", 5 * 32 + 12, 0)

    -- Copy From dropdown
    if Controls and Controls.CreateDropdown then
        local copyValues, copyOrder = {}, {}
        for i = 1, (DMY and DMY.MAX_WINDOWS or 5) do
            if i ~= selectedWindow then
                copyValues[i] = "Window " .. i
                table.insert(copyOrder, i)
            end
        end

        local copyDropdown = Controls:CreateDropdown({
            parent = row,
            values = copyValues,
            order = copyOrder,
            placeholder = "Copy from...",
            width = 120,
            height = 22,
            fontSize = 10,
            set = function(sourceIdx)
                if addon.Dialogs and addon.Dialogs.Show then
                    addon.Dialogs:Show("SCOOT_COPY_DMY_CONFIRM", {
                        formatArgs = { tostring(sourceIdx), tostring(selectedWindow) },
                        onAccept = function()
                            if DMY and DMY.CopyWindowSettings then
                                DMY.CopyWindowSettings(sourceIdx, selectedWindow)
                            end
                            if builder then builder:DeferredRefreshAll() end
                        end,
                    })
                end
            end,
        })
        copyDropdown:SetPoint("LEFT", indicator, "RIGHT", 8, 0)
    end

    -- [+ Column] button (only enabled for Overall windows)
    local columns = cfg and cfg.columns or {}
    local isOverall = cfg and cfg.sessionType == 0
    if #columns < 5 and Controls and Controls.CreateButton then
        local addColBtn = Controls:CreateButton({
            parent = row, text = "+ Column", fontSize = 10, height = 22,
            onClick = function()
                if not isOverall then return end
                if cfg and cfg.columns then
                    local nOld = #cfg.columns
                    local newCol = { format = "damage" }
                    -- Windows with custom column widths: seed the new column
                    -- at 1/nOld so normalization lands it at exactly 1/nNew
                    -- while existing columns keep their proportions. Windows
                    -- in equal-split mode (no stored fractions) stay that way.
                    local hasFractions = false
                    for _, col in ipairs(cfg.columns) do
                        if tonumber(col.widthFraction) then hasFractions = true break end
                    end
                    if hasFractions and nOld > 0 then
                        newCol.widthFraction = 1 / nOld
                    end
                    table.insert(cfg.columns, newCol)
                    if hasFractions and DMY.NormalizeColumnFractions then
                        DMY.NormalizeColumnFractions(cfg)
                    end
                    if builder then builder:DeferredRefreshAll() end
                    if DMY and DMY._comp then DMY._ApplyStyling(DMY._comp) end
                end
            end,
        })
        addColBtn:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        if not isOverall then
            addColBtn:SetAlpha(0.4)
        end
    end

    return row
end

--------------------------------------------------------------------------------
-- Main Renderer
--------------------------------------------------------------------------------

function DMYSettings.Render(panel, scrollContent)
    -- Honour a window chosen by a deep link (addon.UI:OpenToPage pageState).
    selectedWindow = panel._damageMeterYSelectedWindow or selectedWindow

    panel:ClearContent()
    local builder = SettingsBuilder:CreateFor(scrollContent)
    panel._currentBuilder = builder
    builder:SetOnRefresh(function() DMYSettings.Render(panel, scrollContent) end)

    local Helpers = addon.UI.Settings.Helpers
    local h = Helpers.CreateComponentHelpers("damageMeterV2")
    local getSetting, setSetting = h.get, h.setAndApply
    local function setAndRefresh(k, v) setSetting(k, v); builder:DeferredRefreshAll() end

    local comp = DMY and DMY._comp

    -- Window Selector
    local ws = CreateWindowSelector(scrollContent, builder)
    ws:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", 12, -8)
    ws:SetPoint("TOPRIGHT", scrollContent, "TOPRIGHT", -12, -8)
    table.insert(builder._controls, ws)
    builder._currentY = -8 - 28 - 8

    -- Preview Pane
    if comp then
        local pp, ph = CreatePreviewPane(scrollContent, comp, selectedWindow, builder)
        if pp then
            pp:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", 12, builder._currentY)
            pp:SetPoint("TOPRIGHT", scrollContent, "TOPRIGHT", -12, builder._currentY)
            table.insert(builder._controls, pp)
            builder._currentY = builder._currentY - ph - 8
        end
    end

    -- Collapsible Sections

    -- Sizing (per-window) — first because it's per-window and most relevant to selected window
    local function getWinSizing(key, default)
        local winCfg = DMY and DMY._GetWindowConfig and DMY._GetWindowConfig(selectedWindow)
        return winCfg and winCfg[key] or default
    end
    local function setWinSizing(key, value)
        -- Shared write path with the Edit Mode mirror (validates + clamps +
        -- restyles), so the two surfaces cannot drift.
        if DMY and DMY.SetWindowSizing then
            DMY.SetWindowSizing(selectedWindow, key, value)
        end
        builder:DeferredRefreshAll()
    end

    builder:AddCollapsibleSection({ title = "Sizing", componentId = "damageMeterV2", sectionKey = "layout", defaultExpanded = false,
        infoIcon = {
            tooltipTitle = "Per-Window Setting",
            tooltipText = "Sizing settings apply only to the selected window (1-5). All other settings in this menu apply to all windows.",
        },
        buildContent = function(_, inner)
            inner:AddDescription("Columns can be sized individually in Edit Mode by dragging the vertical white lines in a selected window.", { color = {1, 0.82, 0}, bottomPadding = 2 })
            inner:AddSlider({ label = "Window Scale", min = 0.5, max = 2.0, step = 0.05, precision = 2,
                get = function() return getWinSizing("windowScale", 1.0) end, set = function(v) setWinSizing("windowScale", v) end })
            inner:AddSlider({ label = "Frame Width", min = 100, max = 800, step = 10,
                get = function() return getWinSizing("frameWidth", 350) end, set = function(v) setWinSizing("frameWidth", v) end })
            inner:AddSlider({ label = "Frame Height", min = 100, max = 600, step = 10,
                get = function() return getWinSizing("frameHeight", 250) end, set = function(v) setWinSizing("frameHeight", v) end })
            inner:Finalize()
        end })

    builder:AddCollapsibleSection({ title = "Quality of Life", componentId = "damageMeterV2", sectionKey = "qol", defaultExpanded = false,
        buildContent = function(_, inner)
            inner:AddSelector({ label = "Auto-Reset Data", values = { off = "Off", instance = "When Entering Instance" }, order = { "off", "instance" },
                get = function() return getSetting("autoResetData") or "off" end, set = function(v) setSetting("autoResetData", v) end })
            inner:AddToggle({ label = "Prompt Before Reset", get = function() return getSetting("autoResetPrompt") ~= false end, set = function(v) setSetting("autoResetPrompt", v) end,
                isDisabled = function() return (getSetting("autoResetData") or "off") == "off" end })
            inner:AddSlider({ label = "Update Throttle (seconds)", min = 0.5, max = 3.0, step = 0.1, precision = 1,
                get = function() return getSetting("updateThrottle") or 1.0 end, set = function(v) setSetting("updateThrottle", v) end })
            inner:AddToggle({ label = "Show Local Player Row", description = "Pin your character at the bottom of the meter when scrolled out of view.",
                get = function() return getSetting("showLocalPlayer") ~= false end, set = function(v) setSetting("showLocalPlayer", v) end })
            inner:AddToggle({ label = "Enable /dmshow and /dmreset commands",
                description = "Type /dmshow to toggle the Damage Meter on or off. Type /dmreset to reset all session data.",
                get = function() return getSetting("enableSlashDM") or false end, set = function(v) setSetting("enableSlashDM", v) end })
            inner:Finalize()
        end })

    builder:AddCollapsibleSection({ title = "Bars", componentId = "damageMeterV2", sectionKey = "bars", defaultExpanded = false,
        buildContent = function(_, inner)
            inner:AddSelector({
                label = "Bar Mode",
                description = "Controls how the damage meter bars are displayed.",
                values = { default = "Default", thin = "Thin", hollow = "Hollow", hidden = "Hide Bars" },
                order = { "default", "thin", "hollow", "hidden" },
                emphasized = true,
                get = function() return getSetting("barMode") or "default" end,
                set = function(v) setAndRefresh("barMode", v) end,
            })
            inner:AddTabbedSection({
                componentId = "damageMeterV2", sectionKey = "barTabs",
                tabs = {
                    { key = "sizing", label = "Sizing" },
                    { key = "style", label = "Style" },
                    { key = "border", label = "Border" },
                    { key = "barVisibility", label = "Visibility" },
                },
                buildContent = {
                    sizing = function(_, tabInner)
                        tabInner:AddSlider({ label = "Bar Height", min = 15, max = 40, step = 1,
                            get = function() return getSetting("barHeight") or 22 end, set = function(v) setAndRefresh("barHeight", v) end })
                        tabInner:AddSlider({ label = "Bar Spacing", min = 0, max = 8, step = 1,
                            get = function() return getSetting("barSpacing") or 2 end, set = function(v) setAndRefresh("barSpacing", v) end })
                        tabInner:Finalize()
                    end,
                    style = function(_, tabInner)
                        tabInner:AddDualBarStyleRow({
                            label = "Foreground",
                            getTexture = function() return getSetting("barTexture") or "default" end,
                            setTexture = function(v) setAndRefresh("barTexture", v) end,
                            colorValues = { class = "Class Color", custom = "Custom" },
                            colorOrder = { "class", "custom" },
                            getColorMode = function() return getSetting("barForegroundColorMode") or "class" end,
                            setColorMode = function(v) setAndRefresh("barForegroundColorMode", v) end,
                            getColor = function()
                                local c = getSetting("barCustomColor") or {0.8,0.7,0.2,1}
                                return c[1] or 0.8, c[2] or 0.7, c[3] or 0.2, c[4] or 1
                            end,
                            setColor = function(r,g,b,a) setAndRefresh("barCustomColor", {r,g,b,a}) end,
                            customColorValue = "custom",
                        })
                        tabInner:AddDualBarStyleRow({
                            label = "Background",
                            getTexture = function() return getSetting("barBgTexture") or "default" end,
                            setTexture = function(v) setAndRefresh("barBgTexture", v) end,
                            colorValues = { default = "Default", custom = "Custom" },
                            colorOrder = { "default", "custom" },
                            getColorMode = function() return getSetting("barBgColorMode") or "default" end,
                            setColorMode = function(v) setAndRefresh("barBgColorMode", v) end,
                            getColor = function()
                                local c = getSetting("barBgCustomColor") or {0.1,0.1,0.1,0.8}
                                return c[1] or 0.1, c[2] or 0.1, c[3] or 0.1, c[4] or 0.8
                            end,
                            setColor = function(r,g,b,a) setAndRefresh("barBgCustomColor", {r,g,b,a}) end,
                            customColorValue = "custom",
                            hasAlpha = true,
                        })
                        tabInner:AddSlider({ label = "Background Opacity", min = 0, max = 100, step = 5,
                            get = function() return getSetting("barBackgroundOpacity") or 80 end,
                            set = function(v) setAndRefresh("barBackgroundOpacity", v) end })
                        tabInner:Finalize()
                    end,
                    border = function(_, tabInner)
                        tabInner:AddBarBorderSelector({
                            label = "Border Style",
                            get = function() return getSetting("barBorderStyle") or "none" end,
                            set = function(v) setAndRefresh("barBorderStyle", v) end,
                            includeNone = true,
                        })
                        tabInner:AddSelectorColorPicker({
                            label = "Border Color",
                            values = { default = "Default (Black)", class = "Class Color", custom = "Custom" },
                            order = { "default", "class", "custom" },
                            get = function() return getSetting("barBorderColorMode") or "default" end,
                            set = function(v) setAndRefresh("barBorderColorMode", v or "default") end,
                            getColor = function()
                                local c = getSetting("barBorderColor") or {0,0,0,1}
                                return c[1] or 0, c[2] or 0, c[3] or 0, c[4] or 1
                            end,
                            setColor = function(r,g,b,a) setAndRefresh("barBorderColor", {r,g,b,a}) end,
                            customValue = "custom",
                            hasAlpha = true,
                        })
                        tabInner:AddSlider({ label = "Border Thickness", min = 1, max = 8, step = 0.5, precision = 1,
                            get = function() return getSetting("barBorderThickness") or 1 end,
                            set = function(v) setAndRefresh("barBorderThickness", v) end })
                        tabInner:AddDualSlider({
                            label = "Border Inset",
                            sliderA = { label = "H", min = -4, max = 4, step = 1,
                                get = function() return getSetting("barBorderInsetH") or 0 end,
                                set = function(v) setAndRefresh("barBorderInsetH", v) end },
                            sliderB = { label = "V", min = -4, max = 4, step = 1,
                                get = function() return getSetting("barBorderInsetV") or 0 end,
                                set = function(v) setAndRefresh("barBorderInsetV", v) end },
                        })
                        tabInner:Finalize()
                    end,
                    barVisibility = function(_, tabInner)
                        tabInner:AddToggle({ label = "Hide Rank Numbers",
                            get = function() return getSetting("hideRankNumbers") == true end,
                            set = function(v) setAndRefresh("hideRankNumbers", v) end })
                        tabInner:Finalize()
                    end,
                },
            })
            inner:Finalize()
        end })

    -- Shared text property helpers (used by Text and Title Bar sections)
    local TextHelpers = addon.UI.Settings.Helpers
    -- Resolved against the registered default, the same way the styling pass
    -- resolves it. The panel must never invent its own fallback: displaying
    -- ROBOTO_SEMICOND_BOLD here while the HUD rendered a locally hardcoded
    -- FRIZQT__ is precisely how the fresh-profile font bug stayed invisible.
    local function getTextProp(tableKey, propKey)
        local c = h.getComponent()
        local t = c and addon:ResolveComponentSubTable(c, tableKey) or getSetting(tableKey)
        return t and t[propKey]
    end
    local function setTextProp(tableKey, propKey, value)
        local c = h.getComponent()
        if c then
            -- Seeded from a copy of the registered default, so changing one
            -- property never drops its siblings and never aliases (and then
            -- mutates) the registration table shared by every profile.
            local t = addon:EnsureComponentSubTable(c, tableKey)
            if t then t[propKey] = value end
        end
    end
    local function applyText()
        local c = h.getComponent()
        if c and c.ApplyStyling then
            C_Timer.After(0, function()
                if c and c.ApplyStyling then c:ApplyStyling() end
            end)
        end
        builder:DeferredRefreshAll()
    end
    -- All meter text is Scoot-drawn, so the paired Deep Shadow styles are
    -- offered on every tab. The sub-tables store style/size under
    -- fontStyle/fontSize; the accessors translate the composite's field names.
    local FIELD_KEYS = { style = "fontStyle", size = "fontSize" }
    local function AddTextControls(tabInner, tableKey, defaultSize)
        tabInner:AddTextStyleBlock({
            get = function(field)
                return getTextProp(tableKey, FIELD_KEYS[field] or field)
            end,
            set = function(field, value)
                setTextProp(tableKey, FIELD_KEYS[field] or field, value)
            end,
            apply = applyText,
            defaults = { size = defaultSize },
            style = { order = TextHelpers.fontStyleOrderPaired },
            size = { min = 6, max = 24 },
            offset = false,
        })
    end

    -- sectionKey stays "text" so users' expand/collapse state survives the rename
    builder:AddCollapsibleSection({ title = "Bar Texts", componentId = "damageMeterV2", sectionKey = "text", defaultExpanded = false,
        buildContent = function(_, inner)
            inner:AddTabbedSection({
                componentId = "damageMeterV2", sectionKey = "textTabs",
                tabs = {
                    { key = "playerName", label = "Player Name" },
                    { key = "headerRow", label = "Header Row" },
                    { key = "meterNumbers", label = "Meter Numbers" },
                },
                buildContent = {
                    playerName = function(_, tabInner)
                        AddTextControls(tabInner, "textNames", 12)
                        tabInner:AddToggle({ label = "Hide Realm Names",
                            description = "Shows only the player name without server (e.g., 'Player' instead of 'Player-Realm').",
                            get = function() return getSetting("hideRealmNames") ~= false end,
                            set = function(v) setAndRefresh("hideRealmNames", v) end })
                        tabInner:Finalize()
                    end,
                    headerRow = function(_, tabInner)
                        tabInner:AddSelector({ label = "Column Header Names",
                            description = "Regular shows full metric names. Abbreviated compacts them (e.g., 'Intrpts'). Icons replaces text with a matched metric icon per column.",
                            values = { regular = "Regular", abbreviated = "Abbreviated", icons = "Icons" },
                            order = { "regular", "abbreviated", "icons" },
                            get = function() return getSetting("columnHeaderMode") or "regular" end,
                            set = function(v) setAndRefresh("columnHeaderMode", v) end })
                        AddTextControls(tabInner, "textHeaders", 10)
                        tabInner:Finalize()
                    end,
                    meterNumbers = function(_, tabInner)
                        AddTextControls(tabInner, "textValues", 11)
                        tabInner:Finalize()
                    end,
                },
            })
            inner:Finalize()
        end })

    builder:AddCollapsibleSection({ title = "Title Bar", componentId = "damageMeterV2", sectionKey = "titleBar", defaultExpanded = false,
        buildContent = function(_, inner)
            inner:AddTabbedSection({
                componentId = "damageMeterV2", sectionKey = "titleBarTabs",
                tabs = {
                    { key = "titleSettings", label = "Settings" },
                    { key = "titleText", label = "Title Text" },
                    { key = "timerText", label = "Timer Text" },
                },
                buildContent = {
                    titleSettings = function(_, tabInner)
                        tabInner:AddToggle({ label = "Show Title Bar Backdrop",
                            get = function() return getSetting("showTitleBarBackdrop") ~= false end,
                            set = function(v) setAndRefresh("showTitleBarBackdrop", v) end })
                        tabInner:AddSelector({ label = "Title Mode",
                            values = { auto = "Auto (Session Name)", custom = "Custom" }, order = { "auto", "custom" },
                            get = function() return getSetting("titleMode") or "auto" end,
                            set = function(v) setSetting("titleMode", v) end })
                        tabInner:AddToggle({ label = "Vertical Title Mode",
                            description = "Displays the title vertically on the left side of the frame.",
                            get = function() return getSetting("verticalTitleMode") or false end,
                            set = function(v) setAndRefresh("verticalTitleMode", v) end })
                        tabInner:Finalize()
                    end,
                    titleText = function(_, tabInner)
                        AddTextControls(tabInner, "textTitle", 13)
                        tabInner:Finalize()
                    end,
                    timerText = function(_, tabInner)
                        AddTextControls(tabInner, "textTimer", 13)
                        tabInner:Finalize()
                    end,
                },
            })
            inner:Finalize()
        end })

    builder:AddCollapsibleSection({ title = "Icons", componentId = "damageMeterV2", sectionKey = "icons", defaultExpanded = false,
        buildContent = function(_, inner)
            inner:AddToggle({ label = "Show Icons",
                get = function() return getSetting("showIcons") ~= false end,
                set = function(v) setAndRefresh("showIcons", v) end })

            -- Icon style selector: "Default (Spec)" + JiberishIcons styles if available
            local iconStyleValues = { default = "Default (Spec)" }
            local iconStyleOrder = { "default" }
            if addon.IsJiberishIconsAvailable and addon.IsJiberishIconsAvailable() then
                local jiStyles = addon.GetJiberishIconsStyles and addon.GetJiberishIconsStyles() or {}
                for key, name in pairs(jiStyles) do
                    iconStyleValues[key] = name
                    table.insert(iconStyleOrder, key)
                end
            end
            if #iconStyleOrder > 1 then
                inner:AddSelector({ label = "Icon Style",
                    values = iconStyleValues, order = iconStyleOrder,
                    get = function() return getSetting("iconStyle") or "default" end,
                    set = function(v) setAndRefresh("iconStyle", v) end,
                    isDisabled = function() return getSetting("showIcons") == false end })
            end
            inner:Finalize()
        end })

    builder:AddCollapsibleSection({ title = "Window Border", componentId = "damageMeterV2", sectionKey = "windowBorder", defaultExpanded = false,
        buildContent = function(_, inner)
            inner:AddSelector({ label = "Border Style",
                values = { none = "None", square = "Square", rounded = "Rounded" },
                order = { "none", "square", "rounded" },
                get = function() return getSetting("windowBorderStyle") or "none" end,
                set = function(v) setAndRefresh("windowBorderStyle", v) end })
            inner:AddColorPicker({ label = "Border Color", hasAlpha = true,
                get = function() local c = getSetting("windowBorderColor") or {0,0,0,1}; return c[1],c[2],c[3],c[4] end,
                set = function(r,g,b,a) setAndRefresh("windowBorderColor", {r,g,b,a}) end,
                isDisabled = function() return (getSetting("windowBorderStyle") or "none") == "none" end })
            inner:AddSlider({ label = "Border Thickness", min = 1, max = 8, step = 0.5, precision = 1,
                get = function() return getSetting("windowBorderThickness") or 1 end,
                set = function(v) setAndRefresh("windowBorderThickness", v) end,
                isDisabled = function() return (getSetting("windowBorderStyle") or "none") == "none" end })
            inner:Finalize()
        end })

    builder:AddCollapsibleSection({ title = "Window Backdrop", componentId = "damageMeterV2", sectionKey = "backdrop", defaultExpanded = false,
        buildContent = function(_, inner)
            inner:AddToggle({ label = "Show Window Backdrop",
                get = function() return getSetting("showBackdrop") ~= false end,
                set = function(v) setAndRefresh("showBackdrop", v) end })
            inner:AddColorPicker({ label = "Backdrop Color",
                get = function() local c = getSetting("windowBackdropColor") or {0.06,0.06,0.08,0.95}; return c[1],c[2],c[3],c[4] end,
                set = function(r,g,b,a) setAndRefresh("windowBackdropColor", {r,g,b,a}) end,
                isDisabled = function() return getSetting("showBackdrop") == false end })
            inner:AddSlider({ label = "Backdrop Opacity", min = 1, max = 100, step = 1,
                get = function()
                    local v = getSetting("windowBackdropOpacity")
                    if v then return v end
                    local c = getSetting("windowBackdropColor") or {0.06,0.06,0.08,0.95}
                    return math.floor((c[4] or 0.95) * 100 + 0.5)
                end,
                set = function(v) setAndRefresh("windowBackdropOpacity", v) end,
                isDisabled = function() return getSetting("showBackdrop") == false end })
            inner:Finalize()
        end })

    builder:AddCollapsibleSection({ title = "Visibility", componentId = "damageMeterV2", sectionKey = "visibility", defaultExpanded = false,
        buildContent = function(_, inner)
            inner:AddSelector({ label = "Visibility", values = { always = "Always", incombat = "In Combat", hidden = "Hidden" }, order = { "always", "incombat", "hidden" },
                get = function() return getSetting("visibility") or "always" end, set = function(v) setSetting("visibility", v) end })
            inner:AddSlider({ label = "Opacity", min = 0, max = 100, step = 5, get = function() return getSetting("opacity") or 100 end, set = function(v) setSetting("opacity", v) end })
            inner:AddSlider({ label = "Out of Combat Opacity", min = 0, max = 100, step = 5, get = function() return getSetting("opacityOutOfCombat") or 100 end, set = function(v) setSetting("opacityOutOfCombat", v) end })
            inner:Finalize()
        end })

    builder:AddCollapsibleSection({ title = "Export Window", componentId = "damageMeterV2", sectionKey = "exportWindow", defaultExpanded = false,
        buildContent = function(_, inner)
            inner:AddDescription("Settings for the High Score export window will appear here in a future update.")
            inner:Finalize()
        end })

    builder:Finalize()
end

addon.UI.SettingsPanel:RegisterRenderer("damageMeterV2", function(panel, scrollContent)
    DMYSettings.Render(panel, scrollContent)
end)
