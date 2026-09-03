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
-- Column Width Fractions
--------------------------------------------------------------------------------

-- Per-column widths are stored as fractions of the column area on each column
-- entry (cfg.columns[c].widthFraction), set only by dragging the Edit Mode
-- divider lines. nil = equal split, so existing profiles need no migration.
--
-- The name column is stored separately as cfg.nameWidthFraction, a fraction of
-- the whole width pool (frameWidth - NAME_AREA_LEFT), because it sits left of
-- the column area those per-column fractions divide up. nil falls back to the
-- old fixed 113px name block at any frame width, so an undragged window keeps
-- the exact layout it had before the name column became draggable.

-- legacyPx: the name column width to fall back to, in the caller's pixel space
-- (the settings preview runs the same math at its own scale).
function DMY._GetNameFraction(cfg, pool, legacyPx)
    pool = tonumber(pool)
    if not pool or pool <= 0 then return 0 end
    local f = cfg and tonumber(cfg.nameWidthFraction)
    if not f or f <= 0 or f >= 1 then
        legacyPx = tonumber(legacyPx) or (DMY.BAR_LEFT_OFFSET - DMY.NAME_AREA_LEFT)
        f = legacyPx / pool
    end
    return math.max(0, math.min(1, f))
end

function DMY._GetColumnFractions(cfg, numColumns)
    local fractions = {}
    local sum = 0
    for c = 1, numColumns do
        local col = cfg.columns and cfg.columns[c]
        local f = col and tonumber(col.widthFraction)
        if not f or f <= 0 then f = 1 / numColumns end
        fractions[c] = f
        sum = sum + f
    end
    if sum <= 0 then sum = 1 end
    for c = 1, numColumns do
        fractions[c] = fractions[c] / sum
    end
    return fractions
end

-- Rescale stored fractions to sum 1.0 after a column add/remove. Windows still
-- in equal-split mode (no stored fractions anywhere) are left untouched.
function DMY.NormalizeColumnFractions(cfg)
    if not cfg or not cfg.columns then return end
    local n = #cfg.columns
    if n == 0 then return end
    local sum, any = 0, false
    for _, col in ipairs(cfg.columns) do
        local f = tonumber(col.widthFraction)
        if f and f > 0 then
            any = true
            sum = sum + f
        else
            sum = sum + (1 / n)
        end
    end
    if not any or sum <= 0 then return end
    for _, col in ipairs(cfg.columns) do
        local f = tonumber(col.widthFraction)
        if not f or f <= 0 then f = 1 / n end
        col.widthFraction = f / sum
    end
end

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

    -- Column area: everything right of the name column. The name column's own
    -- width is a fraction of the pool too, so its right edge (edge 0) is
    -- dragged exactly like the interior boundaries.
    local nameLeft = DMY.NAME_AREA_LEFT
    local pool = math.max(fw - nameLeft, 1)
    local left = win._dragNameEdge
    if not left then
        left = nameLeft + pool * DMY._GetNameFraction(cfg, pool)
    end
    local maxLeft = fw - numColumns * DMY.MIN_COL_WIDTH
    local minLeft = nameLeft + DMY.MIN_NAME_WIDTH
    if maxLeft < minLeft then maxLeft = minLeft end
    left = SnapToPixels(math.max(minLeft, math.min(maxLeft, left)), win.frame)
    local available = math.max(fw - left, 1)

    -- Cumulative pixel edges from the stored fractions (equal split when
    -- unset). A live divider drag overrides via win._dragFractions. The last
    -- column absorbs the rounding leftovers so the edges always tile [left, fw].
    local fractions = win._dragFractions or DMY._GetColumnFractions(cfg, numColumns)
    local edges = { [0] = left }
    local acc = 0
    for c = 1, numColumns - 1 do
        acc = acc + (fractions[c] or (1 / numColumns))
        edges[c] = SnapToPixels(left + available * acc, win.frame)
    end
    edges[numColumns] = fw

    win._colEdges = edges
    win._numColumns = numColumns

    -- Position column header cells; content (text or icon) is hard-clipped
    -- inside them. _ApplyColumnHeaderContent raises _headerLines to 2 when a
    -- dual-metric label stacks, and the header row grows to fit it.
    win._headerLines = 1
    for c = 1, DMY.MAX_COLUMNS do
        local clip = win.columnHeaderClips and win.columnHeaderClips[c]
        local cr = win.columnClickRegions and win.columnClickRegions[c]
        if c <= numColumns and clip then
            clip:ClearAllPoints()
            clip:SetPoint("LEFT", win.header, "LEFT", edges[c - 1] + 1, 0)
            clip:SetPoint("RIGHT", win.header, "LEFT", edges[c] - 1, 0)
            clip:SetPoint("TOP", win.header, "TOP", 0, 0)
            clip:SetPoint("BOTTOM", win.header, "BOTTOM", 0, 0)
            DMY._ApplyColumnHeaderContent(win, c, cfg.columns[c] and cfg.columns[c].format, comp)
            clip:Show()
            if cr then cr:Show() end
        else
            if clip then clip:Hide() end
            if cr then cr:Hide() end
        end
    end

    -- The session title is bounded by edge 0, so refit it here rather than
    -- waiting for the next timer tick (matters during a live divider drag).
    if DMY._UpdateTimerText then
        DMY._UpdateTimerText(windowIndex)
    end

    -- Keep Edit Mode divider strips glued to the boundaries
    if DMY.Dividers and DMY.Dividers.Refresh then
        DMY.Dividers.Refresh()
    end
