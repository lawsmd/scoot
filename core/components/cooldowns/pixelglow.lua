-- pixelglow.lua — Code-generated pixel glow replacement for Blizzard's ProcLoopFlipbook.
-- Perimeter-walking dot/dash animation around CDM icons (Essential & Utility only).
local addonName, addon = ...

addon.PixelGlow = {}
local PG = addon.PixelGlow

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

local WHITE8X8 = "Interface\\BUTTONS\\WHITE8X8"
local DOT_SEGMENTS = 16
local DASH_SEGMENTS = 8
local DOT_SIZE = 3
local DASH_WIDTH = 2
local DASH_LENGTH_RATIO = 0.06  -- fraction of perimeter per dash

--------------------------------------------------------------------------------
-- State (weak-keyed)
--------------------------------------------------------------------------------

local glowPool = {}
local activeGlows = setmetatable({}, { __mode = "k" })
local pendingGlows = setmetatable({}, { __mode = "k" })

--------------------------------------------------------------------------------
-- HSV → RGB (pure Lua, no C_ColorUtil)
--------------------------------------------------------------------------------

local function hsvToRGB(h, s, v)
    if s == 0 then return v, v, v end
    h = (h % 1) * 6
    local i = math.floor(h)
    local f = h - i
    local p = v * (1 - s)
    local q = v * (1 - s * f)
    local t = v * (1 - s * (1 - f))
    if i == 0 then     return v, t, p
    elseif i == 1 then return q, v, p
    elseif i == 2 then return p, v, t
    elseif i == 3 then return p, q, v
    elseif i == 4 then return t, p, v
    else               return v, p, q
    end
end

--------------------------------------------------------------------------------
-- Class color helper
--------------------------------------------------------------------------------

local function getClassColor()
    local r, g, b = addon.GetClassColorRGB("player")
    return r or 1, g or 1, b or 1
end

--------------------------------------------------------------------------------
-- Perimeter position: maps t (0→1) to x,y on rectangle border
-- Origin = BOTTOMLEFT of frame
--------------------------------------------------------------------------------

local function perimeterPosition(t, w, h)
    local perimeter = 2 * (w + h)
    local d = (t % 1) * perimeter

    if d < w then
        -- Top edge: left → right
        return d, h, "top"
    end
    d = d - w
    if d < h then
        -- Right edge: top → bottom
        return w, h - d, "right"
    end
    d = d - h
    if d < w then
        -- Bottom edge: right → left
        return w - d, 0, "bottom"
    end
    d = d - w
    -- Left edge: bottom → top
    return 0, d, "left"
end

--------------------------------------------------------------------------------
-- Speed → period mapping
--------------------------------------------------------------------------------

local function speedToPeriod(speed)
    speed = math.max(-20, math.min(70, speed or 25))
    return 4.0 - (speed - 10) * (3.5 / 90)
end

--------------------------------------------------------------------------------
-- Segment management
--------------------------------------------------------------------------------

local function ensureSegments(ctrl, count, segW, segH)
    ctrl.segments = ctrl.segments or {}
    -- Create missing segments
    for i = #ctrl.segments + 1, count do
        local tex = ctrl.frame:CreateTexture(nil, "OVERLAY")
        tex:SetTexture(WHITE8X8)
        tex:SetSize(segW, segH)
        ctrl.segments[i] = tex
    end
    -- Show needed, hide excess
    for i = 1, #ctrl.segments do
        if i <= count then
            ctrl.segments[i]:SetSize(segW, segH)
            ctrl.segments[i]:Show()
        else
            ctrl.segments[i]:Hide()
        end
    end
    ctrl.segmentCount = count
end

--------------------------------------------------------------------------------
-- Glow controller
--------------------------------------------------------------------------------

local controllerMT = {}
controllerMT.__index = controllerMT

function controllerMT:Play()
    self.playing = true
    self.frame:Show()
    activeGlows[self.targetIcon] = self
end

function controllerMT:Stop()
    self.playing = false
    self.frame:Hide()
    if self.targetIcon then
        activeGlows[self.targetIcon] = nil
    end
end

function controllerMT:IsPlaying()
    return self.playing == true
end

