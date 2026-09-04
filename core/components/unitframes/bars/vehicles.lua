--------------------------------------------------------------------------------
-- bars/vehicles.lua
-- Vehicle/AlternatePower frame texture enforcement + Show hooks.
-- Re-enforces hiding of VehicleFrameTexture and AlternatePowerFrameTexture
-- after Blizzard art transitions (vehicle enter/exit).
--------------------------------------------------------------------------------

local addonName, addon = ...

local function hideVehicleArt(tex)
    local hide = tex.HideBase or tex.Hide
    if hide then hide(tex) end
end

local VEHICLE_ART_OPTS = {
    methods = { "Show" },
    apply = hideVehicleArt,
    when = function()
        local db = addon and addon.db and addon.db.profile
        local unitFrames = db and rawget(db, "unitFrames") or nil
        local cfgP = unitFrames and rawget(unitFrames, "Player") or nil
        return cfgP ~= nil and cfgP.useCustomBorders == true
    end,
}

-- Direct upvalue to the event-driven guard (editmode/core.lua loads first in TOC)
local isEditModeActive = addon.EditMode.IsEditModeActiveOrOpening

-- Enforce VehicleFrameTexture visibility based on Use Custom Borders setting
local function EnforceVehicleFrameTextureVisibility()
    if isEditModeActive() then return end
    local db = addon and addon.db and addon.db.profile
    local unitFrames = db and rawget(db, "unitFrames") or nil
    local cfg = unitFrames and rawget(unitFrames, "Player") or nil
    if not cfg then return end
    if cfg.useCustomBorders ~= true then return end -- Only enforce when custom borders enabled

    local container = _G.PlayerFrame and _G.PlayerFrame.PlayerFrameContainer
    local vehicleTex = container and container.VehicleFrameTexture
    if vehicleTex and vehicleTex.SetShown then
        pcall(vehicleTex.SetShown, vehicleTex, false)
    end
end

-- Enforce AlternatePowerFrameTexture visibility based on Use Custom Borders setting
local function EnforceAlternatePowerFrameTextureVisibility()
    if isEditModeActive() then return end
    local db = addon and addon.db and addon.db.profile
    local unitFrames = db and rawget(db, "unitFrames") or nil
    local cfg = unitFrames and rawget(unitFrames, "Player") or nil
    if not cfg then return end
    if cfg.useCustomBorders ~= true then return end -- Only enforce when custom borders enabled

    local container = _G.PlayerFrame and _G.PlayerFrame.PlayerFrameContainer
    local altTex = container and container.AlternatePowerFrameTexture
    if altTex and altTex.SetShown then
        pcall(altTex.SetShown, altTex, false)
    end
end

-- Hook Blizzard's vehicle art transitions to re-enforce hiding.

if not addon._VehicleArtHooksInstalled then
    addon._VehicleArtHooksInstalled = true

    -- Hook PlayerFrame_ToVehicleArt to re-enforce VehicleFrameTexture hiding
    -- Called when entering a vehicle (Blizzard shows VehicleFrameTexture)
    if _G.hooksecurefunc and type(_G.PlayerFrame_ToVehicleArt) == "function" then
        _G.hooksecurefunc("PlayerFrame_ToVehicleArt", function()
            if _G.C_Timer and _G.C_Timer.After then
                _G.C_Timer.After(0, EnforceVehicleFrameTextureVisibility)
            else
                EnforceVehicleFrameTextureVisibility()
            end
        end)
    end

    -- Hook PlayerFrame_ToPlayerArt to re-enforce AlternatePowerFrameTexture hiding
    -- Called when exiting a vehicle (Blizzard shows AlternatePowerFrameTexture)
    if _G.hooksecurefunc and type(_G.PlayerFrame_ToPlayerArt) == "function" then
        _G.hooksecurefunc("PlayerFrame_ToPlayerArt", function()
            if _G.C_Timer and _G.C_Timer.After then
                _G.C_Timer.After(0, EnforceAlternatePowerFrameTextureVisibility)
            else
                EnforceAlternatePowerFrameTextureVisibility()
            end
        end)
    end

    -- Show() hooks on the textures themselves, for any Show() call and not
    -- just the known Blizzard functions (core/enforce.lua; the key reads the
    -- setting live and hides with Hide).
    local container = _G.PlayerFrame and _G.PlayerFrame.PlayerFrameContainer
    addon.Enforce.Install(container and container.VehicleFrameTexture, "vehicleArt", VEHICLE_ART_OPTS)
    addon.Enforce.Install(container and container.AlternatePowerFrameTexture, "vehicleArt", VEHICLE_ART_OPTS)
end
