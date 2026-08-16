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
local BTN_SIZE = 16      -- group box action buttons
local BTN_GAP = 8
local ROW_BTN_SIZE = 13  -- tracker row action buttons (smaller rows)
local ROW_BTN_GAP = 6

-- The left column holds single rows; the right holds group boxes and earns
-- the wider share.
local LEFT_FRACTION = 0.38
local DIVIDER_CLEAR_L = 12   -- left pane edge to divider
local DIVIDER_CLEAR_R = 14   -- divider to group boxes

local state = {
    active = false,
    panel = nil,
    scrollContent = nil,
    rows = {},
    flyouts = {},
    dropGroups = {},      -- [gid] = { box, highlight, icons = { {frame, index} } }
    leftPane = nil,
    leftDropHighlight = nil,
}

local KIND_LABELS = { buff = "Buff", debuff = "Debuff" }
local UNIT_LABELS = { player = "Player", target = "Target", focus = "Focus" }
local SHAPE_LABELS = { icon = "Icon", bar = "Horizontal Bar", shape = "Shape" }
local GROW_LABELS = { RIGHT = "Right", LEFT = "Left", DOWN = "Down", UP = "Up" }
local GROW_ORDER = { "RIGHT", "LEFT", "DOWN", "UP" }

-- One descriptor for every surface: the tracker row's meta line, the group
-- icon's hover tooltip, and the Copy from Global rows (which pass
-- includeDisabled = false: another character's enabled state is not news).
local function TrackerMetaText(tracker, includeDisabled)
    local text = (KIND_LABELS[tracker.kind] or "?") .. " on "
        .. (UNIT_LABELS[tracker.unit] or "?") .. ", shown as "
        .. (SHAPE_LABELS[tracker.shape] or "?")
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

local function GetDragCursor()
    if Drag.cursor then return Drag.cursor end
    local f = CreateFrame("Frame", "ScootAuraListDragCursor", UIParent)
    f:SetSize(ICON_SIZE, ICON_SIZE)
    f:SetFrameStrata("TOOLTIP")
    f:SetFrameLevel(100)
    local tex = f:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f._tex = tex
    f:Hide()
    Drag.cursor = f
    return f
end

local function GetDragMarker()
    if Drag.marker then return Drag.marker end
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(2, ICON_SIZE)
    f:SetFrameStrata("TOOLTIP")
    f:SetFrameLevel(99)
    local tex = f:CreateTexture(nil, "OVERLAY")
    tex:SetAllPoints()
    tex:SetColorTexture(0.3, 0.9, 0.3, 1)
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

local function ClearDropFeedback()
    if Drag.marker then Drag.marker:Hide() end
    for _, reg in pairs(state.dropGroups) do
        if reg.highlight then reg.highlight:Hide() end
    end
    if state.leftDropHighlight then state.leftDropHighlight:Hide() end
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
    cursor:Show()
    if sourceFrame then sourceFrame:SetAlpha(0.4) end

    cursor:SetScript("OnUpdate", function(self)
        local cx, cy = GetCursorPosition()
        local scale = UIParent:GetEffectiveScale()
        cx, cy = cx / scale, cy / scale
        self:ClearAllPoints()
        self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx, cy)

        local gid, index, anchorFrame, side, ungroup = FindDropTarget(cx, cy)
        Drag.targetGid, Drag.targetIndex, Drag.targetUngroup = gid, index, ungroup

        ClearDropFeedback()
        if gid then
            local reg = state.dropGroups[gid]
            if reg and reg.highlight then reg.highlight:Show() end
            if anchorFrame then
                local marker = GetDragMarker()
                marker:ClearAllPoints()
                if side == "LEFT" then
                    marker:SetPoint("RIGHT", anchorFrame, "LEFT", -1, 0)
                else
                    marker:SetPoint("LEFT", anchorFrame, "RIGHT", 1, 0)
                end
                marker:Show()
            end
        elseif ungroup and state.leftDropHighlight then
            state.leftDropHighlight:Show()
        end
    end)

    -- The cursor frame never received OnMouseDown, so drop detection rides
    -- GLOBAL_MOUSE_UP (right button up cancels).
    if not Drag.eventFrame then
        Drag.eventFrame = CreateFrame("Frame")
    end
    Drag.eventFrame:SetScript("OnEvent", function(self, event, ...)
        if event == "GLOBAL_MOUSE_UP" then
            local button = ...
            self:UnregisterEvent("GLOBAL_MOUSE_UP")
            EndDrag(button == "RightButton")
        end
    end)
    Drag.eventFrame:RegisterEvent("GLOBAL_MOUSE_UP")
