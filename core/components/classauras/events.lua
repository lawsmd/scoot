-- classauras/events.lua - Event handling, Edit Mode integration, init orchestration
local addonName, addon = ...

local CA = addon.ClassAuras

-- Local aliases (resolved at load time — all prior files loaded)
local GetDB = CA._GetDB
local auraTracking = CA._auraTracking
local guidCache = CA._guidCache
local CacheAuraIdentity = CA._CacheAuraIdentity
local spellToAura = CA._spellToAura
local nameToAura = CA._nameToAura
local playerClassToken = CA._playerClassToken

-- Local state
local editModeActive = false
local containersInitialized = false
local rebuildPending = false

--------------------------------------------------------------------------------
-- LibEditMode Integration
--------------------------------------------------------------------------------

local function SaveAuraPosition(auraId, layoutName, point, x, y)
    if not addon.db or not addon.db.profile then return end
    addon.db.profile.classAuraPositions = addon.db.profile.classAuraPositions or {}
    addon.db.profile.classAuraPositions[auraId] = addon.db.profile.classAuraPositions[auraId] or {}
    addon.db.profile.classAuraPositions[auraId][layoutName] = {
        point = point,
        x = x,
        y = y,
    }
end

local function RestoreAuraPosition(auraId, layoutName)
    local state = CA._activeAuras[auraId]
    if not state or not state.container then return end

    local positions = addon.db and addon.db.profile and addon.db.profile.classAuraPositions
    local auraPositions = positions and positions[auraId]
    local pos = auraPositions and auraPositions[layoutName]

    if pos and pos.point then
        state.container:ClearAllPoints()
        state.container:SetPoint(pos.point, pos.x or 0, pos.y or 0)
    end
end

