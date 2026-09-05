-- SettingsBuilder.lua - Declarative layout system for UI settings
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.SettingsBuilder = {}
local Builder = addon.UI.SettingsBuilder
local Theme = addon.UI.Theme
local Controls = addon.UI.Controls

-- Scan mode state (module-level, shared across all builder instances during index scan)
Builder._scanMode = false
Builder._scanEntries = {}
Builder._scanRendererKey = nil
Builder._scanSectionStack = {}

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

local SECTION_HEADER_HEIGHT = 32
local SECTION_SPACING = 16          -- Space before a section header
local ITEM_SPACING = 12             -- Space between controls
local CONTENT_PADDING = 8           -- Padding from edges
local FIRST_ITEM_OFFSET = 8         -- Initial offset from top

-- Shared with the files that attach further methods to this table.
Builder._ITEM_SPACING = ITEM_SPACING
Builder._CONTENT_PADDING = CONTENT_PADDING

--------------------------------------------------------------------------------
-- Builder Instance Methods
--------------------------------------------------------------------------------
-- The builder pattern: Create a builder for a scroll content frame,
-- then use chainable methods to add controls. Finalize when done.
--
-- Usage:
--   local builder = addon.UI.SettingsBuilder:CreateFor(scrollContent)
--   builder:AddSection("Quality of Life")
--   builder:AddToggle({
--       label = "Enable Feature",
--       get = function() return addon.db.profile.feature end,
--       set = function(v) addon.db.profile.feature = v end,
--   })
--   builder:Finalize()
--------------------------------------------------------------------------------

function Builder:CreateFor(scrollContent)
    local instance = {
        _scrollContent = scrollContent,
        _currentY = -FIRST_ITEM_OFFSET,
        _controls = {},         -- Track created controls for cleanup
        _controlsByKey = {},    -- Track controls by key for dynamic updates
        _sections = {},         -- Track section headers
        _inSection = false,     -- Currently inside a section?
        _useLightDim = false,   -- Use lighter dim text (for collapsible section interiors)
        _parentCollapsible = nil, -- Reference to parent collapsible section (if inside one)
    }

    -- Set metatable to use Builder methods on the instance
    setmetatable(instance, { __index = self })

    return instance
end

--------------------------------------------------------------------------------
-- Clear: Remove all existing content from the scroll content
--------------------------------------------------------------------------------

function Builder:Clear()
    -- Cleanup existing controls
    for _, control in ipairs(self._controls) do
        if control.Cleanup then
            control:Cleanup()
        end
        if control.Hide then
            control:Hide()
        end
        if control.SetParent then
            control:SetParent(nil)
        end
    end
    self._controls = {}
    self._controlsByKey = {}

    -- Hide section headers
    for _, header in ipairs(self._sections) do
        if header.Hide then
            header:Hide()
        end
    end
    self._sections = {}

    -- Reset position
    self._currentY = -FIRST_ITEM_OFFSET
    self._inSection = false

    return self
end

--------------------------------------------------------------------------------
-- Row helpers shared by the delegating Add* methods
--------------------------------------------------------------------------------
-- _ScanRecord: during a search-index scan, record the row and skip rendering.
-- Returns true when the caller should return without creating its control.
--
-- _PlaceRow: the placement tail for a created control: item spacing (plus 4 for
-- emphasized rows), the edge anchors, registration in _controls and
-- _controlsByKey, the search tags read by settingspanel/search.lua, the Y
-- advance, and deferred height propagation to a parent collapsible. A nil
-- control places nothing and advances nothing.
--
-- _AttachInfoIcon: an info icon beside the control's label, registered for
-- cleanup. Runs after _PlaceRow; it reads no layout state.
--------------------------------------------------------------------------------

