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
                "actionBars", "buffsDebuffs", "cooldownManager",
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

    -- Migration V5: prune settings whose features were replaced or removed.
    -- Every key listed here has no reader left in the addon, so it only bloats
    -- profiles and any preset exported from them. Runs on raw SavedVariables so
    -- the tables are pruned before AceDB wraps them.
    do
        local sv = _G["ScootDB"]
        if sv and not (sv.global and sv.global._retiredKeysPrunedV5) then
            -- The old TUI settings window; the current panel keeps its own
            -- windowPosition/windowSize.
            if type(sv.global) == "table" then
                sv.global.tuiWindowPosition = nil
                sv.global.tuiWindowSize = nil
            end

            -- Components retired outright — drop the whole stored table.
            local RETIRED_COMPONENTS = { "nameplatesUnit" }

            -- component id -> keys that component no longer reads.
            local RETIRED_COMPONENT_KEYS = {
                essentialCooldowns = { "alignGroupCenter" },
                utilityCooldowns   = { "alignGroupCenter" },
                trackedBuffs       = { "compactCenter" },
                minimapStyle       = { "clockAnchor" },
                tooltip            = { "textLine2", "textLine3", "textLine4",
                                       "textLine5", "textLine6", "textLine7" },
                damageMeter        = { "customTruncation", "namesFont", "namesFontStyle",
                                       "numbersFont", "useCustomBarBorder" },
            }
            -- The button-bar components all carried the same retired border switch.
            for i = 1, 8 do
                RETIRED_COMPONENT_KEYS["actionBar" .. i] = { "borderDisableAll" }
            end
            RETIRED_COMPONENT_KEYS.petBar = { "borderDisableAll" }

            -- Per-unit keys dropped from the Unit Frames schema.
            local RETIRED_UNIT_KEYS = {
                "frameSpacingYDelta", "healthvalueHidden", "healthBarOverlayHeightPct",
                "powerBarCustomPositionEnabled", "powerBarPosX", "powerBarPosY",
            }

            for _, profileData in pairs(sv.profiles or {}) do
                if type(profileData) == "table" then
                    profileData.keepFriendlyNameplatesDisabled = nil

                    local components = profileData.components
                    if type(components) == "table" then
                        for _, id in ipairs(RETIRED_COMPONENTS) do
                            components[id] = nil
                        end
                        for id, keys in pairs(RETIRED_COMPONENT_KEYS) do
                            local cfg = components[id]
                            if type(cfg) == "table" then
                                for _, key in ipairs(keys) do cfg[key] = nil end
                            end
                        end
                        -- Superseded by hideRealmNames at the component root.
                        local dmY = components.damageMeterV2
                        if type(dmY) == "table" and type(dmY.textNames) == "table" then
                            dmY.textNames.hideRealmName = nil
                        end
                        -- The stack text lost its backdrop tint.
                        local ess = components.essentialCooldowns
                        if type(ess) == "table" and type(ess.textStacks) == "table" then
                            ess.textStacks.backdropColor = nil
                        end
                    end

                    local uf = profileData.unitFrames
                    if type(uf) == "table" then
                        for _, unitCfg in pairs(uf) do
                            if type(unitCfg) == "table" then
                                for _, key in ipairs(RETIRED_UNIT_KEYS) do
                                    unitCfg[key] = nil
                                end
                                if type(unitCfg.castBar) == "table" then
                                    unitCfg.castBar.textFillEndCapStyle = nil
                                end
                            end
                        end
                    end

                    local gf = profileData.groupFrames
                    if type(gf) == "table" then
                        -- Aura Tracking was rebuilt onto groupFrames.auraTracking and
                        -- the spell list is re-picked there; the old table is dead.
                        gf.healerAuras = nil
                        for _, groupKey in ipairs({ "party", "raid" }) do
                            if type(gf[groupKey]) == "table" then
                                gf[groupKey].healthBarPadding = nil
                            end
                        end
                    end
                end
            end

            -- Spec assignments pointing at deleted profiles can never resolve, so
            -- drop them; then drop character tables that are left with nothing and
            -- belong to a character the addon has no profile key for (renamed or
            -- deleted). Characters still in profileKeys are always kept.
            if type(sv.char) == "table" then
                local profiles = type(sv.profiles) == "table" and sv.profiles or {}
                local profileKeys = type(sv.profileKeys) == "table" and sv.profileKeys or {}
                for charKey, charData in pairs(sv.char) do
                    if type(charData) == "table" then
                        local specProfiles = charData.specProfiles
                        local assignments = type(specProfiles) == "table" and specProfiles.assignments or nil
                        local remaining = 0
                        if type(assignments) == "table" then
                            for specId, profileName in pairs(assignments) do
                                if profiles[profileName] == nil then
                                    assignments[specId] = nil
                                else
                                    remaining = remaining + 1
                                end
                            end
                        end
                        if remaining == 0 and profileKeys[charKey] == nil then
                            sv.char[charKey] = nil
                        end
                    end
                end
            end

            if not sv.global then sv.global = {} end
            sv.global._retiredKeysPrunedV5 = true
        end
    end

    -- Migration V6: clear the saved variables left behind by the Class Auras
    -- system, deleted in full and replaced by ScootAuras. Nothing reads these
    -- keys any more, and the component pruner cannot reclaim them: its
    -- default-strip pass only runs for components that registered this session,
    -- so a table belonging to a deleted feature survives forever. Runs on raw
    -- SavedVariables, before AceDB wraps them, so it sees every profile.
    do
        local sv = _G["ScootDB"]
        if sv and not (sv.global and sv.global._classAurasRemovedV6) then
            for _, profileData in pairs(sv.profiles or {}) do
                if type(profileData) == "table" then
                    -- The whole store goes. Clearing only its entries would
                    -- leave an empty table behind for good: the pruner's
                    -- empty-profile-table pass works from a fixed key list that
                    -- never included this one.
                    profileData.classAuraPositions = nil

                    -- Match on the prefix. Listing the seven shipped aura ids
                    -- would miss any id introduced by a hand-edited profile or
                    -- an imported preset. scootAura_* tables are left alone:
                    -- another character's trackers are legitimately unregistered
                    -- on this one.
                    local components = profileData.components
                    if type(components) == "table" then
                        for id in pairs(components) do
                            if type(id) == "string" and id:sub(1, 10) == "classAura_" then
                                components[id] = nil
                            end
                        end
                    end

                    -- Migration V2 wrote this key as true into every profile it
                    -- touched, so it is persisted almost everywhere.
                    local moduleEnabled = profileData.moduleEnabled
                    if type(moduleEnabled) == "table" then
                        moduleEnabled.classAuras = nil
                    end
                end
            end

            if not sv.global then sv.global = {} end
            sv.global._classAurasRemovedV6 = true
        end
    end

    -- Migration V7: Personal Resource Display sizing moved from Scoot pixel values
    -- to Blizzard's native Edit Mode sliders (12.0.7 settings). Convert what a
    -- profile stored, then flag the profile so its explicit PRD mirror values get
    -- pushed into its Edit Mode layout once (personal_resource_display/editmode.lua
    -- consumes the flag on the first read pass with Edit Mode ready). Runs on raw
    -- SavedVariables, before AceDB wraps them, so it sees every profile.
    do
        local sv = _G["ScootDB"]
        if sv and not (sv.global and sv.global._prdNativeMirrorsV7) then
            local function clampRound(v, lo, hi, step)
                v = tonumber(v)
                if v == nil then return nil end
                step = step or 1
                v = lo + math.floor(((v - lo) / step) + 0.5) * step
                if v < lo then v = lo elseif v > hi then v = hi end
                return v
            end
            for _, profileData in pairs(sv.profiles or {}) do
                if type(profileData) == "table" then
                    local components = profileData.components
                    if type(components) == "table" then
                        local health = components.prdHealth
                        local power = components.prdPower
                        local touched = false

                        -- Health bar width (px of a 200 px default bar) -> PRD-wide
                        -- Bar Width percent (native BarWidth: 50..150 %, step 10).
                        if type(health) == "table" and type(health.barWidth) == "number" then
                            local pct = clampRound(health.barWidth / 200 * 100, 50, 150, 10)
                            components.prdGlobal = components.prdGlobal or {}
                            if pct ~= 100 then
                                components.prdGlobal.barWidth = pct
                            end
                            health.barWidth = nil
                            touched = true
                        end
                        -- Bar heights (px) -> native HealthBarHeight / PowerBarHeight (10..30 px).
                        if type(health) == "table" and type(health.barHeight) == "number" then
                            health.barHeight = clampRound(health.barHeight, 10, 30, 1)
                            touched = true
                        end
                        if type(power) == "table" and type(power.barHeight) == "number" then
                            power.barHeight = clampRound(power.barHeight, 10, 30, 1)
                            touched = true
                        end

                        -- Any PRD configuration at all (hides included, which the
                        -- applicators used to re-push on every apply) gets one push.
                        for id in pairs(components) do
                            if type(id) == "string" and id:sub(1, 3) == "prd" then
                                touched = true
                                break
                            end
                        end
                        if touched then
                            profileData.prdSettings = profileData.prdSettings or {}
                            profileData.prdSettings.pendingNativePush = true
                        end
                    end
                end
            end

            if not sv.global then sv.global = {} end
            sv.global._prdNativeMirrorsV7 = true
        end
    end

    -- Migration V8: ScootAuras moves from per-profile stores to one account-wide
    -- store. Auras used to belong to one character inside one profile, reachable
    -- from another character only by copying; now every character sees every
    -- aura and a per-record spec list decides where it loads.
    --
    -- Ids were allocated per profile, so profile A's tracker 3 and profile B's
    -- tracker 3 are different auras sharing an id, a styling key
    -- ("scootAura_3") and a position key ("t3"). Everything is renumbered into
    -- one id space; nothing can be carried over as-is. Duplicates across copied
    -- profiles survive as separate auras by decision.
    --
    -- Spec lists are not written here. Turning a class token into spec IDs needs
    -- class data that is not guaranteed at ADDON_LOADED, so records carry
    -- `_pendingSpecClass` and SAU.ResolvePendingSpecStamps finishes the job at
    -- PLAYER_ENTERING_WORLD (the V7 pendingNativePush precedent).
    do
        local sv = _G["ScootDB"]
        if sv and not (sv.global and sv.global._scootAurasAccountWideV8) then
            local names = {}
            for profileName in pairs(sv.profiles or {}) do
                if type(profileName) == "string" then
                    table.insert(names, profileName)
                end
            end
            table.sort(names)

            local merged = { nextId = 1, trackers = {}, groups = {}, styling = {}, positions = {} }
            local moved = 0

            for _, profileName in ipairs(names) do
                local profileData = sv.profiles[profileName]
                if type(profileData) == "table" then
                    local store = profileData.scootAuras
                    local components = profileData.components
                    local positions = profileData.scootAuraPositions
                    local owners = type(store) == "table" and store.owners or nil

                    -- oldId -> newId, shared between trackers and groups exactly
                    -- as the old id space was.
                    local remap = {}

                    local function claimId(oldId)
                        if remap[oldId] then return remap[oldId] end
                        local newId = merged.nextId
                        merged.nextId = newId + 1
                        remap[oldId] = newId
                        return newId
                    end

                    local function stampClass(record)
                        if type(record.specs) == "table" and #record.specs > 0 then return end
                        local ownerRec = owners and record.owner and owners[record.owner]
                        local class = type(ownerRec) == "table" and ownerRec.class or nil
                        record._pendingSpecClass = (type(class) == "string") and class or true
                    end

                    local function carry(oldId, newId, prefix)
                        if type(components) == "table" then
                            local styling = components["scootAura_" .. oldId]
                            if type(styling) == "table" then
                                merged.styling["scootAura_" .. newId] = styling
                            end
                        end
                        if type(positions) == "table" then
                            local perKey = positions[prefix .. oldId]
                            if type(perKey) == "table" then
                                merged.positions[prefix .. newId] = perKey
                            end
                        end
                    end

                    if type(store) == "table" then
                        -- Ids first, so group references resolve however the
                        -- pairs order falls out.
                        for oldId, record in pairs(store.trackers or {}) do
                            if type(record) == "table" then claimId(oldId) end
                        end
                        for oldGid, record in pairs(store.groups or {}) do
                            if type(record) == "table" then claimId(oldGid) end
                        end

                        for oldId, record in pairs(store.trackers or {}) do
                            if type(record) == "table" then
                                local newId = remap[oldId]
                                -- Before owner is cleared: the class token the
                                -- deferred spec stamp needs is looked up by it.
                                stampClass(record)
                                record.owner = nil
                                record.order = newId
                                if record.groupId ~= nil then
                                    record.groupId = remap[record.groupId]
                                end
                                merged.trackers[newId] = record
                                carry(oldId, newId, "t")
                                moved = moved + 1
                            end
                        end

                        for oldGid, record in pairs(store.groups or {}) do
                            if type(record) == "table" then
                                local newGid = remap[oldGid]
                                stampClass(record)
                                record.owner = nil
                                local order = {}
                                for _, memberId in ipairs(record.memberOrder or {}) do
                                    if remap[memberId] then
                                        table.insert(order, remap[memberId])
                                    end
                                end
                                record.memberOrder = order
                                merged.groups[newGid] = record
                                carry(oldGid, newGid, "g")
                                moved = moved + 1
                            end
                        end
                    end

                    profileData.scootAuras = nil
                    profileData.scootAuraPositions = nil
                    if type(components) == "table" then
                        for id in pairs(components) do
                            if type(id) == "string" and id:sub(1, 10) == "scootAura_" then
                                components[id] = nil
                            end
                        end
                    end
                end
            end

            if not sv.global then sv.global = {} end
            -- Zero-touch: an account that never built an aura gets no store.
            if moved > 0 then
                sv.global.scootAuras = merged
            end
            sv.global._scootAurasAccountWideV8 = true
        end
    end

    -- Migration V9: Deep Shadow becomes the Unit Frames Z house font style.
    -- Every UFZ text (name, health block, both power texts, level pair) is a
    -- Scoot-created FontString fed by Lua SetText, so the companion black copy
    -- works on all of them.
    --
    -- Unlike a component served by AceDB defaults, the UFZ per-unit DB
    -- materializes every declared default into the profile the first time a
    -- unit is touched (_EnsureUnitDB). A stored "SHADOWTHICKOUTLINE" is
    -- therefore indistinguishable from a hand-picked one, and changing the
    -- declared default alone would reach only fresh profiles. So rewrite the
    -- old default in place: a profile that chose any OTHER style keeps it.
    -- Runs on raw SavedVariables, before AceDB wraps them.
    do
        local sv = _G["ScootDB"]
        if sv and not (sv.global and sv.global._unitFramesZDeepShadowV9) then
            local STYLE_KEYS = { "style", "nameStyle", "powerStyle", "levelStyle" }
            for _, profileData in pairs(sv.profiles or {}) do
                if type(profileData) == "table" then
                    local units = profileData.unitFramesZUnits
                    if type(units) == "table" then
                        for _, cfg in pairs(units) do
                            if type(cfg) == "table" then
                                for _, key in ipairs(STYLE_KEYS) do
                                    if cfg[key] == "SHADOWTHICKOUTLINE" then
                                        cfg[key] = "DEEPSHADOWTHICKOUTLINE"
                                    end
                                end
                            end
                        end
                    end
                end
            end

            if not sv.global then sv.global = {} end
            sv.global._unitFramesZDeepShadowV9 = true
        end
    end

    -- Migration V10: the widget's opacity pair joins the addon.Opacity catalog
    -- (opacityCombat -> opacity, opacityOOC -> opacityOutOfCombat).
    -- Runs on raw SavedVariables, before AceDB wraps them.
    do
        local sv = _G["ScootDB"]
        if sv and not (sv.global and sv.global._widgetOpacityKeysV10) then
            for _, profileData in pairs(sv.profiles or {}) do
                if type(profileData) == "table" then
                    local components = profileData.components
                    local cfg = type(components) == "table" and components.widget or nil
                    if type(cfg) == "table" then
                        local RENAMED = { opacityCombat = "opacity", opacityOOC = "opacityOutOfCombat" }
                        for old, new in pairs(RENAMED) do
                            if cfg[new] == nil then cfg[new] = cfg[old] end
                            cfg[old] = nil
                        end
                    end
                end
            end

            if not sv.global then sv.global = {} end
            sv.global._widgetOpacityKeysV10 = true
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
    -- Order matters: RaidVisibility registers its GROUP_ROSTER_UPDATE handler
    -- here and RaidRosterOverlay registers its own just below; the event bus
    -- dispatches in registration order, and the overlay must read member-frame
    -- geometry only after visibility has mutated it.
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
            accentColorMode = "custom",  -- "custom" uses accentColor; "class" uses the player class color
            windowPosition = nil,  -- Saved as { point, relPoint, x, y }
            scootAuraEditorPosition = nil,  -- ScootAura editor window, same shape
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
                cooldownManager = false,
                damageMeter = false,
                extraAbilities = false,
                groupFrames = false,
                minimap = false,
                notes = false,
                objectiveTracker = false,
                prd = false,
                scootAuras = false,
                sct = false,
                tooltip = false,
                unitFrames = false,
                unitFramesZ = false,
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

