-- actionbars.lua - Per-profile enable state for action bars 2-8
local _, addon = ...
local Events = addon.Events

-- Aliases for internals promoted by core.lua
local Debug = addon.Profiles._Debug

-- OPT-24: Pre-concatenated key strings for action bar settings (avoid per-call concatenation)
local AB_SETTING_KEYS = {}   -- [barNum] = "PROXY_SHOW_ACTIONBAR_N"
local AB_ENABLE_KEYS = {}    -- [barNum] = "enableBarN"
for i = 2, 8 do
    AB_SETTING_KEYS[i] = "PROXY_SHOW_ACTIONBAR_" .. i
    AB_ENABLE_KEYS[i] = "enableBar" .. i
end

-- OPT-24: Lazy-cache setting objects (session-stable registry entries).
--
-- Only successful lookups are cached. Blizzard creates the PROXY_SHOW_ACTIONBAR_*
-- settings from a registrar that waits on both VARIABLES_LOADED and
-- PLAYER_ENTERING_WORLD (Blizzard_SettingsRegistrar.lua), which is strictly after
-- OnInitialize. Caching a failed lookup would poison every later apply for the
-- rest of the session -- see ensureBarSettingsArrivalHook below.
local settingObjectCache = {} -- [barNum] = setting object (never false)
local function getSettingObject(barNum)
    local cached = settingObjectCache[barNum]
    if cached then return cached end
    if not Settings or not Settings.GetSetting then return nil end
    local ok, setting = pcall(Settings.GetSetting, AB_SETTING_KEYS[barNum])
    if ok and setting then
        settingObjectCache[barNum] = setting
        return setting
    end
    return nil
end

-- Bars 2-8 are registered in a single loop, so bar 2 is a valid proxy for all seven.
local function areBarSettingsReady()
    return getSettingObject(2) ~= nil
end

-- Set while a bar setting is being written, so the back-sync callback can tell
-- Scoot's writes apart from the user's. Sound because SettingMixin:TriggerValueChanged
-- runs synchronously inside ApplyValue, on this same call stack.
local abWriting = false

-- OPT-24: Module-level helper with value-check (skips SetValue when already matching)
local function applyBarSettingsAPI(barNum, desired)
    local setting = getSettingObject(barNum)
    if not setting or not setting.SetValue then return false end

    if setting.GetValue then
        local ok, current = pcall(setting.GetValue, setting)
        if ok and current == desired then return true end
    end

    abWriting = true
    -- immediate=true so the write is applied now rather than parked as a pending
    -- value awaiting a commit step (SettingMixin:SetValue).
    local ok = pcall(setting.SetValue, setting, desired, true)
    abWriting = false
    return ok
end

-- Reconciler state. Combat deferral goes through Events.RunOutOfCombat with one
-- shared key, so two profile switches in one combat resolve to the latest reason
-- (the old code created one frame per bar per apply and closed over stale
-- values, so they resolved in arbitrary order).
local abArrivalHookInstalled -- SETTINGS_LOADED hook installed once per session
local abBackSyncInstalled    -- value-changed callbacks installed once per session
local abVerifyScheduled      -- collapses parallel reconciles into one verify pass

local ReconcileActionBarsEnabled  -- forward declaration (mutual recursion below)
local ensureBarSettingsArrivalHook
local installActionBarBackSync

-- Seed any unset enableBarN from the live value, once per profile, so a profile
-- switch fully determines bar visibility instead of leaving unset bars wherever the
-- previous profile left them. Must only run once the settings registry is live.
local function BackfillActionBarEnableState(profile)
    -- rawget/rawset throughout, matching the zero-touch convention in
    -- core/components/base/core.lua, so nothing reads or writes through an
    -- AceDB-materialized defaults table.
    local s = rawget(profile, "actionBarSettings")
    if s and s.__backfilledV1 then return s end

    local seeded = {}
    for barNum = 2, 8 do
        if not s or s[AB_ENABLE_KEYS[barNum]] == nil then
            local setting = getSettingObject(barNum)
            if setting and setting.GetValue then
                local ok, current = pcall(setting.GetValue, setting)
                if ok and current ~= nil then
                    seeded[AB_ENABLE_KEYS[barNum]] = current and true or false
                end
            end
        end
    end

    if not s and not next(seeded) then
        return nil  -- nothing to write; don't materialize a table the pruner would drop
    end

    if not s then
        s = {}
        rawset(profile, "actionBarSettings", s)
    end
    for k, v in pairs(seeded) do
        s[k] = v
    end
    s.__backfilledV1 = true
    Debug("Backfilled actionBarSettings enable state", "seeded=" .. tostring(next(seeded) ~= nil))
    return s
end

