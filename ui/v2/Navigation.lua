-- Navigation.lua - Terminal-style navigation sidebar with custom scrollbar
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.Navigation = {}
local Navigation = addon.UI.Navigation
local Theme = addon.UI.Theme
local Controls = addon.UI.Controls

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

local NAV_WIDTH = 220  -- Width of the navigation sidebar
local ROW_HEIGHT = 24  -- Height of each navigation row
local PARENT_ROW_HEIGHT = 28  -- Slightly taller for section headers
local CHILD_INDENT = 20  -- Indentation for child items
local PADDING_LEFT = 8
local PADDING_TOP = 8
local PADDING_RIGHT = 8

-- Scrollbar dimensions
local SCROLLBAR_WIDTH = 8
local SCROLLBAR_THUMB_MIN_HEIGHT = 30
local SCROLLBAR_TRACK_PADDING = 2
local SCROLLBAR_RIGHT_MARGIN = 8  -- Gap between scrollbar and right edge/separator

-- Tree line dimensions (texture-based, not text)
local TREE_LINE_WIDTH = 1
local TREE_LINE_HORIZONTAL_LENGTH = 10
local TREE_LINE_COLOR_ALPHA = 0.4

--------------------------------------------------------------------------------
-- Navigation Model (matching existing navModel structure)
--------------------------------------------------------------------------------

Navigation.NavModel = {
    {
        key = "profiles",
        label = "Profiles",
        collapsible = true,
        children = {
            { key = "profilesManage", label = "Manage Profiles" },
            { key = "profilesPresets", label = "Presets" },
            { key = "profilesRules", label = "Rules" },
            { key = "profilesImportExport", label = "Import/Export" },
        },
    },
    {
        key = "applyAll",
        label = "Apply All",
        collapsible = true,
        children = {
            { key = "applyAllFonts", label = "Fonts" },
            { key = "applyAllTextures", label = "Bar Textures" },
        },
    },
    {
        key = "interface",
        label = "Interface",
        collapsible = true,
        children = {
            { key = "damageMeter", label = "Damage Meters" },
            { key = "tooltip", label = "Tooltip" },
            { key = "objectiveTracker", label = "Objective Tracker" },
            { key = "minimap", label = "Minimap" },
            { key = "chat", label = "Chat" },
            { key = "misc", label = "Misc." },
        },
    },
    {
        key = "qol",
        label = "Quality of Life",
        collapsible = true,
        children = {
            { key = "qolLootVendors", label = "Loot & Vendors" },
        },
    },
    {
        key = "cdm",
        label = "Cooldown Manager",
        collapsible = true,
        children = {
            { key = "cdmQoL", label = "Quality of Life" },
            { key = "essentialCooldowns", label = "Essential Cooldowns" },
            { key = "utilityCooldowns", label = "Utility Cooldowns" },
            { key = "trackedBuffs", label = "Tracked Buffs" },
            { key = "trackedBars", label = "Tracked Bars" },
            { key = "customGroup1", label = "Custom Group 1" },
            { key = "customGroup2", label = "Custom Group 2" },
            { key = "customGroup3", label = "Custom Group 3" },
        },
    },
    {
        key = "classAuras",
        label = "Class Auras",
        collapsible = true,
        children = {
            { key = "classAurasDeathKnight", label = "Death Knight" },
            { key = "classAurasDemonHunter", label = "Demon Hunter" },
            { key = "classAurasDruid",       label = "Druid" },
            { key = "classAurasEvoker",      label = "Evoker" },
            { key = "classAurasHunter",      label = "Hunter" },
            { key = "classAurasMage",        label = "Mage" },
            { key = "classAurasMonk",        label = "Monk" },
            { key = "classAurasPaladin",     label = "Paladin" },
            { key = "classAurasPriest",      label = "Priest" },
            { key = "classAurasRogue",       label = "Rogue" },
            { key = "classAurasShaman",      label = "Shaman" },
            { key = "classAurasWarlock",     label = "Warlock" },
            { key = "classAurasWarrior",     label = "Warrior" },
        },
    },
    {
        key = "actionBars",
        label = "Action Bars",
        collapsible = true,
        children = {
            { key = "actionBar1", label = "Action Bar 1" },
            { key = "actionBar2", label = "Action Bar 2" },
            { key = "actionBar3", label = "Action Bar 3" },
            { key = "actionBar4", label = "Action Bar 4" },
            { key = "actionBar5", label = "Action Bar 5" },
            { key = "actionBar6", label = "Action Bar 6" },
            { key = "actionBar7", label = "Action Bar 7" },
            { key = "actionBar8", label = "Action Bar 8" },
            { key = "petBar", label = "Pet Bar" },
            { key = "stanceBar", label = "Stance Bar" },
            { key = "microBar", label = "Micro Bar" },
            { key = "extraAbilities", label = "Extra Abilities" },
        },
    },
    {
        key = "prd",
        label = "Personal Resource",
        collapsible = true,
        children = {
            { key = "prdGeneral", label = "General" },
            { key = "prdHealthBar", label = "Health Bar" },
            { key = "prdPowerBar", label = "Power Bar" },
            { key = "prdClassResource", label = "Class Resource" },
        },
    },
    {
        key = "unitFrames",
        label = "Unit Frames",
        collapsible = true,
        children = {
            { key = "ufPlayer", label = "Player" },
            { key = "ufTarget", label = "Target" },
            { key = "ufFocus", label = "Focus" },
            { key = "ufPet", label = "Pet" },
            { key = "ufToT", label = "Target of Target" },
            { key = "ufFocusTarget", label = "Target of Focus" },
            { key = "ufBoss", label = "Boss" },
        },
    },
    {
        key = "groupFrames",
        label = "Group Frames",
        collapsible = true,
        children = {
            { key = "gfParty", label = "Party Frames" },
            { key = "gfRaid", label = "Raid Frames" },
        },
    },
    {
        key = "buffsDebuffs",
        label = "Buffs/Debuffs",
        collapsible = true,
        children = {
            { key = "buffs", label = "Buffs" },
            { key = "debuffs", label = "Debuffs" },
        },
    },
    {
        key = "sct",
        label = "Scrolling Combat Text",
        collapsible = true,
        children = {
            { key = "sctDamage", label = "Damage Numbers" },
        },
    },
    {
        key = "debug",
        label = "Debug",
        collapsible = true,
        hidden = true,  -- Hidden by default, shown via /scoot debugmenu
        children = {
            { key = "debugMenu", label = "Debug Menu" },
        },
    },
}

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

