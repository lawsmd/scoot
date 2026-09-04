-- procstart.lua - Proc Start (burst/splash) animations and overlay module
-- Registers 10 code-only proc start animations with addon.Animations,
-- plus the addon.ProcStart overlay management module for CDM integration.
local addonName, addon = ...

local Anim = addon.Animations
local W8 = "Interface\\BUTTONS\\WHITE8X8"

--------------------------------------------------------------------------------
-- Animation Registrations
--------------------------------------------------------------------------------

-- 5.1 Flash Pulse: Rapid full-frame blink (NES hit-stun flash)
Anim.Register({
    id = "procStartFlashPulse",
    category = "alert",
    buildAnimGroup = function(tex)
        tex:SetTexture(W8)
        tex:SetVertexColor(1, 1, 1, 0)

        local ag = tex:CreateAnimationGroup()
        ag:SetLooping("REPEAT")

        local flash = ag:CreateAnimation("Alpha")
        flash:SetFromAlpha(0)
        flash:SetToAlpha(0.9)
        flash:SetDuration(0.10)
        flash:SetSmoothing("IN_OUT")

        local pulseCount = 3
        local count = 0
        ag:SetScript("OnLoop", function(self)
            count = count + 1
            if count >= pulseCount then
                self:Stop()
                count = 0
            end
        end)

        ag:SetScript("OnPlay", function()
            count = 0
        end)

        ag:SetScript("OnStop", function()
            tex:SetAlpha(0)
            -- REPEAT+Stop doesn't fire OnFinished, so hide frame manually
            local f = tex:GetParent()
            if f then f:Hide() end
        end)

        return ag
    end,
})

-- 5.2 Scale Burst: Square scales up from center and fades
Anim.Register({
    id = "procStartScaleBurst",
    category = "alert",
    buildAnimGroup = function(tex)
        tex:SetTexture(W8)
        tex:SetVertexColor(1, 1, 1, 0.8)

        local ag = tex:CreateAnimationGroup()

        local scale = ag:CreateAnimation("Scale")
        scale:SetScaleFrom(0.3, 0.3)
        scale:SetScaleTo(1.5, 1.5)
        scale:SetDuration(0.4)
        scale:SetSmoothing("OUT")
        scale:SetOrder(1)

        local fade = ag:CreateAnimation("Alpha")
        fade:SetFromAlpha(0.8)
        fade:SetToAlpha(0)
        fade:SetDuration(0.4)
        fade:SetOrder(1)

        ag:SetToFinalAlpha(true)
        return ag
    end,
})

-- 5.3 Ring Expand: Hollow ring expands outward (sonar pulse)
Anim.Register({
    id = "procStartRingExpand",
    category = "alert",
    buildAnimGroup = function(tex)
        local ok = pcall(tex.SetAtlas, tex, "heartofazeroth-slot-minor-ring")
        if not ok then
            pcall(tex.SetAtlas, tex, "WhiteCircle-RaidBlips")
        end
        tex:SetVertexColor(1, 1, 1, 0.9)

        local ag = tex:CreateAnimationGroup()

        local scale = ag:CreateAnimation("Scale")
        scale:SetScaleFrom(0.5, 0.5)
        scale:SetScaleTo(1.4, 1.4)
        scale:SetDuration(0.4)
        scale:SetSmoothing("OUT")
        scale:SetOrder(1)

        local fade = ag:CreateAnimation("Alpha")
        fade:SetFromAlpha(0.9)
        fade:SetToAlpha(0)
        fade:SetDuration(0.4)
        fade:SetOrder(1)

        ag:SetToFinalAlpha(true)
        return ag
    end,
})

-- 5.8 Spin Fade: Square spins, grows, and fades (shuriken/card flip)
Anim.Register({
    id = "procStartSpinFade",
    category = "alert",
    buildAnimGroup = function(tex)
        tex:SetTexture(W8)
        tex:SetVertexColor(1, 1, 1, 0.85)

        local ag = tex:CreateAnimationGroup()

        local spin = ag:CreateAnimation("Rotation")
        spin:SetDegrees(180)
        spin:SetDuration(0.4)
        spin:SetSmoothing("OUT")
        spin:SetOrder(1)

        local scale = ag:CreateAnimation("Scale")
        scale:SetScaleFrom(0.5, 0.5)
        scale:SetScaleTo(1.3, 1.3)
        scale:SetDuration(0.4)
        scale:SetSmoothing("OUT")
        scale:SetOrder(1)

        local fade = ag:CreateAnimation("Alpha")
        fade:SetFromAlpha(0.85)
        fade:SetToAlpha(0)
        fade:SetDuration(0.4)
        fade:SetOrder(1)

        ag:SetToFinalAlpha(true)
        return ag
    end,
})

