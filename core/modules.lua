-- modules.lua - Component-level module toggle system
local _, addon = ...

--------------------------------------------------------------------------------
-- X/Y/Z Variant Color Definitions
--------------------------------------------------------------------------------

addon.VARIANT_COLORS = {
    X = { 0.2, 0.9, 0.3 },   -- Green (Native)
    Y = { 1.0, 0.85, 0.1 },  -- Yellow (Modern)
    Z = { 0.3, 0.6, 1.0 },   -- Blue (Text)
}

--------------------------------------------------------------------------------
-- Component ID → Category Mapping
--------------------------------------------------------------------------------

local COMPONENT_TO_CATEGORY = {
    -- Action Bars
    actionBar1 = "actionBars", actionBar2 = "actionBars", actionBar3 = "actionBars",
    actionBar4 = "actionBars", actionBar5 = "actionBars", actionBar6 = "actionBars",
    actionBar7 = "actionBars", actionBar8 = "actionBars",
    microBar = "actionBars", stanceBar = "actionBars", petBar = "actionBars",
    -- Buffs/Debuffs
    buffs = "buffsDebuffs", debuffs = "buffsDebuffs",
    -- Cast Bars
    castBarZ = "castBars",
    -- Cooldown Manager
    essentialCooldowns = "cooldownManager", utilityCooldowns = "cooldownManager",
    trackedBuffs = "cooldownManager", trackedBars = "cooldownManager",
    customGroup1 = "cooldownManager", customGroup2 = "cooldownManager",
    customGroup3 = "cooldownManager", customGroup4 = "cooldownManager",
    customGroup5 = "cooldownManager",
    -- Damage Meter
    damageMeter = "damageMeter",
    damageMeterV2 = "damageMeter",
    -- Extra Abilities
    extraAbilities = "extraAbilities",
    -- Minimap
    minimapStyle = "minimap",
    -- Notes
    notes = "notes",
    -- Objective Tracker
    objectiveTracker = "objectiveTracker",
    -- Personal Resource Display
    prdGlobal = "prd", prdHealth = "prd", prdPower = "prd", prdClassResource = "prd",
    -- Scrolling Combat Text
    sctDamage = "sct",
    -- Tooltip
    tooltip = "tooltip",
    -- Widget (Reports launchpad)
    widget = "widget",
}

--- Returns the module category for a component ID.
--- Handles dynamic class aura IDs (classAura_*) via prefix check.
function addon:GetComponentCategory(componentId)
    if not componentId then return nil end
    local cat = COMPONENT_TO_CATEGORY[componentId]
    if cat then return cat end
    if componentId:sub(1, 10) == "classAura_" then
        return "classAuras"
    end
    return nil
end

--------------------------------------------------------------------------------
-- Category Definitions (for UI)
--------------------------------------------------------------------------------

addon.MODULE_CATEGORY_ORDER = {
    "actionBars",
    "bossWarnings",
    "buffsDebuffs",
    -- Not rendered on the Features page (hiddenFromFeatures) — it appears as a
    -- variant row inside Unit Frames. It stays in this list because init.lua
    -- builds the session module snapshot by walking it.
    "castBars",
    "classAuras",
    "cooldownManager",
    "damageMeter",
    "extraAbilities",
    "groupFrames",
    "minimap",
    "notes",
    "objectiveTracker",
    "prd",
    "widget",  -- label "Reports/Widget" — sorted alphabetically by label
    "sct",
    "tooltip",
    "unitFrames",
    -- Not rendered on the Features page (hiddenFromFeatures) — each Z-capable
    -- unit renders as a per-unit OFF/X/Z mode cycle inside Unit Frames (the
    -- modeCycle entries on unitFrames.subToggles). It stays in this list because
    -- init.lua builds the session module snapshot by walking it.
    "unitFramesZ",
}

