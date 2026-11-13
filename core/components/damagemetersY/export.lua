-- damagemetersY/export.lua - Export pipeline: the data gatherer, the zone an
-- export names, the High Score window and chat output
local _, addon = ...
local DMY = addon.DamageMetersY

--------------------------------------------------------------------------------
-- Damage Meters Y Export Pipeline
--
-- The gatherer and the zone record below are the one export data path. Every
-- caller reads them at the moment of an export: this meter's gear menu, the
-- native meter's export button where an addon carries that meter, and the
-- debug export.
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- Spec Icon -> Name Resolver
--------------------------------------------------------------------------------

local specIconToName = nil

-- Built from the shared spec catalog (core/specs.lua), which reads the spec
-- getters off their 12.x namespace first. An empty build is not kept: the
-- catalog is empty until the class data loads.
local function GetSpecNameFromIconID(iconID)
    iconID = DMY._PlainNumber(iconID)
    if not iconID or iconID == 0 then return nil end
    if not specIconToName then
        local _, byId = addon.Specs.Buckets()
        local map = {}
        for _, spec in pairs(byId or {}) do
            if spec.icon and spec.name then
                map[spec.icon] = spec.name
            end
        end
        if not next(map) then return nil end
        specIconToName = map
    end
    return specIconToName[iconID]
end

--------------------------------------------------------------------------------
-- Shared Export Helpers
--------------------------------------------------------------------------------
-- Group member spec/item level comes from the centralized passive inspect
-- service (core/inspect.lua, addon.Inspect) where it is loaded.

-- Build a GUID -> non-secret display-name map from the current group roster.
-- In 12.0 the damage-meter API's source.name is a secret string for non-local
-- players, but UnitName on group/self units is never secret. Gather always runs
-- out of combat (export paths bail on InCombatLockdown), so roster reads are safe.
local function BuildRosterNameMap()
    local map = {}

    -- Always include the local player: party units exclude self, and solo has no group units.
    local pOk, pGuid = pcall(UnitGUID, "player")
    local nOk, pName = pcall(UnitName, "player")
    if pOk and pGuid and nOk and pName then
        map[pGuid] = pName:match("^([^%-]+)") or pName
    end

    local prefix, count
    if IsInRaid() then
        prefix, count = "raid", GetNumGroupMembers()
    elseif IsInGroup() then
        prefix, count = "party", GetNumGroupMembers() - 1
    end
    if prefix then
        for i = 1, count do
            local unit = prefix .. i
            local gOk, guid = pcall(UnitGUID, unit)
            local unOk, uName = pcall(UnitName, unit)
            if gOk and guid and unOk and uName then
                map[guid] = uName:match("^([^%-]+)") or uName
            end
        end
    end

    return map
end

-- Resolve a combat-source's display name to a plain (non-secret) string.
-- Priority: live roster -> inspect service cache -> guarded source.name -> "Unknown".
-- source.name is never operated on (index/match/compare) unless issecretvalue proves it is not secret.
local function ResolveExportName(guid, source, rosterNames)
    -- 1) Live group roster (non-secret UnitName; covers self + present members)
    if guid and rosterNames then
        local n = rosterNames[guid]
        if n then return n end
    end
    -- 2) Inspect service cache (non-secret UnitName captured at inspect time)
    if guid and addon.Inspect then
        local c = addon.Inspect:GetUnitInfo(guid)
        if c and c.name then return c.name end
    end
    -- 3) source.name ONLY if provably non-secret (local player / readable NPC).
    if issecretvalue then                       -- if global absent, skip this tier entirely
        local sname = source.name               -- reading a secret into a local is safe
        if not issecretvalue(sname) then         -- detection is safe; false for nil too
            if type(sname) == "string" then
                local stripped = sname:match("^([^%-]+)")
                if stripped and stripped ~= "" then return stripped end
            end
        end
    end
    -- 4) Give up
    return "Unknown"
end

function addon.FormatPlayerSpecInfo(player)
    local parts = {}
    if player.specName then
        local abbr = addon.SPEC_ABBREVIATIONS and addon.SPEC_ABBREVIATIONS[player.specName]
        table.insert(parts, abbr or player.specName)
    end
    if player.itemLevel then table.insert(parts, "ilvl " .. player.itemLevel) end
    if #parts > 0 then return "(" .. table.concat(parts, " - ") .. ")" end
    return nil
end

--------------------------------------------------------------------------------
-- Zone Record (the location an export names)
--------------------------------------------------------------------------------

local MYTHIC_KEYSTONE_DIFFICULTY = 8

local function GetActiveKeystoneLevel()
    if not (C_ChallengeMode and C_ChallengeMode.GetActiveKeystoneInfo) then return nil end
    local ok, level = pcall(C_ChallengeMode.GetActiveKeystoneInfo)
    if ok and type(level) == "number" and not issecretvalue(level) and level > 0 then
        return level
    end
    return nil
