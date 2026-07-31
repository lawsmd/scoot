-- init.lua - Addon initialization, defaults registration, and event routing
local addonName, addon = ...

addon.FeatureToggles = addon.FeatureToggles or {}

function addon:OnInitialize()
    -- PTR safety: Settings modules can be renamed/restructured between builds.
    -- Treat these loads as best-effort to avoid hard errors during initialization.
    if C_AddOns and C_AddOns.LoadAddOn then
        pcall(C_AddOns.LoadAddOn, "Blizzard_Settings")
        pcall(C_AddOns.LoadAddOn, "Blizzard_Settings_Shared")
    end
    -- Warm up bundled fonts early to avoid first-open rendering differences
    if addon.PreloadFonts then addon.PreloadFonts() end

    -- Migration: cement explicit moduleEnabled = true for all existing profiles.
    -- Defaults changed from true → false (zero-touch policy). Without this,
    -- existing profiles that relied on the old defaults would lose their modules.
    -- Runs on raw SavedVariables BEFORE AceDB:New so copyDefaults won't overwrite.
    do
        local sv = _G["ScootDB"]
        if sv and sv.profiles and not (sv.global and sv.global._moduleEnabledDefaultsV2) then
            local KEYS = {
                "actionBars", "buffsDebuffs", "classAuras", "cooldownManager",
                "damageMeter", "extraAbilities", "groupFrames", "minimap",
                "notes", "objectiveTracker", "prd", "sct", "tooltip", "unitFrames",
            }
            for _, profileData in pairs(sv.profiles) do
                if type(profileData) == "table" then
                    if not profileData.moduleEnabled then
                        profileData.moduleEnabled = {}
                    end
                    for _, key in ipairs(KEYS) do
                        if profileData.moduleEnabled[key] == nil then
                            profileData.moduleEnabled[key] = true
                        end
                    end
                end
            end
            if not sv.global then sv.global = {} end
            sv.global._moduleEnabledDefaultsV2 = true
        end
    end

    -- Migration V3: Remove _enabled from newly-noMasterToggle categories.
    -- If _enabled was false, propagate that to all sub-keys (preserves user intent).
    do
        local sv = _G["ScootDB"]
        if sv and sv.profiles and not (sv.global and sv.global._moduleEnabledNoMasterV3) then
            local NO_MASTER_CATS = { "actionBars", "buffsDebuffs", "cooldownManager", "groupFrames", "unitFrames" }
            for _, profileData in pairs(sv.profiles) do
                if type(profileData) == "table" and type(profileData.moduleEnabled) == "table" then
                    for _, cat in ipairs(NO_MASTER_CATS) do
                        local val = profileData.moduleEnabled[cat]
                        if type(val) == "table" then
                            if val._enabled == false then
                                -- Master was off: set all sub-keys to false
                                for k, _ in pairs(val) do
                                    if k ~= "_enabled" then val[k] = false end
                                end
                            end
                            val._enabled = nil
                        end
                    end
                end
            end
            if not sv.global then sv.global = {} end
            sv.global._moduleEnabledNoMasterV3 = true
        end
    end

    -- Migration V4: Remove healthBarReverseFill/powerBarReverseFill (conflicts with TempMaxHealthLoss)
    do
        local sv = _G["ScootDB"]
        if sv and sv.profiles and not (sv.global and sv.global._reverseFillRemovedV4) then
            for _, profileData in pairs(sv.profiles) do
                if type(profileData) == "table" then
                    local uf = type(profileData.unitFrames) == "table" and profileData.unitFrames or nil
                    if uf then
                        for _, unitKey in ipairs({ "Target", "Focus" }) do
                            local unitCfg = type(uf[unitKey]) == "table" and uf[unitKey] or nil
                            if unitCfg then
                                unitCfg.healthBarReverseFill = nil
                                unitCfg.powerBarReverseFill = nil
                            end
                        end
                    end
                end
            end
            if not sv.global then sv.global = {} end
            sv.global._reverseFillRemovedV4 = true
        end
    end

    -- 1. Create the database first so moduleEnabled is available for component gating.
    --    GetDefaults() does not reference self.Components — safe to call before init.
    self.db = LibStub("AceDB-3.0"):New("ScootDB", self:GetDefaults(), true)

    if self.Profiles and self.Profiles.Initialize then
        self.Profiles:Initialize()
    end
    if self.Rules and self.Rules.Initialize then
        self.Rules:Initialize()
    end
    -- Initialize Interface feature modules that depend on AceDB/profile selection.
    -- Chat hide/show is combat-safe and enforced separately from ApplyStyles().
    if self.Chat and self.Chat.Initialize then
        self.Chat:Initialize()
    end
    -- Raid frame hiding is likewise combat-safe and enforced outside ApplyStyles().
    if self.RaidVisibility and self.RaidVisibility.Initialize then
        self.RaidVisibility:Initialize()
    end
    -- The roster overlay is a Scoot-owned frame, so it is likewise safe to
    -- build and show outside ApplyStyles().
    if self.RaidRosterOverlay and self.RaidRosterOverlay.Initialize then
        self.RaidRosterOverlay:Initialize()
    end

    -- Apply pending preset activation (set during preset import).
    -- Runs on the next load to avoid "Interface action failed because of an AddOn"
    -- when trying to activate immediately after creating/saving layouts.
    if self.db and self.db.global and self.db.global.pendingPresetActivation and C_Timer and C_Timer.After then
        local pending = self.db.global.pendingPresetActivation
        C_Timer.After(0.6, function()
            if not addon or not addon.db or not addon.db.global then return end
            local p = addon.db.global.pendingPresetActivation
            if not p or not p.layoutName then return end
            if InCombatLockdown and InCombatLockdown() then return end
            if addon.Profiles and addon.Profiles.SwitchToProfile then
                addon.Profiles:SwitchToProfile(p.layoutName, { reason = "PresetActivationOnLoad", force = true })
            end
            addon.db.global.pendingPresetActivation = nil
        end)
    end

    -- NOTE: pendingProfileActivation is consumed in Profiles:Initialize() so the new
    -- profile/layout is activated as early as possible (before ApplyStyles runs).

    -- 2. Define components — disabled modules are skipped via moduleEnabled checks.
    self:InitializeComponents()

    -- Snapshot which modules are active this session (for nav filtering).
    -- Uses MODULE_CATEGORY_ORDER + IsModuleEnabled() instead of pairs() on the
    -- raw DB table, so that AceDB default-only keys (never explicitly set by the
    -- user) are included and the snapshot always matches IsModuleEnabled() results.
    self._activeModules = {}
    self._activeModuleSubs = {}
    for _, category in ipairs(self.MODULE_CATEGORY_ORDER) do
        self._activeModules[category] = self:IsModuleEnabled(category)
        local catDef = self.MODULE_CATEGORIES[category]
        if catDef and catDef.subToggles then
            self._activeModuleSubs[category] = {}
            for _, sub in ipairs(catDef.subToggles) do
                local checkId = sub.members and sub.members[1] or sub.id
                self._activeModuleSubs[category][sub.id] =
                    self:IsModuleEnabled(category, checkId) and true or false
            end
        end
    end

    -- 3. Now that DB exists, link components to their DB tables
    self:LinkComponentsToDB()

    -- 4. Allow components that only need global resources to apply immediately (before world load)
    if self.ApplyEarlyComponentStyles then
        self:ApplyEarlyComponentStyles()
    end

    -- 5. Register for events
    -- Login/spec-change guard: PLAYER_SPECIALIZATION_CHANGED can fire during initial login.
    -- Prompting/reloading in that phase must be suppressed; only live spec switches should prompt.
    self._scootSpecLoginGuard = true

    -- Initialize Edit Mode integration (hooks + compatibility flags).
    if self.EditMode and self.EditMode.Initialize then
        pcall(self.EditMode.Initialize)
    end

    self:RegisterEvents()
