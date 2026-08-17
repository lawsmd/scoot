-- apply_all.lua - Batch style application across component categories
local addonName, addon = ...

addon.ApplyAll = addon.ApplyAll or {}
local ApplyAll = addon.ApplyAll
local os_time = _G and _G.time

local FONT_KEYS = { fontFace = true }

-- Bar texture keys by system
local FG_TEXTURE_KEYS = {
    styleForegroundTexture = true,
    healthBarTexture = true,
    powerBarTexture = true,
    castBarTexture = true,
}
local BG_TEXTURE_KEYS = {
    styleBackgroundTexture = true,
    healthBarBackgroundTexture = true,
    powerBarBackgroundTexture = true,
    castBarBackgroundTexture = true,
}

-- Ensure font tables exist before ApplyAll traverses them

-- Unit Frame font structures
local UNIT_FRAME_UNITS = { "Player", "Target", "Focus", "Pet" }
local UNIT_FRAME_TEXT_KEYS = {
    "textHealthPercent",
    "textHealthValue",
    "textPowerPercent",
    "textPowerValue",
    "textName",
    "textLevel",
}

local FONT_DEFAULT = { fontFace = "FRIZQT__" }

-- Generic structure-ensurer driven by declarative specs.
--
-- Under `root = "components"` the item IS a registered component, so its own
-- registered default is the correct seed -- EnsureComponentSubTable supplies a
-- copy of it. Seeding the generic FONT_DEFAULT there instead would write a
-- table holding nothing but `fontFace = "FRIZQT__"`, which then shadows the
-- component's registered default and strands every sibling property (fontStyle,
-- fontSize, colorMode, color) at whatever the styling code happens to fall back
-- to. Profile roots that are not components (unitFrames, groupFrames) have no
-- registration to consult and keep the declarative seed.
local function ensureStructures(profile, specs)
    if not profile then return end
    for _, spec in ipairs(specs) do
        local asComponents = (spec.root == "components") and not spec.path
        for _, item in ipairs(spec.items) do
            if asComponents and addon.Components and addon.Components[item] then
                for _, key in ipairs(spec.keys) do
                    addon:EnsureComponentSubTable(item, key)
                end
            else
                profile[spec.root] = profile[spec.root] or {}
                local rootTbl = profile[spec.root]
                rootTbl[item] = rootTbl[item] or {}
                local container = rootTbl[item]
                if spec.path then
                    container[spec.path] = container[spec.path] or {}
                    container = container[spec.path]
                end
                for _, key in ipairs(spec.keys) do
                    if type(spec.default) == "table" then
                        container[key] = container[key] or {}
                        for prop, val in pairs(spec.default) do
                            if container[key][prop] == nil then
                                container[key][prop] = val
                            end
                        end
                    else
                        if container[key] == nil then
                            container[key] = spec.default
                        end
                    end
                end
            end
        end
    end
end

-- Unit Frame bar texture keys (stored at root level of each unit config)
local UNIT_FRAME_TEXTURE_KEYS = {
    "healthBarTexture",
    "healthBarBackgroundTexture",
    "powerBarTexture",
    "powerBarBackgroundTexture",
}

-- Cast bar texture keys (stored inside castBar table)
local CAST_BAR_TEXTURE_KEYS = {
    "castBarTexture",
    "castBarBackgroundTexture",
}

-- CDM components use inline fallbacks; create text setting tables explicitly
local COOLDOWN_COMPONENT_IDS = {
    "essentialCooldowns",
    "utilityCooldowns",
    "trackedBuffs",
    "trackedBars",
}
-- Common text keys used by cooldown components (trackedBars uses textName/textDuration)
local COOLDOWN_TEXT_KEYS = {
    "textStacks",
    "textCooldown",
    "textCharges",
    "textName",
    "textDuration",
}

-- Auras (buffs/debuffs) text settings
local AURA_COMPONENT_IDS = {
    "buffs",
    "debuffs",
}
local AURA_TEXT_KEYS = {
    "textCount",
    "textDuration",
}

