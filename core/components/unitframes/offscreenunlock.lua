-- offscreenunlock.lua - Off-screen drag unlock for Player and Target frames
local addonName, addon = ...

-- Reference to FrameState module for safe property storage (avoids writing to Blizzard frames)
local FS = addon.FrameState

local function getState(frame)
	return FS.Get(frame)
end

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

-- Disables Blizzard's screen clamping so Edit Mode can drag frames off-edge
-- (primarily for Steam Deck / handheld setups).
--
-- Constraints:
--   No frame movement -- Edit Mode is the position source of truth.
--   Combat-safe: defers mutations to PLAYER_REGEN_ENABLED.
--   Lightweight: runs only on settings change / ApplyStyles / layout update.
--
-- Uses SetClampedToScreen(false), SetClampRectInsets(0,0,0,0), and
-- SetIgnoreFramePositionManager(true). Checkbox replaces the original slider.
-- NOTE: ReanchorFrame/SetPoint caused right-side snap; do NOT call position APIs.

local UNITS = { "Player", "Target" }

local function _DbgEnabled()
	return addon and addon._dbgOffscreenUnlock == true
end

local function _DbgPrint(...)
	if not _DbgEnabled() then return end
	addon.DebugPrint("[OffscreenUnlock]", ...)
end

-- Prefer the Edit Mode registered system frame, which is what Edit Mode drags.
local _GetEditModeRegisteredFrame = addon.GetEditModeUnitFrame