end

function addon:GetDefaults()
    local defaults = {
        global = {
            pendingPresetActivation = nil,
            pendingProfileActivation = nil,
            _profileSwitchLog = nil,  -- persists debug entries across reload
            -- Settings Panel (global accent color, position, size)
            accentColor = { r = 0, g = 1, b = 0.255, a = 1 },  -- Matrix green #00FF41
            windowPosition = nil,  -- Saved as { point, relPoint, x, y }
        },
        profile = {
            applyAll = {
                fontPending = "FRIZQT__",
                barTexturePending = "default",
                lastFontApplied = nil,
                lastTextureApplied = nil,
            },
            -- Cooldown Manager quality-of-life settings
            -- NOTE: enableCDM is intentionally omitted from defaults so it remains nil
            -- (inherit Blizzard CVar) until the user explicitly sets it per profile.
            cdmQoL = {
                enableSlashCDM = false,
            },
            -- PRD per-profile settings
            -- NOTE: enablePRD is intentionally omitted from defaults so it remains nil
            -- (inherit Blizzard CVar) until the user explicitly sets it per profile.
            prdSettings = {},
            minimap = {
                hide = false,
                minimapPos = 220,
            },
            misc = {
                customGameMenu = false,
            },
            components = {},
            rules = {},
            rulesState = {
                baselines = {},
                nextId = 1,
            },
            moduleEnabled = {
                actionBars = false,
                bossWarnings = false,
                buffsDebuffs = false,
                classAuras = false,
                cooldownManager = false,
                damageMeter = false,
                extraAbilities = false,
                groupFrames = false,
                minimap = false,
                notes = false,
                objectiveTracker = false,
                prd = false,
                sct = false,
                tooltip = false,
                unitFrames = false,
                widget = false,
            },
            groupFrames = {
                raid = {
                    healthBarTexture = "default",
                    healthBarColorMode = "default",
                    healthBarTint = {1, 1, 1, 1},
                    healthBarBackgroundTexture = "default",
                    healthBarBackgroundColorMode = "default",
                    healthBarBackgroundTint = {0, 0, 0, 1},
                    healthBarBackgroundOpacity = 50,
                },
            },
        },
        char = {
            specProfiles = {
                enabled = false,
                assignments = {}
            }
        }
    }

    -- NOTE: Per-component defaults are NOT registered here. AceDB's copyDefaults
    -- writes registered scalar defaults into the raw profile table via rawset,
    -- which defeats rawget-based zero-touch detection. Instead, per-component
    -- defaults are provided at runtime by attachSettingsDefaults() in
    -- core/components/base/core.lua, which uses a metatable __index fallback
    -- that returns defaults WITHOUT writing them to the profile table.

    return defaults
end

