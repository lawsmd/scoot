-- scootauras/events.lua - Init orchestration, Edit Mode callbacks, flush triggers
local addonName, addon = ...

local SAU = addon.ScootAuras
local Engine = SAU.Engine

local containersInitialized = false
local editModeActive = false
local lemCallbacksRegistered = false

--------------------------------------------------------------------------------
-- LibEditMode callbacks (once per session; AddFrame happens per claim)
--------------------------------------------------------------------------------

local function RegisterLEMCallbacks()
    if lemCallbacksRegistered then return end
    local lib = LibStub("LibEditMode", true)
    if not lib then return end
    lemCallbacksRegistered = true

    lib:RegisterCallback("layout", function()
        -- Positions only. A layout switch that swaps profiles reaches the
        -- Edit Mode preview through reconcile -> ClaimForTracker ->
        -- ApplyStyling, so no preview work is needed here.
        Engine.ApplyPositionsForActiveLayout()
    end)

    lib:RegisterCallback("enter", function()
        editModeActive = true
        local store = SAU.GetStore()
        if not store or not store.trackers then return end
        for trackerId, tracker in pairs(store.trackers) do
            local state = SAU._activeStates[trackerId]
            if state and state.shell and tracker.enabled and SAU.IsModuleActive() then
                -- Engine content cannot fake an aura; show Scoot-side preview
                -- art on the frame instead. Grouped shells stay hidden: the
                -- group frame is the drag unit, and the preview art rides the
                -- visual inside it.
                if not (state.entry and state.entry.grouped) then
                    state.shell:Show()
                end
                Engine.ApplyAll(trackerId)
                Engine.ShowEditModePreview(trackerId, tracker, state)
            end
        end
        -- Empty groups become visible (and draggable) while editing.
        if SAU.Groups then SAU.Groups.ReflowAll() end
    end)

    lib:RegisterCallback("exit", function()
        editModeActive = false
        if SAU.Rearrange then SAU.Rearrange.ForceEnd() end
        for trackerId, state in pairs(SAU._activeStates) do
            Engine.HideEditModePreview(state)
            local tracker = SAU.GetTracker(trackerId)
            if tracker and SAU._ApplyStyling then
                SAU._ApplyStyling(trackerId, tracker)
            end
        end
        -- Re-hide empty groups.
        if SAU.Groups then SAU.Groups.ReflowAll() end
    end)
end

SAU._isEditModeActive = function() return editModeActive end

--------------------------------------------------------------------------------
-- Init
--------------------------------------------------------------------------------

local function InitializeFromProfile()
    Engine.SetInitialized()
    RegisterLEMCallbacks()
    if not SAU.IsModuleActive() then return end
    local store = SAU.GetStore()
    if not store or not store.trackers then return end
    SAU.ValidateGroupData()
    for trackerId in pairs(store.trackers) do
        SAU.RegisterTrackerComponent(trackerId)
        addon:EnsureComponentDB(SAU.GetComponentId(trackerId))
        Engine.ClaimForTracker(trackerId)
    end
    -- Groups after trackers: membership reparents claimed visuals.
    if SAU.Groups then SAU.Groups.ApplyAll() end
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
eventFrame:RegisterEvent("PLAYER_FOCUS_CHANGED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")

eventFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_ENTERING_WORLD" then
        if not containersInitialized then
            containersInitialized = true
            InitializeFromProfile()
            C_Timer.After(0.5, function()
                SAU.RebuildAll()
            end)
        else
            SAU.RebuildAll()
            Engine.TryFlush("pew")
        end

    elseif event == "PLAYER_TARGET_CHANGED" then
        -- Containers bound to "target" do not self-refresh on retarget.
        Engine.KickUnit("target", "retarget")

    elseif event == "PLAYER_FOCUS_CHANGED" then
        Engine.KickUnit("focus", "refocus")

    elseif event == "PLAYER_REGEN_ENABLED" then
        Engine.TryFlush("regen")

    elseif event == "ZONE_CHANGED_NEW_AREA" then
        -- Restricted-instance exits open the gate without a regen event.
        Engine.TryFlush("zone")
    end
end)
