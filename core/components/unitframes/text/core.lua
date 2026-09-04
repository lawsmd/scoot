--------------------------------------------------------------------------------
-- text/core.lua
-- Shared state, pre-emptive text hiding, and Character Pane / Edit Mode hooks
-- for the unit frame text subsystem.
--------------------------------------------------------------------------------

local addonName, addon = ...

-- Namespace for cross-file locals (text subsystem)
addon.UnitFrameText = addon.UnitFrameText or {}
local UFT = addon.UnitFrameText

-- Reference to FrameState module for safe property storage (avoids writing to Blizzard frames)
local FS = addon.FrameState

-- Secret-value safe helpers (shared module)
local SS = addon.SecretSafe
local safeOffset = SS.safeOffset
local safePointToken = SS.safePointToken
local safeGetWidth = SS.safeGetWidth

-- Resolve boss name FontString from a boss frame. Promoted to addon namespace so both
-- the health/power text positioning code and the boss name/level block can use it.
function addon.ResolveBossNameFS(bossFrame)
    return (bossFrame and (bossFrame.name
        or (bossFrame.TargetFrameContent
            and bossFrame.TargetFrameContent.TargetFrameContentMain
            and bossFrame.TargetFrameContent.TargetFrameContentMain.Name)))
        or nil
end

-- Map of name-anchor positions to { textPoint, namePoint, justifyH, gapX, gapY }
-- Promoted to addon.UnitFrameText for cross-file access (health.lua, power.lua)
UFT._NAME_ANCHOR_MAP = {
    LEFT_OF_NAME  = { "RIGHT",       "LEFT",        "RIGHT",  -2, 0 },
    RIGHT_OF_NAME = { "LEFT",        "RIGHT",       "LEFT",    2, 0 },
    TOP_LEFT      = { "BOTTOMLEFT",  "TOPLEFT",     "LEFT",    0, 2 },
    TOP           = { "BOTTOM",      "TOP",         "CENTER",  0, 2 },
    TOP_RIGHT     = { "BOTTOMRIGHT", "TOPRIGHT",    "RIGHT",   0, 2 },
    BOTTOM_LEFT   = { "TOPLEFT",     "BOTTOMLEFT",  "LEFT",    0, -2 },
    BOTTOM        = { "TOP",         "BOTTOM",      "CENTER",  0, -2 },
    BOTTOM_RIGHT  = { "TOPRIGHT",    "BOTTOMRIGHT", "RIGHT",   0, -2 },
}

--------------------------------------------------------------------------------
-- Pre-emptive Hiding Functions for Name/Level Text
--------------------------------------------------------------------------------
-- These functions are called SYNCHRONOUSLY (not deferred) from event handlers
-- like PLAYER_TARGET_CHANGED and PLAYER_FOCUS_CHANGED. They hide text elements
-- BEFORE Blizzard's TargetFrame_Update/FocusFrame_Update runs, preventing
-- the brief visual "flash" that occurs when relying solely on post-update hooks.
--------------------------------------------------------------------------------

-- Pre-emptive hide for Level text on Target/Focus frames
-- Called synchronously from PLAYER_TARGET_CHANGED/PLAYER_FOCUS_CHANGED events
function addon.PreemptiveHideLevelText(unit)
	local db = addon and addon.db and addon.db.profile
	local unitFrames = db and rawget(db, "unitFrames")
	local cfg = unitFrames and rawget(unitFrames, unit)
	if not cfg then return end
	-- Only hide if levelTextHidden is explicitly true
	if cfg.levelTextHidden ~= true then return end

	local levelFS = nil
	if unit == "Target" then
		levelFS = _G.TargetFrame and _G.TargetFrame.TargetFrameContent
			and _G.TargetFrame.TargetFrameContent.TargetFrameContentMain
			and _G.TargetFrame.TargetFrameContent.TargetFrameContentMain.LevelText
	elseif unit == "Focus" then
		levelFS = _G.FocusFrame and _G.FocusFrame.TargetFrameContent
			and _G.FocusFrame.TargetFrameContent.TargetFrameContentMain
			and _G.FocusFrame.TargetFrameContent.TargetFrameContentMain.LevelText
	elseif unit == "Player" then
		levelFS = _G.PlayerLevelText
	end

	if levelFS and levelFS.SetShown then
		pcall(levelFS.SetShown, levelFS, false)
	end
