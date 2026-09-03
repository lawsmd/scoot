-- customgroups/layout.lua - Layout engine, container opacity, LibEditMode integration
local addonName, addon = ...

local CG = addon.CustomGroups
local containers = addon.CustomGroupContainers

--------------------------------------------------------------------------------
-- Layout Engine
--------------------------------------------------------------------------------

local ANCHOR_MODE_MAP = {
    left   = "TOPLEFT",
    right  = "TOPRIGHT",
    center = "CENTER",
    top    = "TOP",
    bottom = "BOTTOM",
}

local function ReanchorContainer(container, anchorPosition)
    local targetPoint = ANCHOR_MODE_MAP[anchorPosition or "center"]
    if not targetPoint or not container then return end

    local parent = container:GetParent()
    if not parent then return end
    local scale = container:GetScale() or 1
    local left, top, right, bottom = container:GetLeft(), container:GetTop(), container:GetRight(), container:GetBottom()
    if not left or not top or not right or not bottom then return end

    left, top, right, bottom = left * scale, top * scale, right * scale, bottom * scale
    local pw, ph = parent:GetSize()

    local x = targetPoint:find("LEFT") and left
        or targetPoint:find("RIGHT") and (right - pw)
        or ((left + right) / 2 - pw / 2)
    local y = targetPoint:find("BOTTOM") and bottom
        or targetPoint:find("TOP") and (top - ph)
        or ((top + bottom) / 2 - ph / 2)

    container:ClearAllPoints()
    container:SetPoint(targetPoint, x / scale, y / scale)
end

function CG._LayoutIcons(groupIndex)
    local activeIcons = CG._activeIcons
    local icons = activeIcons[groupIndex]
    if #icons == 0 then return end

    local container = containers[groupIndex]
    if not container then return end

    local component = addon.Components and addon.Components["customGroup" .. groupIndex]
    if not component or not component.db then return end

    local db = component.db
    local orientation = db.orientation or "H"
    local direction = db.direction or "right"
    local stride = tonumber(db.columns) or 12
    local padding = tonumber(db.iconPadding) or 2
    local anchorPosition = db.anchorPosition or "center"

    if stride < 1 then stride = 1 end

    local iconW, iconH = CG._GetIconDimensions(db)

    -- Primary axis = direction icons grow along (H=horizontal, V=vertical)
    -- Secondary axis = direction rows stack along (perpendicular)
    -- primarySize/secondarySize = icon dimension along each axis
    local primarySize, secondarySize
    if orientation == "H" then
        primarySize = iconW
        secondarySize = iconH
    else
        primarySize = iconH
        secondarySize = iconW
    end

    -- Determine reference point and axis signs based on direction
    -- primarySign: +1 = icons grow in positive direction, -1 = negative
    -- secondarySign: +1 = rows stack in positive direction, -1 = negative
    local refPoint, primarySign, secondarySign
    if orientation == "H" then
        if direction == "left" then
            refPoint = "TOPRIGHT"
            primarySign = -1
            secondarySign = -1
        else -- "right"
            refPoint = "TOPLEFT"
            primarySign = 1
            secondarySign = -1
        end
    else -- "V"
        if direction == "up" then
            refPoint = "BOTTOMLEFT"
            primarySign = 1
            secondarySign = 1
        else -- "down"
            refPoint = "TOPLEFT"
            primarySign = -1
            secondarySign = 1
        end
    end

    -- Group icons into rows
    local count = #icons
    local numRows = math.ceil(count / stride)
    local row1Count = math.min(count, stride)

    -- Row 1 span (edge-to-edge, not center-to-center)
    local row1Span = (row1Count * primarySize) + ((row1Count - 1) * padding)

    -- Row 1 start position (leading edge of first icon, in primary axis units from refPoint)
    local row1Start = 0

    -- Row 1 center for aligning additional rows
    local row1Center = row1Start + row1Span / 2

    -- Position each icon using CENTER anchor
    for i, icon in ipairs(icons) do
        icon:SetSize(iconW, iconH)
        CG._ApplyTexCoord(icon, iconW, iconH, db.iconZoom)

        local pos = i - 1
        local major = pos % stride       -- index along primary axis
        local minor = math.floor(pos / stride) -- row index

        -- Determine row start for this icon's row
        local rowStart
        if minor == 0 then
            rowStart = row1Start
        else
            local rowCount = math.min(count - (minor * stride), stride)
            local rowSpan = (rowCount * primarySize) + ((rowCount - 1) * padding)
            if anchorPosition == "left" or anchorPosition == "right" then
                rowStart = row1Start
            else
                rowStart = row1Center - rowSpan / 2
            end
        end

        -- Icon center along primary axis (from refPoint)
        local primaryPos = rowStart + (major * (primarySize + padding)) + (primarySize / 2)
        -- Icon center along secondary axis (from refPoint)
        local secondaryPos = (minor * (secondarySize + padding)) + (secondarySize / 2)

        -- Map to (x, y) using axis signs
        local x, y
        if orientation == "H" then
            x = primaryPos * primarySign
            y = secondaryPos * secondarySign
        else
            x = secondaryPos * secondarySign
            y = primaryPos * primarySign
        end

        icon:ClearAllPoints()
        icon:SetPoint("CENTER", container, refPoint, x, y)
    end

    -- Calculate container size (unchanged — icons may extend past bounds when centered)
    local majorCount = math.min(count, stride)
    local minorCount = numRows

    local totalW, totalH
    if orientation == "H" then
        totalW = (majorCount * iconW) + ((majorCount - 1) * padding)
        totalH = (minorCount * iconH) + ((minorCount - 1) * padding)
    else
        totalW = (minorCount * iconW) + ((minorCount - 1) * padding)
        totalH = (majorCount * iconH) + ((majorCount - 1) * padding)
    end

    ReanchorContainer(container, anchorPosition)
    container:SetSize(math.max(1, totalW), math.max(1, totalH))
