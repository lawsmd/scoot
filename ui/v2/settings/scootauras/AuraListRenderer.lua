-- AuraListRenderer.lua - The Aura List page (ScootAuras section)
--
-- Two panes: individual trackers on the left (the narrower column), groups on
-- the right. Drag a tracker row onto a group box to add it; drag a member icon
-- to reorder it, onto another group to move it, or onto the tracker list to
-- remove it from its group. Hand-rolled rows registered for teardown via
-- panel._scootAurasCleanup.
local addonName, addon = ...

addon.UI = addon.UI or {}

local ROW_H = 28
local ADD_ROW_H = 30
local PAD = 8
local COL_LABEL_H = 30
local ROW_ICON = 17
local ICON_SIZE = 26
local ICON_GAP = 4
local BOX_HEADER_H = 26
local BOX_PAD = 8
local BOX_GAP = 10
local NOT_LOADED_TOP_GAP = 10   -- loaded block to the Not Loaded rule
local NOT_LOADED_HEADER_H = 37   -- gap + rule + label, before the first grayed row
local NONE_LOADED_TOP_GAP = 6    -- column label to the "None Loaded" placeholder
local NONE_LOADED_H = 26         -- the placeholder line and the gap under it
local BTN_SIZE = 16      -- group box action buttons
local BTN_GAP = 8
local ROW_BTN_SIZE = 13  -- tracker row action buttons (smaller rows)
local ROW_BTN_GAP = 6
local MEMBER_BTN_SIZE = 11  -- badges on a group member icon (ICON_SIZE is 26)
local MEMBER_BTN_GAP = 1
local ROW_TOP_PAD = 6    -- row top to the name line
local ROW_TEXT_GAP = 2   -- name line to the wrapped meta line
local ROW_BTN_Y = -7     -- button cluster inset from the row top

-- The spec restriction button. A funnel says "narrow this down", which is
-- what it does; the flat glyph matches the delete and gear art beside it.
local SPEC_ATLAS = "ui-questtrackerbutton-filter"
local SPEC_ATLAS_FALLBACK = "common-icon-undo"

-- The left column holds single rows; the right holds group boxes and earns
-- the wider share.
local LEFT_FRACTION = 0.38
local DIVIDER_CLEAR_L = 12   -- left pane edge to divider
local DIVIDER_CLEAR_R = 14   -- divider to group boxes

-- One color for the whole drag language: the insertion line, the outline every
-- zone wears while a drag can land in it, and the wash on the one under the
-- cursor. Anything green on this page means "the aura goes here".
local DROP_R, DROP_G, DROP_B = 0.3, 0.9, 0.3

local state = {
    active = false,
    panel = nil,
    scrollContent = nil,
    rows = {},
    flyouts = {},
    dropGroups = {},      -- [gid] = { box, zone, icons = { {frame, index} } }
    leftPane = nil,
    leftDropZone = nil,
    specButtons = {},     -- [key] = { button, reveal } for the spec fly-out
    hoverables = {},      -- every frame carrying an UpdateHover
    textRows = {},        -- rows whose height came from a text measurement
}

local KIND_LABELS = { buff = "Buff", debuff = "Debuff", missingbuff = "Missing Buff" }
local UNIT_LABELS = {
    player = "Player", group = "Group", target = "Target", focus = "Focus",
}
local SHAPE_LABELS = {
    icon = "Icon", bar = "Horizontal Bar", shape = "Shape",
    text = "Text", icontext = "Icon & Text",
}
local GROW_LABELS = { RIGHT = "Right", LEFT = "Left", DOWN = "Down", UP = "Up" }
local GROW_ORDER = { "RIGHT", "LEFT", "DOWN", "UP" }

-- One descriptor for every surface: the tracker row's meta line and the group
-- icon's hover tooltip.
local function TrackerMetaText(tracker, includeDisabled, includeSpecs)
    local text = (KIND_LABELS[tracker.kind] or "?") .. " on "
        .. (UNIT_LABELS[tracker.unit] or "?") .. ", shown as "
        .. (SHAPE_LABELS[tracker.shape] or "?")
    if includeSpecs ~= false then
        local SAU = addon.ScootAuras
        local named = SAU and SAU.DescribeSpecs and SAU.DescribeSpecs(tracker.specs)
        if named then text = text .. ", " .. named .. " only" end
    end
    if includeDisabled ~= false and tracker.enabled == false then
        text = text .. "  (disabled)"
    end
    return text
end

addon.ScootAurasUI = addon.ScootAurasUI or {}
addon.ScootAurasUI.TrackerMetaText = TrackerMetaText

local RenderList

local function Refresh()
    if state.active and state.panel and state.scrollContent then
        RenderList(state.panel, state.scrollContent)
    end
end

--------------------------------------------------------------------------------
-- Drag and drop (cursor ghost, insertion marker, GLOBAL_MOUSE_UP drop)
--------------------------------------------------------------------------------

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

--------------------------------------------------------------------------------
-- Cleanup (invoked from UIPanel:ClearContent through the registered slot)
--------------------------------------------------------------------------------

local function Cleanup(panel)
    if Drag.active then EndDrag(true) end
    -- The spec fly-out outlives the page (one instance, re-anchored per row),
    -- so close it before its anchor is destroyed. The exception is a re-render
    -- it asked for: RenderList hands it the rebuilt trigger instead.
    local SpecFlyout = addon.UI.ScootAuraSpecFlyout
    if SpecFlyout and not SpecFlyout.IsReanchoring() then SpecFlyout.Close() end
    for _, fly in ipairs(state.flyouts) do
        if fly.Cleanup then fly:Cleanup() end
        fly:Hide()
    end
    state.flyouts = {}
    for _, row in ipairs(state.rows) do
        row:Hide()
        row:SetParent(nil)
    end
    state.rows = {}
    state.textRows = {}
    state.hoverables = {}
    state.specButtons = {}
    for gid in pairs(state.dropGroups) do
        state.dropGroups[gid] = nil
    end
    state.leftPane = nil
    state.leftDropZone = nil
    state.active = false
    panel._scootAurasCleanup = nil

    -- Header pieces this page borrows: the Import button and the restyled
    -- subtitle. The button is built once per window and cached (not in
    -- state.flyouts, whose entries are destroyed here), so hide it rather than
    -- tear it down.
    local contentPane = panel.frame and panel.frame._contentPane
    if contentPane and contentPane._scootAuraImportBtn then
        contentPane._scootAuraImportBtn:Hide()
    end
    if panel.ResetHeaderSubtitle then panel:ResetHeaderSubtitle() end
end

--------------------------------------------------------------------------------
-- Header action: "Import" (placeholder)
--------------------------------------------------------------------------------

