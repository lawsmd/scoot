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

-- The indicator glyphs come from the sectionHeader role.
local function Glyph(expanded)
    local glyphs = addon.UI.Chrome.Spec("sectionHeader").glyphs or {}
    if expanded then return glyphs.expanded or "\226\150\188" end
    return glyphs.collapsed or "\226\150\182"
end

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
    local override = Controls.SkinOverride("Collapsible", options)
    if override then return override end

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

    -- Background, hover fill and the box edges come from the sectionHeader role
    header._backdrop = addon.UI.Chrome.Backdrop("sectionHeader", header)

    -- Indicator (▼/▶)
    local indicator = header:CreateFontString(nil, "OVERLAY")
    theme:ApplyFont(indicator, "label", M().collapsible.indicatorSize)
    indicator:SetPoint("LEFT", header, "LEFT", M().collapsible.contentPadding, 0)
    indicator:SetText(Glyph(expanded))
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

    -- Background and the box's remaining edges come from the sectionBody role
    content._backdrop = addon.UI.Chrome.Backdrop("sectionBody", content)
    section._content = content
    -- Total horizontal inset of the content frame against the section, read
    -- by the builder to pass the reduced width into the inner builder.
    section._contentInset = content._backdrop.inset * 2

    ----------------------------------------------------------------------------
    -- Update visual state based on expanded/collapsed
    ----------------------------------------------------------------------------
    local function UpdateExpandedState()
        local isExpanded = section._expanded

        header._backdrop:SetOpen(isExpanded)
        header._indicator:SetText(Glyph(isExpanded))
        if isExpanded then
            content:Show()
            section:SetHeight(M().sectionHeaderHeight + section._contentHeight + M().collapsible.borderWidth)
        else
            content:Hide()
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
        self._backdrop:SetHover(true)
    end)

    header:SetScript("OnLeave", function(self)
        self._backdrop:SetHover(false)
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
        -- The box edges and fills retint through the backdrop handles; the
        -- indicator is the one accent text here and the title stays white.
        header._indicator:SetTextColor(r, g, b, 1)
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