local function InitializeEditMode()
    local lib = LibStub("LibEditMode", true)
    if not lib then return end

    local auras = CA._classAuras[playerClassToken]
    if not auras then return end

    for _, aura in ipairs(auras) do
        if not aura.skipEditMode then
            local state = CA._activeAuras[aura.id]
            if state and state.container then
                state.container.editModeName = aura.editModeName or aura.label

                local auraId = aura.id
                local dp = aura.defaultPosition or { point = "CENTER", x = 0, y = -200 }

                lib:AddFrame(state.container, function(frame, layoutName, point, x, y)
                    if point and x and y then
                        frame:ClearAllPoints()
                        frame:SetPoint(point, x, y)
                    end
                    if layoutName then
                        local savedPoint, _, _, savedX, savedY = frame:GetPoint(1)
                        if savedPoint then
                            SaveAuraPosition(auraId, layoutName, savedPoint, savedX, savedY)
                        else
                            SaveAuraPosition(auraId, layoutName, point, x, y)
                        end
                    end
                end, {
                    point = dp.point,
                    x = dp.x or 0,
                    y = dp.y or 0,
                }, nil)

                local Brand = addon.EditMode and addon.EditMode.Brand
                if Brand then
                    -- An aura hidden from settings has no section to expand, so
                    -- the link falls back to the class page.
                    local visible = not aura.hideFromSettings
                    Brand:Register(state.container, {
                        navKey      = CA.NAV_KEY_BY_CLASS[playerClassToken],
                        componentId = visible and ("classAura_" .. aura.id) or nil,
                        sectionKey  = visible and "main" or nil,
                    })
                end
            end
        end
    end

    lib:RegisterCallback("layout", function(layoutName, layoutIndex)
        local classAuras = CA._classAuras[playerClassToken]
        if not classAuras then return end
        for _, aura in ipairs(classAuras) do
            if not aura.skipEditMode then
                RestoreAuraPosition(aura.id, layoutName)
            end
        end
        -- Re-apply anchor linkage after primary positions restored
        for _, aura in ipairs(classAuras) do
            if aura.anchorTo then
                local st = CA._activeAuras[aura.id]
                if st then CA._ApplyAnchorLinkage(aura, st) end
            end
        end
    end)

    lib:RegisterCallback("enter", function()
        editModeActive = true
        local classAuras = CA._classAuras[playerClassToken]
        if not classAuras then return end
        for _, aura in ipairs(classAuras) do
            local st = CA._activeAuras[aura.id]
            if st and st.container then
                local db = GetDB(aura)
                -- For linked auras, check primary's enabled state
                local isEnabled = db and db.enabled
                if not isEnabled and aura.anchorTo then
                    local primaryAura = CA._registry[aura.anchorTo]
                    local primaryDb = primaryAura and GetDB(primaryAura)
                    isEnabled = primaryDb and primaryDb.enabled
                end
                if isEnabled then
                    CA._ApplyIconMode(aura, st)
                    CA._ApplyTextStyling(aura, st)
                    CA._ApplyBarStyling(aura, st)
                    CA._LayoutElements(aura, st)
                    st.container:Show()
                    -- Set preview for elements and hide CooldownFrame fallback
                    local emHideText = db.hideText
                    for _, elem in ipairs(st.elements) do
                        if elem._cdFrame then elem._cdFrame:Hide() end
                        if elem.type == "text" and elem.def.source == "applications" then
                            if not emHideText then
                                pcall(elem.widget.SetText, elem.widget, "#")
                                pcall(elem.widget.Show, elem.widget)
                            end
                        end
                        if elem.type == "text" and elem.def.source == "duration" then
                            if not emHideText then
                                pcall(elem.widget.SetText, elem.widget, "8.3")
                                pcall(elem.widget.Show, elem.widget)
                            end
                        end
                        -- Bar preview: ~60% fill
                        if elem.type == "bar" and elem.def.source == "applications" then
                            local maxVal = elem.def.maxValue or 20
                            pcall(elem.barFill.SetValue, elem.barFill, math.floor(maxVal * 0.6))
                        end
                        if elem.type == "bar" and elem.def.source == "duration" then
                            local maxVal = 20  -- preview value for edit mode
                            pcall(elem.barFill.SetMinMaxValues, elem.barFill, 0, maxVal)
                            pcall(elem.barFill.SetValue, elem.barFill, math.floor(maxVal * 0.6))
                        end
                    end
                    -- Per-aura edit mode enter hook
                    if aura.onEditModeEnter then aura.onEditModeEnter(aura.id, st) end
                end
            end
        end
        -- Re-apply anchor linkage in edit mode
        for _, aura in ipairs(classAuras) do
            if aura.anchorTo then
                local st = CA._activeAuras[aura.id]
                if st then CA._ApplyAnchorLinkage(aura, st) end
            end
        end
    end)

    lib:RegisterCallback("exit", function()
        editModeActive = false
        local classAuras = CA._classAuras[playerClassToken]
        if not classAuras then return end
        for _, aura in ipairs(classAuras) do
            -- Clear preview text and bar before rescan
            local st = CA._activeAuras[aura.id]
            if st then
                for _, elem in ipairs(st.elements) do
                    if elem.type == "text" and elem.def.source == "applications" then
                        pcall(elem.widget.SetText, elem.widget, "")
                    end
                    if elem.type == "text" and elem.def.source == "duration" then
                        pcall(elem.widget.SetText, elem.widget, "")
                    end
                    if elem.type == "bar" and elem.def.source == "applications" then
                        pcall(elem.barFill.SetValue, elem.barFill, 0)
                    end
                    if elem.type == "bar" and elem.def.source == "duration" then
                        pcall(elem.barFill.SetValue, elem.barFill, 0)
                    end
                end
                -- Stop any active aura display before rescan
                CA._StopAuraDisplay(aura.id)
                -- Per-aura edit mode exit hook
                if aura.onEditModeExit then aura.onEditModeExit(aura.id, st) end
            end
            if CA._activeAuras[aura.id] then
                CA.ScanAura(aura)
            end
        end
        CA._RescanForCDMBorrow()
    end)
end

--------------------------------------------------------------------------------
-- Event Handling
--------------------------------------------------------------------------------

