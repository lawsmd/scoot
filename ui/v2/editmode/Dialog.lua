-- Dialog.lua - Addon-branded reskin of LibEditMode's frame settings dialog
--
-- The dialog is reskinned in place rather than replaced. LibEditMode calls into
-- internal.dialog from seven sites, and core/editmode/nudgearrows.lua hooks both
-- its Update method and its OnHide. All of that survives a reskin and would die
-- under a replacement.
--
-- The seam is a post-hook on UpdateButtons, not Update: UpdateButtons runs before
-- Show() and Layout() (see dialogMixin:Update), so the fixed size is in place
-- before any sizing pass, and the hook stays disjoint from nudgearrows'.
local addonName, addon = ...

addon.EditMode = addon.EditMode or {}
addon.EditMode.Dialog = {}
local Dialog = addon.EditMode.Dialog
local Brand = addon.EditMode.Brand

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

local DIALOG_W    = 260
local PAD         = 14
local BORDER      = 3
local TITLE_SIZE  = 14
local BRAND_SIZE  = 8
local TITLE_GAP   = 6
local BLOCK_GAP   = 14   -- title to mirror slot, when the slot has content
local EMPTY_GAP   = 10   -- title to buttons, when it does not
local BTN_H       = 26
local BTN_GAP     = 6
local CLOSE_SIZE  = 24

-- Nudge arrows (core/editmode/nudgearrows.lua) sit outside the element's edges
-- at each edge midpoint: ARROW_INSET (2) + ARROW_SIZE (20). Clearing that band
-- keeps the dialog from ever covering them.
local ARROW_CLEARANCE = 26

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

-- Held module-local rather than on the LEM dialog table, so a future LibEditMode
-- has few keys to collide with. The one key written there is _ownedBy, because
-- it is the one fact two addons' copies of this file have to share.
local skin
local hooked = false
local ownedHeight          -- set while the dialog is showing one of this addon's frames
local lastPositionedFor    -- selection the dialog was last anchored to
local mirrorBuiltFor       -- selection the mirror slot was last built for
local mirrorDirty          -- force a rebuild even for the same selection

local function GetTheme()
    return addon.UI and addon.UI.Theme
end

-- The editDialog chrome role. Flat is the accent-bordered box with the brand
-- row; "blizzard" keeps LibEditMode's own dialog border, black fill and close
-- button, and marks the box with the skin's icon.
local function DialogSpec()
    local Chrome = addon.UI and addon.UI.Chrome
    local spec = Chrome and Chrome.Spec and Chrome.Spec("editDialog")
    return spec or { kind = "flat" }, Chrome
end

local function TitleColor()
    local spec, Chrome = DialogSpec()
    if spec.titleColor and Chrome then return Chrome.Color(spec.titleColor) end
    return addon.GetAccentColorRGB()
end

--------------------------------------------------------------------------------
-- Chrome
--------------------------------------------------------------------------------

local function CreateCloseButton(parent, onClick)
    local theme = GetTheme()
    local r, g, b = addon.GetAccentColorRGB()

    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(CLOSE_SIZE, CLOSE_SIZE)
    btn:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -8, -8)
    btn:SetFrameLevel(parent:GetFrameLevel() + 10)

    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(r, g, b, 1)
    bg:Hide()

    local label = btn:CreateFontString(nil, "OVERLAY")
    local face = (theme and theme.GetFont) and theme:GetFont("BUTTON") or "Fonts\\FRIZQT__.TTF"
    pcall(label.SetFont, label, face, 16, "")
    label:SetPoint("CENTER")
    label:SetText("X")
    label:SetTextColor(r, g, b, 1)

    btn:SetScript("OnEnter", function()
        bg:Show()
        label:SetTextColor(0, 0, 0, 1)
    end)
    btn:SetScript("OnLeave", function()
        bg:Hide()
        local ar, ag, ab = addon.GetAccentColorRGB()
        label:SetTextColor(ar, ag, ab, 1)
    end)
    btn:SetScript("OnClick", onClick)

    btn._bg, btn._label = bg, label
    return btn
end

--------------------------------------------------------------------------------
-- Skin construction
--------------------------------------------------------------------------------

