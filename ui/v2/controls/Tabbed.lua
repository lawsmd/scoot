-- Tabbed.lua - Horizontal tabs for organizing sub-settings
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.Controls = addon.UI.Controls or {}
local Controls = addon.UI.Controls
local Theme -- Will be set after Theme.lua loads

-- Lazy Theme accessor
local function GetTheme()
    if not Theme then
        Theme = addon.UI.Theme
    end
    return Theme
end

-- Constants

local TAB_HEIGHT = 26
local TAB_PADDING = 16  -- Horizontal padding per side of tab text
local TAB_SPACING = 2   -- Gap between tabs
local TAB_BAR_PADDING = 8  -- Padding on sides of tab bar
local TAB_ROW_SPACING = 2  -- Gap between tab rows when multi-row
local TABBED_BORDER_WIDTH = 1
local TABBED_BORDER_ALPHA = 0.6
local TABBED_CONTENT_PADDING = 8
local MAX_TABS_PER_ROW = 5

-- Session storage for selected tab state

addon.UI._tabStates = addon.UI._tabStates or {}

local function GetTabState(componentId, sectionKey, defaultTab)
    addon.UI._tabStates[componentId] = addon.UI._tabStates[componentId] or {}
    local state = addon.UI._tabStates[componentId][sectionKey]
    if state == nil then
        return defaultTab
    end
    return state
end

local function SetTabState(componentId, sectionKey, tabKey)
    addon.UI._tabStates[componentId] = addon.UI._tabStates[componentId] or {}
    addon.UI._tabStates[componentId][sectionKey] = tabKey
end

-- TabbedSection: Horizontal tabs for organizing sub-settings

