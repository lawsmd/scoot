-- widget/core.lua - QoL Widget: floating green diamond launchpad for notifications and reports
local addonName, addon = ...

addon.Widget = addon.Widget or {}
local W = addon.Widget

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

local DEFAULT_SIZE = 20
local MIN_SIZE = 16
local MAX_SIZE = 40

local DIAMOND_GREEN = { 0.20, 0.90, 0.30, 1 }
local DIAMOND_BLACK = { 0, 0, 0, 1 }

local SQRT2_INV = 0.70710678  -- 1 / sqrt(2)
local OUTLINE_THICKNESS = 1.5  -- visible black ring in pixels (constant across sizes)

local DEFAULT_POINT = "TOPLEFT"
local DEFAULT_RELATIVE = "TOPLEFT"
local DEFAULT_X = 100
local DEFAULT_Y = -200

local FLY_DOWN, FLY_UP, FLY_LEFT, FLY_RIGHT = "down", "up", "left", "right"

--------------------------------------------------------------------------------
-- Module-Level State
--------------------------------------------------------------------------------

local widgetFrame      -- main container Frame
local diamondOutline   -- black rotated square (texture)
local diamondFill      -- green rotated square (texture)

local flyoutChain = {}  -- ordered list of registered child handles
local nextHandleId = 1

local hoverActive = false

--------------------------------------------------------------------------------
-- DB Helpers
--------------------------------------------------------------------------------

local function getComponent()
    return addon.Components and addon.Components["widget"]
end

local function isOnProxy(comp)
    return comp and comp._ScootDBProxy and comp.db == comp._ScootDBProxy
end

local function getSetting(key, fallback)
    local comp = getComponent()
    if not comp or not comp.db then return fallback end
    local v = comp.db[key]
    if v == nil then return fallback end
    return v
end

--------------------------------------------------------------------------------
-- Diamond Sizing
--------------------------------------------------------------------------------
-- A 45-degree-rotated solid-color square renders as a diamond inscribed in
-- its bounding box. For corners to just touch the container's edge midpoints,
-- the texture's logical edge length must be containerSize * (1 / sqrt(2)).

local function applyDiamondSize(size)
    if not widgetFrame then return end
    local outlineSize = size * SQRT2_INV
    local fillSize = math.max(2, outlineSize - 2 * OUTLINE_THICKNESS)
    widgetFrame:SetSize(size, size)
    diamondOutline:SetSize(outlineSize, outlineSize)
    diamondFill:SetSize(fillSize, fillSize)
end

--------------------------------------------------------------------------------
-- Frame Construction
--------------------------------------------------------------------------------

local function createWidgetFrame()
    if widgetFrame then return widgetFrame end

    local frame = CreateFrame("Frame", "ScootWidgetFrame", UIParent)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")

    -- Black outline diamond (rotated square below the fill)
    local outline = frame:CreateTexture(nil, "ARTWORK", nil, 0)
    outline:SetColorTexture(DIAMOND_BLACK[1], DIAMOND_BLACK[2], DIAMOND_BLACK[3], DIAMOND_BLACK[4])
    outline:SetRotation(math.rad(45))
    outline:SetPoint("CENTER")

    -- Green fill diamond (rotated square above the outline)
    local fill = frame:CreateTexture(nil, "ARTWORK", nil, 1)
    fill:SetColorTexture(DIAMOND_GREEN[1], DIAMOND_GREEN[2], DIAMOND_GREEN[3], DIAMOND_GREEN[4])
    fill:SetRotation(math.rad(45))
    fill:SetPoint("CENTER")

    widgetFrame = frame
    diamondOutline = outline
    diamondFill = fill

    applyDiamondSize(DEFAULT_SIZE)
    frame:SetPoint(DEFAULT_POINT, UIParent, DEFAULT_RELATIVE, DEFAULT_X, DEFAULT_Y)

    -- Drag handlers: click-drag always works. No modifier, no lock.
    frame:SetScript("OnDragStart", function(self)
        self._scootDragging = true
        self:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        W:_SavePosition()
        W:_ReflowFlyoutChildren()
        -- Cleared next frame: the engine's OnMouseUp/OnDragStop firing order
        -- on release is not guaranteed, and a drag must never read as a click.
        C_Timer.After(0, function()
            self._scootDragging = nil
        end)
    end)

    -- Plain left-click (not a drag) dispatches to the registered handler.
    frame:SetScript("OnMouseUp", function(self, button)
        if button ~= "LeftButton" then return end
        if self._scootDragging then return end
        if not self:IsMouseOver() then return end
        if W._clickHandler then
            pcall(W._clickHandler)
        end
    end)

    -- Hover reveal
    frame:SetScript("OnEnter", function()
        hoverActive = true
        W:_ApplyOpacity()
    end)
    frame:SetScript("OnLeave", function()
        hoverActive = false
        W:_ApplyOpacity()
    end)

    frame:Hide()  -- ApplyStyling decides whether to show
    return frame