addon.MODULE_CATEGORIES = {
    actionBars = {
        label = "Action Bars",
        noMasterToggle = true,
        subToggles = {
            { id = "actionBars18", label = "Action Bars 1-8",
              members = {"actionBar1","actionBar2","actionBar3","actionBar4",
                         "actionBar5","actionBar6","actionBar7","actionBar8"} },
            { id = "microBar", label = "Micro Bar" },
            { id = "petBar", label = "Pet Bar" },
            { id = "stanceBar", label = "Stance Bar" },
        },
    },
    bossWarnings = {
        label = "Boss Warnings",
    },
    buffsDebuffs = {
        label = "Buffs/Debuffs",
        noMasterToggle = true,
        subToggles = {
            { id = "buffs", label = "Buffs" },
            { id = "debuffs", label = "Debuffs" },
        },
    },
    castBars = {
        label = "Cast Bars",
        mutuallyExclusive = true,
        noMasterToggle = true,
        -- Rendered as a variant row inside Unit Frames rather than as a category
        -- of its own, because X is only ever in effect for unit frames that are
        -- enabled there. See the castBarsVariant entry under unitFrames.
        hiddenFromFeatures = true,
        -- There is no OFF here. Cast bars always exist; the only question is who
        -- draws them, so the selector cycles X -> Z -> X. X is the default that
        -- addon:IsCastBarXEnabled() assumes when nothing has been stored yet.
        subToggles = {
            -- castBarX has no component of its own: the X path lives inside the
            -- unit frame components and is read through addon:IsCastBarXEnabled().
            { id = "castBarX", label = "Cast Bars",
              variant = "X",
              versionBadge = { label = "X", title = "Cast Bar X", text = "Blizzard's own cast bars, restyled in place by Scoot. Each frame's cast bar settings live on that frame's page and only take effect while that unit frame is enabled above — with the frame off, its Cast Bar X customizations simply aren't applied." } },
            -- Z's sub-toggle id MUST equal the component id: addon:RegisterComponent
            -- gates on IsModuleEnabled(GetComponentCategory(id), id), so a mismatch
            -- makes the component silently never register.
            { id = "castBarZ", label = "Cast Bars",
              variant = "Z",
              versionBadge = { label = "Z", title = "Cast Bar Z", text = "Scoot's own cast bars, drawn as filling text instead of a bar. They stand alone: positioned freely in Edit Mode and configured on the Cast Bars page under Unit Frames." } },
        },
    },
    classAuras = {
        label = "Class Auras",
        -- No sub-toggles on Features page (dynamic per-class aura IDs)
    },
    cooldownManager = {
        label = "Cooldown Manager",
        noMasterToggle = true,
        subToggles = {
            { id = "essentialCooldowns", label = "Essential Cooldowns" },
            { id = "utilityCooldowns", label = "Utility Cooldowns" },
            { id = "trackedBuffs", label = "Tracked Buffs" },
            { id = "trackedBars", label = "Tracked Bars" },
            { id = "customGroups", label = "Custom Groups",
              members = {"customGroup1","customGroup2","customGroup3",
                         "customGroup4","customGroup5"} },
        },
    },
    damageMeter = {
        label = "Damage Meters",
        mutuallyExclusive = true, -- only one sub-toggle can be ON at a time
        noMasterToggle = true, -- no parent ON/OFF; master state derived from sub-toggles
        subToggles = {
            { id = "damageMeter", label = "Damage Meters",
              variant = "X",
              versionBadge = { label = "X", title = "Damage Meters X", text = "Reskins Blizzard's built-in damage meter frames. Heavily customized frames may result in taint errors during raid encounters, use with caution." } },
            { id = "damageMeterV2", label = "Damage Meters",
              variant = "Y",
              versionBadge = { label = "Y", title = "Damage Meters Y", text = "Custom frames that replace Blizzard's meter entirely. Multi-column and multi-window support." } },
        },
    },
    extraAbilities = {
        label = "Extra Abilities",
    },
    groupFrames = {
        label = "Group Frames",
        noMasterToggle = true,
        subToggles = {
            { id = "party", label = "Party" },
            { id = "raid", label = "Raid" },
            { id = "auraTracking", label = "Aura Tracking" },
        },
    },
    minimap = {
        label = "Minimap",
    },
    notes = {
        label = "Notes",
    },
    objectiveTracker = {
        label = "Objective Tracker",
    },
    prd = {
        label = "Personal Resource Display",
    },
    sct = {
        label = "Scrolling Combat Text",
    },
    tooltip = {
        label = "Tooltip",
    },
    widget = {
        label = "Reports/Widget",
    },
    unitFrames = {
        label = "Unit Frames",
        noMasterToggle = true,
        subToggles = {
            -- Player and Target are three-state rows: OFF / X (style Blizzard's
            -- frame, state in unitFrames.<unit>) / Z (Scoot-owned frame, state in
            -- unitFramesZ.<unit>). The modeCycle options carry which category+sub
            -- each mode reads and writes; the Features page clears every option's
            -- key and sets the chosen one, which is what keeps X and Z exclusive.
            { id = "Player", label = "Player",
              modeCycle = {
                { id = "X", variant = "X", category = "unitFrames", subId = "Player",
                  versionBadge = { label = "X", title = "Player Frame X", text = "Blizzard's own Player frame, restyled in place by Scoot. Configured on the Player page under Unit Frames." } },
                { id = "Z", variant = "Z", category = "unitFramesZ", subId = "Player",
                  versionBadge = { label = "Z", title = "Player Frame Z", text = "Scoot's own text-first Player frame. Blizzard's Player frame is removed entirely while this is on — and everything attached to it goes with it: the Pet frame, totem and rune/class power bars, and a cast bar locked to the Player frame in Edit Mode. Positioned in Edit Mode; configured on the Player page." } },
              } },
            { id = "Target", label = "Target",
              modeCycle = {
                { id = "X", variant = "X", category = "unitFrames", subId = "Target",
                  versionBadge = { label = "X", title = "Target Frame X", text = "Blizzard's own Target frame, restyled in place by Scoot. Configured on the Target page under Unit Frames." } },
                { id = "Z", variant = "Z", category = "unitFramesZ", subId = "Target",
                  versionBadge = { label = "Z", title = "Target Frame Z", text = "Scoot's own text-first Target frame. Blizzard's Target frame is removed entirely while this is on — and everything attached to it goes with it: the Target-of-Target frame and the target's cast bar. Positioned in Edit Mode; configured on the Target page." } },
              } },
            { id = "TargetOfTarget", label = "Target of Target" },
            { id = "Focus", label = "Focus" },
            { id = "FocusTarget", label = "Target of Focus" },
            { id = "Pet", label = "Pet" },
            { id = "Boss", label = "Boss" },
            -- Not an on/off row: a variant selector for the castBars category,
            -- nested here because that is where its effect is scoped. Its state
            -- lives in moduleEnabled.castBars, never in unitFrames.
            { id = "castBarsVariant", label = "Cast Bars", variantCategory = "castBars" },
        },
    },
    unitFramesZ = {
        label = "Unit Frames",
        noMasterToggle = true,
        -- Rendered through the per-unit modeCycle rows inside Unit Frames, never
        -- as a category of its own.
        hiddenFromFeatures = true,
        -- Absent MUST keep meaning "off": the preset backfill turns absent
        -- categories into `true`, and a bare `true` on a noMasterToggle category
        -- reads enabled for every sub — which would force Z on for all units
        -- (while the backfill also turns X on) the moment any preset is applied.
        noPresetBackfill = true,
        -- NOT mutuallyExclusive: each unit's Z toggle is independent. X/Z
        -- exclusivity is per unit and lives in the modeCycle writes (plus the
        -- component initializer's write-back), not in this category.
        -- The component id (unitFramesZ) is deliberately NOT in
        -- COMPONENT_TO_CATEGORY: RegisterComponent would gate on
        -- IsModuleEnabled("unitFramesZ", "unitFramesZ"), which no sub key ever
        -- satisfies. The initializer gates inline instead.
        subToggles = {
            { id = "Player", label = "Player", variant = "Z" },
            { id = "Target", label = "Target", variant = "Z" },
        },
    },
}

--------------------------------------------------------------------------------
-- IsModuleEnabled / SetModuleEnabled
--------------------------------------------------------------------------------

--- Check if a module category (and optionally a sub-toggle) is enabled.
--- Returns false for absent keys (zero-touch policy: new modules default to off).
function addon:IsModuleEnabled(category, subId)
    local profile = self.db and self.db.profile
    if not profile then return false end
    local me = profile.moduleEnabled
    if not me then return false end

    local val = me[category]
    if val == nil then return false end    -- absent key = disabled
    if val == false then return false end  -- master off
    if val == true then
        -- For mutuallyExclusive categories, only the first sub-toggle defaults to enabled
        if subId then
            local catDef = self.MODULE_CATEGORIES[category]
            if catDef and catDef.mutuallyExclusive and catDef.subToggles then
                return catDef.subToggles[1] and catDef.subToggles[1].id == subId
            end
        end
        return true
    end

    -- Table form: master + sub-toggles
    if type(val) == "table" then
        local catDef = self.MODULE_CATEGORIES[category]
        local isNoMaster = catDef and catDef.noMasterToggle

        -- noMasterToggle: master state derived from any sub-toggle being true
        if isNoMaster and not subId then
            for k, v in pairs(val) do
                if k ~= "_enabled" and v == true then return true end
            end
            return false
        end

        -- Standard master gate (skip for noMasterToggle categories)
        if not isNoMaster and val._enabled == false then return false end

        if subId then
            local sub = val[subId]
            return sub == true                      -- absent sub = disabled
        end
        return true
    end
    return true
end

--- Is the X cast bar path (Scoot styling Blizzard's own cast bars) active?
---
--- X is the default, so an absent key means ON here — the opposite of the usual
--- zero-touch reading. The Cast Bars selector has no off state: an enabled unit
--- frame always has a cast bar, and the only question is who draws it. Absent
--- also covers every profile configured before the selector existed, all of
--- which were on X by definition.
---
--- Zero-touch still holds, because the X path is additionally gated on the
--- unit's own unitFrames toggle and a fresh profile has none of those enabled.
function addon:IsCastBarXEnabled()
    local profile = self.db and self.db.profile
    local me = profile and profile.moduleEnabled
    if not me or me.castBars == nil then return true end
    return self:IsModuleEnabled("castBars", "castBarX")
end

--- Set a module toggle value. Handles boolean→table transition for sub-toggles.
function addon:SetModuleEnabled(category, subId, value)
    local profile = self.db and self.db.profile
    if not profile then return end
    if not profile.moduleEnabled then
        profile.moduleEnabled = {}
    end
    local me = profile.moduleEnabled
    -- Force materialization: if moduleEnabled exists only via metatable,
    -- ensure it's in the raw profile so writes persist across accesses.
    if rawget(profile, "moduleEnabled") == nil then
        profile.moduleEnabled = me
    end

    local catDef = self.MODULE_CATEGORIES[category]
    local isNoMaster = catDef and catDef.noMasterToggle

    if not subId then
        -- Master toggle (no-op for noMasterToggle categories)
        if isNoMaster then return end
        if type(me[category]) == "table" then
            me[category]._enabled = value
        else
            me[category] = value
        end
    else
        -- Sub-toggle: ensure table form
        local current = me[category]
        if type(current) ~= "table" then
            local wasEnabled = (current == true)
            me[category] = isNoMaster and {} or { _enabled = wasEnabled }
            current = me[category]
            -- Initialize sub-toggles: for mutuallyExclusive categories only the
            -- first sub-toggle defaults to true; others default to the master state.
            -- Grouped sub-toggles expand their members.
            if catDef and catDef.subToggles then
                for i, sub in ipairs(catDef.subToggles) do
                    -- NOT `A and B or C`: with wasEnabled == false that collapses
                    -- to (i == 1) and silently seeds the first sub-toggle on.
                    local initVal
                    if catDef.mutuallyExclusive then
                        initVal = (i == 1)
                    else
                        initVal = wasEnabled
                    end
                    if sub.members then
                        for _, memberId in ipairs(sub.members) do
                            current[memberId] = initVal
                        end
                    elseif not sub.variantCategory then
                        -- Variant rows keep their state in the category they point
                        -- at; a key seeded here would be dead data.
                        current[sub.id] = initVal
                    end
                end
            end
        end
        current[subId] = value
    end
end

--- Check if every module category is disabled (all toggles off).
function addon:AreAllModulesDisabled()
    local profile = self.db and self.db.profile
    if not profile then return true end
    local me = profile.moduleEnabled
    if not me then return true end
    for _, category in ipairs(self.MODULE_CATEGORY_ORDER) do
        if self:IsModuleEnabled(category) then
            return false
        end
    end
    return true
end