local function EnsureSkin(dialog)
    local spec, Chrome = DialogSpec()
    local native = (spec.kind == "blizzard")

    -- A skin switch changes which box this is; the old one is dropped whole.
    if skin and skin._kind ~= spec.kind then
        Dialog.Cleanup()
        skin:Hide()
        skin = nil
    end
    if skin then return skin end

    -- Checked before anything is built, so a partial skin is never cached.
    local Controls = addon.UI and addon.UI.Controls
    if not Controls or not Controls.CreateButton then return nil end

    local theme = GetTheme()
    local bgR, bgG, bgB = 0.004, 0.004, 0.006
    if theme and theme.GetBackgroundSolidColor then
        bgR, bgG, bgB = theme:GetBackgroundSolidColor()
    end

    skin = CreateFrame("Frame", nil, dialog)
    skin:SetAllPoints()
    -- Defence in depth for the window before the first SetFixedSize lands.
    skin.ignoreInLayout = true
    skin._kind = spec.kind
    skin._native = native

    local portrait
    if native then
        local p = spec.portrait
        if p and Chrome and Chrome.Portrait then
            portrait = Chrome.Portrait(skin, p)
            portrait:SetPoint("TOPLEFT", skin, "TOPLEFT", p.x or 0, p.y or 0)
            skin._portrait = portrait
            -- How far the ring reaches into the box, which the title clears.
            skin._portraitReach = math.max(0, (p.size or 32) + (p.x or 0))
        end
    else
        local bg = skin:CreateTexture(nil, "BACKGROUND", nil, -8)
        bg:SetPoint("TOPLEFT", BORDER, -BORDER)
        bg:SetPoint("BOTTOMRIGHT", -BORDER, BORDER)
        bg:SetColorTexture(bgR, bgG, bgB, 0.98)
        skin._bg = bg

        skin._border = addon.UI.Controls.CreateBorder(skin, { thickness = BORDER })

        local Tooltip = addon.EditMode.Tooltip
        local brand = Tooltip.BuildBrandRow(skin, BRAND_SIZE)
        brand.icon:SetPoint("TOPLEFT", skin, "TOPLEFT", PAD, -PAD)
        skin._brand = brand
    end

    -- Anchor TOPLEFT only, with an explicit width. A TOPLEFT + RIGHT pair would
    -- be two *vertical* constraints (top edge and vertical centre), and WoW
    -- derives height from that pair - which silently overrides SetHeight.
    local title = skin:CreateFontString(nil, "OVERLAY")
    local face = (theme and theme.GetFont) and theme:GetFont("HEADER") or "Fonts\\FRIZQT__.TTF"
    pcall(title.SetFont, title, face, TITLE_SIZE, "")
    -- What the mirror slot anchors back by. The title is pushed right by the
    -- mark in the corner; the slot below it is not, or its controls sit off the
    -- box's centre line and its right edge hangs over the border.
    skin._mirrorIndent = 0
    if skin._brand then
        title:SetPoint("TOPLEFT", skin._brand.icon, "BOTTOMLEFT", 0, -TITLE_GAP)
        title:SetWidth(DIALOG_W - (PAD * 2))
    else
        -- Beside the mark and short of the library's close button.
        local left = math.max(PAD, (skin._portraitReach or 0) + 6)
        title:SetPoint("TOPLEFT", skin, "TOPLEFT", left, -PAD)
        title:SetWidth(DIALOG_W - left - PAD - CLOSE_SIZE)
        skin._mirrorIndent = PAD - left
    end
    title:SetJustifyH("LEFT")
    title:SetWordWrap(false)
    skin._title = title

    if not native then
        skin._close = CreateCloseButton(skin, function()
            dialog:Hide()
            dialog:Reset()
        end)
    end

    -- Holds mirrored settings controls, filled per selection by SyncMirror. Empty
    -- for a frame whose registration named no provider, and the height formula
    -- collapses the gap around it in that case so the box stays compact.
    local mirror = CreateFrame("Frame", nil, skin)
    mirror:SetPoint("TOPLEFT", title, "BOTTOMLEFT", skin._mirrorIndent, -EMPTY_GAP)
    mirror:SetWidth(DIALOG_W - (PAD * 2))
    mirror:SetHeight(0)
    skin.MirrorSlot = mirror
    skin._mirrorTitle = title
    -- Tracked explicitly rather than read back via GetHeight(), so the box size
    -- can never again depend on anchor-derived geometry. Anything that puts
    -- controls in MirrorSlot must set both this and the frame's height.
    skin._mirrorHeight = 0

    local btnWidth = DIALOG_W - (PAD * 2)

    -- Anchored bottom-up so the padding below the last button is structural and
    -- cannot be lost to a height miscalculation.
    skin._resetBtn = Controls:CreateButton({
        parent   = skin,
        text     = HUD_EDIT_MODE_RESET_POSITION or "Reset To Default Position",
        width    = btnWidth,
        height   = BTN_H,
        fontSize = 11,
        onClick  = function()
            if InCombatLockdown() then return end
            local d = Dialog._dialog
            if d and d.ResetPosition then d:ResetPosition() end
            if skin._resetBtn.SetEnabled then skin._resetBtn:SetEnabled(false) end
        end,
    })
    skin._resetBtn:ClearAllPoints()
    skin._resetBtn:SetPoint("BOTTOMLEFT", skin, "BOTTOMLEFT", PAD, PAD)

    skin._configureBtn = Controls:CreateButton({
        parent   = skin,
        text     = "Configure in " .. (addon.Brand or "Scoot"),
        width    = btnWidth,
        height   = BTN_H,
        fontSize = 11,
        onClick  = function() Dialog.Configure() end,
    })
    skin._configureBtn:ClearAllPoints()
    skin._configureBtn:SetPoint("BOTTOMLEFT", skin._resetBtn, "TOPLEFT", 0, BTN_GAP)

    return skin
