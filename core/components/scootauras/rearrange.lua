-- scootauras/rearrange.lua - In-Edit-Mode member reordering for aura groups
--
-- An explicit mode entered from the group's Edit Mode dialog ("Rearrange
-- Auras"). While active, a DIALOG-strata blocker occludes the group's
-- LibEditMode selection (strata outranks the selection's toplevel flag), so
-- the group cannot be drag-moved or deselected by clicks inside it, and
-- per-member overlays capture drags. A drop reorders through
-- SAU.SetTrackerGroup; scope is reordering WITHIN the group only, so a drop
-- outside the group frame cancels. The mode force-ends on combat, Edit Mode
-- exit, selection change, and group release.
local addonName, addon = ...

local SAU = addon.ScootAuras
local Rearrange = {}
SAU.Rearrange = Rearrange

local mode = nil   -- { gid, entry } while active
local drag = nil   -- { trackerId, sourceIndex, targetIndex, visual } while dragging

local container    -- UIParent child, DIALOG strata; blocker + overlays under it
local blocker
local overlays = {}
local shownOverlays = 0
local ghost
local marker
local eventFrame

local ICON_SIZE = 26

local BeginMemberDrag, EndDrag

local function AccentColor()
    local theme = addon.UI and addon.UI.Theme
    if theme and theme.GetAccentColor then return theme:GetAccentColor() end
    return 0.2, 0.9, 0.3
end

local function IsPlainNumber(v)
    return type(v) == "number" and not issecretvalue(v)
end

-- Frame rect in physical pixels (GetCursorPosition space). Grouped visuals
-- live under group scale x member scale, so raw GetLeft() values are not
-- comparable across frames; multiplying by each frame's effective scale puts
-- everything in one space.
local function PhysRect(f)
    local ok, l, r, t, b = pcall(function()
        local es = f:GetEffectiveScale()
        local left, right = f:GetLeft(), f:GetRight()
        local top, bottom = f:GetTop(), f:GetBottom()
        if type(left) ~= "number" then return nil end
        return left * es, right * es, top * es, bottom * es
    end)
    if not (ok and IsPlainNumber(l) and IsPlainNumber(r)
        and IsPlainNumber(t) and IsPlainNumber(b)) then
        return nil
    end
    return l, r, t, b
end

-- Per grow direction: which cursor axis decides the insertion side, and which
-- spatial side of a member's center means "insert BEFORE it" (its own data
-- index; the other side is index + 1). Reversed grows flip the meaning: a
-- LEFT-growing row chains rightmost-first, so spatially left of a member is
-- AFTER it in memberOrder. Screen y grows upward.
local SIDE = {
    RIGHT = { axis = "x", beforeWhenLess = true,  beforeEdge = "LEFT",   afterEdge = "RIGHT"  },
    LEFT  = { axis = "x", beforeWhenLess = false, beforeEdge = "RIGHT",  afterEdge = "LEFT"   },
    DOWN  = { axis = "y", beforeWhenLess = false, beforeEdge = "TOP",    afterEdge = "BOTTOM" },
    UP    = { axis = "y", beforeWhenLess = true,  beforeEdge = "BOTTOM", afterEdge = "TOP"    },
}

--------------------------------------------------------------------------------
-- Frames
--------------------------------------------------------------------------------

local function EnsureFrames()
    if container then return end

    container = CreateFrame("Frame", "ScootAuraRearrangeOverlay", UIParent)
    container:SetFrameStrata("DIALOG")
    container:SetFrameLevel(100)
    container:EnableMouse(false)
    container:Hide()

    -- Swallows every click on the group so the LEM selection under it never
    -- sees a drag or a deselect. The LEM dialog sits at DIALOG level 200, so
    -- its own buttons stay clickable above this; the nudge arrows at DIALOG
    -- 500 stay live too (nudging mid-mode is harmless, the overlays are
    -- anchored to the visuals and follow).
    blocker = CreateFrame("Frame", nil, container)
    blocker:SetAllPoints(container)
    blocker:SetFrameLevel(100)
    blocker:EnableMouse(true)

    -- Watches for the mode's ground truth disappearing: dialog hidden or
    -- moved to another frame, or the group released out from under us.
    -- Cheaper and less invasive than hooking LEM dialog internals, and it
    -- costs nothing while the mode is inactive (hidden frames skip OnUpdate).
    local acc = 0
    container:SetScript("OnUpdate", function(_, dt)
        acc = acc + dt
        if acc < 0.1 then return end
        acc = 0
        if not mode then return end
        local Dialog = addon.EditMode and addon.EditMode.Dialog
        local d = Dialog and Dialog._dialog
        local selectionOk = d and d:IsShown() and d.selection
            and d.selection.parent == mode.entry.frame
        if not selectionOk or mode.entry.occupantId ~= mode.gid then
            Rearrange.ForceEnd()
        end
    end)

    eventFrame = CreateFrame("Frame")
    eventFrame:SetScript("OnEvent", function(self, event, ...)
        if event == "PLAYER_REGEN_DISABLED" then
            Rearrange.ForceEnd()
        elseif event == "GLOBAL_MOUSE_UP" then
            local button = ...
            self:UnregisterEvent("GLOBAL_MOUSE_UP")
            EndDrag(button == "RightButton")
        end
    end)
