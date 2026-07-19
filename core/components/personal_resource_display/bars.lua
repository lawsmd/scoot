--------------------------------------------------------------------------------
-- personal_resource_display/bars.lua
-- Bar overlays, foreground/background styling, texture hiding, borders,
-- mana cost prediction, health loss animation, visuals orchestrators,
-- all three applicators.
--------------------------------------------------------------------------------

local addonName, addon = ...

local PRD = addon.PRD
local Util = addon.ComponentsUtil or {}

-- Import from core
local getState = PRD._getState
local getProp = PRD._getProp
local setProp = PRD._setProp
local isPRDEnabledByCVar = PRD._isPRDEnabledByCVar
local getHealthContainer = PRD._getHealthContainer
local getPowerBar = PRD._getPowerBar
local clampValue = PRD._clampValue
local ensureSettingValue = PRD._ensureSettingValue
local setSettingValue = PRD._setSettingValue
local ensureColorSetting = PRD._ensureColorSetting
local queueAfterCombat = PRD._queueAfterCombat
local MIN_HEALTH_BAR_WIDTH = PRD._MIN_HEALTH_BAR_WIDTH
local MAX_HEALTH_BAR_WIDTH = PRD._MAX_HEALTH_BAR_WIDTH
local MIN_HEALTH_BAR_HEIGHT = PRD._MIN_HEALTH_BAR_HEIGHT
local MAX_HEALTH_BAR_HEIGHT = PRD._MAX_HEALTH_BAR_HEIGHT
local MIN_POWER_BAR_HEIGHT = PRD._MIN_POWER_BAR_HEIGHT
local MAX_POWER_BAR_HEIGHT = PRD._MAX_POWER_BAR_HEIGHT
local MIN_CLASS_RESOURCE_SCALE_PERCENT = PRD._MIN_CLASS_RESOURCE_SCALE_PERCENT
local MAX_CLASS_RESOURCE_SCALE_PERCENT = PRD._MAX_CLASS_RESOURCE_SCALE_PERCENT

-- Import from opacity (late-bound for function bodies — opacity.lua loads before bars.lua)
-- PRD._getPRDOpacityForState accessed inside function bodies at runtime

-- Import from text (late-bound for function bodies — text.lua loads before bars.lua)
-- PRD._applyHealthTextOverlay, PRD._applyPowerTextOverlay, PRD._hideTextOverlay
-- accessed inside function bodies at runtime

-- 12.0.7: drive a native Personal Resource Display Edit Mode setting (by logical key)
-- through the centralized, combat-safe, Edit-Mode-first write path. Used to re-point
-- per-part hides onto Blizzard's own SetHide* handlers, which SetShown() the bar and
-- reflow the layout in an untainted context. Safe no-op until the Edit Mode layer is
-- ready, and skips redundant writes (so it never triggers a layout rebuild on a value
-- that already matches — preserving the zero-touch policy on fresh profiles).
local function writePRDNative(logicalKey, enabled)
    local EM = addon.EditMode
    if EM and EM.WritePRDSetting then
        EM.WritePRDSetting(logicalKey, enabled and 1 or 0)
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
-- Overlay frames are parented to UIParent to avoid taint on nameplate frames.
-- Pattern matches Boss/Party/Raid frame overlays (secret-safe, no secret values).
--------------------------------------------------------------------------------

local prdBarOverlays = {
    health = { frame = nil, fgTexture = nil, bgFrame = nil, bgTexture = nil, origFillHidden = false, hookedTexture = nil },
    power = { frame = nil, fgTexture = nil, bgFrame = nil, bgTexture = nil, origFillHidden = false, hookedTexture = nil },
}

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
        local overlayFrame = CreateFrame("Frame", nil, UIParent)
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
        local bgFrame = CreateFrame("Frame", nil, UIParent)
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