function addon:RegisterEvents()
    -- AceEvent hard-errors when registering unknown events; guard any version-variant events.
    local function safeRegisterEvent(eventName)
        local ok = pcall(self.RegisterEvent, self, eventName)
        return ok
    end

    self:RegisterEvent("PLAYER_ENTERING_WORLD")
    -- PTR safety: Edit Mode event names have historically changed between major patches.
    safeRegisterEvent("EDIT_MODE_LAYOUTS_UPDATED")
    self:RegisterEvent("ADDON_LOADED")
    self:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    -- Ensure Unit Frame styling is re-applied when target/focus units change
    self:RegisterEvent("PLAYER_TARGET_CHANGED")
    self:RegisterEvent("PLAYER_FOCUS_CHANGED")
    -- Pet lifecycle / pet overlays
    self:RegisterEvent("UNIT_PET")
    self:RegisterEvent("PET_UI_UPDATE")
    self:RegisterEvent("PET_ATTACK_START")
    self:RegisterEvent("PET_ATTACK_STOP")
    -- Pet threat changes drive PetFrameFlash via UnitFrame_UpdateThreatIndicator
    self:RegisterEvent("UNIT_THREAT_SITUATION_UPDATE")
    -- Boss unit frames can be created/shown after initial load; re-apply when encounter units update.
    safeRegisterEvent("INSTANCE_ENCOUNTER_ENGAGE_UNIT")
    safeRegisterEvent("UPDATE_BOSS_FRAMES")
    -- Re-evaluate Rules when player levels up (for playerLevel trigger type)
    self:RegisterEvent("PLAYER_LEVEL_UP")
    -- Combat state changes for opacity updates (priority: With Target > In Combat > Out of Combat)
    self:RegisterEvent("PLAYER_REGEN_DISABLED")
    self:RegisterEvent("PLAYER_REGEN_ENABLED")
    
    -- Apply dropdown stepper fixes (function lives in ui_fixes.lua)
    if addon.UIFixes and addon.UIFixes.ApplyDropdownStepperFixes then
        addon.UIFixes.ApplyDropdownStepperFixes()
    end
end

-- Refresh opacity state for all elements affected by combat/target priority
-- Safe to call during combat as SetAlpha is not a protected function
function addon:RefreshOpacityState()
    -- Update Unit Frame visibility/opacity
    if addon.ApplyAllUnitFrameVisibility then
        addon.ApplyAllUnitFrameVisibility()
    end
    -- Update all components that have opacity settings (CDM, Action Bars, Auras, etc.)
    for id, component in pairs(self.Components) do
        -- Zero-Touch: skip unconfigured components (still on proxy DB)
        if component._ScootDBProxy and component.db == component._ScootDBProxy then
            -- no-op: component not configured
        elseif (component.RefreshOpacity or component.ApplyStyling) and component.settings then
            -- Check for opacity settings with various naming conventions:
            -- - CDM uses: opacity, opacityOutOfCombat, opacityWithTarget
            -- - Action Bars use: barOpacity, barOpacityOutOfCombat, barOpacityWithTarget
            -- - Auras use: opacity, opacityOutOfCombat, opacityWithTarget
            local hasOpacity = component.settings.opacity or
                component.settings.opacityInInstanceCombat or
                component.settings.opacityOutOfCombat or
                component.settings.opacityWithTarget or
                component.settings.barOpacity or
                component.settings.barOpacityOutOfCombat or
                component.settings.barOpacityWithTarget
            if hasOpacity then
                if component.RefreshOpacity then
                    pcall(component.RefreshOpacity, component)
                else
                    pcall(component.ApplyStyling, component)
                end
            end
        end
    end
end

function addon:PLAYER_REGEN_DISABLED()
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            self:RefreshOpacityState()
        end)
    else
        self:RefreshOpacityState()
    end
end

-- Shared helper for pet overlay enforcement events
local function handlePetOverlayEvent()
    -- IMPORTANT: PetFrame is an Edit Mode managed/protected system frame.
    -- Pending work is flagged during combat so it is always re-asserted on PLAYER_REGEN_ENABLED.
    -- Experimental: also allows in-combat alpha enforcement for PetFrameFlash to prevent
    -- the red glow/ring from reappearing and persisting until combat ends.
    if InCombatLockdown and InCombatLockdown() then
        addon._pendingPetOverlaysEnforce = true
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            if addon.UnitFrames_EnforcePetOverlays then
                addon.UnitFrames_EnforcePetOverlays()
            end
        end)
    elseif addon.UnitFrames_EnforcePetOverlays then
        addon.UnitFrames_EnforcePetOverlays()
    end
end

function addon:UNIT_PET(event, unit)
    if unit == "player" then handlePetOverlayEvent() end
end

function addon:PET_UI_UPDATE()
    handlePetOverlayEvent()
end

function addon:PET_ATTACK_START()
    handlePetOverlayEvent()
end

function addon:PET_ATTACK_STOP()
    handlePetOverlayEvent()
end

function addon:UNIT_THREAT_SITUATION_UPDATE(event, unit)
    if unit == "pet" then handlePetOverlayEvent() end
end

