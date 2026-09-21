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

-- The background z-stack (SUBLEVEL_BG, SUBLEVEL_FILL, SUBLEVEL_HOVER) and the
-- house alphas (ALPHA_HOVER, ALPHA_EMPHASIS, ALPHA_SELECTED,
-- BORDER_ALPHA_NORMAL, BORDER_ALPHA_FOCUS) are pushed onto Controls by
-- Skin.SetActive from the active skin's metrics. The three sublevels are
-- load-bearing: base fill below, emphasis/secondary fill above it, hover fill
-- on top.

-- Layout and style numbers for controls come from the active skin.
function Controls.Metrics()
    return addon.UI.Skin.Metrics()
end

-- The role a settings row's own name draws in. A skin that wants the row
-- names styled apart from the rest of its label text names one in
-- metrics.rowLabelFontRole; the rest keep the label role they always had.
-- Every row label resolves this, the row chrome's and the measure that sizes
-- a cluster against it, so a style put on the role reaches the whole page.
function Controls.RowLabelFontRole()
    local m = Controls.Metrics()
    return (m and m.rowLabelFontRole) or "label"
end

-- The ON and OFF on a toggle's pill, wherever one is drawn: a settings row's
-- indicator, the compact pill in a selector row, the Features page's, and the
-- pills a renderer builds itself. A skin with a toggle font role names the
-- face, the size and the style there. size is the fallback's, for a skin that
-- names no such role.
--
-- lit is the state with the accent fill behind it, where the text is black. An
-- outline is black too, so there it thickens the glyph rather than drawing the
-- rim it gives the dim text of an unlit pill. The lit pill takes the role's
-- face and size and drops its style, so a caller applies this on every state
-- change, not once at creation.
function Controls.ApplyToggleFont(fs, lit, size)
    if not fs or not fs.SetFont then return end
    local theme = GetTheme()
    if not theme then
        fs:SetFont("Fonts\\FRIZQT__.TTF", size or 11, "")
        return
    end
    if theme._fontRoles and theme._fontRoles.toggle then
        theme:ApplyFont(fs, "toggle", nil, lit and "NONE" or nil)
    else
        fs:SetFont(theme:GetFont("BUTTON"), size or 11, "")
    end
end

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

-- Put a texture the caller built itself on the shared accent subscription, and
-- paint it now. For accent-tinted chrome that is not a hover fill and so has no
-- reason to come from AddHoverFill: a scroll thumb, a rule, a separator. The
-- registry is weak-keyed, so a caller never has to unregister.
function Controls.RegisterThemedFill(fill, alpha)
    if not fill then return end
    alpha = (alpha ~= nil) and alpha or Controls.ALPHA_HOVER
    themedFills[fill] = alpha
    local r, g, b = 1, 1, 1
    local theme = GetTheme()
    if theme then
        r, g, b = theme:GetAccentColor()
    end
    fill:SetColorTexture(r, g, b, alpha)
    EnsureThemeSubscription()
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

--------------------------------------------------------------------------------
-- Shared row chrome
--------------------------------------------------------------------------------

-- Row-height math shared by every settings row that carries a description.
local MAX_ROW_HEIGHT = 200        -- Cap to prevent excessively tall rows
local LABEL_LINE_HEIGHT = 16      -- Approximate label height
local DESC_PADDING_TOP = 2        -- Space between label and description
local DESC_PADDING_BOTTOM = 36    -- Space below description to border

-- The draw-override dispatch every row factory runs first: when the active
-- skin registered a replacement for the control, its frame is returned and
-- the stock drawing is skipped. See ui/v2/Skin.lua for the override contract.
function Controls.SkinOverride(controlName, options)
    local Skin = addon.UI.Skin
    local fn = Skin and Skin.GetOverride and Skin.GetOverride(controlName)
    if fn then
        return fn(options)
    end
    return nil
end

-- Reapplies every cluster anchor against the row's current height. Called by
-- the chrome measure after a height change, so clusters stay centered in the
-- top band while the description extends the row downward.
local function ApplyClusterAnchors(row)
    local anchors = row._clusterAnchors
    if not anchors then return end
    local h = row:GetHeight() or 0
    for _, a in ipairs(anchors) do
        local yOff = 0
        if h > a.band then yOff = (h - a.band) / 2 end
        a.frame:SetPoint(a.point, row, a.point, a.x, yOff + a.y)
    end
end

