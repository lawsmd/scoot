--------------------------------------------------------------------------------
-- groupauras/animdefs.lua
-- All 12 code-driven animated icon definitions for the aura tracking system.
-- Each animation uses WHITE8X8 textures driven by a 0-1 progress model.
--
-- Depends on groupauras/animengine.lua (AE.RegisterAnim)
--------------------------------------------------------------------------------

local addonName, addon = ...

local HA = addon.AuraTracking
if not HA or not HA.AnimEngine then return end
local AE = HA.AnimEngine

local pi = math.pi
local sin = math.sin
local cos = math.cos
local abs = math.abs
local floor = math.floor
local max = math.max
local min = math.min

--------------------------------------------------------------------------------
-- Shared Helpers
--------------------------------------------------------------------------------

local function defaultApplyColor(ctrl, r, g, b, a)
    local def = AE.GetDef(ctrl.animId)
    local n = def and def.numTextures or 1
    for i = 1, n do
        local tex = ctrl.textures[i]
        if tex and tex:IsShown() then
            tex:SetVertexColor(r, g, b, a)
        end
    end
end

--------------------------------------------------------------------------------
-- 1. Line Spinner
-- A single bar rotating smoothly through orientations.
--------------------------------------------------------------------------------

AE.RegisterAnim({
    id = "line_spinner",
    label = "Line Spinner",
    numTextures = 1,
    period = 0.8,
    setup = function(ctrl, size)
        local tex = ctrl.textures[1]
        local barW = max(2, size * 0.12)
        local barH = max(4, size * 0.55)
        tex:SetSize(barW, barH)
        tex:ClearAllPoints()
        tex:SetPoint("CENTER", ctrl.frame, "CENTER", 0, 0)
    end,
    update = function(ctrl, progress)
        ctrl.textures[1]:SetRotation(progress * pi)
    end,
    applyColor = defaultApplyColor,
})

--------------------------------------------------------------------------------
-- 2. Orbital Dots
-- 5 dots traveling in a circular path around the center.
--------------------------------------------------------------------------------

AE.RegisterAnim({
    id = "orbital_dots",
    label = "Orbital Dots",
    numTextures = 5,
    period = 1.5,
    setup = function(ctrl, size)
        local dotSize = max(2, size * 0.14)
        for i = 1, 5 do
            local tex = ctrl.textures[i]
            -- Lead dot largest, trailing dots smaller
            local scale = 1.0 - (i - 1) * 0.12
            tex:SetSize(dotSize * scale, dotSize * scale)
        end
    end,
    update = function(ctrl, progress)
        local size = ctrl.size
        local cx, cy = 0, 0
        local r = size * 0.32
        local N = 5
        for i = 1, N do
            local theta = (progress + (i - 1) / N) * 2 * pi
            local x = cx + r * cos(theta)
            local y = cy + r * sin(theta)
            local tex = ctrl.textures[i]
            tex:ClearAllPoints()
            tex:SetPoint("CENTER", ctrl.frame, "CENTER", x, y)
        end
    end,
    applyColor = defaultApplyColor,
})

--------------------------------------------------------------------------------
-- 3. Fading Ring
-- 10 dots in a fixed circle; a brightness sweep rotates around the ring.
-- No repositioning — only SetVertexColor changes each frame.
--------------------------------------------------------------------------------

AE.RegisterAnim({
    id = "fading_ring",
    label = "Fading Ring",
    numTextures = 10,
    period = 2.0,
    setup = function(ctrl, size)
        local dotSize = max(2, size * 0.11)
        local r = size * 0.34
        local N = 10
        for i = 1, N do
            local tex = ctrl.textures[i]
            tex:SetSize(dotSize, dotSize)
            local angle = (i - 1) / N * 2 * pi
            local x = r * cos(angle)
            local y = r * sin(angle)
            tex:ClearAllPoints()
            tex:SetPoint("CENTER", ctrl.frame, "CENTER", x, y)
        end
    end,
    update = function(ctrl, progress)
        local N = 10
        local headAngle = progress * 2 * pi
        local cr, cg, cb = ctrl.colorR or 1, ctrl.colorG or 1, ctrl.colorB or 1
        for i = 1, N do
            local dotAngle = (i - 1) / N * 2 * pi
            local dist = (headAngle - dotAngle) % (2 * pi)
            local alpha = max(0.1, 1.0 - dist / (2 * pi))
            ctrl.textures[i]:SetVertexColor(cr, cg, cb, alpha)
        end
    end,
    applyColor = function(ctrl, r, g, b, a)
        ctrl.colorR, ctrl.colorG, ctrl.colorB = r, g, b
        -- Colors are applied per-frame in update via alpha sweep
    end,
})

