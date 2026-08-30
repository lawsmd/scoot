-- Utils.lua - Shared utilities for UI controls
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.Controls = addon.UI.Controls or {}
local Controls = addon.UI.Controls

-- Debounce Utility for Edit Mode Sync
-- Coalesces rapid calls into a single delayed call.

local debounceTimers = {}

local function Debounce(key, delay, callback)
    if debounceTimers[key] then
        debounceTimers[key]:Cancel()
        debounceTimers[key] = nil
    end

    delay = delay or 0.2
    debounceTimers[key] = C_Timer.NewTimer(delay, function()
        debounceTimers[key] = nil
        if callback then
            callback()
        end
    end)
end

local function CancelDebounce(key)
    if debounceTimers[key] then
        debounceTimers[key]:Cancel()
        debounceTimers[key] = nil
    end
end

Controls.Debounce = Debounce
Controls.CancelDebounce = CancelDebounce

-- Global Sync Lock System
-- Persists lock state across slider instances that get recreated on panel re-render.

local globalSyncLocks = {}  -- { [debounceKey] = { locked = bool, pendingValue = number } }

local function SetGlobalSyncLock(key, value)
    globalSyncLocks[key] = { locked = true, pendingValue = value }
end

local function ClearGlobalSyncLock(key)
    globalSyncLocks[key] = nil
end

local function IsGlobalSyncLocked(key)
    return globalSyncLocks[key] and globalSyncLocks[key].locked
end

local function GetGlobalSyncPendingValue(key)
    return globalSyncLocks[key] and globalSyncLocks[key].pendingValue
end

Controls.SetGlobalSyncLock = SetGlobalSyncLock
Controls.ClearGlobalSyncLock = ClearGlobalSyncLock
Controls.IsGlobalSyncLocked = IsGlobalSyncLocked
Controls.GetGlobalSyncPendingValue = GetGlobalSyncPendingValue

--------------------------------------------------------------------------------
-- Shared border and background drawing
--------------------------------------------------------------------------------

local Theme -- Will be set after Theme.lua loads
local function GetTheme()
    if not Theme then
        Theme = addon.UI.Theme
    end
    return Theme
end

-- Background z-stack. The three sublevels are load-bearing: base fill below,
-- emphasis/secondary fill above it, hover fill on top.
Controls.SUBLEVEL_BG    = -8
Controls.SUBLEVEL_FILL  = -7
Controls.SUBLEVEL_HOVER = -6

-- House alpha conventions for accent-tinted fills.
Controls.ALPHA_HOVER    = 0.08
Controls.ALPHA_EMPHASIS = 0.03
Controls.ALPHA_SELECTED = 0.12

-- House alpha conventions for borders on focusable controls.
Controls.BORDER_ALPHA_NORMAL = 0.6
Controls.BORDER_ALPHA_FOCUS  = 1.0

-- Per-border state lives here, keyed by the border object, so pairs(border)
-- yields only edge textures. External code iterates _border tables directly
-- (the settings-panel pulse calls tex:SetAlpha on every value), so nothing but
-- textures may ever appear inside a border object.
local borderState = setmetatable({}, { __mode = "k" })

-- Accent-themed objects retinted on accent change. One shared Theme
-- subscription replaces the per-widget keys controls used to mint (which
-- leaked: widgets rebuilt on re-render rarely unsubscribed their old keys).
local themedBorders = setmetatable({}, { __mode = "k" }) -- border object -> true
local themedFills = setmetatable({}, { __mode = "k" })   -- fill texture -> alpha

local themeSubscribed = false
local function EnsureThemeSubscription()
    if themeSubscribed then return end
    local theme = GetTheme()
    if not theme then return end
    themeSubscribed = true
    theme:Subscribe("ScootControlsUtils", function(r, g, b)
        for border in pairs(themedBorders) do
            pcall(border.Refresh, border)
        end
        for fill, alpha in pairs(themedFills) do
            pcall(fill.SetColorTexture, fill, r, g, b, alpha)
        end
    end)
end

local BorderMethods = {}
local BorderMT = { __index = BorderMethods }

-- Re-resolve color and alpha and repaint every edge. Replaces the hand-written
-- pairs(_border) retint loops. Alpha comes from getAlpha when set, so focus and
-- hover states survive an accent change.
function BorderMethods:Refresh()
    local st = borderState[self]
    if not st then return end
    local r, g, b = st.r, st.g, st.b
    if st.themed then
        local theme = GetTheme()
        if theme then
            r, g, b = theme:GetAccentColor()
        end
    end
    local alpha = st.alpha
    if st.getAlpha then
        local resolved = st.getAlpha(st.frame)
        if resolved ~= nil then alpha = resolved end
    end
    for side, tex in pairs(self) do
        local a = alpha
        if st.sideAlphas and st.sideAlphas[side] ~= nil then
            a = st.sideAlphas[side]
        end
        tex:SetColorTexture(r or 0, g or 0, b or 0, a or 1)
    end
