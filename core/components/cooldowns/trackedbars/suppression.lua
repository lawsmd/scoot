local addonName, addon = ...

local TB = addon.TB

--------------------------------------------------------------------------------
-- Suppression State Machine
--
-- Authority model: removal signals (OnUnitAuraRemovedEvent, ClearAuraInfo,
-- RefreshData lost-instance) suppress an item. Restore only happens through
-- validated add events or combat fallback timers.
--------------------------------------------------------------------------------

local function clearSuppressionState(item)
    TB.suppressedByRemoval[item] = nil
    TB.suppressedCooldownID[item] = nil
    TB.pendingAuraAdd[item] = nil
    TB.suppressedAt[item] = nil
end
TB.clearSuppressionState = clearSuppressionState

local function isItemSuppressed(item)
    if not TB.suppressedByRemoval[item] then
        return false
    end
    local scopedCooldownID = TB.suppressedCooldownID[item]
    local currentCooldownID = TB.getItemCooldownID(item)
    if scopedCooldownID and currentCooldownID and scopedCooldownID ~= currentCooldownID then
        if TB.tbTraceEnabled then
            TB.tbTrace("Suppression: cleared on cooldown change old=%s new=%s id=%s",
                tostring(scopedCooldownID), tostring(currentCooldownID), tostring(item):sub(-6))
        end
        clearSuppressionState(item)
        TB.auraRecentlyCleared[item] = nil
        TB.auraRemovedSpellID[item] = nil
        return false
    end
    return true
end
TB.isItemSuppressed = isItemSuppressed

local function enforceSuppressedVisibility(item)
    pcall(item.SetAlpha, item, 0)
    local ov = TB.trackedBarOverlays[item]
    if ov then ov:Hide() end
    if TB.verticalModeActive then
        local comp = addon.Components and addon.Components.trackedBars
        if comp and TB.scheduleVerticalRebuild then
            TB.scheduleVerticalRebuild(comp)
        end
    end
end
TB.enforceSuppressedVisibility = enforceSuppressedVisibility

local function suppressItem(item, reason)
    local now = GetTime()
    if not isItemSuppressed(item) then
        TB.suppressedByRemoval[item] = true
        TB.suppressedCooldownID[item] = TB.getItemCooldownID(item)
    end
    TB.suppressedAt[item] = now
    TB.auraRecentlyCleared[item] = now
    TB.pendingAuraAdd[item] = nil
    enforceSuppressedVisibility(item)
    if TB.tbTraceEnabled then
        TB.tbTrace("Suppression: set reason=%s cooldown=%s id=%s",
            tostring(reason or "?"), tostring(TB.suppressedCooldownID[item]), tostring(item):sub(-6))
    end
end
TB.suppressItem = suppressItem

local function restoreSuppressedItem(item, reason)
    if not isItemSuppressed(item) then
        TB.pendingAuraAdd[item] = nil
        return
    end
    clearSuppressionState(item)
    TB.auraRecentlyCleared[item] = nil
    TB.auraRemovedSpellID[item] = nil
    if TB.verticalModeActive then
        local comp = addon.Components and addon.Components.trackedBars
        if comp and TB.scheduleVerticalRebuild then
            TB.scheduleVerticalRebuild(comp)
        end
        if TB.tbTraceEnabled then
            TB.tbTrace("Suppression: restored (vertical) reason=%s id=%s",
                tostring(reason or "?"), tostring(item):sub(-6))
        end
        return
    end

    local ok, isInactive = pcall(function() return item.isActive == false end)
    if ok and not issecretvalue(isInactive) and isInactive then
        if TB.tbTraceEnabled then
            TB.tbTrace("Suppression: cleared but item inactive reason=%s id=%s",
                tostring(reason or "?"), tostring(item):sub(-6))
        end
        return
    end

    pcall(item.SetAlpha, item, 1)
    local ov = TB.trackedBarOverlays[item]
    if ov and (not item.IsShown or item:IsShown()) then
        ov:Show()
    end
    if TB.tbTraceEnabled then
        TB.tbTrace("Suppression: restored reason=%s id=%s", tostring(reason or "?"), tostring(item):sub(-6))
    end
end
TB.restoreSuppressedItem = restoreSuppressedItem

--------------------------------------------------------------------------------
-- Aura Helpers
--------------------------------------------------------------------------------

local function addSpellToSet(spellSet, sid)
    if type(sid) == "number" and not issecretvalue(sid) then
        spellSet[sid] = true
    end
end

function TB.hasLiveAuraInstance(item)
    local auraInstance = item and item.auraInstanceID
    if type(auraInstance) ~= "number" or issecretvalue(auraInstance) then
        return false, nil
    end

    local getter = C_UnitAuras and C_UnitAuras.GetAuraDataByAuraInstanceID
    if type(getter) ~= "function" then
        return true, nil
    end

    local ok, auraData = pcall(getter, "player", auraInstance)
    if ok and auraData and not issecretvalue(auraData) then
        return true, auraData
    end

    return false, nil
