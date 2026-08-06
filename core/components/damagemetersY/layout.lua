-- damagemetersY/layout.lua - Column width calculation, bar row layout, window sizing
local _, addon = ...
local DMY = addon.DamageMetersY

-- DMY windows carry a fractional effective scale (windowScale x UIParent scale),
-- so integer frame-space offsets land between physical pixels and each row
-- rasterizes its font outline at a different sub-pixel phase (some rows look
-- bolder). Snapping layout offsets to whole physical pixels gives every row
-- the same phase.
local function SnapToPixels(value, region, minPixels)
    if not (PixelUtil and PixelUtil.GetNearestPixelSize) then return value end
    local es = region and region:GetEffectiveScale()
    if not es or es <= 0 then return value end
    return PixelUtil.GetNearestPixelSize(value, es, minPixels)
end
DMY._SnapToPixels = SnapToPixels

--------------------------------------------------------------------------------
-- Uses DMY._UnifiedAbbreviate (defined in data.lua) for consistent formatting
-- in both combat (secret values) and OOC (plain values).

--------------------------------------------------------------------------------
-- Column Width Calculation
--------------------------------------------------------------------------------

function DMY._CalculateColumnWidths(windowIndex, comp)
    local win = DMY._windows[windowIndex]
    if not win then return end

    local cfg = DMY._GetWindowConfig(windowIndex)
    if not cfg then return end

    local db = comp.db
    local fw = tonumber(cfg.frameWidth or db.frameWidth) or 350
    local numColumns = math.min(#cfg.columns, DMY.MAX_COLUMNS)
    if numColumns == 0 then numColumns = 1 end
    if cfg.sessionType ~= 0 then numColumns = 1 end  -- Current/Expired: single column only

    -- Available width after icon + name
    local availableWidth = fw - DMY.ICON_SIZE - 6 - DMY.NAME_WIDTH - 8
    local colWidth = math.floor(availableWidth / numColumns)

    win._colWidth = colWidth
    win._numColumns = numColumns

    -- Position column headers (matching value text alignment)
    local barLeftOffset = DMY.ICON_SIZE + 6 + DMY.NAME_WIDTH + 8
    for c = 1, DMY.MAX_COLUMNS do
        local ch = win.columnHeaders[c]
        local cr = win.columnClickRegions and win.columnClickRegions[c]
        if c <= numColumns then
            ch:ClearAllPoints()
            local rightEdge = fw - (numColumns - c) * colWidth
            ch:SetWidth(colWidth - 8)
            ch:SetText(DMY._GetColumnHeader(cfg.columns[c].format))
            if numColumns == 1 then
                ch:SetJustifyH("RIGHT")
                ch:SetPoint("RIGHT", win.header, "LEFT", rightEdge - 4, 0)
            elseif c == 1 then
                ch:SetJustifyH("LEFT")
                ch:SetPoint("LEFT", win.header, "LEFT", barLeftOffset + 4, 0)
            elseif c == numColumns then
                ch:SetJustifyH("RIGHT")
                ch:SetPoint("RIGHT", win.header, "LEFT", rightEdge - 4, 0)
            else
                -- Middle columns: center within column span
                ch:SetJustifyH("CENTER")
                local colCenter = rightEdge - colWidth / 2
                ch:SetPoint("CENTER", win.header, "LEFT", colCenter, 0)
            end
            ch:Show()
            if cr then cr:Show() end
        else
            ch:Hide()
            if cr then cr:Hide() end
        end
    end
end

--------------------------------------------------------------------------------
-- Bar Mode — repositions bar/barBg based on mode
--------------------------------------------------------------------------------

local THIN_BAR_HEIGHT = 4

function DMY._ApplyBarMode(row, barMode, barAreaLeft)
    local bar = row.bar
    local barBg = row.barBg
    if not bar or not barBg then return end

    if barMode == "thin" then
        bar:ClearAllPoints()
        bar:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", barAreaLeft, 0)
        bar:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
        bar:SetHeight(THIN_BAR_HEIGHT)

        barBg:ClearAllPoints()
        barBg:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", barAreaLeft, 0)
        barBg:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
        barBg:SetHeight(THIN_BAR_HEIGHT)
    else
        -- Default and Hollow: full-height bar
        bar:ClearAllPoints()
        bar:SetPoint("LEFT", row, "LEFT", barAreaLeft, 0)
        bar:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        bar:SetPoint("TOP", row, "TOP", 0, 0)
        bar:SetPoint("BOTTOM", row, "BOTTOM", 0, 0)

        barBg:ClearAllPoints()
        barBg:SetPoint("LEFT", row, "LEFT", barAreaLeft, 0)
        barBg:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        barBg:SetPoint("TOP", row, "TOP", 0, 0)
        barBg:SetPoint("BOTTOM", row, "BOTTOM", 0, 0)
    end
end

--------------------------------------------------------------------------------
-- Bar Row Layout
--------------------------------------------------------------------------------

function DMY._LayoutBarRows(windowIndex, comp)
    local win = DMY._windows[windowIndex]
    if not win then return end

    local cfg = DMY._GetWindowConfig(windowIndex)
    if not cfg then return end

    local db = comp.db
    local fw = tonumber(cfg.frameWidth or db.frameWidth) or 350
    local barHeight = tonumber(db.barHeight) or 22
    local barSpacing = tonumber(db.barSpacing) or 2
    local numColumns = win._numColumns or 1
    local colWidth = win._colWidth or 100

    -- Alignment: 1 col = right; 2+ = first left, last right, middle centered in column
    local barLeftOffset = DMY.ICON_SIZE + 6 + DMY.NAME_WIDTH + 8
    local function LayoutRowValueTexts(row)
        for c = 1, DMY.MAX_COLUMNS do
            local vt = row.valueTexts[c]
            if c <= numColumns then
                vt:ClearAllPoints()
                -- Fixed width (matching header SetWidth in _CalculateColumnWidths)
                -- so over-long strings truncate on the right instead of
                -- overflowing leftward across the player name
                vt:SetWidth(math.max(colWidth - 8, 1))
                local rightEdge = fw - (numColumns - c) * colWidth
                if numColumns == 1 then
                    vt:SetJustifyH("RIGHT")
                    vt:SetPoint("RIGHT", row, "LEFT", rightEdge - 4, 0)
                elseif c == 1 then
                    vt:SetJustifyH("LEFT")
                    vt:SetPoint("LEFT", row, "LEFT", barLeftOffset + 4, 0)
                elseif c == numColumns then
                    vt:SetJustifyH("RIGHT")
                    vt:SetPoint("RIGHT", row, "LEFT", rightEdge - 4, 0)
                else
                    -- Middle columns: center within column span
                    vt:SetJustifyH("CENTER")
                    local colCenter = rightEdge - colWidth / 2
                    vt:SetPoint("CENTER", row, "LEFT", colCenter, 0)
                end
                vt:Show()
            else
                vt:Hide()
            end
        end
    end

    local barMode = db.barMode or "default"

    -- Position per-column click overlays (multi-column drill-down dispatch).
    -- Hidden for single-column windows; row's OnMouseUp handles those.
    local function LayoutColClickRegions(row)
        if not row.colClickRegions then return end
        for c = 1, DMY.MAX_COLUMNS do
            local btn = row.colClickRegions[c]
            if not btn then break end
            if numColumns >= 2 and c <= numColumns then
                local rightEdge = fw - (numColumns - c) * colWidth
                local leftEdge  = rightEdge - colWidth
                if c == 1 and leftEdge < barLeftOffset then leftEdge = barLeftOffset end
                btn:ClearAllPoints()
                btn:SetPoint("LEFT",  row, "LEFT", leftEdge,  0)
                btn:SetPoint("RIGHT", row, "LEFT", rightEdge, 0)
                btn:SetPoint("TOP",    row, "TOP",    0, 0)
                btn:SetPoint("BOTTOM", row, "BOTTOM", 0, 0)
                btn:Show()
            else
                btn:Hide()
            end
        end
    end

    local rowStep = barHeight + barSpacing
    local snappedBarHeight = SnapToPixels(barHeight, win.frame)
    for r = 1, DMY.MAX_POOL do
        local row = win.barRows[r]
        row:SetHeight(snappedBarHeight)
        row:SetPoint("TOPLEFT", win.scrollContent, "TOPLEFT", 0, -SnapToPixels((r - 1) * rowStep, win.frame))
        row:SetPoint("RIGHT", win.scrollContent, "RIGHT", 0, 0)

        -- Icon size matches bar height
        local iconSz = math.min(barHeight, DMY.ICON_SIZE)
        row.icon:SetSize(iconSz, iconSz)

        -- Reposition bar/barBg based on bar mode
        DMY._ApplyBarMode(row, barMode, barLeftOffset)

        -- Position value texts at column offsets
        LayoutRowValueTexts(row)
        LayoutColClickRegions(row)
    end

    -- Layout pinned row
    local pinnedRow = win.pinnedRow
    pinnedRow:SetHeight(snappedBarHeight)
    local iconSz = math.min(barHeight, DMY.ICON_SIZE)
    pinnedRow.icon:SetSize(iconSz, iconSz)
    if pinnedRow.nameContainer then pinnedRow.nameContainer:SetHeight(barHeight) end
    DMY._ApplyBarMode(pinnedRow, barMode, barLeftOffset)
    LayoutRowValueTexts(pinnedRow)
    LayoutColClickRegions(pinnedRow)

    -- Adjust scroll area bottom to leave room for pinned row
    local showPinned = db.showLocalPlayer ~= false
    win.scrollArea:SetPoint("TOPLEFT", win.header, "BOTTOMLEFT", 0, -SnapToPixels(1, win.frame, 1))
    win.scrollArea:SetPoint("BOTTOMRIGHT", win.frame, "BOTTOMRIGHT", 0, showPinned and SnapToPixels(barHeight + 1, win.frame) or 0)
end

--------------------------------------------------------------------------------
-- Refresh Bar Rows — Populate visible rows from merged data
--------------------------------------------------------------------------------

function DMY._RefreshBarRows(windowIndex, comp)
    local win = DMY._windows[windowIndex]
    if not win then return end

    local cfg = DMY._GetWindowConfig(windowIndex)
    if not cfg then return end

    local db = comp.db
    local merged = win.mergedData
    local barHeight = tonumber(db.barHeight) or 22
    local barSpacing = tonumber(db.barSpacing) or 2
    local numColumns = win._numColumns or 1
    local inCombat = DMY._inCombat

    -- Calculate visible rows
    local scrollAreaHeight = win.scrollArea:GetHeight()
    local maxVisible = math.floor(scrollAreaHeight / (barHeight + barSpacing))

    if not merged or #merged.playerOrder == 0 then
        -- No data: hide all rows
        for r = 1, DMY.MAX_POOL do
            win.barRows[r]:Hide()
        end
        win.pinnedRow:Hide()
        win.pinnedSeparator:Hide()
        return
    end

    local totalRows = #merged.playerOrder
    local offset = win.scrollOffset or 0

    -- Update scroll content height
    win.scrollContent:SetHeight(totalRows * (barHeight + barSpacing))

    -- Find local player in data
    local localPlayerKey = nil
    local localPlayerVisible = false

    -- Populate visible rows
    for r = 1, DMY.MAX_POOL do
        local row = win.barRows[r]
        local dataIndex = offset + r
        if dataIndex <= totalRows then
            local key = merged.playerOrder[dataIndex]
            local player = merged.players[key]
            if player then
                -- Check if local player is visible in scroll area
                if player.isLocalPlayer then
                    localPlayerKey = key
                    localPlayerVisible = true
                end

                DMY._PopulateBarRow(row, player, key, cfg, merged, numColumns, inCombat)
                row:Show()
            else
                row:Hide()
            end
        else
            row:Hide()
        end
    end

    -- Find local player key if not in visible range
    if not localPlayerKey then
        for _, key in ipairs(merged.playerOrder) do
            local player = merged.players[key]
            if player and player.isLocalPlayer then
                localPlayerKey = key
                break
            end
        end
    end

    -- Pinned local player row
    local showPinned = db.showLocalPlayer ~= false
    if showPinned and localPlayerKey and not localPlayerVisible then
        local player = merged.players[localPlayerKey]
        if player then
            DMY._PopulateBarRow(win.pinnedRow, player, localPlayerKey, cfg, merged, numColumns, inCombat)
            win.pinnedRow:Show()
            win.pinnedSeparator:Show()
        else
            win.pinnedRow:Hide()
            win.pinnedSeparator:Hide()
        end
    else
        win.pinnedRow:Hide()
        win.pinnedSeparator:Hide()
    end
end

--------------------------------------------------------------------------------
-- Populate a single bar row with player data
--------------------------------------------------------------------------------

function DMY._PopulateBarRow(row, player, key, cfg, merged, numColumns, inCombat)
    local comp = DMY._comp
    local db = comp and comp.db

    -- Persist source identity for drill-down click handler.
    -- OOC: key IS the GUID. Combat: key is "rank_N" placeholder (real GUID is secret).
    if inCombat then
        row._sourceGUID = nil
    else
        row._sourceGUID = (key and not tostring(key):find("^rank_")) and key or nil
    end
    row._sourceName = player.name -- may be secret in combat; consumer must handle
    row._classFilename = player.classFilename
    row._identityKey = player.identityKey
    row._sourceCreatureID = nil -- not currently captured in merged data; nil OK for player sources

    -- Name display (SetText accepts secrets during combat)
    row.nameText:SetText(player.name or "")

    -- Name text color
    local nameSettings = db and db.textNames or {}
    local nameColorMode = nameSettings.colorMode or "default"
    if nameColorMode == "class" and player.classFilename then
        local classColor = addon.ClassColors and addon.ClassColors[player.classFilename]
        if classColor then
            row.nameText:SetTextColor(classColor.r or 1, classColor.g or 1, classColor.b or 1, 1)
        end
    elseif nameColorMode == "custom" and nameSettings.color then
        local c = nameSettings.color
        row.nameText:SetTextColor(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
    else
        row.nameText:SetTextColor(1, 1, 1, 1)
    end

    -- Icon (uses styling module)
    if db then
        DMY._StyleBarRow(row, player, db)
    end

    -- Bar color
    local cr, cg, cb = 0.6, 0.6, 0.6
    if db then
        cr, cg, cb = DMY._GetBarColor(player, db)
    end

    -- Show/hide bar fill and background; mode-aware text parenting
    local barMode = db and db.barMode or "default"
    local showBars = barMode ~= "hidden"
    local barTex = row.bar:GetStatusBarTexture()

    if not showBars then
        row.bar:Hide()
        row.barBg:Hide()
        if barTex then barTex:SetAlpha(1) end
        for vc = 1, DMY.MAX_COLUMNS do
            local vt = row.valueTexts[vc]
            if vt then vt:SetParent(row) end
        end
    elseif barMode == "hollow" then
        row.bar:Show()
        row.barBg:Hide()
        if barTex then barTex:SetAlpha(0) end
        for vc = 1, DMY.MAX_COLUMNS do
            local vt = row.valueTexts[vc]
            if vt then vt:SetParent(row.bar) end
        end
    elseif barMode == "thin" then
        row.bar:Show()
        row.barBg:Show()
        if barTex then barTex:SetAlpha(1) end
        for vc = 1, DMY.MAX_COLUMNS do
            local vt = row.valueTexts[vc]
            if vt then vt:SetParent(row) end
        end
    else
        -- Default mode
        row.bar:Show()
        row.barBg:Show()
        if barTex then barTex:SetAlpha(1) end
        for vc = 1, DMY.MAX_COLUMNS do
            local vt = row.valueTexts[vc]
            if vt then vt:SetParent(row.bar) end
        end
    end

    -- Rank number — sits to the LEFT of the name, just after the icon.
    if row.rankText then
        if db and db.hideRankNumbers then
            row.rankText:SetText("")
            row.rankText:Hide()
        else
            row.rankText:SetText(player.rank and (player.rank .. ".") or "")
            row.rankText:ClearAllPoints()
            row.rankText:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
            row.rankText:Show()
        end
    end

    -- Single full-width bar: represents primary column data.
    local primaryDef = cfg.columns[1] and DMY.COLUMN_FORMATS[cfg.columns[1].format]
    if primaryDef and showBars then
        local meterType = primaryDef.primary or primaryDef.meterType
        local maxAmount = merged.maxAmounts[meterType] or 1

        row.bar:SetStatusBarColor(cr, cg, cb)

        if inCombat then
            local val = player.values[meterType]
            if val then
                row.bar:SetMinMaxValues(0, maxAmount)
                row.bar:SetValue(val.totalAmount or 0)
            end
        else
            local val = player.values[meterType]
            local fillVal = val and val.totalAmount or 0
            row.bar:SetMinMaxValues(0, maxAmount)
            row.bar:SetValue(fillVal)
        end

        -- Background styling
        if db then
            local bgColorMode = db.barBgColorMode or "default"
            local bgOpacity = (tonumber(db.barBackgroundOpacity) or 80) / 100
            if bgColorMode == "custom" and db.barBgCustomColor then
                local c = db.barBgCustomColor
                row.barBg:SetColorTexture(c[1] or 0.1, c[2] or 0.1, c[3] or 0.1, bgOpacity)
            else
                row.barBg:SetColorTexture(0.1, 0.1, 0.1, bgOpacity)
            end
        end
    end

    -- Column value texts
    for c = 1, numColumns do
        local vt = row.valueTexts[c]
        if not vt then break end

        local colDef = cfg.columns[c]
        if colDef then
            if inCombat then
                local def = DMY.COLUMN_FORMATS[colDef.format]
                if def then
                    if c == 1 then
                        -- Primary column: use session-level combatSources values
                        local mt = def.primary or def.meterType
                        local val = player.values[mt]
                        if val then
                            if def.primary then
                                local pAbbr = DMY._UnifiedAbbreviate(val[def.primaryField] or 0)
                                local sAbbr = DMY._UnifiedAbbreviate(val[def.secondaryField] or 0)
                                local ok = pcall(vt.SetFormattedText, vt, "%s (%s)", pAbbr, sAbbr)
                                if not ok then
                                    vt:SetText(pAbbr)
                                end
                            else
                                vt:SetText(DMY._UnifiedAbbreviate(val[def.valueField or "totalAmount"] or 0))
                            end
                        end
                    else
                        -- Secondary column: use stored-GUID source query data
                        local secData = merged.secondaryByIdentity
                        local mt = def.primary or def.meterType
                        local idLookup = secData and player.identityKey and secData[player.identityKey]
                        local secTotal = idLookup and idLookup[mt]

                        if secTotal then
                            vt:SetText(DMY._UnifiedAbbreviate(secTotal))
                        else
                            vt:SetText("\226\128\148") -- em dash
                        end
                    end
                end
            else
                -- OOC: formatted text
                vt:SetText(DMY._FormatColumnValue(player, colDef.format))
            end

            -- Apply value text color and opacity (same for combat and OOC)
            vt:SetAlpha(1)
            local valSettings = db and db.textValues or {}
            local valColorMode = valSettings.colorMode or "default"
            if valColorMode == "custom" and valSettings.color then
                local vc = valSettings.color
                vt:SetTextColor(vc[1] or 1, vc[2] or 1, vc[3] or 1, vc[4] or 1)
            else
                vt:SetTextColor(1, 1, 1, 1)
            end
        end
    end
end
