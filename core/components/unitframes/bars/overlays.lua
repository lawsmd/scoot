--------------------------------------------------------------------------------
-- bars/overlays.lua
-- Overlay systems for unit frame bars: frame ordering, boss rect overlays,
-- height clipping, heal prediction reparenting, health/power rect overlays.
--------------------------------------------------------------------------------

local addonName, addon = ...

-- Create module namespace
addon.BarsOverlays = addon.BarsOverlays or {}
local BO = addon.BarsOverlays

-- Reference extracted modules (loaded via TOC before this file)
local Resolvers = addon.BarsResolvers
local Textures = addon.BarsTextures
local Alpha = addon.BarsAlpha
local Utils = addon.BarsUtils

-- Reference to FrameState module for safe property storage (avoids writing to Blizzard frames)
local FS = addon.FrameState

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

-- Direct upvalue to the event-driven guard (editmode/core.lua loads first in TOC)
local isEditModeActive = addon.EditMode.IsEditModeActiveOrOpening

-- Resolver functions
local resolveHealthBar = Resolvers.resolveHealthBar
local resolveHealthContainer = Resolvers.resolveHealthContainer
local resolvePowerBar = Resolvers.resolvePowerBar

-- Resolve TempMaxHealthLoss sibling StatusBar from a HealthBar
local function resolveTempMaxHealthLoss(healthBar)
    if not healthBar then return nil end
    local parent = healthBar:GetParent()
    if not parent then return nil end
    return parent.TempMaxHealthLoss or parent.PlayerFrameTempMaxHealthLoss or nil
end

-- Texture functions
local applyAlpha = Alpha.applyAlpha

-- Utils
local getUiScale = Utils.getUiScale

--------------------------------------------------------------------------------
-- pixelFloor: Round a UI-unit value DOWN to the nearest physical screen pixel.
-- At non-1.0 UI scales, integer UI units don't land on pixel boundaries.
-- Ensures clip container edges snap to exact pixels so clipping
-- and border rendering agree on the same boundary (fixes sub-pixel gaps).
--------------------------------------------------------------------------------
local function pixelFloor(uiValue, frame)
    local scale = 1
    if frame and frame.GetEffectiveScale then
        local ok, es = pcall(frame.GetEffectiveScale, frame)
        if ok and type(es) == "number" and not issecretvalue(es) and es > 0 then
            scale = es
        end
    else
        scale = getUiScale()
    end
    return math.floor(uiValue * scale) / scale
end
BO._pixelFloor = pixelFloor

--------------------------------------------------------------------------------
-- Frame Level Ordering
--------------------------------------------------------------------------------

-- Raise unit frame text layers so they always appear above any custom borders
local function raiseUnitTextLayers(unit, targetLevel)
    -- Never touch protected unit frame hierarchy during combat; doing so taints
    -- later secure operations such as TargetFrameToT:Show().
    if InCombatLockdown and InCombatLockdown() then
        return
    end
    local function safeSetDrawLayer(fs, layer, sub)
        if fs and fs.SetDrawLayer then pcall(fs.SetDrawLayer, fs, layer, sub) end
    end
    local function safeRaiseFrameLevel(frame, baseLevel, bump)
        if not frame then return end
        local cur = (frame.GetFrameLevel and frame:GetFrameLevel()) or 0
        local target = math.max(cur, (tonumber(baseLevel) or 0) + (tonumber(bump) or 0))
        if targetLevel and type(targetLevel) == "number" then
            if target < targetLevel then target = targetLevel end
        end
        if frame.SetFrameLevel then pcall(frame.SetFrameLevel, frame, target) end
    end
    if unit == "Pet" then
        safeSetDrawLayer(_G.PetFrameHealthBarText, "OVERLAY", 6)
        safeSetDrawLayer(_G.PetFrameHealthBarTextLeft, "OVERLAY", 6)
        safeSetDrawLayer(_G.PetFrameHealthBarTextRight, "OVERLAY", 6)
        safeSetDrawLayer(_G.PetFrameManaBarText, "OVERLAY", 6)
        safeSetDrawLayer(_G.PetFrameManaBarTextLeft, "OVERLAY", 6)
        safeSetDrawLayer(_G.PetFrameManaBarTextRight, "OVERLAY", 6)
        -- Bump parent levels above any border holder
        local hb = _G.PetFrameHealthBar
        local mb = _G.PetFrameManaBar
        local base = (hb and hb.GetFrameLevel and hb:GetFrameLevel()) or 0
        safeRaiseFrameLevel(hb, base, 12)
        safeRaiseFrameLevel(mb, base, 12)
        return
    end
    if unit == "Boss" then
        for i = 1, 5 do
            local bossFrame = _G["Boss" .. i .. "TargetFrame"]
            if bossFrame then
                local hbContainer = bossFrame.TargetFrameContent
                    and bossFrame.TargetFrameContent.TargetFrameContentMain
                    and bossFrame.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer
                if hbContainer then
                    safeSetDrawLayer(hbContainer.HealthBarText, "OVERLAY", 6)
                    safeSetDrawLayer(hbContainer.LeftText, "OVERLAY", 6)
                    safeSetDrawLayer(hbContainer.RightText, "OVERLAY", 6)
                    local base = (hbContainer.GetFrameLevel and hbContainer:GetFrameLevel())
                        or (bossFrame.GetFrameLevel and bossFrame:GetFrameLevel()) or 0
                    safeRaiseFrameLevel(hbContainer, base, 12)
                end

                local mana = bossFrame.TargetFrameContent
                    and bossFrame.TargetFrameContent.TargetFrameContentMain
                    and bossFrame.TargetFrameContent.TargetFrameContentMain.ManaBar
                if mana then
                    safeSetDrawLayer(mana.ManaBarText, "OVERLAY", 6)
                    safeSetDrawLayer(mana.LeftText, "OVERLAY", 6)
                    safeSetDrawLayer(mana.RightText, "OVERLAY", 6)
                    local base = (mana.GetFrameLevel and mana:GetFrameLevel())
                        or (bossFrame.GetFrameLevel and bossFrame:GetFrameLevel()) or 0
                    safeRaiseFrameLevel(mana, base, 12)
                end
            end
        end
        return
    end
    local root = (unit == "Player" and _G.PlayerFrame)
        or (unit == "Target" and _G.TargetFrame)
        or (unit == "Focus" and _G.FocusFrame) or nil
    if not root then return end
    -- Health texts
    local hbContainer = (unit == "Player" and root.PlayerFrameContent and root.PlayerFrameContent.PlayerFrameContentMain and root.PlayerFrameContent.PlayerFrameContentMain.HealthBarsContainer)
        or (root.TargetFrameContent and root.TargetFrameContent.TargetFrameContentMain and root.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer)
    if hbContainer then
        safeSetDrawLayer(hbContainer.HealthBarText, "OVERLAY", 6)
        safeSetDrawLayer(hbContainer.LeftText, "OVERLAY", 6)
        safeSetDrawLayer(hbContainer.RightText, "OVERLAY", 6)
        local base = (hbContainer.GetFrameLevel and hbContainer:GetFrameLevel()) or ((root.GetFrameLevel and root:GetFrameLevel()) or 0)
        safeRaiseFrameLevel(hbContainer, base, 12)
    end
    -- Mana texts
    local mana
    if unit == "Player" then
        mana = root.PlayerFrameContent and root.PlayerFrameContent.PlayerFrameContentMain and root.PlayerFrameContent.PlayerFrameContentMain.ManaBarArea and root.PlayerFrameContent.PlayerFrameContentMain.ManaBarArea.ManaBar
    else
        mana = root.TargetFrameContent and root.TargetFrameContent.TargetFrameContentMain and root.TargetFrameContent.TargetFrameContentMain.ManaBar
    end
    if mana then
        safeSetDrawLayer(mana.ManaBarText, "OVERLAY", 6)
        safeSetDrawLayer(mana.LeftText, "OVERLAY", 6)
        safeSetDrawLayer(mana.RightText, "OVERLAY", 6)
        local base = (mana.GetFrameLevel and mana:GetFrameLevel()) or ((root.GetFrameLevel and root:GetFrameLevel()) or 0)
        safeRaiseFrameLevel(mana, base, 12)
    end
