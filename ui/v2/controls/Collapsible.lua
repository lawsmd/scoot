-- Collapsible.lua - Expandable/collapsible section with boxed border
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

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

local COLLAPSIBLE_HEADER_HEIGHT = 32
local COLLAPSIBLE_BORDER_WIDTH = 1
local COLLAPSIBLE_CONTENT_PADDING = 12
local COLLAPSIBLE_BORDER_ALPHA = 0.6  -- Dimmed border
local COLLAPSIBLE_INDICATOR_WIDTH = 24
local COLLAPSIBLE_CORNER_INSET = 8  -- Visual space for corner decoration

local CHAR_EXPANDED = "▼"
local CHAR_COLLAPSED = "▶"

--------------------------------------------------------------------------------
-- Session-only state storage
--------------------------------------------------------------------------------

addon.UI._sectionStates = addon.UI._sectionStates or {}

local function GetSectionState(componentId, sectionKey, defaultVal)
    addon.UI._sectionStates[componentId] = addon.UI._sectionStates[componentId] or {}
    local state = addon.UI._sectionStates[componentId][sectionKey]
    if state == nil then
        return defaultVal or false
    end
    return state
end

local function SetSectionState(componentId, sectionKey, expanded)
    addon.UI._sectionStates[componentId] = addon.UI._sectionStates[componentId] or {}
    addon.UI._sectionStates[componentId][sectionKey] = expanded
end

--------------------------------------------------------------------------------
-- CollapsibleSection: Expandable/collapsible section with boxed border
--------------------------------------------------------------------------------
-- Creates a collapsible section with:
--   - Clickable header row with expand/collapse indicator (▼/▶)
--   - Boxed border when expanded (full box with corners)
--   - Single-line border when collapsed (with end caps)
--   - Content container for child controls
--
-- Options table:
--   title         : Section title text (string, required)
--   componentId   : Component identifier for state key (string, required)
--   sectionKey    : Unique key within component (string, required)
--   defaultExpanded : Initial expanded state (boolean, default false)
--   contentHeight : Fixed content area height (number, optional)
--   parent        : Parent frame (required)
--   name          : Global frame name (optional)
--   onToggle      : Callback when expanded state changes (optional)
--   infoIcon      : Optional { tooltipTitle, tooltipText } for header info icon
--------------------------------------------------------------------------------

