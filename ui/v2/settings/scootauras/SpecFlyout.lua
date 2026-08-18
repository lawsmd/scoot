-- SpecFlyout.lua - "Restrict to Specs" fly-out on the Aura List page
--
-- The Rules spec picker boiled down to the player's own class: one checkbox
-- row per specialization, plus an "All Specializations" row that is checked
-- exactly when the record carries no restriction. One instance serves every
-- tracker row and group box; OpenFor re-targets it and re-reads its state.
-- Edits land immediately; the list re-renders once, after the fly-out closes,
-- because a re-render destroys the row the fly-out is anchored to.
local addonName, addon = ...

addon.UI = addon.UI or {}
local Flyout = {}
addon.UI.ScootAuraSpecFlyout = Flyout

local WIDTH = 214
local PADDING = 10
local INSET = PADDING + 1          -- Flyout content inset (padding + 1px border)
local GAP = 6                      -- trigger-to-panel spacing
local TITLE_H = 20
local ROW_H = 22
local CHECK_SIZE = 12
local ICON_SIZE = 14

local panel                        -- the one live fly-out

local function GetTheme() return addon.UI and addon.UI.Theme end
local function GetSAU() return addon.ScootAuras end

--------------------------------------------------------------------------------
-- Rows
--------------------------------------------------------------------------------

-- Row recipe from the Rules picker (RulesRenderer): a recolored solid square
-- for the check, the spec's own icon, and a name that goes dim when off.
local function AcquireRow(content, index)
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
    icon:SetPoint("LEFT", check, "RIGHT", 6, 0)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row._icon = icon

    local name = row:CreateFontString(nil, "OVERLAY")
    name:SetFont(theme:GetFont("VALUE"), 10, "")
    name:SetPoint("LEFT", icon, "RIGHT", 6, 0)
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
        panel._dirty = true
        PlaySound(self._on and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF
            or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        Flyout.Repaint()
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

--------------------------------------------------------------------------------
-- Build
--------------------------------------------------------------------------------

-- The control centers the panel under its trigger. These triggers sit at the
-- right edge of their row or box, so right-align instead and aim the nub at
-- the button (see CopyFromGlobal for the same correction). SetFlyoutSize
-- re-centers whenever it runs on an open panel, so this is always the last
-- word on placement.
local function AlignUnderTrigger()
    local anchor = panel._anchor
    if not anchor then return end
    panel:ClearAllPoints()
    panel:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -GAP)
    local aw = anchor:GetWidth() or 0
    panel:SetNubOffset(math.floor(WIDTH / 2 - aw / 2))
end

-- Rebuilt on every open: the spec list can be empty before the talent data
-- loads, and one stale empty build would strand the fly-out for the session.
local function Rebuild()
    local SAU = GetSAU()
    local opts = panel._opts
    if not (SAU and opts) then return end

    local content = panel:GetContent()
    for _, row in ipairs(panel._rows or {}) do row:Hide() end

    panel._title:SetText(opts.title or "Load in...")

    local Profiles = addon.Profiles
    local specs = {}
    if Profiles and Profiles.GetSpecOptions then
        local ok, list = pcall(Profiles.GetSpecOptions, Profiles)
        if ok and type(list) == "table" then specs = list end
    end

    local selected = {}
    local stored = opts.get and opts.get() or nil
    local restricted = type(stored) == "table" and #stored > 0
    for _, id in ipairs(stored or {}) do selected[id] = true end

    if #specs == 0 then
        panel._empty:Show()
        panel:SetFlyoutSize(WIDTH, 2 * INSET + TITLE_H + ROW_H + 4)
        AlignUnderTrigger()
        return
    end
    panel._empty:Hide()

    local y = TITLE_H
    local index = 0

    index = index + 1
    local allRow = AcquireRow(content, index)
    allRow:ClearAllPoints()
    allRow:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
    allRow:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -y)
    allRow._icon:SetTexture(nil)
    allRow._name:SetText("All Specializations")
    allRow._onClick = function()
        -- Already the state: clicking it again would be a no-op write.
        if not restricted then return false end
        if opts.clear then opts.clear() end
    end
    PaintRow(allRow, not restricted)
    allRow:Show()
    y = y + ROW_H

    for _, spec in ipairs(specs) do
        index = index + 1
        local specID = spec.specID
        local row = AcquireRow(content, index)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
        row:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -y)
        row._icon:SetTexture(spec.icon)
        row._name:SetText(spec.name or ("Spec " .. tostring(specID)))
        row._onClick = function()
            if opts.toggle then opts.toggle(specID) end
        end
        PaintRow(row, selected[specID] == true)
        row:Show()
        y = y + ROW_H
    end

    panel:SetFlyoutSize(WIDTH, y + 2 * INSET + 4)
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
        height = 120,
        padding = PADDING,
        gap = GAP,
        name = "ScootAuraSpecFlyout",
        onShow = function()
            Rebuild()
        end,
        onHide = function()
            -- Deferred: a re-render destroys the row this fly-out is anchored
            -- to, and Cleanup closes the fly-out, so refreshing inline would
            -- re-enter the renderer from inside its own teardown.
            if not panel._dirty then return end
            panel._dirty = false
            C_Timer.After(0, function()
                local ui = addon.ScootAurasUI
                if ui and ui.RefreshList then ui.RefreshList() end
            end)
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
-- again closes it. opts: title, get() -> spec id array or nil, toggle(specID),
-- clear().
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

function Flyout.Close()
    if panel and panel.Close then panel:Close() end
end