function addon:PLAYER_REGEN_ENABLED()
    if C_Timer and C_Timer.After then
        C_Timer.After(0.1, function()
            -- Handle deferred styling if ApplyStyles was called during combat
            if self._pendingApplyStyles then
                self._pendingApplyStyles = nil
                self:ApplyStyles()
            else
                -- Just refresh opacity state
                self:RefreshOpacityState()
            end

            -- Apply any deferred Pet overlay enforcement now that combat lockdown is lifted.
            if addon._pendingPetOverlaysEnforce then
                addon._pendingPetOverlaysEnforce = nil
                if addon.UnitFrames_EnforcePetOverlays then
                    addon.UnitFrames_EnforcePetOverlays()
                end
            end

            -- Flush any cast bars that were reanchored (position-only) during combat
            if addon.FlushPendingCastBarRefresh then
                addon.FlushPendingCastBarRefresh()
            end
            if addon.FlushPendingBossCastBarRefresh then
                addon.FlushPendingBossCastBarRefresh()
            end

            -- If a spec change required a profile switch while combat-locked, prompt now (out of combat).
            if self.Profiles and self.Profiles._pendingSpecReload then
                local pending = self.Profiles._pendingSpecReload
                self.Profiles._pendingSpecReload = nil
                local specName = (pending and pending.specID and GetSpecializationNameByID and GetSpecializationNameByID(pending.specID)) or "unknown"
                if pending and pending.profile and self.Profiles.PromptReloadToProfile then
                    self.Profiles:PromptReloadToProfile(pending.profile, { reason = "SpecChanged", specID = pending.specID, specName = specName })
                end
            end

            -- Generic queued reload-to-profile requests (never execute ReloadUI() directly here).
            if self.Profiles and self.Profiles._pendingReloadToProfile and self.Profiles.PromptReloadToProfile then
                local p = self.Profiles._pendingReloadToProfile
                self.Profiles._pendingReloadToProfile = nil
                if p and p.layoutName then
                    self.Profiles:PromptReloadToProfile(p.layoutName, p.meta)
                end
            end
        end)
    else
        if self._pendingApplyStyles then
            self._pendingApplyStyles = nil
            self:ApplyStyles()
        else
            self:RefreshOpacityState()
        end

        if addon._pendingPetOverlaysEnforce then
            addon._pendingPetOverlaysEnforce = nil
            if addon.UnitFrames_EnforcePetOverlays then
                addon.UnitFrames_EnforcePetOverlays()
            end
        end

        -- Flush any cast bars that were reanchored (position-only) during combat
        if addon.FlushPendingCastBarRefresh then
            addon.FlushPendingCastBarRefresh()
        end
        if addon.FlushPendingBossCastBarRefresh then
            addon.FlushPendingBossCastBarRefresh()
        end

        -- If a spec change required a profile switch while combat-locked, prompt now (out of combat).
        if self.Profiles and self.Profiles._pendingSpecReload then
            local pending = self.Profiles._pendingSpecReload
            self.Profiles._pendingSpecReload = nil
            local specName = (pending and pending.specID and GetSpecializationNameByID and GetSpecializationNameByID(pending.specID)) or "unknown"
            if pending and pending.profile and self.Profiles.PromptReloadToProfile then
                self.Profiles:PromptReloadToProfile(pending.profile, { reason = "SpecChanged", specID = pending.specID, specName = specName })
            end
        end

        -- Generic queued reload-to-profile requests (never execute ReloadUI() directly here).
        if self.Profiles and self.Profiles._pendingReloadToProfile and self.Profiles.PromptReloadToProfile then
            local p = self.Profiles._pendingReloadToProfile
            self.Profiles._pendingReloadToProfile = nil
            if p and p.layoutName then
                self.Profiles:PromptReloadToProfile(p.layoutName, p.meta)
            end
        end
    end
end

