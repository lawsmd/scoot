-- ScrollBar.lua - the vertical scrollbar beside a ScrollFrame, drawn the
-- way the active skin's scrollBar role says.
--
-- Controls.CreateScrollBar({ parent, scrollFrame, name }) returns a frame the
-- caller anchors. Flat is the framework's own track and thumb: wheel, thumb
-- drag and track click, hidden when the content fits. Template builds
-- Blizzard's scrollbar (MinimalScrollBar) and wires it with ScrollUtil.
--
-- The factory owns the scroll frame's OnScrollRangeChanged in both kinds;
-- callers keep their OnMouseWheel and call bar:Update() after a wheel step.
--
-- Contract: Update(), Cleanup(), and the widget's own GetWidth().
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.Controls = addon.UI.Controls or {}
local Controls = addon.UI.Controls
local Theme -- Will be set after Theme.lua loads

local function GetTheme()
    if not Theme then
        Theme = addon.UI.Theme
    end
    return Theme
end

local function M()
    return Controls.Metrics().scrollBar
end

local function ContentAndVisible(scrollFrame)
    local contentHeight = 0
    local scrollChild = scrollFrame:GetScrollChild()
    if scrollChild then
        contentHeight = scrollChild:GetHeight() or 0
    end
    return contentHeight, scrollFrame:GetHeight() or 1
end

--------------------------------------------------------------------------------
-- Flat
--------------------------------------------------------------------------------

local function BuildFlat(bar, scrollFrame)
    local theme = GetTheme()
    local m = M()
    local ar, ag, ab = theme:GetAccentColor()

    local track = bar:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints()
    track:SetColorTexture(ar, ag, ab, m.trackAlpha)
    bar._track = track

    local thumb = CreateFrame("Button", nil, bar)
    thumb:SetWidth(m.width)
    thumb:SetHeight(m.thumbMin)
    thumb:SetPoint("TOP", bar, "TOP", 0, 0)
    thumb:EnableMouse(true)
    thumb:RegisterForDrag("LeftButton")

    local thumbTex = thumb:CreateTexture(nil, "ARTWORK")
    thumbTex:SetAllPoints()
    thumbTex:SetColorTexture(ar, ag, ab, m.thumbAlpha)
    thumb._tex = thumbTex
    bar._thumb = thumb

    local function paintThumb(alpha)
        local r, g, b = theme:GetAccentColor()
        thumbTex:SetColorTexture(r, g, b, alpha)
    end

    thumb:SetScript("OnEnter", function(self)
        paintThumb(M().thumbHoverAlpha)
    end)
    thumb:SetScript("OnLeave", function(self)
        if not self._isDragging then paintThumb(M().thumbAlpha) end
    end)

    local function Update()
        local contentHeight, visibleHeight = ContentAndVisible(scrollFrame)
        local trackHeight = bar:GetHeight() or 1

        if contentHeight <= visibleHeight then
            bar:Hide()
            return
        end
        bar:Show()

        local thumbHeight = math.max(M().thumbMin, (visibleHeight / contentHeight) * trackHeight)
        thumb:SetHeight(thumbHeight)

        local maxScroll = contentHeight - visibleHeight
        local currentScroll = scrollFrame:GetVerticalScroll() or 0
        local scrollPercent = maxScroll > 0 and (currentScroll / maxScroll) or 0
        local maxThumbOffset = trackHeight - thumbHeight

        thumb:ClearAllPoints()
        thumb:SetPoint("TOP", bar, "TOP", 0, -(scrollPercent * maxThumbOffset))
    end
    bar.Update = Update

    local dragStartY, dragStartScroll

    thumb:SetScript("OnDragStart", function(self)
        self._isDragging = true
        paintThumb(M().thumbDragAlpha)
        local _, cursorY = GetCursorPosition()
        dragStartY = cursorY / self:GetEffectiveScale()
        dragStartScroll = scrollFrame:GetVerticalScroll() or 0
    end)

    thumb:SetScript("OnDragStop", function(self)
        self._isDragging = false
        paintThumb(self:IsMouseOver() and M().thumbHoverAlpha or M().thumbAlpha)
    end)

    thumb:SetScript("OnUpdate", function(self)
        if not self._isDragging then return end
        local _, cursorY = GetCursorPosition()
        cursorY = cursorY / self:GetEffectiveScale()
        local deltaY = dragStartY - cursorY

        local contentHeight, visibleHeight = ContentAndVisible(scrollFrame)
        local trackHeight = bar:GetHeight() or 1
        local maxScroll = contentHeight - visibleHeight
        local maxThumbOffset = trackHeight - thumb:GetHeight()

        if maxThumbOffset > 0 and maxScroll > 0 then
            local scrollDelta = (deltaY / maxThumbOffset) * maxScroll
            scrollFrame:SetVerticalScroll(math.max(0, math.min(maxScroll, dragStartScroll + scrollDelta)))
            Update()
        end
    end)

    bar:EnableMouse(true)
    bar:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" then return end
        local _, cursorY = GetCursorPosition()
        cursorY = cursorY / self:GetEffectiveScale()
        local clickY = cursorY - (self:GetBottom() or 0)
        local clickPercent = 1 - (clickY / (self:GetHeight() or 1))

        local contentHeight, visibleHeight = ContentAndVisible(scrollFrame)
        local maxScroll = contentHeight - visibleHeight
        if maxScroll > 0 then
            scrollFrame:SetVerticalScroll(math.max(0, math.min(maxScroll, clickPercent * maxScroll)))
            Update()
        end
    end)

    bar._subscribeKey = "ScrollBar_" .. tostring(bar)
    theme:Subscribe(bar._subscribeKey, function(r, g, b)
        track:SetColorTexture(r, g, b, M().trackAlpha)
        if not thumb._isDragging then
            thumbTex:SetColorTexture(r, g, b, M().thumbAlpha)
        end
    end)

    function bar:Cleanup()
        if self._subscribeKey then
            theme:Unsubscribe(self._subscribeKey)
            self._subscribeKey = nil
        end
    end
