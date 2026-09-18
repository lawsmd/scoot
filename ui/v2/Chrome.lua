-- Chrome.lua - chrome descriptors: how each surface of the settings panel is
-- drawn, declared per role by the active skin and resolved here against the
-- running client.
--
-- A skin's chrome table holds one descriptor per role: window, titleBar,
-- closeButton, button, resizeGrip, scrollBar, tab, tabBody, sectionHeader,
-- sectionBody, navRow, navCard, navDivider, dropdown. A descriptor names a
-- kind and what that kind needs:
--   flat       the framework's own draw (CreateBorder, AddBackground,
--              AddHoverFill) with numbers from the skin metrics
--   nineSlice  NineSliceUtil.ApplyLayout on a child frame: layout, textureKit
--   atlas      one atlas per state: normal, hover, selected, disabled, pressed
--   template   a Blizzard frame template supplies the art and part of the
--              method surface: template, joined with the caller's own. On
--              the window role the frame itself is the template, and the
--              descriptor names the portrait and a contentBackground
--   window     the window template supplies this part (titleBar, closeButton)
--   ascii, text, texture   how the title bar presents the product's title
-- Any descriptor may carry fallback (another descriptor), labelColors (a
-- color token per state), font ("role" or "template") and inset.
--
-- Spec(role) resolves a role for this client. A descriptor whose template,
-- layout or atlases the client lacks falls through its fallback chain and, at
-- the end of it, to the flat descriptor in Chrome.FLAT. A skin with no chrome
-- table draws every role flat, which is the look the panel shipped with, so
-- the table is a catalog and never a requirement.
--
--   Chrome.Spec(role)                the resolved descriptor
--   Chrome.Declared(role)            the skin's own descriptor, or nil
--   Chrome.Resolve(spec, flat)       one descriptor's chain, for a sub-descriptor
--                                    or a caller that declines a kind
--   Chrome.Available(spec)           whether this client can draw it
--   Chrome.Invalidate()              forget resolutions; Skin.SetActive calls it
--   Chrome.Color(token)              r, g, b, a for a color token or a literal
--   Chrome.CreateFrame(role, frameType, name, parent, extraTemplates)
--                                    a frame on the role's template, if it has one;
--                                    a resolved descriptor stands in for the role
--   Chrome.NineSlice(frame, spec)    the nine-slice child a nineSlice role draws
--   Chrome.Backdrop(role, frame, opts)
--                                    a state handle drawing a role's backdrop on a
--                                    control's frame (tab, tabBody, sectionHeader,
--                                    sectionBody, navRow, dropdown)
--   Chrome.Dump(push)                one line per role for the skin listing
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.Chrome = addon.UI.Chrome or {}
local Chrome = addon.UI.Chrome

Chrome.ROLES = {
    "window", "titleBar", "closeButton", "button", "resizeGrip", "scrollBar",
    "tab", "tabBody", "sectionHeader", "sectionBody", "navRow", "navCard", "navDivider",
    "dropdown",
}

-- The flat defaults: the panel's own drawing, one per role. A skin that
-- declares nothing for a role gets this, and a declared descriptor the client
-- cannot draw ends here too.
Chrome.FLAT = {
    window = {
        kind = "flat", corners = "outset", background = "window",
        noise = { texture = "NOISE_OVERLAY", size = 2048, alpha = 0.25, blend = "ADD" },
    },
    titleBar      = { kind = "ascii", fontRole = "label" },
    closeButton   = { kind = "flat", glyph = "X" },
    button        = { kind = "flat", labelColors = { normal = "accent", hover = "black", active = "background", disabled = "accent" } },
    resizeGrip    = { kind = "flat" },
    scrollBar     = { kind = "flat" },
    tab           = { kind = "flat", labelColors = { normal = "accent", hover = "accent", selected = "black" } },
    tabBody       = { kind = "flat", fill = { 0, 0, 0, 0.15 } },
    sectionHeader = { kind = "flat", background = "collapsible",
                      glyphs = { expanded = "\226\150\188", collapsed = "\226\150\182" } },
    sectionBody   = { kind = "flat", background = "collapsible" },
    navRow        = {
        kind = "flat",
        parent = { labelColors = { normal = "accent", hover = "primary", selected = "primary", disabled = { token = "dim", alpha = 0.35 } } },
        child  = { labelColors = { normal = "primary", hover = "accent", selected = "accent", disabled = { token = "dim", alpha = 0.35 } } },
    },
    -- Flat navCard is the text parent row navRow draws; flat navDivider is
    -- the one-pixel accent line on the nav's right edge.
    navCard       = { kind = "flat" },
    navDivider    = { kind = "flat" },
    dropdown      = { kind = "flat" },
}

