-- DynamicView.lua - The Dynamic Layouts strip on Blizzard's Edit Mode box, the
-- panel it grows into, and the holds, the shield and the screen border of the
-- dynamic view
--
-- The strip is a frame of this addon's own on the top edge of
-- EditModeManagerFrame, drawn as one box with it: the box's top corners, top
-- edge and fill go to alpha 0 while the strip stands on it, the strip's art
-- (the same Dialog nine-slice) drops its bottom pieces and runs its side
-- edges down to meet the box's, and its fill runs the whole box, under the
-- box's own pieces. Nothing on the box is written: it is anchored to, its regions take an
-- alpha, its OnShow and OnHide are hooked, the touches Dialog.lua already
-- makes, one of its methods takes a post-hook, and a drag on the strip moves
-- it through its own StartMoving, so the two stay one box. The collapsed
-- strip stands a strata under the box, so the box's help plate and close
-- button, which sit on the corners the strip's art runs over, draw over it.
-- The strip's one button opens the view (core/dynamiclayouts/view.lua).
--
-- While the view holds, Blizzard's Edit Mode goes out of sight: the box, with
-- its grid and its magnetism lines under it, and its settings dialog take
-- alpha 0, and its selection boxes hide (a widget call; that template has no
-- script behind Hide or Show). Blizzard shows them again from
-- ClearSelectedSystem, which the library calls on every click of an
-- addon-owned box, so a post-hook on it runs the hide again at once. The strip grows
-- down from the box's top edge into the panel, wider than the box by an
-- outset each side for the two columns of frames: the requirements, the
-- transition speed, the frames that take part, and Done. Done puts every
-- Blizzard piece back at once. The other ends of the view put the alphas back
-- and re-show the selections only if Edit Mode still holds a frame later,
-- since Blizzard's own exit has hidden them for good by then.
--
-- The holds are transparent frames that take the mouse over the rects the
-- view has taken off the screen and nowhere else, so the world stays free
-- for the camera: the invisible box and Blizzard's invisible dialog, every
-- Blizzard selection box the view hid that was visible, and every addon-owned
-- box it faded. They stand in the DIALOG strata under the view's boxes, the
-- branded dialog (raised a strata for the view) and the strip. The shield is
-- one full-screen frame over everything, up for the transition window only.
-- The border is four lines in the view's color around the screen.
local addonName, addon = ...

addon.EditMode = addon.EditMode or {}
addon.EditMode.DynamicView = {}
local DynamicView = addon.EditMode.DynamicView

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

local OWNER = "dynamicLayoutsView"

-- Kept off addon.UI.Skin.Metrics: strip-only sizes, cut to the 510-unit Edit
-- Mode box the strip stands on, as Dialog.lua's and Mirror.lua's are cut to
-- their boxes.
local STRIP_H      = 52    -- 44 until the fourth run, which pressed the centered button to the top border
local PAD          = 14
local GAP          = 8
local TITLE_SIZE   = 19    -- the panel's title
local SECTION_SIZE = 15    -- the panel's section headers
local TEXT_SIZE    = 13
local BTN_H        = 26
local BUTTON_W     = 200
local DONE_W       = 120
local ROW_H        = 36    -- Controls:CreateToggle's row
local SLIDER_ROW_H = 40    -- Controls:CreateSlider's row
local GLOW_IN      = 4     -- the halo's inset from the button's edge, inside its border
local PANEL_OUTSET = 45    -- the panel's reach past each side of the box
local NOTE_W       = 300   -- the requirements sentence's wrap width, two lines over the checkboxes
local BORDER_W     = 4
local FADE         = 0.3

-- Draw order, in the DIALOG strata unless said. Blizzard's box stands at the
-- bottom of it with its buttons at 2, its layout dialogs at 100 and its
-- settings dialog at 200, where the library's dialog stands too. The
-- collapsed strip stands in the HIGH strata, over every selection box and
-- under the box itself, whose help plate and close button sit on the corners
-- the strip's art runs over. In the view the holds stand over the box and
-- Blizzard's dialog; the participating boxes keep their template's 1000 over
-- them (core/dynamiclayouts/view.lua), the library's dialog rises a strata
-- (Dialog.SetRaised), the strip goes over the boxes, and for the transition
-- the shield rises over all of it.
local STRIP_STRATA     = "HIGH"
local STRIP_LEVEL      = 50
local STRIP_LEVEL_VIEW = 2000
local HOLD_LEVEL       = 250
local BORDER_LEVEL     = 255
local SHIELD_LEVEL     = 900   -- FULLSCREEN_DIALOG

