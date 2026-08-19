-- SpecFlyout.lua - "Load in..." fly-out on the Aura List page
--
-- Auras are account-wide, so this lists every specialization in the game, not
-- just the player's own class: a Priest's aura is used on a Shaman by checking
-- the Shaman specs here. Layout and row recipe come from the Rules spec picker
-- (RulesRenderer), on a Controls:CreateFlyout instead of that file's hand-rolled
-- popup. Clicking a class header toggles that whole class.
--
-- One instance serves every tracker row and group box; OpenFor re-targets it and
-- re-reads its state. Edits land immediately, list included: a re-render
-- destroys the row this panel hangs from, so RenderList brackets its rebuild
-- with BeginReanchor/EndReanchor and hands over the replacement button.
local addonName, addon = ...

addon.UI = addon.UI or {}
local Flyout = {}
addon.UI.ScootAuraSpecFlyout = Flyout

local WIDTH = 360
local PADDING = 10
local INSET = PADDING + 1          -- Flyout content inset (padding + 1px border)
-- Trigger-to-panel spacing. The nub tip reaches 15px above the panel top, so
-- the stock 6 planted it in the middle of a 13px trigger; 18 lands it 3px
-- clear of the button box, the clearance the group gear fly-out uses.
local GAP = 18
local TITLE_H = 20
local ROW_H = 22
local HEADER_H = 22
local CLASS_GAP = 6
local CHECK_SIZE = 12
local ICON_SIZE = 14
local SPECS_PER_ROW = 3
local MAX_LIST_H = 320

local panel                        -- the one live fly-out

local function GetTheme() return addon.UI and addon.UI.Theme end
local function GetSAU() return addon.ScootAuras end

--------------------------------------------------------------------------------
-- Rows
--------------------------------------------------------------------------------

-- Row recipe from the Rules picker: a recolored solid square for the check, the
-- spec's own icon, and a name that goes dim when off.
local function AcquireSpecRow(content, index)
    panel._rows = panel._rows or {}
    local row = panel._rows[index]
    if row then return row end

    local theme = GetTheme()
    row = CreateFrame("Button", nil, content)
    row:SetHeight(ROW_H)

    local check = row:CreateTexture(nil, "ARTWORK")
    check:SetSize(CHECK_SIZE, CHECK_SIZE)
    check:SetPoint("LEFT", row, "LEFT", 0, 0)
    check:SetTexture("Interface\\Buttons\\WHITE8x8")
    row._check = check

    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(ICON_SIZE, ICON_SIZE)
    icon:SetPoint("LEFT", check, "RIGHT", 4, 0)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row._icon = icon

    local name = row:CreateFontString(nil, "OVERLAY")
    name:SetFont(theme:GetFont("VALUE"), 10, "")
    name:SetPoint("LEFT", icon, "RIGHT", 4, 0)
    name:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    name:SetJustifyH("LEFT")
    name:SetWordWrap(false)
    row._name = name

    row:SetScript("OnEnter", function(self)
        if not self._on then
            local ar, ag, ab = GetTheme():GetAccentColor()
            self._check:SetColorTexture(ar, ag, ab, 0.5)
        end
    end)
    row:SetScript("OnLeave", function(self)
        if self._paint then self._paint() end
    end)
    row:SetScript("OnClick", function(self)
        if not self._onClick then return end
        if self._onClick() == false then return end
        PlaySound(self._on and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF
            or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        Flyout.ApplyEdit()
    end)

    panel._rows[index] = row
    return row
end

local function PaintRow(row, isOn)
    local theme = GetTheme()
    local ar, ag, ab = theme:GetAccentColor()
    local dr, dg, db = theme:GetDimTextColor()
    row._on = isOn
    row._paint = function()
        if isOn then
            row._check:SetColorTexture(ar, ag, ab, 1)
            row._name:SetTextColor(1, 1, 1, 1)
        else
            row._check:SetColorTexture(0.25, 0.25, 0.25, 1)
            row._name:SetTextColor(dr, dg, db, 1)
        end
    end
    row._paint()
end

-- Class header, clickable: checks every spec of the class, or clears them all
-- when the class is already fully checked.
local function AcquireClassRow(content, index)
    panel._headers = panel._headers or {}
    local row = panel._headers[index]
    if row then return row end

    local theme = GetTheme()
    row = CreateFrame("Button", nil, content)
    row:SetHeight(HEADER_H)

    local label = row:CreateFontString(nil, "OVERLAY")
    label:SetFont(theme:GetFont("LABEL"), 11, "")
    label:SetPoint("LEFT", row, "LEFT", 0, 0)
    label:SetJustifyH("LEFT")
    row._label = label

    local hint = row:CreateFontString(nil, "OVERLAY")
    hint:SetFont(theme:GetFont("VALUE"), 9, "")
    hint:SetPoint("LEFT", label, "RIGHT", 6, 0)
    hint:SetJustifyH("LEFT")
    hint:SetTextColor(0.5, 0.5, 0.5, 1)
    row._hint = hint

    row:SetScript("OnEnter", function(self) self._hint:SetAlpha(1) end)
    row:SetScript("OnLeave", function(self) self._hint:SetAlpha(0) end)
    row:SetScript("OnClick", function(self)
        if not self._onClick then return end
        self._onClick()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        Flyout.ApplyEdit()
    end)

    panel._headers[index] = row
    return row
end

--------------------------------------------------------------------------------
-- Build
--------------------------------------------------------------------------------

-- The control centers the panel under its trigger. These triggers sit at the
-- right edge of their row or box, so right-align instead and aim the nub at
-- the button. SetFlyoutSize re-centers whenever it runs on an open panel, so
-- this is always the last word on placement.
local function AlignUnderTrigger()
    local anchor = panel._anchor
    if not anchor then return end
    panel:ClearAllPoints()
    panel:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -GAP)
    local aw = anchor:GetWidth() or 0
    panel:SetNubOffset(math.floor(WIDTH / 2 - aw / 2))
