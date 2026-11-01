-- settingspanel/titleflight.lua - the home page's image lockup and its flight
-- back to the corner: the window's portrait mark and the title image drawn
-- large in the middle of the home page, and on leaving home the two shrink
-- and move back onto the pieces they copy. A product takes this with
-- HomeModel.title = "image" and a texture title (Camelot, forever/menu.lua).
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.SettingsPanel = addon.UI.SettingsPanel or {}
local UIPanel = addon.UI.SettingsPanel
local Controls = addon.UI.Controls

local function Home()
    return Controls.Metrics().home or {}
end

-- The corner pieces the lockup copies: the portrait texture the window
-- template draws and the title image's texture
local function CornerRegions(frame)
    local container = frame.PortraitContainer
    return container and container.portrait, frame._titleTexture
end

local function Lockup(frame)
    local pane = frame._contentPane
    local home = pane and pane._homeContent
    return home and home._lockup
end

-- left, bottom, width, height of a region relative to the window, or nil
-- before the region has a rect
local function RelRect(frame, region)
    local l, b, w, h = region:GetRect()
    local fl, fb = frame:GetRect()
    if not (l and w and fl) or w <= 0 then return nil end
    return l - fl, b - fb, w, h
end

-- Lays the lockup out as the corner pair scaled by home.lockupScale, from
-- the corner's own rects, so the gap and overlap between mark and image keep
-- the proportions the skin gave the corner. The corner sits at fixed
-- offsets from the window's top-left, so one good read holds for the
-- session. A read before the window has laid out retries a frame later
-- while the window shows; a closed window waits for the home page's OnShow.
function UIPanel:LayoutHomeLockup()
    local frame = self.frame
    local lockup = frame and Lockup(frame)
    if not lockup or lockup._laidOut then return end
    local emblem, banner = CornerRegions(frame)
    local el, eb, ew, eh
    if emblem then el, eb, ew, eh = RelRect(frame, emblem) end
    local bl, bb, bw, bh = RelRect(frame, banner)
    if not bl then
        if frame:IsShown() then
            C_Timer.After(0, function() self:LayoutHomeLockup() end)
        end
        return
    end
    local left, bottom = bl, bb
    local right, top = bl + bw, bb + bh
    if el then
        left, bottom = math.min(left, el), math.min(bottom, eb)
        right, top = math.max(right, el + ew), math.max(top, eb + eh)
    end
    local s = Home().lockupScale or 2
    lockup:SetSize((right - left) * s, (top - bottom) * s)
    lockup._banner:ClearAllPoints()
    lockup._banner:SetPoint("TOPLEFT", lockup, "TOPLEFT", (bl - left) * s, -(top - bb - bh) * s)
    lockup._banner:SetSize(bw * s, bh * s)
    if el then
        lockup._emblem:ClearAllPoints()
        lockup._emblem:SetPoint("TOPLEFT", lockup, "TOPLEFT", (el - left) * s, -(top - eb - eh) * s)
        lockup._emblem:SetSize(ew * s, eh * s)
        lockup._emblem:Show()
    else
        lockup._emblem:Hide()
    end
    lockup._laidOut = true
end

-- Shows or hides the corner pair by alpha, so the two keep the rects the
-- lockup and the flight read. The portrait texture takes it rather than its
-- container, whose alpha is the skin's portrait opacity piece; the button's
-- mouse is the title handle's.
function UIPanel:SetCornerShown(shown)
    local frame = self.frame
    if not frame or not Lockup(frame) then return end
    local alpha = shown and 1 or 0
    local emblem = CornerRegions(frame)
    if emblem then emblem:SetAlpha(alpha) end
    if frame._titleBtn then frame._titleBtn:SetAlpha(alpha) end
end

-- Cubic ease in and out: the piece starts slowly, glides, and slows onto its
-- corner without passing it
local function EaseInOutCubic(t)
    if t < 0.5 then return 4 * t * t * t end
    local u = -2 * t + 2
    return 1 - u * u * u / 2
end

-- One texture per piece, kept on the holder across flights
local function Flyer(holder, i, source)
    holder._flyers = holder._flyers or {}
    local tex = holder._flyers[i]
    if not tex then
        tex = holder:CreateTexture(nil, "OVERLAY")
        holder._flyers[i] = tex
    end
    tex:SetTexture(source:GetTexture())
    tex:SetTexCoord(source:GetTexCoord())
    tex:Show()
    return tex
end

-- Starts the flight from the lockup to the corner. Returns false when a
-- rect is not there to fly between, and the caller shows the corner at once.
function UIPanel:AnimateTitleFlight()
    local frame = self.frame
    local lockup = frame and Lockup(frame)
    if not lockup or not lockup._laidOut then return false end
    self:StopTitleFlight()

    local emblem, banner = CornerRegions(frame)
    local pairs_ = {
        { from = lockup._banner, to = banner, delay = Home().bannerDelay or 0 },
    }
    if emblem and lockup._emblem:IsShown() then
        table.insert(pairs_, 1, { from = lockup._emblem, to = emblem, delay = 0 })
    end

    -- The lockup is hidden with the home page by now; a hidden region keeps
    -- the rect its anchors give it
    for _, p in ipairs(pairs_) do
        p.fl, p.fb, p.fw, p.fh = RelRect(frame, p.from)
        p.tl, p.tb, p.tw, p.th = RelRect(frame, p.to)
        if not (p.fl and p.tl) then return false end
    end

    local holder = frame._titleFlight
    if not holder then
        holder = CreateFrame("Frame", nil, frame)
        holder:SetAllPoints(frame)
        frame._titleFlight = holder
    end
    holder:SetFrameLevel(frame:GetOverlayLevel() + 2)
    for i, p in ipairs(pairs_) do
        p.tex = Flyer(holder, i, p.from)
    end
    holder._pairs = pairs_
    holder:Show()

    local duration = Home().flightDuration or 0.35
    local elapsed = 0
    holder:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        local done = true
        for _, p in ipairs(pairs_) do
            local t = math.min(math.max((elapsed - p.delay) / duration, 0), 1)
            if t < 1 then done = false end
            local k = EaseInOutCubic(t)
            local w = p.fw + (p.tw - p.fw) * k
            local h = p.fh + (p.th - p.fh) * k
            local cx = (p.fl + p.fw / 2) + ((p.tl + p.tw / 2) - (p.fl + p.fw / 2)) * k
            local cy = (p.fb + p.fh / 2) + ((p.tb + p.th / 2) - (p.fb + p.fh / 2)) * k
            p.tex:ClearAllPoints()
            p.tex:SetPoint("CENTER", holder, "BOTTOMLEFT", cx, cy)
            p.tex:SetSize(math.max(w, 1), math.max(h, 1))
        end
        if done then self:StopTitleFlight() end
    end)
    return true
end

-- Ends a flight where it stands and puts the corner back. Safe with no
-- flight running.
function UIPanel:StopTitleFlight()
    local frame = self.frame
    local holder = frame and frame._titleFlight
    if not holder or not holder._pairs then return end
    holder:SetScript("OnUpdate", nil)
    for _, p in ipairs(holder._pairs) do
        p.tex:Hide()
        p.tex:ClearAllPoints()
    end
    holder._pairs = nil
    holder:Hide()
    self:SetCornerShown(true)
end
