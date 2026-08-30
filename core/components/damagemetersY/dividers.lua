-- damagemetersY/dividers.lua - Draggable column-width dividers in Edit Mode
--
-- When a DMY window is selected in Edit Mode, thin grayish-white divider lines
-- appear at every column boundary, including the one between the player name
-- column and the first value column. The user drags a divider to resize the
-- two adjacent columns; the result is committed to cfg.columns[c].widthFraction
-- (and cfg.nameWidthFraction for the name boundary) on release. This is the
-- ONLY way per-column widths are set.
--
-- Architecture follows scootauras/rearrange.lua: a DIALOG-strata overlay over
-- the selected frame (level 110 — under the LEM dialog at 200 and the nudge
-- arrows at 500), GLOBAL_MOUSE_UP for drag release, cursor math in the
-- window's own coordinate space via GetEffectiveScale (the windows carry
-- SetScale(windowScale), so raw cursor coordinates are not comparable), and a
-- 0.1s poll re-validating the mode's ground truth for teardown. Unlike
-- rearrange there is NO full-frame blocker: only the thin strips take mouse,
-- so LEM's drag-to-move keeps working everywhere else on the window.
local _, addon = ...
local DMY = addon.DamageMetersY

DMY.Dividers = {}
local Dividers = DMY.Dividers

local STRIP_WIDTH = 8      -- mouse hit width; the visible line is 1px
-- Width floors live in frames.lua so the layout pass clamps to the same values.

local IDLE_COLOR  = { 0.8, 0.8, 0.8, 0.55 }
local HOVER_COLOR = { 1.0, 1.0, 1.0, 0.9 }

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

local container   -- overlay, reparented onto the attached window
local strips = {} -- pooled divider strips
local mouseUpHandle -- GLOBAL_MOUSE_UP subscription, live only during a drag
local attached    -- window index while active, nil otherwise
local drag        -- live drag state, nil otherwise

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function IsPlainNumber(v)
    return type(v) == "number" and not issecretvalue(v)
end

-- Cursor X in the window frame's coordinate space (pcall + plain guard per
-- the rearrange.lua PhysRect discipline).
local function CursorLocalX(frame)
    local ok, x = pcall(function()
        local cx = GetCursorPosition()
        local es = frame:GetEffectiveScale()
        local left = frame:GetLeft()
        if type(left) ~= "number" or not es or es <= 0 then return nil end
        return cx / es - left
    end)
    if not ok or not IsPlainNumber(x) then return nil end
    return x
end

local function GetAttachedWindow()
    return attached and DMY._windows[attached] or nil
end

-- The mode's ground truth: Edit Mode active, this window still the live LEM
-- selection, and out of combat. Every window has at least the name boundary,
-- so single-column Current and Expired windows qualify too.
--
-- checkDialog=false at Attach time: the ShowSelected hook that triggers
-- Attach can fire before LEM's dialog has recorded the new selection, so the
-- dialog check is enforced by the 0.1s poll (which runs after the dialog has
-- caught up) rather than at attach.
local function ConditionsHold(checkDialog)
    if not attached then return false end
    if not DMY._editModeActive then return false end
    if InCombatLockdown() then return false end

    local win = GetAttachedWindow()
    if not win or not win.frame or not win.frame:IsShown() then return false end
    if not win._colEdges then return false end

    if not DMY._GetWindowConfig(attached) then return false end

    if not checkDialog then return true end

    local Dialog = addon.EditMode and addon.EditMode.Dialog
    local d = Dialog and Dialog._dialog
    return d ~= nil and d:IsShown() and d.selection ~= nil
        and d.selection.parent == win.frame
end

--------------------------------------------------------------------------------
-- Drag
--------------------------------------------------------------------------------

local EndDrag -- forward