--------------------------------------------------------------------------------
-- 4. Pulse Dot
-- A single centered dot that grows/shrinks and fades.
--------------------------------------------------------------------------------

AE.RegisterAnim({
    id = "pulse_dot",
    label = "Pulse Dot",
    numTextures = 1,
    period = 1.2,
    setup = function(ctrl, size)
        local tex = ctrl.textures[1]
        tex:ClearAllPoints()
        tex:SetPoint("CENTER", ctrl.frame, "CENTER", 0, 0)
    end,
    update = function(ctrl, progress)
        local size = ctrl.size
        local baseSize = size * 0.25
        local amplitude = size * 0.18
        local wave = sin(progress * 2 * pi)
        local s = baseSize + amplitude * wave
        local alpha = 0.4 + 0.6 * max(0, wave)
        local tex = ctrl.textures[1]
        tex:SetSize(s, s)
        tex:SetVertexColor(ctrl.colorR or 1, ctrl.colorG or 1, ctrl.colorB or 1, alpha)
    end,
    applyColor = function(ctrl, r, g, b, a)
        ctrl.colorR, ctrl.colorG, ctrl.colorB = r, g, b
        -- Alpha managed by update
    end,
})

--------------------------------------------------------------------------------
-- 5. Bouncing Bars (Equalizer)
-- 4 vertical bars oscillating in height with staggered phases.
--------------------------------------------------------------------------------

AE.RegisterAnim({
    id = "bouncing_bars",
    label = "Bouncing Bars",
    numTextures = 4,
    period = 1.0,
    setup = function(ctrl, size)
        local N = 4
        local barW = max(2, size * 0.14)
        local gap = max(1, size * 0.06)
        local totalW = N * barW + (N - 1) * gap
        local startX = -totalW / 2 + barW / 2
        for i = 1, N do
            local tex = ctrl.textures[i]
            tex:SetSize(barW, 1) -- height set per-frame
            tex:ClearAllPoints()
            local x = startX + (i - 1) * (barW + gap)
            tex:SetPoint("BOTTOM", ctrl.frame, "CENTER", x, -size * 0.3)
        end
    end,
    update = function(ctrl, progress)
        local size = ctrl.size
        local maxH = size * 0.6
        local minH = max(2, size * 0.08)
        local N = 4
        local phaseOffset = 2 * pi / N
        for i = 1, N do
            local h = minH + (maxH - minH) * abs(sin(progress * 2 * pi + (i - 1) * phaseOffset))
            local tex = ctrl.textures[i]
            local barW = max(2, size * 0.14)
            tex:SetSize(barW, h)
        end
    end,
    applyColor = defaultApplyColor,
})

--------------------------------------------------------------------------------
-- 6. Ping / Ripple
-- A fixed center dot with a square outline that expands and fades.
-- tex[1] = center dot, tex[2..5] = top/right/bottom/left ring edges
--------------------------------------------------------------------------------