local NINE_SLICE_PIECES = {
    "TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner",
    "TopEdge", "BottomEdge", "LeftEdge", "RightEdge", "Center",
}

local ATLAS_STATES = { "normal", "hover", "selected", "disabled", "pressed", "open", "closed" }

--------------------------------------------------------------------------------
-- Availability
--------------------------------------------------------------------------------

-- Memoized per name. A template the client did not load at startup cannot
-- appear mid-session, so the answer holds until reload.
local templateCache = {}

local function templateExists(name, frameType)
    local cached = templateCache[name]
    if cached ~= nil then return cached end
    local exists
    if C_XMLUtil and C_XMLUtil.GetTemplateInfo then
        local ok, info = pcall(C_XMLUtil.GetTemplateInfo, name)
        exists = ok and info ~= nil
    else
        local ok, probe = pcall(CreateFrame, frameType or "Frame", nil, UIParent, name)
        exists = ok and probe ~= nil
        if exists then probe:Hide() end
    end
    templateCache[name] = exists
    return exists
end

local function atlasExists(name)
    if type(name) ~= "string" then return false end
    if not (C_Texture and C_Texture.GetAtlasInfo) then return false end
    local ok, info = pcall(C_Texture.GetAtlasInfo, name)
    return ok and info ~= nil
end

-- The atlas name a nine-slice piece resolves to under a texture kit.
local function pieceAtlas(pieceLayout, kit)
    local atlas = pieceLayout and pieceLayout.atlas
    if type(atlas) ~= "string" then return nil end
    if kit and atlas:find("%%s") then return string.format(atlas, kit) end
    return atlas
end

function Chrome.Available(spec)
    if type(spec) ~= "table" then return false end
    local kind = spec.kind
    if kind == "template" then
        if type(spec.template) ~= "string" then return false end
        for name in spec.template:gmatch("[^,%s]+") do
            if not templateExists(name, spec.frameType) then return false end
        end
        -- A layout the descriptor swaps in (the no-portrait border) has to exist too
        if spec.layout and not (NineSliceLayouts and type(NineSliceLayouts[spec.layout]) == "table") then
            return false
        end
        return true
    elseif kind == "window" then
        -- The window template's own part: there when the window is a template
        return Chrome.Spec("window").kind == "template"
    elseif kind == "atlas" then
        -- One atlas (a content background, a glow), or one per state
        if spec.atlas then return atlasExists(spec.atlas) end
        local any = false
        for _, state in ipairs(ATLAS_STATES) do
            local name = spec[state]
            if name ~= nil then
                any = true
                if not atlasExists(name) then return false end
            end
        end
        return any
    elseif kind == "nineSlice" then
        if not (NineSliceUtil and NineSliceUtil.ApplyLayout and NineSliceLayouts) then return false end
        local layout = NineSliceLayouts[spec.layout]
        if type(layout) ~= "table" then return false end
        return atlasExists(pieceAtlas(layout.TopLeftCorner, spec.textureKit))
    end
    -- flat, ascii, text, texture: drawn by the framework, always available.
    return true
end

--------------------------------------------------------------------------------
-- Resolution
--------------------------------------------------------------------------------

local resolved = {}

function Chrome.Invalidate()
    for role in pairs(resolved) do resolved[role] = nil end
end

function Chrome.Declared(role)
    local Theme = addon.UI.Theme
    local chrome = Theme and Theme.Chrome
    return chrome and chrome[role] or nil
end

-- The first descriptor in a chain this client can draw, or flat when none
-- can. Spec memoizes it per role; Resolve is the same walk for a descriptor
-- nested inside another (a window's content background, a card's glow) and
-- for a caller that declines the resolved kind and takes its fallback.
function Chrome.Resolve(spec, flat)
    local depth = 0
    while spec and not Chrome.Available(spec) and depth < 8 do
        spec = spec.fallback
        depth = depth + 1
    end
    if not spec or not Chrome.Available(spec) then
        return flat or { kind = "flat" }
    end
    return spec
end

function Chrome.Spec(role)
    local hit = resolved[role]
    if hit then return hit end
    local spec = Chrome.Resolve(Chrome.Declared(role), Chrome.FLAT[role])
    resolved[role] = spec
    return spec
end

--------------------------------------------------------------------------------
-- Colors
--------------------------------------------------------------------------------