local TRIGGER_ROWS = {
    { name = "inCombat",       label = "Not in combat" },
    { name = "targetAcquired", label = "Do not have a target" },
    { name = "insideInstance", label = "Not in an instance" },
}

-- The pieces of the box's border the strip stands in for while it stands on
-- the box: the three top pieces, and the fill, since the strip draws under
-- the box and the box's fill would cover the inner half of the strip's side
-- edges in the band the box's hidden corners left. The strip's own bottom
-- pieces hide while it is collapsed.
local HELD_PIECES   = { "TopLeftCorner", "TopRightCorner", "TopEdge", "Bg" }
local BOTTOM_PIECES = { "BottomLeftCorner", "BottomRightCorner", "BottomEdge" }

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

local strip, shield, border
local panel = nil       -- the panel's fixed controls, built once
local frameRows = {}    -- one checkbox row per adapter, rebuilt on every entry
local holds = nil       -- the mouse holds, an indexed pool
local holdCount = 0

local topPiecesHeld = false      -- the box's top pieces at alpha 0 under the strip
local alphaHeld = false          -- the box and Blizzard's dialog at alpha 0 for the view
local heldSelections = {}        -- Blizzard selection box -> whether it was visible when hidden
local reshowOwed = false         -- a re-show that waited for lockdown to end

local function Chrome() return addon.UI and addon.UI.Chrome end
local function Controls() return addon.UI and addon.UI.Controls end
local function Theme() return addon.UI and addon.UI.Theme end

local function View()
    local DL = addon.DynamicLayouts
    return DL and DL.View or nil
end

local function Manager()
    return _G.EditModeManagerFrame
end

local function BlizzardDialog()
    return _G.EditModeSystemSettingsDialog
end

local function Spec()
    local C = Chrome()
    return (C and C.Spec and C.Spec("editStrip")) or { kind = "flat" }
end

local function Accent()
    local spec, C = Spec(), Chrome()
    if spec.accent and C and C.Color then return C.Color(spec.accent) end
    return 1, 0.4, 0.12, 1
end

local function ApplyFont(fs, role, size)
    local theme = Theme()
    if theme and theme.ApplyFont then theme:ApplyFont(fs, role, size) end
end

local function PrimaryColor()
    local theme = Theme()
    if theme and theme.GetPrimaryTextColor then return theme:GetPrimaryTextColor() end
    return 1, 1, 1, 1
end

local function SetPiecesAlpha(container, names, alpha)
    if type(container) ~= "table" then return end
    for _, name in ipairs(names) do
        local piece = container[name]
        if piece and piece.SetAlpha then pcall(piece.SetAlpha, piece, alpha) end
    end
end

local function IsShown(frame)
    if not (frame and frame.IsShown) then return false end
    local ok, shown = pcall(frame.IsShown, frame)
    return ok and shown == true
end

local function IsVisible(frame)
    if not (frame and frame.IsVisible) then return false end
    local ok, visible = pcall(frame.IsVisible, frame)
    return ok and visible == true
end

--------------------------------------------------------------------------------
-- Blizzard's pieces
--------------------------------------------------------------------------------

-- The box's top corners, top edge and fill, under the strip's own while it
-- stands on the box, and back when the strip leaves.
local function HoldTopPieces(on)
    local mgr = Manager()
    if not (mgr and mgr.Border) then return end
    if on == topPiecesHeld then return end
    topPiecesHeld = on
    SetPiecesAlpha(mgr.Border, HELD_PIECES, on and 0 or 1)
end

-- Every shown Blizzard selection box hidden and remembered, with whether it
-- was visible: a parked system's box is shown on a hidden parent, and gets
-- no hold. The pass runs again whenever Blizzard shows them back under the
-- view, and a box already remembered keeps its first answer.
local function HoldSelections()
    local mgr = Manager()
    local systems = mgr and mgr.registeredSystemFrames
    if type(systems) ~= "table" then return end
    for _, system in ipairs(systems) do
        local sel = type(system) == "table" and system.Selection
        if sel and IsShown(sel) then
            local visible = IsVisible(sel)
            if pcall(sel.Hide, sel) and heldSelections[sel] == nil then
                heldSelections[sel] = visible
            end
        end
    end
