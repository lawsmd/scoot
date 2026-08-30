-- dungeonjournal/season.lua - Builds the "current M+ season" instance set by
-- snapshotting C_ChallengeMode.GetMapTable() + GetMapUIInfo(name). Matches
-- against EJ_GetInstanceInfo(instanceID) primarily by name (most reliable
-- across patches), with dungeonAreaMapID as a secondary check.
local addonName, addon = ...

local DJ = addon.DungeonJournal
if not DJ then return end

-- Snapshot state — exposed via DJ._SeasonDebug for /scoot dj debug.
local _currentSeasonChallengeMaps = {}  -- [challengeMapID] = name
local _currentSeasonNames         = {}  -- [name] = true
local _haveSnapshot = false
local _requestedOnce = false

local function refreshSnapshot()
    if not C_ChallengeMode or not C_ChallengeMode.GetMapTable then return end
    local maps = C_ChallengeMode.GetMapTable()
    if type(maps) ~= "table" then return end

    wipe(_currentSeasonChallengeMaps)
    wipe(_currentSeasonNames)

    for _, mapID in ipairs(maps) do
        if type(mapID) == "number" then
            local name = C_ChallengeMode.GetMapUIInfo and C_ChallengeMode.GetMapUIInfo(mapID) or nil
            _currentSeasonChallengeMaps[mapID] = name or true
            if type(name) == "string" and name ~= "" then
                _currentSeasonNames[name] = true
            end
        end
    end

    if next(_currentSeasonNames) ~= nil then
        _haveSnapshot = true
    end
end

local function requestMapInfo()
    if C_MythicPlus and C_MythicPlus.RequestMapInfo then
        C_MythicPlus.RequestMapInfo()
        _requestedOnce = true
    end
end

-- IsCurrentSeasonInstance: matches the EJ instance against this season's M+
-- map pool. Returns false when the snapshot isn't ready yet; callers will see
-- the populated answer on the next EJ_LootUpdate after the event fires.
function DJ.IsCurrentSeasonInstance(instanceID)
    if type(instanceID) ~= "number" then return false end
    if not _haveSnapshot then
        refreshSnapshot()
        if not _haveSnapshot and not _requestedOnce then
            requestMapInfo()
        end
        if not _haveSnapshot then return false end
    end
    if not EJ_GetInstanceInfo then return false end
    local ok, name, _, _, _, _, _, dungeonAreaMapID = pcall(EJ_GetInstanceInfo, instanceID)
    if not ok then return false end

    if type(name) == "string" and _currentSeasonNames[name] then
        return true
    end
    if type(dungeonAreaMapID) == "number" and _currentSeasonChallengeMaps[dungeonAreaMapID] then
        return true
    end
    return false
end

-- Diagnostic dump for /scoot dj debug.
function DJ._SeasonDebug()
    return {
        haveSnapshot   = _haveSnapshot,
        requestedOnce  = _requestedOnce,
        challengeMaps  = _currentSeasonChallengeMaps,
        seasonNames    = _currentSeasonNames,
    }
end

-- Event wiring
local function onSeasonEvent(event)
    if event == "PLAYER_ENTERING_WORLD" then
        requestMapInfo()
        refreshSnapshot()
        if DJ.RefreshAllVisible then DJ.RefreshAllVisible() end
    elseif event == "CHALLENGE_MODE_MAPS_UPDATE" then
        refreshSnapshot()
        if DJ.RefreshAllVisible then DJ.RefreshAllVisible() end
    end
end
addon.Events.On("DungeonJournal:Season", "PLAYER_ENTERING_WORLD", onSeasonEvent)
addon.Events.On("DungeonJournal:Season", "CHALLENGE_MODE_MAPS_UPDATE", onSeasonEvent)
