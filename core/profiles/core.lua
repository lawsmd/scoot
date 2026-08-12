-- core.lua - Profile activation, CDM CVar enforcement, and reload sequencing
local addonName, addon = ...

addon.Profiles = addon.Profiles or {}
local Profiles = addon.Profiles

local LEO = LibStub and LibStub("LibEditModeOverride-1.0")

local DEBUG_PREFIX = "|cffa0ff00ScootProfiles|r"

local function Debug(...)
    if not addon or not addon._dbgProfiles then return end
    local messages = {}
    for i = 1, select("#", ...) do
        messages[#messages + 1] = tostring(select(i, ...))
    end
    local msg = table.concat(messages, " ")
    if addon.Print then
        addon:Print(DEBUG_PREFIX .. " " .. msg)
    else
        print(DEBUG_PREFIX, msg)
    end
end

-- Persistent debug log that survives /reload (stored in addon.db.global)
local function LogReload(event, data)
    local global = addon and addon.db and addon.db.global
    if not global then return end
    if not global._profileSwitchLog then global._profileSwitchLog = {} end
    local entry = { t = GetTime and string.format("%.3f", GetTime()) or "?", e = event }
    if data then
        for k, v in pairs(data) do entry[k] = tostring(v) end
    end
    table.insert(global._profileSwitchLog, entry)
    while #global._profileSwitchLog > 50 do table.remove(global._profileSwitchLog, 1) end
end

local function deepCopy(tbl)
    if not tbl then return {} end
    return CopyTable(tbl)
end

local function ensureLayoutsLoaded()
    if not LEO then return false end
    if not (LEO.IsReady and LEO:IsReady()) then
        return false
    end
    if LEO.AreLayoutsLoaded and not LEO:AreLayoutsLoaded() then
        if LEO.LoadLayouts then
            local ok = pcall(LEO.LoadLayouts, LEO)
            if not ok then
                return false
            end
        else
            return false
        end
    end
    return true
end

local layoutTypeLabels = {}
if Enum and Enum.EditModeLayoutType then
    layoutTypeLabels[Enum.EditModeLayoutType.Preset] = "Preset"
    layoutTypeLabels[Enum.EditModeLayoutType.Character] = "Character"
    layoutTypeLabels[Enum.EditModeLayoutType.Account] = "Account"
    layoutTypeLabels[Enum.EditModeLayoutType.Override] = "Override"
end

local function LayoutTypeName(layoutType)
    if not layoutType then return "Unknown" end
    return layoutTypeLabels[layoutType] or ("Type" .. tostring(layoutType))
end

local function ensureEditModeFrame()
    if not EditModeManagerFrame or not EditModeManagerFrame.MakeNewLayout then
        if C_AddOns and C_AddOns.LoadAddOn then
            pcall(C_AddOns.LoadAddOn, "Blizzard_EditMode")
        end
    end
    return EditModeManagerFrame
end

-- prepareManager() REMOVED — calling methods on EditModeManagerFrame from addon context
-- taints ALL registered system frames at once (via UpdateSystems → secureexecuterange).
-- All callers replaced with direct C_EditMode API reads (GetLayouts/SaveLayouts).

-- Apply the profile's CDM override (if explicitly set) to the Blizzard CVar.
-- This is character-scoped in Blizzard, so it is enforced per-profile by setting it
-- when the active Scoot profile changes.
local function ApplyCooldownViewerEnabledForActiveProfile(reason)
    if not addon:IsModuleEnabled("cooldownManager") then return end
    local profile = addon and addon.db and addon.db.profile
    local q = profile and profile.cdmQoL
    local desired = q and q.enableCDM
    if desired == nil then
        return
    end
    local value = (desired and "1") or "0"

    local function applyCVar()
        if C_CVar and C_CVar.SetCVar then
            pcall(C_CVar.SetCVar, "cooldownViewerEnabled", value)
        elseif SetCVar then
            pcall(SetCVar, "cooldownViewerEnabled", value)
        end
    end

    if InCombatLockdown and InCombatLockdown() then
        local f = CreateFrame("Frame")
        f:RegisterEvent("PLAYER_REGEN_ENABLED")
        f:SetScript("OnEvent", function(self)
            self:UnregisterAllEvents()
            applyCVar()
        end)
    else
        applyCVar()
    end

    -- Important: setting the CVar does not reliably hide already-visible CDM frames
    -- until the user toggles Blizzard's checkbox UI. If the profile explicitly disables
    -- CDM, the viewer frames must be proactively hidden so the UI matches the setting
    -- immediately (including right after /reload).
    --
    -- Intentionally does NOT force-show when enabling; Edit Mode + viewer visibility
    -- settings (and Blizzard state) should remain the source of truth for whether a
    -- particular viewer is currently visible.
    if desired == false then
        local function hideViewers()
            local viewers = {
                "EssentialCooldownViewer",
                "UtilityCooldownViewer",
                "BuffIconCooldownViewer",
                "BuffBarCooldownViewer",
            }
            for _, viewerName in ipairs(viewers) do
                local frame = _G and _G[viewerName]
                if frame then
                    if frame.SetShown then
                        pcall(frame.SetShown, frame, false)
                    elseif frame.Hide then
                        pcall(frame.Hide, frame)
                    end
                end
            end
        end

        if InCombatLockdown and InCombatLockdown() then
            -- Avoid touching potentially protected UI during combat; retry after combat ends.
            if C_Timer and C_Timer.After then
                C_Timer.After(0.1, function()
                    if not (InCombatLockdown and InCombatLockdown()) then
                        hideViewers()
                    end
                end)
            end
        else
            hideViewers()
        end
    end

    Debug("Applied cooldownViewerEnabled from profile", tostring(value), reason and ("reason=" .. tostring(reason)) or "")
end

local function ApplyPRDEnabledForActiveProfile(reason)
    if not addon:IsModuleEnabled("prd") then return end
    local profile = addon and addon.db and addon.db.profile
    local s = profile and profile.prdSettings
    local desired = s and s.enablePRD
    if desired == nil then
        return  -- Not explicitly set; don't override CVar
    end
    local value = (desired and "1") or "0"

    local function applyCVar()
        if C_CVar and C_CVar.SetCVar then
            pcall(C_CVar.SetCVar, "nameplateShowSelf", value)
        elseif SetCVar then
            pcall(SetCVar, "nameplateShowSelf", value)
        end
    end

    if InCombatLockdown and InCombatLockdown() then
        local f = CreateFrame("Frame")
        f:RegisterEvent("PLAYER_REGEN_ENABLED")
        f:SetScript("OnEvent", function(self)
            self:UnregisterAllEvents()
            applyCVar()
        end)
    else
        applyCVar()
    end

    -- If disabling, trigger a re-apply so borders/overlays get cleared
    if desired == false then
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function()
                if addon and addon.ApplyStyles then
                    addon:ApplyStyles()
                end
            end)
        end
    end

    Debug("Applied nameplateShowSelf from profile", tostring(value), reason and ("reason=" .. tostring(reason)) or "")
end