end

-- The player's own class first, then alphabetical: the common edit is a spec of
-- the class you are on.
local function OrderedBuckets()
    local Rules = addon.Rules
    if not (Rules and Rules.GetSpecBuckets) then return {} end
    local ok, buckets = pcall(Rules.GetSpecBuckets, Rules)
    if not ok or type(buckets) ~= "table" then return {} end

    local mine = addon.GetClassTokenForUnit and addon.GetClassTokenForUnit("player") or nil
    local out = {}
    for _, entry in ipairs(buckets) do
        if type(entry) == "table" and #(entry.specs or {}) > 0 then
            table.insert(out, entry)
        end
    end
    table.sort(out, function(a, b)
        local am, bm = (a.file == mine), (b.file == mine)
        if am ~= bm then return am end
        return tostring(a.name) < tostring(b.name)
    end)
    return out
end

-- Rebuilt on every open: the spec list can be empty before the class data
-- loads, and one stale empty build would strand the fly-out for the session.
local function Rebuild()
    local SAU = GetSAU()
    local opts = panel._opts
    if not (SAU and opts) then return end

    local content = panel._list
    for _, row in ipairs(panel._rows or {}) do row:Hide() end
    for _, row in ipairs(panel._headers or {}) do row:Hide() end

    panel._title:SetText(opts.title or "Load in...")

    local buckets = OrderedBuckets()

    local selected = {}
    local stored = opts.get and opts.get() or nil
    for _, id in ipairs(stored or {}) do selected[id] = true end

    if #buckets == 0 then
        panel._empty:Show()
        panel._scroll:Hide()
        panel:SetFlyoutSize(WIDTH, 2 * INSET + TITLE_H + ROW_H + 4)
        AlignUnderTrigger()
        return
    end
    panel._empty:Hide()
    panel._scroll:Show()

    local colWidth = math.floor((WIDTH - 2 * INSET) / SPECS_PER_ROW)
    local y, specIndex, classIndex = 0, 0, 0

    for _, classEntry in ipairs(buckets) do
        classIndex = classIndex + 1
        local header = AcquireClassRow(content, classIndex)
        header:ClearAllPoints()
        header:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
        header:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -y)
        header._label:SetText(classEntry.name or "Unknown")

        local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classEntry.file]
        if color then
            header._label:SetTextColor(color.r, color.g, color.b, 1)
        else
            local ar, ag, ab = GetTheme():GetAccentColor()
            header._label:SetTextColor(ar, ag, ab, 1)
        end

        local allOn = true
        for _, spec in ipairs(classEntry.specs) do
            if not selected[spec.specID] then allOn = false break end
        end
        header._hint:SetText(allOn and "clear class" or "check class")
        header._hint:SetAlpha(0)
        header._onClick = function()
            for _, spec in ipairs(classEntry.specs) do
                if selected[spec.specID] == allOn and opts.toggle then
                    opts.toggle(spec.specID)
                end
            end
        end
        header:Show()
        y = y + HEADER_H

        local col = 0
        for _, spec in ipairs(classEntry.specs) do
            specIndex = specIndex + 1
            local specID = spec.specID
            local row = AcquireSpecRow(content, specIndex)
            row:ClearAllPoints()
            row:SetWidth(colWidth)
            row:SetPoint("TOPLEFT", content, "TOPLEFT", 8 + col * colWidth, -y)
            row._icon:SetTexture(spec.icon)
            row._name:SetText(spec.name or ("Spec " .. tostring(specID)))
            row._onClick = function()
                if opts.toggle then opts.toggle(specID) end
            end
            PaintRow(row, selected[specID] == true)
            row:Show()

            col = col + 1
            if col >= SPECS_PER_ROW then
                col = 0
                y = y + ROW_H
            end
        end
        if col > 0 then y = y + ROW_H end
        y = y + CLASS_GAP
    end

    content:SetHeight(math.max(1, y))
    local listH = math.min(MAX_LIST_H, y)
    panel._scroll:SetHeight(listH)
    panel:SetFlyoutSize(WIDTH, TITLE_H + listH + 2 * INSET + 4)
    if panel._scroll.UpdateThumb then panel._scroll.UpdateThumb() end
    AlignUnderTrigger()
