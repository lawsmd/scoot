-- Navigation.lua - Terminal-style navigation sidebar with custom scrollbar
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.Navigation = {}
local Navigation = addon.UI.Navigation
local Theme = addon.UI.Theme
local Controls = addon.UI.Controls
local Chrome = addon.UI.Chrome

-- Frame names and the one tooltip that names the addon carry the brand: both
-- addons load this file in the retail client.
local BRAND = addon.Brand or "Scoot"

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

-- Layout numbers come from the active skin: navWidth, windowInset,
-- titleBarHeight, and the metrics.nav and metrics.scrollBar tables.
local function M()
    return Controls.Metrics()
end

--------------------------------------------------------------------------------
-- Navigation Model
--------------------------------------------------------------------------------

-- The tree is the product's, not the framework's: Scoot fills it from
-- ui/v2/settings/NavModel.lua and Camelot from forever/menu.lua, each loading
-- after this file. Every read of it below and in settingspanel/ is at call
-- time, the same contract as addon.SearchVocabulary.
Navigation.NavModel = {}

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

Navigation._expandedSections = {}  -- Track which parent sections are expanded
Navigation._selectedKey = nil      -- Currently selected navigation item (nil = Home via logo)
Navigation._rows = {}              -- References to created row frames

--- Check if a module category (and optionally sub-toggle) was active at session start.
function Navigation:IsNavModuleActive(moduleCategory, moduleSubId)
    if not addon._activeModules then return true end
    if not addon._activeModules[moduleCategory] then return false end
    -- Sub-toggle check (e.g., damageMeter + damageMeterV2)
    if moduleSubId and addon._activeModuleSubs and addon._activeModuleSubs[moduleCategory] then
        local sub = addon._activeModuleSubs[moduleCategory][moduleSubId]
        if sub == false then return false end
    end
    return true
end

--- Check if every child of a collapsible parent has a module field and all are disabled.
function Navigation:AreAllChildrenModuleDisabled(navItem)
    if not navItem.collapsible or not navItem.children then return false end
    for _, child in ipairs(navItem.children) do
        if not child.module then
            return false  -- Non-module child is always active
        end
        if self:IsNavModuleActive(child.module, child.moduleSubId) then
            return false  -- At least one module-child is active
        end
    end
    return true
end

--------------------------------------------------------------------------------
-- Navigation Frame Creation
--------------------------------------------------------------------------------

