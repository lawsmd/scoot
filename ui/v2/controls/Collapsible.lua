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

-- The clear margin the header's art keeps outside its drawn border. The body
-- moves in and up by it so the box's lines meet that border; a flat header
-- draws to its own edge and has none.
local function HeaderEdge()
    local edge = addon.UI.Chrome.Spec("sectionHeader").edge or {}
    return edge.left or 0, edge.right or 0, edge.bottom or 0
end

local function ExpandedHeight(contentHeight)
    local _, _, up = HeaderEdge()
    return M().sectionHeaderHeight + contentHeight + M().collapsible.borderWidth - up
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
    local totalHeight = expanded and (ExpandedHeight(contentHeight)) or M().sectionHeaderHeight

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

    -- Indicator: a character in the label font or art, as the skin names it.
    -- The title hangs off the indicator's region, and a change of glyph kind
    -- swaps that region, so both are placed again after every SetGlyph.
    local indicator = addon.UI.Chrome.Glyph(header, Glyph(expanded), {
        fontRole = "label", fontSize = M().collapsible.indicatorSize,
    })
    indicator:SetColor(ar, ag, ab, 1)
    header._indicator = indicator

    -- Title text (white, not accent-colored)
    local titleFS = header:CreateFontString(nil, "OVERLAY")
    theme:ApplyFont(titleFS, "header", M().collapsible.titleSize)
    local function PlaceIndicator()
        indicator.region:ClearAllPoints()
        indicator.region:SetPoint("LEFT", header, "LEFT", M().collapsible.contentPadding, 0)
        titleFS:ClearAllPoints()
        titleFS:SetPoint("LEFT", indicator.region, "RIGHT", 6, 0)
    end
    PlaceIndicator()
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
    local edgeLeft, edgeRight, edgeUp = HeaderEdge()
    content:SetPoint("TOPLEFT", header, "BOTTOMLEFT", M().collapsible.borderWidth + edgeLeft, edgeUp)
    content:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", -M().collapsible.borderWidth - edgeRight, edgeUp)
    content:SetHeight(contentHeight)

    -- Background and the box's remaining edges come from the sectionBody role
    content._backdrop = addon.UI.Chrome.Backdrop("sectionBody", content)
    section._content = content
    -- Total horizontal inset of the content frame against the section, read
    -- by the builder to pass the reduced width into the inner builder.
    section._contentInset = content._backdrop.inset * 2 + edgeLeft + edgeRight

    ----------------------------------------------------------------------------
    -- Update visual state based on expanded/collapsed
    ----------------------------------------------------------------------------
    local function UpdateExpandedState()
        local isExpanded = section._expanded

        header._backdrop:SetOpen(isExpanded)
        header._indicator:SetGlyph(Glyph(isExpanded))
        PlaceIndicator()
        if isExpanded then
            content:Show()
            section:SetHeight(ExpandedHeight(section._contentHeight))
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
        header._indicator:SetColor(r, g, b, 1)
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
            return ExpandedHeight(self._contentHeight)
        else
            return M().sectionHeaderHeight
        end
    end

    function section:SetContentHeight(height)
        self._contentHeight = height
        self._content:SetHeight(height)
        if self._expanded then
            self:SetHeight(ExpandedHeight(height))
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
