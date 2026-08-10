-- classauras/scanning.lua - Aura detection, DurationObject tracking, display start/stop, OnUpdate
local addonName, addon = ...

local CA = addon.ClassAuras

-- Local aliases (resolved at load time — core.lua, layout.lua, styling.lua load first)
local GetDB = CA._GetDB
local auraTracking = CA._auraTracking
local guidCache = CA._guidCache
local CacheAuraIdentity = CA._CacheAuraIdentity
local playerClassToken = CA._playerClassToken

-- Deferred retry gate: prevents duplicate timers per aura
local pendingRetries = {}  -- [auraId] = true

local IsAuraFilteredOutByInstanceID = C_UnitAuras.IsAuraFilteredOutByInstanceID

local broadFilterCache = {}  -- [filter] = filter with "|PLAYER" stripped

--------------------------------------------------------------------------------
-- Aura Scanning
--------------------------------------------------------------------------------

-- Broad-filter aura scanning: post-scan ownership + name matching.
-- Strips |PLAYER from the filter, scans all matching auras, then verifies ownership afterward.
-- Key design points:
--   1. Filter broadened (strip |PLAYER) -- ownership checked post-scan
--   2. Name-based matching fallback via inline canonName resolution
--   3. Post-scan ownership via sourceUnit then IsAuraFilteredOutByInstanceID
--   4. Zero pcall: issecretvalue guards replace pcall closures (OPT-19)
local function FindAuraOnUnit(unit, filter, spellId, linkedSpellIds, canonName)
    local broadFilter = broadFilterCache[filter]
    if not broadFilter then
        broadFilter = filter and filter:gsub("|PLAYER", "") or filter
        broadFilterCache[filter] = broadFilter
    end

    for i = 1, 40 do
        local auraData = C_UnitAuras.GetAuraDataByIndex(unit, i, broadFilter)
        if not auraData then break end

        local matched = false
        local matchedSpell = nil

        -- Primary: spellId match (issecretvalue guard replaces pcall)
        local auraSpell = auraData.spellId
        if not issecretvalue(auraSpell) then
            if auraSpell == spellId then
                matched = true
                matchedSpell = spellId
            elseif linkedSpellIds then
                for _, linkedId in ipairs(linkedSpellIds) do
                    if auraSpell == linkedId then
                        matched = true
                        matchedSpell = linkedId
                        break
                    end
                end
            end
        end

        -- Fallback: name match
        if not matched and canonName then
            local auraName = auraData.name
            if auraName and not issecretvalue(auraName) then
                if auraName:lower() == canonName then
                    matched = true
                    matchedSpell = spellId
                end
            end
        end

        if matched then
            local isMine = nil

            local src = auraData.sourceUnit
            if not issecretvalue(src) then
                isMine = (src == "player" or src == "pet")
            end

            if isMine == nil then
                local iid = auraData.auraInstanceID
                if iid and not issecretvalue(iid) then
                    isMine = not IsAuraFilteredOutByInstanceID(unit, iid, filter)
                end
            end

            if isMine ~= false then
                return auraData, matchedSpell
            end
        end
    end
    return nil, nil
end

--------------------------------------------------------------------------------
-- Duration Display (DurationObject-based -- unified combat/non-combat)
--------------------------------------------------------------------------------
-- Uses C_UnitAuras.GetAuraDuration() to get a live C++ DurationObject each frame.
-- StatusBar:SetValue/SetMinMaxValues and Cooldown:SetCooldown are AllowedWhenTainted,
-- so bar fill and countdown text work correctly even with secret values.

local function StyleCooldownText(elem, auraId)
    if not elem._cdFrame then return end
    local fs = elem._cdFrame:GetCountdownFontString()
    if not fs then return end
    local auraDef = CA._registry[auraId]
    local state = CA._activeAuras[auraId]
    if not state then return end
    local db = GetDB(auraDef)
    if not db then return end
    local fontKey = db.textFont or "FRIZQT__"
    local fontFace = addon.ResolveFontFace(fontKey)
    local fontSize = db.textSize or 24
    local fontFlags = db.textStyle or "OUTLINE"
    pcall(fs.SetFont, fs, fontFace, fontSize, fontFlags)
    local override = CA._GetActiveOverride(CA._registry[auraId])
    local c = (override and override.textColor) or db.textColor or { 1, 1, 1, 1 }
    pcall(fs.SetTextColor, fs, c[1], c[2], c[3], c[4])