-- A token names a palette read, so a descriptor stays a table of names and
-- follows the accent and the palette at draw time. A literal is {r, g, b, a}
-- or {r=, g=, b=, a=}.
function Chrome.Color(token)
    local Theme = addon.UI.Theme
    if type(token) == "table" and token.token then
        local r, g, b, a = Chrome.Color(token.token)
        return r, g, b, (token.alpha ~= nil) and token.alpha or a
    end
    if type(token) == "table" then
        return token[1] or token.r or 0, token[2] or token.g or 0, token[3] or token.b or 0,
            (token[4] ~= nil and token[4]) or (token.a ~= nil and token.a) or 1
    end
    if not Theme then return 1, 1, 1, 1 end
    if token == "primary" then return Theme:GetPrimaryTextColor() end
    if token == "dim" then return Theme:GetDimTextColor() end
    if token == "dimLight" then return Theme:GetDimTextLightColor() end
    if token == "background" then return Theme:GetBackgroundSolidColor() end
    if token == "collapsible" then return Theme:GetCollapsibleBgColor() end
    if token == "black" then return 0, 0, 0, 1 end
    if token == "white" then return 1, 1, 1, 1 end
    return Theme:GetAccentColor()
end

--------------------------------------------------------------------------------
-- Construction helpers
--------------------------------------------------------------------------------

-- The frame a role's control is built on. A template kind puts the skin's
-- template first and the caller's own after it, so a secure button keeps
-- its handler templates whatever the skin draws it with.
function Chrome.CreateFrame(role, frameType, name, parent, extraTemplates)
    local spec = type(role) == "table" and role or Chrome.Spec(role)
    local template
    if spec.kind == "template" then template = spec.template end
    if type(extraTemplates) == "string" and extraTemplates ~= "" then
        template = template and (template .. ", " .. extraTemplates) or extraTemplates
    end
    local frame = CreateFrame(frameType, name, parent, template)
    return frame, spec
end

-- The nine-slice pieces drawn on a child that fills the frame, so the frame's
-- own textures and the pieces never share a draw layer. The child answers
-- SetBorderColor for a tint and Destroy for teardown.
function Chrome.NineSlice(frame, spec)
    local child = CreateFrame("Frame", nil, frame)
    child:SetAllPoints(frame)
    child:SetFrameLevel(frame:GetFrameLevel())
    local layout = NineSliceLayouts[spec.layout]
    NineSliceUtil.ApplyLayout(child, layout, spec.textureKit)

    function child:SetBorderColor(r, g, b, a)
        for _, name in ipairs(NINE_SLICE_PIECES) do
            local piece = self[name]
            if piece and piece.SetVertexColor then piece:SetVertexColor(r, g, b, a or 1) end
        end
    end

    function child:Destroy()
        self:Hide()
        self:SetParent(nil)
    end

    if spec.tint then
        child:SetBorderColor(Chrome.Color(spec.tint))
    end
    return child
end

--------------------------------------------------------------------------------
-- Backdrop handles
--------------------------------------------------------------------------------
-- Chrome.Backdrop(role, frame, opts) draws a role's backdrop on a frame the
-- control owns and returns a handle the control drives by state:
--   SetHover(bool), SetSelected(bool), SetDisabled(bool), SetOpen(bool)
--   Refresh()              repaint from the flags; the accent subscription calls it
--   LabelColor([state])    r, g, b, a for the current or a named state
--   SetShown(bool), Destroy()
--   inset                  the horizontal content inset the parts take
-- opts: variant ("parent" or "child", the navRow color maps), label (a
-- FontString the handle colors by state), inset (an override).
--
-- The flat parts reproduce the framework's own draw for each role. The
-- atlas kind shows one texture per declared state and falls back to normal.

local function Ctl()
    return addon.UI.Controls
end

local function Metrics()
    return addon.UI.Controls.Metrics()
end

local handles = setmetatable({}, { __mode = "k" })
local handlesSubscribed = false
local function EnsureHandleSubscription()
    if handlesSubscribed then return end
    local Theme = addon.UI.Theme
    if not Theme then return end
    handlesSubscribed = true
    Theme:Subscribe("ChromeBackdrops", function()
        for h in pairs(handles) do
            pcall(h.Refresh, h)
        end
    end)
end

local BackdropMT = {}
BackdropMT.__index = BackdropMT

-- Hover wins over selected where the control reads that way (a nav row's
-- label brightens under the cursor even while selected); a tab keeps its
-- selected look under the cursor.
function BackdropMT:State()
    if self.disabled then return "disabled" end
    if self.hover and (self.hoverWins or not self.selected) then return "hover" end
    if self.selected then return "selected" end
    if self.open then return "open" end
    return "normal"
end

