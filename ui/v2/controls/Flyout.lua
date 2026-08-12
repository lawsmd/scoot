-- Flyout.lua - Flexible flyout menu panel with directional nub
-- Provides a generic flyout panel that opens from any trigger button
-- in any cardinal direction, with a triangular nub pointing back at the trigger.
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.Controls = addon.UI.Controls or {}
local Controls = addon.UI.Controls
local Theme -- Will be set after Theme.lua loads

-- Lazy Theme accessor
local function GetTheme()
    if not Theme then
        Theme = addon.UI.Theme
    end
    return Theme
end

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

local FLYOUT_BORDER_WIDTH = 1
local FLYOUT_BORDER_ALPHA = 0.8
local FLYOUT_BG_ALPHA = 0.98
local FLYOUT_GAP = 6
local FLYOUT_NUB_WIDTH = 28
local FLYOUT_NUB_HEIGHT = 16
local FLYOUT_NUB_OVERLAP = 1
local FLYOUT_CONTENT_PADDING = 8
local FLYOUT_DEFAULT_WIDTH = 200
local FLYOUT_DEFAULT_HEIGHT = 150

local TRIANGLE_TEXTURE = "Interface\\AddOns\\Scoot\\media\\textures\\flyout-nub"

-- Source texture points UP. SetRotation rotates counterclockwise.
-- The nub points toward the trigger (opposite of open direction).
local NUB_ROTATION = {
    DOWN  = 0,              -- panel below trigger, nub on top edge points UP
    UP    = math.pi,        -- panel above trigger, nub on bottom edge points DOWN
    LEFT  = -math.pi / 2,   -- panel left of trigger, nub on right edge points RIGHT
    RIGHT = math.pi / 2,    -- panel right of trigger, nub on left edge points LEFT
}

--------------------------------------------------------------------------------
-- Local helpers
--------------------------------------------------------------------------------

local function PositionPanel(panel)
    local anchor = panel._anchor
    local dir = panel._direction
    local gap = panel._gap

    panel:ClearAllPoints()

    if dir == "DOWN" then
        panel:SetPoint("TOP", anchor, "BOTTOM", 0, -gap)
    elseif dir == "UP" then
        panel:SetPoint("BOTTOM", anchor, "TOP", 0, gap)
    elseif dir == "RIGHT" then
        panel:SetPoint("LEFT", anchor, "RIGHT", gap, 0)
    elseif dir == "LEFT" then
        panel:SetPoint("RIGHT", anchor, "LEFT", -gap, 0)
    end
end

local function PositionNub(panel)
    local dir = panel._direction
    local nubBorder = panel._nubBorder
    local nubFill = panel._nubFill
    local overlap = FLYOUT_NUB_OVERLAP
    local offset = panel._nubOffset or 0
    local isHorizontal = (dir == "LEFT" or dir == "RIGHT")

    nubBorder:ClearAllPoints()
    nubFill:ClearAllPoints()

    -- SetRotation rotates within the existing frame bounds, so swap
    -- width/height for horizontal directions to keep the triangle proportional
    if isHorizontal then
        nubBorder:SetSize(FLYOUT_NUB_HEIGHT, FLYOUT_NUB_WIDTH)
        nubFill:SetSize(FLYOUT_NUB_HEIGHT - 2, FLYOUT_NUB_WIDTH - 2)
    else
        nubBorder:SetSize(FLYOUT_NUB_WIDTH, FLYOUT_NUB_HEIGHT)
        nubFill:SetSize(FLYOUT_NUB_WIDTH - 2, FLYOUT_NUB_HEIGHT - 2)
    end

    local rotation = NUB_ROTATION[dir]
    nubBorder:SetRotation(rotation)
    nubFill:SetRotation(rotation)

    if dir == "DOWN" then
        -- nub on top edge, pointing up toward trigger
        nubBorder:SetPoint("BOTTOM", panel, "TOP", offset, -overlap)
        nubFill:SetPoint("BOTTOM", panel, "TOP", offset, -overlap + 1)
    elseif dir == "UP" then
        -- nub on bottom edge, pointing down toward trigger
        nubBorder:SetPoint("TOP", panel, "BOTTOM", offset, overlap)
        nubFill:SetPoint("TOP", panel, "BOTTOM", offset, overlap - 1)
    elseif dir == "RIGHT" then
        -- nub on left edge, pointing left toward trigger
        nubBorder:SetPoint("RIGHT", panel, "LEFT", overlap, offset)
        nubFill:SetPoint("RIGHT", panel, "LEFT", overlap - 1, offset)
    elseif dir == "LEFT" then
        -- nub on right edge, pointing right toward trigger
        nubBorder:SetPoint("LEFT", panel, "RIGHT", -overlap, offset)
        nubFill:SetPoint("LEFT", panel, "RIGHT", -overlap + 1, offset)
    end
