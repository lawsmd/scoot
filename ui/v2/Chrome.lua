-- Chrome.lua - chrome descriptors: how each surface of the settings panel is
-- drawn, declared per role by the active skin and resolved here against the
-- running client.
--
-- A skin's chrome table holds one descriptor per role: window, titleBar,
-- closeButton, button, resizeGrip, scrollBar, tab, tabBody, sectionHeader,
-- sectionBody, navRow, dropdown. A descriptor names a kind and what that kind
-- needs:
--   flat       the framework's own draw (CreateBorder, AddBackground,
--              AddHoverFill) with numbers from the skin metrics
--   nineSlice  NineSliceUtil.ApplyLayout on a child frame: layout, textureKit
--   atlas      one atlas per state: normal, hover, selected, disabled, pressed
--   template   a Blizzard frame template supplies the art and part of the
--              method surface: template, joined with the caller's own
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
--   Chrome.Available(spec)           whether this client can draw it
--   Chrome.Invalidate()              forget resolutions; Skin.SetActive calls it
--   Chrome.Color(token)              r, g, b, a for a color token or a literal
--   Chrome.CreateFrame(role, frameType, name, parent, extraTemplates)
--                                    a frame on the role's template, if it has one
--   Chrome.NineSlice(frame, spec)    the nine-slice child a nineSlice role draws
--   Chrome.Dump(push)                one line per role for the skin listing
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.Chrome = addon.UI.Chrome or {}
local Chrome = addon.UI.Chrome

Chrome.ROLES = {
    "window", "titleBar", "closeButton", "button", "resizeGrip", "scrollBar",
    "tab", "tabBody", "sectionHeader", "sectionBody", "navRow", "dropdown",
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
    button        = { kind = "flat" },
    resizeGrip    = { kind = "flat" },
    scrollBar     = { kind = "flat" },
    tab           = { kind = "flat" },
    tabBody       = { kind = "flat" },
    sectionHeader = { kind = "flat", glyphs = { expanded = "\226\150\188", collapsed = "\226\150\182" } },
    sectionBody   = { kind = "flat" },
    navRow        = { kind = "flat" },
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
        return true
    elseif kind == "atlas" then
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

function Chrome.Spec(role)
    local hit = resolved[role]
    if hit then return hit end
    local spec = Chrome.Declared(role)
    local depth = 0
    while spec and not Chrome.Available(spec) and depth < 8 do
        spec = spec.fallback
        depth = depth + 1
    end
    if not spec or not Chrome.Available(spec) then
        spec = Chrome.FLAT[role] or { kind = "flat" }
    end
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
    local spec = Chrome.Spec(role)
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
-- Listing
--------------------------------------------------------------------------------

local function describe(spec)
    if type(spec) ~= "table" then return "nil" end
    local kind = spec.kind or "?"
    if kind == "template" then return kind .. " " .. tostring(spec.template) end
    if kind == "nineSlice" then
        return kind .. " " .. tostring(spec.layout) .. (spec.textureKit and (" / " .. spec.textureKit) or "")
    end
    if kind == "atlas" then
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