end

local function AcquireOverlay(n)
    local ov = overlays[n]
    if not ov then
        ov = CreateFrame("Frame", nil, container)
        ov:SetFrameLevel(110)
        local wash = ov:CreateTexture(nil, "ARTWORK")
        wash:SetAllPoints(ov)
        wash:Hide()
        ov._wash = wash
        ov:RegisterForDrag("LeftButton")
        ov:SetScript("OnEnter", function(self) self._wash:Show() end)
        ov:SetScript("OnLeave", function(self) self._wash:Hide() end)
        ov:SetScript("OnDragStart", function(self) BeginMemberDrag(self) end)
        overlays[n] = ov
    end
    return ov
end

--- One overlay per rendered member, anchored to its visual so reflows, nudges,
-- and scale changes track for free. Only dataIndex can go stale mid-mode, and
-- the only writer is our own drop, which rebuilds.
local function BuildOverlays()
    local group = SAU.GetGroup(mode.gid)
    local Engine = SAU.Engine
    local r, g, b = AccentColor()
    local n = 0
    if group then
        for index, trackerId in ipairs(group.memberOrder or {}) do
            local tentry = Engine._byTracker[trackerId]
            local tracker = SAU.GetTracker(trackerId)
            -- LayoutGroup's exact skip conditions: overlays only for members
            -- that render inside the group.
            if tentry and tentry.grouped and tracker and tracker.groupId == mode.gid
                and tracker.enabled ~= false then
                n = n + 1
                local ov = AcquireOverlay(n)
                ov:ClearAllPoints()
                ov:SetAllPoints(tentry.visual)
                ov.trackerId = trackerId
                ov.dataIndex = index
                ov._wash:SetColorTexture(r, g, b, 0.15)
                ov._wash:Hide()
                ov:EnableMouse(true)
                ov:Show()
            end
        end
    end
    for i = n + 1, #overlays do
        overlays[i]:Hide()
        overlays[i]:EnableMouse(false)
        overlays[i].trackerId, overlays[i].dataIndex = nil, nil
    end
    shownOverlays = n
end

local function EnsureGhost()
    if ghost then return ghost end
    ghost = CreateFrame("Frame", nil, UIParent)
    ghost:SetSize(ICON_SIZE, ICON_SIZE)
    ghost:SetFrameStrata("TOOLTIP")
    ghost:SetFrameLevel(100)
    local tex = ghost:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    ghost._tex = tex
    ghost:Hide()
    return ghost
end

local function EnsureMarker()
    if marker then return marker end
    marker = CreateFrame("Frame", nil, UIParent)
    marker:SetFrameStrata("TOOLTIP")
    marker:SetFrameLevel(99)
    local tex = marker:CreateTexture(nil, "OVERLAY")
    tex:SetAllPoints()
    tex:SetColorTexture(0.3, 0.9, 0.3, 1)
    marker:Hide()
    return marker
end

--------------------------------------------------------------------------------
-- Drop targeting
--------------------------------------------------------------------------------

--- Perpendicular to the grow axis; the cross dimension comes from the anchor
-- overlay's edges, so no scale math is needed.
local function PositionMarker(ov, edge)
    local m = EnsureMarker()
    m:ClearAllPoints()
    if edge == "LEFT" then
        m:SetWidth(2)
        m:SetPoint("TOPRIGHT", ov, "TOPLEFT", -1, 0)
        m:SetPoint("BOTTOMRIGHT", ov, "BOTTOMLEFT", -1, 0)
    elseif edge == "RIGHT" then
        m:SetWidth(2)
        m:SetPoint("TOPLEFT", ov, "TOPRIGHT", 1, 0)
        m:SetPoint("BOTTOMLEFT", ov, "BOTTOMRIGHT", 1, 0)
    elseif edge == "TOP" then
        m:SetHeight(2)
        m:SetPoint("BOTTOMLEFT", ov, "TOPLEFT", 0, 1)
        m:SetPoint("BOTTOMRIGHT", ov, "TOPRIGHT", 0, 1)
    else -- BOTTOM
        m:SetHeight(2)
        m:SetPoint("TOPLEFT", ov, "BOTTOMLEFT", 0, -1)
        m:SetPoint("TOPRIGHT", ov, "BOTTOMRIGHT", 0, -1)
    end
    m:Show()
end

