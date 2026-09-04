-- rules.lua - Conditional rules engine for automatic setting overrides
local addonName, addon = ...

addon.Rules = addon.Rules or {}
local Rules = addon.Rules

local ACTIONS = {}
local SPEC_CACHE = nil
local SPEC_BY_ID = nil

-- Tracks which actionIds are currently overridden by active rules (in-memory).
-- Used to detect when an action was previously overridden but is no longer.
local ACTIVE_OVERRIDES = {}

-- Baseline tracking helper functions.
-- Baselines are persisted in profile.ruleBaselines so they survive logout/login.
-- Key: actionId, Value: the value that was in place before the first rule override.

local function getBaselinesTable()
    local profile = addon.db and addon.db.profile
    if not profile then
        return {}
    end
    profile.ruleBaselines = profile.ruleBaselines or {}
    return profile.ruleBaselines
end

local function getBaseline(actionId)
    local baselines = getBaselinesTable()
    return baselines[actionId]
end

local function setBaseline(actionId, value)
    local baselines = getBaselinesTable()
    baselines[actionId] = value
end

local function clearBaseline(actionId)
    local baselines = getBaselinesTable()
    baselines[actionId] = nil
end

local function ensureProfile()
    local db = addon.db
    local profile = db and db.profile
    if not profile then
        return nil
    end

    profile.rules = profile.rules or {}
    profile.rulesState = profile.rulesState or {}
    profile.rulesState.nextId = profile.rulesState.nextId or 1

    return profile
end

local function getRulesTable()
    local profile = ensureProfile()
    if not profile then
        return {}
    end

    local rules = profile.rules
    if type(rules) ~= "table" then
        rules = {}
        profile.rules = rules
    end

    -- Normalize array holes to keep deterministic ordering
    local cleaned = {}
    for _, entry in ipairs(rules) do
        table.insert(cleaned, entry)
    end
    profile.rules = cleaned
    return cleaned
end

local function getRuleState()
    local profile = ensureProfile()
    local state = profile and profile.rulesState
    if not state then
        return nil
    end
    state.nextId = state.nextId or 1
    return state
end

local function nextRuleId()
    local state = getRuleState()
    if not state then
        return "rule-0001"
    end
    local id = string.format("rule-%04d", state.nextId)
    state.nextId = state.nextId + 1
    return id
end

-- Normalize a value based on the action's valueType
local function normalizeValue(value, valueType)
    if valueType == "boolean" then
        return value and true or false
    elseif valueType == "number" then
        return tonumber(value) or 0
    elseif valueType == "color" then
        -- Color values are tables {r, g, b, a}
        if type(value) == "table" then
            return value
        end
        return { 1, 1, 1, 1 }  -- Default white
    else
        -- For string/dropdown values, return as-is
        return value
    end
end

local function buildSpecCache()
    if SPEC_CACHE then
        return SPEC_CACHE, SPEC_BY_ID
    end
    SPEC_BY_ID = {}
    SPEC_CACHE = {}

    if type(GetNumClasses) ~= "function" or type(GetClassInfo) ~= "function" then
        return SPEC_CACHE, SPEC_BY_ID
    end

    local totalClasses = GetNumClasses()
    for classIndex = 1, totalClasses do
        local className, classFile, classID = GetClassInfo(classIndex)
        if classID then
            local classEntry = {
                classID = classID,
                name = className or ("Class " .. tostring(classIndex)),
                file = classFile,
                specs = {},
            }

            local count = GetNumSpecializationsForClassID(classID) or 0
            for specIndex = 1, count do
                local specID, specName, _, specIcon = GetSpecializationInfoForClassID(classID, specIndex)
                if specID then
                    local specEntry = {
                        classID = classID,
                        className = classEntry.name,
                        file = classFile,
                        specID = specID,
                        name = specName or ("Spec " .. tostring(specIndex)),
                        icon = specIcon,
                    }
                    table.insert(classEntry.specs, specEntry)
                    SPEC_BY_ID[specID] = specEntry
                end
            end

            table.insert(SPEC_CACHE, classEntry)
        end
    end

    table.sort(SPEC_CACHE, function(a, b)
        return tostring(a.name) < tostring(b.name)
    end)

    -- Cache only once the class data is really there: an empty build captured
    -- before login would stick for the session and strand every caller.
    if #SPEC_CACHE == 0 then
        local empty, emptyById = SPEC_CACHE, SPEC_BY_ID
        SPEC_CACHE, SPEC_BY_ID = nil, nil
        return empty, emptyById
    end

    return SPEC_CACHE, SPEC_BY_ID
