-- dmY.lua - /scoot debug dmY: Modern damage meter probes for CVars, GUIDs, and source APIs
local addonName, addon = ...

--------------------------------------------------------------------------------
-- /scoot debug dmY cvar — Test 1: CVar data collection
--------------------------------------------------------------------------------

local function DebugDMYCVar()
    if InCombatLockdown() then
        addon:Print("Cannot toggle CVar during combat.")
        return
    end

    if not (C_DamageMeter and C_DamageMeter.GetCombatSessionFromType) then
        addon:Print("C_DamageMeter API not available.")
        return
    end

    local current = C_CVar.GetCVar("damageMeterEnabled")

    -- First run: CVar is "1" → set to "0" and instruct user
    if current ~= "0" then
        C_CVar.SetCVar("damageMeterEnabled", "0")
        addon:Print("DMY CVar Test: Set damageMeterEnabled = 0")
        addon:Print("  Blizzard meter is now hidden.")
        addon:Print("  1) Enter combat (dungeon trash or target dummy)")
        addon:Print("  2) After combat ends, run: /scoot debug dmY cvar")
        return
    end

    -- Second run: CVar is "0" → check data, restore, report
    local lines = { "== DMY CVar Test ==" }
    table.insert(lines, "CVar was: 0 (Blizzard meter disabled)")

    C_CVar.SetCVar("damageMeterEnabled", "1")
    table.insert(lines, "Restored CVar to: 1")
    table.insert(lines, "")

    local sessionTests = {
        { label = "Overall",  type = Enum.DamageMeterSessionType.Overall },
        { label = "Current",  type = Enum.DamageMeterSessionType.Current },
    }

    local anyData = false
    for _, test in ipairs(sessionTests) do
        local ok, session = pcall(C_DamageMeter.GetCombatSessionFromType, test.type, Enum.DamageMeterType.DamageDone)
        table.insert(lines, test.label .. " (DamageDone):")
        if not ok or not session then
            table.insert(lines, "  Query failed or returned nil")
        else
            local sourceCount = session.combatSources and #session.combatSources or 0
            table.insert(lines, "  combatSources count: " .. sourceCount)
            table.insert(lines, "  maxAmount: " .. tostring(session.maxAmount))
            table.insert(lines, "  totalAmount: " .. tostring(session.totalAmount))
            table.insert(lines, "  durationSeconds: " .. tostring(session.durationSeconds))
            if sourceCount > 0 then
                anyData = true
                table.insert(lines, "  RESULT: DATA COLLECTED WITH CVAR=0")
            else
                table.insert(lines, "  RESULT: NO DATA (0 sources)")
            end
        end
        table.insert(lines, "")
    end

    if anyData then
        table.insert(lines, "VERDICT: Safe to use CVar disable strategy for V2.")
        table.insert(lines, "  Setting damageMeterEnabled=0 hides the Blizzard UI but the")
        table.insert(lines, "  engine continues collecting combat data via C_DamageMeter.")
    else
        table.insert(lines, "VERDICT: CVar kills data collection — need fallback strategy.")
        table.insert(lines, "  V2 must keep CVar=1 and hide Blizzard's frame via")
        table.insert(lines, "  off-screen positioning or scale trick.")
    end

    addon.DebugShowWindow("DMY CVar Test", table.concat(lines, "\n"))
end

--------------------------------------------------------------------------------
-- /scoot debug dmY api — Tests 2-4: sourceGUID secrecy, SetText, SetValue
--------------------------------------------------------------------------------

-- Reusable hidden test frame (created once, reused across calls)
local testFrame, testBar, testText

local function EnsureTestFrame()
    if testFrame then return end
    testFrame = CreateFrame("Frame", nil, UIParent)
    testFrame:SetSize(200, 20)
    testFrame:SetPoint("CENTER", UIParent, "CENTER", 0, -10000) -- off-screen
    testFrame:Hide()

    testBar = CreateFrame("StatusBar", nil, testFrame)
    testBar:SetSize(180, 16)
    testBar:SetPoint("CENTER")

    testText = testBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    testText:SetPoint("CENTER")
end

local function TestSecret(value)
    -- issecretvalue may not exist on all builds
    if issecretvalue then
        local ok, result = pcall(issecretvalue, value)
        if ok then return result end
    end
    -- Fallback: try tostring — secrets error on tostring in some contexts
    -- but type() always works. If issecretvalue isn't available, the result is uncertain.
    return nil -- unknown
end

local function FormatSecretResult(isSecret)
    if isSecret == true then return "true"
    elseif isSecret == false then return "false"
    else return "unknown (issecretvalue not available)"
    end
end

local function FormatSafeValue(value, isSecret)
    if isSecret == true then return "(secret)" end
    if value == nil then return "nil" end
    return tostring(value)
end