function addon:PLAYER_ENTERING_WORLD(event, isInitialLogin, isReloadingUi)
    -- Initialize Edit Mode integration (best-effort; keep addon loading even if Edit Mode changes).
    if addon.EditMode and addon.EditMode.Initialize then
        pcall(addon.EditMode.Initialize)
    end
    -- Re-assert per-bar enable state on zone changes; the SETTINGS_LOADED arrival hook
    -- only fires once per session. Idempotent and self-deferring, so cheap.
    if addon.ReconcileActionBarsEnabled then
        addon.ReconcileActionBarsEnabled("PLAYER_ENTERING_WORLD")
    end
    -- Ensure fonts are preloaded even if initialization order changes
    if addon.PreloadFonts then addon.PreloadFonts() end
    -- Force index-mode for Opacity on Cooldown Viewer systems (compat path); safe no-op if already set
    do
        local LEO_local = LibStub and LibStub("LibEditModeOverride-1.0")
        if LEO_local and _G.Enum and _G.Enum.EditModeSystem and _G.Enum.EditModeCooldownViewerSetting then
            local sys = _G.Enum.EditModeSystem.CooldownViewer
            local setting = _G.Enum.EditModeCooldownViewerSetting.Opacity
            LEO_local._forceIndexBased = LEO_local._forceIndexBased or {}
            LEO_local._forceIndexBased[sys] = LEO_local._forceIndexBased[sys] or {}
            -- Enable compat mode so both write/read paths use raw<->index consistently under the hood
            LEO_local._forceIndexBased[sys][setting] = true
        end
    end
    
    -- NOTE: A method override on EditModeManagerFrame.NotifyChatOfLayoutChange was removed because
    -- method overrides cause PERSISTENT TAINT that propagates to unrelated Blizzard code.
    -- In 11.2.7, this taint was blocking ActionButton:SetAttribute() calls in the new
    -- "press and hold" system. The cosmetic benefit of suppressing announcements is not worth
    -- breaking core action bar functionality.
    
    -- Use centralized sync function (if available)
    if addon.EditMode and addon.EditMode.RefreshSyncAndNotify then
        pcall(addon.EditMode.RefreshSyncAndNotify, "PLAYER_ENTERING_WORLD")
    end
    -- Re-evaluate combat/instance-driven opacity overrides when zoning (including entering/leaving instances).
    self:RefreshOpacityState()
    if self.Profiles then
        if self.Profiles.TryPendingSync then
            self.Profiles:TryPendingSync()
        end
        if self.Profiles.OnPlayerSpecChanged then
            -- On initial world entry, spec profiles may need to switch to an assigned layout.
            -- Do this without triggering a reload ONLY on real login/reload.
            self.Profiles:OnPlayerSpecChanged({ fromLogin = not not (isInitialLogin or isReloadingUi) })
        end
    end

    -- Clear login guard shortly after initial login/reload.
    if isInitialLogin or isReloadingUi then
        if C_Timer and C_Timer.After then
            C_Timer.After(0.5, function()
                if addon then
                    addon._scootSpecLoginGuard = false
                    -- Record a stable baseline spec after login/reload to ignore
                    -- non-spec-change triggers (like loading screens) later in the session.
                    if addon.Profiles and addon.Profiles.RecordCurrentSpec then
                        addon.Profiles:RecordCurrentSpec()
                    end
                end
            end)
        else
            self._scootSpecLoginGuard = false
            if addon.Profiles and addon.Profiles.RecordCurrentSpec then
                addon.Profiles:RecordCurrentSpec()
            end
        end
    end
    if self.Rules and self.Rules.OnPlayerLogin then
        self.Rules:OnPlayerLogin()
    end
    
    -- Install early alpha enforcement hooks for Target/Focus frame elements.
    -- Must happen BEFORE first target acquisition to prevent "first target flash".
    -- The hooks ensure elements stay hidden even before applyForUnit() has run.
    if addon.InstallEarlyUnitFrameAlphaHooks then
        addon.InstallEarlyUnitFrameAlphaHooks()
    end
    
    -- Install Boss frame hooks to catch updates during combat.
    -- Boss frames are updated via INSTANCE_ENCOUNTER_ENGAGE_UNIT and UPDATE_BOSS_FRAMES,
    -- but those handlers skip during combat. These hooks catch Show/CheckFaction/etc.
    if addon.InstallBossFrameHooks then
        addon.InstallBossFrameHooks()
    end
    
    self:ApplyStyles()

    -- Post-load belt-and-braces: profile/layout sync (TryPendingSync, spec
    -- profiles above) can finish after the styling pass just ran, and the
    -- pre-emptive hides bail silently while config is unreadable. Re-assert on
    -- short delays so Target/Focus art never sits at its post-reload default
    -- (visible) because the first passes ran too early. Idempotent SetAlpha(0).
    if C_Timer and C_Timer.After then
        local function reassertArtHiding()
            if addon.PreemptiveHideTargetElements then addon.PreemptiveHideTargetElements() end
            if addon.PreemptiveHideFocusElements then addon.PreemptiveHideFocusElements() end
        end
        C_Timer.After(1, reassertArtHiding)
        C_Timer.After(3, reassertArtHiding)
    end

    -- Enforce Pet overlay visibility immediately after initial styling.
    -- Ensures PetAttackModeTexture is hidden before the first frame renders if the
    -- player has a pet that's already in attack mode when logging in or reloading.
    if addon.UnitFrames_EnforcePetOverlays then
        addon.UnitFrames_EnforcePetOverlays()
    end
    
    -- Deferred reapply of Player textures to catch any Blizzard resets after initial apply
    -- Ensures textures persist even if Blizzard updates the frame after our initial styling
    if C_Timer and C_Timer.After and addon.ApplyUnitFrameBarTexturesFor then
        C_Timer.After(0.1, function()
            addon.ApplyUnitFrameBarTexturesFor("Player")
        end)
    end
    -- Deferred Pet overlay enforcement to catch Blizzard resets (PetFrame:Update runs after login).
    -- Ensures PetAttackModeTexture stays hidden even if Blizzard shows it after initial styling.
    if C_Timer and C_Timer.After and addon.UnitFrames_EnforcePetOverlays then
        C_Timer.After(0.1, function()
            addon.UnitFrames_EnforcePetOverlays()
        end)
    end
    -- Deferred reapply of Cast Bars to catch any Blizzard resets after initial apply.
    -- Guard with Zero‑Touch: only reapply if the profile has explicit cast bar config.
    if C_Timer and C_Timer.After and addon.ApplyAllUnitFrameCastBars and addon.db and addon.db.profile then
        local profile = addon.db.profile
        local unitFrames = rawget(profile, "unitFrames")
        local playerCfg = unitFrames and rawget(unitFrames, "Player")
        local hasPlayerCastCfg = playerCfg and rawget(playerCfg, "castBar") ~= nil
        if hasPlayerCastCfg then
            C_Timer.After(0.1, function()
                if not (InCombatLockdown and InCombatLockdown()) then
                    addon.ApplyAllUnitFrameCastBars()
                end
            end)
        end
    end
    -- Deferred reapply of Player name/level text visibility to catch Blizzard resets
    -- (e.g., PlayerFrame_Update, PlayerFrame_UpdateRolesAssigned) that run after initial styling
    if C_Timer and C_Timer.After and addon.ApplyUnitFrameNameLevelTextFor then
        C_Timer.After(0.1, function()
            addon.ApplyUnitFrameNameLevelTextFor("Player")
        end)
    end
    -- Deferred reapply of Player health/power bar text visibility to catch Blizzard resets
    -- (TextStatusBarMixin:UpdateTextStringWithValues shows LeftText/RightText after initial styling)
    if C_Timer and C_Timer.After then
        C_Timer.After(0.1, function()
            if addon.ApplyUnitFrameHealthTextVisibilityFor then
                addon.ApplyUnitFrameHealthTextVisibilityFor("Player")
            end
            if addon.ApplyUnitFramePowerTextVisibilityFor then
                addon.ApplyUnitFramePowerTextVisibilityFor("Player")
            end
        end)
        -- Additional longer-delay reapply specifically for instance loading transitions.
        -- When entering instances, Blizzard's unit frame updates can run significantly later
        -- than the 0.1s delay, resetting fonts via SetFontObject. This secondary pass ensures
        -- custom text styling (font face/size/color) persists through instance loading.
        C_Timer.After(0.5, function()
            if addon.ApplyAllUnitFrameHealthTextVisibility then
                addon.ApplyAllUnitFrameHealthTextVisibility()
            end
            if addon.ApplyAllUnitFramePowerTextVisibility then
                addon.ApplyAllUnitFramePowerTextVisibility()
            end
            -- Also reapply bar textures for Player to catch Alternate Power Bar text styling
            if addon.ApplyUnitFrameBarTexturesFor then
                addon.ApplyUnitFrameBarTexturesFor("Player")
                -- Boss frames may appear/update during/after instance transitions; reapply on the longer delay.
                addon.ApplyUnitFrameBarTexturesFor("Boss")
            end
            if addon.ApplyUnitFrameHealthTextVisibilityFor then
                addon.ApplyUnitFrameHealthTextVisibilityFor("Boss")
            end
            if addon.ApplyUnitFramePowerTextVisibilityFor then
                addon.ApplyUnitFramePowerTextVisibilityFor("Boss")
            end
            if addon.ApplyUnitFrameNameLevelTextFor then
                addon.ApplyUnitFrameNameLevelTextFor("Boss")
            end
        end)
    end
