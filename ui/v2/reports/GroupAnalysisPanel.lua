-- GroupAnalysisPanel.lua - Group Analysis report panel (widget flyout child)
--
-- Persistent surface attached to the widget diamond through the flyout-child
-- chain, so it stacks along the configured direction and inherits the
-- widget's combat fade through frame parenting. The diamond sits on the
-- panel's near edge as its head, so the header block is pushed clear of it
-- (see addon.Widget:GetHeadInset).
--
-- Each player is a two-line cell: role icon in a gutter on the left, then a
-- class-colored name with the realm in parentheses beside it for cross-realm
-- members (same color, smaller, vertically centered on the name), full
-- spec name underneath, item level right-aligned on the name line. Cells
-- whose data hasn't arrived yet stay blank and fill in as the passive inspect
-- service reports updates; the title animates as "Group Analysis..." for as
-- long as that service still has members it can reach (see Loading dots).
--
-- Raids run two columns, split by a faint vertical rule, with a "Sort By"
-- footer that cycles between item-level order (descending, left column
-- first) and by-group blocks in the raid roster overlay's book order (see
-- Display lists).
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
-- Widths are sized to the content, not padded out — and to *observed* long
-- name + parenthesized-realm pairs, not the theoretical 12-char-name-plus-
-- longest-realm worst case, which in practice never fills and left the two
-- columns visibly adrift. The rare over-budget pair clips, as everything here
-- does. titleSize/headerSize sit 25% above nameSize so the
-- header block reads as a distinct tier rather than as another row. realmSize
-- runs well under specSize on purpose: the parenthesized realm is an
-- annotation on the name, not a second word competing with it.
--
-- width/colWidth cover the text content only. The role icon gutter is added on
-- top of them at render time — once per column on the left, and mirrored once
-- on the panel's right edge so the layout reads symmetric with icons on — so
-- turning icons off returns the panel to exactly these numbers and no width
-- needs retuning when the icon size changes.
local METRICS = {
    party = { width = 175, rowHeight = 30, nameLine = 15,
              titleSize = 15, nameSize = 12, realmSize = 6.75, specSize = 7.5, headerSize = 11,
              ilvlCol = 60, roleIconSize = 16, columns = 1, rowsPerColumn = 40 },
    raid  = { colWidth = 150, rowHeight = 26, nameLine = 13,
              titleSize = 14, nameSize = 11, realmSize = 6, specSize = 6.75, headerSize = 10,
              ilvlCol = 56, roleIconSize = 14, columns = 2, rowsPerColumn = 20 },
}
METRICS.solo = METRICS.party

local TITLE_TOP_PAD = 6      -- panel top edge to title, before head clearance
local TITLE_HEIGHT = 20      -- title baseline to column headers
local COLHEADER_HEIGHT = 24  -- header text, its underline, and the gap to row 1
local UNDERLINE_GAP = 2
local UNDERLINE_HEIGHT = 1
local REALM_GAP = 4
local SPEC_INDENT = 6        -- spec line's hang under the name it belongs to
local ROLE_ICON_GAP = 6      -- role icon to the player block beside it
local PADDING = 8
local COLUMN_GAP = 12
local BORDER = 1
local SPEC_GRAY = { 0.55, 0.55, 0.55, 0.9 }
local COLHEADER_GRAY = { 0.65, 0.65, 0.65, 1 }
local GROUP_HEADER_GOLD = { 1, 0.82, 0, 1 }  -- the raid roster overlay's header color
local DIVIDER_GRAY = { 0.6, 0.6, 0.6, 0.15 }
local GROUP_HEADER_PAD = 4  -- under a "Group N" line, before its first member
local GROUP_BLOCK_GAP = 4   -- extra air above a header that follows another block
local FOOTER_HEIGHT = 18
local FOOTER_GAP = 4
local RENDER_DEBOUNCE = 0.2
-- Three frames, not four: an empty frame would leave the title bare for a beat
-- every cycle, which reads as "done" and then contradicts itself.
local DOTS_FRAMES = { ".", "..", "..." }  -- title suffix cycled while cells are still filling
local DOTS_PERIOD = 0.35                  -- seconds per frame; a full cycle reads as one breath
local FALLBACK_BG_ALPHA = 0.98  -- only if the Reports opacity setting is unreachable