local function _AddUniqueFrame(list, seen, f)
	if not f or type(f) ~= "table" then return end
	if seen[f] then return end
	seen[f] = true
	list[#list + 1] = f
end

-- Prefer a narrow target set: only affect the unit frame Edit Mode
-- manages, without unintentionally touching related managed frames (totems/class
-- resources) that can change the effective bounds and make corner placement worse.
local function _CollectCandidateFrames(unit)
	local list, seen = {}, {}
	local reg = _GetEditModeRegisteredFrame(unit)
	_AddUniqueFrame(list, seen, reg)
	if unit == "Player" then _AddUniqueFrame(list, seen, _G.PlayerFrame) end
	if unit == "Target" then _AddUniqueFrame(list, seen, _G.TargetFrame) end
	return list
end

local function _ReadAllowOffscreen(unit)
	-- Zero-touch friendly: avoid creating tables here (use rawget only).
	local profile = addon and addon.db and addon.db.profile
	local uf = profile and rawget(profile, "unitFrames")
	local unitCfg = (type(uf) == "table") and rawget(uf, unit) or nil
	local misc = (type(unitCfg) == "table") and rawget(unitCfg, "misc") or nil
	if type(misc) ~= "table" then
		return false
	end
	-- New setting (checkbox)
	local enabled = rawget(misc, "allowOffscreenDrag") == true
	if enabled then
		return true
	end
	return false
end

local pendingUnits = {}
local combatWatcher

-- The original working slider used SetClampRectInsets(0,0,0,0) to disable clamping.
local CLAMP_ZERO = 0

-- A 0.1px SetPoint nudge during Edit Mode triggers the internal state change
-- that permits off-screen dragging. Adjusts live frame position using the
-- frame's existing anchor targets -- does not write to Edit Mode layout data.
-- (ReanchorFrame caused re-anchoring to unrelated UI elements.)

-- Tracks whether the nudge has been applied this Edit Mode session
local _nudgeApplied = {}

local function _ApplySliderStyleNudge(unit, frame)
	if not frame then return false end
	if frame.IsForbidden and frame:IsForbidden() then return false end
	if not (frame.GetPoint and frame.ClearAllPoints and frame.SetPoint) then return false end
	
	-- Get current anchor
	local point, relativeTo, relativePoint, xOfs, yOfs = frame:GetPoint(1)
	if not point then
		_DbgPrint("No anchor found for", unit)
		return false
	end
	
	-- Validate relativeTo - if it's nil or not UIParent, be very careful
	-- The corruption happens when relativeTo becomes an action bar
	local relativeToName = nil
	if relativeTo then
		if type(relativeTo) == "table" and relativeTo.GetName then
			relativeToName = relativeTo:GetName()
		elseif type(relativeTo) == "string" then
			relativeToName = relativeTo
		end
	end
	
	-- Safety check: if anchored to something other than UIParent, don't touch it
	-- Prevents cementing a corrupted anchor
	if relativeToName and relativeToName ~= "UIParent" then
		_DbgPrint("Frame", unit, "anchored to", relativeToName, "- not nudging to avoid corruption")
		return false
	end
	
	-- Apply a tiny X nudge (0.1 px) - imperceptible but triggers Edit Mode's
	-- internal state change that allows off-screen dragging
	local nudge = 0.1
	local newXOfs = (xOfs or 0) + nudge
	
	_DbgPrint("Applying slider-style nudge to", unit, ":", point, relativeToName, relativePoint, newXOfs, yOfs)
	
	-- Apply the nudge
	local ok, err = pcall(function()
		frame:ClearAllPoints()
		frame:SetPoint(point, relativeTo or _G.UIParent, relativePoint, newXOfs, yOfs or 0)
	end)
	
	if not ok then
		_DbgPrint("SetPoint nudge failed for", unit, err)
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
	if getProp(frame, "offscreenHooksInstalled") then return end
	setProp(frame, "offscreenHooksInstalled", true)

	-- When the setting is enabled, keep clamping OFF even if Blizzard/Edit Mode
	-- tries to re-enable it after the apply pass.
	--
	-- NOTE: On some unit frames, IsClampedToScreen stays true regardless. In those
	-- cases, the effective unlock is achieved via expanded clamp rect insets.
	if frame.SetClampedToScreen and frame.IsClampedToScreen then
		_G.hooksecurefunc(frame, "SetClampedToScreen", function(self, clamped)
			if not getProp(self, "offscreenEnforceEnabled") then return end
			if getProp(self, "offscreenEnforceGuard") then return end
			-- If Blizzard tries to enable clamping, force it back off
			if clamped then
				setProp(self, "offscreenEnforceGuard", true)
				pcall(self.SetClampedToScreen, self, false)
				setProp(self, "offscreenEnforceGuard", nil)
			end
		end)
	end

	if frame.SetClampRectInsets and frame.GetClampRectInsets then
		_G.hooksecurefunc(frame, "SetClampRectInsets", function(self, l, r, t, b)
			-- Enforce ALWAYS when checkbox is enabled (not just Edit Mode).
			-- Prevents Blizzard from reasserting clamp insets when exiting Edit Mode.
			if not getProp(self, "offscreenEnforceEnabled") then return end
			if getProp(self, "offscreenEnforceGuard") then return end
			-- Force (0,0,0,0) to prevent snap-back.
			if (l or 0) ~= CLAMP_ZERO or (r or 0) ~= CLAMP_ZERO or (t or 0) ~= CLAMP_ZERO or (b or 0) ~= CLAMP_ZERO then
				setProp(self, "offscreenEnforceGuard", true)
				pcall(self.SetClampRectInsets, self, CLAMP_ZERO, CLAMP_ZERO, CLAMP_ZERO, CLAMP_ZERO)
				setProp(self, "offscreenEnforceGuard", nil)
			end
		end)
	end
end

local function _EnsureCombatWatcher()
	if combatWatcher then return end
	combatWatcher = CreateFrame("Frame")
	combatWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
	combatWatcher:SetScript("OnEvent", function()
		for unit in pairs(pendingUnits) do
			pendingUnits[unit] = nil
			if addon and addon.ApplyUnitFrameOffscreenUnlockFor then
				addon.ApplyUnitFrameOffscreenUnlockFor(unit)
			end
		end
	end)
end

-- Apply unclamp/clamp state for a single unit.
local function applyFor(unit)
	if not addon:IsModuleEnabled("unitFrames", unit) then return false end
	local candidates = _CollectCandidateFrames(unit)
	if not candidates or #candidates == 0 then
		return false
	end

	local shouldUnclamp = _ReadAllowOffscreen(unit)
	local editModeActive = _IsEditModeActive()

	-- Combat safety: defer until combat ends
	if InCombatLockdown and InCombatLockdown() then
		pendingUnits[unit] = true
		_EnsureCombatWatcher()
		return true
	end

	-- Important: do NOT rely solely on the cached flag here.
	-- Blizzard can re-enable clamping later (notably when entering Edit Mode),
	-- so the live frame state is re-checked and re-enforced if needed.

	local didWork = false

	-- Apply the slider-style SetPoint nudge when enabled and in Edit Mode.
	-- Key behavior that made the original slider work.
	if shouldUnclamp and editModeActive and not _nudgeApplied[unit] then
		local regFrame = _GetEditModeRegisteredFrame(unit)
		if regFrame then
			local nudged = _ApplySliderStyleNudge(unit, regFrame)
			if nudged then
				_nudgeApplied[unit] = true
				didWork = true
			end
		end
	end

	-- Only poke on the transition from disabled -> enabled (per candidate frame).
	for _, frame in ipairs(candidates) do
		if frame and not (frame.IsForbidden and frame:IsForbidden()) then
			_InstallOffscreenEnforcementHooks(frame)
			local prev = getProp(frame, "offscreenUnclampActive")

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
			-- (not just during Edit Mode). This prevents the snap-back when exiting Edit Mode.
			if frame.IsClampedToScreen and frame.SetClampedToScreen then
				if getProp(frame, "origClampedToScreen") == nil then
					local ok, v = pcall(frame.IsClampedToScreen, frame)
					if ok then setProp(frame, "origClampedToScreen", not not v) end
				end
				local baseClamped = (getProp(frame, "origClampedToScreen") ~= nil) and (getProp(frame, "origClampedToScreen") == true) or true
				
				if shouldUnclamp then
					-- Disable clamping when checkbox is enabled (always, not just Edit Mode)
					local curOk, cur = pcall(frame.IsClampedToScreen, frame)
					if (not curOk) or cur or (prev ~= shouldUnclamp) then
						local ok, err = pcall(frame.SetClampedToScreen, frame, false)
						if not ok then _DbgPrint("SetClampedToScreen(false) failed for", unit, err) end
						didWork = didWork or ok
					end
				else
					-- Restore original state only when checkbox is DISABLED
					local curOk, cur = pcall(frame.IsClampedToScreen, frame)
					if (not curOk) or (cur ~= baseClamped) or (prev ~= shouldUnclamp) then
						local ok, err = pcall(frame.SetClampedToScreen, frame, baseClamped)
						if not ok then _DbgPrint("SetClampedToScreen(restore) failed for", unit, err) end
						didWork = didWork or ok
					end
				end
			end

			if frame.GetClampRectInsets and frame.SetClampRectInsets then
				if getProp(frame, "origClampInsets") == nil then
					local ok, l, r, t, b = pcall(frame.GetClampRectInsets, frame)
					if ok then setProp(frame, "origClampInsets", { l = l or 0, r = r or 0, t = t or 0, b = b or 0 }) end
				end
				-- Zero out clamp rect when checkbox is enabled (ALWAYS, not just Edit Mode).
				-- Key fix: prevents snap-back when exiting Edit Mode.
				if shouldUnclamp then
					local curOk, l, r, t, b = pcall(frame.GetClampRectInsets, frame)
					local needs = (not curOk) or (l ~= CLAMP_ZERO or r ~= CLAMP_ZERO or t ~= CLAMP_ZERO or b ~= CLAMP_ZERO) or (prev ~= shouldUnclamp)
					if needs then
						local ok, err = pcall(frame.SetClampRectInsets, frame, CLAMP_ZERO, CLAMP_ZERO, CLAMP_ZERO, CLAMP_ZERO)
						if not ok then _DbgPrint("SetClampRectInsets(zero) failed for", unit, err) end
						didWork = didWork or ok
					end
				else
					-- Restore original insets only when checkbox is DISABLED
					local o = getProp(frame, "origClampInsets")
					if o then
						local curOk, l, r, t, b = pcall(frame.GetClampRectInsets, frame)
						local needs = (not curOk) or (l ~= (o.l or 0) or r ~= (o.r or 0) or t ~= (o.t or 0) or b ~= (o.b or 0)) or (prev ~= shouldUnclamp)
						if needs then
							local ok, err = pcall(frame.SetClampRectInsets, frame, o.l or 0, o.r or 0, o.t or 0, o.b or 0)
							if not ok then _DbgPrint("Restore SetClampRectInsets failed for", unit, err) end
							didWork = didWork or ok
						end
					end
				end
			end

			-- Toggle enforcement flag LAST so hooks can correct post-apply re-clamping.
			setProp(frame, "offscreenEnforceEnabled", shouldUnclamp and true or nil)

			setProp(frame, "offscreenUnclampActive", shouldUnclamp)
		end
	end

	return didWork
end

local function applyAll()
	for _, unit in ipairs(UNITS) do
		applyFor(unit)
	end
end

-- Edit Mode can reapply clamping as it enters; enforce the unclamped state right after entry.
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
					applyAll()
				end)
			end
		end)
	end
	if type(mgr.ExitEditMode) == "function" then
		_G.hooksecurefunc(mgr, "ExitEditMode", function()
			-- Reset nudge tracking when leaving Edit Mode
			_ResetNudgeTracking()
			-- Apply unclamping immediately AND with delays to catch all post-exit processing.
			-- Blizzard may apply clamping in multiple stages when exiting Edit Mode.
			if C_Timer and C_Timer.After then
				-- Immediate
				C_Timer.After(0, function()
					if InCombatLockdown and InCombatLockdown() then return end
					applyAll()
				end)
				-- Short delay to catch deferred processing
				C_Timer.After(0.1, function()
					if InCombatLockdown and InCombatLockdown() then return end
					applyAll()
				end)
				-- Longer delay as a safety net
				C_Timer.After(0.3, function()
					if InCombatLockdown and InCombatLockdown() then return end
					applyAll()
				end)
			else
				applyAll()
			end
		end)
	end
end

-- Defer a short moment after layout updates so Edit Mode can finish repositioning.
local function onLayoutsUpdated()
	if not (C_Timer and C_Timer.After) then
		applyAll()
		return
	end
	C_Timer.After(0.1, function()
		if InCombatLockdown and InCombatLockdown() then
			-- Let the combat watcher handle reapply after combat.
			for _, unit in ipairs(UNITS) do
				pendingUnits[unit] = true
			end
			_EnsureCombatWatcher()
			return
		end
		applyAll()
	end)
end

addon.ApplyUnitFrameOffscreenUnlockFor = applyFor
addon.ApplyAllUnitFrameOffscreenUnlocks = applyAll
addon.OnUnitFrameOffscreenUnlockLayoutsUpdated = onLayoutsUpdated

installEditModeHooks()

-- Back-compat: older exports used the "ContainerOffset" naming.
addon.ApplyUnitFrameContainerOffsetFor = applyFor
addon.ApplyAllUnitFrameContainerOffsets = applyAll
addon.OnUnitFrameContainerOffsetLayoutsUpdated = onLayoutsUpdated


