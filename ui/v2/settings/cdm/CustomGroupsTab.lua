-- CustomGroupsTab.lua - Inject a Scoot tab into Blizzard's Cooldown Manager window
-- with full custom groups management UI (3 collapsible groups, drag-and-drop, reorder)
local addonName, addon = ...

local CG = addon.CustomGroups

local SCOOT_ICON = "Interface\\AddOns\\Scoot\\ScootIcon"
local DISPLAY_MODE = "scoot"
local ICON_SIZE = 38
local ICON_PADDING = 8
local GRID_STRIDE = 7
local CATEGORY_SPACING = 18
local DROP_TARGET_ICON = "Interface\\PaperDollInfoFrame\\Character-Plus"

local injected = false
local isScootTabActive = false

--------------------------------------------------------------------------------
-- Utility: Resolve icon texture for a spell or item
--------------------------------------------------------------------------------

local function GetEntryTexture(entry)
    if not entry then return nil end
    if entry.type == "spell" then
        local info = C_Spell.GetSpellInfo(entry.id)
        return info and info.iconID or nil
    elseif entry.type == "item" then
        return C_Item.GetItemIconByID(entry.id)
    end
    return nil
end

local function GetEntryName(entry)
    if not entry then return "Unknown" end
    if entry.type == "spell" then
        local info = C_Spell.GetSpellInfo(entry.id)
        return info and info.name or ("Spell #" .. entry.id)
    elseif entry.type == "item" then
        local name = C_Item.GetItemNameByID(entry.id)
        return name or ("Item #" .. entry.id)
    end
    return "Unknown"
end

--------------------------------------------------------------------------------
-- Drag System State
--------------------------------------------------------------------------------

local DragState = {
    active = false,
    sourceGroup = nil,
    sourceIndex = nil,
    cursorFrame = nil,
    reorderMarker = nil,
    targetGroup = nil,
    targetIndex = nil,
}

--------------------------------------------------------------------------------
-- Content Frame: 3 collapsible custom groups with icon grids
--------------------------------------------------------------------------------

local contentFrame
local categoryFrames = {}  -- [1..3] = category display frames
local itemPools = {}       -- [1..3] = arrays of item frames (reused)
local dropTargets = {}     -- [1..3] = drop target frames

-- Forward declarations
local RefreshCategory, RefreshAllCategories

--------------------------------------------------------------------------------
-- Drop Target: green "+" frame that accepts cursor items
--------------------------------------------------------------------------------

local function CreateDropTarget(parent, groupIndex)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(ICON_SIZE, ICON_SIZE)

    -- Background
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.15, 0.15, 0.15, 0.8)

    -- Plus icon
    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(DROP_TARGET_ICON)
    icon:SetSize(24, 24)
    icon:SetPoint("CENTER")
    icon:SetVertexColor(0.3, 0.9, 0.3, 0.8)

    -- Highlight
    local hl = f:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(0.3, 0.9, 0.3, 0.2)

    -- Border
    local border = f:CreateTexture(nil, "OVERLAY")
    border:SetPoint("TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", 1, -1)
    border:SetColorTexture(0.3, 0.9, 0.3, 0.4)
    local inner = f:CreateTexture(nil, "ARTWORK", nil, 1)
    inner:SetAllPoints()
    inner:SetColorTexture(0, 0, 0, 0) -- transparent, border is the outer frame
    -- Actually make a proper border using 4 edge textures
    border:Hide()
    local function MakeBorderEdge(point1, rel1, point2, rel2, w, h)
        local edge = f:CreateTexture(nil, "OVERLAY")
        edge:SetColorTexture(0.3, 0.9, 0.3, 0.5)
        edge:SetPoint(point1, f, rel1)
        edge:SetPoint(point2, f, rel2)
        if w then edge:SetWidth(w) end
        if h then edge:SetHeight(h) end
        return edge
    end
    MakeBorderEdge("TOPLEFT", "TOPLEFT", "TOPRIGHT", "TOPRIGHT", nil, 1)
    MakeBorderEdge("BOTTOMLEFT", "BOTTOMLEFT", "BOTTOMRIGHT", "BOTTOMRIGHT", nil, 1)
    MakeBorderEdge("TOPLEFT", "TOPLEFT", "BOTTOMLEFT", "BOTTOMLEFT", 1, nil)
    MakeBorderEdge("TOPRIGHT", "TOPRIGHT", "BOTTOMRIGHT", "BOTTOMRIGHT", 1, nil)

    f:EnableMouse(true)

    -- Tooltip
    f:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Add Spell or Item", 1, 1, 1)
        GameTooltip:AddLine("Drag a Spell, Ability, or Item here\nto track its cooldown.", 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- Accept cursor drop
    local function TryAcceptCursor()
        -- GetCursorInfo returns: type, info1, info2, spellID
        -- For "spell": type, subType, _, spellID
        -- For "item":  type, itemID
        local infoType, info1, _, info3 = GetCursorInfo()
        if not infoType then return false end

        if infoType == "spell" then
            -- spellID is the 4th return value in modern WoW
            local spellID = info3 or info1
            if spellID and CG.AddEntry(groupIndex, "spell", spellID) then
                ClearCursor()
                RefreshAllCategories()
                return true
            end
        elseif infoType == "item" then
            local itemID = info1
            if itemID and CG.AddEntry(groupIndex, "item", itemID) then
                ClearCursor()
                RefreshAllCategories()
                return true
            end
        end
        return false
    end

    f:SetScript("OnReceiveDrag", function()
        TryAcceptCursor()
    end)
    f:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" then
            TryAcceptCursor()
        end
    end)

    return f