end

EndDrag = function(cancelled)
    if not Drag.active then return end
    if Drag.cursor then
        Drag.cursor:SetScript("OnUpdate", nil)
        Drag.cursor:Hide()
    end
    if Drag.eventFrame then
        Drag.eventFrame:UnregisterEvent("GLOBAL_MOUSE_UP")
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
    for gid in pairs(state.dropGroups) do
        state.dropGroups[gid] = nil
    end
    state.leftPane = nil
    state.leftDropHighlight = nil
    state.active = false
    panel._scootAurasCleanup = nil

    -- Header pieces this page borrows: the two action buttons and the
    -- restyled subtitle. The buttons and the copy fly-out are built once per
    -- window and cached (not in state.flyouts, whose entries are destroyed
    -- here), so hide and close rather than tear down.
    local contentPane = panel.frame and panel.frame._contentPane
    if contentPane then
        if contentPane._scootAuraCopyBtn then contentPane._scootAuraCopyBtn:Hide() end
        if contentPane._scootAuraImportBtn then contentPane._scootAuraImportBtn:Hide() end
        if contentPane._scootAuraCopyFlyout then contentPane._scootAuraCopyFlyout:Close() end
    end
    if panel.ResetHeaderSubtitle then panel:ResetHeaderSubtitle() end
end

--------------------------------------------------------------------------------
-- Header actions: "Import" (placeholder) and "Copy from Global"
--------------------------------------------------------------------------------

-- Built once per settings window on the shared page header, right of the
-- title, in the header's small-button recipe (see the Collapse All button in
-- settingspanel/core.lua). Shown by RenderList, hidden by Cleanup.
local function EnsureHeaderButtons(contentPane)
    if not contentPane or not contentPane._header then return end
    if contentPane._scootAuraCopyBtn then return end
    local Controls = addon.UI.Controls
    if not Controls or not Controls.CreateButton then return end
    local header = contentPane._header

    local copyBtn = Controls:CreateButton({
        parent = header,
        name = "ScootAuraCopyFromGlobalBtn",
        text = "Copy from Global",
        height = 17,
        fontSize = 10,
        borderWidth = 1,
        borderAlpha = 0.6,
        onClick = function()
            local fly = contentPane._scootAuraCopyFlyout
            if fly then fly:Toggle() end
        end,
    })
    copyBtn:SetPoint("TOPRIGHT", header, "TOPRIGHT", -16, -12)
    copyBtn:Hide()
    contentPane._scootAuraCopyBtn = copyBtn

    local importBtn = Controls:CreateButton({
        parent = header,
        name = "ScootAuraImportBtn",
        text = "Import",
        height = 17,
        fontSize = 10,
        borderWidth = 1,
        borderAlpha = 0.6,
    })
    importBtn:SetPoint("RIGHT", copyBtn, "LEFT", -8, 0)
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

    local CopyFlyout = addon.UI.ScootAuraCopyFlyout
    if CopyFlyout and CopyFlyout.Create then
        contentPane._scootAuraCopyFlyout = CopyFlyout.Create(copyBtn)
    end
end

--------------------------------------------------------------------------------
-- Shared row pieces
--------------------------------------------------------------------------------

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
    tex:SetAtlas(atlas)
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

