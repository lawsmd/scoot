-- damagemetersY/data.lua - Number formatting, death aggregation, merged data pipeline
local _, addon = ...
local DMY = addon.DamageMetersY

--------------------------------------------------------------------------------
-- Number Formatting
--------------------------------------------------------------------------------

local function FloorPart(n, sig, frac)
    local v = math.floor(n / sig) / frac
    if frac > 1 then
        local s = string.format("%.1f", v)
        return (s:gsub("%.0$", ""))  -- "2.0" → "2", matching engine output
    end
    return string.format("%d", v)
end

-- Mirrors the AbbreviateNumbers breakpoint config (floor-pair semantics) so
-- drilldown rows, the settings preview, and the degraded fallback match the
-- live meter. Keep in sync with BuildBreakpointTable below.
function DMY._FormatCompact(n)
    n = tonumber(n)
    if not n or n ~= n or n <= 0 then return "0" end
    if n >= 1e10 then return FloorPart(n, 1e9, 1) .. "B"
    elseif n >= 1e9 then return FloorPart(n, 1e8, 10) .. "B"
    elseif n >= 1e7 then return FloorPart(n, 1e6, 1) .. "M"
    elseif n >= 1e6 then return FloorPart(n, 1e5, 10) .. "M"
    elseif n >= 1e4 then return FloorPart(n, 1e3, 1) .. "K"
    elseif n >= 1e3 then return FloorPart(n, 1e2, 10) .. "K"
    else return string.format("%d", math.floor(n)) end
end

function DMY._FormatDuration(sec)
    if not sec or sec <= 0 then return "0:00" end
    sec = math.floor(sec)
    if sec >= 3600 then
        return string.format("%d:%02d:%02d", math.floor(sec / 3600), math.floor(sec / 60) % 60, sec % 60)
    end
    return string.format("%d:%02d", math.floor(sec / 60), sec % 60)
end

--------------------------------------------------------------------------------
-- Deaths Aggregation
--
-- Deaths metric returns one entry per death event, not per player.
-- Count occurrences per GUID.
--------------------------------------------------------------------------------

local function CountDeathsPerGUID(deathSession)
    local counts = {}
    if deathSession and deathSession.combatSources then
        for _, source in ipairs(deathSession.combatSources) do
            local guid = source.sourceGUID
            if guid then
                counts[guid] = (counts[guid] or 0) + 1
            end
        end
    end
    return counts
end

--------------------------------------------------------------------------------
-- GUID Cache + Identity Lookup
--
-- Populated during OOC queries, used during combat for secondary column data.
-- The source-level API (GetCombatSessionSourceFromType) accepts pre-stored
-- non-secret GUIDs during combat, enabling live secondary column values.
--------------------------------------------------------------------------------

DMY._guidCache = {}       -- { [guid] = { classFilename, specIconID, isLocalPlayer } }
DMY._identityToGUID = {}  -- { [identityKey] = guid or false (false = collision) }

local function BuildIdentityKey(classFilename, specIconID, isLocalPlayer)
    return (classFilename or "UNKNOWN") .. "_" .. tostring(specIconID or 0) .. "_" .. tostring(isLocalPlayer)
end

--------------------------------------------------------------------------------
-- QueryMergedData — Core data pipeline
--
-- Returns a merged table with all players and their values across all columns.
-- During combat, primary column uses session-level combatSources (engine-sorted).
-- Secondary columns use stored-GUID source queries for live data.
-- Out of combat, all columns are GUID-correlated via session-level lookups.
--------------------------------------------------------------------------------