AE.RegisterAnim({
    id = "ping_ripple",
    label = "Ping / Ripple",
    numTextures = 5,
    period = 1.5,
    setup = function(ctrl, size)
        -- Center dot (static)
        local dotSize = max(3, size * 0.16)
        local center = ctrl.textures[1]
        center:SetSize(dotSize, dotSize)
        center:ClearAllPoints()
        center:SetPoint("CENTER", ctrl.frame, "CENTER", 0, 0)

        -- Ring edges: thin bars that form a square
        local thickness = max(1, size * 0.06)
        for i = 2, 5 do
            ctrl.textures[i]:SetSize(thickness, thickness) -- resized per-frame
            ctrl.textures[i]:ClearAllPoints()
        end
    end,
    update = function(ctrl, progress)
        local size = ctrl.size
        local maxR = size * 0.42
        local thickness = max(1, size * 0.06)
        local ringSize = maxR * progress
        local alpha = max(0, 1.0 - progress)
        local cr, cg, cb = ctrl.colorR or 1, ctrl.colorG or 1, ctrl.colorB or 1

        -- Top edge
        local top = ctrl.textures[2]
        top:SetSize(ringSize * 2, thickness)
        top:ClearAllPoints()
        top:SetPoint("CENTER", ctrl.frame, "CENTER", 0, ringSize)
        top:SetVertexColor(cr, cg, cb, alpha)

        -- Bottom edge
        local bottom = ctrl.textures[3]
        bottom:SetSize(ringSize * 2, thickness)
        bottom:ClearAllPoints()
        bottom:SetPoint("CENTER", ctrl.frame, "CENTER", 0, -ringSize)
        bottom:SetVertexColor(cr, cg, cb, alpha)

        -- Left edge
        local left = ctrl.textures[4]
        left:SetSize(thickness, ringSize * 2)
        left:ClearAllPoints()
        left:SetPoint("CENTER", ctrl.frame, "CENTER", -ringSize, 0)
        left:SetVertexColor(cr, cg, cb, alpha)

        -- Right edge
        local right = ctrl.textures[5]
        right:SetSize(thickness, ringSize * 2)
        right:ClearAllPoints()
        right:SetPoint("CENTER", ctrl.frame, "CENTER", ringSize, 0)
        right:SetVertexColor(cr, cg, cb, alpha)
    end,
    applyColor = function(ctrl, r, g, b, a)
        ctrl.colorR, ctrl.colorG, ctrl.colorB = r, g, b
        -- Center dot gets full color
        ctrl.textures[1]:SetVertexColor(r, g, b, a)
        -- Ring edges colored per-frame in update
    end,
})

--------------------------------------------------------------------------------
-- 7. Grid Sweep
-- 3x3 grid of dots; one dot lights up in a spiral pattern.
-- No repositioning — only SetVertexColor each frame.
--------------------------------------------------------------------------------

local GRID_SPIRAL_ORDER = { 1, 2, 3, 6, 9, 8, 7, 4, 5 }

AE.RegisterAnim({
    id = "grid_sweep",
    label = "Grid Sweep",
    numTextures = 9,
    period = 1.5,
    setup = function(ctrl, size)
        local dotSize = max(2, size * 0.18)
        local gap = max(1, size * 0.06)
        local cellSize = dotSize + gap
        for row = 0, 2 do
            for col = 0, 2 do
                local idx = row * 3 + col + 1
                local tex = ctrl.textures[idx]
                tex:SetSize(dotSize, dotSize)
                tex:ClearAllPoints()
                local x = (col - 1) * cellSize
                local y = (1 - row) * cellSize  -- top row = positive y
                tex:SetPoint("CENTER", ctrl.frame, "CENTER", x, y)
            end
        end
    end,
    update = function(ctrl, progress)
        local activeIdx = GRID_SPIRAL_ORDER[floor(progress * 9) % 9 + 1]
        local cr, cg, cb = ctrl.colorR or 1, ctrl.colorG or 1, ctrl.colorB or 1
        for i = 1, 9 do
            if i == activeIdx then
                ctrl.textures[i]:SetVertexColor(cr, cg, cb, 1.0)
            else
                ctrl.textures[i]:SetVertexColor(cr, cg, cb, 0.15)
            end
        end
    end,
    applyColor = function(ctrl, r, g, b, a)
        ctrl.colorR, ctrl.colorG, ctrl.colorB = r, g, b
        -- Per-dot alpha managed by update
    end,
})

--------------------------------------------------------------------------------
-- 8. Bouncing Dot
-- A single dot that bounces up and down with squash deformation at ground.
--------------------------------------------------------------------------------

