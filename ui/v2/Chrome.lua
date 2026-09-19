-- Chrome.lua - chrome descriptors: how each surface of the settings panel is
-- drawn, declared per role by the active skin and resolved here against the
-- running client.
--
-- A skin's chrome table holds one descriptor per role: window, picker,
-- titleBar, closeButton, button, resizeGrip, scrollBar, tab, tabBody,
-- sectionHeader, sectionBody, navRow, navCard, navDivider, dropdown,
-- arrowButton, field, infoIcon, tooltip, slider, input. A descriptor names a
-- kind and what that kind needs:
--   flat       the framework's own draw (CreateBorder, AddBackground,
--              AddHoverFill) with numbers from the skin metrics
--   nineSlice  NineSliceUtil.ApplyLayout on a child frame: layout, textureKit
--   atlas      one atlas per state: normal, hover, selected, disabled, pressed
--   sliced     one atlas per state, each cut into nine by texcoords so the
--              art takes any width and height: the state names of atlas, plus
--              slice, edge, desaturate, tint = { border, center } (color
--              tokens), pieces = { border, fill } (opacity piece names),
--              glyphColors and pressedOffset
--   template   a Blizzard frame template supplies the art and part of the
--              method surface: template, joined with the caller's own. On
--              the window role the frame itself is the template, and the
--              descriptor names the portrait and a contentBackground
--   window     the window template supplies this part (titleBar, closeButton)
--   card       a nine-slice cut out of one atlas by texcoords, with a glow
--              shown while open: atlas (or texture and size), slice, edge,
--              glow (an atlas descriptor, with fixed for a band that keeps
--              its own scale)
--   glyph      art alone, no box behind it: glyphs, glyphColors, and scale,
--              the multiplier on the size the caller asks for, since a
--              letter drawn in the middle of its texture needs a bigger box
--              than a character in a font does
--   ascii, text, texture   how the title bar presents the product's title.
--              On the resizeGrip role, texture is the atlas kind with file
--              paths in place of atlas names: normal, hover, pressed, plus
--              glow, an image laid over the base under the cursor, and tint,
--              a color token the art is vertex-colored with
-- Any descriptor may carry fallback (another descriptor), labelColors (a
-- color token per state), glyphColors (the same for an icon or an arrow),
-- glyphs (a character or an art table per name), font ("role" or "template")
-- and inset.
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
--   Chrome.SlicedAtlas(frame, spec, layer, sublevel)
--                                    nine textures cut from one atlas by texcoords
--   Chrome.GridAtlas(frame, spec, layer, sublevel, xs, ys)
--                                    one atlas cut at named splits, each split laid
--                                    on a frame position the caller gives; a cell
--                                    may repeat a band of the art instead of
--                                    stretching (grid.tile)
--   Chrome.Backdrop(role, frame, opts)
--                                    a state handle drawing a role's backdrop on a
--                                    control's frame (tab, tabBody, sectionHeader,
--                                    sectionBody, navRow, dropdown, and any role
--                                    of kind atlas, sliced or card)
--   Chrome.Glyph(parent, glyph, opts) an icon or an arrow as one handle: a string
--                                    draws in the button font, a table
--                                    { atlas | texture, size, desaturate } draws
--                                    art; region, SetColor, SetShown, SetGlyph
--   Chrome.Portrait(parent, spec)    an icon on its own frame, ringed or bare
--   Chrome.Dump(push)                one line per role for the skin listing
--   Chrome.Opacity(name)             a named piece's opacity from the skin's
--                                    opacity table, 1 when the skin leaves it out
--   Chrome.ApplyOpacity(name, region, scale)
--                                    put a region on a piece's opacity, times a
--                                    state's own alpha
--   Chrome.RefreshOpacity([name])    reapply one piece, or all of them
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.Chrome = addon.UI.Chrome or {}
local Chrome = addon.UI.Chrome

Chrome.ROLES = {
    "window", "picker", "titleBar", "closeButton", "button", "resizeGrip", "scrollBar",
    "tab", "tabBody", "sectionHeader", "sectionBody", "navRow", "navCard", "navDivider",
    "dropdown", "arrowButton", "field", "infoIcon", "tooltip", "slider", "input",
    "editSelection", "editDialog",
}

