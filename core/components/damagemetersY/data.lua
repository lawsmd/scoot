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
-- Secret-safe GUID access
--
-- sourceGUID has no NeverSecret exemption: under active addon restrictions
-- (combat, and possibly an entire M+ run) it comes back secret. Truthiness
-- tests and table-keying on a secret throw, so every sourceGUID read goes
-- through this filter and secret GUIDs degrade to "absent".
--------------------------------------------------------------------------------

local function PlainGUID(v)
    if v == nil then return nil end
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end

-- Generic plain filters, exposed for drilldown code (deathRecapID,
-- deathTimeSeconds, recap event fields). Same contract as PlainGUID:
-- nil unless the value is present and plain.
function DMY._PlainValue(v)
    if v == nil then return nil end
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end

function DMY._PlainNumber(v)
    v = DMY._PlainValue(v)
    if type(v) ~= "number" then return nil end
    return v
end

-- M:SS (or H:MM:SS) from a plain, non-negative seconds value.
function DMY._FormatDeathTime(seconds)
    seconds = math.floor(seconds + 0.5)
    if seconds >= 3600 then
        return string.format("%d:%02d:%02d",
            math.floor(seconds / 3600), math.floor((seconds % 3600) / 60), seconds % 60)
    end
    return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
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
            local guid = PlainGUID(source.sourceGUID)
            if guid then
                counts[guid] = (counts[guid] or 0) + 1
            end
        end
    end
    return counts
end

--------------------------------------------------------------------------------
-- GUID Cache + Identity Lookup (drilldown support only)
--
-- Rebuilt once per OOC refresh cycle from the stable Overall sessions.
-- Used exclusively by drilldown to re-resolve a row's GUID after combat.
-- Secondary columns no longer touch this cache — they correlate rows to
-- per-metric session data by identity key (see _QueryMergedData).
--------------------------------------------------------------------------------

DMY._guidCache = {}       -- { [guid] = { classFilename, specIconID, isLocalPlayer } }
DMY._identityToGUID = {}  -- { [identityKey] = guid or false (false = collision) }

local function BuildIdentityKey(classFilename, specIconID, isLocalPlayer)
    return (classFilename or "UNKNOWN") .. "_" .. tostring(specIconID or 0) .. "_" .. tostring(isLocalPlayer)
end
DMY._BuildIdentityKey = BuildIdentityKey

-- Rebuild the drilldown GUID cache from Overall DamageDone + HealingDone
-- (the union covers zero-damage healers). Commits only when the read produced
-- at least one plain GUID: a restricted-context refresh (secret GUIDs) or an
-- empty session keeps the previous cache instead of clobbering it.
-- _HandleReset performs the legitimate wipe.
function DMY._RebuildGUIDCache()
    if DMY._inCombat then return end
    if not (C_DamageMeter and C_DamageMeter.GetCombatSessionFromType) then return end

    local guidCache, identityToGUID = {}, {}
    for _, meterType in ipairs({ 0, 2 }) do -- DamageDone, HealingDone
        local ok, session = pcall(C_DamageMeter.GetCombatSessionFromType, 0, meterType)
        if ok and session and session.combatSources then
            for _, source in ipairs(session.combatSources) do
                local guid = PlainGUID(source.sourceGUID)
                if guid and not guidCache[guid] then
                    local ikey = BuildIdentityKey(source.classFilename, source.specIconID, source.isLocalPlayer)
                    guidCache[guid] = {
                        classFilename = source.classFilename,
                        specIconID = source.specIconID,
                        isLocalPlayer = source.isLocalPlayer,
                    }
                    if identityToGUID[ikey] == nil then
                        identityToGUID[ikey] = guid
                    else
                        identityToGUID[ikey] = false -- collision: same class+spec
                    end
                end
            end
        end
    end

    if next(guidCache) then
        DMY._guidCache, DMY._identityToGUID = guidCache, identityToGUID
    end
end

