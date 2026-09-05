-- opacity.lua - Cooldown Manager: viewer-level and per-icon cooldown opacity
-- SetAlpha on viewer containers is safe. Drives combat, out-of-combat, and
-- with-target opacity settings (stored as 50-100, converted to 0.0-1.0).
local addonName, addon = ...

local SS = addon.SecretSafe
local Overlays = addon.CDMOverlays
local CDM_VIEWERS = addon.CDM_VIEWERS

-- Track which FontStrings have been decoupled from parent alpha (weak keys for GC)
local textAlphaDecoupled = setmetatable({}, { __mode = "k" })

local offCDRefreshTicker = nil
-- Forward declaration; body defined after applyPerIconCooldownOpacity exists
local startOffCDRefreshTicker

-- All viewers that support opacity (including trackedBars)
local CDM_OPACITY_VIEWERS = {
    EssentialCooldownViewer = "essentialCooldowns",
    UtilityCooldownViewer = "utilityCooldowns",
    BuffIconCooldownViewer = "trackedBuffs",
    BuffBarCooldownViewer = "trackedBars",
}
Overlays._opacityViewers = CDM_OPACITY_VIEWERS

-- Get the appropriate opacity value based on current game state
-- Container alpha for the viewer's current state (core/opacity.lua). The
-- combat value is the Edit Mode setting, stored as 50-100.
local function getViewerOpacityForState(componentId)
    local component = addon.Components and addon.Components[componentId]
    if not component or not component.db then return 1.0 end
    local alpha = addon.Opacity.Resolve(component.db, addon.Opacity.Keys.Plain)
    return alpha
end

-- Apply opacity to a single viewer frame and its overlays
local applyViewerOpacity = function(viewerName, componentId)
    local viewer = _G[viewerName]
    if not viewer then return end

    if viewer.IsForbidden and viewer:IsForbidden() then return end

    -- Zero-Touch: skip unconfigured components (still on proxy DB)
    local component = addon.Components and addon.Components[componentId]
    if addon.IsComponentUnconfigured(component) then return end

    local alpha = getViewerOpacityForState(componentId)

    -- Apply to viewer frame
    -- Overlays are parented to CDM icons (children of the viewer), so they
    -- automatically inherit the viewer's alpha through the parent chain.
    -- No need to explicitly set overlay alpha - doing so would double-reduce it.
    pcall(function()
        viewer:SetAlpha(alpha)
    end)
end
Overlays._ApplyViewerOpacity = applyViewerOpacity

-- Update all CDM viewer opacities based on current state
local function updateAllViewerOpacities()
    for viewerName, componentId in pairs(CDM_OPACITY_VIEWERS) do
        applyViewerOpacity(viewerName, componentId)
    end
end
Overlays._UpdateAllViewerOpacities = updateAllViewerOpacities

-- Exposed function for settings changes
function addon.RefreshCDMViewerOpacity(componentId)
    if componentId then
        -- Refresh specific component
        for viewerName, cid in pairs(CDM_OPACITY_VIEWERS) do
            if cid == componentId then
                applyViewerOpacity(viewerName, componentId)
                break
            end
        end
    else
        -- Refresh all
        updateAllViewerOpacities()
    end
end

--------------------------------------------------------------------------------
-- Per-Icon Cooldown Opacity (Essential/Utility CDM)
--------------------------------------------------------------------------------
-- Uses SetAlphaFromBoolean with secret boolean from Duration Object IsZero()
-- to dim individual CDM icons when their spell is on cooldown.
-- GCD filtered via isOnGCD (NeverSecret). SetAlphaFromBoolean evaluates secret booleans in C++ without Lua-side inspection.
-- Text opacity can be controlled independently via opacityOnCooldownText.
-- When text differs from icon, SetIgnoreParentAlpha decouples the Cooldown frame
-- from the icon frame's alpha chain and SetAlphaFromBoolean drives it independently.
-- Targets the Cooldown frame (not its FontString) because Blizzard's C++ cooldown
-- renderer resets the FontString's alpha every frame, overriding the styled values.
--------------------------------------------------------------------------------

local function applyTextCooldownAlpha(cooldownFrame, durObj, containerAlpha, textDimAlpha, isGCD, isOffCooldownMode)
    -- cooldownFrame keys the textAlphaDecoupled weak table below
    cooldownFrame = SS.plainFrame(cooldownFrame)
    if not cooldownFrame then return end
    pcall(cooldownFrame.SetIgnoreParentAlpha, cooldownFrame, true)
    textAlphaDecoupled[cooldownFrame] = true
    if isGCD then
        pcall(cooldownFrame.SetAlpha, cooldownFrame, containerAlpha)
    else
        local readyAlpha = containerAlpha
        local cdAlpha = math.min(containerAlpha, textDimAlpha)
        if isOffCooldownMode then readyAlpha, cdAlpha = cdAlpha, readyAlpha end
        local zeroOk, isZero = pcall(durObj.IsZero, durObj)
        if not zeroOk then
            pcall(cooldownFrame.SetAlpha, cooldownFrame, containerAlpha)
            return
        end
        pcall(cooldownFrame.SetAlphaFromBoolean, cooldownFrame, isZero, readyAlpha, cdAlpha)
    end
end

