--------------------------------------------------------------------------------
-- bars/alpha.lua
-- Alpha enforcement helpers for unit frame styling
-- 
-- IMPORTANT (taint): Avoid SetShown/Show/Hide and avoid SetScript overrides on Blizzard frames.
-- "Hidden" visuals are enforced via SetAlpha(0/1) + a deferred Show hook.
--------------------------------------------------------------------------------

local addonName, addon = ...

-- Reference to FrameState module for safe property storage (avoids writing to Blizzard frames)
local FS = addon.FrameState

-- Create module namespace
addon.BarsAlpha = addon.BarsAlpha or {}
local Alpha = addon.BarsAlpha

-- Direct upvalue to the event-driven guard (editmode/core.lua loads first in TOC)
local isEditModeActive = addon.EditMode.IsEditModeActiveOrOpening

local issecretvalue = _G.issecretvalue

--------------------------------------------------------------------------------
-- Alpha Application
--------------------------------------------------------------------------------

-- Apply alpha to a frame or texture (safe wrapper).
-- nil alpha means "config unreadable" (see the computeAlpha closures): skip the
-- write entirely rather than guessing. Restoring to visible must only ever
-- happen from an explicit settings-driven pass, never from a transient window.
function Alpha.applyAlpha(frameOrTexture, alpha)
    if alpha == nil then return end
    if not frameOrTexture or not frameOrTexture.SetAlpha then return end
    pcall(frameOrTexture.SetAlpha, frameOrTexture, alpha)
end

--------------------------------------------------------------------------------
-- Alpha Enforcement via Hooks
--------------------------------------------------------------------------------

-- Install hooks to enforce a computed alpha value on a frame/texture
-- @param frameOrTexture: The frame or texture to enforce alpha on
-- @param computeAlpha: Function that returns the desired alpha value (0 or 1)
--
-- An adapter over core/enforce.lua. The key is live whenever computeAlpha()
-- is readable (nil means the config is unreadable: skip, fail closed), and
-- its apply writes the desired value, 1 included, so a desired 1 still forces
-- visible. Show and SetShown re-assert at once and again after a stack break,
-- SetAlpha at once; every hook bails while Edit Mode is open or opening.
--
-- IMPORTANT (taint/combat): These enforcers only call SetAlpha, which is safe for visual-only
-- regions/textures even in combat. Do NOT gate on InCombatLockdown(), otherwise Blizzard can
-- Show()/SetAlpha() during combat and the element may remain visible after combat.
function Alpha.hookAlphaEnforcer(frameOrTexture, computeAlpha)
    if not frameOrTexture or type(computeAlpha) ~= "function" then return end
    local fs = FS
    if fs and fs.IsHooked(frameOrTexture, "alphaEnforcer") then return end
    if fs then fs.MarkHooked(frameOrTexture, "alphaEnforcer") end

    local function active(obj)
        if isEditModeActive() then
            if addon.RepColorTraceIfTracked then addon.RepColorTraceIfTracked(obj, "enforce", "bail: edit mode") end
            return false
        end
        if computeAlpha() == nil then
            if addon.RepColorTraceIfTracked then addon.RepColorTraceIfTracked(obj, "enforce", "skip: cfg unreadable") end
            return false
        end
        return true
    end

    local function apply(obj)
        local desired = computeAlpha()
        if desired == nil then return end
        if obj.GetAlpha and type(obj.GetAlpha) == "function" then
            local ok, current = pcall(obj.GetAlpha, obj)
            -- Guard order: type -> issecretvalue -> compare. A secret survives the
            -- pcall'd getter, and comparing it raw would error inside this hook.
            if ok and type(current) == "number"
                and not (issecretvalue and issecretvalue(current))
                and current == desired then
                return
            end
        end
        Alpha.applyAlpha(obj, desired)
    end

    addon.Enforce.Install(frameOrTexture, "alphaEnforcer", {
        methods = { "Show", "SetShown", "SetAlpha" },
        timing = { Show = "both", SetShown = "both", SetAlpha = "sync" },
        when = active,
        apply = apply,
    })
end

--------------------------------------------------------------------------------
-- Use Custom Borders Alpha Computers
--------------------------------------------------------------------------------

-- The alpha a Blizzard art region holds under the unit's Use Custom Borders
-- setting: nil while the unit's config is unreadable (the enforcer skips rather
-- than restore visibility), 0 when the setting is on (or, with withHideBorder,
-- when Hide Border is on), else 1. One closure per unit and flag, memoized, so
-- a styling pass allocates none; hookAlphaEnforcer installs once per region, so
-- closure identity never changes which install holds.
local customBordersAlphaByKey = {}
function Alpha.customBordersAlpha(unit, withHideBorder)
    local key = withHideBorder and (unit .. ":hideBorder") or unit
    local compute = customBordersAlphaByKey[key]
    if compute then return compute end
    compute = function()
        local db = addon and addon.db and addon.db.profile
        local unitFrames = db and rawget(db, "unitFrames") or nil
        local cfg = unitFrames and rawget(unitFrames, unit) or nil
        if not cfg then return nil end
        if cfg.useCustomBorders or (withHideBorder and cfg.healthBarHideBorder) then return 0 end
        return 1
    end
    customBordersAlphaByKey[key] = compute
    return compute
end

--------------------------------------------------------------------------------
-- Vehicle Frame Texture Visibility Enforcement
--------------------------------------------------------------------------------

-- Enforce visibility for vehicle-related textures
function Alpha.EnforceVehicleFrameTextureVisibility()
    -- PlayerFrame's VehicleTexture overlay. This sits above the custom border layer and
    -- normally shows a vehicle-specific atlas when mounted. If useCustomBorders is true,
    -- it is hidden so the user's custom border art is visible instead.
    local vehicleTex = _G.PlayerFrame
        and _G.PlayerFrame.PlayerFrameContainer
        and _G.PlayerFrame.PlayerFrameContainer.VehicleTexture
    if vehicleTex then
        local computeVehicleAlpha = Alpha.customBordersAlpha("Player", false)
        Alpha.applyAlpha(vehicleTex, computeVehicleAlpha())
        Alpha.hookAlphaEnforcer(vehicleTex, computeVehicleAlpha)
    end
end

--------------------------------------------------------------------------------
-- Alternate Power Frame Texture Visibility Enforcement
--------------------------------------------------------------------------------

-- Enforce visibility for alternate power bar textures
function Alpha.EnforceAlternatePowerFrameTextureVisibility()
    -- PlayerFrameAlternatePowerBarFrame (Alternate Power/Stagger bar below Player frame).
    -- When useCustomBorders is true for Player frame, hide this overlay so the custom
    -- border appears cleanly.
    local altBar = _G.PlayerFrameAlternatePowerBarFrame
    if altBar then
        local altTex = altBar.TextureBorder or altBar.BorderTexture
        if altTex then
            local computeAltAlpha = Alpha.customBordersAlpha("Player", false)
            Alpha.applyAlpha(altTex, computeAltAlpha())
            Alpha.hookAlphaEnforcer(altTex, computeAltAlpha)
        end
    end
end

return Alpha
