-- portraits.lua - Portrait offset, scale, zoom, mask, border, and hide controls
local addonName, addon = ...

-- Scratch opts for ResolveColorRGBA (portrait border; unit set per call)
local portraitColorOpts = {}
local Util = addon.ComponentsUtil
local CleanupIconBorderAttachments = Util.CleanupIconBorderAttachments

-- Reference to FrameState module for safe property storage (avoids writing to Blizzard frames)
local FS = addon.FrameState
local SS = addon.SecretSafe
local Enforce = addon.Enforce

-- Portrait zoom traces. Enable with /run Scoot._dbgPortraits = true.
local function trace(...)
	if addon._dbgPortraits then addon.DebugPrint("[Portraits]", ...) end
end

local function getState(frame)
    return FS.Get(frame)
end

-- Unit Frames: Apply Portrait positioning (X/Y offsets)
do
	-- Shared portrait part resolvers (core/frames.lua)
	local resolvePortraitFrame = addon.Frames.resolvePortraitFrame
	local resolvePortraitMaskFrame = addon.Frames.resolvePortraitMaskFrame
	local resolvePortraitCornerIconFrame = addon.Frames.resolvePortraitCornerIconFrame
	local resolvePortraitRestLoopFrame = addon.Frames.resolvePortraitRestLoopFrame
	local resolvePortraitStatusTextureFrame = addon.Frames.resolvePortraitStatusTextureFrame
	local resolveDamageTextFrame = addon.Frames.resolveDamageTextFrame
	local resolveBossPortraitFrameTexture = addon.Frames.resolveBossPortraitFrameTexture
	local resolvePetAttackModeTexture = addon.Frames.resolvePetAttackModeTexture
	local resolvePetFrameFlash = addon.Frames.resolvePetFrameFlash

	-- Store original positions (per frame, not per unit, to handle frame recreation)
	local originalPositions = {}
	-- NOTE: Does NOT capture original scales because frames may retain the applied scale across reloads.
	-- Portrait frames have no Edit Mode scale setting, so baseline is always 1.0.
	-- Store original texture coordinates (per frame, not per unit, to handle frame recreation)
	local originalTexCoords = {}
	-- Store original alpha values (per frame, not per unit, to handle frame recreation)
	local originalAlphas = {}
	-- Store original mask atlas (per frame, not per unit, to handle frame recreation)
	local originalMaskAtlas = {}

	-- OPT-20: Frame resolution cache (session-stable hierarchy)
	-- Avoids 5-8 resolve* calls + portraitTexture resolution per applyForUnit invocation.
	-- NOT cached when resolvePortraitFrame returns nil (Focus/Pet may not exist yet).
	local resolvedFrameCache = {}

	local function getCachedFrames(unit)
		local cached = resolvedFrameCache[unit]
		if cached then return cached end

		local portrait = resolvePortraitFrame(unit)
		if not portrait then return nil end

		-- Resolve portraitTexture from the portrait frame
		local portraitTexture = nil
		if portrait.GetObjectType and portrait:GetObjectType() == "Texture" then
			portraitTexture = portrait
		elseif portrait.GetPortrait then
			portraitTexture = portrait:GetPortrait()
		elseif portrait.GetRegions then
			for _, region in ipairs({ portrait:GetRegions() }) do
				if region and region.GetObjectType and region:GetObjectType() == "Texture" then
					portraitTexture = region
					break
				end
			end
		end

		cached = {
			portrait = portrait,
			mask = resolvePortraitMaskFrame(unit),
			cornerIcon = (unit == "Player") and resolvePortraitCornerIconFrame(unit) or nil,
			restLoop = (unit == "Player") and resolvePortraitRestLoopFrame(unit) or nil,
			statusTexture = (unit == "Player") and resolvePortraitStatusTextureFrame(unit) or nil,
			bossPortrait = (unit == "Target" or unit == "Focus") and resolveBossPortraitFrameTexture(unit) or nil,
			petAttackMode = (unit == "Pet") and resolvePetAttackModeTexture(unit) or nil,
			petFlash = (unit == "Pet") and resolvePetFrameFlash(unit) or nil,
			portraitTexture = portraitTexture,
		}
		resolvedFrameCache[unit] = cached
		return cached
	end

	-- Pet portrait overlays are driven by Blizzard and may re-show/recreate in combat.
	-- Keep them hidden via SetAlpha(0) plus vertex alpha 0 with re-enforcement hooks
	-- (core/enforce.lua; no Hide/Show). Enforcement is synchronous: PetAttackModeTexture
	-- pulses via SetVertexColor in PetFrame:OnUpdate every frame, so a deferred re-assert
	-- loses the race and flashes. The rgb comes from the texture, never from a hook argument.
	local function applyPetOverlayHidden(tex)
		if tex.SetAlpha then pcall(tex.SetAlpha, tex, 0) end
		if tex.SetVertexColor then
			local r, g, b = 1, 1, 1
			if tex.GetVertexColor then
				local ok, rr, gg, bb = pcall(tex.GetVertexColor, tex)
				if ok then
					r, g, b = SS.safeNumber(rr) or r, SS.safeNumber(gg) or g, SS.safeNumber(bb) or b
				end
			end
			pcall(tex.SetVertexColor, tex, r, g, b, 0)
		end
	end
	local PET_OVERLAY_OPTS = { methods = { "Show", "SetShown", "SetAlpha", "SetVertexColor" }, apply = applyPetOverlayHidden }
	local PET_OVERLAY_RELEASE = { restore = false }

	local function applyStickyOverlayAlpha(texture, hidden, visibleAlpha)
		if not texture then return end
		if visibleAlpha == nil then visibleAlpha = 1.0 end
		if hidden then
			Enforce.Set(texture, "petOverlay", true, PET_OVERLAY_OPTS)
			return
		end
		-- Clear the flag, then restore the visible alpha and the vertex alpha so
		-- Blizzard's pulse animation works again (safe in combat: not protected).
		Enforce.Set(texture, "petOverlay", false, PET_OVERLAY_RELEASE)
		if texture.SetAlpha then
			pcall(texture.SetAlpha, texture, visibleAlpha)
		end
		if texture.SetVertexColor then
			local r, g, b = 1, 1, 1
			if texture.GetVertexColor then
				local ok, rr, gg, bb = pcall(texture.GetVertexColor, texture)
				if ok then
					r, g, b = SS.safeNumber(rr) or r, SS.safeNumber(gg) or g, SS.safeNumber(bb) or b
				end
			end
			pcall(texture.SetVertexColor, texture, r, g, b, visibleAlpha)
		end
	end

	local function EnforcePetOverlays()
		-- PetFrame is managed/protected by Edit Mode.
		-- Still flags pending when combat-locked (to re-assert again on combat end),
		-- but also allows the experimental in-combat alpha enforcement to keep PetFrameFlash hidden.
		if InCombatLockdown and InCombatLockdown() then
			addon._pendingPetOverlaysEnforce = true
		end
		local db = addon and addon.db and addon.db.profile
		if not db or not db.unitFrames or not db.unitFrames.Pet then
			return
		end

		local ufCfg = db.unitFrames.Pet
		local portraitCfg = ufCfg.portrait or {}

		local hidePortrait = (portraitCfg.hidePortrait == true)
		local useCustomBorders = (ufCfg.useCustomBorders == true)

		-- Portrait opacity is stored as percent (1-100)
		local opacityPct = tonumber(portraitCfg.opacity) or 100
		if opacityPct < 1 then opacityPct = 1 elseif opacityPct > 100 then opacityPct = 100 end
		local opacityValue = opacityPct / 100.0

		local petPortrait = _G.PetPortrait
		local petPortraitMask = _G.PetPortraitMask
		local petAttackModeTexture = _G.PetAttackModeTexture
		local petFrameFlash = _G.PetFrameFlash

		-- Capture original alpha for newly created texture instances (frame recreation).
		if petPortrait and not originalAlphas[petPortrait] then
			originalAlphas[petPortrait] = petPortrait:GetAlpha() or 1.0
		end
		if petPortraitMask and not originalAlphas[petPortraitMask] then
			originalAlphas[petPortraitMask] = petPortraitMask:GetAlpha() or 1.0
		end
		if petAttackModeTexture and not originalAlphas[petAttackModeTexture] then
			originalAlphas[petAttackModeTexture] = petAttackModeTexture:GetAlpha() or 1.0
		end
		if petFrameFlash and not originalAlphas[petFrameFlash] then
			originalAlphas[petFrameFlash] = petFrameFlash:GetAlpha() or 1.0
		end

		-- Apply visibility/opacity to the pet portrait and mask using sticky alpha
		-- (safe technique that avoids taint by only using SetAlpha, not Hide/Show)
		if petPortrait then
			local visibleAlpha = hidePortrait and 0.0 or ((originalAlphas[petPortrait] or 1.0) * opacityValue)
			applyStickyOverlayAlpha(petPortrait, hidePortrait, visibleAlpha)
		end

		if petPortraitMask then
			local visibleAlpha = hidePortrait and 0.0 or ((originalAlphas[petPortraitMask] or 1.0) * opacityValue)
			applyStickyOverlayAlpha(petPortraitMask, hidePortrait, visibleAlpha)
		end

		-- Apply to overlay textures (attack mode indicator and damage flash)
		if petAttackModeTexture then
			local hidden = hidePortrait or useCustomBorders
			local visibleAlpha = (originalAlphas[petAttackModeTexture] or 1.0) * opacityValue
			applyStickyOverlayAlpha(petAttackModeTexture, hidden, visibleAlpha)
		end

		if petFrameFlash then
			local hidden = hidePortrait or useCustomBorders
			local visibleAlpha = (originalAlphas[petFrameFlash] or 1.0) * opacityValue
			applyStickyOverlayAlpha(petFrameFlash, hidden, visibleAlpha)

			-- Some builds drive the red glow via sub-texture regions under PetFrameFlash.
			-- Enforce sticky alpha on immediate texture regions too (cheap + thorough).
			if petFrameFlash.GetRegions then
				for _, region in ipairs({ petFrameFlash:GetRegions() }) do
					if region and region.GetObjectType and region:GetObjectType() == "Texture" then
						if not originalAlphas[region] and region.GetAlpha then
							originalAlphas[region] = region:GetAlpha() or 1.0
						end
						local regionVisibleAlpha = (originalAlphas[region] or 1.0) * opacityValue
						applyStickyOverlayAlpha(region, hidden, regionVisibleAlpha)
					end
				end
			end
		end
	end

	-- Expose a public helper so init.lua event handlers can re-enforce sticky pet overlays.
	function addon.UnitFrames_EnforcePetOverlays()
		EnforcePetOverlays()
	end

	-- Keep a hidden portrait or mask frame hidden when Blizzard re-shows it
	-- (core/enforce.lua). The flag, portraitHiddenByScoot, is written by the
	-- apply pass below and read live. Show and SetShown re-hide with alpha 0 plus
	-- Hide; SetAlpha re-hides with alpha 0 alone. Synchronous, behind the guard.
	local function applyPortraitHidden(frame, method)
		if frame.SetAlpha then pcall(frame.SetAlpha, frame, 0) end
		if method ~= "SetAlpha" then
			local hide = frame.HideBase or frame.Hide
			if hide then pcall(hide, frame) end
		end
	end
	local PORTRAIT_HIDE_OPTS = {
		methods = { "Show", "SetShown", "SetAlpha" },
		apply = applyPortraitHidden,
		when = function(frame) return getState(frame).portraitHiddenByScoot == true end,
	}

	local function installPortraitHideEnforcement(portraitFrame, maskFrame, unit)
		Enforce.Install(portraitFrame, "portraitHidden", PORTRAIT_HIDE_OPTS)
		Enforce.Install(maskFrame, "portraitHidden", PORTRAIT_HIDE_OPTS)
	end

	-- [OPT-12] Extracted from applyForUnit to eliminate per-call closure allocation.
	-- Each function reads module-level tables (originalPositions, originalTexCoords,
	-- originalAlphas, originalMaskAtlas) directly instead of capturing outer-scope locals.

	local function applyMask(unit, maskFrame, useFullCircleMask)
		if not maskFrame or unit ~= "Player" then return end
		local origAtlas = originalMaskAtlas[maskFrame]
		if not origAtlas then return end
		if useFullCircleMask then
			if maskFrame.SetAtlas then
				pcall(maskFrame.SetAtlas, maskFrame, "CircleMask", false)
			end
		else
			if maskFrame.SetAtlas then
				pcall(maskFrame.SetAtlas, maskFrame, origAtlas, false)
			end
		end
	end

	local function applyScale(unit, portraitFrame, maskFrame, cornerIconFrame, scaleMultiplier)
		if InCombatLockdown() then return end
		-- Scale portrait frame (baseline 1.0 x multiplier)
		-- Use pcall for Pet as PetFrame is Edit Mode managed (SetScale is C-side safe, but guard anyway)
		if unit == "Pet" then
			pcall(portraitFrame.SetScale, portraitFrame, scaleMultiplier)
		else
			portraitFrame:SetScale(scaleMultiplier)
		end
		-- Scale mask frame if it exists
		if maskFrame then
			if unit == "Pet" then
				pcall(maskFrame.SetScale, maskFrame, scaleMultiplier)
			else
				maskFrame:SetScale(scaleMultiplier)
			end
		end
		-- Scale corner icon frame if it exists (Player only)
		if cornerIconFrame and unit == "Player" then
			cornerIconFrame:SetScale(scaleMultiplier)
		end
	end

	local function applyPosition(unit, portraitFrame, maskFrame, cornerIconFrame, offsetX, offsetY)
		if unit == "Pet" then
			-- Skip positioning for Pet - causes entire frame to move due to managed frame layout system
			return
		end
		if InCombatLockdown() then return end
		local origPortrait = originalPositions[portraitFrame]
		if not origPortrait then return end

		-- Move portrait frame
		portraitFrame:ClearAllPoints()
		portraitFrame:SetPoint(origPortrait.point, origPortrait.relativeTo, origPortrait.relativePoint, origPortrait.xOfs + offsetX, origPortrait.yOfs + offsetY)

		-- Move mask frame if it exists
		-- For Target/Focus/Pet, anchor mask to portrait to keep them locked together
		-- For Player, use original anchor to maintain proper positioning
		local origMask = maskFrame and originalPositions[maskFrame] or nil
		if maskFrame and origMask then
			maskFrame:ClearAllPoints()
			if unit == "Target" or unit == "Focus" or unit == "Pet" then
				if unit == "Pet" then
					maskFrame:SetPoint("TOPLEFT", portraitFrame, "TOPLEFT", 0, 0)
					maskFrame:SetPoint("BOTTOMRIGHT", portraitFrame, "BOTTOMRIGHT", 0, 0)
				else
					maskFrame:SetPoint("CENTER", portraitFrame, "CENTER", 0, 0)
				end
			else
				maskFrame:SetPoint(origMask.point, origMask.relativeTo, origMask.relativePoint, origMask.xOfs + offsetX, origMask.yOfs + offsetY)
			end
		end

		-- Move corner icon frame if it exists (Player only)
		local origCornerIcon = cornerIconFrame and originalPositions[cornerIconFrame] or nil
		if cornerIconFrame and origCornerIcon and unit == "Player" then
			cornerIconFrame:ClearAllPoints()
			cornerIconFrame:SetPoint(origCornerIcon.point, origCornerIcon.relativeTo, origCornerIcon.relativePoint, origCornerIcon.xOfs + offsetX, origCornerIcon.yOfs + offsetY)
		end
	end

	local function applyZoom(unit, portraitFrame, portraitTexture, zoomPct)
		if not portraitTexture then
			trace("Portrait zoom - texture not found for", unit)
			return
		end

		-- Re-capture original coordinates if not stored yet (handles texture recreation)
		if not originalTexCoords[portraitFrame] then
			local ulX, ulY, blX, blY, urX, urY, brX, brY = portraitTexture:GetTexCoord()
			local left = math.min(ulX or 0, blX or 0, urX or 0, brX or 0)
			local right = math.max(ulX or 1, blX or 1, urX or 1, brX or 1)
			local top = math.min(ulY or 0, blY or 0, urY or 0, brY or 0)
			local bottom = math.max(ulY or 1, blY or 1, urY or 1, brY or 1)
			originalTexCoords[portraitFrame] = {
				left = left,
				right = right,
				top = top,
				bottom = bottom,
			}
		end

		local origCoords = originalTexCoords[portraitFrame]
		if not origCoords then return end

		local zoomFactor = zoomPct / 100.0

		if zoomFactor == 1.0 then
			-- No zoom: restore original coordinates
			if portraitTexture.SetTexCoord then
				portraitTexture:SetTexCoord(origCoords.left, origCoords.right, origCoords.top, origCoords.bottom)
			end
		elseif zoomFactor > 1.0 then
			-- Zoom in: crop edges
			local cropAmount = (zoomFactor - 1.0) / (2.0 * zoomFactor)
			local origWidth = origCoords.right - origCoords.left
			local origHeight = origCoords.bottom - origCoords.top
			local newLeft = origCoords.left + (origWidth * cropAmount)
			local newRight = origCoords.right - (origWidth * cropAmount)
			local newTop = origCoords.top + (origHeight * cropAmount)
			local newBottom = origCoords.bottom - (origHeight * cropAmount)

			if portraitTexture.SetTexCoord then
				portraitTexture:SetTexCoord(newLeft, newRight, newTop, newBottom)
				trace(string.format("Portrait zoom %d%% for %s - coords: %.3f,%.3f,%.3f,%.3f", zoomPct, unit, newLeft, newRight, newTop, newBottom))
			end
		else
			-- Zoom out: show more (limited by texture bounds)
			local origWidth = origCoords.right - origCoords.left
			local origHeight = origCoords.bottom - origCoords.top

			local isFullBounds = (origCoords.left <= 0.001 and origCoords.right >= 0.999 and
			                      origCoords.top <= 0.001 and origCoords.bottom >= 0.999)

			if isFullBounds then
				if portraitTexture.SetTexCoord then
					portraitTexture:SetTexCoord(origCoords.left, origCoords.right, origCoords.top, origCoords.bottom)
				end
				trace(string.format("Portrait zoom out %d%% for %s - limited by full texture bounds (0,1,0,1)", zoomPct, unit))
			else
				local origCenterX = origCoords.left + (origWidth / 2.0)
				local origCenterY = origCoords.top + (origHeight / 2.0)
				local newWidth = origWidth / zoomFactor
				local newHeight = origHeight / zoomFactor
				local newLeft = math.max(0, origCenterX - (newWidth / 2.0))
				local newRight = math.min(1, origCenterX + (newWidth / 2.0))
				local newTop = math.max(0, origCenterY - (newHeight / 2.0))
				local newBottom = math.min(1, origCenterY + (newHeight / 2.0))

				if portraitTexture.SetTexCoord then
					portraitTexture:SetTexCoord(newLeft, newRight, newTop, newBottom)
					trace(string.format("Portrait zoom out %d%% for %s - coords: %.3f,%.3f,%.3f,%.3f", zoomPct, unit, newLeft, newRight, newTop, newBottom))
				end
			end
		end
	end

	local function applyBorder(unit, portraitFrame, cfg)
		if not portraitFrame then return end

		local parentFrame = portraitFrame:GetParent()
		if not parentFrame then return end

		local borderKey = "ScootPortraitBorder_" .. tostring(unit)
		local borderTexture = parentFrame[borderKey]

		local hidePortrait = (cfg.hidePortrait == true)
		local borderEnabled = cfg.portraitBorderEnable and not hidePortrait
		if not borderEnabled then
			if borderTexture then
				borderTexture:Hide()
			end
			return
		end

		local borderStyle = cfg.portraitBorderStyle or "texture_c"
		if borderStyle == "default" then
			borderStyle = "texture_c"
		end

		local textureMap = {
			texture_c = "Interface\\AddOns\\Scoot\\media\\portraitborder\\texture_c.tga",
			texture_s = "Interface\\AddOns\\Scoot\\media\\portraitborder\\texture_s.tga",
			rare_c = "Interface\\AddOns\\Scoot\\media\\portraitborder\\rare_c.tga",
			rare_s = "Interface\\AddOns\\Scoot\\media\\portraitborder\\rare_s.tga",
		}

		local texturePath = textureMap[borderStyle]
		if not texturePath then return end

		if not borderTexture then
			if unit == "Pet" then
				local ok, tex = pcall(parentFrame.CreateTexture, parentFrame, nil, "OVERLAY")
				if ok and tex then
					borderTexture = tex
					parentFrame[borderKey] = borderTexture
				else
					return
				end
			else
				borderTexture = parentFrame:CreateTexture(nil, "OVERLAY")
				parentFrame[borderKey] = borderTexture
			end
		end

		borderTexture:SetTexture(texturePath)

		local thickness = tonumber(cfg.portraitBorderThickness) or 1
		if thickness < 1 then thickness = 1 elseif thickness > 16 then thickness = 16 end

		local baseOutset = 4.0
		local expandX = -(baseOutset + (thickness * 2.0))
		local expandY = -(baseOutset + (thickness * 2.0))

		borderTexture:ClearAllPoints()
		borderTexture:SetPoint("TOPLEFT", portraitFrame, "TOPLEFT", expandX, -expandY)
		borderTexture:SetPoint("BOTTOMRIGHT", portraitFrame, "BOTTOMRIGHT", -expandX, expandY)

		local colorMode = cfg.portraitBorderColorMode or "texture"
		portraitColorOpts.unitForClass = unit == "Player" and "player" or (unit == "Target" and "target" or (unit == "Focus" and "focus" or "pet"))
		local r, g, b, a = addon.ResolveColorRGBA(colorMode, cfg.portraitBorderTintColor, portraitColorOpts)

		borderTexture:SetVertexColor(r, g, b, a)
		borderTexture:SetDrawLayer("OVERLAY", 7)
		borderTexture:Show()
	end

	local function ensureDamageTextBaseline(fs, key)
		addon._ufDamageTextBaselines = addon._ufDamageTextBaselines or {}
		addon._ufDamageTextBaselines[key] = addon._ufDamageTextBaselines[key] or {}
		local b = addon._ufDamageTextBaselines[key]
		if b.point == nil then
			if fs and fs.GetPoint then
				local p, relTo, rp, x, y = fs:GetPoint(1)
				b.point = p or "CENTER"
				b.relTo = relTo or (fs.GetParent and fs:GetParent()) or nil
				b.relPoint = rp or b.point
				b.x = tonumber(x) or 0
				b.y = tonumber(y) or 0
			else
				b.point, b.relTo, b.relPoint, b.x, b.y = "CENTER", (fs and fs.GetParent and fs:GetParent()) or nil, "CENTER", 0, 0
			end
		end
		return b
	end

	local function applyVisibility(unit, portraitFrame, maskFrame, cornerIconFrame, restLoopFrame, statusTextureFrame, bossPortraitFrameTexture, petAttackModeTexture, petFrameFlash, cfg, ufCfg, opacityValue)
		local hidePortrait = (cfg.hidePortrait == true)
		local hideRestLoop = (cfg.hideRestLoop == true)
		local hideStatusTexture = (cfg.hideStatusTexture == true)
		local hideCornerIcon = (cfg.hideCornerIcon == true)

		local origPortraitAlpha = originalAlphas[portraitFrame] or 1.0
		local origMaskAlpha = maskFrame and (originalAlphas[maskFrame] or 1.0) or nil
		local origCornerIconAlpha = cornerIconFrame and (originalAlphas[cornerIconFrame] or 1.0) or nil
		local origRestLoopAlpha = restLoopFrame and (originalAlphas[restLoopFrame] or 1.0) or nil
		local origStatusTextureAlpha = statusTextureFrame and (originalAlphas[statusTextureFrame] or 1.0) or nil
		local origBossPortraitFrameTextureAlpha = bossPortraitFrameTexture and (originalAlphas[bossPortraitFrameTexture] or 1.0) or nil
		local origPetAttackModeTextureAlpha = petAttackModeTexture and (originalAlphas[petAttackModeTexture] or 1.0) or nil
		local origPetFrameFlashAlpha = petFrameFlash and (originalAlphas[petFrameFlash] or 1.0) or nil

		if unit ~= "Pet" then
			local portraitHidden = hidePortrait
			local finalAlpha = portraitHidden and 0.0 or (origPortraitAlpha * opacityValue)

			local pfState = getState(portraitFrame)
			if pfState then
				pfState.portraitHiddenByScoot = portraitHidden
			end

			if portraitHidden then
				installPortraitHideEnforcement(portraitFrame, maskFrame, unit)

				if portraitFrame.SetAlpha then
					portraitFrame:SetAlpha(0)
				end
				if portraitFrame.Hide then
					portraitFrame:Hide()
				end
			else
				if portraitFrame.SetAlpha then
					portraitFrame:SetAlpha(finalAlpha)
				end
				if portraitFrame.Show then
					portraitFrame:Show()
				end
			end

			if maskFrame then
				local maskHidden = hidePortrait
				local maskAlpha = maskHidden and 0.0 or (origMaskAlpha * opacityValue)

				local mfState = getState(maskFrame)
				if mfState then
					mfState.portraitHiddenByScoot = maskHidden
				end

				if maskHidden then
					if maskFrame.SetAlpha then
						maskFrame:SetAlpha(0)
					end
					if maskFrame.Hide then
						maskFrame:Hide()
					end
				else
					if maskFrame.SetAlpha then
						maskFrame:SetAlpha(maskAlpha)
					end
					if maskFrame.Show then
						maskFrame:Show()
					end
				end
			end
		end

		if cornerIconFrame and unit == "Player" then
			local iconHidden = hidePortrait or hideCornerIcon
			local iconAlpha = iconHidden and 0.0 or (origCornerIconAlpha * opacityValue)
			if cornerIconFrame.SetAlpha then
				cornerIconFrame:SetAlpha(iconAlpha)
			end
			if iconHidden and cornerIconFrame.Hide then
				cornerIconFrame:Hide()
			end
		end

		if restLoopFrame and unit == "Player" then
			local restHidden = hidePortrait or hideRestLoop
			local restAlpha = restHidden and 0.0 or (origRestLoopAlpha * opacityValue)
			if restLoopFrame.SetAlpha then
				restLoopFrame:SetAlpha(restAlpha)
			end
			if restHidden and restLoopFrame.Hide then
				restLoopFrame:Hide()
			end
		end

		if statusTextureFrame and unit == "Player" then
			local useCustomBorders = ufCfg and (ufCfg.useCustomBorders == true)
			local statusHidden = hidePortrait or hideStatusTexture or useCustomBorders
			local statusAlpha = statusHidden and 0.0 or (origStatusTextureAlpha * opacityValue)
			if statusTextureFrame.SetAlpha then
				statusTextureFrame:SetAlpha(statusAlpha)
			end
			if statusHidden and statusTextureFrame.Hide then
				statusTextureFrame:Hide()
			end
		end

		if bossPortraitFrameTexture and (unit == "Target" or unit == "Focus") then
			local bossTexHidden = hidePortrait
			local bossTexAlpha = bossTexHidden and 0.0 or (origBossPortraitFrameTextureAlpha * opacityValue)
			if bossPortraitFrameTexture.SetAlpha then
				bossPortraitFrameTexture:SetAlpha(bossTexAlpha)
			end
			if bossTexHidden and bossPortraitFrameTexture.Hide then
				bossPortraitFrameTexture:Hide()
			end
		end

		if petAttackModeTexture and unit == "Pet" then
			local useCustomBorders = ufCfg and (ufCfg.useCustomBorders == true)
			local petAttackHidden = hidePortrait or useCustomBorders
			local petAttackVisibleAlpha = (origPetAttackModeTextureAlpha * opacityValue)
			applyStickyOverlayAlpha(petAttackModeTexture, petAttackHidden, petAttackVisibleAlpha)
		end

		if petFrameFlash and unit == "Pet" then
			local useCustomBorders = ufCfg and (ufCfg.useCustomBorders == true)
			local petFlashHidden = hidePortrait or useCustomBorders
			local petFlashVisibleAlpha = (origPetFrameFlashAlpha * opacityValue)
			applyStickyOverlayAlpha(petFrameFlash, petFlashHidden, petFlashVisibleAlpha)
		end
	end

	local function applyDamageText(unit, cfg)
		if unit ~= "Player" and unit ~= "Pet" then return end
		local damageTextFrame = resolveDamageTextFrame(unit)
		if not damageTextFrame then return end

		local damageTextDisabled = cfg.damageTextDisabled == true

		if damageTextDisabled then
			if damageTextFrame.SetAlpha then
				pcall(damageTextFrame.SetAlpha, damageTextFrame, 0)
			end
			return
		end

		local damageTextCfg = cfg.damageText or {}

		-- Hook SetTextHeight to re-apply the custom font size after Blizzard changes it
		-- Skip for Pet: PetHitIndicator is a child of PetFrame (Edit Mode system frame) — Rule 11
		local dtState = getState(damageTextFrame)
		if dtState then dtState.unitKey = unit end
		if unit ~= "Pet" and dtState and not dtState.setTextHeightHooked then
			dtState.setTextHeightHooked = true

			hooksecurefunc(damageTextFrame, "SetTextHeight", function(self, height)
				local st = getState(self)
				if st and st.applyingTextHeight then return end

				local unitKey = (st and st.unitKey) or "Player"
				local db = addon and addon.db and addon.db.profile
				if db and db.unitFrames and db.unitFrames[unitKey] and db.unitFrames[unitKey].portrait then
					local cfg = db.unitFrames[unitKey].portrait
					local damageTextCfg = cfg.damageText or {}
					local customSize = tonumber(damageTextCfg.size)
					if customSize then
						local customFace = addon.ResolveFontFace(damageTextCfg.fontFace)
						local customStyle = tostring(damageTextCfg.style or "OUTLINE")
						if st then st.applyingTextHeight = true end
						if addon.ApplyFontStyle then
							addon.ApplyFontStyle(self, customFace, customSize, customStyle)
						elseif self.SetFont then
							pcall(self.SetFont, self, customFace, customSize, customStyle)
						end
						if st then st.applyingTextHeight = nil end
					end
				end
			end)
		end

		-- Apply text styling
		local face = addon.ResolveFontFace(damageTextCfg.fontFace)
		local size = tonumber(damageTextCfg.size) or 14
		local outline = tostring(damageTextCfg.style or "OUTLINE")
		if addon.ApplyFontStyle then
			addon.ApplyFontStyle(damageTextFrame, face, size, outline)
		elseif damageTextFrame.SetFont then
			pcall(damageTextFrame.SetFont, damageTextFrame, face, size, outline)
		end

		-- Kept off addon.ResolveColorRGBA: custom and default both fall back to the stored color, else Name/Level Text yellow.
		-- Determine color based on colorMode
		local c = nil
		local colorMode = damageTextCfg.colorMode or "default"
		if colorMode == "class" then
			if addon.GetClassColorRGB then
				local cr, cg, cb = addon.GetClassColorRGB("player")
				c = { cr or 1, cg or 1, cb or 1, 1 }
			else
				c = {1.0, 0.82, 0.0, 1}
			end
		elseif colorMode == "custom" then
			c = damageTextCfg.color or {1.0, 0.82, 0.0, 1}
		else
			c = damageTextCfg.color or {1.0, 0.82, 0.0, 1}
		end
		if damageTextFrame.SetTextColor then
			pcall(damageTextFrame.SetTextColor, damageTextFrame, c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
		end

		-- Apply offset (skip for Pet — ClearAllPoints/SetPoint risky on system frame child)
		if unit ~= "Pet" then
			local ox = (damageTextCfg.offset and tonumber(damageTextCfg.offset.x)) or 0
			local oy = (damageTextCfg.offset and tonumber(damageTextCfg.offset.y)) or 0
			if damageTextFrame.ClearAllPoints and damageTextFrame.SetPoint then
				local b = ensureDamageTextBaseline(damageTextFrame, unit .. ":damageText")
				damageTextFrame:ClearAllPoints()
				damageTextFrame:SetPoint(b.point or "CENTER", b.relTo or (damageTextFrame.GetParent and damageTextFrame:GetParent()) or nil, b.relPoint or b.point or "CENTER", (b.x or 0) + ox, (b.y or 0) + oy)
			end
		end
	end


	local function applyForUnit(unit)
		if not addon:IsModuleEnabled("unitFrames", unit) then return end
		local db = addon and addon.db and addon.db.profile
		if not db then return end
		local unitFrames = rawget(db, "unitFrames")
		local ufCfg = unitFrames and rawget(unitFrames, unit) or nil
		if not ufCfg then return end
		local cfg = rawget(ufCfg, "portrait")
		if not cfg then return end

		-- OPT-20: Use cached frame resolution (session-stable hierarchy)
		local frames = getCachedFrames(unit)
		if not frames then return end
		local portraitFrame = frames.portrait
		local maskFrame = frames.mask
		local cornerIconFrame = frames.cornerIcon
		local restLoopFrame = frames.restLoop
		local statusTextureFrame = frames.statusTexture
		local bossPortraitFrameTexture = frames.bossPortrait
		local petAttackModeTexture = frames.petAttackMode
		local petFrameFlash = frames.petFlash

		-- Capture original positions on first access
		if not originalPositions[portraitFrame] then
			local point, relativeTo, relativePoint, xOfs, yOfs = portraitFrame:GetPoint()
			if point then
				originalPositions[portraitFrame] = {
					point = point,
					relativeTo = relativeTo,
					relativePoint = relativePoint,
					xOfs = xOfs or 0,
					yOfs = yOfs or 0,
				}
			end
		end

		-- Capture mask position if it exists
		if maskFrame and not originalPositions[maskFrame] then
			local point, relativeTo, relativePoint, xOfs, yOfs = maskFrame:GetPoint()
			if point then
				originalPositions[maskFrame] = {
					point = point,
					relativeTo = relativeTo,
					relativePoint = relativePoint,
					xOfs = xOfs or 0,
					yOfs = yOfs or 0,
				}
			end
		end

		-- Capture corner icon position if it exists
		if cornerIconFrame and not originalPositions[cornerIconFrame] then
			local point, relativeTo, relativePoint, xOfs, yOfs = cornerIconFrame:GetPoint()
			if point then
				originalPositions[cornerIconFrame] = {
					point = point,
					relativeTo = relativeTo,
					relativePoint = relativePoint,
					xOfs = xOfs or 0,
					yOfs = yOfs or 0,
				}
			end
		end

		local origPortrait = originalPositions[portraitFrame]
		if not origPortrait then return end

		local origMask = maskFrame and originalPositions[maskFrame] or nil
		local origCornerIcon = cornerIconFrame and originalPositions[cornerIconFrame] or nil

		-- NOTE: Portrait scale baseline is always 1.0 (no Edit Mode scale setting for portraits)
		-- Does NOT capture frame:GetScale() because the frame may retain the applied scale across reloads

		local portraitTexture = frames.portraitTexture

		-- Capture original texture coordinates on first access
		if portraitTexture and not originalTexCoords[portraitFrame] then
			-- GetTexCoord returns 8 values: ulX, ulY, blX, blY, urX, urY, brX, brY
			-- Extract bounds from corner coordinates
			local ulX, ulY, blX, blY, urX, urY, brX, brY = portraitTexture:GetTexCoord()
			-- Extract min/max from all corners to get bounding box
			local left = math.min(ulX or 0, blX or 0, urX or 0, brX or 0)
			local right = math.max(ulX or 1, blX or 1, urX or 1, brX or 1)
			local top = math.min(ulY or 0, blY or 0, urY or 0, brY or 0)
			local bottom = math.max(ulY or 1, blY or 1, urY or 1, brY or 1)
			originalTexCoords[portraitFrame] = {
				left = left,
				right = right,
				top = top,
				bottom = bottom,
			}
		end

		-- Capture original alpha on first access
		if not originalAlphas[portraitFrame] then
			originalAlphas[portraitFrame] = portraitFrame:GetAlpha() or 1.0
		end
		if maskFrame and not originalAlphas[maskFrame] then
			originalAlphas[maskFrame] = maskFrame:GetAlpha() or 1.0
		end
		if cornerIconFrame and not originalAlphas[cornerIconFrame] then
			originalAlphas[cornerIconFrame] = cornerIconFrame:GetAlpha() or 1.0
		end
		if restLoopFrame and not originalAlphas[restLoopFrame] then
			originalAlphas[restLoopFrame] = restLoopFrame:GetAlpha() or 1.0
		end
		if statusTextureFrame and not originalAlphas[statusTextureFrame] then
			originalAlphas[statusTextureFrame] = statusTextureFrame:GetAlpha() or 1.0
		end
		if bossPortraitFrameTexture and not originalAlphas[bossPortraitFrameTexture] then
			originalAlphas[bossPortraitFrameTexture] = bossPortraitFrameTexture:GetAlpha() or 1.0
		end
		if petAttackModeTexture and not originalAlphas[petAttackModeTexture] then
			originalAlphas[petAttackModeTexture] = petAttackModeTexture:GetAlpha() or 1.0
		end
		if petFrameFlash and not originalAlphas[petFrameFlash] then
			originalAlphas[petFrameFlash] = petFrameFlash:GetAlpha() or 1.0
		end

		local origPortraitAlpha = originalAlphas[portraitFrame] or 1.0
		local origMaskAlpha = maskFrame and (originalAlphas[maskFrame] or 1.0) or nil
		local origCornerIconAlpha = cornerIconFrame and (originalAlphas[cornerIconFrame] or 1.0) or nil
		local origRestLoopAlpha = restLoopFrame and (originalAlphas[restLoopFrame] or 1.0) or nil
		local origStatusTextureAlpha = statusTextureFrame and (originalAlphas[statusTextureFrame] or 1.0) or nil
		local origBossPortraitFrameTextureAlpha = bossPortraitFrameTexture and (originalAlphas[bossPortraitFrameTexture] or 1.0) or nil
		local origPetAttackModeTextureAlpha = petAttackModeTexture and (originalAlphas[petAttackModeTexture] or 1.0) or nil
		local origPetFrameFlashAlpha = petFrameFlash and (originalAlphas[petFrameFlash] or 1.0) or nil

		-- Capture original mask atlas on first access (for Player only - to support full circle mask)
		if maskFrame and unit == "Player" and not originalMaskAtlas[maskFrame] then
			if maskFrame.GetAtlas then
				local ok, atlas = pcall(maskFrame.GetAtlas, maskFrame)
				if ok and atlas then
					originalMaskAtlas[maskFrame] = atlas
				else
					-- Fallback: use known default Player mask atlas
					originalMaskAtlas[maskFrame] = "UI-HUD-UnitFrame-Player-Portrait-Mask"
				end
			else
				-- Fallback: use known default Player mask atlas
				originalMaskAtlas[maskFrame] = "UI-HUD-UnitFrame-Player-Portrait-Mask"
			end
		end

		local origMaskAtlas = maskFrame and (originalMaskAtlas[maskFrame] or nil) or nil

		-- Get offsets from config
		local offsetX = tonumber(cfg.offsetX) or 0
		local offsetY = tonumber(cfg.offsetY) or 0

		-- Get scale from config (100-200%, stored as percentage)
		local scalePct = tonumber(cfg.scale) or 100
		local scaleMultiplier = scalePct / 100.0

		-- Get zoom from config (100-200%, stored as percentage)
		-- 100% = no zoom (full texture), > 100% = zoom in (crop edges)
		-- Note: Zoom out (< 100%) is not supported - portrait textures are at full bounds (0,1,0,1)
		local zoomPct = tonumber(cfg.zoom) or 100
		if zoomPct < 100 then zoomPct = 100 elseif zoomPct > 200 then zoomPct = 200 end

		-- Get visibility settings from config
		local hidePortrait = (cfg.hidePortrait == true)
		local hideRestLoop = (cfg.hideRestLoop == true)
		local hideStatusTexture = (cfg.hideStatusTexture == true)
		local hideCornerIcon = (cfg.hideCornerIcon == true)
		local opacityPct = tonumber(cfg.opacity) or 100
		if opacityPct < 1 then opacityPct = 1 elseif opacityPct > 100 then opacityPct = 100 end
		local opacityValue = opacityPct / 100.0

		-- Get full circle mask setting (Player only)
		local useFullCircleMask = (unit == "Player") and (cfg.useFullCircleMask == true) or false


		if InCombatLockdown() then
			-- Pet overlays are combat-driven and may appear during combat; enforce sticky alpha immediately.
			-- This path only uses SetAlpha + hooksecurefunc on the texture itself (combat-safe).
			if unit == "Pet" then
				EnforcePetOverlays()
			end
			-- Defer application until out of combat
			if _G.C_Timer and _G.C_Timer.After then
				_G.C_Timer.After(0.1, function()
					if not InCombatLockdown() then
						applyPosition(unit, portraitFrame, maskFrame, cornerIconFrame, offsetX, offsetY)
						applyScale(unit, portraitFrame, maskFrame, cornerIconFrame, scaleMultiplier)
						applyZoom(unit, portraitFrame, portraitTexture, zoomPct)
						applyMask(unit, maskFrame, useFullCircleMask)
						applyBorder(unit, portraitFrame, cfg)
						applyVisibility(unit, portraitFrame, maskFrame, cornerIconFrame, restLoopFrame, statusTextureFrame, bossPortraitFrameTexture, petAttackModeTexture, petFrameFlash, cfg, ufCfg, opacityValue)
						applyDamageText(unit, cfg)
					end
				end)
			end
		else
			-- Pet overlays use a separate enforcement path due to Edit Mode taint restrictions
			if unit == "Pet" then
				EnforcePetOverlays()
			end
			applyPosition(unit, portraitFrame, maskFrame, cornerIconFrame, offsetX, offsetY)
			applyScale(unit, portraitFrame, maskFrame, cornerIconFrame, scaleMultiplier)
			applyZoom(unit, portraitFrame, portraitTexture, zoomPct)
			applyMask(unit, maskFrame, useFullCircleMask)
			applyBorder(unit, portraitFrame, cfg)
			applyVisibility(unit, portraitFrame, maskFrame, cornerIconFrame, restLoopFrame, statusTextureFrame, bossPortraitFrameTexture, petAttackModeTexture, petFrameFlash, cfg, ufCfg, opacityValue)
			applyDamageText(unit, cfg)
		end
	end

	function addon.ApplyUnitFramePortraitFor(unit)
		applyForUnit(unit)
	end

	function addon.ApplyAllUnitFramePortraits()
		applyForUnit("Player")
		applyForUnit("Target")
		applyForUnit("Focus")
		applyForUnit("Pet")
		applyForUnit("TargetOfTarget")
		applyForUnit("FocusTarget")
	end

	-- OPT-20: Debounce portrait hook invocations
	-- Both UnitFramePortrait_Update and SetPortraitTexture fire for the same event.
	-- Coalesce into a single C_Timer.After(0) per unit per frame.
	local pendingPortraitUnits = {}
	local portraitTimerScheduled = false

	local function schedulePortraitApply(unitKey)
		pendingPortraitUnits[unitKey] = true
		if portraitTimerScheduled then return end
		portraitTimerScheduled = true
		if _G.C_Timer and _G.C_Timer.After then
			_G.C_Timer.After(0, function()
				portraitTimerScheduled = false
				for unit in pairs(pendingPortraitUnits) do
					pendingPortraitUnits[unit] = nil
					applyForUnit(unit)
				end
			end)
		end
	end

	-- Hook portrait updates to reapply zoom when Blizzard updates portraits
	-- Hook UnitFramePortrait_Update which is called when portraits need refreshing
	if _G.UnitFramePortrait_Update then
		_G.hooksecurefunc("UnitFramePortrait_Update", function(unitFrame)
			-- Screen before unitFrame.unit: indexing a secret handle throws
			unitFrame = SS.plainFrame(unitFrame)
			if unitFrame and unitFrame.unit then
				local unit = unitFrame.unit
				local unitKey = nil
				if unit == "player" then unitKey = "Player"
				elseif unit == "target" then unitKey = "Target"
				elseif unit == "focus" then unitKey = "Focus"
				elseif unit == "pet" then unitKey = "Pet"
				elseif unit == "targettarget" then unitKey = "TargetOfTarget"
				end
				if unitKey then
					schedulePortraitApply(unitKey)
				end
			end
		end)
	end

	-- Hook Blizzard's CombatFeedback system to prevent showing damage text when disabled
	-- Need to hook both OnCombatEvent (when damage happens) and OnUpdate (animation loop)
	-- CombatFeedback_OnCombatEvent receives PlayerFrame/PetFrame as 'self', and frame.feedbackText is the HitText
	-- CombatFeedback_OnUpdate also receives PlayerFrame/PetFrame as 'self'
	if _G.CombatFeedback_OnCombatEvent then
		_G.hooksecurefunc("CombatFeedback_OnCombatEvent", function(self, event, flags, amount, type)
			-- Comparing a secret throws just like indexing one, so screen before the
			-- PlayerFrame/PetFrame test below.
			self = SS.plainFrame(self)
			if not self then return end

			-- Dispatch: determine unit key and feedback FontString
			-- For Pet, use _G.PetHitIndicator directly (avoids reading PetFrame's Lua table)
			local unitKey, feedbackFS
			if self == _G.PlayerFrame then
				unitKey = "Player"
				feedbackFS = self.feedbackText
			elseif self == _G.PetFrame then
				unitKey = "Pet"
				feedbackFS = _G.PetHitIndicator
			else
				return
			end

			if feedbackFS then
				local db = addon and addon.db and addon.db.profile
				if db and db.unitFrames and db.unitFrames[unitKey] and db.unitFrames[unitKey].portrait then
					local cfg = db.unitFrames[unitKey].portrait
					local damageTextDisabled = cfg.damageTextDisabled == true

					if damageTextDisabled then
						-- Immediately set alpha to 0 if disabled, preventing it from being visible
						-- Happens after Blizzard sets feedbackStartTime, so it won't cause nil errors
						if feedbackFS.SetAlpha then
							pcall(feedbackFS.SetAlpha, feedbackFS, 0)
						end
					else
						-- Override Blizzard's font size with the custom size
						-- Blizzard calls SetTextHeight(fontHeight) which sets the text region height
						-- Uses SetFont() with the custom size instead, which sets the real font size
						-- SetFont will properly scale the text, while SetTextHeight just scales the region (causing pixelation)
						local damageTextCfg = cfg.damageText or {}
						local customSize = tonumber(damageTextCfg.size) or 14
						local customFace = addon.ResolveFontFace(damageTextCfg.fontFace)
						local customStyle = tostring(damageTextCfg.style or "OUTLINE")

						-- Use SetFont to set the font size (SetTextHeight only scales the region)
						-- This must be called after Blizzard's SetTextHeight to override it
						if addon.ApplyFontStyle then
							addon.ApplyFontStyle(feedbackFS, customFace, customSize, customStyle)
						elseif feedbackFS.SetFont then
							pcall(feedbackFS.SetFont, feedbackFS, customFace, customSize, customStyle)
						end
					end
				end
			end
		end)
	end

	-- Hook CombatFeedback_OnUpdate to continuously keep alpha at 0 when disabled
	-- Critical because OnUpdate runs every frame and will override the alpha setting
	if _G.CombatFeedback_OnUpdate then
		_G.hooksecurefunc("CombatFeedback_OnUpdate", function(self, elapsed)
			-- Comparing a secret throws just like indexing one, so screen first
			self = SS.plainFrame(self)
			if not self then return end

			-- Dispatch: determine unit key and feedback FontString
			local unitKey, feedbackFS
			if self == _G.PlayerFrame then
				unitKey = "Player"
				feedbackFS = self.feedbackText
			elseif self == _G.PetFrame then
				unitKey = "Pet"
				feedbackFS = _G.PetHitIndicator
			else
				return
			end

			if feedbackFS then
				local db = addon and addon.db and addon.db.profile
				if db and db.unitFrames and db.unitFrames[unitKey] and db.unitFrames[unitKey].portrait then
					local damageTextDisabled = db.unitFrames[unitKey].portrait.damageTextDisabled == true
					if damageTextDisabled then
						-- Continuously force alpha to 0, overriding Blizzard's animation
						-- Runs after Blizzard's SetAlpha calls, so it will override them
						if feedbackFS.SetAlpha then
							pcall(feedbackFS.SetAlpha, feedbackFS, 0)
						end
					end
				end
			end
		end)
	end
	
	-- Also hook SetPortraitTexture as a fallback
	if _G.SetPortraitTexture then
		_G.hooksecurefunc("SetPortraitTexture", function(texture, unit)
			if issecretvalue(unit) then return end
			if unit and (unit == "player" or unit == "target" or unit == "focus" or unit == "pet" or unit == "targettarget") then
				local unitKey = nil
				if unit == "player" then unitKey = "Player"
				elseif unit == "target" then unitKey = "Target"
				elseif unit == "focus" then unitKey = "Focus"
				elseif unit == "pet" then unitKey = "Pet"
				elseif unit == "targettarget" then unitKey = "TargetOfTarget"
				end
				if unitKey then
					schedulePortraitApply(unitKey)
				end
			end
		end)
	end

	-- Keep the Player Frame status halo hidden when Scoot wants it hidden.
	local function EnforcePlayerStatusTextureVisibility()
		local db = addon and addon.db and addon.db.profile
		if not db then
			return
		end

		local ufCfg = db.unitFrames and db.unitFrames.Player
		if not ufCfg then
			return
		end

		local portraitCfg = ufCfg.portrait or {}
		local hidePortrait = portraitCfg.hidePortrait == true
		local hideStatusTexture = portraitCfg.hideStatusTexture == true
		local useCustomBorders = ufCfg.useCustomBorders == true

		if not (hidePortrait or hideStatusTexture or useCustomBorders) then
			-- Respect Blizzard visuals when no Scoot rule wants it hidden.
			return
		end

		local statusTexture = resolvePortraitStatusTextureFrame("Player")
		if not statusTexture then
			return
		end

		if statusTexture.SetAlpha then
			statusTexture:SetAlpha(0)
		end
		if statusTexture.Hide then
			statusTexture:Hide()
		end
	end

	if _G.PlayerFrame_UpdateStatus then
		_G.hooksecurefunc("PlayerFrame_UpdateStatus", EnforcePlayerStatusTextureVisibility)
	end
end

