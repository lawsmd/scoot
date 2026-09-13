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
local FLYOUT_NUB_CORNER = 6        -- straight border kept between the nub and a panel corner
local FLYOUT_CONTENT_PADDING = 8
local FLYOUT_DEFAULT_WIDTH = 200
local FLYOUT_DEFAULT_HEIGHT = 150

local TRIANGLE_TEXTURE = "Interface\\AddOns\\Scoot\\media\\textures\\flyout-nub"

-- The nub is the panel border continued: an accent triangle with a
-- background-colored triangle over it, inset by the border width along the
-- two slanted edges. Both bases sit inside the panel. The accent triangle's
-- base lies on the inner edge of the border strip and its sides run into the
-- strip; the fill's base lies one pixel deeper and paints over the strip
-- between the two corners, which breaks the strip under the nub.
local NUB_FILL_EXTRA = 1
local NUB_BORDER_BASE = FLYOUT_BORDER_WIDTH
local NUB_FILL_BASE = NUB_BORDER_BASE + NUB_FILL_EXTRA
local NUB_SLANT = math.sqrt(FLYOUT_NUB_HEIGHT ^ 2 + (FLYOUT_NUB_WIDTH / 2) ^ 2)
local NUB_FILL_WIDTH = FLYOUT_NUB_WIDTH * (1 + NUB_FILL_EXTRA / FLYOUT_NUB_HEIGHT)
    - 2 * FLYOUT_BORDER_WIDTH * NUB_SLANT / FLYOUT_NUB_HEIGHT
local NUB_FILL_HEIGHT = FLYOUT_NUB_HEIGHT + NUB_FILL_EXTRA
    - FLYOUT_BORDER_WIDTH * NUB_SLANT / (FLYOUT_NUB_WIDTH / 2)

-- flyout-nub.tga is 32x32 and its triangle stops short of the image edge:
-- two texels on each side and at the apex, three under the base. The quads
-- are sized so the drawn triangle, not the image, measures what was asked
-- for, and anchored by where the drawn base falls.
local NUB_TEX_SIDE = 2 / 32
local NUB_TEX_APEX = 2 / 32
local NUB_TEX_BASE = 3 / 32

-- Quad width and height for a drawn triangle of w by h, and how far the quad
-- runs on past the drawn base line.
local function NubQuad(w, h)
    local qw = w / (1 - 2 * NUB_TEX_SIDE)
    local qh = h / (1 - NUB_TEX_APEX - NUB_TEX_BASE)
    return qw, qh, NUB_TEX_BASE * qh
end

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

-- How far an edge-aligned panel sticks out past the anchor's edge: enough
-- for the nub to center on a trigger narrower than itself and still leave a
-- corner's run of straight border beside it.
local function EdgeShift(panel)
    local aw = panel._anchor and panel._anchor:GetWidth() or 0
    return math.max(0, FLYOUT_NUB_WIDTH / 2 + FLYOUT_NUB_CORNER - aw / 2)
end

local function PositionPanel(panel)
    local anchor = panel._anchor
    local dir = panel._direction
    local gap = panel._gap
    local align = panel._align

    panel:ClearAllPoints()

    if dir == "DOWN" then
        if align == "RIGHT" then
            panel:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", EdgeShift(panel), -gap)
        elseif align == "LEFT" then
            panel:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", -EdgeShift(panel), -gap)
        else
            panel:SetPoint("TOP", anchor, "BOTTOM", 0, -gap)
        end
    elseif dir == "UP" then
        if align == "RIGHT" then
            panel:SetPoint("BOTTOMRIGHT", anchor, "TOPRIGHT", EdgeShift(panel), gap)
        elseif align == "LEFT" then
            panel:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", -EdgeShift(panel), gap)
        else
            panel:SetPoint("BOTTOM", anchor, "TOP", 0, gap)
        end
    elseif dir == "RIGHT" then
        panel:SetPoint("LEFT", anchor, "RIGHT", gap, 0)
    elseif dir == "LEFT" then
        panel:SetPoint("RIGHT", anchor, "LEFT", -gap, 0)
    end
end

-- The nub's center along the panel edge, relative to the panel's center. An
-- edge-aligned panel aims it at the anchor's center, held a corner's run
-- inside the panel edge; a centered panel uses the offset the caller set.
local function NubOffset(panel)
    local align = panel._align
    if align ~= "LEFT" and align ~= "RIGHT" then return panel._nubOffset or 0 end
    local pw = panel:GetWidth() or 0
    local aw = panel._anchor and panel._anchor:GetWidth() or 0
    local reach = pw / 2 - aw / 2 - EdgeShift(panel)
    local limit = math.max(0, pw / 2 - FLYOUT_NUB_WIDTH / 2 - FLYOUT_NUB_CORNER)
    reach = math.max(-limit, math.min(limit, reach))
    if align == "LEFT" then reach = -reach end
    return math.floor(reach)
end

