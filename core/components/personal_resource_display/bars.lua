--------------------------------------------------------------------------------
-- personal_resource_display/bars.lua
-- Bar overlays, foreground/background styling, texture hiding, borders,
-- mana cost prediction, health loss animation, visuals orchestrators,
-- the four applicators (health, power, alternate power, class resource).
--
-- Native Edit Mode settings (per-part hides, heights, width, scale, spacing, opacity,
-- visibility) are NOT written here: editmode.lua pushes them on user action and reads
-- them back on Edit Mode commits. Applicators only read db.hideBar to hide Scoot's own art.
--------------------------------------------------------------------------------

local addonName, addon = ...

local PRD = addon.PRD
local Util = addon.ComponentsUtil or {}
local Enforce = addon.Enforce

-- Import from core
local getProp = PRD._getProp
local setProp = PRD._setProp
local isPRDEnabledByCVar = PRD._isPRDEnabledByCVar
local getHealthContainer = PRD._getHealthContainer
local getPowerBar = PRD._getPowerBar
local getAltPowerBar = PRD._getAltPowerBar
local clampValue = PRD._clampValue
local ensureSettingValue = PRD._ensureSettingValue
local setSettingValue = PRD._setSettingValue
local ensureColorSetting = PRD._ensureColorSetting
local queueAfterCombat = PRD._queueAfterCombat
local MIN_CLASS_RESOURCE_SCALE_PERCENT = PRD._MIN_CLASS_RESOURCE_SCALE_PERCENT
local MAX_CLASS_RESOURCE_SCALE_PERCENT = PRD._MAX_CLASS_RESOURCE_SCALE_PERCENT

-- Scratch opts for ResolveColorRGBA: per-call fields overwritten before each call
local prdBarColorOpts = {}

-- Import from opacity (late-bound for function bodies — opacity.lua loads before bars.lua)
-- PRD._getPRDOpacityForState accessed inside function bodies at runtime

-- Import from text (late-bound for function bodies — text.lua loads before bars.lua)
-- PRD._applyHealthTextOverlay, PRD._applyPowerTextOverlay, PRD._applyAltPowerTextOverlay,
-- PRD._hideTextOverlay accessed inside function bodies at runtime

-- Write a normalized value back only when it differs: a write through the zero-touch
-- proxy materializes the component, so routine normalization must never write.
local function normalizeSettingValue(component, key, value)
    if component and component.db and component.db[key] ~= value then
        setSettingValue(component, key, value)
    end
end

--------------------------------------------------------------------------------
-- Border Management
--------------------------------------------------------------------------------

-- Find the Blizzard-native border frame for a PRD bar.
-- Health bar: border is on the parent container (HealthBarsContainer.border)
-- Power bar: border is directly on the bar (PowerBar.Border)
local function findBlizzardBorderFrame(bar)
    if not bar then return nil end
    local borderFrame = bar.Border or bar.border
    if not borderFrame then
        local ok, parent = pcall(bar.GetParent, bar)
        if ok and parent then
            borderFrame = parent.border or parent.Border
        end
    end
    return borderFrame
end

-- Hide or show the Blizzard-native border frame (Left/Right/Top/Bottom edge textures).
local function setBlizzardBorderVisible(bar, visible)
    local borderFrame = findBlizzardBorderFrame(bar)
    if not borderFrame then return end
    if visible then
        pcall(borderFrame.Show, borderFrame)
    else
        pcall(borderFrame.Hide, borderFrame)
    end
end

local function clearBarBorder(bar)
    if not bar then
        return
    end
    if addon.BarBorders and addon.BarBorders.ClearBarFrame then
        addon.BarBorders.ClearBarFrame(bar)
    end
    if addon.Borders and addon.Borders.HideAll then
        addon.Borders.HideAll(bar)
    end
    -- Restore Blizzard's native border when the custom border is cleared
    setBlizzardBorderVisible(bar, true)
end

--------------------------------------------------------------------------------
-- Bar Overlay System
-- Uses overlay textures anchored to StatusBarTexture (auto-follows fill level).
-- Overlay frames are children of the PRD bar they decorate (Rule 6: creating a child
-- under a system frame is safe), so they inherit the bar's shown state (native
-- HideHealth/HidePower/HideAltPower and the alt bar's spec gating), the per-part state
-- opacity, and the PRD's native Size, Opacity and visibility mode. Strata and levels
-- are set absolutely so the ordering does not depend on the parent.
-- Pattern matches Boss/Party/Raid frame overlays (secret-safe, no secret values).
--------------------------------------------------------------------------------

