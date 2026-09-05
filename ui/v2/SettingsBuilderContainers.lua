-- SettingsBuilderContainers.lua - Collapsible and tabbed sections over SettingsBuilder
-- Attaches methods to addon.UI.SettingsBuilder; instances created by
-- Builder:CreateFor resolve them through the metatable, so inner builders
-- nested to any depth see the full method set.
local addonName, addon = ...

local Builder = addon.UI.SettingsBuilder
local Controls = addon.UI.Controls

local ITEM_SPACING = Builder._ITEM_SPACING
local CONTENT_PADDING = Builder._CONTENT_PADDING

--------------------------------------------------------------------------------
-- AddCollapsibleSection: Add an expandable/collapsible section
--------------------------------------------------------------------------------
-- Creates a collapsible section with header and content area.
-- Content is built via a callback that receives an inner builder.
--
-- Options:
--   title         : Section title text (required)
--   componentId   : Component identifier for state persistence (required)
--   sectionKey    : Unique key within component (required)
--   defaultExpanded : Initial expanded state (default false)
--   buildContent  : function(contentFrame, innerBuilder) to populate content
--   onToggle      : Optional callback when expand/collapse changes
--------------------------------------------------------------------------------

local COLLAPSIBLE_GAP_COLLAPSED = 8
local COLLAPSIBLE_GAP_EXPANDED = 12

function Builder:AddCollapsibleSection(options)
    local scrollContent = self._scrollContent
    if not scrollContent then return self end

    if not options.title or not options.componentId or not options.sectionKey then
        return self
    end

    if Builder._scanMode then
        table.insert(Builder._scanSectionStack, {
            title = options.title,
            componentId = options.componentId,
            sectionKey = options.sectionKey,
        })
        if options.buildContent then
            options.buildContent(self._scrollContent, self)
        end
        table.remove(Builder._scanSectionStack)
        return self
    end

    if #self._controls > 0 or #self._sections > 0 then
        self._currentY = self._currentY - ITEM_SPACING
    end

    -- Store reference to onRefresh callback if set
    local onRefresh = self._onRefresh

    local section = Controls:CreateCollapsibleSection({
        parent = scrollContent,
        title = options.title,
        componentId = options.componentId,
        sectionKey = options.sectionKey,
        defaultExpanded = options.defaultExpanded,
        contentHeight = 100,  -- Placeholder, will be updated by inner builder
        infoIcon = options.infoIcon,  -- Pass through info icon options
        onToggle = function(expanded)
            -- Call user callback if provided
            if options.onToggle then
                options.onToggle(expanded)
            end
            -- Trigger page refresh to re-layout
            if onRefresh then
                onRefresh()
            end
        end,
    })

    if not section then return self end

    -- Store outer refresh callback on section for dynamic height updates from nested controls
    section._outerOnRefresh = onRefresh

    section:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", CONTENT_PADDING, self._currentY)
    section:SetPoint("TOPRIGHT", scrollContent, "TOPRIGHT", -CONTENT_PADDING, self._currentY)

    table.insert(self._controls, section)

    -- Build content using an inner builder
    if options.buildContent then
        local contentFrame = section:GetContentFrame()

        -- Create inner builder for the content area
        local innerBuilder = Builder:CreateFor(contentFrame)
        innerBuilder._useLightDim = true  -- Use lighter description text on gray background
        innerBuilder._parentSectionTitle = options.title  -- For search navigate-to-result
        innerBuilder._parentCollapsible = section  -- Reference for dynamic height updates
        innerBuilder._onRefresh = onRefresh  -- Nested builders can DeferredRefreshAll()

        -- Call the build function
        options.buildContent(contentFrame, innerBuilder)

        -- Get the content height from the inner builder
        local contentHeight = innerBuilder:GetHeight()

        -- Set the section's content height
        section:SetContentHeight(contentHeight)

        -- Store inner builder for cleanup
        section._innerBuilder = innerBuilder
    end

    -- Update Y position based on current expanded state
    local sectionHeight = section:GetHeight()
    self._currentY = self._currentY - sectionHeight

    -- Add appropriate gap after section
    local gap = section:IsExpanded() and COLLAPSIBLE_GAP_EXPANDED or COLLAPSIBLE_GAP_COLLAPSED
    self._currentY = self._currentY - gap

    return self
end

--------------------------------------------------------------------------------
-- AddTabbedSection: Add a horizontal tabbed section for sub-settings
--------------------------------------------------------------------------------
-- Creates a tabbed section with multiple tab pages, each with its own content.
-- Dynamic height based on selected tab's content.
--
-- Options:
--   tabs          : Array of { key = "uniqueKey", label = "Display Label" } (required)
--   componentId   : Component identifier for state persistence (required)
--   sectionKey    : Unique key within component (required)
--   defaultTab    : Key of tab to show by default (optional, defaults to first)
--   buildContent  : Table of { tabKey = function(contentFrame, innerBuilder) }
--                   Each function populates that tab's content
--   onTabChange   : Optional callback when tab changes
--   maxTabsPerRow : Optional per-row tab capacity (default 5)
--------------------------------------------------------------------------------