end

--------------------------------------------------------------------------------
-- Configure in the addon's settings window
--------------------------------------------------------------------------------

function Dialog.Configure()
    local d = Dialog._dialog
    local sel = d and d.selection
    local info = sel and sel.parent and Brand:GetInfo(sel.parent)
    if not info or not info.navKey then return end

    -- Matches UIPanel:Show()'s silent combat bail; nothing prints to chat.
    if InCombatLockdown() then return end

    -- Let every LibEditMode consumer drop its dialog first (the library's own
    -- cross-addon contract).
    if EventRegistry and EventRegistry.TriggerEvent then
        pcall(EventRegistry.TriggerEvent, EventRegistry, "EditModeExternal.hideDialog")
    end

    addon.EditMode.CloseEditMode(function()
        addon.UI:OpenToPage(info.navKey, info)
    end)
end

--------------------------------------------------------------------------------
-- Mode switching
--------------------------------------------------------------------------------

local LEM_REGIONS = { "Border", "Close", "Title", "Settings", "Buttons" }
-- What a "blizzard" box keeps from the library: its border and close button.
local LEM_KEPT = { Border = true, Close = true }

local function SetLEMChromeShown(dialog, shown)
    local native = skin and skin._native
    for _, key in ipairs(LEM_REGIONS) do
        local region = dialog[key]
        if region then
            if shown or (native and LEM_KEPT[key]) then region:Show() else region:Hide() end
        end
    end
end

--------------------------------------------------------------------------------
-- Mirrored settings
--------------------------------------------------------------------------------

local function ClearMirror()
    local M = addon.EditMode.Mirror
    if M then M.Clear() end
    mirrorBuiltFor = nil
    mirrorDirty = nil
    if skin then
        skin.MirrorSlot:SetHeight(0)
        skin._mirrorHeight = 0
    end
end