--- Returns (insertIndex, anchorOverlay, edge) in raw memberOrder slots (before
-- removal adjustment), or nil when the cursor left the group (cancel).
local function FindDropTarget(cx, cy)
    local gl, gr, gt, gb = PhysRect(mode.entry.frame)
    if not gl then return nil end
    local margin = 8 * (UIParent:GetEffectiveScale() or 1)
    if cx < gl - margin or cx > gr + margin or cy < gb - margin or cy > gt + margin then
        return nil
    end

    local group = SAU.GetGroup(mode.gid)
    local growKey = group and group.settings and group.settings.grow
    local side = SIDE[growKey] or SIDE.RIGHT

    local bestOv, bestDist, bestCenter
    for i = 1, shownOverlays do
        local ov = overlays[i]
        if ov:IsShown() then
            local l, r, t, b = PhysRect(ov)
            if l then
                local ocx, ocy = (l + r) / 2, (t + b) / 2
                local d = (cx - ocx) ^ 2 + (cy - ocy) ^ 2
                if not bestDist or d < bestDist then
                    bestDist, bestOv = d, ov
                    bestCenter = (side.axis == "x") and ocx or ocy
                end
            end
        end
    end
    if not bestOv then return nil end

    local cursorOnAxis = (side.axis == "x") and cx or cy
    local before = (cursorOnAxis < bestCenter) == side.beforeWhenLess
    local index = before and bestOv.dataIndex or (bestOv.dataIndex + 1)
    local edge = before and side.beforeEdge or side.afterEdge
    return index, bestOv, edge
end

--------------------------------------------------------------------------------
-- Drag
--------------------------------------------------------------------------------

BeginMemberDrag = function(ov)
    if drag or not mode or not ov.trackerId then return end
    local tracker = SAU.GetTracker(ov.trackerId)
    if not tracker then return end
    drag = { trackerId = ov.trackerId, sourceIndex = ov.dataIndex }

    local tentry = SAU.Engine._byTracker[ov.trackerId]
    drag.visual = tentry and tentry.visual
    if drag.visual then drag.visual:SetAlpha(0.4) end

    local g = EnsureGhost()
    g._tex:SetTexture(SAU._SpellIcon(tracker.spellId))
    g:SetAlpha(0.85)
    g:Show()

    g:SetScript("OnUpdate", function(self)
        local cx, cy = GetCursorPosition()
        local uiScale = UIParent:GetEffectiveScale()
        self:ClearAllPoints()
        self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx / uiScale, cy / uiScale)

        local index, anchorOv, edge = FindDropTarget(cx, cy)
        drag.targetIndex = index
        if marker then marker:Hide() end
        if index and anchorOv then
            PositionMarker(anchorOv, edge)
        end
    end)

    -- The overlay never received OnMouseDown, so drop detection rides
    -- GLOBAL_MOUSE_UP (right button up cancels the drag, not the mode).
    eventFrame:RegisterEvent("GLOBAL_MOUSE_UP")
end

EndDrag = function(cancelled)
    if not drag then return end
    if ghost then
        ghost:SetScript("OnUpdate", nil)
        ghost:Hide()
    end
    if marker then marker:Hide() end
    if eventFrame then eventFrame:UnregisterEvent("GLOBAL_MOUSE_UP") end
    if drag.visual then drag.visual:SetAlpha(1) end

    local trackerId = drag.trackerId
    local sourceIndex = drag.sourceIndex
    local targetIndex = drag.targetIndex
    drag = nil

    if cancelled or not targetIndex or not mode then return end
    local idx = targetIndex
    if sourceIndex < idx then
        idx = idx - 1   -- the removal shifts the tail left
    end
    if idx == sourceIndex then return end
    SAU.SetTrackerGroup(trackerId, mode.gid, idx)
    BuildOverlays()
end

--------------------------------------------------------------------------------
-- Mode
--------------------------------------------------------------------------------

function Rearrange.Begin(gid)
    if InCombatLockdown() then return end
    if mode then Rearrange.End() end
    local Groups = SAU.Groups
    local entry = Groups and Groups._byGroup and Groups._byGroup[gid]
    if not entry then return end
    EnsureFrames()
    mode = { gid = gid, entry = entry }
    container:ClearAllPoints()
    container:SetAllPoints(entry.frame)
    BuildOverlays()
    container:Show()
    eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
end

--- Teardown only. The Done button's own rebuild wrapper refreshes the mirror
-- a frame later; calling RefreshMirror here would rebuild the slot inside the
-- control's own click handler.
function Rearrange.End()
    if not mode then return end
    if drag then EndDrag(true) end
    container:Hide()
    eventFrame:UnregisterEvent("PLAYER_REGEN_DISABLED")
    mode = nil
end

--- Teardown plus the mirror poke, for every exit path that is not one of the
-- mirror's own controls (combat, selection change, group release, Edit Mode
-- exit). RefreshMirror self-guards when the dialog is hidden.
function Rearrange.ForceEnd()
    if not mode then return end
    Rearrange.End()
    local Dialog = addon.EditMode and addon.EditMode.Dialog
    if Dialog and Dialog.RefreshMirror then Dialog.RefreshMirror() end
end

function Rearrange.IsActiveFor(gid)
    return mode ~= nil and mode.gid == gid
end