end

--------------------------------------------------------------------------------
-- Item Frame: 38x38 icon with tooltip, right-click remove, left-click drag
--------------------------------------------------------------------------------

local function CreateItemFrame(parent, groupIndex)
    local f = CreateFrame("Button", nil, parent)
    f:SetSize(ICON_SIZE, ICON_SIZE)
    f:RegisterForClicks("AnyUp")
    f:RegisterForDrag("LeftButton")

    -- Icon texture
    f.Icon = f:CreateTexture(nil, "ARTWORK")
    f.Icon:SetAllPoints()
    f.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) -- Standard icon crop

    -- Highlight
    local hl = f:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.2)

    -- Border (subtle dark)
    local function MakeEdge(p1, r1, p2, r2, w, h)
        local e = f:CreateTexture(nil, "OVERLAY")
        e:SetColorTexture(0, 0, 0, 0.8)
        e:SetPoint(p1, f, r1)
        e:SetPoint(p2, f, r2)
        if w then e:SetWidth(w) end
        if h then e:SetHeight(h) end
    end
    MakeEdge("TOPLEFT", "TOPLEFT", "TOPRIGHT", "TOPRIGHT", nil, 1)
    MakeEdge("BOTTOMLEFT", "BOTTOMLEFT", "BOTTOMRIGHT", "BOTTOMRIGHT", nil, 1)
    MakeEdge("TOPLEFT", "TOPLEFT", "BOTTOMLEFT", "BOTTOMLEFT", 1, nil)
    MakeEdge("TOPRIGHT", "TOPRIGHT", "BOTTOMRIGHT", "BOTTOMRIGHT", 1, nil)

    -- Desaturation overlay for locked/dragging state
    f._groupIndex = groupIndex
    f._entryIndex = nil
    f._entry = nil

    -- Tooltip
    f:SetScript("OnEnter", function(self)
        if DragState.active then return end
        if not self._entry then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if self._entry.type == "spell" then
            GameTooltip:SetSpellByID(self._entry.id)
        elseif self._entry.type == "item" then
            GameTooltip:SetItemByID(self._entry.id)
        end
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- Right-click: remove
    f:SetScript("OnClick", function(self, button)
        if button == "RightButton" and self._entry and self._entryIndex then
            -- Use MenuUtil context menu
            if MenuUtil and MenuUtil.CreateContextMenu then
                MenuUtil.CreateContextMenu(self, function(ownerRegion, rootDescription)
                    rootDescription:CreateButton("Remove from Group", function()
                        CG.RemoveEntry(self._groupIndex, self._entryIndex)
                        RefreshAllCategories()
                    end)
                end)
            else
                -- Fallback: just remove directly
                CG.RemoveEntry(self._groupIndex, self._entryIndex)
                RefreshAllCategories()
            end
        end
    end)

    -- Left drag: begin reorder
    f:SetScript("OnDragStart", function(self)
        if not self._entry or not self._entryIndex then return end
        BeginDrag(self._groupIndex, self._entryIndex, self)
    end)

    return f
end

--------------------------------------------------------------------------------
-- Drag Cursor Frame (follows mouse during reorder)
--------------------------------------------------------------------------------

local function GetOrCreateDragCursor()
    if DragState.cursorFrame then return DragState.cursorFrame end

    local f = CreateFrame("Frame", "ScootCDMDragCursor", UIParent)
    f:SetSize(ICON_SIZE, ICON_SIZE)
    f:SetFrameStrata("TOOLTIP")
    f:SetFrameLevel(100)

    f.Icon = f:CreateTexture(nil, "ARTWORK")
    f.Icon:SetAllPoints()
    f.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    f:Hide()

    DragState.cursorFrame = f
    return f
end

local function GetOrCreateReorderMarker()
    if DragState.reorderMarker then return DragState.reorderMarker end

    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(2, ICON_SIZE)
    f:SetFrameStrata("TOOLTIP")
    f:SetFrameLevel(99)

    local tex = f:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    tex:SetColorTexture(0.3, 0.9, 0.3, 1)

    f:Hide()

    DragState.reorderMarker = f
    return f
end

--------------------------------------------------------------------------------
-- Drag-and-Drop Reorder System
--------------------------------------------------------------------------------

-- Find the nearest item frame under the cursor across all categories.
-- Returns: (group, insertDataIndex, anchorFrame, anchorSide)
-- insertDataIndex is the position in the full data model (not the filtered pool).
local function FindNearestTarget(cursorX, cursorY)
    local bestDist = math.huge
    local bestGroup, bestDataIndex, bestAnchorFrame, bestAnchorSide = nil, nil, nil, nil

    for gi = 1, 3 do
        local pool = itemPools[gi]
        if pool then
            for _, itemFrame in ipairs(pool) do
                if itemFrame:IsShown() and itemFrame._entryIndex then
                    local left = itemFrame:GetLeft()
                    local right = itemFrame:GetRight()
                    local top = itemFrame:GetTop()
                    local bottom = itemFrame:GetBottom()

                    if left and right and top and bottom then
                        local cx = (left + right) / 2
                        local cy = (top + bottom) / 2
                        local dist = (cursorX - cx)^2 + (cursorY - cy)^2

                        if dist < bestDist then
                            bestDist = dist
                            bestGroup = gi
                            if cursorX < cx then
                                -- Insert before this item
                                bestDataIndex = itemFrame._entryIndex
                                bestAnchorFrame = itemFrame
                                bestAnchorSide = "LEFT"
                            else
                                -- Insert after this item
                                bestDataIndex = itemFrame._entryIndex + 1
                                bestAnchorFrame = itemFrame
                                bestAnchorSide = "RIGHT"
                            end
                        end
                    end
                end
            end
        end

        -- Also check the drop target area for "append at end"
        local dt = dropTargets[gi]
        if dt and dt:IsShown() then
            local left = dt:GetLeft()
            local right = dt:GetRight()
            local top = dt:GetTop()
            local bottom = dt:GetBottom()
            if left and right and top and bottom then
                local cx = (left + right) / 2
                local cy = (top + bottom) / 2
                local dist = (cursorX - cx)^2 + (cursorY - cy)^2
                if dist < bestDist then
                    bestDist = dist
                    bestGroup = gi
                    local allEntries = CG.GetEntries(gi)
                    bestDataIndex = #allEntries + 1
                    bestAnchorFrame = dt
                    bestAnchorSide = "LEFT"
                end
            end
        end
    end

    if bestGroup and bestDataIndex then
        return bestGroup, bestDataIndex, bestAnchorFrame, bestAnchorSide
    end

    return nil, nil, nil, nil
end

function BeginDrag(groupIndex, entryIndex, sourceFrame)
    DragState.active = true
    DragState.sourceGroup = groupIndex
    DragState.sourceIndex = entryIndex

    -- Setup drag cursor
    local cursor = GetOrCreateDragCursor()
    local entry = CG.GetEntries(groupIndex)[entryIndex]
    if entry then
        cursor.Icon:SetTexture(GetEntryTexture(entry))
    end
    cursor:SetAlpha(0.8)
    cursor:Show()

    -- Desaturate source
    if sourceFrame then
        sourceFrame.Icon:SetDesaturated(true)
        sourceFrame:SetAlpha(0.4)
    end

    local marker = GetOrCreateReorderMarker()
    DragState._sourceFrame = sourceFrame

    -- Track mouse with OnUpdate
    cursor:SetScript("OnUpdate", function(self)
        local x, y = GetCursorPosition()
        local scale = UIParent:GetEffectiveScale()
        x, y = x / scale, y / scale
        self:ClearAllPoints()
        self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)

        -- Find nearest target (returns data model index + anchor info)
        local tGroup, tIndex, anchorFrame, anchorSide = FindNearestTarget(x, y)
        DragState.targetGroup = tGroup
        DragState.targetIndex = tIndex

        -- Update reorder marker using anchor info from FindNearestTarget
        if anchorFrame then
            marker:ClearAllPoints()
            marker:SetParent(anchorFrame:GetParent())
            if anchorSide == "LEFT" then
                marker:SetPoint("RIGHT", anchorFrame, "LEFT", -2, 0)
            else
                marker:SetPoint("LEFT", anchorFrame, "RIGHT", 2, 0)
            end
            marker:Show()
        else
            marker:Hide()
        end
    end)

    -- Use an event frame to detect global mouse up (more reliable than OnMouseUp
    -- on the cursor frame, which requires the frame to have received OnMouseDown)
    if not DragState._eventFrame then
        DragState._eventFrame = CreateFrame("Frame")
    end
    DragState._eventFrame:SetScript("OnEvent", function(self, event, ...)
        if event == "GLOBAL_MOUSE_UP" then
            local button = ...
            self:UnregisterEvent("GLOBAL_MOUSE_UP")
            EndDrag(button == "RightButton")
        end
    end)
    DragState._eventFrame:RegisterEvent("GLOBAL_MOUSE_UP")
