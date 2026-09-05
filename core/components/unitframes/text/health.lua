--------------------------------------------------------------------------------
-- text/health.lua
-- Health text font styling, visibility enforcement, and positioning for all
-- unit frames (Player, Target, Focus, Boss, Pet, ToT, FocusTarget).
--------------------------------------------------------------------------------

local addonName, addon = ...

-- Health text opts for ResolveColorRGBA. The sniff pair keeps the historical
-- behavior: nil mode or an explicit "default" with a stored non-white color
-- applies that color; no barKind, so a class miss stays white, not green
local ufHealthTextColorOpts = { legacySniff = true, legacySniffDefault = true }

-- Font half and Zero-Touch gate opts for this file's value texts
local ufTextFontOpts = { size = 14 }
local ufTextCustomizationOpts = { alignment = true, alignmentMode = true }

-- Reference to FrameState module for safe property storage (avoids writing to Blizzard frames)
local FS = addon.FrameState

-- Secret-value safe helpers (shared module)
local SS = addon.SecretSafe
local safeOffset = SS.safeOffset
local safePointToken = SS.safePointToken
local safeGetWidth = SS.safeGetWidth

-- Cross-file import: NAME_ANCHOR_MAP (defined in text/core.lua, loaded first in TOC)
local NAME_ANCHOR_MAP = addon.UnitFrameText._NAME_ANCHOR_MAP

--Direct upvalue to the event-driven guard (editmode/core.lua loads first in TOC)
local isEditModeActive = addon.EditMode.IsEditModeActiveOrOpening

-- Hide-enforcement hooks (core/enforce.lua). The hidden flag stays in
-- FrameState, where the profile-switch reset in base/core.lua also clears it;
-- the keys read it live. Show and SetText re-assert at once, SetAlpha after a
-- stack break; every hook bails while Edit Mode is open.
local Enforce = addon.Enforce
local HEALTH_TEXT_OPTS = {
    methods = { "Show", "SetAlpha", "SetText" },
    timing = { SetAlpha = "defer" },
    skipInEditMode = true,
    when = function(fs) return FS.IsHidden(fs, "healthText") end,
}
local HEALTH_TEXT_CENTER_OPTS = {
    methods = { "SetText" },
    skipInEditMode = true,
    when = function(fs) return FS.IsHidden(fs, "healthTextCenter") end,
}

