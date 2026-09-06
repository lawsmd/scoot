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
-- Primary path
--------------------------------------------------------------------------------

local function Recolor(selection, state)
    if not selection then return end
    state = state or "highlight"

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
    if not selection or selection._scootSkinned then return end
    selection._scootSkinned = true

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

    selection:HookScript("OnHide", function()
        local tooltip = addon.EditMode.Tooltip
        if tooltip and tooltip.Hide then tooltip.Hide() end
    end)
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