-- Hide the original StatusBarTexture fill and hook SetAlpha to keep it hidden.
-- Tracks which texture instance was hooked; re-hooks if the bar gets a new instance.
local function hidePRDOriginalFill(bar, barType)
    local storage = prdBarOverlays[barType]
    if not storage then return end

    local statusBarTex = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
    if not statusBarTex then return end

    pcall(statusBarTex.SetAlpha, statusBarTex, 0)
    storage.origFillHidden = true

    -- Only hook if this is a new/different StatusBarTexture instance
    if hooksecurefunc and storage.hookedTexture ~= statusBarTex then
        storage.hookedTexture = statusBarTex
        hooksecurefunc(statusBarTex, "SetAlpha", function(self, alpha)
            if storage.origFillHidden and storage.hookedTexture == self and alpha > 0 then
                if C_Timer and C_Timer.After then
                    C_Timer.After(0, function()
                        if storage.origFillHidden and storage.hookedTexture == self then
                            pcall(self.SetAlpha, self, 0)
                        end
                    end)
                end
            end
        end)
    end
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

    -- Apply color
    local r, g, b, a = 1, 1, 1, 1
    if colorMode == "custom" and type(tint) == "table" then
        r, g, b, a = tint[1] or 1, tint[2] or 1, tint[3] or 1, tint[4] or 1
    elseif colorMode == "class" then
        local cr, cg, cb = addon.GetClassColorRGB("player")
        r, g, b, a = cr or 1, cg or 1, cb or 1, 1
    elseif colorMode == "power" and barType == "power" then
        local pr, pg, pb = addon.GetPowerColorRGB("player")
        r, g, b, a = pr or 1, pg or 1, pb or 1, 1
    elseif colorMode == "texture" then
        r, g, b, a = 1, 1, 1, 1  -- Raw texture colors unmodified
    elseif colorMode == "default" then
        -- Blizzard's intended bar color
        if barType == "health" then
            local hr, hg, hb = addon.GetDefaultHealthColorRGB()
            r, g, b, a = hr or 0, hg or 1, hb or 0, 1
        elseif barType == "power" then
            local pr, pg, pb = addon.GetPowerColorRGB("player")
            r, g, b, a = pr or 1, pg or 1, pb or 1, 1
        end
    end
    pcall(storage.fgTexture.SetVertexColor, storage.fgTexture, r, g, b, a)

    -- Show overlay, hide original fill
    storage.frame:Show()
    storage.fgTexture:Show()
    hidePRDOriginalFill(bar, barType)
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
    setSettingValue(component, "styleBackgroundOpacity", opacity)

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
    setSettingValue(component, "borderThickness", thickness)
    setSettingValue(component, "borderInsetH", insetH)
    setSettingValue(component, "borderInsetV", insetV)
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
-- Uses the same recursion-guard hook pattern as hidePRDBarTextures.
local function hidePRDManaCostPrediction(powerBar, hidden)
    if not powerBar then return end
    local manaCostBar = powerBar.ManaCostPredictionBar
    if not manaCostBar then return end

    local flagName = "_ScootPRDManaCostHidden"

    local function installAlphaHook(tex, flag)
        if not tex then return end
        local st = getState(tex)
        if not st then return end
        local hookKey = flag .. "Hooked"
        if st[hookKey] then return end
        st[hookKey] = true

        if _G.hooksecurefunc and tex.SetAlpha then
            _G.hooksecurefunc(tex, "SetAlpha", function(self, alpha)
                if getProp(self, flag) and alpha and alpha > 0 then
                    if not getProp(self, "_ScootPRDSettingAlpha") then
                        setProp(self, "_ScootPRDSettingAlpha", true)
                        pcall(self.SetAlpha, self, 0)
                        setProp(self, "_ScootPRDSettingAlpha", nil)
                    end
                end
            end)
        end

        if _G.hooksecurefunc and tex.Show then
            _G.hooksecurefunc(tex, "Show", function(self)
                if getProp(self, flag) and self.SetAlpha then
                    if not getProp(self, "_ScootPRDSettingAlpha") then
                        setProp(self, "_ScootPRDSettingAlpha", true)
                        pcall(self.SetAlpha, self, 0)
                        setProp(self, "_ScootPRDSettingAlpha", nil)
                    end
                end
            end)
        end
    end

    if hidden then
        setProp(manaCostBar, flagName, true)
        if manaCostBar.SetAlpha then pcall(manaCostBar.SetAlpha, manaCostBar, 0) end
        installAlphaHook(manaCostBar, flagName)
    else
        setProp(manaCostBar, flagName, false)
        if manaCostBar.SetAlpha then pcall(manaCostBar.SetAlpha, manaCostBar, 1) end
    end
