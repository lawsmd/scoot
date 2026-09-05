-- offscreenunlock.lua - addon.OffscreenUnlock: families of Edit-Mode-managed
-- frames kept free of screen clamping so Edit Mode can drag them past the
-- screen edge and save the position.
--
-- Contract: OffscreenUnlock.NewFamily(desc) returns one family table with
-- applyFor, applyAll, onLayoutsUpdated, and installEditModeHooks. The family
-- disables clamping with SetClampedToScreen(false), SetClampRectInsets(0,0,0,0),
-- and SetIgnoreFramePositionManager(true), re-asserts that state through
-- hooksecurefunc when Blizzard re-clamps, and applies a 0.1px SetPoint nudge
-- once per Edit Mode session to flip Edit Mode's internal drag state. Edit Mode
-- owns positions: no other SetPoint, and never ReanchorFrame (it re-anchored
-- frames to unrelated UI elements). Combat-unsafe work defers through
-- addon.Events.RunOutOfCombat under the descriptor's key. Per-frame state lives
-- in addon.FrameState, never on the Blizzard frame.
local addonName, addon = ...

local FS = addon.FrameState

local OU = {}
addon.OffscreenUnlock = OU

local function getProp(frame, key)
    local st = FS.Get(frame)
    return st and st[key] or nil
end

local function setProp(frame, key, value)
    local st = FS.Get(frame)
    if st then
        st[key] = value
    end
end

-- The clamp rect insets value that disables clamping.
local CLAMP_ZERO = 0

-- FrameState prop names, per family. With a propPrefix the base gets the prefix
-- plus its first letter uppercased ("minimap" + "origClampInsets" =
-- "minimapOrigClampInsets"), which keeps every pre-factory name intact.
local PROP_BASES = {
    hooksInstalled = "offscreenHooksInstalled",
    enforceEnabled = "offscreenEnforceEnabled",
    enforceGuard = "offscreenEnforceGuard",
    origClamped = "origClampedToScreen",
    origInsets = "origClampInsets",
    unclampActive = "offscreenUnclampActive",
}

local function buildPropKeys(prefix)
    local props = {}
    for name, base in pairs(PROP_BASES) do
        if prefix and prefix ~= "" then
            props[name] = prefix .. base:sub(1, 1):upper() .. base:sub(2)
        else
            props[name] = base
        end
    end
    return props
end