end
BO._raiseUnitTextLayers = raiseUnitTextLayers

-- Compute border holder level below current text and enforce ordering deterministically
local function ensureTextAndBorderOrdering(unit)
    -- PetFrame is an Edit Mode managed/protected unit frame.
    -- Even out-of-combat frame-level/strata adjustments on PetFrame children can taint the frame
    -- and later cause protected Edit Mode methods (e.g., PetFrame:HideBase(), PetFrame:SetPointBase())
    -- to be blocked. Do not perform any ordering work for Pet.
    if unit == "Pet" then
        return
    end
    -- Guard against combat lockdown: raising frame levels on protected unit frames
    -- during combat will taint subsequent secure operations (see taint.log).
    if InCombatLockdown and InCombatLockdown() then
        return
    end

    -- Boss frames: ensure text containers are above border anchor frames for all Boss1-Boss5
    if unit == "Boss" then
        for i = 1, 5 do
            local bossFrame = _G["Boss" .. i .. "TargetFrame"]
            if bossFrame then
                -- Health bar text ordering
                local hbContainer = bossFrame.TargetFrameContent
                    and bossFrame.TargetFrameContent.TargetFrameContentMain
                    and bossFrame.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer
                local hb = hbContainer and hbContainer.HealthBar

                if hb and hbContainer then
                    -- Get border anchor frame level (if it exists)
                    local borderAnchor = getProp(hb, "bossHealthBorderAnchor")
                    local borderLevel = borderAnchor and borderAnchor.GetFrameLevel and borderAnchor:GetFrameLevel() or 0
                    local barLevel = hb.GetFrameLevel and hb:GetFrameLevel() or 0

                    -- Text container must be above border anchor
                    local desiredTextLevel = math.max(
                        (hbContainer.GetFrameLevel and hbContainer:GetFrameLevel() or 0),
                        borderLevel + 1,
                        barLevel + 2
                    )
                    if hbContainer.SetFrameLevel then
                        pcall(hbContainer.SetFrameLevel, hbContainer, desiredTextLevel)
                    end

                    -- Keep border anchor between bar and text
                    if borderAnchor and borderAnchor.SetFrameLevel then
                        local holderLevel = math.max(1, desiredTextLevel - 1, barLevel + 1)
                        pcall(borderAnchor.SetFrameLevel, borderAnchor, holderLevel)
                    end
                end

                -- Power bar text ordering
                local pb = bossFrame.TargetFrameContent
                    and bossFrame.TargetFrameContent.TargetFrameContentMain
                    and bossFrame.TargetFrameContent.TargetFrameContentMain.ManaBar

                if pb then
                    -- Get border anchor frame level (if it exists)
                    local borderAnchor = getProp(pb, "bossPowerBorderAnchor")
                    local borderLevel = borderAnchor and borderAnchor.GetFrameLevel and borderAnchor:GetFrameLevel() or 0
                    local barLevel = pb.GetFrameLevel and pb:GetFrameLevel() or 0

                    -- ManaBar is both the StatusBar and the text container for Boss frames
                    local desiredTextLevel = math.max(
                        (pb.GetFrameLevel and pb:GetFrameLevel() or 0),
                        borderLevel + 1,
                        barLevel + 2
                    )
                    if pb.SetFrameLevel then
                        pcall(pb.SetFrameLevel, pb, desiredTextLevel)
                    end

                    -- Keep border anchor between bar and text
                    if borderAnchor and borderAnchor.SetFrameLevel then
                        local holderLevel = math.max(1, desiredTextLevel - 1, barLevel + 1)
                        pcall(borderAnchor.SetFrameLevel, borderAnchor, holderLevel)
                    end
                end
            end
        end
        -- Raise text draw layers to high OVERLAY sublevel
        raiseUnitTextLayers("Boss")
        return
    end

    local root = (unit == "Player" and _G.PlayerFrame)
        or (unit == "Target" and _G.TargetFrame)
        or (unit == "Focus" and _G.FocusFrame)
        or (unit == "Pet" and _G.PetFrame) or nil
    if not root then return end
    local hb = resolveHealthBar(root, unit) or nil
    local hbContainer = resolveHealthContainer(root, unit) or nil
    local pb = resolvePowerBar(root, unit) or nil
    local manaContainer
    if unit == "Player" then
        manaContainer = root.PlayerFrameContent and root.PlayerFrameContent.PlayerFrameContentMain and root.PlayerFrameContent.PlayerFrameContentMain.ManaBarArea and root.PlayerFrameContent.PlayerFrameContentMain.ManaBarArea.ManaBar or nil
    else
        manaContainer = root.TargetFrameContent and root.TargetFrameContent.TargetFrameContentMain and root.TargetFrameContent.TargetFrameContentMain.ManaBar or nil
    end
    -- Determine bar level and desired ordering: bar < holder < text
    local barLevel = (hb and hb.GetFrameLevel and hb:GetFrameLevel()) or 0
    if pb and pb.GetFrameLevel then
        local pbl = pb:GetFrameLevel() or 0
        if pbl > barLevel then barLevel = pbl end
    end
    local curTextLevel = 0
    if hbContainer and hbContainer.GetFrameLevel then curTextLevel = math.max(curTextLevel, hbContainer:GetFrameLevel() or 0) end
    if manaContainer and manaContainer.GetFrameLevel then curTextLevel = math.max(curTextLevel, manaContainer:GetFrameLevel() or 0) end
    local desiredTextLevel = math.max(curTextLevel, barLevel + 2)
    -- Raise text containers above holder
    if hbContainer and hbContainer.SetFrameLevel then pcall(hbContainer.SetFrameLevel, hbContainer, desiredTextLevel) end
    if manaContainer and manaContainer.SetFrameLevel then pcall(manaContainer.SetFrameLevel, manaContainer, desiredTextLevel) end
    -- Keep text FontStrings at high overlay sublevel
    raiseUnitTextLayers(unit, desiredTextLevel)
    -- Place the textured border holder between bar and text
    do
        local holderLevel = math.max(1, desiredTextLevel - 1, barLevel + 1)
        local hHolder = hb and hb.ScootStyledBorder or nil
        if hHolder and hHolder.SetFrameLevel then
            -- Lock desired level so internal size hooks won't raise it above text later
            setProp(hb, "borderFixedLevel", holderLevel)
            pcall(hHolder.SetFrameLevel, hHolder, holderLevel)
        end
        -- Match holder strata to the text container's strata so frame level ordering decides (bar < holder < text)
        if hHolder and hHolder.SetFrameStrata then
            local s = (hbContainer and hbContainer.GetFrameStrata and hbContainer:GetFrameStrata())
                or (hb and hb.GetFrameStrata and hb:GetFrameStrata())
                or (root and root.GetFrameStrata and root:GetFrameStrata())
                or "MEDIUM"
            pcall(hHolder.SetFrameStrata, hHolder, s)
        end
        local pHolder = pb and pb.ScootStyledBorder or nil
        if pHolder and pHolder.SetFrameLevel then
            setProp(pb, "borderFixedLevel", holderLevel)
            pcall(pHolder.SetFrameLevel, pHolder, holderLevel)
        end
        if pHolder and pHolder.SetFrameStrata then
            local s2 = (manaContainer and manaContainer.GetFrameStrata and manaContainer:GetFrameStrata())
                or (pb and pb.GetFrameStrata and pb:GetFrameStrata())
                or (root and root.GetFrameStrata and root:GetFrameStrata())
                or "MEDIUM"
            pcall(pHolder.SetFrameStrata, pHolder, s2)
        end
        -- No overlay frame creation: respect stock-frame reuse policy
    end