end

function EndDrag(cancelled)
    if not DragState.active then return end

    local cursor = DragState.cursorFrame
    local marker = DragState.reorderMarker

    if cursor then
        cursor:SetScript("OnUpdate", nil)
        cursor:Hide()
    end

    -- Ensure event frame is cleaned up
    if DragState._eventFrame then
        DragState._eventFrame:UnregisterEvent("GLOBAL_MOUSE_UP")
    end
    if marker then
        marker:Hide()
    end

    -- Restore source frame
    if DragState._sourceFrame then
        DragState._sourceFrame.Icon:SetDesaturated(false)
        DragState._sourceFrame:SetAlpha(1)
    end

    if not cancelled and DragState.targetGroup and DragState.targetIndex then
        local srcGroup = DragState.sourceGroup
        local srcIndex = DragState.sourceIndex
        local dstGroup = DragState.targetGroup
        local dstIndex = DragState.targetIndex

        if srcGroup == dstGroup then
            -- Adjust index if moving within same group
            if srcIndex < dstIndex then
                dstIndex = dstIndex - 1
            end
            CG.ReorderEntry(srcGroup, srcIndex, dstIndex)
        else
            CG.MoveEntry(srcGroup, srcIndex, dstGroup, dstIndex)
        end
    end

    DragState.active = false
    DragState.sourceGroup = nil
    DragState.sourceIndex = nil
    DragState.targetGroup = nil
    DragState.targetIndex = nil
    DragState._sourceFrame = nil

    RefreshAllCategories()
