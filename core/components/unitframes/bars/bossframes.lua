--------------------------------------------------------------------------------
-- bars/bossframes.lua
-- Boss1..Boss5 unit frame bar styling on the shared config db.unitFrames.Boss.
-- applyForBoss runs the whole Boss path that applyForUnit (bars.lua) used to
-- carry inline: the frame art enforcers, the ReputationColor pass with its
-- deferred re-hide, then the health and power bars with their borders, rect
-- overlays, and reapply hooks.
--------------------------------------------------------------------------------

local addonName, addon = ...

addon.BarsBossFrames = addon.BarsBossFrames or {}
local Boss = addon.BarsBossFrames

-- Boss bar opts for ResolveColorRGBA (hook-path scratch, fields set per call)
local bossBarColorOpts = {}

local Util = addon.ComponentsUtil
local Resolvers = addon.BarsResolvers
local Textures = addon.BarsTextures
local Alpha = addon.BarsAlpha
local BarsOverlays = addon.BarsOverlays
local Combat = addon.BarsCombat
local FS = addon.FrameState

-- Direct upvalue to the event-driven guard (editmode/core.lua loads first in TOC)
local isEditModeActive = addon.EditMode.IsEditModeActiveOrOpening

local resolveHealthBar = Resolvers.resolveHealthBar
local resolvePowerBar = Resolvers.resolvePowerBar
local resolveBossHealthMask = Resolvers.resolveBossHealthMask
local resolveBossPowerMask = Resolvers.resolveBossPowerMask
local resolveBossHealthBarsContainer = Resolvers.resolveBossHealthBarsContainer
local resolveBossManaBar = Resolvers.resolveBossManaBar
local applyToBar = Textures.applyToBar
local applyBackgroundToBar = Textures.applyBackgroundToBar
local hasBackgroundCustomization = Textures.hasBackgroundCustomization
local ensureMaskOnBarTexture = Textures.ensureMaskOnBarTexture
local applyAlpha = Alpha.applyAlpha
local hookAlphaEnforcer = Alpha.hookAlphaEnforcer
local customBordersAlpha = Alpha.customBordersAlpha
local ensureTextAndBorderOrdering = BarsOverlays._ensureTextAndBorderOrdering
local ensureBossRectOverlay = BarsOverlays._ensureBossRectOverlay
local queueUnitFrameTextureReapply = Combat.queueUnitFrameTextureReapply

local function getState(frame)
    return FS.Get(frame)
end

local function getProp(frame, key)
    local st = FS.Get(frame)
    return st and st[key] or nil
end

local function setProp(frame, key, value)
    local st = FS.Get(frame)
    if st then
        st[key] = value
    end
end

