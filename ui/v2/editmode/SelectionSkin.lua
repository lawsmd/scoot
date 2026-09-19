-- SelectionSkin.lua - Recolors the Edit Mode selection box for Scoot-owned frames
-- Blizzard bakes blue into the editmode-actionbar-* atlases, so the pieces are
-- desaturated first and then tinted with the Scoot accent.
local addonName, addon = ...

addon.EditMode = addon.EditMode or {}
addon.EditMode.SelectionSkin = {}
local SelectionSkin = addon.EditMode.SelectionSkin
local Brand = addon.EditMode.Brand

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

local PIECES = {
    "TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner",
    "TopEdge", "BottomEdge", "LeftEdge", "RightEdge", "Center",
}

-- Border reads as a crisp frame, center as a restrained wash. Colouring them
-- separately is why NineSlicePanelMixin's two setters are used instead of one
-- flat SetVertexColor, which would render as a solid green block.
local BORDER_ALPHA = { highlight = 0.75, selected = 1.00 }
local CENTER_ALPHA = { highlight = 0.18, selected = 0.32 }

local FALLBACK_BORDER_WIDTH = { highlight = 1, selected = 2 }
local PROBE_ATLAS = "editmode-actionbar-selected-NineSlice-Corner"

-- Overriding the label font defeats ShrinkUntilTruncate's measurement and
-- overflows narrow frames (Notes, small Custom Groups). Recolour only.
SelectionSkin.SKIN_LABEL_FONT = false

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

local fallbackParts = setmetatable({}, { __mode = "k" })
local probed = false

local function GetTheme()
    return addon.UI and addon.UI.Theme
end

--------------------------------------------------------------------------------
-- Desaturation
--------------------------------------------------------------------------------

local function Desaturate(tex)
    if not tex then return end
    if tex.SetDesaturation then
        pcall(tex.SetDesaturation, tex, 1)
    else
        pcall(tex.SetDesaturated, tex, true)
    end
end

-- IsDesaturated is secret-restricted in 12.0 (SecretReturnsForAspect =
-- Enum.SecretAspect.Desaturation), so both the call and the comparison have to
-- sit inside the pcall. An inconclusive result means "assume supported" - a read
-- restriction must never silently downgrade everyone to the fallback border.
local function ProbeDesaturationSupport()
    local f = CreateFrame("Frame")
    local t = f:CreateTexture(nil, "BACKGROUND")

    local applied = pcall(t.SetAtlas, t, PROBE_ATLAS, true)
    if not applied then return true end

    Desaturate(t)

    local ok, isDesaturated = pcall(function() return t:IsDesaturated() == true end)
    if not ok then return true end
    return isDesaturated
end

local function EnsureProbed()
    if probed then return end
    probed = true
    if not ProbeDesaturationSupport() then
        Brand.forceFallbackBorder = true
    end
end

--------------------------------------------------------------------------------
-- Fallback: hide Blizzard's nine-slice, draw a Scoot border
--------------------------------------------------------------------------------

local function GetFallbackParts(selection)
    local parts = fallbackParts[selection]
    if parts then return parts end

    parts = { edges = {} }

    local wash = selection:CreateTexture(nil, "BACKGROUND", nil, -8)
    wash:SetAllPoints()
    parts.wash = wash

    for _, key in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        parts.edges[key] = selection:CreateTexture(nil, "BORDER", nil, 1)
    end

    local glow = selection:CreateTexture(nil, "ARTWORK")
    glow:SetAllPoints()
    glow:SetBlendMode("ADD")
    glow:Hide()
    parts.glow = glow

    fallbackParts[selection] = parts
    return parts
end

local function LayoutFallbackEdges(parts, width)
    local e = parts.edges

    e.TOP:ClearAllPoints()
    e.TOP:SetPoint("TOPLEFT")
    e.TOP:SetPoint("TOPRIGHT")
    e.TOP:SetHeight(width)

    e.BOTTOM:ClearAllPoints()
    e.BOTTOM:SetPoint("BOTTOMLEFT")
    e.BOTTOM:SetPoint("BOTTOMRIGHT")
    e.BOTTOM:SetHeight(width)

    -- Inset vertically so the corners don't draw twice.
    e.LEFT:ClearAllPoints()
    e.LEFT:SetPoint("TOPLEFT", 0, -width)
    e.LEFT:SetPoint("BOTTOMLEFT", 0, width)
    e.LEFT:SetWidth(width)

    e.RIGHT:ClearAllPoints()
    e.RIGHT:SetPoint("TOPRIGHT", 0, -width)
    e.RIGHT:SetPoint("BOTTOMRIGHT", 0, width)
    e.RIGHT:SetWidth(width)