end

--------------------------------------------------------------------------------
-- Category Frame: Header + Grid container
--------------------------------------------------------------------------------

local HEADER_HEIGHT = 26  -- matches ListHeaderThreeSliceTemplate

local function CreateCategoryFrame(parent, groupIndex)
    local cat = CreateFrame("Frame", "ScootCDMCategory" .. groupIndex, parent)
    cat:SetWidth(parent:GetWidth() or 300)
    cat._groupIndex = groupIndex
    cat._collapsed = false

    -- Blizzard ListHeaderThreeSliceTemplate: 3-slice background with expand/collapse arrow
    local header = CreateFrame("Button", nil, cat, "ListHeaderThreeSliceTemplate")
    header:SetHeight(HEADER_HEIGHT)
    header:SetPoint("TOPLEFT", cat, "TOPLEFT", 0, 0)
    header:SetPoint("TOPRIGHT", cat, "TOPRIGHT", 0, 0)

    header:SetTitleColor(false, NORMAL_FONT_COLOR)
    header:SetTitleColor(true, NORMAL_FONT_COLOR)
    header:SetHeaderText(CG.GetGroupDisplayName(groupIndex))
    header:UpdateCollapsedState(false)  -- start expanded

    -- Subtitle: "Custom Group X" (only visible when a custom name is set)
    local subtitle = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    subtitle:SetTextColor(0.5, 0.5, 0.5)
    subtitle:SetText("(Custom Group " .. groupIndex .. ")")
    if CG.GetGroupName(groupIndex) then
        subtitle:Show()
    else
        subtitle:Hide()
    end
    cat._subtitle = subtitle

    -- Rename button — pencil icon, parented to cat (above the header Button's click region)
    local renameBtn = CreateFrame("Button", nil, cat)
    renameBtn:SetSize(16, HEADER_HEIGHT)
    renameBtn:SetFrameLevel(header:GetFrameLevel() + 10)

    local renameIcon = renameBtn:CreateTexture(nil, "ARTWORK")
    renameIcon:SetAtlas("Pencil-Icon")
    renameIcon:SetSize(16, 16)
    renameIcon:SetPoint("CENTER", 0, 0)
    renameIcon:SetAlpha(0.35)
    renameBtn._icon = renameIcon

    -- Position rename button right after the header text content
    local function UpdateRenamePosition()
        renameBtn:ClearAllPoints()
        local textWidth = header.Name and header.Name:GetStringWidth() or 100
        renameBtn:SetPoint("LEFT", header, "LEFT", 10 + textWidth + 4, 0)
    end
    cat._updateRenamePosition = UpdateRenamePosition
    UpdateRenamePosition()

    renameBtn:SetScript("OnEnter", function(self)
        self._icon:SetAlpha(0.8)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Rename Group", 1, 1, 1)
        GameTooltip:Show()
    end)
    renameBtn:SetScript("OnLeave", function(self)
        self._icon:SetAlpha(0.35)
        GameTooltip:Hide()
    end)
    cat._renameBtn = renameBtn

    -- Anchor subtitle to the right side of the header (where countText used to be)
    subtitle:SetPoint("RIGHT", header.Right, "LEFT", -4, 0)

    -- Inline EditBox for renaming (hidden by default)
    local editBox = CreateFrame("EditBox", nil, header, "InputBoxTemplate")
    editBox:SetSize(160, 20)
    editBox:SetPoint("LEFT", header.Name, "LEFT", -2, 0)
    editBox:SetAutoFocus(false)
    editBox:SetMaxLetters(32)
    editBox:SetFrameLevel(header:GetFrameLevel() + 10)

    -- Match header font
    local fontPath, fontSize = header.Name:GetFont()
    if fontPath then
        editBox:SetFont(fontPath, fontSize or 13, "")
    end

    -- Hide the chrome (InputBoxTemplate has Left/Right/Middle textures)
    if editBox.Left then editBox.Left:Hide() end
    if editBox.Right then editBox.Right:Hide() end
    if editBox.Middle then editBox.Middle:Hide() end

    editBox:Hide()
    cat._editBox = editBox

    local function BeginRename()
        local currentName = CG.GetGroupName(groupIndex) or ""
        editBox:SetText(currentName)
        header.Name:Hide()
        renameBtn:Hide()
        subtitle:Hide()
        editBox:Show()
        editBox:SetFocus()
        editBox:HighlightText()
    end

    local function CommitRename()
        local newName = editBox:GetText()
        editBox:ClearFocus()
        editBox:Hide()
        CG.SetGroupName(groupIndex, newName)
        header:SetHeaderText(CG.GetGroupDisplayName(groupIndex))
        header.Name:Show()
        renameBtn:Show()
        UpdateRenamePosition()
        if CG.GetGroupName(groupIndex) then
            subtitle:Show()
        else
            subtitle:Hide()
        end
    end

    local function CancelRename()
        editBox:ClearFocus()
        editBox:Hide()
        header.Name:Show()
        renameBtn:Show()
        if CG.GetGroupName(groupIndex) then
            subtitle:Show()
        end
    end

    renameBtn:SetScript("OnClick", function()
        BeginRename()
    end)

    editBox:SetScript("OnEnterPressed", function()
        CommitRename()
    end)

    editBox:SetScript("OnEscapePressed", function()
        CancelRename()
    end)

    editBox:SetScript("OnEditFocusLost", function()
        if editBox:IsShown() then
            CancelRename()
        end
    end)

    -- Click to toggle collapse
    header:SetClickHandler(function()
        cat._collapsed = not cat._collapsed
        header:UpdateCollapsedState(cat._collapsed)
        RefreshCategory(groupIndex)
    end)

    cat._header = header

    -- Container for icons (below header)
    local container = CreateFrame("Frame", nil, cat)
    container:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -10)
    container:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, -10)
    cat._container = container

    -- Item frame pool
    itemPools[groupIndex] = {}

    -- Drop target
    dropTargets[groupIndex] = CreateDropTarget(container, groupIndex)

    return cat