-- Multi-texture buildController with auto-hide on finish. Lives on the registry
-- now that Cast Bar Z's completion effects need the same shape (animations.lua).
local buildMultiTextureController = Anim.BuildMultiTextureController

-- 5.4 Cross Flare: Four thin lines shoot outward from center (+X/-X/+Y/-Y)
Anim.Register({
    id = "procStartCrossFlare",
    category = "alert",
    buildController = function(frame)
        return buildMultiTextureController(frame, function(f, textures, animGroups)
            local thickness = 2
            local length = 12
            local arms = {
                { 0, 20 },   -- up
                { 0, -20 },  -- down
                { 20, 0 },   -- right
                { -20, 0 },  -- left
            }
            for i, offset in ipairs(arms) do
                local tex = f:CreateTexture(nil, "OVERLAY")
                tex:SetTexture(W8)
                tex:SetVertexColor(1, 1, 1, 0.9)
                if offset[1] == 0 then
                    tex:SetSize(thickness, length)
                else
                    tex:SetSize(length, thickness)
                end
                tex:SetPoint("CENTER", f, "CENTER", 0, 0)
                textures[i] = tex

                local ag = tex:CreateAnimationGroup()
                local move = ag:CreateAnimation("Translation")
                move:SetOffset(offset[1], offset[2])
                move:SetDuration(0.5)
                move:SetSmoothing("OUT")
                move:SetOrder(1)

                local fade = ag:CreateAnimation("Alpha")
                fade:SetFromAlpha(0.9)
                fade:SetToAlpha(0)
                fade:SetDuration(0.5)
                fade:SetOrder(1)

                ag:SetToFinalAlpha(true)
                animGroups[i] = ag
            end
        end)
    end,
})

-- 5.5 Diamond Burst: Four small squares fly diagonally (Mega Man Pop)
Anim.Register({
    id = "procStartDiamondBurst",
    category = "alert",
    buildController = function(frame)
        return buildMultiTextureController(frame, function(f, textures, animGroups)
            local size = 4
            local dist = 20
            local dirs = {
                { dist,  dist },
                { -dist, dist },
                { dist,  -dist },
                { -dist, -dist },
            }
            for i, dir in ipairs(dirs) do
                local tex = f:CreateTexture(nil, "OVERLAY")
                tex:SetTexture(W8)
                tex:SetVertexColor(1, 1, 1, 1.0)
                tex:SetSize(size, size)
                tex:SetPoint("CENTER", f, "CENTER", 0, 0)
                textures[i] = tex

                local ag = tex:CreateAnimationGroup()
                local move = ag:CreateAnimation("Translation")
                move:SetOffset(dir[1], dir[2])
                move:SetDuration(0.5)
                move:SetSmoothing("OUT")
                move:SetOrder(1)

                local fade = ag:CreateAnimation("Alpha")
                fade:SetFromAlpha(1.0)
                fade:SetToAlpha(0)
                fade:SetDuration(0.5)
                fade:SetOrder(1)

                ag:SetToFinalAlpha(true)
                animGroups[i] = ag
            end
        end)
    end,
})