local prdBarOverlays = {
    health = { frame = nil, fgTexture = nil, bgFrame = nil, bgTexture = nil, origFillHidden = false, hookedTexture = nil },
    power = { frame = nil, fgTexture = nil, bgFrame = nil, bgTexture = nil, origFillHidden = false, hookedTexture = nil },
    altpower = { frame = nil, fgTexture = nil, bgFrame = nil, bgTexture = nil, origFillHidden = false, hookedTexture = nil },
}

-- The alternate power bar's own colour is dynamic for two classes (Monk stagger
-- thresholds, Demon Hunter void metamorphosis). While the alt overlay shows a custom
-- texture in the "default" colour mode, re-sample the bar's colour on a light ticker.
local altPowerColorTicker = nil

local function stopAltPowerColorTicker()
    if altPowerColorTicker then
        altPowerColorTicker:Cancel()
        altPowerColorTicker = nil
    end
end

-- Create or re-anchor the foreground overlay for a PRD bar.
-- The overlay texture is anchored directly to the StatusBarTexture, so it
-- automatically resizes as bar value changes (no hooks needed for width tracking).
local function ensurePRDForegroundOverlay(bar, barType)
    if not bar then return nil end
    local storage = prdBarOverlays[barType]
    if not storage then return nil end

    local statusBarTex = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
    if not statusBarTex then return nil end

    if not storage.frame then
        local overlayFrame = CreateFrame("Frame", nil, bar)
        overlayFrame:SetFrameStrata("MEDIUM")
        overlayFrame:SetFrameLevel(50)

        local fgTexture = overlayFrame:CreateTexture(nil, "ARTWORK")
        fgTexture:SetVertTile(false)
        fgTexture:SetHorizTile(false)
        fgTexture:SetTexCoord(0, 1, 0, 1)

        storage.frame = overlayFrame
        storage.fgTexture = fgTexture
    end

    -- Anchor overlay frame to the StatusBarTexture (the fill portion)
    storage.frame:ClearAllPoints()
    storage.frame:SetPoint("TOPLEFT", statusBarTex, "TOPLEFT")
    storage.frame:SetPoint("BOTTOMRIGHT", statusBarTex, "BOTTOMRIGHT")

    -- Foreground texture fills the overlay frame
    storage.fgTexture:ClearAllPoints()
    storage.fgTexture:SetAllPoints(storage.frame)

    return storage
end

-- Create or re-anchor the background overlay for a PRD bar.
-- Background covers the full bar area (not just the fill portion).
local function ensurePRDBackgroundOverlay(bar, barType)
    if not bar then return nil end
    local storage = prdBarOverlays[barType]
    if not storage then return nil end

    if not storage.bgFrame then
        local bgFrame = CreateFrame("Frame", nil, bar)
        bgFrame:SetFrameStrata("MEDIUM")
        bgFrame:SetFrameLevel(49)

        local bgTexture = bgFrame:CreateTexture(nil, "BACKGROUND")
        bgTexture:SetAllPoints(bgFrame)

        storage.bgFrame = bgFrame
        storage.bgTexture = bgTexture
    end

    -- Anchor background to the full bar bounds
    storage.bgFrame:ClearAllPoints()
    storage.bgFrame:SetPoint("TOPLEFT", bar, "TOPLEFT")
    storage.bgFrame:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT")

    return storage
end

-- Alpha 0 with Show and SetAlpha hooks, alpha 1 on restore (core/enforce.lua).
local PRD_ALPHA_OPTS = { methods = { "Show", "SetAlpha" } }

-- Hide the original StatusBarTexture fill and keep it hidden while
-- storage.origFillHidden holds. The key reads live against the texture
-- instance the bar owns now, so a bar that gets a new instance is covered
-- afresh and the old one goes inert.
local function hidePRDOriginalFill(bar, barType)
    local storage = prdBarOverlays[barType]
    if not storage then return end

    local statusBarTex = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
    if not statusBarTex then return end

    storage.origFillHidden = true
    storage.hookedTexture = statusBarTex
    Enforce.Install(statusBarTex, "prdOrigFill", {
        methods = { "SetAlpha" },
        timing = "defer",
        when = function()
            return storage.origFillHidden == true and storage.hookedTexture == statusBarTex
        end,
    })
    Enforce.Apply(statusBarTex)
end

-- Restore the original StatusBarTexture fill visibility.
local function showPRDOriginalFill(bar, barType)
    local storage = prdBarOverlays[barType]
    if not storage then return end

    storage.origFillHidden = false
    if not bar then return end
    local statusBarTex = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
    if statusBarTex then
        pcall(statusBarTex.SetAlpha, statusBarTex, 1)
    end
end

--------------------------------------------------------------------------------
-- Foreground / Background Styling
--------------------------------------------------------------------------------

