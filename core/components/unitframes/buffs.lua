local addonName, addon = ...
local Util = addon.ComponentsUtil
local CleanupIconBorderAttachments = Util.CleanupIconBorderAttachments
local ClampOpacity = Util.ClampOpacity

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

local function isEditModeActive()
	if addon and addon.EditMode and addon.EditMode.IsEditModeActiveOrOpening then
		return addon.EditMode.IsEditModeActiveOrOpening()
	end
	local mgr = _G.EditModeManagerFrame
	return mgr and (mgr.editModeActive or (mgr.IsShown and mgr:IsShown()))
end

-- Unit Frames: Buffs & Debuffs positioning and sizing (Target/Focus)
do
	-- Store original positions per aura frame so offsets remain relative to stock layout
	local originalAuraPositions = {}

	local function resolveUnitFrame(unit)
		local mgr = _G.EditModeManagerFrame
		local EM = _G.Enum and _G.Enum.EditModeUnitFrameSystemIndices
		local EMSys = _G.Enum and _G.Enum.EditModeSystem
		if mgr and EM and EMSys and mgr.GetRegisteredSystemFrame then
			local idx = (unit == "Target" and EM.Target) or (unit == "Focus" and EM.Focus) or nil
			if idx then
				local frame = mgr:GetRegisteredSystemFrame(EMSys.UnitFrame, idx)
				if frame then
					return frame
				end
			end
		end
		-- Fallback to global frames if Edit Mode lookup is unavailable
		if unit == "Target" then
			return _G.TargetFrame
		elseif unit == "Focus" then
			return _G.FocusFrame
		end
	end

	-- Internal implementation that accepts a visualOnly flag for combat-safe styling
	local function applyBuffsDebuffsForUnitInternal(unit, visualOnly)
		if unit ~= "Target" and unit ~= "Focus" then return end

		local db = addon and addon.db and addon.db.profile
		if not db then return end

		db.unitFrames = db.unitFrames or {}
		db.unitFrames[unit] = db.unitFrames[unit] or {}
		db.unitFrames[unit].buffsDebuffs = db.unitFrames[unit].buffsDebuffs or {}
		local cfg = db.unitFrames[unit].buffsDebuffs

		local frame = resolveUnitFrame(unit)
		if not frame then return end

		local offsetX = tonumber(cfg.offsetX) or 0
		local offsetY = tonumber(cfg.offsetY) or 0
		local scalePct = tonumber(cfg.iconScale) or 100
		if scalePct < 20 then scalePct = 20 elseif scalePct > 200 then scalePct = 200 end
		local scaleMultiplier = scalePct / 100.0
		local hideBuffsDebuffs = cfg.hideBuffsDebuffs == true

		-- Helper: hide or show all aura frames in a pool
		-- SAFE during combat: SetAlpha and EnableMouse are cosmetic operations
		local function setPoolVisibility(pool, hidden)
			if not pool or not pool.EnumerateActive then return end
			for auraFrame in pool:EnumerateActive() do
				if auraFrame then
					if hidden then
						auraFrame:SetAlpha(0)
						if auraFrame.EnableMouse then auraFrame:EnableMouse(false) end
					else
						auraFrame:SetAlpha(1)
						if auraFrame.EnableMouse then auraFrame:EnableMouse(true) end
					end
				end
			end
		end

		-- Apply visibility to all active aura frames in the pools
		-- SAFE during combat
		local auraPools = frame.auraPools
		if auraPools and auraPools.GetPool then
			local buffPool = auraPools:GetPool("TargetBuffFrameTemplate")
			local debuffPool = auraPools:GetPool("TargetDebuffFrameTemplate")
			setPoolVisibility(buffPool, hideBuffsDebuffs)
			setPoolVisibility(debuffPool, hideBuffsDebuffs)
		end

		-- If hidden, skip all the detailed styling work (positioning, sizing, borders)
		if hideBuffsDebuffs then
			return
		end

		-- Calculate icon dimensions from ratio if set
		local ratio = tonumber(cfg.tallWideRatio) or 0
		local ratioWidth, ratioHeight
		if ratio ~= 0 and addon.IconRatio then
			-- Use component ID based on unit for base size lookup
			local componentId = (unit == "Target") and "targetBuffsDebuffs" or "focusBuffsDebuffs"
			ratioWidth, ratioHeight = addon.IconRatio.GetDimensionsForComponent(componentId, ratio)
		end

		-- Apply visual styling to all auras in a pool
		-- SAFE during combat: SetScale and border styling are cosmetic operations
		local function applyToPool(pool)
			if not pool or not pool.EnumerateActive then return end

			for auraFrame in pool:EnumerateActive() do
				-- Apply uniform scale to shrink/grow icons without fighting
				-- Blizzard's internal aura-row math. This affects the visual size
				-- while leaving the logical layout width/height unchanged.
				-- Let Blizzard determine the base icon size; only multiplied by scale.
				-- iconScale=100 means 1.0x (Blizzard default), 50 means 0.5x, 200 means 2.0x.
				if auraFrame and auraFrame.SetScale then
					auraFrame:SetScale(scaleMultiplier)

					-- Apply ratio-based sizing if configured
					local icon = auraFrame.Icon
					if icon and ratioWidth and ratioHeight then
						-- Resize the auraFrame itself (the icon is anchored to fill it)
						if auraFrame.SetSize then
							auraFrame:SetSize(ratioWidth, ratioHeight)
						end
						-- Calculate texture coordinates to crop instead of stretch
						local aspectRatio = ratioWidth / ratioHeight
						local left, right, top, bottom = 0, 1, 0, 1
						if aspectRatio > 1.0 then
							-- Wider than tall - crop top/bottom
							local cropAmount = 1.0 - (1.0 / aspectRatio)
							local cropOffset = cropAmount / 2.0
							top = cropOffset
							bottom = 1.0 - cropOffset
						elseif aspectRatio < 1.0 then
							-- Taller than wide - crop left/right
							local cropAmount = 1.0 - aspectRatio
							local cropOffset = cropAmount / 2.0
							left = cropOffset
							right = 1.0 - cropOffset
						end
						if icon.SetTexCoord then
							pcall(icon.SetTexCoord, icon, left, right, top, bottom)
						end
					elseif icon and icon.SetTexCoord then
						-- Reset to default coords if no ratio
						pcall(icon.SetTexCoord, icon, 0, 1, 0, 1)
					end

					-- Custom icon border styling (Essential Cooldowns-style) when enabled
					local blizzBorder = auraFrame.Border
					if icon then
						if cfg.borderEnable then
							-- Hide Blizzard's default debuff border so it doesn't compete visually
							if blizzBorder and blizzBorder.Hide then
								blizzBorder:Hide()
							elseif blizzBorder and blizzBorder.SetAlpha then
								blizzBorder:SetAlpha(0)
							end

							local styleKey = cfg.borderStyle or "square"
							local thickness = tonumber(cfg.borderThickness) or 1
							if thickness < 1 then thickness = 1 elseif thickness > 16 then thickness = 16 end
							local tintEnabled = cfg.borderTintEnable and type(cfg.borderTintColor) == "table"
							local tintColor
							if tintEnabled then
								local c = cfg.borderTintColor or {1,1,1,1}
								tintColor = { c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 }
							end

							-- Hard reset any existing Scoot borders on this icon and its wrapper
							-- before applying a new style to avoid any chance of layered leftovers.
							if addon.Borders and addon.Borders.HideAll then
								addon.Borders.HideAll(icon)
								local iconState = getState(icon)
								local container = iconState and iconState.ScootIconBorderContainer
								if container then
									addon.Borders.HideAll(container)
								end
							end

							if addon.ApplyIconBorderStyle then
								addon.ApplyIconBorderStyle(icon, styleKey, {
									thickness = thickness,
									color = tintEnabled and tintColor or nil,
									tintEnabled = tintEnabled,
									db = cfg,
									thicknessKey = "borderThickness",
									tintColorKey = "borderTintColor",
									defaultThickness = 1,
								})
							end
							-- Explicitly resize the border container to match icon dimensions
							-- (SetPoint anchoring to Textures doesn't always propagate size changes)
							if ratioWidth and ratioHeight then
								local iconState = getState(icon)
								local container = iconState and iconState.ScootIconBorderContainer
								if container and container.SetSize then
									container:SetSize(ratioWidth, ratioHeight)
								end
							end
						else
							-- Restore Blizzard's default border and hide any custom border textures
							if addon.Borders and addon.Borders.HideAll then
								addon.Borders.HideAll(icon)
								-- Also clear any borders attached to the icon's wrapper container created
								-- by ApplyIconBorderStyle when the icon is a Texture.
								local iconState = getState(icon)
								local container = iconState and iconState.ScootIconBorderContainer
								if container then
									addon.Borders.HideAll(container)
								end
							end
							if blizzBorder then
								if blizzBorder.Show then
									blizzBorder:Show()
								elseif blizzBorder.SetAlpha then
									blizzBorder:SetAlpha(1)
								end
							end
						end
					end
				end
			end
		end

		-- Use Blizzard's aura pools to get the active Buff/Debuff frames.
		-- Target/Focus both inherit TargetFrameTemplate, which creates pools
		-- for "TargetBuffFrameTemplate" and "TargetDebuffFrameTemplate".
		-- SAFE during combat: all operations in applyToPool are cosmetic
		local auraPools2 = frame.auraPools
		if auraPools2 and auraPools2.GetPool then
			local buffPool = auraPools2:GetPool("TargetBuffFrameTemplate")
			local debuffPool = auraPools2:GetPool("TargetDebuffFrameTemplate")
			applyToPool(buffPool)
			applyToPool(debuffPool)
		end

		-- Positioning: nudge the shared Buffs/Debuffs containers so rows stay intact
		-- and all auras move together, regardless of row/column indexing.
		-- UNSAFE during combat: ClearAllPoints/SetPoint on containers may cause issues
		-- Skip positioning when visualOnly is true (combat + hook path)
		if not visualOnly then
			local inCombat = InCombatLockdown and InCombatLockdown()
			if inCombat then
				-- Defer positioning to after combat ends
				if _G.C_Timer and _G.C_Timer.After then
					local u = unit
					_G.C_Timer.After(0.1, function()
						if not (InCombatLockdown and InCombatLockdown()) then
							-- Re-run with visualOnly=false to apply positioning
							applyBuffsDebuffsForUnitInternal(u, false)
						end
					end)
				end
			else
				-- Out of combat: apply positioning
				local contextual = frame.TargetFrameContent and frame.TargetFrameContent.TargetFrameContentContextual
				if contextual then
					local containers = { contextual.buffs, contextual.debuffs }
					for _, holder in ipairs(containers) do
						if holder and holder.GetPoint then
							if not originalAuraPositions[holder] then
								local p, relTo, relPoint, xOfs, yOfs = holder:GetPoint(1)
								if p then
									originalAuraPositions[holder] = {
										point = p,
										relativeTo = relTo,
										relativePoint = relPoint,
										xOfs = xOfs or 0,
										yOfs = yOfs or 0,
									}
								end
							end
							local orig = originalAuraPositions[holder]
							if orig then
								holder:ClearAllPoints()
								holder:SetPoint(
									orig.point or "CENTER",
									orig.relativeTo,
									orig.relativePoint or orig.point or "CENTER",
									(orig.xOfs or 0) + offsetX,
									(orig.yOfs or 0) + offsetY
								)
							end
						end
					end
				end
			end
		end
	end

	-- Public wrapper: called from settings changes and ApplyStyles
	-- When not in combat, runs full styling. When in combat from a hook, uses visualOnly.
	local function applyBuffsDebuffsForUnit(unit)
		-- Check if this call is from a combat hook (visual-only path)
		local frame = resolveUnitFrame(unit)
		local frameState = getState(frame)
		local visualOnly = frameState and frameState.buffsDebuffsVisualOnly
		applyBuffsDebuffsForUnitInternal(unit, visualOnly)
	end

	function addon.ApplyUnitFrameBuffsDebuffsFor(unit)
		applyBuffsDebuffsForUnit(unit)
	end

	function addon.ApplyAllUnitFrameBuffsDebuffs()
		applyBuffsDebuffsForUnit("Target")
		applyBuffsDebuffsForUnit("Focus")
	end

	-- Hook aura updates so Scoot re-applies styling after Blizzard layouts.
	-- During combat, visualOnly mode applies cosmetic styling (borders, sizing)
	-- while deferring layout operations (container positioning) until combat ends.
	if _G.TargetFrame and _G.TargetFrame.UpdateAuras and _G.hooksecurefunc then
		_G.hooksecurefunc(_G.TargetFrame, "UpdateAuras", function(self)
			if isEditModeActive() then return end
			if addon and addon.ApplyUnitFrameBuffsDebuffsFor then
				local inCombat = InCombatLockdown and InCombatLockdown()
				-- Set visual-only flag when in combat so styling skips layout operations
				local st = getState(self)
				if st then st.buffsDebuffsVisualOnly = inCombat end
				addon.ApplyUnitFrameBuffsDebuffsFor("Target")
				if st then st.buffsDebuffsVisualOnly = nil end
			end
		end)
	end
	if _G.FocusFrame and _G.FocusFrame.UpdateAuras and _G.hooksecurefunc then
		_G.hooksecurefunc(_G.FocusFrame, "UpdateAuras", function(self)
			if isEditModeActive() then return end
			if addon and addon.ApplyUnitFrameBuffsDebuffsFor then
				local inCombat = InCombatLockdown and InCombatLockdown()
				-- Set visual-only flag when in combat so styling skips layout operations
				local st = getState(self)
				if st then st.buffsDebuffsVisualOnly = inCombat end
				addon.ApplyUnitFrameBuffsDebuffsFor("Focus")
				if st then st.buffsDebuffsVisualOnly = nil end
			end
		end)
	end
end
