-- GearFlyout.lua - The gear fly-out on the Aura List page
--
-- One panel serves every tracker row, group member cell, and group box. A
-- tracker gets a two-row menu (Duplicate, Export); a group gets the same two
-- rows and then the layout controls (Spacing, Group Scale, Grow Direction)
-- while the group is loaded. Export swaps the panel to a page holding the
-- string, selected for Ctrl+C. The lifecycle is the spec fly-out's: OpenFor
-- re-targets the one instance, and RenderList brackets its rebuild with
-- BeginReanchor/EndReanchor, so a re-render under an open panel hands it its
-- replacement trigger.
local addonName, addon = ...

addon.UI = addon.UI or {}
local Flyout = {}
addon.UI.ScootAuraGearFlyout = Flyout

local MENU_W_TRACKER_MIN = 120     -- the tracker menu grows to fit its longest label
local MENU_W_GROUP = 340
local EXPORT_W = 340
local PADDING = 10
local INSET = PADDING + 1          -- Flyout content inset (padding + 1px border)
local DEFAULT_GAP = 26             -- clears the group gear's oversized glyph
local ROW_H = 24
local GROUP_ROWS = 2               -- Duplicate, Export; the layout controls hang under them
local ROW_TEXT_INSET = 6
local DIVIDER_H = 13               -- a 1px rule with 6px above and below
local MSG_H = 28                   -- two wrapped lines at LABEL 10
local MSG_BOX_GAP = 4
local EXPORT_BOX_H = 80
local ERROR_R, ERROR_G, ERROR_B = 1, 0.35, 0.35

local GROW_LABELS = { RIGHT = "Right", LEFT = "Left", DOWN = "Down", UP = "Up" }
local GROW_ORDER = { "RIGHT", "LEFT", "DOWN", "UP" }

local panel                        -- the one live fly-out

local function GetTheme() return addon.UI and addon.UI.Theme end
local function GetSAU() return addon.ScootAuras end
local function GetControls() return addon.UI and addon.UI.Controls end

local function RefreshList()
    local ui = addon.ScootAurasUI
    if ui and ui.RefreshList then ui.RefreshList() end
end

--------------------------------------------------------------------------------
-- Geometry
--------------------------------------------------------------------------------

-- Every trigger sits at the right edge of its row or box, so the panel is
-- created right-aligned (`align = "RIGHT"`) and the control re-places it,
-- nub on the button, whenever the size or the anchor changes.
local function SizePanel(w, contentH)
    panel:SetFlyoutSize(w, contentH + 2 * INSET)
end

local function ShowPage(name)
    panel._page = name
    panel._menu:SetShown(name == "menu")
    panel._export:SetShown(name == "export")
end

--------------------------------------------------------------------------------
-- Menu rows
--------------------------------------------------------------------------------

-- A compact clickable row: a label and an accent wash on hover. AcquireRow
-- sets the label's alignment, because the pool serves both menus.
local function CreateMenuRow(_, parent)
    local theme = GetTheme()
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW_H)

    local bg = row:CreateTexture(nil, "BACKGROUND", nil, -6)
    bg:SetAllPoints()
    bg:SetColorTexture(1, 1, 1, 0)
    row._bg = bg

    local text = row:CreateFontString(nil, "OVERLAY")
    text:SetFont(theme:GetFont("LABEL"), 11, "")
    text:SetPoint("LEFT", row, "LEFT", ROW_TEXT_INSET, 0)
    text:SetJustifyH("LEFT")
    text:SetTextColor(1, 1, 1, 1)
    row._text = text

    row:SetScript("OnEnter", function(self)
        local r, g, b = GetTheme():GetAccentColor()
        self._bg:SetColorTexture(r, g, b, 0.12)
    end)
    row:SetScript("OnLeave", function(self)
        self._bg:SetColorTexture(1, 1, 1, 0)
    end)
    row:SetScript("OnClick", function(self)
        if self._onClick then self._onClick() end
    end)
    return row
end