Navigation._expandedSections = {}  -- Track which parent sections are expanded
Navigation._selectedKey = nil      -- Currently selected navigation item (nil = Home via logo)
Navigation._rows = {}              -- References to created row frames

--------------------------------------------------------------------------------
-- Custom Scrollbar
--------------------------------------------------------------------------------

local function CreateScrollbar(parent, scrollFrame)
    local ar, ag, ab = Theme:GetAccentColor()

    -- Scrollbar container (with margin from right edge)
    local scrollbar = CreateFrame("Frame", nil, parent)
    scrollbar:SetWidth(SCROLLBAR_WIDTH)
    scrollbar:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -SCROLLBAR_RIGHT_MARGIN, -PADDING_TOP)
    scrollbar:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -SCROLLBAR_RIGHT_MARGIN, PADDING_TOP)

    -- Track background (subtle)
    local track = scrollbar:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints()
    track:SetColorTexture(ar, ag, ab, 0.1)
    scrollbar._track = track

    -- Thumb (draggable part)
    local thumb = CreateFrame("Button", nil, scrollbar)
    thumb:SetWidth(SCROLLBAR_WIDTH)
    thumb:SetHeight(SCROLLBAR_THUMB_MIN_HEIGHT)
    thumb:SetPoint("TOP", scrollbar, "TOP", 0, 0)
    thumb:EnableMouse(true)
    thumb:RegisterForDrag("LeftButton")

    local thumbTex = thumb:CreateTexture(nil, "ARTWORK")
    thumbTex:SetAllPoints()
    thumbTex:SetColorTexture(ar, ag, ab, 0.5)
    thumb._tex = thumbTex

    -- Hover effect for thumb
    thumb:SetScript("OnEnter", function(self)
        local r, g, b = Theme:GetAccentColor()
        self._tex:SetColorTexture(r, g, b, 0.8)
    end)

    thumb:SetScript("OnLeave", function(self)
        if not self._isDragging then
            local r, g, b = Theme:GetAccentColor()
            self._tex:SetColorTexture(r, g, b, 0.5)
        end
    end)

    scrollbar._thumb = thumb
    scrollbar._scrollFrame = scrollFrame

    -- Calculate and update thumb size/position based on content
    local function UpdateScrollbar()
        if not scrollFrame then return end

        local contentHeight = 0
        local scrollChild = scrollFrame:GetScrollChild()
        if scrollChild then
            contentHeight = scrollChild:GetHeight() or 0
        end

        local visibleHeight = scrollFrame:GetHeight() or 1
        local trackHeight = scrollbar:GetHeight() or 1

        -- Hide scrollbar if content fits
        if contentHeight <= visibleHeight then
            scrollbar:Hide()
            return
        end

        scrollbar:Show()

        -- Calculate thumb height proportionally
        local thumbHeight = math.max(
            SCROLLBAR_THUMB_MIN_HEIGHT,
            (visibleHeight / contentHeight) * trackHeight
        )
        thumb:SetHeight(thumbHeight)

        -- Calculate thumb position based on scroll offset
        local maxScroll = contentHeight - visibleHeight
        local currentScroll = scrollFrame:GetVerticalScroll() or 0
        local scrollPercent = maxScroll > 0 and (currentScroll / maxScroll) or 0

        local maxThumbOffset = trackHeight - thumbHeight
        local thumbOffset = scrollPercent * maxThumbOffset

        thumb:ClearAllPoints()
        thumb:SetPoint("TOP", scrollbar, "TOP", 0, -thumbOffset)
    end

    scrollbar.Update = UpdateScrollbar

    -- Dragging the thumb
    local dragStartY, dragStartScroll

    thumb:SetScript("OnDragStart", function(self)
        self._isDragging = true
        local r, g, b = Theme:GetAccentColor()
        self._tex:SetColorTexture(r, g, b, 1)

        local _, cursorY = GetCursorPosition()
        local scale = self:GetEffectiveScale()
        dragStartY = cursorY / scale
        dragStartScroll = scrollFrame:GetVerticalScroll() or 0
    end)

    thumb:SetScript("OnDragStop", function(self)
        self._isDragging = false
        if not self:IsMouseOver() then
            local r, g, b = Theme:GetAccentColor()
            self._tex:SetColorTexture(r, g, b, 0.5)
        else
            local r, g, b = Theme:GetAccentColor()
            self._tex:SetColorTexture(r, g, b, 0.8)
        end
    end)

    thumb:SetScript("OnUpdate", function(self)
        if not self._isDragging then return end

        local _, cursorY = GetCursorPosition()
        local scale = self:GetEffectiveScale()
        cursorY = cursorY / scale

        local deltaY = dragStartY - cursorY  -- Inverted because Y increases downward in scroll

        local contentHeight = 0
        local scrollChild = scrollFrame:GetScrollChild()
        if scrollChild then
            contentHeight = scrollChild:GetHeight() or 0
        end

        local visibleHeight = scrollFrame:GetHeight() or 1
        local trackHeight = scrollbar:GetHeight() or 1
        local thumbHeight = thumb:GetHeight()

        local maxScroll = contentHeight - visibleHeight
        local maxThumbOffset = trackHeight - thumbHeight

        if maxThumbOffset > 0 and maxScroll > 0 then
            local scrollDelta = (deltaY / maxThumbOffset) * maxScroll
            local newScroll = math.max(0, math.min(maxScroll, dragStartScroll + scrollDelta))
            scrollFrame:SetVerticalScroll(newScroll)
        end
    end)

    -- Click on track to jump
    scrollbar:EnableMouse(true)
    scrollbar:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" then return end

        local _, cursorY = GetCursorPosition()
        local scale = self:GetEffectiveScale()
        cursorY = cursorY / scale

        local selfBottom = self:GetBottom() or 0
        local clickY = cursorY - selfBottom
        local trackHeight = self:GetHeight() or 1

        local clickPercent = 1 - (clickY / trackHeight)  -- Inverted

        local contentHeight = 0
        local scrollChild = scrollFrame:GetScrollChild()
        if scrollChild then
            contentHeight = scrollChild:GetHeight() or 0
        end

        local visibleHeight = scrollFrame:GetHeight() or 1
        local maxScroll = contentHeight - visibleHeight

        if maxScroll > 0 then
            local newScroll = clickPercent * maxScroll
            scrollFrame:SetVerticalScroll(math.max(0, math.min(maxScroll, newScroll)))
        end
    end)

    -- Subscribe to theme updates
    Theme:Subscribe("Scrollbar_" .. tostring(scrollbar), function(r, g, b)
        if scrollbar._track then
            scrollbar._track:SetColorTexture(r, g, b, 0.1)
        end
        if thumb._tex and not thumb._isDragging then
            thumb._tex:SetColorTexture(r, g, b, 0.5)
        end
    end)

    return scrollbar