end

local function FallbackRecolor(selection, state)
    if NineSliceUtil and NineSliceUtil.SetLayoutShown then
        pcall(NineSliceUtil.SetLayoutShown, selection, false)
        if selection.MouseOverHighlight then
            pcall(NineSliceUtil.SetLayoutShown, selection.MouseOverHighlight, false)
        end
    end

    local r, g, b = addon.GetAccentColorRGB()
    local parts = GetFallbackParts(selection)
    local width = FALLBACK_BORDER_WIDTH[state] or 1

    LayoutFallbackEdges(parts, width)
    for _, tex in pairs(parts.edges) do
        tex:SetColorTexture(r, g, b, BORDER_ALPHA[state] or 0.75)
    end
    parts.wash:SetColorTexture(r, g, b, CENTER_ALPHA[state] or 0.18)
    parts.glow:SetColorTexture(r, g, b, 0.25)
end

--------------------------------------------------------------------------------
-- Skin path: the editSelection chrome role draws the box
--------------------------------------------------------------------------------
-- A skin that declares editSelection as a nine-slice replaces Blizzard's blue
-- box with its own border, fill and glow. Every region here belongs to the
-- LibEditMode selection frame, which is a child of one of the addon's frames.

local chromeParts = setmetatable({}, { __mode = "k" })

local function SelectionSpec()
    local Chrome = addon.UI and addon.UI.Chrome
    local spec = Chrome and Chrome.Spec and Chrome.Spec("editSelection")
    if spec and spec.kind == "nineSlice" then return spec, Chrome end
    return nil
end

-- A frame's own size, or nil when the read is unusable. Scoot's positionables
-- are addon frames, but one anchored to a secret-restricted region can answer
-- secret, so the value is screened before it reaches any arithmetic.
local function SizeOf(region)
    local ok, w, h = pcall(region.GetSize, region)
    if not ok or type(w) ~= "number" or type(h) ~= "number" then return nil end
    if issecretvalue and (issecretvalue(w) or issecretvalue(h)) then return nil end
    return w, h
end

-- The window's corners need room; a frame under spec.minSize takes spec.small.
-- Read off the element rather than the padded box below, so growing the box can
-- never pick a layout whose corners then ask for more growth.
local function BorderSpecFor(selection, spec, Chrome)
    if not (spec.minSize and spec.small) then return spec end
    local w, h = SizeOf(selection)
    if not w then return spec end
    if w >= spec.minSize and h >= spec.minSize then return spec end
    local small = Chrome.Resolve(spec.small, nil)
    return (small and small.kind == "nineSlice") and small or spec
end

-- The nine-slice's corner art sizes itself from its atlas, so the extent is read
-- off the built piece rather than declared per layout.
local function CornerExtent(border)
    local piece = border and border.TopLeftCorner
    if not piece then return 0, 0 end
    local w, h = SizeOf(piece)
    return w or 0, h or 0
end

-- How far the drawn box stands off the element on each axis. `pad.gap` is the
-- standoff every frame gets; an element shorter than the two corners plus that
-- gap grows the box further, split evenly on both sides, so the corners never
-- draw over each other.
local function OutsetFor(selection, spec, parts)
    local pad = spec.pad
    if not pad then return 0, 0 end
    local gap = pad.gap or 0
    local w, h = SizeOf(selection)
    if not w then return gap, gap end
    local cw, ch = parts.cornerW or 0, parts.cornerH or 0
    return math.max(gap, cw + gap - w / 2), math.max(gap, ch + gap - h / 2)
end

local function SetBlizzardBoxShown(selection, shown)
    if not (NineSliceUtil and NineSliceUtil.SetLayoutShown) then return end
    pcall(NineSliceUtil.SetLayoutShown, selection, shown)
    if selection.MouseOverHighlight then
        pcall(NineSliceUtil.SetLayoutShown, selection.MouseOverHighlight, shown)
    end
end

local function DropChromeParts(selection)
    local parts = chromeParts[selection]
    if not parts then return end
    if parts.pulse then parts.pulse:Stop() end
    if parts.border then parts.border:Destroy() end
    if parts.glowArt then parts.glowArt:Destroy() end
    if parts.glowHolder then parts.glowHolder:Hide() end
    if parts.fill then parts.fill:Hide() end
    if parts.box then
        parts.box:Hide()
        parts.box:SetParent(nil)
    end
    chromeParts[selection] = nil
end