end

function addon:PLAYER_TARGET_CHANGED()
    -- =========================================================================
    -- EDIT MODE GUARD: Skip synchronous modifications during Edit Mode
    -- =========================================================================
    -- When Edit Mode opens, it calls TargetUnit which fires PLAYER_TARGET_CHANGED.
    -- Synchronous modifications to TargetFrame elements during this call chain
    -- taint the execution context, causing Blizzard's UpdateTextStringWithValues
    -- to fail with "secret value" errors when it tries to compare StatusBar values.
    -- Skip preemptive hiding when Edit Mode is active or opening.
    if addon.EditMode.IsEditModeActiveOrOpening() then
        if addon.RepColorTrace then addon.RepColorTrace("PTC", "bail: edit mode guard") end
        -- Defer all work to avoid taint propagation during Edit Mode
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function()
                self:RefreshOpacityState()
            end)
            -- Self-heal: the guard has a load-time seeding false positive
            -- (editmode/core.lua). If it was transient, re-run the preemptive
            -- hide once it clears so a missed acquisition-time hide doesn't
            -- leave the post-reload default (visible) art until the next
            -- target change.
            C_Timer.After(0.5, function()
                if addon.EditMode.IsEditModeActiveOrOpening() then return end
                if addon.PreemptiveHideTargetElements then
                    addon.PreemptiveHideTargetElements()
                end
            end)
        end
        return
    end
    if addon.RepColorTrace then addon.RepColorTrace("PTC", "fired") end

    -- =========================================================================
    -- IMMEDIATE PRE-EMPTIVE HIDING (runs BEFORE Blizzard's TargetFrame_Update)
    -- =========================================================================
    -- Key to preventing visual "flash" of hidden elements.
    -- PLAYER_TARGET_CHANGED fires BEFORE Blizzard's internal handler calls
    -- TargetFrame_Update. By hiding elements synchronously here (not deferred),
    -- they're already hidden when Blizzard tries to show them.
    if addon.PreemptiveHideTargetElements then
        addon.PreemptiveHideTargetElements()
    end
    if addon.PreemptiveHideLevelText then
        addon.PreemptiveHideLevelText("Target")
    end
    if addon.PreemptiveHideNameText then
        addon.PreemptiveHideNameText("Target")
    end

    -- =========================================================================
    -- DEFERRED FULL STYLING PASS (runs AFTER Blizzard's TargetFrame_Update)
    -- =========================================================================
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            if addon.ApplyUnitFrameBarTexturesFor then
                addon.ApplyUnitFrameBarTexturesFor("Player")
                addon.ApplyUnitFrameBarTexturesFor("Target")
            end
            if addon.ApplyUnitFrameNameLevelTextFor then
                addon.ApplyUnitFrameNameLevelTextFor("Target")
            end
            if addon.ApplyUnitFrameHealthTextVisibilityFor then
                addon.ApplyUnitFrameHealthTextVisibilityFor("Target")
            end
            if addon.ApplyUnitFramePowerTextVisibilityFor then
                addon.ApplyUnitFramePowerTextVisibilityFor("Target")
            end
            self:RefreshOpacityState()
            
            C_Timer.After(0.1, function()
                if addon.ApplyUnitFrameBarTexturesFor then
                    addon.ApplyUnitFrameBarTexturesFor("Player")
                end
            end)
        end)
    else
        if addon.ApplyUnitFrameBarTexturesFor then
            addon.ApplyUnitFrameBarTexturesFor("Player")
            addon.ApplyUnitFrameBarTexturesFor("Target")
        end
        if addon.ApplyUnitFrameNameLevelTextFor then
            addon.ApplyUnitFrameNameLevelTextFor("Target")
        end
        if addon.ApplyUnitFrameHealthTextVisibilityFor then
            addon.ApplyUnitFrameHealthTextVisibilityFor("Target")
        end
        if addon.ApplyUnitFramePowerTextVisibilityFor then
            addon.ApplyUnitFramePowerTextVisibilityFor("Target")
        end
        self:RefreshOpacityState()
    end
end

function addon:PLAYER_FOCUS_CHANGED()
    -- =========================================================================
    -- EDIT MODE GUARD: Skip synchronous modifications during Edit Mode
    -- =========================================================================
    -- Same rationale as PLAYER_TARGET_CHANGED: Edit Mode triggers FocusUnit
    -- which fires PLAYER_FOCUS_CHANGED. Skip preemptive hiding to avoid taint.
    if addon.EditMode.IsEditModeActiveOrOpening() then
        if addon.RepColorTrace then addon.RepColorTrace("PFC", "bail: edit mode guard") end
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function()
                if addon.ApplyUnitFrameBarTexturesFor then
                    addon.ApplyUnitFrameBarTexturesFor("Focus")
                end
            end)
            -- Self-heal for a transient guard false positive (see PLAYER_TARGET_CHANGED)
            C_Timer.After(0.5, function()
                if addon.EditMode.IsEditModeActiveOrOpening() then return end
                if addon.PreemptiveHideFocusElements then
                    addon.PreemptiveHideFocusElements()
                end
            end)
        end
        return
    end
    if addon.RepColorTrace then addon.RepColorTrace("PFC", "fired") end

    -- =========================================================================
    -- IMMEDIATE PRE-EMPTIVE HIDING (runs BEFORE Blizzard's FocusFrame_Update)
    -- =========================================================================
    -- Key to preventing visual "flash" of hidden elements.
    -- PLAYER_FOCUS_CHANGED fires BEFORE Blizzard's internal handler calls
    -- FocusFrame_Update. By hiding elements synchronously here (not deferred),
    -- they're already hidden when Blizzard tries to show them.
    if addon.PreemptiveHideFocusElements then
        addon.PreemptiveHideFocusElements()
    end
    if addon.PreemptiveHideLevelText then
        addon.PreemptiveHideLevelText("Focus")
    end
    if addon.PreemptiveHideNameText then
        addon.PreemptiveHideNameText("Focus")
    end

    -- =========================================================================
    -- DEFERRED FULL STYLING PASS (runs AFTER Blizzard's FocusFrame_Update)
    -- =========================================================================
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            if addon.ApplyUnitFrameBarTexturesFor then
                addon.ApplyUnitFrameBarTexturesFor("Focus")
            end
            -- Also apply Name & Level Text visibility to ensure hidden settings persist
            if addon.ApplyUnitFrameNameLevelTextFor then
                addon.ApplyUnitFrameNameLevelTextFor("Focus")
            end
            -- Also apply Health/Power bar text visibility to ensure hidden settings persist
            if addon.ApplyUnitFrameHealthTextVisibilityFor then
                addon.ApplyUnitFrameHealthTextVisibilityFor("Focus")
            end
            if addon.ApplyUnitFramePowerTextVisibilityFor then
                addon.ApplyUnitFramePowerTextVisibilityFor("Focus")
            end
        end)
    else
        if addon.ApplyUnitFrameBarTexturesFor then
            addon.ApplyUnitFrameBarTexturesFor("Focus")
        end
        if addon.ApplyUnitFrameNameLevelTextFor then
            addon.ApplyUnitFrameNameLevelTextFor("Focus")
        end
        if addon.ApplyUnitFrameHealthTextVisibilityFor then
            addon.ApplyUnitFrameHealthTextVisibilityFor("Focus")
        end
        if addon.ApplyUnitFramePowerTextVisibilityFor then
            addon.ApplyUnitFramePowerTextVisibilityFor("Focus")
        end
    end
end

-- Boss unit frames can appear/update without target/focus change events.
-- Re-apply our styling after Blizzard updates boss units.
function addon:INSTANCE_ENCOUNTER_ENGAGE_UNIT()
    -- IMPORTANT: Call preemptive hide BEFORE combat check to ensure ReputationColor
    -- (and other visual elements) are hidden immediately, even during combat.
    -- SetAlpha via pcall is safe during combat and won't cause taint.
    if addon.PreemptiveHideBossElements then
        addon.PreemptiveHideBossElements()
    end

    -- Text visibility uses pcall(SetAlpha) which is combat-safe (same as PreemptiveHide).
    if addon.ApplyUnitFrameHealthTextVisibilityFor then addon.ApplyUnitFrameHealthTextVisibilityFor("Boss") end
    if addon.ApplyUnitFramePowerTextVisibilityFor then addon.ApplyUnitFramePowerTextVisibilityFor("Boss") end

    -- Boss unit frames can update during combat. Do not touch protected Boss frames during combat
    -- (even "cosmetic" changes) to avoid taint that can later block BossTargetFrameContainer:SetSize().
    if InCombatLockdown and InCombatLockdown() then
        self._pendingApplyStyles = true
        return
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            if addon.ApplyUnitFrameBarTexturesFor then addon.ApplyUnitFrameBarTexturesFor("Boss") end
            if addon.ApplyUnitFrameHealthTextVisibilityFor then addon.ApplyUnitFrameHealthTextVisibilityFor("Boss") end
            if addon.ApplyUnitFramePowerTextVisibilityFor then addon.ApplyUnitFramePowerTextVisibilityFor("Boss") end
            if addon.ApplyBossCastBarFor then addon.ApplyBossCastBarFor() end
            if addon.ApplyBossHighLevelIconVisibility then addon.ApplyBossHighLevelIconVisibility() end
        end)
        -- Small follow-up pass to catch late Boss frame construction.
        C_Timer.After(0.1, function()
            if addon.ApplyUnitFrameBarTexturesFor then addon.ApplyUnitFrameBarTexturesFor("Boss") end
            if addon.ApplyBossCastBarFor then addon.ApplyBossCastBarFor() end
        end)
    else
        if addon.ApplyUnitFrameBarTexturesFor then addon.ApplyUnitFrameBarTexturesFor("Boss") end
        if addon.ApplyUnitFrameHealthTextVisibilityFor then addon.ApplyUnitFrameHealthTextVisibilityFor("Boss") end
        if addon.ApplyUnitFramePowerTextVisibilityFor then addon.ApplyUnitFramePowerTextVisibilityFor("Boss") end
        if addon.ApplyBossCastBarFor then addon.ApplyBossCastBarFor() end
        if addon.ApplyBossHighLevelIconVisibility then addon.ApplyBossHighLevelIconVisibility() end
    end