end

--------------------------------------------------------------------------------
-- Navigation Frame Creation
--------------------------------------------------------------------------------

function Navigation:Create(parent)
    if not parent then return nil end

    -- Create main navigation frame (no background - inherits from parent)
    local navFrame = CreateFrame("Frame", "ScootNavFrame", parent)
    navFrame:SetWidth(NAV_WIDTH)
    navFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", Theme.BORDER_WIDTH, -(80 + Theme.BORDER_WIDTH))
    navFrame:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", Theme.BORDER_WIDTH, Theme.BORDER_WIDTH)

    -- Right border separator
    local separator = navFrame:CreateTexture(nil, "BORDER")
    separator:SetWidth(1)
    separator:SetPoint("TOPRIGHT", navFrame, "TOPRIGHT", 0, 0)
    separator:SetPoint("BOTTOMRIGHT", navFrame, "BOTTOMRIGHT", 0, 0)
    local ar, ag, ab = Theme:GetAccentColor()
    separator:SetColorTexture(ar, ag, ab, 0.4)
    navFrame._separator = separator

    -- Custom scroll frame (no template - built from scratch)
    local scrollFrame = CreateFrame("ScrollFrame", "ScootNavScrollFrame", navFrame)
    scrollFrame:SetPoint("TOPLEFT", navFrame, "TOPLEFT", PADDING_LEFT, -PADDING_TOP)
    scrollFrame:SetPoint("BOTTOMRIGHT", navFrame, "BOTTOMRIGHT", -(SCROLLBAR_RIGHT_MARGIN + SCROLLBAR_WIDTH + 4), PADDING_TOP)
    scrollFrame:EnableMouseWheel(true)

    -- Mouse wheel scrolling
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local current = self:GetVerticalScroll() or 0
        local scrollChild = self:GetScrollChild()
        local contentHeight = scrollChild and scrollChild:GetHeight() or 0
        local visibleHeight = self:GetHeight() or 1
        local maxScroll = math.max(0, contentHeight - visibleHeight)

        local step = ROW_HEIGHT * 3  -- Scroll 3 rows at a time
        local newScroll = current - (delta * step)
        newScroll = math.max(0, math.min(maxScroll, newScroll))

        self:SetVerticalScroll(newScroll)

        -- Update custom scrollbar
        if navFrame._scrollbar and navFrame._scrollbar.Update then
            navFrame._scrollbar:Update()
        end
    end)

    -- Content frame that will hold all nav items
    local contentFrame = CreateFrame("Frame", "ScootNavContent", scrollFrame)
    contentFrame:SetWidth(scrollFrame:GetWidth() or (NAV_WIDTH - PADDING_LEFT - SCROLLBAR_RIGHT_MARGIN - SCROLLBAR_WIDTH - 4))
    scrollFrame:SetScrollChild(contentFrame)
    navFrame._content = contentFrame
    navFrame._scrollFrame = scrollFrame

    -- Create custom scrollbar
    local scrollbar = CreateScrollbar(navFrame, scrollFrame)
    navFrame._scrollbar = scrollbar

    -- Update scrollbar when scroll changes
    scrollFrame:SetScript("OnScrollRangeChanged", function()
        if scrollbar and scrollbar.Update then
            scrollbar:Update()
        end
    end)

    -- Initialize expanded state (start collapsed)
    self:InitializeExpandedState()

    -- Build navigation rows
    self:BuildRows(contentFrame)

    -- Initial scrollbar update
    C_Timer.After(0.1, function()
        if scrollbar and scrollbar.Update then
            scrollbar:Update()
        end
    end)

    -- Store reference
    self._frame = navFrame

    -- Subscribe to theme updates
    Theme:Subscribe("Navigation_Frame", function(r, g, b)
        if navFrame._separator then
            navFrame._separator:SetColorTexture(r, g, b, 0.4)
        end
        self:UpdateRowColors()
    end)

    return navFrame