end

--------------------------------------------------------------------------------
-- Template
--------------------------------------------------------------------------------

-- ScrollUtil owns the scroll frame's OnVerticalScroll and
-- OnScrollRangeChanged from here on, and the bar hides itself when the
-- content fits. Update re-fires the range handler for a caller that moved
-- the scroll itself.
local function BuildTemplate(bar, scrollFrame)
    ScrollUtil.InitScrollFrameWithScrollBar(scrollFrame, bar)
    if bar.SetHideIfUnscrollable then
        bar:SetHideIfUnscrollable(true)
    end

    function bar:Update()
        local fn = scrollFrame:GetScript("OnScrollRangeChanged")
        if fn then
            fn(scrollFrame, 0, scrollFrame:GetVerticalScrollRange() or 0)
        end
    end

    function bar:Cleanup() end
end

--------------------------------------------------------------------------------
-- Factory
--------------------------------------------------------------------------------

function Controls.CreateScrollBar(opts)
    if not opts or not opts.parent or not opts.scrollFrame then return nil end
    local scrollFrame = opts.scrollFrame
    local Chrome = addon.UI.Chrome
    local spec = Chrome.Spec("scrollBar")

    local bar
    if spec.kind == "template" then
        bar = Chrome.CreateFrame("scrollBar", spec.frameType or "EventFrame", opts.name, opts.parent)
        bar:SetWidth(M().width)
        BuildTemplate(bar, scrollFrame)
    else
        bar = CreateFrame("Frame", opts.name, opts.parent)
        bar:SetWidth(M().width)
        BuildFlat(bar, scrollFrame)
        scrollFrame:SetScript("OnScrollRangeChanged", function()
            bar:Update()
        end)
    end
    bar._scrollFrame = scrollFrame
    return bar
end