-- Apply foreground texture overlay to a PRD bar.
local function applyPRDForegroundStyle(bar, barType, component)
    if not bar or not component then return end

    local textureKey = ensureSettingValue(component, "styleForegroundTexture") or "default"
    local colorMode = ensureSettingValue(component, "styleForegroundColorMode") or "default"
    local tint = ensureColorSetting(component, "styleForegroundTint", {1, 1, 1, 1})

    local isDefaultTex = (textureKey == nil or textureKey == "" or textureKey == "default")
    local isDefaultColor = (colorMode == nil or colorMode == "" or colorMode == "default")

    if isDefaultTex and isDefaultColor then
        -- No customization: hide overlay, restore original fill
        local storage = prdBarOverlays[barType]
        if storage and storage.frame then
            storage.frame:Hide()
        end
        showPRDOriginalFill(bar, barType)
        if barType == "altpower" then stopAltPowerColorTicker() end
        return
    end

    -- Ensure overlay exists and is anchored
    local storage = ensurePRDForegroundOverlay(bar, barType)
    if not storage then return end

    -- Apply texture
    local resolvedPath = addon.Media and addon.Media.ResolveBarTexturePath and addon.Media.ResolveBarTexturePath(textureKey)
    if resolvedPath then
        pcall(storage.fgTexture.SetTexture, storage.fgTexture, resolvedPath)
    else
        -- Copy from bar's current StatusBarTexture (atlas or file path)
        local statusBarTex = bar:GetStatusBarTexture()
        if statusBarTex then
            local okAtlas, atlasName = pcall(statusBarTex.GetAtlas, statusBarTex)
            if okAtlas and atlasName and atlasName ~= "" then
                pcall(storage.fgTexture.SetAtlas, storage.fgTexture, atlasName, true)
            else
                local okTex, texPath = pcall(statusBarTex.GetTexture, statusBarTex)
                if okTex and texPath then
                    pcall(storage.fgTexture.SetTexture, storage.fgTexture, texPath)
                end
            end
        end
    end

    -- Apply color. Health and power take their stock defaults from barKind;
    -- the alt bar instead passes its live color through as the resolver
    -- fallback: whatever Blizzard last set on it (mana blue, Ebon Might,
    -- stagger green/yellow/red, void metamorphosis), no arithmetic, no
    -- compare, so a secret-tagged colour is still fine.
    prdBarColorOpts.fbR, prdBarColorOpts.fbG, prdBarColorOpts.fbB, prdBarColorOpts.fbA = nil, nil, nil, nil
    if barType == "altpower" then
        prdBarColorOpts.barKind = nil
        local ok, cr, cg, cb = pcall(bar.GetStatusBarColor, bar)
        if ok and cr ~= nil then
            prdBarColorOpts.fbR, prdBarColorOpts.fbG, prdBarColorOpts.fbB, prdBarColorOpts.fbA = cr, cg, cb, 1
        end
    else
        prdBarColorOpts.barKind = barType
    end
    local r, g, b, a = addon.ResolveColorRGBA(colorMode, tint, prdBarColorOpts)
    pcall(storage.fgTexture.SetVertexColor, storage.fgTexture, r, g, b, a)

    -- Show overlay, hide original fill
    storage.frame:Show()
    storage.fgTexture:Show()
    hidePRDOriginalFill(bar, barType)

    -- Alt bar, default colour: keep following Blizzard's colour swaps for the two
    -- classes whose alt bar recolours itself between PRD events.
    if barType == "altpower" then
        local _, playerClass = UnitClass("player")
        local dynamic = (playerClass == "MONK" or playerClass == "DEMONHUNTER")
        if colorMode == "default" and dynamic then
            if not altPowerColorTicker and C_Timer and C_Timer.NewTicker then
                altPowerColorTicker = C_Timer.NewTicker(0.2, function()
                    local st = prdBarOverlays.altpower
                    local altBar = getAltPowerBar()
                    if not (st and st.frame and st.frame:IsVisible() and altBar) then
                        stopAltPowerColorTicker()
                        return
                    end
                    local okc, nr, ng, nb = pcall(altBar.GetStatusBarColor, altBar)
                    if okc and nr ~= nil then
                        pcall(st.fgTexture.SetVertexColor, st.fgTexture, nr, ng, nb, 1)
                    end
                end)
            end
        else
            stopAltPowerColorTicker()
        end
    end
end