end

--------------------------------------------------------------------------------
-- Initialize Expanded State
--------------------------------------------------------------------------------

function Navigation:InitializeExpandedState()
    for _, parent in ipairs(self.NavModel) do
        if parent.collapsible then
            self._expandedSections[parent.key] = false
        end
    end
end

--------------------------------------------------------------------------------
-- Build Navigation Rows
--------------------------------------------------------------------------------

function Navigation:BuildRows(contentFrame)
    if not contentFrame then return end

    -- Clear existing rows
    for _, row in ipairs(self._rows) do
        if row and row.Hide then
            row:Hide()
            row:SetParent(nil)
        end
    end
    self._rows = {}

    local yOffset = 0
    local rowIndex = 0

    for parentIdx, parent in ipairs(self.NavModel) do
        -- Skip hidden sections (e.g., Debug) unless explicitly enabled in profile
        local debugEnabled = addon.db and addon.db.profile and addon.db.profile.debugMenuEnabled
        if parent.hidden and not debugEnabled then
            -- Skip this parent and its children entirely
        else
        rowIndex = rowIndex + 1

        -- Create parent row
        local parentRow = self:CreateParentRow(contentFrame, parent, yOffset)
        self._rows[rowIndex] = parentRow
        yOffset = yOffset - PARENT_ROW_HEIGHT

        -- Create child rows if parent is collapsible and expanded
        if parent.collapsible and parent.children then
            local isExpanded = self._expandedSections[parent.key]

            for childIdx, child in ipairs(parent.children) do
                rowIndex = rowIndex + 1
                local isLastChild = (childIdx == #parent.children)
                local childRow = self:CreateChildRow(
                    contentFrame,
                    child,
                    yOffset,
                    isLastChild,
                    isExpanded,
                    #parent.children,
                    childIdx
                )
                self._rows[rowIndex] = childRow

                if isExpanded then
                    yOffset = yOffset - ROW_HEIGHT
                end
            end
        end
        end  -- end else (skip hidden sections)
    end

    -- Set content frame height
    local totalHeight = math.abs(yOffset) + PADDING_TOP
    contentFrame:SetHeight(math.max(totalHeight, 100))

    -- Update scrollbar
    if self._frame and self._frame._scrollbar and self._frame._scrollbar.Update then
        self._frame._scrollbar:Update()
    end
end

--------------------------------------------------------------------------------
-- Create Parent Row (Section header - no tree lines)
--------------------------------------------------------------------------------

function Navigation:CreateParentRow(parent, navItem, yOffset)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(PARENT_ROW_HEIGHT)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, yOffset)
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, yOffset)
    row:EnableMouse(true)
    row:RegisterForClicks("AnyUp")

    -- Store metadata
    row._key = navItem.key
    row._isParent = true
    row._isCollapsible = navItem.collapsible
    row._navItem = navItem

    local ar, ag, ab = Theme:GetAccentColor()

    -- Hover background
    local hoverBg = row:CreateTexture(nil, "BACKGROUND")
    hoverBg:SetAllPoints()
    hoverBg:SetColorTexture(ar, ag, ab, 0.15)
    hoverBg:Hide()
    row._hoverBg = hoverBg

    -- Selection background
    local selectBg = row:CreateTexture(nil, "BACKGROUND", nil, -1)
    selectBg:SetAllPoints()
    selectBg:SetColorTexture(ar, ag, ab, 0.25)
    selectBg:Hide()
    row._selectBg = selectBg

    -- Expand/collapse indicator (▶/▼) - only for collapsible
    local indicator = row:CreateFontString(nil, "OVERLAY")
    local fontPath = Theme:GetFont("BUTTON")
    indicator:SetFont(fontPath, 10, "")
    indicator:SetPoint("LEFT", row, "LEFT", 4, 0)

    if navItem.collapsible then
        local isExpanded = self._expandedSections[navItem.key]
        indicator:SetText(isExpanded and "▼" or "▶")
        indicator:SetTextColor(ar, ag, ab, 0.7)
    else
        indicator:SetText("")
    end
    row._indicator = indicator

    -- Label text
    local label = row:CreateFontString(nil, "OVERLAY")
    Theme:ApplyLabelFont(label, 12)
    if navItem.collapsible then
        label:SetPoint("LEFT", indicator, "RIGHT", 6, 0)
    else
        label:SetPoint("LEFT", row, "LEFT", 8, 0)
    end
    label:SetText(navItem.label)
    row._label = label

    -- Hover effect
    row:SetScript("OnEnter", function(self)
        local r, g, b = Theme:GetAccentColor()
        self._hoverBg:SetColorTexture(r, g, b, 0.15)
        self._hoverBg:Show()
        self._label:SetTextColor(1, 1, 1, 1)
    end)

    row:SetScript("OnLeave", function(self)
        self._hoverBg:Hide()
        local r, g, b = Theme:GetAccentColor()
        if Navigation._selectedKey == self._key then
            self._label:SetTextColor(1, 1, 1, 1)
        else
            self._label:SetTextColor(r, g, b, 1)
        end
    end)

    -- Click handler
    row:SetScript("OnClick", function(self, button)
        if self._isCollapsible then
            Navigation:ToggleSection(self._key)
        else
            Navigation:SelectItem(self._key)
        end
    end)

    self:UpdateRowSelectionState(row)
    return row
