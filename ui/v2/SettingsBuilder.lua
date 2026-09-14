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
-- Spacing
--------------------------------------------------------------------------------
-- The page-spine spacing (item spacing, content padding, section spacing and
-- header height, first-item offset) comes from the active skin's metrics,
-- read once per instance in CreateFor. A page rebuild creates fresh builders,
-- so a skin switch reaches every page through the re-render.

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

-- opts.availWidth: the content frame's width when the caller knows it better
-- than the frame does (containers pass the inset child width). Rows anchor at
-- the content padding on both edges, so _rowWidth is what a row control may
-- claim as its definite width; 0 when no width is known, and the row controls
-- then fall back to their deferred measure.
function Builder:CreateFor(scrollContent, opts)
    local m = Controls.Metrics()
    local availWidth = (opts and opts.availWidth)
        or (scrollContent and scrollContent:GetWidth()) or 0
    local instance = {
        _scrollContent = scrollContent,
        _itemSpacing = m.itemSpacing,
        _contentPadding = m.contentPadding,
        _sectionSpacing = m.sectionSpacing,
        _sectionHeaderHeight = m.sectionHeaderHeight,
        _firstItemOffset = m.firstItemOffset,
        _currentY = -m.firstItemOffset,
        _availWidth = availWidth,
        _rowWidth = math.max(0, availWidth - 2 * m.contentPadding),
        _controls = {},         -- Track created controls for cleanup
        _controlsByKey = {},    -- Track controls by key for dynamic updates
        _sections = {},         -- Track section headers
        _placed = {},           -- Vertical layout records for Relayout
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

-- Controls and section headers tear down the same way: Cleanup first, so a
-- frame releases its theme subscription before it is detached. Headers used to
-- get Hide() on their own, which left one UISection_<frame> key in
-- Theme._subscribers per page navigation, each holding its font string and
-- line alive. One loop for both lists so the two cannot drift apart again.
local function releaseFrames(frames)
    for _, f in ipairs(frames) do
        if f.Cleanup then f:Cleanup() end
        if f.Hide then f:Hide() end
        if f.SetParent then f:SetParent(nil) end
    end
end

function Builder:Clear()
    releaseFrames(self._controls)
    self._controls = {}
    self._controlsByKey = {}

    releaseFrames(self._sections)
    self._sections = {}
    self._placed = {}

    -- Reset position
    self._currentY = -self._firstItemOffset
    self._inSection = false
    self._pendingDividerRow = nil

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
--
-- _FlushRowDivider: the builder owns row dividers. A row's divider is drawn
-- only when further content follows it: _PlaceRow, AddDescription, AddLabel,
-- and the section containers flush the pending row; AddSection and Finalize
-- do not, so the last row of a page, section, or tab never gets one. A row
-- placed with noBottomBorder opts out. The divider is a texture on the row
-- itself, so it moves with row growth and releases with the row in Clear.
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

-- Records one vertically placed frame for Relayout. gapAfter may be a number
-- or a function returning one (a collapsible's trailing gap depends on its
-- expanded state at relayout time).
function Builder:_Record(frame, gapBefore, xLeft, xRight, gapAfter)
    table.insert(self._placed, {
        frame = frame,
        gapBefore = gapBefore or 0,
        xLeft = xLeft or 0,
        xRight = xRight or 0,
        gapAfter = gapAfter,
    })
end

-- Re-walks the placed records and recomputes every Y from current frame
-- heights, then updates the content height. The gaps were recorded as they
-- were applied at build time, so a relayout with unchanged heights is a
-- no-op. Coalesce bursts through _MarkDirty.
function Builder:Relayout()
    local scrollContent = self._scrollContent
    if not scrollContent then return self end
    local y = -self._firstItemOffset
    for _, item in ipairs(self._placed) do
        if not item.frame then
            y = y - item.gapBefore
        else
            y = y - item.gapBefore
            item.frame:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", item.xLeft, y)
            item.frame:SetPoint("TOPRIGHT", scrollContent, "TOPRIGHT", item.xRight, y)
            y = y - (item.frame:GetHeight() or 0)
            local gapAfter = item.gapAfter
            if type(gapAfter) == "function" then gapAfter = gapAfter() end
            y = y - (gapAfter or 0)
        end
    end
    self._currentY = y
    if self._finalHeight then
        self._finalHeight = math.abs(y) + self._contentPadding
        scrollContent:SetHeight(self._finalHeight)
    end
    return self
end

function Builder:_MarkDirty()
    if self._relayoutScheduled then return end
    self._relayoutScheduled = true
    C_Timer.After(0, function()
        self._relayoutScheduled = nil
        self:Relayout()
        -- A nested builder's growth changes its section's height, so the
        -- outer builder reflows the rows below the section.
        if self._parentBuilder then
            self._parentBuilder:_MarkDirty()
        end
    end)
end

-- Font-load edge: a face that loads after first render wraps at a different
-- height. One deferred pass re-runs every placed row's measure; a change
-- reflows the page. Finalize and the section containers schedule it, so
-- nested builders are covered at any depth.
function Builder:_ScheduleRemeasure()
    C_Timer.After(0, function()
        local changed = false
        for _, item in ipairs(self._placed) do
            local f = item.frame
            if f and f._measureDesc then
                local before = f:GetHeight() or 0
                f._measureDesc()
                if math.abs((f:GetHeight() or 0) - before) > 0.5 then
                    changed = true
                end
            end
        end
        if changed then self:Relayout() end
    end)
end

function Builder:_FlushRowDivider()
    local prev = self._pendingDividerRow
    self._pendingDividerRow = nil
    if not prev or prev._noDividerAfter then return end
    local m = Controls.Metrics()
    local divider = prev:CreateTexture(nil, "BORDER", nil, -1)
    divider:SetHeight(m.dividerThickness)
    divider:SetPoint("BOTTOMLEFT", prev, "BOTTOMLEFT", 0, 0)
    divider:SetPoint("BOTTOMRIGHT", prev, "BOTTOMRIGHT", 0, 0)
    Controls.RegisterThemedFill(divider, m.dividerAlpha)
    prev._divider = divider
end

function Builder:_PlaceRow(ctl, options)
    if not ctl then return end
    local scrollContent = self._scrollContent

    self:_FlushRowDivider()

    local spacing = 0
    if #self._controls > 0 then
        spacing = options.emphasized and (self._itemSpacing + 4) or self._itemSpacing
        self._currentY = self._currentY - spacing
    end

    ctl:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", self._contentPadding, self._currentY)
    ctl:SetPoint("TOPRIGHT", scrollContent, "TOPRIGHT", -self._contentPadding, self._currentY)

    table.insert(self._controls, ctl)
    ctl._searchLabel = options.label
    ctl._searchSection = self._parentSectionTitle

    if options.key then
        self._controlsByKey[options.key] = ctl
    end

    self._currentY = self._currentY - ctl:GetHeight()

    if options.noBottomBorder then
        ctl._noDividerAfter = true
    end
    self._pendingDividerRow = ctl
    self:_Record(ctl, spacing, self._contentPadding, -self._contentPadding)

    -- A late height change (the deferred measure of a legacy row, a font that
    -- loads after first render) bumps the parent collapsible by its delta and
    -- reflows the rows below on the next frame.
    local parentCollapsible = self._parentCollapsible
    local builder = self
    ctl._onHeightChanged = function(delta)
        if parentCollapsible then
            parentCollapsible:SetContentHeight(parentCollapsible._contentHeight + delta)
        end
        builder:_MarkDirty()
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

    -- A section header separates on its own; the previous section's last row
    -- gets no divider.
    self._pendingDividerRow = nil

    -- Add spacing before section (unless it's the first item)
    local spacing = 0
    if self._inSection or #self._controls > 0 then
        spacing = self._sectionSpacing
        self._currentY = self._currentY - spacing
    end

    local header = CreateFrame("Frame", nil, scrollContent)
    header:SetHeight(self._sectionHeaderHeight)
    header:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", 0, self._currentY)
    header:SetPoint("TOPRIGHT", scrollContent, "TOPRIGHT", 0, self._currentY)

    -- Get theme colors
    local ar, ag, ab = Theme:GetAccentColor()

    -- Section title with terminal-style prefix
    local prefix = options.icon or "▸"
    local titleFS = header:CreateFontString(nil, "OVERLAY")
    local fontPath = Theme:GetFont("HEADER")
    titleFS:SetFont(fontPath, 14, "")
    titleFS:SetPoint("LEFT", header, "LEFT", self._contentPadding, 0)
    titleFS:SetText(prefix .. " " .. (title or "Section"))
    titleFS:SetTextColor(ar, ag, ab, 1)
    header._title = titleFS

    -- Horizontal line after title
    local line = header:CreateTexture(nil, "BORDER")
    line:SetHeight(1)
    line:SetPoint("LEFT", titleFS, "RIGHT", 8, 0)
    line:SetPoint("RIGHT", header, "RIGHT", -self._contentPadding, 0)
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
    self:_Record(header, spacing, 0, 0)

    self._currentY = self._currentY - self._sectionHeaderHeight
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

    self:_FlushRowDivider()

    local gapBefore = 0
    if #self._controls > 0 or #self._sections > 0 then
        gapBefore = self._itemSpacing
    end
    if options.topPadding then
        gapBefore = gapBefore + options.topPadding
    end
    self._currentY = self._currentY - gapBefore

    local frame = CreateFrame("Frame", nil, scrollContent)
    frame:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", self._contentPadding, self._currentY)
    frame:SetPoint("TOPRIGHT", scrollContent, "TOPRIGHT", -self._contentPadding, self._currentY)

    local descFS = frame:CreateFontString(nil, "OVERLAY")
    local fontPath = Theme:GetFont("VALUE")
    descFS:SetFont(fontPath, options.fontSize or 12, "")
    descFS:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
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

    -- Wrap against the known row width and set the height before returning.
    -- Without a known width (a caller-built content frame that is not sized
    -- yet), fall back to an estimate corrected on the next frame.
    if self._rowWidth and self._rowWidth > 0 then
        descFS:SetWidth(self._rowWidth)
        frame:SetHeight((descFS:GetStringHeight() or 16) + 4)
    else
        local estimatedHeight = math.ceil((string.len(text or "") / 80) + 1) * 14
        frame:SetHeight(math.max(16, estimatedHeight))
        C_Timer.After(0, function()
            if descFS and frame then
                local w = frame:GetWidth() or 0
                if w > 0 then descFS:SetWidth(w) end
                frame:SetHeight((descFS:GetStringHeight() or 16) + 4)
            end
        end)
    end

    table.insert(self._controls, frame)
    self:_Record(frame, gapBefore, self._contentPadding, -self._contentPadding, options.bottomPadding)

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

    self:_FlushRowDivider()

    local gapBefore = 0
    if #self._controls > 0 or #self._sections > 0 then
        gapBefore = self._itemSpacing
    end
    self._currentY = self._currentY - gapBefore

    local frame = CreateFrame("Frame", nil, scrollContent)
    frame:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", self._contentPadding, self._currentY)
    frame:SetPoint("TOPRIGHT", scrollContent, "TOPRIGHT", -self._contentPadding, self._currentY)

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
    self:_Record(frame, gapBefore, self._contentPadding, -self._contentPadding)

    self._currentY = self._currentY - frame:GetHeight()

    return self
end

--------------------------------------------------------------------------------
-- AddSpacer: Add vertical space
--------------------------------------------------------------------------------

function Builder:AddSpacer(height)
    height = height or 16
    self._currentY = self._currentY - height
    table.insert(self._placed, { gapBefore = height })
    return self
end

--------------------------------------------------------------------------------
-- Finalize: Set scroll content height and prepare for display
--------------------------------------------------------------------------------

function Builder:Finalize()
    local scrollContent = self._scrollContent
    if not scrollContent then return self end

    -- Add bottom padding
    local totalHeight = math.abs(self._currentY) + self._contentPadding

    -- Set scroll content height
    scrollContent:SetHeight(totalHeight)

    -- Store final height for reference
    self._finalHeight = totalHeight

    self:_ScheduleRemeasure()

    return self
end

--------------------------------------------------------------------------------
-- PlaceCustom: place a renderer-built frame through the builder's layout
--------------------------------------------------------------------------------
-- Spacing, edge anchors, cleanup registration, and the relayout record for a
-- frame the renderer built itself. Replaces direct _currentY/_controls writes.
--
-- opts:
--   gapBefore    : Vertical gap above; defaults to the item spacing once any
--                  content precedes the frame
--   gapAfter     : Extra gap below (default 0)
--   inset        : Horizontal inset from the content edges (default the
--                  content padding)
--   fullBleed    : Anchor at the content edges (same as inset = 0)
--   dividerAfter : Let the builder draw a divider under this frame when more
--                  content follows (default off)
--   key, label   : The _controlsByKey entry and the search tag
--------------------------------------------------------------------------------

function Builder:PlaceCustom(frame, opts)
    if not frame then return self end
    opts = opts or {}
    local scrollContent = self._scrollContent
    if not scrollContent then return self end

    self:_FlushRowDivider()

    local gapBefore = opts.gapBefore
    if gapBefore == nil then
        gapBefore = (#self._controls > 0 or #self._sections > 0) and self._itemSpacing or 0
    end
    self._currentY = self._currentY - gapBefore

    local inset = opts.inset
    if inset == nil then
        inset = opts.fullBleed and 0 or self._contentPadding
    end
    local xLeft = inset
    local xRight = -inset
    frame:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", xLeft, self._currentY)
    frame:SetPoint("TOPRIGHT", scrollContent, "TOPRIGHT", xRight, self._currentY)

    table.insert(self._controls, frame)
    if opts.key then self._controlsByKey[opts.key] = frame end
    if opts.label then frame._searchLabel = opts.label end
    frame._searchSection = self._parentSectionTitle

    self._currentY = self._currentY - (frame:GetHeight() or 0)
    local gapAfter = opts.gapAfter or 0
    self._currentY = self._currentY - gapAfter

    if opts.dividerAfter then
        self._pendingDividerRow = frame
    end
    self:_Record(frame, gapBefore, xLeft, xRight, gapAfter > 0 and gapAfter or nil)

    return self
end

--------------------------------------------------------------------------------
-- Adopt: register a caller-built frame for cleanup without placing it
--------------------------------------------------------------------------------
-- For satellites of a placed row: an attached button, a fly-out, a widget
-- anchored inside a PlaceCustom wrapper. Clear releases it with the page.
--------------------------------------------------------------------------------

function Builder:Adopt(frame)
    if frame then
        table.insert(self._controls, frame)
    end
    return self
end

--------------------------------------------------------------------------------
-- RefreshControls: re-run Refresh on every registered control
--------------------------------------------------------------------------------
-- For set handlers whose value gates sibling rows' disabled states.
--------------------------------------------------------------------------------

function Builder:RefreshControls()
    for _, control in ipairs(self._controls) do
        if control and control.Refresh then
            pcall(control.Refresh, control)
        end
    end
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
