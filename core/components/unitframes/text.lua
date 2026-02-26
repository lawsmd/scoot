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

-- Secret-value safe helpers (shared module)
local SS = addon.SecretSafe
local safeOffset = SS.safeOffset
local safePointToken = SS.safePointToken
local safeGetWidth = SS.safeGetWidth

-- Helper to get a usable width for FontString alignment.
-- StatusBars return nil from safeGetWidth (to avoid secret value issues), so it needs
-- alternative strategies: try the FontString itself, try the grandparent (which is
-- typically NOT a StatusBar), or fall back to a reasonable default.
local function getBarWidthForAlignment(fs)
    if not fs then return 120 end

    -- Check if this FontString is part of a unit frame hierarchy FIRST.
    -- If so, avoid ALL GetWidth calls as they can trigger internal updates
    -- (like heal prediction) that fail on secret values.
    local parent = fs.GetParent and fs:GetParent()
    if parent then
        local grandparent = parent.GetParent and parent:GetParent()
        if grandparent and (grandparent.unit or grandparent.healthbar) then
            -- Part of a unit frame hierarchy - use safe fallback immediately
            return 120
        end
    end

    -- Not part of a unit frame - safe to try GetWidth calls
    -- Try FontString's own width first (if it was already sized)
    local fsWidth = safeGetWidth(fs)
    if fsWidth and fsWidth > 10 then
        return fsWidth
    end

    -- Try parent's parent if it's a simple container
    if parent then
        local grandparent = parent.GetParent and parent:GetParent()
        if grandparent then
            local gpWidth = safeGetWidth(grandparent)
            if gpWidth and gpWidth > 10 then
                return gpWidth
            end
        end
    end

    -- Fallback: use a known reasonable width for unit frame bars
    return 120
end

local function isEditModeActive()
	if addon and addon.EditMode and addon.EditMode.IsEditModeActiveOrOpening then
		return addon.EditMode.IsEditModeActiveOrOpening()
	end
	local mgr = _G.EditModeManagerFrame
	return mgr and (mgr.editModeActive or (mgr.IsShown and mgr:IsShown()))
end

