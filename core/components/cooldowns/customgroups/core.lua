-- customgroups/core.lua - Namespace, data model, rebuild orchestrator, events, component registration
local addonName, addon = ...

local Component = addon.ComponentPrototype

--------------------------------------------------------------------------------
-- Namespace
--------------------------------------------------------------------------------

addon.CustomGroups = {}
local CG = addon.CustomGroups
CG.NUM_GROUPS = 5

--------------------------------------------------------------------------------
-- Data Model
--------------------------------------------------------------------------------

-- Ensure the DB structure exists for all groups
local function EnsureGroupsDB()
    local profile = addon.db and addon.db.profile
    if not profile then return nil end
    if not profile.customCDMGroups then
        profile.customCDMGroups = {
            [1] = { entries = {} },
            [2] = { entries = {} },
            [3] = { entries = {} },
            [4] = { entries = {} },
            [5] = { entries = {} },
        }
    end
    for i = 1, CG.NUM_GROUPS do
        if not profile.customCDMGroups[i] then
            profile.customCDMGroups[i] = { entries = {} }
        end
        if not profile.customCDMGroups[i].entries then
            profile.customCDMGroups[i].entries = {}
        end
    end
    return profile.customCDMGroups
end
CG._EnsureGroupsDB = EnsureGroupsDB

--- Get the entries array for a group (1-3).
--- @param groupIndex number
--- @return table
function CG.GetEntries(groupIndex)
    local groups = EnsureGroupsDB()
    if not groups or not groups[groupIndex] then return {} end
    return groups[groupIndex].entries
end

--- Add an entry to a group. Rejects duplicates (same type+id in the same group).
--- @param groupIndex number
--- @param entryType string "spell" or "item"
--- @param id number
--- @return boolean success
function CG.AddEntry(groupIndex, entryType, id)
    if not groupIndex or not entryType or not id then return false end
    local entries = CG.GetEntries(groupIndex)

    -- Duplicate check within this group
    for _, entry in ipairs(entries) do
        if entry.type == entryType and entry.id == id then
            return false
        end
    end

    table.insert(entries, { type = entryType, id = id })
    CG.FireCallback()
    return true
end

--- Remove an entry by position from a group.
--- @param groupIndex number
--- @param entryIndex number
function CG.RemoveEntry(groupIndex, entryIndex)
    local entries = CG.GetEntries(groupIndex)
    if entryIndex < 1 or entryIndex > #entries then return end
    table.remove(entries, entryIndex)
    CG.FireCallback()
end