function DMY._QueryMergedData(sessionType, sessionID, columns, inCombat)
    if not C_DamageMeter then return nil end
    if not C_DamageMeter.GetCombatSessionFromType and not C_DamageMeter.GetCombatSessionFromID then
        return nil
    end
    if not columns or #columns == 0 then return nil end

    local FORMATS = DMY.COLUMN_FORMATS
    local EXCLUDED = DMY.SECONDARY_EXCLUDED_FORMATS

    -- Determine which meter types are needed for the primary column
    local primaryDef = FORMATS[columns[1].format]
    if not primaryDef then return nil end
    local primaryType = primaryDef.primary or primaryDef.meterType

    -- Determine all needed meter types
    local neededTypes
    if inCombat then
        -- Combat: session-level query for primary column only
        neededTypes = {}
        neededTypes[primaryType] = true
    else
        neededTypes = DMY._GetNeededMeterTypes(columns)
    end

    -- Query each meter type via session-level API
    local sessions = {}
    for meterType in pairs(neededTypes) do
        local ok, result
        if sessionID then
            ok, result = pcall(C_DamageMeter.GetCombatSessionFromID, sessionID, meterType)
        else
            ok, result = pcall(C_DamageMeter.GetCombatSessionFromType, sessionType, meterType)
        end
        if ok and result then
            sessions[meterType] = result
        end
    end

    -- Get primary session
    local primarySession = sessions[primaryType]
    if not primarySession or not primarySession.combatSources or #primarySession.combatSources == 0 then
        return nil
    end

    -- Deaths pre-count (only needed if Deaths column is present and OOC)
    local deathCounts
    if not inCombat and sessions[9] then -- 9 = Deaths
        deathCounts = CountDeathsPerGUID(sessions[9])
    end

    -- Build GUID-keyed lookups for secondary types (OOC only)
    local guidLookups = {}
    if not inCombat then
        for meterType, session in pairs(sessions) do
            if session.combatSources then
                guidLookups[meterType] = {}
                for _, source in ipairs(session.combatSources) do
                    if source.sourceGUID then
                        guidLookups[meterType][source.sourceGUID] = source
                    end
                end
            end
        end

        -- Populate GUID cache + identity lookup from primary session
        DMY._guidCache = {}
        DMY._identityToGUID = {}
        for _, source in ipairs(primarySession.combatSources) do
            if source.sourceGUID then
                local ikey = BuildIdentityKey(source.classFilename, source.specIconID, source.isLocalPlayer)
                DMY._guidCache[source.sourceGUID] = {
                    classFilename = source.classFilename,
                    specIconID = source.specIconID,
                    isLocalPlayer = source.isLocalPlayer,
                }
                if DMY._identityToGUID[ikey] == nil then
                    DMY._identityToGUID[ikey] = source.sourceGUID
                else
                    DMY._identityToGUID[ikey] = false -- collision: same class+spec
                end
            end
        end
    end

    -- Combat: determine secondary meter types needed and query via source API
    local secondaryByIdentity  -- { [identityKey] = { [meterType] = totalAmount } }
    if inCombat and next(DMY._guidCache) then
        -- Collect secondary meter types from non-primary, non-excluded columns
        local secondaryTypes = {}
        for c = 2, #columns do
            local colDef = columns[c]
            if colDef and not EXCLUDED[colDef.format] then
                local def = FORMATS[colDef.format]
                if def then
                    local mt = def.primary or def.meterType
                    if mt ~= primaryType then
                        secondaryTypes[mt] = true
                    end
                end
            end
        end

        if next(secondaryTypes) then
            secondaryByIdentity = {}

            -- Query session-level for maxAmounts of secondary types
            for mt in pairs(secondaryTypes) do
                local ok, result
                if sessionID then
                    ok, result = pcall(C_DamageMeter.GetCombatSessionFromID, sessionID, mt)
                else
                    ok, result = pcall(C_DamageMeter.GetCombatSessionFromType, sessionType, mt)
                end
                if ok and result then
                    sessions[mt] = result
                end
            end

            -- Query source-level API per cached GUID per secondary meter type
            for guid, info in pairs(DMY._guidCache) do
                local ikey = BuildIdentityKey(info.classFilename, info.specIconID, info.isLocalPlayer)
                -- Skip collision keys
                if DMY._identityToGUID[ikey] ~= false then
                    if not secondaryByIdentity[ikey] then
                        secondaryByIdentity[ikey] = {}
                    end
                    for mt in pairs(secondaryTypes) do
                        local ok, srcResult = pcall(
                            C_DamageMeter.GetCombatSessionSourceFromType,
                            sessionType, mt, guid, nil
                        )
                        if ok and srcResult then
                            secondaryByIdentity[ikey][mt] = srcResult.totalAmount
                        end
                    end
                end
            end
        end
    end

    -- Build merged table
    local merged = {
        playerOrder = {},
        players = {},
        maxAmounts = {},
        secondaryByIdentity = secondaryByIdentity,  -- nil when OOC (not needed)
        durationSeconds = primarySession.durationSeconds,
        sessionType = sessionType,
    }

    -- Collect max amounts per meter type
    for meterType, session in pairs(sessions) do
        merged.maxAmounts[meterType] = session.maxAmount
    end

    -- Iterate primary session (engine-sorted order = rank)
    local seenGUIDs = {}
    for rank, source in ipairs(primarySession.combatSources) do
        -- In combat, sourceGUID is secret — cannot use as table key or compare.
        -- Use rank-based keys and skip duplicate detection entirely.
        local guid = not inCombat and source.sourceGUID or nil
        local key = guid or ("rank_" .. rank)

        -- Skip duplicate GUIDs (OOC only)
        if inCombat or (guid and not seenGUIDs[guid]) then
            if guid then seenGUIDs[guid] = true end

            table.insert(merged.playerOrder, key)

            -- Build identity key from NeverSecret fields (works in combat)
            local identityKey = BuildIdentityKey(source.classFilename, source.specIconID, source.isLocalPlayer)

            local player = {
                name = source.name,                   -- secret in combat
                classFilename = source.classFilename, -- NeverSecret
                specIconID = source.specIconID,        -- NeverSecret (may be nil)
                isLocalPlayer = source.isLocalPlayer,  -- NeverSecret
                identityKey = identityKey,             -- for combat secondary lookup
                rank = rank,
                values = {},
            }

            -- Primary column value
            player.values[primaryType] = {
                totalAmount = source.totalAmount,         -- secret in combat
                amountPerSecond = source.amountPerSecond,  -- secret in combat
            }

            -- Deaths special case for primary column
            if primaryDef.isDeaths and deathCounts and guid then
                player.values[primaryType] = {
                    totalAmount = deathCounts[guid] or 0,
                    amountPerSecond = 0,
                }
            end

            -- Secondary columns (OOC only, GUID-correlated)
            if not inCombat and guid then
                for meterType, lookup in pairs(guidLookups) do
                    if meterType ~= primaryType and not player.values[meterType] then
                        local s = lookup[guid]
                        if s then
                            if meterType == 9 and deathCounts then -- Deaths
                                player.values[meterType] = {
                                    totalAmount = deathCounts[guid] or 0,
                                    amountPerSecond = 0,
                                }
                            else
                                player.values[meterType] = {
                                    totalAmount = s.totalAmount,
                                    amountPerSecond = s.amountPerSecond,
                                }
                            end
                        end
                    end
                end
            end

            merged.players[key] = player
        end
    end

    return merged