end

function addon:UPDATE_BOSS_FRAMES()
    -- IMPORTANT: Call preemptive hide BEFORE combat check to ensure ReputationColor
    -- (and other visual elements) are hidden immediately, even during combat.
    -- SetAlpha via pcall is safe during combat and won't cause taint.
    if addon.PreemptiveHideBossElements then
        addon.PreemptiveHideBossElements()
    end

    -- Text visibility uses pcall(SetAlpha) which is combat-safe (same as PreemptiveHide).
    if addon.ApplyUnitFrameHealthTextVisibilityFor then addon.ApplyUnitFrameHealthTextVisibilityFor("Boss") end
    if addon.ApplyUnitFramePowerTextVisibilityFor then addon.ApplyUnitFramePowerTextVisibilityFor("Boss") end

    -- Keep this lightweight: boss frames can update frequently during encounters.
    if InCombatLockdown and InCombatLockdown() then
        self._pendingApplyStyles = true
        return
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            if addon.ApplyUnitFrameBarTexturesFor then addon.ApplyUnitFrameBarTexturesFor("Boss") end
            if addon.ApplyUnitFrameHealthTextVisibilityFor then addon.ApplyUnitFrameHealthTextVisibilityFor("Boss") end
            if addon.ApplyUnitFramePowerTextVisibilityFor then addon.ApplyUnitFramePowerTextVisibilityFor("Boss") end
            if addon.ApplyBossCastBarFor then addon.ApplyBossCastBarFor() end
            if addon.ApplyBossHighLevelIconVisibility then addon.ApplyBossHighLevelIconVisibility() end
        end)
    else
        if addon.ApplyUnitFrameBarTexturesFor then addon.ApplyUnitFrameBarTexturesFor("Boss") end
        if addon.ApplyUnitFrameHealthTextVisibilityFor then addon.ApplyUnitFrameHealthTextVisibilityFor("Boss") end
        if addon.ApplyUnitFramePowerTextVisibilityFor then addon.ApplyUnitFramePowerTextVisibilityFor("Boss") end
        if addon.ApplyBossCastBarFor then addon.ApplyBossCastBarFor() end
        if addon.ApplyBossHighLevelIconVisibility then addon.ApplyBossHighLevelIconVisibility() end
    end
