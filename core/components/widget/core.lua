-- widget/core.lua - QoL Widget: floating diamond launchpad for notifications and reports
local addonName, addon = ...

addon.Widget = addon.Widget or {}
local W = addon.Widget

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

local DEFAULT_SIZE = 20
local MIN_SIZE = 16
local MAX_SIZE = 40

local DIAMOND_BLACK = { 0, 0, 0, 1 }

local SQRT2_INV = 0.70710678  -- 1 / sqrt(2)
local OUTLINE_THICKNESS = 1.5  -- visible black ring in pixels (constant across sizes)

local DEFAULT_POINT = "TOPLEFT"
local DEFAULT_RELATIVE = "TOPLEFT"
local DEFAULT_X = 100
local DEFAULT_Y = -200

local FLY_DOWN, FLY_UP, FLY_LEFT, FLY_RIGHT = "down", "up", "left", "right"

-- Breathing room between the diamond's intruding half and a panel's content.
local HEAD_CLEARANCE = 3

-- While a persistent surface (a report panel) is attached, the widget rides at
-- this strata so the panel clears always-on-screen HUD elements that live at
-- MEDIUM. Ranks let the raise skip users who configured something higher.
local CHAIN_STRATA = "HIGH"
local STRATA_RANK = {
    BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4,
    DIALOG = 5, FULLSCREEN = 6, FULLSCREEN_DIALOG = 7, TOOLTIP = 8,
}

--------------------------------------------------------------------------------
-- Module-Level State
--------------------------------------------------------------------------------

local widgetFrame      -- main container Frame
local diamondOutline   -- black rotated square (texture)
local diamondFill      -- accent-colored rotated square (texture)

local flyoutChain = {}  -- ordered list of registered child handles
local nextHandleId = 1
local chainStrataRaised = false  -- we moved the widget to CHAIN_STRATA, so we owe a restore

local hoverActive = false

--------------------------------------------------------------------------------
-- DB Helpers
--------------------------------------------------------------------------------

local function getComponent()
    return addon.Components and addon.Components["widget"]
end

local isOnProxy = addon.IsComponentUnconfigured

local function getSetting(key, fallback)
    local v = addon.GetComponentSetting("widget", key)
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

    -- Accent-colored fill diamond (rotated square above the outline)
    local fill = frame:CreateTexture(nil, "ARTWORK", nil, 1)
    local ar, ag, ab = addon.GetAccentColorRGB()
    fill:SetColorTexture(ar, ag, ab, 1)
    fill:SetRotation(math.rad(45))
    fill:SetPoint("CENTER")

    widgetFrame = frame
    diamondOutline = outline
    diamondFill = fill

    -- The widget is built once and lives for the session, so the diamond
    -- repaints on accent changes rather than freezing at build.
    local theme = addon.UI and addon.UI.Theme
    if theme and theme.Subscribe then
        theme:Subscribe("ScootWidgetDiamond", function(r, g, b)
            fill:SetColorTexture(r, g, b, 1)
        end)
    end

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

-- Hover pre-empts the pair; the combat and out-of-combat values resolve
-- through addon.Opacity (no target state, so the CombatOnly key set).
function W:_ApplyOpacity()
    if not widgetFrame then return end
    local alpha
    if hoverActive then
        local pct = tonumber(getSetting("opacityHover", 100)) or 100
        alpha = math.max(0, math.min(100, pct)) / 100
    else
        local comp = getComponent()
        alpha = addon.Opacity.Resolve(comp and comp.db, addon.Opacity.Keys.CombatOnly)
    end
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
--
-- The head child (the one anchored to the diamond itself) is pulled back by
-- GetHeadOffset() so its near edge runs through the diamond's two side
-- corners. Children further down the chain anchor to their predecessor with
-- no offset, so only the first one wears the diamond.

local function getDirectionAnchors(direction, isHead)
    local off = isHead and W:GetHeadOffset() or 0
    if direction == FLY_UP then
        return "BOTTOM", "TOP", 0, -off
    elseif direction == FLY_LEFT then
        return "RIGHT", "LEFT", off, 0
    elseif direction == FLY_RIGHT then
        return "LEFT", "RIGHT", -off, 0
    end
    return "TOP", "BOTTOM", 0, off  -- down (default)
end