end

-- The view: the box and Blizzard's settings dialog at alpha 0, and the
-- selection boxes hidden.
local function HoldBlizzardPieces()
    local mgr = Manager()
    if mgr then pcall(mgr.SetAlpha, mgr, 0) end
    local dlg = BlizzardDialog()
    if dlg and dlg.SetAlpha then pcall(dlg.SetAlpha, dlg, 0) end
    alphaHeld = true
    wipe(heldSelections)
    HoldSelections()
end

local function ReleaseBlizzardAlpha()
    if not alphaHeld then return end
    alphaHeld = false
    local mgr = Manager()
    if mgr then pcall(mgr.SetAlpha, mgr, 1) end
    local dlg = BlizzardDialog()
    if dlg and dlg.SetAlpha then pcall(dlg.SetAlpha, dlg, 1) end
end

local function ReshowSelections()
    reshowOwed = false
    for sel in pairs(heldSelections) do
        pcall(sel.Show, sel)
    end
    wipe(heldSelections)
end

-- After an end that was not Done: Blizzard's own exit hides every selection
-- for good, so the re-show runs only while Edit Mode still holds, and out of
-- lockdown, where it waits for regen.
local function ReshowSelectionsIfEditing()
    if next(heldSelections) == nil then return end
    local EM = addon.EditMode
    if not (EM and EM.IsEditing and EM.IsEditing()) then
        wipe(heldSelections)
        reshowOwed = false
        return
    end
    if InCombatLockdown() then
        reshowOwed = true
        return
    end
    ReshowSelections()
end

-- The library's dialog shares the DIALOG strata with the holds, so it rises
-- a strata for the view (ui/v2/editmode/Dialog.lua).
local function RaiseLibraryDialog(on)
    local D = addon.EditMode.Dialog
    if D and D.SetRaised then D.SetRaised(on) end
end

--------------------------------------------------------------------------------
-- The holds
--------------------------------------------------------------------------------

local function BuildHolds()
    if holds then return end
    holds = addon.Pool.NewIndexed(function()
        local hold = CreateFrame("Frame", nil, UIParent)
        hold:SetFrameStrata("DIALOG")
        hold:SetFrameLevel(HOLD_LEVEL)
        hold:EnableMouse(true)
        hold:Hide()
        return hold
    end, function(hold)
        hold:Hide()
        hold:ClearAllPoints()
    end)
end

local function Cover(target)
    holdCount = holdCount + 1
    local hold = holds:Get(holdCount)
    hold:ClearAllPoints()
    hold:SetAllPoints(target)
    hold:Show()
end

local function ReleaseHolds()
    if holds then holds:HideFrom(1) end
    holdCount = 0
end

-- One hold per rect the view has taken off the screen: the box, Blizzard's
-- dialog while it is shown, the Blizzard selection boxes that were visible,
-- and the faded addon-owned boxes whose frames are on screen. Anchors only.
local function SyncHolds()
    ReleaseHolds()
    if not (alphaHeld and holds) then return end
    local mgr, dlg = Manager(), BlizzardDialog()
    if mgr then Cover(mgr) end
    if IsShown(dlg) then Cover(dlg) end
    for sel, visible in pairs(heldSelections) do
        if visible then Cover(sel) end
    end
    local V = View()
    if V and V.ForEachFadedBox then
        V.ForEachFadedBox(function(sel)
            if IsVisible(sel) then Cover(sel) end
        end)
    end
end

--------------------------------------------------------------------------------
-- The strip
--------------------------------------------------------------------------------