-- Built once per settings window on the shared page header, right of the
-- title, in the header's small-button recipe (see the Collapse All button in
-- settingspanel/core.lua). Shown by RenderList, hidden by Cleanup.
local function EnsureHeaderButtons(contentPane)
    if not contentPane or not contentPane._header then return end
    if contentPane._scootAuraImportBtn then return end
    local Controls = addon.UI.Controls
    if not Controls or not Controls.CreateButton then return end
    local header = contentPane._header

    local importBtn = Controls:CreateButton({
        parent = header,
        name = "ScootAuraImportBtn",
        text = "Import",
        height = 17,
        fontSize = 10,
        borderWidth = 1,
        borderAlpha = 0.6,
    })
    importBtn:SetPoint("TOPRIGHT", header, "TOPRIGHT", -16, -12)
    importBtn:Hide()
    -- Placeholder: no action yet. HookScript, because the button control owns
    -- OnEnter/OnLeave for its hover fill.
    importBtn:HookScript("OnEnter", function(self)
        if Controls.GetOrCreateTooltip then
            local tip = Controls:GetOrCreateTooltip()
            tip:SetContent(nil, "Coming soon...")
            tip:ShowAtAnchor(self, "TOPRIGHT", "BOTTOMRIGHT", 0, -4)
        end
    end)
    importBtn:HookScript("OnLeave", function()
        if Controls.GetOrCreateTooltip then
            Controls:GetOrCreateTooltip():Hide()
        end
    end)
    contentPane._scootAuraImportBtn = importBtn
end

--------------------------------------------------------------------------------
-- Shared row pieces
--------------------------------------------------------------------------------

-- The spec fly-out outlives a re-render; its trigger does not. Every surface
-- carrying one files it under the record's own key ("t<id>" for a tracker,
-- "g<gid>" for a group), so the open panel finds the replacement once the
-- rebuilt rows exist. A tracker is a list row or a group member, never both,
-- so one key covers both surfaces.
local function RegisterSpecButton(key, button, reveal)
    state.specButtons[key] = { button = button, reveal = reveal }
end

-- Flat glyph button: desaturated atlas tinted accent, brightening on hover,
-- named by tooltip. All three actions (gear, duplicate, delete) draw from the
-- same flat Blizzard glyph vocabulary as the rename pencil. glyphScale grows
-- the art without changing the button's layout box (the gear atlas carries
-- padding inside its glyph box and renders half the size of its neighbors).
local function CreateIconButton(row, atlas, tooltipLabel, theme, size, glyphScale)
    local ar, ag, ab = theme:GetAccentColor()
    local btn = CreateFrame("Button", nil, row)
    size = size or BTN_SIZE
    btn:SetSize(size, size)
    local tex = btn:CreateTexture(nil, "ARTWORK")
    local glyph = size * (glyphScale or 1)
    tex:SetSize(glyph, glyph)
    tex:SetPoint("CENTER", 0, 0)
    -- An atlas name that does not resolve leaves the texture blank rather
    -- than erroring, so check rather than trust.
    if not pcall(tex.SetAtlas, tex, atlas) or not tex:GetAtlas() then
        pcall(tex.SetAtlas, tex, SPEC_ATLAS_FALLBACK)
    end
    tex:SetDesaturated(true)
    tex:SetVertexColor(ar, ag, ab)
    tex:SetAlpha(0.6)
    btn._tex = tex
    btn:SetScript("OnEnter", function(self)
        tex:SetAlpha(1)
        if row.UpdateHover then row.UpdateHover() end
        if tooltipLabel then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(tooltipLabel, 1, 1, 1)
            GameTooltip:Show()
        end
    end)
    btn:SetScript("OnLeave", function()
        tex:SetAlpha(0.6)
        GameTooltip:Hide()
        if row.UpdateHover then row.UpdateHover() end
    end)
    btn:Hide()
    return btn
end

-- Compact ON/OFF state indicator (the Features-page form): bordered box with
-- an accent fill when on, dim hollow when off. Sized to match the icon
-- buttons beside it.
local IND_W, IND_H, IND_BORDER = 27, ROW_BTN_SIZE, 2

local function CreateEnabledIndicator(row, theme)
    local ar, ag, ab = theme:GetAccentColor()
    local dimR, dimG, dimB = theme:GetDimTextColor()
    local btn = CreateFrame("Button", nil, row)
    btn:SetSize(IND_W, IND_H)

    local borders = {}
    local function edge()
        local tex = btn:CreateTexture(nil, "BORDER")
        table.insert(borders, tex)
        return tex
    end
    local top = edge()
    top:SetPoint("TOPLEFT", 0, 0)
    top:SetPoint("TOPRIGHT", 0, 0)
    top:SetHeight(IND_BORDER)
    local bottom = edge()
    bottom:SetPoint("BOTTOMLEFT", 0, 0)
    bottom:SetPoint("BOTTOMRIGHT", 0, 0)
    bottom:SetHeight(IND_BORDER)
    local left = edge()
    left:SetPoint("TOPLEFT", 0, -IND_BORDER)
    left:SetPoint("BOTTOMLEFT", 0, IND_BORDER)
    left:SetWidth(IND_BORDER)
    local right = edge()
    right:SetPoint("TOPRIGHT", 0, -IND_BORDER)
    right:SetPoint("BOTTOMRIGHT", 0, IND_BORDER)
    right:SetWidth(IND_BORDER)

    local fill = btn:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("TOPLEFT", IND_BORDER, -IND_BORDER)
    fill:SetPoint("BOTTOMRIGHT", -IND_BORDER, IND_BORDER)
    fill:SetColorTexture(ar, ag, ab, 1)

    local text = btn:CreateFontString(nil, "OVERLAY")
    text:SetFont(theme:GetFont("BUTTON"), 8, "")
    text:SetPoint("CENTER", 0, 0)

    btn.SetOn = function(_, isOn)
        for _, tex in ipairs(borders) do
            tex:SetColorTexture(ar, ag, ab, isOn and 1 or 0.4)
        end
        fill:SetShown(isOn)
        if isOn then
            text:SetText("ON")
            text:SetTextColor(0, 0, 0, 1)
        else
            text:SetText("OFF")
            text:SetTextColor(dimR, dimG, dimB, 1)
        end
    end
    btn:Hide()
    return btn
end

--------------------------------------------------------------------------------
-- Left pane: tracker rows
--------------------------------------------------------------------------------