local function RunAPITests()
    local lines = { "== DMY API Secrecy Test ==" }
    local inCombat = InCombatLockdown()

    if inCombat then
        table.insert(lines, "Run context: IN COMBAT (results are meaningful)")
    else
        table.insert(lines, "Run context: OUT OF COMBAT (all values non-secret)")
        table.insert(lines, "  Re-run during combat for real secrecy test.")
    end
    table.insert(lines, "")

    if not (C_DamageMeter and C_DamageMeter.GetCombatSessionFromType) then
        table.insert(lines, "ERROR: C_DamageMeter API not available.")
        return lines
    end

    -- Query two different meter types
    local ok1, sessionDmg = pcall(C_DamageMeter.GetCombatSessionFromType,
        Enum.DamageMeterSessionType.Overall, Enum.DamageMeterType.DamageDone)
    local ok2, sessionHeal = pcall(C_DamageMeter.GetCombatSessionFromType,
        Enum.DamageMeterSessionType.Overall, Enum.DamageMeterType.HealingDone)

    if not ok1 or not sessionDmg or not sessionDmg.combatSources or #sessionDmg.combatSources == 0 then
        table.insert(lines, "ERROR: No DamageDone data available. Fight something first.")
        if not ok1 then table.insert(lines, "  pcall error: " .. tostring(sessionDmg)) end
        return lines
    end

    local dmgSources = sessionDmg.combatSources
    local healSources = (ok2 and sessionHeal and sessionHeal.combatSources) or {}

    table.insert(lines, string.format("DamageDone sources: %d | HealingDone sources: %d",
        #dmgSources, #healSources))
    table.insert(lines, "")

    --------------------------------------------------------------------------
    -- Test 2: Field secrecy on first source
    --------------------------------------------------------------------------
    table.insert(lines, "--- Field Secrecy (DamageDone, source 1) ---")

    local src = dmgSources[1]
    local fields = {
        { name = "sourceGUID",      value = src.sourceGUID,      expected = "unknown" },
        { name = "name",            value = src.name,            expected = "ConditionalSecret" },
        { name = "totalAmount",     value = src.totalAmount,     expected = "secret in combat" },
        { name = "amountPerSecond", value = src.amountPerSecond, expected = "secret in combat" },
        { name = "classFilename",   value = src.classFilename,   expected = "NeverSecret" },
        { name = "specIconID",      value = src.specIconID,      expected = "NeverSecret" },
        { name = "isLocalPlayer",   value = src.isLocalPlayer,   expected = "NeverSecret" },
        { name = "deathRecapID",    value = src.deathRecapID,    expected = "NeverSecret" },
    }

    for _, f in ipairs(fields) do
        local isSecret = TestSecret(f.value)
        local safeVal = FormatSafeValue(f.value, isSecret)
        table.insert(lines, string.format("  %-18s type=%-8s issecret=%-8s value=%s  (%s)",
            f.name .. ":", type(f.value), FormatSecretResult(isSecret), safeVal, f.expected))
    end
    table.insert(lines, "")

    -- Also test session-level maxAmount
    table.insert(lines, "--- Session-Level Fields ---")
    local maxSecret = TestSecret(sessionDmg.maxAmount)
    table.insert(lines, string.format("  %-18s type=%-8s issecret=%-8s value=%s",
        "maxAmount:", type(sessionDmg.maxAmount), FormatSecretResult(maxSecret),
        FormatSafeValue(sessionDmg.maxAmount, maxSecret)))
    local totalSecret = TestSecret(sessionDmg.totalAmount)
    table.insert(lines, string.format("  %-18s type=%-8s issecret=%-8s value=%s",
        "totalAmount:", type(sessionDmg.totalAmount), FormatSecretResult(totalSecret),
        FormatSafeValue(sessionDmg.totalAmount, totalSecret)))
    local durSecret = TestSecret(sessionDmg.durationSeconds)
    table.insert(lines, string.format("  %-18s type=%-8s issecret=%-8s value=%s",
        "durationSeconds:", type(sessionDmg.durationSeconds), FormatSecretResult(durSecret),
        FormatSafeValue(sessionDmg.durationSeconds, durSecret)))
    table.insert(lines, "")

    --------------------------------------------------------------------------
    -- Test 2b: Cross-session GUID correlation
    --------------------------------------------------------------------------
    table.insert(lines, "--- Cross-Session GUID Correlation ---")

    local guidA = src.sourceGUID

    -- Table key test
    local okKey, errKey = pcall(function()
        local t = {}
        t[guidA] = true
        return t[guidA]
    end)
    if okKey then
        table.insert(lines, "  Table key with sourceGUID:   OK (can use as table key)")
    else
        table.insert(lines, "  Table key with sourceGUID:   FAILED — " .. tostring(errKey))
    end

    -- Cross-session comparison
    if #healSources > 0 then
        local guidB = healSources[1].sourceGUID
        local okCmp, errCmp = pcall(function()
            return guidA == guidB
        end)
        if okCmp then
            table.insert(lines, "  Cross-session GUID compare:  OK (comparison succeeded)")
        else
            table.insert(lines, "  Cross-session GUID compare:  FAILED — " .. tostring(errCmp))
        end

        -- Try building a lookup from one and accessing from the other
        local okLookup, errLookup = pcall(function()
            local lookup = {}
            for _, s in ipairs(dmgSources) do
                if s.sourceGUID then lookup[s.sourceGUID] = s end
            end
            local found = 0
            for _, s in ipairs(healSources) do
                if s.sourceGUID and lookup[s.sourceGUID] then found = found + 1 end
            end
            return found
        end)
        if okLookup then
            table.insert(lines, string.format("  GUID lookup (dmg→heal):      OK (%s matches found)", tostring(errLookup)))
        else
            table.insert(lines, "  GUID lookup (dmg→heal):      FAILED — " .. tostring(errLookup))
        end
    else
        table.insert(lines, "  Cross-session compare:       SKIPPED (no HealingDone data)")
        table.insert(lines, "  GUID lookup (dmg→heal):      SKIPPED (no HealingDone data)")
    end
    table.insert(lines, "")

    --------------------------------------------------------------------------
    -- Tests 3-4: SetText and SetValue on Scoot-owned frames
    --------------------------------------------------------------------------
    table.insert(lines, "--- Scoot-Owned Frame Tests ---")

    EnsureTestFrame()

    -- SetMinMaxValues with potentially secret maxAmount
    local okMM, errMM = pcall(function()
        testBar:SetMinMaxValues(0, sessionDmg.maxAmount)
    end)
    table.insert(lines, string.format("  SetMinMaxValues(0, maxAmount):  %s",
        okMM and "OK" or ("FAILED — " .. tostring(errMM))))

    -- SetValue with secret totalAmount
    local okSV, errSV = pcall(function()
        testBar:SetValue(src.totalAmount)
    end)
    table.insert(lines, string.format("  SetValue(totalAmount):          %s",
        okSV and "OK" or ("FAILED — " .. tostring(errSV))))

    -- SetText with secret name
    local okTN, errTN = pcall(function()
        testText:SetText(src.name)
    end)
    table.insert(lines, string.format("  SetText(name):                  %s",
        okTN and "OK" or ("FAILED — " .. tostring(errTN))))

    -- SetText with secret totalAmount (number → display)
    local okTA, errTA = pcall(function()
        testText:SetText(src.totalAmount)
    end)
    table.insert(lines, string.format("  SetText(totalAmount):           %s",
        okTA and "OK" or ("FAILED — " .. tostring(errTA))))

    -- SetText with secret amountPerSecond
    local okAPS, errAPS = pcall(function()
        testText:SetText(src.amountPerSecond)
    end)
    table.insert(lines, string.format("  SetText(amountPerSecond):       %s",
        okAPS and "OK" or ("FAILED — " .. tostring(errAPS))))
    table.insert(lines, "")

    --------------------------------------------------------------------------
    -- Verdict
    --------------------------------------------------------------------------
    table.insert(lines, "--- VERDICT ---")

    local guidSecret = TestSecret(guidA)
    local guidKeyWorks = okKey
    local guidCmpWorks = (#healSources > 0) and (select(1, pcall(function() return guidA == (healSources[1].sourceGUID) end))) or nil

    if guidSecret == false or (guidKeyWorks and guidCmpWorks) then
        table.insert(lines, "  sourceGUID: NeverSecret (or usable as key/comparable)")
        table.insert(lines, "    -> Strategy C: full multi-column live updates during combat")
    elseif guidSecret == true or (not guidKeyWorks) then
        table.insert(lines, "  sourceGUID: Secret during combat")
        table.insert(lines, "    -> Strategy A: primary column only during combat,")
        table.insert(lines, "       full refresh on combat end")
    else
        table.insert(lines, "  sourceGUID: INCONCLUSIVE (run during combat to get definitive answer)")
    end

    local frameTestsOK = okMM and okSV and okTN and okTA and okAPS
    if frameTestsOK then
        table.insert(lines, "  SetText/SetValue on Scoot frames: All OK")
    else
        table.insert(lines, "  SetText/SetValue on Scoot frames: SOME FAILED (see above)")
    end

    return lines
end

local function DebugDMYAPI()
    local lines = RunAPITests()
    local output = table.concat(lines, "\n")

    if InCombatLockdown() then
        addon:Print("DMY API test collected. Results will show after combat ends.")
    end
    -- Deferred in combat to avoid taint from UI creation during combat
    addon.Events.RunOutOfCombat(function()
        addon.DebugShowWindow("DMY API Secrecy Test", output)
    end)
end

--------------------------------------------------------------------------------
-- /scoot debug dmY fields — Exhaustive mid-combat field dump
-- Purpose: find any non-secret identifier that could correlate players across
-- meter types during combat (solving the rank-drift problem).
--------------------------------------------------------------------------------

local ALL_METER_TYPES = {
    { key = "DamageDone",           enum = Enum.DamageMeterType.DamageDone },
    { key = "Dps",                  enum = Enum.DamageMeterType.Dps },
    { key = "HealingDone",          enum = Enum.DamageMeterType.HealingDone },
    { key = "Hps",                  enum = Enum.DamageMeterType.Hps },
    { key = "Absorbs",              enum = Enum.DamageMeterType.Absorbs },
    { key = "Interrupts",           enum = Enum.DamageMeterType.Interrupts },
    { key = "Dispels",              enum = Enum.DamageMeterType.Dispels },
    { key = "DamageTaken",          enum = Enum.DamageMeterType.DamageTaken },
    { key = "AvoidableDamageTaken", enum = Enum.DamageMeterType.AvoidableDamageTaken },
    { key = "Deaths",               enum = Enum.DamageMeterType.Deaths },
    { key = "EnemyDamageTaken",     enum = Enum.DamageMeterType.EnemyDamageTaken },
}

local KNOWN_FIELDS = {
    "sourceGUID", "sourceCreatureID", "name", "classFilename", "specIconID",
    "totalAmount", "amountPerSecond", "isLocalPlayer", "deathRecapID",
    "deathTimeSeconds", "classification",
}

local function FieldSecrecy(value)
    if issecretvalue then
        local ok, result = pcall(issecretvalue, value)
        if ok then return result end
    end
    return nil
end

local function SafeDisplay(value, isSecret)
    if isSecret == true then return "(secret)" end
    if value == nil then return "nil" end
    return tostring(value)
end

local function RunFieldsDump()
    local lines = { "== DMY Exhaustive Field Dump ==" }
    local inCombat = InCombatLockdown()

    if inCombat then
        table.insert(lines, "Context: IN COMBAT — secrecy results are meaningful")
    else
        table.insert(lines, "Context: OUT OF COMBAT — all values non-secret")
        table.insert(lines, "  Re-run DURING COMBAT for real results.")
    end
    table.insert(lines, "")

    if not (C_DamageMeter and C_DamageMeter.GetCombatSessionFromType) then
        table.insert(lines, "ERROR: C_DamageMeter API not available.")
        return lines
    end

    --------------------------------------------------------------------------
    -- Section 1: All fields on every source, every meter type
    --------------------------------------------------------------------------
    table.insert(lines, "========================================")
    table.insert(lines, "SECTION 1: Per-Source Field Dump (Overall)")
    table.insert(lines, "========================================")
    table.insert(lines, "")

    -- Collect sessions and track non-secret fields for later analysis
    local sessionsByType = {}
    local nonSecretFields = {}  -- { fieldName = { count, exampleValue } }

    for _, mt in ipairs(ALL_METER_TYPES) do
        local ok, session = pcall(C_DamageMeter.GetCombatSessionFromType,
            Enum.DamageMeterSessionType.Overall, mt.enum)
        if ok and session and session.combatSources and #session.combatSources > 0 then
            sessionsByType[mt.key] = session
            table.insert(lines, string.format("--- %s (%d sources) ---", mt.key, #session.combatSources))

            for srcIdx, src in ipairs(session.combatSources) do
                table.insert(lines, string.format("  Source #%d:", srcIdx))
                for _, fieldName in ipairs(KNOWN_FIELDS) do
                    local val = src[fieldName]
                    local isSecret = FieldSecrecy(val)
                    local marker = ""
                    if val ~= nil and isSecret == false then
                        marker = "  *** NON-SECRET ***"
                        if not nonSecretFields[fieldName] then
                            nonSecretFields[fieldName] = { count = 0, values = {} }
                        end
                        nonSecretFields[fieldName].count = nonSecretFields[fieldName].count + 1
                        table.insert(nonSecretFields[fieldName].values, { meterType = mt.key, srcIdx = srcIdx, value = val })
                    end
                    table.insert(lines, string.format("    %-20s type=%-8s secret=%-6s value=%s%s",
                        fieldName, type(val), tostring(isSecret), SafeDisplay(val, isSecret), marker))
                end
            end
            table.insert(lines, "")
        end
    end

    if not next(sessionsByType) then
        table.insert(lines, "ERROR: No session data for any meter type. Fight something first.")
        return lines
    end

    --------------------------------------------------------------------------
    -- Section 2: sourceCreatureID correlation test
    --------------------------------------------------------------------------
    table.insert(lines, "========================================")
    table.insert(lines, "SECTION 2: sourceCreatureID Correlation")
    table.insert(lines, "========================================")
    table.insert(lines, "")

    local cidInfo = nonSecretFields["sourceCreatureID"]
    if not cidInfo or cidInfo.count == 0 then
        table.insert(lines, "sourceCreatureID: NOT non-secret (or nil on all sources)")
        table.insert(lines, "  Cannot use as combat correlator.")
    else
        table.insert(lines, string.format("sourceCreatureID: non-secret on %d source(s)", cidInfo.count))
        table.insert(lines, "")

        -- Table key test
        local testVal = cidInfo.values[1].value
        local okKey, errKey = pcall(function()
            local t = {}
            t[testVal] = true
            return t[testVal]
        end)
        table.insert(lines, string.format("  Table key test: %s",
            okKey and "OK — can use as table key" or ("FAILED — " .. tostring(errKey))))

        -- Uniqueness within DamageDone
        local dmgSession = sessionsByType["DamageDone"]
        if dmgSession then
            local cidSet = {}
            local dupes = 0
            local nilCount = 0
            for _, src in ipairs(dmgSession.combatSources) do
                local cid = src.sourceCreatureID
                local cidSecret = FieldSecrecy(cid)
                if cid == nil then
                    nilCount = nilCount + 1
                elseif cidSecret == false then
                    local okStr, cidStr = pcall(tostring, cid)
                    if okStr then
                        if cidSet[cidStr] then dupes = dupes + 1
                        else cidSet[cidStr] = true end
                    end
                end
            end
            table.insert(lines, string.format("  Uniqueness in DamageDone: %d unique, %d duplicates, %d nil",
                (function() local n = 0; for _ in pairs(cidSet) do n = n + 1 end; return n end)(),
                dupes, nilCount))
        end

        -- Cross-metric stability: same player → same creatureID across types?
        table.insert(lines, "")
        table.insert(lines, "  Cross-metric creatureID stability:")
        local dmgLookup = {}
        if dmgSession then
            for i, src in ipairs(dmgSession.combatSources) do
                local cid = src.sourceCreatureID
                local cidSecret = FieldSecrecy(cid)
                if cid ~= nil and cidSecret == false then
                    local okConv, cidKey = pcall(tostring, cid)
                    if okConv then
                        dmgLookup[cidKey] = { index = i, classFilename = src.classFilename }
                    end
                end
            end
        end

        local healSession = sessionsByType["HealingDone"]
        if healSession and next(dmgLookup) then
            local matches = 0
            local misses = 0
            for _, src in ipairs(healSession.combatSources) do
                local cid = src.sourceCreatureID
                local cidSecret = FieldSecrecy(cid)
                if cid ~= nil and cidSecret == false then
                    local okConv, cidKey = pcall(tostring, cid)
                    if okConv then
                        local dmgEntry = dmgLookup[cidKey]
                        if dmgEntry then
                            matches = matches + 1
                            table.insert(lines, string.format("    MATCH: creatureID=%s  dmg_class=%s  heal_class=%s",
                                cidKey, tostring(dmgEntry.classFilename), tostring(src.classFilename)))
                        else
                            misses = misses + 1
                        end
                    end
                end
            end
            table.insert(lines, string.format("    Total: %d matches, %d unmatched heal sources", matches, misses))
        else
            table.insert(lines, "    SKIPPED — need both DamageDone and HealingDone data")
        end
    end
    table.insert(lines, "")

    --------------------------------------------------------------------------
    -- Section 3: Composite key feasibility
    --------------------------------------------------------------------------
    table.insert(lines, "========================================")
    table.insert(lines, "SECTION 3: Composite Key Feasibility")
    table.insert(lines, "========================================")
    table.insert(lines, "")

    local dmgSession = sessionsByType["DamageDone"]
    if dmgSession then
        local classSet = {}
        local classSpecSet = {}
        local totalSources = #dmgSession.combatSources
        for _, src in ipairs(dmgSession.combatSources) do
            local cls = src.classFilename
            local spec = src.specIconID
            local clsSecret = FieldSecrecy(cls)
            local specSecret = FieldSecrecy(spec)
            if clsSecret == false then
                classSet[tostring(cls)] = true
                if specSecret == false and spec ~= nil then
                    classSpecSet[tostring(cls) .. ":" .. tostring(spec)] = true
                end
            end
        end
        local uniqueClass = 0
        for _ in pairs(classSet) do uniqueClass = uniqueClass + 1 end
        local uniqueClassSpec = 0
        for _ in pairs(classSpecSet) do uniqueClassSpec = uniqueClassSpec + 1 end

        table.insert(lines, string.format("  Total sources: %d", totalSources))
        table.insert(lines, string.format("  Unique classFilename values: %d", uniqueClass))
        table.insert(lines, string.format("  Unique classFilename+specIconID combos: %d", uniqueClassSpec))
        if uniqueClassSpec == totalSources then
            table.insert(lines, "  RESULT: classFilename+specIconID IS unique — viable composite key for this group")
        elseif uniqueClass == totalSources then
            table.insert(lines, "  RESULT: classFilename alone IS unique — viable for this group (but fragile in raids)")
        else
            table.insert(lines, "  RESULT: NOT unique — composite key not enough for this group")
        end

        -- classification values
        table.insert(lines, "")
        table.insert(lines, "  classification values seen:")
        for _, src in ipairs(dmgSession.combatSources) do
            local c = src.classification
            local cSecret = FieldSecrecy(c)
            table.insert(lines, string.format("    class=%s  classification=%s  secret=%s",
                tostring(src.classFilename), SafeDisplay(c, cSecret), tostring(cSecret)))
        end
    else
        table.insert(lines, "  SKIPPED — no DamageDone data")
    end
    table.insert(lines, "")

    --------------------------------------------------------------------------
    -- Section 4: Raw pairs() dump — discover undocumented fields
    --------------------------------------------------------------------------
    table.insert(lines, "========================================")
    table.insert(lines, "SECTION 4: Raw Table Keys (pairs() dump)")
    table.insert(lines, "========================================")
    table.insert(lines, "")

    if dmgSession and dmgSession.combatSources and #dmgSession.combatSources > 0 then
        local src = dmgSession.combatSources[1]
        table.insert(lines, "DamageDone source #1 — all keys via pairs():")
        local okPairs, errPairs = pcall(function()
            local keys = {}
            for k, v in pairs(src) do
                local kSecret = FieldSecrecy(k)
                local vSecret = FieldSecrecy(v)
                table.insert(keys, {
                    key = SafeDisplay(k, kSecret),
                    keyType = type(k),
                    keySecret = tostring(kSecret),
                    valType = type(v),
                    valSecret = tostring(vSecret),
                    valDisplay = SafeDisplay(v, vSecret),
                })
            end
            return keys
        end)
        if okPairs then
            for _, entry in ipairs(errPairs) do
                local marker = (entry.valSecret == "false") and "  *** NON-SECRET ***" or ""
                table.insert(lines, string.format("  key=%-22s ktype=%-8s vtype=%-8s vsecret=%-6s val=%s%s",
                    entry.key, entry.keyType, entry.valType, entry.valSecret, entry.valDisplay, marker))
            end
        else
            table.insert(lines, "  pairs() FAILED — " .. tostring(errPairs))
            table.insert(lines, "  (table may be secret-protected)")
        end

        -- Also try the session-level table
        table.insert(lines, "")
        table.insert(lines, "DamageDone session — all keys via pairs():")
        local okSPairs, errSPairs = pcall(function()
            local keys = {}
            for k, v in pairs(dmgSession) do
                local kSecret = FieldSecrecy(k)
                local vSecret = FieldSecrecy(v)
                if k ~= "combatSources" then -- skip the big array
                    table.insert(keys, {
                        key = SafeDisplay(k, kSecret),
                        keyType = type(k),
                        valType = type(v),
                        valSecret = tostring(vSecret),
                        valDisplay = SafeDisplay(v, vSecret),
                    })
                else
                    table.insert(keys, {
                        key = "combatSources",
                        keyType = "string",
                        valType = "table",
                        valSecret = "n/a",
                        valDisplay = string.format("(table, %d entries)", #v),
                    })
                end
            end
            return keys
        end)
        if okSPairs then
            for _, entry in ipairs(errSPairs) do
                table.insert(lines, string.format("  key=%-22s ktype=%-8s vtype=%-8s vsecret=%-6s val=%s",
                    entry.key, entry.keyType, entry.valType, entry.valSecret, entry.valDisplay))
            end
        else
            table.insert(lines, "  pairs() FAILED — " .. tostring(errSPairs))
        end
    else
        table.insert(lines, "  SKIPPED — no DamageDone data")
    end
    table.insert(lines, "")

    --------------------------------------------------------------------------
    -- Summary verdict
    --------------------------------------------------------------------------
    table.insert(lines, "========================================")
    table.insert(lines, "SUMMARY")
    table.insert(lines, "========================================")
    table.insert(lines, "")

    local potentialCorrelators = {}
    for fieldName, info in pairs(nonSecretFields) do
        -- Only interesting if it's not one of the already-known NeverSecret display fields
        if fieldName ~= "classFilename" and fieldName ~= "specIconID"
            and fieldName ~= "isLocalPlayer" and fieldName ~= "deathRecapID"
            and fieldName ~= "classification" then
            table.insert(potentialCorrelators, string.format("%s (non-secret on %d sources)", fieldName, info.count))
        end
    end

    if #potentialCorrelators > 0 then
        table.insert(lines, "POTENTIAL NEW CORRELATORS FOUND:")
        for _, desc in ipairs(potentialCorrelators) do
            table.insert(lines, "  -> " .. desc)
        end
        table.insert(lines, "")
        table.insert(lines, "Next step: verify uniqueness and cross-metric stability above.")
    else
        if inCombat then
            table.insert(lines, "NO new non-secret identifiers found during combat.")
            table.insert(lines, "Gray-out mitigation remains the production approach.")
        else
            table.insert(lines, "Run this command DURING COMBAT for meaningful results.")
        end
    end

    -- Always list which known NeverSecret fields were confirmed
    table.insert(lines, "")
    table.insert(lines, "Confirmed NeverSecret fields (already known):")
    for _, fieldName in ipairs({"classFilename", "specIconID", "isLocalPlayer", "deathRecapID", "classification"}) do
        local info = nonSecretFields[fieldName]
        if info then
            table.insert(lines, string.format("  %s — non-secret on %d sources", fieldName, info.count))
        end
    end

    return lines
end

local function DebugDMYFields()
    local lines = RunFieldsDump()
    local output = table.concat(lines, "\n")

    if InCombatLockdown() then
        addon:Print("DMY field dump collected. Results will show after combat ends.")
    end
    addon.Events.RunOutOfCombat(function()
        addon.DebugShowWindow("DMY Field Dump", output)
    end)
end

--------------------------------------------------------------------------------
-- /scoot debug dmY drilldown — In-combat drill-down feasibility test
-- Purpose: determine whether GetCombatSessionSourceFromType can be called from
-- addon code during combat using a pre-stored (non-secret) sourceGUID.
--
-- Two-phase test:
--   Phase 1 (OOC): Store a sourceGUID and verify OOC baseline
--   Phase 2 (combat): Try the source API with the stored GUID
--------------------------------------------------------------------------------

local _storedTestGUID = nil
local _storedTestName = nil
local _storedTestClass = nil

local function RunDrilldownTest()
    local lines = { "== DMY Drill-Down Feasibility Test ==" }
    local inCombat = InCombatLockdown()

    table.insert(lines, string.format("InCombatLockdown(): %s", tostring(inCombat)))
    table.insert(lines, string.format("Stored GUID: %s", _storedTestGUID and "yes" or "none"))
    table.insert(lines, "")

    if not (C_DamageMeter and C_DamageMeter.GetCombatSessionSourceFromType) then
        table.insert(lines, "ERROR: C_DamageMeter source API not available.")
        return lines
    end

    --------------------------------------------------------------------------
    -- Phase 1: OOC — store GUID and verify baseline
    -- Also runs automatically if invoked during combat with no stored GUID,
    -- using UnitGUID("player") as a guaranteed non-secret fallback.
    --------------------------------------------------------------------------
    if not inCombat then
        table.insert(lines, "Phase 1: OUT OF COMBAT — storing GUID and testing OOC baseline")
        table.insert(lines, "")

        -- Get session data for a sourceGUID
        local ok, session = pcall(C_DamageMeter.GetCombatSessionFromType,
            Enum.DamageMeterSessionType.Overall, Enum.DamageMeterType.DamageDone)

        if not ok or not session or not session.combatSources or #session.combatSources == 0 then
            table.insert(lines, "ERROR: No DamageDone data available. Fight something first.")
            if not ok then table.insert(lines, "  pcall error: " .. tostring(session)) end
            return lines
        end

        -- Find first source with a usable GUID
        local src = session.combatSources[1]
        local guid = src.sourceGUID

        if not guid then
            table.insert(lines, "ERROR: First source has no sourceGUID.")
            return lines
        end

        -- Store GUID as plain string
        _storedTestGUID = guid
        _storedTestName = tostring(src.name) or "unknown"
        _storedTestClass = src.classFilename or "unknown"

        table.insert(lines, string.format("Stored GUID for: %s (%s)", _storedTestName, _storedTestClass))
        table.insert(lines, string.format("  GUID: %s", _storedTestGUID))
        table.insert(lines, string.format("  issecretvalue(storedGUID): %s", FormatSecretResult(TestSecret(_storedTestGUID))))
        table.insert(lines, "")

        -- Test R6/8: OOC baseline. Is the source API callable at all?
        table.insert(lines, "--- Test R6: OOC Source API Baseline ---")

        local okSrc, srcResult = pcall(C_DamageMeter.GetCombatSessionSourceFromType,
            Enum.DamageMeterSessionType.Overall, Enum.DamageMeterType.DamageDone,
            _storedTestGUID, nil)

        if not okSrc then
            table.insert(lines, "  GetCombatSessionSourceFromType: FAILED")
            table.insert(lines, "  Error: " .. tostring(srcResult))
            table.insert(lines, "")
            table.insert(lines, "VERDICT: Source API does not work from addon code even OOC.")
            table.insert(lines, "  Drill-down from addon code is not feasible at any time.")
            return lines
        end

        if not srcResult then
            table.insert(lines, "  GetCombatSessionSourceFromType: returned nil")
            table.insert(lines, "")
            table.insert(lines, "VERDICT: Source API returns nil from addon code OOC.")
            table.insert(lines, "  AllowedWhenUntainted may block tainted callers entirely.")
            return lines
        end

        table.insert(lines, "  GetCombatSessionSourceFromType: OK (returned data)")

        -- Dump the result structure
        table.insert(lines, string.format("  maxAmount: %s", tostring(srcResult.maxAmount)))
        table.insert(lines, string.format("  totalAmount: %s", tostring(srcResult.totalAmount)))

        local spells = srcResult.combatSpells
        if spells then
            table.insert(lines, string.format("  combatSpells count: %d", #spells))
            table.insert(lines, "")

            -- Show first 3 spells
            local showCount = math.min(3, #spells)
            for i = 1, showCount do
                local spell = spells[i]
                local spellName = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spell.spellID) or "?"
                table.insert(lines, string.format("  Spell %d:", i))
                table.insert(lines, string.format("    spellID:         %s (%s)", tostring(spell.spellID), spellName))
                table.insert(lines, string.format("    totalAmount:     %s", tostring(spell.totalAmount)))
                table.insert(lines, string.format("    amountPerSecond: %s", tostring(spell.amountPerSecond)))
                table.insert(lines, string.format("    creatureName:    '%s'", tostring(spell.creatureName)))
                table.insert(lines, string.format("    overkillAmount:  %s", tostring(spell.overkillAmount)))
                table.insert(lines, string.format("    isAvoidable:     %s", tostring(spell.isAvoidable)))
                table.insert(lines, string.format("    isDeadly:        %s", tostring(spell.isDeadly)))
            end
        else
            table.insert(lines, "  combatSpells: nil")
        end

        table.insert(lines, "")
        table.insert(lines, "Phase 1 COMPLETE. GUID stored as plain Lua string.")
        table.insert(lines, "  1) Enter combat")
        table.insert(lines, "  2) Re-run: /scoot debug dmY drilldown")
        table.insert(lines, "  The stored GUID will be tested against the source API during combat.")

        return lines
    end

    --------------------------------------------------------------------------
    -- Phase 2: IN COMBAT — test stored GUID against source API
    --------------------------------------------------------------------------
    table.insert(lines, "Phase 2: IN COMBAT — testing stored GUID against source API")
    table.insert(lines, "")

    -- If no stored GUID, auto-store using UnitGUID("player") as a fallback.
    -- UnitGUID("player") is always non-secret and always available.
    if not _storedTestGUID then
        table.insert(lines, "No stored GUID from Phase 1. Auto-storing via UnitGUID(\"player\").")
        local playerGUID = UnitGUID("player")
        if playerGUID then
            _storedTestGUID = playerGUID
            _storedTestName = UnitName("player") or "You"
            _storedTestClass = select(2, UnitClass("player")) or "UNKNOWN"
            table.insert(lines, string.format("  Auto-stored: %s (%s)", _storedTestName, _storedTestClass))
            table.insert(lines, string.format("  GUID: %s", _storedTestGUID))
            table.insert(lines, string.format("  issecretvalue: %s", FormatSecretResult(TestSecret(_storedTestGUID))))
            table.insert(lines, "")
            table.insert(lines, "  NOTE: Skipped Phase 1 OOC baseline. This test only covers R1")
            table.insert(lines, "  (in-combat source API call). Run OOC afterward for full R6 baseline.")
            table.insert(lines, "")
        else
            table.insert(lines, "  ERROR: UnitGUID(\"player\") returned nil. Cannot proceed.")
            return lines
        end
    end

    table.insert(lines, string.format("Stored GUID: %s", _storedTestGUID))
    table.insert(lines, string.format("Stored name: %s (%s)", _storedTestName or "?", _storedTestClass or "?"))

    -- Verify stored GUID is NOT secret (a plain string saved earlier)
    local guidSecret = TestSecret(_storedTestGUID)
    table.insert(lines, string.format("issecretvalue(storedGUID): %s", FormatSecretResult(guidSecret)))
    if guidSecret == true then
        table.insert(lines, "  WARNING: Stored GUID is somehow secret. This should not happen.")
        table.insert(lines, "  The stored copy was a plain Lua string. Re-run Phase 1 OOC.")
        return lines
    end
    table.insert(lines, "")

    --------------------------------------------------------------------------
    -- Test R1: THE GATE QUESTION
    -- Can GetCombatSessionSourceFromType be called from addon code during
    -- combat with a pre-stored (non-secret) GUID?
    --------------------------------------------------------------------------
    table.insert(lines, "--- Test R1: Source API Call During Combat (GATE QUESTION) ---")

    local okSrc, srcResult = pcall(C_DamageMeter.GetCombatSessionSourceFromType,
        Enum.DamageMeterSessionType.Overall, Enum.DamageMeterType.DamageDone,
        _storedTestGUID, nil)

    if not okSrc then
        table.insert(lines, "  R1 RESULT: pcall FAILED")
        table.insert(lines, "  Error: " .. tostring(srcResult))
        table.insert(lines, "")
        table.insert(lines, "VERDICT: Source API REJECTS tainted callers during combat.")
        table.insert(lines, "  AllowedWhenUntainted blocks the call entirely.")
        table.insert(lines, "  Drill-down is confirmed OOC-only. No bypass via stored GUID.")
        table.insert(lines, "  Blizzard can do this because their code runs untainted.")
        return lines
    end

    if not srcResult then
        table.insert(lines, "  R1 RESULT: pcall OK but returned nil")
        table.insert(lines, "")
        table.insert(lines, "VERDICT: Source API returns nil for tainted callers during combat.")
        table.insert(lines, "  Drill-down is confirmed OOC-only. No bypass via stored GUID.")
        table.insert(lines, "  Blizzard can do this because their code runs untainted.")
        return lines
    end

    table.insert(lines, "  R1 RESULT: pcall OK — RETURNED DATA!")
    table.insert(lines, "  The stored-GUID bypass WORKS. Source API is callable during combat.")
    table.insert(lines, "")

    --------------------------------------------------------------------------
    -- Test R2: Session-level field secrecy
    --------------------------------------------------------------------------
    table.insert(lines, "--- Test R2: Source Session Fields ---")

    local maxSecret = TestSecret(srcResult.maxAmount)
    local totalSecret = TestSecret(srcResult.totalAmount)
    table.insert(lines, string.format("  maxAmount:    type=%-8s issecret=%s  value=%s",
        type(srcResult.maxAmount), FormatSecretResult(maxSecret),
        FormatSafeValue(srcResult.maxAmount, maxSecret)))
    table.insert(lines, string.format("  totalAmount:  type=%-8s issecret=%s  value=%s",
        type(srcResult.totalAmount), FormatSecretResult(totalSecret),
        FormatSafeValue(srcResult.totalAmount, totalSecret)))
    table.insert(lines, "")

    --------------------------------------------------------------------------
    -- Test R4: Is combatSpells iterable?
    --------------------------------------------------------------------------
    table.insert(lines, "--- Test R4: combatSpells Iterability ---")

    local spells = srcResult.combatSpells
    if not spells then
        table.insert(lines, "  combatSpells: nil (no spell data returned)")
        table.insert(lines, "")
        return lines
    end

    -- Test #length
    local okLen, lenResult = pcall(function() return #spells end)
    if okLen then
        table.insert(lines, string.format("  #combatSpells: %s (iterable)", tostring(lenResult)))
    else
        table.insert(lines, "  #combatSpells: FAILED — " .. tostring(lenResult))
        table.insert(lines, "  Table may be secret-flagged. Cannot iterate.")
        return lines
    end

    -- Test ipairs
    local okIpairs, ipairsErr = pcall(function()
        local count = 0
        for _ in ipairs(spells) do count = count + 1 end
        return count
    end)
    if okIpairs then
        table.insert(lines, string.format("  ipairs iteration: OK (%s entries)", tostring(ipairsErr)))
    else
        table.insert(lines, "  ipairs iteration: FAILED — " .. tostring(ipairsErr))
    end

    -- Test direct index access
    local okIdx, idxResult = pcall(function() return spells[1] end)
    if okIdx and idxResult then
        table.insert(lines, "  spells[1] access: OK")
    else
        table.insert(lines, "  spells[1] access: FAILED — " .. tostring(idxResult))
    end
    table.insert(lines, "")

    --------------------------------------------------------------------------
    -- Test R3: Per-spell field secrecy (CRITICAL: spellID)
    --------------------------------------------------------------------------
    table.insert(lines, "--- Test R3: Spell Field Secrecy ---")

    local spellCount = okLen and lenResult or 0
    local showCount = math.min(3, spellCount)

    for i = 1, showCount do
        local okSpell, spell = pcall(function() return spells[i] end)
        if not okSpell or not spell then
            table.insert(lines, string.format("  Spell %d: ACCESS FAILED — %s", i, tostring(spell)))
            break
        end

        table.insert(lines, string.format("  Spell %d:", i))

        local spellFields = {
            { name = "spellID",         value = spell.spellID },
            { name = "totalAmount",     value = spell.totalAmount },
            { name = "amountPerSecond", value = spell.amountPerSecond },
            { name = "creatureName",    value = spell.creatureName },
            { name = "overkillAmount",  value = spell.overkillAmount },
            { name = "isAvoidable",     value = spell.isAvoidable },
            { name = "isDeadly",        value = spell.isDeadly },
        }

        for _, f in ipairs(spellFields) do
            local isSecret = TestSecret(f.value)
            local safeVal = FormatSafeValue(f.value, isSecret)
            table.insert(lines, string.format("    %-18s type=%-8s issecret=%-8s value=%s",
                f.name .. ":", type(f.value), FormatSecretResult(isSecret), safeVal))
        end

        -- If spellID is NOT secret, test spell name/icon lookup
        local spellIDSecret = TestSecret(spell.spellID)
        if spellIDSecret == false then
            local okName, spellName = pcall(function()
                return C_Spell.GetSpellName(spell.spellID)
            end)
            local okTex, spellTex = pcall(function()
                return C_Spell.GetSpellTexture(spell.spellID)
            end)
            table.insert(lines, string.format("    C_Spell.GetSpellName:    %s → %s",
                okName and "OK" or "FAILED", okName and tostring(spellName) or tostring(spellTex)))
            table.insert(lines, string.format("    C_Spell.GetSpellTexture: %s → %s",
                okTex and "OK" or "FAILED", okTex and tostring(spellTex) or "error"))
        else
            table.insert(lines, "    (spellID is secret — cannot look up spell name/icon)")
        end

        table.insert(lines, "")
    end

    --------------------------------------------------------------------------
    -- Test R5: Engine sort order verification
    --------------------------------------------------------------------------
    if spellCount >= 2 then
        table.insert(lines, "--- Test R5: Engine Sort Order ---")

        -- Check if amounts are in descending order (highest first)
        local okSort, sortResult = pcall(function()
            local prev = spells[1].totalAmount
            for i = 2, math.min(5, spellCount) do
                local curr = spells[i].totalAmount
                if curr > prev then return false end
                prev = curr
            end
            return true
        end)

        if not okSort then
            table.insert(lines, "  Sort check: CANNOT VERIFY — " .. tostring(sortResult))
            table.insert(lines, "  (totalAmount is likely secret, cannot compare)")
        elseif sortResult then
            table.insert(lines, "  Sort check: CONFIRMED descending order (engine pre-sorted)")
        else
            table.insert(lines, "  Sort check: NOT in descending order")
        end
        table.insert(lines, "")
    end

    --------------------------------------------------------------------------
    -- Test: SetText/SetValue with spell data on Scoot-owned frames
    --------------------------------------------------------------------------
    table.insert(lines, "--- Display Test: SetText/SetValue with spell data ---")
    EnsureTestFrame()

    if spellCount >= 1 then
        local spell = spells[1]

        local okSV, errSV = pcall(function()
            testBar:SetMinMaxValues(0, srcResult.maxAmount)
            testBar:SetValue(spell.totalAmount)
        end)
        table.insert(lines, string.format("  SetMinMaxValues + SetValue:  %s",
            okSV and "OK" or ("FAILED — " .. tostring(errSV))))

        local okST, errST = pcall(function()
            testText:SetText(spell.totalAmount)
        end)
        table.insert(lines, string.format("  SetText(totalAmount):        %s",
            okST and "OK" or ("FAILED — " .. tostring(errST))))

        local okSTA, errSTA = pcall(function()
            testText:SetText(spell.amountPerSecond)
        end)
        table.insert(lines, string.format("  SetText(amountPerSecond):    %s",
            okSTA and "OK" or ("FAILED — " .. tostring(errSTA))))

        -- Test AbbreviateNumbers if available
        if AbbreviateNumbers then
            local okAbbr, errAbbr = pcall(function()
                local formatted = AbbreviateNumbers(spell.totalAmount)
                testText:SetText(formatted)
            end)
            table.insert(lines, string.format("  AbbreviateNumbers + SetText: %s",
                okAbbr and "OK" or ("FAILED — " .. tostring(errAbbr))))
        end
    end
    table.insert(lines, "")

    --------------------------------------------------------------------------
    -- Verdict
    --------------------------------------------------------------------------
    table.insert(lines, "--- VERDICT ---")
    table.insert(lines, "  R1: Source API callable during combat with stored GUID: YES")
    table.insert(lines, "")

    -- Summarize field secrecy
    if spellCount >= 1 then
        local spellIDSecret = TestSecret(spells[1].spellID)
        if spellIDSecret == false then
            table.insert(lines, "  spellID: NeverSecret — spell names/icons ARE available during combat")
            table.insert(lines, "    -> Degraded in-combat drill-down IS FEASIBLE")
            table.insert(lines, "    -> Display: engine-sorted spell bars with names, icons, and")
            table.insert(lines, "       secret values via SetText/SetValue")
            table.insert(lines, "    -> Limitations: no sorting, no filtering, no percentage computation")
        elseif spellIDSecret == true then
            table.insert(lines, "  spellID: SECRET — cannot look up spell names/icons during combat")
            table.insert(lines, "    -> In-combat drill-down is technically possible but severely limited")
            table.insert(lines, "    -> Bars would show secret values but no spell names or icons")
            table.insert(lines, "    -> Questionable UX value")
        else
            table.insert(lines, "  spellID: UNKNOWN — issecretvalue() not available")
        end
    end

    return lines
end

local function DebugDMYDrilldown()
    local lines = RunDrilldownTest()
    local output = table.concat(lines, "\n")

    if InCombatLockdown() then
        addon:Print("DMY drill-down test collected. Results will show after combat ends.")
    end
    addon.Events.RunOutOfCombat(function()
        addon.DebugShowWindow("DMY Drill-Down Feasibility Test", output)
    end)
end

--------------------------------------------------------------------------------
-- /scoot debug dmY multicol — Multi-column live combat feasibility test
-- Purpose: determine if the source-level API can provide live secondary column
-- data during combat using stored GUIDs, eliminating the gray-out.
--
-- Two-phase test:
--   Phase 1 (OOC): Cache all player GUIDs and verify source API for multiple
--                   meter types. Compare source-level totalAmount to session-level
--                   values to confirm they represent the same data.
--   Phase 2 (combat): For each cached GUID, query multiple meter types via the
--                      source API and test displayability.
--------------------------------------------------------------------------------

local _multicolCache = nil  -- { [guid] = { name, classFilename, sessionValues = { [meterType] = { totalAmount, amountPerSecond } } } }

local function RunMulticolTest()
    local lines = { "== DMY Multi-Column Live Combat Test ==" }
    local inCombat = InCombatLockdown()

    table.insert(lines, string.format("InCombatLockdown(): %s", tostring(inCombat)))
    table.insert(lines, string.format("Cached GUIDs: %s", _multicolCache and "yes" or "none"))
    table.insert(lines, "")

    if not (C_DamageMeter and C_DamageMeter.GetCombatSessionSourceFromType) then
        table.insert(lines, "ERROR: C_DamageMeter source API not available.")
        return lines
    end

    -- Meter types to test secondary column queries against
    local testTypes = {
        { label = "DamageDone",  enum = Enum.DamageMeterType.DamageDone,  field = "totalAmount" },
        { label = "Dps",         enum = Enum.DamageMeterType.Dps,         field = "amountPerSecond" },
        { label = "HealingDone", enum = Enum.DamageMeterType.HealingDone, field = "totalAmount" },
        { label = "Hps",         enum = Enum.DamageMeterType.Hps,         field = "amountPerSecond" },
    }

    --------------------------------------------------------------------------
    -- Phase 1: OOC — cache GUIDs, compare source vs session data
    --------------------------------------------------------------------------
    if not inCombat then
        table.insert(lines, "Phase 1: OUT OF COMBAT — caching GUIDs and comparing source vs session data")
        table.insert(lines, "")

        _multicolCache = {}

        -- Get primary session (DamageDone) for player list
        local ok, session = pcall(C_DamageMeter.GetCombatSessionFromType,
            Enum.DamageMeterSessionType.Overall, Enum.DamageMeterType.DamageDone)

        if not ok or not session or not session.combatSources or #session.combatSources == 0 then
            table.insert(lines, "ERROR: No DamageDone data. Fight something first.")
            if not ok then table.insert(lines, "  pcall error: " .. tostring(session)) end
            return lines
        end

        -- Cache GUIDs and session-level values for comparison
        table.insert(lines, "--- Caching player GUIDs from DamageDone session ---")
        local cachedCount = 0
        for _, src in ipairs(session.combatSources) do
            if src.sourceGUID then
                _multicolCache[src.sourceGUID] = {
                    name = tostring(src.name),
                    classFilename = src.classFilename,
                    sessionValues = {},
                }
                cachedCount = cachedCount + 1
            end
        end
        table.insert(lines, string.format("  Cached %d player GUIDs", cachedCount))
        table.insert(lines, "")

        -- For each meter type, query session-level AND source-level, compare
        table.insert(lines, "--- Source vs Session Value Comparison (OOC) ---")
        table.insert(lines, "  Goal: verify source.totalAmount matches session combatSources values")
        table.insert(lines, "")

        for _, mt in ipairs(testTypes) do
            table.insert(lines, string.format("  Meter type: %s (column field: %s)", mt.label, mt.field))

            -- Get session-level data
            local okS, sess = pcall(C_DamageMeter.GetCombatSessionFromType,
                Enum.DamageMeterSessionType.Overall, mt.enum)

            if not okS or not sess or not sess.combatSources then
                table.insert(lines, "    Session query: FAILED or no data")
            else
                -- Build session-level lookup by GUID
                local sessLookup = {}
                for _, src in ipairs(sess.combatSources) do
                    if src.sourceGUID then
                        sessLookup[src.sourceGUID] = {
                            totalAmount = src.totalAmount,
                            amountPerSecond = src.amountPerSecond,
                        }
                    end
                end

                -- For first 3 cached GUIDs, compare source-level vs session-level
                local compared = 0
                for guid, info in pairs(_multicolCache) do
                    if compared >= 3 then break end

                    local okSrc, srcResult = pcall(C_DamageMeter.GetCombatSessionSourceFromType,
                        Enum.DamageMeterSessionType.Overall, mt.enum, guid, nil)

                    local sessData = sessLookup[guid]

                    if okSrc and srcResult and sessData then
                        -- Compare source.totalAmount to session values
                        local srcTotal = srcResult.totalAmount
                        local sessTotal = sessData.totalAmount
                        local sessAPS = sessData.amountPerSecond

                        local matchTotal = (srcTotal == sessTotal)
                        local matchAPS = (srcTotal == sessAPS)

                        table.insert(lines, string.format("    %s:", info.name))
                        table.insert(lines, string.format("      source.totalAmount:       %s", tostring(srcTotal)))
                        table.insert(lines, string.format("      session.totalAmount:      %s", tostring(sessTotal)))
                        table.insert(lines, string.format("      session.amountPerSecond:  %s", tostring(sessAPS)))
                        table.insert(lines, string.format("      source == session.total:  %s", tostring(matchTotal)))
                        table.insert(lines, string.format("      source == session.aPS:    %s", tostring(matchAPS)))

                        -- Store for reference
                        info.sessionValues[mt.enum] = sessData
                    elseif not okSrc then
                        table.insert(lines, string.format("    %s: source query FAILED — %s", info.name, tostring(srcResult)))
                    else
                        table.insert(lines, string.format("    %s: no data (source=%s, session=%s)",
                            info.name, tostring(srcResult ~= nil), tostring(sessData ~= nil)))
                    end

                    compared = compared + 1
                end
            end
            table.insert(lines, "")
        end

        table.insert(lines, "Phase 1 COMPLETE. GUIDs cached.")
        table.insert(lines, "  1) Enter combat")
        table.insert(lines, "  2) Re-run: /scoot debug dmY multicol")

        return lines
    end

    --------------------------------------------------------------------------
    -- Phase 2: IN COMBAT — query source API per GUID per meter type
    --------------------------------------------------------------------------
    table.insert(lines, "Phase 2: IN COMBAT — testing multi-column via source API")
    table.insert(lines, "")

    -- Auto-cache using UnitGUID("player") if Phase 1 wasn't run
    if not _multicolCache then
        local playerGUID = UnitGUID("player")
        if playerGUID then
            _multicolCache = {
                [playerGUID] = {
                    name = UnitName("player") or "You",
                    classFilename = select(2, UnitClass("player")) or "UNKNOWN",
                    sessionValues = {},
                },
            }
            table.insert(lines, "No Phase 1 cache. Auto-stored player GUID only.")
            table.insert(lines, "  For full comparison, run OOC first then re-test in combat.")
            table.insert(lines, "")
        else
            table.insert(lines, "ERROR: Cannot auto-store GUID.")
            return lines
        end
    end

    local guidCount = 0
    for _ in pairs(_multicolCache) do guidCount = guidCount + 1 end
    table.insert(lines, string.format("Cached GUIDs: %d", guidCount))
    table.insert(lines, "")

    -- For each meter type, query source API for each cached GUID
    table.insert(lines, "--- Per-GUID Source Queries During Combat ---")

    EnsureTestFrame()

    for _, mt in ipairs(testTypes) do
        table.insert(lines, string.format("Meter type: %s", mt.label))

        -- Also get session-level maxAmount for bar normalization
        local okSess, sessData = pcall(C_DamageMeter.GetCombatSessionFromType,
            Enum.DamageMeterSessionType.Overall, mt.enum)
        local sessMaxAmount = okSess and sessData and sessData.maxAmount or nil
        local sessMaxSecret = sessMaxAmount and TestSecret(sessMaxAmount)
        table.insert(lines, string.format("  Session maxAmount: %s (secret=%s)",
            sessMaxAmount and type(sessMaxAmount) or "nil",
            sessMaxAmount and FormatSecretResult(sessMaxSecret) or "n/a"))

        local queriedCount = 0
        local successCount = 0

        for guid, info in pairs(_multicolCache) do
            local okSrc, srcResult = pcall(C_DamageMeter.GetCombatSessionSourceFromType,
                Enum.DamageMeterSessionType.Overall, mt.enum, guid, nil)

            queriedCount = queriedCount + 1
            if okSrc and srcResult then
                successCount = successCount + 1
                local totalSecret = TestSecret(srcResult.totalAmount)

                table.insert(lines, string.format("  %s: OK — totalAmount type=%s secret=%s",
                    info.name, type(srcResult.totalAmount), FormatSecretResult(totalSecret)))

                -- Test display pipeline
                local okDisplay, errDisplay = pcall(function()
                    if sessMaxAmount then
                        testBar:SetMinMaxValues(0, sessMaxAmount)
                    end
                    testBar:SetValue(srcResult.totalAmount)
                    local formatted = AbbreviateNumbers and AbbreviateNumbers(srcResult.totalAmount) or srcResult.totalAmount
                    testText:SetText(formatted)
                end)
                if not okDisplay then
                    table.insert(lines, string.format("    Display test: FAILED — %s", tostring(errDisplay)))
                end
            elseif not okSrc then
                table.insert(lines, string.format("  %s: FAILED — %s", info.name, tostring(srcResult)))
            else
                table.insert(lines, string.format("  %s: returned nil", info.name))
            end
        end

        table.insert(lines, string.format("  Summary: %d/%d queries succeeded", successCount, queriedCount))
        table.insert(lines, "")
    end

    --------------------------------------------------------------------------
    -- Verdict
    --------------------------------------------------------------------------
    table.insert(lines, "--- VERDICT ---")
    table.insert(lines, "  If all meter types returned data for all cached GUIDs:")
    table.insert(lines, "    -> Live multi-column during combat IS FEASIBLE")
    table.insert(lines, "    -> Each secondary column queries source API per cached GUID")
    table.insert(lines, "    -> totalAmount is secret but displayable via SetText/SetValue")
    table.insert(lines, "    -> Eliminates secondary column gray-out and rank-drift problem")
    table.insert(lines, "")
    table.insert(lines, "  Cost: N_players × N_secondary_columns API calls per refresh")
    table.insert(lines, string.format("  This test: %d GUIDs × %d meter types = %d calls",
        guidCount, #testTypes, guidCount * #testTypes))

    return lines
end

local function DebugDMYMulticol()
    local lines = RunMulticolTest()
    local output = table.concat(lines, "\n")

    if InCombatLockdown() then
        addon:Print("DMY multi-column test collected. Results will show after combat ends.")
    end
    addon.Events.RunOutOfCombat(function()
        addon.DebugShowWindow("DMY Multi-Column Live Combat Test", output)
    end)
end

--------------------------------------------------------------------------------
-- /scoot debug dmY drilldata — §24 Tests 11-13: drill-down data shape
-- Purpose: confirm combatSpellDetails contents per metric type, AoE aggregation
-- behavior, and isAvoidable/isDeadly accuracy on DamageTaken metrics.
--
-- Runs OOC only — the source API is OOC-only for tainted callers.
--------------------------------------------------------------------------------

local DRILLDATA_DETAIL_FIELDS = {
    "unitName", "unitClassFilename", "classification",
    "isPet", "isMob", "amount", "specIconID",
}

local function DumpSpellDetails(lines, details, indent)
    if not details then
        table.insert(lines, indent .. "(combatSpellDetails: nil)")
        return
    end
    for _, fname in ipairs(DRILLDATA_DETAIL_FIELDS) do
        local val = details[fname]
        local sec = TestSecret(val)
        table.insert(lines, string.format("%s%-20s type=%-8s issecret=%-8s value=%s",
            indent, fname .. ":", type(val), FormatSecretResult(sec),
            FormatSafeValue(val, sec)))
    end
end

local function CountSpellAggregation(spells)
    local seen, total, dups = {}, 0, 0
    for _, s in ipairs(spells) do
        total = total + 1
        local id = s.spellID
        if id ~= nil then
            if seen[id] then dups = dups + 1
            else seen[id] = true end
        end
    end
    local unique = 0
    for _ in pairs(seen) do unique = unique + 1 end
    return total, unique, dups
end

local function CountFlaggedTrue(spells, fieldName)
    local count, errored = 0, false
    for _, s in ipairs(spells) do
        local ok, val = pcall(function() return s[fieldName] end)
        if not ok then
            errored = true
        elseif val == true then
            count = count + 1
        end
    end
    return count, errored
end

local function RunOneMetric(lines, label, meterType, hasAvoidableInfo)
    table.insert(lines, "============================================================")
    table.insert(lines, "Metric: " .. label)
    table.insert(lines, "============================================================")

    if not meterType then
        table.insert(lines, "  ENUM not present in this build, skipping.")
        table.insert(lines, "")
        return
    end

    local ok, session = pcall(C_DamageMeter.GetCombatSessionFromType,
        Enum.DamageMeterSessionType.Overall, meterType)
    if not ok or not session or not session.combatSources or #session.combatSources == 0 then
        table.insert(lines, "  No data for this metric (no combat sources).")
        table.insert(lines, "")
        return
    end

    local src = session.combatSources[1]
    if not src.sourceGUID then
        table.insert(lines, "  First source has no sourceGUID.")
        table.insert(lines, "")
        return
    end

    table.insert(lines, string.format("  Querying source: %s (%s)  GUID=%s",
        tostring(src.name), tostring(src.classFilename), tostring(src.sourceGUID)))

    local okSrc, srcResult = pcall(C_DamageMeter.GetCombatSessionSourceFromType,
        Enum.DamageMeterSessionType.Overall, meterType,
        src.sourceGUID, src.sourceCreatureID)
    if not okSrc then
        table.insert(lines, "  Source API pcall failed: " .. tostring(srcResult))
        table.insert(lines, "")
        return
    end
    if not srcResult then
        table.insert(lines, "  Source API returned nil.")
        table.insert(lines, "")
        return
    end

    local spells = srcResult.combatSpells
    if not spells or #spells == 0 then
        table.insert(lines, "  combatSpells: empty")
        table.insert(lines, "")
        return
    end

    table.insert(lines, string.format("  Session: maxAmount=%s totalAmount=%s",
        tostring(srcResult.maxAmount), tostring(srcResult.totalAmount)))
    table.insert(lines, "")

    -- Test 12: AoE aggregation
    local total, unique, dups = CountSpellAggregation(spells)
    table.insert(lines, "  Test 12 — AoE aggregation:")
    table.insert(lines, string.format("    Total entries: %d  Unique spellIDs: %d  Duplicates: %d",
        total, unique, dups))
    if dups > 0 then
        table.insert(lines, "    -> ONE ENTRY PER TARGET (engine creates a separate entry per hit target)")
    else
        table.insert(lines, "    -> AGGREGATED (one entry per spellID; combatSpellDetails holds primary target)")
    end
    table.insert(lines, "")

    -- Test 13 (DamageTaken-family only): isAvoidable / isDeadly counts
    if hasAvoidableInfo then
        table.insert(lines, "  Test 13 — Avoidable/Deadly flags:")
        local avoidable, errA = CountFlaggedTrue(spells, "isAvoidable")
        local deadly, errD = CountFlaggedTrue(spells, "isDeadly")
        if errA then
            table.insert(lines, "    isAvoidable inspection errored (likely secret in this context)")
        else
            table.insert(lines, string.format("    isAvoidable=true: %d / %d", avoidable, total))
        end
        if errD then
            table.insert(lines, "    isDeadly inspection errored (likely secret in this context)")
        else
            table.insert(lines, string.format("    isDeadly=true:    %d / %d", deadly, total))
        end
        table.insert(lines, "")
    end

    -- Test 11: combatSpellDetails contents (first 3 spells)
    local showCount = math.min(3, #spells)
    table.insert(lines, string.format("  Test 11 — combatSpellDetails (first %d spells):", showCount))
    for i = 1, showCount do
        local spell = spells[i]
        local spellName = "?"
        if spell.spellID and C_Spell and C_Spell.GetSpellName then
            local okN, nm = pcall(C_Spell.GetSpellName, spell.spellID)
            if okN and nm and nm ~= "" then spellName = nm end
        end
        table.insert(lines, string.format("    Spell %d: id=%s name=%s totalAmount=%s amountPerSecond=%s",
            i, tostring(spell.spellID), spellName,
            tostring(spell.totalAmount), tostring(spell.amountPerSecond)))
        local creatureName = spell.creatureName
        if creatureName ~= nil and creatureName ~= "" then
            table.insert(lines, string.format("      creatureName: '%s' (pet attribution)", tostring(creatureName)))
        end
        table.insert(lines, string.format("      overkillAmount=%s isAvoidable=%s isDeadly=%s",
            tostring(spell.overkillAmount), tostring(spell.isAvoidable), tostring(spell.isDeadly)))
        DumpSpellDetails(lines, spell.combatSpellDetails, "      ")
        table.insert(lines, "")
    end
end

local function RunDrilldataTest()
    local lines = { "== DMY Drill-Down Data Shape Test (Section 24 Tests 11-13) ==" }

    if InCombatLockdown() then
        table.insert(lines, "ERROR: This test must be run OUT OF COMBAT.")
        table.insert(lines, "  The source API is OOC-only for tainted (addon) callers.")
        table.insert(lines, "  Re-run after combat ends.")
        return lines
    end

    if not (C_DamageMeter and C_DamageMeter.GetCombatSessionSourceFromType) then
        table.insert(lines, "ERROR: C_DamageMeter source API not available.")
        return lines
    end

    table.insert(lines, "Run context: OUT OF COMBAT")
    table.insert(lines, "Iterating relevant meter types and dumping per-spell shape.")
    table.insert(lines, "")

    local M = Enum.DamageMeterType or {}
    local metrics = {
        { label = "DamageDone",           type = M.DamageDone,           avoidable = false },
        { label = "HealingDone",          type = M.HealingDone,          avoidable = false },
        { label = "DamageTaken",          type = M.DamageTaken,          avoidable = true  },
        { label = "AvoidableDamageTaken", type = M.AvoidableDamageTaken, avoidable = true  },
        { label = "Interrupts",           type = M.Interrupts,           avoidable = false },
        { label = "Dispels",              type = M.Dispels,              avoidable = false },
        { label = "EnemyDamageTaken",     type = M.EnemyDamageTaken,     avoidable = false },
    }

    for _, m in ipairs(metrics) do
        RunOneMetric(lines, m.label, m.type, m.avoidable)
    end

    table.insert(lines, "============================================================")
    table.insert(lines, "DONE — review combatSpellDetails per metric.")
    table.insert(lines, "")
    table.insert(lines, "What to confirm by reading the output:")
    table.insert(lines, "  - Test 11: For each metric, what does combatSpellDetails.unitName")
    table.insert(lines, "    actually contain? (target name? attacker name? empty?)")
    table.insert(lines, "  - Test 12: AoE behavior — one entry per target, or aggregated?")
    table.insert(lines, "  - Test 13: For DamageTaken/AvoidableDamageTaken, do isAvoidable")
    table.insert(lines, "    and isDeadly counts match expectations from your last fight?")
    return lines
end

local function DebugDMYDrilldata()
    local lines = RunDrilldataTest()
    addon.DebugShowWindow("DMY Drill-Down Data Shape Test", table.concat(lines, "\n"))
end

--------------------------------------------------------------------------------
-- /scoot debug dmY abbrev — Abbreviation config + formatter battery
-- Runs OOC on plain numbers (secrecy gates access, not formatting), so it
-- fully characterizes the C-side formatters without needing combat values.
--------------------------------------------------------------------------------

local function DebugDMYAbbrev()
    local DMY = addon.DamageMetersY
    if not (DMY and DMY._BuildBreakpointTable) then
        addon:Print("DMY abbreviation module not available.")
        return
    end

    local lines = { "== DMY Abbreviation Battery ==", "" }
    local function add(s) table.insert(lines, s) end

    -- [1] Engine default breakpoints
    add("[1] C_StringUtil.GetDefaultAbbreviationBreakpoints():")
    if C_StringUtil and C_StringUtil.GetDefaultAbbreviationBreakpoints then
        local ok, bps = pcall(C_StringUtil.GetDefaultAbbreviationBreakpoints)
        if ok and type(bps) == "table" then
            for i, bp in ipairs(bps) do
                add(string.format("  [%d] breakpoint=%s abbrev=%q sigDiv=%s fracDiv=%s isGlobal=%s",
                    i, tostring(bp.breakpoint), tostring(bp.abbreviation),
                    tostring(bp.significandDivisor), tostring(bp.fractionDivisor),
                    tostring(bp.abbreviationIsGlobal)))
            end
        else
            add("  ERROR: " .. tostring(bps))
        end
    else
        add("  API not present")
    end
    add("")

    -- [2] Config creation tries (pcall keeps the exact error text)
    local bp10 = DMY._BuildBreakpointTable()
    bp10[#bp10].breakpoint = 10
    local candidates = {
        { label = "(a) fixed table (production, base bp=1)", data = DMY._BuildBreakpointTable() },
        { label = "(b) OLD broken table (no significandDivisor)", data = {
            { breakpoint = 1000000000, abbreviation = "B", fractionDivisor = 100000000 },
            { breakpoint = 1000000, abbreviation = "M", fractionDivisor = 100000 },
            { breakpoint = 1000, abbreviation = "K", fractionDivisor = 100 },
            { breakpoint = 1, abbreviation = "", fractionDivisor = 1, abbreviationIsGlobal = false },
        }},
        { label = "(c) fixed table, base bp=10", data = bp10 },
    }

    add("[2] CreateAbbreviateConfig attempts:")
    local working = {}
    if CreateAbbreviateConfig then
        for _, cand in ipairs(candidates) do
            local ok, result = pcall(CreateAbbreviateConfig, cand.data)
            if ok and result then
                table.insert(working, { label = cand.label, opts = { config = result } })
                add("  " .. cand.label .. ": OK")
            else
                add("  " .. cand.label .. ": FAILED -> " .. tostring(result))
            end
        end
    else
        add("  CreateAbbreviateConfig API not present")
    end
    add("  production config: " .. (DMY._RebuildAbbrevConfig() and "LIVE" or "NIL"))
    add("  DMY._abbrevError: " .. tostring(DMY._abbrevError))
    add("")

    -- [3] Formatting matrix
    local values = { 0.4, 5.5, 999.989898989898, 1234, 9999, 12345, 999999, 1234567, 1.23e9 }
    local rawOpts = { breakpointData = DMY._BuildBreakpointTable() }
    add("[3] Formatting matrix:")
    local function try(label, fn, ...)
        if not fn then
            add(string.format("    %-38s = (API missing)", label))
            return
        end
        local ok, r = pcall(fn, ...)
        add(string.format("    %-38s = %s", label, ok and tostring(r) or ("ERR: " .. tostring(r))))
    end
    for _, v in ipairs(values) do
        add(string.format("  v = %s", tostring(v)))
        for _, w in ipairs(working) do
            try("AbbreviateNumbers " .. w.label, AbbreviateNumbers, v, w.opts)
        end
        try("AbbreviateNumbers (defaults)", AbbreviateNumbers, v)
        try("AbbreviateNumbers (breakpointData)", AbbreviateNumbers, v, rawOpts)
        try("AbbreviateLargeNumbers", AbbreviateLargeNumbers, v)
        try("AbbrevLarge (breakpointData)", AbbreviateLargeNumbers, v, rawOpts)
        try("BreakUpLargeNumbers (natural=true)", BreakUpLargeNumbers, v, true)
        try("BreakUpLargeNumbers (natural=false)", BreakUpLargeNumbers, v, false)
        try("DMY._FormatCompact", DMY._FormatCompact, v)
    end

    addon.DebugShowWindow("DMY Abbrev Battery", lines)
end

--------------------------------------------------------------------------------
-- /scoot debug dmY colprobe — identity-correlated secondary column probe
-- Purpose: verify the session-correlation pipeline that replaced the
-- stored-GUID bypass. Dumps restriction states, per-secondary-type session
-- identity keys with secrecy flags, the live mergedData display simulation,
-- and the (drilldown-only) GUID cache state. Run OOC and again mid-combat.
--------------------------------------------------------------------------------

local function DebugDMYColprobe()
    local DMY = addon.DamageMetersY
    local lines = { "== DMY Column Probe (identity correlation) ==" }
    local function add(fmt, ...)
        table.insert(lines, select("#", ...) > 0 and string.format(fmt, ...) or fmt)
    end

    if not DMY or not DMY._initialized then
        add("DMY not initialized (component disabled?).")
        addon.DebugShowWindow("DMY Column Probe", table.concat(lines, "\n"))
        return
    end
    if not (C_DamageMeter and C_DamageMeter.GetCombatSessionFromType) then
        add("C_DamageMeter API not available.")
        addon.DebugShowWindow("DMY Column Probe", table.concat(lines, "\n"))
        return
    end

    -- [1] Combat + restriction states
    add("[1] Context:")
    add("    InCombatLockdown = %s | DMY._inCombat = %s",
        tostring(InCombatLockdown()), tostring(DMY._inCombat))
    if C_RestrictedActions and C_RestrictedActions.IsAddOnRestrictionActive
        and Enum and Enum.AddOnRestrictionType then
        for name, enumVal in pairs(Enum.AddOnRestrictionType) do
            local ok, active = pcall(C_RestrictedActions.IsAddOnRestrictionActive, enumVal)
            add("    Restriction %-14s = %s", name, ok and tostring(active) or ("ERR: " .. tostring(active)))
        end
    else
        add("    C_RestrictedActions.IsAddOnRestrictionActive not available")
    end
    add("")

    -- [2] Window column configs + per-secondary-type session identity dump
    local FORMATS = DMY.COLUMN_FORMATS
    for i = 1, DMY.MAX_WINDOWS do
        local cfg = DMY._GetWindowConfig(i)
        if cfg and cfg.enabled and cfg.columns and #cfg.columns > 1 then
            local primaryDef = FORMATS[cfg.columns[1].format]
            local primaryType = primaryDef and (primaryDef.primary or primaryDef.meterType)
            add("[2] Window %d (sessionType=%s sessionID=%s): primary=%s (mt=%s)",
                i, tostring(cfg.sessionType), tostring(cfg.sessionID),
                tostring(cfg.columns[1].format), tostring(primaryType))

            for c = 2, #cfg.columns do
                local colDef = cfg.columns[c]
                local def = colDef and FORMATS[colDef.format]
                local mt = def and (def.primary or def.meterType)
                if not def then
                    add("    col %d: %s — UNKNOWN FORMAT", c, tostring(colDef and colDef.format))
                elseif mt == primaryType then
                    add("    col %d: %s — same meter type as primary (reads the primary session record)", c, colDef.format)
                else
                    add("    col %d: %s (mt=%d) — session dump:", c, colDef.format, mt)
                    local ok, session
                    if cfg.sessionID then
                        ok, session = pcall(C_DamageMeter.GetCombatSessionFromID, cfg.sessionID, mt)
                    else
                        ok, session = pcall(C_DamageMeter.GetCombatSessionFromType, cfg.sessionType, mt)
                    end
                    if not ok then
                        add("      query FAILED: %s", tostring(session))
                    elseif not session or not session.combatSources then
                        add("      no session data (all-zero metric so far)")
                    else
                        local ikeyCounts = {}
                        for idx, src in ipairs(session.combatSources) do
                            local ikey = DMY._BuildIdentityKey(src.classFilename, src.specIconID, src.isLocalPlayer)
                            ikeyCounts[ikey] = (ikeyCounts[ikey] or 0) + 1
                            local guidSecret = TestSecret(src.sourceGUID)
                            local totalSecret = TestSecret(src.totalAmount)
                            add("      #%d ikey=%s guidSecret=%s totalSecret=%s",
                                idx, ikey, FormatSecretResult(guidSecret), FormatSecretResult(totalSecret))
                        end
                        if mt == 9 then
                            add("      deaths per-ikey counts:")
                            for ikey, n in pairs(ikeyCounts) do
                                add("        %s = %d", ikey, n)
                            end
                        else
                            for ikey, n in pairs(ikeyCounts) do
                                if n > 1 then
                                    add("      COLLISION: %s appears %dx in this session", ikey, n)
                                end
                            end
                        end
                    end
                end
            end
            add("")
        end
    end

    -- [3] Live mergedData display simulation (what each row's cells resolve to)
    for i = 1, DMY.MAX_WINDOWS do
        local win = DMY._windows and DMY._windows[i]
        local cfg = DMY._GetWindowConfig(i)
        local merged = win and win.mergedData
        if cfg and cfg.enabled and merged and cfg.columns and #cfg.columns > 1 then
            add("[3] Window %d mergedData:", i)
            add("    secondaryQueried: %s", merged.secondaryQueried and "yes" or "nil (OOC or no secondaries)")
            if merged.identityCollisions then
                local any = false
                for ikey in pairs(merged.identityCollisions) do
                    add("    collision: %s", ikey)
                    any = true
                end
                if not any then add("    collisions: none") end
            end
            local pDef = FORMATS[cfg.columns[1].format]
            local pType = pDef and (pDef.primary or pDef.meterType)
            for _, key in ipairs(merged.playerOrder or {}) do
                local player = merged.players[key]
                if player then
                    local parts = {}
                    for c = 2, #cfg.columns do
                        local def = FORMATS[cfg.columns[c].format]
                        local mt = def and (def.primary or def.meterType)
                        local outcome
                        if not mt then
                            outcome = "?"
                        elseif mt == pType then
                            outcome = "PRIMARY-RECORD"
                        elseif merged.identityCollisions and merged.identityCollisions[player.identityKey] then
                            outcome = "DASH(collision)"
                        elseif merged.secondaryQueried and merged.secondaryQueried[mt] then
                            local pres = merged.secondaryPresence and merged.secondaryPresence[player.identityKey]
                            outcome = (pres and pres[mt]) and "VALUE" or "ZERO"
                        elseif merged.secondaryQueried then
                            outcome = "DASH(query failed)"
                        else
                            outcome = "OOC-path"
                        end
                        table.insert(parts, string.format("c%d=%s", c, outcome))
                    end
                    add("    %s ikey=%s %s", tostring(key), tostring(player.identityKey), table.concat(parts, " "))
                end
            end
            add("")
        end
    end

    -- [4] Drilldown GUID cache state
    local cacheCount, collisionCount = 0, 0
    for _ in pairs(DMY._guidCache or {}) do cacheCount = cacheCount + 1 end
    for _, v in pairs(DMY._identityToGUID or {}) do
        if v == false then collisionCount = collisionCount + 1 end
    end
    add("[4] Drilldown GUID cache: %d entries, %d identity collisions", cacheCount, collisionCount)

    local output = table.concat(lines, "\n")
    addon.Events.RunOutOfCombat(function()
        addon.DebugShowWindow("DMY Column Probe", output)
    end)
end

--------------------------------------------------------------------------------
-- /scoot debug dmY names — Hide Realm Names resolver state
-- Passive: reports which resolver tier painted rows since login plus the
-- correlation caches. Not required for the feature; post-hoc diagnosis only.
--------------------------------------------------------------------------------

local function DebugDMYNames()
    local DMY = addon.DamageMetersY
    if not DMY then
        addon.DebugShowWindow("DMY Names", "DMY not available.")
        return
    end

    local lines = { "== DMY Display Name Resolver ==", "" }
    local function add(fmt, ...)
        table.insert(lines, select("#", ...) > 0 and string.format(fmt, ...) or fmt)
    end

    local db = DMY._comp and DMY._comp.db
    add("hideRealmNames setting: %s", tostring(db and db.hideRealmNames))
    add("")

    add("[1] Resolver tier counts (rows painted since login, toggle on only):")
    local c = DMY._nameTierCounts or {}
    add("  plain     (readable name, match-strip): %d", c.plain or 0)
    add("  roster    (ikey->GUID->roster map):     %d", c.roster or 0)
    add("  inspect   (ikey->GUID->inspect cache):  %d", c.inspect or 0)
    add("  ambiguate (secret name, \"short\"):       %d", c.ambiguate or 0)
    add("  raw       (untouched fallback):         %d", c.raw or 0)
    add("")

    add("[2] Roster name map (plain, realm-free):")
    local n = 0
    for guid, name in pairs(DMY._rosterNames or {}) do
        n = n + 1
        add("  %s -> %s", guid, name)
    end
    if n == 0 then add("  (empty — rebuilds OOC on roster update / full refresh)") end
    add("")

    local collisions = 0
    for _, v in pairs(DMY._identityToGUID or {}) do
        if v == false then collisions = collisions + 1 end
    end
    add("[3] identityToGUID: %d collisions marked", collisions)

    addon.DebugShowWindow("DMY Names", table.concat(lines, "\n"))
end

--------------------------------------------------------------------------------
-- /scoot debug dmY drillstate — In-combat drilldown resolution counters
-- Passive: reports which link of the combat drilldown chain succeeded or
-- failed for clicks since login. Not required for the feature; post-hoc
-- diagnosis only. (The older `drilldown` subcommand is the field-level
-- secrecy probe; this one reads production counters.)
--------------------------------------------------------------------------------

local function DebugDMYDrillState()
    local DMY = addon.DamageMetersY
    if not DMY then
        addon.DebugShowWindow("DMY Drilldown State", "DMY not available.")
        return
    end

    local lines = { "== DMY In-Combat Drilldown State ==", "" }
    local function add(fmt, ...)
        table.insert(lines, select("#", ...) > 0 and string.format(fmt, ...) or fmt)
    end

    add("InCombatLockdown(): %s", tostring(InCombatLockdown()))
    add("")

    local c = DMY._drillCounts or {}
    add("[1] GUID resolution (combat clicks since login):")
    add("  tierLocal  (own row via UnitGUID):     %d", c.tierLocal or 0)
    add("  tierCache  (ikey -> OOC GUID cache):   %d", c.tierCache or 0)
    add("  unresolved (fell back to pending):     %d", c.unresolved or 0)
    add("")
    add("[2] Live query + render:")
    add("  popOk      (live drilldown rendered):  %d", c.popOk or 0)
    add("  queryFail  (API error or nil result):  %d", c.queryFail or 0)
    add("  emptyData  (no combatSpells returned): %d", c.emptyData or 0)
    add("  popFail    (render threw, degraded):   %d", c.popFail or 0)
    add("")
    add("[death] Death log / recap links:")
    add("  dlogOk     (death log rendered):       %d", c.dlogOk or 0)
    add("  dlogEmpty  (no deaths in session):     %d", c.dlogEmpty or 0)
    add("  dlogAmbig  (ikey collision, pending):  %d", c.dlogAmbig or 0)
    add("  dlogFail   (query/build/render fail):  %d", c.dlogFail or 0)
    add("  recapOk    (recap rendered):           %d", c.recapOk or 0)
    add("  recapEmpty (no recap events):          %d", c.recapEmpty or 0)
    add("  recapFail  (recap render threw):       %d", c.recapFail or 0)
    add("  segHit/segMiss (Overall labels):       %d / %d", c.segHit or 0, c.segMiss or 0)
    add("")

    local dd = DMY._activeDrilldown
    if dd then
        add("[3] Active drilldown: meterType=%s isPending=%s hasGUID=%s view=%s scope=%s",
            tostring(dd.meterType), tostring(dd.isPending), tostring(dd.sourceGUID ~= nil),
            tostring(dd.deathsView), tostring(dd.logScope))
    else
        add("[3] Active drilldown: none")
    end

    addon.DebugShowWindow("DMY Drilldown State", table.concat(lines, "\n"))
end

--------------------------------------------------------------------------------
-- /scoot debug dmY deathprobe — Deaths session + C_DeathRecap secrecy probe
-- Captures IMMEDIATELY (run it mid-combat — that's the point: it delivers the
-- verdict on whether C_DeathRecap returns plain data during combat).
-- Display defers to combat end when run in combat (colprobe pattern).
--------------------------------------------------------------------------------

local function DebugDMYDeathProbe()
    local DMY = addon.DamageMetersY
    if not DMY then
        addon.DebugShowWindow("DMY Death Probe", "DMY not available.")
        return
    end

    local lines = { "== DMY Death Probe ==", "" }
    local function add(fmt, ...)
        table.insert(lines, select("#", ...) > 0 and string.format(fmt, ...) or fmt)
    end

    local function FieldInfo(v)
        if v == nil then return "nil" end
        if issecretvalue and issecretvalue(v) then return "SECRET(" .. type(v) .. ")" end
        return type(v) .. "=" .. tostring(v)
    end

    add("InCombatLockdown(): %s", tostring(InCombatLockdown()))
    add("")

    -- [1] Deaths sessions: Current (1) and Overall (0)
    local firstRecapID = nil
    for _, sessionType in ipairs({ 1, 0 }) do
        local label = sessionType == 1 and "Current" or "Overall"
        add("[1] Deaths session (%s):", label)
        if not (C_DamageMeter and C_DamageMeter.GetCombatSessionFromType) then
            add("  C_DamageMeter unavailable")
        else
            local ok, session = pcall(C_DamageMeter.GetCombatSessionFromType, sessionType, 9)
            if not ok then
                add("  query THREW")
            elseif not session or not session.combatSources then
                add("  no session / no combatSources")
            else
                local sources = session.combatSources
                add("  %d death events (API order = most recent first)", #sources)
                for i = 1, math.min(#sources, 10) do
                    local s = sources[i]
                    add("  [%d] recapID=%s time=%s guid=%s name=%s class=%s spec=%s local=%s",
                        i, FieldInfo(s.deathRecapID), FieldInfo(s.deathTimeSeconds),
                        FieldInfo(s.sourceGUID), FieldInfo(s.name),
                        FieldInfo(s.classFilename), FieldInfo(s.specIconID),
                        FieldInfo(s.isLocalPlayer))
                    if not firstRecapID then
                        local rid = s.deathRecapID
                        if rid ~= nil and not (issecretvalue and issecretvalue(rid))
                            and type(rid) == "number" and rid > 0 then
                            firstRecapID = rid
                        end
                    end
                end
                if #sources > 10 then add("  ... (%d more)", #sources - 10) end
            end
        end
        add("")
    end

    -- [2] C_DeathRecap probe on the first plain recapID found
    add("[2] C_DeathRecap probe:")
    if not (C_DeathRecap and C_DeathRecap.GetRecapEvents) then
        add("  C_DeathRecap unavailable")
    elseif not firstRecapID then
        add("  no plain recapID > 0 found in [1] — nothing to probe")
    else
        add("  probing recapID=%d", firstRecapID)
        if C_DeathRecap.HasRecapEvents then
            local ok, has = pcall(C_DeathRecap.HasRecapEvents, firstRecapID)
            add("  HasRecapEvents: %s", ok and FieldInfo(has) or "THREW")
        end
        local okEv, events = pcall(C_DeathRecap.GetRecapEvents, firstRecapID)
        if not okEv then
            add("  GetRecapEvents: THREW")
        elseif type(events) ~= "table" then
            add("  GetRecapEvents: %s", FieldInfo(events))
        else
            local okCount, n = pcall(function() return #events end)
            add("  GetRecapEvents: table, count=%s", okCount and tostring(n) or "SECRET-TABLE")
            if okCount and n and n > 0 then
                local ev = events[1]
                add("  event[1] (killing blow) field secrecy:")
                for _, f in ipairs({ "event", "spellId", "spellName", "school", "amount",
                    "overkill", "absorbed", "resisted", "blocked", "timestamp",
                    "currentHP", "sourceName", "hideCaster", "environmentalType" }) do
                    local okF, v = pcall(function() return ev[f] end)
                    add("    %-17s %s", f, okF and FieldInfo(v) or "INDEX THREW")
                end
            end
        end
        if C_DeathRecap.GetRecapMaxHealth then
            local okHP, hp = pcall(C_DeathRecap.GetRecapMaxHealth, firstRecapID)
            add("  GetRecapMaxHealth: %s", okHP and FieldInfo(hp) or "THREW")
        end
    end
    add("")

    -- [3] Recap → segment index state
    local idxCount = 0
    local samples = {}
    for rid, v in pairs(DMY._recapSegmentIndex or {}) do
        idxCount = idxCount + 1
        if #samples < 5 then
            if type(v) == "table" then
                table.insert(samples, string.format("    %d -> seg=%s time=%s",
                    rid, tostring(v.seg), tostring(v.time)))
            else
                table.insert(samples, string.format("    %d -> %s", rid, tostring(v)))
            end
        end
    end
    add("[3] recapSegmentIndex: %d entries, dirty=%s",
        idxCount, tostring(DMY._recapSegmentIndexDirty))
    for _, s in ipairs(samples) do add(s) end
    add("")

    -- [4] Death counters
    local c = DMY._drillCounts or {}
    add("[4] Counters: dlogOk=%d dlogEmpty=%d dlogAmbig=%d dlogFail=%d",
        c.dlogOk or 0, c.dlogEmpty or 0, c.dlogAmbig or 0, c.dlogFail or 0)
    add("    recapOk=%d recapEmpty=%d recapFail=%d segHit=%d segMiss=%d",
        c.recapOk or 0, c.recapEmpty or 0, c.recapFail or 0, c.segHit or 0, c.segMiss or 0)

    local output = table.concat(lines, "\n")
    addon.Events.RunOutOfCombat(function()
        addon.DebugShowWindow("DMY Death Probe", output)
    end)
end

--------------------------------------------------------------------------------
-- /scoot debug dmY headericons — Icons header mode gallery (visual tuning aid)
--
-- Renders every DMY.HEADER_ICONS entry at the three common header font sizes
-- (desaturated + tinted with the resolved Header Row color, exactly as the
-- live headers render them) plus an untouched reference copy. Tuning loop:
-- edit the spec table in columns.lua, /reload, reopen the gallery.
--------------------------------------------------------------------------------

local headerIconGallery

local function DebugDMYHeaderIcons()
    local DMY = addon.DamageMetersY
    if not (DMY and DMY.HEADER_ICONS and DMY._ConfigureHeaderIcon) then
        addon:Print("DMY header icons not available.")
        return
    end

    -- Rebuild fresh each open so edited specs show after /reload and repeated
    -- opens never stack stale textures
    if headerIconGallery then
        headerIconGallery:Hide()
        headerIconGallery:SetParent(nil)
        headerIconGallery = nil
    end

    local KIND_ORDER = {
        "damage", "healing", "absorbs", "interrupts", "dispels",
        "deaths", "dmgTaken", "avoidable", "enemyDmg",
    }
    local SIZES = { 10, 12, 14 } -- header font sizes to simulate

    -- Candidate replacements rendered below the live set for side-by-side
    -- comparison; adopt one by copying its spec into DMY.HEADER_ICONS
    local SPELL_ICON_ZOOM = { 0.08, 0.92, 0.08, 0.92 }
    local ALT_SPECS = {
        { label = "deaths: ping skull",  spec = { atlas = "Ping_Marker_Icon_Threat", desaturate = true, scale = 1.0 } },
        -- classic texture files ARE numbered by raid-target index (8 = skull),
        -- unlike the reverse-ordered GM-raidMarkerN atlases
        { label = "deaths: classic mark", spec = { texture = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8", desaturate = true, scale = 1.0 } },
        { label = "avoid: warning tri",  spec = { atlas = "transmog-icon-warning-small", desaturate = true, scale = 1.0 } },
        { label = "avoid: profession !", spec = { atlas = "Professions_Icon_Warning", desaturate = true, scale = 1.0 } },
        { label = "avoid: fire",         spec = { texture = "Interface\\Icons\\Spell_Fire_Fire", texCoord = SPELL_ICON_ZOOM, desaturate = true, scale = 1.0 } },
    }

    local headerH = DMY.HEADER_HEIGHT or 24
    local rowH = 34
    local labelW = 110
    local cellW = 34
    local width = 16 + labelW + (#SIZES + 1) * cellW + 16
    local height = 46 + #KIND_ORDER * rowH + 26 + #ALT_SPECS * rowH + 12

    local f = CreateFrame("Frame", "ScootDMYHeaderIconGallery", UIParent)
    headerIconGallery = f
    f:SetSize(width, height)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)

    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.06, 0.06, 0.08, 0.97)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 12, -10)
    title:SetText("DMY Header Icons — sizes " .. table.concat(SIZES, "/") .. "pt + raw")

    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", 2, 2)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    local hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", 12, -28)
    hint:SetText("Tune scale/yOffset/texCoord in damagemetersY/columns.lua, then /reload")

    local function renderRow(labelText, spec, y)
        local label = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("TOPLEFT", 12, y - 10)
        label:SetWidth(labelW)
        label:SetJustifyH("LEFT")
        label:SetWordWrap(false)
        label:SetText(labelText)

        if not spec then
            local missing = f:CreateFontString(nil, "OVERLAY", "GameFontRedSmall")
            missing:SetPoint("TOPLEFT", 12 + labelW, y - 10)
            missing:SetText("no HEADER_ICONS entry")
            return
        end

        for s, fontSize in ipairs(SIZES) do
            -- Simulated header cell: same dark ground as a meter header
            local cell = CreateFrame("Frame", nil, f)
            cell:SetSize(cellW - 4, headerH)
            cell:SetPoint("TOPLEFT", 12 + labelW + (s - 1) * cellW, y - (rowH - headerH) / 2)
            local cellBg = cell:CreateTexture(nil, "BACKGROUND")
            cellBg:SetAllPoints()
            cellBg:SetColorTexture(0.08, 0.08, 0.10, 0.9)

            local icon = cell:CreateTexture(nil, "OVERLAY")
            -- Mirror _ConfigureHeaderIcon's sizing, with the gallery's
            -- own font size substituted for the Header Row setting
            local base = math.min(fontSize + 4, headerH - 2)
            icon:SetSize(DMY._HeaderIconDims(spec, base))
            if spec.atlas then
                icon:SetAtlas(spec.atlas)
            elseif spec.texture then
                icon:SetTexture(spec.texture)
            end
            if spec.texCoord then
                icon:SetTexCoord(spec.texCoord[1], spec.texCoord[2], spec.texCoord[3], spec.texCoord[4])
            end
            icon:SetDesaturated(spec.desaturate ~= false)
            local r, g, b, a = 0.8, 0.8, 0.8, 1
            if DMY._ResolveHeaderColor and DMY._comp then
                r, g, b, a = DMY._ResolveHeaderColor(DMY._comp)
            end
            icon:SetVertexColor(r, g, b, a)
            icon:SetPoint("CENTER", cell, "CENTER", 0, tonumber(spec.yOffset) or 0)
        end

        -- Raw reference: no desaturation, no tint, fitted to an 18px box
        local raw = f:CreateTexture(nil, "OVERLAY")
        raw:SetSize(DMY._HeaderIconDims(spec, 18))
        raw:SetPoint("TOPLEFT", 12 + labelW + #SIZES * cellW + 6, y - (rowH - 18) / 2)
        if spec.atlas then
            raw:SetAtlas(spec.atlas)
        elseif spec.texture then
            raw:SetTexture(spec.texture)
        end
        if spec.texCoord then
            raw:SetTexCoord(spec.texCoord[1], spec.texCoord[2], spec.texCoord[3], spec.texCoord[4])
        end
    end

    for i, kind in ipairs(KIND_ORDER) do
        renderRow(kind, DMY.HEADER_ICONS[kind], -46 - (i - 1) * rowH)
    end

    local altTop = -46 - #KIND_ORDER * rowH
    local altHeader = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    altHeader:SetPoint("TOPLEFT", 12, altTop - 8)
    altHeader:SetText("Alternates — adopt by copying the spec into HEADER_ICONS")
    for i, alt in ipairs(ALT_SPECS) do
        renderRow(alt.label, alt.spec, altTop - 26 - (i - 1) * rowH)
    end

    f:Show()
end

addon:RegisterDebugCommand({
    name = "dmY", help = "Modern damage meter probes",
    verbs = {
        { word = "cvar", help = "CVar data collection", fn = DebugDMYCVar },
        { word = "api", help = "source API probe", fn = DebugDMYAPI },
        { word = "trace", help = "the trace log", fn = addon.DebugDMYTrace },
        { word = "fields", help = "field secrecy per source", fn = DebugDMYFields },
        { word = "drilldown", help = "spell breakdown probe", fn = DebugDMYDrilldown },
        { word = "drilldata", help = "drilldown data snapshot", fn = DebugDMYDrilldata },
        { word = "multicol", help = "multi-column data", fn = DebugDMYMulticol },
        { word = "abbrev", help = "number abbreviation", fn = DebugDMYAbbrev },
        { word = "colprobe", help = "column probe", fn = DebugDMYColprobe },
        { word = "names", help = "name resolution", fn = DebugDMYNames },
        { word = "drillstate", help = "drilldown state", fn = DebugDMYDrillState },
        { word = "deathprobe", help = "death recap probe", fn = DebugDMYDeathProbe },
        { word = "headericons", help = "header icon state", fn = DebugDMYHeaderIcons },
    },
})
