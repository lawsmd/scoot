local addonName, addon = ...

--[[
    Unit Frame Scale Multiplier
    
    Layers an addon-only scale multiplier on top of Edit Mode's existing scale.
    This allows users to scale unit frames beyond the 200% Edit Mode limit.
    
    Key insight: The baseline must NOT be read from frame:GetScale() because the frame
    may retain a previously-applied multiplied scale across reloads. Instead, the
    Edit Mode scale value is read directly and the result computed: emScale * multiplier.
]]

-- Debug helper (disabled by default)
local DEBUG_SCALE_MULT = false
local function debugPrint(...)
    if DEBUG_SCALE_MULT and addon and addon.DebugPrint then
        addon.DebugPrint("[ScaleMult]", ...)
    elseif DEBUG_SCALE_MULT then
        print("[Scoot ScaleMult]", ...)
    end
end

-- Resolve unit frame for a given unit key
local function getUnitFrameFor(unit)
    if unit == "Player" then
        return _G.PlayerFrame
    elseif unit == "Target" then
        return _G.TargetFrame
    elseif unit == "Focus" then
        return _G.FocusFrame
    elseif unit == "Pet" then
        return _G.PetFrame
    end
end

-- Get the Edit Mode registered frame for a unit
local function getEditModeFrameFor(unit)
    local mgr = _G.EditModeManagerFrame
    local EM = _G.Enum and _G.Enum.EditModeUnitFrameSystemIndices
    local EMSys = _G.Enum and _G.Enum.EditModeSystem
    if not (mgr and EM and EMSys and mgr.GetRegisteredSystemFrame) then return nil end
    
    local idx
    if unit == "Player" then idx = EM.Player
    elseif unit == "Target" then idx = EM.Target
    elseif unit == "Focus" then idx = EM.Focus
    elseif unit == "Pet" then idx = EM.Pet
    end
    if not idx then return nil end
    
    return mgr:GetRegisteredSystemFrame(EMSys.UnitFrame, idx)
end

-- Read Edit Mode's FrameSize setting for a unit (returns 100-200, or nil if unavailable)
local function getEditModeScale(unit)
    local frameUF = getEditModeFrameFor(unit)
    local settingId = _G.Enum and _G.Enum.EditModeUnitFrameSetting and _G.Enum.EditModeUnitFrameSetting.FrameSize
    if not (frameUF and settingId and addon and addon.EditMode and addon.EditMode.GetSetting) then
        return nil
    end
    
    local v = addon.EditMode.GetSetting(frameUF, settingId)
    if v == nil then return 100 end
    
    -- Edit Mode may store as index (0-20) or direct value (100-200)
    if v <= 20 then
        return 100 + (v * 5)
    end
    return math.max(100, math.min(200, v))
end

-- Zero‑Touch: return the unit frame config table only if it already exists.
-- Do NOT create `db.unitFrames[unit]` implicitly; new profiles must be stock Blizzard UI.
local function getUFDB(unit)
    local db = addon and addon.db and addon.db.profile
    if not db then return nil end
    local unitFrames = rawget(db, "unitFrames")
    return unitFrames and rawget(unitFrames, unit) or nil
end

-- Clamp scale multiplier to valid range (1.0 to 2.0)
local function clampScaleMult(value)
    local v = tonumber(value) or 1.0
    if v < 1.0 then return 1.0 end
    if v > 2.0 then return 2.0 end
    return v
end

-- Apply scale multiplier for a single unit
local function applyScaleMultFor(unit)
    -- PetFrame is an Edit Mode managed/protected frame; do not scale it from addon code.
    if unit == "Pet" then
        return
    end

    local cfg = getUFDB(unit)
    if not cfg then return end
    -- Zero‑Touch: only apply when the user explicitly configured the multiplier.
    if cfg.scaleMult == nil then return end
    
    local frame = getUnitFrameFor(unit)
    if not frame then
        debugPrint("No frame for", unit)
        return
    end
    
    -- Check for forbidden frame
    if frame.IsForbidden and frame:IsForbidden() then
        debugPrint("Frame forbidden for", unit)
        return
    end
    
    local scaleMult = clampScaleMult(cfg.scaleMult)
    
    -- Read Edit Mode's scale value directly (100-200) and convert to scale factor
    -- KEY: frame:GetScale() is not trusted because it may contain
    -- a previously-applied multiplier from before reload
    local emScaleValue = getEditModeScale(unit) or 100
    local emScaleFactor = emScaleValue / 100  -- 100 → 1.0, 200 → 2.0
    
    -- Calculate new scale: Edit Mode scale x addon multiplier
    local newScale = emScaleFactor * scaleMult
    
    -- Skip ALL scale changes during combat - SetScale on unit frames triggers
    -- Edit Mode's protected SetScaleBase() method, causing taint errors
    if InCombatLockdown and InCombatLockdown() then
        debugPrint("Skipping scale change for", unit, "during combat")
        return
    end
    
    if frame.SetScale then
        local ok, err = pcall(frame.SetScale, frame, newScale)
        if ok then
            debugPrint("Applied scale", newScale, "to", unit, "(emScale:", emScaleFactor, "mult:", scaleMult, ")")
        else
            debugPrint("Failed to apply scale to", unit, ":", err)
        end
    end
end

-- Apply scale multiplier to all unit frames
local function applyAllScaleMults()
    local units = { "Player", "Target", "Focus", "Pet" }
    for _, unit in ipairs(units) do
        applyScaleMultFor(unit)
    end
end

-- Reapply scale after Edit Mode layout changes
-- This should be called from EDIT_MODE_LAYOUTS_UPDATED handler
local function onLayoutsUpdated()
    -- Defer application slightly to let Edit Mode finish its updates
    if C_Timer and C_Timer.After then
        C_Timer.After(0.1, function()
            -- Skip if combat started during the delay
            if InCombatLockdown and InCombatLockdown() then
                return
            end
            applyAllScaleMults()
        end)
    else
        if InCombatLockdown and InCombatLockdown() then
            return
        end
        applyAllScaleMults()
    end
end

-- Expose functions on addon object
addon.ApplyUnitFrameScaleMultFor = applyScaleMultFor
addon.ApplyAllUnitFrameScaleMults = applyAllScaleMults
addon.OnUnitFrameScaleMultLayoutsUpdated = onLayoutsUpdated

-- Legacy function kept for compatibility (no-op now since Edit Mode is read directly)
addon.InvalidateUnitFrameScaleMultBaselines = function()
    debugPrint("InvalidateUnitFrameScaleMultBaselines called (no-op, Edit Mode is read directly)")
end