local function ApplyDamageMeterEnabledForActiveProfile(reason)
    if not addon:IsModuleEnabled("damageMeter") then return end

    -- V2 active → always disable Blizzard's meter regardless of V1 settings
    if addon:IsModuleEnabled("damageMeter", "damageMeterV2") then
        local function applyV2CVar()
            if C_CVar and C_CVar.SetCVar then
                pcall(C_CVar.SetCVar, "damageMeterEnabled", "0")
            elseif SetCVar then
                pcall(SetCVar, "damageMeterEnabled", "0")
            end
        end
        if InCombatLockdown and InCombatLockdown() then
            local f = CreateFrame("Frame")
            f:RegisterEvent("PLAYER_REGEN_ENABLED")
            f:SetScript("OnEvent", function(self)
                self:UnregisterAllEvents()
                applyV2CVar()
            end)
        else
            applyV2CVar()
        end
        -- Hide Blizzard meter frame
        if not (InCombatLockdown and InCombatLockdown()) then
            local frame = _G and _G["DamageMeter"]
            if frame then
                if frame.SetShown then pcall(frame.SetShown, frame, false)
                elseif frame.Hide then pcall(frame.Hide, frame)
                end
            end
        end
        Debug("Applied damageMeterEnabled=0 for V2", reason and ("reason=" .. tostring(reason)) or "")
        return
    end

    local profile = addon and addon.db and addon.db.profile
    local s = profile and profile.damageMeterSettings
    local desired = s and s.enableDamageMeter
    if desired == nil then
        return  -- Not explicitly set; don't override CVar
    end
    local value = (desired and "1") or "0"

    local function applyCVar()
        if C_CVar and C_CVar.SetCVar then
            pcall(C_CVar.SetCVar, "damageMeterEnabled", value)
        elseif SetCVar then
            pcall(SetCVar, "damageMeterEnabled", value)
        end
    end

    if InCombatLockdown and InCombatLockdown() then
        local f = CreateFrame("Frame")
        f:RegisterEvent("PLAYER_REGEN_ENABLED")
        f:SetScript("OnEvent", function(self)
            self:UnregisterAllEvents()
            applyCVar()
        end)
    else
        applyCVar()
    end

    -- Hide damage meter if disabling (same pattern as CDM)
    if desired == false then
        local function hideDamageMeter()
            local frame = _G and _G["DamageMeter"]
            if frame then
                if frame.SetShown then
                    pcall(frame.SetShown, frame, false)
                elseif frame.Hide then
                    pcall(frame.Hide, frame)
                end
            end
        end

        if InCombatLockdown and InCombatLockdown() then
            if C_Timer and C_Timer.After then
                C_Timer.After(0.1, function()
                    if not (InCombatLockdown and InCombatLockdown()) then
                        hideDamageMeter()
                    end
                end)
            end
        else
            hideDamageMeter()
        end
    end

    Debug("Applied damageMeterEnabled from profile", tostring(value), reason and ("reason=" .. tostring(reason)) or "")
end

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
-- our OnInitialize. Caching a failed lookup would poison every later apply for the
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

-- Set while we are writing a bar setting, so our own back-sync callback can tell
-- our writes apart from the user's. Sound because SettingMixin:TriggerValueChanged
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

-- Reconciler state. One shared frame for combat deferral (the old code created one
-- frame per bar per apply and closed over stale values, so two profile switches in
-- one combat resolved in arbitrary order).
local abCombatFrame          -- lazily created, registered for PLAYER_REGEN_ENABLED
local abReconcilePending     -- reason string queued while in combat
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
    -- core/components/base/core.lua, so we never read or write through an
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
    -- forbidden in combat. Queue and re-read the profile when combat ends.
    if InCombatLockdown and InCombatLockdown() then
        abReconcilePending = reason
        if not abCombatFrame then
            abCombatFrame = CreateFrame("Frame")
            abCombatFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
            abCombatFrame:SetScript("OnEvent", function()
                local queued = abReconcilePending
                abReconcilePending = nil
                if queued then
                    ReconcileActionBarsEnabled(queued .. "+PostCombat")
                end
            end)
        end
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

-- The settings we need do not exist at OnInitialize. SETTINGS_LOADED fires
-- immediately after Blizzard's registrants run (Blizzard_SettingsRegistrar.lua), and
-- is what Blizzard's own ActionBarController uses to wire up these same seven
-- settings. Note that registration itself does NOT fire a value-changed event, so
-- Settings.CallWhenRegistered is not a usable arrival hook here.
function ensureBarSettingsArrivalHook()
    if abArrivalHookInstalled then return end
    abArrivalHookInstalled = true

    local f = CreateFrame("Frame")
    f:RegisterEvent("SETTINGS_LOADED")
    f:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()
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


-- Raid frames: Blizzard renders raid-frame debuffs as private auras (forbidden,
-- secure environment) and enlarges boss/role-specific ones when its
-- "Display Larger Role-Specific Auras" option is on. We can't restyle those
-- borders, but we can flip the CVar that drives them. Setting the CVar fires
-- CompactUnitFrameProfiles' CVar callback, which reapplies to all raid +
-- raid-style party frames automatically (no manual rebuild).
local function ApplyRaidLargerRoleDebuffsForActiveProfile(reason)
    local profile = addon and addon.db and addon.db.profile
    local gf = profile and profile.groupFrames
    local s = gf and gf.raid
    local desired = s and s.enlargeRoleDebuffs
    if desired == nil then
        return  -- Zero-Touch: never override until the user configures the toggle
    end
    local value = (desired and "1") or "0"

    local function applyCVar()
        if C_CVar and C_CVar.SetCVar then
            pcall(C_CVar.SetCVar, "raidFramesDisplayLargerRoleSpecificDebuffs", value)
        elseif SetCVar then
            pcall(SetCVar, "raidFramesDisplayLargerRoleSpecificDebuffs", value)
        end
    end

    if InCombatLockdown and InCombatLockdown() then
        local f = CreateFrame("Frame")
        f:RegisterEvent("PLAYER_REGEN_ENABLED")
        f:SetScript("OnEvent", function(self)
            self:UnregisterAllEvents()
            applyCVar()
        end)
    else
        applyCVar()
    end

    Debug("Applied raidFramesDisplayLargerRoleSpecificDebuffs from profile", tostring(value), reason and ("reason=" .. tostring(reason)) or "")
end

-- Expose for the Raid Frames renderer toggle so it reuses the one combat-guarded implementation.
addon.ApplyRaidLargerRoleDebuffs = ApplyRaidLargerRoleDebuffsForActiveProfile

