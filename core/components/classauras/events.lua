-- classauras/events.lua - Event handling, Edit Mode integration, init orchestration
local addonName, addon = ...

local CA = addon.ClassAuras

-- Local aliases (resolved at load time — all prior files loaded)
local GetDB = CA._GetDB
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
                    -- Content is engine-owned and cannot fake an aura; show
                    -- Scoot-side preview art on the frame instead.
                    st.container:Show()
                    CA.Engine.ApplyAll(aura)
                    CA.Engine.ShowEditModePreview(aura, st)
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
            local st = CA._activeAuras[aura.id]
            if st then
                CA.Engine.HideEditModePreview(st)
                if aura.onEditModeExit then aura.onEditModeExit(aura.id, st) end
                -- Re-assert Tier 1 state (enabled/hidden, scale, opacity)
                CA._ApplyStyling(aura)
            end
        end
        CA._RescanForCDMBorrow()
    end)
end

--------------------------------------------------------------------------------
-- Event Handling
--------------------------------------------------------------------------------
-- Aura acquisition and display are engine-side (engine.lua); events here only
-- cover init, target kicks, the regen flush, spec rebuilds, and CDM rescans.

local caEventFrame = CreateFrame("Frame")
caEventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
caEventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
caEventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
caEventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")

caEventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        if not containersInitialized then
            CA._InitializeContainers()
            containersInitialized = true

            C_Timer.After(0.5, function()
                CA._RebuildAll()
                InitializeEditMode()
            end)

            -- Install CDM hooks and do the initial rescan after CDM loads
            C_Timer.After(1.0, function()
                CA._InstallMixinHooks()
                CA._RescanForCDMBorrow()
            end)
        else
            CA._RebuildAll()
            C_Timer.After(0.5, function()
                CA._RescanForCDMBorrow()
            end)
        end

    elseif event == "PLAYER_TARGET_CHANGED" then
        CA._RescanForCDMBorrow()
        C_Timer.After(0.1, function() CA._RescanForCDMBorrow() end)
        -- Engine containers bound to "target" do not self-refresh on retarget
        CA.Engine.KickUnit("target", "retarget")

    elseif event == "PLAYER_REGEN_ENABLED" then
        CA._RescanForCDMBorrow()
        -- Engine: flush styling/build work queued while the button tree was
        -- untouchable, then kick every container back in sync
        CA.Engine.FlushPending()

    elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
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