local function DragTick()
    if not drag or not attached then return end
    local win = GetAttachedWindow()
    if not win then return end

    local x = CursorLocalX(win.frame)
    if not x then return end

    -- Boundary 0 is the name column's right edge: its left neighbour is the
    -- pool origin rather than another column edge, and it has its own floor.
    local b = drag.boundary
    local base = drag.baseEdges
    local leftLimit = (b == 0) and DMY.NAME_AREA_LEFT or base[b - 1]
    local minX = leftLimit + ((b == 0) and DMY.MIN_NAME_WIDTH or DMY.MIN_COL_WIDTH)
    local maxX = base[b + 1] - DMY.MIN_COL_WIDTH
    if maxX < minX then return end -- adjacent columns already at minimum

    local newEdge = math.max(minX, math.min(maxX, x))
    if drag.lastApplied and math.abs(newEdge - drag.lastApplied) < 1 then
        return
    end
    drag.lastApplied = newEdge

    -- Rebuild the fraction vector from the base edges with only boundary b
    -- moved; every other boundary stays frozen during this drag.
    local n = win._numColumns or 1
    local newLeft = (b == 0) and newEdge or base[0]
    local available = base[n] - newLeft
    if available <= 0 then return end
    local fractions = {}
    for c = 1, n do
        local leftEdge  = (c - 1 == b) and newEdge or base[c - 1]
        local rightEdge = (c == b) and newEdge or base[c]
        fractions[c] = (rightEdge - leftEdge) / available
    end

    win._dragFractions = fractions
    if b == 0 then win._dragNameEdge = newEdge end
    if DMY._comp then
        DMY._CalculateColumnWidths(attached, DMY._comp)
        DMY._LayoutBarRows(attached, DMY._comp)
    end
end

local function BeginDrag(boundary)
    if drag or not attached then return end
    local win = GetAttachedWindow()
    if not win or not win._colEdges then return end

    local base = {}
    for k, v in pairs(win._colEdges) do base[k] = v end

    drag = {
        boundary = boundary,
        baseEdges = base,
        lastApplied = nil,
    }

    mouseUpHandle = addon.Events.On("DamageMetersY:Dividers", "GLOBAL_MOUSE_UP", function(_, button)
        EndDrag(button == "RightButton")
    end)
    container._updater:Show()
end

-- cancel = true reverts to the committed fractions with no DB write.
EndDrag = function(cancel)
    if not drag then return end
    drag = nil
    if mouseUpHandle then
        mouseUpHandle:Off()
        mouseUpHandle = nil
    end
    if container and container._updater then container._updater:Hide() end

    local win = GetAttachedWindow()
    if not win then return end

    if not cancel and win._dragFractions and attached then
        -- Commit: recompute fractions from the FINAL pixel edges (post
        -- pixel-snap), so repeated drags never accumulate rounding drift.
        local cfg = DMY._GetWindowConfig(attached)
        local edges = win._colEdges
        local n = win._numColumns or 1
        if cfg and cfg.columns and edges and edges[0] and edges[n] then
            local pool = edges[n] - DMY.NAME_AREA_LEFT
            if pool > 0 then
                cfg.nameWidthFraction = (edges[0] - DMY.NAME_AREA_LEFT) / pool
            end
            local available = edges[n] - edges[0]
            if available > 0 and n >= 2 then
                for c = 1, n do
                    if cfg.columns[c] then
                        cfg.columns[c].widthFraction = (edges[c] - edges[c - 1]) / available
                    end
                end
            end
        end
    end

    win._dragFractions = nil
    win._dragNameEdge = nil
    if attached and DMY._comp then
        DMY._CalculateColumnWidths(attached, DMY._comp)
        DMY._LayoutBarRows(attached, DMY._comp)
    end
end

--------------------------------------------------------------------------------
-- Frames
--------------------------------------------------------------------------------

local function AcquireStrip(b)
    local strip = strips[b]
    if not strip then
        strip = CreateFrame("Frame", nil, container)
        strip:SetWidth(STRIP_WIDTH)
        strip:SetFrameLevel(110)
        strip:EnableMouse(true)
        strip:RegisterForDrag("LeftButton")

        local line = strip:CreateTexture(nil, "OVERLAY")
        line:SetPoint("TOP", strip, "TOP", 0, 0)
        line:SetPoint("BOTTOM", strip, "BOTTOM", 0, 0)
        line:SetWidth(1)
        line:SetColorTexture(IDLE_COLOR[1], IDLE_COLOR[2], IDLE_COLOR[3], IDLE_COLOR[4])
        strip._line = line

        strip:SetScript("OnEnter", function(self)
            self._line:SetColorTexture(HOVER_COLOR[1], HOVER_COLOR[2], HOVER_COLOR[3], HOVER_COLOR[4])
        end)
        strip:SetScript("OnLeave", function(self)
            if not drag or drag.boundary ~= self._boundary then
                self._line:SetColorTexture(IDLE_COLOR[1], IDLE_COLOR[2], IDLE_COLOR[3], IDLE_COLOR[4])
            end
        end)
        strip:SetScript("OnDragStart", function(self)
            BeginDrag(self._boundary)
        end)
        strips[b] = strip
    end
    strip._boundary = b
    return strip