-- Re-read the profile and re-assert every bar's enable state. Idempotent; safe to
-- call from any entry point (login, profile switch, preset apply, Edit Mode change).
function ReconcileActionBarsEnabled(reason)
    reason = reason or "unspecified"

    local profile = addon and addon.db and addon.db.profile
    if not profile then return end

    if not addon:IsModuleEnabled("actionBars") then
        Debug("Skipped action bar reconcile: actionBars module disabled", "reason=" .. reason)
        return
    end

    -- Writing these settings shows/hides the secure MultiBar frames, so it is
    -- forbidden in combat. Queue and re-read the profile when combat ends; the
    -- drained call re-checks combat and re-defers if a new fight started.
    if InCombatLockdown and InCombatLockdown() then
        Events.RunOutOfCombat(function()
            ReconcileActionBarsEnabled(reason .. "+PostCombat")
        end, "Profiles:abReconcile")
        Debug("Deferred action bar reconcile until combat ends", "reason=" .. reason)
        return
    end

    if not areBarSettingsReady() then
        ensureBarSettingsArrivalHook()
        Debug("Deferred action bar reconcile: settings registry not ready", "reason=" .. reason)
        return
    end

    installActionBarBackSync()

    local s = BackfillActionBarEnableState(profile)
    if not s then
        Debug("Skipped action bar reconcile: no actionBarSettings", "reason=" .. reason)
        return
    end

    local written = 0
    for barNum = 2, 8 do
        local desired = s[AB_ENABLE_KEYS[barNum]]
        if desired ~= nil then
            if applyBarSettingsAPI(barNum, desired) then
                written = written + 1
            end
        end
    end

    Debug("Reconciled action bars", "reason=" .. reason, "written=" .. written)

    -- Verify late. SetActionBarToggles round-trips the server and GetActionBarToggles
    -- lags behind it (Blizzard keeps its own 10s cache for this reason), so a write
    -- issued right after login can be dropped by ApplyValue's equality check against
    -- stale mirror data. Re-check once and re-write once; never loop.
    if written > 0 and not abVerifyScheduled and C_Timer and C_Timer.After then
        abVerifyScheduled = true
        C_Timer.After(1.5, function()
            abVerifyScheduled = false
            if InCombatLockdown and InCombatLockdown() then return end
            local p = addon and addon.db and addon.db.profile
            local ps = p and rawget(p, "actionBarSettings")
            if not ps then return end
            for barNum = 2, 8 do
                local desired = ps[AB_ENABLE_KEYS[barNum]]
                if desired ~= nil then
                    local setting = getSettingObject(barNum)
                    if setting and setting.GetValue then
                        local ok, current = pcall(setting.GetValue, setting)
                        if ok and current ~= desired then
                            Debug("Action bar verify mismatch; re-writing", "bar=" .. barNum,
                                "want=" .. tostring(desired), "got=" .. tostring(current))
                            applyBarSettingsAPI(barNum, desired)
                        end
                    end
                end
            end
        end)
    end
end

-- The required settings do not exist at OnInitialize. SETTINGS_LOADED fires
-- immediately after Blizzard's registrants run (Blizzard_SettingsRegistrar.lua), and
-- is what Blizzard's own ActionBarController uses to wire up these same seven
-- settings. Note that registration itself does NOT fire a value-changed event, so
-- Settings.CallWhenRegistered is not a usable arrival hook here.
function ensureBarSettingsArrivalHook()
    if abArrivalHookInstalled then return end
    abArrivalHookInstalled = true

    Events.Once("Profiles", "SETTINGS_LOADED", function()
        ReconcileActionBarsEnabled("SettingsLoaded")
    end)
end

-- Mirror changes the user makes in Blizzard's own Options/Edit Mode UI back into the
-- active Scoot profile, so an in-combat fix there sticks instead of being reverted by
-- the next reconcile.
function installActionBarBackSync()
    if abBackSyncInstalled then return end
    if not Settings or not Settings.SetOnValueChangedCallback then return end
    abBackSyncInstalled = true

    for barNum = 2, 8 do
        local bn = barNum
        pcall(Settings.SetOnValueChangedCallback, AB_SETTING_KEYS[bn], function(_, _, value)
            if abWriting then return end  -- our own write, not the user's
            local profile = addon and addon.db and addon.db.profile
            if not profile then return end
            if not addon:IsModuleEnabled("actionBars") then return end

            local s = rawget(profile, "actionBarSettings")
            if not s then
                s = {}
                rawset(profile, "actionBarSettings", s)
            end

            local newValue = value and true or false
            if s[AB_ENABLE_KEYS[bn]] == newValue then return end
            s[AB_ENABLE_KEYS[bn]] = newValue

            Debug("Back-synced action bar from Blizzard UI", "bar=" .. bn,
                "value=" .. tostring(newValue), "profile=" .. tostring(addon.db:GetCurrentProfile()))
        end)
    end

    Debug("Installed action bar back-sync callbacks")
end

-- Expose for the Action Bars renderer toggle and the Edit Mode / world entry hooks in
-- core/init.lua so they reuse the one combat- and readiness-guarded implementation.
addon.ReconcileActionBarsEnabled = ReconcileActionBarsEnabled

-- Expose for Profiles:Initialize (core.lua), which arms the arrival hook before the
-- Blizzard settings objects exist at login.
addon.Profiles._ensureBarSettingsArrivalHook = ensureBarSettingsArrivalHook