-- Re-run on every recolor, so the box follows an element that changes size while
-- Edit Mode is open.
local function LayoutBox(selection, parts)
    local ox, oy = OutsetFor(selection, parts.spec, parts)
    parts.outX, parts.outY = ox, oy
    parts.box:ClearAllPoints()
    parts.box:SetPoint("TOPLEFT", selection, "TOPLEFT", -ox, oy)
    parts.box:SetPoint("BOTTOMRIGHT", selection, "BOTTOMRIGHT", ox, -oy)
end

local function BuildChromeParts(selection, spec, borderSpec, Chrome)
    local parts = { spec = spec, borderSpec = borderSpec }

    -- Border, fill and glow all hang on this rather than on the selection, so
    -- one outset moves the three together and the element keeps the whole
    -- selection frame as its hit area.
    local box = CreateFrame("Frame", nil, selection)
    box:SetFrameLevel(selection:GetFrameLevel())
    parts.box = box
    LayoutBox(selection, parts)

    if spec.fill and spec.fill.texture then
        local inset = spec.fill.inset or 0
        local fill = box:CreateTexture(nil, "BACKGROUND", nil, -8)
        fill:SetTexture(spec.fill.texture, "REPEAT", "REPEAT")
        fill:SetHorizTile(true)
        fill:SetVertTile(true)
        fill:SetPoint("TOPLEFT", inset, -inset)
        fill:SetPoint("BOTTOMRIGHT", -inset, inset)
        parts.fill = fill
    end

    parts.border = Chrome.NineSlice(box, borderSpec)
    -- The corner art is what the box has to clear, and it exists only once the
    -- layout is applied, so the measurement folds back into the anchors here.
    parts.cornerW, parts.cornerH = CornerExtent(parts.border)
    LayoutBox(selection, parts)

    local glow = spec.glow
    if glow then
        local out = glow.outset or 0
        -- The holder carries the piece opacity and the art inside it carries
        -- the pulse, so the two alphas multiply and neither overwrites the other.
        local holder = CreateFrame("Frame", nil, box)
        holder:SetPoint("TOPLEFT", -out, out)
        holder:SetPoint("BOTTOMRIGHT", out, -out)
        holder:SetFrameLevel(box:GetFrameLevel())
        local art = Chrome.NineSlice(holder, borderSpec)
        for _, name in ipairs(PIECES) do
            local piece = art[name]
            if piece and piece.SetBlendMode then piece:SetBlendMode("ADD") end
        end
        if glow.tint then art:SetBorderColor(Chrome.Color(glow.tint)) end

        local pulse = glow.pulse
        if pulse then
            local group = art:CreateAnimationGroup()
            group:SetLooping("BOUNCE")
            local alpha = group:CreateAnimation("Alpha")
            alpha:SetFromAlpha(pulse.from or 0.3)
            alpha:SetToAlpha(pulse.to or 0.7)
            alpha:SetDuration(pulse.duration or 1.4)
            alpha:SetSmoothing("IN_OUT")
            parts.pulse = group
        end
        parts.glowHolder, parts.glowArt = holder, art
    end

    chromeParts[selection] = parts
    return parts
end

local function PaintGlow(parts, state, hovered)
    local art, glow = parts.glowArt, parts.spec.glow
    if not art then return end
    if state == "selected" and parts.pulse then
        if not parts.pulse:IsPlaying() then parts.pulse:Play() end
        return
    end
    if parts.pulse then parts.pulse:Stop() end
    local rest = glow.highlight or 0.25
    art:SetAlpha(hovered and (glow.hover or math.min(1, rest * 2)) or rest)
end

local function ChromeRecolor(selection, state, spec, Chrome)
    local borderSpec = BorderSpecFor(selection, spec, Chrome)
    local parts = chromeParts[selection]
    if parts and (parts.spec ~= spec or parts.borderSpec ~= borderSpec) then
        DropChromeParts(selection)
        parts = nil
    end
    parts = parts or BuildChromeParts(selection, spec, borderSpec, Chrome)
    parts.state = state
    LayoutBox(selection, parts)

    SetBlizzardBoxShown(selection, false)

    local scale = (spec.scale and spec.scale[state]) or 1
    Chrome.ApplyOpacity("editSelectionBorder", parts.border, scale)
    if parts.fill then Chrome.ApplyOpacity("editSelectionFill", parts.fill, scale) end
    if parts.glowHolder then Chrome.ApplyOpacity("editSelectionGlow", parts.glowHolder, 1) end
    PaintGlow(parts, state, selection.instructionsShown and true or false)
end

--------------------------------------------------------------------------------
-- Primary path
--------------------------------------------------------------------------------