local function resetTextAlpha(cooldownFrame)
    cooldownFrame = SS.plainFrame(cooldownFrame)
    if cooldownFrame and textAlphaDecoupled[cooldownFrame] then
        pcall(cooldownFrame.SetIgnoreParentAlpha, cooldownFrame, false)
        pcall(cooldownFrame.SetAlpha, cooldownFrame, 1.0)
        textAlphaDecoupled[cooldownFrame] = nil
    end
end

local function processOneIconOpacity(child, iconSetting, readyAlpha, cdAlpha, needsTextOverride, containerAlpha, textDimAlpha, isOffCooldownMode)
    if not Overlays._IsValidCDMItemFrame(child) or not Overlays._IsFrameVisible(child) then return end

    local idOk, spellId = pcall(child.GetBaseSpellID, child)
    if not idOk or not spellId then return end

    if C_Spell.GetOverrideSpell then
        local overrideOk, overrideId = pcall(C_Spell.GetOverrideSpell, spellId)
        if overrideOk and type(overrideId) == "number"
           and not (issecretvalue and issecretvalue(overrideId))
           and overrideId ~= 0 then
            spellId = overrideId
        end
    end

    local cdInfo = C_Spell.GetSpellCooldown(spellId)
    local isGCD = cdInfo and cdInfo.isOnGCD
    local durObj = not isGCD and C_Spell.GetSpellCooldownDuration(spellId) or nil

    -- Icon frame opacity
    if iconSetting >= 100 then
        pcall(child.SetAlpha, child, 1.0)
    elseif isGCD then
        pcall(child.SetAlpha, child, readyAlpha)
    elseif durObj and durObj.IsZero then
        local zeroOk, isZero = pcall(durObj.IsZero, durObj)
        if zeroOk then
            pcall(child.SetAlphaFromBoolean, child, isZero, readyAlpha, cdAlpha)
        else
            pcall(child.SetAlpha, child, readyAlpha)
        end
    else
        pcall(child.SetAlpha, child, readyAlpha)
    end

    -- Text opacity (independent when text != icon setting)
    if needsTextOverride and child.Cooldown then
        if isGCD then
            applyTextCooldownAlpha(child.Cooldown, nil, containerAlpha, textDimAlpha, true, isOffCooldownMode)
        elseif durObj and durObj.IsZero then
            applyTextCooldownAlpha(child.Cooldown, durObj, containerAlpha, textDimAlpha, false, isOffCooldownMode)
        else
            resetTextAlpha(child.Cooldown)
        end
    elseif not needsTextOverride and child.Cooldown then
        resetTextAlpha(child.Cooldown)
    end
end

local applyPerIconCooldownOpacity = function(viewerFrameName, componentId)
    local viewer = _G[viewerFrameName]
    if not viewer then return end
    local component = addon.Components and addon.Components[componentId]
    if not component or not component.db then return end

    local iconSetting = tonumber(component.db.opacityOnCooldown) or 100
    local textSetting = tonumber(component.db.opacityOnCooldownText) or 100

    -- Nothing to do if both are at 100%
    if iconSetting >= 100 and textSetting >= 100 then return end

    local mode = component.db.cooldownOpacityMode
    local isOffCooldownMode = (mode == "offCooldown")

    local containerAlpha = getViewerOpacityForState(componentId)
    local needsTextOverride = not isOffCooldownMode and (textSetting ~= iconSetting)

    -- Compute icon dim alpha (compensated for container opacity)
    local iconDimAlpha = iconSetting / 100
    if iconSetting < 100 and containerAlpha > 0 and containerAlpha < 1.0 then
        iconDimAlpha = math.min(1.0, iconDimAlpha / containerAlpha)
    end

    -- Pre-compute ready/cd alphas based on mode
    local readyAlpha, cdAlpha = 1.0, iconDimAlpha
    if isOffCooldownMode then readyAlpha, cdAlpha = cdAlpha, readyAlpha end

    -- Compute text dim alpha (absolute, used with SetIgnoreParentAlpha)
    local textDimAlpha = textSetting / 100

    for _, child in ipairs(Overlays._GetViewerChildren(viewer, viewerFrameName)) do
        pcall(processOneIconOpacity, child, iconSetting, readyAlpha, cdAlpha,
              needsTextOverride, containerAlpha, textDimAlpha, isOffCooldownMode)
    end

    -- Keep ticker alive while off-cooldown mode needs refresh
    if isOffCooldownMode and iconSetting < 100 then
        startOffCDRefreshTicker()
    end
end
Overlays._ApplyPerIconCooldownOpacity = applyPerIconCooldownOpacity

addon.RefreshCDMCooldownOpacity = applyPerIconCooldownOpacity

-- 1s safety ticker: catches long-cooldown-end while idle (no event fires).
-- Self-terminates when no viewer needs off-cooldown refresh.
startOffCDRefreshTicker = function()
    if offCDRefreshTicker then return end
    offCDRefreshTicker = C_Timer.NewTicker(1.0, function()
        local anyActive = false
        for viewerName, componentId in pairs(CDM_VIEWERS) do
            local component = addon.Components and addon.Components[componentId]
            if component and component.db
               and component.db.cooldownOpacityMode == "offCooldown"
               and (tonumber(component.db.opacityOnCooldown) or 100) < 100 then
                applyPerIconCooldownOpacity(viewerName, componentId)
                anyActive = true
            end
        end
        if not anyActive then
            offCDRefreshTicker:Cancel()
            offCDRefreshTicker = nil
        end
    end)
end