-- Called from applyForUnit (bars.lua) for unit "Boss" after its gates. The
-- three passes below run in the order applyForUnit ran them; cfg is
-- db.unitFrames.Boss.
function Boss.applyForBoss(cfg)
    local unit = "Boss"

    -- Boss unit frames commonly appear/update during combat (e.g., INSTANCE_ENCOUNTER_ENGAGE_UNIT / UPDATE_BOSS_FRAMES).
    -- IMPORTANT (taint): Even "cosmetic-only" writes to Boss unit frame regions (including SetAlpha on textures)
    -- can taint the Boss system and later block protected layout calls like BossTargetFrameContainer:SetSize().
    -- Do not mutate protected unit frame regions during combat. If Boss needs a re-assertion,
    -- queue a post-combat reapply instead.
    if InCombatLockdown and InCombatLockdown() then
        queueUnitFrameTextureReapply("Boss")
    else
        for i = 1, addon.NUM_BOSS_FRAMES do
            local bossFrame = addon.GetBossFrame(i)
            if bossFrame then
                -- FrameTexture (hide for useCustomBorders OR healthBarHideBorder)
                local bossFT = bossFrame.TargetFrameContainer and bossFrame.TargetFrameContainer.FrameTexture
                if bossFT then
                    local computeBossFTAlpha = customBordersAlpha("Boss", true)
                    applyAlpha(bossFT, computeBossFTAlpha())
                    hookAlphaEnforcer(bossFT, computeBossFTAlpha)
                end

                -- Flash (aggro/threat glow) (hide for useCustomBorders)
                local bossFlash = bossFrame.TargetFrameContainer and bossFrame.TargetFrameContainer.Flash
                if bossFlash then
                    local computeBossFlashAlpha = customBordersAlpha("Boss", false)
                    applyAlpha(bossFlash, computeBossFlashAlpha())
                    hookAlphaEnforcer(bossFlash, computeBossFlashAlpha)
                end

                -- ReputationColor strip (hide for useCustomBorders)
                local bossReputationColor = bossFrame.TargetFrameContent
                    and bossFrame.TargetFrameContent.TargetFrameContentMain
                    and bossFrame.TargetFrameContent.TargetFrameContentMain.ReputationColor
                if bossReputationColor then
                    local computeBossRepAlpha = customBordersAlpha("Boss", false)
                    applyAlpha(bossReputationColor, computeBossRepAlpha())
                    hookAlphaEnforcer(bossReputationColor, computeBossRepAlpha)
                end
            end
        end
    end

    -- Boss frames can also be updated by Blizzard during combat (boss target changes, etc.).
    -- Apply the same early ReputationColor handling pattern as Target/Focus: run BEFORE the combat
    -- early-return so the element stays hidden, with C_Timer follow-up to catch late Blizzard updates.
    local computeBossUseCustomBordersAlpha = customBordersAlpha("Boss", false)

    for i = 1, addon.NUM_BOSS_FRAMES do
        local bossFrame = addon.GetBossFrame(i)
        if bossFrame then
            local bossRepColor = bossFrame.TargetFrameContent
                and bossFrame.TargetFrameContent.TargetFrameContentMain
                and bossFrame.TargetFrameContent.TargetFrameContentMain.ReputationColor

            if bossRepColor then
                -- Always apply current alpha, regardless of hook state
                local desiredAlpha = computeBossUseCustomBordersAlpha()
                applyAlpha(bossRepColor, desiredAlpha)
                hookAlphaEnforcer(bossRepColor, computeBossUseCustomBordersAlpha)

                -- Belt-and-suspenders: schedule a follow-up re-hide after Blizzard's updates complete
                -- Catches cases where Blizzard resets alpha after the initial hide
                local bossIndex = i  -- Capture loop variable for closure
                _G.C_Timer.After(0, function()
                    -- Re-resolve in case the texture object changed
                    local bossFrame2 = addon.GetBossFrame(bossIndex)
                    local repColor2 = bossFrame2 and bossFrame2.TargetFrameContent
                        and bossFrame2.TargetFrameContent.TargetFrameContentMain
                        and bossFrame2.TargetFrameContent.TargetFrameContentMain.ReputationColor
                    if repColor2 and repColor2.SetAlpha then
                        local alpha2 = computeBossUseCustomBordersAlpha()
                        -- nil = config unreadable at this tick: skip the write
                        if alpha2 ~= nil then
                            pcall(repColor2.SetAlpha, repColor2, alpha2)
                        end
                        -- Install enforcer on the (possibly new) object
                        hookAlphaEnforcer(repColor2, computeBossUseCustomBordersAlpha)
                    end
                end)
            end
        end
    end

    -- Boss frames: apply to Boss1..Boss5 frames (shared config: db.unitFrames.Boss), then return.
    -- Boss frames are individual TargetFrame variants and are NOT the same as the EditMode system frame.
    for i = 1, addon.NUM_BOSS_FRAMES do
        local bossFrame = addon.GetBossFrame(i)
        local unitId = "boss" .. i
        -- Apply styling whenever the frame exists. Let resolveHealthBar/resolvePowerBar
        -- handle finding the bars within the frame structure.
        if bossFrame then
            local hb = resolveHealthBar(bossFrame, unit)
                if hb then
                    local healthBarHideTextureOnly = (cfg.healthBarHideTextureOnly == true)
                    if healthBarHideTextureOnly then
                        if Util and Util.SetHealthBarTextureOnlyHidden then
                            Util.SetHealthBarTextureOnlyHidden(hb, true)
                        end
                    else
                        if Util and Util.SetHealthBarTextureOnlyHidden then
                            Util.SetHealthBarTextureOnlyHidden(hb, false)
                        end
                    end

                    -- Skip texture/color application when bar is hidden — no point
                    -- applying textures (which creates new texture objects and stale
                    -- hooks) or colors to an invisible bar.
                    if not healthBarHideTextureOnly then
                        local colorModeHB = cfg.healthBarColorMode or "default"
                        local texKeyHB = cfg.healthBarTexture or "default"
                        applyToBar(hb, texKeyHB, colorModeHB, cfg.healthBarTint, unitId, "health", unitId)

                        -- Background overlay (only when explicitly customized)
                        do
                            if hasBackgroundCustomization(cfg, "healthBar") then
                                local bgTexKeyHB = cfg.healthBarBackgroundTexture or "default"
                                local bgColorModeHB = cfg.healthBarBackgroundColorMode or "default"
                                local bgOpacityHB = cfg.healthBarBackgroundOpacity or 50
                                applyBackgroundToBar(hb, bgTexKeyHB, bgColorModeHB, cfg.healthBarBackgroundTint, bgOpacityHB, unit, "health")
                            end
                        end

                        ensureMaskOnBarTexture(hb, resolveBossHealthMask(bossFrame))
                    end

                    -- Clip HealthBarsContainer children to prevent dark background
                    -- below health bar when boss has no power bar
                    local hbClipContainer = resolveBossHealthBarsContainer(bossFrame)
                    if hbClipContainer and hbClipContainer.SetClipsChildren then
                        hbClipContainer:SetClipsChildren(true)
                    end

                    -- Rectangular overlay to fill top-left chip when using custom borders
                    ensureBossRectOverlay(bossFrame, hb, cfg, "health", unitId)

                    -- Health Bar custom border (same settings as other unit frames)
                    -- BOSS FRAME FIX: The HealthBar StatusBar has oversized dimensions spanning both
                    -- health and power bars. The HealthBarsContainer (parent of HealthBar) has the
                    -- correct bounds because ManaBar is a sibling of HealthBarsContainer, not a child.
                    -- The border anchors to HealthBarsContainer instead of the StatusBar.
                    if healthBarHideTextureOnly then
                        -- Clear borders when texture-only hiding is active
                        local anchorFrame = getProp(hb, "bossHealthBorderAnchor")
                        if anchorFrame then
                            if addon.BarBorders and addon.BarBorders.ClearBarFrame then addon.BarBorders.ClearBarFrame(anchorFrame) end
                            if addon.Borders and addon.Borders.HideAll then addon.Borders.HideAll(anchorFrame) end
                        end
                    else
                    do
                        local styleKey = cfg.healthBarBorderStyle
                        local hiddenEdges = cfg.healthBarBorderHiddenEdges
                        local tintEnabled = not not cfg.healthBarBorderTintEnable
                        local tintColor = type(cfg.healthBarBorderTintColor) == "table" and {
                            cfg.healthBarBorderTintColor[1] or 1,
                            cfg.healthBarBorderTintColor[2] or 1,
                            cfg.healthBarBorderTintColor[3] or 1,
                            cfg.healthBarBorderTintColor[4] or 1,
                        } or {1, 1, 1, 1}
                        local thickness = tonumber(cfg.healthBarBorderThickness) or 1
                        if thickness < 1 then thickness = 1 elseif thickness > 16 then thickness = 16 end
                        local insetH = tonumber(cfg.healthBarBorderInsetH) or tonumber(cfg.healthBarBorderInset) or 0
                        local insetV = tonumber(cfg.healthBarBorderInsetV) or tonumber(cfg.healthBarBorderInset) or 0

                        -- Resolve HealthBarsContainer which has correct bounds (just health bar area)
                        local hbContainer = resolveBossHealthBarsContainer(bossFrame)

                        -- Create or retrieve the anchor frame for border application
                        -- This frame matches the HealthBarsContainer bounds, not the oversized StatusBar
                        local anchorFrame = getProp(hb, "bossHealthBorderAnchor")
                        if not anchorFrame then
                            anchorFrame = CreateFrame("Frame", nil, hb)
                            anchorFrame:SetFrameLevel((hb:GetFrameLevel() or 0) + 1)
                            setProp(hb, "bossHealthBorderAnchor", anchorFrame)
                        end

                        -- Anchor to HealthBarsContainer bounds if available, else clipping container or StatusBar
                        anchorFrame:ClearAllPoints()
                        if hbContainer then
                            anchorFrame:SetPoint("TOPLEFT", hbContainer, "TOPLEFT", 0, 0)
                            anchorFrame:SetPoint("BOTTOMRIGHT", hbContainer, "BOTTOMRIGHT", 0, 0)
                        else
                            anchorFrame:SetAllPoints(hb)
                        end
                        anchorFrame:Show()

                        -- BOSS FRAME CLEANUP: Clear any stale borders on parent containers and the StatusBar.
                        -- Previously borders may have been applied to wrong frames (e.g., HealthBarsContainer,
                        -- TargetFrameContentMain, bossFrame.healthbar with wrong dimensions). Clear them all.
                        do
                            local clearTargets = {
                                bossFrame.healthbar,
                                hb,
                                hb and hb:GetParent(), -- HealthBarsContainer
                                bossFrame.TargetFrameContent and bossFrame.TargetFrameContent.TargetFrameContentMain,
                                bossFrame.TargetFrameContent,
                            }
                            for _, target in ipairs(clearTargets) do
                                -- Don't clear the anchor frame itself (borders are applied here)
                                if target and target ~= anchorFrame then
                                    if addon.BarBorders and addon.BarBorders.ClearBarFrame then
                                        addon.BarBorders.ClearBarFrame(target)
                                    end
                                    if addon.Borders and addon.Borders.HideAll then
                                        addon.Borders.HideAll(target)
                                    end
                                end
                            end
                        end

                        -- Apply border to anchor frame (not hb!) so it matches HealthBarTexture bounds
                        if cfg.useCustomBorders then
                            if styleKey == "none" or styleKey == nil then
                                if addon.BarBorders and addon.BarBorders.ClearBarFrame then addon.BarBorders.ClearBarFrame(anchorFrame) end
                                if addon.Borders and addon.Borders.HideAll then addon.Borders.HideAll(anchorFrame) end
                            else
                                local styleDef = addon.BarBorders and addon.BarBorders.GetStyle and addon.BarBorders.GetStyle(styleKey)
                                local color
                                if tintEnabled then
                                    color = tintColor
                                else
                                    if styleDef then
                                        color = {1, 1, 1, 1}
                                    else
                                        color = {0, 0, 0, 1}
                                    end
                                end
                                local handled = false
                                -- Clear old borders from anchor frame before applying new
                                if addon.BarBorders and addon.BarBorders.ClearBarFrame then
                                    addon.BarBorders.ClearBarFrame(anchorFrame)
                                end
                                if addon.Borders and addon.Borders.HideAll then
                                    addon.Borders.HideAll(anchorFrame)
                                end
                                -- Try ApplySquare for Boss health bar borders (simpler, more reliable)
                                -- BarBorders.ApplyToBarFrame requires a StatusBar, but anchorFrame is a Frame
                                if addon.Borders and addon.Borders.ApplySquare then
                                    local sqColor = tintEnabled and tintColor or {0, 0, 0, 1}
                                    local baseY = 1
                                    local baseX = 1
                                    local expandY = baseY - insetV
                                    local expandX = baseX - insetH
                                    if expandX < -6 then expandX = -6 elseif expandX > 6 then expandX = 6 end
                                    if expandY < -6 then expandY = -6 elseif expandY > 6 then expandY = 6 end
                                    addon.Borders.ApplySquare(anchorFrame, {
                                        size = thickness,
                                        color = sqColor,
                                        layer = "OVERLAY",
                                        layerSublevel = 3,
                                        expandX = expandX,
                                        expandY = expandY,
                                        skipDimensionCheck = true, -- Anchor frame may be small
                                        hiddenEdges = hiddenEdges,
                                    })
                                    handled = true
                                end
                                if handled then
                                    ensureTextAndBorderOrdering(unit)
                                end
                            end
                        else
                            if addon.BarBorders and addon.BarBorders.ClearBarFrame then addon.BarBorders.ClearBarFrame(anchorFrame) end
                            if addon.Borders and addon.Borders.HideAll then addon.Borders.HideAll(anchorFrame) end
                        end
                    end
                    end -- if not healthBarHideTextureOnly

                    -- Boss frames can get refreshed by Blizzard (HealthUpdate, Update) which resets textures.
                    -- Install hooks to re-assert styling after Blizzard updates.
                    local bossState = getState(bossFrame)
                    if _G.hooksecurefunc and bossState then
                        local function installBossHealthHook(hookTarget, hookName, flagName)
                            if bossState[flagName] then return true end
                            if hookTarget and type(hookTarget[hookName]) == "function" then
                                bossState[flagName] = true
                                _G.hooksecurefunc(hookTarget, hookName, function()
                                    if isEditModeActive() then return end
                                    local db2 = addon and addon.db and addon.db.profile
                                    if not db2 then return end
                                    local unitFrames2 = rawget(db2, "unitFrames")
                                    local cfgBoss = unitFrames2 and rawget(unitFrames2, "Boss") or nil
                                    if not cfgBoss then return end

                                    -- Re-hide fill texture after Blizzard may have recreated it
                                    if cfgBoss.healthBarHideTextureOnly == true then
                                        local hbReapply = bossFrame.healthbar
                                        if hbReapply and Util and Util.SetHealthBarTextureOnlyHidden then
                                            Util.SetHealthBarTextureOnlyHidden(hbReapply, true)
                                        end
                                        return
                                    end

                                    local texKey = cfgBoss.healthBarTexture or "default"
                                    local colorMode = cfgBoss.healthBarColorMode or "default"
                                    local tint = cfgBoss.healthBarTint

                                    local hasCustomTexture = (type(texKey) == "string" and texKey ~= "" and texKey ~= "default")
                                    -- Kept off addon.ResolveColorRGBA: hook-install gate; the compare decides whether to hook, not what to paint.
                                    local hasCustomColor = (colorMode == "custom" and type(tint) == "table") or (colorMode == "class") or (colorMode == "texture")
                                    if not hasCustomTexture and not hasCustomColor then return end

                                    -- Throttle: skip if a reapply is already pending for this frame
                                    local st = getState(bossFrame)
                                    if st and st.bossReapplyPending then return end
                                    if st then st.bossReapplyPending = true end

                                    -- Defer to next frame to let Blizzard finish its updates
                                    _G.C_Timer.After(0, function()
                                        local st2 = getState(bossFrame)
                                        if st2 then st2.bossReapplyPending = nil end
                                        -- Use direct property (most reliable)
                                        local hbReapply = bossFrame.healthbar
                                        if hbReapply then
                                            local resolvedPath = addon.Media and addon.Media.ResolveBarTexturePath and addon.Media.ResolveBarTexturePath(texKey)
                                            if resolvedPath and hbReapply.SetStatusBarTexture then
                                                pcall(hbReapply.SetStatusBarTexture, hbReapply, resolvedPath)
                                            end
                                            -- Reapply color
                                            local tex = hbReapply:GetStatusBarTexture()
                                            if tex and tex.SetVertexColor then
                                                bossBarColorOpts.barKind = "health"
                                                bossBarColorOpts.unitForClass = unitId
                                                local r, g, b, a = addon.ResolveColorRGBA(colorMode, tint, bossBarColorOpts)
                                                pcall(tex.SetVertexColor, tex, r, g, b, a)
                                            end
                                        end
                                    end)
                                end)
                                return true
                            end
                            return false
                        end
                        -- Hook HealthUpdate (targeted, fires for low-health player units)
                        installBossHealthHook(bossFrame, "HealthUpdate", "bossHealthUpdateHooked")
                        -- ALSO hook Update — HealthUpdate only fires for player-controlled
                        -- units at <20% health (OnUpdate handler), which bosses never are.
                        -- Update fires on INSTANCE_ENCOUNTER_ENGAGE_UNIT,
                        -- UNIT_TARGETABLE_CHANGED, etc. where Blizzard calls
                        -- UnitFrameHealthBar_Update → SetStatusBarColor(0, 1, 0).
                        installBossHealthHook(bossFrame, "Update", "bossUpdateHooked")
                    end
                end

                local pb = resolvePowerBar(bossFrame, unit)
                if pb then
                    local powerBarHidden = (cfg.powerBarHidden == true)
                    local powerBarHideTextureOnly = (cfg.powerBarHideTextureOnly == true)

                    if pb.GetAlpha and getProp(pb, "origPBAlpha") == nil then
                        local ok, a = pcall(pb.GetAlpha, pb)
                        setProp(pb, "origPBAlpha", ok and (a or 1) or 1)
                    end

                    -- Detect boss with no usable power resource
                    local bossHasNoPower = false
                    if pb.GetMinMaxValues then
                        local okMM, pMin, pMax = pcall(pb.GetMinMaxValues, pb)
                        if okMM and type(pMax) == "number" and not issecretvalue(pMax) and pMax <= 0 then
                            bossHasNoPower = true
                        end
                    end

                    if bossHasNoPower then
                        -- Hide entire ManaBar to prevent rogue texture artifacts
                        -- (Spark, invalid atlas, etc.). Text repositioned via "Around Name"
                        -- is reparented to TargetFrameContentMain and is NOT affected.
                        if pb.SetAlpha then pcall(pb.SetAlpha, pb, 0) end
                        if addon.BarBorders and addon.BarBorders.ClearBarFrame then addon.BarBorders.ClearBarFrame(pb) end
                        if addon.Borders and addon.Borders.HideAll then addon.Borders.HideAll(pb) end
                        local bpAnchor = getProp(pb, "bossPowerBorderAnchor")
                        if bpAnchor then
                            if addon.BarBorders and addon.BarBorders.ClearBarFrame then addon.BarBorders.ClearBarFrame(bpAnchor) end
                            if addon.Borders and addon.Borders.HideAll then addon.Borders.HideAll(bpAnchor) end
                        end
                    end

                    if not bossHasNoPower then
                    if powerBarHidden then
                        if pb.SetAlpha then pcall(pb.SetAlpha, pb, 0) end
                        do local bg = getProp(pb, "ScootBG"); if bg and bg.SetAlpha then pcall(bg.SetAlpha, bg, 0) end end
                        if addon.BarBorders and addon.BarBorders.ClearBarFrame then addon.BarBorders.ClearBarFrame(pb) end
                        if addon.Borders and addon.Borders.HideAll then addon.Borders.HideAll(pb) end
                        if Util and Util.SetPowerBarTextureOnlyHidden then Util.SetPowerBarTextureOnlyHidden(pb, false) end
                    elseif powerBarHideTextureOnly then
                        local origAlpha = getProp(pb, "origPBAlpha")
                        if origAlpha and pb.SetAlpha then pcall(pb.SetAlpha, pb, origAlpha) end
                        if Util and Util.SetPowerBarTextureOnlyHidden then Util.SetPowerBarTextureOnlyHidden(pb, true) end
                        if addon.BarBorders and addon.BarBorders.ClearBarFrame then addon.BarBorders.ClearBarFrame(pb) end
                        if addon.Borders and addon.Borders.HideAll then addon.Borders.HideAll(pb) end
                    else
                        local origAlpha = getProp(pb, "origPBAlpha")
                        if origAlpha and pb.SetAlpha then pcall(pb.SetAlpha, pb, origAlpha) end
                        if Util and Util.SetPowerBarTextureOnlyHidden then Util.SetPowerBarTextureOnlyHidden(pb, false) end
                    end

                    local colorModePB = cfg.powerBarColorMode or "default"
                    local texKeyPB = cfg.powerBarTexture or "default"
                    applyToBar(pb, texKeyPB, colorModePB, cfg.powerBarTint, "player", "power", unitId)

                    do
                        if hasBackgroundCustomization(cfg, "powerBar") then
                            local bgTexKeyPB = cfg.powerBarBackgroundTexture or "default"
                            local bgColorModePB = cfg.powerBarBackgroundColorMode or "default"
                            local bgOpacityPB = cfg.powerBarBackgroundOpacity or 50
                            applyBackgroundToBar(pb, bgTexKeyPB, bgColorModePB, cfg.powerBarBackgroundTint, bgOpacityPB, unit, "power")
                        end
                    end

                    if powerBarHideTextureOnly and not powerBarHidden then
                        if Util and Util.SetPowerBarTextureOnlyHidden then Util.SetPowerBarTextureOnlyHidden(pb, true) end
                    end

                    ensureMaskOnBarTexture(pb, resolveBossPowerMask(bossFrame))

                    -- Rectangular overlay to fill bottom-right chip when using custom borders
                    ensureBossRectOverlay(bossFrame, pb, cfg, "power", unitId)

                    -- Power Bar custom border (mirrors Health Bar border settings; supports power-specific overrides)
                    -- BOSS FRAME FIX: Use the same anchor frame pattern as Health Bar for consistency.
                    -- Unlike HealthBar, ManaBar is NOT inside a container - it's directly under TargetFrameContentMain.
                    -- The ManaBar StatusBar should have correct bounds (it's a sibling of HealthBarsContainer).
                    do
                        local styleKey = cfg.powerBarBorderStyle or cfg.healthBarBorderStyle
                        local hiddenEdges = cfg.powerBarBorderHiddenEdges
                        local tintEnabled
                        if cfg.powerBarBorderTintEnable ~= nil then
                            tintEnabled = not not cfg.powerBarBorderTintEnable
                        else
                            tintEnabled = not not cfg.healthBarBorderTintEnable
                        end
                        local baseTint = type(cfg.powerBarBorderTintColor) == "table" and cfg.powerBarBorderTintColor or cfg.healthBarBorderTintColor
                        local tintColor = type(baseTint) == "table" and {
                            baseTint[1] or 1,
                            baseTint[2] or 1,
                            baseTint[3] or 1,
                            baseTint[4] or 1,
                        } or {1, 1, 1, 1}
                        local thickness = tonumber(cfg.powerBarBorderThickness) or tonumber(cfg.healthBarBorderThickness) or 1
                        if thickness < 1 then thickness = 1 elseif thickness > 16 then thickness = 16 end
                        local insetH = (cfg.powerBarBorderInsetH ~= nil) and tonumber(cfg.powerBarBorderInsetH) or (cfg.powerBarBorderInset ~= nil) and tonumber(cfg.powerBarBorderInset) or tonumber(cfg.healthBarBorderInsetH) or tonumber(cfg.healthBarBorderInset) or 0
                        local insetV = (cfg.powerBarBorderInsetV ~= nil) and tonumber(cfg.powerBarBorderInsetV) or (cfg.powerBarBorderInset ~= nil) and tonumber(cfg.powerBarBorderInset) or tonumber(cfg.healthBarBorderInsetV) or tonumber(cfg.healthBarBorderInset) or 0

                        -- Resolve ManaBar for correct bounds
                        local mbResolved = resolveBossManaBar(bossFrame)

                        -- Create or retrieve the anchor frame for border application
                        -- For consistency with Health Bar, use the same pattern even though ManaBar
                        -- may already have correct bounds (it's not inside an oversized container)
                        local anchorFrame = getProp(pb, "bossPowerBorderAnchor")
                        if not anchorFrame then
                            anchorFrame = CreateFrame("Frame", nil, pb)
                            anchorFrame:SetFrameLevel((pb:GetFrameLevel() or 0) + 1)
                            setProp(pb, "bossPowerBorderAnchor", anchorFrame)
                        end

                        -- Anchor to resolved ManaBar bounds if available, else fall back to pb
                        anchorFrame:ClearAllPoints()
                        if mbResolved then
                            anchorFrame:SetPoint("TOPLEFT", mbResolved, "TOPLEFT", 0, 0)
                            anchorFrame:SetPoint("BOTTOMRIGHT", mbResolved, "BOTTOMRIGHT", 0, 0)
                        else
                            anchorFrame:SetAllPoints(pb)
                        end
                        anchorFrame:Show()

                        -- BOSS FRAME CLEANUP: Clear any stale borders on the StatusBar
                        do
                            local clearTargets = {
                                bossFrame.manabar,
                                pb,
                                pb and pb:GetParent(),
                            }
                            for _, target in ipairs(clearTargets) do
                                -- Don't clear the anchor frame itself (borders are applied here)
                                if target and target ~= anchorFrame then
                                    if addon.BarBorders and addon.BarBorders.ClearBarFrame then
                                        addon.BarBorders.ClearBarFrame(target)
                                    end
                                    if addon.Borders and addon.Borders.HideAll then
                                        addon.Borders.HideAll(target)
                                    end
                                end
                            end
                        end

                        -- Apply border to anchor frame
                        -- Skip border application when power bar is fully hidden.
                        if cfg.useCustomBorders and not powerBarHidden and not powerBarHideTextureOnly then
                            if styleKey == "none" or styleKey == nil then
                                if addon.BarBorders and addon.BarBorders.ClearBarFrame then addon.BarBorders.ClearBarFrame(anchorFrame) end
                                if addon.Borders and addon.Borders.HideAll then addon.Borders.HideAll(anchorFrame) end
                            else
                                local styleDef = addon.BarBorders and addon.BarBorders.GetStyle and addon.BarBorders.GetStyle(styleKey)
                                local color
                                if tintEnabled then
                                    color = tintColor
                                else
                                    if styleDef then
                                        color = {1, 1, 1, 1}
                                    else
                                        color = {0, 0, 0, 1}
                                    end
                                end
                                -- Clear old borders from anchor frame before applying new
                                if addon.BarBorders and addon.BarBorders.ClearBarFrame then
                                    addon.BarBorders.ClearBarFrame(anchorFrame)
                                end
                                if addon.Borders and addon.Borders.HideAll then
                                    addon.Borders.HideAll(anchorFrame)
                                end
                                -- Use ApplySquare for Boss power bar borders (same pattern as health bar)
                                if addon.Borders and addon.Borders.ApplySquare then
                                    local sqColor = tintEnabled and tintColor or {0, 0, 0, 1}
                                    local baseY = 1
                                    local baseX = 1
                                    local expandY = baseY - insetV
                                    local expandX = baseX - insetH
                                    if expandX < -6 then expandX = -6 elseif expandX > 6 then expandX = 6 end
                                    if expandY < -6 then expandY = -6 elseif expandY > 6 then expandY = 6 end
                                    addon.Borders.ApplySquare(anchorFrame, {
                                        size = thickness,
                                        color = sqColor,
                                        layer = "OVERLAY",
                                        layerSublevel = 3,
                                        expandX = expandX,
                                        expandY = expandY,
                                        skipDimensionCheck = true, -- Anchor frame may be small
                                        hiddenEdges = hiddenEdges,
                                    })
                                end
                                ensureTextAndBorderOrdering(unit)
                            end
                        else
                            if addon.BarBorders and addon.BarBorders.ClearBarFrame then addon.BarBorders.ClearBarFrame(anchorFrame) end
                            if addon.Borders and addon.Borders.HideAll then addon.Borders.HideAll(anchorFrame) end
                        end
                    end

                    -- Boss power bars can get refreshed by Blizzard which resets textures.
                    -- Install a hook to re-assert styling after Blizzard updates.
                    local bossState = getState(bossFrame)
                    if _G.hooksecurefunc and bossState and not bossState.bossPowerUpdateHooked then
                        bossState.bossPowerUpdateHooked = true
                        -- Hook the power bar's SetValue which is called on every power change
                        if pb.SetValue and type(pb.SetValue) == "function" then
                            _G.hooksecurefunc(pb, "SetValue", function()
                                if isEditModeActive() then return end
                                local db2 = addon and addon.db and addon.db.profile
                                if not db2 then return end
                                local unitFrames2 = rawget(db2, "unitFrames")
                                local cfgBoss = unitFrames2 and rawget(unitFrames2, "Boss") or nil
                                if not cfgBoss then return end

                                -- Re-hide fill texture after Blizzard may have reset it
                                if cfgBoss.powerBarHideTextureOnly == true and not (cfgBoss.powerBarHidden == true) then
                                    local pbReapply = bossFrame.manabar
                                    if pbReapply and Util and Util.SetPowerBarTextureOnlyHidden then
                                        Util.SetPowerBarTextureOnlyHidden(pbReapply, true)
                                    end
                                    return
                                end

                                local texKey = cfgBoss.powerBarTexture or "default"
                                local colorMode = cfgBoss.powerBarColorMode or "default"
                                local tint = cfgBoss.powerBarTint

                                local hasCustomTexture = (type(texKey) == "string" and texKey ~= "" and texKey ~= "default")
                                -- Kept off addon.ResolveColorRGBA: hook-install gate; the compare decides whether to hook, not what to paint.
                                local hasCustomColor = (colorMode == "custom" and type(tint) == "table") or (colorMode == "class") or (colorMode == "texture")
                                if not hasCustomTexture and not hasCustomColor then return end

                                -- Throttle: skip if a reapply is already pending
                                local st = getState(bossFrame)
                                if st and st.bossPowerReapplyPending then return end
                                if st then st.bossPowerReapplyPending = true end

                                _G.C_Timer.After(0, function()
                                    local st2 = getState(bossFrame)
                                    if st2 then st2.bossPowerReapplyPending = nil end
                                    local pbReapply = bossFrame.manabar
                                    if pbReapply then
                                        local resolvedPath = addon.Media and addon.Media.ResolveBarTexturePath and addon.Media.ResolveBarTexturePath(texKey)
                                        if resolvedPath and pbReapply.SetStatusBarTexture then
                                            pcall(pbReapply.SetStatusBarTexture, pbReapply, resolvedPath)
                                        end
                                        local tex = pbReapply:GetStatusBarTexture()
                                        if tex and tex.SetVertexColor then
                                            bossBarColorOpts.barKind = "power"
                                            bossBarColorOpts.unitForClass = unitId
                                            local r, g, b, a = addon.ResolveColorRGBA(colorMode, tint, bossBarColorOpts)
                                            pcall(tex.SetVertexColor, tex, r, g, b, a)
                                        end
                                    end
                                end)
                            end)
                        end
                    end
                    end -- if not bossHasNoPower
                end
        end
    end

    -- Boss frame art: Handle all 5 Boss frames (Boss1TargetFrame through Boss5TargetFrame)
    for i = 1, addon.NUM_BOSS_FRAMES do
        local bossFrame = addon.GetBossFrame(i)
        if bossFrame and bossFrame.TargetFrameContainer then
            local bossFT = bossFrame.TargetFrameContainer.FrameTexture
            if bossFT then
                local computeBossAlpha = customBordersAlpha("Boss", true)
                applyAlpha(bossFT, computeBossAlpha())
                hookAlphaEnforcer(bossFT, computeBossAlpha)
            end
            -- Also hide the Flash (aggro/threat glow) if present on Boss frames
            local bossFlash = bossFrame.TargetFrameContainer.Flash
            if bossFlash then
                local computeBossFlashAlpha = customBordersAlpha("Boss", false)
                applyAlpha(bossFlash, computeBossFlashAlpha())
                hookAlphaEnforcer(bossFlash, computeBossFlashAlpha)
            end
        end
    end
end

return Boss