AE.RegisterAnim({
    id = "bouncing_dot",
    label = "Bouncing Dot",
    numTextures = 1,
    period = 0.8,
    setup = function(ctrl, size)
        local tex = ctrl.textures[1]
        local dotSize = max(3, size * 0.2)
        tex:SetSize(dotSize, dotSize)
        tex:ClearAllPoints()
        tex:SetPoint("CENTER", ctrl.frame, "CENTER", 0, 0)
    end,
    update = function(ctrl, progress)
        local size = ctrl.size
        local dotBase = max(3, size * 0.2)
        local amplitude = size * 0.3
        local yOff = amplitude * abs(sin(progress * pi))
        local groundY = -size * 0.2

        local tex = ctrl.textures[1]
        tex:ClearAllPoints()
        tex:SetPoint("CENTER", ctrl.frame, "CENTER", 0, groundY + yOff)

        -- Squash near ground
        if yOff < amplitude * 0.1 then
            tex:SetSize(dotBase * 1.3, dotBase * 0.7)
        else
            tex:SetSize(dotBase, dotBase)
        end
    end,
    applyColor = defaultApplyColor,
})

--------------------------------------------------------------------------------
-- 9. Rotating Cross / Asterisk
-- Two perpendicular bars forming a + shape, rotating smoothly as a unit.
--------------------------------------------------------------------------------

AE.RegisterAnim({
    id = "rotating_cross",
    label = "Rotating Cross",
    numTextures = 2,
    period = 2.0,
    setup = function(ctrl, size)
        local barW = max(2, size * 0.12)
        local barH = max(4, size * 0.5)
        for i = 1, 2 do
            local tex = ctrl.textures[i]
            tex:SetSize(barW, barH)
            tex:ClearAllPoints()
            tex:SetPoint("CENTER", ctrl.frame, "CENTER", 0, 0)
        end
        -- Bar 2 starts perpendicular
        ctrl.textures[2]:SetRotation(pi / 2)
    end,
    update = function(ctrl, progress)
        local angle = progress * 2 * pi
        ctrl.textures[1]:SetRotation(angle)
        ctrl.textures[2]:SetRotation(angle + pi / 2)
    end,
    applyColor = defaultApplyColor,
})

--------------------------------------------------------------------------------
-- 10. Flip Square (3D Coin)
-- A square whose width oscillates to simulate a coin flip.
--------------------------------------------------------------------------------

AE.RegisterAnim({
    id = "flip_square",
    label = "Flip Square",
    numTextures = 1,
    period = 1.0,
    setup = function(ctrl, size)
        local tex = ctrl.textures[1]
        local maxW = max(4, size * 0.4)
        tex:SetSize(maxW, maxW)
        tex:ClearAllPoints()
        tex:SetPoint("CENTER", ctrl.frame, "CENTER", 0, 0)
    end,
    update = function(ctrl, progress)
        local size = ctrl.size
        local maxW = max(4, size * 0.4)
        local cosVal = cos(progress * 2 * pi)
        local w = max(1, maxW * abs(cosVal))
        local tex = ctrl.textures[1]
        tex:SetSize(w, maxW)

        -- Color swap at flip point to suggest two faces
        local cr, cg, cb = ctrl.colorR or 1, ctrl.colorG or 1, ctrl.colorB or 1
        if cosVal >= 0 then
            tex:SetVertexColor(cr, cg, cb, 1)
        else
            tex:SetVertexColor(cr * 0.5, cg * 0.5, cb * 0.5, 1)
        end
    end,
    applyColor = function(ctrl, r, g, b, a)
        ctrl.colorR, ctrl.colorG, ctrl.colorB = r, g, b
        -- Color is applied per-frame in update (two-face swap)
    end,
})

--------------------------------------------------------------------------------
-- 11. Helix / DNA
-- Two dots counter-orbiting with faked depth (size + alpha).
--------------------------------------------------------------------------------

