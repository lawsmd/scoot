-- dkrunes.lua - DK Rune Pixel-Art Texture Overlay System
-- Replaces Blizzard rune visuals with spec-colored pixel skull textures when enabled.
local addonName, addon = ...

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

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

local RUNE_MEDIA_PREFIX = "Interface\\AddOns\\Scoot\\media\\textures\\runes\\pixel-skull-"

local RUNE_MEDIA_EXT = ".tga"

local SPEC_TEXTURES = {
	[1] = RUNE_MEDIA_PREFIX .. "blood" .. RUNE_MEDIA_EXT,
	[2] = RUNE_MEDIA_PREFIX .. "frost" .. RUNE_MEDIA_EXT,
	[3] = RUNE_MEDIA_PREFIX .. "unholy" .. RUNE_MEDIA_EXT,
}
local DEFAULT_TEXTURE = RUNE_MEDIA_PREFIX .. "base" .. RUNE_MEDIA_EXT

-- Blizzard texture region keys to suppress (set alpha 0)
local BLIZZARD_TEXTURE_KEYS = {
	"BG_Shadow", "BG_Inactive", "BG_Active",
	"Rune_Inactive", "Rune_Grad", "Rune_Lines",
	"Rune_Active", "Rune_Mid", "Rune_Eyes",
	"Glow", "Glow2", "Smoke",
}

-- Blizzard animation group keys to stop
local BLIZZARD_ANIM_KEYS = {
	"CooldownFillAnim", "CooldownEndingAnim", "EmptyAnim",
}

--------------------------------------------------------------------------------
-- Config Accessors
--------------------------------------------------------------------------------

local function getUFConfig()
	local db = addon and addon.db and addon.db.profile
	if not db then return nil end
	local cfg = db.unitFrames and db.unitFrames.Player and db.unitFrames.Player.classResource
	return cfg
end

local function getPRDConfig()
	local comp = addon.Components and addon.Components.prdClassResource
	if comp and comp.db then
		return comp.db
	end
end

--------------------------------------------------------------------------------
-- Per-RuneButton Overlay Creation
--------------------------------------------------------------------------------

local function getSpecTexture(specIndex)
	return SPEC_TEXTURES[specIndex] or DEFAULT_TEXTURE
end

local function createRuneOverlay(runeButton)
	local existing = getProp(runeButton, "scooterRuneOverlay")
	if existing then return existing end

	local overlay = CreateFrame("Frame", nil, runeButton)
	overlay:SetAllPoints(runeButton)
	overlay:SetFrameLevel(runeButton:GetFrameLevel() + 10)

	local skull = overlay:CreateTexture(nil, "ARTWORK")
	skull:SetSize(24, 24)
	skull:SetPoint("CENTER", overlay, "CENTER", 0, 0)
	skull:SetTexelSnappingBias(0)
	skull:SetSnapToPixelGrid(false)
	overlay.skull = skull

	local cooldown = CreateFrame("Cooldown", nil, overlay, "CooldownFrameTemplate")
	cooldown:SetAllPoints(skull)
	cooldown:SetFrameLevel(overlay:GetFrameLevel() + 1)
	cooldown:SetReverse(false)
	cooldown:SetDrawBling(false)
	cooldown:SetDrawEdge(false)
	cooldown:SetHideCountdownNumbers(true)
	cooldown:SetSwipeColor(0, 0, 0, 1.0)
	overlay.cooldown = cooldown

	overlay:Hide()
	setProp(runeButton, "scooterRuneOverlay", overlay)
	return overlay
end

--------------------------------------------------------------------------------
-- Blizzard Visual Suppression / Restore
--------------------------------------------------------------------------------

local function suppressBlizzardVisuals(runeButton)
	-- Stop all animation groups (prevents them from re-setting alpha)
	for _, animKey in ipairs(BLIZZARD_ANIM_KEYS) do
		local anim = runeButton[animKey]
		if anim and anim.Stop then
			pcall(anim.Stop, anim)
		end
	end

	-- Set all texture regions to alpha 0
	for _, texKey in ipairs(BLIZZARD_TEXTURE_KEYS) do
		local tex = runeButton[texKey]
		if tex and tex.SetAlpha then
			pcall(tex.SetAlpha, tex, 0)
		end
	end

	-- Hide DepleteVisuals frame and stop its animation
	local deplete = runeButton.DepleteVisuals
	if deplete then
		if deplete.DepleteAnim and deplete.DepleteAnim.Stop then
			pcall(deplete.DepleteAnim.Stop, deplete.DepleteAnim)
		end
		pcall(deplete.Hide, deplete)
	end

	-- Hide Blizzard's Cooldown child
	local blizzCD = runeButton.Cooldown
	if blizzCD and blizzCD.SetAlpha then
		pcall(blizzCD.SetAlpha, blizzCD, 0)
	end

	-- Track that this rune button was suppressed (for safe restore guard)
	setProp(runeButton, "scooterRuneSuppressed", true)