-- The flat defaults: the panel's own drawing, one per role. A skin that
-- declares nothing for a role gets this, and a declared descriptor the client
-- cannot draw ends here too.
Chrome.FLAT = {
    window = {
        kind = "flat", corners = "outset", background = "window",
        noise = { texture = "NOISE_OVERLAY", size = 2048, alpha = 0.25, blend = "ADD" },
    },
    -- The floating dialog the font, bar texture, bar border and icon pickers
    -- open in (Controls.CreatePickerShell). It is the window role's small
    -- relation and takes the same kinds, minus the contentBackground: the
    -- panes inside it are a tab column and a scroll frame, not a nav and a
    -- page, so a background cut for the panel's geometry would not meet them.
    -- Flat is the panel's fill with a border around it.
    picker        = { kind = "flat", background = "window" },
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
    -- Flat arrowButton and field are the selector family's own draws: the
    -- caller's arrow character over an accent hover fill, and a border with a
    -- background around the whole field.
    arrowButton   = { kind = "flat" },
    field         = { kind = "flat" },
    -- The help icon a label, a tab or a header button carries, and the box
    -- its text opens in (ui/v2/controls/InfoIcon.lua). Flat draws the
    -- bordered square with the character centered in it, and a bordered box
    -- with the title in the accent above the body.
    infoIcon      = { kind = "flat", glyphs = { info = "i", help = "?" } },
    tooltip       = { kind = "flat" },
    -- A slider row's track, thumb and steppers (ui/v2/controls/Slider.lua).
    -- Flat is the accent line with a square thumb between two arrow buttons;
    -- a template kind builds Blizzard's slider with steppers.
    slider        = { kind = "flat" },
    -- The typed value box beside a slider (Controls.CreateValueInput). Flat is
    -- an accent border around the background color; a template kind keeps the
    -- art of Blizzard's InputBoxTemplate, which the flat draw hides.
    input         = { kind = "flat" },
    -- The search page's query box (Controls:CreateSearchBox). Flat is the
    -- framework's bordered edit box; a template kind builds Blizzard's
    -- SearchBoxTemplate, the options search bar with its magnifying glass
    -- and its clear button, on the skin's searchBox metric.
    searchBox     = { kind = "flat" },
    -- The Edit Mode surfaces for the addon's own frames (ui/v2/editmode/).
    -- Flat editSelection is Blizzard's selection box tinted with the accent;
    -- flat editDialog is the accent-bordered box with the brand row.
    editSelection = { kind = "flat" },
    editDialog    = { kind = "flat" },
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
    elseif kind == "card" then
        -- The face has to exist; the glow resolves on its own and may be absent
        if spec.atlas then return atlasExists(spec.atlas) end
        return type(spec.texture) == "string"
    elseif kind == "atlas" or kind == "sliced" then
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
    elseif kind == "glyph" then
        -- Every named atlas has to exist. A file path is taken on trust: the
        -- API answers nothing about a texture until one is drawn.
        if type(spec.glyphs) ~= "table" then return false end
        local any = false
        for _, glyph in pairs(spec.glyphs) do
            any = true
            if type(glyph) == "table" and glyph.atlas and not atlasExists(glyph.atlas) then
                return false
            end
        end
        return any
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
    Chrome.ForgetOpacity()
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
-- Piece opacity
--------------------------------------------------------------------------------

-- A skin's opacity table holds one number per named piece of the panel's
-- art: the window's border and its fill, each band of the page background,
-- a card's border and its interior. The values are the skin author's and
-- never a player setting. A piece the skin leaves out draws at 1, so a skin
-- with no table draws as it always has. applied remembers every region a
-- piece was put on, with the state scale it carried, so a retune repaints
-- the open panel; overrides are the debug command's session values.
local applied = {}
local opacityOverrides = {}

function Chrome.Opacity(name)
    local override = opacityOverrides[name]
    if override then return override end
    local Theme = addon.UI.Theme
    local declared = Theme and Theme.Opacity
    local value = declared and declared[name]
    return type(value) == "number" and value or 1
end

-- scale is a state's own alpha (a disabled card's dim), multiplied onto the
-- piece's value so the two never overwrite each other.
function Chrome.ApplyOpacity(name, region, scale)
    if not (region and region.SetAlpha) then return end
    scale = scale or 1
    local regions = applied[name]
    if not regions then
        regions = setmetatable({}, { __mode = "k" })
        applied[name] = regions
    end
    regions[region] = scale
    region:SetAlpha(Chrome.Opacity(name) * scale)
end

function Chrome.RefreshOpacity(name)
    for piece, regions in pairs(applied) do
        if name == nil or name == piece then
            local value = Chrome.Opacity(piece)
            for region, scale in pairs(regions) do
                region:SetAlpha(value * scale)
            end
        end
    end
end

-- A skin switch rebuilds the panel, so the regions of the last build go
function Chrome.ForgetOpacity()
    for piece in pairs(applied) do applied[piece] = nil end
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
-- SetBorderColor and SetCenterColor for a tint and Destroy for teardown.
--
-- A layout that carries a Center piece carries a fill the art leaves neutral
-- for the caller to color: Blizzard ships TooltipDefaultLayout's center as a
-- light gray and every tooltip built on it calls SetCenterColor with
-- TOOLTIP_DEFAULT_BACKGROUND_COLOR (SharedTooltipTemplates.lua,
-- TooltipBackdropTemplateMixin). Left alone it draws white text on white.
-- spec.tint = { border, center } colors the two apart; a bare spec.tint
-- colors all nine, which is what a border-only layout wants.
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

    function child:SetCenterColor(r, g, b, a)
        local piece = self.Center
        if piece and piece.SetVertexColor then piece:SetVertexColor(r, g, b, a or 1) end
    end

    function child:Destroy()
        self:Hide()
        self:SetParent(nil)
    end

    local tint = spec.tint
    if type(tint) == "table" and (tint.border or tint.center) then
        -- Border first: it takes every piece, and the center is set back after
        if tint.border then child:SetBorderColor(Chrome.Color(tint.border)) end
        if tint.center then child:SetCenterColor(Chrome.Color(tint.center)) end
    elseif tint then
        child:SetBorderColor(Chrome.Color(tint))
    end
    return child
end

-- An icon on a frame of its own, for a surface that is not the window (the
-- window's ring is a corner of its template's border and cannot be borrowed).
-- spec = { texture = key-or-path, ring = key-or-path | false, mask = false,
-- size = n }. A ring brings the minimap button's geometry with it: a ring
-- texture 53/31 of the button, whose drawn circle sits in its top-left, over an
-- icon 20/31 of it. Without one the icon takes the whole box, since a mark drawn
-- to its own edge has no hole to sit in. mask = false drops the round crop and
-- the black disc under it, both of which are there to fill a ring. The frame
-- answers SetIcon(keyOrPath).
function Chrome.Portrait(parent, spec)
    local Theme = addon.UI.Theme
    local function path(key)
        return (Theme and Theme.Textures and Theme.Textures[key]) or key
    end
    local size = spec.size or 32
    local unit = size / 31
    local ringArt = spec.ring
    if ringArt == nil then ringArt = "Interface\\Minimap\\MiniMap-TrackingBorder" end
    local iconSize = ringArt and (20 * unit) or size

    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(size, size)
    frame:SetFrameLevel(parent:GetFrameLevel() + 12)

    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetSize(iconSize, iconSize)
    icon:SetPoint("CENTER")
    icon:SetTexture(path(spec.texture))

    if spec.mask ~= false then
        local back = frame:CreateTexture(nil, "BACKGROUND")
        back:SetColorTexture(0, 0, 0, 1)
        back:SetSize(iconSize, iconSize)
        back:SetPoint("CENTER")

        local mask = frame:CreateMaskTexture()
        mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints(icon)
        icon:AddMaskTexture(mask)
        back:AddMaskTexture(mask)
    end

    if ringArt then
        local ring = frame:CreateTexture(nil, "OVERLAY")
        ring:SetSize(53 * unit, 53 * unit)
        ring:SetPoint("TOPLEFT")
        ring:SetTexture(path(ringArt))
    end

    function frame:SetIcon(key) icon:SetTexture(path(key)) end
    return frame
