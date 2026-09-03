-- base/core.lua - Component system: registration, state management, apply-styling orchestration
local addonName, addon = ...

addon.Components = addon.Components or {}
addon.ComponentInitializers = addon.ComponentInitializers or {}
addon.ComponentsUtil = addon.ComponentsUtil or {}

local FS = addon.FrameState

local function getState(frame)
    return FS.Get(frame)
end

local function getProp(frame, key)
    local st = FS.Get(frame)
    return st and st[key] or nil
end

local function setProp(frame, key, value)
    local st = FS.Get(frame)
    if st then
        st[key] = value
    end
end

local Util = addon.ComponentsUtil
local UNIT_FRAME_CATEGORY_TO_UNIT = {
    ufPlayer = "Player",
    ufTarget = "Target",
    ufFocus  = "Focus",
    ufPet    = "Pet",
}

local function CopyDefaultValue(value)
    if type(value) ~= "table" then
        return value
    end

    local copy = {}
    for k, v in pairs(value) do
        copy[k] = CopyDefaultValue(v)
    end
    return copy
end

-- The single source of truth for "what does this setting resolve to when the
-- profile stores nothing". Both the materialized-table metatable and the
-- zero-touch proxy read through here so the two can never disagree.
--
-- Returns the registration table's value BY REFERENCE for table defaults.
-- Callers may read it but must never mutate it -- writes go through
-- addon:EnsureComponentSubTable, which seeds a copy.
local function registeredDefault(component, key)
    local settings = component and component.settings
    local meta = settings and settings[key]
    if type(meta) == "table" then
        return meta.default
    end
end

-- Metatable fallback: unset keys return their registered defaults.
local function attachSettingsDefaults(db, component)
    if not db or not component then return end
    if not component.settings then return end
    if getmetatable(db) then return end  -- don't clobber proxy's metatable
    setmetatable(db, {
        __index = function(_, key)
            return registeredDefault(component, key)
        end,
    })
end

-- Most components persist into profile.components. A component that carries
-- GetContainer owns its storage instead, keyed by the same component id:
-- ScootAuras trackers are account-wide, so theirs live in
-- db.global.scootAuras.styling. `create` materializes the container; without it
-- nothing is written, which is what keeps zero-touch detection honest.
local function componentContainer(component, create)
    if component and component.GetContainer then
        local ok, container = pcall(component.GetContainer, create)
        if ok and type(container) == "table" then return container end
        return nil
    end
    local profile = addon.db and addon.db.profile
    if not profile then return nil end
    local components = rawget(profile, "components")
    if create and type(components) ~= "table" then
        components = {}
        profile.components = components
    end
    return components
end
addon.ComponentsUtil.GetContainerFor = componentContainer

-- Drops component tables with no content, then strips values that exactly match
-- a registered scalar default, so the rawget-based zero-touch guard keeps
-- working. Runs over any container, not just profile.components.
local function pruneComponentContainer(container, registry)
    for id, tbl in pairs(container) do
        if type(tbl) == "table" then
            local hasContent = false
            for _, v in next, tbl do
                if type(v) ~= "table" then
                    hasContent = true
                    break
                end
                for _ in next, v do
                    hasContent = true
                    break
                end
                if hasContent then break end
            end
            if not hasContent then
                container[id] = nil
            end
        end
    end

    for id, tbl in pairs(container) do
        if type(tbl) == "table" then
            local comp = registry[id]
            if comp and comp.settings then
                for key, value in pairs(tbl) do
                    local def = comp.settings[key]
                    if type(def) == "table" and def.default ~= nil
                       and type(def.default) ~= "table" and value == def.default then
                        tbl[key] = nil
                    end
                end
                -- Strip position values — ephemeral mirrors of the frame's
                -- Edit Mode position, re-derived every EDIT_MODE_LAYOUTS_UPDATED
                -- via SyncComponentPositionFromEditMode. They must not keep a
                -- component table alive and defeat zero-touch detection.
                if rawget(tbl, "positionX") ~= nil then tbl.positionX = nil end
                if rawget(tbl, "positionY") ~= nil then tbl.positionY = nil end
                if next(tbl) == nil then
                    container[id] = nil
                end
            end
        end
    end
end

local Component = {}
Component.__index = Component

function Component:New(o)
    o = o or {}
    return setmetatable(o, self)
end