AE.RegisterAnim({
    id = "helix_dna",
    label = "Helix / DNA",
    numTextures = 2,
    period = 1.5,
    setup = function(ctrl, size)
        local dotBase = max(3, size * 0.16)
        for i = 1, 2 do
            local tex = ctrl.textures[i]
            tex:SetSize(dotBase, dotBase)
            tex:ClearAllPoints()
            tex:SetPoint("CENTER", ctrl.frame, "CENTER", 0, 0)
        end
    end,
    update = function(ctrl, progress)
        local size = ctrl.size
        local dotBase = max(3, size * 0.16)
        local r = size * 0.3
        local cr, cg, cb = ctrl.colorR or 1, ctrl.colorG or 1, ctrl.colorB or 1

        local theta = progress * 2 * pi

        -- Dot A
        local xA = r * cos(theta)
        local yA = r * sin(theta)
        local depthA = sin(theta)
        local sizeA = dotBase + dotBase * 0.4 * depthA
        local alphaA = 0.4 + 0.6 * (depthA * 0.5 + 0.5)
        local texA = ctrl.textures[1]
        texA:ClearAllPoints()
        texA:SetPoint("CENTER", ctrl.frame, "CENTER", xA, yA)
        texA:SetSize(max(2, sizeA), max(2, sizeA))
        texA:SetVertexColor(cr, cg, cb, alphaA)

        -- Dot B (opposite)
        local xB = r * cos(theta + pi)
        local yB = r * sin(theta + pi)
        local depthB = -depthA
        local sizeB = dotBase + dotBase * 0.4 * depthB
        local alphaB = 0.4 + 0.6 * (depthB * 0.5 + 0.5)
        local texB = ctrl.textures[2]
        texB:ClearAllPoints()
        texB:SetPoint("CENTER", ctrl.frame, "CENTER", xB, yB)
        texB:SetSize(max(2, sizeB), max(2, sizeB))
        texB:SetVertexColor(cr, cg, cb, alphaB)

        -- Draw order: front dot renders on top
        if depthA >= 0 then
            texA:SetDrawLayer("OVERLAY", 2)
            texB:SetDrawLayer("OVERLAY", 1)
        else
            texA:SetDrawLayer("OVERLAY", 1)
            texB:SetDrawLayer("OVERLAY", 2)
        end
    end,
    applyColor = function(ctrl, r, g, b, a)
        ctrl.colorR, ctrl.colorG, ctrl.colorB = r, g, b
        -- Per-dot alpha managed by update
    end,
})

--------------------------------------------------------------------------------
-- 12. Starburst
-- 6 lines radiating outward from center, expanding and fading.
-- Two staggered groups (even/odd) for continuous activity.
--------------------------------------------------------------------------------

AE.RegisterAnim({
    id = "starburst",
    label = "Starburst",
    numTextures = 6,
    period = 1.2,
    setup = function(ctrl, size)
        local N = 6
        local barW = max(1, size * 0.06)
        local barH = max(2, size * 0.18)
        for i = 1, N do
            local tex = ctrl.textures[i]
            tex:SetSize(barW, barH)
            -- Pre-rotate each line to its fixed radial angle
            local angle = (i - 1) / N * 2 * pi
            tex:SetRotation(angle)
            tex:ClearAllPoints()
            tex:SetPoint("CENTER", ctrl.frame, "CENTER", 0, 0)
        end
    end,
    update = function(ctrl, progress)
        local size = ctrl.size
        local maxRadius = size * 0.38
        local N = 6
        local cr, cg, cb = ctrl.colorR or 1, ctrl.colorG or 1, ctrl.colorB or 1

        for i = 1, N do
            -- Stagger: even lines at progress, odd lines at progress + 0.5
            local p
            if i % 2 == 0 then
                p = progress
            else
                p = (progress + 0.5) % 1
            end

            local offset = p * maxRadius
            local alpha = max(0, 1.0 - p)
            local angle = (i - 1) / N * 2 * pi
            local x = offset * cos(angle)
            local y = offset * sin(angle)

            local tex = ctrl.textures[i]
            tex:ClearAllPoints()
            tex:SetPoint("CENTER", ctrl.frame, "CENTER", x, y)
            tex:SetVertexColor(cr, cg, cb, alpha)
        end
    end,
    applyColor = function(ctrl, r, g, b, a)
        ctrl.colorR, ctrl.colorG, ctrl.colorB = r, g, b
        -- Per-line alpha managed by update
    end,
})
