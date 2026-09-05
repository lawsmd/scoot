--------------------------------------------------------------------------------
-- text/pipeline.lua
-- One pipeline for the health and power value texts. UFT._BuildTextPipeline
-- takes a kind descriptor (DB keys, FrameState keys, resolvers, and the forked
-- halves as functions) and returns the three appliers the descriptor file
-- assigns to its addon exports. The font cache and baseline store are indexed
-- through addon[name] on every call: base/core.lua replaces those tables on a
-- profile switch, so capturing one as an upvalue would go stale.
--------------------------------------------------------------------------------

local addonName, addon = ...

-- Reference to FrameState module for safe property storage (avoids writing to Blizzard frames)
local FS = addon.FrameState

-- Hide-enforcement hooks (core/enforce.lua); the opts tables come from the descriptor
local Enforce = addon.Enforce

-- Secret-value safe helpers (shared module)
local SS = addon.SecretSafe
local safeOffset = SS.safeOffset

-- Cross-file imports (defined in text/core.lua, loaded first in TOC)
local UFT = addon.UnitFrameText
local NAME_ANCHOR_MAP = UFT._NAME_ANCHOR_MAP
local findFontStringByNameHint = UFT._FindFontStringByNameHint
local forceTextRedraw = UFT._ForceTextRedraw

local getUnitFrameFor = addon.GetUnitFrame