end

--------------------------------------------------------------------------------
-- Container-Level Opacity
--------------------------------------------------------------------------------

function CG._UpdateGroupOpacity(groupIndex)
    local container = containers[groupIndex]
    if not container then return end
    -- Zero-Touch: skip unconfigured components (still on proxy DB)
    local component = addon.Components and addon.Components["customGroup" .. groupIndex]
    if addon.IsComponentUnconfigured(component) then return end
    container:SetAlpha(CG._getGroupOpacityForState(groupIndex))
end

function CG._UpdateAllGroupOpacities()
    for i = 1, CG.NUM_GROUPS do
        CG._UpdateGroupOpacity(i)
    end
end

--------------------------------------------------------------------------------
-- LibEditMode Integration
--------------------------------------------------------------------------------

local function SaveGroupPosition(groupIndex, layoutName, point, x, y)
    local groups = CG._EnsureGroupsDB()
    if not groups or not groups[groupIndex] then return end

    if not groups[groupIndex].positions then
        groups[groupIndex].positions = {}
    end

    groups[groupIndex].positions[layoutName] = {
        point = point,
        x = x,
        y = y,
    }
end

local function RestoreGroupPosition(groupIndex, layoutName)
    local container = containers[groupIndex]
    if not container then return end

    local groups = CG._EnsureGroupsDB()
    if not groups or not groups[groupIndex] then return end

    local positions = groups[groupIndex].positions
    local pos = positions and positions[layoutName]

    if pos and pos.point then
        container:ClearAllPoints()
        container:SetPoint(pos.point, pos.x or 0, pos.y or 0)
    end
end

local function UpdateEditModeNames()
    for i = 1, CG.NUM_GROUPS do
        local container = containers[i]
        if container then
            container.editModeName = CG.GetGroupDisplayName(i)
        end
    end
end

function CG._InitializeEditMode()
    local lib = LibStub("LibEditMode", true)
    if not lib then return end

    for i = 1, CG.NUM_GROUPS do
        local container = containers[i]
        if container then
            container.editModeName = CG.GetGroupDisplayName(i)
            lib:AddFrame(container, function(frame, layoutName, point, x, y)
                if point and x and y then
                    frame:ClearAllPoints()
                    frame:SetPoint(point, x, y)
                end
                -- Re-anchor to match anchorPosition
                local component = addon.Components and addon.Components["customGroup" .. i]
                if component and component.db then
                    ReanchorContainer(frame, component.db.anchorPosition or "center")
                end
                -- Save the re-anchored position
                if layoutName then
                    local savedPoint, _, _, savedX, savedY = frame:GetPoint(1)
                    if savedPoint then
                        SaveGroupPosition(i, layoutName, savedPoint, savedX, savedY)
                    else
                        SaveGroupPosition(i, layoutName, point, x, y)
                    end
                end
            end, {
                point = "CENTER",
                x = 0,
                y = -100 + (i - 1) * -60,
            }, nil)

            local Brand = addon.EditMode and addon.EditMode.Brand
            if Brand then
                -- Each group is its own nav page, so the page is the item.
                Brand:Register(container, { navKey = "customGroup" .. i })
            end
        end
    end

    lib:RegisterCallback("layout", function(layoutName, layoutIndex)
        for i = 1, CG.NUM_GROUPS do
            RestoreGroupPosition(i, layoutName)
        end
    end)

    CG.RegisterCallback(UpdateEditModeNames)
end