end

local function restoreBlizzardVisuals(runeButton)
	-- Restore Blizzard Cooldown alpha
	local blizzCD = runeButton.Cooldown
	if blizzCD and blizzCD.SetAlpha then
		pcall(blizzCD.SetAlpha, blizzCD, 1)
	end

	-- Restore DepleteVisuals alpha (do NOT force-Show; Blizzard manages visibility)
	local deplete = runeButton.DepleteVisuals
	if deplete and deplete.SetAlpha then
		pcall(deplete.SetAlpha, deplete, 1)
	end

	-- Restore correct texture alphas by replaying the appropriate Blizzard animation
	-- to its final state. Each animation has setToFinalAlpha="true", so Play+Finish
	-- sets exactly the right alpha per texture for that visual state.
	-- (Blindly setting all 12 textures to alpha 1 stacks active+inactive+glow, causing bright artifacts.)
	local vs = runeButton.visualState

	-- Stop all animations first (they were stopped during suppress, but be safe)
	for _, animKey in ipairs(BLIZZARD_ANIM_KEYS) do
		local anim = runeButton[animKey]
		if anim and anim.Stop then
			pcall(anim.Stop, anim)
		end
	end

	-- Restore BG_Shadow (not managed by any animation)
	local bgShadow = runeButton.BG_Shadow
	if bgShadow and bgShadow.SetAlpha then
		pcall(bgShadow.SetAlpha, bgShadow, 1)
	end

	if vs == RUNE_STATE_READY or vs == nil then
		-- Skip CooldownEndingAnim to final: BG_Active=1, Rune_Active=1, rest=0
		local anim = runeButton.CooldownEndingAnim
		if anim and anim.Play and anim.Finish then
			pcall(anim.Play, anim)
			pcall(anim.Finish, anim)
		end
	else
		-- Skip EmptyAnim to final: BG_Inactive=1, Rune_Inactive=0.4, rest=0
		-- Next RUNE_POWER_UPDATE will kick off CooldownFillAnim if needed
		local anim = runeButton.EmptyAnim
		if anim and anim.Play and anim.Finish then
			pcall(anim.Play, anim)
			pcall(anim.Finish, anim)
		end
	end

	-- Clear tracking flags
	setProp(runeButton, "scooterRuneSuppressed", nil)
	setProp(runeButton, "scooterRuneVisualState", nil)
end

--------------------------------------------------------------------------------
-- State Update
--------------------------------------------------------------------------------

-- Blizzard's RuneButtonMixin.VisualState enum (set in untainted context)
local RUNE_STATE_EMPTY = 1
local RUNE_STATE_ON_COOLDOWN = 2
local RUNE_STATE_COOLDOWN_ENDING = 3
local RUNE_STATE_READY = 4

local function updateOverlayState(runeButton, specIndex)
	local overlay = getProp(runeButton, "scooterRuneOverlay")
	if not overlay then return end

	local texturePath = getSpecTexture(specIndex)

	-- Read Blizzard's cached state (set in untainted context by UpdateState)
	-- instead of calling GetRuneCooldown() which returns secrets from tainted context
	local vs = runeButton.visualState
	local lastState = runeButton.lastRuneState

	-- If Blizzard hasn't called UpdateState yet, default to Ready (next RUNE_POWER_UPDATE will correct)
	if vs == nil then
		vs = RUNE_STATE_READY
	end

	if vs == RUNE_STATE_READY then
		-- Ready: bright skull, no cooldown swipe
		overlay:Show()
		overlay.skull:SetTexture(texturePath)
		overlay.skull:SetAlpha(1.0)
		overlay.cooldown:Clear()
	elseif vs == RUNE_STATE_ON_COOLDOWN or vs == RUNE_STATE_COOLDOWN_ENDING then
		-- On cooldown: skull visible with dark swipe
		overlay:Show()
		overlay.skull:SetTexture(texturePath)
		overlay.skull:SetAlpha(1.0)
		overlay.cooldown:SetSwipeTexture(texturePath)
		if lastState and lastState.start and lastState.duration then
			pcall(overlay.cooldown.SetCooldown, overlay.cooldown, lastState.start, lastState.duration)
		end
	else
		-- Empty state: hide overlay
		overlay:Hide()
	end
end

--------------------------------------------------------------------------------
-- Context Resolution
--------------------------------------------------------------------------------

