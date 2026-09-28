-- DynamicView.lua - The Dynamic Layouts strip on Blizzard's Edit Mode box, the
-- panel it grows into, and the shield and screen border of the dynamic view
--
-- The strip is a frame of this addon's own on the top edge of
-- EditModeManagerFrame, anchored to it and drawn with the same Dialog
-- nine-slice, so it reads as the box's own header while nothing on the box is
-- written: the box is anchored to and its OnShow and OnHide are hooked, the
-- touches Dialog.lua already makes. Its one button opens the view
-- (core/dynamiclayouts/view.lua). While the view holds, the strip grows down
-- over the box, which keeps the layout dropdown out of reach mid-view, and
-- shows the global controls: the requirements, the transition speed, the
-- frames that take part, and Done.
--
-- The shield is a transparent full-screen frame that takes the mouse: over
-- everything for the transition window, then under the raised selection
-- boxes, the branded dialog and the strip, so Blizzard's own selections and
-- the world are out of reach while the view holds. The border is four lines
-- in the view's color around the screen.
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
local STRIP_LEVEL  = 600   -- over the box's own children; its help plate is 510
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

-- FULLSCREEN_DIALOG for the transition, over everything; DIALOG after it,
-- under the raised boxes (FULLSCREEN_DIALOG), the library's dialog (200) and
-- the strip.
local SHIELD_LEVEL_LOCK = 900
local SHIELD_LEVEL_HOLD = 50

local TRIGGER_ROWS = {
    { name = "inCombat",       label = "Not in combat" },
    { name = "targetAcquired", label = "Do not have a target" },
    { name = "insideInstance", label = "Not in an instance" },
}

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

local strip, shield, border
local panel = nil       -- the panel's fixed controls, built once
local frameRows = {}    -- one checkbox row per adapter, rebuilt on every entry

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

local function Spec()
    local C = Chrome()
    return (C and C.Spec and C.Spec("editStrip")) or { kind = "flat" }
end

local function Accent()
    local spec, C = Spec(), Chrome()
    if spec.accent and C and C.Color then return C.Color(spec.accent) end
    return 0.42, 0.68, 1.0, 1
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

    -- The box's own nine-slice over its black fill, or the flat border where
    -- the layout is missing.
    if spec.kind == "nineSlice" and C.NineSlice then
        strip._border = C.NineSlice(strip, spec)
    elseif Ctl.CreateBorder then
        strip._border = Ctl.CreateBorder(strip, { thickness = 2 })
    end
    local fill = spec.fill or {}
    local inset = fill.inset or 4
    local fillTex = strip:CreateTexture(nil, "BACKGROUND", nil, -6)
    fillTex:SetPoint("TOPLEFT", inset, -inset)
    fillTex:SetPoint("BOTTOMRIGHT", -inset, inset)
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
    -- while the view can open.
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

    local r, g, b = Accent()
    local glow = strip:CreateTexture(nil, "BACKGROUND", nil, -5)
    glow:SetPoint("TOPLEFT", btn, "TOPLEFT", -GLOW_OUT, GLOW_OUT)
    glow:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", GLOW_OUT, -GLOW_OUT)
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

-- The strip's height and where it hangs: on the box's top edge, or over the
-- box from that edge down while the view holds. TOPLEFT and TOPRIGHT are two
-- horizontal constraints, so SetHeight stands.
local LayoutPanel

local function AnchorStrip(expanded)
    local mgr = Manager()
    if not (strip and mgr) then return end
    strip:ClearAllPoints()
    if expanded then
        local ok, mgrH = pcall(mgr.GetHeight, mgr)
        mgrH = (ok and type(mgrH) == "number") and mgrH or 0
        local contentH = LayoutPanel()
        strip:SetPoint("TOPLEFT", mgr, "TOPLEFT", 0, STRIP_H)
        strip:SetPoint("TOPRIGHT", mgr, "TOPRIGHT", 0, STRIP_H)
        strip:SetHeight(math.max(STRIP_H + mgrH, contentH))
    else
        strip:SetPoint("BOTTOMLEFT", mgr, "TOPLEFT", 0, 0)
        strip:SetPoint("BOTTOMRIGHT", mgr, "TOPRIGHT", 0, 0)
        strip:SetHeight(STRIP_H)
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
    title:SetTextColor(PrimaryColor())
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
        strip._glow:SetShown(not on)
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
    border:SetFrameLevel(SHIELD_LEVEL_HOLD + 5)
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
end

local function OnEnter()
    if not BuildStrip() then return end
    BuildShield()
    BuildPanel()
    BuildFrameRows()
    AnchorStrip(true)
    SetPanelShown(true)
    RefreshPanel()
    strip:Show()
    ShowBorder()
end

local function OnExit(reason)
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
    if not V.IsActive() then
        AnchorStrip(false)
        SetPanelShown(false)
    end
    strip:Show()
    UpdateButton()
end

local function HideStrip()
    if strip then strip:Hide() end
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
addon.Events.On(OWNER, "PLAYER_REGEN_ENABLED", DynamicView.Refresh)

do
    local V = View()
    if V and V.SetHost then
        V.SetHost({ onEnter = OnEnter, onExit = OnExit, onLock = OnLock })
    end
end