-- Row height from its two text lines. GetStringHeight reports the wrapped
-- height once the FontString has an explicit width, but it can under-report
-- before a font has rendered once, so RenderList checks these again a frame
-- later and restacks if anything moved.
local function MeasuredRowHeight(name, meta)
    local nameH = name:GetStringHeight() or 0
    local metaH = meta:GetStringHeight() or 0
    if nameH <= 0 then nameH = 10 end
    if metaH <= 0 then metaH = 9 end
    return math.max(ROW_H,
        math.ceil(ROW_TOP_PAD + nameH + ROW_TEXT_GAP + metaH + ROW_TOP_PAD))
end

-- paneW arrives from the caller because a pane's rect resolves at the end of
-- the frame, too late for the meta line's wrap width (the group boxes take
-- their width the same way).
local function CreateTrackerRow(pane, trackerId, tracker, paneW, loaded)
    local theme = addon.UI.Theme
    local ar, ag, ab = theme:GetAccentColor()
    local SAU = addon.ScootAuras

    local row = CreateFrame("Frame", nil, pane)
    row:SetHeight(ROW_H)
    row:EnableMouse(true)

    local hoverBg = row:CreateTexture(nil, "BACKGROUND", nil, -8)
    hoverBg:SetAllPoints()
    hoverBg:SetColorTexture(ar, ag, ab, 0.08)
    hoverBg:Hide()

    -- Icon and buttons hang from the top, not the middle: the row grows
    -- downward as the meta line wraps, and both belong on the name's line.
    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(ROW_ICON, ROW_ICON)
    icon:SetPoint("TOPLEFT", row, "TOPLEFT", PAD, -5)
    local texture = addon.ScootAuras._SpellIcon(tracker.spellId)
    icon:SetTexture(texture)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- Text stops short of the button cluster, so a long name or meta line
    -- never runs under it. Four buttons now: spec, delete, duplicate, ON.
    local textClear = PAD + IND_W + 3 * (ROW_BTN_SIZE + ROW_BTN_GAP) + 6

    local textLeft = PAD + ROW_ICON + 6
    local textW = math.max(40, (paneW or 240) - textLeft - textClear)

    local name = row:CreateFontString(nil, "OVERLAY")
    name:SetFont(theme:GetFont("LABEL"), 8, "")
    name:SetPoint("TOPLEFT", row, "TOPLEFT", textLeft, -ROW_TOP_PAD)
    name:SetWidth(textW)
    name:SetJustifyH("LEFT")
    name:SetWordWrap(false)
    name:SetText(tracker.name or ("Aura " .. tostring(tracker.spellId)))
    name:SetTextColor(0.92, 0.92, 0.92, 1)

    -- Wrapped, not truncated: the list scrolls, so lines are cheaper than a
    -- descriptor that ends in an ellipsis. An explicit SetWidth is what makes
    -- GetStringHeight report the wrapped height in this same tick.
    local meta = row:CreateFontString(nil, "OVERLAY")
    meta:SetFont(theme:GetFont("LABEL"), 7, "")
    meta:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -ROW_TEXT_GAP)
    meta:SetWidth(textW)
    meta:SetJustifyH("LEFT")
    meta:SetJustifyV("TOP")
    meta:SetWordWrap(true)
    meta:SetText(TrackerMetaText(tracker))
    meta:SetTextColor(0.55, 0.55, 0.55, 1)

    row._name, row._meta = name, meta
    row:SetHeight(MeasuredRowHeight(name, meta))

    -- An unloaded aura is grayed in place: the wrong spec, or switched off. It
    -- stays fully interactive, because editing one is how it gets loaded.
    if loaded == false then
        icon:SetDesaturated(true)
        icon:SetAlpha(0.45)
        name:SetTextColor(0.5, 0.5, 0.5, 1)
        meta:SetTextColor(0.42, 0.42, 0.42, 1)
    elseif tracker.enabled == false then
        icon:SetDesaturated(true)
        name:SetTextColor(0.55, 0.55, 0.55, 1)
    end

    -- All four buttons ride the row hover.
    local specBtn = CreateIconButton(row, SPEC_ATLAS, "Loaded on these specs", theme, ROW_BTN_SIZE)
    specBtn:SetPoint("TOPRIGHT", row, "TOPRIGHT", -PAD, ROW_BTN_Y)

    local deleteBtn = CreateIconButton(row, "common-icon-delete", "Delete", theme, ROW_BTN_SIZE)
    deleteBtn:SetPoint("RIGHT", specBtn, "LEFT", -ROW_BTN_GAP, 0)
    local duplicateBtn = CreateIconButton(row, "friends-icon-battlenet-copy", "Duplicate", theme, ROW_BTN_SIZE)
    duplicateBtn:SetPoint("RIGHT", deleteBtn, "LEFT", -ROW_BTN_GAP, 0)

    local enabledBtn = CreateEnabledIndicator(row, theme)
    enabledBtn:SetPoint("RIGHT", duplicateBtn, "LEFT", -ROW_BTN_GAP, 0)
    enabledBtn:SetOn(tracker.enabled ~= false)
    enabledBtn:SetScript("OnEnter", function()
        if row.UpdateHover then row.UpdateHover() end
    end)
    enabledBtn:SetScript("OnLeave", function()
        if row.UpdateHover then row.UpdateHover() end
    end)

    -- IsMouseOver covers children, so moving onto a button keeps the row lit.
    -- A live drag turns the hover art off: the pointer under the ghost passes
    -- over rows that are not drop targets, and a lit row says they are. The
    -- pane's own green wash is the answer for that drag.
    row.UpdateHover = function()
        local SpecFlyout = addon.UI.ScootAuraSpecFlyout
        local over = not Drag.active
            and (row:IsMouseOver()
                or (SpecFlyout and SpecFlyout.IsOpenFor(specBtn))
                or false)
        hoverBg:SetShown(over)
        specBtn:SetShown(over)
        deleteBtn:SetShown(over)
        duplicateBtn:SetShown(over)
        enabledBtn:SetShown(over)
    end
    row:SetScript("OnEnter", row.UpdateHover)
    row:SetScript("OnLeave", row.UpdateHover)
    table.insert(state.hoverables, row)
    RegisterSpecButton("t" .. tostring(trackerId), specBtn, row.UpdateHover)

    row:SetScript("OnMouseUp", function(_, button)
        if ClickGuard() then return end
        if button == "LeftButton" and addon.ShowScootAuraEditor then
            addon.ShowScootAuraEditor(trackerId)
        end
    end)

    row:RegisterForDrag("LeftButton")
    row:SetScript("OnDragStart", function()
        BeginDrag(trackerId, nil, nil, texture, row)
    end)

    enabledBtn:SetScript("OnClick", function()
        SAU.SetTrackerEnabled(trackerId, tracker.enabled == false)
        Refresh()
    end)

    specBtn:SetScript("OnClick", function()
        if ClickGuard() then return end
        local SpecFlyout = addon.UI.ScootAuraSpecFlyout
        if not SpecFlyout then return end
        SpecFlyout.OpenFor(specBtn, {
            title = "Load this aura in...",
            key = "t" .. tostring(trackerId),
            get = function()
                local t = SAU.GetTracker(trackerId)
                return t and t.specs
            end,
            toggle = function(specID) SAU.ToggleTrackerSpec(trackerId, specID) end,
        })
    end)

    duplicateBtn:SetScript("OnClick", function()
        local newId = SAU.DuplicateTracker(trackerId)
        if newId then Refresh() end
    end)

    deleteBtn:SetScript("OnClick", function()
        local Controls = addon.UI.Controls
        local trackerName = tracker.name or tostring(tracker.spellId)
        local doDelete = function()
            if addon.UI.ScootAuraEditor and addon.UI.ScootAuraEditor.IsOpen() then
                addon.UI.ScootAuraEditor.Close()
            end
            SAU.DeleteTracker(trackerId)
            Refresh()
        end
        if Controls and Controls.ConfirmDialog then
            Controls:ConfirmDialog(
                "Delete '" .. trackerName .. "'? Its styling and saved position are removed too.",
                doDelete)
        else
            doDelete()
        end
    end)

    return row