end

-- Pre-emptive hide for Name text on Target/Focus frames
-- Called synchronously from PLAYER_TARGET_CHANGED/PLAYER_FOCUS_CHANGED events
function addon.PreemptiveHideNameText(unit)
	local db = addon and addon.db and addon.db.profile
	local unitFrames = db and rawget(db, "unitFrames")
	local cfg = unitFrames and rawget(unitFrames, unit)
	if not cfg then return end
	-- Only hide if nameTextHidden is explicitly true
	if cfg.nameTextHidden ~= true then return end

	local nameFS = nil
	if unit == "Target" then
		nameFS = _G.TargetFrame and _G.TargetFrame.TargetFrameContent
			and _G.TargetFrame.TargetFrameContent.TargetFrameContentMain
			and _G.TargetFrame.TargetFrameContent.TargetFrameContentMain.Name
	elseif unit == "Focus" then
		nameFS = _G.FocusFrame and _G.FocusFrame.TargetFrameContent
			and _G.FocusFrame.TargetFrameContent.TargetFrameContentMain
			and _G.FocusFrame.TargetFrameContent.TargetFrameContentMain.Name
	elseif unit == "Player" then
		nameFS = _G.PlayerName
	end

	if nameFS and nameFS.SetShown then
		pcall(nameFS.SetShown, nameFS, false)
	end
end