end
BO._ensureTextAndBorderOrdering = ensureTextAndBorderOrdering

--------------------------------------------------------------------------------
-- Boss Rectangular Overlays
--------------------------------------------------------------------------------

-- Boss rectangular overlays: fill mask chips in health bar (top-left) and power bar (bottom-right)
-- when useCustomBorders is enabled.
local function updateBossRectOverlay(bar, overlayKey)
    local st = getState(bar)
    local overlay = st and st[overlayKey] or nil
    if not bar or not overlay then return end
    if not (st and st.rectActive) then
        overlay:Hide()
        return
    end

    -- Anchor to StatusBarTexture for horizontal fill tracking (no secret value reads).
    local statusBarTex = bar:GetStatusBarTexture()
    if not statusBarTex then
        overlay:Hide()
        return
    end

    -- Hide overlay if the StatusBar fill has zero effective width (boss with no power)
    local okW, fillW = pcall(statusBarTex.GetWidth, statusBarTex)
    if okW and type(fillW) == "number" and not issecretvalue(fillW) and fillW <= 0.1 then
        overlay:Hide()
        return
    end

    -- BOSS FIX: Use stored bounds frame for vertical constraints.
    -- Boss HealthBar StatusBar is oversized (spans both health + power areas).
    -- Anchors LEFT/RIGHT to StatusBarTexture (tracks fill width automatically),
    -- and TOP/BOTTOM to the correct bounds frame (HealthBarsContainer for health,
    -- ManaBar for power).
    local boundsFrame = st.bossRectBoundsFrame

    overlay:ClearAllPoints()
    if boundsFrame and boundsFrame ~= bar then
        -- Hybrid anchoring: 4 edges anchored separately
        -- Horizontal: track StatusBarTexture fill
        overlay:SetPoint("LEFT", statusBarTex, "LEFT", 0, 0)
        overlay:SetPoint("RIGHT", statusBarTex, "RIGHT", 0, 0)
        -- Vertical: constrain to correct bounds frame
        overlay:SetPoint("TOP", boundsFrame, "TOP", 0, 0)
        overlay:SetPoint("BOTTOM", boundsFrame, "BOTTOM", 0, 0)
    else
        -- Fallback for non-Boss bars or if bounds resolution failed
        overlay:SetAllPoints(statusBarTex)
    end
    overlay:Show()
end