end

--------------------------------------------------------------------------------
-- Texture Hiding
--------------------------------------------------------------------------------

-- Hide/restore PRD bar fill texture and background, using the same immediate
-- recursion-guard hook pattern as the Player UF SetPowerBarTextureOnlyHidden.
local function hidePRDBarTextures(bar, barType, hidden)
    if not bar or type(bar) ~= "table" then return end

    local fillTex = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
    local bgTex = bar.Background or bar.background

    local fillFlag = "_ScootPRDFillHidden_" .. barType
    local bgFlag = "_ScootPRDBGHidden_" .. barType

    local function installAlphaHook(tex, flagName)
        if not tex then return end
        local st = getState(tex)
        if not st then return end
        local hookKey = flagName .. "Hooked"
        if st[hookKey] then return end
        st[hookKey] = true

        if _G.hooksecurefunc and tex.SetAlpha then
            _G.hooksecurefunc(tex, "SetAlpha", function(self, alpha)
                if getProp(self, flagName) and alpha and alpha > 0 then
                    if not getProp(self, "_ScootPRDSettingAlpha") then
                        setProp(self, "_ScootPRDSettingAlpha", true)
                        pcall(self.SetAlpha, self, 0)
                        setProp(self, "_ScootPRDSettingAlpha", nil)
                    end
                end
            end)
        end

        if _G.hooksecurefunc and tex.Show then
            _G.hooksecurefunc(tex, "Show", function(self)
                if getProp(self, flagName) and self.SetAlpha then
                    if not getProp(self, "_ScootPRDSettingAlpha") then
                        setProp(self, "_ScootPRDSettingAlpha", true)
                        pcall(self.SetAlpha, self, 0)
                        setProp(self, "_ScootPRDSettingAlpha", nil)
                    end
                end
            end)
        end
    end

    if hidden then
        if fillTex then
            setProp(fillTex, fillFlag, true)
            if fillTex.SetAlpha then pcall(fillTex.SetAlpha, fillTex, 0) end
            installAlphaHook(fillTex, fillFlag)
        end
        if bgTex then
            setProp(bgTex, bgFlag, true)
            if bgTex.SetAlpha then pcall(bgTex.SetAlpha, bgTex, 0) end
            installAlphaHook(bgTex, bgFlag)
        end
    else
        if fillTex then
            setProp(fillTex, fillFlag, false)
            if fillTex.SetAlpha then pcall(fillTex.SetAlpha, fillTex, 1) end
        end
        if bgTex then
            setProp(bgTex, bgFlag, false)
            if bgTex.SetAlpha then pcall(bgTex.SetAlpha, bgTex, 1) end
        end
    end
end

--------------------------------------------------------------------------------
-- Native Bar Backdrop (12.0.7+)
--------------------------------------------------------------------------------
-- Patch 12.0.7 gave each PRD bar a backdrop texture (the dark background plus a
-- baked-in frame/border edge) using the atlas "UI-HUD-CoolDownManager-Bar-BG".
-- It is an anonymous BACKGROUND-layer texture (no parentKey), so we locate it by
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
local function setNativeBarBackgroundHidden(bar, barType, hidden)
    if not bar then return end
    local bgTex = findNativeBarBackground(bar)
    if not bgTex then return end

    local flagName = "_ScootPRDBGArtHidden_" .. barType
    local st = getState(bgTex)
    if st and not st[flagName .. "Hooked"] then
        st[flagName .. "Hooked"] = true
        if _G.hooksecurefunc and bgTex.SetAlpha then
            _G.hooksecurefunc(bgTex, "SetAlpha", function(self, alpha)
                if getProp(self, flagName) and alpha and alpha > 0 then
                    if not getProp(self, "_ScootPRDSettingAlpha") then
                        setProp(self, "_ScootPRDSettingAlpha", true)
                        pcall(self.SetAlpha, self, 0)
                        setProp(self, "_ScootPRDSettingAlpha", nil)
                    end
                end
            end)
        end
        if _G.hooksecurefunc and bgTex.Show then
            _G.hooksecurefunc(bgTex, "Show", function(self)
                if getProp(self, flagName) and self.SetAlpha then
                    if not getProp(self, "_ScootPRDSettingAlpha") then
                        setProp(self, "_ScootPRDSettingAlpha", true)
                        pcall(self.SetAlpha, self, 0)
                        setProp(self, "_ScootPRDSettingAlpha", nil)
                    end
                end
            end)
        end
    end

    if hidden then
        setProp(bgTex, flagName, true)
        pcall(bgTex.SetAlpha, bgTex, 0)
    else
        setProp(bgTex, flagName, false)
        pcall(bgTex.SetAlpha, bgTex, 1)
    end