local function CreateTrackerRow(pane, trackerId, tracker)
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

    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(ROW_ICON, ROW_ICON)
    icon:SetPoint("LEFT", row, "LEFT", PAD, 0)
    local texture = addon.ScootAuras._SpellIcon(tracker.spellId)
    icon:SetTexture(texture)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- Text stops short of where the hover buttons appear, so a long name or
    -- meta line never runs under them.
    local textClear = PAD + IND_W + 2 * (ROW_BTN_SIZE + ROW_BTN_GAP) + 6

    local textLeft = PAD + ROW_ICON + 6

    local name = row:CreateFontString(nil, "OVERLAY")
    name:SetFont(theme:GetFont("LABEL"), 8, "")
    name:SetPoint("TOPLEFT", row, "TOPLEFT", textLeft, -6)
    name:SetPoint("TOPRIGHT", row, "TOPRIGHT", -textClear, -6)
    name:SetJustifyH("LEFT")
    name:SetWordWrap(false)
    name:SetText(tracker.name or ("Aura " .. tostring(tracker.spellId)))
    name:SetTextColor(0.92, 0.92, 0.92, 1)

    local meta = row:CreateFontString(nil, "OVERLAY")
    meta:SetFont(theme:GetFont("LABEL"), 7, "")
    meta:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", textLeft, 6)
    meta:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -textClear, 6)
    meta:SetJustifyH("LEFT")
    meta:SetWordWrap(false)
    meta:SetText(TrackerMetaText(tracker))
    meta:SetTextColor(0.55, 0.55, 0.55, 1)

    if tracker.enabled == false then
        icon:SetDesaturated(true)
        name:SetTextColor(0.55, 0.55, 0.55, 1)
    end

    local deleteBtn = CreateIconButton(row, "common-icon-delete", "Delete", theme, ROW_BTN_SIZE)
    deleteBtn:SetPoint("RIGHT", row, "RIGHT", -PAD, 0)
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
    row.UpdateHover = function()
        local over = row:IsMouseOver()
        hoverBg:SetShown(over)
        deleteBtn:SetShown(over)
        duplicateBtn:SetShown(over)
        enabledBtn:SetShown(over)
    end
    row:SetScript("OnEnter", row.UpdateHover)
    row:SetScript("OnLeave", row.UpdateHover)

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

