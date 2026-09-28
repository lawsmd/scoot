-- DynamicView.lua - The Dynamic Layouts strip on Blizzard's Edit Mode box, the
-- panel it grows into, and the shield and screen border of the dynamic view
--
-- The strip is a frame of this addon's own on the top edge of
-- EditModeManagerFrame, drawn as one box with it: the box's top corners and
-- top edge go to alpha 0 while the strip stands on it, the strip's art (the
-- same Dialog nine-slice) drops its bottom pieces and runs its side edges
-- down to meet the box's, and its fill ends where the box's fill begins.
-- Nothing on the box is written: it is anchored to, its regions take an
-- alpha, and its OnShow and OnHide are hooked, the touches Dialog.lua already
-- makes. The strip's one button opens the view (core/dynamiclayouts/view.lua).
--
-- While the view holds, Blizzard's Edit Mode goes out of sight: the box, with
-- its grid and its magnetism lines under it, and its settings dialog take
-- alpha 0, and its selection boxes hide (a widget call; that template has no
-- script behind Hide or Show). The strip grows down from the box's top edge
-- into the panel: the requirements, the transition speed, the frames that
-- take part, and Done. Done puts every Blizzard piece back at once. The other
-- ends of the view put the alphas back and re-show the selections only if
-- Edit Mode still holds a frame later, since Blizzard's own exit has hidden
-- them for good by then.
--
-- The shield is a transparent full-screen frame that takes the mouse: over
-- everything for the transition window, then in the DIALOG strata over the
-- box and Blizzard's dialog and under the view's boxes, the branded dialog
-- (raised a strata for the view) and the strip. The border is four lines in
-- the view's color around the screen.
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
local STRIP_H      = 44
local PAD          = 14
local GAP          = 8
local TITLE_SIZE   = 15
local TEXT_SIZE    = 13
local BTN_H        = 26
local BUTTON_W     = 200
local DONE_W       = 120
local ROW_H        = 36    -- Controls:CreateToggle's row
local SLIDER_ROW_H = 40    -- Controls:CreateSlider's row
local GLOW_OUT     = 4
local BORDER_W     = 4
local FADE         = 0.3

-- Draw order, in the DIALOG strata unless said. Blizzard's box stands at the
-- bottom of it with its buttons at 2, its layout dialogs at 100 and its
-- settings dialog at 200, where the library's dialog stands too. The
-- collapsed strip sits over the box and under the dialogs. In the view the
-- shield holds over the box and Blizzard's dialog; the participating boxes
-- keep their template's 1000 over it (core/dynamiclayouts/view.lua), the
-- library's dialog rises a strata (Dialog.SetRaised), the strip goes over
-- the boxes, and for the transition the shield rises over all of it.
local STRIP_LEVEL       = 50
local STRIP_LEVEL_VIEW  = 2000
local SHIELD_LEVEL_HOLD = 250
local BORDER_LEVEL      = 255
local SHIELD_LEVEL_LOCK = 900   -- FULLSCREEN_DIALOG

local TRIGGER_ROWS = {
    { name = "inCombat",       label = "Not in combat" },
    { name = "targetAcquired", label = "Do not have a target" },
    { name = "insideInstance", label = "Not in an instance" },
}

-- The nine-slice pieces the strip shares with the box's border.
local TOP_PIECES    = { "TopLeftCorner", "TopRightCorner", "TopEdge" }
local BOTTOM_PIECES = { "BottomLeftCorner", "BottomRightCorner", "BottomEdge" }

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

local strip, shield, border
local panel = nil       -- the panel's fixed controls, built once
local frameRows = {}    -- one checkbox row per adapter, rebuilt on every entry

local topPiecesHeld = false      -- the box's top pieces at alpha 0 under the strip
local alphaHeld = false          -- the box and Blizzard's dialog at alpha 0 for the view
local hiddenSelections = {}      -- Blizzard's selection boxes the view hid, to show again
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

--------------------------------------------------------------------------------
-- Blizzard's pieces
--------------------------------------------------------------------------------