local caEventFrame = CreateFrame("Frame")
caEventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
caEventFrame:RegisterEvent("UNIT_AURA")
caEventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
caEventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
caEventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
caEventFrame:RegisterEvent("ENCOUNTER_START")
caEventFrame:RegisterEvent("CHALLENGE_MODE_START")
caEventFrame:RegisterEvent("PVP_MATCH_ACTIVE")

caEventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        if not containersInitialized then
            CA._InitializeContainers()
            containersInitialized = true

            C_Timer.After(0.5, function()
                CA._RebuildAll()
                InitializeEditMode()
            end)

            -- Install CDM mixin hooks and do initial scans after CDM loads
            C_Timer.After(1.0, function()
                CA._InstallMixinHooks()
                CA._ScanAllAuras()
                CA._RescanForCDMBorrow()
            end)
        else
            CA._RebuildAll()
            C_Timer.After(0.5, function()
                CA._ScanAllAuras()
                CA._RescanForCDMBorrow()
            end)
        end

    elseif event == "UNIT_AURA" then
        local unit, updateInfo = ...
        if CA._trackedUnits[unit] then
            -- Check for removal of tracked instances (NeverSecretContents = true)
            if updateInfo and updateInfo.removedAuraInstanceIDs then
                for _, removedID in ipairs(updateInfo.removedAuraInstanceIDs) do
                    for auraId, tracked in pairs(auraTracking) do
                        if tracked.auraInstanceID == removedID and tracked.unit == unit then
                            auraTracking[auraId] = nil
                            break
                        end
                    end
                    -- Invalidate GUID cache entries referencing the removed instance
                    for guid, cached in pairs(guidCache) do
                        if cached.auraInstanceID == removedID then
                            guidCache[guid] = nil
                            break
                        end
                    end
                end
            end

            -- Detect pandemic refresh: re-trigger CooldownFrame setup with fresh DurationObject
            if updateInfo and updateInfo.updatedAuraInstanceIDs then
                local auras = CA._classAuras[playerClassToken]
                if auras then
                    for _, aura in ipairs(auras) do
                        local tracked = auraTracking[aura.id]
                        if tracked and tracked.unit == unit then
                            for _, updatedID in ipairs(updateInfo.updatedAuraInstanceIDs) do
                                if updatedID == tracked.auraInstanceID then
                                    CA.ScanAura(aura)
                                    break
                                end
                            end
                        end
                    end
                end
            end

            -- === Process addedAuras for instant identity capture ===
            -- Two-tier matching: spellId (O(1)), then name fallback (O(1)) when spellId is secret.
            -- pcall ensures zero regression if fields happen to be secret in some edge case.
            if updateInfo and updateInfo.addedAuras then
                for _, addedAura in ipairs(updateInfo.addedAuras) do
                    pcall(function()
                        local iid = addedAura.auraInstanceID
                        if not iid or issecretvalue(iid) then return end

                        local sid = addedAura.spellId
                        local matchedAura = nil
                        local activeSpell = nil

                        -- Primary: spellId match (O(1))
                        if sid and not issecretvalue(sid) then
                            matchedAura = spellToAura[sid]
                            activeSpell = sid
                        end

                        -- Fallback: name match when spellId is secret (O(1) table lookup)
                        if not matchedAura then
                            local auraName = addedAura.name
                            if auraName and not issecretvalue(auraName) then
                                matchedAura = nameToAura[auraName:lower()]
                                if matchedAura then
                                    activeSpell = matchedAura.auraSpellId
                                end
                            end
                        end

                        if matchedAura and matchedAura.unit == unit and CA._activeAuras[matchedAura.id] then
                            auraTracking[matchedAura.id] = {
                                unit = unit,
                                auraInstanceID = iid,
                                activeSpellId = activeSpell,
                            }
                            CacheAuraIdentity(unit, matchedAura.id, iid, activeSpell)
                        end
                    end)
                end
            end

            -- === GUID cache cross-reference for isFullUpdate (when spellId is secret) ===
            if updateInfo.isFullUpdate and updateInfo.addedAuras then
                local tok2, uguid = pcall(UnitGUID, unit)
                if tok2 and uguid and not issecretvalue(uguid) then
                    local auras2 = CA._classAuras[playerClassToken]
                    if auras2 then
                        for _, aura in ipairs(auras2) do
                            if aura.unit == unit and CA._activeAuras[aura.id] and not auraTracking[aura.id] then
                                local cached = guidCache[uguid]
                                if cached and cached.auraId == aura.id then
                                    for _, addedAura in ipairs(updateInfo.addedAuras) do
                                        pcall(function()
                                            local iid = addedAura.auraInstanceID
                                            if not issecretvalue(iid) and iid == cached.auraInstanceID then
                                                auraTracking[aura.id] = {
                                                    unit = unit,
                                                    auraInstanceID = cached.auraInstanceID,
                                                    activeSpellId = cached.activeSpellId,
                                                }
                                            end
                                        end)
                                    end
                                end
                            end
                        end
                    end
                end
            end

            CA._ScanAllAurasForUnit(unit)   -- Direct scan + DurationObject tracking
            CA._RescanForCDMBorrow()        -- CDM icon alpha + instanceID capture
            -- Targeted deferred retry: only for auras that still lack tracking
            local aurasForUnit = CA._classAuras[playerClassToken]
            if aurasForUnit then
                for _, aura in ipairs(aurasForUnit) do
                    if aura.unit == unit and CA._activeAuras[aura.id] and not auraTracking[aura.id] then
                        local retryAura = aura
                        C_Timer.After(0, function()
                            if CA._activeAuras[retryAura.id] and not auraTracking[retryAura.id] then
                                CA.ScanAura(retryAura)
                            end
                        end)
                    end
                end
            end
        end

    elseif event == "PLAYER_TARGET_CHANGED" then
        -- GUID cache: instant re-acquisition for previously-seen targets
        local auras = CA._classAuras[playerClassToken]
        if auras then
            local tok, tguid = pcall(UnitGUID, "target")
            if tok and tguid and not issecretvalue(tguid) then
                for _, aura in ipairs(auras) do
                    if aura.unit == "target" and CA._activeAuras[aura.id] then
                        local cached = guidCache[tguid]
                        if cached and cached.auraId == aura.id then
                            local dok, durObj = pcall(C_UnitAuras.GetAuraDuration, "target", cached.auraInstanceID)
                            if dok and durObj then
                                -- Cache hit: populate tracking immediately
                                auraTracking[aura.id] = {
                                    unit = "target",
                                    auraInstanceID = cached.auraInstanceID,
                                    activeSpellId = cached.activeSpellId,
                                }
                            else
                                guidCache[tguid] = nil  -- invalid
                            end
                        end
                    end
                end
            end
        end

        CA._ScanAllAuras()
        CA._RescanForCDMBorrow()
        C_Timer.After(0.1, function() CA._RescanForCDMBorrow() end)

    elseif event == "PLAYER_REGEN_ENABLED" then
        -- Leaving combat: rescan auras and CDM alpha state
        CA._ScanAllAuras()
        CA._RescanForCDMBorrow()

    elseif event == "ENCOUNTER_START"
        or event == "CHALLENGE_MODE_START"
        or event == "PVP_MATCH_ACTIVE" then
        -- 12.0.5: auraInstanceID values re-randomize on these transitions, so
        -- entries in both caches silently point at dead instances. Drop them
        -- and trigger a fresh scan so the OnUpdate loop picks up new IDs.
        -- ResetAllHiddenCDMFrames covers the case where RefreshLayout has not
        -- fired yet at this point -- stale per-frame hide bindings would
        -- otherwise leave unrelated CDM icons invisible after pool re-shuffle.
        wipe(auraTracking)
        wipe(guidCache)
        CA._ResetAllHiddenCDMFrames()
        CA._ScanAllAuras()
        CA._RescanForCDMBorrow()

    elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
        wipe(guidCache)
        if not rebuildPending then
            rebuildPending = true
            C_Timer.After(0.2, function()
                rebuildPending = false
                CA._RebuildAll()
            end)
        end
    end
end)

--------------------------------------------------------------------------------
-- Namespace Promotion
--------------------------------------------------------------------------------

CA._isEditModeActive = function() return editModeActive end
