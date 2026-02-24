-- SettingsBuilder.lua - Declarative layout system for UI settings
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.SettingsBuilder = {}
local Builder = addon.UI.SettingsBuilder
local Theme = addon.UI.Theme
local Controls = addon.UI.Controls

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

local SECTION_HEADER_HEIGHT = 32
local SECTION_SPACING = 16          -- Space before a section header
local ITEM_SPACING = 12             -- Space between controls
local CONTENT_PADDING = 8           -- Padding from edges
local FIRST_ITEM_OFFSET = 8         -- Initial offset from top

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

    -- Create section header frame
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

    -- Update Y position
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

    -- Add item spacing (more for emphasized toggles)
    if #self._controls > 0 then
        local spacing = options.emphasized and (ITEM_SPACING + 4) or ITEM_SPACING
        self._currentY = self._currentY - spacing
    end

    -- Create toggle using Controls module
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

    if toggle then
        -- Position the toggle
        toggle:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", CONTENT_PADDING, self._currentY)
        toggle:SetPoint("TOPRIGHT", scrollContent, "TOPRIGHT", -CONTENT_PADDING, self._currentY)

        -- Track for cleanup
        table.insert(self._controls, toggle)

        -- Register by key for dynamic updates
        if options.key then
            self._controlsByKey[options.key] = toggle
        end

        -- Update Y position
        self._currentY = self._currentY - toggle:GetHeight()
    end

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

    -- Add spacing
    if #self._controls > 0 or #self._sections > 0 then
        self._currentY = self._currentY - ITEM_SPACING
    end

    -- Create description frame
    local frame = CreateFrame("Frame", nil, scrollContent)
    frame:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", CONTENT_PADDING, self._currentY)
    frame:SetPoint("TOPRIGHT", scrollContent, "TOPRIGHT", -CONTENT_PADDING, self._currentY)

    local descFS = frame:CreateFontString(nil, "OVERLAY")
    local fontPath = Theme:GetFont("VALUE")
    descFS:SetFont(fontPath, 12, "")
    descFS:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    descFS:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    descFS:SetText(text or "")
    descFS:SetJustifyH("LEFT")
    descFS:SetWordWrap(true)

    -- Color (use lighter dim for collapsible section interiors)
    if options.dim ~= false then
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

    -- Update Y position
    self._currentY = self._currentY - frame:GetHeight()

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

    -- Add spacing before label
    if #self._controls > 0 or #self._sections > 0 then
        self._currentY = self._currentY - ITEM_SPACING
    end

    -- Create label frame
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

    -- Update Y position
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

    -- Add spacing before section
    if #self._controls > 0 or #self._sections > 0 then
        self._currentY = self._currentY - ITEM_SPACING
    end

    -- Store reference to onRefresh callback if set
    local onRefresh = self._onRefresh

    -- Create the collapsible section control
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

    -- Position the section
    section:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", CONTENT_PADDING, self._currentY)
    section:SetPoint("TOPRIGHT", scrollContent, "TOPRIGHT", -CONTENT_PADDING, self._currentY)

    -- Track for cleanup
    table.insert(self._controls, section)

    -- Build content using an inner builder
    if options.buildContent then
        local contentFrame = section:GetContentFrame()

        -- Create inner builder for the content area
        local innerBuilder = Builder:CreateFor(contentFrame)
        innerBuilder._useLightDim = true  -- Use lighter description text on gray background
        innerBuilder._parentCollapsible = section  -- Reference for dynamic height updates

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
-- This allows the renderer to re-render the page when layout changes.
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
--------------------------------------------------------------------------------