-- The box's top corners and top edge, under the strip's own while it stands
-- on the box, and back when the strip leaves.
local function HoldTopPieces(on)
    local mgr = Manager()
    if not (mgr and mgr.Border) then return end
    if on == topPiecesHeld then return end
    topPiecesHeld = on
    SetPiecesAlpha(mgr.Border, TOP_PIECES, on and 0 or 1)
end

-- The view: the box and Blizzard's settings dialog at alpha 0, and every
-- Blizzard selection box that is shown hidden, remembered for the re-show.
local function HoldBlizzardPieces()
    local mgr = Manager()
    if mgr then pcall(mgr.SetAlpha, mgr, 0) end
    local dlg = BlizzardDialog()
    if dlg and dlg.SetAlpha then pcall(dlg.SetAlpha, dlg, 0) end
    alphaHeld = true

    wipe(hiddenSelections)
    local systems = mgr and mgr.registeredSystemFrames
    if type(systems) ~= "table" then return end
    for _, system in ipairs(systems) do
        local sel = type(system) == "table" and system.Selection
        if sel and sel.IsShown then
            local ok, shown = pcall(sel.IsShown, sel)
            if ok and shown == true then
                if pcall(sel.Hide, sel) then
                    hiddenSelections[#hiddenSelections + 1] = sel
                end
            end
        end
    end
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
    for i = #hiddenSelections, 1, -1 do
        local sel = hiddenSelections[i]
        hiddenSelections[i] = nil
        pcall(sel.Show, sel)
    end
end

-- After an end that was not Done: Blizzard's own exit hides every selection
-- for good, so the re-show runs only while Edit Mode still holds, and out of
-- lockdown, where it waits for regen.
local function ReshowSelectionsIfEditing()
    if #hiddenSelections == 0 then return end
    local EM = addon.EditMode
    if not (EM and EM.IsEditing and EM.IsEditing()) then
        wipe(hiddenSelections)
        reshowOwed = false
        return
    end
    if InCombatLockdown() then
        reshowOwed = true
        return
    end
    ReshowSelections()
end

-- The library's dialog shares the DIALOG strata with the shield's hold, so
-- it rises a strata for the view (ui/v2/editmode/Dialog.lua).
local function RaiseLibraryDialog(on)
    local D = addon.EditMode.Dialog
    if D and D.SetRaised then D.SetRaised(on) end
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
    strip:SetFrameStrata("DIALOG")
    strip:SetFrameLevel(STRIP_LEVEL)
    strip:EnableMouse(true)
    strip:Hide()

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

    local reach = 0
    if spec.portrait and C.Portrait then
        local p = spec.portrait
        local portrait = C.Portrait(strip, p)
        portrait:SetPoint("TOPLEFT", strip, "TOPLEFT", p.x or 0, p.y or 0)
        strip._portrait = portrait
        reach = math.max(0, (p.size or 32) + (p.x or 0))
    end
    strip._reach = reach

    -- The button, with an additive halo in the view's color that breathes
    -- while the view can open. The halo sits on a frame of its own at the
    -- art's level, made after the art and before the button, so it draws over
    -- the fill and under the button; on the strip itself the fill would cover
    -- it.
    local r, g, b = Accent()
    local glowHolder = CreateFrame("Frame", nil, strip)
    glowHolder:SetFrameLevel(art:GetFrameLevel())
    local glow = glowHolder:CreateTexture(nil, "BACKGROUND")
    glow:SetAllPoints(glowHolder)
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
    strip._glowHolder, strip._glow, strip._pulse = glowHolder, glow, pulse

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
    glowHolder:SetPoint("TOPLEFT", btn, "TOPLEFT", -GLOW_OUT, GLOW_OUT)
    glowHolder:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", GLOW_OUT, -GLOW_OUT)

    return strip
end

local LayoutPanel

-- The strip's rect and its art. Collapsed: 44 units on the box's top edge,
-- the art two corners longer than the strip so its side edges, which end at
-- its hidden bottom corners, reach the top of the box's own side edges where
-- the box's hidden top corners sat; the fill ends at the top of the box's
-- fill. Expanded: the panel's height from the box's top edge down, all nine
-- pieces, the fill inside them. TOPLEFT and TOPRIGHT are two horizontal
-- constraints, so SetHeight stands. The strip's level moves with the state
-- and its children move with it.
local function AnchorStrip(expanded)
    local mgr = Manager()
    if not (strip and mgr) then return end
    local art, fill, inset = strip._art, strip._fill, strip._inset
    strip:ClearAllPoints()
    art:ClearAllPoints()
    fill:ClearAllPoints()
    strip:SetPoint("TOPLEFT", mgr, "TOPLEFT", 0, STRIP_H)
    strip:SetPoint("TOPRIGHT", mgr, "TOPRIGHT", 0, STRIP_H)
    fill:SetPoint("TOPLEFT", art, "TOPLEFT", inset, -inset)
    if expanded then
        strip:SetFrameLevel(STRIP_LEVEL_VIEW)
        strip:SetHeight(LayoutPanel())
        art:SetAllPoints(strip)
        fill:SetPoint("BOTTOMRIGHT", art, "BOTTOMRIGHT", -inset, inset)
        SetPiecesAlpha(strip._border, BOTTOM_PIECES, 1)
    else
        strip:SetFrameLevel(STRIP_LEVEL)
        strip:SetHeight(STRIP_H)
        art:SetPoint("TOPLEFT", strip, "TOPLEFT", 0, 0)
        art:SetPoint("TOPRIGHT", strip, "TOPRIGHT", 0, 0)
        art:SetHeight(STRIP_H + 2 * (strip._cornerH or 0))
        local bg = mgr.Border and mgr.Border.Bg
        if bg then
            fill:SetPoint("BOTTOMRIGHT", bg, "TOPRIGHT", 0, 0)
        else
            fill:SetPoint("BOTTOMRIGHT", mgr, "TOPRIGHT", -inset, -inset)
        end
        SetPiecesAlpha(strip._border, BOTTOM_PIECES, 0)
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
        strip._glow:SetAlpha(0.1)
    end
end

--------------------------------------------------------------------------------
-- The panel
--------------------------------------------------------------------------------

local function BuildPanel()
    if panel then return panel end
    local Ctl = Controls()
    panel = {}

    local title = strip:CreateFontString(nil, "OVERLAY")
    ApplyFont(title, "header", TITLE_SIZE)
    title:SetTextColor(Accent())
    title:SetJustifyH("LEFT")
    title:SetText("Dynamic Layout")
    panel.title = title

    local req = strip:CreateFontString(nil, "OVERLAY")
    ApplyFont(req, "label", TEXT_SIZE)
    req:SetTextColor(PrimaryColor())
    req:SetJustifyH("LEFT")
    req:SetWordWrap(true)
    req:SetText("Switch to the dynamic layout when every checked requirement is met")
    panel.requirements = req

    panel.triggers = {}
    for _, t in ipairs(TRIGGER_ROWS) do
        local name = t.name
        panel.triggers[#panel.triggers + 1] = Ctl:CreateToggle({
            parent = strip, label = t.label,
            get = function()
                local V = View()
                return (V and V.GetTrigger(name)) and true or false
            end,
            set = function(v)
                local V = View()
                if V then V.SetTrigger(name, v) end
            end,
        })
    end

    panel.speed = Ctl:CreateSlider({
        parent = strip, label = "Transition speed",
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

    local frames = strip:CreateFontString(nil, "OVERLAY")
    ApplyFont(frames, "header", TITLE_SIZE)
    frames:SetTextColor(PrimaryColor())
    frames:SetJustifyH("LEFT")
    frames:SetText("Frames")
    panel.framesTitle = frames

    panel.done = Ctl:CreateButton({
        parent = strip, text = "Done", width = DONE_W, height = BTN_H, fontSize = 12,
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
            parent = strip, label = def.label,
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

--- Lay the panel out from the strip's top edge down; returns the height it
--- needs. The width is the box's own, read off the box rather than off the
--- strip, whose rect follows its anchors a frame later.
LayoutPanel = function()
    if not panel then return STRIP_H end
    local mgr = Manager()
    local ok, W = pcall(mgr.GetWidth, mgr)
    W = (ok and type(W) == "number" and W > 0) and W or 510
    local left = PAD
    local y = -PAD

    panel.title:ClearAllPoints()
    panel.title:SetPoint("TOPLEFT", strip, "TOPLEFT", math.max(PAD, (strip._reach or 0) + 6), y)
    y = y - TITLE_SIZE - 6 - GAP

    panel.requirements:ClearAllPoints()
    panel.requirements:SetPoint("TOPLEFT", strip, "TOPLEFT", left, y)
    panel.requirements:SetPoint("TOPRIGHT", strip, "TOPRIGHT", -PAD, y)
    y = y - TEXT_SIZE - 8

    for _, row in ipairs(panel.triggers) do
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", strip, "TOPLEFT", left, y)
        row:SetPoint("TOPRIGHT", strip, "TOPRIGHT", -PAD, y)
        y = y - ROW_H
    end
    y = y - GAP

    panel.speed:ClearAllPoints()
    panel.speed:SetPoint("TOPLEFT", strip, "TOPLEFT", left, y)
    panel.speed:SetPoint("TOPRIGHT", strip, "TOPRIGHT", -PAD, y)
    y = y - SLIDER_ROW_H - GAP

    panel.framesTitle:ClearAllPoints()
    panel.framesTitle:SetPoint("TOPLEFT", strip, "TOPLEFT", left, y)
    y = y - TITLE_SIZE - 6 - 2

    local colW = (W - PAD * 3) / 2
    for i, row in ipairs(frameRows) do
        local col = (i - 1) % 2
        local line = math.floor((i - 1) / 2)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", strip, "TOPLEFT", left + col * (colW + PAD), y - line * ROW_H)
        row:SetWidth(colW)
    end
    y = y - math.ceil(#frameRows / 2) * ROW_H - GAP

    panel.done:ClearAllPoints()
    panel.done:SetPoint("TOPRIGHT", strip, "TOPRIGHT", -PAD, y)
    y = y - BTN_H - PAD
    return -y
end

local function SetPanelShown(on)
    if strip then
        strip._button:SetShown(not on)
        strip._glowHolder:SetShown(not on)
    end
    if not panel then return end
    panel.title:SetShown(on)
    panel.requirements:SetShown(on)
    for _, row in ipairs(panel.triggers) do row:SetShown(on) end
    panel.speed:SetShown(on)
    panel.framesTitle:SetShown(on)
    for _, row in ipairs(frameRows) do row:SetShown(on) end
    panel.done:SetShown(on)
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
    shield:SetFrameStrata("DIALOG")
    shield:SetFrameLevel(SHIELD_LEVEL_HOLD)
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
    if not shield then return end
    if on then
        shield:SetFrameStrata("FULLSCREEN_DIALOG")
        shield:SetFrameLevel(SHIELD_LEVEL_LOCK)
        shield:Show()
        return
    end
    local V = View()
    if V and V.IsActive() then
        shield:SetFrameStrata("DIALOG")
        shield:SetFrameLevel(SHIELD_LEVEL_HOLD)
    else
        shield:Hide()
    end
    -- The release after Done is what lets the button open the view again.
    UpdateButton()
end

local function OnEnter()
    if not BuildStrip() then return end
    BuildShield()
    BuildPanel()
    BuildFrameRows()
    HoldBlizzardPieces()
    RaiseLibraryDialog(true)
    AnchorStrip(true)
    SetPanelShown(true)
    RefreshPanel()
    strip:Show()
    ShowBorder()
end

local function OnExit(reason)
    RaiseLibraryDialog(false)
    ReleaseBlizzardAlpha()
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

--------------------------------------------------------------------------------
-- Show and hide with the box
--------------------------------------------------------------------------------

local function ShowStrip()
    local V, mgr = View(), Manager()
    if not (V and V.IsFeatureOn() and mgr) then return end
    local ok, shown = pcall(mgr.IsShown, mgr)
    if not (ok and shown == true) then return end
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
        V.SetHost({ onEnter = OnEnter, onExit = OnExit, onLock = OnLock })
    end
end
