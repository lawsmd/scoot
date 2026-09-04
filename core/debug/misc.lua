-- misc.lua - Assorted /scoot debug dumps that have no module of their own
local addonName, addon = ...

--------------------------------------------------------------------------------
-- Quest Log Debug Dump
--------------------------------------------------------------------------------

local function DebugDumpQuests()
    local ok, numEntries, numQuests = pcall(C_QuestLog.GetNumQuestLogEntries)
    if not ok or type(numEntries) ~= "number" then
        addon.DebugShowWindow("Quest Debug", "Failed to get quest log entries")
        return
    end
    local ok2, maxQuests = pcall(C_QuestLog.GetMaxNumQuestsCanAccept)

    local classNames = {}
    if Enum and Enum.QuestClassification then
        for k, v in pairs(Enum.QuestClassification) do
            classNames[v] = k
        end
    end

    local lines = {}
    local countAll, countFiltered = 0, 0
    table.insert(lines, "== Quest Log Debug ==")
    table.insert(lines, string.format("numEntries=%s  numQuests(API)=%s  maxCanAccept=%s", tostring(numEntries), tostring(numQuests), tostring(maxQuests)))
    table.insert(lines, "")
    table.insert(lines, "idx | questID | classification | flags | title")
    table.insert(lines, string.rep("-", 90))

    for i = 1, numEntries do
        local info = C_QuestLog.GetInfo(i)
        if info and not info.isHeader then
            countAll = countAll + 1

            local apiIsTask = C_QuestLog.IsQuestTask(info.questID)
            local apiIsWorld = C_QuestLog.IsWorldQuest(info.questID)
            local apiIsBounty = C_QuestLog.IsQuestBounty(info.questID)
            local apiIsCalling = C_QuestLog.IsQuestCalling and C_QuestLog.IsQuestCalling(info.questID)

            local flags = {}
            if info.isHidden then table.insert(flags, "hidden") end
            if info.isBounty then table.insert(flags, "bounty") end
            if info.isTask then table.insert(flags, "task") end
            if info.isInternalOnly then table.insert(flags, "internal") end
            if info.startEvent then table.insert(flags, "startEvent") end
            if apiIsWorld then table.insert(flags, "API:world") end
            if apiIsTask and not info.isTask then table.insert(flags, "API:task") end
            if apiIsBounty and not info.isBounty then table.insert(flags, "API:bounty") end
            if apiIsCalling then table.insert(flags, "API:calling") end
            if info.frequency and info.frequency > 0 then
                table.insert(flags, "freq=" .. info.frequency)
            end

            local excluded = info.isHidden or info.isBounty or info.isTask or apiIsWorld or apiIsTask
            if not excluded and info.questClassification then
                local class = info.questClassification
                if class == Enum.QuestClassification.BonusObjective
                    or class == Enum.QuestClassification.WorldQuest
                    or class == Enum.QuestClassification.Calling
                    or class == Enum.QuestClassification.Meta
                    or class == Enum.QuestClassification.Recurring
                    or class == Enum.QuestClassification.Campaign then
                    excluded = true
                end
            end
            if not excluded then countFiltered = countFiltered + 1 end
            local mark = excluded and "[EXCLUDED]" or "[COUNTED]"

            local className = classNames[info.questClassification] or tostring(info.questClassification or "?")

            table.insert(lines, string.format(
                "%3d | %6d | %-16s | %-40s | %s %s",
                i, info.questID or 0, className,
                #flags > 0 and table.concat(flags, ", ") or "-",
                info.title or "???", mark
            ))
        end
    end

    table.insert(lines, "")
    table.insert(lines, string.format("Total non-header: %d | Current filter count: %d | Cap: %s",
        countAll, countFiltered, tostring(maxQuests)))

    addon.DebugShowWindow("Quest Log Debug", table.concat(lines, "\n"))
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Damage Meter Export
-- ─────────────────────────────────────────────────────────────────────────────

function addon.DebugExportDamageMeters(sessionOverride)
    -- Guards
    if InCombatLockdown() then
        addon:Print("Export only available out of combat.")
        return
    end

    -- Determine session type + primary meter type from window 1
    local sessionType = Enum.DamageMeterSessionType.Overall
    local primaryMeterType = Enum.DamageMeterType.Dps
    if DamageMeter and DamageMeter.sessionWindows and DamageMeter.sessionWindows[1] then
        local win = DamageMeter.sessionWindows[1]
        if win.sessionType ~= nil then sessionType = win.sessionType end
        if win.damageMeterType ~= nil then primaryMeterType = win.damageMeterType end
    end

    -- Command-line session override
    if sessionOverride then
        local overrides = {
            overall = Enum.DamageMeterSessionType.Overall,
            current = Enum.DamageMeterSessionType.Current,
            expired = Enum.DamageMeterSessionType.Expired,
        }
        local st = overrides[string.lower(sessionOverride)]
        if st then sessionType = st end
    end

    -- Use shared data gathering function
    local data, err = addon.GatherDamageMeterExportData(sessionType, primaryMeterType)
    if not data then
        addon:Print(err or "No export data available.")
        return
    end

    -- Dynamic name column width
    local nameW = 16
    for _, guid in ipairs(data.playerOrder) do
        local n = #(data.players[guid].name or "")
        if n > nameW then nameW = n end
    end
    nameW = math.min(nameW, 20)
    local colW = 12

    -- Build output
    local lines = {}
    table.insert(lines, string.format("Scoot Damage Meter Export  --  %s (%s)", data.sessionLabel, data.FormatDuration(data.duration)))

    local totalW = 4 + nameW + (#data.columns * (colW + 1))
    local sep = string.rep("-", totalW)
    table.insert(lines, sep)

    -- Header row
    local hdr = { string.format("%-3s %-" .. nameW .. "s", "#", "Player") }
    for _, h in ipairs(data.columnNames) do
        table.insert(hdr, string.format("%" .. colW .. "s", h))
    end
    table.insert(lines, table.concat(hdr, " "))
    table.insert(lines, sep)

    -- Data rows
    for rank, guid in ipairs(data.playerOrder) do
        local p = data.players[guid]
        local name = p.name or "Unknown"
        if #name > nameW then name = string.sub(name, 1, nameW) end

        local row = { string.format("%-3d %-" .. nameW .. "s", rank, name) }
        for _, mt in ipairs(data.columns) do
            table.insert(row, string.format("%" .. colW .. "s", data.GetDisplayValue(guid, mt)))
        end
        local line = table.concat(row, " ")
        if p.isLocalPlayer then line = line .. "  *" end
        table.insert(lines, line)
    end

    table.insert(lines, sep)
    table.insert(lines, string.format("Instance: %s | Players: %d | %s",
        data.instanceLabel, data.playerCount, data.timestamp))

    addon.DebugShowWindow("Damage Meter Export", table.concat(lines, "\n"))
end

addon:RegisterDebugCommand({
    name = "quests", help = "quest log dump",
    handler = function() DebugDumpQuests() end,
})