end

--------------------------------------------------------------------------------
-- Create Child Row (with texture-based tree lines)
--------------------------------------------------------------------------------

function Navigation:CreateChildRow(parent, navItem, yOffset, isLastChild, isVisible, totalChildren, childIndex)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, yOffset)
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, yOffset)
    row:EnableMouse(true)
    row:RegisterForClicks("AnyUp")

    -- Store metadata
    row._key = navItem.key
    row._isParent = false
    row._navItem = navItem
    row._isLastChild = isLastChild

    local ar, ag, ab = Theme:GetAccentColor()

    -- Hover background
    local hoverBg = row:CreateTexture(nil, "BACKGROUND")
    hoverBg:SetAllPoints()
    hoverBg:SetColorTexture(ar, ag, ab, 0.15)
    hoverBg:Hide()
    row._hoverBg = hoverBg

    -- Selection background
    local selectBg = row:CreateTexture(nil, "BACKGROUND", nil, -1)
    selectBg:SetAllPoints()
    selectBg:SetColorTexture(ar, ag, ab, 0.25)
    selectBg:Hide()
    row._selectBg = selectBg

    -- Tree lines using textures (not text characters)
    local treeLines = {}

    -- Vertical line (from parent down to this item)
    local vertLine = row:CreateTexture(nil, "ARTWORK")
    vertLine:SetWidth(TREE_LINE_WIDTH)
    vertLine:SetColorTexture(ar, ag, ab, TREE_LINE_COLOR_ALPHA)
    vertLine:SetPoint("TOPLEFT", row, "TOPLEFT", 10, 0)

    if isLastChild then
        -- For last child, vertical line goes from top to center (where horizontal line is)
        vertLine:SetPoint("BOTTOM", row, "LEFT", 10, 0)
    else
        -- For other children, vertical line goes full height
        vertLine:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 10, 0)
    end
    treeLines.vertical = vertLine

    -- Horizontal line (branch to label)
    local horizLine = row:CreateTexture(nil, "ARTWORK")
    horizLine:SetHeight(TREE_LINE_WIDTH)
    horizLine:SetColorTexture(ar, ag, ab, TREE_LINE_COLOR_ALPHA)
    horizLine:SetPoint("LEFT", row, "LEFT", 10 + TREE_LINE_WIDTH, 0)
    horizLine:SetWidth(TREE_LINE_HORIZONTAL_LENGTH - TREE_LINE_WIDTH)
    treeLines.horizontal = horizLine

    row._treeLines = treeLines

    -- Label text
    local label = row:CreateFontString(nil, "OVERLAY")
    Theme:ApplyValueFont(label, 11)
    label:SetPoint("LEFT", row, "LEFT", CHILD_INDENT + 6, 0)
    label:SetText(navItem.label)
    row._label = label

    -- Hover effect
    row:SetScript("OnEnter", function(self)
        local r, g, b = Theme:GetAccentColor()
        self._hoverBg:SetColorTexture(r, g, b, 0.15)
        self._hoverBg:Show()
        self._label:SetTextColor(r, g, b, 1)
    end)

    row:SetScript("OnLeave", function(self)
        self._hoverBg:Hide()
        if Navigation._selectedKey == self._key then
            local r, g, b = Theme:GetAccentColor()
            self._label:SetTextColor(r, g, b, 1)
        else
            self._label:SetTextColor(1, 1, 1, 1)
        end
    end)

    -- Click handler
    row:SetScript("OnClick", function(self, button)
        Navigation:SelectItem(self._key)
    end)

    -- Set visibility
    if isVisible then
        row:Show()
    else
        row:Hide()
    end

    self:UpdateRowSelectionState(row)
    return row