local function BuildStrip()
    if strip then return strip end
    local mgr, C, Ctl = Manager(), Chrome(), Controls()
    if not (mgr and C and Ctl and Ctl.CreateButton) then return nil end
    local spec = Spec()

    strip = CreateFrame("Frame", nil, UIParent)
    strip:SetFrameStrata(STRIP_STRATA)
    strip:SetFrameLevel(STRIP_LEVEL)
    strip:EnableMouse(true)
    strip:Hide()

    -- A drag on the strip, collapsed or grown into the panel, moves the box
    -- through the box's own movable flag and screen clamp, and the strip
    -- follows on its anchors. The box's own drag does the same from its own
    -- rect, which in the view is invisible under a hold.
    strip:RegisterForDrag("LeftButton")
    strip:SetScript("OnDragStart", function()
        local box = Manager()
        if box and box.StartMoving then pcall(box.StartMoving, box) end
    end)
    strip:SetScript("OnDragStop", function()
        local box = Manager()
        if box and box.StopMovingOrSizing then pcall(box.StopMovingOrSizing, box) end
    end)

    -- The art on a child of its own, so it can run past the strip's rect into
    -- the box while the strip's mouse area stays the strip: the box's own
    -- nine-slice over its black fill, or the flat border where the layout is
    -- missing.
    local art = CreateFrame("Frame", nil, strip)
    art:SetFrameLevel(strip:GetFrameLevel() + 1)
    strip._art = art
    if spec.kind == "nineSlice" and C.NineSlice then
        strip._border = C.NineSlice(art, spec)
    elseif Ctl.CreateBorder then
        strip._border = Ctl.CreateBorder(art, { thickness = 2 })
    end
    local cornerH = 0
    local corner = strip._border and strip._border.TopLeftCorner
    if corner and corner.GetHeight then
        local ok, h = pcall(corner.GetHeight, corner)
        if ok and type(h) == "number" then cornerH = h end
    end
    strip._cornerH = cornerH

    local fill = spec.fill or {}
    strip._inset = fill.inset or 4
    local fillTex = art:CreateTexture(nil, "BACKGROUND", nil, -6)
    local fr, fg, fb, fa = 0, 0, 0, 0.8
    if type(fill.color) == "table" and C.Color then fr, fg, fb, fa = C.Color(fill.color) end
    fillTex:SetColorTexture(fr, fg, fb, fa)
    strip._fill = fillTex

    -- The panel's frame, a level over the art: its strings and its rows draw
    -- on it, so the art's fill never covers them, which it did at the first
    -- run when the strings sat on the strip itself.
    local content = CreateFrame("Frame", nil, strip)
    content:SetFrameLevel(art:GetFrameLevel() + 1)
    content:SetAllPoints(strip)
    content:Hide()
    strip._content = content

    local btn = Ctl:CreateButton({
        parent = strip, text = "Edit Dynamic Layout", width = BUTTON_W, height = BTN_H, fontSize = 12,
        onClick = function()
            local V = View()
            if V then V.Enter() end
        end,
    })
    btn:ClearAllPoints()
    btn:SetPoint("CENTER", strip, "CENTER", 0, 0)
    strip._button = btn

    -- The emblem beside the button, and beside the panel's title in the
    -- view: the owner moved it off the strip's corner at the third run, so
    -- it marks the button as the addon's and not the box. The role's corner
    -- offsets go unused here.
    if spec.portrait and C.Portrait then
        strip._portrait = C.Portrait(strip, spec.portrait)
    end

    -- The halo: an additive wash in the view's color inside the button's
    -- border, over its art and under its label, that breathes while the view
    -- can open. Inside, since the owner found the first run's halo, which
    -- stood outside the button, spilling onto the strip.
    local r, g, b = Accent()
    local glow = btn:CreateTexture(nil, "ARTWORK")
    glow:SetPoint("TOPLEFT", btn, "TOPLEFT", GLOW_IN, -GLOW_IN)
    glow:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -GLOW_IN, GLOW_IN)
    glow:SetColorTexture(r, g, b, 1)
    glow:SetBlendMode("ADD")
    glow:SetAlpha(0.15)
    local pulse = glow:CreateAnimationGroup()
    pulse:SetLooping("BOUNCE")
    local alpha = pulse:CreateAnimation("Alpha")
    alpha:SetFromAlpha(0.15)
    alpha:SetToAlpha(0.5)
    alpha:SetDuration(1.4)
    alpha:SetSmoothing("IN_OUT")
    strip._glow, strip._pulse = glow, pulse

    return strip
end

local LayoutPanel

local function AnchorPortrait(beside)
    local portrait = strip and strip._portrait
    if not (portrait and beside) then return end
    portrait:ClearAllPoints()
    portrait:SetPoint("RIGHT", beside, "LEFT", -GAP, 0)
end

