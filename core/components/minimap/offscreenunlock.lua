local addonName, addon = ...

-- Reference to FrameState module for safe property storage (avoids writing to Blizzard frames)
local FS = nil
local function ensureFS()
    if not FS then FS = addon.FrameState end
    return FS
end

local function getState(frame)
    local fs = ensureFS()
    return fs and fs.Get(frame) or nil
end

local function getProp(frame, key)
    local st = getState(frame)
    return st and st[key] or nil
end

local function setProp(frame, key, value)
    local st = getState(frame)
    if st then
        st[key] = value
    end
end

--[[----------------------------------------------------------------------------
    Minimap Off-Screen Drag Unlock

    Purpose:
      Allow users (notably Steam Deck / handheld setups) to drag the minimap
      partially off-screen in Edit Mode by disabling Blizzard's screen clamping.

    Key design constraints:
      - Do NOT move the frame ourselves (no drift). Edit Mode remains the source of
        truth for the frame's position.
      - Be combat-safe: avoid mutating protected frames during combat.
        If called during combat, defer to PLAYER_REGEN_ENABLED.
      - Keep it lightweight: no hooks or per-frame updates; only run on explicit
        triggers (settings change, ApplyStyles, Edit Mode layout updates).

    Implementation strategy:
      Reuses the same technique from Unit Frame off-screen unlock:
      SetClampedToScreen(false), SetClampRectInsets(0,0,0,0),
      SetIgnoreFramePositionManager(true), and a 0.1px nudge via SetPoint
      when in Edit Mode to trigger internal unlock.
----------------------------------------------------------------------------]]--

local function _DbgEnabled()
    return addon and addon._dbgMinimapOffscreenUnlock == true
end

local function _DbgPrint(...)
    if not _DbgEnabled() then return end
    if addon and addon.DebugPrint then
        addon.DebugPrint("[MinimapOffscreenUnlock]", ...)
    else
        print("[Scoot MinimapOffscreenUnlock]", ...)
    end
end

-- Prefer the Edit Mode registered system frame (what Edit Mode actually drags).
local function _GetMinimapFrame()
    local mgr = _G.EditModeManagerFrame
    local EMSys = _G.Enum and _G.Enum.EditModeSystem
    if mgr and EMSys and mgr.GetRegisteredSystemFrame then
        local frame = mgr:GetRegisteredSystemFrame(EMSys.Minimap)
        if frame then return frame end
    end
    -- Fallback to MinimapCluster global
    return _G.MinimapCluster
end

local function _ReadAllowOffscreen()
    -- Zero-touch friendly: avoid creating tables here (use rawget only).
    local profile = addon and addon.db and addon.db.profile
    local components = profile and rawget(profile, "components")
    local minimapStyle = (type(components) == "table") and rawget(components, "minimapStyle") or nil
    if type(minimapStyle) ~= "table" then
        return false
    end
    return rawget(minimapStyle, "allowOffScreenDragging") == true
end

local pending = false
local combatWatcher

-- The clamp rect insets value to use when unlocked
local CLAMP_ZERO = 0

-- Track whether the nudge has been applied this Edit Mode session
local _nudgeApplied = false

local function _ApplySliderStyleNudge(frame)
    if not frame then return false end
    if frame.IsForbidden and frame:IsForbidden() then return false end
    if not (frame.GetPoint and frame.ClearAllPoints and frame.SetPoint) then return false end

    -- Get current anchor
    local point, relativeTo, relativePoint, xOfs, yOfs = frame:GetPoint(1)
    if not point then
        _DbgPrint("No anchor found for MinimapCluster")
        return false
    end

    -- Validate relativeTo - if it's nil or not UIParent, be very careful
    local relativeToName = nil
    if relativeTo then
        if type(relativeTo) == "table" and relativeTo.GetName then
            relativeToName = relativeTo:GetName()
        elseif type(relativeTo) == "string" then
            relativeToName = relativeTo
        end
    end

    -- Safety check: if anchored to something other than UIParent, don't touch it
    if relativeToName and relativeToName ~= "UIParent" then
        _DbgPrint("Frame anchored to", relativeToName, "- not nudging to avoid corruption")
        return false
    end

    -- Apply a tiny X nudge (0.1 px) - imperceptible but triggers Edit Mode's
    -- internal state change that allows off-screen dragging
    local nudge = 0.1
    local newXOfs = (xOfs or 0) + nudge

    _DbgPrint("Applying slider-style nudge:", point, relativeToName, relativePoint, newXOfs, yOfs)

    -- Apply the nudge
    local ok, err = pcall(function()
        frame:ClearAllPoints()
        frame:SetPoint(point, relativeTo or _G.UIParent, relativePoint, newXOfs, yOfs or 0)
    end)

    if not ok then
        _DbgPrint("SetPoint nudge failed:", err)
        return false
    end

    return true
end

local function _ResetNudgeTracking()
    _nudgeApplied = false
end

local function _IsEditModeActive()
    local mgr = _G.EditModeManagerFrame
    if not mgr then return false end
    if mgr.IsEditModeActive then
        local ok, v = pcall(mgr.IsEditModeActive, mgr)
        if ok then return v == true end
    end
    -- Fallback (best-effort; varies by build)
    if rawget(mgr, "editModeActive") ~= nil then
        return mgr.editModeActive == true
    end
    return false