end

--------------------------------------------------------------------------------
-- Position Persistence
--------------------------------------------------------------------------------

function W:_SavePosition()
    if not widgetFrame then return end
    local point, _, relativePoint, x, y = widgetFrame:GetPoint(1)
    if not point then return end

    local comp = getComponent()
    if not comp then return end
    if isOnProxy(comp) then
        addon:EnsureComponentDB(comp)
    end
    if not comp.db then return end
    comp.db.position = {
        point = point,
        relativePoint = relativePoint,
        xOfs = x,
        yOfs = y,
    }
end

function W:_RestorePosition()
    if not widgetFrame then return end
    local pos = getSetting("position", nil)
    widgetFrame:ClearAllPoints()
    if type(pos) == "table" and pos.point then
        widgetFrame:SetPoint(pos.point, UIParent, pos.relativePoint or pos.point,
            pos.xOfs or 0, pos.yOfs or 0)
    else
        widgetFrame:SetPoint(DEFAULT_POINT, UIParent, DEFAULT_RELATIVE, DEFAULT_X, DEFAULT_Y)
    end
end

function W:ResetPosition()
    if not widgetFrame then return end
    local comp = getComponent()
    if comp and not isOnProxy(comp) and comp.db then
        comp.db.position = nil
    end
    widgetFrame:ClearAllPoints()
    widgetFrame:SetPoint(DEFAULT_POINT, UIParent, DEFAULT_RELATIVE, DEFAULT_X, DEFAULT_Y)
    W:_ReflowFlyoutChildren()
end

--------------------------------------------------------------------------------
-- Combat-Aware Opacity
--------------------------------------------------------------------------------

function W:_ApplyOpacity()
    if not widgetFrame then return end
    local pct
    if hoverActive then
        pct = tonumber(getSetting("opacityHover", 100))
    elseif InCombatLockdown and InCombatLockdown() then
        pct = tonumber(getSetting("opacityCombat", 40))
    else
        pct = tonumber(getSetting("opacityOOC", 100))
    end
    pct = math.max(0, math.min(100, pct or 100))
    local alpha = pct / 100
    widgetFrame:SetAlpha(alpha)
end

--------------------------------------------------------------------------------
-- Flyout Direction Anchoring
--------------------------------------------------------------------------------
-- The diamond is the panel head: it sits on the near edge of the topmost
-- child, and children stack along the flyout direction.
--
--   down  -> child TOP    anchors to anchorTarget BOTTOM (panel hangs below)
--   up    -> child BOTTOM anchors to anchorTarget TOP    (panel grows up)
--   right -> child LEFT   anchors to anchorTarget RIGHT  (panel extends right)
--   left  -> child RIGHT  anchors to anchorTarget LEFT   (panel extends left)

local function getDirectionAnchors(direction)
    if direction == FLY_UP then
        return "BOTTOM", "TOP", 0, 0
    elseif direction == FLY_LEFT then
        return "RIGHT", "LEFT", 0, 0
    elseif direction == FLY_RIGHT then
        return "LEFT", "RIGHT", 0, 0
    end
    return "TOP", "BOTTOM", 0, 0  -- down (default)
end

local function anchorChildToTarget(childFrame, anchorTarget, direction)
    if not childFrame or not anchorTarget then return end
    local childPt, parentPt, xOfs, yOfs = getDirectionAnchors(direction)
    childFrame:ClearAllPoints()
    childFrame:SetPoint(childPt, anchorTarget, parentPt, xOfs, yOfs)
end

--------------------------------------------------------------------------------
-- Flyout Child Registry & Stacking
--------------------------------------------------------------------------------

function W:_ReflowFlyoutChildren()
    if not widgetFrame then return end
    local direction = getSetting("flyoutDirection", FLY_DOWN)
    local anchorTarget = widgetFrame
    for _, entry in ipairs(flyoutChain) do
        anchorChildToTarget(entry.frame, anchorTarget, direction)
        anchorTarget = entry.frame
    end
end