function Controls:CreateCollapsibleSection(options)
    local theme = GetTheme()
    if not options or not options.parent then
        return nil
    end

    local parent = options.parent
    local title = options.title or "Section"
    local componentId = options.componentId or "unknown"
    local sectionKey = options.sectionKey or "default"
    local defaultExpanded = options.defaultExpanded or false
    local contentHeight = options.contentHeight or 100
    local name = options.name
    local onToggle = options.onToggle

    -- Get initial state from session storage
    local expanded = GetSectionState(componentId, sectionKey, defaultExpanded)

    -- Get theme colors
    local ar, ag, ab = theme:GetAccentColor()
    local bgR, bgG, bgB, bgA = theme:GetBackgroundSolidColor()
    local dimR, dimG, dimB = theme:GetDimTextColor()

    -- Calculate total height
    local totalHeight = expanded and (COLLAPSIBLE_HEADER_HEIGHT + contentHeight + COLLAPSIBLE_BORDER_WIDTH) or COLLAPSIBLE_HEADER_HEIGHT

    -- Main container frame
    local section = CreateFrame("Frame", name, parent)
    section:SetHeight(totalHeight)

    -- Store state
    section._expanded = expanded
    section._contentHeight = contentHeight
    section._componentId = componentId
    section._sectionKey = sectionKey

    ----------------------------------------------------------------------------
    -- Header row (always visible, clickable)
    ----------------------------------------------------------------------------
    local header = CreateFrame("Button", nil, section)
    header:SetPoint("TOPLEFT", section, "TOPLEFT", 0, 0)
    header:SetPoint("TOPRIGHT", section, "TOPRIGHT", 0, 0)
    header:SetHeight(COLLAPSIBLE_HEADER_HEIGHT)
    header:RegisterForClicks("AnyUp")

    -- Solid gray background (always visible for visual distinction)
    header._solidBg = Controls.AddBackground(header, { color = "collapsible" })

    -- Hover background (on top of solid bg)
    header._hoverBg = Controls.AddHoverFill(header)

    -- Header border textures (stored for updating)
    header._borders = {}

    -- TOP border
    local topBorder = header:CreateTexture(nil, "BORDER", nil, -1)
    topBorder:SetPoint("TOPLEFT", header, "TOPLEFT", 0, 0)
    topBorder:SetPoint("TOPRIGHT", header, "TOPRIGHT", 0, 0)
    topBorder:SetHeight(COLLAPSIBLE_BORDER_WIDTH)
    topBorder:SetColorTexture(ar, ag, ab, COLLAPSIBLE_BORDER_ALPHA)
    header._borders.TOP = topBorder

    -- LEFT border (extends down when expanded)
    local leftBorder = header:CreateTexture(nil, "BORDER", nil, -1)
    leftBorder:SetPoint("TOPLEFT", header, "TOPLEFT", 0, -COLLAPSIBLE_BORDER_WIDTH)
    leftBorder:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, 0)
    leftBorder:SetWidth(COLLAPSIBLE_BORDER_WIDTH)
    leftBorder:SetColorTexture(ar, ag, ab, COLLAPSIBLE_BORDER_ALPHA)
    header._borders.LEFT = leftBorder

    -- RIGHT border
    local rightBorder = header:CreateTexture(nil, "BORDER", nil, -1)
    rightBorder:SetPoint("TOPRIGHT", header, "TOPRIGHT", 0, -COLLAPSIBLE_BORDER_WIDTH)
    rightBorder:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, 0)
    rightBorder:SetWidth(COLLAPSIBLE_BORDER_WIDTH)
    rightBorder:SetColorTexture(ar, ag, ab, COLLAPSIBLE_BORDER_ALPHA)
    header._borders.RIGHT = rightBorder

    -- BOTTOM border (only shown when collapsed)
    local bottomBorder = header:CreateTexture(nil, "BORDER", nil, -1)
    bottomBorder:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, 0)
    bottomBorder:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, 0)
    bottomBorder:SetHeight(COLLAPSIBLE_BORDER_WIDTH)
    bottomBorder:SetColorTexture(ar, ag, ab, COLLAPSIBLE_BORDER_ALPHA)
    header._borders.BOTTOM = bottomBorder

    -- Indicator (▼/▶)
    local indicator = header:CreateFontString(nil, "OVERLAY")
    local indicatorFont = theme:GetFont("LABEL")
    indicator:SetFont(indicatorFont, 14, "")
    indicator:SetPoint("LEFT", header, "LEFT", COLLAPSIBLE_CONTENT_PADDING, 0)
    indicator:SetText(expanded and CHAR_EXPANDED or CHAR_COLLAPSED)
    indicator:SetTextColor(ar, ag, ab, 1)
    header._indicator = indicator

    -- Title text (white, not accent-colored)
    local titleFS = header:CreateFontString(nil, "OVERLAY")
    local titleFont = theme:GetFont("HEADER")
    titleFS:SetFont(titleFont, 16, "")
    titleFS:SetPoint("LEFT", indicator, "RIGHT", 6, 0)
    titleFS:SetText(title)
    titleFS:SetTextColor(1, 1, 1, 1)
    header._title = titleFS

    -- Optional info icon (positioned after title text)
    local infoSpec = Controls.InfoIconOptions(options.infoIcon)
    if infoSpec then
        local infoIcon = Controls:CreateInfoIcon({
            parent = header,
            tooltipTitle = infoSpec.tooltipTitle,
            tooltipText = infoSpec.tooltipText,
            size = 14,
        })
        if infoIcon then
            -- Position to the right of the title with a small gap
            infoIcon:SetPoint("LEFT", titleFS, "RIGHT", 6, 0)
            section._infoIcon = infoIcon
        end
    end

    section._header = header

    ----------------------------------------------------------------------------
    -- Content container (visible when expanded)
    ----------------------------------------------------------------------------
    local content = CreateFrame("Frame", nil, section)
    content:SetPoint("TOPLEFT", header, "BOTTOMLEFT", COLLAPSIBLE_BORDER_WIDTH, 0)
    content:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", -COLLAPSIBLE_BORDER_WIDTH, 0)
    content:SetHeight(contentHeight)

    -- Content left border
    local contentLeftBorder = section:CreateTexture(nil, "BORDER", nil, -1)
    contentLeftBorder:SetPoint("TOPLEFT", content, "TOPLEFT", -COLLAPSIBLE_BORDER_WIDTH, 0)
    contentLeftBorder:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", -COLLAPSIBLE_BORDER_WIDTH, 0)
    contentLeftBorder:SetWidth(COLLAPSIBLE_BORDER_WIDTH)
    contentLeftBorder:SetColorTexture(ar, ag, ab, COLLAPSIBLE_BORDER_ALPHA)
    content._leftBorder = contentLeftBorder

    -- Content right border
    local contentRightBorder = section:CreateTexture(nil, "BORDER", nil, -1)
    contentRightBorder:SetPoint("TOPRIGHT", content, "TOPRIGHT", COLLAPSIBLE_BORDER_WIDTH, 0)
    contentRightBorder:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", COLLAPSIBLE_BORDER_WIDTH, 0)
    contentRightBorder:SetWidth(COLLAPSIBLE_BORDER_WIDTH)
    contentRightBorder:SetColorTexture(ar, ag, ab, COLLAPSIBLE_BORDER_ALPHA)
    content._rightBorder = contentRightBorder

    -- Content background (matching header gray for visual consistency)
    content._bg = Controls.AddBackground(content, { color = "collapsible" })

    section._content = content

    ----------------------------------------------------------------------------
    -- Footer (bottom border when expanded)
    ----------------------------------------------------------------------------
    local footer = CreateFrame("Frame", nil, section)
    footer:SetPoint("TOPLEFT", content, "BOTTOMLEFT", -COLLAPSIBLE_BORDER_WIDTH, 0)
    footer:SetPoint("TOPRIGHT", content, "BOTTOMRIGHT", COLLAPSIBLE_BORDER_WIDTH, 0)
    footer:SetHeight(COLLAPSIBLE_BORDER_WIDTH)

    local footerBorder = footer:CreateTexture(nil, "BORDER", nil, -1)
    footerBorder:SetAllPoints()
    footerBorder:SetColorTexture(ar, ag, ab, COLLAPSIBLE_BORDER_ALPHA)
    footer._border = footerBorder

    section._footer = footer

    ----------------------------------------------------------------------------
    -- Update visual state based on expanded/collapsed
    ----------------------------------------------------------------------------
    local function UpdateExpandedState()
        local isExpanded = section._expanded

        if isExpanded then
            -- Expanded: show content, hide header bottom border
            content:Show()
            content._leftBorder:Show()
            content._rightBorder:Show()
            footer:Show()
            header._borders.BOTTOM:Hide()
            header._indicator:SetText(CHAR_EXPANDED)
            section:SetHeight(COLLAPSIBLE_HEADER_HEIGHT + section._contentHeight + COLLAPSIBLE_BORDER_WIDTH)
        else
            -- Collapsed: hide content, show header bottom border
            content:Hide()
            content._leftBorder:Hide()
            content._rightBorder:Hide()
            footer:Hide()
            header._borders.BOTTOM:Show()
            header._indicator:SetText(CHAR_COLLAPSED)
            section:SetHeight(COLLAPSIBLE_HEADER_HEIGHT)
        end
    end
    section._updateExpandedState = UpdateExpandedState

    -- Initialize visual state
    UpdateExpandedState()

    ----------------------------------------------------------------------------
    -- Header interaction
    ----------------------------------------------------------------------------
    header:SetScript("OnEnter", function(self)
        self._hoverBg:Show()
    end)

    header:SetScript("OnLeave", function(self)
        self._hoverBg:Hide()
    end)

    header:SetScript("OnClick", function(self, mouseButton)
        section._expanded = not section._expanded
        SetSectionState(componentId, sectionKey, section._expanded)
        UpdateExpandedState()
        PlaySound(section._expanded and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)

        if onToggle then
            onToggle(section._expanded)
        end
    end)

    ----------------------------------------------------------------------------
    -- Theme subscription
    ----------------------------------------------------------------------------
    local subscribeKey = "Collapsible_" .. componentId .. "_" .. sectionKey
    section._subscribeKey = subscribeKey

    theme:Subscribe(subscribeKey, function(r, g, b)
        -- Update header borders (dimmed)
        for _, tex in pairs(header._borders) do
            tex:SetColorTexture(r, g, b, 0.6)
        end
        -- Update header elements
        header._indicator:SetTextColor(r, g, b, 1)
        -- Title stays white (not accent)
        -- Update content borders (dimmed)
        content._leftBorder:SetColorTexture(r, g, b, 0.6)
        content._rightBorder:SetColorTexture(r, g, b, 0.6)
        -- Update footer (dimmed)
        footer._border:SetColorTexture(r, g, b, 0.6)
    end)

    ----------------------------------------------------------------------------
    -- Public methods
    ----------------------------------------------------------------------------
    function section:IsExpanded()
        return self._expanded
    end

    function section:SetExpanded(expanded)
        self._expanded = expanded
        SetSectionState(self._componentId, self._sectionKey, expanded)
        self._updateExpandedState()
    end

    function section:Toggle()
        self:SetExpanded(not self._expanded)
    end

    function section:GetContentFrame()
        return self._content
    end

    function section:GetHeight()
        if self._expanded then
            return COLLAPSIBLE_HEADER_HEIGHT + self._contentHeight + COLLAPSIBLE_BORDER_WIDTH
        else
            return COLLAPSIBLE_HEADER_HEIGHT
        end
    end

    function section:SetContentHeight(height)
        self._contentHeight = height
        self._content:SetHeight(height)
        if self._expanded then
            self:SetHeight(COLLAPSIBLE_HEADER_HEIGHT + height + COLLAPSIBLE_BORDER_WIDTH)
        end
    end

    function section:Cleanup()
        if self._subscribeKey then
            theme:Unsubscribe(self._subscribeKey)
        end
        if self._infoIcon and self._infoIcon.Cleanup then
            self._infoIcon:Cleanup()
        end
        if self._innerBuilder then
            self._innerBuilder:Cleanup()
        end
    end

    return section
end