end

local function EnsureFrames()
    if container then return end

    container = CreateFrame("Frame", "ScootDMYDividerOverlay", UIParent)
    container:SetFrameStrata("DIALOG")
    container:SetFrameLevel(110)
    container:EnableMouse(false)
    container:Hide()

    -- Ground-truth poll (0.1s): deselection, dialog hidden, Blizzard system
    -- selected, session switched to Current, column removed, combat — all
    -- collapse to "conditions no longer hold". Costs nothing while hidden.
    local acc = 0
    container:SetScript("OnUpdate", function(_, dt)
        acc = acc + dt
        if acc < 0.1 then return end
        acc = 0
        if attached and not ConditionsHold(true) then
            Dividers.Detach()
        end
    end)

    -- Per-frame drag tracker, shown only while a drag is live
    local updater = CreateFrame("Frame", nil, container)
    updater:Hide()
    updater:SetScript("OnUpdate", DragTick)
    container._updater = updater

    addon.Events.On("DamageMetersY:Dividers", "PLAYER_REGEN_DISABLED", function()
        Dividers.Detach()
    end)
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

--- Repositions the strips from the window's current column edges. Called by
--- _CalculateColumnWidths on every geometry pass, so the strips stay glued to
--- the boundaries through width-slider changes and live drag reflows.
function Dividers.Refresh()
    if not attached or not container then return end
    local win = GetAttachedWindow()
    if not win or not win._colEdges then return end

    local n = win._numColumns or 1
    local edges = win._colEdges
    -- Real height, not the constant: the header grows for a wrapped session
    -- title or a stacked dual-metric column header.
    local headerH = win.header and win.header:GetHeight() or 0
    if headerH <= 0 then headerH = DMY.HEADER_HEIGHT or 24 end

    -- Boundary 0 is the name column's right edge; 1..n-1 are the interior
    -- value-column boundaries.
    for b = 0, n - 1 do
        local strip = AcquireStrip(b)
        if edges[b] then
            strip:ClearAllPoints()
            strip:SetPoint("TOP", container, "TOPLEFT", edges[b], -headerH)
            strip:SetPoint("BOTTOM", container, "BOTTOMLEFT", edges[b], 0)
            strip._line:SetWidth(DMY._SnapToPixels(1, strip, 1))
            strip:Show()
        else
            strip:Hide()
        end
    end
    for b = n, #strips do
        if strips[b] then strips[b]:Hide() end
    end
end

--- Attaches the divider overlay to a window. No-ops unless the window is
--- Edit-Mode-selected and out of combat.
function Dividers.Attach(windowIndex)
    EnsureFrames()

    if attached and attached ~= windowIndex then
        Dividers.Detach()
    end

    local win = DMY._windows[windowIndex]
    if not win or not win.frame then return end

    attached = windowIndex
    if not ConditionsHold(false) then
        attached = nil
        return
    end

    container:SetParent(win.frame)
    container:ClearAllPoints()
    container:SetAllPoints(win.frame)
    container:SetFrameStrata("DIALOG")
    container:SetFrameLevel(110)
    container:Show()

    Dividers.Refresh()
end

--- Cancels any live drag (reverting uncommitted widths) and hides the overlay.
function Dividers.Detach()
    if drag then EndDrag(true) end
    if not attached then return end
    attached = nil
    if container then
        for _, strip in pairs(strips) do strip:Hide() end
        container:Hide()
        container:SetParent(UIParent)
        container:ClearAllPoints()
    end
end

function Dividers.IsActive()
    return attached ~= nil
end

function Dividers.IsActiveFor(windowIndex)
    return attached == windowIndex
end
