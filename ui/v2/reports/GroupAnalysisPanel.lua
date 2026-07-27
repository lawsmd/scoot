-- GroupAnalysisPanel.lua - Group Analysis report panel (widget flyout child)
--
-- Persistent surface attached to the widget diamond through the flyout-child
-- chain, so it stacks along the configured direction and inherits the
-- widget's combat fade through frame parenting. Three aligned columns per
-- row: class-colored name, gray spec parenthetical, item level. Cells whose
-- data hasn't arrived yet stay blank and fill in as the passive inspect
-- service reports updates.
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.Reports = addon.UI.Reports or {}
local Panel = {}
addon.UI.Reports.GroupAnalysisPanel = Panel

local GA -- resolved lazily; reports/core loads before this file, data file too

-- Party rows are roomy (5 max); raid rows are tight so 40 fit in two columns.
local METRICS = {
    party = { width = 280, rowHeight = 20, nameSize = 12, specSize = 9,
              nameCol = 120, ilvlCol = 44, columns = 1, rowsPerColumn = 40 },
    raid  = { colWidth = 210, rowHeight = 15, nameSize = 11, specSize = 8,
              nameCol = 90, ilvlCol = 36, columns = 2, rowsPerColumn = 20 },
}
METRICS.solo = METRICS.party

local HEADER_HEIGHT = 24
local PADDING = 8
local COLUMN_GAP = 12
local BORDER = 1
local SPEC_GRAY = { 0.5, 0.5, 0.5, 0.8 }
local RENDER_DEBOUNCE = 0.2

local frame = nil
local rows = {}
local flyoutHandle = nil
local renderQueued = false

local function getFont()
    local face = addon.GetDefaultFontFace and addon.GetDefaultFontFace()
    if face then return face end
    return _G.GameFontNormal and _G.GameFontNormal:GetFont() or "Fonts\\FRIZQT__.TTF"
end

--------------------------------------------------------------------------------
-- Frame
--------------------------------------------------------------------------------

local function ensureFrame()
    if frame then return frame end

    local W = addon.Widget
    local parent = (W and W:GetFrame()) or UIParent

    frame = CreateFrame("Frame", "ScootGroupAnalysisPanel", parent)
    frame:SetSize(METRICS.party.width, 100)
    frame:EnableMouse(true)
    frame:Hide()

    local theme = addon.UI.Theme
    local ar, ag, ab = 0.2, 0.9, 0.3
    local bgR, bgG, bgB = 0.06, 0.06, 0.08
    if theme then
        if theme.GetAccentColor then ar, ag, ab = theme:GetAccentColor() end
        if theme.GetBackgroundSolidColor then bgR, bgG, bgB = theme:GetBackgroundSolidColor() end
    end

    local bg = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    bg:SetPoint("TOPLEFT", BORDER, -BORDER)
    bg:SetPoint("BOTTOMRIGHT", -BORDER, BORDER)
    bg:SetColorTexture(bgR, bgG, bgB, 0.98)
    frame._bg = bg

    frame._border = {}
    for _, edge in ipairs({
        { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true },
        { "TOPLEFT", "BOTTOMLEFT", false }, { "TOPRIGHT", "BOTTOMRIGHT", false },
    }) do
        local t = frame:CreateTexture(nil, "BORDER", nil, -1)
        t:SetPoint(edge[1]); t:SetPoint(edge[2])
        if edge[3] then t:SetHeight(BORDER) else t:SetWidth(BORDER) end
        t:SetColorTexture(ar, ag, ab, 0.8)
        table.insert(frame._border, t)
    end

    local title = frame:CreateFontString(nil, "OVERLAY")
    title:SetFont(getFont(), 11, "OUTLINE")
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, -6)
    title:SetText("Group Analysis")
    title:SetTextColor(ar, ag, ab, 1)
    frame._title = title

    local close = CreateFrame("Button", nil, frame)
    close:SetSize(16, 16)
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)
    local closeText = close:CreateFontString(nil, "OVERLAY")
    closeText:SetFont(getFont(), 12, "OUTLINE")
    closeText:SetPoint("CENTER")
    closeText:SetText("x")
    closeText:SetTextColor(0.7, 0.7, 0.7, 1)
    close._text = closeText
    close:SetScript("OnEnter", function(self) self._text:SetTextColor(1, 1, 1, 1) end)
    close:SetScript("OnLeave", function(self) self._text:SetTextColor(0.7, 0.7, 0.7, 1) end)
    close:SetScript("OnClick", function() Panel:Close() end)
    frame._close = close

    return frame
end

--------------------------------------------------------------------------------
-- Rows
--------------------------------------------------------------------------------