-- Unit Frames: Toggle Health % (LeftText) and Value (RightText) visibility per unit
do
    -- Cache for resolved health text fontstrings per unit so combat-time hooks stay cheap.
    addon._ufHealthTextFonts = addon._ufHealthTextFonts or {}

    local function getUnitFrameFor(unit)
        local mgr = _G.EditModeManagerFrame
		local EM = _G.Enum and _G.Enum.EditModeUnitFrameSystemIndices
		local EMSys = _G.Enum and _G.Enum.EditModeSystem
		if not (mgr and EMSys and mgr.GetRegisteredSystemFrame) then
			-- Fallback for environments where Edit Mode indices aren't available
			if unit == "Pet" then return _G.PetFrame end
			return nil
		end
		local idx = nil
		if EM then
			idx = (unit == "Player" and EM.Player)
				or (unit == "Target" and EM.Target)
				or (unit == "Focus" and EM.Focus)
				or (unit == "Pet" and EM.Pet)
		end
		if idx then
			return mgr:GetRegisteredSystemFrame(EMSys.UnitFrame, idx)
		end
		-- If no index was resolved (older builds lacking EM.Pet), try known globals
		if unit == "Pet" then return _G.PetFrame end
    end

    local function findFontStringByNameHint(root, hint)
        if not root then return nil end
        local target
        local function scan(obj)
            if not obj or target then return end
            if obj.GetObjectType and obj:GetObjectType() == "FontString" then
                local nm = obj.GetName and obj:GetName() or (obj.GetDebugName and obj:GetDebugName()) or ""
                if type(nm) == "string" and string.find(string.lower(nm), string.lower(hint), 1, true) then
                    target = obj; return
                end
            end
            if obj.GetRegions then
                local n = (obj.GetNumRegions and obj:GetNumRegions(obj)) or 0
                for i = 1, n do
                    local r = select(i, obj:GetRegions())
                    if r and r.GetObjectType and r:GetObjectType() == "FontString" then
                        local nm = r.GetName and r:GetName() or (r.GetDebugName and r:GetDebugName()) or ""
                        if type(nm) == "string" and string.find(string.lower(nm), string.lower(hint), 1, true) then
                            target = r; return
                        end
                    end
                end
            end
            if obj.GetChildren then
                local m = (obj.GetNumChildren and obj:GetNumChildren()) or 0
                for i = 1, m do
                    local c = select(i, obj:GetChildren())
                    scan(c)
                    if target then return end
                end
            end
        end
        scan(root)
        return target
    end

    -- Resolve health bar for this unit
    local function resolveHealthBarForVisibility(frame, unit)
        if unit == "Pet" then return _G.PetFrameHealthBar end
        if frame and frame.HealthBarsContainer and frame.HealthBarsContainer.HealthBar then
            return frame.HealthBarsContainer.HealthBar
        end
        -- Try direct paths
        if unit == "Player" then
            local root = _G.PlayerFrame
            if root and root.PlayerFrameContent and root.PlayerFrameContent.PlayerFrameContentMain
                and root.PlayerFrameContent.PlayerFrameContentMain.HealthBarsContainer
                and root.PlayerFrameContent.PlayerFrameContentMain.HealthBarsContainer.HealthBar then
                return root.PlayerFrameContent.PlayerFrameContentMain.HealthBarsContainer.HealthBar
            end
        elseif unit == "Target" then
            local root = _G.TargetFrame
            if root and root.TargetFrameContent and root.TargetFrameContent.TargetFrameContentMain
                and root.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer
                and root.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer.HealthBar then
                return root.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer.HealthBar
            end
        elseif unit == "Focus" then
            local root = _G.FocusFrame
            if root and root.TargetFrameContent and root.TargetFrameContent.TargetFrameContentMain
                and root.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer
                and root.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer.HealthBar then
                return root.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer.HealthBar
            end
        end
    end

    -- Helper: determine whether the current player can ever have an Alternate Power Bar.
    -- Intentionally keyed off spec IDs where possible so the check is cheap and future‑proof.
    --
    -- IMPORTANT (Druid nuance):
    -- Some classes (notably DRUID) can surface the global AlternatePowerBar based on form/talents
    -- even when the player's active spec is not the "typical" spec for that resource.
    -- Example: Restoration Druid can talent into Moonkin Form, causing Astral Power to become the
    -- main bar and mana to appear on the AlternatePowerBar.
    --
    -- Because the Settings UI should allow pre-configuration, DRUID is treated as class-capable.
    -- Specs covered (per user guidance):
    --   - Balance Druid      (specID = 102, class = DRUID)
    --   - Shadow Priest      (specID = 258, class = PRIEST)
    --   - Brewmaster Monk    (specID = 268, class = MONK)
    --   - Elemental Shaman   (specID = 262, class = SHAMAN)
    local function playerHasAlternatePowerBar()
        if not UnitClass or not GetSpecialization or not GetSpecializationInfo then
            return false
        end
        local _, classToken = UnitClass("player")
        if not classToken then
            return false
        end

        -- Class-capable fast-paths (form/talent driven; not reliably spec-gated).
        if classToken == "DRUID" then
            return true
        end

        local specIndex = GetSpecialization()
        if not specIndex then
            return false
        end
        local specID = select(1, GetSpecializationInfo(specIndex))
        if not specID then
            return false
        end

        -- Map of class -> set of specIDs that use the global AlternatePowerBar.
        local altSpecsByClass = {
            PRIEST = { [258] = true },  -- Shadow
            MONK   = { [268] = true },  -- Brewmaster
            SHAMAN = { [262] = true },  -- Elemental
        }

        local classSpecs = altSpecsByClass[classToken]
        return classSpecs and classSpecs[specID] or false
    end

    -- Expose for UI modules (builders.lua) to gate the Alternate Power Bar section.
    addon.UnitFrames_PlayerHasAlternatePowerBar = playerHasAlternatePowerBar

    -- Hook UpdateTextString to reapply visibility after Blizzard's updates.
    -- IMPORTANT: Use hooksecurefunc to avoid replacing the method and taint
    -- secure StatusBar instances used by Blizzard (Combat Log, unit frames, etc.).
    local function hookHealthBarUpdateTextString(bar, unit)
        local fs = ensureFS()
        if not bar or not fs then return end
        if fs.IsHooked(bar, "healthBarUpdateTextString") then return end
        fs.MarkHooked(bar, "healthBarUpdateTextString")
        if _G.hooksecurefunc then
            _G.hooksecurefunc(bar, "UpdateTextString", function(self, ...)
                if addon and addon.ApplyUnitFrameHealthTextVisibilityFor then
                    addon.ApplyUnitFrameHealthTextVisibilityFor(unit)
                end
            end)
        end
    end

    -- NOTE: SetFont/SetFontObject hooks removed for performance reasons.
    -- Font persistence during Character Pane opening is handled by the Character Frame hook section.
    -- Font persistence during instance loading can be handled via PLAYER_ENTERING_WORLD if needed.
    -- The previous hooks called ApplyAll* functions on every font change which was too expensive.
    local function hookHealthTextFontReset(fs, unit, textType)
        -- No-op: hooks removed for performance
    end

    -- Shared text styling helpers (used by Player/Target/Focus/Pet AND Boss frames).
    -- Keep these outside applyForUnit so Boss can reuse the exact same styling logic.
    addon._ufTextBaselines = addon._ufTextBaselines or {}

    local function ensureBaseline(fs, key, fallbackFrame)
        addon._ufTextBaselines[key] = addon._ufTextBaselines[key] or {}
        local b = addon._ufTextBaselines[key]
        if b.point == nil then
            if fs and fs.GetPoint then
                local p, relTo, rp, x, y = fs:GetPoint(1)
                b.point = p or "CENTER"
                b.relTo = relTo or (fs.GetParent and fs:GetParent()) or fallbackFrame
                b.relPoint = rp or b.point
                b.x = safeOffset(x)
                b.y = safeOffset(y)
            else
                b.point, b.relTo, b.relPoint, b.x, b.y = "CENTER", (fs and fs.GetParent and fs:GetParent()) or fallbackFrame, "CENTER", 0, 0
            end
        end
        return b
    end

    -- Helper to force FontString redraw after alignment change (secret-value safe)
    local function forceTextRedraw(fs)
        if fs and fs.GetText and fs.SetText then
            local ok, txt = pcall(fs.GetText, fs)
            if ok and txt and type(txt) == "string" then
                fs:SetText("")
                fs:SetText(txt)
            else
                -- Fallback: toggle alpha to force redraw without needing text value
                local okAlpha, alpha = pcall(function() return fs.GetAlpha and fs:GetAlpha() end)
                if okAlpha and alpha then
                    pcall(fs.SetAlpha, fs, 0)
                    pcall(fs.SetAlpha, fs, alpha)
                end
            end
        end
    end

    -- Default/clean profiles should not modify Blizzard text.
    -- Only treat settings as "customized" if they differ from structural defaults.
    local function hasTextCustomization(styleCfg)
        if not styleCfg then return false end
        if styleCfg.fontFace ~= nil and styleCfg.fontFace ~= "" and styleCfg.fontFace ~= "FRIZQT__" then
            return true
        end
        if styleCfg.size ~= nil or styleCfg.style ~= nil or styleCfg.color ~= nil or styleCfg.alignment ~= nil then
            return true
        end
        if styleCfg.colorMode ~= nil and styleCfg.colorMode ~= "default" then
            return true
        end
        if styleCfg.offset and (styleCfg.offset.x ~= nil or styleCfg.offset.y ~= nil) then
            local ox = tonumber(styleCfg.offset.x) or 0
            local oy = tonumber(styleCfg.offset.y) or 0
            if ox ~= 0 or oy ~= 0 then
                return true
            end
        end
        return false
    end

    -- Targeted zero-touch check for DeadText/UnconsciousText: only fontFace and style matter
    -- (color, alignment, offset are irrelevant — we preserve Blizzard's original values)
    local function hasFontFaceOrStyle(styleCfg)
        if not styleCfg then return false end
        if styleCfg.fontFace ~= nil and styleCfg.fontFace ~= "" and styleCfg.fontFace ~= "FRIZQT__" then
            return true
        end
        if styleCfg.style ~= nil then
            return true
        end
        return false
    end

    -- Apply font face and outline style to DeadText/UnconsciousText FontStrings,
    -- inheriting from the user's Health Bar > Value Text settings.
    -- Preserves Blizzard's original size and color.
    local function applyDeadTextFontInheritance(fs, styleCfg)
        if not fs or not styleCfg then return end
        if not hasFontFaceOrStyle(styleCfg) then return end

        -- Read current font size to preserve it
        local ok, currentFont, currentSize, currentFlags = pcall(fs.GetFont, fs)
        if not ok or type(currentSize) ~= "number" then return end

        local face = addon.ResolveFontFace and addon.ResolveFontFace(styleCfg.fontFace or "FRIZQT__")
            or currentFont
        local outline = styleCfg.style ~= nil and tostring(styleCfg.style) or (currentFlags or "")

        local fstate = ensureFS()
        if fstate then fstate.SetProp(fs, "applyingFont", true) end
        if addon.ApplyFontStyle then
            addon.ApplyFontStyle(fs, face, currentSize, outline)
        elseif fs.SetFont then
            pcall(fs.SetFont, fs, face, currentSize, outline)
        end
        if fstate then fstate.SetProp(fs, "applyingFont", nil) end
    end

    -- Hook Show() on DeadText/UnconsciousText so font inheritance reapplies
    -- each time Blizzard's CheckDead() displays the text.
    local function hookDeadTextShow(fs, unit)
        if not fs then return end
        local fstate = ensureFS()
        if not fstate then return end
        if fstate.IsHooked(fs, "deadTextFontShow") then return end
        fstate.MarkHooked(fs, "deadTextFontShow")

        if _G.hooksecurefunc then
            _G.hooksecurefunc(fs, "Show", function(self)
                if isEditModeActive() then return end
                local db = addon and addon.db and addon.db.profile
                if not db then return end
                local unitFrames = rawget(db, "unitFrames")
                local cfg = unitFrames and rawget(unitFrames, unit) or nil
                if not cfg then return end
                applyDeadTextFontInheritance(self, cfg.textHealthValue or {})
            end)
        end
    end

    local function applyTextStyle(fs, styleCfg, baselineKey, fallbackFrame)
        if not fs or not styleCfg then return end
        if not hasTextCustomization(styleCfg) then
            return
        end

        local face = addon.ResolveFontFace and addon.ResolveFontFace(styleCfg.fontFace or "FRIZQT__") or (select(1, _G.GameFontNormal:GetFont()))
        local size = tonumber(styleCfg.size) or 14
        local outline = tostring(styleCfg.style or "OUTLINE")

        -- Set flag to prevent the SetFont hook from triggering a reapply loop
        local fstate = ensureFS()
        if fstate then fstate.SetProp(fs, "applyingFont", true) end
        if addon.ApplyFontStyle then
            addon.ApplyFontStyle(fs, face, size, outline)
        elseif fs.SetFont then
            pcall(fs.SetFont, fs, face, size, outline)
        end
        if fstate then fstate.SetProp(fs, "applyingFont", nil) end

        -- Resolve color based on colorMode
        local colorMode = styleCfg.colorMode or "default"
        local c
        if colorMode == "class" then
            -- Extract unit token from baselineKey (e.g., "Player:left" → "player")
            local unitToken = baselineKey and baselineKey:match("^(.-):")
            if unitToken then unitToken = unitToken:lower() end
            local cr, cg, cb = addon.GetClassColorRGB(unitToken or "player")
            c = {cr or 1, cg or 1, cb or 1, 1}
        elseif colorMode == "custom" then
            c = styleCfg.color or {1, 1, 1, 1}
        else
            -- "default" or nil: backward compat - use custom color if non-white, else white
            local raw = styleCfg.color
            if raw and (raw[1] ~= 1 or raw[2] ~= 1 or raw[3] ~= 1 or (raw[4] or 1) ~= 1) then
                c = raw
            else
                c = {1, 1, 1, 1}
            end
        end
        if fs.SetTextColor then
            pcall(fs.SetTextColor, fs, c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
        end

        -- Only modify width/alignment/position if alignment or offset is explicitly configured.
        -- This prevents Apply All Fonts (which only sets fontFace) from inadvertently changing
        -- text positioning. Width/alignment changes are only appropriate when the user has
        -- explicitly configured layout-related settings.
        local hasLayoutCustomization = styleCfg.alignment ~= nil
            or (styleCfg.offset and (styleCfg.offset.x ~= nil or styleCfg.offset.y ~= nil))

        if hasLayoutCustomization then
            -- Determine default alignment based on text role
            -- Check for both :right and -right patterns to handle all unit types (Player:right, Boss1:health-right, etc.)
            local defaultAlign = "LEFT"
            if baselineKey and (baselineKey:find(":right", 1, true) or baselineKey:find("-right", 1, true)) then
                defaultAlign = "RIGHT"
            elseif baselineKey and (baselineKey:find(":center", 1, true) or baselineKey:find("-center", 1, true)) then
                defaultAlign = "CENTER"
            end
            local alignment = styleCfg.alignment or defaultAlign

            local parentBar = fs.GetParent and fs:GetParent()

            -- Get baseline Y position and user offsets
            local b = ensureBaseline(fs, baselineKey, fallbackFrame or parentBar)
            local ox = (styleCfg.offset and tonumber(styleCfg.offset.x)) or 0
            local oy = (styleCfg.offset and tonumber(styleCfg.offset.y)) or 0
            local yOffset = safeOffset(b.y) + oy

            -- Use two-point anchoring to span the parent bar width.
            -- This makes JustifyH work correctly without needing GetWidth() (which can
            -- trigger secret value errors on unit frame StatusBars).
            if fs.ClearAllPoints and fs.SetPoint and parentBar then
                fs:ClearAllPoints()
                -- Anchor both left and right edges to span the bar
                -- Apply small padding (2px) plus user X offset for text inset
                local leftPad = 2 + ox
                local rightPad = -2 + ox
                pcall(fs.SetPoint, fs, "LEFT", parentBar, "LEFT", leftPad, yOffset)
                pcall(fs.SetPoint, fs, "RIGHT", parentBar, "RIGHT", rightPad, yOffset)
            end

            if fs.SetJustifyH then
                pcall(fs.SetJustifyH, fs, alignment)
            end

            -- Force redraw to apply alignment visually
            forceTextRedraw(fs)
        end
    end

    local function applyForUnit(unit)
        local db = addon and addon.db and addon.db.profile
        if not db then return end
        -- Zero‑Touch: do not create config tables. If this unit has no config, do nothing.
        local unitFrames = rawget(db, "unitFrames")
        local cfg = unitFrames and rawget(unitFrames, unit) or nil
        if not cfg then
            return
        end
        local frame = getUnitFrameFor(unit)
        if not frame then return end
        
        -- Resolve health bar and hook its UpdateTextString if not already hooked
        local hb = resolveHealthBarForVisibility(frame, unit)
        if hb then
            hookHealthBarUpdateTextString(hb, unit)
        end
        
		local leftFS
		local rightFS
		if unit == "Pet" then
			leftFS = _G.PetFrameHealthBarTextLeft or (frame.HealthBarsContainer and frame.HealthBarsContainer.LeftText)
			rightFS = _G.PetFrameHealthBarTextRight or (frame.HealthBarsContainer and frame.HealthBarsContainer.RightText)
		end
        -- Full resolution path (may scan children/regions). This should only run during
        -- explicit styling passes (ApplyStyles), not on every health text update.
		leftFS = leftFS
            or (frame.HealthBarsContainer and frame.HealthBarsContainer.LeftText)
            or findFontStringByNameHint(frame, "HealthBarsContainer.LeftText")
            or findFontStringByNameHint(frame, ".LeftText")
            or findFontStringByNameHint(frame, "HealthBarTextLeft")
		rightFS = rightFS
            or (frame.HealthBarsContainer and frame.HealthBarsContainer.RightText)
            or findFontStringByNameHint(frame, "HealthBarsContainer.RightText")
            or findFontStringByNameHint(frame, ".RightText")
            or findFontStringByNameHint(frame, "HealthBarTextRight")

        -- Also resolve the center TextString (used in NUMERIC display mode and Character Pane)
        -- This ensures styling persists when Blizzard switches between BOTH and NUMERIC modes
        -- Character Pane shows HealthBarText instead of LeftText/RightText
        local textStringFS
        if unit == "Pet" then
            textStringFS = _G.PetFrameHealthBarText
        elseif unit == "Player" then
            local root = _G.PlayerFrame
            textStringFS = root and root.PlayerFrameContent 
                and root.PlayerFrameContent.PlayerFrameContentMain 
                and root.PlayerFrameContent.PlayerFrameContentMain.HealthBarsContainer 
                and root.PlayerFrameContent.PlayerFrameContentMain.HealthBarsContainer.HealthBarText
        elseif unit == "Target" then
            local root = _G.TargetFrame
            textStringFS = root and root.TargetFrameContent 
                and root.TargetFrameContent.TargetFrameContentMain 
                and root.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer 
                and root.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer.HealthBarText
        elseif unit == "Focus" then
            local root = _G.FocusFrame
            textStringFS = root and root.TargetFrameContent 
                and root.TargetFrameContent.TargetFrameContentMain 
                and root.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer 
                and root.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer.HealthBarText
        end

        -- Cache resolved fontstrings so combat-time hooks can avoid expensive scans.
        addon._ufHealthTextFonts[unit] = {
            leftFS = leftFS,
            rightFS = rightFS,
            textStringFS = textStringFS,
        }

        -- Install font reset hooks to reapply styling when Blizzard calls SetFontObject
        hookHealthTextFontReset(leftFS, unit, "left")
        hookHealthTextFontReset(rightFS, unit, "right")
        hookHealthTextFontReset(textStringFS, unit, "center")

        -- Helper: Apply visibility using SetAlpha (combat-safe) instead of SetShown (taint-prone).
        -- Hooks Show(), SetAlpha(), and SetText() to re-enforce alpha=0 AND font styling when Blizzard updates.
        -- Tri‑state: nil means "don't touch"; true=hide; false=show (restore).
        -- NOTE: Uses FrameState to avoid writing properties directly to Blizzard frames (causes taint).
        local function applyHealthTextVisibility(fs, hiddenSetting, unitForHook)
            if not fs then return end
            local fstate = ensureFS()
            if not fstate then return end
            if hiddenSetting == nil then
                return
            end
            local hidden = (hiddenSetting == true)
            if hidden then
                if fs.SetAlpha then pcall(fs.SetAlpha, fs, 0) end
                -- Install hooks once to re-enforce alpha when Blizzard calls Show(), SetAlpha(), or SetText()
                if not fstate.IsHooked(fs, "healthTextVisibility") then
                    fstate.MarkHooked(fs, "healthTextVisibility")
                    if _G.hooksecurefunc then
                        -- Hook Show() to re-enforce alpha=0
                        _G.hooksecurefunc(fs, "Show", function(self)
                            if isEditModeActive() then return end
                            local st = ensureFS()
                            if st and st.IsHidden(self, "healthText") and self.SetAlpha then
                                pcall(self.SetAlpha, self, 0)
                            end
                        end)
                        -- Hook SetAlpha() to re-enforce alpha=0 when Blizzard tries to make it visible
                        _G.hooksecurefunc(fs, "SetAlpha", function(self, alpha)
                            if isEditModeActive() then return end
                            local st = ensureFS()
                            if st and st.IsHidden(self, "healthText") and alpha and alpha > 0 then
                                -- Use C_Timer to avoid infinite recursion (hook calls SetAlpha which triggers hook)
                                if not st.GetProp(self, "healthTextAlphaDeferred") then
                                    st.SetProp(self, "healthTextAlphaDeferred", true)
                                    C_Timer.After(0, function()
                                        local st2 = ensureFS()
                                        if st2 then st2.SetProp(self, "healthTextAlphaDeferred", nil) end
                                        if st2 and st2.IsHidden(self, "healthText") and self.SetAlpha then
                                            pcall(self.SetAlpha, self, 0)
                                        end
                                    end)
                                end
                            end
                        end)
                        -- Hook SetText() to re-enforce alpha=0 when Blizzard updates text content
                        _G.hooksecurefunc(fs, "SetText", function(self)
                            if isEditModeActive() then return end
                            local st = ensureFS()
                            if st and st.IsHidden(self, "healthText") and self.SetAlpha then
                                pcall(self.SetAlpha, self, 0)
                            end
                        end)
                    end
                end
                fstate.SetHidden(fs, "healthText", true)
            else
                fstate.SetHidden(fs, "healthText", false)
                if fs.SetAlpha then pcall(fs.SetAlpha, fs, 1) end
            end
        end

        -- Apply current visibility once as part of the styling pass.
        applyHealthTextVisibility(leftFS, cfg.healthPercentHidden, unit)
        applyHealthTextVisibility(rightFS, cfg.healthValueHidden, unit)

        -- Install SetText hook for center TextString to enforce hidden state only
        local fstate = ensureFS()
        if textStringFS and fstate and not fstate.IsHooked(textStringFS, "healthTextCenterSetText") then
            fstate.MarkHooked(textStringFS, "healthTextCenterSetText")
            if _G.hooksecurefunc then
                _G.hooksecurefunc(textStringFS, "SetText", function(self)
                    if isEditModeActive() then return end
                    -- Enforce hidden state immediately if configured
                    local st = ensureFS()
                    if st and st.IsHidden(self, "healthTextCenter") and self.SetAlpha then
                        pcall(self.SetAlpha, self, 0)
                    end
                end)
            end
        end

        if leftFS then applyTextStyle(leftFS, cfg.textHealthPercent or {}, unit .. ":left", frame) end
        if rightFS then applyTextStyle(rightFS, cfg.textHealthValue or {}, unit .. ":right", frame) end
        -- Style center TextString using Value settings (used in NUMERIC display mode and Character Pane)
        -- Always apply styling if text customizations exist; handle visibility separately
        if textStringFS then
            -- Handle visibility only when explicitly configured
            if cfg.healthValueHidden ~= nil then
                local valueHidden = (cfg.healthValueHidden == true)
                if valueHidden then
                    if textStringFS.SetAlpha then pcall(textStringFS.SetAlpha, textStringFS, 0) end
                    if fstate then fstate.SetHidden(textStringFS, "healthTextCenter", true) end
                else
                    if fstate and fstate.IsHidden(textStringFS, "healthTextCenter") then
                        if textStringFS.SetAlpha then pcall(textStringFS.SetAlpha, textStringFS, 1) end
                        fstate.SetHidden(textStringFS, "healthTextCenter", false)
                    end
                end
            end
            -- Always apply styling (applyTextStyle returns early if no customizations)
            if not (fstate and fstate.IsHidden(textStringFS, "healthTextCenter")) then
                applyTextStyle(textStringFS, cfg.textHealthValue or {}, unit .. ":health-center", frame)
            end
        end

        -- DeadText / UnconsciousText: inherit font face + style from Health Value text settings.
        -- Only Target and Focus have these (Player/Pet do not).
        if unit == "Target" or unit == "Focus" then
            local root = (unit == "Target") and _G.TargetFrame or _G.FocusFrame
            local hbContainer = root and root.TargetFrameContent
                and root.TargetFrameContent.TargetFrameContentMain
                and root.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer
            if hbContainer then
                local valueCfg = cfg.textHealthValue or {}
                local deadText = hbContainer.DeadText
                local unconsciousText = hbContainer.UnconsciousText
                applyDeadTextFontInheritance(deadText, valueCfg)
                hookDeadTextShow(deadText, unit)
                applyDeadTextFontInheritance(unconsciousText, valueCfg)
                hookDeadTextShow(unconsciousText, unit)
            end
        end
    end

    -- Boss frames: Apply Health % (LeftText) and Value (RightText/Center) styling.
    -- Boss frames are not returned by EditModeManagerFrame's UnitFrame system indices like Player/Target/Focus/Pet,
    -- so Boss1..Boss5 are resolved deterministically using their global names.
    function addon.ApplyBossHealthTextStyling()
        local db = addon and addon.db and addon.db.profile
        if not db then return end

        local unitFrames = rawget(db, "unitFrames")
        local cfg = unitFrames and rawget(unitFrames, "Boss") or nil
        if not cfg then
            return
        end

        for i = 1, 5 do
            local bossFrame = _G["Boss" .. i .. "TargetFrame"]
            local hbContainer = bossFrame
                and bossFrame.TargetFrameContent
                and bossFrame.TargetFrameContent.TargetFrameContentMain
                and bossFrame.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer

            if hbContainer then
                local hb = hbContainer.HealthBar
                if hb then
                    -- Ensure combat-time visibility enforcement exists for Boss health texts
                    hookHealthBarUpdateTextString(hb, "Boss")
                end

                local leftFS = hbContainer.LeftText
                local rightFS = hbContainer.RightText
                local centerFS = hbContainer.HealthBarText

                if leftFS then
                    applyTextStyle(leftFS, cfg.textHealthPercent or {}, "Boss" .. tostring(i) .. ":health-left", hbContainer)
                end
                if rightFS then
                    applyTextStyle(rightFS, cfg.textHealthValue or {}, "Boss" .. tostring(i) .. ":health-right", hbContainer)
                end
                if centerFS then
                    applyTextStyle(centerFS, cfg.textHealthValue or {}, "Boss" .. tostring(i) .. ":health-center", hbContainer)
                end

                -- DeadText / UnconsciousText: inherit font face + style from Health Value settings
                local valueCfg = cfg.textHealthValue or {}
                local deadText = hbContainer.DeadText
                local unconsciousText = hbContainer.UnconsciousText
                applyDeadTextFontInheritance(deadText, valueCfg)
                hookDeadTextShow(deadText, "Boss")
                applyDeadTextFontInheritance(unconsciousText, valueCfg)
                hookDeadTextShow(unconsciousText, "Boss")
            end
        end

        -- Apply visibility once as part of the styling pass.
        if addon.ApplyUnitFrameHealthTextVisibilityFor then
            addon.ApplyUnitFrameHealthTextVisibilityFor("Boss")
        end
    end

    -- Lightweight visibility-only function used by UpdateTextString hooks.
    -- Uses SetAlpha instead of SetShown to avoid taint during combat.
    function addon.ApplyUnitFrameHealthTextVisibilityFor(unit)
        local db = addon and addon.db and addon.db.profile
        if not db then return end
        local unitFrames = rawget(db, "unitFrames")
        local cfg = unitFrames and rawget(unitFrames, unit) or nil
        if not cfg then
            return
        end

        -- Helper: Apply visibility using SetAlpha (combat-safe) instead of SetShown.
        -- Hooks Show(), SetAlpha(), and SetText() to re-enforce alpha=0 when Blizzard updates the element.
        -- Tri‑state: nil means "don't touch"; true=hide; false=show (restore).
        -- NOTE: Uses FrameState to avoid writing properties directly to Blizzard frames (causes taint).
        local function applyVisibility(fs, hiddenSetting)
            if not fs then return end
            local fstate = ensureFS()
            if not fstate then return end
            if hiddenSetting == nil then
                return
            end
            local hidden = (hiddenSetting == true)
            if hidden then
                if fs.SetAlpha then pcall(fs.SetAlpha, fs, 0) end
                -- Install hooks once to re-enforce alpha when Blizzard calls Show(), SetAlpha(), or SetText()
                if not fstate.IsHooked(fs, "healthTextVisibility") then
                    fstate.MarkHooked(fs, "healthTextVisibility")
                    if _G.hooksecurefunc then
                        -- Hook Show() to re-enforce alpha=0
                        _G.hooksecurefunc(fs, "Show", function(self)
                            if isEditModeActive() then return end
                            local st = ensureFS()
                            if st and st.IsHidden(self, "healthText") and self.SetAlpha then
                                pcall(self.SetAlpha, self, 0)
                            end
                        end)
                        -- Hook SetAlpha() to re-enforce alpha=0 when Blizzard tries to make it visible
                        _G.hooksecurefunc(fs, "SetAlpha", function(self, alpha)
                            if isEditModeActive() then return end
                            local st = ensureFS()
                            if st and st.IsHidden(self, "healthText") and alpha and alpha > 0 then
                                -- Use C_Timer to avoid infinite recursion (hook calls SetAlpha which triggers hook)
                                if not st.GetProp(self, "healthTextAlphaDeferred") then
                                    st.SetProp(self, "healthTextAlphaDeferred", true)
                                    C_Timer.After(0, function()
                                        local st2 = ensureFS()
                                        if st2 then st2.SetProp(self, "healthTextAlphaDeferred", nil) end
                                        if st2 and st2.IsHidden(self, "healthText") and self.SetAlpha then
                                            pcall(self.SetAlpha, self, 0)
                                        end
                                    end)
                                end
                            end
                        end)
                        -- Hook SetText() to re-enforce alpha=0 when Blizzard updates text content
                        _G.hooksecurefunc(fs, "SetText", function(self)
                            if isEditModeActive() then return end
                            local st = ensureFS()
                            if st and st.IsHidden(self, "healthText") and self.SetAlpha then
                                pcall(self.SetAlpha, self, 0)
                            end
                        end)
                    end
                end
                fstate.SetHidden(fs, "healthText", true)
            else
                fstate.SetHidden(fs, "healthText", false)
                if fs.SetAlpha then pcall(fs.SetAlpha, fs, 1) end
            end
        end

        -- Boss frames: apply to Boss1..Boss5 deterministically (no cache dependency).
        if unit == "Boss" then
            for i = 1, 5 do
                local bossFrame = _G["Boss" .. i .. "TargetFrame"]
                local hbContainer = bossFrame
                    and bossFrame.TargetFrameContent
                    and bossFrame.TargetFrameContent.TargetFrameContentMain
                    and bossFrame.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer
                local leftFS = hbContainer and hbContainer.LeftText or nil
                local rightFS = hbContainer and hbContainer.RightText or nil
                local centerFS = hbContainer and hbContainer.HealthBarText or nil
                applyVisibility(leftFS, cfg.healthPercentHidden)
                applyVisibility(rightFS, cfg.healthValueHidden)
                -- Center TextString is used in NUMERIC mode; treat it as Value Text for parity with Player/Target.
                applyVisibility(centerFS, cfg.healthValueHidden)
            end
            return
        end

        local cache = addon._ufHealthTextFonts and addon._ufHealthTextFonts[unit]
        if not cache then
            -- If fonts haven't been resolved yet this session, skip work here.
            -- They will be resolved during the next ApplyStyles() pass.
            return
        end

        local leftFS = cache.leftFS
        local rightFS = cache.rightFS

        applyVisibility(leftFS, cfg.healthPercentHidden)
        applyVisibility(rightFS, cfg.healthValueHidden)
    end

	function addon.ApplyAllUnitFrameHealthTextVisibility()
		applyForUnit("Player")
		applyForUnit("Target")
		applyForUnit("Focus")
		applyForUnit("Pet")
        if addon.ApplyBossHealthTextStyling then
            addon.ApplyBossHealthTextStyling()
        end
	end

    -- Copy addon-only Unit Frame text settings from source unit to destination unit
    function addon.CopyUnitFrameTextSettings(sourceUnit, destUnit)
        local db = addon and addon.db and addon.db.profile
        if not db then return false end
        db.unitFrames = db.unitFrames or {}
        local src = db.unitFrames[sourceUnit]
        if not src then return false end
        db.unitFrames[destUnit] = db.unitFrames[destUnit] or {}
        local dst = db.unitFrames[destUnit]
        local function deepcopy(v)
            if type(v) ~= "table" then return v end
            local out = {}
            for k, vv in pairs(v) do out[k] = deepcopy(vv) end
            return out
        end
        local keys = {
            "healthPercentHidden",
            "healthValueHidden",
            "textHealthPercent",
            "textHealthValue",
        }
        for _, k in ipairs(keys) do
            if src[k] ~= nil then dst[k] = deepcopy(src[k]) else dst[k] = nil end
        end
        if addon.ApplyUnitFrameHealthTextVisibilityFor then addon.ApplyUnitFrameHealthTextVisibilityFor(destUnit) end
        return true
    end
end

	-- Unit Frames: Toggle Power % (LeftText when present) and Value (RightText) visibility per unit
do
    -- Cache for resolved power text fontstrings per unit so combat-time hooks stay cheap.
    addon._ufPowerTextFonts = addon._ufPowerTextFonts or {}

	local function getUnitFrameFor(unit)
		local mgr = _G.EditModeManagerFrame
		local EM = _G.Enum and _G.Enum.EditModeUnitFrameSystemIndices
		local EMSys = _G.Enum and _G.Enum.EditModeSystem
		if not (mgr and EMSys and mgr.GetRegisteredSystemFrame) then
			if unit == "Pet" then return _G.PetFrame end
			return nil
		end
		local idx = nil
		if EM then
			idx = (unit == "Player" and EM.Player)
				or (unit == "Target" and EM.Target)
				or (unit == "Focus" and EM.Focus)
				or (unit == "Pet" and EM.Pet)
		end
		if idx then
			return mgr:GetRegisteredSystemFrame(EMSys.UnitFrame, idx)
		end
		if unit == "Pet" then return _G.PetFrame end
	end

	local function findFontStringByNameHint(root, hint)
		if not root then return nil end
		local target
		local function scan(obj)
			if not obj or target then return end
			if obj.GetObjectType and obj:GetObjectType() == "FontString" then
				local nm = obj.GetName and obj:GetName() or (obj.GetDebugName and obj:GetDebugName()) or ""
				if type(nm) == "string" and string.find(string.lower(nm), string.lower(hint), 1, true) then
					target = obj; return
				end
			end
			if obj.GetRegions then
				local n = (obj.GetNumRegions and obj:GetNumRegions(obj)) or 0
				for i = 1, n do
					local r = select(i, obj:GetRegions())
					if r and r.GetObjectType and r:GetObjectType() == "FontString" then
						local nm = r.GetName and r:GetName() or (r.GetDebugName and r:GetDebugName()) or ""
						if type(nm) == "string" and string.find(string.lower(nm), string.lower(hint), 1, true) then
							target = r; return
						end
					end
				end
			end
			if obj.GetChildren then
				local m = (obj.GetNumChildren and obj:GetNumChildren()) or 0
				for i = 1, m do
					local c = select(i, obj:GetChildren())
					scan(c)
					if target then return end
				end
			end
		end
		scan(root)
		return target
	end

	-- Resolve the content main frame for anchoring name backdrop
	local function resolveUFContentMain_NLT(unit)
		if unit == "Player" then
			local root = _G.PlayerFrame
			return root and root.PlayerFrameContent and root.PlayerFrameContent.PlayerFrameContentMain or nil
		elseif unit == "Target" then
			local root = _G.TargetFrame
			return root and root.TargetFrameContent and root.TargetFrameContent.TargetFrameContentMain or nil
		elseif unit == "Focus" then
			local root = _G.FocusFrame
			return root and root.TargetFrameContent and root.TargetFrameContent.TargetFrameContentMain or nil
		elseif unit == "Pet" then
			return _G.PetFrame
		end
	end

	-- Resolve the Health Bar status bar for anchoring name backdrop
	local function resolveHealthBar_NLT(unit)
		if unit == "Pet" then return _G.PetFrameHealthBar end
		if unit == "Player" then
			local root = _G.PlayerFrame
			return root
				and root.PlayerFrameContent
				and root.PlayerFrameContent.PlayerFrameContentMain
				and root.PlayerFrameContent.PlayerFrameContentMain.HealthBarsContainer
				and root.PlayerFrameContent.PlayerFrameContentMain.HealthBarsContainer.HealthBar
				or nil
		elseif unit == "Target" then
			local root = _G.TargetFrame
			return root
				and root.TargetFrameContent
				and root.TargetFrameContent.TargetFrameContentMain
				and root.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer
				and root.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer.HealthBar
				or nil
		elseif unit == "Focus" then
			local root = _G.FocusFrame
			return root
				and root.TargetFrameContent
				and root.TargetFrameContent.TargetFrameContentMain
				and root.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer
				and root.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer.HealthBar
				or nil
		end
	end

	-- Resolve power bar for this unit
	local function resolvePowerBarForVisibility(frame, unit)
		if unit == "Pet" then return _G.PetFrameManaBar end
		if frame and frame.ManaBar then return frame.ManaBar end
		-- Try direct paths
		if unit == "Player" then
			local root = _G.PlayerFrame
			if root and root.PlayerFrameContent and root.PlayerFrameContent.PlayerFrameContentMain
				and root.PlayerFrameContent.PlayerFrameContentMain.ManaBarArea
				and root.PlayerFrameContent.PlayerFrameContentMain.ManaBarArea.ManaBar then
				return root.PlayerFrameContent.PlayerFrameContentMain.ManaBarArea.ManaBar
			end
		elseif unit == "Target" then
			local root = _G.TargetFrame
			if root and root.TargetFrameContent and root.TargetFrameContent.TargetFrameContentMain
				and root.TargetFrameContent.TargetFrameContentMain.ManaBar then
				return root.TargetFrameContent.TargetFrameContentMain.ManaBar
			end
		elseif unit == "Focus" then
			local root = _G.FocusFrame
			if root and root.TargetFrameContent and root.TargetFrameContent.TargetFrameContentMain
				and root.TargetFrameContent.TargetFrameContentMain.ManaBar then
				return root.TargetFrameContent.TargetFrameContentMain.ManaBar
			end
		end
	end

	-- Hook UpdateTextString to reapply visibility after Blizzard's updates.
	-- Use hooksecurefunc to avoid replacing the method and taint secure StatusBars.
	local function hookPowerBarUpdateTextString(bar, unit)
		local fstate = ensureFS()
		if not bar or not fstate then return end
		if fstate.IsHooked(bar, "powerBarUpdateTextString") then return end
		fstate.MarkHooked(bar, "powerBarUpdateTextString")
		if _G.hooksecurefunc then
			_G.hooksecurefunc(bar, "UpdateTextString", function(self, ...)
				if addon and addon.ApplyUnitFramePowerTextVisibilityFor then
					addon.ApplyUnitFramePowerTextVisibilityFor(unit)
				end
			end)
		end
	end

	-- NOTE: SetFont/SetFontObject hooks removed for performance reasons.
	-- Font persistence during Character Pane opening is handled by the Character Frame hook section.
	-- Font persistence during instance loading can be handled via PLAYER_ENTERING_WORLD if needed.
	-- The previous hooks called ApplyAll* functions on every font change which was too expensive.
	local function hookPowerTextFontReset(fs, unit, textType)
		-- No-op: hooks removed for performance
	end

	-- Styling helpers (defined at do-block scope for use by both applyForUnit and ApplyBossPowerTextStyling)
	addon._ufPowerTextBaselines = addon._ufPowerTextBaselines or {}
	local function ensureBaseline(fs, key, fallbackFrame)
		addon._ufPowerTextBaselines[key] = addon._ufPowerTextBaselines[key] or {}
		local b = addon._ufPowerTextBaselines[key]
		if b.point == nil then
			if fs and fs.GetPoint then
				local p, relTo, rp, x, y = fs:GetPoint(1)
				b.point = p or "CENTER"
				b.relTo = relTo or (fs.GetParent and fs:GetParent()) or fallbackFrame
				b.relPoint = rp or b.point
				b.x = safeOffset(x)
				b.y = safeOffset(y)
			else
				b.point, b.relTo, b.relPoint, b.x, b.y = "CENTER", (fs and fs.GetParent and fs:GetParent()) or fallbackFrame, "CENTER", 0, 0
			end
		end
		return b
	end

	-- Helper to force FontString redraw after alignment change (secret-value safe)
	local function forceTextRedraw(fs)
		if fs and fs.GetText and fs.SetText then
			local ok, txt = pcall(fs.GetText, fs)
			if ok and txt and type(txt) == "string" then
				fs:SetText("")
				fs:SetText(txt)
			else
				-- Fallback: toggle alpha to force redraw without needing text value
				local okAlpha, alpha = pcall(function() return fs.GetAlpha and fs:GetAlpha() end)
				if okAlpha and alpha then
					pcall(fs.SetAlpha, fs, 0)
					pcall(fs.SetAlpha, fs, alpha)
				end
			end
		end
	end

	-- Default/clean profiles should not modify Blizzard text.
	-- Only treat settings as "customized" if they differ from structural defaults.
	local function hasTextCustomization(styleCfg)
		if not styleCfg then return false end
		if styleCfg.fontFace ~= nil and styleCfg.fontFace ~= "" and styleCfg.fontFace ~= "FRIZQT__" then
			return true
		end
		if styleCfg.size ~= nil or styleCfg.style ~= nil or styleCfg.color ~= nil or styleCfg.alignment ~= nil then
			return true
		end
		-- colorMode is used for Power Bar text to support "classPower" color
		if styleCfg.colorMode ~= nil and styleCfg.colorMode ~= "default" then
			return true
		end
		if styleCfg.offset and (styleCfg.offset.x ~= nil or styleCfg.offset.y ~= nil) then
			local ox = tonumber(styleCfg.offset.x) or 0
			local oy = tonumber(styleCfg.offset.y) or 0
			if ox ~= 0 or oy ~= 0 then
				return true
			end
		end
		return false
	end

	local function applyTextStyle(fs, styleCfg, baselineKey, fallbackFrame)
		if not fs or not styleCfg then return end
		if not hasTextCustomization(styleCfg) then
			return
		end
		local face = addon.ResolveFontFace and addon.ResolveFontFace(styleCfg.fontFace or "FRIZQT__") or (select(1, _G.GameFontNormal:GetFont()))
		local size = tonumber(styleCfg.size) or 14
		local outline = tostring(styleCfg.style or "OUTLINE")
		-- Set flag to prevent the SetFont hook from triggering a reapply loop
		local fst = ensureFS()
		if fst then fst.SetProp(fs, "applyingFont", true) end
		if addon.ApplyFontStyle then addon.ApplyFontStyle(fs, face, size, outline) elseif fs.SetFont then pcall(fs.SetFont, fs, face, size, outline) end
		if fst then fst.SetProp(fs, "applyingFont", nil) end
		-- Determine effective color based on colorMode (for Power Bar text)
		local c = styleCfg.color or {1,1,1,1}
		local colorMode = styleCfg.colorMode or "default"
		if colorMode == "classPower" then
			-- Use the class's power bar color (Energy = yellow, Rage = red, Mana = blue, etc.)
			if addon.GetPowerColorRGB then
				local pr, pg, pb = addon.GetPowerColorRGB("player")
				-- Lighten mana blue for text readability (mana = powerType 0)
				local powerType = UnitPowerType("player")
				if powerType == 0 then -- MANA
					local lightenFactor = 0.25
					pr = (pr or 0) + (1 - (pr or 0)) * lightenFactor
					pg = (pg or 0) + (1 - (pg or 0)) * lightenFactor
					pb = (pb or 0) + (1 - (pb or 0)) * lightenFactor
				end
				c = {pr or 1, pg or 1, pb or 1, 1}
			end
		elseif colorMode == "class" then
			local cr, cg, cb = addon.GetClassColorRGB("player")
			c = {cr or 1, cg or 1, cb or 1, 1}
		elseif colorMode == "default" then
			-- Default white for Blizzard's standard bar text color
			c = {1, 1, 1, 1}
		end
		-- colorMode == "custom" uses styleCfg.color as-is
		if fs.SetTextColor then pcall(fs.SetTextColor, fs, c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1) end

		-- Only modify width/alignment/position if alignment or offset is explicitly configured.
		-- This prevents Apply All Fonts (which only sets fontFace) from inadvertently changing
		-- text positioning. Width/alignment changes are only appropriate when the user has
		-- explicitly configured layout-related settings.
		local hasLayoutCustomization = styleCfg.alignment ~= nil
			or (styleCfg.offset and (styleCfg.offset.x ~= nil or styleCfg.offset.y ~= nil))

		if hasLayoutCustomization then
			-- Determine default alignment based on whether this is left (%) or right (value) or center text
			-- Check for both :right and -right patterns to handle all unit types
			local defaultAlign = "LEFT"
			if baselineKey and (baselineKey:find(":right", 1, true) or baselineKey:find("-right", 1, true)) then
				defaultAlign = "RIGHT"
			elseif baselineKey and (baselineKey:find(":center", 1, true) or baselineKey:find("-center", 1, true)) then
				defaultAlign = "CENTER"
			end
			local alignment = styleCfg.alignment or defaultAlign

			local parentBar = fs.GetParent and fs:GetParent()

			-- Get baseline Y position and user offsets
			local b = ensureBaseline(fs, baselineKey, fallbackFrame or parentBar)
			local ox = (styleCfg.offset and tonumber(styleCfg.offset.x)) or 0
			local oy = (styleCfg.offset and tonumber(styleCfg.offset.y)) or 0
			local yOffset = safeOffset(b.y) + oy

			-- Use two-point anchoring to span the parent bar width.
			-- This makes JustifyH work correctly without needing GetWidth() (which can
			-- trigger secret value errors on unit frame StatusBars).
			if fs.ClearAllPoints and fs.SetPoint and parentBar then
				fs:ClearAllPoints()
				-- Anchor both left and right edges to span the bar
				-- Apply small padding (2px) plus user X offset for text inset
				local leftPad = 2 + ox
				local rightPad = -2 + ox
				pcall(fs.SetPoint, fs, "LEFT", parentBar, "LEFT", leftPad, yOffset)
				pcall(fs.SetPoint, fs, "RIGHT", parentBar, "RIGHT", rightPad, yOffset)
			end

			-- Apply text alignment
			if fs.SetJustifyH then
				pcall(fs.SetJustifyH, fs, alignment)
			end

			-- Force redraw to apply alignment visually
			forceTextRedraw(fs)
		end
	end

	local function applyForUnit(unit)
		local db = addon and addon.db and addon.db.profile
		if not db then return end
		-- Zero‑Touch: do not create config tables. If this unit has no config, do nothing.
		local unitFrames = rawget(db, "unitFrames")
		local cfg = unitFrames and rawget(unitFrames, unit) or nil
		if not cfg then
			return
		end
		local frame = getUnitFrameFor(unit)
		if not frame then return end

		-- Resolve power bar and hook its UpdateTextString if not already hooked
		local pb = resolvePowerBarForVisibility(frame, unit)
		if pb then
			hookPowerBarUpdateTextString(pb, unit)
		end

		-- Attempt to resolve power bar text regions
		local leftFS
		local rightFS
		if unit == "Pet" then
			-- Pet uses standalone globals more often
			leftFS = _G.PetFrameManaBarTextLeft
			rightFS = _G.PetFrameManaBarTextRight
		end

        -- Full resolution path (may scan children/regions). This should only run during
        -- explicit styling passes (ApplyStyles), not on every power text update.
		leftFS = leftFS
			or (frame.ManaBar and frame.ManaBar.LeftText)
			or findFontStringByNameHint(frame, "ManaBar.LeftText")
			or findFontStringByNameHint(frame, ".LeftText")
			or findFontStringByNameHint(frame, "ManaBarTextLeft")
		rightFS = rightFS
			or (frame.ManaBar and frame.ManaBar.RightText)
			or findFontStringByNameHint(frame, "ManaBar.RightText")
			or findFontStringByNameHint(frame, ".RightText")
			or findFontStringByNameHint(frame, "ManaBarTextRight")

        -- Also resolve the center TextString (used in NUMERIC display mode and Character Pane)
        -- This ensures styling persists when Blizzard switches between BOTH and NUMERIC modes
        -- Character Pane shows ManaBarText instead of LeftText/RightText
        local textStringFS
        if unit == "Pet" then
            textStringFS = _G.PetFrameManaBarText
        elseif unit == "Player" then
            local root = _G.PlayerFrame
            textStringFS = root and root.PlayerFrameContent 
                and root.PlayerFrameContent.PlayerFrameContentMain 
                and root.PlayerFrameContent.PlayerFrameContentMain.ManaBarArea 
                and root.PlayerFrameContent.PlayerFrameContentMain.ManaBarArea.ManaBar 
                and root.PlayerFrameContent.PlayerFrameContentMain.ManaBarArea.ManaBar.ManaBarText
        elseif unit == "Target" then
            local root = _G.TargetFrame
            textStringFS = root and root.TargetFrameContent 
                and root.TargetFrameContent.TargetFrameContentMain 
                and root.TargetFrameContent.TargetFrameContentMain.ManaBar 
                and root.TargetFrameContent.TargetFrameContentMain.ManaBar.ManaBarText
        elseif unit == "Focus" then
            local root = _G.FocusFrame
            textStringFS = root and root.TargetFrameContent 
                and root.TargetFrameContent.TargetFrameContentMain 
                and root.TargetFrameContent.TargetFrameContentMain.ManaBar 
                and root.TargetFrameContent.TargetFrameContentMain.ManaBar.ManaBarText
        end

        -- Cache resolved fontstrings so combat-time hooks can avoid expensive scans.
        addon._ufPowerTextFonts[unit] = {
            leftFS = leftFS,
            rightFS = rightFS,
            textStringFS = textStringFS,
        }

        -- Install font reset hooks to reapply styling when Blizzard calls SetFontObject
        hookPowerTextFontReset(leftFS, unit, "left")
        hookPowerTextFontReset(rightFS, unit, "right")
        hookPowerTextFontReset(textStringFS, unit, "center")

        -- Helper: Apply visibility using SetAlpha (combat-safe) instead of SetShown (taint-prone).
        -- Hooks Show(), SetAlpha(), and SetText() to re-enforce BOTH alpha=0 AND font styling when Blizzard updates.
        -- Tri‑state: nil means "don't touch"; true=hide; false=show (restore).
        -- NOTE: Uses FrameState to avoid writing properties directly to Blizzard frames (causes taint).
        local function applyPowerTextVisibility(fs, hiddenSetting, unitForHook)
            if not fs then return end
            local fstate = ensureFS()
            if not fstate then return end
            if hiddenSetting == nil then
                return
            end
            local hidden = (hiddenSetting == true)
            if hidden then
                if fs.SetAlpha then pcall(fs.SetAlpha, fs, 0) end
                -- Install hooks once to re-enforce alpha when Blizzard calls Show(), SetAlpha(), or SetText()
                if not fstate.IsHooked(fs, "powerTextVisibility") then
                    fstate.MarkHooked(fs, "powerTextVisibility")
                    if _G.hooksecurefunc then
                        -- Hook Show() to re-enforce alpha=0
                        _G.hooksecurefunc(fs, "Show", function(self)
                            local st = ensureFS()
                            if st and st.IsHidden(self, "powerText") and self.SetAlpha then
                                pcall(self.SetAlpha, self, 0)
                            end
                        end)
                        -- Hook SetAlpha() to re-enforce alpha=0 when Blizzard tries to make it visible
                        _G.hooksecurefunc(fs, "SetAlpha", function(self, alpha)
                            local st = ensureFS()
                            if st and st.IsHidden(self, "powerText") and alpha and alpha > 0 then
                                -- Use C_Timer to avoid infinite recursion (hook calls SetAlpha which triggers hook)
                                if not st.GetProp(self, "powerTextAlphaDeferred") then
                                    st.SetProp(self, "powerTextAlphaDeferred", true)
                                    C_Timer.After(0, function()
                                        local st2 = ensureFS()
                                        if st2 then st2.SetProp(self, "powerTextAlphaDeferred", nil) end
                                        if st2 and st2.IsHidden(self, "powerText") and self.SetAlpha then
                                            pcall(self.SetAlpha, self, 0)
                                        end
                                    end)
                                end
                            end
                        end)
                        -- Hook SetText() to re-enforce alpha=0 when Blizzard updates text content
                        _G.hooksecurefunc(fs, "SetText", function(self)
                            local st = ensureFS()
                            if st and st.IsHidden(self, "powerText") and self.SetAlpha then
                                pcall(self.SetAlpha, self, 0)
                            end
                        end)
                    end
                end
                fstate.SetHidden(fs, "powerText", true)
            else
                fstate.SetHidden(fs, "powerText", false)
                if fs.SetAlpha then pcall(fs.SetAlpha, fs, 1) end
            end
        end

		-- Visibility: tolerate missing LeftText on some classes/specs (no-op)
		-- When the entire Power Bar is hidden, force all power texts hidden regardless of individual toggles.
		local powerBarHiddenSetting = cfg.powerBarHidden -- tri-state
		local leftHiddenSetting
		local rightHiddenSetting
		if powerBarHiddenSetting == true then
			leftHiddenSetting = true
			rightHiddenSetting = true
		else
			leftHiddenSetting = cfg.powerPercentHidden
			rightHiddenSetting = cfg.powerValueHidden
		end
		applyPowerTextVisibility(leftFS, leftHiddenSetting, unit)
		applyPowerTextVisibility(rightFS, rightHiddenSetting, unit)

        -- Install SetText hook for center TextString to enforce hidden state only
        local fstate = ensureFS()
        if textStringFS and fstate and not fstate.IsHooked(textStringFS, "powerTextCenterSetText") then
            fstate.MarkHooked(textStringFS, "powerTextCenterSetText")
            if _G.hooksecurefunc then
                _G.hooksecurefunc(textStringFS, "SetText", function(self)
                    -- Enforce hidden state immediately if configured
                    local st = ensureFS()
                    if st and st.IsHidden(self, "powerTextCenter") and self.SetAlpha then
                        pcall(self.SetAlpha, self, 0)
                    end
                end)
            end
        end

		if leftFS then applyTextStyle(leftFS, cfg.textPowerPercent or {}, unit .. ":power-left", frame) end
		if rightFS then applyTextStyle(rightFS, cfg.textPowerValue or {}, unit .. ":power-right", frame) end
        -- Style center TextString using Value settings (used in NUMERIC display mode and Character Pane)
        -- Always apply styling if text customizations exist; handle visibility separately
        if textStringFS then
            -- Handle visibility only when explicitly configured
            local centerHiddenSetting = nil
            if powerBarHiddenSetting == true then
                centerHiddenSetting = true
            elseif cfg.powerValueHidden ~= nil then
                centerHiddenSetting = cfg.powerValueHidden
            end

            if centerHiddenSetting ~= nil then
                local valueHidden = (centerHiddenSetting == true)
                if valueHidden then
                    if textStringFS.SetAlpha then pcall(textStringFS.SetAlpha, textStringFS, 0) end
                    if fstate then fstate.SetHidden(textStringFS, "powerTextCenter", true) end
                else
                    if fstate and fstate.IsHidden(textStringFS, "powerTextCenter") then
                        if textStringFS.SetAlpha then pcall(textStringFS.SetAlpha, textStringFS, 1) end
                        fstate.SetHidden(textStringFS, "powerTextCenter", false)
                    end
                end
            end
            -- Always apply styling (applyTextStyle returns early if no customizations)
            if not (fstate and fstate.IsHidden(textStringFS, "powerTextCenter")) then
                applyTextStyle(textStringFS, cfg.textPowerValue or {}, unit .. ":power-center", frame)
            end
        end
	end

    -- Boss frames: Apply Power % (LeftText) and Value (RightText) styling.
    -- Boss frames are not returned by EditModeManagerFrame's UnitFrame system indices like Player/Target/Focus/Pet,
    -- so Boss1..Boss5 are resolved deterministically using their global names.
    function addon.ApplyBossPowerTextStyling()
        local db = addon and addon.db and addon.db.profile
        if not db then return end

        local unitFrames = rawget(db, "unitFrames")
        local cfg = unitFrames and rawget(unitFrames, "Boss") or nil
        if not cfg then
            return
        end

        for i = 1, 5 do
            local bossFrame = _G["Boss" .. i .. "TargetFrame"]
            local manaBar = bossFrame
                and bossFrame.TargetFrameContent
                and bossFrame.TargetFrameContent.TargetFrameContentMain
                and bossFrame.TargetFrameContent.TargetFrameContentMain.ManaBar

            if manaBar then
                -- Ensure combat-time visibility enforcement exists for Boss power texts
                hookPowerBarUpdateTextString(manaBar, "Boss")

                local leftFS = manaBar.LeftText
                local rightFS = manaBar.RightText

                if leftFS then
                    applyTextStyle(leftFS, cfg.textPowerPercent or {}, "Boss" .. tostring(i) .. ":power-left", manaBar)
                end
                if rightFS then
                    applyTextStyle(rightFS, cfg.textPowerValue or {}, "Boss" .. tostring(i) .. ":power-right", manaBar)
                end
            end
        end

        -- Apply visibility once as part of the styling pass.
        if addon.ApplyUnitFramePowerTextVisibilityFor then
            addon.ApplyUnitFramePowerTextVisibilityFor("Boss")
        end
    end

    -- Lightweight visibility-only function used by UpdateTextString hooks.
    -- Uses SetAlpha instead of SetShown to avoid taint during combat.
	function addon.ApplyUnitFramePowerTextVisibilityFor(unit)
        local db = addon and addon.db and addon.db.profile
        if not db then return end
        local unitFrames = rawget(db, "unitFrames")
        local cfg = unitFrames and rawget(unitFrames, unit) or nil
        if not cfg then
            return
        end

        -- Helper: Apply visibility using SetAlpha (combat-safe) instead of SetShown.
        -- Hooks Show(), SetAlpha(), and SetText() to re-enforce alpha=0 when Blizzard updates the element.
        -- Tri‑state: nil means "don't touch"; true=hide; false=show (restore).
        -- NOTE: Uses FrameState to avoid writing properties directly to Blizzard frames (causes taint).
        local function applyVisibility(fs, hiddenSetting)
            if not fs then return end
            local fstate = ensureFS()
            if not fstate then return end
            if hiddenSetting == nil then
                return
            end
            local hidden = (hiddenSetting == true)
            if hidden then
                if fs.SetAlpha then pcall(fs.SetAlpha, fs, 0) end
                -- Install hooks once to re-enforce alpha when Blizzard calls Show(), SetAlpha(), or SetText()
                if not fstate.IsHooked(fs, "powerTextVisibility") then
                    fstate.MarkHooked(fs, "powerTextVisibility")
                    if _G.hooksecurefunc then
                        -- Hook Show() to re-enforce alpha=0
                        _G.hooksecurefunc(fs, "Show", function(self)
                            local st = ensureFS()
                            if st and st.IsHidden(self, "powerText") and self.SetAlpha then
                                pcall(self.SetAlpha, self, 0)
                            end
                        end)
                        -- Hook SetAlpha() to re-enforce alpha=0 when Blizzard tries to make it visible
                        _G.hooksecurefunc(fs, "SetAlpha", function(self, alpha)
                            local st = ensureFS()
                            if st and st.IsHidden(self, "powerText") and alpha and alpha > 0 then
                                -- Use C_Timer to avoid infinite recursion (hook calls SetAlpha which triggers hook)
                                if not st.GetProp(self, "powerTextAlphaDeferred") then
                                    st.SetProp(self, "powerTextAlphaDeferred", true)
                                    C_Timer.After(0, function()
                                        local st2 = ensureFS()
                                        if st2 then st2.SetProp(self, "powerTextAlphaDeferred", nil) end
                                        if st2 and st2.IsHidden(self, "powerText") and self.SetAlpha then
                                            pcall(self.SetAlpha, self, 0)
                                        end
                                    end)
                                end
                            end
                        end)
                        -- Hook SetText() to re-enforce alpha=0 when Blizzard updates text content
                        _G.hooksecurefunc(fs, "SetText", function(self)
                            local st = ensureFS()
                            if st and st.IsHidden(self, "powerText") and self.SetAlpha then
                                pcall(self.SetAlpha, self, 0)
                            end
                        end)
                    end
                end
                fstate.SetHidden(fs, "powerText", true)
            else
                fstate.SetHidden(fs, "powerText", false)
                if fs.SetAlpha then pcall(fs.SetAlpha, fs, 1) end
            end
        end

        -- Boss frames: apply to Boss1..Boss5 deterministically (no cache dependency).
        if unit == "Boss" then
            local powerBarHiddenSetting = cfg.powerBarHidden -- tri-state
            local leftHiddenSetting
            local rightHiddenSetting
            if powerBarHiddenSetting == true then
                leftHiddenSetting = true
                rightHiddenSetting = true
            else
                leftHiddenSetting = cfg.powerPercentHidden
                rightHiddenSetting = cfg.powerValueHidden
            end
            for i = 1, 5 do
                local bossFrame = _G["Boss" .. i .. "TargetFrame"]
                local mana = bossFrame
                    and bossFrame.TargetFrameContent
                    and bossFrame.TargetFrameContent.TargetFrameContentMain
                    and bossFrame.TargetFrameContent.TargetFrameContentMain.ManaBar
                local leftFS = mana and mana.LeftText or nil
                local rightFS = mana and mana.RightText or nil
                applyVisibility(leftFS, leftHiddenSetting)
                applyVisibility(rightFS, rightHiddenSetting)
            end
            return
        end

        local cache = addon._ufPowerTextFonts and addon._ufPowerTextFonts[unit]
        if not cache then
            -- If fonts haven't been resolved yet this session, skip work here.
            -- They will be resolved during the next ApplyStyles() pass.
            return
        end

        local leftFS = cache.leftFS
        local rightFS = cache.rightFS

        -- Visibility: tolerate missing LeftText on some classes/specs (no-op)
        -- When the entire Power Bar is hidden, force all power texts hidden regardless of individual toggles.
		local powerBarHiddenSetting = cfg.powerBarHidden -- tri-state
		local leftHiddenSetting
		local rightHiddenSetting
		if powerBarHiddenSetting == true then
			leftHiddenSetting = true
			rightHiddenSetting = true
		else
			leftHiddenSetting = cfg.powerPercentHidden
			rightHiddenSetting = cfg.powerValueHidden
		end
        applyVisibility(leftFS, leftHiddenSetting)
        applyVisibility(rightFS, rightHiddenSetting)
	end

	function addon.ApplyAllUnitFramePowerTextVisibility()
		applyForUnit("Player")
		applyForUnit("Target")
		applyForUnit("Focus")
		applyForUnit("Pet")
        if addon.ApplyBossPowerTextStyling then
            addon.ApplyBossPowerTextStyling()
        end
	end

	-- Optional helper mirroring health text settings copy (no-op if missing)
	function addon.CopyUnitFramePowerTextSettings(sourceUnit, destUnit)
		local db = addon and addon.db and addon.db.profile
		if not db then return false end
		db.unitFrames = db.unitFrames or {}
		local src = db.unitFrames[sourceUnit]
		if not src then return false end
		db.unitFrames[destUnit] = db.unitFrames[destUnit] or {}
		local dst = db.unitFrames[destUnit]
		local function deepcopy(v)
			if type(v) ~= "table" then return v end
			local out = {}
			for k, vv in pairs(v) do out[k] = deepcopy(vv) end
			return out
		end
		local keys = {
			"powerPercentHidden",
			"powerValueHidden",
			"textPowerPercent",
			"textPowerValue",
		}
		for _, k in ipairs(keys) do
			if src[k] ~= nil then dst[k] = deepcopy(src[k]) else dst[k] = nil end
		end
		if addon.ApplyUnitFramePowerTextVisibilityFor then addon.ApplyUnitFramePowerTextVisibilityFor(destUnit) end
		return true
	end
end

--- Unit Frames: Apply Name & Level Text styling (visibility, font, size, style, color, offset)
do
	local function getUnitFrameFor(unit)
		local mgr = _G.EditModeManagerFrame
		local EM = _G.Enum and _G.Enum.EditModeUnitFrameSystemIndices
		local EMSys = _G.Enum and _G.Enum.EditModeSystem
		if not (mgr and EMSys and mgr.GetRegisteredSystemFrame) then
			if unit == "Pet" then return _G.PetFrame end
			return nil
		end
		local idx = nil
		if unit == "Player" then idx = EM.Player
		elseif unit == "Target" then idx = EM.Target
		elseif unit == "Focus" then idx = EM.Focus
		elseif unit == "Pet" then idx = EM.Pet
		end
		if not idx then return nil end
		return mgr:GetRegisteredSystemFrame(EMSys.UnitFrame, idx)
	end

	-- Local resolvers for this block (backdrop anchoring helpers)
	local function resolveUFContentMain_NLT(unit)
		if unit == "Player" then
			local root = _G.PlayerFrame
			return root and root.PlayerFrameContent and root.PlayerFrameContent.PlayerFrameContentMain or nil
		elseif unit == "Target" then
			local root = _G.TargetFrame
			return root and root.TargetFrameContent and root.TargetFrameContent.TargetFrameContentMain or nil
		elseif unit == "Focus" then
			local root = _G.FocusFrame
			return root and root.TargetFrameContent and root.TargetFrameContent.TargetFrameContentMain or nil
		elseif unit == "Pet" then
			return _G.PetFrame
		end
	end

	local function resolveHealthBar_NLT(unit)
		if unit == "Pet" then return _G.PetFrameHealthBar end
		if unit == "Player" then
			local root = _G.PlayerFrame
			return root
				and root.PlayerFrameContent
				and root.PlayerFrameContent.PlayerFrameContentMain
				and root.PlayerFrameContent.PlayerFrameContentMain.HealthBarsContainer
				and root.PlayerFrameContent.PlayerFrameContentMain.HealthBarsContainer.HealthBar
				or nil
		elseif unit == "Target" then
			local root = _G.TargetFrame
			return root
				and root.TargetFrameContent
				and root.TargetFrameContent.TargetFrameContentMain
				and root.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer
				and root.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer.HealthBar
				or nil
		elseif unit == "Focus" then
			local root = _G.FocusFrame
			return root
				and root.TargetFrameContent
				and root.TargetFrameContent.TargetFrameContentMain
				and root.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer
				and root.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer.HealthBar
				or nil
		end
	end

	local function findFontStringByNameHint(root, hint)
		if not (root and hint) then return nil end
		local target = nil
		local function scan(obj)
			if not obj then return end
			if target then return end
			if obj.IsObjectType and obj:IsObjectType("FontString") then
				local nm = obj.GetName and obj:GetName() or ""
				if type(nm) == "string" and string.find(nm, hint, 1, true) then
					target = obj
					return
				end
			end
			if obj.GetChildren then
				local m = (obj.GetNumChildren and obj:GetNumChildren()) or 0
				for i = 1, m do
					local c = select(i, obj:GetChildren())
					scan(c)
					if target then return end
				end
			end
		end
		scan(root)
		return target
	end

	local function applyForUnit(unit)
		local db = addon and addon.db and addon.db.profile
		if not db then return end
		-- Zero‑Touch: do not create config tables. If this unit has no config, do nothing.
		local unitFrames = rawget(db, "unitFrames")
		local cfg = unitFrames and rawget(unitFrames, unit) or nil
		if not cfg then
			return
		end

		-- Zero‑Touch: only touch Name/Level/Backdrop when at least one relevant setting is explicitly set.
		local function hasAnyOffset(tbl)
			local off = tbl and tbl.offset
			return off and (off.x ~= nil or off.y ~= nil) or false
		end
		local textNameCfg = rawget(cfg, "textName")
		local textLevelCfg = rawget(cfg, "textLevel")
		local hasNameTextSettings = textNameCfg and (
			textNameCfg.fontFace ~= nil
			or textNameCfg.size ~= nil
			or textNameCfg.style ~= nil
			or textNameCfg.colorMode ~= nil
			or textNameCfg.color ~= nil
			or textNameCfg.alignment ~= nil
			or textNameCfg.containerWidthPct ~= nil
			or hasAnyOffset(textNameCfg)
		) or false
		local hasLevelTextSettings = textLevelCfg and (
			textLevelCfg.fontFace ~= nil
			or textLevelCfg.size ~= nil
			or textLevelCfg.style ~= nil
			or textLevelCfg.colorMode ~= nil
			or textLevelCfg.color ~= nil
			or hasAnyOffset(textLevelCfg)
		) or false
		local hasVisibilitySettings = (cfg.nameTextHidden ~= nil) or (cfg.levelTextHidden ~= nil)
		local hasBackdropSettings = (
			cfg.nameBackdropEnabled ~= nil
			or cfg.nameBackdropTexture ~= nil
			or cfg.nameBackdropColorMode ~= nil
			or cfg.nameBackdropTint ~= nil
			or cfg.nameBackdropOpacity ~= nil
			or cfg.nameBackdropWidthPct ~= nil
			or cfg.nameBackdropBorderEnabled ~= nil
			or cfg.nameBackdropBorderStyle ~= nil
			or cfg.nameBackdropBorderThickness ~= nil
			or cfg.nameBackdropBorderInset ~= nil
			or cfg.nameBackdropBorderInsetH ~= nil
			or cfg.nameBackdropBorderInsetV ~= nil
			or cfg.nameBackdropBorderTintEnable ~= nil
			or cfg.nameBackdropBorderTintColor ~= nil
		)
		if not (hasVisibilitySettings or hasNameTextSettings or hasLevelTextSettings or hasBackdropSettings) then
			return
		end

		-- Boss frames are a multi-frame system (Boss1..Boss5). They do not map cleanly
		-- to a single "unit frame" for baseline/child resolution. Handle as a special case.
		if unit == "Boss" then
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
			local function resolveBossFrame(i)
				return _G and _G["Boss" .. i .. "TargetFrame"] or nil
			end

			local function resolveBossNameFS(bossFrame)
				-- Blizzard exposes bossFrame.name, but fall back to the canonical nested path.
				return (bossFrame and (bossFrame.name
					or (bossFrame.TargetFrameContent
						and bossFrame.TargetFrameContent.TargetFrameContentMain
						and bossFrame.TargetFrameContent.TargetFrameContentMain.Name)))
					or nil
			end

			local function resolveBossLevelFS(bossFrame)
				return (bossFrame
					and bossFrame.TargetFrameContent
					and bossFrame.TargetFrameContent.TargetFrameContentMain
					and bossFrame.TargetFrameContent.TargetFrameContentMain.LevelText)
					or nil
			end

			local function resolveBossContentMain(bossFrame)
				return bossFrame
					and bossFrame.TargetFrameContent
					and bossFrame.TargetFrameContent.TargetFrameContentMain
					or nil
			end

			local function resolveBossHealthBar(bossFrame)
				-- Blizzard exposes bossFrame.healthbar (preferred).
				return bossFrame and bossFrame.healthbar
					or (bossFrame and bossFrame.TargetFrameContent
						and bossFrame.TargetFrameContent.TargetFrameContentMain
						and bossFrame.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer
						and bossFrame.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer.HealthBar)
					or nil
			end

			-- Baselines for Boss name text are stored per-boss-index.
			addon._ufNameLevelTextBaselines = addon._ufNameLevelTextBaselines or {}
			local function ensureBossBaseline(fs, key, fallbackFrame)
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

				local function hasTextCustomization(cfgT)
					if not cfgT then return false end
					if cfgT.fontFace ~= nil and cfgT.fontFace ~= "" and cfgT.fontFace ~= "FRIZQT__" then return true end
					if cfgT.size ~= nil or cfgT.style ~= nil then return true end
					if cfgT.colorMode ~= nil and cfgT.colorMode ~= "" and cfgT.colorMode ~= "default" then return true end
					if cfgT.color ~= nil then return true end
					if cfgT.offset and (cfgT.offset.x ~= nil or cfgT.offset.y ~= nil) then
						local ox = tonumber(cfgT.offset.x) or 0
						local oy = tonumber(cfgT.offset.y) or 0
						if ox ~= 0 or oy ~= 0 then return true end
					end
					return false
				end
				if not hasTextCustomization(styleCfg) then return end

				local face = addon.ResolveFontFace and addon.ResolveFontFace(styleCfg.fontFace or "FRIZQT__") or (select(1, _G.GameFontNormal:GetFont()))
				local size = tonumber(styleCfg.size) or 14
				local outline = tostring(styleCfg.style or "OUTLINE")
				local fst = ensureFS()
				if fst then fst.SetProp(fs, "applyingFont", true) end
				if addon.ApplyFontStyle then addon.ApplyFontStyle(fs, face, size, outline) elseif fs.SetFont then pcall(fs.SetFont, fs, face, size, outline) end
				if fst then fst.SetProp(fs, "applyingFont", nil) end

				-- Boss frames: no class color option. Treat "class" as "default".
				local colorMode = styleCfg.colorMode or "default"
				if colorMode == "class" then colorMode = "default" end

				local c
				if colorMode == "custom" then
					c = styleCfg.color or { 1.0, 0.82, 0.0, 1 }
				else
					-- Default: match the Name/Level Text default behavior (yellow).
					c = styleCfg.color or { 1.0, 0.82, 0.0, 1 }
				end
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

			local function applyBossBackdrop(main, hb, index)
				-- Reuse the same DB keys as other unit frames (nameBackdrop*).
				local holderKey = "ScootNameBackdrop_Boss" .. tostring(index)
				local mainState = getState(main)
				local existingTex = mainState and mainState[holderKey] or nil

				local configured = (
					cfg.nameBackdropEnabled ~= nil
					or cfg.nameBackdropTexture ~= nil
					or cfg.nameBackdropColorMode ~= nil
					or cfg.nameBackdropTint ~= nil
					or cfg.nameBackdropOpacity ~= nil
					or cfg.nameBackdropWidthPct ~= nil
				)
				if not configured then
					if existingTex then existingTex:Hide() end
					return
				end

				local texKey = cfg.nameBackdropTexture or ""
				local enabledBackdrop = not not cfg.nameBackdropEnabled
				local colorMode = cfg.nameBackdropColorMode or "default" -- default | texture | custom
				local tint = cfg.nameBackdropTint or { 1, 1, 1, 1 }
				local opacity = tonumber(cfg.nameBackdropOpacity) or 50
				if opacity < 0 then opacity = 0 elseif opacity > 100 then opacity = 100 end
				local opacityAlpha = opacity / 100
				local resolvedPath = addon.Media and addon.Media.ResolveBarTexturePath and addon.Media.ResolveBarTexturePath(texKey)

				local tex = existingTex
				if main and not tex then
					tex = main:CreateTexture(nil, "BACKGROUND", nil, -8)
					if mainState then mainState[holderKey] = tex end
				end
				if not tex then return end

				if hb and resolvedPath and enabledBackdrop then
					addon._ufNameBackdropBaseWidth = addon._ufNameBackdropBaseWidth or {}
					local baseKey = "Boss" .. tostring(index)
					local base = tonumber(addon._ufNameBackdropBaseWidth[baseKey])
					if not base or base <= 0 then
						base = safeGetWidth(hb)
						if base and base > 0 then
							addon._ufNameBackdropBaseWidth[baseKey] = base
						end
					end
					-- If the width can't be safely read a width (secret-value environment), skip cosmetics.
					if not base or base <= 0 then
						tex:Hide()
						return
					end
					local wPct = tonumber(cfg.nameBackdropWidthPct) or 100
					if wPct < 25 then wPct = 25 elseif wPct > 300 then wPct = 300 end
					local desiredWidth = math.max(1, math.floor((base * wPct / 100) + 0.5))

					tex:ClearAllPoints()
					-- Boss frames align right; grow left from the portrait side (match Target/Focus behavior).
					tex:SetPoint("BOTTOMRIGHT", hb, "TOPRIGHT", 0, 0)
					tex:SetSize(desiredWidth, 16)
					tex:SetTexture(resolvedPath)
					if tex.SetDrawLayer then tex:SetDrawLayer("BACKGROUND", -8) end
					if tex.SetHorizTile then tex:SetHorizTile(false) end
					if tex.SetVertTile then tex:SetVertTile(false) end
					if tex.SetTexCoord then tex:SetTexCoord(0, 1, 0, 1) end

					local r, g, b = 1, 1, 1
					if colorMode == "texture" then
						r, g, b = 1, 1, 1
					elseif colorMode == "default" then
						r, g, b = 0, 0, 0
					elseif colorMode == "custom" and type(tint) == "table" then
						r, g, b = tint[1] or 1, tint[2] or 1, tint[3] or 1
					end
					if tex.SetVertexColor then tex:SetVertexColor(r, g, b, 1) end
					if tex.SetAlpha then tex:SetAlpha(opacityAlpha) end
					tex:Show()
				else
					tex:Hide()
				end
			end

			local function applyBossBackdropBorder(main, hb, index)
				local borderKey = "ScootNameBackdropBorder_Boss" .. tostring(index)
				local mainState = getState(main)
				local existingBorderFrame = mainState and mainState[borderKey] or nil

				local configured = (
					cfg.nameBackdropBorderEnabled ~= nil
					or cfg.nameBackdropBorderStyle ~= nil
					or cfg.nameBackdropBorderThickness ~= nil
					or cfg.nameBackdropBorderInset ~= nil
					or cfg.nameBackdropBorderInsetH ~= nil
					or cfg.nameBackdropBorderInsetV ~= nil
					or cfg.nameBackdropBorderTintEnable ~= nil
					or cfg.nameBackdropBorderTintColor ~= nil
					or cfg.useCustomBorders ~= nil
					or cfg.nameBackdropEnabled ~= nil
					or cfg.nameBackdropTexture ~= nil
					or cfg.nameBackdropWidthPct ~= nil
				)
				if not configured then
					if existingBorderFrame then
						if addon.Borders and addon.Borders.HideAll then addon.Borders.HideAll(existingBorderFrame) end
						if existingBorderFrame.SetBackdrop then pcall(existingBorderFrame.SetBackdrop, existingBorderFrame, nil) end
						existingBorderFrame:Hide()
					end
					return
				end

				local styleKey = cfg.nameBackdropBorderStyle or "square"
				local localEnabled = not not cfg.nameBackdropBorderEnabled
				local globalEnabled = not not cfg.useCustomBorders
				local useBorders = localEnabled and globalEnabled
				local thickness = tonumber(cfg.nameBackdropBorderThickness) or 1
				if thickness < 1 then thickness = 1 elseif thickness > 16 then thickness = 16 end
				local insetH = tonumber(cfg.nameBackdropBorderInsetH) or tonumber(cfg.nameBackdropBorderInset) or 0
				local insetV = tonumber(cfg.nameBackdropBorderInsetV) or tonumber(cfg.nameBackdropBorderInset) or 0
				if insetH < -8 then insetH = -8 elseif insetH > 8 then insetH = 8 end
				if insetV < -8 then insetV = -8 elseif insetV > 8 then insetV = 8 end
				local tintEnabled = not not cfg.nameBackdropBorderTintEnable
				local tintColor = cfg.nameBackdropBorderTintColor or { 1, 1, 1, 1 }

				local borderFrame = existingBorderFrame
				if main and not borderFrame then
					local template = BackdropTemplateMixin and "BackdropTemplate" or nil
					borderFrame = CreateFrame("Frame", nil, main, template)
					if mainState then mainState[borderKey] = borderFrame end
				end
				if not borderFrame then return end

				if hb and useBorders then
					addon._ufNameBackdropBaseWidth = addon._ufNameBackdropBaseWidth or {}
					local baseKey = "Boss" .. tostring(index)
					local base = tonumber(addon._ufNameBackdropBaseWidth[baseKey])
					if not base or base <= 0 then
						base = safeGetWidth(hb)
						if base and base > 0 then
							addon._ufNameBackdropBaseWidth[baseKey] = base
						end
					end
					-- If the width can't be safely read a width (secret-value environment), skip cosmetics.
					if not base or base <= 0 then
						borderFrame:Hide()
						return
					end
					local wPct = tonumber(cfg.nameBackdropWidthPct) or 100
					if wPct < 25 then wPct = 25 elseif wPct > 300 then wPct = 300 end
					local desiredWidth = math.max(1, math.floor((base * wPct / 100) + 0.5))

					borderFrame:ClearAllPoints()
					borderFrame:SetPoint("BOTTOMRIGHT", hb, "TOPRIGHT", 0, 0)
					borderFrame:SetSize(desiredWidth, 16)

					local styleDef = addon.BarBorders and addon.BarBorders.GetStyle and addon.BarBorders.GetStyle(styleKey) or nil
					local styleTexture = styleDef and styleDef.texture or nil
					local thicknessScale = (styleDef and styleDef.thicknessScale) or 1.0
					local DEFAULT_REF = 18
					local DEFAULT_MULT = 1.35
					local h = (borderFrame.GetHeight and borderFrame:GetHeight()) or 16
					if h < 1 then h = DEFAULT_REF end
					local edgeSize = math.floor((thickness * DEFAULT_MULT * thicknessScale * (h / DEFAULT_REF)) + 0.5)
					if edgeSize < 1 then edgeSize = 1 elseif edgeSize > 48 then edgeSize = 48 end

					if styleKey == "square" or not styleTexture then
						if borderFrame.SetBackdrop then pcall(borderFrame.SetBackdrop, borderFrame, nil) end
						if addon.Borders and addon.Borders.HideAll then addon.Borders.HideAll(borderFrame) end
						if addon.Borders and addon.Borders.ApplySquare then
							addon.Borders.ApplySquare(borderFrame, {
								size = edgeSize,
								color = tintEnabled and (tintColor or { 1, 1, 1, 1 }) or { 1, 1, 1, 1 },
								layer = "OVERLAY",
								layerSublevel = 7,
								expandX = -(insetH),
								expandY = -(insetV),
							})
						end
						borderFrame:Show()
					else
						if addon.Borders and addon.Borders.HideAll then addon.Borders.HideAll(borderFrame) end
						local ok = false
						if borderFrame.SetBackdrop then
							local insetPxH = math.max(0, math.floor(edgeSize * 0.65 + 0.5) + insetH)
							local insetPxV = math.max(0, math.floor(edgeSize * 0.65 + 0.5) + insetV)
							local bd = {
								bgFile = nil,
								edgeFile = styleTexture,
								tile = false,
								edgeSize = edgeSize,
								insets = { left = insetPxH, right = insetPxH, top = insetPxV, bottom = insetPxV },
							}
							ok = pcall(borderFrame.SetBackdrop, borderFrame, bd)
						end
						if ok and borderFrame.SetBackdropBorderColor then
							local c = tintEnabled and tintColor or { 1, 1, 1, 1 }
							borderFrame:SetBackdropBorderColor(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
						end
						if not ok then
							borderFrame:Hide()
						else
							borderFrame:Show()
						end
					end
				else
					if addon.Borders and addon.Borders.HideAll then addon.Borders.HideAll(borderFrame) end
					if borderFrame.SetBackdrop then pcall(borderFrame.SetBackdrop, borderFrame, nil) end
					borderFrame:Hide()
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
				if main then
					applyBossBackdrop(main, hb, i)
					applyBossBackdropBorder(main, hb, i)
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

			for i = 1, 5 do
				applyBossIndex(i)
			end
			return
		end

		local frame = getUnitFrameFor(unit)
		if not frame then return end

		-- Resolve Name and Level FontStrings
		local nameFS, levelFS
		
	-- Try direct child access first (most common)
	if unit == "Player" then
		nameFS = _G.PlayerName
		levelFS = _G.PlayerLevelText
	elseif unit == "Target" then
		-- Target uses nested content structure
		local targetFrame = _G.TargetFrame
		if targetFrame and targetFrame.TargetFrameContent and targetFrame.TargetFrameContent.TargetFrameContentMain then
			nameFS = targetFrame.TargetFrameContent.TargetFrameContentMain.Name
			levelFS = targetFrame.TargetFrameContent.TargetFrameContentMain.LevelText
		end
	elseif unit == "Focus" then
		-- Focus reuses Target's content structure naming (TargetFrameContent, not FocusFrameContent!)
		local focusFrame = _G.FocusFrame
		if focusFrame and focusFrame.TargetFrameContent and focusFrame.TargetFrameContent.TargetFrameContentMain then
			nameFS = focusFrame.TargetFrameContent.TargetFrameContentMain.Name
			levelFS = focusFrame.TargetFrameContent.TargetFrameContentMain.LevelText
		end
	elseif unit == "Pet" then
		-- Pet uses global FontString names (PetName is a direct global, not nested)
		nameFS = _G.PetName
		-- Pet frame doesn't have a LevelText FontString (no level display)
		levelFS = nil
	end

		-- Fallback: search by name hints
		if not nameFS then nameFS = findFontStringByNameHint(frame, "Name") end
		if not levelFS then levelFS = findFontStringByNameHint(frame, "LevelText") end

		-- Apply visibility only when explicitly configured.
		-- Name/Level text are NOT StatusBar children, so SetShown is safe here.
		if nameFS and nameFS.SetShown and cfg.nameTextHidden ~= nil then
			pcall(nameFS.SetShown, nameFS, not cfg.nameTextHidden)
		end
		if levelFS and levelFS.SetShown and cfg.levelTextHidden ~= nil then
			pcall(levelFS.SetShown, levelFS, not cfg.levelTextHidden)
		end

		-- Apply styling
		addon._ufNameLevelTextBaselines = addon._ufNameLevelTextBaselines or {}
		local function ensureBaseline(fs, key)
			addon._ufNameLevelTextBaselines[key] = addon._ufNameLevelTextBaselines[key] or {}
			local b = addon._ufNameLevelTextBaselines[key]
			if b.point == nil then
				if fs and fs.GetPoint then
					local p, relTo, rp, x, y = fs:GetPoint(1)
					b.point = p or "CENTER"
					b.relTo = relTo or (fs.GetParent and fs:GetParent()) or frame
					b.relPoint = rp or b.point
					b.x = safeOffset(x)
					b.y = safeOffset(y)
				else
					b.point, b.relTo, b.relPoint, b.x, b.y = "CENTER", (fs and fs.GetParent and fs:GetParent()) or frame, "CENTER", 0, 0
				end
			end
			return b
		end

		-- Optional: widen the name container for Target/Focus to reduce truncation.
		-- This adjusts the Name FontString's width and anchor so the right edge
		-- stays aligned relative to the ReputationColor strip while growing left.
		-- NOTE: This function MUST incorporate the configured offset values because it
		-- runs AFTER applyTextStyle() and overwrites the position set there.
		addon._ufNameContainerBaselines = addon._ufNameContainerBaselines or {}
		local function applyNameContainerWidth(unitKey, nameFSLocal)
			if not nameFSLocal then return end
			-- Only Target/Focus currently support this control; Player/Pet keep stock behavior.
			if unitKey ~= "Target" and unitKey ~= "Focus" then return end

			local unitCfg = unitFrames and rawget(unitFrames, unitKey) or nil
			local styleCfg = unitCfg and rawget(unitCfg, "textName") or nil
			if not styleCfg then
				return
			end
			-- Zero‑Touch: only touch width/anchors if the user explicitly configured this slider.
			if styleCfg.containerWidthPct == nil then
				return
			end
			local pct = tonumber(styleCfg.containerWidthPct) or 100

			-- Clamp slider semantics to [80,150] (matches UI slider).
			if pct < 80 then pct = 80 elseif pct > 150 then pct = 150 end

			-- Read configured offset values (same as applyTextStyle uses)
			local configOffsetX = (styleCfg.offset and tonumber(styleCfg.offset.x)) or 0
			local configOffsetY = (styleCfg.offset and tonumber(styleCfg.offset.y)) or 0

			local key = unitKey .. ":nameContainer"
			local baseline = addon._ufNameContainerBaselines[key]
			if not baseline then
				baseline = {}
				baseline.width = safeGetWidth(nameFSLocal) or 90
				if nameFSLocal.GetPoint then
					local p, relTo, rp, x, y = nameFSLocal:GetPoint(1)
					baseline.point = p or "TOPLEFT"
					baseline.relTo = relTo or (nameFSLocal.GetParent and nameFSLocal:GetParent()) or frame
					baseline.relPoint = rp or baseline.point
					baseline.x = safeOffset(x)
					baseline.y = safeOffset(y)
				else
					baseline.point, baseline.relTo, baseline.relPoint, baseline.x, baseline.y =
						"TOPLEFT", (nameFSLocal.GetParent and nameFSLocal:GetParent()) or frame, "TOPLEFT", 0, 0
				end
				addon._ufNameContainerBaselines[key] = baseline
			end

			-- Read configured alignment (Target/Focus only)
			local alignment = styleCfg.alignment or "LEFT"

			-- Helper to force FontString redraw after alignment change
			local function forceTextRedraw(fs)
				if fs and fs.GetText and fs.SetText then
					local txt = fs:GetText()
					if txt then
						fs:SetText("")
						fs:SetText(txt)
					end
				end
			end

			-- When at 100%, restore original width/anchor (with offset) and bail.
			if pct == 100 then
				if nameFSLocal.ClearAllPoints and nameFSLocal.SetPoint and baseline.width then
					nameFSLocal:SetWidth(baseline.width)
					-- Apply text alignment within the container
					if nameFSLocal.SetJustifyH then
						pcall(nameFSLocal.SetJustifyH, nameFSLocal, alignment)
					end
					nameFSLocal:ClearAllPoints()
					nameFSLocal:SetPoint(
						baseline.point or "TOPLEFT",
						baseline.relTo or (nameFSLocal.GetParent and nameFSLocal:GetParent()) or frame,
						baseline.relPoint or baseline.point or "TOPLEFT",
						(baseline.x or 0) + configOffsetX,
						(baseline.y or 0) + configOffsetY
					)
					-- Force redraw to apply alignment visually
					forceTextRedraw(nameFSLocal)
				end
				return
			end

			local baseWidth = baseline.width or safeGetWidth(nameFSLocal) or 90
			local newWidth = math.floor((baseWidth * pct / 100) + 0.5)

			-- Default behavior: scale the width and preserve left anchor.
			local point, relTo, relPoint, xOff, yOff =
				baseline.point, baseline.relTo, baseline.relPoint, baseline.x, baseline.y

			-- If the canonical ReputationColor strip is found, keep right margin stable
			-- by nudging the TOPLEFT X offset leftwards as width grows.
			local main = resolveUFContentMain_NLT(unitKey)
			local rep = main and main.ReputationColor or nil
			if rep and relTo == rep and (point == "TOPLEFT" or point == "LEFT") then
				-- Right edge offset remains unchanged; only the left edge moves.
				local delta = newWidth - baseWidth
				xOff = (xOff or 0) - delta
			end

			if nameFSLocal.SetWidth then
				nameFSLocal:SetWidth(newWidth)
			end
			-- Apply text alignment within the container
			if nameFSLocal.SetJustifyH then
				pcall(nameFSLocal.SetJustifyH, nameFSLocal, alignment)
			end
			if nameFSLocal.ClearAllPoints and nameFSLocal.SetPoint then
				nameFSLocal:ClearAllPoints()
				nameFSLocal:SetPoint(
					point or "TOPLEFT",
					relTo or (nameFSLocal.GetParent and nameFSLocal:GetParent()) or frame,
					relPoint or point or "TOPLEFT",
					(xOff or 0) + configOffsetX,
					(yOff or 0) + configOffsetY
				)
			end
			-- Force redraw to apply alignment visually
			forceTextRedraw(nameFSLocal)
		end

	local function applyTextStyle(fs, styleCfg, baselineKey)
		if not fs or not styleCfg then return end
		-- Default/clean profiles should not modify Blizzard text.
		-- Only treat settings as "customized" if they differ from structural defaults.
		local function hasTextCustomization(cfgT)
			if not cfgT then return false end
			if cfgT.fontFace ~= nil and cfgT.fontFace ~= "" and cfgT.fontFace ~= "FRIZQT__" then
				return true
			end
			if cfgT.size ~= nil or cfgT.style ~= nil then
				return true
			end
			-- Name/Level uses colorMode; only treat as customized if not default.
			if cfgT.colorMode ~= nil and cfgT.colorMode ~= "" and cfgT.colorMode ~= "default" then
				return true
			end
			if cfgT.color ~= nil then
				return true
			end
			if cfgT.offset and (cfgT.offset.x ~= nil or cfgT.offset.y ~= nil) then
				local ox = tonumber(cfgT.offset.x) or 0
				local oy = tonumber(cfgT.offset.y) or 0
				if ox ~= 0 or oy ~= 0 then
					return true
				end
			end
			return false
		end
		if not hasTextCustomization(styleCfg) then
			return
		end
		local face = addon.ResolveFontFace and addon.ResolveFontFace(styleCfg.fontFace or "FRIZQT__") or (select(1, _G.GameFontNormal:GetFont()))
		local size = tonumber(styleCfg.size) or 14
		local outline = tostring(styleCfg.style or "OUTLINE")
		-- Set flag to prevent the SetFont hook from triggering a reapply loop
		local fst = ensureFS()
		if fst then fst.SetProp(fs, "applyingFont", true) end
		if addon.ApplyFontStyle then addon.ApplyFontStyle(fs, face, size, outline) elseif fs.SetFont then pcall(fs.SetFont, fs, face, size, outline) end
		if fst then fst.SetProp(fs, "applyingFont", nil) end
		-- Determine color based on colorMode
		local c = nil
		local colorMode = styleCfg.colorMode or "default"
		if colorMode == "class" then
			-- Class Color: use player's class color
			if addon.GetClassColorRGB then
				local unitForClass = unit == "Player" and "player" or (unit == "Target" and "target" or (unit == "Focus" and "focus" or "pet"))
				local cr, cg, cb = addon.GetClassColorRGB(unitForClass)
				c = { cr or 1, cg or 1, cb or 1, 1 }
			else
				c = {1.0, 0.82, 0.0, 1} -- fallback to default yellow
			end
		elseif colorMode == "custom" then
			-- Custom: use stored color
			c = styleCfg.color or {1.0, 0.82, 0.0, 1}
		else
			-- Default: use Blizzard's default yellow color (1.0, 0.82, 0.0) instead of white
			c = styleCfg.color or {1.0, 0.82, 0.0, 1}
		end
		if fs.SetTextColor then pcall(fs.SetTextColor, fs, c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1) end

		-- Only reposition if offset is explicitly configured.
		-- This prevents Apply All Fonts (which only sets fontFace) from inadvertently changing
		-- text positioning.
		local hasOffsetCustomization = styleCfg.offset and (styleCfg.offset.x ~= nil or styleCfg.offset.y ~= nil)
		if hasOffsetCustomization then
			local ox = tonumber(styleCfg.offset.x) or 0
			local oy = tonumber(styleCfg.offset.y) or 0
			if fs.ClearAllPoints and fs.SetPoint then
				local b = ensureBaseline(fs, baselineKey)
				fs:ClearAllPoints()
				local point = safePointToken(b.point, "CENTER")
				local relTo = b.relTo or (fs.GetParent and fs:GetParent()) or frame
				local relPoint = safePointToken(b.relPoint, point)
				local x = safeOffset(b.x) + ox
				local y = safeOffset(b.y) + oy
				local ok = pcall(fs.SetPoint, fs, point, relTo, relPoint, x, y)
				if not ok then
					local parent = (fs.GetParent and fs:GetParent()) or frame
					pcall(fs.SetPoint, fs, point, parent, relPoint, 0, 0)
				end
			end
		end
	end

	if nameFS then
		applyTextStyle(nameFS, cfg.textName or {}, unit .. ":name")
		-- Apply optional name container width adjustment (Target/Focus only).
		applyNameContainerWidth(unit, nameFS)

		-- For Target/Focus name text with class color, Blizzard resets the color on target change.
		-- Install hooks to immediately re-apply the class color, preventing visible flash.
		if (unit == "Target" or unit == "Focus") and cfg.textName and cfg.textName.colorMode == "class" then
			local nameState = getState(nameFS)
			local unitFrame = unit == "Target" and _G.TargetFrame or _G.FocusFrame

			-- Hook SetTextColor on the FontString to catch color changes during target switches
			if nameState and not nameState.textColorHooked then
				nameState.textColorHooked = true

				hooksecurefunc(nameFS, "SetTextColor", function(self, r, g, b, a)
					-- Guard against recursion since SetTextColor is called inside the hook
					local st = getState(self)
					if st and st.applyingTextColor then return end

					-- Check if class color is configured for this unit
					local db = addon and addon.db and addon.db.profile
					local unitKey = unit -- captured from outer scope
					local unitCfg = db and db.unitFrames and db.unitFrames[unitKey]
					local textNameCfg = unitCfg and unitCfg.textName

					if textNameCfg and textNameCfg.colorMode == "class" and addon.GetClassColorRGB then
						local unitToken = unitKey == "Target" and "target" or "focus"
						local cr, cg, cb = addon.GetClassColorRGB(unitToken)
						if cr and cg and cb then
							-- Re-apply the class color (overrides what Blizzard just set)
							if st then st.applyingTextColor = true end
							pcall(self.SetTextColor, self, cr, cg, cb, 1)
							if st then st.applyingTextColor = nil end
						end
					end
					-- If class color not configured, Blizzard's color remains (hook does nothing)
				end)
			end

			-- Hook the unit frame's OnShow to catch the "frame freshly drawn" case.
			-- When going from no target to having a target, the frame shows and unit data
			-- may not be available during the initial SetTextColor call.
			-- Strategy: Hide the name text immediately on show, apply the color, then reveal it.
			-- This prevents any flash of the wrong color.
			local frameState = getState(unitFrame)
			if unitFrame and frameState and not frameState.onShowClassColorHooked then
				frameState.onShowClassColorHooked = true

				unitFrame:HookScript("OnShow", function(self)
					local db = addon and addon.db and addon.db.profile
					local unitKey = unit
					local unitCfg = db and db.unitFrames and db.unitFrames[unitKey]
					local textNameCfg = unitCfg and unitCfg.textName

					if textNameCfg and textNameCfg.colorMode == "class" and nameFS then
						-- Hide the name text immediately to prevent flash
						pcall(nameFS.SetAlpha, nameFS, 0)

						-- Defer to next frame to ensure unit data is available, then apply color and reveal
						C_Timer.After(0, function()
							if addon.GetClassColorRGB then
								local unitToken = unitKey == "Target" and "target" or "focus"
								local cr, cg, cb = addon.GetClassColorRGB(unitToken)
								if cr and cg and cb and nameFS.SetTextColor then
									local st = getState(nameFS)
									if st then st.applyingTextColor = true end
									pcall(nameFS.SetTextColor, nameFS, cr, cg, cb, 1)
									if st then st.applyingTextColor = nil end
								end
							end
							-- Reveal the name text with correct color
							pcall(nameFS.SetAlpha, nameFS, 1)
						end)
					end
				end)
			end
		end
	end
	if levelFS then 
		applyTextStyle(levelFS, cfg.textLevel or {}, unit .. ":level")
		
		-- For Player level text, Blizzard uses SetVertexColor (not SetTextColor!) which requires special handling
		-- Blizzard constantly resets the level color, so hooksecurefunc re-applies the custom color
		-- CRITICAL: hooksecurefunc avoids taint. Method overrides cause taint that spreads
		-- through the execution context, blocking protected functions like SetTargetClampingInsets().
		if unit == "Player" and levelFS then
			-- Install hook once (hooksecurefunc runs AFTER Blizzard's SetVertexColor)
			local levelState = getState(levelFS)
			if levelState and not levelState.vertexColorHooked then
				levelState.vertexColorHooked = true
				
				hooksecurefunc(levelFS, "SetVertexColor", function(self, r, g, b, a)
					-- Guard against recursion since SetVertexColor is called inside the hook
					local st = getState(self)
					if st and st.applyingVertexColor then return end
					
					-- Check if a custom color is configured
					local db = addon and addon.db and addon.db.profile
					if db and db.unitFrames and db.unitFrames.Player and db.unitFrames.Player.textLevel and db.unitFrames.Player.textLevel.color then
						local c = db.unitFrames.Player.textLevel.color
						-- Re-apply the custom color (overrides what Blizzard just set)
						if st then st.applyingVertexColor = true end
						pcall(self.SetVertexColor, self, c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
						if st then st.applyingVertexColor = nil end
					end
					-- If no custom color configured, Blizzard's color remains (hook does nothing)
				end)
			end
			
			-- Apply the custom color immediately if configured
			if cfg.textLevel and cfg.textLevel.color then
				local c = cfg.textLevel.color
				local st = getState(levelFS)
				if st then st.applyingVertexColor = true end
				pcall(levelFS.SetVertexColor, levelFS, c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
				if st then st.applyingVertexColor = nil end
			end
		end
	end
		-- Name Backdrop: texture strip anchored to top edge of the Health Bar at the lowest z-order
		do
			local main = resolveUFContentMain_NLT(unit)
			local hb = resolveHealthBar_NLT(unit)
			local holderKey = "ScootNameBackdrop_" .. tostring(unit)
			local mainState = getState(main)
			local existingTex = mainState and mainState[holderKey] or nil

			-- Zero‑Touch: only create/manage the backdrop texture when this feature has been configured.
			local configured = (
				cfg.nameBackdropEnabled ~= nil
				or cfg.nameBackdropTexture ~= nil
				or cfg.nameBackdropColorMode ~= nil
				or cfg.nameBackdropTint ~= nil
				or cfg.nameBackdropOpacity ~= nil
				or cfg.nameBackdropWidthPct ~= nil
			)
			if not configured then
				-- If the texture exists from earlier in this session/profile, hide it.
				if existingTex then existingTex:Hide() end
			else
			local texKey = cfg.nameBackdropTexture or ""
			-- Default to disabled backdrop unless explicitly enabled in the profile.
			local enabledBackdrop = not not cfg.nameBackdropEnabled
			local colorMode = cfg.nameBackdropColorMode or "default" -- default | texture | custom
			local tint = cfg.nameBackdropTint or {1,1,1,1}
			local opacity = tonumber(cfg.nameBackdropOpacity) or 50
			if opacity < 0 then opacity = 0 elseif opacity > 100 then opacity = 100 end
			local opacityAlpha = opacity / 100
			local resolvedPath = addon.Media and addon.Media.ResolveBarTexturePath and addon.Media.ResolveBarTexturePath(texKey)
			local tex = existingTex
			if main and not tex then
				tex = main:CreateTexture(nil, "BACKGROUND", nil, -8)
				if mainState then mainState[holderKey] = tex end
			end
			if tex then
				if hb and resolvedPath and enabledBackdrop then
					-- Compute a baseline width per-session (do NOT persist baselines into SavedVariables).
					addon._ufNameBackdropBaseWidth = addon._ufNameBackdropBaseWidth or {}
					local base = tonumber(addon._ufNameBackdropBaseWidth[unit])
					if not base or base <= 0 then
						base = safeGetWidth(hb)
						if base and base > 0 then
							addon._ufNameBackdropBaseWidth[unit] = base
						end
					end
					-- If the width can't be safely read a width (secret-value environment), skip cosmetics.
					if not base or base <= 0 then
						tex:Hide()
						return
					end
					local wPct = tonumber(cfg.nameBackdropWidthPct) or 100
					if wPct < 25 then wPct = 25 elseif wPct > 300 then wPct = 300 end
					local desiredWidth = math.max(1, math.floor((base * wPct / 100) + 0.5))
					tex:ClearAllPoints()
					-- Anchor to RIGHT edge for Target/Focus so the strip grows left from the portrait side
					if unit == "Target" or unit == "Focus" then
						tex:SetPoint("BOTTOMRIGHT", hb, "TOPRIGHT", 0, 0)
					else
						tex:SetPoint("BOTTOMLEFT", hb, "TOPLEFT", 0, 0)
					end
					tex:SetSize(desiredWidth, 16)
					tex:SetTexture(resolvedPath)
					if tex.SetDrawLayer then tex:SetDrawLayer("BACKGROUND", -8) end
					if tex.SetHorizTile then tex:SetHorizTile(false) end
					if tex.SetVertTile then tex:SetVertTile(false) end
					if tex.SetTexCoord then tex:SetTexCoord(0,1,0,1) end
					-- Color behavior mirrors bar backgrounds:
					--  - texture  => preserve original colors (white vertex)
					--  - default  => use default background color (black)
					--  - custom   => use tint (including alpha)
					do
						local r, g, b = 1, 1, 1
						if colorMode == "texture" then
							r, g, b = 1, 1, 1
						elseif colorMode == "default" then
							-- Unit frame default background is black
							r, g, b = 0, 0, 0
						elseif colorMode == "custom" and type(tint) == "table" then
							r, g, b = tint[1] or 1, tint[2] or 1, tint[3] or 1
						end
						if tex.SetVertexColor then tex:SetVertexColor(r, g, b, 1) end
						if tex.SetAlpha then tex:SetAlpha(opacityAlpha) end
					end
					tex:Show()
				else
					tex:Hide()
				end
			end
			end -- configured
		end
		-- Name Backdrop Border: draw a border around the same region
		do
			local main = resolveUFContentMain_NLT(unit)
			local hb = resolveHealthBar_NLT(unit)
			local borderKey = "ScootNameBackdropBorder_" .. tostring(unit)
			local mainState = getState(main)
			local existingBorderFrame = mainState and mainState[borderKey] or nil

			-- Zero‑Touch: only create/manage the border when this feature has been configured.
			local configured = (
				cfg.nameBackdropBorderEnabled ~= nil
				or cfg.nameBackdropBorderStyle ~= nil
				or cfg.nameBackdropBorderThickness ~= nil
				or cfg.nameBackdropBorderInset ~= nil
				or cfg.nameBackdropBorderInsetH ~= nil
				or cfg.nameBackdropBorderInsetV ~= nil
				or cfg.nameBackdropBorderTintEnable ~= nil
				or cfg.nameBackdropBorderTintColor ~= nil
				or cfg.useCustomBorders ~= nil
				or cfg.nameBackdropEnabled ~= nil
				or cfg.nameBackdropTexture ~= nil
				or cfg.nameBackdropWidthPct ~= nil
			)
			if not configured then
				-- If the border frame exists from earlier in this session/profile, hide and clear it.
				if existingBorderFrame then
					if addon.Borders and addon.Borders.HideAll then addon.Borders.HideAll(existingBorderFrame) end
					if existingBorderFrame.SetBackdrop then pcall(existingBorderFrame.SetBackdrop, existingBorderFrame, nil) end
					existingBorderFrame:Hide()
				end
			else
			local styleKey = cfg.nameBackdropBorderStyle or "square"
			-- Align border gating with UI defaults: disabled until explicitly enabled.
			local localEnabled = not not cfg.nameBackdropBorderEnabled
			local globalEnabled = not not cfg.useCustomBorders
			local useBorders = localEnabled and globalEnabled
			local thickness = tonumber(cfg.nameBackdropBorderThickness) or 1
			if thickness < 1 then thickness = 1 elseif thickness > 16 then thickness = 16 end
			local insetH = tonumber(cfg.nameBackdropBorderInsetH) or tonumber(cfg.nameBackdropBorderInset) or 0
			local insetV = tonumber(cfg.nameBackdropBorderInsetV) or tonumber(cfg.nameBackdropBorderInset) or 0
			if insetH < -8 then insetH = -8 elseif insetH > 8 then insetH = 8 end
			if insetV < -8 then insetV = -8 elseif insetV > 8 then insetV = 8 end
			local tintEnabled = not not cfg.nameBackdropBorderTintEnable
			local tintColor = cfg.nameBackdropBorderTintColor or {1,1,1,1}

			local borderFrame = existingBorderFrame
			if main and not borderFrame then
				local template = BackdropTemplateMixin and "BackdropTemplate" or nil
				borderFrame = CreateFrame("Frame", nil, main, template)
				if mainState then mainState[borderKey] = borderFrame end
			end
			if borderFrame and hb and useBorders then
				-- Match border width to the same baseline-derived width as backdrop
				addon._ufNameBackdropBaseWidth = addon._ufNameBackdropBaseWidth or {}
				local base = tonumber(addon._ufNameBackdropBaseWidth[unit])
				if not base or base <= 0 then
					base = safeGetWidth(hb)
					if base and base > 0 then
						addon._ufNameBackdropBaseWidth[unit] = base
					end
				end
				-- If the width can't be safely read a width (secret-value environment), skip cosmetics.
				if not base or base <= 0 then
					borderFrame:Hide()
					return
				end
				local wPct = tonumber(cfg.nameBackdropWidthPct) or 100
				if wPct < 25 then wPct = 25 elseif wPct > 300 then wPct = 300 end
				local desiredWidth = math.max(1, math.floor((base * wPct / 100) + 0.5))
				borderFrame:ClearAllPoints()
				-- Anchor to RIGHT edge for Target/Focus so the border grows left from the portrait side
				if unit == "Target" or unit == "Focus" then
					borderFrame:SetPoint("BOTTOMRIGHT", hb, "TOPRIGHT", 0, 0)
				else
					borderFrame:SetPoint("BOTTOMLEFT", hb, "TOPLEFT", 0, 0)
				end
				borderFrame:SetSize(desiredWidth, 16)
				local styleDef = addon.BarBorders and addon.BarBorders.GetStyle and addon.BarBorders.GetStyle(styleKey) or nil
				local styleTexture = styleDef and styleDef.texture or nil
				local thicknessScale = (styleDef and styleDef.thicknessScale) or 1.0
				local DEFAULT_REF = 18
				local DEFAULT_MULT = 1.35
				local h = (borderFrame.GetHeight and borderFrame:GetHeight()) or 16
				if h < 1 then h = DEFAULT_REF end
				local edgeSize = math.floor((thickness * DEFAULT_MULT * thicknessScale * (h / DEFAULT_REF)) + 0.5)
				if edgeSize < 1 then edgeSize = 1 elseif edgeSize > 48 then edgeSize = 48 end

				if styleKey == "square" or not styleTexture then
					-- Clear any previous backdrop-based border before applying square edges
					if borderFrame.SetBackdrop then pcall(borderFrame.SetBackdrop, borderFrame, nil) end
					if addon.Borders and addon.Borders.HideAll then addon.Borders.HideAll(borderFrame) end
					if addon.Borders and addon.Borders.ApplySquare then
						addon.Borders.ApplySquare(borderFrame, {
							size = edgeSize,
							color = tintEnabled and (tintColor or {1,1,1,1}) or {1,1,1,1},
							layer = "OVERLAY",
							layerSublevel = 7,
							expandX = -(insetH),
							expandY = -(insetV),
						})
					end
					borderFrame:Show()
				else
					-- Clear any previous square edges before applying a backdrop-based border
					if addon.Borders and addon.Borders.HideAll then addon.Borders.HideAll(borderFrame) end
					local ok = false
					if borderFrame.SetBackdrop then
						local insetPxH = math.max(0, math.floor(edgeSize * 0.65 + 0.5) + insetH)
						local insetPxV = math.max(0, math.floor(edgeSize * 0.65 + 0.5) + insetV)
						local bd = {
							bgFile = nil,
							edgeFile = styleTexture,
							tile = false,
							edgeSize = edgeSize,
							insets = { left = insetPxH, right = insetPxH, top = insetPxV, bottom = insetPxV },
						}
						ok = pcall(borderFrame.SetBackdrop, borderFrame, bd)
					end
					if ok and borderFrame.SetBackdropBorderColor then
						local c = tintEnabled and tintColor or {1,1,1,1}
						borderFrame:SetBackdropBorderColor(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
					end
					if not ok then
						borderFrame:Hide()
					else
						borderFrame:Show()
					end
				end
			elseif borderFrame then
				-- Fully clear both border types on disable
				if addon.Borders and addon.Borders.HideAll then addon.Borders.HideAll(borderFrame) end
				if borderFrame.SetBackdrop then pcall(borderFrame.SetBackdrop, borderFrame, nil) end
				borderFrame:Hide()
			end
			end -- configured
		end
	end

	function addon.ApplyUnitFrameNameLevelTextFor(unit)
		applyForUnit(unit)
	end

	function addon.ApplyAllUnitFrameNameLevelText()
		applyForUnit("Player")
		applyForUnit("Target")
		applyForUnit("Focus")
		applyForUnit("Pet")
		applyForUnit("Boss")
	end

	-- Hook TargetFrame_Update, FocusFrame_Update, and Player frame update functions
	-- to reapply name/level text styling (including visibility and alignment) after
	-- Blizzard's updates reset properties.
	--
	-- IMPORTANT (pop-in): Reapply immediately (same frame) to avoid visible
	-- "flash" when acquiring a target. hooksecurefunc already runs AFTER Blizzard's
	-- update completes, so an additional one-frame defer is not required for correctness.
	-- A second reapply is optionally scheduled on the next tick as a safety net.
	local _nameLevelTextHooksInstalled = false
	local function installNameLevelTextHooks()
		if _nameLevelTextHooksInstalled then return end
		_nameLevelTextHooksInstalled = true

		local function reapply(unit)
			if not addon.ApplyUnitFrameNameLevelTextFor then return end
			-- Immediate enforcement (prevents pop-in)
			addon.ApplyUnitFrameNameLevelTextFor(unit)
			-- One-tick backup in case a later same-frame Blizzard update path overrides us
			if _G.C_Timer and _G.C_Timer.After then
				_G.C_Timer.After(0, function()
					if addon.ApplyUnitFrameNameLevelTextFor then
						addon.ApplyUnitFrameNameLevelTextFor(unit)
					end
				end)
			end
		end

		-- Player frame hooks: PlayerFrame_Update and PlayerFrame_UpdateRolesAssigned
		-- can reset level text visibility. Hook both to ensure custom settings persist.
		if _G.hooksecurefunc then
			-- PlayerFrame_Update calls PlayerFrame_UpdateLevel which sets the level text
			if type(_G.PlayerFrame_Update) == "function" then
				_G.hooksecurefunc("PlayerFrame_Update", function()
					reapply("Player")
				end)
			end
			
			-- PlayerFrame_UpdateRolesAssigned directly sets PlayerLevelText:SetShown()
			if type(_G.PlayerFrame_UpdateRolesAssigned) == "function" then
				_G.hooksecurefunc("PlayerFrame_UpdateRolesAssigned", function()
					reapply("Player")
				end)
			end
			
			-- PlayerFrame_ToPlayerArt is called when switching from vehicle to player
			if type(_G.PlayerFrame_ToPlayerArt) == "function" then
				_G.hooksecurefunc("PlayerFrame_ToPlayerArt", function()
					reapply("Player")
				end)
			end
		end

		if _G.hooksecurefunc and type(_G.TargetFrame_Update) == "function" then
			_G.hooksecurefunc("TargetFrame_Update", function()
				if isEditModeActive() then return end
				reapply("Target")
			end)
		end

		if _G.hooksecurefunc and type(_G.FocusFrame_Update) == "function" then
			_G.hooksecurefunc("FocusFrame_Update", function()
				if isEditModeActive() then return end
				reapply("Focus")
			end)
		end
	end

	-- Install hooks on first style application
	local _origApplyAll = addon.ApplyAllUnitFrameNameLevelText
	addon.ApplyAllUnitFrameNameLevelText = function()
		-- Zero‑Touch: only install persistence hooks when Name/Level/Backdrop is actually configured.
		local db = addon and addon.db and addon.db.profile
		local unitFrames = db and rawget(db, "unitFrames") or nil
		local function hasAnyOffset(tbl)
			local off = tbl and tbl.offset
			return off and (off.x ~= nil or off.y ~= nil) or false
		end
		local function unitHasNameLevelConfig(unit)
			local cfg = unitFrames and rawget(unitFrames, unit) or nil
			if not cfg then return false end
			if cfg.nameTextHidden ~= nil or cfg.levelTextHidden ~= nil then return true end
			if cfg.nameBackdropEnabled ~= nil
				or cfg.nameBackdropTexture ~= nil
				or cfg.nameBackdropColorMode ~= nil
				or cfg.nameBackdropTint ~= nil
				or cfg.nameBackdropOpacity ~= nil
				or cfg.nameBackdropWidthPct ~= nil
				or cfg.nameBackdropBorderEnabled ~= nil
				or cfg.nameBackdropBorderStyle ~= nil
				or cfg.nameBackdropBorderThickness ~= nil
				or cfg.nameBackdropBorderInset ~= nil
				or cfg.nameBackdropBorderInsetH ~= nil
				or cfg.nameBackdropBorderInsetV ~= nil
				or cfg.nameBackdropBorderTintEnable ~= nil
				or cfg.nameBackdropBorderTintColor ~= nil
				or cfg.useCustomBorders ~= nil
			then
				return true
			end
			local tn = rawget(cfg, "textName")
			if tn and (tn.fontFace ~= nil or tn.size ~= nil or tn.style ~= nil or tn.colorMode ~= nil or tn.color ~= nil or tn.alignment ~= nil or tn.containerWidthPct ~= nil or hasAnyOffset(tn)) then
				return true
			end
			local tl = rawget(cfg, "textLevel")
			if tl and (tl.fontFace ~= nil or tl.size ~= nil or tl.style ~= nil or tl.colorMode ~= nil or tl.color ~= nil or hasAnyOffset(tl)) then
				return true
			end
			return false
		end
		if unitHasNameLevelConfig("Player") or unitHasNameLevelConfig("Target") or unitHasNameLevelConfig("Focus") or unitHasNameLevelConfig("Pet") or unitHasNameLevelConfig("Boss") then
			installNameLevelTextHooks()
		end
		_origApplyAll()
	end
end

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
		local fstate = ensureFS()
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
		local fstate = ensureFS()
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
	local hookFrame = CreateFrame("Frame")
	hookFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
	hookFrame:SetScript("OnEvent", function(self, event)
		if event == "PLAYER_ENTERING_WORLD" then
			-- Defer to ensure CharacterFrame is loaded
			if _G.C_Timer and _G.C_Timer.After then
				_G.C_Timer.After(1, function()
					hookCharacterFrameOnShow()
				end)
			end
		end
	end)

	-- Hook PaperDollFrame.VisibilityUpdated event for reliable reapplication
	-- This fires when the Character Pane (PaperDollFrame) is shown or hidden
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
-- Target of Target: Name Text Styling
-- The ToT frame only has a Name FontString, no health/power/level text.
--------------------------------------------------------------------------------
do
	-- Resolve ToT Name FontString
	local function resolveToTNameFS()
		local tot = _G.TargetFrameToT
		return tot and tot.Name or nil
	end

	-- Baseline storage for ToT Name text
	addon._ufToTNameTextBaseline = addon._ufToTNameTextBaseline or {}

	-- Apply ToT Name Text styling
	local function applyToTNameText()
		local db = addon and addon.db and addon.db.profile
		if not db then return end
		-- Zero‑Touch: do not create config tables. If ToT has no config, do nothing.
		local unitFrames = rawget(db, "unitFrames")
		local cfg = unitFrames and rawget(unitFrames, "TargetOfTarget") or nil
		if not cfg then return end
		local styleCfg = rawget(cfg, "textName")

		local nameFS = resolveToTNameFS()
		if not nameFS then return end

		-- Zero‑Touch: if neither visibility nor style is configured, do nothing.
		local function hasAnyOffset(tbl)
			local off = tbl and tbl.offset
			return off and (off.x ~= nil or off.y ~= nil) or false
		end
		local function hasTextCustomization(tbl)
			if not tbl then return false end
			if tbl.fontFace ~= nil and tbl.fontFace ~= "" and tbl.fontFace ~= "FRIZQT__" then return true end
			if tbl.size ~= nil or tbl.style ~= nil or tbl.colorMode ~= nil or tbl.color ~= nil or tbl.alignment ~= nil then return true end
			if hasAnyOffset(tbl) then return true end
			return false
		end
		local hasVisibilitySetting = (cfg.nameTextHidden ~= nil)
		local hasStyleSetting = hasTextCustomization(styleCfg)
		if not hasVisibilitySetting and not hasStyleSetting then
			return
		end

		-- Apply visibility: tri‑state (nil=no touch) via SetAlpha (combat-safe)
		-- NOTE: Uses FrameState to avoid writing properties directly to Blizzard frames (causes taint).
		local fstate = ensureFS()
		if cfg.nameTextHidden ~= nil and fstate then
			local hidden = (cfg.nameTextHidden == true)
			if hidden then
				if nameFS.SetAlpha then pcall(nameFS.SetAlpha, nameFS, 0) end
				fstate.SetHidden(nameFS, "totName", true)
				-- Install hook to re-enforce hidden state
				if not fstate.IsHooked(nameFS, "totNameVisibility") then
					fstate.MarkHooked(nameFS, "totNameVisibility")
					if _G.hooksecurefunc then
						_G.hooksecurefunc(nameFS, "SetText", function(self)
							local st = ensureFS()
							if st and st.IsHidden(self, "totName") and self.SetAlpha then
								pcall(self.SetAlpha, self, 0)
							end
						end)
						_G.hooksecurefunc(nameFS, "Show", function(self)
							local st = ensureFS()
							if st and st.IsHidden(self, "totName") and self.SetAlpha then
								pcall(self.SetAlpha, self, 0)
							end
						end)
					end
				end
			else
				fstate.SetHidden(nameFS, "totName", false)
				if nameFS.SetAlpha then pcall(nameFS.SetAlpha, nameFS, 1) end
			end
		end

		-- Skip styling if hidden
		if cfg.nameTextHidden == true then return end
		-- Zero‑Touch: only apply font/position/style if explicitly customized.
		if not hasStyleSetting then
			return
		end

		-- Capture baseline position once
		local function ensureBaseline()
			if not addon._ufToTNameTextBaseline.point then
				if nameFS and nameFS.GetPoint then
					local p, relTo, rp, x, y = nameFS:GetPoint(1)
					addon._ufToTNameTextBaseline.point = p or "TOPLEFT"
					addon._ufToTNameTextBaseline.relTo = relTo or (nameFS.GetParent and nameFS:GetParent())
					addon._ufToTNameTextBaseline.relPoint = rp or addon._ufToTNameTextBaseline.point
					addon._ufToTNameTextBaseline.x = safeOffset(x)
					addon._ufToTNameTextBaseline.y = safeOffset(y)
				else
					addon._ufToTNameTextBaseline.point = "TOPLEFT"
					addon._ufToTNameTextBaseline.relTo = nameFS and nameFS.GetParent and nameFS:GetParent()
					addon._ufToTNameTextBaseline.relPoint = "TOPLEFT"
					addon._ufToTNameTextBaseline.x = 0
					addon._ufToTNameTextBaseline.y = 0
				end
			end
			return addon._ufToTNameTextBaseline
		end

		-- Apply font styling
		local face = addon.ResolveFontFace and addon.ResolveFontFace((styleCfg and styleCfg.fontFace) or "FRIZQT__") or (select(1, _G.GameFontNormal:GetFont()))
		local size = tonumber(styleCfg and styleCfg.size) or 10
		local outline = tostring((styleCfg and styleCfg.style) or "OUTLINE")
		if addon.ApplyFontStyle then
			addon.ApplyFontStyle(nameFS, face, size, outline)
		elseif nameFS.SetFont then
			pcall(nameFS.SetFont, nameFS, face, size, outline)
		end

		-- Apply color based on colorMode
		local colorMode = (styleCfg and styleCfg.colorMode) or "default"
		local r, g, b, a = 1, 1, 1, 1
		if colorMode == "class" then
			-- Class color: use target-of-target's class color
			if addon.GetClassColorRGB then
				local cr, cg, cb = addon.GetClassColorRGB("targettarget")
				r, g, b, a = cr or 1, cg or 1, cb or 1, 1
			end
		elseif colorMode == "custom" then
			local c = (styleCfg and styleCfg.color) or {1, 1, 1, 1}
			r, g, b, a = c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
		else
			-- Default: use Blizzard default (white for ToT name)
			r, g, b, a = 1, 1, 1, 1
		end
		if nameFS.SetTextColor then pcall(nameFS.SetTextColor, nameFS, r, g, b, a) end

		-- Apply alignment
		local alignment = (styleCfg and styleCfg.alignment) or "LEFT"
		if nameFS.SetJustifyH then pcall(nameFS.SetJustifyH, nameFS, alignment) end

		-- Apply offset relative to baseline
		local ox = tonumber(styleCfg and styleCfg.offset and styleCfg.offset.x) or 0
		local oy = tonumber(styleCfg and styleCfg.offset and styleCfg.offset.y) or 0
		if nameFS.ClearAllPoints and nameFS.SetPoint then
			local b = ensureBaseline()
			nameFS:ClearAllPoints()
			local point = safePointToken(b.point, "TOPLEFT")
			local relTo = b.relTo or (nameFS.GetParent and nameFS:GetParent())
			local relPoint = safePointToken(b.relPoint, point)
			local x = safeOffset(b.x) + ox
			local y = safeOffset(b.y) + oy
			local ok = pcall(nameFS.SetPoint, nameFS, point, relTo, relPoint, x, y)
			if not ok then
				local parent = (nameFS.GetParent and nameFS:GetParent())
				pcall(nameFS.SetPoint, nameFS, point, parent, relPoint, 0, 0)
			end
		end
	end

	-- Expose for UI and Copy From
	addon.ApplyToTNameText = applyToTNameText

	-- Hook TargetofTarget frame updates to reapply styling
	-- ToT frame is re-shown when target changes, so hook the ToT OnShow
	-- NOTE: Uses FrameState to avoid writing properties directly to Blizzard frames (causes taint).
	local function installToTHooks()
		local fstate = ensureFS()
		if not fstate then return end
		local tot = _G.TargetFrameToT
		if tot and not fstate.IsHooked(tot, "nameTextHooked") then
			fstate.MarkHooked(tot, "nameTextHooked")
			if tot.HookScript then
				tot:HookScript("OnShow", function()
					if _G.C_Timer and _G.C_Timer.After then
						_G.C_Timer.After(0, applyToTNameText)
					end
				end)
			end
		end
	end

	-- Install hooks after PLAYER_ENTERING_WORLD
	local totHookFrame = CreateFrame("Frame")
	totHookFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
	totHookFrame:SetScript("OnEvent", function(self, event)
		if event == "PLAYER_ENTERING_WORLD" then
			if _G.C_Timer and _G.C_Timer.After then
				_G.C_Timer.After(0.5, function()
					installToTHooks()
					-- Apply initial styling
					applyToTNameText()
				end)
			end
		end
	end)
end

--------------------------------------------------------------------------------
-- Focus Target: Name Text Styling
-- The FoT frame only has a Name FontString, no health/power/level text.
-- Uses identical template to ToT (TargetofTargetFrameTemplate).
--------------------------------------------------------------------------------
do
	local function resolveFoTNameFS()
		local fot = _G.FocusFrameToT
		return fot and fot.Name or nil
	end

	addon._ufFoTNameTextBaseline = addon._ufFoTNameTextBaseline or {}

	local function applyFoTNameText()
		local db = addon and addon.db and addon.db.profile
		if not db then return end
		db.unitFrames = db.unitFrames or {}
		db.unitFrames.FocusTarget = db.unitFrames.FocusTarget or {}
		local cfg = db.unitFrames.FocusTarget
		cfg.textName = cfg.textName or {}
		local styleCfg = cfg.textName

		local nameFS = resolveFoTNameFS()
		if not nameFS then return end

		-- Zero‑Touch: if neither visibility nor style is configured, do nothing.
		local function hasAnyOffset(tbl)
			local off = tbl and tbl.offset
			return off and (off.x ~= nil or off.y ~= nil) or false
		end
		local function hasTextCustomization(tbl)
			if not tbl then return false end
			if tbl.fontFace ~= nil and tbl.fontFace ~= "" and tbl.fontFace ~= "FRIZQT__" then return true end
			if tbl.size ~= nil or tbl.style ~= nil or tbl.colorMode ~= nil or tbl.color ~= nil or tbl.alignment ~= nil then return true end
			if hasAnyOffset(tbl) then return true end
			return false
		end
		local hasVisibilitySetting = (cfg.nameTextHidden ~= nil)
		local hasStyleSetting = hasTextCustomization(styleCfg)
		if not hasVisibilitySetting and not hasStyleSetting then
			return
		end

		-- Apply visibility: tri‑state (nil=no touch) via SetAlpha (combat-safe)
		-- NOTE: Uses FrameState to avoid writing properties directly to Blizzard frames (causes taint).
		local fstate = ensureFS()
		if cfg.nameTextHidden ~= nil and fstate then
			local hidden = (cfg.nameTextHidden == true)
			if hidden then
				if nameFS.SetAlpha then pcall(nameFS.SetAlpha, nameFS, 0) end
				fstate.SetHidden(nameFS, "fotName", true)
				-- Install hook to re-enforce hidden state
				if not fstate.IsHooked(nameFS, "fotNameVisibility") then
					fstate.MarkHooked(nameFS, "fotNameVisibility")
					if _G.hooksecurefunc then
						_G.hooksecurefunc(nameFS, "SetText", function(self)
							local st = ensureFS()
							if st and st.IsHidden(self, "fotName") and self.SetAlpha then
								pcall(self.SetAlpha, self, 0)
							end
						end)
						_G.hooksecurefunc(nameFS, "Show", function(self)
							local st = ensureFS()
							if st and st.IsHidden(self, "fotName") and self.SetAlpha then
								pcall(self.SetAlpha, self, 0)
							end
						end)
					end
				end
			else
				fstate.SetHidden(nameFS, "fotName", false)
				if nameFS.SetAlpha then pcall(nameFS.SetAlpha, nameFS, 1) end
			end
		end

		-- Skip styling if hidden
		if cfg.nameTextHidden == true then return end
		-- Zero‑Touch: only apply font/position/style if explicitly customized.
		if not hasStyleSetting then
			return
		end

		-- Capture baseline position once
		local function ensureBaseline()
			if not addon._ufFoTNameTextBaseline.point then
				if nameFS and nameFS.GetPoint then
					local p, relTo, rp, x, y = nameFS:GetPoint(1)
					addon._ufFoTNameTextBaseline.point = p or "TOPLEFT"
					addon._ufFoTNameTextBaseline.relTo = relTo or (nameFS.GetParent and nameFS:GetParent())
					addon._ufFoTNameTextBaseline.relPoint = rp or addon._ufFoTNameTextBaseline.point
					addon._ufFoTNameTextBaseline.x = safeOffset(x)
					addon._ufFoTNameTextBaseline.y = safeOffset(y)
				else
					addon._ufFoTNameTextBaseline.point = "TOPLEFT"
					addon._ufFoTNameTextBaseline.relTo = nameFS and nameFS.GetParent and nameFS:GetParent()
					addon._ufFoTNameTextBaseline.relPoint = "TOPLEFT"
					addon._ufFoTNameTextBaseline.x = 0
					addon._ufFoTNameTextBaseline.y = 0
				end
			end
			return addon._ufFoTNameTextBaseline
		end

		-- Apply font styling
		local face = addon.ResolveFontFace and addon.ResolveFontFace((styleCfg and styleCfg.fontFace) or "FRIZQT__") or (select(1, _G.GameFontNormal:GetFont()))
		local size = tonumber(styleCfg and styleCfg.size) or 10
		local outline = tostring((styleCfg and styleCfg.style) or "OUTLINE")
		if addon.ApplyFontStyle then
			addon.ApplyFontStyle(nameFS, face, size, outline)
		elseif nameFS.SetFont then
			pcall(nameFS.SetFont, nameFS, face, size, outline)
		end

		-- Apply color based on colorMode
		local colorMode = (styleCfg and styleCfg.colorMode) or "default"
		local r, g, b, a = 1, 1, 1, 1
		if colorMode == "class" then
			-- Class color: use focus-target's class color
			if addon.GetClassColorRGB then
				local cr, cg, cb = addon.GetClassColorRGB("focustarget")
				r, g, b, a = cr or 1, cg or 1, cb or 1, 1
			end
		elseif colorMode == "custom" then
			local c = (styleCfg and styleCfg.color) or {1, 1, 1, 1}
			r, g, b, a = c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
		else
			-- Default: use Blizzard default (white for FoT name)
			r, g, b, a = 1, 1, 1, 1
		end
		if nameFS.SetTextColor then pcall(nameFS.SetTextColor, nameFS, r, g, b, a) end

		-- Apply alignment
		local alignment = (styleCfg and styleCfg.alignment) or "LEFT"
		if nameFS.SetJustifyH then pcall(nameFS.SetJustifyH, nameFS, alignment) end

		-- Apply offset relative to baseline
		local ox = tonumber(styleCfg and styleCfg.offset and styleCfg.offset.x) or 0
		local oy = tonumber(styleCfg and styleCfg.offset and styleCfg.offset.y) or 0
		if nameFS.ClearAllPoints and nameFS.SetPoint then
			local b = ensureBaseline()
			nameFS:ClearAllPoints()
			local point = safePointToken(b.point, "TOPLEFT")
			local relTo = b.relTo or (nameFS.GetParent and nameFS:GetParent())
			local relPoint = safePointToken(b.relPoint, point)
			local x = safeOffset(b.x) + ox
			local y = safeOffset(b.y) + oy
			local ok = pcall(nameFS.SetPoint, nameFS, point, relTo, relPoint, x, y)
			if not ok then
				local parent = (nameFS.GetParent and nameFS:GetParent())
				pcall(nameFS.SetPoint, nameFS, point, parent, relPoint, 0, 0)
			end
		end
	end

	-- Expose for UI and Copy From
	addon.ApplyFoTNameText = applyFoTNameText

	-- Hook FocusFrameToT frame updates to reapply styling
	-- FoT frame is re-shown when focus target changes, so hook the FoT OnShow
	-- NOTE: Uses FrameState to avoid writing properties directly to Blizzard frames (causes taint).
	local function installFoTHooks()
		local fstate = ensureFS()
		if not fstate then return end
		local fot = _G.FocusFrameToT
		if fot and not fstate.IsHooked(fot, "fotNameTextHooked") then
			fstate.MarkHooked(fot, "fotNameTextHooked")
			if fot.HookScript then
				fot:HookScript("OnShow", function()
					if _G.C_Timer and _G.C_Timer.After then
						_G.C_Timer.After(0, applyFoTNameText)
					end
				end)
			end
		end
	end

	-- Install hooks after PLAYER_ENTERING_WORLD
	local fotHookFrame = CreateFrame("Frame")
	fotHookFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
	fotHookFrame:SetScript("OnEvent", function(self, event)
		if event == "PLAYER_ENTERING_WORLD" then
			if _G.C_Timer and _G.C_Timer.After then
				_G.C_Timer.After(0.5, function()
					installFoTHooks()
					-- Apply initial styling
					applyFoTNameText()
				end)
			end
		end
	end)
end

--------------------------------------------------------------------------------
-- Edit Mode Exit Hook: Reapply text visibility when Edit Mode closes
--------------------------------------------------------------------------------
-- The SetAlpha visibility hooks skip enforcement during Edit Mode to avoid taint.
-- When Edit Mode closes, Blizzard may have shown text elements that should be hidden.
-- This hook re-enforces visibility settings after Edit Mode exits.
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