local function ensureBossRectOverlay(bossFrame, bar, cfg, barType, unitId)
    if not bar or not bossFrame then return end

    local db = addon and addon.db and addon.db.profile
    if not db then return end

    -- Zero-Touch: do not create config tables
    local unitFrames = rawget(db, "unitFrames")
    local ufCfg = unitFrames and rawget(unitFrames, "Boss") or nil
    if not ufCfg then
        return
    end

    -- Boss overlays activate when useCustomBorders is enabled (fills chips created by frame art masks)
    local shouldActivate = (ufCfg.useCustomBorders == true)

    -- Deactivate health overlay if texture-only hiding is active
    if barType == "health" and cfg and cfg.healthBarHideTextureOnly == true then
        shouldActivate = false
    end
    -- Deactivate power overlay if texture-only hiding is active
    if barType == "power" and cfg and cfg.powerBarHideTextureOnly == true then
        shouldActivate = false
    end

    local overlayKey = (barType == "health") and "ScootRectFillHealth" or "ScootRectFillPower"
    local st = getState(bar)
    if not st then return end
    st.rectActive = shouldActivate

    -- CRITICAL: Resolve the correct bounds frame for Boss bars.
    -- For health: HealthBarsContainer (correct bounds - health bar only)
    -- For power: ManaBar directly (correct bounds - it's a sibling of HealthBarsContainer)
    -- The HealthBar StatusBar has oversized bounds spanning both bars!
    local boundsFrame
    if barType == "health" then
        -- Use the same resolver as the border code
        if Resolvers and Resolvers.resolveBossHealthBarsContainer then
            boundsFrame = Resolvers.resolveBossHealthBarsContainer(bossFrame)
        end
        if not boundsFrame then
            -- Fallback: try to get parent (HealthBarsContainer)
            boundsFrame = bar:GetParent()
        end
    else
        -- For power bar, use the ManaBar resolver
        if Resolvers and Resolvers.resolveBossManaBar then
            boundsFrame = Resolvers.resolveBossManaBar(bossFrame)
        end
        if not boundsFrame then
            -- Fallback: ManaBar should have correct bounds itself
            boundsFrame = bar
        end
    end

    -- Store the correct bounds frame for use in updateBossRectOverlay
    st.bossRectBoundsFrame = boundsFrame or bar

    if not shouldActivate then
        if st[overlayKey] then
            st[overlayKey]:Hide()
        end
        return
    end

    if not st[overlayKey] then
        local overlay = bar:CreateTexture(nil, "OVERLAY", nil, 2)
        overlay:SetVertTile(false)
        overlay:SetHorizTile(false)
        overlay:SetTexCoord(0, 1, 0, 1)
        st[overlayKey] = overlay

        -- Drive overlay width from the bar's value/size changes
        local hookKey = (barType == "health") and "bossHealthRectHooksInstalled" or "bossPowerRectHooksInstalled"
        if _G.hooksecurefunc and not st[hookKey] then
            st[hookKey] = true
            _G.hooksecurefunc(bar, "SetValue", function(self)
                if isEditModeActive() then return end
                updateBossRectOverlay(self, overlayKey)
            end)
            _G.hooksecurefunc(bar, "SetMinMaxValues", function(self)
                if isEditModeActive() then return end
                updateBossRectOverlay(self, overlayKey)
            end)
            if bar.HookScript then
                bar:HookScript("OnSizeChanged", function(self)
                    if isEditModeActive() then return end
                    updateBossRectOverlay(self, overlayKey)
                end)
            end
        end
    end

    -- Copy the configured bar texture/tint so the overlay visually matches
    local texKey, texPath, stockAtlas
    if barType == "health" then
        texKey = cfg.healthBarTexture or "default"
        texPath = addon.Media and addon.Media.ResolveBarTexturePath and addon.Media.ResolveBarTexturePath(texKey)
        stockAtlas = "UI-HUD-UnitFrame-Target-PortraitOn-Bar-Health" -- Boss uses Target-style atlas
    else -- power
        texKey = cfg.powerBarTexture or "default"
        texPath = addon.Media and addon.Media.ResolveBarTexturePath and addon.Media.ResolveBarTexturePath(texKey)
        stockAtlas = "UI-HUD-UnitFrame-Target-PortraitOn-Bar-Mana" -- Boss uses Target-style atlas
    end

    local overlay = st[overlayKey]
    if texPath then
        -- Custom texture configured
        overlay:SetTexture(texPath)
    else
        -- Default texture - try to copy from bar
        local tex = bar:GetStatusBarTexture()
        local applied = false
        if tex then
            -- Try GetAtlas first
            local okAtlas, atlasName = pcall(tex.GetAtlas, tex)
            if okAtlas and atlasName and atlasName ~= "" then
                if overlay.SetAtlas then
                    pcall(overlay.SetAtlas, overlay, atlasName, true)
                    applied = true
                end
            end

            if not applied then
                local okTex, pathOrTex = pcall(tex.GetTexture, tex)
                if okTex then
                    if type(pathOrTex) == "string" and pathOrTex ~= "" then
                        local isAtlas = _G.C_Texture and _G.C_Texture.GetAtlasInfo and _G.C_Texture.GetAtlasInfo(pathOrTex) ~= nil
                        if isAtlas and overlay.SetAtlas then
                            pcall(overlay.SetAtlas, overlay, pathOrTex, true)
                            applied = true
                        else
                            overlay:SetTexture(pathOrTex)
                            applied = true
                        end
                    elseif type(pathOrTex) == "number" and pathOrTex > 0 then
                        overlay:SetTexture(pathOrTex)
                        applied = true
                    end
                end
            end
        end

        -- Fallback to stock atlas
        if not applied and stockAtlas and overlay.SetAtlas then
            pcall(overlay.SetAtlas, overlay, stockAtlas, true)
        end
    end

    -- Copy vertex color from configured settings
    local colorMode, tint
    if barType == "health" then
        colorMode = cfg.healthBarColorMode or "default"
        tint = cfg.healthBarTint
    else
        colorMode = cfg.powerBarColorMode or "default"
        tint = cfg.powerBarTint
    end

    local r, g, b, a = 1, 1, 1, 1
    if colorMode == "custom" and type(tint) == "table" then
        r, g, b, a = tint[1] or 1, tint[2] or 1, tint[3] or 1, tint[4] or 1
    elseif colorMode == "class" and addon.GetClassColorRGB then
        local cr, cg, cb = addon.GetClassColorRGB(unitId or "player")
        if cr == nil and barType == "health" and addon.GetDefaultHealthColorRGB then
            cr, cg, cb = addon.GetDefaultHealthColorRGB()
        end
        r, g, b = cr or 1, cg or 1, cb or 1
    elseif colorMode == "texture" then
        r, g, b, a = 1, 1, 1, 1
    elseif barType == "health" and colorMode == "default" and addon.GetDefaultHealthColorRGB then
        local hr, hg, hb = addon.GetDefaultHealthColorRGB()
        r, g, b = hr or 0, hg or 1, hb or 0
    end
    overlay:SetVertexColor(r, g, b, a)

    -- Safety: verify overlay has a valid texture. If every atlas/texture try
    -- failed silently, fall back to SetColorTexture to prevent gray checkerboard.
    do
        local okA, aName = pcall(overlay.GetAtlas, overlay)
        local okT, tPath = pcall(overlay.GetTexture, overlay)
        local hasValidTex = (okA and aName and aName ~= "")
            or (okT and tPath and ((type(tPath) == "string" and tPath ~= "") or (type(tPath) == "number" and tPath > 0)))
        if not hasValidTex and overlay.SetColorTexture then
            overlay:SetColorTexture(r, g, b, a)
        end
    end

    updateBossRectOverlay(bar, overlayKey)
end
BO._ensureBossRectOverlay = ensureBossRectOverlay


-- Border anchor that spans the union of HealthBar and HealthBarsContainer bounds.
-- Needed because Blizzard's CheckClassification() shrinks HealthBarsContainer for
-- "minus" mobs while HealthBar keeps its fixed XML size, so neither frame alone
-- covers the visible overlay in every case.
local function ensureBorderUnionAnchor(hb, hbContainer, unit)
    if not hb or not hbContainer then return nil end
    local st = getState(hb)
    if not st then return nil end

    local union = st.borderUnionFrame
    if not union then
        union = CreateFrame("Frame", nil, hbContainer)
        st.borderUnionFrame = union
        if hb.HookScript then
            hb:HookScript("OnSizeChanged", function() ensureBorderUnionAnchor(hb, hbContainer, unit) end)
        end
        if hbContainer.HookScript then
            hbContainer:HookScript("OnSizeChanged", function() ensureBorderUnionAnchor(hb, hbContainer, unit) end)
        end
    end

    union:ClearAllPoints()
    union:SetPoint("TOPLEFT", hbContainer, "TOPLEFT", 0, 0)

    local okH1, hbH = pcall(hb.GetHeight, hb)
    local okH2, cH  = pcall(hbContainer.GetHeight, hbContainer)
    local okW1, hbW = pcall(hb.GetWidth, hb)
    local okW2, cW  = pcall(hbContainer.GetWidth, hbContainer)

    local bottomAnchor = hbContainer
    if okH1 and okH2 and type(hbH) == "number" and type(cH) == "number"
        and not issecretvalue(hbH) and not issecretvalue(cH) and hbH > cH then
        bottomAnchor = hb
    end
    local rightAnchor = hbContainer
    if okW1 and okW2 and type(hbW) == "number" and type(cW) == "number"
        and not issecretvalue(hbW) and not issecretvalue(cW) and hbW > cW then
        rightAnchor = hb
    end

    union:SetPoint("BOTTOM", bottomAnchor, "BOTTOM", 0, 0)
    union:SetPoint("RIGHT",  rightAnchor,  "RIGHT",  0, 0)
    return union
end
BO._ensureBorderUnionAnchor = ensureBorderUnionAnchor

--------------------------------------------------------------------------------
-- Health Rect Overlay
--------------------------------------------------------------------------------

-- Optional rectangular overlay for unit frame health bars when the portrait is hidden.
-- Visually "fills in" the right-side chip on Target/Focus when the
-- circular portrait is hidden, without replacing the stock StatusBar frame.
-- Also used for "Color by Value" mode to avoid modifying Blizzard's protected textures.
local function updateRectHealthOverlay(unit, bar)
    local st = getState(bar)
    local overlay = st and st.rectFill or nil
    if not bar or not overlay then return end

    local statusBarTex = bar:GetStatusBarTexture()

    if not (st and st.rectActive) then
        overlay:Hide()
        -- Restore Blizzard's native texture visibility when overlay is inactive
        if statusBarTex and statusBarTex.SetAlpha then
            pcall(statusBarTex.SetAlpha, statusBarTex, 1)
        end
        if bar.HealthBarTexture and bar.HealthBarTexture.SetAlpha then
            pcall(bar.HealthBarTexture.SetAlpha, bar.HealthBarTexture, 1)
        end
        return
    end
    -- PetFrame's managed UnitFrame updates (heal prediction sizing) can be triggered by
    -- innocuous StatusBar reads from addon code, and may hard-error due to "secret values" inside
    -- Blizzard_UnitFrame (e.g., myCurrentHealAbsorb comparisons). This overlay is purely cosmetic,
    -- so it is disabled for Pet to guarantee preset/profile application can't provoke that path.
    if st and st.rectDisabledForSecretValues then
        -- Important: do not call methods (Hide/Show/SetWidth/etc.) from inside the
        -- bar:SetValue / bar:SetMinMaxValues hook path in a "secret value"
        -- environment. The overlay is cosmetic; a complete no-op is preferred.
        return
    end
    -- Instead of reading values (GetMinMaxValues, GetValue, GetWidth) which return
    -- "secret values", the overlay anchors directly to the StatusBarTexture. The StatusBarTexture
    -- is the "fill" portion of the StatusBar and automatically scales with health value.
    if not statusBarTex then
        overlay:Hide()
        return
    end

    overlay:ClearAllPoints()
    overlay:SetAllPoints(statusBarTex)
    overlay:Show()

    -- CRITICAL: Hide Blizzard's native texture(s) so they don't show through as white.
    -- The overlay is a Scoot-controlled texture that receives the value-based color.
    -- Without hiding the native texture, you see "white mixed with color" at low alpha
    -- and "pure white" at full alpha.
    if statusBarTex and statusBarTex.SetAlpha then
        pcall(statusBarTex.SetAlpha, statusBarTex, 0)
    end
    -- Also hide the named HealthBarTexture if it's a different object
    if bar.HealthBarTexture and bar.HealthBarTexture ~= statusBarTex and bar.HealthBarTexture.SetAlpha then
        pcall(bar.HealthBarTexture.SetAlpha, bar.HealthBarTexture, 0)
    end
end

--------------------------------------------------------------------------------
-- TempMaxHealthLoss Rect Overlay
--------------------------------------------------------------------------------

-- Rectangular overlay for TempMaxHealthLoss (purple bar segment showing temporary max
-- health reduction). Fills the portrait chip the same way ensureRectHealthOverlay does
-- for the main health bar fill.
local function updateRectTmhlOverlay(unit, healthBar)
    local st = getState(healthBar)
    if not st then return end
    local overlay = st.tmhlRectFill
    if not overlay then return end

    if not st.rectActive then
        overlay:Hide()
        return
    end

    local tmhl = resolveTempMaxHealthLoss(healthBar)
    if not tmhl then
        overlay:Hide()
        return
    end

    local tmhlVisible = tmhl.IsShown and tmhl:IsShown()
    if not tmhlVisible then
        overlay:Hide()
        return
    end

    local okTex, tmhlTex = pcall(tmhl.GetStatusBarTexture, tmhl)
    if not okTex or not tmhlTex then
        overlay:Hide()
        return
    end

    overlay:ClearAllPoints()
    overlay:SetAllPoints(tmhlTex)
    overlay:Show()

    -- Hide Blizzard's native TempMaxHealthLoss fill texture
    if tmhlTex and tmhlTex.SetAlpha then
        pcall(tmhlTex.SetAlpha, tmhlTex, 0)
    end
end

--------------------------------------------------------------------------------
-- Power Rect Overlay
--------------------------------------------------------------------------------

-- Power bar foreground overlay: addon-owned texture that sits above the StatusBar fill.
-- Unlike the health overlay (which fills portrait gaps), this overlay exists to persist
-- custom textures/colors through combat. Because it's a Scoot-owned texture (not a protected
-- StatusBar region), no combat guard is needed.
local function updateRectPowerOverlay(unit, bar)
    local st = getState(bar)
    local overlay = st and st.powerFill or nil
    if not bar or not overlay then return end
    if not (st and st.powerOverlayActive) then
        overlay:Hide()
        return
    end

    local okTex, statusBarTex = pcall(bar.GetStatusBarTexture, bar)
    if not okTex then statusBarTex = nil end

    overlay:ClearAllPoints()
    if statusBarTex then
        overlay:SetAllPoints(statusBarTex)
    else
        overlay:SetAllPoints(bar)
    end
    overlay:Show()