end

--------------------------------------------------------------------------------
-- Column header content — text (regular/abbreviated) or metric icon
--------------------------------------------------------------------------------

function DMY._ApplyColumnHeaderContent(win, c, formatKey, comp)
    local ch = win.columnHeaders[c]
    local icon = win.columnHeaderIcons and win.columnHeaderIcons[c]
    if not ch then return end

    local db = comp and comp.db
    local mode = (db and db.columnHeaderMode) or "regular"
    local def = formatKey and DMY.COLUMN_FORMATS[formatKey]

    local iconSpec
    if mode == "icons" and def and def.iconKind and DMY.HEADER_ICONS then
        iconSpec = DMY.HEADER_ICONS[def.iconKind]
    end

    if iconSpec and icon then
        ch:SetText("")
        ch:Hide()
        DMY._ConfigureHeaderIcon(icon, iconSpec, comp)
        icon:Show()
    else
        if icon then icon:Hide() end
        local text
        if mode == "abbreviated" and def and def.headerAbbrev then
            text = def.headerAbbrev
        else
            text = DMY._GetColumnHeader(formatKey)
        end

        -- Dual-metric formats stack over two lines: the primary metric, then
        -- its parenthesised secondary below. The FontString is CENTER-anchored
        -- with CENTER justification, so the shorter line centers over the
        -- longer one.
        local stacked
        if def and def.primary ~= nil and def.secondary ~= nil then
            stacked = DMY._StackHeaderLabel(text)
        end
        if stacked then
            ch:SetWordWrap(true)
            ch:SetMaxLines(2)
            ch:SetText(stacked)
            win._headerLines = 2
        else
            ch:SetWordWrap(false)
            ch:SetMaxLines(1)
            ch:SetText(text)
        end
        ch:Show()
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

    -- Per-column pixel edges computed by _CalculateColumnWidths. Edge 0 is the
    -- dragged name/column boundary, so the bars start there.
    local edges = win._colEdges or { [0] = DMY.BAR_LEFT_OFFSET, [numColumns] = fw }
    local barLeftOffset = edges[0] or DMY.BAR_LEFT_OFFSET

    -- Value texts sit inside hard-clipping column cells: single CENTER anchor,
    -- no width — over-long strings clip at both cell edges instead of
    -- ellipsizing or overflowing into the neighboring column
    local function LayoutRowValueTexts(row)
        for c = 1, DMY.MAX_COLUMNS do
            local clip = row.colClips and row.colClips[c]
            local vt = row.valueTexts[c]
            if c <= numColumns and clip and edges[c] then
                clip:ClearAllPoints()
                clip:SetPoint("LEFT", row, "LEFT", edges[c - 1] + 1, 0)
                clip:SetPoint("RIGHT", row, "LEFT", edges[c] - 1, 0)
                clip:SetPoint("TOP", row, "TOP", 0, 0)
                clip:SetPoint("BOTTOM", row, "BOTTOM", 0, 0)
                clip:Show()
                if vt then vt:Show() end
            else
                if clip then clip:Hide() end
                if vt then vt:Hide() end
            end
        end
    end

    -- The name clip stretches from the icon to the name column's right edge,
    -- less the gutter that separates it from column 1.
    local function LayoutNameClip(row)
        if not row.nameClip then return end
        row.nameClip:SetPoint("RIGHT", row, "LEFT", barLeftOffset - DMY.NAME_GUTTER, 0)
    end

    local barMode = db.barMode or "default"

    -- Position per-column click overlays (multi-column drill-down dispatch).
    -- Hidden for single-column windows; row's OnMouseUp handles those.
    local function LayoutColClickRegions(row)
        if not row.colClickRegions then return end
        for c = 1, DMY.MAX_COLUMNS do
            local btn = row.colClickRegions[c]
            if not btn then break end
            if numColumns >= 2 and c <= numColumns and edges[c] then
                btn:ClearAllPoints()
                btn:SetPoint("LEFT",  row, "LEFT", edges[c - 1], 0)
                btn:SetPoint("RIGHT", row, "LEFT", edges[c], 0)
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

        -- Position the name clip and the value texts at column offsets
        LayoutNameClip(row)
        LayoutRowValueTexts(row)
        LayoutColClickRegions(row)
    end

    -- Layout pinned row
    local pinnedRow = win.pinnedRow
    pinnedRow:SetHeight(snappedBarHeight)
    local iconSz = math.min(barHeight, DMY.ICON_SIZE)
    pinnedRow.icon:SetSize(iconSz, iconSz)
    DMY._ApplyBarMode(pinnedRow, barMode, barLeftOffset)
    LayoutNameClip(pinnedRow)
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
    -- Display name: realm-stripped when Hide Realm Names is on. Drilldown
    -- titles read _sourceName, so they inherit the stripped form.
    local displayName = player.name
    if db and db.hideRealmNames then
        displayName = DMY._ResolveDisplayName(player, key, merged) or player.name
    end
    row._sourceName = displayName -- may be secret in combat; consumer must handle
    row._classFilename = player.classFilename
    row._identityKey = player.identityKey
    row._isLocalPlayer = player.isLocalPlayer
    row._sourceCreatureID = nil -- not currently captured in merged data; nil OK for player sources

    -- Name display (SetText accepts secrets during combat)
    row.nameText:SetText(displayName or "")

    -- Name text color
    local nameSettings = addon:ResolveComponentSubTable(DMY._comp, "textNames") or {}
    local nameColorMode = nameSettings.colorMode or "default"
    if nameColorMode == "class" and player.classFilename then
        local classColor = addon.GetClassColorObj(player.classFilename)
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

    -- Show/hide bar fill and background. Value texts live in per-column clip
    -- cells at a fixed frame level above the StatusBar, so no mode-aware
    -- reparenting is needed to keep text drawing over the bar fill.
    local barMode = db and db.barMode or "default"
    local showBars = barMode ~= "hidden"
    local barTex = row.bar:GetStatusBarTexture()

    if not showBars then
        row.bar:Hide()
        row.barBg:Hide()
        if barTex then barTex:SetAlpha(1) end
    elseif barMode == "hollow" then
        row.bar:Show()
        row.barBg:Hide()
        if barTex then barTex:SetAlpha(0) end
    else
        -- Thin and Default modes
        row.bar:Show()
        row.barBg:Show()
        if barTex then barTex:SetAlpha(1) end
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
                    -- Resolve this column's { totalAmount, amountPerSecond } record,
                    -- then render it identically whatever the column index. Every
                    -- gate reads a plain map; the (possibly secret) amount only ever
                    -- flows into UnifiedAbbreviate -> SetText/SetFormattedText.
                    local mt = def.primary or def.meterType
                    local primaryType = primaryDef and (primaryDef.primary or primaryDef.meterType)
                    local val, blocked
                    if c == 1 or mt == primaryType then
                        -- The row already carries the primary session's record for
                        -- this meter type, so no secondary query was issued for it.
                        val = player.values[mt]
                    else
                        local ikey = player.identityKey
                        if ikey and merged.identityCollisions and merged.identityCollisions[ikey] then
                            blocked = "\226\128\148" -- em dash: ambiguous (class+spec collision)
                        elseif merged.secondaryQueried and merged.secondaryQueried[mt] then
                            local pres = ikey and merged.secondaryPresence and merged.secondaryPresence[ikey]
                            if pres and pres[mt] then
                                val = merged.secondaryByIdentity[ikey][mt]
                            else
                                blocked = "0" -- absent from that metric's session = zero
                            end
                        else
                            blocked = "\226\128\148" -- em dash: session query failed
                        end
                    end

                    if blocked then
                        vt:SetText(blocked)
                    elseif val then
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
                end
            else
                -- OOC: formatted text
                vt:SetText(DMY._FormatColumnValue(player, colDef.format))
            end

            -- Apply value text color and opacity (same for combat and OOC)
            vt:SetAlpha(1)
            local valSettings = addon:ResolveComponentSubTable(DMY._comp, "textValues") or {}
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