local frame = nil
local rows = {}
local colHeaders = nil
local groupHeaders = {}
local flyoutHandle = nil
local renderQueued = false
local render  -- forward: the footer's click handler re-renders immediately

local dotsTicker = nil     -- non-nil IS the "dots are showing" flag; no parallel boolean
local dotsPhase = 1
local dotsMissing = 0      -- last count render took, so the ticker can re-decide without a snapshot
local dotsSettled = false  -- a sweep drained with cells still blank: they are not coming

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

-- The dots ticker writes here between renders, with no face or size in hand:
-- render has already fonted the string, but applyFont can come up empty, so
-- confirm rather than assume. This is the only SetText in the file that
-- doesn't go through setStyledText, and this check is why it's safe.
local function setDotsText(text)
    local fs = frame and frame._titleDots
    if not fs or not fs:GetFont() then return end
    fs:SetText(text)
end

--------------------------------------------------------------------------------
-- Sort setting
--------------------------------------------------------------------------------

-- Zero-Touch: "ilvl" is the default, stored as absence. Anything unexpected
-- folds to it so a stale stored value can't wedge the layout.
local function getSortBy()
    local v = addon.Reports
        and addon.Reports:GetSetting("groupAnalysis", "sortBy", "ilvl")
        or "ilvl"
    if v ~= "group" then v = "ilvl" end
    return v
end

-- The value rides in the string as a color escape so one centered FontString
-- carries both the gray label and the brighter value; hover repaints the
-- value white without moving anything.
local function sortFooterText(sortBy, hover)
    local value = (sortBy == "group") and "Group" or "Item Level"
    local color = hover and "ffffffff" or "ffe8e8e8"
    return "Sort By: |c" .. color .. value .. "|r"
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

    -- The loading dots are a second string rather than a longer title. The
    -- title is centered with no fixed width, so it auto-sizes: growing its own
    -- text would re-center it and shove "Group Analysis" sideways every frame.
    -- Hanging the dots off its right edge instead leaves the title's position
    -- byte-identical whether loading or not, and nothing moves when the dots
    -- go away. Anchored once, here: the point references the title object, so
    -- render's ClearAllPoints on the title carries the dots along for free.
    -- No text yet — no font has been applied and SetText would error.
    local titleDots = frame:CreateFontString(nil, "OVERLAY")
    titleDots:SetJustifyH("LEFT")
    titleDots:SetWordWrap(false)
    titleDots:SetTextColor(ar, ag, ab, 1)
    titleDots:SetPoint("LEFT", title, "RIGHT", 0, 0)
    frame._titleDots = titleDots

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

    -- Faint rule splitting a two-column raid layout, centered in the column
    -- gap. Render positions it and decides visibility; party and solo (and a
    -- raid small enough for one column) never show it.
    local divider = frame:CreateTexture(nil, "ARTWORK")
    divider:SetWidth(1)
    divider:SetColorTexture(unpack(DIVIDER_GRAY))
    divider:Hide()
    frame._divider = divider

    -- "Sort By" footer, raid only. Clicking cycles the two modes rather than
    -- opening a menu — with exactly two options a flip is faster than a pick.
    -- No text yet: no font has been applied and SetText would error, so the
    -- hover scripts carry the same GetFont guard as setDotsText.
    local footer = CreateFrame("Button", nil, frame)
    footer:SetHeight(FOOTER_HEIGHT)
    local footerText = footer:CreateFontString(nil, "OVERLAY")
    footerText:SetPoint("CENTER")
    footerText:SetJustifyH("CENTER")
    footerText:SetWordWrap(false)
    footerText:SetTextColor(unpack(COLHEADER_GRAY))
    footer._text = footerText
    footer:SetScript("OnClick", function()
        -- Storing nil for the default keeps Zero-Touch intact. The setting
        -- message's re-render is debounced, so render directly: a click that
        -- takes 0.2s to land reads as a miss.
        local nextVal = (getSortBy() == "ilvl") and "group" or nil
        if addon.Reports then
            addon.Reports:SetSetting("groupAnalysis", "sortBy", nextVal)
        end
        if render then render() end
    end)
    footer:SetScript("OnEnter", function(self)
        if self._text:GetFont() then
            self._text:SetText(sortFooterText(getSortBy(), true))
        end
    end)
    footer:SetScript("OnLeave", function(self)
        if self._text:GetFont() then
            self._text:SetText(sortFooterText(getSortBy(), false))
        end
    end)
    footer:Hide()
    frame._sortFooter = footer

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
-- Group headers
--------------------------------------------------------------------------------
-- "Group N" / "Other" lines, by-group sort only. Pooled flat like the rows;
-- render assigns labels in placement order.