end

local reusableRelevantSpells = {}

function TB.getRelevantAddedAuraInfo(item, unitAuraUpdateInfo)
    if not unitAuraUpdateInfo or type(unitAuraUpdateInfo) ~= "table" then
        return false, nil
    end
    local added = unitAuraUpdateInfo.addedAuras
    if type(added) ~= "table" then
        return false, nil
    end

    local relevantSpells = reusableRelevantSpells
    wipe(relevantSpells)
    addSpellToSet(relevantSpells, TB.auraRemovedSpellID[item])
    addSpellToSet(relevantSpells, TB.cachedSpellID[item])
    addSpellToSet(relevantSpells, TB.barItemFirstSpellID[item])
    addSpellToSet(relevantSpells, item.auraSpellID)
    if item.GetSpellID then
        local okSID, sid = pcall(item.GetSpellID, item)
        if okSID then
            addSpellToSet(relevantSpells, sid)
        end
    end
    if item.GetCooldownInfo then
        local okInfo, info = pcall(item.GetCooldownInfo, item)
        if okInfo and type(info) == "table" then
            addSpellToSet(relevantSpells, info.spellID)
            addSpellToSet(relevantSpells, info.overrideSpellID)
            addSpellToSet(relevantSpells, info.linkedSpellID)
            if type(info.linkedSpellIDs) == "table" then
                for _, linkedSID in ipairs(info.linkedSpellIDs) do
                    addSpellToSet(relevantSpells, linkedSID)
                end
            end
        end
    end

    for _, aura in ipairs(added) do
        local sid = aura and aura.spellId
        if type(sid) == "number" and not issecretvalue(sid) then
            if relevantSpells[sid] then
                return true, sid
            end
            if item.NeedsAddedAuraUpdate then
                local okNeeds, needs = pcall(item.NeedsAddedAuraUpdate, item, sid)
                if okNeeds and needs then
                    return true, sid
                end
            end
        end
    end
    return false, nil
end

--------------------------------------------------------------------------------
-- Background Verification (diagnostics-only when tracing is enabled)
--------------------------------------------------------------------------------

function TB.scheduleBackgroundVerification(self)
    if not TB.tbTraceEnabled then return end
    local gen = (TB.cascadeTimers[self] or 0) + 1
    TB.cascadeTimers[self] = gen

    local intervals = { 0, 0.1, 0.2, 0.4, 0.6, 0.8, 1.0 }

    local function checkAt(idx)
        if TB.cascadeTimers[self] ~= gen then
            if TB.tbTraceEnabled then
                TB.tbTrace("BackgroundVerify: stale gen at idx=%d id=%s", idx, tostring(self):sub(-6))
            end
            return
        end

        local clearTime = TB.auraRecentlyCleared[self]
        local clearAge = clearTime and (GetTime() - clearTime) or -1
        local suppressed = isItemSuppressed(self)
        local hasPendingAdd = TB.pendingAuraAdd[self] ~= nil
        local shown = self:IsShown()

        local spellID = nil
        local okSpell, sid = pcall(function() return self:GetSpellID() end)
        if okSpell and type(sid) == "number" and not issecretvalue(sid) then
            spellID = sid
        elseif type(TB.cachedSpellID[self]) == "number" then
            spellID = TB.cachedSpellID[self]
        end
        local auraData = nil
        if spellID then
            local okAura, ad = pcall(C_UnitAuras.GetPlayerAuraBySpellID, spellID)
            if okAura and not issecretvalue(ad) then
                auraData = ad
            end
        end

        if TB.tbTraceEnabled then
            local auraState = auraData and "present" or "nil"
            local auraInst = auraData and tostring(auraData.auraInstanceID) or "nil"
            local pendingText = hasPendingAdd and "yes" or "no"
            TB.tbTrace("BackgroundVerify(v15): idx=%d suppressed=%s pendingAdd=%s shown=%s clearAge=%.3f spell=%s aura=%s inst=%s id=%s",
                idx, tostring(suppressed), pendingText, tostring(shown), clearAge,
                tostring(spellID), auraState, auraInst, tostring(self):sub(-6))
        end

        if idx < #intervals then
            local delay = intervals[idx + 1] - intervals[idx]
            C_Timer.After(delay, function() checkAt(idx + 1) end)
        else
            TB.cascadeTimers[self] = nil
            if TB.tbTraceEnabled then
                TB.tbTrace("BackgroundVerify(v15): complete id=%s", tostring(self):sub(-6))
            end
        end
    end

    C_Timer.After(0, function() checkAt(1) end)
end