-- Apply background texture overlay to a PRD bar.
local function applyPRDBackgroundStyle(bar, barType, component)
    if not bar or not component then return end

    local bgTextureKey = ensureSettingValue(component, "styleBackgroundTexture") or "default"
    local colorMode = ensureSettingValue(component, "styleBackgroundColorMode") or "default"
    local tint = ensureColorSetting(component, "styleBackgroundTint", {0, 0, 0, 1})
    local opacity = ensureSettingValue(component, "styleBackgroundOpacity")
    opacity = tonumber(opacity) or 50
    opacity = clampValue(math.floor(opacity + 0.5), 0, 100)
    normalizeSettingValue(component, "styleBackgroundOpacity", opacity)

    local isDefaultTex = (bgTextureKey == nil or bgTextureKey == "" or bgTextureKey == "default")
    local isDefaultColor = (colorMode == nil or colorMode == "" or colorMode == "default")

    if isDefaultTex and isDefaultColor then
        local storage = prdBarOverlays[barType]
        if storage and storage.bgFrame then
            storage.bgFrame:Hide()
        end
        return
    end

    -- Ensure background overlay exists
    local storage = ensurePRDBackgroundOverlay(bar, barType)
    if not storage then return end

    -- Apply texture
    local resolvedPath = addon.Media and addon.Media.ResolveBarTexturePath and addon.Media.ResolveBarTexturePath(bgTextureKey)
    if resolvedPath then
        pcall(storage.bgTexture.SetTexture, storage.bgTexture, resolvedPath)
    else
        -- Default: solid color fill
        if storage.bgTexture.SetColorTexture then
            pcall(storage.bgTexture.SetColorTexture, storage.bgTexture, 0, 0, 0, 1)
        end
    end

    -- Apply color
    local r, g, b, a = 0, 0, 0, 1
    if colorMode == "custom" and type(tint) == "table" then
        r, g, b, a = tint[1] or 0, tint[2] or 0, tint[3] or 0, tint[4] or 1
    end
    pcall(storage.bgTexture.SetVertexColor, storage.bgTexture, r, g, b, a)

    -- Apply opacity
    local alphaValue = opacity / 100
    pcall(storage.bgFrame.SetAlpha, storage.bgFrame, alphaValue)

    storage.bgFrame:Show()
    storage.bgTexture:Show()
end

-- Hide all PRD bar overlays (used during cleanup or when bar is hidden).
local function hidePRDBarOverlay(barType)
    local storage = prdBarOverlays[barType]
    if not storage then return end
    if storage.frame then
        pcall(storage.frame.Hide, storage.frame)
    end
    if storage.bgFrame then
        pcall(storage.bgFrame.Hide, storage.bgFrame)
    end
    storage.origFillHidden = false
    storage.hookedTexture = nil
    if barType == "altpower" then stopAltPowerColorTicker() end
end

--------------------------------------------------------------------------------
-- Bar Border
--------------------------------------------------------------------------------

local function applyPRDBarBorder(component, statusBar)
    if not component or not statusBar then
        return
    end
    local db = component.db
    if not db then return end
    local styleKey = db.borderStyle or "square"
    local hiddenEdges = db.borderHiddenEdges
    if styleKey == "none" then
        clearBarBorder(statusBar)
        return
    end
    -- Hide Blizzard's native border edges (Left/Right/Top/Bottom textures)
    -- since a custom border is being applied to this bar.
    setBlizzardBorderVisible(statusBar, false)
    local tintEnabled = db.borderTintEnable and true or false
    local tintColor = ensureColorSetting(component, "borderTintColor", {1, 1, 1, 1})
    local thickness = tonumber(db.borderThickness) or 1
    thickness = clampValue(math.floor(thickness * 2 + 0.5) / 2, 1, 16)
    local insetH = tonumber(db.borderInsetH) or tonumber(db.borderInset) or 0
    local insetV = tonumber(db.borderInsetV) or tonumber(db.borderInset) or 0
    insetH = clampValue(math.floor(insetH + 0.5), -4, 4)
    insetV = clampValue(math.floor(insetV + 0.5), -4, 4)
    normalizeSettingValue(component, "borderThickness", thickness)
    normalizeSettingValue(component, "borderInsetH", insetH)
    normalizeSettingValue(component, "borderInsetV", insetV)
    local color
    if tintEnabled then
        color = tintColor
    else
        local styleDef = addon.BarBorders and addon.BarBorders.GetStyle and addon.BarBorders.GetStyle(styleKey)
        if styleDef then
            color = {1, 1, 1, 1}
        else
            color = {0, 0, 0, 1}
        end
    end
    if addon.BarBorders and addon.BarBorders.ApplyToBarFrame then
        if addon.BarBorders.ClearBarFrame then
            addon.BarBorders.ClearBarFrame(statusBar)
        end
        local handled = addon.BarBorders.ApplyToBarFrame(statusBar, styleKey, {
            color = color,
            thickness = thickness,
            levelOffset = 51,
            insetH = insetH,
            insetV = insetV,
            hiddenEdges = hiddenEdges,
        })
        if handled then
            -- Hide any old square border that may have been applied previously
            if addon.Borders and addon.Borders.HideAll then
                addon.Borders.HideAll(statusBar)
            end
            return
        end
    end
    if addon.BarBorders and addon.BarBorders.ClearBarFrame then
        addon.BarBorders.ClearBarFrame(statusBar)
    end
    if addon.Borders and addon.Borders.ApplySquare then
        local fallbackColor = tintEnabled and tintColor or {0, 0, 0, 1}
        local baseY = (thickness <= 1) and 0 or 1
        local baseX = 1
        local expandY = baseY - insetV
        local expandX = baseX - insetH
        if expandX < -6 then expandX = -6 elseif expandX > 6 then expandX = 6 end
        if expandY < -6 then expandY = -6 elseif expandY > 6 then expandY = 6 end
        addon.Borders.ApplySquare(statusBar, {
            size = thickness,
            color = fallbackColor,
            layer = "OVERLAY",
            layerSublevel = 3,
            levelOffset = 51,
            -- Child of the bar, so it hides/dims/scales with it (see overlay parenting note)
            containerParent = statusBar,
            expandX = expandX,
            expandY = expandY,
            hiddenEdges = hiddenEdges,
        })
    end