local function acquireGroupHeader(index)
    local gh = groupHeaders[index]
    if not gh then
        -- Text is set in render, never here: at creation time no font has
        -- been applied yet and SetText would error.
        gh = frame:CreateFontString(nil, "OVERLAY")
        gh:SetJustifyH("LEFT")
        gh:SetWordWrap(false)
        groupHeaders[index] = gh
    end
    gh:Show()
    return gh
end

local function hideGroupHeadersFrom(index)
    for i = index, #groupHeaders do
        groupHeaders[i]:Hide()
    end
end

--------------------------------------------------------------------------------
-- Loading dots
--------------------------------------------------------------------------------
-- The title animates while cells are still filling in. The hard half is
-- stopping: the inspect service has no completion event, un-inspectable
-- members never populate, and its 300s TTL re-queues everyone, so "spin while
-- any cell is blank" would never end. The stop condition is the service's own
-- queue draining (Inspect:HasPendingWork), which is exact — no wall-clock
-- timeout, which would misfire on the service's legitimate quiet windows and
-- break outright across a loading screen.
--------------------------------------------------------------------------------

local updateDots  -- forward: tickDots re-decides through it, and it starts tickDots

local function stopDots()
    if dotsTicker then
        dotsTicker:Cancel()
        dotsTicker = nil
    end
    setDotsText("")
end

-- Fails quiet like getRoleAtlas: a load-order change degrades to "no dots"
-- rather than an error.
local function inspectHasPendingWork()
    local I = addon.Inspect
    return (I and I.HasPendingWork and I:HasPendingWork()) or false
end

-- Only the two fields the inspect service actually delivers, and only for the
-- members it can reach. Everything excluded here has a legitimate permanent
-- nil that would otherwise pin the dots on forever: name comes back nil under
-- identity secrecy in exactly the instanced content this panel gets opened in
-- (while spec/ilvl still arrive, being static data); realm is nil same-realm
-- and role nil when unassigned; and the local player's spec/ilvl come from
-- GetSpecialization/GetAverageItemLevel with no loader behind them and no
-- event subscribed that would ever re-render them.
--
-- type() screens first because it is safe on secrets and on nil.
local function countMissing(entries)
    local n = 0
    for _, entry in ipairs(entries) do
        if not entry.isPlayer then
            if type(entry.specName) ~= "string" then n = n + 1 end
            if type(entry.itemLevel) ~= "number" then n = n + 1 end
        end
    end
    return n
end

local function tickDots()
    if not frame or not frame:IsShown() then
        stopDots()
        return
    end
    -- Polled rather than purely event-driven, and this is why: when the last
    -- queued member times out, the service clears it inside its own ticker and
    -- sends no message at all, so nothing would ever queue the render that
    -- stops us.
    updateDots(dotsMissing)
    if not dotsTicker then return end
    dotsPhase = dotsPhase % #DOTS_FRAMES + 1
    setDotsText(DOTS_FRAMES[dotsPhase])
end

