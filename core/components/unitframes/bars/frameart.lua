--------------------------------------------------------------------------------
-- bars/frameart.lua
-- Blizzard frame art suppression behind Use Custom Borders (and Hide Border for
-- the FrameTexture): the stock frame texture, the Target prestige art, the
-- Player alternate and vehicle textures, the ReputationColor strips, and the
-- threat Flash regions. Each region gets its alpha written and an enforcer
-- that holds it (bars/alpha.lua).
--------------------------------------------------------------------------------

local addonName, addon = ...

addon.BarsFrameArt = addon.BarsFrameArt or {}
local FrameArt = addon.BarsFrameArt

local Resolvers = addon.BarsResolvers
local Alpha = addon.BarsAlpha

local resolveUnitFrameFrameTexture = Resolvers.resolveUnitFrameFrameTexture
local applyAlpha = Alpha.applyAlpha
local hookAlphaEnforcer = Alpha.hookAlphaEnforcer
local customBordersAlpha = Alpha.customBordersAlpha

-- Write the region's alpha now and install the enforcer that holds it.
local function enforce(region, alpha)
    if not region then return end
    applyAlpha(region, alpha())
    hookAlphaEnforcer(region, alpha)
end

-- The ReputationColor strip of the Target or Focus frame, resolved live because
-- Blizzard can recreate it during rapid target changes.
local function resolveReputationColor(unit)
    local root = (unit == "Target" and _G.TargetFrame) or (unit == "Focus" and _G.FocusFrame) or nil
    return root and root.TargetFrameContent
        and root.TargetFrameContent.TargetFrameContentMain
        and root.TargetFrameContent.TargetFrameContentMain.ReputationColor
end

-- Threat glow per unit: PlayerFrame's FrameFlash, the Target and Focus Flash.
local FLASH = {
    Player = function()
        local container = _G.PlayerFrame and _G.PlayerFrame.PlayerFrameContainer
        return container and container.FrameFlash
    end,
    Target = function()
        local container = _G.TargetFrame and _G.TargetFrame.TargetFrameContainer
        return container and container.Flash
    end,
    Focus = function()
        local container = _G.FocusFrame and _G.FocusFrame.TargetFrameContainer
        return container and container.Flash
    end,
}

-- Target and Focus ReputationColor, run by applyForUnit (bars.lua) before the
-- health and power passes. Target/Focus frames can be updated or rebuilt by
-- Blizzard during combat (rapid target swaps, faction updates); protected
-- StatusBars and layout are never touched then, but a visual-only region can
-- be held through SetAlpha plus an enforcer, so the strip stays hidden even
-- when Blizzard recreates it. A deferred re-hide catches a late recreate.
function FrameArt.applyEarly(unit)
    if unit ~= "Target" and unit ~= "Focus" then return end
    local alpha = customBordersAlpha(unit, false)
    local reputationColor = resolveReputationColor(unit)
    if not reputationColor then return end

    -- Always apply current alpha, regardless of hook state
    enforce(reputationColor, alpha)

    C_Timer.After(0, function()
        -- Re-resolve in case the texture object changed
        local repColor2 = resolveReputationColor(unit)
        if repColor2 and repColor2.SetAlpha then
            local alpha2 = alpha()
            -- nil = config unreadable at this tick: skip the write
            -- (never restore visible from a transient window)
            if alpha2 ~= nil then
                pcall(repColor2.SetAlpha, repColor2, alpha2)
            end
            -- Install enforcer on the (possibly new) object
            hookAlphaEnforcer(repColor2, alpha)
        end
    end)
end

-- Run by applyForUnit (bars.lua) after the health and power passes for Player,
-- Target, and Focus. These regions have fixed positions that cannot follow a
-- repositioned or resized bar, so they are hidden whenever Use Custom Borders
-- is on. The ReputationColor branch is the one place that writes alpha 1 back
-- when the setting is off; the enforcers never restore visibility on their own.
function FrameArt.apply(unit, cfg)
    -- Stock frame art (includes the health bar border)
    enforce(resolveUnitFrameFrameTexture(unit), customBordersAlpha(unit, true))

    -- Target-specific prestige elements (PvP badge/portrait)
    if unit == "Target" then
        local contextual = _G.TargetFrame
            and _G.TargetFrame.TargetFrameContent
            and _G.TargetFrame.TargetFrameContent.TargetFrameContentContextual
        if contextual then
            local alpha = customBordersAlpha("Target", false)
            enforce(contextual.PrestigePortrait, alpha)
            enforce(contextual.PrestigeBadge, alpha)
            enforce(contextual.PvpIcon, alpha)
        end
    end

    -- Player-specific frame art
    if unit == "Player" and _G.PlayerFrame and _G.PlayerFrame.PlayerFrameContainer then
        local container = _G.PlayerFrame.PlayerFrameContainer
        local alpha = customBordersAlpha("Player", false)
        enforce(container.AlternatePowerFrameTexture, alpha)
        enforce(container.VehicleFrameTexture, alpha)
    end

    -- ReputationColor for Target/Focus: hidden with Use Custom Borders on,
    -- restored to visible with it off.
    if unit == "Target" or unit == "Focus" then
        local reputationColor = resolveReputationColor(unit)
        if reputationColor then
            applyAlpha(reputationColor, cfg.useCustomBorders and 0 or 1)
            hookAlphaEnforcer(reputationColor, customBordersAlpha(unit, false))
        end
    end

    -- Threat glow (FrameFlash / Flash)
    local flash = FLASH[unit]
    if flash then
        enforce(flash(), customBordersAlpha(unit, false))
    end
end

return FrameArt
