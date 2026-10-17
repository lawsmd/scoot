--------------------------------------------------------------------------------
-- ui/v2/editmode/DynamicTabs.lua
-- The off-screen tabs of the dynamic view of Edit Mode. A frame whose dynamic
-- record names an edge (Move Off Screen in its dialog) is really off-screen
-- while the view holds, so a tab on that edge stands in for it: the frame's
-- name and an arrow pointing out of the screen, at the coordinate along the
-- edge where the frame stands in its regular layout. A click on the tab
-- selects the frame, and the library's dialog then attaches to the tab
-- (Dialog.lua) instead of the off-screen box, so Opacity, Scale and the
-- Move Off Screen controls stay in reach. The tab does not drag.
--
-- Drawn from the skin's `editTab` role, flat: the black fill, the copper
-- edge, and the ember in additive bands outside it, held lit rather than
-- pulsing. Shown only while the view holds; DynamicView.lua's handlers for
-- core/dynamiclayouts/view.lua call Sync on entry, on a participation change
-- and on a record write, and HideAll on exit.
--------------------------------------------------------------------------------

local addonName, addon = ...

local EM = addon.EditMode
local DynamicTabs = {}
EM.DynamicTabs = DynamicTabs

local TAB_STRATA = "DIALOG"
local ARROW_TEXTURE = "Interface\\Buttons\\Arrow-Down-Up"
-- The art points down; SetRotation turns it counterclockwise.
local ROTATION = { BOTTOM = 0, RIGHT = math.pi / 2, TOP = math.pi, LEFT = -math.pi / 2 }
local FALLBACK_ACCENT = { 1, 0.4, 0.12 }

local free = {}        -- built tabs not in use
local shown = {}       -- adapter id -> tab
local bySelection = setmetatable({}, { __mode = "k" })  -- selection -> tab

local function DL() return addon.DynamicLayouts end

local function Spec()
    local C = addon.UI and addon.UI.Chrome
    local spec = C and C.Spec and C.Spec("editTab")
    return (type(spec) == "table" and spec) or {}, C
end

-- The skin's box numbers, with every field present.
local function Metrics()
    local spec = Spec()
    local m = spec.metrics or {}
    return {
        height = m.height or 28, padX = m.padX or 12, arrow = m.arrow or 16,
        gap = m.gap or 6, edge = m.edge or 2, inset = m.inset or 4,
    }
end

local function rgb(C, value, fallback)
    if value and C and C.Color then return C.Color(value) end
    local t = fallback or FALLBACK_ACCENT
    return t[1], t[2], t[3], t[4] or 1
end

local function selectionFor(id)
    local found
    local dl = DL()
    EM.ForEachPositionable(function(frame, selection)
        if not found and selection and dl.IdForFrame(frame) == id then found = selection end
    end)
    return found
end

--------------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------------

-- A rectangle outline of `width` on `frame`, `out` units outside its rect.
local function Outline(frame, layer, out, width)
    local lines = {}
    for i = 1, 4 do lines[i] = frame:CreateTexture(nil, layer) end
    local top, bottom, left, right = lines[1], lines[2], lines[3], lines[4]
    top:SetPoint("TOPLEFT", -out, out)
    top:SetPoint("TOPRIGHT", out, out)
    top:SetHeight(width)
    bottom:SetPoint("BOTTOMLEFT", -out, -out)
    bottom:SetPoint("BOTTOMRIGHT", out, -out)
    bottom:SetHeight(width)
    left:SetPoint("TOPLEFT", -out, out - width)
    left:SetPoint("BOTTOMLEFT", -out, -out + width)
    left:SetWidth(width)
    right:SetPoint("TOPRIGHT", out, out - width)
    right:SetPoint("BOTTOMRIGHT", out, -out + width)
    right:SetWidth(width)
    return lines
end

local function Paint(tab)
    local spec, C = Spec()
    local glow = spec.glow or {}
    local selection = tab.id and selectionFor(tab.id)
    local alpha
    if selection and selection.isSelected then
        alpha = glow.selected or 1
    elseif tab:IsMouseOver() then
        alpha = glow.hover or 0.9
    else
        alpha = glow.rest or 0.7
    end
    local r, g, b = rgb(C, spec.accent)
    for _, band in ipairs(tab.glow) do
        for _, line in ipairs(band.lines) do
            line:SetColorTexture(r, g, b, band.alpha * alpha)
        end
    end
end

