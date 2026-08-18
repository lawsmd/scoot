--------------------------------------------------------------------------------
-- personal_resource_display/opacity.lua
-- State-based opacity (combat > target > OOC), per-component apply functions.
--------------------------------------------------------------------------------

local addonName, addon = ...

local PRD = addon.PRD

-- Import from core
local getProp = PRD._getProp
local setProp = PRD._setProp
local ensureSettingValue = PRD._ensureSettingValue
local getHealthContainer = PRD._getHealthContainer
local getPowerBar = PRD._getPowerBar
local getAltPowerBar = PRD._getAltPowerBar

--------------------------------------------------------------------------------
-- Text overlay storage reference (set by text.lua at load time)
-- Accessed via PRD._textOverlays which text.lua promotes
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- Opacity State Machine
--------------------------------------------------------------------------------

-- Get opacity value based on current combat/target state
local function getPRDOpacityForState(componentId)
    local component = addon.Components and addon.Components[componentId]
    if not component or not component.db then return 1.0 end

    local db = component.db
    local inCombat = InCombatLockdown and InCombatLockdown()
    local hasTarget = UnitExists("target")

    -- Priority: combat > target > out-of-combat
    local opacityValue
    if inCombat then
        opacityValue = tonumber(db.opacityInCombat) or 100
    elseif hasTarget then
        opacityValue = tonumber(db.opacityWithTarget) or 100
    else
        opacityValue = tonumber(db.opacityOutOfCombat) or 100
    end

    -- Convert from percentage (1-100) to alpha (0.01-1.0)
    return math.max(0.01, math.min(1.0, opacityValue / 100))
end

-- Apply opacity to prdHealth component
local function applyPRDHealthOpacity()
    local component = addon.Components and addon.Components.prdHealth
    if not component or not component.db then return end
    -- Zero-Touch: skip unconfigured components (still on proxy DB)
    if component._ScootDBProxy and component.db == component._ScootDBProxy then return end

    -- Skip if bar is hidden
    if component.db.hideBar then return end

    local container = getHealthContainer()
    if not container then return end

    -- Scoot's overlays (fill/background/border/text) are children of the container
    -- and inherit this alpha; nothing else to set.
    local alpha = getPRDOpacityForState("prdHealth")
    pcall(container.SetAlpha, container, alpha)
end

-- Apply opacity to prdPower component
local function applyPRDPowerOpacity()
    local component = addon.Components and addon.Components.prdPower
    if not component or not component.db then return end
    -- Zero-Touch: skip unconfigured components (still on proxy DB)
    if component._ScootDBProxy and component.db == component._ScootDBProxy then return end

    -- Skip if bar is hidden
    if component.db.hideBar then return end

    local frame = getPowerBar()
    if not frame then return end

    -- Overlays are children of the bar and inherit this alpha.
    local alpha = getPRDOpacityForState("prdPower")
    pcall(frame.SetAlpha, frame, alpha)
end

-- Apply opacity to prdAltPower component
local function applyPRDAltPowerOpacity()
    local component = addon.Components and addon.Components.prdAltPower
    if not component or not component.db then return end
    -- Zero-Touch: skip unconfigured components (still on proxy DB)
    if component._ScootDBProxy and component.db == component._ScootDBProxy then return end

    -- Skip if bar is hidden
    if component.db.hideBar then return end

    local frame = getAltPowerBar()
    if not frame then return end

    -- Overlays are children of the bar and inherit this alpha.
    local alpha = getPRDOpacityForState("prdAltPower")
    pcall(frame.SetAlpha, frame, alpha)
end

-- Apply opacity to prdClassResource component
local function applyPRDClassResourceOpacity()
    local component = addon.Components and addon.Components.prdClassResource
    if not component or not component.db then return end
    -- Zero-Touch: skip unconfigured components (still on proxy DB)
    if component._ScootDBProxy and component.db == component._ScootDBProxy then return end

    -- Skip if bar is hidden
    if component.db.hideBar then return end

    local prd = PersonalResourceDisplayFrame
    if not prd then return end
    local classContainer = prd.ClassFrameContainer
    if not classContainer then return end

    local frame
    if classContainer.GetChildren then
        frame = classContainer:GetChildren()
    end
    if not frame then return end
    if frame.IsForbidden and frame:IsForbidden() then return end

    local alpha = getPRDOpacityForState("prdClassResource")
    pcall(frame.SetAlpha, frame, alpha)
end

-- Update all PRD component opacities based on current state
local function updateAllPRDOpacities()
    applyPRDHealthOpacity()
    applyPRDPowerOpacity()
    applyPRDAltPowerOpacity()
    applyPRDClassResourceOpacity()
end

-- Exposed function for settings changes (immediate slider feedback)
function addon.RefreshPRDOpacity(componentId)
    if componentId == "prdHealth" then
        applyPRDHealthOpacity()
    elseif componentId == "prdPower" then
        applyPRDPowerOpacity()
    elseif componentId == "prdAltPower" then
        applyPRDAltPowerOpacity()
    elseif componentId == "prdClassResource" then
        applyPRDClassResourceOpacity()
    else
        updateAllPRDOpacities()
    end
end

local function storeOriginalAlpha(frame, storageKey)
    if not frame or not frame.GetAlpha then
        return
    end
    storageKey = storageKey or "_ScootPRDOrigAlpha"
    if getProp(frame, storageKey) ~= nil then
        return
    end
    local ok, alpha = pcall(frame.GetAlpha, frame)
    setProp(frame, storageKey, ok and (alpha or 1) or 1)
end

local function applyHiddenAlpha(frame, hidden, storageKey)
    if not frame or not frame.SetAlpha then
        return
    end
    storageKey = storageKey or "_ScootPRDOrigAlpha"
    if hidden then
        storeOriginalAlpha(frame, storageKey)
        pcall(frame.SetAlpha, frame, 0)
    else
        local original = getProp(frame, storageKey)
        if original == nil then
            original = 1
        end
        pcall(frame.SetAlpha, frame, original)
    end
end

--------------------------------------------------------------------------------
-- Namespace Promotions
--------------------------------------------------------------------------------

PRD._getPRDOpacityForState = getPRDOpacityForState
PRD._updateAllPRDOpacities = updateAllPRDOpacities
PRD._applyPRDHealthOpacity = applyPRDHealthOpacity
PRD._applyPRDPowerOpacity = applyPRDPowerOpacity
PRD._applyPRDAltPowerOpacity = applyPRDAltPowerOpacity
PRD._applyPRDClassResourceOpacity = applyPRDClassResourceOpacity
PRD._storeOriginalAlpha = storeOriginalAlpha
PRD._applyHiddenAlpha = applyHiddenAlpha