local function resolveRuneContext(runeButton)
	-- Walk parent chain to determine if this is UF or PRD
	local parent = runeButton:GetParent()
	if not parent then return nil, nil end

	local parentName = parent:GetName()

	-- UF RuneFrame is named "RuneFrame"
	if parentName == "RuneFrame" then
		return "uf", parent
	end

	-- PRD: the rune frame is inside PersonalResourceDisplayFrame.ClassFrameContainer
	-- Check up a few levels for the PRD hierarchy
	local grandparent = parent:GetParent()
	if grandparent then
		local gpName = grandparent:GetName()
		if gpName and gpName:find("PersonalResourceDisplay") then
			return "prd", parent
		end
		-- One more level up
		local greatGrandparent = grandparent:GetParent()
		if greatGrandparent then
			local ggpName = greatGrandparent:GetName()
			if ggpName and ggpName:find("PersonalResourceDisplay") then
				return "prd", parent
			end
		end
	end

	-- Fallback: check parent's parent chain more broadly
	-- The PRD class nameplate bar is a child of ClassFrameContainer
	if parentName and parentName:find("DeathKnight") then
		return "prd", parent
	end

end

local function getConfigForContext(context)
	if context == "uf" then
		return getUFConfig()
	elseif context == "prd" then
		return getPRDConfig()
	end
end

--------------------------------------------------------------------------------
-- Hook Installation (per-runeFrame)
--------------------------------------------------------------------------------

local function installRuneHooks(runeFrame)
	if not runeFrame or not runeFrame.Runes then return end
	if getProp(runeFrame, "dkRuneHooksInstalled") then return end

	for i = 1, #runeFrame.Runes do
		local runeButton = runeFrame.Runes[i]
		if runeButton then
			-- Hook UpdateState
			if runeButton.UpdateState then
				hooksecurefunc(runeButton, "UpdateState", function(self)
					local ctx, _ = resolveRuneContext(self)
					local cfg = getConfigForContext(ctx)
					if not cfg or (cfg.textureStyle_DEATHKNIGHT or "default") ~= "pixel" then return end
					suppressBlizzardVisuals(self)
					local specIndex = GetSpecialization and GetSpecialization() or nil
					updateOverlayState(self, specIndex)
				end)
			end

			-- Hook UpdateSpec
			if runeButton.UpdateSpec then
				hooksecurefunc(runeButton, "UpdateSpec", function(self, specIndex)
					local ctx, _ = resolveRuneContext(self)
					local cfg = getConfigForContext(ctx)
					if not cfg or (cfg.textureStyle_DEATHKNIGHT or "default") ~= "pixel" then return end
					local overlay = getProp(self, "scooterRuneOverlay")
					if overlay and overlay.skull then
						local tex = getSpecTexture(specIndex)
						overlay.skull:SetTexture(tex)
						overlay.cooldown:SetSwipeTexture(tex)
					end
				end)
			end
		end
	end

	setProp(runeFrame, "dkRuneHooksInstalled", true)
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

function addon.ApplyDKRuneTextures(context)
	-- Only applies to Death Knights
	local _, playerClass = UnitClass("player")
	if playerClass ~= "DEATHKNIGHT" then return end

	-- Combat guard
	if InCombatLockdown and InCombatLockdown() then return end

	local runeFrame
	local cfg

	if context == "uf" then
		runeFrame = _G.RuneFrame
		cfg = getUFConfig()
	elseif context == "prd" then
		local prd = PersonalResourceDisplayFrame
		if prd and prd.ClassFrameContainer then
			local child = prd.ClassFrameContainer.GetChildren and prd.ClassFrameContainer:GetChildren()
			if child and child.Runes then
				runeFrame = child
			end
		end
		cfg = getPRDConfig()
	end

	if not runeFrame or not runeFrame.Runes then return end
	if not cfg then return end

	local textureStyle = cfg.textureStyle_DEATHKNIGHT or "default"

	if textureStyle == "pixel" then
		-- Install hooks (idempotent)
		installRuneHooks(runeFrame)

		local specIndex = GetSpecialization and GetSpecialization() or nil

		for i = 1, #runeFrame.Runes do
			local runeButton = runeFrame.Runes[i]
			if runeButton then
				-- Create/get overlay
				createRuneOverlay(runeButton)
				-- Suppress Blizzard visuals
				suppressBlizzardVisuals(runeButton)
				-- Update overlay state
				updateOverlayState(runeButton, specIndex)
			end
		end
	else
		-- Default mode: hide overlays, restore Blizzard visuals
		for i = 1, #runeFrame.Runes do
			local runeButton = runeFrame.Runes[i]
			if runeButton then
				local overlay = getProp(runeButton, "scooterRuneOverlay")
				if overlay then
					overlay:Hide()
				end
				if getProp(runeButton, "scooterRuneSuppressed") then
					restoreBlizzardVisuals(runeButton)
				end
			end
		end
	end
end