-- The strip's rect and its art. Collapsed: 52 units on the box's top edge,
-- the box's width, the art two corners longer than the strip so its side
-- edges, which end at its hidden bottom corners, reach the top of the box's
-- own side edges where the box's hidden top corners sat; the fill runs to
-- the bottom corner of the box's own fill, which is at alpha 0, since the
-- strip draws under the box. Expanded: the panel's height from the box's top
-- edge down and its width plus the outset each side, all nine pieces, the
-- fill inside them. TOPLEFT and TOPRIGHT are two horizontal constraints, so
-- SetHeight stands. The strip's strata and level move with the state and its
-- children move with them.
local function AnchorStrip(expanded)
    local mgr = Manager()
    if not (strip and mgr) then return end
    local art, fill, inset = strip._art, strip._fill, strip._inset
    local outset = expanded and PANEL_OUTSET or 0
    strip:ClearAllPoints()
    art:ClearAllPoints()
    fill:ClearAllPoints()
    strip:SetPoint("TOPLEFT", mgr, "TOPLEFT", -outset, STRIP_H)
    strip:SetPoint("TOPRIGHT", mgr, "TOPRIGHT", outset, STRIP_H)
    fill:SetPoint("TOPLEFT", art, "TOPLEFT", inset, -inset)
    if expanded then
        strip:SetFrameStrata("DIALOG")
        strip:SetFrameLevel(STRIP_LEVEL_VIEW)
        strip:SetHeight(LayoutPanel())
        art:SetAllPoints(strip)
        fill:SetPoint("BOTTOMRIGHT", art, "BOTTOMRIGHT", -inset, inset)
        SetPiecesAlpha(strip._border, BOTTOM_PIECES, 1)
    else
        strip:SetFrameStrata(STRIP_STRATA)
        strip:SetFrameLevel(STRIP_LEVEL)
        strip:SetHeight(STRIP_H)
        art:SetPoint("TOPLEFT", strip, "TOPLEFT", 0, 0)
        art:SetPoint("TOPRIGHT", strip, "TOPRIGHT", 0, 0)
        art:SetHeight(STRIP_H + 2 * (strip._cornerH or 0))
        local bg = mgr.Border and mgr.Border.Bg
        if bg then
            fill:SetPoint("BOTTOMRIGHT", bg, "BOTTOMRIGHT", 0, 0)
        else
            fill:SetPoint("BOTTOMRIGHT", mgr, "BOTTOMRIGHT", -inset, inset)
        end
        SetPiecesAlpha(strip._border, BOTTOM_PIECES, 0)
        AnchorPortrait(strip._button)
    end
end

local function UpdateButton()
    if not (strip and strip._button) then return end
    local V = View()
    local can = (V and V.CanEnter()) and true or false
    if strip._button.SetEnabled then strip._button:SetEnabled(can) end
    if can then
        if not strip._pulse:IsPlaying() then strip._pulse:Play() end
    else
        strip._pulse:Stop()
        strip._glow:SetAlpha(0)
    end
end

--------------------------------------------------------------------------------
-- The panel
--------------------------------------------------------------------------------

