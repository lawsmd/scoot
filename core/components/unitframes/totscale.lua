local addonName, addon = ...

--[[
    Target of Target (ToT) and Focus Target (FoT) Positioning and Scaling

    These frames are NOT Edit Mode managed - Blizzard creates them as children
    of Target/Focus frames. SetScale() and SetPoint() can safely be used outside
    combat with proper guards.

    Key considerations:
    - TargetFrameToT: Never re-anchored during gameplay, positioning persists
    - FocusFrameToT: Re-anchored by FocusFrameMixin:SetSmallSize() when toggling
      Focus frame size - requires SetPoint hook to persist the custom position
]]

-- Reference to FrameState module for safe property storage (avoids writing to Blizzard frames)
local FS = nil
local function ensureFS()
    if not FS then FS = addon.FrameState end
    return FS
end

local function getProp(frame, key)
    local fs = ensureFS()
    if not fs then return nil end
    local st = fs.Get(frame)
    return st and st[key] or nil
end

local function setProp(frame, key, value)
    local fs = ensureFS()
    if not fs then return end
    local st = fs.Get(frame)
    if st then
        st[key] = value
    end
end

-- Debug helper (disabled by default)
local DEBUG_TOT_SCALE = false
local function debugPrint(...)
    if DEBUG_TOT_SCALE and addon and addon.DebugPrint then
        addon.DebugPrint("[ToTScale]", ...)
    elseif DEBUG_TOT_SCALE then
        print("[Scoot ToTScale]", ...)
    end
end

--------------------------------------------------------------------------------
-- Combat Deferral
--------------------------------------------------------------------------------

-- Track pending applies to run when combat ends
local pendingApplies = {}

-- Event frame for combat deferral
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_REGEN_ENABLED" then
        -- Apply any pending scale/position changes
        for key, fn in pairs(pendingApplies) do
            if type(fn) == "function" then
                local ok, err = pcall(fn)
                if not ok then
                    debugPrint("Deferred apply failed for", key, ":", err)
                end
            end
        end
        wipe(pendingApplies)
    end
end)

--------------------------------------------------------------------------------
-- Zero-Touch DB Access
--------------------------------------------------------------------------------

-- Return the ToT config table only if it already exists (Zero-Touch policy)
local function getToTDB()
    local db = addon and addon.db and addon.db.profile
    if not db then return nil end
    local unitFrames = rawget(db, "unitFrames")
    return unitFrames and rawget(unitFrames, "TargetOfTarget") or nil
end

-- Return the FocusTarget config table only if it already exists (Zero-Touch policy)
local function getFocusTargetDB()
    local db = addon and addon.db and addon.db.profile
    if not db then return nil end
    local unitFrames = rawget(db, "unitFrames")
    return unitFrames and rawget(unitFrames, "FocusTarget") or nil
end

--------------------------------------------------------------------------------
-- Frame Resolution
--------------------------------------------------------------------------------

local function getTargetFrameToT()
    return _G.TargetFrameToT
end

local function getFocusFrameToT()
    return _G.FocusFrameToT
end

--------------------------------------------------------------------------------
-- Original Anchor Capture
--------------------------------------------------------------------------------

-- Store original anchors once per frame to prevent compounding offsets
local originalAnchors = {}

local function captureOriginalAnchor(frame, frameKey)
    if originalAnchors[frameKey] then
        return originalAnchors[frameKey]
    end

    if frame and frame.GetPoint then
        local point, relativeTo, relativePoint, xOfs, yOfs = frame:GetPoint(1)
        if point then
            originalAnchors[frameKey] = {
                point = point,
                relativeTo = relativeTo,
                relativePoint = relativePoint,
                xOfs = xOfs or 0,
                yOfs = yOfs or 0,
            }
            debugPrint("Captured original anchor for", frameKey, ":", point, relativePoint, xOfs, yOfs)
            return originalAnchors[frameKey]
        end
    end
end

--------------------------------------------------------------------------------
-- Target of Target (ToT) Scale and Position
--------------------------------------------------------------------------------