end

-- Add button pinned by the caller to the bottom of its pane, text centered.
local function CreateAddRow(pane, label, onClick)
    local theme = addon.UI.Theme
    local ar, ag, ab = theme:GetAccentColor()

    local row = CreateFrame("Frame", nil, pane)
    row:SetHeight(ADD_ROW_H)
    row:EnableMouse(true)

    local hoverBg = row:CreateTexture(nil, "BACKGROUND", nil, -8)
    hoverBg:SetAllPoints()
    hoverBg:SetColorTexture(ar, ag, ab, 0.1)
    hoverBg:Hide()

    local text = row:CreateFontString(nil, "OVERLAY")
    text:SetFont(theme:GetFont("LABEL"), 13, "")
    text:SetPoint("CENTER", row, "CENTER", 0, 0)
    text:SetText(label)
    text:SetTextColor(ar, ag, ab, 1)

    row:SetScript("OnEnter", function() hoverBg:Show() end)
    row:SetScript("OnLeave", function() hoverBg:Hide() end)
    row:SetScript("OnMouseUp", function(_, button)
        if ClickGuard() then return end
        if button == "LeftButton" then onClick() end
    end)

    return row
end

--------------------------------------------------------------------------------
-- Right pane: group boxes
--------------------------------------------------------------------------------

local function CreateGroupFlyout(anchorBtn, gid)
    local Controls = addon.UI.Controls
    local SAU = addon.ScootAuras
    -- The gap clears the gear's oversized glyph: the nub tip reaches 15px
    -- above the panel top, the glyph 8px below the button box.
    local flyout = Controls:CreateFlyout({
        anchor = anchorBtn,
        direction = "DOWN",
        width = 340,
        height = 140,
        padding = 10,
        gap = 26,
    })
    local content = flyout:GetContent()

    local spacingSlider = Controls:CreateSlider({
        parent = content,
        label = "Spacing",
        min = 0,
        max = 50,
        step = 1,
        width = 90,
        inputWidth = 40,
        get = function()
            local group = SAU.GetGroup(gid)
            return (group and group.settings and group.settings.spacing) or 4
        end,
        set = function(value)
            SAU.SetGroupSettings(gid, { spacing = value })
        end,
    })
    spacingSlider:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
    spacingSlider:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, 0)

    -- Scales the whole group as a unit, on top of each member's own scale.
    local scaleSlider = Controls:CreateSlider({
        parent = content,
        label = "Group Scale",
        min = 25,
        max = 200,
        step = 5,
        width = 90,
        inputWidth = 40,
        get = function()
            local group = SAU.GetGroup(gid)
            return (group and group.settings and group.settings.scale) or 100
        end,
        set = function(value)
            SAU.SetGroupSettings(gid, { scale = value })
        end,
    })
    scaleSlider:SetPoint("TOPLEFT", spacingSlider, "BOTTOMLEFT", 0, 0)
    scaleSlider:SetPoint("TOPRIGHT", spacingSlider, "BOTTOMRIGHT", 0, 0)

    local selector = Controls:CreateSelector({
        parent = content,
        label = "Grow Direction",
        values = GROW_LABELS,
        order = GROW_ORDER,
        width = 130,
        noBottomBorder = true,
        get = function()
            local group = SAU.GetGroup(gid)
            return (group and group.settings and group.settings.grow) or "RIGHT"
        end,
        set = function(value)
            SAU.SetGroupSettings(gid, { grow = value })
        end,
    })
    selector:SetPoint("TOPLEFT", scaleSlider, "BOTTOMLEFT", 0, 0)
    selector:SetPoint("TOPRIGHT", scaleSlider, "BOTTOMRIGHT", 0, 0)

    table.insert(state.flyouts, flyout)
    return flyout
end

