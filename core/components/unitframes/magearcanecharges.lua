-- magearcanecharges.lua - Mage Arcane Charge Pixel-Art Texture Overlay System
-- Replaces Blizzard orb visuals with pixel art textures when enabled.
-- Unlike DK Runes (overlay frames), this directly replaces the Orb texture.
-- ArcaneIcon (white spark) is hidden in pixel mode; other FX animations are preserved.
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

local TEXTURE_PATH = "Interface\\AddOns\\Scoot\\media\\textures\\pixel-arcane-charge"
local CHARGE_ICON_SIZE = 30
local BLIZZARD_ORB_ATLAS = "UF-Arcane-Orb"

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
-- Per-Button Setup / State / Restore
--------------------------------------------------------------------------------

local function hideArcaneIcon(chargeButton)
	local icon = chargeButton.ArcaneIcon
	if icon and icon.Hide then
		pcall(icon.Hide, icon)
	end
end

local function setupChargeOverlay(chargeButton)
	if getProp(chargeButton, "scooterChargeOverlaid") then return end

	local orb = chargeButton.Orb
	if not orb then return end

	-- Replace Orb texture with pixel art
	orb:SetTexture(TEXTURE_PATH)
	orb:SetTexCoord(0, 1, 0, 1)
	orb:SetSize(CHARGE_ICON_SIZE, CHARGE_ICON_SIZE)
	orb:SetTexelSnappingBias(0)
	orb:SetSnapToPixelGrid(false)

	-- Suppress ArcaneBG and ArcaneBGShadow (conflict visually with pixel art)
	local arcaneBG = chargeButton.ArcaneBG
	if arcaneBG then
		arcaneBG:SetAlpha(0)
	end
	local arcaneBGShadow = chargeButton.ArcaneBGShadow
	if arcaneBGShadow then
		arcaneBGShadow:SetAlpha(0)
	end

	hideArcaneIcon(chargeButton)
	setProp(chargeButton, "scooterChargeOverlaid", true)
end

local function updateChargeState(chargeButton)
	local orb = chargeButton.Orb
	if not orb then return end

	if chargeButton.isActive then
		orb:SetAlpha(1.0)
		orb:SetDesaturated(false)
	else
		orb:SetAlpha(0.5)
		orb:SetDesaturated(true)
	end
end

local function restoreChargeButton(chargeButton)
	local orb = chargeButton.Orb
	if orb then
		orb:SetAtlas(BLIZZARD_ORB_ATLAS)
		orb:SetAlpha(1.0)
		orb:SetDesaturated(false)
	end

	local arcaneBG = chargeButton.ArcaneBG
	if arcaneBG then
		arcaneBG:SetAlpha(1)
	end
	local arcaneBGShadow = chargeButton.ArcaneBGShadow
	if arcaneBGShadow then
		arcaneBGShadow:SetAlpha(1)
	end

	local arcaneIcon = chargeButton.ArcaneIcon
	if arcaneIcon and arcaneIcon.Show then
		pcall(arcaneIcon.Show, arcaneIcon)
	end

	setProp(chargeButton, "scooterChargeOverlaid", nil)
	setProp(chargeButton, "scooterChargeSetActiveHooked", nil)
end

--------------------------------------------------------------------------------
-- Hook Installation (per-chargeFrame, idempotent)
--------------------------------------------------------------------------------

local function getConfigForContext(context)
	if context == "uf" then
		return getUFConfig()
	elseif context == "prd" then
		return getPRDConfig()
	end
end

local function resolveChargeContext(chargeFrame)
	if not chargeFrame then return nil end
	local name = chargeFrame:GetName()

	-- UF frame is named "MageArcaneChargesFrame"
	if name == "MageArcaneChargesFrame" then
		return "uf"
	end

	-- PRD frame: ClassNameplateBarMageFrame or child of PRD container
	if name and name:find("ClassNameplate") then
		return "prd"
	end

	-- Walk parents looking for PRD
	local parent = chargeFrame:GetParent()
	while parent do
		local pName = parent:GetName()
		if pName and pName:find("PersonalResourceDisplay") then
			return "prd"
		end
		parent = parent:GetParent()
	end