-- Action Bar components: actionBar1-8, petBar, stanceBar
local ACTION_BAR_COMPONENT_IDS = {
    "actionBar1", "actionBar2", "actionBar3", "actionBar4",
    "actionBar5", "actionBar6", "actionBar7", "actionBar8",
    "petBar", "stanceBar",
}
local ACTION_BAR_TEXT_KEYS = {
    "textStacks",
    "textCooldown",
    "textHotkey",
    "textMacro",
}

-- Objective Tracker component
local OBJECTIVE_TRACKER_TEXT_KEYS = {
    "textHeader",
    "textQuestName",
    "textQuestObjective",
}

-- Group Frames (Party and Raid) font structures
local GROUP_FRAMES_PARTY_TEXT_KEYS = {
    "textPlayerName",
}
local GROUP_FRAMES_RAID_TEXT_KEYS = {
    "textPlayerName",
    "textStatusText",
    "textGroupNumbers",
}

-- Declarative specs for font structure initialization.
-- NOTE: sctDamage is excluded from Apply All because SCT font changes
-- require a full game restart (not /reload). Users must change SCT fonts
-- directly via the SCT settings panel to see the restart warning.
local FONT_SPECS = {
    { root = "unitFrames", items = UNIT_FRAME_UNITS, keys = UNIT_FRAME_TEXT_KEYS, default = FONT_DEFAULT },
    { root = "unitFrames", items = UNIT_FRAME_UNITS, path = "portrait", keys = { "damageText" }, default = FONT_DEFAULT },
    { root = "unitFrames", items = UNIT_FRAME_UNITS, path = "castBar", keys = { "spellNameText", "castTimeText" }, default = FONT_DEFAULT },
    { root = "components", items = COOLDOWN_COMPONENT_IDS, keys = COOLDOWN_TEXT_KEYS, default = FONT_DEFAULT },
    { root = "components", items = AURA_COMPONENT_IDS, keys = AURA_TEXT_KEYS, default = FONT_DEFAULT },
    { root = "components", items = { "tooltip" }, keys = { "textTitle", "textEverythingElse", "textComparison" }, default = FONT_DEFAULT },
    { root = "components", items = ACTION_BAR_COMPONENT_IDS, keys = ACTION_BAR_TEXT_KEYS, default = FONT_DEFAULT },
    { root = "components", items = { "objectiveTracker" }, keys = OBJECTIVE_TRACKER_TEXT_KEYS, default = FONT_DEFAULT },
    { root = "groupFrames", items = { "party" }, keys = GROUP_FRAMES_PARTY_TEXT_KEYS, default = FONT_DEFAULT },
    { root = "groupFrames", items = { "raid" }, keys = GROUP_FRAMES_RAID_TEXT_KEYS, default = FONT_DEFAULT },
}

-- Declarative specs for bar texture structure initialization
local TEXTURE_SPECS = {
    { root = "unitFrames", items = UNIT_FRAME_UNITS, keys = UNIT_FRAME_TEXTURE_KEYS, default = "default" },
    { root = "unitFrames", items = UNIT_FRAME_UNITS, path = "castBar", keys = CAST_BAR_TEXTURE_KEYS, default = "default" },
}

local function ensureState()
    local db = addon.db
    local profile = db and db.profile
    if not profile then
        return nil
    end
    -- Zero‑Touch: never force defaults into SavedVariables just by opening the UI.
    -- Only create/write `profile.applyAll` when the user explicitly changes Apply All settings.
    local state = rawget(profile, "applyAll")
    return state, profile
end

local function ensureStateWritable()
    local db = addon.db
    local profile = db and db.profile
    if not profile then
        return nil
    end
    local state = rawget(profile, "applyAll")
    if not state then
        state = {}
        profile.applyAll = state
    end
    return state, profile
end