-- centered puts the label mid-row (the tracker menu) instead of at the left
-- edge (the group menu).
local function AcquireRow(index, label, onClick, centered)
    panel._rows = panel._rows or addon.Pool.NewIndexed(CreateMenuRow)
    local row = panel._rows:Get(index, panel._menu)
    local y = -(index - 1) * ROW_H
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", panel._menu, "TOPLEFT", 0, y)
    row:SetPoint("TOPRIGHT", panel._menu, "TOPRIGHT", 0, y)
    row._text:ClearAllPoints()
    if centered then
        row._text:SetPoint("CENTER", row, "CENTER", 0, 0)
    else
        row._text:SetPoint("LEFT", row, "LEFT", ROW_TEXT_INSET, 0)
    end
    row._text:SetText(label)
    row._onClick = onClick
    row:Show()
    return row
end

--------------------------------------------------------------------------------
-- Export page
--------------------------------------------------------------------------------

local function EnsureExportPage()
    if panel._exportBox then return end
    local theme = GetTheme()
    local Controls = GetControls()
    local page = panel._export
    local w = EXPORT_W - 2 * INSET

    local message = page:CreateFontString(nil, "OVERLAY")
    message:SetFont(theme:GetFont("LABEL"), 10, "")
    message:SetPoint("TOPLEFT", page, "TOPLEFT", 0, 0)
    message:SetWidth(w)
    message:SetHeight(MSG_H)
    message:SetJustifyH("LEFT")
    message:SetJustifyV("TOP")
    message:SetWordWrap(true)
    message:SetMaxLines(2)
    panel._message = message

    local box = Controls:CreateMultiLineEditBox({
        parent = page,
        width = w,
        height = EXPORT_BOX_H,
        readOnly = true,
        fontSize = 11,
    })
    box:SetPoint("TOPLEFT", message, "BOTTOMLEFT", 0, -MSG_BOX_GAP)
    panel._exportBox = box
end

local function SetMessage(text, isError)
    if isError then
        panel._message:SetTextColor(ERROR_R, ERROR_G, ERROR_B, 1)
    else
        local dr, dg, db = GetTheme():GetDimTextColor()
        panel._message:SetTextColor(dr, dg, db, 1)
    end
    panel._message:SetText(text or "")
end

-- The string for the open record, or the error in its place. The highlight
-- lands a beat after the text, the profile page's recipe; reopening the gear
-- anywhere starts on the menu page again.
local function ShowExport()
    local SAU = GetSAU()
    if not (SAU and panel._kind) then return end
    EnsureExportPage()
    local str, err
    if panel._kind == "g" then
        str, err = SAU.ExportGroup(panel._id)
    else
        str, err = SAU.ExportTracker(panel._id)
    end
    ShowPage("export")
    local box = panel._exportBox
    if not str then
        SetMessage(err or "Export failed", true)
        box:Hide()
        SizePanel(EXPORT_W, MSG_H)
        return
    end
    SetMessage("Press Ctrl+C to copy", false)
    box:Show()
    box:SetText(str)
    SizePanel(EXPORT_W, MSG_H + MSG_BOX_GAP + EXPORT_BOX_H)
    C_Timer.After(0.05, function()
        if panel:IsOpen() and panel._page == "export" then
            box:SetFocus()
            box:SelectAll()
        end
    end)
end

--------------------------------------------------------------------------------
-- Group layout controls
--------------------------------------------------------------------------------

local function CurrentGroup()
    local SAU = GetSAU()
    if not (SAU and panel._kind == "g") then return nil end
    return SAU.GetGroup(panel._id)
end