-- desc fields:
--   keys              array of family member keys ({ "Player", "Target" }, { "Minimap" })
--   isEnabled(key)    member gate; nil means always enabled
--   resolveFrame(key) the Edit Mode registered frame, the one that gets the nudge
--   extraFrames(key)  optional array of extra frames for the clamp work only
--   readSetting(key)  the family's checkbox read
--   combatKey(key)    RunOutOfCombat key for the deferred reapply
--   debugFlag         addon field name that turns the debug prints on
--   debugTag          prefix for the debug prints
--   propPrefix        optional prefix for the six FrameState prop names
function OU.NewFamily(desc)
    local keys = desc.keys
    local isEnabled = desc.isEnabled
    local resolveFrame = desc.resolveFrame
    local extraFrames = desc.extraFrames
    local readSetting = desc.readSetting
    local combatKey = desc.combatKey
    local debugFlag = desc.debugFlag
    local debugTag = desc.debugTag
    local P = buildPropKeys(desc.propPrefix)

    local family = {}

    local function _DbgEnabled()
        return addon and addon[debugFlag] == true
    end

    local function _DbgPrint(...)
        if not _DbgEnabled() then return end
        addon.DebugPrint(debugTag, ...)
    end

    local function _AddUniqueFrame(list, seen, f)
        if not f or type(f) ~= "table" then return end
        if seen[f] then return end
        seen[f] = true
        list[#list + 1] = f
    end

    -- Prefer a narrow target set: only the frames the descriptor names, without
    -- touching related managed frames (totems, class resources) whose bounds
    -- would change the effective clamp region.
    local function _CollectCandidateFrames(key)
        local list, seen = {}, {}
        _AddUniqueFrame(list, seen, resolveFrame(key))
        local extras = extraFrames and extraFrames(key)
        if extras then
            for _, f in ipairs(extras) do
                _AddUniqueFrame(list, seen, f)
            end
        end
        return list
    end

    -- Tracks whether the nudge has run this Edit Mode session, per key.
    local _nudgeApplied = {}

    -- A 0.1px SetPoint nudge during Edit Mode triggers the internal state change
    -- that permits off-screen dragging. Adjusts the live frame position using
    -- the frame's existing anchor targets; writes nothing to Edit Mode layout data.
    local function _ApplySliderStyleNudge(key, frame)
        if not frame then return false end
        if frame.IsForbidden and frame:IsForbidden() then return false end
        if not (frame.GetPoint and frame.ClearAllPoints and frame.SetPoint) then return false end

        local point, relativeTo, relativePoint, xOfs, yOfs = frame:GetPoint(1)
        if not point then
            _DbgPrint("No anchor found for", key)
            return false
        end

        local relativeToName = nil
        if relativeTo then
            if type(relativeTo) == "table" and relativeTo.GetName then
                relativeToName = relativeTo:GetName()
            elseif type(relativeTo) == "string" then
                relativeToName = relativeTo
            end
        end

        -- A frame anchored to anything other than UIParent is left alone: a
        -- SetPoint there can cement a corrupted anchor (an action bar, say).
        if relativeToName and relativeToName ~= "UIParent" then
            _DbgPrint("Frame", key, "anchored to", relativeToName, "- not nudging")
            return false
        end

        local nudge = 0.1
        local newXOfs = (xOfs or 0) + nudge

        _DbgPrint("Applying slider-style nudge to", key, ":", point, relativeToName, relativePoint, newXOfs, yOfs)

        local ok, err = pcall(function()
            frame:ClearAllPoints()
            frame:SetPoint(point, relativeTo or _G.UIParent, relativePoint, newXOfs, yOfs or 0)
        end)

        if not ok then
            _DbgPrint("SetPoint nudge failed for", key, err)
            return false
        end

        return true
    end

    local function _ResetNudgeTracking()
        _nudgeApplied = {}
    end

    local function _IsEditModeActive()
        return addon.EditMode.IsEditModeActiveOrOpening()
    end

    local function _InstallOffscreenEnforcementHooks(frame)
        if not (frame and _G.hooksecurefunc) then return end
        if getProp(frame, P.hooksInstalled) then return end
        setProp(frame, P.hooksInstalled, true)

        -- While the setting is enabled, keep clamping off even if Blizzard or
        -- Edit Mode re-enables it after the apply pass.
        --
        -- On some unit frames IsClampedToScreen stays true regardless; there
        -- the expanded clamp rect insets carry the effect.
        if frame.SetClampedToScreen and frame.IsClampedToScreen then
            _G.hooksecurefunc(frame, "SetClampedToScreen", function(self, clamped)
                if not getProp(self, P.enforceEnabled) then return end
                if getProp(self, P.enforceGuard) then return end
                if clamped then
                    setProp(self, P.enforceGuard, true)
                    pcall(self.SetClampedToScreen, self, false)
                    setProp(self, P.enforceGuard, nil)
                end
            end)
        end

        if frame.SetClampRectInsets and frame.GetClampRectInsets then
            _G.hooksecurefunc(frame, "SetClampRectInsets", function(self, l, r, t, b)
                -- Enforced whenever the setting is on, not only in Edit Mode:
                -- Blizzard reasserts clamp insets on Edit Mode exit.
                if not getProp(self, P.enforceEnabled) then return end
                if getProp(self, P.enforceGuard) then return end
                if (l or 0) ~= CLAMP_ZERO or (r or 0) ~= CLAMP_ZERO or (t or 0) ~= CLAMP_ZERO or (b or 0) ~= CLAMP_ZERO then
                    setProp(self, P.enforceGuard, true)
                    pcall(self.SetClampRectInsets, self, CLAMP_ZERO, CLAMP_ZERO, CLAMP_ZERO, CLAMP_ZERO)
                    setProp(self, P.enforceGuard, nil)
                end
            end)
        end
    end

    -- Queue a post-combat reapply for one key on the shared regen drain; repeat
    -- queues under the same key coalesce.
    local function _QueueDeferredApply(key)
        addon.Events.RunOutOfCombat(function()
            family.applyFor(key)
        end, combatKey(key))
    end

    -- Apply unclamp/clamp state for one family member.
    function family.applyFor(key)
        if isEnabled and not isEnabled(key) then return false end
        local candidates = _CollectCandidateFrames(key)
        if not candidates or #candidates == 0 then
            _DbgPrint("No candidate frames for", key)
            return false
        end

        local shouldUnclamp = readSetting(key)
        local editModeActive = _IsEditModeActive()

        -- Combat safety: defer until combat ends.
        if InCombatLockdown and InCombatLockdown() then
            _QueueDeferredApply(key)
            return true
        end

        -- The cached flag alone is not trusted: Blizzard can re-enable clamping
        -- later (notably on Edit Mode entry), so the live frame state is
        -- re-checked and re-enforced when needed.

        local didWork = false

        -- The slider-style SetPoint nudge, when enabled and in Edit Mode.
        if shouldUnclamp and editModeActive and not _nudgeApplied[key] then
            local regFrame = resolveFrame(key)
            if regFrame then
                local nudged = _ApplySliderStyleNudge(key, regFrame)
                if nudged then
                    _nudgeApplied[key] = true
                    didWork = true
                end
            end
        end

        for _, frame in ipairs(candidates) do
            if frame and not (frame.IsForbidden and frame:IsForbidden()) then
                _InstallOffscreenEnforcementHooks(frame)
                local prev = getProp(frame, P.unclampActive)

                -- With the setting on, always ignore the position manager (not
                -- only during Edit Mode); prevents snap-back on exit.
                if frame.SetIgnoreFramePositionManager then
                    if shouldUnclamp then
                        pcall(frame.SetIgnoreFramePositionManager, frame, true)
                    else
                        pcall(frame.SetIgnoreFramePositionManager, frame, false)
                    end
                end

                if frame.IsClampedToScreen and frame.SetClampedToScreen then
                    if getProp(frame, P.origClamped) == nil then
                        local ok, v = pcall(frame.IsClampedToScreen, frame)
                        if ok then setProp(frame, P.origClamped, not not v) end
                    end
                    local baseClamped = (getProp(frame, P.origClamped) ~= nil) and (getProp(frame, P.origClamped) == true) or true

                    if shouldUnclamp then
                        local curOk, cur = pcall(frame.IsClampedToScreen, frame)
                        if (not curOk) or cur or (prev ~= shouldUnclamp) then
                            local ok, err = pcall(frame.SetClampedToScreen, frame, false)
                            if not ok then _DbgPrint("SetClampedToScreen(false) failed for", key, err) end
                            didWork = didWork or ok
                        end
                    else
                        -- Restore the original state only when the setting is off.
                        local curOk, cur = pcall(frame.IsClampedToScreen, frame)
                        if (not curOk) or (cur ~= baseClamped) or (prev ~= shouldUnclamp) then
                            local ok, err = pcall(frame.SetClampedToScreen, frame, baseClamped)
                            if not ok then _DbgPrint("SetClampedToScreen(restore) failed for", key, err) end
                            didWork = didWork or ok
                        end
                    end
                end

                if frame.GetClampRectInsets and frame.SetClampRectInsets then
                    if getProp(frame, P.origInsets) == nil then
                        local ok, l, r, t, b = pcall(frame.GetClampRectInsets, frame)
                        if ok then setProp(frame, P.origInsets, { l = l or 0, r = r or 0, t = t or 0, b = b or 0 }) end
                    end
                    -- Zeroed whenever the setting is on, not only in Edit Mode;
                    -- prevents snap-back on Edit Mode exit.
                    if shouldUnclamp then
                        local curOk, l, r, t, b = pcall(frame.GetClampRectInsets, frame)
                        local needs = (not curOk) or (l ~= CLAMP_ZERO or r ~= CLAMP_ZERO or t ~= CLAMP_ZERO or b ~= CLAMP_ZERO) or (prev ~= shouldUnclamp)
                        if needs then
                            local ok, err = pcall(frame.SetClampRectInsets, frame, CLAMP_ZERO, CLAMP_ZERO, CLAMP_ZERO, CLAMP_ZERO)
                            if not ok then _DbgPrint("SetClampRectInsets(zero) failed for", key, err) end
                            didWork = didWork or ok
                        end
                    else
                        local o = getProp(frame, P.origInsets)
                        if o then
                            local curOk, l, r, t, b = pcall(frame.GetClampRectInsets, frame)
                            local needs = (not curOk) or (l ~= (o.l or 0) or r ~= (o.r or 0) or t ~= (o.t or 0) or b ~= (o.b or 0)) or (prev ~= shouldUnclamp)
                            if needs then
                                local ok, err = pcall(frame.SetClampRectInsets, frame, o.l or 0, o.r or 0, o.t or 0, o.b or 0)
                                if not ok then _DbgPrint("Restore SetClampRectInsets failed for", key, err) end
                                didWork = didWork or ok
                            end
                        end
                    end
                end

                -- The enforcement flag toggles last so the hooks can correct
                -- post-apply re-clamping.
                setProp(frame, P.enforceEnabled, shouldUnclamp and true or nil)

                setProp(frame, P.unclampActive, shouldUnclamp)
            end
        end

        return didWork
    end

    function family.applyAll()
        for _, key in ipairs(keys) do
            family.applyFor(key)
        end
    end

    -- Edit Mode can reapply clamping as it enters; enforce right after entry.
    local _editModeHooksInstalled = false
    function family.installEditModeHooks()
        if _editModeHooksInstalled then return end
        _editModeHooksInstalled = true
        if not _G.hooksecurefunc then return end
        local mgr = _G.EditModeManagerFrame
        if not mgr then return end
        if type(mgr.EnterEditMode) == "function" then
            _G.hooksecurefunc(mgr, "EnterEditMode", function()
                -- Reset nudge tracking on entry so the nudge runs again.
                _ResetNudgeTracking()
                if C_Timer and C_Timer.After then
                    C_Timer.After(0, function()
                        if InCombatLockdown and InCombatLockdown() then return end
                        family.applyAll()
                    end)
                end
            end)
        end
        if type(mgr.ExitEditMode) == "function" then
            _G.hooksecurefunc(mgr, "ExitEditMode", function()
                _ResetNudgeTracking()
                -- Blizzard applies clamping in several post-exit stages, so the
                -- reapply runs immediately and again on two delays.
                if C_Timer and C_Timer.After then
                    C_Timer.After(0, function()
                        if InCombatLockdown and InCombatLockdown() then return end
                        family.applyAll()
                    end)
                    C_Timer.After(0.1, function()
                        if InCombatLockdown and InCombatLockdown() then return end
                        family.applyAll()
                    end)
                    C_Timer.After(0.3, function()
                        if InCombatLockdown and InCombatLockdown() then return end
                        family.applyAll()
                    end)
                else
                    family.applyAll()
                end
            end)
        end
    end

    -- Defer a short moment after layout updates so Edit Mode can finish repositioning.
    function family.onLayoutsUpdated()
        if not (C_Timer and C_Timer.After) then
            family.applyAll()
            return
        end
        C_Timer.After(0.1, function()
            if InCombatLockdown and InCombatLockdown() then
                for _, key in ipairs(keys) do
                    _QueueDeferredApply(key)
                end
                return
            end
            family.applyAll()
        end)
    end

    return family
end