end

local function GetCurrentZoneLabel()
    local instName, instType, diffID, diffName = GetInstanceInfo()
    if instName and instName ~= "" and instType ~= "none" then
        if diffID == MYTHIC_KEYSTONE_DIFFICULTY then
            local level = GetActiveKeystoneLevel()
            if level then return instName .. " +" .. level end
        end
        return (diffName and diffName ~= "") and (instName .. " (" .. diffName .. ")") or instName
    else
        return (instName and instName ~= "") and instName or "Open World"
    end
end

-- Where the meter stood at its last reset: the START line of an export.
local resetZoneSnapshot = nil

local function SnapshotResetZone()
    resetZoneSnapshot = GetCurrentZoneLabel()
end

-- Where the meter last received data, which is the location an export names.
-- Recorded in combat only: a meter fills from a fight, while the data events
-- also fire on a zone-in carrying nothing new, and one of those on arrival is
-- what relabelled a finished key with the city the player hearthed to.
-- Cleared on reset, and lost on reload (the export then falls back to the
-- current zone).
local dataZoneLatest = nil
local dataZoneBySession = {}

local function RecordDataZone(sessionID)
    local label = GetCurrentZoneLabel()
    dataZoneLatest = label
    if type(sessionID) == "number" and not issecretvalue(sessionID) then
        dataZoneBySession[sessionID] = label
    end
end

local function OnZoneEvent(event, _, sessionID)
    if event == "DAMAGE_METER_RESET" then
        dataZoneLatest = nil
        wipe(dataZoneBySession)
        return
    end
    if event == "PLAYER_REGEN_DISABLED" then
        -- Combat start: the fight that is about to fill the meter happens here,
        -- and this reading is the one a data event arriving late cannot move.
        RecordDataZone(nil)
        return
    end
    if InCombatLockdown() then
        RecordDataZone(sessionID)
    end
end

function DMY._GetDataZoneLabel(sessionID)
    return (sessionID and dataZoneBySession[sessionID]) or dataZoneLatest or GetCurrentZoneLabel()
end

-- Started from the meter's component initializer, which runs whenever the
-- damage meter module is on, whichever meter is the active one. The gatherer
-- serves both, so the recording cannot wait on this meter's own gate, and
-- with the module off nothing here is registered at all.
local zoneRecordStarted = false

function DMY._StartZoneRecord()
    if zoneRecordStarted then return end
    zoneRecordStarted = true

    if C_DamageMeter and C_DamageMeter.ResetAllCombatSessions then
        hooksecurefunc(C_DamageMeter, "ResetAllCombatSessions", SnapshotResetZone)
    end

    -- Deferred so GetInstanceInfo() has difficulty info by the time START is taken.
    addon.Events.OnWorldEntered(function()
        SnapshotResetZone()
    end)

    for _, event in ipairs({
        "DAMAGE_METER_COMBAT_SESSION_UPDATED",
        "DAMAGE_METER_CURRENT_SESSION_UPDATED",
        "DAMAGE_METER_RESET",
        "PLAYER_REGEN_DISABLED",
    }) do
        addon.Events.On("DamageMeterZone", event, OnZoneEvent)
    end

    -- A key that starts after the reset moves START onto the key's own label, so a
    -- run that auto-reset on entry does not read "(Mythic Keystone)" above "+16".
    -- Skipped once data has arrived, because START marks where the data began. The
    -- level is read a frame later, and a read that comes back empty keeps the
    -- existing snapshot.
    addon.Events.On("DamageMeterZone", "CHALLENGE_MODE_START", function()
        if dataZoneLatest then return end
        C_Timer.After(0, function()
            if dataZoneLatest then return end
            if GetActiveKeystoneLevel() then SnapshotResetZone() end
        end)
    end)
end

-- The export location lines of the debug window.
function DMY._DebugZoneLines()
    local lines, push = addon.DebugLines("Damage Meter Export Location", "")
    push("Current zone:       %s", GetCurrentZoneLabel())
    push("Export location:    %s", DMY._GetDataZoneLabel(nil))
    push("  recorded:         %s", dataZoneLatest or "nothing yet this session")
    push("START snapshot:     %s", resetZoneSnapshot or "none")
    push("In combat:          %s", tostring(InCombatLockdown()))
    push("")
    push("Per segment:")
    local any = false
    for sessionID, label in pairs(dataZoneBySession) do
        push("  #%d  %s", sessionID, label)
        any = true
    end
    if not any then push("  (none)") end
    return lines
end

--------------------------------------------------------------------------------
-- Export Data Gathering
--------------------------------------------------------------------------------