--- Bring the mirror slot in step with the current selection.
---
--- Rebuilt only when the selection changes or a control asked for it: entering
--- Scoot mode happens on every UpdateButtons, which includes every frame of a drag,
--- and rebuilding there would destroy a control the user is holding. Everything
--- else re-reads values in place.
local function SyncMirror(selection, info)
    local M = addon.EditMode.Mirror
    if not M then return end

    if mirrorBuiltFor == selection and not mirrorDirty then
        M.Refresh()
        return
    end

    mirrorBuiltFor = selection
    mirrorDirty = nil

    local height = M.Build(skin.MirrorSlot, selection and selection.parent,
        info and info.mirror, Dialog.RefreshMirror) or 0

    skin.MirrorSlot:SetHeight(height)
    skin._mirrorHeight = height

    -- The slot's own gap has to match the one ComputeHeight budgets for, or the
    -- controls sit higher than the box was sized for and the slack lands above
    -- the buttons instead.
    skin.MirrorSlot:ClearAllPoints()
    skin.MirrorSlot:SetPoint("TOPLEFT", skin._mirrorTitle, "BOTTOMLEFT", skin._mirrorIndent or 0,
        -((height > 0) and BLOCK_GAP or EMPTY_GAP))
end

local function ComputeHeight()
    local mirrorH = skin._mirrorHeight or 0
    -- Nothing mirrored for this frame, so collapse the block gap rather than
    -- leaving an empty band between the title and the buttons.
    local gap = (mirrorH > 0) and BLOCK_GAP or EMPTY_GAP

    local brandH = skin._brand and (skin._brand.height + TITLE_GAP) or 0

    return PAD
        + brandH
        + TITLE_SIZE + 4
        + gap
        + mirrorH
        + BTN_H + BTN_GAP + BTN_H
        + PAD
end

--------------------------------------------------------------------------------
-- Placement
--------------------------------------------------------------------------------

-- Anchored diagonally off a corner of the selected element, outside the nudge
-- arrows' band. Corners are the safe zone: arrows sit at edge midpoints, so a
-- diagonal offset clears all four regardless of the element's size.
local function PositionForSelection(dialog, selection, height)
    local frame = selection and selection.parent
    if not frame then return end

    -- Prefer up-and-right; flip to whichever corner keeps the box on screen.
    local horizontal, vertical = "RIGHT", "TOP"

    local ok, right, top = pcall(function()
        return frame:GetRight(), frame:GetTop()
    end)
    if ok and type(right) == "number" and type(top) == "number" then
        local screenW, screenH = UIParent:GetWidth(), UIParent:GetHeight()
        if right + ARROW_CLEARANCE + DIALOG_W > screenW then horizontal = "LEFT" end
        if top + ARROW_CLEARANCE + height > screenH then vertical = "BOTTOM" end
    end

    local dx = (horizontal == "RIGHT") and ARROW_CLEARANCE or -ARROW_CLEARANCE
    local dy = (vertical == "TOP") and ARROW_CLEARANCE or -ARROW_CLEARANCE

    local selfPoint =
        (vertical == "TOP" and horizontal == "RIGHT" and "BOTTOMLEFT")
        or (vertical == "TOP" and "BOTTOMRIGHT")
        or (horizontal == "RIGHT" and "TOPLEFT")
        or "TOPRIGHT"

    local framePoint = vertical .. horizontal   -- TOPRIGHT / TOPLEFT / BOTTOMRIGHT / BOTTOMLEFT

    dialog:ClearAllPoints()
    dialog:SetPoint(selfPoint, frame, framePoint, dx, dy)
end

-- The role's `attach` table: the box sits beside the element, top edges level,
-- `gap` units off the side facing the middle of the screen: right of an element
-- in the left half, left of one in the right half. A host with no nudge arrows
-- has no band to clear, so it can sit close.
local attachedSide         -- side the box was last anchored on, nil when unanchored

local function AttachToSelection(dialog, selection, attach, onlyOnFlip)
    local frame = selection and selection.parent
    if not frame then return end

    local side = "RIGHT"
    local ok, centerX = pcall(frame.GetCenter, frame)
    if ok and type(centerX) == "number" then
        local ratio = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
        if centerX * ratio > UIParent:GetWidth() / 2 then side = "LEFT" end
    end
    if onlyOnFlip and side == attachedSide then return end
    attachedSide = side

    -- The selection box stands off small elements, so the gap is measured from
    -- the border the player sees rather than from the element's own edge.
    local skinner = addon.EditMode.SelectionSkin
    local outX = 0
    if skinner and skinner.Outset then outX = (skinner.Outset(selection)) end
    local gap = (attach.gap or 8) + outX
    dialog:ClearAllPoints()
    if side == "RIGHT" then
        dialog:SetPoint("TOPLEFT", frame, "TOPRIGHT", gap, 0)
    else
        dialog:SetPoint("TOPRIGHT", frame, "TOPLEFT", -gap, 0)
    end