end

local function currentSpecID()
    if type(GetSpecialization) ~= "function" or type(GetSpecializationInfo) ~= "function" then
        return nil
    end
    local specIndex = GetSpecialization()
    if not specIndex then
        return nil
    end
    local specID = select(1, GetSpecializationInfo(specIndex))
    return specID
end

local function currentPlayerLevel()
    if type(UnitLevel) ~= "function" then
        return 0
    end
    return UnitLevel("player") or 0
end

local function applyActionValue(actionId, value, reason)
    local handler = ACTIONS[actionId]
    if not handler or not handler.set then
        return
    end

    -- Always log rule actions for diagnostic purposes
    local label = handler.path and table.concat(handler.path, " > ") or actionId
    local displayValue = tostring(value)
    if handler.valueType == "boolean" then
        displayValue = value and "true" or "false"
    end

    local ok, changed = pcall(handler.set, value, reason)
    if not ok then
        if addon and addon.Print then
            addon:Print(string.format("Rules: Failed to apply %s (%s)", label, tostring(changed)))
        end
        return
    end

    -- Only log when a change was made
    if changed ~= false and addon and addon.Print then
        addon:Print(string.format("Rules: %s = %s (%s)", label, displayValue, reason or ""))
    end
end

-- Kept off addon.Refresh: each action re-applies the one target its write touched, not a chain.
local function registerDefaultActions()
    -- Personal Resource Display: per-part hide actions. Each mirrors a Blizzard Edit
    -- Mode setting (HideHealth / HidePower / HideAltPower / HideClassInfo), so the write
    -- goes through the component db (materializing it if needed) and is pushed to Edit
    -- Mode by personal_resource_display/editmode.lua; the applicator only parks Scoot's art.
    local function registerPRDHideAction(componentId, pageLabel, label)
        local actionId = componentId .. ".hideBar"
        ACTIONS[actionId] = {
            id = actionId,
            valueType = "boolean",
            widget = "checkbox",           -- Matches component.settings[settingId].ui.widget
            componentId = componentId,     -- For resolving component reference
            settingId = "hideBar",         -- For resolving setting within component
            defaultValue = false,
            path = { "Personal Resource", pageLabel, label },
            get = function()
                local profile = addon.db and addon.db.profile
                local comp = profile and profile.components and profile.components[componentId]
                if comp and comp.hideBar ~= nil then
                    return comp.hideBar
                end
                return false
            end,
            set = function(value)
                if not (addon.db and addon.db.profile) then
                    return false
                end
                local db = addon.EnsureComponentDB and addon:EnsureComponentDB(componentId)
                if not db then
                    return false
                end
                value = value and true or false
                if db.hideBar == value then
                    return false
                end
                db.hideBar = value
                if addon.PRD and addon.PRD.PushMirror then
                    pcall(addon.PRD.PushMirror, componentId, "hideBar")
                end
                local component = addon.Components and addon.Components[componentId]
                if component and component.ApplyStyling then
                    pcall(component.ApplyStyling, component)
                elseif addon.ApplyStyles then
                    addon:ApplyStyles()
                end
                return true
            end,
        }
    end

    registerPRDHideAction("prdPower", "Power Bar", "Hide Power Bar")
    registerPRDHideAction("prdHealth", "Health Bar", "Hide Health Bar")
    registerPRDHideAction("prdAltPower", "Alternate Power Bar", "Hide Alternate Power Bar")
    registerPRDHideAction("prdClassResource", "Class Resource", "Hide Class Resource")

    -- Target/Focus Unit Frames: Hide Level Text (applies to both Target and Focus frames)
    ACTIONS["ufTargetFocus.levelTextHidden"] = {
        id = "ufTargetFocus.levelTextHidden",
        valueType = "boolean",
        widget = "checkbox",
        componentId = "ufTargetFocus",
        settingId = "levelTextHidden",
        defaultValue = false,
        path = { "Target/Focus Unit Frames", "Name & Level Text", "Visibility", "Hide Level Text" },
        get = function()
            -- Return true if EITHER Target or Focus has it hidden
            local profile = addon.db and addon.db.profile
            local uf = profile and profile.unitFrames
            local target = uf and uf.Target
            local focus = uf and uf.Focus
            return (target and target.levelTextHidden) or (focus and focus.levelTextHidden) or false
        end,
        set = function(value)
            -- Apply to BOTH Target and Focus
            local profile = addon.db and addon.db.profile
            if not profile then return false end
            profile.unitFrames = profile.unitFrames or {}
            profile.unitFrames.Target = profile.unitFrames.Target or {}
            profile.unitFrames.Focus = profile.unitFrames.Focus or {}
            local boolVal = value and true or false
            local changed = false
            if profile.unitFrames.Target.levelTextHidden ~= boolVal then
                profile.unitFrames.Target.levelTextHidden = boolVal
                changed = true
            end
            if profile.unitFrames.Focus.levelTextHidden ~= boolVal then
                profile.unitFrames.Focus.levelTextHidden = boolVal
                changed = true
            end
            if changed and addon.ApplyUnitFrameNameLevelTextFor then
                pcall(addon.ApplyUnitFrameNameLevelTextFor, "Target")
                pcall(addon.ApplyUnitFrameNameLevelTextFor, "Focus")
            end
            return changed
        end,
    }

    -- Player Unit Frame: Hide Class Resource
    ACTIONS["ufPlayerClassResource.hide"] = {
        id = "ufPlayerClassResource.hide",
        valueType = "boolean",
        widget = "checkbox",
        componentId = "ufPlayerClassResource",
        settingId = "hide",
        defaultValue = false,
        path = { "Player Unit Frame", "Class Resource", "Visibility", "Hide Class Resource" },
        get = function()
            local profile = addon.db and addon.db.profile
            local uf = profile and profile.unitFrames
            local player = uf and uf.Player
            local cr = player and player.classResource
            return cr and cr.hide or false
        end,
        set = function(value)
            local profile = addon.db and addon.db.profile
            if not profile then return false end
            profile.unitFrames = profile.unitFrames or {}
            profile.unitFrames.Player = profile.unitFrames.Player or {}
            profile.unitFrames.Player.classResource = profile.unitFrames.Player.classResource or {}
            local cr = profile.unitFrames.Player.classResource
            local boolVal = value and true or false
            if cr.hide == boolVal then return false end
            cr.hide = boolVal
            if addon.ApplyUnitFrameClassResource then
                pcall(addon.ApplyUnitFrameClassResource, "Player")
            elseif addon.ApplyStyles then
                pcall(addon.ApplyStyles, addon)
            end
            return true
        end,
    }

    -- Player Unit Frame: Hide Power Bar
    ACTIONS["ufPlayerPower.hideBar"] = {
        id = "ufPlayerPower.hideBar",
        valueType = "boolean",
        widget = "checkbox",
        componentId = "ufPlayer",
        settingId = "powerBarHidden",
        defaultValue = false,
        path = { "Player Unit Frame", "Power Bar", "Visibility", "Hide Power Bar" },
        get = function()
            local profile = addon.db and addon.db.profile
            local uf = profile and profile.unitFrames
            local player = uf and uf.Player
            return player and player.powerBarHidden or false
        end,
        set = function(value)
            local profile = addon.db and addon.db.profile
            if not profile then return false end
            profile.unitFrames = profile.unitFrames or {}
            profile.unitFrames.Player = profile.unitFrames.Player or {}
            local player = profile.unitFrames.Player
            local boolVal = value and true or false
            if player.powerBarHidden == boolVal then return false end
            player.powerBarHidden = boolVal
            if addon.ApplyUnitFrameBarTexturesFor then
                pcall(addon.ApplyUnitFrameBarTexturesFor, "Player")
            end
            if addon.ApplyUnitFramePowerTextVisibilityFor then
                pcall(addon.ApplyUnitFramePowerTextVisibilityFor, "Player")
            end
            return true
        end,
    }

    -- Player Unit Frame: Power Bar - Disable % Text (LeftText when present)
    ACTIONS["ufPlayerPower.percentTextDisabled"] = {
        id = "ufPlayerPower.percentTextDisabled",
        valueType = "boolean",
        widget = "checkbox",
        componentId = "ufPlayer",
        settingId = "powerPercentHidden",
        defaultValue = false,
        path = { "Player Unit Frame", "Power Bar", "% Text", "Disable % Text" },
        get = function()
            local profile = addon.db and addon.db.profile
            local uf = profile and profile.unitFrames
            local player = uf and uf.Player
            return player and player.powerPercentHidden or false
        end,
        set = function(value)
            local profile = addon.db and addon.db.profile
            if not profile then return false end
            profile.unitFrames = profile.unitFrames or {}
            profile.unitFrames.Player = profile.unitFrames.Player or {}
            local player = profile.unitFrames.Player
            local boolVal = value and true or false
            if player.powerPercentHidden == boolVal then return false end
            player.powerPercentHidden = boolVal
            if addon.ApplyUnitFramePowerTextVisibilityFor then
                pcall(addon.ApplyUnitFramePowerTextVisibilityFor, "Player")
            elseif addon.ApplyStyles then
                pcall(addon.ApplyStyles, addon)
            end
            return true
        end,
    }

    -- Player Unit Frame: Power Bar - Disable Value Text (RightText when present)
    ACTIONS["ufPlayerPower.valueTextDisabled"] = {
        id = "ufPlayerPower.valueTextDisabled",
        valueType = "boolean",
        widget = "checkbox",
        componentId = "ufPlayer",
        settingId = "powerValueHidden",
        defaultValue = false,
        path = { "Player Unit Frame", "Power Bar", "Value Text", "Disable Value Text" },
        get = function()
            local profile = addon.db and addon.db.profile
            local uf = profile and profile.unitFrames
            local player = uf and uf.Player
            return player and player.powerValueHidden or false
        end,
        set = function(value)
            local profile = addon.db and addon.db.profile
            if not profile then return false end
            profile.unitFrames = profile.unitFrames or {}
            profile.unitFrames.Player = profile.unitFrames.Player or {}
            local player = profile.unitFrames.Player
            local boolVal = value and true or false
            if player.powerValueHidden == boolVal then return false end
            player.powerValueHidden = boolVal
            if addon.ApplyUnitFramePowerTextVisibilityFor then
                pcall(addon.ApplyUnitFramePowerTextVisibilityFor, "Player")
            elseif addon.ApplyStyles then
                pcall(addon.ApplyStyles, addon)
            end
            return true
        end,
    }