end

--------------------------------------------------------------------------------
-- Toggle Section Expand/Collapse
--------------------------------------------------------------------------------

function Navigation:ToggleSection(parentKey)
    if not parentKey then return end

    self._expandedSections[parentKey] = not self._expandedSections[parentKey]

    if self._frame and self._frame._content then
        self:BuildRows(self._frame._content)
    end
end

--------------------------------------------------------------------------------
-- Select Navigation Item
--------------------------------------------------------------------------------

function Navigation:SelectItem(key)
    if not key then return end

    local previousKey = self._selectedKey
    self._selectedKey = key

    for _, row in ipairs(self._rows) do
        if row and row._key then
            self:UpdateRowSelectionState(row)
        end
    end

    if self._onSelectCallback then
        self._onSelectCallback(key, previousKey)
    end
end

--------------------------------------------------------------------------------
-- Update Row Selection State
--------------------------------------------------------------------------------

function Navigation:UpdateRowSelectionState(row)
    if not row or not row._key then return end

    local isSelected = (self._selectedKey == row._key)
    local ar, ag, ab = Theme:GetAccentColor()

    if isSelected then
        row._selectBg:SetColorTexture(ar, ag, ab, 0.25)
        row._selectBg:Show()
        if row._isParent then
            row._label:SetTextColor(1, 1, 1, 1)
        else
            row._label:SetTextColor(ar, ag, ab, 1)
        end
    else
        row._selectBg:Hide()
        if row._isParent then
            row._label:SetTextColor(ar, ag, ab, 1)
        else
            row._label:SetTextColor(1, 1, 1, 1)
        end
    end