-- 5.6 Starburst: 8 thin rays shoot outward from center at 45deg intervals
Anim.Register({
    id = "procStartStarburst",
    category = "alert",
    buildController = function(frame)
        return buildMultiTextureController(frame, function(f, textures, animGroups)
            local thickness = 2
            local rayLength = 12
            local rayCount = 8
            local dist = 18
            for i = 1, rayCount do
                local angle = (i - 1) * (2 * math.pi / rayCount)
                local tex = f:CreateTexture(nil, "OVERLAY")
                tex:SetTexture(W8)
                tex:SetVertexColor(1, 1, 1, 0.9)
                tex:SetSize(thickness, rayLength)
                tex:SetPoint("CENTER", f, "CENTER", 0, 0)
                tex:SetRotation(angle)
                textures[i] = tex

                local ag = tex:CreateAnimationGroup()

                -- Move outward along the ray's direction
                local dx = math.sin(angle) * dist
                local dy = math.cos(angle) * dist
                local move = ag:CreateAnimation("Translation")
                move:SetOffset(dx, dy)
                move:SetDuration(0.4)
                move:SetSmoothing("OUT")
                move:SetOrder(1)

                local fade = ag:CreateAnimation("Alpha")
                fade:SetFromAlpha(0.9)
                fade:SetToAlpha(0)
                fade:SetDuration(0.4)
                fade:SetOrder(1)

                ag:SetToFinalAlpha(true)
                animGroups[i] = ag
            end
        end)
    end,
})

-- 5.7 Pixel Scatter: 6 tiny squares fly outward in varied directions
Anim.Register({
    id = "procStartPixelScatter",
    category = "alert",
    buildController = function(frame)
        return buildMultiTextureController(frame, function(f, textures, animGroups)
            local size = 3
            local directions = {
                { 18,  12 },
                { -14, 16 },
                { 20,  -8 },
                { -18, -14 },
                { 6,   22 },
                { -8,  -20 },
            }
            for i, dir in ipairs(directions) do
                local tex = f:CreateTexture(nil, "OVERLAY")
                tex:SetTexture(W8)
                tex:SetVertexColor(1, 1, 1, 1.0)
                tex:SetSize(size, size)
                tex:SetPoint("CENTER", f, "CENTER", 0, 0)
                textures[i] = tex

                local ag = tex:CreateAnimationGroup()
                local move = ag:CreateAnimation("Translation")
                move:SetOffset(dir[1], dir[2])
                move:SetDuration(0.5)
                move:SetSmoothing("OUT")
                move:SetOrder(1)

                local fade = ag:CreateAnimation("Alpha")
                fade:SetFromAlpha(1.0)
                fade:SetToAlpha(0)
                fade:SetDuration(0.5)
                fade:SetOrder(1)

                local shrink = ag:CreateAnimation("Scale")
                shrink:SetScaleFrom(1.0, 1.0)
                shrink:SetScaleTo(0.3, 0.3)
                shrink:SetDuration(0.5)
                shrink:SetSmoothing("IN")
                shrink:SetOrder(1)

                ag:SetToFinalAlpha(true)
                animGroups[i] = ag
            end
        end)
    end,
})