local function CreateGroupBox(pane, gid, group, boxW, loaded)
    local theme = addon.UI.Theme
    local ar, ag, ab = theme:GetAccentColor()
    local SAU = addon.ScootAuras

    local box = CreateFrame("Frame", nil, pane)
    box:EnableMouse(true)

    local bg = box:CreateTexture(nil, "BACKGROUND", nil, -8)
    bg:SetAllPoints()
    bg:SetColorTexture(ar, ag, ab, 0.04)

    local zone = CreateDropZone(box)

    local function edge()
        local tex = box:CreateTexture(nil, "BORDER")
        tex:SetColorTexture(ar, ag, ab, 0.3)
        return tex
    end
    local eTop = edge()
    eTop:SetPoint("TOPLEFT", 0, 0)
    eTop:SetPoint("TOPRIGHT", 0, 0)
    eTop:SetHeight(1)
    local eBottom = edge()
    eBottom:SetPoint("BOTTOMLEFT", 0, 0)
    eBottom:SetPoint("BOTTOMRIGHT", 0, 0)
    eBottom:SetHeight(1)
    local eLeft = edge()
    eLeft:SetPoint("TOPLEFT", 0, -1)
    eLeft:SetPoint("BOTTOMLEFT", 0, 1)
    eLeft:SetWidth(1)
    local eRight = edge()
    eRight:SetPoint("TOPRIGHT", 0, -1)
    eRight:SetPoint("BOTTOMRIGHT", 0, 1)
    eRight:SetWidth(1)

    -- Group name plus rename pencil; the name feeds the Edit Mode container.
    local nameBtn = CreateFrame("Button", nil, box)
    nameBtn:SetHeight(18)
    nameBtn:SetPoint("TOPLEFT", box, "TOPLEFT", BOX_PAD, -4)
    local nameFS = nameBtn:CreateFontString(nil, "OVERLAY")
    nameFS:SetFont(theme:GetFont("LABEL"), 12, "")
    nameFS:SetPoint("LEFT", 0, 0)
    nameFS:SetText(group.name or ("Aura Group " .. gid))
    nameFS:SetTextColor(0.92, 0.92, 0.92, 1)
    -- Reserve room for the button cluster, one wider than it used to be.
    local btnReserve = 130 + BTN_SIZE + BTN_GAP
    nameBtn:SetWidth(math.max(20, math.min(nameFS:GetStringWidth() + 6, boxW - btnReserve)))

    local pencilBtn = CreateFrame("Button", nil, box)
    pencilBtn:SetSize(12, 12)
    pencilBtn:SetPoint("LEFT", nameBtn, "RIGHT", 4, 0)
    local pencil = pencilBtn:CreateTexture(nil, "ARTWORK")
    pencil:SetAllPoints()
    pencil:SetAtlas("Pencil-Icon")
    pencil:SetDesaturated(true)
    pencil:SetVertexColor(ar, ag, ab)
    pencil:SetAlpha(0.4)
    pencilBtn:SetScript("OnEnter", function() pencil:SetAlpha(0.9) end)
    pencilBtn:SetScript("OnLeave", function() pencil:SetAlpha(0.4) end)

    local renameBox = CreateFrame("EditBox", nil, box, "InputBoxTemplate")
    renameBox:SetHeight(18)
    renameBox:SetPoint("TOPLEFT", box, "TOPLEFT", BOX_PAD + 6, -4)
    renameBox:SetPoint("TOPRIGHT", box, "TOPRIGHT", -(90 + BTN_SIZE + BTN_GAP), -4)
    renameBox:SetAutoFocus(false)
    renameBox:SetFontObject("GameFontHighlightSmall")
    renameBox:Hide()
    local function CommitRename()
        local text = renameBox:GetText()
        renameBox:Hide()
        nameBtn:Show()
        pencilBtn:Show()
        if text and text ~= "" and text ~= group.name then
            SAU.RenameGroup(gid, text)
            Refresh()
        end
    end
    local function CancelRename()
        renameBox:Hide()
        nameBtn:Show()
        pencilBtn:Show()
    end
    renameBox:SetScript("OnEnterPressed", CommitRename)
    renameBox:SetScript("OnEscapePressed", CancelRename)
    renameBox:SetScript("OnEditFocusLost", function()
        if renameBox:IsShown() then CancelRename() end
    end)
    local function StartRename()
        if ClickGuard() then return end
        renameBox:SetText(group.name or "")
        nameBtn:Hide()
        pencilBtn:Hide()
        renameBox:Show()
        renameBox:SetFocus()
        renameBox:HighlightText()
    end
    nameBtn:SetScript("OnClick", StartRename)
    pencilBtn:SetScript("OnClick", StartRename)

    -- Hover-revealed, right to left: spec filter, delete, duplicate, layout gear.
    local specBtn = CreateIconButton(box, SPEC_ATLAS, "Loaded on these specs", theme)
    specBtn:SetPoint("TOPRIGHT", box, "TOPRIGHT", -BOX_PAD, -5)
    specBtn:SetScript("OnClick", function()
        if ClickGuard() then return end
        local SpecFlyout = addon.UI.ScootAuraSpecFlyout
        if not SpecFlyout then return end
        SpecFlyout.OpenFor(specBtn, {
            title = "Load this group in...",
            key = "g" .. tostring(gid),
            get = function()
                local g = SAU.GetGroup(gid)
                return g and g.specs
            end,
            toggle = function(specID) SAU.ToggleGroupSpec(gid, specID) end,
        })
    end)

    local deleteBtn = CreateIconButton(box, "common-icon-delete", "Delete Group", theme)
    deleteBtn:SetPoint("RIGHT", specBtn, "LEFT", -BTN_GAP, 0)
    local duplicateBtn = CreateIconButton(box, "friends-icon-battlenet-copy", "Duplicate Group", theme)
    duplicateBtn:SetPoint("RIGHT", deleteBtn, "LEFT", -BTN_GAP, 0)
    -- Layout settings describe a group that is on screen. An unloaded group has
    -- none, so it carries no gear and builds no fly-out.
    local layoutBtn, flyout
    if loaded ~= false then
        layoutBtn = CreateIconButton(box, "GM-icon-settings", "Layout", theme, BTN_SIZE, 2)
        layoutBtn:SetPoint("RIGHT", duplicateBtn, "LEFT", -BTN_GAP, 0)

        flyout = CreateGroupFlyout(layoutBtn, gid)
        layoutBtn:SetScript("OnClick", function()
            if ClickGuard() then return end
            flyout:Toggle()
        end)
    end

    duplicateBtn:SetScript("OnClick", function()
        if SAU.DuplicateGroup(gid) then Refresh() end
    end)

    deleteBtn:SetScript("OnClick", function()
        local Controls = addon.UI.Controls
        local groupName = group.name or ("Aura Group " .. gid)
        local doDelete = function()
            SAU.DeleteGroup(gid)
            Refresh()
        end
        if Controls and Controls.ConfirmDialog then
            Controls:ConfirmDialog(
                "Delete '" .. groupName .. "'? Its trackers are kept and return to their own positions.",
                doDelete)
        else
            doDelete()
        end
    end)

    -- A restricted group says so under its name. Groups have no meta line,
    -- so the header grows by this one when it is there.
    local headerH = BOX_HEADER_H
    local groupSpecs = SAU.DescribeSpecs and SAU.DescribeSpecs(group.specs)
    if groupSpecs then
        local specFS = box:CreateFontString(nil, "OVERLAY")
        specFS:SetFont(theme:GetFont("LABEL"), 7, "")
        specFS:SetPoint("TOPLEFT", box, "TOPLEFT", BOX_PAD, -(BOX_HEADER_H - 6))
        specFS:SetWidth(math.max(40, boxW - BOX_PAD * 2))
        specFS:SetJustifyH("LEFT")
        specFS:SetWordWrap(true)
        specFS:SetText(groupSpecs .. " only")
        specFS:SetTextColor(0.55, 0.55, 0.55, 1)
        headerH = BOX_HEADER_H + math.ceil(math.max(9, specFS:GetStringHeight() or 9)) + 2
    end

    -- Member icon grid, in memberOrder order.
    local icons = {}
    local perRow = math.max(1, math.floor((boxW - BOX_PAD * 2 + ICON_GAP) / (ICON_SIZE + ICON_GAP)))
    local shown = 0
    for index, memberId in ipairs(group.memberOrder or {}) do
        local tracker = SAU.GetTracker(memberId)
        if tracker then
            local slot = shown
            shown = shown + 1
            local col = slot % perRow
            local rowIdx = math.floor(slot / perRow)
            local btn = CreateFrame("Button", nil, box)
            btn:SetSize(ICON_SIZE, ICON_SIZE)
            btn:SetPoint("TOPLEFT", box, "TOPLEFT",
                BOX_PAD + col * (ICON_SIZE + ICON_GAP),
                -(headerH + rowIdx * (ICON_SIZE + ICON_GAP)))

            local tex = btn:CreateTexture(nil, "ARTWORK")
            tex:SetAllPoints()
            local texture = addon.ScootAuras._SpellIcon(tracker.spellId)
            tex:SetTexture(texture)
            tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            if loaded == false or not SAU.IsTrackerActive(memberId, tracker) then
                tex:SetDesaturated(true)
                tex:SetAlpha(0.45)
            end

            -- A group is shared by the whole account, but its members are often
            -- one class each. Both badges live in the icon's top-right corner so
            -- a member's spec list and an in-group copy are reachable without
            -- pulling it out of the group first. They sit inside the icon rect:
            -- an outset badge would cover the neighbour, and IsMouseOver tests
            -- the parent's own rect, so the badge would hide itself under the
            -- pointer. An unloaded member keeps both, the way a grayed tracker
            -- row does, because the spec badge is how an aura gets loaded.
            local memberSpecBtn = CreateIconButton(btn, SPEC_ATLAS,
                "Loaded on these specs", theme, MEMBER_BTN_SIZE)
            memberSpecBtn:SetPoint("TOPRIGHT", btn, "TOPRIGHT", 0, 0)
            local memberDupBtn = CreateIconButton(btn, "friends-icon-battlenet-copy",
                "Duplicate in Group", theme, MEMBER_BTN_SIZE)
            memberDupBtn:SetPoint("RIGHT", memberSpecBtn, "LEFT", -MEMBER_BTN_GAP, 0)

            -- The accent glyph would sink into bright spell art. CreateIconButton
            -- draws it in ARTWORK, so a BACKGROUND plate sits under it.
            for _, badge in ipairs({ memberSpecBtn, memberDupBtn }) do
                local shade = badge:CreateTexture(nil, "BACKGROUND")
                shade:SetAllPoints()
                shade:SetColorTexture(0, 0, 0, 0.72)
                -- The badges cover the icon's corner and would otherwise eat a
                -- drag started there.
                badge:RegisterForDrag("LeftButton")
                badge:SetScript("OnDragStart", function()
                    BeginDrag(memberId, gid, index, texture, btn)
                end)
            end

            btn.UpdateHover = function()
                local SpecFlyout = addon.UI.ScootAuraSpecFlyout
                local over = not Drag.active
                    and (btn:IsMouseOver()
                        or (SpecFlyout and SpecFlyout.IsOpenFor(btn))
                        or false)
                memberSpecBtn:SetShown(over)
                memberDupBtn:SetShown(over)
                if box.UpdateHover then box.UpdateHover() end
            end
            table.insert(state.hoverables, btn)
            RegisterSpecButton("t" .. tostring(memberId), btn, btn.UpdateHover)

            -- Anchored to the icon, not to the badge in its corner: a panel
            -- hung off an 11px badge inside the art puts its nub across the
            -- spell icon. From the icon the nub clears both.
            memberSpecBtn:SetScript("OnClick", function()
                if ClickGuard() then return end
                local SpecFlyout = addon.UI.ScootAuraSpecFlyout
                if not SpecFlyout then return end
                SpecFlyout.OpenFor(btn, {
                    title = "Load this aura in...",
                    key = "t" .. tostring(memberId),
                    get = function()
                        local t = SAU.GetTracker(memberId)
                        return t and t.specs
                    end,
                    toggle = function(specID) SAU.ToggleTrackerSpec(memberId, specID) end,
                })
            end)

            -- Copies the member into its group beside itself. The editor's own
            -- duplicate then edits the copy; here the user is browsing the list,
            -- so it stays put.
            memberDupBtn:SetScript("OnClick", function()
                if ClickGuard() then return end
                if SAU.DuplicateTrackerInGroup(memberId) then
                    GameTooltip:Hide()
                    Refresh()
                end
            end)

            btn:SetScript("OnEnter", function(self)
                btn.UpdateHover()
                if Drag.active then return end
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(tracker.name or ("Aura " .. tostring(tracker.spellId)), 1, 1, 1)
                GameTooltip:AddLine(TrackerMetaText(tracker), 0.7, 0.7, 0.7, true)
                GameTooltip:Show()
            end)
            btn:SetScript("OnLeave", function()
                GameTooltip:Hide()
                btn.UpdateHover()
            end)
            btn:SetScript("OnClick", function()
                if ClickGuard() then return end
                if addon.ShowScootAuraEditor then
                    addon.ShowScootAuraEditor(memberId)
                end
            end)
            btn:RegisterForDrag("LeftButton")
            btn:SetScript("OnDragStart", function()
                BeginDrag(memberId, gid, index, texture, btn)
            end)

            table.insert(icons, { frame = btn, index = index })
        end
    end

    if shown == 0 then
        local hint = box:CreateFontString(nil, "OVERLAY")
        hint:SetFont(theme:GetFont("LABEL"), 11, "")
        hint:SetPoint("TOPLEFT", box, "TOPLEFT", BOX_PAD, -(headerH + 8))
        hint:SetText("Drag trackers here")
        hint:SetTextColor(0.55, 0.55, 0.55, 1)
    end

    local iconRows = math.max(1, math.ceil(shown / perRow))
    box:SetHeight(headerH + iconRows * (ICON_SIZE + ICON_GAP) + BOX_PAD)

    box.UpdateHover = function()
        local SpecFlyout = addon.UI.ScootAuraSpecFlyout
        local over = not Drag.active
            and (box:IsMouseOver()
                or (flyout and flyout:IsOpen())
                or (SpecFlyout and SpecFlyout.IsOpenFor(specBtn))
                or false)
        specBtn:SetShown(over)
        deleteBtn:SetShown(over)
        duplicateBtn:SetShown(over)
        if layoutBtn then layoutBtn:SetShown(over) end
    end
    box:SetScript("OnEnter", box.UpdateHover)
    box:SetScript("OnLeave", box.UpdateHover)
    table.insert(state.hoverables, box)
    RegisterSpecButton("g" .. tostring(gid), specBtn, box.UpdateHover)

    state.dropGroups[gid] = { box = box, zone = zone, icons = icons }
    return box