--------------------------------------------------------------------------------
-- Recap → segment index (deaths drilldown, Overall scope)
--
-- Overall sessions carry no per-death timestamps (deathTimeSeconds == -1), so
-- the Overall death list labels each death by finding its recapID in the
-- retained segments' Deaths sessions. Values are precomputed PLAIN strings,
-- { seg = "SegName", time = "3:22"|nil } (separate fields — the row renders
-- time in its own left column). `time` is the death's position on the
-- OVERALL clock — prior segment durations accumulated chronologically plus
-- the within-segment deathTimeSeconds — matching the Overall window's
-- top-left timer. A combat-time lookup is then a single plain table index
-- (recapID is NeverSecret), with zero arithmetic on secrets.
-- Rebuilt lazily (deaths drilldown open/refresh) when dirty and OOC; dirtied
-- at PLAYER_REGEN_ENABLED, wiped+dirtied by _HandleReset.
--------------------------------------------------------------------------------

DMY._recapSegmentIndex = {}
DMY._recapSegmentIndexDirty = true

function DMY._RebuildRecapSegmentIndex()
    if DMY._inCombat then return end
    if not (C_DamageMeter and C_DamageMeter.GetAvailableCombatSessions
        and C_DamageMeter.GetCombatSessionFromID) then return end

    local index = {}
    -- offset = seconds already on the Overall clock when this segment began;
    -- nil = unknown (an earlier segment reported no duration), in which case
    -- the death renders an em dash rather than a misleading segment-local time.
    local function Absorb(session, label, offset)
        if not session or not session.combatSources then return end
        for _, source in ipairs(session.combatSources) do
            local rid = DMY._PlainNumber(source.deathRecapID)
            if rid and rid > 0 and not index[rid] then
                local t = DMY._PlainNumber(source.deathTimeSeconds)
                index[rid] = {
                    seg = label,
                    time = (offset and t and t >= 0)
                        and DMY._FormatDeathTime(offset + t) or nil,
                }
            end
        end
    end

    -- Pass 1: retained segments in chronological order (sessionIDs are
    -- monotonically increasing) with each segment's duration — the Available
    -- list carries it; the session payload is the fallback.
    local retained = {}
    local okList, segments = pcall(C_DamageMeter.GetAvailableCombatSessions)
    if okList and segments then
        pcall(table.sort, segments, function(a, b) return a.sessionID < b.sessionID end)
        for _, seg in ipairs(segments) do
            local sid = DMY._PlainNumber(seg.sessionID)
            if sid then
                local ok, session = pcall(C_DamageMeter.GetCombatSessionFromID, sid, 9)
                if ok then
                    local name = DMY._PlainValue(seg.name)
                    if not name or name == "" then name = "Combat #" .. tostring(sid) end
                    retained[#retained + 1] = {
                        session = session, name = name,
                        dur = DMY._PlainNumber(seg.durationSeconds)
                            or (session and DMY._PlainNumber(session.durationSeconds)),
                    }
                end
            end
        end
    end
    local okCur, currentSession = false, nil
    if C_DamageMeter.GetCombatSessionFromType then
        okCur, currentSession = pcall(C_DamageMeter.GetCombatSessionFromType, 1, 9)
    end

    -- Death times are positions on the OVERALL window's clock (its top-left
    -- timer), not within their own segment. Base = Overall total minus every
    -- duration still accounted for — nonzero only when old segments have been
    -- evicted from the Available list; sub-second residue is duration
    -- rounding, not eviction. (If the just-ended combat sits in BOTH the
    -- Available list and the Current slot, its duration is subtracted twice —
    -- the clamp absorbs that in the no-eviction case; with eviction the base
    -- can under-count by at most that one combat.)
    local base, retainedSum = 0, 0
    for _, r in ipairs(retained) do
        retainedSum = retainedSum + (r.dur or 0)
    end
    if C_DamageMeter.GetSessionDurationSeconds then
        local okT, total = pcall(C_DamageMeter.GetSessionDurationSeconds, 0)
        total = okT and DMY._PlainNumber(total) or nil
        if total then
            local currentDur = (okCur and currentSession)
                and DMY._PlainNumber(currentSession.durationSeconds) or nil
            base = total - retainedSum - (currentDur or 0)
            if base < 1 then base = 0 end
        end
    end

    -- Pass 2: absorb with running offsets. Named/expired segments first so
    -- their labels win over "Current".
    local offset = base
    for _, r in ipairs(retained) do
        Absorb(r.session, r.name, offset)
        offset = (offset and r.dur) and (offset + r.dur) or nil
    end
    -- The latest combat may not be in the Available list yet; when it is,
    -- its deaths were indexed above and the dedup makes this a no-op.
    if okCur then Absorb(currentSession, "Current", offset) end

    DMY._recapSegmentIndex = index
    DMY._recapSegmentIndexDirty = false