end

local function ruleMatchesSpecialization(trigger, specID)
    local specs = trigger.specIds
    if type(specs) ~= "table" then
        return false
    end
    for _, id in ipairs(specs) do
        if id == specID then
            return true
        end
    end
    return false
end

local function ruleMatchesPlayerLevel(trigger, playerLevel)
    local targetLevel = tonumber(trigger.level)
    if not targetLevel then
        return false
    end
    return playerLevel == targetLevel
end

local function ruleMatches(rule, specID, playerLevel)
    if not rule or rule.enabled == false then
        return false
    end
    local trigger = rule.trigger or {}
    local triggerType = trigger.type

    if triggerType == "specialization" then
        return ruleMatchesSpecialization(trigger, specID)
    elseif triggerType == "playerLevel" then
        return ruleMatchesPlayerLevel(trigger, playerLevel)
    end

    return false
end

function Rules:Initialize()
    if self._initialized then
        return
    end

    registerDefaultActions()
    buildSpecCache()

    if addon.db and addon.db.RegisterCallback then
        addon.db.RegisterCallback(self, "OnProfileChanged", "OnProfileChanged")
        addon.db.RegisterCallback(self, "OnProfileCopied", "OnProfileChanged")
        addon.db.RegisterCallback(self, "OnProfileReset", "OnProfileChanged")
        addon.db.RegisterCallback(self, "OnNewProfile", "OnProfileChanged")
    end

    self._initialized = true
    self._lastSpecID = currentSpecID()
    self:ApplyAll("Initialize")