function controllerMT:Configure(style, colorMode, customColor, speed)
    self.style = style
    self.colorMode = colorMode or "custom"
    self.customColor = customColor or {1, 0.84, 0, 1}
    self.period = speedToPeriod(speed)

    local count, segW, segH
    if style == "dashes" then
        count = DASH_SEGMENTS
        segW = DASH_WIDTH
        segH = DASH_WIDTH  -- will be dynamically adjusted per edge in OnUpdate
    else
        count = DOT_SEGMENTS
        segW = DOT_SIZE
        segH = DOT_SIZE
    end
    ensureSegments(self, count, segW, segH)

    -- Pre-resolve static color. Branch on the defaulted mode and always write
    -- all three channels, so a nil or unrecognized mode cannot leave a stale
    -- color from an earlier Configure. Rainbow overwrites per frame in OnUpdate.
    if self.colorMode == "class" then
        self.resolvedR, self.resolvedG, self.resolvedB = getClassColor()
    else
        self.resolvedR = self.customColor[1] or 1
        self.resolvedG = self.customColor[2] or 0.84
        self.resolvedB = self.customColor[3] or 0
    end
end

function controllerMT:SetTargetSize(w, h)
    if not w or not h then return end
    self.cachedW = w
    self.cachedH = h
end

function controllerMT:AnchorTo(target, insetH, insetV)
    self.targetIcon = target
    self.frame:ClearAllPoints()
    insetH = insetH or 0
    insetV = insetV or 0
    self.frame:SetPoint("TOPLEFT", target, "TOPLEFT", insetH, -insetV)
    self.frame:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", -insetH, insetV)

    -- Match target's strata so frame levels are comparable
    local okS, strata = pcall(function() return target:GetFrameStrata() end)
    if okS and strata then
        self.frame:SetFrameStrata(strata)
    end

    -- Frame level above SpellActivationAlert
    local ok, level = pcall(function() return target:GetFrameLevel() end)
    if ok and type(level) == "number" then
        self.frame:SetFrameLevel(level + 10)
    else
        self.frame:SetFrameLevel(20)
    end
end

function controllerMT:Destroy()
    self:Stop()
    if self.segments then
        for i = 1, #self.segments do
            self.segments[i]:Hide()
            self.segments[i]:SetTexture(nil)
        end
    end
    self.segments = nil
    self.frame:Hide()
    self.frame:SetParent(nil)
    self.targetIcon = nil
end

local function createController()
    local ctrl = setmetatable({}, controllerMT)
    ctrl.frame = CreateFrame("Frame", nil, UIParent)
    ctrl.frame:Hide()
    ctrl.segments = {}
    ctrl.segmentCount = 0
    ctrl.progress = 0
    ctrl.playing = false
    ctrl.cachedW = nil
    ctrl.cachedH = nil
    ctrl.style = "dots"
    ctrl.colorMode = "custom"
    ctrl.customColor = {1, 0.84, 0, 1}
    ctrl.period = 2.0
    ctrl.hueOffset = 0
    ctrl.resolvedR = 1
    ctrl.resolvedG = 0.84
    ctrl.resolvedB = 0
    return ctrl
end

local function acquireController()
    local ctrl = table.remove(glowPool)
    if ctrl then
        ctrl.progress = 0
        ctrl.hueOffset = 0
        ctrl.playing = false
        return ctrl
    end
    return createController()
end

local function releaseController(ctrl)
    ctrl:Stop()
    ctrl.frame:ClearAllPoints()
    ctrl.frame:Hide()
    ctrl.targetIcon = nil
    table.insert(glowPool, ctrl)
end

--------------------------------------------------------------------------------
-- OnUpdate engine (single shared frame)
--------------------------------------------------------------------------------

local engineFrame = CreateFrame("Frame", nil, UIParent)
engineFrame:Hide()

local function engineHasWork()
    if next(pendingGlows) then return true end
    if next(activeGlows) then return true end
    return false
end

local function updateEngine()
    if engineHasWork() then
        engineFrame:Show()
    else
        engineFrame:Hide()
    end
end