end

function BorderMethods:SetAlpha(alpha)
    local st = borderState[self]
    if st then st.alpha = alpha end
    self:Refresh()
end

-- Static color override; the border stops following the accent.
function BorderMethods:SetColor(r, g, b, a)
    local st = borderState[self]
    if st then
        st.themed = false
        themedBorders[self] = nil
        st.r, st.g, st.b = r, g, b
        if a ~= nil then st.alpha = a end
    end
    self:Refresh()
end

function BorderMethods:SetShown(shown)
    for _, tex in pairs(self) do
        tex:SetShown(shown)
    end
end

-- Eager cleanup for owners that tear widgets down (dialog close, card removal).
-- Collection via the weak registries covers everything else.
function BorderMethods:Destroy()
    themedBorders[self] = nil
    borderState[self] = nil
    for _, tex in pairs(self) do
        tex:Hide()
    end
end

-- Draws a solid border on an addon-owned widget and returns a handle whose
-- pairs() yields the edge textures (TOP/BOTTOM/LEFT/RIGHT) and whose methods
-- live on its metatable. The caller stores it (frame._border = ...).
--
-- opts:
--   thickness  edge size in pixels (default 1), or a per-side map such as
--              { BOTTOM = 1, LEFT = 3 } for mixed-weight partial borders
--   corners    "inset" (default; verticals trimmed, single-draw corners),
--              "overlap" (all edges full extent, corners double-drawn),
--              "outset" (border outside the frame rect)
--   sides      nil for all four, or a list such as {"BOTTOM"} / {"LEFT"};
--              partial edges span their full extent
--   layer      draw layer (default "BORDER"), sublevel (default -1)
--   color      nil follows the accent color and retints on accent change;
--              {r,g,b[,a]} is static and never subscribes
--   alpha      base alpha (default 1; a color[4] fills in when alpha is unset)
--   sideAlphas per-side alpha overrides ({ LEFT = 1 }); overridden sides
--              ignore alpha/getAlpha
--   getAlpha   function(frame) -> alpha, consulted at every retint, for
--              focus/hover state that must survive accent changes
function Controls.CreateBorder(frame, opts)
    opts = opts or {}
    local t = opts.thickness or 1
    local function size(side)
        if type(t) == "table" then return t[side] or 1 end
        return t
    end
    local layer = opts.layer or "BORDER"
    local sublevel = (opts.sublevel ~= nil) and opts.sublevel or -1
    local corners = opts.corners or "inset"
    local border = setmetatable({}, BorderMT)

    local wanted
    if opts.sides then
        wanted = {}
        for _, side in ipairs(opts.sides) do
            wanted[side] = true
        end
    end
    local partial = wanted ~= nil

    local function make(side)
        local tex = frame:CreateTexture(nil, layer, nil, sublevel)
        border[side] = tex
        return tex
    end

    if not wanted or wanted.TOP then
        local tex = make("TOP")
        if corners == "outset" then
            tex:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", -size("LEFT"), 0)
            tex:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", size("RIGHT"), 0)
        else
            tex:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
            tex:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
        end
        tex:SetHeight(size("TOP"))
    end
    if not wanted or wanted.BOTTOM then
        local tex = make("BOTTOM")
        if corners == "outset" then
            tex:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", -size("LEFT"), 0)
            tex:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", size("RIGHT"), 0)
        else
            tex:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
            tex:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
        end
        tex:SetHeight(size("BOTTOM"))
    end
    if not wanted or wanted.LEFT then
        local tex = make("LEFT")
        if corners == "outset" then
            tex:SetPoint("TOPRIGHT", frame, "TOPLEFT", 0, 0)
            tex:SetPoint("BOTTOMRIGHT", frame, "BOTTOMLEFT", 0, 0)
        elseif corners == "inset" and not partial then
            tex:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -size("TOP"))
            tex:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, size("BOTTOM"))
        else
            tex:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
            tex:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
        end
        tex:SetWidth(size("LEFT"))
    end
    if not wanted or wanted.RIGHT then
        local tex = make("RIGHT")
        if corners == "outset" then
            tex:SetPoint("TOPLEFT", frame, "TOPRIGHT", 0, 0)
            tex:SetPoint("BOTTOMLEFT", frame, "BOTTOMRIGHT", 0, 0)
        elseif corners == "inset" and not partial then
            tex:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -size("TOP"))
            tex:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, size("BOTTOM"))
        else
            tex:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
            tex:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
        end
        tex:SetWidth(size("RIGHT"))
    end

    local st = {
        frame = frame,
        alpha = (opts.alpha ~= nil) and opts.alpha or 1,
        getAlpha = opts.getAlpha,
        sideAlphas = opts.sideAlphas,
        themed = opts.color == nil,
    }
    if opts.color then
        st.r = opts.color[1] or 0
        st.g = opts.color[2] or 0
        st.b = opts.color[3] or 0
        if opts.color[4] ~= nil and opts.alpha == nil then
            st.alpha = opts.color[4]
        end
    end
    borderState[border] = st
    if st.themed then
        themedBorders[border] = true
        EnsureThemeSubscription()
    end
    border:Refresh()
    return border
