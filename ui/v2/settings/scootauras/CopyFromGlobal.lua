-- CopyFromGlobal.lua - "Copy from Global" fly-out on the Aura List page
--
-- One tall, single-column list of every tracker on the account that another
-- character owns (SAU.CollectCopySources), headed per character in class
-- color. Rows look like the Individual Auras rows; clicking one creates this
-- character's copy (SAU.CopyTrackerFromSource), closes the fly-out, refreshes
-- the list, and opens the editor on the copy. Built once per settings window
-- and rebuilt from data on every open.
local addonName, addon = ...

addon.UI = addon.UI or {}
local Flyout = {}
addon.UI.ScootAuraCopyFlyout = Flyout

local WIDTH = 460
local PADDING = 10
local INSET = PADDING + 1          -- Flyout content inset (padding + 1px border)
local MAX_HEIGHT = 780
local SCREEN_FRACTION = 0.8
local GAP = 6                      -- trigger-to-panel spacing

local ROW_H = 28                   -- mirrors AuraListRenderer's tracker rows
local ROW_ICON = 17
local PAD = 8
local HEADER_H = 24
local HEADER_FONT_SIZE = 13
local SECTION_GAP = 8
local EMPTY_H = 56

local current   -- the live fly-out (one Aura List page, one trigger)

local function GetTheme() return addon.UI and addon.UI.Theme end
local function GetSAU() return addon.ScootAuras end

local function MetaText(tracker)
    local ui = addon.ScootAurasUI
    if ui and ui.TrackerMetaText then
        return ui.TrackerMetaText(tracker, false)
    end
    return ""
end

local function SpellTexture(spellId)
    return GetSAU()._SpellIcon(spellId)
end

--------------------------------------------------------------------------------
-- Pooled widgets (headers, rows, the empty-state line)
--------------------------------------------------------------------------------

local function AcquireHeader(panel, child)
    panel._headers = panel._headers or {}
    for _, fs in ipairs(panel._headers) do
        if not fs._used then
            fs._used = true
            fs:Show()
            return fs
        end
    end
    local theme = GetTheme()
    local fs = child:CreateFontString(nil, "OVERLAY")
    fs:SetFont(theme:GetFont("HEADER"), HEADER_FONT_SIZE, "")
    fs:SetJustifyH("LEFT")
    fs:SetJustifyV("BOTTOM")
    fs:SetWordWrap(false)
    fs._used = true
    table.insert(panel._headers, fs)
    return fs
end

local function OnRowClick(row)
    local panel = row._panel
    local src = row._src
    if not src then return end
    local SAU = GetSAU()
    if not SAU or not SAU.CopyTrackerFromSource then return end

    local newId, err = SAU.CopyTrackerFromSource(src)
    panel:Close()
    if addon.ScootAurasUI and addon.ScootAurasUI.RefreshList then
        addon.ScootAurasUI.RefreshList()
    end
    if newId then
        if addon.ShowScootAuraEditor then addon.ShowScootAuraEditor(newId) end
    else
        local Controls = addon.UI and addon.UI.Controls
        if Controls and Controls.InfoDialog then
            Controls:InfoDialog("Could not copy the tracker: " .. tostring(err))
        end
    end
end

local function AcquireRow(panel, child)
    panel._rows = panel._rows or {}
    for _, row in ipairs(panel._rows) do
        if not row._used then
            row._used = true
            row:Show()
            return row
        end
    end
    local theme = GetTheme()
    local ar, ag, ab = theme:GetAccentColor()

    local row = CreateFrame("Frame", nil, child)
    row:SetHeight(ROW_H)
    row:EnableMouse(true)
    row._panel = panel

    local hoverBg = row:CreateTexture(nil, "BACKGROUND", nil, -8)
    hoverBg:SetAllPoints()
    hoverBg:SetColorTexture(ar, ag, ab, 0.08)
    hoverBg:Hide()
    row._hoverBg = hoverBg

    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(ROW_ICON, ROW_ICON)
    icon:SetPoint("LEFT", row, "LEFT", PAD, 0)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row._icon = icon

    local textLeft = PAD + ROW_ICON + 6

    local name = row:CreateFontString(nil, "OVERLAY")
    name:SetFont(theme:GetFont("LABEL"), 8, "")
    name:SetPoint("TOPLEFT", row, "TOPLEFT", textLeft, -6)
    name:SetPoint("TOPRIGHT", row, "TOPRIGHT", -PAD, -6)
    name:SetJustifyH("LEFT")
    name:SetWordWrap(false)
    name:SetTextColor(0.92, 0.92, 0.92, 1)
    row._name = name

    local meta = row:CreateFontString(nil, "OVERLAY")
    meta:SetFont(theme:GetFont("LABEL"), 7, "")
    meta:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", textLeft, 6)
    meta:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -PAD, 6)
    meta:SetJustifyH("LEFT")
    meta:SetWordWrap(false)
    meta:SetTextColor(0.55, 0.55, 0.55, 1)
    row._meta = meta

    row:SetScript("OnEnter", function() hoverBg:Show() end)
    row:SetScript("OnLeave", function() hoverBg:Hide() end)
    row:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" then OnRowClick(self) end
    end)

    row._used = true
    table.insert(panel._rows, row)
    return row
end

local function ReleaseAll(panel)
    for _, fs in ipairs(panel._headers or {}) do
        fs._used = false
        fs:Hide()
    end
    for _, row in ipairs(panel._rows or {}) do
        row._used = false
        row._src = nil
        row._hoverBg:Hide()
        row:Hide()
    end
    if panel._empty then panel._empty:Hide() end
