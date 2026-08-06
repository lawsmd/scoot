-- damagemetersY/drilldown.lua - Source row click → spell breakdown popup
local _, addon = ...
local DMY = addon.DamageMetersY

--------------------------------------------------------------------------------
-- Active drill-down state — single global, only one popup visible at a time.
--------------------------------------------------------------------------------

DMY._activeDrilldown = nil

local drilldownMenu = nil -- lazy singleton

local POPUP_WIDTH = 280

-- Meter types where combatSpellDetails is populated with attacker info.
-- Empirical findings 2026-05-20: only DamageTaken (7) and AvoidableDamageTaken (8).
local DAMAGE_TAKEN_FAMILY = { [7] = true, [8] = true }

-- HealingDone (2) and Hps (3) return per-target rows with empty unitName.
-- Renderer must aggregate by spellID to avoid duplicate-looking rows.
local HEAL_FAMILY_AGGREGATE = { [2] = true, [3] = true }

local DEATHS_METER_TYPE = 9

-- Classification colors for mob attackers (unitClassFilename is always "WARRIOR" for mobs).
local CLASSIFICATION_COLORS = {
    normal    = { 1, 1, 1 },
    elite     = { 1, 0.82, 0 },
    rare      = { 0.74, 0.74, 0.85 },
    rareelite = { 1, 0.84, 0.4 },
    worldboss = { 1, 0.4, 0 },
}

--------------------------------------------------------------------------------
-- Aggregation helper: collapse duplicate spellIDs (sum totalAmount, max APS).
-- Used for HealingDone family where engine returns one row per target.
--------------------------------------------------------------------------------

