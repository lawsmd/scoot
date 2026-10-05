-- ScrollList.lua - a scrolling list of rows: an indexed row pool inside a
-- clipped ScrollFrame, the skin's scrollbar beside it, the wheel, hover and
-- a single selection on the listRow role.
--
-- Every list in the framework built this by hand: a ScrollFrame, a scroll
-- child, a wheel handler, rows laid out one under the other. The list owns
-- the frame, the pool and the scroll; the caller owns a row's content and
-- what a row shows for an item.
--
-- opts:
--   parent          required
--   name            a global name for the frame
--   width, height   the frame's size; a caller may anchor the frame instead
--   rowHeight       default metrics.listRow.height
--   rowGap          the room between rows, default 0
--   padding         a number or { left, right, top, bottom } the rows keep
--                   off the frame's edge, default 0
--   gutter          false lets the rows run under the bar's column; the
--                   default keeps the column free whether or not the bar
--                   shows, so a list that grows past its height does not
--                   reflow
--   scrollBar       false leaves the bar out
--   wheelRows       rows per wheel notch, default 3
--   hover           false leaves the cursor without a wash
--   createRow(row, index)
--                   builds the row's content on the Button the list made,
--                   once per row
--   render(row, item, index)
--                   fills a row for an item, on every SetItems
--   onSelect(item, index, row)
--                   a left click; with it the clicked row stays selected.
--                   Without it rows take no selection
--   onRightClick(item, index, row)
--   onEnter, onLeave(item, index, row)
--
-- Returns a handle: frame, scrollFrame, content, SetItems(items),
-- Refresh(), SetSelected(index), GetSelected(), GetSelectedItem(),
-- GetRow(index), ScrollToTop(), ScrollToIndex(index), Cleanup(). A row
-- carries _backdrop, its listRow handle, so render can call SetStatus and
-- SetDisabled on it, and _index.
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.Controls = addon.UI.Controls or {}
local Controls = addon.UI.Controls

local function Pad(padding)
    if type(padding) == "number" then
        return { left = padding, right = padding, top = padding, bottom = padding }
    end
    if type(padding) ~= "table" then
        return { left = 0, right = 0, top = 0, bottom = 0 }
    end
    return { left = padding.left or 0, right = padding.right or 0, top = padding.top or 0, bottom = padding.bottom or 0 }
end

function Controls.CreateScrollList(opts)
    if not opts or not opts.parent then return nil end
    local Chrome = addon.UI.Chrome
    local m = Controls.Metrics()
    local lm = m.listRow or {}
    local sb = m.scrollBar
    local rowHeight = opts.rowHeight or lm.height or 24
    local rowGap = opts.rowGap or 0
    local pitch = rowHeight + rowGap
    local pad = Pad(opts.padding)
    local withBar = opts.scrollBar ~= false
    local gutter = (withBar and opts.gutter ~= false) and (sb.width + sb.margin + sb.gap) or 0
    local wheelRows = opts.wheelRows or 3
    local selectable = opts.onSelect ~= nil
    local hover = opts.hover ~= false

    local frame = CreateFrame("Frame", opts.name, opts.parent)
    if opts.width and opts.height then frame:SetSize(opts.width, opts.height) end

    local scrollFrame = CreateFrame("ScrollFrame", nil, frame)
    scrollFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", pad.left, -pad.top)
    scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -(pad.right + gutter), pad.bottom)

    -- The child is as wide as the view, so rows anchored to both its edges
    -- take the view's width
    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetPoint("TOPLEFT")
    content:SetSize(1, 1)
    scrollFrame:SetScrollChild(content)
    scrollFrame:SetScript("OnSizeChanged", function(_, w)
        content:SetWidth(math.max(1, w or 1))
    end)

    local bar
    if withBar then
        bar = Controls.CreateScrollBar({ parent = frame, scrollFrame = scrollFrame })
        if bar then
            bar:SetPoint("TOPRIGHT", scrollFrame, "TOPRIGHT", sb.margin + sb.width, 0)
            bar:SetPoint("BOTTOMRIGHT", scrollFrame, "BOTTOMRIGHT", sb.margin + sb.width, 0)
        end
    end

    local list = { frame = frame, scrollFrame = scrollFrame, content = content, _items = {}, _selected = nil }

    local function Scroll(target)
        local maxScroll = math.max(0, (content:GetHeight() or 0) - (scrollFrame:GetHeight() or 1))
        scrollFrame:SetVerticalScroll(math.max(0, math.min(maxScroll, target)))
        if bar then bar:Sync() end
    end

    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        Scroll((self:GetVerticalScroll() or 0) - delta * pitch * wheelRows)
    end)
    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", function(_, delta)
        scrollFrame:GetScript("OnMouseWheel")(scrollFrame, delta)
    end)

    local function Click(row, button)
        local index = row._index
        local item = list._items[index]
        if item == nil then return end
        if button == "RightButton" then
            if opts.onRightClick then opts.onRightClick(item, index, row) end
            return
        end
        if selectable then
            list:SetSelected(index)
            opts.onSelect(item, index, row)
        end
    end

    local pool = addon.Pool.NewIndexed(function(index)
        local row = CreateFrame("Button", nil, content)
        row:SetHeight(rowHeight)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row._backdrop = Chrome.Backdrop("listRow", row)
        row._index = index
        row:SetScript("OnEnter", function(self)
            if hover then self._backdrop:SetHover(true) end
            if opts.onEnter then opts.onEnter(list._items[self._index], self._index, self) end
        end)
        row:SetScript("OnLeave", function(self)
            if hover then self._backdrop:SetHover(false) end
            if opts.onLeave then opts.onLeave(list._items[self._index], self._index, self) end
        end)
        row:SetScript("OnClick", Click)
        if opts.createRow then opts.createRow(row, index) end
        return row
    end)
    list._pool = pool

    function list:SetItems(items)
        self._items = items or {}
        local n = #self._items
        if self._selected and self._selected > n then self._selected = nil end
        for i = 1, n do
            local row = pool:Get(i)
            local y = -((i - 1) * pitch)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
            row:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, y)
            row:SetHeight(rowHeight)
            row._backdrop:SetSelected(selectable and i == self._selected)
            -- Shown before it is filled: a FontString styled while hidden
            -- keeps its creation font
            row:Show()
            if opts.render then opts.render(row, self._items[i], i) end
        end
        pool:HideFrom(n + 1)
        local height = n > 0 and (n * pitch - rowGap) or 0
        content:SetHeight(math.max(height, 1))
        Scroll(scrollFrame:GetVerticalScroll() or 0)
    end

    function list:Refresh()
        self:SetItems(self._items)
    end

    function list:SetSelected(index)
        self._selected = index
        for i = 1, pool:Count() do
            pool:Get(i)._backdrop:SetSelected(selectable and i == index)
        end
    end

    function list:GetSelected()
        return self._selected
    end

    function list:GetSelectedItem()
        return self._selected and self._items[self._selected] or nil
    end

    function list:GetRow(index)
        if not index or index < 1 or index > pool:Count() then return nil end
        return pool:Get(index)
    end

    function list:ScrollToTop()
        Scroll(0)
    end

    function list:ScrollToIndex(index)
        Scroll(((index or 1) - 1) * pitch)
    end

    function list:Cleanup()
        if bar and bar.Cleanup then bar:Cleanup() end
    end

    return list
end