-- Unit Frames: Toggle Health % (LeftText) and Value (RightText) visibility per unit
do
    -- Cache for resolved health text fontstrings per unit so combat-time hooks stay cheap.
    addon._ufHealthTextFonts = addon._ufHealthTextFonts or {}

    local getUnitFrameFor = addon.GetUnitFrame

    --weak-key cache for health text FontString lookups
    local _htFSCache = setmetatable({}, { __mode = "k" })

    local function findFontStringByNameHint(root, hint)
        if not root then return nil end
        --check cache
        local rootCache = _htFSCache[root]
        if rootCache then
            local cached = rootCache[hint]
            if cached then return cached end
        end
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
        --cache non-nil results
        if target then
            if not _htFSCache[root] then
                _htFSCache[root] = {}
            end
            _htFSCache[root][hint] = target
        end
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

    -- Check whether the current player can have an Alternate Power Bar.
    -- DRUID is treated as class-capable (form/talent driven, not reliably spec-gated).
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
        local fs = FS
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

    -- Targeted zero-touch check for DeadText/UnconsciousText: only fontFace and style matter
    -- (color, alignment, offset are irrelevant: Blizzard's original values are kept).
    -- Deliberately narrower than addon.HasTextCustomization.
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

        local face = addon.ResolveFontFace(styleCfg.fontFace)
        local outline = styleCfg.style ~= nil and tostring(styleCfg.style) or (currentFlags or "")

        addon.ApplyFontStyle(fs, face, currentSize, outline)
    end

    -- Hook Show() on DeadText/UnconsciousText so font inheritance reapplies
    -- each time Blizzard's CheckDead() displays the text.
    local function hookDeadTextShow(fs, unit)
        if not fs then return end
        local fstate = FS
        if not fstate then return end
        if fstate.IsHooked(fs, "deadTextFontShow") then return end
        fstate.MarkHooked(fs, "deadTextFontShow")

        if _G.hooksecurefunc then
            -- Kept off addon.Enforce: not a hide; reapplies font inheritance when DeadText shows.
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
        if not addon.HasTextCustomization(styleCfg, ufTextCustomizationOpts) then
            return
        end

        addon.ApplyTextFont(fs, styleCfg, ufTextFontOpts)

        -- Resolve color based on colorMode
        local colorMode = styleCfg.colorMode or "default"
        -- Extract unit token from baselineKey (e.g., "Player:left" -> "player")
        local unitToken = baselineKey and baselineKey:match("^(.-):")
        if unitToken then unitToken = unitToken:lower() end
        if addon.IsValueColorMode(colorMode) then
            -- "Color by Value": use health-based color curve (secret-safe)
            if unitToken and addon.BarsTextures and addon.BarsTextures.applyHealthTextColor then
                addon.BarsTextures.applyHealthTextColor(fs, unitToken, colorMode == "valueDark")
            elseif fs.SetTextColor then
                pcall(fs.SetTextColor, fs, 0, 1, 0, 1) -- fallback green
            end
        else
            ufHealthTextColorOpts.unitForClass = unitToken or "player"
            local cr, cg, cb, ca = addon.ResolveColorRGBA(colorMode, styleCfg.color, ufHealthTextColorOpts)
            if fs.SetTextColor then
                pcall(fs.SetTextColor, fs, cr, cg, cb, ca)
            end
        end

        -- Only modify layout if alignment or offset is explicitly configured (avoids
        -- Apply All Fonts inadvertently changing text positioning).
        local hasLayoutCustomization = styleCfg.alignment ~= nil
            or styleCfg.alignmentMode ~= nil
            or (styleCfg.offset and (styleCfg.offset.x ~= nil or styleCfg.offset.y ~= nil))

        -- Ensure name-anchor reparenting is undone if layout customizations are removed
        if not hasLayoutCustomization then
            local fst = FS
            if fst then
                local origParent = fst.GetProp(fs, "nameAnchorOrigParent")
                if origParent and fs.SetParent then
                    pcall(fs.SetParent, fs, origParent)
                    local origLayer = fst.GetProp(fs, "nameAnchorOrigLayer") or "OVERLAY"
                    local origSub = fst.GetProp(fs, "nameAnchorOrigSublayer") or 1
                    pcall(fs.SetDrawLayer, fs, origLayer, origSub)
                    fst.SetProp(fs, "nameAnchorOrigParent", nil)
                    fst.SetProp(fs, "nameAnchorOrigLayer", nil)
                    fst.SetProp(fs, "nameAnchorOrigSublayer", nil)
                end
            end
        end

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

            -- Name-anchor mode: position text relative to boss name FontString
            local useNameAnchor = false
            if styleCfg.alignmentMode == "name" and baselineKey and baselineKey:find("^Boss") then
                local bossIdx = baselineKey:match("^Boss(%d+)")
                if bossIdx then
                    local bossFrame = addon.GetBossFrame(bossIdx)
                    local nameFS = bossFrame and addon.ResolveBossNameFS(bossFrame) or nil
                    if nameFS then
                        local anchorKey = styleCfg.nameAnchor or "RIGHT_OF_NAME"
                        local anchorInfo = NAME_ANCHOR_MAP[anchorKey]
                        if anchorInfo then
                            useNameAnchor = true
                            -- Reparent to contentMain so SetPoint can target nameFS (same hierarchy)
                            local contentMain = bossFrame.TargetFrameContent
                                and bossFrame.TargetFrameContent.TargetFrameContentMain
                            if contentMain and fs.SetParent then
                                local fst = FS
                                if fst and not fst.GetProp(fs, "nameAnchorOrigParent") then
                                    fst.SetProp(fs, "nameAnchorOrigParent", fs:GetParent())
                                    fst.SetProp(fs, "nameAnchorOrigLayer", select(1, fs:GetDrawLayer()))
                                    fst.SetProp(fs, "nameAnchorOrigSublayer", select(2, fs:GetDrawLayer()))
                                end
                                pcall(fs.SetParent, fs, contentMain)
                                pcall(fs.SetDrawLayer, fs, "OVERLAY", 7)
                            end
                            local textPt, namePt, justH, gapX, gapY = anchorInfo[1], anchorInfo[2], anchorInfo[3], anchorInfo[4], anchorInfo[5]
                            if fs.ClearAllPoints and fs.SetPoint then
                                fs:ClearAllPoints()
                                pcall(fs.SetPoint, fs, textPt, nameFS, namePt, gapX + ox, gapY + oy)
                            end
                            if fs.SetJustifyH then
                                pcall(fs.SetJustifyH, fs, justH)
                            end
                            -- Undo two-point width constraint — let text auto-size
                            if fs.SetWidth then
                                pcall(fs.SetWidth, fs, 0)
                            end
                            forceTextRedraw(fs)
                        end
                    end
                end
            end

            if not useNameAnchor then
                -- Restore original parent if previously reparented for name-anchor mode
                local fst = FS
                if fst then
                    local origParent = fst.GetProp(fs, "nameAnchorOrigParent")
                    if origParent and fs.SetParent then
                        pcall(fs.SetParent, fs, origParent)
                        local origLayer = fst.GetProp(fs, "nameAnchorOrigLayer") or "OVERLAY"
                        local origSub = fst.GetProp(fs, "nameAnchorOrigSublayer") or 1
                        pcall(fs.SetDrawLayer, fs, origLayer, origSub)
                        fst.SetProp(fs, "nameAnchorOrigParent", nil)
                        fst.SetProp(fs, "nameAnchorOrigLayer", nil)
                        fst.SetProp(fs, "nameAnchorOrigSublayer", nil)
                    end
                end

                -- Bar-relative mode: two-point anchoring to span the parent bar width.
                -- Makes JustifyH work correctly without needing GetWidth() (which can
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
    end

    local function applyForUnit(unit)
        if not addon:IsModuleEnabled("unitFrames", unit) then return end
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

        --reuse cached FontStrings if available (frame tree is stable)
        local leftFS, rightFS, textStringFS
        local existingCache = addon._ufHealthTextFonts[unit]
        if existingCache and existingCache.leftFS and existingCache.rightFS then
            leftFS = existingCache.leftFS
            rightFS = existingCache.rightFS
            textStringFS = existingCache.textStringFS
        else
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
            -- Ensures styling persists when Blizzard switches between BOTH and NUMERIC modes
            -- Character Pane shows HealthBarText instead of LeftText/RightText
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
        end

        -- Apply visibility using SetAlpha (combat-safe) instead of SetShown (taint-prone).
        -- Tri‑state: nil = don't touch; true = hide; false = show.
        local function applyHealthTextVisibility(fs, hiddenSetting, unitForHook)
            if not fs then return end
            local fstate = FS
            if not fstate then return end
            --Invalidate hot-path cache so settings changes propagate
            if fstate then fstate.ClearProp(fs, "healthTextAppliedHidden") end
            if hiddenSetting == nil then
                return
            end
            local hidden = (hiddenSetting == true)
            if hidden then
                if fs.SetAlpha then pcall(fs.SetAlpha, fs, 0) end
                Enforce.Install(fs, "healthText", HEALTH_TEXT_OPTS)
                fstate.SetHidden(fs, "healthText", true)
            else
                fstate.SetHidden(fs, "healthText", false)
                if fs.SetAlpha then pcall(fs.SetAlpha, fs, 1) end
            end
        end

        -- Apply current visibility once as part of the styling pass.
        applyHealthTextVisibility(leftFS, cfg.healthPercentHidden, unit)
        applyHealthTextVisibility(rightFS, cfg.healthValueHidden, unit)

        -- The center TextString: SetText re-asserts the hidden state only
        local fstate = FS
        Enforce.Install(textStringFS, "healthTextCenter", HEALTH_TEXT_CENTER_OPTS)

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

        for i = 1, addon.NUM_BOSS_FRAMES do
            local bossFrame = addon.GetBossFrame(i)
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

                addon._ufHealthTextFonts["Boss" .. tostring(i)] = {
                    leftFS = leftFS,
                    rightFS = rightFS,
                    textStringFS = centerFS,
                }

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
        if not addon:IsModuleEnabled("unitFrames", unit) then return end
        local db = addon and addon.db and addon.db.profile
        if not db then return end
        local unitFrames = rawget(db, "unitFrames")
        local cfg = unitFrames and rawget(unitFrames, unit) or nil
        if not cfg then
            return
        end
        --Zero-touch fast path — skip entirely when no visibility settings are configured
        if rawget(cfg, "healthPercentHidden") == nil and rawget(cfg, "healthValueHidden") == nil then return end

        -- Apply visibility using SetAlpha (combat-safe) instead of SetShown (taint-prone).
        -- Tri‑state: nil = don't touch; true = hide; false = show.
        local function applyVisibility(fs, hiddenSetting)
            if not fs then return end
            local fstate = FS
            if not fstate then return end
            if hiddenSetting == nil then
                return
            end
            --Skip if this visibility state is already applied
            local currentApplied = fstate.GetProp(fs, "healthTextAppliedHidden")
            if currentApplied == hiddenSetting then return end
            local hidden = (hiddenSetting == true)
            if hidden then
                if fs.SetAlpha then pcall(fs.SetAlpha, fs, 0) end
                Enforce.Install(fs, "healthText", HEALTH_TEXT_OPTS)
                fstate.SetHidden(fs, "healthText", true)
                fstate.SetProp(fs, "healthTextAppliedHidden", true)
            else
                fstate.SetHidden(fs, "healthText", false)
                if fs.SetAlpha then pcall(fs.SetAlpha, fs, 1) end
                fstate.SetProp(fs, "healthTextAppliedHidden", false)
            end
        end

        -- Boss frames: apply to Boss1..Boss5 deterministically (no cache dependency).
        if unit == "Boss" then
            for i = 1, addon.NUM_BOSS_FRAMES do
                local bossFrame = addon.GetBossFrame(i)
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

end
