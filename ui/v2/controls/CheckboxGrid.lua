-- CheckboxGrid.lua - One settings row of labelled checkboxes in a grid
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.Controls = addon.UI.Controls or {}
local Controls = addon.UI.Controls
local Theme

local function GetTheme()
    if not Theme then
        Theme = addon.UI.Theme
    end
    return Theme
end

--------------------------------------------------------------------------------
-- CheckboxGrid
--
-- Options:
--   parent     : Frame - Parent frame (required)
--   label      : Row label text, on its own line above the grid
--   columns    : Cells per grid row (default 4)
--   items      : Array of { key, label, get, set, isDisabled } (required)
--   disabled / isDisabled : Function returning the whole row's disabled state
--   rowWidth   : The builder's row width
--   name       : Optional global frame name
--
-- The mark is the toggle chrome role's when the skin draws a template there
-- (Blizzard's checkbox on Forever), else the framework's square
-- (Controls.CreateCheckBox). A click on the mark or on its label toggles.
--------------------------------------------------------------------------------

function Controls:CreateCheckboxGrid(options)
    local theme = GetTheme()
    if not options or not options.parent then return nil end
    local items = options.items
    if type(items) ~= "table" or #items == 0 then return nil end

    local m = Controls.Metrics()
    local parent = options.parent
    local columns = math.max(1, options.columns or 4)
    local rowWidth = options.rowWidth or (parent:GetWidth() or 0)
    local padLeft = m.rowPadding
    local band = m.rowHeight
    -- A cell is a control's height; a mark stands off its label as a check
    -- list row's mark does (PopupList).
    local cellHeight = m.controlHeight
    local markGap = m.listRow.padX
    local gridRows = math.ceil(#items / columns)
    local colWidth = math.floor((rowWidth - padLeft * 2) / columns)
    local isDisabledFn = options.disabled or options.isDisabled

    local row = CreateFrame("Frame", options.name, parent)
    row:SetHeight(band + gridRows * cellHeight + m.descPadBottom)
    row._hoverBg = Controls.AddHoverFill(row, { sublevel = Controls.SUBLEVEL_BG })
    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self) self._hoverBg:Show() end)
    row:SetScript("OnLeave", function(self) self._hoverBg:Hide() end)

    local labelFS = row:CreateFontString(nil, "OVERLAY")
    theme:ApplyFont(labelFS, Controls.RowLabelFontRole())
    labelFS:SetPoint("LEFT", row, "TOPLEFT", padLeft, -band / 2)
    labelFS:SetText(options.label or "")
    labelFS:SetTextColor(theme:GetAccentColor())
    row._label = labelFS

    local Chrome = addon.UI.Chrome
    local spec = (Chrome and Chrome.Spec) and Chrome.Spec("toggle") or nil
    local template = spec and spec.kind == "template"

    local cells = {}
    row._cells = cells
    row._isDisabled = false

    local function CellDisabled(cell)
        if row._isDisabled then return true end
        local fn = cell._def.isDisabled
        return fn and fn() and true or false
    end

    local function Paint(cell)
        local disabled = CellDisabled(cell)
        cell._disabled = disabled
        local r, g, b = theme:GetAccentColor()
        if cell._indicator then
            cell._indicator:SetState(cell._value, disabled)
        else
            cell._mark:SetColor(r, g, b, disabled and 0.35 or 1)
            cell._mark:SetChecked(cell._value)
        end
        cell._text:SetTextColor(r, g, b, disabled and 0.35 or 1)
    end

    -- Visual first, then the setter in a pcall, as MultiToggleRow does: a
    -- setter that errors must not leave the box looking dead.
    local function Toggle(cell)
        if cell._disabled then return end
        cell._value = not cell._value
        Paint(cell)
        PlaySound(cell._value and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
        local set = cell._def.set
        if set then
            local ok, err = pcall(set, cell._value)
            if not ok then geterrorhandler()(err) end
        end
    end

    local function ShowHover() row._hoverBg:Show() end
    local function HideHover() row._hoverBg:Hide() end

    for i, def in ipairs(items) do
        local col = (i - 1) % columns
        local line = math.floor((i - 1) / columns)
        local cell = CreateFrame("Button", nil, row)
        cell:SetSize(colWidth, cellHeight)
        cell:SetPoint("TOPLEFT", row, "TOPLEFT", padLeft + col * colWidth, -(band + line * cellHeight))
        cell:RegisterForClicks("AnyUp")
        cell._def = def

        local markFrame
        if template then
            local indicator = Controls.CreateToggleIndicator(cell, {
                fit = cellHeight,
                onClick = function() Toggle(cell) end,
                onEnter = ShowHover,
                onLeave = HideHover,
            })
            cell._indicator = indicator
            markFrame = indicator.frame
        else
            markFrame = Controls.CreateCheckBox(cell)
            cell._mark = markFrame
        end
        markFrame:SetPoint("LEFT", cell, "LEFT", 0, 0)

        local text = cell:CreateFontString(nil, "OVERLAY")
        theme:ApplyFont(text, "label")
        text:SetPoint("LEFT", markFrame, "RIGHT", markGap, 0)
        text:SetPoint("RIGHT", cell, "RIGHT", -markGap, 0)
        text:SetJustifyH("LEFT")
        text:SetWordWrap(false)
        text:SetText(def.label or "")
        cell._text = text

        cell:SetScript("OnClick", Toggle)
        cell:SetScript("OnEnter", ShowHover)
        cell:SetScript("OnLeave", HideHover)

        cell._value = def.get and def.get() and true or false
        Paint(cell)
        cells[i] = cell
    end

    -- Public methods

    function row:Refresh()
        if self._isDisabledFn then
            self._isDisabled = self._isDisabledFn() and true or false
        end
        for _, cell in ipairs(cells) do
            local get = cell._def.get
            cell._value = get and get() and true or false
            Paint(cell)
        end
        local r, g, b = theme:GetAccentColor()
        self._label:SetTextColor(r, g, b, self._isDisabled and 0.35 or 1)
    end

    function row:SetDisabled(disabled)
        self._isDisabled = disabled and true or false
        self:Refresh()
    end

    function row:IsDisabled()
        return self._isDisabled
    end

    function row:SetLabel(newLabel)
        self._label:SetText(newLabel)
    end

    function row:Cleanup()
        if self._subscribeKey then
            theme:Unsubscribe(self._subscribeKey)
        end
    end

    row._isDisabledFn = isDisabledFn
    row._subscribeKey = "CheckboxGrid_" .. (options.name or tostring(row))
    theme:Subscribe(row._subscribeKey, function() row:Refresh() end)
    if isDisabledFn then row:Refresh() end

    return row
end

return Controls
