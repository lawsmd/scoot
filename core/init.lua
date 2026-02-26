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
    -- 1. Define components and populate self.Components
    self:InitializeComponents()
    
    -- Explicitly require the new ScrollingCombatText component file (if loaded via TOC, this is handled)
    -- but we ensure its initializer runs if it used the RegisterComponent pattern


    -- One-time migration: ScooterModDB → ScootDB
    if ScooterModDB and not ScootDB then
        ScootDB = ScooterModDB
        ScooterModDB = nil
    end

    -- 2. Create the database, using the component list to build defaults
    self.db = LibStub("AceDB-3.0"):New("ScootDB", self:GetDefaults(), true)

    -- Migrate legacy "tui" prefixed global keys to new names (one release cycle)
    if self.db and self.db.global then
        local g = self.db.global
        if g.tuiAccentColor and not g.accentColor then
            g.accentColor = g.tuiAccentColor
        end
        if g.tuiWindowPosition and not g.windowPosition then
            g.windowPosition = g.tuiWindowPosition
        end
        if g.tuiWindowSize and not g.windowSize then
            g.windowSize = g.tuiWindowSize
        end
        -- Keep old keys for one release cycle, then remove in a follow-up
    end

    -- Migrate profile-level keys: scooterModButtonSeparate → scootButtonSeparate, scooterProfile → scootProfile
    if self.db and self.db.sv and self.db.sv.profiles then
        for _, profileData in pairs(self.db.sv.profiles) do
            -- Minimap component setting
            if profileData.components and profileData.components.minimapStyle then
                local mm = profileData.components.minimapStyle
                if mm.scooterModButtonSeparate ~= nil and mm.scootButtonSeparate == nil then
                    mm.scootButtonSeparate = mm.scooterModButtonSeparate
                    mm.scooterModButtonSeparate = nil
                end
            end
            -- Preset profile snapshot key
            if profileData.scooterProfile ~= nil and profileData.scootProfile == nil then
                profileData.scootProfile = profileData.scooterProfile
                profileData.scooterProfile = nil
            end
        end
    end

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

    -- Apply pending preset activation (set during preset import).
    -- This runs on the next load to avoid "Interface action failed because of an AddOn"
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

    -- Migrate legacy iconWidth/iconHeight to tallWideRatio for all applicable components
    self:MigrateIconWidthHeightToRatio()

    -- Migrate legacy pixel-based barWidth to new Edit Mode percentage scale
    do
        local profile = self.db and self.db.profile
        local trackedBarsDb = profile and profile.components and profile.components.trackedBars
        if trackedBarsDb and trackedBarsDb.barWidth then
            local old = tonumber(trackedBarsDb.barWidth)
            if old and old > 49 then
                -- Old values were pixels (120-480, default 220)
                -- Convert to approximate percentage: old / 220 * 100
                local pct = math.floor((old / 220) * 100 + 0.5)
                if pct < 50 then pct = 50 elseif pct > 200 then pct = 200 end
                trackedBarsDb.barWidth = pct
            end
        end
    end

    -- Clean up stale centerAnchor/centerAdditionalRows keys from Custom Groups
    do
        local profile = self.db and self.db.profile
        local components = profile and profile.components
        if components then
            for i = 1, 3 do
                local cgDb = components["customGroup" .. i]
                if cgDb then
                    cgDb.centerAnchor = nil
                    cgDb.centerAdditionalRows = nil
                end
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
    -- We must not prompt/reload in that phase; only live spec switches should prompt.
    self._scootSpecLoginGuard = true

    -- Initialize Edit Mode integration (hooks + compatibility flags).
    if self.EditMode and self.EditMode.Initialize then
        pcall(self.EditMode.Initialize)
    end

    self:RegisterEvents()
end

-- Migrate legacy iconWidth/iconHeight settings to tallWideRatio
-- This converts saved width/height pairs into the new unified ratio slider value
function addon:MigrateIconWidthHeightToRatio()
    if not self.db or not self.db.profile then return end
    local profile = self.db.profile

    -- Component IDs and their base sizes for migration
    local componentMigrations = {
        { id = "essentialCooldowns", baseSize = 50 },
        { id = "utilityCooldowns", baseSize = 30 },
        { id = "trackedBuffs", baseSize = 40 },
        { id = "buffs", baseSize = 30 },
        { id = "debuffs", baseSize = 30 },
    }

    -- Migrate component settings
    profile.components = profile.components or {}
    for _, info in ipairs(componentMigrations) do
        local compDb = profile.components[info.id]
        if compDb then
            local width = tonumber(compDb.iconWidth)
            local height = tonumber(compDb.iconHeight)
            -- Only migrate if iconWidth/iconHeight exist and tallWideRatio doesn't
            if width and height and compDb.tallWideRatio == nil then
                local ratio = 0
                if addon.IconRatio and addon.IconRatio.MigrateFromWidthHeight then
                    ratio = addon.IconRatio.MigrateFromWidthHeight(width, height, info.baseSize)
                end
                compDb.tallWideRatio = ratio
                compDb.iconWidth = nil
                compDb.iconHeight = nil
            end
        end
    end

    -- Migrate trackedBars icon settings (uses iconTallWideRatio instead)
    local trackedBarsDb = profile.components.trackedBars
    if trackedBarsDb then
        local width = tonumber(trackedBarsDb.iconWidth)
        local height = tonumber(trackedBarsDb.iconHeight)
        if width and height and trackedBarsDb.iconTallWideRatio == nil then
            local ratio = 0
            if addon.IconRatio and addon.IconRatio.MigrateFromWidthHeight then
                ratio = addon.IconRatio.MigrateFromWidthHeight(width, height, 30)
            end
            trackedBarsDb.iconTallWideRatio = ratio
            trackedBarsDb.iconWidth = nil
            trackedBarsDb.iconHeight = nil
        end
    end

    -- Migrate Unit Frame buffs/debuffs (Target and Focus)
    profile.unitFrames = profile.unitFrames or {}
    for _, unit in ipairs({ "Target", "Focus" }) do
        local unitDb = profile.unitFrames[unit]
        if unitDb and unitDb.buffsDebuffs then
            local cfg = unitDb.buffsDebuffs
            -- UF buffs/debuffs didn't have iconWidth/iconHeight before, only iconScale
            -- But we add tallWideRatio support now - no migration needed, just ensure nil doesn't break
        end
    end