end

function Rules:IsInitialized()
    return self._initialized and addon.db ~= nil
end

function Rules:GetRules()
    return getRulesTable()
end

function Rules:GetRuleById(ruleId)
    if not ruleId then
        return nil
    end
    for _, rule in ipairs(getRulesTable()) do
        if rule.id == ruleId then
            return rule
        end
    end
end

-- Check if a specific rule is currently active (trigger conditions match)
-- Used by the UI to show visual feedback on which rules are matching
function Rules:IsRuleActive(ruleId)
    if not self:IsInitialized() then
        return false
    end
    local rule = self:GetRuleById(ruleId)
    if not rule then
        return false
    end
    local specID = currentSpecID()
    local playerLevel = currentPlayerLevel()
    return ruleMatches(rule, specID, playerLevel)
end

function Rules:CreateRule(opts)
    local rule = {
        id = nextRuleId(),
        enabled = true,
        trigger = {
            type = "specialization",
            specIds = {},
        },
        action = {
            id = nil,  -- No default action; user must select a target
            value = true,
        },
    }

    if opts then
        if opts.triggerType then
            rule.trigger.type = opts.triggerType
        end
        if opts.specIds then
            rule.trigger.specIds = {}
            for _, id in ipairs(opts.specIds) do
                table.insert(rule.trigger.specIds, id)
            end
        end
        if opts.actionId then
            rule.action.id = opts.actionId
            -- Set default value based on action's valueType
            local handler = ACTIONS[opts.actionId]
            if handler then
                rule.action.value = handler.defaultValue
            end
        end
        if opts.value ~= nil then
            local handler = ACTIONS[rule.action.id]
            local valueType = handler and handler.valueType or "boolean"
            rule.action.value = normalizeValue(opts.value, valueType)
        end
    end

    local rules = getRulesTable()
    table.insert(rules, rule)

    self:ApplyAll("CreateRule")
    return rule