end

local function OpenFlyout(panel)
    if panel._isOpen then return end
    panel._isOpen = true

    -- Prevent Toggle() from immediately closing after opening.
    -- CreateButton registers for AnyUp+AnyDown, so a single physical click
    -- fires OnClick twice (down then up) across consecutive frames. Without
    -- this guard the second Toggle() call would close the flyout instantly.
    panel._openTime = GetTime()

    PositionPanel(panel)
    PositionNub(panel)

    panel._closeListener:Show()
    panel._closeListener:SetFrameLevel(panel:GetFrameLevel() - 1)

    panel:Show()
    panel:Raise()

    PlaySound(SOUNDKIT.IG_MAINMENU_OPEN)

    if panel._onShow then
        panel._onShow(panel)
    end
end

local function CloseFlyout(panel)
    if not panel._isOpen then return end
    panel._isOpen = false

    panel:Hide()
    panel._closeListener:Hide()

    PlaySound(SOUNDKIT.IG_MAINMENU_CLOSE)

    if panel._onHide then
        panel._onHide(panel)
    end
end

local FLYOUT_TOGGLE_COOLDOWN = 0.25

local function ToggleFlyout(panel)
    if panel._openTime and (GetTime() - panel._openTime) < FLYOUT_TOGGLE_COOLDOWN then return end
    if panel._isOpen then
        CloseFlyout(panel)
    else
        OpenFlyout(panel)
    end
end

--------------------------------------------------------------------------------
-- Controls:CreateFlyout(options)
--------------------------------------------------------------------------------
-- Creates a flexible flyout panel with a directional nub that points at the
-- trigger button. Returns the panel frame with public methods attached.
--
-- Options table:
--   anchor     : Frame   (required) trigger button the flyout opens from
--   direction  : string  "UP"/"DOWN"/"LEFT"/"RIGHT" (default "DOWN")
--   width      : number  panel width (default 200)
--   height     : number  panel height (default 150)
--   padding    : number  content inset (default 8)
--   gap        : number  trigger-to-panel spacing (default 6). Negative values
--                        overlap the panel onto the trigger, so the trigger
--                        reads as the panel's head (see WidgetMenu.lua)
--   nubOffset  : number  nub offset along panel edge, 0 = centered on anchor (default 0)
--   showNub    : boolean show the triangle nub (default true)
--   onShow     : function(panel) callback when opened
--   onHide     : function(panel) callback when closed
--   name       : string  optional global frame name
--------------------------------------------------------------------------------