end

--------------------------------------------------------------------------------
-- Health Loss Animation
--------------------------------------------------------------------------------

-- Helper to get the animated loss bar frame from PlayerFrame
local function getPRDAnimatedLossBar()
    return PlayerFrame
        and PlayerFrame.PlayerFrameContent
        and PlayerFrame.PlayerFrameContent.PlayerFrameContentMain
        and PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.HealthBarsContainer
        and PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.HealthBarsContainer.PlayerFrameHealthBarAnimatedLoss
end

-- Hide/show the health loss animation (the dark red bar that appears when taking damage)
local function applyPRDHealthLossAnimationVisibility(component)
    local hideAnim = ensureSettingValue(component, "hideHealthLossAnimation") and true or false
    local animatedLossBar = getPRDAnimatedLossBar()

    if not animatedLossBar then return end

    if hideAnim then
        pcall(animatedLossBar.Hide, animatedLossBar)
        -- Install hook to keep it hidden (same pattern as hidePRDBarTextures)
        if not getProp(animatedLossBar, "_ScootHideLossAnimHooked") then
            setProp(animatedLossBar, "_ScootHideLossAnimHooked", true)
            pcall(function()
                hooksecurefunc(animatedLossBar, "Show", function(self)
                    if getProp(self, "_ScootHideLossAnim") then
                        pcall(self.Hide, self)
                    end
                end)
            end)
        end
        setProp(animatedLossBar, "_ScootHideLossAnim", true)
    else
        setProp(animatedLossBar, "_ScootHideLossAnim", false)
        -- Don't force Show - let Blizzard control visibility naturally
    end
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
    -- Bar visibility is driven natively in applyHealthOffsets (Edit Mode HideHealth,
    -- which SetShown()s the container and reflows the rest of the PRD). This path runs
    -- only when the bar is shown; apply Scoot's state-based opacity on top.
    local alpha = PRD._getPRDOpacityForState("prdHealth")
    pcall(container.SetAlpha, container, alpha)
    pcall(statusBar.SetAlpha, statusBar, alpha)
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
    local hide = ensureSettingValue(component, "hideBar") and true or false
    setSettingValue(component, "hideBar", hide)
    -- 12.0.7: native HideClassInfo SetShown()s + reflows the ClassFrameContainer.
    writePRDNative("hide_class_info", hide)
    -- 12.0.7: independent native toggle that removes the class resource from the
    -- regular Player Frame (not the PRD). Event-driven on Blizzard's side.
    local hideOnPlayer = ensureSettingValue(component, "hideClassInfoOnPlayerFrame") and true or false
    writePRDNative("hide_class_info_on_player_frame", hideOnPlayer)
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
    component.db.scale = value
    return value / 100
end

--------------------------------------------------------------------------------
-- Applicators
--------------------------------------------------------------------------------
-- NOTE: The old HealthBarsContainer Show-hook (which re-hid the container after
-- Blizzard reshowed it) was retired in 12.0.7. Hiding now flows through the native
-- HideHealth Edit Mode setting, so Blizzard's own clean rebuild owns the container's
-- shown state — removing a hook on a system-frame-tree member (taint risk, Rule 11).