end

function Rules:DeleteRule(ruleId)
    if not ruleId then
        return
    end
    local rules = getRulesTable()
    local deletedActionId = nil
    local changed = false

    for index = #rules, 1, -1 do
        if rules[index].id == ruleId then
            -- Capture the action this rule targeted before deleting
            deletedActionId = rules[index].action and rules[index].action.id
            table.remove(rules, index)
            changed = true
            break
        end
    end

    if changed then
        -- If no remaining rules target this action, clear its baseline
        if deletedActionId then
            local stillTargeted = false
            for _, rule in ipairs(rules) do
                if rule.action and rule.action.id == deletedActionId then
                    stillTargeted = true
                    break
                end
            end
            if not stillTargeted then
                clearBaseline(deletedActionId)
            end
        end

        self:ApplyAll("DeleteRule")
    end
end

function Rules:SetRuleEnabled(ruleId, enabled)
    local rule = self:GetRuleById(ruleId)
    if not rule then
        return
    end
    local desired = not not enabled
    if rule.enabled == desired then
        return
    end
    rule.enabled = desired
    self:ApplyAll("ToggleRule")
end

function Rules:SetRuleTriggerSpecs(ruleId, specIdList)
    local rule = self:GetRuleById(ruleId)
    if not rule or rule.trigger.type ~= "specialization" then
        return
    end
    local unique = {}
    local ordered = {}
    for _, specID in ipairs(specIdList or {}) do
        if specID and not unique[specID] then
            unique[specID] = true
            table.insert(ordered, specID)
        end
    end
    rule.trigger.specIds = ordered
    self:ApplyAll("UpdateSpecs")
end

function Rules:ToggleRuleSpec(ruleId, specID)
    local rule = self:GetRuleById(ruleId)
    if not rule or rule.trigger.type ~= "specialization" or not specID then
        return
    end
    rule.trigger.specIds = rule.trigger.specIds or {}
    local found = false
    for idx = #rule.trigger.specIds, 1, -1 do
        if rule.trigger.specIds[idx] == specID then
            table.remove(rule.trigger.specIds, idx)
            found = true
            break
        end
    end
    if not found then
        table.insert(rule.trigger.specIds, specID)
        table.sort(rule.trigger.specIds)
    end
    self:ApplyAll("ToggleSpec")
end

-- Change the trigger type and reset trigger-specific data
function Rules:SetRuleTriggerType(ruleId, triggerType)
    local rule = self:GetRuleById(ruleId)
    if not rule then
        return
    end
    if rule.trigger.type == triggerType then
        return  -- No change
    end
    -- Reset trigger data when switching types
    rule.trigger = rule.trigger or {}
    rule.trigger.type = triggerType
    if triggerType == "specialization" then
        rule.trigger.specIds = {}
        rule.trigger.level = nil
    elseif triggerType == "playerLevel" then
        rule.trigger.specIds = nil
        rule.trigger.level = nil  -- User must set the level
    end
    self:ApplyAll("ChangeTriggerType")
end

-- Set the level value for playerLevel triggers
function Rules:SetRuleTriggerLevel(ruleId, level)
    local rule = self:GetRuleById(ruleId)
    if not rule or rule.trigger.type ~= "playerLevel" then
        return
    end
    local numLevel = tonumber(level)
    rule.trigger.level = numLevel
    self:ApplyAll("ChangeTriggerLevel")