local function applyToTScale()
    local cfg = getToTDB()
    if not cfg then return end

    -- Zero-Touch: only apply when user has explicitly configured scale
    if cfg.scale == nil then return end

    local frame = getTargetFrameToT()
    if not frame then
        debugPrint("ToT frame not found")
        return
    end

    -- Check for forbidden frame
    if frame.IsForbidden and frame:IsForbidden() then
        debugPrint("ToT frame is forbidden")
        return
    end

    local scale = tonumber(cfg.scale) or 1.0
    -- Clamp to valid range (0.5 to 2.0)
    if scale < 0.5 then scale = 0.5 end
    if scale > 2.0 then scale = 2.0 end

    -- Combat guard - defer to when combat ends
    if InCombatLockdown and InCombatLockdown() then
        debugPrint("Combat lockdown, deferring ToT scale")
        pendingApplies["ToTScale"] = applyToTScale
        return
    end

    if frame.SetScale then
        local ok, err = pcall(frame.SetScale, frame, scale)
        if ok then
            debugPrint("Applied ToT scale:", scale)
        else
            debugPrint("Failed to apply ToT scale:", err)
        end
    end
end

local function applyToTPosition()
    local cfg = getToTDB()
    if not cfg then return end

    -- Zero-Touch: only apply when user has explicitly configured offsets
    local offsetX = tonumber(cfg.offsetX)
    local offsetY = tonumber(cfg.offsetY)
    if offsetX == nil and offsetY == nil then return end

    offsetX = offsetX or 0
    offsetY = offsetY or 0

    local frame = getTargetFrameToT()
    if not frame then
        debugPrint("ToT frame not found")
        return
    end

    -- Check for forbidden frame
    if frame.IsForbidden and frame:IsForbidden() then
        debugPrint("ToT frame is forbidden")
        return
    end

    -- Combat guard - defer to when combat ends
    if InCombatLockdown and InCombatLockdown() then
        debugPrint("Combat lockdown, deferring ToT position")
        pendingApplies["ToTPosition"] = applyToTPosition
        return
    end

    -- Capture original anchor once (prevent compounding)
    local orig = captureOriginalAnchor(frame, "ToT")
    if not orig then
        debugPrint("Could not capture ToT original anchor")
        return
    end

    -- Apply position with offsets from original anchor
    if frame.ClearAllPoints and frame.SetPoint then
        -- Flag to prevent hook re-triggering
        setProp(frame, "ignoreSetPoint", true)

        local ok, err = pcall(function()
            frame:ClearAllPoints()
            frame:SetPoint(
                orig.point,
                orig.relativeTo,
                orig.relativePoint,
                (orig.xOfs or 0) + offsetX,
                (orig.yOfs or 0) + offsetY
            )
        end)

        setProp(frame, "ignoreSetPoint", nil)

        if ok then
            debugPrint("Applied ToT position: offsetX=", offsetX, "offsetY=", offsetY)
        else
            debugPrint("Failed to apply ToT position:", err)
        end
    end
end

--------------------------------------------------------------------------------
-- Focus Target (FoT) Scale and Position
--------------------------------------------------------------------------------

-- Track if SetPoint hook is installed for FocusFrameToT
local focusToTHookInstalled = false

local function applyFocusTargetScale()
    local cfg = getFocusTargetDB()
    if not cfg then return end

    -- Zero-Touch: only apply when user has explicitly configured scale
    if cfg.scale == nil then return end

    local frame = getFocusFrameToT()
    if not frame then
        debugPrint("FocusTarget frame not found")
        return
    end

    -- Check for forbidden frame
    if frame.IsForbidden and frame:IsForbidden() then
        debugPrint("FocusTarget frame is forbidden")
        return
    end

    local scale = tonumber(cfg.scale) or 1.0
    -- Clamp to valid range (0.5 to 2.0)
    if scale < 0.5 then scale = 0.5 end
    if scale > 2.0 then scale = 2.0 end

    -- Combat guard - defer to when combat ends
    if InCombatLockdown and InCombatLockdown() then
        debugPrint("Combat lockdown, deferring FocusTarget scale")
        pendingApplies["FocusTargetScale"] = applyFocusTargetScale
        return
    end

    if frame.SetScale then
        local ok, err = pcall(frame.SetScale, frame, scale)
        if ok then
            debugPrint("Applied FocusTarget scale:", scale)
        else
            debugPrint("Failed to apply FocusTarget scale:", err)
        end
    end