function Builder:AddTabbedSection(options)
    local scrollContent = self._scrollContent
    if not scrollContent then return self end

    if not options.tabs or #options.tabs == 0 or not options.componentId or not options.sectionKey then
        return self
    end

    if Builder._scanMode then
        if options.buildContent then
            for _, tabData in ipairs(options.tabs) do
                local buildFunc = options.buildContent[tabData.key]
                if buildFunc then
                    table.insert(Builder._scanSectionStack, {
                        title = tabData.label,
                        tab = tabData.key,
                        tabLabel = tabData.label,
                        componentId = options.componentId,
                        sectionKey = options.sectionKey,
                    })
                    buildFunc(self._scrollContent, self)
                    table.remove(Builder._scanSectionStack)
                end
            end
        end
        return self
    end

    if #self._controls > 0 or #self._sections > 0 then
        self._currentY = self._currentY - ITEM_SPACING
    end

    -- Store reference to onRefresh callback if set
    local onRefresh = self._onRefresh

    -- Reference to parent collapsible (if nested inside one)
    local parentCollapsible = self._parentCollapsible

    local section = Controls:CreateTabbedSection({
        parent = scrollContent,
        tabs = options.tabs,
        componentId = options.componentId,
        sectionKey = options.sectionKey,
        defaultTab = options.defaultTab,
        maxTabsPerRow = options.maxTabsPerRow,
        onTabChange = function(newTabKey, oldTabKey)
            -- Call user callback if provided
            if options.onTabChange then
                options.onTabChange(newTabKey, oldTabKey)
            end
            -- Trigger page refresh to re-layout if height might change
            -- (Only if not inside a collapsible - collapsible handles its own refresh)
            if onRefresh and not parentCollapsible then
                onRefresh()
            end
        end,
    })

    if not section then return self end

    section:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", CONTENT_PADDING, self._currentY)
    section:SetPoint("TOPRIGHT", scrollContent, "TOPRIGHT", -CONTENT_PADDING, self._currentY)

    table.insert(self._controls, section)

    -- Build content for each tab using inner builders
    if options.buildContent then
        for _, tabData in ipairs(options.tabs) do
            local tabKey = tabData.key
            local buildFunc = options.buildContent[tabKey]

            if buildFunc then
                local contentFrame = section:GetTabContent(tabKey)

                if contentFrame then
                    -- Create inner builder for this tab's content
                    local innerBuilder = Builder:CreateFor(contentFrame)
                    innerBuilder._useLightDim = self._useLightDim  -- Inherit parent's light dim setting
                    innerBuilder._parentSectionTitle = tabData.label  -- For search navigate-to-result
                    innerBuilder._onRefresh = onRefresh  -- Nested builders can DeferredRefreshAll()

                    -- Call the build function
                    buildFunc(contentFrame, innerBuilder)

                    -- Get the content height from the inner builder
                    local contentHeight = innerBuilder:GetHeight()

                    -- Set this tab's content height
                    section:SetTabContentHeight(tabKey, contentHeight)

                    -- Also give the tab content frame itself an explicit height matching
                    -- its children. When the tabbed section is used at the top level of
                    -- a scroll page (not nested inside a collapsible), leaving tabContent
                    -- with no SetHeight causes the children not to render — observed on
                    -- group frame Aura Tracking per-spell tabs. Collapsible content frames
                    -- get explicit SetHeight internally, which is why nested cases work.
                    if contentFrame.SetHeight then
                        contentFrame:SetHeight(contentHeight)
                    end

                    -- Store inner builder on content frame for cleanup
                    contentFrame._innerBuilder = innerBuilder
                end
            end
        end
    end

    -- Update Y position based on current section height
    local sectionHeight = section:GetHeight()
    self._currentY = self._currentY - sectionHeight

    -- Add gap after section
    self._currentY = self._currentY - ITEM_SPACING

    -- If inside a collapsible, set up dynamic height updates
    -- This must be done AFTER _currentY is updated to capture the correct initial height
    if parentCollapsible and section then
        -- Track the initial tabbed section height
        -- Content height is computed from the current builder state
        local lastTabbedHeight = section:GetHeight()

        section:SetOnHeightChange(function(newTabbedHeight)
            -- Calculate the delta from the last known tabbed section height
            local delta = newTabbedHeight - lastTabbedHeight
            lastTabbedHeight = newTabbedHeight  -- Update for next change

            -- Get current collapsible content height and apply delta
            local currentContentHeight = parentCollapsible._contentHeight or 100
            local newContentHeight = currentContentHeight + delta
            parentCollapsible:SetContentHeight(newContentHeight)

            -- Trigger outer page refresh to reposition controls below this collapsible
            if parentCollapsible._outerOnRefresh then
                parentCollapsible._outerOnRefresh()
            end
        end)
    end

    return section
end
