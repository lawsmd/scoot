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

-- Layout numbers come from the active skin: sectionHeaderHeight and the
-- metrics.collapsible table.
local function M()
    return Controls.Metrics()
end

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
    local totalHeight = expanded and (M().sectionHeaderHeight + contentHeight + M().collapsible.borderWidth) or M().sectionHeaderHeight

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
    header:SetHeight(M().sectionHeaderHeight)
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
    topBorder:SetHeight(M().collapsible.borderWidth)
    topBorder:SetColorTexture(ar, ag, ab, M().collapsible.borderAlpha)
    header._borders.TOP = topBorder

    -- LEFT border (extends down when expanded)
    local leftBorder = header:CreateTexture(nil, "BORDER", nil, -1)
    leftBorder:SetPoint("TOPLEFT", header, "TOPLEFT", 0, -M().collapsible.borderWidth)
    leftBorder:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, 0)
    leftBorder:SetWidth(M().collapsible.borderWidth)
    leftBorder:SetColorTexture(ar, ag, ab, M().collapsible.borderAlpha)
    header._borders.LEFT = leftBorder

    -- RIGHT border
    local rightBorder = header:CreateTexture(nil, "BORDER", nil, -1)
    rightBorder:SetPoint("TOPRIGHT", header, "TOPRIGHT", 0, -M().collapsible.borderWidth)
    rightBorder:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, 0)
    rightBorder:SetWidth(M().collapsible.borderWidth)
    rightBorder:SetColorTexture(ar, ag, ab, M().collapsible.borderAlpha)
    header._borders.RIGHT = rightBorder

    -- BOTTOM border (only shown when collapsed)
    local bottomBorder = header:CreateTexture(nil, "BORDER", nil, -1)
    bottomBorder:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, 0)
    bottomBorder:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, 0)
    bottomBorder:SetHeight(M().collapsible.borderWidth)
    bottomBorder:SetColorTexture(ar, ag, ab, M().collapsible.borderAlpha)
    header._borders.BOTTOM = bottomBorder

    -- Indicator (▼/▶)
    local indicator = header:CreateFontString(nil, "OVERLAY")
    theme:ApplyFont(indicator, "label", M().collapsible.indicatorSize)
    indicator:SetPoint("LEFT", header, "LEFT", M().collapsible.contentPadding, 0)
    indicator:SetText(expanded and CHAR_EXPANDED or CHAR_COLLAPSED)
    indicator:SetTextColor(ar, ag, ab, 1)
    header._indicator = indicator

    -- Title text (white, not accent-colored)
    local titleFS = header:CreateFontString(nil, "OVERLAY")
    theme:ApplyFont(titleFS, "header", M().collapsible.titleSize)
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
    content:SetPoint("TOPLEFT", header, "BOTTOMLEFT", M().collapsible.borderWidth, 0)
    content:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", -M().collapsible.borderWidth, 0)
    content:SetHeight(contentHeight)
    -- Total horizontal inset of the content frame against the section, read
    -- by the builder to pass the reduced width into the inner builder.
    section._contentInset = M().collapsible.borderWidth * 2

    -- Content left border
    local contentLeftBorder = section:CreateTexture(nil, "BORDER", nil, -1)
    contentLeftBorder:SetPoint("TOPLEFT", content, "TOPLEFT", -M().collapsible.borderWidth, 0)
    contentLeftBorder:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", -M().collapsible.borderWidth, 0)
    contentLeftBorder:SetWidth(M().collapsible.borderWidth)
    contentLeftBorder:SetColorTexture(ar, ag, ab, M().collapsible.borderAlpha)
    content._leftBorder = contentLeftBorder

    -- Content right border
    local contentRightBorder = section:CreateTexture(nil, "BORDER", nil, -1)
    contentRightBorder:SetPoint("TOPRIGHT", content, "TOPRIGHT", M().collapsible.borderWidth, 0)
    contentRightBorder:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", M().collapsible.borderWidth, 0)
    contentRightBorder:SetWidth(M().collapsible.borderWidth)
    contentRightBorder:SetColorTexture(ar, ag, ab, M().collapsible.borderAlpha)
    content._rightBorder = contentRightBorder

    -- Content background (matching header gray for visual consistency)
    content._bg = Controls.AddBackground(content, { color = "collapsible" })

    section._content = content

    ----------------------------------------------------------------------------
    -- Footer (bottom border when expanded)
    ----------------------------------------------------------------------------
    local footer = CreateFrame("Frame", nil, section)
    footer:SetPoint("TOPLEFT", content, "BOTTOMLEFT", -M().collapsible.borderWidth, 0)
    footer:SetPoint("TOPRIGHT", content, "BOTTOMRIGHT", M().collapsible.borderWidth, 0)
    footer:SetHeight(M().collapsible.borderWidth)

    local footerBorder = footer:CreateTexture(nil, "BORDER", nil, -1)
    footerBorder:SetAllPoints()
    footerBorder:SetColorTexture(ar, ag, ab, M().collapsible.borderAlpha)
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
            section:SetHeight(M().sectionHeaderHeight + section._contentHeight + M().collapsible.borderWidth)
        else
            -- Collapsed: hide content, show header bottom border
            content:Hide()
            content._leftBorder:Hide()
            content._rightBorder:Hide()
            footer:Hide()
            header._borders.BOTTOM:Show()
            header._indicator:SetText(CHAR_COLLAPSED)
            section:SetHeight(M().sectionHeaderHeight)
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
            return M().sectionHeaderHeight + self._contentHeight + M().collapsible.borderWidth
        else
            return M().sectionHeaderHeight
        end
    end

    function section:SetContentHeight(height)
        self._contentHeight = height
        self._content:SetHeight(height)
        if self._expanded then
            self:SetHeight(M().sectionHeaderHeight + height + M().collapsible.borderWidth)
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
