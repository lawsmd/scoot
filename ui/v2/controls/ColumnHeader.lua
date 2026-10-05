-- ColumnHeader.lua - the strip of column names over a table of rows, on the
-- sectionHeader role, with a sort mark on the sorted column.
--
-- opts:
--   parent      required
--   name        a global name for the frame
--   height      default metrics.listRow.height
--   padX        what the first and last cells keep off the edges; default
--               metrics.listRow.padX
--   columns     an ordered list of { key, label, width, justify, sortable };
--               a column with no width takes what the others leave
--   sortKey, ascending
--               the column the rows are sorted by at creation
--   onSort(key, ascending)
--               a click on a sortable column; the header repaints its mark
--               and the caller re-sorts
--   open        true drops the strip's bottom edge so a sectionBody under it
--               closes the box, as a section's header and body draw one box
--
-- The frame carries _cells (key to { frame, text, mark }) and the methods
-- SetColumns(columns), SetSort(key, ascending), GetSort(), Cleanup().
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.Controls = addon.UI.Controls or {}
local Controls = addon.UI.Controls

local UP, DOWN = "\226\150\178", "\226\150\188"

function Controls.CreateColumnHeader(opts)
    if not opts or not opts.parent then return nil end
    local Theme = addon.UI.Theme
    local Chrome = addon.UI.Chrome
    local lm = Controls.Metrics().listRow or {}
    local padX = opts.padX or lm.padX or 8

    local frame = CreateFrame("Frame", opts.name, opts.parent)
    frame:SetHeight(opts.height or lm.height or 24)
    frame._backdrop = Chrome.Backdrop("sectionHeader", frame)
    frame._backdrop:SetOpen(opts.open and true or false)
    frame._cells = {}
    frame._order = {}
    frame._sortKey = opts.sortKey
    frame._ascending = opts.ascending ~= false

    local function PaintCell(cell)
        local sorted = cell._key == frame._sortKey
        local r, g, b, a
        if sorted then
            r, g, b, a = Theme:GetAccentColor()
        elseif cell._hover then
            r, g, b, a = Theme:GetPrimaryTextColor()
        else
            r, g, b, a = Theme:GetDimTextColor()
        end
        cell._text:SetTextColor(r, g, b, a or 1)
        if cell._mark then
            cell._mark:SetText(sorted and (frame._ascending and UP or DOWN) or "")
            cell._mark:SetTextColor(r, g, b, a or 1)
        end
    end

    local function PaintAll()
        for _, cell in ipairs(frame._order) do PaintCell(cell) end
    end

    local function Layout()
        local total = frame:GetWidth() or 0
        local fixed, free = 0, 0
        for _, cell in ipairs(frame._order) do
            if cell._width then fixed = fixed + cell._width else free = free + 1 end
        end
        local spare = math.max(0, total - padX * 2 - fixed)
        local each = free > 0 and (spare / free) or 0
        local x = padX
        for _, cell in ipairs(frame._order) do
            local w = cell._width or each
            cell:ClearAllPoints()
            cell:SetPoint("TOPLEFT", frame, "TOPLEFT", x, 0)
            cell:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", x, 0)
            cell:SetWidth(math.max(1, w))
            x = x + w
        end
    end

    function frame:SetColumns(columns)
        for _, cell in ipairs(self._order) do cell:Hide() end
        wipe(self._cells)
        wipe(self._order)
        for _, col in ipairs(columns or {}) do
            local cell = CreateFrame("Button", nil, self)
            cell._key = col.key
            cell._width = col.width
            cell:RegisterForClicks("LeftButtonUp")

            local text = cell:CreateFontString(nil, "OVERLAY")
            Theme:ApplyFont(text, "miniLabel")
            text:SetJustifyH(col.justify or "LEFT")
            text:SetWordWrap(false)
            text:SetText(col.label or "")
            cell._text = text

            if col.sortable then
                local mark = cell:CreateFontString(nil, "OVERLAY")
                Theme:ApplyFont(mark, "miniLabel")
                cell._mark = mark
                -- The mark stands at the end of a left-justified name and
                -- before a right-justified one
                if (col.justify or "LEFT") == "RIGHT" then
                    text:SetPoint("RIGHT", cell, "RIGHT", 0, 0)
                    mark:SetPoint("RIGHT", text, "LEFT", -2, 0)
                else
                    text:SetPoint("LEFT", cell, "LEFT", 0, 0)
                    mark:SetPoint("LEFT", text, "RIGHT", 2, 0)
                end
                cell:SetScript("OnEnter", function(c) c._hover = true; PaintCell(c) end)
                cell:SetScript("OnLeave", function(c) c._hover = false; PaintCell(c) end)
                cell:SetScript("OnClick", function(c)
                    if frame._sortKey == c._key then
                        frame._ascending = not frame._ascending
                    else
                        frame._sortKey = c._key
                        frame._ascending = true
                    end
                    PaintAll()
                    if opts.onSort then opts.onSort(frame._sortKey, frame._ascending) end
                    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
                end)
            else
                text:SetPoint("LEFT", cell, "LEFT", 0, 0)
                text:SetPoint("RIGHT", cell, "RIGHT", 0, 0)
                cell:EnableMouse(false)
            end

            self._cells[col.key] = cell
            self._order[#self._order + 1] = cell
        end
        Layout()
        PaintAll()
    end

    function frame:SetSort(key, ascending)
        self._sortKey = key
        if ascending ~= nil then self._ascending = ascending and true or false end
        PaintAll()
    end

    function frame:GetSort()
        return self._sortKey, self._ascending
    end

    function frame:Cleanup()
        if self._backdrop then self._backdrop:Destroy() end
    end

    frame:SetScript("OnSizeChanged", Layout)
    frame:SetColumns(opts.columns)
    return frame
end