end

-- The art one descriptor names, as a file and the texcoord rect of the
-- member on it: spec.atlas, or spec.texture with spec.size = { w, h } and an
-- optional spec.texCoords = { l, r, t, b }. Returns nil when the art is
-- missing, else file, width, height, left, right, top, bottom.
local function AtlasSource(spec)
    local file, w, h, L, R, T, B
    if spec.atlas then
        if not (C_Texture and C_Texture.GetAtlasInfo) then return nil end
        local ok, info = pcall(C_Texture.GetAtlasInfo, spec.atlas)
        if not ok or type(info) ~= "table" then return nil end
        file = info.file or info.filename
        w, h = info.width, info.height
        L, R, T, B = info.leftTexCoord, info.rightTexCoord, info.topTexCoord, info.bottomTexCoord
    elseif type(spec.texture) == "string" then
        file = spec.texture
        w, h = spec.size and spec.size[1], spec.size and spec.size[2]
        local tc = spec.texCoords or { 0, 1, 0, 1 }
        L, R, T, B = tc[1], tc[2], tc[3], tc[4]
    else
        return nil
    end
    if not (file and w and h and w > 0 and h > 0 and L and R and T and B) then return nil end
    return file, w, h, L, R, T, B
end

-- A nine-slice cut out of one atlas member, or one bundled file, by
-- texcoords; spec.slice = { left, right, top, bottom } in the member's own
-- pixels. The corners keep their size, the edges stretch one way and the
-- center both, all on anchors to the frame, so a resize costs nothing. A
-- zero side omits its pieces, which makes { top, bottom } a vertical
-- three-slice. spec.edge = { left, right, top, bottom } is the margin of the
-- member that lies outside the frame's rect: clear pixels and any ornament
-- that protrudes past the border, so the border's outer edge lands on the
-- frame's edge. Returns nil when the art is missing, else a handle: pieces
-- (with border and center, the same textures in two groups), SetShown,
-- SetDesaturated, SetAlpha, SetVertexColor, SetBorderColor, SetCenterColor,
-- SetSource, ApplyOpacity, Destroy.
function Chrome.SlicedAtlas(frame, spec, layer, sublevel)
    local file, w, h, L, R, T, B = AtlasSource(spec)
    if not file then return nil end

    local slice = spec.slice or {}
    local sl, sr = slice.left or 0, slice.right or 0
    local st, sb = slice.top or 0, slice.bottom or 0
    local edge = spec.edge or {}
    local eL, eR = edge.left or 0, edge.right or 0
    local eT, eB = edge.top or 0, edge.bottom or 0
    local function cuts(l, r, t, b, mw, mh)
        local du, dv = (r - l) / mw, (b - t) / mh
        return { l, l + sl * du, r - sr * du, r }, { t, t + st * dv, b - sb * dv, b }
    end
    local u, v = cuts(L, R, T, B, w, h)
    local colWidth = { sl, nil, sr }
    local rowHeight = { st, nil, sb }

    local pieces, border, center, cells = {}, {}, {}, {}
    local function piece(col, row)
        local tex = frame:CreateTexture(nil, layer or "BACKGROUND", nil, sublevel)
        tex:SetTexture(file)
        tex:SetTexCoord(u[col], u[col + 1], v[row], v[row + 1])
        pieces[#pieces + 1] = tex
        cells[#pieces] = { col, row }
        local group = (col == 2 and row == 2) and center or border
        group[#group + 1] = tex
        return tex
    end
    for row = 1, 3 do
        for col = 1, 3 do
            local cw, rh = colWidth[col], rowHeight[row]
            local skip = (cw ~= nil and cw <= 0) or (rh ~= nil and rh <= 0)
            if not skip then
                local tex = piece(col, row)
                if cw then tex:SetWidth(cw) end
                if rh then tex:SetHeight(rh) end
                -- Column anchors: the left column starts edge.left outside
                -- the frame, the right column ends edge.right outside it, the
                -- middle runs between the two slice widths; rows likewise
                local x1, x2 = (col == 1) and -eL or (sl - eL), (col == 3) and eR or -(sr - eR)
                local y1, y2 = (row == 1) and eT or -(st - eT), (row == 3) and -eB or (sb - eB)
                if col == 1 and row == 1 then tex:SetPoint("TOPLEFT", frame, "TOPLEFT", -eL, eT)
                elseif col == 3 and row == 1 then tex:SetPoint("TOPRIGHT", frame, "TOPRIGHT", eR, eT)
                elseif col == 1 and row == 3 then tex:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", -eL, -eB)
                elseif col == 3 and row == 3 then tex:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", eR, -eB)
                elseif row == 1 then
                    tex:SetPoint("TOPLEFT", frame, "TOPLEFT", x1, eT)
                    tex:SetPoint("TOPRIGHT", frame, "TOPRIGHT", x2, eT)
                elseif row == 3 then
                    tex:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", x1, -eB)
                    tex:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", x2, -eB)
                elseif col == 1 then
                    tex:SetPoint("TOPLEFT", frame, "TOPLEFT", -eL, y1)
                    tex:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", -eL, y2)
                elseif col == 3 then
                    tex:SetPoint("TOPRIGHT", frame, "TOPRIGHT", eR, y1)
                    tex:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", eR, y2)
                else
                    tex:SetPoint("TOPLEFT", frame, "TOPLEFT", x1, y1)
                    tex:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", x2, y2)
                end
            end
        end
    end

    local handle = { pieces = pieces, border = border, center = center }
    function handle:SetShown(shown) for _, t in ipairs(self.pieces) do t:SetShown(shown) end end
    function handle:SetDesaturated(on) for _, t in ipairs(self.pieces) do t:SetDesaturated(on and true or false) end end
    function handle:SetAlpha(a) for _, t in ipairs(self.pieces) do t:SetAlpha(a) end end
    -- The eight outer pieces take one named opacity and the center another
    function handle:ApplyOpacity(borderName, centerName, scale)
        for _, t in ipairs(self.border) do Chrome.ApplyOpacity(borderName, t, scale) end
        for _, t in ipairs(self.center) do Chrome.ApplyOpacity(centerName or borderName, t, scale) end
    end
    function handle:SetVertexColor(r, g, b, a) for _, t in ipairs(self.pieces) do t:SetVertexColor(r, g, b, a or 1) end end
    function handle:SetBorderColor(r, g, b, a) for _, t in ipairs(self.border) do t:SetVertexColor(r, g, b, a or 1) end end
    function handle:SetCenterColor(r, g, b, a) for _, t in ipairs(self.center) do t:SetVertexColor(r, g, b, a or 1) end end
    -- Another member of the same cut (a state's art) on the same pieces.
    -- Returns false, and leaves the pieces as they were, when it is missing.
    function handle:SetSource(other)
        local f, mw, mh, l, r, t, b = AtlasSource(other)
        if not f then return false end
        local nu, nv = cuts(l, r, t, b, mw, mh)
        for i, tex in ipairs(self.pieces) do
            local col, row = cells[i][1], cells[i][2]
            tex:SetTexture(f)
            tex:SetTexCoord(nu[col], nu[col + 1], nv[row], nv[row + 1])
        end
        return true
    end
    function handle:Destroy() for _, t in ipairs(self.pieces) do t:Hide() end end
    return handle
end

-- Where one copy ends and the next begins, in frame units down from the
-- cell's top: 0, then a boundary per seam, then the cell's own bottom. A
-- seam is put on the centre of a physical pixel. A seam that lands on a
-- whole pixel falls between the two copies, which leaves the row under it
-- drawn by neither, and on art the panel sees through that empty row reads
-- as a bright hairline of whatever the panel stands on. On a pixel's centre
-- every row lies wholly inside one copy. The snap moves a seam by less than
-- a pixel and changes a copy's height by the same, which its texcoords
-- follow. A cell the layout engine has not placed yet has no scale to snap
-- against and takes the band's own height.
local function Boundaries(f, height, n, bandHeight)
    local edges = { [0] = 0, [n] = height }
    local scale = f:GetEffectiveScale() or 0
    local top = f:GetTop()
    for k = 1, n - 1 do
        local ideal = k * bandHeight
        if top and scale > 0 then
            local centre = math.floor((top - ideal) * scale) + 0.5
            edges[k] = top - centre / scale
        else
            edges[k] = ideal
        end
    end
    return edges
end

-- A grid cell that repeats one band of the member's rows down its rect
-- instead of stretching: copies at the band's own height from the top,
-- every other one flipped so each seam meets its own row, the last cut
-- short by its texcoords. The count follows the cell's height. v0 and v1
-- are texcoords, bandHeight the band's height in the member's pixels.
local function TiledCell(frame, place, file, u0, u1, v0, v1, bandHeight, layer, sublevel)
    local cell = CreateFrame("Frame", nil, frame)
    cell:SetFrameLevel(frame:GetFrameLevel())
    place(cell)
    cell.tiles = {}
    local function layout(f)
        local height = f:GetHeight() or 0
        local n = math.max(1, math.ceil(height / bandHeight))
        local edges = Boundaries(f, height, n, bandHeight)
        for i = 1, n do
            local t = f.tiles[i]
            if not t then
                t = f:CreateTexture(nil, layer or "BACKGROUND", nil, sublevel)
                t:SetTexture(file)
                f.tiles[i] = t
            end
            local top = edges[i - 1]
            local shown = math.max(0.5, edges[i] - top)
            local span = (v1 - v0) * math.min(1, shown / bandHeight)
            if i % 2 == 1 then
                t:SetTexCoord(u0, u1, v0, v0 + span)
            else
                t:SetTexCoord(u0, u1, v1, v1 - span)
            end
            t:ClearAllPoints()
            t:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -top)
            t:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -top)
            t:SetHeight(shown)
            t:Show()
        end
        for i = n + 1, #f.tiles do f.tiles[i]:Hide() end
    end
    cell:SetScript("OnSizeChanged", layout)
    cell:SetScript("OnShow", layout)
    -- The snap reads where the cell stands on the pixel grid, so it is taken
    -- again when the panel comes to rest somewhere else. The window is the
    -- host's parent; the movable test keeps the hook off a frame the addon
    -- does not own, and a cell the grid has replaced is hidden by then.
    local window = frame:GetParent()
    if window and window.IsMovable and window:IsMovable() then
        hooksecurefunc(window, "StopMovingOrSizing", function()
            if cell:IsShown() then layout(cell) end
        end)
    end
    layout(cell)
    return cell
end

-- One atlas cut into a grid and laid over the frame with each cut at a
-- frame position the caller names: spec.grid.cols and spec.grid.rows are
-- the splits in the member's own pixels, xs and ys the matching positions
-- in frame pixels from the frame's top-left corner. Every cell stretches to
-- its rect, so an edge baked into the art lands where the layout puts the
-- edge it stands for. A cell named in spec.grid.tile = { { col, row, v =
-- { top, bottom } } } repeats that band of the member's rows down its rect
-- instead, for a column whose art was painted around one fixed layout.
-- grid.fromRight and grid.fromBottom count the trailing splits that keep the
-- member's own distance from the frame's far edge, whatever the caller
-- passed: a border strip baked at the art's right or bottom keeps its width
-- through a resize. A negative position in xs or ys reads the same way.
-- grid.names = { { name, ... }, ... }, a row of piece names per grid row,
-- puts each cell on that piece's opacity (Chrome.ApplyOpacity).
-- Returns nil when the art is missing, else a handle: pieces, cells,
-- SetShown, Destroy.
function Chrome.GridAtlas(frame, spec, layer, sublevel, xs, ys)
    local file, w, h, L, R, T, B = AtlasSource(spec)
    if not file then return nil end
    local grid = spec.grid or {}
    local du, dv = (R - L) / w, (B - T) / h
    local u, v = { L }, { T }
    for _, c in ipairs(grid.cols or {}) do u[#u + 1] = L + c * du end
    u[#u + 1] = R
    for _, r in ipairs(grid.rows or {}) do v[#v + 1] = T + r * dv end
    v[#v + 1] = B
    local px, py = {}, {}
    for i, x in ipairs(xs or {}) do px[i] = x end
    for i, y in ipairs(ys or {}) do py[i] = y end
    local cols, rows = grid.cols or {}, grid.rows or {}
    for i = math.max(1, #cols - (grid.fromRight or 0) + 1), #cols do px[i] = cols[i] - w end
    for i = math.max(1, #rows - (grid.fromBottom or 0) + 1), #rows do py[i] = rows[i] - h end
    -- A position as a side of the frame and an offset from it; nil is the far edge
    local function sideX(p)
        if p == nil then return "RIGHT", 0 end
        if p < 0 then return "RIGHT", p end
        return "LEFT", p
    end
    local function sideY(p)
        if p == nil then return "BOTTOM", 0 end
        if p < 0 then return "BOTTOM", -p end
        return "TOP", -p
    end
    local tiled = {}
    for _, t in ipairs(grid.tile or {}) do
        if t.row and t.col and t.v then
            tiled[t.row] = tiled[t.row] or {}
            tiled[t.row][t.col] = t
        end
    end

    -- Three points fix a cell's rect: the top-left, the right edge (a split
    -- or the frame's edge) and the bottom edge (likewise)
    local function placer(col, row)
        local lastCol, lastRow = col == #u - 1, row == #v - 1
        local sx1, ox1 = sideX((col == 1) and 0 or px[col - 1])
        local sy1, oy1 = sideY((row == 1) and 0 or py[row - 1])
        local sx2, ox2 = sideX((not lastCol) and px[col] or nil)
        local sy2, oy2 = sideY((not lastRow) and py[row] or nil)
        return function(region)
            region:SetPoint("TOPLEFT", frame, sy1 .. sx1, ox1, oy1)
            region:SetPoint("TOPRIGHT", frame, sy1 .. sx2, ox2, oy1)
            region:SetPoint("BOTTOMLEFT", frame, sy2 .. sx1, ox1, oy2)
        end
    end

    local pieces, cells = {}, {}
    for row = 1, #v - 1 do
        for col = 1, #u - 1 do
            local place = placer(col, row)
            local tile = tiled[row] and tiled[row][col]
            local region
            if tile then
                region = TiledCell(frame, place, file, u[col], u[col + 1],
                    T + tile.v[1] * dv, T + tile.v[2] * dv, tile.v[2] - tile.v[1], layer, sublevel)
                cells[#cells + 1] = region
            else
                region = frame:CreateTexture(nil, layer or "BACKGROUND", nil, sublevel)
                region:SetTexture(file)
                region:SetTexCoord(u[col], u[col + 1], v[row], v[row + 1])
                place(region)
                pieces[#pieces + 1] = region
            end
            local name = grid.names and grid.names[row] and grid.names[row][col]
            if name then Chrome.ApplyOpacity(name, region) end
        end
    end

    -- A border cell has no fill beneath it, so a border fainter than the
    -- fill beside it would show more of the world. grid.underlay = { { name,
    -- from = { col, row }, cells = { { col, row }, ... } }, ... } lays a copy
    -- of the from cell's art under each listed cell, one sublevel down, on
    -- the named piece. Each copy samples the strip of the from cell nearest
    -- the cell it sits under, at the cell's own size in member pixels.
    local bx, by = { 0 }, { 0 }
    for _, c in ipairs(cols) do bx[#bx + 1] = c end
    bx[#bx + 1] = w
    for _, r in ipairs(rows) do by[#by + 1] = r end
    by[#by + 1] = h
    local function strip(lo, hi, size, index, from)
        if index < from then return lo, math.min(hi, lo + size) end
        if index > from then return math.max(lo, hi - size), hi end
        return lo, hi
    end
    local underSublevel = math.max(-8, (sublevel or 0) - 1)
    for _, under in ipairs(grid.underlay or {}) do
        local fc, fr = under.from and under.from[1], under.from and under.from[2]
        if under.name and fc and fr and bx[fc + 1] and by[fr + 1] then
            local band = tiled[fr] and tiled[fr][fc]
            local y0, y1 = by[fr], by[fr + 1]
            if band then y0, y1 = band.v[1], band.v[2] end
            for _, cell in ipairs(under.cells or {}) do
                local col, row = cell[1], cell[2]
                if bx[col + 1] and by[row + 1] then
                    local xa, xb = strip(bx[fc], bx[fc + 1], bx[col + 1] - bx[col], col, fc)
                    local ya, yb = strip(y0, y1, by[row + 1] - by[row], row, fr)
                    local tex = frame:CreateTexture(nil, layer or "BACKGROUND", nil, underSublevel)
                    tex:SetTexture(file)
                    tex:SetTexCoord(L + xa * du, L + xb * du, T + ya * dv, T + yb * dv)
                    placer(col, row)(tex)
                    pieces[#pieces + 1] = tex
                    Chrome.ApplyOpacity(under.name, tex)
                end
            end
        end
    end

    local handle = { pieces = pieces, cells = cells }
    function handle:SetShown(shown)
        for _, t in ipairs(self.pieces) do t:SetShown(shown) end
        for _, c in ipairs(self.cells) do c:SetShown(shown) end
    end
    function handle:Destroy()
        for _, t in ipairs(self.pieces) do t:Hide() end
        for _, c in ipairs(self.cells) do c:SetScript("OnSizeChanged", nil); c:Hide() end
    end
    return handle
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
-- FontString the handle colors by state), inset (an override), header (the
-- band a card's hover fill covers, in pixels from the top).
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
-- selected look under the cursor. A role whose open art is the lit one, as a
-- section header's is, sets hoverOverOpen = false: the cursor then leaves that
-- art alone rather than dropping the control back to the dimmer hover wash,
-- and hoverGlow lifts it instead.
function BackdropMT:State()
    if self.disabled then return "disabled" end
    if self.pressed then return "pressed" end
    local lit = (self.selected and not self.hoverWins) or (self.open and not self.hoverOverOpen)
    if self.hover and not lit then return "hover" end
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

-- The color of an icon or an arrow on the control, by the same state walk
function BackdropMT:GlyphColor(state)
    state = state or self:State()
    local colors = self.spec.glyphColors or self.labelColors or {}
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
function BackdropMT:SetPressed(v) self.pressed = v and true or false; self:Refresh() end

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

-- spec.border = false draws no box, so the change of ground at the body's
-- edge is the only mark; a table gives the box a thickness, an alpha and a
-- color of its own. The box is themed, and so the accent, unless the table
-- names a color: a skin whose tab art carries another hue draws the body's
-- box in that hue, and the section's accent line around it stays a line of a
-- different color rather than the same one twice. spec.fill takes a color
-- token as well as a literal, so a skin can name a palette entry instead of
-- repeating its numbers.
Flat.tabBody = function(h, frame, spec)
    local m = Metrics().tab
    local width = 0
    if spec.border ~= false then
        local b = (type(spec.border) == "table") and spec.border or {}
        width = b.thickness or m.borderWidth
        h.border = Ctl().CreateBorder(frame, {
            thickness = width,
            alpha = b.alpha or m.borderAlpha,
            color = b.color and { Chrome.Color(b.color) } or nil,
        })
    end
    local fill = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    fill:SetPoint("TOPLEFT", width, 0)
    fill:SetPoint("BOTTOMRIGHT", -width, width)
    local r, g, b, a = Chrome.Color(spec.fill or { 0, 0, 0, 0.15 })
    fill:SetColorTexture(r, g, b, a)
    h.parts = { fill }
    h.inset = width + m.contentPadding
    h.paint = function() end
end

-- spec.border gives the section's box an alpha and a color of its own, as
-- tabBody's does. The header and the body draw the same box in two pieces, so
-- both read the same table and a skin sets it on both. Left out, the box is
-- themed and follows the accent.
Flat.sectionHeader = function(h, frame, spec)
    local m = Metrics().collapsible
    local box = (type(spec.border) == "table") and spec.border or {}
    h.bg = Ctl().AddBackground(frame, { color = spec.background or "collapsible" })
    h.hoverFill = Ctl().AddHoverFill(frame)
    h.border = Ctl().CreateBorder(frame, {
        thickness = m.borderWidth,
        alpha = box.alpha or m.borderAlpha,
        corners = "overlap",
        color = box.color and { Chrome.Color(box.color) } or nil,
    })
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
    local box = (type(spec.border) == "table") and spec.border or {}
    local boxAlpha = box.alpha or m.borderAlpha
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
        if box.color then
            local r, g, blue = Chrome.Color(box.color)
            tex:SetColorTexture(r, g, blue, boxAlpha)
        else
            Ctl().RegisterThemedFill(tex, boxAlpha)
        end
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

-- The opacity piece an atlas role's state textures take, where it is not the
-- role's own name. A table gives one piece per state, for a role whose states
-- are different art standing in different company: a nav row's selected gold
-- sits beside the card's glow and gives up light the hover wash does not.
local ATLAS_PIECE = { navRow = { hover = "navRowHover", selected = "navRowSelected" } }

local function AtlasPiece(role, state)
    local piece = ATLAS_PIECE[role]
    if type(piece) == "table" then return piece[state] or role end
    return piece or role
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
            Chrome.ApplyOpacity(AtlasPiece(h.role, state), tex)
            h.textures[state] = tex
            h.parts[#h.parts + 1] = tex
        end
    end
    h.inset = spec.inset or 0
    -- spec.hoverGlow: an additive copy of the drawn art at that alpha while
    -- the cursor is on a control the state walk holds on its lit art. Dark
    -- pixels add nothing, so the art's own light is what brightens.
    local glow
    if spec.hoverGlow then
        glow = frame:CreateTexture(nil, spec.layer or "BACKGROUND", nil, (spec.sublevel or 0) + 1)
        glow:SetAllPoints()
        glow:SetBlendMode("ADD")
        glow:Hide()
        h.parts[#h.parts + 1] = glow
    end
    h.paint = function()
        local state = h:State()
        local pick = h.textures[state] or h.textures.normal
        for _, tex in pairs(h.textures) do
            tex:SetShown(tex == pick)
        end
        if glow then
            local lift = pick and h.hover and not h.disabled and state ~= "hover"
            if lift then
                glow:SetAtlas(spec[state] or spec.normal)
                Chrome.ApplyOpacity(AtlasPiece(h.role, state), glow, spec.hoverGlow)
            end
            glow:SetShown(lift and true or false)
        end
    end
end

-- One nine-slice whose source follows the state, so a button of any size
-- keeps the art's corners and rim. A state with no art of its own draws the
-- normal member. The tint multiplies, so a skin that recolors sets desaturate.
local function SlicedParts(h, frame, spec)
    h.parts = {}
    h.inset = spec.inset or 0
    local cut = { atlas = spec.normal or spec.atlas, slice = spec.slice, edge = spec.edge }
    h.art = Chrome.SlicedAtlas(frame, cut, spec.layer or "BACKGROUND", spec.sublevel)
    if not h.art then
        h.paint = function() end
        return
    end
    for _, tex in ipairs(h.art.pieces) do h.parts[#h.parts + 1] = tex end
    local pieces = spec.pieces or {}
    local drawn
    h.paint = function()
        local name = spec[h:State()] or spec.normal or spec.atlas
        if name ~= drawn and h.art:SetSource({ atlas = name }) then drawn = name end
        h.art:SetDesaturated(spec.desaturate)
        local tint = spec.tint
        if tint then
            if tint.border then h.art:SetBorderColor(Chrome.Color(tint.border)) end
            if tint.center then h.art:SetCenterColor(Chrome.Color(tint.center)) end
        end
        h.art:ApplyOpacity(pieces.border or h.role, pieces.fill or pieces.border or h.role, h.scale or 1)
    end
end

-- An icon or an arrow a control draws over its backdrop. A string is a
-- character in the button font, which is how the flat skin draws its arrows;
-- a table names art, desaturated before the color goes on so the color is the
-- caller's and never the art's own.
function Chrome.Glyph(parent, glyph, opts)
    opts = opts or {}
    local handle = {}
    local function build(g)
        if handle.region then handle.region:Hide() end
        handle.art = type(g) == "table"
        if handle.art then
            local tex = handle.texture or parent:CreateTexture(nil, opts.layer or "OVERLAY")
            handle.texture = tex
            local size = g.size or opts.size
            if g.atlas then
                tex:SetAtlas(g.atlas, size == nil)
            else
                tex:SetTexture(g.texture)
                if g.texCoords then tex:SetTexCoord(unpack(g.texCoords)) end
            end
            if size then tex:SetSize(size, size) end
            -- Radians, counter-clockwise: one arrow can point a second way.
            tex:SetRotation(g.rotation or 0)
            tex:SetDesaturated(g.desaturate ~= false)
            handle.region = tex
        else
            local fs = handle.fontString or parent:CreateFontString(nil, opts.layer or "OVERLAY")
            handle.fontString = fs
            local Theme = addon.UI.Theme
            if Theme and Theme.ApplyFont then
                Theme:ApplyFont(fs, opts.fontRole or "button", opts.fontSize or 14)
            end
            fs:SetText(g or "")
            handle.region = fs
        end
        handle.region:Show()
    end
    build(glyph)
    function handle:SetGlyph(g)
        build(g)
        if self.r then self:SetColor(self.r, self.g, self.b, self.a) end
    end
    function handle:SetColor(r, g, b, a)
        self.r, self.g, self.b, self.a = r, g, b, a or 1
        if self.art then
            self.region:SetVertexColor(r, g, b, a or 1)
        else
            self.region:SetTextColor(r, g, b, a or 1)
        end
    end
    function handle:SetShown(shown) self.region:SetShown(shown and true or false) end
    function handle:GetWidth() return self.region:GetWidth() or 0 end
    return handle
end

-- The card: the face sliced from its atlas over the whole frame, a hover
-- fill inside the border across the header band (opts.header, else the
-- frame's height), the label colored by state, and a glow at the right edge
-- while the group is open or selected. The glow stands nav.card.glowInset
-- inside the frame's top and bottom edges, the way Blizzard's ends on the
-- card's border, on a frame above the card's children. With glow.fixed =
-- { top, bottom }, rows of the glow's atlas,
-- the band between them keeps its own scale while the rows outside stretch,
-- so an arrow baked into the middle stays an arrow on a tall card; the whole
-- glow scales down together when the card is shorter than the atlas.
-- Without fixed, one texture stretched to the glow frame. The glow and the
-- fill read the flags directly, since the glow has to stay while the cursor
-- is over it.
--
-- The glow's width follows its height, which comes from the card's anchors,
-- and the card's from the nav content frame's. On the panel's first build
-- that frame has no height until every row is placed, so at creation the
-- glow reads a height of zero. A zero height is a rect not yet resolved,
-- never a size to fit: the natural size stands until OnSizeChanged brings
-- a real one. Fitting to zero set the width to zero, and a frame with no
-- width has no rect and gets no size event, so the first build's glow
-- stayed invisible until a click rebuilt the rows against a sized frame.
local function GlowFrame(frame, glowSpec, m)
    local file, w, gh, L, R, T, B = AtlasSource(glowSpec)
    if not file then return nil end
    local inset = m.glowInset or 0
    local x = glowSpec.x or m.glowOffset or 0
    local glow = CreateFrame("Frame", nil, frame)
    glow:SetFrameLevel(frame:GetFrameLevel() + 5)
    glow:SetPoint("TOPRIGHT", frame, "TOPRIGHT", x, -inset)
    glow:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", x, inset)
    glow:SetWidth(w)

    local dv = (B - T) / gh
    local function band(v0, v1)
        local t = glow:CreateTexture(nil, "ARTWORK")
        t:SetTexture(file)
        t:SetTexCoord(L, R, T + v0 * dv, T + v1 * dv)
        return t
    end

    local fixed = glowSpec.fixed
    local mid
    if fixed then
        local top, bottom = band(0, fixed.top), band(fixed.bottom, gh)
        mid = band(fixed.top, fixed.bottom)
        mid:SetHeight(fixed.bottom - fixed.top)
        mid:SetPoint("LEFT")
        mid:SetPoint("RIGHT")
        top:SetPoint("TOPLEFT")
        top:SetPoint("TOPRIGHT")
        top:SetPoint("BOTTOMLEFT", mid, "TOPLEFT")
        top:SetPoint("BOTTOMRIGHT", mid, "TOPRIGHT")
        bottom:SetPoint("BOTTOMLEFT")
        bottom:SetPoint("BOTTOMRIGHT")
        bottom:SetPoint("TOPLEFT", mid, "BOTTOMLEFT")
        bottom:SetPoint("TOPRIGHT", mid, "BOTTOMRIGHT")
    else
        band(0, gh):SetAllPoints()
    end

    -- The width follows the height at the atlas's aspect until the atlas's
    -- own size, and the fixed band scales with it; no height yet, no fit
    local function fit(f, _, height)
        if not height or height <= 0 then return end
        local s = math.min(1, height / gh)
        local width = w * s
        if math.abs((f:GetWidth() or 0) - width) > 0.5 then f:SetWidth(width) end
        if mid then mid:SetHeight((fixed.bottom - fixed.top) * s) end
    end
    glow:SetScript("OnSizeChanged", fit)
    fit(glow, nil, glow:GetHeight())
    glow:Hide()
    return glow
end

local function CardParts(h, frame, spec)
    local m = Metrics().nav.card
    h.parts = {}
    h.art = Chrome.SlicedAtlas(frame, spec, spec.layer or "BACKGROUND", spec.sublevel)
    if h.art then
        for _, tex in ipairs(h.art.pieces) do h.parts[#h.parts + 1] = tex end
    end
    local glowSpec = spec.glow and Chrome.Resolve(spec.glow, nil)
    if glowSpec and glowSpec.kind == "atlas" and glowSpec.atlas then
        h.glow = GlowFrame(frame, glowSpec, m)
        if h.glow then
            h.parts[#h.parts + 1] = h.glow
            Chrome.ApplyOpacity("cardGlow", h.glow)
        end
    end
    if m.hoverAlpha and m.hoverAlpha > 0 then
        local inner = m.inner or (spec.slice and spec.slice.left) or 0
        local fill = Ctl().AddHoverFill(frame, { alpha = m.hoverAlpha })
        fill:ClearAllPoints()
        fill:SetPoint("TOPLEFT", frame, "TOPLEFT", inner, -inner)
        fill:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -inner, -inner)
        fill:SetHeight(math.max(1, (h.header or frame:GetHeight() or 0) - 2 * inner))
        h.hoverFill = fill
        h.parts[#h.parts + 1] = fill
    end
    h.hoverWins = true
    h.paint = function()
        if h.glow then h.glow:SetShown((h.open or h.selected) and not h.disabled) end
        if h.hoverFill then h.hoverFill:SetShown(h.hover and not h.disabled) end
        if h.art then
            h.art:SetDesaturated(h.disabled)
            h.art:ApplyOpacity("cardBorder", "cardFill", h.disabled and m.disabledAlpha or 1)
        end
    end
end

function Chrome.Backdrop(role, frame, opts)
    opts = opts or {}
    local spec = Chrome.Spec(role)
    local h = setmetatable({
        role = role, frame = frame, spec = spec, label = opts.label, header = opts.header,
        hover = false, selected = false, disabled = false, open = false,
        inset = 0, hoverWins = false, hoverOverOpen = true,
    }, BackdropMT)

    local flat = Chrome.FLAT[role] or {}
    local variant = opts.variant and (spec[opts.variant] or flat[opts.variant])
    h.labelColors = (variant and variant.labelColors) or spec.labelColors or flat.labelColors

    if spec.kind == "atlas" then
        AtlasParts(h, frame, spec)
    elseif spec.kind == "sliced" then
        SlicedParts(h, frame, spec)
    elseif spec.kind == "card" then
        CardParts(h, frame, spec)
    elseif Flat[role] then
        Flat[role](h, frame, spec)
    else
        h.parts = {}
        h.paint = function() end
    end
    if spec.hoverOverSelected ~= nil then h.hoverWins = spec.hoverOverSelected and true or false end
    if spec.hoverOverOpen ~= nil then h.hoverOverOpen = spec.hoverOverOpen and true or false end
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
    if kind == "card" then
        local glow = type(spec.glow) == "table" and spec.glow.atlas
        return kind .. " " .. tostring(spec.atlas or spec.texture) .. (glow and (" glow=" .. glow) or "")
    end
    if kind == "nineSlice" then
        return kind .. " " .. tostring(spec.layout) .. (spec.textureKit and (" / " .. spec.textureKit) or "")
    end
    if kind == "glyph" then
        local names = {}
        for name, glyph in pairs(spec.glyphs or {}) do
            local art = type(glyph) == "table" and (glyph.atlas or glyph.texture) or glyph
            names[#names + 1] = name .. "=" .. tostring(art)
        end
        table.sort(names)
        return kind .. " " .. table.concat(names, " ")
    end
    if kind == "atlas" or kind == "sliced" then
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

--------------------------------------------------------------------------------
-- Opacity tuning
--------------------------------------------------------------------------------

-- Every piece the draw code applies, in the order the listing prints them
Chrome.PIECES = {
    "windowBorder", "windowFill", "titleStreaks", "portrait",
    "pickerBorder", "pickerFill", "pickerStreaks",
    "pageStreaks", "pageTopBorder", "pageBorder", "pageFill",
    "navColumn", "navDivider", "cardBorder", "cardFill", "cardGlow",
    "navRowHover", "navRowSelected",
    "sectionHeader", "tab", "buttonBorder", "buttonFill", "closeButton", "scrollTrack", "scrollThumb",
    "inputField", "searchField",
    "editSelectionBorder", "editSelectionFill", "editSelectionGlow",
}

local function isPiece(name)
    for _, piece in ipairs(Chrome.PIECES) do
        if piece == name then return true end
    end
    return false
end

-- The listing is the skin's table as Lua, overrides folded in, so a look
-- found in game pastes back into the skin file.
local function DumpOpacity()
    local lines, push = addon.DebugLines()
    push("opacity = {")
    for _, piece in ipairs(Chrome.PIECES) do
        local count = 0
        for _ in pairs(applied[piece] or {}) do count = count + 1 end
        push(string.format("    %-14s = %.2f,  -- %d regions%s", piece, Chrome.Opacity(piece), count,
            opacityOverrides[piece] and ", overridden this session" or ""))
    end
    push("},")
    addon.DebugShowWindow("Chrome opacity", lines)
end

local opacityCommand = {
    name = "opacity",
    help = "Panel art opacity by piece; 'opacity <piece> <0-1>' retunes the open panel, 'opacity reset' drops the session values",
    usage = { "opacity lists every piece; piece names are case-sensitive (windowBorder, pageFill, cardFill)" },
    handler = function(sub, rest)
        local name = rest and rest[1]
        if not name or name == "" then return DumpOpacity() end
        if sub == "reset" then
            for piece in pairs(opacityOverrides) do opacityOverrides[piece] = nil end
            Chrome.RefreshOpacity()
            return DumpOpacity()
        end
        local value = tonumber(rest[2])
        if not isPiece(name) or not value then return addon.Commands.USAGE end
        opacityOverrides[name] = math.max(0, math.min(1, value))
        Chrome.RefreshOpacity(name)
    end,
}
-- The same command at the top level and under debug
addon:RegisterSlashCommand(opacityCommand)
addon:RegisterDebugCommand(opacityCommand)