end

--------------------------------------------------------------------------------
-- Unified number abbreviation (same function used OOC and in combat)
--
-- Root cause of the old sub-1K raw-float bug (fixed 2026-07): the previous
-- breakpoint table omitted the REQUIRED significandDivisor field
-- (NumberAbbreviationBreakpoint requires breakpoint, abbreviation,
-- significandDivisor, fractionDivisor; formula:
--   floor(value / significandDivisor) / fractionDivisor).
-- CreateAbbreviateConfig raised a validation error that pcall swallowed,
-- _abbrevOpts stayed nil, and AbbreviateNumbers(value, nil) used the engine
-- DEFAULT breakpoints, which have no base (breakpoint=1) entry — so sub-1K
-- amountPerSecond floats passed through raw ("999.989898989898").
-- The fixed table supplies both divisors plus a base entry so sub-1K floats
-- floor to integers. Creation errors are kept in DMY._abbrevError for
-- inspection via /scoot debug dmY abbrev.
--------------------------------------------------------------------------------

local function BaseBreakpoint()
    -- Floors sub-1K values to whole numbers ("999", not "999.9898...").
    return { breakpoint = 1, abbreviation = "",
             significandDivisor = 1, fractionDivisor = 1,
             abbreviationIsGlobal = false }
end

local function BuildBreakpointTable()
    local t
    -- Prefer live engine defaults (locale-correct); copy, never mutate the API table.
    if C_StringUtil and C_StringUtil.GetDefaultAbbreviationBreakpoints then
        local ok, defaults = pcall(C_StringUtil.GetDefaultAbbreviationBreakpoints)
        if ok and type(defaults) == "table" and #defaults > 0 then
            t = {}
            for i, bp in ipairs(defaults) do
                t[i] = { breakpoint = bp.breakpoint, abbreviation = bp.abbreviation,
                         significandDivisor = bp.significandDivisor,
                         fractionDivisor = bp.fractionDivisor,
                         abbreviationIsGlobal = bp.abbreviationIsGlobal }
            end
        end
    end
    if not t then
        -- Hand-authored mirror of the classic paired defaults (enUS-style)
        t = {
            { breakpoint = 1e10, abbreviation = "B", significandDivisor = 1e9, fractionDivisor = 1,  abbreviationIsGlobal = false },
            { breakpoint = 1e9,  abbreviation = "B", significandDivisor = 1e8, fractionDivisor = 10, abbreviationIsGlobal = false },
            { breakpoint = 1e7,  abbreviation = "M", significandDivisor = 1e6, fractionDivisor = 1,  abbreviationIsGlobal = false },
            { breakpoint = 1e6,  abbreviation = "M", significandDivisor = 1e5, fractionDivisor = 10, abbreviationIsGlobal = false },
            { breakpoint = 1e4,  abbreviation = "K", significandDivisor = 1e3, fractionDivisor = 1,  abbreviationIsGlobal = false },
            { breakpoint = 1e3,  abbreviation = "K", significandDivisor = 1e2, fractionDivisor = 10, abbreviationIsGlobal = false },
        }
    end
    t[#t + 1] = BaseBreakpoint()
    -- NumberAbbrevOptions docs: "Order these from largest to smallest."
    table.sort(t, function(a, b) return a.breakpoint > b.breakpoint end)
    return t
end
DMY._BuildBreakpointTable = BuildBreakpointTable   -- used by the debug battery

DMY._abbrevError = nil
local _abbrevOpts = nil
local _abbrevBuildTried = false

function DMY._RebuildAbbrevConfig()
    _abbrevBuildTried = true
    _abbrevOpts, DMY._abbrevError = nil, nil
    if not CreateAbbreviateConfig then
        DMY._abbrevError = "CreateAbbreviateConfig API missing"
        return nil
    end
    local ok, result = pcall(CreateAbbreviateConfig, BuildBreakpointTable())
    if ok and result then
        _abbrevOpts = { config = result }
        return _abbrevOpts
    end
    DMY._abbrevError = "bp=1: " .. tostring(result)
    -- breakpoint=1 may trip restricted validation (NotMultipleOfTen); retry bp=10.
    -- Values below 10 then pass through raw but are contained by the fixed
    -- value-text widths (layout.lua).
    local retry = BuildBreakpointTable()
    retry[#retry].breakpoint = 10
    ok, result = pcall(CreateAbbreviateConfig, retry)
    if ok and result then
        _abbrevOpts = { config = result }
    else
        DMY._abbrevError = DMY._abbrevError .. " | bp=10: " .. tostring(result)
    end
    return _abbrevOpts
end

local function UnifiedAbbreviate(value)
    if not _abbrevBuildTried then DMY._RebuildAbbrevConfig() end
    if _abbrevOpts and AbbreviateNumbers then
        local ok, result = pcall(AbbreviateNumbers, value, _abbrevOpts)
        if ok then return result end
    end
    -- Degraded path (config creation failed): plain numbers via Lua formatter.
    if not (issecretvalue and issecretvalue(value)) then
        local fmtOk, fmtResult = pcall(DMY._FormatCompact, value)
        if fmtOk then return fmtResult end
    end
    -- Secrets: engine-default abbreviation (sub-1K raw, contained by the
    -- fixed value-text widths).
    if AbbreviateNumbers then
        local ok, result = pcall(AbbreviateNumbers, value)
        if ok then return result end
    end
    -- Ultimate fallback: return raw value (SetText will handle secrets)
    return value
end

DMY._UnifiedAbbreviate = UnifiedAbbreviate

--------------------------------------------------------------------------------
-- Format a column value for display (works both OOC and combat)
--------------------------------------------------------------------------------

function DMY._FormatColumnValue(player, formatKey)
    local def = DMY.COLUMN_FORMATS[formatKey]
    if not def then return "" end

    if def.primary then
        -- Combo format: "50K (1.6M)"
        local pVal = player.values[def.primary]
        local sVal = player.values[def.secondary]
        local pNum = pVal and pVal[def.primaryField] or 0
        local sNum = sVal and sVal[def.secondaryField] or 0
        return UnifiedAbbreviate(pNum) .. " (" .. UnifiedAbbreviate(sNum) .. ")"
    end

    -- Simple format
    local val = player.values[def.meterType]
    if not val then return "-" end
    return UnifiedAbbreviate(val[def.valueField] or 0)
end

--- Returns the raw numeric value for a column (used for bar fill).
function DMY._GetColumnValue(player, formatKey)
    local def = DMY.COLUMN_FORMATS[formatKey]
    if not def then return 0 end
    local meterType = def.primary or def.meterType
    local val = player.values[meterType]
    if not val then return 0 end
    return val[def.valueField or "totalAmount"] or 0
end

--- Returns the max amount for a column's meter type.
function DMY._GetColumnMax(mergedData, formatKey)
    local def = DMY.COLUMN_FORMATS[formatKey]
    if not def then return 1 end
    local meterType = def.primary or def.meterType
    return mergedData.maxAmounts[meterType] or 1
end