end

local function applyFocusTargetPosition()
    local cfg = getFocusTargetDB()
    if not cfg then return end

    -- Zero-Touch: only apply when user has explicitly configured offsets
    local offsetX = tonumber(cfg.offsetX)
    local offsetY = tonumber(cfg.offsetY)
    if offsetX == nil and offsetY == nil then return end

    offsetX = offsetX or 0
    offsetY = offsetY or 0

    local frame = getFocusFrameToT()
    if not frame then
        debugPrint("FocusTarget frame not found")
        return
    end

    -- Check for forbidden frame
    if frame.IsForbidden and frame:IsForbidden() then
        debugPrint("FocusTarget frame is forbidden")
        return
    end

    -- Combat guard - defer to when combat ends
    if InCombatLockdown and InCombatLockdown() then
        debugPrint("Combat lockdown, deferring FocusTarget position")
        pendingApplies["FocusTargetPosition"] = applyFocusTargetPosition
        return
    end

    -- Capture original anchor once (prevent compounding)
    local orig = captureOriginalAnchor(frame, "FocusTarget")
    if not orig then
        debugPrint("Could not capture FocusTarget original anchor")
        return
    end

    -- Install SetPoint hook once to re-apply position when Blizzard re-anchors
    -- (e.g., when toggling Focus Frame size via SetSmallSize())
    if not focusToTHookInstalled and hooksecurefunc then
        focusToTHookInstalled = true
        hooksecurefunc(frame, "SetPoint", function(self, ...)
            -- Ignore SetPoint calls from this addon
            if getProp(self, "ignoreSetPoint") then return end

            -- Check if position config exists to re-apply
            local c = getFocusTargetDB()
            if not c then return end
            local ox = tonumber(c.offsetX)
            local oy = tonumber(c.offsetY)
            if ox == nil and oy == nil then return end

            -- Schedule re-apply on next frame to avoid recursion
            C_Timer.After(0, function()
                if addon.ApplyFocusTargetPosition then
                    addon.ApplyFocusTargetPosition()
                end
            end)
        end)
        debugPrint("Installed SetPoint hook for FocusTarget")
    end

    -- Apply position with offsets from original anchor
    if frame.ClearAllPoints and frame.SetPoint then
        -- Flag to prevent hook from re-triggering
        setProp(frame, "ignoreSetPoint", true)

        local ok, err = pcall(function()
            frame:ClearAllPoints()
            frame:SetPoint(
                orig.point,
                orig.relativeTo,
                orig.relativePoint,
                (orig.xOfs or 0) + offsetX,
                (orig.yOfs or 0) + offsetY
            )
        end)

        setProp(frame, "ignoreSetPoint", nil)

        if ok then
            debugPrint("Applied FocusTarget position: offsetX=", offsetX, "offsetY=", offsetY)
        else
            debugPrint("Failed to apply FocusTarget position:", err)
        end
    end
end

--------------------------------------------------------------------------------
-- Expose Functions on Addon Object
--------------------------------------------------------------------------------

addon.ApplyToTScale = applyToTScale
addon.ApplyToTPosition = applyToTPosition
addon.ApplyFocusTargetScale = applyFocusTargetScale
addon.ApplyFocusTargetPosition = applyFocusTargetPosition

-- Combined apply functions for convenience
function addon.ApplyAllToTSettings()
    applyToTScale()
    applyToTPosition()
end

function addon.ApplyAllFocusTargetSettings()
    applyFocusTargetScale()
    applyFocusTargetPosition()
end

-- Reset original anchors (useful if Blizzard layout changes)
function addon.ResetToTOriginalAnchors()
    originalAnchors = {}
    debugPrint("Reset original anchors for ToT/FocusTarget")
end