function BackdropMT:LabelColor(state)
    state = state or self:State()
    local colors = self.labelColors or {}
    local token = colors[state] or colors.normal or "accent"
    return Chrome.Color(token)
end

function BackdropMT:Refresh()
    if self.paint then self.paint() end
    if self.label and self.labelColors then
        self.label:SetTextColor(self:LabelColor())
    end
end

function BackdropMT:SetHover(v) self.hover = v and true or false; self:Refresh() end
function BackdropMT:SetSelected(v) self.selected = v and true or false; self:Refresh() end
function BackdropMT:SetDisabled(v) self.disabled = v and true or false; self:Refresh() end
function BackdropMT:SetOpen(v) self.open = v and true or false; self:Refresh() end

function BackdropMT:SetShown(shown)
    if shown then
        if self.border then self.border:SetShown(true) end
        self:Refresh()
        return
    end
    for _, part in ipairs(self.parts or {}) do part:Hide() end
    if self.border then self.border:SetShown(false) end
end

function BackdropMT:Destroy()
    handles[self] = nil
    for _, part in ipairs(self.parts or {}) do part:Hide() end
    if self.border and self.border.Destroy then self.border:Destroy() end
end

local Flat = {}

Flat.tab = function(h, frame, spec)
    local m = Metrics().tab
    h.selectedFill = Ctl().AddHoverFill(frame, { alpha = 1, inset = 1 })
    h.hoverFill = Ctl().AddHoverFill(frame, { alpha = m.hoverAlpha, inset = 1, sublevel = Ctl().SUBLEVEL_BG })
    h.border = Ctl().CreateBorder(frame, { alpha = m.borderAlpha })
    h.parts = { h.selectedFill, h.hoverFill }
    h.paint = function()
        h.selectedFill:SetShown(h.selected)
        h.hoverFill:SetShown(h.hover and not h.selected)
    end
end

Flat.tabBody = function(h, frame, spec)
    local m = Metrics().tab
    h.border = Ctl().CreateBorder(frame, { thickness = m.borderWidth, alpha = m.borderAlpha })
    local fill = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    fill:SetPoint("TOPLEFT", m.borderWidth, 0)
    fill:SetPoint("BOTTOMRIGHT", -m.borderWidth, m.borderWidth)
    local c = spec.fill or { 0, 0, 0, 0.15 }
    fill:SetColorTexture(c[1] or 0, c[2] or 0, c[3] or 0, c[4] or 1)
    h.parts = { fill }
    h.inset = m.borderWidth + m.contentPadding
    h.paint = function() end
end

Flat.sectionHeader = function(h, frame, spec)
    local m = Metrics().collapsible
    h.bg = Ctl().AddBackground(frame, { color = spec.background or "collapsible" })
    h.hoverFill = Ctl().AddHoverFill(frame)
    h.border = Ctl().CreateBorder(frame, { thickness = m.borderWidth, alpha = m.borderAlpha, corners = "overlap" })
    -- The verticals start under the top edge and run to the bottom, where
    -- the body's edges take over while the section is open.
    h.border.LEFT:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -m.borderWidth)
    h.border.RIGHT:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -m.borderWidth)
    h.parts = { h.bg, h.hoverFill }
    h.paint = function()
        h.hoverFill:SetShown(h.hover)
        h.border.BOTTOM:SetShown(not h.open)
    end
end

Flat.sectionBody = function(h, frame, spec)
    local m = Metrics().collapsible
    h.bg = Ctl().AddBackground(frame, { color = spec.background or "collapsible" })
    -- Left, right and bottom edges just outside the content rect, closing the
    -- box the header opened.
    local function edge()
        return frame:CreateTexture(nil, "BORDER", nil, -1)
    end
    local left = edge()
    left:SetPoint("TOPLEFT", frame, "TOPLEFT", -m.borderWidth, 0)
    left:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", -m.borderWidth, 0)
    left:SetWidth(m.borderWidth)
    local right = edge()
    right:SetPoint("TOPRIGHT", frame, "TOPRIGHT", m.borderWidth, 0)
    right:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", m.borderWidth, 0)
    right:SetWidth(m.borderWidth)
    local bottom = edge()
    bottom:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", -m.borderWidth, 0)
    bottom:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", m.borderWidth, 0)
    bottom:SetHeight(m.borderWidth)
    for _, tex in ipairs({ left, right, bottom }) do
        Ctl().RegisterThemedFill(tex, m.borderAlpha)
    end
    h.parts = { h.bg, left, right, bottom }
    h.inset = m.borderWidth
    h.paint = function() end
end