end

--------------------------------------------------------------------------------
-- Mana Cost Prediction
--------------------------------------------------------------------------------

-- Hide/restore ManaCostPredictionBar on the PRD power bar.
local function hidePRDManaCostPrediction(powerBar, hidden)
    if not powerBar then return end
    Enforce.Set(powerBar.ManaCostPredictionBar, "prdManaCost", hidden, PRD_ALPHA_OPTS)
end

--------------------------------------------------------------------------------
-- Texture Hiding
--------------------------------------------------------------------------------

-- Hide/restore PRD bar fill texture and background. The same immediate
-- re-assert as the Player UF SetPowerBarTextureOnlyHidden; the hook body is
-- Enforce's.
local function hidePRDBarTextures(bar, barType, hidden)
    if not bar or type(bar) ~= "table" then return end
    Enforce.Set(bar.GetStatusBarTexture and bar:GetStatusBarTexture(), "prdFill", hidden, PRD_ALPHA_OPTS)
    Enforce.Set(bar.Background or bar.background, "prdBG", hidden, PRD_ALPHA_OPTS)
end

--------------------------------------------------------------------------------
-- Native Bar Backdrop (12.0.7+)
--------------------------------------------------------------------------------
-- Patch 12.0.7 gave each PRD bar a backdrop texture (the dark background plus a
-- baked-in frame/border edge) using the atlas "UI-HUD-CoolDownManager-Bar-BG".
-- It is an anonymous BACKGROUND-layer texture (no parentKey), located by
-- scanning the bar's regions. Hidden via the same recursion-guard alpha pattern.
local PRD_BG_ATLAS = "UI-HUD-CoolDownManager-Bar-BG"

local function findNativeBarBackground(bar)
    if not bar then return nil end
    local cached = getProp(bar, "_ScootPRDBGArt")
    if cached then return cached end
    if not bar.GetRegions then return nil end
    local fallback
    for _, region in ipairs({ bar:GetRegions() }) do
        if region and region.GetObjectType and region:GetObjectType() == "Texture" then
            local okLayer, layer = pcall(region.GetDrawLayer, region)
            if okLayer and layer == "BACKGROUND" then
                local okAtlas, atlas = pcall(region.GetAtlas, region)
                if okAtlas and atlas == PRD_BG_ATLAS then
                    setProp(bar, "_ScootPRDBGArt", region)
                    return region
                end
                fallback = fallback or region
            end
        end
    end
    if fallback then setProp(bar, "_ScootPRDBGArt", fallback) end
    return fallback
end

-- Hide/restore the native bar backdrop art. Used by both the dedicated
-- "Hide Bar Background" toggle and the "Hide the Bar but not its Text" mode.
-- Hooked on the first call either way, as before.
local function setNativeBarBackgroundHidden(bar, barType, hidden)
    if not bar then return end
    local bgTex = findNativeBarBackground(bar)
    if not bgTex then return end
    Enforce.Install(bgTex, "prdBGArt", PRD_ALPHA_OPTS)
    Enforce.Set(bgTex, "prdBGArt", hidden, PRD_ALPHA_OPTS)
end

--------------------------------------------------------------------------------
-- Health Loss Animation
--------------------------------------------------------------------------------