end

--------------------------------------------------------------------------------
-- Layout: Position icons in a grid within a category container
--------------------------------------------------------------------------------

local function LayoutGrid(groupIndex)
    local cat = categoryFrames[groupIndex]
    if not cat then return end

    local container = cat._container
    local entries = CG.GetEntries(groupIndex)
    local pool = itemPools[groupIndex]
    local dt = dropTargets[groupIndex]

    if cat._collapsed then
        container:Hide()
        cat:SetHeight(HEADER_HEIGHT)
        return
    end

    container:Show()

    -- Filter entries by character access
    local visibleEntries = {}
    for dataIdx, entry in ipairs(entries) do
        if CG.IsEntryVisible(entry) then
            table.insert(visibleEntries, { entry = entry, dataIndex = dataIdx })
        end
    end

    -- Ensure we have enough item frames
    while #pool < #visibleEntries do
        local item = CreateItemFrame(container, groupIndex)
        table.insert(pool, item)
    end

    -- Position items in grid
    local col = 0
    local row = 0
    local totalItems = 0

    -- Drop target is always first
    dt:ClearAllPoints()
    dt:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
    dt:Show()
    col = 1
    totalItems = 1

    for i, vis in ipairs(visibleEntries) do
        local item = pool[i]
        item._entry = vis.entry
        item._entryIndex = vis.dataIndex
        item._groupIndex = groupIndex

        -- Set texture
        local tex = GetEntryTexture(vis.entry)
        if tex then
            item.Icon:SetTexture(tex)
            item.Icon:SetDesaturated(false)
        else
            item.Icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
            item.Icon:SetDesaturated(true)
        end

        -- Position in grid
        if col >= GRID_STRIDE then
            col = 0
            row = row + 1
        end

        item:ClearAllPoints()
        item:SetPoint("TOPLEFT", container, "TOPLEFT",
            col * (ICON_SIZE + ICON_PADDING),
            -(row * (ICON_SIZE + ICON_PADDING)))
        item:Show()

        col = col + 1
        totalItems = totalItems + 1
    end

    -- Hide excess pool items
    for i = #visibleEntries + 1, #pool do
        pool[i]:Hide()
    end

    -- Calculate container height
    local totalRows = math.ceil(totalItems / GRID_STRIDE)
    local containerHeight = math.max(ICON_SIZE, totalRows * (ICON_SIZE + ICON_PADDING) - ICON_PADDING)
    container:SetHeight(containerHeight)

    -- Category total height = header + gap + container
    cat:SetHeight(HEADER_HEIGHT + 10 + containerHeight)