end

-- LibEditMode updates the box when a drag stops, never during one. The watch
-- runs only while the box is shown, and re-anchors only when the element
-- crosses the middle of the screen.
local function WatchAttachedSide(dialog)
    if skin._sideWatch then return end
    skin._sideWatch = true
    skin:HookScript("OnUpdate", function()
        local attach = DialogSpec().attach
        if attach and dialog.selection and dialog._ownedBy == addonName then
            AttachToSelection(dialog, dialog.selection, attach, true)
        end
    end)
end

-- LibEditMode registers the box for a left-button drag. An attached box gives
-- that up while it shows one of this addon's frames, and takes it back on exit.
local function SetDialogDraggable(dialog, draggable)
    if draggable then
        dialog:RegisterForDrag("LeftButton")
    else
        dialog:RegisterForDrag()
    end
end

local function EnterOwnedMode(dialog, selection, info)
    if not EnsureSkin(dialog) then return end

    -- Hiding dialog.Settings is what drops the permanently-greyed "Reset To
    -- Default". LEM still builds and enables it; it is simply not rendered, so
    -- it returns for free once AddFrameSettings is ever called.
    SetLEMChromeShown(dialog, false)
    -- Two addons listing this file share one library dialog. The claim tells
    -- the other copy's exit below to leave the regions this one just arranged.
    dialog._ownedBy = addonName

    local r, g, b = TitleColor()
    skin._title:SetText(Brand:GetSystemName(selection))
    skin._title:SetTextColor(r, g, b, 1)
    if skin._brand then
        skin._brand.text:SetTextColor(addon.GetAccentColorRGB())
    end

    -- Read LEM's own answer rather than recomputing it: isDefaultPosition is a
    -- file-local with no external reach, but UpdateButtons has already stored the result.
    local lemBtn = dialog.Buttons and dialog.Buttons.ResetPositionButton
    local enabled = false
    if lemBtn and lemBtn.IsEnabled then
        local ok, v = pcall(lemBtn.IsEnabled, lemBtn)
        enabled = (ok and v == true)
    end
    if skin._resetBtn and skin._resetBtn.SetEnabled then
        skin._resetBtn:SetEnabled(enabled)
    end

    -- Before ComputeHeight: the slot's height is an input to it.
    SyncMirror(selection, info)

    skin:Show()

    -- ResizeLayoutMixin:Layout() short-circuits its final SetSize when a fixed
    -- size is set, so this cooperates with the layout pass instead of fighting it.
    local height = ComputeHeight()
    ownedHeight = height
    dialog:SetFixedSize(DIALOG_W, height)
    dialog:SetSize(DIALOG_W, height)   -- correct on this frame, not just after Layout

    -- Only reposition when the selection changes, so dragging the
    -- element (which re-runs Update) doesn't fight a dialog the user has moved.
    -- An attached box has no position of the player's to respect, so it is
    -- placed on every pass: the side can flip as the element nears the edge.
    local attach = DialogSpec().attach
    if attach then
        lastPositionedFor = selection
        AttachToSelection(dialog, selection, attach)
        WatchAttachedSide(dialog)
        SetDialogDraggable(dialog, false)
    elseif lastPositionedFor ~= selection then
        lastPositionedFor = selection
        PositionForSelection(dialog, selection, height)
        SetDialogDraggable(dialog, true)
    end
end

