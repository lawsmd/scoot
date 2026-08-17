-- damagemetersY/combat.lua - Combat mode transitions, segment snapshots, post-combat refresh
local _, addon = ...
local DMY = addon.DamageMetersY

--------------------------------------------------------------------------------
-- Combat Mode Transitions
--------------------------------------------------------------------------------

function DMY._EnterCombatMode()
    DMY._inCombat = true
    DMY._combatStartTime = GetTime()

    for i = 1, DMY.MAX_WINDOWS do
        local win = DMY._windows[i]
        if win and win.mergedData then
            win._preCombatDuration = win.mergedData.durationSeconds or 0
        end
    end
end

function DMY._ExitCombatMode()
    DMY._inCombat = false
    DMY._combatStartTime = 0
    -- Full refresh happens synchronously from REGEN_ENABLED handler
end

--------------------------------------------------------------------------------
-- Combat Update — Primary column + live secondary via stored-GUID source queries
--------------------------------------------------------------------------------

function DMY._UpdateWindowCombat(windowIndex)
    local win = DMY._windows[windowIndex]
    if not win or not win.frame:IsShown() then return end

    local cfg = DMY._GetWindowConfig(windowIndex)
    if not cfg or not cfg.enabled then return end

    local comp = DMY._comp
    if not comp then return end

    -- Query merged data in combat mode (primary + secondary via stored-GUID bypass)
    local merged = DMY._QueryMergedData(cfg.sessionType, cfg.sessionID, cfg.columns, true)
    if not merged then return end

    -- Store combat merged data
    win.mergedData = merged

    -- Refresh the bar rows display
    DMY._RefreshBarRows(windowIndex, comp)

    -- Update header timer
    DMY._UpdateTimerText(windowIndex)
end

--------------------------------------------------------------------------------
-- OOC Full Update — All columns, GUID-correlated
--------------------------------------------------------------------------------

function DMY._UpdateWindowOOC(windowIndex)
    local win = DMY._windows[windowIndex]
    if not win or not win.frame:IsShown() then return end

    local cfg = DMY._GetWindowConfig(windowIndex)
    if not cfg or not cfg.enabled then return end

    local comp = DMY._comp
    if not comp then return end

    -- Query merged data OOC (all columns, GUID correlated)
    local merged = DMY._QueryMergedData(cfg.sessionType, cfg.sessionID, cfg.columns, false)
    if not merged then
        -- No data — clear display
        win.mergedData = nil
        DMY._RefreshBarRows(windowIndex, comp)
        DMY._UpdateTimerText(windowIndex)
        return
    end

    win.mergedData = merged

    -- Refresh display
    DMY._RefreshBarRows(windowIndex, comp)
    DMY._UpdateTimerText(windowIndex)
end

--------------------------------------------------------------------------------
-- Full Refresh All Windows — Called SYNCHRONOUSLY from REGEN_ENABLED
--------------------------------------------------------------------------------

function DMY._FullRefreshAllWindows()
    if not DMY._initialized then return end

    -- Ensure column header colors match DB settings
    local db = DMY._comp and DMY._comp.db
    if db then
        local headerStyle = addon:ResolveComponentSubTable(DMY._comp, "textHeaders") or {}
        local useCustom = headerStyle.colorMode == "custom" and headerStyle.color
        for i = 1, DMY.MAX_WINDOWS do
            local win = DMY._windows[i]
            if win then
                for c = 1, DMY.MAX_COLUMNS do
                    local ch = win.columnHeaders[c]
                    local hr, hg, hb, ha = 0.8, 0.8, 0.8, 1
                    if useCustom then
                        local hc = headerStyle.color
                        hr, hg, hb, ha = hc[1] or 0.8, hc[2] or 0.8, hc[3] or 0.8, hc[4] or 1
                    end
                    if ch then
                        ch:SetAlpha(1)
                        ch:SetTextColor(hr, hg, hb, ha)
                    end
                    -- Icons header mode: keep the metric icon tint in sync
                    local hi = win.columnHeaderIcons and win.columnHeaderIcons[c]
                    if hi and hi:IsShown() then
                        hi:SetVertexColor(hr, hg, hb, ha)
                    end
                end
            end
        end
    end

    -- One cache rebuild per refresh cycle (drilldown support), never per
    -- window — per-window rebuilds let the last window's session clobber
    -- the shared cache (the multi-column em-dash bug).
    DMY._RebuildGUIDCache()
    DMY._RebuildRosterNames()

    for i = 1, DMY.MAX_WINDOWS do
        local cfg = DMY._GetWindowConfig(i)
        if cfg and cfg.enabled then
            DMY._UpdateWindowOOC(i)
        end
    end
end

--------------------------------------------------------------------------------
-- Update All Windows (throttled, called from event handler)
--------------------------------------------------------------------------------

function DMY._UpdateAllWindows()
    if not DMY._initialized then return end

    local inCombat = DMY._inCombat
    if not inCombat then
        DMY._RebuildGUIDCache()
    end
    for i = 1, DMY.MAX_WINDOWS do
        local cfg = DMY._GetWindowConfig(i)
        if cfg and cfg.enabled then
            if inCombat then
                DMY._UpdateWindowCombat(i)
            else
                DMY._UpdateWindowOOC(i)
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Timer Text
--------------------------------------------------------------------------------