end

RefreshCategory = function(groupIndex)
    LayoutGrid(groupIndex)
    -- Re-stack categories and update scroll height
    if contentFrame then
        local totalHeight = 0
        for i = 1, 3 do
            local cat = categoryFrames[i]
            if cat then
                cat:ClearAllPoints()
                cat:SetPoint("TOPLEFT", contentFrame._scrollChild, "TOPLEFT", 0, -totalHeight)
                cat:SetPoint("RIGHT", contentFrame._scrollChild, "RIGHT", 0, 0)
                totalHeight = totalHeight + cat:GetHeight() + CATEGORY_SPACING
            end
        end
        contentFrame._scrollChild:SetHeight(math.max(totalHeight, 100))
    end
end

RefreshAllCategories = function()
    for i = 1, 3 do
        LayoutGrid(i)
    end
    -- Re-stack categories
    if contentFrame then
        local totalHeight = 0
        for i = 1, 3 do
            local cat = categoryFrames[i]
            if cat then
                cat:ClearAllPoints()
                cat:SetPoint("TOPLEFT", contentFrame._scrollChild, "TOPLEFT", 0, -totalHeight)
                cat:SetPoint("RIGHT", contentFrame._scrollChild, "RIGHT", 0, 0)
                totalHeight = totalHeight + cat:GetHeight() + CATEGORY_SPACING
            end
        end
        contentFrame._scrollChild:SetHeight(math.max(totalHeight, 100))
    end
end

--------------------------------------------------------------------------------
-- Content Frame Creation
--------------------------------------------------------------------------------