-- 5.9 Corner Brackets: Four L-shaped brackets expand from icon corners
Anim.Register({
    id = "procStartCornerBrackets",
    category = "alert",
    buildController = function(frame)
        return buildMultiTextureController(frame, function(f, textures, animGroups)
            local thick = 2
            local armLen = 8
            local corners = {
                { "TOPLEFT",     {armLen, thick}, {thick, armLen}, {armLen/2, 0},  {0, -armLen/2}, -6,  6 },
                { "TOPRIGHT",    {armLen, thick}, {thick, armLen}, {-armLen/2, 0}, {0, -armLen/2},  6,  6 },
                { "BOTTOMLEFT",  {armLen, thick}, {thick, armLen}, {armLen/2, 0},  {0, armLen/2},  -6, -6 },
                { "BOTTOMRIGHT", {armLen, thick}, {thick, armLen}, {-armLen/2, 0}, {0, armLen/2},   6, -6 },
            }
            for _, c in ipairs(corners) do
                local anchor, hSize, vSize, hOff, vOff, mx, my = c[1], c[2], c[3], c[4], c[5], c[6], c[7]

                -- Horizontal arm
                local hTex = f:CreateTexture(nil, "OVERLAY")
                hTex:SetTexture(W8)
                hTex:SetVertexColor(1, 1, 1, 0.9)
                hTex:SetSize(hSize[1], hSize[2])
                hTex:SetPoint(anchor, f, anchor, hOff[1], hOff[2])
                textures[#textures + 1] = hTex

                local hAg = hTex:CreateAnimationGroup()
                local hMove = hAg:CreateAnimation("Translation")
                hMove:SetOffset(mx, my)
                hMove:SetDuration(0.4)
                hMove:SetSmoothing("OUT")
                hMove:SetOrder(1)
                local hFade = hAg:CreateAnimation("Alpha")
                hFade:SetFromAlpha(0.9)
                hFade:SetToAlpha(0)
                hFade:SetDuration(0.4)
                hFade:SetOrder(1)
                hAg:SetToFinalAlpha(true)
                animGroups[#animGroups + 1] = hAg

                -- Vertical arm
                local vTex = f:CreateTexture(nil, "OVERLAY")
                vTex:SetTexture(W8)
                vTex:SetVertexColor(1, 1, 1, 0.9)
                vTex:SetSize(vSize[1], vSize[2])
                vTex:SetPoint(anchor, f, anchor, vOff[1], vOff[2])
                textures[#textures + 1] = vTex

                local vAg = vTex:CreateAnimationGroup()
                local vMove = vAg:CreateAnimation("Translation")
                vMove:SetOffset(mx, my)
                vMove:SetDuration(0.4)
                vMove:SetSmoothing("OUT")
                vMove:SetOrder(1)
                local vFade = vAg:CreateAnimation("Alpha")
                vFade:SetFromAlpha(0.9)
                vFade:SetToAlpha(0)
                vFade:SetDuration(0.4)
                vFade:SetOrder(1)
                vAg:SetToFinalAlpha(true)
                animGroups[#animGroups + 1] = vAg
            end
        end)
    end,
})

-- 5.10 Double Ring: Two concentric rings expand with staggered timing
Anim.Register({
    id = "procStartDoubleRing",
    category = "alert",
    buildController = function(frame)
        return buildMultiTextureController(frame, function(f, textures, animGroups)
            local function makeRing(scaleFrom, scaleTo, alphaFrom, delay, dur)
                local tex = f:CreateTexture(nil, "OVERLAY")
                pcall(tex.SetAtlas, tex, "heartofazeroth-slot-minor-ring")
                tex:SetVertexColor(1, 1, 1, alphaFrom)
                tex:SetAllPoints(f)
                textures[#textures + 1] = tex

                local ag = tex:CreateAnimationGroup()
                local scale = ag:CreateAnimation("Scale")
                scale:SetScaleFrom(scaleFrom, scaleFrom)
                scale:SetScaleTo(scaleTo, scaleTo)
                scale:SetDuration(dur)
                scale:SetSmoothing("OUT")
                scale:SetStartDelay(delay)
                scale:SetOrder(1)

                local fade = ag:CreateAnimation("Alpha")
                fade:SetFromAlpha(alphaFrom)
                fade:SetToAlpha(0)
                fade:SetDuration(dur)
                fade:SetStartDelay(delay)
                fade:SetOrder(1)

                ag:SetToFinalAlpha(true)
                animGroups[#animGroups + 1] = ag
            end

            makeRing(0.3, 1.0, 1.0, 0, 0.3)
            makeRing(0.5, 1.5, 0.6, 0.08, 0.4)
        end)
    end,
})

--------------------------------------------------------------------------------
-- addon.ProcStart — Overlay Management Module
--------------------------------------------------------------------------------

-- Per-animation metadata (squareOnly forces square frame, supportsScale enables particle scaling)
local ANIM_META = {
    procStartFlashPulse     = {},
    procStartScaleBurst     = {},
    procStartRingExpand     = { squareOnly = true },
    procStartSpinFade       = { squareOnly = true },
    procStartCrossFlare     = { supportsScale = true },
    procStartDiamondBurst   = { supportsScale = true },
    procStartStarburst      = { supportsScale = true },
    procStartPixelScatter   = { supportsScale = true },
    procStartCornerBrackets = { supportsScale = true },
    procStartDoubleRing     = { squareOnly = true },
}

addon.ProcStart = addon.ProcStart or {}
local PS = addon.ProcStart

-- Expose metadata for UI (disabled state of scale slider)
PS.ANIM_META = ANIM_META

local activeOverlays = setmetatable({}, { __mode = "k" })  -- cdmIcon -> controller
local overlayPools = {}  -- [animId] -> addon.Pool, one free list per animation

--------------------------------------------------------------------------------
-- Color helpers
--------------------------------------------------------------------------------

local function getClassColor()
    local r, g, b = addon.GetClassColorRGB("player")
    return r or 1, g or 1, b or 1, 1
end

local function applyColor(ctrl, colorMode, customColor)
    local r, g, b, a = 1, 1, 1, 1
    if colorMode == "class" then
        r, g, b, a = getClassColor()
    elseif colorMode == "custom" and customColor then
        r = customColor[1] or 1
        g = customColor[2] or 1
        b = customColor[3] or 1
        a = customColor[4] or 1
    end

    local textures = ctrl:GetTextures()
    if textures then
        for _, tex in ipairs(textures) do
            tex:SetVertexColor(r, g, b, a)
        end
    end
end

--------------------------------------------------------------------------------
-- Pool management
--------------------------------------------------------------------------------

local function resetController(ctrl)
    ctrl:Stop()
    ctrl:Hide()
    if ctrl._frame then
        ctrl._frame:ClearAllPoints()
    end
end

-- A controller is built for one animation and only ever serves that one;
-- _procStartAnimId names the free list it returns to.
local function poolFor(animId)
    local pool = overlayPools[animId]
    if not pool then
        pool = addon.Pool.New(function()
            local ctrl = Anim.Create(animId, UIParent)
            if ctrl then
                ctrl._procStartAnimId = animId
            end
            return ctrl
        end, resetController)
        overlayPools[animId] = pool
    end
    return pool
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

function PS.PlayForIcon(cdmIcon, config)
    if not cdmIcon or not config or not config.style then return end

    -- Stop any existing overlay for this icon
    if activeOverlays[cdmIcon] then
        PS.StopForIcon(cdmIcon)
    end

    local animId = config.style

    local ctrl = poolFor(animId):Acquire()
    if not ctrl then return end

    -- Apply color
    applyColor(ctrl, config.colorMode, config.customColor)

    -- Determine size (match icon dimensions)
    local iconW = config.iconW or 42
    local iconH = config.iconH or 42

    -- Force square for animations that look bad stretched (circles, spinners)
    local meta = ANIM_META[animId]
    if meta and meta.squareOnly then
        local maxDim = math.max(iconW, iconH)
        iconW, iconH = maxDim, maxDim
    end
    ctrl:SetSize(iconW, iconH)

    -- Apply particle scale for animations that support it
    -- Store original sizes on first use so pooled controllers scale from base, not cumulative
    local scale = config.scale or 1
    if meta and meta.supportsScale then
        local textures = ctrl:GetTextures()
        if textures then
            if not ctrl._origTexSizes then
                ctrl._origTexSizes = {}
                for i, tex in ipairs(textures) do
                    local w, h = tex:GetSize()
                    ctrl._origTexSizes[i] = { w = w or 3, h = h or 3 }
                end
            end
            for i, tex in ipairs(textures) do
                local orig = ctrl._origTexSizes[i]
                if orig then
                    tex:SetSize(orig.w * scale, orig.h * scale)
                end
            end
        end
    end

    -- Anchor to icon center, match strata and frame level
    local strata = "MEDIUM"
    local level = 30
    pcall(function() strata = cdmIcon:GetFrameStrata() end)
    pcall(function() level = cdmIcon:GetFrameLevel() + 15 end)
    if ctrl._frame then
        ctrl._frame:SetFrameStrata(strata)
        ctrl._frame:SetFrameLevel(level)
        ctrl._frame:ClearAllPoints()
        ctrl._frame:SetPoint("CENTER", cdmIcon, "CENTER", 0, 0)
    end

    -- Store in active table
    activeOverlays[cdmIcon] = ctrl

    ctrl:Play()
end

function PS.StopForIcon(cdmIcon)
    local ctrl = activeOverlays[cdmIcon]
    if ctrl then
        local animId = ctrl._procStartAnimId
        activeOverlays[cdmIcon] = nil
        if animId then
            poolFor(animId):Release(ctrl)
        else
            ctrl:Stop()
        end
    end
end

function PS.StopAll()
    for cdmIcon, ctrl in pairs(activeOverlays) do
        local animId = ctrl._procStartAnimId
        if animId then
            poolFor(animId):Release(ctrl)
        else
            ctrl:Stop()
        end
    end
    wipe(activeOverlays)
end

function PS.GetForIcon(cdmIcon)
    return activeOverlays[cdmIcon]
end

function PS.CreatePreviewController(animId, parent)
    if not animId or not parent then return nil end
    local ctrl = Anim.Create(animId, parent)
    return ctrl
end