end

function Rules:SetRuleAction(ruleId, actionId)
    local rule = self:GetRuleById(ruleId)
    if not rule or not ACTIONS[actionId] then
        return
    end
    rule.action = rule.action or {}
    rule.action.id = actionId
    -- Reset value to the action's default when switching targets
    rule.action.value = ACTIONS[actionId].defaultValue
    self:ApplyAll("ChangeAction")
end

function Rules:SetRuleActionValue(ruleId, value)
    local rule = self:GetRuleById(ruleId)
    if not rule then
        return
    end
    rule.action = rule.action or {}
    local actionId = rule.action.id
    local handler = ACTIONS[actionId]
    local valueType = handler and handler.valueType or "boolean"
    local normalized = normalizeValue(value, valueType)
    -- For tables (colors), always update since equality check is complex
    if valueType ~= "color" and rule.action.value == normalized then
        return
    end
    rule.action.value = normalized
    self:ApplyAll("ChangeActionValue")
end

function Rules:GetActionMetadata(actionId)
    return ACTIONS[actionId]
end

function Rules:GetAllActions()
    return ACTIONS
end

function Rules:GetActionPathLabel(actionId)
    local action = ACTIONS[actionId]
    if not action or not action.path then
        return "Select Target"
    end
    return table.concat(action.path, " › ")
end

function Rules:GetSpecBuckets()
    local buckets, specById = buildSpecCache()
    return buckets, specById
end

function Rules:GetSpecSummary(rule)
    rule = rule or {}
    local specIds = rule.trigger and rule.trigger.specIds
    if not specIds or #specIds == 0 then
        return "No specs selected"
    end
    local specs = {}
    buildSpecCache()
    for _, specID in ipairs(specIds) do
        local entry = SPEC_BY_ID and SPEC_BY_ID[specID]
        if entry then
            table.insert(specs, entry.name)
        else
            table.insert(specs, tostring(specID))
        end
    end
    table.sort(specs)
    return table.concat(specs, ", ")
end

local function gatherActionMenu()
    local tree = {}
    local function findChild(list, label)
        for _, node in ipairs(list) do
            if node.text == label then
                return node
            end
        end
    end

    for _, action in pairs(ACTIONS) do
        local cursor = tree
        for index, label in ipairs(action.path or { action.id }) do
            local node = findChild(cursor, label)
            if not node then
                node = { text = label, children = {} }
                table.insert(cursor, node)
            end
            if index == #action.path then
                node.actionId = action.id
            end
            cursor = node.children
        end
    end

    return tree
end

function Rules:GetActionMenuTree()
    if not self._actionMenuCache then
        self._actionMenuCache = gatherActionMenu()
    end
    return self._actionMenuCache
end