-- Built once and refreshed per open: the get and set closures read the open
-- group, so one Spacing, one Group Scale, and one Grow Direction serve every
-- box. Settings apply live with no list re-render.
local function EnsureLayoutControls()
    if panel._layout then return panel._layout end
    local Controls = GetControls()
    local menu = panel._menu
    local ar, ag, ab = GetTheme():GetAccentColor()

    local divider = menu:CreateTexture(nil, "BORDER")
    divider:SetHeight(1)
    divider:SetColorTexture(ar, ag, ab, 0.25)
    local ruleY = -(GROUP_ROWS * ROW_H + math.floor(DIVIDER_H / 2))
    divider:SetPoint("TOPLEFT", menu, "TOPLEFT", 0, ruleY)
    divider:SetPoint("TOPRIGHT", menu, "TOPRIGHT", 0, ruleY)

    local function SetSetting(changes)
        local SAU = GetSAU()
        if SAU and panel._kind == "g" then SAU.SetGroupSettings(panel._id, changes) end
    end

    local spacing = Controls:CreateSlider({
        parent = menu,
        label = "Spacing",
        min = 0,
        max = 50,
        step = 1,
        width = 90,
        inputWidth = 40,
        get = function()
            local group = CurrentGroup()
            return (group and group.settings and group.settings.spacing) or 4
        end,
        set = function(value) SetSetting({ spacing = value }) end,
    })
    local top = -(GROUP_ROWS * ROW_H + DIVIDER_H)
    spacing:SetPoint("TOPLEFT", menu, "TOPLEFT", 0, top)
    spacing:SetPoint("TOPRIGHT", menu, "TOPRIGHT", 0, top)

    -- Scales the whole group as a unit, on top of each member's own scale.
    local scale = Controls:CreateSlider({
        parent = menu,
        label = "Group Scale",
        min = 25,
        max = 200,
        step = 5,
        width = 90,
        inputWidth = 40,
        get = function()
            local group = CurrentGroup()
            return (group and group.settings and group.settings.scale) or 100
        end,
        set = function(value) SetSetting({ scale = value }) end,
    })
    scale:SetPoint("TOPLEFT", spacing, "BOTTOMLEFT", 0, 0)
    scale:SetPoint("TOPRIGHT", spacing, "BOTTOMRIGHT", 0, 0)

    local grow = Controls:CreateSelector({
        parent = menu,
        label = "Grow Direction",
        values = GROW_LABELS,
        order = GROW_ORDER,
        width = 130,
        noBottomBorder = true,
        get = function()
            local group = CurrentGroup()
            return (group and group.settings and group.settings.grow) or "RIGHT"
        end,
        set = function(value) SetSetting({ grow = value }) end,
    })
    grow:SetPoint("TOPLEFT", scale, "BOTTOMLEFT", 0, 0)
    grow:SetPoint("TOPRIGHT", scale, "BOTTOMRIGHT", 0, 0)

    panel._layout = { divider = divider, spacing = spacing, scale = scale, grow = grow }
    return panel._layout
end

local function SetLayoutShown(shown)
    local layout = panel._layout
    if not layout then return end
    layout.divider:SetShown(shown)
    layout.spacing:SetShown(shown)
    layout.scale:SetShown(shown)
    layout.grow:SetShown(shown)
end

--------------------------------------------------------------------------------
-- Build
--------------------------------------------------------------------------------

-- Rebuilt on every open: the rows read the record live, and an unloaded
-- group has no layout controls.
local function Rebuild()
    local SAU = GetSAU()
    if not (SAU and panel._kind and panel._id) then return end
    ShowPage("menu")
    if panel._rows then panel._rows:HideFrom(1) end
    local id, opts = panel._id, panel._opts or {}

    if panel._kind == "t" then
        -- Copies the tracker; inside a group, directly after itself. The
        -- editor's own duplicate then edits the copy; here the user is
        -- browsing the list, so the copy stays put.
        local dup = AcquireRow(1, opts.inGroup and "Duplicate in Group" or "Duplicate", function()
            local newId
            if opts.inGroup then
                newId = SAU.DuplicateTrackerInGroup(id)
            else
                newId = SAU.DuplicateTracker(id)
            end
            GameTooltip:Hide()
            panel:Close()
            if newId then RefreshList() end
        end, true)
        local export = AcquireRow(2, "Export", ShowExport, true)
        SetLayoutShown(false)
        -- As wide as the longer label wants, at least the minimum: a row's
        -- menu says Duplicate, a member cell's says Duplicate in Group.
        local textW = math.max(dup._text:GetStringWidth() or 0, export._text:GetStringWidth() or 0)
        local w = math.max(MENU_W_TRACKER_MIN, math.ceil(textW) + 2 * (ROW_TEXT_INSET + INSET))
        SizePanel(w, 2 * ROW_H)
        return
    end

    local group = SAU.GetGroup(id)
    AcquireRow(1, "Duplicate", function()
        local newGid = SAU.DuplicateGroup(id)
        panel:Close()
        if newGid then RefreshList() end
    end)
    AcquireRow(2, "Export", ShowExport)

    -- Layout settings describe a group that is on screen; an unloaded group
    -- keeps the two rows above and nothing else. The group's ON/OFF pill sits
    -- on the box beside the gear, so no row here re-renders the list.
    local layout = EnsureLayoutControls()
    local loaded = group ~= nil and SAU.IsGroupActive(id, group)
    SetLayoutShown(loaded)
    local contentH = GROUP_ROWS * ROW_H
    if loaded then
        layout.spacing:Refresh()
        layout.scale:Refresh()
        layout.grow:Refresh()
        contentH = contentH + DIVIDER_H
            + layout.spacing:GetHeight() + layout.scale:GetHeight() + layout.grow:GetHeight()
    end
    SizePanel(MENU_W_GROUP, contentH)