-- Helper to get the animated loss bar frame from PlayerFrame
local function getPRDAnimatedLossBar()
    local container = addon.Frames.resolveHealthContainer(nil, "Player")
    return container and container.PlayerFrameHealthBarAnimatedLoss
end

-- The loss animation is hidden with Hide, not alpha, and Blizzard controls
-- its visibility again once the toggle clears: no forced Show on restore.
local function hidePRDLossAnim(bar)
    local hide = bar.HideBase or bar.Hide
    hide(bar)
end
local PRD_LOSS_ANIM_OPTS = { methods = { "Show" }, apply = hidePRDLossAnim, restore = false }

-- Hide/show the health loss animation (the dark red bar that appears when taking damage)
local function applyPRDHealthLossAnimationVisibility(component)
    local hideAnim = ensureSettingValue(component, "hideHealthLossAnimation") and true or false
    local animatedLossBar = getPRDAnimatedLossBar()
    if not animatedLossBar then return end
    Enforce.Set(animatedLossBar, "prdLossAnim", hideAnim, PRD_LOSS_ANIM_OPTS)
end

--------------------------------------------------------------------------------
-- Visuals Orchestrators
--------------------------------------------------------------------------------

local function applyPRDHealthVisuals(component, container)
    if not component or not container then
        return
    end
    local statusBar = container.healthBar or container.HealthBar
    if not statusBar then
        return
    end
    -- Bar visibility is driven natively (Edit Mode HideHealth, mirrored by editmode.lua,
    -- SetShown()s the container and reflows the rest of the PRD). This path runs only
    -- when the bar is shown; apply Scoot's state-based opacity on the container. The
    -- status bar and every Scoot overlay are children of it and inherit the alpha.
    local alpha = PRD._getPRDOpacityForState("prdHealth")
    pcall(container.SetAlpha, container, alpha)
    local hideTextureOnly = ensureSettingValue(component, "hideTextureOnly") and true or false
    local hideBarBackground = ensureSettingValue(component, "hideBarBackground") and true or false
    -- The 12.0.7 backdrop art is hidden when either the texture-only mode or the
    -- dedicated background toggle is on (texture-only implies the backdrop too).
    setNativeBarBackgroundHidden(statusBar, "health", hideTextureOnly or hideBarBackground)
    if hideTextureOnly then
        hidePRDBarTextures(statusBar, "health", true)
        hidePRDBarOverlay("health")
        clearBarBorder(statusBar)
        setBlizzardBorderVisible(statusBar, false)
        PRD._applyHealthTextOverlay(component)
        return
    end
    hidePRDBarTextures(statusBar, "health", false)
    applyPRDForegroundStyle(statusBar, "health", component)
    applyPRDBackgroundStyle(statusBar, "health", component)
    applyPRDBarBorder(component, statusBar)
    PRD._applyHealthTextOverlay(component)
    applyPRDHealthLossAnimationVisibility(component)
end

local function applyPRDPowerVisuals(component, frame)
    if not component or not frame then
        return
    end
    -- Bar visibility is driven natively in applyPowerOffsets (Edit Mode HidePower).
    -- This path runs only when the bar is shown; apply Scoot's state-based opacity.
    local alpha = PRD._getPRDOpacityForState("prdPower")
    pcall(frame.SetAlpha, frame, alpha)
    local hideTextureOnly = ensureSettingValue(component, "hideTextureOnly") and true or false
    local hideBarBackground = ensureSettingValue(component, "hideBarBackground") and true or false
    -- The 12.0.7 backdrop art is hidden when either the texture-only mode or the
    -- dedicated background toggle is on (texture-only implies the backdrop too).
    setNativeBarBackgroundHidden(frame, "power", hideTextureOnly or hideBarBackground)
    if hideTextureOnly then
        hidePRDBarTextures(frame, "power", true)
        hidePRDManaCostPrediction(frame, true)
        hidePRDBarOverlay("power")
        clearBarBorder(frame)
        setBlizzardBorderVisible(frame, false)
        PRD._applyPowerTextOverlay(component)
        return
    end
    -- Apply mana cost prediction hiding based on setting (when bar is visible)
    local hideManaCost = component.db and component.db.hideManaCostPrediction
    hidePRDManaCostPrediction(frame, hideManaCost)
    hidePRDBarTextures(frame, "power", false)
    applyPRDForegroundStyle(frame, "power", component)
    applyPRDBackgroundStyle(frame, "power", component)
    applyPRDBarBorder(component, frame)
    PRD._applyPowerTextOverlay(component)
end