function Controls:CreateTabbedSection(options)
    local theme = GetTheme()
    if not options or not options.parent or not options.tabs or #options.tabs == 0 then
        return nil
    end

    local parent = options.parent
    local tabs = options.tabs
    local componentId = options.componentId or "unknown"
    local sectionKey = options.sectionKey or "tabs"
    local defaultTab = options.defaultTab or tabs[1].key
    local onTabChange = options.onTabChange
    local onHeightChange = options.onHeightChange
    local name = options.name
    -- Per-section row capacity; every existing caller keeps the default
    local maxTabsPerRow = options.maxTabsPerRow or MAX_TABS_PER_ROW

    -- Get initial selected tab from session storage
    local selectedTabKey = GetTabState(componentId, sectionKey, defaultTab)

    -- Validate selected tab exists
    local tabExists = false
    for _, tab in ipairs(tabs) do
        if tab.key == selectedTabKey then
            tabExists = true
            break
        end
    end
    if not tabExists then
        selectedTabKey = tabs[1].key
    end

    -- Get theme colors
    local ar, ag, ab = theme:GetAccentColor()
    local bgR, bgG, bgB, bgA = theme:GetBackgroundSolidColor()
    local dimR, dimG, dimB = theme:GetDimTextColor()

    -- Calculate tab row layout
    local numTabs = #tabs
    local hasSecondRow = numTabs > maxTabsPerRow
    local tabBarHeight = hasSecondRow and (TAB_HEIGHT * 2 + TAB_ROW_SPACING) or TAB_HEIGHT

    -- Main container frame
    local section = CreateFrame("Frame", name, parent)
    section._selectedTabKey = selectedTabKey
    section._componentId = componentId
    section._sectionKey = sectionKey
    section._tabs = tabs
    section._tabButtons = {}
    section._tabContents = {}
    section._contentHeights = {}

    -- Tab bar container
    local tabBar = CreateFrame("Frame", nil, section)
    tabBar:SetPoint("TOPLEFT", section, "TOPLEFT", 0, 0)
    tabBar:SetPoint("TOPRIGHT", section, "TOPRIGHT", 0, 0)
    tabBar:SetHeight(tabBarHeight)
    section._tabBar = tabBar

    -- Content container (below tab bar)
    local contentContainer = CreateFrame("Frame", nil, section)
    contentContainer:SetPoint("TOPLEFT", tabBar, "BOTTOMLEFT", 0, 0)
    contentContainer:SetPoint("TOPRIGHT", tabBar, "BOTTOMRIGHT", 0, 0)
    -- Height set dynamically based on selected tab content
    section._contentContainer = contentContainer

    -- Content border textures (all 4 sides)
    section._contentBorders = Controls.CreateBorder(contentContainer, {
        thickness = TABBED_BORDER_WIDTH,
        alpha = TABBED_BORDER_ALPHA,
    })

    -- Content background
    local contentBg = contentContainer:CreateTexture(nil, "BACKGROUND", nil, -8)
    contentBg:SetPoint("TOPLEFT", TABBED_BORDER_WIDTH, 0)
    contentBg:SetPoint("BOTTOMRIGHT", -TABBED_BORDER_WIDTH, TABBED_BORDER_WIDTH)
    contentBg:SetColorTexture(0, 0, 0, 0.15)
    section._contentBg = contentBg

    -- Create tab buttons and content frames
    local INFO_ICON_SIZE = 12
    local INFO_ICON_SPACING = 4

    local function CreateTabButton(tabData, index)
        local tabBtn = CreateFrame("Button", nil, tabBar)
        tabBtn:SetHeight(TAB_HEIGHT)
        tabBtn:EnableMouse(true)
        tabBtn:RegisterForClicks("AnyUp")

        -- Check if this tab has an info icon
        local hasInfoIcon = tabData.infoIcon and (tabData.infoIcon.tooltipText or tabData.infoIcon.tooltipTitle)
        local infoIconWidth = hasInfoIcon and (INFO_ICON_SIZE + INFO_ICON_SPACING) or 0

        -- Calculate text width for button sizing
        local labelFont = theme:GetFont("LABEL")
        local tempFS = tabBtn:CreateFontString(nil, "OVERLAY")
        tempFS:SetFont(labelFont, 12, "")
        tempFS:SetText(tabData.label)
        local textWidth = tempFS:GetStringWidth()
        tempFS:Hide()

        local btnWidth
        if textWidth and textWidth > 0 then
            btnWidth = textWidth + (TAB_PADDING * 2) + infoIconWidth
        else
            -- Font not loaded yet (first game launch) - estimate width
            -- ~7px per character at 12pt, plus padding
            btnWidth = (#tabData.label * 7) + (TAB_PADDING * 2) + infoIconWidth
            -- Re-measure after font loads
            C_Timer.After(0, function()
                if tabBtn and tempFS then
                    tempFS:Show()
                    local actualWidth = tempFS:GetStringWidth()
                    tempFS:Hide()
                    if actualWidth and actualWidth > 0 then
                        tabBtn:SetWidth(actualWidth + (TAB_PADDING * 2) + infoIconWidth)
                    end
                end
            end)
        end
        tabBtn:SetWidth(btnWidth)

        -- Selected fill background (accent color, shown when selected)
        tabBtn._selectedFill = Controls.AddHoverFill(tabBtn, { alpha = 1, inset = 1 })

        -- Hover background (subtle highlight)
        tabBtn._hoverBg = Controls.AddHoverFill(tabBtn, {
            alpha = 0.15,
            inset = 1,
            sublevel = Controls.SUBLEVEL_BG,
        })

        -- Tab border (full box)
        tabBtn._borders = Controls.CreateBorder(tabBtn, { alpha = TABBED_BORDER_ALPHA })

        -- Label (offset left if info icon present)
        local labelStr = tabBtn:CreateFontString(nil, "OVERLAY")
        labelStr:SetFont(labelFont, 12, "")
        if hasInfoIcon then
            -- Center the label + icon combo by offsetting label left
            labelStr:SetPoint("CENTER", -infoIconWidth / 2, 0)
        else
            labelStr:SetPoint("CENTER", 0, 0)
        end
        labelStr:SetText(tabData.label)
        labelStr:SetTextColor(ar, ag, ab, 1)
        tabBtn._label = labelStr

        -- Info icon (if specified)
        if hasInfoIcon and Controls.CreateInfoIcon then
            local infoBtn = Controls:CreateInfoIcon({
                parent = tabBtn,
                tooltipTitle = tabData.infoIcon.tooltipTitle,
                tooltipText = tabData.infoIcon.tooltipText,
                size = INFO_ICON_SIZE,
                iconType = "info",
            })
            infoBtn:SetPoint("LEFT", labelStr, "RIGHT", INFO_ICON_SPACING, 0)
            tabBtn._infoIcon = infoBtn
        end

        -- Store tab key
        tabBtn._tabKey = tabData.key
        tabBtn._tabIndex = index

        -- Click handler
        tabBtn:SetScript("OnClick", function(self)
            section:SelectTab(self._tabKey)
            PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB)
        end)

        -- Hover handlers
        tabBtn:SetScript("OnEnter", function(self)
            if section._selectedTabKey ~= self._tabKey then
                self._hoverBg:Show()
            end
        end)

        tabBtn:SetScript("OnLeave", function(self)
            self._hoverBg:Hide()
        end)

        return tabBtn
    end

    local function CreateTabContent(tabData, index)
        local content = CreateFrame("Frame", nil, contentContainer)
        content:SetPoint("TOPLEFT", contentContainer, "TOPLEFT", TABBED_BORDER_WIDTH + TABBED_CONTENT_PADDING, -TABBED_CONTENT_PADDING)
        content:SetPoint("TOPRIGHT", contentContainer, "TOPRIGHT", -(TABBED_BORDER_WIDTH + TABBED_CONTENT_PADDING), -TABBED_CONTENT_PADDING)
        -- Height managed dynamically
        content._tabKey = tabData.key
        content._tabIndex = index
        return content
    end

    -- Create all tabs
    for i, tabData in ipairs(tabs) do
        local tabBtn = CreateTabButton(tabData, i)
        local tabContent = CreateTabContent(tabData, i)

        tabBtn._visible = tabData.visible  -- nil means always visible
        section._tabButtons[tabData.key] = tabBtn
        section._tabContents[tabData.key] = tabContent
        section._contentHeights[tabData.key] = 100  -- Default, updated by builder
    end

    -- Position tabs (with multi-row support)
    local function LayoutTabs()
        local allTabs = {}
        for _, tabData in ipairs(tabs) do
            local tabBtn = section._tabButtons[tabData.key]
            local isVis = true
            if type(tabBtn._visible) == "function" then
                isVis = tabBtn._visible()
            end
            if isVis then
                tabBtn:Show()
                table.insert(allTabs, tabBtn)
            else
                tabBtn:Hide()
            end
        end

        if #allTabs == 0 then return end

        -- Recalculate row layout based on visible count
        local visCount = #allTabs
        local needsSecondRow = visCount > maxTabsPerRow
        local newTabBarHeight = needsSecondRow and (TAB_HEIGHT * 2 + TAB_ROW_SPACING) or TAB_HEIGHT
        tabBar:SetHeight(newTabBarHeight)
        tabBarHeight = newTabBarHeight  -- update upvalue

        -- Split into rows: bottom row (first maxTabsPerRow), top row (rest)
        local bottomCount = math.min(maxTabsPerRow, visCount)
        local bottomRow = {}
        for i = 1, bottomCount do
            table.insert(bottomRow, allTabs[i])
        end

        local topRow = {}
        if visCount > maxTabsPerRow then
            for i = maxTabsPerRow + 1, visCount do
                table.insert(topRow, allTabs[i])
            end
        end

        -- Position bottom row (left-aligned)
        local xOffset = TAB_BAR_PADDING
        local yOffset = needsSecondRow and -(TAB_HEIGHT + TAB_ROW_SPACING) or 0

        for i, tabBtn in ipairs(bottomRow) do
            tabBtn:ClearAllPoints()
            tabBtn:SetPoint("TOPLEFT", tabBar, "TOPLEFT", xOffset, yOffset)
            xOffset = xOffset + tabBtn:GetWidth() + TAB_SPACING
        end

        -- Position top row (left-aligned, above bottom row)
        if #topRow > 0 then
            xOffset = TAB_BAR_PADDING
            for i, tabBtn in ipairs(topRow) do
                tabBtn:ClearAllPoints()
                tabBtn:SetPoint("TOPLEFT", tabBar, "TOPLEFT", xOffset, 0)
                xOffset = xOffset + tabBtn:GetWidth() + TAB_SPACING
            end
        end
    end

    LayoutTabs()

    -- Tab selection state update
    local function UpdateTabVisuals()
        for key, tabBtn in pairs(section._tabButtons) do
            local isSelected = (key == section._selectedTabKey)
            tabBtn._selectedFill:SetShown(isSelected)
            tabBtn._hoverBg:Hide()

            if isSelected then
                -- Selected: inverted colors (accent fill, dark text)
                tabBtn._label:SetTextColor(0, 0, 0, 1)
            else
                -- Not selected: accent text, no fill
                local r, g, b = theme:GetAccentColor()
                tabBtn._label:SetTextColor(r, g, b, 1)
            end
        end

        -- Show/hide content frames
        for key, content in pairs(section._tabContents) do
            content:SetShown(key == section._selectedTabKey)
        end
    end

    local function UpdateSectionHeight()
        local contentHeight = section._contentHeights[section._selectedTabKey] or 100
        local totalContentHeight = contentHeight + (TABBED_CONTENT_PADDING * 2) + TABBED_BORDER_WIDTH

        contentContainer:SetHeight(totalContentHeight)
        local newHeight = tabBarHeight + totalContentHeight
        section:SetHeight(newHeight)

        -- Notify parent of height change (for dynamic resizing of parent collapsible)
        if onHeightChange then
            onHeightChange(newHeight)
        end
    end

    -- Initialize visual state
    UpdateTabVisuals()
    UpdateSectionHeight()

    -- Theme subscription
    local subscribeKey = "TabbedSection_" .. componentId .. "_" .. sectionKey
    section._subscribeKey = subscribeKey

    theme:Subscribe(subscribeKey, function(r, g, b)
        -- Borders and fills retint via Utils; only the labels need per-state handling
        for key, tabBtn in pairs(section._tabButtons) do
            if key == section._selectedTabKey then
                tabBtn._label:SetTextColor(0, 0, 0, 1)  -- Dark text on accent fill
            else
                tabBtn._label:SetTextColor(r, g, b, 1)  -- Accent text
            end
        end
    end)

    -- Public methods
    function section:SelectTab(tabKey)
        if tabKey == self._selectedTabKey then return end

        local oldKey = self._selectedTabKey
        self._selectedTabKey = tabKey
        SetTabState(self._componentId, self._sectionKey, tabKey)

        UpdateTabVisuals()
        UpdateSectionHeight()

        if onTabChange then
            onTabChange(tabKey, oldKey)
        end
    end

    function section:GetSelectedTab()
        return self._selectedTabKey
    end

    function section:GetTabContent(tabKey)
        return self._tabContents[tabKey]
    end

    function section:SetTabContentHeight(tabKey, height)
        self._contentHeights[tabKey] = height
        if tabKey == self._selectedTabKey then
            UpdateSectionHeight()
        end
    end

    function section:SetOnHeightChange(callback)
        onHeightChange = callback
    end

    function section:GetHeight()
        local contentHeight = self._contentHeights[self._selectedTabKey] or 100
        local totalContentHeight = contentHeight + (TABBED_CONTENT_PADDING * 2) + TABBED_BORDER_WIDTH
        return tabBarHeight + totalContentHeight
    end

    function section:GetTabBarHeight()
        return tabBarHeight
    end

    function section:Cleanup()
        if self._subscribeKey then
            theme:Unsubscribe(self._subscribeKey)
        end
        -- Clean up any inner builders stored on content frames
        for key, content in pairs(self._tabContents) do
            if content._innerBuilder and content._innerBuilder.Cleanup then
                content._innerBuilder:Cleanup()
            end
        end
    end

    function section:RefreshTabVisibility()
        LayoutTabs()
        -- If selected tab is now invisible, select first visible tab
        local selBtn = self._tabButtons[self._selectedTabKey]
        if selBtn and not selBtn:IsShown() then
            for _, tabData in ipairs(tabs) do
                local btn = self._tabButtons[tabData.key]
                if btn and btn:IsShown() then
                    self:SelectTab(tabData.key)
                    return
                end
            end
        end
        UpdateTabVisuals()
        UpdateSectionHeight()
    end

    return section
end