local function CreateGroupBox(pane, gid, group, boxW)
    local theme = addon.UI.Theme
    local ar, ag, ab = theme:GetAccentColor()
    local SAU = addon.ScootAuras

    local box = CreateFrame("Frame", nil, pane)
    box:EnableMouse(true)

    local bg = box:CreateTexture(nil, "BACKGROUND", nil, -8)
    bg:SetAllPoints()
    bg:SetColorTexture(ar, ag, ab, 0.04)

    local highlight = box:CreateTexture(nil, "BACKGROUND", nil, -7)
    highlight:SetAllPoints()
    highlight:SetColorTexture(ar, ag, ab, 0.12)
    highlight:Hide()

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
    nameBtn:SetWidth(math.max(20, math.min(nameFS:GetStringWidth() + 6, boxW - 130)))

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
    renameBox:SetPoint("TOPRIGHT", box, "TOPRIGHT", -90, -4)
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

    -- Hover-revealed actions, left to right: layout gear, duplicate, delete.
    local deleteBtn = CreateIconButton(box, "common-icon-delete", "Delete Group", theme)
    deleteBtn:SetPoint("TOPRIGHT", box, "TOPRIGHT", -BOX_PAD, -5)
    local duplicateBtn = CreateIconButton(box, "friends-icon-battlenet-copy", "Duplicate Group", theme)
    duplicateBtn:SetPoint("RIGHT", deleteBtn, "LEFT", -BTN_GAP, 0)
    local layoutBtn = CreateIconButton(box, "GM-icon-settings", "Layout", theme, BTN_SIZE, 2)
    layoutBtn:SetPoint("RIGHT", duplicateBtn, "LEFT", -BTN_GAP, 0)

    local flyout = CreateGroupFlyout(layoutBtn, gid)
    layoutBtn:SetScript("OnClick", function()
        if ClickGuard() then return end
        flyout:Toggle()
    end)

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
                -(BOX_HEADER_H + rowIdx * (ICON_SIZE + ICON_GAP)))

            local tex = btn:CreateTexture(nil, "ARTWORK")
            tex:SetAllPoints()
            local texture = addon.ScootAuras._SpellIcon(tracker.spellId)
            tex:SetTexture(texture)
            tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            if tracker.enabled == false then tex:SetDesaturated(true) end

            btn:SetScript("OnEnter", function(self)
                if box.UpdateHover then box.UpdateHover() end
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(tracker.name or ("Aura " .. tostring(tracker.spellId)), 1, 1, 1)
                GameTooltip:AddLine(TrackerMetaText(tracker), 0.7, 0.7, 0.7, true)
                GameTooltip:Show()
            end)
            btn:SetScript("OnLeave", function()
                GameTooltip:Hide()
                if box.UpdateHover then box.UpdateHover() end
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
        hint:SetPoint("TOPLEFT", box, "TOPLEFT", BOX_PAD, -(BOX_HEADER_H + 8))
        hint:SetText("Drag trackers here")
        hint:SetTextColor(0.55, 0.55, 0.55, 1)
    end

    local iconRows = math.max(1, math.ceil(shown / perRow))
    box:SetHeight(BOX_HEADER_H + iconRows * (ICON_SIZE + ICON_GAP) + BOX_PAD)

    box.UpdateHover = function()
        local over = box:IsMouseOver() or (flyout and flyout:IsOpen())
        deleteBtn:SetShown(over)
        duplicateBtn:SetShown(over)
        layoutBtn:SetShown(over)
    end
    box:SetScript("OnEnter", box.UpdateHover)
    box:SetScript("OnLeave", box.UpdateHover)

    state.dropGroups[gid] = { box = box, highlight = highlight, icons = icons }
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

RenderList = function(panel, scrollContent)
    if Drag.active then EndDrag(true) end
    panel:ClearContent()

    local SAU = addon.ScootAuras
    local SettingsBuilder = addon.UI.SettingsBuilder

    if not (SAU and SAU.IsModuleActive()) then
        local builder = SettingsBuilder:CreateFor(scrollContent)
        panel._currentBuilder = builder
        builder:AddDescription(
            "ScootAuras is turned off. Enable it on the Features page, then reload.",
            { color = { 1, 0.82, 0 }, fontSize = 13, topPadding = 8 })
        builder:Finalize()
        return
    end

    state.active = true
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
            "Click a tracker to edit it. Drag trackers into groups; drag a group's icons to reorder or remove them. Position frames in Edit Mode.")
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
    if contentPane and contentPane._scootAuraCopyBtn then
        contentPane._scootAuraCopyBtn:Show()
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

    local leftHl = leftPane:CreateTexture(nil, "BACKGROUND", nil, -8)
    leftHl:SetAllPoints()
    leftHl:SetColorTexture(ar, ag, ab, 0.06)
    leftHl:Hide()
    state.leftDropHighlight = leftHl

    local rightPane = CreateFrame("Frame", nil, scrollContent)
    rightPane:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", rightX, 0)
    rightPane:SetPoint("TOPRIGHT", scrollContent, "TOPRIGHT", 0, 0)
    table.insert(state.rows, rightPane)

    ColumnLabel(leftPane, "Individual Auras", theme)
    ColumnLabel(rightPane, "Groups", theme)

    -- Left pane: ungrouped trackers.
    local yL = COL_LABEL_H
    for _, item in ipairs(SAU.SortedTrackers()) do
        if item.tracker.groupId == nil then
            local row = CreateTrackerRow(leftPane, item.id, item.tracker)
            row:SetPoint("TOPLEFT", leftPane, "TOPLEFT", 0, -yL)
            row:SetPoint("TOPRIGHT", leftPane, "TOPRIGHT", 0, -yL)
            table.insert(state.rows, row)
            yL = yL + ROW_H
        end
    end

    -- Right pane: group boxes. Widths come from the content frame (pane rects
    -- resolve at end of frame, too late for the icon wrap).
    local rightW = math.max(120, totalW - rightX)
    local yR = COL_LABEL_H
    for _, item in ipairs(SAU.SortedGroups()) do
        local box = CreateGroupBox(rightPane, item.id, item.group, rightW)
        box:SetPoint("TOPLEFT", rightPane, "TOPLEFT", 0, -yR)
        box:SetPoint("TOPRIGHT", rightPane, "TOPRIGHT", 0, -yR)
        table.insert(state.rows, box)
        yR = yR + box:GetHeight() + BOX_GAP
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
                RenderList(panel, scrollContent)
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