local function applyHealthOffsets(component)
    -- PRD is PersonalResourceDisplayFrame (parented to UIParent), not a nameplate.
    -- Positioning is handled by Edit Mode; this function applies sizing, styling, and visibility.
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

    -- 12.0.7: drive Blizzard's native HideHealth via Edit Mode. It SetShown()s the
    -- HealthBarsContainer and reflows the rest of the PRD (power moves up to fill the
    -- gap) in an untainted context — replacing the old container:Hide() + Show-hook,
    -- which touched the system-frame tree.
    local hide = ensureSettingValue(component, "hideBar") and true or false
    writePRDNative("hide_health", hide)
    if hide then
        local statusBar = container.healthBar or container.HealthBar
        if statusBar then
            clearBarBorder(statusBar)
        end
        hidePRDBarOverlay("health")
        PRD._hideTextOverlay("health")
        return
    end

    -- Sizing: apply barWidth/barHeight
    local baseWidth = getProp(container, "_ScootBaseWidth")
    if not baseWidth or baseWidth <= 0 then
        local ok, w = pcall(container.GetWidth, container)
        baseWidth = (ok and w and w > 0) and w or 200
        setProp(container, "_ScootBaseWidth", baseWidth)
    end

    if component.settings and component.settings.barWidth then
        local defaultWidth = math.floor(baseWidth + 0.5)
        if component.settings.barWidth.default ~= defaultWidth then
            component.settings.barWidth.default = defaultWidth
        end
    end

    local storedWidth = component.db and component.db.barWidth
    if storedWidth then
        storedWidth = clampValue(math.floor(storedWidth + 0.5), MIN_HEALTH_BAR_WIDTH, MAX_HEALTH_BAR_WIDTH)
    end

    local baseHeight = getProp(container, "_ScootBaseHeight")
    if not baseHeight or baseHeight <= 0 then
        local ok, h = pcall(container.GetHeight, container)
        baseHeight = (ok and h and h > 0) and h or 12
        setProp(container, "_ScootBaseHeight", baseHeight)
    end

    if component.settings and component.settings.barHeight then
        local defaultHeight = math.floor(baseHeight + 0.5)
        if component.settings.barHeight.default ~= defaultHeight then
            component.settings.barHeight.default = defaultHeight
        end
    end

    local storedHeight = component.db and component.db.barHeight
    if storedHeight then
        storedHeight = clampValue(math.floor(storedHeight + 0.5), MIN_HEALTH_BAR_HEIGHT, MAX_HEALTH_BAR_HEIGHT)
    end

    local desiredWidth = storedWidth or baseWidth
    local desiredHeight = storedHeight or baseHeight

    -- Apply sizing
    if desiredWidth ~= baseWidth then
        pcall(container.SetWidth, container, desiredWidth)
    end
    if desiredHeight ~= baseHeight then
        pcall(container.SetHeight, container, desiredHeight)
    end

    local statusBar = container.healthBar or container.HealthBar
    if statusBar then
        pcall(statusBar.SetAllPoints, statusBar, container)
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

    -- 12.0.7: drive Blizzard's native HidePower via Edit Mode (PowerBar:SetShown() +
    -- layout reflow), replacing the direct Hide()/SetAlpha(0).
    local hide = ensureSettingValue(component, "hideBar") and true or false
    writePRDNative("hide_power", hide)

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

    -- Sizing: apply barHeight
    local baseHeight = getProp(frame, "_ScootBaseHeight")
    if not baseHeight or baseHeight <= 0 then
        local ok, h = pcall(frame.GetHeight, frame)
        baseHeight = (ok and h and h > 0) and h or 8
        setProp(frame, "_ScootBaseHeight", baseHeight)
    end

    if component.settings and component.settings.barHeight then
        local defaultHeight = math.floor(baseHeight + 0.5)
        if component.settings.barHeight.default ~= defaultHeight then
            component.settings.barHeight.default = defaultHeight
        end
    end

    local storedHeight = component.db and component.db.barHeight
    if storedHeight then
        storedHeight = clampValue(math.floor(storedHeight + 0.5), MIN_POWER_BAR_HEIGHT, MAX_POWER_BAR_HEIGHT)
        if storedHeight ~= baseHeight then
            pcall(frame.SetHeight, frame, storedHeight)
        end
    end

    -- Apply visuals (styling, text overlays)
    if frame.GetStatusBarTexture then
        applyPRDPowerVisuals(component, frame)
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
PRD._applyClassResourceOffsets = applyClassResourceOffsets
PRD._hidePRDBarOverlay = hidePRDBarOverlay