local function Recolor(selection, state)
    if not selection then return end
    state = state or "highlight"

    local spec, Chrome = SelectionSpec()
    if spec then
        ChromeRecolor(selection, state, spec, Chrome)
        return
    end
    -- A skin switch back to the flat look: drop the skin's parts and return
    -- Blizzard's pieces for the tint below.
    if chromeParts[selection] then
        DropChromeParts(selection)
        SetBlizzardBoxShown(selection, true)
    end

    if Brand.forceFallbackBorder then
        FallbackRecolor(selection, state)
        return
    end

    for _, name in ipairs(PIECES) do
        Desaturate(selection[name])
    end

    local r, g, b = addon.GetAccentColorRGB()
    if selection.SetBorderColor then
        selection:SetBorderColor(r, g, b, BORDER_ALPHA[state] or 0.75)
    end
    if selection.SetCenterColor then
        selection:SetCenterColor(r, g, b, CENTER_ALPHA[state] or 0.18)
    end
end

local function RecolorMouseOverHighlight(selection)
    local hi = selection and selection.MouseOverHighlight
    if not hi then return end

    -- Laid out once in the template's OnLoad and never re-applied, so a single
    -- pass at registration is enough. ADD blend over desaturated art gives a
    -- clean accent glow.
    for _, name in ipairs(PIECES) do
        Desaturate(hi[name])
    end
    if hi.SetVertexColor then
        local r, g, b = addon.GetAccentColorRGB()
        pcall(hi.SetVertexColor, hi, r, g, b, 1)
    end
end

local function RecolorLabel(selection)
    local label = selection and selection.Label
    if not label then return end

    local r, g, b = addon.GetAccentColorRGB()
    local spec, Chrome = SelectionSpec()
    if spec and spec.labelColor then
        r, g, b = Chrome.Color(spec.labelColor)
    end
    label:SetTextColor(r, g, b, 1)

    if SelectionSkin.SKIN_LABEL_FONT then
        local theme = GetTheme()
        if theme and theme.GetFont then
            pcall(label.SetFont, label, theme:GetFont("HEADER"), 13, "OUTLINE")
        end
    end
end

--------------------------------------------------------------------------------
-- Public
--------------------------------------------------------------------------------

function SelectionSkin.Apply(selection)
    if not selection or selection._emSkinned then return end
    selection._emSkinned = true

    EnsureProbed()

    -- The selection's own nine-slice pieces don't exist yet: the Edit Mode mixin
    -- overrides NineSlicePanelMixin:OnLoad, so no ApplyLayout runs on `self`
    -- until the first resetSelection() on Edit Mode enter. The hooks below catch that.
    RecolorMouseOverHighlight(selection)

    hooksecurefunc(selection, "ShowHighlighted", function(self)
        Recolor(self, "highlight")
    end)
    hooksecurefunc(selection, "ShowSelected", function(self)
        Recolor(self, "selected")
    end)

    -- Single choke point for all three label callers. Runs after the shrink
    -- logic, which resets text colour via SetFontObject, so this always wins.
    hooksecurefunc(selection, "UpdateLabelVisibility", RecolorLabel)

    if Brand.forceFallbackBorder then
        hooksecurefunc(selection, "ShowEditInstructions", function(self, shown)
            local parts = fallbackParts[self]
            if parts and parts.glow then parts.glow:SetShown(shown and true or false) end
        end)
    end

    -- Hover on the skin's box: the glow brightens while the cursor is over an
    -- unselected frame. A no-op while the flat look draws.
    hooksecurefunc(selection, "ShowEditInstructions", function(self, shown)
        local parts = chromeParts[self]
        if parts then PaintGlow(parts, parts.state, shown and true or false) end
    end)

    selection:HookScript("OnHide", function()
        local tooltip = addon.EditMode.Tooltip
        if tooltip and tooltip.Hide then tooltip.Hide() end
    end)
end

--- How far the drawn box stands off the element, for a caller placing something
--- beside it. 0, 0 while the flat look draws: that border sits on the edges.
function SelectionSkin.Outset(selection)
    local parts = selection and chromeParts[selection]
    if not parts then return 0, 0 end
    return parts.outX or 0, parts.outY or 0
end

--- Re-apply to every registered frame. Used by the theme subscription and by
--- the /scoot debug skin override.
function SelectionSkin.RefreshAll()
    if not Brand or not Brand.ForEach then return end
    Brand:ForEach(function(_, entry)
        local selection = entry.selection
        if selection then
            Recolor(selection, selection.textureShown or "highlight")
            RecolorMouseOverHighlight(selection)
            RecolorLabel(selection)
        end
    end)
end

local theme = addon.UI and addon.UI.Theme
if theme and theme.Subscribe then
    theme:Subscribe("ScootEditModeSelection", function()
        SelectionSkin.RefreshAll()
    end)
end