end

--------------------------------------------------------------------------------
-- Build from data
--------------------------------------------------------------------------------

local function HeaderColor(bucket)
    local theme = GetTheme()
    if bucket.unassigned then return 0.6, 0.6, 0.6 end
    if bucket.classToken and addon.GetClassColorRGB then
        local r, g, b = addon.GetClassColorRGB(bucket.classToken)
        if r then return r, g, b end
    end
    local ar, ag, ab = theme:GetAccentColor()
    return ar, ag, ab
end

local function Rebuild(panel)
    local child = panel._scrollChild
    local scrollFrame = panel._scrollFrame
    ReleaseAll(panel)

    local SAU = GetSAU()
    local buckets = (SAU and SAU.CollectCopySources) and SAU.CollectCopySources() or {}
    local rowW = WIDTH - 2 * INSET
    local y = 0

    if #buckets == 0 then
        if not panel._empty then
            local theme = GetTheme()
            local fs = child:CreateFontString(nil, "OVERLAY")
            fs:SetFont(theme:GetFont("LABEL"), 11, "")
            fs:SetJustifyH("CENTER")
            fs:SetTextColor(0.6, 0.6, 0.6, 1)
            fs:SetText("No other characters have ScootAuras yet.")
            panel._empty = fs
        end
        panel._empty:ClearAllPoints()
        panel._empty:SetPoint("TOPLEFT", child, "TOPLEFT", 0, 0)
        panel._empty:SetPoint("TOPRIGHT", child, "TOPLEFT", rowW, 0)
        panel._empty:SetHeight(EMPTY_H)
        panel._empty:Show()
        y = EMPTY_H
    end

    for i, bucket in ipairs(buckets) do
        if i > 1 then y = y + SECTION_GAP end
        local header = AcquireHeader(panel, child)
        header:ClearAllPoints()
        header:SetPoint("TOPLEFT", child, "TOPLEFT", PAD, -y)
        header:SetPoint("TOPRIGHT", child, "TOPLEFT", rowW - PAD, -y)
        header:SetHeight(HEADER_H)
        header:SetText(bucket.displayName)
        header:SetTextColor(HeaderColor(bucket))
        y = y + HEADER_H

        for _, src in ipairs(bucket.sources) do
            local row = AcquireRow(panel, child)
            row._src = src
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -y)
            row:SetPoint("TOPRIGHT", child, "TOPLEFT", rowW, -y)
            local t = src.tracker
            row._icon:SetTexture(SpellTexture(t.spellId))
            row._icon:SetDesaturated(false)
            row._name:SetText(t.name or ("Aura " .. tostring(t.spellId)))
            row._meta:SetText(MetaText(t))
            y = y + ROW_H
        end
    end

    child:SetWidth(rowW)
    child:SetHeight(math.max(1, y))

    local screenH = (UIParent and UIParent:GetHeight()) or 768
    local wanted = y + 2 * INSET
    local h = math.floor(math.min(wanted, MAX_HEIGHT, screenH * SCREEN_FRACTION))
    panel:SetFlyoutSize(WIDTH, math.max(h, EMPTY_H + 2 * INSET))
    if scrollFrame.ResetScroll then scrollFrame.ResetScroll() end
end

-- The control centers the panel under its trigger; a 460px panel under a
-- button at the header's right edge would run past the window and be shoved
-- around by screen clamping. Right-align it under the button instead and aim
-- the nub at the button's middle. Runs after PositionPanel (SetFlyoutSize
-- re-centers), so it is the last word on placement for this open.
local function AlignUnderTrigger(panel)
    local anchor = panel._anchor
    if not anchor then return end
    panel:ClearAllPoints()
    panel:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -GAP)
    local aw = anchor:GetWidth() or 0
    panel:SetNubOffset(math.floor(WIDTH / 2 - aw / 2))
end

--------------------------------------------------------------------------------
-- Public
--------------------------------------------------------------------------------

--- Creates the fly-out for a trigger button. One instance lives per settings
-- window; the caller caches it and toggles it from the trigger's onClick.
function Flyout.Create(anchorBtn)
    local Controls = addon.UI and addon.UI.Controls
    if not Controls or not Controls.CreateFlyout then return nil end
    local Picker = addon.UI and addon.UI.ScootAuraCDMPicker
    if not Picker or not Picker.CreateScrollRegion then return nil end

    local panel = Controls:CreateFlyout({
        anchor = anchorBtn,
        direction = "DOWN",
        width = WIDTH,
        height = 300,
        padding = PADDING,
        gap = GAP,
        name = "ScootAuraCopyFlyout",
        onShow = function(self)
            Rebuild(self)
            AlignUnderTrigger(self)
        end,
    })
    if not panel then return nil end

    local content = panel:GetContent()
    local scrollFrame, child = Picker.CreateScrollRegion(content)
    scrollFrame:SetAllPoints(content)
    panel._scrollFrame = scrollFrame
    panel._scrollChild = child

    current = panel
    return panel
end

function Flyout.Close()
    if current and current.Close then current:Close() end
end

function Flyout.IsOpen()
    return current ~= nil and current:IsOpen()
end

-- For the settings window's OnHide list: the panel is parented to UIParent
-- and would otherwise outlive the window (it hides on combat).
function addon.CloseScootAuraCopyFlyout()
    Flyout.Close()
end