-- Get available options at a given path depth for breadcrumb navigation
-- pathSegments: array of strings representing the path so far (can be empty for level 1)
-- Returns: array of { text = "label", hasChildren = bool }
function Rules:GetActionsAtPath(pathSegments)
    pathSegments = pathSegments or {}
    local depth = #pathSegments

    local results = {}
    local seen = {}

    for _, action in pairs(ACTIONS) do
        local path = action.path
        if path and #path > depth then
            -- Check whether this action's path matches the current path prefix
            local matches = true
            for i = 1, depth do
                if path[i] ~= pathSegments[i] then
                    matches = false
                    break
                end
            end

            if matches then
                local nextSegment = path[depth + 1]
                if nextSegment and not seen[nextSegment] then
                    seen[nextSegment] = true
                    -- Check if this segment has children (more path beyond it)
                    local hasChildren = (#path > depth + 1)
                    table.insert(results, {
                        text = nextSegment,
                        hasChildren = hasChildren,
                    })
                end
            end
        end
    end

    -- Sort alphabetically
    table.sort(results, function(a, b)
        return a.text < b.text
    end)

    return results
end

-- Get the actionId for a complete 4-segment path
-- fullPath: array of 4 strings representing the complete path
-- Returns: actionId string or nil if no matching action
function Rules:GetActionIdForPath(fullPath)
    if not fullPath or #fullPath < 1 then
        return nil
    end

    for actionId, action in pairs(ACTIONS) do
        local path = action.path
        if path and #path == #fullPath then
            local matches = true
            for i = 1, #fullPath do
                if path[i] ~= fullPath[i] then
                    matches = false
                    break
                end
            end
            if matches then
                return actionId
            end
        end
    end
end

-- Get the path segments for a given actionId
-- Returns: array of path segments or empty array if not found
function Rules:GetActionPath(actionId)
    local action = ACTIONS[actionId]
    if action and action.path then
        return action.path
    end
    return {}
end

-- Clear all stored baselines. Use this to reset the "normal" values for all actions.
-- After clearing, the next time a rule activates, it will capture fresh baselines.
function Rules:ClearAllBaselines()
    local profile = addon.db and addon.db.profile
    if profile then
        profile.ruleBaselines = {}
    end
    ACTIVE_OVERRIDES = {}
end

-- Clear the baseline for a specific action.
function Rules:ClearBaseline(actionId)
    if actionId then
        clearBaseline(actionId)
    end
end

-- Check if a baseline exists for an action (useful for debugging)
function Rules:HasBaseline(actionId)
    return getBaseline(actionId) ~= nil
end

-- Get the baseline value for an action (useful for debugging)
function Rules:GetBaseline(actionId)
    return getBaseline(actionId)
end

function Rules:ApplyAll(reason)
    if not self:IsInitialized() then
        return
    end

    local currentSpec = currentSpecID()
    local playerLevel = currentPlayerLevel()
    if currentSpec ~= self._lastSpecID then
        self._lastSpecID = currentSpec
    end

    -- Determine which actions will be overridden by matching rules this cycle.
    -- Key: actionId, Value: the value to apply
    local newOverrides = {}
    local rules = getRulesTable()

    for _, rule in ipairs(rules) do
        local actionId = rule.action and rule.action.id
        local handler = ACTIONS[actionId]
        if handler and ruleMatches(rule, currentSpec, playerLevel) then
            local value = rule.action.value
            value = normalizeValue(value, handler.valueType)
            -- Last matching rule wins (rules are processed in order)
            newOverrides[actionId] = value
        end
    end

    -- Capture baselines for newly overridden actions (first override wins, persisted in profile)
    for actionId, _ in pairs(newOverrides) do
        if getBaseline(actionId) == nil then
            local handler = ACTIONS[actionId]
            if handler and handler.get then
                local ok, currentValue = pcall(handler.get)
                if ok then
                    -- Store the current (non-overridden) value as the baseline
                    setBaseline(actionId, currentValue)
                    -- Log baseline capture for diagnostics
                    if addon and addon.Print then
                        local label = handler.path and table.concat(handler.path, " > ") or actionId
                        local displayValue = tostring(currentValue)
                        if handler.valueType == "boolean" then
                            displayValue = currentValue and "true" or "false"
                        end
                        addon:Print(string.format("Rules: Baseline captured for %s = %s", label, displayValue))
                    end
                end
            end
        end
    end

    -- Restore baselines for actions no longer overridden (iterates persisted baselines,
    -- not in-memory ACTIVE_OVERRIDES, so restoration works correctly across reload/character switch)
    local baselines = getBaselinesTable()
    for actionId, baselineValue in pairs(baselines) do
        if not newOverrides[actionId] then
            applyActionValue(actionId, baselineValue, reason .. " (restore baseline)")
            -- Keep the baseline in the profile - it represents the user's "normal" setting
            -- and will be used again if rules reactivate later.
        end
    end

    -- Apply new override values
    for actionId, value in pairs(newOverrides) do
        applyActionValue(actionId, value, reason)
    end

    -- Update tracking table for next cycle
    ACTIVE_OVERRIDES = newOverrides
end

function Rules:OnProfileChanged()
    self._actionMenuCache = nil
    -- Clear in-memory override tracking when switching profiles.
    -- Baselines are stored in profile.ruleBaselines, so they come with the new profile.
    ACTIVE_OVERRIDES = {}
    buildSpecCache()
    self:ApplyAll("ProfileChanged")
end

function Rules:OnPlayerSpecChanged()
    self._actionMenuCache = nil
    buildSpecCache()
    self:ApplyAll("SpecChanged")
end

function Rules:OnPlayerLogin()
    buildSpecCache()
    self._lastSpecID = currentSpecID()
    self:ApplyAll("Login")
end

function Rules:OnPlayerLevelUp()
    self:ApplyAll("LevelUp")
end

return Rules