-- The only place the dots start or stop. Called from render with a fresh count
-- and from the ticker with the last one.
function updateDots(missing)
    dotsMissing = missing
    local pending = inspectHasPendingWork()

    if missing == 0 then
        dotsSettled = false          -- everyone's in; a future sweep may dot again
    elseif dotsTicker and not pending then
        dotsSettled = true           -- watched a live sweep drain with cells still blank
    end
    -- The dotsTicker guard makes that latch an observed transition rather than
    -- a snapshot, which matters after combat: the render 0.2s behind
    -- PLAYER_REGEN_ENABLED sees no pending work because the service doesn't
    -- restart for another 2s, and latching there would kill the dots for the
    -- rest of the session. Cleared on roster and regen (see OpenOrRefresh) but
    -- deliberately NOT by the TTL requeue — otherwise a panel left open with an
    -- unreachable member animates in bursts every 5 minutes.

    local loading = missing > 0 and pending and not dotsSettled
    if loading and not dotsTicker then
        dotsPhase = 1
        dotsTicker = C_Timer.NewTicker(DOTS_PERIOD, tickDots)
    elseif not loading and dotsTicker then
        stopDots()
    end
end

--------------------------------------------------------------------------------
-- Display lists
--------------------------------------------------------------------------------
-- Render consumes one shape whatever the mode: per-column lists of
-- { entry = e } and { header = "Group N" } items. The sorting and grouping
-- happen here so the placement loop stays a dumb cursor walk.
--------------------------------------------------------------------------------

-- Secret-safe sort key: only a confirmed plain number participates. Anything
-- else (still-loading nil, or a secret) keys to -1, which sinks it below every
-- real item level while the roster-order tiebreak keeps that tail stable.
local function sortableIlvl(entry)
    local v = entry.itemLevel
    if type(v) == "number" and not (issecretvalue and issecretvalue(v)) then
        return v
    end
    return -1
end

-- Header lines are shorter than player cells, so column balance is measured
-- in pixels, not line counts. Mirrors the placement loop's cursor steps; used
-- only to pick the shorter column for the "Other" block, so a drift costs a
-- slightly lopsided panel, not a misrender.
local function columnPixelHeight(list, M)
    local h = 0
    for i, item in ipairs(list) do
        if item.header then
            if i > 1 then h = h + GROUP_BLOCK_GAP end
            h = h + M.nameLine + GROUP_HEADER_PAD
        else
            h = h + M.rowHeight
        end
    end
    return h
end

