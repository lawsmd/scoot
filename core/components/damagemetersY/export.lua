-- damagemetersY/export.lua - Export pipeline: column types, data gathering, chat output
local _, addon = ...
local DMY = addon.DamageMetersY

--------------------------------------------------------------------------------
-- Damage Meters Y Export Pipeline
--------------------------------------------------------------------------------

--- Export window data to the High Score arcade display.
function DMY._ExportToWindow(windowIndex)
    if InCombatLockdown() then
        if addon.Print then addon:Print("Export not available during combat.") end
        return
    end

    local cfg = DMY._GetWindowConfig(windowIndex)
    if not cfg then return end

    local sessionType = cfg.sessionType or (not cfg.sessionID and 0) or nil
    local primaryMeterType = DMY._GetPrimaryMeterType(cfg)

    local data, err = addon.GatherDamageMeterExportData(sessionType, primaryMeterType, cfg.sessionID)
    if not data then
        if addon.Print then addon:Print(err or "No export data available.") end
        return
    end

    if cfg.sessionID and cfg._sessionName then
        data.sessionLabel = cfg._sessionName
    end

    if addon.ShowHighScoreWindow then
        addon.ShowHighScoreWindow(data)
    end
end

--- Export to a specific chat channel with specified line count.
function DMY._ExportToChatChannel(windowIndex, channel, lineCount)
    if InCombatLockdown() then
        if addon.Print then addon:Print("Export not available during combat.") end
        return
    end

    local cfg = DMY._GetWindowConfig(windowIndex)
    if not cfg then return end

    local sessionType = cfg.sessionType or (not cfg.sessionID and 0) or nil
    local primaryMeterType = DMY._GetPrimaryMeterType(cfg)
    lineCount = lineCount or 5

    local data, err = addon.GatherDamageMeterExportData(sessionType, primaryMeterType, cfg.sessionID)
    if not data then
        if addon.Print then addon:Print(err or "No export data available.") end
        return
    end

    if cfg.sessionID and cfg._sessionName then
        data.sessionLabel = cfg._sessionName
    end

    local messages = {}
    local headerName = data.columnNames[1] or "DPS"
    table.insert(messages, string.format("Scoot - %s (%s) [%s]:", headerName, data.sessionLabel, data.FormatDuration(data.duration)))

    local count = math.min(lineCount, #data.playerOrder)
    for i = 1, count do
        local guid = data.playerOrder[i]
        local p = data.players[guid]
        local mt = data.columns[1]
        local val = data.GetDisplayValue(guid, mt)
        local info = addon.FormatPlayerSpecInfo(p)
        local nameStr = info and (p.name .. " " .. info) or p.name
        table.insert(messages, string.format("#%d. %s - %s", i, nameStr, val))
    end

    for _, msg in ipairs(messages) do
        SendChatMessage(msg, channel)
    end
end