local function anchorChildToTarget(childFrame, anchorTarget, direction, isHead)
    if not childFrame or not anchorTarget then return end
    local childPt, parentPt, xOfs, yOfs = getDirectionAnchors(direction, isHead)
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

    -- Report panels must clear the always-on-screen HUD (damage meters and
    -- the like sit at MEDIUM with busy frame levels), so the whole assembly
    -- rides at CHAIN_STRATA while any child is attached — raised on the
    -- widget, not the child, because children inherit the parent's strata and
    -- the head child draws one level under the diamond, which only holds with
    -- both on the same strata. Never lowers a user-configured DIALOG+ widget,
    -- and only touches strata it raised itself: the WidgetMenu holds its own
    -- temporary raise (savedStrata) that a drag mid-menu must not stomp.
    if #flyoutChain > 0 then
        local configured = getSetting("frameStrata", "MEDIUM")
        if (STRATA_RANK[configured] or 0) < STRATA_RANK[CHAIN_STRATA] then
            pcall(widgetFrame.SetFrameStrata, widgetFrame, CHAIN_STRATA)
            chainStrataRaised = true
        end
    elseif chainStrataRaised then
        chainStrataRaised = false
        pcall(widgetFrame.SetFrameStrata, widgetFrame, getSetting("frameStrata", "MEDIUM"))
    end

    -- Half the diamond sits inside the head child, and children draw above
    -- their parent by default, so without this the panel swallows the lower
    -- half of the icon. Dropping the child a level lets the diamond draw on
    -- top without touching the widget's configured strata.
    local level = widgetFrame:GetFrameLevel()
    if level < 1 then
        widgetFrame:SetFrameLevel(1)
        level = 1
    end

    for i, entry in ipairs(flyoutChain) do
        local isHead = (i == 1)
        anchorChildToTarget(entry.frame, anchorTarget, direction, isHead)
        if isHead then
            pcall(entry.frame.SetFrameLevel, entry.frame, level - 1)
        end
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
    self:_ReflowFlyoutChildren()
end

-- True while any persistent surface (a report panel, a future notification)
-- is attached. Callers that want to take over the diamond's flyout space ask
-- this first — see WidgetMenu's "clicking again returns to the list".
function W:HasFlyoutChildren()
    return #flyoutChain > 0
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

function W:GetAnchorForFlyout()
    if not widgetFrame then return nil end
    local direction = getSetting("flyoutDirection", FLY_DOWN)
    -- Anchors straight to the diamond, so it is a head by definition.
    local childPt, parentPt, xOfs, yOfs = getDirectionAnchors(direction, true)
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

-- Clamped edge length of the diamond's container. The diamond is inscribed in
-- it, so half this value is the distance from the container's centre to any
-- corner: consumers anchoring to the diamond's corners need that number.
function W:GetIconSize()
    local size = tonumber(getSetting("iconSize", DEFAULT_SIZE)) or DEFAULT_SIZE
    return math.max(MIN_SIZE, math.min(MAX_SIZE, size))
end

--------------------------------------------------------------------------------
-- Head geometry
--------------------------------------------------------------------------------
-- Every surface the widget spawns wears the diamond as its head: the panel's
-- near edge runs exactly through the diamond's two side corners, so the icon
-- reads as part of the panel rather than a separate thing floating beside it.
-- Both numbers live here so current and future surfaces stay consistent.

-- Centre-to-corner distance of the diamond. Exact, not tuned: the frame is a
-- square with the diamond inscribed and centred, so the side corners land on
-- the container's midline.
function W:GetHeadOffset()
    return self:GetIconSize() / 2
end

-- Layout numbers for a panel wearing the diamond as its head, in the given
-- direction. contentInset is the panel's own padding on the overlapped edge
-- (the diamond only has to clear whatever that padding does not already).
--
-- Returns padTop, padLeft (shift content clear of the intruding half) and
-- extraH, extraW (grow the panel by the same amount, so the usable content
-- box is identical in all four directions).
-- Accepts either case: the widget stores "down", the flyout control uses "DOWN".
function W:GetHeadInset(direction, contentInset)
    direction = direction or self:GetFlyoutDirection()
    if type(direction) == "string" then direction = direction:lower() end
    local depth = math.max(0, math.ceil(self:GetHeadOffset() - (contentInset or 0)) + HEAD_CLEARANCE)
    if direction == FLY_DOWN then
        return depth, 0, 0, 0        -- diamond on the top edge
    elseif direction == FLY_UP then
        return 0, 0, depth, 0        -- diamond on the bottom edge
    elseif direction == FLY_RIGHT then
        return 0, depth, 0, depth    -- diamond on the left edge
    end
    return 0, 0, 0, depth            -- left: diamond on the right edge
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
-- Event Handling
--------------------------------------------------------------------------------

-- Combat and target edges reach _ApplyOpacity through RefreshOpacityState via
-- the component's RefreshOpacity; only the world-entry restyle stays local.
addon.Events.On("Widget", "PLAYER_ENTERING_WORLD", function()
    local comp = getComponent()
    if comp then
        comp:ApplyStyling()
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
            iconSize           = { type = "addon", default = 20 },
            position           = { type = "addon", default = nil },
            flyoutDirection    = { type = "addon", default = "down" },
            opacity            = { type = "addon", default = 40 },
            opacityOutOfCombat = { type = "addon", default = 100 },
            opacityHover       = { type = "addon", default = 100 },
            frameStrata        = { type = "addon", default = "MEDIUM" },
        },
        ApplyStyling = ApplyWidgetStyling,
        RefreshOpacity = function() W:_ApplyOpacity() end,
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

addon:RegisterSlashCommand({
    name = "widget", help = "widget component",
    verbs = {
        { word = "reset", help = "reset the widget position", fn = function()
            addon.Widget:ResetPosition()
            addon:Print("Widget position reset.")
        end },
    },
})