local function applyPRDClassResourceVisibility(component, frame)
    if not component or not frame then
        return
    end
    -- Native HideClassInfo / HideClassInfoOnPlayerFrame are Edit Mode settings mirrored
    -- by editmode.lua (pushed on user action, read back on commits). Here we only skip
    -- Scoot's own styling while the part is hidden.
    local hide = ensureSettingValue(component, "hideBar") and true or false
    if hide then
        return
    end
    -- Shown: apply Scoot's state-based opacity to the class resource frame.
    local alpha = PRD._getPRDOpacityForState("prdClassResource")
    pcall(frame.SetAlpha, frame, alpha)
end

--------------------------------------------------------------------------------
-- Scale Functions
--------------------------------------------------------------------------------

local function applyScaleToFrame(frame, multiplier, component)
    if not frame or type(multiplier) ~= "number" or multiplier <= 0 then
        return
    end
    if not frame.SetScale then
        return
    end

    if getProp(frame, "_ScootBaseScale") == nil then
        local base = 1
        if frame.GetScale then
            local ok, existing = pcall(frame.GetScale, frame)
            if ok and existing then
                base = existing
            end
        end
        setProp(frame, "_ScootBaseScale", base or 1)
    end

    local baseScale = getProp(frame, "_ScootBaseScale") or 1
    local desired = baseScale * multiplier

    local current
    if frame.GetScale then
        local ok, existing = pcall(frame.GetScale, frame)
        if ok and existing then
            current = existing
        end
    end
    if current and math.abs(current - desired) < 0.0001 then
        return
    end

    local ok = pcall(frame.SetScale, frame, desired)
    if not ok then
        queueAfterCombat(component)
    end
end

local function resolveClassResourceScale(component)
    if not component or not component.db then
        return 1
    end
    local value = tonumber(component.db.scale) or 100
    value = clampValue(math.floor(value + 0.5), MIN_CLASS_RESOURCE_SCALE_PERCENT, MAX_CLASS_RESOURCE_SCALE_PERCENT)
    normalizeSettingValue(component, "scale", value)
    return value / 100
end

--------------------------------------------------------------------------------
-- Applicators
--------------------------------------------------------------------------------
-- NOTE: The old HealthBarsContainer Show-hook (which re-hid the container after
-- Blizzard reshowed it) was retired in 12.0.7. Hiding now flows through the native
-- HideHealth Edit Mode setting, so Blizzard's own clean rebuild owns the container's
-- shown state — removing a hook on a system-frame-tree member (taint risk, Rule 11).
-- Sizing likewise moved to native Edit Mode (HealthBarHeight / PowerBarHeight / BarWidth /
-- Size / Padding), mirrored by editmode.lua; the applicators no longer size anything.

local function applyHealthOffsets(component)
    -- PRD is PersonalResourceDisplayFrame (parented to UIParent), not a nameplate.
    -- Positioning and sizing are handled by Edit Mode; this function applies styling.
    if not isPRDEnabledByCVar() then
        -- PRD is disabled; clear any existing borders/overlays and bail out
        local container = getHealthContainer()
        if container then
            local statusBar = container.healthBar or container.HealthBar
            if statusBar then clearBarBorder(statusBar) end
            hidePRDBarOverlay("health")
            PRD._hideTextOverlay("health")
        end
        return
    end

    local container = getHealthContainer()
    if not container then
        return
    end

    -- Native HideHealth (Edit Mode, mirrored by editmode.lua) SetShown()s the
    -- HealthBarsContainer and reflows the rest of the PRD in an untainted context.
    -- Here we only park Scoot's own art while the part is hidden.
    local hide = ensureSettingValue(component, "hideBar") and true or false
    if hide then
        local statusBar = container.healthBar or container.HealthBar
        if statusBar then
            clearBarBorder(statusBar)
        end
        hidePRDBarOverlay("health")
        PRD._hideTextOverlay("health")
        return
    end

    -- Apply visuals (styling, borders, text overlays)
    applyPRDHealthVisuals(component, container)
end

local function applyPowerOffsets(component)
    -- PRD power bar is PersonalResourceDisplayFrame.PowerBar (IsProtected: false).
    if not isPRDEnabledByCVar() then
        local frame = getPowerBar()
        if frame then
            clearBarBorder(frame)
            hidePRDBarOverlay("power")
            PRD._hideTextOverlay("power")
        end
        return
    end

    local frame = getPowerBar()
    if not frame then
        return
    end

    -- Native HidePower (Edit Mode, mirrored by editmode.lua) SetShown()s the PowerBar
    -- and reflows the layout. Here we only park Scoot's own art while hidden.
    local hide = ensureSettingValue(component, "hideBar") and true or false

    -- Child frame features (operates on child frames: FullPowerFrame, FeedbackFrame)
    if Util then
        if Util.SetFullPowerSpikeHidden then
            local hideSpikes = (component.db and component.db.hideSpikeAnimations) or hide
            Util.SetFullPowerSpikeHidden(frame, hideSpikes)
        end
        if Util.SetPowerFeedbackHidden then
            local hideFeedback = (component.db and component.db.hidePowerFeedback) or hide
            Util.SetPowerFeedbackHidden(frame, hideFeedback)
        end
    end

    if hide then
        clearBarBorder(frame)
        setBlizzardBorderVisible(frame, false)
        hidePRDManaCostPrediction(frame, true)
        hidePRDBarOverlay("power")
        PRD._hideTextOverlay("power")
        return
    end

    -- Apply visuals (styling, text overlays)
    if frame.GetStatusBarTexture then
        applyPRDPowerVisuals(component, frame)
    end