-- Kept off addon.Events: fixed-order regen orchestration and unit-swap handlers that run addon.Refresh chains.
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
    -- Combat state changes for opacity updates (priority: In Combat > With Target > Out of Combat)
    self:RegisterEvent("PLAYER_REGEN_DISABLED")
    self:RegisterEvent("PLAYER_REGEN_ENABLED")
    
    -- Apply dropdown stepper fixes (function lives in ui_fixes.lua)
    if addon.UIFixes and addon.UIFixes.ApplyDropdownStepperFixes then
        addon.UIFixes.ApplyDropdownStepperFixes()
    end
end

-- Kept off addon.Refresh: registry-driven; walks addon.Components and refreshes each one that declares opacity.
-- Refresh opacity state for all elements affected by combat/target priority
-- Safe to call during combat as SetAlpha is not a protected function
function addon:RefreshOpacityState()
    -- Update Unit Frame visibility/opacity
    if addon.ApplyAllUnitFrameVisibility then
        addon.ApplyAllUnitFrameVisibility()
    end
    -- Unit Frames Z keeps its settings per-unit rather than in component
    -- settings, so the loop below never sees it -- explicit seam instead.
    if addon.UnitFramesZ and addon.UnitFramesZ.RefreshOpacity then
        addon.UnitFramesZ.RefreshOpacity()
    end
    -- The widget styles itself while unconfigured (module-enabled means
    -- visible), so the zero-touch skip below would strand its combat dimming.
    do
        local widget = self.Components and self.Components.widget
        if widget and addon.IsComponentUnconfigured(widget) and widget.RefreshOpacity then
            pcall(widget.RefreshOpacity, widget)
        end
    end
    -- Update all components that have opacity settings (CDM, Action Bars, Auras, etc.)
    for id, component in pairs(self.Components) do
        -- Zero-Touch: skip unconfigured components (still on proxy DB)
        if addon.IsComponentUnconfigured(component) then
            -- no-op: component not configured
        elseif (component.RefreshOpacity or component.ApplyStyling) and component.settings then
            -- Any catalog key (core/opacity.lua) or the objective tracker's
            -- compound key qualifies; a component with only a combat value
            -- still refreshes on a combat edge.
            local hasOpacity = addon.Opacity.DeclaresAny(component.settings) or
                component.settings.opacityInInstanceCombat
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

    -- Kept off addon.Refresh: login order is the one condition no static gate checks; timed re-asserts stay here.
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
    -- Ensures textures persist even if Blizzard updates the frame after the first styling
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
    C_Timer.After(0, function()
        addon.ApplyUnitFrameBarTexturesFor("Player")
        addon.Refresh.Run("unitSwap", "Target")
        self:RefreshOpacityState()

        C_Timer.After(0.1, function()
            addon.ApplyUnitFrameBarTexturesFor("Player")
        end)
    end)