end

-- Solid background texture. Palette colors are static, so no subscription.
--
-- opts:
--   color     "solid" (default, GetBackgroundSolidColor) | "window"
--             (GetBackgroundColor) | "collapsible" (GetCollapsibleBgColor)
--             | {r,g,b[,a]} literal
--   alpha     overrides the palette alpha (popup menus use 0.98)
--   inset     0 for SetAllPoints (default), n to inset by the border thickness
--   sublevel  default Controls.SUBLEVEL_BG
function Controls.AddBackground(frame, opts)
    opts = opts or {}
    local sublevel = (opts.sublevel ~= nil) and opts.sublevel or Controls.SUBLEVEL_BG
    local bg = frame:CreateTexture(nil, "BACKGROUND", nil, sublevel)
    local inset = opts.inset or 0
    if inset == 0 then
        bg:SetAllPoints()
    else
        bg:SetPoint("TOPLEFT", frame, "TOPLEFT", inset, -inset)
        bg:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -inset, inset)
    end
    local color = opts.color or "solid"
    local r, g, b, a
    if type(color) == "table" then
        r, g, b, a = color[1] or 0, color[2] or 0, color[3] or 0, color[4]
    else
        local theme = GetTheme()
        if theme then
            if color == "window" then
                r, g, b, a = theme:GetBackgroundColor()
            elseif color == "collapsible" then
                r, g, b, a = theme:GetCollapsibleBgColor()
            else
                r, g, b, a = theme:GetBackgroundSolidColor()
            end
        end
    end
    if opts.alpha ~= nil then a = opts.alpha end
    bg:SetColorTexture(r or 0, g or 0, b or 0, (a == nil) and 1 or a)
    return bg
end

-- Accent-tinted fill for hover, emphasis, and selected states. Created hidden
-- unless opts.shown; callers toggle it with Show/Hide from their own handlers
-- (which usually do more than the fill: label inversion, arrow tint). Retints
-- on accent change even while hidden, which is what let the old alpha-0 idiom
-- retire.
--
-- opts: alpha (default ALPHA_HOVER), inset, sublevel (default SUBLEVEL_FILL),
--       shown (default false)
function Controls.AddHoverFill(frame, opts)
    opts = opts or {}
    local sublevel = (opts.sublevel ~= nil) and opts.sublevel or Controls.SUBLEVEL_FILL
    local fill = frame:CreateTexture(nil, "BACKGROUND", nil, sublevel)
    local inset = opts.inset or 0
    if inset == 0 then
        fill:SetAllPoints()
    else
        fill:SetPoint("TOPLEFT", frame, "TOPLEFT", inset, -inset)
        fill:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -inset, inset)
    end
    local alpha = (opts.alpha ~= nil) and opts.alpha or Controls.ALPHA_HOVER
    local r, g, b = 1, 1, 1
    local theme = GetTheme()
    if theme then
        r, g, b = theme:GetAccentColor()
    end
    fill:SetColorTexture(r, g, b, alpha)
    themedFills[fill] = alpha
    EnsureThemeSubscription()
    if not opts.shown then
        fill:Hide()
    end
    return fill
end

-- Change a hover fill's alpha (hover 0.08 vs selected 0.12 on one texture).
-- Keeps the stored alpha in sync so the next accent change repaints correctly.
function Controls.SetFillTint(fill, alpha)
    if not fill then return end
    if themedFills[fill] ~= nil then
        themedFills[fill] = alpha
    end
    local r, g, b = 1, 1, 1
    local theme = GetTheme()
    if theme then
        r, g, b = theme:GetAccentColor()
    end
    fill:SetColorTexture(r, g, b, alpha)
end