end

local function _InstallOffscreenEnforcementHooks(frame)
    if not (frame and _G.hooksecurefunc) then return end
    if getProp(frame, "minimapOffscreenHooksInstalled") then return end
    setProp(frame, "minimapOffscreenHooksInstalled", true)

    -- When the setting is enabled, keep clamping OFF even if Blizzard/Edit Mode
    -- tries to re-enable it after the apply pass.
    if frame.SetClampedToScreen and frame.IsClampedToScreen then
        _G.hooksecurefunc(frame, "SetClampedToScreen", function(self, clamped)
            if not getProp(self, "minimapOffscreenEnforceEnabled") then return end
            if getProp(self, "minimapOffscreenEnforceGuard") then return end
            -- If Blizzard tries to enable clamping, force it back off
            if clamped then
                setProp(self, "minimapOffscreenEnforceGuard", true)
                pcall(self.SetClampedToScreen, self, false)
                setProp(self, "minimapOffscreenEnforceGuard", nil)
            end
        end)
    end

    if frame.SetClampRectInsets and frame.GetClampRectInsets then
        _G.hooksecurefunc(frame, "SetClampRectInsets", function(self, l, r, t, b)
            -- Enforce ALWAYS when checkbox is enabled (not just Edit Mode).
            -- This prevents Blizzard from reasserting clamp insets when exiting Edit Mode.
            if not getProp(self, "minimapOffscreenEnforceEnabled") then return end
            if getProp(self, "minimapOffscreenEnforceGuard") then return end
            -- Force (0,0,0,0) to prevent snap-back.
            if (l or 0) ~= CLAMP_ZERO or (r or 0) ~= CLAMP_ZERO or (t or 0) ~= CLAMP_ZERO or (b or 0) ~= CLAMP_ZERO then
                setProp(self, "minimapOffscreenEnforceGuard", true)
                pcall(self.SetClampRectInsets, self, CLAMP_ZERO, CLAMP_ZERO, CLAMP_ZERO, CLAMP_ZERO)
                setProp(self, "minimapOffscreenEnforceGuard", nil)
            end
        end)
    end
end

local function _EnsureCombatWatcher()
    if combatWatcher then return end
    combatWatcher = CreateFrame("Frame")
    combatWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
    combatWatcher:SetScript("OnEvent", function()
        if pending then
            pending = false
            if addon and addon.ApplyMinimapOffscreenUnlock then
                addon.ApplyMinimapOffscreenUnlock()
            end
        end
    end)
end

