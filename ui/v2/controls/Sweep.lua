-- Sweep.lua - the redraw a pane shows while its rows are on their way and
-- when they land: a veil of the pane's own fill dims what is there, and a
-- line in the accent with a short trail runs down the pane. Scan loops the
-- line over the whole veil while the pane waits; Reveal runs it once from
-- the top with the veil cut away above it, so the new rows come up line by
-- line, and clears. A search that answers in a tenth of a second still
-- shows the one reveal pass.
--
-- opts:
--   parent        required; the caller anchors the frame over the pane
--   scanPeriod    seconds per scan pass; default 0.6
--   revealPeriod  seconds for the reveal pass; default 0.3
--   veilAlpha     the fill's alpha over the rows; default 0.6
--   lineHeight    default 2
--   trailHeight   default 28
--
-- Returns a frame carrying Scan(), Reveal(), Stop() and IsPlaying(). The
-- frame clips to its rect, so the trail never leaves the pane. It is hidden
-- while idle and runs its update only while shown.
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.Controls = addon.UI.Controls or {}
local Controls = addon.UI.Controls

function Controls.CreateSweep(opts)
    if not opts or not opts.parent then return nil end
    local Theme = addon.UI.Theme
    local scanPeriod = opts.scanPeriod or 0.6
    local revealPeriod = opts.revealPeriod or 0.3
    local veilAlpha = opts.veilAlpha or 0.6
    local lineHeight = opts.lineHeight or 2
    local trailHeight = opts.trailHeight or 28

    local frame = CreateFrame("Frame", opts.name, opts.parent)
    frame:SetClipsChildren(true)
    frame:Hide()

    local veil = frame:CreateTexture(nil, "ARTWORK", nil, 1)
    local trail = frame:CreateTexture(nil, "ARTWORK", nil, 2)
    local line = frame:CreateTexture(nil, "ARTWORK", nil, 3)
    line:SetHeight(lineHeight)
    trail:SetHeight(trailHeight)
    trail:SetPoint("BOTTOMLEFT", line, "TOPLEFT", 0, 0)
    trail:SetPoint("BOTTOMRIGHT", line, "TOPRIGHT", 0, 0)
    trail:SetColorTexture(1, 1, 1, 1)

    frame._mode = nil
    frame._t = 0

    local function Paint()
        local r, g, b = Theme:GetAccentColor()
        local vr, vg, vb = Theme:GetCollapsibleBgColor()
        veil:SetColorTexture(vr, vg, vb, veilAlpha)
        line:SetColorTexture(r, g, b, frame._mode == "reveal" and 0.95 or 0.6)
        -- The glow behind the line, strongest at the line and gone at the
        -- trail's top
        trail:SetGradient("VERTICAL", CreateColor(r, g, b, frame._mode == "reveal" and 0.22 or 0.12),
            CreateColor(r, g, b, 0))
    end

    -- The veil covers the pane while scanning and only what lies under the
    -- line while revealing
    local function AnchorVeil()
        veil:ClearAllPoints()
        if frame._mode == "reveal" then
            veil:SetPoint("TOPLEFT", line, "BOTTOMLEFT", 0, 0)
            veil:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
        else
            veil:SetAllPoints(frame)
        end
    end

    local function PlaceLine(progress)
        local y = progress * (frame:GetHeight() or 0)
        line:ClearAllPoints()
        line:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -y)
        line:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -y)
    end

    function frame:Stop()
        self._mode = nil
        self._t = 0
        self:Hide()
    end

    function frame:IsPlaying()
        return self._mode ~= nil and self:IsShown()
    end

    local function Start(mode)
        frame._mode = mode
        frame._t = 0
        Paint()
        AnchorVeil()
        PlaceLine(0)
        frame:Show()
    end

    -- Loops until Reveal or Stop; a second call while scanning is a no-op
    function frame:Scan()
        if self._mode == "scan" and self:IsShown() then return end
        Start("scan")
    end

    -- One pass from the top, then clear; restarts a reveal already running
    function frame:Reveal()
        Start("reveal")
    end

    frame:SetScript("OnUpdate", function(self, elapsed)
        local mode = self._mode
        if not mode then
            self:Hide()
            return
        end
        local period = mode == "reveal" and revealPeriod or scanPeriod
        self._t = self._t + elapsed
        if self._t >= period then
            if mode == "reveal" then
                self:Stop()
                return
            end
            self._t = self._t - period
        end
        PlaceLine(self._t / period)
    end)

    -- A pane hidden mid-pass comes back idle
    frame:HookScript("OnHide", function(self)
        self._mode = nil
        self._t = 0
    end)

    return frame
end
