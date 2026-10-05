-- Drawer.lua - a panel that slides out of a window's side: the window's
-- own surface (the window role), as tall as the window, out of its right
-- edge and back in the same way. A list that floated in front of the
-- window hid the rows it filtered; a drawer stands beside them.
--
-- The drawer slides inside a clipping band anchored to the window's edge,
-- so it comes out of the edge rather than appearing whole. Its own border
-- is drawn outset like the window's, and the band is placed so the two
-- borders meet on the same line. The window going away closes the drawer
-- at once; Escape closes it and stops there, so the window stays.
--
-- opts:
--   parent     the window frame the drawer extends; required
--   width      default 460
--   side       "right" (default) or "left"
--   role       the chrome role the surface takes; default "window"
--   duration   the slide's seconds; default 0.18
--   pad        the content's inset from the surface; default the
--              collapsible content padding
--   scroll     false leaves the scroll frame out; the default puts the
--              content in a ScrollFrame with the skin's bar beside it
--   onOpen(drawer), onClose(drawer)
--              onOpen runs as the slide out starts, the moment to fill the
--              content; onClose when the slide in ends
-- Returns the drawer frame: content (the frame a caller fills), contentWidth
-- (what the content is given across, the pad and the bar's column taken),
-- Open(), Close(instant), Toggle(), IsOpen(), SetContentHeight(h),
-- Resize(width), Cleanup(). Resize sets the drawer's width for the next
-- open, or at once while it is out, and sets the content's width with it,
-- so a list that measures its host at open reads the new width.
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.Controls = addon.UI.Controls or {}
local Controls = addon.UI.Controls

local DEFAULTS = { width = 460, duration = 0.18, wheelStep = 40 }

-- Fast out, settling in
local function Ease(t)
    local u = 1 - t
    return 1 - u * u * u
end

function Controls.CreateDrawer(opts)
    opts = opts or {}
    local parent = opts.parent
    if not parent then return nil end
    local Window = addon.UI.Window
    local m = Controls.Metrics()
    local border = (m and m.windowBorderWidth) or 3
    local width = opts.width or DEFAULTS.width
    local side = opts.side == "left" and "left" or "right"
    local duration = opts.duration or DEFAULTS.duration
    local pad = opts.pad or ((m and m.collapsible or {}).contentPadding) or 12

    -- The band the drawer slides through: beside the window, as tall as the
    -- window and its border, one border wider than the drawer
    local clip = CreateFrame("Frame", nil, parent)
    clip:SetClipsChildren(true)
    clip:SetWidth(width + border)
    if side == "right" then
        clip:SetPoint("TOPLEFT", parent, "TOPRIGHT", border, border)
        clip:SetPoint("BOTTOMLEFT", parent, "BOTTOMRIGHT", border, -border)
    else
        clip:SetPoint("TOPRIGHT", parent, "TOPLEFT", -border, border)
        clip:SetPoint("BOTTOMRIGHT", parent, "BOTTOMLEFT", -border, -border)
    end
    clip:SetFrameLevel(parent:GetFrameLevel() + 1)
    clip:Hide()

    local drawer = Window:Create(nil, clip, width, 1, { role = opts.role or "window" })
    drawer:SetFrameStrata(parent:GetFrameStrata())
    drawer:SetFrameLevel(parent:GetFrameLevel() + 2)
    drawer:SetMovable(false)
    drawer:SetClampedToScreen(false)
    drawer._clip = clip

    -- Where the drawer stands for a progress from 0, tucked in, to 1, out
    local function Place(progress)
        local shift = (1 - progress) * (width + border)
        drawer:ClearAllPoints()
        if side == "right" then
            drawer:SetPoint("TOPLEFT", clip, "TOPLEFT", -shift, -border)
            drawer:SetPoint("BOTTOMLEFT", clip, "BOTTOMLEFT", -shift, border)
        else
            drawer:SetPoint("TOPRIGHT", clip, "TOPRIGHT", shift, -border)
            drawer:SetPoint("BOTTOMRIGHT", clip, "BOTTOMRIGHT", shift, border)
        end
    end
    Place(0)

    -- The content, in a scroll frame with the skin's bar unless declined
    local content
    local gutter = 0
    if opts.scroll ~= false then
        local sb = m.scrollBar
        gutter = sb.width + sb.margin + sb.gap
        local scrollFrame = CreateFrame("ScrollFrame", nil, drawer)
        scrollFrame:SetPoint("TOPLEFT", drawer, "TOPLEFT", pad, -pad)
        scrollFrame:SetPoint("BOTTOMRIGHT", drawer, "BOTTOMRIGHT", -(pad + gutter), pad)
        content = CreateFrame("Frame", nil, scrollFrame)
        content:SetPoint("TOPLEFT")
        content:SetSize(1, 1)
        scrollFrame:SetScrollChild(content)
        scrollFrame:SetScript("OnSizeChanged", function(_, w)
            content:SetWidth(math.max(1, w or 1))
        end)
        local bar = Controls.CreateScrollBar({ parent = drawer, scrollFrame = scrollFrame })
        if bar then
            bar:SetPoint("TOPRIGHT", scrollFrame, "TOPRIGHT", sb.margin + sb.width, 0)
            bar:SetPoint("BOTTOMRIGHT", scrollFrame, "BOTTOMRIGHT", sb.margin + sb.width, 0)
        end
        local function Scroll(target)
            local maxScroll = math.max(0, (content:GetHeight() or 0) - (scrollFrame:GetHeight() or 1))
            scrollFrame:SetVerticalScroll(math.max(0, math.min(maxScroll, target)))
            if bar then bar:Sync() end
        end
        scrollFrame:EnableMouseWheel(true)
        scrollFrame:SetScript("OnMouseWheel", function(self, delta)
            Scroll((self:GetVerticalScroll() or 0) - delta * DEFAULTS.wheelStep)
        end)
        drawer._scrollFrame, drawer._bar = scrollFrame, bar
    else
        content = CreateFrame("Frame", nil, drawer)
        content:SetPoint("TOPLEFT", drawer, "TOPLEFT", pad, -pad)
        content:SetPoint("BOTTOMRIGHT", drawer, "BOTTOMRIGHT", -pad, pad)
    end
    drawer.content = content
    drawer.contentWidth = width - pad * 2 - gutter

    -- The slide: progress runs toward the target at the duration's pace
    local progress, target = 0, 0
    local function Step(_, elapsed)
        local dir = target > progress and 1 or -1
        progress = progress + dir * (elapsed / duration)
        local done = (dir > 0 and progress >= target) or (dir < 0 and progress <= target)
        if done then
            progress = target
            clip:SetScript("OnUpdate", nil)
        end
        Place(Ease(progress))
        if done and target == 0 then
            clip:Hide()
            if opts.onClose then opts.onClose(drawer) end
        end
    end

    function drawer:IsOpen()
        return target == 1
    end

    function drawer:Open()
        if target == 1 then return end
        target = 1
        clip:Show()
        if opts.onOpen then opts.onOpen(self) end
        Place(Ease(progress))
        clip:SetScript("OnUpdate", Step)
    end

    function drawer:Close(instant)
        if target == 0 and not clip:IsShown() then return end
        target = 0
        if instant then
            progress = 0
            clip:SetScript("OnUpdate", nil)
            Place(0)
            clip:Hide()
            if opts.onClose then opts.onClose(self) end
            return
        end
        clip:SetScript("OnUpdate", Step)
    end

    function drawer:Toggle()
        if self:IsOpen() then self:Close() else self:Open() end
    end

    function drawer:SetContentHeight(h)
        content:SetHeight(math.max(1, h or 1))
        if self._bar then self._bar:Sync() end
    end

    -- The band, the drawer's place and the content's width follow at once;
    -- the scroll frame's own size change writes the same content width
    -- again when the layout runs
    function drawer:Resize(w)
        width = math.max(1, w or width)
        clip:SetWidth(width + border)
        self.contentWidth = width - pad * 2 - gutter
        content:SetWidth(math.max(1, self.contentWidth))
        Place(Ease(progress))
        return self.contentWidth
    end

    function drawer:Cleanup()
        clip:SetScript("OnUpdate", nil)
        if self._bar and self._bar.Cleanup then self._bar:Cleanup() end
    end

    parent:HookScript("OnHide", function() drawer:Close(true) end)
    addon.EscapeKey.Attach(drawer, function() drawer:Close() end)

    return drawer
end