end

function addon:PLAYER_FOCUS_CHANGED()
    -- =========================================================================
    -- EDIT MODE GUARD: Skip synchronous modifications during Edit Mode
    -- =========================================================================
    -- Same rationale as PLAYER_TARGET_CHANGED: Edit Mode triggers FocusUnit
    -- which fires PLAYER_FOCUS_CHANGED. Skip preemptive hiding to avoid taint.
    if addon.EditMode.IsEditModeActiveOrOpening() then
        if addon.RepColorTrace then addon.RepColorTrace("PFC", "bail: edit mode guard") end
        C_Timer.After(0, function()
            addon.ApplyUnitFrameBarTexturesFor("Focus")
        end)
        -- Self-heal for a transient guard false positive (see PLAYER_TARGET_CHANGED)
        C_Timer.After(0.5, function()
            if addon.EditMode.IsEditModeActiveOrOpening() then return end
            if addon.PreemptiveHideFocusElements then
                addon.PreemptiveHideFocusElements()
            end
        end)
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
    C_Timer.After(0, function()
        addon.Refresh.Run("unitSwap", "Focus")
    end)
end

-- Boss unit frames can appear/update without target/focus change events.
-- Re-apply styling after Blizzard updates boss units. Both events share one
-- handler; INSTANCE_ENCOUNTER_ENGAGE_UNIT adds a 0.1s follow-up pass to catch
-- late Boss frame construction.
local function onBossFramesChanged(self, event)
    -- IMPORTANT: Call preemptive hide BEFORE combat check to ensure ReputationColor
    -- (and other visual elements) are hidden immediately, even during combat.
    -- SetAlpha via pcall is safe during combat and won't cause taint.
    if addon.PreemptiveHideBossElements then
        addon.PreemptiveHideBossElements()
    end

    -- Text visibility uses pcall(SetAlpha) which is combat-safe (same as PreemptiveHide).
    addon.ApplyUnitFrameHealthTextVisibilityFor("Boss")
    addon.ApplyUnitFramePowerTextVisibilityFor("Boss")

    -- Boss unit frames can update during combat. Do not touch protected Boss frames during combat
    -- (even "cosmetic" changes) to avoid taint that can later block BossTargetFrameContainer:SetSize().
    if InCombatLockdown and InCombatLockdown() then
        self._pendingApplyStyles = true
        return
    end
    C_Timer.After(0, function()
        addon.Refresh.Run("unitBoss", "Boss")
    end)
    if event == "INSTANCE_ENCOUNTER_ENGAGE_UNIT" then
        C_Timer.After(0.1, function()
            addon.ApplyUnitFrameBarTexturesFor("Boss")
            addon.ApplyBossCastBarFor()
        end)
    end
end
addon.INSTANCE_ENCOUNTER_ENGAGE_UNIT = onBossFramesChanged
addon.UPDATE_BOSS_FRAMES = onBossFramesChanged

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
    -- Layout swaps made through Blizzard's own Edit Mode dropdown bypass the profile
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