local function BuildTab()
    local spec, C = Spec()
    local m = Metrics()
    local tab = CreateFrame("Button", nil, UIParent)
    tab:SetFrameStrata(TAB_STRATA)
    if spec.level then tab:SetFrameLevel(spec.level) end
    tab:SetHeight(m.height)
    tab:RegisterForClicks("LeftButtonUp")

    local fill = tab:CreateTexture(nil, "BACKGROUND")
    fill:SetAllPoints()
    fill:SetColorTexture(rgb(C, spec.fill, { 0, 0, 0, 0.85 }))

    local er, eg, eb = rgb(C, spec.edge)
    for _, line in ipairs(Outline(tab, "BORDER", 0, m.edge)) do
        line:SetColorTexture(er, eg, eb, 1)
    end

    tab.glow = {}
    for _, band in ipairs((spec.glow and spec.glow.bands) or { { out = 2, alpha = 1 } }) do
        local lines = Outline(tab, "ARTWORK", band.out, m.edge)
        for _, line in ipairs(lines) do line:SetBlendMode("ADD") end
        tab.glow[#tab.glow + 1] = { lines = lines, alpha = band.alpha }
    end

    local tr, tg, tb = rgb(C, spec.text, { 1, 0.86, 0.7 })
    local label = tab:CreateFontString(nil, "OVERLAY")
    local theme = addon.UI and addon.UI.Theme
    if theme and theme.ApplyFont then theme:ApplyFont(label, "header", spec.textSize) end
    if not label:GetFont() then label:SetFontObject(GameFontNormal) end
    label:SetTextColor(tr, tg, tb, 1)
    label:SetPoint("LEFT", m.padX, 0)
    tab.label = label

    local arrow = tab:CreateTexture(nil, "OVERLAY")
    arrow:SetTexture(ARROW_TEXTURE)
    arrow:SetSize(m.arrow, m.arrow)
    arrow:SetPoint("LEFT", label, "RIGHT", m.gap, 0)
    arrow:SetVertexColor(tr, tg, tb, 1)
    tab.arrow = arrow

    tab:SetScript("OnClick", function(self) DynamicTabs.Select(self.id) end)
    tab:SetScript("OnEnter", Paint)
    tab:SetScript("OnLeave", Paint)
    return tab
end

--------------------------------------------------------------------------------
-- Placement
--------------------------------------------------------------------------------

-- On the edge, at the frame's coordinate along it, kept whole on screen.
local function Place(tab, edge, cx, cy)
    local m = Metrics()
    local W, H = UIParent:GetSize()
    tab:ClearAllPoints()
    if edge == "BOTTOM" or edge == "TOP" then
        local limit = math.max(0, W / 2 - tab:GetWidth() / 2 - m.inset)
        local x = math.max(-limit, math.min(limit, cx))
        tab:SetPoint(edge, UIParent, edge, x, (edge == "BOTTOM") and m.inset or -m.inset)
    else
        local limit = math.max(0, H / 2 - m.height / 2 - m.inset)
        local y = math.max(-limit, math.min(limit, cy))
        tab:SetPoint(edge, UIParent, edge, (edge == "LEFT") and m.inset or -m.inset, y)
    end
end

local function Release(id)
    local tab = shown[id]
    if not tab then return end
    shown[id] = nil
    if tab.selection then bySelection[tab.selection] = nil end
    tab.id, tab.selection, tab.edge = nil, nil, nil
    tab:Hide()
    free[#free + 1] = tab
end

local function Show(id, edge)
    local dl = DL()
    local cx, cy = dl.BaseCenter(id)
    if not cx then
        Release(id)
        return
    end
    local tab = shown[id]
    if not tab then
        tab = table.remove(free) or BuildTab()
        shown[id] = tab
    end
    if tab.selection then bySelection[tab.selection] = nil end
    local st = dl.Get(id)
    local m = Metrics()
    tab.id, tab.edge = id, edge
    tab.selection = selectionFor(id)
    if tab.selection then bySelection[tab.selection] = tab end
    tab.label:SetText(st and st.def.label or id)
    tab.arrow:SetRotation(ROTATION[edge] or 0)
    tab:SetWidth(m.padX + tab.label:GetStringWidth() + m.gap + m.arrow + m.padX)
    Place(tab, edge, cx, cy)
    Paint(tab)
    tab:Show()
end

--------------------------------------------------------------------------------
-- API
--------------------------------------------------------------------------------

--- One tab per participating frame with an off-screen edge, while the view
--- holds; every other tab hides.
function DynamicTabs.Sync()
    local dl = DL()
    local view = dl and dl.View
    if not (view and view.IsActive and view.IsActive()) then
        DynamicTabs.HideAll()
        return
    end
    local want = {}
    for _, id in ipairs(dl.Ids()) do
        local edge = dl.IsParticipating(id) and dl.OffscreenEdge(id)
        if edge then want[id] = edge end
    end
    for id in pairs(shown) do
        if not want[id] then Release(id) end
    end
    for id, edge in pairs(want) do
        Show(id, edge)
    end
end

function DynamicTabs.HideAll()
    for id in pairs(shown) do Release(id) end
end

--- Repaint every tab's glow, for a selection that changed.
function DynamicTabs.Repaint()
    for _, tab in pairs(shown) do Paint(tab) end
end

--- The tab standing in for a selection, and its edge; nil when there is none.
function DynamicTabs.For(selection)
    local tab = selection and bySelection[selection]
    if tab and tab:IsShown() then return tab, tab.edge end
    return nil
end

--- Select the frame a tab stands for, as a click on its box does: the
--- library's own handler selects it and opens the dialog.
function DynamicTabs.Select(id)
    local selection = id and selectionFor(id)
    if not selection then return end
    local onDown = selection:GetScript("OnMouseDown")
    if onDown then onDown(selection, "LeftButton") end
    C_Timer.After(0, DynamicTabs.Repaint)
end
