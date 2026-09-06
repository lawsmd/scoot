--------------------------------------------------------------------------------
-- text/bossnames.lua
-- Name and level text styling, visibility, and name backdrops for the Boss
-- frames (Boss1..Boss5). The per-unit applier in text/names.lua dispatches
-- "Boss" here at call time; this file loads after it in the TOC.
--------------------------------------------------------------------------------

local addonName, addon = ...

local UFT = addon.UnitFrameText
local hasNameLevelConfig = UFT._HasNameLevelConfig
local applyNameBackdrop = UFT._ApplyNameBackdrop
local applyNameBackdropBorder = UFT._ApplyNameBackdropBorder

-- Reference to FrameState module for safe property storage (avoids writing to Blizzard frames)
local FS = addon.FrameState

local function getState(frame)
	return FS.Get(frame)
end

-- Secret-value safe helpers (shared module)
local SS = addon.SecretSafe
local safeOffset = SS.safeOffset
local safePointToken = SS.safePointToken
local safeGetWidth = SS.safeGetWidth

-- Font-half opts for the name/level texts
local nameTextFontOpts = { size = 14 }

--- Boss Frames: Apply Name & Level Text styling
do
	local function applyBossNameLevelText()
		if not addon:IsModuleEnabled("unitFrames", "Boss") then return end
		local db = addon and addon.db and addon.db.profile
		if not db then return end
		-- Zero‑Touch: do not create config tables. If Boss has no config, do nothing.
		local unitFrames = rawget(db, "unitFrames")
		local cfg = unitFrames and rawget(unitFrames, "Boss") or nil
		if not cfg then return end
		-- Zero‑Touch: only touch Name/Level/Backdrop when at least one relevant setting is explicitly set.
		if not hasNameLevelConfig(cfg) then return end

		-- Ensure a first application pass when the boss system becomes visible.
		-- Boss frames often become relevant only after the container shows (e.g., in instances),
		-- so the container is hooked once to trigger a reapply and install per-frame hooks.
		if _G and _G.hooksecurefunc then
			local container = _G.BossTargetFrameContainer
			local cState = getState(container)
			if container and cState and not cState.bossNameTextContainerHooked then
				cState.bossNameTextContainerHooked = true
				if type(container.OnShow) == "function" then
					_G.hooksecurefunc(container, "OnShow", function()
						-- IMPORTANT (taint): This hook executes inside Blizzard's boss-frame show/layout flow.
						-- Do not run styling synchronously here; defer to break the execution context chain.
						local function doApply()
							if InCombatLockdown and InCombatLockdown() then
								-- Boss frames show/hide during encounters; defer the heavy work until out of combat.
								addon._pendingApplyStyles = true
								return
							end
							if addon and addon.ApplyUnitFrameNameLevelTextFor then
								addon.ApplyUnitFrameNameLevelTextFor("Boss")
							end
						end
						if _G.C_Timer and _G.C_Timer.After then
							_G.C_Timer.After(0, doApply)
						else
							doApply()
						end
					end)
				end
			end
		end

		-- Apply to all five boss frames when any Boss name/backdrop setting is configured.
		-- Zero‑Touch remains intact because this block is only reached when cfg exists AND
		-- at least one relevant setting was explicitly set above.
		local resolveBossFrame = addon.GetBossFrame

		local resolveBossNameFS = addon.Frames.resolveBossNameFS
		local resolveBossLevelFS = addon.Frames.resolveBossLevelFS
		local resolveBossContentMain = addon.Frames.resolveBossContentMain

		local function resolveBossHealthBar(bossFrame)
			return addon.Frames.resolveHealthBar(bossFrame, "Boss")
		end

		-- Baselines for Boss name text are stored per-boss-index. Guard on every call:
		-- the style revert in base/core.lua nils this table out.
		local function ensureBossBaseline(fs, key, fallbackFrame)
			addon._ufNameLevelTextBaselines = addon._ufNameLevelTextBaselines or {}
			addon._ufNameLevelTextBaselines[key] = addon._ufNameLevelTextBaselines[key] or {}
			local b = addon._ufNameLevelTextBaselines[key]
			if b.point == nil then
				if fs and fs.GetPoint then
					local p, relTo, rp, x, y = fs:GetPoint(1)
					b.point = p or "CENTER"
					b.relTo = relTo or (fs.GetParent and fs:GetParent()) or fallbackFrame
					b.relPoint = rp or b.point
					b.x = safeOffset(x)
					b.y = safeOffset(y)
				else
					b.point, b.relTo, b.relPoint, b.x, b.y = "CENTER", (fallbackFrame or (fs and fs.GetParent and fs:GetParent())), "CENTER", 0, 0
				end
			end
			return b
		end

		local function applyBossTextStyle(fs, styleCfg, baselineKey, fallbackFrame)
			if not fs or not styleCfg then return end

			if not addon.HasTextCustomization(styleCfg) then return end

			addon.ApplyTextFont(fs, styleCfg, nameTextFontOpts)

			-- Kept off addon.ResolveColorRGBA: every mode renders the stored color, else the yellow; one line needs no resolver.
			-- Boss frames: no class color option, and every mode renders the
			-- stored color, else the Name/Level Text default yellow
			local c = styleCfg.color or { 1.0, 0.82, 0.0, 1 }
			if fs.SetTextColor then pcall(fs.SetTextColor, fs, c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1) end

			local ox = (styleCfg.offset and tonumber(styleCfg.offset.x)) or 0
			local oy = (styleCfg.offset and tonumber(styleCfg.offset.y)) or 0
			if fs.ClearAllPoints and fs.SetPoint then
				local b = ensureBossBaseline(fs, baselineKey, fallbackFrame)
				fs:ClearAllPoints()
				local point = safePointToken(b.point, "CENTER")
				local relTo = b.relTo or (fs.GetParent and fs:GetParent()) or fallbackFrame
				local relPoint = safePointToken(b.relPoint, point)
				local x = safeOffset(b.x) + ox
				local y = safeOffset(b.y) + oy
				local ok = pcall(fs.SetPoint, fs, point, relTo, relPoint, x, y)
				if not ok then
					local parent = (fs.GetParent and fs:GetParent()) or fallbackFrame
					pcall(fs.SetPoint, fs, point, parent, relPoint, 0, 0)
				end
			end
		end

		local function applyBossNameContainerWidth(nameFS, styleCfg, bossIndex)
			if not nameFS or not styleCfg then return end
			if styleCfg.containerWidthPct == nil then return end

			local pct = tonumber(styleCfg.containerWidthPct) or 100
			if pct < 80 then pct = 80 elseif pct > 500 then pct = 500 end

			local key = "Boss" .. tostring(bossIndex) .. ":nameContainer"
			local baseline = addon._ufNameContainerBaselines[key]
			if not baseline then
				baseline = { width = safeGetWidth(nameFS) or 90 }
				addon._ufNameContainerBaselines[key] = baseline
			end

			local baseWidth = baseline.width or 90
			local newWidth = math.floor((baseWidth * pct / 100) + 0.5)

			if nameFS.SetWidth then
				nameFS:SetWidth(pct == 100 and baseWidth or newWidth)
			end

			local alignment = styleCfg.alignment or "LEFT"
			if nameFS.SetJustifyH then pcall(nameFS.SetJustifyH, nameFS, alignment) end

			if nameFS.GetText and nameFS.SetText then
				local txt = nameFS:GetText()
				if txt then nameFS:SetText(""); nameFS:SetText(txt) end
			end
		end

		local function applyBossIndex(i)
			local bossFrame = resolveBossFrame(i)
			if not bossFrame then return end

			local nameFS = resolveBossNameFS(bossFrame)
			local main = resolveBossContentMain(bossFrame)
			local hb = resolveBossHealthBar(bossFrame)

			-- Visibility: name text is not a StatusBar child, so SetShown is safe.
			if nameFS and nameFS.SetShown and cfg.nameTextHidden ~= nil then
				pcall(nameFS.SetShown, nameFS, not cfg.nameTextHidden)
			end

			if nameFS then
				applyBossTextStyle(nameFS, cfg.textName or {}, "Boss" .. tostring(i) .. ":name", bossFrame)
				applyBossNameContainerWidth(nameFS, cfg.textName or {}, i)
			end

			-- Level text
			local levelFS = resolveBossLevelFS(bossFrame)
			if levelFS and levelFS.SetShown and cfg.levelTextHidden ~= nil then
				pcall(levelFS.SetShown, levelFS, not cfg.levelTextHidden)
			end
			if levelFS then
				applyBossTextStyle(levelFS, cfg.textLevel or {}, "Boss" .. tostring(i) .. ":level", bossFrame)
			end

			-- Backdrop + Border: attach to the same content main frame as Target/Focus.
			-- Boss frames align right; grow left from the portrait side. The
			-- width-abort returns are ignored: the border still runs after a
			-- backdrop width miss on Boss frames.
			if main then
				local key = "Boss" .. tostring(i)
				applyNameBackdrop(main, hb, cfg, key, true)
				applyNameBackdropBorder(main, hb, cfg, key, true)
			end

			-- Persistence hooks (Boss frames can refresh/overwrite text props).
			local bossState = getState(bossFrame)
			if _G.hooksecurefunc and bossState and not bossState.bossNameTextHooked then
				bossState.bossNameTextHooked = true
				local function safeReapply()
					-- Throttle per-frame to avoid rapid spam from Update/OnShow.
					if bossState.bossNameTextReapplyPending then return end
					bossState.bossNameTextReapplyPending = true
					if _G.C_Timer and _G.C_Timer.After then
						_G.C_Timer.After(0, function()
							bossState.bossNameTextReapplyPending = nil
							applyBossIndex(i)
						end)
					else
						bossState.bossNameTextReapplyPending = nil
						applyBossIndex(i)
					end
				end
				if type(bossFrame.Update) == "function" then
					_G.hooksecurefunc(bossFrame, "Update", safeReapply)
				end
				if type(bossFrame.OnShow) == "function" then
					_G.hooksecurefunc(bossFrame, "OnShow", safeReapply)
				end
			end
		end

		for i = 1, addon.NUM_BOSS_FRAMES do
			applyBossIndex(i)
		end
	end

	function addon.ApplyBossNameLevelText()
		applyBossNameLevelText()
	end
end