end

--------------------------------------------------------------------------------
-- Page render
--------------------------------------------------------------------------------

-- Column heading: larger, underlined, centered over its pane.
local function ColumnLabel(pane, text, theme)
    local ar, ag, ab = theme:GetAccentColor()
    local fs = pane:CreateFontString(nil, "OVERLAY")
    fs:SetFont(theme:GetFont("LABEL"), 13, "")
    fs:SetPoint("TOP", pane, "TOP", 0, -4)
    fs:SetText(text)
    fs:SetTextColor(ar, ag, ab, 0.9)
    local underline = pane:CreateTexture(nil, "BORDER")
    underline:SetPoint("TOPLEFT", fs, "BOTTOMLEFT", -4, -3)
    underline:SetPoint("TOPRIGHT", fs, "BOTTOMRIGHT", 4, -3)
    underline:SetHeight(1)
    underline:SetColorTexture(ar, ag, ab, 0.6)
end

-- Section heading for the Not Loaded block: a hairline rule, then a dim label.
-- Returns the height it consumed.
local function NotLoadedHeading(pane, y, theme)
    local ar, ag, ab = theme:GetAccentColor()
    local rule = pane:CreateTexture(nil, "BORDER")
    rule:SetHeight(1)
    rule:SetPoint("TOPLEFT", pane, "TOPLEFT", 0, -(y + NOT_LOADED_TOP_GAP))
    rule:SetPoint("TOPRIGHT", pane, "TOPRIGHT", 0, -(y + NOT_LOADED_TOP_GAP))
    rule:SetColorTexture(ar, ag, ab, 0.25)

    local fs = pane:CreateFontString(nil, "OVERLAY")
    fs:SetFont(theme:GetFont("LABEL"), 11, "")
    fs:SetPoint("TOP", pane, "TOP", 0, -(y + NOT_LOADED_TOP_GAP + 10))
    fs:SetText("Not Loaded")
    local dr, dg, db = theme:GetDimTextColor()
    fs:SetTextColor(dr, dg, db, 1)

    return NOT_LOADED_HEADER_H