--------------------------------------------------------------------------------
-- Character Frame Hook: Reapply Player text styling when Character Pane opens
--------------------------------------------------------------------------------
-- Opening the Character Pane (default keybind: 'C') causes Blizzard to reset
-- Player unit frame text fonts. This hook ensures custom styling persists.
-- NOTE: Simplified to use single deferred callbacks to avoid performance issues.
--------------------------------------------------------------------------------
do
	-- Kept off addon.Refresh: driven by hooks on the Character Frame, not by a refresh pass.
	-- Helper function to reapply all Player text styling
	local function reapplyPlayerTextStyling()
		if addon.ApplyAllUnitFrameHealthTextVisibility then
			addon.ApplyAllUnitFrameHealthTextVisibility()
		end
		if addon.ApplyAllUnitFramePowerTextVisibility then
			addon.ApplyAllUnitFramePowerTextVisibility()
		end
		-- Also reapply bar textures for Alternate Power Bar text
		if addon.ApplyUnitFrameBarTexturesFor then
			addon.ApplyUnitFrameBarTexturesFor("Player")
		end
	end

	-- Hook ToggleCharacter function (called by keybind and menu clicks)
	if _G.hooksecurefunc and _G.ToggleCharacter then
		_G.hooksecurefunc("ToggleCharacter", function(tab)
			-- Reapply text styling after a short delay to let Blizzard finish its updates
			if _G.C_Timer and _G.C_Timer.After then
				_G.C_Timer.After(0.15, reapplyPlayerTextStyling)
			end
		end)
	end

	-- Also hook CharacterFrameTab1-4 OnClick (the tabs at the bottom of Character Frame)
	-- These can trigger updates when switching between Character/Reputation/Currency tabs
	-- NOTE: Uses FrameState to avoid writing properties directly to Blizzard frames (causes taint).
	local function hookCharacterTabs()
		local fstate = FS
		if not fstate then return end
		for i = 1, 4 do
			local tab = _G["CharacterFrameTab" .. i]
			if tab and tab.HookScript and not fstate.IsHooked(tab, "textHooked") then
				fstate.MarkHooked(tab, "textHooked")
				tab:HookScript("OnClick", function()
					if _G.C_Timer and _G.C_Timer.After then
						_G.C_Timer.After(0.15, reapplyPlayerTextStyling)
					end
				end)
			end
		end
	end

	-- Hook CharacterFrame OnShow as a backup
	local function hookCharacterFrameOnShow()
		local fstate = FS
		if not fstate then return end
		local charFrame = _G.CharacterFrame
		if charFrame and charFrame.HookScript and not fstate.IsHooked(charFrame, "textOnShowHooked") then
			fstate.MarkHooked(charFrame, "textOnShowHooked")
			charFrame:HookScript("OnShow", function()
				if _G.C_Timer and _G.C_Timer.After then
					_G.C_Timer.After(0.15, reapplyPlayerTextStyling)
				end
			end)
			-- Also hook tabs when CharacterFrame exists
			hookCharacterTabs()
		end
	end

	-- Try to install hooks immediately
	hookCharacterFrameOnShow()

	-- Also listen for PLAYER_ENTERING_WORLD to install hooks (CharacterFrame may load later)
	addon.Events.On("UnitFrames:Text", "PLAYER_ENTERING_WORLD", function()
		-- Defer to ensure CharacterFrame is loaded
		if _G.C_Timer and _G.C_Timer.After then
			_G.C_Timer.After(1, function()
				hookCharacterFrameOnShow()
			end)
		end
	end)

	-- Hook PaperDollFrame.VisibilityUpdated event for reliable reapplication
	-- Fires when the Character Pane (PaperDollFrame) is shown or hidden
	-- Using EventRegistry is more reliable than HookScript as it uses Blizzard's official event system
	if _G.EventRegistry and _G.EventRegistry.RegisterCallback then
		_G.EventRegistry:RegisterCallback("PaperDollFrame.VisibilityUpdated", function(_, shown)
			if shown then
				-- Single deferred reapply after Blizzard's Character Pane updates complete
				if _G.C_Timer and _G.C_Timer.After then
					_G.C_Timer.After(0.2, reapplyPlayerTextStyling)
				end
			end
		end, addon)
	end
end

--------------------------------------------------------------------------------
-- Edit Mode Exit Hook: Reapply text visibility when Edit Mode closes
--------------------------------------------------------------------------------
-- The SetAlpha visibility hooks skip enforcement during Edit Mode to avoid taint.
-- When Edit Mode closes, Blizzard may have shown text elements that should be hidden.
-- Re-enforces visibility settings after Edit Mode exits.
--------------------------------------------------------------------------------
do
	local function reapplyAllTextVisibility()
		if addon.ApplyAllUnitFrameHealthTextVisibility then
			addon.ApplyAllUnitFrameHealthTextVisibility()
		end
		if addon.ApplyAllUnitFramePowerTextVisibility then
			addon.ApplyAllUnitFramePowerTextVisibility()
		end
	end

	local mgr = _G.EditModeManagerFrame
	if mgr and _G.hooksecurefunc and type(mgr.ExitEditMode) == "function" then
		_G.hooksecurefunc(mgr, "ExitEditMode", function()
			if _G.C_Timer and _G.C_Timer.After then
				-- Immediate reapply
				_G.C_Timer.After(0, function()
					if _G.InCombatLockdown and _G.InCombatLockdown() then return end
					reapplyAllTextVisibility()
				end)
				-- Short delay to catch deferred Blizzard processing
				_G.C_Timer.After(0.1, function()
					if _G.InCombatLockdown and _G.InCombatLockdown() then return end
					reapplyAllTextVisibility()
				end)
				-- Longer delay as safety net
				_G.C_Timer.After(0.3, function()
					if _G.InCombatLockdown and _G.InCombatLockdown() then return end
					reapplyAllTextVisibility()
				end)
			else
				reapplyAllTextVisibility()
			end
		end)
	end
end