end

--------------------------------------------------------------------------------
-- Update All Row Colors (theme change)
--------------------------------------------------------------------------------

function Navigation:UpdateRowColors()
    local ar, ag, ab = Theme:GetAccentColor()

    for _, row in ipairs(self._rows) do
        if row then
            if row._indicator then
                row._indicator:SetTextColor(ar, ag, ab, 0.7)
            end

            if row._hoverBg then
                row._hoverBg:SetColorTexture(ar, ag, ab, 0.15)
            end
            if row._selectBg then
                row._selectBg:SetColorTexture(ar, ag, ab, 0.25)
            end

            -- Update tree line colors for child rows
            if row._treeLines then
                for _, line in pairs(row._treeLines) do
                    line:SetColorTexture(ar, ag, ab, TREE_LINE_COLOR_ALPHA)
                end
            end

            self:UpdateRowSelectionState(row)
        end
    end
end

--------------------------------------------------------------------------------
-- Expand All / Collapse All
--------------------------------------------------------------------------------

function Navigation:ExpandAll()
    for _, parent in ipairs(self.NavModel) do
        if parent.collapsible then
            self._expandedSections[parent.key] = true
        end
    end

    if self._frame and self._frame._content then
        self:BuildRows(self._frame._content)
    end
end

function Navigation:CollapseAll()
    for _, parent in ipairs(self.NavModel) do
        if parent.collapsible then
            self._expandedSections[parent.key] = false
        end
    end

    if self._frame and self._frame._content then
        self:BuildRows(self._frame._content)
    end
end

--------------------------------------------------------------------------------
-- Set Selection Callback
--------------------------------------------------------------------------------

function Navigation:SetOnSelectCallback(callback)
    if type(callback) == "function" then
        self._onSelectCallback = callback
    end
end

--------------------------------------------------------------------------------
-- Get Current Selection
--------------------------------------------------------------------------------

function Navigation:GetSelectedKey()
    return self._selectedKey
end

--------------------------------------------------------------------------------
-- Get Navigation Frame
--------------------------------------------------------------------------------

function Navigation:GetFrame()
    return self._frame
end

--------------------------------------------------------------------------------
-- Rebuild Navigation (e.g., when debug menu visibility changes)
--------------------------------------------------------------------------------

function Navigation:Rebuild()
    if self._frame and self._frame._content then
        self:BuildRows(self._frame._content)
    end
end

--------------------------------------------------------------------------------
-- Cleanup
--------------------------------------------------------------------------------

function Navigation:Cleanup()
    Theme:Unsubscribe("Navigation_Frame")

    for _, row in ipairs(self._rows) do
        if row then
            row:Hide()
            row:SetParent(nil)
        end
    end

    self._rows = {}
    self._frame = nil
end