end

-- Stand-in for an empty loaded block, so a pane holding only grayed records
-- reads as a state rather than a rendering gap. Returns the height it consumed.
local function NoneLoadedText(pane, y, theme)
    local fs = pane:CreateFontString(nil, "OVERLAY")
    fs:SetFont(theme:GetFont("LABEL"), 11, "")
    fs:SetPoint("TOP", pane, "TOP", 0, -(y + NONE_LOADED_TOP_GAP))
    fs:SetText("None Loaded")
    local dr, dg, db = theme:GetDimTextColor()
    fs:SetTextColor(dr, dg, db, 1)

    return NONE_LOADED_H
end

RenderList = function(panel, scrollContent, corrective)
    if Drag.active then EndDrag(true) end

    -- An open spec fly-out survives the rebuild that its own edit asked for.
    -- Its trigger does not, so it is unpinned here and handed the replacement
    -- once the new rows exist; every re-render path runs through this bracket,
    -- the deferred corrective pass included.
    local SpecFlyout = addon.UI.ScootAuraSpecFlyout
    local specKey = SpecFlyout and SpecFlyout.GetOpenKey() or nil
    if specKey and not SpecFlyout.BeginReanchor() then specKey = nil end

    panel:ClearContent()

    local SAU = addon.ScootAuras
    local SettingsBuilder = addon.UI.SettingsBuilder

    if not (SAU and SAU.IsModuleActive()) then
        if specKey then SpecFlyout.EndReanchor(nil) end
        local builder = SettingsBuilder:CreateFor(scrollContent)
        panel._currentBuilder = builder
        builder:AddDescription(
            "ScootAuras is turned off. Enable it on the Features page, then reload.",
            { color = { 1, 0.82, 0 }, fontSize = 13, topPadding = 8 })
        builder:Finalize()
        return
    end

    state.active = true
    state.textRows = {}
    state.panel = panel
    state.scrollContent = scrollContent
    panel._scootAurasCleanup = function() Cleanup(panel) end

    local theme = addon.UI.Theme
    local ar, ag, ab = theme:GetAccentColor()
    local totalW = scrollContent:GetWidth() or 600

    -- The how-to line rides the page header as its subtitle: gray like the
    -- row meta text, hung under the title and spanning the header's width so
    -- it wraps to a second line instead of truncating. The header buttons sit
    -- on the title row above it. Cleanup restores the stock look through
    -- UIPanel:ResetHeaderSubtitle before another page reuses the FontString;
    -- the flag keeps the theme subscription from recoloring it to accent.
    local contentPane = panel.frame and panel.frame._contentPane
    if contentPane and contentPane._headerSubtitle and contentPane._header then
        local sub = contentPane._headerSubtitle
        sub:SetText(
            "Auras are shared by every character on your account and load in the specializations you pick. Click a tracker to edit it. Drag trackers into groups; drag a group's icons to reorder or remove them. Position frames in Edit Mode.")
        sub:ClearAllPoints()
        sub:SetPoint("TOPLEFT", contentPane._header, "TOPLEFT", 16, -36)
        sub:SetPoint("BOTTOMRIGHT", contentPane._header, "BOTTOMRIGHT", -16, 4)
        sub:SetFont(theme:GetFont("LABEL"), 10, "")
        sub:SetJustifyH("LEFT")
        sub:SetJustifyV("TOP")
        sub:SetWordWrap(true)
        sub:SetTextColor(0.55, 0.55, 0.55, 1)
        contentPane._headerSubtitleCustom = true
        sub:Show()
    end

    -- Header actions, right of the title.
    EnsureHeaderButtons(contentPane)
    if contentPane and contentPane._scootAuraImportBtn then
        contentPane._scootAuraImportBtn:Show()
    end

    -- Pane split: fixed offsets from the measured content width, divider
    -- between them with clearance on both sides.
    local leftW = math.floor(totalW * LEFT_FRACTION)
    local rightX = leftW + DIVIDER_CLEAR_R

    local leftPane = CreateFrame("Frame", nil, scrollContent)
    leftPane:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", 0, 0)
    leftPane:SetPoint("TOPRIGHT", scrollContent, "TOPLEFT", leftW - DIVIDER_CLEAR_L, 0)
    state.leftPane = leftPane
    table.insert(state.rows, leftPane)

    -- The tracker list takes a drop as one target: it is ordered by name, so
    -- there is no position to aim at and no insertion line to draw.
    state.leftDropZone = CreateDropZone(leftPane)

    local rightPane = CreateFrame("Frame", nil, scrollContent)
    rightPane:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", rightX, 0)
    rightPane:SetPoint("TOPRIGHT", scrollContent, "TOPRIGHT", 0, 0)
    table.insert(state.rows, rightPane)

    ColumnLabel(leftPane, "Individual Auras", theme)
    ColumnLabel(rightPane, "Groups", theme)

    -- Left pane: ungrouped trackers. Rows are no longer a fixed height: the
    -- meta line wraps, so each row reports what it needs.
    local leftRowW = math.max(80, leftW - DIVIDER_CLEAR_L)
    local yL = COL_LABEL_H
    local loadedT, unloadedT = {}, {}
    for _, item in ipairs(SAU.SortedTrackers()) do
        if item.tracker.groupId == nil then
            local bucket = SAU.IsTrackerActive(item.id, item.tracker) and loadedT or unloadedT
            table.insert(bucket, item)
        end
    end

    local function AddTrackerRows(items, loaded)
        for _, item in ipairs(items) do
            local row = CreateTrackerRow(leftPane, item.id, item.tracker, leftRowW, loaded)
            row:SetPoint("TOPLEFT", leftPane, "TOPLEFT", 0, -yL)
            row:SetPoint("TOPRIGHT", leftPane, "TOPRIGHT", 0, -yL)
            table.insert(state.rows, row)
            table.insert(state.textRows, row)
            yL = yL + row:GetHeight()
        end
    end

    if #loadedT > 0 then
        AddTrackerRows(loadedT, true)
    else
        yL = yL + NoneLoadedText(leftPane, yL, theme)
    end
    if #unloadedT > 0 then
        yL = yL + NotLoadedHeading(leftPane, yL, theme)
        AddTrackerRows(unloadedT, false)
    end

    -- Right pane: group boxes. Widths come from the content frame (pane rects
    -- resolve at end of frame, too late for the icon wrap).
    local rightW = math.max(120, totalW - rightX)
    local yR = COL_LABEL_H
    local loadedG, unloadedG = {}, {}
    for _, item in ipairs(SAU.SortedGroups()) do
        local bucket = SAU.IsGroupActive(item.id, item.group) and loadedG or unloadedG
        table.insert(bucket, item)
    end

    local function AddGroupBoxes(items, loaded)
        for _, item in ipairs(items) do
            local box = CreateGroupBox(rightPane, item.id, item.group, rightW, loaded)
            box:SetPoint("TOPLEFT", rightPane, "TOPLEFT", 0, -yR)
            box:SetPoint("TOPRIGHT", rightPane, "TOPRIGHT", 0, -yR)
            table.insert(state.rows, box)
            yR = yR + box:GetHeight() + BOX_GAP
        end
    end

    if #loadedG > 0 then
        AddGroupBoxes(loadedG, true)
    else
        yR = yR + NoneLoadedText(rightPane, yR, theme)
    end
    if #unloadedG > 0 then
        yR = yR + NotLoadedHeading(rightPane, yR, theme)
        AddGroupBoxes(unloadedG, false)
    end

    -- Content height: enough for the longer list plus the add buttons, but
    -- never shorter than the viewport, so the add buttons and the divider sit
    -- at the pane bottom even when the lists are short.
    local scrollFrame = scrollContent:GetParent()
    local viewH = (scrollFrame and scrollFrame:GetHeight()) or 0
    local contentH = math.max(yL, yR) + ADD_ROW_H + 16
    if viewH > 0 then
        contentH = math.max(contentH, viewH - 2)
    end
    scrollContent:SetHeight(contentH)
    leftPane:SetHeight(contentH)
    rightPane:SetHeight(contentH)

    -- Add buttons, statically centered at the bottom of their panes.
    local addAura = CreateAddRow(leftPane, "+ Add Aura", function()
        if addon.ShowScootAuraEditor then addon.ShowScootAuraEditor(nil) end
    end)
    addAura:SetPoint("BOTTOMLEFT", leftPane, "BOTTOMLEFT", 0, 4)
    addAura:SetPoint("BOTTOMRIGHT", leftPane, "BOTTOMRIGHT", 0, 4)
    table.insert(state.rows, addAura)

    local addGroup = CreateAddRow(rightPane, "+ Add Group", function()
        if SAU.CreateGroup(nil) then Refresh() end
    end)
    addGroup:SetPoint("BOTTOMLEFT", rightPane, "BOTTOMLEFT", 0, 4)
    addGroup:SetPoint("BOTTOMRIGHT", rightPane, "BOTTOMRIGHT", 0, 4)
    table.insert(state.rows, addGroup)

    -- Divider, full pane height regardless of list length.
    local sep = CreateFrame("Frame", nil, scrollContent)
    sep:SetSize(1, contentH)
    sep:SetPoint("TOP", scrollContent, "TOPLEFT", leftW, 0)
    local sepTex = sep:CreateTexture(nil, "BORDER")
    sepTex:SetAllPoints()
    sepTex:SetColorTexture(ar, ag, ab, 0.2)
    table.insert(state.rows, sep)

    -- Hand the fly-out its rebuilt trigger. A record that moved between the
    -- Loaded and Not Loaded blocks has a new button at a new height, so the
    -- panel jumps with it; one that is gone from the page closes it.
    if specKey then
        local entry = state.specButtons[specKey]
        SpecFlyout.EndReanchor(entry and entry.button, entry and entry.reveal)
    end

    -- The shared content scrollbar re-measures on the next frame. The first
    -- render after a page switch can also read a stale viewport height (the
    -- scroll frame re-anchors in the same tick); one corrective re-render
    -- pins the add buttons to the true bottom. The viewport height does not
    -- depend on the content, so this cannot loop.
    local pane = panel.frame and panel.frame._contentPane
    C_Timer.After(0, function()
        if pane and pane._scrollbar and pane._scrollbar.Update then
            pane._scrollbar:Update()
        end
        if state.active and state.scrollContent == scrollContent then
            local vh = (scrollFrame and scrollFrame:GetHeight()) or 0
            if vh > 0 and math.abs(vh - viewH) > 1 then
                RenderList(panel, scrollContent, corrective)
                return
            end
            -- A cold font measures short. Now that the rows have rendered
            -- once, re-measure and restack if any of them wants more room.
            -- One corrective pass only: the flag rides the recursion.
            if corrective then return end
            for _, row in ipairs(state.textRows) do
                if row._name and row._meta
                    and math.abs(MeasuredRowHeight(row._name, row._meta) - (row:GetHeight() or 0)) > 1 then
                    RenderList(panel, scrollContent, true)
                    return
                end
            end
        end
    end)
end

--------------------------------------------------------------------------------
-- Registration + external refresh hook (the editor pokes this)
--------------------------------------------------------------------------------

addon.ScootAurasUI = addon.ScootAurasUI or {}
function addon.ScootAurasUI.RefreshList()
    Refresh()
end

addon.UI.SettingsPanel:RegisterRenderer("scootAurasList", function(panel, scrollContent)
    RenderList(panel, scrollContent)
end)