function UFT._BuildTextPipeline(kind)
    -- Cache for resolved fontstrings per unit so combat-time hooks stay cheap,
    -- and the anchor baseline store. Owned by addon so the profile-switch reset
    -- in base/core.lua reaches both.
    addon[kind.fontCache] = addon[kind.fontCache] or {}
    addon[kind.baselineTable] = addon[kind.baselineTable] or {}

    -- Left, right, and center hidden settings from the profile, all tri-state
    -- (nil = don't touch; true = hide; false = show). A bar-hidden key in the
    -- descriptor overrides the individual toggles when set to true; the center
    -- setting mirrors the value toggle only when that toggle is configured.
    local function computeHidden(cfg)
        if kind.keys.barHidden and cfg[kind.keys.barHidden] == true then
            return true, true, true
        end
        local leftHidden = cfg[kind.keys.percentHidden]
        local rightHidden = cfg[kind.keys.valueHidden]
        local centerHidden = nil
        if rightHidden ~= nil then
            centerHidden = rightHidden
        end
        return leftHidden, rightHidden, centerHidden
    end

    -- Hook UpdateTextString to reapply visibility after Blizzard's updates.
    -- IMPORTANT: Use hooksecurefunc to avoid replacing the method and taint
    -- secure StatusBar instances used by Blizzard (Combat Log, unit frames, etc.).
    local function hookBarUpdateTextString(bar, unit)
        local fstate = FS
        if not bar or not fstate then return end
        if fstate.IsHooked(bar, kind.hookMarker) then return end
        fstate.MarkHooked(bar, kind.hookMarker)
        if _G.hooksecurefunc then
            _G.hooksecurefunc(bar, "UpdateTextString", function(self, ...)
                local fn = addon and addon[kind.visibilityForName]
                if fn then fn(unit) end
            end)
        end
    end

    local function ensureBaseline(fs, key, fallbackFrame)
        local store = addon[kind.baselineTable]
        store[key] = store[key] or {}
        local b = store[key]
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

    local function applyTextStyle(fs, styleCfg, baselineKey, fallbackFrame)
        if not fs or not styleCfg then return end
        if not addon.HasTextCustomization(styleCfg, kind.customizationOpts) then
            return
        end

        addon.ApplyTextFont(fs, styleCfg, kind.fontOpts)

        -- Color half: forked per resource, supplied by the descriptor
        kind.colorApplier(fs, styleCfg, baselineKey)

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
            -- Check for both :right and -right patterns to handle all unit types (Player:health-right, Boss1:health-right, etc.)
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
                            -- Undo two-point width constraint so the text auto-sizes
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
        -- Zero-Touch: do not create config tables. If this unit has no config, do nothing.
        local unitFrames = rawget(db, "unitFrames")
        local cfg = unitFrames and rawget(unitFrames, unit) or nil
        if not cfg then
            return
        end
        local frame = getUnitFrameFor(unit)
        if not frame then return end

        -- Resolve the bar and hook its UpdateTextString if not already hooked
        local bar = kind.barResolver(frame, unit)
        if bar then
            hookBarUpdateTextString(bar, unit)
        end

        --reuse cached FontStrings if available (frame tree is stable)
        local leftFS, rightFS, textStringFS
        local existingCache = addon[kind.fontCache][unit]
        if existingCache and existingCache.leftFS and existingCache.rightFS then
            leftFS = existingCache.leftFS
            rightFS = existingCache.rightFS
            textStringFS = existingCache.textStringFS
        else
            leftFS, rightFS = kind.directTexts(frame, unit)
            -- Full resolution path (may scan children/regions). This should only run during
            -- explicit styling passes (ApplyStyles), not on every text update.
            leftFS = leftFS
                or findFontStringByNameHint(frame, kind.hints.left[1])
                or findFontStringByNameHint(frame, kind.hints.left[2])
                or findFontStringByNameHint(frame, kind.hints.left[3])
            rightFS = rightFS
                or findFontStringByNameHint(frame, kind.hints.right[1])
                or findFontStringByNameHint(frame, kind.hints.right[2])
                or findFontStringByNameHint(frame, kind.hints.right[3])

            -- Also resolve the center TextString (used in NUMERIC display mode and Character Pane)
            -- Ensures styling persists when Blizzard switches between BOTH and NUMERIC modes
            textStringFS = kind.centerResolver(unit)

            -- Cache resolved fontstrings so combat-time hooks can avoid expensive scans.
            addon[kind.fontCache][unit] = {
                leftFS = leftFS,
                rightFS = rightFS,
                textStringFS = textStringFS,
            }
        end

        -- Apply visibility using SetAlpha (combat-safe) instead of SetShown (taint-prone).
        -- Tri-state: nil = don't touch; true = hide; false = show.
        local function applyStylingVisibility(fs, hiddenSetting)
            if not fs then return end
            local fstate = FS
            if not fstate then return end
            --Invalidate hot-path cache so settings changes propagate
            if fstate then fstate.ClearProp(fs, kind.appliedProp) end
            if hiddenSetting == nil then
                return
            end
            local hidden = (hiddenSetting == true)
            if hidden then
                if fs.SetAlpha then pcall(fs.SetAlpha, fs, 0) end
                Enforce.Install(fs, kind.hiddenKey, kind.textOpts)
                fstate.SetHidden(fs, kind.hiddenKey, true)
            else
                fstate.SetHidden(fs, kind.hiddenKey, false)
                if fs.SetAlpha then pcall(fs.SetAlpha, fs, 1) end
            end
        end

        -- Apply current visibility once as part of the styling pass.
        local leftHidden, rightHidden, centerHidden = computeHidden(cfg)
        applyStylingVisibility(leftFS, leftHidden)
        applyStylingVisibility(rightFS, rightHidden)

        -- The center TextString: SetText re-asserts the hidden state only
        local fstate = FS
        Enforce.Install(textStringFS, kind.hiddenCenterKey, kind.centerOpts)

        -- Descriptor hatch for idempotent settings migrations tied to this pass
        if kind.migrate then
            kind.migrate(cfg)
        end

        if leftFS then applyTextStyle(leftFS, cfg[kind.keys.percentStyle] or {}, unit .. ":" .. kind.slug .. "-left", frame) end
        if rightFS then applyTextStyle(rightFS, cfg[kind.keys.valueStyle] or {}, unit .. ":" .. kind.slug .. "-right", frame) end
        -- Style center TextString using Value settings (used in NUMERIC display mode and Character Pane)
        -- Always apply styling if text customizations exist; handle visibility separately
        if textStringFS then
            -- Handle visibility only when explicitly configured
            if centerHidden ~= nil then
                local valueHidden = (centerHidden == true)
                if valueHidden then
                    if textStringFS.SetAlpha then pcall(textStringFS.SetAlpha, textStringFS, 0) end
                    if fstate then fstate.SetHidden(textStringFS, kind.hiddenCenterKey, true) end
                else
                    if fstate and fstate.IsHidden(textStringFS, kind.hiddenCenterKey) then
                        if textStringFS.SetAlpha then pcall(textStringFS.SetAlpha, textStringFS, 1) end
                        fstate.SetHidden(textStringFS, kind.hiddenCenterKey, false)
                    end
                end
            end
            -- Always apply styling (applyTextStyle returns early if no customizations)
            if not (fstate and fstate.IsHidden(textStringFS, kind.hiddenCenterKey)) then
                applyTextStyle(textStringFS, cfg[kind.keys.valueStyle] or {}, unit .. ":" .. kind.slug .. "-center", frame)
            end
        end

        -- Descriptor hatch for per-unit work outside the shared shape
        if kind.applyForUnitExtras then
            kind.applyForUnitExtras(unit, cfg)
        end
    end

    -- Boss frames: styling for Boss1..Boss5. Boss frames are not returned by
    -- EditModeManagerFrame's UnitFrame system indices like Player/Target/Focus/Pet,
    -- so they are resolved deterministically using their global names.
    local function applyBossStyling()
        local db = addon and addon.db and addon.db.profile
        if not db then return end

        local unitFrames = rawget(db, "unitFrames")
        local cfg = unitFrames and rawget(unitFrames, "Boss") or nil
        if not cfg then
            return
        end

        for i = 1, addon.NUM_BOSS_FRAMES do
            local bossFrame = addon.GetBossFrame(i)
            local container = bossFrame and kind.bossContainer(bossFrame) or nil

            if container then
                local bar = kind.bossBar(container)
                if bar then
                    -- Ensure combat-time visibility enforcement exists for Boss texts
                    hookBarUpdateTextString(bar, "Boss")
                end

                local leftFS = container.LeftText
                local rightFS = container.RightText

                if leftFS then
                    applyTextStyle(leftFS, cfg[kind.keys.percentStyle] or {}, "Boss" .. tostring(i) .. ":" .. kind.slug .. "-left", container)
                end
                if rightFS then
                    applyTextStyle(rightFS, cfg[kind.keys.valueStyle] or {}, "Boss" .. tostring(i) .. ":" .. kind.slug .. "-right", container)
                end

                if kind.bossCenter then
                    local centerFS = kind.bossCenter(container)
                    if centerFS then
                        applyTextStyle(centerFS, cfg[kind.keys.valueStyle] or {}, "Boss" .. tostring(i) .. ":" .. kind.slug .. "-center", container)
                    end
                    -- Per-boss font cache; the shape (leftFS/rightFS/textStringFS) is read
                    -- outside this file, keep it stable.
                    addon[kind.fontCache]["Boss" .. tostring(i)] = {
                        leftFS = leftFS,
                        rightFS = rightFS,
                        textStringFS = centerFS,
                    }
                end

                if kind.bossExtras then
                    kind.bossExtras(container, cfg)
                end
            end
        end

        -- Apply visibility once as part of the styling pass.
        local fn = addon[kind.visibilityForName]
        if fn then fn("Boss") end
    end

    -- Lightweight visibility-only function used by UpdateTextString hooks.
    -- Uses SetAlpha instead of SetShown to avoid taint during combat.
    local function applyVisibilityFor(unit)
        if not addon:IsModuleEnabled("unitFrames", unit) then return end
        local db = addon and addon.db and addon.db.profile
        if not db then return end
        local unitFrames = rawget(db, "unitFrames")
        local cfg = unitFrames and rawget(unitFrames, unit) or nil
        if not cfg then
            return
        end
        --Zero-touch fast path: skip entirely when no visibility settings are configured
        local hasVisibilitySetting = rawget(cfg, kind.keys.percentHidden) ~= nil
            or rawget(cfg, kind.keys.valueHidden) ~= nil
            or (kind.keys.barHidden ~= nil and rawget(cfg, kind.keys.barHidden) ~= nil)
        if not hasVisibilitySetting then return end

        -- Apply visibility using SetAlpha (combat-safe) instead of SetShown (taint-prone).
        -- Tri-state: nil = don't touch; true = hide; false = show.
        local function applyVisibility(fs, hiddenSetting)
            if not fs then return end
            local fstate = FS
            if not fstate then return end
            if hiddenSetting == nil then
                return
            end
            --Skip if this visibility state is already applied
            local currentApplied = fstate.GetProp(fs, kind.appliedProp)
            if currentApplied == hiddenSetting then return end
            local hidden = (hiddenSetting == true)
            if hidden then
                if fs.SetAlpha then pcall(fs.SetAlpha, fs, 0) end
                Enforce.Install(fs, kind.hiddenKey, kind.textOpts)
                fstate.SetHidden(fs, kind.hiddenKey, true)
                fstate.SetProp(fs, kind.appliedProp, true)
            else
                fstate.SetHidden(fs, kind.hiddenKey, false)
                if fs.SetAlpha then pcall(fs.SetAlpha, fs, 1) end
                fstate.SetProp(fs, kind.appliedProp, false)
            end
        end

        local leftHidden, rightHidden = computeHidden(cfg)

        -- Boss frames: apply to Boss1..Boss5 deterministically (no cache dependency).
        if unit == "Boss" then
            for i = 1, addon.NUM_BOSS_FRAMES do
                local bossFrame = addon.GetBossFrame(i)
                local container = bossFrame and kind.bossContainer(bossFrame) or nil
                local leftFS = container and container.LeftText or nil
                local rightFS = container and container.RightText or nil
                applyVisibility(leftFS, leftHidden)
                applyVisibility(rightFS, rightHidden)
                if kind.bossCenter then
                    -- Center TextString is used in NUMERIC mode; treat it as Value Text for parity.
                    local centerFS = container and kind.bossCenter(container) or nil
                    applyVisibility(centerFS, rightHidden)
                end
            end
            return
        end

        local cache = addon[kind.fontCache][unit]
        local leftFS = cache and cache.leftFS or nil
        local rightFS = cache and cache.rightFS or nil
        if not (leftFS or rightFS) then
            -- Font cache miss: the first call after a profile switch wiped the
            -- cache, or before the first full pass. Resolve through the direct
            -- paths only; scanning, hooks, and styling stay in ApplyStyles.
            local frame = getUnitFrameFor(unit)
            if not frame then return end
            leftFS, rightFS = kind.directTexts(frame, unit)
            -- The profile-switch reset clears the hidden flags but not the
            -- applied props; clear them so the first apply is not skipped.
            local fstate = FS
            if fstate then
                if leftFS then fstate.ClearProp(leftFS, kind.appliedProp) end
                if rightFS then fstate.ClearProp(rightFS, kind.appliedProp) end
            end
            -- Cache only a complete set, matching what the styling pass builds;
            -- the center resolver is direct paths too. A partial result stays
            -- uncached so the next styling pass re-resolves in full.
            if leftFS and rightFS then
                addon[kind.fontCache][unit] = {
                    leftFS = leftFS,
                    rightFS = rightFS,
                    textStringFS = kind.centerResolver(unit),
                }
            end
        end

        applyVisibility(leftFS, leftHidden)
        applyVisibility(rightFS, rightHidden)
    end

    local function applyAll()
        applyForUnit("Player")
        applyForUnit("Target")
        applyForUnit("Focus")
        applyForUnit("Pet")
        applyBossStyling()
    end

    return {
        applyAll = applyAll,
        applyBossStyling = applyBossStyling,
        applyVisibilityFor = applyVisibilityFor,
    }
end