function Navigation:Create(parent)
    if not parent then return nil end

    -- Create main navigation frame (no background - inherits from parent)
    local navFrame = CreateFrame("Frame", BRAND .. "NavFrame", parent)
    navFrame:SetWidth(M().navWidth)
    local inset = M().windowInset
    navFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", inset, -(M().titleBarHeight + inset))
    navFrame:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", inset, inset)

    -- The divider on the nav's right edge, the way the navDivider role says:
    -- an atlas centered on the edge at its own width, cut into a vertical
    -- three-slice when the role names one so its caps keep their size, or
    -- the flat accent line at nav.dividerWidth inside the edge. The content
    -- pane clears nav.dividerGap past the edge either way. The rows draw
    -- over the divider, so a card's right border meets it the way the
    -- Legacy pane's cards do.
    local dividerSpec = Chrome.Spec("navDivider")
    if dividerSpec.kind == "atlas" and dividerSpec.normal then
        local divider = CreateFrame("Frame", nil, navFrame)
        divider:SetFrameLevel(navFrame:GetFrameLevel() + 1)
        local ok, info = pcall(C_Texture.GetAtlasInfo, dividerSpec.normal)
        divider:SetWidth(dividerSpec.width or (ok and info and info.width) or M().nav.dividerWidth)
        divider:SetPoint("TOP", navFrame, "TOPRIGHT", dividerSpec.x or 0, dividerSpec.y or 0)
        divider:SetPoint("BOTTOM", navFrame, "BOTTOMRIGHT", dividerSpec.x or 0, -(dividerSpec.y or 0))
        local art
        if dividerSpec.slice then
            art = Chrome.SlicedAtlas(divider, { atlas = dividerSpec.normal, slice = dividerSpec.slice }, "BORDER")
        end
        if not art then
            local tex = divider:CreateTexture(nil, "BORDER")
            tex:SetAtlas(dividerSpec.normal)
            tex:SetAllPoints()
        end
        navFrame._separator = divider
    else
        local separator = navFrame:CreateTexture(nil, "BORDER")
        separator:SetWidth(M().nav.dividerWidth)
        Controls.RegisterThemedFill(separator, M().nav.dividerAlpha)
        separator:SetPoint("TOPRIGHT", navFrame, "TOPRIGHT", 0, 0)
        separator:SetPoint("BOTTOMRIGHT", navFrame, "BOTTOMRIGHT", 0, 0)
        navFrame._separator = separator
    end

    -- Custom scroll frame (no template - built from scratch). Under the card
    -- look the rows run to the nav's edge so the cards meet the divider; the
    -- scrollbar then lies over their right margin, above them, and shows
    -- only while the tree overflows.
    local isCard = self:IsCardNav()
    local rightReserve = isCard and 0 or (M().scrollBar.margin + M().scrollBar.width + M().scrollBar.gap)
    local scrollFrame = CreateFrame("ScrollFrame", BRAND .. "NavScrollFrame", navFrame)
    scrollFrame:SetPoint("TOPLEFT", navFrame, "TOPLEFT", M().nav.padLeft, -M().nav.padTop)
    scrollFrame:SetPoint("BOTTOMRIGHT", navFrame, "BOTTOMRIGHT", -rightReserve, M().nav.padTop)
    scrollFrame:EnableMouseWheel(true)

    -- Mouse wheel scrolling
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local current = self:GetVerticalScroll() or 0
        local scrollChild = self:GetScrollChild()
        local contentHeight = scrollChild and scrollChild:GetHeight() or 0
        local visibleHeight = self:GetHeight() or 1
        local maxScroll = math.max(0, contentHeight - visibleHeight)

        local step = M().nav.rowHeight * 3  -- Scroll 3 rows at a time
        local newScroll = current - (delta * step)
        newScroll = math.max(0, math.min(maxScroll, newScroll))

        self:SetVerticalScroll(newScroll)

        -- Update custom scrollbar
        if navFrame._scrollbar and navFrame._scrollbar.Sync then
            navFrame._scrollbar:Sync()
        end
    end)

    -- Content frame that will hold all nav items
    local contentFrame = CreateFrame("Frame", BRAND .. "NavContent", scrollFrame)
    contentFrame:SetWidth(scrollFrame:GetWidth() or (M().navWidth - M().nav.padLeft - rightReserve))
    scrollFrame:SetScrollChild(contentFrame)
    navFrame._content = contentFrame
    navFrame._scrollFrame = scrollFrame

    -- The scrollbar owns the scroll frame's range handler
    local scrollbar = Controls.CreateScrollBar({ parent = navFrame, scrollFrame = scrollFrame })
    scrollbar:SetPoint("TOPRIGHT", navFrame, "TOPRIGHT", -M().scrollBar.margin, -M().nav.padTop)
    scrollbar:SetPoint("BOTTOMRIGHT", navFrame, "BOTTOMRIGHT", -M().scrollBar.margin, M().nav.padTop)
    if isCard then
        scrollbar:SetFrameLevel(navFrame:GetFrameLevel() + 10)
    end
    navFrame._scrollbar = scrollbar

    -- Initialize expanded state (start collapsed)
    self:InitializeExpandedState()

    -- Build navigation rows
    self:BuildRows(contentFrame)

    -- Initial scrollbar update
    C_Timer.After(0.1, function()
        if scrollbar and scrollbar.Sync then
            scrollbar:Sync()
        end
    end)

    -- Store reference
    self._frame = navFrame

    -- Subscribe to theme updates; the flat divider follows the accent on its own
    Theme:Subscribe("Navigation_Frame", function()
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
    -- One group is open at a time, and it is the selected page's. A rebuild
    -- after a skin switch keeps the selected key, so its group comes back open.
    local parentKey = self:ParentKeyOf(self._selectedKey)
    if parentKey then
        self._expandedSections[parentKey] = true
    end
end

--------------------------------------------------------------------------------
-- Visibility
--------------------------------------------------------------------------------
-- The two rules that decide what the sidebar shows. BuildRows is one caller;
-- the settings search index is the other, and it has to agree, or search offers
-- a page the sidebar is hiding. Extracted rather than copied for that reason.

--- True when a top-level section appears in the sidebar at all.
function Navigation:IsParentVisible(parent)
    if not parent then return false end
    if not parent.hidden then return true end
    return (addon.db and addon.db.profile and addon.db.profile.debugMenuEnabled) and true or false
end

--- The children the sidebar currently shows under parent: class-gated pages
--- dropped, and among a variantGroup or a mutually exclusive category only the
--- active member, with groupFallback standing in when the whole group is off.
--- Returns an empty array for a parent with no children.
function Navigation:GetVisibleChildren(parent)
    if not parent or not parent.children then return {} end

    -- variantGroup pass: children sharing a variantGroup are alternative
    -- pages for one three-state unit (OFF/X/Z), spanning two categories
    -- -- which is why the mutuallyExclusive filter below cannot serve
    -- them. Among members, only the active one shows; when the whole
    -- group is off, only the groupFallback member shows (grayed, via
    -- the normal disabled path).
    local groupActive = nil
    for _, child in ipairs(parent.children) do
        if child.variantGroup and self:IsNavModuleActive(child.module, child.moduleSubId) then
            groupActive = groupActive or {}
            groupActive[child.variantGroup] = true
        end
    end

    -- Pre-filter: skip inactive variants for mutuallyExclusive categories
    local visibleChildren = {}
    for _, child in ipairs(parent.children) do
        local catDef = child.module and addon.MODULE_CATEGORIES and addon.MODULE_CATEGORIES[child.module]
        local isMutuallyExclusive = catDef and catDef.mutuallyExclusive
        if type(child.isVisible) == "function" and not child.isVisible() then
            -- Page exists but does not apply to this character (class-gated pages)
        elseif child.variantGroup then
            if groupActive and groupActive[child.variantGroup] then
                if self:IsNavModuleActive(child.module, child.moduleSubId) then
                    visibleChildren[#visibleChildren + 1] = child
                end
            elseif child.groupFallback then
                visibleChildren[#visibleChildren + 1] = child
            end
        elseif isMutuallyExclusive and not child.alwaysShow then
            -- Only show the active variant: the variants of a mutually
            -- exclusive category are alternative pages for one feature,
            -- so showing both would read as duplicates. alwaysShow opts
            -- out for a section that has no other variant page to fall
            -- back on, keeping the row visible but grayed.
            if self:IsNavModuleActive(child.module, child.moduleSubId) then
                visibleChildren[#visibleChildren + 1] = child
            end
        else
            visibleChildren[#visibleChildren + 1] = child
        end
    end

    return visibleChildren
end

--------------------------------------------------------------------------------
-- Build Navigation Rows
--------------------------------------------------------------------------------

function Navigation:BuildRows(contentFrame)
    if not contentFrame then return end

    -- Clear existing rows. A backdrop handle stays in the accent registry
    -- until destroyed, so each one goes with its row.
    for _, row in ipairs(self._rows) do
        if row and row.Hide then
            if row._backdrop then row._backdrop:Destroy() end
            row:Hide()
            row:SetParent(nil)
        end
    end
    self._rows = {}

    local yOffset = 0
    local rowIndex = 0

    -- Build sorted iteration order: disabled parent groups sink to bottom
    local enabledIndices = {}
    local disabledIndices = {}
    for i, parent in ipairs(self.NavModel) do
        local skip = not self:IsParentVisible(parent)
        if not skip and parent.collapsible and self:AreAllChildrenModuleDisabled(parent) then
            disabledIndices[#disabledIndices + 1] = i
        elseif not skip then
            enabledIndices[#enabledIndices + 1] = i
        end
    end
    for _, idx in ipairs(disabledIndices) do
        enabledIndices[#enabledIndices + 1] = idx
    end

    local isCard = self:IsCardNav()
    local card = M().nav.card
    for _, parentIdx in ipairs(enabledIndices) do
        local parent = self.NavModel[parentIdx]
        rowIndex = rowIndex + 1

        -- Check if all children's modules are disabled (grays out the parent)
        local isParentModuleDisabled = self:AreAllChildrenModuleDisabled(parent)
        if isParentModuleDisabled then
            self._expandedSections[parent.key] = false
        end

        local visibleChildren = {}
        if parent.collapsible and parent.children then
            visibleChildren = self:GetVisibleChildren(parent)
        end
        local isExpanded = (parent.collapsible and self._expandedSections[parent.key]) and true or false

        -- A card holds its children: its height is the header band plus,
        -- while the group is open, the child rows and the bottom border.
        -- A text row is the header alone, its children rows of their own.
        local headerHeight = isCard and card.height or M().nav.parentRowHeight
        local bodyHeight = 0
        if isCard and isExpanded and #visibleChildren > 0 then
            bodyHeight = #visibleChildren * M().nav.rowHeight + card.padBottom
        end

        local parentRow = self:CreateParentRow(contentFrame, parent, yOffset, isParentModuleDisabled, bodyHeight)
        self._rows[rowIndex] = parentRow

        local childHost = isCard and parentRow or contentFrame
        local childY = isCard and -headerHeight or (yOffset - headerHeight)
        local childInset = isCard and card.inner or 0

        for childIdx, child in ipairs(visibleChildren) do
            rowIndex = rowIndex + 1
            local isLastChild = (childIdx == #visibleChildren)
            local isModuleDisabled = child.module and not self:IsNavModuleActive(child.module, child.moduleSubId)
            local childRow = self:CreateChildRow(
                childHost,
                child,
                childY,
                isLastChild,
                isExpanded,
                #visibleChildren,
                childIdx,
                isModuleDisabled,
                childInset
            )
            self._rows[rowIndex] = childRow

            if isExpanded then
                childY = childY - M().nav.rowHeight
            end
        end

        if isCard then
            yOffset = yOffset - (headerHeight + bodyHeight + card.spacing)
        else
            yOffset = yOffset - headerHeight
            if isExpanded then
                yOffset = yOffset - #visibleChildren * M().nav.rowHeight
            end
        end
    end

    -- Set content frame height
    local totalHeight = math.abs(yOffset) + M().nav.padTop
    contentFrame:SetHeight(math.max(totalHeight, 100))

    -- Update scrollbar
    if self._frame and self._frame._scrollbar and self._frame._scrollbar.Sync then
        self._frame._scrollbar:Sync()
    end
end

--------------------------------------------------------------------------------
-- Create Parent Row (Section header - no tree lines)
--------------------------------------------------------------------------------

-- A parent row is a card when the navCard role says so: the group's name
-- centered on the header band of the card's art, no glyph, a glow while the
-- group is open, and the child rows inside the same card under the header
-- (bodyHeight, from BuildRows, is the room they take while open). Its
-- numbers are nav.card. Otherwise it is the text row navRow draws.
function Navigation:IsCardNav()
    return Chrome.Spec("navCard").kind == "card"
end

function Navigation:CreateParentRow(parent, navItem, yOffset, isModuleDisabled, bodyHeight)
    local isCard = self:IsCardNav()
    local row = CreateFrame("Button", nil, parent)
    if isCard then
        local c = M().nav.card
        row:SetHeight(c.height + (bodyHeight or 0))
        row:SetPoint("TOPLEFT", parent, "TOPLEFT", c.padLeft, yOffset)
        row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -c.padRight, yOffset)
        row._isCard = true
    else
        row:SetHeight(M().nav.parentRowHeight)
        row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, yOffset)
        row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, yOffset)
    end
    row:EnableMouse(true)
    row:RegisterForClicks("AnyUp")

    -- Store metadata
    row._key = navItem.key
    row._isParent = true
    row._isCollapsible = navItem.collapsible
    row._isModuleDisabled = isModuleDisabled
    row._navItem = navItem

    local ar, ag, ab = Theme:GetAccentColor()

    local indicator
    local label = row:CreateFontString(nil, "OVERLAY")
    if isCard then
        local c = M().nav.card
        Theme:ApplyFont(label, c.labelFontRole, c.labelSize)
        label:SetPoint("CENTER", row, "TOP", 0, -c.height / 2)
        label:SetJustifyH("CENTER")
        label:SetText(navItem.label)
        row._label = label

        -- The card's art, glow and header hover fill, and the label's color
        -- by state
        row._backdrop = Chrome.Backdrop("navCard", row, { label = label, header = c.height })
    else
        -- Expand/collapse indicator (▶/▼) - only for collapsible
        indicator = row:CreateFontString(nil, "OVERLAY")
        Theme:ApplyFont(indicator, "button", M().nav.indicatorSize)
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
        local labelSize = navItem.fontSize or 12
        Theme:ApplyLabelFont(label, labelSize)
        if navItem.collapsible then
            label:SetPoint("LEFT", indicator, "RIGHT", 6, 0)
        else
            label:SetPoint("LEFT", row, "LEFT", 8, 0)
        end
        label:SetText(navItem.label)
        row._label = label

        -- Hover and selection fills, and the label's color by state, come from
        -- the navRow role's parent variant
        row._backdrop = Chrome.Backdrop("navRow", row, { variant = "parent", label = label })
    end
    row._backdrop:SetDisabled(isModuleDisabled)
    if navItem.collapsible then
        row._backdrop:SetOpen(self._expandedSections[navItem.key] and true or false)
    end

    if isModuleDisabled then
        -- Disabled: gray out the indicator, show tooltip on hover
        local dimR, dimG, dimB = Theme:GetDimTextColor()
        if navItem.collapsible and indicator then
            indicator:SetTextColor(dimR, dimG, dimB, 0.35)
        end

        row:SetScript("OnEnter", function(self)
            local C = addon.UI and addon.UI.Controls
            if C and C.GetOrCreateTooltip then
                local tip = C:GetOrCreateTooltip()
                tip:SetContent("Module Disabled", "Enable this module on the Features page to access its settings.")
                tip:ShowAtAnchor(self, "TOPLEFT", "TOPRIGHT", 8, 0)
            end
        end)
        row:SetScript("OnLeave", function(self)
            local C = addon.UI and addon.UI.Controls
            if C and C.GetOrCreateTooltip then
                C:GetOrCreateTooltip():Hide()
            end
        end)
        row:SetScript("OnClick", nil)
    else
        row:SetScript("OnEnter", function(self)
            self._backdrop:SetHover(true)
        end)

        row:SetScript("OnLeave", function(self)
            self._backdrop:SetHover(false)
        end)

        -- Click handler
        row:SetScript("OnClick", function(self, button)
            if self._isCollapsible then
                Navigation:ToggleSection(self._key)
            else
                Navigation:SelectItem(self._key)
            end
        end)
    end

    self:UpdateRowSelectionState(row)
    return row
end

--------------------------------------------------------------------------------
-- Create Child Row (with texture-based tree lines)
--------------------------------------------------------------------------------

-- parent is the nav's content frame, or the card the row sits inside, in
-- which case xInset keeps the row within the card's border.
function Navigation:CreateChildRow(parent, navItem, yOffset, isLastChild, isVisible, totalChildren, childIndex, isModuleDisabled, xInset)
    local row = CreateFrame("Button", nil, parent)
    local inset = xInset or 0
    row:SetHeight(M().nav.rowHeight)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", inset, yOffset)
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -inset, yOffset)
    row:EnableMouse(true)
    row:RegisterForClicks("AnyUp")

    -- Store metadata
    row._key = navItem.key
    row._isParent = false
    row._navItem = navItem
    row._isLastChild = isLastChild
    row._isModuleDisabled = isModuleDisabled

    local ar, ag, ab = Theme:GetAccentColor()

    -- Tree lines as textures, where the skin draws them: a zero
    -- nav.treeLineWidth skips them and the label keeps its indent.
    if M().nav.treeLineWidth > 0 then
        local treeLines = {}
        local lineX = M().nav.treeLineX

        -- Vertical line (from parent down to this item)
        local vertLine = row:CreateTexture(nil, "ARTWORK")
        vertLine:SetWidth(M().nav.treeLineWidth)
        vertLine:SetColorTexture(ar, ag, ab, M().nav.treeLineAlpha)
        vertLine:SetPoint("TOPLEFT", row, "TOPLEFT", lineX, 0)

        if isLastChild then
            -- For last child, vertical line goes from top to center (where horizontal line is)
            vertLine:SetPoint("BOTTOM", row, "LEFT", lineX, 0)
        else
            -- For other children, vertical line goes full height
            vertLine:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", lineX, 0)
        end
        treeLines.vertical = vertLine

        -- Horizontal line (branch to label)
        local horizLine = row:CreateTexture(nil, "ARTWORK")
        horizLine:SetHeight(M().nav.treeLineWidth)
        horizLine:SetColorTexture(ar, ag, ab, M().nav.treeLineAlpha)
        horizLine:SetPoint("LEFT", row, "LEFT", lineX + M().nav.treeLineWidth, 0)
        horizLine:SetWidth(M().nav.treeLineLength - M().nav.treeLineWidth)
        treeLines.horizontal = horizLine

        row._treeLines = treeLines
    end

    -- Label text
    local label = row:CreateFontString(nil, "OVERLAY")
    Theme:ApplyValueFont(label, 11)
    label:SetPoint("LEFT", row, "LEFT", M().nav.childIndent + 6, 0)
    label:SetText(navItem.label)
    row._label = label

    -- Hover and selection fills, and the label's color by state, come from
    -- the navRow role's child variant
    row._backdrop = Chrome.Backdrop("navRow", row, { variant = "child", label = label })
    row._backdrop:SetDisabled(isModuleDisabled)

    -- Version badge info icon (e.g., "X" / "Y" with variant color).
    -- hideBadgesWhenDisabled: a variantGroup's OFF fallback row must read as
    -- plain "Player", not "Player [X]" -- no mode is in effect, so no letter.
    local suppressBadges = isModuleDisabled and navItem.hideBadgesWhenDisabled
    if navItem.versionBadge and not suppressBadges
        and addon.UI and addon.UI.Controls and addon.UI.Controls.CreateInfoIcon then
        -- Use variant color if available (X=green, Y=yellow, Z=blue)
        local badgeColor = nil
        if navItem.variant and addon.VARIANT_COLORS and addon.VARIANT_COLORS[navItem.variant] then
            badgeColor = addon.VARIANT_COLORS[navItem.variant]
        end

        -- For mutually exclusive and mode-cycled entries, append switch
        -- instructions to the tooltip
        local catDef = navItem.module and addon.MODULE_CATEGORIES and addon.MODULE_CATEGORIES[navItem.module]
        local tooltipSuffix = ""
        if catDef and catDef.mutuallyExclusive then
            tooltipSuffix = "\n\nSwitch variants on the Features page."
        elseif navItem.variantGroup then
            tooltipSuffix = "\n\nSwitch modes on the Features page."
        end

        row._versionBadge = addon.UI.Controls:CreateInfoIcon({
            parent = row,
            tooltipTitle = navItem.versionBadge.title or "",
            tooltipText = (navItem.versionBadge.text or "") .. tooltipSuffix,
            size = 18,
            iconType = "info",
            customText = navItem.versionBadge.label or "",
            colorOverride = badgeColor,
        })
        -- Adjust font size for badge label
        if row._versionBadge._iconText then
            local fontPath = row._versionBadge._iconText:GetFont()
            if fontPath then
                pcall(row._versionBadge._iconText.SetFont, row._versionBadge._iconText, fontPath, 8, "OUTLINE")
            end
        end
        row._versionBadge:SetPoint("LEFT", label, "RIGHT", 4, 0)
    end

    -- Beta badge (red "beta" label)
    if navItem.betaBadge and not suppressBadges
        and addon.UI and addon.UI.Controls and addon.UI.Controls.CreateInfoIcon then
        local BETA_COLOR = { 0.9, 0.2, 0.2 }
        local betaBadge = addon.UI.Controls:CreateInfoIcon({
            parent = row,
            tooltipTitle = "Beta Feature",
            tooltipText = "This feature is new and may need additional testing. Please report any issues you encounter.",
            size = 18,
            width = 32,
            iconType = "info",
            customText = "beta",
            colorOverride = BETA_COLOR,
        })
        if betaBadge._iconText then
            local fontPath = betaBadge._iconText:GetFont()
            if fontPath then
                pcall(betaBadge._iconText.SetFont, betaBadge._iconText, fontPath, 8, "OUTLINE")
            end
        end
        local anchorFrame = row._versionBadge or label
        betaBadge:SetPoint("LEFT", anchorFrame, "RIGHT", 4, 0)
        row._betaBadge = betaBadge
    end

    if isModuleDisabled then
        -- Disabled module: dim the tree lines and badges, no interaction
        local dimR, dimG, dimB = Theme:GetDimTextColor()
        for _, line in pairs(row._treeLines or {}) do
            line:SetColorTexture(ar, ag, ab, M().nav.treeLineAlpha * 0.3)
        end
        if row._versionBadge and row._versionBadge._iconText then
            row._versionBadge._iconText:SetTextColor(dimR, dimG, dimB, 0.35)
            for _, tex in pairs(row._versionBadge._border) do tex:SetColorTexture(dimR, dimG, dimB, 0.15) end
        end
        if row._betaBadge and row._betaBadge._iconText then
            row._betaBadge._iconText:SetTextColor(dimR, dimG, dimB, 0.35)
            for _, tex in pairs(row._betaBadge._border) do tex:SetColorTexture(dimR, dimG, dimB, 0.15) end
        end
        row:SetScript("OnEnter", function(self)
            local C = addon.UI and addon.UI.Controls
            if C and C.GetOrCreateTooltip then
                local tip = C:GetOrCreateTooltip()
                if navItem.variantGroup then
                    -- A three-state unit sitting on OFF: "module disabled" would
                    -- be the wrong mental model -- nothing is broken, the unit
                    -- just has no mode selected.
                    tip:SetContent("Frame Off",
                        BRAND .. " is leaving this frame alone. Choose the X or Z mode on the Features page to configure it.")
                else
                    tip:SetContent("Module Disabled", "Enable this module on the Features page to access its settings.")
                end
                tip:ShowAtAnchor(self, "TOPLEFT", "TOPRIGHT", 8, 0)
            end
        end)
        row:SetScript("OnLeave", function(self)
            local C = addon.UI and addon.UI.Controls
            if C and C.GetOrCreateTooltip then
                C:GetOrCreateTooltip():Hide()
            end
        end)
        row:SetScript("OnClick", nil)
    else
        row:SetScript("OnEnter", function(self)
            self._backdrop:SetHover(true)
        end)

        row:SetScript("OnLeave", function(self)
            self._backdrop:SetHover(false)
        end)

        -- Click handler
        row:SetScript("OnClick", function(self, button)
            Navigation:SelectItem(self._key)
        end)
    end

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
-- Expand One Section (the nav is an accordion)
--------------------------------------------------------------------------------

-- The parent key a child key sits under; nil for a parent key or for a page
-- the tree does not hold, such as the toolbar's.
function Navigation:ParentKeyOf(key)
    if not key then return nil end
    for _, parent in ipairs(self.NavModel) do
        if parent.children then
            for _, child in ipairs(parent.children) do
                if child.key == key then return parent.key end
            end
        end
    end
    return nil
end

-- The one writer of the expanded state besides the disabled force-collapse
-- in BuildRows: opens parentKey, closes every other group, and rebuilds when
-- anything moved. nil closes them all. Returns whether anything changed.
function Navigation:ExpandOnly(parentKey)
    local changed = false
    for _, parent in ipairs(self.NavModel) do
        if parent.collapsible then
            local want = (parent.key == parentKey)
            if (self._expandedSections[parent.key] or false) ~= want then
                self._expandedSections[parent.key] = want
                changed = true
            end
        end
    end
    if changed then self:Rebuild() end
    return changed
end

-- A click on a group's row: a closed group opens and the rest close; the
-- open group closes. The content pane keeps its page either way.
function Navigation:ToggleSection(parentKey)
    if not parentKey then return end
    if self._expandedSections[parentKey] then
        self:ExpandOnly(nil)
    else
        self:ExpandOnly(parentKey)
    end
end

--------------------------------------------------------------------------------
-- Select Navigation Item
--------------------------------------------------------------------------------

function Navigation:SelectItem(key)
    if not key then return end

    local previousKey = self._selectedKey
    self._selectedKey = key

    -- The page's group opens and the others close. A page outside the tree,
    -- the toolbar's, leaves the groups as they are.
    local parentKey = self:ParentKeyOf(key)
    if parentKey then
        self:ExpandOnly(parentKey)
    end

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
    if row._isModuleDisabled then return end

    if row._backdrop then
        row._backdrop:SetSelected(self._selectedKey == row._key)
    end

    if self.UpdateJumpingLettersColor then
        self:UpdateJumpingLettersColor(row)
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

            -- Update tree line colors for child rows
            if row._treeLines then
                local alpha = row._isModuleDisabled and (M().nav.treeLineAlpha * 0.3) or M().nav.treeLineAlpha
                for _, line in pairs(row._treeLines) do
                    line:SetColorTexture(ar, ag, ab, alpha)
                end
            end

            -- Re-apply the dim indicator on disabled rows; the label follows
            -- its backdrop
            if row._isModuleDisabled and row._indicator then
                local dimR, dimG, dimB = Theme:GetDimTextColor()
                row._indicator:SetTextColor(dimR, dimG, dimB, 0.35)
            end
            if row._backdrop then
                row._backdrop:Refresh()
            end

            self:UpdateRowSelectionState(row)
        end
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
    if self.CleanupJumpingLetters then
        self:CleanupJumpingLetters()
    end

    Theme:Unsubscribe("Navigation_Frame")
    if self._frame and self._frame._scrollbar and self._frame._scrollbar.Cleanup then
        self._frame._scrollbar:Cleanup()
    end

    for _, row in ipairs(self._rows) do
        if row then
            if row._backdrop then row._backdrop:Destroy() end
            row:Hide()
            row:SetParent(nil)
        end
    end

    self._rows = {}
    self._frame = nil
end
