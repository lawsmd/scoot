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

local classResourceZoneWatcher = nil

local function ensureClassResourceZoneWatcher()
	if classResourceZoneWatcher then
		return
	end
	classResourceZoneWatcher = CreateFrame("Frame")
	classResourceZoneWatcher:RegisterEvent("PLAYER_ENTERING_WORLD")
	classResourceZoneWatcher:SetScript("OnEvent", function()
		-- Defer to allow Blizzard to finish any post-load layout passes first.
		C_Timer.After(0.1, function()
			if addon and addon.ApplyUnitFrameClassResource then
				addon.ApplyUnitFrameClassResource("Player")
			end
		end)
	end)
end

-- Baseline storage for managed frame offsets
-- NOTE: Frame scales are not captured because frames may retain a previously-applied
-- scale across reloads. Class resource frames have no Edit Mode scale, so baseline is always 1.0.
local originalPaddings = setmetatable({}, { __mode = "k" })
local hookedFrames = setmetatable({}, { __mode = "k" })
local layoutHooked = false

-- Debug helper (disabled by default)
local DEBUG_CLASS_RESOURCE = false
local function debugPrint(...)
	if DEBUG_CLASS_RESOURCE and addon and addon.DebugPrint then
		addon.DebugPrint("[ClassResource]", ...)
	elseif DEBUG_CLASS_RESOURCE then
		print("[Scoot ClassResource]", ...)
	end
end

local function safeGetFrame(name)
	local frame = _G[name]
	if frame and frame.IsForbidden and frame:IsForbidden() then
		return nil
	end
	return frame
end

local CLASS_RESOURCE_ENTRIES = {
	{
		label = "Druid Combo Points",
		classes = { DRUID = true },
		frameNames = { "DruidComboPointBarFrame" },
	},
	{
		label = "Rogue Combo Points",
		classes = { ROGUE = true },
		frameNames = { "RogueComboPointBarFrame", "ComboPointPlayerFrame" },
	},
	{
		label = "Paladin Holy Power",
		classes = { PALADIN = true },
		frameNames = { "PaladinPowerBarFrame" },
	},
	{
		label = "Monk Chi",
		classes = { MONK = true },
		frameNames = { "MonkHarmonyBarFrame" },
	},
	{
		label = "Warlock Soul Shards",
		classes = { WARLOCK = true },
		frameNames = { "WarlockPowerFrame" },
	},
	{
		label = "Death Knight Runes",
		classes = { DEATHKNIGHT = true },
		frameNames = { "RuneFrame" },
	},
	{
		label = "Shaman Totems",
		classes = { SHAMAN = true },
		frameNames = { "TotemFrame" },
	},
	{
		label = "Mage Arcane Charges",
		classes = { MAGE = true },
		frameNames = { "MageArcaneChargesFrame" },
	},
	{
		label = "Evoker Essence",
		classes = { EVOKER = true },
		frameNames = { "EssencePlayerFrame" },
	},
}

local CLASS_LABELS = {}
for _, entry in ipairs(CLASS_RESOURCE_ENTRIES) do
	if entry.classes then
		for classToken in pairs(entry.classes) do
			CLASS_LABELS[classToken] = entry.label
		end
	end
end

local function ensureConfig()
	local db = addon and addon.db and addon.db.profile
	if not db then return nil end

	db.unitFrames = db.unitFrames or {}
	db.unitFrames.Player = db.unitFrames.Player or {}
	db.unitFrames.Player.classResource = db.unitFrames.Player.classResource or {}
	local cfg = db.unitFrames.Player.classResource

	-- Clean up removed custom position keys (feature retired)
	cfg.classResourceCustomPositionEnabled = nil
	cfg.classResourcePosX = nil
	cfg.classResourcePosY = nil
	return cfg
end