function Builder:AddSelector(options)
    local scrollContent = self._scrollContent
    if not scrollContent then return self end

    -- Add item spacing (more for emphasized selectors)
    if #self._controls > 0 then
        local spacing = options.emphasized and (ITEM_SPACING + 4) or ITEM_SPACING
        self._currentY = self._currentY - spacing
    end

    -- Create selector using Controls module
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
        disabled = options.disabled,
        isDisabled = options.isDisabled,
        optionInfoIcons = options.optionInfoIcons,
    })

    if selector then
        -- Position the selector
        selector:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", CONTENT_PADDING, self._currentY)
        selector:SetPoint("TOPRIGHT", scrollContent, "TOPRIGHT", -CONTENT_PADDING, self._currentY)

        -- Track for cleanup
        table.insert(self._controls, selector)

        -- Register by key for dynamic updates
        if options.key then
            self._controlsByKey[options.key] = selector
        end

        -- Add info icon if specified
        if options.infoIcon and options.infoIcon.tooltipText and selector._label then
            local iconSize = options.infoIcon.size or 12
            local infoIcon = Controls:CreateInfoIcon({
                parent = selector,
                tooltipText = options.infoIcon.tooltipText,
                tooltipTitle = options.infoIcon.tooltipTitle,
                size = iconSize,
            })
            if infoIcon then
                infoIcon:SetPoint("LEFT", selector._label, "RIGHT", 4, 4)
                selector._infoIcon = infoIcon
                table.insert(self._controls, infoIcon)
            end
        end

        -- Update Y position
        self._currentY = self._currentY - selector:GetHeight()
    end

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

    -- Add item spacing
    if #self._controls > 0 then
        self._currentY = self._currentY - ITEM_SPACING
    end

    -- Create slider using Controls module
    local slider = Controls:CreateSlider({
        parent = scrollContent,
        label = options.label,
        description = options.description,
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

    if slider then
        -- Position the slider
        slider:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", CONTENT_PADDING, self._currentY)
        slider:SetPoint("TOPRIGHT", scrollContent, "TOPRIGHT", -CONTENT_PADDING, self._currentY)

        -- Track for cleanup
        table.insert(self._controls, slider)

        -- Register by key for dynamic updates
        if options.key then
            self._controlsByKey[options.key] = slider
        end

        -- Add info icon if specified (positioned at top-right corner of label)
        if options.infoIcon and options.infoIcon.tooltipText and slider._label then
            local iconSize = options.infoIcon.size or 12  -- Slightly smaller for corner position
            local infoIcon = Controls:CreateInfoIcon({
                parent = slider,
                tooltipText = options.infoIcon.tooltipText,
                tooltipTitle = options.infoIcon.tooltipTitle,
                size = iconSize,
            })
            if infoIcon then
                -- Position icon at top-right corner of the label text
                -- Offset up (positive Y) to align with top of text
                infoIcon:SetPoint("LEFT", slider._label, "RIGHT", 4, 4)

                slider._infoIcon = infoIcon
                table.insert(self._controls, infoIcon)
            end
        end

        -- Update Y position
        self._currentY = self._currentY - slider:GetHeight()
    end

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

    -- Add item spacing
    if #self._controls > 0 then
        self._currentY = self._currentY - ITEM_SPACING
    end

    -- Create font selector using Controls module
    local fontSelector = Controls:CreateFontSelector({
        parent = scrollContent,
        label = options.label,
        description = options.description,
        get = options.get,
        set = options.set,
        width = options.width,
        useLightDim = self._useLightDim,
    })

    if fontSelector then
        -- Position the font selector
        fontSelector:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", CONTENT_PADDING, self._currentY)
        fontSelector:SetPoint("TOPRIGHT", scrollContent, "TOPRIGHT", -CONTENT_PADDING, self._currentY)

        -- Track for cleanup
        table.insert(self._controls, fontSelector)

        -- Register by key for dynamic updates
        if options.key then
            self._controlsByKey[options.key] = fontSelector
        end

        -- Update Y position
        self._currentY = self._currentY - fontSelector:GetHeight()
    end

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

    -- Add item spacing
    if #self._controls > 0 then
        self._currentY = self._currentY - ITEM_SPACING
    end

    -- Create bar texture selector using Controls module
    local barTextureSelector = Controls:CreateBarTextureSelector({
        parent = scrollContent,
        label = options.label,
        description = options.description,
        get = options.get,
        set = options.set,
        width = options.width,
        useLightDim = self._useLightDim,
    })

    if barTextureSelector then
        -- Position the bar texture selector
        barTextureSelector:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", CONTENT_PADDING, self._currentY)
        barTextureSelector:SetPoint("TOPRIGHT", scrollContent, "TOPRIGHT", -CONTENT_PADDING, self._currentY)

        -- Track for cleanup
        table.insert(self._controls, barTextureSelector)

        -- Register by key for dynamic updates
        if options.key then
            self._controlsByKey[options.key] = barTextureSelector
        end

        -- Update Y position
        self._currentY = self._currentY - barTextureSelector:GetHeight()
    end

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

    -- Add item spacing
    if #self._controls > 0 then
        self._currentY = self._currentY - ITEM_SPACING
    end

    -- Create bar border selector using Controls module
    local barBorderSelector = Controls:CreateBarBorderSelector({
        parent = scrollContent,
        label = options.label,
        description = options.description,
        get = options.get,
        set = options.set,
        width = options.width,
        includeNone = options.includeNone,
        useLightDim = self._useLightDim,
    })

    if barBorderSelector then
        -- Position the bar border selector
        barBorderSelector:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", CONTENT_PADDING, self._currentY)
        barBorderSelector:SetPoint("TOPRIGHT", scrollContent, "TOPRIGHT", -CONTENT_PADDING, self._currentY)

        -- Track for cleanup
        table.insert(self._controls, barBorderSelector)

        -- Register by key for dynamic updates
        if options.key then
            self._controlsByKey[options.key] = barBorderSelector
        end

        -- Update Y position
        self._currentY = self._currentY - barBorderSelector:GetHeight()
    end

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
--------------------------------------------------------------------------------

function Builder:AddTabbedSection(options)
    local scrollContent = self._scrollContent
    if not scrollContent then return self end

    if not options.tabs or #options.tabs == 0 or not options.componentId or not options.sectionKey then
        return self
    end

    -- Add spacing before section
    if #self._controls > 0 or #self._sections > 0 then
        self._currentY = self._currentY - ITEM_SPACING
    end

    -- Store reference to onRefresh callback if set
    local onRefresh = self._onRefresh

    -- Reference to parent collapsible (if nested inside one)
    local parentCollapsible = self._parentCollapsible

    -- Create the tabbed section control
    local section = Controls:CreateTabbedSection({
        parent = scrollContent,
        tabs = options.tabs,
        componentId = options.componentId,
        sectionKey = options.sectionKey,
        defaultTab = options.defaultTab,
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

    -- Position the section
    section:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", CONTENT_PADDING, self._currentY)
    section:SetPoint("TOPRIGHT", scrollContent, "TOPRIGHT", -CONTENT_PADDING, self._currentY)

    -- Track for cleanup
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

                    -- Call the build function
                    buildFunc(contentFrame, innerBuilder)

                    -- Get the content height from the inner builder
                    local contentHeight = innerBuilder:GetHeight()

                    -- Set this tab's content height
                    section:SetTabContentHeight(tabKey, contentHeight)

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

    return self
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

    -- Add item spacing
    if #self._controls > 0 then
        self._currentY = self._currentY - ITEM_SPACING
    end

    -- Create color picker using Controls module
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

    if colorPicker then
        -- Position the color picker
        colorPicker:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", CONTENT_PADDING, self._currentY)
        colorPicker:SetPoint("TOPRIGHT", scrollContent, "TOPRIGHT", -CONTENT_PADDING, self._currentY)

        -- Track for cleanup
        table.insert(self._controls, colorPicker)

        -- Register by key for dynamic updates
        if options.key then
            self._controlsByKey[options.key] = colorPicker
        end

        -- Update Y position
        self._currentY = self._currentY - colorPicker:GetHeight()
    end

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

    -- Add item spacing
    if #self._controls > 0 then
        self._currentY = self._currentY - ITEM_SPACING
    end

    -- Create toggle color picker using Controls module
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

    if toggleColor then
        -- Position the control
        toggleColor:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", CONTENT_PADDING, self._currentY)
        toggleColor:SetPoint("TOPRIGHT", scrollContent, "TOPRIGHT", -CONTENT_PADDING, self._currentY)

        -- Track for cleanup
        table.insert(self._controls, toggleColor)

        -- Register by key for dynamic updates
        if options.key then
            self._controlsByKey[options.key] = toggleColor
        end

        -- Update Y position
        self._currentY = self._currentY - toggleColor:GetHeight()
    end

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

    -- Add item spacing
    if #self._controls > 0 then
        self._currentY = self._currentY - ITEM_SPACING
    end

    -- Create selector color picker using Controls module
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

    if selectorColor then
        -- Position the control
        selectorColor:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", CONTENT_PADDING, self._currentY)
        selectorColor:SetPoint("TOPRIGHT", scrollContent, "TOPRIGHT", -CONTENT_PADDING, self._currentY)

        -- Track for cleanup
        table.insert(self._controls, selectorColor)

        -- Register by key for dynamic updates
        if options.key then
            self._controlsByKey[options.key] = selectorColor
        end

        -- Update Y position
        self._currentY = self._currentY - selectorColor:GetHeight()
    end

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

    -- Add item spacing
    if #self._controls > 0 then
        self._currentY = self._currentY - ITEM_SPACING
    end

    -- Create dual slider using Controls module
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

    if dualSlider then
        -- Position the dual slider
        dualSlider:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", CONTENT_PADDING, self._currentY)
        dualSlider:SetPoint("TOPRIGHT", scrollContent, "TOPRIGHT", -CONTENT_PADDING, self._currentY)

        -- Track for cleanup
        table.insert(self._controls, dualSlider)

        -- Register by key for dynamic updates
        if options.key then
            self._controlsByKey[options.key] = dualSlider
        end

        -- Update Y position
        self._currentY = self._currentY - dualSlider:GetHeight()
    end

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

    -- Add item spacing
    if #self._controls > 0 then
        self._currentY = self._currentY - ITEM_SPACING
    end

    -- Create dual selector using Controls module
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

    if dualSelector then
        -- Position the dual selector
        dualSelector:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", CONTENT_PADDING, self._currentY)
        dualSelector:SetPoint("TOPRIGHT", scrollContent, "TOPRIGHT", -CONTENT_PADDING, self._currentY)

        -- Track for cleanup
        table.insert(self._controls, dualSelector)

        -- Register by key for dynamic updates
        if options.key then
            self._controlsByKey[options.key] = dualSelector
        end

        -- Update Y position
        self._currentY = self._currentY - dualSelector:GetHeight()
    end

    return self
end

--------------------------------------------------------------------------------
-- Future Control Methods (stubs)
--------------------------------------------------------------------------------

-- AddTextInput: For string entry
-- function Builder:AddTextInput(options) ... end

-- AddButton: For action buttons
-- function Builder:AddButton(options) ... end
