-- procglow.lua - Blizzard's spell alert (the proc glow) on a frame the addon owns
--
-- The action button and the Cooldown Manager draw one alert,
-- ActionButtonSpellAlertTemplate: a burst that plays once, then a border
-- that loops. This file rebuilds it from the same two atlases, so a caller's
-- icon glows as a proc does on a Blizzard button, with nothing of Blizzard's
-- called or written. The numbers below are copied from
-- Blizzard_ActionBar/Shared/ActionButtonSpellAlerts.xml and .lua; a patch
-- that moves them there is mirrored here by hand.
--
--   glow (frame, 1.4 x the icon, centered on it)
--    +- loop texture   fills the frame
--    +- burst texture  centered, 150/45 x the icon
--
-- The frame takes the alpha its caller writes. Each group animates its own
-- texture, so the two never meet.
local _, addon = ...

addon.ProcGlow = addon.ProcGlow or {}
local ProcGlow = addon.ProcGlow

local BURST_ATLAS = "UI-HUD-ActionBar-Proc-Start-Flipbook"
local LOOP_ATLAS = "UI-HUD-ActionBar-Proc-Loop-Flipbook"
local ROWS, COLUMNS, FRAMES = 6, 5, 30
local BURST_SECONDS = 0.7
local LOOP_SECONDS = 1
-- The alert frame is 1.4 times its button, and the burst a fixed 150 on a
-- button of 45.
local LOOP_SCALE = 1.4
local BURST_SCALE = 150 / 45

--- How far the loop reaches past the icon on each side, as a share of the
-- icon's width or height. A caller that clips reads it to leave room.
ProcGlow.OVERHANG = (LOOP_SCALE - 1) / 2

--- Whether this client holds the loop's atlas. A client without it draws
-- nothing, and the caller's debug output can say why.
function ProcGlow.HasArt()
    local info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(LOOP_ATLAS)
    return info ~= nil
end

local function AddFlipBook(group, order, seconds)
    local flip = group:CreateAnimation("FlipBook")
    flip:SetOrder(order)
    flip:SetDuration(seconds)
    flip:SetFlipBookRows(ROWS)
    flip:SetFlipBookColumns(COLUMNS)
    flip:SetFlipBookFrames(FRAMES)
    flip:SetFlipBookFrameWidth(0)
    flip:SetFlipBookFrameHeight(0)
    return flip
end

local function AddAlpha(group, order, from, to)
    local alpha = group:CreateAnimation("Alpha")
    alpha:SetOrder(order)
    alpha:SetDuration(0.001)
    alpha:SetFromAlpha(from)
    alpha:SetToAlpha(to)
    return alpha
end

local GlowMethods = {}

--- Centers the glow on `target` and sizes it for an icon of w by h. The
-- sizes are written only when they change: a resize under a playing
-- flipbook hitches.
function GlowMethods:Fit(target, w, h)
    if self.fitTarget == target and self.fitW == w and self.fitH == h then return end
    self.fitTarget, self.fitW, self.fitH = target, w, h
    self:ClearAllPoints()
    self:SetPoint("CENTER", target, "CENTER")
    self:SetSize(w * LOOP_SCALE, h * LOOP_SCALE)
    self.burstTexture:SetSize(w * BURST_SCALE, h * BURST_SCALE)
end

--- Starts the glow: the burst and then the loop, or the loop at once. A
-- running glow is left alone, so a caller can ask on every event. The
-- groups play from OnShow, which also runs when a hidden ancestor comes
-- back.
function GlowMethods:Start(withBurst)
    if self.running then return end
    self.running = true
    self.burstPending = withBurst and true or false
    self:Show()
end

function GlowMethods:Stop()
    self.running = false
    self.burstPending = false
    self:Hide()
end

function GlowMethods:IsRunning()
    return self.running == true
end

local function OnShow(self)
    if not self.running then return end
    if self.burstPending then
        self.burstPending = false
        self.burst:Play()
    else
        self.loop:Play()
    end
end

-- Runs for Stop and for a hidden ancestor alike. A stopped group puts its
-- texture back at alpha 0, so nothing of either sheet is left drawn.
local function OnHide(self)
    self.burst:Stop()
    self.loop:Stop()
end

--- Builds a hidden glow under `parent`. The caller places it with Fit,
-- sets its frame level and alpha, and runs it with Start and Stop.
function ProcGlow.Create(parent)
    local glow = CreateFrame("Frame", nil, parent)
    glow:Hide()

    local loopTexture = glow:CreateTexture(nil, "ARTWORK")
    loopTexture:SetAtlas(LOOP_ATLAS)
    loopTexture:SetAllPoints(glow)
    loopTexture:SetAlpha(0)

    local burstTexture = glow:CreateTexture(nil, "ARTWORK")
    burstTexture:SetAtlas(BURST_ATLAS)
    burstTexture:SetPoint("CENTER", glow, "CENTER")
    burstTexture:SetSize(150, 150)
    burstTexture:SetAlpha(0)

    -- The loop holds its texture at alpha 1 for as long as the group plays.
    local loop = loopTexture:CreateAnimationGroup()
    loop:SetLooping("REPEAT")
    AddAlpha(loop, 1, 1, 1)
    AddFlipBook(loop, 2, LOOP_SECONDS)

    -- The burst shows its texture, runs the sheet once, hides it and hands
    -- over to the loop.
    local burst = burstTexture:CreateAnimationGroup()
    burst:SetToFinalAlpha(true)
    AddAlpha(burst, 1, 1, 1)
    AddFlipBook(burst, 2, BURST_SECONDS)
    AddAlpha(burst, 3, 1, 0)
    burst:SetScript("OnFinished", function()
        if glow.running then loop:Play() end
    end)

    glow.loopTexture = loopTexture
    glow.burstTexture = burstTexture
    glow.loop = loop
    glow.burst = burst
    glow.running = false
    glow.burstPending = false
    for name, method in pairs(GlowMethods) do
        glow[name] = method
    end
    glow:SetScript("OnShow", OnShow)
    glow:SetScript("OnHide", OnHide)
    return glow
end