local function BuildPanel()
    if panel then return panel end
    local Ctl, content = Controls(), strip._content
    panel = {}

    local title = content:CreateFontString(nil, "OVERLAY")
    ApplyFont(title, "header", TITLE_SIZE)
    title:SetTextColor(Accent())
    title:SetJustifyH("CENTER")
    title:SetText("Dynamic Layout")
    panel.title = title

    -- The sentence over the checkboxes, wrapped and centered so it reads as
    -- theirs: at the third run it ran the panel's width on one line and read
    -- as the title's.
    local req = content:CreateFontString(nil, "OVERLAY")
    ApplyFont(req, "label", TEXT_SIZE)
    req:SetTextColor(PrimaryColor())
    req:SetJustifyH("CENTER")
    req:SetWordWrap(true)
    req:SetWidth(NOTE_W)
    req:SetText("Switch to the dynamic layout when every checked requirement is met")
    panel.requirements = req

    -- The three rows' labels hang off their checkboxes, right-aligned, in
    -- place of the row's own left-anchored label, which at the third run
    -- stood a panel's width from its checkbox.
    panel.triggers = {}
    for _, t in ipairs(TRIGGER_ROWS) do
        local name = t.name
        local row = Ctl:CreateToggle({
            parent = content, label = t.label,
            get = function()
                local V = View()
                return (V and V.GetTrigger(name)) and true or false
            end,
            set = function(v)
                local V = View()
                if V then V.SetTrigger(name, v) end
            end,
        })
        local label, box = row._label, row._indicator
        if label and box then
            label:ClearAllPoints()
            label:SetWidth(0)
            label:SetJustifyH("RIGHT")
            label:SetPoint("RIGHT", box, "LEFT", -GAP, 0)
        end
        panel.triggers[#panel.triggers + 1] = row
    end

    panel.speed = Ctl:CreateSlider({
        parent = content, label = "Transition speed",
        min = 0.25, max = 2, step = 0.25, precision = 2, displaySuffix = "s",
        width = 180, inputWidth = 48,
        get = function()
            local V = View()
            return V and V.GetSpeed() or 0.5
        end,
        set = function(v)
            local V = View()
            if V then V.SetSpeed(v) end
        end,
    })

    local frames = content:CreateFontString(nil, "OVERLAY")
    ApplyFont(frames, "header", SECTION_SIZE)
    frames:SetTextColor(PrimaryColor())
    frames:SetJustifyH("LEFT")
    frames:SetText("Frames")
    panel.framesTitle = frames

    panel.done = Ctl:CreateButton({
        parent = content, text = "Done", width = DONE_W, height = BTN_H, fontSize = 12,
        onClick = function()
            local V = View()
            if V then V.Exit() end
        end,
    })
    return panel
end

-- One checkbox per live adapter, in registration order. Rebuilt on every
-- entry: an adapter can register between two openings of Edit Mode.
local function BuildFrameRows()
    for _, row in ipairs(frameRows) do
        if row.Cleanup then pcall(row.Cleanup, row) end
        row:Hide()
        row:ClearAllPoints()
        row:SetParent(nil)
    end
    wipe(frameRows)
    local DL, Ctl = addon.DynamicLayouts, Controls()
    if not (DL and DL.Definitions and Ctl) then return end
    for _, def in ipairs(DL.Definitions()) do
        local id = def.id
        frameRows[#frameRows + 1] = Ctl:CreateToggle({
            parent = strip._content, label = def.label,
            get = function()
                local V = View()
                return (V and V.IsParticipating(id)) and true or false
            end,
            set = function(v)
                local V = View()
                if V then V.SetParticipating(id, v) end
            end,
        })
    end
end

-- The three requirement rows as one block: the widest label, the checkbox
-- and the row's own padding each side set the block's width, and each row is
-- that wide and centered, so the labels, right-aligned against their
-- checkboxes, and the checkboxes stand as one centered column pair. The
-- padding is read off the checkbox's anchor, the row's own number.
local function LayoutRequirementRows(content, W, y)
    local labelW, boxW, pad = 0, 0, PAD
    for _, row in ipairs(panel.triggers) do
        local label, box = row._label, row._indicator
        if label and label.GetStringWidth then
            local ok, w = pcall(label.GetStringWidth, label)
            if ok and type(w) == "number" and w > labelW then labelW = w end
        end
        if box then
            boxW = box:GetWidth()
            local _, _, _, x = box:GetPoint(1)
            if type(x) == "number" then pad = -x end
        end
    end
    local rowW = pad + math.ceil(labelW) + GAP + boxW + pad
    local left = (W - rowW) / 2
    for _, row in ipairs(panel.triggers) do
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", content, "TOPLEFT", left, y)
        row:SetWidth(rowW)
        y = y - ROW_H
    end
    return y
end