end

function addon:GetDefaults()
    local defaults = {
        global = {
            pendingPresetActivation = nil,
            pendingProfileActivation = nil,
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

    for id, component in pairs(self.Components) do
        defaults.profile.components[id] = {}
        local settings = component.settings or {}
        for settingId, setting in pairs(settings) do
            -- Some entries in component.settings are boolean flags or helper values rather than
            -- full setting descriptors. Only copy those that are tables with an explicit default.
            if type(setting) == "table" and setting.default ~= nil then
                defaults.profile.components[id][settingId] = setting.default
            end
        end
    end

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
-- This is safe to call during combat as SetAlpha is not a protected function
function addon:RefreshOpacityState()
    -- Update Unit Frame visibility/opacity
    if addon.ApplyAllUnitFrameVisibility then
        addon.ApplyAllUnitFrameVisibility()
    end
    -- Update all components that have opacity settings (CDM, Action Bars, Auras, etc.)
    for id, component in pairs(self.Components) do
        if component.ApplyStyling and component.settings then
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
                pcall(component.ApplyStyling, component)
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
    -- We *flag* pending work during combat so we always re-assert on PLAYER_REGEN_ENABLED.
    -- Experimental: we also allow in-combat alpha enforcement for PetFrameFlash to prevent
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
    
    -- NOTE: We previously had a method override on EditModeManagerFrame.NotifyChatOfLayoutChange
    -- to suppress incorrect layout announcements during spec switches. This was removed because
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
                    -- Record a stable baseline spec after login/reload so we can ignore
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
    -- This must happen BEFORE first target acquisition to prevent "first target flash".
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
    
    -- Enforce Pet overlay visibility immediately after initial styling.
    -- This ensures PetAttackModeTexture is hidden before the first frame renders if the
    -- player has a pet that's already in attack mode when logging in or reloading.
    if addon.UnitFrames_EnforcePetOverlays then
        addon.UnitFrames_EnforcePetOverlays()
    end
    
    -- Deferred reapply of Player textures to catch any Blizzard resets after initial apply
    -- This ensures textures persist even if Blizzard updates the frame after our initial styling
    if C_Timer and C_Timer.After and addon.ApplyUnitFrameBarTexturesFor then
        C_Timer.After(0.1, function()
            addon.ApplyUnitFrameBarTexturesFor("Player")
        end)
    end
    -- Deferred Pet overlay enforcement to catch Blizzard resets (PetFrame:Update runs after login).
    -- This ensures PetAttackModeTexture stays hidden even if Blizzard shows it after initial styling.
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
    local editModeActive = addon and addon.EditMode and addon.EditMode.IsEditModeActiveOrOpening
        and addon.EditMode.IsEditModeActiveOrOpening()
    if editModeActive then
        -- Defer all work to avoid taint propagation during Edit Mode
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function()
                self:RefreshOpacityState()
            end)
        end
        return
    end

    -- =========================================================================
    -- IMMEDIATE PRE-EMPTIVE HIDING (runs BEFORE Blizzard's TargetFrame_Update)
    -- =========================================================================
    -- This is the key to preventing visual "flash" of hidden elements.
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
    local editModeActive = addon and addon.EditMode and addon.EditMode.IsEditModeActiveOrOpening
        and addon.EditMode.IsEditModeActiveOrOpening()
    if editModeActive then
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function()
                if addon.ApplyUnitFrameBarTexturesFor then
                    addon.ApplyUnitFrameBarTexturesFor("Focus")
                end
            end)
        end
        return
    end

    -- =========================================================================
    -- IMMEDIATE PRE-EMPTIVE HIDING (runs BEFORE Blizzard's FocusFrame_Update)
    -- =========================================================================
    -- This is the key to preventing visual "flash" of hidden elements.
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
    end
end

function addon:UPDATE_BOSS_FRAMES()
    -- IMPORTANT: Call preemptive hide BEFORE combat check to ensure ReputationColor
    -- (and other visual elements) are hidden immediately, even during combat.
    -- SetAlpha via pcall is safe during combat and won't cause taint.
    if addon.PreemptiveHideBossElements then
        addon.PreemptiveHideBossElements()
    end

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
        end)
    else
        if addon.ApplyUnitFrameBarTexturesFor then addon.ApplyUnitFrameBarTexturesFor("Boss") end
        if addon.ApplyUnitFrameHealthTextVisibilityFor then addon.ApplyUnitFrameHealthTextVisibilityFor("Boss") end
        if addon.ApplyUnitFramePowerTextVisibilityFor then addon.ApplyUnitFramePowerTextVisibilityFor("Boss") end
        if addon.ApplyBossCastBarFor then addon.ApplyBossCastBarFor() end
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