function Controls:CreateFlyout(options)
    local theme = GetTheme()
    if not options or not options.anchor then
        return nil
    end

    local anchor = options.anchor
    local direction = options.direction or "DOWN"
    local panelWidth = options.width or FLYOUT_DEFAULT_WIDTH
    local panelHeight = options.height or FLYOUT_DEFAULT_HEIGHT
    local padding = options.padding or FLYOUT_CONTENT_PADDING
    local gap = options.gap or FLYOUT_GAP
    local nubOffset = options.nubOffset or 0
    local showNub = (options.showNub ~= false)
    local onShow = options.onShow
    local onHide = options.onHide
    local name = options.name

    -- Get theme colors
    local ar, ag, ab = theme:GetAccentColor()
    local bgR, bgG, bgB = theme:GetBackgroundSolidColor()

    ---------------------------------------------------------------------------
    -- Panel frame
    ---------------------------------------------------------------------------

    local panel = CreateFrame("Frame", name, UIParent)
    panel:SetFrameStrata("FULLSCREEN_DIALOG")
    panel:SetFrameLevel(100)
    panel:SetClampedToScreen(true)
    panel:EnableMouse(true)
    panel:SetSize(panelWidth, panelHeight)
    panel:Hide()

    -- State
    panel._anchor = anchor
    panel._direction = direction
    panel._gap = gap
    panel._nubOffset = nubOffset
    panel._padding = padding
    panel._onShow = onShow
    panel._onHide = onHide
    panel._isOpen = false

    ---------------------------------------------------------------------------
    -- Background
    ---------------------------------------------------------------------------

    local bg = panel:CreateTexture(nil, "BACKGROUND", nil, -8)
    bg:SetPoint("TOPLEFT", FLYOUT_BORDER_WIDTH, -FLYOUT_BORDER_WIDTH)
    bg:SetPoint("BOTTOMRIGHT", -FLYOUT_BORDER_WIDTH, FLYOUT_BORDER_WIDTH)
    bg:SetColorTexture(bgR, bgG, bgB, FLYOUT_BG_ALPHA)
    panel._bg = bg
    panel._bgAlpha = FLYOUT_BG_ALPHA

    ---------------------------------------------------------------------------
    -- Border (4 edges, matching Dropdown.lua pattern)
    ---------------------------------------------------------------------------

    local border = {}

    local bTop = panel:CreateTexture(nil, "BORDER", nil, -1)
    bTop:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
    bTop:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, 0)
    bTop:SetHeight(FLYOUT_BORDER_WIDTH)
    bTop:SetColorTexture(ar, ag, ab, FLYOUT_BORDER_ALPHA)
    border.TOP = bTop

    local bBottom = panel:CreateTexture(nil, "BORDER", nil, -1)
    bBottom:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 0, 0)
    bBottom:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0)
    bBottom:SetHeight(FLYOUT_BORDER_WIDTH)
    bBottom:SetColorTexture(ar, ag, ab, FLYOUT_BORDER_ALPHA)
    border.BOTTOM = bBottom

    local bLeft = panel:CreateTexture(nil, "BORDER", nil, -1)
    bLeft:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -FLYOUT_BORDER_WIDTH)
    bLeft:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 0, FLYOUT_BORDER_WIDTH)
    bLeft:SetWidth(FLYOUT_BORDER_WIDTH)
    bLeft:SetColorTexture(ar, ag, ab, FLYOUT_BORDER_ALPHA)
    border.LEFT = bLeft

    local bRight = panel:CreateTexture(nil, "BORDER", nil, -1)
    bRight:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, -FLYOUT_BORDER_WIDTH)
    bRight:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, FLYOUT_BORDER_WIDTH)
    bRight:SetWidth(FLYOUT_BORDER_WIDTH)
    bRight:SetColorTexture(ar, ag, ab, FLYOUT_BORDER_ALPHA)
    border.RIGHT = bRight

    panel._border = border

    ---------------------------------------------------------------------------
    -- Nub (two-triangle bordered approach)
    ---------------------------------------------------------------------------

    -- Outer triangle (accent/border color)
    local nubBorder = panel:CreateTexture(nil, "OVERLAY", nil, 1)
    nubBorder:SetTexture(TRIANGLE_TEXTURE)
    nubBorder:SetSize(FLYOUT_NUB_WIDTH, FLYOUT_NUB_HEIGHT)
    nubBorder:SetVertexColor(ar, ag, ab, FLYOUT_BORDER_ALPHA)
    panel._nubBorder = nubBorder

    -- Inner triangle (background color, slightly smaller)
    local nubFill = panel:CreateTexture(nil, "OVERLAY", nil, 2)
    nubFill:SetTexture(TRIANGLE_TEXTURE)
    nubFill:SetSize(FLYOUT_NUB_WIDTH - 2, FLYOUT_NUB_HEIGHT - 2)
    nubFill:SetVertexColor(bgR, bgG, bgB, FLYOUT_BG_ALPHA)
    panel._nubFill = nubFill

    if not showNub then
        nubBorder:Hide()
        nubFill:Hide()
    end

    ---------------------------------------------------------------------------
    -- Content frame
    ---------------------------------------------------------------------------

    local inset = padding + FLYOUT_BORDER_WIDTH
    local content = CreateFrame("Frame", nil, panel)
    content:SetPoint("TOPLEFT", panel, "TOPLEFT", inset, -inset)
    content:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -inset, inset)
    panel._content = content

    ---------------------------------------------------------------------------
    -- Close listener (invisible fullscreen button)
    ---------------------------------------------------------------------------

    local closeListener = CreateFrame("Button", nil, UIParent)
    closeListener:SetFrameStrata("FULLSCREEN")
    closeListener:SetFrameLevel(99)
    closeListener:SetAllPoints(UIParent)
    closeListener:EnableMouse(true)
    closeListener:RegisterForClicks("AnyDown")
    closeListener:SetScript("OnClick", function()
        CloseFlyout(panel)
    end)
    closeListener:Hide()
    panel._closeListener = closeListener

    ---------------------------------------------------------------------------
    -- ESC key handling
    ---------------------------------------------------------------------------

    addon.EscapeKey.Attach(panel, function(self)
        CloseFlyout(self)
    end)

    ---------------------------------------------------------------------------
    -- Theme subscription
    ---------------------------------------------------------------------------

    local subscribeKey = "Flyout_" .. (name or tostring(panel))
    panel._subscribeKey = subscribeKey

    theme:Subscribe(subscribeKey, function(r, g, b)
        for _, tex in pairs(panel._border) do
            tex:SetColorTexture(r, g, b, FLYOUT_BORDER_ALPHA)
        end
        panel._nubBorder:SetVertexColor(r, g, b, FLYOUT_BORDER_ALPHA)
    end)

    ---------------------------------------------------------------------------
    -- Public methods
    ---------------------------------------------------------------------------

    function panel:Open()
        OpenFlyout(self)
    end

    function panel:Close()
        CloseFlyout(self)
    end

    function panel:Toggle()
        ToggleFlyout(self)
    end

    function panel:IsOpen()
        return self._isOpen
    end

    function panel:GetContent()
        return self._content
    end

    function panel:SetDirection(dir)
        self._direction = dir
        if self._isOpen then
            PositionPanel(self)
            PositionNub(self)
        end
    end

    function panel:SetAnchor(newAnchor)
        self._anchor = newAnchor
        if self._isOpen then
            PositionPanel(self)
            PositionNub(self)
        end
    end

    function panel:SetFlyoutSize(w, h)
        self:SetSize(w, h)
        if self._isOpen then
            PositionPanel(self)
            PositionNub(self)
        end
    end

    -- Trigger-to-panel spacing. Negative values overlap the panel onto the
    -- trigger, letting the trigger read as the panel's head.
    function panel:SetGap(newGap)
        self._gap = newGap
        if self._isOpen then
            PositionPanel(self)
            PositionNub(self)
        end
    end

    -- Backdrop opacity, 0-1. The panel fill and the nub's fill are the same
    -- surface seen from two angles, so they always move together; the border
    -- and the nub's outline are deliberately left alone, so a near-transparent
    -- panel still reads as a panel.
    function panel:SetBackdropAlpha(alpha)
        alpha = tonumber(alpha)
        if not alpha then return end
        alpha = math.max(0, math.min(1, alpha))
        self._bgAlpha = alpha
        local r, g, b = GetTheme():GetBackgroundSolidColor()
        self._bg:SetColorTexture(r, g, b, alpha)
        self._nubFill:SetVertexColor(r, g, b, alpha)
    end

    function panel:SetNubOffset(offset)
        self._nubOffset = offset
        if self._isOpen then
            PositionNub(self)
        end
    end

    function panel:SetNubShown(shown)
        self._nubBorder:SetShown(shown)
        self._nubFill:SetShown(shown)
    end

    function panel:Cleanup()
        if self._subscribeKey then
            theme:Unsubscribe(self._subscribeKey)
        end
        CloseFlyout(self)
        if self._closeListener then
            self._closeListener:Hide()
            self._closeListener:SetParent(nil)
        end
    end

    return panel
end
