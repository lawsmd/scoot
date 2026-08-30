-- damagemetersY/events.lua - Event registration, timer ticker, combat state sync
local _, addon = ...
local DMY = addon.DamageMetersY

--------------------------------------------------------------------------------
-- Event System
--------------------------------------------------------------------------------

local updatePending = false
local resetPending = false

local function OnEvent(event, ...)
    if not DMY._initialized then return end

    -- Resolution/UI-scale changed: pixel-snapped layout offsets are stale
    if event == "UI_SCALE_CHANGED" or event == "DISPLAY_SIZE_CHANGED" then
        if DMY._comp then DMY._ApplyStyling(DMY._comp) end
        return
    end

    if event == "DAMAGE_METER_RESET" then
        resetPending = true
        if DMY._CloseDrilldown then DMY._CloseDrilldown() end
    end

    -- Roster changed: refresh the drilldown GUID cache while identities are
    -- readable. In combat do nothing — the next OOC cycle rebuilds anyway.
    if event == "GROUP_ROSTER_UPDATE" then
        if not DMY._inCombat then
            DMY._RebuildGUIDCache()
            DMY._RebuildRosterNames()
        end
        return
    end

    -- Combat ended: immediate synchronous full refresh
    if event == "PLAYER_REGEN_ENABLED" then
        DMY._Trace("REGEN_ENABLED -> ExitCombatMode + FullRefresh")
        DMY._ExitCombatMode()
        DMY._FullRefreshAllWindows()
        if DMY._comp then
            DMY._RefreshOpacity(DMY._comp)
        end
        -- A segment just closed: recap→segment labels are stale (rebuilt
        -- lazily by the deaths drilldown)
        DMY._recapSegmentIndexDirty = true
        if DMY._OnCombatEnd_RefreshDrilldown then
            DMY._OnCombatEnd_RefreshDrilldown()
        end
        return
    end

    -- Combat started: transition to combat mode
    if event == "PLAYER_REGEN_DISABLED" then
        DMY._Trace("REGEN_DISABLED -> EnterCombatMode")
        DMY._EnterCombatMode()
        if DMY._comp then
            DMY._RefreshOpacity(DMY._comp)
        end
        return
    end

    -- Auto-reset on instance entry
    if event == "PLAYER_ENTERING_WORLD" then
        local isInitialLogin, isReloadingUi = ...
        -- Defer styling re-apply (existing behavior)
        C_Timer.After(1.0, function()
            if DMY._comp then
                DMY._ApplyStyling(DMY._comp)
            end
        end)

        -- Auto-reset on instance entry
        if isInitialLogin or isReloadingUi then return end

        local comp = DMY._comp
        if not comp or not comp.db then return end

        local mode = comp.db.autoResetData
        if mode ~= "instance" then return end

        local inInstance, instanceType = IsInInstance()
        if not inInstance then return end
        if instanceType ~= "party" and instanceType ~= "raid" and instanceType ~= "scenario" then return end

        if not C_DamageMeter or not C_DamageMeter.ResetAllCombatSessions then return end

        if comp.db.autoResetPrompt then
            if addon.Dialogs and addon.Dialogs.Show then
                addon.Dialogs:Show("SCOOT_DM_RESET_CONFIRM", {
                    onAccept = function()
                        C_DamageMeter.ResetAllCombatSessions()
                    end,
                })
            end
        else
            C_DamageMeter.ResetAllCombatSessions()
        end
        return
    end

    -- Throttled update for damage meter data events
    if not updatePending then
        updatePending = true
        DMY._Trace("THROTTLE event=" .. event .. " inCombat=" .. tostring(DMY._inCombat))
        local throttle = DMY._comp and DMY._comp.db and DMY._comp.db.updateThrottle or 1.0
        C_Timer.After(throttle, function()
            updatePending = false
            if resetPending then
                resetPending = false
                DMY._HandleReset()
            end
            DMY._Trace("TIMER_FIRED calling _UpdateAllWindows")
            DMY._UpdateAllWindows()
            if DMY._RefreshOpenDeathLog then
                DMY._RefreshOpenDeathLog()
            end
        end)
    end
end

--------------------------------------------------------------------------------
-- Timer Ticker (1-second OnUpdate for header stopwatch)
--------------------------------------------------------------------------------

local timerFrame = nil

local function OnTimerUpdate(self, elapsed)
    self._elapsed = (self._elapsed or 0) + elapsed
    if self._elapsed < 1.0 then return end
    self._elapsed = 0

    if not DMY._initialized then return end

    for i = 1, DMY.MAX_WINDOWS do
        local win = DMY._windows[i]
        local cfg = DMY._GetWindowConfig(i)
        if win and cfg and cfg.enabled and win.frame:IsShown() then
            DMY._UpdateTimerText(i)
        end
    end
end

--------------------------------------------------------------------------------
-- Initialization (called from core.lua _Initialize)
--------------------------------------------------------------------------------

function DMY._InitializeEvents(comp)
    -- Events. Registered once (_Initialize latches), so the file-scoped owner
    -- keeps them alive across component re-initialization.
    for _, event in ipairs({
        "DAMAGE_METER_COMBAT_SESSION_UPDATED",
        "DAMAGE_METER_CURRENT_SESSION_UPDATED",
        "DAMAGE_METER_RESET",
        "PLAYER_REGEN_ENABLED",
        "PLAYER_REGEN_DISABLED",
        "PLAYER_ENTERING_WORLD",
        "GROUP_ROSTER_UPDATE",
        "UI_SCALE_CHANGED",
        "DISPLAY_SIZE_CHANGED",
    }) do
        addon.Events.On("DamageMetersY", event, OnEvent)
    end

    -- Timer ticker
    timerFrame = CreateFrame("Frame")
    timerFrame._elapsed = 0
    timerFrame:SetScript("OnUpdate", OnTimerUpdate)

    -- If already in combat when this loads, sync state
    if InCombatLockdown() then
        DMY._inCombat = true
        DMY._combatStartTime = GetTime()
    end
end