end
BO._updateRectPowerOverlay = updateRectPowerOverlay

--------------------------------------------------------------------------------
-- ensureRectHealthOverlay
--------------------------------------------------------------------------------

local function ensureRectHealthOverlay(unit, bar, cfg)
    if not bar then return end

    local db = addon and addon.db and addon.db.profile
    if not db then return end
    -- Zero-Touch: do not create config tables. If this unit has no config, do nothing.
    local unitFrames = rawget(db, "unitFrames")
    local ufCfg = unitFrames and rawget(unitFrames, unit) or nil
    if not ufCfg then
        return
    end

    -- Determine whether overlay should be active based on unit type and settings:
    -- - Target/Focus: activate when portrait is hidden (fills portrait cut-out on right side)
    -- - Player/TargetOfTarget/Pet: activate when using custom borders (fills top-right corner chip in mask)
    -- - ANY unit: activate when using non-default color mode (custom, class, value, texture)
    --   Ensures the overlay system handles "Color by Value" instead of trying to modify
    --   Blizzard's protected textures directly.
    local shouldActivate = false
    local st = getState(bar)
    if not st then return end

    -- Reset per-call disable flag unless explicitly re-set below.
    st.rectDisabledForSecretValues = nil

    -- Check if non-default color or texture settings require overlay
    local colorMode = cfg and cfg.healthBarColorMode or "default"
    local texKey = cfg and cfg.healthBarTexture or "default"
    local hasNonDefaultColor = (colorMode ~= "default" and colorMode ~= "" and colorMode ~= nil)
    local hasNonDefaultTexture = (texKey ~= "default" and texKey ~= "" and texKey ~= nil)
    local needsOverlayForStyling = hasNonDefaultColor or hasNonDefaultTexture

    if unit == "Target" or unit == "Focus" then
        local portraitCfg = rawget(ufCfg, "portrait")
        local portraitHidden = (portraitCfg and portraitCfg.hidePortrait == true) or false
        shouldActivate = portraitHidden or needsOverlayForStyling
    elseif unit == "Player" then
        shouldActivate = (ufCfg.useCustomBorders == true) or needsOverlayForStyling
    elseif unit == "TargetOfTarget" then
        shouldActivate = (ufCfg.useCustomBorders == true) or needsOverlayForStyling
    elseif unit == "FocusTarget" then
        shouldActivate = (ufCfg.useCustomBorders == true) or needsOverlayForStyling
    elseif type(unit) == "string" and string.lower(unit) == "pet" then
        -- PetFrame has a small top-right "chip" when Blizzard's border textures are hidden
        -- and replace them with a custom border. Use the same overlay pattern as Player/ToT.
        shouldActivate = (ufCfg.useCustomBorders == true) or needsOverlayForStyling
    else
        -- Others: skip
        if st.rectFill then
            st.rectActive = false
            st.rectFill:Hide()
        end
        return
    end

    -- Deactivate overlay if texture-only hiding is active
    if cfg and cfg.healthBarHideTextureOnly == true then
        shouldActivate = false
    end

    st.rectActive = shouldActivate

    if not shouldActivate then
        if st.rectFill then
            st.rectFill:Hide()
        end
        if st.tmhlRectFill then
            st.tmhlRectFill:Hide()
            -- Restore TempMaxHealthLoss native texture visibility
            local tmhl = resolveTempMaxHealthLoss(bar)
            if tmhl then
                local okT, tmhlTex = pcall(tmhl.GetStatusBarTexture, tmhl)
                if okT and tmhlTex and tmhlTex.SetAlpha then
                    pcall(tmhlTex.SetAlpha, tmhlTex, 1)
                end
            end
        end
        return
    end

    if not st.rectFill then
        local overlay = bar:CreateTexture(nil, "OVERLAY", nil, 2)
        overlay:SetVertTile(false)
        overlay:SetHorizTile(false)
        overlay:SetTexCoord(0, 1, 0, 1)
        st.rectFill = overlay

        -- Drive overlay width from the health bar's own value/size changes.
        -- NOTE: No combat guard needed here because updateRectHealthOverlay() only
        -- operates on ScootRectFill (a Scoot-owned child texture), not Blizzard's
        -- protected StatusBar. Cosmetic operations on Scoot-owned textures are safe.
        if _G.hooksecurefunc and not st.rectHooksInstalled then
            st.rectHooksInstalled = true
            _G.hooksecurefunc(bar, "SetValue", function(self)
                if isEditModeActive() then return end
                updateRectHealthOverlay(unit, self)
            end)
            _G.hooksecurefunc(bar, "SetMinMaxValues", function(self)
                if isEditModeActive() then return end
                updateRectHealthOverlay(unit, self)
            end)
            if bar.HookScript then
                bar:HookScript("OnSizeChanged", function(self)
                    if isEditModeActive() then return end
                    updateRectHealthOverlay(unit, self)
                end)
            end
        end
    end

    -- Copy the configured health bar texture/tint so the overlay visually matches.
    -- The CONFIGURED texture from the DB is used rather than reading from the bar,
    -- because GetTexture() can return a number (texture ID) instead of a string path
    -- after SetStatusBarTexture(), which caused the overlay to fall back to WHITE.
    local texKey = cfg.healthBarTexture or "default"
    local resolvedPath = addon.Media and addon.Media.ResolveBarTexturePath and addon.Media.ResolveBarTexturePath(texKey)
    local overlay = st.rectFill

    if resolvedPath then
        -- Custom texture configured - use the resolved path
        if overlay and overlay.SetTexture then
            overlay:SetTexture(resolvedPath)
        end
    else
        -- Default texture - try to copy from bar, with fallback chain
        -- CRITICAL: GetTexture() can return an atlas token STRING. Passing an atlas token
        -- to SetTexture() causes the entire spritesheet to render.
        -- Must check if the string is an atlas and use SetAtlas() instead.
        local tex = bar:GetStatusBarTexture()
        local applied = false
        if tex then
            -- First, try GetAtlas() which is the most reliable for atlas-backed textures
            local okAtlas, atlasName = pcall(tex.GetAtlas, tex)
            if okAtlas and atlasName and atlasName ~= "" then
                if overlay and overlay.SetAtlas then
                    pcall(overlay.SetAtlas, overlay, atlasName, true)
                    applied = true
                end
            end

            if not applied then
                local okTex, pathOrTex = pcall(tex.GetTexture, tex)
                if okTex then
                    if type(pathOrTex) == "string" and pathOrTex ~= "" then
                        -- Check whether this string is an atlas token
                        local isAtlas = _G.C_Texture and _G.C_Texture.GetAtlasInfo and _G.C_Texture.GetAtlasInfo(pathOrTex) ~= nil
                        if isAtlas and overlay and overlay.SetAtlas then
                            -- Use SetAtlas to avoid spritesheet rendering
                            pcall(overlay.SetAtlas, overlay, pathOrTex, true)
                            applied = true
                        else
                            -- It's a file path, safe to use SetTexture
                            if overlay then overlay:SetTexture(pathOrTex) end
                            applied = true
                        end
                    elseif type(pathOrTex) == "number" and pathOrTex > 0 then
                        -- Texture ID - use it directly
                        if overlay then overlay:SetTexture(pathOrTex) end
                        applied = true
                    end
                end
            end
        end

        -- Fallback to stock health bar atlas for this unit
        if not applied then
            local stockAtlas
            if unit == "Player" then
                stockAtlas = "UI-HUD-UnitFrame-Player-PortraitOn-Bar-Health"
            elseif unit == "Target" then
                stockAtlas = "UI-HUD-UnitFrame-Target-PortraitOn-Bar-Health"
            elseif unit == "Focus" then
                stockAtlas = "UI-HUD-UnitFrame-Target-PortraitOn-Bar-Health"
            elseif unit == "TargetOfTarget" then
                stockAtlas = "UI-HUD-UnitFrame-Party-PortraitOn-Bar-Health" -- ToT shares party atlas
            elseif unit == "FocusTarget" then
                stockAtlas = "UI-HUD-UnitFrame-Party-PortraitOn-Bar-Health" -- FoT shares party atlas
            elseif unit == "Pet" then
                -- Best-effort fallback; if this atlas changes, the earlier "copy from bar" path should
                -- still handle the real default correctly.
                stockAtlas = "UI-HUD-UnitFrame-Pet-PortraitOn-Bar-Health"
            end
            if stockAtlas and overlay and overlay.SetAtlas then
                pcall(overlay.SetAtlas, overlay, stockAtlas, true)
            elseif overlay and overlay.SetColorTexture then
                -- Last resort: use green health color instead of white
                overlay:SetColorTexture(0, 0.8, 0, 1)
            end
        end
    end

    -- Apply vertex color to match configured color mode
    local colorMode = cfg.healthBarColorMode or "default"
    local tint = cfg.healthBarTint
    local r, g, b, a = 1, 1, 1, 1

    -- Map unit config key to unit token for API calls
    local unitToken = unit
    if unit == "Player" then unitToken = "player"
    elseif unit == "Target" then unitToken = "target"
    elseif unit == "Focus" then unitToken = "focus"
    elseif unit == "Pet" then unitToken = "pet"
    elseif unit == "TargetOfTarget" then unitToken = "targettarget"
    elseif unit == "FocusTarget" then unitToken = "focustarget"
    end

    if colorMode == "value" or colorMode == "valueDark" then
        -- "Color by Value" mode: use UnitHealthPercent with color curve
        -- Apply initial color now; dynamic updates handled by hooks below
        local useDark = (colorMode == "valueDark")
        if addon.BarsTextures and addon.BarsTextures.applyValueBasedColor then
            -- Pass the overlay as the texture to color
            addon.BarsTextures.applyValueBasedColor(bar, unitToken, overlay, useDark)
        end
        -- Store reference so dynamic updates can find the overlay
        st.valueColorOverlay = overlay
        st.valueColorUseDark = useDark  -- Store for dynamic updates
    elseif colorMode == "custom" and type(tint) == "table" then
        r, g, b, a = tint[1] or 1, tint[2] or 1, tint[3] or 1, tint[4] or 1
        if overlay and overlay.SetVertexColor then
            overlay:SetVertexColor(r, g, b, a)
        end
    elseif colorMode == "class" and addon.GetClassColorRGB then
        local cr, cg, cb = addon.GetClassColorRGB(unitToken)
        if cr == nil and addon.GetDefaultHealthColorRGB then
            cr, cg, cb = addon.GetDefaultHealthColorRGB()
        end
        r, g, b, a = cr or 1, cg or 1, cb or 1, 1
        if overlay and overlay.SetVertexColor then
            overlay:SetVertexColor(r, g, b, a)
        end
    elseif colorMode == "texture" then
        -- Preserve texture's original colors
        r, g, b, a = 1, 1, 1, 1
        if overlay and overlay.SetVertexColor then
            overlay:SetVertexColor(r, g, b, a)
        end
    elseif colorMode == "default" then
        -- Use the addon's static health color API as the authoritative source.
        -- GetVertexColor on atlas-backed StatusBarTextures (e.g., Pet) returns white
        -- because the color is baked into the atlas, not applied via vertex color.
        if addon.GetDefaultHealthColorRGB then
            local hr, hg, hb = addon.GetDefaultHealthColorRGB()
            r, g, b = hr or 0, hg or 1, hb or 0
        else
            -- Fallback: try to get the bar's current vertex color
            local tex = bar:GetStatusBarTexture()
            if tex and tex.GetVertexColor then
                local ok, vr, vg, vb, va = pcall(tex.GetVertexColor, tex)
                if ok then
                    r, g, b, a = vr or 1, vg or 1, vb or 1, va or 1
                end
            end
        end
        if overlay and overlay.SetVertexColor then
            overlay:SetVertexColor(r, g, b, a)
        end
    end

    updateRectHealthOverlay(unit, bar)

    ---------------------------------------------------------------------------
    -- TempMaxHealthLoss rectangular overlay (Target/Focus/Player)
    -- Fills the portrait chip on TempMaxHealthLoss the same way the health bar
    -- overlay fills the portrait chip on the main health fill.
    ---------------------------------------------------------------------------
    if shouldActivate then
        local tmhl = resolveTempMaxHealthLoss(bar)
        if tmhl then
            -- Create overlay texture once
            if not st.tmhlRectFill then
                local tmhlOverlay = tmhl:CreateTexture(nil, "OVERLAY", nil, 2)
                tmhlOverlay:SetVertTile(false)
                tmhlOverlay:SetHorizTile(false)
                tmhlOverlay:SetTexCoord(0, 1, 0, 1)
                st.tmhlRectFill = tmhlOverlay
            end

            local tmhlOverlay = st.tmhlRectFill

            -- Apply the same custom texture as the health bar overlay for visual consistency
            local tmhlTexKey = cfg.healthBarTexture or "default"
            local tmhlResolvedPath = addon.Media and addon.Media.ResolveBarTexturePath
                and addon.Media.ResolveBarTexturePath(tmhlTexKey)
            if tmhlResolvedPath then
                tmhlOverlay:SetTexture(tmhlResolvedPath)
            else
                -- Copy texture from TempMaxHealthLoss's own StatusBarTexture
                local okT, tmhlTex = pcall(tmhl.GetStatusBarTexture, tmhl)
                local applied = false
                if okT and tmhlTex then
                    local okAtlas, atlasName = pcall(tmhlTex.GetAtlas, tmhlTex)
                    if okAtlas and atlasName and atlasName ~= "" then
                        pcall(tmhlOverlay.SetAtlas, tmhlOverlay, atlasName, true)
                        applied = true
                    end
                    if not applied then
                        local okP, pathOrTex = pcall(tmhlTex.GetTexture, tmhlTex)
                        if okP then
                            if type(pathOrTex) == "string" and pathOrTex ~= "" then
                                local isAtlas = _G.C_Texture and _G.C_Texture.GetAtlasInfo
                                    and _G.C_Texture.GetAtlasInfo(pathOrTex) ~= nil
                                if isAtlas then
                                    pcall(tmhlOverlay.SetAtlas, tmhlOverlay, pathOrTex, true)
                                else
                                    tmhlOverlay:SetTexture(pathOrTex)
                                end
                                applied = true
                            elseif type(pathOrTex) == "number" and pathOrTex > 0 then
                                tmhlOverlay:SetTexture(pathOrTex)
                                applied = true
                            end
                        end
                    end
                end
                if not applied then
                    tmhlOverlay:SetColorTexture(0.4, 0, 0.4, 1) -- fallback purple
                end
            end

            -- Apply TempMaxHealthLoss's own color (NOT health bar color)
            if tmhl.GetStatusBarColor then
                local okC, tr, tg, tb, ta = pcall(tmhl.GetStatusBarColor, tmhl)
                if okC and tr then
                    tmhlOverlay:SetVertexColor(tr, tg, tb, ta or 1)
                end
            end

            -- Install hooks on TempMaxHealthLoss (once per bar)
            if not st.tmhlHooksInstalled then
                st.tmhlHooksInstalled = true

                if tmhl.SetValue then
                    pcall(function()
                        _G.hooksecurefunc(tmhl, "SetValue", function()
                            if isEditModeActive() then return end
                            updateRectTmhlOverlay(unit, bar)
                        end)
                    end)
                end

                if tmhl.SetMinMaxValues then
                    pcall(function()
                        _G.hooksecurefunc(tmhl, "SetMinMaxValues", function()
                            if isEditModeActive() then return end
                            updateRectTmhlOverlay(unit, bar)
                        end)
                    end)
                end

                if tmhl.HookScript then
                    pcall(function()
                        tmhl:HookScript("OnShow", function()
                            if isEditModeActive() then return end
                            updateRectTmhlOverlay(unit, bar)
                        end)
                        tmhl:HookScript("OnHide", function()
                            if isEditModeActive() then return end
                            local s = getState(bar)
                            if s and s.tmhlRectFill then
                                s.tmhlRectFill:Hide()
                            end
                        end)
                        tmhl:HookScript("OnSizeChanged", function()
                            if isEditModeActive() then return end
                            updateRectTmhlOverlay(unit, bar)
                        end)
                    end)
                end

                -- Re-sync color when Blizzard changes it
                if tmhl.SetStatusBarColor then
                    pcall(function()
                        _G.hooksecurefunc(tmhl, "SetStatusBarColor", function(self)
                            if isEditModeActive() then return end
                            local s = getState(bar)
                            if s and s.tmhlRectFill and s.rectActive then
                                local okC, cr, cg, cb, ca = pcall(self.GetStatusBarColor, self)
                                if okC and cr then
                                    s.tmhlRectFill:SetVertexColor(cr, cg, cb, ca or 1)
                                end
                            end
                        end)
                    end)
                end

                -- Re-hide native texture if Blizzard swaps it
                if tmhl.SetStatusBarTexture then
                    pcall(function()
                        _G.hooksecurefunc(tmhl, "SetStatusBarTexture", function(self)
                            if isEditModeActive() then return end
                            local s = getState(bar)
                            if not (s and s.rectActive and s.tmhlRectFill) then return end
                            local newTex = self:GetStatusBarTexture()
                            if newTex and newTex.SetAlpha then
                                pcall(newTex.SetAlpha, newTex, 0)
                            end
                            updateRectTmhlOverlay(unit, bar)
                        end)
                    end)
                end
            end

            -- Initial update
            updateRectTmhlOverlay(unit, bar)
        end
    elseif st.tmhlRectFill then
        -- Overlay deactivated: hide and restore native texture
        st.tmhlRectFill:Hide()
        local tmhl = resolveTempMaxHealthLoss(bar)
        if tmhl then
            local okT, tmhlTex = pcall(tmhl.GetStatusBarTexture, tmhl)
            if okT and tmhlTex and tmhlTex.SetAlpha then
                pcall(tmhlTex.SetAlpha, tmhlTex, 1)
            end
        end
    end