function DMY._AggregateSpellsBySpellID(combatSpells)
    if not combatSpells then return {} end
    local byID, order = {}, {}
    for _, spell in ipairs(combatSpells) do
        local id = spell.spellID
        local existing = byID[id]
        if existing then
            existing.totalAmount = (existing.totalAmount or 0) + (spell.totalAmount or 0)
            if (spell.amountPerSecond or 0) > (existing.amountPerSecond or 0) then
                existing.amountPerSecond = spell.amountPerSecond
            end
        else
            byID[id] = {
                spellID = id,
                totalAmount = spell.totalAmount,
                amountPerSecond = spell.amountPerSecond,
                creatureName = spell.creatureName,
                overkillAmount = spell.overkillAmount,
                isAvoidable = spell.isAvoidable,
                isDeadly = spell.isDeadly,
                combatSpellDetails = spell.combatSpellDetails,
            }
            order[#order + 1] = id
        end
    end
    local out = {}
    for _, id in ipairs(order) do
        out[#out + 1] = byID[id]
    end
    table.sort(out, function(a, b)
        return (a.totalAmount or 0) > (b.totalAmount or 0)
    end)
    return out
end

--------------------------------------------------------------------------------
-- Spell row name formatter.
-- Returns: (nameText, details) — details only non-nil for DamageTaken family.
--------------------------------------------------------------------------------

function DMY._FormatSpellRowName(spell, meterType)
    local spellName
    if C_Spell and C_Spell.GetSpellName then
        spellName = C_Spell.GetSpellName(spell.spellID)
    end
    spellName = spellName or ("Spell " .. tostring(spell.spellID or "?"))

    if DAMAGE_TAKEN_FAMILY[meterType] then
        local details = spell.combatSpellDetails
        if details and details.unitName and details.unitName ~= "" then
            return string.format("%s (%s)", spellName, details.unitName), details
        end
        return spellName, details
    end

    -- All other metrics: spell name + optional pet attribution
    if spell.creatureName and spell.creatureName ~= "" then
        return string.format("%s (%s)", spellName, spell.creatureName), nil
    end
    return spellName, nil
end

--------------------------------------------------------------------------------
-- Attacker color (DamageTaken family only).
--------------------------------------------------------------------------------

function DMY._GetAttackerColor(details)
    if not details then return 1, 1, 1 end

    -- Real classification wins regardless of isMob (e.g. boss adds are isMob=false elite)
    if details.classification and details.classification ~= "" and CLASSIFICATION_COLORS[details.classification] then
        -- Mobs always have unitClassFilename="WARRIOR" junk — never trust it
        if details.isMob then
            local c = CLASSIFICATION_COLORS[details.classification]
            return c[1], c[2], c[3]
        end
    end

    -- Real player (rare in DamageTaken but possible for PvP/duels)
    if not details.isMob and details.unitClassFilename and details.unitClassFilename ~= "" then
        local cc = addon.ClassColors and addon.ClassColors[details.unitClassFilename]
        if cc then return cc.r or 1, cc.g or 1, cc.b or 1 end
    end

    -- Classification fallback (covers isMob with non-mapped classification)
    if details.classification and details.classification ~= "" then
        local c = CLASSIFICATION_COLORS[details.classification] or CLASSIFICATION_COLORS.normal
        return c[1], c[2], c[3]
    end

    return 1, 1, 1
end

--------------------------------------------------------------------------------
-- Query helper — wraps the source API in pcall. Legal in combat too: the API
-- rejects only SECRET arguments from tainted context, and dd.sourceGUID is
-- plain by construction (row key OOC, _ResolveCombatSourceGUID in combat).
--------------------------------------------------------------------------------

function DMY._QuerySpellBreakdown()
    local dd = DMY._activeDrilldown
    if not dd or not dd.sourceGUID then return nil end

    if not C_DamageMeter then return nil end
    local ok, result
    if dd.sessionID then
        if C_DamageMeter.GetCombatSessionSourceFromID then
            ok, result = pcall(C_DamageMeter.GetCombatSessionSourceFromID,
                dd.sessionID, dd.meterType, dd.sourceGUID, dd.sourceCreatureID)
        end
    else
        if C_DamageMeter.GetCombatSessionSourceFromType then
            ok, result = pcall(C_DamageMeter.GetCombatSessionSourceFromType,
                dd.sessionType, dd.meterType, dd.sourceGUID, dd.sourceCreatureID)
        end
    end

    if ok and result then
        dd.spellData = result
        dd.spellDataFromCombat = DMY._inCombat and true or false
        dd.isPending = false
        return result
    end
    -- Combat-queried data has secret fields — never hand it to the OOC
    -- populate path as a stale fallback (regen refresh auto-closes on nil).
    if dd.spellDataFromCombat then return nil end
    return dd.spellData
end

--------------------------------------------------------------------------------
-- Deaths metric → look up deathRecapID by GUID and open Blizzard's Death Recap.
--------------------------------------------------------------------------------

local function GetDeathRecapForGUID(sessionType, sessionID, sourceGUID)
    if not C_DamageMeter then return 0 end
    local ok, deathSession
    if sessionID and C_DamageMeter.GetCombatSessionFromID then
        ok, deathSession = pcall(C_DamageMeter.GetCombatSessionFromID, sessionID, DEATHS_METER_TYPE)
    elseif C_DamageMeter.GetCombatSessionFromType then
        ok, deathSession = pcall(C_DamageMeter.GetCombatSessionFromType, sessionType, DEATHS_METER_TYPE)
    end
    if not ok or not deathSession or not deathSession.combatSources then return 0 end
    for _, source in ipairs(deathSession.combatSources) do
        if source.sourceGUID == sourceGUID and source.deathRecapID and source.deathRecapID ~= 0 then
            return source.deathRecapID
        end
    end
    return 0
end

--------------------------------------------------------------------------------
-- Populate the popup with header + spell rows (or placeholder).
--------------------------------------------------------------------------------

local function GetMetricLabel(meterType)
    -- Use the COLUMN_FORMATS header text for the matching format key
    -- Map meterType → user-facing label
    local LABELS = {
        [0]  = "Damage",
        [1]  = "DPS",
        [2]  = "Healing",
        [3]  = "HPS",
        [4]  = "Absorbs",
        [5]  = "Interrupts",
        [6]  = "Dispels",
        [7]  = "Damage Taken",
        [8]  = "Avoidable Damage",
        [9]  = "Deaths",
        [10] = "Enemy Damage",
    }
    return LABELS[meterType] or "?"
end

function DMY._PopulateDrilldownPopup(menu, spellData)
    local dd = DMY._activeDrilldown
    if not dd then return end
    menu:Clear()

    -- Header: PlayerName — Metric (with close X)
    local title = (dd.sourceName or "Unknown") .. "  —  " .. GetMetricLabel(dd.meterType)
    local classColor = nil
    if dd.classFilename then
        local cc = addon.ClassColors and addon.ClassColors[dd.classFilename]
        if cc then classColor = { cc.r or 1, cc.g or 1, cc.b or 1 } end
    end
    menu:AddHeaderBar(title, classColor, function() DMY._CloseDrilldown() end)
    menu:AddDivider()

    if not spellData or not spellData.combatSpells or #spellData.combatSpells == 0 then
        menu:AddPlaceholderText("No spell data for this player.")
        menu:ShowAtAnchor(dd.anchor)
        return
    end

    -- Aggregate by spellID for HealingDone family
    local spells = spellData.combatSpells
    if HEAL_FAMILY_AGGREGATE[dd.meterType] then
        spells = DMY._AggregateSpellsBySpellID(spells)
    end

    -- Player's class color for bar fills
    local barR, barG, barB = 0.6, 0.6, 0.6
    if dd.classFilename then
        local cc = addon.ClassColors and addon.ClassColors[dd.classFilename]
        if cc then barR, barG, barB = cc.r or 0.6, cc.g or 0.6, cc.b or 0.6 end
    end

    local maxAmount = spellData.maxAmount or 1
    if maxAmount <= 0 then maxAmount = 1 end
    local totalAmount = spellData.totalAmount or 0

    for _, spell in ipairs(spells) do
        local nameText, attackerDetails = DMY._FormatSpellRowName(spell, dd.meterType)

        local primaryValue
        if dd.showsPerSecondAsPrimary then
            primaryValue = spell.amountPerSecond or 0
        else
            primaryValue = spell.totalAmount or 0
        end

        local percent = 0
        if totalAmount > 0 then
            percent = (spell.totalAmount or 0) / totalAmount * 100
        end

        local valueText = DMY._FormatCompact(primaryValue) .. string.format(" (%.0f%%)", percent)

        local fillFrac = 0
        if maxAmount > 0 then
            fillFrac = (spell.totalAmount or 0) / maxAmount
            if fillFrac < 0 then fillFrac = 0 end
            if fillFrac > 1 then fillFrac = 1 end
        end

        local nameR, nameG, nameB = 1, 1, 1
        if DAMAGE_TAKEN_FAMILY[dd.meterType] and attackerDetails then
            nameR, nameG, nameB = DMY._GetAttackerColor(attackerDetails)
        end

        menu:AddSpellRow({
            spellID = spell.spellID,
            nameText = nameText,
            nameColor = { nameR, nameG, nameB },
            valueText = valueText,
            fillFraction = fillFrac,
            barColor = { barR, barG, barB },
        })
    end

    menu:ShowAtAnchor(dd.anchor)
end

--------------------------------------------------------------------------------
-- Combat-safe populate. Every field on the returned structure is secret in
-- combat (SecretWhenInCombat; DamageMeterCombatSpell has no NeverSecret
-- fields), so this renders only what the secret-capable primitives allow:
-- engine-sorted rows, C_Spell name/icon lookups (AllowedWhenTainted),
-- UnifiedAbbreviate values, raw StatusBar fills. Dropped until the regen
-- upgrade: percent shares (no secret division), heal-family aggregation
-- (secret table keys), pet/attacker suffixes (emptiness tests throw), and
-- isMob-based coloring (classification-only instead). Caller pcalls this;
-- returns true only when spell rows were rendered.
--------------------------------------------------------------------------------

function DMY._PopulateDrilldownPopupCombat(menu, spellData)
    local dd = DMY._activeDrilldown
    if not dd then return false end

    local spells = spellData and spellData.combatSpells
    if not spells or #spells == 0 then
        DMY._drillCounts.emptyData = DMY._drillCounts.emptyData + 1
        return false
    end

    menu:Clear()

    -- Concat is secret-whitelisted; truthiness only on dd.sourceName.
    local title = (dd.sourceName or "Unknown") .. "  —  " .. GetMetricLabel(dd.meterType)
    local classColor = nil
    if dd.classFilename then
        local cc = addon.ClassColors and addon.ClassColors[dd.classFilename]
        if cc then classColor = { cc.r or 1, cc.g or 1, cc.b or 1 } end
    end
    menu:AddHeaderBar(title, classColor, function() DMY._CloseDrilldown() end)
    menu:AddDivider()

    local barR, barG, barB = 0.6, 0.6, 0.6
    if dd.classFilename then
        local cc = addon.ClassColors and addon.ClassColors[dd.classFilename]
        if cc then barR, barG, barB = cc.r or 0.6, cc.g or 0.6, cc.b or 0.6 end
    end

    -- Secret max for raw fills; engine sorts descending, so the first row's
    -- total substitutes when the source-level maxAmount is absent.
    local fillMax = spellData.maxAmount or (spells[1] and spells[1].totalAmount)

    for _, spell in ipairs(spells) do
        local spellName
        if C_Spell and C_Spell.GetSpellName then
            local ok, n = pcall(C_Spell.GetSpellName, spell.spellID)
            if ok and n then spellName = n end
        end
        if not spellName then spellName = "Unknown Spell" end

        -- Attacker color: classification is NeverSecret; isMob is secret, so
        -- unitClassFilename can't be trusted (mob "WARRIOR" junk) — skip it.
        local nameR, nameG, nameB = 1, 1, 1
        if DAMAGE_TAKEN_FAMILY[dd.meterType] then
            local details = spell.combatSpellDetails
            local classification = details and details.classification
            if type(classification) == "string"
                and not (issecretvalue and issecretvalue(classification)) then
                local c = CLASSIFICATION_COLORS[classification]
                if c then nameR, nameG, nameB = c[1], c[2], c[3] end
            end
        end

        local primaryValue
        if dd.showsPerSecondAsPrimary then
            primaryValue = spell.amountPerSecond or spell.totalAmount
        else
            primaryValue = spell.totalAmount
        end

        menu:AddSpellRow({
            spellID = spell.spellID,
            nameText = spellName,
            nameColor = { nameR, nameG, nameB },
            valueText = DMY._UnifiedAbbreviate(primaryValue or 0),
            rawFill = true,
            fillValueRaw = spell.totalAmount,
            fillMaxRaw = fillMax,
            barColor = { barR, barG, barB },
        })
    end

    menu:ShowAtAnchor(dd.anchor)
    return true
end

--------------------------------------------------------------------------------
-- Show the in-combat pending placeholder.
--------------------------------------------------------------------------------

function DMY._ShowPendingState(menu)
    local dd = DMY._activeDrilldown
    if not dd then return end
    menu:Clear()
    local title = (dd.sourceName or "Loading…") .. "  —  " .. GetMetricLabel(dd.meterType or 1)
    local classColor = nil
    if dd.classFilename then
        local cc = addon.ClassColors and addon.ClassColors[dd.classFilename]
        if cc then classColor = { cc.r or 1, cc.g or 1, cc.b or 1 } end
    end
    menu:AddHeaderBar(title, classColor, function() DMY._CloseDrilldown() end)
    menu:AddDivider()
    menu:AddPlaceholderText("Will load once combat ends…")
    menu:ShowAtAnchor(dd.anchor)
end

--------------------------------------------------------------------------------
-- Build / get the singleton drill-down menu.
--------------------------------------------------------------------------------

local function GetOrCreateMenu()
    if drilldownMenu then return drilldownMenu end
    drilldownMenu = DMY._CreateFlyoutMenu(POPUP_WIDTH)
    drilldownMenu:HookScript("OnHide", function()
        -- Clear active state when popup is dismissed by any path.
        DMY._activeDrilldown = nil
    end)
    return drilldownMenu
end

--------------------------------------------------------------------------------
-- Open drill-down for a clicked row.
--------------------------------------------------------------------------------

function DMY._OpenDrilldown(row, columnIndex)
    if not row then return end
    columnIndex = columnIndex or 1
    local windowIndex = row._windowIndex
    if not windowIndex then return end

    local cfg = DMY._GetWindowConfig(windowIndex)
    if not cfg then return end

    local colFormat = cfg.columns and cfg.columns[columnIndex] and cfg.columns[columnIndex].format
    local colDef = colFormat and DMY.COLUMN_FORMATS[colFormat]
    if not colDef then return end

    local meterType = colDef.primary or colDef.meterType

    -- EnemyDamageTaken (10): source has no GUID — skip drill-down
    if meterType == 10 then return end

    local sourceGUID = row._sourceGUID -- nil in combat
    local identityKey = row._identityKey

    -- Deaths metric (OOC only): open Blizzard's Death Recap, bypass popup if recap exists
    if meterType == DEATHS_METER_TYPE and not DMY._inCombat and sourceGUID then
        local recapID = GetDeathRecapForGUID(cfg.sessionType, cfg.sessionID, sourceGUID)
        if recapID and recapID > 0 and OpenDeathRecapUI then
            OpenDeathRecapUI(recapID)
            return
        end
        -- Fall through to popup with placeholder
    end

    -- Build active state
    DMY._activeDrilldown = {
        windowIndex = windowIndex,
        columnIndex = columnIndex,
        sourceGUID = sourceGUID,
        sourceCreatureID = row._sourceCreatureID,
        sourceName = row._sourceName,
        classFilename = row._classFilename,
        identityKey = identityKey,
        isLocalPlayer = row._isLocalPlayer,
        meterType = meterType,
        showsPerSecondAsPrimary = (colDef.valueField == "amountPerSecond") or (colDef.primaryField == "amountPerSecond"),
        sessionType = cfg.sessionType,
        sessionID = cfg.sessionID,
        spellData = nil,
        isPending = false,
        anchor = row,
    }

    local menu = GetOrCreateMenu()

    -- Deaths fallback: no recap available
    if meterType == DEATHS_METER_TYPE then
        menu:Clear()
        local title = (DMY._activeDrilldown.sourceName or "Unknown") .. "  —  Deaths"
        local classColor = nil
        if DMY._activeDrilldown.classFilename then
            local cc = addon.ClassColors and addon.ClassColors[DMY._activeDrilldown.classFilename]
            if cc then classColor = { cc.r or 1, cc.g or 1, cc.b or 1 } end
        end
        menu:AddHeaderBar(title, classColor, function() DMY._CloseDrilldown() end)
        menu:AddDivider()
        menu:AddPlaceholderText("No death recap available.")
        menu:ShowAtAnchor(row)
        return
    end

    -- In-combat: attempt a live drilldown with a plain GUID. Any failed link
    -- (unresolvable identity, query rejection, empty data, render throw)
    -- degrades to the pending placeholder — today's exact behavior.
    if DMY._inCombat then
        local win = DMY._windows and DMY._windows[windowIndex]
        local guid = DMY._ResolveCombatSourceGUID(row, win and win.mergedData)
        if guid then
            DMY._activeDrilldown.sourceGUID = guid
            local spellData = DMY._QuerySpellBreakdown()
            if spellData then
                local ok, rendered = pcall(DMY._PopulateDrilldownPopupCombat, menu, spellData)
                if ok and rendered then
                    DMY._drillCounts.popOk = DMY._drillCounts.popOk + 1
                    return
                end
                if not ok then
                    DMY._drillCounts.popFail = DMY._drillCounts.popFail + 1
                end
            else
                DMY._drillCounts.queryFail = DMY._drillCounts.queryFail + 1
            end
        end
        DMY._activeDrilldown.isPending = true
        DMY._ShowPendingState(menu)
        return
    end

    -- OOC: query and populate
    if not sourceGUID then
        -- Should not happen OOC, but guard anyway
        menu:Clear()
        menu:AddHeaderBar("Unknown source", nil, function() DMY._CloseDrilldown() end)
        menu:AddDivider()
        menu:AddPlaceholderText("Source identity unavailable.")
        menu:ShowAtAnchor(row)
        return
    end

    local spellData = DMY._QuerySpellBreakdown()
    DMY._PopulateDrilldownPopup(menu, spellData)
end

--------------------------------------------------------------------------------
-- Close — clears state and hides menu.
--------------------------------------------------------------------------------

function DMY._CloseDrilldown()
    DMY._activeDrilldown = nil
    if drilldownMenu and drilldownMenu:IsShown() then
        drilldownMenu:Hide()
    end
end

--------------------------------------------------------------------------------
-- PLAYER_REGEN_ENABLED hook: re-resolve GUID via identityKey, query, repopulate.
-- Called from events.lua after _FullRefreshAllWindows.
--------------------------------------------------------------------------------

function DMY._OnCombatEnd_RefreshDrilldown()
    local dd = DMY._activeDrilldown
    if not dd or not drilldownMenu or not drilldownMenu:IsShown() then return end

    -- Resolve GUID from identityKey if we don't have one (clicked during combat)
    if not dd.sourceGUID and dd.identityKey then
        local guid = DMY._identityToGUID and DMY._identityToGUID[dd.identityKey]
        if guid and guid ~= false then
            dd.sourceGUID = guid
            local cached = DMY._guidCache and DMY._guidCache[guid]
            if cached and cached.classFilename then
                dd.classFilename = cached.classFilename
            end
        end
    end

    -- Re-resolve sourceName and anchor from the current row pool
    -- (rows have been repopulated by _FullRefreshAllWindows by now)
    if dd.sourceGUID then
        local win = DMY._windows and DMY._windows[dd.windowIndex]
        if win then
            local found = false
            if win.barRows then
                for r = 1, DMY.MAX_POOL do
                    local row = win.barRows[r]
                    if row and row:IsShown() and row._sourceGUID == dd.sourceGUID then
                        if row._sourceName and row._sourceName ~= "" then
                            dd.sourceName = row._sourceName
                        end
                        dd.anchor = row
                        found = true
                        break
                    end
                end
            end
            if not found and win.pinnedRow and win.pinnedRow:IsShown() and win.pinnedRow._sourceGUID == dd.sourceGUID then
                if win.pinnedRow._sourceName and win.pinnedRow._sourceName ~= "" then
                    dd.sourceName = win.pinnedRow._sourceName
                end
                dd.anchor = win.pinnedRow
            end
        end
    end

    -- Deaths metric: try recap now that we have a GUID
    if dd.meterType == DEATHS_METER_TYPE and dd.sourceGUID then
        local recapID = GetDeathRecapForGUID(dd.sessionType, dd.sessionID, dd.sourceGUID)
        if recapID and recapID > 0 and OpenDeathRecapUI then
            DMY._CloseDrilldown()
            OpenDeathRecapUI(recapID)
            return
        end
        -- Otherwise: show "No death recap available"
        drilldownMenu:Clear()
        local title = (dd.sourceName or "Unknown") .. "  —  Deaths"
        local classColor = nil
        if dd.classFilename then
            local cc = addon.ClassColors and addon.ClassColors[dd.classFilename]
            if cc then classColor = { cc.r or 1, cc.g or 1, cc.b or 1 } end
        end
        drilldownMenu:AddHeaderBar(title, classColor, function() DMY._CloseDrilldown() end)
        drilldownMenu:AddDivider()
        drilldownMenu:AddPlaceholderText("No death recap available.")
        drilldownMenu:ShowAtAnchor(dd.anchor)
        return
    end

    if not dd.sourceGUID then
        -- Player no longer visible / identity unresolvable — auto-close
        DMY._CloseDrilldown()
        return
    end

    local spellData = DMY._QuerySpellBreakdown()
    if not spellData then
        DMY._CloseDrilldown()
        return
    end
    DMY._PopulateDrilldownPopup(drilldownMenu, spellData)
end