end

local function StopAuraDisplay(auraId)
    auraTracking[auraId] = nil
    local state = CA._activeAuras[auraId]
    if not state then return end
    state._lastActiveSpellId = nil
    state.container:SetScript("OnUpdate", nil)
    for _, elem in ipairs(state.elements) do
        if elem.type == "text" and elem.def.source == "duration" then
            pcall(elem.widget.SetText, elem.widget, "")
            pcall(elem.widget.Show, elem.widget)
        end
        if elem.type == "bar" and elem.def.source == "duration" then
            pcall(elem.barFill.SetValue, elem.barFill, 0)
        end
    end
    -- Hide CooldownFrame fallback text if present
    for _, elem in ipairs(state.elements) do
        if elem._cdFrame then elem._cdFrame:Hide() end
    end
    if not CA._isEditModeActive() then
        state.container:Hide()
    end
end

local function StartAuraDisplay(auraId)
    local state = CA._activeAuras[auraId]
    if not state then return end
    local auraDef = CA._registry[auraId]
    if not auraDef then return end
    local t = auraTracking[auraId]
    if not t then return end

    -- Reset text throttle so first frame always updates text
    state._lastTextUpdate = 0

    -- Get initial DurationObject for CooldownFrame setup
    local ok, durObj = pcall(C_UnitAuras.GetAuraDuration, t.unit, t.auraInstanceID)
    if not ok or not durObj then
        StopAuraDisplay(auraId)
        return
    end
    -- Set up CooldownFrame for each duration text element (fallback for secret text)
    for _, elem in ipairs(state.elements) do
        if elem.type == "text" and elem.def.source == "duration" then
            if not elem._cdFrame then
                local cdFrame = CreateFrame("Cooldown", nil, state.container, "CooldownFrameTemplate")
                cdFrame:SetAllPoints(elem.widget)
                -- Same level as the elevated text frame, so the countdown draws above bar fills
                cdFrame:SetFrameLevel(state.container:GetFrameLevel() + 4)
                cdFrame:SetDrawSwipe(false)
                cdFrame:SetDrawEdge(false)
                cdFrame:SetHideCountdownNumbers(false)
                elem._cdFrame = cdFrame
                elem._cdFrame:Hide()  -- Hidden only on first creation; OnUpdate controls visibility
            end
            -- DurationObject stays in C++ land (same pattern as customgroups/tracking.lua:123)
            pcall(elem._cdFrame.SetCooldownFromDurationObject, elem._cdFrame, durObj)
            StyleCooldownText(elem, auraId)
        end
    end

    -- Set initial bar range
    for _, elem in ipairs(state.elements) do
        if elem.type == "bar" and elem.def.source == "duration" then
            pcall(elem.barFill.SetMinMaxValues, elem.barFill, 0, durObj:GetTotalDuration())
        end
    end

    CA._LayoutElements(auraDef, state)
    CA._UpdateNameText(auraDef, state)
    state.container:Show()

    -- Single unified OnUpdate -- uses DurationObject for all timing
    state.container:SetScript("OnUpdate", function(self)
        local track = auraTracking[auraId]
        if not track then self:SetScript("OnUpdate", nil); return end

        -- Fresh DurationObject each frame (live C++ object, always current)
        local dOk, dObj = pcall(C_UnitAuras.GetAuraDuration, track.unit, track.auraInstanceID)
        if not dOk or not dObj then
            StopAuraDisplay(auraId)
            return
        end
        -- === BAR: always accurate (SetValue/SetMinMaxValues accept secrets) ===
        for _, elem in ipairs(state.elements) do
            if elem.type == "bar" and elem.def.source == "duration" then
                pcall(elem.barFill.SetMinMaxValues, elem.barFill, 0, dObj:GetTotalDuration())
                local fillMode = elem.def.fillMode or "deplete"
                if fillMode == "deplete" then
                    pcall(elem.barFill.SetValue, elem.barFill, dObj:GetRemainingDuration())
                else
                    pcall(elem.barFill.SetValue, elem.barFill, dObj:GetElapsedDuration())
                end
            end
        end

        -- === TEXT: try non-secret custom format, fall back to CooldownFrame ===
        -- Throttle text updates to 0.1s intervals (bar fill remains per-frame for smoothness)
        local now = GetTime()
        local textElapsed = now - (state._lastTextUpdate or 0)
        if textElapsed >= 0.1 then
            state._lastTextUpdate = now
            local htDb = GetDB(auraDef)
            local hideText = htDb and htDb.hideText
            for _, elem in ipairs(state.elements) do
                if elem.type == "text" and elem.def.source == "duration" then
                    if hideText then
                        pcall(elem.widget.Hide, elem.widget)
                        if elem._cdFrame then elem._cdFrame:Hide() end
                    else
                        local rok, remaining = pcall(function()
                            local r = dObj:GetRemainingDuration()
                            if issecretvalue(r) then return nil end
                            return r
                        end)
                        if rok and remaining and remaining > 0 then
                            -- Non-secret: custom formatted text
                            local text
                            if remaining >= 60 then
                                text = string.format("%dm", math.floor(remaining / 60))
                            elseif remaining >= 10 then
                                text = string.format("%.0f", remaining)
                            else
                                text = string.format("%.1f", remaining)
                            end
                            pcall(elem.widget.SetText, elem.widget, text)
                            pcall(elem.widget.Show, elem.widget)
                            if elem._cdFrame then elem._cdFrame:Hide() end
                        else
                            -- Secret: CooldownFrame handles countdown via C++ rendering
                            pcall(elem.widget.Hide, elem.widget)
                            if elem._cdFrame then elem._cdFrame:Show() end
                        end
                    end
                end
            end
        end
    end)