local function CreateContentFrame(cdmFrame)
    local f = CreateFrame("ScrollFrame", "ScootCDMContent", cdmFrame)
    f:SetPoint("TOPLEFT", 17, -72)
    f:SetPoint("BOTTOMRIGHT", -30, 29)
    f:Hide()
    f:EnableMouseWheel(true)

    -- Scroll child
    local scrollChild = CreateFrame("Frame", "ScootCDMScrollChild", f)
    scrollChild:SetWidth(f:GetWidth() or 300)
    f:SetScrollChild(scrollChild)
    f._scrollChild = scrollChild

    -- Mouse wheel scrolling
    f:SetScript("OnMouseWheel", function(self, delta)
        local current = self:GetVerticalScroll() or 0
        local childHeight = scrollChild:GetHeight() or 0
        local visibleHeight = self:GetHeight() or 1
        local maxScroll = math.max(0, childHeight - visibleHeight)

        local step = ICON_SIZE * 2
        local newScroll = current - (delta * step)
        newScroll = math.max(0, math.min(maxScroll, newScroll))
        self:SetVerticalScroll(newScroll)
    end)

    -- Fix scroll child width on size change
    f:SetScript("OnSizeChanged", function(self, w, h)
        scrollChild:SetWidth(w)
    end)

    -- Create the 3 category frames
    for i = 1, 3 do
        categoryFrames[i] = CreateCategoryFrame(scrollChild, i)
    end

    -- Register for data change callbacks
    CG.RegisterCallback(function()
        -- Update header texts, subtitles, and rename button positions for all 3 categories
        for i = 1, 3 do
            local cat = categoryFrames[i]
            if cat and cat._header then
                cat._header:SetHeaderText(CG.GetGroupDisplayName(i))
                if cat._subtitle then
                    if CG.GetGroupName(i) then
                        cat._subtitle:Show()
                    else
                        cat._subtitle:Hide()
                    end
                end
                if cat._updateRenamePosition then
                    cat._updateRenamePosition()
                end
            end
        end
        if f:IsShown() then
            RefreshAllCategories()
        end
    end)

    -- Event-driven refresh for visibility changes (items acquired, spells learned)
    local refreshEventFrame = CreateFrame("Frame")
    local refreshPending = false

    local function DebouncedRefresh()
        if not refreshPending then
            refreshPending = true
            C_Timer.After(0.3, function()
                refreshPending = false
                if f:IsShown() then
                    RefreshAllCategories()
                end
            end)
        end
    end

    refreshEventFrame:SetScript("OnEvent", function()
        DebouncedRefresh()
    end)

    -- Refresh on show
    f:SetScript("OnShow", function()
        -- Register visibility events while tab is open
        refreshEventFrame:RegisterEvent("BAG_UPDATE")
        refreshEventFrame:RegisterEvent("SPELLS_CHANGED")
        refreshEventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")

        -- Ensure scroll child width matches
        scrollChild:SetWidth(f:GetWidth() or 300)
        -- Refresh header texts (handles profile switches)
        for i = 1, 3 do
            local cat = categoryFrames[i]
            if cat and cat._header then
                cat._header:SetHeaderText(CG.GetGroupDisplayName(i))
                if cat._subtitle then
                    if CG.GetGroupName(i) then
                        cat._subtitle:Show()
                    else
                        cat._subtitle:Hide()
                    end
                end
                if cat._updateRenamePosition then
                    cat._updateRenamePosition()
                end
            end
        end
        RefreshAllCategories()
    end)

    f:SetScript("OnHide", function()
        refreshEventFrame:UnregisterAllEvents()
    end)

    contentFrame = f
    return f
end

--------------------------------------------------------------------------------
-- Tab Button Construction (mirrors LargeSideTabButtonTemplate)
--------------------------------------------------------------------------------

local function CreateTabButton(cdmFrame)
    local tab = CreateFrame("Frame", "ScootCDMTab", cdmFrame)
    tab:SetSize(43, 55)
    tab:EnableMouse(true)
    Mixin(tab, SidePanelTabButtonMixin)

    -- BACKGROUND layer: tab frame graphic
    tab.Background = tab:CreateTexture(nil, "BACKGROUND")
    tab.Background:SetAtlas("questlog-tab-side", true)
    tab.Background:SetPoint("CENTER")

    -- ARTWORK layer: Scoot icon
    tab.Icon = tab:CreateTexture(nil, "ARTWORK")
    tab.Icon:SetTexture(SCOOT_ICON)
    tab.Icon:SetSize(28, 28)
    tab.Icon:SetPoint("CENTER", -2, 0)

    -- OVERLAY layer: selection glow
    tab.SelectedTexture = tab:CreateTexture(nil, "OVERLAY")
    tab.SelectedTexture:SetAtlas("QuestLog-Tab-side-Glow-select", true)
    tab.SelectedTexture:SetPoint("CENTER")
    tab.SelectedTexture:Hide()

    -- HIGHLIGHT layer: hover glow
    local highlight = tab:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAtlas("QuestLog-Tab-side-Glow-hover", true)
    highlight:SetPoint("CENTER")

    -- Properties expected by the tab system
    tab.displayMode = DISPLAY_MODE
    tab.tooltipText = "Scoot"

    -- Override SetChecked: the mixin calls SetAtlas on Icon, but we use a .tga file.
    function tab:SetChecked(checked)
        if self.SelectedTexture then
            self.SelectedTexture:SetShown(checked)
        end
        if checked then
            self.Icon:SetVertexColor(1, 1, 1)
        else
            self.Icon:SetVertexColor(0.75, 0.75, 0.75)
        end
    end

    -- Wire up script handlers from the mixin
    tab:SetScript("OnMouseDown", tab.OnMouseDown)
    tab:SetScript("OnMouseUp", tab.OnMouseUp)
    tab:SetScript("OnEnter", tab.OnEnter)
    tab:SetScript("OnLeave", tab.OnLeave)

    -- Position below AurasTab
    tab:SetPoint("TOP", cdmFrame.AurasTab, "BOTTOM", 0, -3)

    return tab