local function acquireRow(index)
    local row = rows[index]
    if not row then
        row = {}
        row.name = frame:CreateFontString(nil, "OVERLAY")
        row.name:SetJustifyH("LEFT")
        row.name:SetWordWrap(false)
        row.spec = frame:CreateFontString(nil, "OVERLAY")
        row.spec:SetJustifyH("LEFT")
        row.spec:SetWordWrap(false)
        row.ilvl = frame:CreateFontString(nil, "OVERLAY")
        row.ilvl:SetJustifyH("RIGHT")
        row.ilvl:SetWordWrap(false)
        rows[index] = row
    end
    row.name:Show()
    row.spec:Show()
    row.ilvl:Show()
    return row
end

local function hideRowsFrom(index)
    for i = index, #rows do
        rows[i].name:Hide()
        rows[i].spec:Hide()
        rows[i].ilvl:Hide()
    end
end

local function specText(specName)
    if not specName then return nil end
    local abbr = addon.SPEC_ABBREVIATIONS and addon.SPEC_ABBREVIATIONS[specName]
    return "(" .. (abbr or specName):upper() .. ")"
end

--------------------------------------------------------------------------------
-- Render
--------------------------------------------------------------------------------

local function render()
    if not frame or not frame:IsShown() then return end
    if not GA then
        GA = addon.Reports and addon.Reports.GroupAnalysis
        if not GA then return end
    end

    local snapshot = GA.BuildSnapshot()
    local M = METRICS[snapshot.mode] or METRICS.party
    local font = getFont()

    local colWidth = (M.columns > 1) and M.colWidth or M.width - 2 * PADDING
    local total = #snapshot.entries

    for i, entry in ipairs(snapshot.entries) do
        local row = acquireRow(i)
        local col = (M.columns > 1) and (i > M.rowsPerColumn and 2 or 1) or 1
        local rowIndex = (col == 2) and (i - M.rowsPerColumn) or i
        local x = PADDING + (col - 1) * (colWidth + COLUMN_GAP)
        local y = -HEADER_HEIGHT - ((rowIndex - 1) * M.rowHeight)

        row.name:SetFont(font, M.nameSize, "OUTLINE")
        row.name:ClearAllPoints()
        row.name:SetPoint("TOPLEFT", frame, "TOPLEFT", x, y)
        row.name:SetSize(M.nameCol, M.rowHeight)
        row.name:SetText(entry.name or "")
        if entry.classR then
            row.name:SetTextColor(entry.classR, entry.classG, entry.classB, 1)
        else
            row.name:SetTextColor(1, 1, 1, 1)
        end

        row.spec:SetFont(font, M.specSize, "OUTLINE")
        row.spec:ClearAllPoints()
        row.spec:SetPoint("TOPLEFT", frame, "TOPLEFT", x + M.nameCol + 4, y)
        row.spec:SetSize(colWidth - M.nameCol - 4 - M.ilvlCol, M.rowHeight)
        row.spec:SetText(specText(entry.specName) or "")
        row.spec:SetTextColor(SPEC_GRAY[1], SPEC_GRAY[2], SPEC_GRAY[3], SPEC_GRAY[4])

        row.ilvl:SetFont(font, M.nameSize, "OUTLINE")
        row.ilvl:ClearAllPoints()
        row.ilvl:SetPoint("TOPLEFT", frame, "TOPLEFT", x + colWidth - M.ilvlCol, y)
        row.ilvl:SetSize(M.ilvlCol, M.rowHeight)
        row.ilvl:SetText(entry.itemLevel and tostring(entry.itemLevel) or "")
        row.ilvl:SetTextColor(1, 1, 1, 1)
    end
    hideRowsFrom(total + 1)

    local visibleRows = math.min(total, M.rowsPerColumn)
    local width = (M.columns > 1)
        and (2 * PADDING + M.columns * colWidth + (M.columns - 1) * COLUMN_GAP)
        or M.width
    local height = HEADER_HEIGHT + (visibleRows * M.rowHeight) + PADDING
    frame:SetSize(width, height)
end

local function queueRender()
    if renderQueued then return end
    renderQueued = true
    C_Timer.After(RENDER_DEBOUNCE, function()
        renderQueued = false
        render()
    end)
end

--------------------------------------------------------------------------------
-- Open / close
--------------------------------------------------------------------------------

local function onRelease(released)
    if GA then GA.Unsubscribe() end
    if released then released:Hide() end
    flyoutHandle = nil
end

function Panel:OpenOrRefresh()
    ensureFrame()
    GA = addon.Reports and addon.Reports.GroupAnalysis

    if not flyoutHandle then
        frame:Show()
        flyoutHandle = addon.Widget:RegisterFlyoutChild(frame, {
            id = "groupAnalysis",
            onRelease = onRelease,
        })
        if GA then
            -- Roster and combat changes rebuild; inspect updates fill blanks.
            GA.Subscribe(function()
                queueRender()
            end)
        end
    end

    render()
end

function Panel:Close()
    if flyoutHandle then
        addon.Widget:ReleaseFlyoutChild(flyoutHandle)
    end
end

function Panel:IsOpen()
    return flyoutHandle ~= nil
end