end

--------------------------------------------------------------------------------
-- In-combat drilldown GUID resolution.
--
-- A row clicked during combat has no plain sourceGUID (the merged key is a
-- "rank_N" placeholder), but the source API only rejects SECRET arguments from
-- tainted context — a plain GUID passed in combat is a legal query. Two plain
-- sources exist: the local player's own GUID (UnitGUID("player") is never
-- secret) and the OOC-rebuilt identity cache, guarded by the CURRENT session's
-- collision map so a duplicate class+spec in this pull can never open another
-- player's breakdown. Counters feed /scoot debug dmY drillstate.
--------------------------------------------------------------------------------

DMY._drillCounts = { tierLocal = 0, tierCache = 0, unresolved = 0,
                     queryFail = 0, emptyData = 0, popOk = 0, popFail = 0,
                     -- Deaths drilldown links (death log + recap views)
                     dlogOk = 0, dlogEmpty = 0, dlogAmbig = 0, dlogFail = 0,
                     recapOk = 0, recapEmpty = 0, recapFail = 0,
                     segHit = 0, segMiss = 0 }

-- Returns a plain GUID for a row clicked during combat, or nil to fall back
-- to the pending placeholder.
function DMY._ResolveCombatSourceGUID(row, merged)
    local counts = DMY._drillCounts

    if row and row._isLocalPlayer == true then
        local ok, guid = pcall(UnitGUID, "player")
        guid = ok and PlainGUID(guid) or nil
        if guid then
            counts.tierLocal = counts.tierLocal + 1
            return guid
        end
    end

    local ikey = row and row._identityKey
    if ikey and not (merged and merged.identityCollisions and merged.identityCollisions[ikey]) then
        local mapped = DMY._identityToGUID and DMY._identityToGUID[ikey]
        if mapped and mapped ~= false then
            counts.tierCache = counts.tierCache + 1
            return mapped
        end
    end

    counts.unresolved = counts.unresolved + 1
    return nil
end

--------------------------------------------------------------------------------
-- Roster name map + display-name resolution (Hide Realm Names)
--
-- rosterNames maps plain UnitGUIDs to plain realm-free names captured from the
-- group roster. UnitName's first return never includes the realm for same-realm
-- players; the match is belt-and-braces for cross-realm "Name-Realm" strings.
-- Rebuilt OOC alongside the GUID cache, commit-only-if-nonempty for the same
-- reason. UnitName can return a secret in identity-restricted content, so the
-- value is never operated on until issecretvalue proves it plain.
--------------------------------------------------------------------------------

DMY._rosterNames = {}  -- { [guid] = plain realm-free name }
DMY._nameTierCounts = { plain = 0, roster = 0, inspect = 0, ambiguate = 0, raw = 0 }

local function PlainRosterName(unit)
    local ok, n = pcall(UnitName, unit)
    if not ok or n == nil then return nil end
    if issecretvalue and issecretvalue(n) then return nil end
    if type(n) ~= "string" then return nil end
    return n:match("^([^%-]+)") or n
end

function DMY._RebuildRosterNames()
    if DMY._inCombat then return end

    local map = {}
    local ok, pGuid = pcall(UnitGUID, "player")
    pGuid = ok and PlainGUID(pGuid) or nil
    local pName = PlainRosterName("player")
    if pGuid and pName then
        map[pGuid] = pName
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
            guid = gOk and PlainGUID(guid) or nil
            local name = PlainRosterName(unit)
            if guid and name then
                map[guid] = name
            end
        end
    end

    if next(map) then
        DMY._rosterNames = map
    end