function DMY._UpdateTimerText(windowIndex)
    local win = DMY._windows[windowIndex]
    if not win then return end

    local cfg = DMY._GetWindowConfig(windowIndex)
    if not cfg then return end

    local label = DMY._GetSessionLabel(cfg.sessionType, cfg.sessionID, cfg._sessionName)
    local duration

    if cfg.sessionID then
        -- Specific segment: fixed duration (use cached pre-combat value during combat)
        if DMY._inCombat then
            duration = win._preCombatDuration or 0
        else
            duration = win.mergedData and win.mergedData.durationSeconds
        end
    else
        -- Overall / Current: session-driven API, non-secret during combat.
        -- Survives player death/resurrect because it tracks the session, not the player.
        local ok, dur = pcall(C_DamageMeter.GetSessionDurationSeconds, cfg.sessionType)
        if ok and type(dur) == "number" then
            duration = dur
        elseif not DMY._inCombat then
            duration = win.mergedData and win.mergedData.durationSeconds
        else
            local elapsed = GetTime() - (DMY._combatStartTime or GetTime())
            local preCombat = win._preCombatDuration or 0
            duration = (cfg.sessionType == 0) and (preCombat + elapsed) or elapsed
        end
    end

    -- Compute timer string early (needed for title width calculation)
    local comp = DMY._comp
    local db = comp and comp.db
    local timerStr = ""
    if duration and duration > 0 then
        timerStr = "[" .. DMY._FormatDuration(duration) .. "]"
    end
    if win.timerText then
        win.timerText:SetText(timerStr)
    end

    -- Update title text
    local isVertical = db and db.verticalTitleMode

    if isVertical and win.verticalTitle then
        -- Vertical title: stack characters vertically, all caps
        local stacked = label:upper():gsub(".", "%1\n"):sub(1, -2)
        win.verticalTitle:SetText(stacked)
        win.verticalTitle:Show()
        if win.titleText then
            win.titleText:SetText("")
            win.titleText:SetWidth(0)
        end
        win.header:SetHeight(DMY._SnapToPixels(DMY.HEADER_HEIGHT, win.frame))
    else
        if win.verticalTitle then win.verticalTitle:Hide() end
        if win.titleText then
            local isSegment = cfg.sessionID ~= nil
            if isSegment then
                -- Calculate available title width to prevent column header overlap
                local fw = tonumber(cfg.frameWidth or (db and db.frameWidth)) or 350

                -- Right boundary: the column area's left edge. Headers are
                -- center-anchored inside their cells now, so geometry replaces
                -- the old GetStringWidth measurement (which the Icons header
                -- mode has no text for anyway).
                local rightBound
                local clip = win.columnHeaderClips and win.columnHeaderClips[1]
                if clip and clip:IsShown() then
                    rightBound = (win._colEdges and win._colEdges[0] or DMY.BAR_LEFT_OFFSET) - 8
                else
                    rightBound = fw - 8
                end

                -- Reserve space for timer text
                local timerW = 0
                if timerStr ~= "" and win.timerText then
                    timerW = (win.timerText:GetStringWidth() or 0) + 8
                end

                local maxTitleWidth = rightBound - 26 - timerW
                if maxTitleWidth < 40 then maxTitleWidth = 40 end

                -- Apply constrained title (word wrap handles multi-word names)
                win.titleText:SetWidth(maxTitleWidth)
                win.titleText:SetText(label)

                -- Single long word without spaces: manual "..." truncation
                if not label:find(" ") then
                    local fullW = win.titleText:GetStringWidth()
                    if fullW and fullW > maxTitleWidth then
                        local trunc = label
                        while #trunc > 1 do
                            trunc = trunc:sub(1, -2)
                            win.titleText:SetText(trunc .. "...")
                            local tw = win.titleText:GetStringWidth()
                            if tw and tw <= maxTitleWidth then break end
                        end
                    end
                end

                -- Expand header height if title wrapped to 2 lines
                local titleH = win.titleText:GetStringHeight() or 15
                if titleH > 20 then
                    win.header:SetHeight(DMY._SnapToPixels(math.max(DMY.HEADER_HEIGHT, titleH + 8), win.frame))
                else
                    win.header:SetHeight(DMY._SnapToPixels(DMY.HEADER_HEIGHT, win.frame))
                end
            else
                -- Overall/Current: standard single-line layout
                win.titleText:SetWidth(0)
                win.titleText:SetText(label)
                win.header:SetHeight(DMY._SnapToPixels(DMY.HEADER_HEIGHT, win.frame))
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Reset Handler
--------------------------------------------------------------------------------

function DMY._HandleReset()
    if DMY._CloseDrilldown then DMY._CloseDrilldown() end
    -- Sessions are gone; identity data from the previous group must not
    -- survive to create stale GUIDs or false collisions. Pre-reset recapIDs
    -- must likewise never label post-reset deaths.
    wipe(DMY._guidCache)
    wipe(DMY._identityToGUID)
    wipe(DMY._recapSegmentIndex)
    DMY._recapSegmentIndexDirty = true
    for i = 1, DMY.MAX_WINDOWS do
        local win = DMY._windows[i]
        if win then
            win.mergedData = nil
            win.scrollOffset = 0
            win._preCombatDuration = 0
            if DMY._comp then
                DMY._RefreshBarRows(i, DMY._comp)
                DMY._UpdateTimerText(i)
            end
        end
    end
end
