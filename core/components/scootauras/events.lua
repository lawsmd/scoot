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
        for trackerId, tracker in pairs(SAU.AllTrackers()) do
            local state = SAU._activeStates[trackerId]
            if state and state.shell and SAU.IsTrackerActive(trackerId, tracker)
                and SAU.IsModuleActive() then
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
        -- The loop force-shows standalone shells but never a grouped member's
        -- visual, so a member the combat gate hid would stay invisible with
        -- Edit Mode open. The gate reads open while editing, so this shows it.
        SAU.RefreshCombatGates()
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
    SAU.ValidateGroupData()
    -- Records migrated from the per-profile stores carry a class token instead
    -- of a spec list, because the migration runs before class data is loaded.
    SAU.ResolvePendingSpecStamps()
    -- Claims only what loads in this character's current spec; the rest is
    -- listed under Not Loaded and holds no container.
    SAU.ReconcileActivation("pew")
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
eventFrame:RegisterEvent("PLAYER_FOCUS_CHANGED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
-- Trackers with "Only in Combat" gate on plain combat state: a missing-buff
-- reminder through its clip window, every other kind by hiding its frame.
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
-- Missing-buff trackers with "Only in Instances" gate on plain instance state,
-- which only ever moves across one of these two.
eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
-- Spell descriptions (name/icon by CDM override chain) cache a base-to-display
-- map; these are the moments the catalog behind it can move.
eventFrame:RegisterEvent("COOLDOWN_VIEWER_DATA_LOADED")
eventFrame:RegisterEvent("COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED")
eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
eventFrame:RegisterEvent("TRAIT_CONFIG_UPDATED")
-- A spell being substituted for another (Shadowform while Voidform is up).
-- The CDM event covers catalog entries; forms and stances mostly are not
-- entries, so the two below are what reaches those. Guarded because a client
-- that does not know an event name errors on registration.
for _, event in ipairs({
    "COOLDOWN_VIEWER_TABLE_HOTFIXED",
    "UPDATE_SHAPESHIFT_FORM",
    "SPELLS_CHANGED",
}) do
    pcall(eventFrame.RegisterEvent, eventFrame, event)
end
-- The group half of a missing-buff reminder: the glow the game shows on its
-- own action buttons, and the roster the scan is measured against. Both
-- payloads are plain (SpellActivationOverlayDocumentation.lua).
eventFrame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
eventFrame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE")
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")

local specResolvePending = false
local overrideResolvePending = false
local zoneResolvePending = false

--- Re-runs every reminder's plain-state gate a moment after a zone change.
-- Deferred and coalesced on purpose: entering a dungeon fires these events
-- several times and not all of the instance data is present on the first, which
-- is why Blizzard's own instance-difficulty display waits 250 ms
-- (InstanceDifficulty.lua:81-96). The synchronous pass beside this one can
-- therefore read the zone the player just left.
local function RefreshGatesSoon()
    if zoneResolvePending or not SAU.Missing then return end
    zoneResolvePending = true
    C_Timer.After(0.25, function()
        zoneResolvePending = false
        if SAU.Missing then SAU.Missing.RefreshGates() end
    end)
end

-- arg1 is the first payload of whichever event arrived: a unit token for
-- PLAYER_SPECIALIZATION_CHANGED, a spell id for the two glow events, a base
-- spell id for the override event, whose arg2 is the spell replacing it.
eventFrame:SetScript("OnEvent", function(_, event, arg1, arg2)
    if event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW"
        or event == "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE" then
        if SAU.Missing then
            SAU.Missing.OnOverlayGlow(arg1, event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
        end
        return
    end
    if event == "PLAYER_SPECIALIZATION_CHANGED" then
        -- Fires for party and raid members too; only the player's own spec
        -- moves the gate.
        if arg1 and arg1 ~= "player" then return end
        SAU.InvalidateSpellDescriptions()
        Engine.MarkStaleFilters(event)
        -- Re-run every tracker's spec gate one frame later: the event can
        -- arrive before GetSpecialization reports the new spec, and a talent
        -- swap fires it more than once. Both calls are plain Scoot frame work,
        -- so this needs no structural gate and no pending queue.
        if not specResolvePending then
            specResolvePending = true
            C_Timer.After(0, function()
                specResolvePending = false
                SAU.RebuildAll()
                if SAU.Groups then SAU.Groups.RequestReflow() end
            end)
        end
        return
    end
    if event == "COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED" then
        -- One spell substituted or restored: base id in arg1, the spell
        -- replacing it in arg2, nil when the substitution ends. The catalog is
        -- unchanged, so the map is patched for this one base rather than
        -- dropped, which would walk every category again on the next
        -- description each time a player shifts form.
        SAU.NoteSpellOverride(arg1, arg2)
        if SAU.Missing then SAU.Missing.OnOverrideChanged(arg1) end
        return
    end
    if event == "UPDATE_SHAPESHIFT_FORM" or event == "SPELLS_CHANGED" then
        -- Both arrive before the state they report has settled (PRD core.lua
        -- records the same of UPDATE_SHAPESHIFT_FORM), and SPELLS_CHANGED
        -- fires repeatedly over a login, so coalesce into one deferred pass.
        -- These run on the shared frame for every user, so bail before any
        -- work when nothing reads them.
        if overrideResolvePending or not SAU.Missing or not SAU.Missing.AnyLive() then
            return
        end
        overrideResolvePending = true
        C_Timer.After(0, function()
            overrideResolvePending = false
            SAU.Missing.OnOverrideChanged()
        end)
        return
    end
    if event == "COOLDOWN_VIEWER_DATA_LOADED"
        or event == "COOLDOWN_VIEWER_TABLE_HOTFIXED"
        or event == "TRAIT_CONFIG_UPDATED" then
        SAU.InvalidateSpellDescriptions()
        if SAU.Missing then SAU.Missing.RefreshOverrideDependents() end
        Engine.MarkStaleFilters(event)
        return
    end

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
        RefreshGatesSoon()

    elseif event == "PLAYER_TARGET_CHANGED" then
        -- Containers bound to "target" do not self-refresh on retarget.
        Engine.KickUnit("target", "retarget")

    elseif event == "PLAYER_FOCUS_CHANGED" then
        Engine.KickUnit("focus", "refocus")

    elseif event == "PLAYER_REGEN_ENABLED" then
        Engine.TryFlush("regen")
        SAU.RefreshCombatGates()
        if SAU.Missing then SAU.Missing.RefreshGates() end

    elseif event == "PLAYER_REGEN_DISABLED" then
        SAU.RefreshCombatGates()
        if SAU.Missing then SAU.Missing.RefreshGates() end

    elseif event == "ZONE_CHANGED_NEW_AREA" then
        -- Restricted-instance exits open the gate without a regen event.
        Engine.TryFlush("zone")
        RefreshGatesSoon()

    elseif event == "GROUP_ROSTER_UPDATE" then
        if SAU.Missing then SAU.Missing.RefreshGroupTrackers() end
    end
end)