-- Anchors a control cluster centered in the row's top band, so the cluster
-- stays level with the label instead of floating mid-description. The anchor
-- is reapplied whenever the chrome measure changes the row height.
--
-- opts: point (default "RIGHT"), x (default -rowPadding), y (extra offset,
--       default 0), band (default the row's base height from AddRowChrome)
function Controls.AnchorCluster(row, frame, opts)
    opts = opts or {}
    local m = Controls.Metrics()
    row._clusterAnchors = row._clusterAnchors or {}
    table.insert(row._clusterAnchors, {
        frame = frame,
        point = opts.point or "RIGHT",
        x = (opts.x ~= nil) and opts.x or -m.rowPadding,
        y = opts.y or 0,
        band = opts.band or row._clusterBand or m.rowHeight,
    })
    ApplyClusterAnchors(row)
end

-- The width-driven layout path: the caller passes the definite row width, the
-- label anchors at the top so growth extends downward only, the description
-- wraps against an explicit width, and the row height is set before the
-- function returns. row._measureDesc re-runs the measure (font-load edge);
-- it may shrink as well as grow and reapplies the cluster anchors.
local function AddRowChromeV2(row, opts)
    local theme = GetTheme()
    local m = Controls.Metrics()
    local hasDesc = opts.description and opts.description ~= ""
    local padLeft = opts.padLeft or m.rowPadding
    local baseHeight = opts.baseHeight or m.rowHeight
    row._clusterBand = opts.band or baseHeight

    local labelFS = row:CreateFontString(nil, "OVERLAY")
    theme:ApplyFont(labelFS, Controls.RowLabelFontRole(), opts.labelFontSize)
    labelFS:SetText(opts.label)
    labelFS:SetTextColor(theme:GetAccentColor())
    row._label = labelFS

    if not hasDesc then
        labelFS:SetPoint("LEFT", row, "LEFT", padLeft, 0)
        row:SetHeight(baseHeight)
        return labelFS, nil
    end

    labelFS:SetPoint("TOPLEFT", row, "TOPLEFT", padLeft, -m.labelTopPad)

    local controlReserve = opts.controlReserve or 0
    local descTop = m.labelTopPad + m.labelLineHeight + m.descGap
    local descFS = row:CreateFontString(nil, "OVERLAY")
    theme:ApplyFont(descFS, "desc", opts.descFontSize)
    descFS:SetPoint("TOPLEFT", row, "TOPLEFT", padLeft, -descTop)
    descFS:SetText(opts.description)
    local dim = opts.dimColor
    if dim then
        descFS:SetTextColor(dim[1], dim[2], dim[3], 1)
    end
    descFS:SetJustifyH("LEFT")
    descFS:SetWordWrap(true)
    row._description = descFS

    local function Measure()
        local wrapWidth = opts.rowWidth - padLeft - controlReserve
        if wrapWidth <= 0 then return false end
        descFS:SetWidth(wrapWidth)
        local textHeight = descFS:GetStringHeight() or 0
        local required = descTop + textHeight + m.descPadBottom
        local newHeight = math.min(math.max(baseHeight, required), m.maxRowHeight)
        local current = row:GetHeight() or 0
        if math.abs(newHeight - current) > 0.5 then
            row:SetHeight(newHeight)
            ApplyClusterAnchors(row)
            if row._onHeightChanged then
                row._onHeightChanged(newHeight - current)
            end
        end
        return true
    end
    row._measureDesc = Measure
    Measure()
    return labelFS, descFS
end

-- Label, description, and height measurement for a settings row. Writes
-- row._label, row._description, and row._measureDesc onto the row and calls
-- row._onHeightChanged on a height change; SettingsBuilder, Navigation, and
-- the search jump all read those fields, so they stay on the frame. Returns
-- the label and description FontStrings.
--
-- Two contracts share the name. With opts.rowWidth the v2 path above runs:
--   rowWidth        the definite row width (required for the v2 path)
--   controlReserve  width kept clear of the description for the control
--                   cluster, one number for both the wrap and the anchor
--   baseHeight      minimum row height (default metrics rowHeight)
--   band            cluster band for AnchorCluster (default baseHeight)
--   label, labelFontSize, padLeft, description, descFontSize, dimColor as below
--
-- Without rowWidth the legacy path runs, deferred measure and all; it phases
-- out as the remaining row controls convert:
--   label          label text
--   labelFontSize  default 13
--   labelYOffset   label y offset (default 6 with a description, else 0)
--   padLeft        label x inset from the row's left edge (default 12)
--   description    description text; nil or "" builds the label alone
--   descFontSize   default 11
--   padAbove       label-to-description gap, also counted in the height math
--                  (default DESC_PADDING_TOP; emphasized rows pass 4)
--   reserve        width kept free right of the description for the control
--                  cluster: the description's RIGHT anchor offset. nil skips
--                  the RIGHT anchor for callers that size the text in the
--                  measure pass alone
--   measureReserve total width subtracted from the row width when measuring
--                  the wrap width (default reserve + padLeft)
--   dimColor       {r,g,b} for the description text
function Controls.AddRowChrome(row, opts)
    if opts.rowWidth then
        return AddRowChromeV2(row, opts)
    end
    local theme = GetTheme()
    local hasDesc = opts.description and opts.description ~= ""
    local padLeft = opts.padLeft or 12

    local labelFS = row:CreateFontString(nil, "OVERLAY")
    theme:ApplyFont(labelFS, Controls.RowLabelFontRole(), opts.labelFontSize or 13)
    local labelY = opts.labelYOffset
    if labelY == nil then labelY = hasDesc and 6 or 0 end
    labelFS:SetPoint("LEFT", row, "LEFT", padLeft, labelY)
    labelFS:SetText(opts.label)
    labelFS:SetTextColor(theme:GetAccentColor())
    row._label = labelFS

    if not hasDesc then
        return labelFS, nil
    end

    local padAbove = opts.padAbove or DESC_PADDING_TOP
    local descFS = row:CreateFontString(nil, "OVERLAY")
    descFS:SetFont(theme:GetFont("VALUE"), opts.descFontSize or 11, "")
    descFS:SetPoint("TOPLEFT", labelFS, "BOTTOMLEFT", 0, -padAbove)
    if opts.reserve then
        descFS:SetPoint("RIGHT", row, "RIGHT", -opts.reserve, 0)
    end
    descFS:SetText(opts.description)
    local dim = opts.dimColor
    if dim then
        descFS:SetTextColor(dim[1], dim[2], dim[3], 1)
    end
    descFS:SetJustifyH("LEFT")
    descFS:SetWordWrap(true)
    row._description = descFS

    local measureReserve = opts.measureReserve or ((opts.reserve or 0) + padLeft)

    -- Deferred height measurement after text layout completes
    local function MeasureAndAdjustHeight()
        if not row or not descFS then return false end

        -- Get the row's effective width (try row, then parent)
        local rowWidth = row:GetWidth()
        if rowWidth == 0 and row:GetParent() then
            rowWidth = row:GetParent():GetWidth() or 0
        end
        if rowWidth == 0 then return false end

        local descAvailableWidth = rowWidth - measureReserve
        if descAvailableWidth <= 0 then return false end

        -- Explicit width so GetStringHeight returns the wrapped height
        descFS:SetWidth(descAvailableWidth)

        local textHeight = descFS:GetStringHeight() or 0
        local requiredHeight = LABEL_LINE_HEIGHT + padAbove + textHeight + DESC_PADDING_BOTTOM
        requiredHeight = math.min(requiredHeight, MAX_ROW_HEIGHT)

        local currentHeight = row:GetHeight()
        if requiredHeight > currentHeight then
            row:SetHeight(requiredHeight)
            if row._onHeightChanged then
                row._onHeightChanged(requiredHeight - currentHeight)
            end
        end
        return true
    end
    row._measureDesc = MeasureAndAdjustHeight

    -- Try immediate measurement, fall back to deferred
    if not MeasureAndAdjustHeight() then
        C_Timer.After(0.1, MeasureAndAdjustHeight)
    end
    return labelFS, descFS
end

-- Arrow-button chrome for cyclers: the Button, its transparent accent fill,
-- and the centred glyph, plus the shared hover tint. The caller anchors the
-- button and owns the click handler; key-list wrap and numeric clamp are
-- different algorithms and stay with their files.
--
-- The arrowButton role decides the draw. Flat is the draw below. Any other
-- kind draws the role's art per state through Chrome.Backdrop and takes the
-- arrow from the role's glyphs[direction], colored by its glyphColors; the
-- separator is left out, since the art has its own rim. On that path _bg is
-- inert and _text answers SetTextColor the way the callers use it: a full
-- alpha is the enabled arrow, a reduced one the locked or disabled arrow.
--
-- opts:
--   width, height  button size
--   glyph          the arrow character of the flat draw
--   direction      "prev" or "next", the key into the role's glyphs
--   fontSize       default 14
--   noHover        skip the hover handlers (the sliders install their own,
--                  gated on their sync lock)
--   separator      "LEFT" or "RIGHT": a 1px accent rule on that side of the
--                  button, drawn on parent and returned second
local INERT_FILL = { SetColorTexture = function() end, SetShown = function() end, Hide = function() end, Show = function() end }

local function CreateArtArrowButton(arrow, spec, opts)
    local Chrome = addon.UI.Chrome
    local backdrop = (not opts.noHover) and Chrome.Backdrop("arrowButton", arrow) or nil
    local art = spec.glyphs and spec.glyphs[opts.direction or "next"]
    local glyph = Chrome.Glyph(arrow, art or opts.glyph, { fontSize = opts.fontSize or 14 })
    glyph.region:SetPoint("CENTER", 0, 0)
    local offset = spec.pressedOffset

    local function color(state)
        local colors = spec.glyphColors or {}
        return Chrome.Color(colors[state] or colors.normal or "accent")
    end
    local dimmed = false
    local function paint()
        local state = dimmed and "disabled" or (backdrop and backdrop:State()) or "normal"
        glyph:SetColor(color(state))
        local down = offset and state == "pressed"
        glyph.region:SetPoint("CENTER", down and offset[1] or 0, down and offset[2] or 0)
    end
    if backdrop then
        local paintArt = backdrop.paint
        backdrop.paint = function()
            paintArt()
            paint()
        end
        arrow:SetScript("OnEnter", function() backdrop:SetHover(true) end)
        arrow:SetScript("OnLeave", function() backdrop:SetHover(false) end)
        arrow:HookScript("OnMouseDown", function() if not dimmed then backdrop:SetPressed(true) end end)
        arrow:HookScript("OnMouseUp", function() backdrop:SetPressed(false) end)
        arrow:HookScript("OnHide", function() backdrop:SetPressed(false) end)
    end
    arrow._backdrop = backdrop
    arrow._bg = INERT_FILL
    arrow._text = {
        SetTextColor = function(_, _, _, _, a)
            dimmed = (a or 1) < 1
            if backdrop then backdrop:SetDisabled(dimmed) else paint() end
        end,
    }
    paint()
end

function Controls.CreateArrowButton(parent, opts)
    local theme = GetTheme()
    local ar, ag, ab = theme:GetAccentColor()

    local arrow = CreateFrame("Button", nil, parent)
    arrow:SetSize(opts.width, opts.height)
    arrow:EnableMouse(true)
    arrow:RegisterForClicks("AnyUp")

    local spec = addon.UI.Chrome.Spec("arrowButton")
    if spec.kind ~= "flat" then
        CreateArtArrowButton(arrow, spec, opts)
        return arrow, nil
    end

    local bg = arrow:CreateTexture(nil, "BACKGROUND", nil, -6)
    bg:SetAllPoints()
    bg:SetColorTexture(ar, ag, ab, 0)
    arrow._bg = bg

    local text = arrow:CreateFontString(nil, "OVERLAY")
    text:SetFont(theme:GetFont("BUTTON"), opts.fontSize or 14, "")
    text:SetPoint("CENTER", 0, 0)
    text:SetText(opts.glyph)
    text:SetTextColor(ar, ag, ab, 1)
    arrow._text = text

    if not opts.noHover then
        arrow:SetScript("OnEnter", function(btn)
            local r, g, b = theme:GetAccentColor()
            btn._bg:SetColorTexture(r, g, b, 0.2)
        end)
        arrow:SetScript("OnLeave", function(btn)
            btn._bg:SetColorTexture(0, 0, 0, 0)
        end)
    end

    local sep
    if opts.separator then
        sep = parent:CreateTexture(nil, "BORDER", nil, 0)
        if opts.separator == "RIGHT" then
            sep:SetPoint("TOPLEFT", arrow, "TOPRIGHT", 0, 0)
            sep:SetPoint("BOTTOMLEFT", arrow, "BOTTOMRIGHT", 0, 0)
        else
            sep:SetPoint("TOPRIGHT", arrow, "TOPLEFT", 0, 0)
            sep:SetPoint("BOTTOMRIGHT", arrow, "BOTTOMLEFT", 0, 0)
        end
        sep:SetWidth(1)
        sep:SetColorTexture(ar, ag, ab, 0.4)
    end
    return arrow, sep
end

-- The shell of a selector field: what is drawn around the arrows and the
-- value. The field role decides it. Flat is a border and a background around
-- the whole field. Any other kind draws the role's art per state through
-- Chrome.Backdrop, on the value button alone when the role says spans =
-- "value" (the arrows are then buttons of their own beside it), and the
-- border and background it returns are inert.
--
-- Returns border, background, backdrop (nil when flat).
local INERT_BORDER_MT = { __index = {
    Refresh = function() end, SetShown = function() end, SetAlpha = function() end, Destroy = function() end,
} }

function Controls.AddFieldChrome(field, valueBtn, opts)
    opts = opts or {}
    local Chrome = addon.UI.Chrome
    local spec = Chrome.Spec("field")
    if spec.kind == "flat" then
        local border = Controls.CreateBorder(field, { alpha = opts.borderAlpha })
        local bg = Controls.AddBackground(field, { inset = 1, sublevel = Controls.SUBLEVEL_FILL })
        return border, bg, nil
    end
    local target = (spec.spans == "value" and valueBtn) or field
    local backdrop = Chrome.Backdrop("field", target)
    if valueBtn then
        valueBtn:HookScript("OnEnter", function() backdrop:SetHover(true) end)
        valueBtn:HookScript("OnLeave", function() backdrop:SetHover(false) end)
        valueBtn:HookScript("OnMouseDown", function() backdrop:SetPressed(true) end)
        valueBtn:HookScript("OnMouseUp", function() backdrop:SetPressed(false) end)
    end
    return setmetatable({}, INERT_BORDER_MT), INERT_FILL, backdrop
end

-- The open indicator on a field's value button. A role with no glyphs.open
-- keeps the caller's character. Art from the role is centered on the value
-- button's bottom edge or pinned right, by the role's indicator table, and
-- indicator.show = "hover" keeps it hidden until the cursor is over the
-- field. role is "field" unless the caller names another (the header
-- dropdown passes its own). The handle answers SetTextColor the way the callers use it: a full
-- alpha is the hover color, a reduced one the resting color.
function Controls.AddFieldIndicator(valueBtn, fontString, role)
    local Chrome = addon.UI.Chrome
    local spec = Chrome.Spec(role or "field")
    local art = spec.glyphs and spec.glyphs.open
    if spec.kind == "flat" or not art then return fontString end
    fontString:Hide()
    local where = spec.indicator or {}
    local glyph = Chrome.Glyph(valueBtn, art)
    glyph.region:SetPoint(where.point or "RIGHT", valueBtn, where.point or "RIGHT", where.x or -8, where.y or 0)
    local colors = spec.glyphColors or {}
    local function paint(hover)
        glyph:SetColor(Chrome.Color(colors[hover and "hover" or "normal"] or colors.normal or "accent"))
        glyph:SetShown(hover or where.show ~= "hover")
    end
    paint(false)
    return { SetTextColor = function(_, _, _, _, a) paint((a or 1) >= 1) end }
end

-- The typed value box beside a slider's track. The input role decides the
-- draw. Flat is a bare EditBox with an accent border around the background
-- color, brighter while the box has focus. A template kind builds the box on
-- the skin's template and keeps its Left, Middle and Right art on the
-- inputField opacity piece; Blizzard's own input box is the one its options
-- search bar is drawn in. That art starts 5 units left of the EditBox and is
-- 20 tall, so the text centers in the art and _artLeft tells the caller how
-- far to stand the box off its neighbour.
--
-- opts: width, height, fontSize (default 12), maxLetters (default 10),
--       inset (flat border's outset from the box, default 2),
--       textInset (flat text inset, default 4)
--
-- Returns the EditBox. box._artLeft is the art's reach past the left edge;
-- box._setFocusLook(focused) repaints the flat border and is inert otherwise.
-- opts.justifyH (default CENTER) and opts.textInset reach both kinds: the
-- dialog's name prompt reads from the left with a margin, a slider's value
-- box sits centered in its art.
-- How far the input role's art reaches past the box's left edge, for a caller
-- that sizes its cluster before it builds the box.
function Controls.ValueInputReach()
    return addon.UI.Chrome.Spec("input").kind == "template" and 5 or 0
end

function Controls.CreateValueInput(parent, opts)
    local theme = GetTheme()
    local spec = addon.UI.Chrome.Spec("input")
    local art = spec.kind == "template"

    local box = addon.UI.Chrome.CreateFrame(spec, "EditBox", nil, parent)
    box:SetSize(opts.width, art and 20 or opts.height)
    box:SetAutoFocus(false)
    box:SetNumeric(false)  -- Allow decimals
    box:SetMaxLetters(opts.maxLetters or 10)
    box:EnableMouse(true)
    box:SetFont(theme:GetFont("VALUE"), opts.fontSize or 12, "")
    box:SetTextColor(1, 1, 1, 1)
    box:SetJustifyH(opts.justifyH or "CENTER")

    if art then
        for _, key in ipairs({ "Left", "Middle", "Right" }) do
            if box[key] then addon.UI.Chrome.ApplyOpacity("inputField", box[key]) end
        end
        box:SetTextInsets(opts.textInset or 0, 5, 0, 0)
        box._artLeft = Controls.ValueInputReach()
        box._setFocusLook = function() end
        return box
    end

    box:SetTextInsets(opts.textInset or 4, opts.textInset or 4, 0, 0)

    local inset = opts.inset or 2
    local border = Controls.CreateBorder(box, {
        corners = "outset", thickness = inset, layer = "BACKGROUND", sublevel = 1, alpha = 0.6,
    })
    local bgR, bgG, bgB, bgA = theme:GetBackgroundSolidColor()
    local bg = box:CreateTexture(nil, "BACKGROUND", nil, 0)
    bg:SetPoint("TOPLEFT", -inset, inset)
    bg:SetPoint("BOTTOMRIGHT", inset, -inset)
    bg:SetColorTexture(bgR, bgG, bgB, bgA)
    box._artLeft = 0
    box._setFocusLook = function(focused) border:SetAlpha(focused and 1 or 0.6) end
    return box
end

--------------------------------------------------------------------------------
-- Click-outside dismissal
--------------------------------------------------------------------------------

-- The invisible full-screen click-catcher behind every floating list and
-- flyout: any click that misses the floating frame lands here and runs
-- onClose. Returns the catcher Button hidden; the owner shows it one frame
-- level below the floating frame on open and hides it again on close.
function Controls.AttachDismissOnClickOutside(onClose)
    local closeListener = CreateFrame("Button", nil, UIParent)
    closeListener:SetFrameStrata("FULLSCREEN")
    closeListener:SetFrameLevel(99)
    closeListener:SetAllPoints(UIParent)
    closeListener:EnableMouse(true)
    closeListener:RegisterForClicks("AnyUp", "AnyDown")
    closeListener:SetScript("OnClick", onClose)
    closeListener:Hide()
    return closeListener
end

--------------------------------------------------------------------------------
-- Picker dialog shell
--------------------------------------------------------------------------------

-- The modal dialog shell shared by the font, bar texture, bar border, and
-- icon pickers: a movable FULLSCREEN_DIALOG singleton, title, close button,
-- left tab column with separator, scroll frame with scroll child, ESC and
-- click-outside dismissal, and one theme subscription that keeps every part
-- on the current accent. The picker keeps its item lists, previews, Show and
-- Close globals, and defines frame:PopulateContent() after this returns.
--
-- Every part comes from the active skin rather than from numbers here: the
-- surface is the picker role, the tab column the navRow role, the X the
-- closeButton role, and the bar beside the scroll frame is
-- Controls.CreateScrollBar. On the forever skin that makes the dialog a
-- Blizzard panel with the client's own border, title plate and scrollbar,
-- and each tab a list row; on tui every one of those roles is the
-- framework's flat draw, which is the look the pickers shipped with.
--
-- opts:
--   name          global frame name; also the theme subscription key, and the
--                  scroll frame is named with Frame swapped for ScrollFrame
--   height         the room the dialog needs inside its art
--   contentWidth   the room the picker's grid needs inside the scroll frame.
--                  The shell adds the tab column, the gap beside it, the
--                  scrollbar gutter and its own padding to get the dialog's
--                  width, and the scroll child is this wide; a picker that
--                  adds its own number for that chrome sizes the dialog
--                  short, and the scroll frame clips its last column
--   title          title text
--   onClose        the picker's close routine, wired to the X, ESC, and the
--                  click-outside poll
--   onHide         extra OnHide work after the poll stops (animated previews)
--   tabs           default tab list of { key, label }; a Show that varies the
--                  list writes frame._workingTabs before calling UpdateTabs
--   getSelectedTab function() -> the selected tab key
--   onTabSelected  function(key) -> record the selection; the shell repaints
--                  the tabs, calls frame:PopulateContent(), and plays the
--                  click sound
--   padding        default 12; titleHeight 30; tabWidth 90; tabHeight 32
--
-- Returns the frame carrying Title, CloseButton, TabContainer, TabButtons,
-- UpdateTabs, UpdateTabVisuals, SetTitleInset, ScrollFrame, _scrollBar,
-- _scrollInsetRight, Content, and the _accentR/_accentG/_accentB fields the
-- populate passes read.
function Controls.CreatePickerShell(opts)
    local theme = GetTheme()
    local Chrome = addon.UI.Chrome
    local accentR, accentG, accentB = theme:GetAccentColor()
    local padding = opts.padding or 12
    local titleHeight = opts.titleHeight or 30
    local tabWidth = opts.tabWidth or 90
    local tabHeight = opts.tabHeight or 32
    -- The gap between the tab column and the scroll frame, and the gutter the
    -- scrollbar stands in on the far side of it.
    local tabGap, scrollGutter = 12, 20
    local onClose = opts.onClose
    local getSelectedTab = opts.getSelectedTab
    local onTabSelected = opts.onTabSelected

    -- The dialog's surface, the way the picker role says. A template kind
    -- builds the frame on the skin's panel template, whose border, title
    -- plate and close button come with it; flat is the framework's fill and
    -- four-edge border, the look the pickers shipped with.
    local spec = Chrome.Spec("picker")
    local frame = Chrome.CreateFrame(spec, "Frame", opts.name, UIParent)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetFrameLevel(100)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)

    -- How far the panes stand off the frame's edge. Art that draws into the
    -- rect keeps them at the skin's windowInset; a flat border is its own
    -- width and the padding already clears it.
    local edge = 0
    if spec.kind == "template" then
        addon.UI.Window:BuildTemplateParts(frame, spec)
        edge = Controls.Metrics().windowInset or 0
    elseif spec.kind == "nineSlice" then
        frame._bg = Controls.AddBackground(frame, { color = spec.background or "window" })
        frame._chrome = Chrome.NineSlice(frame, spec)
        edge = Controls.Metrics().windowInset or 0
    else
        frame._bg = Controls.AddBackground(frame, { color = spec.background or "window" })
        frame._borders = Controls.CreateBorder(frame, { alpha = 0.8 })
    end
    local pad = padding + edge
    -- The caller's contentWidth and height are the room it needs inside the
    -- dialog, so art that reaches into the rect grows the frame by its own
    -- margin rather than taking that room away: the tab column and the
    -- scroll frame come out the same size under every skin. The width is the
    -- grid's room plus everything the shell keeps beside it, which is the
    -- one place that arithmetic is done.
    local frameWidth = opts.contentWidth + tabWidth + tabGap + scrollGutter + padding * 2 + edge * 2
    local frameHeight = opts.height + edge * 2
    frame:SetSize(frameWidth, frameHeight)
    -- What a picker anchoring a band of its own keeps off the frame's edge,
    -- so its row lines up with the tab column under it.
    frame._padInset = pad

    -- Title: the template's own plate where the frame has one, a string in
    -- the header font otherwise.
    local titleFont = theme:GetFont("HEADER")
    local title
    if frame.SetTitle and frame.GetTitleText and frame.TitleContainer then
        frame:SetTitle(opts.title)
        title = frame:GetTitleText()
    else
        title = frame:CreateFontString(nil, "OVERLAY")
        title:SetFont(titleFont, 14, "")
        title:SetPoint("TOPLEFT", frame, "TOPLEFT", padding, -10)
        title:SetText(opts.title)
        title:SetTextColor(1, 1, 1, 1)
    end
    frame.Title = title

    -- The X, from the closeButton role: a window kind adopts the one the
    -- template already built and keeps its corner, so only the rest is placed.
    local closeBtn, closeSpec = Controls:CreateCloseButton({ parent = frame, onClick = onClose })
    if not (closeSpec and closeSpec.kind == "window") then
        closeBtn:ClearAllPoints()
        closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -6, -6)
    end
    frame.CloseButton = closeBtn

    -- Tab container (left side)
    local tabContainer = CreateFrame("Frame", nil, frame)
    tabContainer:SetSize(tabWidth, frameHeight - titleHeight - pad - padding)
    tabContainer:SetPoint("TOPLEFT", frame, "TOPLEFT", pad, -(titleHeight + 4))
    frame.TabContainer = tabContainer

    -- A picker with a header band under the title (the global-token buttons)
    -- calls this with a larger inset; the tab column and the scroll frame
    -- anchored to it move down together.
    frame._titleInset = titleHeight
    function frame:SetTitleInset(px)
        px = px or titleHeight
        if self._titleInset == px then return end
        self._titleInset = px
        tabContainer:SetSize(tabWidth, frameHeight - px - pad - padding)
        tabContainer:ClearAllPoints()
        tabContainer:SetPoint("TOPLEFT", self, "TOPLEFT", pad, -(px + 4))
    end

    -- Vertical separator between tabs and content
    local tabSep = frame:CreateTexture(nil, "BORDER", nil, 0)
    tabSep:SetWidth(1)
    tabSep:SetPoint("TOPLEFT", tabContainer, "TOPRIGHT", 4, 0)
    tabSep:SetPoint("BOTTOMLEFT", tabContainer, "BOTTOMRIGHT", 4, 0)
    tabSep:SetColorTexture(accentR, accentG, accentB, 0.4)
    frame._tabSep = tabSep

    -- Tab buttons (managed pool, rebuilt on each Show via UpdateTabs)
    frame.TabButtons = {}
    frame._tabLabelFont = theme:GetFont("LABEL")

    function frame:UpdateTabs()
        local tabs = self._workingTabs or opts.tabs
        local tc = self.TabContainer
        local lf = self._tabLabelFont

        for i, tabData in ipairs(tabs) do
            local tabBtn = self.TabButtons[i]
            if not tabBtn then
                tabBtn = CreateFrame("Button", nil, tc)
                tabBtn:SetSize(tabWidth, tabHeight)
                tabBtn:EnableMouse(true)
                tabBtn:RegisterForClicks("AnyUp")

                local tabLabel = tabBtn:CreateFontString(nil, "OVERLAY")
                tabLabel:SetFont(lf, 11, "")
                tabLabel:SetPoint("CENTER", tabBtn, "CENTER", 2, 0)
                tabBtn._label = tabLabel

                -- The column is a list of rows, not a row of tabs, so it
                -- takes the navRow role: the skin's own row art per state,
                -- and the label colored by the same state walk.
                tabBtn._backdrop = Chrome.Backdrop("navRow", tabBtn, {
                    variant = "parent", label = tabLabel,
                })

                -- A skin whose selected state is art of its own says so
                -- already; the accent bar is for the flat draw, whose states
                -- are two fills of the same color.
                local indicator = tabBtn:CreateTexture(nil, "OVERLAY", nil, 1)
                indicator:SetSize(2, tabHeight)
                indicator:SetPoint("LEFT", tabBtn, "LEFT", 0, 0)
                indicator:SetColorTexture(frame._accentR, frame._accentG, frame._accentB, 1)
                indicator:Hide()
                tabBtn._indicator = indicator
                tabBtn._indicatorUsed = not Chrome.Spec("navRow").selected

                tabBtn:SetScript("OnEnter", function(btn)
                    btn._backdrop:SetHover(true)
                end)
                tabBtn:SetScript("OnLeave", function(btn)
                    btn._backdrop:SetHover(false)
                end)
                tabBtn:SetScript("OnClick", function(btn)
                    if getSelectedTab() ~= btn._key then
                        onTabSelected(btn._key)
                        frame:UpdateTabVisuals()
                        frame:PopulateContent()
                        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
                    end
                end)

                self.TabButtons[i] = tabBtn
            end

            tabBtn._key = tabData.key
            tabBtn._label:SetText(tabData.label)
            tabBtn:ClearAllPoints()
            tabBtn:SetPoint("TOPLEFT", tc, "TOPLEFT", 0, -((i - 1) * tabHeight))
            tabBtn:Show()
        end

        -- Hide extra buttons from previous Show
        for i = #tabs + 1, #self.TabButtons do
            self.TabButtons[i]:Hide()
        end
    end

    function frame:UpdateTabVisuals()
        for _, tabBtn in ipairs(self.TabButtons) do
            local isSelected = (getSelectedTab() == tabBtn._key)
            tabBtn._backdrop:SetSelected(isSelected)
            tabBtn._indicator:SetShown(isSelected and tabBtn._indicatorUsed)
        end
    end

    -- Content area (scroll frame, right of tabs)
    local scrollFrame = CreateFrame("ScrollFrame", opts.name:gsub("Frame$", "ScrollFrame"), frame)
    scrollFrame:SetPoint("TOPLEFT", tabContainer, "TOPRIGHT", tabGap, 0)
    scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -(pad + scrollGutter), pad)
    frame.ScrollFrame = scrollFrame
    -- What a picker that re-anchors the scroll frame's bottom (the bar
    -- border picker's edge row) keeps on its right, so the grid stays inside
    -- it under a skin whose art reaches into the rect.
    frame._scrollInsetRight = pad + scrollGutter

    -- The bar beside it, the way the scrollBar role says. The pickers show
    -- and hide it themselves from the content height they just laid out.
    local scrollBar = Controls.CreateScrollBar({ parent = frame, scrollFrame = scrollFrame })
    if scrollBar then
        local sb = Controls.Metrics().scrollBar
        scrollBar:SetPoint("TOPRIGHT", scrollFrame, "TOPRIGHT", sb.margin + sb.width, 0)
        scrollBar:SetPoint("BOTTOMRIGHT", scrollFrame, "BOTTOMRIGHT", sb.margin + sb.width, 0)
        frame._scrollBar = scrollBar
    end

    -- The factory owns OnScrollRangeChanged in both kinds and leaves the
    -- wheel to the caller.
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local child = self:GetScrollChild()
        local maxScroll = math.max(0, (child and child:GetHeight() or 0) - (self:GetHeight() or 1))
        local target = (self:GetVerticalScroll() or 0) - (delta * 40)
        self:SetVerticalScroll(math.max(0, math.min(maxScroll, target)))
        if frame._scrollBar and frame._scrollBar.Sync then
            frame._scrollBar:Sync()
        end
    end)

    -- Content frame (scroll child)
    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(opts.contentWidth, 100)  -- Height adjusted by the populate pass
    scrollFrame:SetScrollChild(content)
    frame.Content = content

    -- Store accent colors for the populate passes
    frame._accentR = accentR
    frame._accentG = accentG
    frame._accentB = accentB

    -- ESC to close
    addon.EscapeKey.Attach(frame, function()
        onClose()
    end)

    -- Click outside to close
    frame:SetScript("OnShow", function(self)
        self:SetScript("OnUpdate", function(f)
            if not f:IsMouseOver() and IsMouseButtonDown("LeftButton") then
                C_Timer.After(0.05, function()
                    if frame:IsShown() and not frame:IsMouseOver() then
                        onClose()
                    end
                end)
            end
        end)
    end)
    frame:SetScript("OnHide", function(self)
        self:SetScript("OnUpdate", nil)
        if opts.onHide then
            opts.onHide(self)
        end
    end)

    -- One subscription per shell keeps the chrome on the current accent; the
    -- frames are singletons, so the key never needs to be released.
    -- The parts that come from a role retint themselves: Chrome.Backdrop and
    -- Controls.CreateScrollBar each hold their own subscription. What is left
    -- is the shell's own drawing.
    theme:Subscribe(opts.name, function(r, g, b)
        frame._accentR, frame._accentG, frame._accentB = r, g, b
        frame._tabSep:SetColorTexture(r, g, b, 0.4)
        for _, tabBtn in ipairs(frame.TabButtons) do
            tabBtn._indicator:SetColorTexture(r, g, b, 1)
        end
        frame:UpdateTabVisuals()
        if frame:IsShown() and frame.PopulateContent then
            frame:PopulateContent()
        end
    end)

    return frame
end
