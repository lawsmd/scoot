-- GroupAnalysisPanel.lua - Group Analysis report panel (widget flyout child)
--
-- Persistent surface attached to the widget diamond through the flyout-child
-- chain, so it stacks along the configured direction and inherits the
-- widget's combat fade through frame parenting. The diamond sits on the
-- panel's near edge as its head, so the header block is pushed clear of it
-- (see addon.Widget:GetHeadInset).
--
-- Each player is a two-line cell: role icon in a gutter on the left, then a
-- class-colored name with the realm beside it for cross-realm members, full
-- spec name underneath, item level right-aligned. Cells whose data hasn't
-- arrived yet stay blank and fill in as the passive inspect service reports
-- updates.
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.Reports = addon.UI.Reports or {}
local Panel = {}
addon.UI.Reports.GroupAnalysisPanel = Panel

local GA -- resolved lazily; reports/core loads before this file, data file too

-- Party rows are roomy (5 max); raid rows are tight so 40 fit in two columns.
-- nameLine is the height of a cell's first line, i.e. how far below the name
-- the spec sits; rowHeight is that plus the spec line plus a gap to the next
-- cell. ilvlCol has to fit the "Item Level" header, not just three digits.
--
-- Widths are sized to the content, not padded out: the widest realistic first
-- line is a 12-character name (WoW's cap) plus a long realm at realmSize, and
-- the remainder is the ilvl column. Overlong realms clip, as everything here
-- does. titleSize/headerSize sit 25% above nameSize so the header block reads
-- as a distinct tier rather than as another row.
--
-- width/colWidth cover the text content only. The role icon gutter is added on
-- top of them at render time, so turning icons off returns the panel to exactly
-- these numbers and no width needs retuning when the icon size changes.
local METRICS = {
    party = { width = 250, rowHeight = 30, nameLine = 15,
              titleSize = 15, nameSize = 12, realmSize = 9, specSize = 10, headerSize = 11,
              ilvlCol = 60, roleIconSize = 16, columns = 1, rowsPerColumn = 40 },
    raid  = { colWidth = 195, rowHeight = 26, nameLine = 13,
              titleSize = 14, nameSize = 11, realmSize = 8, specSize = 9, headerSize = 10,
              ilvlCol = 56, roleIconSize = 14, columns = 2, rowsPerColumn = 20 },
}
METRICS.solo = METRICS.party

local TITLE_TOP_PAD = 6      -- panel top edge to title, before head clearance
local TITLE_HEIGHT = 20      -- title baseline to column headers
local COLHEADER_HEIGHT = 24  -- header text, its underline, and the gap to row 1
local UNDERLINE_GAP = 2
local UNDERLINE_HEIGHT = 1
local REALM_GAP = 4
local ROLE_ICON_GAP = 6      -- role icon to the player block beside it
local PADDING = 8
local COLUMN_GAP = 12
local BORDER = 1
local SPEC_GRAY = { 0.55, 0.55, 0.55, 0.9 }
local COLHEADER_GRAY = { 0.65, 0.65, 0.65, 1 }
local RENDER_DEBOUNCE = 0.2
local FALLBACK_BG_ALPHA = 0.98  -- only if the Reports opacity setting is unreachable

local frame = nil
local rows = {}
local colHeaders = nil
local flyoutHandle = nil
local renderQueued = false

-- Every report panel shares one user-selectable face (Reports > Config).
-- Do not reach for addon.GetDefaultFontFace here: despite the name it
-- resolves to GameFontNormal (Friz Quadrata), not a Scoot font.
local function getFont()
    local Reports = addon.Reports
    if Reports and Reports.GetFontFace then
        local face = Reports:GetFontFace()
        if face then return face end
    end
    local theme = addon.UI and addon.UI.Theme
    if theme and theme.GetFont then return theme:GetFont("PROPORTIONAL_MED") end
    return "Fonts\\FRIZQT__.TTF"
end

-- The Raid Manager set, shared with the group frames' role icon setting rather
-- than restated here — one place owns the atlas names. Returns nil if that
-- module's table is somehow missing, which renders as no icons rather than an
-- error.
local function getRoleAtlas(role)
    if not role then return nil end
    local sets = addon.BarsUtils and addon.BarsUtils.ROLE_ICON_ATLASES
    local gm = sets and sets.gm
    return gm and gm[role] or nil
end

-- SetFont fails silently (returns false, leaves the string unfonted) when the
-- file is missing or not yet loaded, and SetText on an unfonted FontString
-- errors outright with "Font not set". So walk the fallbacks and confirm with
-- GetFont that one actually took. Every SetFont in this file goes through
-- here, and no SetText runs before it.
local fontCandidates = {}  -- reused; a render touches this ~4x per row

local function addCandidate(path)
    if type(path) == "string" and path ~= "" then
        fontCandidates[#fontCandidates + 1] = path
    end
end

local function applyFont(fs, size, flags)
    local theme = addon.UI and addon.UI.Theme
    -- Built without nil holes on purpose: a hole would stop ipairs at the
    -- first gap and the later fallbacks would never be reached.
    wipe(fontCandidates)
    addCandidate(getFont())
    addCandidate(theme and theme.GetFont and theme:GetFont("PROPORTIONAL_MED"))
    addCandidate(select(1, _G.GameFontNormal:GetFont()))
    addCandidate("Fonts\\FRIZQT__.TTF")

    for _, path in ipairs(fontCandidates) do
        local ok, applied = pcall(fs.SetFont, fs, path, size, flags)
        if ok and applied ~= false then return true end
    end
    -- Nothing took this pass, but SetText is still safe if an earlier call
    -- left a font on the string.
    return fs:GetFont() ~= nil
end

-- Guarantees the font is in place first, so a fallback miss can never turn
-- into a hard error partway through a render.
local function setStyledText(fs, size, text)
    if not applyFont(fs, size, "OUTLINE") then return end
    fs:SetText(text or "")
end

--------------------------------------------------------------------------------
-- Frame
--------------------------------------------------------------------------------

-- Reports > Config owns one backdrop opacity for every surface the diamond
-- spawns. Only the fill moves: the border, the title and the row text stay
-- fully opaque, so a low value reads as "see through the panel" rather than
-- "the report is fading out". Cheap enough to re-apply on every render, and
-- called directly on the opacity message so a slider drag tracks live.
local function applyBackdrop()
    if not frame or not frame._bg or not frame._bgColor then return end
    local alpha = FALLBACK_BG_ALPHA
    local Reports = addon.Reports
    if Reports and Reports.GetBackdropAlpha then
        alpha = Reports:GetBackdropAlpha()
    end
    local c = frame._bgColor
    frame._bg:SetColorTexture(c[1], c[2], c[3], alpha)
end

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
    -- Color now, alpha per applyBackdrop: the opacity is a user setting and
    -- the panel outlives any one value of it.
    frame._bgColor = { bgR, bgG, bgB }
    frame._bg = bg
    applyBackdrop()

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

    -- Centered on the panel, under the diamond. Anchored per render so it
    -- tracks head clearance when the icon size or flyout direction changes.
    local title = frame:CreateFontString(nil, "OVERLAY")
    title:SetJustifyH("CENTER")
    title:SetWordWrap(false)
    title:SetTextColor(ar, ag, ab, 1)
    frame._title = title

    local close = CreateFrame("Button", nil, frame)
    close:SetSize(16, 16)
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)
    local closeText = close:CreateFontString(nil, "OVERLAY")
    closeText:SetPoint("CENTER")
    setStyledText(closeText, 12, "x")
    closeText:SetTextColor(0.7, 0.7, 0.7, 1)
    close._text = closeText
    close:SetScript("OnEnter", function(self) self._text:SetTextColor(1, 1, 1, 1) end)
    close:SetScript("OnLeave", function(self) self._text:SetTextColor(0.7, 0.7, 0.7, 1) end)
    close:SetScript("OnClick", function() Panel:Close() end)
    frame._close = close

    return frame
end

--------------------------------------------------------------------------------
-- Column headers
--------------------------------------------------------------------------------
-- One pair per layout column, so a two-column raid panel labels both halves.

local function acquireColumnHeader(index)
    colHeaders = colHeaders or {}
    local header = colHeaders[index]
    if not header then
        -- Text is set in render, never here: at creation time no font has
        -- been applied yet and SetText would error.
        header = {}
        header.player = frame:CreateFontString(nil, "OVERLAY")
        header.player:SetJustifyH("LEFT")
        header.player:SetWordWrap(false)
        -- Deliberately no SetWidth: both header strings auto-size to their
        -- text so the underlines can anchor to their own bounds instead of
        -- measuring with GetStringWidth, which under-reports before a string
        -- has been rendered once.
        header.ilvl = frame:CreateFontString(nil, "OVERLAY")
        header.ilvl:SetJustifyH("RIGHT")
        header.ilvl:SetWordWrap(false)
        header.playerRule = frame:CreateTexture(nil, "ARTWORK")
        header.ilvlRule = frame:CreateTexture(nil, "ARTWORK")
        colHeaders[index] = header
    end
    header.player:Show()
    header.ilvl:Show()
    header.playerRule:Show()
    header.ilvlRule:Show()
    return header
end

-- Underlines the header in place, spanning exactly the text it sits under.
local function underline(rule, fs)
    rule:ClearAllPoints()
    rule:SetPoint("TOPLEFT", fs, "BOTTOMLEFT", 0, -UNDERLINE_GAP)
    rule:SetPoint("TOPRIGHT", fs, "BOTTOMRIGHT", 0, -UNDERLINE_GAP)
    rule:SetHeight(UNDERLINE_HEIGHT)
    rule:SetColorTexture(unpack(COLHEADER_GRAY))
end

local function hideColumnHeadersFrom(index)
    if not colHeaders then return end
    for i = index, #colHeaders do
        colHeaders[i].player:Hide()
        colHeaders[i].ilvl:Hide()
        colHeaders[i].playerRule:Hide()
        colHeaders[i].ilvlRule:Hide()
    end
end

--------------------------------------------------------------------------------
-- Rows
--------------------------------------------------------------------------------

local function acquireRow(index)
    local row = rows[index]
    if not row then
        row = {}
        -- ARTWORK, matching the header underlines: above the panel background,
        -- below the OVERLAY text.
        row.roleIcon = frame:CreateTexture(nil, "ARTWORK")
        -- No fixed width: the name auto-sizes so the realm can sit right
        -- against it whatever the name's length.
        row.name = frame:CreateFontString(nil, "OVERLAY")
        row.name:SetJustifyH("LEFT")
        row.name:SetWordWrap(false)
        row.realm = frame:CreateFontString(nil, "OVERLAY")
        row.realm:SetJustifyH("LEFT")
        row.realm:SetWordWrap(false)
        row.spec = frame:CreateFontString(nil, "OVERLAY")
        row.spec:SetJustifyH("LEFT")
        row.spec:SetWordWrap(false)
        row.ilvl = frame:CreateFontString(nil, "OVERLAY")
        row.ilvl:SetJustifyH("RIGHT")
        row.ilvl:SetJustifyV("MIDDLE")
        row.ilvl:SetWordWrap(false)
        rows[index] = row
    end
    -- roleIcon is deliberately absent here: whether it shows depends on the
    -- entry's role and the visibility setting, so render decides per row.
    row.name:Show()
    row.realm:Show()
    row.spec:Show()
    row.ilvl:Show()
    return row
end

local function hideRowsFrom(index)
    for i = index, #rows do
        rows[i].roleIcon:Hide()
        rows[i].name:Hide()
        rows[i].realm:Hide()
        rows[i].spec:Hide()
        rows[i].ilvl:Hide()
    end
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

    applyBackdrop()

    local snapshot = GA.BuildSnapshot()
    local M = METRICS[snapshot.mode] or METRICS.party

    -- The diamond wears the panel's near edge; shift content clear of the
    -- half that intrudes and grow the panel by the same amount, so the usable
    -- content box is identical in all four flyout directions. TITLE_TOP_PAD is
    -- the smaller of the panel's two insets, so clearance is never short.
    local W = addon.Widget
    local padTop, padLeft, extraH, extraW = 0, 0, 0, 0
    if W and W.GetHeadInset then
        padTop, padLeft, extraH, extraW = W:GetHeadInset(W:GetFlyoutDirection(), TITLE_TOP_PAD)
    end

    -- The usable box is inset by padLeft on the left and (extraW - padLeft) on
    -- the right, so the centre of the content is not the centre of the frame.
    local centerShift = padLeft - extraW / 2

    -- colWidth is the text content width; roleCol is the gutter added to its
    -- left. "Hide All" collapses the gutter outright, so the panel returns to
    -- its pre-icon width; "Hide DPS Icons" keeps it and blanks those rows'
    -- slots, which is what keeps the name column straight.
    local vis = addon.Reports
        and addon.Reports:GetSetting("groupAnalysis", "roleIconVisibility", "showAll")
        or "showAll"
    local roleCol = (vis ~= "hideAll") and (M.roleIconSize + ROLE_ICON_GAP) or 0

    local colWidth = (M.columns > 1) and M.colWidth or (M.width - 2 * PADDING)
    local total = #snapshot.entries

    -- Header block: title centered on the panel, column labels beneath it.
    local titleY = -(TITLE_TOP_PAD + padTop)
    frame._title:ClearAllPoints()
    frame._title:SetPoint("TOP", frame, "TOP", centerShift, titleY)
    setStyledText(frame._title, M.titleSize, "Group Analysis")

    setStyledText(frame._close._text, 12, "x")

    -- One column spans the gutter plus the text; textX is where the player
    -- block starts, and the headers use it too so header and rows stay aligned
    -- whatever the gutter is doing.
    local columnWidth = roleCol + colWidth
    local function columnX(col)
        return PADDING + padLeft + (col - 1) * (columnWidth + COLUMN_GAP)
    end

    local colHeaderY = titleY - TITLE_HEIGHT
    for col = 1, M.columns do
        local header = acquireColumnHeader(col)
        local textX = columnX(col) + roleCol

        header.player:ClearAllPoints()
        header.player:SetPoint("TOPLEFT", frame, "TOPLEFT", textX, colHeaderY)
        setStyledText(header.player, M.headerSize, "Player")
        header.player:SetTextColor(unpack(COLHEADER_GRAY))
        underline(header.playerRule, header.player)

        -- Anchored by its right edge to the column's, matching the row ilvl
        -- box below it (which keeps a fixed width for vertical centering).
        header.ilvl:ClearAllPoints()
        header.ilvl:SetPoint("TOPRIGHT", frame, "TOPLEFT", textX + colWidth, colHeaderY)
        setStyledText(header.ilvl, M.headerSize, "Item Level")
        header.ilvl:SetTextColor(unpack(COLHEADER_GRAY))
        underline(header.ilvlRule, header.ilvl)
    end
    hideColumnHeadersFrom(M.columns + 1)

    local rowsTop = colHeaderY - COLHEADER_HEIGHT

    for i, entry in ipairs(snapshot.entries) do
        local row = acquireRow(i)
        local col = (M.columns > 1) and (i > M.rowsPerColumn and 2 or 1) or 1
        local rowIndex = (col == 2) and (i - M.rowsPerColumn) or i
        local x = columnX(col)
        local textX = x + roleCol
        local y = rowsTop - ((rowIndex - 1) * M.rowHeight)

        local r, g, b = 1, 1, 1
        if entry.classR then r, g, b = entry.classR, entry.classG, entry.classB end

        -- Centered inside the same rowHeight box the item level uses, so the
        -- two sit on one line across the two-line cell.
        local atlas = (roleCol > 0) and getRoleAtlas(entry.role) or nil
        if atlas and not (vis == "hideDPS" and entry.role == "DAMAGER") then
            row.roleIcon:ClearAllPoints()
            row.roleIcon:SetPoint("TOPLEFT", frame, "TOPLEFT", x,
                y - (M.rowHeight - M.roleIconSize) / 2)
            row.roleIcon:SetSize(M.roleIconSize, M.roleIconSize)
            row.roleIcon:SetAtlas(atlas)
            row.roleIcon:Show()
        else
            row.roleIcon:Hide()
        end

        row.name:ClearAllPoints()
        row.name:SetPoint("TOPLEFT", frame, "TOPLEFT", textX, y)
        setStyledText(row.name, M.nameSize, entry.name)
        row.name:SetTextColor(r, g, b, 1)

        -- Cross-realm only: same-realm members carry no realm in the snapshot.
        row.realm:ClearAllPoints()
        row.realm:SetPoint("BOTTOMLEFT", row.name, "BOTTOMRIGHT", REALM_GAP, 0)
        setStyledText(row.realm, M.realmSize, entry.realm)
        row.realm:SetTextColor(r, g, b, 1)

        row.spec:ClearAllPoints()
        row.spec:SetPoint("TOPLEFT", frame, "TOPLEFT", textX, y - M.nameLine)
        setStyledText(row.spec, M.specSize, entry.specName)
        row.spec:SetTextColor(unpack(SPEC_GRAY))

        -- Centered against the whole two-line cell rather than either line.
        row.ilvl:ClearAllPoints()
        row.ilvl:SetPoint("TOPLEFT", frame, "TOPLEFT", textX + colWidth - M.ilvlCol, y)
        row.ilvl:SetSize(M.ilvlCol, M.rowHeight)
        setStyledText(row.ilvl, M.nameSize, entry.itemLevel and tostring(entry.itemLevel) or "")
        row.ilvl:SetTextColor(1, 1, 1, 1)
    end
    hideRowsFrom(total + 1)

    local visibleRows = math.min(total, M.rowsPerColumn)
    -- Every column carries its own gutter, so the panel grows by one per column.
    local width = (M.columns > 1)
        and (2 * PADDING + M.columns * columnWidth + (M.columns - 1) * COLUMN_GAP)
        or (M.width + roleCol)
    local headerBlock = TITLE_TOP_PAD + padTop + TITLE_HEIGHT + COLHEADER_HEIGHT
    local height = headerBlock + (visibleRows * M.rowHeight) + PADDING
    frame:SetSize(width + extraW, height + extraH)
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
    addon:UnregisterMessage("SCOOT_REPORTS_FONT_CHANGED")
    addon:UnregisterMessage("SCOOT_REPORTS_OPACITY_CHANGED")
    addon:UnregisterMessage("SCOOT_REPORT_SETTING_CHANGED")
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
        -- The Config page promises font changes apply without a reload.
        addon:RegisterMessage("SCOOT_REPORTS_FONT_CHANGED", function()
            queueRender()
        end)
        -- Opacity re-colors one texture and moves nothing, so it skips the
        -- render debounce entirely and tracks a slider drag frame by frame.
        addon:RegisterMessage("SCOOT_REPORTS_OPACITY_CHANGED", function()
            applyBackdrop()
        end)
        -- Same promise for per-report settings. A full re-render is cheap
        -- enough that filtering by report id would only add a failure mode.
        addon:RegisterMessage("SCOOT_REPORT_SETTING_CHANGED", function()
            queueRender()
        end)
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