end

local function installChargeHooks(chargeFrame)
	if not chargeFrame then return end
	if getProp(chargeFrame, "arcaneChargeHooksInstalled") then return end

	-- Hook UpdatePower to catch button creation from pool and state changes
	if chargeFrame.UpdatePower then
		hooksecurefunc(chargeFrame, "UpdatePower", function(self)
			local ctx = resolveChargeContext(self)
			local cfg = getConfigForContext(ctx)
			if not cfg or (cfg.textureStyle_MAGE or "default") ~= "pixel" then return end

			local buttons = self.classResourceButtonTable
			if not buttons then return end

			for i = 1, #buttons do
				local btn = buttons[i]
				if btn then
					-- Setup overlay on new buttons
					if not getProp(btn, "scooterChargeOverlaid") then
						setupChargeOverlay(btn)
					end

					-- Hook SetActive on new buttons (idempotent per-button)
					if not getProp(btn, "scooterChargeSetActiveHooked") and btn.SetActive then
						hooksecurefunc(btn, "SetActive", function(self2)
							local ctx2 = resolveChargeContext(self2:GetParent())
							local cfg2 = getConfigForContext(ctx2)
							if not cfg2 or (cfg2.textureStyle_MAGE or "default") ~= "pixel" then return end
							if getProp(self2, "scooterChargeOverlaid") then
								updateChargeState(self2)
								hideArcaneIcon(self2)
							end
						end)
						setProp(btn, "scooterChargeSetActiveHooked", true)
					end

					-- Update state and suppress FX on newly-pooled buttons
					updateChargeState(btn)
					if getProp(btn, "scooterChargeOverlaid") then
						hideArcaneIcon(btn)
					end
				end
			end
		end)
	end

	setProp(chargeFrame, "arcaneChargeHooksInstalled", true)
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

function addon.ApplyMageArcaneChargeTextures(context)
	local _, playerClass = UnitClass("player")
	if playerClass ~= "MAGE" then return end

	if InCombatLockdown and InCombatLockdown() then return end

	local chargeFrame
	local cfg

	if context == "uf" then
		chargeFrame = _G.MageArcaneChargesFrame
		cfg = getUFConfig()
	elseif context == "prd" then
		local prd = PersonalResourceDisplayFrame
		if prd and prd.ClassFrameContainer and prd.ClassFrameContainer.GetChildren then
			local child = prd.ClassFrameContainer:GetChildren()
			if child and child.classResourceButtonTable then
				chargeFrame = child
			end
		end
		cfg = getPRDConfig()
	end

	if not chargeFrame then return end
	if not cfg then return end

	local textureStyle = cfg.textureStyle_MAGE or "default"
	local buttons = chargeFrame.classResourceButtonTable

	if textureStyle == "pixel" then
		installChargeHooks(chargeFrame)

		if buttons then
			for i = 1, #buttons do
				local btn = buttons[i]
				if btn then
					setupChargeOverlay(btn)

					-- Hook SetActive per-button (idempotent)
					if not getProp(btn, "scooterChargeSetActiveHooked") and btn.SetActive then
						hooksecurefunc(btn, "SetActive", function(self)
							local ctx = resolveChargeContext(self:GetParent())
							local cfg2 = getConfigForContext(ctx)
							if not cfg2 or (cfg2.textureStyle_MAGE or "default") ~= "pixel" then return end
							if getProp(self, "scooterChargeOverlaid") then
								updateChargeState(self)
								hideArcaneIcon(self)
							end
						end)
						setProp(btn, "scooterChargeSetActiveHooked", true)
					end

					updateChargeState(btn)
					hideArcaneIcon(btn)
				end
			end
		end
	else
		-- Default mode: restore all charge buttons
		if buttons then
			for i = 1, #buttons do
				local btn = buttons[i]
				if btn and getProp(btn, "scooterChargeOverlaid") then
					restoreChargeButton(btn)
				end
			end
		end
	end
end