--- Lay the panel out from the strip's top edge down; returns the height it
--- needs. The width is the box's own plus the outset each side, read off the
--- box rather than off the strip, whose rect follows its anchors a frame
--- later. The title is centered; the requirements sentence and its rows are
--- a centered block under it; the frames run in two columns, each wide
--- enough for the longest label and its checkbox. Idempotent, and run again a
--- frame after the entry: the sentence's wrapped height reads as one line
--- until it has drawn once.
LayoutPanel = function()
    if not panel then return STRIP_H end
    local mgr, content = Manager(), strip._content
    local ok, W = pcall(mgr.GetWidth, mgr)
    W = ((ok and type(W) == "number" and W > 0) and W or 510) + 2 * PANEL_OUTSET
    local left = PAD
    local y = -PAD

    panel.title:ClearAllPoints()
    panel.title:SetPoint("TOP", content, "TOP", 0, y)
    AnchorPortrait(panel.title)
    y = y - TITLE_SIZE - 6 - GAP * 2

    -- The sentence, at least its two lines tall, close over its rows.
    local req = panel.requirements
    req:ClearAllPoints()
    req:SetPoint("TOP", content, "TOP", 0, y)
    local lineH = TEXT_SIZE + 4
    local noteH = 2 * lineH
    local okH, h = pcall(req.GetStringHeight, req)
    if okH and type(h) == "number" and h > noteH then noteH = h end
    y = y - noteH - 4

    y = LayoutRequirementRows(content, W, y)
    y = y - GAP

    panel.speed:ClearAllPoints()
    panel.speed:SetPoint("TOPLEFT", content, "TOPLEFT", left, y)
    panel.speed:SetPoint("TOPRIGHT", content, "TOPRIGHT", -PAD, y)
    y = y - SLIDER_ROW_H - GAP

    panel.framesTitle:ClearAllPoints()
    panel.framesTitle:SetPoint("TOPLEFT", content, "TOPLEFT", left, y)
    y = y - SECTION_SIZE - 6 - 2

    local colW = (W - PAD * 3) / 2
    for i, row in ipairs(frameRows) do
        local col = (i - 1) % 2
        local line = math.floor((i - 1) / 2)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", content, "TOPLEFT", left + col * (colW + PAD), y - line * ROW_H)
        row:SetWidth(colW)
    end
    y = y - math.ceil(#frameRows / 2) * ROW_H - GAP

    panel.done:ClearAllPoints()
    panel.done:SetPoint("TOPRIGHT", content, "TOPRIGHT", -PAD, y)
    y = y - BTN_H - PAD
    return -y
end

local function SetPanelShown(on)
    if not strip then return end
    strip._button:SetShown(not on)
    strip._content:SetShown(on)
end

local function RefreshPanel()
    if not panel then return end
    for _, row in ipairs(panel.triggers) do
        if row.Refresh then pcall(row.Refresh, row) end
    end
    if panel.speed.Refresh then pcall(panel.speed.Refresh, panel.speed) end
    for _, row in ipairs(frameRows) do
        if row.Refresh then pcall(row.Refresh, row) end
    end
end

--------------------------------------------------------------------------------
-- The shield and the border
--------------------------------------------------------------------------------

local function BuildShield()
    if shield then return end
    shield = CreateFrame("Frame", nil, UIParent)
    shield:SetAllPoints(UIParent)
    shield:EnableMouse(true)
    shield:SetFrameStrata("FULLSCREEN_DIALOG")
    shield:SetFrameLevel(SHIELD_LEVEL)
    shield:Hide()

    border = CreateFrame("Frame", nil, UIParent)
    border:SetAllPoints(UIParent)
    border:SetFrameStrata("DIALOG")
    border:SetFrameLevel(BORDER_LEVEL)
    border:Hide()
    local r, g, b = Accent()
    local function line()
        local tex = border:CreateTexture(nil, "OVERLAY")
        tex:SetColorTexture(r, g, b, 0.9)
        return tex
    end
    local top, bottom, left, right = line(), line(), line(), line()
    top:SetPoint("TOPLEFT")
    top:SetPoint("TOPRIGHT")
    top:SetHeight(BORDER_W)
    bottom:SetPoint("BOTTOMLEFT")
    bottom:SetPoint("BOTTOMRIGHT")
    bottom:SetHeight(BORDER_W)
    left:SetPoint("TOPLEFT", 0, -BORDER_W)
    left:SetPoint("BOTTOMLEFT", 0, BORDER_W)
    left:SetWidth(BORDER_W)
    right:SetPoint("TOPRIGHT", 0, -BORDER_W)
    right:SetPoint("BOTTOMRIGHT", 0, BORDER_W)
    right:SetWidth(BORDER_W)

    -- The fades, as animation groups on the frame: an alpha in, and an alpha
    -- out that hides the frame when it lands unless the view came back.
    local fadeIn = border:CreateAnimationGroup()
    local up = fadeIn:CreateAnimation("Alpha")
    up:SetFromAlpha(0)
    up:SetToAlpha(1)
    up:SetDuration(FADE)
    fadeIn:SetScript("OnFinished", function() border:SetAlpha(1) end)
    local fadeOut = border:CreateAnimationGroup()
    local down = fadeOut:CreateAnimation("Alpha")
    down:SetFromAlpha(1)
    down:SetToAlpha(0)
    down:SetDuration(FADE)
    fadeOut:SetScript("OnFinished", function()
        local V = View()
        if V and V.IsActive() then
            border:SetAlpha(1)
        else
            border:Hide()
        end
    end)
    border._fadeIn, border._fadeOut = fadeIn, fadeOut
end

local function ShowBorder()
    if not border then return end
    border._fadeOut:Stop()
    border:SetAlpha(1)
    border:Show()
    border._fadeIn:Play()
end

local function HideBorder()
    if not (border and border:IsShown()) then return end
    border._fadeIn:Stop()
    border._fadeOut:Play()
end

--------------------------------------------------------------------------------
-- The view's handlers
--------------------------------------------------------------------------------

local function OnLock(on)
    if shield then shield:SetShown(on and true or false) end
    -- The release after Done is what lets the button open the view again.
    if not on then UpdateButton() end
end

local function OnEnter()
    if not BuildStrip() then return end
    BuildShield()
    BuildHolds()
    BuildPanel()
    BuildFrameRows()
    HoldBlizzardPieces()
    SyncHolds()
    RaiseLibraryDialog(true)
    AnchorStrip(true)
    SetPanelShown(true)
    RefreshPanel()
    strip:Show()
    ShowBorder()
    -- The second pass, once the sentence has drawn (LayoutPanel).
    C_Timer.After(0, function()
        if alphaHeld and strip and strip._content:IsShown() then AnchorStrip(true) end
    end)
end

local function OnExit(reason)
    RaiseLibraryDialog(false)
    ReleaseBlizzardAlpha()
    ReleaseHolds()
    if reason == "done" then
        ReshowSelections()
    else
        C_Timer.After(0, ReshowSelectionsIfEditing)
    end
    if strip then
        AnchorStrip(false)
        SetPanelShown(false)
        UpdateButton()
    end
    HideBorder()
    -- Done keeps the shield up for its transition; the other ends drop it now.
    if reason ~= "done" and shield then shield:Hide() end
end

-- A frame joined or left: its box faded or came back, so the holds follow.
local function OnParticipation()
    SyncHolds()
end

--------------------------------------------------------------------------------
-- Show and hide with the box
--------------------------------------------------------------------------------

local function ShowStrip()
    local V, mgr = View(), Manager()
    if not (V and V.IsFeatureOn() and mgr) then return end
    if not IsShown(mgr) then return end
    if not BuildStrip() then return end
    HoldTopPieces(true)
    AnchorStrip(false)
    SetPanelShown(false)
    strip:Show()
    UpdateButton()
end

local function HideStrip()
    if strip then strip:Hide() end
    HoldTopPieces(false)
end

function DynamicView.Refresh()
    if strip and strip:IsShown() then UpdateButton() end
end

-- Blizzard's ClearSelectedSystem highlights every system that was highlighted
-- at Edit Mode's enter, which shows their selection boxes, and the library
-- calls it on every click of an addon-owned box. Under the view the hide
-- runs again at once, before the frame draws.
local function OnClearSelectedSystem()
    if not alphaHeld then return end
    HoldSelections()
    SyncHolds()
end

-- One shot on the first world entry, as Dialog.lua installs its own hook:
-- the box exists at login and is shown and hidden around every Edit Mode
-- session, and around the panels that hide it in between.
addon.Events.OnWorldEntered(function()
    if DynamicView._hooked then return end
    local mgr = Manager()
    if not (mgr and mgr.HookScript) then return end
    DynamicView._hooked = true
    mgr:HookScript("OnShow", ShowStrip)
    mgr:HookScript("OnHide", HideStrip)
    if hooksecurefunc and type(mgr.ClearSelectedSystem) == "function" then
        hooksecurefunc(mgr, "ClearSelectedSystem", OnClearSelectedSystem)
    end
    ShowStrip()
end)

addon.Events.On(OWNER, "PLAYER_REGEN_DISABLED", DynamicView.Refresh)
addon.Events.On(OWNER, "PLAYER_REGEN_ENABLED", function()
    if reshowOwed then ReshowSelectionsIfEditing() end
    DynamicView.Refresh()
end)

do
    local V = View()
    if V and V.SetHost then
        V.SetHost({ onEnter = OnEnter, onExit = OnExit, onLock = OnLock, onParticipation = OnParticipation })
    end
end