engineFrame:SetScript("OnUpdate", function(_, elapsed)
    -- Process pending glows: detect ProcLoop start
    for cdmIcon, config in pairs(pendingGlows) do
        local ok, playing = pcall(function()
            local alert = cdmIcon.SpellActivationAlert
            return alert and alert.ProcLoop and alert.ProcLoop:IsPlaying()
        end)
        if ok and playing then
            -- ProcLoop just started — suppress it
            pcall(function()
                local alert = cdmIcon.SpellActivationAlert
                alert.ProcLoop:Stop()
                alert.ProcLoopFlipbook:Hide()
            end)
            -- Start pixel glow
            local glow = acquireController()
            glow:Configure(config.style, config.colorMode, config.customColor, config.speed)
            if config.iconW then glow:SetTargetSize(config.iconW, config.iconH) end
            glow:AnchorTo(cdmIcon, config.insetH, config.insetV)
            glow:Play()
            pendingGlows[cdmIcon] = nil
        end
    end

    -- Animate active glows
    for cdmIcon, ctrl in pairs(activeGlows) do
        if not ctrl.playing then
            activeGlows[cdmIcon] = nil
        else
            -- Advance progress and rainbow hue accumulator
            ctrl.progress = (ctrl.progress + elapsed / ctrl.period) % 1
            ctrl.hueOffset = (ctrl.hueOffset + elapsed / ctrl.period * 0.5) % 1

            local w = ctrl.frame:GetWidth()
            local h = ctrl.frame:GetHeight()
            if w == 0 or h == 0 then w, h = 42, 42 end
            local count = ctrl.segmentCount or 0
            local isDashes = (ctrl.style == "dashes")

            -- Perimeter length for dash sizing
            local perimeter = 2 * (w + h)
            local dashLen = isDashes and (perimeter * DASH_LENGTH_RATIO) or 0

            for i = 1, count do
                local seg = ctrl.segments[i]
                if seg then
                    local segT = (ctrl.progress + (i - 1) / count) % 1
                    local x, y, edge = perimeterPosition(segT, w, h)

                    -- Dash sizing with corner clamping (must precede SetPoint)
                    if isDashes then
                        local halfDash = dashLen / 2
                        if edge == "top" or edge == "bottom" then
                            local minX = math.max(0, x - halfDash)
                            local maxX = math.min(w, x + halfDash)
                            local visLen = maxX - minX
                            if visLen > 0 then
                                seg:SetSize(visLen, DASH_WIDTH)
                                x = (minX + maxX) / 2
                            else
                                seg:SetSize(0.001, 0.001)
                            end
                        else
                            local minY = math.max(0, y - halfDash)
                            local maxY = math.min(h, y + halfDash)
                            local visLen = maxY - minY
                            if visLen > 0 then
                                seg:SetSize(DASH_WIDTH, visLen)
                                y = (minY + maxY) / 2
                            else
                                seg:SetSize(0.001, 0.001)
                            end
                        end
                    end

                    seg:ClearAllPoints()
                    seg:SetPoint("CENTER", ctrl.frame, "BOTTOMLEFT", x, y)

                    -- Color
                    if ctrl.colorMode == "rainbow" then
                        local hue = (segT + ctrl.hueOffset) % 1
                        local r, g, b = hsvToRGB(hue, 1, 1)
                        seg:SetVertexColor(r, g, b, 1)
                    else
                        seg:SetVertexColor(
                            ctrl.resolvedR or 1,
                            ctrl.resolvedG or 0.84,
                            ctrl.resolvedB or 0,
                            1
                        )
                    end
                end
            end
        end
    end

    -- Self-disable when idle
    if not engineHasWork() then
        engineFrame:Hide()
    end
end)

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

function PG.AcquireForIcon(cdmIcon, style, colorMode, customColor, speed)
    if not cdmIcon then return nil end
    -- Release existing glow for this icon
    local existing = activeGlows[cdmIcon]
    if existing then
        releaseController(existing)
    end

    local ctrl = acquireController()
    ctrl:Configure(style, colorMode, customColor, speed)
    return ctrl
end

function PG.ReleaseForIcon(cdmIcon)
    if not cdmIcon then return end
    local ctrl = activeGlows[cdmIcon]
    if ctrl then
        releaseController(ctrl)
        activeGlows[cdmIcon] = nil
    end
end

function PG.ReleaseAll()
    for cdmIcon, ctrl in pairs(activeGlows) do
        releaseController(ctrl)
    end
    wipe(activeGlows)
    wipe(pendingGlows)
    updateEngine()
end

function PG.GetForIcon(cdmIcon)
    if not cdmIcon then return nil end
    return activeGlows[cdmIcon]
end

function PG.StartForIcon(cdmIcon, config)
    if not cdmIcon or not config then return end
    local existing = activeGlows[cdmIcon]
    if existing and existing:IsPlaying() then
        -- Already running — reconfigure without resetting animation progress
        existing:Configure(config.style, config.colorMode, config.customColor, config.speed)
        if config.iconW then existing:SetTargetSize(config.iconW, config.iconH) end
        return
    end
    if existing then
        releaseController(existing)
    end
    pendingGlows[cdmIcon] = nil

    local glow = acquireController()
    glow:Configure(config.style, config.colorMode, config.customColor, config.speed)
    if config.iconW then glow:SetTargetSize(config.iconW, config.iconH) end
    glow:AnchorTo(cdmIcon, config.insetH, config.insetV)
    glow:Play()
    updateEngine()
end

function PG.AddPending(cdmIcon, config)
    if not cdmIcon or not config then return end
    pendingGlows[cdmIcon] = config
    updateEngine()
end

function PG.RemovePending(cdmIcon)
    if not cdmIcon then return end
    pendingGlows[cdmIcon] = nil
    if not engineHasWork() then
        engineFrame:Hide()
    end
end