function Builder:_ScanRecord(entryType, label, description)
    if not (Builder._scanMode and label) then return false end
    table.insert(Builder._scanEntries, {
        type = entryType,
        label = label,
        description = description or "",
        rendererKey = Builder._scanRendererKey,
        section = Builder._scanSectionStack[#Builder._scanSectionStack],
    })
    return true
end

function Builder:_PlaceRow(ctl, options)
    if not ctl then return end
    local scrollContent = self._scrollContent

    if #self._controls > 0 then
        local spacing = options.emphasized and (ITEM_SPACING + 4) or ITEM_SPACING
        self._currentY = self._currentY - spacing
    end

    ctl:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", CONTENT_PADDING, self._currentY)
    ctl:SetPoint("TOPRIGHT", scrollContent, "TOPRIGHT", -CONTENT_PADDING, self._currentY)

    table.insert(self._controls, ctl)
    ctl._searchLabel = options.label
    ctl._searchSection = self._parentSectionTitle

    if options.key then
        self._controlsByKey[options.key] = ctl
    end

    self._currentY = self._currentY - ctl:GetHeight()

    if self._parentCollapsible then
        local parentCollapsible = self._parentCollapsible
        ctl._onHeightChanged = function(delta)
            parentCollapsible:SetContentHeight(parentCollapsible._contentHeight + delta)
        end
    end
end

function Builder:_AttachInfoIcon(ctl, options)
    if not ctl then return end
    local infoSpec = Controls.InfoIconOptions(options.infoIcon)
    if not (infoSpec and ctl._label) then return end
    local infoIcon = Controls:CreateInfoIcon({
        parent = ctl,
        tooltipText = infoSpec.tooltipText,
        tooltipTitle = infoSpec.tooltipTitle,
        size = infoSpec.size or 12,
    })
    if infoIcon then
        infoIcon:SetPoint("LEFT", ctl._label, "RIGHT", 4, 4)
        ctl._infoIcon = infoIcon
        table.insert(self._controls, infoIcon)
    end
end

--------------------------------------------------------------------------------
-- AddSection: Add a section header with terminal-style formatting
--------------------------------------------------------------------------------
-- Creates a header like:
--   ┌─ SECTION TITLE ─────────────────────────────────────┐
--
-- Options:
--   title : Section title text
--   icon  : Optional icon character (e.g., "▸", "◆")
--------------------------------------------------------------------------------

function Builder:AddSection(title, options)
    options = options or {}
    local scrollContent = self._scrollContent
    if not scrollContent then return self end

    -- Add spacing before section (unless it's the first item)
    if self._inSection or #self._controls > 0 then
        self._currentY = self._currentY - SECTION_SPACING
    end

    local header = CreateFrame("Frame", nil, scrollContent)
    header:SetHeight(SECTION_HEADER_HEIGHT)
    header:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", 0, self._currentY)
    header:SetPoint("TOPRIGHT", scrollContent, "TOPRIGHT", 0, self._currentY)

    -- Get theme colors
    local ar, ag, ab = Theme:GetAccentColor()

    -- Section title with terminal-style prefix
    local prefix = options.icon or "▸"
    local titleFS = header:CreateFontString(nil, "OVERLAY")
    local fontPath = Theme:GetFont("HEADER")
    titleFS:SetFont(fontPath, 14, "")
    titleFS:SetPoint("LEFT", header, "LEFT", CONTENT_PADDING, 0)
    titleFS:SetText(prefix .. " " .. (title or "Section"))
    titleFS:SetTextColor(ar, ag, ab, 1)
    header._title = titleFS

    -- Horizontal line after title
    local line = header:CreateTexture(nil, "BORDER")
    line:SetHeight(1)
    line:SetPoint("LEFT", titleFS, "RIGHT", 8, 0)
    line:SetPoint("RIGHT", header, "RIGHT", -CONTENT_PADDING, 0)
    line:SetColorTexture(ar, ag, ab, 0.3)
    header._line = line

    -- Subscribe to theme changes
    local subscribeKey = "UISection_" .. tostring(header)
    Theme:Subscribe(subscribeKey, function(r, g, b)
        if titleFS then
            titleFS:SetTextColor(r, g, b, 1)
        end
        if line then
            line:SetColorTexture(r, g, b, 0.3)
        end
    end)
    header._subscribeKey = subscribeKey
    header.Cleanup = function(self)
        if self._subscribeKey then
            Theme:Unsubscribe(self._subscribeKey)
        end
    end

    table.insert(self._sections, header)

    self._currentY = self._currentY - SECTION_HEADER_HEIGHT
    self._inSection = true

    return self
end

--------------------------------------------------------------------------------
-- AddToggle: Add a toggle (boolean) setting
--------------------------------------------------------------------------------
-- Options:
--   label       : Setting label text
--   description : Optional description below label
--   get         : Function returning current value
--   set         : Function(newValue) to save value
--   key         : Optional unique key for dynamic updates (SetLabel, etc.)
--   emphasized  : Optional boolean for "Hero Toggle" styling (master controls)
--   infoIcon    : Optional { tooltipText, tooltipTitle } for inline info icon
--------------------------------------------------------------------------------

function Builder:AddToggle(options)
    local scrollContent = self._scrollContent
    if not scrollContent then return self end

    if self:_ScanRecord("toggle", options.label, options.description) then return self end

    local toggle = Controls:CreateToggle({
        parent = scrollContent,
        label = options.label,
        description = options.description,
        get = options.get,
        set = options.set,
        useLightDim = self._useLightDim,
        emphasized = options.emphasized,
        infoIcon = options.infoIcon,
        disabled = options.disabled,
        isDisabled = options.isDisabled,
    })

    self:_PlaceRow(toggle, options)

    return self
end

--------------------------------------------------------------------------------
-- AddDescription: Add standalone descriptive text
--------------------------------------------------------------------------------
-- Options:
--   text   : Description text
--   dim    : Use dim color (default true)
--------------------------------------------------------------------------------

function Builder:AddDescription(text, options)
    options = options or {}
    local scrollContent = self._scrollContent
    if not scrollContent then return self end

    if #self._controls > 0 or #self._sections > 0 then
        self._currentY = self._currentY - ITEM_SPACING
    end
    if options.topPadding then
        self._currentY = self._currentY - options.topPadding
    end

    local frame = CreateFrame("Frame", nil, scrollContent)
    frame:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", CONTENT_PADDING, self._currentY)
    frame:SetPoint("TOPRIGHT", scrollContent, "TOPRIGHT", -CONTENT_PADDING, self._currentY)

    local descFS = frame:CreateFontString(nil, "OVERLAY")
    local fontPath = Theme:GetFont("VALUE")
    descFS:SetFont(fontPath, options.fontSize or 12, "")
    descFS:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    descFS:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    descFS:SetText(text or "")
    descFS:SetJustifyH("LEFT")
    descFS:SetWordWrap(true)

    -- Color (use lighter dim for collapsible section interiors)
    if options.color then
        descFS:SetTextColor(options.color[1], options.color[2], options.color[3], 1)
    elseif options.dim ~= false then
        local dR, dG, dB
        if self._useLightDim then
            dR, dG, dB = Theme:GetDimTextLightColor()
        else
            dR, dG, dB = Theme:GetDimTextColor()
        end
        descFS:SetTextColor(dR, dG, dB, 1)
    else
        local ar, ag, ab = Theme:GetAccentColor()
        descFS:SetTextColor(ar, ag, ab, 1)
    end

    frame._text = descFS

    -- Calculate height based on text
    C_Timer.After(0, function()
        if descFS and frame then
            local textHeight = descFS:GetStringHeight() or 16
            frame:SetHeight(textHeight + 4)
        end
    end)

    -- Initial height estimate (will be corrected)
    local estimatedHeight = math.ceil((string.len(text or "") / 80) + 1) * 14
    frame:SetHeight(math.max(16, estimatedHeight))

    table.insert(self._controls, frame)

    self._currentY = self._currentY - frame:GetHeight()
    if options.bottomPadding then
        self._currentY = self._currentY - options.bottomPadding
    end

    return self
end

--------------------------------------------------------------------------------
-- AddLabel: Add a subsection label/header
--------------------------------------------------------------------------------
-- Creates a bold, non-dim label used for grouping controls within a section.
-- Usage: inner:AddLabel("Group Title")
--------------------------------------------------------------------------------

function Builder:AddLabel(text)
    local scrollContent = self._scrollContent
    if not scrollContent then return self end

    if #self._controls > 0 or #self._sections > 0 then
        self._currentY = self._currentY - ITEM_SPACING
    end

    local frame = CreateFrame("Frame", nil, scrollContent)
    frame:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", CONTENT_PADDING, self._currentY)
    frame:SetPoint("TOPRIGHT", scrollContent, "TOPRIGHT", -CONTENT_PADDING, self._currentY)

    local labelFS = frame:CreateFontString(nil, "OVERLAY")
    local fontPath = Theme:GetFont("VALUE")
    labelFS:SetFont(fontPath, 12, "")
    labelFS:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    labelFS:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    labelFS:SetText(text or "")
    labelFS:SetJustifyH("LEFT")
    labelFS:SetWordWrap(false)

    -- Use accent color for labels (not dim)
    local ar, ag, ab = Theme:GetAccentColor()
    labelFS:SetTextColor(ar, ag, ab, 1)

    frame._text = labelFS
    frame:SetHeight(18)

    table.insert(self._controls, frame)

    self._currentY = self._currentY - frame:GetHeight()

    return self
end

--------------------------------------------------------------------------------
-- AddSpacer: Add vertical space
--------------------------------------------------------------------------------

function Builder:AddSpacer(height)
    height = height or 16
    self._currentY = self._currentY - height
    return self
end

--------------------------------------------------------------------------------
-- Finalize: Set scroll content height and prepare for display
--------------------------------------------------------------------------------

function Builder:Finalize()
    local scrollContent = self._scrollContent
    if not scrollContent then return self end

    -- Add bottom padding
    local totalHeight = math.abs(self._currentY) + CONTENT_PADDING

    -- Set scroll content height
    scrollContent:SetHeight(totalHeight)

    -- Store final height for reference
    self._finalHeight = totalHeight

    return self
end

--------------------------------------------------------------------------------
-- GetHeight: Return the computed content height
--------------------------------------------------------------------------------

function Builder:GetHeight()
    return self._finalHeight or math.abs(self._currentY)
end

--------------------------------------------------------------------------------
-- GetControl: Retrieve a control by its key for dynamic updates
--------------------------------------------------------------------------------
-- Returns the control registered with the given key, or nil if not found.
-- Use this to update controls dynamically (e.g., SetLabel, SetOptions).
--
-- Usage:
--   builder:AddSelector({ ..., key = "iconDirection" })
--   local selector = builder:GetControl("iconDirection")
--   selector:SetOptions(newValues, newOrder)
--------------------------------------------------------------------------------

function Builder:GetControl(key)
    return self._controlsByKey[key]
end

--------------------------------------------------------------------------------
-- Cleanup: Release all resources
--------------------------------------------------------------------------------

function Builder:Cleanup()
    self:Clear()
    self._scrollContent = nil
end

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
-- SetOnRefresh: Set a callback to be called when sections expand/collapse
--------------------------------------------------------------------------------
-- Allows the renderer to re-render the page when layout changes. The inner
-- builders of collapsible and tabbed sections inherit the callback, so
-- DeferredRefreshAll() rebuilds the page from any depth.
--
-- Usage:
--   builder:SetOnRefresh(function()
--       self:RenderMyCategory(scrollContent)
--   end)
--------------------------------------------------------------------------------

function Builder:SetOnRefresh(callback)
    self._onRefresh = callback
    return self
end

function Builder:RefreshAll()
    if self._onRefresh then
        self._onRefresh()
    end
end

function Builder:DeferredRefreshAll()
    local onRefresh = self._onRefresh
    if not onRefresh then return end
    C_Timer.After(0, function()
        onRefresh()
    end)
end

--------------------------------------------------------------------------------
-- AddSelector: Add a selector/dropdown setting
--------------------------------------------------------------------------------
-- Options:
--   label       : Setting label text
--   description : Optional description below label
--   values      : Table of { key = "Display Text" } pairs
--   order       : Optional array of keys for display order
--   get         : Function returning current key
--   set         : Function(newKey) to save value
--   width       : Selector width (optional)
--   key         : Optional unique key for dynamic updates (SetLabel, SetOptions)
--   emphasized  : Optional boolean for "Hero" styling (master controls)
--   labelAlign  : "field" right-aligns the label against the field's left edge
--   noBottomBorder : Optional boolean to hide the 1px row bottom border
--   sizeScale   : Optional factor scaling the whole control (fonts, heights);
--                 not supported together with description or emphasized
--   gear        : Optional in-field gear button opening a sub-options fly-out.
--                 { pages = { [optionKey] = { build = function(content, panel,
--                 key), tooltip, width, height } }, width, height, direction }.
--                 The gear shows only while an option carrying a page is
--                 selected. See ui/v2/controls/SelectorGear.lua. A sub-option
--                 whose set triggers a page re-render closes the fly-out.
--------------------------------------------------------------------------------

function Builder:AddSelector(options)
    local scrollContent = self._scrollContent
    if not scrollContent then return self end

    if self:_ScanRecord("selector", options.label, options.description) then return self end

    local selector = Controls:CreateSelector({
        parent = scrollContent,
        label = options.label,
        description = options.description,
        values = options.values,
        order = options.order,
        get = options.get,
        set = options.set,
        width = options.width,
        useLightDim = self._useLightDim,
        emphasized = options.emphasized,
        labelAlign = options.labelAlign,
        noBottomBorder = options.noBottomBorder,
        sizeScale = options.sizeScale,
        disabled = options.disabled,
        isDisabled = options.isDisabled,
        optionInfoIcons = options.optionInfoIcons,
        disabledOptions = options.disabledOptions,
        gear = options.gear,
    })

    self:_PlaceRow(selector, options)
    self:_AttachInfoIcon(selector, options)

    return self
end

--------------------------------------------------------------------------------
-- AddSlider: Add a numeric slider setting
--------------------------------------------------------------------------------
-- Options:
--   label          : Setting label text
--   description    : Optional description below label
--   min            : Minimum value (required)
--   max            : Maximum value (required)
--   step           : Step increment (default 1)
--   get            : Function returning current value
--   set            : Function(newValue) to save value
--   minLabel       : Optional tiny label under left end
--   maxLabel       : Optional tiny label under right end
--   width          : Slider track width (optional)
--   inputWidth     : Text input width (optional)
--   precision      : Decimal places for display (default 0)
--   key            : Optional unique key for dynamic updates (SetLabel, SetMinMax)
--   onEditModeSync : Function(newValue) to call for Edit Mode sync (debounced)
--   debounceDelay  : Delay before Edit Mode sync (default 0.2s)
--   debounceKey    : Unique key for debounce timer (auto-generated if nil)
--   infoIcon       : Optional table { tooltipText, tooltipTitle } to add info icon
--------------------------------------------------------------------------------

function Builder:AddSlider(options)
    local scrollContent = self._scrollContent
    if not scrollContent then return self end

    if self:_ScanRecord("slider", options.label, options.description) then return self end

    local slider = Controls:CreateSlider({
        parent = scrollContent,
        label = options.label,
        description = options.description,
        emphasized = options.emphasized,
        min = options.min,
        max = options.max,
        step = options.step,
        get = options.get,
        set = options.set,
        minLabel = options.minLabel,
        maxLabel = options.maxLabel,
        width = options.width,
        inputWidth = options.inputWidth,
        precision = options.precision,
        displayMultiplier = options.displayMultiplier,
        displaySuffix = options.displaySuffix,
        -- Edit Mode sync support
        onEditModeSync = options.onEditModeSync,
        debounceDelay = options.debounceDelay,
        debounceKey = options.debounceKey,
        useLightDim = self._useLightDim,
        -- Disabled state support
        disabled = options.disabled,
        isDisabled = options.isDisabled,
    })

    self:_PlaceRow(slider, options)
    self:_AttachInfoIcon(slider, options)

    return self
end

--------------------------------------------------------------------------------
-- AddFontSelector: Add a font selection dropdown with popup picker
--------------------------------------------------------------------------------
-- Options:
--   label       : Setting label text
--   description : Optional description below label
--   get         : Function returning current font key (e.g., "FRIZQT__")
--   set         : Function(fontKey) to save selected font
--   width       : Selector box width (optional)
--------------------------------------------------------------------------------

function Builder:AddFontSelector(options)
    local scrollContent = self._scrollContent
    if not scrollContent then return self end

    if self:_ScanRecord("font", options.label, options.description) then return self end

    local fontSelector = Controls:CreateFontSelector({
        parent = scrollContent,
        label = options.label,
        description = options.description,
        get = options.get,
        set = options.set,
        width = options.width,
        useLightDim = self._useLightDim,
    })

    self:_PlaceRow(fontSelector, options)

    return self
end

--------------------------------------------------------------------------------
-- AddBarTextureSelector: Add a bar texture selection dropdown with popup picker
--------------------------------------------------------------------------------
-- Options:
--   label       : Setting label text
--   description : Optional description below label
--   get         : Function returning current texture key (e.g., "bevelled")
--   set         : Function(textureKey) to save selected texture
--   width       : Selector box width (optional)
--------------------------------------------------------------------------------

function Builder:AddBarTextureSelector(options)
    local scrollContent = self._scrollContent
    if not scrollContent then return self end

    local barTextureSelector = Controls:CreateBarTextureSelector({
        parent = scrollContent,
        label = options.label,
        description = options.description,
        get = options.get,
        set = options.set,
        width = options.width,
        useLightDim = self._useLightDim,
    })

    self:_PlaceRow(barTextureSelector, options)

    return self
end

--------------------------------------------------------------------------------
-- AddBarBorderSelector: Add a bar border selection dropdown with popup picker
--------------------------------------------------------------------------------
-- Options:
--   label       : Setting label text
--   description : Optional description below label
--   get         : Function returning current border key (e.g., "mmtPixel")
--   set         : Function(borderKey) to save selected border
--   width       : Selector box width (optional)
--   includeNone : Whether to show "No Border" option (default true)
--------------------------------------------------------------------------------

function Builder:AddBarBorderSelector(options)
    local scrollContent = self._scrollContent
    if not scrollContent then return self end

    if self:_ScanRecord("border", options.label, options.description) then return self end

    local barBorderSelector = Controls:CreateBarBorderSelector({
        parent = scrollContent,
        label = options.label,
        description = options.description,
        get = options.get,
        set = options.set,
        width = options.width,
        includeNone = options.includeNone,
        includeBlizzardDefault = options.includeBlizzardDefault,
        useLightDim = self._useLightDim,
        getHiddenEdges = options.getHiddenEdges,
        setHiddenEdges = options.setHiddenEdges,
    })

    self:_PlaceRow(barBorderSelector, options)

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

--------------------------------------------------------------------------------
-- AddColorPicker: Add a color selection row with swatch
--------------------------------------------------------------------------------
-- Options:
--   label       : Setting label text
--   description : Optional description below label
--   get         : Function returning {r, g, b, a} or r, g, b, a
--   set         : Function(r, g, b, a) to save color
--   hasAlpha    : Boolean, show opacity slider (default false)
--   swatchWidth : Swatch width (optional)
--   swatchHeight: Swatch height (optional)
--------------------------------------------------------------------------------

function Builder:AddColorPicker(options)
    local scrollContent = self._scrollContent
    if not scrollContent then return self end

    if self:_ScanRecord("color", options.label, options.description) then return self end

    local colorPicker = Controls:CreateColorPicker({
        parent = scrollContent,
        label = options.label,
        description = options.description,
        get = options.get,
        set = options.set,
        hasAlpha = options.hasAlpha,
        swatchWidth = options.swatchWidth,
        swatchHeight = options.swatchHeight,
        useLightDim = self._useLightDim,
        disabled = options.disabled,
        isDisabled = options.isDisabled,
    })

    self:_PlaceRow(colorPicker, options)

    return self
end

--------------------------------------------------------------------------------
-- AddToggleColorPicker: Add a toggle with inline color picker
--------------------------------------------------------------------------------
-- Options:
--   label       : Setting label text
--   description : Optional description below label
--   get         : Function returning toggle state (boolean)
--   set         : Function(newValue) to save toggle state
--   getColor    : Function returning {r, g, b, a} or r, g, b, a
--   setColor    : Function(r, g, b, a) to save color
--   hasAlpha    : Boolean, show opacity slider (default true)
--   swatchWidth : Swatch width (optional)
--   swatchHeight: Swatch height (optional)
--------------------------------------------------------------------------------

function Builder:AddToggleColorPicker(options)
    local scrollContent = self._scrollContent
    if not scrollContent then return self end

    if self:_ScanRecord("toggle + color", options.label, options.description) then return self end

    local toggleColor = Controls:CreateToggleColorPicker({
        parent = scrollContent,
        label = options.label,
        description = options.description,
        get = options.get,
        set = options.set,
        getColor = options.getColor,
        setColor = options.setColor,
        hasAlpha = options.hasAlpha,
        swatchWidth = options.swatchWidth,
        swatchHeight = options.swatchHeight,
        useLightDim = self._useLightDim,
        disabled = options.disabled,
        isDisabled = options.isDisabled,
    })

    self:_PlaceRow(toggleColor, options)

    return self
end

--------------------------------------------------------------------------------
-- AddSelectorColorPicker: Add a selector with inline color swatch for custom
--------------------------------------------------------------------------------
-- Options:
--   label       : Setting label text
--   description : Optional description below label
--   values      : Table of { key = "Display Text" } pairs
--   order       : Optional array of keys for display order
--   get         : Function returning current key
--   set         : Function(newKey) to save value
--   getColor    : Function returning {r, g, b, a} or r, g, b, a (for custom mode)
--   setColor    : Function(r, g, b, a) to save custom color
--   customValue : Key value that triggers color swatch display (default "custom")
--   hasAlpha    : Boolean, show opacity slider (default true)
--   width       : Selector width (optional)
--------------------------------------------------------------------------------

function Builder:AddSelectorColorPicker(options)
    local scrollContent = self._scrollContent
    if not scrollContent then return self end

    if self:_ScanRecord("selector + color", options.label, options.description) then return self end

    local selectorColor = Controls:CreateSelectorColorPicker({
        parent = scrollContent,
        label = options.label,
        description = options.description,
        values = options.values,
        order = options.order,
        get = options.get,
        set = options.set,
        getColor = options.getColor,
        setColor = options.setColor,
        customValue = options.customValue,
        hasAlpha = options.hasAlpha,
        width = options.width,
        useLightDim = self._useLightDim,
        disabled = options.disabled,
        isDisabled = options.isDisabled,
        optionInfoIcons = options.optionInfoIcons,
    })

    self:_PlaceRow(selectorColor, options)

    return self
end

--------------------------------------------------------------------------------
-- AddDualSlider: Add two compact sliders side-by-side (for X/Y offset pairs)
--------------------------------------------------------------------------------
-- Options:
--   label          : Setting label text (left side)
--   description    : Optional description below label
--   sliderA        : Table with slider A options (see below)
--   sliderB        : Table with slider B options (see below)
--   trackWidth     : Slider track width override (optional, default 90)
--   inputWidth     : Text input width override (optional, default 36)
--   debounceKey    : Unique key for debounce timer (optional)
--   onEditModeSync : Function(aVal, bVal) for Edit Mode sync (debounced)
--   key            : Optional unique key for dynamic updates
--
-- Slider A/B options:
--   axisLabel  : Small prefix label (e.g., "X" or "Y")
--   min, max   : Value range (required)
--   step       : Step increment (default 1)
--   get        : Function returning current value
--   set        : Function(newValue) to save value
--   minLabel   : Optional tiny label under left end
--   maxLabel   : Optional tiny label under right end
--   precision  : Decimal places for display (default 0)
--------------------------------------------------------------------------------

function Builder:AddDualSlider(options)
    local scrollContent = self._scrollContent
    if not scrollContent then return self end

    if self:_ScanRecord("slider", options.label, options.description) then return self end

    local dualSlider = Controls:CreateDualSlider({
        parent = scrollContent,
        label = options.label,
        description = options.description,
        sliderA = options.sliderA,
        sliderB = options.sliderB,
        trackWidth = options.trackWidth,
        inputWidth = options.inputWidth,
        debounceKey = options.debounceKey,
        onEditModeSync = options.onEditModeSync,
        debounceDelay = options.debounceDelay,
        useLightDim = self._useLightDim,
        disabled = options.disabled,
        isDisabled = options.isDisabled,
    })

    self:_PlaceRow(dualSlider, options)

    return self
end

--------------------------------------------------------------------------------
-- AddDualSelector: Add two compact selectors side-by-side
--------------------------------------------------------------------------------
-- Options:
--   label       : Setting label text (left side, optional)
--   description : Optional description below label
--   selectorA   : Table with selector A options (see below)
--   selectorB   : Table with selector B options (see below)
--   key         : Optional unique key for dynamic updates
--   disabled    : Function returning disabled state (optional)
--
-- Selector A/B options:
--   values      : Table of { key = "Display Text" }
--   order       : Optional array of keys for display order
--   get         : Function returning current key
--   set         : Function(newKey) to save value
--   syncCooldown: Optional cooldown for sync lock
--------------------------------------------------------------------------------

function Builder:AddDualSelector(options)
    local scrollContent = self._scrollContent
    if not scrollContent then return self end

    local dualSelector = Controls:CreateDualSelector({
        parent = scrollContent,
        label = options.label,
        description = options.description,
        selectorA = options.selectorA,
        selectorB = options.selectorB,
        useLightDim = self._useLightDim,
        disabled = options.disabled,
        isDisabled = options.isDisabled,
        name = options.name,
        maxContainerWidth = options.maxContainerWidth,
    })

    self:_PlaceRow(dualSelector, options)

    return self
end

--------------------------------------------------------------------------------
-- AddSelectorToggleRow: Selector + Toggle compact row
--------------------------------------------------------------------------------
-- Options:
--   label       : Setting label text (left side, optional)
--   description : Optional description below label
--   selector    : Table with selector options (values, order, get, set)
--   toggle      : Table with toggle options (get, set, label)
--   key         : Optional unique key for dynamic updates
--   disabled    : Function returning disabled state (optional)
--------------------------------------------------------------------------------

function Builder:AddSelectorToggleRow(options)
    local scrollContent = self._scrollContent
    if not scrollContent then return self end

    if self:_ScanRecord("selector toggle", options.label, options.description) then return self end

    local selectorToggle = Controls:CreateSelectorToggleRow({
        parent = scrollContent,
        label = options.label,
        description = options.description,
        selector = options.selector,
        toggle = options.toggle,
        useLightDim = self._useLightDim,
        disabled = options.disabled,
        isDisabled = options.isDisabled,
        name = options.name,
    })

    self:_PlaceRow(selectorToggle, options)

    return self
end

--------------------------------------------------------------------------------
-- AddToggleSliderRow: Toggle + Slider compact row
--------------------------------------------------------------------------------
-- Options:
--   label       : Row label text
--   description : Optional description below label
--   toggle      : Table with toggle options (get, set, label)
--   slider      : Table with slider options (get, set, min, max, step, suffix, label)
--   disabled / isDisabled : Function returning disabled state
--   key         : Optional unique key for dynamic updates
--------------------------------------------------------------------------------

function Builder:AddToggleSliderRow(options)
    local scrollContent = self._scrollContent
    if not scrollContent then return self end

    if self:_ScanRecord("toggle slider", options.label, options.description) then return self end

    local toggleSlider = Controls:CreateToggleSliderRow({
        parent = scrollContent,
        label = options.label,
        description = options.description,
        toggle = options.toggle,
        slider = options.slider,
        useLightDim = self._useLightDim,
        disabled = options.disabled,
        isDisabled = options.isDisabled,
        name = options.name,
    })

    self:_PlaceRow(toggleSlider, options)

    return self
end

--------------------------------------------------------------------------------
-- AddMultiToggleRow: Several compact toggles in one row
--------------------------------------------------------------------------------
-- Options:
--   label       : Row label text
--   description : Optional explainer below the label
--   toggles     : Array of { key, label, get, set }
--   disabled / isDisabled : Function returning disabled state
--   key         : Optional unique key for dynamic updates
--------------------------------------------------------------------------------

function Builder:AddMultiToggleRow(options)
    local scrollContent = self._scrollContent
    if not scrollContent then return self end

    if Builder._scanMode and options.label then
        -- Fold the per-toggle labels into the indexed text so searching for an
        -- individual toggle still surfaces the row that holds it.
        local searchText = options.description or ""
        if type(options.toggles) == "table" then
            local names = {}
            for _, def in ipairs(options.toggles) do
                if def.label and def.label ~= "" then
                    table.insert(names, def.label)
                end
            end
            if #names > 0 then
                searchText = searchText .. " " .. table.concat(names, " ")
            end
        end

        self:_ScanRecord("multi toggle", options.label, searchText)
        return self
    end

    local multiToggle = Controls:CreateMultiToggleRow({
        parent = scrollContent,
        label = options.label,
        description = options.description,
        toggles = options.toggles,
        useLightDim = self._useLightDim,
        disabled = options.disabled,
        isDisabled = options.isDisabled,
        name = options.name,
    })

    self:_PlaceRow(multiToggle, options)

    return self
end

--------------------------------------------------------------------------------
-- AddDualBarStyleRow: Texture + Color compact row
--------------------------------------------------------------------------------
-- Options:
--   label              : Row label text (e.g. "Foreground", "Background")
--   description        : Optional description below label
--   getTexture / setTexture : Texture get/set callbacks
--   colorValues / colorOrder / colorInfoIcons : Color selector options
--   getColorMode / setColorMode : Color mode get/set callbacks
--   getColor / setColor : Custom color get/set callbacks
--   customColorValue   : Key that triggers swatch (default "custom")
--   hasAlpha           : Whether color picker supports alpha
--   disabled / isDisabled : Function returning disabled state
--   key                : Optional unique key for dynamic updates
--------------------------------------------------------------------------------

function Builder:AddDualBarStyleRow(options)
    local scrollContent = self._scrollContent
    if not scrollContent then return self end

    if self:_ScanRecord("bar style", options.label, options.description) then return self end

    local dualBarStyle = Controls:CreateDualBarStyleRow({
        parent = scrollContent,
        label = options.label,
        description = options.description,
        getTexture = options.getTexture,
        setTexture = options.setTexture,
        colorValues = options.colorValues,
        colorOrder = options.colorOrder,
        colorInfoIcons = options.colorInfoIcons,
        getColorMode = options.getColorMode,
        setColorMode = options.setColorMode,
        getColor = options.getColor,
        setColor = options.setColor,
        customColorValue = options.customColorValue,
        hasAlpha = options.hasAlpha,
        useLightDim = self._useLightDim,
        disabled = options.disabled,
        isDisabled = options.isDisabled,
        name = options.name,
    })

    self:_PlaceRow(dualBarStyle, options)

    return self
end

--------------------------------------------------------------------------------
-- AddTextInput: Add a single-line text input
--------------------------------------------------------------------------------
-- Options:
--   label       : Setting label text
--   description : Optional description below label
--   get         : Function returning current text string
--   set         : Function(newText) to save text
--   placeholder : Optional placeholder text
--   maxLetters  : Max character count (0 = unlimited)
--   key         : Optional unique key for dynamic updates
--------------------------------------------------------------------------------

function Builder:AddTextInput(options)
    local scrollContent = self._scrollContent
    if not scrollContent then return self end

    local textInput = Controls:CreateSingleLineEditBox({
        parent = scrollContent,
        label = options.label,
        placeholder = options.placeholder,
        maxLetters = options.maxLetters,
        text = options.get and options.get() or "",
        width = scrollContent:GetWidth() - (CONTENT_PADDING * 2),
    })

    if textInput then
        self:_PlaceRow(textInput, options)

        -- Wire up set callback
        textInput:SetOnChange(function(text)
            if options.set then
                options.set(text)
            end
        end)

        -- Add description if provided
        if options.description then
            self._currentY = self._currentY - 4
            local descFS = scrollContent:CreateFontString(nil, "OVERLAY")
            local fontPath = Theme:GetFont("VALUE")
            descFS:SetFont(fontPath, 11, "")
            descFS:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", CONTENT_PADDING + 2, self._currentY)
            descFS:SetPoint("TOPRIGHT", scrollContent, "TOPRIGHT", -CONTENT_PADDING, self._currentY)
            descFS:SetText(options.description)
            descFS:SetJustifyH("LEFT")
            descFS:SetWordWrap(true)
            if self._useLightDim then
                descFS:SetTextColor(0.55, 0.55, 0.55, 1)
            else
                local dimR, dimG, dimB = Theme:GetDimTextColor()
                descFS:SetTextColor(dimR, dimG, dimB, 1)
            end
            table.insert(self._controls, descFS)
            self._currentY = self._currentY - (descFS:GetStringHeight() or 14)
        end
    end

    return self
end

--------------------------------------------------------------------------------
-- AddMultiLineEditBox: Add a multi-line text input
--------------------------------------------------------------------------------
-- Options:
--   label       : Setting label text
--   get         : Function returning current text string
--   set         : Function(newText) to save text
--   placeholder : Optional placeholder text
--   height      : Edit box height (default 120)
--   key         : Optional unique key for dynamic updates
--------------------------------------------------------------------------------

function Builder:AddMultiLineEditBox(options)
    local scrollContent = self._scrollContent
    if not scrollContent then return self end

    local editBox = Controls:CreateMultiLineEditBox({
        parent = scrollContent,
        label = options.label,
        placeholder = options.placeholder,
        height = options.height or 120,
        text = options.get and options.get() or "",
        width = scrollContent:GetWidth() - (CONTENT_PADDING * 2),
    })

    if editBox then
        self:_PlaceRow(editBox, options)

        -- Wire up change detection on focus loss
        local innerEditBox = editBox._editBox
        if innerEditBox and options.set then
            innerEditBox:HookScript("OnEditFocusLost", function(self)
                options.set(self:GetText())
            end)
        end
    end

    return self
end

--------------------------------------------------------------------------------
-- AddPreview: Inline preview row for Custom Groups / ScootAuras
--------------------------------------------------------------------------------

function Builder:AddPreview(options)
    local scrollContent = self._scrollContent
    if not scrollContent then return self end

    local preview = Controls:CreatePreview({
        parent = scrollContent,
        componentId = options.componentId,
        mode = options.mode,
        settingKeys = options.settingKeys,
        iconTexture = options.iconTexture,
        auraDefaultBarColor = options.auraDefaultBarColor,
        caTextSource = options.caTextSource,
        caTextLiteral = options.caTextLiteral,
        previewNameLabel = options.previewNameLabel,
        useLightDim = self._useLightDim,
        rowHeight = options.rowHeight,
        previewScale = options.previewScale,
        maxRowHeight = options.maxRowHeight,
        borderPath = options.borderPath,
        getSetting = options.getSetting,
        getSubSetting = options.getSubSetting,
        shapeAtlas = options.shapeAtlas,
        shapeColor = options.shapeColor,
        shapeDrain = options.shapeDrain,
        noBottomBorder = options.noBottomBorder,
        noHover = options.noHover,
        noLabel = options.noLabel,
        timerEpoch = options.timerEpoch,
    })

    self:_PlaceRow(preview, options)

    return self
end