--- Move an entry from one group to another (or same group, different position).
--- @param fromGroup number
--- @param fromIndex number
--- @param toGroup number
--- @param toIndex number
function CG.MoveEntry(fromGroup, fromIndex, toGroup, toIndex)
    local srcEntries = CG.GetEntries(fromGroup)
    if fromIndex < 1 or fromIndex > #srcEntries then return end

    local entry = table.remove(srcEntries, fromIndex)
    local dstEntries = CG.GetEntries(toGroup)

    -- Clamp target index
    toIndex = math.max(1, math.min(toIndex, #dstEntries + 1))
    table.insert(dstEntries, toIndex, entry)
    CG.FireCallback()
end

--- Reorder an entry within the same group.
--- @param groupIndex number
--- @param fromIndex number
--- @param toIndex number
function CG.ReorderEntry(groupIndex, fromIndex, toIndex)
    local entries = CG.GetEntries(groupIndex)
    if fromIndex < 1 or fromIndex > #entries then return end
    toIndex = math.max(1, math.min(toIndex, #entries))
    if fromIndex == toIndex then return end

    local entry = table.remove(entries, fromIndex)
    table.insert(entries, toIndex, entry)
    CG.FireCallback()
end

--- Optional callback for UI refresh when data changes.
CG._callbacks = {}

function CG.RegisterCallback(fn)
    table.insert(CG._callbacks, fn)
end

function CG.FireCallback()
    for _, fn in ipairs(CG._callbacks) do
        pcall(fn)
    end
end

--- Get the custom name for a group (nil if not set).
--- @param groupIndex number
--- @return string|nil
function CG.GetGroupName(groupIndex)
    local groups = EnsureGroupsDB()
    if not groups or not groups[groupIndex] then return nil end
    return groups[groupIndex].name
end

--- Set a custom name for a group. Stores trimmed name; nil/empty clears it.
--- @param groupIndex number
--- @param name string|nil
function CG.SetGroupName(groupIndex, name)
    local groups = EnsureGroupsDB()
    if not groups or not groups[groupIndex] then return end
    if name and type(name) == "string" then
        name = strtrim(name)
        if name == "" then name = nil end
    else
        name = nil
    end
    groups[groupIndex].name = name
    CG.FireCallback()
end

--- Get the display name for a group: custom name or fallback "Custom Group X".
--- @param groupIndex number
--- @return string
function CG.GetGroupDisplayName(groupIndex)
    local customName = CG.GetGroupName(groupIndex)
    if customName then return customName end
    return "Custom Group " .. groupIndex
end

--------------------------------------------------------------------------------
-- Container State
--------------------------------------------------------------------------------

addon.CustomGroupContainers = {}
local containers = addon.CustomGroupContainers

-- Whether HUD system has been initialized
local cgInitialized = false

--------------------------------------------------------------------------------
-- Container Opacity State Helper
--------------------------------------------------------------------------------

local function getGroupOpacityForState(groupIndex)
    local component = addon.Components and addon.Components["customGroup" .. groupIndex]
    if not component or not component.db then return 1.0 end

    local db = component.db
    local inCombat = InCombatLockdown and InCombatLockdown()
    local hasTarget = UnitExists("target")

    local opacityValue
    if inCombat then
        opacityValue = tonumber(db.opacity) or 100
    elseif hasTarget then
        opacityValue = tonumber(db.opacityWithTarget) or 100
    else
        opacityValue = tonumber(db.opacityOutOfCombat) or 100
    end

    return math.max(0, math.min(1.0, opacityValue / 100))
end
CG._getGroupOpacityForState = getGroupOpacityForState

--------------------------------------------------------------------------------
-- Visibility Filtering + Rebuild
--------------------------------------------------------------------------------

function CG.IsEntryVisible(entry)
    if entry.type == "spell" then
        return IsPlayerSpell(entry.id) or IsSpellKnown(entry.id)
            or C_SpellBook.IsSpellInSpellBook(entry.id, Enum.SpellBookSpellBank.Player, true)
    elseif entry.type == "item" then
        return (C_Item.GetItemCount(entry.id) or 0) > 0
    end
    return false
end
local IsEntryVisible = CG.IsEntryVisible

local function GetEntryTexture(entry)
    if entry.type == "spell" then
        return C_Spell.GetSpellTexture(entry.id)
    elseif entry.type == "item" then
        return C_Item.GetItemIconByID(entry.id)
    end
    return nil
end

local function RebuildGroup(groupIndex)
    if not cgInitialized then return end

    local container = containers[groupIndex]
    if not container then return end

    local comp = addon.Components and addon.Components["customGroup" .. groupIndex]
    if comp and not comp.db.enabled then
        CG._ReleaseAllIcons(groupIndex)
        container:Hide()
        CG._ManageItemTicker(0, groupIndex)
        return
    end

    CG._ReleaseAllIcons(groupIndex)

    local entries = CG.GetEntries(groupIndex)
    local visibleEntries = {}
    local currentGroupItemCount = 0

    for idx, entry in ipairs(entries) do
        if IsEntryVisible(entry) then
            table.insert(visibleEntries, { entry = entry, index = idx })
            if entry.type == "item" then
                currentGroupItemCount = currentGroupItemCount + 1
            end
        end
    end

    -- Manage item ticker (extracted to tracking.lua)
    CG._ManageItemTicker(currentGroupItemCount, groupIndex)

    -- Acquire icons for visible entries
    local activeIcons = CG._activeIcons
    for _, vis in ipairs(visibleEntries) do
        local icon = CG._AcquireIcon(groupIndex, container)
        local texture = GetEntryTexture(vis.entry)
        if texture then
            icon.Icon:SetTexture(texture)
        end
        icon.entry = vis.entry
        icon.entryIndex = vis.index
        icon._groupIndex = groupIndex
        icon.Cooldown:SetScript("OnCooldownDone", CG._OnIconCooldownDone)
        table.insert(activeIcons[groupIndex], icon)
    end

    -- Handle items that may need data loading
    for _, icon in ipairs(activeIcons[groupIndex]) do
        if icon.entry.type == "item" and not icon.Icon:GetTexture() then
            C_Item.RequestLoadItemDataByID(icon.entry.id)
        end
    end

    if #activeIcons[groupIndex] == 0 then
        container:Hide()
    else
        container:Show()
        CG._LayoutIcons(groupIndex)
        CG._RefreshAllCooldowns(groupIndex)
    end
end

local function RebuildAllGroups()
    for i = 1, CG.NUM_GROUPS do
        RebuildGroup(i)
        CG._ApplyBordersToGroup(i)
        CG._ApplyTextToGroup(i)
        CG._ApplyKeybindTextToGroup(i)
        CG._UpdateGroupOpacity(i)
    end
end

--------------------------------------------------------------------------------
-- Container Initialization
--------------------------------------------------------------------------------

local function InitializeContainers()
    for i = 1, CG.NUM_GROUPS do
        local container = CreateFrame("Frame", "ScootCustomGroup" .. i, UIParent)
        -- An explicit level, not just the inherited MEDIUM: a bare UIParent child
        -- lands at level 1 and loses the mouse hit-test to every overlay above it,
        -- which is what swallowed the icon tooltips under a UFZ click overlay (11).
        addon.Strata.ApplyHUD(container, 30)
        container:SetSize(1, 1)
        container:SetMovable(true)
        container:SetClampedToScreen(true)
        container:SetPoint("CENTER", 0, -100 + (i - 1) * -60)
        container:Hide()
        containers[i] = container
        addon.RegisterPetBattleFrame(container)
    end
end

--------------------------------------------------------------------------------
-- Event Handling
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- Backward-Compat Migration: enabled state
--------------------------------------------------------------------------------

local function MigrateGroupEnabledState()
    local groups = EnsureGroupsDB()
    if not groups then return end
    for i = 1, CG.NUM_GROUPS do
        local entries = groups[i] and groups[i].entries
        if entries and #entries > 0 then
            local comp = addon.Components and addon.Components["customGroup" .. i]
            if comp then
                local db = addon:EnsureComponentDB(comp)
                if db and rawget(db, "enabled") == nil then
                    db.enabled = true
                end
            end
        end
    end
end

local bagUpdatePending = false
local spellCDDirty = false
local itemCDDirty = false

local function onCustomGroupEvent(event)
    if event == "PLAYER_ENTERING_WORLD" then
        if not cgInitialized then
            InitializeContainers()
            cgInitialized = true

            C_Timer.After(0.5, function()
                MigrateGroupEnabledState()
                RebuildAllGroups()
                CG._InitializeEditMode()
            end)
        else
            RebuildAllGroups()
        end

    elseif event == "SPELL_UPDATE_COOLDOWN" or event == "SPELL_UPDATE_CHARGES" then
        if not spellCDDirty then
            spellCDDirty = true
            C_Timer.After(0, function()
                spellCDDirty = false
                CG._RefreshAllSpellCooldowns()
            end)
        end

    elseif event == "BAG_UPDATE_COOLDOWN" then
        if not itemCDDirty then
            itemCDDirty = true
            C_Timer.After(0, function()
                itemCDDirty = false
                CG._RefreshAllItemCooldowns()
            end)
        end

    elseif event == "PLAYER_SPECIALIZATION_CHANGED"
        or event == "PLAYER_TALENT_UPDATE"
        or event == "TRAIT_CONFIG_UPDATED"
        or event == "PLAYER_EQUIPMENT_CHANGED" then
        C_Timer.After(0.2, RebuildAllGroups)

    elseif event == "PLAYER_REGEN_DISABLED"
        or event == "PLAYER_REGEN_ENABLED"
        or event == "PLAYER_TARGET_CHANGED" then
        CG._UpdateAllGroupOpacities()
        -- Re-apply per-icon cooldown opacity with updated container alpha
        for gi = 1, CG.NUM_GROUPS do
            CG._UpdateGroupCooldownOpacities(gi)
        end

        if event == "PLAYER_TARGET_CHANGED" then
            C_Timer.After(0.5, function()
                CG._RefreshAllSpellCooldowns()
            end)
        end

    elseif event == "BAG_UPDATE" then
        if not bagUpdatePending then
            bagUpdatePending = true
            C_Timer.After(0.2, function()
                bagUpdatePending = false
                RebuildAllGroups()
            end)
        end

    elseif event == "ITEM_DATA_LOAD_RESULT" then
        -- Retry textures for items that may have been loading
        local activeIcons = CG._activeIcons
        for gi = 1, CG.NUM_GROUPS do
            for _, icon in ipairs(activeIcons[gi]) do
                if icon.entry and icon.entry.type == "item" and not icon.Icon:GetTexture() then
                    local texture = C_Item.GetItemIconByID(icon.entry.id)
                    if texture then
                        icon.Icon:SetTexture(texture)
                    end
                end
            end
        end
    end
end

for _, event in ipairs({
    "PLAYER_ENTERING_WORLD",
    "SPELL_UPDATE_COOLDOWN",
    "SPELL_UPDATE_CHARGES",
    "BAG_UPDATE_COOLDOWN",
    "PLAYER_SPECIALIZATION_CHANGED",
    "PLAYER_TALENT_UPDATE",
    "TRAIT_CONFIG_UPDATED",
    "PLAYER_EQUIPMENT_CHANGED",
    "PLAYER_REGEN_DISABLED",
    "PLAYER_REGEN_ENABLED",
    "PLAYER_TARGET_CHANGED",
    "ITEM_DATA_LOAD_RESULT",
    "BAG_UPDATE",
}) do
    addon.Events.On("Cooldowns:CustomGroups", event, onCustomGroupEvent)
end

--------------------------------------------------------------------------------
-- Data Model Callback → HUD Updates
--------------------------------------------------------------------------------

CG.RegisterCallback(function()
    if cgInitialized then
        RebuildAllGroups()
    end
end)

-- Refresh keybind text when bindings/talents/action bars change
if addon.SpellBindings and addon.SpellBindings.RegisterRefreshCallback then
    addon.SpellBindings.RegisterRefreshCallback(function()
        if not cgInitialized then return end
        for i = 1, CG.NUM_GROUPS do
            CG._ApplyKeybindTextToGroup(i)
        end
    end)
end

--------------------------------------------------------------------------------
-- ApplyStyling Implementation
--------------------------------------------------------------------------------

local function CustomGroupApplyStyling(component)
    local groupIndex = tonumber(component.id:match("%d+"))
    if not groupIndex then return end
    if not cgInitialized then return end

    -- Zero-Touch: skip unconfigured components (still on proxy DB)
    if addon.IsComponentUnconfigured(component) then return end

    if not component.db.enabled then
        local container = containers[groupIndex]
        if container then
            CG._ReleaseAllIcons(groupIndex)
            container:Hide()
            CG._ManageItemTicker(0, groupIndex)
        end
        return
    end

    RebuildGroup(groupIndex)
    CG._ApplyBordersToGroup(groupIndex)
    CG._ApplyTextToGroup(groupIndex)
    CG._ApplyKeybindTextToGroup(groupIndex)
    CG._UpdateGroupOpacity(groupIndex)
    CG._UpdateGroupCooldownOpacities(groupIndex)
end

--------------------------------------------------------------------------------
-- Copy From: Custom Group Settings
--------------------------------------------------------------------------------

function addon.CopyCDMCustomGroupSettings(sourceComponentId, destComponentId)
    if type(sourceComponentId) ~= "string" or type(destComponentId) ~= "string" then return end
    if sourceComponentId == destComponentId then return end

    local src = addon.Components and addon.Components[sourceComponentId]
    local dst = addon.Components and addon.Components[destComponentId]
    if not src or not dst then return end
    if not src.db or not dst.db then return end

    -- Destination must be a Custom Group
    if not destComponentId:match("^customGroup%d$") then return end

    local function deepcopy(v)
        if type(v) ~= "table" then return v end
        local out = {}
        for k, vv in pairs(v) do out[k] = deepcopy(vv) end
        return out
    end

    -- When source is Essential/Utility, skip iconSize (% scale vs pixel size)
    local isEssentialOrUtility = (sourceComponentId == "essentialCooldowns" or sourceComponentId == "utilityCooldowns")

    -- Copy all destination-defined settings from source DB
    for key, def in pairs(dst.settings or {}) do
        if key == "supportsText" or key == "enabled" then -- skip meta/activation flags
        elseif isEssentialOrUtility and key == "iconSize" then -- skip incompatible
        else
            local srcVal = src.db[key]
            if srcVal ~= nil then
                dst.db[key] = deepcopy(srcVal)
            end
        end
    end

    -- Apply styling to destination
    if dst.ApplyStyling then
        dst:ApplyStyling()
    end
end

--------------------------------------------------------------------------------
-- Helper: Any Group Enabled?
--------------------------------------------------------------------------------

function CG.IsAnyGroupEnabled()
    for i = 1, CG.NUM_GROUPS do
        local comp = addon.Components and addon.Components["customGroup" .. i]
        if comp and comp.db and comp.db.enabled then
            return true
        end
    end
    return false
end

--------------------------------------------------------------------------------
-- Component Registration (Custom Groups)
--------------------------------------------------------------------------------

-- Shared settings definition factory (all type="addon", no Edit Mode backing)
local function CreateCustomGroupSettings()
    return {
        -- Enable
        enabled = { type = "addon", default = false },

        -- Layout
        orientation = { type = "addon", default = "H" },
        direction = { type = "addon", default = "right" },
        columns = { type = "addon", default = 12 },
        iconPadding = { type = "addon", default = 2 },

        -- Anchor position
        anchorPosition = { type = "addon", default = "center" },

        -- Sizing
        iconSize = { type = "addon", default = 30 },
        tallWideRatio = { type = "addon", default = 0 },
        iconZoom = { type = "addon", default = 0 },

        -- Border
        borderEnable = { type = "addon", default = false },
        borderTintEnable = { type = "addon", default = false },
        borderTintColor = { type = "addon", default = {1, 1, 1, 1} },
        borderStyle = { type = "addon", default = "none" },
        borderThickness = { type = "addon", default = 1 },
        borderInset = { type = "addon", default = 0 },
        borderInsetH = { type = "addon", default = 0 },
        borderInsetV = { type = "addon", default = 0 },

        -- Text
        textStacks = { type = "addon", default = {} },
        textCooldown = { type = "addon", default = {} },
        textBindings = { type = "addon", default = {} },
        supportsText = { type = "addon", default = true },

        -- Visibility
        opacity = { type = "addon", default = 100 },
        opacityOutOfCombat = { type = "addon", default = 100 },
        opacityWithTarget = { type = "addon", default = 100 },
        opacityOnCooldown = { type = "addon", default = 100 },
        opacityOnCooldownText = { type = "addon", default = 100 },
        cooldownOpacityMode = { type = "addon", default = nil },
    }
end

addon:RegisterComponentInitializer(function(self)
    for i = 1, CG.NUM_GROUPS do
        local comp = Component:New({
            id = "customGroup" .. i,
            name = "Custom Group " .. i,
            settings = CreateCustomGroupSettings(),
            ApplyStyling = CustomGroupApplyStyling,
        })
        self:RegisterComponent(comp)
    end
end, "cooldownManager")