end

function addon:PLAYER_LEVEL_UP()
    -- Re-evaluate Rules when player levels up (for playerLevel trigger type)
    if self.Rules and self.Rules.OnPlayerLevelUp then
        self.Rules:OnPlayerLevelUp()
    end
end

function addon:EDIT_MODE_LAYOUTS_UPDATED()
    -- Use centralized sync function (if available)
    if addon.EditMode and addon.EditMode.RefreshSyncAndNotify then
        pcall(addon.EditMode.RefreshSyncAndNotify, "EDIT_MODE_LAYOUTS_UPDATED")
    end
    if self.Profiles and self.Profiles.RequestSync then
        self.Profiles:RequestSync("EDIT_MODE_LAYOUTS_UPDATED")
    end
    -- Invalidate scale multiplier baselines so they get recaptured with new Edit Mode scale
    if addon.OnUnitFrameScaleMultLayoutsUpdated then
        addon.OnUnitFrameScaleMultLayoutsUpdated()
    end
	-- Reapply container X-offset after Edit Mode has finished its repositioning
	if addon.OnUnitFrameOffscreenUnlockLayoutsUpdated then
		addon.OnUnitFrameOffscreenUnlockLayoutsUpdated()
	end
    -- Layout swaps made through Blizzard's own Edit Mode dropdown bypass our profile
    -- callbacks entirely, so re-assert per-bar enable state here too.
    if addon.ReconcileActionBarsEnabled then
        addon.ReconcileActionBarsEnabled("EDIT_MODE_LAYOUTS_UPDATED")
    end
    self:ApplyStyles()
end

function addon:PLAYER_SPECIALIZATION_CHANGED(event, unit)
    if unit and unit ~= "player" then
        return
    end
    if self.Profiles and self.Profiles.OnPlayerSpecChanged then
        self.Profiles:OnPlayerSpecChanged({ fromLogin = not not self._scootSpecLoginGuard })
    end
    if self.Rules and self.Rules.OnPlayerSpecChanged then
        self.Rules:OnPlayerSpecChanged()
    end
    self:ApplyStyles()
end

-- Attach copy button to TableAttributeDisplay when debug tools load
function addon:ADDON_LOADED(event, name)
    if name == "Blizzard_DebugTools" then
        C_Timer.After(0, function()
            if addon.AttachTableInspectorCopyButton then
                addon.AttachTableInspectorCopyButton()
            end
        end)
    end
end

-- Expose the attribute dump logic for the slash command (implementation in debug.lua)
function addon:DumpTableAttributes()
    if addon.DumpTableAttributes then
        local success = addon.DumpTableAttributes()
        if not success then
            addon:Print("No Table Inspector window or highlight frame found to dump.")
        end
    else
        addon:Print("Debug module not loaded.")
    end
end