local function appendBlock(col, label, entries)
    col[#col + 1] = { header = label }
    for _, e in ipairs(entries) do
        col[#col + 1] = { entry = e }
    end
end

local function buildColumns(snapshot, M, sortBy)
    local entries = snapshot.entries

    -- Party/solo: one roster-order column, no headers, no sorting.
    if M.columns == 1 then
        local col = {}
        for _, e in ipairs(entries) do
            col[#col + 1] = { entry = e }
        end
        return { col }
    end

    if sortBy == "group" then
        -- Book order, matching the raid roster overlay: odd groups stack down
        -- the left column, even down the right, so the pairs read 1|2, 3|4 on
        -- down. subgroup is a guarded read (see groupanalysis.lua), so nil is
        -- expected rather than exceptional: those players land in a trailing
        -- "Other" block on the shorter column instead of being dropped.
        local groups = {}
        local other = {}
        for _, e in ipairs(entries) do
            local g = e.subgroup
            if type(g) == "number" and g >= 1 and g <= 8 then
                groups[g] = groups[g] or {}
                table.insert(groups[g], e)
            else
                table.insert(other, e)
            end
        end

        if next(groups) then
            local left, right = {}, {}
            for g = 1, 8 do
                if groups[g] then
                    appendBlock((g % 2 == 1) and left or right, "Group " .. g, groups[g])
                end
            end
            if #other > 0 then
                local target = columnPixelHeight(left, M) <= columnPixelHeight(right, M)
                    and left or right
                appendBlock(target, "Other", other)
            end
            return { left, right }
        end
        -- No subgroup was readable at all: fall through to the flat split in
        -- roster order — the same degradation the roster overlay uses when no
        -- per-group frames exist to read from.
    end

    local list = entries
    if sortBy == "ilvl" then
        -- Copy before sorting; the snapshot's roster order is the tiebreak,
        -- held in a side table rather than stamped onto the entries.
        list = {}
        local rosterIndex = {}
        for i, e in ipairs(entries) do
            list[i] = e
            rosterIndex[e] = i
        end
        table.sort(list, function(a, b)
            local ia, ib = sortableIlvl(a), sortableIlvl(b)
            if ia ~= ib then return ia > ib end
            return rosterIndex[a] < rosterIndex[b]
        end)
    end

    -- Flat split: fill the left column to its cap, truncate to the right.
    local left, right = {}, {}
    for i, e in ipairs(list) do
        local col = (i > M.rowsPerColumn) and right or left
        col[#col + 1] = { entry = e }
    end
    return { left, right }
end

--------------------------------------------------------------------------------
-- Render
--------------------------------------------------------------------------------

function render()
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
    -- The sort only means anything across two columns; party and solo always
    -- read in roster order whatever the stored setting says.
    local sortBy = (snapshot.mode == "raid") and getSortBy() or "ilvl"

    -- Header block: title centered on the panel, column labels beneath it.
    local titleY = -(TITLE_TOP_PAD + padTop)
    frame._title:ClearAllPoints()
    frame._title:SetPoint("TOP", frame, "TOP", centerShift, titleY)

    -- Decide first, then paint, so the paint reflects the decision. Render owns
    -- the dots' font and size; the ticker owns only the phase and its SetText.
    -- Painting the *current* phase rather than blanking is what keeps a render
    -- from dropping an animation frame — inspect updates land every few
    -- seconds, which is to say constantly while the dots are running.
    updateDots(countMissing(snapshot.entries))
    setStyledText(frame._title, M.titleSize, "Group Analysis")
    setStyledText(frame._titleDots, M.titleSize, dotsTicker and DOTS_FRAMES[dotsPhase] or "")

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

    local cols = buildColumns(snapshot, M, sortBy)
    local rowIndex = 0
    local headerIndex = 0
    local maxColHeight = 0

    for c, list in ipairs(cols) do
        local x = columnX(c)
        local textX = x + roleCol
        local y = rowsTop

        for li, item in ipairs(list) do
            if item.header then
                -- Air above a block that follows another; the first block
                -- sits flush under the column headers like a plain row does.
                if li > 1 then y = y - GROUP_BLOCK_GAP end
                headerIndex = headerIndex + 1
                local gh = acquireGroupHeader(headerIndex)
                gh:ClearAllPoints()
                gh:SetPoint("TOPLEFT", frame, "TOPLEFT", textX, y)
                setStyledText(gh, M.headerSize, item.header)
                gh:SetTextColor(unpack(GROUP_HEADER_GOLD))
                y = y - (M.nameLine + GROUP_HEADER_PAD)
            else
                local entry = item.entry
                rowIndex = rowIndex + 1
                local row = acquireRow(rowIndex)

                local r, g, b = 1, 1, 1
                if entry.classR then r, g, b = entry.classR, entry.classG, entry.classB end

                -- Centered on the name line, like the item level: the name is
                -- the cell's anchor line, and everything on it reads level.
                local atlas = (roleCol > 0) and getRoleAtlas(entry.role) or nil
                if atlas and not (vis == "hideDPS" and entry.role == "DAMAGER") then
                    row.roleIcon:ClearAllPoints()
                    row.roleIcon:SetPoint("TOPLEFT", frame, "TOPLEFT", x,
                        y - (M.nameLine - M.roleIconSize) / 2)
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

                -- Cross-realm only: same-realm members carry no realm in the
                -- snapshot. The parentheses live inside the same FontString as
                -- the realm, so they take the class color with it rather than
                -- reading as punctuation the panel owns. LEFT-to-RIGHT centers
                -- the realm's box on the name's across the two sizes;
                -- bottom-aligning them instead hangs the smaller string off
                -- the baseline and reads as a subscript.
                row.realm:ClearAllPoints()
                row.realm:SetPoint("LEFT", row.name, "RIGHT", REALM_GAP, 0)
                setStyledText(row.realm, M.realmSize, entry.realm and ("(" .. entry.realm .. ")") or "")
                row.realm:SetTextColor(r, g, b, 1)

                -- Indented off the name's left edge rather than flush with
                -- it: the offset is what makes the second line read as
                -- belonging to the name above it instead of as a column of
                -- its own.
                row.spec:ClearAllPoints()
                row.spec:SetPoint("TOPLEFT", frame, "TOPLEFT", textX + SPEC_INDENT, y - M.nameLine)
                setStyledText(row.spec, M.specSize, entry.specName)
                row.spec:SetTextColor(unpack(SPEC_GRAY))

                -- On the name line, not centered across the two-line cell:
                -- the number belongs to the player, and the name line is
                -- where the player is.
                row.ilvl:ClearAllPoints()
                row.ilvl:SetPoint("TOPLEFT", frame, "TOPLEFT", textX + colWidth - M.ilvlCol, y)
                row.ilvl:SetSize(M.ilvlCol, M.nameLine)
                setStyledText(row.ilvl, M.nameSize, entry.itemLevel and tostring(entry.itemLevel) or "")
                row.ilvl:SetTextColor(1, 1, 1, 1)

                y = y - M.rowHeight
            end
        end

        local used = rowsTop - y
        if used > maxColHeight then maxColHeight = used end
    end
    hideRowsFrom(rowIndex + 1)
    hideGroupHeadersFrom(headerIndex + 1)

    -- Every column carries its own gutter, so the panel grows by one per
    -- column — plus one more on the right edge, mirroring the leftmost gutter,
    -- so the ilvl column gets the same breathing room the icons give the names
    -- and the text block stays centered. Both derive from roleCol, so "Hide
    -- All" collapses the two sides together.
    local width = (M.columns > 1)
        and (2 * PADDING + M.columns * columnWidth + (M.columns - 1) * COLUMN_GAP + roleCol)
        or (M.width + 2 * roleCol)

    -- The divider spans the header line and the rows, and only earns its
    -- place once the second column actually holds something.
    local divider = frame._divider
    if divider then
        if M.columns > 1 and cols[2] and #cols[2] > 0 then
            divider:ClearAllPoints()
            divider:SetPoint("TOPLEFT", frame, "TOPLEFT",
                columnX(2) - COLUMN_GAP / 2 - 0.5, colHeaderY)
            divider:SetHeight(COLHEADER_HEIGHT + maxColHeight)
            divider:Show()
        else
            divider:Hide()
        end
    end

    -- The footer spans the content box so the click target is generous; its
    -- text centers itself on that box, which is where the title centers too.
    local footer = frame._sortFooter
    local footerH = 0
    if footer then
        if snapshot.mode == "raid" then
            footerH = FOOTER_GAP + FOOTER_HEIGHT
            footer:ClearAllPoints()
            footer:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING + padLeft,
                rowsTop - maxColHeight - FOOTER_GAP)
            footer:SetSize(width - 2 * PADDING, FOOTER_HEIGHT)
            -- IsMouseOver keeps the hover paint honest when a background
            -- re-render lands while the cursor is parked on the control.
            setStyledText(footer._text, M.headerSize,
                sortFooterText(sortBy, footer:IsMouseOver()))
            footer:Show()
        else
            footer:Hide()
        end
    end

    local headerBlock = TITLE_TOP_PAD + padTop + TITLE_HEIGHT + COLHEADER_HEIGHT
    local height = headerBlock + maxColHeight + footerH + PADDING
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
    -- First, ahead of anything that can throw: the widget invokes this under a
    -- pcall, so a failure below would be swallowed along with every remaining
    -- line — orphaning a ticker that holds a closure over a hidden frame until
    -- the next reload.
    stopDots()
    dotsSettled = false
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
            GA.Subscribe(function(event)
                -- Both mean there is genuinely new work for the scan, so a
                -- previous give-up no longer applies: new members to reach, or
                -- a sweep that combat cut short mid-flight.
                if event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_REGEN_ENABLED" then
                    dotsSettled = false
                end
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
