--------------------------------------------------------------------------------
-- bars/smallframes.lua
-- Consolidated handler for Pet, TargetOfTarget, FocusTarget unit frame bars.
-- These three units share nearly identical styling logic — only the border
-- anchor key, unit token, and power bar resolution differ.
--------------------------------------------------------------------------------

local addonName, addon = ...

-- Create module namespace
addon.BarsSmallFrames = addon.BarsSmallFrames or {}
local SF = addon.BarsSmallFrames

-- Reference extracted modules (loaded via TOC before this file)
local Resolvers = addon.BarsResolvers
local Textures = addon.BarsTextures
local Alpha = addon.BarsAlpha
local BarsOverlays = addon.BarsOverlays

local Util = addon.ComponentsUtil

-- Reference to FrameState module for safe property storage
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

-- Resolver functions
local resolveHealthBar = Resolvers.resolveHealthBar
local resolvePowerBar = Resolvers.resolvePowerBar
local resolveUnitFrameFrameTexture = Resolvers.resolveUnitFrameFrameTexture

-- Alpha functions
local applyAlpha = Alpha.applyAlpha
local hookAlphaEnforcer = Alpha.hookAlphaEnforcer

-- Texture functions
local applyBackgroundToBar = Textures.applyBackgroundToBar

-- Overlay functions
local ensureRectHealthOverlay = BarsOverlays._ensureRectHealthOverlay

-- Per-unit configuration: maps unit name to its specific parameters
local UNIT_CONFIG = {
    Pet = {
        borderAnchorKey = "petHealthBorderAnchor",
        unitToken = "pet",
        hasManaBarFallback = true, -- Pet uses _G.PetFrameManaBar fallback
    },
    TargetOfTarget = {
        borderAnchorKey = "totHealthBorderAnchor",
        unitToken = "targettarget",
        hasManaBarFallback = false,
    },
    FocusTarget = {
        borderAnchorKey = "fotHealthBorderAnchor",
        unitToken = "focustarget",
        hasManaBarFallback = false,
    },
}
table.freeze(UNIT_CONFIG)

--------------------------------------------------------------------------------
-- applyForSmallUnit: Unified handler for Pet, TargetOfTarget, FocusTarget
--------------------------------------------------------------------------------