end

--------------------------------------------------------------------------------
-- Main injection (taint-safe: no method overrides, no property writes,
-- no Blizzard array mutation, no method calls on system frames)
--------------------------------------------------------------------------------

local function ActivateScootTab(cdmFrame, contentFrameRef, blizzElements, tab)
    if isScootTabActive then return end
    isScootTabActive = true

    -- Uncheck all Blizzard tabs (C-side widget ops — safe)
    for _, btn in ipairs(cdmFrame.TabButtons) do
        btn:SetChecked(false)
    end
    tab:SetChecked(true)

    -- Hide Blizzard content elements (C-side widget ops — safe)
    for _, el in ipairs(blizzElements) do
        if el then el:Hide() end
    end

    -- Show our content
    contentFrameRef:Show()

    -- Set portrait (C-side texture op — safe, avoids calling frame method)
    cdmFrame.PortraitContainer.portrait:SetTexture(SCOOT_ICON)
end

local function InjectScootTab()
    if injected then return end

    local cdmFrame = CooldownViewerSettings
    if not cdmFrame then return end
    if not cdmFrame.TabButtons then return end
    if not cdmFrame.AurasTab then return end

    injected = true

    -- Elements to hide/show when toggling our tab
    local blizzElements = {
        cdmFrame.CooldownScroll,
        cdmFrame.SearchBox,
        cdmFrame.SettingsDropdown,
        cdmFrame.UndoButton,
    }

    -- Create content frame
    local content = CreateContentFrame(cdmFrame)

    -- Create tab button
    local tab = CreateTabButton(cdmFrame)

    -- Tab click: activate our tab (NO call to cdmFrame:SetDisplayMode — avoids taint)
    tab:SetCustomOnMouseUpHandler(function(t, button, upInside)
        if button == "LeftButton" and upInside then
            ActivateScootTab(cdmFrame, content, blizzElements, tab)
        end
    end)

    -- DO NOT insert tab into cdmFrame.TabButtons (would mutate Blizzard array)
    -- Tab is already anchored below AurasTab in CreateTabButton

    -- Hook SetDisplayMode for deactivation (replaces method override — taint-safe)
    hooksecurefunc(cdmFrame, "SetDisplayMode", function(self, displayMode)
        if isScootTabActive then
            isScootTabActive = false
            content:Hide()
            tab:SetChecked(false)
            -- Blizzard's SetDisplayMode already ran and restored its content.
            -- Re-show the elements we hid as a safety measure:
            for _, el in ipairs(blizzElements) do
                if el then el:Show() end
            end
        end
    end)

    -- Hook RefreshLayout for portrait (taint-safe)
    hooksecurefunc(cdmFrame, "RefreshLayout", function(self)
        if isScootTabActive then
            cdmFrame.PortraitContainer.portrait:SetTexture(SCOOT_ICON)
        end
    end)

    -- Cleanup on CDM window close
    cdmFrame:HookScript("OnHide", function()
        if isScootTabActive then
            isScootTabActive = false
            content:Hide()
            tab:SetChecked(false)
            for _, el in ipairs(blizzElements) do
                if el then el:Show() end
            end
        end
    end)
end

--------------------------------------------------------------------------------
-- Trigger injection from multiple entry points (all converge on idempotent fn)
--------------------------------------------------------------------------------

-- 1. When Blizzard_CooldownViewer loads, and also hook OpenCooldownManagerSettings
--    once it exists (Scoot.lua loads after this file in the TOC)
local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, event, loadedAddon)
    if loadedAddon == "Blizzard_CooldownViewer" then
        C_Timer.After(0, InjectScootTab)
    end
    if loadedAddon == addonName and addon.OpenCooldownManagerSettings then
        self:UnregisterEvent("ADDON_LOADED")
        hooksecurefunc(addon, "OpenCooldownManagerSettings", function()
            C_Timer.After(0, InjectScootTab)
        end)
    end
end)

-- 3. Immediate check (e.g., after /reload when addon is already loaded)
if CooldownViewerSettings then
    C_Timer.After(0, InjectScootTab)
end
