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