end

--------------------------------------------------------------------------------
-- Public Scan Functions
--------------------------------------------------------------------------------

function CA.ScanAura(aura)
    local state = CA._activeAuras[aura.id]
    if not state then return end

    local db = GetDB(aura)
    local isEnabled = db and db.enabled
    -- For linked auras, check primary's enabled state as fallback
    if not isEnabled and aura.anchorTo then
        local primaryAura = CA._registry[aura.anchorTo]
        local primaryDb = primaryAura and GetDB(primaryAura)
        isEnabled = primaryDb and primaryDb.enabled
    end
    if not db or not isEnabled then
        state.container:Hide()
        return
    end

    if not UnitExists(aura.unit) then
        if not CA._isEditModeActive() then
            StopAuraDisplay(aura.id)
            state.container:Hide()
        end
        return
    end

    if not aura.filter or not aura.auraSpellId then return end

    -- === Skip FindAuraOnUnit when identity is already tracked ===
    local auraData, matchedSpellId
    local existingTrack = auraTracking[aura.id]
    if existingTrack and existingTrack.unit == aura.unit then
        -- Validate existing tracking — GetAuraDuration confirms instance still alive
        local vok, vdur = pcall(C_UnitAuras.GetAuraDuration, existingTrack.unit, existingTrack.auraInstanceID)
        if not vok or not vdur then
            -- Stale tracking — clear and fall through to full scan
            auraTracking[aura.id] = nil
            auraData, matchedSpellId = FindAuraOnUnit(aura.unit, aura.filter, aura.auraSpellId, aura.linkedSpellIds, aura._canonName)
        end
        -- else: valid tracking, skip FindAuraOnUnit entirely (auraData stays nil)
    else
        auraData, matchedSpellId = FindAuraOnUnit(aura.unit, aura.filter, aura.auraSpellId, aura.linkedSpellIds, aura._canonName)
    end

    if auraData then
        -- Capture auraInstanceID + activeSpellId for DurationObject tracking
        pcall(function()
            local iid = auraData.auraInstanceID
            if iid and not issecretvalue(iid) then
                auraTracking[aura.id] = { unit = aura.unit, auraInstanceID = iid, activeSpellId = matchedSpellId }
                CacheAuraIdentity(aura.unit, aura.id, iid, matchedSpellId)
            end
        end)

        -- Applications from direct scan
        local ok, apps = pcall(function() return auraData.applications end)
        if ok and apps then
            local scanDb = GetDB(aura)
            local scanHideText = scanDb and scanDb.hideText
            local displayApps = (apps == 0) and 1 or apps
            for _, elem in ipairs(state.elements) do
                if elem.def.source == "applications" then
                    if elem.type == "text" then
                        if not scanHideText then
                            pcall(elem.widget.SetText, elem.widget, tostring(displayApps))
                            pcall(elem.widget.Show, elem.widget)
                        end
                    elseif elem.type == "bar" then
                        pcall(elem.barFill.SetValue, elem.barFill, displayApps)
                    end
                end
            end
        end
    end

    -- === Validate tracked instance (from direct scan, CDM hook, or rescan) ===
    local tracked = auraTracking[aura.id]
    if tracked then
        local dok, durObj = pcall(C_UnitAuras.GetAuraDuration, tracked.unit, tracked.auraInstanceID)
        if not dok or not durObj then
            auraTracking[aura.id] = nil
        end
    end

    -- Re-check after validation
    tracked = auraTracking[aura.id]
    if not tracked then
        StopAuraDisplay(aura.id)
        -- keepVisible: leave container shown when target exists (for exclamation animation)
        if aura.keepVisible and UnitExists(aura.unit) then
            if not CA._isEditModeActive() then state.container:Show() end
        else
            if not CA._isEditModeActive() then state.container:Hide() end
        end
        -- Lifecycle hook: aura missing
        if aura.onAuraMissing then aura.onAuraMissing(aura.id, state) end
        -- Single deferred retry: catches CDM hook delay + transient secret windows.
        -- pendingRetries gate prevents duplicate/cascading timers for the same aura.
        if not pendingRetries[aura.id] and UnitExists(aura.unit) then
            pendingRetries[aura.id] = true
            local auraRef = aura
            C_Timer.After(0.2, function()
                pendingRetries[auraRef.id] = nil
                if CA._activeAuras[auraRef.id] and UnitExists(auraRef.unit) then
                    CA.ScanAura(auraRef)
                end
            end)
        end
        return
    end

    -- === Start/update display via DurationObject ===
    StartAuraDisplay(aura.id)
    -- Lifecycle hook: aura found
    if aura.onAuraFound then aura.onAuraFound(aura.id, state) end

    -- === Detect linked spell override changes (icon/bar/text visual swap) ===
    local tracked2 = auraTracking[aura.id]
    if tracked2 and aura.spellOverrides then
        local prevActive = state._lastActiveSpellId
        local curActive = tracked2.activeSpellId
        if prevActive ~= curActive then
            state._lastActiveSpellId = curActive
            CA._ApplyIconMode(aura, state)
            CA._ApplyTextStyling(aura, state)
            CA._ApplyBarStyling(aura, state)
            CA._UpdateNameText(aura, state)
        end
    end

    -- === Applications via combat-safe API (when direct scan didn't provide them) ===
    if not auraData then
        local fallbackDb = GetDB(aura)
        local fallbackHideText = fallbackDb and fallbackDb.hideText
        for _, elem in ipairs(state.elements) do
            if elem.def.source == "applications" then
                local aok, countStr = pcall(C_UnitAuras.GetAuraApplicationDisplayCount,
                    tracked.unit, tracked.auraInstanceID, 1)
                if aok and countStr then
                    if elem.type == "text" then
                        if not fallbackHideText then
                            local displayStr = countStr
                            if not issecretvalue(countStr) and (countStr == "" or countStr == "0") then
                                displayStr = "1"
                            end
                            pcall(elem.widget.SetText, elem.widget, displayStr)
                            pcall(elem.widget.Show, elem.widget)
                        end
                    elseif elem.type == "bar" then
                        if not issecretvalue(countStr) then
                            local num = tonumber(countStr)
                            if num then
                                pcall(elem.barFill.SetValue, elem.barFill, (num == 0) and 1 or num)
                            end
                        end
                    end
                end
            end
        end
    end
end

local function ScanAllAurasForUnit(unit)
    local auras = CA._classAuras[playerClassToken]
    if not auras then return end
    for _, aura in ipairs(auras) do
        if aura.unit == unit and CA._activeAuras[aura.id] then
            CA.ScanAura(aura)
        end
    end
end

local function ScanAllAuras()
    local auras = CA._classAuras[playerClassToken]
    if not auras then return end
    for _, aura in ipairs(auras) do
        if CA._activeAuras[aura.id] then
            CA.ScanAura(aura)
        end
    end
end

--------------------------------------------------------------------------------
-- Namespace Promotions
--------------------------------------------------------------------------------

CA._ScanAllAuras = ScanAllAuras
CA._ScanAllAurasForUnit = ScanAllAurasForUnit
CA._StartAuraDisplay = StartAuraDisplay
CA._StopAuraDisplay = StopAuraDisplay
CA._StyleCooldownText = StyleCooldownText