function W:RegisterFlyoutChild(frame, opts)
    if not frame then return nil end
    if not widgetFrame then createWidgetFrame() end
    local handle = {
        id = nextHandleId,
        frame = frame,
        opts = opts or {},
    }
    nextHandleId = nextHandleId + 1
    table.insert(flyoutChain, handle)
    self:_ReflowFlyoutChildren()
    return handle
end

function W:ReleaseFlyoutChild(handle)
    if not handle then return false end
    for i, entry in ipairs(flyoutChain) do
        if entry == handle or (entry.id and entry.id == handle.id) then
            table.remove(flyoutChain, i)
            local opts = entry.opts
            if opts and type(opts.onRelease) == "function" then
                pcall(opts.onRelease, entry.frame)
            end
            self:_ReflowFlyoutChildren()
            return true
        end
    end
    return false
end

function W:ReleaseAllFlyoutChildren()
    while #flyoutChain > 0 do
        local entry = table.remove(flyoutChain)
        local opts = entry.opts
        if opts and type(opts.onRelease) == "function" then
            pcall(opts.onRelease, entry.frame)
        end
    end
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

function W:GetAnchorForFlyout()
    if not widgetFrame then return nil end
    local direction = getSetting("flyoutDirection", FLY_DOWN)
    local childPt, parentPt, xOfs, yOfs = getDirectionAnchors(direction)
    return childPt, widgetFrame, parentPt, xOfs, yOfs
end

function W:IsVisible()
    if not widgetFrame then return false end
    if not widgetFrame:IsShown() then return false end
    return widgetFrame:GetAlpha() > 0.01
end

function W:GetFrame()
    return widgetFrame
end

function W:GetFlyoutDirection()
    return getSetting("flyoutDirection", FLY_DOWN)
end

-- Registers the plain-left-click handler (the reports menu today). One slot:
-- consumers own multiplexing if they ever need it, so future features never
-- have to touch the widget core again.
function W:SetClickHandler(fn)
    W._clickHandler = fn
end

--------------------------------------------------------------------------------
-- ApplyStyling
--------------------------------------------------------------------------------

-- The widget's module-level toggle on the Features page is the only enable gate.
-- If this initializer ran, the user opted in; ApplyStyling unconditionally renders
-- the diamond. Settings reads fall through the proxy / metatable to defaults when
-- the user hasn't customized anything yet.
local function ApplyWidgetStyling(self)
    if not widgetFrame then createWidgetFrame() end

    local strata = getSetting("frameStrata", "MEDIUM")
    pcall(widgetFrame.SetFrameStrata, widgetFrame, strata)

    local size = tonumber(getSetting("iconSize", DEFAULT_SIZE)) or DEFAULT_SIZE
    size = math.max(MIN_SIZE, math.min(MAX_SIZE, size))
    applyDiamondSize(size)

    W:_RestorePosition()

    widgetFrame:Show()
    W:_ApplyOpacity()

    W:_ReflowFlyoutChildren()
end

--------------------------------------------------------------------------------
-- Combat Event Handling
--------------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:SetScript("OnEvent", function(_, event)
    local comp = getComponent()
    if not comp then return end
    if event == "PLAYER_ENTERING_WORLD" then
        comp:ApplyStyling()
    else
        W:_ApplyOpacity()
    end
end)

--------------------------------------------------------------------------------
-- Component Registration
--------------------------------------------------------------------------------

addon:RegisterComponentInitializer(function(self)
    local Component = addon.ComponentPrototype

    local widgetComponent = Component:New({
        id = "widget",
        name = "Widget",
        settings = {
            iconSize        = { type = "addon", default = 20 },
            position        = { type = "addon", default = nil },
            flyoutDirection = { type = "addon", default = "down" },
            opacityCombat   = { type = "addon", default = 40 },
            opacityOOC      = { type = "addon", default = 100 },
            opacityHover    = { type = "addon", default = 100 },
            frameStrata     = { type = "addon", default = "MEDIUM" },
        },
        ApplyStyling = ApplyWidgetStyling,
    })

    self:RegisterComponent(widgetComponent)

    -- Warm the shared inspect service only when a report is enabled: the
    -- widget alone (no reports) must not generate background inspects.
    if addon.Reports and addon.Reports:HasAnyEnabled() and addon.Inspect then
        addon.Inspect:EnsureStarted()
    end

    -- Module-enabled means widget-visible. addon:ApplyStyles only iterates
    -- components with a materialized DB (zero-touch), which won't be true for
    -- a fresh user who hasn't tweaked any setting yet. Render directly here so
    -- the diamond appears the moment the module turns on.
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            if widgetComponent.ApplyStyling then
                widgetComponent:ApplyStyling()
            end
        end)
    end
end, "widget")