end

-- Alternate power bar (12.0.7). Blizzard owns presence: the bar is shown only while
-- the class/spec has an alternate resource, and native HideAltPower SetShown()s it.
-- Scoot's overlays are children of the bar, so they follow both without a Lua gate.
local function applyPRDAltPowerVisuals(component, frame)
    if not component or not frame then
        return
    end
    local alpha = PRD._getPRDOpacityForState("prdAltPower")
    pcall(frame.SetAlpha, frame, alpha)
    local hideTextureOnly = ensureSettingValue(component, "hideTextureOnly") and true or false
    local hideBarBackground = ensureSettingValue(component, "hideBarBackground") and true or false
    setNativeBarBackgroundHidden(frame, "altpower", hideTextureOnly or hideBarBackground)
    if hideTextureOnly then
        hidePRDBarTextures(frame, "altpower", true)
        hidePRDBarOverlay("altpower")
        clearBarBorder(frame)
        setBlizzardBorderVisible(frame, false)
        PRD._applyAltPowerTextOverlay(component)
        return
    end
    hidePRDBarTextures(frame, "altpower", false)
    applyPRDForegroundStyle(frame, "altpower", component)
    applyPRDBackgroundStyle(frame, "altpower", component)
    applyPRDBarBorder(component, frame)
    PRD._applyAltPowerTextOverlay(component)
end

local function applyAltPowerOffsets(component)
    if not isPRDEnabledByCVar() then
        local frame = getAltPowerBar()
        if frame then
            clearBarBorder(frame)
            hidePRDBarOverlay("altpower")
            PRD._hideTextOverlay("altpower")
        end
        return
    end

    local frame = getAltPowerBar()
    if not frame then
        return
    end

    -- Native HideAltPower (Edit Mode, mirrored by editmode.lua). Park Scoot's art while hidden.
    local hide = ensureSettingValue(component, "hideBar") and true or false
    if hide then
        clearBarBorder(frame)
        setBlizzardBorderVisible(frame, false)
        hidePRDBarOverlay("altpower")
        PRD._hideTextOverlay("altpower")
        return
    end

    if frame.GetStatusBarTexture then
        applyPRDAltPowerVisuals(component, frame)
    end
end

local function applyClassResourceOffsets(component)
    -- Class resource is inside PersonalResourceDisplayFrame.ClassFrameContainer.
    -- Positioning is handled by Blizzard; this function applies scale and visibility.
    if not isPRDEnabledByCVar() then
        return
    end

    local prd = PersonalResourceDisplayFrame
    if not prd then
        return
    end
    local classContainer = prd.ClassFrameContainer
    if not classContainer then
        return
    end

    -- The class resource frame is a child of ClassFrameContainer (e.g., prdClassFrame)
    local frame
    if classContainer.GetChildren then
        frame = classContainer:GetChildren()
    end
    if not frame then
        return
    end
    if frame.IsForbidden and frame:IsForbidden() then
        return
    end

    local componentScale = resolveClassResourceScale(component)
    applyScaleToFrame(frame, componentScale, component)
    applyPRDClassResourceVisibility(component, frame)

    -- Apply DK rune texture overlay if available
    if addon.ApplyDKRuneTextures then
        addon.ApplyDKRuneTextures("prd")
    end

    -- Apply Mage arcane charge texture overlay if available
    if addon.ApplyMageArcaneChargeTextures then
        addon.ApplyMageArcaneChargeTextures("prd")
    end
end

--------------------------------------------------------------------------------
-- Namespace Promotions
--------------------------------------------------------------------------------

PRD._applyHealthOffsets = applyHealthOffsets
PRD._applyPowerOffsets = applyPowerOffsets
PRD._applyAltPowerOffsets = applyAltPowerOffsets
PRD._applyClassResourceOffsets = applyClassResourceOffsets
PRD._hidePRDBarOverlay = hidePRDBarOverlay