Flat.navRow = function(h, frame, spec)
    local m = Metrics().nav
    local hoverBg = frame:CreateTexture(nil, "BACKGROUND")
    hoverBg:SetAllPoints()
    Ctl().RegisterThemedFill(hoverBg, m.hoverAlpha)
    local selectBg = frame:CreateTexture(nil, "BACKGROUND", nil, -1)
    selectBg:SetAllPoints()
    Ctl().RegisterThemedFill(selectBg, m.selectedAlpha)
    h.hoverWins = true
    h.parts = { hoverBg, selectBg }
    h.paint = function()
        hoverBg:SetShown(h.hover and not h.disabled)
        selectBg:SetShown(h.selected and not h.disabled)
    end
end

Flat.dropdown = function(h, frame, spec)
    local m = Metrics().dropdown
    h.border = Ctl().CreateBorder(frame, {
        alpha = m.borderAlpha,
        getAlpha = function() return h.hover and m.borderHoverAlpha or m.borderAlpha end,
    })
    h.bg = Ctl().AddBackground(frame, { inset = 1, sublevel = Ctl().SUBLEVEL_FILL })
    h.hoverFill = Ctl().AddHoverFill(frame, { alpha = m.hoverAlpha, inset = 1, sublevel = Ctl().SUBLEVEL_HOVER })
    h.parts = { h.bg, h.hoverFill }
    h.paint = function()
        h.hoverFill:SetShown(h.hover)
        h.border:Refresh()
    end
end

local function AtlasParts(h, frame, spec)
    h.textures = {}
    h.parts = {}
    for _, state in ipairs(ATLAS_STATES) do
        local name = spec[state]
        if name then
            local tex = frame:CreateTexture(nil, spec.layer or "BACKGROUND", nil, spec.sublevel)
            if spec.sizing == "native" then
                tex:SetAtlas(name, true)
                tex:SetPoint(spec.point or "CENTER")
            else
                tex:SetAtlas(name)
                tex:SetAllPoints()
            end
            tex:Hide()
            h.textures[state] = tex
            h.parts[#h.parts + 1] = tex
        end
    end
    h.inset = spec.inset or 0
    h.paint = function()
        local pick = h.textures[h:State()] or h.textures.normal
        for _, tex in pairs(h.textures) do
            tex:SetShown(tex == pick)
        end
    end
end

function Chrome.Backdrop(role, frame, opts)
    opts = opts or {}
    local spec = Chrome.Spec(role)
    local h = setmetatable({
        role = role, frame = frame, spec = spec, label = opts.label,
        hover = false, selected = false, disabled = false, open = false,
        inset = 0, hoverWins = false,
    }, BackdropMT)

    local flat = Chrome.FLAT[role] or {}
    local variant = opts.variant and (spec[opts.variant] or flat[opts.variant])
    h.labelColors = (variant and variant.labelColors) or spec.labelColors or flat.labelColors

    if spec.kind == "atlas" then
        AtlasParts(h, frame, spec)
    elseif Flat[role] then
        Flat[role](h, frame, spec)
    else
        h.parts = {}
        h.paint = function() end
    end
    if spec.hoverOverSelected ~= nil then h.hoverWins = spec.hoverOverSelected and true or false end
    if opts.inset then h.inset = opts.inset end

    handles[h] = true
    EnsureHandleSubscription()
    h:Refresh()
    return h
end

--------------------------------------------------------------------------------
-- Listing
--------------------------------------------------------------------------------

local function describe(spec)
    if type(spec) ~= "table" then return "nil" end
    local kind = spec.kind or "?"
    if kind == "template" then return kind .. " " .. tostring(spec.template) end
    if kind == "window" then return "window (the window template's part)" end
    if kind == "nineSlice" then
        return kind .. " " .. tostring(spec.layout) .. (spec.textureKit and (" / " .. spec.textureKit) or "")
    end
    if kind == "atlas" then
        if spec.atlas then return kind .. " " .. tostring(spec.atlas) end
        local names = {}
        for _, state in ipairs(ATLAS_STATES) do
            if spec[state] then names[#names + 1] = state .. "=" .. tostring(spec[state]) end
        end
        return kind .. " " .. table.concat(names, " ")
    end
    return kind
end

function Chrome.Dump(push)
    push("chrome:")
    for _, role in ipairs(Chrome.ROLES) do
        local declared = Chrome.Declared(role)
        local spec = Chrome.Spec(role)
        local line = string.format("  %-14s %s", role, describe(spec))
        if declared == nil then
            line = line .. "  (default)"
        elseif declared ~= spec then
            line = line .. "  (fallback taken; declared " .. describe(declared) .. ")"
        end
        push(line)
    end
end