local function resolveClassResourceFrames()
	local classToken = UnitClassBase and UnitClassBase("player") or select(2, UnitClass("player"))
	local fallbackLabel = (classToken and CLASS_LABELS[classToken]) or "Class Resource"
	if not classToken then
		return {}, fallbackLabel
	end

	for _, entry in ipairs(CLASS_RESOURCE_ENTRIES) do
		if entry.classes and entry.classes[classToken] then
			local resolved = {}
			local seen = {}
			for _, frameName in ipairs(entry.frameNames or {}) do
				local frame = safeGetFrame(frameName)
				if frame and not seen[frame] then
					resolved[#resolved + 1] = frame
					seen[frame] = true
				end
			end
			if #resolved > 0 then
				return resolved, entry.label
			end
		end
	end

	return {}, fallbackLabel
end

-- Capture original padding values for managed frames
-- NOTE: Scale is not captured because frames may retain a previously-applied scale across reloads.
-- Class resource frames have no Edit Mode scale setting, so baseline is always 1.0.
local function captureBaselines(frame)
	if not frame then return end
	
	-- Capture original padding (used by LayoutFrame system for positioning)
	if not originalPaddings[frame] then
		originalPaddings[frame] = {
			leftPadding = frame.leftPadding or 0,
			topPadding = frame.topPadding or 0,
		}
		debugPrint("Captured baseline paddings for", frame:GetName() or "unnamed",
			"left:", originalPaddings[frame].leftPadding,
			"top:", originalPaddings[frame].topPadding)
	end
end

local function clampOffset(value)
	local v = tonumber(value) or 0
	if v < -150 then
		return -150
	elseif v > 150 then
		return 150
	end
	return v
end

local function clampScale(value)
	local v = tonumber(value) or 100
	if v < 50 then
		return 50
	elseif v > 150 then
		return 150
	end
	return v
end

-- Hook visibility-restoring functions on a frame to maintain hidden state
-- CRITICAL: hooksecurefunc is used to avoid taint. Method overrides on Blizzard frames
-- cause taint that spreads through the execution context, blocking protected functions
-- like SetTargetClampingInsets() during nameplate setup.
local function ensureVisibilityHooks(frame, cfg)
	if not frame or hookedFrames[frame] then return end
	hookedFrames[frame] = true
	
	-- Store reference to config getter for hooks
	setProp(frame, "classResourceCfg", ensureConfig)
	
	-- Hook Show to enforce hidden state (runs AFTER Blizzard's Show)
	-- CRITICAL: Combat guard required to avoid tainting nameplate operations during form changes
	if frame.Show then
		hooksecurefunc(frame, "Show", function(self)
			-- Skip during combat to avoid tainting nameplate operations
			if InCombatLockdown and InCombatLockdown() then return end
			local cfgGetter = getProp(self, "classResourceCfg")
			local frameCfg = cfgGetter and cfgGetter()
			if frameCfg and frameCfg.hide then
				self:SetAlpha(0)
				debugPrint("Enforcing hidden via Show hook on", self:GetName() or "unnamed")
			end
		end)
	end
	
	-- Hook SetAlpha to re-enforce hidden state (runs AFTER Blizzard's SetAlpha)
	-- Uses a guard flag to prevent infinite recursion since SetAlpha is called inside the hook
	-- CRITICAL: Combat guard required to avoid tainting nameplate operations during form changes
	if frame.SetAlpha then
		hooksecurefunc(frame, "SetAlpha", function(self, alpha)
			-- Skip during combat to avoid tainting nameplate operations
			if InCombatLockdown and InCombatLockdown() then return end
			-- Guard against recursion
			if getProp(self, "classResourceApplyingAlpha") then return end
			
			local cfgGetter = getProp(self, "classResourceCfg")
			local frameCfg = cfgGetter and cfgGetter()
			if frameCfg and frameCfg.hide and alpha ~= 0 then
				-- Frame should be hidden but Blizzard set non-zero alpha; correct it
				setProp(self, "classResourceApplyingAlpha", true)
				self:SetAlpha(0)
				setProp(self, "classResourceApplyingAlpha", nil)
				debugPrint("Re-enforcing hidden via SetAlpha hook on", self:GetName() or "unnamed")
			end
		end)
	end
	
	debugPrint("Installed visibility hooks on", frame:GetName() or "unnamed")
end

-- Trigger layout update on the managed container
-- Cache the closure to avoid memory allocation on every call
local layoutTriggerClosure = nil
local function triggerLayoutUpdate()
	local container = _G.PlayerFrameBottomManagedFramesContainer
	if container and container.Layout then
		-- Defer to next frame to avoid recursion
		-- CRITICAL: Use cached closure to avoid creating new functions every call
		if not layoutTriggerClosure then
			layoutTriggerClosure = function()
				local c = _G.PlayerFrameBottomManagedFramesContainer
				if c and c.Layout then
					pcall(c.Layout, c)
				end
			end
		end
		C_Timer.After(0, layoutTriggerClosure)
	end
end

-- Set up hook on the layout container to reapply scale after layout
-- CRITICAL: Combat guard required to avoid tainting nameplate operations during form changes
local function ensureLayoutHook()
	if layoutHooked then return end
	
	local container = _G.PlayerFrameBottomManagedFramesContainer
	if container and hooksecurefunc then
		layoutHooked = true
		hooksecurefunc(container, "Layout", function()
			local inCombat = InCombatLockdown and InCombatLockdown()

			-- Reapply styling after layout completes.
			local cfg = ensureConfig()
			if not cfg then return end

			local frames, _ = resolveClassResourceFrames()
			for _, frame in ipairs(frames) do
				-- Skip in-combat scale/visibility enforcement to avoid touching secure-ish paths
				-- during sensitive transitions; zone-change reapply covers this.
				if not inCombat then
					-- Reapply scale (layout doesn't override this)
					-- Baseline is always 1.0 for class resources (no Edit Mode scale)
					local multiplier = clampScale(cfg.scale or 100) / 100
					if frame.SetScale then
						pcall(frame.SetScale, frame, multiplier)
					end

					-- Reapply visibility
					if cfg.hide then
						pcall(frame.SetAlpha, frame, 0)
					end
				end
			end
			debugPrint("Layout hook fired, reapplied scale and visibility")
		end)
		debugPrint("Installed layout container hook")
	end
end

local function applyClassResourceForUnit(unit)
	if unit ~= "Player" then
		return
	end

	local cfg = ensureConfig()
	if not cfg then
		debugPrint("No config available, skipping apply")
		return
	end

	-- Initialize defaults
	if cfg.scale == nil then cfg.scale = 100 end
	if cfg.hide == nil then cfg.hide = false end
	if cfg.offsetX == nil then cfg.offsetX = 0 end
	if cfg.offsetY == nil then cfg.offsetY = 0 end

	local frames, label = resolveClassResourceFrames()
	if #frames == 0 then
		debugPrint("No frames resolved for class resource:", label)
		return
	end
	
	debugPrint("Applying to", #frames, "frame(s) for", label)

	-- Set up layout hook first
	ensureLayoutHook()
	ensureClassResourceZoneWatcher()

	-- Skip layout-affecting changes during combat
	local inCombat = InCombatLockdown and InCombatLockdown()
	
	local offsetX = clampOffset(cfg.offsetX)
	local offsetY = clampOffset(cfg.offsetY)
	local scaleMultiplier = clampScale(cfg.scale) / 100

	for _, frame in ipairs(frames) do
		captureBaselines(frame)
		ensureVisibilityHooks(frame, cfg)

		local origPadding = originalPaddings[frame] or { leftPadding = 0, topPadding = 0 }

		-- POSITIONING: Use leftPadding/topPadding within the managed layout system
		-- TAINT MITIGATION: Only write padding properties when user has requested non-zero offsets.
		-- Zero-Touch profiles (offsetX=0, offsetY=0) skip this write to avoid tainting Blizzard frames.
		-- Users who configure offsets accept the trade-off for the functionality.
		if not inCombat and (offsetX ~= 0 or offsetY ~= 0) then
			local newLeft = (origPadding.leftPadding or 0) + offsetX
			local newTop = (origPadding.topPadding or 0) - offsetY  -- Negate Y so positive = up
			-- Only write if different from current to minimize unnecessary taint surface
			if frame.leftPadding ~= newLeft then
				frame.leftPadding = newLeft
			end
			if frame.topPadding ~= newTop then
				frame.topPadding = newTop
			end
			debugPrint("Set padding for", frame:GetName() or "unnamed",
				"left:", frame.leftPadding, "top:", frame.topPadding)
		end

		-- SCALE: Apply scale multiplier - baseline is always 1.0 for class resources (no Edit Mode scale)
		if frame.SetScale then
			pcall(frame.SetScale, frame, scaleMultiplier)
			debugPrint("Set scale for", frame:GetName() or "unnamed", "to", scaleMultiplier)
		end

		-- VISIBILITY: Use SetAlpha for managed frames (more reliable than Hide/Show)
		if cfg.hide then
			pcall(frame.SetAlpha, frame, 0)
			debugPrint("Hidden", frame:GetName() or "unnamed", "via SetAlpha(0)")
		else
			pcall(frame.SetAlpha, frame, 1)
			debugPrint("Shown", frame:GetName() or "unnamed", "via SetAlpha(1)")
		end
	end

	-- Trigger layout update to apply padding changes when using offsets
	if not inCombat and (offsetX ~= 0 or offsetY ~= 0) then
		triggerLayoutUpdate()
	end

	-- Apply DK rune texture overlay if available
	if addon.ApplyDKRuneTextures then
		addon.ApplyDKRuneTextures("uf")
	end

	-- Apply Mage arcane charge texture overlay if available
	if addon.ApplyMageArcaneChargeTextures then
		addon.ApplyMageArcaneChargeTextures("uf")
	end
end

function addon.ApplyUnitFrameClassResource(unit)
	applyClassResourceForUnit(unit or "Player")
end

function addon.ApplyAllUnitFrameClassResources()
	applyClassResourceForUnit("Player")
end

function addon.UnitFrames_GetPlayerClassResourceTitle()
	local _, label = resolveClassResourceFrames()
	if label and label ~= "" then
		return label
	end
	return "Class Resource"
end