local function ExitOwnedMode(dialog)
    -- Cleared rather than left in place: the next Scoot frame may name a different
    -- provider, or none, and a stale control would still be writing to the frame
    -- that is no longer selected.
    ClearMirror()
    if skin then skin:Hide() end
    ownedHeight = nil
    lastPositionedFor = nil

    -- The library's regions and size are this copy's to restore only while it
    -- holds the claim. When the other addon's copy has taken the dialog for one
    -- of its frames, restoring here would undo what it arranged.
    if dialog._ownedBy ~= nil and dialog._ownedBy ~= addonName then return end
    dialog._ownedBy = nil
    SetDialogDraggable(dialog, true)
    SetLEMChromeShown(dialog, true)
    if dialog.ClearFixedSize then dialog:ClearFixedSize() end
end

local function OnDialogUpdateButtons(dialog)
    Dialog._dialog = dialog

    local sel = dialog.selection
    local info = sel and sel.parent and Brand:GetInfo(sel.parent)

    if info then
        EnterOwnedMode(dialog, sel, info)
    else
        ExitOwnedMode(dialog)
    end
end

--- Rebuild the mirror slot and resize the box around it.
---
--- Handed to Mirror as the rebuild callback, for controls whose write changes which
--- controls exist. Routed through EnterOwnedMode rather than SyncMirror alone so the
--- title and the box height come along: a snap-mode change renames the frame, and
--- renaming is exactly the case where a stale title would be noticed.
function Dialog.RefreshMirror()
    local dialog = Dialog._dialog
    if not dialog or not dialog:IsShown() then return end

    local sel = dialog.selection
    local info = sel and sel.parent and Brand:GetInfo(sel.parent)
    if not info then return end

    mirrorDirty = true
    EnterOwnedMode(dialog, sel, info)
end

--------------------------------------------------------------------------------
-- Hook installation
--------------------------------------------------------------------------------

--- LibEditMode creates internal.dialog lazily on the first AddFrame, so this is
--- retried the same way core/editmode/nudgearrows.lua does.
function Dialog.EnsureHooked()
    if hooked then return true end

    local lib = Brand and Brand.GetLib and Brand.GetLib()
    local d = lib and lib.internal and lib.internal.dialog
    if not d then return false end

    hooked = true
    Dialog._dialog = d

    hooksecurefunc(d, "UpdateButtons", OnDialogUpdateButtons)

    -- Layout() is the last thing Update() does, and it re-derives size from its
    -- children. Re-asserting here guarantees the compact size regardless of what
    -- LEM's hidden regions would otherwise measure to.
    hooksecurefunc(d, "Layout", function(dialog)
        if ownedHeight then
            dialog:SetSize(DIALOG_W, ownedHeight)
        end
    end)

    d:HookScript("OnHide", function()
        lastPositionedFor = nil
        -- Also drops any open selector dropdown, which is parented to UIParent and
        -- would otherwise outlive the box it belongs to.
        ClearMirror()
        local tooltip = addon.EditMode.Tooltip
        if tooltip and tooltip.Hide then tooltip.Hide() end
    end)

    return true
end

function Dialog.Cleanup()
    ClearMirror()
    if skin then
        if skin._configureBtn and skin._configureBtn.Cleanup then skin._configureBtn:Cleanup() end
        if skin._resetBtn and skin._resetBtn.Cleanup then skin._resetBtn:Cleanup() end
    end
end

-- One shot on the first world entry: EditModeManagerFrame exists at login, so
-- the OnShow retry installed here covers every later Edit Mode open. The old
-- frame re-ran this on every loading screen; those runs were no-ops once the
-- retry was in.
addon.Events.OnWorldEntered(function()
    -- The dialog only exists after the first AddFrame, so retry on Edit Mode
    -- open.
    if EditModeManagerFrame then
        EditModeManagerFrame:HookScript("OnShow", Dialog.EnsureHooked)
    end
    Dialog.EnsureHooked()
end)

local theme = addon.UI and addon.UI.Theme
if theme and theme.Subscribe then
    theme:Subscribe("ScootEditModeDialog", function(r, g, b)
        if not skin then return end
        local tr, tg, tb = TitleColor()
        skin._title:SetTextColor(tr, tg, tb, 1)
        if skin._brand then skin._brand.text:SetTextColor(r, g, b, 1) end
        if skin._close then
            skin._close._bg:SetColorTexture(r, g, b, 1)
            skin._close._label:SetTextColor(r, g, b, 1)
        end
    end)
end