end

local function Create(anchorBtn)
    local Controls = GetControls()
    if not Controls or not Controls.CreateFlyout then return nil end

    local p = Controls:CreateFlyout({
        anchor = anchorBtn,
        direction = "DOWN",
        align = "RIGHT",
        width = MENU_W_GROUP,
        height = 100,
        padding = PADDING,
        gap = DEFAULT_GAP,
        name = "ScootAuraGearFlyout",
        onShow = function() Rebuild() end,
        onHide = function(self)
            if self._exportBox then self._exportBox:ClearFocus() end
            self._page = nil
        end,
    })
    if not p then return nil end
    panel = p

    -- Two page frames over the content, one shown at a time.
    local content = p:GetContent()
    local menu = CreateFrame("Frame", nil, content)
    menu:SetAllPoints(content)
    p._menu = menu
    local export = CreateFrame("Frame", nil, content)
    export:SetAllPoints(content)
    export:Hide()
    p._export = export

    return p
end

--------------------------------------------------------------------------------
-- Public
--------------------------------------------------------------------------------

--- Opens the fly-out on `anchorBtn` for one record. kind is "t" or "g", id the
-- record's id. Clicking the same button again closes it. opts: key (the
-- record's identity, so the panel can find its new trigger after a re-render),
-- gap (trigger-to-panel spacing), inGroup (a tracker shown inside a group box,
-- whose Duplicate lands beside it).
function Flyout.OpenFor(anchorBtn, kind, id, opts)
    if not anchorBtn then return end
    if not panel then
        if not Create(anchorBtn) then return end
    end
    if panel:IsOpen() and panel._anchor == anchorBtn then
        panel:Close()
        return
    end
    panel._kind = kind
    panel._id = id
    panel._opts = opts or {}
    panel:SetGap((opts and opts.gap) or DEFAULT_GAP)
    panel:SetAnchor(anchorBtn)
    if panel:IsOpen() then
        Rebuild()
    else
        panel:Open()
    end
end

--- Pins the panel where it stands and holds off Cleanup's Close, so the Aura
-- List can destroy the button this panel hangs from. Returns true when there
-- is an open panel to carry over; RenderList must then call EndReanchor.
function Flyout.BeginReanchor()
    if not (panel and panel:IsOpen()) then return false end
    panel._reanchoring = true
    local left, top = panel:GetLeft(), panel:GetTop()
    panel:ClearAllPoints()
    if left and top then
        panel:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
    else
        panel:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
    return true
end

--- Hands over the rebuilt trigger. `reveal` is the new row's hover repaint,
-- because a hover-revealed button starts hidden and the mouse may be on the
-- panel by now. No button means the record is gone from the page: close.
function Flyout.EndReanchor(newAnchor, reveal)
    if not (panel and panel._reanchoring) then return end
    panel._reanchoring = false
    if not (newAnchor and panel:IsOpen()) then
        if panel:IsOpen() then panel:Close() end
        return
    end
    panel:SetAnchor(newAnchor)
    if reveal then reveal() end
end

function Flyout.IsReanchoring()
    return (panel and panel._reanchoring) and true or false
end

--- The open record's identity, or nil. RenderList reads this before it clears
-- the page and looks the key up again once the new rows exist.
function Flyout.GetOpenKey()
    if not (panel and panel:IsOpen() and panel._opts) then return nil end
    return panel._opts.key
end

--- True while the fly-out is open on this button. The Aura List asks before
-- hiding a hover-revealed gear, so the trigger stays put under its own panel
-- once the mouse leaves the row.
function Flyout.IsOpenFor(anchorBtn)
    if not (panel and anchorBtn) then return false end
    if panel._anchor ~= anchorBtn then return false end
    return panel:IsOpen() and true or false
end

function Flyout.Close()
    if not panel then return end
    panel._reanchoring = false
    if panel.Close then panel:Close() end
end