function Component:SyncEditModeSettings()
    local frame = _G[self.frameName]
    if not frame then return end

    -- Zero-Touch: don't back-sync settings for unconfigured components.
    -- Writing to a proxy DB materializes the real table, which would cause
    -- ApplyStyling to run for a component the user never configured.
    if addon.IsComponentUnconfigured(self) then return end

    local changed = false
    for settingId, setting in pairs(self.settings) do
        if type(setting) == "table" and setting.type == "editmode" then
            if addon.EditMode.SyncEditModeSettingToComponent(self, settingId) then
                changed = true
            end
        end
    end

    return changed
end

-- Event API (refactor #33): thin forwards to addon.Events, owner-keyed by the
-- stable string id so InitializeComponents' wipe-and-rerun tears down the old
-- generation's registrations. Handlers fire even for UNCONFIGURED components:
-- the Zero-Touch gate belongs to styling call sites (ApplyStyles below,
-- RefreshOpacityState in core/init.lua), not to event delivery, because hook
-- installers must run pre-config. A handler that styles must self-guard:
--   if self.db == self._ScootDBProxy then return end
function Component:On(event, handler)
    addon.Events._MarkComponentOwner(self.id)
    local component = self
    return addon.Events.On(self.id, event, function(...)
        handler(component, ...)
    end)
end

function Component:Once(event, handler)
    addon.Events._MarkComponentOwner(self.id)
    local component = self
    return addon.Events.Once(self.id, event, function(...)
        handler(component, ...)
    end)
end

function Component:RunOutOfCombat(fn, key)
    return addon.Events.RunOutOfCombat(fn, key and (self.id .. ":" .. key) or nil)
end

addon.ComponentPrototype = Component

function addon:RegisterComponent(component)
    -- Sub-toggle gate: skip individual components disabled within an enabled category
    local cat = self:GetComponentCategory(component.id)
    if cat and not self:IsModuleEnabled(cat, component.id) then
        return
    end
    self.Components[component.id] = component
end

function addon:RegisterComponentInitializer(initializer, category)
    if type(initializer) ~= "function" then return end
    table.insert(self.ComponentInitializers, { fn = initializer, category = category })
end

function addon:InitializeComponents()
    if wipe then
        wipe(self.Components)
    else
        self.Components = {}
    end

    -- Tear down the previous generation's Component:On registrations before the
    -- initializers re-run; otherwise orphaned handlers keep firing on the old
    -- component tables.
    if self.Events and self.Events.ResetComponentOwners then
        self.Events.ResetComponentOwners()
    end

    for _, entry in ipairs(self.ComponentInitializers) do
        if type(entry) == "function" then
            -- Legacy format (no category) — always run
            pcall(entry, self)
        else
            local cat = entry.category
            if not cat or self:IsModuleEnabled(cat) then
                pcall(entry.fn, self)
            end
        end
    end
end

function addon:LinkComponentsToDB()
    -- Zero-Touch: only assign pre-existing persisted tables.
    local profile = self.db and self.db.profile
    local components = profile and rawget(profile, "components") or nil

    -- Every distinct container backing a registered component. Components that
    -- own their storage (ScootAuras trackers) must be pruned and linked too, or
    -- their saved styling reads as "nothing persisted" and resolves to defaults.
    local containers = {}
    if components then containers[components] = true end
    for _, component in pairs(self.Components) do
        if component.GetContainer then
            local owned = componentContainer(component, false)
            if owned then containers[owned] = true end
        end
    end

    -- Auto-prune empty component tables left by prior materialization bugs, then
    -- strip AceDB-materialized default values.
    -- GetDefaults() previously registered scalar defaults for all component
    -- settings, causing AceDB's copyDefaults to write them into profile tables
    -- via rawset. This defeated rawget-based zero-touch detection, causing
    -- ApplyStyling to run for components the user never configured.
    for container in pairs(containers) do
        pruneComponentContainer(container, self.Components)
    end

    if components and next(components) == nil then
        rawset(profile, "components", nil)
        components = nil
    end

    -- Auto-prune empty profile-level settings tables.
    if profile then
        for _, key in ipairs({"actionBarSettings", "prdSettings", "damageMeterSettings", "cdmQoL", "qol"}) do
            local t = rawget(profile, key)
            if t and type(t) == "table" then
                if next(t) == nil then
                    rawset(profile, key, nil)
                end
            end
        end
    end

    for _, component in pairs(self.Components) do
        self:LinkComponent(component, components)
    end
end

--- Points one component at its persisted settings table, or at a defaults proxy
-- when nothing is persisted. Split out of LinkComponentsToDB so a component
-- registered mid-session can be linked without materializing anything, which
-- EnsureComponentDB would do.
function addon:LinkComponent(component, profileComponents)
    local id = component and component.id
    if not id then return end
    do
        local container
        if component.GetContainer then
            container = componentContainer(component, false)
        elseif profileComponents ~= nil then
            container = profileComponents
        else
            local profile = self.db and self.db.profile
            container = profile and rawget(profile, "components") or nil
        end
        local persisted = container and rawget(container, id) or nil
        if persisted then
            component.db = persisted
            attachSettingsDefaults(persisted, component)
        else
            -- Proxy: nothing is persisted, so reads resolve to the registered
            -- defaults and the first write materializes the real table.
            --
            -- Resolving defaults here is what makes a fresh profile render the
            -- same as a configured one. Without it, styling code reads nil and
            -- silently substitutes its own hardcoded fallback (historically
            -- FRIZQT__), so any feature whose intended default is a bundled
            -- Scoot font rendered in Friz Quadrata until the user touched the
            -- setting -- while the settings panel, which falls back to the real
            -- default for display, insisted the correct font was already set.
            if not component._ScootDBProxy then
                local proxy = {}
                setmetatable(proxy, {
                    __index = function(_, key)
                        local real = component.db
                        if real and real ~= proxy then
                            return real[key]
                        end
                        return registeredDefault(component, key)
                    end,
                    __newindex = function(_, key, value)
                        local realDb = addon:EnsureComponentDB(component)
                        if realDb then
                            rawset(realDb, key, value)
                        end
                    end,
                    __pairs = function()
                        local real = component.db
                        if real and real ~= proxy then
                            return pairs(real)
                        end
                        return function() return nil end
                    end,
                })
                component._ScootDBProxy = proxy
            end
            component.db = component._ScootDBProxy
        end
    end
end

-- Zero-Touch predicate: true while nothing is persisted for the component and
-- its db is still the defaults proxy above. Guards must not write through the
-- proxy, which would materialize the real table and activate styling.
function addon.IsComponentUnconfigured(component)
    return component ~= nil
        and component._ScootDBProxy ~= nil
        and component.db == component._ScootDBProxy
end

-- Read one setting from a component's database. The live component's db
-- resolves registered defaults through the proxy __index; the
-- profile.components fallback (component not registered yet) is a raw read
-- and returns nil for unset keys instead of the registered default.
function addon.GetComponentSetting(componentId, key)
    local comp = addon.Components and addon.Components[componentId]
    if comp and comp.db then
        return comp.db[key]
    end
    local profile = addon.db and addon.db.profile
    local components = profile and profile.components
    return components and components[componentId] and components[componentId][key]
end

function addon:EnsureComponentDB(componentOrId)
    local component = componentOrId
    if type(componentOrId) == "string" then
        component = self.Components and self.Components[componentOrId]
    end
    if not component or not component.id then
        return nil
    end
    local components = componentContainer(component, true)
    if type(components) ~= "table" then
        return nil
    end
    local db = rawget(components, component.id)
    if type(db) ~= "table" then
        db = {}
        components[component.id] = db
    end
    component.db = db
    attachSettingsDefaults(db, component)
    return db
end

-- Read a settings sub-table (textNames, textStacks, ...) resolved against its
-- registered default, so a PARTIAL stored table still yields every sibling
-- property.
--
-- Partial tables are not hypothetical: the old write path stored a bare `{}`
-- through the zero-touch proxy and then set only the edited key, permanently
-- dropping every sibling. Those profiles are already on disk, so styling code
-- must heal them at read time -- EnsureComponentSubTable only stops new ones.
--
-- Allocates only when the stored table really is partial; the common cases
-- (nothing stored, or a complete table) return an existing table as-is.
function addon:ResolveComponentSubTable(component, key)
    local def = registeredDefault(component, key)
    local db = component and component.db
    local stored = db and rawget(db, key) or nil

    if type(stored) ~= "table" then
        return def
    end
    if type(def) ~= "table" then
        return stored
    end

    local merged
    for k, v in pairs(def) do
        if stored[k] == nil then
            merged = merged or CopyDefaultValue(stored)
            merged[k] = CopyDefaultValue(v)
        end
    end
    return merged or stored
end

-- Materialize a settings sub-table for WRITING, seeded from a copy of the
-- registered default.
--
-- Replaces the `comp.db.textX = comp.db.textX or {}` idiom, which was wrong
-- both ways: through the proxy it wrote a bare `{}` that shadowed the default
-- and lost every sibling key, and through the defaults metatable it aliased
-- the registration table itself into the profile -- so the next `[k] = v`
-- mutated comp.settings[key].default for every other profile in the session
-- and serialized the result into SavedVariables.
function addon:EnsureComponentSubTable(componentOrId, key)
    local db = self:EnsureComponentDB(componentOrId)
    if not db then return nil end

    local existing = rawget(db, key)
    if type(existing) == "table" then
        return existing
    end

    local component = componentOrId
    if type(componentOrId) == "string" then
        component = self.Components and self.Components[componentOrId]
    end

    local def = registeredDefault(component, key)
    local seeded = (type(def) == "table") and CopyDefaultValue(def) or {}
    rawset(db, key, seeded)
    return seeded
end

function addon:ClearFrameLevelState()
    -- Best-effort cleanup on profile switch. Clears hook flags so hidden states
    -- stop being enforced (full restore requires reload).
    local function safeAlpha(fs)
        if fs and fs.SetAlpha then pcall(fs.SetAlpha, fs, 1) end
    end
    local function clearTextFlags(fs)
        if not fs then return end
        -- Clear FrameState hidden flags
        local fstate = FS
        if fstate then
            fstate.SetHidden(fs, "healthText", false)
            fstate.SetHidden(fs, "powerText", false)
            fstate.SetHidden(fs, "healthTextCenter", false)
            fstate.SetHidden(fs, "powerTextCenter", false)
            fstate.SetHidden(fs, "totName", false)
            fstate.SetHidden(fs, "altPowerText", false)
        end
        safeAlpha(fs)
    end

    if self._ufHealthTextFonts then
        for _, cache in pairs(self._ufHealthTextFonts) do
            clearTextFlags(cache and cache.leftFS)
            clearTextFlags(cache and cache.rightFS)
            clearTextFlags(cache and cache.textStringFS)
        end
    end
    if self._ufPowerTextFonts then
        for _, cache in pairs(self._ufPowerTextFonts) do
            clearTextFlags(cache and cache.leftFS)
            clearTextFlags(cache and cache.rightFS)
            clearTextFlags(cache and cache.textStringFS)
        end
    end

    clearTextFlags(_G.PlayerFrameHealthBarTextLeft)
    clearTextFlags(_G.PlayerFrameHealthBarTextRight)
    clearTextFlags(_G.PlayerFrameManaBarTextLeft)
    clearTextFlags(_G.PlayerFrameManaBarTextRight)
    clearTextFlags(_G.PetFrameHealthBarTextLeft)
    clearTextFlags(_G.PetFrameHealthBarTextRight)
    clearTextFlags(_G.PetFrameManaBarTextLeft)
    clearTextFlags(_G.PetFrameManaBarTextRight)

    -- Empty these rather than nil them out. Several consumers guard their container
    -- once at load time (inside a `do` block) and index it directly thereafter, so
    -- removing the table entirely makes every later apply error on a nil index.
    self._ufTextBaselines = {}
    self._ufPowerTextBaselines = {}
    self._ufNameLevelTextBaselines = {}
    self._ufNameContainerBaselines = {}
    self._ufNameBackdropBaseWidth = {}
    self._ufToTNameTextBaseline = {}

    self._ufHealthTextFonts = {}
    self._ufPowerTextFonts = {}
end

function addon:ApplyStyles()
    -- CRITICAL: Styling during combat taints protected frames ("blocked from an action").
    if InCombatLockdown and InCombatLockdown() then
        -- Cast bar hooks are visual-only and safe during combat.
        if addon.EnsureAllUnitFrameCastBarHooks then
            addon.EnsureAllUnitFrameCastBarHooks()
        end
        if not self._pendingApplyStyles then
            self._pendingApplyStyles = true
            self:RegisterEvent("PLAYER_REGEN_ENABLED")
        end
        return
    end
    for _, component in pairs(self.Components) do
        -- Zero-Touch: skip unconfigured components. A proxy db is exactly the
        -- state LinkComponentsToDB leaves behind when nothing is persisted, and
        -- unlike a profile.components lookup it holds for components that own
        -- their storage.
        local hasConfig = component.db ~= nil and not addon.IsComponentUnconfigured(component)
        if hasConfig and component.ApplyStyling then
            component:ApplyStyling()
        end
    end
    if self:IsModuleEnabled("unitFrames") then
        if addon.ApplyAllUnitFrameHealthTextVisibility then
            addon.ApplyAllUnitFrameHealthTextVisibility()
        end
        if addon.ApplyAllUnitFramePowerTextVisibility then
            addon.ApplyAllUnitFramePowerTextVisibility()
        end
        if addon.ApplyAllUnitFrameNameLevelText then
            addon.ApplyAllUnitFrameNameLevelText()
        end
        if addon.ApplyAllUnitFrameBarTextures then
            addon.ApplyAllUnitFrameBarTextures()
        end
        if addon.ApplyAllUnitFramePortraits then
            addon.ApplyAllUnitFramePortraits()
        end
        if addon.ApplyAllUnitFrameClassResources then
            addon.ApplyAllUnitFrameClassResources()
        end
        if addon.ApplyAllUnitFrameCastBars then
            addon.ApplyAllUnitFrameCastBars()
        end
        if addon.ApplyAllUnitFrameBuffsDebuffs then
            addon.ApplyAllUnitFrameBuffsDebuffs()
        end
        if addon.ApplyAllUnitFrameVisibility then
            addon.ApplyAllUnitFrameVisibility()
        end
        if addon.ApplyAllThreatMeterVisibility then
            addon.ApplyAllThreatMeterVisibility()
        end
        if addon.ApplyTargetBossIconVisibility then
            addon.ApplyTargetBossIconVisibility()
        end
        if addon.ApplyBossHighLevelIconVisibility then
            addon.ApplyBossHighLevelIconVisibility()
        end
        if addon.ApplyAllPlayerMiscVisibility then
            addon.ApplyAllPlayerMiscVisibility()
        end
        if addon.ApplyPetFrameVisibility then
            addon.ApplyPetFrameVisibility()
        end
        -- Unit Frames: Off-screen drag unlock (Player + Target)
        if addon.ApplyAllUnitFrameOffscreenUnlocks then
            addon.ApplyAllUnitFrameOffscreenUnlocks()
        end
        if addon.ApplyAllUnitFrameScaleMults then
            addon.ApplyAllUnitFrameScaleMults()
        end
        -- ToT/FocusTarget: Apply scale and position (not Edit Mode managed)
        if addon.ApplyAllToTSettings then
            addon.ApplyAllToTSettings()
        end
        if addon.ApplyAllFocusTargetSettings then
            addon.ApplyAllFocusTargetSettings()
        end
    end
    -- Group Frames: Raid
    if addon:IsModuleEnabled("groupFrames", "raid") then
        if addon.ApplyRaidFrameHealthBarStyle then
            addon.ApplyRaidFrameHealthBarStyle()
        end
        if addon.ApplyRaidFrameStatusTextStyle then
            addon.ApplyRaidFrameStatusTextStyle()
        end
        if addon.ApplyRaidFrameGroupTitlesStyle then
            addon.ApplyRaidFrameGroupTitlesStyle()
        end
        if addon.ApplyRaidFrameHealthOverlays then
            addon.ApplyRaidFrameHealthOverlays()
        end
        if addon.ApplyRaidFrameNameOverlays then
            addon.ApplyRaidFrameNameOverlays()
        end
        if addon.ApplyRaidFrameHealthBarBorders then
            addon.ApplyRaidFrameHealthBarBorders()
        end
    end
    -- Group Frames: Party
    if addon:IsModuleEnabled("groupFrames", "party") then
        if addon.ApplyPartyFrameHealthBarStyle then
            addon.ApplyPartyFrameHealthBarStyle()
        end
        if addon.ApplyPartyFrameTitleStyle then
            addon.ApplyPartyFrameTitleStyle()
        end
        if addon.ApplyPartyFrameHealthOverlays then
            addon.ApplyPartyFrameHealthOverlays()
        end
        if addon.ApplyPartyFrameNameOverlays then
            addon.ApplyPartyFrameNameOverlays()
        end
        if addon.ApplyPartyOverAbsorbGlowVisibility then
            addon.ApplyPartyOverAbsorbGlowVisibility()
        end
        if addon.ApplyPartyFrameHealthBarBorders then
            addon.ApplyPartyFrameHealthBarBorders()
        end
    end
end

function addon:ApplyEarlyComponentStyles()
    for _, component in pairs(self.Components) do
        local hasConfig = component.db ~= nil and not addon.IsComponentUnconfigured(component)
        if hasConfig and component.ApplyStyling and component.applyDuringInit then
            component:ApplyStyling()
        end
    end
end

function addon:ResetComponentToDefaults(componentOrId)
    local component = componentOrId
    if type(componentOrId) == "string" then
        component = self.Components and self.Components[componentOrId]
    end

    if not component then
        return false, "component_missing"
    end

    if not component.db then
        if type(self.EnsureComponentDB) == "function" then
            self:EnsureComponentDB(component)
        end
    end

    if not component.db then
        return false, "component_db_unavailable"
    end

    local seen = {}
    for settingId, setting in pairs(component.settings or {}) do
        if type(setting) == "table" then
            seen[settingId] = true
            if setting.default ~= nil then
                if type(setting.default) == "table" then
                    component.db[settingId] = nil  -- Clear to nil; metatable provides default for reads
                else
                    component.db[settingId] = CopyDefaultValue(setting.default)
                end
            else
                component.db[settingId] = nil
            end
        end
    end

    for key in pairs(component.db) do
        if not seen[key] then
            component.db[key] = nil
        end
    end

    if self.EditMode and self.EditMode.ResetComponentPositionToDefault then
        self.EditMode.ResetComponentPositionToDefault(component)
    end

    if self.EditMode and self.EditMode.SyncComponentToEditMode then
        self.EditMode.SyncComponentToEditMode(component, { skipApply = true })
    end

    if self.ApplyStyles then
        self:ApplyStyles()
    end

    return true
end

function addon:ResetUnitFrameCategoryToDefaults(categoryKey)
    if type(categoryKey) ~= "string" then
        return false, "invalid_category"
    end

    local unit = UNIT_FRAME_CATEGORY_TO_UNIT[categoryKey]
    if not unit then
        return false, "unknown_unit"
    end

    local profile = self.db and self.db.profile
    if not profile then
        return false, "db_unavailable"
    end

    if profile.unitFrames then
        profile.unitFrames[unit] = nil
        local hasAny = false
        for _ in pairs(profile.unitFrames) do
            hasAny = true
            break
        end
        if not hasAny then
            profile.unitFrames = nil
        end
    end

    if self.EditMode and self.EditMode.ResetUnitFramePosition then
        self.EditMode.ResetUnitFramePosition(unit)
    end

    if self.ApplyUnitFrameBarTexturesFor then
        self.ApplyUnitFrameBarTexturesFor(unit)
    end
    if self.ApplyUnitFrameHealthTextVisibilityFor then
        self.ApplyUnitFrameHealthTextVisibilityFor(unit)
    end
    if self.ApplyUnitFramePowerTextVisibilityFor then
        self.ApplyUnitFramePowerTextVisibilityFor(unit)
    end
    if self.ApplyUnitFrameNameLevelTextFor then
        self.ApplyUnitFrameNameLevelTextFor(unit)
    end
    if self.ApplyUnitFramePortraitFor then
        self.ApplyUnitFramePortraitFor(unit)
    end
    if self.ApplyUnitFrameCastBarFor then
        self.ApplyUnitFrameCastBarFor(unit)
    end
    if self.ApplyUnitFrameBuffsDebuffsFor then
        self.ApplyUnitFrameBuffsDebuffsFor(unit)
    end
    if self.ApplyUnitFrameVisibilityFor then
        self.ApplyUnitFrameVisibilityFor(unit)
    end

    return true
end

function addon:SyncAllEditModeSettings()
    local anyChanged = false
    for _, component in pairs(self.Components) do
        if component.SyncEditModeSettings then
            if component:SyncEditModeSettings() then
                anyChanged = true
            end
        end
        if addon.EditMode.SyncComponentPositionFromEditMode then
            if addon.EditMode.SyncComponentPositionFromEditMode(component) then
                anyChanged = true
            end
        end
    end

    return anyChanged
end

addon.ComponentsUtil._getState = getState
addon.ComponentsUtil._getProp = getProp
addon.ComponentsUtil._setProp = setProp