end

local function Create(anchorBtn)
    local Controls = addon.UI and addon.UI.Controls
    if not Controls or not Controls.CreateFlyout then return nil end
    local theme = GetTheme()

    local p = Controls:CreateFlyout({
        anchor = anchorBtn,
        direction = "DOWN",
        width = WIDTH,
        height = 200,
        padding = PADDING,
        gap = GAP,
        name = "ScootAuraSpecFlyout",
        onShow = function()
            Rebuild()
        end,
    })
    if not p then return nil end
    panel = p

    local content = p:GetContent()
    local title = content:CreateFontString(nil, "OVERLAY")
    title:SetFont(theme:GetFont("LABEL"), 11, "")
    title:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
    title:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, 0)
    title:SetJustifyH("LEFT")
    title:SetHeight(TITLE_H)
    local ar, ag, ab = theme:GetAccentColor()
    title:SetTextColor(ar, ag, ab, 1)
    p._title = title

    -- Every class will not fit in a fly-out, so the list scrolls.
    local Picker = addon.UI and addon.UI.ScootAuraCDMPicker
    if not (Picker and Picker.CreateScrollRegion) then return nil end
    local scroll, list = Picker.CreateScrollRegion(content)
    scroll:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -TITLE_H)
    scroll:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -TITLE_H)
    scroll:SetHeight(160)
    p._scroll = scroll
    p._list = list

    local empty = content:CreateFontString(nil, "OVERLAY")
    empty:SetFont(theme:GetFont("LABEL"), 10, "")
    empty:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -TITLE_H)
    empty:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -TITLE_H)
    empty:SetJustifyH("LEFT")
    empty:SetText("Specializations are not loaded yet.")
    empty:SetTextColor(0.6, 0.6, 0.6, 1)
    empty:Hide()
    p._empty = empty

    return p
end

--------------------------------------------------------------------------------
-- Public
--------------------------------------------------------------------------------

--- Opens the fly-out on `anchorBtn` for one record. Clicking the same button
-- again closes it. opts: title, key (the record's identity, so the panel can
-- find its new trigger after a re-render), get() -> spec id array or nil,
-- toggle(specID).
function Flyout.OpenFor(anchorBtn, opts)
    if not anchorBtn then return end
    if not panel then
        if not Create(anchorBtn) then return end
    end
    if panel:IsOpen() and panel._anchor == anchorBtn then
        panel:Close()
        return
    end
    panel._opts = opts
    panel:SetAnchor(anchorBtn)
    if panel:IsOpen() then
        Rebuild()
    else
        panel:Open()
    end
end

--- Re-reads the record and repaints the rows in place, after a toggle.
function Flyout.Repaint()
    if panel and panel:IsOpen() then Rebuild() end
end

--- Runs after every spec toggle. Checking a spec moves the record between the
-- Loaded and Not Loaded lists, so the list re-renders here rather than on
-- close; the panel is handed its replacement trigger mid-render and follows
-- the record to wherever the rebuilt list put it.
function Flyout.ApplyEdit()
    local ui = addon.ScootAurasUI
    if ui and ui.RefreshList then ui.RefreshList() end
    Flyout.Repaint()
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
    AlignUnderTrigger()
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
-- hiding a hover-revealed spec button, so the trigger stays put under its
-- own panel once the mouse leaves the row.
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