end
BO._ensureRectHealthOverlay = ensureRectHealthOverlay

--------------------------------------------------------------------------------
-- ensureRectPowerOverlay
--------------------------------------------------------------------------------

-- Power bar foreground overlay: ensures a combat-safe addon-owned texture sits above
-- the StatusBar fill so custom texture/color persists through combat resets.
local function ensureRectPowerOverlay(unit, bar, cfg)
    if not bar then return end
    if not cfg then return end

    local texKey = cfg.powerBarTexture or "default"
    local colorMode = cfg.powerBarColorMode or "default"

    -- Determine whether overlay should be active: only for non-default settings
    local isDefaultTexture = (texKey == "default" or texKey == "" or texKey == nil)
    local isDefaultColor = (colorMode == "default" or colorMode == "" or colorMode == nil)
    local shouldActivate = not (isDefaultTexture and isDefaultColor)

    -- Deactivate overlay if bar is hidden or texture-only-hidden
    if cfg.powerBarHidden == true or cfg.powerBarHideTextureOnly == true then
        shouldActivate = false
    end

    local st = getState(bar)
    if not st then return end

    st.powerOverlayActive = shouldActivate

    if not shouldActivate then
        if st.powerFill then
            st.powerFill:Hide()
            -- Restore original fill visibility
            local okTex, statusBarTex = pcall(bar.GetStatusBarTexture, bar)
            if okTex and statusBarTex then
                pcall(statusBarTex.SetAlpha, statusBarTex, 1)
            end
        end
        return
    end

    -- Create overlay texture once per bar
    if not st.powerFill then
        local createOk, overlay = pcall(bar.CreateTexture, bar, nil, "OVERLAY", nil, 2)
        if not createOk or not overlay then return end
        pcall(overlay.SetVertTile, overlay, false)
        pcall(overlay.SetHorizTile, overlay, false)
        pcall(overlay.SetTexCoord, overlay, 0, 1, 0, 1)
        st.powerFill = overlay

        -- Drive overlay position from bar value/size changes.
        -- No combat guard needed: only touches addon-owned texture.
        if _G.hooksecurefunc and not st.powerOverlayHooksInstalled then
            local hookOk = pcall(function()
                _G.hooksecurefunc(bar, "SetValue", function(self)
                    if isEditModeActive() then return end
                    updateRectPowerOverlay(unit, self)
                end)
                _G.hooksecurefunc(bar, "SetMinMaxValues", function(self)
                    if isEditModeActive() then return end
                    updateRectPowerOverlay(unit, self)
                end)
                if bar.HookScript then
                    bar:HookScript("OnSizeChanged", function(self)
                        if isEditModeActive() then return end
                        updateRectPowerOverlay(unit, self)
                    end)
                end
            end)
            if hookOk then st.powerOverlayHooksInstalled = true end
        end

        -- Sync hook: SetStatusBarTexture
        -- When Blizzard swaps the fill texture (e.g., Druid form change), re-anchor overlay,
        -- re-hide the new fill, and install alpha enforcement on it.
        if _G.hooksecurefunc and not st.powerOverlayTexSyncHooked then
            local hookOk = pcall(function()
                _G.hooksecurefunc(bar, "SetStatusBarTexture", function(self, ...)
                    if isEditModeActive() then return end
                    local s = getState(self)
                    if not (s and s.powerOverlayActive) then return end
                    if getProp(self, "ufInternalTextureWrite") then return end
                    local newTex = self:GetStatusBarTexture()
                    if newTex then
                        pcall(newTex.SetAlpha, newTex, 0)
                        -- Install enforcement on new texture if not already hooked
                        if not getProp(newTex, "powerOverlayAlphaHooked") then
                            setProp(newTex, "powerOverlayAlphaHooked", true)
                            pcall(function()
                                _G.hooksecurefunc(newTex, "SetAlpha", function(tex, alpha)
                                    local barState = getState(self)
                                    if barState and barState.powerOverlayActive and alpha > 0 then
                                        if not getProp(tex, "powerOverlaySettingAlpha") then
                                            setProp(tex, "powerOverlaySettingAlpha", true)
                                            tex:SetAlpha(0)
                                            setProp(tex, "powerOverlaySettingAlpha", nil)
                                        end
                                    end
                                end)
                            end)
                        end
                    end
                    updateRectPowerOverlay(unit, self)
                end)
            end)
            if hookOk then st.powerOverlayTexSyncHooked = true end
        end

        -- Sync hook: SetStatusBarColor
        -- When Blizzard changes the power color (power type change), update overlay
        -- vertex color if using "default" color mode.
        if _G.hooksecurefunc and not st.powerOverlayColorSyncHooked then
            local hookOk = pcall(function()
                _G.hooksecurefunc(bar, "SetStatusBarColor", function(self)
                    if isEditModeActive() then return end
                    local s = getState(self)
                    if not (s and s.powerOverlayActive and s.powerFill) then return end
                    local db = addon and addon.db and addon.db.profile
                    if not db then return end
                    local unitFrames = rawget(db, "unitFrames")
                    local cfgNow = unitFrames and rawget(unitFrames, unit) or nil
                    if not cfgNow then return end
                    local cm = cfgNow.powerBarColorMode or "default"
                    if cm == "default" or cm == "power" then
                        local uid = (unit == "Player" and "player") or (unit == "Target" and "target") or (unit == "Focus" and "focus") or (unit == "Pet" and "pet") or (unit == "TargetOfTarget" and "targettarget") or (unit == "FocusTarget" and "focustarget") or "player"
                        if addon.GetPowerColorRGB then
                            local pr, pg, pb = addon.GetPowerColorRGB(uid)
                            if pr and s.powerFill and s.powerFill.SetVertexColor then
                                s.powerFill:SetVertexColor(pr, pg, pb, 1)
                            end
                        end
                    end
                end)
            end)
            if hookOk then st.powerOverlayColorSyncHooked = true end
        end
    end

    local overlay = st.powerFill

    -- Apply texture to overlay
    local resolvedPath = addon.Media and addon.Media.ResolveBarTexturePath and addon.Media.ResolveBarTexturePath(texKey)

    if resolvedPath then
        -- Custom texture configured
        if overlay and overlay.SetTexture then
            overlay:SetTexture(resolvedPath)
        end
    else
        -- Default texture: copy from bar's StatusBarTexture with atlas detection
        local okSBT, tex = pcall(bar.GetStatusBarTexture, bar)
        if not okSBT then tex = nil end
        local applied = false
        if tex then
            local okAtlas, atlasName = pcall(tex.GetAtlas, tex)
            if okAtlas and atlasName and atlasName ~= "" then
                if overlay and overlay.SetAtlas then
                    pcall(overlay.SetAtlas, overlay, atlasName, true)
                    applied = true
                end
            end

            if not applied then
                local okTex, pathOrTex = pcall(tex.GetTexture, tex)
                if okTex then
                    if type(pathOrTex) == "string" and pathOrTex ~= "" then
                        local isAtlas = _G.C_Texture and _G.C_Texture.GetAtlasInfo and _G.C_Texture.GetAtlasInfo(pathOrTex) ~= nil
                        if isAtlas and overlay and overlay.SetAtlas then
                            pcall(overlay.SetAtlas, overlay, pathOrTex, true)
                            applied = true
                        else
                            if overlay then overlay:SetTexture(pathOrTex) end
                            applied = true
                        end
                    elseif type(pathOrTex) == "number" and pathOrTex > 0 then
                        if overlay then overlay:SetTexture(pathOrTex) end
                        applied = true
                    end
                end
            end
        end

        if not applied then
            -- Fallback: use a solid color texture matching power color
            local unitId = (unit == "Player" and "player") or (unit == "Target" and "target") or (unit == "Focus" and "focus") or (unit == "Pet" and "pet") or (unit == "TargetOfTarget" and "targettarget") or (unit == "FocusTarget" and "focustarget") or "player"
            if overlay and overlay.SetColorTexture then
                local pr, pg, pb = 0, 0, 1
                if addon.GetPowerColorRGB then
                    pr, pg, pb = addon.GetPowerColorRGB(unitId)
                end
                overlay:SetColorTexture(pr or 0, pg or 0, pb or 1, 1)
            end
        end
    end

    -- Apply vertex color to overlay based on color mode
    local unitId = (unit == "Player" and "player") or (unit == "Target" and "target") or (unit == "Focus" and "focus") or (unit == "Pet" and "pet") or (unit == "TargetOfTarget" and "targettarget") or (unit == "FocusTarget" and "focustarget") or "player"
    local tint = cfg.powerBarTint
    local r, g, b, a = 1, 1, 1, 1
    if colorMode == "custom" and type(tint) == "table" then
        r, g, b, a = tint[1] or 1, tint[2] or 1, tint[3] or 1, tint[4] or 1
    elseif colorMode == "class" and addon.GetClassColorRGB then
        local cr, cg, cb = addon.GetClassColorRGB(unitId)
        r, g, b, a = cr or 1, cg or 1, cb or 1, 1
    elseif colorMode == "texture" then
        r, g, b, a = 1, 1, 1, 1
    elseif colorMode == "default" or colorMode == "power" then
        -- Use the addon's power color API as the authoritative source.
        -- Avoids issues where the fill texture's vertex color may be stale/white
        -- after Blizzard resets the StatusBarTexture on combat entry.
        if addon.GetPowerColorRGB then
            local pr, pg, pb = addon.GetPowerColorRGB(unitId)
            if pr then r, g, b = pr, pg, pb end
        end
    end
    if overlay and overlay.SetVertexColor then
        overlay:SetVertexColor(r, g, b, a)
    end

    -- Hide the original fill texture via alpha with persistent enforcement.
    -- Blizzard resets the fill's alpha during power value updates; without enforcement,
    -- the fill becomes visible through the semi-transparent overlay at low frame opacity.
    local okTex, statusBarTex = pcall(bar.GetStatusBarTexture, bar)
    if okTex and statusBarTex then
        pcall(statusBarTex.SetAlpha, statusBarTex, 0)
        -- Install enforcement hook (once per texture) using recursion guard pattern
        if not getProp(statusBarTex, "powerOverlayAlphaHooked") then
            setProp(statusBarTex, "powerOverlayAlphaHooked", true)
            pcall(function()
                _G.hooksecurefunc(statusBarTex, "SetAlpha", function(self, alpha)
                    local barState = getState(bar)
                    if barState and barState.powerOverlayActive and alpha > 0 then
                        if not getProp(self, "powerOverlaySettingAlpha") then
                            setProp(self, "powerOverlaySettingAlpha", true)
                            self:SetAlpha(0)
                            setProp(self, "powerOverlaySettingAlpha", nil)
                        end
                    end
                end)
            end)
        end
    end

    updateRectPowerOverlay(unit, bar)
end
BO._ensureRectPowerOverlay = ensureRectPowerOverlay

return BO