-- Apply unclamp/clamp state for the minimap.
local function applyMinimapOffscreenUnlock()
    local frame = _GetMinimapFrame()
    if not frame then
        _DbgPrint("MinimapCluster not found")
        return false
    end

    local shouldUnclamp = _ReadAllowOffscreen()
    local editModeActive = _IsEditModeActive()

    -- Combat safety: defer until combat ends
    if InCombatLockdown and InCombatLockdown() then
        pending = true
        _EnsureCombatWatcher()
        return true
    end

    local didWork = false

    -- Apply the slider-style SetPoint nudge when enabled and in Edit Mode.
    if shouldUnclamp and editModeActive and not _nudgeApplied then
        local nudged = _ApplySliderStyleNudge(frame)
        if nudged then
            _nudgeApplied = true
            didWork = true
        end
    end

    if not (frame.IsForbidden and frame:IsForbidden()) then
        _InstallOffscreenEnforcementHooks(frame)
        local prev = getProp(frame, "minimapOffscreenUnclampActive")

        -- SetIgnoreFramePositionManager: When checkbox is enabled, always ignore the
        -- position manager (not just during Edit Mode). This prevents snap-back on exit.
        if frame.SetIgnoreFramePositionManager then
            if shouldUnclamp then
                pcall(frame.SetIgnoreFramePositionManager, frame, true)
            else
                pcall(frame.SetIgnoreFramePositionManager, frame, false)
            end
        end

        -- SetClampedToScreen: When checkbox is enabled, ALWAYS try to disable clamping
        if frame.IsClampedToScreen and frame.SetClampedToScreen then
            if getProp(frame, "minimapOrigClampedToScreen") == nil then
                local ok, v = pcall(frame.IsClampedToScreen, frame)
                if ok then setProp(frame, "minimapOrigClampedToScreen", not not v) end
            end
            local baseClamped = (getProp(frame, "minimapOrigClampedToScreen") ~= nil) and (getProp(frame, "minimapOrigClampedToScreen") == true) or true

            if shouldUnclamp then
                -- Disable clamping when checkbox is enabled
                local curOk, cur = pcall(frame.IsClampedToScreen, frame)
                if (not curOk) or cur or (prev ~= shouldUnclamp) then
                    local ok, err = pcall(frame.SetClampedToScreen, frame, false)
                    if not ok then _DbgPrint("SetClampedToScreen(false) failed:", err) end
                    didWork = didWork or ok
                end
            else
                -- Restore original state only when checkbox is DISABLED
                local curOk, cur = pcall(frame.IsClampedToScreen, frame)
                if (not curOk) or (cur ~= baseClamped) or (prev ~= shouldUnclamp) then
                    local ok, err = pcall(frame.SetClampedToScreen, frame, baseClamped)
                    if not ok then _DbgPrint("SetClampedToScreen(restore) failed:", err) end
                    didWork = didWork or ok
                end
            end
        end

        if frame.GetClampRectInsets and frame.SetClampRectInsets then
            if getProp(frame, "minimapOrigClampInsets") == nil then
                local ok, l, r, t, b = pcall(frame.GetClampRectInsets, frame)
                if ok then setProp(frame, "minimapOrigClampInsets", { l = l or 0, r = r or 0, t = t or 0, b = b or 0 }) end
            end
            -- Zero out clamp rect when checkbox is enabled
            if shouldUnclamp then
                local curOk, l, r, t, b = pcall(frame.GetClampRectInsets, frame)
                local needs = (not curOk) or (l ~= CLAMP_ZERO or r ~= CLAMP_ZERO or t ~= CLAMP_ZERO or b ~= CLAMP_ZERO) or (prev ~= shouldUnclamp)
                if needs then
                    local ok, err = pcall(frame.SetClampRectInsets, frame, CLAMP_ZERO, CLAMP_ZERO, CLAMP_ZERO, CLAMP_ZERO)
                    if not ok then _DbgPrint("SetClampRectInsets(zero) failed:", err) end
                    didWork = didWork or ok
                end
            else
                -- Restore original insets only when checkbox is DISABLED
                local o = getProp(frame, "minimapOrigClampInsets")
                if o then
                    local curOk, l, r, t, b = pcall(frame.GetClampRectInsets, frame)
                    local needs = (not curOk) or (l ~= (o.l or 0) or r ~= (o.r or 0) or t ~= (o.t or 0) or b ~= (o.b or 0)) or (prev ~= shouldUnclamp)
                    if needs then
                        local ok, err = pcall(frame.SetClampRectInsets, frame, o.l or 0, o.r or 0, o.t or 0, o.b or 0)
                        if not ok then _DbgPrint("Restore SetClampRectInsets failed:", err) end
                        didWork = didWork or ok
                    end
                end
            end
        end

        -- Toggle enforcement flag LAST so hooks can correct post-apply re-clamping.
        setProp(frame, "minimapOffscreenEnforceEnabled", shouldUnclamp and true or nil)
        setProp(frame, "minimapOffscreenUnclampActive", shouldUnclamp)
    end

    return didWork
end

-- Edit Mode can reapply clamping as it enters; enforce the desired state right after entry.
local _editModeHooksInstalled = false
local function installEditModeHooks()
    if _editModeHooksInstalled then return end
    _editModeHooksInstalled = true
    if not _G.hooksecurefunc then return end
    local mgr = _G.EditModeManagerFrame
    if not mgr then return end
    if type(mgr.EnterEditMode) == "function" then
        _G.hooksecurefunc(mgr, "EnterEditMode", function()
            -- Reset nudge tracking on Edit Mode entry so the nudge is re-applied
            _ResetNudgeTracking()
            if C_Timer and C_Timer.After then
                C_Timer.After(0, function()
                    if InCombatLockdown and InCombatLockdown() then return end
                    applyMinimapOffscreenUnlock()
                end)
            end
        end)
    end
    if type(mgr.ExitEditMode) == "function" then
        _G.hooksecurefunc(mgr, "ExitEditMode", function()
            -- Reset nudge tracking when leaving Edit Mode
            _ResetNudgeTracking()
            -- Apply unclamping immediately AND with delays to catch all post-exit processing.
            if C_Timer and C_Timer.After then
                -- Immediate
                C_Timer.After(0, function()
                    if InCombatLockdown and InCombatLockdown() then return end
                    applyMinimapOffscreenUnlock()
                end)
                -- Short delay to catch deferred processing
                C_Timer.After(0.1, function()
                    if InCombatLockdown and InCombatLockdown() then return end
                    applyMinimapOffscreenUnlock()
                end)
                -- Longer delay as a safety net
                C_Timer.After(0.3, function()
                    if InCombatLockdown and InCombatLockdown() then return end
                    applyMinimapOffscreenUnlock()
                end)
            else
                applyMinimapOffscreenUnlock()
            end
        end)
    end
end

-- Defer a short moment after layout updates so Edit Mode can finish repositioning.
local function onLayoutsUpdated()
    if not (C_Timer and C_Timer.After) then
        applyMinimapOffscreenUnlock()
        return
    end
    C_Timer.After(0.1, function()
        if InCombatLockdown and InCombatLockdown() then
            pending = true
            _EnsureCombatWatcher()
            return
        end
        applyMinimapOffscreenUnlock()
    end)
end

-- Export functions
addon.ApplyMinimapOffscreenUnlock = applyMinimapOffscreenUnlock
addon.OnMinimapOffscreenUnlockLayoutsUpdated = onLayoutsUpdated

-- Install Edit Mode hooks
installEditModeHooks()