local function PositionNub(panel)
    local dir = panel._direction
    local nubBorder = panel._nubBorder
    local nubFill = panel._nubFill
    local offset = NubOffset(panel)
    local isHorizontal = (dir == "LEFT" or dir == "RIGHT")

    local bw, bh, bOver = NubQuad(FLYOUT_NUB_WIDTH, FLYOUT_NUB_HEIGHT)
    local fw, fh, fOver = NubQuad(NUB_FILL_WIDTH, NUB_FILL_HEIGHT)
    -- Quad edge to panel edge, measured into the panel.
    local bIn = NUB_BORDER_BASE + bOver
    local fIn = NUB_FILL_BASE + fOver

    nubBorder:ClearAllPoints()
    nubFill:ClearAllPoints()

    -- SetRotation turns the image inside the quad, so the quad's width and
    -- height swap for the horizontal directions.
    if isHorizontal then
        nubBorder:SetSize(bh, bw)
        nubFill:SetSize(fh, fw)
    else
        nubBorder:SetSize(bw, bh)
        nubFill:SetSize(fw, fh)
    end

    local rotation = NUB_ROTATION[dir]
    nubBorder:SetRotation(rotation)
    nubFill:SetRotation(rotation)

    if dir == "DOWN" then
        -- nub on top edge, pointing up toward trigger
        nubBorder:SetPoint("BOTTOM", panel, "TOP", offset, -bIn)
        nubFill:SetPoint("BOTTOM", panel, "TOP", offset, -fIn)
    elseif dir == "UP" then
        -- nub on bottom edge, pointing down toward trigger
        nubBorder:SetPoint("TOP", panel, "BOTTOM", offset, bIn)
        nubFill:SetPoint("TOP", panel, "BOTTOM", offset, fIn)
    elseif dir == "RIGHT" then
        -- nub on left edge, pointing left toward trigger
        nubBorder:SetPoint("RIGHT", panel, "LEFT", bIn, offset)
        nubFill:SetPoint("RIGHT", panel, "LEFT", fIn, offset)
    elseif dir == "LEFT" then
        -- nub on right edge, pointing right toward trigger
        nubBorder:SetPoint("LEFT", panel, "RIGHT", -bIn, offset)
        nubFill:SetPoint("LEFT", panel, "RIGHT", -fIn, offset)
    end
end

-- Kept off Controls.CreatePopupList: the flyout floats caller-built content
-- with four-direction nub anchoring and an open cooldown, not an option list.
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

    panel._dismiss:Show()
    panel._dismiss:SetFrameLevel(panel:GetFrameLevel() - 1)

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
    panel._dismiss:Hide()

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
--   align      : string  "CENTER" (default) centers the panel on the trigger.
--                        "LEFT" or "RIGHT", for DOWN and UP, sets that panel
--                        edge on the trigger's and aims the nub at the
--                        trigger's center; a trigger narrower than the nub
--                        pushes the panel out past the edge so a corner's run
--                        of straight border stays beside the nub. nubOffset
--                        is ignored while aligned.
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
    local align = options.align
    if align ~= "LEFT" and align ~= "RIGHT" then align = "CENTER" end
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
    panel._align = align
    panel._nubOffset = nubOffset
    panel._padding = padding
    panel._onShow = onShow
    panel._onHide = onHide
    panel._isOpen = false

    ---------------------------------------------------------------------------
    -- Background
    ---------------------------------------------------------------------------

    panel._bg = Controls.AddBackground(panel, {
        inset = FLYOUT_BORDER_WIDTH,
        alpha = FLYOUT_BG_ALPHA,
    })
    panel._bgAlpha = FLYOUT_BG_ALPHA

    ---------------------------------------------------------------------------
    -- Border (4 edges, matching Dropdown.lua pattern)
    ---------------------------------------------------------------------------

    panel._border = Controls.CreateBorder(panel, {
        thickness = FLYOUT_BORDER_WIDTH,
        alpha = FLYOUT_BORDER_ALPHA,
    })

    ---------------------------------------------------------------------------
    -- Nub (two-triangle bordered approach; sized and placed by PositionNub)
    ---------------------------------------------------------------------------

    -- Outer triangle (accent/border color)
    local nubBorder = panel:CreateTexture(nil, "OVERLAY", nil, 1)
    nubBorder:SetTexture(TRIANGLE_TEXTURE)
    nubBorder:SetSize(NubQuad(FLYOUT_NUB_WIDTH, FLYOUT_NUB_HEIGHT))
    nubBorder:SetVertexColor(ar, ag, ab, FLYOUT_BORDER_ALPHA)
    panel._nubBorder = nubBorder

    -- Inner triangle (background color, inset by the border width)
    local nubFill = panel:CreateTexture(nil, "OVERLAY", nil, 2)
    nubFill:SetTexture(TRIANGLE_TEXTURE)
    nubFill:SetSize(NubQuad(NUB_FILL_WIDTH, NUB_FILL_HEIGHT))
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

    panel._dismiss = Controls.AttachDismissOnClickOutside(function()
        CloseFlyout(panel)
    end)

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

    -- Centered panels only; an aligned panel places its own nub.
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
        if self._dismiss then
            self._dismiss:Hide()
            self._dismiss:SetParent(nil)
        end
    end

    return panel
end
