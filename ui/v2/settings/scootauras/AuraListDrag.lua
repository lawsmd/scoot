-- AuraListDrag.lua - drag engine for the Aura List page (cursor ghost,
-- insertion marker, drop zones, GLOBAL_MOUSE_UP drop). Built once at load by
-- the renderer through CreateAuraListDrag; the returned Drag table carries the
-- four entry points as plain-call fields, and Drag.active is read directly.
local addonName, addon = ...

addon.ScootAurasUI = addon.ScootAurasUI or {}

-- One color for the whole drag language: the insertion line, the outline every
-- zone wears while a drag can land in it, and the wash on the one under the
-- cursor. Anything green on this page means "the aura goes here".
local DROP_R, DROP_G, DROP_B = 0.3, 0.9, 0.3

-- deps:
--   state     the renderer's page-state table. Read through `state.` at call
--             time, never cached: Cleanup replaces state.hoverables and
--             state.flyouts wholesale. state.dropGroups entries are the
--             renderer's registrations, [gid] = { box, zone, icons }, with
--             zone produced by CreateDropZone.
--   refresh   re-render request; EndDrag calls it after a drop lands.
--   iconSize  member icon edge; sizes the ghost and the insertion marker.
function addon.ScootAurasUI.CreateAuraListDrag(deps)
    local state, Refresh, ICON_SIZE = deps.state, deps.refresh, deps.iconSize

    local Drag = {
        active = false,
        trackerId = nil,
        sourceGid = nil,      -- nil: dragged from the tracker list
        sourceIndex = nil,    -- data index in the source group's memberOrder
        sourceFrame = nil,
        targetGid = nil,
        targetIndex = nil,
        targetUngroup = false,
        justEndedAt = nil,
    }

    -- Frame OnMouseUp/OnClick still fires after a drag that started on the same
    -- frame; suppress activations during a drag and in the tick it ended.
    local function ClickGuard()
        return Drag.active or Drag.justEndedAt == GetTime()
    end

    -- Drop-zone art on a frame that can receive the drag: an outline while the
    -- drag is live, plus a wash while the cursor is inside it. The wash sits in
    -- BACKGROUND so member icons and row text stay on top of it, the outline in
    -- OVERLAY so the box's own border does not swallow it.
    local function CreateDropZone(frame)
        local zone = {}

        local fill = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
        fill:SetAllPoints()
        fill:SetColorTexture(DROP_R, DROP_G, DROP_B, 0.10)
        fill:Hide()

        local edges = {}
        local top = frame:CreateTexture(nil, "OVERLAY", nil, 3)
        top:SetPoint("TOPLEFT", 0, 0)
        top:SetPoint("TOPRIGHT", 0, 0)
        top:SetHeight(1)
        local bottom = frame:CreateTexture(nil, "OVERLAY", nil, 3)
        bottom:SetPoint("BOTTOMLEFT", 0, 0)
        bottom:SetPoint("BOTTOMRIGHT", 0, 0)
        bottom:SetHeight(1)
        local left = frame:CreateTexture(nil, "OVERLAY", nil, 3)
        left:SetPoint("TOPLEFT", 0, -1)
        left:SetPoint("BOTTOMLEFT", 0, 1)
        left:SetWidth(1)
        local right = frame:CreateTexture(nil, "OVERLAY", nil, 3)
        right:SetPoint("TOPRIGHT", 0, -1)
        right:SetPoint("BOTTOMRIGHT", 0, 1)
        right:SetWidth(1)
        for _, tex in ipairs({ top, bottom, left, right }) do
            tex:SetColorTexture(DROP_R, DROP_G, DROP_B, 1)
            tex:Hide()
            table.insert(edges, tex)
        end

        -- nil: no drag, or nothing can land here. "armed": a live drag could land
        -- here. "hot": the cursor is inside it and a drop lands now.
        function zone:SetState(dropState)
            for _, tex in ipairs(edges) do
                tex:SetShown(dropState ~= nil)
                tex:SetAlpha(dropState == "hot" and 0.95 or 0.3)
            end
            fill:SetShown(dropState == "hot")
        end

        zone:SetState(nil)
        return zone
    end

    -- The ghost under the cursor: the spell icon in a green frame, and a line
    -- naming what a drop does here. Over dead space the line is hidden, so the
    -- absence of a label reads as "this drop does nothing".
    local function GetDragCursor()
        if Drag.cursor then return Drag.cursor end
        local theme = addon.UI.Theme
        local f = CreateFrame("Frame", "ScootAuraListDragCursor", UIParent)
        f:SetSize(ICON_SIZE, ICON_SIZE)
        f:SetFrameStrata("TOOLTIP")
        f:SetFrameLevel(100)
        local tex = f:CreateTexture(nil, "ARTWORK")
        tex:SetPoint("TOPLEFT", 1, -1)
        tex:SetPoint("BOTTOMRIGHT", -1, 1)
        tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        f._tex = tex

        local function edge(p1, p2, w, h)
            local e = f:CreateTexture(nil, "OVERLAY")
            e:SetColorTexture(DROP_R, DROP_G, DROP_B, 0.9)
            e:SetPoint(p1, 0, 0)
            e:SetPoint(p2, 0, 0)
            if w then e:SetWidth(w) end
            if h then e:SetHeight(h) end
        end
        edge("TOPLEFT", "TOPRIGHT", nil, 1)
        edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, 1)
        edge("TOPLEFT", "BOTTOMLEFT", 1, nil)
        edge("TOPRIGHT", "BOTTOMRIGHT", 1, nil)

        local hint = CreateFrame("Frame", nil, f)
        hint:SetPoint("TOP", f, "BOTTOM", 0, -4)
        hint:SetSize(10, 16)
        local plate = hint:CreateTexture(nil, "BACKGROUND")
        plate:SetAllPoints()
        plate:SetColorTexture(0, 0, 0, 0.8)
        local label = hint:CreateFontString(nil, "OVERLAY")
        label:SetFont(theme:GetFont("LABEL"), 10, "")
        label:SetPoint("CENTER", 0, 0)
        label:SetTextColor(DROP_R, DROP_G, DROP_B, 1)
        hint:Hide()
        f._hint, f._hintLabel = hint, label

        f:Hide()
        Drag.cursor = f
        return f
    end

    -- Sizes the plate to the text, so it never reads as an empty box.
    local function SetDragHint(text)
        local cursor = Drag.cursor
        if not cursor then return end
        if not text then
            cursor._hint:Hide()
            return
        end
        cursor._hintLabel:SetText(text)
        cursor._hint:SetSize(math.max(20, (cursor._hintLabel:GetStringWidth() or 20) + 10), 16)
        cursor._hint:Show()
    end

    local function GetDragMarker()
        if Drag.marker then return Drag.marker end
        local f = CreateFrame("Frame", nil, UIParent)
        f:SetSize(2, ICON_SIZE)
        f:SetFrameStrata("TOOLTIP")
        f:SetFrameLevel(99)
        local tex = f:CreateTexture(nil, "OVERLAY")
        tex:SetAllPoints()
        tex:SetColorTexture(DROP_R, DROP_G, DROP_B, 1)
        f:Hide()
        Drag.marker = f
        return f
    end

    local function FrameContains(frame, x, y, margin)
        if not frame or not frame:IsShown() then return false end
        local left, right = frame:GetLeft(), frame:GetRight()
        local top, bottom = frame:GetTop(), frame:GetBottom()
        if not (left and right and top and bottom) then return false end
        margin = margin or 0
        return x >= left - margin and x <= right + margin
            and y >= bottom - margin and y <= top + margin
    end

    -- Every group box takes a drag; the tracker list only takes one that is
    -- leaving a group, so it arms for that drag alone.
    local function LeftPaneTakesDrop()
        return Drag.sourceGid ~= nil
    end

    local function ClearDropFeedback()
        if Drag.marker then Drag.marker:Hide() end
        for _, reg in pairs(state.dropGroups) do
            if reg.zone then reg.zone:SetState(nil) end
        end
        if state.leftDropZone then state.leftDropZone:SetState(nil) end
    end

    -- Outlines every zone the drag could land in, and fills the one the cursor is
    -- inside. Called with no target at drag start, so the zones are visible before
    -- the cursor reaches one.
    local function PaintDropFeedback(gid, anchorFrame, side, ungroup)
        if Drag.marker then Drag.marker:Hide() end
        for id, reg in pairs(state.dropGroups) do
            if reg.zone then reg.zone:SetState(id == gid and "hot" or "armed") end
        end
        if state.leftDropZone then
            if not LeftPaneTakesDrop() then
                state.leftDropZone:SetState(nil)
            else
                state.leftDropZone:SetState(ungroup and "hot" or "armed")
            end
        end
        if gid and anchorFrame then
            local marker = GetDragMarker()
            marker:ClearAllPoints()
            if side == "LEFT" then
                marker:SetPoint("RIGHT", anchorFrame, "LEFT", -1, 0)
            else
                marker:SetPoint("LEFT", anchorFrame, "RIGHT", 1, 0)
            end
            marker:Show()
        end
    end

    -- What a drop here does, in the words the list uses for the same action.
    local function DropHintText(gid, ungroup)
        if ungroup then return "Remove from group" end
        if not gid then return nil end
        local SAU = addon.ScootAuras
        local group = SAU and SAU.GetGroup(gid)
        local name = (group and group.name) or ("Aura Group " .. tostring(gid))
        if Drag.sourceGid == gid then return "Reorder in " .. name end
        if Drag.sourceGid then return "Move to " .. name end
        return "Add to " .. name
    end

    -- Rows, group boxes and member icons all paint on hover. Their own
    -- OnEnter/OnLeave cannot fire when a drag starts or ends under a still
    -- pointer, so both ends of a drag repaint the lot.
    local function RefreshHoverArt()
        for _, frame in ipairs(state.hoverables) do
            if frame.UpdateHover then frame.UpdateHover() end
        end
    end

    -- Returns (gid, insertIndex, anchorFrame, anchorSide, ungroup). The insert
    -- index is the raw slot before removal adjustment; EndDrag corrects same-group
    -- moves.
    local function FindDropTarget(x, y)
        for gid, reg in pairs(state.dropGroups) do
            if FrameContains(reg.box, x, y, 4) then
                local bestFrame, bestIndex, bestSide, bestDist
                for _, ic in ipairs(reg.icons) do
                    local l, r = ic.frame:GetLeft(), ic.frame:GetRight()
                    local t, b = ic.frame:GetTop(), ic.frame:GetBottom()
                    if l and r and t and b then
                        local cx, cy = (l + r) / 2, (t + b) / 2
                        local d = (x - cx) ^ 2 + (y - cy) ^ 2
                        if not bestDist or d < bestDist then
                            bestDist = d
                            bestFrame = ic.frame
                            if x < cx then
                                bestIndex, bestSide = ic.index, "LEFT"
                            else
                                bestIndex, bestSide = ic.index + 1, "RIGHT"
                            end
                        end
                    end
                end
                if not bestFrame then
                    return gid, 1, nil, nil, false
                end
                return gid, bestIndex, bestFrame, bestSide, false
            end
        end
        if Drag.sourceGid and FrameContains(state.leftPane, x, y, 0) then
            return nil, nil, nil, nil, true
        end
        return nil, nil, nil, nil, false
    end

    local EndDrag

    local function BeginDrag(trackerId, sourceGid, sourceIndex, texture, sourceFrame)
        if Drag.active then return end
        Drag.active = true
        Drag.trackerId = trackerId
        Drag.sourceGid = sourceGid
        Drag.sourceIndex = sourceIndex
        Drag.sourceFrame = sourceFrame
        Drag.targetGid, Drag.targetIndex, Drag.targetUngroup = nil, nil, false

        local cursor = GetDragCursor()
        cursor._tex:SetTexture(texture or 134400)
        cursor:SetAlpha(0.85)
        SetDragHint(nil)
        cursor:Show()
        if sourceFrame then sourceFrame:SetAlpha(0.4) end

        Drag.paintedGid, Drag.paintedIndex, Drag.paintedUngroup = nil, nil, nil
        PaintDropFeedback(nil, nil, nil, false)
        -- A row lit by the pointer under the ghost reads as a drop target it is
        -- not, so the hover art is off for the length of the drag.
        RefreshHoverArt()

        cursor:SetScript("OnUpdate", function(self)
            local cx, cy = GetCursorPosition()
            local scale = UIParent:GetEffectiveScale()
            cx, cy = cx / scale, cy / scale
            self:ClearAllPoints()
            self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx, cy)

            local gid, index, anchorFrame, side, ungroup = FindDropTarget(cx, cy)
            Drag.targetGid, Drag.targetIndex, Drag.targetUngroup = gid, index, ungroup

            -- This runs every frame; repaint only when the target moves. The
            -- insert index carries the marker's position, so it is the whole test.
            if gid ~= Drag.paintedGid or index ~= Drag.paintedIndex
                or ungroup ~= Drag.paintedUngroup then
                Drag.paintedGid, Drag.paintedIndex, Drag.paintedUngroup = gid, index, ungroup
                PaintDropFeedback(gid, anchorFrame, side, ungroup)
                SetDragHint(DropHintText(gid, ungroup))
            end
        end)

        -- The cursor frame never received OnMouseDown, so drop detection rides
        -- GLOBAL_MOUSE_UP (right button up cancels). The handle lives from here
        -- to EndDrag.
        Drag.mouseUpHandle = addon.Events.On("UI:AuraList", "GLOBAL_MOUSE_UP", function(_, button)
            EndDrag(button == "RightButton")
        end)
    end

    EndDrag = function(cancelled)
        if not Drag.active then return end
        if Drag.cursor then
            Drag.cursor:SetScript("OnUpdate", nil)
            SetDragHint(nil)
            Drag.cursor:Hide()
        end
        -- Off() from inside the GLOBAL_MOUSE_UP dispatch itself is safe: the bus
        -- tombstones the entry and compacts after the dispatch unwinds.
        if Drag.mouseUpHandle then
            Drag.mouseUpHandle:Off()
            Drag.mouseUpHandle = nil
        end
        ClearDropFeedback()
        if Drag.sourceFrame then Drag.sourceFrame:SetAlpha(1) end

        local trackerId = Drag.trackerId
        local sourceGid, sourceIndex = Drag.sourceGid, Drag.sourceIndex
        local targetGid, targetIndex = Drag.targetGid, Drag.targetIndex
        local targetUngroup = Drag.targetUngroup

        Drag.active = false
        Drag.trackerId, Drag.sourceGid, Drag.sourceIndex, Drag.sourceFrame = nil, nil, nil, nil
        Drag.targetGid, Drag.targetIndex, Drag.targetUngroup = nil, nil, false
        Drag.justEndedAt = GetTime()
        RefreshHoverArt()

        if cancelled or not trackerId then return end
        local SAU = addon.ScootAuras
        if targetGid then
            local idx = targetIndex
            if sourceGid == targetGid and sourceIndex and idx and sourceIndex < idx then
                idx = idx - 1   -- the removal shifts the tail left
            end
            SAU.SetTrackerGroup(trackerId, targetGid, idx)
            Refresh()
        elseif targetUngroup and sourceGid then
            SAU.SetTrackerGroup(trackerId, nil)
            Refresh()
        end
    end

    Drag.ClickGuard = ClickGuard
    Drag.CreateDropZone = CreateDropZone
    Drag.BeginDrag = BeginDrag
    Drag.EndDrag = EndDrag
    return Drag
end
