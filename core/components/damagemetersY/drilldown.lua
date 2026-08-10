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
-- Deaths drilldown — two-level view inside the same popup.
--
-- Level 1 "log": chronological death list. Segment/Current windows show every
-- death in the segment (name + time-of-death); Overall windows show the
-- clicked player's deaths, labeled via the recapID → segment index (Overall
-- sessions carry no timestamps). Level 2 "recap": the selected death's
-- C_DeathRecap event breakdown rendered in-popup, with a back button.
--------------------------------------------------------------------------------

local MAX_DEATH_ROWS = 20 -- visible log rows; mousewheel slides the window
local MAX_RECAP_ROWS = 20 -- newest N recap events
local EM_DASH = "\226\128\148"
local MELEE_ICON_FILE_ID = 135274
local DEATH_LOG_COMPACT_WIDTH = 230 -- segment-scope log: time + icon + name only

-- Segment-scope logs have no right column, so the popup narrows; every other
-- deaths view (player-scope log with segment labels, recap) keeps the default.
-- menu:Clear() restores POPUP_WIDTH, so only the compact case needs setting.
local function DeathViewWidth(dd)
    if dd.deathsView == "log" and dd.logScope ~= "player" then
        return DEATH_LOG_COMPACT_WIDTH
    end
    return nil -- factory default (POPUP_WIDTH)
end

local function GetClassColorTable(classFilename)
    local cc = classFilename and addon.ClassColors and addon.ClassColors[classFilename]
    if cc then return { cc.r or 1, cc.g or 1, cc.b or 1 } end
    return nil
end

local function QueryDeathSession(sessionType, sessionID)
    if not C_DamageMeter then return nil end
    local ok, session
    if sessionID and C_DamageMeter.GetCombatSessionFromID then
        ok, session = pcall(C_DamageMeter.GetCombatSessionFromID, sessionID, DEATHS_METER_TYPE)
    elseif C_DamageMeter.GetCombatSessionFromType then
        ok, session = pcall(C_DamageMeter.GetCombatSessionFromType, sessionType, DEATHS_METER_TYPE)
    end
    if ok then return session end
    return nil
end