function addon.GatherDamageMeterExportData(sessionType, primaryMeterType, sessionID)
    if not C_DamageMeter or not C_DamageMeter.IsDamageMeterAvailable then
        return nil, "Damage Meter API not available."
    end
    local isAvailable, failureReason = C_DamageMeter.IsDamageMeterAvailable()
    if not isAvailable then
        return nil, "Damage Meter not available: " .. (failureReason or "unknown")
    end

    local DMT = Enum.DamageMeterType
    local columnMap = {
        [DMT.DamageDone]            = { DMT.Dps,                DMT.DamageDone,   DMT.Deaths, DMT.Interrupts },
        [DMT.Dps]                   = { DMT.Dps,                DMT.DamageDone,   DMT.Deaths, DMT.Interrupts },
        [DMT.HealingDone]           = { DMT.Hps,                DMT.HealingDone,  DMT.Deaths, DMT.Interrupts },
        [DMT.Hps]                   = { DMT.Hps,                DMT.HealingDone,  DMT.Deaths, DMT.Interrupts },
        [DMT.Deaths]                = { DMT.Deaths,             DMT.Dps,          DMT.DamageDone, DMT.Interrupts },
        [DMT.Interrupts]            = { DMT.Interrupts,         DMT.Dps,          DMT.DamageDone, DMT.Deaths },
        [DMT.Absorbs]               = { DMT.Absorbs,            DMT.Dps,          DMT.DamageDone, DMT.Deaths },
        [DMT.Dispels]               = { DMT.Dispels,            DMT.Dps,          DMT.DamageDone, DMT.Deaths },
        [DMT.DamageTaken]           = { DMT.DamageTaken,        DMT.Dps,          DMT.DamageDone, DMT.Deaths },
        [DMT.AvoidableDamageTaken]  = { DMT.AvoidableDamageTaken, DMT.Dps,        DMT.DamageDone, DMT.Deaths },
        [DMT.EnemyDamageTaken]      = { DMT.EnemyDamageTaken,   DMT.Dps,          DMT.DamageDone, DMT.Deaths },
    }
    local columns = columnMap[primaryMeterType] or columnMap[DMT.Dps]

    local meterNames = {
        [DMT.DamageDone] = "Damage",     [DMT.Dps] = "DPS",
        [DMT.HealingDone] = "Healing",   [DMT.Hps] = "HPS",
        [DMT.Absorbs] = "Absorbs",       [DMT.Interrupts] = "Interrupts",
        [DMT.Dispels] = "Dispels",       [DMT.DamageTaken] = "Dmg Taken",
        [DMT.AvoidableDamageTaken] = "Avoidable", [DMT.Deaths] = "Deaths",
        [DMT.EnemyDamageTaken] = "Enemy Dmg",
    }
    local sessionLabels = {
        [Enum.DamageMeterSessionType.Overall] = "Overall",
        [Enum.DamageMeterSessionType.Current] = "Current",
        [Enum.DamageMeterSessionType.Expired] = "Expired",
    }

    local rateMetrics = { [DMT.Dps] = true, [DMT.Hps] = true }
    local countMetrics = { [DMT.Deaths] = true, [DMT.Interrupts] = true, [DMT.Dispels] = true }

    -- Query all column meter types
    local sessionData = {}
    for _, mt in ipairs(columns) do
        if not sessionData[mt] then
            local ok, result
            if sessionID then
                ok, result = pcall(C_DamageMeter.GetCombatSessionFromID, sessionID, mt)
            else
                ok, result = pcall(C_DamageMeter.GetCombatSessionFromType, sessionType, mt)
            end
            if ok and result then sessionData[mt] = result end
        end
    end

    local primarySession = sessionData[columns[1]]
    if not primarySession or not primarySession.combatSources or #primarySession.combatSources == 0 then
        return nil, "No data available for " .. (sessionLabels[sessionType] or "this") .. " session."
    end

    -- Pre-count Deaths per GUID (each combatSource entry = one death event)
    local deathCounts = {}
    local deathSession = sessionData[DMT.Deaths]
    if deathSession and deathSession.combatSources then
        for _, source in ipairs(deathSession.combatSources) do
            local guid = source.sourceGUID
            if guid then
                deathCounts[guid] = (deathCounts[guid] or 0) + 1
            end
        end
    end

    -- Resolve display names from non-secret sources (source.name is secret for non-local players in 12.0)
    local rosterNames = BuildRosterNameMap()

    -- Build player table keyed by GUID, preserving primary sort order
    local players = {}
    local playerOrder = {}
    for _, source in ipairs(primarySession.combatSources) do
        local guid = source.sourceGUID
        if guid and not players[guid] then
            players[guid] = {
                name = ResolveExportName(guid, source, rosterNames),
                classFilename = source.classFilename or "",
                specIconID = source.specIconID,
                isLocalPlayer = source.isLocalPlayer,
                values = {},
            }
            if columns[1] == DMT.Deaths then
                players[guid].values[columns[1]] = {
                    total = deathCounts[guid] or 0,
                    perSec = 0,
                }
            else
                players[guid].values[columns[1]] = {
                    total = source.totalAmount,
                    perSec = source.amountPerSecond,
                }
            end
            table.insert(playerOrder, guid)
        end
    end

    -- Merge secondary columns by GUID
    for i = 2, #columns do
        local mt = columns[i]
        local data = sessionData[mt]
        if data and data.combatSources then
            if mt == DMT.Deaths then
                -- Deaths: use pre-counted occurrences, not totalAmount
                for _, source in ipairs(data.combatSources) do
                    local guid = source.sourceGUID
                    if guid and players[guid] and not players[guid].values[mt] then
                        players[guid].values[mt] = {
                            total = deathCounts[guid] or 0,
                            perSec = 0,
                        }
                    end
                end
            else
                for _, source in ipairs(data.combatSources) do
                    local guid = source.sourceGUID
                    if guid and players[guid] and not players[guid].values[mt] then
                        players[guid].values[mt] = {
                            total = source.totalAmount,
                            perSec = source.amountPerSecond,
                        }
                    end
                end
            end
        end
    end

    -- Duration
    local duration = primarySession.durationSeconds
    if not duration and not sessionID and sessionType then
        local ok, dur = pcall(C_DamageMeter.GetSessionDurationSeconds, sessionType)
        if ok then duration = dur end
    end

    -- Helpers. The shared floor-pair formatter keeps exported numbers matching
    -- the on-screen meter (the old inline copy here predated the 2026-07
    -- sub-1K fix: it rounded where the meter floors, so exports like "45.7K"
    -- disagreed with the rendered "45.6K").
    local FormatNumber = addon.FormatCompactNumber

    local function FormatDuration(sec)
        if not sec or sec <= 0 then return "0s" end
        local m = math.floor(sec / 60)
        local s = math.floor(sec % 60)
        return m > 0 and string.format("%dm %02ds", m, s) or string.format("%ds", s)
    end

    local function GetDisplayValue(guid, mt)
        local v = players[guid] and players[guid].values[mt]
        if not v then return "-" end
        if rateMetrics[mt] then return FormatNumber(v.perSec)
        elseif countMetrics[mt] then return tostring(math.floor(v.total))
        else return FormatNumber(v.total) end
    end

    -- Column header names
    local columnNames = {}
    for _, mt in ipairs(columns) do
        table.insert(columnNames, meterNames[mt] or "?")
    end

    -- Resolve spec names and item levels
    for guid, p in pairs(players) do
        p.specName = GetSpecNameFromIconID(p.specIconID)
        if p.isLocalPlayer then
            local ok, avg, equipped = pcall(GetAverageItemLevel)
            if ok and equipped and type(equipped) == "number" and equipped > 0 then
                p.itemLevel = math.floor(equipped)
            end
        else
            -- Inspect service by GUID, then by name (historic segments can
            -- outlive the roster GUID mapping)
            local cached = addon.Inspect and addon.Inspect:GetUnitInfo(guid)
            if not cached and addon.Inspect and p.name and p.name ~= "Unknown" then
                cached = addon.Inspect:FindByName(p.name)
            end
            if cached then
                if cached.itemLevel then p.itemLevel = cached.itemLevel end
                if cached.specName then p.specName = cached.specName end
            end
        end
    end

    -- Instance info: where this session's data last arrived
    local instanceLabel = DMY._GetDataZoneLabel(sessionID)

    return {
        players = players,
        playerOrder = playerOrder,
        columns = columns,
        columnNames = columnNames,
        sessionLabel = sessionLabels[sessionType] or (sessionID and ("Segment #" .. sessionID)) or "Unknown",
        duration = duration,
        instanceLabel = instanceLabel,
        startZoneLabel = resetZoneSnapshot,
        playerCount = #playerOrder,
        timestamp = date("%Y-%m-%d %H:%M"),
        FormatNumber = FormatNumber,
        FormatDuration = FormatDuration,
        GetDisplayValue = GetDisplayValue,
    }
end

--------------------------------------------------------------------------------
-- This meter's exports
--------------------------------------------------------------------------------

--- Export window data to the High Score arcade display.
function DMY._ExportToWindow(windowIndex)
    if InCombatLockdown() then
        if addon.Print then addon:Print("Export not available during combat.") end
        return
    end

    local cfg = DMY._GetWindowConfig(windowIndex)
    if not cfg then return end

    local sessionType = cfg.sessionType or (not cfg.sessionID and DMY.ST.Overall) or nil
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

    local sessionType = cfg.sessionType or (not cfg.sessionID and DMY.ST.Overall) or nil
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
    table.insert(messages, string.format("%s - %s (%s) [%s]:", addon.Brand, headerName, data.sessionLabel, data.FormatDuration(data.duration)))

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
