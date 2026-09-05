-- centering.lua - Cooldown Manager: icon centering for CDM viewers
-- Repositions visible icons symmetrically after Blizzard layout. Called from
-- the viewer Layout hook after each layout pass.
local addonName, addon = ...

local Overlays = addon.CDMOverlays
local CDM_VIEWERS = addon.CDM_VIEWERS

-- Center icons within a CDM viewer by repositioning them after Blizzard's layout
-- Two independent features controlled by separate settings:
--   centerAnchor: Row 1 centered symmetrically on anchor point
--   centerAdditionalRows: Rows 2+ centered under row 1 (vs left-aligned)
local function CenterIconsInViewer(viewerFrame, componentId)
    if not viewerFrame then return end
    if viewerFrame.IsForbidden and viewerFrame:IsForbidden() then return end

    local component = addon.Components and addon.Components[componentId]
    if not component or not component.db then return end

    local db = component.db
    local centerOnAnchor = db.centerAnchor
    local centerAdditionalRows = db.centerAdditionalRows

    -- Early exit if neither feature is enabled
    if not centerOnAnchor and not centerAdditionalRows then return end

    -- Collect visible icon children
    local icons = {}
    local children = { viewerFrame:GetChildren() }
    for _, child in ipairs(children) do
        if child and child:IsShown() and child.Icon then
            icons[#icons + 1] = child
        end
    end

    if #icons == 0 then return end

    -- Sort by layoutIndex for consistent ordering
    table.sort(icons, function(a, b)
        return (a.layoutIndex or 0) < (b.layoutIndex or 0)
    end)

    -- Get layout parameters
    local iconLimit = viewerFrame.iconLimit or 12
    local isHorizontal = viewerFrame.isHorizontal ~= false
    -- Enum.CooldownViewerIconDirection: Left=0, Right=1
    -- Convert to multiplier: Right/Up = +1 (normal), Left/Down = -1 (reversed)
    local iconDirectionRaw = viewerFrame.iconDirection
    local iconDirection = (iconDirectionRaw == 0) and -1 or 1

    -- Get icon dimensions and padding from first icon
    local iconWidth = 0
    local iconHeight = 0
    local padding = 0

    pcall(function()
        iconWidth = icons[1]:GetWidth() or 40
        iconHeight = icons[1]:GetHeight() or 40
        -- Estimate padding from Edit Mode settings or use default
        padding = viewerFrame.iconPadding or 2
    end)

    if iconWidth == 0 then iconWidth = 40 end
    if iconHeight == 0 then iconHeight = 40 end

    -- Group icons into rows/columns based on iconLimit
    local rows = {}
    for i = 1, #icons do
        local rowIndex = math.floor((i - 1) / iconLimit) + 1
        rows[rowIndex] = rows[rowIndex] or {}
        rows[rowIndex][#rows[rowIndex] + 1] = icons[i]
    end

    -- Determine growth direction for rows
    local growFromDirection = viewerFrame.growFromDirection or "TOP"
    local rowOffsetModifier = (growFromDirection == "BOTTOM" or growFromDirection == "RIGHT") and 1 or -1

    -- Calculate row 1's geometry (needed for alignment reference)
    local row1Count = #rows[1]

    if isHorizontal then
        local row1Width = (row1Count * iconWidth) + ((row1Count - 1) * padding)
        local row1LeftEdge, row1Center

        if centerOnAnchor then
            -- Row 1 centered on anchor: left edge is at -width/2
            row1LeftEdge = -row1Width / 2
            row1Center = 0  -- anchor point
        else
            -- Row 1 starts at anchor (Blizzard default): left edge at 0
            row1LeftEdge = 0
            row1Center = row1Width / 2
        end

        -- Position each row
        for rowNum, rowIcons in ipairs(rows) do
            local count = #rowIcons
            local rowWidth = (count * iconWidth) + ((count - 1) * padding)
            local startX
            local yOffset = (rowNum - 1) * (iconHeight + padding) * rowOffsetModifier

            if rowNum == 1 then
                -- Row 1: position based on centerOnAnchor
                if centerOnAnchor then
                    startX = (-rowWidth / 2) + (iconWidth / 2)
                else
                    startX = iconWidth / 2  -- Start from left edge (anchor)
                end
            else
                -- Rows 2+: position based on centerAdditionalRows
                if centerAdditionalRows then
                    -- Center this row on the same center as row 1
                    startX = row1Center - (rowWidth / 2) + (iconWidth / 2)
                else
                    -- Left-align to row 1's left edge
                    startX = row1LeftEdge + (iconWidth / 2)
                end
            end

            for i, icon in ipairs(rowIcons) do
                local xPos = (startX + (i - 1) * (iconWidth + padding)) * iconDirection
                pcall(function()
                    icon:ClearAllPoints()
                    icon:SetPoint("CENTER", viewerFrame, "TOPLEFT", xPos, -iconHeight / 2 + yOffset)
                end)
            end
        end
    else
        -- Vertical layout: similar logic but for Y axis
        local row1Height = (row1Count * iconHeight) + ((row1Count - 1) * padding)
        local row1TopEdge, row1Center

        if centerOnAnchor then
            -- Row 1 centered on anchor: top edge is at +height/2
            row1TopEdge = row1Height / 2
            row1Center = 0  -- anchor point
        else
            -- Row 1 starts at anchor (Blizzard default): top edge at 0
            row1TopEdge = 0
            row1Center = -row1Height / 2
        end

        -- Position each row (column in vertical layout)
        for rowNum, rowIcons in ipairs(rows) do
            local count = #rowIcons
            local rowHeight = (count * iconHeight) + ((count - 1) * padding)
            local startY
            local xOffset = (rowNum - 1) * (iconWidth + padding) * rowOffsetModifier

            if rowNum == 1 then
                -- Row 1: position based on centerOnAnchor
                if centerOnAnchor then
                    startY = (rowHeight / 2) - (iconHeight / 2)
                else
                    startY = -iconHeight / 2  -- Start from top edge (anchor)
                end
            else
                -- Rows 2+: position based on centerAdditionalRows
                if centerAdditionalRows then
                    -- Center this row on the same center as row 1
                    startY = row1Center + (rowHeight / 2) - (iconHeight / 2)
                else
                    -- Top-align to row 1's top edge
                    startY = row1TopEdge - (iconHeight / 2)
                end
            end

            for i, icon in ipairs(rowIcons) do
                local yPos = (startY - (i - 1) * (iconHeight + padding)) * iconDirection
                pcall(function()
                    icon:ClearAllPoints()
                    icon:SetPoint("CENTER", viewerFrame, "TOPLEFT", iconWidth / 2 + xOffset, yPos)
                end)
            end
        end
    end
end
Overlays._CenterIconsInViewer = CenterIconsInViewer

-- Exposed function to refresh center anchor (called when setting changes)
function addon.RefreshCDMCenterAnchor(componentId)
    if not componentId then return end

    local viewerName
    for vn, cid in pairs(CDM_VIEWERS) do
        if cid == componentId then
            viewerName = vn
            break
        end
    end

    if not viewerName then return end

    local viewerFrame = _G[viewerName]
    if viewerFrame then
        C_Timer.After(0, function()
            local component = addon.Components and addon.Components[componentId]
            local db = component and component.db
            if db and not db.centerAnchor and not db.centerAdditionalRows then
                -- Centering disabled: re-run Layout to restore default positions
                -- (the Layout hook early-exits since centering is off)
                pcall(function() viewerFrame:Layout() end)
            else
                CenterIconsInViewer(viewerFrame, componentId)
            end
        end)
    end
end