function SF.applyForSmallUnit(unit, frame, cfg)
    local unitCfg = UNIT_CONFIG[unit]
    if not unitCfg then return end

    local borderAnchorKey = unitCfg.borderAnchorKey

    -- Hide FrameTexture (art hiding)
    local ft = resolveUnitFrameFrameTexture(unit)
    if ft then
        local function compute()
            local db2 = addon and addon.db and addon.db.profile
            local unitFrames2 = db2 and rawget(db2, "unitFrames") or nil
            local cfg2 = unitFrames2 and rawget(unitFrames2, unit) or nil
            local hide = cfg2 and (cfg2.useCustomBorders or cfg2.healthBarHideBorder)
            return hide and 0 or 1
        end
        applyAlpha(ft, compute())
        hookAlphaEnforcer(ft, compute)
    end

    -- OVERLAY APPROACH: Instead of calling applyToBar() (which writes SetStatusBarTexture
    -- to Blizzard's bar and can trigger heal prediction updates), use ensureRectHealthOverlay()
    -- which creates an addon-owned overlay texture. The overlay uses SetAllPoints(statusBarTex)
    -- anchoring instead of reading values.
    local hb = resolveHealthBar(frame, unit)
    local healthBarHideTextureOnly = (cfg.healthBarHideTextureOnly == true)

    -- Apply texture-only hiding (hide fill + background, keep text)
    if hb then
        if healthBarHideTextureOnly then
            if Util and Util.SetHealthBarTextureOnlyHidden then
                Util.SetHealthBarTextureOnlyHidden(hb, true)
            end
        else
            if Util and Util.SetHealthBarTextureOnlyHidden then
                Util.SetHealthBarTextureOnlyHidden(hb, false)
            end
        end
    end

    if hb then
        ensureRectHealthOverlay(unit, hb, cfg)
    end

    -- Apply foreground color mode
    local st = getState(hb)
    if st and st.rectActive and st.rectFill then
        local colorMode = cfg.healthBarColorMode or "default"
        local tint = cfg.healthBarTint
        local overlay = st.rectFill

        if colorMode == "value" or colorMode == "valueDark" then
            local useDark = (colorMode == "valueDark")
            if addon.BarsTextures and addon.BarsTextures.applyValueBasedColor then
                addon.BarsTextures.applyValueBasedColor(hb, unitCfg.unitToken, overlay, useDark)
            end
            st.valueColorOverlay = overlay
            st.valueColorUseDark = useDark
        elseif colorMode == "custom" and type(tint) == "table" then
            overlay:SetVertexColor(tint[1] or 1, tint[2] or 1, tint[3] or 1, tint[4] or 1)
        elseif colorMode == "class" and addon.GetClassColorRGB then
            local cr, cg, cb = addon.GetClassColorRGB(unitCfg.unitToken)
            if cr == nil and addon.GetDefaultHealthColorRGB then
                cr, cg, cb = addon.GetDefaultHealthColorRGB()
            end
            overlay:SetVertexColor(cr or 1, cg or 1, cb or 1, 1)
        elseif colorMode == "texture" then
            overlay:SetVertexColor(1, 1, 1, 1)
        elseif colorMode == "default" then
            if addon.GetDefaultHealthColorRGB then
                local hr, hg, hb_color = addon.GetDefaultHealthColorRGB()
                overlay:SetVertexColor(hr or 0, hg or 1, hb_color or 0, 1)
            else
                overlay:SetVertexColor(0, 1, 0, 1)
            end
        end
    end

    -- Apply background texture (overlay only handles foreground)
    if hb then
        local bgTexKeyHB = cfg.healthBarBackgroundTexture
        local bgColorModeHB = cfg.healthBarBackgroundColorMode
        local bgOpacityHB = tonumber(cfg.healthBarBackgroundOpacity)
        local hasBackgroundCustomization = bgTexKeyHB or bgColorModeHB or (bgOpacityHB and bgOpacityHB ~= 1)
        if hasBackgroundCustomization then
            applyBackgroundToBar(hb, bgTexKeyHB, bgColorModeHB, cfg.healthBarBackgroundTint, bgOpacityHB, unit, "health")
        end
    end

    -- Re-apply texture-only hide after styling (ensures newly created ScootBG is also hidden)
    -- Only Pet had this originally, but it's safe for all small frames
    if hb and healthBarHideTextureOnly then
        if Util and Util.SetHealthBarTextureOnlyHidden then
            Util.SetHealthBarTextureOnlyHidden(hb, true)
        end
    end

    -- BORDER APPROACH: BarBorders.ApplyToBarFrame uses GetFrameLevel/GetHeight
    -- without pcall wrappers, which can trigger secret value errors. Use an addon-owned
    -- anchor frame like Boss frames do.
    if hb and healthBarHideTextureOnly then
        -- Clear any custom borders so only text remains
        local anchor = getProp(hb, borderAnchorKey)
        if anchor then
            if addon.BarBorders and addon.BarBorders.ClearBarFrame then
                addon.BarBorders.ClearBarFrame(anchor)
            end
            if addon.Borders and addon.Borders.HideAll then
                addon.Borders.HideAll(anchor)
            end
        end
    elseif hb and cfg.useCustomBorders then
        local styleKey = cfg.healthBarBorderStyle
        local hiddenEdges = cfg.healthBarBorderHiddenEdges
        if styleKey == "none" or styleKey == nil then
            -- Clear any existing border
            if addon.BarBorders and addon.BarBorders.ClearBarFrame then
                local anchor = getProp(hb, borderAnchorKey)
                if anchor then addon.BarBorders.ClearBarFrame(anchor) end
            end
            if addon.Borders and addon.Borders.HideAll then
                local anchor = getProp(hb, borderAnchorKey)
                if anchor then addon.Borders.HideAll(anchor) end
            end
        else
            -- Create or retrieve border anchor frame
            local anchorFrame = getProp(hb, borderAnchorKey)
            if not anchorFrame then
                anchorFrame = CreateFrame("Frame", nil, hb)
                setProp(hb, borderAnchorKey, anchorFrame)
            end
            anchorFrame:ClearAllPoints()
            anchorFrame:SetAllPoints(hb)
            -- Set frame level above the health bar so borders draw on top
            local parentLevel = 10 -- fallback if GetFrameLevel returns secret
            local ok, level = pcall(function() return hb:GetFrameLevel() end)
            if ok and type(level) == "number" then
                parentLevel = level
            end
            anchorFrame:SetFrameLevel(parentLevel + 5)
            anchorFrame:Show()

            -- Apply border settings
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

            -- Clear old borders first
            if addon.BarBorders and addon.BarBorders.ClearBarFrame then
                addon.BarBorders.ClearBarFrame(anchorFrame)
            end
            if addon.Borders and addon.Borders.HideAll then
                addon.Borders.HideAll(anchorFrame)
            end

            -- Use Borders.ApplySquare with skipDimensionCheck (anchor dimensions are inherited via SetAllPoints)
            if addon.Borders and addon.Borders.ApplySquare then
                local sqColor = tintEnabled and tintColor or {0, 0, 0, 1}
                local baseOffset = 1
                local expandX = baseOffset - insetH
                local expandY = baseOffset - insetV
                if expandX < -6 then expandX = -6 elseif expandX > 6 then expandX = 6 end
                if expandY < -6 then expandY = -6 elseif expandY > 6 then expandY = 6 end
                addon.Borders.ApplySquare(anchorFrame, {
                    size = thickness,
                    color = sqColor,
                    layer = "OVERLAY",
                    layerSublevel = 3,
                    expandX = expandX,
                    expandY = expandY,
                    skipDimensionCheck = true, -- Bypass GetWidth/GetHeight check
                    hiddenEdges = hiddenEdges,
                })
            end
        end
    end

    -- Power bar visibility (hide/show via alpha enforcer only)
    local pb = resolvePowerBar(frame, unit)
    if not pb and unitCfg.hasManaBarFallback then
        pb = frame and frame.PetFrameManaBar
    end
    if pb then
        local function computePBAlpha()
            local db2 = addon and addon.db and addon.db.profile
            local unitFrames2 = db2 and rawget(db2, "unitFrames") or nil
            local cfg2 = unitFrames2 and rawget(unitFrames2, unit) or nil
            local hidden = cfg2 and cfg2.powerBarHidden
            return hidden and 0 or 1
        end
        applyAlpha(pb, computePBAlpha())
        hookAlphaEnforcer(pb, computePBAlpha)
    end
end

return SF