end

-- Resolve the name painted on a meter row when Hide Realm Names is on.
-- Tier 0: plain name, stripped directly (player names cannot contain hyphens,
--         so the hyphen always delimits Name-Realm).
-- Tier 1: secret name correlated to a plain roster/inspect name via identity
--         key. Guarded by the CURRENT session's collision map so a duplicate
--         class+spec in this pull can never borrow the other player's name.
-- Tier 2: Ambiguate(name, "short") on the secret itself — "short" removes the
--         realm unconditionally (unlike "none"), is AllowedWhenTainted since
--         12.0.5, and its secret result is a legal SetText argument.
--         Truthiness only on the result, never a comparison.
-- Tier 3: the untouched name (today's behavior).
function DMY._ResolveDisplayName(player, key, merged)
    local name = player.name
    local counts = DMY._nameTierCounts

    if type(name) == "string" and not (issecretvalue and issecretvalue(name)) then
        counts.plain = counts.plain + 1
        return name:match("^([^%-]+)") or name
    end

    local ikey = player.identityKey
    if ikey and not (merged and merged.identityCollisions and merged.identityCollisions[ikey]) then
        local guid
        if type(key) == "string" and not key:find("^rank_") then
            guid = key -- OOC merged key IS the plain GUID
        else
            local mapped = DMY._identityToGUID and DMY._identityToGUID[ikey]
            if mapped and mapped ~= false then guid = mapped end
        end
        if guid then
            local n = DMY._rosterNames and DMY._rosterNames[guid]
            if type(n) == "string" then
                counts.roster = counts.roster + 1
                return n
            end
            local cached = addon.Inspect and addon.Inspect:GetUnitInfo(guid)
            n = cached and cached.name -- realm-stripped at inspect capture time
            if type(n) == "string" then
                counts.inspect = counts.inspect + 1
                return n
            end
        end
    end

    if Ambiguate then
        local ok, short = pcall(Ambiguate, name, "short")
        if ok and short then
            counts.ambiguate = counts.ambiguate + 1
            return short
        end
    end

    counts.raw = counts.raw + 1
    return name
end

--------------------------------------------------------------------------------
-- QueryMergedData — Core data pipeline
--
-- Returns a merged table with all players and their values across all columns.
-- During combat, the primary column uses session-level combatSources
-- (engine-sorted); secondary columns query each metric's own session and
-- correlate rows by identity key (NeverSecret class/spec/isLocalPlayer) —
-- both sides read in the same refresh, so values follow players across
-- mid-combat rank changes. Out of combat, all columns are GUID-correlated
-- via session-level lookups (exact, collision-free).
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
                    local guid = PlainGUID(source.sourceGUID)
                    if guid then
                        guidLookups[meterType][guid] = source
                    end
                end
            end
        end
    end

    -- Combat: query each secondary meter type's own session and correlate by
    -- identity key. Both sides of the correlation (row ikey from the primary
    -- session, value ikey from the secondary session) are read in the same
    -- refresh, so values follow players across mid-combat rank changes with
    -- no stored-GUID prerequisite.
    local secondaryByIdentity  -- { [ikey] = { [mt] = totalAmount (secret ok) / plain deaths count } }
    local secondaryPresence    -- { [ikey] = { [mt] = true } } — plain display gate
    local secondaryQueried     -- { [mt] = true } — query pcall succeeded (nil session = all-zero)
    local identityCollisions   -- { [ikey] = true } — ambiguous rows show the em dash
    if inCombat then
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
            secondaryByIdentity, secondaryPresence = {}, {}
            secondaryQueried, identityCollisions = {}, {}

            for mt in pairs(secondaryTypes) do
                local ok, result
                if sessionID then
                    ok, result = pcall(C_DamageMeter.GetCombatSessionFromID, sessionID, mt)
                else
                    ok, result = pcall(C_DamageMeter.GetCombatSessionFromType, sessionType, mt)
                end
                if ok then
                    secondaryQueried[mt] = true
                    if result then
                        sessions[mt] = result -- feeds merged.maxAmounts below
                        local seenThisSession = {}
                        for _, src in ipairs(result.combatSources or {}) do
                            local ikey = BuildIdentityKey(src.classFilename, src.specIconID, src.isLocalPlayer)
                            local bucket = secondaryByIdentity[ikey]
                            if not bucket then
                                bucket = {}
                                secondaryByIdentity[ikey] = bucket
                                secondaryPresence[ikey] = {}
                            end
                            if mt == 9 then
                                -- Deaths session = one entry per death EVENT; repeats
                                -- of an ikey are the same player dying again, so count
                                -- them (plain integer). Genuine two-player ambiguity is
                                -- caught by the primary-session duplicate check below.
                                bucket[mt] = (bucket[mt] or 0) + 1
                                secondaryPresence[ikey][mt] = true
                            elseif seenThisSession[ikey] then
                                identityCollisions[ikey] = true
                            else
                                seenThisSession[ikey] = true
                                bucket[mt] = src.totalAmount -- may be secret; only ever SetText'd
                                secondaryPresence[ikey][mt] = true
                            end
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
        secondaryPresence = secondaryPresence,      -- plain display gate (combat only)
        secondaryQueried = secondaryQueried,        -- per-mt query success (combat only)
        identityCollisions = identityCollisions,    -- ambiguous ikeys (combat only)
        durationSeconds = primarySession.durationSeconds,
        sessionType = sessionType,
    }

    -- Collect max amounts per meter type
    for meterType, session in pairs(sessions) do
        merged.maxAmounts[meterType] = session.maxAmount
    end

    -- Iterate primary session (engine-sorted order = rank)
    local seenGUIDs = {}
    local primarySeenIkeys = identityCollisions and {}
    for rank, source in ipairs(primarySession.combatSources) do
        -- In combat, sourceGUID is secret — cannot use as table key or compare.
        -- Use rank-based keys and skip duplicate detection entirely.
        local guid = not inCombat and PlainGUID(source.sourceGUID) or nil
        local key = guid or ("rank_" .. rank)

        -- Skip duplicate GUIDs (OOC only)
        if inCombat or (guid and not seenGUIDs[guid]) then
            if guid then seenGUIDs[guid] = true end

            table.insert(merged.playerOrder, key)

            -- Build identity key from NeverSecret fields (works in combat)
            local identityKey = BuildIdentityKey(source.classFilename, source.specIconID, source.isLocalPlayer)

            -- Same class+spec twice in the primary session = ambiguous identity;
            -- gate those rows' secondary columns even if only one of the pair
            -- appears in a secondary session.
            if primarySeenIkeys then
                if primarySeenIkeys[identityKey] then
                    identityCollisions[identityKey] = true
                else
                    primarySeenIkeys[identityKey] = true
                end
            end

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

    -- Deaths values are Scoot-computed per-player counts, but the engine's
    -- session ordering and maxAmount are per-EVENT (most recent death first).
    -- OOC: re-sort a deaths-primary window by count (recency as tiebreak) and
    -- normalize death bars against the highest count. Combat path untouched.
    if deathCounts then
        if primaryDef.isDeaths then
            local origIndex = {}
            for i, key in ipairs(merged.playerOrder) do origIndex[key] = i end
            table.sort(merged.playerOrder, function(a, b)
                local ca, cb = deathCounts[a] or 0, deathCounts[b] or 0
                if ca ~= cb then return ca > cb end
                return origIndex[a] < origIndex[b]
            end)
            for i, key in ipairs(merged.playerOrder) do
                local p = merged.players[key]
                if p then p.rank = i end
            end
        end
        local maxCount = 0
        for _, c in pairs(deathCounts) do
            if c > maxCount then maxCount = c end
        end
        merged.maxAmounts[9] = maxCount
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

    -- Simple format. Rows come from the primary session, so a missing value
    -- means the player scored zero in this metric — display parity with combat.
    local val = player.values[def.meterType]
    if not val then return "0" end
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