local function replaceKeys(root, keys, value, opts)
    if type(root) ~= "table" then
        return 0
    end
    local skipTables = (opts and opts.skipTables) or {}
    local visited = {}
    local changed = 0

    local function traverse(tbl)
        if type(tbl) ~= "table" or visited[tbl] then
            return
        end
        if skipTables[tbl] then
            return
        end
        visited[tbl] = true
        for key, child in pairs(tbl) do
            if keys[key] then
                if tbl[key] ~= value then
                    tbl[key] = value
                    changed = changed + 1
                end
            end
            if type(child) == "table" then
                traverse(child)
            end
        end
    end

    traverse(root)
    return changed
end

local function buildResult(success, changed, reason)
    return {
        ok = success,
        changed = changed or 0,
        reason = reason,
    }
end

function ApplyAll:GetState()
    local state = ensureState()
    return state
end

function ApplyAll:GetPendingFont()
    local state = ensureState()
    return (state and state.fontPending) or "FRIZQT__"
end

function ApplyAll:SetPendingFont(fontKey)
    local state = ensureStateWritable()
    if state then
        state.fontPending = fontKey or "FRIZQT__"
    end
end

function ApplyAll:GetPendingBarTexture()
    local state = ensureState()
    return (state and state.barTexturePending) or "default"
end

function ApplyAll:SetPendingBarTexture(textureKey)
    local state = ensureStateWritable()
    if state then
        state.barTexturePending = textureKey or "default"
    end
end

function ApplyAll:GetLastFontSummary()
    local state = ensureState()
    return state and state.lastFontApplied or nil
end

function ApplyAll:GetLastBarTextureSummary()
    local state = ensureState()
    return state and state.lastTextureApplied or nil
end

local function recordSummary(target, key, changed)
    if not target then
        return
    end
    target.value = key
    target.changed = changed or 0
    if type(os_time) == "function" then
        target.timestamp = os_time()
    else
        target.timestamp = nil
    end
end

function ApplyAll:ApplyFonts(fontKey, opts)
    local state, profile = ensureStateWritable()
    if not state or not profile then
        return buildResult(false, 0, "noProfile")
    end
    local selection = fontKey or state.fontPending
    if not selection or selection == "" then
        return buildResult(false, 0, "noSelection")
    end

    -- Font tables are lazily created when settings panels are visited; ensure they exist.
    ensureStructures(profile, FONT_SPECS)

    -- Skip the applyAll state table and sctDamage component.
    -- SCT is excluded because font changes require a full game restart (not /reload),
    -- and users need to see the restart warning when changing SCT fonts directly.
    local skip = { [state] = true }
    if profile.components and profile.components.sctDamage then
        skip[profile.components.sctDamage] = true
    end
    local changed = replaceKeys(profile, FONT_KEYS, selection, { skipTables = skip })
    state.lastFontApplied = state.lastFontApplied or {}
    recordSummary(state.lastFontApplied, selection, changed)
    if opts and opts.updatePending then
        state.fontPending = selection
    end
    local success = changed > 0
    return buildResult(success, changed, success and nil or "noChanges")
end

function ApplyAll:ApplyBarTextures(textureKey, opts)
    local state, profile = ensureStateWritable()
    if not state or not profile then
        return buildResult(false, 0, "noProfile")
    end
    local selection = textureKey or state.barTexturePending
    if not selection or selection == "" then
        return buildResult(false, 0, "noSelection")
    end

    -- Ensure Unit Frame texture structures exist before traversing.
    -- These are lazily created when the user visits settings panels.
    ensureStructures(profile, TEXTURE_SPECS)

    local skip = { [state] = true }
    local fgChanged = replaceKeys(profile, FG_TEXTURE_KEYS, selection, { skipTables = skip })
    local bgChanged = replaceKeys(profile, BG_TEXTURE_KEYS, selection, { skipTables = skip })
    local changed = fgChanged + bgChanged
    state.lastTextureApplied = state.lastTextureApplied or {}
    recordSummary(state.lastTextureApplied, selection, changed)
    if opts and opts.updatePending then
        state.barTexturePending = selection
    end
    local success = changed > 0
    return buildResult(success, changed, success and nil or "noChanges")
end