-- Builds plain row descriptors: rightLabel is a precomputed plain string, and
-- name is the only conditionally-secret field (only ever SetText'd). Returns
-- rows, or nil + "empty" | "ambiguous" | "noguid".
local function BuildDeathLogRows(deathSession, dd, merged)
    if not deathSession or not deathSession.combatSources then return nil, "empty" end
    local counts = DMY._drillCounts

    -- Overall ("player") scope: filter to the clicked player. OOC by plain
    -- GUID; in combat by NeverSecret identity key, gated by the live session's
    -- collision map (same discipline as _ResolveCombatSourceGUID tier 2).
    local filterGUID, filterIkey
    if dd.logScope == "player" then
        if not DMY._inCombat then
            filterGUID = dd.sourceGUID
            if not filterGUID then return nil, "noguid" end
        else
            filterIkey = dd.identityKey
            if not filterIkey then return nil, "ambiguous" end
            if merged and merged.identityCollisions and merged.identityCollisions[filterIkey] then
                return nil, "ambiguous"
            end
        end
    end

    local rows = {}
    local sources = deathSession.combatSources
    -- The engine lists the most recent death first; reverse for chronology.
    for i = #sources, 1, -1 do
        local source = sources[i]
        local keep = true
        if filterGUID then
            keep = DMY._PlainValue(source.sourceGUID) == filterGUID
        elseif filterIkey then
            keep = DMY._BuildIdentityKey(source.classFilename, source.specIconID, source.isLocalPlayer)
                == filterIkey
        end
        if keep then
            local rid = DMY._PlainNumber(source.deathRecapID) or 0
            local timeLabel, rightLabel
            if dd.logScope == "player" then
                -- Overall has no timestamps; the segment index supplies the
                -- segment name (right column) and the death's position on the
                -- Overall clock (prior segment durations + within-segment time).
                local mapped = rid > 0 and DMY._recapSegmentIndex[rid] or nil
                if mapped then
                    counts.segHit = counts.segHit + 1
                    timeLabel = mapped.time or EM_DASH
                    rightLabel = mapped.seg or EM_DASH
                else
                    counts.segMiss = counts.segMiss + 1
                    timeLabel = EM_DASH
                    rightLabel = EM_DASH
                end
            else
                -- deathTimeSeconds: plain OOC, secret in combat, -1 when the
                -- engine has no timestamp. Em dash upgrades at regen refresh.
                -- No right column in segment scope — the name takes the row.
                local t = DMY._PlainNumber(source.deathTimeSeconds)
                timeLabel = (t and t >= 0) and DMY._FormatDeathTime(t) or EM_DASH
            end
            rows[#rows + 1] = {
                recapID = rid,
                name = source.name,
                classFilename = source.classFilename,
                specIconID = source.specIconID,
                timeLabel = timeLabel,
                rightLabel = rightLabel,
                clickable = rid > 0,
            }
        end
    end
    if #rows == 0 then return nil, "empty" end
    return rows
end

local function AddDeathHeader(menu, dd)
    local title, color, onBack
    if dd.deathsView == "recap" then
        title = (dd.recapOwnerName or "Unknown") .. "  —  Death Recap"
        color = GetClassColorTable(dd.recapOwnerClass)
        onBack = function()
            dd.deathsView = "log"
            dd.recapID = nil
            dd.isPending = false
            DMY._PopulateDeathLogPopup(menu)
        end
    elseif dd.logScope == "player" then
        title = (dd.sourceName or "Unknown") .. "  —  Deaths"
        color = GetClassColorTable(dd.classFilename)
    else
        title = (dd.sessionLabel or "Session") .. "  —  Death Log"
    end
    menu:AddHeaderBar(title, color, function() DMY._CloseDrilldown() end, onBack)
end

local function ShowDeathPlaceholder(menu, dd, text)
    menu:Clear()
    menu:SetMenuWidth(DeathViewWidth(dd))
    AddDeathHeader(menu, dd)
    menu:AddDivider()
    menu:AddPlaceholderText(text)
    menu:ShowAtAnchor(dd.anchor)
end

-- Level 1 renderer. Touches only plain descriptor fields (+ SetText of
-- maybe-secret names), so it needs no combat variant.
function DMY._PopulateDeathLogPopup(menu)
    local dd = DMY._activeDrilldown
    if not dd then return end
    local rows = dd.logRows or {}
    menu:Clear()
    menu:SetMenuWidth(DeathViewWidth(dd))
    AddDeathHeader(menu, dd)
    menu:AddDivider()

    local total = #rows
    if total == 0 then
        menu:AddPlaceholderText("No deaths recorded.")
        menu:ShowAtAnchor(dd.anchor)
        return
    end

    local maxOffset = math.max(0, total - MAX_DEATH_ROWS)
    local offset = dd.logOffset or 0
    if offset > maxOffset then offset = maxOffset end
    if offset < 0 then offset = 0 end
    dd.logOffset = offset

    local first = 1 + offset
    local last = math.min(total, offset + MAX_DEATH_ROWS)

    -- One column width for the whole list (not just the visible window, so
    -- scrolling never re-flows): Overall-clock times can pass the hour and
    -- "H:MM:SS" overflows the default 32px slot. Labels are always plain.
    local timeW = 32
    for _, row in ipairs(rows) do
        if #(row.timeLabel or "") > 5 then
            timeW = 48
            break
        end
    end

    for i = first, last do
        local row = rows[i]
        local onClick
        if row.clickable then
            onClick = function()
                dd.deathsView = "recap"
                dd.recapID = row.recapID
                dd.recapOwnerName = row.name
                dd.recapOwnerClass = row.classFilename
                DMY._ShowDeathRecap(menu)
            end
        end
        menu:AddDeathRow({
            name = row.name,
            classFilename = row.classFilename,
            specIconID = row.specIconID,
            timeLabel = row.timeLabel,
            timeWidth = timeW,
            rightLabel = row.rightLabel,
            onClick = onClick,
        })
    end
    if total > last - first + 1 then
        menu:AddPlaceholderText(string.format("+%d more %s scroll", total - (last - first + 1), EM_DASH))
    end
    menu:ShowAtAnchor(dd.anchor)
end

-- Level 2 renderer. Returns true when event rows rendered, false when the
-- recap has no retrievable events (recapEmpty counted here). May throw on an
-- unexpected secret operation — _ShowDeathRecap pcalls it and degrades.
function DMY._PopulateDeathRecapPopup(menu)
    local dd = DMY._activeDrilldown
    if not dd then return false end
    local counts = DMY._drillCounts

    local rid = DMY._PlainNumber(dd.recapID)
    if not rid or rid <= 0 or not (C_DeathRecap and C_DeathRecap.GetRecapEvents) then
        counts.recapEmpty = counts.recapEmpty + 1
        return false
    end

    if C_DeathRecap.HasRecapEvents then
        local okHas, has = pcall(C_DeathRecap.HasRecapEvents, rid)
        if okHas and DMY._PlainValue(has) == false then
            counts.recapEmpty = counts.recapEmpty + 1
            return false
        end
    end

    local okEv, events = pcall(C_DeathRecap.GetRecapEvents, rid)
    if not okEv or type(events) ~= "table" or #events == 0 then
        counts.recapEmpty = counts.recapEmpty + 1
        return false
    end

    local maxHP, maxHPRaw
    if C_DeathRecap.GetRecapMaxHealth then
        local okHP, hp = pcall(C_DeathRecap.GetRecapMaxHealth, rid)
        if okHP then
            maxHPRaw = hp
            maxHP = DMY._PlainNumber(hp)
            if maxHP and maxHP <= 0 then maxHP = nil end
        end
    end

    -- events[1] is the killing blow (the API lists newest first)
    local deathTimestamp = DMY._PlainNumber(events[1] and events[1].timestamp)

    menu:Clear()
    AddDeathHeader(menu, dd)
    menu:AddDivider()

    local total = #events
    local shown = math.min(total, MAX_RECAP_ROWS)
    if total > shown then
        menu:AddPlaceholderText(string.format("(%d earlier events omitted)", total - shown))
    end

    for i = shown, 1, -1 do -- oldest shown first; killing blow lands last
        local ev = events[i]
        local isKillingBlow = (i == 1)

        local evType = DMY._PlainValue(ev.event)
        local isHeal = (evType == "SPELL_HEAL" or evType == "SPELL_PERIODIC_HEAL")

        local spellName = DMY._PlainValue(ev.spellName)
        if not spellName or spellName == "" then
            if isHeal then
                spellName = "Heal"
            elseif evType == "SWING_DAMAGE" then
                spellName = "Melee"
            elseif evType == "ENVIRONMENTAL_DAMAGE" then
                local env = DMY._PlainValue(ev.environmentalType)
                spellName = (env and env ~= "" and env) or "Environment"
            else
                spellName = "Unknown"
            end
        end

        local label = spellName
        local srcName = DMY._PlainValue(ev.sourceName)
        if srcName and srcName ~= "" and not DMY._PlainValue(ev.hideCaster) then
            label = label .. " (" .. srcName .. ")"
        end
        if isKillingBlow and not isHeal then
            label = label .. "  (Killing Blow)"
        else
            local ts = DMY._PlainNumber(ev.timestamp)
            if deathTimestamp and ts then
                local before = deathTimestamp - ts
                if before > 0.049 then
                    label = string.format("%.1fs  %s", before, label)
                end
            end
        end

        local amount = ev.amount
        local amountPlain = DMY._PlainNumber(amount)
        local valueText, valueColor
        if amountPlain then
            local fmt = DMY._FormatCompact(amountPlain)
            if isHeal then
                valueText, valueColor = "+" .. fmt, { 0.4, 1, 0.4 }
            else
                valueText, valueColor = "-" .. fmt, { 1, 0.35, 0.35 }
            end
        elseif amount ~= nil then
            valueText = DMY._UnifiedAbbreviate(amount) -- secret-capable
        else
            valueText = ""
        end

        local rowSpec = {
            nameText = label,
            nameColor = isKillingBlow and { 1, 0.82, 0 } or { 1, 1, 1 },
            valueText = valueText,
            valueColor = valueColor,
            barColor = isHeal and { 0.10, 0.50, 0.10 } or { 0.60, 0.08, 0.08 },
        }

        -- Icon: plain positive spellId → normal lookup; plain zero/nil →
        -- melee fallback; secret → lookup anyway (AllowedWhenTainted,
        -- pcall-contained in AddSpellRow with question-mark fallback).
        local spellId = ev.spellId
        local spellIdPlain = DMY._PlainNumber(spellId)
        if spellIdPlain then
            if spellIdPlain > 0 then
                rowSpec.spellID = spellIdPlain
            else
                rowSpec.iconFileID = MELEE_ICON_FILE_ID
            end
        elseif spellId ~= nil then
            rowSpec.spellID = spellId
        else
            rowSpec.iconFileID = MELEE_ICON_FILE_ID
        end

        -- Bar fill = HP remaining after this event
        local hpPlain = DMY._PlainNumber(ev.currentHP)
        if hpPlain and maxHP then
            rowSpec.fillFraction = hpPlain / maxHP
        elseif ev.currentHP ~= nil and maxHPRaw ~= nil then
            rowSpec.rawFill = true
            rowSpec.fillValueRaw = ev.currentHP
            rowSpec.fillMaxRaw = maxHPRaw
        else
            rowSpec.fillFraction = 0
        end

        menu:AddSpellRow(rowSpec)
    end

    menu:ShowAtAnchor(dd.anchor)
    return true
end

-- Pcall wrapper around the recap populate with graceful degradation.
function DMY._ShowDeathRecap(menu)
    local dd = DMY._activeDrilldown
    if not dd then return end
    local counts = DMY._drillCounts
    local ok, rendered = pcall(DMY._PopulateDeathRecapPopup, menu)
    if ok and rendered then
        counts.recapOk = counts.recapOk + 1
        dd.isPending = false
        return
    end
    if not ok then
        counts.recapFail = counts.recapFail + 1
    end
    if DMY._inCombat and not ok then
        -- Unexpected secret op — retry at full fidelity when combat ends
        dd.isPending = true
        ShowDeathPlaceholder(menu, dd, "Recap will load once combat ends\226\128\166")
    else
        ShowDeathPlaceholder(menu, dd, "Death recap unavailable.")
    end
end

-- Query → build → populate the death log (shared by click-open, the regen
-- refresh, and the live throttle refresh). Failure dispositions feed the
-- dlog* counters in /scoot debug dmY drillstate.
function DMY._OpenDeathLog(menu)
    local dd = DMY._activeDrilldown
    if not dd then return end
    local counts = DMY._drillCounts

    if not DMY._inCombat and DMY._recapSegmentIndexDirty then
        DMY._RebuildRecapSegmentIndex()
    end

    local win = DMY._windows and DMY._windows[dd.windowIndex]
    local session = QueryDeathSession(dd.sessionType, dd.sessionID)

    local rows, why
    if session then
        local okBuild, r, w = pcall(BuildDeathLogRows, session, dd, win and win.mergedData)
        if okBuild then rows, why = r, w else why = "threw" end
    else
        why = "queryfail"
    end

    if rows then
        dd.logRows = rows
        dd.isPending = false
        local okPop = pcall(DMY._PopulateDeathLogPopup, menu)
        if okPop then
            counts.dlogOk = counts.dlogOk + 1
            return
        end
        counts.dlogFail = counts.dlogFail + 1
    elseif why == "ambiguous" then
        counts.dlogAmbig = counts.dlogAmbig + 1
        dd.isPending = true
        ShowDeathPlaceholder(menu, dd, "Cannot isolate this player's deaths in combat\226\128\166")
        return
    elseif why == "empty" then
        counts.dlogEmpty = counts.dlogEmpty + 1
    else
        counts.dlogFail = counts.dlogFail + 1
    end

    if DMY._inCombat then
        dd.isPending = true
        ShowDeathPlaceholder(menu, dd, "Will load once combat ends\226\128\166")
    elseif why == "empty" then
        ShowDeathPlaceholder(menu, dd, "No deaths recorded.")
    else
        ShowDeathPlaceholder(menu, dd, "Death data unavailable.")
    end
end

-- Mousewheel: slide the log window (assigned as the popup's _onWheel).
function DMY._OnDeathLogWheel(delta)
    local dd = DMY._activeDrilldown
    if not dd or dd.meterType ~= DEATHS_METER_TYPE or dd.deathsView ~= "log" then return end
    if not drilldownMenu or not drilldownMenu:IsShown() then return end
    local rows = dd.logRows
    if not rows or #rows <= MAX_DEATH_ROWS then return end
    dd.logOffset = (dd.logOffset or 0) - delta * 3
    DMY._PopulateDeathLogPopup(drilldownMenu)
end

-- Live refresh while a death log is open, riding the DAMAGE_METER_* throttle
-- (events.lua). On a failed rebuild the last rendered content stays — a stale
-- log beats a placeholder mid-fight. The recap view never live-refreshes
-- (a recap is immutable once the death happened).
function DMY._RefreshOpenDeathLog()
    local dd = DMY._activeDrilldown
    if not dd or dd.meterType ~= DEATHS_METER_TYPE or dd.deathsView ~= "log" then return end
    if not drilldownMenu or not drilldownMenu:IsShown() then return end

    local win = DMY._windows and DMY._windows[dd.windowIndex]
    local session = QueryDeathSession(dd.sessionType, dd.sessionID)
    if not session then return end
    local okBuild, rows = pcall(BuildDeathLogRows, session, dd, win and win.mergedData)
    if not okBuild or not rows then return end
    dd.logRows = rows
    dd.isPending = false
    pcall(DMY._PopulateDeathLogPopup, drilldownMenu)
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
    drilldownMenu._onWheel = function(delta) DMY._OnDeathLogWheel(delta) end
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

    -- Deaths: two-level death log / recap drilldown (in and out of combat)
    if meterType == DEATHS_METER_TYPE then
        local dd = DMY._activeDrilldown
        dd.deathsView = "log"
        dd.logScope = (cfg.sessionType == 0 and not cfg.sessionID) and "player" or "segment"
        dd.logOffset = 0
        dd.sessionLabel = DMY._GetSessionLabel(cfg.sessionType, cfg.sessionID, cfg._sessionName)
        DMY._OpenDeathLog(menu)
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

    -- Deaths: refresh the open view at full fidelity
    if dd.meterType == DEATHS_METER_TYPE then
        if DMY._recapSegmentIndexDirty then
            DMY._RebuildRecapSegmentIndex()
        end
        if dd.deathsView == "recap" then
            DMY._ShowDeathRecap(drilldownMenu)
        elseif dd.logScope == "player" and not dd.sourceGUID then
            -- Overall scope clicked in combat; identity never resolved
            DMY._CloseDrilldown()
        else
            DMY._OpenDeathLog(drilldownMenu)
        end
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