-- Group frames: patch 12.1 added the raidFramesDisplayBuffs CVar, an engine-level switch
-- that removes every buff icon from raid and raid-style party frames (the frames read it
-- through CompactUnitFrameProfiles' CVar callback, which reapplies frame setup on its own).
-- Blizzard wired the CVar but exposed no options UI for it; Scoot's Aura Tracking page does.
local function ApplyGroupBuffIconsHiddenForActiveProfile(reason)
    local profile = addon and addon.db and addon.db.profile
    local gf = profile and profile.groupFrames
    local at = gf and gf.auraTracking

    -- One-shot conversion from the retired replacementStyle overlay setting. Runs here as
    -- well as in ensureAuraTrackingDB (ui/v2/groupframes/Helpers.lua) because this function
    -- fires at login before any settings UI code touches the profile. Both copies are
    -- idempotent; keep them in sync.
    if at and at.replacementStyle ~= nil then
        if at.replacementStyle ~= "none" and at.hideBlizzardBuffIcons == nil then
            at.hideBlizzardBuffIcons = true
        end
        at.replacementStyle = nil
    end

    local desired = at and at.hideBlizzardBuffIcons
    if desired == nil then
        return  -- Zero-Touch: never override until the user configures the toggle
    end
    -- Inverted polarity: the toggle means "hide", the CVar means "display".
    local value = (desired and "0") or "1"

    local function applyCVar()
        if C_CVar and C_CVar.SetCVar then
            pcall(C_CVar.SetCVar, "raidFramesDisplayBuffs", value)
        elseif SetCVar then
            pcall(SetCVar, "raidFramesDisplayBuffs", value)
        end
    end

    if InCombatLockdown and InCombatLockdown() then
        local f = CreateFrame("Frame")
        f:RegisterEvent("PLAYER_REGEN_ENABLED")
        f:SetScript("OnEvent", function(self)
            self:UnregisterAllEvents()
            applyCVar()
        end)
    else
        applyCVar()
    end

    Debug("Applied raidFramesDisplayBuffs from profile", tostring(value), reason and ("reason=" .. tostring(reason)) or "")
end

-- Expose for the Aura Tracking renderer toggle so it reuses the one combat-guarded implementation.
addon.ApplyGroupBuffIconsHidden = ApplyGroupBuffIconsHiddenForActiveProfile

-- Expose for the Action Bars renderer toggle and the Edit Mode / world entry hooks in
-- core/init.lua so they reuse the one combat- and readiness-guarded implementation.
addon.ReconcileActionBarsEnabled = ReconcileActionBarsEnabled

local function getLayouts()
    if not C_EditMode or not C_EditMode.GetLayouts then return nil end
    return C_EditMode.GetLayouts()
end

function Profiles:FindLayoutIndex(layoutName)
    local data = getLayouts()
    if not data or not data.layouts then return nil end
    for index, layout in ipairs(data.layouts) do
        if layout.layoutName == layoutName then
            return index, layout
        end
    end
end

function Profiles:RestoreDropdownSelection(dropdown, key, displayText)
    if not dropdown then return end
    UIDropDownMenu_SetSelectedValue(dropdown, key)
    UIDropDownMenu_SetText(dropdown, displayText or key or "Select a layout")
end

local function addLayoutToCache(self, layoutName)
    if not layoutName then return end
    self._layoutLookup = self._layoutLookup or {}
    self._layoutLookup[layoutName] = true
    self._sortedEditableLayouts = self._sortedEditableLayouts or {}
    for _, existing in ipairs(self._sortedEditableLayouts) do
        if existing == layoutName then
            return
        end
    end
    table.insert(self._sortedEditableLayouts, layoutName)
    table.sort(self._sortedEditableLayouts, function(a, b)
        return tostring(a) < tostring(b)
    end)
end

local function getCurrentSpecID()
    if type(GetSpecialization) ~= "function" then
        return nil
    end
    local specIndex = GetSpecialization()
    if not specIndex then
        return nil
    end
    if type(GetSpecializationInfo) ~= "function" then
        return nil
    end
    local specID = select(1, GetSpecializationInfo(specIndex))
    return specID
end

-- Records the player's current spec to distinguish true mid-session spec changes
-- from incidental events (like PLAYER_ENTERING_WORLD during loading screens).
function Profiles:RecordCurrentSpec()
    local specID = getCurrentSpecID()
    if not specID then
        return
    end
    self._lastKnownSpecID = specID
end

local function buildDefaultProfile()
    -- Zero‑Touch policy: new profiles should start empty so Scoot does not
    -- implicitly "force defaults" into SavedVariables. AceDB defaults still exist
    -- via metatable fallback when reading unset keys.
    return {}
end

local function isCombatLocked()
    return InCombatLockdown and InCombatLockdown()
end

local function normalizeName(name)
    if type(name) ~= "string" then return nil end
    name = strtrim(name)
    if name == "" then return nil end
    return name
end

local function notifyUI()
    -- Deferred re-render of the Manage Profiles page after mutations (copy, rename, delete, create).
    -- Delay ensures postMutationSync has completed. Visibility guards prevent spurious re-renders.
    if not (C_Timer and C_Timer.After) then return end
    C_Timer.After(0.4, function()
        local manage = addon and addon.UI and addon.UI.Settings
            and addon.UI.Settings.Profiles and addon.UI.Settings.Profiles.Manage
        if not manage or not manage._state or not manage._state.refreshCallback then return end
        local panel = addon.UI and addon.UI.SettingsPanel
        if not panel or panel._currentCategoryKey ~= "profilesManage" then return end
        if not (panel.frame and panel.frame:IsShown()) then return end
        manage._state.refreshCallback()
    end)
end

-- Multi-pass sync after layout mutations to avoid stale lists
local function postMutationSync(self, reason)
    if LEO and LEO.LoadLayouts then pcall(LEO.LoadLayouts, LEO) end
    self._postCopySuppressUntil = GetTime() + 0.3
    if C_Timer and C_Timer.After then
        C_Timer.After(0.05, function()
            if LEO and LEO.LoadLayouts then pcall(LEO.LoadLayouts, LEO) end
            if self and self.RefreshFromEditMode and ensureLayoutsLoaded() then
                self:RefreshFromEditMode(reason or "PostMutation")
            else
                self:RequestSync(reason or "PostMutation")
            end
        end)
        C_Timer.After(0.2, function()
            if LEO and LEO.LoadLayouts then pcall(LEO.LoadLayouts, LEO) end
            if self and self.RefreshFromEditMode and ensureLayoutsLoaded() then
                self:RefreshFromEditMode((reason or "PostMutation") .. "+retry")
            end
        end)
        -- After suppression window, try to apply any pending layout to EM
        C_Timer.After(0.35, function()
            if LEO and LEO.LoadLayouts then pcall(LEO.LoadLayouts, LEO) end
            if self and self.RefreshFromEditMode and ensureLayoutsLoaded() then
                self:RefreshFromEditMode((reason or "PostMutation") .. "+final")
            end
        end)
    end
end

-- clearDropdownTaint() REMOVED — dead code (defined but never called).

-- Copy all Edit Mode system settings (including anchors) from one layout to another
local function copyLayoutSettingsByName(sourceName, destName)
    if not sourceName or not destName then return false end
    if not C_EditMode or not C_EditMode.GetLayouts or not C_EditMode.SaveLayouts then return false end
    local li = C_EditMode.GetLayouts()
    if not li or not li.layouts then return false end
    local src, dst, dstIndex
    for idx, layout in ipairs(li.layouts) do
        if layout.layoutName == sourceName then src = layout end
        if layout.layoutName == destName then dst = layout; dstIndex = idx end
    end
    -- If source is a preset, fall back to preset manager
    if not src and EditModePresetLayoutManager and EditModePresetLayoutManager.GetCopyOfPresetLayouts then
        for _, layout in ipairs(EditModePresetLayoutManager:GetCopyOfPresetLayouts() or {}) do
            if layout.layoutName == sourceName then src = layout break end
        end
    end
    if not (src and dst and dst.systems and src.systems) then return false end
    local function indexSystems(layout)
        local map = {}
        for _, sys in ipairs(layout.systems) do
            map[(sys.system or 0) .. ":" .. (sys.systemIndex or 0)] = sys
        end
        return map
    end
    local srcMap = indexSystems(src)
    for _, dsys in ipairs(dst.systems) do
        local key = (dsys.system or 0) .. ":" .. (dsys.systemIndex or 0)
        local ssys = srcMap[key]
        if ssys then
            -- Copy anchor and default-position flags
            if ssys.anchorInfo and dsys.anchorInfo then
                dsys.isInDefaultPosition = not not ssys.isInDefaultPosition
                local sa, da = ssys.anchorInfo, dsys.anchorInfo
                da.point = sa.point; da.relativePoint = sa.relativePoint
                da.offsetX = sa.offsetX; da.offsetY = sa.offsetY
                da.relativeTo = sa.relativeTo
            end
            -- Copy individual setting values by numeric id
            local svalById = {}
            if ssys.settings then
                for _, it in ipairs(ssys.settings) do
                    svalById[it.setting] = it.value
                end
            end
            if dsys.settings then
                for _, it in ipairs(dsys.settings) do
                    local v = svalById[it.setting]
                    if v ~= nil then it.value = v end
                end
            end
        end
    end
    -- Ensure the destination is the active layout so the client reflects changes
    if li.activeLayout and li.layouts[li.activeLayout] and li.layouts[li.activeLayout].layoutName ~= destName then
        for idx, layout in ipairs(li.layouts) do
            if layout.layoutName == destName then li.activeLayout = idx break end
        end
    end
    C_EditMode.SaveLayouts(li)
    if LEO and LEO.LoadLayouts then pcall(LEO.LoadLayouts, LEO) end
    return true
end

-- Apply the active profile's Edit Mode-backed settings for a single component
-- directly through the library, then persist with SaveOnly (no UI panel churn).
local function applyComponentEditModeViaLibrary(component)
    if not component or not component.frameName then return end
    local frame = _G[component.frameName]
    if not frame then return end
    if not LEO or not (LEO.IsReady and LEO:IsReady()) then return end
    if LEO.AreLayoutsLoaded and not LEO:AreLayoutsLoaded() then if LEO.LoadLayouts then pcall(LEO.LoadLayouts, LEO) end end

    local EM = _G.Enum and _G.Enum.EditModeCooldownViewerSetting
    local function set(settingEnumOrId, value)
        if not settingEnumOrId or value == nil then return end
        pcall(LEO.SetFrameSetting, LEO, frame, settingEnumOrId, value)
    end

    local db = component.db or {}

    -- Position (anchor to CENTER with offsets from DB)
    do
        local x = tonumber(db.positionX or (component.settings.positionX and component.settings.positionX.default) or 0) or 0
        local y = tonumber(db.positionY or (component.settings.positionY and component.settings.positionY.default) or 0) or 0
        if LEO.ReanchorFrame and _G.UIParent then
            pcall(LEO.ReanchorFrame, LEO, frame, "CENTER", _G.UIParent, "CENTER", x, y)
        end
    end

    -- Orientation
    if component.settings.orientation then
        local v = (db.orientation or component.settings.orientation.default or "H")
        local emv = (v == "H") and 0 or 1
        set((EM and EM.Orientation) or 0, emv)
        -- UpdateSystemSetting* calls removed to prevent taint.
        -- Visual updates now come from the deferred SetActiveLayout() in SaveOnly().
    end

    -- Columns/Rows (IconLimit)
    if component.settings.columns then
        local v = tonumber(db.columns or component.settings.columns.default or 12) or 12
        set((EM and EM.IconLimit) or 1, v)
    end

    -- Direction (IconDirection)
    if component.settings.direction then
        local dir = tostring(db.direction or component.settings.direction.default or "right")
        local orientation = tostring(db.orientation or component.settings.orientation and component.settings.orientation.default or "H")
        local emv
        if orientation == "H" then emv = (dir == "right") and 1 or 0 else emv = (dir == "up") and 1 or 0 end
        set((EM and EM.IconDirection) or 2, emv)
    end

    -- Icon Padding
    if component.settings.iconPadding then
        local v = tonumber(db.iconPadding or component.settings.iconPadding.default or 2) or 2
        set((EM and EM.IconPadding) or 4, v)
    end

    -- Icon Size (Scale) - raw 50..200 snapped to 10s
    if component.settings.iconSize then
        local v = tonumber(db.iconSize or component.settings.iconSize.default or 100) or 100
        if v < 50 then v = 50 elseif v > 200 then v = 200 end
        v = math.floor(v / 10 + 0.5) * 10
        set((EM and EM.IconSize) or 3, v)
    end

    -- Tracked Bars: Display Mode (BarContent) 0=both,1=icon,2=name
    if component.id == "trackedBars" and component.settings.displayMode and _G.Enum and _G.Enum.EditModeCooldownViewerSetting then
        local v = tostring(db.displayMode or component.settings.displayMode.default or "both")
        local emv = (v == "icon") and 1 or ((v == "name") and 2 or 0)
        set(_G.Enum.EditModeCooldownViewerSetting.BarContent, emv)
    end

    -- Opacity 50..100
    if component.settings.opacity then
        local v = tonumber(db.opacity or component.settings.opacity.default or 100) or 100
        if v < 50 then v = 50 elseif v > 100 then v = 100 end
        set((EM and EM.Opacity) or 5, v)
    end

    -- Visibility dropdown (0 always, 1 combat, 2 hidden)
    if component.settings.visibilityMode then
        local mode = tostring(db.visibilityMode or component.settings.visibilityMode.default or "always")
        local emv = (mode == "combat") and 1 or ((mode == "never") and 2 or 0)
        if EM and EM.VisibleSetting then set(EM.VisibleSetting, emv) else set(0, emv) end
    end

    -- Checkboxes (timers/tooltips/hide-inactive) if present on component
    if component.settings.showTimer and EM and EM.ShowTimer then
        local v = (db.showTimer == nil and component.settings.showTimer.default) or db.showTimer
        set(EM.ShowTimer, v and 1 or 0)
    end
    if component.settings.showTooltip and EM and EM.ShowTooltips then
        local v = (db.showTooltip == nil and component.settings.showTooltip.default) or db.showTooltip
        set(EM.ShowTooltips, v and 1 or 0)
    end
    if component.settings.hideWhenInactive and EM then
        local v = (db.hideWhenInactive == nil and component.settings.hideWhenInactive.default) or db.hideWhenInactive
        -- No stable enum seen earlier; best-effort setting via library
        if frame.settingDisplayInfo and frame.settingDisplayInfo.hideWhenInactive then
            set(frame.settingDisplayInfo.hideWhenInactive, v and 1 or 0)
        end
    end

    -- NOTE: UpdateLayout() calls removed to prevent taint.
    -- The deferred SetActiveLayout() in SaveOnly() triggers Blizzard's clean rebuild.
end

local function applyAllComponentsEditModeViaLibrary()
    if not addon or not addon.Components then return end
    for _, component in pairs(addon.Components) do
        applyComponentEditModeViaLibrary(component)
    end
    if LEO and LEO.SaveOnly then pcall(LEO.SaveOnly, LEO) end
end

-- Short suppression window after copy/clone to avoid Edit Mode writes while opening the EM UI
function Profiles:IsPostCopySuppressed()
    local untilTs = self and self._postCopySuppressUntil
    if not untilTs then return false end
    local now = GetTime and GetTime() or 0
    return now > 0 and now < untilTs
end

local function buildPendingActivation(layoutName, meta)
    local p = { layoutName = layoutName }
    if type(meta) == "table" then
        for k, v in pairs(meta) do
            if k ~= "layoutName" then
                p[k] = v
            end
        end
    end
    return p
end

local function persistAceProfileKeyForChar(db, layoutName)
    if not (db and layoutName) then return end
    local sv = rawget(db, "sv")
    local charKey = db.keys and db.keys.char
    if sv and sv.profileKeys and charKey then
        sv.profileKeys[charKey] = layoutName
    end
end

local function persistEditModeActiveLayoutByName(layoutName)
    if not layoutName then return end
    if not (C_EditMode and C_EditMode.GetLayouts and C_EditMode.SaveLayouts) then return end
    local li = C_EditMode.GetLayouts()
    if not (li and li.layouts) then return end
    for idx, layout in ipairs(li.layouts) do
        if layout and layout.layoutName == layoutName then
            li.activeLayout = idx
            break
        end
    end
    pcall(C_EditMode.SaveLayouts, li)
end

function Profiles:RequestReloadToProfile(layoutName, meta)
    -- IMPORTANT:
    -- ReloadUI() is a protected action and is not safe from arbitrary event handlers
    -- (e.g. spec-change, edit mode callbacks). Calling it directly can produce:
    --   [ADDON_ACTION_BLOCKED] AddOn 'Scoot' tried to call the protected function 'Reload()'.
    --
    -- All reloads MUST be initiated from a hardware event (typically a click).
    -- Therefore this API now delegates to PromptReloadToProfile().
    if not (self.db and self.db.global) then
        return false
    end
    if InCombatLockdown and InCombatLockdown() then
        -- Queue a safe prompt for when combat ends (handled by init.lua regen handler or callers).
        self._pendingReloadToProfile = { layoutName = layoutName, meta = meta }
        return true
    end
    return self:PromptReloadToProfile(layoutName, meta)
end

function Profiles:PromptReloadToProfile(layoutName, meta)
    if not (self.db and self.db.global) then
        return false
    end
    if not addon or not addon.Dialogs or not addon.Dialogs.Show then
        return false
    end
    -- Stash pending activation now; the actual ReloadUI() must come from a hardware event.
    self.db.global.pendingProfileActivation = buildPendingActivation(layoutName, meta)
    -- Choose appropriate dialog based on reason
    local dialogName = "SCOOT_PROFILE_RELOAD"
    if meta and meta.reason == "SpecChanged" then
        dialogName = "SCOOT_SPEC_PROFILE_RELOAD"
    end
    addon.Dialogs:Show(dialogName, {
        data = { layoutName = layoutName },
        onAccept = function()
            -- Persist selection right before reloading (hardware-event-safe click).
            -- Do this here so Cancel doesn't accidentally make the choice "stick" for next reload.
            if addon and addon.db then
                persistAceProfileKeyForChar(addon.db, layoutName)
            end
            LogReload("onAccept", { target = layoutName })
            persistEditModeActiveLayoutByName(layoutName)
            ReloadUI()
        end,
        onCancel = function()
            -- Abandon: clear pending activation to avoid a surprise-reload on next load.
            if addon and addon.db and addon.db.global then
                addon.db.global.pendingProfileActivation = nil
            end
        end,
    })
    return true
end

function Profiles:DebugDumpLayouts(context)
    if not addon or not addon._dbgProfiles then return end
    if not C_EditMode or not C_EditMode.GetLayouts then return end
    local layoutData = C_EditMode.GetLayouts()
    if not layoutData or not layoutData.layouts then return end

    local lines = {}
    for index, layout in ipairs(layoutData.layouts) do
        local name = layout.layoutName or ("<unnamed " .. tostring(index) .. ">")
        local lType = LayoutTypeName(layout.layoutType)
        local modifier = layout.isPreset and "preset" or (layout.layoutType == Enum.EditModeLayoutType.Preset and "preset" or "custom")
        local dirty = layout.isModified and "modified" or "clean"
        lines[#lines + 1] = string.format("[%d] %s (%s, %s, %s)", index, name, lType, modifier, dirty)
    end

    local activeIndex = layoutData.activeLayout
    local activeLayout = layoutData.layouts[activeIndex]
    if activeLayout then
        Debug(string.format("Layouts(%s): active index=%d name=%s type=%s %s", context or "?", activeIndex or -1, tostring(activeLayout.layoutName), LayoutTypeName(activeLayout.layoutType), activeLayout.isModified and "modified" or "clean"))
    else
        Debug(string.format("Layouts(%s): active index=%s (missing entry)", context or "?", tostring(activeIndex)))
    end
    Debug("Layouts detail:", table.concat(lines, " | "))
end

function Profiles:Initialize()
    if self._initialized then
        return
    end

    if not addon or not addon.db then
        return
    end

    self.db = addon.db
    self._knownLayouts = {}
    self._layoutLookup = {}
    self._presetLookup = {}
    self._profileTemplate = buildDefaultProfile()
    self._pendingActiveLayout = nil
    self._pendingRefreshReason = "Initialize"
    self._lastPendingApply = 0
    self._lastRequestedLayout = nil
    self._pendingSpecReload = nil
    self._lastKnownSpecID = nil
    self._reloadActivationLock = nil
    self._reloadActivationLockUntil = nil
    self._specChangeLock = nil
    self._specChangeLockUntil = nil
    self._initialized = true
    Debug("Initialize")

    if self.db.RegisterCallback then
        self.db.RegisterCallback(self, "OnProfileChanged", "OnProfileChanged")
        self.db.RegisterCallback(self, "OnProfileCopied", "OnProfileCopied")
        self.db.RegisterCallback(self, "OnProfileReset", "OnProfileReset")
        self.db.RegisterCallback(self, "OnProfileDeleted", "OnProfileDeleted")
        self.db.RegisterCallback(self, "OnNewProfile", "OnNewProfile")
    end

    -- Consume pending profile activation as early as possible (immediately after DB exists).
    -- Ensures that the very first post-reload session starts on the new profile/layout
    -- before any styling passes run, preventing "sticky" old-profile visuals.
    LogReload("Init:start", { aceProfile = self.db:GetCurrentProfile(), pending = self.db.global and self.db.global.pendingProfileActivation and self.db.global.pendingProfileActivation.layoutName })
    do
        local global = self.db and self.db.global
        local p = global and global.pendingProfileActivation
        if p and p.layoutName then
            local pendingCopy = p
            -- Switch immediately; if Edit Mode layouts aren't ready yet, SwitchToProfile will
            -- still set the AceDB profile and queue the layout apply for when layouts load.
            self:SwitchToProfile(p.layoutName, { reason = "PendingProfileActivation", force = true })
            global.pendingProfileActivation = nil
            -- Prevent RefreshFromEditMode from overriding the profile while LEO cache may be stale
            self._reloadActivationLock = p.layoutName
            self._reloadActivationLockUntil = (GetTime and GetTime() or 0) + 3
            LogReload("Init:afterSwitch", { aceProfile = self.db:GetCurrentProfile(), pendingActive = self._pendingActiveLayout, lock = p.layoutName })
            -- Note: no chat message is printed for spec-triggered reloads.
        end
    end

    -- Ensure CDM enable/disable is applied for the active profile on load.
    ApplyCooldownViewerEnabledForActiveProfile("Initialize")
    ApplyPRDEnabledForActiveProfile("Initialize")
    ApplyDamageMeterEnabledForActiveProfile("Initialize")
    -- Bar enable settings do not exist yet at Initialize (ADDON_LOADED); Blizzard
    -- registers them only after VARIABLES_LOADED + PLAYER_ENTERING_WORLD. Arm the
    -- SETTINGS_LOADED hook unconditionally -- it is what actually applies the profile
    -- on login. The call below is a harmless no-op until then.
    ensureBarSettingsArrivalHook()
    ReconcileActionBarsEnabled("Initialize")
    ApplyRaidLargerRoleDebuffsForActiveProfile("Initialize")
    ApplyGroupBuffIconsHiddenForActiveProfile("Initialize")
    if addon and addon.Chat and addon.Chat.ApplyFromProfile then
        addon.Chat:ApplyFromProfile("Profiles:Initialize")
    end

    self:RequestSync("Initialize")
end

function Profiles:OnNewProfile(_, profileKey)
    if not profileKey then
        return
    end
    self:EnsureProfileExists(profileKey)
end

function Profiles:OnProfileChanged(_, _, newProfileKey)
    if self._suppressProfileCallback then
        return
    end
    addon:LinkComponentsToDB()
    addon:ApplyStyles()
    ApplyCooldownViewerEnabledForActiveProfile("OnProfileChanged")
    ApplyPRDEnabledForActiveProfile("OnProfileChanged")
    ApplyDamageMeterEnabledForActiveProfile("OnProfileChanged")
    ReconcileActionBarsEnabled("OnProfileChanged")
    ApplyRaidLargerRoleDebuffsForActiveProfile("OnProfileChanged")
    ApplyGroupBuffIconsHiddenForActiveProfile("OnProfileChanged")
    if addon and addon.Chat and addon.Chat.ApplyFromProfile then
        addon.Chat:ApplyFromProfile("Profiles:OnProfileChanged")
    end
    self._lastActiveLayout = newProfileKey
    self:RequestSync("ProfileChanged")
end

function Profiles:OnProfileCopied(_, _, sourceKey)
    addon:LinkComponentsToDB()
    addon:ApplyStyles()
    ApplyCooldownViewerEnabledForActiveProfile("OnProfileCopied")
    ApplyPRDEnabledForActiveProfile("OnProfileCopied")
    ApplyDamageMeterEnabledForActiveProfile("OnProfileCopied")
    ReconcileActionBarsEnabled("OnProfileCopied")
    ApplyRaidLargerRoleDebuffsForActiveProfile("OnProfileCopied")
    ApplyGroupBuffIconsHiddenForActiveProfile("OnProfileCopied")
    if addon and addon.Chat and addon.Chat.ApplyFromProfile then
        addon.Chat:ApplyFromProfile("Profiles:OnProfileCopied")
    end
    self:RequestSync("ProfileCopied")
end

function Profiles:OnProfileReset()
    addon:LinkComponentsToDB()
    addon:ApplyStyles()
    ApplyCooldownViewerEnabledForActiveProfile("OnProfileReset")
    ApplyPRDEnabledForActiveProfile("OnProfileReset")
    ApplyDamageMeterEnabledForActiveProfile("OnProfileReset")
    ReconcileActionBarsEnabled("OnProfileReset")
    ApplyRaidLargerRoleDebuffsForActiveProfile("OnProfileReset")
    ApplyGroupBuffIconsHiddenForActiveProfile("OnProfileReset")
    if addon and addon.Chat and addon.Chat.ApplyFromProfile then
        addon.Chat:ApplyFromProfile("Profiles:OnProfileReset")
    end
    self:RequestSync("ProfileReset")
end

function Profiles:OnProfileDeleted(_, _, profileKey)
    if profileKey and self._layoutLookup then
        self._layoutLookup[profileKey] = nil
    end
    self:RequestSync("ProfileDeleted")
end

function Profiles:IsReady()
    return self._initialized and ensureLayoutsLoaded()
end

function Profiles:RequestSync(reason)
    if ensureLayoutsLoaded() then
        self:RefreshFromEditMode(reason or "RequestSync")
        self._pendingRefreshReason = nil
        return
    end
    self._pendingRefreshReason = reason or self._pendingRefreshReason or "RequestSync"
end

function Profiles:TryPendingSync()
    if self._pendingRefreshReason and ensureLayoutsLoaded() then
        local reason = self._pendingRefreshReason
        self._pendingRefreshReason = nil
        self:RefreshFromEditMode(reason or "PendingSync")
    end
end

function Profiles:GetAvailableLayouts()
    local editable = {}
    local presets = {}
    for _, name in ipairs(self._sortedEditableLayouts or {}) do
        table.insert(editable, name)
    end
    for _, name in ipairs(self._sortedPresetLayouts or {}) do
        table.insert(presets, name)
    end
    return editable, presets
end

function Profiles:GetLayoutMenuEntries()
    local entries = {}
    local editable, presets = self:GetAvailableLayouts()

    for _, name in ipairs(editable) do
        table.insert(entries, {
            key = name,
            text = name,
            preset = false,
        })
    end

    for _, name in ipairs(presets) do
        table.insert(entries, {
            key = name,
            text = string.format("%s (Preset)", name),
            preset = true,
        })
    end

    return entries
end

function Profiles:IsPreset(profileKey)
    return self._presetLookup[profileKey] or false
end

function Profiles:EnsureProfileExists(profileKey, opts)
    if not profileKey or not self.db or not self.db.profiles then
        return
    end
    if self.db.profiles[profileKey] then
        if opts and opts.preset then
            self.db.profiles[profileKey].__preset = true
        end
        Debug("EnsureProfileExists reuse", profileKey, opts and opts.preset and "(preset)" or "")
        return
    end

    local template
    if opts and opts.copyFrom and self.db.profiles[opts.copyFrom] then
        template = deepCopy(self.db.profiles[opts.copyFrom])
    else
        template = deepCopy(self._profileTemplate)
    end

    if opts and opts.preset then
        template.__preset = true
    end

    self.db.profiles[profileKey] = template
    Debug("EnsureProfileExists created", profileKey, opts and opts.preset and "(preset)" or "", opts and opts.copyFrom and ("copy=" .. tostring(opts.copyFrom)) or "")
end

function Profiles:_setActiveProfile(profileKey, opts)
    if not profileKey or not self.db then
        return
    end
    opts = opts or {}
    local current = self.db:GetCurrentProfile()
    Debug("_setActiveProfile", profileKey, "current=" .. tostring(current), opts.skipLayout and "[skipLayout]" or "", opts.force and "[force]" or "")
    LogReload("setActive", { target = profileKey, current = current, skipLayout = opts.skipLayout })

    self:EnsureProfileExists(profileKey, { preset = self:IsPreset(profileKey) })

    -- Suppress SCT font change popup during profile switches
    addon._profileSwitchInProgress = true

    if current ~= profileKey or opts.force then
        self._suppressProfileCallback = true
        self.db:SetProfile(profileKey)
        self._suppressProfileCallback = false
    else
    end

    -- If switching to a truly empty/Zero‑Touch profile without reloading, clear
    -- frame-level enforcement flags so old-profile hooks stop forcing hidden states.
    do
        local profile = addon and addon.db and addon.db.profile
        local unitFrames = profile and rawget(profile, "unitFrames") or nil
        local components = profile and rawget(profile, "components") or nil
        local hasUF = type(unitFrames) == "table" and next(unitFrames) ~= nil
        local hasComponents = type(components) == "table" and next(components) ~= nil
        if (not hasUF) and (not hasComponents) and addon and addon.ClearFrameLevelState then
            addon:ClearFrameLevelState()
        end
    end

    addon:LinkComponentsToDB()
    addon:ApplyStyles()
    ApplyCooldownViewerEnabledForActiveProfile("_setActiveProfile")
    ApplyPRDEnabledForActiveProfile("_setActiveProfile")
    ApplyDamageMeterEnabledForActiveProfile("_setActiveProfile")
    ReconcileActionBarsEnabled("_setActiveProfile")
    ApplyRaidLargerRoleDebuffsForActiveProfile("_setActiveProfile")
    ApplyGroupBuffIconsHiddenForActiveProfile("_setActiveProfile")
    if addon and addon.Chat and addon.Chat.ApplyFromProfile then
        addon.Chat:ApplyFromProfile("Profiles:_setActiveProfile")
    end

    -- Clear the suppression flag after profile switch completes
    addon._profileSwitchInProgress = false

    self._lastRequestedLayout = profileKey

    if not opts.skipLayout and ensureLayoutsLoaded() and self._layoutLookup[profileKey] then
        -- Suppress EM writes during the brief post-copy window to avoid blocked-action warnings
		if self:IsPostCopySuppressed() then
			self._pendingActiveLayout = profileKey
			Debug("_setActiveProfile suppressed EM write; pending set", profileKey)
			return
		end
		-- Ensure library state is current before switching layouts
		if LEO and LEO.LoadLayouts then pcall(LEO.LoadLayouts, LEO) end
		local names = (LEO and LEO.GetEditableLayoutNames and LEO:GetEditableLayoutNames()) or {}
		local found = false
		for _, n in ipairs(names) do if n == profileKey then found = true break end end
		if not found then
			self._pendingActiveLayout = profileKey
			Debug("Library missing target layout; deferring EM apply", profileKey)
			return
		end
		local active = LEO:GetActiveLayout()
        if active ~= profileKey then
            self._pendingActiveLayout = profileKey
            LEO:SetActiveLayout(profileKey)
            if addon.EditMode and addon.EditMode.SaveOnly then
                addon.EditMode.SaveOnly()
            end
            Debug("_setActiveProfile queued layout apply", profileKey, "previousActive=" .. tostring(active))
        else
            self._pendingActiveLayout = nil
            Debug("_setActiveProfile layout already active", profileKey)
        end
    end

    if opts.skipLayout and not self._pendingActiveLayout
       and self._layoutLookup and not next(self._layoutLookup) then
        self._pendingActiveLayout = profileKey
        Debug("_setActiveProfile safety-net pending set (empty layout lookup)", profileKey)
    end

    if addon and addon._dbgProfiles and C_Timer and C_Timer.After then
        local targetName = profileKey
        C_Timer.After(0.2, function()
            if addon and addon._dbgProfiles and LEO and LEO.GetActiveLayout then
                local nowActive = LEO:GetActiveLayout()
                Debug("Active layout after switch", "target=" .. tostring(targetName), "current=" .. tostring(nowActive))
            end
        end)
    end

    self._lastActiveLayout = profileKey
end

function Profiles:SwitchToProfile(profileKey, opts)
    if not profileKey then
        return
    end
    opts = opts or {}
    Debug("SwitchToProfile", profileKey, opts.reason and ("reason=" .. tostring(opts.reason)) or "", opts.skipLayout and "[skipLayout]" or "")

    -- Avoid reload loops / unnecessary reloads:
    -- - PendingProfileActivation is consumed on load; the switch must happen immediately without reloading.
    -- - PresetActivationOnLoad similarly must not trigger another reload.
    local skipReload = opts.skipReload
        or opts.reason == "PendingProfileActivation"
        or opts.reason == "PresetActivationOnLoad"
        or opts.reason == "Initialize"

    -- If this is a genuine switch (different profile) and not in a safe on-load path,
    -- force a reload so Blizzard can reinitialize baselines correctly.
    if not skipReload and self.db and self.db.GetCurrentProfile then
        local current = self.db:GetCurrentProfile()
        if current ~= profileKey then
            if isCombatLocked() then
                if addon and addon.Print then addon:Print("Cannot switch profiles during combat.") end
                return
            end
            -- Carry a small amount of metadata for debugging/UX on next load
            local pendingMeta = opts.pendingMeta or { reason = opts.reason }
            -- ReloadUI() is protected unless triggered by a hardware event (e.g. a click).
            -- SwitchToProfile can be reached from non-hardware events, so a prompt is needed.
            self:PromptReloadToProfile(profileKey, pendingMeta)
            return
        end
    end

    if not ensureLayoutsLoaded() then
        self:EnsureProfileExists(profileKey)
        self.db:SetProfile(profileKey)
        addon:LinkComponentsToDB()
        addon:ApplyStyles()
        self._pendingActiveLayout = profileKey
        self._pendingRefreshReason = "DeferredSwitch"
        Debug("SwitchToProfile deferred pending sync", profileKey)
        return
    end
    if not self._layoutLookup[profileKey] then
        -- Allow switching to existing AceDB profile even if layout is missing,
        -- but do not try to adjust Edit Mode.
        opts.skipLayout = true
        self._pendingActiveLayout = profileKey
        Debug("SwitchToProfile missing layout lookup entry, skipping EM interaction; pending set", profileKey)
    end
    self:_setActiveProfile(profileKey, opts)
    self:PruneSpecAssignments()
end

function Profiles:RefreshFromEditMode(origin)
    if not ensureLayoutsLoaded() then
        Debug("RefreshFromEditMode aborted layouts not ready", origin or "?")
        return
    end

    local editableLayouts = LEO:GetEditableLayoutNames() or {}
    local presetLayouts = LEO:GetPresetLayoutNames() or {}
    local activeLayout = LEO:GetActiveLayout()
    Debug("RefreshFromEditMode", origin or "?", "active=" .. tostring(activeLayout), "pending=" .. tostring(self._pendingActiveLayout))
    LogReload("Refresh:" .. tostring(origin or "?"), { leoActive = activeLayout, pending = self._pendingActiveLayout, profile = self.db:GetCurrentProfile(), lock = self._reloadActivationLock })

    table.sort(editableLayouts, function(a, b) return tostring(a) < tostring(b) end)
    table.sort(presetLayouts, function(a, b) return tostring(a) < tostring(b) end)

    wipe(self._layoutLookup)
    wipe(self._presetLookup)

    self._sortedEditableLayouts = {}
    self._sortedPresetLayouts = {}

    for _, name in ipairs(editableLayouts) do
        self._layoutLookup[name] = true
        table.insert(self._sortedEditableLayouts, name)
        self:EnsureProfileExists(name, { copyFrom = self._lastActiveLayout })
    end

    for _, name in ipairs(presetLayouts) do
        self._layoutLookup[name] = true
        self._presetLookup[name] = true
        table.insert(self._sortedPresetLayouts, name)
        self:EnsureProfileExists(name, { preset = true })
    end

    -- Auto-heal: if AceDB contains profiles that don't exist as layouts, remove them
    -- so they can't block preset creation or cause cross-machine desync confusion.
    self:CleanupOrphanedProfiles()

    -- Detect if the current profile's Edit Mode layout was deleted externally (via Blizzard's Edit Mode UI).
    -- If so, prompt the user to reload so state can be properly synchronized.
    self:CheckForExternalDeletion()

    self:PruneSpecAssignments()
    if addon and addon._dbgProfiles then
        Debug("Editable:" , table.concat(self._sortedEditableLayouts, ", "))
        Debug("Presets:" , table.concat(self._sortedPresetLayouts, ", "))
    end

    self:DebugDumpLayouts(origin or "Refresh")

    local pending = self._pendingActiveLayout
    if pending and not self._layoutLookup[pending] then
        self._pendingActiveLayout = nil
        pending = nil
        Debug("Pending layout cleared; no lookup entry")
    end
    local currentProfile = self.db:GetCurrentProfile()
    Debug("Refresh state", "profile=" .. tostring(currentProfile), "active=" .. tostring(activeLayout), "pending=" .. tostring(pending))
    if pending and self._layoutLookup[pending] and activeLayout ~= pending then
        if currentProfile ~= pending then
            self:_setActiveProfile(pending, { skipLayout = true, force = true })
            Debug("Applied pending profile while awaiting EM", pending)
        end
        local now = GetTime and GetTime() or 0
        if not self:IsPostCopySuppressed() and (now == 0 or (now - (self._lastPendingApply or 0)) > 0.5) then
            if LEO and LEO.SetActiveLayout then
                pcall(LEO.SetActiveLayout, LEO, pending)
            end
            if addon.EditMode and addon.EditMode.SaveOnly then
                addon.EditMode.SaveOnly()
            end
            self._lastPendingApply = now
            Debug("Re-applied pending layout to Edit Mode", pending)
        else
            Debug("Suppressed EM re-apply during post-copy window", pending)
        end
        self._pendingActiveLayout = nil
        Debug("Cleared pending flag after resolution", pending)
        return
    end

    if activeLayout and self._layoutLookup[activeLayout] then
        -- If a pending profile activation was recently consumed, don't let stale LEO override it
        local now = GetTime and GetTime() or 0
        if self._reloadActivationLock and self._reloadActivationLockUntil then
            if activeLayout == self._reloadActivationLock then
                -- LEO agrees with target; proceed normally but keep lock active
                -- (LEO can report stale data again in subsequent calls within the same frame)
                Debug("Reload activation lock: LEO confirms target, lock stays", activeLayout)
                LogReload("Refresh:lockConfirmed", { lock = activeLayout })
            elseif now < self._reloadActivationLockUntil then
                -- LEO disagrees with our target and lock hasn't expired; don't override
                Debug("RefreshFromEditMode blocked by reload lock",
                      "lock=" .. tostring(self._reloadActivationLock),
                      "LEO=" .. tostring(activeLayout))
                LogReload("Refresh:locked", { lock = self._reloadActivationLock, leoActive = activeLayout })
                return
            else
                -- Lock expired; clear and fall through to normal behavior
                self._reloadActivationLock = nil
                self._reloadActivationLockUntil = nil
                Debug("Reload activation lock expired")
                LogReload("Refresh:lockExpired", { leoActive = activeLayout })
            end
        end
        -- Spec-change lock: prevent Blizzard's C++ per-spec layout memory from
        -- hot-swapping the profile without the required reload.
        if self._specChangeLock and self._specChangeLockUntil then
            if activeLayout == self._specChangeLock then
                -- LEO agrees with our intended profile; clear lock
                self._specChangeLock = nil
                self._specChangeLockUntil = nil
                Debug("Spec-change lock cleared: LEO matches target", activeLayout)
            elseif now < self._specChangeLockUntil then
                -- LEO reports a different layout (Blizzard's per-spec switch); block it
                Debug("RefreshFromEditMode blocked by spec-change lock",
                      "lock=" .. tostring(self._specChangeLock),
                      "LEO=" .. tostring(activeLayout))
                LogReload("Refresh:specLocked", { lock = self._specChangeLock, leoActive = activeLayout })
                return
            else
                -- Lock expired; clear and fall through
                self._specChangeLock = nil
                self._specChangeLockUntil = nil
                Debug("Spec-change lock expired")
                LogReload("Refresh:specLockExpired", { leoActive = activeLayout })
            end
        end
        local options = { skipLayout = true }
        if self._pendingActiveLayout and self._pendingActiveLayout ~= activeLayout then
            options.skipLayout = self:IsPostCopySuppressed() and true or false
            options.force = true
        end
        self:_setActiveProfile(activeLayout, options)
        Debug("Synced active layout from Edit Mode", activeLayout)
    else
        local current = self.db:GetCurrentProfile()
        if current and self._layoutLookup[current] then
            if activeLayout ~= current then
                self:_setActiveProfile(current, { force = true })
                Debug("Forced Edit Mode to current profile", current, "was", tostring(activeLayout))
            end
        elseif self._sortedEditableLayouts[1] then
            self:SwitchToProfile(self._sortedEditableLayouts[1], { force = true })
            Debug("Fallback to first editable layout", self._sortedEditableLayouts[1])
        end
    end

    if activeLayout and self._pendingActiveLayout == activeLayout then
        self._pendingActiveLayout = nil
        Debug("Cleared pending flag; layout now active", activeLayout)
    end
end

function Profiles:GetActiveProfile()
    return self.db and self.db:GetCurrentProfile()
end

function Profiles:IsActiveProfilePreset()
    local active = self:GetActiveProfile()
    if not active then
        return false
    end
    return self:IsPreset(active)
end

function addon.DumpReloadDebugLog()
    local log = addon.db and addon.db.global and addon.db.global._profileSwitchLog
    if not log or #log == 0 then
        if addon.DebugShowWindow then
            addon.DebugShowWindow("Profile Switch Log", "(no entries)")
        end
        return
    end
    local lines = {}
    for i, entry in ipairs(log) do
        local parts = {}
        for k, v in pairs(entry) do
            parts[#parts + 1] = k .. "=" .. tostring(v)
        end
        table.sort(parts)
        lines[#lines + 1] = "[" .. i .. "] " .. table.concat(parts, " | ")
    end
    if addon.DebugShowWindow then
        addon.DebugShowWindow("Profile Switch Log (" .. #log .. " entries)", table.concat(lines, "\n"))
    end
end

-- Expose internals for sibling profiles files
addon.Profiles._Debug = Debug
addon.Profiles._deepCopy = deepCopy
addon.Profiles._ensureLayoutsLoaded = ensureLayoutsLoaded
addon.Profiles._isCombatLocked = isCombatLocked
addon.Profiles._normalizeName = normalizeName
addon.Profiles._notifyUI = notifyUI
addon.Profiles._postMutationSync = postMutationSync
addon.Profiles._addLayoutToCache = addLayoutToCache
addon.Profiles._getCurrentSpecID = getCurrentSpecID

return Profiles
